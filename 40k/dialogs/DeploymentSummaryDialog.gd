extends AcceptDialog

# DeploymentSummaryDialog - T5-UX8: Deployment summary before ending phase
#
# Shows a summary of all deployed units before ending the deployment phase.
# Lists deployed units with positions, units in transports, attached characters,
# and flags any potential issues. Requires explicit confirmation to proceed.

signal deployment_confirmed()
signal deployment_cancelled()

var deployment_data: Dictionary = {}

func setup(p_deployment_data: Dictionary) -> void:
	deployment_data = p_deployment_data

	title = "Deployment Summary"

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(550, 350)

	# Header
	var header = Label.new()
	header.text = "DEPLOYMENT SUMMARY"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.CORNFLOWER_BLUE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Overview counts
	var p1_units = deployment_data.get("player1_units", [])
	var p2_units = deployment_data.get("player2_units", [])
	var embarked_units = deployment_data.get("embarked_units", [])
	var attached_units = deployment_data.get("attached_units", [])
	var reserves_units = deployment_data.get("reserves_units", [])
	var warnings = deployment_data.get("warnings", [])

	var overview = Label.new()
	overview.text = "Player 1: %d units  |  Player 2: %d units" % [p1_units.size(), p2_units.size()]
	overview.add_theme_font_size_override("font_size", 14)
	overview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(overview)

	main_container.add_child(HSeparator.new())

	# Scrollable content area
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_list = VBoxContainer.new()
	content_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Player 1 deployed units
	if p1_units.size() > 0:
		var p1_header = Label.new()
		p1_header.text = "Player 1 - Deployed Units:"
		p1_header.add_theme_font_size_override("font_size", 13)
		p1_header.add_theme_color_override("font_color", Color.CORNFLOWER_BLUE)
		content_list.add_child(p1_header)
		for unit_info in p1_units:
			var label = Label.new()
			label.text = "  %s" % unit_info.display_text
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color.CORNFLOWER_BLUE)
			content_list.add_child(label)

	# Player 2 deployed units
	if p2_units.size() > 0:
		var p2_header = Label.new()
		p2_header.text = "Player 2 - Deployed Units:"
		p2_header.add_theme_font_size_override("font_size", 13)
		p2_header.add_theme_color_override("font_color", Color.INDIAN_RED)
		content_list.add_child(p2_header)
		for unit_info in p2_units:
			var label = Label.new()
			label.text = "  %s" % unit_info.display_text
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color.INDIAN_RED)
			content_list.add_child(label)

	# Embarked units
	if embarked_units.size() > 0:
		content_list.add_child(HSeparator.new())
		var emb_header = Label.new()
		emb_header.text = "Units in Transports:"
		emb_header.add_theme_font_size_override("font_size", 13)
		emb_header.add_theme_color_override("font_color", Color.YELLOW)
		content_list.add_child(emb_header)
		for unit_info in embarked_units:
			var label = Label.new()
			label.text = "  %s" % unit_info.display_text
			label.add_theme_font_size_override("font_size", 12)
			content_list.add_child(label)

	# Attached characters
	if attached_units.size() > 0:
		content_list.add_child(HSeparator.new())
		var att_header = Label.new()
		att_header.text = "Attached Characters:"
		att_header.add_theme_font_size_override("font_size", 13)
		att_header.add_theme_color_override("font_color", Color.YELLOW)
		content_list.add_child(att_header)
		for unit_info in attached_units:
			var label = Label.new()
			label.text = "  %s" % unit_info.display_text
			label.add_theme_font_size_override("font_size", 12)
			content_list.add_child(label)

	# Reserves
	if reserves_units.size() > 0:
		content_list.add_child(HSeparator.new())
		var res_header = Label.new()
		res_header.text = "Units in Reserves:"
		res_header.add_theme_font_size_override("font_size", 13)
		res_header.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
		content_list.add_child(res_header)
		for unit_info in reserves_units:
			var label = Label.new()
			label.text = "  %s" % unit_info.display_text
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
			content_list.add_child(label)

	# Warnings
	if warnings.size() > 0:
		content_list.add_child(HSeparator.new())
		var warn_header = Label.new()
		warn_header.text = "Warnings:"
		warn_header.add_theme_font_size_override("font_size", 13)
		warn_header.add_theme_color_override("font_color", Color.ORANGE)
		content_list.add_child(warn_header)
		for warning_text in warnings:
			var label = Label.new()
			label.text = "  ⚠ %s" % warning_text
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color.ORANGE)
			content_list.add_child(label)

	scroll.add_child(content_list)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_button = Button.new()
	cancel_button.text = "Go Back"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm and Start Game"
	confirm_button.custom_minimum_size = Vector2(200, 40)
	confirm_button.add_theme_color_override("font_color", Color.GREEN)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_confirm_pressed() -> void:
	print("DeploymentSummaryDialog: Player confirmed ending deployment phase")
	emit_signal("deployment_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("DeploymentSummaryDialog: Player cancelled ending deployment phase")
	emit_signal("deployment_cancelled")
	hide()
	queue_free()
