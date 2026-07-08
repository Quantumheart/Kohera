#!/usr/bin/env bash
# Regenerate the Kpixel icon font from the upstream pixelarticons SVGs.
#
# Source SVGs live in tool/kpixel/svg (pinned snapshot of
# https://github.com/halfmage/pixelarticons @ efb6e172, MIT). Replacing the
# directory refreshes the set. Run from the repo root:
#
#   tool/kpixel/regenerate.sh
#
# Requires icon_font_generator: `dart pub global activate icon_font_generator`
# and `$HOME/.pub-cache/bin` on PATH.
set -euo pipefail

SVG_DIR="tool/kpixel/svg"
OUT_FONT="assets/fonts/kpixel.otf"
OUT_CLASS="lib/core/theme/kpixel.dart"

command -v generator >/dev/null 2>&1 || {
  echo "generator not found. Run: dart pub global activate icon_font_generator" >&2
  exit 1
}

generator "$SVG_DIR" "$OUT_FONT" \
  --output-class-file="$OUT_CLASS" \
  --class-name=Kpixel \
  --font-name=Kpixel

# The generator does not sanitize Dart reserved/built-in identifiers used as
# SVG filenames (switch, library, factory). Rename them so the class compiles.
sed -i '' -E 's/static const IconData switch =/static const IconData switchIcon =/' "$OUT_CLASS"
sed -i '' -E 's/static const IconData library =/static const IconData libraryIcon =/' "$OUT_CLASS"
sed -i '' -E 's/static const IconData factory =/static const IconData factoryIcon =/' "$OUT_CLASS"

echo "Regenerated $OUT_FONT and $OUT_CLASS"
echo "Reminder: re-run \`flutter pub get\` and \`flutter test --update-goldens\` if glyphs changed shape."