extends Node2D

# PersistentEngagementOverlay — always-on engagement rings (T29, doc §5).
#
# For every unit currently engaged with an enemy (any model within 1 inch
# of any enemy model), spawn a persistent EngagementRangeVisual at one of
# its models' position. Refreshes whenever GameState changes, on a debounce.
#
# Child nodes are named `EngagementRing_<unit_id>` so scenarios can address
# them via NodePath.
#
# Self-installs under /root/Main/BoardRoot via Main._ready().

const ENGAGEMENT_RANGE_INCHES := 1.0


var _refresh_pending: bool = false


func _ready() -> void:
	name = "PersistentEngagementOverlay"
	z_index = 5  # Below tokens, above terrain.
	# Best-effort: re-evaluate whenever the game state mutates.
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		for sig in ["state_changed", "unit_moved", "result_applied"]:
			if gs.has_signal(sig) and not gs.is_connected(sig, _request_refresh):
				gs.connect(sig, _request_refresh)
	refresh()


func _request_refresh(_a = null, _b = null) -> void:
	# Coalesce bursts via process_frame yield.
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_do_deferred_refresh")


func _do_deferred_refresh() -> void:
	_refresh_pending = false
	refresh()


func refresh() -> void:
	# Tear down + rebuild. Cheap because engagement count is small.
	for c in get_children():
		c.queue_free()
	var engaged_ids := _compute_engaged_unit_ids()
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	for uid in engaged_ids:
		var unit = gs.get_unit(uid)
		if typeof(unit) != TYPE_DICTIONARY or not unit.has("models"):
			continue
		var anchor := _first_model_position(unit)
		if anchor == Vector2.INF:
			continue
		var ring = preload("res://scripts/EngagementRangeVisual.gd").new()
		ring.name = "EngagementRing_%s" % uid
		ring.is_persistent = true
		ring.position = anchor
		ring.setup_engagement_range(
			Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES),
			Color(0.85, 0.6, 0.2, 1.0)  # subdued amber so it's not loud
		)
		ring.pulse_enabled = false  # ambient ring; pulsing reserved for active selection
		add_child(ring)


func _compute_engaged_unit_ids() -> Array:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var units: Dictionary = gs.state.get("units", {})
	var by_owner: Dictionary = {}
	for uid in units:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var owner = int(u.get("owner", u.get("owner_player", 0)))
		if not by_owner.has(owner):
			by_owner[owner] = []
		by_owner[owner].append(uid)

	var owners: Array = by_owner.keys()
	if owners.size() < 2:
		return []
	var threshold_px := float(Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES))
	var threshold_sq := threshold_px * threshold_px
	var engaged: Dictionary = {}
	for i in range(owners.size()):
		for j in range(i + 1, owners.size()):
			for uid_a in by_owner[owners[i]]:
				for uid_b in by_owner[owners[j]]:
					if _units_within(units[uid_a], units[uid_b], threshold_sq):
						engaged[uid_a] = true
						engaged[uid_b] = true
	return engaged.keys()


func _units_within(unit_a: Dictionary, unit_b: Dictionary, threshold_sq: float) -> bool:
	for ma in unit_a.get("models", []):
		var pa := _model_position(ma)
		if pa == Vector2.INF:
			continue
		for mb in unit_b.get("models", []):
			var pb := _model_position(mb)
			if pb == Vector2.INF:
				continue
			if pa.distance_squared_to(pb) <= threshold_sq:
				return true
	return false


func _first_model_position(unit: Dictionary) -> Vector2:
	for m in unit.get("models", []):
		var p := _model_position(m)
		if p != Vector2.INF:
			return p
	return Vector2.INF


func _model_position(m) -> Vector2:
	if typeof(m) != TYPE_DICTIONARY:
		return Vector2.INF
	var pos = m.get("position", null)
	if typeof(pos) == TYPE_VECTOR2:
		return pos
	if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
		return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF
