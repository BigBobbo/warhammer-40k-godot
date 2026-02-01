extends "res://addons/gut/test.gd"
const GameStateData = preload("res://autoloads/GameState.gd")

# Integration tests for army loading functionality
# Tests the full pipeline from JSON files to game state

var original_game_state: Dictionary

func before_each():
	# Ensure autoloads available
	AutoloadHelper.ensure_autoloads_loaded(get_tree())

	# Backup original game state
	if GameState:
		original_game_state = GameState.state.duplicate(true)

func after_each():
	# Restore original game state
	if GameState and not original_game_state.is_empty():
		GameState.state = original_game_state.duplicate(true)

func test_army_manager_initialization():
	assert_not_null(ArmyListManager, "ArmyListManager should be available as autoload")
	assert_true(ArmyListManager.get_available_armies().size() > 0, "Should find available armies")

func test_load_adeptus_custodes_army():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	
	assert_false(army.is_empty(), "Should successfully load adeptus_custodes army")
	assert_true(army.has("faction"), "Army should have faction data")
	assert_true(army.has("units"), "Army should have units")
	
	# Check faction data
	var faction = army.faction
	assert_eq(faction.name, "Adeptus Custodes", "Faction name should be correct")
	
	# Check units exist
	var units = army.units
	assert_true(units.size() > 0, "Should have units in the army")
	
	# Test specific unit exists
	assert_true(units.has("U_BLADE_CHAMPION_A"), "Should have Blade Champion unit")
	
	# Check unit structure
	var blade_champion = units["U_BLADE_CHAMPION_A"]
	assert_eq(blade_champion.owner, 1, "Unit owner should be set correctly")
	assert_true(blade_champion.has("meta"), "Unit should have meta data")
	assert_true(blade_champion.has("models"), "Unit should have models")
	
	# Check meta data
	var meta = blade_champion.meta
	assert_eq(meta.name, "Blade Champion", "Unit name should be correct")
	assert_true(meta.has("weapons"), "Unit should have weapons")
	assert_true(meta.has("abilities"), "Unit should have abilities")
	assert_true(meta.has("stats"), "Unit should have stats")

func test_load_space_marines_army():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("space_marines", 1)
	
	assert_false(army.is_empty(), "Should successfully load space_marines army")
	assert_true(army.has("units"), "Army should have units")
	
	var units = army.units
	assert_true(units.has("U_INTERCESSORS_A"), "Should have Intercessor unit")
	assert_true(units.has("U_TACTICAL_A"), "Should have Tactical unit")

func test_load_orks_army():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("orks", 2)
	
	assert_false(army.is_empty(), "Should successfully load orks army")
	assert_true(army.has("units"), "Army should have units")
	
	var units = army.units
	assert_true(units.has("U_BOYZ_A"), "Should have Boyz unit")
	assert_true(units.has("U_GRETCHIN_A"), "Should have Gretchin unit")
	
	# Check that owner is set correctly
	for unit_id in units:
		assert_eq(units[unit_id].owner, 2, "Ork units should have owner 2")

func test_apply_army_to_game_state():
	if not ArmyListManager or not GameState:
		pending("Required autoloads not available")
		return
	
	# Start with empty game state
	GameState.state = {
		"units": {},
		"factions": {},
		"meta": {"active_player": 1}
	}
	
	# Load and apply Custodes army
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	assert_false(army.is_empty(), "Should load army successfully")
	
	ArmyListManager.apply_army_to_game_state(army, 1)
	
	# Check that units were added to GameState
	var game_units = GameState.state.units
	assert_true(game_units.size() > 0, "GameState should have units after applying army")
	assert_true(game_units.has("U_BLADE_CHAMPION_A"), "Specific unit should be in GameState")
	
	# Check that faction was set
	assert_true(GameState.state.factions.has("1"), "Faction should be set for player 1")
	assert_eq(GameState.state.factions["1"].name, "Adeptus Custodes", "Faction name should be correct")

func test_weapon_data_parsing_integration():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	assert_false(army.is_empty(), "Should load army")
	
	# Get a unit with weapons
	var blade_champion = army.units.get("U_BLADE_CHAMPION_A", {})
	assert_false(blade_champion.is_empty(), "Should have Blade Champion unit")
	
	var weapons = blade_champion.get("meta", {}).get("weapons", [])
	assert_true(weapons.size() > 0, "Blade Champion should have weapons")
	
	# Test parsing a weapon
	var weapon = weapons[0]
	var parsed_weapon = RulesEngine.parse_weapon_stats(weapon)
	
	assert_true(parsed_weapon.has("attacks"), "Parsed weapon should have attacks")
	assert_true(parsed_weapon.has("range"), "Parsed weapon should have range")
	assert_true(parsed_weapon.has("strength"), "Parsed weapon should have strength")
	assert_true(parsed_weapon.has("ap"), "Parsed weapon should have AP")
	assert_true(parsed_weapon.has("damage"), "Parsed weapon should have damage")

func test_game_initialization_with_armies():
	if not GameState or not ArmyListManager:
		pending("Required autoloads not available")
		return
	
	# Reinitialize GameState to trigger army loading
	GameState.initialize_default_state()
	
	# Check that units were loaded
	var units = GameState.state.units
	assert_true(units.size() > 0, "GameState should have units after initialization")
	
	# Check for Custodes units (should be loaded for player 1)
	var player1_units = []
	var player2_units = []
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.owner == 1:
			player1_units.append(unit_id)
		elif unit.owner == 2:
			player2_units.append(unit_id)
	
	assert_true(player1_units.size() > 0, "Should have units for player 1")
	assert_true(player2_units.size() > 0, "Should have units for player 2")
	
	# Check factions were set
	var factions = GameState.state.get("factions", {})
	assert_true(factions.has("1"), "Should have faction for player 1")
	assert_true(factions.has("2"), "Should have faction for player 2")

func test_invalid_army_fallback():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	# Try to load a non-existent army
	var army = ArmyListManager.load_army_list("nonexistent_army", 1)
	
	assert_true(army.is_empty(), "Should return empty dictionary for non-existent army")

func test_army_validation_with_real_data():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("space_marines", 1)
	assert_false(army.is_empty(), "Should load space marines army")
	
	var validation_result = ArmyListManager.validate_army_structure(army)
	assert_true(validation_result.valid, "Real army data should pass validation")
	assert_eq(validation_result.errors.size(), 0, "Should have no validation errors")

func test_unit_status_conversion():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	assert_false(army.is_empty(), "Should load army")
	
	# Check that string status was converted to enum
	for unit_id in army.units:
		var unit = army.units[unit_id]
		assert_true(unit.status is int, "Status should be converted to integer enum")
		assert_eq(unit.status, GameStateData.UnitStatus.UNDEPLOYED, "Status should be UNDEPLOYED")

func test_model_structure_integrity():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var army = ArmyListManager.load_army_list("adeptus_custodes", 1)
	assert_false(army.is_empty(), "Should load army")
	
	# Check model structure for each unit
	for unit_id in army.units:
		var unit = army.units[unit_id]
		assert_true(unit.has("models"), "Unit should have models")
		
		var models = unit.models
		assert_true(models is Array, "Models should be an array")
		assert_true(models.size() > 0, "Unit should have at least one model")
		
		for model in models:
			assert_true(model.has("id"), "Model should have id")
			assert_true(model.has("wounds"), "Model should have wounds")
			assert_true(model.has("current_wounds"), "Model should have current_wounds")
			assert_true(model.has("base_mm"), "Model should have base_mm")
			assert_true(model.has("alive"), "Model should have alive flag")

# Performance test for large army loading
func test_army_loading_performance():
	if not ArmyListManager:
		pending("ArmyListManager not available")
		return
	
	var start_time = Time.get_ticks_msec()
	
	# Load multiple armies
	var armies = ["adeptus_custodes", "space_marines", "orks"]
	for army_name in armies:
		var army = ArmyListManager.load_army_list(army_name, 1)
		assert_false(army.is_empty(), "Should load " + army_name)
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	assert_true(duration < 1000, "Army loading should complete in under 1 second")
	print("Army loading performance: ", duration, "ms for ", armies.size(), " armies")
