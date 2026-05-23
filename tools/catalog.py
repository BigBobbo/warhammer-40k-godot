"""Canonical terrain piece catalog.

Every GW Chapter Approved tournament layout uses the SAME 18 pieces:
- 6x  (6"x4")   low ruins, standalone
- 4x  (12"x6")  tall ruins; 2 with C-shape walls, 2 with L-shape walls
- 2x  (8"x6")   tall ruins, L-shape walls; each paired with...
- 2x  (4"x6")   low ruins; each adjacent to an 8x6 tall on its 6" edge
                (combined 12x6 footprint, still 2 pieces)
- 2x  (6.5"x5") tall ruins, L-shape walls; each paired with...
- 2x  (3.5"x5") low ruins; each adjacent to a 6.5x5 tall on its 5" edge
                (combined 10x5 footprint, still 2 pieces)

Total: 18 pieces, 9 symmetric pairs under 180-degree rotation about the
board center.
"""

import math

# Canonical pieces. Each row defines ONE class of piece:
#   slot       : symbolic identifier
#   height     : 'tall' or 'low'
#   long       : the longer dimension in inches
#   short      : the shorter dimension in inches (== long for squares)
#   count      : how many of this piece appear in EVERY layout
#   wall_style : 'C' (long base with two arms, all inset 1.5"), 'L'
#                (two perpendicular walls meeting at a corner), or None
#   paired_with: slot id of the partner piece this one is adjacent to
#                (e.g. tall_8x6 <-> low_4x6), or None if standalone
PIECES = [
    # slot           h    long  short count wall  paired_with
    ('low_6x4',     'low',  6.0, 4.0,  6,   None,  None),
    ('tall_12x6_C', 'tall',12.0, 6.0,  2,   'C',   None),
    ('tall_12x6_L', 'tall',12.0, 6.0,  2,   'L',   None),
    ('tall_8x6',    'tall', 8.0, 6.0,  2,   'L',  'low_4x6'),
    ('low_4x6',     'low',  6.0, 4.0,  2,   None, 'tall_8x6'),
    ('tall_6.5x5',  'tall', 6.5, 5.0,  2,   'L',  'low_3.5x5'),
    ('low_3.5x5',   'low',  5.0, 3.5,  2,   None, 'tall_6.5x5'),
]


def slot_by(name):
    for row in PIECES:
        if row[0] == name:
            return row
    raise KeyError(name)


def all_size_classes():
    """Yield distinct (long, short, height) tuples used by any slot."""
    seen = set()
    for slot, h, long_, short, *_ in PIECES:
        key = (long_, short, h)
        if key not in seen:
            seen.add(key)
            yield key


# Pre-compute 45-deg AABB sizes for matching tilted pieces.
# For a (a,b) rectangle rotated 45deg, AABB is (a+b)/sqrt(2) on each side
# (square AABB).
def aabb_45(long_, short):
    return (long_ + short) / math.sqrt(2.0)


def expected_total():
    return sum(p[4] for p in PIECES)


if __name__ == '__main__':
    print(f"Catalog has {len(PIECES)} slots, {expected_total()} pieces total")
    print()
    print(f"{'slot':16s} {'h':5s} {'size':10s} {'count':5s} {'wall':4s}  {'45-AABB':8s}")
    for slot, h, long_, short, cnt, wall, paired in PIECES:
        print(f"{slot:16s} {h:5s} {long_:5.1f}x{short:4.1f} {cnt:5d} "
              f"{(wall or '-'):4s}  {aabb_45(long_, short):.2f}\"")
