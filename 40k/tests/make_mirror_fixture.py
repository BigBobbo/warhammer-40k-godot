#!/usr/bin/env python3
"""Build a MIRROR-MATCH benchmark fixture: the same army on both sides.

Why: `audit_baseline_postdeploy` is Adeptus Custodes (1000 pts, P1) vs Orks
(2000 pts, P2) and P1 wins by ~44 VP. Any AI A/B run on it has to fight a
side bias fifty times the size of the effect under test.

A mirror match removes the army and points asymmetry BY CONSTRUCTION rather
than cancelling it arithmetically, which leaves only the first-turn advantage
(~19 VP at Hard on this board — see 2026-07-10_firstturn_swap.md). That in
turn makes a genuine A/A test possible: same army, same AI on both sides, so
the expected margin is the first-turn advantage and nothing else. If an A/A
run shows more than that, the harness — not the AI change — is what moved.

Method: keep the board, terrain, objectives and deployment zones exactly as
they are; delete P1's army; and give P1 a 180deg-rotated copy of P2's army.
The board's objective layout is already rotationally symmetric
(obj_home_2 maps onto obj_home_1), so the rotation lands cleanly.

Usage:
    python3 40k/tests/make_mirror_fixture.py            # Orks mirror (P2's army)
    python3 40k/tests/make_mirror_fixture.py --source 1 # Custodes mirror
"""
import argparse
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "saves", "audit_baseline_postdeploy.w40ksave")
PX_PER_INCH = 40.0
PREFIX = "MIR_"


def mirror_point(x, y, w_px, h_px):
    """180deg rotation about the board centre — the deployment-zone mirror."""
    return w_px - x, h_px - y


def remap(uid, keep):
    """New id for a copied unit; ids that are not units (None) pass through."""
    if uid is None or uid == "":
        return uid
    return PREFIX + uid if uid in keep else uid


def build(source_player: int, out_name: str) -> str:
    with open(SRC) as fh:
        d = json.load(fh)

    size = d["board"]["size"]
    w_px = float(size["width"]) * PX_PER_INCH
    h_px = float(size["height"]) * PX_PER_INCH
    other = 1 if source_player == 2 else 2

    units = d["units"]
    src_ids = [uid for uid, u in units.items() if int(u.get("owner", 0)) == source_player]
    drop_ids = [uid for uid, u in units.items() if int(u.get("owner", 0)) == other]
    if not src_ids:
        sys.exit(f"no units owned by player {source_player}")

    src_set = set(src_ids)

    # 1. remove the army being replaced
    for uid in drop_ids:
        del units[uid]

    # 2. add a rotated copy of the source army, owned by the other player
    for uid in src_ids:
        u = copy.deepcopy(units[uid])
        new_id = PREFIX + uid
        u["id"] = new_id
        u["owner"] = other
        if u.get("squad_id"):
            u["squad_id"] = remap(u["squad_id"], src_set)
        # cross-unit references must point at the COPIES, not the originals
        u["attached_to"] = remap(u.get("attached_to"), src_set)
        u["embarked_in"] = remap(u.get("embarked_in"), src_set)
        ad = u.get("attachment_data") or {}
        if isinstance(ad.get("attached_characters"), list):
            ad["attached_characters"] = [remap(c, src_set) for c in ad["attached_characters"]]
            u["attachment_data"] = ad
        td = u.get("transport_data") or {}
        if isinstance(td.get("embarked_units"), list):
            td["embarked_units"] = [remap(c, src_set) for c in td["embarked_units"]]
            u["transport_data"] = td
        # rotate every model
        for m in u.get("models", []):
            pos = m.get("position")
            if not pos:
                continue
            nx, ny = mirror_point(float(pos["x"]), float(pos["y"]), w_px, h_px)
            pos["x"], pos["y"] = nx, ny
            if "rotation" in m and m["rotation"] is not None:
                # a 180deg board rotation turns each model to face the other way
                m["rotation"] = float(m["rotation"]) + 3.141592653589793
        units[new_id] = u

    # 3. both players now field the same faction/detachment
    d["factions"][str(other)] = copy.deepcopy(d["factions"][str(source_player)])

    # 4. symmetric per-player state (identical secondary decks, CP, VP)
    if "secondary_missions" in d and "player_state" in d["secondary_missions"]:
        ps = d["secondary_missions"]["player_state"]
        if str(source_player) in ps:
            ps[str(other)] = copy.deepcopy(ps[str(source_player)])
    if "players" in d:
        d["players"][str(other)] = copy.deepcopy(d["players"][str(source_player)])

    # 5. history/log refer to units that no longer exist
    d["history"] = []
    d["phase_log"] = []
    d["unit_visuals"] = {}

    out_path = os.path.join(HERE, "saves", out_name + ".w40ksave")
    with open(out_path, "w") as fh:
        json.dump(d, fh, indent="\t", sort_keys=True)
    return out_path


def validate(path, source_player):
    with open(path) as fh:
        d = json.load(fh)
    units = d["units"]
    size = d["board"]["size"]
    w_px = float(size["width"]) * PX_PER_INCH
    h_px = float(size["height"]) * PX_PER_INCH

    by_owner = {1: [], 2: []}
    for uid, u in units.items():
        by_owner.setdefault(int(u.get("owner", 0)), []).append(uid)

    errs = []
    if len(by_owner[1]) != len(by_owner[2]):
        errs.append(f"unit counts differ: P1={len(by_owner[1])} P2={len(by_owner[2])}")

    def army_signature(ids):
        sig = []
        for uid in ids:
            u = units[uid]
            alive = sum(1 for m in u.get("models", []) if m.get("alive", True))
            sig.append((u["meta"]["name"], alive, int(u["meta"].get("points", 0))))
        return sorted(sig)

    s1, s2 = army_signature(by_owner[1]), army_signature(by_owner[2])
    if s1 != s2:
        errs.append("army composition differs between players")
        for a, b in zip(s1, s2):
            if a != b:
                errs.append(f"   {a}  vs  {b}")

    pts1 = sum(x[2] for x in s1)
    pts2 = sum(x[2] for x in s2)

    # every reference must resolve
    for uid, u in units.items():
        for ref in [u.get("attached_to"), u.get("embarked_in")]:
            if ref and ref not in units:
                errs.append(f"{uid}: dangling reference {ref}")
        for c in (u.get("attachment_data") or {}).get("attached_characters", []) or []:
            if c not in units:
                errs.append(f"{uid}: dangling attached_character {c}")
        for c in (u.get("transport_data") or {}).get("embarked_units", []) or []:
            if c not in units:
                errs.append(f"{uid}: dangling embarked_unit {c}")

    # deployment zones: each army must sit in its own half
    zones = {}
    for z in d["board"]["deployment_zones"]:
        ys = [p["y"] for p in z["poly"]]
        zones[int(z["player"])] = (min(ys) * PX_PER_INCH, max(ys) * PX_PER_INCH)
    for owner, ids in by_owner.items():
        if owner not in zones:
            continue
        lo, hi = zones[owner]
        out = 0
        for uid in ids:
            for m in units[uid].get("models", []):
                p = m.get("position")
                if p and not (lo - 1 <= float(p["y"]) <= hi + 1):
                    out += 1
        if out:
            errs.append(f"P{owner}: {out} models outside its deployment zone y[{lo:.0f},{hi:.0f}]")

    # positions must be exact 180deg images of each other
    def posset(ids):
        return sorted((round(float(m["position"]["x"]), 1), round(float(m["position"]["y"]), 1))
                      for uid in ids for m in units[uid].get("models", [])
                      if m.get("position"))
    p_src = posset(by_owner[source_player])
    p_new = posset(by_owner[1 if source_player == 2 else 2])
    p_src_rot = sorted((round(w_px - x, 1), round(h_px - y, 1)) for x, y in p_src)
    if p_src_rot != p_new:
        errs.append(f"positions are not exact 180deg images ({len(p_src)} vs {len(p_new)} models)")

    print(f"  P1 units {len(by_owner[1])} ({pts1} pts) | P2 units {len(by_owner[2])} ({pts2} pts)")
    print(f"  factions: P1={d['factions']['1']['name']}/{d['factions']['1']['detachment']}"
          f"  P2={d['factions']['2']['name']}/{d['factions']['2']['detachment']}")
    print(f"  first_turn_player={d['meta'].get('first_turn_player')} "
          f"active_player={d['meta'].get('active_player')} phase={d['meta'].get('phase')}")
    if errs:
        print("  VALIDATION FAILED:")
        for e in errs:
            print("   -", e)
        return False
    print("  validation OK — identical armies, mirrored positions, no dangling refs")
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=int, default=2, choices=(1, 2),
                    help="which player's army to mirror onto both sides (default 2 = Orks)")
    ap.add_argument("--name", default=None)
    args = ap.parse_args()
    name = args.name or ("mirror_orks_postdeploy" if args.source == 2 else "mirror_custodes_postdeploy")
    path = build(args.source, name)
    print(f"wrote {path}")
    ok = validate(path, args.source)
    sys.exit(0 if ok else 1)
