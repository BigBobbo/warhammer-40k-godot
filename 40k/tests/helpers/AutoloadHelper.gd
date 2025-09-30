extends RefCounted
class_name AutoloadHelper

# Helper class to ensure autoloads are available in headless test environment
# Use this when tests need access to autoload singletons but don't load Main scene

static func ensure_autoloads_loaded(tree: SceneTree) -> void:
	# Check and load GameState if not present
	if not tree.root.has_node("GameState"):
		var game_state_script = load("res://autoloads/GameState.gd")
		if game_state_script:
			var game_state = game_state_script.new()
			tree.root.add_child(game_state)
			game_state.name = "GameState"
			print("[AutoloadHelper] Loaded GameState autoload for testing")

	# Check and load PhaseManager if not present
	if not tree.root.has_node("PhaseManager"):
		var phase_manager_script = load("res://autoloads/PhaseManager.gd")
		if phase_manager_script:
			var phase_manager = phase_manager_script.new()
			tree.root.add_child(phase_manager)
			phase_manager.name = "PhaseManager"
			print("[AutoloadHelper] Loaded PhaseManager autoload for testing")

	# Check and load ArmyListManager if not present
	if not tree.root.has_node("ArmyListManager"):
		var army_manager_script = load("res://autoloads/ArmyListManager.gd")
		if army_manager_script:
			var army_manager = army_manager_script.new()
			tree.root.add_child(army_manager)
			army_manager.name = "ArmyListManager"
			print("[AutoloadHelper] Loaded ArmyListManager autoload for testing")

	# Check and load TerrainManager if not present
	if not tree.root.has_node("TerrainManager"):
		var terrain_script = load("res://autoloads/TerrainManager.gd")
		if terrain_script:
			var terrain_manager = terrain_script.new()
			tree.root.add_child(terrain_manager)
			terrain_manager.name = "TerrainManager"
			print("[AutoloadHelper] Loaded TerrainManager autoload for testing")

	# Check and load LineOfSightManager if not present
	if not tree.root.has_node("LineOfSightManager"):
		var los_script = load("res://autoloads/LineOfSightManager.gd")
		if los_script:
			var los_manager = los_script.new()
			tree.root.add_child(los_manager)
			los_manager.name = "LineOfSightManager"
			print("[AutoloadHelper] Loaded LineOfSightManager autoload for testing")

	# Check and load TransportManager if not present
	if not tree.root.has_node("TransportManager"):
		var transport_script = load("res://autoloads/TransportManager.gd")
		if transport_script:
			var transport_manager = transport_script.new()
			tree.root.add_child(transport_manager)
			transport_manager.name = "TransportManager"
			print("[AutoloadHelper] Loaded TransportManager autoload for testing")

	# Check and load MeasuringTapeManager if not present
	if not tree.root.has_node("MeasuringTapeManager"):
		var tape_script = load("res://autoloads/MeasuringTapeManager.gd")
		if tape_script:
			var tape_manager = tape_script.new()
			tree.root.add_child(tape_manager)
			tape_manager.name = "MeasuringTapeManager"
			print("[AutoloadHelper] Loaded MeasuringTapeManager autoload for testing")

static func cleanup_test_autoloads(tree: SceneTree) -> void:
	# Remove test-loaded autoloads to prevent conflicts
	# Only remove if they were added by tests (check for a marker?)
	# For now, we'll leave them as they should be cleaned up between test runs
	pass