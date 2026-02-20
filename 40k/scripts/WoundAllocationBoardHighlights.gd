extends Node2D
class_name WoundAllocationBoardHighlights

# Visual highlight system for wound allocation on game board
# Creates GPU-accelerated highlights around models during wound allocation
# T5-V6: Enhanced with pulsing animations, health color gradients, and wound counters

# Highlight types
enum HighlightType {
	PRIORITY,           # Red pulsing - must select (wounded models)
	SELECTABLE,         # Green steady - can select
	SELECTED,           # Yellow flash - just selected
	DEAD,               # Gray X marker - model destroyed
	CHARACTER_PROTECTED, # Blue/purple - character protected by bodyguard (non-selectable)
	PRECISION_TARGET    # Orange - character targetable by Precision weapon (T3-4)
}

# Preload shader at class level (REQUIRED for instantiation to work)
const HighlightShader = preload("res://shaders/model_highlight.gdshader")

# Shader material for highlights
var highlight_shader: Shader
var active_highlights: Dictionary = {}  # model_id -> Sprite2D (temporary highlights)
var death_markers: Dictionary = {}  # model_id -> Sprite2D (persistent death markers)
# T5-V6: Health gradient overlays and wound counters
var health_overlays: Dictionary = {}  # model_id -> Sprite2D (health color ring)
var wound_counters: Dictionary = {}  # model_id -> Label (wound count display)
var pulsing_highlights: Array = []  # Array of highlights that should pulse

func _ready() -> void:
	# Load the highlight shader from class constant
	highlight_shader = HighlightShader
	if not highlight_shader:
		push_error("WoundAllocationBoardHighlights: Failed to load highlight shader")

	print("╔══════════════════════════════════════════════════════════════════")
	print("║ WoundAllocationBoardHighlights._ready() CALLED")
	print("║ Shader loaded: ", highlight_shader != null)
	print("║ Self visible: ", visible)
	print("║ Self modulate: ", modulate)
	print("║ Self z_index: ", z_index)
	print("║ Self in tree: ", is_inside_tree())
	print("║ Self path: ", get_path() if is_inside_tree() else "NOT IN TREE")
	print("╚══════════════════════════════════════════════════════════════════")

# T5-V6: Pulsing animation for PRIORITY highlights
func _process(delta: float) -> void:
	if pulsing_highlights.is_empty():
		return
	# Sine-wave pulse: alpha oscillates between 0.3 and 0.9, scale oscillates between 0.95x and 1.10x
	var t = Time.get_ticks_msec() / 1000.0
	var pulse = (sin(t * 4.0) + 1.0) / 2.0  # 0..1, ~2 Hz
	var alpha = lerp(0.3, 0.9, pulse)
	var scale_factor = lerp(0.95, 1.10, pulse)
	for highlight in pulsing_highlights:
		if is_instance_valid(highlight):
			highlight.modulate.a = alpha
			# Store base scale so we can pulse around it
			var base_scale = highlight.get_meta("base_scale", highlight.scale)
			highlight.scale = base_scale * scale_factor

func create_highlight(model_pos: Vector2, base_radius_mm: float, type: HighlightType, model_id: String = "") -> void:
	"""Create a highlight circle around a model"""
	# Create highlight sprite
	var highlight = Sprite2D.new()
	highlight.name = "Highlight_" + model_id if model_id != "" else "Highlight"

	# Create a simple circle texture
	var texture = _create_circle_texture(128)  # LARGER for visibility
	highlight.texture = texture
	highlight.centered = true  # CRITICAL: Center the sprite
	highlight.position = model_pos

	# Scale based on base size - LARGER for visibility
	var base_px = Measurement.base_radius_px(base_radius_mm)
	var scale_factor = (base_px * 2.0) / 64.0  # 2X larger for testing
	highlight.scale = Vector2(scale_factor, scale_factor)
	highlight.z_index = 50  # High z-index to ensure visibility

	# TESTING: Use simple modulate instead of shaders
	match type:
		HighlightType.PRIORITY:
			# WH Red pulsing for wounded models that must be selected
			# T5-V6: Actual pulsing animation via _process()
			highlight.modulate = Color(0.6, 0.07, 0.07, 0.7)  # WH Red
			highlight.set_meta("base_scale", highlight.scale)
			pulsing_highlights.append(highlight)
			print("WoundAllocationBoardHighlights: Created PRIORITY highlight (WH red, pulsing) at ", model_pos)

		HighlightType.SELECTABLE:
			# Gold steady for models that can be selected
			highlight.modulate = Color(0.83, 0.59, 0.38, 0.6)  # Gold
			print("WoundAllocationBoardHighlights: Created SELECTABLE highlight (gold) at ", model_pos)

		HighlightType.SELECTED:
			# Parchment flash for just-selected model
			highlight.modulate = Color(0.92, 0.88, 0.78, 0.9)  # Parchment
			print("╔══════════════════════════════════════════════════════════════════")
			print("║ CREATING YELLOW FLASH at ", model_pos)
			print("║ This should be VERY VISIBLE for 3 seconds")
			print("╚══════════════════════════════════════════════════════════════════")
			# Make it last 3 seconds for testing
			var tween = create_tween()
			tween.tween_property(highlight, "modulate:a", 0.0, 3.0)  # 3 seconds fade
			tween.tween_callback(highlight.queue_free)

		HighlightType.CHARACTER_PROTECTED:
			# Blue/purple shield - character protected by bodyguard
			highlight.modulate = Color(0.3, 0.3, 0.8, 0.6)  # Blue/purple
			# Add shield icon label
			var shield_label = Label.new()
			shield_label.text = "🛡"
			shield_label.add_theme_font_size_override("font_size", int(base_px * 1.0))
			shield_label.add_theme_color_override("font_color", Color(0.5, 0.5, 1.0))
			shield_label.position = Vector2(-base_px * 0.4, -base_px * 0.5)
			shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			highlight.add_child(shield_label)
			print("WoundAllocationBoardHighlights: Created CHARACTER_PROTECTED highlight (blue) at ", model_pos)

		HighlightType.PRECISION_TARGET:
			# PRECISION (T3-4): Orange highlight for CHARACTER models targetable by Precision
			# T5-V6: Also pulses to draw attention
			highlight.modulate = Color(0.9, 0.5, 0.1, 0.7)  # Orange
			highlight.set_meta("base_scale", highlight.scale)
			pulsing_highlights.append(highlight)
			# Add crosshair icon label
			var precision_label = Label.new()
			precision_label.text = "🎯"
			precision_label.add_theme_font_size_override("font_size", int(base_px * 1.0))
			precision_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
			precision_label.position = Vector2(-base_px * 0.4, -base_px * 0.5)
			precision_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			highlight.add_child(precision_label)
			print("WoundAllocationBoardHighlights: Created PRECISION_TARGET highlight (orange, pulsing) at ", model_pos)

		HighlightType.DEAD:
			# Gray semitransparent circle with skull marker
			highlight.modulate = Color(0.5, 0.5, 0.5, 0.7)  # Gray

			# Add skull emoji label
			var skull_label = Label.new()
			skull_label.text = "💀"
			skull_label.add_theme_font_size_override("font_size", int(base_px * 1.2))
			skull_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
			skull_label.position = Vector2(-base_px * 0.5, -base_px * 0.5)
			skull_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			highlight.add_child(skull_label)
			print("WoundAllocationBoardHighlights: Created DEAD highlight (gray + skull) at ", model_pos)

	add_child(highlight)

	# Store reference if model_id provided (for cleanup)
	if model_id != "":
		active_highlights[model_id] = highlight

func clear_all() -> void:
	"""Remove all highlights from the board (but NOT death markers, health overlays, or wound counters)"""
	for child in get_children():
		# Skip death markers - they persist until phase end
		if child.name.begins_with("DeathMarker_"):
			continue
		# T5-V6: Skip health overlays and wound counters - they persist
		if child.name.begins_with("HealthOverlay_") or child.name.begins_with("WoundCounter_"):
			continue

		child.queue_free()

	# Clear only active_highlights and pulsing list, not death_markers/health overlays/wound counters
	active_highlights.clear()
	pulsing_highlights.clear()
	# death_markers, health_overlays, wound_counters remain until explicitly cleared

func clear_highlight(model_id: String) -> void:
	"""Remove highlight for specific model"""
	if active_highlights.has(model_id):
		active_highlights[model_id].queue_free()
		active_highlights.erase(model_id)

func create_death_marker(model_pos: Vector2, base_radius_mm: float, model_id: String) -> void:
	"""Create a persistent red circle marker at model's death position"""
	print("╔══════════════════════════════════════════════════════════════════")
	print("║ WoundAllocationBoardHighlights.create_death_marker() CALLED")
	print("║ model_id: ", model_id)
	print("║ model_pos: ", model_pos)
	print("║ base_radius_mm: ", base_radius_mm)
	print("╚══════════════════════════════════════════════════════════════════")

	# Create marker sprite
	print("WoundAllocationBoardHighlights: Creating Sprite2D...")
	var marker = Sprite2D.new()
	marker.name = "DeathMarker_" + model_id
	print("  - marker.name: ", marker.name)

	# Create circle texture
	print("WoundAllocationBoardHighlights: Creating circle texture...")
	var texture = _create_circle_texture(128)  # LARGER texture for visibility
	print("  - texture is null: ", texture == null)

	marker.texture = texture
	marker.centered = true  # CRITICAL: Center the sprite
	marker.position = model_pos
	print("  - marker.centered: ", marker.centered)
	print("  - marker.position: ", marker.position)

	# Scale based on base size - MAKE IT MUCH LARGER FOR TESTING
	var base_px = Measurement.base_radius_px(base_radius_mm)
	var scale_factor = (base_px * 3.0) / 64.0  # 3X LARGER for testing
	marker.scale = Vector2(scale_factor, scale_factor)
	print("  - base_px: ", base_px)
	print("  - scale_factor: ", scale_factor)
	print("  - marker.scale: ", marker.scale)
	print("  - Final marker size (pixels): ", 128 * scale_factor)

	# Use SIMPLE MODULATE instead of shader for testing
	print("WoundAllocationBoardHighlights: Setting modulate color (NOT using shader for now)...")
	marker.modulate = Color(1.0, 0.0, 0.0, 0.8)  # Bright red, 80% opacity
	print("  - marker.modulate: ", marker.modulate)

	marker.z_index = 50  # MUCH HIGHER z-index to ensure it's on top
	print("  - marker.z_index: ", marker.z_index)

	print("WoundAllocationBoardHighlights: Adding marker as child...")
	print("  - self is in tree: ", is_inside_tree())
	print("  - self path: ", get_path() if is_inside_tree() else "NOT IN TREE")

	add_child(marker)
	print("  - ✅ add_child() completed")
	print("  - marker is in tree: ", marker.is_inside_tree())
	print("  - marker path: ", marker.get_path() if marker.is_inside_tree() else "NOT IN TREE")
	print("  - marker visible: ", marker.visible)
	print("  - marker modulate: ", marker.modulate)

	# DIAGNOSTIC: Check parent visibility chain
	print("WoundAllocationBoardHighlights: Checking parent visibility chain...")
	var parent_chain = marker
	var chain_depth = 0
	while parent_chain != null and chain_depth < 10:
		print("  - [%d] %s: visible=%s, modulate=%s, z_index=%s" % [
			chain_depth,
			parent_chain.name,
			parent_chain.visible if parent_chain is CanvasItem else "N/A",
			parent_chain.modulate if parent_chain is CanvasItem else "N/A",
			parent_chain.z_index if parent_chain is CanvasItem else "N/A"
		])
		parent_chain = parent_chain.get_parent()
		chain_depth += 1

	# DIAGNOSTIC: Check marker's rendering properties
	print("WoundAllocationBoardHighlights: Marker rendering properties:")
	print("  - texture: ", marker.texture)
	print("  - texture size: ", marker.texture.get_size() if marker.texture else "NO TEXTURE")
	print("  - material: ", marker.material)
	print("  - material shader: ", marker.material.shader if marker.material else "NO MATERIAL")
	print("  - global_position: ", marker.global_position)
	print("  - scale: ", marker.scale)
	print("  - rotation: ", marker.rotation)
	print("  - self_modulate: ", marker.self_modulate)

	# DIAGNOSTIC: Force a redraw
	print("WoundAllocationBoardHighlights: Forcing marker queue_redraw()...")
	if marker.has_method("queue_redraw"):
		marker.queue_redraw()
		print("  - ✅ queue_redraw() called")

	# Store reference for cleanup
	death_markers[model_id] = marker
	print("  - ✅ Stored in death_markers dictionary")
	print("  - death_markers.size(): ", death_markers.size())

	print("╔══════════════════════════════════════════════════════════════════")
	print("║ ✅ DEATH MARKER CREATED SUCCESSFULLY")
	print("║ model_id: ", model_id)
	print("║ position: ", model_pos)
	print("║ global_position: ", marker.global_position)
	print("║ marker name: ", marker.name)
	print("║ marker path: ", marker.get_path() if marker.is_inside_tree() else "NOT IN TREE")
	print("║ Total death markers: ", death_markers.size())
	print("╚══════════════════════════════════════════════════════════════════")

func clear_death_markers() -> void:
	"""Remove all death markers (called at phase end)"""
	for model_id in death_markers:
		var marker = death_markers[model_id]
		if marker and is_instance_valid(marker):
			marker.queue_free()

	death_markers.clear()
	print("WoundAllocationBoardHighlights: Cleared all death markers")

# T5-V6: Health gradient overlay — ring around model colored green→yellow→red based on HP
func create_health_overlay(model_pos: Vector2, base_radius_mm: float, current_wounds: int, max_wounds: int, model_id: String) -> void:
	"""Create a health-colored ring around a model based on its wound ratio"""
	if max_wounds <= 1:
		# Single-wound models don't need a gradient — they're alive or dead
		return

	# Remove existing overlay for this model
	if health_overlays.has(model_id):
		var old = health_overlays[model_id]
		if is_instance_valid(old):
			old.queue_free()
		health_overlays.erase(model_id)

	var health_ratio = float(current_wounds) / float(max_wounds)

	# Color gradient: green (1.0) → yellow (0.5) → red (0.0)
	var health_color: Color
	if health_ratio > 0.5:
		# Green to yellow
		var t = (health_ratio - 0.5) / 0.5
		health_color = Color(1.0 - t * 0.7, 0.5 + t * 0.3, 0.1, 0.5)
	else:
		# Yellow to red
		var t = health_ratio / 0.5
		health_color = Color(0.8 + (1.0 - t) * 0.2, t * 0.5, 0.05, 0.5)

	# Create ring sprite
	var ring = Sprite2D.new()
	ring.name = "HealthOverlay_" + model_id
	ring.texture = _create_ring_texture(128, 12)  # Ring with 12px thickness
	ring.centered = true
	ring.position = model_pos
	ring.modulate = health_color

	var base_px = Measurement.base_radius_px(base_radius_mm)
	var scale_factor = (base_px * 2.4) / 64.0  # Slightly larger than model base
	ring.scale = Vector2(scale_factor, scale_factor)
	ring.z_index = 48  # Below highlight rings but above board

	add_child(ring)
	health_overlays[model_id] = ring
	print("WoundAllocationBoardHighlights: T5-V6 health overlay for %s — %d/%d (%.0f%% hp, color=%s)" % [model_id, current_wounds, max_wounds, health_ratio * 100, health_color])

# T5-V6: Wound counter label near model
func create_wound_counter(model_pos: Vector2, base_radius_mm: float, current_wounds: int, max_wounds: int, model_id: String) -> void:
	"""Display a small wound counter near the model's position"""
	# Remove existing counter for this model
	if wound_counters.has(model_id):
		var old = wound_counters[model_id]
		if is_instance_valid(old):
			old.queue_free()
		wound_counters.erase(model_id)

	# Only show counter for multi-wound models that have taken damage
	if max_wounds <= 1 or current_wounds >= max_wounds:
		return

	var base_px = Measurement.base_radius_px(base_radius_mm)

	# Create a label showing wounds remaining
	var counter = Label.new()
	counter.name = "WoundCounter_" + model_id
	counter.text = "%d/%d" % [current_wounds, max_wounds]
	counter.add_theme_font_size_override("font_size", max(10, int(base_px * 0.55)))

	# Color the text based on health
	var health_ratio = float(current_wounds) / float(max_wounds)
	var font_color: Color
	if health_ratio > 0.5:
		font_color = Color(0.3, 1.0, 0.3)  # Green
	elif health_ratio > 0.25:
		font_color = Color(1.0, 1.0, 0.3)  # Yellow
	else:
		font_color = Color(1.0, 0.3, 0.3)  # Red
	counter.add_theme_color_override("font_color", font_color)

	# Add dark outline for readability
	counter.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	counter.add_theme_constant_override("outline_size", 3)

	# Position below the model base
	counter.position = model_pos + Vector2(-base_px * 0.4, base_px * 0.7)
	counter.z_index = 55  # Above highlights
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(counter)
	wound_counters[model_id] = counter
	print("WoundAllocationBoardHighlights: T5-V6 wound counter for %s — %d/%d" % [model_id, current_wounds, max_wounds])

# T5-V6: Update health overlay and wound counter for a model after damage
func update_model_health_display(model_pos: Vector2, base_radius_mm: float, current_wounds: int, max_wounds: int, model_id: String) -> void:
	"""Update both health overlay ring and wound counter for a model"""
	create_health_overlay(model_pos, base_radius_mm, current_wounds, max_wounds, model_id)
	create_wound_counter(model_pos, base_radius_mm, current_wounds, max_wounds, model_id)

# T5-V6: Remove health overlay and wound counter for a destroyed model
func remove_model_health_display(model_id: String) -> void:
	"""Remove health display elements for a destroyed model"""
	if health_overlays.has(model_id):
		var overlay = health_overlays[model_id]
		if is_instance_valid(overlay):
			overlay.queue_free()
		health_overlays.erase(model_id)

	if wound_counters.has(model_id):
		var counter = wound_counters[model_id]
		if is_instance_valid(counter):
			counter.queue_free()
		wound_counters.erase(model_id)

# T5-V6: Clear all health overlays and wound counters
func clear_health_displays() -> void:
	"""Remove all health overlays and wound counters"""
	for model_id in health_overlays:
		var overlay = health_overlays[model_id]
		if overlay and is_instance_valid(overlay):
			overlay.queue_free()
	health_overlays.clear()

	for model_id in wound_counters:
		var counter = wound_counters[model_id]
		if counter and is_instance_valid(counter):
			counter.queue_free()
	wound_counters.clear()
	print("WoundAllocationBoardHighlights: T5-V6 cleared all health displays")

func _create_circle_texture(size: int) -> ImageTexture:
	"""Create a simple white circle texture for highlighting"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0 - 1.0

	# Draw circle
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= radius:
				# Smooth edge with anti-aliasing
				var alpha = 1.0
				if dist > radius - 2.0:
					alpha = 1.0 - ((dist - (radius - 2.0)) / 2.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)

# T5-V6: Create a ring (hollow circle) texture for health gradient overlay
func _create_ring_texture(size: int, thickness: int) -> ImageTexture:
	"""Create a white ring texture (hollow circle) for health overlay"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var center = Vector2(size / 2.0, size / 2.0)
	var outer_radius = size / 2.0 - 1.0
	var inner_radius = outer_radius - float(thickness)

	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= outer_radius and dist >= inner_radius:
				# Smooth edges with anti-aliasing
				var alpha = 1.0
				if dist > outer_radius - 2.0:
					alpha = 1.0 - ((dist - (outer_radius - 2.0)) / 2.0)
				elif dist < inner_radius + 2.0:
					alpha = (dist - inner_radius) / 2.0
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
