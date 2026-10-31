extends SceneTree

# FIX-SECURED-AWARE (11e rules audit OC-05, protocol V2-4): secured objectives
# (14.03) were ignored by the AI.
#
# Root cause — _evaluate_all_objectives read who holds an objective from OC in
# range only: a 0 v 0 objective was "uncontrolled", a tie "contested", our
# empty home earned WEIGHT_HOME_UNDEFENDED (+9), and the hold pass kept a
# "sole holder" keeper on every objective it held. The AI never asked
# MissionManager.is_objective_secured. The engine (MissionManager
# _check_objective_control) gives a secured objective to the securing player
# on any tie (0 v 0 included) — even with no unit in range — and only a
# greater enemy level of control breaks the lock (14.03; 14.02 tie rule
# "unless that objective is secured"). Bench Kult of Speed Gretchin secure
# objectives with Thievin' Scavengers (OrkAbilities11e), so the Ork AI idled
# keepers on objectives the engine already held for it and tried to re-take
# its own secured objectives.
#
# With FIX_SECURED_AWARE = 1, on a tie the securer holds the objective: for it
# held_safe / held_threatened (threatened when enemy OC is in range or can
# arrive next move), counted in its holds, no home-undefended bonus; for the
# opponent enemy_weak. In the hold pass a keeper is not required on our
# secured objective when no enemy OC is in range or can arrive next move.
# Guards: an objective nobody secured is unchanged; a keeper under a
# projected threat still holds; FIX_SECURED_AWARE = 0 restores the old read.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_secured_aware.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const FIXTURE := "res://tests/saves/mirror_orks_2000_postdeploy.w40ksave"
const MOVABLE := ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "REMAIN_STATIONARY"]
const PX := 40.0
const HOME := Vector2(880, 300)       # synthetic boards: P1 home
const NML := Vector2(500, 1000)       # synthetic boards: a no-man's-land objective
const OPEN := Vector2(1260, 1000)     # synthetic boards: an open no-man's-land objective
const ENEMY_HOME := Vector2(880, 2100)

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null
var _mm = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests():
	if _ran:
		return
	_ran = true
	await process_frame
	print("\n=== FIX-SECURED-AWARE: a secured objective (14.03) stays with its securer on a tie ===\n")
	_mm = root.get_node_or_null("MissionManager")
	var gs = root.get_node_or_null("GameState")
	_assert(_mm != null and gs != null, "MissionManager / GameState autoloads present")
	if _mm == null or gs == null:
		print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
		quit(1)
		return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var prev_state: Dictionary = gs.state.duplicate(true)
	AIDM = load(AI_PATH)

	test_fixture_secured_home_read_as_held()
	test_param_zero_restores_old_read()
	test_secured_home_valued_like_a_held_home()
	test_secured_hold_counts_toward_hold_min()
	test_unsecured_objective_unchanged()
	test_keeper_freed_on_secured_objective()
	test_keeper_kept_when_enemy_can_arrive()

	AIDM._config_overrides.erase("FIX_SECURED_AWARE")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	AIDM._primary_awareness_p1 = {}
	AIDM._primary_awareness_p2 = {}
	gs.state = prev_state
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- helpers -----------------------------------------------------------------

func _eval_of(evals: Array, oid: String) -> Dictionary:
	for ev in evals:
		if str(ev.get("id", "")) == oid:
			return ev
	return {}

func _evals(snap: Dictionary, player: int, battle_round: int, fix: float) -> Array:
	AIDM._config_overrides["FIX_SECURED_AWARE"] = fix
	var friendly = AIDM._get_units_for_player(snap, player)
	var enemies = AIDM._get_enemy_units(snap, player)
	return AIDM._evaluate_all_objectives(snap, AIDM._get_objectives(snap), player, enemies, friendly, battle_round)

## mirror_orks_2000_postdeploy with P1's home objective secured by P1's army
## and every P1 unit that stands in range of it moved away (to the board's
## east edge), so the objective is 0 v 0.
var _fixture_snap: Dictionary = {}
func _fixture() -> Dictionary:
	if not _fixture_snap.is_empty():
		return _fixture_snap
	var gs = root.get_node("GameState")
	var ser = root.get_node("StateSerializer")
	var state: Dictionary = ser.deserialize_game_state(FileAccess.get_file_as_string(FIXTURE))
	gs.load_from_snapshot(state)
	var snap: Dictionary = gs.create_snapshot()
	var home: Dictionary = {}
	for od in snap.board.objectives:
		if str(od.get("id", "")) == "obj_home_1":
			home = od
	var moved: Array = []
	var k := 0
	for uid in snap.units:
		var u: Dictionary = snap.units[uid]
		if int(u.get("owner", 0)) != 1:
			continue
		var in_range := false
		for m in u.models:
			if m.get("alive", true) and _mm.model_in_objective_range(m, home):
				in_range = true
		if not in_range:
			continue
		moved.append(uid)
		for m in u.models:
			m["position"] = Vector2(1700, 1300 + 45 * k)
			k += 1
	print("  moved off obj_home_1 (area-large-14): %s" % str(moved))
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	_mm.secure_objective("obj_home_1", 1, "")
	AIDM._primary_awareness_p1 = {}
	AIDM._primary_awareness_p2 = {}
	_fixture_snap = snap
	return snap

func _unit(snap: Dictionary, uid: String, owner: int, positions: Array, oc: int, move: float = 6.0) -> void:
	var models = []
	for i in range(positions.size()):
		models.append({"id": "m%d" % (i + 1), "alive": true, "base_mm": 32, "base_type": "circular",
			"base_dimensions": {}, "position": positions[i], "wounds": 2, "current_wounds": 2})
	snap.units[uid] = {"id": uid, "owner": owner, "status": 2,
		"meta": {"name": uid, "points": 100, "stats": {"move": move, "toughness": 4, "save": 4,
			"wounds": 2, "leadership": 7, "objective_control": oc}, "keywords": ["INFANTRY"], "weapons": []},
		"models": models, "flags": {}}

func _row(at: Vector2, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(at + Vector2(float(i - (n - 1) / 2.0) * 40.0, 0.0))
	return out

func _board(battle_round: int = 3) -> Dictionary:
	var objs = [
		{"id": "obj_home_1", "position": HOME, "zone": "player1"},
		{"id": "obj_nml_a", "position": NML, "zone": "no_mans_land"},
		{"id": "obj_open", "position": OPEN, "zone": "no_mans_land"},
		{"id": "obj_home_2", "position": ENEMY_HOME, "zone": "player2"},
	]
	return {"battle_round": battle_round, "meta": {"battle_round": battle_round, "active_player": 1},
		"board": {"objectives": objs, "terrain_features": []}, "units": {}}

# --- tests: the objective read -----------------------------------------------

func test_fixture_secured_home_read_as_held() -> void:
	print("\n--- mirror_orks_2000_postdeploy: obj_home_1 secured by P1, no model in range, FIX = 1 ---")
	var snap = _fixture()
	var p1 = _eval_of(_evals(snap, 1, 1, 1.0), "obj_home_1")
	var p2 = _eval_of(_evals(snap, 2, 1, 1.0), "obj_home_1")
	print("  P1 view: state=%s friendly_oc=%s enemy_oc=%s | P2 view: state=%s" % [p1.get("state"), p1.get("friendly_oc"), p1.get("enemy_oc"), p2.get("state")])
	_assert(int(p1.get("friendly_oc", -1)) == 0 and int(p1.get("enemy_oc", -1)) == 0, "the home objective is 0 v 0 (P1's units moved off its area)")
	_assert(str(p1.get("state", "")) == "held_safe", "P1 reads its secured home as held_safe (got %s)" % str(p1.get("state")))
	_assert(str(p2.get("state", "")) == "enemy_weak", "P2 reads P1's secured home as enemy_weak — any OC above P1's breaks the lock (got %s)" % str(p2.get("state")))

func test_param_zero_restores_old_read() -> void:
	print("\n--- same board, FIX = 0 ---")
	var snap = _fixture()
	var p1 = _eval_of(_evals(snap, 1, 1, 0.0), "obj_home_1")
	var p2 = _eval_of(_evals(snap, 2, 1, 0.0), "obj_home_1")
	print("  P1 view: state=%s prio=%.2f | P2 view: state=%s" % [p1.get("state"), float(p1.get("priority", 0.0)), p2.get("state")])
	_assert(str(p1.get("state", "")) == "uncontrolled" and str(p2.get("state", "")) == "uncontrolled",
		"off: both players read the 0 v 0 objective as uncontrolled (the old read)")
	var p1_on = _eval_of(_evals(snap, 1, 1, 1.0), "obj_home_1")
	_assert(float(p1.get("priority", 0.0)) > float(p1_on.get("priority", 0.0)) + 9.0,
		"on drops what off adds: the home-undefended +9 and the uncontrolled weight (off %.2f vs on %.2f)" % [
			float(p1.get("priority", 0.0)), float(p1_on.get("priority", 0.0))])

func test_secured_home_valued_like_a_held_home() -> void:
	print("\n--- synthetic: empty secured home vs a home our squad holds (round 3) ---")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	var a = _board()
	_unit(a, "ENEMY", 2, _row(ENEMY_HOME, 3), 2)
	_unit(a, "ELSEWHERE", 1, _row(NML, 3), 2)
	_mm.secure_objective("obj_home_1", 1, "")
	var secured = _eval_of(_evals(a, 1, 3, 1.0), "obj_home_1")
	_mm.clear_sticky_objectives_for_player(1)
	var b = _board()
	_unit(b, "ENEMY", 2, _row(ENEMY_HOME, 3), 2)
	_unit(b, "ELSEWHERE", 1, _row(NML, 3), 2)
	_unit(b, "HOLDER", 1, _row(HOME, 3), 2)
	var held = _eval_of(_evals(b, 1, 3, 1.0), "obj_home_1")
	print("  secured empty home: state=%s prio=%.2f | held home: state=%s prio=%.2f" % [
		secured.get("state"), float(secured.get("priority", 0.0)), held.get("state"), float(held.get("priority", 0.0))])
	_assert(str(secured.get("state", "")) == "held_safe", "the empty secured home is held_safe")
	_assert(is_equal_approx(float(secured.get("priority", 0.0)), float(held.get("priority", 1.0))),
		"it is valued exactly like a home our squad holds — no home-undefended bonus")

func test_secured_hold_counts_toward_hold_min() -> void:
	print("\n--- synthetic: a hold-2 primary rule; the secured home counts as one of our holds ---")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	var rules = [{"when": "command", "type": "hold_min", "min": 2, "exclude_home": false, "vp": 5}]
	AIDM._secondary_awareness_p1 = {}
	var a = _board()
	_unit(a, "ENEMY", 2, _row(ENEMY_HOME, 3), 2)
	_mm.secure_objective("obj_home_1", 1, "")
	AIDM._primary_awareness_p1 = {"card_name": "test", "active_rules": 1, "vp_rules": rules.duplicate(true)}
	var on = _eval_of(_evals(a, 1, 3, 1.0), "obj_open")
	var off = _eval_of(_evals(a, 1, 3, 0.0), "obj_open")
	print("  obj_open vp: on=%s %s | off=%s %s" % [on.get("vp_value"), str(on.get("vp_sources")), off.get("vp_value"), str(off.get("vp_sources"))])
	_assert(is_equal_approx(float(on.get("vp_value", 0.0)), 5.0), "on: taking obj_open reaches hold-2 with the secured home (5 VP)")
	_assert(is_equal_approx(float(off.get("vp_value", 0.0)), 2.5), "off: the old read counts no hold, so obj_open only builds toward hold-2 (2.5 VP)")
	AIDM._primary_awareness_p1 = {}
	_mm.clear_sticky_objectives_for_player(1)

func test_unsecured_objective_unchanged() -> void:
	print("\n--- guard: nobody secured anything — identical evaluation on and off ---")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	var a = _board()
	_unit(a, "ENEMY", 2, _row(NML + Vector2(0, 40), 2), 2)   # contests obj_nml_a 4 v 4
	_unit(a, "MINE", 1, _row(NML - Vector2(0, 40), 2), 2)
	var on = _evals(a, 1, 3, 1.0)
	var off = _evals(a, 1, 3, 0.0)
	_assert(str(on) == str(off), "no lock: the evaluations are identical")
	_assert(str(_eval_of(on, "obj_nml_a").get("state", "")) == "contested", "a 4 v 4 tie with no lock stays contested (%s)" % str(_eval_of(on, "obj_nml_a").get("state")))

# --- tests: the hold pass ----------------------------------------------------

func _plan(snap: Dictionary, fix: float) -> Dictionary:
	AIDM._config_overrides["FIX_SECURED_AWARE"] = fix
	AIDM._primary_awareness_p1 = {}
	AIDM._secondary_awareness_p1 = {}
	var friendly = AIDM._get_units_for_player(snap, 1)
	var enemies = AIDM._get_enemy_units(snap, 1)
	var objectives = AIDM._get_objectives(snap)
	var evals = AIDM._evaluate_all_objectives(snap, objectives, 1, enemies, friendly, 3)
	return AIDM._assign_units_to_objectives(snap, {"KEEPER": MOVABLE}, evals, objectives, enemies, friendly, 1, 3)

func _keeper_board(enemy_at: Vector2, enemy_move: float = 6.0) -> Dictionary:
	var a = _board()
	_unit(a, "KEEPER", 1, _row(NML, 3), 2)             # the only unit on obj_nml_a
	_unit(a, "HOMER", 1, _row(HOME, 3), 2)             # holds home (not movable this phase)
	_unit(a, "ENEMY", 2, _row(enemy_at, 3), 2, enemy_move)
	return a

func test_keeper_freed_on_secured_objective() -> void:
	print("\n--- hold pass: KEEPER alone on obj_nml_a, which P1 has secured; no enemy can arrive ---")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	_mm.secure_objective("obj_nml_a", 1, "")
	var on: Dictionary = _plan(_keeper_board(ENEMY_HOME), 1.0).get("KEEPER", {})
	var off: Dictionary = _plan(_keeper_board(ENEMY_HOME), 0.0).get("KEEPER", {})
	print("  on: %s %s (%s) | off: %s %s (%s)" % [on.get("action", ""), on.get("objective_id", ""), str(on.get("reason", "")).substr(0, 70),
		off.get("action", ""), off.get("objective_id", ""), str(off.get("reason", "")).substr(0, 70)])
	_assert(str(off.get("action", "")) == "hold" and str(off.get("objective_id", "")) == "obj_nml_a",
		"off: the keeper holds the objective as its sole holder (old)")
	_assert(not (str(on.get("action", "")) == "hold" and str(on.get("objective_id", "")) == "obj_nml_a"),
		"on: the secured objective needs no keeper — the unit is free to act elsewhere (%s %s)" % [on.get("action", ""), on.get("objective_id", "")])
	_mm.clear_sticky_objectives_for_player(1)

func test_keeper_kept_when_enemy_can_arrive() -> void:
	print("\n--- guard: same, but a fast enemy squad (M12, 15\" away: beyond 12\", inside its next move) can reach obj_nml_a ---")
	_mm.clear_sticky_objectives_for_player(1)
	_mm.clear_sticky_objectives_for_player(2)
	_mm.secure_objective("obj_nml_a", 1, "")
	var snap = _keeper_board(NML + Vector2(0, 15.0 * PX), 12.0)
	AIDM._config_overrides["FIX_SECURED_AWARE"] = 1.0
	var ev = _eval_of(AIDM._evaluate_all_objectives(snap, AIDM._get_objectives(snap), 1,
		AIDM._get_enemy_units(snap, 1), AIDM._get_units_for_player(snap, 1), 3), "obj_nml_a")
	print("  obj_nml_a: state=%s projected_enemy_oc=%s" % [ev.get("state"), ev.get("projected_enemy_oc")])
	var on: Dictionary = _plan(snap, 1.0).get("KEEPER", {})
	print("  on: %s %s (%s)" % [on.get("action", ""), on.get("objective_id", ""), str(on.get("reason", "")).substr(0, 70)])
	_assert(str(ev.get("state", "")) == "held_safe" and int(ev.get("projected_enemy_oc", 0)) > 0,
		"the objective reads held_safe with enemy OC one move away (projected %s)" % str(ev.get("projected_enemy_oc")))
	_assert(str(on.get("action", "")) == "hold" and str(on.get("objective_id", "")) == "obj_nml_a",
		"on: with enemy OC one move away the keeper still holds")
	_mm.clear_sticky_objectives_for_player(1)
