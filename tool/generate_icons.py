#!/usr/bin/env python3
"""Generate Kohera app icons for all platforms from a single pixel-art mark.

The mark is a 32×32 pixel-art mushroom above a mycelial root network — the
visible fruiting body and the hidden web through which fungi communicate,
echoing a decentralized chat network. Everything is drawn procedurally from
the shared MASK grid; there is no bitmap source asset. The in-app loader
(lib/shared/widgets/kohera_loader.dart) and the in-app SVG
(assets/icons/kohera_mark.svg) are rendered from the identical mask, so the
shipped launcher icons and the in-app branding stay in lockstep.
"""

import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Match the in-app logo exactly: a flat primaryContainer tile (#D4E3FF) with an
# onPrimaryContainer (#224876) mark, so the shipped icon and login logo are one.
BG = (255, 255, 255, 255)    # #FFFFFF — flat white tile (neutral, opaque)
FG = (34, 72, 118, 255)     # #224876 — onPrimaryContainer, the mark colour
GILL = (22, 47, 77, 255)     # darker primary (#162F4D) — gills under the cap
SPORE = (144, 163, 186, 255)  # lighter primary (#90A3BA) — spores falling

GRID = 32

# Gills: short ticks hanging under the cap rim, beside the stem (rows 9-10;
# the stem occupies x14-18 so these sit in the empty gill space either side).
GILL_GX = [7, 10, 13, 19, 22, 25]
GILL_ROWS = [9, 10]

# Spore positions in mask-grid coords (fractional ok): a frozen snapshot of
# spores released from the gills under the cap, falling down alongside the
# stem and dispersing before the mycelial fan (rows 20+).
SPORES = [
    (7.0,  9.5),
    (24.0, 9.5),
    (8.0, 12.0),
    (23.0, 12.0),
    (10.0, 14.5),
    (21.0, 14.5),
    (9.0, 17.0),
    (22.0, 17.0),
]

# ── Canonical 32×32 pixel mask ──────────────────────────────────────────────
# '#' = mark pixel, '.' = transparent. This is the single source of truth shared
# with the in-app loader mask and kohera_mark.svg (see mark_svg below).
MASK = [
    "................................",
    "............#####...............",
    ".........#############..........",
    ".......#################........",
    "......###################.......",
    "......####################......",
    ".....#####################......",
    ".....#####################......",
    ".....#####################......",
    "..............####..............",
    "..............#####.............",
    "..............#####.............",
    "..............#####.............",
    "...............####.............",
    "...............###..............",
    "...............###..............",
    "..............####..............",
    "..............####..............",
    "..............#####.............",
    ".............#######............",
    "............########............",
    "...........####.#.####..........",
    "..........##.#.##.#####.........",
    ".........##.##.##..#..##........",
    "........##..#...#..##..##.......",
    "......###..##..##...##..##......",
    ".....##...##...##...##...###....",
    "..####...##....##....###..####..",
    "..###...###....##....###...###..",
    "..###...###....##....###....##..",
    "..............####..............",
    "...............##...............",
]


def make_background(size, rounded):
    """Flat brand fill, masked to a rounded square or full square (hard edges)."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    fill = Image.new("RGBA", (size, size), BG)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    else:
        md.rectangle([0, 0, size - 1, size - 1], fill=255)
    out.paste(fill, (0, 0), mask)
    return out


def _mark_image():
    """The 32×32 mask as an RGBA image (FG where '#', transparent elsewhere)."""
    img = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(MASK):
        for x, c in enumerate(row):
            if c == "#":
                px[x, y] = FG
    return img


_MARK = _mark_image()


def _draw_gills(img, size, pad):
    """Short ticks hanging under the cap rim, beside the stem — the spore-
    bearing surface. One cell wide, drawn at mask-grid rows 9-10."""
    box = size - 2 * pad
    cell = box / GRID
    d = ImageDraw.Draw(img)
    for gx in GILL_GX:
        for gy in GILL_ROWS:
            x = pad + gx * cell
            y = pad + gy * cell
            d.rectangle([x, y, x + cell, y + cell], fill=GILL)


def _draw_spores(img, size, pad):
    """Stamp the falling spores at mask-grid coords (fractional). Released from
    the gills under the cap, drifting down alongside the stem. One spore = one
    mask cell, solid square so it shares the mushroom's hard pixel edges."""
    box = size - 2 * pad
    cell = box / GRID
    d = ImageDraw.Draw(img)
    for (gx, gy) in SPORES:
        x = pad + gx * cell
        y = pad + gy * cell
        d.rectangle([x, y, x + cell, y + cell], fill=SPORE)


def draw_mark(img, x0, y0, w, h, compact=False):
    """Stamp the pixel mask into a content box of size w×h, nearest-scaled.

    Nearest-neighbour scaling keeps the hard pixel edges intact at every icon
    size; no anti-aliasing is introduced, matching the pixel-art identity.
    """
    if w <= 0 or h <= 0:
        return
    stamp = _MARK.resize((int(round(w)), int(round(h))), Image.NEAREST)
    img.paste(stamp, (int(round(x0)), int(round(y0))), stamp)


def mark_svg():
    """Emit the monochrome mark as a crisp-edges SVG from the shared MASK.

    Consecutive '#' cells in a row merge into one <rect> so the output matches
    assets/icons/kohera_mark.svg exactly. Single-colour (the consumer tints it
    via a colour filter) so the in-app logo can follow the theme while staying
    in lockstep with the rasterized icons.
    """
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
        'fill="currentColor" shape-rendering="crispEdges">'
    ]
    for y, row in enumerate(MASK):
        x = 0
        while x < GRID:
            if row[x] == "#":
                run = 1
                while x + run < GRID and row[x + run] == "#":
                    run += 1
                parts.append(f'<rect x="{x}" y="{y}" width="{run}" height="1"/>')
                x += run
            else:
                x += 1
    parts.append("</svg>")
    return "\n".join(parts)


def render(size, mode):
    """Render the icon at `size`.

    Modes:
      rounded      — rounded corners, brand bg (Android legacy, macOS, web, windows)
      square       — square, opaque brand bg (iOS)
      maskable     — full-bleed bg, mark in safe zone (web maskable)
      adaptive_fg  — transparent bg, mark in 72dp safe zone (Android adaptive foreground)
      adaptive_bg  — full-bleed bg only, no mark (Android adaptive background)
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if mode in ("rounded", "square", "maskable", "adaptive_bg"):
        img = Image.alpha_composite(img, make_background(size, rounded=(mode == "rounded")))

    if mode != "adaptive_bg":
        # Full-icon platforms (rounded/square) pad 12 per the brand look; the
        # shape-cropped modes (maskable web, Android adaptive-fg) keep the mark
        # inside the launcher safe zone so the thread tips aren't chopped.
        if mode == "maskable":
            pad = size * 0.24
        elif mode == "adaptive_fg":
            pad = size * 0.21
        else:
            pad = size * 0.12
        draw_mark(img, pad, pad, size - 2 * pad, size - 2 * pad)
        _draw_gills(img, size, pad)
        _draw_spores(img, size, pad)

    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"  {os.path.relpath(path, ROOT)}")


# 108dp adaptive-icon layer size in px per density bucket
ADAPTIVE_PX = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
LAUNCHER_PX = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""


def generate_android():
    print("Android:")
    res = os.path.join(ROOT, "android/app/src/main/res")
    for density, size in LAUNCHER_PX.items():
        save(render(size, "rounded"), os.path.join(res, f"mipmap-{density}/ic_launcher.png"))
    for density, size in ADAPTIVE_PX.items():
        save(render(size, "adaptive_fg"), os.path.join(res, f"mipmap-{density}/ic_launcher_foreground.png"))
        save(render(size, "adaptive_bg"), os.path.join(res, f"mipmap-{density}/ic_launcher_background.png"))
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = os.path.join(res, f"mipmap-anydpi-v26/{name}")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(ADAPTIVE_XML)
        print(f"  {os.path.relpath(path, ROOT)}")


def generate_ios():
    print("iOS:")
    sizes = [20, 40, 60, 29, 58, 87, 40, 80, 120, 120, 180, 76, 152, 167, 1024]
    filenames = [
        "Icon-App-20x20@1x.png", "Icon-App-20x20@2x.png", "Icon-App-20x20@3x.png",
        "Icon-App-29x29@1x.png", "Icon-App-29x29@2x.png", "Icon-App-29x29@3x.png",
        "Icon-App-40x40@1x.png", "Icon-App-40x40@2x.png", "Icon-App-40x40@3x.png",
        "Icon-App-60x60@2x.png", "Icon-App-60x60@3x.png",
        "Icon-App-76x76@1x.png", "Icon-App-76x76@2x.png",
        "Icon-App-83.5x83.5@2x.png", "Icon-App-1024x1024@1x.png",
    ]
    base = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for size, fname in zip(sizes, filenames):
        save(render(size, "square").convert("RGB"), os.path.join(base, fname))


def generate_macos():
    print("macOS:")
    base = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        save(render(size, "rounded"), os.path.join(base, f"app_icon_{size}.png"))


def generate_web():
    print("Web:")
    web = os.path.join(ROOT, "web")
    save(render(32, "rounded"), os.path.join(web, "favicon.png"))
    for size in [192, 512]:
        save(render(size, "rounded"), os.path.join(web, f"icons/Icon-{size}.png"))
        save(render(size, "maskable"), os.path.join(web, f"icons/Icon-maskable-{size}.png"))


def generate_windows():
    print("Windows:")
    ico_sizes = [16, 32, 48, 64, 128, 256]
    images = [render(s, "rounded") for s in ico_sizes]
    ico_path = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    images[0].save(ico_path, format="ICO", sizes=[(s, s) for s in ico_sizes], append_images=images[1:])
    print(f"  {os.path.relpath(ico_path, ROOT)}")


def generate_linux():
    print("Linux:")
    save(render(512, "rounded"), os.path.join(ROOT, "linux/io.github.quantumheart.kohera.png"))


def generate_svg():
    print("SVG asset:")
    path = os.path.join(ROOT, "assets/icons/kohera_mark.svg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(mark_svg() + "\n")
    print(f"  {os.path.relpath(path, ROOT)}")


if __name__ == "__main__":
    print("Generating Kohera app icons — pixel-art mushroom + mycelial network mark\n")
    generate_android()
    generate_ios()
    generate_macos()
    generate_web()
    generate_windows()
    generate_linux()
    generate_svg()
    print("\nDone!")