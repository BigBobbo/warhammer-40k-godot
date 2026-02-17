extends Node

# ReplayUI - VCR-style controls overlay for game replay
#
# Creates and manages the replay control bar at the bottom of the screen,
# timeline scrubber, event description panel, and phase/turn indicators.
# All UI elements are built programmatically (no .tscn required).

const GameStateData = preload("res://autoloads/GameState.gd")

# References to the main scene (set by Main.gd when entering replay mode)
var main_scene: CanvasLayer = null

# UI containers
var replay_bar: PanelContainer = null
var event_description_panel: PanelContainer = null
var timeline_slider: HSlider = null

# Control buttons
var btn_step_back: Button = null
var btn_play_pause: Button = null
var btn_step_forward: Button = null
var btn_speed: Button = null
var btn_exit: Button = null

# Labels
var position_label: Label = null
var phase_label: Label = null
var event_label: RichTextLabel = null
var speed_label: Label = null
var round_label: Label = null

# State
var _is_scrubbing: bool = false

const PHASE_NAMES = {
	GameStateData.Phase.DEPLOYMENT: "Deployment",
	GameStateData.Phase.COMMAND: "Command",
	GameStateData.Phase.MOVEMENT: "Movement",
	GameStateData.Phase.SHOOTING: "Shooting",
	GameStateData.Phase.CHARGE: "Charge",
	GameStateData.Phase.FIGHT: "Fight",
	GameStateData.Phase.SCORING: "Scoring",
	GameStateData.Phase.MORALE: "Morale",
}

func _ready() -> void:
	_connect_replay_signals()

func setup(scene: CanvasLayer) -> void:
	"""Called by Main.gd to initialize the replay UI."""
	main_scene = scene
	_build_ui()
	_update_controls()
	print("ReplayUI: Setup complete")

func _connect_replay_signals() -> void:
	if ReplayManager:
		ReplayManager.playback_position_changed.connect(_on_position_changed)
		ReplayManager.replay_event_applied.connect(_on_event_applied)
		ReplayManager.playback_started.connect(_on_playback_started)
		ReplayManager.playback_paused.connect(_on_playback_paused)
		ReplayManager.playback_stopped.connect(_on_playback_stopped)

# ============================================================================
# UI Construction
# ============================================================================

func _build_ui() -> void:
	_build_replay_bar()
	_build_event_description_panel()

func _build_replay_bar() -> void:
	"""Build the bottom control bar with VCR controls and timeline."""
	# Main bar container
	replay_bar = PanelContainer.new()
	replay_bar.name = "ReplayBar"

	# Style the bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	bar_style.border_color = Color(0.6, 0.5, 0.2, 0.8)
	bar_style.border_width_top = 2
	bar_style.content_margin_left = 12
	bar_style.content_margin_right = 12
	bar_style.content_margin_top = 8
	bar_style.content_margin_bottom = 8
	replay_bar.add_theme_stylebox_override("panel", bar_style)

	# Position at bottom of screen
	replay_bar.anchor_left = 0.0
	replay_bar.anchor_right = 1.0
	replay_bar.anchor_top = 1.0
	replay_bar.anchor_bottom = 1.0
	replay_bar.offset_top = -100
	replay_bar.offset_bottom = 0

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	replay_bar.add_child(vbox)

	# Row 1: Timeline slider
	var timeline_row = HBoxContainer.new()
	timeline_row.add_theme_constant_override("separation", 8)
	vbox.add_child(timeline_row)

	position_label = Label.new()
	position_label.text = "0 / 0"
	position_label.custom_minimum_size = Vector2(80, 0)
	position_label.add_theme_font_size_override("font_size", 12)
	position_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	timeline_row.add_child(position_label)

	timeline_slider = HSlider.new()
	timeline_slider.min_value = -1
	timeline_slider.max_value = 0
	timeline_slider.value = -1
	timeline_slider.step = 1
	timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_slider.custom_minimum_size = Vector2(200, 20)
	timeline_slider.value_changed.connect(_on_timeline_value_changed)
	timeline_slider.drag_started.connect(func(): _is_scrubbing = true)
	timeline_slider.drag_ended.connect(_on_timeline_drag_ended)
	timeline_row.add_child(timeline_slider)

	round_label = Label.new()
	round_label.text = "Round 1"
	round_label.custom_minimum_size = Vector2(70, 0)
	round_label.add_theme_font_size_override("font_size", 12)
	round_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timeline_row.add_child(round_label)

	# Row 2: Controls
	var controls_row = HBoxContainer.new()
	controls_row.add_theme_constant_override("separation", 6)
	controls_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(controls_row)

	# Phase label (left side)
	phase_label = Label.new()
	phase_label.text = "Deployment Phase"
	phase_label.custom_minimum_size = Vector2(180, 0)
	phase_label.add_theme_font_size_override("font_size", 13)
	phase_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	controls_row.add_child(phase_label)

	# Spacer
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_child(spacer_left)

	# Step Back
	btn_step_back = _create_button("|<", "Step backward", 40)
	btn_step_back.pressed.connect(_on_step_back_pressed)
	controls_row.add_child(btn_step_back)

	# Play/Pause
	btn_play_pause = _create_button(">", "Play / Pause", 50)
	btn_play_pause.pressed.connect(_on_play_pause_pressed)
	controls_row.add_child(btn_play_pause)

	# Step Forward
	btn_step_forward = _create_button(">|", "Step forward", 40)
	btn_step_forward.pressed.connect(_on_step_forward_pressed)
	controls_row.add_child(btn_step_forward)

	# Speed button
	btn_speed = _create_button("1x", "Cycle playback speed", 45)
	btn_speed.pressed.connect(_on_speed_pressed)
	controls_row.add_child(btn_speed)

	# Spacer
	var spacer_right = Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_child(spacer_right)

	# Exit replay button
	btn_exit = _create_button("Exit Replay", "Return to main menu", 100)
	btn_exit.pressed.connect(_on_exit_pressed)
	var exit_style = StyleBoxFlat.new()
	exit_style.bg_color = Color(0.5, 0.15, 0.15, 0.9)
	exit_style.border_color = Color(0.8, 0.3, 0.3)
	exit_style.border_width_bottom = 1
	exit_style.border_width_top = 1
	exit_style.border_width_left = 1
	exit_style.border_width_right = 1
	exit_style.corner_radius_top_left = 4
	exit_style.corner_radius_top_right = 4
	exit_style.corner_radius_bottom_left = 4
	exit_style.corner_radius_bottom_right = 4
	exit_style.content_margin_left = 8
	exit_style.content_margin_right = 8
	exit_style.content_margin_top = 4
	exit_style.content_margin_bottom = 4
	btn_exit.add_theme_stylebox_override("normal", exit_style)
	controls_row.add_child(btn_exit)

	if main_scene:
		main_scene.add_child(replay_bar)

func _build_event_description_panel() -> void:
	"""Build the event description panel above the control bar."""
	event_description_panel = PanelContainer.new()
	event_description_panel.name = "EventDescPanel"

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.1, 0.9)
	panel_style.border_color = Color(0.4, 0.35, 0.15, 0.6)
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	event_description_panel.add_theme_stylebox_override("panel", panel_style)

	# Position above the replay bar
	event_description_panel.anchor_left = 0.1
	event_description_panel.anchor_right = 0.9
	event_description_panel.anchor_top = 1.0
	event_description_panel.anchor_bottom = 1.0
	event_description_panel.offset_top = -130
	event_description_panel.offset_bottom = -105

	event_label = RichTextLabel.new()
	event_label.bbcode_enabled = true
	event_label.fit_content = true
	event_label.scroll_active = false
	event_label.add_theme_font_size_override("normal_font_size", 13)
	event_label.text = "Game start - press > to begin replay"
	event_description_panel.add_child(event_label)

	if main_scene:
		main_scene.add_child(event_description_panel)

func _create_button(text: String, tooltip: String, min_width: float) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(min_width, 30)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.22, 0.9)
	style.border_color = Color(0.5, 0.45, 0.2, 0.7)
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.2, 0.2, 0.3, 0.95)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))

	return btn

# ============================================================================
# Button Handlers
# ============================================================================

func _on_step_back_pressed() -> void:
	if ReplayManager:
		ReplayManager.step_backward()
		# After stepping backward, request Main to refresh visuals
		if main_scene and main_scene.has_method("_replay_refresh_visuals"):
			main_scene._replay_refresh_visuals()

func _on_play_pause_pressed() -> void:
	if not ReplayManager:
		return
	ReplayManager.toggle_playback()

func _on_step_forward_pressed() -> void:
	if ReplayManager:
		ReplayManager.step_forward()
		# After stepping forward, request Main to refresh visuals
		if main_scene and main_scene.has_method("_replay_refresh_visuals"):
			main_scene._replay_refresh_visuals()

func _on_speed_pressed() -> void:
	if ReplayManager:
		var new_speed = ReplayManager.cycle_speed()
		btn_speed.text = _format_speed(new_speed)

func _on_exit_pressed() -> void:
	# Stop playback and return to main menu
	if ReplayManager:
		ReplayManager.stop_playback()
		ReplayManager.cleanup()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_timeline_value_changed(value: float) -> void:
	if _is_scrubbing and ReplayManager:
		# During drag, just update the position label
		var total = ReplayManager.get_total_events()
		position_label.text = "%d / %d" % [int(value) + 1, total]

func _on_timeline_drag_ended(value_changed: bool) -> void:
	_is_scrubbing = false
	if value_changed and ReplayManager:
		var target_pos = int(timeline_slider.value)
		ReplayManager.jump_to_position(target_pos)
		# Refresh visuals after jump
		if main_scene and main_scene.has_method("_replay_refresh_visuals"):
			main_scene._replay_refresh_visuals()

# ============================================================================
# Keyboard Input
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not ReplayManager or not ReplayManager.is_replay_loaded():
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				_on_play_pause_pressed()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_on_step_back_pressed()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_on_step_forward_pressed()
				get_viewport().set_input_as_handled()
			KEY_S:
				_on_speed_pressed()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_exit_pressed()
				get_viewport().set_input_as_handled()
			KEY_HOME:
				ReplayManager.jump_to_position(-1)
				if main_scene and main_scene.has_method("_replay_refresh_visuals"):
					main_scene._replay_refresh_visuals()
				get_viewport().set_input_as_handled()
			KEY_END:
				ReplayManager.jump_to_position(ReplayManager.get_total_events() - 1)
				if main_scene and main_scene.has_method("_replay_refresh_visuals"):
					main_scene._replay_refresh_visuals()
				get_viewport().set_input_as_handled()

# ============================================================================
# Signal Handlers
# ============================================================================

func _on_position_changed(position: int, total: int) -> void:
	if not _is_scrubbing:
		timeline_slider.max_value = total - 1
		timeline_slider.value = position
	position_label.text = "%d / %d" % [position + 1, total]
	_update_controls()

func _on_event_applied(event: Dictionary) -> void:
	var description = event.get("description", "")
	var event_type = event.get("type", "")

	# Color the description based on player
	var active_player = event.get("active_player", 0)
	if event_type == "phase_change":
		event_label.text = "[color=#ccb844]%s[/color]" % description
	elif event_type == "initial_state":
		event_label.text = "[color=#888888]%s[/color]" % description
	elif active_player == 1:
		event_label.text = "[color=#6688cc]%s[/color]" % description
	elif active_player == 2:
		event_label.text = "[color=#cc6644]%s[/color]" % description
	else:
		event_label.text = description

	# Update phase/round labels
	var phase_val = event.get("phase", event.get("new_phase", -1))
	if phase_val >= 0 and phase_val < PHASE_NAMES.size():
		phase_label.text = "%s Phase" % PHASE_NAMES.get(phase_val, "Unknown")

	var battle_round = event.get("battle_round", 0)
	if battle_round > 0:
		round_label.text = "Round %d" % battle_round

func _on_playback_started() -> void:
	btn_play_pause.text = "||"
	_update_controls()

func _on_playback_paused() -> void:
	btn_play_pause.text = ">"
	_update_controls()

func _on_playback_stopped() -> void:
	btn_play_pause.text = ">"
	_update_controls()

# ============================================================================
# UI State Updates
# ============================================================================

func _update_controls() -> void:
	if not ReplayManager:
		return

	btn_step_back.disabled = ReplayManager.is_at_start()
	btn_step_forward.disabled = ReplayManager.is_at_end()
	btn_speed.text = _format_speed(ReplayManager.get_playback_speed())

func _format_speed(speed: float) -> String:
	if speed == int(speed):
		return "%dx" % int(speed)
	return "%.1fx" % speed

# ============================================================================
# Cleanup
# ============================================================================

func teardown() -> void:
	"""Remove all replay UI elements."""
	if replay_bar and is_instance_valid(replay_bar):
		replay_bar.queue_free()
		replay_bar = null
	if event_description_panel and is_instance_valid(event_description_panel):
		event_description_panel.queue_free()
		event_description_panel = null
	print("ReplayUI: Teardown complete")
