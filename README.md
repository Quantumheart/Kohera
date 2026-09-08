# Kohera

**Coherent threads, encrypted.**

Kohera is a retro-pixel Matrix chat client — coherent threads for encrypted messaging, voice/video calls, and spaces. Built with Flutter, runs on desktop, mobile, and web.

<!-- Hero: stacked brand lockup (assets/icons/kohera_lockup_stacked.svg) + themed screenshots (SNES / PICO-8 / Paper) — tracked in issue #811. -->

## Features

**Messaging**
- Rich text rendering (HTML, Markdown, syntax-highlighted code blocks)
- Message reactions, replies, editing, and deletion
- File and image uploads with progress tracking
- Link previews via OpenGraph
- @mention autocomplete with styled pills
- Typing indicators and read receipts
- Pinned messages
- In-room message search

**Voice & Video Calling**
- 1:1 and group calls over LiveKit
- Camera and microphone controls
- Screen sharing

**End-to-End Encryption**
- Cross-signing and device verification (SAS emoji)
- Key backup setup with recovery key
- Auto-unlock from secure storage on startup
- Backup status indicators and management

**Spaces & Rooms**
- Discord/Slack-style vertical space rail
- Create, edit, and manage spaces
- Room creation, DM creation, and invite flows
- Join any room or space by address (alias, room ID, or matrix.to link)
- Room details panel with member list and shared media
- Room admin controls

**Adaptive Layouts**

| Width | Layout |
| --- | --- |
| < 720 px | Space rail + room list; chat pushes full-screen |
| 720 – 1100 px | Space rail + room list + content pane (2-column) |
| &ge; 1100 px | Space rail + resizable room list + chat pane (3-column) |

**Other**
- Material You dynamic color theming with light/dark modes
- Theme and layout density picker
- SSO and reCAPTCHA support
- Local and desktop push notifications
- Device management

## Getting Started

### Prerequisites

- Flutter 3.47.0 (stable)
- Dart 3.11+

### Setup

```bash
git clone https://github.com/Quantumheart/Kohera.git
cd Kohera
flutter pub get
flutter run              # default device
flutter run -d linux     # Linux desktop
flutter run -d chrome    # Web
```

The app connects to any Matrix homeserver. Enter your homeserver URL, username, and password on the login screen (defaults to `matrix.org`).

### Building for Release

```bash
flutter build linux --release
flutter build windows --release
```

### Web Deployment (Docker)

Build and run the containerized web app locally:

```bash
docker build -t kohera-web .
docker run -p 8080:80 kohera-web
```

Then open `http://localhost:8080`.

Pull the latest release image from GHCR:

```bash
docker pull ghcr.io/quantumheart/kohera:latest
docker run -p 8080:80 ghcr.io/quantumheart/kohera:latest
```

## Architecture

Feature-based organization under `lib/`:

```
lib/
├── main.dart
├── core/
│   ├── brand/            # Wordmark, lockup, and brand assets
│   ├── extensions/       # Responsive device helpers
│   ├── media/            # Media handling helpers
│   ├── models/           # Space tree, upload state
│   ├── routing/          # GoRouter configuration
│   ├── services/         # AccountSession + sub_services (auth, sync, selection, UIA)
│   ├── state/            # Root ChangeNotifiers
│   ├── theme/            # Material You light/dark themes
│   └── utils/            # Emoji, colors, time formatting, syntax highlighting
├── data/
│   ├── repositories/     # Feature-facing data access
│   └── services/         # MatrixClientService (sole Matrix SDK client owner)
├── features/
│   ├── auth/             # Login, registration, SSO, reCAPTCHA
│   ├── calling/          # Voice/video calls (LiveKit)
│   ├── chat/             # Message timeline, compose bar, reactions, search
│   ├── e2ee/             # Bootstrap, device verification, key backup
│   ├── home/             # Adaptive shell layout, inbox
│   ├── notifications/    # Push and local notification handling
│   ├── rooms/            # Room list, details, creation, invites, admin
│   ├── settings/         # Preferences, devices, themes, notifications
│   ├── share_in/         # Inbound share handling
│   ├── spaces/           # Space rail, creation, management
│   └── whats_new/        # Release highlights
└── shared/widgets/       # Avatars, image viewer, section headers, speed dial
```

**State management:** Multiple `ChangeNotifier`s provided at the root via Provider. `MatrixClientService` (`data/services/`) is the sole owner of the Matrix SDK client — the sanctioned boundary the data layer depends on. `AccountSession` (`core/services/`) is the per-account composition root that builds the sub-service graph (AuthService, SyncService, SelectionService, ChatBackupService, UiaService, and the rest under `core/services/sub_services/`). `MatrixService` is a thin lifecycle coordinator that holds an `AccountSession`.

See [`docs/e2ee-flow.md`](docs/e2ee-flow.md) for E2EE state machine diagrams.

## Development

```bash
flutter analyze                                          # Lint
dart run build_runner build --delete-conflicting-outputs  # Generate mocks
flutter test                                             # Run all tests
flutter test test/services/matrix_service_test.dart      # Single test file
```

Mock generation must run before `flutter test` whenever `@GenerateMocks` annotations change.

### Commit Convention

Scope-prefixed commits — `scope: description`, where the scope names the area
of the codebase that changed (not the kind of change). This follows the style
used by Linux, Git, FreeBSD, and Go. A commitlint CI check enforces that a
lowercase scope prefix is present.

```
chat: fix jump-to-latest after search
calling: retry LiveKit join on ICE failure
e2ee: bootstrap key backup on first login
build: bump Flutter to 3.47.0
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full scope list.

## Key Dependencies

| Package | Purpose |
| --- | --- |
| `matrix` | Matrix protocol SDK |
| `flutter_vodozemac` / `vodozemac` | E2EE cryptography (Rust bindings) |
| `provider` | State management |
| `go_router` | Declarative routing |
| `dynamic_color` | Material You palette extraction |
| `cached_network_image` | Image caching |
| `flutter_secure_storage` | Encrypted credential storage |
| `sqflite` | Local database |
| `flutter_local_notifications` | Push notifications |
| `highlight` | Code syntax highlighting |

## CI/CD

GitHub Actions runs on push/PR to `master`:
1. **Analyze** — `flutter analyze` (plus an NSE import guard)
2. **Test** — mock generation + `flutter test --coverage`, with a coverage gate and Codecov upload
3. **Build** — smoke release builds for Linux, macOS, Android, and iOS
4. **Commitlint** — enforces the scope-prefixed commit convention

Releases are cut manually: run the **Prepare Release** workflow, pick a semver bump (patch/minor/major), and it writes `pubspec.yaml`, pushes a `v*` tag, and drafts a GitHub Release whose notes are generated from merged-PR labels (see [`.github/release.yml`](.github/release.yml)). The tag then drives the platform builds — Linux (tar.gz), Windows (Inno Setup installer), macOS (notarized zip), iOS (TestFlight), and Android (APK) — attaches them to the release, and un-drafts it. A separate workflow builds and pushes a web Docker image to `ghcr.io` and deploys it.

## Attribution

All emojis designed by [OpenMoji](https://openmoji.org/) – the open-source emoji and icon project. License: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
