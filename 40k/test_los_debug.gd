extends Node

# Test script to verify LoS debug visualization

func _ready() -> void:
	print("Testing LoS Debug Visualization...")
	
	# Wait for scene to load
	await get_tree().create_timer(1.0).timeout
	
	# Get the LoS debug visual node
	var los_debug = get_node_or_null("/root/Main/BoardRoot/LoSDebugVisual")
	if not los_debug:
		print("ERROR: LoSDebugVisual not found!")
		get_tree().quit()
		return
	
	print("SUCCESS: LoSDebugVisual found")
	
	# Enable debug mode
	los_debug.set_debug_enabled(true)
	print("Debug mode enabled")
	
	# Test a simple LoS check
	var from_pos = Vector2(400, 400)
	var to_pos = Vector2(800, 800)
	var board = {"terrain_features": []}
	
	print("Testing LoS from ", from_pos, " to ", to_pos)
	var result = los_debug.check_and_visualize_los(from_pos, to_pos, board)
	
	print("LoS check result:")
	print("  Has LoS: ", result.has_los)
	print("  Blocked by: ", result.blocked_by)
	print("  Provides cover: ", result.provides_cover)
	
	# Test with terrain
	if TerrainManager:
		TerrainManager.setup_terrain("Layout 2")
		board = GameState.create_snapshot()
		
		print("\nTesting with terrain...")
		result = los_debug.check_and_visualize_los(from_pos, to_pos, board)
		print("  Has LoS with terrain: ", result.has_los)
		print("  Blocked by: ", result.blocked_by)
		print("  Provides cover: ", result.provides_cover)
	
	print("\nLoS Debug Test Complete!")
	
	# Keep running for a moment to see visuals
	await get_tree().create_timer(3.0).timeout
	
	get_tree().quit()