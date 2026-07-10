extends Node2D
class_name ObjectiveVisual

# ObjectiveVisual - Displays objective markers on the board with control indicators
# Shows a single circle representing the full control range (3" + 20mm radius)
# Styled with parchment/bone tones for contrast against green felt board

var objective_data: Dictionary = {}
var control_indicator: Label
var objective_marker: Node2D
var objective_circle: Line2D
var objective_polygon: Polygon2D
var tempting_target_label: Label = null  # Visual indicator for A Tempting Target
var loot_objective_label: Label = null  # Visual indicator for Here Be Loot (OA-1)
var card_action_label: Label = null  # 11e GDM card-action markers (Triangulated/Decoy/...)

# ISS-055 / 14.01: when terrain area(s) host this objective, the AREAS are
# the objective — rendered as highlighted polygons instead of the misleading
# control-radius circle. The official layouts' linked centre pair spans two
# areas that form one objective.
var is_terrain_objective: bool = false
var terrain_area_ids: Array = []
var _area_fills: Array = []     # Polygon2D per hosting area
var _area_outlines: Array = []  # Line2D per hosting area

# Constants
const OBJECTIVE_RADIUS_INCHES = 3.78740157  # 3" + 20mm (0.78740157")

# High-contrast color palette for objectives (visible against dark green board)
const OBJ_OUTLINE_COLOR = Color(1.0, 0.9, 0.6, 1.0)      # Bright gold outline
const OBJ_FILL_COLOR = Color(0.9, 0.85, 0.5, 0.45)       # Warm gold fill
const OBJ_CENTER_COLOR = Color(1.0, 0.95, 0.7, 1.0)      # Bright gold center marker
const OBJ_OUTER_GLOW_COLOR = Color(1.0, 0.9, 0.5, 0.2)   # Subtle outer glow

func setup(data: Dictionary) -> void:
	objective_data = data
	position = data.position
	name = data.id
	_create_visuals()

## 14.01: the terrain area pieces hosting this objective. Layout-sourced
## objectives name them via source_pieces (the centre pair lists both);
## otherwise the single area containing the marker point, if any. Mirrors
## MissionManager._objective_host_areas so what the player sees is exactly
## what controls.
func _find_hosting_areas() -> Array:
	# setup() runs before this node enters the tree (Main calls setup() then
	# add_child), so self-relative autoload paths don't resolve — go through
	# the main loop root instead.
	var tm = Engine.get_main_loop().root.get_node_or_null("TerrainManager") if Engine.get_main_loop() else null
	if tm == null:
		return []
	var areas: Array = []
	for piece_id in objective_data.get("source_pieces", []):
		for piece in tm.terrain_features:
			if str(piece.get("id", "")) == str(piece_id) and str(piece.get("piece_class", "")) == "area":
				areas.append(piece)
				break
	if areas.is_empty() and tm.has_method("area_at"):
		var hit = tm.area_at(position)
		if not hit.is_empty():
			areas.append(hit)
	return areas

func _create_visuals() -> void:
	# Create objective marker container
	objective_marker = Node2D.new()
	objective_marker.name = "ObjectiveMarker"
	add_child(objective_marker)

	# Calculate the full control radius (3" + 20mm)
	var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)

	# ISS-055 / 14.01: terrain-hosted objectives render as their area(s) —
	# control comes from being WITHIN the area, so the radius circle would
	# mislead. The centre cross + labels still mark the objective point.
	var host_areas = _find_hosting_areas()
	if not host_areas.is_empty():
		is_terrain_objective = true
		for area in host_areas:
			terrain_area_ids.append(str(area.get("id", "")))
			var local_points = PackedVector2Array()
			for p in area.get("polygon", PackedVector2Array()):
				local_points.append(p - position)
			if local_points.size() < 3:
				continue
			var fill = Polygon2D.new()
			fill.name = "AreaFill_%s" % str(area.get("id", ""))
			fill.color = Color(OBJ_FILL_COLOR.r, OBJ_FILL_COLOR.g, OBJ_FILL_COLOR.b, 0.28)
			fill.polygon = local_points
			fill.z_index = 0
			objective_marker.add_child(fill)
			_area_fills.append(fill)
			var outline = Line2D.new()
			outline.name = "AreaOutline_%s" % str(area.get("id", ""))
			outline.width = 5.0
			outline.default_color = OBJ_OUTLINE_COLOR
			outline.z_index = 1
			outline.closed = true
			for p in local_points:
				outline.add_point(p)
			objective_marker.add_child(outline)
			_area_outlines.append(outline)
		_create_marker_cross_and_labels(40.0)
		print("[ObjectiveVisual] %s rendered as terrain objective (areas: %s)" % [objective_data.get("id", "?"), str(terrain_area_ids)])
		return

	# Open-ground objective: classic marker + control-radius circle.
	# Outer glow ring for extra visibility
	var glow_ring = Polygon2D.new()
	glow_ring.name = "GlowRing"
	glow_ring.color = OBJ_OUTER_GLOW_COLOR
	glow_ring.z_index = -1
	var glow_points = PackedVector2Array()
	var glow_radius = control_radius + 6.0
	for i in range(32):
		var angle = i * TAU / 32
		glow_points.append(Vector2(cos(angle), sin(angle)) * glow_radius)
	glow_ring.polygon = glow_points
	objective_marker.add_child(glow_ring)

	# Filled objective area
	objective_polygon = Polygon2D.new()
	objective_polygon.name = "ObjectivePolygon"
	objective_polygon.color = OBJ_FILL_COLOR
	objective_polygon.z_index = 0

	# Create circle points for filled area
	var polygon_points = PackedVector2Array()
	for i in range(32):
		var angle = i * TAU / 32
		polygon_points.append(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_polygon.polygon = polygon_points
	objective_marker.add_child(objective_polygon)

	# Objective circle outline - bright gold, thick
	objective_circle = Line2D.new()
	objective_circle.name = "ObjectiveCircle"
	objective_circle.width = 5.0
	objective_circle.default_color = OBJ_OUTLINE_COLOR
	objective_circle.z_index = 1

	# Create circle points for outline
	for i in range(33):
		var angle = i * TAU / 32
		objective_circle.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
	objective_circle.closed = true
	objective_marker.add_child(objective_circle)

	_create_marker_cross_and_labels(control_radius + 35)

## The objective-point cross, control label, and id label — shared by the
## circle and terrain-area rendering modes. label_offset is how far above
## the marker the control label sits.
func _create_marker_cross_and_labels(label_offset: float) -> void:
	# Center marker - larger cross to indicate exact center
	var marker_size = 22.0
	var center_marker = Line2D.new()
	center_marker.name = "CenterMarker"
	center_marker.width = 3.0
	center_marker.default_color = OBJ_CENTER_COLOR
	center_marker.z_index = 2
	center_marker.add_point(Vector2(-marker_size, 0))
	center_marker.add_point(Vector2(marker_size, 0))
	objective_marker.add_child(center_marker)

	var center_marker2 = Line2D.new()
	center_marker2.name = "CenterMarker2"
	center_marker2.width = 3.0
	center_marker2.default_color = OBJ_CENTER_COLOR
	center_marker2.z_index = 2
	center_marker2.add_point(Vector2(0, -marker_size))
	center_marker2.add_point(Vector2(0, marker_size))
	objective_marker.add_child(center_marker2)

	# Diagonal cross lines for extra visibility
	var diag_size = marker_size * 0.7
	var diag1 = Line2D.new()
	diag1.name = "DiagMarker1"
	diag1.width = 2.0
	diag1.default_color = Color(OBJ_CENTER_COLOR.r, OBJ_CENTER_COLOR.g, OBJ_CENTER_COLOR.b, 0.6)
	diag1.z_index = 2
	diag1.add_point(Vector2(-diag_size, -diag_size))
	diag1.add_point(Vector2(diag_size, diag_size))
	objective_marker.add_child(diag1)

	var diag2 = Line2D.new()
	diag2.name = "DiagMarker2"
	diag2.width = 2.0
	diag2.default_color = Color(OBJ_CENTER_COLOR.r, OBJ_CENTER_COLOR.g, OBJ_CENTER_COLOR.b, 0.6)
	diag2.z_index = 2
	diag2.add_point(Vector2(-diag_size, diag_size))
	diag2.add_point(Vector2(diag_size, -diag_size))
	objective_marker.add_child(diag2)

	# Control indicator label - larger and with outline for readability
	control_indicator = Label.new()
	control_indicator.name = "ControlIndicator"
	control_indicator.text = "Uncontrolled"
	control_indicator.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	control_indicator.add_theme_font_size_override("font_size", 16)
	control_indicator.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	control_indicator.add_theme_constant_override("outline_size", 3)
	control_indicator.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	control_indicator.position = Vector2(-55, -label_offset)
	control_indicator.z_index = 10
	add_child(control_indicator)

	# Objective ID label — centered, bold, with outline
	var id_label = Label.new()
	id_label.name = "ObjectiveID"
	var raw_id = objective_data.id.replace("obj_", "").to_upper()
	var display_id = raw_id.replace("_", " ")
	id_label.text = display_id
	id_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	id_label.add_theme_font_size_override("font_size", 16)
	id_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 1.0))
	id_label.add_theme_constant_override("outline_size", 4)
	id_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_label.size = Vector2(120, 24)
	id_label.position = Vector2(-60, -12)
	id_label.z_index = 10
	add_child(id_label)

func update_control(player: int, contested: bool = false) -> void:
	var faction_name = ""
	if GameState and player > 0:
		faction_name = GameState.get_faction_name(player)
	var p_color = FactionPalettes.get_player_border_color(player) if FactionPalettes and player > 0 else Color.WHITE
	var outline_color: Color
	var fill_color: Color
	match player:
		1, 2:
			var label_text = faction_name if faction_name != "" else "Player %d" % player
			control_indicator.text = label_text
			control_indicator.modulate = Color(p_color, 1.0)
			outline_color = Color(p_color.r, p_color.g, p_color.b, 1.0)
			fill_color = Color(p_color.r, p_color.g, p_color.b, 0.35)
		_:
			# Controller 0 covers two very different states: a genuine
			# stand-off (equal, nonzero OC on both sides) and simply nobody
			# in range. Only the former may read "CONTESTED" — an empty
			# marker claiming CONTESTED was the mek-contested-status bug.
			if contested:
				control_indicator.text = "CONTESTED"
				control_indicator.modulate = Color(1.0, 1.0, 0.5, 1.0)
				outline_color = Color(1.0, 1.0, 0.4, 1.0)
				fill_color = Color(1.0, 1.0, 0.3, 0.4)
			else:
				control_indicator.text = "Uncontrolled"
				control_indicator.modulate = Color.WHITE
				outline_color = OBJ_OUTLINE_COLOR
				fill_color = OBJ_FILL_COLOR
	# Circle mode nodes are absent for terrain objectives (and vice versa).
	if objective_circle:
		objective_circle.default_color = outline_color
	if objective_polygon:
		objective_polygon.color = fill_color
	for outline in _area_outlines:
		outline.default_color = outline_color
	for fill in _area_fills:
		# Areas are big — keep the wash translucent so terrain reads through.
		fill.color = Color(fill_color.r, fill_color.g, fill_color.b, 0.28)

# T7-39: Flash effect constants for objective control changes
const FLASH_DURATION := 0.8  # Total flash animation duration
const FLASH_PULSE_COUNT := 3  # Number of brightness pulses
const FLASH_COLOR_AI_CAPTURE := Color(0.1, 1.0, 0.2, 0.8)  # Green flash on AI capture
const FLASH_COLOR_AI_LOSS := Color(1.0, 0.15, 0.05, 0.8)    # Red flash on AI loss
const FLASH_COLOR_CONTESTED := Color(1.0, 1.0, 0.2, 0.8)     # Yellow flash on contested
const FLASH_RING_EXPAND := 1.4  # How much the flash ring expands beyond control radius

var _flash_ring: Line2D = null  # Reusable flash ring node
var _flash_tween: Tween = null  # Current flash animation tween

func flash_control_change(new_controller: int, old_controller: int) -> void:
	"""T7-39: Flash objective marker when control state changes.
	Green flash when AI (Player 2) captures, red when AI loses control."""
	# Determine flash color based on who gained/lost control
	var flash_color: Color
	if new_controller == 2:
		# AI captured this objective
		flash_color = FLASH_COLOR_AI_CAPTURE
	elif old_controller == 2:
		# AI lost this objective
		flash_color = FLASH_COLOR_AI_LOSS
	elif new_controller == 0:
		# Became contested
		flash_color = FLASH_COLOR_CONTESTED
	else:
		# Player 1 captured (from contested/uncontrolled)
		flash_color = FLASH_COLOR_AI_LOSS  # Red from AI perspective

	print("[ObjectiveVisual] T7-39: Flashing %s (old=%d, new=%d, color=%s)" % [
		objective_data.get("id", "?"), old_controller, new_controller, flash_color])

	# Kill any existing flash animation
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	# Create flash ring if it doesn't exist
	if _flash_ring == null:
		_flash_ring = Line2D.new()
		_flash_ring.name = "FlashRing"
		_flash_ring.z_index = 3
		_flash_ring.closed = true
		var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)
		for i in range(33):
			var angle = i * TAU / 32
			_flash_ring.add_point(Vector2(cos(angle), sin(angle)) * control_radius)
		objective_marker.add_child(_flash_ring)

	# Configure flash ring appearance
	_flash_ring.width = 8.0
	_flash_ring.default_color = flash_color
	_flash_ring.visible = true
	_flash_ring.scale = Vector2.ONE

	# Create pulsing flash animation
	_flash_tween = create_tween()

	# Pulse brightness 3 times with expanding ring
	var pulse_duration = FLASH_DURATION / FLASH_PULSE_COUNT
	for i in range(FLASH_PULSE_COUNT):
		# Brighten + expand
		_flash_tween.tween_property(_flash_ring, "scale",
			Vector2.ONE * FLASH_RING_EXPAND, pulse_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_flash_tween.parallel().tween_property(_flash_ring, "default_color:a",
			flash_color.a, pulse_duration * 0.1)
		# Contract back
		_flash_tween.tween_property(_flash_ring, "scale",
			Vector2.ONE, pulse_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Final fade out
	_flash_tween.tween_property(_flash_ring, "default_color:a", 0.0, 0.2)
	_flash_tween.tween_callback(func(): _flash_ring.visible = false)

func set_tempting_target(enabled: bool, player: int = 0) -> void:
	"""Mark or unmark this objective as a Tempting Target for the given player."""
	if enabled:
		if tempting_target_label == null:
			tempting_target_label = Label.new()
			tempting_target_label.name = "TemptingTargetLabel"
			tempting_target_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
			tempting_target_label.add_theme_font_size_override("font_size", 13)
			tempting_target_label.add_theme_constant_override("outline_size", 3)
			tempting_target_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
			tempting_target_label.z_index = 10
			var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)
			tempting_target_label.position = Vector2(-65, control_radius + 5)
			add_child(tempting_target_label)
		tempting_target_label.text = "TEMPTING TARGET (P%d)" % player
		tempting_target_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))
		tempting_target_label.visible = true
		print("[ObjectiveVisual] Marked %s as Tempting Target for Player %d" % [objective_data.get("id", "?"), player])
	else:
		if tempting_target_label != null:
			tempting_target_label.visible = false
		print("[ObjectiveVisual] Unmarked %s as Tempting Target" % objective_data.get("id", "?"))

func set_loot_objective(enabled: bool, player: int = 0) -> void:
	"""Mark or unmark this objective as a Loot Objective for the given player (OA-1)."""
	if enabled:
		if loot_objective_label == null:
			loot_objective_label = Label.new()
			loot_objective_label.name = "LootObjectiveLabel"
			loot_objective_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
			loot_objective_label.add_theme_font_size_override("font_size", 13)
			loot_objective_label.add_theme_constant_override("outline_size", 3)
			loot_objective_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
			loot_objective_label.z_index = 10
			var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)
			# Position below objective (or below tempting target label if present)
			var y_offset = control_radius + 5
			if tempting_target_label != null and tempting_target_label.visible:
				y_offset += 20
			loot_objective_label.position = Vector2(-55, y_offset)
			add_child(loot_objective_label)
		loot_objective_label.text = "LOOT OBJECTIVE (P%d)" % player
		loot_objective_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.2, 1.0))  # Orky green
		loot_objective_label.visible = true
		print("[ObjectiveVisual] Marked %s as Loot Objective for Player %d" % [objective_data.get("id", "?"), player])
	else:
		if loot_objective_label != null:
			loot_objective_label.visible = false
		print("[ObjectiveVisual] Unmarked %s as Loot Objective" % objective_data.get("id", "?"))

func set_card_action_badges(badges: Array) -> void:
	"""11e GDM card-action markers on this objective (Triangulated, Consecrated,
	Decoy, intel tokens, operation markers). Empty array clears the badge."""
	if badges.is_empty():
		if card_action_label != null:
			card_action_label.visible = false
		return
	if card_action_label == null:
		card_action_label = Label.new()
		card_action_label.name = "CardActionBadges"
		card_action_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		card_action_label.add_theme_font_size_override("font_size", 16)
		card_action_label.add_theme_constant_override("outline_size", 3)
		card_action_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		card_action_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0, 1.0))
		card_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_action_label.z_index = 10
		card_action_label.size = Vector2(240, 20)
		var control_radius = Measurement.inches_to_px(OBJECTIVE_RADIUS_INCHES)
		# Below the objective, under the Tempting Target / Loot labels
		card_action_label.position = Vector2(-120, control_radius + 25)
		add_child(card_action_label)
	card_action_label.text = " · ".join(PackedStringArray(badges))
	card_action_label.visible = true

func highlight(enabled: bool) -> void:
	if enabled:
		objective_circle.width = 7.0
		modulate.a = 1.0
	else:
		objective_circle.width = 5.0
		modulate.a = 1.0

func get_objective_id() -> String:
	return objective_data.get("id", "")

func get_position_inches() -> Vector2:
	return Vector2(
		Measurement.px_to_inches(position.x),
		Measurement.px_to_inches(position.y)
	)

func get_control_radius_inches() -> float:
	return OBJECTIVE_RADIUS_INCHES

func set_burning(is_burning: bool) -> void:
	"""Visual indicator that a burn action is in progress on this objective."""
	if is_burning:
		control_indicator.text = "BURNING"
		control_indicator.modulate = Color(1.0, 0.5, 0.0, 1.0)  # Orange
		objective_circle.default_color = Color(1.0, 0.4, 0.0, 1.0)  # Orange outline
		objective_polygon.color = Color(1.0, 0.3, 0.0, 0.35)  # Orange fill

func set_removed() -> void:
	"""Hide the objective when it has been burned or removed from play."""
	visible = false
	print("ObjectiveVisual: %s removed from board" % objective_data.get("id", "unknown"))
