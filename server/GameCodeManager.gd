extends Node

# GameCodeManager - Generates and manages 6-character game codes for matchmaking
# Used by the dedicated server to create/track game sessions

signal game_created(game_code: String, host_peer_id: int)
signal game_joined(game_code: String, guest_peer_id: int)
signal game_removed(game_code: String)

# Character set for game codes (excludes confusable chars: 0/O, 1/I/L)
const CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH = 6

# Active games: game_code -> GameSession
var active_games: Dictionary = {}

# Peer to game mapping: peer_id -> game_code
var peer_to_game: Dictionary = {}

# Maximum concurrent games
const MAX_GAMES = 50

# Game session timeout (seconds)
const GAME_TIMEOUT = 300.0  # 5 minutes

class GameSession:
	var game_code: String = ""
	var host_peer_id: int = -1
	var guest_peer_id: int = -1
	var created_at: float = 0.0
	var last_activity: float = 0.0
	var state: String = "waiting"  # waiting, playing, finished

	func _init(code: String, host_id: int) -> void:
		game_code = code
		host_peer_id = host_id
		created_at = Time.get_unix_time_from_system()
		last_activity = created_at

	func is_full() -> bool:
		return guest_peer_id != -1

	func update_activity() -> void:
		last_activity = Time.get_unix_time_from_system()

	func get_age() -> float:
		return Time.get_unix_time_from_system() - last_activity

	func to_dict() -> Dictionary:
		return {
			"code": game_code,
			"host": host_peer_id,
			"guest": guest_peer_id,
			"state": state,
			"created": created_at
		}

func _ready() -> void:
	# Set up cleanup timer
	var timer = Timer.new()
	timer.wait_time = 60.0  # Check every minute
	timer.timeout.connect(_cleanup_stale_games)
	timer.autostart = true
	add_child(timer)
	print("GameCodeManager: Initialized")

func generate_code() -> String:
	"""Generate a unique 6-character game code."""
	var code = ""
	var attempts = 0

	while attempts < 100:
		code = ""
		for i in range(CODE_LENGTH):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]

		# Ensure uniqueness
		if not active_games.has(code):
			return code

		attempts += 1

	push_error("GameCodeManager: Failed to generate unique code after 100 attempts")
	return ""

func create_game(host_peer_id: int) -> String:
	"""Create a new game session and return the game code."""
	if active_games.size() >= MAX_GAMES:
		push_warning("GameCodeManager: Maximum game limit reached")
		return ""

	# Check if peer already has a game
	if peer_to_game.has(host_peer_id):
		var existing_code = peer_to_game[host_peer_id]
		push_warning("GameCodeManager: Peer %d already in game %s" % [host_peer_id, existing_code])
		return existing_code

	var code = generate_code()
	if code.is_empty():
		return ""

	var session = GameSession.new(code, host_peer_id)
	active_games[code] = session
	peer_to_game[host_peer_id] = code

	print("GameCodeManager: Created game %s for peer %d" % [code, host_peer_id])
	game_created.emit(code, host_peer_id)

	return code

func join_game(game_code: String, guest_peer_id: int) -> Dictionary:
	"""Attempt to join an existing game. Returns result dictionary."""
	# Normalize code to uppercase
	game_code = game_code.to_upper().strip_edges()

	if not active_games.has(game_code):
		return {"success": false, "error": "Game not found"}

	var session: GameSession = active_games[game_code]

	if session.is_full():
		return {"success": false, "error": "Game is full"}

	if session.host_peer_id == guest_peer_id:
		return {"success": false, "error": "Cannot join your own game"}

	# Check if peer is already in another game
	if peer_to_game.has(guest_peer_id):
		var existing_code = peer_to_game[guest_peer_id]
		if existing_code != game_code:
			return {"success": false, "error": "Already in another game"}

	session.guest_peer_id = guest_peer_id
	session.state = "playing"
	session.update_activity()
	peer_to_game[guest_peer_id] = game_code

	print("GameCodeManager: Peer %d joined game %s" % [guest_peer_id, game_code])
	game_joined.emit(game_code, guest_peer_id)

	return {
		"success": true,
		"host_peer_id": session.host_peer_id,
		"game_code": game_code
	}

func remove_game(game_code: String) -> void:
	"""Remove a game session."""
	if not active_games.has(game_code):
		return

	var session: GameSession = active_games[game_code]

	# Clean up peer mappings
	if peer_to_game.get(session.host_peer_id) == game_code:
		peer_to_game.erase(session.host_peer_id)
	if peer_to_game.get(session.guest_peer_id) == game_code:
		peer_to_game.erase(session.guest_peer_id)

	active_games.erase(game_code)

	print("GameCodeManager: Removed game %s" % game_code)
	game_removed.emit(game_code)

func on_peer_disconnected(peer_id: int) -> void:
	"""Handle peer disconnection."""
	if not peer_to_game.has(peer_id):
		return

	var game_code = peer_to_game[peer_id]
	var session: GameSession = active_games.get(game_code)

	if not session:
		peer_to_game.erase(peer_id)
		return

	# If host disconnects, remove the entire game
	if session.host_peer_id == peer_id:
		print("GameCodeManager: Host disconnected, removing game %s" % game_code)
		remove_game(game_code)
	# If guest disconnects, just clear the guest
	elif session.guest_peer_id == peer_id:
		print("GameCodeManager: Guest disconnected from game %s" % game_code)
		session.guest_peer_id = -1
		session.state = "waiting"
		peer_to_game.erase(peer_id)

func get_game_for_peer(peer_id: int) -> String:
	"""Get the game code for a peer."""
	return peer_to_game.get(peer_id, "")

func get_session(game_code: String) -> GameSession:
	"""Get a game session by code."""
	return active_games.get(game_code.to_upper())

func get_active_game_count() -> int:
	"""Get the number of active games."""
	return active_games.size()

func update_game_activity(game_code: String) -> void:
	"""Update the last activity timestamp for a game."""
	var session = active_games.get(game_code)
	if session:
		session.update_activity()

func _cleanup_stale_games() -> void:
	"""Remove games that have been inactive for too long."""
	var to_remove: Array[String] = []

	for code in active_games:
		var session: GameSession = active_games[code]
		if session.get_age() > GAME_TIMEOUT:
			to_remove.append(code)

	for code in to_remove:
		print("GameCodeManager: Removing stale game %s" % code)
		remove_game(code)

	if to_remove.size() > 0:
		print("GameCodeManager: Cleaned up %d stale games, %d remaining" % [to_remove.size(), active_games.size()])

func get_stats() -> Dictionary:
	"""Get server statistics."""
	var waiting = 0
	var playing = 0

	for session in active_games.values():
		if session.state == "waiting":
			waiting += 1
		elif session.state == "playing":
			playing += 1

	return {
		"total_games": active_games.size(),
		"waiting": waiting,
		"playing": playing,
		"max_games": MAX_GAMES
	}
