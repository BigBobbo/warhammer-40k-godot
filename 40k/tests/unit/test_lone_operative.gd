extends "res://addons/gut/test.gd"

# Tests for the LONE OPERATIVE ability implementation (T2-2)
#
# Per Warhammer 40k 10th Edition rules:
# Unless part of an Attached unit, a unit with the Lone Operative ability
# can only be selected as the target of a ranged attack if the attacking
# model is within 12".
#
# These tests verify:
# 1. has_lone_operative() correctly detects Lone Operative in string format
# 2. has_lone_operative() correctly detects Lone Operative in dictionary format
# 3. has_lone_operative() returns false when unit has no Lone Operative
# 4. get_eligible_targets() excludes Lone Operative targets beyond 12"
# 5. get_eligible_targets() includes Lone Operative targets within 12"
# 6. validate_shoot() rejects targeting Lone Operative beyond 12"
# 7. Attached Lone Operative units can be targeted normally

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# has_lone_operative() Tests - String format
# ==========================================

func test_has_lone_operative_string_format():
	"""Lone Operative as a simple string in abilities array should be detected."""
	var unit = {
		"meta": {
			"abilities": ["Lone Operative"]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit), "Should detect Lone Operative as string ability")

func test_has_lone_operative_string_case_insensitive():
	"""Lone Operative detection should be case-insensitive."""
	var unit = {
		"meta": {
			"abilities": ["lone operative"]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit), "Should detect 'lone operative' (lowercase)")

	var unit2 = {
		"meta": {
			"abilities": ["LONE OPERATIVE"]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit2), "Should detect 'LONE OPERATIVE' (uppercase)")

# ==========================================
# has_lone_operative() Tests - Dictionary format
# ==========================================

func test_has_lone_operative_dict_format():
	"""Lone Operative as a dictionary with name key should be detected."""
	var unit = {
		"meta": {
			"abilities": [{"name": "Lone Operative", "description": "This unit has Lone Operative."}]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit), "Should detect Lone Operative as dictionary ability")

func test_has_lone_operative_dict_case_insensitive():
	"""Lone Operative detection in dict format should be case-insensitive."""
	var unit = {
		"meta": {
			"abilities": [{"name": "lone operative", "description": "Unit is a lone operative"}]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit), "Should detect 'lone operative' (lowercase) in dict")

# ==========================================
# has_lone_operative() Tests - Negative cases
# ==========================================

func test_has_lone_operative_returns_false_no_abilities():
	"""Unit with no abilities should not have Lone Operative."""
	var unit = {
		"meta": {
			"abilities": []
		}
	}
	assert_false(rules_engine.has_lone_operative(unit), "Empty abilities should not have Lone Operative")

func test_has_lone_operative_returns_false_no_meta():
	"""Unit with no meta should not have Lone Operative."""
	var unit = {}
	assert_false(rules_engine.has_lone_operative(unit), "No meta should not have Lone Operative")

func test_has_lone_operative_returns_false_other_abilities():
	"""Unit with other abilities but not Lone Operative should return false."""
	var unit = {
		"meta": {
			"abilities": ["Stealth", "Deep Strike"]
		}
	}
	assert_false(rules_engine.has_lone_operative(unit), "Non-Lone Operative abilities should not match")

func test_has_lone_operative_mixed_abilities():
	"""Lone Operative should be found among multiple abilities."""
	var unit = {
		"meta": {
			"abilities": [
				"Stealth",
				{"name": "Lone Operative", "description": "This unit has the Lone Operative ability."},
				"Deep Strike"
			]
		}
	}
	assert_true(rules_engine.has_lone_operative(unit), "Should find Lone Operative among mixed abilities")

# ==========================================
# Targeting restriction tests
# ==========================================

# Helper: Create a board with an actor unit and a Lone Operative target at a given distance
# PX_PER_INCH = 40.0, so 12" = 480px
# Uses meta.weapons format with type "Ranged" so get_unit_weapons() and get_weapon_profile() work
func _create_lone_operative_board(actor_pos: Vector2, target_pos: Vector2, target_has_lone_op: bool, target_attached_to = null, attached_characters: Array = []) -> Dictionary:
	var target_abilities = ["Lone Operative"] if target_has_lone_op else []
	var target_unit = {
		"owner": 2,
		"meta": {
			"name": "Vindicare Assassin",
			"abilities": target_abilities,
			"keywords": ["CHARACTER", "INFANTRY"],
			"weapons": []
		},
		"models": [
			{
				"id": "target_model_1",
				"alive": true,
				"position": {"x": target_pos.x, "y": target_pos.y},
				"base_size_mm": 32
			}
		],
		"flags": {},
	}
	if target_attached_to != null:
		target_unit["attached_to"] = target_attached_to
	if not attached_characters.is_empty():
		target_unit["attachment_data"] = {"attached_characters": attached_characters}

	var board = {
		"units": {
			"actor_unit": {
				"owner": 1,
				"meta": {
					"name": "Tactical Squad",
					"abilities": [],
					"keywords": ["INFANTRY"],
					"weapons": [
						{
							"name": "Bolt Rifle",
							"type": "Ranged",
							"range": "24",
							"attacks": "2",
							"ballistic_skill": "3",
							"strength": "4",
							"ap": "-1",
							"damage": "1",
							"keywords": []
						}
					]
				},
				"models": [
					{
						"id": "actor_model_1",
						"alive": true,
						"position": {"x": actor_pos.x, "y": actor_pos.y},
						"base_size_mm": 32
					}
				],
				"flags": {},
			},
			"target_unit": target_unit
		},
		"terrain": {"pieces": []}
	}
	return board

func test_lone_operative_excluded_from_eligible_targets_beyond_12():
	"""Lone Operative target beyond 12\" should NOT appear in eligible targets."""
	# Place actor at origin, target at 15" away (600px at 40px/inch)
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(700, 100),  # 15" away
		true  # has Lone Operative
	)
	var eligible = rules_engine.get_eligible_targets("actor_unit", board)
	assert_false(eligible.has("target_unit"), "Lone Operative beyond 12\" should not be eligible")

func test_lone_operative_included_in_eligible_targets_within_12():
	"""Lone Operative target within 12\" should appear in eligible targets."""
	# Place actor and target 10" apart (400px)
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(500, 100),  # 10" away
		true  # has Lone Operative
	)
	var eligible = rules_engine.get_eligible_targets("actor_unit", board)
	assert_true(eligible.has("target_unit"), "Lone Operative within 12\" should be eligible")

func test_non_lone_operative_eligible_beyond_12():
	"""Non-Lone Operative target beyond 12\" should still be eligible (if in weapon range)."""
	# Place actor and target 15" apart (600px) but within 24" weapon range
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(700, 100),  # 15" away
		false  # does NOT have Lone Operative
	)
	var eligible = rules_engine.get_eligible_targets("actor_unit", board)
	assert_true(eligible.has("target_unit"), "Non-Lone Operative beyond 12\" should be eligible")

func test_lone_operative_at_exactly_12_inches():
	"""Lone Operative target at exactly 12\" should be eligible (within 12\")."""
	# 12" = 480px center-to-center. With 32mm bases, edge-to-edge will be slightly less.
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(580, 100),  # 12" center-to-center, edge-to-edge < 12"
		true  # has Lone Operative
	)
	var eligible = rules_engine.get_eligible_targets("actor_unit", board)
	assert_true(eligible.has("target_unit"), "Lone Operative at 12\" should be eligible")

# ==========================================
# validate_shoot() restriction tests
# ==========================================

func test_validate_shoot_rejects_lone_operative_beyond_12():
	"""validate_shoot should reject targeting a Lone Operative beyond 12\"."""
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(700, 100),  # 15" away
		true  # has Lone Operative
	)
	var action = {
		"actor_unit_id": "actor_unit",
		"payload": {
			"assignments": [
				{
					"weapon_id": "bolt_rifle",
					"target_unit_id": "target_unit"
				}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	assert_false(result.valid, "Should reject targeting Lone Operative beyond 12\"")
	var found_lone_op_error = false
	for error in result.errors:
		if "Lone Operative" in error:
			found_lone_op_error = true
			break
	assert_true(found_lone_op_error, "Error should mention Lone Operative")

func test_validate_shoot_allows_lone_operative_within_12():
	"""validate_shoot should allow targeting a Lone Operative within 12\"."""
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(500, 100),  # 10" away
		true  # has Lone Operative
	)
	var action = {
		"actor_unit_id": "actor_unit",
		"payload": {
			"assignments": [
				{
					"weapon_id": "bolt_rifle",
					"target_unit_id": "target_unit"
				}
			]
		}
	}
	var result = rules_engine.validate_shoot(action, board)
	# Check there's no Lone Operative error (there may be other errors like visibility)
	var found_lone_op_error = false
	for error in result.errors:
		if "Lone Operative" in error:
			found_lone_op_error = true
			break
	assert_false(found_lone_op_error, "Should not have Lone Operative error when within 12\"")

# ==========================================
# Attached unit exception tests
# ==========================================

func test_lone_operative_attached_can_be_targeted_at_any_range():
	"""Lone Operative unit that is attached to a bodyguard should be targetable normally.
	Note: Units with attached_to set are already filtered out by get_eligible_targets()
	as they are targeted through their bodyguard. This test verifies the bodyguard unit
	(which has attached characters) is NOT restricted by Lone Operative."""
	# Create a bodyguard unit that has an attached Lone Operative character
	var board = _create_lone_operative_board(
		Vector2(100, 100),
		Vector2(700, 100),  # 15" away
		true,  # has Lone Operative
		null,  # not attached_to anything (this IS the bodyguard/parent)
		["character_1"]  # has attached characters (so it's leading a squad)
	)
	var eligible = rules_engine.get_eligible_targets("actor_unit", board)
	assert_true(eligible.has("target_unit"), "Lone Operative leading a squad should be targetable at any range")
