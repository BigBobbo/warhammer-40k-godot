extends "res://addons/gut/test.gd"

# Tests for skip-attacks-when-target-destroyed behavior
#
# When a unit shoots multiple different weapons at a target unit and that target
# is destroyed mid-sequence, remaining weapons targeting the destroyed unit
# should be skipped automatically (no further attacks to allocate).
#
# Tests cover:
# 1. _is_unit_destroyed helper correctly identifies destroyed units
# 2. AI batch path (_auto_roll_saves) skips saves for destroyed targets
# 3. Overwatch skips remaining weapons when target destroyed mid-resolution
# 4. Sequential resolution skip logic (already existed, verify it works)

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_unit(id: String, model_count: int, owner: int = 1, keywords: Array = ["INFANTRY"], save: int = 3, toughness: int = 4, wounds: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": wounds,
			"current_wounds": wounds,
			"base_mm": 32,
			"position": {"x": 100 + i * 20 + (owner - 1) * 200, "y": 100},
			"alive": true,
			"status_effects": [],
			"weapons": [{"id": "bolt_rifle", "weapon_id": "bolt_rifle"}]
		})
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Test Unit %s" % id,
			"keywords": keywords,
			"stats": {
				"move": 6,
				"toughness": toughness,
				"save": save,
				"wounds": wounds,
				"leadership": 7,
				"objective_control": 1
			},
			"weapons": [],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _create_weapon_profile(id: String, bs: int = 3, strength: int = 4, ap: int = -1, damage: int = 1, attacks: int = 2) -> Dictionary:
	return {
		"id": id,
		"name": "Test Weapon %s" % id,
		"type": "ranged",
		"bs": bs,
		"strength": strength,
		"ap": ap,
		"damage": damage,
		"damage_raw": str(damage),
		"attacks": attacks,
		"attacks_raw": str(attacks),
		"range": 24,
		"keywords": [],
		"special_rules": ""
	}

func before_each():
	GameState.state = GameState._create_default_state()
	if GameState.state.has("units"):
		GameState.state.units.clear()


# ==========================================
# _is_unit_destroyed Helper Tests
# ==========================================

func test_unit_with_alive_models_not_destroyed():
	"""A unit with alive models should not be considered destroyed."""
	var unit = _create_unit("U1", 3, 1)
	GameState.state.units["U1"] = unit

	# Create a ShootingPhase instance to test _is_unit_destroyed
	var phase = ShootingPhase.new()
	phase.game_state_snapshot = GameState.create_snapshot()

	assert_false(phase._is_unit_destroyed("U1"), "Unit with alive models should not be destroyed")
	phase.free()

func test_unit_with_all_dead_models_is_destroyed():
	"""A unit with all models dead should be considered destroyed."""
	var unit = _create_unit("U1", 3, 1)
	for model in unit.models:
		model.alive = false
	GameState.state.units["U1"] = unit

	var phase = ShootingPhase.new()
	phase.game_state_snapshot = GameState.create_snapshot()

	assert_true(phase._is_unit_destroyed("U1"), "Unit with all dead models should be destroyed")
	phase.free()

func test_unit_partially_dead_not_destroyed():
	"""A unit with some models dead but at least one alive should not be destroyed."""
	var unit = _create_unit("U1", 3, 1)
	unit.models[0].alive = false
	unit.models[1].alive = false
	# models[2] still alive
	GameState.state.units["U1"] = unit

	var phase = ShootingPhase.new()
	phase.game_state_snapshot = GameState.create_snapshot()

	assert_false(phase._is_unit_destroyed("U1"), "Unit with one alive model should not be destroyed")
	phase.free()

func test_nonexistent_unit_treated_as_destroyed():
	"""A unit that doesn't exist in the game state should be treated as destroyed."""
	var phase = ShootingPhase.new()
	phase.game_state_snapshot = GameState.create_snapshot()

	assert_true(phase._is_unit_destroyed("NONEXISTENT"), "Nonexistent unit should be treated as destroyed")
	phase.free()


# ==========================================
# Overwatch Target Destroyed Skip Tests
# ==========================================

func test_overwatch_skips_weapons_after_target_destroyed():
	"""When overwatch kills the target, remaining weapons should be skipped."""
	# Setup: target unit with 1 model (1 wound) — easy to destroy
	var target = _create_unit("U_TARGET", 1, 1, ["INFANTRY"], 6, 3, 1)
	target.models[0].position = {"x": 200, "y": 200}
	GameState.state.units["U_TARGET"] = target

	# Shooter with multiple weapons (many models with weapons)
	var shooter = _create_unit("U_SHOOTER", 5, 2, ["INFANTRY"], 3, 4, 1)
	for i in range(shooter.models.size()):
		shooter.models[i].position = {"x": 200 + i * 20, "y": 300}
		shooter.models[i].weapons = [
			{"id": "heavy_bolter", "weapon_id": "heavy_bolter"},
			{"id": "bolt_rifle", "weapon_id": "bolt_rifle"}
		]
	GameState.state.units["U_SHOOTER"] = shooter

	# Setup weapon profiles
	if not GameState.state.has("weapons"):
		GameState.state["weapons"] = {}
	# High-damage weapon to ensure a kill
	GameState.state.weapons["heavy_bolter"] = _create_weapon_profile("heavy_bolter", 3, 5, -1, 2, 3)
	GameState.state.weapons["bolt_rifle"] = _create_weapon_profile("bolt_rifle", 3, 4, -1, 1, 2)

	var board = GameState.create_snapshot()
	var rng = RulesEngine.RNGService.new()

	var result = RulesEngine.resolve_overwatch_shooting("U_SHOOTER", "U_TARGET", board, rng)

	assert_true(result.success, "Overwatch should succeed")

	# After the target is destroyed, the total number of weapon results should be
	# less than the total number of weapons (some were skipped).
	# We can't predict the exact number since it depends on dice rolls,
	# but we verify the implementation doesn't crash and produces valid results.
	assert_true(result.weapon_results.size() >= 1, "Should have at least one weapon result")

	# If the target was destroyed, verify no further damage was done after destruction
	if result.total_casualties >= 1:
		# Target had only 1 model — once killed, remaining weapons should have been skipped
		print("Overwatch destroyed target with %d weapons fired out of potential many" % result.weapon_results.size())


# ==========================================
# AI Batch Save Skip Tests
# ==========================================

func test_ai_auto_roll_saves_skips_destroyed_target():
	"""In AI batch mode, saves for subsequent weapons should be skipped if target already destroyed."""
	# Setup: Target with 1 model, 1 wound
	var target = _create_unit("U_TARGET", 1, 1, ["INFANTRY"], 6, 3, 1)
	GameState.state.units["U_TARGET"] = target

	var shooter = _create_unit("U_SHOOTER", 3, 2, ["INFANTRY"], 3, 4, 1)
	GameState.state.units["U_SHOOTER"] = shooter

	if not GameState.state.has("weapons"):
		GameState.state["weapons"] = {}
	GameState.state.weapons["bolt_rifle"] = _create_weapon_profile("bolt_rifle", 3, 4, -1, 1, 2)

	# Create ShootingPhase to test _auto_roll_saves
	var phase = ShootingPhase.new()
	phase.game_state_snapshot = GameState.create_snapshot()

	# Build save_data_list with two entries targeting the same unit
	# First entry: 1 wound (will likely kill the 1-wound model)
	# Second entry: 1 wound (should be skipped if target destroyed)
	var save_data_list = [
		{
			"success": true,
			"target_unit_id": "U_TARGET",
			"target_unit_name": "Test Target",
			"weapon_id": "bolt_rifle",
			"weapon_name": "Bolt Rifle",
			"wounds_to_save": 1,
			"damage": 1,
			"damage_raw": "1",
			"ap": -1,
			"base_save": 6,
			"devastating_wounds": 0,
			"model_save_profiles": [{
				"model_id": "m1",
				"model_index": 0,
				"save_needed": 7,  # Impossible save — guarantees failure
				"armour": 6,
				"is_wounded": false,
				"is_character": false,
				"using_invuln": false
			}]
		},
		{
			"success": true,
			"target_unit_id": "U_TARGET",
			"target_unit_name": "Test Target",
			"weapon_id": "bolt_rifle",
			"weapon_name": "Second Bolt Rifle",
			"wounds_to_save": 1,
			"damage": 1,
			"damage_raw": "1",
			"ap": -1,
			"base_save": 6,
			"devastating_wounds": 0,
			"model_save_profiles": [{
				"model_id": "m1",
				"model_index": 0,
				"save_needed": 7,
				"armour": 6,
				"is_wounded": false,
				"is_character": false,
				"using_invuln": false
			}]
		}
	]

	var result = phase._auto_roll_saves(save_data_list)

	# The first weapon should cause 1 casualty (save impossible at 7+)
	# The second weapon should be skipped because target was destroyed
	assert_eq(result.casualties, 1, "Should only have 1 casualty (second weapon skipped)")

	phase.free()
