#!/usr/bin/env python3
"""Generate Kohera app icons for all platforms from a single source rendering.

The mark is a mushroom above a mycelial root network — the visible fruiting body
and the hidden web through which fungi communicate, echoing a decentralized chat
network. Everything is drawn procedurally; there is no bitmap source asset.
"""

import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SS = 4  # supersample factor — render large, downscale with LANCZOS for crisp edges

# Match the in-app logo exactly: a flat primaryContainer tile (#D4E3FF) with an
# onPrimaryContainer (#224876) mark, so the shipped icon and login logo are one.
GRAD_TOP = (212, 227, 255)    # #D4E3FF — flat fill (top == bottom, no gradient)
GRAD_BOTTOM = (212, 227, 255)  # #D4E3FF
FG = (34, 72, 118, 255)       # #224876 — onPrimaryContainer, the mark colour
ACCENT = (34, 72, 118, 255)   # same as the mark — monochrome, matching the logo


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def make_background(size, rounded):
    """Vertical blue gradient, masked to a rounded square or full square."""
    grad = Image.new("RGB", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / max(1, size - 1)
        gd.line([(0, y), (size, y)], fill=lerp(GRAD_TOP, GRAD_BOTTOM, t))

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    else:
        md.rectangle([0, 0, size - 1, size - 1], fill=255)

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(grad.convert("RGBA"), (0, 0), mask)
    return out


# ── Mark geometry, normalised to a unit content box (0..1, origin top-left) ──
# The mushroom is deliberately asymmetric: a left-of-centre cap apex with a
# fuller right shoulder, a stem that bows to the right, and curved threads —
# one of which forks — fanning out to nodes. No base flare, so the stem flows
# straight into the threads instead of bulging.

# Cap: two cubics; the polygon auto-closes along a slightly tilted bottom rim.
_CAP = [
    ((0.17, 0.28), (0.15, 0.07), (0.39, 0.03), (0.51, 0.05)),
    ((0.51, 0.05), (0.67, 0.07), (0.86, 0.12), (0.81, 0.27)),
]

# Stem outline: a cubic down the left edge, a line across the base, a cubic up
# the right edge. Both edges bow right, so the stem leans.
_STEM = [
    ("c", (0.43, 0.27), (0.46, 0.36), (0.47, 0.44), (0.46, 0.50)),
    ("l", (0.55, 0.50)),
    ("c", (0.55, 0.50), (0.59, 0.44), (0.58, 0.36), (0.56, 0.27)),
]

# Thread origins are tucked inside the stem foot (centred on 0.505, within its
# 0.46–0.55 width) so the threads emerge as a bundle under the stem and only
# splay lower down — none poke past the stem edges. The fan is symmetric.
_TRUNK = ((0.505, 0.50), (0.505, 0.58), (0.51, 0.65), (0.51, 0.71))

_FULL = {
    "lw": 0.035,
    "fork": ((0.51, 0.71), 0.026),
    "roots": [
        {"segs": [((0.478, 0.50), (0.47, 0.62), (0.30, 0.75), (0.11, 0.89))],
         "tip": (0.11, 0.89), "node": 0.046},
        {"segs": [((0.4915, 0.50), (0.485, 0.63), (0.37, 0.80), (0.30, 0.90))],
         "tip": (0.30, 0.90), "node": 0.040},
        {"segs": [_TRUNK, ((0.51, 0.71), (0.50, 0.80), (0.46, 0.88), (0.41, 0.93))],
         "tip": (0.41, 0.93), "node": 0.050},
        {"segs": [_TRUNK, ((0.51, 0.71), (0.53, 0.80), (0.57, 0.88), (0.61, 0.91))],
         "tip": (0.61, 0.91), "node": 0.043},
        {"segs": [((0.5185, 0.50), (0.525, 0.63), (0.64, 0.78), (0.71, 0.90))],
         "tip": (0.71, 0.90), "node": 0.045},
        {"segs": [((0.532, 0.50), (0.54, 0.62), (0.72, 0.74), (0.90, 0.89))],
         "tip": (0.90, 0.89), "node": 0.039},
    ],
}

# Compact: three bold threads, no fork, big nodes — legible at favicon sizes.
_COMPACT = {
    "lw": 0.065,
    "fork": None,
    "roots": [
        {"segs": [((0.49, 0.50), (0.46, 0.63), (0.33, 0.77), (0.22, 0.90))],
         "tip": (0.22, 0.90), "node": 0.075},
        {"segs": [((0.505, 0.50), (0.505, 0.66), (0.51, 0.80), (0.51, 0.93))],
         "tip": (0.51, 0.93), "node": 0.075},
        {"segs": [((0.52, 0.50), (0.55, 0.63), (0.67, 0.77), (0.78, 0.90))],
         "tip": (0.78, 0.90), "node": 0.075},
    ],
}


def _bezier(seg, steps=28):
    p0, p1, p2, p3 = seg
    pts = []
    for i in range(steps + 1):
        u = i / steps
        mu = 1 - u
        a, b, c, dd = mu * mu * mu, 3 * mu * mu * u, 3 * mu * u * u, u * u * u
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + dd * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + dd * p3[1]))
    return pts


def draw_mark(img, x0, y0, w, h, compact=False):
    """Render the mushroom cap + mycelial network into a content box of size w×h."""
    d = ImageDraw.Draw(img)

    def S(p):
        return (x0 + p[0] * w, y0 + p[1] * h)

    cap = []
    for seg in _CAP:
        cap += _bezier(seg)
    d.polygon([S(p) for p in cap], fill=FG)

    stem = []
    for s in _STEM:
        if s[0] == "c":
            pts = _bezier(s[1:])
            stem += pts[1:] if stem else pts
        else:
            stem.append(s[1])
    d.polygon([S(p) for p in stem], fill=FG)

    g = _COMPACT if compact else _FULL
    lw = max(2, int(g["lw"] * w))
    for leg in g["roots"]:
        pts = []
        for seg in leg["segs"]:
            sp = _bezier(seg)
            pts += sp[1:] if pts else sp
        d.line([S(p) for p in pts], fill=FG, width=lw, joint="curve")
        tx, ty = S(leg["tip"])
        r = leg["node"] * w
        d.ellipse([tx - r, ty - r, tx + r, ty + r], fill=FG)
    if g["fork"]:
        (fx, fy), r = S(g["fork"][0]), g["fork"][1] * w
        d.ellipse([fx - r, fy - r, fx + r, fy + r], fill=FG)


def mark_svg():
    """Emit the monochrome mark as an SVG string from the same shared geometry.

    Single-colour (the consumer tints it via a colour filter) so the in-app logo
    can follow the theme while staying in lockstep with the rasterized icons.
    """
    def n(p):
        return f"{p[0] * 100:.2f} {p[1] * 100:.2f}"

    def cubic_path(segs):
        d = f"M {n(segs[0][0])}"
        for seg in segs:
            d += f" C {n(seg[1])} {n(seg[2])} {n(seg[3])}"
        return d

    cap = f'{cubic_path(_CAP)} Z'
    stem_d = f"M {n(_STEM[0][1])} C {n(_STEM[0][2])} {n(_STEM[0][3])} {n(_STEM[0][4])}"
    stem_d += f" L {n(_STEM[1][1])}"
    stem_d += f" C {n(_STEM[2][2])} {n(_STEM[2][3])} {n(_STEM[2][4])} Z"

    lw = _FULL["lw"] * 100
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="currentColor">',
        f'<path d="{cap}"/>',
        f'<path d="{stem_d}"/>',
    ]
    for leg in _FULL["roots"]:
        parts.append(
            f'<path d="{cubic_path(leg["segs"])}" fill="none" stroke="currentColor" '
            f'stroke-width="{lw:.2f}" stroke-linecap="round" stroke-linejoin="round"/>'
        )
    if _FULL["fork"]:
        (fx, fy), fr = _FULL["fork"][0], _FULL["fork"][1]
        parts.append(f'<circle cx="{fx * 100:.2f}" cy="{fy * 100:.2f}" r="{fr * 100:.2f}"/>')
    for leg in _FULL["roots"]:
        ex, ey = leg["tip"]
        parts.append(
            f'<circle cx="{ex * 100:.2f}" cy="{ey * 100:.2f}" r="{leg["node"] * 100:.2f}"/>'
        )
    parts.append("</svg>")
    return "\n".join(parts)


def render(size, mode):
    """Render the icon at `size`.

    Modes:
      rounded      — rounded corners, gradient bg (Android legacy, macOS, web, windows)
      square       — square, opaque gradient bg (iOS)
      maskable     — full-bleed gradient, mark in safe zone (web maskable)
      adaptive_fg  — transparent bg, mark in the 72dp safe zone (Android adaptive foreground)
      adaptive_bg  — full-bleed gradient only, no mark (Android adaptive background)
    """
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    if mode in ("rounded", "square", "maskable", "adaptive_bg"):
        bg = make_background(s, rounded=(mode == "rounded"))
        img = Image.alpha_composite(img, bg)

    if mode == "maskable":
        pad = s * 0.30
    elif mode == "square":
        pad = s * 0.16
    elif mode == "adaptive_fg":
        pad = s * 0.21  # keep mark inside the 72dp safe zone of the 108dp layer
    else:
        pad = s * 0.18

    if mode != "adaptive_bg":
        draw_mark(img, pad, pad, s - 2 * pad, s - 2 * pad, compact=size < 64)

    return img.resize((size, size), Image.LANCZOS)


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
    print("Generating Kohera app icons — mushroom + mycelial network mark\n")
    generate_android()
    generate_ios()
    generate_macos()
    generate_web()
    generate_windows()
    generate_linux()
    generate_svg()
    print("\nDone!")
