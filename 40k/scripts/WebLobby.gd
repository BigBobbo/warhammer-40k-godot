extends Control

# WebLobby - Online matchmaking UI for web-based multiplayer
# Uses WebSocketRelay for game code creation and joining

signal game_joined(game_code: String)
signal game_created(game_code: String)
signal back_pressed()

# UI State
enum LobbyState { IDLE, CONNECTING, CREATING, JOINING, WAITING_FOR_GUEST, CONNECTED }
var current_state: LobbyState = LobbyState.IDLE

# Current game code
var game_code: String = ""

# References
var relay: Node = null

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
	# Get relay reference
	relay = get_node_or_null("/root/WebSocketRelay")
	if not relay:
		push_error("WebLobby: WebSocketRelay not found")
		return

	# Connect UI signals
	join_button.pressed.connect(_on_join_pressed)
	create_button.pressed.connect(_on_create_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	share_button.pressed.connect(_on_share_pressed)
	back_button.pressed.connect(_on_back_pressed)
	code_input.text_changed.connect(_on_code_input_changed)
	code_input.text_submitted.connect(_on_code_submitted)

	# Connect relay signals
	relay.connected.connect(_on_relay_connected)
	relay.disconnected.connect(_on_relay_disconnected)
	relay.connection_error.connect(_on_connection_error)
	relay.game_created.connect(_on_game_created)
	relay.game_joined.connect(_on_game_joined)
	relay.guest_joined.connect(_on_guest_joined)
	relay.opponent_disconnected.connect(_on_opponent_disconnected)
	relay.message_received.connect(_on_message_received)

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

	game_code = code
	_update_ui_state(LobbyState.CONNECTING)
	_set_status("Connecting to server...")

	relay.connect_to_server()
	# Will call _do_join after connected

func _on_create_pressed() -> void:
	_update_ui_state(LobbyState.CONNECTING)
	_set_status("Connecting to server...")

	relay.connect_to_server()
	# Will call _do_create after connected

func _on_relay_connected() -> void:
	print("WebLobby: Connected to relay server")

	if current_state == LobbyState.CONNECTING:
		# Check if we're creating or joining
		if game_code.is_empty():
			_do_create()
		else:
			_do_join()

func _do_create() -> void:
	_update_ui_state(LobbyState.CREATING)
	_set_status("Creating game...")
	relay.create_game()

func _do_join() -> void:
	_update_ui_state(LobbyState.JOINING)
	_set_status("Joining game %s..." % game_code)
	relay.join_game(game_code)

func _on_relay_disconnected() -> void:
	print("WebLobby: Disconnected from relay server")
	_update_ui_state(LobbyState.IDLE)
	_show_error("Disconnected from server")

func _on_connection_error(message: String) -> void:
	print("WebLobby: Connection error: ", message)
	_update_ui_state(LobbyState.IDLE)
	_show_error(message)

func _on_game_created(code: String) -> void:
	game_code = code
	game_code_label.text = code
	copy_button.visible = true
	share_button.visible = OS.has_feature("web")

	_update_ui_state(LobbyState.WAITING_FOR_GUEST)
	_set_status("Waiting for opponent...\nShare your code: " + code)

	game_created.emit(code)

func _on_game_joined(code: String) -> void:
	game_code = code
	_update_ui_state(LobbyState.CONNECTED)
	_set_status("Connected! Waiting for host to start...")
	game_joined.emit(code)

func _on_guest_joined() -> void:
	_update_ui_state(LobbyState.CONNECTED)
	_set_status("Opponent connected! Starting game...")

	# Notify guest that we're starting the game
	relay.send_game_data({"action": "start_game"})

	# Start the game after a short delay
	await get_tree().create_timer(1.0).timeout
	_start_game()

func _on_opponent_disconnected() -> void:
	_show_error("Opponent disconnected")
	_update_ui_state(LobbyState.IDLE)
	relay.disconnect_from_server()

func _on_message_received(data: Dictionary) -> void:
	# Handle game messages from the relay
	print("WebLobby: Received game data: ", data)

	var action = data.get("action", "")
	match action:
		"start_game":
			print("WebLobby: Host started the game")
			_start_game()

func _start_game() -> void:
	print("WebLobby: Starting game...")

	# Initialize GameState if needed
	if GameState.state.is_empty():
		GameState.initialize_default_state()

	# Mark as coming from web multiplayer lobby
	if not GameState.state.has("meta"):
		GameState.state["meta"] = {}
	GameState.state.meta["from_multiplayer_lobby"] = true
	GameState.state.meta["from_web_lobby"] = true
	GameState.state.meta["game_code"] = game_code
	GameState.state.meta["is_host"] = relay.is_game_host()

	print("WebLobby: Game state initialized, is_host=", relay.is_game_host())

	# Transition to main scene - relay continues running for message passing
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

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
	# Use JavaScript to call the Web Share API
	var js_code = """
		if (navigator.share) {
			navigator.share({
				title: 'Join my Warhammer 40K game!',
				text: 'Join my game with code: %s'
			});
		}
	""" % game_code
	JavaScriptBridge.eval(js_code)

func _on_back_pressed() -> void:
	# Disconnect if connected
	relay.disconnect_from_server()
	back_pressed.emit()
	get_tree().change_scene_to_file("res://scenes/MultiplayerLobby.tscn")

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
			game_code = ""

		LobbyState.CONNECTING, LobbyState.CREATING, LobbyState.JOINING:
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
	status_label.remove_theme_color_override("font_color")

func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)

func _show_toast(message: String) -> void:
	# Simple toast notification
	var original_text = status_label.text
	status_label.text = message

	await get_tree().create_timer(2.0).timeout

	if status_label.text == message:
		status_label.text = original_text
