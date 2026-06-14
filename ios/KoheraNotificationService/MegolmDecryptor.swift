import CryptoKit
import Foundation
import SQLite3

struct MegolmDecryptor {
    private static let appGroupId = "group.io.github.quantumheart.kohera"

    static func decrypt(sessionId: String, ciphertext: String, userId: String, clientName: String = "default") -> String? {
        let pickleKey = derivePickleKey(from: userId)
        guard let pickle = lookupSession(sessionId: sessionId, clientName: clientName) else {
            NSLog("[KoheraNSE] No session found for %@", sessionId)
            return nil
        }

        guard let pickleC = pickle.cString(using: .utf8),
              let ciphertextC = ciphertext.cString(using: .utf8) else {
            NSLog("[KoheraNSE] Failed to convert strings to C format")
            return nil
        }

        let result = ios_decrypt_event(pickleC, pickleKey, ciphertextC)
        defer { ios_free_result(result) }

        if let error = result.error {
            let errorMsg = String(cString: error)
            NSLog("[KoheraNSE] Decryption failed: %@", errorMsg)
            return nil
        }

        guard let plaintextPtr = result.plaintext else {
            NSLog("[KoheraNSE] Null plaintext from decryption")
            return nil
        }

        let plaintext = String(cString: plaintextPtr)
        return extractBody(from: plaintext)
    }

    // ── Pickle key derivation ────────────────────────────────────

    private static func derivePickleKey(from userId: String) -> [UInt8] {
        var bytes = Array(userId.utf16).map { UInt8(truncatingIfNeeded: $0) }
        if bytes.count < 32 {
            bytes.append(contentsOf: [UInt8](repeating: 0, count: 32 - bytes.count))
        } else if bytes.count > 32 {
            bytes = Array(bytes.prefix(32))
        }
        return bytes
    }

    // ── Session lookup ───────────────────────────────────────────

    private static func lookupSession(sessionId: String, clientName: String) -> String? {
        guard let dbKey = loadDbKey(clientName: clientName) else {
            NSLog("[KoheraNSE] No key-mirror encryption key available")
            return nil
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            NSLog("[KoheraNSE] Cannot access App Group container")
            return nil
        }

        let dbPath = containerURL.appendingPathComponent("kohera_\(clientName)_keys.db").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            NSLog("[KoheraNSE] Failed to open key mirror database at %@", dbPath)
            return nil
        }
        defer { sqlite3_close(db) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        let sql = "SELECT v FROM box_inbound_group_session WHERE k = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[KoheraNSE] Failed to prepare query")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
        NSLog("[KoheraNSE] Looking up session: %@", sessionId)

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_ROW else {
            NSLog("[KoheraNSE] Session not found (result: %d)", stepResult)
            return nil
        }

        guard let cValue = sqlite3_column_text(stmt, 0) else { return nil }
        let storedValue = String(cString: cValue)

        guard let jsonData = decryptValue(base64: storedValue, key: dbKey) else {
            NSLog("[KoheraNSE] Failed to decrypt session payload")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let pickle = json["pickle"] as? String else {
            NSLog("[KoheraNSE] Failed to parse session JSON")
            return nil
        }

        return pickle
    }

    // ── Payload encryption (AES-256-GCM, key shared via Keychain) ─

    private static func loadDbKey(clientName: String) -> SymmetricKey? {
        guard let encoded = SharedKeychainReader.read(
                  key: "kohera_\(clientName)_key_mirror_db_key"
              ),
              let data = Data(base64Encoded: encoded),
              data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    private static func decryptValue(base64: String, key: SymmetricKey) -> Data? {
        guard let combined = Data(base64Encoded: base64) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            NSLog("[KoheraNSE] AES-GCM open failed: %@", error.localizedDescription)
            return nil
        }
    }

    // ── Body extraction ──────────────────────────────────────────

    private static func extractBody(from plaintext: String) -> String? {
        guard let data = plaintext.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [String: Any] else {
            NSLog("[KoheraNSE] Failed to parse decrypted event")
            return nil
        }

        let msgtype = content["msgtype"] as? String ?? ""
        switch msgtype {
        case "m.image": return "sent an image"
        case "m.video": return "sent a video"
        case "m.audio": return "sent audio"
        case "m.file":  return "sent a file"
        default:        return content["body"] as? String
        }
    }
}
