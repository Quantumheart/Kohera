# SNES Theme Spec

> Inspiration: [snes.css](https://github.com/devMiguelCarrero/snes.css) — a
> 16-bit CSS framework. snes.css is the **reference for the refined beveled
> pixel look**: pixelated border-image textures, stepped "shadow-shine"
> corner bevels, a wider 6px pixel grid, and the SNES's signature purple
> palette on a neutral grey console canvas (snes.css's default
> `body,html{background-color:#e5e5e5}`). Aged-yellow `#fcf4d9` is kept as an
> elevated-container accent, not the primary surface.

## Design intent

The SNES theme is the **16-bit, soft-beveled** pixel theme. It is the
sophisticated counterpart to the hard-edged NES theme:

- **Wider pixel grid** — `shadowOffset: 6` and `borderWidth: 2` (snes.css
  uses a 6px pixel unit; borders are drawn via a 9-slice pixel texture rather
  than a solid stroke). The larger offset gives SNES a heavier, more
  dimensional feel than NES despite a thinner explicit border token.
- **Soft-pixel corners** — `radius: 4`. Unlike NES.css (perfectly square),
  snes.css ships a `$main-border-radius: 16px` and rounded console edges. We
  use a small radius (4) to keep the pixel identity while signalling that SNES
  is the *softer* of the two.
- **Beveled shadow-shine** — snes.css's signature `generate-shadow-shine`
  mixin produces **stepped corner highlights and shadows** (a dark step
  below-right, a light step above-left). The `KoheraPalette` cannot express
  the full clip-path, but we encode its intent as `shadowHard` (a dark,
  slightly translucent dusk) plus a *lighter* offset than NES to imply the
  bevel rather than a flat stamp. The full stepped bevel is a Phase-3 polish
  item (custom paint), documented below.
- **The SNES palette** — **Phantom Purple `#9b5de5`** as the signature
  primary (SNES's iconic purple face-buttons), **dusk `#2c3e50`** text/border,
  and the snes.css accent ramp (plumber red, nature green, sunshine yellow,
  ocean blue, turquoise, rose, galaxy blue, lava orange).
- **Grey primary surface (revised)** — snes.css's default canvas is **grey
  `#e5e5e5`** (`body,html{background-color:#e5e5e5}`), and this spec now uses
  grey as the SNES light-mode `surface`. **Aged-yellow `#fcf4d9` is demoted
  from the primary surface to an elevated-container accent**
  (`surfaceContainerHighest`) — the "aged console" highlight tier — plus the
  dark-mode `onSurface` text color. Rationale: aged-yellow as the dominant
  light surface collided with Kohera's Paper (`#FBF7EC`) and PICO-8
  (`#FFF1E8`) cream surfaces; grey differentiates SNES decisively and is
  faithful to snes.css's actual default. See the Differentiators table below.

This is the **soft-beveled, most dimensional** pixel theme — neutral grey
canvas with phantom-purple signature and a warm aged-yellow elevated accent.

## Source palette (snes.css)

snes.css variables (`scss/common/variables/colors.scss`):

| Token                  | Value     | Use                          |
|------------------------|-----------|------------------------------|
| `$main-color` (dusk)   | `#2c3e50` | text & border                |
| `$color-text-hover`    | `#566573` | muted text                   |
| border-image (9-slice) | PNG       | pixelated border texture     |
| pixel regular          | `6px`     | grid unit                     |
| pixel small            | `4px`     | secondary grid unit           |
| border-radius          | `16px`    | `$main-border-radius`         |
| font                   | Press Start 2P | —                      |

snes.css main accent ramp:

| Name        | Value     |
|-------------|-----------|
| Plumber Red | `#f22561` |
| Nature Green | `#4bb244` |
| Sunshine Yellow | `#f2c019` |
| Ocean Blue  | `#4eb6d9` |
| Turquoise   | `#40e0d0` |
| **Phantom Purple** | `#9b5de5` |
| Rose        | `#f784b2` |
| Galaxy Blue | `#5a7d9a` |
| Lava Orange | `#ff6f00` |

snes.css backgrounds:

| Name              | Value     | Note                                  |
|-------------------|-----------|---------------------------------------|
| white             | `#fff`    |                                       |
| **grey**          | `#e5e5e5` | **snes.css default body canvas**       |
| aged-yellow       | `#fcf4d9` | yellowed console plastic — accent use |
| secondary-purple  | `#f0e4ff` | very light SNES purple                 |
| soft-green        | `#e2f4ea` |                                       |

**Surface mapping (revised):** grey `#e5e5e5` → light `surface` (default
canvas). Aged-yellow `#fcf4d9` → `surfaceContainerHighest` (elevated accent)
+ dark-mode `onSurface` (warm text). White `#fff` informs
`surfaceContainerLowest`. secondary-purple `#f0e4ff` → light `primaryContainer`.

snes.css button shine/shadow (`variables.scss`):

| Token              | Value                  |
|--------------------|------------------------|
| `$button-shine`    | `rgba(#fff, 0.3)`      |
| `$button-shadow`   | `rgba(#000, 0.2)`      |
| `$button-hover-shine`  | `rgba(#fff, 0.4)`   |
| `$button-hover-shadow` | `rgba(#000, 0.3)`   |

The signature `generate-shadow-shine` mixin (clip-path polygon) draws a
stepped **shadow below-right** + **shine above-left**, giving SNES buttons
their 3D bevel.

## ThemePreset entry

Add to the **Pixel themes** section of `theme_presets.dart`:

```dart
ThemePreset(
  id: 'snes',
  name: 'SNES',
  seedColor: Color(0xFF9b5de5),   // Phantom Purple — SNES signature
  pixelPalette: KoheraPalette.snes,
  darkScheme:  /* see below */,
  lightScheme: /* see below */,
),
```

## ColorScheme

### Dark

```dart
ColorScheme(
  brightness: Brightness.dark,
  primary:            Color(0xFF9b5de5), // Phantom Purple
  onPrimary:          Color(0xFFFFFFFF),
  primaryContainer:   Color(0xFF5a3a8c), // darkened purple
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary:          Color(0xFF4eb6d9), // Ocean Blue
  onSecondary:        Color(0xFF000000),
  secondaryContainer: Color(0xFF2a6d8a),
  onSecondaryContainer: Color(0xFFFFFFFF),
  tertiary:           Color(0xFFf2c019), // Sunshine Yellow
  onTertiary:         Color(0xFF000000),
  tertiaryContainer:   Color(0xFFb8900f),
  onTertiaryContainer: Color(0xFF000000),
  error:              Color(0xFFf22561), // Plumber Red
  onError:            Color(0xFFFFFFFF),
  surface:            Color(0xFF2c3e50), // dusk — snes.css main-color
  onSurface:          Color(0xFFfcf4d9), // aged yellow text (warm accent)
  onSurfaceVariant:   Color(0xFF908a99), // SNES controller grey
  outline:            Color(0xFF566573), // text-hover dusk
  outlineVariant:     Color(0xFF3a4a5c),
  surfaceContainerLowest:  Color(0xFF1f2c3a),
  surfaceContainerLow:    Color(0xFF26333f),
  surfaceContainer:        Color(0xFF2c3e50),
  surfaceContainerHigh:   Color(0xFF384a5c),
  surfaceContainerHighest: Color(0xFF465868),
)
```

### Light — grey console canvas (revised)

Light mode uses **grey `#e5e5e5`** as the primary `surface` (snes.css's
default canvas), with dusk text, the purple accent ramp, and aged-yellow
reserved for the most elevated container (`surfaceContainerHighest`) as an
"aged console" accent.

```dart
ColorScheme(
  brightness: Brightness.light,
  primary:            Color(0xFF9b5de5), // Phantom Purple
  onPrimary:          Color(0xFFFFFFFF),
  primaryContainer:   Color(0xFFf0e4ff), // secondary-purple bg
  onPrimaryContainer: Color(0xFF2c3e50),
  secondary:          Color(0xFF4eb6d9), // Ocean Blue
  onSecondary:        Color(0xFF000000),
  secondaryContainer: Color(0xFFd6f0f8),
  onSecondaryContainer: Color(0xFF2c3e50),
  tertiary:           Color(0xFFf2c019), // Sunshine Yellow
  onTertiary:         Color(0xFF2c3e50),
  tertiaryContainer:   Color(0xFFfdf0b8),
  onTertiaryContainer: Color(0xFF2c3e50),
  error:              Color(0xFFc41a4d), // darkened plumber red for light bg
  onError:            Color(0xFFFFFFFF),
  surface:            Color(0xFFe5e5e5), // GREY — snes.css default canvas
  onSurface:          Color(0xFF2c3e50), // dusk text
  onSurfaceVariant:   Color(0xFF566573), // text-hover
  outline:            Color(0xFF5a7d9a), // Galaxy Blue as outline accent
  outlineVariant:     Color(0xFFb0a890), // warm aged-paper outline accent
  surfaceContainerLowest:  Color(0xFFF5F5F5), // near-white
  surfaceContainerLow:    Color(0xFFEDEDED),
  surfaceContainer:        Color(0xFFE2E2E2),
  surfaceContainerHigh:   Color(0xFFD8D8D8),
  surfaceContainerHighest: Color(0xFFfcf4d9), // AGED-YELLOW elevated accent
)
```

## KoheraPalette factory

Add `KoheraPalette.snes(Brightness brightness)` to `kohera_palette.dart`.

```dart
factory KoheraPalette.snes(Brightness brightness) {
  // snes.css accent ramp
  const phantomPurple = Color(0xFF9b5de5); // signature
  const oceanBlue     = Color(0xFF4eb6d9);
  const sunshineYellow = Color(0xFFf2c019);
  const natureGreen   = Color(0xFF4bb244);
  const plumberRed    = Color(0xFFf22561);
  const rose          = Color(0xFFf784b2);
  const galaxyBlue    = Color(0xFF5a7d9a);
  const lavaOrange    = Color(0xFFff6f00);

  const dusk          = Color(0xFF2c3e50); // snes.css main-color
  const agedYellow    = Color(0xFFfcf4d9); // yellowed console plastic — accent only
  const secondaryPurple = Color(0xFFf0e4ff);

  if (brightness == Brightness.dark) {
    return const KoheraPalette(
      borderStrong: dusk,                    // #2c3e50 — snes.css border color
      borderWidth: 2,                         // border drawn via texture, not thick stroke
      shadowHard:   Color(0x33000000),        // rgba(#000,0.2) — snes.css button-shadow
      shadowOffset: 6,                         // snes.css pixel-regular (wider than NES)
      radius: 4,                              // SOFT-PIXEL — SNES is rounder than NES

      online:  natureGreen,                    // #4bb244
      idle:    sunshineYellow,                 // #f2c019

      unread:  plumberRed,                     // #f22561
      onUnread: Color(0xFFFFFFFF),

      mention: sunshineYellow,                 // #f2c019
      link:    oceanBlue,                       // #4eb6d9

      ownBubble:    phantomPurple,             // your messages = signature purple
      onOwnBubble:  Color(0xFFFFFFFF),
      otherBubble:  Color(0xFF384a5c),         // lifted dusk
      onOtherBubble: agedYellow,               // warm text on dark bubble

      success: natureGreen,
      warning: sunshineYellow,
      danger:  plumberRed,

      scanline: Color(0x2E000000),              // black @ 18%
      dither:  Color(0xFFf0e4ff),               // secondary-purple tint

      // Full snes.css accent ramp (9 colours)
      accentRamp: [
        plumberRed,
        natureGreen,
        sunshineYellow,
        oceanBlue,
        Color(0xFF40e0d0), // turquoise
        phantomPurple,
        rose,
        galaxyBlue,
        lavaOrange,
      ],
    );
  }

  // Light — grey console canvas (revised)
  return const KoheraPalette(
    borderStrong: dusk,                      // #2c3e50
    borderWidth: 2,
    shadowHard:   Color(0x33000000),          // rgba(#000,0.2)
    shadowOffset: 6,
    radius: 4,

    online:  Color(0xFF2f7d2a),              // darker green for light bg
    idle:    Color(0xFFb8900f),               // darker yellow

    unread:  Color(0xFFc41a4d),              // darker red
    onUnread: Color(0xFFFFFFFF),

    mention: Color(0xFFb8900f),
    link:    Color(0xFF2a6d8a),               // darker ocean blue

    ownBubble:    Color(0xFF7b3dc4),           // deeper phantom purple — light contrast + brightness adaptation
    onOwnBubble:  Color(0xFFFFFFFF),
    otherBubble:  secondaryPurple,           // #f0e4ff very light purple
    onOtherBubble: dusk,

    success: Color(0xFF2f7d2a),
    warning: Color(0xFFb8900f),
    danger:  Color(0xFFc41a4d),

    scanline: Color(0x1A000000),              // black @ 10%
    dither:  Color(0xFFdcdcdc),               // neutral grey texture tint (no yellow creep on base)

    accentRamp: [
      plumberRed,
      natureGreen,
      sunshineYellow,
      oceanBlue,
      Color(0xFF40e0d0),
      phantomPurple,
      rose,
      galaxyBlue,
      lavaOrange,
    ],
  );
}
```

## The SNES bevel (signature effect)

snes.css's `generate-shadow-shine` mixin draws **stepped corner highlights and
shadows** via clip-path — a dark step below-right and a light step
above-left. This is the single most distinctive snes.css trait and is **not**
expressible through `KoheraPalette`'s flat `shadowHard`/`shadowOffset`
tokens alone.

### Encoding in the palette (this phase)

- `shadowHard: rgba(#000, 0.2)` — the snes.css `$button-shadow` value.
  Using a *translucent* dark (rather than NES's solid opaque blue) signals the
  softer, more dimensional SNES shadow.
- `radius: 4` — soft-pixel corners (vs NES `0`).

### Full bevel (Phase-3 polish — future task)

A custom `snesBox()` decoration that layers two additional offset boxes to
reproduce the stepped shine/shadow:

```
 ┌─────────────┐  ← light step (shine) offset (-2, -2), rgba(#fff,0.3)
 │ ┌─────────┐ │
 │ │  fill   │ │
 │ └─────────┘ │
 └─────────────┘  ← dark step (shadow) offset (+2, +2), rgba(#000,0.2)
```

Implemented as a `BoxDecoration` with three `boxShadow` entries (light
top-left, dark bottom-right, none) or a `CustomPainter` for exact
clip-path parity. This is tracked as a follow-up once the pixel sweep lands.

## Differentiators vs other pixel themes

| Token          | SNES        | NES        | PICO-8 | Game Boy |
|----------------|-------------|------------|--------|----------|
| `borderWidth`  | 2           | **4**      | 2      | 2        |
| `radius`       | **4**       | 0          | 0      | 0        |
| `shadowOffset`  | **6**       | 4          | 3      | 3        |
| shadow style   | beveled (translucent) | flat stamp | flat | flat |
| `primary`        | **purple**  | blue       | green  | green    |
| light surface  | **grey `#e5e5e5`** | white   | white  | green    |
| light accent container | **aged-yellow `#fcf4d9`** (elevated) | — | — | — |
| feel           | 16-bit soft | 8-bit hard | 8-bit  | 1-bit    |

The **`radius: 4`** (soft-pixel) + **`shadowOffset: 6`** + **translucent
`shadowHard`** together encode the SNES "softer, more dimensional" identity
within the existing palette contract, while the grey canvas, aged-yellow
elevated accent, and phantom-purple primary make it instantly recognisable
and distinct from Kohera's Paper/PICO-8 cream surfaces.

## Verification checklist

- [ ] `ThemePreset(id: 'snes')` appears in the pixel themes section.
- [ ] Picker chip shows seed `#9b5de5` labelled "SNES".
- [ ] Dark mode: dusk `#2c3e50` surfaces, purple primary, aged-yellow text.
- [ ] Light mode: grey `#e5e5e5` surface, dusk text, purple accents; aged-yellow
      only as `surfaceContainerHighest` elevated accent.
- [ ] `KoheraPalette.snes` resolves via `KoheraPalette.of`.
- [ ] `pixelBox` renders 2px border + 6px translucent offset shadow, radius 4.
- [ ] Message bubbles: own = phantom purple (dark `#9b5de5`, light `#7b3dc4`),
      other = lifted dusk (dark) / very-light purple (light).
- [ ] Light `dither` is neutral grey `#dcdcdc` (no yellow creep on base).
- [ ] Accent ramp exposes all 9 snes.css colours for procedural avatars.
- [ ] `dart analyze` clean; theme switches with no layout shift.
- [ ] SNES light surface is visually distinct from Paper/PICO-8 cream.
- [ ] (Follow-up) `snesBox()` bevel decoration prototyped for Phase 3.

## Implementation note: light `ownBubble`

The light-mode `ownBubble` is **deeper phantom purple `#7b3dc4`** (not the
signature `#9b5de5` used in dark mode). Two reasons:

1. **Brightness adaptation** — the project's pixel-preset contract test
   (`test/core/theme/pixel_theme_brightness_test.dart`) requires `ownBubble`
   to differ between light and dark, guarding against copy-paste palettes that
   collapse the two modes. Dark uses `#9b5de5`; light uses `#7b3dc4`.
2. **Light-mode contrast** — white-on-`#7b3dc4` ≈ 5.2:1 vs white-on-`#9b5de5`
   ≈ 3.5:1, so own-message text reads more cleanly on the grey canvas.

The signature phantom purple `#9b5de5` still anchors the theme via `primary`, the
accent ramp, and the dark-mode own bubble.