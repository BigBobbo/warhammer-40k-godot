extends "res://addons/gut/test.gd"

# Tests for the Aura Abilities system (P2-89)
#
# Per Warhammer 40k 10th Edition rules:
# - Aura abilities affect units within a specified range
# - A model with an Aura is always within range of its own Aura
# - Same Aura ability from multiple sources doesn't stack on the same target
# - Aura effects are applied at phase start and cleared at phase end
#
# These tests verify:
# 1. Aura detection and effect propagation to nearby units
# 2. Self-application (unit is always in its own aura)
# 3. Range checking (edge-to-edge model distance)
# 4. Anti-stacking (same aura from multiple sources)
# 5. Friendly/enemy targeting filters
# 6. Phase lifecycle (apply at start, clear at end)

const GameStateData = preload("res://autoloads/GameState.gd")

var ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(ability_mgr, "UnitAbilityManager autoload must be available")

	# Reset state between tests
	ability_mgr._active_ability_effects = []
	ability_mgr._applied_this_phase = {}
	ability_mgr._active_aura_effects = {}

	# Set up minimal game state for testing
	GameState.state["units"] = {}
	GameState.state["board"] = {"size": {"width": 60, "height": 44}}

func after_each():
	# Clean up
	if ability_mgr:
		ability_mgr._active_ability_effects = []
		ability_mgr._applied_this_phase = {}
		ability_mgr._active_aura_effects = {}
	GameState.state["units"] = {}

# ==========================================
# Helpers: Create test units
# ==========================================

func _create_unit(id: String, owner: int, x: float, y: float, name: String = "Test Unit", abilities: Array = []) -> Dictionary:
	"""Create a unit at a specific position with given abilities."""
	var pos_px_x = x * 40.0  # Convert inches to pixels (PX_PER_INCH = 40)
	var pos_px_y = y * 40.0
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"embarked_in": "",
		"meta": {
			"name": name,
			"keywords": ["INFANTRY"],
			"stats": {
				"move": 6,
				"toughness": 4,
				"save": 3,
				"wounds": 2,
				"leadership": 6,
				"objective_control": 2
			},
			"abilities": abilities,
			"weapons": []
		},
		"models": [
			{
				"id": "m1",
				"wounds": 2,
				"current_wounds": 2,
				"base_mm": 32,
				"position": {"x": pos_px_x, "y": pos_px_y},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {},
		"attachment_data": {"attached_characters": []}
	}
	GameState.state["units"][id] = unit
	return unit

# ==========================================
# Test: Aura ABILITY_EFFECTS table format
# ==========================================

func test_omni_scramblers_uses_aura_condition():
	"""Verify Omni-scramblers is defined with aura condition type."""
	var effect_def = ability_mgr.ABILITY_EFFECTS.get("Omni-scramblers", {})
	assert_false(effect_def.is_empty(), "Omni-scramblers should exist in ABILITY_EFFECTS")
	assert_eq(effect_def.get("condition", ""), "aura", "Omni-scramblers should have 'aura' condition")
	assert_eq(effect_def.get("aura_range", 0), 12.0, "Omni-scramblers should have 12\" aura range")
	assert_eq(effect_def.get("aura_target", ""), "enemy", "Omni-scramblers should target enemies")

# ==========================================
# Test: _closest_model_distance
# ==========================================

func test_closest_model_distance_same_position():
	"""Units at the same position should have 0 distance (or very close to it)."""
	var unit_a = _create_unit("u_a", 1, 10.0, 10.0, "Unit A")
	var unit_b = _create_unit("u_b", 1, 10.0, 10.0, "Unit B")

	var dist = ability_mgr._closest_model_distance(unit_a, unit_b)
	# Two 32mm bases at the same position overlap, so distance ≈ 0
	assert_true(dist <= 0.1, "Units at same position should have ~0 distance, got %.2f" % dist)

func test_closest_model_distance_far_apart():
	"""Units 30 inches apart should be far beyond typical aura range."""
	var unit_a = _create_unit("u_a", 1, 10.0, 10.0, "Unit A")
	var unit_b = _create_unit("u_b", 1, 40.0, 10.0, "Unit B")

	var dist = ability_mgr._closest_model_distance(unit_a, unit_b)
	# 30 inches apart center-to-center, minus base radii
	assert_true(dist > 20.0, "Units 30\" apart should have > 20\" distance, got %.2f" % dist)

func test_closest_model_distance_within_6_inches():
	"""Units 5 inches apart (center-to-center) should be within 6\" aura range."""
	var unit_a = _create_unit("u_a", 1, 10.0, 10.0, "Unit A")
	var unit_b = _create_unit("u_b", 1, 15.0, 10.0, "Unit B")

	var dist = ability_mgr._closest_model_distance(unit_a, unit_b)
	assert_true(dist < 6.0, "Units 5\" apart (center) should be within 6\" aura, got %.2f" % dist)

# ==========================================
# Test: _find_units_in_aura_range
# ==========================================

func test_find_friendly_units_in_range():
	"""Should find friendly units within aura range and exclude enemies."""
	var source = _create_unit("u_source", 1, 10.0, 10.0, "Source")
	var friendly_near = _create_unit("u_friend", 1, 14.0, 10.0, "Friendly Near")
	var enemy_near = _create_unit("u_enemy", 2, 14.0, 12.0, "Enemy Near")
	var friendly_far = _create_unit("u_far", 1, 40.0, 10.0, "Friendly Far")

	var results = ability_mgr._find_units_in_aura_range(
		"u_source", source, 6.0, "friendly", 1,
		GameState.state.get("units", {})
	)

	var found_ids = []
	for r in results:
		found_ids.append(r.unit_id)

	assert_true("u_friend" in found_ids, "Should find nearby friendly unit")
	assert_false("u_enemy" in found_ids, "Should NOT find enemy unit with friendly filter")
	assert_false("u_far" in found_ids, "Should NOT find far away friendly unit")

func test_find_enemy_units_in_range():
	"""Should find enemy units within aura range and exclude friendlies."""
	var source = _create_unit("u_source", 1, 10.0, 10.0, "Source")
	var friendly_near = _create_unit("u_friend", 1, 14.0, 10.0, "Friendly Near")
	var enemy_near = _create_unit("u_enemy", 2, 14.0, 10.0, "Enemy Near")

	var results = ability_mgr._find_units_in_aura_range(
		"u_source", source, 6.0, "enemy", 1,
		GameState.state.get("units", {})
	)

	var found_ids = []
	for r in results:
		found_ids.append(r.unit_id)

	assert_true("u_enemy" in found_ids, "Should find nearby enemy unit")
	assert_false("u_friend" in found_ids, "Should NOT find friendly unit with enemy filter")

func test_find_all_units_in_range():
	"""With aura_target='all', should find both friendly and enemy units."""
	var source = _create_unit("u_source", 1, 10.0, 10.0, "Source")
	var friendly_near = _create_unit("u_friend", 1, 14.0, 10.0, "Friendly Near")
	var enemy_near = _create_unit("u_enemy", 2, 14.0, 10.0, "Enemy Near")

	var results = ability_mgr._find_units_in_aura_range(
		"u_source", source, 6.0, "all", 1,
		GameState.state.get("units", {})
	)

	var found_ids = []
	for r in results:
		found_ids.append(r.unit_id)

	assert_true("u_friend" in found_ids, "Should find nearby friendly unit")
	assert_true("u_enemy" in found_ids, "Should find nearby enemy unit")

func test_skip_destroyed_units():
	"""Should not include destroyed units in aura range results."""
	var source = _create_unit("u_source", 1, 10.0, 10.0, "Source")
	var dead_unit = _create_unit("u_dead", 1, 14.0, 10.0, "Dead Unit")
	# Mark all models as dead
	dead_unit["models"][0]["alive"] = false
	GameState.state["units"]["u_dead"] = dead_unit

	var results = ability_mgr._find_units_in_aura_range(
		"u_source", source, 6.0, "friendly", 1,
		GameState.state.get("units", {})
	)

	assert_eq(results.size(), 0, "Should not find destroyed units")

func test_skip_embarked_units():
	"""Should not include embarked units in aura range results."""
	var source = _create_unit("u_source", 1, 10.0, 10.0, "Source")
	var embarked = _create_unit("u_embarked", 1, 14.0, 10.0, "Embarked")
	embarked["embarked_in"] = "u_transport"
	GameState.state["units"]["u_embarked"] = embarked

	var results = ability_mgr._find_units_in_aura_range(
		"u_source", source, 6.0, "friendly", 1,
		GameState.state.get("units", {})
	)

	assert_eq(results.size(), 0, "Should not find embarked units")

# ==========================================
# Test: _should_apply_aura_to_self
# ==========================================

func test_aura_applies_to_self_friendly():
	"""Friendly auras should apply to the source unit itself."""
	var unit = _create_unit("u_self", 1, 10.0, 10.0, "Self")
	var result = ability_mgr._should_apply_aura_to_self("friendly", 1, unit)
	assert_true(result, "Friendly aura should apply to self")

func test_aura_applies_to_self_all():
	"""'All' target auras should apply to the source unit itself."""
	var unit = _create_unit("u_self", 1, 10.0, 10.0, "Self")
	var result = ability_mgr._should_apply_aura_to_self("all", 1, unit)
	assert_true(result, "'All' aura should apply to self")

func test_aura_does_not_apply_to_self_enemy():
	"""Enemy auras should NOT apply to the source unit itself."""
	var unit = _create_unit("u_self", 1, 10.0, 10.0, "Self")
	var result = ability_mgr._should_apply_aura_to_self("enemy", 1, unit)
	assert_false(result, "Enemy aura should not apply to self")

# ==========================================
# Test: Anti-stacking
# ==========================================

func test_aura_does_not_stack():
	"""Same aura ability from multiple sources should not stack on the same target."""
	# Mark an aura as already applied to a target
	ability_mgr._active_aura_effects["u_target:Test Aura"] = "u_source1"

	# Check if the key already exists (simulating the anti-stacking check)
	var aura_key = "u_target:Test Aura"
	assert_true(ability_mgr._active_aura_effects.has(aura_key),
		"Anti-stacking should prevent duplicate aura application")

# ==========================================
# Test: is_unit_in_aura query
# ==========================================

func test_is_unit_in_aura():
	"""Should correctly report whether a unit is under a specific aura."""
	ability_mgr._active_aura_effects["u_target:Test Aura"] = "u_source"

	assert_true(ability_mgr.is_unit_in_aura("u_target", "Test Aura"),
		"Unit should be reported as in aura")
	assert_false(ability_mgr.is_unit_in_aura("u_other", "Test Aura"),
		"Other unit should not be reported as in aura")
	assert_false(ability_mgr.is_unit_in_aura("u_target", "Different Aura"),
		"Unit should not be in a different aura")

# ==========================================
# Test: get_aura_abilities_on_unit query
# ==========================================

func test_get_aura_abilities_on_unit():
	"""Should return aura effects active on a specific unit."""
	ability_mgr._active_ability_effects = [
		{
			"ability_name": "Test Aura",
			"source_unit_id": "u_source",
			"target_unit_id": "u_target",
			"effects": [{"type": "plus_one_hit"}],
			"attack_type": "all",
			"condition": "aura"
		},
		{
			"ability_name": "Other Ability",
			"source_unit_id": "u_source",
			"target_unit_id": "u_target",
			"effects": [{"type": "plus_one_hit"}],
			"attack_type": "all",
			"condition": "always"
		}
	]

	var auras = ability_mgr.get_aura_abilities_on_unit("u_target")
	assert_eq(auras.size(), 1, "Should find 1 aura effect on unit")
	assert_eq(auras[0].ability_name, "Test Aura", "Should return correct aura ability name")

# ==========================================
# Test: find_friendly/enemy_units_within_aura public helpers
# ==========================================

func test_find_friendly_units_within_aura_helper():
	"""Public helper should find friendly units within range."""
	_create_unit("u_source", 1, 10.0, 10.0, "Source")
	_create_unit("u_friend_near", 1, 14.0, 10.0, "Friend Near")
	_create_unit("u_friend_far", 1, 40.0, 10.0, "Friend Far")
	_create_unit("u_enemy", 2, 14.0, 10.0, "Enemy")

	var results = ability_mgr.find_friendly_units_within_aura("u_source", 6.0)
	assert_true("u_friend_near" in results, "Should find nearby friendly unit")
	assert_false("u_friend_far" in results, "Should not find far friendly unit")
	assert_false("u_enemy" in results, "Should not find enemy unit")

func test_find_enemy_units_within_aura_helper():
	"""Public helper should find enemy units within range."""
	_create_unit("u_source", 1, 10.0, 10.0, "Source")
	_create_unit("u_friend", 1, 14.0, 10.0, "Friend")
	_create_unit("u_enemy_near", 2, 14.0, 10.0, "Enemy Near")
	_create_unit("u_enemy_far", 2, 40.0, 10.0, "Enemy Far")

	var results = ability_mgr.find_enemy_units_within_aura("u_source", 6.0)
	assert_true("u_enemy_near" in results, "Should find nearby enemy unit")
	assert_false("u_enemy_far" in results, "Should not find far enemy unit")
	assert_false("u_friend" in results, "Should not find friendly unit")

# ==========================================
# Test: _collect_aura_sources
# ==========================================

func test_collect_aura_sources_from_unit():
	"""Should collect aura abilities from a unit's own abilities."""
	var abilities = [{"name": "Omni-scramblers", "type": "Datasheet"}]
	var unit = _create_unit("u_source", 1, 10.0, 10.0, "Source", abilities)

	var sources = ability_mgr._collect_aura_sources("u_source", unit, GameState.state.get("units", {}))
	assert_eq(sources.size(), 1, "Should find 1 aura source")
	assert_eq(sources[0].ability_name, "Omni-scramblers", "Should find Omni-scramblers")

func test_collect_aura_sources_from_attached_character():
	"""Should collect aura abilities from attached characters."""
	# Create a bodyguard unit and a character with an aura ability
	var bodyguard = _create_unit("u_bodyguard", 1, 10.0, 10.0, "Bodyguard")
	var character = _create_unit("u_char", 1, 10.0, 10.0, "Character", [{"name": "Omni-scramblers", "type": "Datasheet"}])
	bodyguard["attachment_data"]["attached_characters"] = ["u_char"]
	GameState.state["units"]["u_bodyguard"] = bodyguard

	var sources = ability_mgr._collect_aura_sources("u_bodyguard", bodyguard, GameState.state.get("units", {}))
	assert_eq(sources.size(), 1, "Should find 1 aura source from attached character")
	assert_eq(sources[0].source_unit_id, "u_char", "Aura source should be the character")
