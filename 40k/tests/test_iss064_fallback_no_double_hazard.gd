extends SceneTree

# ISS-064 (11e 09.07): fall-back DESPERATE ESCAPE must apply its 06.03
# hazard rolls EXACTLY ONCE at edition 11. The bug: the legacy 10e
# _process_desperate_escape ran at move-CONFIRM with no edition guard
# while the 11e FallBackMove template already rolled hazards at
# move-BEGIN, double-applying losses.
#
# This test drives a battle-shocked unit through BEGIN_FALL_BACK ->
# CONFIRM_UNIT_MOVE against the REAL MovementPhase and asserts the unit's
# alive count does not change between BEGIN (hazards applied) and CONFIRM
# at edition 11. A 10e sensitivity check proves the legacy path is still
# reachable (so this test would catch a regression if the guard were
# removed).
#
# Usage: godot --headless --path . -s tests/test_iss064_fallback_no_double_hazard.gd

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

func _seed_board(gs) -> void:
	# Battle-shocked 5-model INFANTRY unit (1 wound each) in a coherent
	# line; only m0 is engaged with the enemy below it. 1-wound models =>
	# each 06.03 hazard failure (1 MW) destroys one model.
	gs.state["units"] = {
		"U_FB": {"id": "U_FB", "owner": 1, "status": 2,
			"flags": {"battle_shocked": true},
			"status_effects": {"battle_shocked": true},
			"meta": {"name": "Retreaters", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1, "objective_control": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 500}},
				{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 540, "y": 500}},
				{"id": "m2", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 580, "y": 500}},
				{"id": "m3", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 620, "y": 500}},
				{"id": "m4", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 660, "y": 500}},
			]},
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Blockers", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1, "objective_control": 1}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 545}},
			]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 7

func _alive(gs, uid: String) -> int:
	var n := 0
	for m in gs.state["units"][uid].get("models", []):
		if m.get("alive", true):
			n += 1
	return n

func _drive(gs, pm) -> Dictionary:
	# Returns {begin_ok, alive_after_begin, confirm_ok, alive_after_confirm}.
	pm.transition_to_phase(7)
	var phase = pm.get_current_phase_instance()
	var r_begin = phase.execute_action({
		"type": "BEGIN_FALL_BACK", "actor_unit_id": "U_FB", "player": 1,
		"payload": {"fall_back_mode": "desperate_escape"}})
	var a_begin = _alive(gs, "U_FB")
	var r_confirm = phase.execute_action({
		"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": "U_FB", "player": 1})
	var a_confirm = _alive(gs, "U_FB")
	return {"begin_ok": r_begin.get("success", false), "a_begin": a_begin,
		"confirm_ok": r_confirm.get("success", false), "a_confirm": a_confirm}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss064_fallback_no_double_hazard ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or pm == null or rules == null:
		_check("autoloads reachable", false); _finish(); return

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition

	# --- Edition 11: hazards applied at BEGIN, NO second application at CONFIRM ---
	print("-- edition 11: single application --")
	GameConstants.edition = 11
	# Seed chosen so at least one 06.03 hazard fails at BEGIN (so the test
	# proves BEGIN applied losses AND CONFIRM added none). Search seeds.
	var seed11 := -1
	for s in range(1, 400):
		rules.set_test_seed(s)
		gs.state = prev_state.duplicate(true)
		_seed_board(gs)
		var r = _drive(gs, pm)
		if r.begin_ok and r.confirm_ok and r.a_begin < 5:
			seed11 = s
			_check("edition 11: BEGIN applied >=1 hazard loss (alive %d < 5)" % r.a_begin, r.a_begin < 5)
			_check("edition 11: CONFIRM adds NO further loss (begin=%d confirm=%d)" % [r.a_begin, r.a_confirm],
				r.a_confirm == r.a_begin, "double-fire: confirm changed the alive count")
			break
	_check("edition 11: found a seed with a BEGIN hazard loss", seed11 != -1)

	# --- Edition 10 sensitivity: the legacy CONFIRM path is still reachable ---
	# (At 10e the BEGIN 11e seam is inert; the legacy desperate-escape runs
	# at CONFIRM. With a battle-shocked unit it tests all models. Prove it
	# CAN reduce the alive count at CONFIRM — so the guard removal would be
	# caught by this very test.)
	print("\n-- edition 10: legacy desperate-escape still fires at CONFIRM --")
	GameConstants.edition = 10
	var saw_legacy_loss := false
	for s in range(1, 400):
		rules.set_test_seed(s)
		gs.state = prev_state.duplicate(true)
		_seed_board(gs)
		var r = _drive(gs, pm)
		if r.begin_ok and r.confirm_ok and r.a_begin == 5 and r.a_confirm < 5:
			saw_legacy_loss = true
			_check("edition 10: BEGIN applies nothing, CONFIRM legacy path kills (begin=5 confirm=%d)" % r.a_confirm, true)
			break
	_check("edition 10: legacy desperate-escape reachable at CONFIRM (sensitivity)", saw_legacy_loss)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	rules.set_test_seed(-1)
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
