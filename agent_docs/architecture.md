# Architecture

## Directory structure

```
lib/
  main.dart                         # App bootstrap, Provider tree
  data/
    models/                        # Domain models (SDK-free, immutable)
      kohera_room_summary.dart
      kohera_room_member.dart
      kohera_room_permissions.dart
      kohera_message_display.dart
      kohera_reaction.dart
      kohera_reply_preview.dart
      kohera_read_receipt.dart
      kohera_state_event_text.dart
      kohera_media_content.dart
      kohera_poll.dart
      kohera_user_summary.dart
      kohera_device.dart
      kohera_device_key.dart
      kohera_sticker_pack.dart
      kohera_push_rule_state.dart
      space_node.dart
      call_constants.dart
      sticker_pack.dart             # SDK-coupled pack image type (pre-conversion)
    resolvers/                      # SDK→domain model conversion boundary
      room_summary_resolver.dart
      room_permissions_resolver.dart
      room_member_list_resolver.dart
      message_display_resolver.dart
      reaction_resolver.dart
      reply_preview_resolver.dart
      read_receipt_resolver.dart
      state_event_resolver.dart
      media_content_resolver.dart
      poll_resolver.dart
      user_summary_resolver.dart
      device_resolver.dart
      sticker_pack_resolver.dart
    repositories/                   # Repository layer (Flutter Architecture Guide)
      room_repository.dart
      user_repository.dart
      message_repository.dart
      auth_repository.dart
      key_backup_repository.dart
      media_repository.dart
      space_repository.dart
      outbox_repository.dart
      push_rule_repository.dart
      sticker_pack_repository.dart
      message_search_repository.dart
    services/                       # Data-layer services (stateless SDK wrappers)
      avatar_resolver.dart         # mxc://→HTTP URL resolution
      media_resolver.dart           # mxc://→HTTP URL resolution
      message_indexer_service.dart  # Encrypted message search indexing
      message_search_database.dart # SQLite FTS5 search database
  core/
    extensions/
    models/                         # SpaceNode, UploadState, etc.
    routing/
      app_router.dart               # GoRouter with auth-aware redirects
      route_names.dart              # Route constants
    features/
      auth/                           # Login, registration, SSO, reCAPTCHA
      calling/                        # Voice/video via LiveKit + flutter_webrtc
      chat/                           # Message rendering, compose, search
      e2ee/                           # Key backup, cross-signing, device verification
      home/                           # HomeShell: responsive layout manager
      notifications/                  # OS notifications, web push, inbox
      rooms/                          # Room list, details, context menus
      settings/                       # Appearance, notifications, devices, voice/video
      spaces/                         # Space rail, space details
    shared/widgets/                   # Avatars, image viewer, speed dial, section headers
      matrix_service.dart           # Main ChangeNotifier wrapping Client
      client_manager.dart           # Multi-account management
      call_service.dart             # Call orchestration
      preferences_service.dart      # SharedPreferences wrapper
      app_config.dart               # JSON config + env vars
      sub_services/                 # Extracted ChangeNotifiers
        auth_service.dart
        sync_service.dart
        chat_backup_service.dart
        selection_service.dart      # Space/room selection
        uia_service.dart            # User Interactive Auth (cached password, 5-min TTL)
    theme/
    utils/
      platform_info.dart            # Platform-specific via .native.dart / .web.dart
  features/
    auth/                           # Login, registration, SSO, reCAPTCHA
    calling/                        # Voice/video via LiveKit + flutter_webrtc
    chat/                           # Message rendering, compose, search
    e2ee/                           # Key backup, cross-signing, device verification
    home/                           # HomeShell: responsive layout manager
    notifications/                  # OS notifications, web push, inbox
    rooms/                          # Room list, details, context menus
    settings/                       # Appearance, notifications, devices, voice/video
    spaces/                         # Space rail, space details
  shared/widgets/                   # Avatars, image viewer, speed dial, section headers
```

## State management

All state is Provider + ChangeNotifier. The provider tree in `main.dart` provides:

- `ClientManager` -- multi-account management
- `PreferencesService` -- SharedPreferences wrapper
- `MediaPlaybackService` -- audio/video playback

Per active account (nested inside a Consumer):
- `MatrixService` -- wraps matrix.Client, central state
- `SelectionService` -- room/space selection
- `ChatBackupService` -- E2EE key backup status
- `InboxController` -- notification inbox
- `CallService` -- call orchestration
- `PushToTalkService` -- PTT state
- `RoomRepository` -- room data (summaries, permissions, members) via resolvers
- `UserRepository` -- user/device data (summaries, device keys) via resolvers
- `MessageRepository` -- message data (display, reactions, replies) via resolvers
- `AuthRepository` -- auth state (login, logout, session)
- `KeyBackupRepository` -- E2EE key backup, cross-signing
- `MediaRepository` -- avatar/media resolution
- `SpaceRepository` -- space access control
- `OutboxRepository` -- outbox state
- `PushRuleRepository` -- push rule management
- `StickerPackRepository` -- sticker/emoji packs
- `MessageSearchRepository` -- message search indexing

MatrixService lazy-loads sub-services: AuthService, SyncService, SelectionService, ChatBackupService, UiaService.

## Repository layer

The repository layer (`lib/data/repositories/`) follows the [Flutter Guide to App
Architecture](https://docs.flutter.dev/app-architecture/guide). Repositories are
the **source of truth** for application data and the **conversion boundary**
where raw SDK types are transformed into Kohera domain models.

Domain models live in `lib/data/models/` and resolvers live in
`lib/data/resolvers/`. The data layer never imports from `lib/features/` —
dependency direction is always features → data, never the reverse.

Each repository:
- Extends `ChangeNotifier` and is provided via `ChangeNotifierProxyProvider` in
  `main.dart`, reacting to account switches.
- Owns the resolver calls for its domain — controllers and widgets should
  consume domain models from repositories, never call resolvers directly.
- Takes `MatrixService` as a constructor dependency (transitional — will later
  take `MatrixClientService` + sub-services directly).

| Repository | Domain models | Resolvers owned |
|---|---|---|
| `RoomRepository` | `KoheraRoomSummary`, `KoheraRoomPermissions`, `KoheraRoomMemberList` | `RoomSummaryResolver`, `RoomPermissionsResolver`, `RoomMemberListResolver` |
| `UserRepository` | `KoheraUserSummary`, `KoheraDevice`, `KoheraDeviceKey` | `UserSummaryResolver`, `DeviceResolver` |
| `MessageRepository` | `KoheraMessageDisplay`, `KoheraReactionList`, `KoheraReplyPreview`, `KoheraReadReceipt`, `KoheraStateEventText`, `KoheraMediaContent`, `KoheraPoll` | `MessageDisplayResolver`, `ReactionResolver`, `ReplyPreviewResolver`, `ReadReceiptResolver`, `StateEventResolver`, `MediaContentResolver`, `PollResolver` |
| `AuthRepository` | — | — (wraps `AuthService`) |
| `KeyBackupRepository` | — | — (wraps `ChatBackupService`, `MegolmKeyMirror`) |
| `MediaRepository` | — | — (wraps `AvatarResolver`, `MediaResolver`) |
| `SpaceRepository` | — | — (wraps `SpaceAccessService`) |
| `OutboxRepository` | — | — (wraps `OutboxService`) |
| `PushRuleRepository` | — | — (wraps `CallPushRuleManager`, `GlobalPushRuleManager`) |
| `StickerPackRepository` | `KoheraStickerPack` | `StickerPackResolver` (via `StickerPackService`) |
| `MessageSearchRepository` | — | — (wraps `MessageIndexerService`) |

`RoomRepository.rawRoom(roomId)` is a transitional `@Deprecated` method that
returns the raw SDK `Room?` for operations not yet abstracted (send message, set
power level). It will be removed as operations are moved to the repository.

## Domain-model conversion (resolvers)

Every SDK→Kohera-model conversion boundary is a `const class <Thing>Resolver`
living in `lib/data/resolvers/`. The resolver is the **only** file that imports
both the Matrix SDK and the Kohera domain model — everything below the boundary
(widgets, other services) consumes the SDK-free `Kohera*` type and never imports
`package:matrix/matrix.dart`.

**Resolvers are called from repositories, not from controllers or widgets.**
The repository layer (`lib/core/repositories/`) owns the resolver calls and
exposes domain models. Controllers and widgets consume domain models from
repositories — they should never call resolvers directly.

Conventions:

- Declare the class `const`-constructible (no state): `const RoomSummaryResolver();`.
- Expose the primary conversion as a `call` method so it is invokable inline as
  `const RoomSummaryResolver()(room, myUserId: id)`. Use a descriptively named
  method (`resolve`, `convert`, `fromEvent`) when the conversion is async or
  when the resolver bundles multiple operations (see `ReplyPreviewResolver`,
  `ReactionResolver`).
- Keep private helpers (`_toKoheraSticker`, `_lastEventPreview`) as private
  instance methods inside the class. `RegExp`/constant patterns stay
  `static final`.
- Free-standing `toKoheraX(...)` functions and `*_mapper.dart` files are
  deprecated — do not add new ones. Convert existing mappers to resolvers.

Existing compliant resolvers: `MessageDisplayResolver`, `MediaContentResolver`,
`ReactionResolver`, `ReplyPreviewResolver`, `RoomMemberListResolver`,
`RoomPermissionsResolver`, `StateEventResolver`, `ReadReceiptResolver`,
`UserSummaryResolver`, `RoomSummaryResolver`, `StickerPackResolver`,
`DeviceResolver`, `CallParticipantResolver` (still in features/calling/services/).

## Routing

GoRouter with named routes (`core/routing/`). Auth-aware redirects:
- Not logged in -> `/login`
- Logged in + E2EE backup needed -> `/e2ee-setup`
- Logged in on auth route -> `/`

Shell routes wrap the main layout (`HomeShell`). Full-page routes for login, registration, E2EE setup sit outside the shell.

## Responsive layout

`HomeShell` (`features/home/screens/`) manages three breakpoints:
- <720px: NarrowLayout (mobile, single column)
- 720-1100px: WideLayout (tablet, rail + list)
- >=1100px: WideLayout (desktop, rail + list + chat)

## E2EE

Three layers in `features/e2ee/`:
- `BootstrapController` (ChangeNotifier) -- state machine for key backup/cross-signing
- `BootstrapDriver` -- flow orchestration
- `BootstrapViews` -- stateless UI

Auto-unlock recovers keys from FlutterSecureStorage on startup via SyncService callback. See `docs/e2ee-flow.md` for state diagrams.

## Testing

Mockito with `@GenerateNiceMocks` annotations. Generated files: `*.mocks.dart`. Tests are under `test/` mirroring the lib structure: `services/`, `screens/`, `widgets/`, `e2e/`, `utils/`.

## Platform abstractions

Conditional imports for platform differences:
- `platform_info.dart` -> `.native.dart` / `.web.dart`
- `client_factory_native.dart` / `client_factory_web.dart`
- `file_native.dart` / `file_web.dart`

## CI

GitHub Actions (`.github/workflows/ci.yml`): analyze -> test (with coverage/Codecov) -> build-linux, build-macos. Docker multi-stage build for web deployment (Flutter web + Caddy).
