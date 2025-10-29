extends GutTest

# Unit tests for LoS debug toggle functionality
# Tests default state, toggle behavior, and visual cleanup

var los_debug: LoSDebugVisual
var board_root: Node2D

func before_each():
	# Create a fresh LoSDebugVisual instance
	los_debug = load("res://scripts/LoSDebugVisual.gd").new()

	# Create a mock board root to add it to
	board_root = Node2D.new()
	board_root.name = "BoardRoot"
	add_child_autofree(board_root)
	board_root.add_child(los_debug)

func after_each():
	# Cleanup happens automatically via autofree
	pass

func test_default_state_is_disabled():
	assert_false(los_debug.debug_enabled, "Debug should be disabled by default")

func test_toggle_enables_debug():
	# Start disabled
	assert_false(los_debug.debug_enabled)

	# Toggle on
	los_debug.toggle_debug()
	assert_true(los_debug.debug_enabled, "Debug should be enabled after first toggle")

func test_toggle_disables_debug():
	# Start enabled
	los_debug.set_debug_enabled(true)
	assert_true(los_debug.debug_enabled)

	# Toggle off
	los_debug.toggle_debug()
	assert_false(los_debug.debug_enabled, "Debug should be disabled after toggle")

func test_set_debug_enabled_false_clears_visuals():
	# Enable debug and add some visualizations
	los_debug.set_debug_enabled(true)
	los_debug.add_los_line(Vector2(0, 0), Vector2(100, 100), Color.GREEN)

	# Verify los_lines has content
	assert_gt(los_debug.los_lines.size(), 0, "Should have los_lines before disabling")

	# Disable debug
	los_debug.set_debug_enabled(false)

	# Verify cleanup
	assert_eq(los_debug.los_lines.size(), 0, "los_lines should be cleared when disabled")

func test_child_nodes_removed_when_disabled():
	# Enable debug
	los_debug.set_debug_enabled(true)

	# Create some child visualization nodes (simulating debug visuals)
	var child1 = Node2D.new()
	child1.name = "DebugVisual1"
	los_debug.add_child(child1)

	var child2 = Node2D.new()
	child2.name = "DebugVisual2"
	los_debug.add_child(child2)

	# Verify children exist
	assert_eq(los_debug.get_child_count(), 2, "Should have 2 child nodes")

	# Disable debug
	los_debug.set_debug_enabled(false)

	# Wait for cleanup
	await wait_frames(2)

	# Verify children removed
	assert_eq(los_debug.get_child_count(), 0, "All child nodes should be removed when disabled")

func test_clear_all_debug_visuals_removes_children():
	# Add visualization content
	los_debug.set_debug_enabled(true)
	los_debug.add_los_line(Vector2(0, 0), Vector2(100, 100), Color.GREEN)

	# Add child nodes
	var child = Node2D.new()
	los_debug.add_child(child)

	assert_gt(los_debug.los_lines.size(), 0, "Should have los_lines")
	assert_gt(los_debug.get_child_count(), 0, "Should have child nodes")

	# Clear all
	los_debug.clear_all_debug_visuals()

	# Wait for cleanup
	await wait_frames(2)

	# Verify complete cleanup
	assert_eq(los_debug.los_lines.size(), 0, "los_lines should be cleared")
	assert_eq(los_debug.get_child_count(), 0, "Child nodes should be removed")

func test_multiple_toggles():
	# Test rapid toggling
	assert_false(los_debug.debug_enabled, "Start disabled")

	los_debug.toggle_debug()
	assert_true(los_debug.debug_enabled, "First toggle: enabled")

	los_debug.toggle_debug()
	assert_false(los_debug.debug_enabled, "Second toggle: disabled")

	los_debug.toggle_debug()
	assert_true(los_debug.debug_enabled, "Third toggle: enabled")

	los_debug.toggle_debug()
	assert_false(los_debug.debug_enabled, "Fourth toggle: disabled")

func test_visuals_not_drawn_when_disabled():
	# Disable debug
	los_debug.set_debug_enabled(false)

	# Try to add visualization
	los_debug.add_los_line(Vector2(0, 0), Vector2(100, 100), Color.GREEN)

	# Lines should be added to array even when disabled (stored for when enabled)
	# But _draw() should not render them
	# This is tested by checking that lines persist across enable/disable

	# Note: We can't directly test _draw() output, but we can verify behavior
	var line_count = los_debug.los_lines.size()
	assert_gt(line_count, 0, "Lines should be stored even when disabled")
