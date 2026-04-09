# Architecture

## Directory structure

```
lib/
  main.dart                         # App bootstrap, Provider tree
  core/
    extensions/
    models/                         # SpaceNode, UploadState, etc.
    routing/
      app_router.dart               # GoRouter with auth-aware redirects
      route_names.dart              # Route constants
    services/
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

MatrixService lazy-loads sub-services: AuthService, SyncService, SelectionService, ChatBackupService, UiaService.

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
