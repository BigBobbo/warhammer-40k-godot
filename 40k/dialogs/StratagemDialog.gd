extends AcceptDialog
class_name StratagemDialog

# StratagemDialog - UI for reactive stratagem selection during opponent's shooting phase
#
# Shows available stratagems (Go to Ground, Smokescreen) to the defending player
# when their units are selected as targets. Player can choose to use one or decline.

signal stratagem_selected(stratagem_id: String, target_unit_id: String)
signal stratagem_declined()

var available_stratagems: Array = []  # Array of { stratagem: Dictionary, eligible_units: Array[String] }
var defending_player: int = 0
var target_unit_ids: Array = []
var selected_stratagem_id: String = ""
var selected_target_unit_id: String = ""

# MA-42: Auto-decline timer
const AUTO_DECLINE_SECONDS: float = 5.0
var _countdown_timer: Timer = null
var _countdown_label: Label = null
var _time_remaining: float = AUTO_DECLINE_SECONDS

func setup(player: int, stratagems: Array, targets: Array) -> void:
	defending_player = player
	available_stratagems = stratagems
	target_unit_ids = targets

	title = "Reactive Stratagems - Player %d" % player
	min_size = DialogConstants.MEDIUM

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "Your units are being targeted!"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color.YELLOW)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	var cp_label = Label.new()
	cp_label.text = "CP Available: %d" % StratagemManager.get_player_cp(defending_player)
	cp_label.add_theme_font_size_override("font_size", 14)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Scroll container for stratagem cards
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 180)

	var strat_container = VBoxContainer.new()

	for entry in available_stratagems:
		var strat = entry.stratagem
		var eligible_units = entry.eligible_units

		var card = _create_stratagem_card(strat, eligible_units)
		strat_container.add_child(card)
		strat_container.add_child(HSeparator.new())

	scroll.add_child(strat_container)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Decline button
	var decline_button = Button.new()
	decline_button.text = "Decline All Stratagems"
	decline_button.custom_minimum_size = Vector2(480, 35)
	decline_button.pressed.connect(_on_decline_pressed)
	main_container.add_child(decline_button)

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
		print("StratagemDialog: Auto-declining after %d seconds" % int(AUTO_DECLINE_SECONDS))
		_on_decline_pressed()
		return
	if is_instance_valid(_countdown_label):
		_countdown_label.text = "Auto-declining in %d seconds..." % int(_time_remaining)
		if _time_remaining <= 2:
			_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _create_stratagem_card(strat: Dictionary, eligible_units: Array) -> VBoxContainer:
	var card = VBoxContainer.new()

	# Stratagem name and cost
	var name_hbox = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = strat.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.CYAN)
	name_hbox.add_child(name_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(spacer)

	var cost_label = Label.new()
	cost_label.text = "%d CP" % strat.get("cp_cost", 0)
	cost_label.add_theme_font_size_override("font_size", 16)
	cost_label.add_theme_color_override("font_color", Color.GOLD)
	name_hbox.add_child(cost_label)

	card.add_child(name_hbox)

	# Type
	var type_label = Label.new()
	type_label.text = strat.get("type", "")
	type_label.add_theme_font_size_override("font_size", 11)
	type_label.add_theme_color_override("font_color", Color.GRAY)
	card.add_child(type_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = strat.get("effect_text", strat.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	card.add_child(desc_label)

	# Eligible unit buttons
	var units_label = Label.new()
	units_label.text = "Select target:"
	units_label.add_theme_font_size_override("font_size", 12)
	units_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	card.add_child(units_label)

	var button_container = HBoxContainer.new()
	for unit_id in eligible_units:
		var unit = GameState.get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		var use_button = Button.new()
		use_button.text = "Use on %s" % unit_name
		use_button.custom_minimum_size = Vector2(150, 30)
		use_button.pressed.connect(_on_use_pressed.bind(strat.get("id", ""), unit_id))
		button_container.add_child(use_button)

	card.add_child(button_container)

	return card

func _on_use_pressed(stratagem_id: String, target_unit_id: String) -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	selected_stratagem_id = stratagem_id
	selected_target_unit_id = target_unit_id
	print("StratagemDialog: Player %d selected %s on %s" % [defending_player, stratagem_id, target_unit_id])
	emit_signal("stratagem_selected", stratagem_id, target_unit_id)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	if _countdown_timer:
		_countdown_timer.stop()
	print("StratagemDialog: Player %d declined all reactive stratagems" % defending_player)
	emit_signal("stratagem_declined")
	hide()
	queue_free()
