# Recovery Plan: sub-services → repositories

## Goal (the thing wanted from the start)

1. Thin, stateless `MatrixClientService` SDK boundary.
2. The stateful per-account tier lives as **repositories**, not "sub-services".
3. Per-account composition root (`AccountSession`) builds that tier outside the
   widget tree so multi-account survives.

## Status

- **(1) done** — `lib/data/services/matrix_client_service.dart`, 6 loc, `const`.
- **(3) done** — `lib/core/services/account_session.dart` builds the 15-node
  per-account graph; `ClientManager` holds one per account; `MatrixService` is a
  thin coordinator.
- **(2) open** — this plan.

## Why (2) is not a flat rename

The branch scaffolded the repository layer on a **domain** axis (Room, User,
Message, Auth, Space, KeyBackup, Push, Media) and wired every feature onto it. The
sub-services sit on a **concern** axis (Selection, Presence, Sync, Backup, Uia…).
They do not map 1:1:

- One concern serves several domains (`SelectionService` → Room *and* Space;
  `ChatBackupService`/`UiaService` → Auth *and* KeyBackup).
- Several sub-services are **private collaborators**, not top-level anything
  (`backup_version_manager`, `key_backup_signer` under ChatBackup;
  `outbox_database`, `outbox_connectivity` under Outbox).
- Two are **not data** at all (`SyncService` = background loop; `AuthService` =
  login/logout orchestration).

So "rename `sub_services/` → `repositories/`" would produce concern-named repos
colliding with the existing domain repos. The correct move is: **move each
service's state into its owning domain repository**, and let `AccountSession` build
the (now stateful) repositories instead of services.

## Disposition of the 15 AccountSession-built nodes

| Node | loc | Destination | Kind of work |
|---|---:|---|---|
| `MegolmKeyMirror` | 201 | → **KeyBackupRepository** | **rename/move** — 1 internal consumer, 0 UI |
| `MessageIndexerService` | 419 | → **MessageRepository** (`MessageSearchDatabase` stays as its stateless source) | **rename/move** — also fixes the `data/services/` misfit; 4 consumers repoint |
| `SpaceAccessService` | 193 | → **SpaceRepository** | move + repoint 4 UI consumers |
| `PresenceService` | 93 | → **UserRepository** | move + repoint 6 UI consumers |
| `OutboxService` (+db, +connectivity) | 379 | → **OutboxRepository** (recreate; deleted as shell in Tier 2) | move + repoint 1 UI consumer |
| `StickerPackService` | 358 | → **StickerPackRepository** (recreate) | move + repoint ~11 consumers (rich API) |
| `CallPushRuleManager` + `GlobalPushRuleManager` | 94+51 | → **PushRuleRepository** (recreate) | move + repoint 2 UI consumers |
| `ChatBackupService` (+backup_version_manager, +key_backup_signer) | 264 | → **KeyBackupRepository**; Auth's logout-cleanup slice → use-case | move + resolve Auth sharing |
| `SelectionService` | 388 | → **presentation** (shared UI/nav state; not a repo) | relocate out of `data/`; repoint ~10 widgets |
| `UiaService` | 132 | → **presentation/interaction** (shared Auth+KeyBackup) | relocate; repoint |
| `SyncService` | 113 | stays a service (app lifecycle loop) | none |
| `AuthService` | 690 | orchestration → **AuthRepository** or a use-case layer | judgement call |
| `ClientAvatarResolver` / `ClientMediaResolver` | — | already stateless services under Media | none (naming cleanup only) |

## Three buckets of effort

**A — mechanical rename/move (start here).** State-only, single-owner, few or no
external consumers. Move the service's fields+methods into its repo, delete the
service, point `AccountSession` at the repo, repoint the handful of consumers,
regen mocks.
- `MegolmKeyMirror` → KeyBackupRepository (cleanest: 1 internal consumer)
- `MessageIndexerService` → MessageRepository (high value: kills the
  `data/services/` misfit; `MessageSearchDatabase` remains the stateless source)
- `SpaceAccessService` → SpaceRepository
- `PresenceService` → UserRepository

**B — recreate a stateful repo + migrate direct-service UI.** These lost their
shell repo in Tier 2 and the UI now reads the service directly.
- `OutboxService` → OutboxRepository (1 consumer)
- `CallPushRuleManager`+`GlobalPushRuleManager` → PushRuleRepository (2 consumers)
- `StickerPackService` → StickerPackRepository (~11 consumers, rich API — largest)

**C — genuine decisions, do last (or never).**
- `SelectionService` → leaves `data/` for presentation (shared + UI state).
- `UiaService` → presentation/interaction (shared).
- `ChatBackupService` → KeyBackupRepository, but Auth's logout-cleanup needs a
  use-case/interactor so no repo→repo dependency appears.
- `AuthService` orchestration → AuthRepository vs use-case layer.
- `SyncService` → leave as an app-lifecycle service.

## Sequencing

1. Bucket A, one service per commit (`refactor: fold X state into YRepository`),
   green after each. Lowest risk, immediate legibility win. `MessageIndexer`
   first — biggest payoff, self-contained.
2. Bucket B, one repo per commit. Recreate the stateful repo, move UI off the raw
   service provider onto it.
3. Bucket C only if the team wants full guide adherence; each item is a design
   decision, not a move.

After A+B: `sub_services/` holds only `sync`, `auth`, and the shared
`selection`/`uia`/`chatBackup` — i.e. the genuinely-not-a-repo residue. At that
point the tier is honestly named: repositories hold data state, services hold
behavior/orchestration, presentation holds UI state.

## What does NOT need touching

`MatrixClientService`, `AccountSession`, `ClientManager`, and the domain repos'
existing public API (features already consume them). This is additive state-motion
into repos that already exist (bucket A) or are recreated (bucket B), plus the
`AccountSession` construction swap — not another 402-file feature migration.
