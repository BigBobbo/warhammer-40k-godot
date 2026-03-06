extends AcceptDialog

# RapidIngressDialog - UI for Rapid Ingress stratagem at the end of opponent's Movement phase
#
# RAPID INGRESS (Core – Strategic Ploy Stratagem, 1 CP)
# WHEN: End of your opponent's Movement phase.
# TARGET: One unit from your army that is in Reserves.
# EFFECT: Your unit can arrive on the battlefield as if it were the Reinforcements
#         step of your Movement phase.
# RESTRICTION: Cannot arrive in a battle round it normally wouldn't be able to.
#              Once per phase.
#
# Shows eligible reserve units with "Arrive" buttons and a "Decline" button.

signal rapid_ingress_used(unit_id: String, player: int)
signal rapid_ingress_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String, reserve_type: String }

# MA-42: Auto-decline timer
const AUTO_DECLINE_SECONDS: float = 5.0
var _countdown_timer: Timer = null
var _countdown_label: Label = null
var _time_remaining: float = AUTO_DECLINE_SECONDS

func setup(p_player: int, p_eligible_units: Array) -> void:
	player = p_player
	eligible_units = p_eligible_units

	title = "Rapid Ingress Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "RAPID INGRESS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.DODGER_BLUE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Core - Strategic Ploy Stratagem"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# CP info
	var cp_label = Label.new()
	var current_cp = StratagemManager.get_player_cp(player)
	cp_label.text = "Cost: 1 CP (You have %d CP)" % current_cp
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "Your opponent's Movement phase is ending. Select one of your reserve units to arrive on the battlefield as if it were the Reinforcements step of your Movement phase."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a reserve unit to bring in:"
	units_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(units_label)

	# Scrollable container for eligible units
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var unit_list = VBoxContainer.new()

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()

		var name_label = Label.new()
		var reserve_type = unit_info.get("reserve_type", "strategic_reserves")
		var type_tag = "[DS]" if reserve_type == "deep_strike" else "[SR]"
		name_label.text = "%s %s" % [type_tag, unit_info.unit_name]
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.text = "Arrive (1 CP)"
		use_button.custom_minimum_size = Vector2(170, 30)
		use_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id))
		unit_container.add_child(use_button)

		unit_list.add_child(unit_container)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Decline button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var decline_button = Button.new()
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(200, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	# MA-42: Countdown timer display
	_countdown_label = Label.new()
	_countdown_label.text = "Auto-declining in %d seconds..." % int(AUTO_DECLINE_SECONDS)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 13)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	main_container.add_child(_countdown_label)

	add_child(main_container)

	# MA-42: Start auto-decline timer
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)
	_time_remaining = AUTO_DECLINE_SECONDS
	_countdown_timer.start()

func _on_countdown_tick() -> void:
	_time_remaining -= 1.0
	if _time_remaining <= 0:
		_countdown_timer.stop()
		print("RapidIngressDialog: Auto-declining after %d seconds" % int(AUTO_DECLINE_SECONDS))
		_on_decline_pressed()
		return
	if is_instance_valid(_countdown_label):
		_countdown_label.text = "Auto-declining in %d seconds..." % int(_time_remaining)
		if _time_remaining <= 2:
			_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _on_use_pressed(unit_id: String) -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	var unit_name = ""
	for unit_info in eligible_units:
		if unit_info.unit_id == unit_id:
			unit_name = unit_info.unit_name
			break
	print("RapidIngressDialog: Player %d uses RAPID INGRESS with %s (%s)" % [player, unit_name, unit_id])
	emit_signal("rapid_ingress_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	print("RapidIngressDialog: Player %d declines RAPID INGRESS" % player)
	emit_signal("rapid_ingress_declined", player)
	hide()
	queue_free()
