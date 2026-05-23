#!/usr/bin/env python3
"""Precise piece detector for terrain layout reference images.

Uses background segmentation rather than per-piece color matching:
  1. Identify the board's light-gray background pixels.
  2. Everything else inside the board area is either a piece, an annotation
     (red arrows, bullseyes, numbers), or noise (image edges).
  3. Find connected components of non-background pixels.
  4. For each component:
     - Compute axis-aligned bbox.
     - Reject if too small or if mostly red (annotations).
     - Classify as 'tall' if mostly gray, 'low' if mostly blue.
     - Output bbox in inches using the board's calibrated px/inch.

This deliberately does NOT try to handle L-shapes or merged components in
a fancy way. The user can decompose multi-piece footprints manually after
seeing exact bboxes.

Usage:
    python3 tools/detect_pieces_precise.py <image> [--out <debug.png>]
"""

import argparse
import json
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont


# Board is 60"x44" horizontal. Left ~6% of image is the "TERRAIN LAYOUT N" tab.
LEFT_CROP_FRAC = 0.06
BOARD_W_IN = 60.0
BOARD_H_IN = 44.0


def find_board_bounds(arr):
    """Find the playing-area bounds in pixels by detecting light-gray background.
    Returns (x0, y0, x1, y1) inclusive bounds."""
    gray = arr.mean(axis=2)
    bg = (gray > 200) & (gray < 245)
    H, W = bg.shape
    # Largest connected region of background = the playing area
    # (Or just take the bounding box of the bg mask.)
    rows = np.where(bg.any(axis=1))[0]
    cols = np.where(bg.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return 0, 0, W - 1, H - 1
    return cols.min(), rows.min(), cols.max(), rows.max()


def classify_pixel(r, g, b):
    """Return 'tall' (gray hatched), 'low' (blue), 'red' (annotation), or
    'bg' (background)."""
    # Background: light gray to white
    if r > 195 and g > 195 and b > 195:
        return 'bg'
    # Red (objectives, measurement arrows, numbers in red circles)
    if r > 130 and g < 80 and b < 80:
        return 'red'
    # Blue: dark blue ruins
    if r < 50 and 50 < g < 130 and 100 < b < 170 and b > r + 60:
        return 'low'
    # Gray (any darkness): hatching stripes, solid wall fill
    if abs(int(r) - int(g)) < 25 and abs(int(g) - int(b)) < 25 \
            and abs(int(r) - int(b)) < 25 and r < 200:
        return 'tall'
    return 'other'


def build_class_mask(arr):
    """Build a per-pixel classification array."""
    r = arr[..., 0].astype(np.int16)
    g = arr[..., 1].astype(np.int16)
    b = arr[..., 2].astype(np.int16)

    bg = (r > 195) & (g > 195) & (b > 195)
    red = (r > 130) & (g < 80) & (b < 80)
    low = (r < 50) & (g > 50) & (g < 130) & (b > 100) & (b < 170) & (b > r + 60)
    gray = (np.abs(r - g) < 25) & (np.abs(g - b) < 25) & (np.abs(r - b) < 25) \
           & (r < 200) & ~bg & ~red

    # Class codes: 0 bg, 1 tall (gray), 2 low (blue), 3 red, 4 other
    cls = np.zeros(r.shape, dtype=np.uint8)
    cls[gray] = 1
    cls[low] = 2
    cls[red] = 3
    cls[~(bg | gray | low | red)] = 4
    return cls


def flood(mask, x0, y0):
    """BFS over True pixels. Returns the (x, y) list."""
    H, W = mask.shape
    q = deque([(x0, y0)])
    pts = []
    while q:
        x, y = q.popleft()
        if x < 0 or x >= W or y < 0 or y >= H or not mask[y, x]:
            continue
        mask[y, x] = False
        pts.append((x, y))
        q.extend([(x+1, y), (x-1, y), (x, y+1), (x, y-1)])
    return pts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--out', default='/tmp/precise_detect.png')
    ap.add_argument('--min-area-in', type=float, default=4.0,
                    help='Minimum component area in square inches')
    ap.add_argument('--json-out', default=None,
                    help='Path to write a clean JSON of detected blobs '
                         '(suitable for piping to match_to_catalog.py)')
    args = ap.parse_args()

    img = Image.open(args.image).convert('RGB')
    arr = np.array(img)
    H, W, _ = arr.shape
    L = int(W * LEFT_CROP_FRAC)
    arr = arr[:, L:, :]
    H, W, _ = arr.shape

    # Find board bounds within cropped image
    x0, y0, x1, y1 = find_board_bounds(arr)
    board_w_px = x1 - x0 + 1
    board_h_px = y1 - y0 + 1
    px_per_in_w = board_w_px / BOARD_W_IN
    px_per_in_h = board_h_px / BOARD_H_IN
    px_per_in = (px_per_in_w + px_per_in_h) / 2
    print(f"Cropped image: {W}x{H}")
    print(f"Board bounds in pixels: ({x0},{y0}) to ({x1},{y1})")
    print(f"Board size: {board_w_px}x{board_h_px} px = "
          f"{px_per_in_w:.3f} x {px_per_in_h:.3f} px/in (avg {px_per_in:.3f})")

    # Classify all pixels
    cls = build_class_mask(arr)

    min_area_px = args.min_area_in * px_per_in * px_per_in
    print(f"Min component area: {min_area_px:.0f} px ({args.min_area_in} in^2)")

    pieces = []

    # Erode tall mask slightly to break thin "bridges" between adjacent pieces
    # that touch only at a 1-2 px wide gap.
    tall_mask = (cls == 1).copy()
    # Light erosion: a tall pixel stays only if all 4 neighbors are also tall
    tall_eroded = tall_mask.copy()
    tall_eroded[1:-1, 1:-1] = (tall_mask[1:-1, 1:-1] &
                               tall_mask[:-2, 1:-1] &
                               tall_mask[2:, 1:-1] &
                               tall_mask[1:-1, :-2] &
                               tall_mask[1:-1, 2:])

    for kind, mask in [('tall', tall_eroded.copy()), ('low', (cls == 2).copy())]:
        work = mask.copy()
        for y_px in range(H):
            for x_px in range(W):
                if work[y_px, x_px]:
                    pts = flood(work, x_px, y_px)
                    if len(pts) < min_area_px:
                        continue
                    xs = [p[0] for p in pts]
                    ys = [p[1] for p in pts]
                    xmin, xmax = min(xs), max(xs)
                    ymin, ymax = min(ys), max(ys)
                    cx_px = (xmin + xmax) / 2
                    cy_px = (ymin + ymax) / 2
                    w_px = xmax - xmin + 1
                    h_px = ymax - ymin + 1
                    # Convert to inches relative to BOARD origin
                    cx_in = (cx_px - x0) / px_per_in_w
                    cy_in = (cy_px - y0) / px_per_in_h
                    w_in = w_px / px_per_in_w
                    h_in = h_px / px_per_in_h
                    fill = len(pts) / (w_px * h_px)
                    pieces.append({
                        'kind': kind,
                        'cx_in': round(cx_in, 2),
                        'cy_in': round(cy_in, 2),
                        'w_in': round(w_in, 2),
                        'h_in': round(h_in, 2),
                        'cx_px': cx_px,
                        'cy_px': cy_px,
                        'w_px': w_px,
                        'h_px': h_px,
                        'area_px': len(pts),
                        'fill': round(fill, 2),
                    })

    pieces.sort(key=lambda p: (p['cy_in'], p['cx_in']))
    print(f"\nDetected {sum(p['kind']=='tall' for p in pieces)} tall + "
          f"{sum(p['kind']=='low' for p in pieces)} low = {len(pieces)} pieces:")
    for i, p in enumerate(pieces):
        print(f"  [{i:2d}] {p['kind']:5s} center=({p['cx_in']:5.2f},{p['cy_in']:5.2f})  "
              f"size={p['w_in']:5.2f}x{p['h_in']:5.2f}  fill={p['fill']}  "
              f"area={p['area_px']}px")

    # Save debug overlay
    debug = img.crop((L + x0, y0, L + x1 + 1, y1 + 1)).copy()
    # Actually let's just paste a copy of the cropped+board-bounded image
    debug = Image.fromarray(arr[y0:y1+1, x0:x1+1, :]).copy()
    debug = debug.resize((debug.width * 2, debug.height * 2), Image.LANCZOS)
    draw = ImageDraw.Draw(debug, 'RGBA')
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 12)
    except Exception:
        font = ImageFont.load_default()
    for i, p in enumerate(pieces):
        ppx = px_per_in_w * 2  # debug is 2x scale
        ppy = px_per_in_h * 2
        x_l = (p['cx_in'] - p['w_in']/2) * ppx
        y_l = (p['cy_in'] - p['h_in']/2) * ppy
        x_r = (p['cx_in'] + p['w_in']/2) * ppx
        y_r = (p['cy_in'] + p['h_in']/2) * ppy
        color = (255, 200, 0, 200) if p['kind'] == 'tall' else (0, 200, 255, 200)
        draw.rectangle([(x_l, y_l), (x_r, y_r)], outline=color, width=2)
        label = f"{i}: {p['kind'][0]} {p['w_in']:.1f}x{p['h_in']:.1f}"
        draw.text(((x_l + x_r) / 2, (y_l + y_r) / 2), label,
                  fill=(255, 255, 255), font=font, anchor='mm')
    debug.save(args.out)
    print(f"\nDebug overlay: {args.out}")

    if args.json_out:
        with open(args.json_out, 'w') as f:
            json.dump(pieces, f, indent=2)
        print(f"\nClean JSON of {len(pieces)} blobs: {args.json_out}")


if __name__ == '__main__':
    main()
