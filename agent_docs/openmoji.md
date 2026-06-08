# OpenMoji emoji rendering

Kohera renders Unicode emoji as bundled [OpenMoji](https://openmoji.org) images
rather than relying on each platform's emoji font, so emoji look identical on
Linux, macOS, and web. Custom emoji (emoji.gg / sticker packs) are unrelated —
they are image-based via `mxc://` and are not covered here.

## Render path

Everything funnels through one widget and one resolver:

- `lib/core/utils/openmoji.dart` — `openMojiAssetFor(grapheme)` maps a Unicode
  emoji to its bundled asset path, or `null` when none is bundled. It tries the
  literal codepoint sequence first, then the form with variation selectors
  (`U+FE0E`/`U+FE0F`) stripped, because OpenMoji keeps `FE0F` for keycaps
  (`0023-FE0F-20E3`) but drops it elsewhere (`2764`). Codepoints are zero-padded
  to four hex digits. Resolution is gated by the generated manifest
  `lib/core/utils/openmoji_manifest.g.dart`.
- `lib/shared/widgets/openmoji_image.dart` — `OpenMojiImage` is the single
  shared render + fallback path. It shows the OpenMoji asset, and falls back to
  system-font text (`emojiTextStyle`, `lib/core/utils/emoji_style.dart`) when no
  asset is bundled or the asset fails to load. It decodes at `cacheWidth` for
  the target size to bound memory.

Consumers:

- Inline message text — `buildEmojiSpans` (`lib/core/utils/emoji_spans.dart`)
  splits text into spans, wrapping each emoji run in `OpenMojiImage` (and keeps
  a plain `TextSpan` fallback for unbundled runs so text metrics are preserved).
- Reactions — `reaction_chips.dart` (chips, reactors sheet, react button).
- Quick-react bars — `hover_action_bar.dart`, `message_action_sheet.dart`. The
  hot set `kQuickReactEmojis` is warmed via `precacheOpenMoji`.
- Picker grid — `openmoji_picker.dart`, an in-house tabbed/searchable grid
  driven by `OpenMojiCatalog` (`lib/core/utils/openmoji_catalog.dart`) reading
  `assets/openmoji/metadata.json`.

## Asset footprint

- `assets/openmoji/*.png` — 4495 files, ~7 MB (72×72 color PNGs). These are the
  dominant cost; on native they ship in the app binary, on web they are fetched
  lazily per emoji.
- `assets/openmoji/metadata.json` — ~168 KB (picker categories + search index).
- `lib/core/utils/openmoji_manifest.g.dart` — ~93 KB generated source.

Committed as plain git blobs (not Git LFS). ~7 MB is acceptable; if it ever
needs trimming, subset the PNG set to the codepoints referenced by
`metadata.json` plus the skin-tone variants.

### Build/CI cost

The dominant cost is **file count, not bytes**. Flutter bundles every asset
into the build output (`build/unit_test_assets`, the app bundle) plus a
per-asset `AssetManifest` entry. Measured locally (SSD), bundling the 4495 PNGs
adds **~0.7–1.2 s per `flutter test`/`flutter build` invocation** (~3.9 s vs
~2.8 s for a trivial test with the asset dir removed). This is paid once per
job, so it lands on every CI test and build step; slower CI disks may see more.

If this becomes a bottleneck, the fix targets file count:
- **Subset** — `metadata.json` references ~1914 of the 4495 PNGs; trimming the
  set toward referenced codepoints (plus skin-tone variants) roughly halves the
  count. Cheap.
- **Sprite atlas** — pack the PNGs into a few large images + an index and have
  `openMojiAssetFor` return a sub-rect. Eliminates the file-count cost entirely;
  larger change, good as a dedicated follow-up.

Git LFS would help clone time but not bundling.

## Updating the asset set

1. Replace `assets/openmoji/*.png` from an OpenMoji `*-color` release.
2. Regenerate the manifest: `tool/gen_openmoji_manifest.sh`.
3. Regenerate the picker metadata from OpenMoji's `data/openmoji.json`:
   `python3 tool/gen_openmoji_metadata.py path/to/openmoji.json`.
