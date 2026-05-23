#!/usr/bin/env python3
"""Take detected pieces (from detect_pieces.py) and emit a symmetric layout
JSON in vertical-board coordinates.

Pairs each piece with its 180-degree-rotated counterpart around the
horizontal board center (30, 22), averages positions/sizes to force exact
symmetry, then converts the horizontal coords to vertical board coords
(90 deg CCW image rotation):
    x_v = y_h
    y_v = 60 - x_h
    rotation_v = rotation_h + 90  (mod 180 for rectangles)
"""

import json
import sys
from collections import defaultdict


# 16 pieces detected in horizontal source image (60x44 in).
# Each entry: (kind, cx, cy, w_long, h_short, angle_h_deg)
DETECTED = [
    ("tall", 26.5,  6.3,  6.3,  4.6,   0.0),
    ("low",  21.2,  6.6,  4.6,  3.3,  90.0),
    ("tall",  7.0,  8.0,  8.5,  5.7,  90.0),
    ("tall", 48.4,  9.9, 12.4,  6.4,  90.0),
    ("low",  32.3, 11.2,  5.5,  3.6,   0.0),
    ("low",   7.3, 14.0,  5.7,  3.9,   0.0),
    ("low",  54.4, 18.0,  5.7,  3.6,   0.0),
    ("tall", 18.8, 21.9, 12.5,  6.5,  42.1),
    ("tall", 39.9, 22.4, 12.5,  6.5,  42.0),
    ("low",   4.2, 26.1,  5.5,  3.6,   0.0),
    ("low",  51.4, 30.2,  5.7,  3.9,   0.0),
    ("low",  26.4, 33.2,  5.7,  3.6,   0.0),
    ("tall", 10.3, 34.2, 12.7,  6.3,  90.0),
    ("tall", 51.8, 36.1,  8.2,  5.8,  90.0),
    ("low",  37.6, 37.6,  4.6,  3.3,  90.0),
    ("tall", 32.2, 37.9,  6.3,  4.8,   0.0),
]


def pair_pieces(pieces):
    """Return list of (A, B) pairs where B is the 180-degree-symmetric
    counterpart of A around (30, 22). Each piece appears in exactly one pair
    (a piece on the centerline pairs with itself)."""
    used = [False] * len(pieces)
    pairs = []
    for i, a in enumerate(pieces):
        if used[i]:
            continue
        best_j = -1
        best_d = 1e9
        ax, ay = a[1], a[2]
        mx, my = 60 - ax, 44 - ay  # expected location of mirror
        for j, b in enumerate(pieces):
            if used[j] or j == i:
                continue
            if b[0] != a[0]:  # must be same kind
                continue
            bx, by = b[1], b[2]
            d = (bx - mx) ** 2 + (by - my) ** 2
            if d < best_d:
                best_d = d
                best_j = j
        if best_j == -1 or best_d > 9:  # > 3 inches off -> probably self-paired
            pairs.append((a, None))
            used[i] = True
        else:
            pairs.append((a, pieces[best_j]))
            used[i] = True
            used[best_j] = True
    return pairs


def average_pair(a, b):
    """Average a piece with the mirror of its partner to force symmetry.
    Returns the canonical (top-half) piece's averaged values."""
    if b is None:
        return a
    # Mirror b to a's side, then average
    kind, ax, ay, aw, ah, aang = a
    _, bx, by, bw, bh, bang = b
    mx, my = 60 - bx, 44 - by
    # angle: rectangles are 180-invariant, so map angles into [0, 180) and
    # average robustly using sin/cos
    import math
    a_rad = math.radians(aang * 2)
    b_rad = math.radians(bang * 2)
    avg_rad = math.atan2(
        (math.sin(a_rad) + math.sin(b_rad)) / 2,
        (math.cos(a_rad) + math.cos(b_rad)) / 2,
    )
    avg_ang = math.degrees(avg_rad) / 2
    avg_ang = avg_ang % 180
    return (kind,
            round((ax + mx) / 2, 2),
            round((ay + my) / 2, 2),
            round((aw + bw) / 2, 2),
            round((ah + bh) / 2, 2),
            round(avg_ang, 1))


def to_vertical(piece):
    """Convert (kind, cx_h, cy_h, w, h, angle_h) to vertical board piece JSON."""
    kind, cx_h, cy_h, w, h, ang_h = piece
    x_v = round(cy_h, 2)
    y_v = round(60 - cx_h, 2)
    # rotation: image rotated 90 CCW, so piece rotation += 90
    ang_v = (ang_h + 90.0) % 180.0
    return {
        "kind": kind,
        "x_v": x_v,
        "y_v": y_v,
        "w": w,
        "h": h,
        "rot": round(ang_v, 1),
    }


def make_json(pieces_top, pieces_bottom_originals):
    """Build the final layout JSON. pieces_top is the symmetrized 'top half'
    pieces (in horizontal coords); pieces_bottom_originals is the raw
    bottom-half detections (so we can name them but use the symmetric pos)."""
    out = {
        "id": "layout_parse_test",
        "name": "Parse Test (Layout 2 image-detected)",
        "description": "Generated from layout2_reference.jpg via tools/detect_pieces.py + tools/detect_to_json.py. Pieces detected by color segmentation, paired with their 180-degree mirror counterparts, then positions/sizes averaged to force exact rotational symmetry around (22, 30). 16 pieces total: 8 gray hatched (tall ruins) and 8 blue (low ruins).",
        "recommended_deployments": ["hammer_anvil", "dawn_of_war", "crucible_of_battle"],
        "pieces": [],
    }

    counters = defaultdict(int)

    def add(piece_h):
        v = to_vertical(piece_h)
        kind = v["kind"]
        counters[kind] += 1
        idx = counters[kind]
        height = "tall" if kind == "tall" else "low"
        piece = {
            "id": f"{kind}_{idx:02d}",
            "type": "ruins",
            "position": [v["x_v"], v["y_v"]],
            "size": [v["w"], v["h"]],
            "height": height,
            "rotation": v["rot"],
            "walls": [],
        }
        if height == "tall":
            piece["traits"] = ["obscuring"]
        out["pieces"].append(piece)

    for ph in pieces_top:
        add(ph)
        kind, cx, cy, w, h, ang = ph
        mirror = (kind, 60 - cx, 44 - cy, w, h, ang)
        add(mirror)

    return out


def main():
    pairs = pair_pieces(DETECTED)
    print(f"Built {len(pairs)} pairs (expecting 8 for 16 pieces):")
    canonical_top = []
    for a, b in pairs:
        avg = average_pair(a, b)
        # Take the one with smaller y_h as "top"
        if b is not None:
            ay = avg[2]
            by = 44 - avg[2]
            top = avg if ay <= by else (
                avg[0], 60 - avg[1], 44 - avg[2], avg[3], avg[4], avg[5]
            )
        else:
            top = avg
        canonical_top.append(top)
        print(f"  {top[0]:5s} h=({top[1]:5.2f},{top[2]:5.2f}) "
              f"size={top[3]:5.2f}x{top[4]:4.2f} ang={top[5]:.1f}")

    data = make_json(canonical_top, None)

    out_path = sys.argv[1] if len(sys.argv) > 1 else \
        "40k/terrain_layouts/layout_parse_test.json"
    with open(out_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"\nWrote {out_path}  ({len(data['pieces'])} pieces)")


if __name__ == "__main__":
    main()
