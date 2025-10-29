extends SceneTree

# Runner script for TestSaveGenerator
# Usage: godot --path . -s tests/run_save_generator.gd

func _init():
	print("=== Starting TestSaveGenerator ===")

	# Load the generator script and instantiate it
	var generator_script = load("res://tests/helpers/TestSaveGenerator.gd")
	var generator = generator_script.new()

	# Generate all test saves
	generator.generate_all_test_saves()

	print("=== TestSaveGenerator Complete ===")

	# Exit
	quit()
