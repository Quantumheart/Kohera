#!/usr/bin/env bash
# Regenerates lib/core/utils/openmoji_manifest.g.dart from the bundled
# OpenMoji PNG assets. Run after updating the asset set in assets/openmoji/.
set -euo pipefail
cd "$(dirname "$0")/.."

out=lib/core/utils/openmoji_manifest.g.dart
{
  echo "// GENERATED — do not edit by hand."
  echo "// Source: OpenMoji 72x72 color set (openmoji.org). Regenerate via tool/gen_openmoji_manifest.sh"
  echo "// Set of available OpenMoji asset base names (codepoint sequences, no extension)."
  echo "const Set<String> kOpenMojiNames = {"
  ls assets/openmoji/*.png | sed -E 's#.*/##; s#\.png$##' | sort | sed "s/.*/  '&',/"
  echo "};"
} > "$out"

echo "Wrote $out ($(ls assets/openmoji/*.png | wc -l | tr -d ' ') names)"
