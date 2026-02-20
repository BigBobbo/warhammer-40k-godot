extends ColorRect
class_name PhaseTransitionBanner

# T5-V3: Phase Transition Animation Banner
# Shows an animated banner when the game phase changes.
# The banner slides in from the top, holds briefly, then slides out.
# Uses the WhiteDwarf gothic theme for consistent styling.

const SLIDE_IN_DURATION := 0.4
const HOLD_DURATION := 1.5
const SLIDE_OUT_DURATION := 0.35
const BANNER_HEIGHT := 80.0

# Phase display names and icons (unicode symbols for gothic feel)
static func _get_phase_display(phase: GameStateData.Phase) -> Dictionary:
	match phase:
		GameStateData.Phase.FORMATIONS: return {"name": "DECLARE BATTLE FORMATIONS", "icon": "\u2694"}
		GameStateData.Phase.DEPLOYMENT: return {"name": "DEPLOYMENT PHASE", "icon": "\u2693"}
		GameStateData.Phase.SCOUT: return {"name": "SCOUT MOVES", "icon": "\u21E8"}
		GameStateData.Phase.ROLL_OFF: return {"name": "ROLL OFF", "icon": "\u2684"}
		GameStateData.Phase.COMMAND: return {"name": "COMMAND PHASE", "icon": "\u2655"}
		GameStateData.Phase.MOVEMENT: return {"name": "MOVEMENT PHASE", "icon": "\u21C4"}
		GameStateData.Phase.SHOOTING: return {"name": "SHOOTING PHASE", "icon": "\u2316"}
		GameStateData.Phase.CHARGE: return {"name": "CHARGE PHASE", "icon": "\u2694"}
		GameStateData.Phase.FIGHT: return {"name": "FIGHT PHASE", "icon": "\u2620"}
		GameStateData.Phase.SCORING: return {"name": "SCORING PHASE", "icon": "\u2605"}
		GameStateData.Phase.MORALE: return {"name": "MORALE PHASE", "icon": "\u26A0"}
		_: return {"name": "UNKNOWN PHASE", "icon": "?"}

var _phase_label: Label
var _round_label: Label
var _left_line: ColorRect
var _right_line: ColorRect
var _tween: Tween = null
var _is_showing: bool = false

func _ready() -> void:
	# Full-width overlay bar, starts hidden above the screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent bg — we draw our own

	# Anchor to top of screen, full width
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = -BANNER_HEIGHT
	offset_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0

	# Banner background
	color = Color(0.08, 0.06, 0.04, 0.92)

	# Gold accent lines (top and bottom borders)
	var top_line = ColorRect.new()
	top_line.color = WhiteDwarfTheme.WH_GOLD
	top_line.anchor_left = 0.0
	top_line.anchor_right = 1.0
	top_line.anchor_top = 0.0
	top_line.anchor_bottom = 0.0
	top_line.offset_bottom = 2.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_line)

	var bottom_line = ColorRect.new()
	bottom_line.color = WhiteDwarfTheme.WH_GOLD
	bottom_line.anchor_left = 0.0
	bottom_line.anchor_right = 1.0
	bottom_line.anchor_top = 1.0
	bottom_line.anchor_bottom = 1.0
	bottom_line.offset_top = -2.0
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_line)

	# Decorative side lines (flanking the text)
	_left_line = ColorRect.new()
	_left_line.color = Color(WhiteDwarfTheme.WH_GOLD, 0.5)
	_left_line.anchor_left = 0.1
	_left_line.anchor_right = 0.35
	_left_line.anchor_top = 0.5
	_left_line.anchor_bottom = 0.5
	_left_line.offset_top = -1.0
	_left_line.offset_bottom = 1.0
	_left_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_line)

	_right_line = ColorRect.new()
	_right_line.color = Color(WhiteDwarfTheme.WH_GOLD, 0.5)
	_right_line.anchor_left = 0.65
	_right_line.anchor_right = 0.9
	_right_line.anchor_top = 0.5
	_right_line.anchor_bottom = 0.5
	_right_line.offset_top = -1.0
	_right_line.offset_bottom = 1.0
	_right_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_line)

	# Phase name label (centered, large)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_label.anchor_left = 0.0
	_phase_label.anchor_right = 1.0
	_phase_label.anchor_top = 0.0
	_phase_label.anchor_bottom = 0.7
	_phase_label.offset_top = 2.0
	_phase_label.add_theme_font_size_override("font_size", 28)
	_phase_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_label)

	# Round indicator label (smaller, below phase name)
	_round_label = Label.new()
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_round_label.anchor_left = 0.0
	_round_label.anchor_right = 1.0
	_round_label.anchor_top = 0.6
	_round_label.anchor_bottom = 1.0
	_round_label.offset_bottom = -4.0
	_round_label.add_theme_font_size_override("font_size", 13)
	_round_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_round_label)

	# Start hidden above screen
	visible = false
	modulate = Color(1, 1, 1, 0)

func show_phase_banner(phase: GameStateData.Phase, current_round: int = 1, active_player: int = 1) -> void:
	if _is_showing:
		# Kill current animation and reset immediately
		if _tween and _tween.is_valid():
			_tween.kill()
		_reset_position()

	_is_showing = true

	# Set phase text
	var phase_info = _get_phase_display(phase)
	_phase_label.text = "%s  %s  %s" % [phase_info.icon, phase_info.name, phase_info.icon]

	# Set round info
	_round_label.text = "Round %d  \u2022  Player %d Active" % [current_round, active_player]

	# Position above viewport (hidden)
	offset_top = -BANNER_HEIGHT
	offset_bottom = 0.0
	visible = true
	modulate = Color(1, 1, 1, 1)

	# Animate: slide in → hold → slide out
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()

	# Phase 1: Slide in from top
	_tween.tween_property(self, "offset_top", 0.0, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(self, "offset_bottom", BANNER_HEIGHT, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Phase 2: Hold
	_tween.tween_interval(HOLD_DURATION)

	# Phase 3: Slide out to top + fade
	_tween.tween_property(self, "offset_top", -BANNER_HEIGHT, SLIDE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(self, "offset_bottom", 0.0, SLIDE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(self, "modulate", Color(1, 1, 1, 0), SLIDE_OUT_DURATION).set_ease(Tween.EASE_IN)

	# Phase 4: Clean up
	_tween.tween_callback(_on_banner_complete)

	print("PhaseTransitionBanner: Showing banner for %s (Round %d, Player %d)" % [phase_info.name, current_round, active_player])

func _reset_position() -> void:
	offset_top = -BANNER_HEIGHT
	offset_bottom = 0.0
	visible = false
	modulate = Color(1, 1, 1, 0)
	_is_showing = false

func _on_banner_complete() -> void:
	visible = false
	modulate = Color(1, 1, 1, 0)
	_is_showing = false
	print("PhaseTransitionBanner: Banner animation complete")
