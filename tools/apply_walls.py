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
    # tall_01 (top-mid small, rot_h=0): C-shape opening east (right in world).
    # Long base on local west (= world LEFT) PLUS two perpendicular arms
    # extending from the west corners eastward along the north and south
    # edges. Arms are at the corners (no inset for this piece).
    "tall_01": [
        ("west", ["full"]),
        ("arm_north_from_west", []),
        ("arm_south_from_west", []),
    ],
    # tall_03 (top-left vertical L, rot_h=-90): L on world top-right corner.
    "tall_03": [
        ("south", ["full"]),
        ("east_from_south", []),
    ],
    # tall_05 (top-right big L, rot_h=-90): L on world top-left corner.
    "tall_05": [
        ("north", ["full"]),
        ("east_from_north", []),
    ],
    # tall_07 (left diagonal, rot_h=42): C-shape opening south.
    # Long base on north edge but ONLY between the arms (per user feedback:
    # "the walls do not continue to the corners on the long edge, they stop
    # where they turn"). Arms are 1.5" inset from each end and extend 3"
    # toward the opposite edge.
    "tall_07": [
        ("north_between_arms", []),
        ("arm_west", []),
        ("arm_east", []),
    ],
}

ARM_INSET_FROM_END = 1.5
ARM_LENGTH = 3.0
L_CORNER_ARM_LENGTH = 3.0
C_ORTHO_ARM_LENGTH = 4.5  # arm length for the C-shape on small ortho pieces


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
    # U-shape arms for the diagonals: perpendicular walls extending from
    # the long edge toward the opposite side, located 1.5" from each end.
    if edge == "arm_west":
        x = -hw + ARM_INSET_FROM_END
        return {"id": "wall_arm_west",
                "local_start": [x, -hh],
                "local_end":   [x, -hh + ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    if edge == "arm_east":
        x = hw - ARM_INSET_FROM_END
        return {"id": "wall_arm_east",
                "local_start": [x, -hh],
                "local_end":   [x, -hh + ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    # L-shape perpendicular walls for orthogonal pieces.
    # The "east_from_south" wall sits on the local east edge (x=+hw) starting
    # at the south corner (y=+hh) and extending toward north for
    # L_CORNER_ARM_LENGTH inches. Used by pieces whose L corner is at the
    # local east-south corner of the piece-local frame.
    if edge == "east_from_south":
        return {"id": "wall_east_partial",
                "local_start": [hw, hh],
                "local_end":   [hw, hh - L_CORNER_ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    if edge == "east_from_north":
        return {"id": "wall_east_partial",
                "local_start": [hw, -hh],
                "local_end":   [hw, -hh + L_CORNER_ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    # C-shape base wall on the diagonals: runs along the north edge but
    # only between the two arm positions (no extension to the corners).
    if edge == "north_between_arms":
        return {"id": "wall_north",
                "local_start": [-hw + ARM_INSET_FROM_END, -hh],
                "local_end":   [ hw - ARM_INSET_FROM_END, -hh],
                "type": "solid", "blocks_los": True}
    if edge == "south_between_arms":
        return {"id": "wall_south",
                "local_start": [-hw + ARM_INSET_FROM_END, hh],
                "local_end":   [ hw - ARM_INSET_FROM_END, hh],
                "type": "solid", "blocks_los": True}
    # C-shape arms on orthogonal pieces (e.g., tall_01): arms start AT
    # the west corners and extend east along the north/south edges.
    if edge == "arm_north_from_west":
        return {"id": "wall_arm_north",
                "local_start": [-hw, -hh],
                "local_end":   [-hw + C_ORTHO_ARM_LENGTH, -hh],
                "type": "solid", "blocks_los": True}
    if edge == "arm_south_from_west":
        return {"id": "wall_arm_south",
                "local_start": [-hw, hh],
                "local_end":   [-hw + C_ORTHO_ARM_LENGTH, hh],
                "type": "solid", "blocks_los": True}
    raise ValueError(edge)


# 180-rotated edge mapping: a wall on local "north" of piece A becomes
# a wall on local "south" of piece B (the 180-mirror).
ROT180 = {"north": "south", "south": "north", "west": "east", "east": "west",
          "arm_west": "arm_east_south", "arm_east": "arm_west_south",
          "east_from_south": "west_from_north",
          "east_from_north": "west_from_south",
          "north_between_arms": "south_between_arms",
          "arm_north_from_west": "arm_south_from_east",
          "arm_south_from_west": "arm_north_from_east"}


def make_wall_mirror(edge, w_long, h_short):
    """Build the wall that's the 180-rotated counterpart in local coords.
    180 rotation in local frame maps (x, y) -> (-x, -y)."""
    hw = w_long / 2
    hh = h_short / 2
    if edge == "arm_east_south":
        x = hw - ARM_INSET_FROM_END
        return {"id": "wall_arm_east",
                "local_start": [x, hh],
                "local_end":   [x, hh - ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    if edge == "arm_west_south":
        x = -hw + ARM_INSET_FROM_END
        return {"id": "wall_arm_west",
                "local_start": [x, hh],
                "local_end":   [x, hh - ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    # L-shape partial-arm mirrors: 180-rotate the corresponding wall.
    # east_from_south (start at +hw,+hh, end at +hw, +hh - len) ->
    # mirror (start at -hw,-hh, end at -hw, -hh + len)
    if edge == "west_from_north":
        return {"id": "wall_west_partial",
                "local_start": [-hw, -hh],
                "local_end":   [-hw, -hh + L_CORNER_ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    if edge == "west_from_south":
        return {"id": "wall_west_partial",
                "local_start": [-hw, hh],
                "local_end":   [-hw, hh - L_CORNER_ARM_LENGTH],
                "type": "solid", "blocks_los": True}
    # 180-rotated mirror of arm_north_from_west (which was at
    # (-hw,-hh) -> (-hw+L, -hh)) -> (hw, hh) -> (hw-L, hh) which sits on
    # south edge, starting at east corner, extending west.
    if edge == "arm_south_from_east":
        return {"id": "wall_arm_south",
                "local_start": [hw, hh],
                "local_end":   [hw - C_ORTHO_ARM_LENGTH, hh],
                "type": "solid", "blocks_los": True}
    if edge == "arm_north_from_east":
        return {"id": "wall_arm_north",
                "local_start": [hw, -hh],
                "local_end":   [hw - C_ORTHO_ARM_LENGTH, -hh],
                "type": "solid", "blocks_los": True}
    return make_wall(edge, w_long, h_short)

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
        mir_walls.append(make_wall_mirror(ROT180[edge], w_long, h_short))
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
