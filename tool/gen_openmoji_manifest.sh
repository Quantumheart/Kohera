#!/usr/bin/env bash
# Regenerates lib/core/utils/openmoji_manifest.g.dart from the OpenMoji source
# metadata (data/openmoji.json from the OpenMoji repo). The manifest is the gate
# deciding which graphemes render through the bundled OpenMoji color font
# (assets/fonts/OpenMoji-color.ttf); the font is built from the same source set.
# Run after updating the font.
#
# Usage: tool/gen_openmoji_manifest.sh path/to/openmoji.json
set -euo pipefail
cd "$(dirname "$0")/.."

src="${1:-/tmp/openmoji.json}"
out=lib/core/utils/openmoji_manifest.g.dart

python3 - "$src" "$out" <<'PY'
import json
import sys

src, out = sys.argv[1], sys.argv[2]
data = json.load(open(src))
names = sorted({e["hexcode"] for e in data})
with open(out, "w") as f:
    f.write("// GENERATED — do not edit by hand.\n")
    f.write("// Source: OpenMoji source metadata (openmoji.org data/openmoji.json).\n")
    f.write("// Regenerate via tool/gen_openmoji_manifest.sh.\n")
    f.write("// Set of OpenMoji names (codepoint sequences) covered by the bundled font.\n")
    f.write("const Set<String> kOpenMojiNames = {\n")
    for n in names:
        f.write(f"  '{n}',\n")
    f.write("};\n")
print(f"Wrote {out} ({len(names)} names)")
PY
