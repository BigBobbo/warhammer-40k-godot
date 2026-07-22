extends AcceptDialog

# DistractionGrotDialog - UI for the Orks' Distraction Grot reactive save.
#
# DISTRACTION GROT (Orks — free reactive, once per battle)
# WHEN: Shooting phase, after a unit with a Grot Oiler / Distraction Grots is
#       selected as the target of an attack.
# EFFECT: Until the end of the phase, models in the target unit have a 5+
#         invulnerable save against the shooting.
#
# Before this dialog existed the choice was reachable only by the AI (via
# AIPlayer). When a human was the DEFENDER, ShootingPhase emitted
# distraction_grot_available but the ShootingController never listened — so the
# phase paused awaiting USE/DECLINE_DISTRACTION_GROT with no way for the human
# to respond (soft-lock). This dialog is the missing UI.

signal distraction_grot_chosen(unit_id: String, use_ability: bool)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""

func setup(p_unit_id: String, p_player: int) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	unit_id = p_unit_id
	player = p_player

	var unit = GameState.get_unit(unit_id)
	var _dgd_meta = unit.get("meta", {})
	unit_name = _dgd_meta.get("display_name", _dgd_meta.get("name", unit_id))

	title = "Distraction Grot — %s" % unit_name
	min_size = DialogConstants.SMALL

	# Custom buttons only — hide the default OK.
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	var header = Label.new()
	header.text = "DISTRACTION GROT"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	var subheader = Label.new()
	subheader.text = "Orks — free reactive (once per battle)"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	var desc_label = Label.new()
	desc_label.text = "Until the end of the phase, this unit has a 5+ invulnerable save against the incoming shooting."
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(desc_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_container.add_child(spacer)

	var unit_label = Label.new()
	unit_label.text = "%s is being shot at. Activate Distraction Grot for a 5+ invulnerable save?" % unit_name
	unit_label.add_theme_font_size_override("font_size", 14)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(unit_label)

	main_container.add_child(HSeparator.new())

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var use_button = Button.new()
	use_button.name = "UseButton"
	use_button.text = "Activate Distraction Grot"
	use_button.custom_minimum_size = Vector2(220, 50)
	use_button.pressed.connect(_on_use_pressed)
	button_container.add_child(use_button)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(btn_spacer)

	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(150, 50)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)
	add_child(main_container)

func _on_use_pressed() -> void:
	print("DistractionGrotDialog: Player %d activates Distraction Grot for %s" % [player, unit_name])
	emit_signal("distraction_grot_chosen", unit_id, true)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("DistractionGrotDialog: Player %d declines Distraction Grot for %s" % [player, unit_name])
	emit_signal("distraction_grot_chosen", unit_id, false)
	hide()
	queue_free()
