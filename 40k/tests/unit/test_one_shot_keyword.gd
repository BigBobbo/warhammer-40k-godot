extends "res://addons/gut/test.gd"

# Tests for the ONE SHOT weapon keyword implementation (T4-2)
# Tests the ACTUAL RulesEngine methods, not duplicate local implementations
#
# Per Warhammer 40k 10e rules: "Weapons with [ONE SHOT] can only be fired once
# per battle. After firing, the weapon is unavailable for the rest of the game."
#
# One Shot is tracked per model — each model with a one-shot weapon gets one use.

const GameStateData = preload("res://autoloads/GameState.gd")

var rules_engine: Node
var game_state: Node

func before_each():
	# Verify autoloads are available
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return

	# Get actual autoload singletons
	rules_engine = AutoloadHelper.get_rules_engine()
	game_state = AutoloadHelper.get_game_state()

	assert_not_null(rules_engine, "RulesEngine autoload must be available")
	assert_not_null(game_state, "GameState autoload must be available")

# ==========================================
# is_one_shot_weapon() Tests — Built-in Weapon Profiles
# ==========================================

func test_is_one_shot_weapon_returns_true_for_one_shot_missile():
	"""Test that one_shot_missile is recognized as a One Shot weapon"""
	var result = rules_engine.is_one_shot_weapon("one_shot_missile")
	assert_true(result, "one_shot_missile should be recognized as a One Shot weapon")

func test_is_one_shot_weapon_returns_true_for_one_shot_blast():
	"""Test that one_shot_blast is recognized as a One Shot weapon"""
	var result = rules_engine.is_one_shot_weapon("one_shot_blast")
	assert_true(result, "one_shot_blast should be a One Shot weapon")

func test_is_one_shot_weapon_returns_true_for_one_shot_test():
	"""Test that one_shot_test is recognized as a One Shot weapon"""
	var result = rules_engine.is_one_shot_weapon("one_shot_test")
	assert_true(result, "one_shot_test should be a One Shot weapon")

func test_is_one_shot_weapon_returns_false_for_bolt_rifle():
	"""Test that bolt_rifle is NOT a One Shot weapon"""
	var result = rules_engine.is_one_shot_weapon("bolt_rifle")
	assert_false(result, "bolt_rifle should NOT be a One Shot weapon")

func test_is_one_shot_weapon_returns_false_for_lascannon():
	"""Test that lascannon is NOT a One Shot weapon"""
	var result = rules_engine.is_one_shot_weapon("lascannon")
	assert_false(result, "lascannon should NOT be a One Shot weapon")

func test_is_one_shot_weapon_returns_false_for_unknown_weapon():
	"""Test that unknown weapon returns false"""
	var result = rules_engine.is_one_shot_weapon("nonexistent_weapon")
	assert_false(result, "Unknown weapon should return false")

# ==========================================
# is_one_shot_weapon() Tests — Board Weapon with special_rules
# ==========================================

func test_is_one_shot_weapon_from_special_rules():
	"""Test that One Shot is detected from special_rules string (army list format)"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "hunter_killer_missile",
						"name": "Hunter-killer Missile",
						"range": "48",
						"attacks": "1",
						"ballistic_skill": "3",
						"strength": "14",
						"ap": "-3",
						"damage": "D6",
						"special_rules": "one shot",
						"keywords": []
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["hunter_killer_missile"]}]
			}
		}
	}
	var result = rules_engine.is_one_shot_weapon("hunter_killer_missile", board)
	assert_true(result, "Should detect One Shot from special_rules string")

func test_is_one_shot_weapon_case_insensitive_special_rules():
	"""Test that One Shot detection is case-insensitive in special_rules"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "hk_missile",
						"name": "HK Missile",
						"range": "48",
						"attacks": "1",
						"ballistic_skill": "3",
						"strength": "14",
						"ap": "-3",
						"damage": "D6",
						"special_rules": "One Shot, Anti-Vehicle 4+",
						"keywords": []
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["hk_missile"]}]
			}
		}
	}
	var result = rules_engine.is_one_shot_weapon("hk_missile", board)
	assert_true(result, "Should detect One Shot (capitalized) from special_rules")

func test_is_one_shot_weapon_from_keywords_array():
	"""Test that One Shot is detected from keywords array"""
	var board = {
		"units": {
			"test_unit": {
				"meta": {
					"weapons": [{
						"id": "custom_missile",
						"name": "Custom Missile",
						"range": "48",
						"attacks": "1",
						"ballistic_skill": "3",
						"strength": "10",
						"ap": "-2",
						"damage": "3",
						"special_rules": "",
						"keywords": ["ONE SHOT"]
					}]
				},
				"models": [{"id": "m1", "alive": true, "weapons": ["custom_missile"]}]
			}
		}
	}
	var result = rules_engine.is_one_shot_weapon("custom_missile", board)
	assert_true(result, "Should detect ONE SHOT from keywords array")

# ==========================================
# Weapon Profile Tests
# ==========================================

func test_weapon_profile_one_shot_missile_has_keyword():
	"""Test that one_shot_missile profile contains ONE SHOT keyword"""
	var profile = rules_engine.get_weapon_profile("one_shot_missile")
	assert_false(profile.is_empty(), "Should find one_shot_missile profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "ONE SHOT", "one_shot_missile should have ONE SHOT keyword")

func test_weapon_profile_one_shot_blast_has_both_keywords():
	"""Test that one_shot_blast profile has both ONE SHOT and BLAST keywords"""
	var profile = rules_engine.get_weapon_profile("one_shot_blast")
	assert_false(profile.is_empty(), "Should find one_shot_blast profile")
	var keywords = profile.get("keywords", [])
	assert_has(keywords, "ONE SHOT", "one_shot_blast should have ONE SHOT keyword")
	assert_has(keywords, "BLAST", "one_shot_blast should have BLAST keyword")

func test_weapon_profile_bolt_rifle_no_one_shot_keyword():
	"""Test that bolt_rifle profile does NOT contain ONE SHOT keyword"""
	var profile = rules_engine.get_weapon_profile("bolt_rifle")
	assert_false(profile.is_empty(), "Should find bolt_rifle profile")
	var keywords = profile.get("keywords", [])
	assert_does_not_have(keywords, "ONE SHOT", "Bolt rifle should NOT have ONE SHOT keyword")

# ==========================================
# has_fired_one_shot() / mark_one_shot_fired_diffs() Tests
# ==========================================

func test_has_fired_one_shot_returns_false_when_not_fired():
	"""Test that has_fired_one_shot returns false when weapon hasn't been fired"""
	var unit = {
		"flags": {}
	}
	var result = rules_engine.has_fired_one_shot(unit, "m1", "one_shot_missile")
	assert_false(result, "Should return false when weapon hasn't been fired")

func test_has_fired_one_shot_returns_true_when_fired():
	"""Test that has_fired_one_shot returns true after weapon is marked as fired"""
	var unit = {
		"flags": {
			"one_shot_fired": {
				"m1": ["one_shot_missile"]
			}
		}
	}
	var result = rules_engine.has_fired_one_shot(unit, "m1", "one_shot_missile")
	assert_true(result, "Should return true when weapon has been fired")

func test_has_fired_one_shot_different_model_not_affected():
	"""Test that firing for one model doesn't affect another model"""
	var unit = {
		"flags": {
			"one_shot_fired": {
				"m1": ["one_shot_missile"]
			}
		}
	}
	var result = rules_engine.has_fired_one_shot(unit, "m2", "one_shot_missile")
	assert_false(result, "Model m2 should NOT be affected by m1's one-shot usage")

func test_has_fired_one_shot_different_weapon_not_affected():
	"""Test that firing one weapon doesn't affect a different one-shot weapon"""
	var unit = {
		"flags": {
			"one_shot_fired": {
				"m1": ["one_shot_missile"]
			}
		}
	}
	var result = rules_engine.has_fired_one_shot(unit, "m1", "one_shot_blast")
	assert_false(result, "Different weapon should NOT be affected")

func test_mark_one_shot_fired_diffs_creates_correct_diff():
	"""Test that mark_one_shot_fired_diffs generates correct state diffs"""
	var unit = {
		"flags": {}
	}
	var diffs = rules_engine.mark_one_shot_fired_diffs("unit_1", unit, "m1", "one_shot_missile")
	assert_eq(diffs.size(), 1, "Should generate exactly 1 diff")
	assert_eq(diffs[0].op, "set", "Diff should be a set operation")
	assert_eq(diffs[0].path, "units.unit_1.flags.one_shot_fired", "Path should target one_shot_fired")
	var value = diffs[0].value
	assert_true(value.has("m1"), "Value should have model m1")
	assert_has(value.m1, "one_shot_missile", "m1 should contain one_shot_missile")

func test_mark_one_shot_fired_diffs_appends_to_existing():
	"""Test that marking a second one-shot weapon appends to the existing list"""
	var unit = {
		"flags": {
			"one_shot_fired": {
				"m1": ["one_shot_missile"]
			}
		}
	}
	var diffs = rules_engine.mark_one_shot_fired_diffs("unit_1", unit, "m1", "one_shot_blast")
	assert_eq(diffs.size(), 1, "Should generate exactly 1 diff")
	var value = diffs[0].value
	assert_true(value.has("m1"), "Value should have model m1")
	assert_has(value.m1, "one_shot_missile", "Should still contain one_shot_missile")
	assert_has(value.m1, "one_shot_blast", "Should also contain one_shot_blast")

func test_mark_one_shot_fired_diffs_no_duplicate():
	"""Test that marking the same weapon again doesn't create duplicates"""
	var unit = {
		"flags": {
			"one_shot_fired": {
				"m1": ["one_shot_missile"]
			}
		}
	}
	var diffs = rules_engine.mark_one_shot_fired_diffs("unit_1", unit, "m1", "one_shot_missile")
	assert_eq(diffs.size(), 0, "Should not generate a diff for already-fired weapon")

# ==========================================
# filter_fired_one_shot_weapons() Tests
# ==========================================

func test_filter_fired_one_shot_removes_fired_weapons():
	"""Test that filter removes fired one-shot weapons from unit weapons dict"""
	var board = {
		"units": {
			"unit_1": {
				"flags": {
					"one_shot_fired": {
						"m1": ["one_shot_missile"]
					}
				},
				"models": [
					{"id": "m1", "alive": true},
					{"id": "m2", "alive": true}
				]
			}
		}
	}
	var unit_weapons = {
		"m1": ["bolt_rifle", "one_shot_missile"],
		"m2": ["bolt_rifle", "one_shot_missile"]
	}
	var filtered = rules_engine.filter_fired_one_shot_weapons("unit_1", unit_weapons, board)

	# m1 should NOT have one_shot_missile (already fired)
	assert_false("one_shot_missile" in filtered["m1"], "m1 should not have fired one_shot_missile")
	assert_true("bolt_rifle" in filtered["m1"], "m1 should still have bolt_rifle")

	# m2 should STILL have one_shot_missile (hasn't fired)
	assert_true("one_shot_missile" in filtered["m2"], "m2 should still have one_shot_missile")
	assert_true("bolt_rifle" in filtered["m2"], "m2 should still have bolt_rifle")

func test_filter_fired_one_shot_keeps_non_one_shot_weapons():
	"""Test that filter doesn't remove non-one-shot weapons"""
	var board = {
		"units": {
			"unit_1": {
				"flags": {},
				"models": [{"id": "m1", "alive": true}]
			}
		}
	}
	var unit_weapons = {
		"m1": ["bolt_rifle", "lascannon"]
	}
	var filtered = rules_engine.filter_fired_one_shot_weapons("unit_1", unit_weapons, board)
	assert_eq(filtered["m1"].size(), 2, "Should keep all non-one-shot weapons")

func test_filter_fired_one_shot_keeps_unfired_one_shot():
	"""Test that filter keeps unfired one-shot weapons"""
	var board = {
		"units": {
			"unit_1": {
				"flags": {},
				"models": [{"id": "m1", "alive": true}]
			}
		}
	}
	var unit_weapons = {
		"m1": ["bolt_rifle", "one_shot_missile"]
	}
	var filtered = rules_engine.filter_fired_one_shot_weapons("unit_1", unit_weapons, board)
	assert_true("one_shot_missile" in filtered["m1"], "Unfired one-shot should remain")

# ==========================================
# Helper: Build a board with attacker and target units
# ==========================================

func _make_shoot_board(attacker_weapons: Array, target_stats: Dictionary = {},
		attacker_flags: Dictionary = {}, attacker_model_count: int = 1,
		target_model_count: int = 5) -> Dictionary:
	"""Create a minimal board with an attacker unit and target unit for shooting"""
	var attacker_models = []
	for i in range(attacker_model_count):
		attacker_models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"current_wounds": 3,
			"wounds": 3,
			"position": {"x": 100 + i * 30, "y": 100},
			"weapons": attacker_weapons.duplicate()
		})

	var target_models = []
	var t_wounds = target_stats.get("wounds", 1)
	for i in range(target_model_count):
		target_models.append({
			"id": "t%d" % (i + 1),
			"alive": true,
			"current_wounds": t_wounds,
			"wounds": t_wounds,
			"position": {"x": 130 + i * 30, "y": 100}
		})

	return {
		"units": {
			"attacker_unit": {
				"id": "attacker_unit",
				"owner": 1,
				"status": 1,
				"flags": attacker_flags.duplicate(true),
				"meta": {
					"name": "Attacker Unit",
					"keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 3}
				},
				"models": attacker_models
			},
			"target_unit": {
				"id": "target_unit",
				"owner": 2,
				"status": 1,
				"flags": {},
				"meta": {
					"name": "Target Unit",
					"keywords": target_stats.get("keywords", ["INFANTRY"]),
					"stats": {
						"toughness": target_stats.get("toughness", 4),
						"save": target_stats.get("save", 4),
						"wounds": t_wounds
					}
				},
				"models": target_models
			}
		}
	}

func _make_shoot_action(weapon_id: String, model_ids: Array = ["m1"]) -> Dictionary:
	return {
		"type": "SHOOT",
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"weapon_id": weapon_id,
				"target_unit_id": "target_unit",
				"model_ids": model_ids
			}]
		}
	}

# ==========================================
# resolve_shoot() Integration Tests — One Shot marking
# ==========================================

func test_resolve_shoot_marks_one_shot_as_fired():
	"""Test that resolve_shoot generates diffs to mark one-shot weapon as fired"""
	var board = _make_shoot_board(["one_shot_test"])
	var action = _make_shoot_action("one_shot_test")

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot(action, board, rng)

	assert_true(result.success, "Shooting should succeed")

	# Check that one-shot diffs were generated
	var has_one_shot_diff = false
	for diff in result.diffs:
		if diff.get("path", "").contains("one_shot_fired"):
			has_one_shot_diff = true
			break
	assert_true(has_one_shot_diff, "Should generate one_shot_fired diff")

func test_resolve_shoot_marks_one_shot_per_model():
	"""Test that each model firing a one-shot weapon gets individually marked"""
	var board = _make_shoot_board(["one_shot_test"], {}, {}, 3)
	var action = _make_shoot_action("one_shot_test", ["m1", "m2", "m3"])

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot(action, board, rng)

	assert_true(result.success, "Shooting should succeed")

	# Check that diffs contain one_shot_fired
	var one_shot_diff = null
	for diff in result.diffs:
		if diff.get("path", "").contains("one_shot_fired"):
			one_shot_diff = diff
			break

	assert_not_null(one_shot_diff, "Should have one_shot_fired diff")

func test_resolve_shoot_non_one_shot_no_marking():
	"""Test that non-one-shot weapons don't generate one-shot diffs"""
	var board = _make_shoot_board(["bolt_rifle"])
	var action = _make_shoot_action("bolt_rifle")

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot(action, board, rng)

	# Check that NO one-shot diffs were generated
	var has_one_shot_diff = false
	for diff in result.diffs:
		if diff.get("path", "").contains("one_shot_fired"):
			has_one_shot_diff = true
			break
	assert_false(has_one_shot_diff, "Non-one-shot weapons should not generate one_shot_fired diffs")

# ==========================================
# resolve_shoot_until_wounds() Integration Tests — Interactive Path
# ==========================================

func test_resolve_shoot_until_wounds_includes_one_shot_diffs():
	"""Test that the interactive shooting path includes one_shot_diffs in result"""
	var board = _make_shoot_board(["one_shot_test"])
	var action = _make_shoot_action("one_shot_test")

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot_until_wounds(action, board, rng)

	assert_true(result.success, "Interactive shooting should succeed")

	# Check for one_shot_diffs key in result
	var one_shot_diffs = result.get("one_shot_diffs", [])
	assert_true(one_shot_diffs.size() > 0, "Should include one_shot_diffs in result")

func test_resolve_shoot_until_wounds_no_one_shot_diffs_for_normal_weapon():
	"""Test that non-one-shot weapons don't produce one_shot_diffs"""
	var board = _make_shoot_board(["bolt_rifle"])
	var action = _make_shoot_action("bolt_rifle")

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot_until_wounds(action, board, rng)

	var one_shot_diffs = result.get("one_shot_diffs", [])
	assert_eq(one_shot_diffs.size(), 0, "Non-one-shot weapons should not produce one_shot_diffs")

# ==========================================
# validate_shoot() Tests — One Shot Validation
# ==========================================

func test_validate_shoot_rejects_fired_one_shot():
	"""Test that validate_shoot rejects an already-fired one-shot weapon"""
	var board = _make_shoot_board(["one_shot_test"], {}, {
		"one_shot_fired": {
			"m1": ["one_shot_test"]
		}
	})
	var action = _make_shoot_action("one_shot_test")

	var validation = rules_engine.validate_shoot(action, board)
	assert_false(validation.valid, "Should reject fired one-shot weapon")
	assert_true(validation.errors.size() > 0, "Should have validation errors")

func test_validate_shoot_allows_unfired_one_shot():
	"""Test that validate_shoot allows a one-shot weapon that hasn't been fired"""
	var board = _make_shoot_board(["one_shot_test"])
	var action = _make_shoot_action("one_shot_test")

	var validation = rules_engine.validate_shoot(action, board)
	assert_true(validation.valid, "Should allow unfired one-shot weapon")

func test_validate_shoot_allows_normal_weapon():
	"""Test that validate_shoot allows normal weapons regardless"""
	var board = _make_shoot_board(["bolt_rifle"])
	var action = _make_shoot_action("bolt_rifle")

	var validation = rules_engine.validate_shoot(action, board)
	assert_true(validation.valid, "Should allow normal weapon")

# ==========================================
# State Persistence Tests — One Shot survives turns
# ==========================================

func test_one_shot_state_persists_after_marking():
	"""Test that one-shot fired state persists in board state after diffs applied"""
	var board = _make_shoot_board(["one_shot_test"])
	var action = _make_shoot_action("one_shot_test")

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot(action, board, rng)

	# The board should now have one_shot_fired state (diffs applied to board during resolve)
	var attacker = board.get("units", {}).get("attacker_unit", {})
	var fired = attacker.get("flags", {}).get("one_shot_fired", {})
	assert_true(fired.has("m1"), "Model m1 should be in one_shot_fired after resolve")
	assert_true("one_shot_test" in fired.get("m1", []), "one_shot_test should be marked as fired for m1")

func test_one_shot_cannot_fire_twice_in_auto_resolve():
	"""Test that a one-shot weapon cannot be fired again after being used"""
	var board = _make_shoot_board(["one_shot_test"])

	# First shot
	var action1 = _make_shoot_action("one_shot_test")
	var rng1 = RulesEngine.RNGService.new()
	rng1.seed_value = 42
	var result1 = rules_engine.resolve_shoot(action1, board, rng1)
	assert_true(result1.success, "First shot should succeed")

	# Verify the weapon is now marked as fired
	var attacker = board.get("units", {}).get("attacker_unit", {})
	var fired = attacker.get("flags", {}).get("one_shot_fired", {})
	assert_true("one_shot_test" in fired.get("m1", []), "Weapon should be marked as fired")

	# Attempt to validate a second shot — should fail
	var action2 = _make_shoot_action("one_shot_test")
	var validation = rules_engine.validate_shoot(action2, board)
	assert_false(validation.valid, "Second shot should be rejected by validation")

# ==========================================
# Multi-model One Shot Tests
# ==========================================

func test_multi_model_one_shot_marks_all_models():
	"""Test that all models firing the same one-shot weapon get marked"""
	var board = _make_shoot_board(["one_shot_test"], {}, {}, 2)
	var action = _make_shoot_action("one_shot_test", ["m1", "m2"])

	var rng = RulesEngine.RNGService.new()
	rng.seed_value = 42
	var result = rules_engine.resolve_shoot(action, board, rng)

	var attacker = board.get("units", {}).get("attacker_unit", {})
	var fired = attacker.get("flags", {}).get("one_shot_fired", {})
	assert_true(fired.has("m1"), "m1 should be in one_shot_fired")
	assert_true(fired.has("m2"), "m2 should be in one_shot_fired")

func test_one_shot_one_model_fired_other_still_can():
	"""Test that when one model fires one-shot, other models can still fire theirs"""
	var board = _make_shoot_board(["one_shot_test"], {}, {
		"one_shot_fired": {
			"m1": ["one_shot_test"]
		}
	}, 2)

	# Validate m2 can still fire (m1 already fired)
	var action = {
		"type": "SHOOT",
		"actor_unit_id": "attacker_unit",
		"payload": {
			"assignments": [{
				"weapon_id": "one_shot_test",
				"target_unit_id": "target_unit",
				"model_ids": ["m2"]
			}]
		}
	}
	var validation = rules_engine.validate_shoot(action, board)
	assert_true(validation.valid, "m2 should still be able to fire its one-shot weapon")

# ==========================================
# One Shot + Other Keywords Interaction Tests
# ==========================================

func test_one_shot_blast_retains_blast_keyword():
	"""Test that a weapon with both ONE SHOT and BLAST still works as BLAST"""
	var result = rules_engine.is_blast_weapon("one_shot_blast")
	assert_true(result, "one_shot_blast should also be a BLAST weapon")

	var one_shot = rules_engine.is_one_shot_weapon("one_shot_blast")
	assert_true(one_shot, "one_shot_blast should be a ONE SHOT weapon")
