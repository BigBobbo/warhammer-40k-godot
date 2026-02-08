extends Node2D
# BaseShape and CircularBase are available via class_name - no preloads needed

var owner_player: int = 1
var is_preview: bool = false
var model_number: int = 1
var debug_mode: bool = false
var base_shape: BaseShape = null
var model_data: Dictionary = {}

func _ready() -> void:
	z_index = 10

func _draw() -> void:
	if not base_shape:
		# Fallback to circular if no shape defined
		base_shape = CircularBase.new(20.0)

	var fill_color: Color
	var border_color: Color
	var border_width: float = 3.5

	# Color logic
	if debug_mode:
		# Use distinct debug colors (bright yellow/orange)
		fill_color = Color(1.0, 0.8, 0.0, 0.9)  # Yellow
		border_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
		border_width = 4.0  # Thicker border in debug mode

		# Draw additional debug indicator ring
		draw_arc(Vector2.ZERO, base_shape.get_bounds().size.x / 2.0 + 4, 0, TAU, 32, Color(1.0, 1.0, 0.0, 0.5), 2.0)
	elif owner_player == 1:
		# P1: Dark blue-gray fill, gold border
		fill_color = Color(0.2, 0.25, 0.45, 0.8 if is_preview else 1.0)
		border_color = Color(0.83, 0.59, 0.38, 1.0)  # Gold
	else:
		# P2: Deep crimson fill, bone border
		fill_color = Color(0.5, 0.12, 0.1, 0.8 if is_preview else 1.0)
		border_color = Color(0.85, 0.8, 0.65, 1.0)  # Bone

	# Get rotation from model data (defaults to 0.0 for circular bases)
	var rot = model_data.get("rotation", 0.0)

	# Use base shape's draw method with rotation
	base_shape.draw(self, Vector2.ZERO, rot, fill_color, border_color, border_width)

	# Draw silhouette/glyph overlay based on setting
	if not debug_mode:
		_draw_overlay(fill_color, border_color)

	# Draw model number with shadow for readability
	var font = ThemeDB.fallback_font
	var text = str(model_number)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)

	# Black shadow behind text
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.BLACK)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

func _draw_overlay(fill_color: Color, border_color: Color) -> void:
	var style = SettingsService.unit_visual_style if SettingsService else "classic"
	if style == "classic":
		return

	# Need unit_id meta to look up faction/keywords — skip if not set yet
	if not has_meta("unit_id"):
		return

	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	var overlay_color = Color(border_color.r, border_color.g, border_color.b, 0.6)

	# Determine unit type from keywords
	var unit_type = _get_unit_type()
	var faction = _get_faction_name()

	if style == "style_a":
		_draw_silhouette(radius, overlay_color, unit_type)
	elif style == "style_b":
		_draw_faction_glyph(radius, overlay_color, faction)

func _draw_silhouette(radius: float, color: Color, unit_type: String) -> void:
	var s = radius * 0.5  # Scale factor

	match unit_type:
		"VEHICLE":
			# Vehicle hull + turret silhouette
			# Hull body
			var hull = PackedVector2Array([
				Vector2(-s * 1.2, -s * 0.4),
				Vector2(s * 1.2, -s * 0.4),
				Vector2(s * 1.0, s * 0.4),
				Vector2(-s * 1.0, s * 0.4)
			])
			draw_colored_polygon(hull, color)
			# Turret circle
			draw_circle(Vector2(0, -s * 0.1), s * 0.35, color)
			# Gun barrel
			draw_line(Vector2(0, -s * 0.1), Vector2(s * 0.9, -s * 0.3), color, 2.0)

		"MONSTER":
			# Monster body + claws silhouette
			# Torso
			draw_circle(Vector2(0, s * 0.1), s * 0.5, color)
			# Head
			draw_circle(Vector2(0, -s * 0.5), s * 0.25, color)
			# Left claw
			draw_line(Vector2(-s * 0.5, -s * 0.2), Vector2(-s * 1.0, -s * 0.6), color, 2.5)
			draw_line(Vector2(-s * 1.0, -s * 0.6), Vector2(-s * 1.2, -s * 0.3), color, 2.0)
			# Right claw
			draw_line(Vector2(s * 0.5, -s * 0.2), Vector2(s * 1.0, -s * 0.6), color, 2.5)
			draw_line(Vector2(s * 1.0, -s * 0.6), Vector2(s * 1.2, -s * 0.3), color, 2.0)

		_:
			# Infantry: head + body + weapon
			# Head
			draw_circle(Vector2(0, -s * 0.6), s * 0.2, color)
			# Body (torso triangle)
			var body = PackedVector2Array([
				Vector2(-s * 0.35, s * 0.05),
				Vector2(s * 0.35, s * 0.05),
				Vector2(0, -s * 0.35)
			])
			draw_colored_polygon(body, color)
			# Weapon (diagonal line from shoulder)
			draw_line(Vector2(s * 0.2, -s * 0.25), Vector2(s * 0.7, -s * 0.7), color, 2.0)

func _draw_faction_glyph(radius: float, color: Color, faction: String) -> void:
	var s = radius * 0.45  # Scale factor
	var f = faction.to_lower()

	# Determine which glyph to draw based on faction name (flexible matching)
	if f.find("space marine") >= 0 or f.find("astartes") >= 0 or f.find("custode") >= 0:
		# Aquila wings (simplified double-headed eagle) — Imperium factions
		# Left wing
		draw_line(Vector2(0, 0), Vector2(-s * 1.0, -s * 0.5), color, 2.5)
		draw_line(Vector2(-s * 1.0, -s * 0.5), Vector2(-s * 0.6, -s * 0.2), color, 2.0)
		draw_line(Vector2(-s * 0.6, -s * 0.2), Vector2(-s * 1.2, -s * 0.1), color, 2.0)
		# Right wing
		draw_line(Vector2(0, 0), Vector2(s * 1.0, -s * 0.5), color, 2.5)
		draw_line(Vector2(s * 1.0, -s * 0.5), Vector2(s * 0.6, -s * 0.2), color, 2.0)
		draw_line(Vector2(s * 0.6, -s * 0.2), Vector2(s * 1.2, -s * 0.1), color, 2.0)
		# Central skull
		draw_circle(Vector2(0, -s * 0.1), s * 0.25, color)

	elif f.find("ork") >= 0:
		# Ork skull glyph
		# Skull circle
		draw_circle(Vector2(0, -s * 0.15), s * 0.4, color)
		# Jaw
		var jaw = PackedVector2Array([
			Vector2(-s * 0.35, s * 0.15),
			Vector2(s * 0.35, s * 0.15),
			Vector2(s * 0.25, s * 0.5),
			Vector2(-s * 0.25, s * 0.5)
		])
		draw_colored_polygon(jaw, color)
		# Tusks
		draw_line(Vector2(-s * 0.3, s * 0.35), Vector2(-s * 0.4, s * 0.1), color, 2.5)
		draw_line(Vector2(s * 0.3, s * 0.35), Vector2(s * 0.4, s * 0.1), color, 2.5)

	else:
		# Generic skull fallback
		# Skull
		draw_circle(Vector2(0, -s * 0.2), s * 0.35, color)
		# Eyes (dark holes)
		var eye_color = Color(color.r, color.g, color.b, color.a * 0.3)
		draw_circle(Vector2(-s * 0.12, -s * 0.25), s * 0.1, eye_color)
		draw_circle(Vector2(s * 0.12, -s * 0.25), s * 0.1, eye_color)
		# Jaw line
		draw_line(Vector2(-s * 0.2, s * 0.05), Vector2(s * 0.2, s * 0.05), color, 2.0)

func _get_unit_type() -> String:
	var unit_id = get_meta("unit_id") if has_meta("unit_id") else ""
	if unit_id == "":
		return "INFANTRY"

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return "INFANTRY"

	var keywords = unit.get("meta", {}).get("keywords", [])
	for keyword in keywords:
		var kw = str(keyword).to_upper()
		if kw == "VEHICLE":
			return "VEHICLE"
		elif kw == "MONSTER":
			return "MONSTER"

	return "INFANTRY"

func _get_faction_name() -> String:
	var unit_id = get_meta("unit_id") if has_meta("unit_id") else ""
	if unit_id == "":
		return ""

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return ""

	var owner = unit.get("owner", owner_player)
	var faction = GameState.get_faction_name(owner)

	# If faction is unknown, try to infer from unit keywords
	if faction == "Unknown" or faction.begins_with("Player"):
		var keywords = unit.get("meta", {}).get("keywords", [])
		for keyword in keywords:
			var kw = str(keyword).to_lower()
			if kw.find("ork") >= 0:
				return "Orks"
			elif kw.find("space marine") >= 0 or kw.find("astartes") >= 0:
				return "Space Marines"
			elif kw.find("custode") >= 0:
				return "Adeptus Custodes"

	return faction

func set_preview(preview: bool) -> void:
	is_preview = preview
	queue_redraw()

func set_debug_mode(active: bool) -> void:
	debug_mode = active
	queue_redraw()

func set_model_data(data: Dictionary) -> void:
	model_data = data
	base_shape = Measurement.create_base_shape(data)
	queue_redraw()

	# Set model number if available
	var model_id = data.get("id", "")
	if model_id.begins_with("m"):
		var num_str = model_id.substr(1)
		if num_str.is_valid_int():
			model_number = num_str.to_int()
