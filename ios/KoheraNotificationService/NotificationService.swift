import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let notification = request.content.userInfo["notification"] as? [String: Any]
        let eventId = notification?["event_id"] as? String
        let roomId = notification?["room_id"] as? String

        guard let eventId = eventId, let roomId = roomId else {
            contentHandler(content)
            return
        }

        content.threadIdentifier = roomId
        content.categoryIdentifier = "MESSAGE"

        let clientName = resolveClientName(userInfo: request.content.userInfo)

        Task { @MainActor in
            await self.processNotification(
                content: content, eventId: eventId, roomId: roomId, clientName: clientName
            )
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    // ── Client resolution ────────────────────────────────────────

    private func resolveClientName(userInfo: [AnyHashable: Any]) -> String {
        if let notification = userInfo["notification"] as? [String: Any],
           let userId = notification["user_id"] as? String,
           !userId.isEmpty {
            let safe = userId
                .replacingOccurrences(of: "@", with: "")
                .replacingOccurrences(of: ":", with: "_")
            return safe
        }
        return "default"
    }

    // ── Processing ───────────────────────────────────────────────

    private func processNotification(
        content: UNMutableNotificationContent,
        eventId: String,
        roomId: String,
        clientName: String
    ) async {
        guard let accessToken = SharedKeychainReader.read(key: "kohera_\(clientName)_access_token"),
              let homeserver = SharedKeychainReader.read(key: "kohera_\(clientName)_homeserver"),
              let userId = SharedKeychainReader.read(key: "kohera_\(clientName)_user_id") else {
            NSLog("[KoheraNSE] Missing credentials in shared keychain for client %@", clientName)
            return
        }

        guard let event = await MatrixEventFetcher.fetchEvent(
            homeserver: homeserver,
            roomId: roomId,
            eventId: eventId,
            accessToken: accessToken
        ) else {
            NSLog("[KoheraNSE] Failed to fetch event %@", eventId)
            return
        }

        let senderName = extractSenderName(from: event)
        let eventType = event["type"] as? String ?? ""

        if eventType == "m.room.encrypted" {
            decryptAndUpdate(
                content: content, event: event, userId: userId,
                clientName: clientName, senderName: senderName
            )
        } else {
            let msgContent = event["content"] as? [String: Any]
            let body = msgContent?["body"] as? String ?? "New message"
            updateContent(content: content, senderName: senderName, body: body)
        }
    }

    private func decryptAndUpdate(
        content: UNMutableNotificationContent,
        event: [String: Any],
        userId: String,
        clientName: String,
        senderName: String?
    ) {
        guard let encContent = event["content"] as? [String: Any],
              let sessionId = encContent["session_id"] as? String,
              let ciphertext = encContent["ciphertext"] as? String else {
            content.body = "Encrypted message"
            return
        }

        if let body = MegolmDecryptor.decrypt(
            sessionId: sessionId,
            ciphertext: ciphertext,
            userId: userId,
            clientName: clientName
        ) {
            updateContent(content: content, senderName: senderName, body: body)
        } else {
            content.body = "Encrypted message"
        }
    }

    private func updateContent(content: UNMutableNotificationContent, senderName: String?, body: String) {
        if let senderName = senderName {
            content.body = "\(senderName): \(body)"
        } else {
            content.body = body
        }
    }

    private func extractSenderName(from event: [String: Any]) -> String? {
        if let sender = event["sender"] as? String {
            let withoutSigil = sender.dropFirst()
            let localpart = withoutSigil.prefix(while: { $0 != ":" })
            return String(localpart)
        }
        return nil
    }
}
