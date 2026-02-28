extends AcceptDialog

# EpicChallengeDialog - UI for Epic Challenge stratagem during Fight phase
#
# EPIC CHALLENGE (Core – Epic Deed Stratagem, 1 CP)
# WHEN: Fight phase, when a CHARACTER unit from your army is selected to fight.
# TARGET: One CHARACTER model in your unit.
# EFFECT: Until end of phase, melee attacks made by that model have [PRECISION].
# RESTRICTION: Once per phase.
#
# Shows the player option to use Epic Challenge or decline before pile-in.

signal epic_challenge_used(unit_id: String, player: int)
signal epic_challenge_declined(unit_id: String, player: int)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""

func setup(p_unit_id: String, p_player: int) -> void:
	unit_id = p_unit_id
	player = p_player

	var unit = GameState.get_unit(unit_id)
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Epic Challenge Available - Player %d" % player
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "EPIC CHALLENGE"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Core - Epic Deed Stratagem"
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

	# Target info
	var target_label = Label.new()
	target_label.text = "Target: %s (CHARACTER)" % unit_name
	target_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(target_label)

	# Effect description
	var effect_label = Label.new()
	effect_label.text = "Until the end of the phase, all melee attacks made by that model have the [PRECISION] ability."
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.add_theme_font_size_override("font_size", 13)
	main_container.add_child(effect_label)

	# Precision explanation
	var precision_label = Label.new()
	precision_label.text = "[PRECISION]: Attacks that score a Critical Hit can be allocated to CHARACTER models in the target unit."
	precision_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	precision_label.add_theme_font_size_override("font_size", 11)
	precision_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	main_container.add_child(precision_label)

	main_container.add_child(HSeparator.new())

	# Action buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var use_button = Button.new()
	use_button.text = "Use Epic Challenge (1 CP)"
	use_button.custom_minimum_size = Vector2(200, 40)
	use_button.pressed.connect(_on_use_pressed)
	button_container.add_child(use_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var decline_button = Button.new()
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(120, 40)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_use_pressed() -> void:
	print("EpicChallengeDialog: Player %d uses EPIC CHALLENGE on %s" % [player, unit_name])
	emit_signal("epic_challenge_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("EpicChallengeDialog: Player %d declines EPIC CHALLENGE for %s" % [player, unit_name])
	emit_signal("epic_challenge_declined", unit_id, player)
	hide()
	queue_free()
