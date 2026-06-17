extends SceneTree

# ISS-073 (11e 24.35): a SUPER-HEAVY WALKER may, when it begins a Normal,
# Advance or Fall Back move, opt all of its models into the MOBILE keyword
# for that move — letting it move through dense terrain it could not
# otherwise cross. At the end of that move it rolls one D6; on a 1 the unit
# becomes battle-shocked.
#
# This drives the REAL MovementPhase:
#   1. BEGIN_NORMAL_MOVE with payload.shw_mobile_gamble records shw_mobile
#      on the active move (and ONLY for a SUPER-HEAVY WALKER at edition 11).
#   2. _validate_set_model_dest: with MOBILE granted the SHW crosses a dense
#      >4" feature that blocks it when the gamble is NOT taken.
#   3. CONFIRM_UNIT_MOVE rolls the D6 — on a 1 the unit is battle-shocked,
#      otherwise it is not. Driven with deterministic payload.rng_seed.
# A 10e sensitivity check proves the opt-in is inert outside edition 11.
#
# Usage: godot --headless --path . -s tests/test_iss073_shw_mobile_gamble.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _seed_board(gs, keywords: Array) -> void:
	# One SHW model at (500,500). A dense, 6"-tall feature sits across the
	# path to (560,500): a SUPER-HEAVY WALKER (4" limit) is blocked by it
	# unless MOBILE is granted.
	gs.state["units"] = {
		"U_SHW": {"id": "U_SHW", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Big Walker", "keywords": keywords,
				"stats": {"move": 10, "toughness": 9, "save": 3, "wounds": 12, "objective_control": 4}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 12, "current_wounds": 12, "base_mm": 100, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7

func _seed_terrain(tm) -> void:
	tm.terrain_features = [{
		"id": "dense1", "type": "ruins", "category": "dense", "height_inches": 6.0,
		"polygon": PackedVector2Array([
			Vector2(520, 470), Vector2(540, 470), Vector2(540, 530), Vector2(520, 530)
		]),
	}]

func _find_seed(rules, want_one: bool) -> int:
	# Returns a seed s such that RNGService.new(s).roll_d6(1)[0] == 1 (want_one)
	# or != 1 (otherwise). Matches exactly how the gamble constructs its RNG.
	for s in range(0, 500):
		var roll = rules.RNGService.new(s).roll_d6(1)[0]
		if want_one and roll == 1:
			return s
		if not want_one and roll != 1:
			return s
	return -1

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss073_shw_mobile_gamble ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var rules = root.get_node_or_null("RulesEngine")
	var tm = root.get_node_or_null("TerrainManager")
	if gs == null or pm == null or rules == null or tm == null:
		_check("autoloads reachable", false); _finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	var prev_terrain = tm.terrain_features.duplicate(true)

	# ---------------------------------------------------------------------
	print("-- edition 11: BEGIN records shw_mobile only for SHW + gamble --")
	GameConstants.edition = 11

	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	_seed_terrain(tm)
	pm.transition_to_phase(7)  # MOVEMENT
	var phase = pm.get_current_phase_instance()
	var rb = phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"shw_mobile_gamble": true}})
	_check("BEGIN_NORMAL_MOVE succeeds", rb.get("success", false), str(rb))
	_check("SHW + gamble -> active move records shw_mobile = true",
		phase.active_moves.get("U_SHW", {}).get("shw_mobile", false) == true)

	print("\n-- _validate_set_model_dest: MOBILE crosses dense >4\" --")
	var v_mobile = phase._validate_set_model_dest({"actor_unit_id": "U_SHW",
		"payload": {"model_id": "m0", "dest": [560, 500]}})
	_check("MOBILE-granted SHW crosses the dense 6\" feature (allowed)",
		v_mobile.get("valid", false), str(v_mobile))

	# Same SHW, NO gamble -> blocked by the dense >4" feature.
	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	_seed_terrain(tm)
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {}})
	_check("no gamble -> active move records shw_mobile = false",
		phase.active_moves.get("U_SHW", {}).get("shw_mobile", false) == false)
	var v_block = phase._validate_set_model_dest({"actor_unit_id": "U_SHW",
		"payload": {"model_id": "m0", "dest": [560, 500]}})
	_check("SHW without MOBILE is BLOCKED by the dense 6\" feature (13.06)",
		not v_block.get("valid", true), str(v_block))

	# ---------------------------------------------------------------------
	print("\n-- CONFIRM rolls the D6 gamble: 1 -> battle-shocked --")
	var seed_one := _find_seed(rules, true)
	var seed_safe := _find_seed(rules, false)
	_check("found a seed rolling a 1 and a seed rolling >1",
		seed_one != -1 and seed_safe != -1, "one=%d safe=%d" % [seed_one, seed_safe])

	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	tm.terrain_features = []
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"shw_mobile_gamble": true}})
	var rc1 = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"rng_seed": seed_one}})
	_check("CONFIRM succeeds (gamble rolled 1)", rc1.get("success", false), str(rc1))
	_check("gamble rolled 1 -> unit is battle-shocked (24.35)",
		gs.state["units"]["U_SHW"].get("flags", {}).get("battle_shocked", false) == true)

	print("\n-- CONFIRM rolls the D6 gamble: >1 -> NOT battle-shocked --")
	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	tm.terrain_features = []
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"shw_mobile_gamble": true}})
	var rc2 = phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"rng_seed": seed_safe}})
	_check("CONFIRM succeeds (gamble rolled >1)", rc2.get("success", false), str(rc2))
	_check("gamble rolled >1 -> unit is NOT battle-shocked",
		gs.state["units"]["U_SHW"].get("flags", {}).get("battle_shocked", false) == false)

	# No gamble taken -> no D6 -> never battle-shocked.
	print("\n-- no gamble -> no D6, never battle-shocked --")
	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	tm.terrain_features = []
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {}})
	phase.execute_action({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"rng_seed": seed_one}})
	_check("no gamble -> unit never battle-shocked even with the 'roll a 1' seed",
		gs.state["units"]["U_SHW"].get("flags", {}).get("battle_shocked", false) == false)

	# ---------------------------------------------------------------------
	print("\n-- edition 10 sensitivity: opt-in inert, non-SHW inert --")
	GameConstants.edition = 10
	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER", "SUPER-HEAVY WALKER"])
	tm.terrain_features = []
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"shw_mobile_gamble": true}})
	_check("e10: gamble payload is inert (shw_mobile = false)",
		phase.active_moves.get("U_SHW", {}).get("shw_mobile", false) == false)

	GameConstants.edition = 11
	gs.state = prev_state.duplicate(true)
	_seed_board(gs, ["VEHICLE", "WALKER"])  # not SUPER-HEAVY WALKER
	tm.terrain_features = []
	pm.transition_to_phase(7)
	phase = pm.get_current_phase_instance()
	phase.execute_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "U_SHW",
		"player": 1, "payload": {"shw_mobile_gamble": true}})
	_check("e11: non-SHW unit cannot take the gamble (shw_mobile = false)",
		phase.active_moves.get("U_SHW", {}).get("shw_mobile", false) == false)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	tm.terrain_features = prev_terrain
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
