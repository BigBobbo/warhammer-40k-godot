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

# The target currently highlighted by LB/RB in shooting TARGET_SELECT mode
# (empty when none). Windowed scenarios assert this.
var target_highlight_id: String = ""


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
			_cycle(-1)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_RIGHT_SHOULDER:
			_cycle(1)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_Y:
			if _toggle_datasheet():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_X:
			if _context_action():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_A:
			if _assign_highlighted_target():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if _handle_back():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if _enter_panel_focus():
				get_viewport().set_input_as_handled()
	_update_hints()


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
		for child in n.get_children():
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
	if VirtualCursor.is_cursor_active():
		return false  # cursor mode owns X (right-click); VC consumed it anyway
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null and str(sc.active_shooter_id) != "":
		sc._keyboard_skip_unit()
		target_highlight_id = ""
		return true
	return false


func _handle_back() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
		return true
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null and str(sc.active_shooter_id) != "":
		sc._keyboard_deselect_shooter()
		target_highlight_id = ""
		return true
	return false


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
		for child in n.get_children():
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
	if get_viewport().gui_get_focus_owner() != null:
		hints = HINTS_FOCUS
	else:
		var sc = _shooting_controller_in_shooting_phase()
		if sc != null and str(sc.active_shooter_id) != "":
			hints = HINTS_TARGETS
	PadHintBar.set_hints(hints)
