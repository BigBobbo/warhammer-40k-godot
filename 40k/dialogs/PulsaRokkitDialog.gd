extends AcceptDialog

# PulsaRokkitDialog - UI for the Orks' Pulsa Rokkit reactive ability.
#
# PULSA ROKKIT (Orks — once per battle)
# WHEN: Shooting phase, when the bearer's unit is selected to shoot.
# EFFECT: This unit's ranged weapons gain +1 Strength and +1 AP this phase.
#
# Before this dialog existed the choice had NO handler at all — the phase set
# awaiting_pulsa_rokkit and emitted pulsa_rokkit_available, but neither the
# ShootingController nor AIPlayer listened, so it blocked both players (audit
# P1). This dialog is the missing human UI (a matching AI auto-resolver is
# added in AIPlayer).

signal pulsa_rokkit_chosen(unit_id: String, use_ability: bool)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""

func setup(p_unit_id: String, p_player: int) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	unit_id = p_unit_id
	player = p_player

	var unit = GameState.get_unit(unit_id)
	var _prd_meta = unit.get("meta", {})
	unit_name = _prd_meta.get("display_name", _prd_meta.get("name", unit_id))

	title = "Pulsa Rokkit — %s" % unit_name
	min_size = DialogConstants.SMALL

	get_ok_button().visible = false
	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	var header = Label.new()
	header.text = "PULSA ROKKIT"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	var subheader = Label.new()
	subheader.text = "Orks — once per battle"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	var desc_label = Label.new()
	desc_label.text = "This unit's ranged weapons gain +1 Strength and +1 AP this phase."
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(desc_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_container.add_child(spacer)

	var unit_label = Label.new()
	unit_label.text = "%s is about to shoot. Fire the Pulsa Rokkit?" % unit_name
	unit_label.add_theme_font_size_override("font_size", 14)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(unit_label)

	main_container.add_child(HSeparator.new())

	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var use_button = Button.new()
	use_button.name = "UseButton"
	use_button.text = "Fire Pulsa Rokkit"
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
	print("PulsaRokkitDialog: Player %d fires Pulsa Rokkit for %s" % [player, unit_name])
	emit_signal("pulsa_rokkit_chosen", unit_id, true)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("PulsaRokkitDialog: Player %d declines Pulsa Rokkit for %s" % [player, unit_name])
	emit_signal("pulsa_rokkit_chosen", unit_id, false)
	hide()
	queue_free()
