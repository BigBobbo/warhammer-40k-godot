#!/usr/bin/env python3
"""M0 — validate a benchmark fixture BEFORE anything is learned on it.

Why this exists
---------------
Every AI baseline in `40k/tests/bench_baselines/` predating 2026-08-06 was
tuned on `audit_baseline_postdeploy`, which contained an army-list *header row*
imported as a unit: id U_STRIKE_FORCE_A, name "Strike Force",
keywords ["UNKNOWN"], null abilities/weapons/composition, one 1-wound T4
model — and `points: 2000`, which is the ARMY total, not a unit cost.

The damage was not cosmetic:
  * GameState.get_total_army_points() read the Ork army as 3840 instead of
    1840, so the 50% Strategic Reserves cap (11e 20.01) became 1920 instead
    of 920 — that fixture ends up with 69% of the Ork army in reserve and
    only 570 pts on the board.
  * AIDecisionMaker._calculate_target_value adds points * MACRO_POINTS_WEIGHT,
    so the phantom scored +16.0 against a Boyz mob's +0.64 — the enemy AI was
    drawn to shooting a 1-wound placeholder.

A learning loop pointed at a broken environment will confidently learn
garbage, fast, and the garbage will look like progress. So: no campaign runs
against a fixture that has not passed this check, and the fixture's sha256
goes into every game record (see AIBenchmarkRunner._build_provenance).

This generalises `make_mirror_fixture.validate()` — which only knows how to
check a freshly-built mirror — into a standalone gate that runs against any
fixture, any time, without rebuilding it.

Usage
-----
    python3 tools/ai_lab/fixture_check.py                       # all fixtures in 40k/tests/saves
    python3 tools/ai_lab/fixture_check.py mirror_orks_postdeploy
    python3 tools/ai_lab/fixture_check.py path/to/x.w40ksave --json
    python3 tools/ai_lab/fixture_check.py --bench-only          # only the fixtures campaigns use

Exit code 0 = every checked fixture passed, 1 = at least one FAILED.
Warnings alone do not fail the run unless --strict is given.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SAVES = os.path.join(REPO, "40k", "tests", "saves")

PX_PER_INCH = 40.0
STATUS_IN_RESERVES = 7  # GameState.UnitStatus.IN_RESERVES (autoloads/GameState.gd:17)
STATUS_UNDEPLOYED = 0   # GameState.UnitStatus.UNDEPLOYED
PHASE_DEPLOYMENT = 1    # GameState.Phase.DEPLOYMENT (autoloads/GameState.gd:16)

# No single 11e datasheet in this project's army files costs this much. A unit
# above it is almost certainly an army-list header row, not a datasheet.
MAX_PLAUSIBLE_UNIT_POINTS = 800

# Fixtures a learning campaign is allowed to run on. Deliberately just the
# mirrors: they remove the army/points asymmetry BY CONSTRUCTION, which is what
# makes an A/A test meaningful.
#
# The `_2000_` fixtures are the current default. 40k is balanced at 2000 points
# and that is what the game is designed to be played at, so a lab whose every
# number came from 1335- and 1840-point armies was measuring a format nobody
# plays. These are built by `40k/tests/make_2000pt_fixture.gd` from the SHIPPED
# army lists — `custodes_lions` (Lions of the Emperor) and `recon_stomps`
# (Speedwaaagh!) — through the game's own ArmyListManager, so the units are
# exactly the ones a player gets from the army picker.
#
# `_predeploy` variants start at Phase.DEPLOYMENT with nothing on the table, so
# the AI plays the deployment phase itself instead of inheriting a placement it
# did not choose. `_postdeploy` variants start at round 1 Command with both
# armies packed into their zones, which removes deployment variance and is the
# lower-noise choice for A/B work on the phases after it.
#
# `audit_baseline_postdeploy` is NOT here and must not be added. It is the
# fixture every pre-2026-08-06 baseline was tuned on and it still carries the
# U_STRIKE_FORCE_A placeholder (run this script with --all to see it fail).
# It is kept in the repo because scenario tests reference it, not because it is
# fit to learn on.
CAMPAIGN_FIXTURES = [
    "mirror_custodes_2000_predeploy",
    "mirror_orks_2000_predeploy",
    "mirror_custodes_2000_postdeploy",
    "mirror_orks_2000_postdeploy",
    # Retained: the 2026-08 frozen baseline's A/A numbers were measured on
    # these, so they stay checkable until that freeze is superseded.
    "mirror_orks_postdeploy",
    "mirror_custodes_postdeploy",
]


class Report:
    """Errors fail the fixture; warnings are advisory unless --strict."""

    def __init__(self, name: str, path: str):
        self.name = name
        self.path = path
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.info: dict = {}

    def err(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors

    def as_dict(self) -> dict:
        return {
            "fixture": self.name,
            "path": self.path,
            "ok": self.ok,
            "errors": self.errors,
            "warnings": self.warnings,
            **self.info,
        }


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


_B64_RE = re.compile(r"^[A-Za-z0-9+/]+=*$")


def load_save(path: str) -> dict:
    """Read a .w40ksave, transparently handling the compressed form.

    `StateSerializer.save_game` gzips + base64s any payload at or above
    `COMPRESSION_SIZE_THRESHOLD` (50 KB) and writes the base64 text straight
    into the file with no header or marker — exactly as
    `StateSerializer._compress_json` produces it. Every 2000-point fixture is
    over that threshold, and several older fixtures in `40k/tests/saves/` are
    too, so a plain `json.load` fails on them with a bare "Expecting value:
    line 1 column 1" that reads like a corrupt file rather than a compressed
    one. Detection mirrors `StateSerializer._is_compressed`: base64 alphabet
    end to end, length a multiple of 4.
    """
    with open(path, "rb") as fh:
        raw = fh.read()
    text = raw.decode("utf-8", errors="replace").strip()
    if text and _B64_RE.match(text) and len(text) % 4 == 0:
        try:
            return json.loads(gzip.decompress(base64.b64decode(text)).decode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            raise ValueError("looked base64/gzip compressed but did not decode: %s" % exc)
    return json.loads(text)


def parse_point(p):
    """Positions come in two serializations across the fixture corpus.

    Newer saves store {"x": .., "y": ..}; older ones store Godot's Vector2
    `str()` form, "(400.0, 300.0)". Both are valid saves the engine loads, so
    the validator must read both rather than crashing on the older ones.
    Returns (x, y) floats, or None if unparseable/absent.
    """
    if p is None:
        return None
    if isinstance(p, dict):
        try:
            return float(p["x"]), float(p["y"])
        except (KeyError, TypeError, ValueError):
            return None
    if isinstance(p, str):
        try:
            x, y = p.strip().lstrip("(").rstrip(")").split(",")
            return float(x), float(y)
        except (ValueError, AttributeError):
            return None
    if isinstance(p, (list, tuple)) and len(p) >= 2:
        try:
            return float(p[0]), float(p[1])
        except (TypeError, ValueError):
            return None
    return None


def _meta(unit: dict) -> dict:
    return unit.get("meta") or {}


def _keywords(unit: dict) -> list:
    return _meta(unit).get("keywords") or []


def _points(unit: dict) -> int:
    try:
        return int(_meta(unit).get("points", 0) or 0)
    except (TypeError, ValueError):
        return 0


def _alive_models(unit: dict) -> list:
    return [m for m in (unit.get("models") or []) if m.get("alive", True)]


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

def check_placeholders(units: dict, rep: Report) -> None:
    """The exact class of corruption that invalidated the historical baselines."""
    for uid, u in units.items():
        m = _meta(u)
        reasons = []
        if "UNKNOWN" in _keywords(u):
            reasons.append('keywords contain "UNKNOWN"')
        if m.get("weapons") is None and m.get("unit_composition") is None:
            reasons.append("null weapons AND null unit_composition")
        if _points(u) > MAX_PLAUSIBLE_UNIT_POINTS:
            reasons.append("points=%d exceeds any real datasheet (>%d)"
                           % (_points(u), MAX_PLAUSIBLE_UNIT_POINTS))
        if reasons:
            rep.err("%s (%r): looks like an army-list header row, not a datasheet — %s"
                    % (uid, m.get("name", "?"), "; ".join(reasons)))


def check_structure(units: dict, rep: Report) -> None:
    for uid, u in units.items():
        owner = int(u.get("owner", 0) or 0)
        if owner not in (1, 2):
            rep.err("%s: owner=%r is not 1 or 2" % (uid, u.get("owner")))
        if u.get("id") and u["id"] != uid:
            rep.err("%s: unit.id=%r disagrees with its key" % (uid, u["id"]))
        models = u.get("models") or []
        if not models:
            rep.err("%s: has no models" % uid)
        if _points(u) <= 0:
            rep.warn("%s (%r): points=0 — it contributes nothing to army totals "
                     "or to AI target valuation" % (uid, _meta(u).get("name", "?")))
        # dangling references
        for field in ("attached_to", "embarked_in"):
            ref = u.get(field)
            if ref and ref not in units:
                rep.err("%s: dangling %s -> %s" % (uid, field, ref))
        for c in (u.get("attachment_data") or {}).get("attached_characters", []) or []:
            if c not in units:
                rep.err("%s: dangling attached_character -> %s" % (uid, c))
        for c in (u.get("transport_data") or {}).get("embarked_units", []) or []:
            if c not in units:
                rep.err("%s: dangling embarked_unit -> %s" % (uid, c))


def check_positions(units: dict, rep: Report) -> None:
    """An alive, on-table model with no position breaks movement and coherency."""
    for uid, u in units.items():
        status = int(u.get("status", 0) or 0)
        if status == STATUS_IN_RESERVES:
            continue
        if u.get("embarked_in"):
            continue  # legitimately positionless — it is inside a transport
        missing = sum(1 for m in _alive_models(u) if parse_point(m.get("position")) is None)
        if missing:
            rep.err("%s: %d alive model(s) on the table with no position" % (uid, missing))


def check_predeploy(units: dict, rep: Report) -> None:
    """A fixture stopped at Phase.DEPLOYMENT: check status and position AGREE.

    `DeploymentPhase._get_undeployed_units_for_player` is what turns units into
    DEPLOY_UNIT actions, and it keys off `status == UNDEPLOYED`. Both halves of
    a mismatch are silent bugs, in opposite directions:

      * UNDEPLOYED but already positioned — the unit is offered for deployment
        again and re-placed, discarding whatever the fixture author set up;
      * DEPLOYED (or anything else) but positionless — no DEPLOY_UNIT action is
        ever emitted for it, nothing places it, and the unit sits out the whole
        game with no error raised anywhere.

    A *partially* deployed fixture is legitimate and deliberate — that is what
    `deployment_nearly_complete` exists to be — so this is a per-unit
    consistency check, not "nothing may be on the table". The split is recorded
    in `rep.info` so a fully-empty fixture stays distinguishable at a glance.
    """
    fully, empty, partial = 0, 0, 0
    for uid, u in units.items():
        status = int(u.get("status", 0) or 0)
        if status == STATUS_IN_RESERVES:
            continue
        if u.get("embarked_in"):
            continue  # positionless on purpose — inside a transport
        alive = _alive_models(u)
        if not alive:
            continue
        placed = sum(1 for m in alive if parse_point(m.get("position")) is not None)
        if placed == 0:
            empty += 1
            if status != STATUS_UNDEPLOYED:
                rep.err("%s: status=%d but no model has a position — DeploymentPhase "
                        "emits DEPLOY_UNIT only for UNDEPLOYED units, so nothing will "
                        "ever place this one and it sits out the game" % (uid, status))
        elif placed == len(alive):
            fully += 1
            if status == STATUS_UNDEPLOYED:
                rep.err("%s: fully positioned but still UNDEPLOYED — it will be offered "
                        "for deployment again and re-placed, discarding these positions"
                        % uid)
        else:
            partial += 1
            rep.err("%s: %d of %d alive models positioned — a half-placed unit is "
                    "neither deployable nor coherent" % (uid, placed, len(alive)))
    rep.info["deployment"] = {"deployed": fully, "undeployed": empty, "partial": partial}


def check_reserves_cap(units: dict, rep: Report) -> None:
    """11e 20.01: at most half an army's points may start in Strategic Reserves.

    The corrupt fixture broke this silently — the phantom's 2000 pts doubled
    the denominator, so a 69%-in-reserve army passed. Check it against the
    points that are actually on datasheets.
    """
    for player in (1, 2):
        owned = [u for u in units.values() if int(u.get("owner", 0) or 0) == player]
        total = sum(_points(u) for u in owned)
        reserved = sum(_points(u) for u in owned
                       if int(u.get("status", 0) or 0) == STATUS_IN_RESERVES)
        if total <= 0:
            rep.err("P%d: army totals 0 points" % player)
            continue
        pct = 100.0 * reserved / total
        rep.info.setdefault("armies", {})[str(player)] = {
            "units": len(owned), "points": total,
            "reserved_points": reserved, "reserved_pct": round(pct, 1),
        }
        if reserved * 2 > total:
            rep.err("P%d: %d/%d pts (%.0f%%) in Strategic Reserves — over the 11e 20.01 "
                    "50%% cap" % (player, reserved, total, pct))
        elif pct > 0:
            rep.warn("P%d: %.0f%% of the army starts in reserve; the AI plays a "
                     "different game from a fully-deployed fixture" % (player, pct))


def check_deployment_zones(d: dict, units: dict, rep: Report) -> None:
    zones = {}
    for z in (d.get("board") or {}).get("deployment_zones", []) or []:
        pts = [parse_point(p) for p in (z.get("poly") or [])]
        ys = [p[1] for p in pts if p is not None]
        if not ys:
            continue
        zones[int(z["player"])] = (min(ys) * PX_PER_INCH, max(ys) * PX_PER_INCH)
    if not zones:
        rep.warn("no usable deployment zones on the board — cannot check army placement")
        return
    for player, (lo, hi) in zones.items():
        out = 0
        for u in units.values():
            if int(u.get("owner", 0) or 0) != player:
                continue
            for m in _alive_models(u):
                p = parse_point(m.get("position"))
                if p and not (lo - 1 <= p[1] <= hi + 1):
                    out += 1
        if out:
            rep.warn("P%d: %d model(s) outside its own deployment zone y[%.0f,%.0f] "
                     "(expected for a mid-game fixture, suspicious for a post-deploy one)"
                     % (player, out, lo, hi))


def check_meta(d: dict, rep: Report) -> None:
    meta = d.get("meta") or {}
    rnd = int(meta.get("battle_round", 0) or 0)
    if rnd < 1:
        rep.err("meta.battle_round=%r (must be >= 1)" % meta.get("battle_round"))
    if int(meta.get("active_player", 0) or 0) not in (1, 2):
        rep.err("meta.active_player=%r is not 1 or 2" % meta.get("active_player"))
    rep.info["meta"] = {
        "battle_round": rnd,
        "phase": meta.get("phase"),
        "active_player": meta.get("active_player"),
        "first_turn_player": meta.get("first_turn_player"),
    }
    if not (d.get("board") or {}).get("objectives"):
        rep.err("board has no objectives — primary VP cannot be scored")


def army_signature(units: dict, player: int) -> list:
    sig = []
    for uid, u in units.items():
        if int(u.get("owner", 0) or 0) != player:
            continue
        sig.append((_meta(u).get("name", "?"), len(_alive_models(u)), _points(u)))
    return sorted(sig)


def check_mirror(d: dict, units: dict, rep: Report, positions: bool = True) -> None:
    """For a mirror fixture, both sides must be identical by construction.

    A mirror removes the army/points asymmetry rather than cancelling it
    arithmetically, which is what makes a real A/A test possible: same army,
    same AI both sides, so the expected margin is the first-turn advantage and
    nothing else. If A/A shows more than that, the harness moved, not the AI.
    """
    s1, s2 = army_signature(units, 1), army_signature(units, 2)
    if s1 != s2:
        rep.err("mirror: army composition differs between players")
        for a, b in zip(s1, s2):
            if a != b:
                rep.err("   P1 %s  vs  P2 %s" % (a, b))
        if len(s1) != len(s2):
            rep.err("   unit counts differ: P1=%d P2=%d" % (len(s1), len(s2)))
        return

    if not positions:
        return

    size = (d.get("board") or {}).get("size") or {}
    w_px = float(size.get("width", 0)) * PX_PER_INCH
    h_px = float(size.get("height", 0)) * PX_PER_INCH

    def posset(player):
        pts = []
        for u in units.values():
            if int(u.get("owner", 0) or 0) != player:
                continue
            for m in (u.get("models") or []):
                p = parse_point(m.get("position"))
                if p is not None:
                    pts.append((round(p[0], 1), round(p[1], 1)))
        return sorted(pts)

    p1, p2 = posset(1), posset(2)
    p1_rot = sorted((round(w_px - x, 1), round(h_px - y, 1)) for x, y in p1)
    if p1_rot != p2:
        rep.err("mirror: positions are not exact 180deg images "
                "(%d P1 models vs %d P2 models)" % (len(p1), len(p2)))


def looks_like_mirror(name: str, units: dict) -> bool:
    if name.startswith("mirror_"):
        return True
    return army_signature(units, 1) == army_signature(units, 2) and bool(units)


# ---------------------------------------------------------------------------

def check_fixture(path: str, strict: bool = False, mirror: bool | None = None) -> Report:
    name = os.path.basename(path).replace(".w40ksave", "")
    rep = Report(name, path)
    try:
        d = load_save(path)
    except Exception as exc:  # noqa: BLE001 — an unparseable fixture is just a failure
        rep.err("could not parse: %s" % exc)
        return rep

    rep.info["sha256"] = sha256_of(path)
    units = d.get("units") or {}
    if not units:
        rep.err("no units in fixture")
        return rep

    # A fixture that starts at Deployment has not placed anything yet, so the
    # placement invariants are inverted rather than absent. Detect the mode from
    # meta.phase rather than from the filename — the phase is what the runner
    # actually reads (AIBenchmarkRunner reads meta.phase to pick its start
    # phase), so keying off it means the check and the run cannot disagree.
    predeploy = int((d.get("meta") or {}).get("phase", -1) or -1) == PHASE_DEPLOYMENT
    rep.info["predeploy"] = predeploy

    check_placeholders(units, rep)
    check_structure(units, rep)
    if predeploy:
        check_predeploy(units, rep)
    else:
        check_positions(units, rep)
        check_deployment_zones(d, units, rep)
    check_reserves_cap(units, rep)
    check_meta(d, rep)

    is_mirror = looks_like_mirror(name, units) if mirror is None else mirror
    rep.info["mirror"] = is_mirror
    if is_mirror:
        # Position mirroring is meaningless before anything is placed; the army
        # signatures still have to match, and check_mirror tests that first.
        check_mirror(d, units, rep, positions=not predeploy)

    if strict and rep.warnings:
        rep.errors.extend("(strict) " + w for w in rep.warnings)
        rep.warnings = []
    return rep


def resolve(target: str) -> str:
    if os.path.isfile(target):
        return target
    for cand in (os.path.join(SAVES, target),
                 os.path.join(SAVES, target + ".w40ksave")):
        if os.path.isfile(cand):
            return cand
    raise SystemExit("fixture not found: %s (looked in %s)" % (target, SAVES))


def print_report(rep: Report) -> None:
    status = "PASS" if rep.ok else "FAIL"
    print("[%s] %s%s" % (status, rep.name, "  (mirror)" if rep.info.get("mirror") else ""))
    for player, a in sorted((rep.info.get("armies") or {}).items()):
        print("   P%s: %d units, %d pts, %d pts (%.0f%%) in reserve"
              % (player, a["units"], a["points"], a["reserved_points"], a["reserved_pct"]))
    m = rep.info.get("meta") or {}
    if m:
        print("   round=%s phase=%s active=P%s first_turn=P%s  sha256=%s"
              % (m.get("battle_round"), m.get("phase"), m.get("active_player"),
                 m.get("first_turn_player"), rep.info.get("sha256", "")[:12]))
    for e in rep.errors:
        print("   ERROR   %s" % e)
    for w in rep.warnings:
        print("   warning %s" % w)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("fixtures", nargs="*",
                    help="fixture names or paths (default: the campaign fixtures)")
    ap.add_argument("--all", action="store_true",
                    help="sweep every fixture in 40k/tests/saves. Many hand-authored "
                         "scenario fixtures legitimately fail these checks — this is a "
                         "survey, not a gate.")
    ap.add_argument("--strict", action="store_true", help="treat warnings as failures")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    ap.add_argument("--mirror", dest="mirror", action="store_true", default=None,
                    help="force mirror checks on")
    ap.add_argument("--no-mirror", dest="mirror", action="store_false",
                    help="force mirror checks off")
    args = ap.parse_args(argv)

    missing = []
    if args.fixtures:
        targets = [resolve(f) for f in args.fixtures]
    elif args.all:
        targets = sorted(os.path.join(SAVES, f) for f in os.listdir(SAVES)
                         if f.endswith(".w40ksave"))
    else:
        targets = []
        for f in CAMPAIGN_FIXTURES:
            try:
                targets.append(resolve(f))
            except SystemExit:
                missing.append(f)
                print("[MISSING] %s — build it with "
                      "`python3 40k/tests/make_mirror_fixture.py --source 1`" % f)

    reports = [check_fixture(p, strict=args.strict, mirror=args.mirror) for p in targets]

    if args.json:
        print(json.dumps([r.as_dict() for r in reports], indent=2))
    else:
        for rep in reports:
            print_report(rep)
        failed = [r.name for r in reports if not r.ok]
        print("\n%d fixture(s) checked, %d failed%s"
              % (len(reports), len(failed), (": " + ", ".join(failed)) if failed else ""))

    return 1 if (missing or any(not r.ok for r in reports)) else 0


if __name__ == "__main__":
    sys.exit(main())
