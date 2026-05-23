#!/usr/bin/env python3
"""Convert match_to_catalog.py output into a layout JSON file with
exact canonical sizes, snapped adjacent pieces, and walls applied
per slot.

Input: a JSON file like:
    {"matches": [...], "pairs": [...]}
where each match has: kind, slot_hint, long, short, angle, cx_in, cy_in.

Output: a terrain_layouts/layout_*.json compatible with TerrainManager.

Steps:
1. For each paired (tall, low) pair, snap the low piece's centre to
   touch the tall piece on the shared edge.
2. Convert horizontal source coords -> vertical board coords.
3. Apply walls per slot:
     tall_12x6_C  -> C-shape walls (long base + 2 arms inset 1.5", arms 3")
     tall_12x6_L  -> L-shape (two perpendicular full-length walls)
     tall_8x6     -> L-shape (two perpendicular full-length walls)
     tall_6.5x5   -> L-shape
     low_*        -> no walls
"""

import argparse
import json
import math


def snap_pair(tall_match, low_match):
    """Move and rotate the low piece so it touches the tall on their
    shared 6"/5" edge.

    Canonical pairings (per tools/catalog.py):
      tall_8x6  + low_4x6  share a 6" edge -> combined 12x6 footprint.
      tall_6.5x5 + low_3.5x5 share a 5" edge -> combined 10x5 footprint.

    Geometry:
      The shared edge length (6" or 5") equals the SHORT dimension of
      the tall AND the LONG dimension of the low. So the low's long axis
      must be PERPENDICULAR to the tall's long axis, and the low sits
      against the tall's east or west face (the face perpendicular to
      the tall's long axis).
    """
    tx, ty = tall_match['cx_in'], tall_match['cy_in']
    lx, ly = low_match['cx_in'], low_match['cy_in']
    dx, dy = lx - tx, ly - ty

    # Project (dx, dy) onto tall's local axes
    rad = math.radians(tall_match['angle'])
    ca, sa = math.cos(rad), math.sin(rad)
    local_dx = ca * dx + sa * dy   # along tall's long axis
    local_dy = -sa * dx + ca * dy  # perpendicular to tall's long axis

    t_long_half = tall_match['long'] / 2   # extent along long axis
    t_short_half = tall_match['short'] / 2  # extent along short axis
    l_long = low_match['long']
    l_short = low_match['short']

    # The low pairs at the tall's east (+local_x) or west (-local_x) face.
    # Its centre is offset by (t_long_half + l_short/2) along that direction
    # (because the low's SHORT dimension extends from the shared edge into
    # the world; its LONG dimension runs PARALLEL to the tall's short axis).
    sign = 1 if local_dx >= 0 else -1
    new_local_x = sign * (t_long_half + l_short / 2)
    new_local_y = 0.0

    # Convert local offset back to world
    new_dx = ca * new_local_x - sa * new_local_y
    new_dy = sa * new_local_x + ca * new_local_y
    low_match['cx_in'] = round(tx + new_dx, 2)
    low_match['cy_in'] = round(ty + new_dy, 2)

    # CRITICAL: low's long axis is perpendicular to tall's long axis.
    # If tall is at angle theta, low is at angle theta + 90 (mod 180 since
    # rectangles are 180-symmetric).
    low_match['angle'] = (tall_match['angle'] + 90.0) % 180.0


def horizontal_to_vertical(cx_h, cy_h, angle_h, board_w=60.0, board_h=44.0):
    """90deg CCW image rotation: (x_h, y_h) -> (y_h, 60 - x_h),
    rotation += 90 (mod 180 for rectangles)."""
    x_v = cy_h
    y_v = board_w - cx_h
    angle_v = (angle_h + 90.0) % 180.0
    return x_v, y_v, angle_v


def make_walls(slot, long_, short):
    """Generate walls for a piece based on its slot. Returns a list of
    wall dicts in piece-local inches."""
    hw = long_ / 2
    hh = short / 2

    if slot == 'tall_12x6_C':
        # C-shape: long base on local north, between two arms inset 1.5"
        # from each end. Arms extend 3" toward south (opposite edge).
        inset = 1.5
        arm_len = 3.0
        return [
            {'id': 'wall_north', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw + inset, -hh],
             'local_end':   [ hw - inset, -hh]},
            {'id': 'wall_arm_west', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw + inset, -hh],
             'local_end':   [-hw + inset, -hh + arm_len]},
            {'id': 'wall_arm_east', 'type': 'solid', 'blocks_los': True,
             'local_start': [ hw - inset, -hh],
             'local_end':   [ hw - inset, -hh + arm_len]},
        ]
    if slot == 'tall_12x6_L' or slot == 'tall_8x6' or slot == 'tall_6.5x5':
        # L-shape: two full-length perpendicular walls meeting at the
        # local north-west corner. (Caller can mirror to bottom-half pieces.)
        return [
            {'id': 'wall_north', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw, -hh], 'local_end': [hw, -hh]},
            {'id': 'wall_west', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw, -hh], 'local_end': [-hw, hh]},
        ]
    return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('matches_json')
    ap.add_argument('out_json')
    ap.add_argument('--id', default='layout_parse_test')
    ap.add_argument('--name', default='Parsed Layout')
    args = ap.parse_args()

    with open(args.matches_json) as f:
        data = json.load(f)
    matches = data['matches']

    # Snap paired pieces
    for m in matches:
        partner_idx = m.get('paired_with')
        if partner_idx is None: continue
        partner = matches[partner_idx]
        if m['kind'] == 'tall' and partner['kind'] == 'low':
            snap_pair(m, partner)
        # else: the other direction is handled when we encounter the tall
        # one; we don't snap twice.

    # Build pieces
    pieces = []
    counters = {'tall': 0, 'low': 0}
    for m in matches:
        x_v, y_v, angle_v = horizontal_to_vertical(
            m['cx_in'], m['cy_in'], m['angle'])
        counters[m['kind']] += 1
        idx = counters[m['kind']]
        pid = f"{m['kind']}_{idx:02d}"
        piece = {
            'id': pid,
            'type': 'ruins',
            'position': [round(x_v, 2), round(y_v, 2)],
            'size': [m['long'], m['short']],
            'height': 'tall' if m['kind'] == 'tall' else 'low',
            'rotation': round(angle_v, 1),
            'walls': make_walls(m['slot_hint'], m['long'], m['short']),
        }
        if m['kind'] == 'tall':
            piece['traits'] = ['obscuring']
        piece['_slot'] = m['slot_hint']  # debug
        pieces.append(piece)

    layout = {
        'id': args.id,
        'name': args.name,
        'description': f"Generated by catalog-based parser; "
                       f"{len(pieces)} pieces from canonical catalog.",
        'recommended_deployments': ['hammer_anvil', 'dawn_of_war',
                                    'crucible_of_battle'],
        'pieces': pieces,
    }
    with open(args.out_json, 'w') as f:
        json.dump(layout, f, indent=2)
    print(f"Wrote {args.out_json} with {len(pieces)} pieces")


if __name__ == '__main__':
    main()
