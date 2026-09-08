# Contributing to Kohera

Thanks for contributing! Kohera is a Flutter Matrix chat client. This guide
covers how to get set up, the conventions we follow, and how to file issues and
open pull requests.

## Getting started

```bash
flutter pub get                                           # Install dependencies
dart run build_runner build --delete-conflicting-outputs  # Generate mocks
flutter analyze                                           # Lint
flutter test                                              # Run all tests
flutter run -d linux                                      # Run on Linux
```

Run `build_runner` before `flutter test` whenever a test's `@GenerateNiceMocks`
annotations change, or when you touch a class that mocks reference. CI
regenerates mocks before running tests, so generated `*.mocks.dart` files do not
need to be committed.

## Project layout

Feature-based under `lib/`: `core/` (services, routing, theme, state, utils),
`data/` (repositories, services), `features/` (auth, calling, chat, e2ee, home,
notifications, rooms, settings, share_in, spaces, whats_new), and
`shared/widgets/`. State is managed with Provider (`ChangeNotifier`s) wired at
the root. `MatrixClientService` (`data/services/`) is the sole owner of the
`matrix` SDK client; `AccountSession` (`core/services/`) builds the sub-service
graph under `core/services/sub_services/`, and `MatrixService` is a thin
lifecycle coordinator holding an `AccountSession`.

See `agent_docs/architecture.md` for the detailed architecture and
`docs/e2ee-flow.md` for the E2EE state machine.

## Conventions

- **Commits:** scope-prefixed, `scope: description`, enforced by a commitlint
  CI check. The scope names the area of the change, not the kind of change — we
  do not use Conventional Commit types like `feat`/`fix`/`chore`. Projects such
  as Linux, Git, FreeBSD, and Go use this style. Example: `chat: add presence
  dot`.
  - The scope is free-form, not a fixed enum — pick the most specific area the
    change touches. Common scopes, roughly mirroring the tree:
    - **Features** (`lib/features/`): `auth`, `calling`, `chat`, `e2ee`,
      `home`, `notifications`, `rooms`, `settings`, `share_in`, `spaces`,
      `whats_new`.
    - **Cross-cutting** (`lib/core/`, `lib/data/`, `lib/shared/`): `core`,
      `data`, `shared`, `routing`, `theme`, `media`, `brand`.
    - **Infra / non-code**: `build`, `ci`, `deps`, `release`, `docs`, `test`.
    - When a change spans several areas, name the dominant one; when none fits,
      coin a short lowercase scope.
  - In the commit **body**, avoid lines that start with `Word:` and avoid inline
    `#123` references — the commitlint parser treats them as footer trailers and
    fails the `footer-leading-blank` rule. Put issue references only in a footer
    after a blank line: `Refs #123`, `Closes #123`.
- **Logging:** prefix every log with `[Kohera]`, e.g.
  `debugPrint('[Kohera] ...')`.
- **Comments:** code should be self-descriptive; do not add explanatory
  comments. Section markers (`// ── Section name ──────`) are the only
  exception.
- **Tests:** add or update tests for every behavioural change. Keep
  `flutter analyze` clean.

## Filing issues

Issues use templates in `.github/ISSUE_TEMPLATE/` (blank issues are disabled):

- **Epic** — large work split into dependent child issues. List the slices in
  dependency order; each slice should be independently shippable.
- **Feature / enhancement** — fill Goal, Scope, Out of scope, and testable
  Acceptance criteria.
- **Bug report** — what happened, expected behaviour, steps to reproduce,
  environment, and `[Kohera]` logs (redact tokens/IDs).

## Pull requests

- Branch from and target `master`. Do not base a PR on another feature branch
  unless a stacked PR is explicitly requested.
- Use a branch name like `chat/123-short-description`, prefixed with the scope
  the work touches.
- Fill out the pull request template (`.github/PULL_REQUEST_TEMPLATE.md`):
  summary, changes, testing, linked issues (`Closes #N` for the issue, `Refs #N`
  for the epic), and the checklist.
- Before pushing: `flutter analyze` is clean and `flutter test` passes (run
  `build_runner` first if mocks changed).
- Keep PRs focused on one slice; open follow-ups for out-of-scope work.

## Code review

Reviews look for correctness, adherence to the conventions above, and test
coverage. Address review comments with follow-up commits on the same branch;
keep the history readable.
