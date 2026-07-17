# Kohera Colorized Theme-Reactive Mark Brief

Task: scope colorized theme-reactive mark via `accentRamp` (branding leverage #2).
Status: design brief. No code changes.

## Decisions (locked)

1. Thread→ramp mapping: **A — symmetric pairs.** pair(0,4)=`ramp[0]`, pair(1,3)=`ramp[1]`, center(2)=`ramp[2]`. 3 colors used.
2. Cap+stem color: **i — neutral `onSurface`.** Figure static, threads colored.
3. Renderer: **a — CustomPaint** extending loader's `_mask` approach. SVG becomes static reference only.
4. Animation: **β — all-threads wave** (center → outward), replaces current single-random-spark.
5. Non-pixel fallback: **accept grayscale** for Black/White via `fromColorScheme` ramp. No monochrome special-case.

## 1. Ground truth (existing, from `kohera_loader.dart`)

`_MyceliumPulsePainter._legs` defines 5 threads on a 100×100 brand grid, snapped to 32×32 via `_cell`. `_mask` (32×32 string grid) **is** the mark — loader draws from it, not the SVG. SVG + mask currently duplicated; this brief unifies on the mask.

| Leg | Tip | Role | Pair |
|---|---|---|---|
| 0 | (11, 89) | far-left outer | outer pair |
| 1 | (30, 90) | inner-left | inner pair |
| 2 | (50, 96) | center trunk | center |
| 3 | (71, 90) | inner-right | inner pair |
| 4 | (90, 89) | far-right outer | outer pair |

Structure: cap (rows 1-8) → stem (9-20) → threads (21-30) → feet (31-32).

## 2. Color model

### 2.1 Thread → ramp mapping (symmetric A)

```
Color _threadColor(KoheraPalette p, int leg) {
  switch (leg) {
    case 0: case 4: return p.accentRamp[0];  // outer pair
    case 1: case 3: return p.accentRamp[1];  // inner pair
    case 2:        return p.accentRamp[2];  // center
  }
}
```

- Ramp length assumed ≥3. All current ramps satisfy (Game Boy=4, others=6). Guard: `ramp[min(i, ramp.length-1)]` if a future ramp is shorter.
- `accentRamp[0]` = outer threads = same color as wordmark pixeled "K" (#1 brief). Brand signature color ties wordmark K ↔ outer threads. Coherence.

### 2.2 Cap + stem

- Cap (rows 1-8) + stem (rows 9-20) + feet (rows 31-32): `colorScheme.onSurface` (neutral).
- Threads (rows 21-30): per-leg ramp color via `_threadColor`.
- Metaphor preserved: static figure, living colored network.

### 2.3 Fallback (bare ThemeData, widget tests)

- No `KoheraPalette` extension → all threads = `colorScheme.primary` (single color), cap+stem = `onSurface`. Equivalent to current monochrome behavior. Tests unaffected.

### 2.4 Non-pixel themes

- `KoheraPalette.fromColorScheme` builds 6-color ramp from ColorScheme for all presets. Black/White → grayscale ramp → threads all gray (intentional monochrome). Accepted per decision 5.
- No special-case. One code path.

## 3. Renderer (CustomPaint, decision a)

### 3.1 Why not SVG

`flutter_svg` `colorFilter` = single `BlendMode.srcIn` tint over whole asset. Cannot override per-group fill from palette at runtime. Multi-color requires either per-theme static SVGs (N × maintenance, diverges from loader `_mask`) or CSS-in-SVG hacks (unsupported). CustomPaint wins: theme-reactive at paint time, unified w/ loader, `crispEdges` free via integer `Rect` draws.

### 3.2 `KoheraMark` widget (proposed)

```
KoheraMark({required double size, bool colored = true, Color? color})
```

- `colored = true` (default): threads from `KoheraPalette.of(context).accentRamp` via `_threadColor`; cap+stem from `colorScheme.onSurface`.
- `colored = false`: monochrome, single `color ?? onSurfaceVariant` (current behavior preserved for opt-out callers / bare tests).
- Renders via `CustomPaint` + `_MarkPainter` (static). Animation handled by `KoheraLoader` separately (see §4) — `KoheraMark` itself stays static; colored-but-not-animated is valid (e.g. sidebar/settings).
- Existing call sites (auth header, sidebar, settings) get colored by default — no call-site changes required beyond adopting the new widget.

### 3.3 `_MarkPainter` (static colored)

Reuses loader's `_mask` + adds per-thread pixel regions. Paint order:
1. Cap+stem+feet pixels → `onSurface` Paint.
2. For each leg 0..4: thread-region pixels → `_threadColor(palette, leg)` Paint.

`crispEdges` guaranteed by drawing 1×1 integer `Rect`s on the 32-grid, scaled by `size/32` (matching loader's `canvas.scale(size.width/_grid)`).

## 4. Per-thread pixel masks (authoring)

Need 5 thread regions on the 32×32 grid covering rows 21-30 (where threads live). Two derivation options:

- **i. Sample loader Bézier `_legs`** — sample each leg path, snap to 32×32 cells. Imperfect: Bézier centerline ≠ full pixel width of `_mask` threads.
- **ii. Hand-tag from `_mask`** — split `_mask` rows 21-30 into 5 `List<String>` grids (or `List<Rect>` lists), one per leg. Exact match to `_mask`.

**Rec ii.** Author once, exact. ~10 rows × 5 threads. Symmetry check: leg 0 mask = mirror of leg 4 (flip x → 31-x), leg 1 = mirror of leg 3. Author leg 0 + leg 1 + leg 2, derive 3 + 4 by mirror (reduces work, enforces symmetry).

Deliverable: `const List<List<String>> _threadMasks` (length 5) alongside `_mask`. Center-column pixels (the trunk continuation into leg 2) must not double-assign to cap+stem mask — partition cleanly at row 21.

## 5. Animation (β — all-threads wave, decision 4)

Replaces current single-random-spark. Wave radiates from center leg outward through symmetric pairs.

### 5.1 Cycle

- Duration: **1500ms** (slower than current 1100ms — continuous wave reads calmer than random pulse).
- `AnimationController(..).repeat()`, no randomness.
- Deterministic phase per leg.

### 5.2 Phase schedule

| Leg | Brighten window (cycle fraction) |
|---|---|
| 2 (center) | 0.00 – 0.40 |
| 1, 3 (inner pair) | 0.30 – 0.70 |
| 0, 4 (outer pair) | 0.60 – 1.00 (wraps to 0.00) |

- Windows overlap 0.10 → smooth radiating handoff, no hard cut.
- Center starts first; wave reaches outer pair near cycle end; outer pair brighten carries across wrap → seamless loop.

### 5.3 Brighten function

Per leg, within its window: triangle pulse 0→1→0.
```
pulse(leg) = 1 - abs((phase - windowStart) / windowLen * 2 - 1)  // 0..1..0
threadPaintColor(leg) = Color.lerp(_threadColor(p, leg), white, pulse(leg) * 0.9)
```
- Peak brighten = 90% toward white (matches current loader `Color.lerp(color, white, 0.9)`).
- Outside window: pulse = 0 → thread shows base ramp color.

### 5.4 Node flash

At pulse peak (mid-window), flash that leg's tip node white, fade over the back half of the window. Reuse current loader's cross-shape flash (5 cells: center + 4 orthogonal neighbors).

### 5.5 Cap ignition

Optional: subtle cap brighten at cycle start (t=0) to mark the wave origin. `Color.lerp(onSurface, white, 0.3)` for 0.0–0.15 of cycle. Reads as "source emits, wave radiates." Low intensity to avoid flicker on the figure. Flag as optional — may cut if distracting.

### 5.6 Static vs animated split

- `KoheraMark` (static) — colored threads, no motion. Sidebar, settings, auth header, splash.
- `KoheraLoader` (animated) — same colored threads + β wave. Loading states, sync, launch.
- Both share `_mask`, `_threadMasks`, `_threadColor`. One renderer family.

### 5.7 Wordmark K sync (deferred nicety)

Per #1 brief: pixeled "K" uses `ramp[0]` = outer-thread color. Could brighten K in sync w/ outer pair (legs 0,4) brighten window (0.60–1.00). Ties wordmark ↔ mark motion. **Deferred** — flag for implementation; not blocking.

## 6. Contrast / accessibility matrix

Per theme, verify each thread color vs surface + vs cap/stem `onSurface`. Threshold: WCAG AA 3:1 for graphical objects (threads are non-text, but 3:1 minimum for distinguishable UI components).

| Theme | Surface | ramp[0] | ramp[1] | ramp[2] | Notes |
|---|---|---|---|---|---|
| PICO-8 dark | #000000 | pink #FF77A8 | orange #FFA300 | yellow #FFEC27 | all pass on black |
| PICO-8 light | #FFF1E8 | pink #FF77A8 | orange #FFA300 | yellow #FFEC27 | **yellow on cream likely fails** — swap to ramp[4] blue or darken |
| Game Boy dark | #0F380F | #9BBC0F | #8BAC0F | #306230 | center=dark green on dark bg → **check**, may swap to lighter |
| Game Boy light | #9BBC0F | #0F380F | #306230 | #8BAC0F | verify center lightest on light bg |
| Paper light | #FBF7EC | #B0453A | #3A6EA5 | #C9A227 | yellow-gold on cream — verify |
| Paper dark | #15130F | #C46A5B | #7FA6C9 | #D9A441 | likely fine |
| Mocha | #1E1E2E | primary mauve | secondary pink | tertiary rose | fine on dark |
| Black dark | #121212 | grayscale | grayscale | grayscale | intentional low contrast — accept |
| White light | #FFFFFF | grayscale | grayscale | grayscale | accept |

**Action:** produce measured contrast ratios, fill table. For failing cells, either (a) re-order that theme's `accentRamp` so distinguishable colors land in slots 0-2, or (b) for that theme only, override `_threadColor` to use slots 3-5. Prefer (a) — keeps mapping uniform.

PICO-8 light yellow-on-cream is the most likely failure. Candidate fix: shift PICO-8 light `accentRamp` so blue (#29ADFF) or lavender (#83769C) occupies slot 2.

## 7. Files touched (impl deferred)

| File | Change |
|---|---|
| `lib/shared/widgets/kohera_mark.dart` | Rewrite as CustomPaint w/ `_MarkPainter` + `_threadColor`. Keep `KoheraMark` API (`size`, `color`), add `colored` (default true). |
| `lib/shared/widgets/kohera_loader.dart` | Replace single-spark w/ β wave. Reuse `_mask`, add `_threadMasks`, `_threadColor`. Remove `_activeLeg` randomness, add per-leg phase. |
| `lib/core/theme/kohera_palette.dart` | Possibly reorder PICO-8 light `accentRamp` per §6 contrast fix. |
| `assets/icons/kohera_mark.svg` | Demoted to static reference asset (still used by tooling/docs). Keep in sync w/ `_mask` if mask ever changes. |
| `test/widget_tests/` | Goldens w/ colored mark — regenerate after impl. Bare-ThemeData tests get monochrome fallback (verify golden unchanged). |

## 8. Deliverables (this task)

1. This brief.
2. `_threadMasks` spec — 5 hand-tagged thread regions (leg 0,1,2 authored; 3,4 by mirror). Exact pixel lists.
3. `_threadColor` mapping fn (§2.1).
4. β wave spec (§5.1–5.5): phase table, brighten fn, node flash, cap ignition optional.
5. Contrast matrix (§6) filled w/ measured ratios + fix recommendations per failing theme.
6. Fallback rule (§2.3) — monochrome when palette absent.
7. Call-site impact: none (default `colored=true`, API stable).

## 9. Open / deferred

- Wordmark K sync brighten (§5.7) — deferred, flag for #1 impl.
- Cap ignition (§5.5) — optional, decide at impl w/ visual test.
- Per-theme ramp reordering (§6) — decide after contrast measurement.
- Animated SVG export for README/social (colored + looping) — deferred, separate asset task.
- Performance: 5 Paint objects per frame, 1×1 rects on 32-grid — negligible; verify w/ DevTools timeline at impl.