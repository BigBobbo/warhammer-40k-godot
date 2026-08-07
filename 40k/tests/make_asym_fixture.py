#!/usr/bin/env python3
"""B2 — build the ASYMMETRIC benchmark fixture: Custodes vs Orks, post-deploy.

Two mirrors exist, and they do a job nothing else can: they remove the army
asymmetry by construction, so a paired A/B isolates the candidate and nothing
else. What they cannot do is detect **matchup overfitting**. A change that
helps Orks fight Orks may lose to Custodes, and a mirror will never say so —
both sides get the change, so a bias that only appears against a different
army is invisible by construction. `gate_candidate.py` already wants a
>= 2-matchup grid; this gives it a real asymmetric matchup instead of two
views of the same one.

Method, deliberately boring: take the Custodes mirror, delete P2's mirrored
Custodes, and paste in the Ork army from the Ork mirror's P2 side. Both
fixtures descend from the same source save, so the board, terrain, objectives
and deployment zones are identical and the Ork models are already deployed in
the P2 half. Nothing is repositioned, so neither army's deployment is
second-guessed by this script.

The armies are NOT equal on points (Custodes 1335, Orks 1840) and are not
meant to be — that is the shipped matchup, and equalising it would invent a
list no player fields. The resulting structural bias F is measured by an A/A
run and reported; `run_paired.py` cancels F by side-swapping, which is exactly
why F being large is not a problem as long as it is KNOWN.

Usage:
    python3 40k/tests/make_asym_fixture.py
    python3 tools/ai_lab/fixture_check.py asym_orks_vs_custodes_postdeploy
"""
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SAVES = os.path.join(HERE, "saves")
BASE = os.path.join(SAVES, "mirror_custodes_postdeploy.w40ksave")
DONOR = os.path.join(SAVES, "mirror_orks_postdeploy.w40ksave")
OUT_NAME = "asym_orks_vs_custodes_postdeploy"


def load(path):
    with open(path) as fh:
        return json.load(fh)


def build() -> str:
    base = load(BASE)
    donor = load(DONOR)

    if base["board"]["size"] != donor["board"]["size"]:
        sys.exit("the two mirrors disagree about the board size — refusing to splice them")

    units = base["units"]
    drop = [uid for uid, u in units.items() if int(u.get("owner", 0)) == 2]
    for uid in drop:
        del units[uid]
    print("  removed %d mirrored Custodes unit(s) from P2" % len(drop))

    donor_ids = [uid for uid, u in donor["units"].items() if int(u.get("owner", 0)) == 2]
    if not donor_ids:
        sys.exit("the Ork mirror has no P2 units")
    for uid in donor_ids:
        if uid in units:
            sys.exit("id collision between the two mirrors: %s" % uid)
        units[uid] = copy.deepcopy(donor["units"][uid])
    print("  added %d Ork unit(s) as P2" % len(donor_ids))

    # P2's faction, detachment and per-player state come with the army.
    base["factions"]["2"] = copy.deepcopy(donor["factions"]["2"])
    if "secondary_missions" in base and "player_state" in base["secondary_missions"]:
        ps = base["secondary_missions"]["player_state"]
        if "2" in donor.get("secondary_missions", {}).get("player_state", {}):
            ps["2"] = copy.deepcopy(donor["secondary_missions"]["player_state"]["2"])
    if "players" in base and "2" in donor.get("players", {}):
        base["players"]["2"] = copy.deepcopy(donor["players"]["2"])

    # History and visuals refer to units that no longer exist here.
    base["history"] = []
    base["phase_log"] = []
    base["unit_visuals"] = {}

    out = os.path.join(SAVES, OUT_NAME + ".w40ksave")
    with open(out, "w") as fh:
        json.dump(base, fh, indent="\t", sort_keys=True)
    return out


def validate(path) -> int:
    d = load(path)
    units = d["units"]
    errs = []
    per = {1: [], 2: []}
    for uid, u in units.items():
        per.setdefault(int(u.get("owner", 0)), []).append(uid)
        if "UNKNOWN" in ((u.get("meta") or {}).get("keywords") or []):
            errs.append("%s: placeholder unit survived into the fixture" % uid)
        if int(u.get("status", 0)) == 7:
            errs.append("%s: still IN_RESERVES — this fixture starts fully deployed" % uid)
        for m in u.get("models", []):
            if m.get("alive", True) and not m.get("position"):
                errs.append("%s: alive model with no position" % uid)
        for ref in (u.get("attached_to"), u.get("embarked_in")):
            if ref and ref not in units:
                errs.append("%s: dangling reference %s" % (uid, ref))
        for c in (u.get("attachment_data") or {}).get("attached_characters", []) or []:
            if c not in units:
                errs.append("%s: dangling attached_character %s" % (uid, c))
        for c in (u.get("transport_data") or {}).get("embarked_units", []) or []:
            if c not in units:
                errs.append("%s: dangling embarked_unit %s" % (uid, c))

    # Each army must still sit in its own half — the splice must not have put
    # the Orks on top of the Custodes.
    h_px = float(d["board"]["size"]["height"]) * 40.0
    for owner, ids in per.items():
        if owner not in (1, 2):
            continue
        for uid in ids:
            for m in units[uid].get("models", []):
                p = m.get("position")
                if not p:
                    continue
                y = float(p["y"])
                if owner == 1 and y > h_px * 0.5:
                    errs.append("%s: P1 model in P2's half (y=%.0f)" % (uid, y))
                if owner == 2 and y < h_px * 0.5:
                    errs.append("%s: P2 model in P1's half (y=%.0f)" % (uid, y))

    for owner in (1, 2):
        pts = sum(int(units[u]["meta"].get("points", 0)) for u in per[owner])
        names = sorted({units[u]["meta"].get("name", "?") for u in per[owner]})
        print("  P%d: %d units, %d pts — %s" % (owner, len(per[owner]), pts, ", ".join(names[:4]) + ("..." if len(names) > 4 else "")))

    for e in errs:
        print("  ERROR %s" % e)
    return len(errs)


if __name__ == "__main__":
    path = build()
    n = validate(path)
    print("\nwrote %s" % os.path.relpath(path, os.path.dirname(HERE)))
    if n:
        print("VALIDATION FAILED (%d problem(s))" % n)
        raise SystemExit(1)
    print("validation passed — now run tools/ai_lab/fixture_check.py %s" % OUT_NAME)
