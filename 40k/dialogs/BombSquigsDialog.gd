extends AcceptDialog

# BombSquigsDialog - UI for the Orks' Bomb Squigs reactive ability.
#
# BOMB SQUIGS (Orks — free, once per battle)
# WHEN: Movement phase, after a unit with Bomb Squigs makes a Normal move.
# EFFECT: Select one eligible enemy unit; it suffers D3 mortal wounds.
#
# Before this dialog existed the choice was reachable only by the AI (AIPlayer).
# A human player got no prompt — the phase set _bomb_squigs_pending_unit and
# emitted bomb_squigs_available, but the MovementController never listened, so
# the ability was unusable by a human (audit P1). This dialog is the missing UI.

signal bomb_squigs_chosen(actor_unit_id: String, target_unit_id: String, use_ability: bool)

var actor_unit_id: String = ""
var player: int = 0
var actor_name: String = ""
var eligible_targets: Array = []

func setup(p_actor_unit_id: String, p_player: int, p_targets: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	actor_unit_id = p_actor_unit_id
	player = p_player
	eligible_targets = p_targets

	var unit = GameState.get_unit(actor_unit_id)
	var _bsd_meta = unit.get("meta", {})
	actor_name = _bsd_meta.get("display_name", _bsd_meta.get("name", actor_unit_id))

	title = "Bomb Squigs — %s" % actor_name
	min_size = DialogConstants.MEDIUM

	get_ok_button().visible = false
	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.text = "BOMB SQUIGS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	var subheader = Label.new()
	subheader.text = "Orks — free (once per battle)"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	var prompt = Label.new()
	prompt.text = "%s can loose its Bomb Squigs — pick an enemy unit to suffer D3 mortal wounds:" % actor_name
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(prompt)

	main_container.add_child(HSeparator.new())

	var button_container = VBoxContainer.new()
	button_container.name = "Buttons"

	for t in eligible_targets:
		var tid := ""
		if t is Dictionary:
			tid = t.get("target_unit_id", "")
		else:
			tid = str(t)
		if tid == "":
			continue
		var tunit = GameState.get_unit(tid)
		var tname = tunit.get("meta", {}).get("display_name", tunit.get("meta", {}).get("name", tid))
		var tbtn = Button.new()
		tbtn.text = "Bomb Squigs → %s" % tname
		tbtn.custom_minimum_size = Vector2(400, 44)
		tbtn.pressed.connect(_on_target_pressed.bind(tid))
		button_container.add_child(tbtn)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	button_container.add_child(spacer)

	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(400, 36)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)
	add_child(main_container)

func _on_target_pressed(target_unit_id: String) -> void:
	print("BombSquigsDialog: %s bombs %s" % [actor_name, target_unit_id])
	emit_signal("bomb_squigs_chosen", actor_unit_id, target_unit_id, true)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("BombSquigsDialog: %s declines Bomb Squigs" % actor_name)
	emit_signal("bomb_squigs_chosen", actor_unit_id, "", false)
	hide()
	queue_free()
