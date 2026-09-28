#!/usr/bin/env python3
"""
Generates RankIt's App Icon (light/dark/tinted) and launch-screen mark,
committed so the artwork is reproducible without any design tool.

Concept: a three-bar ranking podium (tallest bar in the middle, matching
Beli/Letterboxd-style tiered ranking -- the app's whole premise) with a
five-point star over the #1 bar, on the app's accent-purple background.
Deliberately generic geometric shapes -- no film reel, clapperboard,
ticket, or studio-logo imagery.

Usage: python3 scripts/generate_app_icon.py
Requires: Pillow (`pip install pillow`)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "RankIt", "Resources", "Assets.xcassets")

# RankIt's accent color -- see the AccentColor colorset for the rationale.
ACCENT_LIGHT = (108, 92, 231)   # #6C5CE7
ACCENT_DARK_BG = (43, 33, 84)   # #2B2154 -- a deep, muted shade of the same hue
BAR_LIGHT = (255, 255, 255)     # bars/star on the light + dark icon variants
STAR_GOLD = (255, 209, 102)     # #FFD166 -- warm gold star, distinct from the bars


def rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def five_point_star(cx, cy, outer_r, inner_r, rotation_deg=-90):
    points = []
    for i in range(10):
        angle = math.radians(rotation_deg + i * 36)
        r = outer_r if i % 2 == 0 else inner_r
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    return points


def vertical_gradient(size, top_color, bottom_color):
    w, h = size
    base = Image.new("RGB", (1, h), color=0)
    for y in range(h):
        t = y / max(h - 1, 1)
        row = tuple(int(top_color[i] + (bottom_color[i] - top_color[i]) * t) for i in range(3))
        base.putpixel((0, y), row)
    return base.resize((w, h))


def draw_podium(img_size, bg_top, bg_bottom, bar_color, star_color, grayscale=False):
    size = img_size
    canvas = vertical_gradient((size, size), bg_top, bg_bottom).convert("RGB")
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Three ranked bars -- center (#1) tallest, left (#2) mid, right (#3) shortest.
    bar_w = size * 0.16
    gap = size * 0.06
    base_y = size * 0.78
    heights = [0.30, 0.46, 0.22]  # left(#2), center(#1), right(#3), as fraction of size
    centers_x = [
        size * 0.5 - bar_w - gap,
        size * 0.5,
        size * 0.5 + bar_w + gap,
    ]
    radius = bar_w * 0.28

    for cx, h_frac in zip(centers_x, heights):
        bar_h = size * h_frac
        box = (cx - bar_w / 2, base_y - bar_h, cx + bar_w / 2, base_y)
        rounded_rect(draw, box, radius, bar_color)

    # Baseline strip grounding the podium.
    draw.rounded_rectangle(
        (size * 0.16, base_y - size * 0.012, size * 0.84, base_y + size * 0.02),
        radius=size * 0.01,
        fill=bar_color,
    )

    # Star over the #1 (center) bar.
    star_cx = centers_x[1]
    star_cy = base_y - size * heights[1] - size * 0.14
    star_pts = five_point_star(star_cx, star_cy, outer_r=size * 0.12, inner_r=size * 0.046)
    draw.polygon(star_pts, fill=star_color)

    if grayscale:
        canvas = canvas.convert("L").convert("RGB")

    return canvas


def save_icon(img, path):
    img = img.convert("RGB")  # App Store icons must not carry an alpha channel.
    img.save(path, "PNG")
    print(f"wrote {path}")


def generate_app_icons():
    out_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    size = 1024

    light = draw_podium(size, ACCENT_LIGHT, (74, 61, 200), BAR_LIGHT, STAR_GOLD)
    save_icon(light, os.path.join(out_dir, "AppIcon-1024.png"))

    dark = draw_podium(size, ACCENT_DARK_BG, (20, 15, 46), BAR_LIGHT, STAR_GOLD)
    save_icon(dark, os.path.join(out_dir, "AppIcon-1024-dark.png"))

    # Tinted (iOS 18 "monochrome" home screen icons): a grayscale rendering
    # -- the system applies the user's chosen tint color on top of this.
    tinted = draw_podium(size, ACCENT_LIGHT, (74, 61, 200), BAR_LIGHT, STAR_GOLD, grayscale=True)
    save_icon(tinted, os.path.join(out_dir, "AppIcon-1024-tinted.png"))


def generate_launch_mark():
    """A transparent-background version of the same mark (bars + star, no
    background fill) for the launch screen, sized for @1x/@2x/@3x at 168pt."""
    out_dir = os.path.join(ASSETS, "LaunchLogo.imageset")
    os.makedirs(out_dir, exist_ok=True)

    base_size = 168 * 3  # render at @3x, downsample for @2x/@1x
    canvas = Image.new("RGBA", (base_size, base_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas, "RGBA")

    bar_w = base_size * 0.16
    gap = base_size * 0.06
    base_y = base_size * 0.78
    heights = [0.30, 0.46, 0.22]
    centers_x = [
        base_size * 0.5 - bar_w - gap,
        base_size * 0.5,
        base_size * 0.5 + bar_w + gap,
    ]
    radius = bar_w * 0.28

    for cx, h_frac in zip(centers_x, heights):
        bar_h = base_size * h_frac
        box = (cx - bar_w / 2, base_y - bar_h, cx + bar_w / 2, base_y)
        rounded_rect(draw, box, radius, BAR_LIGHT)

    draw.rounded_rectangle(
        (base_size * 0.16, base_y - base_size * 0.012, base_size * 0.84, base_y + base_size * 0.02),
        radius=base_size * 0.01,
        fill=BAR_LIGHT,
    )

    star_cx = centers_x[1]
    star_cy = base_y - base_size * heights[1] - base_size * 0.14
    star_pts = five_point_star(star_cx, star_cy, outer_r=base_size * 0.12, inner_r=base_size * 0.046)
    draw.polygon(star_pts, fill=STAR_GOLD)

    for scale, suffix in [(1, ""), (2, "@2x"), (3, "@3x")]:
        target = 168 * scale
        resized = canvas.resize((target, target), Image.LANCZOS)
        path = os.path.join(out_dir, f"LaunchLogo{suffix}.png")
        resized.save(path, "PNG")
        print(f"wrote {path}")


if __name__ == "__main__":
    generate_app_icons()
    generate_launch_mark()
