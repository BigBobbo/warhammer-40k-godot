extends VBoxContainer
const GameStateData = preload("res://autoloads/GameState.gd")
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# UI for deploying units directly into transports during deployment phase
# This is designed to be added as a child to the right panel's VBoxContainer

signal deploy_embarked(unit_id: String, transport_id: String)

var unit_list: ItemList
var transport_list: ItemList
var deploy_button: Button
var info_label: Label
var player_label: Label
var selected_unit: String = ""
var selected_transport: String = ""
var current_player: int = 1

func _ready() -> void:
	custom_minimum_size = Vector2(0, 300)  # More compact
	_setup_ui()
	visible = true  # Start visible in deployment phase

func _setup_ui() -> void:
	add_theme_constant_override("separation", 5)

	# Add separator at the top
	add_child(HSeparator.new())

	# Title
	var title = Label.new()
	title.text = "Deploy Embarked"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	# Player indicator
	player_label = Label.new()
	player_label.text = "Player 1 Units"
	player_label.add_theme_font_size_override("font_size", 14)
	player_label.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
	add_child(player_label)

	# Instructions
	info_label = Label.new()
	info_label.text = "Select a unit and transport to deploy embarked"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info_label)

	# Unit selection
	var unit_label = Label.new()
	unit_label.text = "Available Units:"
	add_child(unit_label)

	unit_list = ItemList.new()
	unit_list.custom_minimum_size = Vector2(0, 80)
	unit_list.item_selected.connect(_on_unit_selected)
	add_child(unit_list)

	# Transport selection
	var transport_label = Label.new()
	transport_label.text = "Available Transports:"
	add_child(transport_label)

	transport_list = ItemList.new()
	transport_list.custom_minimum_size = Vector2(0, 80)
	transport_list.item_selected.connect(_on_transport_selected)
	add_child(transport_list)

	# Deploy button
	deploy_button = Button.new()
	deploy_button.text = "Deploy Unit in Transport"
	deploy_button.disabled = true
	deploy_button.pressed.connect(_on_deploy_pressed)
	_WhiteDwarfTheme.apply_to_button(deploy_button)
	add_child(deploy_button)

func show_for_player(player: int) -> void:
	visible = true
	selected_unit = ""
	selected_transport = ""
	deploy_button.disabled = true
	current_player = player

	# Update player label
	if player_label:
		var faction_name = GameState.get_faction_name(player)
		player_label.text = "Player %d (%s) Units" % [player, faction_name]
		# Set color based on player
		if player == 1:
			player_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.9))  # Blue
		else:
			player_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))  # Red

	print("DeploymentTransportUI: Showing units for player ", player)
	_refresh_lists(player)

func _refresh_lists(player: int) -> void:
	unit_list.clear()
	transport_list.clear()

	var units = GameState.get_units_for_player(player)

	# Find undeployed units
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.UNDEPLOYED:
			# Check if it's a transport
			var keywords = unit.get("meta", {}).get("keywords", [])
			var name = unit.get("meta", {}).get("name", unit_id)

			if "TRANSPORT" in keywords:
				# Add to transport list with capacity info
				var capacity_info = TransportManager.get_transport_capacity(unit)
				var capacity_text = "%s (Cap: %d)" % [name, capacity_info.total]
				transport_list.add_item(capacity_text)
				transport_list.set_item_metadata(transport_list.get_item_count() - 1, unit_id)
			else:
				# Add to unit list if it can be transported
				if "INFANTRY" in keywords:  # Most transports can carry infantry
					unit_list.add_item(name)
					unit_list.set_item_metadata(unit_list.get_item_count() - 1, unit_id)

	# Also add deployed transports
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			var keywords = unit.get("meta", {}).get("keywords", [])
			if "TRANSPORT" in keywords:
				var name = unit.get("meta", {}).get("name", unit_id)
				var capacity_info = TransportManager.get_transport_capacity(unit)
				var current_usage = TransportManager.calculate_current_usage(unit_id)
				var capacity_text = "%s (Cap: %d/%d) [Deployed]" % [name, current_usage, capacity_info.total]
				transport_list.add_item(capacity_text)
				transport_list.set_item_metadata(transport_list.get_item_count() - 1, unit_id)

func _on_unit_selected(index: int) -> void:
	selected_unit = unit_list.get_item_metadata(index)
	_check_can_deploy()

func _on_transport_selected(index: int) -> void:
	selected_transport = transport_list.get_item_metadata(index)
	_check_can_deploy()

func _check_can_deploy() -> void:
	if selected_unit == "" or selected_transport == "":
		deploy_button.disabled = true
		info_label.text = "Select both a unit and transport"
		return

	# Check if transport is deployed (required)
	var transport = GameState.get_unit(selected_transport)
	if transport.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		info_label.text = "Transport must be deployed first"
		deploy_button.disabled = true
		return

	# Check capacity
	var unit = GameState.get_unit(selected_unit)
	var capacity_info = TransportManager.get_transport_capacity(transport)
	var current_usage = TransportManager.calculate_current_usage(selected_transport)
	var unit_usage = TransportManager.calculate_unit_usage(unit, capacity_info)

	if current_usage + unit_usage > capacity_info.total:
		info_label.text = "Not enough transport capacity (%d needed, %d available)" % [unit_usage, capacity_info.total - current_usage]
		deploy_button.disabled = true
		return

	# Check keyword restrictions
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	for restriction in capacity_info.restrictions:
		if restriction.begins_with("NOT_"):
			var excluded = restriction.substr(4)
			if excluded in unit_keywords:
				info_label.text = "Transport cannot carry %s units" % excluded
				deploy_button.disabled = true
				return
		else:
			if not restriction in unit_keywords:
				info_label.text = "Transport can only carry %s units" % restriction
				deploy_button.disabled = true
				return

	# All checks passed
	var unit_name = unit.get("meta", {}).get("name", selected_unit)
	var transport_name = transport.get("meta", {}).get("name", selected_transport)
	info_label.text = "Ready to deploy %s in %s" % [unit_name, transport_name]
	deploy_button.disabled = false

func _on_deploy_pressed() -> void:
	if selected_unit != "" and selected_transport != "":
		emit_signal("deploy_embarked", selected_unit, selected_transport)

		# Clear selection
		selected_unit = ""
		selected_transport = ""

		# Refresh lists
		var player = GameState.get_active_player()
		_refresh_lists(player)

func hide_panel() -> void:
	visible = false
