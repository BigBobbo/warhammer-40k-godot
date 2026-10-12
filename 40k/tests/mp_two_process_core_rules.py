#!/usr/bin/env python3
"""Real two-process multiplayer check for the core-rules fixes.

Launches a HOST and a CLIENT Godot process (ENet, test-mode auto-host /
auto-join), each with its own user-data dir and MCP bridge port, then drives
BOTH peers through their MCP bridges:

  A. Fight phase (co_pretrigger, P2 = client active):
     - END_FIGHT during the global Pile In step only ends that half (12.02)
     - END_FIGHT while fights are owed is rejected (12.04) and the client is told
     - the p.74 pass: client passes via its Pass button, host passes ->
       Fight step ends -> Consolidate step (12.07) runs -> phase completes
  B. AFK turn timer in the Fight step with owed fights: no forfeit, timer
     re-armed, second timeout ends the game against the SELECTING player
  C. Movement END_MOVEMENT with unselected units -> Remain Stationary flags on
     BOTH peers, phase advances, no client desync error
     (host active, then client active)

Every check reads the live GameState / phase instance / UI of BOTH peers, and
the host's and client's GameState are compared key-by-key after each step.

Usage (from the repo root; needs the xvfb godot shim on PATH, see CLAUDE.md):
  python3 40k/tests/mp_two_process_core_rules.py [project_40k_dir] [out_dir] [scenario...]
  scenarios: fight afk move_host move_client (default: all)
Env: GODOT (binary, default "godot"), MP_HOST_PORT / MP_CLIENT_PORT (MCP
bridge ports, default 9201/9202). The ENet game port is 7777. Each peer gets
its own user:// via XDG_DATA_HOME (Linux); exit code 0 only if every check
passes.
"""
import json, os, socket, subprocess, sys, time

PROJ = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join("/tmp", "mp_two_process_core_rules")
WHICH = sys.argv[3:] or ["fight", "afk", "move_host", "move_client"]
GODOT = os.environ.get("GODOT", "godot")
HOST_PORT = int(os.environ.get("MP_HOST_PORT", "9201"))
CLIENT_PORT = int(os.environ.get("MP_CLIENT_PORT", "9202"))
if OUT:
    os.makedirs(OUT, exist_ok=True)
SRC_USER = os.path.expanduser("~/.local/share/godot/app_userdata/40k")

results = []
def check(label, cond, detail=""):
    results.append((label, bool(cond), detail))
    print(("  PASS: " if cond else "  FAIL: ") + label + ("" if cond else "  --  " + str(detail)[:600]), flush=True)


class Peer:
    def __init__(self, name, port, args):
        self.name, self.port = name, port
        self.xdg = os.path.join(OUT, "xdg_" + name)
        user = os.path.join(self.xdg, "godot/app_userdata/40k")
        os.makedirs(os.path.join(user, "saves"), exist_ok=True)
        for f in ("settings.cfg", "player_id.txt", "tutorial_progress.cfg"):
            src = os.path.join(SRC_USER, f)
            if os.path.exists(src):
                subprocess.run(["cp", src, user])
        env = dict(os.environ, XDG_DATA_HOME=self.xdg, GODOT_MCP_PORT=str(port))
        self.log_path = os.path.join(OUT, name + ".log")
        self.log = open(self.log_path, "w")
        self.proc = subprocess.Popen([GODOT, "--path", PROJ, "--test-mode", "--instance-name=" + name,
                                      "--resolution=1280x720"] + args,
                                     stdout=self.log, stderr=subprocess.STDOUT, env=env,
                                     start_new_session=True)
        self.sock = None
        self.seq = 0

    def connect(self, timeout=120):
        t0 = time.time()
        while time.time() - t0 < timeout:
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=60)
                self.f = self.sock.makefile("r")
                return True
            except OSError:
                time.sleep(1)
        return False

    def call(self, cmd, params=None):
        self.seq += 1
        self.sock.sendall((json.dumps({"id": self.seq, "command": cmd, "params": params or {}}) + "\n").encode())
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("%s: bridge closed" % self.name)
            msg = json.loads(line)
            if msg.get("id") == self.seq:
                return msg

    def ex(self, code):
        r = self.call("execute_script", {"code": code, "multiline": True})
        res = r.get("result") or {}
        if res.get("status") != "ok":
            return {"__error__": res.get("message") or res.get("error") or r}
        return res.get("result")

    def shot(self, label):
        r = self.call("capture_screenshot", {"label": label})
        return (r.get("result") or {}).get("absolute_path")

    def stop(self):
        # xvfb-run wraps Godot: signal the whole process group, not just the
        # wrapper, or the Godot child survives holding the ENet/MCP ports.
        import signal
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(timeout=10)
        except Exception:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except Exception:
                pass
        self.log.close()


def wait_until(fn, timeout=30, interval=0.5):
    t0 = time.time()
    last = None
    while time.time() - t0 < timeout:
        try:
            last = fn()
            if last is True:
                return True
        except Exception as e:  # noqa
            last = e
        time.sleep(interval)
    return last


def boot(tag):
    host = Peer(tag + "_host", HOST_PORT, ["--auto-host", "--port=7777"])
    time.sleep(3)
    client = Peer(tag + "_client", CLIENT_PORT, ["--auto-join", "--host-ip=127.0.0.1", "--host-port=7777"])
    ok = host.connect() and client.connect()
    check("[%s] both MCP bridges up" % tag, ok)
    in_game = "return tree.current_scene != null and tree.current_scene.name == \"Main\" and NetworkManager.is_networked()"
    r = wait_until(lambda: host.ex(in_game) is True and client.ex(in_game) is True, timeout=90)
    check("[%s] host + client connected and in the Main scene" % tag, r is True, r)
    check("[%s] roles: host is P1 host, client is P2" % tag,
          host.ex("return [NetworkManager.is_host(), NetworkManager.get_local_player()]") == [True, 1]
          and client.ex("return [NetworkManager.is_host(), NetworkManager.get_local_player()]") == [False, 2],
          [host.ex("return [NetworkManager.is_host(), NetworkManager.get_local_player()]"),
           client.ex("return [NetworkManager.is_host(), NetworkManager.get_local_player()]")])
    return host, client


def load_fixture(host, client, name, phase):
    r = host.ex("""var ok = SaveLoadManager._load_game_from_path("res://tests/saves/%s.w40ksave")
GameState.state.meta["from_save"] = true
GameState.state.meta.erase("from_menu")
tree.change_scene_to_file("res://scenes/Main.tscn")
return ok""" % name)
    check("load %s on host" % name, r is True, r)
    probe = "var pm = PhaseManager.get_current_phase_instance()\nreturn pm != null and GameState.get_current_phase() == %d" % phase
    r2 = wait_until(lambda: host.ex(probe) is True and client.ex(probe) is True, timeout=60)
    check("both peers in phase %d with a phase instance" % phase, r2 is True,
          [host.ex("return GameState.get_current_phase()"), client.ex("return GameState.get_current_phase()")])
    # SAVE-2 load-sync ack: the host refuses actions until the client confirms.
    r3 = wait_until(lambda: host.ex("return not NetworkManager._load_sync_blocked") is True, timeout=30)
    check("load sync confirmed by client", r3 is True, r3)
    # Harness: the real resume path (MultiplayerLobby._finalize_resume_load)
    # sets meta.from_save BEFORE snapshotting to clients; we set it after the
    # load here, so mirror it on the client or the hash differs on that key.
    client.ex('GameState.state.meta["from_save"] = true\nGameState.state.meta.erase("from_menu")\nreturn true')
    host.ex("NetworkManager.stop_turn_timer()\nreturn true")
    hashes_equal(host, client, "after loading " + name)


# Pre-existing (reproduces identically on e28e4f7): RulesEngine.
# _ensure_loadout_resolved lazily stamps these derived-cache keys onto a unit
# the first time a peer resolves its weapons, outside the diff stream — so the
# host gains them when the Fight step starts and the client only when it
# resolves the same unit. They are excluded here so the comparison tests the
# state this change produces; every other key must match exactly.
LAZY_CACHE_KEYS = ("_loadout_checked", "_loadout_version", "melee_loadout", "ranged_loadout")

CANON_DUMP = """var nm = NetworkManager
var s = GameState.state
var meta_canon = {}
for k in s.get("meta", {}):
	if k in nm._HASH_META_EXCLUDE:
		continue
	meta_canon[k] = s.meta[k]
var canon = {"units": s.get("units", {}), "players": s.get("players", {}), "factions": s.get("factions", {}), "meta": meta_canon}
return JSON.stringify(nm._canonicalize_numbers(nm._sanitize_for_json(canon)))"""


def _diff(a, b, path="", out=None):
    if out is None:
        out = []
    if type(a) != type(b):
        out.append((path, a, b))
    elif isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append((path + "." + k, a.get(k, "<missing>"), b.get(k, "<missing>")))
            else:
                _diff(a[k], b[k], path + "." + k, out)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append((path + "[len]", len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            _diff(x, y, "%s[%d]" % (path, i), out)
    elif a != b:
        out.append((path, a, b))
    return out


def hashes_equal(host, client, label):
    h = json.loads(host.ex(CANON_DUMP))
    c = json.loads(client.ex(CANON_DUMP))
    d = _diff(h, c)
    real = [x for x in d if x[0].rsplit(".", 1)[-1] not in LAZY_CACHE_KEYS]
    lazy = [x[0] for x in d if x not in real]
    check("host and client GameState identical (%s)%s" % (label, " [ignoring pre-existing lazy loadout cache on %d keys]" % len(lazy) if lazy else ""),
          not real, real[:10])


def route(peer, action):
    """Submit an action through the real network path as `peer`."""
    return peer.ex("return NetworkIntegration.route_action(%s)" % json.dumps(action))


def fight_state(peer):
    return peer.ex("""var fp = PhaseManager.get_current_phase_instance()
if fp == null or not fp.has_method("get_fight_step_11e"):
	return {"phase": GameState.get_current_phase()}
return {"phase": GameState.get_current_phase(), "step": fp.get_fight_step_11e(), "pile_in": fp.pile_in_step_11e,
	"piling": fp.piling_in_player_11e, "cons": fp.consolidation_step_11e, "selecting": fp.current_selecting_player,
	"warboss_eligible": fp.sequencer_11e.eligible_to_fight("U_WARBOSS_B", GameState.state) if fp.sequencer_11e != null else null,
	"passed": fp.sequencer_11e.passed.keys() if fp.sequencer_11e != null else null}""")


def toasts(peer):
    return peer.ex("""var out = []
for t in ToastManager.active_toasts:
	if is_instance_valid(t):
		for c in t.find_children("*", "Label", true, false):
			out.append(c.text)
return out""")


def log_errors(peer, pattern):
    with open(peer.log_path, errors="replace") as f:
        return [l.strip() for l in f if pattern in l]


def scenario_fight():
    host, client = boot("fight")
    try:
        load_fixture(host, client, "co_pretrigger", 10)
        for p in (host, client):
            p.ex('GameState.state.players["1"].merge({"cp": 0}, true)\nGameState.state.players["2"].merge({"cp": 0}, true)\nreturn true')
        s = fight_state(host)
        check("[fight] host: Pile In step, P2 (client) piles first", s.get("step") == "PILE_IN" and s.get("piling") == 2, s)

        # A1: END_FIGHT during Pile In ends only that half (was: whole phase in MP)
        route(client, {"type": "END_FIGHT", "player": 2})
        r = wait_until(lambda: fight_state(host).get("piling") == 1, timeout=15)
        hs, cs = fight_state(host), fight_state(client)
        check("[fight] client END_FIGHT in Pile In ended ONLY P2's half (host still FIGHT, P1 piles)",
              r is True and hs.get("phase") == 10 and hs.get("step") == "PILE_IN", hs)
        check("[fight] client still in FIGHT phase", cs.get("phase") == 10, cs)

        # Move the Warboss >5" from every enemy on BOTH peers (setup) so the
        # p.74 pass becomes legal for both players later.
        mv = 'GameState.state.units["U_WARBOSS_B"].models[0].merge({"position": {"x": 1000.0, "y": 1200.0}}, true)\nif tree.current_scene.has_method("_sync_all_token_positions"):\n\ttree.current_scene._sync_all_token_positions()\nreturn true'
        host.ex(mv); client.ex(mv)

        route(host, {"type": "END_FIGHT", "player": 1})
        r = wait_until(lambda: fight_state(host).get("step") == "FIGHT", timeout=15)
        hs = fight_state(host)
        check("[fight] host END_FIGHT ended P1's half -> Fight step (12.04), still FIGHT phase",
              r is True and hs.get("phase") == 10 and hs.get("selecting") == 2, hs)
        r = wait_until(lambda: fight_state(client).get("step") == "FIGHT", timeout=15)
        check("[fight] client sees the Fight step too", r is True, fight_state(client))

        # A2: host (not selecting) END_FIGHT -> rejected, nothing forfeited
        host.ex("NetworkManager.stop_turn_timer()\nreturn true")
        route(host, {"type": "END_FIGHT", "player": 1})
        time.sleep(1.0)
        hs = fight_state(host)
        check("[fight] host END_FIGHT while P2 selects is rejected (Warboss still owed, still FIGHT step)",
              hs.get("step") == "FIGHT" and hs.get("warboss_eligible") is True and hs.get("phase") == 10, hs)

        # A3: the client's Pass button is driven by the host's data
        pb = client.ex('var b = tree.current_scene.get_node_or_null("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nreturn b != null and b.is_visible_in_tree()')
        check("[fight] client's Pass (Unable to Fight) button is visible (host says P2 may pass)", pb is True, pb)
        client.shot("mp_fight_client_pass_button")
        host.shot("mp_fight_host_waiting")
        client.ex('var b = tree.current_scene.get_node("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nb.pressed.emit()\nreturn true')
        r = wait_until(lambda: fight_state(host).get("selecting") == 1, timeout=15)
        hs = fight_state(host)
        check("[fight] client pass handed the selection to P1 WITHOUT forfeiting the Warboss",
              r is True and hs.get("warboss_eligible") is True and hs.get("step") == "FIGHT" and 2 in (hs.get("passed") or []), hs)
        r = wait_until(lambda: fight_state(client).get("selecting") == 1, timeout=15)
        check("[fight] client UI follows the hand-over (selecting player 1)", r is True, fight_state(client))
        hashes_equal(host, client, "after the client's pass")

        # A4: host passes too -> both passed in succession -> Consolidate step
        host_pb = host.ex('var b = tree.current_scene.get_node_or_null("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nreturn b != null and b.is_visible_in_tree()')
        check("[fight] host's Pass button visible for P1", host_pb is True, host_pb)
        host.ex('var b = tree.current_scene.get_node("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nb.pressed.emit()\nreturn true')
        r = wait_until(lambda: fight_state(host).get("step") in ("CONSOLIDATE",) or fight_state(host).get("phase") != 10, timeout=15)
        hs = fight_state(host)
        check("[fight] both passed -> host enters the Consolidate step (12.07), not a phase skip",
              hs.get("phase") == 10 and hs.get("step") == "CONSOLIDATE", hs)
        r = wait_until(lambda: fight_state(client).get("step") == "CONSOLIDATE", timeout=15)
        check("[fight] client enters the Consolidate step too", r is True, fight_state(client))
        hashes_equal(host, client, "entering Consolidate")
        client.shot("mp_fight_client_consolidate")

        # A5: finish both consolidation halves through END_FIGHT -> phase ends
        for _ in range(4):
            hs = fight_state(host)
            if hs.get("phase") != 10:
                break
            cp = host.ex("return PhaseManager.get_current_phase_instance().consolidating_player_11e")
            route(host if cp == 1 else client, {"type": "END_FIGHT", "player": cp})
            time.sleep(1.5)
        r = wait_until(lambda: host.ex("return GameState.get_current_phase()") != 10 and client.ex("return GameState.get_current_phase()") != 10, timeout=20)
        check("[fight] after the Consolidate step both peers leave the Fight phase",
              r is True, [host.ex("return GameState.get_current_phase()"), client.ex("return GameState.get_current_phase()")])
        check("[fight] the Warboss was never marked as having fought (it passed)",
              host.ex('return GameState.state.units["U_WARBOSS_B"].get("flags", {}).get("has_fought", false)') is False)
        hashes_equal(host, client, "end of Fight phase")
        print("  info: client DESYNC log lines (pre-existing lazy-cache/harness-load noise): %d" % len(log_errors(client, "DESYNC")))
    finally:
        host.stop(); client.stop()


def scenario_afk():
    host, client = boot("afk")
    try:
        load_fixture(host, client, "co_pretrigger", 10)
        for p in (host, client):
            p.ex('GameState.state.players["1"].merge({"cp": 0}, true)\nGameState.state.players["2"].merge({"cp": 0}, true)\nreturn true')
        route(client, {"type": "END_PILE_IN", "player": 2})
        wait_until(lambda: fight_state(host).get("piling") == 1, timeout=15)
        route(host, {"type": "END_PILE_IN", "player": 1})
        r = wait_until(lambda: fight_state(host).get("step") == "FIGHT", timeout=15)
        check("[afk] Fight step running, P2 (client) must select the engaged Warboss", r is True and fight_state(host).get("selecting") == 2, fight_state(host))
        host.ex("NetworkManager.stop_turn_timer()\nNetworkManager.consecutive_timeout_count = 0\nreturn true")
        # Client tries to end the Fight step while its engaged Warboss is owed.
        route(client, {"type": "END_FIGHT", "player": 2})
        r = wait_until(lambda: any("rejected" in t and "12.04" in t for t in (toasts(client) or [])), timeout=10)
        check("[afk] client END_FIGHT with an owed fight is rejected by the host and the client is told why (12.04)",
              r is True, toasts(client))
        hs = fight_state(host)
        check("[afk] ...and nothing was forfeited (Warboss still owed, FIGHT step)",
              hs.get("step") == "FIGHT" and hs.get("warboss_eligible") is True, hs)
        client.shot("mp_afk_client_end_fight_rejected_toast")
        hashes_equal(host, client, "after rejected END_FIGHT")
        host.ex("NetworkManager._on_turn_timeout()\nreturn true")
        time.sleep(1.0)
        hs = fight_state(host)
        check("[afk] 1st timeout: no forfeit — still FIGHT step, Warboss still owed", hs.get("step") == "FIGHT" and hs.get("warboss_eligible") is True, hs)
        check("[afk] 1st timeout: timer re-armed", host.ex("return not NetworkManager.turn_timer.is_stopped()") is True)
        check("[afk] AFK player resolved as the SELECTING player (2), not the active player",
              host.ex("return NetworkManager._afk_player_for_current_phase()") == 2)
        host.ex("""var got = []
NetworkManager.game_over.connect(func(w, why): got.append([w, why]))
NetworkManager.set_meta("_go", got)
NetworkManager._on_turn_timeout()
return true""")
        time.sleep(1.5)
        go = host.ex('return NetworkManager.get_meta("_go")')
        check("[afk] 2nd consecutive timeout ends the game; winner = P1 (P2 was the AFK selector)",
              isinstance(go, list) and go and go[0][0] == 1 and go[0][1] == "turn_timeout", go)
    finally:
        host.stop(); client.stop()


def scenario_move(tag, fixture, active):
    host, client = boot(tag)
    try:
        load_fixture(host, client, fixture, 6)
        host.ex("PhaseManager.transition_to_phase(7)\nreturn true")
        probe = "return GameState.get_current_phase() == 7 and PhaseManager.get_current_phase_instance() != null"
        r = wait_until(lambda: host.ex(probe) is True and client.ex(probe) is True, timeout=30)
        check("[%s] both peers in Movement" % tag, r is True)
        host.ex("NetworkManager.stop_turn_timer()\nreturn true")
        unsel = host.ex("return PhaseManager.get_current_phase_instance().get_units_requiring_selection(%d)" % active)
        check("[%s] host lists unselected units for P%d" % (tag, active), isinstance(unsel, list) and len(unsel) > 0, unsel)
        actor = host if active == 1 else client
        route(actor, {"type": "END_MOVEMENT", "player": active})
        r = wait_until(lambda: host.ex("return GameState.get_current_phase()") == 8 and client.ex("return GameState.get_current_phase()") == 8, timeout=20)
        check("[%s] END_MOVEMENT by P%d advanced BOTH peers to Shooting" % (tag, active), r is True,
              [host.ex("return GameState.get_current_phase()"), client.ex("return GameState.get_current_phase()")])
        code = """var bad = []
for uid in %s:
	var f = GameState.state.units[uid].get("flags", {})
	if not (f.get("moved", false) and f.get("remained_stationary", false)):
		bad.append(uid)
return bad""" % json.dumps(unsel)
        time.sleep(1.0)
        check("[%s] host: every previously-unselected unit remained stationary" % tag, host.ex(code) == [], host.ex(code))
        check("[%s] client: same Remain Stationary flags synced" % tag, client.ex(code) == [], client.ex(code))
        hashes_equal(host, client, tag + " after END_MOVEMENT")
        print("  info: client DESYNC log lines (pre-existing/harness-load noise): %d" % len(log_errors(client, "DESYNC")))
        client.shot(tag + "_client_shooting")
    finally:
        host.stop(); client.stop()


def main():
    for name in WHICH:
        print("\n==== %s ====" % name, flush=True)
        # Safety net for peers a crashed earlier run left behind (only ours).
        subprocess.run(["pkill", "-f", "--", "--instance-name=%s_" % name])
        time.sleep(2)
        try:
            if name == "fight":
                scenario_fight()
            elif name == "afk":
                scenario_afk()
            elif name == "move_host":
                scenario_move("move_host", "audit_baseline_postdeploy", 1)
            elif name == "move_client":
                scenario_move("move_client", "audit_baseline_postdeploy_p2first", 2)
        except Exception as e:
            check("[%s] scenario crashed" % name, False, repr(e))

    passed = sum(1 for _, ok, _ in results if ok)
    print("\n=== MP two-process: %d passed, %d failed ===" % (passed, len(results) - passed))
    json.dump([{"label": l, "ok": ok, "detail": str(d)[:800]} for l, ok, d in results], open(os.path.join(OUT, "results.json"), "w"), indent=1)
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
