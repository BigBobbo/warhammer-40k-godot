extends AcceptDialog

# TransportEmbarkDialog - Modal dialog for selecting units to embark during deployment
# Shows available units and allows selection up to transport capacity

signal units_selected(unit_ids: Array)

var transport_id: String
var transport_name: String = ""
var capacity: int = 0
var capacity_keywords: Array = []
var available_units: Array = []
var selected_units: Array = []
var checkboxes: Dictionary = {}
var current_model_count: int = 0

# UI Nodes
var vbox: VBoxContainer
var capacity_label: Label
var unit_container: VBoxContainer

func _ready() -> void:
	# Set dialog properties
	title = "Select Units to Embark"
	dialog_hide_on_ok = false
	get_ok_button().text = "Confirm Embarkation"
	get_ok_button().pressed.connect(_on_confirm_pressed)

	# Create main container
	vbox = VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(400, 300))
	add_child(vbox)

	# Create capacity label
	capacity_label = Label.new()
	vbox.add_child(capacity_label)

	# Add separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Create scrollable container for units
	var scroll = ScrollContainer.new()
	scroll.set_custom_minimum_size(Vector2(380, 200))
	vbox.add_child(scroll)

	unit_container = VBoxContainer.new()
	scroll.add_child(unit_container)

	print("TransportEmbarkDialog initialized")

func setup(p_transport_id: String) -> void:
	transport_id = p_transport_id
	var transport = GameState.get_unit(transport_id)

	if not transport or not transport.has("transport_data"):
		print("ERROR: Invalid transport unit: ", transport_id)
		queue_free()
		return

	transport_name = transport.meta.get("name", transport_id)
	capacity = transport.transport_data.get("capacity", 0)
	capacity_keywords = transport.transport_data.get("capacity_keywords", [])

	# Set dialog title with transport name
	title = "Embark Units in %s" % transport_name

	# Ensure UI is ready before updating
	if not is_node_ready():
		await ready

	# Update capacity label
	_update_capacity_label()

	# Get available units for embarking
	_populate_available_units(transport.owner)

	# Create checkboxes for each available unit
	_create_unit_checkboxes()

func _populate_available_units(player: int) -> void:
	available_units.clear()

	# Get all units belonging to the same player
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]

		# Skip if not same owner
		if unit.owner != player:
			continue

		# Skip if already deployed
		if unit.status != GameState.UnitStatus.UNDEPLOYED:
			continue

		# Skip transports (they can't embark in other transports)
		if unit.has("transport_data"):
			continue

		# Skip if already embarked
		if unit.get("embarked_in", null) != null:
			continue

		# Check if unit can embark (has required keywords)
		if capacity_keywords.size() > 0:
			if not _has_required_keywords(unit, capacity_keywords):
				continue

		# Check if unit would fit
		var model_count = _get_alive_model_count(unit)
		if model_count <= capacity:
			available_units.append({
				"unit": unit,
				"model_count": model_count
			})

func _has_required_keywords(unit: Dictionary, required: Array) -> bool:
	if not unit.has("meta") or not unit.meta.has("keywords"):
		return false

	var unit_keywords = unit.meta.keywords
	for keyword in required:
		if not keyword in unit_keywords:
			return false

	return true

func _get_alive_model_count(unit: Dictionary) -> int:
	var count = 0
	if unit.has("models"):
		for model in unit.models:
			if model.get("alive", true):
				count += 1
	return count

func _create_unit_checkboxes() -> void:
	# Clear existing checkboxes
	for child in unit_container.get_children():
		child.queue_free()
	checkboxes.clear()
	selected_units.clear()
	current_model_count = 0

	if available_units.is_empty():
		var no_units_label = Label.new()
		no_units_label.text = "No eligible units available for embarking"
		if capacity_keywords.size() > 0:
			no_units_label.text += "\n(Requires %s keywords)" % str(capacity_keywords)
		unit_container.add_child(no_units_label)
		return

	# Create checkbox for each available unit
	for unit_data in available_units:
		var unit = unit_data.unit
		var model_count = unit_data.model_count

		var hbox = HBoxContainer.new()

		var checkbox = CheckBox.new()
		var unit_name = unit.meta.get("name", unit.id)
		checkbox.text = "%s (%d models)" % [unit_name, model_count]
		checkbox.toggled.connect(_on_unit_toggled.bind(unit.id, model_count))

		checkboxes[unit.id] = checkbox
		hbox.add_child(checkbox)

		unit_container.add_child(hbox)

func _on_unit_toggled(pressed: bool, unit_id: String, model_count: int) -> void:
	if pressed:
		# Check if adding this unit would exceed capacity
		if current_model_count + model_count > capacity:
			# Revert the toggle
			checkboxes[unit_id].set_pressed_no_signal(false)

			# Show warning
			var warning_dialog = AcceptDialog.new()
			warning_dialog.title = "Capacity Exceeded"
			warning_dialog.dialog_text = "Adding this unit would exceed transport capacity.\nCurrent: %d/%d\nUnit size: %d models" % [current_model_count, capacity, model_count]
			get_tree().root.add_child(warning_dialog)
			warning_dialog.popup_centered()
			warning_dialog.confirmed.connect(func(): warning_dialog.queue_free())
			return

		selected_units.append(unit_id)
		current_model_count += model_count
	else:
		selected_units.erase(unit_id)
		current_model_count -= model_count

	_update_capacity_label()

func _update_capacity_label() -> void:
	# Safety check - label might not be initialized yet if called from setup() before _ready()
	if not capacity_label:
		return

	capacity_label.text = "Transport Capacity: %d / %d models" % [current_model_count, capacity]

	if capacity_keywords.size() > 0:
		capacity_label.text += "\n(Requires %s keywords)" % str(capacity_keywords)

	# Color code based on capacity usage
	if current_model_count == 0:
		capacity_label.modulate = Color.WHITE
	elif current_model_count < capacity:
		capacity_label.modulate = Color.GREEN
	elif current_model_count == capacity:
		capacity_label.modulate = Color.YELLOW
	else:
		capacity_label.modulate = Color.RED

func _on_confirm_pressed() -> void:
	emit_signal("units_selected", selected_units)
	hide()
	queue_free()
