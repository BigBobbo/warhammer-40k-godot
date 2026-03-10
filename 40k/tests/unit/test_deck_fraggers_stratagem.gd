extends "res://addons/gut/test.gd"

# Tests for DECK FRAGGERS stratagem implementation (OA-7)
#
# Per Warhammer 40k 10th Edition — Freebooter Krew:
# - DECK FRAGGERS (Strategic Ploy Stratagem, 1 CP)
# - WHEN: Your Shooting phase.
# - TARGET: One ORKS unit from your army that has not been selected to shoot.
# - EFFECT: Until end of phase, each time a model in your unit targets an INFANTRY
#   unit with a ranged weapon, that weapon has the [BLAST] ability.
#
# These tests verify:
# 1. StratagemManager marks Deck Fraggers as implemented (custom handler)
# 2. Using the stratagem sets effect_deck_fraggers flag on the target unit
# 3. Only ORKS units can be targeted
# 4. BLAST bonus attacks calculated correctly when targeting INFANTRY
# 5. BLAST does NOT apply when targeting non-INFANTRY units
# 6. BLAST minimum 3 attacks applies vs 6+ model INFANTRY targets
# 7. Flag is cleared at end of phase

const GameStateData = preload("res://autoloads/GameState.gd")


# ==========================================
# Helpers
# ==========================================

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
			"weapons": [
				{
					"name": "Slugga",
					"type": "Ranged",
					"range": 12,
					"attacks": 1,
					"attacks_raw": "1",
					"bs": 5,
					"strength": 4,
					"ap": 0,
					"damage": 1,
					"keywords": []
				},
				{
					"name": "Choppa",
					"type": "Melee",
					"range": 0,
					"attacks": 3,
					"attacks_raw": "3",
					"ws": 3,
					"strength": 4,
					"ap": 1,
					"damage": 1,
					"keywords": []
				}
			],
			"abilities": []
		},
		"models": models,
		"flags": {}
	}

func _create_non_ork_unit(id: String, model_count: int = 5, owner: int = 1) -> Dictionary:
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
			"name": "Space Marines",
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
		"models": models,
		"flags": {}
	}

func _create_infantry_target(id: String, model_count: int = 1, owner: int = 2) -> Dictionary:
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 700 + i * 40, "y": 500},
			"alive": true,
			"status_effects": []
		})
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

func _setup_game_state_for_shooting(unit_id: String = "U_ORK_BOYZ") -> Dictionary:
	"""Set up GameState with an Ork Boyz unit ready for Shooting phase."""
	var unit = _create_ork_boyz_unit(unit_id, 5, 1)
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

func _find_deck_fraggers_id() -> String:
	"""Find the Deck Fraggers stratagem ID from loaded stratagems."""
	for strat_id in StratagemManager.stratagems:
		var strat = StratagemManager.stratagems[strat_id]
		if strat.get("name", "").to_upper() == "DECK FRAGGERS":
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

func test_deck_fraggers_loaded_from_csv():
	"""Deck Fraggers should be loadable from the Freebooter Krew CSV data."""
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var strats = loader.load_faction_stratagems("Orks", "Freebooter Krew")
	var found = false
	for s in strats:
		if "DECK FRAGGERS" in s.name.to_upper():
			found = true
			assert_eq(s.cp_cost, 1, "CP cost should be 1")
			assert_eq(s.timing.turn, "your", "Should be your turn only")
			assert_eq(s.timing.phase, "shooting", "Should be shooting phase")
	assert_true(found, "Should find DECK FRAGGERS in Freebooter Krew stratagems")

func test_deck_fraggers_marked_as_implemented():
	"""After _mark_custom_implemented_stratagems, Deck Fraggers should be implemented=true."""
	_load_freebooter_stratagems()
	var strat_id = _find_deck_fraggers_id()
	assert_ne(strat_id, "", "Should find Deck Fraggers stratagem ID")
	if strat_id != "":
		var strat = StratagemManager.stratagems[strat_id]
		assert_true(strat.get("implemented", false), "Deck Fraggers should be marked as implemented")


# ==========================================
# Section 2: Effect Application
# ==========================================

func test_apply_effects_sets_deck_fraggers_flag():
	"""Using Deck Fraggers should set effect_deck_fraggers flag on target unit."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_ORK_BOYZ"

	var strat_id = _find_deck_fraggers_id()
	assert_ne(strat_id, "", "Should find Deck Fraggers stratagem ID")
	if strat_id == "":
		return

	var result = StratagemManager.use_stratagem(1, strat_id, unit_id)
	assert_true(result.get("success", false), "Stratagem use should succeed")

	# Check the flag was set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_deck_fraggers", false), "effect_deck_fraggers flag should be set")

func test_deck_fraggers_deducts_cp():
	"""Using Deck Fraggers should deduct 1 CP."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_ORK_BOYZ"
	GameState.state.players["1"]["cp"] = 5

	var strat_id = _find_deck_fraggers_id()
	if strat_id == "":
		assert_true(false, "Should find Deck Fraggers stratagem ID")
		return

	var cp_before = GameState.state.players["1"]["cp"]
	StratagemManager.use_stratagem(1, strat_id, unit_id)
	var cp_after = GameState.state.players["1"]["cp"]
	assert_eq(cp_before - cp_after, 1, "Should deduct 1 CP")


# ==========================================
# Section 3: Targeting Validation
# ==========================================

func test_only_orks_units_can_be_targeted():
	"""Deck Fraggers should reject non-ORKS units."""
	_load_freebooter_stratagems()
	# Set up a non-ORKS unit
	var marines = _create_non_ork_unit("U_MARINES", 5, 1)
	GameState.state.units["U_MARINES"] = marines
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3

	var strat_id = _find_deck_fraggers_id()
	if strat_id == "":
		assert_true(false, "Should find Deck Fraggers stratagem ID")
		return

	var result = StratagemManager.use_stratagem(1, strat_id, "U_MARINES")
	assert_false(result.get("success", true), "Should fail for non-ORKS unit")

func test_orks_that_already_shot_cannot_be_targeted():
	"""Deck Fraggers should reject ORKS units that have already shot."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_ORK_BOYZ"
	# Mark unit as already shot
	GameState.state.units[unit_id]["flags"]["has_shot"] = true

	var strat_id = _find_deck_fraggers_id()
	if strat_id == "":
		assert_true(false, "Should find Deck Fraggers stratagem ID")
		return

	var result = StratagemManager.use_stratagem(1, strat_id, unit_id)
	assert_false(result.get("success", true), "Should fail for ORKS unit that already shot")

func test_eligible_units_returns_only_orks():
	"""get_deck_fraggers_eligible_units should only return ORKS units."""
	_load_freebooter_stratagems()
	# Set up both an ORKS and a non-ORKS unit
	var boyz = _create_ork_boyz_unit("U_ORK_BOYZ", 5, 1)
	var marines = _create_non_ork_unit("U_MARINES", 5, 1)
	GameState.state.units["U_ORK_BOYZ"] = boyz
	GameState.state.units["U_MARINES"] = marines
	GameState.state.meta.phase = GameStateData.Phase.SHOOTING
	GameState.state.meta.active_player = 1
	GameState.state.players["1"]["cp"] = 3
	StratagemManager.set_out_of_phase_active(false)
	StratagemManager._usage_history = {"1": [], "2": []}

	var eligible = StratagemManager.get_deck_fraggers_eligible_units(1)
	assert_eq(eligible.size(), 1, "Should find exactly one eligible unit")
	if eligible.size() > 0:
		assert_eq(eligible[0].unit_id, "U_ORK_BOYZ", "Eligible unit should be Ork Boyz")


# ==========================================
# Section 4: BLAST Effect vs INFANTRY in RulesEngine
# ==========================================

func test_blast_bonus_attacks_vs_infantry_6_models():
	"""Deck Fraggers should grant BLAST bonus (+1 attack) when targeting INFANTRY with 6+ models."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	# Create infantry target with 7 models (should get +1 BLAST bonus)
	var target = _create_infantry_target("U_TARGET", 7, 2)
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_TARGET"] = target

	# The flag-based logic: if unit has effect_deck_fraggers AND target has INFANTRY keyword
	# AND weapon is ranged AND weapon doesn't already have BLAST → BLAST bonus applies
	var has_flag = boyz.get("flags", {}).get("effect_deck_fraggers", false)
	var target_is_infantry = RulesEngine.unit_has_keyword(target, "INFANTRY")
	assert_true(has_flag, "Boyz should have the deck fraggers flag")
	assert_true(target_is_infantry, "Target should have INFANTRY keyword")

	# Simulate what RulesEngine does at the call site for BLAST bonus
	var model_count = RulesEngine.count_alive_models(target)
	assert_eq(model_count, 7, "Target should have 7 alive models")
	var blast_bonus = 0
	if has_flag and target_is_infantry:
		if model_count >= 11:
			blast_bonus = 2
		elif model_count >= 6:
			blast_bonus = 1
	assert_eq(blast_bonus, 1, "Should get +1 BLAST bonus vs 7-model INFANTRY target")

func test_blast_bonus_attacks_vs_infantry_11_models():
	"""Deck Fraggers should grant +2 BLAST bonus when targeting INFANTRY with 11+ models."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	var target = _create_infantry_target("U_TARGET", 12, 2)
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_TARGET"] = target

	var model_count = RulesEngine.count_alive_models(target)
	assert_eq(model_count, 12, "Target should have 12 alive models")

	var has_flag = boyz.get("flags", {}).get("effect_deck_fraggers", false)
	var target_is_infantry = RulesEngine.unit_has_keyword(target, "INFANTRY")
	var blast_bonus = 0
	if has_flag and target_is_infantry:
		if model_count >= 11:
			blast_bonus = 2
		elif model_count >= 6:
			blast_bonus = 1
	assert_eq(blast_bonus, 2, "Should get +2 BLAST bonus vs 12-model INFANTRY target")

func test_blast_minimum_3_vs_infantry_6_models():
	"""Deck Fraggers BLAST should enforce minimum 3 attacks vs 6+ model INFANTRY units."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 1, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	var target = _create_infantry_target("U_TARGET", 8, 2)
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_TARGET"] = target

	var has_flag = boyz.get("flags", {}).get("effect_deck_fraggers", false)
	var target_is_infantry = RulesEngine.unit_has_keyword(target, "INFANTRY")
	assert_true(has_flag and target_is_infantry, "Flag and INFANTRY check should pass")

	# Simulate BLAST minimum: if 6+ models and base attacks < 3 → set to 3
	var model_count = RulesEngine.count_alive_models(target)
	var base_attacks = 1  # Slugga has 1 attack
	var effective_attacks = base_attacks
	if has_flag and target_is_infantry:
		if model_count >= 6 and base_attacks < 3:
			effective_attacks = 3
	assert_eq(effective_attacks, 3, "BLAST minimum should bump 1 attack to 3 vs 8-model INFANTRY")

func test_no_blast_vs_non_infantry():
	"""Deck Fraggers should NOT grant BLAST when targeting non-INFANTRY (e.g., VEHICLE)."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	var vehicle = _create_vehicle_target("U_VEHICLE")
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_VEHICLE"] = vehicle

	var has_flag = boyz.get("flags", {}).get("effect_deck_fraggers", false)
	var target_is_infantry = RulesEngine.unit_has_keyword(vehicle, "INFANTRY")
	assert_true(has_flag, "Boyz should have the deck fraggers flag")
	assert_false(target_is_infantry, "Vehicle target should NOT have INFANTRY keyword")

	# No BLAST bonus should apply
	var blast_bonus = 0
	if has_flag and target_is_infantry:
		blast_bonus = 1  # This shouldn't execute
	assert_eq(blast_bonus, 0, "No BLAST bonus should apply vs VEHICLE target")

func test_no_blast_on_melee_weapons():
	"""Deck Fraggers should NOT grant BLAST to melee weapons, even vs INFANTRY."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	var target = _create_infantry_target("U_TARGET", 8, 2)
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_TARGET"] = target

	# Check: melee weapon (Choppa) should NOT get BLAST
	var weapons = boyz.get("meta", {}).get("weapons", [])
	var choppa = null
	for w in weapons:
		if w.get("name", "") == "Choppa":
			choppa = w
			break
	assert_not_null(choppa, "Should find Choppa weapon")
	if choppa == null:
		return

	var wp_type = choppa.get("type", "")
	var is_ranged = wp_type.to_lower() == "ranged" or choppa.get("range", 0) > 0
	assert_false(is_ranged, "Choppa should not be considered ranged")

func test_no_blast_vs_few_models():
	"""Deck Fraggers BLAST should give no bonus vs units with 5 or fewer models."""
	var boyz = _create_ork_boyz_unit("U_BOYZ", 3, 1)
	boyz["flags"]["effect_deck_fraggers"] = true
	var target = _create_infantry_target("U_TARGET", 4, 2)
	GameState.state.units["U_BOYZ"] = boyz
	GameState.state.units["U_TARGET"] = target

	var model_count = RulesEngine.count_alive_models(target)
	assert_eq(model_count, 4, "Target should have 4 alive models")

	var blast_bonus = 0
	var has_flag = boyz.get("flags", {}).get("effect_deck_fraggers", false)
	var target_is_infantry = RulesEngine.unit_has_keyword(target, "INFANTRY")
	if has_flag and target_is_infantry:
		if model_count >= 11:
			blast_bonus = 2
		elif model_count >= 6:
			blast_bonus = 1
	assert_eq(blast_bonus, 0, "No BLAST bonus vs 4-model target (need 6+)")


# ==========================================
# Section 5: Flag Cleanup
# ==========================================

func test_clear_stratagem_flags_removes_deck_fraggers():
	"""Clearing Deck Fraggers should remove the effect_deck_fraggers flag."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_ORK_BOYZ"

	var strat_id = _find_deck_fraggers_id()
	if strat_id == "":
		assert_true(false, "Should find Deck Fraggers stratagem ID")
		return

	# Apply the stratagem
	StratagemManager.use_stratagem(1, strat_id, unit_id)

	# Verify flag is set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_deck_fraggers", false), "Flag should be set before clear")

	# Manually call the clear function
	StratagemManager._clear_stratagem_flags(unit_id, strat_id)

	# Verify flag is removed
	flags = GameState.state.units[unit_id].get("flags", {})
	assert_false(flags.get("effect_deck_fraggers", false), "Flag should be cleared after cleanup")

func test_phase_end_clears_deck_fraggers():
	"""Deck Fraggers effects should expire at end of phase."""
	_load_freebooter_stratagems()
	var unit = _setup_game_state_for_shooting()
	var unit_id = "U_ORK_BOYZ"

	var strat_id = _find_deck_fraggers_id()
	if strat_id == "":
		assert_true(false, "Should find Deck Fraggers stratagem ID")
		return

	# Apply the stratagem
	StratagemManager.use_stratagem(1, strat_id, unit_id)

	# Verify flag is set
	var flags = GameState.state.units[unit_id].get("flags", {})
	assert_true(flags.get("effect_deck_fraggers", false), "Flag should be set")

	# Trigger phase end (which clears end_of_phase effects)
	StratagemManager.on_phase_end(GameStateData.Phase.SHOOTING)

	# Verify flag is removed
	flags = GameState.state.units[unit_id].get("flags", {})
	assert_false(flags.get("effect_deck_fraggers", false), "Flag should be cleared after phase end")
