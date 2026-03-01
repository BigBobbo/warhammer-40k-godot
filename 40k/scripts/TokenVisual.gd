extends Node2D
# BaseShape and CircularBase are available via class_name - no preloads needed

var owner_player: int = 1
var is_preview: bool = false
var model_number: int = 1
var debug_mode: bool = false
var base_shape: BaseShape = null
var model_data: Dictionary = {}

# Enhanced mode: selection/hover state
var is_selected: bool = false
var is_hovered: bool = false
var _pulse_time: float = 0.0

# Sprite overlay (Phase 2 - static)
var _sprite_resolved: bool = false
var _sprite_texture: Texture2D = null

# Animated sprite system
var _anim_resolved: bool = false
var _animations: Dictionary = {}               # animation_name -> SpriteAnimationData
var _current_anim_name: String = "idle"         # Active animation
var _animation_time: float = 0.0               # Continuous time for procedural animations
var _anim_needs_redraw: bool = false            # Whether animation frame changed this tick

# Animation state constants
const ANIM_IDLE := "idle"
const ANIM_MOVE := "move"
const ANIM_ATTACK := "attack"
const ANIM_DEATH := "death"


func _ready() -> void:
	z_index = 10

func _process(delta: float) -> void:
	var style = SettingsService.unit_visual_style if SettingsService else "classic"

	# Always advance animation time for procedural and sprite animations
	_animation_time += delta
	_anim_needs_redraw = false

	# Advance sprite animation frames if we have animated sprites
	if not _animations.is_empty() and _animations.has(_current_anim_name):
		var anim: SpriteAnimationData = _animations[_current_anim_name]
		if anim.advance(delta):
			_anim_needs_redraw = true

	# Determine if we need to redraw this frame
	var needs_redraw = false

	if style == "enhanced" and not debug_mode:
		# Enhanced mode always animates (procedural silhouettes or sprite frames)
		needs_redraw = true
	elif is_selected or is_hovered:
		# Selection/hover pulsing
		needs_redraw = true

	if needs_redraw:
		_pulse_time += delta
		queue_redraw()
	elif _anim_needs_redraw:
		queue_redraw()

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

	# Check style
	var style = SettingsService.unit_visual_style if SettingsService else "classic"

	if style == "enhanced" and not debug_mode:
		_draw_enhanced(fill_color, border_color)
	else:
		# Original rendering path for classic/style_a/style_b and debug mode
		var rot = model_data.get("rotation", 0.0)
		base_shape.draw(self, Vector2.ZERO, rot, fill_color, border_color, border_width)

		# Draw silhouette/glyph overlay based on setting
		if not debug_mode:
			_draw_overlay(fill_color, border_color)

		# Draw fought overlay and engaged indicator for classic styles too
		if not debug_mode:
			var bounds = base_shape.get_bounds()
			var classic_radius = min(bounds.size.x, bounds.size.y) / 2.0
			var classic_rot = model_data.get("rotation", 0.0)
			_draw_fought_overlay(classic_radius, base_shape.get_type(), classic_rot)
			_draw_engaged_overlay(classic_radius)

	# Draw model number with shadow for readability (all styles)
	_draw_model_number()

func _draw_enhanced(fill_color: Color, border_color: Color) -> void:
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	var rot = model_data.get("rotation", 0.0)
	var shape_type = base_shape.get_type()

	# --- Layer 1: Gradient base fill ---
	var dark_color: Color
	var light_color: Color
	if owner_player == 1:
		dark_color = Color(0.2, 0.25, 0.45, 1.0)
		light_color = Color(0.35, 0.4, 0.6, 1.0)
	else:
		dark_color = Color(0.5, 0.12, 0.1, 1.0)
		light_color = Color(0.65, 0.25, 0.2, 1.0)

	if shape_type == "circular":
		TokenDrawUtils.draw_gradient_circle(self, Vector2.ZERO, radius, dark_color)
	else:
		var poly_points = _get_shape_polygon(rot)
		TokenDrawUtils.draw_gradient_polygon(self, poly_points, dark_color)

	# --- Layer 2: Metallic base rim ---
	if shape_type == "circular":
		TokenDrawUtils.draw_metallic_rim(self, Vector2.ZERO, radius, border_color)
	else:
		var poly_points = _get_shape_polygon(rot)
		TokenDrawUtils.draw_metallic_rim_polygon(self, poly_points, border_color)

	# --- Layer 3: Faction-colored inner ring ---
	var faction_accent = _get_faction_accent_color()
	if shape_type == "circular":
		TokenDrawUtils.draw_faction_ring(self, Vector2.ZERO, radius, faction_accent)
	else:
		var poly_points = _get_shape_polygon(rot)
		TokenDrawUtils.draw_faction_ring_polygon(self, poly_points, faction_accent)

	# --- Layer 4: Animated sprite overlay or animated silhouette ---
	_draw_enhanced_overlay(radius, border_color)

	# --- Layer 5: Wound pips ---
	_draw_wound_pips(radius)

	# --- Layer 6: "Has fought" dimming overlay + checkmark ---
	_draw_fought_overlay(radius, shape_type, rot)

	# --- Layer 6b: "Engaged" crossed swords indicator ---
	_draw_engaged_overlay(radius)

	# --- Layer 7: Status indicator tick ---
	_draw_status_tick(radius)

	# --- Layer 8: Selection/hover pulsing ring ---
	if is_selected or is_hovered:
		_draw_selection_ring(radius)

func _draw_enhanced_overlay(radius: float, border_color: Color) -> void:
	if not has_meta("unit_id"):
		return

	var unit_type = _get_unit_type()
	var is_character = _is_character()

	# Try animated sprite resolution first, then static sprite
	if SpriteResolver and not _anim_resolved:
		_resolve_animated_sprite()
	if SpriteResolver and not _sprite_resolved:
		_resolve_sprite()

	# Priority 1: Animated sprite frames
	if not _animations.is_empty() and _animations.has(_current_anim_name):
		var anim: SpriteAnimationData = _animations[_current_anim_name]
		var tex = anim.get_current_texture()
		if tex:
			_draw_sprite_texture(tex, radius)
		else:
			_draw_animated_silhouette(radius, border_color, unit_type)
	# Priority 2: Static sprite texture
	elif _sprite_texture:
		_draw_sprite_texture(_sprite_texture, radius)
	# Priority 3: Animated procedural silhouettes (always available)
	else:
		_draw_animated_silhouette(radius, border_color, unit_type)

	# Character chevron (drawn above sprite or silhouette)
	if is_character:
		TokenDrawUtils.draw_leader_chevron(self, Vector2.ZERO, radius, _get_faction_accent_color())


func _draw_sprite_texture(tex: Texture2D, radius: float) -> void:
	# Draw a sprite texture overlay at 70% of base diameter
	var target_size = radius * 2.0 * 0.7
	var tex_size = tex.get_size()
	var scale_factor = target_size / max(tex_size.x, tex_size.y)
	var draw_size = tex_size * scale_factor
	var draw_rect_area = Rect2(-draw_size / 2.0, draw_size)
	draw_texture_rect(tex, draw_rect_area, false)


func _draw_animated_silhouette(radius: float, border_color: Color, unit_type: String) -> void:
	# Draw procedural silhouettes with animation
	var overlay_color = Color(border_color.r, border_color.g, border_color.b, 0.6)
	match unit_type:
		"VEHICLE":
			TokenDrawUtils.draw_vehicle_silhouette_animated(self, Vector2.ZERO, radius, overlay_color, _animation_time)
		"MONSTER":
			TokenDrawUtils.draw_monster_silhouette_animated(self, Vector2.ZERO, radius, overlay_color, _animation_time)
		_:
			TokenDrawUtils.draw_infantry_silhouette_animated(self, Vector2.ZERO, radius, overlay_color, _animation_time)


func _draw_wound_pips(radius: float) -> void:
	if not has_meta("unit_id") or not has_meta("model_id"):
		return

	var unit_id = get_meta("unit_id")
	var model_id_str = get_meta("model_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id_str:
			var total_wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", total_wounds)
			TokenDrawUtils.draw_wound_pips(self, Vector2.ZERO, radius, total_wounds, current_wounds)
			break

func _draw_fought_overlay(radius: float, shape_type: String, rot: float) -> void:
	if not has_meta("unit_id"):
		return
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	var flags = unit.get("flags", {})
	if not flags.get("has_fought", false):
		return
	var poly_points = PackedVector2Array()
	if shape_type != "circular":
		poly_points = _get_shape_polygon(rot)
	TokenDrawUtils.draw_fought_overlay(self, Vector2.ZERO, radius, shape_type, poly_points)

func _draw_engaged_overlay(radius: float) -> void:
	if not has_meta("unit_id"):
		return
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	var flags = unit.get("flags", {})
	if not flags.get("is_engaged", false):
		return
	# Don't show engaged indicator if unit has already fought (fought overlay takes priority)
	if flags.get("has_fought", false):
		return
	var fight_priority = flags.get("fight_priority", 1)
	TokenDrawUtils.draw_engaged_indicator(self, Vector2.ZERO, radius, fight_priority)

func _draw_status_tick(radius: float) -> void:
	if not has_meta("unit_id"):
		return

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var flags = unit.get("flags", {})
	TokenDrawUtils.draw_status_tick(self, Vector2.ZERO, radius, flags)

func _draw_selection_ring(radius: float) -> void:
	# Pulsing gold ring for selected/hovered state
	var pulse = (sin(_pulse_time * 4.0) + 1.0) / 2.0  # 0..1 oscillation
	var alpha: float
	var ring_color: Color

	if is_selected:
		alpha = 0.5 + pulse * 0.5  # 0.5..1.0
		ring_color = Color(1.0, 0.85, 0.2, alpha)  # Gold
	else:
		alpha = 0.3 + pulse * 0.3  # 0.3..0.6
		ring_color = Color(0.9, 0.9, 0.9, alpha)  # White-ish

	draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 48, ring_color, 2.5)

func _draw_model_number() -> void:
	var font = ThemeDB.fallback_font
	var text = str(model_number)
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)

	# Black shadow behind text
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.BLACK)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

func _resolve_sprite() -> void:
	_sprite_resolved = true
	if not has_meta("unit_id"):
		return

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", "")
	var faction = _get_faction_name()
	var unit_type = _get_unit_type()

	_sprite_texture = SpriteResolver.resolve_sprite(unit_name, faction, unit_type)


func _resolve_animated_sprite() -> void:
	_anim_resolved = true
	if not has_meta("unit_id"):
		return

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", "")
	var faction = _get_faction_name()
	var unit_type = _get_unit_type()

	_animations = SpriteResolver.resolve_animated_sprite(unit_name, faction, unit_type)
	if not _animations.is_empty():
		DebugLogger.info("[TokenVisual] Loaded %d animation(s) for unit %s: %s" % [_animations.size(), unit_id, ", ".join(_animations.keys())])
		# Start with idle animation if available, otherwise use the first one
		if _animations.has(ANIM_IDLE):
			_current_anim_name = ANIM_IDLE
		else:
			_current_anim_name = _animations.keys()[0]


func _get_shape_polygon(rot: float) -> PackedVector2Array:
	# Generate polygon points for the current base shape with rotation
	var shape_type = base_shape.get_type()
	var points = PackedVector2Array()

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
			points.append(base_shape.rotate_point(c, rot))
	elif shape_type == "oval":
		var oval_base = base_shape as OvalBase
		var segments = 32
		for i in range(segments):
			var angle = (float(i) / float(segments)) * TAU
			var local_point = Vector2(
				oval_base.length * cos(angle),
				oval_base.width * sin(angle)
			)
			points.append(base_shape.rotate_point(local_point, rot))
	else:
		# Fallback: generate circle points
		var circ = base_shape as CircularBase
		var r = circ.radius if circ else 20.0
		for i in range(32):
			var angle = (float(i) / 32.0) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * r)

	return points

func _get_faction_accent_color() -> Color:
	# Returns an accent color based on faction for the inner ring
	var faction = _get_faction_name().to_lower()

	if faction.find("custode") >= 0:
		return Color(0.85, 0.7, 0.2, 0.8)  # Auramite gold
	elif faction.find("space marine") >= 0 or faction.find("astartes") >= 0:
		return Color(0.75, 0.6, 0.3, 0.8)  # Imperial gold
	elif faction.find("ork") >= 0:
		return Color(0.6, 0.7, 0.3, 0.8)  # Ork green-yellow
	elif owner_player == 1:
		return Color(0.7, 0.55, 0.3, 0.7)  # Default P1 gold
	else:
		return Color(0.7, 0.5, 0.45, 0.7)  # Default P2 warm silver

func _is_character() -> bool:
	var unit_id = get_meta("unit_id") if has_meta("unit_id") else ""
	if unit_id == "":
		return false

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false

	var keywords = unit.get("meta", {}).get("keywords", [])
	for keyword in keywords:
		if str(keyword).to_upper() == "CHARACTER":
			return true
	return false

# --- Original overlay rendering (style_a, style_b, classic) ---

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

func set_selected(selected: bool) -> void:
	is_selected = selected
	if not selected:
		_pulse_time = 0.0
	queue_redraw()

func set_hovered(hovered: bool) -> void:
	is_hovered = hovered
	if not hovered:
		_pulse_time = 0.0
	queue_redraw()


# --- Animation control API ---
# Called by game phase controllers to trigger animation state changes.

func play_animation(anim_name: String) -> void:
	# Switch to a named animation. Falls back to idle if not found.
	if _animations.is_empty():
		# No sprite animations loaded - just track state for procedural animations
		_current_anim_name = anim_name
		return

	if _animations.has(anim_name):
		if _current_anim_name != anim_name:
			_current_anim_name = anim_name
			_animations[anim_name].reset()
	elif _animations.has(ANIM_IDLE):
		# Requested animation not available, fall back to idle
		if _current_anim_name != ANIM_IDLE:
			_current_anim_name = ANIM_IDLE
			_animations[ANIM_IDLE].reset()

	queue_redraw()


func get_current_animation() -> String:
	return _current_anim_name


func has_animation(anim_name: String) -> bool:
	return _animations.has(anim_name)
