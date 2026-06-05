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

Feature-based under `lib/`: `core/` (services, routing, theme, utils),
`features/` (auth, calling, chat, e2ee, home, notifications, rooms, settings,
spaces), and `shared/widgets/`. State is managed with Provider
(`ChangeNotifier`s) wired at the root; `MatrixService` wraps the `matrix` SDK
client, with sub-services under `core/services/sub_services/`.

See `agent_docs/architecture.md` for the detailed architecture and
`docs/e2ee-flow.md` for the E2EE state machine.

## Conventions

- **Commits:** Conventional Commits, enforced by a commitlint CI check. Allowed
  types: `feat`, `fix`, `perf`, `refactor`, `style`, `docs`, `test`, `chore`,
  `ci`, `build`, `revert`. Reference the issue in the subject scope when it
  helps, e.g. `feat(#123): add presence dot`.
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
- Use a branch name like `feat/123-short-description` or
  `fix/123-short-description`.
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
