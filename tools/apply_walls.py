#!/usr/bin/env python3
"""Set walls on tall pieces in layout_parse_test.json based on the source
image. For each top-half tall piece I encode the wall edge(s) by looking
at layout2_reference.jpg, then mirror to the bottom half via 180-degree
rotation in piece-local coords.

Wall coordinates are LOCAL to the piece (in inches), with:
  +x_local = the piece's long axis (size[0] direction before rotation)
  +y_local = the piece's short axis (size[1] direction)
So local +x maps to whatever world direction the piece's rotation says.
For piece rotation in HORIZONTAL coords:
    rot_h = 0   -> +x_local points world +x (right)
    rot_h = 90  -> +x_local points world +y (down)
    rot_h = 42  -> upper-right diagonal
"""

import json
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else \
    "40k/terrain_layouts/layout_parse_test.json"

# Wall edges per top-half piece, in piece-LOCAL frame.
# Each piece has half-widths derived from its size [w_long, h_short]:
#   hw = w_long/2, hh = h_short/2
# Edge "north" = ly = -hh, "south" = +hh, "west" = lx = -hw, "east" = +hw.
#
# In HORIZONTAL world view (the source image), with rot_h applied to the
# piece's local axes, the world-direction of each local edge is:
#   For rot_h = 0:   local east -> world right, north -> world up
#   For rot_h = 90:  local east -> world down,  north -> world right
#   For rot_h = 42:  local east -> world upper-right, north -> upper-left
#
# Source image observations (top-half pieces only; bottom = 180-rotated):
#
# tall_01  (top-mid small, rot_h=0): wall on the LEFT side in world view.
#   World left = -x world = local west.
#   So local west.
#
# tall_03  (top-left vertical L, rot_h=90): wall on the LEFT in world.
#   World -x = local +y (south) because rot 90: local +x = world +y, so
#   local +y = world -x. So world left = local south.
#
# tall_05  (top-right big L, rot_h=90): walls on world LEFT AND TOP.
#   World left = local south. World top = world -y = local west.
#   Two walls: local south + local west.
#
# tall_07  (center-left diagonal, rot_h=42): in the source image the
#   wall is on the UPPER edge of the diagonal. The piece's long axis
#   points lower-right (rot_h=42, +x_local = (cos42, sin42) ~ upper-
#   right-down direction). The "upper" edge of the diagonal in world
#   view is the local north edge (since rotating local +y direction by
#   42 deg gives world (-sin42, cos42) = upper-left-down, but that's
#   not "north" in world terms... hmm).
#   Easier mental model: the diagonal's long axis goes from lower-left
#   to upper-right (since the piece tilts \ in image but is detected
#   at angle 42 which means long axis is rotated 42 CCW from +x in
#   image coords; with image y-down, that's 42 below horizontal
#   pointing right-down -> long axis from upper-left to lower-right).
#   The wall is on the upper-right side of this axis = local north.

WALLS_TOP_HALF = {
    "tall_01": [("west",  ["full"])],
    "tall_03": [("south", ["full"])],
    "tall_05": [("south", ["full"]), ("west", ["full"])],
    "tall_07": [("north", ["full"])],
}


def make_wall(edge, w_long, h_short):
    hw = w_long / 2
    hh = h_short / 2
    if edge == "north":
        return {"id": "wall_north",
                "local_start": [-hw, -hh],
                "local_end":   [hw,  -hh],
                "type": "solid", "blocks_los": True}
    if edge == "south":
        return {"id": "wall_south",
                "local_start": [-hw, hh],
                "local_end":   [hw,  hh],
                "type": "solid", "blocks_los": True}
    if edge == "west":
        return {"id": "wall_west",
                "local_start": [-hw, -hh],
                "local_end":   [-hw,  hh],
                "type": "solid", "blocks_los": True}
    if edge == "east":
        return {"id": "wall_east",
                "local_start": [hw, -hh],
                "local_end":   [hw,  hh],
                "type": "solid", "blocks_los": True}
    raise ValueError(edge)


# 180-rotated edge mapping: a wall on local "north" of piece A becomes
# a wall on local "south" of piece B (the 180-mirror).
ROT180 = {"north": "south", "south": "north", "west": "east", "east": "west"}

PAIRS = {
    "tall_01": "tall_02",
    "tall_03": "tall_04",
    "tall_05": "tall_06",
    "tall_07": "tall_08",
}


with open(PATH) as f:
    data = json.load(f)
pieces = {p["id"]: p for p in data["pieces"]}


for top_id, mirror_id in PAIRS.items():
    p_top = pieces[top_id]
    p_mir = pieces[mirror_id]
    size = p_top["size"]
    w_long, h_short = size[0], size[1]
    top_walls = []
    mir_walls = []
    for edge, _spec in WALLS_TOP_HALF.get(top_id, []):
        top_walls.append(make_wall(edge, w_long, h_short))
        mir_walls.append(make_wall(ROT180[edge], w_long, h_short))
    p_top["walls"] = top_walls
    p_mir["walls"] = mir_walls

# Verify symmetry: for each pair, mirror's walls should be 180-rotated.
print("Walls assigned:")
for top_id, mirror_id in PAIRS.items():
    a = pieces[top_id]["walls"]
    b = pieces[mirror_id]["walls"]
    print(f"  {top_id} ({len(a)} walls), {mirror_id} ({len(b)} walls)")
    for w in a:
        print(f"    {top_id}: {w['id']}  {w['local_start']} -> {w['local_end']}")
    for w in b:
        print(f"    {mirror_id}: {w['id']}  {w['local_start']} -> {w['local_end']}")


with open(PATH, "w") as f:
    json.dump(data, f, indent=2)
print(f"\nWrote {PATH}")
