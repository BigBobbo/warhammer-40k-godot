extends AcceptDialog

# UnitSwitchConfirmDialog - asks the player whether to switch the active unit
# when they click a different friendly unit's model on the board while the
# currently active unit is mid-interaction (an unconfirmed move in the
# Movement phase, staged target assignments in the Shooting phase).
#
# The consequence line is provided by the spawning controller so the player
# always knows what happens to the in-progress work ("...move will be
# confirmed" / "...assignments will be discarded").
#
# Structured like CommandRerollDialog: stable node names so windowed
# scenarios can drive /root/UnitSwitchConfirmDialog/Content/ButtonRow/*.

signal switch_confirmed(target_unit_id: String)
signal switch_declined(target_unit_id: String)

var target_unit_id: String = ""
var _answered: bool = false

func setup(current_unit_name: String, target_unit_name: String, p_target_unit_id: String, consequence_text: String) -> void:
	# Stable node name so windowed scenarios can address the dialog and its
	# buttons regardless of which controller spawned it.
	name = "UnitSwitchConfirmDialog"
	WhiteDwarfTheme.apply_to_dialog(self)
	target_unit_id = p_target_unit_id

	title = "Switch Unit?"
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# Closing via the window X / ESC counts as "keep the current unit".
	canceled.connect(_on_canceled)

	_build_ui(current_unit_name, target_unit_name, consequence_text)

func _build_ui(current_unit_name: String, target_unit_name: String, consequence_text: String) -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)
	main_container.add_theme_constant_override("separation", 8)

	# Header
	var header = Label.new()
	header.text = "SWITCH UNIT?"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Question
	var question_label = Label.new()
	question_label.name = "QuestionLabel"
	question_label.text = "Do you want to switch to %s?" % target_unit_name
	question_label.add_theme_font_size_override("font_size", 15)
	question_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(question_label)

	# Consequence for the unit that is mid-interaction
	if consequence_text != "":
		var consequence_label = Label.new()
		consequence_label.name = "ConsequenceLabel"
		consequence_label.text = consequence_text
		consequence_label.add_theme_font_size_override("font_size", 12)
		consequence_label.add_theme_color_override("font_color", Color(0.8, 0.65, 0.4))
		consequence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		consequence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		main_container.add_child(consequence_label)

	main_container.add_child(HSeparator.new())

	# Action buttons
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonRow"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 16)

	var switch_button = Button.new()
	switch_button.name = "SwitchButton"
	switch_button.text = "Switch to %s" % target_unit_name
	switch_button.custom_minimum_size = Vector2(170, 42)
	switch_button.pressed.connect(_on_switch_pressed)
	WhiteDwarfTheme.apply_primary_button(switch_button)
	button_container.add_child(switch_button)

	var stay_button = Button.new()
	stay_button.name = "StayButton"
	stay_button.text = "Keep %s" % current_unit_name
	stay_button.custom_minimum_size = Vector2(150, 42)
	stay_button.pressed.connect(_on_stay_pressed)
	WhiteDwarfTheme.apply_secondary_button(stay_button)
	button_container.add_child(stay_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_switch_pressed() -> void:
	if _answered:
		return
	_answered = true
	print("UnitSwitchConfirmDialog: Player chose to SWITCH to %s" % target_unit_id)
	emit_signal("switch_confirmed", target_unit_id)
	hide()
	queue_free()

func _on_stay_pressed() -> void:
	if _answered:
		return
	_answered = true
	print("UnitSwitchConfirmDialog: Player chose to KEEP the current unit (declined switch to %s)" % target_unit_id)
	emit_signal("switch_declined", target_unit_id)
	hide()
	queue_free()

func _on_canceled() -> void:
	if _answered:
		return
	_answered = true
	print("UnitSwitchConfirmDialog: Dialog dismissed — keeping the current unit")
	emit_signal("switch_declined", target_unit_id)
	queue_free()
