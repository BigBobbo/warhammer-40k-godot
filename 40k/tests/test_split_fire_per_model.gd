extends SceneTree

# SPLIT-FIRE + PER-MODEL LOS+RANGE
#
# Verifies the engine-side primitives that back split-fire:
#  1. get_eligible_shooter_models filters per-model by range
#  2. _filter_eligible_model_ids drops ineligibles from a passed-in slice
#  3. ShootingPhase._process_assign_target accepts multiple pending
#     assignments for the same weapon_id with disjoint model_ids
#  4. CLEAR_ASSIGNMENT with target_unit_id removes a single slice
#  5. CONFIRM_TARGETS preserves the splits (two confirmed_assignments)
#  6. Resolve-time filter drops models that lost eligibility post-confirm
#     (e.g. moved out of range / killed)
#
# Uses U_BOYZ_A + "slugga" (12" range) from the legacy UNIT_WEAPONS table so
# weapon lookup works without depending on unit.meta.weapons parsing.
#
# Usage: godot --headless --path . -s tests/test_split_fire_per_model.gd

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

# Board layout (slugga = 12" range, 1" = 40 px):
#   Shooters m1..m4 in a horizontal row at (0,0)..(600,0) — 5" apart
#   NEAR target row directly above at y=-200 (5" away) → ALL 4 in range
#   FAR target single model at (1000, 0): only the rightmost shooters reach it
#                                          (m1 ~25"away, m4 ~10")
func _make_board() -> Dictionary:
	# Shift everything off the board origin — EnhancedLineOfSight treats
	# Vector2.ZERO as an invalid/unset position.
	var OX := 1000.0
	var OY := 1000.0
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "m%d" % (i + 1),
			"position": {"x": OX + float(i * 200), "y": OY},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	# NEAR: 4 models stacked above the shooters — every shooter has a close
	# target model directly across, so all 4 are in the 12" range.
	var near_models = []
	for i in range(4):
		near_models.append({
			"id": "mn%d" % i,
			"position": {"x": OX + float(i * 200), "y": OY - 200.0},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	# FAR: single model far to the right. Only the rightmost shooters (m3, m4)
	# are within 12"; m1 and m2 are out of range.
	var far_models = [{
		"id": "mf0",
		"position": {"x": OX + 1000.0, "y": OY},
		"base_mm": 32, "base_type": "circular",
		"alive": true, "wounds": 1, "current_wounds": 1,
		"stats": {"toughness": 4, "save": 4}
	}]
	var board = {
		"units": {
			# U_BOYZ_A is in the legacy UNIT_WEAPONS table — m1..m4 carry slugga.
			"U_BOYZ_A": {
				"id": "U_BOYZ_A", "owner": 1,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": shooter_models
			},
			"U_TARGET_NEAR": {
				"id": "U_TARGET_NEAR", "owner": 2,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": near_models
			},
			"U_TARGET_FAR": {
				"id": "U_TARGET_FAR", "owner": 2,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": far_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1},
		"terrain_features": []
	}
	return board

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_split_fire_per_model ===\n")

	_test_eligibility_all_in_range()
	_test_eligibility_some_out_of_range()
	_test_filter_drops_ineligible()
	_test_phase_split_assignment_keeps_both()
	_test_phase_split_assignment_model_ids_disjoint()
	_test_phase_per_target_clear()
	_test_phase_confirm_preserves_splits()
	_test_resolve_time_filter_drops_dead()

	_finish()

# ----------------------------------------------------------------------------
# 1. All bearers in range and LoS → all eligible
# ----------------------------------------------------------------------------
func _test_eligibility_all_in_range() -> void:
	print("\n-- 1. eligibility: all 4 bearers in range of NEAR target --")
	var board = _make_board()
	var rules = root.get_node("RulesEngine")
	var result = rules.get_eligible_shooter_models("U_BOYZ_A", "slugga", "U_TARGET_NEAR", board)
	# Note: U_BOYZ_A has m1..m9 in UNIT_WEAPONS but only m1..m4 are in the
	# test board (alive). Eligibility iterates models in the unit, so m5..m9
	# from the legacy table won't be found via _get_model_by_id and are skipped.
	_check("near: 4 eligible shooters",
		result.eligible.size() == 4,
		"got %d: %s (distances=%s, reasons=%s)" % [
			result.eligible.size(), str(result.eligible),
			str(result.distances), str(result.reasons)])

# ----------------------------------------------------------------------------
# 2. Far target: only some bearers in range (edge-to-edge < 12")
# ----------------------------------------------------------------------------
func _test_eligibility_some_out_of_range() -> void:
	print("\n-- 2. eligibility: FAR target only reachable by some bearers --")
	var board = _make_board()
	var rules = root.get_node("RulesEngine")
	var result = rules.get_eligible_shooter_models("U_BOYZ_A", "slugga", "U_TARGET_FAR", board)
	_check("far: at least one but fewer than 4 eligible",
		result.eligible.size() >= 1 and result.eligible.size() < 4,
		"got %d: %s (distances=%s, reasons=%s)" % [
			result.eligible.size(), str(result.eligible),
			str(result.distances), str(result.reasons)])
	var any_out_of_range := false
	for r in result.reasons.values():
		if r == "out_of_range":
			any_out_of_range = true
			break
	_check("far: at least one bearer flagged out_of_range",
		any_out_of_range,
		"reasons map: %s" % str(result.reasons))

# ----------------------------------------------------------------------------
# 3. Filter helper: passed-in model_ids are reduced to the eligible subset
# ----------------------------------------------------------------------------
func _test_filter_drops_ineligible() -> void:
	print("\n-- 3. _filter_eligible_model_ids drops ineligible ids --")
	var board = _make_board()
	var rules = root.get_node("RulesEngine")
	var all_ids = ["m1", "m2", "m3", "m4"]
	var filtered = rules._filter_eligible_model_ids(all_ids, "U_BOYZ_A", "slugga", "U_TARGET_FAR", board)
	_check("filter: kept.size() < 4 (some dropped)",
		filtered.kept.size() < 4,
		"kept=%s dropped=%s" % [str(filtered.kept), str(filtered.dropped)])
	_check("filter: kept ∪ dropped == input",
		(filtered.kept.size() + filtered.dropped.size()) == all_ids.size())

# ----------------------------------------------------------------------------
# 4. ShootingPhase: two ASSIGN_TARGET with same weapon, different targets,
#    both kept in pending_assignments
# ----------------------------------------------------------------------------
func _test_phase_split_assignment_keeps_both() -> void:
	print("\n-- 4. phase: same weapon → two targets → two pending assignments --")
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	var board = _make_board()
	phase.game_state_snapshot = board
	phase.active_shooter_id = "U_BOYZ_A"

	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_NEAR", "model_ids": ["m1", "m2"]}
	})
	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_FAR", "model_ids": ["m3", "m4"]}
	})

	_check("phase: 2 pending_assignments after split",
		phase.pending_assignments.size() == 2,
		"got %d: %s" % [phase.pending_assignments.size(), str(phase.pending_assignments)])
	phase.queue_free()

# ----------------------------------------------------------------------------
# 5. ShootingPhase: model_ids are disjoint across splits (no double-allocation)
# ----------------------------------------------------------------------------
func _test_phase_split_assignment_model_ids_disjoint() -> void:
	print("\n-- 5. phase: assigning overlapping model_ids strips the dup --")
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	var board = _make_board()
	phase.game_state_snapshot = board
	phase.active_shooter_id = "U_BOYZ_A"

	# First: m1, m2 → NEAR
	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_NEAR", "model_ids": ["m1", "m2"]}
	})
	# Then: m2, m3 → FAR — m2 already allocated, must be stripped
	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_FAR", "model_ids": ["m2", "m3"]}
	})

	var far_alloc: Array = []
	for a in phase.pending_assignments:
		if a.target_unit_id == "U_TARGET_FAR":
			far_alloc = a.model_ids
			break
	_check("phase: FAR allocation excludes already-assigned m2",
		"m2" not in far_alloc and "m3" in far_alloc,
		"FAR allocation: %s" % str(far_alloc))
	phase.queue_free()

# ----------------------------------------------------------------------------
# 6. ShootingPhase: CLEAR_ASSIGNMENT with target_unit_id clears just one slice
# ----------------------------------------------------------------------------
func _test_phase_per_target_clear() -> void:
	print("\n-- 6. phase: per-target CLEAR_ASSIGNMENT removes one slice only --")
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	var board = _make_board()
	phase.game_state_snapshot = board
	phase.active_shooter_id = "U_BOYZ_A"

	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_NEAR", "model_ids": ["m1", "m2"]}
	})
	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_FAR", "model_ids": ["m3", "m4"]}
	})
	phase.process_action({
		"type": "CLEAR_ASSIGNMENT",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_FAR"}
	})

	_check("phase: 1 pending_assignment remaining after per-target clear",
		phase.pending_assignments.size() == 1,
		"got %d: %s" % [phase.pending_assignments.size(), str(phase.pending_assignments)])
	if not phase.pending_assignments.is_empty():
		_check("phase: remaining assignment is NEAR (the one we kept)",
			phase.pending_assignments[0].target_unit_id == "U_TARGET_NEAR",
			"target_unit_id=%s" % phase.pending_assignments[0].target_unit_id)
	phase.queue_free()

# ----------------------------------------------------------------------------
# 7. ShootingPhase: CONFIRM_TARGETS preserves the two splits as two
#    confirmed_assignments (the merge step does NOT collapse different targets)
# ----------------------------------------------------------------------------
func _test_phase_confirm_preserves_splits() -> void:
	print("\n-- 7. phase: confirm produces 2 confirmed_assignments --")
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	var board = _make_board()
	phase.game_state_snapshot = board
	phase.active_shooter_id = "U_BOYZ_A"

	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_NEAR", "model_ids": ["m1", "m2"]}
	})
	phase.process_action({
		"type": "ASSIGN_TARGET",
		"payload": {"weapon_id": "slugga", "target_unit_id": "U_TARGET_FAR", "model_ids": ["m3", "m4"]}
	})
	phase.process_action({"type": "CONFIRM_TARGETS", "payload": {}})

	_check("phase: 2 confirmed_assignments after confirm",
		phase.confirmed_assignments.size() == 2,
		"got %d" % phase.confirmed_assignments.size())
	_check("phase: pending_assignments cleared on confirm",
		phase.pending_assignments.is_empty())
	phase.queue_free()

# ----------------------------------------------------------------------------
# 8. Resolve-time filter: dead models are dropped before contributing attacks
# ----------------------------------------------------------------------------
func _test_resolve_time_filter_drops_dead() -> void:
	print("\n-- 8. resolve-time: dead model is dropped before contributing attacks --")
	var board = _make_board()
	# Kill m3 and m4 post-assignment to simulate damage taken before resolve
	board.units.U_BOYZ_A.models[2]["alive"] = false
	board.units.U_BOYZ_A.models[3]["alive"] = false
	var rules = root.get_node("RulesEngine")
	var filtered = rules._filter_eligible_model_ids(
		["m1", "m2", "m3", "m4"],
		"U_BOYZ_A", "slugga", "U_TARGET_NEAR", board
	)
	_check("resolve: dead models dropped, only m1/m2 kept",
		filtered.kept.size() == 2 and "m1" in filtered.kept and "m2" in filtered.kept,
		"kept=%s dropped=%s reasons=%s" % [
			str(filtered.kept), str(filtered.dropped), str(filtered.reasons)])

func _finish():
	print("")
	print("Result: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
