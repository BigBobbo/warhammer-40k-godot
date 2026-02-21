extends Node2D
class_name DamageFeedbackVisual

# DamageFeedbackVisual - Target unit damage feedback (flash + death animation + floating numbers)
# T5-V4: Provides visual feedback when models take damage or are destroyed.
# - Damage flash: Red tint pulse radiating outward from the model position
# - Death animation: Expanding ring + fade-out with skull marker and particles
# T5-V12: Floating damage numbers that rise from wounded/destroyed models
# - Floating numbers: Damage value floats upward and fades out from model position

# === Damage Flash Constants ===
const DAMAGE_FLASH_DURATION := 0.4  # Total duration of damage flash
const DAMAGE_FLASH_RADIUS_MULT := 1.8  # Flash radius relative to base radius
const DAMAGE_FLASH_COLOR := Color(1.0, 0.15, 0.05, 0.7)  # Bright red flash
const DAMAGE_FLASH_CORE_COLOR := Color(1.0, 0.6, 0.1, 0.9)  # Orange-white core

# === Death Animation Constants ===
const DEATH_RING_DURATION := 0.5  # Ring expansion time
const DEATH_FADE_DURATION := 0.8  # Fade-out time after ring
const DEATH_RING_START_MULT := 0.5  # Ring starts at 50% of base
const DEATH_RING_END_MULT := 2.5  # Ring expands to 250% of base
const DEATH_RING_COLOR := Color(0.8, 0.05, 0.0, 0.8)  # Deep red expanding ring
const DEATH_FLASH_COLOR := Color(1.0, 0.3, 0.0, 0.9)  # Orange-red death flash
const DEATH_SKULL_DURATION := 1.5  # How long skull marker stays visible
const DEATH_PARTICLE_COUNT := 8  # Number of debris particles

# === T5-V12: Floating Number Constants ===
const FLOAT_NUMBER_DURATION := 1.2  # How long the number floats
const FLOAT_NUMBER_RISE_PX := 40.0  # How far the number rises (in pixels)
const FLOAT_NUMBER_FONT_SIZE := 22  # Base font size for floating numbers
const FLOAT_NUMBER_COLOR_DAMAGE := Color(1.0, 0.2, 0.1, 1.0)  # Red for damage
const FLOAT_NUMBER_COLOR_KILL := Color(0.8, 0.05, 0.0, 1.0)  # Dark red for kills

# === T7-53: Kill Notification Constants ===
const KILL_NOTIFY_DURATION := 2.0  # How long the notification stays visible
const KILL_NOTIFY_RISE_PX := 60.0  # How far it rises
const KILL_NOTIFY_FONT_SIZE := 18  # Font size for kill notification
const KILL_NOTIFY_COLOR := Color(0.9, 0.05, 0.0, 1.0)  # Deep red for unit destruction

# Internal state
var _effects: Array = []  # Active effects list [{type, pos, radius, elapsed, duration, ...}]

func _ready() -> void:
	z_index = 55  # Above board highlights (50), below UI
	print("[DamageFeedbackVisual] T5-V4: Ready")

func _process(delta: float) -> void:
	if _effects.is_empty():
		return

	var finished_indices := []

	for i in range(_effects.size()):
		var effect = _effects[i]
		effect.elapsed += delta

		if effect.elapsed >= effect.duration:
			finished_indices.append(i)

	# Remove finished effects (in reverse order to preserve indices)
	for i in range(finished_indices.size() - 1, -1, -1):
		var idx = finished_indices[i]
		var effect = _effects[idx]
		# Clean up any child nodes (skull labels, etc.)
		if effect.has("skull_node") and is_instance_valid(effect.skull_node):
			effect.skull_node.queue_free()
		_effects.remove_at(idx)

	queue_redraw()

func _draw() -> void:
	for effect in _effects:
		match effect.type:
			"damage_flash":
				_draw_damage_flash(effect)
			"death_ring":
				_draw_death_ring(effect)
			"death_particles":
				_draw_death_particles(effect)

# ── Public API ──────────────────────────────────────────────────────────────

func play_damage_flash(model_pos: Vector2, base_radius_px: float, damage: int = 1, max_wounds: int = 1) -> void:
	"""Play a red damage flash at model position. Intensity scales with damage ratio."""
	var intensity = clampf(float(damage) / float(max(max_wounds, 1)), 0.3, 1.0)

	_effects.append({
		"type": "damage_flash",
		"pos": model_pos,
		"radius": base_radius_px * DAMAGE_FLASH_RADIUS_MULT,
		"elapsed": 0.0,
		"duration": DAMAGE_FLASH_DURATION,
		"intensity": intensity
	})

	queue_redraw()
	print("[DamageFeedbackVisual] T5-V4: Damage flash at %s (radius=%.0f, intensity=%.2f)" % [str(model_pos), base_radius_px, intensity])

func play_floating_number(model_pos: Vector2, damage: int, is_kill: bool = false) -> void:
	"""T5-V12: Show a damage number floating upward from model position."""
	var label = Label.new()
	label.text = "-%d" % damage
	var font_size = FLOAT_NUMBER_FONT_SIZE + (4 if damage >= 3 else 0)  # Bigger text for bigger hits
	label.add_theme_font_size_override("font_size", font_size)
	var base_color = FLOAT_NUMBER_COLOR_KILL if is_kill else FLOAT_NUMBER_COLOR_DAMAGE
	label.add_theme_color_override("font_color", base_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Slight random horizontal offset to prevent stacking when multiple models hit
	var x_offset = randf_range(-12.0, 12.0)
	label.position = model_pos + Vector2(x_offset - font_size * 0.4, -font_size * 0.6)
	label.z_index = 57  # Above skull markers (56)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# Tween 1: Rise upward with ease-out
	var rise_tween = create_tween()
	rise_tween.tween_property(label, "position:y", label.position.y - FLOAT_NUMBER_RISE_PX, FLOAT_NUMBER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Tween 2: Fade out in second half, then clean up
	var fade_tween = create_tween()
	fade_tween.tween_property(label, "theme_override_colors/font_color:a", 0.0, FLOAT_NUMBER_DURATION * 0.5).set_delay(FLOAT_NUMBER_DURATION * 0.5)
	fade_tween.tween_callback(label.queue_free)

	print("[DamageFeedbackVisual] T5-V12: Floating number -%d at %s (kill=%s)" % [damage, str(model_pos), str(is_kill)])

func play_death_animation(model_pos: Vector2, base_radius_px: float) -> void:
	"""Play death animation: expanding ring + particles + skull marker."""
	# Effect 1: Expanding red ring
	_effects.append({
		"type": "death_ring",
		"pos": model_pos,
		"base_radius": base_radius_px,
		"elapsed": 0.0,
		"duration": DEATH_RING_DURATION + DEATH_FADE_DURATION
	})

	# Effect 2: Debris particles flying outward
	var particles := []
	for p in range(DEATH_PARTICLE_COUNT):
		var angle = (float(p) / float(DEATH_PARTICLE_COUNT)) * TAU + randf() * 0.3
		var speed = base_radius_px * (1.5 + randf() * 2.0)
		var size = 2.0 + randf() * 3.0
		particles.append({
			"angle": angle,
			"speed": speed,
			"size": size,
			"color": Color(
				0.6 + randf() * 0.4,
				0.1 + randf() * 0.3,
				0.0,
				0.8 + randf() * 0.2
			)
		})

	_effects.append({
		"type": "death_particles",
		"pos": model_pos,
		"particles": particles,
		"elapsed": 0.0,
		"duration": DEATH_RING_DURATION + DEATH_FADE_DURATION
	})

	# Effect 3: Skull marker label (fades in after ring, stays briefly)
	var skull_label = Label.new()
	skull_label.text = "💀"
	var font_size = int(base_radius_px * 1.2)
	skull_label.add_theme_font_size_override("font_size", font_size)
	skull_label.add_theme_color_override("font_color", Color(0.9, 0.1, 0.05, 0.0))  # Start invisible
	skull_label.position = model_pos + Vector2(-font_size * 0.3, -font_size * 0.4)
	skull_label.z_index = 56
	skull_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skull_label)

	# Animate skull: fade in during ring, hold, then fade out
	var tween = create_tween()
	tween.tween_property(skull_label, "theme_override_colors/font_color:a", 1.0, DEATH_RING_DURATION * 0.5).set_delay(DEATH_RING_DURATION * 0.5)
	tween.tween_interval(DEATH_SKULL_DURATION)
	tween.tween_property(skull_label, "theme_override_colors/font_color:a", 0.0, 0.5)
	tween.tween_callback(skull_label.queue_free)

	queue_redraw()
	print("[DamageFeedbackVisual] T5-V4: Death animation at %s (radius=%.0f)" % [str(model_pos), base_radius_px])

func play_kill_notification(unit_center_pos: Vector2, unit_name: String) -> void:
	"""T7-53: Show a 'UNIT DESTROYED' notification floating above the destroyed unit's position."""
	var label = Label.new()
	label.text = "DESTROYED: %s" % unit_name
	label.add_theme_font_size_override("font_size", KILL_NOTIFY_FONT_SIZE)
	label.add_theme_color_override("font_color", KILL_NOTIFY_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Position above unit center
	label.position = unit_center_pos + Vector2(-KILL_NOTIFY_FONT_SIZE * 3.0, -KILL_NOTIFY_FONT_SIZE * 1.5)
	label.z_index = 58  # Above floating numbers (57)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add background panel for readability
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.size = Vector2(label.text.length() * KILL_NOTIFY_FONT_SIZE * 0.6, KILL_NOTIFY_FONT_SIZE * 1.4)
	bg.position = unit_center_pos + Vector2(-bg.size.x * 0.5, -KILL_NOTIFY_FONT_SIZE * 1.5)
	bg.z_index = 57
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	add_child(label)

	# Tween: Rise upward
	var rise_tween = create_tween()
	rise_tween.tween_property(label, "position:y", label.position.y - KILL_NOTIFY_RISE_PX, KILL_NOTIFY_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var bg_rise = create_tween()
	bg_rise.tween_property(bg, "position:y", bg.position.y - KILL_NOTIFY_RISE_PX, KILL_NOTIFY_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Tween: Fade out in second half, then clean up
	var fade_tween = create_tween()
	fade_tween.tween_property(label, "theme_override_colors/font_color:a", 0.0, KILL_NOTIFY_DURATION * 0.4).set_delay(KILL_NOTIFY_DURATION * 0.6)
	fade_tween.tween_callback(label.queue_free)

	var bg_fade = create_tween()
	bg_fade.tween_property(bg, "color:a", 0.0, KILL_NOTIFY_DURATION * 0.4).set_delay(KILL_NOTIFY_DURATION * 0.6)
	bg_fade.tween_callback(bg.queue_free)

	print("[DamageFeedbackVisual] T7-53: Kill notification '%s' at %s" % [unit_name, str(unit_center_pos)])

func play_result_summary(target_pos: Vector2, summary_text: String) -> void:
	"""T7-38: Show a hit/wound result summary floating above target position during AI shooting."""
	var font_size := 14
	var label = Label.new()
	label.text = summary_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7, 1.0))  # Warm white
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = target_pos + Vector2(-summary_text.length() * 3.5, -font_size * 2.5)
	label.z_index = 58
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Background for readability
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.size = Vector2(summary_text.length() * 7.0 + 8, font_size + 6)
	bg.position = target_pos + Vector2(-bg.size.x * 0.5, -font_size * 2.5)
	bg.z_index = 57
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	add_child(label)

	# Rise and fade
	var duration := 2.5
	var rise_tween = create_tween()
	rise_tween.tween_property(label, "position:y", label.position.y - 50.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	var bg_rise = create_tween()
	bg_rise.tween_property(bg, "position:y", bg.position.y - 50.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	var fade_tween = create_tween()
	fade_tween.tween_property(label, "theme_override_colors/font_color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	fade_tween.tween_callback(label.queue_free)

	var bg_fade = create_tween()
	bg_fade.tween_property(bg, "color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	bg_fade.tween_callback(bg.queue_free)

	print("[DamageFeedbackVisual] T7-38: Result summary '%s' at %s" % [summary_text, str(target_pos)])

# ── Drawing Helpers ─────────────────────────────────────────────────────────

func _draw_damage_flash(effect: Dictionary) -> void:
	var progress = clampf(effect.elapsed / effect.duration, 0.0, 1.0)
	var pos: Vector2 = effect.pos
	var max_radius: float = effect.radius
	var intensity: float = effect.get("intensity", 1.0)

	# Flash expands quickly then fades
	# First 30%: expand and brighten; remaining 70%: fade out
	var expand_t = clampf(progress / 0.3, 0.0, 1.0)
	var fade_t = clampf((progress - 0.3) / 0.7, 0.0, 1.0)

	var current_radius = max_radius * (0.5 + expand_t * 0.5)
	var alpha = intensity * (1.0 - fade_t)

	# Outer flash (red glow)
	var outer_color = Color(DAMAGE_FLASH_COLOR.r, DAMAGE_FLASH_COLOR.g, DAMAGE_FLASH_COLOR.b, alpha * 0.4)
	draw_circle(pos, current_radius, outer_color)

	# Mid ring
	var mid_color = Color(DAMAGE_FLASH_COLOR.r, DAMAGE_FLASH_COLOR.g, DAMAGE_FLASH_COLOR.b, alpha * 0.6)
	draw_circle(pos, current_radius * 0.7, mid_color)

	# Inner core (bright orange-white)
	var core_alpha = alpha * (1.0 - expand_t * 0.5)
	var core_color = Color(DAMAGE_FLASH_CORE_COLOR.r, DAMAGE_FLASH_CORE_COLOR.g, DAMAGE_FLASH_CORE_COLOR.b, core_alpha * 0.7)
	draw_circle(pos, current_radius * 0.35, core_color)

	# Pulsing ring outline for emphasis
	var ring_alpha = alpha * 0.8
	var ring_color = Color(1.0, 0.2, 0.0, ring_alpha)
	draw_arc(pos, current_radius * 0.85, 0, TAU, 32, ring_color, 2.0)

func _draw_death_ring(effect: Dictionary) -> void:
	var progress = clampf(effect.elapsed / effect.duration, 0.0, 1.0)
	var pos: Vector2 = effect.pos
	var base_r: float = effect.base_radius

	# Phase 1 (0..ring_frac): Ring expands
	var ring_frac = DEATH_RING_DURATION / effect.duration
	# Phase 2 (ring_frac..1): Fade out
	var ring_progress = clampf(progress / ring_frac, 0.0, 1.0)
	var fade_progress = clampf((progress - ring_frac) / (1.0 - ring_frac), 0.0, 1.0)

	var ring_radius = base_r * lerpf(DEATH_RING_START_MULT, DEATH_RING_END_MULT, ring_progress)
	var alpha = 1.0 - fade_progress

	# Inner flash (bright, fades quickly)
	if ring_progress < 0.6:
		var flash_alpha = alpha * (1.0 - ring_progress / 0.6) * 0.7
		var flash_color = Color(DEATH_FLASH_COLOR.r, DEATH_FLASH_COLOR.g, DEATH_FLASH_COLOR.b, flash_alpha)
		draw_circle(pos, base_r * DEATH_RING_START_MULT, flash_color)

	# Expanding ring outline
	var ring_width = 3.0 + ring_progress * 2.0
	var ring_color = Color(DEATH_RING_COLOR.r, DEATH_RING_COLOR.g, DEATH_RING_COLOR.b, alpha * DEATH_RING_COLOR.a)
	draw_arc(pos, ring_radius, 0, TAU, 48, ring_color, ring_width)

	# Secondary thinner ring (slightly behind main ring)
	if ring_progress > 0.2:
		var inner_ring_progress = clampf((ring_progress - 0.2) / 0.8, 0.0, 1.0)
		var inner_radius = base_r * lerpf(DEATH_RING_START_MULT, DEATH_RING_END_MULT * 0.7, inner_ring_progress)
		var inner_alpha = alpha * 0.4
		var inner_color = Color(1.0, 0.5, 0.1, inner_alpha)
		draw_arc(pos, inner_radius, 0, TAU, 32, inner_color, 1.5)

func _draw_death_particles(effect: Dictionary) -> void:
	var progress = clampf(effect.elapsed / effect.duration, 0.0, 1.0)
	var pos: Vector2 = effect.pos
	var particles: Array = effect.particles

	# Particles start moving at ring_start and fade out
	var ring_frac = DEATH_RING_DURATION / effect.duration
	var particle_progress = clampf((progress - ring_frac * 0.3) / (1.0 - ring_frac * 0.3), 0.0, 1.0)
	var alpha = 1.0 - particle_progress

	if alpha <= 0.0:
		return

	for p in particles:
		var dist = p.speed * particle_progress
		var particle_pos = pos + Vector2(cos(p.angle), sin(p.angle)) * dist
		var p_size = p.size * (1.0 - particle_progress * 0.5)
		var p_color = Color(p.color.r, p.color.g, p.color.b, p.color.a * alpha)
		draw_circle(particle_pos, p_size, p_color)

# ── Cleanup ─────────────────────────────────────────────────────────────────

func clear_all() -> void:
	"""Remove all active effects immediately."""
	for effect in _effects:
		if effect.has("skull_node") and is_instance_valid(effect.skull_node):
			effect.skull_node.queue_free()
	_effects.clear()
	# Also remove any skull labels that are children
	for child in get_children():
		if child is Label:
			child.queue_free()
	queue_redraw()
	print("[DamageFeedbackVisual] T5-V4: Cleared all effects")
