extends SceneTree

# Test script for SecondaryMissionManager deck mechanics
# Run: godot --headless --script res://tests/test_secondary_missions.gd

const SecondaryMissionData = preload("res://scripts/data/SecondaryMissionData.gd")

var _pass_count = 0
var _fail_count = 0

func _init():
	print("=== Secondary Mission Tests ===\n")

	test_mission_data()
	test_deck_building()
	test_card_counts()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")
	quit()

func assert_eq(actual, expected, description: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s (expected %s, got %s)" % [description, str(expected), str(actual)])

func assert_true(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s" % description)

func test_mission_data():
	print("--- Mission Data Tests ---")

	var all = SecondaryMissionData.get_all_missions()
	assert_eq(all.size(), 19, "Total missions = 19")

	# Check card numbers
	for i in range(all.size()):
		assert_eq(all[i]["number"], i + 1, "Card %d has correct number" % (i + 1))

	# Check specific cards
	var bel = SecondaryMissionData.get_mission_by_id("behind_enemy_lines")
	assert_eq(bel["number"], 1, "Behind Enemy Lines is card 1")
	assert_eq(bel["category"], "positional", "Behind Enemy Lines is positional")
	assert_true(bel["can_be_fixed"], "Behind Enemy Lines can be fixed")

	var np = SecondaryMissionData.get_mission_by_id("no_prisoners")
	assert_true(np["can_be_fixed"], "No Prisoners can_be_fixed")
	assert_true(not np["tournament_legal_fixed"], "No Prisoners NOT tournament_legal_fixed")

	var dom = SecondaryMissionData.get_mission_by_id("display_of_might")
	assert_true(not dom["in_standard_deck"], "Display of Might NOT in standard deck")

	var ds = SecondaryMissionData.get_mission_by_id("defend_stronghold")
	assert_eq(ds["when_drawn"]["effect"], "mandatory_shuffle_back", "Defend Stronghold mandatory shuffle")
	assert_eq(ds["scoring"]["min_round"], 2, "Defend Stronghold round 2+")

	# Invalid ID
	var invalid = SecondaryMissionData.get_mission_by_id("nonexistent")
	assert_eq(invalid.size(), 0, "Invalid ID returns empty dict")

func test_deck_building():
	print("\n--- Deck Building Tests ---")

	var tactical = SecondaryMissionData.get_tactical_deck()
	assert_eq(tactical.size(), 18, "Tactical deck has 18 cards")

	# Ensure Display of Might not in tactical deck
	var has_dom = false
	for m in tactical:
		if m["id"] == "display_of_might":
			has_dom = true
	assert_true(not has_dom, "Tactical deck excludes Display of Might")

	# IDs
	var ids = SecondaryMissionData.get_mission_ids_for_deck(false)
	assert_eq(ids.size(), 18, "Standard deck IDs = 18")

	var ids_full = SecondaryMissionData.get_mission_ids_for_deck(true)
	assert_eq(ids_full.size(), 19, "Full deck IDs = 19")

func test_card_counts():
	print("\n--- Card Count Tests ---")

	var fixed = SecondaryMissionData.get_fixed_eligible_missions()
	assert_eq(fixed.size(), 9, "Fixed eligible = 9 (cards 1-9)")

	var tourn_fixed = SecondaryMissionData.get_tournament_fixed_missions()
	assert_eq(tourn_fixed.size(), 8, "Tournament fixed = 8 (No Prisoners excluded)")

	var action_missions = SecondaryMissionData.get_action_missions()
	assert_eq(action_missions.size(), 4, "Action missions = 4")

	var positional = SecondaryMissionData.get_missions_by_category("positional")
	assert_eq(positional.size(), 4, "Positional missions = 4")

	var kill = SecondaryMissionData.get_missions_by_category("kill")
	assert_eq(kill.size(), 6, "Kill missions = 6")

	var obj_ctrl = SecondaryMissionData.get_missions_by_category("objective_control")
	assert_eq(obj_ctrl.size(), 5, "Objective control missions = 5")
