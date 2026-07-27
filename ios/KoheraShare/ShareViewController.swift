import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

/// Share Extension principal class.
///
/// Shows an in-sheet room picker populated from the App-Group `roomSnapshot`
/// store the main app writes on sync. On Post, copies each attachment into the
/// App-Group container via NSFileCoordinator and appends a `pendingShares`
/// entry (matching the Dart `PendingShare` schema) so the main app can drain
/// it and perform the real Matrix send. The Matrix SDK never runs here.
final class ShareViewController: UIViewController {
  private let appGroup = "group.io.github.quantumheart.kohera"
  private let snapshotKey = "roomSnapshot"
  private let pendingKey = "pendingShares"
  private let activeAccountKey = "activeAccountId"

  // Serializes concurrent NSItemProvider callbacks appending to `staged`.
  private let stagingQueue = DispatchQueue(label: "kohera.share.staging")

  private var rooms: [RoomPick] = []
  private var accountId: String?
  private var selectedRoom: RoomPick?

  private let tableView = UITableView(frame: .zero, style: .plain)
  private let emptyLabel = UILabel()
  private let postButton = UIBarButtonItem(
    title: "Post",
    style: .done,
    target: nil,
    action: nil
  )

  struct RoomPick {
    let roomId: String
    let displayname: String
    let avatarMxc: String?
    let avatarPath: String?
  }

  // ── Lifecycle ───────────────────────────────────────────────

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Share to Kohera"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancel)
    )
    postButton.isEnabled = false
    postButton.target = self
    postButton.action = #selector(post)
    navigationItem.rightBarButtonItem = postButton

    view.backgroundColor = .systemBackground
    configureEmptyLabel()
    configureTableView()
    loadFromAppGroup()
  }

  private func configureEmptyLabel() {
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.text = "Open Kohera and log in to populate the room list."
    emptyLabel.textAlignment = .center
    emptyLabel.textColor = .secondaryLabel
    emptyLabel.numberOfLines = 0
    emptyLabel.font = .preferredFont(forTextStyle: .body)
    view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  private func configureTableView() {
    tableView.translatesAutoresizingMaskIntoConstraints = false
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "room")
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  // ── App-Group read ──────────────────────────────────────────

  private func loadFromAppGroup() {
    guard let suite = UserDefaults(suiteName: appGroup) else {
      showEmpty()
      return
    }
    accountId = suite.string(forKey: activeAccountKey)

    guard let raw = suite.string(forKey: snapshotKey),
          let data = raw.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      showEmpty()
      return
    }

    rooms = arr.compactMap { dict in
      guard let roomId = dict["roomId"] as? String,
            let displayname = dict["displayname"] as? String else { return nil }
      return RoomPick(
        roomId: roomId,
        displayname: displayname,
        avatarMxc: dict["avatarMxc"] as? String,
        avatarPath: dict["avatarPath"] as? String
      )
    }
    showEmpty()
  }

  private func showEmpty() {
    let empty = rooms.isEmpty
    tableView.isHidden = empty
    emptyLabel.isHidden = !empty
    tableView.reloadData()
  }

  /// Returns the room's avatar image: the pre-rendered file at `avatarPath`
  /// if present and loadable, otherwise a colored-initial placeholder circle.
  private func avatarImage(for room: RoomPick) -> UIImage? {
    if let path = room.avatarPath,
       let image = UIImage(contentsOfFile: path) {
      return image
    }
    return initialPlaceholder(for: room)
  }

  /// Renders a 72x72 circle filled with a color derived from the roomId, with
  /// the display name's first character as a white glyph.
  private func initialPlaceholder(for room: RoomPick) -> UIImage {
    let size = CGSize(width: 72, height: 72)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
      let rect = CGRect(origin: .zero, size: size)
      ctx.cgContext.setFillColor(placeholderColor(for: room.roomId).cgColor)
      ctx.cgContext.fillEllipse(in: rect)
      let initial = String(room.displayname.prefix(1)).uppercased()
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
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

  /// Deterministic color from the roomId hash.
  private func placeholderColor(for roomId: String) -> UIColor {
    let hash = roomId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    let palette: [UIColor] = [
      .systemBlue, .systemTeal, .systemGreen, .systemOrange,
      .systemPink, .systemPurple, .systemIndigo, .systemBrown,
    ]
    return palette[abs(hash) % palette.count]
  }

  // ── Actions ─────────────────────────────────────────────────

  @objc private func cancel() {
    extensionContext?.cancelRequest(withError: NSError(domain: "KoheraShare", code: 0))
  }

  @objc private func post() {
    guard let room = selectedRoom else { return }
    postButton.isEnabled = false

    stageAndEnqueue(targetRoom: room) { [weak self] in
      DispatchQueue.main.async {
        self?.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  // ── Staging ─────────────────────────────────────────────────

  private func stageAndEnqueue(targetRoom: RoomPick, completion: @escaping () -> Void) {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
      enqueueTextShare(targetRoom: targetRoom, text: nil, completion: completion)
      return
    }

    let group = DispatchGroup()
    var staged: [[String: Any]] = []

    for item in items {
      guard let attachments = item.attachments, !attachments.isEmpty else { continue }
      for provider in attachments {
        group.enter()
        stageAttachment(provider: provider) { entry in
          // NSItemProvider callbacks arrive on arbitrary threads; serialize
          // appends to avoid concurrent mutation of `staged`.
          self.stagingQueue.sync { if let entry = entry { staged.append(entry) } }
          group.leave()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { completion(); return }
      if staged.isEmpty {
        // No file/url/text attachment staged — fall back to the host's inline
        // text (e.g. selected text in Notes arrives as attributedContentText,
        // not as an NSItemProvider attachment).
        let text = items.compactMap { $0.attributedContentText?.string }
          .first(where: { !$0.isEmpty })
        self.enqueueTextShare(targetRoom: targetRoom, text: text, completion: completion)
      } else {
        self.enqueue(staged: staged, targetRoom: targetRoom, completion: completion)
      }
    }
  }

  private func stageAttachment(
    provider: NSItemProvider,
    done: @escaping ([String: Any]?) -> Void
  ) {
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
        let text = (item as? String) ?? (item as? URL)?.absoluteString
        done(text.map { ["kind": "text", "text": $0] })
      }
      return
    }

    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
        let text = (item as? URL)?.absoluteString ?? (item as? String)
        done(text.map { ["kind": "text", "text": $0] })
      }
      return
    }

    let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] tempURL, error in
      guard let self, let tempURL = tempURL, error == nil else { done(nil); return }
      self.copyIntoAppGroup(tempURL: tempURL, provider: provider) { entry in
        done(entry)
      }
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
    text: String?,
    completion: @escaping () -> Void
  ) {
    guard let text = text, !text.isEmpty else { completion(); return }
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

// ── Table view ─────────────────────────────────────────────────

extension ShareViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rooms.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "room", for: indexPath)
    var content = cell.defaultContentConfiguration()
    let room = rooms[indexPath.row]
    content.text = room.displayname
    content.image = avatarImage(for: room)
    content.imageProperties.maximumSize = CGSize(width: 36, height: 36)
    content.imageProperties.cornerRadius = 6
    cell.contentConfiguration = content
    cell.accessoryType = room.roomId == selectedRoom?.roomId ? .checkmark : .none
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    selectedRoom = rooms[indexPath.row]
    postButton.isEnabled = true
    tableView.reloadRows(at: [indexPath], with: .none)
  }
}