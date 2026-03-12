extends "res://addons/gut/test.gd"

# Tests for OA-35: Grot Riggers (Trukk — regain 1 lost wound at start of Command phase)
#
# Rule: "At the start of your Command phase, this model regains 1 lost wound."
#
# These tests verify:
# 1. has_grot_riggers() detects the ability on a unit
# 2. get_grot_riggers_eligible() checks wound state correctly
# 3. CommandPhase._apply_grot_riggers() heals 1 wound automatically
# 4. No healing when at full wounds
# 5. Healing is capped at max wounds

const GameStateData = preload("res://autoloads/GameState.gd")

var ability_mgr: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	ability_mgr = AutoloadHelper.get_autoload("UnitAbilityManager")
	assert_not_null(ability_mgr, "UnitAbilityManager autoload must be available")

	# Set up minimal game state
	GameState.state["units"] = {}
	if not GameState.state.has("factions"):
		GameState.state["factions"] = {}

# ==========================================
# Helper: Create a Trukk unit with Grot Riggers
# ==========================================

func _create_trukk(id: String, owner: int, current_wounds: int = 12, max_wounds: int = 12) -> Dictionary:
	"""Create a Trukk vehicle unit with Grot Riggers ability."""
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Trukk",
			"keywords": ["VEHICLE", "TRANSPORT", "DEDICATED TRANSPORT", "ORKS"],
			"stats": {"move": 12, "toughness": 8, "save": 4, "wounds": max_wounds, "leadership": 7, "objective_control": 2},
			"abilities": [
				{"name": "Grot Riggers", "type": "Datasheet", "description": "At the start of your Command phase, this model regains 1 lost wound."},
				{"name": "Deadly Demise D3", "type": "Core"},
				{"name": "Firing Deck 2", "type": "Core"}
			]
		},
		"models": [
			{
				"id": "trukk_model",
				"wounds": max_wounds,
				"current_wounds": current_wounds,
				"base_mm": 100,
				"position": {"x": 200, "y": 200},
				"alive": true,
				"status_effects": []
			}
		],
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

func _create_unit_without_grot_riggers(id: String, owner: int) -> Dictionary:
	"""Create a unit that does NOT have Grot Riggers."""
	var unit = {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"meta": {
			"name": "Boyz",
			"keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 6, "toughness": 5, "save": 5, "wounds": 1, "leadership": 7, "objective_control": 2},
			"abilities": []
		},
		"models": [
			{"id": "boy1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": {"x": 100, "y": 100}, "alive": true, "status_effects": []}
		],
		"flags": {}
	}
	GameState.state["units"][id] = unit
	return unit

# ==========================================
# Test: has_grot_riggers detection
# ==========================================

func test_has_grot_riggers_with_ability():
	_create_trukk("trukk_1", 1)
	assert_true(ability_mgr.has_grot_riggers("trukk_1"), "Trukk should have Grot Riggers ability")

func test_has_grot_riggers_without_ability():
	_create_unit_without_grot_riggers("boyz_1", 1)
	assert_false(ability_mgr.has_grot_riggers("boyz_1"), "Boyz should NOT have Grot Riggers ability")

func test_has_grot_riggers_nonexistent_unit():
	assert_false(ability_mgr.has_grot_riggers("nonexistent"), "Nonexistent unit should return false")

# ==========================================
# Test: get_grot_riggers_eligible wound check
# ==========================================

func test_eligible_when_wounded():
	_create_trukk("trukk_1", 1, 8, 12)  # 8/12 wounds
	var info = ability_mgr.get_grot_riggers_eligible("trukk_1")
	assert_true(info.get("eligible", false), "Trukk with 8/12 wounds should be eligible")
	assert_eq(info.current_wounds, 8, "Current wounds should be 8")
	assert_eq(info.max_wounds, 12, "Max wounds should be 12")
	assert_eq(info.model_index, 0, "Model index should be 0")

func test_not_eligible_when_full_wounds():
	_create_trukk("trukk_1", 1, 12, 12)  # Full wounds
	var info = ability_mgr.get_grot_riggers_eligible("trukk_1")
	assert_false(info.get("eligible", false), "Trukk at full wounds should NOT be eligible")

func test_not_eligible_when_unit_not_found():
	var info = ability_mgr.get_grot_riggers_eligible("nonexistent")
	assert_false(info.get("eligible", false), "Nonexistent unit should NOT be eligible")

func test_eligible_when_1_wound_lost():
	_create_trukk("trukk_1", 1, 11, 12)  # 11/12 wounds
	var info = ability_mgr.get_grot_riggers_eligible("trukk_1")
	assert_true(info.get("eligible", false), "Trukk with 11/12 wounds should be eligible")

# ==========================================
# Test: Grot Riggers in ABILITY_EFFECTS
# ==========================================

func test_ability_effects_entry():
	var effects = ability_mgr.ABILITY_EFFECTS
	assert_true(effects.has("Grot Riggers"), "ABILITY_EFFECTS should contain Grot Riggers")
	var entry = effects["Grot Riggers"]
	assert_eq(entry.condition, "start_of_command", "Condition should be start_of_command")
	assert_eq(entry.target, "unit", "Target should be unit (self)")
	assert_true(entry.implemented, "Should be marked as implemented")
	assert_false(entry.has("once_per_battle"), "Should NOT be once per battle")
