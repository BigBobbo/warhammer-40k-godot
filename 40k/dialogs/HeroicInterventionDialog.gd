extends AcceptDialog

# HeroicInterventionDialog - UI for Heroic Intervention stratagem during opponent's charge
#
# HEROIC INTERVENTION (Core – Strategic Ploy Stratagem, 2 CP)
# WHEN: Your opponent's Charge phase, just after an enemy unit ends a Charge move.
# TARGET: One unit from your army within 6" of that enemy unit and not within
#         Engagement Range of any enemy units.
# EFFECT: Your unit declares a charge targeting only that enemy unit, then makes
#         a charge roll. It cannot be selected to fight in the Fights First step.
# RESTRICTION: Cannot select a VEHICLE unit unless it has the WALKER keyword.
#              Once per phase.
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal heroic_intervention_used(unit_id: String, player: int, mode: String)
signal heroic_intervention_declined(player: int)

var player: int = 0
var charging_unit_id: String = ""  # The enemy unit that just charged
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }
var charging_unit_name: String = ""

# MA-42: Auto-decline timer
const AUTO_DECLINE_SECONDS: float = 5.0
var _countdown_timer: Timer = null
var _countdown_label: Label = null
var _time_remaining: float = AUTO_DECLINE_SECONDS

func setup(p_player: int, p_charging_unit_id: String, p_eligible_units: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	player = p_player
	charging_unit_id = p_charging_unit_id
	eligible_units = p_eligible_units
	# Derive the display name from the charging unit
	var charging_unit = GameState.get_unit(charging_unit_id)
	var _hid_meta = charging_unit.get("meta", {})
	charging_unit_name = _hid_meta.get("display_name", _hid_meta.get("name", charging_unit_id))

	title = "Heroic Intervention Available - Player %d" % player

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "HEROIC INTERVENTION"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
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

	# CP info (1 CP at 11e, 2 CP at 10e)
	var cp_label = Label.new()
	var current_cp = StratagemManager.get_player_cp(player)
	var hi_cost := 1 if GameConstants.edition >= 11 else 2
	cp_label.text = "Cost: %d CP (You have %d CP)" % [hi_cost, current_cp]
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.add_theme_color_override("font_color", Color.CYAN)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Charging unit info (10e per-charge window) or the 11e end-of-phase window
	var target_label = Label.new()
	if charging_unit_id != "":
		target_label.text = "Enemy unit that charged: %s" % charging_unit_name
	else:
		target_label.text = "End of the enemy Charge phase"
	target_label.add_theme_font_size_override("font_size", 14)
	target_label.add_theme_color_override("font_color", Color.RED)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(target_label)

	# Trigger description
	var trigger_label = Label.new()
	if charging_unit_id != "":
		trigger_label.text = "%s has just completed a charge move. You may counter-charge with one of your eligible units." % charging_unit_name
	else:
		trigger_label.text = "All enemy charges are resolved. One of your eligible units may resolve a Heroic Intervention charge (15.11)."
	trigger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trigger_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(trigger_label)

	# Effect description
	var effect_label = Label.new()
	if GameConstants.edition >= 11:
		effect_label.text = "LEAP TO DEFEND: 2D6 charge at the closest enemy that charged this turn (within 12\").  INTO THE FRAY: 2D6 charge capped at 6\" at the closest enemy within 6\". The unit does NOT gain Fights First."
	else:
		effect_label.text = "Your unit will declare a charge targeting only that enemy unit and make a 2D6 charge roll. Note: The unit does NOT gain Fights First."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 12)
	effect_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_container.add_child(effect_label)

	main_container.add_child(HSeparator.new())

	# Eligible units section
	var units_label = Label.new()
	units_label.text = "Select a unit to counter-charge:"
	units_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(units_label)

	# Scrollable container for eligible units (stable names so windowed
	# scenarios can click the same affordances a player sees)
	var scroll = ScrollContainer.new()
	scroll.name = "UnitScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()
		unit_container.name = "Row_%s" % unit_info.unit_id

		var name_label = Label.new()
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		if GameConstants.edition >= 11:
			# 15.11 mode choice per unit
			var leap_button = Button.new()
			leap_button.name = "Leap_%s" % unit_info.unit_id
			leap_button.text = "Leap to Defend (1 CP)"
			leap_button.custom_minimum_size = Vector2(160, 30)
			leap_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id, "leap_to_defend"))
			unit_container.add_child(leap_button)

			var fray_button = Button.new()
			fray_button.name = "Fray_%s" % unit_info.unit_id
			fray_button.text = "Into the Fray (1 CP)"
			fray_button.custom_minimum_size = Vector2(160, 30)
			fray_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id, "into_the_fray"))
			unit_container.add_child(fray_button)
		else:
			var use_button = Button.new()
			use_button.name = "Use_%s" % unit_info.unit_id
			use_button.text = "Counter-Charge (2 CP)"
			use_button.custom_minimum_size = Vector2(170, 30)
			use_button.pressed.connect(_on_use_pressed.bind(unit_info.unit_id, "leap_to_defend"))
			unit_container.add_child(use_button)

		unit_list.add_child(unit_container)

	scroll.add_child(unit_list)
	main_container.add_child(scroll)

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

	# MA-42: Countdown timer display
	_countdown_label = Label.new()
	_countdown_label.text = "Auto-declining in %d seconds..." % int(AUTO_DECLINE_SECONDS)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 13)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	main_container.add_child(_countdown_label)

	add_child(main_container)

	# MA-42: Start auto-decline timer. setup() runs BEFORE the dialog is added
	# to the tree, so an explicit start() here fails ("Timer was not added to
	# the SceneTree") and the auto-decline never armed — autostart arms it the
	# moment the dialog enters the tree instead.
	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.autostart = true
	_countdown_timer.timeout.connect(_on_countdown_tick)
	_time_remaining = AUTO_DECLINE_SECONDS
	add_child(_countdown_timer)
	if is_inside_tree():
		_countdown_timer.start()

func _on_countdown_tick() -> void:
	_time_remaining -= 1.0
	if _time_remaining <= 0:
		_countdown_timer.stop()
		print("HeroicInterventionDialog: Auto-declining after %d seconds" % int(AUTO_DECLINE_SECONDS))
		_on_decline_pressed()
		return
	if is_instance_valid(_countdown_label):
		_countdown_label.text = "Auto-declining in %d seconds..." % int(_time_remaining)
		if _time_remaining <= 2:
			_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _on_use_pressed(unit_id: String, mode: String = "leap_to_defend") -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	var unit_name = ""
	for unit_info in eligible_units:
		if unit_info.unit_id == unit_id:
			unit_name = unit_info.unit_name
			break
	print("HeroicInterventionDialog: Player %d uses HEROIC INTERVENTION with %s (%s, mode: %s)" % [player, unit_name, unit_id, mode])
	emit_signal("heroic_intervention_used", unit_id, player, mode)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	print("HeroicInterventionDialog: Player %d declines HEROIC INTERVENTION" % player)
	emit_signal("heroic_intervention_declined", player)
	hide()
	queue_free()
