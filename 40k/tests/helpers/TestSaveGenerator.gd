extends Node

# TestSaveGenerator - Generates test save files for deployment testing
# This ensures test saves always match the current StateSerializer format

const GameStateData = preload("res://autoloads/GameState.gd")

func generate_all_test_saves() -> void:
	print("=== Generating Test Save Files ===")

	generate_deployment_start()
	generate_deployment_player1_turn()
	generate_deployment_player2_turn()
	generate_deployment_with_terrain()
	generate_deployment_nearly_complete()

	print("=== Test Save Generation Complete ===")

# Generate deployment_start.w40ksave
# Start of deployment phase with all units undeployed
func generate_deployment_start() -> bool:
	print("Generating deployment_start.w40ksave...")

	var game_state = _create_base_deployment_state()

	# Save to file - use absolute file path
	var save_path = "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/saves/deployment_start.w40ksave"
	var success = _save_to_file(save_path, game_state)

	if success:
		print("✓ deployment_start.w40ksave created successfully")
	else:
		push_error("✗ Failed to create deployment_start.w40ksave")

	return success

# Generate deployment_player1_turn.w40ksave
# Deployment phase, Player 1's turn
func generate_deployment_player1_turn() -> bool:
	print("Generating deployment_player1_turn.w40ksave...")

	var game_state = _create_base_deployment_state()
	game_state.meta.active_player = 1

	# Save to file
	var save_path = "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/saves/deployment_player1_turn.w40ksave"
	var success = _save_to_file(save_path, game_state)

	if success:
		print("✓ deployment_player1_turn.w40ksave created successfully")
	else:
		push_error("✗ Failed to create deployment_player1_turn.w40ksave")

	return success

# Generate deployment_player2_turn.w40ksave
# Deployment phase, Player 2's turn
func generate_deployment_player2_turn() -> bool:
	print("Generating deployment_player2_turn.w40ksave...")

	var game_state = _create_base_deployment_state()
	game_state.meta.active_player = 2

	# Save to file
	var save_path = "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/saves/deployment_player2_turn.w40ksave"
	var success = _save_to_file(save_path, game_state)

	if success:
		print("✓ deployment_player2_turn.w40ksave created successfully")
	else:
		push_error("✗ Failed to create deployment_player2_turn.w40ksave")

	return success

# Generate deployment_with_terrain.w40ksave
# Deployment phase with terrain pieces
func generate_deployment_with_terrain() -> bool:
	print("Generating deployment_with_terrain.w40ksave...")

	var game_state = _create_base_deployment_state()

	# Add terrain pieces
	game_state.board.terrain = [
		{
			"id": "terrain_1",
			"position": Vector2(200.0, 400.0),
			"size": Vector2(80.0, 80.0),
			"type": "ruins",
			"blocks_los": false,
			"provides_cover": true
		},
		{
			"id": "terrain_2",
			"position": Vector2(1400.0, 1800.0),
			"size": Vector2(80.0, 80.0),
			"type": "ruins",
			"blocks_los": false,
			"provides_cover": true
		},
		{
			"id": "terrain_3",
			"position": Vector2(880.0, 1200.0),
			"size": Vector2(120.0, 60.0),
			"type": "obscuring",
			"blocks_los": true,
			"provides_cover": true
		}
	]

	# Save to file
	var save_path = "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/saves/deployment_with_terrain.w40ksave"
	var success = _save_to_file(save_path, game_state)

	if success:
		print("✓ deployment_with_terrain.w40ksave created successfully")
	else:
		push_error("✗ Failed to create deployment_with_terrain.w40ksave")

	return success

# Generate deployment_nearly_complete.w40ksave
# Almost done with deployment, only one unit left to deploy per player
func generate_deployment_nearly_complete() -> bool:
	print("Generating deployment_nearly_complete.w40ksave...")

	var game_state = _create_base_deployment_state()

	# Deploy most units for both players, leaving one undeployed each
	var unit_count_p1 = 0
	var unit_count_p2 = 0

	for unit_id in game_state.units:
		var unit = game_state.units[unit_id]

		if unit.owner == 1:
			unit_count_p1 += 1
			# Deploy all but the last unit for player 1
			if unit_count_p1 < game_state.units.size() / 2:
				_deploy_unit_at_position(unit, Vector2(400.0, 200.0 + unit_count_p1 * 100.0))
		elif unit.owner == 2:
			unit_count_p2 += 1
			# Deploy all but the last unit for player 2
			if unit_count_p2 < game_state.units.size() / 2:
				_deploy_unit_at_position(unit, Vector2(1400.0, 1900.0 - unit_count_p2 * 100.0))

	# Save to file
	var save_path = "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/saves/deployment_nearly_complete.w40ksave"
	var success = _save_to_file(save_path, game_state)

	if success:
		print("✓ deployment_nearly_complete.w40ksave created successfully")
	else:
		push_error("✗ Failed to create deployment_nearly_complete.w40ksave")

	return success

# Helper function to save game state to file
func _save_to_file(file_path: String, game_state: Dictionary) -> bool:
	# Add serialization metadata
	game_state["_serialization"] = {
		"version": "1.0.0",
		"timestamp": Time.get_unix_time_from_system(),
		"game_version": "1.0.0",
		"serializer": "StateSerializer"
	}

	# Serialize to JSON
	var json_string = JSON.stringify(game_state, "\t")
	if json_string.is_empty():
		push_error("Failed to serialize game state")
		return false

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open file for writing: " + file_path)
		return false

	file.store_string(json_string)
	file.close()
	return true

# Helper function to create base deployment state
func _create_base_deployment_state() -> Dictionary:
	var game_state = {
		"meta": {
			"game_id": "test_game_" + str(Time.get_unix_time_from_system()),
			"turn_number": 1,
			"battle_round": 1,
			"active_player": 1,
			"phase": GameStateData.Phase.DEPLOYMENT,
			"created_at": Time.get_unix_time_from_system(),
			"version": "1.0.0"
		},
		"board": {
			"size": {"width": 44, "height": 60},
			"deployment_zones": [
				{
					"player": 1,
					"poly": [
						Vector2(0, 0),
						Vector2(880, 0),
						Vector2(880, 240),
						Vector2(0, 240)
					]
				},
				{
					"player": 2,
					"poly": [
						Vector2(0, 1920),
						Vector2(880, 1920),
						Vector2(880, 2160),
						Vector2(0, 2160)
					]
				}
			],
			"objectives": [
				{
					"id": "obj_center",
					"position": Vector2(880.0, 1200.0),
					"radius_mm": 40
				},
				{
					"id": "obj_tl",
					"position": Vector2(400.0, 560.0),
					"radius_mm": 40
				},
				{
					"id": "obj_tr",
					"position": Vector2(1360.0, 560.0),
					"radius_mm": 40
				},
				{
					"id": "obj_bl",
					"position": Vector2(400.0, 1840.0),
					"radius_mm": 40
				},
				{
					"id": "obj_br",
					"position": Vector2(1360.0, 1840.0),
					"radius_mm": 40
				}
			],
			"terrain": [],
			"terrain_features": []
		},
		"units": _create_test_units(),
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"factions": {
			"1": {
				"name": "Adeptus Custodes",
				"detachment": "Shield Host",
				"points": 1000.0,
				"player_name": "Player 1",
				"team_name": ""
			},
			"2": {
				"name": "Orks",
				"detachment": "Waaagh!",
				"points": 1000.0,
				"player_name": "Player 2",
				"team_name": ""
			}
		},
		"phase_log": [],
		"history": []
	}

	return game_state

# Helper function to create test units
func _create_test_units() -> Dictionary:
	var units = {}

	# Player 1 units - use simple IDs that match test expectations
	units["unit_p1_1"] = _create_unit_data(
		"unit_p1_1",
		"Custodian Guard",
		1,
		3,
		40.0,
		{"wounds": 3.0, "toughness": 6.0, "save": 2.0, "invuln": 4.0}
	)

	units["unit_p1_2"] = _create_unit_data(
		"unit_p1_2",
		"Blade Champion",
		1,
		1,
		40.0,
		{"wounds": 6.0, "toughness": 6.0, "save": 2.0, "invuln": 4.0}
	)

	units["unit_p1_3"] = _create_unit_data(
		"unit_p1_3",
		"Witchseekers",
		1,
		3,
		32.0,
		{"wounds": 1.0, "toughness": 3.0, "save": 3.0}
	)

	# Player 2 units - use simple IDs that match test expectations
	units["unit_p2_1"] = _create_unit_data(
		"unit_p2_1",
		"Boyz",
		2,
		10,
		32.0,
		{"wounds": 1.0, "toughness": 5.0, "save": 6.0}
	)

	units["unit_p2_2"] = _create_unit_data(
		"unit_p2_2",
		"Warboss",
		2,
		1,
		40.0,
		{"wounds": 6.0, "toughness": 5.0, "save": 4.0}
	)

	units["unit_p2_3"] = _create_unit_data(
		"unit_p2_3",
		"Battlewagon",
		2,
		1,
		180.0,
		{"wounds": 16.0, "toughness": 10.0, "save": 3.0},
		"rectangular",
		{"length": 180.0, "width": 110.0}
	)

	return units

# Helper function to create unit data structure
func _create_unit_data(
	id: String,
	name: String,
	owner: int,
	model_count: int,
	base_mm: float,
	stats: Dictionary,
	base_type: String = "round",
	base_dimensions: Dictionary = {}
) -> Dictionary:
	var unit = {
		"id": id,
		"owner": owner,
		"squad_id": id,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"disembarked_this_phase": false,
		"embarked_in": null,
		"flags": {},
		"meta": {
			"name": name,
			"points": 100.0,
			"stats": {
				"move": 6.0,
				"toughness": stats.get("toughness", 4.0),
				"save": stats.get("save", 4.0),
				"wounds": stats.get("wounds", 1.0),
				"leadership": 6.0,
				"objective_control": 1.0
			},
			"keywords": ["INFANTRY"],
			"abilities": [],
			"weapons": [],
			"wargear": [],
			"unit_composition": [{"line": 1.0, "description": "%s x%d" % [name, model_count]}],
			"enhancements": [],
			"is_warlord": false
		},
		"models": []
	}

	# Add invuln save if present
	if stats.has("invuln"):
		unit.meta.stats["invuln"] = stats.invuln

	# Create models
	for i in range(model_count):
		var model = {
			"id": "m" + str(i + 1),
			"position": null,
			"alive": true,
			"wounds": stats.get("wounds", 1.0),
			"current_wounds": stats.get("wounds", 1.0),
			"base_mm": base_mm,
			"status_effects": []
		}

		# Add base type and dimensions for non-round bases
		if base_type != "round":
			model["base_type"] = base_type
			if not base_dimensions.is_empty():
				model["base_dimensions"] = base_dimensions

		unit.models.append(model)

	return unit

# Helper function to deploy a unit at a specific position
func _deploy_unit_at_position(unit: Dictionary, position: Vector2) -> void:
	unit.status = GameStateData.UnitStatus.DEPLOYED

	# Deploy all models in the unit
	for i in range(unit.models.size()):
		var model = unit.models[i]
		# Position models in a line
		model.position = position + Vector2(i * 50.0, 0)
