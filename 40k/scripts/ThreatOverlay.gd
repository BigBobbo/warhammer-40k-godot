extends Node2D
class_name ThreatOverlay

# ThreatOverlay — held-key (Tab) power-user mode showing enemy threat
# ranges (T10, doc §6).
#
# When active, for each unit owned by the OPPOSING player (relative to
# GameState.meta.active_player), draws:
#   - shooting range circle in MARGINAL_YELLOW at 15% alpha (uses the
#     unit's longest weapon range or a fallback of 24")
#   - charge threat ring (12") in INVALID_RED at 10% alpha
#
# Off by default. Public state for scenarios:
#   active : bool
#   rendered_rings : Array  — [{unit_id, kind: "shoot"|"charge",
#                              color_slot, radius_px}, ...]
#
# Self-installs under /root/Main/BoardRoot via Main._ready().

const SHOOTING_RANGE_FALLBACK_INCHES := 24.0
const CHARGE_RANGE_INCHES := 12.0


var active: bool = false
var rendered_rings: Array = []


func _ready() -> void:
	name = "ThreatOverlay"
	z_index = 4  # Below tokens, above terrain.


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if active:
		_build()
	else:
		_tear_down()


func _tear_down() -> void:
	rendered_rings = []
	for c in get_children():
		c.queue_free()


func _build() -> void:
	_tear_down()
	var gs = get_node_or_null("/root/GameState")
	var uic = get_node_or_null("/root/UIConstants")
	if gs == null or uic == null:
		return
	var active_player: int = int(gs.state.get("meta", {}).get("active_player", 1))
	var units: Dictionary = gs.state.get("units", {})
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	for uid in units:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var owner: int = int(u.get("owner", u.get("owner_player", 0)))
		if owner == active_player:
			continue
		var anchor: Vector2 = _first_model_position(u)
		if anchor == Vector2.INF:
			continue
		var shoot_range_inches: float = _longest_weapon_range(u)
		var shoot_px: float = shoot_range_inches * px_per_inch
		var charge_px: float = CHARGE_RANGE_INCHES * px_per_inch
		_spawn_ring(uid, "shoot", anchor, shoot_px,
			uic.MARGINAL_YELLOW, 0.15)
		rendered_rings.append({
			"unit_id": uid, "kind": "shoot",
			"color_slot": "MARGINAL_YELLOW",
			"radius_px": shoot_px,
		})
		_spawn_ring(uid, "charge", anchor, charge_px,
			uic.INVALID_RED, 0.10)
		rendered_rings.append({
			"unit_id": uid, "kind": "charge",
			"color_slot": "INVALID_RED",
			"radius_px": charge_px,
		})


func _spawn_ring(uid: String, kind: String, world_pos: Vector2,
		radius_px: float, color: Color, alpha: float) -> void:
	var ring := Polygon2D.new()
	ring.name = "Ring_%s_%s" % [uid, kind]
	ring.position = world_pos
	ring.polygon = _circle_points(radius_px, 48)
	var c := color
	c.a = alpha
	ring.color = c
	add_child(ring)


func _circle_points(radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(steps):
		var theta: float = float(i) / float(steps) * TAU
		out.append(Vector2(cos(theta), sin(theta)) * radius)
	return out


func _first_model_position(unit: Dictionary) -> Vector2:
	for m in unit.get("models", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var pos = m.get("position", null)
		if typeof(pos) == TYPE_VECTOR2:
			return pos
		if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
			return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF


func _longest_weapon_range(unit: Dictionary) -> float:
	var weapons = unit.get("meta", {}).get("weapons", [])
	if typeof(weapons) != TYPE_ARRAY or weapons.is_empty():
		return SHOOTING_RANGE_FALLBACK_INCHES
	var best: float = 0.0
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var rng_raw = w.get("range", 0)
		var rng: float = 0.0
		if typeof(rng_raw) == TYPE_INT or typeof(rng_raw) == TYPE_FLOAT:
			rng = float(rng_raw)
		elif typeof(rng_raw) == TYPE_STRING:
			var s := String(rng_raw).replace("\"", "").strip_edges()
			if s.is_valid_float():
				rng = float(s)
		best = max(best, rng)
	if best <= 0.0:
		return SHOOTING_RANGE_FALLBACK_INCHES
	return best
