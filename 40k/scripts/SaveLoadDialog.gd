extends AcceptDialog

# SaveLoadDialog - Modal dialog for save/load operations
# Provides comprehensive save file management with metadata and validation

@onready var save_name_input: LineEdit = $VBoxContainer/SaveSection/SaveInputContainer/SaveNameInput
@onready var save_button: Button = $VBoxContainer/SaveSection/SaveInputContainer/SaveButton
@onready var saves_list: ItemList = $VBoxContainer/LoadSection/SavesScrollContainer/SavesList
@onready var load_button: Button = $VBoxContainer/LoadSection/LoadButtonContainer/LoadButton
@onready var delete_button: Button = $VBoxContainer/LoadSection/LoadButtonContainer/DeleteButton
@onready var cancel_button: Button = $VBoxContainer/LoadSection/LoadButtonContainer/CancelButton

# Signals for communication with Main scene
signal save_requested(save_name: String)
signal load_requested(save_file: String, owner_id: String)
signal delete_requested(save_file: String)

# Internal state
var save_files_data: Array = []  # Store save metadata for reference
var selected_save_index: int = -1
var is_web_platform: bool = false
var _save_files_signal_connected: bool = false

func _ready() -> void:
	# Configure dialog properties
	dialog_close_on_escape = true
	exclusive = false  # Allow clicking outside to close
	process_mode = Node.PROCESS_MODE_ALWAYS  # Always process input
	is_web_platform = OS.has_feature("web")

	# Wait for nodes to be ready
	await get_tree().process_frame

	# Connect UI signals
	_connect_ui_signals()

	# Connect to SaveLoadManager async signal for web
	if is_web_platform and SaveLoadManager and not _save_files_signal_connected:
		SaveLoadManager.save_files_received.connect(_on_save_files_received)
		SaveLoadManager.delete_completed.connect(_on_delete_completed)
		_save_files_signal_connected = true
		print("SaveLoadDialog: Connected to async save_files_received signal for web")

	# Initialize dialog
	refresh_saves_list()
	_update_button_states()

	print("SaveLoadDialog initialized successfully")

func _connect_ui_signals() -> void:
	# Debug: Print the actual node paths we're trying to access
	print("SaveLoadDialog: Checking node references...")
	print("  - save_button path: VBoxContainer/SaveSection/SaveInputContainer/SaveButton")
	print("  - save_name_input path: VBoxContainer/SaveSection/SaveInputContainer/SaveNameInput")
	print("  - saves_list path: VBoxContainer/LoadSection/SavesScrollContainer/SavesList")
	print("  - load_button path: VBoxContainer/LoadSection/LoadButtonContainer/LoadButton")
	
	# Try to get nodes manually if @onready failed
	if not save_button:
		save_button = get_node_or_null("VBoxContainer/SaveSection/SaveInputContainer/SaveButton")
		print("SaveLoadDialog: Manual lookup for save_button: ", save_button != null)
	
	if not save_name_input:
		save_name_input = get_node_or_null("VBoxContainer/SaveSection/SaveInputContainer/SaveNameInput")
		print("SaveLoadDialog: Manual lookup for save_name_input: ", save_name_input != null)
	
	if not saves_list:
		saves_list = get_node_or_null("VBoxContainer/LoadSection/SavesScrollContainer/SavesList")
		print("SaveLoadDialog: Manual lookup for saves_list: ", saves_list != null)
	
	if not load_button:
		load_button = get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/LoadButton")
		print("SaveLoadDialog: Manual lookup for load_button: ", load_button != null)
	
	if not delete_button:
		delete_button = get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/DeleteButton")
		print("SaveLoadDialog: Manual lookup for delete_button: ", delete_button != null)
	
	if not cancel_button:
		cancel_button = get_node_or_null("VBoxContainer/LoadSection/LoadButtonContainer/CancelButton")
		print("SaveLoadDialog: Manual lookup for cancel_button: ", cancel_button != null)
	
	# Now connect signals
	if save_button:
		save_button.pressed.connect(_on_save_button_pressed)
		print("SaveLoadDialog: Connected save button")
	else:
		print("SaveLoadDialog: ERROR - save_button not found!")
	
	if save_name_input:
		save_name_input.text_submitted.connect(_on_save_name_submitted)
		# Ensure the input can receive focus
		save_name_input.mouse_filter = Control.MOUSE_FILTER_STOP
		save_name_input.focus_mode = Control.FOCUS_ALL
		print("SaveLoadDialog: Connected save input")
	else:
		print("SaveLoadDialog: ERROR - save_name_input not found!")
	
	if saves_list:
		saves_list.item_selected.connect(_on_save_selected)
		saves_list.item_activated.connect(_on_save_double_clicked)
		print("SaveLoadDialog: Connected saves list")
	else:
		print("SaveLoadDialog: ERROR - saves_list not found!")
	
	if load_button:
		load_button.pressed.connect(_on_load_button_pressed)
		print("SaveLoadDialog: Connected load button")
	else:
		print("SaveLoadDialog: ERROR - load_button not found!")
	
	if delete_button:
		delete_button.pressed.connect(_on_delete_button_pressed)
		print("SaveLoadDialog: Connected delete button")
	else:
		print("SaveLoadDialog: ERROR - delete_button not found!")
	
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_button_pressed)
		print("SaveLoadDialog: Connected cancel button")
	else:
		print("SaveLoadDialog: ERROR - cancel_button not found!")
	
	print("SaveLoadDialog UI signals connected")

func refresh_saves_list() -> void:
	# Check if saves_list exists
	if not saves_list:
		print("SaveLoadDialog: ERROR - saves_list is null in refresh_saves_list!")
		return

	# Clear current list
	saves_list.clear()
	save_files_data.clear()
	selected_save_index = -1

	if is_web_platform:
		# On web: show placeholder, trigger async fetch
		saves_list.add_item("Loading saves...")
		saves_list.set_item_disabled(0, true)
		_update_button_states()
		# Trigger async cloud fetch - results come via _on_save_files_received
		SaveLoadManager.get_save_files()
		print("SaveLoadDialog: Initiated async save list fetch for web")
		return

	# Desktop: synchronous populate
	var save_files = SaveLoadManager.get_save_files()
	print("SaveLoadDialog: Found ", save_files.size(), " save files")
	_populate_saves_list(save_files)

func _populate_saves_list(save_files: Array) -> void:
	if not saves_list:
		return

	saves_list.clear()
	save_files_data.clear()
	selected_save_index = -1

	# Populate the list
	for save_info in save_files:
		var display_name = _format_save_display_name(save_info)
		saves_list.add_item(display_name)
		save_files_data.append(save_info)

		# Set tooltip with additional info
		var item_index = saves_list.get_item_count() - 1
		var tooltip = _create_save_tooltip(save_info)
		saves_list.set_item_tooltip(item_index, tooltip)

	_update_button_states()
	print("SaveLoadDialog: Populated list with ", save_files_data.size(), " save files")

func _on_save_files_received(save_files: Array) -> void:
	print("SaveLoadDialog: Received %d save files from cloud" % save_files.size())
	_populate_saves_list(save_files)

func _on_delete_completed(save_name: String) -> void:
	print("SaveLoadDialog: Delete completed for: ", save_name)
	# Refresh the list after successful cloud delete
	refresh_saves_list()

func _format_save_display_name(save_info: Dictionary) -> String:
	# Extract information from save_info
	var file_name = save_info.get("display_name", "Unknown")
	var metadata = save_info.get("metadata", {})
	
	# Get user description or use filename
	var description = ""
	if metadata.has("save_info"):
		description = metadata["save_info"].get("description", "")
	
	if description.is_empty():
		description = file_name.replace(".w40ksave", "")
	
	# Format timestamp
	var timestamp_text = ""
	if metadata.has("created_at"):
		var timestamp = metadata["created_at"]
		var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
		timestamp_text = "%04d-%02d-%02d %02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute
		]
	
	# Prefix shared saves
	var prefix = ""
	if save_info.get("ownership", "own") == "shared":
		prefix = "[Shared] "

	# Format: "[Shared] Description - YYYY-MM-DD HH:MM"
	return "%s%s - %s" % [prefix, description, timestamp_text]

func _create_save_tooltip(save_info: Dictionary) -> String:
	var metadata = save_info.get("metadata", {})
	var tooltip_lines = []
	
	# Add description
	var description = ""
	if metadata.has("save_info"):
		description = metadata["save_info"].get("description", "")
	if not description.is_empty():
		tooltip_lines.append("Name: " + description)
	
	# Add game state info
	if metadata.has("game_state"):
		var game_state = metadata["game_state"]
		tooltip_lines.append("Turn: " + str(game_state.get("turn", "Unknown")))
		tooltip_lines.append("Phase: " + str(game_state.get("phase", "Unknown")))
		tooltip_lines.append("Active Player: " + str(game_state.get("active_player", "Unknown")))
	
	# Add file info
	tooltip_lines.append("File: " + save_info.get("display_name", "Unknown"))
	
	return "\n".join(tooltip_lines)

func _update_button_states() -> void:
	# Update load and delete button states based on selection
	var has_selection = selected_save_index >= 0 and selected_save_index < save_files_data.size()
	load_button.disabled = not has_selection
	# Disable delete for shared saves (can only delete your own)
	var is_shared = false
	if has_selection:
		is_shared = save_files_data[selected_save_index].get("ownership", "own") == "shared"
	delete_button.disabled = not has_selection or is_shared

func _sanitize_save_name(input_name: String) -> String:
	# Remove invalid filename characters and trim
	var sanitized = input_name.strip_edges()
	var invalid_chars = ["<", ">", ":", "\"", "|", "?", "*", "/", "\\"]
	
	for char in invalid_chars:
		sanitized = sanitized.replace(char, "_")
	
	# Limit length to reasonable amount (255 is filesystem limit, use 200 for safety)
	if sanitized.length() > 200:
		sanitized = sanitized.substr(0, 200)
	
	return sanitized

func _generate_default_save_name() -> String:
	# Generate timestamp-based name if user doesn't provide one
	var datetime = Time.get_datetime_dict_from_system()
	return "save_%04d-%02d-%02d_%02d-%02d-%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# UI Event Handlers

func _on_save_button_pressed() -> void:
	print("SaveLoadDialog: Save button pressed!")
	var raw_input = save_name_input.text.strip_edges()
	print("SaveLoadDialog: Input text: '", raw_input, "'")
	var save_name: String
	
	if raw_input.is_empty():
		# Generate default name
		save_name = _generate_default_save_name()
		print("SaveLoadDialog: Using default save name: ", save_name)
	else:
		# Sanitize user input
		save_name = _sanitize_save_name(raw_input)
		print("SaveLoadDialog: Using sanitized save name: ", save_name)
	
	# Check if save already exists and prompt for overwrite
	if SaveLoadManager.save_exists(save_name):
		_show_overwrite_confirmation(save_name)
	else:
		_perform_save(save_name)

func _on_save_name_submitted(text: String) -> void:
	# Handle Enter key in save name input
	_on_save_button_pressed()

func _on_save_selected(index: int) -> void:
	print("SaveLoadDialog: Save selected at index ", index)
	selected_save_index = index
	_update_button_states()
	print("SaveLoadDialog: Button states updated - Load enabled: ", not load_button.disabled)

func _on_save_double_clicked(index: int) -> void:
	# Double-click to load save
	print("SaveLoadDialog: Save double-clicked at index ", index)
	selected_save_index = index

	if selected_save_index >= 0 and selected_save_index < save_files_data.size():
		var save_info = save_files_data[selected_save_index]
		var save_name = save_info.get("display_name", "")
		var owner_id = save_info.get("owner_id", "")
		print("SaveLoadDialog: Double-click load of: ", save_name, " (owner_id: ", owner_id, ")")
		emit_signal("load_requested", save_name.replace(".w40ksave", ""), owner_id)
		hide()

func _on_load_button_pressed() -> void:
	print("SaveLoadDialog: Load button pressed!")
	if selected_save_index < 0 or selected_save_index >= save_files_data.size():
		print("SaveLoadDialog: No valid save selected for loading")
		return

	var save_info = save_files_data[selected_save_index]
	var save_name = save_info.get("display_name", "")
	var owner_id = save_info.get("owner_id", "")

	print("SaveLoadDialog: Requesting load of: ", save_name, " (owner_id: ", owner_id, ")")
	emit_signal("load_requested", save_name.replace(".w40ksave", ""), owner_id)
	hide()

func _on_delete_button_pressed() -> void:
	if selected_save_index < 0 or selected_save_index >= save_files_data.size():
		print("SaveLoadDialog: No valid save selected for deletion")
		return
	
	var save_info = save_files_data[selected_save_index]
	var save_name = save_info.get("display_name", "")
	
	_show_delete_confirmation(save_name)

func _on_cancel_button_pressed() -> void:
	hide()

# Confirmation Dialogs

func _show_overwrite_confirmation(save_name: String) -> void:
	# Create confirmation dialog for overwrite
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "A save file named '%s' already exists.\nDo you want to overwrite it?" % save_name
	confirmation.title = "Overwrite Save File?"
	
	# Add to scene temporarily
	get_tree().current_scene.add_child(confirmation)
	
	# Connect signals
	confirmation.confirmed.connect(func(): 
		_perform_save(save_name)
		confirmation.queue_free()
	)
	confirmation.canceled.connect(func(): 
		confirmation.queue_free()
	)
	confirmation.close_requested.connect(func(): 
		confirmation.queue_free()
	)
	
	# Show dialog
	confirmation.popup_centered()

func _show_delete_confirmation(save_name: String) -> void:
	# Create confirmation dialog for deletion
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Are you sure you want to delete the save file '%s'?\nThis action cannot be undone." % save_name.replace(".w40ksave", "")
	confirmation.title = "Delete Save File?"
	
	# Add to scene temporarily
	get_tree().current_scene.add_child(confirmation)
	
	# Connect signals
	confirmation.confirmed.connect(func(): 
		_perform_delete(save_name)
		confirmation.queue_free()
	)
	confirmation.canceled.connect(func(): 
		confirmation.queue_free()
	)
	confirmation.close_requested.connect(func(): 
		confirmation.queue_free()
	)
	
	# Show dialog
	confirmation.popup_centered()

# Core Actions

func _perform_save(save_name: String) -> void:
	print("SaveLoadDialog: Performing save with name: ", save_name)
	
	# Clear input field
	save_name_input.text = ""
	
	# Emit save request with user's original input as description
	var user_description = save_name_input.text.strip_edges()
	if user_description.is_empty():
		user_description = save_name
	
	emit_signal("save_requested", save_name)
	hide()

func _perform_delete(save_name: String) -> void:
	var file_name_only = save_name.replace(".w40ksave", "")
	print("SaveLoadDialog: Performing delete of: ", file_name_only)
	
	emit_signal("delete_requested", file_name_only)
	
	# Refresh list after delete (will be called from Main after delete completes)
	call_deferred("refresh_saves_list")

# Public Interface

func show_dialog() -> void:
	# Refresh saves list and show dialog
	refresh_saves_list()
	save_name_input.text = ""
	popup_centered()
	
	# Ensure proper focus after popup
	await get_tree().process_frame
	if save_name_input:
		save_name_input.grab_focus()
		print("SaveLoadDialog: Focus grabbed by save input")
	
	print("SaveLoadDialog: Dialog shown and focused")

func hide_dialog() -> void:
	hide()

# Override popup methods to ensure proper initialization

func _about_to_popup() -> void:
	# Called just before dialog is shown
	refresh_saves_list()
	save_name_input.text = ""
	print("SaveLoadDialog: About to popup, refreshed saves list")

func _popup_centered_wrapper(min_size: Vector2i = Vector2i()) -> void:
	# Custom wrapper to avoid native method override warning
	refresh_saves_list()
	popup_centered(min_size)
	
	# Focus save input for immediate typing
	if save_name_input:
		save_name_input.grab_focus()

# Debug methods
func print_debug_info() -> void:
	print("=== SaveLoadDialog Debug Info ===")
	print("Save files data count: ", save_files_data.size())
	print("Selected save index: ", selected_save_index)
	print("Dialog visible: ", visible)
	print("Load button disabled: ", load_button.disabled)
	print("Delete button disabled: ", delete_button.disabled)
	print("==================================")