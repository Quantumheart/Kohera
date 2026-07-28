import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension principal class.
///
/// Custom `UINavigationController` (Signal-style) so we control the full UI
/// stack and height, instead of the system-clamped `SLComposeServiceViewController`
/// sheet. Flow:
///
///   RoomPickerController (search + avatars, full height)
///     └─> ComposeViewController (attachment preview + message + Send/Cancel)
///           └─> stage attachments into the App-Group container, append a
///               `pendingShares` entry, complete the extension request.
///
/// The Matrix SDK never runs here. Rooms come from the App-Group `roomSnapshot`
/// the main app writes on sync; avatars are pre-rendered into the App Group.
final class ShareViewController: UINavigationController {

  let appGroup = "group.io.github.quantumheart.kohera"
  let pendingKey = "pendingShares"
  let activeAccountKey = "activeAccountId"

  // Serializes concurrent NSItemProvider callbacks appending to staged.
  let stagingQueue = DispatchQueue(label: "kohera.share.staging")

  var accountId: String?
  private(set) var selectedRoom: RoomPick?

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
    accountId = UserDefaults(suiteName: appGroup)?.string(forKey: activeAccountKey)

    let picker = RoomPickerController(appGroup: appGroup)
    picker.onSelect = { [weak self] room in
      guard let self else { return }
      self.selectedRoom = room
      self.pushCompose(for: room)
    }
    picker.onCancel = { [weak self] in
      self?.cancelExtension()
    }
    setViewControllers([picker], animated: false)
  }

  private func pushCompose(for room: RoomPick) {
    let compose = ComposeViewController(targetRoom: room)
    compose.onSend = { [weak self] text in
      self?.stageAndEnqueue(typedText: text)
    }
    compose.onCancel = { [weak self] in
      self?.popComposeOrCancel()
    }
    pushViewController(compose, animated: true)
  }

  private func popComposeOrCancel() {
    if viewControllers.count > 1 {
      popViewController(animated: true)
    } else {
      cancelExtension()
    }
  }

  func cancelExtension() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  /// Brings the main app to the foreground so its `ShareDrainService` wakes
  /// and drains the just-enqueued `pendingShares`. Walks the responder chain
  /// to reach the system `openURL:` handler (the `receive_sharing_intent`
  /// technique) using our `koherashare` URL scheme; the payload is empty
  /// because the data already lives in the App-Group store.
  private func redirectToHostApp() {
    guard let url = URL(string: "koherashare://share") else { return }
    var responder: UIResponder? = self
    let selectorOpenURL = sel_registerName("openURL:")
    var found = false
    while responder != nil {
      if responder?.responds(to: selectorOpenURL) == true {
        found = true
        NSLog("[Kohera] Share: openURL responder = \(String(describing: responder))")
        _ = responder?.perform(selectorOpenURL, with: url)
      }
      responder = responder?.next
    }
    NSLog("[Kohera] Share: redirectToHostApp done, found=\(found)")
  }

  // ── Staging + enqueue ───────────────────────────────────────

  private func stageAndEnqueue(typedText: String) {
    guard let room = selectedRoom else {
      cancelExtension()
      return
    }
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let group = DispatchGroup()
    var staged: [[String: Any]] = []
    var inlineText = typedText

    for item in items {
      guard let attachments = item.attachments, !attachments.isEmpty else { continue }
      for provider in attachments {
        // Text/URL attachments fold into the compose text, not staged as files.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { raw, _ in
            let s = (raw as? URL)?.absoluteString ?? (raw as? String)
            if let s = s, !s.isEmpty {
              self.stagingQueue.sync {
                if inlineText.isEmpty { inlineText = s }
                else if !inlineText.contains(s) { inlineText += "\n\(s)" }
              }
            }
            group.leave()
          }
          continue
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { raw, _ in
            let s = (raw as? String) ?? (raw as? URL)?.absoluteString
            if let s = s, !s.isEmpty {
              self.stagingQueue.sync {
                if inlineText.isEmpty { inlineText = s }
                else if !inlineText.contains(s) { inlineText += "\n\(s)" }
              }
            }
            group.leave()
          }
          continue
        }
        group.enter()
        stageFile(provider: provider) { entry in
          self.stagingQueue.sync { if let entry = entry { staged.append(entry) } }
          group.leave()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      let sendGroup = DispatchGroup()
      if !inlineText.isEmpty {
        sendGroup.enter()
        self.enqueueTextShare(targetRoom: room, text: inlineText) { sendGroup.leave() }
      }
      if !staged.isEmpty {
        sendGroup.enter()
        self.enqueue(staged: staged, targetRoom: room) { sendGroup.leave() }
      }
      sendGroup.notify(queue: .main) { [weak self] in
        guard let self else { return }
        NSLog("[Kohera] Share: staging complete, redirecting to host app")
        self.redirectToHostApp()
        self.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  private func stageFile(
    provider: NSItemProvider,
    done: @escaping ([String: Any]?) -> Void
  ) {
    let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
      UTType($0)?.conforms(to: .image) == false
    }) ?? provider.registeredTypeIdentifiers.first ?? UTType.data.identifier

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
          "kind": "file",
          "filePath": dest.path,
          "mimeType": mime,
          "originalFileName": originalName,
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

  // ── Enqueue ─────────────────────────────────────────────────

  private func enqueueTextShare(
    targetRoom: RoomPick,
    text: String,
    completion: @escaping () -> Void
  ) {
    let entry: [String: Any] = [
      "id": UUID().uuidString,
      "targetRoomId": targetRoom.roomId,
      "accountId": accountId ?? "",
      "kind": "text",
      "text": text,
      "createdAt": Int(Date().timeIntervalSince1970 * 1000),
    ]
    appendPending(entry: entry, completion: completion)
  }

  private func enqueue(
    staged: [[String: Any]],
    targetRoom: RoomPick,
    completion: @escaping () -> Void
  ) {
    let createdAt = Int(Date().timeIntervalSince1970 * 1000)
    let group = DispatchGroup()
    for entry in staged {
      group.enter()
      var full: [String: Any] = [
        "id": UUID().uuidString,
        "targetRoomId": targetRoom.roomId,
        "accountId": accountId ?? "",
        "createdAt": createdAt,
      ]
      for (k, v) in entry { full[k] = v }
      appendPending(entry: full) { group.leave() }
    }
    group.notify(queue: .main) { completion() }
  }

  private func appendPending(entry: [String: Any], completion: @escaping () -> Void) {
    guard let suite = UserDefaults(suiteName: appGroup) else { completion(); return }
    var arr: [[String: Any]] = []
    if let raw = suite.string(forKey: pendingKey),
       let data = raw.data(using: .utf8),
       let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      arr = existing
    }
    arr.append(entry)
    if let back = try? JSONSerialization.data(withJSONObject: arr),
       let s = String(data: back, encoding: .utf8) {
      suite.set(s, forKey: pendingKey)
      NSLog("[Kohera] Share enqueued for room \(entry["targetRoomId"] ?? "?")")
    }
    completion()
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
    title = "Choose room"
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
    cell.accessoryType = .disclosureIndicator
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

// ── Compose / approval ─────────────────────────────────────────

final class ComposeViewController: UIViewController, UITextViewDelegate {
  private let targetRoom: ShareViewController.RoomPick
  private let textView = UITextView()
  private let placeholderLabel = UILabel()
  private let previewStack = UIStackView()
  private let previewScroll = UIScrollView()

  var onSend: ((String) -> Void)?
  var onCancel: (() -> Void)?

  init(targetRoom: ShareViewController.RoomPick) {
    self.targetRoom = targetRoom
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = targetRoom.displayname
    view.backgroundColor = .systemBackground

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancel)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "Send",
      style: .done,
      target: self,
      action: #selector(send)
    )

    setupPreview()
    setupTextView()
    loadAttachments()
  }

  @objc private func cancel() { onCancel?() }

  @objc private func send() {
    let text = textView.text ?? ""
    onSend?(text)
  }

  // ── Layout ──────────────────────────────────────────────────

  private func setupPreview() {
    previewScroll.translatesAutoresizingMaskIntoConstraints = false
    previewStack.translatesAutoresizingMaskIntoConstraints = false
    previewStack.axis = .horizontal
    previewStack.spacing = 8
    previewStack.alignment = .center
    previewScroll.addSubview(previewStack)
    previewScroll.showsHorizontalScrollIndicator = true
    view.addSubview(previewScroll)

    NSLayoutConstraint.activate([
      previewScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      previewScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
      previewStack.topAnchor.constraint(equalTo: previewScroll.topAnchor, constant: 8),
      previewStack.bottomAnchor.constraint(equalTo: previewScroll.bottomAnchor, constant: -8),
      previewStack.leadingAnchor.constraint(equalTo: previewScroll.leadingAnchor, constant: 12),
      previewStack.trailingAnchor.constraint(equalTo: previewScroll.trailingAnchor, constant: -12),
      previewStack.heightAnchor.constraint(equalTo: previewScroll.heightAnchor, constant: -16),
    ])
  }

  private func setupTextView() {
    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.font = .preferredFont(forTextStyle: .body)
    textView.delegate = self
    textView.layer.cornerRadius = 10
    textView.backgroundColor = .secondarySystemBackground
    textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
    view.addSubview(textView)

    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.text = "Add a message (optional)…"
    placeholderLabel.textColor = .placeholderText
    placeholderLabel.font = .preferredFont(forTextStyle: .body)
    placeholderLabel.isHidden = true
    view.addSubview(placeholderLabel)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: previewScroll.bottomAnchor, constant: 8),
      textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
      placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
      placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),
    ])
  }

  // ── Attachments ─────────────────────────────────────────────

  private struct Preview {
    let image: UIImage?
    let name: String
  }

  private func loadAttachments() {
    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    var foundAny = false
    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          foundAny = true
          loadImagePreview(provider: provider)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          foundAny = true
          loadTextPreview(provider: provider, type: UTType.url.identifier)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          foundAny = true
          loadTextPreview(provider: provider, type: UTType.plainText.identifier)
        } else {
          foundAny = true
          addFileChip(name: provider.suggestedName ?? "Attachment")
        }
      }
    }
    if !foundAny {
      previewScroll.isHidden = true
    }
  }

  private func loadImagePreview(provider: NSItemProvider) {
    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
      let image = (item as? UIImage)
        ?? (item as? URL).flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init)
      DispatchQueue.main.async {
        guard let self, let image = image else { return }
        self.addImageChip(image: image)
      }
    }
  }

  private func loadTextPreview(provider: NSItemProvider, type: String) {
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
      let s = (item as? String) ?? (item as? URL)?.absoluteString
      DispatchQueue.main.async {
        guard let self, let s = s, !s.isEmpty else { return }
        if (self.textView.text ?? "").isEmpty {
          self.textView.text = s
          self.placeholderLabel.isHidden = true
        }
        self.addLinkChip(text: s)
      }
    }
  }

  private func addImageChip(image: UIImage) {
    let iv = UIImageView(image: image)
    iv.contentMode = .scaleAspectFill
    iv.clipsToBounds = true
    iv.layer.cornerRadius = 8
    iv.widthAnchor.constraint(equalToConstant: 80).isActive = true
    iv.heightAnchor.constraint(equalToConstant: 80).isActive = true
    previewStack.addArrangedSubview(iv)
  }

  private func addLinkChip(text: String) {
    let label = UILabel()
    label.text = text.count > 40 ? String(text.prefix(40)) + "…" : text
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .link
    label.numberOfLines = 2
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
    previewStack.addArrangedSubview(label)
  }

  private func addFileChip(name: String) {
    let label = UILabel()
    label.text = "📎 \(name)"
    label.font = .preferredFont(forTextStyle: .footnote)
    label.numberOfLines = 2
    label.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
    previewStack.addArrangedSubview(label)
  }

  // ── Text view delegate ──────────────────────────────────────

  func textViewDidChange(_ textView: UITextView) {
    placeholderLabel.isHidden = !textView.text.isEmpty
  }
}