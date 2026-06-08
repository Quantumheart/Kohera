#!/usr/bin/env python3
"""Generate assets/openmoji/metadata.json for the in-house emoji picker.

Source: OpenMoji metadata (data/openmoji.json from the OpenMoji repo).
Keeps base (no skin-tone) emoji from the standard Unicode groups that have a
bundled PNG asset, grouped and ordered for the picker. Each entry is
{e: emoji, n: hexcode/asset-name, a: annotation, s: search text}.

Usage: python3 tool/gen_openmoji_metadata.py path/to/openmoji.json
"""
import json
import os
import sys

GROUPS = [
    "smileys-emotion",
    "people-body",
    "animals-nature",
    "food-drink",
    "travel-places",
    "activities",
    "objects",
    "symbols",
    "flags",
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(src):
    data = json.load(open(src))
    available = {
        f[:-4]
        for f in os.listdir(os.path.join(ROOT, "assets/openmoji"))
        if f.endswith(".png")
    }

    buckets = {g: [] for g in GROUPS}
    for e in data:
        if e.get("skintone"):
            continue
        g = e["group"]
        if g not in buckets:
            continue
        name = e["hexcode"]
        if name not in available:
            continue
        annotation = e.get("annotation", "")
        search = " ".join(filter(None, [annotation, e.get("tags", "")])).lower()
        buckets[g].append((
            e.get("order") or 0,
            {"e": e["emoji"], "n": name, "a": annotation, "s": search},
        ))

    groups = []
    total = 0
    for g in GROUPS:
        items = [x for _, x in sorted(buckets[g], key=lambda t: t[0])]
        groups.append({"key": g, "emoji": items})
        total += len(items)

    out = os.path.join(ROOT, "assets/openmoji/metadata.json")
    with open(out, "w") as f:
        json.dump({"groups": groups}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Wrote {out}: {total} emoji across {len(groups)} groups")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/openmoji.json")
