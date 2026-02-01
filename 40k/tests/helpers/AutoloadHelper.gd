extends RefCounted
class_name AutoloadHelper

# Helper class to access autoload singletons in test environment
#
# IMPORTANT: Autoloads are registered in project.godot and should be automatically
# loaded by Godot when running tests. This helper provides convenient access and
# verification methods.
#
# NOTE: Uses Engine.get_main_loop() to access the SceneTree, which works even
# when the test instance hasn't fully entered the tree yet.
#
# DO NOT create new instances of autoloads - this creates duplicates that don't
# share state with the real singletons.

# Get the SceneTree via Engine.get_main_loop() - more reliable than get_tree()
static func _get_scene_tree() -> SceneTree:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop as SceneTree
	return null

# Verify that required autoloads are available
# Call this in before_each() to fail fast if autoloads aren't loaded
static func verify_autoloads_available() -> bool:
	var tree = _get_scene_tree()
	if tree == null or tree.root == null:
		push_error("[AutoloadHelper] SceneTree not available")
		return false

	var required = ["GameState", "RulesEngine", "Measurement", "PhaseManager"]
	var missing = []

	for autoload_name in required:
		if not tree.root.has_node(autoload_name):
			missing.append(autoload_name)

	if missing.size() > 0:
		push_error("[AutoloadHelper] Missing required autoloads: " + str(missing))
		push_error("[AutoloadHelper] Make sure tests are run with: godot --path 40k -s ...")
		return false

	return true

# Get an autoload by name, returns null if not found
static func get_autoload(autoload_name: String) -> Node:
	var tree = _get_scene_tree()
	if tree == null or tree.root == null:
		push_error("[AutoloadHelper] SceneTree not available")
		return null
	if tree.root.has_node(autoload_name):
		return tree.root.get_node(autoload_name)
	push_error("[AutoloadHelper] Autoload not found: " + autoload_name)
	return null

# Convenience getters for common autoloads
static func get_game_state() -> Node:
	return get_autoload("GameState")

static func get_rules_engine() -> Node:
	return get_autoload("RulesEngine")

static func get_measurement() -> Node:
	return get_autoload("Measurement")

static func get_phase_manager() -> Node:
	return get_autoload("PhaseManager")

static func get_terrain_manager() -> Node:
	return get_autoload("TerrainManager")

static func get_army_list_manager() -> Node:
	return get_autoload("ArmyListManager")

static func get_transport_manager() -> Node:
	return get_autoload("TransportManager")

static func get_line_of_sight_manager() -> Node:
	return get_autoload("LineOfSightManager")

# List all available autoloads (for debugging)
static func list_available_autoloads() -> Array:
	var tree = _get_scene_tree()
	if tree == null or tree.root == null:
		return []
	var autoloads = []
	for child in tree.root.get_children():
		# Autoloads are direct children of root with specific names
		if child.name in ["GameState", "RulesEngine", "Measurement", "PhaseManager",
						  "TerrainManager", "ArmyListManager", "TransportManager",
						  "LineOfSightManager", "MeasuringTapeManager", "DebugManager",
						  "DebugLogger", "ActionLogger", "NetworkManager", "TurnManager",
						  "SaveLoadManager", "ReplayManager", "StateSerializer",
						  "BoardState", "GameManager", "MissionManager", "FeatureFlags",
						  "SettingsService", "TestModeHandler", "EnhancedLineOfSight",
						  "TransportFactory"]:
			autoloads.append(child.name)
	return autoloads

# DEPRECATED: This method created duplicate instances and should not be used.
# Autoloads should be loaded by Godot from project.godot.
static func ensure_autoloads_loaded() -> void:
	push_warning("[AutoloadHelper] ensure_autoloads_loaded() is deprecated. " +
				 "Use verify_autoloads_available() instead. Autoloads should be " +
				 "loaded automatically by Godot from project.godot.")
	if not verify_autoloads_available():
		push_error("[AutoloadHelper] Required autoloads not available!")
