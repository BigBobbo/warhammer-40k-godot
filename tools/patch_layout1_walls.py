#!/usr/bin/env python3
"""Patch the wall corners in a layout JSON based on per-piece manual
overrides.

Each override entry: {piece_id: corner} where corner is one of
'nw', 'ne', 'sw', 'se'.
"""

import json
import sys


def make_walls(slot, long_, short, corner):
    hw = long_ / 2
    hh = short / 2

    if slot == 'tall_12x6_C':
        inset = 1.5
        arm_len = 3.0
        if corner in ('nw', 'ne'):
            y_base = -hh; arm_dy = arm_len
        else:
            y_base = +hh; arm_dy = -arm_len
        return [
            {'id': 'wall_base', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw + inset, y_base],
             'local_end':   [ hw - inset, y_base]},
            {'id': 'wall_arm_west', 'type': 'solid', 'blocks_los': True,
             'local_start': [-hw + inset, y_base],
             'local_end':   [-hw + inset, y_base + arm_dy]},
            {'id': 'wall_arm_east', 'type': 'solid', 'blocks_los': True,
             'local_start': [ hw - inset, y_base],
             'local_end':   [ hw - inset, y_base + arm_dy]},
        ]
    # L-shape
    if corner == 'nw':
        x_v, y_h = -hw, -hh
    elif corner == 'ne':
        x_v, y_h = +hw, -hh
    elif corner == 'sw':
        x_v, y_h = -hw, +hh
    else:  # se
        x_v, y_h = +hw, +hh
    return [
        {'id': 'wall_h', 'type': 'solid', 'blocks_los': True,
         'local_start': [-hw, y_h], 'local_end': [hw, y_h]},
        {'id': 'wall_v', 'type': 'solid', 'blocks_los': True,
         'local_start': [x_v, -hh], 'local_end': [x_v, hh]},
    ]


# Layout 1 wall corners (hand-specified from user feedback):
OVERRIDES_LAYOUT_1 = {
    'tall_01': 'nw',  # C on local NORTH (user: "C on the left side")
    'tall_02': 'se',  # L on local SE (user: "L on the top right")
    'tall_03': 'ne',  # 180-mirror of tall_08's SW
    'tall_04': 'sw',  # 180-mirror of tall_05 (NE -> SW)
    'tall_05': 'ne',  # L on local NE (user: "L on the top right")
    'tall_06': 'sw',  # C on local SOUTH (180-mirror of tall_01)
    'tall_07': 'nw',  # L on local NW (180-mirror of tall_02)
    'tall_08': 'sw',  # L on local SW (user: "L on the left two diagonal walls")
}


def main():
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)
    for p in data['pieces']:
        pid = p['id']
        if pid not in OVERRIDES_LAYOUT_1:
            continue
        corner = OVERRIDES_LAYOUT_1[pid]
        slot = p.get('_slot', '')
        p['walls'] = make_walls(slot, p['size'][0], p['size'][1], corner)
        print(f"  {pid} -> {corner} ({slot})")
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Wrote {path}")


if __name__ == '__main__':
    main()
