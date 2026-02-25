extends "res://addons/gut/test.gd"

# Tests for UnitAbilityManager (Step 10: Unit Abilities)
#
# These tests verify:
# 1. ABILITY_EFFECTS lookup table has correct definitions
# 2. Leader ability detection and effect application
# 3. Always-on unit ability detection and effect application
# 4. Phase lifecycle (apply at phase start, clear at phase end)
# 5. Integration with EffectPrimitives flags
# 6. RulesEngine reads ability-applied flags during combat resolution
# 7. Query helpers (get_active_ability_effects_for_unit, etc.)

const GameStateData = preload("res://autoloads/GameState.gd")

var ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(ability_mgr, "UnitAbilityManager autoload must be available")

	# Reset state between tests
	ability_mgr._active_ability_effects.clear()
	ability_mgr._applied_this_phase.clear()

	# Set up minimal game state
	GameState.state["units"] = {}
	if not GameState.state.has("factions"):
		GameState.state["factions"] = {}

# ==========================================
# Helper: Create test units
# ==========================================

func _create_bodyguard_unit(id: String, owner: int, abilities: Array = [], model_count: int = 5) -> Dictionary:
	"""Create a bodyguard (non-CHARACTER) unit."""
	var models = []
	for i in range(model_count):
		models.append({
			"id": "m%d" % (i + 1),
			"wounds": 2,
			"current_wounds": 2,
			"base_mm": 32,
			"position": {"x": 100 + i * 20, "y": 100},
			"alive": true,
			"status_effects": []
		})
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2},
			"abilities": abilities
		},
		"models": models,
		"flags": {},
		"attachment_data": {"attached_characters": []}
	}
	GameState.state["units"][id] = unit
	return unit

func _create_leader_unit(id: String, owner: int, abilities: Array = []) -> Dictionary:
	"""Create a CHARACTER leader unit (1 model)."""
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Warboss",
			"keywords": ["CHARACTER", "INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 4, "wounds": 6, "leadership": 6, "objective_control": 1},
			"abilities": abilities
		},
		"models": [
			{"id": "m1", "wounds": 6, "current_wounds": 6, "base_mm": 40, "position": {"x": 100, "y": 100}, "alive": true, "status_effects": []}
		],
		"flags": {},
		"attached_to": null
	}
	GameState.state["units"][id] = unit
	return unit

func _attach_leader_to_unit(leader_id: String, bodyguard_id: String) -> void:
	"""Simulate a leader attachment."""
	var leader = GameState.state["units"][leader_id]
	var bodyguard = GameState.state["units"][bodyguard_id]
	leader["attached_to"] = bodyguard_id
	if not bodyguard.has("attachment_data"):
		bodyguard["attachment_data"] = {"attached_characters": []}
	bodyguard["attachment_data"]["attached_characters"].append(leader_id)

# ==========================================
# TEST: Lookup table correctness
# ==========================================

func test_ability_lookup_table_has_required_entries():
	"""ABILITY_EFFECTS should contain the key combat-affecting abilities."""
	var table = ability_mgr.ABILITY_EFFECTS
	assert_true(table.has("Might is Right"), "Should have Might is Right")
	assert_true(table.has("More Dakka"), "Should have More Dakka")
	assert_true(table.has("Flashiest Gitz"), "Should have Flashiest Gitz")
	assert_true(table.has("Red Skull Kommandos"), "Should have Red Skull Kommandos")
	assert_true(table.has("Dok's Toolz"), "Should have Dok's Toolz")
	assert_true(table.has("Stand Vigil"), "Should have Stand Vigil")
	assert_true(table.has("Ramshackle"), "Should have Ramshackle")

func test_ability_lookup_table_structure():
	"""Each ability entry should have the required keys."""
	var table = ability_mgr.ABILITY_EFFECTS
	for ability_name in table:
		var entry = table[ability_name]
		assert_true(entry.has("condition"), "%s should have 'condition'" % ability_name)
		assert_true(entry.has("effects"), "%s should have 'effects'" % ability_name)
		assert_true(entry.has("target"), "%s should have 'target'" % ability_name)
		assert_true(entry.has("attack_type"), "%s should have 'attack_type'" % ability_name)
		assert_true(entry.has("implemented"), "%s should have 'implemented'" % ability_name)

func test_might_is_right_definition():
	"""Might is Right should grant +1 to hit for melee attacks from led unit."""
	var entry = ability_mgr.ABILITY_EFFECTS["Might is Right"]
	assert_eq(entry.condition, "while_leading")
	assert_eq(entry.target, "led_unit")
	assert_eq(entry.attack_type, "melee")
	assert_true(entry.implemented)
	assert_eq(entry.effects.size(), 1)
	assert_eq(entry.effects[0].type, "plus_one_hit")

func test_more_dakka_definition():
	"""More Dakka should grant re-roll 1s to hit for ranged attacks from led unit."""
	var entry = ability_mgr.ABILITY_EFFECTS["More Dakka"]
	assert_eq(entry.condition, "while_leading")
	assert_eq(entry.target, "led_unit")
	assert_eq(entry.attack_type, "ranged")
	assert_true(entry.implemented)
	assert_eq(entry.effects.size(), 1)
	assert_eq(entry.effects[0].type, "reroll_hits")
	assert_eq(entry.effects[0].scope, "ones")

func test_doks_toolz_definition():
	"""Dok's Toolz should grant FNP 5+ to led unit."""
	var entry = ability_mgr.ABILITY_EFFECTS["Dok's Toolz"]
	assert_eq(entry.condition, "while_leading")
	assert_eq(entry.target, "led_unit")
	assert_true(entry.implemented)
	assert_eq(entry.effects.size(), 1)
	assert_eq(entry.effects[0].type, "grant_fnp")
	assert_eq(entry.effects[0].value, 5)

# ==========================================
# TEST: Leader ability application
# ==========================================

func test_leader_ability_applies_flags_to_bodyguard():
	"""When a leader with Might is Right is attached, bodyguard gets +1 hit flag in Fight phase."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	# Apply for Fight phase (melee)
	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	# Check that bodyguard unit got the effect flag
	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var has_plus_one = EffectPrimitivesData.has_effect_plus_one_hit(bodyguard)
	assert_true(has_plus_one, "Bodyguard unit should have +1 to hit from Might is Right")

func test_leader_ability_melee_not_applied_in_shooting():
	"""Might is Right (melee) should NOT apply during Shooting phase."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var has_plus_one = EffectPrimitivesData.has_effect_plus_one_hit(bodyguard)
	assert_false(has_plus_one, "Melee ability should not apply in Shooting phase")

func test_leader_ranged_ability_applies_in_shooting():
	"""More Dakka (ranged) should apply during Shooting phase."""
	var abilities = [{"name": "More Dakka", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_BIGMEK_A", 1, abilities)
	_attach_leader_to_unit("U_BIGMEK_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var reroll_scope = bodyguard.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
	assert_eq(reroll_scope, "ones", "Led unit should have reroll ones for hits from More Dakka")

func test_leader_cover_ability_applies():
	"""Red Skull Kommandos should grant cover to led unit."""
	var abilities = [{"name": "Red Skull Kommandos", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_KOMMANDOS_A", 1)
	_create_leader_unit("U_SNIKROT_A", 1, abilities)
	_attach_leader_to_unit("U_SNIKROT_A", "U_KOMMANDOS_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_KOMMANDOS_A"]
	assert_true(EffectPrimitivesData.has_effect_cover(bodyguard),
		"Led unit should have Benefit of Cover from Red Skull Kommandos")

func test_leader_fnp_ability_applies():
	"""Dok's Toolz should grant FNP 5+ to led unit."""
	var abilities = [{"name": "Dok's Toolz", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_PAINBOY_A", 1, abilities)
	_attach_leader_to_unit("U_PAINBOY_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var fnp = EffectPrimitivesData.get_effect_fnp(bodyguard)
	assert_eq(fnp, 5, "Led unit should have FNP 5+ from Dok's Toolz")

func test_leader_flashiest_gitz_reroll_all():
	"""Flashiest Gitz should grant re-roll all ranged Hit rolls."""
	var abilities = [{"name": "Flashiest Gitz", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_FLASH_GITZ_A", 1)
	_create_leader_unit("U_BADRUKK_A", 1, abilities)
	_attach_leader_to_unit("U_BADRUKK_A", "U_FLASH_GITZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_FLASH_GITZ_A"]
	var reroll_scope = bodyguard.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_HITS, "")
	assert_eq(reroll_scope, "all", "Led unit should have reroll all hits from Flashiest Gitz")

# ==========================================
# TEST: No leader attached — no effects
# ==========================================

func test_no_effects_without_leader_attached():
	"""A unit without an attached leader should NOT get leader ability effects."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, [
		{"name": "Might is Right", "type": "Datasheet", "description": "..."}
	])
	# Do NOT attach leader to bodyguard

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_false(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Unattached unit should not have +1 to hit")

func test_dead_leader_does_not_grant_ability():
	"""A dead leader should not grant abilities."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	# Kill the leader
	GameState.state["units"]["U_WARBOSS_A"]["models"][0]["alive"] = false

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_false(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Dead leader should not grant +1 to hit")

# ==========================================
# TEST: Always-on unit abilities
# ==========================================

func test_stand_vigil_applies_reroll_wounds():
	"""Stand Vigil should grant re-roll Wound rolls of 1 to the unit itself."""
	_create_bodyguard_unit("U_GUARD_A", 1, [
		{"name": "Stand Vigil", "type": "Datasheet", "description": "..."}
	])

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var unit = GameState.state["units"]["U_GUARD_A"]
	var reroll_scope = unit.get("flags", {}).get(EffectPrimitivesData.FLAG_REROLL_WOUNDS, "")
	assert_eq(reroll_scope, "ones", "Stand Vigil should grant reroll 1s to wound")

func test_ramshackle_applies_worsen_ap():
	"""Ramshackle should worsen AP of incoming attacks by 1."""
	_create_bodyguard_unit("U_WAGON_A", 1, [
		{"name": "Ramshackle", "type": "Datasheet", "description": "..."}
	])

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var unit = GameState.state["units"]["U_WAGON_A"]
	var worsen = EffectPrimitivesData.get_effect_worsen_ap(unit)
	assert_eq(worsen, 1, "Ramshackle should worsen AP by 1")
	assert_true(EffectPrimitivesData.has_effect_worsen_ap(unit), "Ramshackle should set worsen_ap flag")

# ==========================================
# TEST: Phase lifecycle (apply/clear)
# ==========================================

func test_effects_cleared_at_phase_end():
	"""Effects should be cleared when on_phase_end is called."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_true(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Precondition: should have +1 to hit during Fight phase")

	ability_mgr.on_phase_end(GameStateData.Phase.FIGHT)

	# Re-read unit after clearing
	bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_false(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Effect should be cleared at phase end")

func test_active_effects_tracking():
	"""Active effects should be tracked and queryable."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var effects = ability_mgr.get_active_ability_effects_for_unit("U_BOYZ_A")
	assert_eq(effects.size(), 1, "Should have 1 active ability effect")
	assert_eq(effects[0].ability_name, "Might is Right")
	assert_eq(effects[0].source_unit_id, "U_WARBOSS_A")
	assert_eq(effects[0].target_unit_id, "U_BOYZ_A")
	assert_eq(effects[0].attack_type, "melee")

func test_unit_has_active_ability_query():
	"""unit_has_active_ability should return true when ability is applied."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	assert_true(ability_mgr.unit_has_active_ability("U_BOYZ_A", "Might is Right"))
	assert_false(ability_mgr.unit_has_active_ability("U_BOYZ_A", "More Dakka"))

# ==========================================
# TEST: Query helpers
# ==========================================

func test_get_ability_effect_definition():
	"""Should return the correct definition for known abilities."""
	var def_data = ability_mgr.get_ability_effect_definition("Might is Right")
	assert_false(def_data.is_empty(), "Should find Might is Right definition")
	assert_eq(def_data.condition, "while_leading")

func test_get_ability_effect_definition_unknown():
	"""Should return empty dict for unknown abilities."""
	var def_data = ability_mgr.get_ability_effect_definition("Made Up Ability")
	assert_true(def_data.is_empty(), "Unknown ability should return empty dict")

func test_is_ability_implemented():
	"""Should report implementation status correctly."""
	assert_true(ability_mgr.is_ability_implemented("Might is Right"))
	assert_true(ability_mgr.is_ability_implemented("More Dakka"))
	assert_false(ability_mgr.is_ability_implemented("Da Biggest and da Best"))
	assert_false(ability_mgr.is_ability_implemented("Totally Fake Ability"))

func test_get_implemented_abilities():
	"""Should return all implemented ability names."""
	var implemented = ability_mgr.get_implemented_abilities()
	assert_true(implemented.size() > 0, "Should have some implemented abilities")
	assert_true("Might is Right" in implemented)
	assert_true("More Dakka" in implemented)
	assert_true("Stand Vigil" in implemented)
	assert_false("Da Biggest and da Best" in implemented)

func test_get_unit_ability_summary():
	"""Should return summary with implementation status for all unit abilities."""
	_create_bodyguard_unit("U_BOYZ_A", 1, [
		{"name": "Might is Right", "type": "Datasheet", "description": "..."},
		{"name": "Unknown Power", "type": "Datasheet", "description": "..."}
	])

	var summary = ability_mgr.get_unit_ability_summary("U_BOYZ_A")
	assert_eq(summary.size(), 2)
	assert_eq(summary[0].name, "Might is Right")
	assert_true(summary[0].implemented)
	assert_true(summary[0].has_definition)
	assert_eq(summary[1].name, "Unknown Power")
	assert_false(summary[1].implemented)
	assert_false(summary[1].has_definition)

# ==========================================
# TEST: Static query helpers
# ==========================================

func test_unit_has_leader_ability_static():
	"""Static check should find leader ability without phase flags."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var all_units = GameState.state["units"]
	assert_true(ability_mgr.unit_has_leader_ability(bodyguard, "Might is Right", all_units))
	assert_false(ability_mgr.unit_has_leader_ability(bodyguard, "More Dakka", all_units))

func test_get_ability_attack_type():
	"""Should return correct attack type restriction."""
	assert_eq(ability_mgr.get_ability_attack_type("Might is Right"), "melee")
	assert_eq(ability_mgr.get_ability_attack_type("More Dakka"), "ranged")
	assert_eq(ability_mgr.get_ability_attack_type("Red Skull Kommandos"), "all")
	assert_eq(ability_mgr.get_ability_attack_type("Unknown"), "all")

# ==========================================
# TEST: Multiple leaders / abilities
# ==========================================

func test_multiple_leader_abilities():
	"""A unit with multiple attached leaders should get effects from all."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, [
		{"name": "Might is Right", "type": "Datasheet", "description": "..."}
	])
	var painboy = _create_leader_unit("U_PAINBOY_A", 1, [
		{"name": "Dok's Toolz", "type": "Datasheet", "description": "..."}
	])

	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")
	_attach_leader_to_unit("U_PAINBOY_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_true(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Should have +1 to hit from Warboss")
	var fnp = EffectPrimitivesData.get_effect_fnp(bodyguard)
	assert_eq(fnp, 5, "Should have FNP 5+ from Painboy")

	var effects = ability_mgr.get_active_ability_effects_for_unit("U_BOYZ_A")
	assert_eq(effects.size(), 2, "Should have 2 active ability effects")

# ==========================================
# TEST: Prophet of Da Great Waaagh! (dual effect)
# ==========================================

func test_prophet_dual_effect():
	"""Prophet of Da Great Waaagh! should grant both +1 hit and +1 wound."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_GHAZ_A", 1, [
		{"name": "Prophet of Da Great Waaagh!", "type": "Datasheet", "description": "..."}
	])
	_attach_leader_to_unit("U_GHAZ_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_true(EffectPrimitivesData.has_effect_plus_one_hit(bodyguard),
		"Should have +1 to hit from Prophet")
	assert_true(EffectPrimitivesData.has_effect_plus_one_wound(bodyguard),
		"Should have +1 to wound from Prophet")

# ==========================================
# TEST: Eligibility effects (Movement phase)
# ==========================================

func test_fall_back_and_charge_eligibility():
	"""One Scalpel Short of a Medpack should grant fall_back_and_charge in Movement phase."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_GROTSNIK_A", 1, [
		{"name": "One Scalpel Short of a Medpack", "type": "Datasheet", "description": "..."}
	])
	_attach_leader_to_unit("U_GROTSNIK_A", "U_BOYZ_A")

	ability_mgr.on_movement_phase_start()

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	assert_true(EffectPrimitivesData.has_effect_fall_back_and_charge(bodyguard),
		"Led unit should have fall_back_and_charge eligibility")

# ==========================================
# TEST: Save/Load
# ==========================================

func test_save_and_load_state():
	"""Should correctly save and restore state."""
	var abilities = [{"name": "Might is Right", "type": "Datasheet", "description": "..."}]
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_WARBOSS_A", 1, abilities)
	_attach_leader_to_unit("U_WARBOSS_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)

	var state = ability_mgr.get_state_for_save()
	assert_true(state.has("active_ability_effects"))
	assert_eq(state["active_ability_effects"].size(), 1)

	# Reset and reload
	ability_mgr.reset_for_new_game()
	assert_eq(ability_mgr._active_ability_effects.size(), 0)

	ability_mgr.load_state(state)
	assert_eq(ability_mgr._active_ability_effects.size(), 1)
	assert_eq(ability_mgr._active_ability_effects[0].ability_name, "Might is Right")

# ==========================================
# TEST: RulesEngine FNP integration
# ==========================================

func test_rules_engine_fnp_reads_effect_flag():
	"""RulesEngine.get_unit_fnp should return effect-granted FNP when set."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	_create_leader_unit("U_PAINBOY_A", 1, [
		{"name": "Dok's Toolz", "type": "Datasheet", "description": "..."}
	])
	_attach_leader_to_unit("U_PAINBOY_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var fnp = RulesEngine.get_unit_fnp(bodyguard)
	assert_eq(fnp, 5, "RulesEngine.get_unit_fnp should return 5 from Dok's Toolz effect flag")

func test_rules_engine_fnp_uses_better_value():
	"""RulesEngine.get_unit_fnp should use the better (lower) FNP between base and effect."""
	_create_bodyguard_unit("U_BOYZ_A", 1)
	# Set a base FNP of 6+
	GameState.state["units"]["U_BOYZ_A"]["meta"]["stats"]["fnp"] = 6

	_create_leader_unit("U_PAINBOY_A", 1, [
		{"name": "Dok's Toolz", "type": "Datasheet", "description": "..."}
	])
	_attach_leader_to_unit("U_PAINBOY_A", "U_BOYZ_A")

	ability_mgr.on_phase_start(GameStateData.Phase.SHOOTING)

	var bodyguard = GameState.state["units"]["U_BOYZ_A"]
	var fnp = RulesEngine.get_unit_fnp(bodyguard)
	assert_eq(fnp, 5, "Should use better FNP 5+ from ability (not base 6+)")
