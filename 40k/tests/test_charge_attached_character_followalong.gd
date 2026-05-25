extends SceneTree

# Regression: when a charging bodyguard moves, its attached character must
# auto-move by the same delta (and be included in the coherency check) so the
# character does not get left behind and break unit coherency.
#
# Pre-fix bug: ChargeController only allowed dragging bodyguard models, so the
# attached character stayed in its starting position. Coherency validation
# missed this (because it only inspected per_model_paths) and the resulting
# out-of-coherency state froze the game in downstream coherency enforcement.

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
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_attached_character_followalong ===\n")

	var game_state = root.get_node("GameState")
	if game_state == null:
		print("  FAIL: GameState autoload not available")
		_finish()
		return

	# --- Build minimal scenario: 3-model bodyguard squad + 1 attached leader ---
	# Bodyguard models at y=100, leader behind them at y=140 (within 2" coherency).
	var bodyguard_id := "U_TEST_BODYGUARD"
	var leader_id := "U_TEST_LEADER"
	var px = func(x, y): return {"x": x, "y": y}
	var make_model = func(id, pos): return {
		"id": id, "alive": true, "current_wounds": 1, "wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": pos,
	}

	game_state.state["units"][bodyguard_id] = {
		"owner": 1,
		"status": 3,  # DEPLOYED-equivalent enum slot; only used by helpers not under test
		"meta": {"name": "Test Bodyguard", "keywords": ["INFANTRY"]},
		"models": [
			make_model.call("m1", px.call(100, 100)),
			make_model.call("m2", px.call(140, 100)),
			make_model.call("m3", px.call(180, 100)),
		],
		"attachment_data": {"attached_characters": [leader_id]},
		"flags": {},
	}
	game_state.state["units"][leader_id] = {
		"owner": 1,
		"status": 3,
		"meta": {"name": "Test Leader", "keywords": ["CHARACTER", "INFANTRY"]},
		"models": [make_model.call("m1", px.call(140, 140))],
		"attached_to": bodyguard_id,
		"flags": {},
	}

	# --- Drive the new helpers directly via a temporary ChargePhase instance ---
	var ChargePhaseScript = load("res://phases/ChargePhase.gd")
	var phase = ChargePhaseScript.new()
	# Snapshot is used by some validators; harmless for the helpers under test.
	phase.game_state_snapshot = game_state.state.duplicate(true)

	# Paths reflect a 5"-style charge: bodyguard moves +200px on x. Delta = (200, 0).
	var per_model_paths := {
		"m1": [[100, 100], [300, 100]],
		"m2": [[140, 100], [340, 100]],
		"m3": [[180, 100], [380, 100]],
	}

	# 1. Delta computation
	var delta_info = phase._compute_bodyguard_move_delta(bodyguard_id, per_model_paths)
	_check("Delta computed from first bodyguard model",
		delta_info.get("found", false) and delta_info.get("delta") == Vector2(200, 0),
		"got %s" % str(delta_info))

	# 2. Attached-character final positions for coherency
	var char_finals = phase._get_attached_character_final_models(bodyguard_id, per_model_paths)
	_check("One attached-character model included in coherency set",
		char_finals.size() == 1, "got %d" % char_finals.size())
	if char_finals.size() == 1:
		_check("Attached-character final position = origin + delta",
			char_finals[0].get("position") == Vector2(340, 140),
			"got %s" % str(char_finals[0].get("position")))

	# 3. Coherency validation must include the attached character
	var coh = phase._validate_unit_coherency_for_charge(bodyguard_id, per_model_paths)
	_check("Coherency passes when leader follows bodyguard",
		coh.get("valid", false),
		"errors: %s" % str(coh.get("errors", [])))

	# 4. Auto-move changes ops target the leader unit
	var changes = phase._build_attached_character_charge_changes(bodyguard_id, per_model_paths)
	_check("Auto-move emits at least one change op for the leader",
		changes.size() >= 1, "got %d" % changes.size())
	var found_leader_pos_change := false
	for c in changes:
		if str(c.get("path", "")).begins_with("units.%s.models." % leader_id) and str(c.get("path", "")).ends_with(".position"):
			var v = c.get("value", {})
			if v.get("x") == 340.0 and v.get("y") == 140.0:
				found_leader_pos_change = true
				break
	_check("Leader model.0.position set to (340, 140)", found_leader_pos_change,
		"changes=%s" % str(changes))

	# 5. Negative case: no path entries → no delta → no changes
	var empty_changes = phase._build_attached_character_charge_changes(bodyguard_id, {})
	_check("No changes emitted when per_model_paths is empty",
		empty_changes.is_empty(), "got %d" % empty_changes.size())

	phase.free()
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
