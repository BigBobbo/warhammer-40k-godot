extends Node2D
class_name MovementRangeVisual

# MovementRangeVisual — two-layer range shading for a selected unit (T28,
# doc §5).
#
# Inner layer: filled disc at the unit's M radius, 12% alpha, drawn in
#   UIConstants.CONFIRMED_GREEN.
# Outer layer: thin outline ring at (M + selected_weapon_range_inches),
#   drawn in UIConstants.MARGINAL_YELLOW.
#
# Public state for scenarios:
#   inner_fill_radius_px : float
#   outer_outline_radius_px : float
#   set_from(unit_id, weapon_range_inches)
#
# Self-installs under /root/Main/BoardRoot via Main._ready().
#
# T12: every colour here is a UIConstants slot (or its neutral chrome),
# referenced through the preloaded script so it also resolves with no autoload
# in the tree; alphas are named constants applied at draw time.

const UIC := preload("res://autoloads/UIConstants.gd")
const INNER_FILL_ALPHA := 0.12

var inner_fill_radius_px: float = 0.0
var outer_outline_radius_px: float = 0.0
var _unit_id: String = ""


func _ready() -> void:
	name = "MovementRangeVisual"
	z_index = 3


func set_from(unit_id: String, weapon_range_inches: float = 0.0) -> bool:
	_unit_id = unit_id
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var unit = gs.get_unit(unit_id)
	if typeof(unit) != TYPE_DICTIONARY or unit.is_empty():
		return false
	var move_inches: float = float(unit.get("meta", {}).get("stats", {}).get("move", 6.0))
	var px_per_inch: float = float(Measurement.PX_PER_INCH)
	inner_fill_radius_px = move_inches * px_per_inch
	outer_outline_radius_px = (move_inches + weapon_range_inches) * px_per_inch
	# Anchor on the unit's first model position.
	for m in unit.get("models", []):
		var pos = m.get("position", null)
		if typeof(pos) == TYPE_VECTOR2:
			position = pos
			break
		if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
			position = Vector2(float(pos.x), float(pos.y))
			break
	queue_redraw()
	return true


func clear() -> void:
	_unit_id = ""
	inner_fill_radius_px = 0.0
	outer_outline_radius_px = 0.0
	queue_redraw()


func _draw() -> void:
	if inner_fill_radius_px <= 0.0:
		return
	draw_circle(Vector2.ZERO, inner_fill_radius_px, UIC.with_alpha(UIC.CONFIRMED_GREEN, INNER_FILL_ALPHA))
	if outer_outline_radius_px > inner_fill_radius_px:
		draw_arc(Vector2.ZERO, outer_outline_radius_px, 0.0, TAU, 64, UIC.MARGINAL_YELLOW, 2.0, true)


# ---------------------------------------------------------------------------
# T03 drag ruler (doc §5 quick-win #1, "drag-to-move with budget coloring")
# ---------------------------------------------------------------------------
# The path painted while a model is dragged in the Movement phase: one stroke
# per run MovementController hands over — UIConstants.CONFIRMED_GREEN within M,
# MARGINAL_YELLOW within M + Advance, INVALID_RED beyond — a tick where the band
# changes, a dot on the pickup point, a ring on each SHIFT waypoint and the
# cumulative inches beside the cursor. Lives under BoardRoot (board px), so it
# pans and zooms with the table. It only draws: MovementController owns the runs
# (current_drag_segments) and the label text.
class DragRuler extends Node2D:
	const STROKE_PX := 6.0
	const SHADOW_EXTRA_PX := 4.0  # the dark under-stroke is this much wider
	const TICK_HALF_PX := 12.0
	const LABEL_FONT_SIZE := 26
	# Contrast under-stroke, not a semantic colour: it keeps every slot colour
	# readable on light and dark board art alike (UIConstants neutral chrome).
	const SHADOW := UIC.OVERLAY_SHADOW
	const SHADOW_ALPHA := 0.6

	var segments: Array = []  # [{from, to, color_slot, distance_inches}]
	var waypoints: Array = []  # Vector2 corners dropped with SHIFT
	var cursor: Vector2 = Vector2.ZERO
	var label_text: String = ""
	var label_slot: String = ""
	var _label: Label = null

	func _ready() -> void:
		_label = Label.new()
		_label.name = "DragRulerLabel"
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		_label.add_theme_constant_override("outline_size", 8)
		_label.add_theme_color_override("font_outline_color", UIC.with_alpha(SHADOW, SHADOW_ALPHA))
		# Relative to the ruler (just under the ghost): lifts the number above the
		# ghost and its own readouts so the model in hand never hides it.
		_label.z_index = 60
		_label.visible = false
		add_child(_label)

	## Paint `segs` (see class comment) and put `text` beside the cursor, clear of
	## a model base `clearance_px` in radius sitting on it.
	func show_path(segs: Array, wps: Array, cursor_pos: Vector2, text: String, slot: String, clearance_px: float = 32.0) -> void:
		segments = segs.duplicate()
		waypoints = wps.duplicate()
		cursor = cursor_pos
		label_text = text
		label_slot = slot
		if _label != null:
			_label.text = text
			_label.add_theme_color_override("font_color", slot_color(slot))
			_label.position = cursor_pos + Vector2(clearance_px + 10.0, -LABEL_FONT_SIZE * 0.7)
			_label.visible = text != ""
		queue_redraw()

	func clear_path() -> void:
		segments = []
		waypoints = []
		label_text = ""
		label_slot = ""
		if _label != null:
			_label.text = ""
			_label.visible = false
		queue_redraw()

	func is_showing() -> bool:
		return not segments.is_empty()

	func slot_color(slot: String) -> Color:
		var uic = get_node_or_null("/root/UIConstants")
		if uic != null:
			var c = uic.all_slots().get(slot, null)
			if c is Color:
				return c
		match slot:  # a tree without the autoload (headless): the same slots, by name
			"MARGINAL_YELLOW":
				return UIC.MARGINAL_YELLOW
			"INVALID_RED":
				return UIC.INVALID_RED
		return UIC.CONFIRMED_GREEN

	func _draw() -> void:
		if segments.is_empty():
			return
		var colors: Array = []
		for seg in segments:
			colors.append(slot_color(str(seg.color_slot)))
		var shadow := UIC.with_alpha(SHADOW, SHADOW_ALPHA)
		var shadow_w := STROKE_PX + SHADOW_EXTRA_PX
		# 1) dark under-stroke, with round joins at every run end
		for seg in segments:
			draw_line(seg.from, seg.to, shadow, shadow_w, true)
			draw_circle(seg.from, shadow_w * 0.5, shadow)
			draw_circle(seg.to, shadow_w * 0.5, shadow)
		# 2) the coloured runs
		for i in range(segments.size()):
			var seg = segments[i]
			draw_line(seg.from, seg.to, colors[i], STROKE_PX, true)
			draw_circle(seg.from, STROKE_PX * 0.5, colors[i])
			draw_circle(seg.to, STROKE_PX * 0.5, colors[i])
		# 3) a tick across the path wherever the budget band changes
		for i in range(1, segments.size()):
			if str(segments[i].color_slot) == str(segments[i - 1].color_slot):
				continue
			var at: Vector2 = segments[i].from
			var along: Vector2 = (segments[i].to - segments[i].from).normalized()
			var across := Vector2(-along.y, along.x) * TICK_HALF_PX
			draw_line(at - across, at + across, shadow, 4.0 + SHADOW_EXTRA_PX, true)
			draw_line(at - across, at + across, colors[i], 4.0, true)
		# 4) the pickup point, each waypoint, and the cursor end
		var pale := UIC.NEUTRAL_UI_PALE_WHITE
		draw_circle(segments[0].from, 7.0, shadow)
		draw_circle(segments[0].from, 5.0, colors[0])
		for wp in waypoints:
			draw_circle(wp, 10.0, shadow)
			draw_circle(wp, 8.0, pale)
			draw_circle(wp, 4.5, _color_at(wp, colors))
		draw_circle(segments[-1].to, 7.0, shadow)
		draw_circle(segments[-1].to, 5.0, colors[-1])

	# The colour of the run that ends at (or starts from) point p.
	func _color_at(p: Vector2, colors: Array) -> Color:
		for i in range(segments.size()):
			if (segments[i].to as Vector2).distance_to(p) < 0.5:
				return colors[i]
		return colors[0]
