extends AcceptDialog

# CounterOffensiveDialog - UI for Counter-Offensive stratagem during Fight phase
#
# COUNTEROFFENSIVE (11e Core Stratagem 15.12, 2 CP)
# WHEN: Fight step of your opponent's Fight phase, just after an enemy unit has
#       resolved its attacks.
# TARGET: One friendly unit that is eligible to fight.
# EFFECT: Until the end of the phase, your unit has the Fights First ability and
#         it must be the next unit you select to fight (12.04).
#
# (The 10e wording this dialog used to print — "within Engagement Range … your
# unit fights next" — was retired with the rest of the 10e core set.)
#
# 19.01: "an attached unit is a single unit for all rules purposes", so the rows
# below are ATTACHED units, not raw unit dicts: a bodyguard leading a CHARACTER
# gets ONE row ("Custodian Guard + Blade Champion") and picking it activates the
# whole thing. The list arrives pre-folded from
# StratagemManager.get_counter_offensive_eligible_units.
#
# Shows eligible units with "Use" buttons and a "Decline" button.

signal counter_offensive_used(unit_id: String, player: int)
signal counter_offensive_declined(player: int)

var player: int = 0
var eligible_units: Array = []  # Array of { unit_id: String, unit_name: String }

# MA-42: Auto-decline timer
const AUTO_DECLINE_SECONDS: float = 5.0
var _countdown_timer: Timer = null
var _countdown_label: Label = null
var _time_remaining: float = AUTO_DECLINE_SECONDS

func setup(p_player: int, p_eligible_units: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	player = p_player
	eligible_units = p_eligible_units

	title = "Counter-Offensive Available - Player %d" % player
	min_size = DialogConstants.MEDIUM

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	# Named (like AttackAssignmentDialog's "Content") so windowed scenarios can
	# address the rows below by a stable path instead of "@VBoxContainer@12".
	main_container.name = "Content"
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
	subheader.text = "Core Stratagem - 15.12"
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
	effect_label.text = "An enemy unit has just resolved its attacks. Until the end of the phase, the unit you select has the Fights First ability and must be the next unit you select to fight."
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
	scroll.name = "UnitScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 120)
	var unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"

	for unit_info in eligible_units:
		var unit_container = HBoxContainer.new()
		# One row per ATTACHED unit (19.01), addressed by the id that activates
		# it — the bodyguard's, never an attached character's.
		unit_container.name = "CO_%s" % unit_info.unit_id

		var name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.text = unit_info.unit_name
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_container.add_child(name_label)

		var use_button = Button.new()
		use_button.name = "UseButton"
		use_button.text = "Fight Next (2 CP)"
		use_button.custom_minimum_size = Vector2(150, 30)
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
	_countdown_label.add_theme_font_size_override("font_size", 17)
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
		print("CounterOffensiveDialog: Auto-declining after %d seconds" % int(AUTO_DECLINE_SECONDS))
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
	print("CounterOffensiveDialog: Player %d uses COUNTER-OFFENSIVE on %s (%s)" % [player, unit_name, unit_id])
	emit_signal("counter_offensive_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	print("CounterOffensiveDialog: Player %d declines COUNTER-OFFENSIVE" % player)
	emit_signal("counter_offensive_declined", player)
	hide()
	queue_free()
