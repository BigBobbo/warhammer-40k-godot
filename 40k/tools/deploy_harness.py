#!/usr/bin/env python3
"""Deployment harness — run the AI's deployment on predeploy fixtures and
measure it with DeploymentEval (docs/AI_DEPLOYMENT_PLAN.md, P0).

Drives the LIVE game through the GodotMCP runtime bridge (127.0.0.1:9080), so
the real DeploymentPhase, AIPlayer retry/fallback path and AIDecisionMaker run
exactly as in a player's game. For each run it:
  1. loads a `tests/saves/*_predeploy` fixture (both seats AI),
  2. optionally swaps the deployment map AND loads a terrain layout that the
     11e index recommends for that map — or the one named as layout@map —
     (objectives re-derived from the layout),
  3. optionally disables hand-authored AI plans (PLANS_ENABLED=0) and
     optionally attaches leaders as Declare Battle Formations would (--attach
     gate: the windowed gate's pairs, each Deffkilla Wartrike leading a
     6-bike Warbikers unit, both seats — C-2),
  4. waits until DEPLOYMENT ends, immediately disables the AI (so nothing
     moves), and records DeploymentEval metrics for both players plus the
     forced-reserve and rejected-action counts.

Rejected placements (P0.4): `rejected_actions` is the gate metric — every
deployment-type action (DEPLOY_UNIT, COMPOSITE_DEPLOY, EMBARK_UNITS_DEPLOYMENT,
PLACE_IN_RESERVES, ATTACH_CHARACTER_DEPLOYMENT) AIPlayer routed that the game
refused, counted at the source (AIPlayer.get_deploy_rejections(), read with
DeploymentEval.count_rejected_deploy_actions). `failed_attempts` is the legacy
game-log count of first-try DEPLOY_UNIT / COMPOSITE_DEPLOY rejections, kept so
runs stay comparable with the P0.0 baseline (298); rejected >= failed always.

Cold caches (L2-1): every run starts with FormationBuilder.clear_caches(), so
the per-drop times are what the first game of a session pays (the block /
variant legality caches are filled per unit signature); --warm-caches keeps
them across runs. Per-drop WORK is reported as counts too (the largest
evaluations / fresh checks / growth work of any one drop — D10 / C-3).

Several harnesses can run side by side: pass a distinct --port (with --launch
the game is started with GODOT_MCP_PORT=<port>).

Usage (game must be running with the bridge, or pass --launch):
  python3 40k/tools/deploy_harness.py --launch \
      --fixtures mirror_orks_2000_predeploy asym_2000_predeploy \
      --zones fixture hammer_anvil dawn_of_war --seeds 7 11 --plans off \
      --out /tmp/deploy_baseline.json
  python3 40k/tools/deploy_harness.py --launch --port 9400 --attach gate \
      --zones search_and_destroy disruption_vs_reconnaissance_3@search_and_destroy

Exit code 0 always (it is a measurement tool); read the summary table.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time

HOST, PORT = "127.0.0.1", 9080

# --attach presets: CHARACTER -> bodyguard, applied to both seats (a second
# seat's copy of a unit is keyed <id>_P2).
ATTACH_PRESETS = {
    "gate": {"U_DEFFKILLA_WARTRIKE_A": "U_WARBIKERS_C", "U_DEFFKILLA_WARTRIKE_B": "U_WARBIKERS_D"},
}

# Deployment map -> a terrain layout whose 11e index entry recommends it.
LAYOUT_FOR_ZONE = {
    "crucible_of_battle": "take_and_hold_mirror_1",
    "hammer_anvil": "purge_the_foe_vs_priority_assets_3",
    "dawn_of_war": "take_and_hold_mirror_2",
    "search_and_destroy": "disruption_vs_priority_assets_3",
    "sweeping_engagement": "disruption_vs_disruption_3",
    "tipping_point": "disruption_vs_disruption_2",
}


def call(command, params, timeout=600.0):
    s = socket.create_connection((HOST, PORT), timeout=timeout)
    s.sendall((json.dumps({"id": 1, "command": command, "params": params}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode().split("\n")[0]) if buf else {"error": "no response"}


def script(code, timeout=600.0):
    r = call("execute_script", {"code": code, "multiline": True}, timeout)
    res = r.get("result", {})
    if isinstance(res, dict) and res.get("status") == "ok":
        return res.get("result")
    raise RuntimeError("execute_script failed: %s" % json.dumps(r)[:800])


def bridge_up():
    try:
        call("execute_script", {"code": "return 1", "multiline": True}, timeout=5)
        return True
    except OSError:
        return False


def launch(log_path):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/bin") + ":" + env.get("PATH", "")
    env["GODOT_MCP_PORT"] = str(PORT)
    proj = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    with open(log_path, "w") as fh:
        subprocess.Popen(["godot", "--path", proj, "--rendering-method", "gl_compatibility"],
                         stdout=fh, stderr=subprocess.STDOUT, env=env)
    for _ in range(600):
        time.sleep(0.5)
        try:
            if "GodotMCP] Listening" in open(log_path).read():
                time.sleep(1.0)
                return
        except OSError:
            pass
    raise RuntimeError("bridge did not come up; see %s" % log_path)


LOAD_TMPL = r'''
AIPlayer.enabled = false
AIPlayer.ai_players = {1: false, 2: false}
AIDecisionMaker._config_overrides["PLANS_ENABLED"] = %(plans)s
HandoffManager._scenario_mode = true
var ok = SaveLoadManager.load_game("%(fixture)s")
if not ok:
	return {"ok": false}
GameState.state["meta"]["from_save"] = true
GameConstants.edition = 11
RulesEngine.set_test_seed(%(seed)d)
var zone = "%(zone)s"
var layout = "%(layout)s"
var pairs = %(pairs)s
var attached = 0
for cid0 in pairs:
	for sfx in ["", "_P2"]:
		var cid = str(cid0) + sfx
		var bid = str(pairs[cid0]) + sfx
		if not GameState.state.units.has(cid) or not GameState.state.units.has(bid):
			continue
		var bg = GameState.state.units[bid]
		var ad = bg.get("attachment_data", {})
		if ad == null:
			ad = {}
		var lst = ad.get("attached_characters", [])
		if not (cid in lst):
			lst.append(cid)
		ad["attached_characters"] = lst
		bg["attachment_data"] = ad
		GameState.state.units[cid]["attached_to"] = bid
		attached += 1
if zone != "fixture":
	TerrainManager.load_terrain_layout(layout)
	GameState.state["board"]["terrain_layout"] = layout
	var zs = DeploymentZoneData.get_zones(zone)
	var dz = []
	for i in range(zs.size()):
		var z = zs[i]
		dz.append(z if z is Dictionary else {"player": i + 1, "poly": z})
	GameState.state["board"]["deployment_zones"] = dz
	GameState.state["meta"]["deployment_type"] = zone
	MissionManager._setup_objectives_for_deployment(zone)
var gc = GameState.state["meta"].get("game_config", {})
if gc == null:
	gc = {}
gc["player1_type"] = "AI"
gc["player2_type"] = "AI"
GameState.state["meta"]["game_config"] = gc
AIPlayer.clear_action_log()
AIPlayer.clear_deploy_rejections()
FormationBuilder.reset_stats()
if %(cold)s:
	FormationBuilder.clear_caches()
AIDecisionMaker.reset_deploy_drop_stats()
# Fresh event log per run so failed-attempt counts are per-run (dev harness only).
GameEventLog.entries.clear()
tree.change_scene_to_file("res://scenes/Main.tscn")
return {"ok": true, "ev_start": 0, "layout": TerrainManager.current_layout, "deployment_type": GameState.state["meta"].get("deployment_type", "?"), "attached": attached}
'''

POLL = r'''
var p = int(GameState.state["meta"].get("phase", -1))
if p != 1 and p != 0:
	AIPlayer.enabled = false
	AIPlayer.ai_players = {1: false, 2: false}
return p
'''

MEASURE_TMPL = r'''
var out = {}
var alog = AIPlayer.get_action_log()
var ev = GameEventLog.entries
var tail = ev.slice(%(ev_start)d)
for p in [1, 2]:
	var r = DeploymentEval.evaluate(GameState.state, p, {"visibility": %(vis)s, "per_unit": %(rows)s})
	r["forced_reserves"] = DeploymentEval.count_forced_reserves(alog, p)
	r["failed_attempts"] = DeploymentEval.count_failed_deploy_attempts(tail, p)
	r["rejected_actions"] = DeploymentEval.count_rejected_deploy_actions(AIPlayer.get_deploy_rejections(), p)
	out[str(p)] = r
out["layout"] = TerrainManager.current_layout
out["deployment_type"] = GameState.state["meta"].get("deployment_type", "?")
out["phase_after"] = int(GameState.state["meta"].get("phase", -1))
out["deploy_rejections"] = AIPlayer.get_deploy_rejections().slice(0, 10)
# P0.1: the formation builder's own counters and a whole-board legality audit
# (zone / Infiltrators, walls, board, overlaps both ways, coherency with
# attached characters judged as one unit — 19.01 + 03.03).
out["formation_builder"] = FormationBuilder.stats()
# P0.3: whole-decision time per drop (every build of the drop included) and
# the 11e picker's outcomes (inside / behind / column spot).
out["deploy_drops"] = AIDecisionMaker.deploy_drop_stats()
var audit = DeploymentEval.audit_legality(GameState.state)
out["audit"] = {"violations": audit.violations, "models": audit.models, "zone": audit.zone,
	"infiltrators": audit.infiltrators, "wall": audit.wall, "board": audit.board,
	"overlap_pairs": audit.overlap_pairs, "incoherent_units": audit.incoherent_units, "problems": audit.problems}
return out
'''


def run_one(fixture, zone, seed, plans, vis, rows, timeout_s, attach="", cold=True):
    layout = ""
    if "@" in zone:
        layout, zone = zone.split("@", 1)
    elif zone != "fixture":
        layout = LAYOUT_FOR_ZONE.get(zone, "")
    pairs = ATTACH_PRESETS.get(attach, {})
    info = script(LOAD_TMPL % {"plans": "1.0" if plans else "0.0", "fixture": fixture, "seed": seed,
                               "zone": zone, "layout": layout, "pairs": json.dumps(pairs),
                               "cold": "true" if cold else "false"})
    if not info or not info.get("ok"):
        return {"error": "load failed", "info": info}
    # Re-enable AI only now the scene switch is queued; Main's reconfigure
    # reads game_config (both AI) and turns AIPlayer back on.
    t0 = time.time()
    seen_deploy = False
    while time.time() - t0 < timeout_s:
        time.sleep(0.2)
        try:
            p = script(POLL, timeout=30)
        except Exception:
            continue
        if p == 1:
            seen_deploy = True
        if seen_deploy and p not in (0, 1):
            break
    else:
        return {"error": "timeout waiting for deployment to end", "info": info}
    res = script(MEASURE_TMPL % {"ev_start": int(info.get("ev_start", 0)), "vis": "true" if vis else "false",
                                 "rows": "true" if rows else "false"}, timeout=900)
    res["seconds"] = round(time.time() - t0, 1)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixtures", nargs="+", default=["mirror_orks_2000_predeploy"])
    ap.add_argument("--zones", nargs="+", default=["fixture"])
    ap.add_argument("--seeds", nargs="+", type=int, default=[7])
    ap.add_argument("--plans", choices=["on", "off"], default="off")
    ap.add_argument("--visibility", action="store_true", help="also count enemy units that can see each unit (slow)")
    ap.add_argument("--rows", action="store_true", help="include per-unit rows")
    ap.add_argument("--launch", action="store_true")
    ap.add_argument("--timeout", type=float, default=240.0)
    ap.add_argument("--out", default="")
    ap.add_argument("--port", type=int, default=9080, help="GodotMCP runtime port (launch sets GODOT_MCP_PORT)")
    ap.add_argument("--attach", choices=["none"] + sorted(ATTACH_PRESETS.keys()), default="none",
                    help="attach leaders before deployment (gate = the windowed gate's Wartrike pairs)")
    ap.add_argument("--warm-caches", action="store_true",
                    help="keep FormationBuilder's legality caches across runs (default: cleared per run, cold)")
    a = ap.parse_args()
    global PORT
    PORT = a.port

    if not bridge_up():
        if not a.launch:
            sys.exit("bridge not reachable on %s:%d (start the game or pass --launch)" % (HOST, PORT))
        launch(os.path.join("/tmp", "deploy_harness_game_%d.log" % PORT))

    results = []
    for fx in a.fixtures:
        for zone in a.zones:
            for seed in a.seeds:
                r = run_one(fx, zone, seed, a.plans == "on", a.visibility, a.rows, a.timeout,
                            "" if a.attach == "none" else a.attach, not a.warm_caches)
                r.update({"fixture": fx, "zone": zone, "seed": seed, "plans": a.plans, "attach": a.attach,
                          "caches": "warm" if a.warm_caches else "cold"})
                results.append(r)
                if "error" in r:
                    print("%-28s %-20s seed=%-4d ERROR %s" % (fx, zone, seed, r["error"]), flush=True)
                    continue
                fbs = r.get("formation_builder", {})
                au = r.get("audit", {})
                dds = r.get("deploy_drops", {})
                print("%-28s %-20s seed=%-4d builder builds=%s no_legal=%s gate_rej=%s max=%.0fms (%s) | audit violations=%s %s" % (
                    fx, zone, seed, fbs.get("builds", "?"), fbs.get("no_legal", "?"), fbs.get("gate_rejections", "?"),
                    float(fbs.get("max_us", 0)) / 1000.0, fbs.get("max_unit", ""), au.get("violations", "?"),
                    au.get("problems", [])[:3]), flush=True)
                print("%-28s %-20s seed=%-4d drops=%s worst drop=%.0fms (%s) mean=%.0fms | picks inside=%s behind=%s column=%s | spot builds=%s unbuildable=%s" % (
                    fx, zone, seed, dds.get("drops", "?"), float(dds.get("max_us", 0)) / 1000.0, dds.get("max_unit", ""),
                    float(dds.get("total_us", 0)) / 1000.0 / max(1, int(dds.get("drops", 0) or 1)),
                    dds.get("inside", "?"), dds.get("behind", "?"), dds.get("baseline", "?"),
                    dds.get("spot_tries", "?"), dds.get("unbuildable", "?")), flush=True)
                print("%-28s %-20s seed=%-4d per-drop max: evals=%s (%s) fresh=%s (%s) growth=%s (%s) builds=%s | %s caches, attached=%s" % (
                    fx, zone, seed, dds.get("max_evals", "?"), dds.get("max_evals_unit", ""), dds.get("max_fresh", "?"),
                    dds.get("max_fresh_unit", ""), dds.get("max_grow_work", "?"), dds.get("max_grow_work_unit", ""),
                    dds.get("max_builds", "?"), r.get("caches", "?"), r.get("info", {}).get("attached", "?") if isinstance(r.get("info"), dict) else "?"), flush=True)
                for p in ("1", "2"):
                    m = r[p]
                    print("%-28s %-20s seed=%-4d P%s forced=%d rejected=%d failed=%d reserves=%d on=%d hideable_multi=%d full_multi=%d leak=%d open=%d home=%s gap=%.1f\"%s" % (
                        fx, zone, seed, p, m["forced_reserves"], m.get("rejected_actions", -1), m["failed_attempts"], m["in_reserves"], m["on_table"],
                        m["hide_capable_multi"], m["fully_hidden_multi"], m["leakers"], m["open"],
                        m.get("home_objective", {}).get("occupied"), m["min_gap_to_enemy_zone_in"],
                        (" seen=%d" % m["seen_by_enemy_units_any"]) if a.visibility else ""), flush=True)
    tot = {"forced": 0, "rejected": 0, "failed": 0, "multi": 0, "full_multi": 0, "leak": 0, "runs": 0,
           "audit_violations": 0, "builder_no_legal": 0, "builder_gate_rejections": 0, "builder_max_ms": 0.0,
           "drop_max_ms": 0.0, "drops": 0, "drop_total_ms": 0.0, "home_held": 0, "home_known": 0,
           "drop_max_evals": 0, "drop_max_fresh": 0, "drop_max_grow_work": 0}
    for r in results:
        if "error" in r:
            continue
        tot["runs"] += 1
        tot["audit_violations"] += int(r.get("audit", {}).get("violations", 0))
        fbs = r.get("formation_builder", {})
        tot["builder_no_legal"] += int(fbs.get("no_legal", 0))
        tot["builder_gate_rejections"] += int(fbs.get("gate_rejections", 0))
        tot["builder_max_ms"] = max(tot["builder_max_ms"], float(fbs.get("max_us", 0)) / 1000.0)
        dds = r.get("deploy_drops", {})
        tot["drop_max_ms"] = max(tot["drop_max_ms"], float(dds.get("max_us", 0)) / 1000.0)
        tot["drops"] += int(dds.get("drops", 0))
        tot["drop_total_ms"] += float(dds.get("total_us", 0)) / 1000.0
        for k in ("evals", "fresh", "grow_work"):
            tot["drop_max_" + k] = max(tot["drop_max_" + k], int(dds.get("max_" + k, 0)))
        for p in ("1", "2"):
            m = r[p]
            ho = m.get("home_objective", {})
            if ho.get("known"):
                tot["home_known"] += 1
                if ho.get("occupied"):
                    tot["home_held"] += 1
            tot["forced"] += m["forced_reserves"]
            tot["failed"] += m["failed_attempts"]
            tot["rejected"] += int(m.get("rejected_actions", 0))
            tot["multi"] += m["hide_capable_multi"]
            tot["full_multi"] += m["fully_hidden_multi"]
            tot["leak"] += m["leakers"]
    print("TOTAL runs=%d forced_reserves=%d rejected_actions=%d failed_attempts=%d fully_hidden_multi=%d/%d leakers=%d" % (
        tot["runs"], tot["forced"], tot["rejected"], tot["failed"], tot["full_multi"], tot["multi"], tot["leak"]))
    print("TOTAL legality audit violations=%d | builder no_legal=%d gate_rejections=%d worst build=%.0f ms" % (
        tot["audit_violations"], tot["builder_no_legal"], tot["builder_gate_rejections"], tot["builder_max_ms"]))
    print("TOTAL drops=%d worst drop (whole decision)=%.0f ms mean=%.0f ms | home objective held %d/%d seat-runs" % (
        tot["drops"], tot["drop_max_ms"], tot["drop_total_ms"] / max(1, tot["drops"]), tot["home_held"], tot["home_known"]))
    print("TOTAL worst per-drop work: evals=%d fresh=%d growth=%d (%s caches)" % (
        tot["drop_max_evals"], tot["drop_max_fresh"], tot["drop_max_grow_work"], "warm" if a.warm_caches else "cold"))
    if a.out:
        with open(a.out, "w") as fh:
            json.dump({"results": results, "totals": tot}, fh, indent=1)
        print("wrote", a.out)


if __name__ == "__main__":
    main()
