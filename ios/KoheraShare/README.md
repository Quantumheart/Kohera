# KoheraShare — iOS Share Extension target setup

This folder holds the source files for the inbound Share Extension target
(issue #863). The target itself must be added via Xcode (hand-editing
`project.pbxproj` is avoided to protect the existing Runner build). Follow
the steps below once, then commit the resulting `project.pbxproj` changes.

## Files provided

- `ShareViewController.swift` — principal class; in-sheet room picker reading
  the App-Group `roomSnapshot` store, stages attachments via
  `NSFileCoordinator`, appends `pendingShares` entries.
- `Info.plist` — `NSExtension` block (`com.apple.share-services`,
  activation rule: images ≤10, movies ≤5, text, web URL ≤1, files ≤10).
- `KoheraShare.entitlements` — App Group `group.io.github.quantumheart.kohera`
  + keychain sharing `$(AppIdentifierPrefix)io.github.quantumheart.kohera.shared`
  (mirrors `Runner.entitlements` and `KoheraNotificationService.entitlements`).

## Add the target in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the `Runner` project in the navigator → **File → New → Target…**
3. iOS tab → **Share Extension** → Next.
   - Product name: `KoheraShare`
   - Organization identifier: same as Runner (`io.github.quantumheart` so the
     bundle id becomes `io.github.quantumheart.kohera.KoheraShare` — adjust to
     match your signing; the issue targets `com.kohera.app.Share` but the
     existing app bundle id is `io.github.quantumheart.kohera`, so use that
     prefix to keep App-Group/keychain sharing valid).
   - Language: Swift.
   - Uncheck "Include UI test target".
4. Finish. Xcode creates `KoheraShare/` with a default
   `ShareViewController.swift` and `Info.plist`. **Delete the generated**
   `ShareViewController.swift` and **move the three files in this folder into**
   the `KoheraShare/` group (drag into the Xcode navigator, "Copy items if
   needed" off since they already live here). Replace the generated
   `Info.plist` with the one here.
5. Select the `KoheraShare` target → **Signing & Capabilities**:
   - Enable **App Groups** → add `group.io.github.quantumheart.kohera`.
   - Enable **Keychain Sharing** → add
     `$(AppIdentifierPrefix)io.github.quantumheart.kohera.shared`.
   - (Or set the code-sign entitlements file to `KoheraShare.entitlements`
     under Build Settings → Code Signing Entitlements.)
6. Target **Build Settings**:
   - Info.plist File → `KoheraShare/Info.plist`.
   - Code Signing Entitlements → `KoheraShare/KoheraShare.entitlements`.
   - Product Bundle Identifier → `io.github.quantumheart.kohera.KoheraShare`.
   - iOS Deployment Target → match Runner (see `Podfile` platform).
7. Select the `Runner` target → **General → Frameworks, Libraries, and
   Embedded Content** (or **Build Phases → Embed Foundation Extensions**):
   confirm `KoheraShare.appex` is listed with "Embed Without Code Signing"
   (or the embed option Xcode picks for app extensions). The existing
   `KoheraNotificationService.appex` is the template — mirror its embed row.
8. Provisioning: both `Runner` and `KoheraShare` targets need a profile that
   includes the App Group capability. Use the same team as Runner.

## Build & verify

1. `flutter pub get` (so the workspace is up to date), then build from Xcode:
   `flutter build ios --debug` (or run from Xcode on a device/sim).
2. From Photos / Files / Safari / Notes, open the share sheet → Kohera should
   appear.
3. Select Kohera → the room picker should list rooms from the `roomSnapshot`
   store (populate by launching the main app first and letting sync run —
   slice #862 writes the store).
4. Pick a room → Post → inspect
   `UserDefaults(suiteName:"group.io.github.quantumheart.kohera")?.string(forKey:"pendingShares")`
   to confirm the entry was enqueued.

## Schema contract (must match slice #862)

`pendingShares` entries:

```json
{
  "id": "<uuid>",
  "targetRoomId": "!room:server",
  "accountId": "<MatrixService.clientName>",
  "kind": "text" | "file",
  "text": "..." | null,
  "filePath": "/abs/path/in/app-group" | null,
  "mimeType": "image/png" | null,
  "originalFileName": "photo.png" | null,
  "createdAt": 1700000000000
}
```

`roomSnapshot` (read-only here, written by main app):

```json
[{ "roomId": "!room:server", "displayname": "Project", "avatarMxc": "mxc://..." }]
```

`activeAccountId` (read-only here): the active account's clientName string.

## Out of scope for this slice

- Draining `pendingShares` and performing the Matrix send — slice #864.
- Outbound sharing — `share_plus` issue.
- Android / desktop inbound.