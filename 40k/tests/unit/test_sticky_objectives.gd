extends "res://addons/gut/test.gd"

# Tests for P2-23: Get Da Good Bitz — sticky objectives
# Verifies that objectives controlled by a unit with "Get Da Good Bitz" or
# "Objective Secured" remain under the player's control after the unit moves
# away, until the opponent controls the objective.

const GameStateData = preload("res://autoloads/GameState.gd")

var game_state: Node
var mission_manager: Node
var unit_ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state = AutoloadHelper.get_game_state()
	mission_manager = get_node_or_null("/root/MissionManager")
	unit_ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	assert_not_null(game_state, "GameState autoload must be available")
	assert_not_null(mission_manager, "MissionManager autoload must be available")
	assert_not_null(unit_ability_mgr, "UnitAbilityManager autoload must be available")

	# Initialize a default mission and clear state
	mission_manager.initialize_mission("take_and_hold")
	mission_manager._sticky_objectives.clear()

	# Set up minimal game state
	game_state.state["units"] = {}
	game_state.state.meta["battle_round"] = 1
	game_state.state.meta["active_player"] = 1

func after_each():
	# Clean up
	game_state.state["units"] = {}
	mission_manager._sticky_objectives.clear()

# ==========================================
# Helper Functions
# ==========================================

func _create_boyz_unit(unit_id: String, owner: int, position: Vector2) -> Dictionary:
	"""Create a Boyz unit with Get Da Good Bitz ability."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS", "BOYZ"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 2
			},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction", "description": "Faction ability"},
				{"name": "Get Da Good Bitz", "type": "Datasheet", "description": "Sticky objectives"}
			],
			"weapons": []
		},
		"models": [
			{
				"id": unit_id + "_m1",
				"wounds": 1,
				"current_wounds": 1,
				"base_mm": 32,
				"position": {"x": position.x, "y": position.y},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {},
		"attachment_data": {"attached_characters": []}
	}
	return unit

func _create_generic_unit(unit_id: String, owner: int, position: Vector2, oc: int = 1) -> Dictionary:
	"""Create a generic unit without sticky objectives."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Generic Unit",
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 4,
				"wounds": 2,
				"leadership": 7,
				"objective_control": oc
			},
			"abilities": [],
			"weapons": []
		},
		"models": [
			{
				"id": unit_id + "_m1",
				"wounds": 2,
				"current_wounds": 2,
				"base_mm": 32,
				"position": {"x": position.x, "y": position.y},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {},
		"attachment_data": {"attached_characters": []}
	}
	return unit

func _setup_objective_at(obj_id: String, position: Vector2) -> void:
	"""Set up a single objective at a given position."""
	var obj = {"id": obj_id, "position": position, "zone": "no_mans_land"}
	game_state.state.board["objectives"] = [obj]
	mission_manager.objective_control_state[obj_id] = 0

# ==========================================
# 1. Ability Detection Tests
# ==========================================

func test_has_sticky_objectives_ability_boyz():
	"""Verify Boyz unit is detected as having sticky objectives ability."""
	var boyz = _create_boyz_unit("boyz_1", 1, Vector2(100, 100))
	game_state.state.units["boyz_1"] = boyz
	assert_true(unit_ability_mgr.has_sticky_objectives_ability("boyz_1"),
		"Boyz should have sticky objectives ability")

func test_has_sticky_objectives_ability_generic_unit():
	"""Verify generic unit without ability returns false."""
	var unit = _create_generic_unit("generic_1", 1, Vector2(100, 100))
	game_state.state.units["generic_1"] = unit
	assert_false(unit_ability_mgr.has_sticky_objectives_ability("generic_1"),
		"Generic unit should not have sticky objectives ability")

func test_has_sticky_objectives_ability_nonexistent():
	"""Verify nonexistent unit returns false."""
	assert_false(unit_ability_mgr.has_sticky_objectives_ability("nonexistent"),
		"Nonexistent unit should not have sticky objectives ability")

func test_ability_marked_as_implemented():
	"""Verify Get Da Good Bitz is marked as implemented in ABILITY_EFFECTS."""
	var effect_def = unit_ability_mgr.get_ability_effect_definition("Get Da Good Bitz")
	assert_false(effect_def.is_empty(), "Get Da Good Bitz should have an ABILITY_EFFECTS entry")
	assert_true(effect_def.get("implemented", false), "Get Da Good Bitz should be marked as implemented")
	assert_eq(effect_def.get("condition", ""), "end_of_command", "Condition should be end_of_command")

# ==========================================
# 2. Sticky Objective Application Tests
# ==========================================

func test_sticky_objective_applied_when_unit_on_controlled_objective():
	"""Verify sticky lock is applied when Boyz unit is on a controlled objective."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Place Boyz within control range of objective (very close)
	var boyz = _create_boyz_unit("boyz_1", 1, obj_pos + Vector2(10, 0))
	game_state.state.units["boyz_1"] = boyz

	# Mark objective as controlled by player 1
	mission_manager.objective_control_state["obj_1"] = 1

	# Apply sticky objectives
	mission_manager.apply_sticky_objectives(1)

	# Verify sticky lock was created
	var sticky = mission_manager.get_sticky_objectives()
	assert_true(sticky.has("obj_1"), "Objective should have a sticky lock")
	assert_eq(sticky["obj_1"].player, 1, "Sticky lock should be for player 1")
	assert_eq(sticky["obj_1"].source_unit_id, "boyz_1", "Sticky lock source should be boyz_1")

func test_sticky_objective_not_applied_when_objective_not_controlled():
	"""Verify sticky lock is NOT applied when objective is not controlled by the player."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	var boyz = _create_boyz_unit("boyz_1", 1, obj_pos + Vector2(10, 0))
	game_state.state.units["boyz_1"] = boyz

	# Objective controlled by opponent (player 2) or uncontrolled (0)
	mission_manager.objective_control_state["obj_1"] = 2

	mission_manager.apply_sticky_objectives(1)

	var sticky = mission_manager.get_sticky_objectives()
	assert_false(sticky.has("obj_1"), "Sticky lock should not be applied when objective controlled by opponent")

func test_sticky_objective_not_applied_when_unit_out_of_range():
	"""Verify sticky lock is NOT applied when unit is too far from objective."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Place Boyz very far from objective (well beyond 3.79" control range)
	var far_away = obj_pos + Vector2(1000, 0)
	var boyz = _create_boyz_unit("boyz_1", 1, far_away)
	game_state.state.units["boyz_1"] = boyz

	mission_manager.objective_control_state["obj_1"] = 1

	mission_manager.apply_sticky_objectives(1)

	var sticky = mission_manager.get_sticky_objectives()
	assert_false(sticky.has("obj_1"), "Sticky lock should not be applied when unit is out of range")

func test_sticky_objective_not_applied_when_unit_battle_shocked():
	"""Verify sticky lock is NOT applied when unit is battle-shocked."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	var boyz = _create_boyz_unit("boyz_1", 1, obj_pos + Vector2(10, 0))
	boyz.flags["battle_shocked"] = true
	game_state.state.units["boyz_1"] = boyz

	mission_manager.objective_control_state["obj_1"] = 1

	mission_manager.apply_sticky_objectives(1)

	var sticky = mission_manager.get_sticky_objectives()
	assert_false(sticky.has("obj_1"), "Sticky lock should not be applied when unit is battle-shocked")

# ==========================================
# 3. Sticky Objective Persistence Tests
# ==========================================

func test_sticky_objective_persists_when_no_oc_present():
	"""Verify sticky-locked objective remains controlled when no units are nearby."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Set up sticky lock
	mission_manager._sticky_objectives["obj_1"] = {"player": 1, "source_unit_id": "boyz_1"}

	# Create the source unit (alive but far away from objective)
	var boyz = _create_boyz_unit("boyz_1", 1, Vector2(5000, 5000))
	game_state.state.units["boyz_1"] = boyz

	# Check objective control — no units are near objective, but sticky should hold
	mission_manager.check_all_objectives()

	var control = mission_manager.objective_control_state.get("obj_1", 0)
	assert_eq(control, 1, "Sticky-locked objective should remain controlled by player 1")

func test_sticky_objective_broken_by_opponent_oc():
	"""Verify sticky lock is broken when opponent has OC on the objective."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Set up sticky lock for player 1
	mission_manager._sticky_objectives["obj_1"] = {"player": 1, "source_unit_id": "boyz_1"}

	# Create the source unit (alive but far away)
	var boyz = _create_boyz_unit("boyz_1", 1, Vector2(5000, 5000))
	game_state.state.units["boyz_1"] = boyz

	# Place opponent unit ON the objective
	var enemy = _create_generic_unit("enemy_1", 2, obj_pos + Vector2(5, 0), 2)
	game_state.state.units["enemy_1"] = enemy

	# Check objective control — opponent should now control it
	mission_manager.check_all_objectives()

	var control = mission_manager.objective_control_state.get("obj_1", 0)
	assert_eq(control, 2, "Opponent with OC should break sticky lock and control objective")

	# Verify sticky lock was removed
	assert_false(mission_manager._sticky_objectives.has("obj_1"),
		"Sticky lock should be removed when opponent takes control")

func test_sticky_objective_broken_when_source_unit_destroyed():
	"""Verify sticky lock is broken when the source unit is destroyed."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Set up sticky lock
	mission_manager._sticky_objectives["obj_1"] = {"player": 1, "source_unit_id": "boyz_1"}

	# Create the source unit but all models are dead
	var boyz = _create_boyz_unit("boyz_1", 1, Vector2(5000, 5000))
	boyz.models[0].alive = false
	game_state.state.units["boyz_1"] = boyz

	# Check objective control
	mission_manager.check_all_objectives()

	var control = mission_manager.objective_control_state.get("obj_1", 0)
	assert_eq(control, 0, "Sticky lock should not hold when source unit is destroyed")

	# Verify sticky lock was removed
	assert_false(mission_manager._sticky_objectives.has("obj_1"),
		"Sticky lock should be removed when source unit is destroyed")

# ==========================================
# 4. Edge Case Tests
# ==========================================

func test_sticky_does_not_apply_for_wrong_player():
	"""Verify sticky lock only applies for the active player."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	var boyz = _create_boyz_unit("boyz_1", 1, obj_pos + Vector2(10, 0))
	game_state.state.units["boyz_1"] = boyz

	mission_manager.objective_control_state["obj_1"] = 1

	# Apply sticky for player 2 (Boyz belong to player 1)
	mission_manager.apply_sticky_objectives(2)

	var sticky = mission_manager.get_sticky_objectives()
	assert_false(sticky.has("obj_1"), "Sticky should not be applied for wrong player")

func test_player_oc_overrides_own_sticky():
	"""Verify that if the player still has OC on the objective, it stays controlled normally."""
	var obj_pos = Vector2(200, 200)
	_setup_objective_at("obj_1", obj_pos)

	# Player 1 has a sticky lock AND a unit on the objective
	mission_manager._sticky_objectives["obj_1"] = {"player": 1, "source_unit_id": "boyz_1"}

	var boyz = _create_boyz_unit("boyz_1", 1, obj_pos + Vector2(5, 0))
	game_state.state.units["boyz_1"] = boyz

	mission_manager.check_all_objectives()

	var control = mission_manager.objective_control_state.get("obj_1", 0)
	assert_eq(control, 1, "Player with both OC and sticky should control objective")

func test_clear_sticky_on_mission_reinit():
	"""Verify sticky objectives are cleared when mission is reinitialized."""
	mission_manager._sticky_objectives["obj_1"] = {"player": 1, "source_unit_id": "boyz_1"}
	assert_true(mission_manager._sticky_objectives.size() > 0, "Should have sticky objective before reinit")

	mission_manager.initialize_mission("take_and_hold")

	assert_eq(mission_manager._sticky_objectives.size(), 0, "Sticky objectives should be cleared on reinit")
