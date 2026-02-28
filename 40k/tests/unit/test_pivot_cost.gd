extends "res://addons/gut/test.gd"

# Tests for P1-61: Pivot values for non-round base models (10e Core Rules Update)
#
# Pivot value rules:
# - Non-round base, non-Monster/Vehicle = 1" subtracted from movement
# - Monster/Vehicle non-round base = 2" subtracted from movement
# - Vehicle round base >32mm with flying stem = 2" subtracted
# - Aircraft = 0" (exempt)
# - Standard round base = 0" (no cost)
# - Cost is paid once per move, regardless of number of pivots

const MovementPhaseScript = preload("res://phases/MovementPhase.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

var phase: Node
var game_state_node: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")

	var test_state = _create_pivot_test_state()
	game_state_node.state = test_state

	phase = MovementPhaseScript.new()
	add_child(phase)
	phase.enter_phase(test_state)

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _create_pivot_test_state() -> Dictionary:
	return {
		"game_id": "test_pivot",
		"current_phase": GameStateData.Phase.MOVEMENT,
		"current_player": 1,
		"active_player": 1,
		"turn": 1,
		"round": 1,
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.MOVEMENT
		},
		"units": {
			# Standard infantry with round base — 0" pivot cost
			"infantry_round": _create_unit("infantry_round", "Intercessors", 1, Vector2(200, 200),
				["INFANTRY", "IMPERIUM"], 32, "circular"),
			# Infantry with non-round base — 1" pivot cost
			"infantry_nonround": _create_unit("infantry_nonround", "Test Non-Round", 1, Vector2(400, 200),
				["INFANTRY"], 50, "oval", {"length": 75, "width": 42}),
			# Vehicle with non-round base — 2" pivot cost
			"vehicle_nonround": _create_unit("vehicle_nonround", "Battlewagon", 1, Vector2(600, 600),
				["VEHICLE", "ORKS"], 180, "rectangular", {"length": 180, "width": 110}),
			# Monster with non-round base — 2" pivot cost
			"monster_nonround": _create_unit("monster_nonround", "Test Monster", 1, Vector2(800, 600),
				["MONSTER"], 120, "oval", {"length": 120, "width": 92}),
			# Vehicle with round base >32mm and flying stem — 2" pivot cost
			"vehicle_flying_stem": _create_unit("vehicle_flying_stem", "Grav-tank", 1, Vector2(1000, 600),
				["VEHICLE", "FLY"], 100, "circular", {}, true),
			# Vehicle with round base <=32mm — 0" pivot cost
			"vehicle_small_round": _create_unit("vehicle_small_round", "Small Vehicle", 1, Vector2(1200, 600),
				["VEHICLE"], 32, "circular"),
			# Aircraft — 0" pivot cost (exempt)
			"aircraft": _create_unit("aircraft", "Test Aircraft", 1, Vector2(1400, 600),
				["AIRCRAFT", "VEHICLE"], 120, "oval", {"length": 120, "width": 92}),
			# Enemy far away
			"enemy_1": _create_unit("enemy_1", "Enemy", 2, Vector2(200, 2000),
				["INFANTRY"], 32, "circular"),
		},
		"board": {
			"size": {"width": 44.0, "height": 60.0},
			"terrain": []
		},
		"phase_data": {},
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

func _create_unit(id: String, name: String, owner: int, pos: Vector2,
		keywords: Array, base_mm: int, base_type: String,
		base_dims: Dictionary = {}, flying_stem: bool = false) -> Dictionary:
	var model = {
		"id": "%s_m1" % id,
		"alive": true,
		"position": {"x": pos.x, "y": pos.y},
		"base_mm": base_mm,
		"base_type": base_type,
		"rotation": 0.0,
	}
	if not base_dims.is_empty():
		model["base_dimensions"] = base_dims
	if flying_stem:
		model["flying_stem"] = true

	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": name,
			"stats": {"move": 10},
			"keywords": keywords
		},
		"models": [model],
		"weapons": [],
		"attachment_data": {}
	}

# ==========================================
# Pivot Value Calculation Tests
# ==========================================

func test_round_base_infantry_has_zero_pivot_value():
	"""Standard round-base infantry should have 0\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("infantry_round")
	assert_eq(pivot_value, 0.0, "Round-base infantry should have 0\" pivot value")

func test_nonround_base_infantry_has_1_inch_pivot_value():
	"""Non-round base non-Monster/Vehicle should have 1\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("infantry_nonround")
	assert_eq(pivot_value, 1.0, "Non-round base infantry should have 1\" pivot value")

func test_vehicle_nonround_base_has_2_inch_pivot_value():
	"""Vehicle with non-round base should have 2\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("vehicle_nonround")
	assert_eq(pivot_value, 2.0, "Vehicle with non-round base should have 2\" pivot value")

func test_monster_nonround_base_has_2_inch_pivot_value():
	"""Monster with non-round base should have 2\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("monster_nonround")
	assert_eq(pivot_value, 2.0, "Monster with non-round base should have 2\" pivot value")

func test_vehicle_round_base_flying_stem_has_2_inch_pivot_value():
	"""Vehicle on round base >32mm with flying stem should have 2\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("vehicle_flying_stem")
	assert_eq(pivot_value, 2.0, "Vehicle on round base >32mm with flying stem should have 2\" pivot value")

func test_vehicle_small_round_base_has_zero_pivot_value():
	"""Vehicle on round base <=32mm should have 0\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("vehicle_small_round")
	assert_eq(pivot_value, 0.0, "Vehicle on round base <=32mm should have 0\" pivot value")

func test_aircraft_has_zero_pivot_value():
	"""Aircraft should always have 0\" pivot value"""
	var pivot_value = phase.get_pivot_value_for_unit("aircraft")
	assert_eq(pivot_value, 0.0, "Aircraft should have 0\" pivot value")

# ==========================================
# Pivot Cost Tracking in Active Moves
# ==========================================

func test_normal_move_initializes_pivot_tracking():
	"""BEGIN_NORMAL_MOVE should include pivot tracking in active_moves"""
	var action = {"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "vehicle_nonround"}
	var result = phase.process_action(action)
	assert_true(result.success, "BEGIN_NORMAL_MOVE should succeed")

	var move_data = phase.get_active_move_data("vehicle_nonround")
	assert_has(move_data, "pivot_value", "move_data should have pivot_value")
	assert_has(move_data, "pivot_cost_applied", "move_data should have pivot_cost_applied")
	assert_eq(move_data.pivot_value, 2.0, "Vehicle non-round pivot value should be 2\"")
	assert_false(move_data.pivot_cost_applied, "Pivot cost should not be applied initially")

func test_apply_pivot_cost_action():
	"""APPLY_PIVOT_COST should mark pivot as applied in active_moves"""
	# First begin movement
	phase.process_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "vehicle_nonround"})

	# Apply pivot cost
	var result = phase.process_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "vehicle_nonround"})
	assert_true(result.success, "APPLY_PIVOT_COST should succeed")

	var move_data = phase.get_active_move_data("vehicle_nonround")
	assert_true(move_data.pivot_cost_applied, "Pivot cost should be marked as applied")

func test_apply_pivot_cost_only_once():
	"""APPLY_PIVOT_COST should fail if already applied"""
	phase.process_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "vehicle_nonround"})
	phase.process_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "vehicle_nonround"})

	# Try to apply again
	var validation = phase.validate_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "vehicle_nonround"})
	assert_false(validation.valid, "Second APPLY_PIVOT_COST should be rejected")

func test_apply_pivot_cost_rejected_for_zero_pivot_unit():
	"""APPLY_PIVOT_COST should fail for units with 0\" pivot value"""
	phase.process_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "infantry_round"})

	var validation = phase.validate_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "infantry_round"})
	assert_false(validation.valid, "APPLY_PIVOT_COST should be rejected for 0\" pivot value units")

# ==========================================
# Movement Cap Reduction from Pivot Cost
# ==========================================

func test_pivot_cost_reduces_effective_movement():
	"""Pivot cost should reduce effective movement cap for validation"""
	# Vehicle has M10" and 2" pivot cost → effective cap = 8"
	phase.process_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "vehicle_nonround"})
	phase.process_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "vehicle_nonround"})

	var move_data = phase.get_active_move_data("vehicle_nonround")
	var effective_cap = move_data.move_cap_inches - move_data.pivot_value
	assert_eq(effective_cap, 8.0, "Effective cap should be M10\" - 2\" pivot = 8\"")

func test_reset_unit_move_clears_pivot_cost():
	"""RESET_UNIT_MOVE should clear pivot_cost_applied"""
	phase.process_action({"type": "BEGIN_NORMAL_MOVE", "actor_unit_id": "vehicle_nonround"})
	phase.process_action({"type": "APPLY_PIVOT_COST", "actor_unit_id": "vehicle_nonround"})

	var result = phase.process_action({"type": "RESET_UNIT_MOVE", "actor_unit_id": "vehicle_nonround"})
	assert_true(result.success, "RESET_UNIT_MOVE should succeed")

	# After reset, the move_data may be cleared — check it either doesn't exist
	# or has pivot_cost_applied = false
	var move_data = phase.get_active_move_data("vehicle_nonround")
	if not move_data.is_empty():
		assert_false(move_data.get("pivot_cost_applied", false),
			"Pivot cost should be cleared after reset")
