extends Control

# WebLobby - Online matchmaking UI for web-based multiplayer
# Provides game code creation and joining functionality

signal game_joined(game_code: String)
signal game_created(game_code: String)
signal back_pressed()

# UI State
enum LobbyState { IDLE, CREATING, JOINING, WAITING_FOR_GUEST, CONNECTED }
var current_state: LobbyState = LobbyState.IDLE

# Current game code
var game_code: String = ""

# UI References
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var code_input: LineEdit = $VBoxContainer/JoinSection/CodeInput
@onready var join_button: Button = $VBoxContainer/JoinSection/JoinButton
@onready var create_button: Button = $VBoxContainer/CreateSection/CreateButton
@onready var game_code_label: Label = $VBoxContainer/CreateSection/GameCodeLabel
@onready var copy_button: Button = $VBoxContainer/CreateSection/CopyButton
@onready var share_button: Button = $VBoxContainer/CreateSection/ShareButton
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var connecting_indicator: Control = $VBoxContainer/ConnectingIndicator

func _ready() -> void:
	# Connect signals
	join_button.pressed.connect(_on_join_pressed)
	create_button.pressed.connect(_on_create_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	share_button.pressed.connect(_on_share_pressed)
	back_button.pressed.connect(_on_back_pressed)
	code_input.text_changed.connect(_on_code_input_changed)
	code_input.text_submitted.connect(_on_code_submitted)

	# Connect to NetworkManager signals
	var network = get_node_or_null("/root/NetworkManager")
	if network:
		network.game_code_received.connect(_on_game_code_received)
		network.peer_connected.connect(_on_peer_connected)
		network.connection_failed.connect(_on_connection_failed)
		network.game_started.connect(_on_game_started)

	# Initialize UI
	_update_ui_state(LobbyState.IDLE)

	# Hide share button on desktop (Web Share API only works in browsers)
	if not OS.has_feature("web"):
		share_button.visible = false

	print("WebLobby: Ready")

func _on_join_pressed() -> void:
	var code = code_input.text.strip_edges().to_upper()

	if code.length() != 6:
		_show_error("Please enter a 6-character game code")
		return

	_update_ui_state(LobbyState.JOINING)
	_set_status("Joining game %s..." % code)

	var network = get_node_or_null("/root/NetworkManager")
	if network:
		var result = network.join_online_game(code)
		if result != OK:
			_update_ui_state(LobbyState.IDLE)
			_show_error("Failed to connect to server")

func _on_create_pressed() -> void:
	_update_ui_state(LobbyState.CREATING)
	_set_status("Creating game...")

	var network = get_node_or_null("/root/NetworkManager")
	if network:
		var result = network.create_online_game()
		if result != OK:
			_update_ui_state(LobbyState.IDLE)
			_show_error("Failed to connect to server")

func _on_copy_pressed() -> void:
	if game_code.is_empty():
		return

	DisplayServer.clipboard_set(game_code)
	_show_toast("Code copied to clipboard!")

func _on_share_pressed() -> void:
	if game_code.is_empty():
		return

	# Use Web Share API if available (browser only)
	if OS.has_feature("web"):
		_web_share_code()
	else:
		# Fallback to clipboard
		_on_copy_pressed()

func _web_share_code() -> void:
	"""Use the Web Share API to share the game code."""
	# This requires JavaScript interop in Godot web exports
	var share_data = {
		"title": "Join my Warhammer 40K game!",
		"text": "Join my game with code: " + game_code,
		"url": ""  # Could include a direct join URL
	}

	# Call JavaScript share API
	if JavaScriptBridge.get_interface("navigator"):
		var navigator = JavaScriptBridge.get_interface("navigator")
		if navigator.share:
			navigator.share(share_data)
		else:
			_on_copy_pressed()  # Fallback
	else:
		_on_copy_pressed()  # Fallback

func _on_back_pressed() -> void:
	# Disconnect if connected
	var network = get_node_or_null("/root/NetworkManager")
	if network:
		network.disconnect_network()

	back_pressed.emit()

func _on_code_input_changed(new_text: String) -> void:
	# Auto-uppercase and limit to 6 characters
	var filtered = ""
	for c in new_text.to_upper():
		if c in "ABCDEFGHJKMNPQRSTUVWXYZ23456789":
			filtered += c
	if filtered.length() > 6:
		filtered = filtered.substr(0, 6)

	if filtered != new_text:
		code_input.text = filtered
		code_input.caret_column = filtered.length()

	# Enable/disable join button based on code length
	join_button.disabled = filtered.length() != 6

func _on_code_submitted(_text: String) -> void:
	if not join_button.disabled:
		_on_join_pressed()

func _on_game_code_received(code: String) -> void:
	game_code = code
	game_code_label.text = code
	copy_button.visible = true
	share_button.visible = OS.has_feature("web")

	_update_ui_state(LobbyState.WAITING_FOR_GUEST)
	_set_status("Waiting for opponent...\nShare your code: " + code)

	game_created.emit(code)

func _on_peer_connected(_peer_id: int) -> void:
	if current_state == LobbyState.WAITING_FOR_GUEST:
		_update_ui_state(LobbyState.CONNECTED)
		_set_status("Opponent connected! Starting game...")
	elif current_state == LobbyState.JOINING:
		_update_ui_state(LobbyState.CONNECTED)
		_set_status("Connected! Waiting for game to start...")
		game_joined.emit(game_code)

func _on_connection_failed(reason: String) -> void:
	_update_ui_state(LobbyState.IDLE)
	_show_error("Connection failed: " + reason)

func _on_game_started() -> void:
	_set_status("Game starting...")
	# The scene change will be handled by NetworkManager

func _update_ui_state(state: LobbyState) -> void:
	current_state = state

	match state:
		LobbyState.IDLE:
			join_button.disabled = code_input.text.length() != 6
			create_button.disabled = false
			code_input.editable = true
			game_code_label.text = "------"
			copy_button.visible = false
			share_button.visible = false
			connecting_indicator.visible = false

		LobbyState.CREATING, LobbyState.JOINING:
			join_button.disabled = true
			create_button.disabled = true
			code_input.editable = false
			connecting_indicator.visible = true

		LobbyState.WAITING_FOR_GUEST:
			join_button.disabled = true
			create_button.disabled = true
			code_input.editable = false
			connecting_indicator.visible = false

		LobbyState.CONNECTED:
			join_button.disabled = true
			create_button.disabled = true
			code_input.editable = false
			connecting_indicator.visible = true

func _set_status(text: String) -> void:
	status_label.text = text

func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)

	# Reset color after delay
	await get_tree().create_timer(3.0).timeout
	status_label.remove_theme_color_override("font_color")

func _show_toast(message: String) -> void:
	# Simple toast notification
	var original_text = status_label.text
	status_label.text = message

	await get_tree().create_timer(2.0).timeout

	if status_label.text == message:
		status_label.text = original_text
