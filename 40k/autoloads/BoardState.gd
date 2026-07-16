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

# Returns the default model facing (in radians) so a model belonging to `player`
# faces the opponent's board edge. Tokens/sprites render "up" (toward -Y) at
# rotation 0, so a world-space facing direction d maps to rot = atan2(d.x, -d.y).
# The facing direction is the vector from the player's own deployment-zone
# centroid to the opponent's, which points across the board toward the enemy
# edge for every deployment type (including the diagonal Search-and-Destroy
# corners). Falls back to 0.0 (upward) when either zone is unavailable.
func get_default_facing_for_player(player: int) -> float:
	var own_zone: PackedVector2Array = get_deployment_zone_for_player(player)
	var enemy_zone: PackedVector2Array = get_deployment_zone_for_player(3 - player)
	if own_zone.is_empty() or enemy_zone.is_empty():
		return 0.0
	var own_center: Vector2 = _polygon_centroid(own_zone)
	var enemy_center: Vector2 = _polygon_centroid(enemy_zone)
	var dir: Vector2 = enemy_center - own_center
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	return atan2(dir.x, -dir.y)

func _polygon_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())
