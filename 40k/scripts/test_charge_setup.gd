extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# Test helper to set up units ready for charge phase testing

static func setup_test_units_for_charge() -> void:
	print("Setting up test units for charge phase...")
	
	# Ensure we have units
	if GameState.state.get("units", {}).is_empty():
		print("No units found, creating test units...")
		_create_test_units()
	
	# Set up Player 1 units (charging units)
	var p1_unit = "U_INTERCESSORS_A"
	if GameState.state.units.has(p1_unit):
		GameState.state.units[p1_unit].status = GameStateData.UnitStatus.MOVED
		GameState.state.units[p1_unit].owner = 1
		GameState.state.units[p1_unit].flags = {}  # Clear any blocking flags
		
		# Deploy models at specific positions (left side of board)
		var models = GameState.state.units[p1_unit].get("models", [])
		for i in range(models.size()):
			models[i].position = {"x": 200 + i * 40, "y": 600}
			models[i].alive = true
			models[i].current_wounds = models[i].get("wounds", 1)
		
		print("Set up ", p1_unit, " for Player 1 at left side")
	
	# Set up Player 2 units (target units)
	var p2_unit = "U_BOYZ_A"
	if GameState.state.units.has(p2_unit):
		GameState.state.units[p2_unit].status = GameStateData.UnitStatus.DEPLOYED
		GameState.state.units[p2_unit].owner = 2
		GameState.state.units[p2_unit].flags = {}
		
		# Deploy models at specific positions (right side, within 12" charge range)
		var models = GameState.state.units[p2_unit].get("models", [])
		for i in range(models.size()):
			models[i].position = {"x": 500 + i * 30, "y": 600}
			models[i].alive = true
			models[i].current_wounds = models[i].get("wounds", 1)
		
		print("Set up ", p2_unit, " for Player 2 at right side")
	
	# Set active player to 1 (who will be charging)
	GameState.state.meta.active_player = 1
	
	print("Test units ready for charge phase!")
	print("Player 1 should be able to charge Player 2's units")

static func _create_test_units() -> void:
	# Create basic test units if none exist
	GameState.state.units = {
		"U_INTERCESSORS_A": {
			"id": "U_INTERCESSORS_A",
			"owner": 1,
			"status": GameStateData.UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Intercessor Squad Alpha",
				"keywords": ["INFANTRY", "IMPERIUM", "SPACE_MARINES"],
				"stats": {
					"movement": 6,
					"toughness": 4,
					"save": 3,
					"wounds": 2,
					"leadership": 6,
					"oc": 2
				}
			},
			"models": [
				{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32},
				{"id": "m2", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32},
				{"id": "m3", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32},
				{"id": "m4", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32},
				{"id": "m5", "alive": true, "wounds": 2, "current_wounds": 2, "base_mm": 32}
			],
			"flags": {}
		},
		"U_BOYZ_A": {
			"id": "U_BOYZ_A",
			"owner": 2,
			"status": GameStateData.UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Boyz Mob Alpha",
				"keywords": ["INFANTRY", "ORK"],
				"stats": {
					"movement": 6,
					"toughness": 5,
					"save": 6,
					"wounds": 1,
					"leadership": 7,
					"oc": 2
				}
			},
			"models": [
				{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32},
				{"id": "m2", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32},
				{"id": "m3", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32},
				{"id": "m4", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32},
				{"id": "m5", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32}
			],
			"flags": {}
		}
	}
