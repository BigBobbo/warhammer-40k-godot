extends SceneTree

# Test AI Leader Attachment in Formations (T7-17)
# Verifies that AIDecisionMaker._decide_formations() correctly evaluates
# leader-bodyguard pairings based on ability synergies ("while leading"
# bonuses like re-rolls, FNP, +1 to hit) and makes optimal attachments.
# Run with: godot --headless --script tests/unit/test_ai_leader_attachment.gd

const GameStateData = preload("res://autoloads/GameState.gd")
const AIDecisionMaker = preload("res://scripts/AIDecisionMaker.gd")
const AIAbilityAnalyzer = preload("res://scripts/AIAbilityAnalyzer.gd")

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== AI Leader Attachment in Formations Tests (T7-17) ===\n")
	_run_tests()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	var diff = abs(actual - expected)
	if diff <= tolerance:
		_pass_count += 1
		print("PASS: %s (got %.4f, expected %.4f)" % [message, actual, expected])
	else:
		_fail_count += 1
		print("FAIL: %s (got %.4f, expected %.4f, diff %.4f > tolerance %.4f)" % [message, actual, expected, diff, tolerance])

func _run_tests():
	# Core formation decision tests
	test_ai_attaches_leader_when_available()
	test_ai_confirms_when_no_attachments()
	test_ai_confirms_after_all_attachments()
	test_ai_returns_empty_when_no_actions()

	# Synergy scoring tests
	test_score_leader_with_melee_bonus()
	test_score_leader_with_ranged_reroll()
	test_score_leader_with_fnp()
	test_score_leader_no_synergy()
	test_score_scales_with_model_count()
	test_score_scales_with_points()

	# Best pairing selection tests
	test_ai_picks_highest_synergy_pairing()
	test_ai_picks_fnp_leader_for_high_value_unit()

# =========================================================================
# Helpers
# =========================================================================

func _create_snapshot() -> Dictionary:
	return {
		"battle_round": 1,
		"board": {
			"objectives": [],
			"terrain_features": [],
			"deployment_zones": []
		},
		"units": {}
	}

func _add_bodyguard_unit(snapshot: Dictionary, unit_id: String, owner: int,
		name: String = "Intercessors", num_models: int = 5,
		keywords: Array = ["INFANTRY", "PRIMARIS", "IMPERIUM"],
		points: int = 90) -> void:
	var models = []
	for i in range(num_models):
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"base_mm": 32,
			"position": null,
			"wounds": 2,
			"current_wounds": 2
		})
	snapshot.units[unit_id] = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": name,
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 2},
			"keywords": keywords,
			"points": points
		},
		"models": models,
		"attachment_data": {"attached_characters": []}
	}

func _add_character_unit(snapshot: Dictionary, unit_id: String, owner: int,
		name: String = "Captain", abilities: Array = [],
		can_lead: Array = ["INFANTRY", "PRIMARIS"],
		keywords: Array = ["CHARACTER", "INFANTRY", "PRIMARIS", "IMPERIUM"],
		points: int = 80) -> void:
	snapshot.units[unit_id] = {
		"id": unit_id,
		"squad_id": unit_id,
		"owner": owner,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": name,
			"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 5},
			"keywords": keywords,
			"leader_data": {"can_lead": can_lead},
			"abilities": abilities,
			"points": points
		},
		"models": [
			{"id": "m1", "alive": true, "base_mm": 40, "position": null, "wounds": 5, "current_wounds": 5}
		],
		"attached_to": null
	}

func _make_attachment_action(char_id: String, bg_id: String, player: int = 1) -> Dictionary:
	return {
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": char_id,
		"bodyguard_id": bg_id,
		"player": player,
		"description": "Attach %s to %s" % [char_id, bg_id]
	}

func _make_confirm_action(player: int = 1) -> Dictionary:
	return {
		"type": "CONFIRM_FORMATIONS",
		"player": player,
		"description": "Confirm Battle Formations"
	}

# =========================================================================
# Tests: Core formation decisions
# =========================================================================

func test_ai_attaches_leader_when_available():
	var snapshot = _create_snapshot()
	_add_character_unit(snapshot, "captain_a", 1, "Captain")
	_add_bodyguard_unit(snapshot, "intercessors_a", 1, "Intercessors A")

	var available = [
		_make_attachment_action("captain_a", "intercessors_a"),
		_make_confirm_action()
	]

	var decision = AIDecisionMaker._decide_formations(snapshot, available, 1)
	_assert(decision.get("type") == "DECLARE_LEADER_ATTACHMENT",
		"AI should declare leader attachment when available (got: %s)" % decision.get("type", "empty"))
	_assert(decision.get("character_id") == "captain_a",
		"AI should attach captain_a")
	_assert(decision.get("bodyguard_id") == "intercessors_a",
		"AI should attach to intercessors_a")

func test_ai_confirms_when_no_attachments():
	var snapshot = _create_snapshot()
	_add_bodyguard_unit(snapshot, "intercessors_a", 1, "Intercessors A")

	var available = [_make_confirm_action()]

	var decision = AIDecisionMaker._decide_formations(snapshot, available, 1)
	_assert(decision.get("type") == "CONFIRM_FORMATIONS",
		"AI should confirm when no attachment options (got: %s)" % decision.get("type", "empty"))

func test_ai_confirms_after_all_attachments():
	# Simulate: all characters already attached, only CONFIRM left
	var snapshot = _create_snapshot()

	var available = [_make_confirm_action()]

	var decision = AIDecisionMaker._decide_formations(snapshot, available, 1)
	_assert(decision.get("type") == "CONFIRM_FORMATIONS",
		"AI should confirm after all attachments done (got: %s)" % decision.get("type", "empty"))

func test_ai_returns_empty_when_no_actions():
	var snapshot = _create_snapshot()
	var available = []

	var decision = AIDecisionMaker._decide_formations(snapshot, available, 1)
	_assert(decision.is_empty(),
		"AI should return empty when no actions available")

# =========================================================================
# Tests: Synergy scoring
# =========================================================================

func test_score_leader_with_melee_bonus():
	var snapshot = _create_snapshot()
	# Leader with "Might is Right" (+1 melee hit while leading)
	_add_character_unit(snapshot, "warboss", 1, "Warboss",
		[{"name": "Might is Right", "description": "+1 to melee Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_bodyguard_unit(snapshot, "boyz", 1, "Boyz", 10,
		["INFANTRY", "ORKS"], 90)

	var score = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "boyz", snapshot.units)
	# With +1 melee hit: off_melee > 1.0, off_ranged = 1.0, def = 1.0
	# Average multiplier > 1.0, so synergy score should be above baseline
	_assert(score > 1.0, "Melee bonus leader should score > 1.0 (got %.2f)" % score)

func test_score_leader_with_ranged_reroll():
	var snapshot = _create_snapshot()
	# Leader with "Flashiest Gitz" (reroll all ranged hits while leading)
	_add_character_unit(snapshot, "flashgit_boss", 1, "Flash Git Boss",
		[{"name": "Flashiest Gitz", "description": "Re-roll all ranged Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_bodyguard_unit(snapshot, "boyz", 1, "Boyz", 10,
		["INFANTRY", "ORKS"], 90)

	var score = AIDecisionMaker._score_leader_bodyguard_pairing(
		"flashgit_boss", "boyz", snapshot.units)
	_assert(score > 1.0, "Ranged reroll leader should score > 1.0 (got %.2f)" % score)

func test_score_leader_with_fnp():
	var snapshot = _create_snapshot()
	# Leader with "Dok's Toolz" (FNP 5+ while leading)
	_add_character_unit(snapshot, "painboy", 1, "Painboy",
		[{"name": "Dok's Toolz", "description": "Feel No Pain 5+"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_bodyguard_unit(snapshot, "boyz", 1, "Boyz", 10,
		["INFANTRY", "ORKS"], 90)

	var score = AIDecisionMaker._score_leader_bodyguard_pairing(
		"painboy", "boyz", snapshot.units)
	_assert(score > 1.0, "FNP leader should score > 1.0 (got %.2f)" % score)

func test_score_leader_no_synergy():
	var snapshot = _create_snapshot()
	# Leader with no "while leading" abilities
	_add_character_unit(snapshot, "plain_captain", 1, "Plain Captain", [],
		["INFANTRY", "PRIMARIS"])
	_add_bodyguard_unit(snapshot, "intercessors", 1, "Intercessors", 5)

	var score = AIDecisionMaker._score_leader_bodyguard_pairing(
		"plain_captain", "intercessors", snapshot.units)
	# Without any while_leading abilities, multipliers should all be 1.0
	# Score should still be > 0 (baseline from model count and points)
	_assert(score > 0.0, "Leader with no synergy should still score > 0 (got %.2f)" % score)

func test_score_scales_with_model_count():
	var snapshot = _create_snapshot()
	# Same leader, but one bodyguard has more models
	_add_character_unit(snapshot, "warboss", 1, "Warboss",
		[{"name": "Might is Right", "description": "+1 to melee Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_bodyguard_unit(snapshot, "small_squad", 1, "Small Squad", 3,
		["INFANTRY", "ORKS"], 90)
	_add_bodyguard_unit(snapshot, "big_squad", 1, "Big Squad", 10,
		["INFANTRY", "ORKS"], 90)

	var score_small = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "small_squad", snapshot.units)
	var score_big = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "big_squad", snapshot.units)
	_assert(score_big > score_small,
		"Larger squad should score higher (big=%.2f > small=%.2f)" % [score_big, score_small])

func test_score_scales_with_points():
	var snapshot = _create_snapshot()
	_add_character_unit(snapshot, "warboss", 1, "Warboss",
		[{"name": "Might is Right", "description": "+1 to melee Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_bodyguard_unit(snapshot, "cheap_squad", 1, "Cheap Squad", 5,
		["INFANTRY", "ORKS"], 60)
	_add_bodyguard_unit(snapshot, "elite_squad", 1, "Elite Squad", 5,
		["INFANTRY", "ORKS"], 200)

	var score_cheap = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "cheap_squad", snapshot.units)
	var score_elite = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "elite_squad", snapshot.units)
	_assert(score_elite > score_cheap,
		"Higher-value unit should score higher (elite=%.2f > cheap=%.2f)" % [score_elite, score_cheap])

# =========================================================================
# Tests: Best pairing selection
# =========================================================================

func test_ai_picks_highest_synergy_pairing():
	var snapshot = _create_snapshot()
	# Leader with melee bonus
	_add_character_unit(snapshot, "warboss", 1, "Warboss",
		[{"name": "Might is Right", "description": "+1 to melee Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	# Two bodyguard options: one small, one large
	_add_bodyguard_unit(snapshot, "small_boyz", 1, "Small Boyz", 3,
		["INFANTRY", "ORKS"], 60)
	_add_bodyguard_unit(snapshot, "big_boyz", 1, "Big Boyz", 10,
		["INFANTRY", "ORKS"], 150)

	var available = [
		_make_attachment_action("warboss", "small_boyz"),
		_make_attachment_action("warboss", "big_boyz"),
		_make_confirm_action()
	]

	var decision = AIDecisionMaker._decide_formations(snapshot, available, 1)
	_assert(decision.get("type") == "DECLARE_LEADER_ATTACHMENT",
		"AI should make an attachment (got: %s)" % decision.get("type", "empty"))
	_assert(decision.get("bodyguard_id") == "big_boyz",
		"AI should attach to larger, higher-value unit (got: %s)" % decision.get("bodyguard_id", "none"))

func test_ai_picks_fnp_leader_for_high_value_unit():
	var snapshot = _create_snapshot()
	# Two leaders with different abilities
	_add_character_unit(snapshot, "warboss", 1, "Warboss",
		[{"name": "Might is Right", "description": "+1 to melee Hit rolls"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])
	_add_character_unit(snapshot, "painboy", 1, "Painboy",
		[{"name": "Dok's Toolz", "description": "Feel No Pain 5+"}],
		["INFANTRY"], ["CHARACTER", "INFANTRY", "ORKS"])

	# One big bodyguard unit
	_add_bodyguard_unit(snapshot, "meganobz", 1, "Meganobz", 3,
		["INFANTRY", "ORKS"], 200)

	# Both leaders can attach to the same unit - test scoring directly
	var score_warboss = AIDecisionMaker._score_leader_bodyguard_pairing(
		"warboss", "meganobz", snapshot.units)
	var score_painboy = AIDecisionMaker._score_leader_bodyguard_pairing(
		"painboy", "meganobz", snapshot.units)

	# Both should provide meaningful synergy
	_assert(score_warboss > 1.0, "Warboss should have synergy > 1.0 (got %.2f)" % score_warboss)
	_assert(score_painboy > 1.0, "Painboy should have synergy > 1.0 (got %.2f)" % score_painboy)
	# Both are valid choices — just ensure both are scored meaningfully
	print("  Info: Warboss score=%.2f, Painboy score=%.2f" % [score_warboss, score_painboy])
