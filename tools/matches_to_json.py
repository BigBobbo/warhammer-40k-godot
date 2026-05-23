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
    """Move the low piece so it touches the tall piece on their shared
    edge (canonical 6" for 8x6+4x6, canonical 5" for 6.5x5+3.5x5).
    Both pieces are rectangles (possibly rotated). Determine which side
    of the tall the low is on (based on relative position), then place
    the low's appropriate edge against the tall's corresponding edge.
    """
    tx, ty = tall_match['cx_in'], tall_match['cy_in']
    lx, ly = low_match['cx_in'], low_match['cy_in']
    dx, dy = lx - tx, ly - ty
    # In the piece-local frame of the TALL piece, place the low along
    # the side closest to the current low position.
    rad = math.radians(tall_match['angle'])
    ca, sa = math.cos(rad), math.sin(rad)
    # Project (dx, dy) onto tall's local axes
    local_dx = ca * dx + sa * dy
    local_dy = -sa * dx + ca * dy
    # Tall's long axis = local +x, half-length = long/2
    t_hw = tall_match['long'] / 2
    t_hh = tall_match['short'] / 2
    # Low's dimensions (assume same orientation as tall - they share an edge)
    l_long = low_match['long']
    l_short = low_match['short']
    # Determine which face of the tall is closest to the low.
    # Tall is paired with low on either: east face (+x), west (-x),
    # north (-y), or south (+y) in tall's local frame.
    # The shared edge dimension determines which low-side touches.
    # For 8x6+4x6: shared 6" edge is the SHORT side of the tall (6 = short).
    #   So low touches tall on the east or west face (local x = +/- t_hw).
    #   The low's matching edge is also length 6, which is its LONG side (4x6).
    # For 6.5x5+3.5x5: shared 5" edge is the SHORT side of tall (5 = short).
    #   Low touches tall on east or west face. Low's matching edge = 5 = long.
    # In both cases: low touches tall on the +/- x face (long axis ends).
    if abs(local_dx) >= abs(local_dy):
        # Low is to east or west of tall (along tall's long axis)
        sign = 1 if local_dx > 0 else -1
        # Tall's east/west face is at local x = +/- t_hw
        # Low's centre should be at local x = sign * (t_hw + l_long/2)
        new_local_x = sign * (t_hw + l_long / 2)
        new_local_y = 0.0  # share full extent along short axis
    else:
        sign = 1 if local_dy > 0 else -1
        new_local_x = 0.0
        new_local_y = sign * (t_hh + l_short / 2)
    # Convert local back to world
    new_dx = ca * new_local_x - sa * new_local_y
    new_dy = sa * new_local_x + ca * new_local_y
    low_match['cx_in'] = round(tx + new_dx, 2)
    low_match['cy_in'] = round(ty + new_dy, 2)
    # When sharing a face, the low piece inherits the tall's rotation
    low_match['angle'] = tall_match['angle']


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
