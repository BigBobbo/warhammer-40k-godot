#!/usr/bin/env python3
"""Render a terrain layout JSON to PNG for quick visual iteration.

Usage:
    python3 tools/render_layout.py 40k/terrain_layouts/layout_parse_test.json out.png
    python3 tools/render_layout.py <layout.json> <out.png> [--horizontal]

Board is 44" wide x 60" tall (vertical). North is up. Origin (0,0) is top-left.
With --horizontal, renders rotated 90 CW (so vertical board (x,y) -> (60-y, x))
to match the orientation of the source reference image.
"""

import json
import math
import sys
from PIL import Image, ImageDraw, ImageFont

BOARD_W_IN = 44.0
BOARD_H_IN = 60.0
PX_PER_IN = 12  # render scale

COLOR_BG = (40, 32, 24)
COLOR_GRID = (60, 50, 40)
COLOR_TALL_FILL = (60, 60, 65)      # gray hatched in source
COLOR_LOW_FILL = (60, 110, 170)     # blue rectangles in source
COLOR_MED_FILL = (110, 110, 60)
COLOR_OUTLINE = (120, 120, 120)
COLOR_WALL = (255, 240, 100)  # bright yellow so it stands out from outline
COLOR_CENTER = (255, 50, 50)
COLOR_TEXT = (255, 255, 255)


def rotate(px, py, cx, cy, deg):
    rad = math.radians(deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    dx, dy = px - cx, py - cy
    return (cx + dx * cos_a - dy * sin_a,
            cy + dx * sin_a + dy * cos_a)


def piece_corners(cx_in, cy_in, w_in, h_in, rot_deg):
    hx, hy = w_in / 2.0, h_in / 2.0
    local = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    rad = math.radians(rot_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    return [
        (cx_in + lx * cos_a - ly * sin_a,
         cy_in + lx * sin_a + ly * cos_a)
        for lx, ly in local
    ]


def render(json_path, out_path, horizontal=False):
    with open(json_path) as f:
        data = json.load(f)

    if horizontal:
        # Rotate vertical (44x60) -> horizontal (60x44) by 90 CW:
        #   (x_v, y_v) -> (60 - y_v, x_v),  rotation += 90
        # NOTE: the rotation adjustment is +90, not -90. For axis-aligned
        # rectangles both look the same (180-symmetric), but for walls
        # (line segments inside) -90 puts them on opposite corners.
        board_w_in = 60.0
        board_h_in = 44.0
    else:
        board_w_in = BOARD_W_IN
        board_h_in = BOARD_H_IN

    W = int(board_w_in * PX_PER_IN)
    H = int(board_h_in * PX_PER_IN)
    img = Image.new("RGB", (W, H), COLOR_BG)
    draw = ImageDraw.Draw(img, "RGBA")

    for i in range(0, int(board_w_in) + 1, 6):
        x = i * PX_PER_IN
        draw.line([(x, 0), (x, H)], fill=COLOR_GRID, width=1)
    for i in range(0, int(board_h_in) + 1, 6):
        y = i * PX_PER_IN
        draw.line([(0, y), (W, y)], fill=COLOR_GRID, width=1)

    cx_b, cy_b = board_w_in / 2, board_h_in / 2
    draw.line([(cx_b * PX_PER_IN, 0), (cx_b * PX_PER_IN, H)],
              fill=(80, 80, 80), width=1)
    draw.line([(0, cy_b * PX_PER_IN), (W, cy_b * PX_PER_IN)],
              fill=(80, 80, 80), width=1)

    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    except Exception:
        font = ImageFont.load_default()

    for piece in data["pieces"]:
        cx_in, cy_in = piece["position"]
        w_in, h_in = piece["size"]
        rot_deg = piece.get("rotation", 0)
        height = piece.get("height", "tall")
        if horizontal:
            cx_in, cy_in = 60.0 - cy_in, cx_in
            rot_deg += 90.0

        fill = {
            "tall": COLOR_TALL_FILL,
            "medium": COLOR_MED_FILL,
            "low": COLOR_LOW_FILL,
        }.get(height, COLOR_TALL_FILL)

        corners_in = piece_corners(cx_in, cy_in, w_in, h_in, rot_deg)
        corners_px = [(c[0] * PX_PER_IN, c[1] * PX_PER_IN) for c in corners_in]
        draw.polygon(corners_px, fill=fill, outline=COLOR_OUTLINE)

        for wall in piece.get("walls", []):
            s = wall["local_start"]
            e = wall["local_end"]
            sx, sy = rotate(s[0], s[1], 0, 0, rot_deg)
            ex, ey = rotate(e[0], e[1], 0, 0, rot_deg)
            sx_in, sy_in = cx_in + sx, cy_in + sy
            ex_in, ey_in = cx_in + ex, cy_in + ey
            draw.line(
                [(sx_in * PX_PER_IN, sy_in * PX_PER_IN),
                 (ex_in * PX_PER_IN, ey_in * PX_PER_IN)],
                fill=COLOR_WALL, width=5)

        label = piece.get("id", "")
        draw.text((cx_in * PX_PER_IN, cy_in * PX_PER_IN),
                  label, fill=COLOR_TEXT, font=font, anchor="mm")

    draw.ellipse([cx_b * PX_PER_IN - 4, cy_b * PX_PER_IN - 4,
                  cx_b * PX_PER_IN + 4, cy_b * PX_PER_IN + 4],
                 fill=COLOR_CENTER)

    img.save(out_path)
    print(f"wrote {out_path}  ({W}x{H})  {len(data['pieces'])} pieces")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    horizontal = "--horizontal" in sys.argv
    render(sys.argv[1], sys.argv[2], horizontal=horizontal)
