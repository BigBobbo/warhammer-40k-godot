extends SceneTree

# FIX_PILEIN_TARGETS_11E (11e rules audit CH-09, rank 10):
# _compute_pile_in_movements moved each model toward the closest enemy model
# of ANY enemy unit (10th-edition geometry). 12.03 PILE-IN MOVE: "BEFORE
# MOVING: Select pile-in targets: If your unit is engaged, select every enemy
# unit it is engaged with. Otherwise, select one or more enemy units within 5"
# of your unit. WHILE MOVING: ... Each model that is moved must end its move
# closer to the closest pile-in target". The engine (PileInMove.before_moving /
# model_move_allowed, checked by FightPhase._validate_pile_in_11e) measures
# "closer" against the pile-in targets only, so a model drawn toward a
# non-target unit failed the whole move (AIPlayer then retried with no
# movement and logged an ERROR), and an unengaged unit with no enemy within
# 5" was refused 'no pile-in targets within 5"'.
#
# Cases (live FightPhase, P1 active, 12.02 Pile In step, engine validator):
#  (a1) ATK engaged with A; an UNENGAGED unit B is the nearest enemy to ATK's
#       second model: FIX=0 the PILE_IN is rejected ('each moved model must
#       end closer to the closest pile-in target (12.03)'); FIX=1 it is
#       accepted and that model moves toward A.
#  (a2) an unengaged unit that charged, no enemy within 5": FIX=0 moves and
#       is rejected ('no pile-in targets within 5"'); FIX=1 returns no
#       movements (accepted).
#  (a3) 19.03 Attached unit: the bodyguard is engaged with A, its attached
#       character's model has B (unengaged) nearest: FIX=0 rejected, FIX=1
#       the character's model moves toward A and the move is accepted.
#  (g1) engaged with A only (B far away): identical movements at both values.
#  (g2) unengaged charger with one enemy within 5" (the nearest) and one
#       beyond: identical movements at both values.
#
# Run with: godot --headless --path . -s tests/unit/test_ai_fix_pilein_targets_11e.gd

const AI_PATH := "res://scripts/AIDecisionMaker.gd"
const PARAM := "FIX_PILEIN_TARGETS_11E"
const CLOSER_ERR := "closer to the closest pile-in target (12.03)"
const NO_TARGET_ERR := "no pile-in targets within 5"

var _pass_count: int = 0
var _fail_count: int = 0
var _ran := false
var AIDM = null

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

func _gs() -> Node:
	return root.get_node("GameState")

func _pm() -> Node:
	return root.get_node("PhaseManager")

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
	print("\n=== FIX_PILEIN_TARGETS_11E: pile in toward the 12.03 pile-in targets only ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	var aip = root.get_node("AIPlayer")
	aip.enabled = false
	AIDM = load(AI_PATH)

	test_non_target_nearest_enemy()
	test_no_target_within_5()
	test_attached_character_moves_toward_target()
	test_engaged_single_enemy_unchanged()
	test_unengaged_target_within_5_unchanged()

	AIDM._config_overrides.erase(PARAM)
	GameConstants.edition = prev_edition
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)

# --- board helpers -----------------------------------------------------------

const AXE := {"name": "Axe", "type": "Melee", "range": "Melee", "attacks": "2", "weapon_skill": "3",
	"strength": "5", "ap": "-1", "damage": "1", "special_rules": ""}

func _model(mid: String, x: float, y: float) -> Dictionary:
	return {"id": mid, "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32,
		"base_type": "circular", "base_dimensions": {}, "position": {"x": x, "y": y}}

func _unit(uid: String, owner: int, name: String, models: Array, flags: Dictionary = {}) -> Dictionary:
	return {"id": uid, "owner": owner, "status": 2, "flags": flags.duplicate(),
		"meta": {"name": name, "points": 100, "keywords": ["INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2, "leadership": 6, "objective_control": 2},
			"weapons": [AXE], "abilities": []},
		"models": models}

# Enter a fresh Fight phase on `units` with P1 active: the 12.02 Pile In step
# opens with P1's half.
func _enter_pile_in(units: Dictionary) -> Node:
	var gs = _gs()
	var pm = _pm()
	gs.state["units"] = units
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["phase"] = 10
	pm.transition_to_phase(10)
	var fp = pm.get_current_phase_instance()
	if fp.phase_completed.is_connected(pm._on_phase_completed):
		fp.phase_completed.disconnect(pm._on_phase_completed)
	_assert(int(fp.pile_in_step_11e) == int(fp.PileInStep11e.ACTIVE) and int(fp.piling_in_player_11e) == 1,
		"set-up: the 12.02 Pile In step is open for Player 1")
	return fp

func _pile_in(unit_id: String, fix: float) -> Dictionary:
	AIDM._config_overrides[PARAM] = fix
	print("  --- %s = %.0f ---" % [PARAM, fix])
	var snapshot: Dictionary = _gs().create_snapshot(false)
	var action: Dictionary = AIDM._compute_pile_in_action(snapshot, unit_id, 1)
	var mv: Dictionary = action.get("movements", {})
	var keys: Array = mv.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s->(%.1f, %.1f)" % [str(k), mv[k].x, mv[k].y])
	print("  -> PILE_IN %s movements {%s}" % [unit_id, ", ".join(parts)])
	return action

func _validate(fp, action: Dictionary) -> Dictionary:
	var a: Dictionary = action.duplicate(true)
	a["player"] = 1
	var v: Dictionary = fp.validate_action(a)
	print("  -> engine: valid=%s errors=%s" % [str(v.get("valid", false)), str(v.get("errors", []))])
	return v

func _has_error(v: Dictionary, needle: String) -> bool:
	for e in v.get("errors", []):
		if str(e).contains(needle):
			return true
	return false

func _pos(units: Dictionary, uid: String, idx: int) -> Vector2:
	var p = units[uid]["models"][idx]["position"]
	return Vector2(float(p.x), float(p.y))

func _mv_json(action: Dictionary) -> String:
	var out := {}
	var mv: Dictionary = action.get("movements", {})
	for k in mv:
		out[str(k)] = [snappedf(mv[k].x, 0.001), snappedf(mv[k].y, 0.001)]
	return JSON.stringify(out, "", true)

# --- cases -------------------------------------------------------------------

func _a1_units(b_pos: Vector2) -> Dictionary:
	# All on one line (11e engagement range is 2"): ATK m0 is in base contact
	# with A's a0 (52 px apart, 1.6 px edge gap); m1 is 1.9" (76 px edge) from
	# m0 and 3.2" from a0; B's b0 (default) is 2.4" from m1 — not engaged, yet
	# m1's nearest enemy model.
	return {
		"ATK": _unit("ATK", 1, "Axe Squad", [_model("m0", 752, 1000), _model("m1", 878.4, 1000)]),
		"A": _unit("A", 2, "Engaged Foe", [_model("a0", 700, 1000)]),
		"B": _unit("B", 2, "Bystander", [_model("b0", b_pos.x, b_pos.y)]),
	}

func test_non_target_nearest_enemy():
	print("\n-- (a1) engaged with A; unengaged B is ATK m1's nearest enemy --")
	var units := _a1_units(Vector2(1024.8, 1000))
	var fp = _enter_pile_in(units)
	var rules = root.get_node("RulesEngine")
	_assert(rules.check_units_in_engagement_range(units["ATK"], units["A"], _gs().state)
		and not rules.check_units_in_engagement_range(units["ATK"], units["B"], _gs().state),
		"set-up: ATK is engaged with A, not with B")
	var m1 := _pos(units, "ATK", 1)
	var a0 := _pos(units, "A", 0)
	var b0 := _pos(units, "B", 0)
	_assert(m1.distance_to(b0) < m1.distance_to(a0), "set-up: B's model is nearer to m1 than A's")

	var act0 := _pile_in("ATK", 0.0)
	var v0 := _validate(fp, act0)
	var mv0: Dictionary = act0.get("movements", {})
	_assert(mv0.has("1") and Vector2(mv0["1"]).distance_to(b0) < m1.distance_to(b0),
		"FIX=0 (old): m1 piles in toward B, the nearest enemy of any unit")
	_assert(not v0.get("valid", true) and _has_error(v0, CLOSER_ERR),
		"FIX=0 (old): the engine rejects the PILE_IN ('%s')" % CLOSER_ERR)

	var act1 := _pile_in("ATK", 1.0)
	var v1 := _validate(fp, act1)
	var mv1: Dictionary = act1.get("movements", {})
	_assert(v1.get("valid", false), "FIX=1: the engine accepts the PILE_IN (errors %s)" % str(v1.get("errors", [])))
	_assert(mv1.has("1") and Vector2(mv1["1"]).distance_to(a0) < m1.distance_to(a0),
		"FIX=1: m1 piles in toward A, the pile-in target (%s)" % str(mv1.get("1", "no move")))
	_assert(not mv1.has("0"), "FIX=1: m0 (base contact with A) does not move")

func test_no_target_within_5():
	print("\n-- (a2) charged, unengaged, the only enemy 6\" away --")
	var units := {
		"ATK2": _unit("ATK2", 1, "Late Chargers", [_model("m0", 400, 1600), _model("m1", 452, 1600)],
			{"charged_this_turn": true, "fights_first": true}),
		"C": _unit("C", 2, "Distant Foe", [_model("c0", 452 + 50.4 + 240, 1600)]),
	}
	var fp = _enter_pile_in(units)
	var act0 := _pile_in("ATK2", 0.0)
	var v0 := _validate(fp, act0)
	_assert(not act0.get("movements", {}).is_empty(), "FIX=0 (old): models pile in toward C anyway")
	_assert(not v0.get("valid", true) and _has_error(v0, NO_TARGET_ERR),
		"FIX=0 (old): the engine rejects it ('%s\"')" % NO_TARGET_ERR)
	var act1 := _pile_in("ATK2", 1.0)
	var v1 := _validate(fp, act1)
	_assert(act1.get("movements", {}).is_empty(), "FIX=1: no pile-in target -> no movements")
	_assert(v1.get("valid", false), "FIX=1: the engine accepts the empty pile-in (errors %s)" % str(v1.get("errors", [])))

func test_attached_character_moves_toward_target():
	print("\n-- (a3) 19.03: bodyguard engaged with A; its leader's model has unengaged B nearest --")
	var units := _a1_units(Vector2(1135.2, 1000))
	# Leader model 1.5" beyond the bodyguard's m1, 2.4" from B's b0 (5.2" from
	# m1, so B is not engaged), 5.96" from A's a0. m1's nearest is still A.
	units["ATK"]["attachment_data"] = {"attached_characters": ["LDR"]}
	var ldr := _unit("LDR", 1, "Leader", [_model("l0", 988.8, 1000)])
	ldr["attached_to"] = "ATK"
	ldr["meta"]["keywords"] = ["INFANTRY", "CHARACTER"]
	units["LDR"] = ldr
	var fp = _enter_pile_in(units)
	var rules = root.get_node("RulesEngine")
	_assert(rules.check_units_in_engagement_range(units["ATK"], units["A"], _gs().state)
		and not rules.check_units_in_engagement_range(units["ATK"], units["B"], _gs().state)
		and not rules.check_units_in_engagement_range(units["LDR"], units["B"], _gs().state),
		"set-up: the Attached unit is engaged with A, not with B")
	var l0 := _pos(units, "LDR", 0)
	var a0 := _pos(units, "A", 0)
	var b0 := _pos(units, "B", 0)
	_assert(l0.distance_to(b0) < l0.distance_to(a0), "set-up: B's model is nearer to the leader than A's")
	var act0 := _pile_in("ATK", 0.0)
	var v0 := _validate(fp, act0)
	var mv0: Dictionary = act0.get("movements", {})
	_assert(mv0.has("LDR:0") and Vector2(mv0["LDR:0"]).distance_to(b0) < l0.distance_to(b0),
		"FIX=0 (old): the leader's model piles in toward B")
	_assert(not v0.get("valid", true) and _has_error(v0, CLOSER_ERR),
		"FIX=0 (old): the engine rejects the Attached unit's PILE_IN ('%s')" % CLOSER_ERR)
	var act1 := _pile_in("ATK", 1.0)
	var v1 := _validate(fp, act1)
	var mv1: Dictionary = act1.get("movements", {})
	_assert(not mv1.has("LDR:0") or Vector2(mv1["LDR:0"]).distance_to(a0) < l0.distance_to(a0),
		"FIX=1: the leader's model moves toward A or holds (%s)" % str(mv1.get("LDR:0", "no move")))
	_assert(v1.get("valid", false), "FIX=1: the engine accepts the Attached unit's PILE_IN (errors %s)" % str(v1.get("errors", [])))

func test_engaged_single_enemy_unchanged():
	print("\n-- (g1) engaged with A; B is far away --")
	var units := _a1_units(Vector2(1500, 400))
	var fp = _enter_pile_in(units)
	var act0 := _pile_in("ATK", 0.0)
	var v0 := _validate(fp, act0)
	var act1 := _pile_in("ATK", 1.0)
	var v1 := _validate(fp, act1)
	_assert(not act0.get("movements", {}).is_empty(), "set-up: the engaged unit piles in (%d model(s))" % act0.get("movements", {}).size())
	_assert(_mv_json(act0) == _mv_json(act1), "engaged with the nearest enemy: FIX=1 movements identical to FIX=0")
	_assert(v0.get("valid", false) == v1.get("valid", false) and v1.get("valid", false),
		"engaged with the nearest enemy: accepted at both values")

func test_unengaged_target_within_5_unchanged():
	print("\n-- (g2) charged, unengaged; D 3\" away (pile-in target), E 8\" away --")
	var units := {
		"ATK3": _unit("ATK3", 1, "Chargers", [_model("m0", 400, 1600), _model("m1", 452, 1600)],
			{"charged_this_turn": true, "fights_first": true}),
		"D": _unit("D", 2, "Near Foe", [_model("d0", 452 + 50.4 + 120, 1600)]),
		"E": _unit("E", 2, "Far Foe", [_model("e0", 400, 1600 - 50.4 - 320)]),
	}
	var fp = _enter_pile_in(units)
	_assert(not root.get_node("RulesEngine").is_unit_engaged("ATK3", _gs().state), "set-up: ATK3 is unengaged (D is 3\" away)")
	var act0 := _pile_in("ATK3", 0.0)
	var v0 := _validate(fp, act0)
	var act1 := _pile_in("ATK3", 1.0)
	var v1 := _validate(fp, act1)
	_assert(not act0.get("movements", {}).is_empty(), "set-up: the charger piles in (%d model(s))" % act0.get("movements", {}).size())
	_assert(_mv_json(act0) == _mv_json(act1), "nearest enemy is the pile-in target: FIX=1 movements identical to FIX=0")
	_assert(v0.get("valid", false) == v1.get("valid", false), "nearest enemy is the pile-in target: same engine verdict at both values (%s)" % str(v1.get("valid", false)))
