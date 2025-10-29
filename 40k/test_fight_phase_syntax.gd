extends SceneTree

func _init():
	print("=== Testing FightPhase Syntax ===")

	# Try to load and instantiate FightPhase
	var FightPhaseClass = load("res://40k/phases/FightPhase.gd")
	if FightPhaseClass == null:
		print("ERROR: Could not load FightPhase.gd")
		quit(1)
		return

	print("✓ FightPhase.gd loaded successfully")

	var fight_phase = FightPhaseClass.new()
	if fight_phase == null:
		print("ERROR: Could not instantiate FightPhase")
		quit(1)
		return

	print("✓ FightPhase instantiated successfully")

	# Test that _all_eligible_units_have_fought exists
	if not fight_phase.has_method("_all_eligible_units_have_fought"):
		print("ERROR: _all_eligible_units_have_fought method not found")
		quit(1)
		return

	print("✓ _all_eligible_units_have_fought method exists")

	# Test the method with empty sequences
	fight_phase.fights_first_sequence = {"1": [], "2": []}
	fight_phase.normal_sequence = {"1": [], "2": []}
	fight_phase.fights_last_sequence = {"1": [], "2": []}
	fight_phase.units_that_fought = []

	var result = fight_phase._all_eligible_units_have_fought()
	if result != true:
		print("ERROR: Expected true for empty sequences, got: ", result)
		quit(1)
		return

	print("✓ _all_eligible_units_have_fought returns true for empty sequences")

	# Test with some units
	fight_phase.fights_first_sequence = {"1": ["unit1"], "2": []}
	fight_phase.units_that_fought = []

	result = fight_phase._all_eligible_units_have_fought()
	if result != false:
		print("ERROR: Expected false when unit1 hasn't fought, got: ", result)
		quit(1)
		return

	print("✓ _all_eligible_units_have_fought returns false when units haven't fought")

	# Test with all units fought
	fight_phase.units_that_fought = ["unit1"]
	result = fight_phase._all_eligible_units_have_fought()
	if result != true:
		print("ERROR: Expected true when all units fought, got: ", result)
		quit(1)
		return

	print("✓ _all_eligible_units_have_fought returns true when all units fought")

	print("=== All FightPhase Syntax Tests PASSED ===")
	quit(0)
