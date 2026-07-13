extends Node

# M2 pad router (PRPs/steam_deck_controller_support.md §4.1/§5.1, milestone
# M2): the native-controls layer on top of the M1 virtual cursor.
#
#   LB/RB  — cycle the "current list": eligible shooters / eligible targets
#            (shooting, reusing the shipped shoot_* semantics) or the
#            right-panel unit list (other phases; same entry point a mouse
#            row-click uses)
#   A      — in TARGET_SELECT: assign the highlighted target to the current
#            weapon (cursor mode and focused controls keep their own A)
#   B      — release panel focus back to the board; with an active shooter,
#            deselect (the shoot_cancel_target semantic)
#   X      — context action: skip the active shooter (shoot_skip_unit).
#            Only when the virtual cursor is parked — cursor mode owns X as
#            right-click (VirtualCursor consumes it first)
#   Y      — toggle the datasheet of the highlighted target / selected unit
#   D-pad  — with nothing focused: enter panel focus (right panel, then
#            bottom bar); with focus: normal ui_* navigation (not consumed)
#
# Input-order note: _input runs in REVERSE tree order, so the order is
# Main (scene) -> VirtualCursor -> PadRouter -> PadHintBar -> IDM. Main only
# consumes pad_phase_action; VirtualCursor consumes A/X while the cursor is
# active. Everything here acts on what falls through.

const HINTS_BOARD := [
	["ls", "Cursor"],
	["rb", "Cycle Units"],
	["a", "Select / Click"],
	["y", "Datasheet"],
	["dpad", "Focus Panels"],
	["menu", "End Phase"],
]
const HINTS_TARGETS := [
	["rb", "Cycle Targets"],
	["a", "Assign Target"],
	["x", "Skip Unit"],
	["y", "Datasheet"],
	["menu", "Confirm Targets"],
	["b", "Deselect"],
]
const HINTS_FOCUS := [
	["dpad", "Navigate"],
	["a", "Press"],
	["b", "Back To Board"],
]
const HINTS_CARRY := [
	["ls", "Move Model"],
	["a", "Drop"],
	["lb", "Rotate ⟲"],
	["rb", "Rotate ⟳"],
	["b", "Cancel"],
	["menu", "Confirm / End"],
]

# The target currently highlighted by LB/RB in shooting TARGET_SELECT mode
# (empty when none). Windowed scenarios assert this.
var target_highlight_id: String = ""

# M3 model-carry state: the model currently "picked up" rides the virtual
# cursor (warp + held synthetic LMB — the real drag code runs underneath).
# carry_model_index is which of the selected unit's alive models D-pad ◀ ▶
# hops to. Windowed scenarios assert both.
var carry_active: bool = false
var carry_model_index: int = 0
var _carry_pickup_screen := Vector2.ZERO
var _carry_unit_id: String = ""  # resets carry_model_index when the unit changes


func is_carrying() -> bool:
	return carry_active


func _ready() -> void:
	InputDeviceManager.device_changed.connect(func(_m): _update_hints())


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	# A joypad event IS pad input — claim inline so the session's very first
	# press acts instead of being dropped (the _process poll runs after us).
	InputDeviceManager.claim_pad()
	match event.button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			if carry_active:
				_synth_rotate(true)
			else:
				_cycle(-1)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_RIGHT_SHOULDER:
			if carry_active:
				_synth_rotate(false)
			else:
				_cycle(1)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_Y:
			if _toggle_datasheet():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_X:
			if _context_action():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_A:
			if _handle_a():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if _handle_back():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			if _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_LEFT:
			if _hop_model(-1) or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_RIGHT:
			if _hop_model(1) or _enter_panel_focus():
				get_viewport().set_input_as_handled()
	_update_hints()


func _handle_a() -> bool:
	if carry_active:
		_drop_carry()
		return true
	if _assign_highlighted_target():
		return true
	return _try_begin_carry()


# ============================================================================
# Cycling
# ============================================================================

func _cycle(dir: int) -> void:
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null:
		# With an armed shooter that HAS targets, LB/RB walks the target ring.
		# A shooter with nothing to shoot at is a dead end — fall through to
		# cycling shooters so the bumpers always advance the activation.
		if str(sc.active_shooter_id) == "" or sc.eligible_targets.is_empty():
			sc._keyboard_cycle_units(dir < 0)  # reuses the Tab / Shift+Tab path
			target_highlight_id = ""
			if str(sc.active_shooter_id) != "":
				_center_camera_on_unit(str(sc.active_shooter_id))
		else:
			_cycle_target(sc, dir)
		return
	_cycle_unit_list(dir)


func _cycle_target(sc: Node, dir: int) -> void:
	var ring: Array = sc.eligible_targets.keys()
	ring.sort()
	if ring.is_empty():
		target_highlight_id = ""
		return
	# Entering TARGET_SELECT claims the pad: release any panel focus (the
	# shooter-cycling path focuses the unit list) so A means "assign", not
	# "press the focused control".
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	var idx := ring.find(target_highlight_id)
	idx = wrapi(idx + dir, 0, ring.size()) if idx != -1 else (0 if dir > 0 else ring.size() - 1)
	target_highlight_id = str(ring[idx])
	_center_camera_on_unit(target_highlight_id)


func _cycle_unit_list(dir: int) -> void:
	# Generic phases: step whichever unit list is live in the right panel.
	# Several phases build their own ItemList procedurally (the static
	# UnitListPanel is hidden then), so find the first visible populated one
	# and drive its item_selected signal — exactly what a mouse row-click
	# emits, so whoever owns the list reacts identically.
	var m := get_tree().current_scene
	if m == null:
		return
	var panel := m.get_node_or_null("HUD_Right")
	if panel == null:
		return
	var list := _find_visible_item_list(panel)
	if list == null:
		return
	var cur := -1
	var selected := list.get_selected_items()
	if selected.size() > 0:
		cur = selected[0]
	# Skip disabled/header rows.
	var next := cur
	for _i in range(list.item_count):
		next = wrapi(next + dir, 0, list.item_count)
		if list.is_item_selectable(next) and not list.is_item_disabled(next):
			break
	if next == cur or next < 0 or not list.is_item_selectable(next):
		return
	list.select(next)
	list.ensure_current_is_visible()
	list.item_selected.emit(next)


func _find_visible_item_list(root: Node) -> ItemList:
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is ItemList and n.is_visible_in_tree() and n.item_count > 0:
			return n
		for child in n.get_children(true):
			queue.append(child)
	return null


# ============================================================================
# Target assignment / context actions / back
# ============================================================================

func _assign_highlighted_target() -> bool:
	if VirtualCursor.is_cursor_active():
		return false
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var sc = _shooting_controller_in_shooting_phase()
	if sc == null or str(sc.active_shooter_id) == "" or target_highlight_id == "":
		return false
	if not sc.eligible_targets.has(target_highlight_id):
		return false
	# The controller auto-selects a shooter on phase entry WITHOUT dispatching
	# SELECT_SHOOTER, so the phase may not have an active shooter yet and
	# would reject the ASSIGN_TARGET. Sync it first (routed + validated
	# synchronously, same as a list click).
	var phase = PhaseManager.get_current_phase_instance()
	if phase != null and "active_shooter_id" in phase \
			and str(phase.active_shooter_id) != str(sc.active_shooter_id):
		sc.emit_signal("shoot_action_requested", {
			"type": "SELECT_SHOOTER",
			"actor_unit_id": str(sc.active_shooter_id)
		})
	# The click path requires a selected weapon row; select the first one if
	# the player hasn't focused any (same default the mouse flow nudges you to).
	if sc.weapon_tree != null and sc.weapon_tree.get_selected() == null:
		var root: TreeItem = sc.weapon_tree.get_root()
		if root != null and root.get_first_child() != null:
			root.get_first_child().select(0)
	sc._select_target_for_current_weapon(target_highlight_id)
	return true


func _context_action() -> bool:
	if VirtualCursor.is_cursor_active() and not carry_active:
		return false  # cursor mode owns X (right-click); VC consumed it anyway
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null and str(sc.active_shooter_id) != "":
		sc._keyboard_skip_unit()
		target_highlight_id = ""
		return true
	# Movement: X = undo last staged model (plan §4.2 context action).
	var m := get_tree().current_scene
	if m != null and ("current_phase" in m) and m.current_phase == GameStateData.Phase.MOVEMENT \
			and not carry_active and m.movement_controller != null and is_instance_valid(m.movement_controller) \
			and str(m.movement_controller.active_unit_id) != "" \
			and m.movement_controller.has_method("_on_undo_model_pressed"):
		m.movement_controller._on_undo_model_pressed()
		return true
	return false


func _handle_back() -> bool:
	if carry_active:
		_cancel_carry()
		return true
	# One B returns fully to the board: release panel focus AND park the
	# cursor together — leaving either behind makes the next A ambiguous
	# (click vs press-focused vs pickup).
	var did_reset := false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
		did_reset = true
	if VirtualCursor.is_cursor_active():
		VirtualCursor.park()
		did_reset = true
	if did_reset:
		return true
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null and str(sc.active_shooter_id) != "":
		sc._keyboard_deselect_shooter()
		target_highlight_id = ""
		return true
	return false


# ============================================================================
# M3 model carry — pickup/drop/cancel/hop/rotate
# ============================================================================

func _try_begin_carry() -> bool:
	if VirtualCursor.is_cursor_active():
		return false  # cursor mode: A is a click (VirtualCursor consumed it)
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return false
	match m.current_phase:
		GameStateData.Phase.MOVEMENT, GameStateData.Phase.CHARGE:
			var ctrl = m.movement_controller if m.current_phase == GameStateData.Phase.MOVEMENT else m.charge_controller
			if ctrl == null or not is_instance_valid(ctrl) or str(ctrl.active_unit_id) == "":
				return false
			var unit_id := str(ctrl.active_unit_id)
			if unit_id != _carry_unit_id:
				_carry_unit_id = unit_id
				carry_model_index = 0
			var pos = _model_world_pos(unit_id, carry_model_index)
			if pos == null:
				carry_model_index = 0
				pos = _model_world_pos(unit_id, 0)
			if pos == null:
				return false
			# Center first, THEN project — the warp target must use the final
			# camera transform.
			_center_camera_on_world(pos)
			var screen: Vector2 = m.world_to_screen_position(pos)
			VirtualCursor.warp_to(screen)
			VirtualCursor.set_left_button(true)
			_carry_pickup_screen = screen
			carry_active = true
			return true
		GameStateData.Phase.DEPLOYMENT:
			# Placement is click-driven with a cursor-following ghost, so
			# "pickup" is just parking the cursor over the deployment zone;
			# every A after that is a normal cursor click that places a model.
			var dc = m.deployment_controller
			if dc == null or not is_instance_valid(dc) or not dc.is_placing():
				return false
			var center := _deployment_zone_center()
			if center == Vector2.INF:
				return false
			_center_camera_on_world(center)
			VirtualCursor.warp_to(m.world_to_screen_position(center))
			return true
	return false


func _drop_carry() -> void:
	VirtualCursor.set_left_button(false)
	carry_active = false


func _cancel_carry() -> void:
	# The mouse-parity cancel: put the model back where it was picked up and
	# release (there is no dedicated drag-cancel in the mouse flow either).
	VirtualCursor.warp_to(_carry_pickup_screen)
	VirtualCursor.set_left_button(false)
	carry_active = false


func _hop_model(dir: int) -> bool:
	if carry_active:
		return false
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return false
	if m.current_phase != GameStateData.Phase.MOVEMENT and m.current_phase != GameStateData.Phase.CHARGE:
		return false
	var ctrl = m.movement_controller if m.current_phase == GameStateData.Phase.MOVEMENT else m.charge_controller
	if ctrl == null or not is_instance_valid(ctrl) or str(ctrl.active_unit_id) == "":
		return false
	if str(ctrl.active_unit_id) != _carry_unit_id:
		_carry_unit_id = str(ctrl.active_unit_id)
		carry_model_index = 0
	var unit = GameState.get_unit(str(ctrl.active_unit_id))
	var alive := 0
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive += 1
	if alive == 0:
		return false
	carry_model_index = wrapi(carry_model_index + dir, 0, alive)
	var pos = _model_world_pos(str(ctrl.active_unit_id), carry_model_index)
	if pos != null:
		_center_camera_on_world(pos)
	return true


# Returns the world-space position (Vector2) of the unit's Nth alive model,
# or null when out of range.
func _model_world_pos(unit_id: String, alive_index: int):
	var unit = GameState.get_unit(unit_id)
	var idx := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		if idx == alive_index:
			var pos = model.get("position", null)
			if pos is Dictionary and pos.has("x"):
				return Vector2(float(pos.x), float(pos.y))
			elif pos is Vector2:
				return pos
			return null
		idx += 1
	return null


func _deployment_zone_center() -> Vector2:
	var player := GameState.get_active_player() if GameState.has_method("get_active_player") else int(GameState.state.get("meta", {}).get("active_player", 1))
	# PackedVector2Array — don't type-gate on Array, just iterate.
	var zone = BoardState.get_deployment_zone_for_player(player)
	if zone == null or zone.size() == 0:
		return Vector2.INF
	var center := Vector2.ZERO
	for point in zone:
		center += point
	return center / zone.size()


# Pad rotation reuses the rebindable rotate_left/rotate_right keyboard
# semantics: synthesize the currently-bound key event so MovementController /
# DeploymentController / ChargeController react exactly as they do to Q/E,
# including rebinds. The synthetic window stops the device tracker reading
# our own key events as "keyboard used".
func _synth_rotate(left: bool) -> void:
	var binding = KeybindingManager.get_binding("rotate_left" if left else "rotate_right")
	if binding.is_empty() or int(binding.get("key", 0)) == 0:
		return
	InputDeviceManager.note_synthetic_mouse()
	var press := InputEventKey.new()
	press.keycode = binding.key as Key
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = binding.key as Key
	release.pressed = false
	Input.parse_input_event(release)


# ============================================================================
# Panel focus entry (D-pad from board context)
# ============================================================================

func _enter_panel_focus() -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false  # already navigating — let ui_* handle the press
	var m := get_tree().current_scene
	if m == null:
		return false
	for root_path in ["HUD_Right", "HUD_Bottom"]:
		var root := m.get_node_or_null(root_path)
		if root == null:
			continue
		var c := _find_first_focusable(root)
		if c != null:
			c.grab_focus()
			return true
	return false


func _find_first_focusable(root: Node) -> Control:
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Control and n.focus_mode == Control.FOCUS_ALL and n.is_visible_in_tree() \
				and not (n is BaseButton and n.disabled):
			return n
		for child in n.get_children(true):
			queue.append(child)
	return null


# ============================================================================
# Datasheet / camera / helpers
# ============================================================================

func _toggle_datasheet() -> bool:
	var m := get_tree().current_scene
	if m == null:
		return false
	var ds := m.get_node_or_null("DatasheetModal")
	if ds == null:
		return false
	if ds.visible:
		ds.close()
		return true
	var uid := target_highlight_id
	if uid == "" and m.has_method("_selected_unit_id_or_empty"):
		uid = str(m._selected_unit_id_or_empty())
	if uid == "":
		return false
	ds.open_for(uid)
	return true


func _center_camera_on_unit(unit_id: String) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var pos = model.get("position", null)
		if pos is Dictionary and pos.has("x"):
			_center_camera_on_world(Vector2(float(pos.x), float(pos.y)))
			return
		elif pos is Vector2:
			_center_camera_on_world(pos)
			return


func _center_camera_on_world(world_pos: Vector2) -> void:
	# Same duck-typed camera model as VirtualCursor._edge_pan. Exact when the
	# board isn't rotated; with view_rotation it lands near enough to see the
	# unit (rotation-aware framing is an M5 polish item).
	var m := get_tree().current_scene
	if m == null or not ("view_offset" in m) or not m.has_method("update_view_transform"):
		return
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var zoom: float = m.view_zoom if "view_zoom" in m else 1.0
	m.view_offset = world_pos - vp / (2.0 * zoom)
	m.update_view_transform()


func _shooting_controller_in_shooting_phase() -> Node:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or not ("shooting_controller" in m):
		return null
	if m.current_phase != GameStateData.Phase.SHOOTING:
		return null
	var sc = m.shooting_controller
	if sc == null or not is_instance_valid(sc):
		return null
	return sc


func _update_hints() -> void:
	var hints := HINTS_BOARD
	if carry_active:
		hints = HINTS_CARRY
	elif get_viewport().gui_get_focus_owner() != null:
		hints = HINTS_FOCUS
	else:
		var sc = _shooting_controller_in_shooting_phase()
		if sc != null and str(sc.active_shooter_id) != "":
			hints = HINTS_TARGETS
	PadHintBar.set_hints(hints)
