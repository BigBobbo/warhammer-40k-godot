#!/usr/bin/env python3
"""LLM Commander harness — runs seeded AI-vs-AI games under PlanSimulator
while an LLM rewrites one seat's standing earmarks every battle round,
injected mid-game over the MCP bridge. Zero engine changes.

Protocol and recon evidence: .llm/llm-commander-experiment.md.

Usage:
  python3 commander.py --seat 1 --seeds 5001-5006 --label arm_c1
  python3 commander.py --seat 2 --seeds 5001 --model claude-sonnet-5

Per game: start PlanSimulator (games:1, no static plans), watch the phase
stream; near the commanded seat's COMMAND phase slow the game (time_scale
1.0), catch the phase, freeze (time_scale 0.0 — AI pacing is delta-driven,
the bridge polls per-frame and stays alive), snapshot the board, ask the
brain, inject via AIDecisionMaker.set_player_plan(), unfreeze. The 90s
wall-clock stall watchdog is respected by capping each freeze at ~65s.
"""
import argparse
import glob
import json
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brain  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = ("127.0.0.1", 9080)
RESULTS_GLOB = "~/.local/share/godot/app_userdata/40k/plan_sim_results/*.json"
TS_NORMAL = 10.0
TS_SLOW = 1.0
# GameState.Phase enum (verified live 2026-08-26)
PH_DEPLOYMENT, PH_COMMAND, PH_MOVEMENT, PH_FIGHT = 1, 6, 7, 10
PH_CHARGE = 9

SIM_CONFIG = {
    "zone_id": "hammer_anvil", "layout_id": "take_and_hold_mirror_1",
    "mission_id": "take_and_hold", "army1": "custodes_lions",
    "army2": "custodes_lions", "plan1": "", "plan2": "",
    "games": 1, "difficulty": 1, "time_scale": TS_NORMAL,
    "max_seconds_per_game": 900.0,
}

POLL_CODE = """var meta = GameState.state.get("meta", {})
return {"running": PlanSimulator.is_running(),
\t"round": int(meta.get("battle_round", 0)),
\t"phase": int(meta.get("phase", 0)),
\t"active": int(meta.get("active_player", 1)),
\t"actions": AIPlayer._action_log.size(),
\t"ts": Engine.time_scale}"""

CENTRAL_CODE = """var ids = MissionManager.get_objective_ids_by_designation("central")
if not ids.is_empty():
\treturn {"central": ids}
var board = GameState.state.get("board", {})
var bs = board.get("size", {})
var centre = Vector2(Measurement.inches_to_px(float(bs.get("width", 44)) / 2.0), Measurement.inches_to_px(float(bs.get("height", 60)) / 2.0))
var best_id = ""
var best_d = INF
for obj in board.get("objectives", []):
\tvar pos = obj.get("position", null)
\tif pos == null:
\t\tcontinue
\tvar p = pos if pos is Vector2 else Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
\tvar d = centre.distance_to(p)
\tif d < best_d:
\t\tbest_d = d
\t\tbest_id = str(obj.get("id", ""))
return {"central": [best_id] if best_id != "" else []}"""

# context.earmark is a STRING: "VERB" (earmark active) or "VERB:objective"
# (the chosen assignment was the earmarked one). plan_earmark is the actual
# additive score term on a candidate.
VERIFY_CODE = """var n := 0
var tot := 0
var chosen := 0
var terms := 0
for batch in AIPlayer._all_decision_records:
\tif int(batch.get("player", 0)) != SEAT:
\t\tcontinue
\tfor r in batch.get("records", []):
\t\tif str(r.get("decision_type", "")) != "movement":
\t\t\tcontinue
\t\ttot += 1
\t\tvar em = str(r.get("context", {}).get("earmark", ""))
\t\tif em != "":
\t\t\tn += 1
\t\tif ":" in em:
\t\t\tchosen += 1
\t\tfor c in r.get("candidates", []):
\t\t\tvar sb = c.get("score_breakdown", {})
\t\t\tif sb is Dictionary and abs(float(sb.get("plan_earmark", 0))) > 0.01:
\t\t\t\tterms += 1
return {"movement_records": tot, "with_earmark": n, "earmark_chosen": chosen, "bias_terms": terms}"""


def call(command, params, timeout=180.0):
    s = socket.create_connection(BRIDGE, timeout=timeout)
    s.sendall((json.dumps({"id": 1, "command": command, "params": params}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode().split("\n")[0]) if buf else {"error": "no response"}


def script(code, timeout=180.0):
    r = call("execute_script", {"code": code, "multiline": True}, timeout)
    res = r.get("result", {})
    if res.get("status") != "ok":
        raise RuntimeError(f"execute_script failed: {json.dumps(r)[:600]}")
    return res.get("result")


def set_ts(v):
    return script(f"Engine.time_scale = {v}\nreturn Engine.time_scale")


def load_snapshot_code():
    with open(os.path.join(HERE, "snapshot.gd")) as f:
        return "".join(l for l in f if not l.lstrip().startswith("#"))


def inject(seat, earmarks, round_no):
    payload = json.dumps({"name": f"llm_commander_r{round_no}", "earmarks": earmarks},
                         separators=(",", ":"))
    assert "'" not in payload, "single quote would break GDScript embedding"
    code = f"""var plan = JSON.parse_string('{payload}')
AIDecisionMaker.set_player_plan({seat}, plan)
var got = AIDecisionMaker.get_player_plan({seat})
var snap = GameState.create_snapshot(false)
var resolved := []
for e in got.get("earmarks", []):
\tresolved.append(PlanManager.resolve_unit_id(str(e.get("unit", "")), {seat}, snap.get("units", {{}})))
return {{"name": got.get("name", ""), "count": got.get("earmarks", []).size(), "resolved": resolved}}"""
    return script(code)


def newest_result_after(t_epoch):
    for path in sorted(glob.glob(os.path.expanduser(RESULTS_GLOB)), reverse=True):
        if os.path.getmtime(path) >= t_epoch - 2:
            return json.load(open(path)), path
    return None, None


class Journal:
    def __init__(self, path):
        self.f = open(path, "a")

    def log(self, typ, **kw):
        rec = {"t": round(time.time(), 1), "type": typ, **kw}
        self.f.write(json.dumps(rec) + "\n")
        self.f.flush()
        return rec


def run_game(seed, seat, model, jr, snapshot_code):
    opponent = 2 if seat == 1 else 1
    cfg = dict(SIM_CONFIG, seed_base=seed)
    t_start = time.time()
    st = script(f"PlanSimulator.start({json.dumps(cfg)})\nreturn PlanSimulator.is_running()")
    if not st:
        raise RuntimeError("PlanSimulator did not start")
    jr.log("start", seed=seed, seat=seat, model=model)

    central = script(CENTRAL_CODE).get("central", ["obj_center"])
    commanded_rounds = []
    history = []
    last_directive = None
    slow = False
    while True:
        p = script(POLL_CODE)
        if not p["running"]:
            break
        rnd, ph, act = p["round"], p["phase"], p["active"]
        need = rnd >= 1 and rnd not in commanded_rounds
        # enter slow-mo when the commanded seat's command phase is near
        want_slow = (
            (need and act == opponent and ph >= PH_CHARGE) or
            (ph == PH_DEPLOYMENT and p["actions"] >= 26 and 1 not in commanded_rounds) or
            (need and act == seat and ph == PH_COMMAND))
        if want_slow and not slow:
            set_ts(TS_SLOW)
            slow = True
            jr.log("slow", round=rnd, phase=ph, active=act)
        catch = need and act == seat and ph == PH_COMMAND
        late = need and act == seat and PH_MOVEMENT <= ph <= PH_FIGHT
        if catch or late:
            prev = script("var p := Engine.time_scale\nEngine.time_scale = 0.0\nreturn p")
            t_f = time.time()
            try:
                snap = script(snapshot_code)
                jr.log("snapshot", round=rnd, late=late, snap_bytes=len(json.dumps(snap)))
                dec = brain.decide(seat, snap, central, history, model, timeout_s=60)
                jr.log("directive", round=rnd, **dec)
                if dec.get("earmarks"):
                    inj = inject(seat, dec["earmarks"], rnd)
                    jr.log("inject", round=rnd, **inj)
                    last_directive = dec["earmarks"]
                    history.append({"round": rnd, "orders": dec["earmarks"],
                                    "vp_then": snap.get("vp")})
                elif last_directive is not None:
                    jr.log("keep_previous", round=rnd, why=dec.get("error"))
                else:
                    jr.log("no_directive", round=rnd, why=dec.get("error"))
            finally:
                set_ts(TS_NORMAL)
                slow = False
            commanded_rounds.append(rnd)
            jr.log("unfreeze", round=rnd, frozen_s=round(time.time() - t_f, 1))
        elif slow and not need:
            set_ts(TS_NORMAL)
            slow = False
        time.sleep(0.3 if (slow or need and act == seat) else 1.0)

    verify = script(VERIFY_CODE.replace("SEAT", str(seat)))
    time.sleep(2)
    data, path = newest_result_after(t_start)
    game = data["games"][0] if data else {}
    summary = data["summary"] if data else {}
    row = {
        "seed": seed, "seat": seat,
        "margin": game.get("margin"), "winner": game.get("winner"),
        "vp_p1": game.get("vp_p1"), "vp_p2": game.get("vp_p2"),
        "status": game.get("status"), "stalls": summary.get("stalls"),
        "timeouts": summary.get("timeouts"),
        "rounds_commanded": commanded_rounds,
        "movement_records": verify.get("movement_records"),
        "with_earmark": verify.get("with_earmark"),
        "earmark_chosen": verify.get("earmark_chosen"),
        "bias_terms": verify.get("bias_terms"),
        "results_file": os.path.basename(path or ""),
    }
    jr.log("end", **row)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seat", type=int, required=True, choices=[1, 2])
    ap.add_argument("--seeds", default="5001-5006")
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--label", default="run")
    args = ap.parse_args()
    if "-" in args.seeds:
        a, b = args.seeds.split("-")
        seeds = list(range(int(a), int(b) + 1))
    else:
        seeds = [int(s) for s in args.seeds.split(",")]

    os.makedirs(os.path.join(HERE, "runs"), exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    jr = Journal(os.path.join(HERE, "runs", f"{stamp}_{args.label}.jsonl"))
    snapshot_code = load_snapshot_code()
    rows = []
    for seed in seeds:
        print(f"=== seed {seed} seat {args.seat} ===", flush=True)
        try:
            row = run_game(seed, args.seat, args.model, jr, snapshot_code)
        except Exception as e:  # noqa: BLE001 - journal and continue to next seed
            jr.log("game_error", seed=seed, error=f"{type(e).__name__}: {e}")
            print(f"GAME ERROR seed {seed}: {e}", flush=True)
            try:
                set_ts(TS_NORMAL)
            except Exception:
                pass
            row = {"seed": seed, "seat": args.seat, "status": "harness_error",
                   "error": str(e)}
        rows.append(row)
        print(json.dumps(row), flush=True)
    print("ARM SUMMARY:", json.dumps({"label": args.label, "seat": args.seat,
                                      "model": args.model, "rows": rows}), flush=True)


if __name__ == "__main__":
    main()
