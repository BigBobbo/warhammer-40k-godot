extends RefCounted
class_name TestDataFactory

const GameStateData = preload("res://autoloads/GameState.gd")


# Factory class for generating consistent test data
# Provides standardized game states, units, and scenarios for testing

static func create_clean_state() -> Dictionary:
	# Create a minimal clean game state for UI testing
	return {
		"game_id": "test_game",
		"current_phase": GameStateData.Phase.DEPLOYMENT,
		"current_player": 0,
		"turn": 1,
		"round": 1,
		"units": {},
		"board": {
			"size": {"width": 1000, "height": 1000}
		},
		"phase_data": {},
		"settings": {
			"measurement_unit": "inches",
			"scale": 1.0
		}
	}

static func create_test_game_state() -> Dictionary:
	# Create a comprehensive game state with test units for phase testing
	var state = create_clean_state()
	
	# Add test units
	state.units = {
		"test_unit_1": create_test_unit_1(),
		"test_unit_2": create_test_unit_2(),
		"enemy_unit_1": create_enemy_unit_1()
	}
	
	return state

static func create_test_unit_1() -> Dictionary:
	# Create a standard Space Marine Tactical Squad for testing
	return {
		"id": "test_unit_1",
		"name": "Test Tactical Squad",
		"faction": "Space Marines",
		"player_id": 0,
		"unit_type": "Infantry",
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_moved": false,
			"has_advanced": false,
			"has_shot": false,
			"has_charged": false,
			"has_fought": false,
			"is_selected": false
		},
		"stats": {
			"movement": 6,
			"weapon_skill": 3,
			"ballistic_skill": 3,
			"strength": 4,
			"toughness": 4,
			"wounds": 1,
			"attacks": 1,
			"leadership": 7,
			"armor_save": 3
		},
		"models": [
			create_model("sergeant", Vector2(100, 100)),
			create_model("marine_1", Vector2(120, 100)),
			create_model("marine_2", Vector2(140, 100)),
			create_model("marine_3", Vector2(100, 120)),
			create_model("marine_4", Vector2(120, 120))
		],
		"weapons": [
			{
				"name": "Bolter",
				"type": "ranged",
				"range": 24,
				"strength": 4,
				"ap": 0,
				"damage": 1,
				"shots": 1
			}
		],
		"abilities": ["Bolter Discipline"],
		"formation": {
			"coherency_distance": 2,
			"base_size": 25
		}
	}

static func create_test_unit_2() -> Dictionary:
	# Create a second friendly unit for multi-unit testing
	return {
		"id": "test_unit_2", 
		"name": "Test Devastator Squad",
		"faction": "Space Marines",
		"player_id": 0,
		"unit_type": "Infantry",
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_moved": false,
			"has_advanced": false,
			"has_shot": false,
			"has_charged": false,
			"has_fought": false,
			"is_selected": false
		},
		"stats": {
			"movement": 5,
			"weapon_skill": 3,
			"ballistic_skill": 3,
			"strength": 4,
			"toughness": 4,
			"wounds": 1,
			"attacks": 1,
			"leadership": 7,
			"armor_save": 3
		},
		"models": [
			create_model("sergeant", Vector2(300, 100)),
			create_model("devastator_1", Vector2(320, 100)),
			create_model("devastator_2", Vector2(340, 100)),
			create_model("devastator_3", Vector2(300, 120))
		],
		"weapons": [
			{
				"name": "Heavy Bolter",
				"type": "ranged", 
				"range": 36,
				"strength": 5,
				"ap": -1,
				"damage": 2,
				"shots": 3
			}
		],
		"abilities": ["Signum Remote"],
		"formation": {
			"coherency_distance": 2,
			"base_size": 25
		}
	}

static func create_enemy_unit_1() -> Dictionary:
	# Create an enemy unit for combat testing
	return {
		"id": "enemy_unit_1",
		"name": "Enemy Ork Boyz",
		"faction": "Orks",
		"player_id": 1,
		"unit_type": "Infantry",
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {
			"has_moved": false,
			"has_advanced": false,
			"has_shot": false,
			"has_charged": false,
			"has_fought": false,
			"is_selected": false
		},
		"stats": {
			"movement": 5,
			"weapon_skill": 3,
			"ballistic_skill": 5,
			"strength": 4,
			"toughness": 4,
			"wounds": 1,
			"attacks": 2,
			"leadership": 6,
			"armor_save": 6
		},
		"models": [
			create_model("nob", Vector2(500, 500)),
			create_model("boy_1", Vector2(520, 500)),
			create_model("boy_2", Vector2(540, 500)),
			create_model("boy_3", Vector2(500, 520)),
			create_model("boy_4", Vector2(520, 520)),
			create_model("boy_5", Vector2(540, 520))
		],
		"weapons": [
			{
				"name": "Shoota",
				"type": "ranged",
				"range": 18,
				"strength": 4,
				"ap": 0,
				"damage": 1,
				"shots": 2
			},
			{
				"name": "Choppa",
				"type": "melee",
				"strength": 4,
				"ap": 0,
				"damage": 1,
				"attacks": 2
			}
		],
		"abilities": ["Mob Rule"],
		"formation": {
			"coherency_distance": 2,
			"base_size": 25
		}
	}

static func create_model(model_id: String, position: Vector2) -> Dictionary:
	# Create a standard model with position
	return {
		"id": model_id,
		"position": {
			"x": position.x,
			"y": position.y
		},
		"wounds_remaining": 1,
		"is_alive": true,
		"equipment": [],
		"status_effects": []
	}

# Specialized state creators for specific testing scenarios

static func create_movement_test_state() -> Dictionary:
	# State configured for movement phase testing
	var state = create_test_game_state()
	state.current_phase = GameStateData.Phase.MOVEMENT
	
	# Reset movement flags
	for unit_id in state.units.keys():
		state.units[unit_id].flags.has_moved = false
		state.units[unit_id].flags.has_advanced = false
	
	return state

static func create_shooting_test_state() -> Dictionary:
	# State configured for shooting phase testing
	var state = create_test_game_state()
	state.current_phase = GameStateData.Phase.SHOOTING
	
	# Reset shooting flags
	for unit_id in state.units.keys():
		state.units[unit_id].flags.has_shot = false
	
	# Position units within shooting range
	state.units.test_unit_1.models[0].position = {"x": 100, "y": 100}
	state.units.enemy_unit_1.models[0].position = {"x": 150, "y": 100}  # 24" range
	
	return state

static func create_charge_test_state() -> Dictionary:
	# State configured for charge phase testing
	var state = create_test_game_state()
	state.current_phase = GameStateData.Phase.CHARGE
	
	# Reset charge flags
	for unit_id in state.units.keys():
		state.units[unit_id].flags.has_charged = false
	
	# Position units within charge range
	state.units.test_unit_1.models[0].position = {"x": 100, "y": 100}
	state.units.enemy_unit_1.models[0].position = {"x": 112, "y": 100}  # 12" charge range
	
	return state

static func create_fight_test_state() -> Dictionary:
	# State configured for fight phase testing
	var state = create_test_game_state()
	state.current_phase = GameStateData.Phase.FIGHT
	
	# Reset fight flags
	for unit_id in state.units.keys():
		state.units[unit_id].flags.has_fought = false
	
	# Position units in engagement range
	state.units.test_unit_1.models[0].position = {"x": 100, "y": 100}
	state.units.enemy_unit_1.models[0].position = {"x": 101, "y": 100}  # 1" engagement range
	
	return state

static func create_morale_test_state() -> Dictionary:
	# State configured for morale phase testing with casualties
	var state = create_test_game_state()
	state.current_phase = GameStateData.Phase.MORALE
	
	# Add some casualties to trigger morale tests
	var unit = state.units.test_unit_1
	unit.models[2].is_alive = false
	unit.models[2].wounds_remaining = 0
	unit.models[3].is_alive = false
	unit.models[3].wounds_remaining = 0
	
	return state

# Utility methods for creating specific test scenarios

static func create_deployment_scenario() -> Dictionary:
	# Create a deployment phase scenario
	var state = create_clean_state()
	state.current_phase = GameStateData.Phase.DEPLOYMENT
	
	# Add undeployed units
	state.units = {
		"deployment_unit_1": create_undeployed_unit("test_tactical"),
		"deployment_unit_2": create_undeployed_unit("test_devastator")
	}
	
	return state

static func create_undeployed_unit(unit_name: String) -> Dictionary:
	# Create a unit that hasn't been deployed yet
	var unit = create_test_unit_1()
	unit.id = unit_name
	unit.name = unit_name.capitalize()
	unit.status = GameStateData.UnitStatus.UNDEPLOYED
	
	# Clear positions for deployment
	for model in unit.models:
		model.position = {"x": -1, "y": -1}
	
	return unit

static func create_objective_markers() -> Array:
	# Create test objective markers
	return [
		{
			"id": "obj_1",
			"position": Vector2(250, 250),
			"controlled_by": -1,
			"value": 3
		},
		{
			"id": "obj_2", 
			"position": Vector2(750, 250),
			"controlled_by": -1,
			"value": 3
		},
		{
			"id": "obj_3",
			"position": Vector2(500, 500),
			"controlled_by": -1,
			"value": 5
		}
	]

static func create_terrain_features() -> Array:
	# Create test terrain features
	return [
		{
			"type": "wall",
			"position": Vector2(300, 300),
			"size": Vector2(100, 20),
			"blocks_line_of_sight": true,
			"provides_cover": true
		},
		{
			"type": "crater",
			"position": Vector2(600, 600),
			"size": Vector2(50, 50),
			"blocks_line_of_sight": false,
			"provides_cover": true
		}
	]

# Action creation helpers

static func create_movement_action(unit_id: String, model_id: String, to_position: Vector2) -> Dictionary:
	return {
		"type": "move_model",
		"actor_unit_id": unit_id,
		"payload": {
			"model_id": model_id,
			"from_position": Vector2.ZERO,  # Will be filled by test
			"to_position": to_position,
			"movement_type": "normal"
		}
	}

static func create_shooting_action(unit_id: String, target_unit_id: String, weapon_name: String = "Bolter") -> Dictionary:
	return {
		"type": "shoot",
		"actor_unit_id": unit_id,
		"payload": {
			"target_unit_id": target_unit_id,
			"weapon": weapon_name,
			"target_models": []  # Will be filled by test
		}
	}

static func create_charge_action(unit_id: String, target_unit_id: String) -> Dictionary:
	return {
		"type": "declare_charge",
		"actor_unit_id": unit_id,
		"payload": {
			"target_unit_ids": [target_unit_id]
		}
	}

static func create_fight_action(unit_id: String, target_unit_id: String) -> Dictionary:
	return {
		"type": "fight",
		"actor_unit_id": unit_id,
		"payload": {
			"target_unit_id": target_unit_id,
			"weapon": "Choppa"
		}
	}

# Validation helpers

static func validate_test_state(state: Dictionary) -> bool:
	# Basic validation for test state structure
	var required_keys = ["game_id", "current_phase", "units", "board"]
	
	for key in required_keys:
		if not state.has(key):
			print("Missing required key in test state: " + key)
			return false
	
	# Validate units structure
	for unit_id in state.units.keys():
		var unit = state.units[unit_id]
		if not validate_unit_structure(unit):
			print("Invalid unit structure for: " + unit_id)
			return false
	
	return true

static func validate_unit_structure(unit: Dictionary) -> bool:
	# Validate unit has required fields
	var required_fields = ["id", "name", "faction", "player_id", "models", "stats"]
	
	for field in required_fields:
		if not unit.has(field):
			return false
	
	# Validate models array
	if unit.models.size() == 0:
		return false
	
	return true
