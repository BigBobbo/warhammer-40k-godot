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
  D. 11e end of the opponent's Movement phase (15.07 / 15.08):
     fo_host / fo_client — FIRE OVERWATCH: the active peer ends its Movement
       phase; the movement_phase_end window opens on the NON-active peer only
       (mirrored from the host), that peer picks a shooter + snap target in
       the real dialogs, the host resolves the snap shot, the DEFENDING peer
       allocates any wounds in its allocation overlay (05.03), CP / state are
       identical on both peers and both reach the Shooting phase
       (host active -> client decides, then client active -> host decides).
     ri_client — RAPID INGRESS: the host's END_MOVEMENT is NOT force-completed
       past the client's Rapid Ingress prompt; the client declines in its
       dialog (cross-turn action), then the FIRE OVERWATCH window follows and
       is auto-declined by the client's "Skip Overwatch" toggle.

Every check reads the live GameState / phase instance / UI of BOTH peers, and
the host's and client's GameState are compared key-by-key after each step.

Usage (from the repo root; needs the xvfb godot shim on PATH, see CLAUDE.md):
  python3 40k/tests/mp_two_process_core_rules.py [project_40k_dir] [out_dir] [scenario...]
  scenarios: fight afk move_host move_client fo_host fo_client ri_client (default: all)
Env: GODOT (binary, default "godot"), MP_HOST_PORT / MP_CLIENT_PORT (MCP
bridge ports, default 9201/9202). The ENet game port is 7777. Each peer gets
its own user:// via XDG_DATA_HOME (Linux); exit code 0 only if every check
passes.
"""
import json, os, socket, subprocess, sys, time

PROJ = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join("/tmp", "mp_two_process_core_rules")
WHICH = sys.argv[3:] or ["fight", "afk", "move_host", "move_client", "fo_host", "fo_client", "ri_client"]
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
	"passed": fp.sequencer_11e.get("passed").keys() if fp.sequencer_11e != null and fp.sequencer_11e.get("passed") != null else null}""")


def button_text(peer):
    return peer.ex('var b = tree.current_scene.get_node_or_null("PhaseActionButton")\nreturn b.text if b != null else null')


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
        r = wait_until(lambda: str(button_text(client)).endswith("End Fight Phase"), timeout=10)
        check("[fight] client's phase button left 'Finish Pile Ins' for the Fight step", r is True, button_text(client))

        # A2: host (not selecting) END_FIGHT -> rejected, nothing forfeited
        host.ex("NetworkManager.stop_turn_timer()\nreturn true")
        route(host, {"type": "END_FIGHT", "player": 1})
        time.sleep(1.0)
        hs = fight_state(host)
        check("[fight] host END_FIGHT while P2 selects is rejected (Warboss still owed, still FIGHT step)",
              hs.get("step") == "FIGHT" and hs.get("warboss_eligible") is True and hs.get("phase") == 10, hs)

        # A3: the client's Pass button is driven by the host's data
        pb_probe = 'var b = tree.current_scene.get_node_or_null("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nreturn b != null and b.is_visible_in_tree()'
        pb = wait_until(lambda: client.ex(pb_probe) is True, timeout=5)
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
        host_pb = wait_until(lambda: host.ex(pb_probe) is True, timeout=5)
        check("[fight] host's Pass button visible for P1", host_pb is True, host_pb)
        host.ex('var b = tree.current_scene.get_node("HUD_Right/VBoxContainer/FightScrollContainer/FightPanel/FightSelectionPanel/PassButton")\nb.pressed.emit()\nreturn true')
        r = wait_until(lambda: fight_state(host).get("step") in ("CONSOLIDATE",) or fight_state(host).get("phase") != 10, timeout=15)
        hs = fight_state(host)
        check("[fight] both passed -> host enters the Consolidate step (12.07), not a phase skip",
              hs.get("phase") == 10 and hs.get("step") == "CONSOLIDATE", hs)
        r = wait_until(lambda: fight_state(client).get("step") == "CONSOLIDATE", timeout=15)
        check("[fight] client enters the Consolidate step too", r is True, fight_state(client))
        r = wait_until(lambda: str(button_text(client)).endswith("Finish Consolidations")
                       and str(button_text(host)).endswith("Finish Consolidations"), timeout=10)
        check("[fight] both phase buttons read 'Finish Consolidations' in the Consolidate step", r is True,
              [button_text(host), button_text(client)])
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


# ── D. 11e end of the opponent's Movement phase (15.07 / 15.08) ───────────

FO_CARD = "Content/StratScroll/StratList/Card_fire_overwatch_11e"


def phase_state(peer):
    return peer.ex("""var ph = PhaseManager.get_current_phase_instance()
var w = ph.get_pending_stratagem_window() if ph != null and ph.has_method("get_pending_stratagem_window") else {}
return {"phase": GameState.get_current_phase(), "window": str(w.get("window_id", "")), "decider": int(w.get("player", 0)),
	"ri": ph.get("_awaiting_rapid_ingress") if ph != null else null,
	"prompt": ph.has_pending_end_of_phase_prompt() if ph != null and ph.has_method("has_pending_end_of_phase_prompt") else null,
	"cp1": int(GameState.state.players["1"]["cp"]), "cp2": int(GameState.state.players["2"]["cp"])}""")


def decline_pending_windows(host, client):
    """Answer (decline) any window still pending on the host from its decider's peer."""
    for _ in range(4):
        st = phase_state(host)
        if not st.get("window"):
            return
        dec = st["decider"]
        route(host if dec == 1 else client, {"type": "DECLINE_WINDOW_STRATAGEM", "player": dec, "window_id": st["window"]})
        time.sleep(1.0)


def fo_dialog(peer):
    return peer.ex("""var d = tree.root.get_node_or_null("StratagemDialog")
if d == null or not d.visible:
	return null
var card = d.get_node_or_null("%s")
if card == null:
	return {"card": false}
var uses = []
for b in card.get_node("Buttons").get_children():
	uses.append(str(b.name))
return {"card": true, "uses": uses}""" % FO_CARD)


def drive_allocation(peer, timeout=40):
    """Click through the defender's AllocationGroupOverlay (05.03) if it opens."""
    t0 = time.time()
    clicks = []
    while time.time() - t0 < timeout:
        step = peer.ex("""var o = tree.current_scene.get_node_or_null("AllocationGroupOverlay")
if o == null:
	return "none"
for path in ["Center/Panel/Row/DecisionCol/ResultPanel/DoneButton", "PickPanel/PickVBox/PickButtons/AutoPickButton",
		"PickPanel/PickVBox/PickButtons/ConfirmRemovalButton", "Center/Panel/Row/DecisionCol/RerollPanel/KeepRollsButton",
		"Center/Panel/Row/DecisionCol/ConfirmButton"]:
	var b = o.get_node_or_null(path)
	if b != null and b.is_visible_in_tree() and not b.disabled:
		b.pressed.emit()
		return path
return "waiting"
""")
        if step == "none":
            return clicks
        if step not in ("waiting",):
            clicks.append(step)
        time.sleep(0.8)
    return clicks


def scenario_fo(tag, fixture, active):
    host, client = boot(tag)
    try:
        load_fixture(host, client, fixture, 6)
        if active == 2:
            # ork11e_orks_active is saved with P1 (Orks) active; hand the turn
            # to P2 (Custodes, the client) on BOTH peers before Movement starts
            # so the HOST's Orks are the non-active player answering the window.
            swap = 'GameState.state.meta["active_player"] = 2\nreturn GameState.get_active_player()'
            check("[%s] P2 (client) is the active player on both peers" % tag, host.ex(swap) == 2 and client.ex(swap) == 2)
        host.ex("PhaseManager.transition_to_phase(7)\nreturn true")
        probe = "return GameState.get_current_phase() == 7 and PhaseManager.get_current_phase_instance() != null"
        r = wait_until(lambda: host.ex(probe) is True and client.ex(probe) is True, timeout=30)
        check("[%s] both peers in Movement (edition %s, active P%s)" % (tag, host.ex("return GameConstants.edition"), host.ex("return GameState.get_active_player()")),
              r is True and host.ex("return GameState.get_active_player()") == active)
        decline_pending_windows(host, client)
        host.ex("NetworkManager.stop_turn_timer()\nreturn true")
        decider = 2 if active == 1 else 1
        actor = host if active == 1 else client
        dpeer = client if decider == 2 else host
        other = host if dpeer is client else client
        # The deciding seat unticks its HUD "Skip Overwatch" toggle (ON by default).
        dpeer.ex('var t = tree.current_scene.get_node("HUD_Bottom/HBoxContainer/AutoDeclineOverwatch")\nt.button_pressed = false\nreturn t.button_pressed')
        start = phase_state(host)
        route(actor, {"type": "END_MOVEMENT", "player": active})
        r = wait_until(lambda: (fo_dialog(dpeer) or {}).get("card") is True, timeout=20)
        hs = phase_state(host)
        check("[%s] END_MOVEMENT by P%d: the host holds the Movement phase on P%d's movement_phase_end window" % (tag, active, decider),
              hs.get("phase") == 7 and hs.get("window") == "movement_phase_end" and hs.get("decider") == decider, hs)
        check("[%s] the NON-active peer (P%d) shows the FIRE OVERWATCH offer (mirrored window)" % (tag, decider), r is True, fo_dialog(dpeer))
        check("[%s] the active peer is NOT offered it (no FO card there)" % tag, not (fo_dialog(other) or {}).get("card"), fo_dialog(other))
        check("[%s] client is still in Movement too" % tag, client.ex("return GameState.get_current_phase()") == 7)
        dpeer.shot(tag + "_fo_offer_on_decider")
        uses = (fo_dialog(dpeer) or {}).get("uses", [])
        shooter_btn = uses[0] if uses else ""
        shooter = shooter_btn.replace("Use_fire_overwatch_11e_", "")
        dpeer.ex('tree.root.get_node("StratagemDialog/%s/Buttons/%s").pressed.emit()\nreturn true' % (FO_CARD, shooter_btn))
        pick = wait_until(lambda: dpeer.ex("""var d = tree.root.get_node_or_null("StratagemTargetDialog")
if d == null:
	return false
for c in d.get_node("Content").get_children():
	if str(c.name).begins_with("Pick_"):
		return true
return false""") is True, timeout=10)
        check("[%s] the decider's snap-target picker opened for %s" % (tag, shooter), pick is True)
        target = dpeer.ex("""var d = tree.root.get_node("StratagemTargetDialog")
for c in d.get_node("Content").get_children():
	if str(c.name).begins_with("Pick_"):
		c.pressed.emit()
		return str(c.name).substr(5)
return \"\"""")
        dpeer.shot(tag + "_fo_after_pick")
        # The DEFENDER (the active player) allocates any wounds (05.03).
        clicks = drive_allocation(other, timeout=45)
        print("  info: [%s] defender allocation clicks on P%d's peer: %s" % (tag, active, clicks))
        r = wait_until(lambda: host.ex("return GameState.get_current_phase()") == 8 and client.ex("return GameState.get_current_phase()") == 8, timeout=40)
        check("[%s] after the snap shot BOTH peers reach the Shooting phase" % tag, r is True,
              [phase_state(host), phase_state(client)])
        key = "cp%d" % decider
        check("[%s] P%d spent exactly 1 CP (host)" % (tag, decider), phase_state(host).get(key) == start.get(key) - 1, [start, phase_state(host)])
        check("[%s] …and the client agrees" % tag, phase_state(client).get(key) == start.get(key) - 1, phase_state(client))
        used = host.ex("""var n = 0
for u in StratagemManager._usage_history.get("%d", []):
	if str(u.stratagem_id) == "fire_overwatch_11e" and str(u.target_unit_id) == "%s":
		n += 1
return n""" % (decider, shooter))
        check("[%s] host recorded one FIRE OVERWATCH by %s at %s" % (tag, shooter, target), used == 1, used)
        log_n = host.ex('var n = 0\nfor e in GameEventLog.entries:\n\tif ">>> FIRE OVERWATCH <<<" in str(e.get("text", "")):\n\t\tn += 1\nreturn n')
        check("[%s] host Game Log has the snap-shot lines" % tag, isinstance(log_n, int) and log_n >= 1, log_n)
        time.sleep(1.5)
        hashes_equal(host, client, tag + " after FIRE OVERWATCH")
        dpeer.shot(tag + "_fo_resolved_decider")
        other.shot(tag + "_fo_resolved_active")
        print("  info: client DESYNC log lines: %d" % len(log_errors(client, "DESYNC")))
    finally:
        host.stop(); client.stop()


def scenario_ri_client():
    tag = "ri_client"
    host, client = boot(tag)
    try:
        load_fixture(host, client, "ork11e_orks_reactive", 6)
        reserves = 'for uid in ["U_STORMBOYZ_A"]:\n\tvar u = GameState.state.units[uid]\n\tu["status"] = GameStateData.UnitStatus.IN_RESERVES\n\tu["reserve_type"] = "strategic_reserves"\n\tfor m in u.models:\n\t\tm["position"] = null\nreturn true'
        host.ex(reserves); client.ex(reserves)
        host.ex("PhaseManager.transition_to_phase(7)\nreturn true")
        probe = "return GameState.get_current_phase() == 7 and PhaseManager.get_current_phase_instance() != null"
        r = wait_until(lambda: host.ex(probe) is True and client.ex(probe) is True, timeout=30)
        check("[ri] both peers in Movement", r is True)
        decline_pending_windows(host, client)
        host.ex("NetworkManager.stop_turn_timer()\nreturn true")
        hashes_equal(host, client, "ri before END_MOVEMENT")
        start = phase_state(host)
        route(host, {"type": "END_MOVEMENT", "player": 1})
        dlg = 'var d = tree.root.get_node_or_null("RapidIngressDialog")\nreturn d != null and d.visible and d.get_node_or_null("Content/UnitScroll/UnitList/Row_U_STORMBOYZ_A") != null'
        r = wait_until(lambda: client.ex(dlg) is True, timeout=20)
        hs = phase_state(host)
        check("[ri] host END_MOVEMENT is NOT force-completed past the client's RAPID INGRESS prompt (phase 7, prompt pending)",
              hs.get("phase") == 7 and hs.get("ri") is True and hs.get("prompt") is True, hs)
        check("[ri] the client (P2, non-active) shows the Rapid Ingress dialog with its reserve unit", r is True, client.ex(dlg))
        check("[ri] the host (P1) shows no Rapid Ingress dialog", host.ex(dlg) is not True)
        client.shot("ri_client_rapid_ingress_dialog")
        client.ex('tree.root.get_node("RapidIngressDialog/Content/Buttons/DeclineButton").pressed.emit()\nreturn true')
        # Skip Overwatch (ON by default on the client) auto-declines the
        # FIRE OVERWATCH window that follows.
        r = wait_until(lambda: host.ex("return GameState.get_current_phase()") == 8 and client.ex("return GameState.get_current_phase()") == 8, timeout=30)
        check("[ri] the client's decline (cross-turn) resumed the host's phase: both peers reach Shooting", r is True,
              [phase_state(host), phase_state(client)])
        end = phase_state(host)
        check("[ri] no CP spent by either player", end.get("cp1") == start.get("cp1") and end.get("cp2") == start.get("cp2"), [start, end])
        check("[ri] the Stormboyz stay in reserves", host.ex('return GameState.state.units["U_STORMBOYZ_A"].status') == 7)
        time.sleep(1.0)
        hashes_equal(host, client, "ri after decline")
        client.shot("ri_client_after_decline_shooting")
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
            elif name == "fo_host":
                scenario_fo("fo_host", "ork11e_orks_reactive", 1)
            elif name == "fo_client":
                scenario_fo("fo_client", "ork11e_orks_active", 2)
            elif name == "ri_client":
                scenario_ri_client()
        except Exception as e:
            check("[%s] scenario crashed" % name, False, repr(e))

    passed = sum(1 for _, ok, _ in results if ok)
    print("\n=== MP two-process: %d passed, %d failed ===" % (passed, len(results) - passed))
    json.dump([{"label": l, "ok": ok, "detail": str(d)[:800]} for l, ok, d in results], open(os.path.join(OUT, "results.json"), "w"), indent=1)
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
