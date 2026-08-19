# Repository Migration — Issue #1024

Migrating the remaining features off direct `matrix.client` / resolver access
and onto the data-layer repositories, per the
[Flutter Guide to App Architecture](https://docs.flutter.dev/app-architecture/guide).

**Epic:** #1021 · **This issue:** #1024 (depends on #1023) · **Branch:**
`refactor/matrix-service-decomposition`

## Goal

After #1024, no consumer code in `lib/features/`, `lib/core/routing/`, or
`lib/shared/` accesses `matrix.client` directly or calls resolvers directly.

Acceptance greps (must return empty):

```bash
grep -rn "\.client\b" lib/features/ lib/core/routing/ lib/shared/
grep -rn "Resolver()" lib/features/ lib/shared/widgets/
```

Plus `flutter analyze` clean (modulo the transitional `rawRoom` deprecation
notices, removed in #1025) and `flutter test` green.

## Approach — vertical slices

One feature area at a time, each an independent commit that keeps the app
green (strangler-fig). Per slice: grow the relevant repository with the SDK
boundary methods, repoint consumers, add repository providers to that area's
test trees, run the suite.

Baseline at start of #1024: **235** `.client` accesses + **25** resolver calls
across `lib/features/`.

## Status

| Slice | Area | Commit | State |
|-------|------|--------|-------|
| 1 | Auth | `1dc501dd` | ✅ Done |
| 2 | Spaces (+ shared `report_content_dialog`) | `bd84f99f` | ✅ Done |
| 3 | Settings | `3e0da036` | ✅ Done |
| 4 | E2EE | `71c4f031` | ✅ Done |
| 5 | Notifications | — | 🔄 In progress |
| 6 | Calling | — | Open |
| 7 | Home / share_in | — | Open |
| 8 | Core routing (`app_router`, `account_switch_redirector`) | — | Open |

Each done slice: `flutter analyze` clean, `flutter test` **2885 passed, 1
skipped**.

## Per-slice notes

### ✅ 1 — Auth (`1dc501dd`)

`RegistrationController` now uses `AuthRepository` (`checkHomeserver`,
`register`, `completeRegistration`, `auth`, `isLoggedIn`). `matrixService`
retained only for the pending-service commit identity check (#1025 territory).

### ✅ 2 — Spaces (`bd84f99f`)

Folded `SpaceMenuActions` into `SpaceRepository` (permissions, notifications,
children, create/join, leave). Migrated the space context menu, details panel,
rail, and action dialog. Consolidated the duplicate `KoheraPushRuleState` onto
the data-layer model. Migrated shared `report_content_dialog` to
`RoomRepository.lastEventId` + `UserRepository.reportEvent`. Space discovery
dialogs now read the provided `SpaceDiscoveryDataSource` from context. Added
`RoomRepository.avatarUri`, `MatrixService.userID`, and `SpaceRepository`
helpers (`parentSpaceRefs`, `spaceExists`, `spaceDisplayname`,
`ownHomeserverHost`).

### ✅ 3 — Settings (`3e0da036`)

Deleted `DeviceManagementService`, `AccountDeactivationService`,
`ProfileAvatarService` (their logic already lived on / moved to
`UserRepository`). Devices, ignored-users, and settings screens plus the
profile-avatar card, account switcher, and deactivate-account dialog now use
`UserRepository` / `MediaRepository`. Grew `UserRepository` with `verifyDevice`,
`toggleBlockDevice`, `deactivateAccount`, `fetchOwnProfile`, `setDisplayName`,
`setOwnAvatar`, `fetchDisplayName`, `onSync`, `homeserver`.

### ✅ 4 — E2EE (`71c4f031`)

Folded encryption bootstrap + verification into `KeyBackupRepository`.
`BootstrapController`, `BootstrapDriver`, `RecoveryKeyHandler`, and the
verification request listener now route through it. Added the E2EE bootstrap
boundary to `KeyBackupRepository`: `encryption`/`userId` accessors,
`updateUserDeviceKeys`, `prepareForBootstrap`, `hasServerKeyBackup`,
`markSessionsForBackupUpload`, `startSelfVerification`, `uia`. Deleted the dead
`KoheraKeyVerification.isMe` getter (its only remaining `.client` access).

> **Sensitive area.** This slice touches encryption bootstrap / cross-signing /
> verification. Recommend an `e2ee-auditor` (or `/security-review`) pass on
> `71c4f031` against `docs/e2ee-flow.md` before merge.

### 🔄 5 — Notifications (in progress)

New **`PushRepository`** (`lib/data/repositories/push_repository.dart`) as the
notification SDK boundary: identity (`userId`/`deviceId`/`deviceName`),
`onSync`, pusher registration (`postPusher`/`deletePusher`), and push-payload
access (`getRoom`, `getRoomEvent`, `decryptRoomEvent`,
`unreadNotificationCount`). Wired into the provider tree in `main.dart`.

- **Done:** `push_service.dart` migrated to `PushRepository`.
- **Remaining:** `apns_push_service`, `ios_voip_push_service`,
  `web_push_service` (same pusher pattern), `notification_service`,
  `notification_grouper`, `inbox_controller`, the
  `NotificationLifecycleObserver` construction wiring in `main.dart`, and all
  affected tests.
- **Note:** `inbox_controller` / `notification_grouper` hold their own `Client`
  field (`updateClient(Client)`, `_grouper..client = newClient`) — a
  different shape than the other services; migrating them threads a repository
  in place of the raw `Client`.

## Key design decisions

- **Fold SDK-wrapper services into repositories** (chosen for spaces, settings,
  e2ee). Widget/feature "service" wrappers that existed only to keep
  `package:matrix` out of widgets move their methods onto the owning repository;
  the old wrapper is deleted.
- **New `PushRepository`** for notifications rather than overloading
  `PushRuleRepository` (push *rules* ≠ *pushers*) or `Room`/`User` repos.
- **AC scope is `.client` / `Resolver()`**, not "no SDK types". Repositories may
  take/return SDK types (`Room`, `Event`, `KeyVerification`, `Encryption`,
  `Pusher`) as documented escape hatches; features operate on those returned
  objects freely — only `matrix.client` and direct resolver construction are
  banned in the consumer layers.
- **Repositories extend `ChangeNotifier`** uniformly so they wire via
  `ChangeNotifierProxyProvider<MatrixService, XRepo>` and pass through
  `MatrixService` notifications for `context.watch`. Most are stateless method
  surfaces where this is boilerplate; kept uniform intentionally, revisit in
  #1025 if desired.
- **Test pattern:** widget/e2e trees gain the new repositories as providers
  (real repos wrapping the existing mock `MatrixService` — they delegate to the
  stubbed client, so existing stubs keep working); a Mockito pitfall to note is
  that calling a mock getter *inside* a `when(...)` argument corrupts the stub
  (capture into a local first).

## Out of scope (→ #1025)

- Removing the `client` getter from `MatrixService`.
- Removing the transitional `@Deprecated RoomRepository.rawRoom`.
- Extracting view models from screens.
