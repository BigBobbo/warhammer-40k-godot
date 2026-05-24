#!/usr/bin/env python3
"""Match detected blobs to canonical catalog pieces.

Input: output of tools/detect_pieces_precise.py (or any source that gives
   a list of blobs with kind/center/AABB/fill).
Output: a list of pieces with EXACT canonical sizes, snapped positions,
   inferred rotations, and pairing info.

Each detected blob is classified as either:
  - axis-aligned (fill ~= 1.0):     AABB IS the piece's size; rotation
                                    is 0 if long axis along x, 90 if
                                    along y.
  - 45-deg rotated (fill ~= 0.5):   the piece is rotated 45deg; the
                                    actual (long, short) satisfies
                                    (long + short) / sqrt(2) == AABB
                                    dimension. Rotation = 45 (or -45,
                                    indistinguishable from AABB alone).

Matching: among the canonical (long, short) pairs in tools/catalog.py,
pick the one with smallest L1 distance to the detected dimensions.

For the (12x6) tall pieces, two slots exist (C-walled and L-walled).
The matcher cannot tell them apart from geometry alone; the caller
must specify via a wall-style hint or by examining the source image.
"""

import argparse
import json
import math
import sys

from catalog import PIECES, aabb_45


def _canonical_size_classes(height):
    """Yield (slot, long, short, paired_with) for canonical pieces matching
    the given height. Duplicate slots (e.g. tall_12x6_C and tall_12x6_L
    have the same dimensions) are deduplicated to (long, short) here;
    wall-style is resolved later."""
    seen = set()
    out = []
    for slot, h, long_, short, cnt, wall, paired in PIECES:
        if h != height:
            continue
        key = (long_, short)
        if key in seen:
            continue
        seen.add(key)
        out.append((slot, long_, short, paired))
    return out


def match_blob(blob):
    """Match a single detected blob to a canonical (long, short, rotation).
    Returns dict: {kind, long, short, angle, slot_hint, score}.
    angle is in degrees (0, 90, or 45) for orientation in horizontal frame.
    """
    kind = blob['kind']
    w_aabb = blob['w_in']
    h_aabb = blob['h_in']
    fill = blob.get('fill', 1.0)

    is_rotated = fill < 0.65 and abs(w_aabb - h_aabb) < max(w_aabb, h_aabb) * 0.15

    candidates = _canonical_size_classes(kind)
    best = None

    for slot, c_long, c_short, paired in candidates:
        if is_rotated:
            # 45-deg rotation: AABB is square with side (long+short)/sqrt(2).
            expected_aabb = aabb_45(c_long, c_short)
            measured = (w_aabb + h_aabb) / 2
            score = abs(expected_aabb - measured)
            # Use detector's angle_hint if it determined +45 or -45 from
            # the rightmost-pixel test. Default to +45 otherwise.
            angle = blob.get('angle_hint', 45.0) or 45.0
            cand = {
                'long': c_long, 'short': c_short,
                'angle': angle, 'slot_hint': slot, 'score': score,
            }
        else:
            # Axis-aligned. Determine orientation: which AABB dim is the long?
            if w_aabb >= h_aabb:
                # Long along x -> angle = 0, expected (w,h) = (long, short)
                e_w, e_h = c_long, c_short
                angle = 0.0
            else:
                # Long along y -> angle = 90, expected (w,h) = (short, long)
                e_w, e_h = c_short, c_long
                angle = 90.0
            score = abs(w_aabb - e_w) + abs(h_aabb - e_h)
            cand = {
                'long': c_long, 'short': c_short,
                'angle': angle, 'slot_hint': slot, 'score': score,
            }

        if best is None or cand['score'] < best['score']:
            best = cand

    best['kind'] = kind
    best['cx_in'] = blob['cx_in']
    best['cy_in'] = blob['cy_in']
    best['aabb_in'] = (w_aabb, h_aabb)
    best['fill'] = fill
    best['is_rotated'] = is_rotated
    return best


def pair_adjacent(matches, max_distance_in=8.0):
    """For each tall piece that has a 'paired_with' rule in the catalog
    (currently tall_8x6 and tall_6.5x5), find the nearest LOW piece of
    any low slot and mark them as paired. The low piece will then be
    relabelled based on which tall it's paired with."""
    pair_rules = {}  # tall_slot -> low_slot
    for slot, h, long_, short, cnt, wall, paired in PIECES:
        if h == 'tall' and paired is not None:
            pair_rules[slot] = paired

    paired_marks = [False] * len(matches)
    pairs = []
    for tall_slot in pair_rules:
        idxs_t = [i for i, m in enumerate(matches)
                  if m['slot_hint'] == tall_slot and not paired_marks[i]]
        idxs_l = [i for i, m in enumerate(matches)
                  if m['kind'] == 'low' and not paired_marks[i]]
        for it in idxs_t:
            mt = matches[it]
            best_il = -1
            best_d = max_distance_in
            for il in idxs_l:
                if paired_marks[il]: continue
                ml = matches[il]
                d = math.hypot(mt['cx_in'] - ml['cx_in'],
                               mt['cy_in'] - ml['cy_in'])
                if d < best_d:
                    best_d = d
                    best_il = il
            if best_il != -1:
                paired_marks[it] = True
                paired_marks[best_il] = True
                pairs.append((it, best_il, best_d))
                matches[it]['paired_with'] = best_il
                matches[best_il]['paired_with'] = it
    return pairs


def assign_wall_style(matches, board_w=60.0, board_h=44.0):
    """For the four (12x6) tall pieces, half are C-walled and half are
    L-walled (per the canonical catalog).

    Heuristic: pieces CLOSER to the board centre get C-walls; pieces
    FARTHER from centre get L-walls. This matches both Layout 1 (where
    the 4 verticals split into a near-centre C pair and a far-corner L
    pair) and Layout 2 (centre diagonals = C, outer horizontals = L).
    """
    twelve_six = [m for m in matches
                  if m['slot_hint'] in ('tall_12x6_C', 'tall_12x6_L')]
    if len(twelve_six) < 2:
        return
    cx_b, cy_b = board_w / 2, board_h / 2
    twelve_six.sort(key=lambda m: math.hypot(m['cx_in'] - cx_b,
                                              m['cy_in'] - cy_b))
    # Half closest get C, half farthest get L. Round half size.
    half = len(twelve_six) // 2
    for i, m in enumerate(twelve_six):
        if i < half:
            m['slot_hint'] = 'tall_12x6_C'
        else:
            m['slot_hint'] = 'tall_12x6_L'


def filter_artifacts(matches, max_score=1.5, board_w=60.0, board_h=44.0,
                     edge_margin=3.0, min_fill=0.42):
    """Reject:
    - Bad match score (likely annotations or noise).
    - Centre within `edge_margin` of image edges (corner annotations -
      measurement arrows, "TERRAIN LAYOUT" tab fragments).
    - Fill ratio too low (annotations don't fill a clean rectangle).
      Real pieces: axis-aligned ~0.95, 45-deg rotated ~0.5."""
    out = []
    for m in matches:
        if m['score'] > max_score:
            continue
        if (m['cx_in'] < edge_margin or m['cx_in'] > board_w - edge_margin or
                m['cy_in'] < edge_margin or m['cy_in'] > board_h - edge_margin):
            continue
        if m.get('fill', 1.0) < min_fill:
            continue
        out.append(m)
    return out


def dedupe_overlapping(matches, min_distance_in=2.0):
    """If two matches of the same slot are very close, keep the one with
    the lower score (better match). The detector + symmetry-fill can
    occasionally create duplicates."""
    keep = [True] * len(matches)
    for i, m in enumerate(matches):
        if not keep[i]: continue
        for j in range(i + 1, len(matches)):
            if not keep[j]: continue
            n = matches[j]
            if n['slot_hint'] != m['slot_hint']: continue
            d = math.hypot(m['cx_in'] - n['cx_in'],
                           m['cy_in'] - n['cy_in'])
            if d < min_distance_in:
                if m['score'] <= n['score']:
                    keep[j] = False
                else:
                    keep[i] = False
                    break
    return [m for i, m in enumerate(matches) if keep[i]]


def relabel_paired(matches):
    """After pairing, change slot of low pieces paired with tall_8x6 to
    'low_4x6', and paired with tall_6.5x5 to 'low_3.5x5'."""
    for m in matches:
        partner_idx = m.get('paired_with')
        if partner_idx is None: continue
        partner = matches[partner_idx]
        if m['kind'] != 'low': continue
        if partner['slot_hint'] == 'tall_8x6':
            m['slot_hint'] = 'low_4x6'
            m['long'], m['short'] = 6.0, 4.0
        elif partner['slot_hint'] == 'tall_6.5x5':
            m['slot_hint'] = 'low_3.5x5'
            m['long'], m['short'] = 5.0, 3.5


def merge_fragments(matches, max_distance_in=2.0):
    """Merge nearby blobs of the same kind into a single piece. The
    detector sometimes fragments a piece when an annotation line crosses
    through it. Combine fragments by union of their AABBs."""
    out = []
    used = [False] * len(matches)
    for i, m in enumerate(matches):
        if used[i]: continue
        cluster = [m]
        used[i] = True
        for j in range(i + 1, len(matches)):
            if used[j]: continue
            n = matches[j]
            if n['kind'] != m['kind']: continue
            d = math.hypot(m['cx_in'] - n['cx_in'],
                           m['cy_in'] - n['cy_in'])
            if d <= max_distance_in:
                cluster.append(n)
                used[j] = True
        if len(cluster) == 1:
            out.append(m)
        else:
            # Merge cluster: union AABBs, recompute centre
            xs_lo, xs_hi = [], []
            ys_lo, ys_hi = [], []
            for c in cluster:
                xs_lo.append(c['cx_in'] - c['aabb_in'][0]/2)
                xs_hi.append(c['cx_in'] + c['aabb_in'][0]/2)
                ys_lo.append(c['cy_in'] - c['aabb_in'][1]/2)
                ys_hi.append(c['cy_in'] + c['aabb_in'][1]/2)
            x_lo, x_hi = min(xs_lo), max(xs_hi)
            y_lo, y_hi = min(ys_lo), max(ys_hi)
            merged_blob = {
                'kind': m['kind'],
                'cx_in': (x_lo + x_hi) / 2,
                'cy_in': (y_lo + y_hi) / 2,
                'w_in': x_hi - x_lo,
                'h_in': y_hi - y_lo,
                'fill': max(c['fill'] for c in cluster),
            }
            out.append(match_blob(merged_blob))
    return out


def add_missing_via_symmetry(matches, board_w=60.0, board_h=44.0,
                              max_distance_in=1.5):
    """For each piece A, look for a 180-mirror counterpart at (W-x, H-y).
    If none found, ADD one. Useful for filling gaps where the detector
    missed a piece in one half but found it in the other."""
    extra = []
    for i, m in enumerate(matches):
        mx = board_w - m['cx_in']
        my = board_h - m['cy_in']
        found = False
        for j, n in enumerate(matches):
            if i == j: continue
            if n['kind'] != m['kind']: continue
            if math.hypot(n['cx_in'] - mx, n['cy_in'] - my) <= max_distance_in:
                found = True
                break
        if not found:
            mirror = dict(m)
            mirror['cx_in'] = mx
            mirror['cy_in'] = my
            mirror['synthesised'] = True
            extra.append(mirror)
    return matches + extra


def enforce_symmetry(matches, board_w=60.0, board_h=44.0):
    """Average each piece with its mirror to force exact 180-deg symmetry."""
    out = list(matches)
    used = [False] * len(out)
    for i, m in enumerate(out):
        if used[i]: continue
        mx = board_w - m['cx_in']
        my = board_h - m['cy_in']
        best_j = -1
        best_d = 1e9
        for j in range(i + 1, len(out)):
            if used[j]: continue
            n = out[j]
            if n['slot_hint'] != m['slot_hint']: continue
            d = math.hypot(n['cx_in'] - mx, n['cy_in'] - my)
            if d < best_d:
                best_d = d
                best_j = j
        if best_j != -1 and best_d < 3.0:
            n = out[best_j]
            mx_n = board_w - n['cx_in']
            my_n = board_h - n['cy_in']
            avg_x = (m['cx_in'] + mx_n) / 2
            avg_y = (m['cy_in'] + my_n) / 2
            m['cx_in'] = round(avg_x, 2)
            m['cy_in'] = round(avg_y, 2)
            n['cx_in'] = round(board_w - avg_x, 2)
            n['cy_in'] = round(board_h - avg_y, 2)
            used[i] = True
            used[best_j] = True
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('blobs_json',
                    help='JSON file with detected blobs (output of '
                         'detect_pieces_precise.py)')
    ap.add_argument('--max-score', type=float, default=1.5,
                    help='Reject matches with score worse than this (in)')
    args = ap.parse_args()
    with open(args.blobs_json) as f:
        blobs = json.load(f)

    print(f"Loaded {len(blobs)} raw blobs", file=sys.stderr)
    matches = [match_blob(b) for b in blobs]

    matches = merge_fragments(matches)
    print(f"After fragment merge:    {len(matches)}", file=sys.stderr)

    matches = filter_artifacts(matches, max_score=args.max_score)
    print(f"After artifact filter:   {len(matches)}", file=sys.stderr)

    matches = dedupe_overlapping(matches)
    print(f"After dedupe:            {len(matches)}", file=sys.stderr)

    matches = add_missing_via_symmetry(matches)
    print(f"After symmetry gap-fill: {len(matches)}", file=sys.stderr)

    matches = dedupe_overlapping(matches)
    print(f"After 2nd dedupe:        {len(matches)}", file=sys.stderr)

    matches = enforce_symmetry(matches)

    pairs = pair_adjacent(matches)
    relabel_paired(matches)
    assign_wall_style(matches)

    # Count summary
    from collections import Counter
    summary = Counter(m['slot_hint'] for m in matches)
    print(f"\nFinal piece counts:", file=sys.stderr)
    for k, v in sorted(summary.items()):
        print(f"  {k:14s} {v}", file=sys.stderr)
    print(json.dumps({'matches': matches, 'pairs': pairs}, indent=2))


if __name__ == '__main__':
    main()
