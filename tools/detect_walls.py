#!/usr/bin/env python3
"""Detect walls within tall terrain pieces. Walls are solid dark-gray
regions (distinct from the hatched body's mid-gray) and are always
aligned with one of the piece's edges.

Strategy:
  1. Build a wall mask: pixels with RGB roughly 50-90 (solid dark).
  2. Erode to remove thin border-edge anti-aliasing pixels (1-2 px).
  3. Find connected components and their min-area-rects.
  4. For each component, find which tall piece it belongs to (the piece
     whose bbox contains the component's centroid).
  5. Express the component's geometry in piece-local coords. The wall's
     long axis should be aligned with the piece (rotation ~ piece's
     rotation) or perpendicular to it.
  6. Snap the wall to the nearest piece edge.
"""

import json
import math
import sys
from collections import deque

from PIL import Image


TALL_PIECES_H = [
    ("tall_01", 26.85,  6.2,   6.3,    4.7,   0.0),
    ("tall_02", 33.15, 37.8,   6.3,    4.7,   0.0),
    ("tall_03",  7.95,  7.95,  8.35,   5.7,  90.0),
    ("tall_04", 52.05, 36.05,  8.35,   5.7,  90.0),
    ("tall_05", 49.05,  9.85, 12.55,   6.35, 90.0),
    ("tall_06", 10.95, 34.15, 12.55,   6.35, 90.0),
    ("tall_07", 19.45, 21.75, 12.5,    6.5,  42.0),
    ("tall_08", 40.55, 22.25, 12.5,    6.5,  42.0),
]


def is_wall_pixel(rgb):
    r, g, b = rgb[:3]
    return (50 <= r <= 90 and 50 <= g <= 90 and 50 <= b <= 90
            and abs(r - g) < 15 and abs(g - b) < 15 and abs(r - b) < 15)


def erode(mask, W, H, k=1):
    out = mask
    for _ in range(k):
        new = [[False] * W for _ in range(H)]
        for y in range(1, H - 1):
            row = out[y]; rowu = out[y-1]; rowd = out[y+1]
            for x in range(1, W - 1):
                if row[x] and rowu[x] and rowd[x] and row[x-1] and row[x+1]:
                    new[y][x] = True
        out = new
    return out


def flood(mask, x0, y0, W, H):
    q = deque([(x0, y0)])
    pts = []
    while q:
        x, y = q.popleft()
        if x < 0 or x >= W or y < 0 or y >= H or not mask[y][x]:
            continue
        mask[y][x] = False
        pts.append((x, y))
        q.append((x+1, y)); q.append((x-1, y))
        q.append((x, y+1)); q.append((x, y-1))
    return pts


def main():
    img_path = sys.argv[1] if len(sys.argv) > 1 else \
        "40k/terrain_layouts/source/layout2_reference.jpg"
    json_path = sys.argv[2] if len(sys.argv) > 2 else \
        "40k/terrain_layouts/layout_parse_test.json"

    img = Image.open(img_path).convert("RGB")
    W0 = img.size[0]
    L = int(W0 * 0.06)
    img = img.crop((L, 0, W0, img.size[1]))
    W, H = img.size
    px_per_in = (W / 60.0 + H / 44.0) / 2
    px = img.load()
    print(f"Cropped {W}x{H}, {px_per_in:.2f} px/in")

    # Build wall pixel mask (solid dark gray)
    mask = [[is_wall_pixel(px[x, y]) for x in range(W)] for y in range(H)]

    # Erode to remove thin (1-2 px) border anti-aliasing strips.
    # Walls are thicker (~3+ px at 13 px/in -> wall thickness >= 0.25").
    mask_e = erode(mask, W, H, k=2)

    # Find connected components
    components = []
    for y in range(H):
        for x in range(W):
            if mask_e[y][x]:
                pts = flood(mask_e, x, y, W, H)
                if len(pts) >= 15:  # minimum area
                    components.append(pts)
    print(f"Found {len(components)} wall-candidate components after erosion")

    # Helper: given a piece, transform world (px) to piece-local (inches)
    def to_local(piece, wx, wy):
        cx_h, cy_h, w_long, h_short, ang_h = piece[1:]
        cx_px = cx_h * px_per_in
        cy_px = cy_h * px_per_in
        rad = math.radians(ang_h)
        ca, sa = math.cos(rad), math.sin(rad)
        dx = wx - cx_px; dy = wy - cy_px
        lx_px =  ca * dx + sa * dy
        ly_px = -sa * dx + ca * dy
        return lx_px / px_per_in, ly_px / px_per_in

    def piece_contains(piece, wx, wy):
        lx, ly = to_local(piece, wx, wy)
        _, _, _, w_long, h_short, _ = piece
        return abs(lx) <= w_long/2 + 0.3 and abs(ly) <= h_short/2 + 0.3

    walls_per_piece = {pid: [] for pid, *_ in TALL_PIECES_H}

    for comp in components:
        xs = [p[0] for p in comp]
        ys = [p[1] for p in comp]
        ccx = sum(xs) / len(xs)
        ccy = sum(ys) / len(ys)

        # Find owning piece (centroid inside piece bbox)
        owner = None
        for piece in TALL_PIECES_H:
            if piece_contains(piece, ccx, ccy):
                owner = piece
                break
        if owner is None:
            continue

        # Express component in piece-local coords; find extents
        local_pts = [to_local(owner, x, y) for x, y in comp]
        lxs = [p[0] for p in local_pts]
        lys = [p[1] for p in local_pts]
        lx_lo, lx_hi = min(lxs), max(lxs)
        ly_lo, ly_hi = min(lys), max(lys)
        l_len_x = lx_hi - lx_lo
        l_len_y = ly_hi - ly_lo

        pid = owner[0]
        w_long = owner[3]
        h_short = owner[4]
        hw = w_long / 2
        hh = h_short / 2

        # Determine wall orientation: long along x (horizontal in local)
        # vs long along y. Also: which edge it sits against.
        if l_len_x >= l_len_y:
            # long along x -> wall on north or south edge
            # find which is closer
            ly_mid = (ly_lo + ly_hi) / 2
            if abs(ly_mid - (-hh)) < abs(ly_mid - hh):
                edge = "north"; y_at = -hh
            else:
                edge = "south"; y_at = hh
            # Sanity: wall pixels should be near that edge
            if abs(ly_mid - y_at) > h_short * 0.5:
                continue
            if l_len_x < 1.5:  # too short to be a meaningful wall
                continue
            walls_per_piece[pid].append({
                "id": f"wall_{edge}",
                "local_start": [round(lx_lo, 2), round(y_at, 2)],
                "local_end":   [round(lx_hi, 2), round(y_at, 2)],
                "type": "solid",
                "blocks_los": True,
                "_pixels": len(comp),
                "_thickness_in": round(l_len_y, 2),
            })
        else:
            # long along y -> wall on west or east edge
            lx_mid = (lx_lo + lx_hi) / 2
            if abs(lx_mid - (-hw)) < abs(lx_mid - hw):
                edge = "west"; x_at = -hw
            else:
                edge = "east"; x_at = hw
            if abs(lx_mid - x_at) > w_long * 0.5:
                continue
            if l_len_y < 1.5:
                continue
            walls_per_piece[pid].append({
                "id": f"wall_{edge}",
                "local_start": [round(x_at, 2), round(ly_lo, 2)],
                "local_end":   [round(x_at, 2), round(ly_hi, 2)],
                "type": "solid",
                "blocks_los": True,
                "_pixels": len(comp),
                "_thickness_in": round(l_len_x, 2),
            })

    print("\nDetected walls per piece:")
    for pid, walls in walls_per_piece.items():
        if not walls:
            print(f"  {pid}: (none)")
        for w in walls:
            s = w["local_start"]; e = w["local_end"]
            L_in = math.hypot(e[0]-s[0], e[1]-s[1])
            print(f"  {pid}: {w['id']:11s} "
                  f"({s[0]:+5.2f},{s[1]:+5.2f}) -> ({e[0]:+5.2f},{e[1]:+5.2f})  "
                  f"len={L_in:.2f}\"  thick={w['_thickness_in']:.2f}\"  "
                  f"px={w['_pixels']}")

    # Apply symmetry: for each pair (A, B) of 180-symmetric pieces, the wall
    # geometry should be the same in piece-local frame (because local frames
    # rotate with the piece, and 180 rotation maps the piece onto itself).
    # Walls should be 180-rotated in local coords for the mirror piece. We
    # enforce this by intersecting detected walls between paired pieces.
    pairs = [("tall_01", "tall_02"), ("tall_03", "tall_04"),
             ("tall_05", "tall_06"), ("tall_07", "tall_08")]

    def symmetrize(a_walls, b_walls):
        """Keep only walls that appear in both pieces, after mapping each
        b-wall through 180 rotation in the local frame: (x,y) -> (-x,-y).
        Returns (a_kept, b_kept) where b's walls are the 180-rotated
        version of a's (so they look correct on the mirror piece)."""
        def edge_of(w):
            return w["id"].replace("wall_", "")
        # Map a's walls to which edges they're on
        a_edges = {edge_of(w): w for w in a_walls}
        b_edges = {edge_of(w): w for w in b_walls}
        # 180-rotated mapping: north <-> south, east <-> west
        rot180 = {"north": "south", "south": "north",
                  "east": "west", "west": "east"}
        keep = []
        a_keep = []
        b_keep = []
        for edge_a, wa in a_edges.items():
            edge_b_needed = rot180[edge_a]
            if edge_b_needed in b_edges:
                a_keep.append(wa)
                # Construct b's wall by 180-rotating a's wall in local frame
                s = wa["local_start"]; e = wa["local_end"]
                b_w = {
                    "id": f"wall_{edge_b_needed}",
                    "local_start": [-s[0], -s[1]],
                    "local_end":   [-e[0], -e[1]],
                    "type": "solid",
                    "blocks_los": True,
                }
                b_keep.append(b_w)
        return a_keep, b_keep

    for a_id, b_id in pairs:
        a_k, b_k = symmetrize(walls_per_piece[a_id], walls_per_piece[b_id])
        walls_per_piece[a_id] = a_k
        walls_per_piece[b_id] = b_k

    print("\nAfter symmetry pruning:")
    for pid, walls in walls_per_piece.items():
        if not walls:
            print(f"  {pid}: (none)")
        for w in walls:
            s = w["local_start"]; e = w["local_end"]
            print(f"  {pid}: {w['id']:11s} "
                  f"({s[0]:+5.2f},{s[1]:+5.2f}) -> ({e[0]:+5.2f},{e[1]:+5.2f})")

    # Write into JSON, stripping debug fields
    with open(json_path) as f:
        data = json.load(f)
    for piece in data["pieces"]:
        pid = piece["id"]
        if pid in walls_per_piece:
            cleaned = []
            for w in walls_per_piece[pid]:
                cleaned.append({k: v for k, v in w.items() if not k.startswith("_")})
            piece["walls"] = cleaned
    with open(json_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"\nWrote walls into {json_path}")


if __name__ == "__main__":
    main()
