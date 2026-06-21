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

GRAD_TOP = (37, 133, 224)     # #2585E0 — subtle lift above the seed
GRAD_BOTTOM = (13, 103, 196)  # #0D67C0 — subtle drop below the seed (midpoint = #1976D2)
ACCENT = (25, 118, 210, 255)  # #1976D2 — interior strokes (the original accent)
FG = (255, 255, 255, 255)     # white bubble


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


def _cap_dome(d, cx, top, w, h, fill):
    d.pieslice([cx - w / 2, top, cx + w / 2, top + 2 * h], 180, 360, fill=fill)
    return top + h


def _stem(d, cx, top, bottom, w_top, w_bot, fill):
    d.polygon([(cx - w_top / 2, top), (cx + w_top / 2, top),
               (cx + w_bot / 2, bottom), (cx - w_bot / 2, bottom)], fill=fill)
    d.ellipse([cx - w_bot / 2, bottom - w_bot * 0.35, cx + w_bot / 2, bottom + w_bot * 0.35], fill=fill)


def _dot(d, x, y, r, fill):
    d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def _mark_geometry(x0, y0, w, h, compact):
    """Compute the mark's coordinates once, shared by the PIL and SVG renderers.

    When `compact`, use fewer, bolder roots with larger nodes so the mark stays
    legible at favicon / small-launcher sizes where thin threads turn to mush.
    """
    cx = x0 + w / 2
    cap_top = y0 + h * 0.06
    cap_w, cap_h = w * 0.60, h * 0.20
    gill = cap_top + cap_h
    base_y = y0 + h * 0.50

    if compact:
        lw = w * 0.065
        tips = [(-0.34, 0.90), (0.0, 0.95), (0.34, 0.90)]
        tip_r, mid_r, base_r = w * 0.075, 0.0, w * 0.065
    else:
        lw = w * 0.035
        tips = [(-0.40, 0.92), (-0.18, 0.86), (0.04, 0.94), (0.26, 0.84), (0.42, 0.90)]
        tip_r, mid_r, base_r = w * 0.045, w * 0.028, w * 0.05

    roots = []
    for tx, ty in tips:
        ex, ey = x0 + w * (0.5 + tx), y0 + h * ty
        mx, my = (cx + ex) / 2 + w * tx * 0.10, (base_y + ey) / 2
        roots.append((mx, my, ex, ey))

    return {
        "cx": cx, "cap_top": cap_top, "cap_w": cap_w, "cap_h": cap_h, "gill": gill,
        "base_y": base_y, "stem_top_w": w * 0.15, "stem_bot_w": w * 0.17,
        "lw": lw, "tip_r": tip_r, "mid_r": mid_r, "base_r": base_r, "roots": roots,
    }


def draw_mark(img, x0, y0, w, h, compact=False):
    """Render the mushroom cap + mycelial root network into a content box of size w×h."""
    d = ImageDraw.Draw(img)
    g = _mark_geometry(x0, y0, w, h, compact)
    _cap_dome(d, g["cx"], g["cap_top"], g["cap_w"], g["cap_h"], FG)
    _stem(d, g["cx"], g["gill"], g["base_y"], g["stem_top_w"], g["stem_bot_w"], FG)

    lw = max(2, int(g["lw"]))
    for mx, my, ex, ey in g["roots"]:
        d.line([(g["cx"], g["base_y"]), (mx, my)], fill=FG, width=lw)
        d.line([(mx, my), (ex, ey)], fill=FG, width=lw)
        _dot(d, ex, ey, g["tip_r"], FG)
        if g["mid_r"]:
            _dot(d, mx, my, g["mid_r"], ACCENT)
    _dot(d, g["cx"], g["base_y"], g["base_r"], ACCENT)


def mark_svg():
    """Emit the monochrome mark as an SVG string from the same shared geometry.

    Single-colour (the consumer tints it via a colour filter) so the in-app logo
    can follow the theme while staying in lockstep with the rasterized icons.
    """
    g = _mark_geometry(0, 0, 100, 100, compact=False)
    cx, gill, base_y = g["cx"], g["gill"], g["base_y"]
    rx, ry = g["cap_w"] / 2, g["cap_h"]
    st, sb = g["stem_top_w"] / 2, g["stem_bot_w"] / 2

    def n(v):
        return f"{v:.2f}"

    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="currentColor">',
        f'<path d="M {n(cx - rx)} {n(gill)} A {n(rx)} {n(ry)} 0 0 1 {n(cx + rx)} {n(gill)} Z"/>',
        f'<polygon points="{n(cx - st)},{n(gill)} {n(cx + st)},{n(gill)} '
        f'{n(cx + sb)},{n(base_y)} {n(cx - sb)},{n(base_y)}"/>',
        f'<ellipse cx="{n(cx)}" cy="{n(base_y)}" rx="{n(sb)}" ry="{n(sb * 0.7)}"/>',
    ]
    for mx, my, ex, ey in g["roots"]:
        parts.append(
            f'<path d="M {n(cx)} {n(base_y)} L {n(mx)} {n(my)} L {n(ex)} {n(ey)}" '
            f'fill="none" stroke="currentColor" stroke-width="{n(g["lw"])}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
        )
        parts.append(f'<circle cx="{n(ex)}" cy="{n(ey)}" r="{n(g["tip_r"])}"/>')
    parts.append(f'<circle cx="{n(cx)}" cy="{n(base_y)}" r="{n(g["base_r"])}"/>')
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
