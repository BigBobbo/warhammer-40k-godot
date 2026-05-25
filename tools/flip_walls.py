#!/usr/bin/env python3
"""Flip all wall local_start and local_end coordinates by 180-degrees in
the piece-local frame (multiply x and y by -1).

This corrects walls that were authored against the buggy horizontal
renderer (which used rot_v - 90 instead of rot_v + 90, putting walls on
opposite corners in horizontal view). The walls in the JSON looked right
in those buggy renders but appear on the wrong corners in-game and in
the corrected horizontal renderer.

Usage: python3 tools/flip_walls.py path/to/layout.json
"""

import json
import sys


def main():
    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)
    flipped = 0
    for p in data['pieces']:
        for w in p.get('walls', []):
            s = w['local_start']; e = w['local_end']
            w['local_start'] = [-s[0], -s[1]]
            w['local_end'] = [-e[0], -e[1]]
            flipped += 1
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Flipped {flipped} walls in {path}")


if __name__ == '__main__':
    main()
