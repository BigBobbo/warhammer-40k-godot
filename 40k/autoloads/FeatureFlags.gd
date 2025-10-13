extends Node

# Feature flags for development and testing
# Note: No class_name since this is an autoload singleton
# Set to false for production, true for development/testing
const MULTIPLAYER_ENABLED: bool = true  # Toggle for development

# Check if multiplayer is available
# Note: Godot's ENet multiplayer is available in all standard builds
static func is_multiplayer_available() -> bool:
	return MULTIPLAYER_ENABLED
