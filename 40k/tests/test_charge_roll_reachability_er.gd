extends SceneTree

# Regression suite for the "reachable target dropped by the post-roll selection
# filter" bug (branch claude/charge-distance-calc-erzq9r).
#
# Reported symptom (11e, ER 2"): a Deffkopta rolled 9" to charge a target 9.6"
# away (edge-to-edge) and the charge was reported FAILED with
#   "Rolled 9\" but nearest target is 9.6\" away (need to close to within 2\"
#    engagement range)"
# even though a charging model only needs to close to ENGAGEMENT RANGE (2"),
# i.e. travel 9.6 − 2 = 7.6", which a 9" roll easily covers.
#
# Root cause: the 11e post-roll target-selection filter (ChargeMove11e
# ._targets_within, called from ChargePhase._resolve_charge_roll) kept only
# targets whose RAW base-to-base distance was <= min(12, roll). It forgot that
# reaching a target means closing to within ER, so the reachable ceiling is
# min(12, roll + ER). A target at 9.6" (raw) was dropped by a 9" roll, leaving
# no selectable targets, so the charge was judged an insufficient roll.
#
# Usage: godot --headless --path . -s tests/test_charge_roll_reachability_er.gd

var passed := 0
var failed := 0

const PX_PER_INCH := 40.0  # project scale (Measurement.inches_to_px)

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s %s" % [label, ("(" + detail + ")") if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run_tests)

func _make_unit(id: String, owner: int, keywords: Array, positions: Array, base_mm: int = 32) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		var pos = positions[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"current_wounds": 4,
			"wounds": 4,
			"base_mm": base_mm,
			"base_type": "circular",
			"position": ({"x": pos.x, "y": pos.y} if pos != null else null),
		})
	return {
		"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": id, "keywords": keywords, "stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 4}},
		"models": models,
		"embarked_in": null,
	}

func _setup_state(units: Dictionary, active_player: int = 2) -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": active_player, "battle_round": 1, "turn_number": 1, "game_id": "test"},
		"units": units,
		"players": {"1": {"cp": 0, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"board": {"terrain": []},
		"phase_log": [],
	}

func _new_phase() -> Node:
	var phase = load("res://phases/ChargePhase.gd").new()
	root.add_child(phase)
	phase._on_phase_enter()
	return phase

func _tm() -> Node:
	return root.get_node("TerrainManager")

# Charger at origin; single enemy target whose edge-to-edge gap ≈ `edge_in`.
# 32mm circular bases → radius 0.63" each, so center gap = edge_in + 1.26".
func _two_unit_state(edge_in: float) -> Dictionary:
	var origin := Vector2(700.0, 2150.0)
	var center_gap_px := (edge_in + 1.26) * PX_PER_INCH
	var charger = _make_unit("U_CHG", 2, ["INFANTRY", "FLY"], [origin])
	var target = _make_unit("U_TGT", 1, ["INFANTRY"], [origin + Vector2(center_gap_px, 0.0)])
	return {"U_CHG": charger, "U_TGT": target}

func _measured_edge(state: Dictionary) -> float:
	var m = root.get_node("Measurement")
	return m.model_to_model_distance_inches(state["U_CHG"].models[0], state["U_TGT"].models[0])

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_roll_reachability_er ===")
	var prev_edition = GameConstants.edition

	_test_9_roll_reaches_9_6_target()
	_test_target_just_out_of_reach_still_fails()

	GameConstants.edition = prev_edition
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# The reported case: roll 9, target 9.6" away, ER 2" → reachable (needs 7.6").
func _test_9_roll_reaches_9_6_target() -> void:
	print("\n-- 11e: roll 9\" reaches a target 9.6\" away (ER 2\") --")
	GameConstants.edition = 11  # ER = 2"
	var state := _two_unit_state(9.6)
	_setup_state(state)
	_tm().terrain_features.clear()
	var edge := _measured_edge(state)
	_check("target edge distance ≈ 9.6\"", edge > 9.4 and edge < 9.8, "edge=%.2f" % edge)

	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {
		"targets": ["U_TGT"],
		"declared_targets": ["U_TGT"],
		"distance": 9,
		"dice_rolls": [4, 5],
	}
	var result = phase._resolve_charge_roll("U_CHG")

	_check("charge SUCCEEDS (roll 9 vs 9.6\" − 2\" ER = 7.6\" needed)",
		result.get("charge_failed", true) == false,
		"charge_failed=%s" % str(result.get("charge_failed", "missing")))
	_check("no insufficient-roll failure recorded",
		phase.failed_charge_attempts.size() == 0,
		"count=%d" % phase.failed_charge_attempts.size())
	_check("target retained (not dropped by the selection filter)",
		phase.pending_charges.get("U_CHG", {}).get("targets", []) == ["U_TGT"],
		str(phase.pending_charges.get("U_CHG", {}).get("targets", [])))
	phase.queue_free()

# A genuinely-unreachable target (edge 12", roll 9, ER 2" → needs 10") still fails.
func _test_target_just_out_of_reach_still_fails() -> void:
	print("\n-- 11e: roll 9\" cannot reach a target 12\" away (needs 10\") --")
	GameConstants.edition = 11  # ER = 2"
	var state := _two_unit_state(12.0)
	_setup_state(state)
	_tm().terrain_features.clear()
	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {
		"targets": ["U_TGT"],
		"declared_targets": ["U_TGT"],
		"distance": 9,
		"dice_rolls": [4, 5],
	}
	var result = phase._resolve_charge_roll("U_CHG")
	_check("charge FAILS (roll 9 vs 12\" − 2\" ER = 10\" needed)",
		result.get("charge_failed", false) == true,
		"charge_failed=%s" % str(result.get("charge_failed", "missing")))
	phase.queue_free()
