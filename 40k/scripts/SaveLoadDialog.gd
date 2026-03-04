extends PanelContainer

# SaveLoadDialog - Modal dialog for save/load operations
# Styled with WhiteDwarf theme to match SettingsMenu
# Provides comprehensive save file management with metadata and validation

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

# UI references (built dynamically)
var save_name_input: LineEdit
var save_button: Button
var saves_list: ItemList
var load_button: Button
var delete_button: Button
var cancel_button: Button
var main_menu_button: Button
var preview_label: RichTextLabel  # SAVE-11: Preview panel for selected save

# Signals for communication with Main scene
signal save_requested(save_name: String)
signal load_requested(save_file: String, owner_id: String)
signal delete_requested(save_file: String)
signal main_menu_requested()

# Internal state
var save_files_data: Array = []  # Store save metadata for reference
var selected_save_index: int = -1
var is_web_platform: bool = false
var _save_files_signal_connected: bool = false
var _is_multiplayer_client: bool = false  # SAVE-8: Track if non-host in multiplayer

func _ready() -> void:
	# Configure as full-screen overlay (hidden initially)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_web_platform = OS.has_feature("web")

	_build_ui()

	# Connect to SaveLoadManager async signal for web
	if is_web_platform and SaveLoadManager and not _save_files_signal_connected:
		SaveLoadManager.save_files_received.connect(_on_save_files_received)
		SaveLoadManager.delete_completed.connect(_on_delete_completed)
		_save_files_signal_connected = true
		print("SaveLoadDialog: Connected to async save_files_received signal for web")

	# Initialize
	refresh_saves_list()
	_update_button_states()

	print("SaveLoadDialog initialized successfully")

func _build_ui() -> void:
	name = "SaveLoadDialog"

	# Full-screen semi-transparent overlay
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Dark overlay background
	var overlay_style = StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	add_theme_stylebox_override("panel", overlay_style)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel — SAVE-11: widened to fit preview panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 550)
	WhiteDwarfThemeData.apply_to_panel(panel)
	center.add_child(panel)

	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "SAVE & LOAD GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(title)

	# Separator
	var sep1 = HSeparator.new()
	sep1.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep1)

	# ── Save Section ──
	var save_header = Label.new()
	save_header.text = "Create New Save"
	save_header.add_theme_font_size_override("font_size", 16)
	save_header.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(save_header)

	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	vbox.add_child(save_row)

	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Enter save name (leave empty for timestamp)"
	save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_name_input.custom_minimum_size = Vector2(0, 36)
	save_name_input.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	save_name_input.add_theme_color_override("font_placeholder_color", Color(0.6, 0.55, 0.45, 0.5))
	# Style the input background
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	input_style.border_color = WhiteDwarfThemeData.WH_GOLD
	input_style.border_width_bottom = 1
	input_style.border_width_top = 1
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	input_style.corner_radius_top_left = 3
	input_style.corner_radius_top_right = 3
	input_style.corner_radius_bottom_left = 3
	input_style.corner_radius_bottom_right = 3
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	save_name_input.add_theme_stylebox_override("normal", input_style)
	var input_focus_style = input_style.duplicate()
	input_focus_style.border_color = WhiteDwarfThemeData.WH_PARCHMENT
	save_name_input.add_theme_stylebox_override("focus", input_focus_style)
	save_name_input.mouse_filter = Control.MOUSE_FILTER_STOP
	save_name_input.focus_mode = Control.FOCUS_ALL
	save_name_input.text_submitted.connect(_on_save_name_submitted)
	save_row.add_child(save_name_input)

	save_button = Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(100, 36)
	WhiteDwarfThemeData.apply_to_button(save_button)
	save_button.pressed.connect(_on_save_button_pressed)
	save_row.add_child(save_button)

	# Separator
	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep2)

	# ── Load Section ──
	var load_header = Label.new()
	load_header.text = "Existing Saves"
	load_header.add_theme_font_size_override("font_size", 16)
	load_header.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(load_header)

	# SAVE-11: Horizontal layout for saves list + preview panel
	var list_and_preview = HBoxContainer.new()
	list_and_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_and_preview.add_theme_constant_override("separation", 10)
	vbox.add_child(list_and_preview)

	# Saves list in a scroll container
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(350, 200)
	list_and_preview.add_child(scroll)

	saves_list = ItemList.new()
	saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_list.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	saves_list.add_theme_color_override("font_selected_color", WhiteDwarfThemeData.WH_GOLD)
	# Style the list background
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0.08, 0.07, 0.05, 0.9)
	list_style.border_color = Color(0.3, 0.25, 0.18, 0.6)
	list_style.border_width_bottom = 1
	list_style.border_width_top = 1
	list_style.border_width_left = 1
	list_style.border_width_right = 1
	list_style.corner_radius_top_left = 3
	list_style.corner_radius_top_right = 3
	list_style.corner_radius_bottom_left = 3
	list_style.corner_radius_bottom_right = 3
	list_style.content_margin_left = 6
	list_style.content_margin_right = 6
	list_style.content_margin_top = 4
	list_style.content_margin_bottom = 4
	saves_list.add_theme_stylebox_override("panel", list_style)
	# Selected item highlight
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.4, 0.3, 0.15, 0.5)
	selected_style.corner_radius_top_left = 2
	selected_style.corner_radius_top_right = 2
	selected_style.corner_radius_bottom_left = 2
	selected_style.corner_radius_bottom_right = 2
	saves_list.add_theme_stylebox_override("selected", selected_style)
	saves_list.add_theme_stylebox_override("selected_focus", selected_style)
	saves_list.item_selected.connect(_on_save_selected)
	saves_list.item_activated.connect(_on_save_double_clicked)
	scroll.add_child(saves_list)

	# SAVE-11: Preview panel
	var preview_container = PanelContainer.new()
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.custom_minimum_size = Vector2(280, 0)
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.1, 0.08, 0.06, 0.9)
	preview_style.border_color = Color(0.3, 0.25, 0.18, 0.6)
	preview_style.border_width_bottom = 1
	preview_style.border_width_top = 1
	preview_style.border_width_left = 1
	preview_style.border_width_right = 1
	preview_style.corner_radius_top_left = 3
	preview_style.corner_radius_top_right = 3
	preview_style.corner_radius_bottom_left = 3
	preview_style.corner_radius_bottom_right = 3
	preview_style.content_margin_left = 10
	preview_style.content_margin_right = 10
	preview_style.content_margin_top = 8
	preview_style.content_margin_bottom = 8
	preview_container.add_theme_stylebox_override("panel", preview_style)
	list_and_preview.add_child(preview_container)

	preview_label = RichTextLabel.new()
	preview_label.bbcode_enabled = true
	preview_label.fit_content = false
	preview_label.scroll_active = true
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_label.add_theme_color_override("default_color", WhiteDwarfThemeData.WH_PARCHMENT)
	preview_label.add_theme_font_size_override("normal_font_size", 13)
	preview_label.text = ""
	_set_preview_placeholder()
	preview_container.add_child(preview_label)

	# Separator
	var sep3 = HSeparator.new()
	sep3.add_theme_color_override("separator", WhiteDwarfThemeData.WH_GOLD)
	vbox.add_child(sep3)

	# ── Button Row ──
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	load_button = Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(100, 40)
	load_button.disabled = true
	WhiteDwarfThemeData.apply_to_button(load_button)
	load_button.pressed.connect(_on_load_button_pressed)
	btn_row.add_child(load_button)

	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.custom_minimum_size = Vector2(100, 40)
	delete_button.disabled = true
	WhiteDwarfThemeData.apply_to_button(delete_button)
	delete_button.pressed.connect(_on_delete_button_pressed)
	btn_row.add_child(delete_button)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	main_menu_button = Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.custom_minimum_size = Vector2(120, 40)
	WhiteDwarfThemeData.apply_to_button(main_menu_button)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	btn_row.add_child(main_menu_button)

	cancel_button = Button.new()
	cancel_button.text = "Close"
	cancel_button.custom_minimum_size = Vector2(100, 40)
	WhiteDwarfThemeData.apply_to_button(cancel_button)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	btn_row.add_child(cancel_button)

	print("SaveLoadDialog: UI built with WhiteDwarf theme")

# ============================================================================
# Saves List Management
# ============================================================================

func refresh_saves_list() -> void:
	if not saves_list:
		print("SaveLoadDialog: ERROR - saves_list is null in refresh_saves_list!")
		return

	saves_list.clear()
	save_files_data.clear()
	selected_save_index = -1

	if is_web_platform:
		saves_list.add_item("Loading saves...")
		saves_list.set_item_disabled(0, true)
		_update_button_states()
		SaveLoadManager.get_save_files()
		print("SaveLoadDialog: Initiated async save list fetch for web")
		return

	var save_files = SaveLoadManager.get_save_files()
	print("SaveLoadDialog: Found ", save_files.size(), " save files")
	_populate_saves_list(save_files)

func _populate_saves_list(save_files: Array) -> void:
	if not saves_list:
		return

	saves_list.clear()
	save_files_data.clear()
	selected_save_index = -1
	_set_preview_placeholder()  # SAVE-11: Reset preview when list refreshes

	for save_info in save_files:
		var display_name = _format_save_display_name(save_info)
		saves_list.add_item(display_name)
		save_files_data.append(save_info)

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
	refresh_saves_list()

func _format_save_display_name(save_info: Dictionary) -> String:
	var file_name = save_info.get("display_name", "Unknown")
	var metadata = save_info.get("metadata", {})

	var description = ""
	if metadata.has("save_info"):
		description = metadata["save_info"].get("description", "")

	if description.is_empty():
		description = file_name.replace(".w40ksave", "")

	var timestamp_text = ""
	if metadata.has("created_at"):
		var timestamp = metadata["created_at"]
		var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
		timestamp_text = "%04d-%02d-%02d %02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute
		]

	var prefix = ""
	if save_info.get("ownership", "own") == "shared":
		prefix = "[Shared] "

	return "%s%s - %s" % [prefix, description, timestamp_text]

func _create_save_tooltip(save_info: Dictionary) -> String:
	var metadata = save_info.get("metadata", {})
	var tooltip_lines = []

	var description = ""
	if metadata.has("save_info"):
		description = metadata["save_info"].get("description", "")
	if not description.is_empty():
		tooltip_lines.append("Name: " + description)

	if metadata.has("game_state"):
		var game_state = metadata["game_state"]
		tooltip_lines.append("Turn: " + str(game_state.get("turn", "Unknown")))
		tooltip_lines.append("Phase: " + str(game_state.get("phase", "Unknown")))
		tooltip_lines.append("Active Player: " + str(game_state.get("active_player", "Unknown")))

	tooltip_lines.append("File: " + save_info.get("display_name", "Unknown"))

	return "\n".join(tooltip_lines)

func _update_button_states() -> void:
	var has_selection = selected_save_index >= 0 and selected_save_index < save_files_data.size()
	if load_button:
		# SAVE-8: Keep load button hidden for non-host multiplayer clients
		if _is_multiplayer_client:
			load_button.visible = false
		else:
			load_button.disabled = not has_selection
	var is_shared = false
	if has_selection:
		is_shared = save_files_data[selected_save_index].get("ownership", "own") == "shared"
	if delete_button:
		delete_button.disabled = not has_selection or is_shared

func _sanitize_save_name(input_name: String) -> String:
	var sanitized = input_name.strip_edges()
	var invalid_chars = ["<", ">", ":", "\"", "|", "?", "*", "/", "\\"]

	for char in invalid_chars:
		sanitized = sanitized.replace(char, "_")

	if sanitized.length() > 200:
		sanitized = sanitized.substr(0, 200)

	return sanitized

func _generate_default_save_name() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "save_%04d-%02d-%02d_%02d-%02d-%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# ============================================================================
# UI Event Handlers
# ============================================================================

func _on_save_button_pressed() -> void:
	print("SaveLoadDialog: Save button pressed!")
	var raw_input = save_name_input.text.strip_edges()
	print("SaveLoadDialog: Input text: '", raw_input, "'")
	var save_name: String

	if raw_input.is_empty():
		save_name = _generate_default_save_name()
		print("SaveLoadDialog: Using default save name: ", save_name)
	else:
		save_name = _sanitize_save_name(raw_input)
		print("SaveLoadDialog: Using sanitized save name: ", save_name)

	# SAVE-5: On web, check the cached save list for overwrite protection
	# since SaveLoadManager.save_exists() can't do sync cloud checks
	if is_web_platform:
		if _save_exists_in_cache(save_name):
			print("SaveLoadDialog: SAVE-5 Web overwrite detected for: ", save_name)
			_show_overwrite_confirmation(save_name)
		else:
			_perform_save(save_name)
	elif SaveLoadManager.save_exists(save_name):
		_show_overwrite_confirmation(save_name)
	else:
		_perform_save(save_name)

# SAVE-5: Check if a save name exists in the cached save_files_data (for web platform)
func _save_exists_in_cache(save_name: String) -> bool:
	for save_info in save_files_data:
		var display_name = save_info.get("display_name", "")
		if display_name == save_name or display_name == save_name + ".w40ksave":
			print("SaveLoadDialog: SAVE-5 Found existing save in cache: ", display_name)
			return true
	return false

func _on_save_name_submitted(_text: String) -> void:
	_on_save_button_pressed()

func _on_save_selected(index: int) -> void:
	print("SaveLoadDialog: Save selected at index ", index)
	selected_save_index = index
	_update_button_states()
	_update_preview_panel()  # SAVE-11
	print("SaveLoadDialog: Button states updated - Load enabled: ", not load_button.disabled)

func _on_save_double_clicked(index: int) -> void:
	print("SaveLoadDialog: Save double-clicked at index ", index)
	selected_save_index = index

	# SAVE-8: Block double-click load for non-host multiplayer clients
	if _is_multiplayer_client:
		print("SaveLoadDialog: SAVE-8 Double-click load blocked for non-host client")
		return

	if selected_save_index >= 0 and selected_save_index < save_files_data.size():
		var save_info = save_files_data[selected_save_index]
		var save_name = save_info.get("display_name", "")
		var owner_id = save_info.get("owner_id", "")
		print("SaveLoadDialog: Double-click load of: ", save_name, " (owner_id: ", owner_id, ")")
		# SAVE-9: Show confirmation before loading
		_show_load_confirmation(save_name, owner_id)

func _on_load_button_pressed() -> void:
	print("SaveLoadDialog: Load button pressed!")
	if selected_save_index < 0 or selected_save_index >= save_files_data.size():
		print("SaveLoadDialog: No valid save selected for loading")
		return

	var save_info = save_files_data[selected_save_index]
	var save_name = save_info.get("display_name", "")
	var owner_id = save_info.get("owner_id", "")

	print("SaveLoadDialog: Requesting load of: ", save_name, " (owner_id: ", owner_id, ")")
	# SAVE-9: Show confirmation before loading
	_show_load_confirmation(save_name, owner_id)

func _on_delete_button_pressed() -> void:
	if selected_save_index < 0 or selected_save_index >= save_files_data.size():
		print("SaveLoadDialog: No valid save selected for deletion")
		return

	var save_info = save_files_data[selected_save_index]
	var save_name = save_info.get("display_name", "")

	_show_delete_confirmation(save_name)

func _on_cancel_button_pressed() -> void:
	hide()

func _on_main_menu_button_pressed() -> void:
	print("SaveLoadDialog: Main Menu button pressed!")
	_show_main_menu_confirmation()

# ============================================================================
# Confirmation Dialogs
# ============================================================================

## SAVE-9: Load confirmation dialog to warn about unsaved progress
func _show_load_confirmation(save_name: String, owner_id: String) -> void:
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Loading a save will replace your current game.\nAny unsaved progress will be lost.\n\nLoad '%s'?" % save_name.replace(".w40ksave", "")
	confirmation.title = "Load Save File?"

	var parent = get_tree().current_scene if get_tree().current_scene else get_parent()
	parent.add_child(confirmation)

	confirmation.confirmed.connect(func():
		confirmation.queue_free()
		_perform_load(save_name, owner_id)
	)
	confirmation.canceled.connect(func():
		print("SaveLoadDialog: SAVE-9 Load cancelled by user")
		confirmation.queue_free()
	)
	confirmation.close_requested.connect(func():
		confirmation.queue_free()
	)

	confirmation.popup_centered()

func _perform_load(save_name: String, owner_id: String) -> void:
	print("SaveLoadDialog: SAVE-9 Load confirmed, proceeding with: ", save_name)
	emit_signal("load_requested", save_name.replace(".w40ksave", ""), owner_id)
	hide()

func _show_main_menu_confirmation() -> void:
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Return to the Main Menu?\nAny unsaved progress will be lost."
	confirmation.title = "Return to Main Menu?"

	var parent = get_tree().current_scene if get_tree().current_scene else get_parent()
	parent.add_child(confirmation)

	confirmation.confirmed.connect(func():
		confirmation.queue_free()
		hide()
		emit_signal("main_menu_requested")
	)
	confirmation.canceled.connect(func():
		confirmation.queue_free()
	)
	confirmation.close_requested.connect(func():
		confirmation.queue_free()
	)

	confirmation.popup_centered()

func _show_overwrite_confirmation(save_name: String) -> void:
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "A save file named '%s' already exists.\nDo you want to overwrite it?" % save_name
	confirmation.title = "Overwrite Save File?"

	get_tree().current_scene.add_child(confirmation)

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

	confirmation.popup_centered()

func _show_delete_confirmation(save_name: String) -> void:
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Are you sure you want to delete the save file '%s'?\nThis action cannot be undone." % save_name.replace(".w40ksave", "")
	confirmation.title = "Delete Save File?"

	get_tree().current_scene.add_child(confirmation)

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

	confirmation.popup_centered()

# ============================================================================
# Core Actions
# ============================================================================

func _perform_save(save_name: String) -> void:
	print("SaveLoadDialog: Performing save with name: ", save_name)

	save_name_input.text = ""

	var user_description = save_name_input.text.strip_edges()
	if user_description.is_empty():
		user_description = save_name

	emit_signal("save_requested", save_name)
	hide()

func _perform_delete(save_name: String) -> void:
	var file_name_only = save_name.replace(".w40ksave", "")
	print("SaveLoadDialog: Performing delete of: ", file_name_only)

	emit_signal("delete_requested", file_name_only)

	call_deferred("refresh_saves_list")

# ============================================================================
# Public Interface
# ============================================================================

func show_dialog() -> void:
	# SAVE-8: Check if we're a non-host client in multiplayer
	_is_multiplayer_client = NetworkManager and NetworkManager.is_networked() and not NetworkManager.is_host()
	if _is_multiplayer_client:
		print("SaveLoadDialog: SAVE-8 Non-host client detected — Load button will be hidden")

	refresh_saves_list()
	save_name_input.text = ""
	visible = true

	# SAVE-8: Hide load button for non-host multiplayer clients
	if load_button:
		load_button.visible = not _is_multiplayer_client

	await get_tree().process_frame
	if save_name_input:
		save_name_input.grab_focus()
		print("SaveLoadDialog: Focus grabbed by save input")

	print("SaveLoadDialog: Dialog shown and focused")

func hide_dialog() -> void:
	hide()

# ============================================================================
# Input handling — Escape to close
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()

# ============================================================================
# SAVE-11: Preview Panel
# ============================================================================

func _set_preview_placeholder() -> void:
	if preview_label:
		preview_label.text = "[center][color=#b8a88a]Select a save file\nto see preview[/color][/center]"

func _update_preview_panel() -> void:
	if not preview_label:
		return

	if selected_save_index < 0 or selected_save_index >= save_files_data.size():
		_set_preview_placeholder()
		return

	var save_info = save_files_data[selected_save_index]
	var metadata = save_info.get("metadata", {})
	var preview = metadata.get("preview", {})

	# If no preview in metadata, try to extract from save file (legacy saves)
	if preview.is_empty() and not is_web_platform:
		var file_path = save_info.get("file_path", "")
		if not file_path.is_empty():
			print("SaveLoadDialog: SAVE-11 Extracting preview from save file: %s" % file_path)
			preview = SaveLoadManager.extract_preview_from_save(file_path)

	if preview.is_empty():
		preview_label.text = "[center][color=#b8a88a]No preview available[/color][/center]"
		return

	_render_preview(metadata, preview)

func _render_preview(metadata: Dictionary, preview: Dictionary) -> void:
	var game_state = metadata.get("game_state", {})
	var battle_round = preview.get("battle_round", game_state.get("turn", "?"))
	var phase_num = game_state.get("phase", -1)
	var phase_name = _get_phase_name(phase_num)

	var bbcode = ""

	# Header: Round & Phase
	bbcode += "[color=#c9a84c][b]Round %s[/b][/color]  [color=#8a7a6a]%s[/color]\n" % [str(battle_round), phase_name]
	bbcode += "[color=#4a3a2a]────────────────────────[/color]\n"

	# Player sections
	var players = preview.get("players", {})
	for player_id in ["1", "2"]:
		var p = players.get(player_id, {})
		if p.is_empty():
			continue

		var faction = p.get("faction", "Unknown")
		var detachment = p.get("detachment", "")
		var points = p.get("points", 0)
		var vp = p.get("vp", 0)
		var cp = p.get("cp", 0)
		var alive_units = p.get("alive_units", 0)
		var total_units = p.get("total_units", 0)
		var alive_models = p.get("alive_models", 0)
		var total_models = p.get("total_models", 0)

		# Player header
		bbcode += "\n[color=#c9a84c][b]Player %s[/b][/color]\n" % player_id
		bbcode += "[color=#d4c4a0]%s[/color]" % faction
		if not detachment.is_empty():
			bbcode += " [color=#8a7a6a](%s)[/color]" % detachment
		if points > 0:
			bbcode += " [color=#8a7a6a]%dpts[/color]" % int(points)
		bbcode += "\n"

		# VP / CP
		bbcode += "[color=#6aaa6a]VP: %d[/color]  [color=#6a8aaa]CP: %d[/color]\n" % [int(vp), int(cp)]

		# Unit counts
		var lost_units = total_units - alive_units
		var lost_models = total_models - alive_models
		bbcode += "[color=#b8a88a]Units: %d/%d[/color]" % [alive_units, total_units]
		if lost_units > 0:
			bbcode += "  [color=#aa6a6a](-%d)[/color]" % lost_units
		bbcode += "\n"
		bbcode += "[color=#b8a88a]Models: %d/%d[/color]" % [alive_models, total_models]
		if lost_models > 0:
			bbcode += "  [color=#aa6a6a](-%d)[/color]" % lost_models
		bbcode += "\n"

		# Army composition (unit names)
		var unit_names = p.get("unit_names", [])
		if not unit_names.is_empty():
			bbcode += "[color=#8a7a6a]"
			# Count duplicates
			var name_counts = {}
			for uname in unit_names:
				name_counts[uname] = name_counts.get(uname, 0) + 1
			var displayed = []
			for uname in name_counts:
				if name_counts[uname] > 1:
					displayed.append("%s x%d" % [uname, name_counts[uname]])
				else:
					displayed.append(uname)
			bbcode += ", ".join(displayed)
			bbcode += "[/color]\n"

	preview_label.text = bbcode

func _get_phase_name(phase_num: int) -> String:
	match phase_num:
		0: return "Formations"
		1: return "Deployment"
		2: return "Redeployment"
		3: return "Scout"
		4: return "Roll Off"
		5: return "Command"
		6: return "Movement"
		7: return "Shooting"
		8: return "Charge"
		9: return "Fight"
		10: return "Scoring"
		11: return "Morale"
		_: return "Unknown"

# Debug methods
func print_debug_info() -> void:
	print("=== SaveLoadDialog Debug Info ===")
	print("Save files data count: ", save_files_data.size())
	print("Selected save index: ", selected_save_index)
	print("Dialog visible: ", visible)
	print("Load button disabled: ", load_button.disabled)
	print("Delete button disabled: ", delete_button.disabled)
	print("==================================")
