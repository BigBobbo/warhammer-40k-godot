extends AcceptDialog

# SentinelStormDialog - UI for Sentinel Storm shoot-again ability (Custodian Guard)
#
# SENTINEL STORM (Adeptus Custodes — Custodian Guard Datasheet Ability)
# WHEN: Shooting phase, after this unit has shot.
# EFFECT: Once per battle, this unit can shoot again.

signal sentinel_storm_chosen(unit_id: String, use_ability: bool)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""

func setup(p_unit_id: String, p_player: int) -> void:
	unit_id = p_unit_id
	player = p_player

	var unit = GameState.get_unit(unit_id)
	unit_name = unit.get("meta", {}).get("name", unit_id)

	title = "Sentinel Storm — %s" % unit_name

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(500, 250)

	# Header
	var header = Label.new()
	header.text = "SENTINEL STORM"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Adeptus Custodes — Custodian Guard"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color.GRAY)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# Ability description
	var desc_label = Label.new()
	desc_label.text = "Once per battle, after this unit has shot, it can shoot again."
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(desc_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_container.add_child(spacer)

	# Unit info
	var unit_label = Label.new()
	unit_label.text = "%s has finished shooting. Activate Sentinel Storm to shoot again?" % unit_name
	unit_label.add_theme_font_size_override("font_size", 14)
	unit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(unit_label)

	main_container.add_child(HSeparator.new())

	# Button container
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# Use ability button
	var use_button = Button.new()
	use_button.text = "Activate Sentinel Storm"
	use_button.custom_minimum_size = Vector2(220, 50)
	use_button.pressed.connect(_on_use_pressed)
	button_container.add_child(use_button)

	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(btn_spacer)

	# Decline button
	var decline_button = Button.new()
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(150, 50)
	decline_button.pressed.connect(_on_decline_pressed)
	button_container.add_child(decline_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_use_pressed() -> void:
	print("SentinelStormDialog: Player %d activates Sentinel Storm for %s" % [player, unit_name])
	emit_signal("sentinel_storm_chosen", unit_id, true)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("SentinelStormDialog: Player %d declines Sentinel Storm for %s" % [player, unit_name])
	emit_signal("sentinel_storm_chosen", unit_id, false)
	hide()
	queue_free()
