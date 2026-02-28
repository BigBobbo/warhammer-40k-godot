extends AcceptDialog

# Dialog for selecting a transport to deploy a unit into during deployment phase

signal transport_selected(transport_id: String)

var unit_id: String = ""
var transport_list: ItemList
var deploy_button: Button
var selected_transport_id: String = ""

func _ready() -> void:
	title = "Deploy Unit in Transport"
	min_size = DialogConstants.MEDIUM

	# Create main container
	var vbox = VBoxContainer.new()
	add_child(vbox)

	# Info label
	var info_label = Label.new()
	info_label.text = "Select a transport to deploy this unit into:"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info_label)

	# Transport list
	transport_list = ItemList.new()
	transport_list.custom_minimum_size = Vector2(0, 200)
	transport_list.item_selected.connect(_on_transport_selected)
	vbox.add_child(transport_list)

	# Custom buttons
	get_ok_button().text = "Deploy Embarked"
	get_ok_button().disabled = true
	confirmed.connect(_on_confirmed)

	# Add "Deploy Normally" button
	add_button("Deploy Normally", false, "deploy_normal")
	# Connect to custom_action signal to handle the custom button
	if not custom_action.is_connected(_on_custom_action):
		custom_action.connect(_on_custom_action)

func show_for_unit(unit_id_: String, deployment_controller: Node) -> void:
	unit_id = unit_id_
	selected_transport_id = ""
	get_ok_button().disabled = true

	# Clear list
	transport_list.clear()

	# Get available transports
	if deployment_controller and deployment_controller.has_method("get_available_transports_for_unit"):
		var transports = deployment_controller.get_available_transports_for_unit(unit_id)

		if transports.is_empty():
			# No transports available, just deploy normally
			_on_deploy_normally()
			return

		# Populate list
		for transport in transports:
			var text = "%s (%d/%d capacity)" % [
				transport.name,
				transport.capacity_used,
				transport.capacity_total
			]
			transport_list.add_item(text)
			transport_list.set_item_metadata(transport_list.get_item_count() - 1, transport.id)

	# Show dialog
	popup_centered()

func _on_transport_selected(index: int) -> void:
	selected_transport_id = transport_list.get_item_metadata(index)
	get_ok_button().disabled = false

func _on_confirmed() -> void:
	if selected_transport_id != "":
		emit_signal("transport_selected", selected_transport_id)

func _on_deploy_normally() -> void:
	# Signal to deploy normally (empty transport_id means normal deployment)
	emit_signal("transport_selected", "")
	hide()

func _on_custom_action(action: String) -> void:
	# Handle custom button actions
	if action == "deploy_normal":
		_on_deploy_normally()
