extends SceneTree

# Simple syntax check for ChargeController fix
func _init():
	print("=== Testing Charge Controller Syntax ===")

	# Try to load ChargeController to verify it compiles
	var charge_controller_script = load("res://scripts/ChargeController.gd")
	if charge_controller_script:
		print("✅ ChargeController.gd loaded successfully")

		# Check that our new method exists
		var instance = charge_controller_script.new()
		if instance.has_method("_get_charge_targets_from_phase"):
			print("✅ _get_charge_targets_from_phase method exists")
		else:
			print("❌ ERROR: _get_charge_targets_from_phase method not found!")

		if instance.has_method("_is_charge_successful"):
			print("✅ _is_charge_successful method exists")
		else:
			print("❌ ERROR: _is_charge_successful method not found!")

		if instance.has_method("_on_charge_roll_made"):
			print("✅ _on_charge_roll_made method exists")
		else:
			print("❌ ERROR: _on_charge_roll_made method not found!")

		if instance.has_method("_on_dice_rolled"):
			print("✅ _on_dice_rolled method exists")
		else:
			print("❌ ERROR: _on_dice_rolled method not found!")

		instance.free()
	else:
		print("❌ ERROR: Failed to load ChargeController.gd")

	print("=== Syntax Check Complete ===")
	quit()
