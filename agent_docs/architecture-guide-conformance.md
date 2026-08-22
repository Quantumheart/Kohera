# Architecture vs. Flutter's App Architecture Guide

Assessment of Kohera's data-layer design against
[Flutter's recommended app architecture](https://docs.flutter.dev/app-architecture/guide),
recorded after the #1025 decomposition. This is a findings document, not a plan
of record — it captures where we conform, where we deviate, and the measured cost
of closing the gap.

## The guide in one line

Two data-layer tiers: **Repository** (single source of truth, holds app-wide
session state, returns domain models) over **Service** (stateless wrapper around
an external source). UI is **View → ViewModel**. Dependencies point downward only;
repositories are never aware of each other. UI state lives in view models.

## Scorecard

| Guide principle | Kohera | Verdict |
|---|---|---|
| Separation of concerns / layering | widgets → controllers (VM) → repositories → services | good |
| One repository per data type, single source of truth | 12 repositories in `data/repositories/` | strong |
| Repositories never aware of each other | repos depend on `MatrixClientService` + sub-services, never another repo | strong |
| Stateless service at the external boundary | `MatrixClientService` wraps the SDK `Client`, holds no state | textbook |
| Domain models, not SDK types, across the boundary | `data/resolvers/` map SDK → `Kohera*` models (documented escape hatches aside) | good |
| Views depend on view models, not the data layer | many widgets `context.watch` a repository or sub-service directly | partial |
| Services hold no state | the `sub_services/` are stateful `ChangeNotifier`s | deviates |
| App-wide session state lives in repositories | that state lives in the stateful sub-services | deviates |

Structural grade against the guide: **B+**. The core — repo-per-type, repo
independence, stateless SDK boundary, domain models — is exactly what the guide is
after and is what #1025 delivered.

## The three deviations

1. **Tier inversion (the substantive one).** Kohera has an extra data-layer tier
   the guide does not model: stateful per-account **sub-services**
   (`SelectionService`, `PresenceService`, `ChatBackupService`, `SyncService`,
   ...) sit between the repositories and the stateless `MatrixClientService`.
   By the guide, that session state belongs *in the repositories*, and the only
   thing below a repository should be a stateless service. Only
   `MatrixClientService` matches the guide's "Service."

   This is a deliberate deviation, not an accident: accounts outlive the widget
   tree. `ClientManager` holds N live per-account `MatrixService`s and drives
   background (inactive) accounts (pause/resume sync, logout, restore). The
   stateful tier is owned by `AccountSession` so a background account keeps a live
   service graph with no Provider tree above it. A pure repository tier, scoped to
   the active account by Provider, cannot express that.

2. **Views reach the data layer directly.** Sub-services are provided straight to
   the widget tree and watched without a view model in between (e.g.
   `SelectionService` across 10 widgets). Legitimate for a narrow shared
   UI-state notifier; a deviation from "View → ViewModel."

3. **Repositories re-expose the tier below them.** Repos carry pass-through
   getters (`repo.presence`, `repo.outbox`, `repo.stickerPacks`, ...). The same
   objects are also provided directly (deviation 2), so the source of truth is
   double-exposed.

## Cost of closing the gap

Three tiers of remediation were scoped. Measured coupling of the stateful
sub-services (LOC, files referencing them in `lib`, references in `test`):

| Sub-service | LOC | lib files | test refs | owning repo(s) |
|---|---:|---:|---:|---|
| SelectionService | 388 | 20 | 42 | Room + Space (+ 10 widgets) |
| PresenceService | 93 | 8 | 17 | User |
| ChatBackupService | 264 | 8 | 27 | KeyBackup + Auth |
| OutboxService | 379 | 3 | 10 | Outbox |
| StickerPackService | 358 | 11 | 18 | StickerPack |
| SpaceAccessService | 193 | 5 | 17 | Space |
| UiaService | 132 | 6 | 16 | Auth + KeyBackup |
| MegolmKeyMirror | 201 | 1 | 8 | KeyBackup |
| CallPushRuleManager | 94 | 2 | 9 | PushRule |
| GlobalPushRuleManager | 51 | 2 | 9 | PushRule |
| MessageIndexerService | 419 | 4 | 1 | Message + MessageSearch |
| SyncService | 113 | 1 | 11 | (coordinator) |
| AuthService | 690 | 1 | 15 | Auth |

Total in play: ~3,375 LOC, ~290 test references.

### Tier 1 — route service reads through repo facades (rejected)

Make no widget touch a stateful service directly; expose what it needs through
the owning repository. Evaluated against the real call sites, this does not
improve conformance:

- **StickerPackService** — the UI uses a rich API (`packsForRoom`,
  `importedEmojiGgSlugs`, `importPack`, and passes the service into a picker
  controller). Routing through `StickerPackRepository` means either a fat facade
  re-exporting the whole service, or `repo.stickerPacks.<x>` — which is the
  pass-through we are trying to remove. Net-negative; this is really a merge.
- **SelectionService** — a narrow notifier watched by 10 widgets. Routing them
  through `RoomRepository` broadens each widget's rebuild to every sync tick (a
  performance regression), and selection is UI state, not data.
- Only **ChatBackupService** (`dismissBanner`, watch) and **OutboxService**
  (watch-for-status) are cleanly routable, and the win there is marginal.

Conclusion: a repo facade over a still-stateful service launders access rather
than moving toward the guide. **Not worth doing.**

### Tier 2 — drop pass-through getters, reclassify Selection (executed)

Remove the repo getters that re-expose a service. Treat `SelectionService` and
`PresenceService` as the shared UI-state notifiers they already are (watched
directly / reached via `MatrixService`), and stop repos re-exposing them. Closes
deviation 3 and part of 2.

What shipped:

- **4 pure-shell repos deleted** — `OutboxRepository`, `PushRuleRepository`,
  `StickerPackRepository`, `MessageSearchRepository`. Each was a single
  pass-through getter with zero consumers beyond its own `main.dart` provider;
  the real UI already talks to the wrapped service directly (`matrix.outbox`,
  `matrix.globalPushRuleManager`, `context.read<StickerPackService>()`,
  `matrix.messageIndexer`).
- **Pass-through getters dropped** from the surviving repos: `user.presence`,
  `auth.auth`, `auth.uia`, `keyBackup.keyMirror`, `space.spaceAccess`,
  `message.messageIndexer`, and `room`'s selection forwarding (`selectedSpaceIds`,
  `selectedRoomId`, `selectSpace`, `selectRoom`, `toggleSpaceSelection`,
  `clearSpaceSelection`, `spaceTree`). Fields the repo still uses internally were
  kept; only the public re-exposure went.
- **Live consumers migrated** — `presence` (member sheet, space details, room
  details controller), `selectRoom` (member sheet, room details controller), and
  `getServerAuthCapabilities` (registration) now read the notifier directly or a
  new domain method on the repo.

Two corrections to the pre-execution estimate:

- `keyBackup.chatBackup` / `keyBackup.uia` were **not** dead — the E2EE bootstrap,
  recovery-key, and verification-listener flows used them. Rather than re-expose
  the service object, `KeyBackupRepository` now exposes the specific operations as
  domain methods (`runKeyRecovery`, `checkChatBackupStatus`, `getStoredRecoveryKey`,
  `storeRecoveryKey`, `clearCachedPassword`), which is the guide-aligned shape.
- The larger churn was test-side as predicted: the `remaining_repositories_test`
  delegation asserts and the deleted repos' tests were removed; suite dropped ~14
  now-meaningless delegation tests, no behavior tests lost. `flutter analyze`
  clean; suite green modulo the pre-existing `ink_sparkle.frag` shader-env flakes.

### Tier 3 — merge stateful services into repositories (a second epic)

The literal guide end-state. Fold each data-backing service's state into its
repository; `AccountSession` builds per-account *repositories* instead of
sub-services.

- **Group A — clean 1:1 merges:** Presence, Outbox, Sticker, SpaceAccess,
  MegolmKeyMirror, Call/GlobalPushRuleManager. ~1,370 LOC relocated, ~30 lib
  files rewired, ~88 test references. Mechanical; test rewrites dominate.
  Self-contained and finishable.
- **Group B — shared, cannot fully merge:** Selection (Room+Space, and it is UI
  state), ChatBackup (KeyBackup+Auth), Uia (Auth+KeyBackup), MessageIndexer
  (Message+MessageSearch). ~1,200 LOC. Each forces a lose-lose: repo→repo
  awareness (a guide violation), duplicated state, or merging the two repos.
  The pure end-state is unreachable without further consolidation.
- **Group C — correctly stays a service:** SyncService (background loop),
  AuthService (login/restore/logout orchestration). Behavior, not repo state.
  Leave both.
- **Plus** reshaping `AccountSession` / `ClientManager` / `main.dart` to build
  and expose per-account repositories, which re-enters the multi-account
  lifecycle — the highest-risk area from #1025.

Scale: **~50 lib files + ~40–60 test files, ~2,500 LOC relocated** — comparable
to #1025 itself (134 files) — and it **cannot complete**, because Group B does not
fold. Payoff is aesthetic (fewer concepts, fewer hops, smaller mocks); no new
capability.

## Recommendation

The substantive wins the guide targets are already banked. The remaining gap is
the stateful sub-service tier, which exists for a real reason (accounts outlive
the widget tree) the guide does not model.

- **Worth doing:** Tier 2 (drop dead pass-through getters, reclassify Selection
  as UI state). Low cost, real tidy-up.
- **Optional:** Tier 3 **Group A only** as a standalone chunk if the team values
  guide legibility (~1,370 LOC, ~30 files, ~88 test refs).
- **Not worth doing:** Tier 1 (laundering) and Tier 3 Group B (does not fold
  without repo mergers or repo→repo coupling).
- **Best framing for deviation 1:** document it rather than refactor it —
  Kohera's data layer has two tiers, *stateful per-account services*
  (`AccountSession`-owned, so background accounts stay live) and a *stateless SDK
  boundary* (`MatrixClientService`) — because accounts outlive the widget tree.
