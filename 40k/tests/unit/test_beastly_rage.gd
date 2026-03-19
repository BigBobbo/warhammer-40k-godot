extends "res://addons/gut/test.gd"

# Tests for the Beastly Rage ability (Beastboss on Squigosaur)
# Verifies that melee weapons gain DEVASTATING WOUNDS after charging.
# Since characters fight with their own unit_id, this naturally restricts
# the effect to the Beastboss's attacks only (not the bodyguard unit's).

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Build board with Beastboss attacker
# ==========================================

func _make_beastboss_board(charged: bool, weapon_special_rules: String = "") -> Dictionary:
	"""Create a board with a Beastboss attacker (with Beastly Rage) and a target unit."""
	var flags = {}
	if charged:
		flags["charged_this_turn"] = true

	return {
		"units": {
			"beastboss_unit": {
				"owner": 1,
				"flags": flags,
				"models": [{
					"alive": true,
					"current_wounds": 7,
					"wounds": 7,
					"position": {"x": 100, "y": 100}
				}],
				"meta": {
					"name": "Beastboss on Squigosaur",
					"stats": {
						"toughness": 7,
						"save": 4,
						"wounds": 7
					},
					"abilities": ["Beastly Rage"],
					"weapons": [{
						"name": "Beastchoppa",
						"type": "Melee",
						"range": "Melee",
						"attacks": "5",
						"weapon_skill": "2",
						"strength": "7",
						"ap": "-1",
						"damage": "2",
						"special_rules": weapon_special_rules
					}],
					"keywords": ["MONSTER", "CHARACTER", "ORKS"]
				}
			},
			"target_unit": {
				"owner": 2,
				"models": [
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 130, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 160, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 190, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 220, "y": 100}},
					{"alive": true, "current_wounds": 2, "wounds": 2, "position": {"x": 250, "y": 100}}
				],
				"meta": {
					"name": "Test Target",
					"stats": {
						"toughness": 4,
						"save": 3,
						"wounds": 2
					},
					"keywords": ["INFANTRY"]
				}
			}
		}
	}

func _make_action(weapon_id: String = "beastchoppa", attacker_id: String = "beastboss_unit") -> Dictionary:
	return {
		"actor_unit_id": attacker_id,
		"payload": {
			"assignments": [{
				"attacker": attacker_id,
				"target": "target_unit",
				"weapon": weapon_id
			}]
		}
	}

# ==========================================
# has_beastly_rage_active() Tests
# ==========================================

func test_has_beastly_rage_active_when_charged():
	"""Beastly Rage should be active when unit has the ability and charged this turn."""
	var board = _make_beastboss_board(true)
	var unit = board.units.beastboss_unit
	assert_true(RulesEngine.has_beastly_rage_active(unit),
		"Should return true when unit has Beastly Rage and charged")

func test_has_beastly_rage_inactive_when_not_charged():
	"""Beastly Rage should be inactive when unit did NOT charge this turn."""
	var board = _make_beastboss_board(false)
	var unit = board.units.beastboss_unit
	assert_false(RulesEngine.has_beastly_rage_active(unit),
		"Should return false when unit has Beastly Rage but did not charge")

func test_has_beastly_rage_inactive_without_ability():
	"""Beastly Rage should be inactive for units without the ability, even if they charged."""
	var unit = {
		"flags": {"charged_this_turn": true},
		"meta": {
			"abilities": ["Some Other Ability"],
			"keywords": ["INFANTRY"]
		}
	}
	assert_false(RulesEngine.has_beastly_rage_active(unit),
		"Should return false when unit charged but lacks Beastly Rage ability")

func test_has_beastly_rage_with_dict_ability_format():
	"""Beastly Rage should work when abilities are in Dictionary format."""
	var unit = {
		"flags": {"charged_this_turn": true},
		"meta": {
			"abilities": [{"name": "Beastly Rage"}],
			"keywords": ["MONSTER", "CHARACTER", "ORKS"]
		}
	}
	assert_true(RulesEngine.has_beastly_rage_active(unit),
		"Should work with Dictionary-format abilities")

# ==========================================
# Melee Resolution Integration Tests
# ==========================================

func test_beastly_rage_grants_devastating_wounds_on_charge():
	"""When Beastboss charged, wound rolls should show devastating_wounds_weapon=true."""
	var board = _make_beastboss_board(true)
	var action = _make_action()
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")

	# Find wound dice block
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	assert_not_null(wound_dice, "Should have a wound roll dice block")
	if wound_dice:
		assert_true(wound_dice.get("devastating_wounds_weapon", false),
			"Devastating Wounds should be active after charging with Beastly Rage")

func test_beastly_rage_no_devastating_wounds_without_charge():
	"""When Beastboss did NOT charge, devastating wounds should NOT be granted."""
	var board = _make_beastboss_board(false)
	var action = _make_action()
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")

	# Find wound dice block
	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_false(wound_dice.get("devastating_wounds_weapon", false),
			"Devastating Wounds should NOT be active when Beastboss did not charge")

func test_beastly_rage_stacks_with_weapon_devastating_wounds():
	"""If weapon already has DW, Beastly Rage should not cause issues (OR logic)."""
	var board = _make_beastboss_board(true, "devastating wounds")
	var action = _make_action()
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed")

	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_true(wound_dice.get("devastating_wounds_weapon", false),
			"Devastating Wounds should still be active (weapon + ability)")

func test_bodyguard_unit_does_not_get_beastly_rage():
	"""A bodyguard unit (Squighog Boyz) should NOT gain DW even when it charged,
	because it doesn't have the Beastly Rage ability."""
	var board = _make_beastboss_board(true)
	# Add a bodyguard unit without Beastly Rage that also charged
	board.units["squighog_unit"] = {
		"owner": 1,
		"flags": {"charged_this_turn": true},
		"models": [
			{"alive": true, "current_wounds": 3, "wounds": 3, "position": {"x": 100, "y": 130}},
			{"alive": true, "current_wounds": 3, "wounds": 3, "position": {"x": 130, "y": 130}}
		],
		"meta": {
			"name": "Squighog Boyz",
			"stats": {"toughness": 7, "save": 4, "wounds": 3},
			"abilities": ["Monster Hunters"],
			"weapons": [{
				"name": "Stikka",
				"type": "Melee",
				"range": "Melee",
				"attacks": "3",
				"weapon_skill": "3",
				"strength": "5",
				"ap": "-1",
				"damage": "1",
				"special_rules": ""
			}],
			"keywords": ["CAVALRY", "ORKS"]
		}
	}
	var action = {
		"actor_unit_id": "squighog_unit",
		"payload": {
			"assignments": [{
				"attacker": "squighog_unit",
				"target": "target_unit",
				"weapon": "stikka"
			}]
		}
	}
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Melee resolution should succeed for Squighog Boyz")

	var wound_dice = null
	for dice in result.dice:
		if dice.context == "wound_roll_melee":
			wound_dice = dice
			break

	if wound_dice:
		assert_false(wound_dice.get("devastating_wounds_weapon", false),
			"Squighog Boyz should NOT have Devastating Wounds (only Beastboss gets it)")
