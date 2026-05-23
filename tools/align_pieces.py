#!/usr/bin/env python3
"""Apply targeted alignment fixes to layout_parse_test.json.

Edits each named piece in horizontal coords, then mirrors the change to the
180-degree counterpart to keep symmetry. Position/size conversions:
  vertical (x_v, y_v) <-> horizontal (60 - y_v, x_v)
  with rotation_v = rotation_h + 90 (mod 180 since rectangles are symmetric).
"""

import json
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else \
    "40k/terrain_layouts/layout_parse_test.json"

with open(PATH) as f:
    data = json.load(f)
pieces = {p["id"]: p for p in data["pieces"]}


def update(pid, **changes):
    p = pieces[pid]
    if "position" in changes:
        p["position"] = list(changes["position"])
    if "size" in changes:
        p["size"] = list(changes["size"])


# === Top-left (tall_03) and bottom-right (tall_04): width 5.7 (was 5.75)
# Center horizontally on x_h = 7.95 (matching low_05 / low_06).
# In JSON: rotation 0 means horizontal width = size[1]. Set size[1] = 5.7.
# Position: h_x = 60 - y_v -> y_v = 60 - 7.95 = 52.05 (and mirror 7.95).
update("tall_03", position=[7.95, 52.05], size=[8.35, 5.7])
update("tall_04", position=[44 - 7.95, 60 - 52.05], size=[8.35, 5.7])

# === Top-mid (tall_01) - right edge on centerline x_h = 30.
# Keep size [6.3, 4.7] rotation 90 (so h_width = 6.3, h_height = 4.7).
# center_x_h = 30 - 6.3/2 = 26.85 -> y_v = 60 - 26.85 = 33.15.
# Keep center_y_h = 6.2 -> x_v = 6.2 (unchanged).
update("tall_01", position=[6.2, 33.15])
update("tall_02", position=[44 - 6.2, 60 - 33.15])  # mirror -> [37.8, 26.85]

# === low_01 (top-mid blue, LEFT of tall_01) - height 4.7 (was 4.6),
# right edge touches tall_01 left edge at x_h = 23.7, same y_center as tall_01.
# In JSON: rotation 0 means h_width = size[1], h_height = size[0].
# Set size[0] = 4.7. Keep size[1] = 3.3 (h_width = 3.3).
# center_x_h = 23.7 - 3.3/2 = 22.05 -> y_v = 60 - 22.05 = 37.95.
# center_y_h = 6.2 -> x_v = 6.2.
update("low_01", position=[6.2, 37.95], size=[4.7, 3.3])
update("low_02", position=[44 - 6.2, 60 - 37.95], size=[4.7, 3.3])

# === low_03 (top-mid-right blue, BELOW-RIGHT of tall_01) - left edge on
# centerline, top edge touches tall_01's bottom at y_h = 8.55.
# Keep size [5.6, 3.6] rotation 90 -> h_width = 5.6, h_height = 3.6.
# tall_01 bottom_y_h = 6.2 + 4.7/2 = 8.55.
# low_03 top_y_h = 8.55 -> center_y_h = 8.55 + 3.6/2 = 10.35 -> x_v = 10.35.
# low_03 left_x_h = 30 -> center_x_h = 30 + 5.6/2 = 32.8 -> y_v = 27.2.
update("low_03", position=[10.35, 27.2])
update("low_04", position=[44 - 10.35, 60 - 27.2])  # -> [33.65, 32.8]


# Sanity: verify symmetry
print("Symmetry check after edits:")
seen = set()
for pid, p in pieces.items():
    if pid in seen:
        continue
    seen.add(pid)
    cx, cy = p["position"]
    mx, my = 44 - cx, 60 - cy
    partner = None
    for qid, q in pieces.items():
        if qid in seen or qid == pid:
            continue
        qx, qy = q["position"]
        if abs(qx - mx) < 0.01 and abs(qy - my) < 0.01:
            partner = qid
            break
    if partner:
        seen.add(partner)
        q = pieces[partner]
        same_size = p["size"] == q["size"]
        same_rot = p["rotation"] == q["rotation"]
        ok = same_size and same_rot
        print(f"  {pid} <-> {partner}: {'OK' if ok else 'MISMATCH'}")
    else:
        print(f"  {pid}: NO MIRROR FOUND at ({mx}, {my})")


with open(PATH, "w") as f:
    json.dump(data, f, indent=2)
print(f"\nWrote {PATH}")
