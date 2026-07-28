import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension principal class.
///
/// Room picker only: tapping a room stages the shared content into the
/// App-Group container, writes a single `incomingShare` record
/// `{roomId, text, files}`, and redirects to the host app via the
/// `koherashare://` URL scheme. Kohera wakes, sends to that room (Matrix SDK
/// + E2EE keys live in the main app), and navigates to it. No compose sheet,
/// no caption, no queue. Rooms + avatars come from the App-Group
/// `roomSnapshot` the main app writes on sync.
final class ShareViewController: UINavigationController {

  let appGroup = "group.io.github.quantumheart.kohera"

  // Serializes concurrent NSItemProvider callbacks appending to staged.
  let stagingQueue = DispatchQueue(label: "kohera.share.staging")

  struct RoomPick {
    let roomId: String
    let displayname: String
    let avatarMxc: String?
    let avatarPath: String?
  }

  // ── Lifecycle ───────────────────────────────────────────────

  override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = CGSize(
      width: UIScreen.main.bounds.width,
      height: UIScreen.main.bounds.height
    )

    let picker = RoomPickerController(appGroup: appGroup)
    picker.onSelect = { [weak self] room in
      self?.stageAndHandoff(room: room)
    }
    picker.onCancel = { [weak self] in
      self?.cancelExtension()
    }
    setViewControllers([picker], animated: false)
  }

  func cancelExtension() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  // ── Stage + hand off ─────────────────────────────────────────

  private func stageAndHandoff(room: RoomPick) {
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let group = DispatchGroup()
    var textParts: [String] = []
    var files: [[String: Any]] = []

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
      self.writeIncomingShare(roomId: room.roomId, text: textParts.joined(separator: "\n"), files: files)
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
          "name": originalName,
          "mimeType": mime,
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

  private func writeIncomingShare(roomId: String, text: String, files: [[String: Any]]) {
    guard let suite = UserDefaults(suiteName: appGroup) else { return }
    var record: [String: Any] = ["roomId": roomId]
    if !text.isEmpty { record["text"] = text }
    if !files.isEmpty { record["files"] = files }
    guard let data = try? JSONSerialization.data(withJSONObject: record),
          let raw = String(data: data, encoding: .utf8) else { return }
    suite.set(raw, forKey: "incomingShare")
    NSLog("[Kohera] Share staged for room \(roomId)")
  }

  /// Brings the main app to the foreground so it can read + send the share.
  /// On iOS 18+ the legacy `openURL:` selector is swallowed, so use
  /// `UIApplication.open(_:options:completionHandler:)`; keep the legacy
  /// selector for older iOS (the receive_sharing_intent technique).
  private func redirectToHostApp() {
    guard let url = URL(string: "koherashare://share") else { return }
    var responder: UIResponder? = self
    if #available(iOS 18.0, *) {
      while responder != nil {
        if let application = responder as? UIApplication {
          application.open(url, options: [:], completionHandler: nil)
        }
        responder = responder?.next
      }
    } else {
      let selectorOpenURL = sel_registerName("openURL:")
      while responder != nil {
        if responder?.responds(to: selectorOpenURL) == true {
          _ = responder?.perform(selectorOpenURL, with: url)
        }
        responder = responder?.next
      }
    }
  }
}

// ── Room picker (root) ─────────────────────────────────────────

final class RoomPickerController: UITableViewController, UISearchResultsUpdating {
  private let snapshotKey = "roomSnapshot"
  private let appGroup: String
  private var rooms: [ShareViewController.RoomPick] = []
  private var filtered: [ShareViewController.RoomPick] = []
  private let searchController = UISearchController(searchResultsController: nil)

  var onSelect: ((ShareViewController.RoomPick) -> Void)?
  var onCancel: (() -> Void)?

  init(appGroup: String) {
    self.appGroup = appGroup
    super.init(style: .plain)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Send to"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancel)
    )

    searchController.searchResultsUpdater = self
    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchBar.placeholder = "Search rooms"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
    definesPresentationContext = true

    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "room")
    tableView.rowHeight = 60
    loadFromAppGroup()
  }

  @objc private func cancel() {
    onCancel?()
  }

  private func loadFromAppGroup() {
    guard let suite = UserDefaults(suiteName: appGroup),
          let raw = suite.string(forKey: snapshotKey),
          let data = raw.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      rooms = []
      filtered = []
      showEmpty()
      return
    }
    rooms = arr.compactMap { dict in
      guard let roomId = dict["roomId"] as? String,
            let displayname = dict["displayname"] as? String else { return nil }
      return ShareViewController.RoomPick(
        roomId: roomId,
        displayname: displayname,
        avatarMxc: dict["avatarMxc"] as? String,
        avatarPath: dict["avatarPath"] as? String
      )
    }
    filtered = rooms
    showEmpty()
  }

  private func showEmpty() {
    let empty = filtered.isEmpty
    if empty {
      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      let msg = rooms.isEmpty
        ? "Open Kohera and log in to populate the room list."
        : "No rooms match \"\(searchController.searchBar.text ?? "")\"."
      label.text = msg
      label.textAlignment = .center
      label.textColor = .secondaryLabel
      label.numberOfLines = 0
      label.font = .preferredFont(forTextStyle: .body)
      tableView.backgroundView = label
    } else {
      tableView.backgroundView = nil
    }
    tableView.separatorStyle = empty ? .none : .singleLine
    tableView.reloadData()
  }

  // ── Search ──────────────────────────────────────────────────

  func updateSearchResults(for searchController: UISearchController) {
    let q = (searchController.searchBar.text ?? "").lowercased()
    filtered = q.isEmpty
      ? rooms
      : rooms.filter { $0.displayname.lowercased().contains(q) }
    showEmpty()
  }

  // ── Table view ──────────────────────────────────────────────

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    filtered.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "room", for: indexPath)
    var content = cell.defaultContentConfiguration()
    let room = filtered[indexPath.row]
    content.text = room.displayname
    content.image = avatarImage(for: room)
    content.imageProperties.maximumSize = CGSize(width: 40, height: 40)
    content.imageProperties.cornerRadius = 8
    cell.contentConfiguration = content
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onSelect?(filtered[indexPath.row])
  }

  // ── Avatar helpers ──────────────────────────────────────────

  private func avatarImage(for room: ShareViewController.RoomPick) -> UIImage? {
    if let path = room.avatarPath,
       let image = UIImage(contentsOfFile: path) {
      return image
    }
    return initialPlaceholder(for: room)
  }

  private func initialPlaceholder(for room: ShareViewController.RoomPick) -> UIImage {
    let size = CGSize(width: 80, height: 80)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
      let rect = CGRect(origin: .zero, size: size)
      ctx.cgContext.setFillColor(placeholderColor(for: room.roomId).cgColor)
      ctx.cgContext.fillEllipse(in: rect)
      let initial = String(room.displayname.prefix(1)).uppercased()
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let drawn = (initial as NSString).size(withAttributes: attrs)
      let drawRect = CGRect(
        x: (size.width - drawn.width) / 2,
        y: (size.height - drawn.height) / 2,
        width: drawn.width,
        height: drawn.height
      )
      (initial as NSString).draw(in: drawRect, withAttributes: attrs)
    }
  }

  private func placeholderColor(for roomId: String) -> UIColor {
    let hash = roomId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    let palette: [UIColor] = [
      .systemBlue, .systemTeal, .systemGreen, .systemOrange,
      .systemPink, .systemPurple, .systemIndigo, .systemBrown,
    ]
    return palette[abs(hash) % palette.count]
  }
}