extends AcceptDialog

# MomentShackleDialog - UI for the Blade Champion's Moment Shackle choice at the
# start of the Fight phase.
#
# MOMENT SHACKLE (Adeptus Custodes — Blade Champion datasheet ability)
# WHEN: Start of the Fight phase, before any unit fights (once per battle).
# EFFECT: Select one:
#   - Watcher's Axe gains +X Attacks (modelled as flags.moment_shackle_attacks_12)
#   - The bearer's unit gains a 2+ invulnerable save this phase
# Declining spends nothing.
#
# Before this dialog existed the choice was reachable only by the AI (via
# get_available_actions()), and the phase blocked on USE/DECLINE_MOMENT_SHACKLE
# — so a human Custodes player was soft-locked. This dialog is the missing UI.

signal moment_shackle_chosen(unit_id: String, choice: String, player: int)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""

func setup(p_unit_id: String, p_player: int) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	unit_id = p_unit_id
	player = p_player

	var unit = GameState.get_unit(unit_id)
	var _msd_meta = unit.get("meta", {})
	unit_name = _msd_meta.get("display_name", _msd_meta.get("name", unit_id))

	title = "Moment Shackle — %s" % unit_name
	min_size = DialogConstants.MEDIUM

	# Custom buttons only — hide the default OK.
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "MOMENT SHACKLE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	var subheader = Label.new()
	subheader.text = "Adeptus Custodes — Blade Champion (once per battle)"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	var unit_label = Label.new()
	unit_label.text = "%s — choose a Moment Shackle effect for this Fight phase:" % unit_name
	unit_label.add_theme_font_size_override("font_size", 14)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(unit_label)

	main_container.add_child(HSeparator.new())

	var button_container = VBoxContainer.new()
	button_container.name = "Buttons"

	# Attacks button
	var attacks_button = Button.new()
	attacks_button.name = "AttacksButton"
	attacks_button.text = "Watcher's Axe — 12 Attacks"
	attacks_button.custom_minimum_size = Vector2(400, 50)
	attacks_button.pressed.connect(_on_attacks_pressed)
	button_container.add_child(attacks_button)

	var attacks_desc = Label.new()
	attacks_desc.text = "The bearer's Watcher's Axe makes a fixed 12 Attacks this phase."
	attacks_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attacks_desc.add_theme_font_size_override("font_size", 11)
	attacks_desc.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	button_container.add_child(attacks_desc)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	button_container.add_child(spacer)

	# Invuln button
	var invuln_button = Button.new()
	invuln_button.name = "InvulnButton"
	invuln_button.text = "2+ Invulnerable Save"
	invuln_button.custom_minimum_size = Vector2(400, 50)
	invuln_button.pressed.connect(_on_invuln_pressed)
	button_container.add_child(invuln_button)

	var invuln_desc = Label.new()
	invuln_desc.text = "The bearer's unit has a 2+ invulnerable save this phase."
	invuln_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invuln_desc.add_theme_font_size_override("font_size", 11)
	invuln_desc.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	button_container.add_child(invuln_desc)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	button_container.add_child(spacer2)

	# Decline button
	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(400, 36)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)
	add_child(main_container)

func _on_attacks_pressed() -> void:
	print("MomentShackleDialog: Player %d — %s chooses 12 Attacks" % [player, unit_name])
	emit_signal("moment_shackle_chosen", unit_id, "attacks_12", player)
	hide()
	queue_free()

func _on_invuln_pressed() -> void:
	print("MomentShackleDialog: Player %d — %s chooses 2+ invuln" % [player, unit_name])
	emit_signal("moment_shackle_chosen", unit_id, "invuln_2", player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("MomentShackleDialog: Player %d — %s declines Moment Shackle" % [player, unit_name])
	emit_signal("moment_shackle_chosen", unit_id, "decline", player)
	hide()
	queue_free()
