extends Node2D
class_name PersistentEngagementOverlay

# PersistentEngagementOverlay — always-on engagement rings (T29, doc §5).
#
# For every unit currently engaged with an enemy (any model within the
# edition-aware engagement range of any enemy model, measured base-edge to
# base-edge like the phases do), spawn a persistent EngagementRangeVisual at
# one of its models' position. Refreshes whenever GameState changes, on a
# debounce.
#
# Child nodes are named `EngagementRing_<unit_id>` so scenarios can address
# them via NodePath.
#
# Self-installs under /root/Main/BoardRoot via Main._ready().

# ISS-002: engagement range comes from GameConstants.engagement_range_inches()
# (edition-dependent). Do not re-declare it as a local constant.


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
		# Detach before queue_free: a queued-free child keeps its name until
		# end of frame, so re-adding a ring with the same name in the same
		# frame would get auto-renamed (@Node2D@...) and scenarios could no
		# longer address it as EngagementRing_<unit_id>.
		remove_child(c)
		c.queue_free()
	var engaged_ids := _compute_engaged_unit_ids()
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	for uid in engaged_ids:
		var unit = gs.get_unit(uid)
		if typeof(unit) != TYPE_DICTIONARY or not unit.has("models"):
			continue
		var anchor_model := _first_anchor_model(unit)
		if anchor_model.is_empty():
			continue
		var anchor := _model_position(anchor_model)
		var ring = preload("res://scripts/EngagementRangeVisual.gd").new()
		ring.name = "EngagementRing_%s" % uid
		ring.is_persistent = true
		ring.position = anchor
		# ER is measured base-edge to base-edge, so the drawn ring spans the
		# anchor model's base plus the edition-aware engagement range.
		ring.setup_engagement_range(
			Measurement.base_radius_px(int(anchor_model.get("base_mm", 32)))
				+ Measurement.inches_to_px(GameConstants.engagement_range_inches()),
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
	var engaged: Dictionary = {}
	for i in range(owners.size()):
		for j in range(i + 1, owners.size()):
			for uid_a in by_owner[owners[i]]:
				for uid_b in by_owner[owners[j]]:
					if _units_within(units[uid_a], units[uid_b]):
						engaged[uid_a] = true
						engaged[uid_b] = true
	return engaged.keys()


## True if any alive model of unit_a is within engagement range of any alive
## model of unit_b, using the same shape-aware base-edge-to-base-edge
## measurement as the phases. (This previously compared centre-to-centre
## distance against the ER, which under-detected engagement by both models'
## base radii and disagreed with the rules checks.)
func _units_within(unit_a: Dictionary, unit_b: Dictionary) -> bool:
	var er_px := float(Measurement.inches_to_px(GameConstants.engagement_range_inches()))
	for ma in unit_a.get("models", []):
		var pa := _model_position(ma)
		if pa == Vector2.INF or not ma.get("alive", true):
			continue
		for mb in unit_b.get("models", []):
			var pb := _model_position(mb)
			if pb == Vector2.INF or not mb.get("alive", true):
				continue
			# Cheap centre-distance prefilter before the iterative shape solve.
			if pa.distance_to(pb) > er_px + _bound_radius_px(ma) + _bound_radius_px(mb):
				continue
			if Measurement.is_in_engagement_range_shape_aware(ma, mb):
				return true
	return false


## Upper bound of a model base's reach from its centre, in px (covers
## circular, rectangular and oval bases).
func _bound_radius_px(m: Dictionary) -> float:
	var base_mm := float(m.get("base_mm", 32))
	var dims: Dictionary = m.get("base_dimensions", {})
	var max_mm: float = max(base_mm, max(float(dims.get("length", 0.0)), float(dims.get("width", 0.0))))
	return Measurement.mm_to_px(max_mm) / 2.0


## First alive model with a valid position — the ring anchor.
func _first_anchor_model(unit: Dictionary) -> Dictionary:
	for m in unit.get("models", []):
		if _model_position(m) == Vector2.INF:
			continue
		if m.get("alive", true):
			return m
	return {}


func _model_position(m) -> Vector2:
	if typeof(m) != TYPE_DICTIONARY:
		return Vector2.INF
	var pos = m.get("position", null)
	if typeof(pos) == TYPE_VECTOR2:
		return pos
	if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
		return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF
