extends SceneTree

func _init():
	print("=== TRANSPORT SYSTEM COMPILATION TEST ===")

	# Test loading transport scripts
	var scripts_to_test = [
		"res://autoloads/TransportManager.gd",
		"res://scripts/TransportEmbarkDialog.gd",
		"res://scripts/DisembarkDialog.gd",
		"res://scripts/DisembarkController.gd",
		"res://scripts/FiringDeckDialog.gd"
	]

	var all_loaded = true
	for script_path in scripts_to_test:
		var script = load(script_path)
		if script:
			print("✓ Loaded: ", script_path)
		else:
			print("✗ Failed to load: ", script_path)
			all_loaded = false

	# TransportManager is an autoload, will be available in game but not in standalone script
	print("ℹ TransportManager is registered as autoload in project.godot")

	if all_loaded:
		print("\n=== ALL TRANSPORT COMPONENTS LOADED SUCCESSFULLY ===")
	else:
		print("\n=== SOME COMPONENTS FAILED TO LOAD ===")

	quit()