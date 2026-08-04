# Test Coverage Gap Analysis

**Branch:** `chore/test-coverage-gap-analysis` (from `origin/master` @ `f1c83d56`)
**Date:** generated from a clean `flutter test --coverage` run (2550 tests, all passing)
**Coverage gate:** `flutter_ci_guard --min-coverage 80` (`.github/workflows/ci.yml`)

## Headline numbers

| Metric | Value |
|---|---|
| Tests run | 2550 (all pass) |
| lib files with coverage data | 386 |
| lib files total (`.dart`) | 462 |
| Instrumented lines (lib/) | 23 837 |
| Covered lines (lib/) | 16 885 |
| **Overall lib/ coverage** | **70.84 %** |
| Required by CI gate | 80 % |
| **Status** | ❌ **FAIL — gate would fail in CI** |
| Lines still needed to reach 80 % | **~2 184** |

> Note: the gate runs with zero exclude rules (`exclude files: 0`), so the 70.84 %
> figure is the real number CI will evaluate. The deficit of ~2 184 covered lines
> is the practical target for closing the gap.
>
> Important: files with *no coverage record at all* (e.g. the generated
> `openmoji_manifest.g.dart`, ~4 497 lines) are **already absent from the lcov
> denominator** — `flutter test --coverage` only instruments files that are
> transitively imported by a test. So excluding generated files from the gate
> would **not** change the headline number; the only way to raise it is to write
> tests that cover the ~2 184 currently-uncovered *instrumented* lines.

## Per-directory coverage (worst first)

| Directory | Cov % | Covered / Lines |
|---|---:|---:|
| `lib/features/home` | 46.5 % | 168 / 361 |
| `lib/features/e2ee` | 61.9 % | 665 / 1075 |
| `lib/features/notifications` | 62.5 % | 526 / 841 |
| `lib/features/settings` | 68.8 % | 734 / 1067 |
| `lib/features/chat` | 68.9 % | 4646 / 6745 |
| `lib/core` | 69.8 % | 2511 / 3598 |
| `lib/features/whats_new` | 71.9 % | 164 / 228 |
| `lib/features/spaces` | 73.4 % | 1315 / 1791 |
| `lib/features/rooms` | 73.7 % | 3599 / 4881 |
| `lib/features/calling` | 73.9 % | 845 / 1143 |
| `lib/features/auth` | 80.5 % | 699 / 868 |
| `lib/shared` | 81.7 % | 808 / 989 |
| `lib/features/share_in` | 82.0 % | 205 / 250 |

**Top opportunity areas:** `home` (46.5 %), `e2ee` (61.9 %), `notifications`
(62.5 %), `settings` (68.8 %), and `chat` (68.9 % — also the largest absolute
block at 6 745 lines, so even small % gains move the needle).

## Category A — Files at 0 % coverage *and present in lcov* (932 lines)

These files are loaded/instrumented but **no test exercises any line**.
Highest-leverage targets (sorted by size):

| File | Lines |
|---|---:|
| `lib/features/chat/screens/thread_screen.dart` | 129 |
| `lib/core/media/mobile/mobile_kohera_video_controller.dart` | 87 |
| `lib/features/chat/screens/thread_list_screen.dart` | 82 |
| `lib/features/chat/widgets/forward_message_dialog.dart` | 65 |
| `lib/core/services/emoji_gg_service.dart` | 64 |
| `lib/features/chat/widgets/sticker_message_item.dart` | 55 |
| `lib/core/media/mobile/mobile_kohera_player.dart` | 53 |
| `lib/features/chat/widgets/emoji_suggestion_list.dart` | 47 |
| `lib/shared/widgets/mxc_image.dart` | 44 |
| `lib/core/media/media_kit/media_kit_kohera_video_controller.dart` | 38 |
| `lib/features/chat/services/thread_reply_loader.dart` | 32 |
| `lib/features/home/widgets/inbox/invitations_view.dart` | 32 |
| `lib/core/media/media_kit/media_kit_kohera_player.dart` | 31 |
| `lib/features/e2ee/widgets/setup/setup_key_card.dart` | 31 |
| `lib/features/chat/widgets/reply_preview_host.dart` | 29 |
| `lib/core/models/emoji_gg_pack.dart` | 25 |
| `lib/features/e2ee/widgets/key_verification_inline.dart` | 23 |
| `lib/features/e2ee/widgets/setup/setup_unlock_section.dart` | 20 |
| `lib/features/chat/widgets/inline_image_preview.dart` | 17 |
| `lib/features/e2ee/widgets/setup/setup_verify_section.dart` | 15 |
| `lib/core/services/client_factory_native.dart` | 13 |

## Category B — Files with *no coverage record at all* (not transitively tested)

76 lib files never appear in `lcov.info` — meaning no test even imports them,
> so they are **not counted in the 23 837-line denominator**. Writing tests that
> import them will *add* their lines to the denominator (so % can dip before it
> rises as those lines get covered). Breakdown:

- **Generated (no test value):** 1 file, ~4 497 lines —
  `lib/core/utils/openmoji_manifest.g.dart`. Leave untested; it never enters the
  denominator. Optionally add to `flutter_ci_guard` excludes for safety.
- **Platform-conditional stubs (`_web`/`_native`):** 19 files, ~404 lines —
  cannot be covered on a single host platform; treat as out of scope for the
  Linux CI runner (e.g. `*_web.dart`, `*_native.dart`, `web_push_service`).
  These also never enter the host denominator. Good candidates for an explicit
  exclude rule so a future web CI job can cover them separately.
- **Genuinely untested source (real targets):** 56 files, ~4 386 lines.
  Highest-leverage (excluding <5-line trivial facade files):

| File | ~Lines |
|---|---:|
| `lib/main.dart` | 430 |
| `lib/features/settings/screens/notification_settings_screen.dart` | 380 |
| `lib/features/settings/screens/emoji_gg_browse_screen.dart` | 373 |
| `lib/features/settings/screens/sticker_packs_screen.dart` | 372 |
| `lib/core/routing/app_router.dart` | 305 |
| `lib/features/notifications/services/push_service.dart` | 246 |
| `lib/features/settings/widgets/custom_theme_editor.dart` | 245 |
| `lib/features/notifications/widgets/notification_lifecycle_observer.dart` | 227 |
| `lib/features/notifications/services/web_push_service.dart` | 209 |
| `lib/features/e2ee/screens/show_recovery_key_screen.dart` | 178 |
| `lib/features/settings/screens/ignored_users_screen.dart` | 174 |
| `lib/features/calling/widgets/incoming_call_overlay.dart` | 170 |
| `lib/features/settings/screens/appearance_screen.dart` | 110 |
| `lib/features/calling/screens/call_screen.dart` | 78 |
| `lib/core/routing/route_names.dart` | 68 |
| `lib/features/calling/models/call_state.dart` | 50 |

The remaining ~40 files in this bucket are 1–2 line conditional facade/export
files (e.g. `client_factory.dart`, `kohera_player_factory.dart`) that delegate
to a platform impl — not worth direct unit tests.

## Category C — Low-but-nonzero coverage (partial gaps)

Files with real size that are well under threshold (top of the long tail):

| File | Cov % | Covered / Lines |
|---|---:|---:|
| `lib/core/theme/custom_theme.dart` | 1.6 % | 1 / 64 |
| `lib/features/chat/services/reaction_resolver.dart` | 3.4 % | 1 / 29 |
| `lib/features/chat/widgets/long_press_wrapper.dart` | 4.2 % | 2 / 48 |
| `lib/features/notifications/services/apns_push_service.dart` | 4.5 % | 5 / 111 |
| `lib/shared/models/kohera_room_summary.dart` | 6.7 % | 2 / 30 |
| `lib/core/services/sub_services/megolm_key_mirror.dart` | 8.4 % | 8 / 95 |
| `lib/core/services/sub_services/outbox_database.dart` | 10.9 % | 6 / 55 |
| `lib/core/utils/media_cache.dart` | 13.6 % | 9 / 66 |
| `lib/features/settings/widgets/account_switcher.dart` | 15.4 % | 4 / 26 |
| `lib/features/chat/services/thread_roots_service.dart` | 16.7 % | 5 / 30 |
| `lib/features/rooms/widgets/room_list.dart` | 20.9 % | 91 / 435 |
| `lib/features/calling/services/push_to_talk_service.dart` | 21.7 % | 10 / 46 |
| `lib/features/home/widgets/mobile_space_drawer.dart` | 24.6 % | 31 / 126 |
| `lib/core/services/sub_services/key_backup_signer.dart` | 25.0 % | 9 / 36 |
| `lib/features/share_in/services/share_intake_controller.dart` | 32.5 % | 13 / 40 |
| `lib/features/chat/screens/chat_screen.dart` | 36.5 % | 237 / 649 |
| `lib/core/services/sub_services/uia_service.dart` | 36.7 % | 22 / 60 |
| `lib/features/chat/widgets/irc_message_tile.dart` | 38.6 % | 61 / 158 |
| `lib/features/chat/widgets/message_list_view.dart` | 40.4 % | 95 / 235 |
| `lib/features/e2ee/widgets/qr_verification_views.dart` | 41.9 % | 18 / 43 |

## Recommended action plan (priority order)

1. **Add tests for the 0%-coverage *instrumented* files (Category A, 932 lines).**
   These are already in the denominator but fully uncovered, so every line
   covered here is a direct 1:1 reduction of the 2 184-line deficit. Start with
   the thread feature and the emoji/sticker widgets/services.
2. **Lift the big partial gaps (Category C).** `chat_screen.dart` alone has 412
   uncovered lines — covering even a third of it (~140 lines) is a big win.
   `room_list.dart` (344 uncovered), `mobile_space_drawer.dart` (95 uncovered),
   `message_list_view.dart` (140 uncovered) and `irc_message_tile.dart` (97
   uncovered) are next.
3. **Core service-layer unit tests with mocks** — `megolm_key_mirror` (87
   uncovered), `outbox_database` (49), `media_cache` (57), `uia_service` (38),
   `key_backup_signer` (27), `apns_push_service` (106). These are pure logic,
   high ROI, mockable.
4. **Bring `lib/main.dart` and routing into the test graph** (Category B real
   targets) — importing them adds ~800 lines to the denominator, so pair the
   import with real assertions to avoid a temporary dip.
5. **Settings + E2EE screen widget tests** (Category B real targets) — coherent,
   low-risk widget-test batches.
7. **Routing** — `app_router.dart` (305) and `route_names.dart` (68) have no
   coverage; route-configuration tests are cheap and catch regressions.
8. **Optionally add `flutter_ci_guard` exclude rules** for `*_web.dart` /
   `*_native.dart` platform stubs so the gate ignores platform code that the
   Linux runner structurally cannot cover (cosmetic; they're already absent
   from the denominator today).

## Files explicitly out of scope for host-platform unit coverage

Platform-conditional implementations that cannot be exercised on the Linux CI
runner and should be excluded or covered via integration tests on their target
platform: the 19 `*_web.dart` / `*_native.dart` stubs (~404 lines), plus the
mobile-specific media controllers (`mobile_kohera_player.dart`,
`mobile_kohera_video_controller.dart`) which require a mobile runtime.

---

*Generated by `flutter test --coverage` + `coverage/lcov.info` analysis on
`chore/test-coverage-gap-analysis`. Re-run with `python3 tool/coverage_analysis.py`
(see committed script) to refresh after adding tests.*