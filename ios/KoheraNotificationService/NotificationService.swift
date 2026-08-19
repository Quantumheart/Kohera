import Intents
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    private var currentRoomId: String?
    private var hasDelivered = false
    private var expired = false

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            deliver(request.content)
            return
        }

        let notification = request.content.userInfo["notification"] as? [String: Any]
        let eventId = notification?["event_id"] as? String
        let roomId = notification?["room_id"] as? String

        guard let eventId = eventId, let roomId = roomId else {
            deliver(content)
            return
        }

        self.currentRoomId = roomId
        content.threadIdentifier = roomId
        content.categoryIdentifier = "MESSAGE"

        let clientName = resolveClientName(userInfo: request.content.userInfo)

        Task { @MainActor in
            await self.processNotification(
                content: content, eventId: eventId, roomId: roomId, clientName: clientName
            )
            self.deliver(self.bestAttemptContent ?? content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        expired = true
        if let content = bestAttemptContent {
            applyFallbackTitleIfNeeded(content: content, roomId: currentRoomId)
            if content.body.isEmpty {
                content.body = "Encrypted message"
            }
            deliver(content)
        }
    }

    private func deliver(_ content: UNNotificationContent) {
        guard !hasDelivered else { return }
        hasDelivered = true
        contentHandler?(content)
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

        let eventTask = Task { await MatrixEventFetcher.fetchEvent(
            homeserver: homeserver, roomId: roomId, eventId: eventId, accessToken: accessToken
        ) }
        let roomNameTask = Task { await MatrixEventFetcher.fetchRoomName(
            homeserver: homeserver, roomId: roomId, accessToken: accessToken
        ) }
        let directRoomIdsTask = Task { await MatrixEventFetcher.fetchDirectRoomIds(
            homeserver: homeserver, userId: userId, accessToken: accessToken
        ) }

        guard let event = await eventTask.value else {
            NSLog("[KoheraNSE] Failed to fetch event %@", eventId)
            roomNameTask.cancel()
            directRoomIdsTask.cancel()
            return
        }
        if expired {
            roomNameTask.cancel()
            directRoomIdsTask.cancel()
            return
        }

        let senderId = event["sender"] as? String
        let directRoomIds = await directRoomIdsTask.value
        let isDirect = directRoomIds?.contains(roomId) ?? false

        let body = await resolveBody(event: event, userId: userId, clientName: clientName)

        if expired {
            roomNameTask.cancel()
            return
        }

        content.body = body
        let fallbackSender = extractSenderName(from: event)

        let profileTask = Task { () -> (avatarUrl: String?, displayname: String?)? in
            guard let senderId = senderId else { return nil }
            return await MatrixEventFetcher.fetchProfile(
                homeserver: homeserver, userId: senderId, accessToken: accessToken
            )
        }
        let counterpartTask = Task { () -> String? in
            guard isDirect, let senderId = senderId else { return nil }
            return await MatrixEventFetcher.fetchMemberDisplayname(
                homeserver: homeserver, roomId: roomId, userId: senderId, accessToken: accessToken
            )
        }

        if expired { roomNameTask.cancel(); counterpartTask.cancel(); return }
        let profile = await profileTask.value
        if expired { roomNameTask.cancel(); counterpartTask.cancel(); return }

        let resolvedSenderName = nonEmpty(profile?.displayname) ?? fallbackSender

        if expired { roomNameTask.cancel(); counterpartTask.cancel(); return }
        let roomName = await roomNameTask.value
        if expired { counterpartTask.cancel(); return }
        let counterpart = await counterpartTask.value
        let title = resolveTitle(roomId: roomId, roomName: roomName, counterpart: counterpart)
        content.title = title
        if !isDirect, let resolvedSender = resolvedSenderName {
            content.subtitle = resolvedSender
        }

        if expired { return }

        await applySenderIntent(
            content: content,
            senderId: senderId,
            senderName: resolvedSenderName,
            avatarMxc: profile?.avatarUrl,
            homeserver: homeserver,
            accessToken: accessToken,
            speakableGroupName: title,
            includeSenderAsRecipient: isDirect
        )
    }

    // ── Body resolution ────────────────────────────────────────────

    private func resolveBody(event: [String: Any], userId: String, clientName: String) async -> String {
        let eventType = event["type"] as? String ?? ""
        if eventType == "m.room.encrypted" {
            return await decryptBody(event: event, userId: userId, clientName: clientName)
        }
        let msgContent = event["content"] as? [String: Any]
        return msgContent?["body"] as? String ?? "New message"
    }

    private func decryptBody(event: [String: Any], userId: String, clientName: String) async -> String {
        guard let encContent = event["content"] as? [String: Any],
              let sessionId = encContent["session_id"] as? String,
              let ciphertext = encContent["ciphertext"] as? String else {
            return "Encrypted message"
        }

        if let body = MegolmDecryptor.decrypt(
            sessionId: sessionId, ciphertext: ciphertext,
            userId: userId, clientName: clientName
        ) {
            return body
        }

        let pollIntervalNanos: UInt64 = 800_000_000
        let maxRetries = 6
        for _ in 0..<maxRetries {
            if expired { break }
            try? await Task.sleep(nanoseconds: pollIntervalNanos)
            if expired { break }
            if let body = MegolmDecryptor.decrypt(
                sessionId: sessionId, ciphertext: ciphertext,
                userId: userId, clientName: clientName
            ) {
                return body
            }
            NSLog("[KoheraNSE] Session not yet mirrored, retrying: %@", sessionId)
        }
        return "Encrypted message"
    }

    // ── Communication notification (sender avatar as icon) ────────

    private func applySenderIntent(
        content: UNMutableNotificationContent,
        senderId: String?,
        senderName: String?,
        avatarMxc: String?,
        homeserver: String,
        accessToken: String,
        speakableGroupName: String,
        includeSenderAsRecipient: Bool
    ) async {
        guard #available(iOS 15.0, *) else { return }
        guard let senderId = senderId else { return }

        var avatarImage: INImage?
        if let mxcUrl = avatarMxc,
           let fileUrl = await MatrixEventFetcher.downloadThumbnail(
               homeserver: homeserver, mxcUrl: mxcUrl, accessToken: accessToken
           ),
           let data = try? Data(contentsOf: fileUrl) {
            avatarImage = INImage(imageData: data)
        }

        let handle = INPersonHandle(value: senderId, type: .unknown)
        let sender = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: senderName ?? senderId,
            image: avatarImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )

        let groupName: INSpeakableString? = speakableGroupName.isEmpty
            ? nil
            : INSpeakableString(spokenPhrase: speakableGroupName)

        let intent = INSendMessageIntent(
            recipients: includeSenderAsRecipient ? [sender] : nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName,
            conversationIdentifier: content.threadIdentifier,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()

        guard !expired else { return }
        if let updated = try? content.updating(from: intent) as? UNMutableNotificationContent {
            self.bestAttemptContent = updated
        }
    }

    // ── Helpers ────────────────────────────────────────────────────

    private func extractSenderName(from event: [String: Any]) -> String? {
        if let sender = event["sender"] as? String {
            let withoutSigil = sender.dropFirst()
            let localpart = withoutSigil.prefix(while: { $0 != ":" })
            return String(localpart)
        }
        return nil
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        return string
    }

    private func resolveTitle(roomId: String, roomName: String?, counterpart: String?) -> String {
        if let roomName = nonEmpty(roomName) {
            return roomName
        }
        if let counterpart = nonEmpty(counterpart) {
            return counterpart
        }
        if let localpart = roomIdLocalpart(roomId) {
            return localpart
        }
        return "New message"
    }

    private func roomIdLocalpart(_ roomId: String) -> String? {
        guard roomId.hasPrefix("!") else { return nil }
        let withoutSigil = roomId.dropFirst()
        let localpart = withoutSigil.prefix(while: { $0 != ":" })
        let result = String(localpart)
        return result.isEmpty ? nil : result
    }

    private func applyFallbackTitleIfNeeded(content: UNMutableNotificationContent, roomId: String?) {
        guard content.title.isEmpty else { return }
        if let roomId = roomId, let localpart = roomIdLocalpart(roomId) {
            content.title = localpart
        } else {
            content.title = "New message"
        }
    }
}