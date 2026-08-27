#!/usr/bin/env python3
"""The commander brain: builds a prompt from a board snapshot, asks an LLM
via `claude -p` for a directive, parses and sanitizes the result.

The engine consumes the directive as an earmarks-only plan through
AIDecisionMaker.set_player_plan(); semantics documented in the preamble
below match the implementation (AIDecisionMaker.gd PM-3 block): earmarks
are additive priors on the per-round unit->objective assignment, not
orders, and release automatically below 50% unit strength.
"""
import json
import re
import subprocess
import time

VALID_VERBS = {"HOLD_OBJECTIVE", "PUSH_CENTER", "HUNT_CHARACTERS", "SCREEN"}

PREAMBLE = """You are the strategic commander for Player {seat} in a Warhammer 40k \
match (custodes_lions mirror; both armies M5-6, elite, 11 units). Each battle \
round you issue standing orders consumed by a deterministic tactical AI.

Order semantics (exactly as the engine implements them):
- HOLD_OBJECTIVE (needs "target"): +8 assignment bias toward that objective.
- PUSH_CENTER: +6 bias toward the central objective(s): {central}.
- HUNT_CHARACTERS: +4 bias toward enemy CHARACTER units.
- SCREEN: withholds the unit from objective assignment entirely (rarely wise).
Orders are priors, not scripts: the tactical AI still weighs threats, \
distance and OC efficiency, and an order releases if the unit drops below \
half strength. One order per unit; units you omit are handled freely by the \
tactical AI (often fine). Orders persist until you change them next round.

Scoring (take_and_hold): at each player's command phase from round 2, VP for \
holding more objectives than the opponent, bracket caps at 3 held. Board is \
44x60 inches; Player 1's zone is the south (y<=18), Player 2's the north \
(y>=42). Your home objective is {home}; the enemy home is {enemy_home}. \
Games last 5 rounds. A unit moves ~6" per round; do not order slow units \
across the board late in the game.

Reply with ONLY a JSON object, no prose, no code fences:
{{"earmarks": [{{"unit": "<unit id from YOUR units>", "verb": "<verb>", \
"target": "<objective id, HOLD_OBJECTIVE only>"}}, ...], \
"reasoning": "<one sentence>"}}"""


def build_prompt(seat, snapshot, central_ids, history):
    home = "obj_home_1" if seat == 1 else "obj_home_2"
    enemy_home = "obj_home_2" if seat == 1 else "obj_home_1"
    pre = PREAMBLE.format(seat=seat, central=", ".join(central_ids) or "obj_center",
                          home=home, enemy_home=enemy_home)
    lines = [pre, "", f"== Board state (you are P{seat}) =="]
    lines.append(json.dumps(snapshot, separators=(",", ":")))
    if history:
        lines.append("")
        lines.append("== Your previous orders and VP trend ==")
        for h in history[-3:]:
            lines.append(json.dumps(h, separators=(",", ":")))
    lines.append("")
    lines.append("Issue this round's orders now. JSON only.")
    return "\n".join(lines)


def call_llm(prompt, model, timeout_s=60):
    t0 = time.time()
    try:
        proc = subprocess.run(
            ["claude", "-p", "--model", model],
            input=prompt.encode(), capture_output=True, timeout=timeout_s)
        out = proc.stdout.decode(errors="replace")
        return out, time.time() - t0, None
    except subprocess.TimeoutExpired:
        return "", time.time() - t0, "timeout"
    except Exception as e:  # noqa: BLE001 - report any brain failure, never crash the run
        return "", time.time() - t0, f"{type(e).__name__}: {e}"


def parse_directive(raw):
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if not m:
        return None, "no JSON object in output"
    try:
        d = json.loads(m.group(0))
    except json.JSONDecodeError as e:
        return None, f"JSON parse error: {e}"
    if not isinstance(d.get("earmarks"), list):
        return None, "missing earmarks list"
    return d, None


def sanitize(directive, seat, snapshot):
    """Drop anything the engine would silently ignore; return (earmarks, dropped)."""
    own_units = {u["id"] for u in snapshot.get("units", [])
                 if u.get("owner") == seat and u.get("alive", 0) > 0}
    objectives = {o["id"] for o in snapshot.get("objectives", [])}
    seen, keep, dropped = set(), [], []
    for e in directive.get("earmarks", []):
        if not isinstance(e, dict):
            dropped.append({"entry": e, "why": "not a dict"})
            continue
        unit = str(e.get("unit", ""))
        verb = str(e.get("verb", ""))
        target = str(e.get("target", ""))
        why = None
        if unit not in own_units:
            why = "unknown/not-own/dead unit"
        elif verb not in VALID_VERBS:
            why = "invalid verb"
        elif verb == "HOLD_OBJECTIVE" and target not in objectives:
            why = "HOLD without a live objective target"
        elif unit in seen:
            why = "duplicate unit (one order per unit)"
        if why:
            dropped.append({"entry": e, "why": why})
            continue
        seen.add(unit)
        row = {"unit": unit, "verb": verb}
        if verb == "HOLD_OBJECTIVE":
            row["target"] = target
        keep.append(row)
    return keep, dropped


def decide(seat, snapshot, central_ids, history, model, timeout_s=60):
    """Full brain step. Returns a journal-ready dict; 'earmarks' is None on
    failure (caller keeps the previous directive in force)."""
    prompt = build_prompt(seat, snapshot, central_ids, history)
    raw, latency, err = call_llm(prompt, model, timeout_s)
    rec = {"latency_s": round(latency, 1), "error": err, "raw_len": len(raw)}
    if err:
        rec["earmarks"] = None
        return rec
    directive, perr = parse_directive(raw)
    if perr:
        rec.update({"earmarks": None, "error": perr, "raw": raw[:1000]})
        return rec
    keep, dropped = sanitize(directive, seat, snapshot)
    rec.update({"earmarks": keep, "dropped": dropped,
                "reasoning": str(directive.get("reasoning", ""))[:300]})
    return rec
