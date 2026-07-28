import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension principal class.
///
/// Minimal capture-and-handoff: stages the shared attachment(s) into the
/// App-Group container, writes a single `incomingShare` record (text and/or
/// staged file paths), then redirects to the host app via the `koherashare://`
/// URL scheme. The host app wakes, reads the record, and performs the real
/// Matrix send (with room selection) in-app, where the SDK + E2EE keys live.
/// The Matrix SDK never runs in the extension.
final class ShareViewController: SLComposeServiceViewController {
  private let appGroup = "group.io.github.quantumheart.kohera"
  private let stagingQueue = DispatchQueue(label: "kohera.share.staging")

  // ── Lifecycle ───────────────────────────────────────────────

  override func presentationAnimationDidFinish() {
    super.presentationAnimationDidFinish()
    placeholder = "Add a caption (optional)…"
  }

  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    stageAndRedirect()
  }

  // ── Stage + hand off ─────────────────────────────────────────

  private func stageAndRedirect() {
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let group = DispatchGroup()
    var textParts: [String] = []
    var files: [[String: Any]] = []

    let typed = contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !typed.isEmpty { textParts.append(typed) }

    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        // Text/URL attachments fold into the message body, not staged as files.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { raw, _ in
            let s = (raw as? URL)?.absoluteString ?? (raw as? String)
            if let s = s, !s.isEmpty { self.stagingQueue.sync { textParts.append(s) } }
            group.leave()
          }
          continue
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { raw, _ in
            let s = (raw as? String) ?? (raw as? URL)?.absoluteString
            if let s = s, !s.isEmpty { self.stagingQueue.sync { textParts.append(s) } }
            group.leave()
          }
          continue
        }
        // Image/video/file attachments stage into the App-Group container.
        group.enter()
        stageFile(provider: provider) { entry in
          self.stagingQueue.sync { if let entry = entry { files.append(entry) } }
          group.leave()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      self.writeIncomingShare(text: textParts.joined(separator: "\n"), files: files)
      self.redirectToHostApp()
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func stageFile(
    provider: NSItemProvider,
    done: @escaping ([String: Any]?) -> Void
  ) {
    let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] tempURL, error in
      guard let self, let tempURL = tempURL, error == nil else { done(nil); return }
      self.copyIntoAppGroup(tempURL: tempURL, provider: provider, done: done)
    }
  }

  private func copyIntoAppGroup(
    tempURL: URL,
    provider: NSItemProvider,
    done: @escaping ([String: Any]?) -> Void
  ) {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    ) else { done(nil); return }

    let dir = container.appendingPathComponent("share_in", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let originalName = provider.suggestedName ?? tempURL.lastPathComponent
    let stagedName = "\(UUID().uuidString)_\(originalName)"
    let dest = dir.appendingPathComponent(stagedName)

    let coordinator = NSFileCoordinator()
    coordinator.coordinate(readingItemAt: tempURL, options: [.withoutChanges], error: nil) { src in
      do {
        try FileManager.default.copyItem(at: src, to: dest)
        let mime = self.mime(for: tempURL, provider: provider)
        done([
          "filePath": dest.path,
          "mimeType": mime,
          "name": originalName,
        ])
      } catch {
        NSLog("[Kohera] Share staging copy failed: \(error)")
        done(nil)
      }
    }
  }

  private func mime(for url: URL, provider: NSItemProvider) -> String {
    if let type = UTType(filenameExtension: url.pathExtension),
       let mime = type.preferredMIMEType {
      return mime
    }
    if let id = provider.registeredTypeIdentifiers.first,
       let type = UTType(id), let mime = type.preferredMIMEType {
      return mime
    }
    return "application/octet-stream"
  }

  private func writeIncomingShare(text: String, files: [[String: Any]]) {
    guard let suite = UserDefaults(suiteName: appGroup) else { return }
    var record: [String: Any] = [:]
    if !text.isEmpty { record["text"] = text }
    if !files.isEmpty { record["files"] = files }
    guard !record.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: record),
          let raw = String(data: data, encoding: .utf8) else { return }
    suite.set(raw, forKey: "incomingShare")
  }

  /// Brings the main app to the foreground so it can read + send the share.
  /// On iOS 18+ the legacy `openURL:` selector is swallowed, so use
  /// `UIApplication.open(_:options:completionHandler:)`; keep the legacy
  /// selector for older iOS (the receive_sharing_intent technique).
  private func redirectToHostApp() {
    guard let url = URL(string: "koherashare://share") else { return }
    var responder: UIResponder? = self
    if #available(iOS 18.0, *) {
      NSLog("[Kohera] Share: redirect iOS 18+ branch")
      var foundApp = false
      while responder != nil {
        if let application = responder as? UIApplication {
          foundApp = true
          NSLog("[Kohera] Share: calling UIApplication.open")
          application.open(url, options: [:]) { success in
            NSLog("[Kohera] Share: UIApplication.open completion success=\(success)")
          }
        }
        responder = responder?.next
      }
      NSLog("[Kohera] Share: found UIApplication=\(foundApp)")
    } else {
      NSLog("[Kohera] Share: redirect legacy openURL branch")
      let selectorOpenURL = sel_registerName("openURL:")
      while responder != nil {
        if responder?.responds(to: selectorOpenURL) == true {
          NSLog("[Kohera] Share: legacy openURL responder=\(String(describing: responder))")
          _ = responder?.perform(selectorOpenURL, with: url)
        }
        responder = responder?.next
      }
    }
  }
}