#!/usr/bin/env python3
"""Patch the wall corners in a layout JSON based on per-piece manual
overrides.

Each override entry: {piece_id: corner} where corner is one of
'nw', 'ne', 'sw', 'se'.
"""

import json
import sys


def make_walls(slot, long_, short, corner, h_ext=None, v_ext=None):
    """h_ext / v_ext: optional extents (in inches) for the two L arms.
    h_ext is the length of the wall running along the long axis (the
    "horizontal" arm in local frame). v_ext is the length of the wall
    running along the short axis (the "vertical" arm in local frame).
    Default = full length (long_ for h, short for v).
    """
    hw = long_ / 2
    hh = short / 2
    if h_ext is None: h_ext = long_
    if v_ext is None: v_ext = short

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
    # L-shape: walls along two adjacent edges meeting at `corner`.
    # The H wall runs along the long axis on the y=y_h edge.
    # The V wall runs along the short axis on the x=x_v edge.
    # Each may be FULL or PARTIAL, extending from the corner.
    if corner == 'nw':
        x_v_edge, y_h_edge = -hw, -hh
        h_dir, v_dir = +1, +1  # H goes from west toward east, V from north toward south
    elif corner == 'ne':
        x_v_edge, y_h_edge = +hw, -hh
        h_dir, v_dir = -1, +1
    elif corner == 'sw':
        x_v_edge, y_h_edge = -hw, +hh
        h_dir, v_dir = +1, -1
    else:  # se
        x_v_edge, y_h_edge = +hw, +hh
        h_dir, v_dir = -1, -1
    return [
        # Horizontal wall along long-axis edge, extending h_ext from corner
        {'id': 'wall_h', 'type': 'solid', 'blocks_los': True,
         'local_start': [x_v_edge, y_h_edge],
         'local_end':   [x_v_edge + h_dir * h_ext, y_h_edge]},
        # Vertical wall along short-axis edge, extending v_ext from corner
        {'id': 'wall_v', 'type': 'solid', 'blocks_los': True,
         'local_start': [x_v_edge, y_h_edge],
         'local_end':   [x_v_edge, y_h_edge + v_dir * v_ext]},
    ]


# Layout 1 wall corners + extents (from user feedback + source inspection):
OVERRIDES_LAYOUT_1 = {
    'tall_01': ('nw', None, None),  # C: standard arms
    'tall_02': ('se', 6.0, 6.0),    # L 12x6: long-axis arm 6 (half), short full
    'tall_03': ('ne', None, None),  # L 6.5x5: full arms
    'tall_04': ('sw', 7.0, 5.0),    # L 8x6: arms stop ~1" short
    'tall_05': ('ne', 7.0, 5.0),    # L 8x6: arms stop ~1" short
    'tall_06': ('sw', None, None),  # C: standard arms (mirror of tall_01)
    'tall_07': ('nw', 6.0, 6.0),    # L 12x6: long-axis arm half (mirror of tall_02)
    'tall_08': ('sw', None, None),  # L 6.5x5: full arms (mirror of tall_03)
}


def main():
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)
    for p in data['pieces']:
        pid = p['id']
        if pid not in OVERRIDES_LAYOUT_1:
            continue
        corner, h_ext, v_ext = OVERRIDES_LAYOUT_1[pid]
        slot = p.get('_slot', '')
        p['walls'] = make_walls(slot, p['size'][0], p['size'][1], corner,
                                 h_ext=h_ext, v_ext=v_ext)
        ext_str = f" h={h_ext} v={v_ext}" if (h_ext or v_ext) else ""
        print(f"  {pid} -> {corner}{ext_str} ({slot})")
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Wrote {path}")


if __name__ == '__main__':
    main()
