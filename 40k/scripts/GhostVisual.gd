extends Node2D
# BaseShape and CircularBase are available via class_name - no preloads needed

var owner_player: int = 1
var is_valid_position: bool = true
var model_data: Dictionary = {}
var base_rotation: float = 0.0
var base_shape: BaseShape = null

# Sprite overlay so the player can see which way the model is facing while
# deploying (mirrors TokenVisual's letter-mode Layer 3). Resolved lazily in
# _draw() because unit_id meta is set after set_model_data() at creation.
var _sprite_resolved: bool = false
var _sprite_texture: Texture2D = null
var _tank_resolved: bool = false
var _tank_body_tex: Texture2D = null
var _tank_barrel_tex: Texture2D = null

# MA-17: Model type label shown during placement
var model_type_label: String = ""

# Pulsing effect state
var _pulse_time: float = 0.0
const PULSE_SPEED: float = 2.5  # Cycles per second
const PULSE_MIN_ALPHA: float = 0.7  # Minimum alpha multiplier during pulse
const PULSE_MAX_ALPHA: float = 1.0  # Maximum alpha multiplier during pulse

# Connecting line to nearest placed model (world-space position, or null if none)
var nearest_model_world_pos = null  # Vector2 or null
var nearest_model_distance_inches: float = -1.0  # -1 means no data

# P3-116: Coherency preview — lines to ALL unit models during movement
# Each entry: { "world_pos": Vector2, "distance_inches": float, "in_coherency": bool }
var coherency_lines_data: Array = []
var coherency_status_text: String = ""  # e.g., "Coherent" or "2/3 coherent"
var coherency_is_valid: bool = true  # Overall coherency status

func _ready() -> void:
	z_index = 20
	set_process(true)

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()

func _draw() -> void:
	if not base_shape:
		# Fallback to circular if no shape defined
		print("WARNING: GhostVisual._draw() called with null base_shape! Using fallback circle.")
		print("  model_data: ", model_data)
		base_shape = CircularBase.new(20.0)

	# Calculate pulse alpha multiplier (smooth sine wave)
	var pulse_factor = lerp(PULSE_MIN_ALPHA, PULSE_MAX_ALPHA, (sin(_pulse_time * PULSE_SPEED * TAU) + 1.0) / 2.0)

	var fill_color: Color
	var border_color: Color

	if not is_valid_position:
		fill_color = Color(0.8, 0.2, 0.2, 0.5 * pulse_factor)
		border_color = Color(1.0, 0.0, 0.0, 0.8 * pulse_factor)
	else:
		if owner_player == 1:
			# P1: Blue-gray fill (reduced alpha), gold border
			fill_color = Color(0.2, 0.25, 0.45, 0.4 * pulse_factor)
			border_color = Color(0.83, 0.59, 0.38, 0.6 * pulse_factor)
		else:
			# P2: Crimson fill (reduced alpha), bone border
			fill_color = Color(0.5, 0.12, 0.1, 0.4 * pulse_factor)
			border_color = Color(0.85, 0.8, 0.65, 0.6 * pulse_factor)

	# Check if enhanced mode for gradient ghost fill
	var style = SettingsService.unit_visual_style if SettingsService else "classic"
	if style == "letter":
		_draw_ghost_letter_mode(pulse_factor)
	elif style == "enhanced":
		var ghost_alpha = fill_color.a
		var ghost_base = Color(fill_color.r, fill_color.g, fill_color.b, ghost_alpha)
		if base_shape.get_type() == "circular":
			TokenDrawUtils.draw_gradient_circle(self, Vector2.ZERO, (base_shape as CircularBase).radius, ghost_base)
			# Light border rim
			var rim_color = Color(border_color.r, border_color.g, border_color.b, ghost_alpha * 0.7)
			draw_arc(Vector2.ZERO, (base_shape as CircularBase).radius, 0, TAU, 48, rim_color, 2.0)
		else:
			var poly_points = _get_ghost_polygon()
			TokenDrawUtils.draw_gradient_polygon(self, poly_points, ghost_base)
			# Light border
			var rim_color = Color(border_color.r, border_color.g, border_color.b, ghost_alpha * 0.7)
			var closed = PackedVector2Array()
			for p in poly_points:
				closed.append(p)
			if poly_points.size() > 0:
				closed.append(poly_points[0])
			draw_polyline(closed, rim_color, 2.0)
		# Show the model's sprite (or a facing arrow) so the player can see the
		# deployment facing and how it changes as they rotate.
		if not _draw_ghost_model_art(pulse_factor):
			_draw_facing_arrow(pulse_factor, border_color)
	else:
		# Original rendering path (classic / style_a / style_b)
		base_shape.draw(self, Vector2.ZERO, base_rotation, fill_color, border_color, 2.0)
		# Show the model's sprite (or a facing arrow) so the player can see the
		# deployment facing and how it changes as they rotate.
		if not _draw_ghost_model_art(pulse_factor):
			_draw_facing_arrow(pulse_factor, border_color)

	# Draw connecting lines to unit models (if available)
	if coherency_lines_data.size() > 0:
		# P3-116: Draw coherency lines to ALL models in unit
		_draw_all_coherency_lines()
	else:
		# Fallback: single nearest model line (used in deployment)
		_draw_coherency_line(border_color)

	# MA-17: Draw model type label above the ghost
	if model_type_label != "":
		_draw_model_type_label(pulse_factor)

func _draw_coherency_line(border_color: Color) -> void:
	if nearest_model_world_pos == null:
		return

	# Convert BoardRoot-space target to local-space for drawing.
	# This node may be a child of a container (e.g. ghost_visual) that is positioned
	# at the drag location, so we must account for the full parent chain position.
	var board_pos: Vector2 = position
	if get_parent():
		board_pos = get_parent().position + position
	var local_target: Vector2 = nearest_model_world_pos - board_pos

	# Determine line color based on coherency (2" threshold)
	var line_color: Color
	if nearest_model_distance_inches >= 0.0 and nearest_model_distance_inches <= 2.0 + Measurement.DISTANCE_TOLERANCE_INCHES:
		line_color = Color(0.2, 0.9, 0.2, 0.4)  # Green - in coherency
	else:
		line_color = Color(0.9, 0.2, 0.2, 0.4)  # Red - out of coherency

	# Draw dashed line from ghost center to nearest model
	var from_pos = Vector2.ZERO
	var direction = (local_target - from_pos)
	var total_length = direction.length()
	if total_length < 1.0:
		return

	var dash_length = 6.0
	var gap_length = 4.0
	var segment_length = dash_length + gap_length
	var dir_normalized = direction.normalized()

	var distance_traveled = 0.0
	while distance_traveled < total_length:
		var dash_start = from_pos + dir_normalized * distance_traveled
		var dash_end_dist = min(distance_traveled + dash_length, total_length)
		var dash_end = from_pos + dir_normalized * dash_end_dist
		draw_line(dash_start, dash_end, line_color, 1.5, true)
		distance_traveled += segment_length

func _draw_all_coherency_lines() -> void:
	"""P3-116: Draw dashed lines from ghost to all unit models, colored by coherency status."""
	# Calculate our position in BoardRoot space once (accounts for parent container offset)
	var board_pos: Vector2 = position
	if get_parent():
		board_pos = get_parent().position + position

	for line_data in coherency_lines_data:
		var world_pos: Vector2 = line_data.get("world_pos", Vector2.ZERO)
		var in_coherency: bool = line_data.get("in_coherency", false)

		# Convert BoardRoot-space target to local-space for drawing.
		# This node may be a child of a container (e.g. ghost_visual) that is positioned
		# at the drag location, so we must account for the parent's position.
		var local_target: Vector2 = world_pos - board_pos

		var line_color: Color
		if in_coherency:
			line_color = Color(0.2, 0.9, 0.2, 0.5)  # Green - in coherency
		else:
			line_color = Color(0.9, 0.2, 0.2, 0.6)  # Red - out of coherency

		# Draw dashed line
		var from_pos = Vector2.ZERO
		var direction = (local_target - from_pos)
		var total_length = direction.length()
		if total_length < 1.0:
			continue

		var dash_length = 6.0
		var gap_length = 4.0
		var segment_length = dash_length + gap_length
		var dir_normalized = direction.normalized()

		var distance_traveled = 0.0
		while distance_traveled < total_length:
			var dash_start = from_pos + dir_normalized * distance_traveled
			var dash_end_dist = min(distance_traveled + dash_length, total_length)
			var dash_end = from_pos + dir_normalized * dash_end_dist
			draw_line(dash_start, dash_end, line_color, 1.5, true)
			distance_traveled += segment_length

		# Draw a small dot at the target model position for clarity
		var dot_color = Color(0.2, 0.9, 0.2, 0.6) if in_coherency else Color(0.9, 0.2, 0.2, 0.6)
		draw_circle(local_target, 3.0, dot_color)

func _draw_model_type_label(pulse_factor: float) -> void:
	"""MA-17: Draw a small label above the ghost showing the model type (e.g., 'Spanner')."""
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text_size = font.get_string_size(model_type_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

	# Position the label above the ghost base
	var base_bounds = base_shape.get_bounds() if base_shape else Rect2(-20, -20, 40, 40)
	var label_y = base_bounds.position.y - 8.0  # Above the top of the base
	var label_pos = Vector2(-text_size.x / 2.0, label_y)

	# Semi-transparent dark background for readability
	var bg_padding = Vector2(4, 2)
	var bg_rect = Rect2(
		label_pos.x - bg_padding.x,
		label_y - text_size.y - bg_padding.y,
		text_size.x + bg_padding.x * 2,
		text_size.y + bg_padding.y * 2
	)
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.5 * pulse_factor))

	# White text
	var text_color = Color(1.0, 1.0, 1.0, 0.9 * pulse_factor)
	draw_string(font, label_pos, model_type_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

func set_coherency_preview(lines_data: Array, status_text: String, is_valid: bool) -> void:
	"""P3-116: Set coherency preview data for all unit models during movement.
	lines_data: Array of { world_pos: Vector2, distance_inches: float, in_coherency: bool }"""
	coherency_lines_data = lines_data
	coherency_status_text = status_text
	coherency_is_valid = is_valid

func clear_coherency_preview() -> void:
	"""P3-116: Clear all coherency preview lines."""
	coherency_lines_data.clear()
	coherency_status_text = ""
	coherency_is_valid = true

func set_nearest_model(world_pos, distance_inches: float) -> void:
	nearest_model_world_pos = world_pos
	nearest_model_distance_inches = distance_inches
	# No need to queue_redraw() here as _process() already does it every frame

func clear_nearest_model() -> void:
	nearest_model_world_pos = null
	nearest_model_distance_inches = -1.0

func set_validity(valid: bool) -> void:
	is_valid_position = valid
	queue_redraw()

func set_model_data(data: Dictionary) -> void:
	print("[GhostVisual] set_model_data called")
	print("[GhostVisual] data keys: ", data.keys())
	model_data = data
	base_shape = Measurement.create_base_shape(data)
	# Re-resolve the facing sprite for the new model (combined deploys and the
	# "next model" step reuse the same ghost with different model data).
	_sprite_resolved = false
	_sprite_texture = null
	_tank_resolved = false
	_tank_body_tex = null
	_tank_barrel_tex = null
	print("[GhostVisual] base_shape created: ", base_shape != null)
	if base_shape:
		print("[GhostVisual] base_shape type: ", base_shape.get_type())
	queue_redraw()

func set_model_type_label(label: String) -> void:
	"""MA-17: Set the model type label to display above the ghost during placement."""
	print("[GhostVisual] MA-17: set_model_type_label('%s')" % label)
	model_type_label = label
	queue_redraw()

func set_base_rotation(rot: float) -> void:
	base_rotation = rot
	# Don't set Node2D rotation - the shape handles rotation in draw()
	queue_redraw()

func get_base_rotation() -> float:
	"""Get the current rotation of the ghost base"""
	return base_rotation

func rotate_by(angle: float) -> void:
	"""Rotate the ghost by the given angle (in radians)"""
	base_rotation += angle
	# Don't set Node2D rotation - the shape handles rotation in draw()
	queue_redraw()

func _get_ghost_polygon() -> PackedVector2Array:
	var points = PackedVector2Array()
	var shape_type = base_shape.get_type()

	if shape_type == "rectangular":
		var rect_base = base_shape as RectangularBase
		var hl = rect_base.length / 2.0
		var hw = rect_base.width / 2.0
		var corners = [
			Vector2(-hl, -hw),
			Vector2(hl, -hw),
			Vector2(hl, hw),
			Vector2(-hl, hw)
		]
		for c in corners:
			points.append(base_shape.rotate_point(c, base_rotation))
	elif shape_type == "oval":
		var oval_base = base_shape as OvalBase
		var segments = 32
		for i in range(segments):
			var angle = (float(i) / float(segments)) * TAU
			var local_point = Vector2(
				oval_base.length * cos(angle),
				oval_base.width * sin(angle)
			)
			points.append(base_shape.rotate_point(local_point, base_rotation))
	else:
		# Fallback circle
		var circ = base_shape as CircularBase
		var r = circ.radius if circ else 20.0
		for i in range(32):
			var angle = (float(i) / 32.0) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * r)

	return points

# --- Letter-mode ghost rendering ---

func _draw_ghost_letter_mode(pulse_factor: float) -> void:
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0

	# Get unit color if unit_id meta is available
	var ghost_color = _get_ghost_unit_color()
	ghost_color.a = 0.45 * pulse_factor  # Semi-transparent with pulse
	var border_shade = Color(ghost_color.r * 0.6, ghost_color.g * 0.6, ghost_color.b * 0.6, 0.6 * pulse_factor)

	# Draw solid fill
	if base_shape.get_type() == "circular":
		draw_circle(Vector2.ZERO, radius, ghost_color)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, border_shade, 2.0)
	else:
		var poly_points = _get_ghost_polygon()
		draw_colored_polygon(poly_points, ghost_color)
		for i in range(poly_points.size()):
			var from = poly_points[i]
			var to = poly_points[(i + 1) % poly_points.size()]
			draw_line(from, to, border_shade, 2.0)

	# Layer 3: top-down unit art / tank sprite (rotates with base_rotation so the
	# facing is visible during deployment). Units without dedicated art keep the
	# Vassal-style letter counter plus a small facing arrow.
	if not _draw_ghost_model_art(pulse_factor):
		_draw_ghost_letter_label(radius, pulse_factor)
		_draw_facing_arrow(pulse_factor, border_shade)


func _get_ghost_unit_color() -> Color:
	if has_meta("unit_id"):
		var unit_id = get_meta("unit_id")
		var color = GameState.get_unit_color(unit_id)
		if color != Color.TRANSPARENT:
			return color
	# Fallback to player colors
	if owner_player == 1:
		return Color(0.2, 0.35, 0.6)
	else:
		return Color(0.6, 0.2, 0.15)


func _get_ghost_faction_font() -> Font:
	if not has_meta("unit_id"):
		return FactionPalettes.FONT_CASLON
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return FactionPalettes.FONT_CASLON
	var unit_owner = unit.get("owner", owner_player)
	var faction = GameState.get_faction_name(unit_owner)
	# If faction is unknown, try to infer from unit keywords
	if faction == "Unknown" or faction.begins_with("Player"):
		var keywords = unit.get("meta", {}).get("keywords", [])
		for keyword in keywords:
			var kw = str(keyword).to_lower()
			if kw.find("ork") >= 0:
				faction = "Orks"
				break
			elif kw.find("space marine") >= 0 or kw.find("astartes") >= 0:
				faction = "Space Marines"
				break
			elif kw.find("custode") >= 0:
				faction = "Adeptus Custodes"
				break
	return FactionPalettes.get_faction_font(faction)

func _draw_ghost_letter_label(radius: float, pulse_factor: float) -> void:
	if not has_meta("unit_id"):
		return

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	# Get label text
	var label = GameState.get_unit_label(unit_id)
	if label == "":
		var unit_name = unit.get("meta", {}).get("name", "?")
		label = unit_name.substr(0, 1).to_upper()

	var ghost_color = _get_ghost_unit_color()
	var text_color = FactionPalettes.get_contrast_text_color(ghost_color)
	text_color.a = 0.7 * pulse_factor

	var font = _get_ghost_faction_font()
	var font_size = int(radius * 1.0)
	var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2.0, text_size.y / 4.0)

	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


# --- Facing sprite overlay (mirrors TokenVisual's letter-mode Layer 3) ---

func _get_ghost_unit_type() -> String:
	if not has_meta("unit_id"):
		return "INFANTRY"
	var unit = GameState.get_unit(get_meta("unit_id"))
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

func _get_ghost_faction_name() -> String:
	if not has_meta("unit_id"):
		return ""
	var unit = GameState.get_unit(get_meta("unit_id"))
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

func _resolve_ghost_sprite() -> void:
	_sprite_resolved = true
	if not has_meta("unit_id") or SpriteResolver == null:
		return
	var unit = GameState.get_unit(get_meta("unit_id"))
	if unit.is_empty():
		return
	var unit_name = unit.get("meta", {}).get("name", "")
	_sprite_texture = SpriteResolver.resolve_sprite(unit_name, _get_ghost_faction_name(), _get_ghost_unit_type())

func _get_ghost_sprite_texture() -> Texture2D:
	if not _sprite_resolved:
		_resolve_ghost_sprite()
	return _sprite_texture

func _resolve_ghost_tank_sprites() -> void:
	_tank_resolved = true
	if not has_meta("unit_id"):
		return
	if _get_ghost_unit_type() != "VEHICLE":
		return
	var unit = GameState.get_unit(get_meta("unit_id"))
	var keywords = unit.get("meta", {}).get("keywords", [])
	var titanic := false
	for k in keywords:
		if str(k).to_upper() == "TITANIC":
			titanic = true
			break
	var faction = _get_ghost_faction_name()
	_tank_body_tex = TokenTankSprites.body_texture(faction, owner_player, titanic)
	# The oversized titanic hull reads better without the standard turret.
	_tank_barrel_tex = null if titanic else TokenTankSprites.barrel_texture(faction, owner_player)

func _get_tank_body_texture() -> Texture2D:
	if not _tank_resolved:
		_resolve_ghost_tank_sprites()
	return _tank_body_tex

# Draws the model's top-down art (or generic vehicle tank sprite) rotated by
# base_rotation so the deployment facing is visible. Returns true if it drew
# any sprite, false if the unit has no dedicated art (caller falls back to the
# letter counter / facing arrow).
func _draw_ghost_model_art(pulse_factor: float) -> bool:
	if not has_meta("unit_id"):
		return false
	var tex := _get_ghost_sprite_texture()
	if tex != null:
		_draw_ghost_sprite_texture(tex, pulse_factor)
		return true
	if _get_tank_body_texture() != null:
		_draw_ghost_tank_sprite(pulse_factor)
		return true
	return false

func _draw_ghost_sprite_texture(tex: Texture2D, pulse_factor: float) -> void:
	# Top-down art mapped 1:1 over the base, rotated to the model's facing.
	var bounds = base_shape.get_bounds()
	var fit = min(bounds.size.x / tex.get_width(), bounds.size.y / tex.get_height())
	var tint = Color(1, 1, 1, 0.85 * pulse_factor)
	draw_set_transform(Vector2.ZERO, base_rotation, Vector2(fit, fit))
	var tex_size = Vector2(tex.get_width(), tex.get_height())
	draw_texture_rect(tex, Rect2(-tex_size / 2.0, tex_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ghost_tank_sprite(pulse_factor: float) -> void:
	var bounds = base_shape.get_bounds()
	var body = _tank_body_tex
	var fit = min(bounds.size.x * 0.95 / body.get_width(), bounds.size.y * 0.95 / body.get_height())
	var tint = Color(1, 1, 1, 0.85 * pulse_factor)
	draw_set_transform(Vector2.ZERO, base_rotation, Vector2(fit, fit))
	var body_size = Vector2(body.get_width(), body.get_height())
	draw_texture_rect(body, Rect2(-body_size / 2.0, body_size), false, tint)
	if _tank_barrel_tex != null:
		var barrel = _tank_barrel_tex
		var barrel_size = Vector2(barrel.get_width(), barrel.get_height())
		# The Kenney barrel texture points muzzle-down; flip it 180° so the gun
		# faces the hull front (up at rotation 0), matching TokenVisual.
		draw_set_transform(Vector2.ZERO, base_rotation + PI, Vector2(fit, fit))
		draw_texture_rect(barrel, Rect2(Vector2(-barrel_size.x / 2.0, -barrel_size.y * 0.28), barrel_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Small chevron at the front of the base pointing in the facing direction, so
# units without dedicated sprite art (and circular bases in particular) still
# show which way they face and visibly turn when the player rotates them.
func _draw_facing_arrow(pulse_factor: float, arrow_color: Color) -> void:
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	if radius <= 0.0:
		return
	# At rotation 0 the sprite faces "up" (-Y); the facing vector for base_rotation
	# is therefore (sin, -cos), matching the sprite draw_set_transform rotation.
	var front = Vector2(sin(base_rotation), -cos(base_rotation))
	var perp = Vector2(-front.y, front.x)
	var tip = front * radius
	var back = front * (radius * 0.55)
	var half = radius * 0.28
	var left = back + perp * half
	var right = back - perp * half
	var col = Color(arrow_color.r, arrow_color.g, arrow_color.b, 0.9 * pulse_factor)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), col)
