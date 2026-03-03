extends Control
class_name DiceRollVisual

# DiceRollVisual - Animated 2D dice roll visualization
# Shows dice rolling with animation and color-coded results
# Gold for critical hits (6s), red for natural 1s, green for successes, gray for failures

# Die visual constants
const DIE_SIZE := 28.0
const DIE_MARGIN := 4.0
const DIE_CORNER_RADIUS := 4.0
const MAX_DICE_PER_ROW := 7
const ROW_HEIGHT := DIE_SIZE + DIE_MARGIN
const ANIM_DURATION := 0.6  # Total animation time in seconds
const ANIM_CYCLE_INTERVAL := 0.06  # How fast dice cycle during animation
const SETTLE_STAGGER := 0.04  # Stagger between each die settling
const DISPLAY_DURATION := 4.0  # How long to show results before fading

# Sound trigger tracking
var _sound_tick_elapsed: float = 0.0
var _settled_dice_count: int = 0  # Track how many dice have settled (for sound triggers)

# Colors
const COLOR_CRITICAL := Color(1.0, 0.84, 0.0)  # Gold for 6s
const COLOR_FUMBLE := Color(0.9, 0.15, 0.15)  # Red for 1s
const COLOR_SUCCESS := Color(0.2, 0.75, 0.2)  # Green for success
const COLOR_FAIL := Color(0.35, 0.35, 0.4)  # Dark gray for failure
const COLOR_DIE_TEXT := Color(1.0, 1.0, 1.0)  # White text
const COLOR_DIE_TEXT_DARK := Color(0.1, 0.1, 0.1)  # Dark text for gold dice
const COLOR_CONTEXT_LABEL := Color(0.7, 0.7, 0.8)  # Label color

# Reroll comparison colors
const COLOR_REROLL_OLD_BG := Color(0.3, 0.2, 0.2)  # Dimmed dark red for original dice
const COLOR_REROLL_ARROW := Color(1.0, 0.84, 0.0)  # Gold arrow between old/new
const ARROW_WIDTH := 16.0  # Width of the arrow separator between old and new dice

# State
var _dice_data: Array = []  # Array of {value: int, color: Color, settled: bool, display_value: int}
var _original_dice_data: Array = []  # Original dice for reroll comparison display
var _threshold: int = 0
var _context: String = ""
var _is_animating: bool = false
var _is_reroll_comparison: bool = false  # True when showing old → new side-by-side
var _anim_elapsed: float = 0.0
var _fade_alpha: float = 1.0
var _fade_tween: Tween = null
var _display_timer: Timer = null
var _context_label: String = ""

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_timer = Timer.new()
	_display_timer.one_shot = true
	_display_timer.timeout.connect(_start_fade_out)
	add_child(_display_timer)

func _process(delta: float) -> void:
	if not _is_animating:
		return

	_anim_elapsed += delta
	_sound_tick_elapsed += delta

	# Play rolling tick sound during cycling phase
	if _sound_tick_elapsed >= ANIM_CYCLE_INTERVAL:
		_sound_tick_elapsed = 0.0
		var sm = _get_sound_manager()
		if sm:
			sm.play_roll_tick()

	# Cycle through random values for unsettled dice
	var any_unsettled := false
	for i in range(_dice_data.size()):
		var die = _dice_data[i]
		if die.settled:
			continue

		# Each die settles at a staggered time
		var settle_time = ANIM_DURATION * 0.5 + i * SETTLE_STAGGER
		if _anim_elapsed >= settle_time:
			die.display_value = die.value
			die.settled = true
			_settled_dice_count += 1
			# Play settle sound + critical audio cues
			_play_die_settle_sound(die.value)
		else:
			# Cycle through random values
			die.display_value = randi_range(1, 6)
			any_unsettled = true

	if not any_unsettled:
		_is_animating = false
		# Play result sound based on overall outcome
		_play_result_sound()
		# Start display timer before fade-out
		_display_timer.start(DISPLAY_DURATION)

	queue_redraw()

func _draw() -> void:
	if _dice_data.is_empty():
		return

	# Apply fade alpha
	var alpha = _fade_alpha

	# Draw context label at the top
	if not _context_label.is_empty():
		var font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
		var font_size = 11
		var label_color = Color(COLOR_CONTEXT_LABEL, alpha)
		draw_string(font, Vector2(2, font_size), _context_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)

	# Y offset for dice (below label)
	var y_offset = 16.0

	var use_retro := false
	var _settings = get_tree().root.get_node_or_null("/root/SettingsService") if is_inside_tree() else null
	if _settings:
		use_retro = _settings.retro_mode

	# Reroll comparison mode: draw original dice (dimmed + strikethrough), arrow, then new dice
	if _is_reroll_comparison and not _original_dice_data.is_empty():
		_draw_reroll_comparison(y_offset, alpha, use_retro)
		return

	# Standard single-roll display
	_draw_dice_set(_dice_data, 0.0, y_offset, alpha, use_retro, false)

func _draw_reroll_comparison(y_offset: float, alpha: float, use_retro: bool) -> void:
	"""Draw original dice (dimmed) → arrow → new dice side-by-side."""
	# Draw original dice (dimmed with strikethrough)
	_draw_dice_set(_original_dice_data, 0.0, y_offset, alpha, use_retro, true)

	# Calculate x position after original dice
	var old_width = _original_dice_data.size() * (DIE_SIZE + DIE_MARGIN)

	# Draw arrow separator
	var arrow_x = old_width + 2.0
	var arrow_y = y_offset + DIE_SIZE * 0.5
	var arrow_color = Color(COLOR_REROLL_ARROW, alpha)
	var font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
	var arrow_font_size = 14
	draw_string(font, Vector2(arrow_x, arrow_y + arrow_font_size * 0.35), "->", HORIZONTAL_ALIGNMENT_LEFT, -1, arrow_font_size, arrow_color)

	# Draw new dice after the arrow
	var new_x_offset = old_width + ARROW_WIDTH + 4.0
	_draw_dice_set(_dice_data, new_x_offset, y_offset, alpha, use_retro, false)

func _draw_dice_set(dice_set: Array, x_offset: float, y_offset: float, alpha: float, use_retro: bool, is_old: bool) -> void:
	"""Draw a set of dice at the given offset. If is_old, draw dimmed with strikethrough."""
	for i in range(dice_set.size()):
		var die = dice_set[i]
		var col = i % MAX_DICE_PER_ROW
		var row = i / MAX_DICE_PER_ROW

		var x = x_offset + col * (DIE_SIZE + DIE_MARGIN)
		var y = y_offset + row * ROW_HEIGHT

		var rect = Rect2(x, y, DIE_SIZE, DIE_SIZE)

		# Background color — dimmed for old dice
		var bg_color: Color
		if is_old:
			bg_color = COLOR_REROLL_OLD_BG
		elif die.settled:
			bg_color = _get_die_color(die.value)
		else:
			bg_color = Color(0.5, 0.5, 0.6)

		# Reduce alpha for old dice to make them look faded
		var die_alpha = alpha * 0.5 if is_old else alpha
		bg_color.a = die_alpha

		if use_retro:
			draw_rect(rect, Color(0.0, 0.0, 0.0, die_alpha * 0.7))
			var inner = Rect2(x + 2, y + 2, DIE_SIZE - 4, DIE_SIZE - 4)
			draw_rect(inner, bg_color)

			var pip_color: Color
			if not is_old and die.settled and die.value == 6:
				pip_color = Color(COLOR_DIE_TEXT_DARK, die_alpha)
			else:
				pip_color = Color(COLOR_DIE_TEXT, die_alpha)
			_draw_pixel_pips(x, y, die.display_value, pip_color)
		else:
			var style = StyleBoxFlat.new()
			style.bg_color = bg_color
			style.set_corner_radius_all(DIE_CORNER_RADIUS)
			style.set_border_width_all(1)
			style.border_color = Color(0.0, 0.0, 0.0, die_alpha * 0.5)
			draw_style_box(style, rect)

			var font = FactionPalettes.FONT_RAJDHANI_SEMIBOLD
			var font_size = 16
			var text = str(die.display_value)
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var text_x = x + (DIE_SIZE - text_size.x) * 0.5
			var text_y = y + (DIE_SIZE + text_size.y * 0.65) * 0.5

			var text_color: Color
			if not is_old and die.settled and die.value == 6:
				text_color = Color(COLOR_DIE_TEXT_DARK, die_alpha)
			else:
				text_color = Color(COLOR_DIE_TEXT, die_alpha)

			# Glow for new dice criticals during animation
			if not is_old and die.settled and _is_animating and die.value == 6:
				var glow_rect = Rect2(x - 2, y - 2, DIE_SIZE + 4, DIE_SIZE + 4)
				var glow_style = StyleBoxFlat.new()
				glow_style.bg_color = Color(1.0, 0.84, 0.0, die_alpha * 0.3)
				glow_style.set_corner_radius_all(DIE_CORNER_RADIUS + 2)
				draw_style_box(glow_style, glow_rect)

			draw_string(font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

			# Strikethrough for old dice, X for natural 1s on new dice
			if is_old:
				# Diagonal strikethrough on old dice
				var line_color = Color(1.0, 0.3, 0.3, die_alpha * 0.8)
				draw_line(Vector2(x + 3, y + DIE_SIZE - 3), Vector2(x + DIE_SIZE - 3, y + 3), line_color, 2.0)
			elif die.settled and die.value == 1:
				var line_color = Color(1.0, 1.0, 1.0, die_alpha * 0.3)
				draw_line(Vector2(x + 4, y + 4), Vector2(x + DIE_SIZE - 4, y + DIE_SIZE - 4), line_color, 1.0)
				draw_line(Vector2(x + DIE_SIZE - 4, y + 4), Vector2(x + 4, y + DIE_SIZE - 4), line_color, 1.0)

func _draw_pixel_pips(x: float, y: float, value: int, color: Color) -> void:
	# Draw pixel-art pip dots on a die face (like real dice pips)
	var pip_size = 4.0
	var cx = x + DIE_SIZE * 0.5
	var cy = y + DIE_SIZE * 0.5
	var offset = DIE_SIZE * 0.25

	# Center pip
	if value == 1 or value == 3 or value == 5:
		draw_rect(Rect2(cx - pip_size / 2, cy - pip_size / 2, pip_size, pip_size), color)
	# Top-left and bottom-right
	if value >= 2:
		draw_rect(Rect2(cx - offset - pip_size / 2, cy - offset - pip_size / 2, pip_size, pip_size), color)
		draw_rect(Rect2(cx + offset - pip_size / 2, cy + offset - pip_size / 2, pip_size, pip_size), color)
	# Top-right and bottom-left
	if value >= 4:
		draw_rect(Rect2(cx + offset - pip_size / 2, cy - offset - pip_size / 2, pip_size, pip_size), color)
		draw_rect(Rect2(cx - offset - pip_size / 2, cy + offset - pip_size / 2, pip_size, pip_size), color)
	# Middle-left and middle-right
	if value == 6:
		draw_rect(Rect2(cx - offset - pip_size / 2, cy - pip_size / 2, pip_size, pip_size), color)
		draw_rect(Rect2(cx + offset - pip_size / 2, cy - pip_size / 2, pip_size, pip_size), color)


# ============================================================================
# Sound Helpers
# ============================================================================

func _get_sound_manager() -> Node:
	"""Safely get DiceSoundManager autoload (avoids compile-time identifier issues)."""
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("/root/DiceSoundManager")

func _play_die_settle_sound(value: int) -> void:
	"""Play appropriate sound when a single die settles."""
	var sm = _get_sound_manager()
	if not sm:
		return
	sm.play_settle()
	# Critical hit (natural 6) — extra chime
	if value == 6:
		sm.play_critical_success()
	# Fumble (natural 1) — low buzz
	elif value == 1:
		sm.play_critical_failure()

func _play_result_sound() -> void:
	"""Play overall result sound when all dice have settled."""
	var sm = _get_sound_manager()
	if not sm:
		return
	if _dice_data.is_empty():
		return

	# Count successes vs failures based on threshold
	if _threshold <= 0:
		# No threshold (charge rolls etc.) — no result sound
		return

	var successes := 0
	var failures := 0
	for die in _dice_data:
		if die.value >= _threshold:
			successes += 1
		else:
			failures += 1

	if successes > failures:
		sm.play_result_success()
	elif failures > 0:
		sm.play_result_failure()

func show_dice_roll(dice_data: Dictionary) -> void:
	var context = dice_data.get("context", "")

	# Skip non-roll contexts
	if context in ["resolution_start", "weapon_progress", "variable_damage", "auto_hit"]:
		return

	# Skip feel_no_pain (handled separately in log but we can still animate it)
	var rolls_raw = dice_data.get("rolls_raw", [])
	if rolls_raw.is_empty():
		return

	# Cancel any ongoing animation/fade
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_display_timer.stop()

	# Clear any reroll comparison state
	_is_reroll_comparison = false
	_original_dice_data.clear()

	# Parse threshold
	var threshold_str = dice_data.get("threshold", "")
	_threshold = int(threshold_str.replace("+", "")) if not threshold_str.is_empty() else 0
	_context = context

	# Build context label
	match context:
		"to_hit":
			_context_label = "Hit Rolls (need %s)" % threshold_str
		"to_wound":
			_context_label = "Wound Rolls (need %s)" % threshold_str
		"save_roll":
			_context_label = "Save Rolls (need %s)" % threshold_str
		"feel_no_pain":
			var fnp_val = dice_data.get("fnp_value", 0)
			_context_label = "Feel No Pain (%d+)" % fnp_val
			_threshold = fnp_val
		"charge_roll":
			_context_label = "Charge Roll (2D6)"
		_:
			if threshold_str.is_empty():
				_context_label = context.capitalize().replace("_", " ")
			else:
				_context_label = "%s (need %s)" % [context.capitalize().replace("_", " "), threshold_str]

	# Build dice array
	_dice_data.clear()
	for roll_value in rolls_raw:
		_dice_data.append({
			"value": roll_value,
			"display_value": randi_range(1, 6),
			"color": Color.WHITE,
			"settled": false
		})

	# Calculate needed height
	var num_rows = ceili(float(_dice_data.size()) / MAX_DICE_PER_ROW)
	custom_minimum_size.y = 16.0 + num_rows * ROW_HEIGHT + 4.0

	# Reset state and start animation
	_fade_alpha = 1.0
	_anim_elapsed = 0.0
	_sound_tick_elapsed = 0.0
	_settled_dice_count = 0
	_is_animating = true
	visible = true
	queue_redraw()

	print("DiceRollVisual: Showing %d dice for %s (threshold %s)" % [_dice_data.size(), context, threshold_str])

func show_reroll_comparison(original_rolls: Array, new_rolls: Array, context: String = "", threshold_str: String = "") -> void:
	"""Show original dice and new dice side-by-side for Command Re-roll visualization.
	Original dice appear dimmed with a strikethrough, followed by an arrow, then animated new dice."""
	if original_rolls.is_empty() or new_rolls.is_empty():
		return

	# Cancel any ongoing animation/fade
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_display_timer.stop()

	# Parse threshold
	_threshold = int(threshold_str.replace("+", "")) if not threshold_str.is_empty() else 0
	_context = context
	_is_reroll_comparison = true

	# Build context label
	match context:
		"charge_roll":
			_context_label = "COMMAND RE-ROLL: Charge (2D6)"
		"advance_roll":
			_context_label = "COMMAND RE-ROLL: Advance (D6)"
		"battle_shock_test":
			_context_label = "COMMAND RE-ROLL: Battle-shock (2D6)"
		_:
			_context_label = "COMMAND RE-ROLL: %s" % context.capitalize().replace("_", " ")

	# Build original dice array (already settled, no animation)
	_original_dice_data.clear()
	for roll_value in original_rolls:
		_original_dice_data.append({
			"value": roll_value,
			"display_value": roll_value,
			"color": Color.WHITE,
			"settled": true
		})

	# Build new dice array (animated)
	_dice_data.clear()
	for roll_value in new_rolls:
		_dice_data.append({
			"value": roll_value,
			"display_value": randi_range(1, 6),
			"color": Color.WHITE,
			"settled": false
		})

	# Calculate needed height — dice are on one row since rerolls are typically 1-2 dice
	var num_rows = 1
	custom_minimum_size.y = 16.0 + num_rows * ROW_HEIGHT + 4.0

	# Calculate needed width: old dice + arrow + new dice
	var total_dice_width = (original_rolls.size() + new_rolls.size()) * (DIE_SIZE + DIE_MARGIN) + ARROW_WIDTH + 4.0
	custom_minimum_size.x = max(custom_minimum_size.x, total_dice_width)

	# Reset state and start animation
	_fade_alpha = 1.0
	_anim_elapsed = 0.0
	_sound_tick_elapsed = 0.0
	_settled_dice_count = 0
	_is_animating = true
	visible = true
	queue_redraw()

	print("DiceRollVisual: Showing reroll comparison %s → %s for %s" % [str(original_rolls), str(new_rolls), context])

func _get_die_color(value: int) -> Color:
	# When no threshold (e.g. charge rolls), use neutral blue tones
	if _threshold <= 0:
		if value == 6:
			return COLOR_CRITICAL  # Gold for 6s
		elif value == 1:
			return COLOR_FUMBLE  # Red for 1s
		else:
			return Color(0.25, 0.45, 0.7)  # Neutral blue

	if value == 6:
		return COLOR_CRITICAL  # Gold for criticals
	elif value == 1:
		return COLOR_FUMBLE  # Red for natural 1s
	elif value >= _threshold:
		return COLOR_SUCCESS  # Green for success
	else:
		return COLOR_FAIL  # Gray for failure

func _start_fade_out() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "_fade_alpha", 0.0, 1.0).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_on_fade_complete)

func _on_fade_complete() -> void:
	visible = false
	_dice_data.clear()
	_original_dice_data.clear()
	_is_reroll_comparison = false
	queue_redraw()

# Allow external callers to force-clear the display
func clear_display() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_display_timer.stop()
	_is_animating = false
	_dice_data.clear()
	_original_dice_data.clear()
	_is_reroll_comparison = false
	_fade_alpha = 1.0
	visible = false
	queue_redraw()
