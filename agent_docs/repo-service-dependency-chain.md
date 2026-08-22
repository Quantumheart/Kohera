# Repository → Service Dependency Chain

Snapshot of the data-layer dependency graph after the #1025 decomposition and the
Tier 2 cleanup (dead pass-through getters dropped, 4 shell repos deleted). Edges
are taken from the provider `create` calls in `lib/main.dart` and the sub-service
construction in `lib/core/services/account_session.dart`.

## Diagram

```
 ROLE:  stateless facade        stateful sub-services         stateless boundary   stateful source
        (data/repositories)     (core/services/sub_services)  (data/services)      (SDK / sqlite)

┌───────────────────┐
│ AuthRepository     ─────┬────────────▶ AuthService ─────┐
│                    ─────┼────────────▶ ChatBackupService ┤
└───────────────────┘     └───────────────────────────────┼──▶┌──────────────────┐
┌───────────────────┐                                      │   │                  │
│ KeyBackupRepository ────┬────────────▶ ChatBackupService ┤   │ MatrixClient     │      ┌───────────┐
│                    ─────┼────────────▶ UiaService ────────┤   │ Service          │─────▶│ SDK Client│
└───────────────────┘     └────────────────────────────────┤   │ (const, 6 loc)   │      │ (rooms,   │
┌───────────────────┐                                       │   │                  │      │  timeline,│
│ RoomRepository     ─────┬────────────▶ SelectionService ──┤   └──────────────────┘      │  keys)    │
└───────────────────┘     └─────────────────────────────────┤            ▲                └───────────┘
┌───────────────────┐                                        │            │
│ SpaceRepository    ─────┬────────────▶ SelectionService ───┤            │ every sub-service
│                    ─────┼────────────▶ SpaceAccessService ─┤            │ holds a
└───────────────────┘     └─────────────────────────────────┤            │ MatrixClientService
┌───────────────────┐                                        │            │
│ UserRepository     ──────────────────────────────(direct)──┤────────────┘
└───────────────────┘                                        │
┌───────────────────┐                                        │
│ PushRepository     ──────────────────────────────(direct)──┤
└───────────────────┘                                        │
┌───────────────────┐                                        │
│ MessageRepository  ─────┬─────────────────────────(direct)─┘
│                    ─────┴────▶ MessageIndexerService ──┬──▶ MatrixClientService ─▶ SDK Client
└───────────────────┘         (STATEFUL, in data/svc!)  └──▶ MessageSearchDatabase ─▶ sqlite
┌───────────────────┐
│ MediaRepository    ─────┬────▶ AvatarResolver (iface) ─▶ ClientAvatarResolver ─┐
│                    ─────┴────▶ MediaResolver  (iface) ─▶ ClientMediaResolver ──┴─▶ SDK Client
└───────────────────┘             (data/services)          (core/services)
```

## Per-repository edges

| Repository | Depends on |
|---|---|
| AuthRepository | MatrixClientService, AuthService, ChatBackupService |
| KeyBackupRepository | MatrixClientService, ChatBackupService, UiaService |
| RoomRepository | MatrixClientService, SelectionService |
| SpaceRepository | MatrixClientService, SelectionService, SpaceAccessService |
| UserRepository | MatrixClientService |
| PushRepository | MatrixClientService |
| MessageRepository | MatrixClientService, MessageIndexerService |
| MediaRepository | AvatarResolver, MediaResolver (interfaces) |

## Reading the graph

- **Every repo is stateless** (left column) and depends *downward only* — never on
  another repo. Matches the guide's "repositories are never aware of each other."
- **Fan-in:** all 8 repos and all sub-services collapse onto the single
  `MatrixClientService`, the only clean stateless SDK boundary. Textbook Service.
- **The stateful tier is the middle column** (`sub_services/`). This is deviation 1
  from `architecture-guide-conformance.md`: the guide wants that box merged *into*
  the repository on its left, so the repo becomes the stateful source of truth.
- **The repos are converters + notification relays**, not state owners. State lives
  in the middle column (sub-services) and in the SDK `Client` on the right.

## Two anomalies inside `data/services/`

1. **MessageIndexerService is a stateful sub-service in the wrong folder.** It
   `extends ChangeNotifier` and owns an in-memory index, per-room progress, a sync
   subscription, and a background drain loop — behaving exactly like a middle-column
   sub-service, yet it lives in `data/services/` instead of `core/services/sub_services/`
   alongside its 13 peers. It is also the only node with a *second* stateless source
   (`MessageSearchDatabase → sqlite`). Tier 2 deleted `MessageSearchRepository`, so
   the indexer is now Message-only and its guide-true fold (state up into
   `MessageRepository`, `MessageSearchDatabase` staying as the stateless source) is
   no longer blocked.

2. **MediaRepository's services are interfaces split from their impls.**
   `AvatarResolver` / `MediaResolver` are `abstract interface class` contracts in
   `data/services/`, but the concrete `ClientAvatarResolver` / `ClientMediaResolver`
   live one layer out in `core/services/`. The `*Resolver` suffix also collides with
   `data/resolvers/`, which holds a different animal — const, stateless SDK→domain
   mappers (`RoomSummaryResolver`, etc.). Same name, two folders, two meanings.

## Net

A clean, downward-only DAG with correct repo independence and a single stateless SDK
boundary — but with an extra stateful tier the guide does not model (deviation 1) and
the two filing anomalies above sitting inside `data/services/`.
