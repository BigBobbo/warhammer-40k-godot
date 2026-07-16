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

# Built-in Kenney tank sprites drawn on VEHICLE tokens in letter mode
var _tank_resolved: bool = false
var _tank_body_tex: Texture2D = null
var _tank_barrel_tex: Texture2D = null

# Faction font cache (for letter mode)
var _faction_font: Font = null

# T09: per-phase exhaustion flag. When set, the token modulates to a dim
# grey to signal "has acted this phase". Cleared by PhaseManager.phase_changed.
var is_exhausted_this_phase: bool = false
const T09_EXHAUSTION_MODULATE := Color(0.6, 0.6, 0.6, 1.0)
const T09_NORMAL_MODULATE := Color(1.0, 1.0, 1.0, 1.0)

# Neutral base fill used in "ring" color-display mode (letter style). The unit's
# color is drawn only as a ring on top of this, so the base itself is a plain
# dark slate that keeps the model art and colored ring readable.
const LETTER_RING_BASE_FILL := Color(0.24, 0.24, 0.27, 1.0)

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
	# T16: add a child Label that shows the model identifier and is hidden
	# by t16_apply_zoom() when zoom falls below the threshold.
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = str(model_number)
	lbl.position = Vector2(-6, 12)  # under the base
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	lbl.add_theme_font_size_override("font_size", 10)
	add_child(lbl)
	# T15: silhouette child (procedural). Drawn first so rings render on top.
	var silhouette := _t15_make_silhouette()
	if silhouette != null:
		add_child(silhouette)
	# T09: reset exhaustion on phase boundary.
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.has_signal("phase_changed"):
		if not pm.is_connected("phase_changed", _t09_on_phase_changed):
			pm.connect("phase_changed", _t09_on_phase_changed)
	# Letter/classic styles only redraw on interaction, so without this hook a
	# style change in settings leaves every idle token rendering the old style.
	if SettingsService and SettingsService.has_signal("unit_style_changed"):
		if not SettingsService.is_connected("unit_style_changed", _on_unit_style_changed):
			SettingsService.connect("unit_style_changed", _on_unit_style_changed)
	# Toggling full-base vs ring color display must repaint idle tokens too.
	if SettingsService and SettingsService.has_signal("unit_color_display_changed"):
		if not SettingsService.is_connected("unit_color_display_changed", _on_unit_style_changed):
			SettingsService.connect("unit_color_display_changed", _on_unit_style_changed)
	# T08: two concentric rings expose faction vs player-slot color so
	# scenarios can assert per-ring modulate. FactionRing draws inner ring;
	# SlotRing draws a slightly larger thin outer ring. Both render on top
	# of the existing _draw() output but at very low alpha so they don't
	# visually compete with the established token aesthetic.
	var faction := _t08_make_ring("FactionRing", 1.0, 0.35, _t08_faction_color())
	add_child(faction)
	var slot := _t08_make_ring("SlotRing", 1.2, 0.7, _t08_slot_color())
	add_child(slot)


func _t09_on_phase_changed(_new_phase) -> void:
	if is_exhausted_this_phase:
		set_exhausted_this_phase(false)


func _on_unit_style_changed(_new_style: String) -> void:
	queue_redraw()


# T19: pulse the outer SlotRing's alpha between 0.7 and 1.0 to indicate the
# active actor. Looped at UIConstants.MOTION_PULSE_LOOP_S (2.0s).
var is_pulsing: bool = false
var _t19_tween: Tween = null


func start_pulse() -> void:
	if is_pulsing:
		return
	is_pulsing = true
	var slot = get_node_or_null("SlotRing")
	if slot == null:
		return
	var loop_s: float = 2.0
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null and "MOTION_PULSE_LOOP_S" in uic:
		loop_s = float(uic.MOTION_PULSE_LOOP_S)
	if _t19_tween != null and _t19_tween.is_valid():
		_t19_tween.kill()
	_t19_tween = create_tween()
	_t19_tween.set_loops()
	_t19_tween.tween_property(slot, "modulate:a", 1.0, loop_s * 0.5).from(0.7)
	_t19_tween.tween_property(slot, "modulate:a", 0.7, loop_s * 0.5)


func stop_pulse() -> void:
	is_pulsing = false
	if _t19_tween != null and _t19_tween.is_valid():
		_t19_tween.kill()
		_t19_tween = null
	var slot = get_node_or_null("SlotRing")
	if slot != null:
		var c: Color = slot.modulate
		c.a = 0.7
		slot.modulate = c


# T18: wound chip at base edge. wound_chip_text is "" for hidden, "W/Wmax"
# format otherwise. Multi-wound models call update_wound_chip(current, max);
# single-wound models call update_wound_chip(1, 1) which hides the chip.
var wound_chip_text: String = ""
var _t18_chip: Label = null


func _t18_ensure_chip() -> void:
	if _t18_chip != null:
		return
	_t18_chip = Label.new()
	_t18_chip.name = "WoundChip"
	_t18_chip.position = Vector2(10, 22)  # base edge, lower right
	_t18_chip.add_theme_font_size_override("font_size", 11)
	_t18_chip.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	_t18_chip.visible = false
	add_child(_t18_chip)


# T18: update the wound chip. Single-wound models hide it.
func update_wound_chip(current_wounds: int, max_wounds: int) -> void:
	_t18_ensure_chip()
	if max_wounds <= 1:
		wound_chip_text = ""
		_t18_chip.visible = false
		return
	wound_chip_text = "%d/%d" % [current_wounds, max_wounds]
	_t18_chip.text = wound_chip_text
	_t18_chip.visible = true


# T17: status icon slots (TL, TR, BR) + overflow chip (BL). Capped at 3
# visible icons; the rest are summarized in the chip "+N".
const T17_MAX_VISIBLE_ICONS := 3

var visible_status_icon_count: int = 0
var overflow_chip_count: int = 0
var _t17_slot_tl: Label = null
var _t17_slot_tr: Label = null
var _t17_slot_br: Label = null
var _t17_chip_bl: Label = null


func _t17_ensure_status_slots() -> void:
	if _t17_slot_tl != null:
		return
	var positions := {
		"StatusTL": Vector2(-18, -18),
		"StatusTR": Vector2(10, -18),
		"StatusBR": Vector2(10, 10),
		"OverflowChip": Vector2(-18, 10),
	}
	for slot_name in positions:
		var lbl := Label.new()
		lbl.name = slot_name
		lbl.position = positions[slot_name]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
		lbl.visible = false
		add_child(lbl)
		match slot_name:
			"StatusTL": _t17_slot_tl = lbl
			"StatusTR": _t17_slot_tr = lbl
			"StatusBR": _t17_slot_br = lbl
			"OverflowChip": _t17_chip_bl = lbl


# T17: replace the visible status set. The first three items in `statuses`
# occupy TL/TR/BR slots; the rest collapse into the BL "+N" overflow chip.
func set_active_statuses(statuses: Array) -> void:
	_t17_ensure_status_slots()
	var slots := [_t17_slot_tl, _t17_slot_tr, _t17_slot_br]
	visible_status_icon_count = 0
	for i in range(slots.size()):
		if i < statuses.size():
			slots[i].text = str(statuses[i])
			slots[i].visible = true
			visible_status_icon_count += 1
		else:
			slots[i].visible = false
	overflow_chip_count = max(0, statuses.size() - T17_MAX_VISIBLE_ICONS)
	if overflow_chip_count > 0:
		_t17_chip_bl.text = "+%d" % overflow_chip_count
		_t17_chip_bl.visible = true
	else:
		_t17_chip_bl.visible = false


# T16: hide the Label child if camera zoom < threshold. Caller (Main) walks
# all tokens on zoom change. Returns the resulting visibility.
const T16_ZOOM_HIDE_THRESHOLD := 0.6


func t16_apply_zoom(zoom: float) -> bool:
	var lbl = get_node_or_null("Label")
	if lbl == null:
		return false
	lbl.visible = zoom >= T16_ZOOM_HIDE_THRESHOLD
	return lbl.visible


# T09: set the per-phase exhaustion flag and refresh modulate.
func set_exhausted_this_phase(value: bool) -> void:
	is_exhausted_this_phase = value
	if value:
		modulate = T09_EXHAUSTION_MODULATE
	else:
		modulate = T09_NORMAL_MODULATE


# T08: live-rebind modulate when needed (called by external systems if
# faction or active player changes).
func t08_refresh_ring_colors() -> void:
	var faction = get_node_or_null("FactionRing")
	if faction != null:
		faction.modulate = _t08_faction_color()
	var slot = get_node_or_null("SlotRing")
	if slot != null:
		slot.modulate = _t08_slot_color()


# T15: procedural silhouette node. silhouette_category is one of
# {"infantry", "tank", "walker", "beast", "character", "aircraft", "mounted"}
# derived from the unit's keywords. The Sprite2D gets a small procedurally-
# generated ImageTexture so scenarios can assert texture != null without
# needing art assets to land first.
var silhouette_category: String = ""


func _t15_make_silhouette() -> Sprite2D:
	silhouette_category = _t15_category_from_keywords()
	if silhouette_category == "":
		return null
	var s := Sprite2D.new()
	s.name = "Silhouette"
	s.texture = _t15_make_silhouette_texture(silhouette_category)
	s.modulate = Color(1, 1, 1, 0.85)
	s.position = Vector2(0, 0)
	s.z_index = 1
	# The procedural silhouette is a placeholder that renders as a white shape
	# (a disc for infantry, etc.) at the model center. It exists purely so the
	# T15 scenario can assert the node/texture/category are wired up; it was
	# never meant to be a visible gameplay element. Keep the node (with its
	# texture + silhouette_category) for those assertions but don't render it,
	# so it no longer shows a white circle in the middle of every model.
	s.visible = false
	return s


func _t15_category_from_keywords() -> String:
	var keywords: Array = []
	if "model_data" in self and typeof(model_data) == TYPE_DICTIONARY:
		var raw = model_data.get("keywords", [])
		if typeof(raw) == TYPE_ARRAY:
			keywords = raw
	if keywords.is_empty():
		var gs = get_node_or_null("/root/GameState")
		if gs != null:
			# Walk all units to find one whose model contains this TokenVisual's
			# unit_id via meta lookup; cheap because TokenVisual.name is the unit_id.
			var uid: String = name
			var u = gs.get_unit(uid)
			if typeof(u) == TYPE_DICTIONARY:
				var k2 = u.get("meta", {}).get("keywords", [])
				if typeof(k2) == TYPE_ARRAY:
					keywords = k2
	var upper: Array = []
	for k in keywords:
		upper.append(str(k).to_upper())
	if upper.has("AIRCRAFT") or upper.has("FLY"):
		return "aircraft"
	if upper.has("VEHICLE"):
		return "tank"
	if upper.has("WALKER"):
		return "walker"
	if upper.has("MOUNTED") or upper.has("CAVALRY"):
		return "mounted"
	if upper.has("BEAST") or upper.has("MONSTER"):
		return "beast"
	if upper.has("CHARACTER"):
		return "character"
	if upper.has("INFANTRY"):
		return "infantry"
	return "infantry"  # default; non-empty so Silhouette is added


func _t15_make_silhouette_texture(category: String) -> ImageTexture:
	# 32x32 white-on-transparent shape; modulate handles color tinting.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match category:
		"infantry":
			_t15_fill_disc(img, Vector2i(16, 16), 8)
		"character":
			_t15_fill_disc(img, Vector2i(16, 12), 5)
			_t15_fill_rect(img, Rect2i(11, 16, 10, 12))
		"tank":
			_t15_fill_rect(img, Rect2i(6, 10, 20, 12))
		"walker":
			# Triangle pointing up
			for y in range(8, 28):
				var width: int = (y - 8)
				_t15_fill_rect(img, Rect2i(16 - width / 2, y, max(1, width), 1))
		"beast":
			_t15_fill_disc(img, Vector2i(16, 18), 10)
		"aircraft":
			_t15_fill_rect(img, Rect2i(4, 14, 24, 4))
			_t15_fill_rect(img, Rect2i(14, 6, 4, 20))
		"mounted":
			_t15_fill_disc(img, Vector2i(12, 18), 6)
			_t15_fill_disc(img, Vector2i(22, 14), 5)
		_:
			_t15_fill_disc(img, Vector2i(16, 16), 8)
	return ImageTexture.create_from_image(img)


func _t15_fill_disc(img: Image, center: Vector2i, radius: int) -> void:
	var sz: Vector2i = img.get_size()
	for y in range(max(0, center.y - radius), min(sz.y, center.y + radius + 1)):
		for x in range(max(0, center.x - radius), min(sz.x, center.x + radius + 1)):
			var dx: int = x - center.x
			var dy: int = y - center.y
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, Color(1, 1, 1, 1))


func _t15_fill_rect(img: Image, rect: Rect2i) -> void:
	var sz: Vector2i = img.get_size()
	for y in range(max(0, rect.position.y), min(sz.y, rect.position.y + rect.size.y)):
		for x in range(max(0, rect.position.x), min(sz.x, rect.position.x + rect.size.x)):
			img.set_pixel(x, y, Color(1, 1, 1, 1))


func _t08_make_ring(node_name: String, scale_factor: float, alpha: float, ring_color: Color) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.scale = Vector2(scale_factor, scale_factor)
	var c := ring_color
	c.a = alpha
	n.modulate = c
	return n


func _t08_faction_color() -> Color:
	# T41: route through UIConstants.faction_color_for_player so every
	# caller of "faction color" goes through one path.
	var uic = get_node_or_null("/root/UIConstants")
	if uic != null and uic.has_method("faction_color_for_player"):
		return uic.faction_color_for_player(owner_player)
	# Final fallback (matches UIConstants's own fallback).
	if owner_player == 1:
		return Color(0.83, 0.59, 0.38, 1.0)
	return Color(0.85, 0.8, 0.65, 1.0)


func _t08_slot_color() -> Color:
	var uic = get_node_or_null("/root/UIConstants")
	if uic == null:
		return Color(1, 1, 1, 1)
	if owner_player == 1:
		return uic.FRIENDLY_PLAYER_TEAL
	return uic.ENEMY_PLAYER_MAGENTA

func _process(delta: float) -> void:
	# T-095 ghost pulse: redraw is_preview tokens every frame so the pulse animates.
	if is_preview:
		_pulse_time += delta
		queue_redraw()

	var style = SettingsService.unit_visual_style if SettingsService else "classic"

	# Letter mode doesn't need continuous redraw (no animations)
	if style == "letter" and not debug_mode:
		if is_selected or is_hovered:
			_pulse_time += delta
			queue_redraw()
		return

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

	var use_retro = SettingsService.retro_mode if SettingsService else false
	if (use_retro and not debug_mode) or (style == "enhanced" and not debug_mode):
		# Retro and enhanced modes always animate (procedural pixel art or silhouettes)
		needs_redraw = true
	elif is_selected or is_hovered:
		# Selection/hover pulsing
		needs_redraw = true
	elif _has_marked_for_death_flag():
		# Marked for Death pulsing indicator
		needs_redraw = true
	elif _has_beacon_flag():
		# Beacon designation pulsing indicator
		needs_redraw = true
	elif _has_performed_action_flag():
		# Secondary action pulsing indicator
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

	# Check style and retro mode
	var style = SettingsService.unit_visual_style if SettingsService else "classic"
	var use_retro = SettingsService.retro_mode if SettingsService else false

	if style == "letter" and not debug_mode:
		_draw_letter_mode()
		_draw_battle_shock_indicator()  # T-096: also show in letter mode
		_draw_colorblind_shape_badge()  # T-097: colorblind-friendly shape badge
		return

	if use_retro and not debug_mode:
		# Retro pixel art rendering - replaces entire visual with pixel art sprites
		_draw_retro(fill_color, border_color)
	elif style == "enhanced" and not debug_mode:
		_draw_enhanced(fill_color, border_color)
	else:
		# Original rendering path for classic/style_a/style_b and debug mode
		var rot = model_data.get("rotation", 0.0)
		base_shape.draw(self, Vector2.ZERO, rot, fill_color, border_color, border_width)

		# Draw silhouette/glyph overlay based on setting
		if not debug_mode:
			_draw_overlay(fill_color, border_color)

		# Draw health bar and overlays for classic styles too
		if not debug_mode:
			var bounds = base_shape.get_bounds()
			var classic_radius = min(bounds.size.x, bounds.size.y) / 2.0
			var classic_rot = model_data.get("rotation", 0.0)
			_draw_health_bar(classic_radius)
			_draw_fought_overlay(classic_radius, base_shape.get_type(), classic_rot)
			_draw_engaged_overlay(classic_radius)
			_draw_marked_for_death_indicator(classic_radius)
			_draw_beacon_indicator(classic_radius)
			_draw_action_overlay(classic_radius)

	# MA-20: Draw model type colored ring (all styles except letter which handles it separately)
	if not debug_mode and style != "letter":
		var bounds_for_ring = base_shape.get_bounds()
		var ring_radius = min(bounds_for_ring.size.x, bounds_for_ring.size.y) / 2.0
		_draw_model_type_ring(ring_radius)

	# Draw model number with shadow for readability (all styles)
	_draw_model_number()

	# Draw unit name label beneath the token base
	_draw_unit_name_label()

	# T-096: Battle-shock indicator (red ring + "!" if unit is battle-shocked)
	_draw_battle_shock_indicator()

	# T-095: Edge color border for preview tokens (deployment selection)
	_draw_preview_edge_border()

	# T-097: Colorblind shape badge — when colorblind_mode != "none",
	# draw a per-player distinguishing shape (triangle = P1, square = P2)
	# at the lower-right of the base so ownership reads without relying on color.
	_draw_colorblind_shape_badge()

	# T-101: Damaged-model art — overlay scorch/crack lines when wounded.
	if not debug_mode:
		var dmg_bounds = base_shape.get_bounds()
		var dmg_radius = min(dmg_bounds.size.x, dmg_bounds.size.y) / 2.0
		_draw_damage_overlay(dmg_radius)

func _draw_enhanced(fill_color: Color, border_color: Color) -> void:
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	var rot = model_data.get("rotation", 0.0)
	var shape_type = base_shape.get_type()
	var use_retro = SettingsService.retro_mode if SettingsService else false

	if use_retro:
		# --- Retro mode: flat base + top-down pixel art (Hotline Miami style) ---
		# Faction-tinted base (orks green, custodes gold) instead of player slot color.
		var base_color: Color = _get_faction_primary_color().darkened(0.55)
		base_color.a = 1.0

		# Simple flat circle base
		if shape_type == "circular":
			draw_circle(Vector2.ZERO, radius, base_color)
			# Thin 1px border
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, border_color.darkened(0.3), 1.5)
		else:
			var poly_points = _get_shape_polygon(rot)
			draw_colored_polygon(poly_points, base_color)
			var closed = PackedVector2Array()
			for p in poly_points:
				closed.append(p)
			closed.append(poly_points[0])
			draw_polyline(closed, border_color.darkened(0.3), 1.5)

		# Draw top-down pixel art as the primary visual
		_draw_retro_pixel_art(radius, border_color)
	else:
		# --- Standard enhanced mode: gradient base + metallic rim ---
		# Base gradient derives from the faction's primary color (orks green,
		# custodes gold, ...) with the player slot color only as fallback.
		var primary := _get_faction_primary_color()
		var dark_color := primary.darkened(0.45)
		dark_color.a = 1.0
		var light_color := primary.lightened(0.1)
		light_color.a = 1.0

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

	# --- Shared layers (both retro and standard) ---

	# --- Layer 5: Wound pips ---
	_draw_wound_pips(radius)

	# --- Layer 5b: Persistent health bar above base ---
	_draw_health_bar(radius)

	# --- Layer 6: "Has fought" dimming overlay + checkmark ---
	_draw_fought_overlay(radius, shape_type, rot)

	# --- Layer 6b: "Engaged" crossed swords indicator ---
	_draw_engaged_overlay(radius)

	# --- Layer 7: Status indicator tick ---
	_draw_status_tick(radius)

	# --- Layer 7b: Marked for Death target indicator ---
	_draw_marked_for_death_indicator(radius)

	# --- Layer 7b2: Beacon designation indicator (11e secondary) ---
	_draw_beacon_indicator(radius)

	# --- Layer 7c: Secondary action indicator ---
	_draw_action_overlay(radius)

	# --- Layer 8: Selection/hover pulsing ring ---
	if is_selected or is_hovered:
		_draw_selection_ring(radius)

func _draw_retro(fill_color: Color, border_color: Color) -> void:
	# Full retro pixel art rendering path - replaces the entire token visual.
	# Draws: flat base -> pixel art sprite (primary visual) -> minimal overlays
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	var rot = model_data.get("rotation", 0.0)
	var shape_type = base_shape.get_type()

	# --- Layer 1: Simple flat base (no gradient, no metallic rim) ---
	var base_color = fill_color
	base_color.a = 1.0
	if shape_type == "circular":
		draw_circle(Vector2.ZERO, radius, Color(0.08, 0.08, 0.08, 1.0))  # Dark background
		draw_circle(Vector2.ZERO, radius - 1.5, base_color.darkened(0.5))  # Flat fill
	else:
		var poly_points = _get_shape_polygon(rot)
		draw_colored_polygon(poly_points, Color(0.08, 0.08, 0.08, 1.0))
		var center = Vector2.ZERO
		var inset_points = PackedVector2Array()
		for p in poly_points:
			inset_points.append(center + (p - center) * 0.95)
		draw_colored_polygon(inset_points, base_color.darkened(0.5))

	# --- Layer 2: Thin pixel-style border ---
	if shape_type == "circular":
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, border_color, 2.0)
	else:
		var poly_points = _get_shape_polygon(rot)
		poly_points.append(poly_points[0])
		draw_polyline(poly_points, border_color, 2.0)

	# --- Layer 3: Pixel art sprite (PRIMARY visual) ---
	var unit_type = _get_unit_type()
	var armor_color = fill_color
	armor_color.a = 1.0
	var accent_color = _get_faction_accent_color()

	match unit_type:
		"VEHICLE":
			TokenDrawUtils.draw_retro_vehicle(self, Vector2.ZERO, radius, armor_color, accent_color, _animation_time)
		"MONSTER":
			TokenDrawUtils.draw_retro_monster(self, Vector2.ZERO, radius, armor_color, accent_color, _animation_time)
		_:
			TokenDrawUtils.draw_retro_infantry(self, Vector2.ZERO, radius, armor_color, accent_color, _animation_time)

	# --- Layer 4: Pixel-art health bar ---
	if has_meta("unit_id") and has_meta("model_id"):
		var unit_id = get_meta("unit_id")
		var model_id_str = get_meta("model_id")
		var unit = GameState.get_unit(unit_id)
		if not unit.is_empty():
			var models = unit.get("models", [])
			for model in models:
				if model.get("id", "") == model_id_str:
					var total_wounds = model.get("wounds", 1)
					var current_wounds = model.get("current_wounds", total_wounds)
					TokenDrawUtils.draw_retro_health_bar(self, Vector2.ZERO, radius, total_wounds, current_wounds)
					break

	# --- Layer 5: Fought/engaged overlays (kept for gameplay clarity) ---
	_draw_fought_overlay(radius, shape_type, rot)
	_draw_engaged_overlay(radius)

	# --- Layer 6: Selection ring (kept but simpler) ---
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


# --- Letter-mode rendering ---

func _get_faction_font() -> Font:
	if _faction_font != null:
		return _faction_font
	var faction = _get_faction_name()
	if faction != "":
		_faction_font = FactionPalettes.get_faction_font(faction)
	else:
		_faction_font = FactionPalettes.FONT_CASLON
	return _faction_font

func _draw_letter_mode() -> void:
	var bounds = base_shape.get_bounds()
	var radius = min(bounds.size.x, bounds.size.y) / 2.0
	var rot = model_data.get("rotation", 0.0)
	var shape_type = base_shape.get_type()

	# Get unit color (auto-assign if not yet set)
	var token_color = _get_token_color()
	# In "ring" color mode the base stays a neutral color and token_color is drawn
	# only as a ring inside the perimeter (see Layer 3c); in "full" mode the whole
	# base is filled with token_color as before.
	var ring_mode = _is_ring_color_mode()
	var base_fill = LETTER_RING_BASE_FILL if ring_mode else token_color
	var border_shade = Color(base_fill.r * 0.6, base_fill.g * 0.6, base_fill.b * 0.6)

	# --- Layer 1: Solid fill ---
	if shape_type == "circular":
		draw_circle(Vector2.ZERO, radius, base_fill)
	else:
		var poly_points = _get_shape_polygon(rot)
		draw_colored_polygon(poly_points, base_fill)

	# --- Layer 2: Thin darker border ---
	if shape_type == "circular":
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, border_shade, 2.0)
	else:
		var poly_points = _get_shape_polygon(rot)
		for i in range(poly_points.size()):
			var from = poly_points[i]
			var to = poly_points[(i + 1) % poly_points.size()]
			draw_line(from, to, border_shade, 2.0)

	# --- Layer 2c: Unit color ring (ring color mode) ---
	# Drawn BELOW the model art (Layer 3) so the sprite/letter renders on top of
	# the squad-identifying color band rather than being obscured by it (a thick
	# ring over e.g. the Stompa sprite looked wrong). The ring still reads clearly
	# because it hugs the base perimeter, where top-down art is mostly transparent.
	if ring_mode:
		_draw_unit_color_ring(radius, token_color, shape_type, rot)

	# --- Layer 3: Top-down unit art, vehicle tank sprite, or letter label ---
	# Units with dedicated top-down art (bundled or user drop-in, resolved by
	# SpriteResolver) render that; VEHICLE tokens without dedicated art fall
	# back to the generic tank sprite (faction colorway); everything else
	# keeps the Vassal-style letter counter.
	if _get_unit_sprite_texture() != null:
		_draw_unit_sprite(rot)
	elif _get_tank_body_texture() != null:
		_draw_tank_sprite(rot)
	else:
		var label = _get_letter_label()
		if label != "":
			var text_color = FactionPalettes.get_contrast_text_color(base_fill)
			var font = _get_faction_font()
			# Font size ~60% of base diameter, smaller for multi-char labels
			var base_font_size = int(radius * 1.2)
			var font_size = base_font_size if label.length() <= 2 else int(base_font_size * 0.65)
			var text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = Vector2(-text_size.x / 2.0, text_size.y / 4.0)

			# Faux-bold: draw 3x with sub-pixel offsets
			for offset in [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, 0)]:
				draw_string(font, text_pos + offset, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

	# --- Layer 3b: MA-20 model type colored ring ---
	_draw_model_type_ring(radius)

	# --- Layer 4: Model number or type label (only on select/hover) ---
	if is_selected or is_hovered:
		var num_font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
		# MA-20: Show model type short label instead of model number when available
		var type_label = _get_model_type_short_label()
		var num_text = type_label if type_label != "" else str(model_number)
		var num_size = 10
		var num_text_size = num_font.get_string_size(num_text, HORIZONTAL_ALIGNMENT_CENTER, -1, num_size)
		var num_pos = Vector2(-num_text_size.x / 2.0, radius - 2)
		# Use model type color if available
		var num_color = Color.WHITE
		var ring_col = _get_model_type_ring_color()
		if ring_col != Color.TRANSPARENT:
			num_color = Color(ring_col.r, ring_col.g, ring_col.b, 1.0).lightened(0.3)
		draw_string(num_font, num_pos + Vector2(0.5, 0.5), num_text, HORIZONTAL_ALIGNMENT_CENTER, -1, num_size, Color(0, 0, 0, 0.6))
		draw_string(num_font, num_pos, num_text, HORIZONTAL_ALIGNMENT_CENTER, -1, num_size, num_color)

	# --- Layer 5: Reuse existing overlays ---
	_draw_wound_pips(radius)
	_draw_health_bar(radius)
	_draw_fought_overlay(radius, shape_type, rot)
	_draw_engaged_overlay(radius)
	_draw_status_tick(radius)
	_draw_action_overlay(radius)

	# --- Layer 6: Selection/hover pulsing ring ---
	if is_selected or is_hovered:
		_draw_selection_ring(radius)

	# --- Layer 7: Unit name label beneath base ---
	_draw_unit_name_label()


func _get_token_color() -> Color:
	if not has_meta("unit_id"):
		# Fallback based on player
		if owner_player == 1:
			return Color(0.2, 0.35, 0.6)
		else:
			return Color(0.6, 0.2, 0.15)

	var unit_id = get_meta("unit_id")
	var color = GameState.get_unit_color(unit_id)
	if color == Color.TRANSPARENT:
		color = GameState.auto_assign_unit_color(unit_id)
	return color


func _is_ring_color_mode() -> bool:
	# The color is shown as a ring (neutral base) rather than filling the base.
	return SettingsService != null and SettingsService.unit_color_display_mode == "ring"


func _draw_unit_color_ring(radius: float, ring_color: Color, shape_type: String, rot: float) -> void:
	# Draw the unit's color as a band just inside the base perimeter, following
	# the base shape. Width scales with base size but stays legible on tiny bases.
	var ring_width: float = max(3.5, radius * 0.18)
	var c := ring_color
	c.a = 1.0
	if shape_type == "circular":
		# Centre the band so its outer edge sits ~1px inside the base border.
		var r: float = radius - ring_width * 0.5 - 1.0
		if r <= 0.0:
			r = radius * 0.5
		draw_arc(Vector2.ZERO, r, 0, TAU, 48, c, ring_width)
	else:
		var pts := _get_shape_polygon(rot)
		var inset: float = ring_width * 0.5 + 1.0
		var ring_pts := PackedVector2Array()
		for p in pts:
			var l: float = p.length()
			if l > inset:
				ring_pts.append(p * ((l - inset) / l))
			else:
				ring_pts.append(p)
		if ring_pts.size() > 0:
			ring_pts.append(ring_pts[0])
			draw_polyline(ring_pts, c, ring_width)


func _get_letter_label() -> String:
	if not has_meta("unit_id"):
		return "?"

	var unit_id = get_meta("unit_id")

	# Check for custom label override
	var custom = GameState.get_unit_label(unit_id)
	if custom != "":
		return custom

	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return "?"

	var unit_name = unit.get("meta", {}).get("name", "?")
	var unit_type = _get_unit_type()

	# Vehicles/monsters get first word (abbreviated if long)
	if unit_type == "VEHICLE" or unit_type == "MONSTER":
		var words = unit_name.split(" ")
		if words.size() > 0:
			var first_word = words[0]
			return first_word.substr(0, min(first_word.length(), 5))

	# Characters: show first 2-3 chars of first word for better ID
	if _is_character():
		var words = unit_name.split(" ")
		var first_word = words[0] if words.size() > 0 else unit_name
		if first_word.length() <= 4:
			return first_word
		return first_word.substr(0, 3)

	# Mixed composition units get abbreviation + asterisk
	var composition = unit.get("meta", {}).get("unit_composition", [])
	if composition.size() > 1:
		return unit_name.substr(0, 2).to_upper() + "*"

	# Default: first 2 chars for better identification
	return unit_name.substr(0, 2)

func _draw_retro_pixel_art(radius: float, border_color: Color) -> void:
	# Retro mode: draw top-down pixel art as the primary unit visual (Hotline Miami style)
	var unit_type = "INFANTRY"
	if has_meta("unit_id"):
		unit_type = _get_unit_type()

	# Use faction-tinted color for the pixel art (player slot color as fallback)
	var pixel_color: Color = _get_faction_primary_color().lightened(0.2)
	pixel_color.a = 1.0
	var accent = _get_faction_accent_color()
	accent.a = 1.0

	match unit_type:
		"VEHICLE":
			TokenDrawUtils.draw_vehicle_topdown(self, Vector2.ZERO, radius, pixel_color, accent, _animation_time)
		"MONSTER":
			TokenDrawUtils.draw_monster_topdown(self, Vector2.ZERO, radius, pixel_color, accent, _animation_time)
		_:
			TokenDrawUtils.draw_infantry_topdown(self, Vector2.ZERO, radius, pixel_color, accent, _animation_time)

	# Character chevron
	if has_meta("unit_id") and _is_character():
		TokenDrawUtils.draw_leader_chevron(self, Vector2.ZERO, radius, accent)


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
	var use_retro = SettingsService.retro_mode if SettingsService else false

	if use_retro:
		# Top-down pixel art retro silhouettes (Hotline Miami style)
		var accent = _get_faction_accent_color()
		accent.a = 1.0
		match unit_type:
			"VEHICLE":
				TokenDrawUtils.draw_vehicle_topdown(self, Vector2.ZERO, radius, overlay_color, accent, _animation_time)
			"MONSTER":
				TokenDrawUtils.draw_monster_topdown(self, Vector2.ZERO, radius, overlay_color, accent, _animation_time)
			_:
				TokenDrawUtils.draw_infantry_topdown(self, Vector2.ZERO, radius, overlay_color, accent, _animation_time)
	else:
		# Standard smooth silhouettes
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

func _draw_health_bar(radius: float) -> void:
	if not has_meta("unit_id") or not has_meta("model_id"):
		return

	var unit_id = get_meta("unit_id")
	var model_id_str = get_meta("model_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var is_char = _is_character()
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id_str:
			var total_wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", total_wounds)
			TokenDrawUtils.draw_health_bar(self, Vector2.ZERO, radius, total_wounds, current_wounds, is_char)
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

func _draw_marked_for_death_indicator(radius: float) -> void:
	if not has_meta("unit_id"):
		return
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	var mfd_type = unit.get("flags", {}).get("marked_for_death", "")
	if mfd_type == "":
		return

	# Draw a distinct crosshair/target indicator
	var pulse = (sin(_pulse_time * 3.0) + 1.0) / 2.0  # 0..1 oscillation
	var indicator_radius = radius + 6.0

	if mfd_type == "alpha":
		# Alpha targets: red crosshair ring with "A" label
		var alpha_val = 0.5 + pulse * 0.3
		var ring_color = Color(1.0, 0.2, 0.2, alpha_val)
		draw_arc(Vector2.ZERO, indicator_radius, 0, TAU, 48, ring_color, 2.0)
		# Inner crosshair lines
		var cross_len = indicator_radius * 0.4
		draw_line(Vector2(-cross_len, 0), Vector2(cross_len, 0), ring_color, 1.5)
		draw_line(Vector2(0, -cross_len), Vector2(0, cross_len), ring_color, 1.5)
		# "A" label top-right
		var font = ThemeDB.fallback_font
		if font:
			var label_pos = Vector2(indicator_radius * 0.6, -indicator_radius * 0.6)
			draw_string(font, label_pos + Vector2(1, 1), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
			draw_string(font, label_pos, "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.3))
	elif mfd_type == "gamma":
		# Gamma targets: orange/yellow dashed ring with "G" label
		var alpha_val = 0.4 + pulse * 0.3
		var ring_color = Color(1.0, 0.7, 0.1, alpha_val)
		# Draw dashed ring (segments)
		var segments = 12
		for i in range(segments):
			if i % 2 == 0:
				var start_angle = TAU * i / segments
				var end_angle = TAU * (i + 1) / segments
				draw_arc(Vector2.ZERO, indicator_radius, start_angle, end_angle, 8, ring_color, 2.0)
		# "G" label top-right
		var font = ThemeDB.fallback_font
		if font:
			var label_pos = Vector2(indicator_radius * 0.6, -indicator_radius * 0.6)
			draw_string(font, label_pos + Vector2(1, 1), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
			draw_string(font, label_pos, "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.8, 0.2))

func _draw_beacon_indicator(radius: float) -> void:
	"""11e Beacon secondary: cyan pulsing ring + 'B' label on the designated unit."""
	if not has_meta("unit_id"):
		return
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	if not unit.get("flags", {}).get("beacon", false):
		return

	var pulse = (sin(_pulse_time * 3.0) + 1.0) / 2.0
	var indicator_radius = radius + 6.0
	var alpha_val = 0.45 + pulse * 0.35
	var ring_color = Color(0.2, 0.9, 1.0, alpha_val)
	draw_arc(Vector2.ZERO, indicator_radius, 0, TAU, 48, ring_color, 2.0)
	# Rotating "signal" dot on the ring for a beacon feel
	var dot_angle = fmod(_pulse_time * 2.0, TAU)
	var dot_pos = Vector2(cos(dot_angle), sin(dot_angle)) * indicator_radius
	draw_circle(dot_pos, 3.0, ring_color)
	var font = ThemeDB.fallback_font
	if font:
		var label_pos = Vector2(indicator_radius * 0.6, -indicator_radius * 0.6)
		draw_string(font, label_pos + Vector2(1, 1), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
		draw_string(font, label_pos, "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.95, 1.0))

func _has_beacon_flag() -> bool:
	if not has_meta("unit_id"):
		return false
	var unit = GameState.get_unit(get_meta("unit_id"))
	return not unit.is_empty() and unit.get("flags", {}).get("beacon", false)

func _draw_selection_ring(radius: float) -> void:
	var pulse = (sin(_pulse_time * 4.0) + 1.0) / 2.0
	var alpha: float
	var ring_color: Color
	var base_color = FactionPalettes.get_player_border_color(owner_player)

	if is_selected:
		alpha = 0.6 + pulse * 0.4
		ring_color = Color(base_color.r, base_color.g, base_color.b, alpha).lightened(0.3)
	else:
		alpha = 0.3 + pulse * 0.3
		ring_color = Color(0.9, 0.9, 0.9, alpha)

	draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 48, ring_color, 3.0)

func _draw_model_number() -> void:
	var font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	# MA-20: Show model type short label instead of model number when model_profiles exist
	var type_label = _get_model_type_short_label()
	var text = type_label if type_label != "" else str(model_number)
	var font_size = 16
	# Slightly smaller font for multi-character type labels
	if text.length() > 1 and type_label != "":
		font_size = 13
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)

	# MA-20: Use model type color for the text when available, white otherwise
	var text_color = Color.WHITE
	var ring_color = _get_model_type_ring_color()
	if ring_color != Color.TRANSPARENT:
		# Use a bright version of the ring color for the label text
		text_color = Color(ring_color.r, ring_color.g, ring_color.b, 1.0).lightened(0.3)

	# Black shadow behind text
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

# --- MA-20: Model type helpers ---

# Predefined distinct colors for model type rings (up to 6 types)
const MODEL_TYPE_COLORS = [
	Color(0.2, 0.8, 0.3, 0.85),   # Green
	Color(0.3, 0.5, 1.0, 0.85),   # Blue
	Color(1.0, 0.55, 0.1, 0.85),  # Orange
	Color(0.8, 0.3, 0.8, 0.85),   # Purple
	Color(1.0, 0.85, 0.1, 0.85),  # Yellow
	Color(0.1, 0.85, 0.85, 0.85), # Cyan
]

func _get_model_type_short_label() -> String:
	"""MA-20: Get a short label for this model's type (e.g., 'D' for Deffgun, 'S' for Spanner).
	Returns '' if no model_profiles exist (backward compat)."""
	if not has_meta("unit_id"):
		return ""

	var model_type = model_data.get("model_type", "")
	if model_type == "" or model_type == null:
		return ""

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return ""

	var profiles = unit.get("meta", {}).get("model_profiles", {})
	if profiles.is_empty():
		return ""

	var profile = profiles.get(model_type, {})
	if profile.is_empty():
		return ""

	# Check for explicit short_label override in profile
	var short_label = profile.get("short_label", "")
	if short_label != "":
		return short_label

	# Auto-generate from the label
	var label = profile.get("label", "")
	if label == "":
		return model_type.substr(0, 1).to_upper()

	# If label has parenthesized content like "Loota (Deffgun)", use first letter inside parens
	var paren_start = label.find("(")
	var paren_end = label.find(")")
	if paren_start >= 0 and paren_end > paren_start + 1:
		var paren_content = label.substr(paren_start + 1, paren_end - paren_start - 1).strip_edges()
		return paren_content.substr(0, 1).to_upper()

	# Otherwise use first letter of the label
	return label.substr(0, 1).to_upper()


func _get_model_type_ring_color() -> Color:
	"""MA-20: Get a distinct color for this model's type for the colored ring indicator.
	Returns Color.TRANSPARENT if no model_profiles or only 1 profile type."""
	if not has_meta("unit_id"):
		return Color.TRANSPARENT

	var model_type = model_data.get("model_type", "")
	if model_type == "" or model_type == null:
		return Color.TRANSPARENT

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return Color.TRANSPARENT

	var profiles = unit.get("meta", {}).get("model_profiles", {})
	if profiles.size() <= 1:
		# No need for color distinction with 0 or 1 profile type
		return Color.TRANSPARENT

	# Find the index of this model_type among sorted profile keys for deterministic color
	var profile_keys = profiles.keys()
	profile_keys.sort()
	var type_index = profile_keys.find(model_type)
	if type_index < 0:
		return Color.TRANSPARENT

	return MODEL_TYPE_COLORS[type_index % MODEL_TYPE_COLORS.size()]


func _draw_model_type_ring(radius: float) -> void:
	"""MA-20: Draw a colored ring around the base to indicate model type."""
	var ring_color = _get_model_type_ring_color()
	if ring_color == Color.TRANSPARENT:
		return

	# Draw a thin colored ring just inside the base border
	var ring_radius = radius - 1.5
	draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 48, ring_color, 2.0)


# Max characters shown for a unit's on-board name label before it is elided.
# Chosen so a base name plus a Greek-letter suffix (e.g. "Custodian Guard
# Epsilon", 23 chars) still fits without truncation.
const UNIT_LABEL_MAX_CHARS := 24


func _compact_unit_name(display_name: String) -> String:
	# Shorten an over-long unit name for the on-board label WITHOUT dropping the
	# trailing disambiguator. ArmyListManager appends a Greek-letter suffix
	# ("Alpha", "Delta", …) to duplicate squads so the player can tell them
	# apart, and that suffix sits at the END of display_name. The old
	# tail-truncation ("Custodian Guard Alpha" -> "Custodian Guard ..") chopped
	# exactly that suffix off, collapsing every duplicate to an identical label.
	# Instead, keep the suffix intact and elide the middle of the base name.
	if display_name.length() <= UNIT_LABEL_MAX_CHARS:
		return display_name
	var space := display_name.rfind(" ")
	if space > 0:
		var suffix := display_name.substr(space + 1)
		# Reserve room for the head + ".." joiner + the space before the suffix.
		var head_room := UNIT_LABEL_MAX_CHARS - suffix.length() - 3
		if suffix.length() > 0 and head_room >= 3:
			return display_name.substr(0, head_room).strip_edges() + ".. " + suffix
	# Single word, or an unusually long trailing word: fall back to plain
	# tail truncation.
	return display_name.substr(0, UNIT_LABEL_MAX_CHARS - 2) + ".."


func _draw_unit_name_label() -> void:
	if SettingsService and not SettingsService.show_unit_labels:
		return
	if not has_meta("unit_id"):
		return

	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return

	# One name plate per UNIT, not per model: drawing it under all 11 gretchin
	# produces an unreadable smear of repeated text. Only the unit's first
	# alive model carries the plate (it migrates as casualties are removed).
	if not _is_unit_label_anchor(unit):
		return

	# Prefer display_name (includes Greek suffix for duplicates) over raw name
	var meta = unit.get("meta", {})
	var unit_name = meta.get("display_name", meta.get("name", ""))
	if unit_name == "":
		return

	# Shorten long names to keep the label compact, but keep the disambiguating
	# suffix (e.g. "Alpha"/"Delta") visible so duplicate squads stay tellable
	# apart. See _compact_unit_name().
	unit_name = _compact_unit_name(unit_name)

	var font = _get_faction_font()
	var font_size = 11
	var bounds = base_shape.get_bounds()
	var base_radius = min(bounds.size.x, bounds.size.y) / 2.0

	# Position label just below the token base
	var text_size = font.get_string_size(unit_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var label_y = base_radius + font_size + 3
	var text_pos = Vector2(-text_size.x / 2.0, label_y)

	# Add model count badge for multi-model units
	var count_text = ""
	var models = unit.get("models", [])
	var total = models.size()
	if total > 1:
		var alive = 0
		for m in models:
			if m.get("current_wounds", 1) > 0:
				alive += 1
		count_text = "%d/%d" % [alive, total]

	# Build combined label
	var display = unit_name
	if count_text != "":
		display = "%s [%s]" % [unit_name, count_text]

	var combined_size = font.get_string_size(display, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var combined_pos = Vector2(-combined_size.x / 2.0, label_y)

	# Draw text with faction-appropriate color
	var label_color = _get_faction_accent_color()
	label_color.a = 0.9

	# Draw background pill for readability
	var bg_rect = Rect2(combined_pos.x - 4, combined_pos.y - font_size, combined_size.x + 8, font_size + 5)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.8), true)
	draw_rect(bg_rect, Color(label_color, 0.3), false, 1.0)
	draw_string(font, combined_pos + Vector2(0.5, 0.5), display, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.7))
	draw_string(font, combined_pos, display, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, label_color)

# True when this token's model is the unit's first alive model — the single
# model that carries the unit name plate. Falls back to model_number 1 when
# the model id can't be matched (e.g. previews without meta).
func _is_unit_label_anchor(unit: Dictionary) -> bool:
	if not has_meta("model_id"):
		return model_number == 1
	var my_id = str(get_meta("model_id"))
	for m in unit.get("models", []):
		if m.get("current_wounds", m.get("wounds", 1)) > 0:
			return str(m.get("id", "")) == my_id
	return model_number == 1

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

	# MA-20: per-model art. When this model has a distinct profile (Boss Nob,
	# Runtherd, Spanner, ...) resolve <unit>_<model_type> art first, falling back
	# to the shared squad sprite for rank-and-file models (see SpriteResolver).
	var model_variant := _get_model_sprite_variant()

	_sprite_texture = SpriteResolver.resolve_sprite(unit_name, faction, unit_type, model_variant)


# MA-20: sprite discriminator for this model. Returns the model_type so that
# SpriteResolver can look up "<unit>_<model_type>.png" (e.g. stormboyz_boss_nob).
# Returns "" when the unit has no model_profiles or this model has no model_type
# (legacy units → shared squad sprite, unchanged behaviour).
func _get_model_sprite_variant() -> String:
	var model_type = model_data.get("model_type", "")
	if model_type == "" or model_type == null:
		return ""
	if not has_meta("unit_id"):
		return ""
	var unit = GameState.get_unit(get_meta("unit_id"))
	if unit.is_empty():
		return ""
	var profiles = unit.get("meta", {}).get("model_profiles", {})
	if not profiles.has(model_type):
		return ""
	return str(model_type)


func _get_unit_sprite_texture() -> Texture2D:
	if not _sprite_resolved:
		_resolve_sprite()
	return _sprite_texture


func _draw_unit_sprite(rot: float) -> void:
	# Top-down unit art drawn 1:1 over the base: the sprite's square canvas maps
	# to the base diameter, so the figure fills its base and weapons may overhang
	# the base circle (Vassal-style). Rotates with the model's facing like tanks.
	var bounds = base_shape.get_bounds()
	var tex = _sprite_texture
	var fit = min(bounds.size.x / tex.get_width(), bounds.size.y / tex.get_height())
	draw_set_transform(Vector2.ZERO, rot, Vector2(fit, fit))
	var tex_size = Vector2(tex.get_width(), tex.get_height())
	draw_texture_rect(tex, Rect2(-tex_size / 2.0, tex_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_tank_body_texture() -> Texture2D:
	if not _tank_resolved:
		_resolve_tank_sprites()
	return _tank_body_tex


func _resolve_tank_sprites() -> void:
	_tank_resolved = true
	if not has_meta("unit_id"):
		return
	if _get_unit_type() != "VEHICLE":
		return
	var unit = GameState.get_unit(get_meta("unit_id"))
	var keywords = unit.get("meta", {}).get("keywords", [])
	var titanic := false
	for k in keywords:
		if str(k).to_upper() == "TITANIC":
			titanic = true
			break
	var faction = _get_faction_name()
	_tank_body_tex = TokenTankSprites.body_texture(faction, owner_player, titanic)
	# The oversized titanic hull reads better without the standard turret.
	_tank_barrel_tex = null if titanic else TokenTankSprites.barrel_texture(faction, owner_player)


func _draw_tank_sprite(rot: float) -> void:
	var bounds = base_shape.get_bounds()
	var body = _tank_body_tex
	var fit = min(bounds.size.x * 0.95 / body.get_width(), bounds.size.y * 0.95 / body.get_height())
	draw_set_transform(Vector2.ZERO, rot, Vector2(fit, fit))
	var body_size = Vector2(body.get_width(), body.get_height())
	draw_texture_rect(body, Rect2(-body_size / 2.0, body_size), false)
	if _tank_barrel_tex != null:
		var barrel = _tank_barrel_tex
		var barrel_size = Vector2(barrel.get_width(), barrel.get_height())
		# The Kenney barrel texture points muzzle-down with the turret ring at
		# its top; flip it 180° so the gun faces the hull front (up at rot 0)
		# with the turret ring parked mid-hull.
		draw_set_transform(Vector2.ZERO, rot + PI, Vector2(fit, fit))
		draw_texture_rect(barrel, Rect2(Vector2(-barrel_size.x / 2.0, -barrel_size.y * 0.28), barrel_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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

func _has_marked_for_death_flag() -> bool:
	var unit_id = get_meta("unit_id") if has_meta("unit_id") else ""
	if unit_id == "":
		return false
	var unit = GameState.get_unit(unit_id)
	return unit.get("flags", {}).get("marked_for_death", "") != ""

func _has_performed_action_flag() -> bool:
	var unit_id = get_meta("unit_id") if has_meta("unit_id") else ""
	if unit_id == "":
		return false
	var unit = GameState.get_unit(unit_id)
	return unit.get("flags", {}).get("performed_action", "") != ""

func _draw_action_overlay(radius: float) -> void:
	if not has_meta("unit_id"):
		return
	var unit_id = get_meta("unit_id")
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	if unit.get("flags", {}).get("performed_action", "") == "":
		return
	TokenDrawUtils.draw_action_indicator(self, Vector2.ZERO, radius, _pulse_time)

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
	# In retro mode, use top-down pixel art silhouettes even for style_a
	var use_retro = SettingsService.retro_mode if SettingsService else false
	if use_retro:
		var accent = _get_faction_accent_color()
		accent.a = 1.0
		match unit_type:
			"VEHICLE":
				TokenDrawUtils.draw_vehicle_topdown(self, Vector2.ZERO, radius, color, accent, _animation_time)
			"MONSTER":
				TokenDrawUtils.draw_monster_topdown(self, Vector2.ZERO, radius, color, accent, _animation_time)
			_:
				TokenDrawUtils.draw_infantry_topdown(self, Vector2.ZERO, radius, color, accent, _animation_time)
		return

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

# Faction primary color for token bodies (enhanced/retro modes); falls back to
# the player slot color when the faction doesn't resolve.
func _get_faction_primary_color() -> Color:
	var faction = _get_faction_name()
	if faction != "" and FactionPalettes:
		return FactionPalettes.get_primary_color(faction)
	if owner_player == 1:
		return Color(0.2, 0.25, 0.45, 1.0)
	return Color(0.5, 0.12, 0.1, 1.0)

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
	_faction_font = null  # Reset font cache on model change
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


# T-095: Draw a glowing player-colored edge border on preview-mode tokens
# (the ones being placed during deployment). Reads is_preview flag.
# T-095 + T-095-ghost-pulse: animated pulse via _process_pulse / queue_redraw.
func _draw_preview_edge_border() -> void:
	if not is_preview:
		return
	if not base_shape:
		return
	var bounds = base_shape.get_bounds()
	var radius_local: float = min(bounds.size.x, bounds.size.y) / 2.0
	var glow_color: Color
	if owner_player == 1:
		glow_color = Color(0.83, 0.59, 0.38, 0.9)  # Gold
	else:
		glow_color = Color(0.85, 0.8, 0.65, 0.9)  # Bone
	# Pulsing outer ring + steady inner ring
	var pulse_t: float = (sin(Time.get_ticks_msec() * 0.003) + 1.0) * 0.5
	var outer_alpha: float = 0.6 + 0.35 * pulse_t
	draw_arc(Vector2.ZERO, radius_local + 9.0, 0, TAU, 48, Color(glow_color.r, glow_color.g, glow_color.b, outer_alpha), 6.0)
	draw_arc(Vector2.ZERO, radius_local + 4.0, 0, TAU, 48, glow_color, 3.0)


# T-096: Draw a red ring + "!" indicator on tokens of battle-shocked units.
func _draw_battle_shock_indicator() -> void:
	if not has_meta("unit_id"):
		return
	var unit_id_local: String = get_meta("unit_id")
	var unit_local = GameState.get_unit(unit_id_local) if GameState else {}
	if unit_local.is_empty():
		return
	if not unit_local.get("flags", {}).get("battle_shocked", false):
		return
	if not base_shape:
		return
	var bounds = base_shape.get_bounds()
	var radius_local: float = min(bounds.size.x, bounds.size.y) / 2.0
	# Red glow ring just outside the base — thick to stay visible at board scale (~0.3)
	draw_arc(Vector2.ZERO, radius_local + 12.0, 0, TAU, 48, Color(1.0, 0.15, 0.1, 0.95), 14.0)
	# Inner darker ring for contrast
	draw_arc(Vector2.ZERO, radius_local + 4.0, 0, TAU, 48, Color(0.6, 0.0, 0.0, 0.95), 8.0)
	# "!" exclamation badge on the right edge — large enough to be visible at board scale
	var badge_pos := Vector2(radius_local + 18.0, -radius_local + 6.0)
	draw_circle(badge_pos, 22.0, Color(1.0, 0.15, 0.1, 1.0))
	draw_arc(badge_pos, 22.0, 0, TAU, 32, Color(0.0, 0.0, 0.0, 1.0), 4.0)
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, badge_pos + Vector2(-7.0, 12.0), "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, Color.WHITE)


# T-101: Damaged-model art overlay.
# When the model has lost wounds, draw a small set of scorch/crack lines on the
# base whose count and opacity scale with damage_ratio = 1 - current/max.
# Uses a deterministic offset based on model_id so the lines stay stable
# frame-to-frame and don't shimmer.
func _draw_damage_overlay(radius: float) -> void:
	if not has_meta("unit_id") or not has_meta("model_id"):
		return
	var unit_id_local: String = get_meta("unit_id")
	var model_id_str: String = get_meta("model_id")
	var unit_local = GameState.get_unit(unit_id_local) if GameState else {}
	if unit_local.is_empty():
		return
	var total_wounds: int = 1
	var current_wounds: int = 1
	for m in unit_local.get("models", []):
		if str(m.get("id", "")) == model_id_str:
			total_wounds = int(m.get("wounds", 1))
			current_wounds = int(m.get("current_wounds", total_wounds))
			break
	if total_wounds <= 0:
		return
	if current_wounds >= total_wounds:
		return  # Undamaged — skip overlay
	var damage_ratio: float = clamp(1.0 - float(current_wounds) / float(total_wounds), 0.0, 1.0)
	# Deterministic seed per model id so cracks don't shimmer
	var seed_val: int = hash(model_id_str)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var n_cracks: int = int(2 + damage_ratio * 4)  # 2-6 lines
	var alpha: float = 0.45 + 0.45 * damage_ratio   # 0.45-0.9
	var crack_color := Color(0.05, 0.05, 0.06, alpha)
	for i in range(n_cracks):
		var angle: float = rng.randf_range(0.0, TAU)
		var inner_r: float = radius * rng.randf_range(0.15, 0.45)
		var outer_r: float = radius * rng.randf_range(0.55, 0.95)
		var p_inner := Vector2(cos(angle), sin(angle)) * inner_r
		var jitter: float = rng.randf_range(-0.35, 0.35)
		var p_outer := Vector2(cos(angle + jitter), sin(angle + jitter)) * outer_r
		draw_line(p_inner, p_outer, crack_color, 2.0 + damage_ratio * 1.5)
	# Heavy damage — add a few scorch dots
	if damage_ratio >= 0.5:
		var dot_color := Color(0.15, 0.08, 0.05, alpha)
		var n_dots: int = int(damage_ratio * 4)
		for i in range(n_dots):
			var dot_angle: float = rng.randf_range(0.0, TAU)
			var dot_r: float = radius * rng.randf_range(0.25, 0.85)
			var dot_pos := Vector2(cos(dot_angle), sin(dot_angle)) * dot_r
			draw_circle(dot_pos, 1.6 + damage_ratio * 1.8, dot_color)


# T-097: Colorblind shape badge.
# When SettingsService.colorblind_mode != "none", draw a per-player distinct shape
# at the lower-right of the base so player ownership reads via shape, not just color.
# P1 = upward triangle, P2 = square. Drawn in a high-contrast neutral palette.
func _draw_colorblind_shape_badge() -> void:
	if not SettingsService:
		return
	var mode: String = SettingsService.colorblind_mode
	if mode == "" or mode == "none":
		return
	if not base_shape:
		return
	var bounds = base_shape.get_bounds()
	var radius_local: float = min(bounds.size.x, bounds.size.y) / 2.0
	# Lower-right placement — opposite corner from the battle-shock ! badge
	var badge_pos := Vector2(radius_local + 14.0, radius_local + 4.0)
	var s: float = 14.0  # half-size of the badge
	var fill := Color(0.95, 0.95, 0.95, 0.95)  # near-white
	var outline := Color(0.05, 0.05, 0.08, 1.0)  # near-black

	if owner_player == 1:
		# Upward triangle for P1
		var tri := PackedVector2Array([
			badge_pos + Vector2(0.0, -s),
			badge_pos + Vector2(-s, s * 0.85),
			badge_pos + Vector2(s, s * 0.85),
		])
		draw_colored_polygon(tri, fill)
		var closed := PackedVector2Array()
		for p in tri:
			closed.append(p)
		closed.append(tri[0])
		draw_polyline(closed, outline, 2.0)
	else:
		# Square for P2
		var rect := PackedVector2Array([
			badge_pos + Vector2(-s, -s),
			badge_pos + Vector2(s, -s),
			badge_pos + Vector2(s, s),
			badge_pos + Vector2(-s, s),
		])
		draw_colored_polygon(rect, fill)
		var closed := PackedVector2Array()
		for p in rect:
			closed.append(p)
		closed.append(rect[0])
		draw_polyline(closed, outline, 2.0)
