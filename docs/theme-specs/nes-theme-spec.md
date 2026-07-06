# NES Theme Spec

> Inspiration: [NES.css](https://github.com/nostalgic-css/NES.css) — an 8-bit
> CSS framework. NES.css is the **reference for the flat chunky-pixel look**:
> solid 4px borders, hard offset drop-shadows (no blur), and the classic NES
> console accent palette (blue/green/yellow/red) on a near-black/white base.

## Design intent

The NES theme is the **8-bit, hard-edged** pixel theme. It distinguishes itself
from the other pixel palettes (PICO-8, Game Boy) by:

- **Thicker, solid borders** — `borderWidth: 4` (vs the system default of 2).
  This is the single most recognisable NES.css trait: every surface wears a
> chunky solid outline, not a thin hairline.
- **Flat hard offset shadows** — a solid `shadowHard` colour displaced by the
  full border width with **zero blur**, giving the classic "stamped" button
  look. No soft elevation.
- **Sharp corners** — `radius: 0`. NES.css buttons are perfectly square.
- **The NES.css accent palette** — blue `#209cee` primary, green `#92cc41`,
  yellow `#f7d51d`, red `#e76e55` — the four button colours NES.css ships with,
  plus the near-black `#212529` base and pure-white `#ffffff` background.

This is the **darkest, hardest** pixel theme: high contrast, zero softness.

## Source palette (NES.css)

NES.css base variables (`scss/base/variables.scss`):

| Token            | Value     | Use                       |
|------------------|-----------|---------------------------|
| base color       | `#212529` | text / border / dark surf |
| background       | `#fff`    | light surface             |
| border size      | `4px`     | border width              |
| font             | Press Start 2P | —                   |

NES.css button accent ramp (`normal / hover / shadow`):

| Semantic | Normal    | Hover     | Shadow    |
|----------|-----------|-----------|-----------|
| primary  | `#209cee` | `#108de0` | `#006bb3` |
| success  | `#92cc41` | `#76c442` | `#4aa52e` |
| warning  | `#f7d51d` | `#f2c409` | `#e59400` |
| error    | `#e76e55` | `#ce372b` | `#8c2022` |

The underlying [NES hardware palette](https://en.wikipedia.org/wiki/List_of_video_game_console_palettes#NES)
(64 colours) provides additional accent candidates — see `accentRamp` below.

## ThemePreset entry

Add to the **Pixel themes** section of `theme_presets.dart`:

```dart
ThemePreset(
  id: 'nes',
  name: 'NES',
  seedColor: Color(0xFF209cee),   // NES.css primary blue
  pixelPalette: KoheraPalette.nes,
  darkScheme:  /* see below */,
  lightScheme: /* see below */,
),
```

## ColorScheme

### Dark (primary mode)

NES.css defaults to white-on-near-black. Dark mode is the natural home.

```dart
ColorScheme(
  brightness: Brightness.dark,
  primary:            Color(0xFF209cee), // NES.css primary blue
  onPrimary:          Color(0xFFFFFFFF),
  primaryContainer:   Color(0xFF006bb3), // NES.css primary shadow
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary:          Color(0xFF92cc41), // success green
  onSecondary:        Color(0xFF000000),
  secondaryContainer: Color(0xFF4aa52e), // green shadow
  onSecondaryContainer: Color(0xFFFFFFFF),
  tertiary:           Color(0xFFf7d51d), // warning yellow
  onTertiary:         Color(0xFF000000),
  tertiaryContainer:   Color(0xFFe59400), // yellow shadow
  onTertiaryContainer: Color(0xFF000000),
  error:              Color(0xFFe76e55), // error red
  onError:            Color(0xFFFFFFFF),
  surface:            Color(0xFF212529), // NES.css base black
  onSurface:          Color(0xFFFFFFFF),
  onSurfaceVariant:   Color(0xFFbcbcbc), // NES palette $color-10 (light grey)
  outline:            Color(0xFF7c7c7c), // NES palette $color-00 (grey)
  outlineVariant:     Color(0xFF503000), // NES palette $color-08 (brown)
  surfaceContainerLowest:  Color(0xFF000000),
  surfaceContainerLow:    Color(0xFF1a1e22),
  surfaceContainer:        Color(0xFF212529),
  surfaceContainerHigh:   Color(0xFF2b3137),
  surfaceContainerHighest: Color(0xFF3a4148),
)
```

### Light

```dart
ColorScheme(
  brightness: Brightness.light,
  primary:            Color(0xFF209cee),
  onPrimary:          Color(0xFFFFFFFF),
  primaryContainer:   Color(0xFF108de0), // hover blue
  onPrimaryContainer: Color(0xFFFFFFFF),
  secondary:          Color(0xFF4aa52e), // green shadow (darker for light bg)
  onSecondary:        Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFF92cc41),
  onSecondaryContainer: Color(0xFF000000),
  tertiary:           Color(0xFFe59400), // yellow shadow
  onTertiary:         Color(0xFFFFFFFF),
  tertiaryContainer:   Color(0xFFf7d51d),
  onTertiaryContainer: Color(0xFF000000),
  error:              Color(0xFFce372b), // error hover (darker for light bg)
  onError:            Color(0xFFFFFFFF),
  surface:            Color(0xFFFFFFFF), // NES.css background
  onSurface:          Color(0xFF212529), // NES.css base black
  onSurfaceVariant:   Color(0xFF503000), // brown
  outline:            Color(0xFF7c7c7c),
  outlineVariant:     Color(0xFFbcbcbc),
  surfaceContainerLowest:  Color(0xFFFFFFFF),
  surfaceContainerLow:    Color(0xFFF8F8F8),
  surfaceContainer:        Color(0xFFEFEFEF),
  surfaceContainerHigh:   Color(0xFFE0E0E0),
  surfaceContainerHighest: Color(0xFFC8C8C8),
)
```

## KoheraPalette factory

Add `KoheraPalette.nes(Brightness brightness)` to `kohera_palette.dart`,
mirroring the `.pico8` / `.gameboy` factories.

```dart
factory KoheraPalette.nes(Brightness brightness) {
  // NES.css accent palette
  const nesBlue   = Color(0xFF209cee);
  const nesGreen  = Color(0xFF92cc41);
  const nesYellow = Color(0xFFf7d51d);
  const nesRed    = Color(0xFFe76e55);
  const nesBase   = Color(0xFF212529); // near-black
  const nesBg     = Color(0xFFFFFFFF); // white

  if (brightness == Brightness.dark) {
    return const KoheraPalette(
      borderStrong: nesBase,                 // #212529 — NES.css base
      borderWidth: 4,                        // NES.css border-size (thicker than default)
      shadowHard:   Color(0xFF006bb3),       // NES primary shadow — blue offset
      shadowOffset: 4,                       // matches border width: flat stamp
      radius: 0,                             // sharp — NES.css buttons are square

      online:  nesGreen,                      // #92cc41
      idle:    nesYellow,                     // #f7d51d

      unread:  nesRed,                        // #e76e55
      onUnread: Color(0xFFFFFFFF),

      mention: nesYellow,                     // #f7d51d
      link:    nesBlue,                       // #209cee

      ownBubble:    nesBlue,                  // your messages = primary blue
      onOwnBubble:  Color(0xFFFFFFFF),
      otherBubble:  Color(0xFF3a4148),        // lifted dark grey
      onOtherBubble: Color(0xFFFFFFFF),

      success: nesGreen,
      warning: nesYellow,
      danger:  nesRed,

      scanline: Color(0x2E000000),            // black @ 18%
      dither:  Color(0xFF1a1e22),

      // NES hardware palette accents (subset of the 64-colour ramp)
      accentRamp: [
        nesBlue,   // 11: #0068F8-ish blue
        nesGreen,  // 19: green
        nesYellow, // 28: yellow
        nesRed,    // 16: red
        Color(0xFFf85898), // 25: pink
        Color(0xFFf87858), // 26: orange
      ],
    );
  }

  // Light variant — accent shadows become the "normal" tones for contrast.
  return const KoheraPalette(
    borderStrong: nesBase,                 // #212529
    borderWidth: 4,
    shadowHard:   Color(0xFFadafbc),        // NES.css default shadow grey
    shadowOffset: 4,
    radius: 0,

    online:  Color(0xFF4aa52e),             // green shadow (darker)
    idle:    Color(0xFFe59400),             // yellow shadow (darker)

    unread:  Color(0xFFce372b),             // red hover (darker)
    onUnread: Color(0xFFFFFFFF),

    mention: Color(0xFFe59400),
    link:    Color(0xFF006bb3),             // blue shadow (darker)

    ownBubble:    nesBlue,
    onOwnBubble:  Color(0xFFFFFFFF),
    otherBubble:  Color(0xFFEFEFEF),        // light grey
    onOtherBubble: nesBase,

    success: Color(0xFF4aa52e),
    warning: Color(0xFFe59400),
    danger:  Color(0xFFce372b),

    scanline: Color(0x1A000000),            // black @ 10% (lighter)
    dither:  Color(0xFFE0E0E0),

    accentRamp: [
      nesBlue,
      Color(0xFF4aa52e),
      Color(0xFFe59400),
      Color(0xFFce372b),
      Color(0xFFf85898),
      Color(0xFFf87858),
    ],
  );
}
```

## Differentiators vs other pixel themes

| Token          | NES        | PICO-8 | Game Boy | SNES        |
|----------------|------------|--------|----------|-------------|
| `borderWidth`  | **4**      | 2      | 2        | 2           |
| `radius`       | **0**      | 0      | 0        | 4 (soft)    |
| `shadowOffset`  | **4**      | 3      | 3        | 6           |
| shadow style   | flat stamp | flat   | flat     | beveled     |
| primary        | blue       | green  | green    | purple      |
| feel           | 8-bit hard | 8-bit  | 1-bit    | 16-bit soft |

The **`borderWidth: 4`** is the NES theme's headline differentiator — it is the
only preset that ships with the chunky NES.css border weight.

## Verification checklist

- [ ] `ThemePreset(id: 'nes')` appears in the pixel themes section.
- [ ] Picker chip shows seed `#209cee` labelled "NES".
- [ ] Dark mode: near-black `#212529` surfaces, blue primary, 4px borders.
- [ ] Light mode: white surfaces, `#212529` text, accents remain vivid.
- [ ] `KoheraPalette.nes` is selectable and `KoheraPalette.of` resolves it.
- [ ] `pixelBox` renders the 4px border + flat 4px offset shadow, no blur.
- [ ] Message bubbles: own = blue, other = lifted grey (dark) / light grey (light).
- [ ] `dart analyze` clean; theme switches with no layout shift.