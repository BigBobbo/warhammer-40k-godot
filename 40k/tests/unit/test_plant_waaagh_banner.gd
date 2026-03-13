extends "res://addons/gut/test.gd"

# Tests for OA-46: Plant the Waaagh! Banner / Da Boss Iz Watchin'
#
# Per Warhammer 40k 10th Edition rules (Nob with Waaagh! Banner datasheet):
#
# "Plant the Waaagh! Banner":
#   Once per battle, at the start of the battle round, this model can use this ability.
#   If it does, until the start of the next battle round, this model's unit gains the
#   benefits of the Waaagh! ability as if you had called a Waaagh! this battle round.
#
# "Da Boss Iz Watchin'":
#   While this model is gaining the benefits of the Waaagh! ability, it has a 4+
#   invulnerable save and an Objective Control characteristic of 5.
#
# These tests verify:
# 1. can_plant_waaagh_banner() returns false for units without the ability
# 2. can_plant_waaagh_banner() returns true for deployed units with the ability
# 3. activate_plant_waaagh_banner() sets waaagh_active, 4+ invuln, OC 5, advance+charge
# 4. Ability is marked once per battle — cannot be used twice
# 5. _clear_plant_waaagh_banner_effects clears all flags at start of next Command phase
# 6. Army-wide Waaagh! also applies Da Boss Iz Watchin' (4+ invuln + OC 5)
# 7. ABILITY_EFFECTS table has correct entries for both abilities

const GameStateData = preload("res://autoloads/GameState.gd")

var faction_mgr: Node
var ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available")
		return
	faction_mgr = AutoloadHelper.get_autoload("FactionAbilityManager")
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(faction_mgr, "FactionAbilityManager must be available")
	assert_not_null(ability_mgr, "UnitAbilityManager must be available")

	# Reset Waaagh! state
	faction_mgr._waaagh_used = {"1": false, "2": false}
	faction_mgr._waaagh_active = {"1": false, "2": false}
	faction_mgr._plant_waaagh_banner_used = {}

	# Set up minimal game state
	GameState.state["units"] = {}
	if not GameState.state.has("factions"):
		GameState.state["factions"] = {}
	GameState.state["factions"]["1"] = "Orks"
	faction_mgr._player_abilities["1"] = ["Waaagh!"]

func _create_nob_waaagh_banner_unit(unit_id: String = "U_NOB_WAAAGH_A", owner: int = 1) -> Dictionary:
	"""Create a Nob with Waaagh! Banner unit with both abilities."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Nob with Waaagh! Banner",
			"keywords": ["ORKS", "INFANTRY", "CHARACTER", "NOB WITH WAAAGH! BANNER"],
			"stats": {"move": 6, "toughness": 5, "save": 4, "wounds": 3, "leadership": 7, "objective_control": 1},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction", "description": "Waaagh! faction ability"},
				{"name": "Plant the Waaagh! Banner", "type": "Datasheet",
				 "description": "Once per battle: unit gains Waaagh! effects."},
				{"name": "Da Boss Iz Watchin'", "type": "Datasheet",
				 "description": "While Waaagh! active: 4+ invuln and OC 5."}
			]
		},
		"flags": {},
		"models": [
			{"id": "m1", "wounds": 3, "current_wounds": 3, "base_mm": 32,
			 "position": {"x": 100, "y": 100}, "alive": true, "status_effects": []}
		]
	}
	GameState.state["units"][unit_id] = unit
	return unit

func _create_boyz_unit(unit_id: String = "U_BOYZ_A", owner: int = 1) -> Dictionary:
	"""Create a regular Boyz unit without Plant the Waaagh! Banner."""
	var unit = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Boyz",
			"keywords": ["ORKS", "INFANTRY"],
			"stats": {"move": 6, "toughness": 4, "save": 6, "wounds": 1, "leadership": 6, "objective_control": 2},
			"abilities": [
				{"name": "Waaagh!", "type": "Faction", "description": "Waaagh! faction ability"}
			]
		},
		"flags": {},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 25,
			 "position": {"x": 200, "y": 100}, "alive": true, "status_effects": []}
		]
	}
	GameState.state["units"][unit_id] = unit
	return unit

# ============================================================================
# Test: ABILITY_EFFECTS table registration
# ============================================================================

func test_plant_waaagh_banner_in_ability_effects():
	"""Plant the Waaagh! Banner should be registered in ABILITY_EFFECTS."""
	assert_true(ability_mgr.ABILITY_EFFECTS.has("Plant the Waaagh! Banner"),
		"'Plant the Waaagh! Banner' should be in ABILITY_EFFECTS")

func test_plant_waaagh_banner_marked_implemented():
	"""Plant the Waaagh! Banner should be marked as implemented."""
	var entry = ability_mgr.ABILITY_EFFECTS.get("Plant the Waaagh! Banner", {})
	assert_true(entry.get("implemented", false),
		"'Plant the Waaagh! Banner' should be marked as implemented")

func test_da_boss_iz_watchin_in_ability_effects():
	"""Da Boss Iz Watchin' should be registered in ABILITY_EFFECTS."""
	assert_true(ability_mgr.ABILITY_EFFECTS.has("Da Boss Iz Watchin'"),
		"'Da Boss Iz Watchin'' should be in ABILITY_EFFECTS")

func test_da_boss_iz_watchin_marked_implemented():
	"""Da Boss Iz Watchin' should be marked as implemented."""
	var entry = ability_mgr.ABILITY_EFFECTS.get("Da Boss Iz Watchin'", {})
	assert_true(entry.get("implemented", false),
		"'Da Boss Iz Watchin'' should be marked as implemented")

# ============================================================================
# Test: can_plant_waaagh_banner()
# ============================================================================

func test_can_plant_waaagh_banner_false_without_ability():
	"""Unit without Plant the Waaagh! Banner ability cannot use it."""
	_create_boyz_unit()
	var result = faction_mgr.can_plant_waaagh_banner("U_BOYZ_A")
	assert_false(result, "Boyz without ability should return false")

func test_can_plant_waaagh_banner_true_for_eligible_unit():
	"""Deployed unit with the ability should be eligible."""
	_create_nob_waaagh_banner_unit()
	var result = faction_mgr.can_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_true(result, "Nob with Waaagh! Banner should be eligible")

func test_can_plant_waaagh_banner_false_if_undeployed():
	"""Undeployed unit cannot use Plant the Waaagh! Banner."""
	_create_nob_waaagh_banner_unit()
	GameState.state["units"]["U_NOB_WAAAGH_A"]["status"] = GameStateData.UnitStatus.UNDEPLOYED
	var result = faction_mgr.can_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_false(result, "Undeployed unit should not be eligible")

func test_can_plant_waaagh_banner_false_if_already_used():
	"""Cannot use Plant the Waaagh! Banner twice in one battle."""
	_create_nob_waaagh_banner_unit()
	faction_mgr._plant_waaagh_banner_used["U_NOB_WAAAGH_A"] = true
	var result = faction_mgr.can_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_false(result, "Already used unit should not be eligible")

# ============================================================================
# Test: activate_plant_waaagh_banner()
# ============================================================================

func test_activate_sets_waaagh_active():
	"""Activation sets waaagh_active flag on the unit."""
	_create_nob_waaagh_banner_unit()
	var result = faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_true(result.get("success", false), "Activation should succeed")
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_true(flags.get("waaagh_active", false), "waaagh_active should be set")

func test_activate_sets_plant_banner_active():
	"""Activation sets plant_waaagh_banner_active flag on the unit."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_true(flags.get("plant_waaagh_banner_active", false),
		"plant_waaagh_banner_active should be set")

func test_activate_sets_advance_and_charge():
	"""Activation grants advance and charge eligibility."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_true(flags.get("effect_advance_and_charge", false),
		"effect_advance_and_charge should be set")

func test_activate_sets_4plus_invuln():
	"""Da Boss Iz Watchin': activation grants 4+ invulnerable save."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_eq(flags.get("effect_invuln", 0), 4,
		"effect_invuln should be 4 (4+ save)")
	assert_eq(flags.get("effect_invuln_source", ""), "Da Boss Iz Watchin'",
		"effect_invuln_source should be 'Da Boss Iz Watchin''")

func test_activate_sets_oc_5():
	"""Da Boss Iz Watchin': activation grants OC 5."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_eq(flags.get("effect_oc_override", 0), 5,
		"effect_oc_override should be 5")
	assert_eq(flags.get("effect_oc_source", ""), "Da Boss Iz Watchin'",
		"effect_oc_source should be 'Da Boss Iz Watchin''")

func test_activate_marks_once_per_battle():
	"""Activation marks the unit as used (once per battle)."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_true(faction_mgr._plant_waaagh_banner_used.get("U_NOB_WAAAGH_A", false),
		"Unit should be marked as used after activation")

func test_activate_twice_fails():
	"""Cannot activate Plant the Waaagh! Banner twice in one battle."""
	_create_nob_waaagh_banner_unit()
	var first = faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var second = faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	assert_true(first.get("success", false), "First activation should succeed")
	assert_false(second.get("success", false), "Second activation should fail (once per battle)")

# ============================================================================
# Test: _clear_plant_waaagh_banner_effects()
# ============================================================================

func test_clear_removes_plant_banner_active():
	"""Clearing removes the plant_waaagh_banner_active flag."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.get("plant_waaagh_banner_active", false),
		"plant_waaagh_banner_active should be cleared")

func test_clear_removes_waaagh_active():
	"""Clearing removes waaagh_active flag."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.get("waaagh_active", false),
		"waaagh_active should be cleared")

func test_clear_removes_advance_and_charge():
	"""Clearing removes effect_advance_and_charge flag."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.get("effect_advance_and_charge", false),
		"effect_advance_and_charge should be cleared")

func test_clear_removes_invuln():
	"""Clearing removes the Da Boss Iz Watchin' 4+ invuln."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.has("effect_invuln"), "effect_invuln should be cleared")

func test_clear_removes_oc_override():
	"""Clearing removes the Da Boss Iz Watchin' OC 5 override."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.has("effect_oc_override"), "effect_oc_override should be cleared")

func test_clear_does_not_affect_other_units():
	"""Clearing Plant banner effects only affects units with plant_waaagh_banner_active."""
	_create_nob_waaagh_banner_unit()
	_create_boyz_unit()
	# Manually set invuln on Boyz from a different source
	GameState.state["units"]["U_BOYZ_A"]["flags"]["effect_invuln"] = 5
	GameState.state["units"]["U_BOYZ_A"]["flags"]["effect_invuln_source"] = "Waaagh!"
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	faction_mgr._clear_plant_waaagh_banner_effects(1)
	# Boyz invuln should be untouched (they have "Waaagh!" source, not "Da Boss Iz Watchin'")
	var boyz_flags = GameState.state["units"]["U_BOYZ_A"].get("flags", {})
	assert_eq(boyz_flags.get("effect_invuln", 0), 5,
		"Boyz invuln should not be cleared by Plant banner clearing")

# ============================================================================
# Test: Da Boss Iz Watchin' via army-wide Waaagh!
# ============================================================================

func test_army_waaagh_applies_da_boss_iz_watchin():
	"""When army Waaagh! activates, units with Da Boss Iz Watchin' get 4+ invuln and OC 5."""
	_create_nob_waaagh_banner_unit()
	# Apply army Waaagh! effects directly
	faction_mgr._apply_waaagh_effects(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_true(flags.get("waaagh_active", false), "waaagh_active should be set")
	assert_eq(flags.get("effect_invuln", 0), 4,
		"Da Boss Iz Watchin' should upgrade invuln to 4+ during army Waaagh!")
	assert_eq(flags.get("effect_oc_override", 0), 5,
		"Da Boss Iz Watchin' should set OC 5 during army Waaagh!")

func test_army_waaagh_gives_5plus_invuln_to_regular_units():
	"""Regular Ork units (without Da Boss Iz Watchin') get 5+ invuln from army Waaagh!."""
	_create_boyz_unit()
	faction_mgr._apply_waaagh_effects(1)
	var flags = GameState.state["units"]["U_BOYZ_A"].get("flags", {})
	assert_eq(flags.get("effect_invuln", 0), 5,
		"Regular Ork units should get 5+ invuln from army Waaagh!")
	assert_false(flags.has("effect_oc_override"),
		"Regular Ork units should NOT get OC override from army Waaagh!")

func test_army_waaagh_deactivation_clears_da_boss_iz_watchin():
	"""Army Waaagh! deactivation clears Da Boss Iz Watchin' effects."""
	_create_nob_waaagh_banner_unit()
	# Activate army Waaagh!
	faction_mgr._waaagh_active["1"] = true
	faction_mgr._apply_waaagh_effects(1)
	# Now deactivate
	faction_mgr._waaagh_active["1"] = true  # must be active to deactivate
	faction_mgr.deactivate_waaagh(1)
	var flags = GameState.state["units"]["U_NOB_WAAAGH_A"].get("flags", {})
	assert_false(flags.has("effect_invuln"),
		"effect_invuln should be cleared when army Waaagh! ends")
	assert_false(flags.has("effect_oc_override"),
		"effect_oc_override should be cleared when army Waaagh! ends")

# ============================================================================
# Test: get_plant_waaagh_banner_eligible_units()
# ============================================================================

func test_eligible_units_returns_nob_with_ability():
	"""get_plant_waaagh_banner_eligible_units returns units with the ability."""
	_create_nob_waaagh_banner_unit()
	_create_boyz_unit()
	var eligible = faction_mgr.get_plant_waaagh_banner_eligible_units(1)
	assert_eq(eligible.size(), 1, "Only Nob with Waaagh! Banner should be eligible")
	assert_eq(eligible[0].unit_id, "U_NOB_WAAAGH_A")

func test_eligible_units_empty_after_use():
	"""After using Plant the Waaagh! Banner, unit is no longer eligible."""
	_create_nob_waaagh_banner_unit()
	faction_mgr.activate_plant_waaagh_banner("U_NOB_WAAAGH_A")
	var eligible = faction_mgr.get_plant_waaagh_banner_eligible_units(1)
	assert_eq(eligible.size(), 0, "Used unit should not appear in eligible list")
