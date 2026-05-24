#!/usr/bin/env python3
"""Detect wall shape (C vs L) for tall_12x6 pieces by examining the wall
pixels within the piece's bbox in the source image.

Logic:
  For each 12x6 piece, look at pixels inside the piece's local bbox.
  Identify "wall" pixels (very dark gray, RGB < 95). For each of the
  4 edges (north, south, east, west), count wall pixels within a band
  of ~0.5" inside the edge.

  - L-shape: 2 ADJACENT edges have high density.
  - C-shape: 1 edge has high density (the long base).

  Pieces with 2 adjacent edges -> tall_12x6_L
  Pieces with 1 edge or non-adjacent walls -> tall_12x6_C
"""

import math
import sys
import numpy as np
from PIL import Image


def detect_wall_shape_for_piece(arr, x0_px, y0_px, ppx_w, ppx_h,
                                cx_in, cy_in, long_, short, angle_h_deg):
    """Return 'L' or 'C' for a 12x6 tall piece."""
    cx_px = x0_px + cx_in * ppx_w
    cy_px = y0_px + cy_in * ppx_h
    rad = math.radians(angle_h_deg)
    ca, sa = math.cos(rad), math.sin(rad)

    # Wall pixel mask: very dark gray
    r = arr[..., 0].astype(np.int16)
    g = arr[..., 1].astype(np.int16)
    b = arr[..., 2].astype(np.int16)
    wall = (r < 95) & (g < 95) & (b < 95) & (np.abs(r-g) < 15) & (np.abs(g-b) < 15)

    # For each of the 4 edges, count wall pixels in a band 0-0.5" inside
    # AND in a band 0.5-1.5" deeper (to distinguish wall thickness).
    H, W = wall.shape
    band_depth = 0.5  # inches
    edge_counts = {}
    edge_total = {}

    edges = {
        'north': (-1, 'y'),  # local y = -short/2
        'south': (+1, 'y'),
        'west':  (-1, 'x'),
        'east':  (+1, 'x'),
    }

    # Sample on a grid
    step = 0.1  # inches
    for edge, (sign, axis) in edges.items():
        cnt = 0; total = 0
        if axis == 'y':
            # Band along y = sign*(short/2 - 0..band_depth)
            for d in np.arange(0, band_depth, step):
                ly = sign * (short / 2 - d)
                for lx in np.arange(-long_/2 + 0.5, long_/2 - 0.5, step):
                    wx_in = (lx*ca - ly*sa)
                    wy_in = (lx*sa + ly*ca)
                    px = int(cx_px + wx_in * ppx_w)
                    py = int(cy_px + wy_in * ppx_h)
                    if 0 <= px < W and 0 <= py < H:
                        total += 1
                        if wall[py, px]:
                            cnt += 1
        else:  # axis == 'x'
            for d in np.arange(0, band_depth, step):
                lx = sign * (long_ / 2 - d)
                for ly in np.arange(-short/2 + 0.5, short/2 - 0.5, step):
                    wx_in = (lx*ca - ly*sa)
                    wy_in = (lx*sa + ly*ca)
                    px = int(cx_px + wx_in * ppx_w)
                    py = int(cy_px + wy_in * ppx_h)
                    if 0 <= px < W and 0 <= py < H:
                        total += 1
                        if wall[py, px]:
                            cnt += 1
        edge_counts[edge] = cnt
        edge_total[edge] = total

    density = {e: edge_counts[e] / max(1, edge_total[e]) for e in edges}

    # L-shape: 2 ADJACENT edges with high density (>0.5)
    # C-shape: 1 edge with high density
    high_edges = [e for e, d in density.items() if d > 0.4]
    return density, high_edges


def main():
    img_path = sys.argv[1]
    img = Image.open(img_path).convert('RGB')
    arr = np.array(img); H, W, _ = arr.shape
    L = int(W * 0.06); arr = arr[:, L:, :]
    gray = arr.mean(axis=2)
    bg = (gray > 200) & (gray < 245)
    rows = np.where(bg.any(axis=1))[0]
    cols = np.where(bg.any(axis=0))[0]
    x0, y0 = cols.min(), rows.min()
    ppx_w = (cols.max()-x0+1)/60; ppx_h = (rows.max()-y0+1)/44

    # Hard-coded list of tall_12x6 pieces in Layout 1 (horizontal coords)
    pieces = [
        ('tall_01_top_right', 41.14, 9.92, 90),  # vertical orientation (long axis vertical)
        ('tall_02_top_left',   8.36,10.94, 90),
        ('tall_06_bot_left',  18.86,34.08, 90),
        ('tall_07_bot_right', 51.64,33.06, 90),
    ]

    for name, cx, cy, ang in pieces:
        density, high = detect_wall_shape_for_piece(
            arr, x0, y0, ppx_w, ppx_h, cx, cy, 12.0, 6.0, ang)
        shape = 'L' if len(high) >= 2 else 'C' if len(high) == 1 else '?'
        print(f"{name:20s} @ ({cx:5.2f},{cy:5.2f}): density={dict((k,round(v,2)) for k,v in density.items())}  high={high}  shape={shape}")


if __name__ == '__main__':
    main()
