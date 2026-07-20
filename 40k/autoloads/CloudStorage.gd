extends Node

# CloudStorage - HTTP client for server-side persistence
# Handles player registration, game saves, and army lists via REST API

signal saves_list_received(saves: Array)
signal save_uploaded(save_name: String)
signal save_downloaded(save_name: String, metadata: Dictionary, game_data: String)
signal save_deleted(save_name: String)
signal armies_list_received(armies: Array)
signal army_uploaded(army_name: String)
signal army_downloaded(army_name: String, army_data: Dictionary)
signal army_deleted(army_name: String)
signal request_failed(operation: String, error: String)
signal player_registered()
signal game_participation_registered(game_id: String)

const PRODUCTION_URL = "https://warhammer-40k-godot.fly.dev"
const LOCAL_URL = "http://localhost:9080"
const REQUEST_TIMEOUT = 15.0  # Covers fly.io cold start

# Cold-start resilience: the fly.io server scales to zero when idle
# (min_machines_running = 0). The first request after an idle period has to wake
# the machine, which can time out (transport failure) or return a gateway error
# (502/503/504) before Node is listening. Without a retry, that transient
# failure surfaces to the player as an *empty* save/army list — indistinguishable
# from "you have nothing saved". We transparently retry those specific failures a
# few times with a short backoff before giving up.
const MAX_TRANSPORT_RETRIES = 3
const RETRY_BACKOFF_BASE = 1.5  # seconds; multiplied by the attempt number

var base_url: String = ""
var player_id: String = ""
var http_request: HTTPRequest = null
var request_queue: Array = []
var is_processing: bool = false
var _current_request: Dictionary = {}  # The request currently in flight (for retries)

# True when this client is meant to talk to a real save/army server: always on
# web, on desktop when a server_config.json explicitly names one, and on
# exported desktop builds (the itch.io Linux download / Steam Deck build),
# which default to the production server so they share the same cloud saves
# and armies as the browser build. False only for the implicit dev fallback
# (running from source with no config), where localhost:9080 may not have a
# server behind it — SaveLoadManager uses this to decide whether desktop
# saves should sync to the cloud.
var is_remote_configured: bool = false

# Resolved in _init (not _ready) on purpose: autoloads are ALL instantiated
# before ANY _ready runs, but SaveLoadManager is registered before CloudStorage
# in project.godot — resolving here guarantees SaveLoadManager._ready sees the
# final base_url/is_remote_configured values.
func _init() -> void:
	base_url = _resolve_base_url()

func _resolve_base_url() -> String:
	if OS.has_feature("web"):
		is_remote_configured = true
		return PRODUCTION_URL

	# Explicit override: res://server_config.json (dev checkout) or
	# user://server_config.json (player-writable, lives next to the saves).
	for config_path in ["res://server_config.json", "user://server_config.json"]:
		var override_url = _read_api_url_from_config(config_path)
		if not override_url.is_empty():
			is_remote_configured = true
			print("CloudStorage: Using server URL from %s" % config_path)
			return override_url

	# Exported player builds (no editor feature) default to the production
	# server so the downloadable Linux/macOS builds see the same cloud saves
	# and armies as the itch.io browser build.
	if not OS.has_feature("editor"):
		is_remote_configured = true
		return PRODUCTION_URL

	# Running from source with no config: keep the local dev server default.
	return LOCAL_URL

func _read_api_url_from_config(config_path: String) -> String:
	if not FileAccess.file_exists(config_path):
		return ""
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return ""
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) == OK and json.data is Dictionary and json.data.has("api_url"):
		return str(json.data.api_url)
	return ""

func _ready() -> void:
	print("CloudStorage: Using server URL: ", base_url, " (remote_configured: ", is_remote_configured, ")")

	# Setup HTTP request node
	http_request = HTTPRequest.new()
	http_request.timeout = REQUEST_TIMEOUT
	http_request.request_completed.connect(_on_request_completed)
	add_child(http_request)

	# Initialize player ID
	_init_player_id()

	# Register with server
	_register_player()

func _init_player_id() -> void:
	if OS.has_feature("web"):
		# Web: try localStorage first for player ID persistence. On itch.io the game
		# runs in a third-party iframe where the browser may partition or block
		# localStorage, so we keep a user:// (IndexedDB-backed) copy as a fallback.
		# Note: saves are now a shared/central store, so a fresh/unstable player ID
		# no longer hides previously-saved games — it only affects ownership labels.
		var stored_id = JavaScriptBridge.eval("localStorage.getItem('w40k_player_id')")
		if stored_id != null and str(stored_id) != "null" and str(stored_id).length() > 8:
			player_id = str(stored_id)
			print("CloudStorage: Loaded player ID from localStorage: ", player_id.substr(0, 8), "...")
		else:
			# Fall back to a user:// copy if localStorage was empty/blocked
			var id_path = "user://player_id.txt"
			if FileAccess.file_exists(id_path):
				var file = FileAccess.open(id_path, FileAccess.READ)
				if file:
					var file_id = file.get_as_text().strip_edges()
					file.close()
					if file_id.length() > 8:
						player_id = file_id
						print("CloudStorage: Loaded player ID from user:// fallback: ", player_id.substr(0, 8), "...")

			if player_id.is_empty():
				player_id = _generate_uuid()
				print("CloudStorage: Generated new player ID: ", player_id.substr(0, 8), "...")

			# Persist to both localStorage and user:// (each is best-effort)
			JavaScriptBridge.eval("try { localStorage.setItem('w40k_player_id', '%s'); } catch (e) {}" % player_id)
			var out_file = FileAccess.open(id_path, FileAccess.WRITE)
			if out_file:
				out_file.store_string(player_id)
				out_file.close()
	else:
		# Desktop: use file for player ID persistence
		var id_path = "user://player_id.txt"
		if FileAccess.file_exists(id_path):
			var file = FileAccess.open(id_path, FileAccess.READ)
			if file:
				player_id = file.get_as_text().strip_edges()
				file.close()
				if player_id.length() > 8:
					print("CloudStorage: Loaded player ID from file: ", player_id.substr(0, 8), "...")
				else:
					player_id = ""

		if player_id.is_empty():
			player_id = _generate_uuid()
			var file = FileAccess.open(id_path, FileAccess.WRITE)
			if file:
				file.store_string(player_id)
				file.close()
			print("CloudStorage: Generated new player ID: ", player_id.substr(0, 8), "...")

func _generate_uuid() -> String:
	# Generate a v4-style UUID
	var hex_chars = "0123456789abcdef"
	var uuid = ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		if i == 12:
			uuid += "4"  # Version 4
		elif i == 16:
			uuid += hex_chars[8 + (randi() % 4)]  # Variant bits
		else:
			uuid += hex_chars[randi() % 16]
	return uuid

func _register_player() -> void:
	_enqueue_request("POST", "/api/players", null, "register", {})

# ============================================================================
# Public API - Saves
# ============================================================================

func list_saves() -> void:
	_enqueue_request("GET", "/api/saves", null, "list_saves", {})

func get_save(save_name: String) -> void:
	_enqueue_request("GET", "/api/saves/" + save_name.uri_encode(), null, "get_save", {"save_name": save_name})

func put_save(save_name: String, metadata: Dictionary, game_data: String) -> void:
	var body = {
		"metadata": metadata,
		"game_data": game_data
	}
	_enqueue_request("PUT", "/api/saves/" + save_name.uri_encode(), body, "put_save", {"save_name": save_name})

func delete_save(save_name: String) -> void:
	_enqueue_request("DELETE", "/api/saves/" + save_name.uri_encode(), null, "delete_save", {"save_name": save_name})

func get_shared_save(save_name: String, owner_id: String) -> void:
	var path = "/api/saves/" + save_name.uri_encode() + "?owner_id=" + owner_id.uri_encode()
	_enqueue_request("GET", path, null, "get_save", {"save_name": save_name})

func register_game_participation(game_id: String) -> void:
	_enqueue_request("POST", "/api/games/" + game_id.uri_encode() + "/join", null, "register_game", {"game_id": game_id})

# ============================================================================
# Public API - Armies
# ============================================================================

func list_armies() -> void:
	_enqueue_request("GET", "/api/armies", null, "list_armies", {}, true)

func get_army(army_name: String) -> void:
	_enqueue_request("GET", "/api/armies/" + army_name.uri_encode(), null, "get_army", {"army_name": army_name}, true)

func put_army(army_name: String, army_data: Dictionary) -> void:
	var body = {"army_data": army_data}
	_enqueue_request("PUT", "/api/armies/" + army_name.uri_encode(), body, "put_army", {"army_name": army_name})

func delete_army(army_name: String) -> void:
	_enqueue_request("DELETE", "/api/armies/" + army_name.uri_encode(), null, "delete_army", {"army_name": army_name})

# ============================================================================
# HTTP Request Queue
# ============================================================================

func _enqueue_request(method: String, path: String, body, operation: String, context: Dictionary, public_request: bool = false) -> void:
	request_queue.append({
		"method": method,
		"path": path,
		"body": body,
		"operation": operation,
		"context": context,
		"public": public_request
	})
	if not is_processing:
		_process_next_request()

func _process_next_request() -> void:
	if request_queue.is_empty():
		is_processing = false
		return

	is_processing = true
	var req = request_queue.pop_front()
	_current_request = req
	_send_request(req)

# Send (or re-send, on retry) a single request. The request dict may carry an
# "_attempts" counter that _on_request_completed increments before re-sending.
func _send_request(req: Dictionary) -> void:
	var url = base_url + req.path
	var headers = ["Content-Type: application/json"]
	if not req.get("public", false):
		headers.append("X-Player-ID: " + player_id)

	var http_method = _http_method_enum(req.method)

	var body_str = ""
	if req.body != null:
		body_str = JSON.stringify(req.body)

	# Store current operation info for the callback
	http_request.set_meta("current_operation", req.operation)
	http_request.set_meta("current_context", req.context)

	var attempt = int(req.get("_attempts", 0))
	if attempt > 0:
		print("CloudStorage: RETRY %d/%d %s %s" % [attempt, MAX_TRANSPORT_RETRIES, req.method, req.path])
	else:
		print("CloudStorage: %s %s" % [req.method, req.path])
	var error = http_request.request(url, headers, http_method, body_str)
	if error != OK:
		print("CloudStorage: Failed to send request: ", error)
		emit_signal("request_failed", req.operation, "Failed to send HTTP request")
		_process_next_request()

func _http_method_enum(method: String) -> int:
	match method:
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation = http_request.get_meta("current_operation", "unknown")
	var context = http_request.get_meta("current_context", {})

	# Cold-start resilience: a transport failure (timeout / can't connect) or a
	# gateway error (502/503/504) is the signature of the fly.io machine waking
	# from idle. Retry a few times before surfacing an error, so a sleeping
	# server does not look like an empty save list to the player.
	var is_transport_failure = result != HTTPRequest.RESULT_SUCCESS
	var is_gateway_error = response_code == 502 or response_code == 503 or response_code == 504
	if is_transport_failure or is_gateway_error:
		var attempts = int(_current_request.get("_attempts", 0))
		if attempts < MAX_TRANSPORT_RETRIES:
			_current_request["_attempts"] = attempts + 1
			var delay = RETRY_BACKOFF_BASE * float(attempts + 1)
			var reason = ("transport result %d" % result) if is_transport_failure else ("HTTP %d" % response_code)
			print("CloudStorage: %s failed (%s) — retry %d/%d in %.1fs (server may be waking up)" % [
				operation, reason, attempts + 1, MAX_TRANSPORT_RETRIES, delay])
			await get_tree().create_timer(delay).timeout
			_send_request(_current_request)
			return

	if is_transport_failure:
		var error_msg = "HTTP request failed (result: %d)" % result
		print("CloudStorage: %s - %s" % [operation, error_msg])
		emit_signal("request_failed", operation, error_msg)
		_process_next_request()
		return

	if response_code < 200 or response_code >= 300:
		var error_msg = "Server returned %d" % response_code
		var body_text = body.get_string_from_utf8()
		if not body_text.is_empty():
			var json = JSON.new()
			if json.parse(body_text) == OK and json.data is Dictionary:
				error_msg = json.data.get("error", error_msg)
		print("CloudStorage: %s - %s" % [operation, error_msg])
		emit_signal("request_failed", operation, error_msg)
		_process_next_request()
		return

	# Parse response body
	var response_data = {}
	var body_text = body.get_string_from_utf8()
	if not body_text.is_empty():
		var json = JSON.new()
		if json.parse(body_text) == OK and json.data is Dictionary:
			response_data = json.data

	# Route response to appropriate handler
	match operation:
		"register":
			print("CloudStorage: Player registered successfully")
			emit_signal("player_registered")
		"list_saves":
			var saves = response_data.get("saves", [])
			print("CloudStorage: Received %d saves" % saves.size())
			emit_signal("saves_list_received", saves)
		"get_save":
			var save_name = context.get("save_name", "")
			var metadata = response_data.get("metadata", {})
			var game_data = response_data.get("game_data", "")
			print("CloudStorage: Downloaded save: ", save_name)
			emit_signal("save_downloaded", save_name, metadata, game_data)
		"put_save":
			var save_name = context.get("save_name", "")
			print("CloudStorage: Uploaded save: ", save_name)
			emit_signal("save_uploaded", save_name)
		"delete_save":
			var save_name = context.get("save_name", "")
			print("CloudStorage: Deleted save: ", save_name)
			emit_signal("save_deleted", save_name)
		"list_armies":
			var armies = response_data.get("armies", [])
			print("CloudStorage: Received %d armies" % armies.size())
			emit_signal("armies_list_received", armies)
		"get_army":
			var army_name = context.get("army_name", "")
			var army_data = response_data.get("army_data", {})
			print("CloudStorage: Downloaded army: ", army_name)
			emit_signal("army_downloaded", army_name, army_data)
		"put_army":
			var army_name = context.get("army_name", "")
			print("CloudStorage: Uploaded army: ", army_name)
			emit_signal("army_uploaded", army_name)
		"delete_army":
			var army_name = context.get("army_name", "")
			print("CloudStorage: Deleted army: ", army_name)
			emit_signal("army_deleted", army_name)
		"register_game":
			var game_id = context.get("game_id", "")
			print("CloudStorage: Game participation registered: ", game_id)
			emit_signal("game_participation_registered", game_id)

	_process_next_request()
