extends Node

# HandoffManager — play-and-pass ("hotseat") device-handoff ceremony.
#
# The engine already routes every action to the correct seat; what local
# Human-vs-Human games lacked was the moment where the device changes hands.
# This autoload owns a full-screen, input-blocking handoff screen shown at
# the seams where the OTHER human should take the controls:
#
#   1. Each player-turn start (PhaseManager.turn_started — COMMAND entry).
#   2. The Formations secret-declaration swap (Main.gd routes the P2 dialog
#      through request_handoff so P1's picks are hidden first).
#   3. Deployment phase entry (announces who deploys first; the per-unit
#      deployment alternation stays promptless — placement is open info).
#
# It NEVER appears when: a network game is active, either seat is AI, the
# scenario/test harness is driving (unless a test opts in via
# force_enabled_for_test), or the player disabled it in Settings > Gameplay.
#
# Reactive windows (saves, overwatch, heroic intervention, fight-phase
# alternation) deliberately do NOT get a full handoff screen — they are
# 5-second decisions already covered by the MA-42 blocking overlay.

signal handoff_acknowledged(player: int)

const GameStateData = preload("res://autoloads/GameState.gd")

const SCREEN_LAYER := 120  # above dialogs (Window exclusive excepted) and HUD

var _layer: CanvasLayer = null
var _ready_button: Button = null
var _title_label: Label = null
var _seat_label: Label = null
var _context_label: Label = null
var _pending_callback: Callable = Callable()
var _pending_player: int = 0
var _visible: bool = false
var _scenario_mode: bool = false

# Popup Windows (secondary-mission draws, stratagem prompts, …) render above
# every CanvasLayer, so they would leak the incoming player's information
# straight through the privacy screen. While the screen is up we hide any
# visible popup Window and restore it on acknowledge; a short poll catches
# dialogs that open AFTER the screen (Command-phase draws are deferred).
var _suppressed_windows: Array = []
var _suppress_timer: Timer = null

# Windowed scenario tests opt in explicitly; everything else under the
# harness must never see a blocking modal (459 pre-existing scenarios).
var force_enabled_for_test: bool = false

func _ready() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) == TYPE_STRING and (a.begins_with("--scenario-file=") or a.begins_with("--ai-benchmark")):
			_scenario_mode = true
			break
	# PhaseManager is an earlier autoload, safe to reach here.
	PhaseManager.turn_started.connect(_on_turn_started)
	PhaseManager.phase_changed.connect(_on_phase_changed)

func is_local_hotseat() -> bool:
	# A game where two humans share one device: not networked, no AI seat.
	if NetworkManager.is_networked():
		return false
	if AIPlayer.is_ai_player(1) or AIPlayer.is_ai_player(2):
		return false
	# Only meaningful once a game is actually running (Main scene up).
	return GameState.state.get("units", {}).size() > 0

func handoff_enabled() -> bool:
	if _scenario_mode and not force_enabled_for_test:
		return false
	if not SettingsService.get_hotseat_handoff_enabled():
		return false
	return is_local_hotseat()

# Show the handoff screen for `player`, then run `on_ready` once they
# acknowledge. When the ceremony is disabled the callback runs immediately,
# so call sites never need their own gating.
func request_handoff(player: int, context: String = "", on_ready: Callable = Callable()) -> void:
	if not handoff_enabled():
		if on_ready.is_valid():
			on_ready.call()
		return
	_pending_callback = on_ready
	_pending_player = player
	_show_screen(player, context)

func _on_turn_started(player: int) -> void:
	# A player turn begins with its Command phase (07.02).
	request_handoff(player, "Battle Round %d — Command Phase" % GameState.get_battle_round())

func _on_phase_changed(new_phase) -> void:
	if new_phase == GameStateData.Phase.DEPLOYMENT:
		request_handoff(GameState.get_active_player(), "Deployment — you set up first")

# ---------------------------------------------------------------- UI ----

func _show_screen(player: int, context: String) -> void:
	if _layer == null:
		_build_screen()
	var faction_name := _faction_label(player)
	_title_label.text = "PASS THE DEVICE"
	var seat := GameState.get_player_display_name(player)
	if seat == "Player %d" % player:
		_seat_label.text = "Player %d — %s" % [player, faction_name]
	else:
		_seat_label.text = "%s (Player %d) — %s" % [seat, player, faction_name]
	_seat_label.add_theme_color_override("font_color",
		UIConstants.FRIENDLY_PLAYER_TEAL if player == 1 else UIConstants.ENEMY_PLAYER_MAGENTA)
	_context_label.text = context
	_layer.visible = true
	_visible = true
	get_viewport().gui_release_focus()
	_ready_button.grab_focus()
	_suppress_popup_windows()
	_suppress_timer.start()
	DebugLogger.info("HandoffManager: handoff screen shown", {"player": player, "context": context})

func _on_ready_pressed() -> void:
	if not _visible:
		return
	_visible = false
	_layer.visible = false
	_suppress_timer.stop()
	_restore_popup_windows()
	var cb := _pending_callback
	var player := _pending_player
	_pending_callback = Callable()
	_pending_player = 0
	DebugLogger.info("HandoffManager: handoff acknowledged", {"player": player})
	emit_signal("handoff_acknowledged", player)
	if cb.is_valid():
		cb.call()

func _suppress_popup_windows() -> void:
	# Descendant Windows of the root window are popups/dialogs; the root
	# (main) window itself is never in find_children results.
	for w in get_tree().root.find_children("*", "Window", true, false):
		if w.visible and not _suppressed_windows.has(w):
			w.hide()
			_suppressed_windows.append(w)

func _restore_popup_windows() -> void:
	for w in _suppressed_windows:
		if is_instance_valid(w):
			w.show()
	_suppressed_windows.clear()

func _build_screen() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "HandoffScreen"
	_layer.layer = SCREEN_LAYER
	_layer.visible = false
	add_child(_layer)

	_suppress_timer = Timer.new()
	_suppress_timer.wait_time = 0.15
	_suppress_timer.one_shot = false
	_suppress_timer.timeout.connect(_suppress_popup_windows)
	add_child(_suppress_timer)

	var blocker := ColorRect.new()
	blocker.name = "HandoffBlocker"
	blocker.color = Color(0.05, 0.045, 0.04, 1.0)  # opaque: privacy screen
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	# Pad support: PadRouter stands down while a native-nav modal is open.
	blocker.add_to_group("pad_native_nav_modal")
	_layer.add_child(blocker)

	var center := CenterContainer.new()
	center.name = "HandoffCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.add_child(center)

	var box := VBoxContainer.new()
	box.name = "HandoffBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.45))
	box.add_child(_title_label)

	_seat_label = Label.new()
	_seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_label.add_theme_font_size_override("font_size", 34)
	box.add_child(_seat_label)

	_context_label = Label.new()
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_label.add_theme_font_size_override("font_size", 22)
	_context_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	box.add_child(_context_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	_ready_button = Button.new()
	_ready_button.name = "HandoffReadyButton"
	_ready_button.text = "[Enter]  I'm ready — take the controls"
	_ready_button.custom_minimum_size = Vector2(420, 64)
	_ready_button.add_theme_font_size_override("font_size", 24)
	_ready_button.pressed.connect(_on_ready_pressed)
	var btn_wrap := CenterContainer.new()
	btn_wrap.name = "HandoffBtnWrap"
	btn_wrap.add_child(_ready_button)
	box.add_child(btn_wrap)

	var hint := Label.new()
	hint.text = "The board is hidden while the device changes hands."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	box.add_child(hint)

func _faction_label(player: int) -> String:
	return GameState.get_faction_name(player)

func _unhandled_input(event: InputEvent) -> void:
	if not _visible:
		return
	# Swallow everything while the privacy screen is up; Enter / pad-accept
	# confirms (the focused button also handles this natively).
	if event.is_action_pressed("ui_accept"):
		_on_ready_pressed()
	get_viewport().set_input_as_handled()
