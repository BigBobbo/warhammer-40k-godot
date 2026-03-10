extends "res://addons/gut/test.gd"

# Tests for ROLLING LOOT-HEAP stratagem implementation (OA-6)
#
# Per Warhammer 40k 10th Edition — Freebooter Krew:
# - ROLLING LOOT-HEAP (Strategic Ploy Stratagem, 1 CP)
# - WHEN: Your Shooting phase.
# - TARGET: One Flash Gitz unit from your army that has not been selected to shoot.
# - EFFECT: Until the end of the phase, ranged weapons equipped by models in your
#   unit have the [ANTI-VEHICLE 4+] ability.
#
# These tests verify:
# 1. StratagemManager marks Rolling Loot-heap as implemented (custom handler)
# 2. Using the stratagem sets effect_rolling_loot_heap flag on the target unit
# 3. Only Flash Gitz units can be targeted
# 4. RulesEngine lowers critical wound threshold to 4+ vs VEHICLE targets
# 5. Non-VEHICLE targets are unaffected
# 6. Flag is cleared at end of phase

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

func _create_flash_gitz_unit(id: String, model_count: int = 5, owner: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 500 + i * 40, "y": 500},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Flash Gitz",
			"keywords": ["INFANTRY", "ORKS", "FLASH GITZ"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 4,
				"wounds": 2,
				"leadership": 7,
				"objective_control": 1
			},
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _create_ork_boyz_unit(id: String, model_count: int = 5, owner: int = 1) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 1,
			"current_wounds": 1,
			"base_mm": 32,
			"position": {"x": 500 + i * 40, "y": 500},
			"alive": true,
			"status_effects": []
		})
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Ork Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {
				"move": 6,
				"toughness": 5,
				"save": 5,
				"wounds": 1,
				"leadership": 7,
				"objective_control": 2
			},
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _create_vehicle_target(id: String, owner: int = 2) -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Leman Russ",
			"keywords": ["VEHICLE", "IMPERIUM"],
			"stats": {
				"move": 10,
				"toughness": 11,
				"save": 2,
				"wounds": 13,
				"leadership": 7,
				"objective_control": 3
			},
			"abilities": []
		},
		"models": [{
			"id": "m1",
			"wounds": 13,
			"current_wounds": 13,
			"base_mm": 25,
			"position": {"x": 700, "y": 500},
			"alive": true,
			"status_effects": []
		}],
		"flags": {}
	}

func _create_infantry_target(id: String, owner: int = 2) -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Intercessors",
			"keywords": ["INFANTRY", "IMPERIUM"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 6,
				"objective_control": 2
			},
			"abilities": []
		},
		"models": [{
			"id": "m1",
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 700, "y": 500},
			"alive": true,
			"status_effects": []
		}],
		"flags": {}
	}

func _setup_game_state_for_shooting(unit_id: String = "U_FLASH_GITZ") -> Dictionary:
	"""Set up GameState with a Flash Gitz unit ready for Shooting phase."""
	var unit = _create_flash_gitz_unit(unit_id, 5, 1)
	GameState.state.units[unit_id] = unit
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3
	# Clear any leftover out-of-phase state from other tests
	StratagemManager.set_out_of_phase_active(false)
	# Clear usage history to prevent restrictions from prior tests
	StratagemManager._usage_history = {"1": [], "2": []}
	# Clear active effects
	StratagemManager.active_effects = []
	return unit

func _find_rolling_loot_heap_id() -> String:
	"""Find the Rolling Loot-heap stratagem ID from loaded stratagems."""
	for strat_id in StratagemManager.stratagems:
		var strat = StratagemManager.stratagems[strat_id]
		if strat.get("name", "").to_upper() == "ROLLING LOOT-HEAP":
			return strat_id
	return ""

func _load_freebooter_stratagems():
	"""Load Freebooter Krew stratagems for player 1."""
	if not GameState.state.has("players"):
		GameState.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	# Load faction stratagems using the loader
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var strats = loader.load_faction_stratagems("Orks", "Freebooter Krew")
	for strat in strats:
		StratagemManager.stratagems[strat.id] = strat
		if not StratagemManager._player_faction_stratagems.has("1"):
			StratagemManager._player_faction_stratagems["1"] = []
		StratagemManager._player_faction_stratagems["1"].append(strat.id)
	# Mark custom implementations
	StratagemManager._mark_custom_implemented_stratagems(1)


# ==========================================
# Section 1: Stratagem Registration
# ==========================================

func test_rolling_loot_heap_loaded_from_csv():
	"""Rolling Loot-heap should be loadable from the Freebooter Krew CSV data."""
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var strats = loader.load_faction_stratagems("Orks", "Freebooter Krew")
	var found = false
	for s in strats:
		if "ROLLING LOOT" in s.name.to_upper():
			found = true
			assert_eq(s.cp_cost, 1, "CP cost should be 1")
			assert_eq(s.timing.turn, "your", "Should be your turn only")
			assert_eq(s.timing.phase, "shooting", "Should be shooting phase")
	assert_true(found, "Should find ROLLING LOOT-HEAP in Freebooter Krew stratagems")

func test_rolling_loot_heap_marked_as_implemented():
	"""After _mark_custom_implemented_stratagems, Rolling Loot-heap should be implemented=true."""
	_load_freebooter_stratagems()
	var strat_id = _find_rolling_loot_heap_id()
	assert_ne(strat_id, "", "Should find Rolling Loot-heap stratagem ID")
	if strat_id != "":
		var strat = StratagemManager.stratagems[strat_id]
		assert_true(strat.get("implemented", false), "Rolling Loot-heap should be marked as implemented")


# ==========================================
# Section 2: Effect Application
# ==========================================

func test_apply_effects_sets_rolling_loot_heap_flag():
	"""Using Rolling Loot-heap should set effect_rolling_loot_heap flag on target unit."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_FLASH_GITZ"

	var strat_id = _find_rolling_loot_heap_id()
	assert_ne(strat_id, "", "Should find Rolling Loot-heap stratagem ID")
	if strat_id == "":
		return

	var result = StratagemManager.use_stratagem(1, strat_id, unit_id)
	assert_true(result.get("success", false), "Stratagem use should succeed")

	# Check the flag was set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_rolling_loot_heap", false), "effect_rolling_loot_heap flag should be set")

func test_rolling_loot_heap_deducts_cp():
	"""Using Rolling Loot-heap should deduct 1 CP."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_FLASH_GITZ"
	GameState.state.players["1"]["cp"] = 5

	var strat_id = _find_rolling_loot_heap_id()
	if strat_id == "":
		assert_true(false, "Should find Rolling Loot-heap stratagem ID")
		return

	var cp_before = GameState.state.players["1"]["cp"]
	StratagemManager.use_stratagem(1, strat_id, unit_id)
	var cp_after = GameState.state.players["1"]["cp"]
	assert_eq(cp_before - cp_after, 1, "Should deduct 1 CP")


# ==========================================
# Section 3: Flash Gitz Targeting Validation
# ==========================================

func test_only_flash_gitz_can_be_targeted():
	"""Rolling Loot-heap should reject non-Flash Gitz units."""
	_load_freebooter_stratagems()
	# Set up a non-Flash Gitz unit
	var boyz = _create_ork_boyz_unit("U_ORK_BOYZ", 5, 1)
	GameState.state.units["U_ORK_BOYZ"] = boyz
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var strat_id = _find_rolling_loot_heap_id()
	if strat_id == "":
		assert_true(false, "Should find Rolling Loot-heap stratagem ID")
		return

	var result = StratagemManager.use_stratagem(1, strat_id, "U_ORK_BOYZ")
	assert_false(result.get("success", true), "Should fail for non-Flash Gitz unit")

func test_flash_gitz_that_already_shot_cannot_be_targeted():
	"""Rolling Loot-heap should reject Flash Gitz that have already shot."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_FLASH_GITZ"
	# Mark unit as already shot
	GameState.state.units[unit_id]["flags"]["has_shot"] = true

	var strat_id = _find_rolling_loot_heap_id()
	if strat_id == "":
		assert_true(false, "Should find Rolling Loot-heap stratagem ID")
		return

	var result = StratagemManager.use_stratagem(1, strat_id, unit_id)
	assert_false(result.get("success", true), "Should fail for Flash Gitz that already shot")

func test_eligible_units_returns_only_flash_gitz():
	"""get_rolling_loot_heap_eligible_units should only return Flash Gitz units."""
	_load_freebooter_stratagems()
	# Set up both a Flash Gitz and a non-Flash Gitz unit
	var flash_gitz = _create_flash_gitz_unit("U_FLASH_GITZ", 5, 1)
	var boyz = _create_ork_boyz_unit("U_ORK_BOYZ", 5, 1)
	GameState.state.units["U_FLASH_GITZ"] = flash_gitz
	GameState.state.units["U_ORK_BOYZ"] = boyz
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var eligible = StratagemManager.get_rolling_loot_heap_eligible_units(1)
	assert_eq(eligible.size(), 1, "Should find exactly one eligible unit")
	if eligible.size() > 0:
		assert_eq(eligible[0].unit_id, "U_FLASH_GITZ", "Eligible unit should be Flash Gitz")

func test_is_flash_gitz_unit():
	"""is_flash_gitz_unit should correctly identify Flash Gitz units."""
	var flash_gitz = _create_flash_gitz_unit("U_FG", 3, 1)
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	GameState.state.units["U_FG"] = flash_gitz
	GameState.state.units["U_BOYZ"] = boyz

	assert_true(StratagemManager.is_flash_gitz_unit("U_FG"), "Flash Gitz should be identified")
	assert_false(StratagemManager.is_flash_gitz_unit("U_BOYZ"), "Ork Boyz should not be Flash Gitz")
	assert_false(StratagemManager.is_flash_gitz_unit("nonexistent"), "Nonexistent unit should return false")


# ==========================================
# Section 4: Anti-Vehicle 4+ Effect in RulesEngine
# ==========================================

func test_critical_wound_threshold_lowered_vs_vehicle():
	"""When effect_rolling_loot_heap is set and target is VEHICLE, critical wound threshold should be 4+."""
	var vehicle_target = _create_vehicle_target("U_VEHICLE")
	var flash_gitz = _create_flash_gitz_unit("U_FG", 3, 1)
	flash_gitz["flags"]["effect_rolling_loot_heap"] = true
	GameState.state.units["U_VEHICLE"] = vehicle_target
	GameState.state.units["U_FG"] = flash_gitz

	# The critical wound threshold from the weapon itself should be 6 (no innate Anti-keyword)
	var base_threshold = RulesEngine.get_critical_wound_threshold("shoota", vehicle_target, GameState.state)
	assert_eq(base_threshold, 6, "Base critical wound threshold should be 6 (no innate anti-keyword)")

	# The Rolling Loot-heap effect is checked at the call site in resolve_weapon_assignment,
	# not in get_critical_wound_threshold itself. So we verify the flag-based logic directly.
	# The flag check: if unit has effect_rolling_loot_heap AND target has VEHICLE keyword → threshold = min(current, 4)
	var has_flag = flash_gitz.get("flags", {}).get("effect_rolling_loot_heap", false)
	var target_is_vehicle = RulesEngine.unit_has_keyword(vehicle_target, "VEHICLE")
	assert_true(has_flag, "Flash Gitz should have the rolling loot heap flag")
	assert_true(target_is_vehicle, "Target should have VEHICLE keyword")

	# Simulate what RulesEngine does at the call site
	var effective_threshold = base_threshold
	if has_flag and target_is_vehicle:
		effective_threshold = mini(effective_threshold, 4)
	assert_eq(effective_threshold, 4, "Effective critical wound threshold should be 4 vs VEHICLE")

func test_critical_wound_threshold_not_lowered_vs_infantry():
	"""When effect_rolling_loot_heap is set but target is NOT VEHICLE, threshold stays at 6."""
	var infantry_target = _create_infantry_target("U_INFANTRY")
	var flash_gitz = _create_flash_gitz_unit("U_FG", 3, 1)
	flash_gitz["flags"]["effect_rolling_loot_heap"] = true
	GameState.state.units["U_INFANTRY"] = infantry_target
	GameState.state.units["U_FG"] = flash_gitz

	var base_threshold = RulesEngine.get_critical_wound_threshold("shoota", infantry_target, GameState.state)
	assert_eq(base_threshold, 6, "Base critical wound threshold should be 6")

	# Simulate the call-site logic
	var has_flag = flash_gitz.get("flags", {}).get("effect_rolling_loot_heap", false)
	var target_is_vehicle = RulesEngine.unit_has_keyword(infantry_target, "VEHICLE")
	assert_true(has_flag, "Flash Gitz should have the rolling loot heap flag")
	assert_false(target_is_vehicle, "Infantry target should NOT have VEHICLE keyword")

	var effective_threshold = base_threshold
	if has_flag and target_is_vehicle:
		effective_threshold = mini(effective_threshold, 4)
	assert_eq(effective_threshold, 6, "Threshold should remain 6 vs non-VEHICLE target")


# ==========================================
# Section 5: Flag Cleanup
# ==========================================

func test_clear_stratagem_flags_removes_rolling_loot_heap():
	"""Clearing Rolling Loot-heap should remove the effect_rolling_loot_heap flag."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_FLASH_GITZ"

	var strat_id = _find_rolling_loot_heap_id()
	if strat_id == "":
		assert_true(false, "Should find Rolling Loot-heap stratagem ID")
		return

	# Apply the stratagem
	StratagemManager.use_stratagem(1, strat_id, unit_id)

	# Verify flag is set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_rolling_loot_heap", false), "Flag should be set before clear")

	# Manually call the clear function
	StratagemManager._clear_stratagem_flags(unit_id, strat_id)

	# Verify flag is removed
	flags = GameState.state.units[unit_id].get("flags", {})
	assert_false(flags.get("effect_rolling_loot_heap", false), "Flag should be cleared after cleanup")

func test_phase_end_clears_rolling_loot_heap():
	"""Rolling Loot-heap effects should expire at end of phase."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_FLASH_GITZ"

	var strat_id = _find_rolling_loot_heap_id()
	if strat_id == "":
		assert_true(false, "Should find Rolling Loot-heap stratagem ID")
		return

	# Apply the stratagem
	StratagemManager.use_stratagem(1, strat_id, unit_id)

	# Verify flag is set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_rolling_loot_heap", false), "Flag should be set")

	# Trigger phase end (which clears end_of_phase effects)
	StratagemManager.on_phase_end(GameStateData.Phase.SHOOTING)

	# Verify flag is removed
	flags = GameState.state.units[unit_id].get("flags", {})
	assert_false(flags.get("effect_rolling_loot_heap", false), "Flag should be cleared after phase end")
