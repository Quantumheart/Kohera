# Kohera Wordmark + Lockup Brief

Task: scope wordmark + mark/wordmark lockup (branding leverage #1).
Status: design brief. No code changes.

## Decisions (locked)

- Typeface path: **B + D** — custom pixeled "K" glyph (ramp-colored via `KoheraPalette.accentRamp`) + "ohera" in `PressStart2P`.
- Primary lockup: **stacked** (mark on top, wordmark below). Horizontal = secondary.
- Favicon / tiny sizes: **mark only** (no wordmark, no monogram).
- Ramp-colored "K": **in** — the wordmark's first glyph uses `accentRamp[0]`.

## 1. Mark analysis (existing)

Source: `assets/icons/kohera_mark.svg`, 32x32 viewBox, `crispEdges`, monochrome `currentColor`.

Silhouette (reconstructed):
- Rows 1-8: wide head/hood block (width 21, centered).
- Rows 9-20: thin body column (width ~4-5, centered).
- Rows 21-30: 4 radiating threads w/ node feet (symmetric spread).
- Rows 31-32: feet.

Traits: symmetric, top-heavy, bottom-spreading, heavy pixel density. Matches `kohera_loader` thread motif.

Implication for wordmark: mark is visually heavy. Wordmark should not also be uniformly heavy — the custom "K" carries the weight; "ohera" in PressStart2P is solid but lighter by virtue of being smaller glyphs. Stacked lockup suits the centered, vertical silhouette.

## 2. Wordmark construction

### 2.1 Glyph set

- **"K"**: custom pixeled glyph, master grid 16x16 (half the mark's 32x32 so it scales cleanly w/ integer scaling: 16->32->64). Authored as SVG w/ `crispEdges`, `fill` = `accentRamp[0]` at render time (theme-reactive; see #4). Shape: blocky pixel "K" — vertical stem + two diagonals, all pixel-snapped. Reference the mark's stroke weight (~3-4px on a 16-grid) for family resemblance.
- **"ohera"**: `PressStart2P` font, color = `onSurface` (neutral, adapts per theme).

### 2.2 Rendering

- "K" rendered from SVG (`kohera_glyph_k.svg`), sized to match PressStart2P cap-height at the target size.
- "ohera" rendered as Text w/ `PressStart2P`, `letterSpacing: 0` (per existing `displayLarge` rule — pixel fonts need zero letter-spacing).
- Baseline alignment: "K" SVG baseline = PressStart2P text baseline. PressStart2P has tall caps w/ no descenders; align cap-tops, not baselines, since both are all-cap-height glyphs. Test visually — PressStart2P "o/a/e" sit slightly low, may need 1px nudge.
- Combined as a single Row in a `KoheraWordmark` widget (sister to `KoheraMark`).

### 2.3 Color

- "K" fill = `KoheraPalette.of(context).accentRamp[0]`.
- "ohera" = `Theme.of(context).colorScheme.onSurface`.
- Fallback when `KoheraPalette` absent (bare ThemeData, e.g. widget tests): "K" = `colorScheme.primary`.
- Wordmark never gets per-letter rainbow coloring beyond the single "K" accent.

## 3. Lockups

### 3.1 Primary: stacked

```
   [mark]
  Kohera
```

- Mark centered above wordmark.
- Mark height : wordmark cap-height = **0.8:1** (mark smaller, wordmark dominates — reads "app name first").
- Vertical gap = 0.25 × mark-height.
- Wordmark centered under mark's horizontal center.

Used in: auth header (replaces current `AppLogoHeader` mark+`displayLarge` text), splash/launch screens, README hero, web manifest/social card, app icon (mark-only at icon scale — see ladder).

### 3.2 Secondary: horizontal

```
[mark] Kohera
```

- Mark left, wordmark right.
- Mark height : wordmark cap-height = **1.2:1** (mark dominates).
- Horizontal gap = 0.5 × mark-height.
- Optical centering: align mark vertical-center to wordmark cap-height midpoint (not full line height — PressStart2P has padding above caps).

Used in: sidebar wide-layout header, settings header, secondary contexts where horizontal space > vertical.

### 3.3 Clear space

- Minimum clear space on all sides = **mark height** (standard).
- Within lockup, the gap rules above override (they're tighter than clear space, by design).
- No element intrudes inside clear-space boundary.

### 3.4 Min size

- Stacked lockup min: wordmark 14px (PressStart2P floor for readability; stacked aids reading).
- Horizontal lockup min: wordmark 18px.
- Below these → mark only.

## 4. Sizing ladder

| Context | Wordmark size | Lockup | Notes |
|---|---|---|---|
| Favicon 16/32 | — | mark only | per decision |
| iOS AppIcon 20-40 (settings) | — | mark only | |
| iOS AppIcon 60-1024 (home/store) | — | mark only | optional: mark + tagline on store only, not in icon |
| Android launcher | — | mark only | adaptive icon, safe-zone padding |
| Web Icon 192/512 + maskable | — | mark only | maskable: 0.8x safe zone |
| Sidebar header | 18px | horizontal | |
| Settings header | 18px | horizontal | |
| Auth header | 28px | stacked | replaces current 72px mark + 32px text |
| Splash / launch | 32px | stacked | mark 0.8x wordmark |
| README hero | 48px | stacked + tagline | tagline in DepartureMono, 0.4x wordmark |
| Manifest / social card (512) | 64px | stacked | centered, theme surface bg |

## 5. Do / don't

**Do**
- Render SVGs w/ `crispEdges` always (mark + "K" glyph).
- Keep integer scaling for pixel assets (16->32->64; avoid 24, 48 odd scales).
- Use `onSurface` for "ohera" so it adapts per theme.
- Color only the "K" w/ ramp[0]; leave rest neutral.
- Use stacked as default; switch to horizontal only when vertical space constrained.

**Don't**
- Stretch mark or glyph non-uniformly (breaks pixel grid).
- Recolor "ohera" per-letter (rainbow).
- Rotate the lockup.
- Place on photos w/o a contrast scrim (min 0.5 alpha surface).
- Add drop shadow to wordmark (mark has hard shadow via `KoheraPalette.shadowHard`; wordmark stays flat).
- Pair PressStart2P wordmark w/ non-pixel themes (Paper, Catppuccin, Black, White, Ocean, etc.) — those use mark only, no wordmark, OR a DepartureMono wordmark variant (deferred — not in this scope).

## 6. Per-context usage map

| Location | Current | Target |
|---|---|---|
| `lib/features/auth/widgets/app_logo_header.dart` | 72px mark box + `displayLarge` "Kohera" (PressStart2P 32, neutral) | stacked lockup: 56px mark + 28px wordmark (pixeled ramp-K + PressStart2P "ohera") |
| `lib/features/home/widgets/wide_layout.dart:177` | `KoheraMark` in sidebar | horizontal lockup, 18px wordmark |
| `lib/features/settings/screens/settings_screen.dart:208` | `KoheraMark(size:24)` | horizontal lockup, 18px wordmark (or mark-only if space tight) |
| `web/index.html` title | lowercase `kohera` | plain text "Kohera" (browser tab — no font) — handled by #3 |
| `web/manifest.json` | name "Kohera" (plain) | keep plain text; icons = mark only |
| iOS/macOS app icons | Flutter default | mark only — handled by #4 |
| Splash / launch (all platforms) | Flutter default | stacked lockup — handled by #4 |
| README hero | none | stacked lockup + tagline — handled by #5 |

## 7. Deliverables

1. `assets/icons/kohera_glyph_k.svg` — 16x16 master pixeled "K", monochrome (ramp applied at render).
2. `assets/icons/kohera_lockup_stacked.svg` — static reference rendering (for docs/README), mark + wordmark.
3. `assets/icons/kohera_lockup_horizontal.svg` — static reference rendering.
4. `lib/shared/widgets/kohera_wordmark.dart` — widget rendering pixeled-K + PressStart2P "ohera" (implementation deferred — this is design scope).
5. This brief doc.
6. Size ladder table (section 4).
7. Clear-space + min-size spec (sections 3.3, 3.4).

## 8. Open questions (for later tasks)

- PressStart2P "ohera" cap-top padding — verify baseline alignment w/ pixeled "K" once glyph authored.
- DepartureMono wordmark variant for non-pixel themes — deferred (separate task if adopted).
- Animated wordmark (pixeled "K" pulse in sync w/ mark thread animation) — deferred to #2 colorized mark task.
- Tagline copy + placement — deferred to #5.