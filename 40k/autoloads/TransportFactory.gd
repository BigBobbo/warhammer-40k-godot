extends Node

# TransportFactory - Creates appropriate MultiplayerPeer based on platform/URL
# Abstracts the difference between ENet (desktop LAN) and WebSocket (web/online)

signal connection_status_changed(status: String)

# Server configuration
var server_url: String = ""  # Set at runtime for production
const DEFAULT_ENET_PORT: int = 7777
const DEFAULT_WS_PORT: int = 9080
const PRODUCTION_SERVER_URL: String = "wss://warhammer-40k-godot.fly.dev"

func _ready() -> void:
	# Load server URL from config if available
	_load_server_config()
	print("TransportFactory: Initialized")

func _load_server_config() -> void:
	"""Load server URL from local config file or environment."""
	# On web platform, always use production server
	if OS.has_feature("web"):
		server_url = PRODUCTION_SERVER_URL
		print("TransportFactory: Web platform - using production server: ", server_url)
		return

	# Check for local config file first (for development)
	var local_config_path = "res://server_config.local.json"
	if FileAccess.file_exists(local_config_path):
		var file = FileAccess.open(local_config_path, FileAccess.READ)
		if file:
			var json = JSON.parse_string(file.get_as_text())
			if json and json.has("server_url"):
				server_url = json.server_url
				print("TransportFactory: Loaded local server URL: ", server_url)
			file.close()
			return

	# Check for production config in user:// (exported builds)
	var prod_config_path = "user://server_config.json"
	if FileAccess.file_exists(prod_config_path):
		var file = FileAccess.open(prod_config_path, FileAccess.READ)
		if file:
			var json = JSON.parse_string(file.get_as_text())
			if json and json.has("server_url"):
				server_url = json.server_url
				print("TransportFactory: Loaded production server URL: ", server_url)
			file.close()
			return

	# Default to environment variable or hardcoded fallback
	if OS.has_environment("WS_SERVER_URL"):
		server_url = OS.get_environment("WS_SERVER_URL")
		print("TransportFactory: Using environment server URL: ", server_url)
	else:
		# Development default - local server
		server_url = "ws://localhost:9080"
		print("TransportFactory: Using default local server URL: ", server_url)

func is_web_platform() -> bool:
	"""Check if running in a web browser."""
	return OS.has_feature("web")

func should_use_websocket(url_or_ip: String) -> bool:
	"""Determine if WebSocket should be used based on platform and URL."""
	# Always use WebSocket on web platform
	if is_web_platform():
		return true

	# Use WebSocket if URL starts with ws:// or wss://
	if url_or_ip.begins_with("ws://") or url_or_ip.begins_with("wss://"):
		return true

	return false

func create_server_peer(port: int = -1) -> MultiplayerPeer:
	"""Create a server peer. On web, this should not be called (servers run headless)."""
	if is_web_platform():
		push_error("TransportFactory: Cannot create server on web platform")
		return null

	var actual_port = port if port > 0 else DEFAULT_ENET_PORT
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(actual_port, 1)  # Max 1 client for 2-player game

	if error != OK:
		push_error("TransportFactory: Failed to create ENet server on port %d - error %d" % [actual_port, error])
		return null

	print("TransportFactory: Created ENet server on port ", actual_port)
	return peer

func create_client_peer(url_or_ip: String, port: int = -1) -> MultiplayerPeer:
	"""Create a client peer that connects to either ENet or WebSocket server."""
	if should_use_websocket(url_or_ip):
		return _create_websocket_client(url_or_ip, port)
	else:
		return _create_enet_client(url_or_ip, port)

func _create_websocket_client(url: String, port: int = -1) -> MultiplayerPeer:
	"""Create a WebSocket client peer."""
	var ws_url = url

	# Build proper WebSocket URL if needed
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		# Assume it's just a hostname/IP, construct full URL
		var actual_port = port if port > 0 else DEFAULT_WS_PORT
		# Use wss:// for production (non-localhost)
		if url == "localhost" or url == "127.0.0.1":
			ws_url = "ws://%s:%d" % [url, actual_port]
		else:
			ws_url = "wss://%s:%d" % [url, actual_port]

	print("TransportFactory: Creating WebSocket client to ", ws_url)
	connection_status_changed.emit("Connecting to %s..." % ws_url)

	var peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_client(ws_url)

	if error != OK:
		push_error("TransportFactory: Failed to create WebSocket client to %s - error %d" % [ws_url, error])
		connection_status_changed.emit("Connection failed")
		return null

	print("TransportFactory: WebSocket client created, connecting...")
	return peer

func _create_enet_client(ip: String, port: int = -1) -> MultiplayerPeer:
	"""Create an ENet client peer for LAN connections."""
	var actual_port = port if port > 0 else DEFAULT_ENET_PORT

	print("TransportFactory: Creating ENet client to %s:%d" % [ip, actual_port])
	connection_status_changed.emit("Connecting to %s:%d..." % [ip, actual_port])

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, actual_port)

	if error != OK:
		push_error("TransportFactory: Failed to create ENet client to %s:%d - error %d" % [ip, actual_port, error])
		connection_status_changed.emit("Connection failed")
		return null

	print("TransportFactory: ENet client created, connecting...")
	return peer

func create_websocket_server(port: int = -1) -> MultiplayerPeer:
	"""Create a WebSocket server peer (for dedicated server)."""
	var actual_port = port if port > 0 else DEFAULT_WS_PORT

	print("TransportFactory: Creating WebSocket server on port ", actual_port)

	var peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_server(actual_port)

	if error != OK:
		push_error("TransportFactory: Failed to create WebSocket server on port %d - error %d" % [actual_port, error])
		return null

	print("TransportFactory: WebSocket server created on port ", actual_port)
	return peer

func get_production_server_url() -> String:
	"""Get the production server URL for web clients."""
	return server_url

func set_server_url(url: String) -> void:
	"""Override the server URL (useful for testing or dynamic configuration)."""
	server_url = url
	print("TransportFactory: Server URL set to ", url)
