extends AcceptDialog

# DisconnectDialog - P2-41: Graceful disconnect handling
#
# Shown when the opponent disconnects during a multiplayer game.
# Provides options to wait for reconnection, save the game state,
# continue in single-player mode, or claim victory.

signal save_game_requested()
signal continue_single_player_requested()
signal claim_victory_requested()

const RECONNECT_GRACE_SECONDS: float = 60.0

var disconnected_player: int = 0
var countdown_timer: Timer = null
var countdown_label: Label = null
var seconds_remaining: float = RECONNECT_GRACE_SECONDS
var _waiting_for_reconnect: bool = true

func _init():
	title = "Opponent Disconnected"
	min_size = DialogConstants.MEDIUM

func setup(p_disconnected_player: int) -> void:
	disconnected_player = p_disconnected_player
	seconds_remaining = RECONNECT_GRACE_SECONDS
	_waiting_for_reconnect = true

	# Disable default OK button — we use custom buttons
	get_ok_button().visible = false

	# Prevent closing via X button or escape while waiting
	close_requested.connect(_on_close_attempted)

	_build_ui()
	_start_countdown()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 10)
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 30, 0)

	# Warning header
	var header = Label.new()
	header.text = "CONNECTION LOST"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color.ORANGE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	# Status message
	var status_label = Label.new()
	status_label.text = "Player %d has disconnected." % disconnected_player
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(status_label)

	# Countdown label
	countdown_label = Label.new()
	countdown_label.text = "Waiting for reconnection... %ds remaining" % int(seconds_remaining)
	countdown_label.add_theme_font_size_override("font_size", 13)
	countdown_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(countdown_label)

	main_container.add_child(HSeparator.new())

	# Options label
	var options_label = Label.new()
	options_label.text = "Choose an action:"
	options_label.add_theme_font_size_override("font_size", 13)
	options_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	options_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(options_label)

	# Buttons container
	var button_container = VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 8)

	# Save Game button
	var save_button = Button.new()
	save_button.text = "Save Game State"
	save_button.custom_minimum_size = Vector2(300, 36)
	save_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	save_button.tooltip_text = "Save the current game so you can resume later"
	save_button.pressed.connect(_on_save_pressed)
	button_container.add_child(save_button)

	# Continue Single-Player button
	var sp_button = Button.new()
	sp_button.text = "Continue in Single-Player"
	sp_button.custom_minimum_size = Vector2(300, 36)
	sp_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp_button.tooltip_text = "Switch the disconnected player to AI and keep playing"
	sp_button.pressed.connect(_on_continue_single_player_pressed)
	button_container.add_child(sp_button)

	# Claim Victory button
	var victory_button = Button.new()
	victory_button.text = "Claim Victory (Opponent Forfeit)"
	victory_button.custom_minimum_size = Vector2(300, 36)
	victory_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	victory_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	victory_button.tooltip_text = "End the game — you win by opponent disconnect"
	victory_button.pressed.connect(_on_claim_victory_pressed)
	button_container.add_child(victory_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _start_countdown() -> void:
	countdown_timer = Timer.new()
	countdown_timer.wait_time = 1.0
	countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(countdown_timer)
	countdown_timer.start()
	print("DisconnectDialog: Started %ds reconnection grace period" % int(RECONNECT_GRACE_SECONDS))

func _on_countdown_tick() -> void:
	seconds_remaining -= 1.0
	if countdown_label and is_instance_valid(countdown_label):
		if seconds_remaining > 0:
			countdown_label.text = "Waiting for reconnection... %ds remaining" % int(seconds_remaining)
			# Change color to red when low on time
			if seconds_remaining <= 10:
				countdown_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			elif seconds_remaining <= 20:
				countdown_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		else:
			countdown_label.text = "Reconnection window expired."
			countdown_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			_on_grace_period_expired()

func _on_grace_period_expired() -> void:
	"""Grace period ran out — auto-claim victory."""
	if not _waiting_for_reconnect:
		return
	_waiting_for_reconnect = false
	if countdown_timer:
		countdown_timer.stop()
	print("DisconnectDialog: Grace period expired — auto-claiming victory")
	claim_victory_requested.emit()
	hide()
	queue_free()

func on_peer_reconnected() -> void:
	"""Called by Main.gd if the peer reconnects during the grace period."""
	_waiting_for_reconnect = false
	if countdown_timer:
		countdown_timer.stop()
	print("DisconnectDialog: Peer reconnected — closing dialog")
	hide()
	queue_free()

func _on_save_pressed() -> void:
	print("DisconnectDialog: Save game requested")
	save_game_requested.emit()
	# Don't close dialog — let user take another action after saving

func _on_continue_single_player_pressed() -> void:
	_waiting_for_reconnect = false
	if countdown_timer:
		countdown_timer.stop()
	print("DisconnectDialog: Continue in single-player requested")
	continue_single_player_requested.emit()
	hide()
	queue_free()

func _on_claim_victory_pressed() -> void:
	_waiting_for_reconnect = false
	if countdown_timer:
		countdown_timer.stop()
	print("DisconnectDialog: Claim victory requested")
	claim_victory_requested.emit()
	hide()
	queue_free()

func _on_close_attempted() -> void:
	# Prevent closing via X button — user must pick an option
	print("DisconnectDialog: Close attempted — user must select an option")
