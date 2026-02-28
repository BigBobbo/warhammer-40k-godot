extends AcceptDialog

# KatahStanceDialog - UI for Martial Ka'tah stance selection during Fight phase
#
# MARTIAL KA'TAH (Adeptus Custodes Faction Ability)
# WHEN: Fight phase, each time a unit with this ability is selected to fight.
# EFFECT: Select one Ka'tah Stance:
#   - Dacatarai: Melee attacks gain Sustained Hits 1
#   - Rendax: Melee attacks gain Lethal Hits
# The stance is active until the unit finishes attacking.
#
# MASTER OF THE STANCES (Shield-Captain Datasheet Ability)
# Once per battle: both Ka'tah stances active simultaneously.

signal stance_selected(unit_id: String, stance: String, player: int)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""
var master_of_stances_available: bool = false

func setup(p_unit_id: String, p_player: int, p_master_available: bool = false) -> void:
	unit_id = p_unit_id
	player = p_player
	master_of_stances_available = p_master_available

	var unit = GameState.get_unit(unit_id)
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Martial Ka'tah — %s" % unit_name
	min_size = DialogConstants.MEDIUM

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "MARTIAL KA'TAH"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Adeptus Custodes — Faction Ability"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# Unit info
	var unit_label = Label.new()
	unit_label.text = "%s selected to fight — choose a Ka'tah Stance:" % unit_name
	unit_label.add_theme_font_size_override("font_size", 14)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(unit_label)

	main_container.add_child(HSeparator.new())

	# Stance buttons
	var button_container = VBoxContainer.new()

	# Master of the Stances button (if available)
	if master_of_stances_available:
		var both_button = Button.new()
		both_button.text = "MASTER OF THE STANCES — Both Stances Active"
		both_button.custom_minimum_size = Vector2(400, 50)
		both_button.add_theme_color_override("font_color", Color.GOLD)
		both_button.pressed.connect(_on_both_pressed)
		button_container.add_child(both_button)

		var both_desc = Label.new()
		both_desc.text = "Once per battle: Both Dacatarai (Sustained Hits 1) AND Rendax (Lethal Hits) are active simultaneously for this fight."
		both_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		both_desc.add_theme_font_size_override("font_size", 11)
		both_desc.add_theme_color_override("font_color", Color.LIGHT_GOLDENROD)
		button_container.add_child(both_desc)

		var spacer0 = Control.new()
		spacer0.custom_minimum_size = Vector2(0, 10)
		button_container.add_child(spacer0)

	# Dacatarai button
	var dacatarai_button = Button.new()
	dacatarai_button.text = "Dacatarai — Sustained Hits 1"
	dacatarai_button.custom_minimum_size = Vector2(400, 50)
	dacatarai_button.pressed.connect(_on_dacatarai_pressed)
	button_container.add_child(dacatarai_button)

	# Dacatarai description
	var dacatarai_desc = Label.new()
	dacatarai_desc.text = "Each time a model in this unit makes a melee attack, a successful unmodified Hit roll of 6 scores one additional hit."
	dacatarai_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dacatarai_desc.add_theme_font_size_override("font_size", 11)
	dacatarai_desc.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	button_container.add_child(dacatarai_desc)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	button_container.add_child(spacer)

	# Rendax button
	var rendax_button = Button.new()
	rendax_button.text = "Rendax — Lethal Hits"
	rendax_button.custom_minimum_size = Vector2(400, 50)
	rendax_button.pressed.connect(_on_rendax_pressed)
	button_container.add_child(rendax_button)

	# Rendax description
	var rendax_desc = Label.new()
	rendax_desc.text = "Each time a model in this unit makes a melee attack, a successful unmodified Hit roll of 6 is always a successful Wound roll (auto-wound)."
	rendax_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rendax_desc.add_theme_font_size_override("font_size", 11)
	rendax_desc.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	button_container.add_child(rendax_desc)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_both_pressed() -> void:
	print("KatahStanceDialog: Player %d selects BOTH stances (Master of the Stances) for %s" % [player, unit_name])
	emit_signal("stance_selected", unit_id, "both", player)
	hide()
	queue_free()

func _on_dacatarai_pressed() -> void:
	print("KatahStanceDialog: Player %d selects DACATARAI stance for %s" % [player, unit_name])
	emit_signal("stance_selected", unit_id, "dacatarai", player)
	hide()
	queue_free()

func _on_rendax_pressed() -> void:
	print("KatahStanceDialog: Player %d selects RENDAX stance for %s" % [player, unit_name])
	emit_signal("stance_selected", unit_id, "rendax", player)
	hide()
	queue_free()
