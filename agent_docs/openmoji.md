# OpenMoji emoji rendering

Kohera renders Unicode emoji with the bundled [OpenMoji](https://openmoji.org)
color font rather than relying on each platform's emoji font, so emoji look
identical on Linux, macOS, web, and mobile. Custom emoji (emoji.gg / sticker
packs) are unrelated — they are image-based via `mxc://` and are not covered
here.

The set previously shipped as ~4500 individual 72×72 PNGs (~7.7 MB of bytes,
and far more on-disk/CI cost from the file count). It now ships as a single
COLRv1 vector font (`assets/fonts/OpenMoji-color.ttf`, ~2.4 MB), declared under
`fonts:` in `pubspec.yaml` with family `OpenMoji`.

## Render path

Everything funnels through one widget and one resolver:

- `lib/core/utils/openmoji.dart` — `openMojiNameFor(grapheme)` maps a Unicode
  emoji to its OpenMoji codepoint-sequence name, or `null` when the grapheme is
  not in the set. It tries the literal codepoint sequence first, then the form
  with variation selectors (`U+FE0E`/`U+FE0F`) stripped, because OpenMoji keeps
  `FE0F` for keycaps (`0023-FE0F-20E3`) but drops it elsewhere (`2764`).
  Codepoints are zero-padded to four hex digits. Resolution is gated by the
  generated manifest `lib/core/utils/openmoji_manifest.g.dart`, and the gate
  also drives skin-tone support (`openMojiSupportsSkinTone`, `applySkinTone`).
  `openMojiFontFamily` is the font family constant.
- `lib/shared/widgets/openmoji_image.dart` — `OpenMojiImage` is the single
  shared render + fallback path. For in-set graphemes it renders the emoji as
  `Text` styled with `openMojiFontFamily` (sized to its box); for anything else
  it falls back to system-font text (`emojiTextStyle`,
  `lib/core/utils/emoji_style.dart`).
- `useBundledOpenMoji` (`lib/core/utils/openmoji.dart`) gates the bundled font.
  It is `false` on native iOS, where Impeller does not paint COLRv1 color glyphs
  (the glyph is selected but renders transparent, so emoji show blank). There
  `OpenMojiImage` renders every emoji through the system color emoji font
  (`emojiFontFallback`) instead. Flutter web (CanvasKit/Skia, including iOS
  Safari) and all other platforms keep the bundled OpenMoji font.

Consumers:

- Inline message text — `buildEmojiSpans` (`lib/core/utils/emoji_spans.dart`)
  splits text into spans, wrapping each emoji run in `OpenMojiImage` (and keeps
  a plain `TextSpan` fallback for unbundled runs so text metrics are preserved).
- Reactions — `reaction_chips.dart` (chips, reactors sheet, react button).
- Quick-react bars — `hover_action_bar.dart`, `message_action_sheet.dart`.
- Picker grid — `openmoji_picker.dart`, an in-house tabbed/searchable grid
  driven by `OpenMojiCatalog` (`lib/core/utils/openmoji_catalog.dart`) reading
  `assets/openmoji/metadata.json`.

## Asset footprint

- `assets/fonts/OpenMoji-color.ttf` — single COLRv1 color font, ~2.4 MB. Ships
  once in the app binary; glyph shaping (ZWJ sequences, keycaps, flags, skin
  tones) is handled by the text engine.
- `assets/openmoji/metadata.json` — ~208 KB (picker categories + search index).
- `lib/core/utils/openmoji_manifest.g.dart` — ~93 KB generated source (the
  render gate / skin-tone support set).

Committed as plain git blobs (not Git LFS). Replacing the ~4500 individual PNGs
with one font collapses the dominant file-count cost (per-asset `AssetManifest`
entries + on-disk block overhead) and cuts bundled bytes from ~7.7 MB to ~2.4 MB.

> Rendering note: the font is **COLRv1**. Skia (desktop, web/CanvasKit) renders
> it, but Impeller on **native iOS** does not paint COLRv1 glyphs — they show
> blank — so iOS falls back to the system emoji font via `useBundledOpenMoji`.
> Re-verify emoji render (not tofu, not blank) on real iOS/Android devices after
> a Flutter SDK bump; if Impeller gains COLRv1 support, the iOS branch of
> `useBundledOpenMoji` can be removed.

## Updating the font

1. Replace `assets/fonts/OpenMoji-color.ttf` from an OpenMoji release
   (`font/OpenMoji-color-glyf_colr_1/OpenMoji-color-glyf_colr_1.ttf`).
2. Regenerate the manifest from the matching source data:
   `tool/gen_openmoji_manifest.sh path/to/openmoji.json`.
3. Regenerate the picker metadata:
   `python3 tool/gen_openmoji_metadata.py path/to/openmoji.json`.
