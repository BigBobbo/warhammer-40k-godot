extends SceneTree

func _init():
	print("Testing GameManager.gd syntax...")

	# Try to load GameManager
	var gm = load("res://autoloads/GameManager.gd")
	if gm:
		print("✓ GameManager.gd loaded successfully")
		print("✓ No syntax errors detected")
	else:
		print("✗ Failed to load GameManager.gd")
		push_error("Syntax error in GameManager.gd")

	quit()
