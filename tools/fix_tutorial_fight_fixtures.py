#!/usr/bin/env python3
"""Repair the melee geometry baked into the T5/T6 tutorial checkpoint fixtures.

The tutorial checkpoints under ``40k/data/tutorials/fixtures/`` are hand-authored
``.w40ksave`` files (gzip + base64 JSON, exactly what ``StateSerializer`` writes).
Three authoring bugs shipped in the fight-phase checkpoints:

1. The Custodian Guard were laid out on a 60px pitch. A 40mm base is
   ``40 / 25.4 * 40 = 62.99px`` across, so every adjacent pair of Custodians
   *overlapped* by ~3px. Visible in-game as intersecting base rings.

2. The Boyz were parked ~5-10px short of the Custodian line — inside 11e
   engagement range (2") but outside ``RulesEngine.BASE_CONTACT_TOLERANCE_INCHES``
   (0.1"), so the lesson's "Yer Boyz are already in contact" was false, and the
   two rear Boyz (m1/m9 at ~2.4") were outside engagement range entirely and
   could not fight at all.

3. ``U_WARBOSS_T`` carried ``status: UNDEPLOYED`` even though it is attached to
   the Boyz and has a board position. ``Main._recreate_unit_visuals()`` only
   builds tokens for ``status >= DEPLOYED``, so the Warboss was never drawn on
   the board in ANY tutorial lesson. The real deployment path
   (``DeploymentPhase.gd:761`` — "auto-deploy attached characters ... so they
   appear on the board") sets DEPLOYED, so the fixtures were simply wrong.

Rerun with ``python3 tools/fix_tutorial_fight_fixtures.py`` (idempotent — it
writes absolute positions, not deltas).
"""

import base64
import gzip
import json
import math
import os
import sys

PX_PER_INCH = 40.0
MM_PER_INCH = 25.4

FIXTURES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "40k", "data", "tutorials", "fixtures"
)

# GameState.UnitStatus
STATUS_DEPLOYED = 2

# Leave this much daylight between two bases we want to read as "in contact".
# 1px == 0.025", comfortably inside RulesEngine.BASE_CONTACT_TOLERANCE_INCHES
# (0.1") while never tripping Measurement.models_overlap().
CONTACT_GAP_PX = 1.0


def radius_px(base_mm):
    return (base_mm / MM_PER_INCH * PX_PER_INCH) / 2.0


R32 = radius_px(32.0)   # 25.197 — Boyz
R40 = radius_px(40.0)   # 31.496 — Warboss / Custodian Guard

# Centre-to-centre distances that put two bases in contact.
BOY_TO_CUSTODIAN = R32 + R40 + CONTACT_GAP_PX
WARBOSS_TO_CUSTODIAN = R40 + R40 + CONTACT_GAP_PX
BOY_TO_BOY = R32 + R32 + CONTACT_GAP_PX

# ── Custodian Guard line ───────────────────────────────────────────────
# Same rank (y=1400) and same left-hand anchor (x=840) the fixtures already
# used, re-pitched from 60px to 73px — the spacing the game itself produces
# (cf. the t4/t7 fixtures) and 10px clear of a base-on-base overlap.
#
# Anchoring on m1 rather than re-centring the line keeps m1 exactly where it
# was, which is what the T5 charge-range readout measures against (Boyz m10 ->
# Custodian m1 = 2.9"); tut_t5_ere_we_go_pad pins that string.
CUSTODES_Y = 1400.0
CUSTODES_PITCH = 73.0
CUSTODES_ANCHOR_X = 840.0
CUSTODES_X = [
    CUSTODES_ANCHOR_X + i * CUSTODES_PITCH for i in range(4)
]  # 840, 913, 986, 1059

FLANK_DEG = 60.0  # angle off vertical for the models that wrap the line's ends


def _flank(cx, cy, distance, degrees, to_the_right):
    rad = math.radians(degrees)
    dx = math.sin(rad) * distance * (1.0 if to_the_right else -1.0)
    dy = -math.cos(rad) * distance
    return (cx + dx, cy + dy)


def t6_ork_layout():
    """Post-charge positions for the Boyz + Warboss in the T6 checkpoint.

    Front rank hugs the Custodian line in base contact; the rear rank sits in
    base contact with the front rank (so it is both inside 2" engagement range
    and eligible via RulesEngine's base-contact chain rule).
    """
    c1x, c2x, c3x, c4x = CUSTODES_X
    front_y = CUSTODES_Y - BOY_TO_CUSTODIAN

    boyz = {
        # Front rank — every one of these touches a Custodian.
        "m1": _flank(c1x, CUSTODES_Y, BOY_TO_CUSTODIAN, FLANK_DEG, False),
        "m2": (c1x, front_y),
        "m3": (c2x, front_y),
        "m4": (c3x, front_y),
        "m5": (c4x, front_y),
    }
    # Rear rank — directly behind its front-rank model, bases touching.
    boyz["m6"] = (boyz["m1"][0], boyz["m1"][1] - BOY_TO_BOY)
    boyz["m7"] = (boyz["m2"][0], boyz["m2"][1] - BOY_TO_BOY)
    boyz["m8"] = (boyz["m3"][0], boyz["m3"][1] - BOY_TO_BOY)
    boyz["m9"] = (boyz["m4"][0], boyz["m4"][1] - BOY_TO_BOY)
    boyz["m10"] = (boyz["m5"][0], boyz["m5"][1] - BOY_TO_BOY)

    # Warboss wraps the right-hand end of the line, in base contact with C4.
    warboss = {"m1": _flank(c4x, CUSTODES_Y, WARBOSS_TO_CUSTODIAN, FLANK_DEG, True)}
    return boyz, warboss


# ── save file I/O ──────────────────────────────────────────────────────


def load_save(path):
    return json.loads(gzip.decompress(base64.b64decode(open(path, "rb").read().strip())))


def write_save(path, data):
    raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
    # mtime=0 so identical input produces an identical file (reproducible diffs).
    blob = gzip.compress(raw, compresslevel=9, mtime=0)
    with open(path, "wb") as fh:
        fh.write(base64.b64encode(blob))


def set_positions(save, unit_id, positions):
    unit = save["units"][unit_id]
    seen = set()
    for model in unit["models"]:
        mid = model.get("id")
        if mid in positions:
            x, y = positions[mid]
            model["position"] = {"x": round(x, 3), "y": round(y, 3)}
            seen.add(mid)
    missing = set(positions) - seen
    if missing:
        raise SystemExit("%s: no such models %s" % (unit_id, sorted(missing)))


def deploy_attached_characters(save):
    """Give every attached character that has a board position DEPLOYED status.

    Without this the token layer skips them entirely (Main.gd:9248)."""
    touched = []
    for uid, unit in save["units"].items():
        if not unit.get("attached_to"):
            continue
        if unit.get("embarked_in"):
            continue
        if not any(m.get("position") for m in unit.get("models", [])):
            continue
        if unit.get("status") != STATUS_DEPLOYED:
            unit["status"] = STATUS_DEPLOYED
            touched.append(uid)
    return touched


def fix_t6(save):
    boyz, warboss = t6_ork_layout()
    set_positions(save, "U_CUSTODIAN_GUARD_T", {
        "m%d" % (i + 1): (x, CUSTODES_Y) for i, x in enumerate(CUSTODES_X)
    })
    set_positions(save, "U_BOYZ_T", boyz)
    set_positions(save, "U_WARBOSS_T", warboss)
    return deploy_attached_characters(save)


def fix_t5(save):
    # Same Custodian line as T6 so the two checkpoints line up when the full
    # course chains T5 -> T6.
    set_positions(save, "U_CUSTODIAN_GUARD_T", {
        "m%d" % (i + 1): (x, CUSTODES_Y) for i, x in enumerate(CUSTODES_X)
    })
    # Pre-charge Warboss sat 56px from Boyz m10 — 0.7px inside its own base.
    set_positions(save, "U_WARBOSS_T", {"m1": (850.0, 1236.0)})
    return deploy_attached_characters(save)


def fix_status_only(save):
    return deploy_attached_characters(save)


JOBS = [
    ("tutorial_t4_shoot.w40ksave", fix_status_only),
    ("tutorial_t5_charge.w40ksave", fix_t5),
    ("tutorial_t6_fight.w40ksave", fix_t6),
    ("tutorial_t7_round2.w40ksave", fix_status_only),
]


def main():
    for name, fn in JOBS:
        path = os.path.normpath(os.path.join(FIXTURES, name))
        save = load_save(path)
        deployed = fn(save)
        write_save(path, save)
        note = (" (deployed: %s)" % ", ".join(deployed)) if deployed else ""
        print("patched %s%s" % (name, note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
