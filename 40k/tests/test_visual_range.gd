extends SceneTree

# Visual test for range indicators in shooting phase

func _init():
	print("\n=== Testing Visual Range Indicators ===\n")
	
	# Test 1: RangeCircle instantiation
	var range_circle = load("res://scripts/RangeCircle.gd").new()
	range_circle.setup(500.0, "Test Weapon")
	if range_circle.radius != 500.0:
		print("FAIL: RangeCircle radius not set")
		quit(1)
	if range_circle.weapon_name != "Test Weapon":
		print("FAIL: RangeCircle weapon name not set")
		quit(1)
	print("✓ RangeCircle can be instantiated and configured")
	range_circle.queue_free()
	
	# Test 2: ShootingController exists and has proper structure
	var controller_script = load("res://scripts/ShootingController.gd")
	if not controller_script:
		print("FAIL: Cannot load ShootingController script")
		quit(1)
	print("✓ ShootingController script loads properly")
	
	# Test 3: Verify RangeCircle drawing capabilities
	var test_circle = load("res://scripts/RangeCircle.gd").new()
	if not test_circle.has_method("_draw"):
		print("FAIL: RangeCircle missing _draw method")
		quit(1)
	print("✓ RangeCircle has drawing capabilities")
	test_circle.queue_free()
	
	print("\n=== All Visual Range Tests Passed ===\n")
	quit(0)