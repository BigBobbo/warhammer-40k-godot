extends AcceptDialog
class_name SecondaryMissionReviewDialog

# SecondaryMissionReviewDialog - Shows newly drawn secondary missions to the player
# and offers the option to spend 1 CP to replace one of them.
# The replaced mission goes back into the deck (not discard pile).

signal mission_replacement_requested(mission_id: String)
signal review_completed()

var _player: int = 0
var _drawn_missions: Array = []
var _player_cp: int = 0
var _deck_size: int = 0
var _can_replace: bool = false
var _replacement_used: bool = false
var _scroll_vbox: VBoxContainer = null
var _replace_info_label: Label = null

# Controller (pad) navigation state.
var _outer_scroll: ScrollContainer = null
var _done_button: Button = null
# Interactive controls in top-to-bottom order — the D-pad focus chain (each
# Replace button, then Continue). Rebuilt whenever the mission cards are.
var _replace_buttons: Array = []

# PadRouter checks this group and keeps its board-oriented handlers (bumper
# unit-cycling, panel-focus entry, the ItemList focus-release) off a dialog
# that drives itself with Godot's native ui_* focus navigation. Without it the
# D-pad never lands in this window and the player cannot review or replace a
# drawn mission with a controller.
const PAD_MODAL_GROUP := "pad_native_nav_modal"
# Hint chips shown while this dialog owns the pad (PadRouter stands down, so it
# no longer drives the hint bar and would otherwise leave the board hints up).
const PAD_HINTS := [["dpad", "Navigate"], ["a", "Select"], ["b", "Close"]]

func setup(player: int, drawn_missions: Array, player_cp: int, deck_size: int) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	_player = player
	_drawn_missions = drawn_missions
	_player_cp = player_cp
	_deck_size = deck_size
	_can_replace = player_cp >= 1 and deck_size > 0
	exclusive = true

	var faction_name = GameState.get_faction_name(player)
	title = "Secondary Missions Drawn - Player %d (%s)" % [player, faction_name]

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# Prevent closing via X button without completing
	close_requested.connect(_on_done_pressed)

	# Controller support: join the native-nav modal group so PadRouter stands
	# down, and (re)build the pad focus chain whenever we become visible or the
	# player picks up the pad while the dialog is open.
	add_to_group(PAD_MODAL_GROUP)
	if not visibility_changed.is_connected(_on_visibility_changed_pad):
		visibility_changed.connect(_on_visibility_changed_pad)
	if InputDeviceManager and not InputDeviceManager.device_changed.is_connected(_on_device_changed_pad):
		InputDeviceManager.device_changed.connect(_on_device_changed_pad)

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.LARGE

	# Outer scroll ensures all content (including Continue button) is reachable
	var outer_scroll = ScrollContainer.new()
	outer_scroll.name = "OuterScroll"
	outer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_outer_scroll = outer_scroll

	var main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 0)

	# Header
	var header = Label.new()
	header.text = "NEW SECONDARY MISSIONS"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.text = "Your secondary objectives for this turn"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if FactionPalettes.FONT_RAJDHANI_SEMIBOLD:
		subheader.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_SEMIBOLD)
	main_container.add_child(subheader)

	_add_dialog_gold_separator(main_container)

	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_vbox.add_theme_constant_override("separation", 8)
	main_container.add_child(_scroll_vbox)

	# Show each drawn mission
	_replace_buttons.clear()
	for i in range(_drawn_missions.size()):
		var mission = _drawn_missions[i]
		_add_mission_card(_scroll_vbox, mission, i)

	_add_dialog_gold_separator(main_container)

	# Replacement info
	_replace_info_label = Label.new()
	if _can_replace:
		_replace_info_label.text = "You may spend 1 CP to replace one mission (it returns to your deck).\nYou have %d CP | Deck: %d cards remaining" % [_player_cp, _deck_size]
		_replace_info_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	else:
		if _player_cp < 1:
			_replace_info_label.text = "Not enough CP to replace a mission (need 1 CP, have %d)" % _player_cp
		elif _deck_size == 0:
			_replace_info_label.text = "Deck is empty - cannot replace a mission"
		else:
			_replace_info_label.text = "Cannot replace missions at this time"
		_replace_info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_replace_info_label.add_theme_font_size_override("font_size", 11)
	_replace_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_replace_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(_replace_info_label)

	_add_dialog_gold_separator(main_container)

	# Done button
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonRow"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(button_container)

	var done_btn = Button.new()
	done_btn.name = "DoneButton"
	done_btn.text = "Continue"
	done_btn.custom_minimum_size = Vector2(160, 40)
	done_btn.pressed.connect(_on_done_pressed)
	WhiteDwarfTheme.apply_primary_button(done_btn)
	button_container.add_child(done_btn)
	_done_button = done_btn

	outer_scroll.add_child(main_container)
	add_child(outer_scroll)

func _add_mission_card(parent: VBoxContainer, mission: Dictionary, index: int) -> void:
	"""Add a single mission card display with optional replace button."""
	var card_container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	style.border_color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	card_container.add_theme_stylebox_override("panel", style)
	parent.add_child(card_container)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 4)
	card_container.add_child(card_vbox)

	# Mission name
	var name_label = Label.new()
	name_label.text = mission.get("name", "Unknown Mission")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		name_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	card_vbox.add_child(name_label)

	# Category
	var cat_label = Label.new()
	cat_label.text = mission.get("category", "")
	cat_label.add_theme_font_size_override("font_size", 11)
	cat_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	card_vbox.add_child(cat_label)

	# Mission instructions/details
	var mission_id = mission.get("id", "")
	var instructions = SecondaryMissionData.get_mission_instructions(mission_id)
	if instructions != "":
		var instructions_label = Label.new()
		instructions_label.text = instructions
		instructions_label.add_theme_font_size_override("font_size", 12)
		instructions_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		instructions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		instructions_label.custom_minimum_size = Vector2(0, 0)
		card_vbox.add_child(instructions_label)

	_add_dialog_gold_separator(card_vbox)

	# Scoring info with human-readable conditions
	var scoring = mission.get("scoring", {})
	var conditions = scoring.get("conditions", [])

	var scoring_header = Label.new()
	scoring_header.text = "SCORING:"
	scoring_header.add_theme_font_size_override("font_size", 11)
	scoring_header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes.FONT_RAJDHANI_BOLD:
		scoring_header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	card_vbox.add_child(scoring_header)

	for condition in conditions:
		var vp = condition.get("vp", 0)
		var check = condition.get("check", "")
		var params = condition.get("params", {})
		var readable_text = SecondaryMissionData.get_human_readable_condition(check, params, vp)
		var condition_label = Label.new()
		condition_label.text = "  %d VP - %s" % [vp, readable_text]
		condition_label.add_theme_font_size_override("font_size", 11)
		condition_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
		condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_vbox.add_child(condition_label)

	# Scoring timing
	var when_text = _get_timing_display(scoring.get("when", ""))
	var timing_label = Label.new()
	timing_label.text = "Scored: %s" % when_text
	timing_label.add_theme_font_size_override("font_size", 10)
	timing_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	card_vbox.add_child(timing_label)

	# Action requirement
	if mission.get("requires_action", false):
		var action_info = mission.get("action", {})
		var action_label = Label.new()
		action_label.text = "Requires Action: %s (during %s phase)" % [
			action_info.get("name", "Unknown"),
			action_info.get("phase", "unknown").capitalize()
		]
		action_label.add_theme_font_size_override("font_size", 10)
		action_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		card_vbox.add_child(action_label)

	# Pending interaction indicator
	if mission.get("pending_interaction", false):
		var pending_label = Label.new()
		pending_label.text = "AWAITING OPPONENT INTERACTION"
		pending_label.add_theme_font_size_override("font_size", 11)
		pending_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		card_vbox.add_child(pending_label)

	# Replace button
	if _can_replace:
		var replace_btn = Button.new()
		replace_btn.name = "ReplaceButton_%d" % index
		replace_btn.text = "Replace this mission (1 CP)"
		replace_btn.custom_minimum_size = Vector2(0, 30)
		replace_btn.add_theme_font_size_override("font_size", 12)
		replace_btn.tooltip_text = "Spend 1 CP to put this mission back in your deck and draw a different one"
		replace_btn.pressed.connect(_on_replace_pressed.bind(mission_id))
		WhiteDwarfTheme.apply_secondary_button(replace_btn)
		card_vbox.add_child(replace_btn)
		# Register in the top-to-bottom controller focus chain.
		_replace_buttons.append(replace_btn)

func _add_dialog_gold_separator(parent: Control) -> void:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)

func _get_timing_display(timing: String) -> String:
	match timing:
		"end_of_your_turn":
			return "End of your turn"
		"end_of_either_turn":
			return "End of either turn"
		"end_of_opponent_turn":
			return "End of opponent's turn"
		"while_active":
			return "While active"
		_:
			return timing

func _on_replace_pressed(mission_id: String) -> void:
	if _replacement_used:
		print("SecondaryMissionReviewDialog: Replacement already used this draw")
		return
	_replacement_used = true
	print("SecondaryMissionReviewDialog: Player %d wants to replace mission %s" % [_player, mission_id])
	emit_signal("mission_replacement_requested", mission_id)

func update_after_replacement(new_missions: Array) -> void:
	"""Rebuild the mission cards to show the updated missions after a replacement."""
	_drawn_missions = new_missions
	_can_replace = false

	# Clear existing mission cards
	for child in _scroll_vbox.get_children():
		child.queue_free()

	# Rebuild mission cards (no replace buttons since replacement was used).
	# The old Replace buttons are being freed, so drop their (now stale)
	# references from the focus chain before rebuilding.
	_replace_buttons.clear()
	for i in range(_drawn_missions.size()):
		var mission = _drawn_missions[i]
		_add_mission_card(_scroll_vbox, mission, i)

	# Update the replacement info text
	_replace_info_label.text = "Mission replaced! Review your new mission above."
	_replace_info_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))

	# Controller: only the Continue button remains interactive now — re-point the
	# focus chain at it so the pad isn't left focused on a freed Replace button.
	if InputDeviceManager and InputDeviceManager.is_pad_active():
		_setup_pad_focus.call_deferred()

func _on_done_pressed() -> void:
	print("SecondaryMissionReviewDialog: Player %d accepted drawn missions" % _player)
	emit_signal("review_completed")
	_restore_board_hints()
	hide()
	queue_free()

# ============================================================================
# CONTROLLER (PAD) NAVIGATION
# ============================================================================
# Reported bug: with a controller the D-pad never highlighted this window, so
# the player could neither read the drawn missions nor replace one. Root cause:
# initial focus landed on the Continue button (scrolled off-screen at the
# bottom) and Godot's geometric focus search — with the Replace buttons nested
# one-per-card — skipped the second Replace button and dead-ended. Fix: join the
# native-nav modal group (PadRouter stands down), wire an explicit top-to-bottom
# focus chain, seed focus on the first VISIBLE control, and keep the focused
# control scrolled into view.

func _on_visibility_changed_pad() -> void:
	if not visible or not _pad_active():
		return
	_apply_pad_hints()
	_setup_pad_focus.call_deferred()


func _on_device_changed_pad(mode: int) -> void:
	# The player picked up the pad while the dialog was already open (it may have
	# popped in mouse/keyboard mode). Set up native navigation now.
	if not is_instance_valid(self) or not visible:
		return
	if mode != InputDeviceManager.InputMode.PAD:
		return
	_apply_pad_hints()
	_setup_pad_focus.call_deferred()


func _setup_pad_focus() -> void:
	# Let the InputDeviceManager watchdog's initial confirm-button grab land
	# first, then move focus to the TOP of the dialog so the selector is visible
	# from the start. Two frames also clears any layout settling from popup().
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not visible or not _pad_active():
		return
	# Park the virtual cursor so A presses the focused button instead of firing a
	# synthetic left-click at the cursor position (VirtualCursor consumes A while
	# the cursor is live). The InputDeviceManager watchdog does the same when a
	# dialog pops while the pad is already active; do it here too so the pick-up-
	# the-pad-mid-dialog path is covered.
	if VirtualCursor and VirtualCursor.has_method("park"):
		VirtualCursor.park()
	_wire_pad_focus_neighbors()
	var first := _first_focus_target()
	if first != null and is_instance_valid(first):
		first.grab_focus()
		_scroll_to_focused(first)


# Build the wrap-around focus chain (each Replace button, then Continue) so
# D-pad ▲ ▼ steps through every interactive control deterministically instead of
# relying on Godot's geometric neighbour search.
func _wire_pad_focus_neighbors() -> void:
	var seq: Array = []
	for b in _replace_buttons:
		if is_instance_valid(b):
			seq.append(b)
	if is_instance_valid(_done_button):
		seq.append(_done_button)
	var n := seq.size()
	if n == 0:
		return
	for i in range(n):
		var ctrl: Control = seq[i]
		ctrl.focus_mode = Control.FOCUS_ALL
		var prev: Control = seq[(i - 1 + n) % n]
		var next: Control = seq[(i + 1) % n]
		ctrl.focus_neighbor_top = ctrl.get_path_to(prev)
		ctrl.focus_previous = ctrl.get_path_to(prev)
		ctrl.focus_neighbor_bottom = ctrl.get_path_to(next)
		ctrl.focus_next = ctrl.get_path_to(next)
		if not ctrl.focus_entered.is_connected(_scroll_to_focused.bind(ctrl)):
			ctrl.focus_entered.connect(_scroll_to_focused.bind(ctrl))


func _first_focus_target() -> Control:
	for b in _replace_buttons:
		if is_instance_valid(b):
			return b
	return _done_button if is_instance_valid(_done_button) else null


func _scroll_to_focused(ctrl: Control) -> void:
	# Keep the focused control on-screen so the controller "selector" is always
	# visible — the dialog content is taller than the scroll region.
	if is_instance_valid(_outer_scroll) and is_instance_valid(ctrl):
		_outer_scroll.ensure_control_visible(ctrl)


func _apply_pad_hints() -> void:
	if PadHintBar and PadHintBar.has_method("set_hints"):
		PadHintBar.set_hints(PAD_HINTS)


func _restore_board_hints() -> void:
	# Hand the hint bar back to PadRouter so it recomputes the board context
	# (we overrode it with navigate/select chips while the dialog owned the pad).
	if _pad_active() and PadRouter and PadRouter.has_method("refresh_hints"):
		PadRouter.refresh_hints()


func _pad_active() -> bool:
	return InputDeviceManager != null and InputDeviceManager.is_pad_active()
