extends SceneTree

# Test script to verify fight action registration in GameManager
# This script tests that all modern fight actions are properly registered

func _init():
	var sep = "================================================================================"
	print(sep)
	print("Testing Fight Action Registration in GameManager")
	print(sep)

	# Test action types that should be registered
	var test_actions = [
		"SELECT_FIGHTER",
		"SELECT_MELEE_WEAPON",
		"PILE_IN",
		"ASSIGN_ATTACKS",
		"CONFIRM_AND_RESOLVE_ATTACKS",
		"ROLL_DICE",
		"CONSOLIDATE",
		"SKIP_UNIT",
		"HEROIC_INTERVENTION",
		"END_FIGHT"
	]

	print("\nExpected Fight Actions (from FightPhase.gd):")
	for action_type in test_actions:
		print("  - " + action_type)

	print("\n" + sep)
	print("Checking GameManager.gd source code for action registration...")
	print(sep)

	# Load and check GameManager source
	var file = FileAccess.open("res://autoloads/GameManager.gd", FileAccess.READ)
	if not file:
		push_error("Failed to open GameManager.gd")
		quit(1)
		return

	var content = file.get_as_text()
	file.close()

	var found_actions = {}
	var missing_actions = []
	var legacy_actions_found = []

	# Check for each expected action
	for action_type in test_actions:
		if content.find('"' + action_type + '":') != -1:
			found_actions[action_type] = true
			print("✓ Found: " + action_type)
		else:
			missing_actions.append(action_type)
			print("✗ Missing: " + action_type)

	# Check for legacy actions that should be removed/commented
	var legacy_actions = ["SELECT_FIGHT_TARGET", "RESOLVE_FIGHT"]
	print("\n" + sep)
	print("Checking for legacy actions (should be commented out)...")
	print(sep)

	for legacy_action in legacy_actions:
		# Check if it appears uncommented in the match statement
		if content.find('"' + legacy_action + '":') != -1:
			var lines = content.split("\n")
			for i in range(lines.size()):
				var line = lines[i]
				if legacy_action in line and not line.strip_edges().begins_with("#"):
					legacy_actions_found.append(legacy_action)
					print("⚠ Warning: Legacy action still active: " + legacy_action)
					break
		else:
			print("✓ Legacy action removed/commented: " + legacy_action)

	# Check for delegation pattern
	print("\n" + sep)
	print("Checking delegation pattern...")
	print(sep)

	var uses_delegation = content.find("_delegate_to_current_phase(action)") != -1
	if uses_delegation:
		print("✓ Uses _delegate_to_current_phase() for action delegation")
	else:
		print("✗ Missing delegation pattern")

	# Print summary
	print("\n" + sep)
	print("SUMMARY")
	print(sep)
	print("Total expected actions: " + str(test_actions.size()))
	print("Found actions: " + str(found_actions.size()))
	print("Missing actions: " + str(missing_actions.size()))
	print("Legacy actions still active: " + str(legacy_actions_found.size()))

	if missing_actions.size() > 0:
		print("\n⚠ MISSING ACTIONS:")
		for action in missing_actions:
			print("  - " + action)

	if legacy_actions_found.size() > 0:
		print("\n⚠ LEGACY ACTIONS STILL ACTIVE:")
		for action in legacy_actions_found:
			print("  - " + action)

	# Final result
	print("\n" + sep)
	if missing_actions.size() == 0 and legacy_actions_found.size() == 0:
		print("✓ ALL TESTS PASSED - Fight actions properly registered!")
		quit(0)
	else:
		print("✗ TESTS FAILED - See issues above")
		quit(1)
