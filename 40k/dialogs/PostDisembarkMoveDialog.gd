extends AcceptDialog
class_name PostDisembarkMoveDialog

# Shown right after a unit disembarks from a transport that had NOT moved this
# phase (11e 18.04 "tactical" disembark). In that case the unit is SELECTED TO
# MAKE a normal or advance move — i.e. it can still move. The move was being
# offered *silently*, so players kept pressing the movement phase's "Confirm
# Move" button believing it finalised the disembark. That ends the move at 0"
# and locks the unit ("it says the unit has moved and I cannot move them").
#
# This dialog makes the choice explicit and unmissable: the disembarked unit can
# still make a normal MOVE, ADVANCE (18.04 "a normal or advance move"), or STAY
# where it was set up.
#
# Node layout (stable paths for scenario/UI tests):
#   PostDisembarkMoveDialog/Content/ButtonBar/MoveButton
#   PostDisembarkMoveDialog/Content/ButtonBar/AdvanceButton
#   PostDisembarkMoveDialog/Content/ButtonBar/StayButton

signal move_unit_chosen(unit_id: String)
signal advance_unit_chosen(unit_id: String)
signal stay_here_chosen(unit_id: String)

var _unit_id: String = ""
var _decided: bool = false

func setup(unit_id: String, unit_name: String, move_inches: int) -> void:
	_unit_id = unit_id

	title = "Disembarked — This Unit Can Still Move"
	# We drive the choice with our own explicit buttons, so hide the default OK.
	dialog_hide_on_ok = false
	get_ok_button().visible = false
	# Apply the shared parchment/gold dialog theme (global class).
	WhiteDwarfTheme.apply_to_dialog(self)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)
	add_child(content)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "%s DISEMBARKED" % unit_name.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	content.add_child(heading)

	var body := Label.new()
	body.name = "Body"
	body.text = ("The transport hadn't moved, so %s can still make a normal or advance move this phase.\n\n"
		+ "• Move This Unit — a normal move (up to %d\"): drag its models, then press End This Unit's Move.\n"
		+ "• Advance — roll a D6 and add it to the move (unit can't shoot or charge this turn).\n"
		+ "• Keep Them Here — leave the unit where it disembarked (it will count as having moved).") % [unit_name, move_inches]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	content.add_child(body)

	var button_bar := HBoxContainer.new()
	button_bar.name = "ButtonBar"
	button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	button_bar.add_theme_constant_override("separation", 12)
	content.add_child(button_bar)

	var move_button := Button.new()
	move_button.name = "MoveButton"
	move_button.text = "Move This Unit"
	move_button.tooltip_text = "Make a normal move: keep this unit selected so you can drag it, then press End This Unit's Move when done."
	WhiteDwarfTheme.apply_primary_button(move_button)
	move_button.pressed.connect(_on_move_pressed)
	button_bar.add_child(move_button)

	var advance_button := Button.new()
	advance_button.name = "AdvanceButton"
	advance_button.text = "Advance (roll D6)"
	advance_button.tooltip_text = "Roll a D6 and add it to this unit's Move for a longer move. The unit cannot shoot or charge this turn."
	WhiteDwarfTheme.apply_primary_button(advance_button)
	advance_button.pressed.connect(_on_advance_pressed)
	button_bar.add_child(advance_button)

	var stay_button := Button.new()
	stay_button.name = "StayButton"
	stay_button.text = "Keep Them Here"
	stay_button.tooltip_text = "End this unit's move without moving it further (it stays where it disembarked)."
	WhiteDwarfTheme.apply_secondary_button(stay_button)
	stay_button.pressed.connect(_on_stay_pressed)
	button_bar.add_child(stay_button)

	# Closing via the window chrome is the safe default: leave the unit selected
	# and still able to move (nothing is lost).
	close_requested.connect(_on_close)
	canceled.connect(_on_close)

func _on_move_pressed() -> void:
	if _decided:
		return
	_decided = true
	emit_signal("move_unit_chosen", _unit_id)
	hide()
	queue_free()

func _on_advance_pressed() -> void:
	if _decided:
		return
	_decided = true
	emit_signal("advance_unit_chosen", _unit_id)
	hide()
	queue_free()

func _on_stay_pressed() -> void:
	if _decided:
		return
	_decided = true
	emit_signal("stay_here_chosen", _unit_id)
	hide()
	queue_free()

func _on_close() -> void:
	# Treated the same as "Move This Unit": the safe default that never silently
	# discards the offered move.
	if _decided:
		return
	_decided = true
	emit_signal("move_unit_chosen", _unit_id)
	queue_free()
