#!/usr/bin/env python3
"""Terrain-layout data integrity checker (11e terrain AREAS, 13.01).

TerrainManager.build_area_group_map (40k/autoloads/TerrainManager.gd) folds the
pieces of a layout into terrain-area GROUPS: link_group wins, else the
parent_area_id chain, else the piece is its own area. Those groups drive
13.09 HIDDEN (a model is within a dense terrain area if ANY piece of its group
is dense) and the 13.10/13.11 visibility exclusions (a model ignores every
obscuring piece of a group it is within). A group must therefore be ONE
physically contiguous terrain area. The upstream 40kdc dataset (1.0.19, the
version the 45 GW layouts were converted from) broke this in two ways, both
from point-mirroring half a board to build the other half:
  * features parented to the point-mirrored twin of the area they sit in
    (e.g. take_and_hold_mirror_1 corner-short-9..12 -> area-medium-7/8, 37"
    away); in take_and_hold_vs_reconnaissance_1 four walls are parented to a
    neighbouring area instead of the home-objective ruin they stand in;
  * one link_group label shared by a cluster AND its mirrored twin, which
    merges two (or four) separate terrain areas into one group.

Checks -- ERROR (exit status 1):
  parent-missing    parent_area_id names no piece of the layout
  parent-not-area   the parent piece is not piece_class "area"
  parent-far        LOOSE criterion: the feature polygon neither overlaps nor
                    comes within ABUT_TOL (0.5") of its parent's polygon
  link-split        the pieces sharing one link_group label do not form one
                    connected cluster (<= ABUT_TOL adjacency, transitive)
  group-split       an engine group (keys resolved exactly like
                    TerrainManager._resolve_group_key) is not one connected
                    cluster -- what parent-far / link-split break in-engine
  area-aggregate    an area's category / height_inches / height / traits are
                    not the generator's derivation from the features parented
                    to it (scripts/40kdc/generate-terrain-layouts.mjs:
                    areaContents, pieceGameplay, pieceTraits, heightCategory),
                    so a re-parent cannot leave stale area data behind
Reported, not failing (--strict makes parent-minority an ERROR):
  parent-minority   STRICT criterion: the feature touches its parent but its
                    centroid is outside it or < 50% of its footprint is inside
                    it. When the area holding most of it is in the SAME group
                    (a link_group sibling half) the engine result is identical.
  parentless-inside a feature without parent_area_id lies mostly inside an
                    area; the engine treats it as its own 13.01 area.
  link-overrides-parent  a feature's link_group puts it in a different group
                    than its parent area (link_group wins in the engine).

The LOOSE criterion is what the engine cares about (30 features / 8 files on
the pre-fix data); the STRICT one also counts features that straddle the
boundary of two linked halves (56 / 17 pre-fix: the 30 plus 26 same-group).

Usage (from the repo root):
  python3 tools/check_terrain_layouts.py               # report; exit 1 on ERROR
  python3 tools/check_terrain_layouts.py --strict      # parent-minority fails too
  python3 tools/check_terrain_layouts.py --json out.json
  python3 tools/check_terrain_layouts.py --fix         # repair in place, then re-check
  python3 tools/check_terrain_layouts.py --layouts-dir DIR --only NAME [--only NAME]

--fix re-parents every parent-far feature to the area holding most of its
footprint (must be >= 50% and unique), gives every extra cluster of a split
link_group label its own label ("<label>#2", "#3", ... in file order; the
first cluster keeps the original), and re-derives the aggregate fields of the
areas whose children changed. It only rewrites files whose JSON round-trips
byte-identically through json.dumps(indent=1), so the diff is exactly the
repaired fields. Stdlib only.
"""

import argparse
import glob
import json
import math
import os
import sys

ABUT_TOL = 0.5          # inches: "overlaps or abuts"
MAJORITY = 0.5          # fraction of a feature's footprint
BOARD_W, BOARD_H = 44.0, 60.0   # portrait 11e board (point mirror centre 22,30)
CATEGORY_RANK = {"exposed": 0, "light": 1, "dense": 2}
ERROR_CHECKS = ("parent-missing", "parent-not-area", "parent-far", "link-split",
                "group-split", "area-aggregate")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(REPO, "40k", "terrain_layouts")


# ── geometry (board inches) ─────────────────────────────────────────────
def _poly(piece):
    return [(float(v[0]), float(v[1])) for v in piece.get("polygon", [])]


def point_in_poly(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            if x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
    return inside


def _seg_point(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    ll = dx * dx + dy * dy
    t = 0.0 if ll == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ll))
    return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _seg_seg(a, b, c, d):
    d1, d2, d3, d4 = _cross(c, d, a), _cross(c, d, b), _cross(a, b, c), _cross(a, b, d)
    if ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and 0 not in (d1, d2, d3, d4):
        return 0.0
    return min(_seg_point(a, c, d), _seg_point(b, c, d), _seg_point(c, a, b), _seg_point(d, a, b))


def poly_distance(p, q):
    """0 when the polygons overlap or touch, else the closest edge gap."""
    if any(point_in_poly(v, q) for v in p) or any(point_in_poly(v, p) for v in q):
        return 0.0
    best = float("inf")
    for i in range(len(p)):
        a, b = p[i], p[(i + 1) % len(p)]
        for j in range(len(q)):
            best = min(best, _seg_seg(a, b, q[j], q[(j + 1) % len(q)]))
            if best == 0.0:
                return 0.0
    return best


def poly_area(p):
    s = 0.0
    for i in range(len(p)):
        s += p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1]
    return abs(s) / 2.0


def centroid(p):
    return (sum(v[0] for v in p) / len(p), sum(v[1] for v in p) / len(p))


def _is_convex(p):
    sign = 0
    for i in range(len(p)):
        c = _cross(p[i], p[(i + 1) % len(p)], p[(i + 2) % len(p)])
        if abs(c) < 1e-12:
            continue
        s = 1 if c > 0 else -1
        if sign == 0:
            sign = s
        elif s != sign:
            return False
    return True


def _clip_convex(subject, clip):
    """Sutherland-Hodgman: subject (any simple polygon) clipped by a convex one."""
    orient = 1.0 if sum(_cross(clip[0], clip[i], clip[i + 1]) for i in range(1, len(clip) - 1)) > 0 else -1.0
    out = list(subject)
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        inp, out = out, []
        if not inp:
            break
        for j in range(len(inp)):
            cur, prev = inp[j], inp[j - 1]
            cin = orient * _cross(a, b, cur) >= 0
            pin = orient * _cross(a, b, prev) >= 0
            if cin != pin:
                dx, dy = cur[0] - prev[0], cur[1] - prev[1]
                den = (b[0] - a[0]) * dy - (b[1] - a[1]) * dx
                if den != 0:
                    t = ((b[0] - a[0]) * (a[1] - prev[1]) - (b[1] - a[1]) * (a[0] - prev[0])) / den
                    out.append((prev[0] + t * dx, prev[1] + t * dy))
            if cin:
                out.append(cur)
    return out


def overlap_fraction(feature, area):
    """Fraction of the feature's footprint inside the area polygon."""
    fa = poly_area(feature)
    if fa == 0:
        return 0.0
    if _is_convex(area):
        clipped = _clip_convex(feature, area)
        return min(1.0, poly_area(clipped) / fa) if len(clipped) >= 3 else 0.0
    # non-convex area (none ship today): grid sampling fallback
    xs, ys = [v[0] for v in feature], [v[1] for v in feature]
    n, tot, hit = 60, 0, 0
    for i in range(n):
        for j in range(n):
            pt = (min(xs) + (i + 0.5) * (max(xs) - min(xs)) / n, min(ys) + (j + 0.5) * (max(ys) - min(ys)) / n)
            if point_in_poly(pt, feature):
                tot += 1
                hit += point_in_poly(pt, area)
    return hit / tot if tot else 0.0


def point_mirror(p):
    return [(BOARD_W - x, BOARD_H - y) for x, y in p]


# ── engine mirror: TerrainManager._resolve_group_key ────────────────────
def resolve_group_key(piece, by_id, depth=0):
    lg = str(piece.get("link_group", "") or "")
    if lg != "":
        return "lg:" + lg
    parent_id = str(piece.get("parent_area_id", "") or "")
    if parent_id != "" and depth < 4 and parent_id in by_id:
        return resolve_group_key(by_id[parent_id], by_id, depth + 1)
    if parent_id != "":
        return "id:" + parent_id
    return "id:" + str(piece.get("id", ""))


def build_area_group_map(pieces):
    by_id = {str(p.get("id", "")): p for p in pieces}
    return {str(p.get("id", "")): resolve_group_key(p, by_id) for p in pieces}


def clusters(ids, polys):
    """Connected components of `ids` under <= ABUT_TOL adjacency (file order)."""
    remaining = list(ids)
    comps = []
    while remaining:
        comp = [remaining.pop(0)]
        k = 0
        while k < len(comp):
            cur = comp[k]
            for other in list(remaining):
                if poly_distance(polys[cur], polys[other]) <= ABUT_TOL:
                    comp.append(other)
                    remaining.remove(other)
            k += 1
        comps.append(comp)
    return comps


# ── generator mirror: scripts/40kdc/generate-terrain-layouts.mjs ────────
def height_category(h):
    return "low" if h < 2 else ("medium" if h <= 4 else "tall")


def area_aggregate(area, children):
    """category / height_inches / height / traits the generator derives for an
    area from the features parented to it (the shipped data has no per-area
    overrides: every area matched this rule before the 2026-11 fix)."""
    cat, max_h = "exposed", 0
    for c in children:
        cc = str(c.get("category", "exposed"))
        if CATEGORY_RANK.get(cc, 0) > CATEGORY_RANK[cat]:
            cat = cc
        max_h = max(max_h, c.get("height_inches", 0))
    traits = (["obscuring"] if cat == "dense" else []) + ["difficult_ground"]
    return {"category": cat, "height_inches": max_h, "height": height_category(max_h), "traits": traits}


# ── checks ──────────────────────────────────────────────────────────────
def check_layout(name, data):
    """Returns (findings, suggestions). suggestions feed --fix."""
    findings = []
    sugg = {"reparent": {}, "relabel": {}}
    pieces = [p for p in data.get("pieces", []) if len(p.get("polygon", [])) >= 3]
    if not pieces:
        return findings, sugg
    by_id = {p["id"]: p for p in pieces}
    polys = {p["id"]: _poly(p) for p in pieces}
    areas = [p for p in pieces if p.get("piece_class") == "area"]
    group_of = build_area_group_map(pieces)

    def add(check, piece_id, msg, **extra):
        f = {"layout": name, "check": check, "piece": piece_id, "message": msg}
        f.update(extra)
        findings.append(f)

    def touching_areas(fid):
        out = []
        for a in areas:
            gap = poly_distance(polys[fid], polys[a["id"]])
            if gap <= ABUT_TOL:
                out.append((a["id"], overlap_fraction(polys[fid], polys[a["id"]]), gap))
        out.sort(key=lambda t: (-t[1], t[2], t[0]))
        return out

    for p in pieces:
        if p.get("piece_class") != "feature":
            continue
        fid = p["id"]
        parent_id = p.get("parent_area_id")
        if not parent_id:
            touch = touching_areas(fid)
            if touch and touch[0][1] >= MAJORITY:
                add("parentless-inside", fid,
                    "no parent_area_id but %.0f%% inside %s (engine: own 13.01 area %s)"
                    % (touch[0][1] * 100, touch[0][0], group_of[fid]), area=touch[0][0])
            continue
        parent = by_id.get(parent_id)
        if parent is None:
            add("parent-missing", fid, "parent_area_id %r names no piece" % parent_id)
            continue
        if parent.get("piece_class") != "area":
            add("parent-not-area", fid, "parent %s is piece_class %r" % (parent_id, parent.get("piece_class")))
        gap = poly_distance(polys[fid], polys[parent_id])
        frac = overlap_fraction(polys[fid], polys[parent_id])
        c_in = point_in_poly(centroid(polys[fid]), polys[parent_id])
        touch = touching_areas(fid)
        best = touch[0] if touch else None
        if gap > ABUT_TOL:
            mirror_twin = poly_distance(point_mirror(polys[fid]), polys[parent_id]) <= ABUT_TOL
            where = ("%s (%.0f%% of its footprint)" % (best[0], best[1] * 100)) if best else "no area"
            add("parent-far", fid,
                "parent %s is %.2f\" away; the feature sits in %s; point-mirror of the feature %s the declared parent"
                % (parent_id, gap, where, "HITS" if mirror_twin else "misses"),
                parent=parent_id, gap_in=round(gap, 3), sits_in=best[0] if best else None,
                sits_in_fraction=round(best[1], 3) if best else 0.0, point_mirror_twin=mirror_twin)
            if best and best[1] >= MAJORITY and (len(touch) == 1 or touch[1][1] < best[1]):
                sugg["reparent"][fid] = best[0]
        elif (not c_in) or frac < MAJORITY:
            same = bool(best) and group_of.get(best[0]) == group_of.get(parent_id)
            add("parent-minority", fid,
                "touches parent %s but only %.0f%% inside (centroid %s); %.0f%% in %s -- %s"
                % (parent_id, frac * 100, "inside" if c_in else "outside",
                   best[1] * 100 if best else 0, best[0] if best else "-",
                   "same engine group (no behavioural effect)" if same else "DIFFERENT engine group"),
                parent=parent_id, parent_fraction=round(frac, 3), majority_area=best[0] if best else None,
                same_group=same)
        if p.get("link_group") and parent is not None and group_of[fid] != resolve_group_key(parent, by_id):
            add("link-overrides-parent", fid,
                "link_group %r puts it in %s, its parent %s resolves to %s"
                % (p["link_group"], group_of[fid], parent_id, resolve_group_key(parent, by_id)))

    # link_group labels: one connected cluster per label
    labels = {}
    for p in pieces:
        if p.get("link_group"):
            labels.setdefault(str(p["link_group"]), []).append(p["id"])
    used = set(labels)
    for lab, ids in labels.items():
        comps = clusters(ids, polys)
        if len(comps) > 1:
            gaps = [min(poly_distance(polys[a], polys[b]) for a in comps[0] for b in c) for c in comps[1:]]
            twin = all(any(poly_distance(point_mirror(polys[a]), polys[b]) <= ABUT_TOL
                           for b in [x for c in comps[1:] for x in c]) for a in comps[0])
            add("link-split", ",".join(ids),
                "link_group %r spans %d separate clusters %s (gaps %s\"); %s"
                % (lab, len(comps), comps, [round(g, 2) for g in gaps],
                   "clusters are point-mirror twins" if twin else "not a simple point-mirror pair"),
                label=lab, clusters=comps, point_mirror_twins=twin)
            k = 2
            for comp in comps[1:]:
                while "%s#%d" % (lab, k) in used:
                    k += 1
                new = "%s#%d" % (lab, k)
                used.add(new)
                for pid in comp:
                    sugg["relabel"][pid] = new
                k += 1

    # engine groups: one connected cluster per group key
    members = {}
    for pid, key in group_of.items():
        members.setdefault(key, []).append(pid)
    for key, ids in members.items():
        comps = clusters(ids, polys)
        if len(comps) > 1:
            gaps = [min(poly_distance(polys[a], polys[b]) for a in comps[0] for b in c) for c in comps[1:]]
            add("group-split", key,
                "engine group %s is %d disconnected pieces-sets %s (gaps %s\")"
                % (key, len(comps), comps, [round(g, 2) for g in gaps]), group=key, clusters=comps)

    # area aggregates (generator rule)
    kids = {}
    for p in pieces:
        if p.get("piece_class") == "feature" and p.get("parent_area_id"):
            kids.setdefault(p["parent_area_id"], []).append(p)
    for a in areas:
        want = area_aggregate(a, kids.get(a["id"], []))
        diff = {k: (a.get(k), v) for k, v in want.items() if a.get(k) != v}
        if diff:
            add("area-aggregate", a["id"],
                "derived fields disagree with its parented features: %s"
                % ", ".join("%s %r -> %r" % (k, v[0], v[1]) for k, v in sorted(diff.items())),
                diff={k: list(v) for k, v in diff.items()})
    return findings, sugg


def apply_fix(path, data, sugg):
    """Mutates `data` per suggestions + re-derives aggregates. Returns change log."""
    log = []
    pieces = data.get("pieces", [])
    by_id = {p.get("id"): p for p in pieces}
    touched_areas = set()
    for fid, new_parent in sorted(sugg["reparent"].items()):
        p = by_id[fid]
        old = p.get("parent_area_id")
        p["parent_area_id"] = new_parent
        touched_areas.update([old, new_parent])
        log.append("%s: %s parent_area_id %s -> %s" % (os.path.basename(path), fid, old, new_parent))
    for pid, new_label in sorted(sugg["relabel"].items()):
        p = by_id[pid]
        log.append("%s: %s link_group %r -> %r" % (os.path.basename(path), pid, p.get("link_group"), new_label))
        p["link_group"] = new_label
    kids = {}
    for p in pieces:
        if p.get("piece_class") == "feature" and p.get("parent_area_id"):
            kids.setdefault(p["parent_area_id"], []).append(p)
    for aid in sorted(a for a in touched_areas if a in by_id):
        a = by_id[aid]
        if a.get("piece_class") != "area":
            continue
        want = area_aggregate(a, kids.get(aid, []))
        for k, v in want.items():
            if a.get(k) != v:
                log.append("%s: %s %s %r -> %r (re-derived from its features)" % (os.path.basename(path), aid, k, a.get(k), v))
                a[k] = v
    return log


def dumps(data):
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--layouts-dir", default=DEFAULT_DIR)
    ap.add_argument("--only", action="append", default=[], help="layout id (file stem); repeatable")
    ap.add_argument("--strict", action="store_true", help="parent-minority findings fail too")
    ap.add_argument("--json", metavar="PATH", help="write all findings as JSON")
    ap.add_argument("--fix", action="store_true", help="repair parent-far / link-split / aggregates in place")
    ap.add_argument("--quiet", action="store_true", help="summary only")
    args = ap.parse_args(argv)

    files = sorted(glob.glob(os.path.join(args.layouts_dir, "*.json")))
    files = [f for f in files if os.path.basename(f) != "index_11e.json"]
    if args.only:
        files = [f for f in files if os.path.basename(f)[:-5] in args.only]
    if not files:
        print("no layout files found under %s" % args.layouts_dir)
        return 2

    fix_log = []
    if args.fix:
        for path in files:
            text = open(path, encoding="utf-8").read()
            data = json.loads(text)
            _, sugg = check_layout(os.path.basename(path)[:-5], data)
            if not sugg["reparent"] and not sugg["relabel"]:
                continue
            if dumps(data) != text:
                print("REFUSING to rewrite %s: it does not round-trip byte-identically" % path)
                continue
            fix_log += apply_fix(path, data, sugg)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(dumps(data))
        print("--fix applied %d change(s):" % len(fix_log))
        for line in fix_log:
            print("  " + line)
        print()

    all_findings = []
    for path in files:
        data = json.load(open(path, encoding="utf-8"))
        f, _ = check_layout(os.path.basename(path)[:-5], data)
        all_findings += f

    def tally(checks):
        sel = [f for f in all_findings if f["check"] in checks]
        return len(sel), len({f["layout"] for f in sel})

    errors = [f for f in all_findings if f["check"] in ERROR_CHECKS or (args.strict and f["check"] == "parent-minority")]
    if not args.quiet:
        for f in all_findings:
            level = "ERROR" if f in errors else "info "
            print("%s %-18s %-38s %-34s %s" % (level, f["check"], f["layout"], f["piece"][:34], f["message"]))
        print()
    n_loose, l_loose = tally(("parent-far",))
    n_strict, l_strict = tally(("parent-far", "parent-minority"))
    same = [f for f in all_findings if f["check"] == "parent-minority" and f.get("same_group")]
    print("checked %d layout file(s) in %s" % (len(files), os.path.relpath(args.layouts_dir, os.getcwd())))
    print("  LOOSE  parent-far (feature >%.1f\" from its parent): %d feature(s) in %d layout(s)" % (ABUT_TOL, n_loose, l_loose))
    print("  STRICT parent-far + parent-minority (centroid outside / <50%% inside parent): %d feature(s) in %d layout(s)"
          " -- %d of the minority cases share the engine group of the area holding them" % (n_strict, l_strict, len(same)))
    for chk in ("parent-missing", "parent-not-area", "link-split", "group-split", "area-aggregate",
                "parentless-inside", "link-overrides-parent"):
        n, l = tally((chk,))
        print("  %-22s %d finding(s) in %d layout(s)" % (chk, n, l))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"findings": all_findings, "fix_log": fix_log}, fh, indent=1)
    print("RESULT: %s (%d error(s))" % ("FAIL" if errors else "PASS", len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
