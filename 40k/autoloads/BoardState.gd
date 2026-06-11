extends Node

# BoardState — deployment-zone visual data facade (ISS-031).
#
# This autoload no longer stores ANY game state. GameState is the single
# source of truth for units/models; BoardState only converts deployment
# zone definitions into pixel-space polygons for visual components, plus
# one legacy property forward.
#
# History: this used to carry a hardcoded shadow `units` dictionary plus
# unit-status helpers that Main synced from GameState on load — write-only
# legacy state with zero readers, removed in ISS-031 (git history has it).

var deployment_zones: Array = []

# Legacy property that forwards to GameState for backwards compatibility
var active_player: int:
	get:
		return GameState.get_active_player()
	set(value):
		GameState.set_active_player(value)

func _ready() -> void:
	initialize_deployment_zones()

func initialize_deployment_zones(deployment_type: String = "hammer_anvil") -> void:
	deployment_zones = DeploymentZoneData.get_zones_px(deployment_type)
	print("[BoardState] Initialized deployment zones for: ", deployment_type)

func get_deployment_zone_for_player(player: int) -> PackedVector2Array:
	for zone in deployment_zones:
		if zone["player"] == player:
			return zone["poly"]
	return PackedVector2Array()
