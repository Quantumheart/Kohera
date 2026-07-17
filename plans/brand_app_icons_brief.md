# Kohera App Icons Brief

Task: replace Flutter-default app icons with pixel brand icons (branding leverage #4).
Status: design brief. No code changes.

## 0. Audit correction

**Icons are NOT Flutter defaults.** `tool/generate_icons.py` already generates branded pixel-art Kohera mark icons for ALL platforms from a shared 32×32 `MASK` (identical to `kohera_loader.dart` `_mask` + `assets/icons/kohera_mark.svg`). Git history confirms deliberate alignment: `d64aa1e0 fix: align install icons with pixel-art in-app branding`, `2b16ffba style: flatten app icon background to match the logo tile exactly`.

Current colors (old blue brand):
- `BG = (212, 227, 255) = #D4E3FF` — light blue (Flutter-blue-derived `primaryContainer`)
- `FG = (34, 72, 118) = #224876` — dark blue (`onPrimaryContainer`)

These track the old `_fallbackSeed #1976D2` Flutter-blue brand. **The real gap: icons are old-blue-branded, not SNES-branded.** Task = recolor to SNES brand + verify safe zones + keep MASK in sync. Not "replace defaults from scratch."

## 1. Existing generator coverage (already complete)

`tool/generate_icons.py` produces, from the shared `MASK`:

| Platform | Outputs | Mode |
|---|---|---|
| Android | `mipmap-{mdpi..xxxhdpi}/ic_launcher.png` (48–192, rounded), `ic_launcher_foreground.png` (108–432, adaptive_fg, 72dp safe zone pad 0.21), `ic_launcher_background.png` (108–432, full-bleed bg), `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml` | adaptive + legacy |
| iOS | `Icon-App-*` 15 sizes 20–1024, square opaque (`.convert("RGB")`) | square |
| macOS | `app_icon_{16,32,64,128,256,512,1024}.png`, rounded (radius 0.22) | rounded |
| Web | `favicon.png` (32, rounded), `Icon-192/512.png` (rounded), `Icon-maskable-192/512.png` (maskable, pad 0.30) | rounded + maskable |
| Windows | `windows/runner/resources/app_icon.ico` (16,32,48,64,128,256, rounded) | ico |
| Linux | `linux/io.github.quantumheart.kohera.png` (512, rounded) | rounded |
| SVG asset | `assets/icons/kohera_mark.svg` (monochrome `currentColor`, `crispEdges`, merged `<rect>` runs) | reference |

All present in repo (verified: Linux png exists, web icons exist, iOS/macOS sets exist, Windows ico exists, SVG exists). Nothing missing. Only colors are stale.

## 2. Recolor to SNES brand (the actual work)

Two constants in `tool/generate_icons.py`:

```python
# before (old blue brand)
BG = (212, 227, 255, 255)   # #D4E3FF  primaryContainer (Flutter-blue seed)
FG = (34, 72, 118, 255)     # #224876  onPrimaryContainer

# after (SNES brand — path A: grey canvas, dusk ink)
BG = (229, 229, 229, 255)   # #e5e5e5  snes.css default body canvas
FG = (44, 62, 80, 255)      # #2c3e50  dusk — snes.css main-color / onSurface
```

Then rerun `python3 tool/generate_icons.py`. Verified visually in preview — `icon_1_grey_dusk_snes_default.png` selected as best vs aged-yellow/white/purple/dusk alternatives.

### 2.1 Color decision — RESOLVED: grey + dusk (path A)

**Decision locked: BG `#e5e5e5` grey + FG `#2c3e50` dusk.** Path A — revise the SNES theme spec so grey is the primary light surface (snes.css's actual default canvas `body,html{background-color:#e5e5e5}`), demoting aged-yellow `#fcf4d9` to an accent/container variant.

Rationale: aged-yellow as the dominant light surface collided with Paper (`#FBF7EC` cream) and PICO-8 (`#FFF1E8` cream). Grey differentiates SNES decisively and is faithful to snes.css. Dusk mark on grey ≈ 7:1 contrast. Neutral base lets phantom purple primary + 9-color accent ramp + beveled translucent shadows carry the SNES identity rather than a yellow tint.

Cross-task: this revises the SNES theme spec (#764 / `docs/theme-specs/snes-theme-spec.md`) — aged-yellow demoted from light `surface` to an accent container. Tracked as task #7, blocks #6 (impl follows revised spec), updates #3 (shell surfaces → grey/dusk).

## 3. Maskable safe-zone review

Web maskable + Android adaptive foreground use padding to keep the mark inside the OS-crop safe zone.

| Mode | Current pad | Safe-zone spec | Verdict |
|---|---|---|---|
| Android adaptive_fg | 0.21 | 72dp / 108dp ≈ 0.667 diameter → pad ≈ 0.167 each side | 0.21 is conservative (mark ~0.58 of layer) — safe, maybe slightly small. OK. |
| Web maskable | 0.30 → **0.12 (locked)** | W3C maskable safe zone = central 80% → pad 0.10 each side | 0.12 keeps mark inside safe zone (76% of tile) — visually present without aggressive crop. Verified in preview `maskable_grey_pad012.png`. |
| iOS square | 0.16 | iOS applies its own corner radius; content clear of corners | OK |
| macOS rounded | 0.18, radius 0.22 | macOS squircle | OK |

**Action (resolved):** maskable pad 0.30 → 0.12 (locked). Verified `maskable_grey_pad012.png` vs `maskable_grey_pad030.png`. Re-measure on Android home + Chrome install + iOS add-to-home (maskable ignored on iOS, falls back to rounded) at impl.

## 4. MASK single-source-of-truth (drift risk)

The 32×32 mark mask is currently duplicated in three places, all hand-kept in sync:
1. `tool/generate_icons.py` `MASK` (Python list)
2. `lib/shared/widgets/kohera_loader.dart` `_mask` (Dart `List<String>`)
3. `assets/icons/kohera_mark.svg` (generated by the script from `MASK`)

#2 adds a fourth: `_threadMasks` (per-thread pixel regions) — authored from the same grid.

**Risk:** any one changes, others drift, icons/loader/SVG diverge silently. No automated check.

**Mitigations (pick severity):**
- **Light (rec):** add a test that asserts `kohera_mark.svg` matches `MASK`-derived output + that `_mask` (read via a debug-exposed constant or a golden) matches the SVG. Fails CI on drift.
- **Medium:** move `MASK` to a single shared file (e.g. `assets/icons/kohera_mask.txt`) read by both the Python script and a Dart const generated from it (`tool/gen_mask_dart.py` writes `lib/core/theme/kohera_mask.dart`). One source, two consumers.
- **Heavy:** full codegen — Python script owns the mask, emits SVG + Dart `_mask` + `_threadMasks` constants. Dart imports generated file.

Rec light for now; escalate to medium if mask ever changes (e.g. NES counterpart, mark revision). Flag as open.

## 5. Regeneration + verification

After recolor (§2) + optional pad tweak (§3):

```bash
python3 tool/generate_icons.py
```

Verify:
- [ ] Visual: each platform icon shows pixel mark on aged-yellow, dusk mark, `crispEdges` preserved (nearest-neighbour, no anti-aliasing).
- [ ] Android: adaptive bg full-bleed aged-yellow, fg mark in safe zone. Legacy `ic_launcher.png` rounded aged-yellow + dusk mark.
- [ ] iOS: 1024 square opaque aged-yellow + dusk mark; smaller sizes legible (mark still recognizable at 20px — pixel mark is robust, but verify the feet/threads don't vanish).
- [ ] macOS: squircle aged-yellow + dusk mark at 16/32 (menu bar) — check legibility at 16.
- [ ] Web: favicon 32 + Icon-192/512 rounded; maskable mark centered, not clipped on Chrome install.
- [ ] Windows: ico at 16/32/48 — taskbar legibility.
- [ ] Linux: 512 rounded — desktop/snap/flatpak listing.
- [ ] SVG unchanged shape (regen produces byte-identical `kohera_mark.svg` if `MASK` unchanged — confirms no accidental mask edit).
- [ ] `flutter analyze` clean (no Dart change here, but sanity).
- [ ] Goldens: any icon-including goldens regenerate (check `test/widget_tests/goldens/`).

## 6. Files touched (impl deferred)

| File | Change |
|---|---|
| `tool/generate_icons.py` | `BG` → `#e5e5e5` grey, `FG` → `#2c3e50` dusk (2 lines). `maskable` pad 0.30 → 0.12 (locked). |
| All generated icon PNGs (android/iOS/macOS/web/windows/linux) | regenerated by rerunning script |
| `assets/icons/kohera_mark.svg` | regenerated (byte-identical if MASK unchanged — sanity check) |
| `test/widget_tests/goldens/` | regenerate any icon-including goldens |

## 7. Deliverables (this task)

1. This brief.
2. Color decision (§2.1) — RESOLVED: grey `#e5e5e5` + dusk `#2c3e50` (path A).
3. Maskable pad (§3) — RESOLVED: 0.12 (was 0.30, mark too small).
4. MASK sync strategy (§4) — light test now, or medium codegen.
5. Verification checklist (§5).
6. Cross-task flag: auth header tile coherence w/ #1 (§2.1).

## 8. Open / deferred

- iOS/macOS dark/tinted icon variants (iOS 18+ dark + tinted modes) — optional, requires separate asset set. Defer.
- Android themed icon (monochrome foreground for Material You themed icons) — optional, add `<monochrome android:drawable="@mipmap/ic_launcher_foreground"/>` to adaptive XML. Defer unless wanted.
- Animated icon (Android 13+ themed/animated) — defer.
- `OriginalFilename` exe casing (#3 open item) — unrelated to icons.
- Medium/heavy MASK codegen (§4) — defer unless mask changes.

## 9. Dependencies

- Blocked by: none (icons can recolor independently; grey/dusk are hardcoded SNES-brand constants, not derived from in-app palette).
- Blocks: #3 splash (splash uses mark bitmap from same generator — coordinate colors so splash + icon match). #3 splash decision now uses grey bg + dusk mark (light) / dusk bg + mark (dark) — matches icon option 1 → coherent.
- Related: #7 (revise SNES spec to grey primary surface) — icon colors track the revised spec's `surface`/`onSurface`, but icon impl does not strictly require #7 first (colors are independent constants).