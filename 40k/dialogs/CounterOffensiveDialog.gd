extends AcceptDialog

# CounterOffensiveDialog - UI for Counter-Offensive stratagem during Fight phase
#
# COUNTER-OFFENSIVE (Core – Strategic Ploy Stratagem, 2 CP)
# WHEN: Fight phase, just after an enemy unit has fought.
# TARGET: One unit from your army that is within Engagement Range of one or more
#         enemy units and that has not already been selected to fight this phase.
# EFFECT: Your unit fights next.
# RESTRICTION: Once per phase.
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal counter_offensive_used(unit_id: String, player: int)
signal counter_offensive_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }

# DEFENDER CONTROL (2026-08-04): the 5-second MA-42 auto-decline countdown is
# gone. Picking who fights next means reading the melee on the board, and five
# seconds declined the stratagem out from under players who looked. The window
# now waits; see ReactiveDecisionUI.
var _countdown_label: Label = null
var _resolved: bool = false

func setup(p_player: int, p_eligible_units: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	player = p_player
	eligible_units = p_eligible_units

	title = "Counter-Offensive Available - Player %d" % player
	min_size = DialogConstants.MEDIUM

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# Non-exclusive on purpose: "exclusive" is the engine's nothing-else-may-see-
	# this-input mode, and the wheel-to-camera forwarding in _input() below is
	# verified against this non-exclusive configuration (2026-08-04, live). The
	# board is still un-clickable while the window is open — Main's full-screen
	# reactive overlay swallows every board/HUD click regardless.
	exclusive = false
	# Escape / window-X = Decline.
	close_requested.connect(_on_decline_pressed)
	canceled.connect(_on_decline_pressed)

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "COUNTER-OFFENSIVE"
	header.add_theme_font_size_override("font_size", 23)
	header.add_theme_color_override("font_color", Color.ORANGE_RED)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Core - Strategic Ploy Stratagem"
	subheader.add_theme_font_size_override("font_size", 16)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# CP info
	var cp_label = Label.new()
	var current_cp = StratagemManager.get_player_cp(player)
	cp_label.text = "Cost: 2 CP (You have %d CP)" % current_cp
	cp_label.add_theme_font_size_override("font_size", 18)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "An enemy unit has just fought. You may select one of your eligible units to fight next, overriding the normal alternation."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 17)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to fight next:"
	units_label.add_theme_font_size_override("font_size", 18)
	main_container.add_child(units_label)

	# Scrollable container for eligible units
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var unit_list = VBoxContainer.new()

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Fight Next (2 CP)"
		use_button.custom_minimum_size = Vector2(150, 30)
		use_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id))
		unit_container.add_child(use_button)

		unit_list.add_child(unit_container)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# "Examine Board" toggle — which melee to interrupt is a board question.
	ReactiveDecisionUI.add_examine_toggle(self, main_container, "Counter-Offensive")

	main_container.add_child(HSeparator.new())

	# Decline button
	var button_container = HBoxContainer.new()
	button_container.name = "Buttons"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(200, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	# Replaces the old auto-decline countdown.
	_countdown_label = ReactiveDecisionUI.window_hint_label(
		"Take your time — this window waits for you and nothing is declined automatically.")
	main_container.add_child(_countdown_label)

	add_child(main_container)

func _input(event: InputEvent) -> void:
	# Wheel notches over the board behind this window zoom the camera instead of
	# dying on the sub-window — see ReactiveDecisionUI.forward_camera_wheel.
	ReactiveDecisionUI.forward_camera_wheel(self, event)

func _on_use_pressed(unit_id: String) -> void:
	if _resolved:
		return
	_resolved = true
	ReactiveDecisionUI.stop_examining(self)
	var unit_name = ""
	for unit_info in eligible_units:
		if unit_info.unit_id == unit_id:
			unit_name = unit_info.unit_name
			break
	print("CounterOffensiveDialog: Player %d uses COUNTER-OFFENSIVE on %s (%s)" % [player, unit_name, unit_id])
	emit_signal("counter_offensive_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	# close_requested and canceled both land here (Escape / window-X).
	if _resolved:
		return
	_resolved = true
	ReactiveDecisionUI.stop_examining(self)
	print("CounterOffensiveDialog: Player %d declines COUNTER-OFFENSIVE" % player)
	emit_signal("counter_offensive_declined", player)
	hide()
	queue_free()
