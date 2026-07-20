extends Node

# M2 pad router (PRPs/steam_deck_controller_support.md §4.1/§5.1, milestone
# M2): the native-controls layer on top of the M1 virtual cursor.
#
#   LB/RB  — THE unit-cycling control, and the only one (BUMPER-ONLY rule):
#            cycle the "current list": eligible shooters / eligible targets
#            (shooting, reusing the shipped shoot_* semantics) or the
#            right-panel unit list (other phases; same entry point a mouse
#            row-click uses). Deployment: cycling switches which unit is being
#            deployed, but locks once any model of the current unit is placed
#            (undo them all to unlock — mirrors the mouse rule). Works while
#            the action bar is open too — the menu follows the new unit.
#   D-pad ◀ ▶ — placement (deployment / reinforcement / scout reserves):
#            cycle the value of the highlighted selector row — model type
#            (multi-profile units) or formation (Single / Spread / Tight);
#            otherwise panel focus entry
#   D-pad ▲ ▼ — the SELECTED unit's phase sub-menu, never the unit list:
#            placement with a model-type picker: move the ▶ highlight
#            between the Select Model Type and Deploy Formation rows.
#            Charge: step the ELIGIBLE TARGETS rows (A toggles the stepped
#            row in/out of the declaration — pad Click / Ctrl+Click).
#            Shooting with an armed shooter: step the weapon rows so each
#            gun can get its own target. Movement with an open move-mode
#            decision: open the action bar (Move / Advance / Fall Back /
#            Stay Still) and step its options. Otherwise panel focus entry —
#            which lands on buttons only: unit lists are demoted to
#            FOCUS_CLICK while the pad is active (see
#            _apply_list_focus_policy) so neither the D-pad nor the left
#            stick's ui_up/ui_down can ever walk the unit list. Cycling
#            units is the bumpers' job alone.
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
	["view", "Pause Menu"],
]
const HINTS_TARGETS := [
	["rb", "Cycle Targets"],
	["dpad", "Weapon ▲ ▼"],
	["a", "Assign Target"],
	["x", "Skip Unit"],
	["y", "Datasheet"],
	["menu", "Confirm Targets"],
	["b", "Deselect"],
]
const HINTS_CHARGE := [
	["rb", "Cycle Units"],
	["dpad", "Target ▲ ▼"],
	["a", "Toggle Target"],
	["menu", "Declare / Roll"],
	["x", "Skip Charge"],
	["y", "Datasheet"],
]
const HINTS_DEPLOY := [
	["ls", "Cursor"],
	["lb", "Prev Unit"],
	["rb", "Next Unit"],
	["a", "Place Model"],
	["dpad", "Type / Formation"],
	["x", "Undo Model"],
	["y", "Datasheet"],
	["menu", "Confirm / End"],
]
const HINTS_FOCUS := [
	["dpad", "Navigate"],
	["a", "Press"],
	["b", "Back To Board"],
]
const HINTS_CARRY := [
	["ls", "Move Model"],
	["rs", "Precision"],
	["a", "Drop"],
	["lb", "Rotate ⟲"],
	["rb", "Rotate ⟳"],
	["b", "Cancel"],
	["menu", "Confirm / End"],
]
const HINTS_MENU := [
	["dpad", "Choose Action"],
	["rb", "Cycle Units"],
	["a", "Confirm"],
	["b", "Cancel"],
]
# Movement with a selected unit whose move-mode decision is still open: ▲ ▼
# opens the same action bar A does, so the D-pad browses the unit's phase
# options instead of the unit list.
const HINTS_MOVE := [
	["ls", "Cursor"],
	["rb", "Cycle Units"],
	["dpad", "Move Menu"],
	["a", "Menu / Pick Up"],
	["x", "Undo Model"],
	["y", "Datasheet"],
	["menu", "End Phase"],
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
	InputDeviceManager.device_changed.connect(_on_device_changed)


func _on_device_changed(mode: int) -> void:
	# BUMPER-ONLY rule: while the pad drives, unit lists leave the focus
	# chain (and give up any focus they already hold); on KBM they restore.
	_apply_list_focus_policy(mode == InputDeviceManager.InputMode.PAD)
	_update_hints()


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	# A joypad event IS pad input — claim inline so the session's very first
	# press acts instead of being dropped (the _process poll runs after us).
	InputDeviceManager.claim_pad()
	# Re-assert the bumper-only rule before routing: lists spawned since the
	# last press get demoted, and any list that grabbed focus lets go.
	_apply_list_focus_policy(true)
	# While the action bar is open it owns the pad exclusively (a lightweight
	# modal): D-pad moves the highlight, A confirms, B cancels, and everything
	# else is swallowed so Start can't end the phase mid-decision. The bumpers
	# keep their one global meaning — switch units — and the menu follows.
	if PadActionBar.is_open():
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP:
				PadActionBar.move_highlight(-1)
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN:
				PadActionBar.move_highlight(1)
			JOY_BUTTON_LEFT_SHOULDER:
				_menu_cycle_unit(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				_menu_cycle_unit(1)
			JOY_BUTTON_A:
				_apply_menu_choice(PadActionBar.activate())
			JOY_BUTTON_B:
				PadActionBar.close()
		get_viewport().set_input_as_handled()
		_update_hints()
		return
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
		JOY_BUTTON_DPAD_UP:
			if _pad_deploy_row_cycle(-1) or _pad_step_secondary(-1) or _try_open_move_menu() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_DOWN:
			if _pad_deploy_row_cycle(1) or _pad_step_secondary(1) or _try_open_move_menu() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_LEFT:
			if _hop_model(-1) or _pad_deploy_option_cycle(-1) or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_RIGHT:
			if _hop_model(1) or _pad_deploy_option_cycle(1) or _enter_panel_focus():
				get_viewport().set_input_as_handled()
	# A handler above may have re-focused a list (e.g. a phase's selection
	# refresh); take it back so a following stick deflection can't walk it.
	var f := get_viewport().gui_get_focus_owner()
	if f is ItemList:
		f.release_focus()
	_update_hints()


func _handle_a() -> bool:
	if carry_active:
		_drop_carry()
		return true
	if _assign_highlighted_target():
		return true
	if _pad_charge_toggle():
		return true
	if _try_open_move_menu():
		return true
	return _try_begin_carry()


# ============================================================================
# M4 move-mode action menu (PadActionBar)
# ============================================================================

func _try_open_move_menu() -> bool:
	if VirtualCursor.is_cursor_active():
		return false  # cursor mode: A is a click (VirtualCursor consumed it)
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return false
	if m.current_phase != GameStateData.Phase.MOVEMENT:
		return false
	var mc = m.movement_controller if ("movement_controller" in m) else null
	if mc == null or not is_instance_valid(mc) or not mc.has_method("pad_menu_options"):
		return false
	var opts: Array = mc.pad_menu_options()
	if opts.is_empty():
		return false
	var unit = GameState.get_unit(str(mc.active_unit_id))
	var title := str(unit.get("meta", {}).get("name", mc.active_unit_id))
	PadActionBar.open(title, opts)
	return true


func _apply_menu_choice(choice_id: String) -> void:
	if choice_id == "":
		return
	var m := get_tree().current_scene
	if m == null:
		return
	var mc = m.movement_controller if ("movement_controller" in m) else null
	if mc == null or not is_instance_valid(mc) or not mc.has_method("pad_apply_menu_choice"):
		return
	mc.pad_apply_menu_choice(choice_id)
	# Choices that start moving models flow straight into the carry so the
	# next thing on the stick is the model itself. Advance waits (its dice
	# dialog owns the next press) and Stay Still is already done — for both,
	# _try_begin_carry's focus/validity guards make the deferred call a no-op
	# anyway, so gating here is just intent.
	if choice_id == "NORMAL" or choice_id == "FALL_BACK":
		call_deferred("_auto_carry_after_menu")


func _auto_carry_after_menu() -> void:
	if not carry_active and _try_begin_carry():
		_update_hints()


# Bumper press while the action bar is open: the bumpers still mean "switch
# unit" (their one global meaning), so close the menu, cycle, and reopen it
# for the new unit — the sub-menu follows the selection. The reopen is
# deferred so the list-selection handlers (radio updates etc.) settle first.
func _menu_cycle_unit(dir: int) -> void:
	PadActionBar.close()
	_cycle(dir)
	call_deferred("_reopen_move_menu")


func _reopen_move_menu() -> void:
	if carry_active or PadActionBar.is_open():
		return
	if _try_open_move_menu():
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
	# Deployment: once any model of the current unit is on the table the unit
	# is committed — LB/RB can't switch away until every model is undone
	# (mirrors the mouse rule in Main._deploy_try_switch_unit).
	var dc = _deployment_controller_placing()
	if dc != null and dc.get_placed_count() > 0:
		ToastManager.show_warning("Undo the placed models before switching units")
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
	# Skip disabled/header rows AND rows the phase says are spent (PRP §2.6:
	# cycling follows activation eligibility, not raw list order — without
	# this, finishing a unit resets the list selection and the next bumper
	# press lands right back on the unit that just moved).
	var next := cur
	var found := -1
	for _i in range(list.item_count):
		next = wrapi(next + dir, 0, list.item_count)
		if not list.is_item_selectable(next) or list.is_item_disabled(next):
			continue
		if not _cycle_row_eligible(list, next):
			continue
		found = next
		break
	if found == -1 or found == cur:
		return
	list.select(found)
	list.ensure_current_is_visible()
	list.item_selected.emit(found)


# Deployment placing: D-pad ◀ ▶ cycles the value of the highlighted selector
# row (model type or formation) via Main so the card UI stays in sync. Focus
# navigation keeps priority — with a focused control, ui_left/ui_right must
# keep navigating.
func _pad_deploy_option_cycle(dir: int) -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	if _deployment_controller_placing() == null:
		return false
	var m := get_tree().current_scene
	if m == null or not m.has_method("pad_cycle_deploy_option"):
		return false
	return m.pad_cycle_deploy_option(dir)


# Deployment placing: D-pad ▲ ▼ moves the ▶ highlight between the card's
# selector rows (Deploy Formation / Select Model Type). Returns false when the
# unit has no picker so the press falls through to panel-focus entry exactly
# as before.
func _pad_deploy_row_cycle(dir: int) -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	if _deployment_controller_placing() == null:
		return false
	var m := get_tree().current_scene
	if m == null or not m.has_method("pad_cycle_deploy_row"):
		return false
	return m.pad_cycle_deploy_row(dir)


# ▲ ▼ fall-through: phase-specific option-list stepping — the ELIGIBLE
# TARGETS rows in charge, the weapon rows in shooting — before the press
# falls back to generic panel-focus entry. Each hook lives on its phase
# controller so stepping drives the exact state a mouse interaction would.
func _pad_step_secondary(dir: int) -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return false
	match m.current_phase:
		GameStateData.Phase.CHARGE:
			var cc = m.charge_controller if ("charge_controller" in m) else null
			if cc != null and is_instance_valid(cc) and cc.has_method("pad_step_target"):
				return cc.pad_step_target(dir)
		GameStateData.Phase.SHOOTING:
			var sc = _shooting_controller_in_shooting_phase()
			if sc != null and sc.has_method("pad_step_weapon"):
				return sc.pad_step_weapon(dir)
	return false


# Charge: A (with the cursor parked) toggles the D-pad-highlighted target row
# in or out of the declaration — the pad equivalent of Click / Ctrl+Click on
# the ELIGIBLE TARGETS list.
func _pad_charge_toggle() -> bool:
	if VirtualCursor.is_cursor_active():
		return false
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or m.current_phase != GameStateData.Phase.CHARGE:
		return false
	var cc = m.charge_controller if ("charge_controller" in m) else null
	if cc == null or not is_instance_valid(cc) or not cc.has_method("pad_toggle_target"):
		return false
	return cc.pad_toggle_target()


# The DeploymentController while a model-placement session is live, else
# null. Covers all three placement flows: normal deployment, movement-phase
# reinforcement arrivals, and scout-reserves set-up — the pad affordances
# (X undo, selector rows, A cursor-warp, unit-switch lock) apply to each.
func _deployment_controller_placing() -> Node:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or not ("deployment_controller" in m):
		return null
	var dc = m.deployment_controller
	if dc == null or not is_instance_valid(dc) or not dc.has_method("is_placing") or not dc.is_placing():
		return null
	match m.current_phase:
		GameStateData.Phase.DEPLOYMENT:
			return dc
		GameStateData.Phase.MOVEMENT:
			return dc if dc.is_reinforcement_mode else null
		GameStateData.Phase.SCOUT:
			return dc if dc.is_scout_reserves_mode else null
	return null


# Phase-aware eligibility for a unit-list row. Phase controllers opt in by
# exposing pad_can_cycle_to(unit_id); rows without unit metadata stay eligible
# (generic lists cycle exactly as before).
func _cycle_row_eligible(list: ItemList, idx: int) -> bool:
	var unit_id = list.get_item_metadata(idx)
	if unit_id == null or str(unit_id) == "":
		return true
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return true
	if m.current_phase == GameStateData.Phase.MOVEMENT and ("movement_controller" in m):
		var mc = m.movement_controller
		if mc != null and is_instance_valid(mc) and mc.has_method("pad_can_cycle_to"):
			return mc.pad_can_cycle_to(str(unit_id))
	return true


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
	# Placement (deployment / reinforcement / scout reserves): X = undo the
	# last placed model (parked-cursor context action, mirroring the movement
	# undo below). Undoing every model re-enables LB/RB unit switching.
	# undo_last_model emits models_placed_changed, so Main refreshes the
	# card/buttons itself.
	var dc = _deployment_controller_placing()
	if dc != null and dc.get_placed_count() > 0 and dc.has_method("undo_last_model"):
		return dc.undo_last_model()
	# Charge: X = skip the selected unit's charge (same as the Skip Charge
	# button; only enabled while no charge move is being resolved).
	var mc_scene := get_tree().current_scene
	if mc_scene != null and ("current_phase" in mc_scene) and mc_scene.current_phase == GameStateData.Phase.CHARGE \
			and ("charge_controller" in mc_scene) and mc_scene.charge_controller != null \
			and is_instance_valid(mc_scene.charge_controller) \
			and mc_scene.charge_controller.has_method("pad_skip") \
			and mc_scene.charge_controller.pad_skip():
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
	# Any deployment-controller placement (deployment / reinforcement / scout
	# reserves): "pickup" is just parking the cursor over the placement area;
	# every A after that is a normal cursor click that places a model.
	if _deployment_controller_placing() != null:
		var dz_center := _deployment_zone_center()
		if dz_center == Vector2.INF:
			return false
		_center_camera_on_world(dz_center)
		VirtualCursor.warp_to(m.world_to_screen_position(dz_center))
		return true
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
	return false


func _drop_carry() -> void:
	VirtualCursor.set_left_button(false)
	carry_active = false


func _cancel_carry() -> void:
	# The mouse-parity cancel: put the model back where it was picked up and
	# release (there is no dedicated drag-cancel in the mouse flow either).
	var unit_id := _carry_unit_id
	var staged_before := _movement_staged_count(unit_id)
	VirtualCursor.warp_to(_carry_pickup_screen)
	VirtualCursor.set_left_button(false)
	carry_active = false
	# Releasing at the pickup point still STAGES a zero-distance move (the
	# drag pipeline stages every drop) — which would mark the unit as
	# mid-move: the M4 action menu won't reopen and a junk 0" stage would be
	# auto-confirmed later. Undo exactly that stage once the synthetic
	# release has been processed. Movement phase only; -1 = not movement.
	if staged_before >= 0:
		_undo_cancelled_carry_stage(unit_id, staged_before)


func _undo_cancelled_carry_stage(unit_id: String, staged_before: int) -> void:
	# The synthetic release goes through the input queue — give it two frames
	# to land before checking whether it staged anything.
	await get_tree().process_frame
	await get_tree().process_frame
	if carry_active:
		return  # already picked up again
	if _movement_staged_count(unit_id) <= staged_before:
		return  # the drop was rejected / nothing staged — nothing to undo
	var m := get_tree().current_scene
	if m == null or not ("movement_controller" in m):
		return
	var mc = m.movement_controller
	if mc != null and is_instance_valid(mc) and str(mc.active_unit_id) == unit_id \
			and mc.has_method("_on_undo_model_pressed"):
		mc._on_undo_model_pressed()


# staged_moves count for `unit_id` in the Movement phase, or -1 when not in
# the Movement phase (charge carries stage differently and keep old behavior).
func _movement_staged_count(unit_id: String) -> int:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or m.current_phase != GameStateData.Phase.MOVEMENT:
		return -1
	var phase = PhaseManager.get_current_phase_instance()
	if phase == null or not phase.has_method("get_active_move_data"):
		return -1
	return phase.get_active_move_data(unit_id).get("staged_moves", []).size()


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
		# ItemLists never take pad focus: lists are driven by their dedicated
		# affordances (LB/RB unit cycling, ▲ ▼ steppers) — focusing one would
		# turn ui_up/ui_down into unit cycling, the exact bug the bumper-only
		# rule exists to prevent.
		if n is Control and not (n is ItemList) and n.focus_mode == Control.FOCUS_ALL \
				and n.is_visible_in_tree() and not (n is BaseButton and n.disabled):
			return n
		for child in n.get_children(true):
			queue.append(child)
	return null


# BUMPER-ONLY unit cycling: while the pad is the active device every ItemList
# in the side panels is demoted to FOCUS_CLICK (mouse clicks are unaffected)
# so directional focus navigation — D-pad OR left-stick ui_up/ui_down — can
# neither land in a list nor walk through it, and a list that already holds
# focus (e.g. mouse-clicked before switching to pad) releases it. Restored to
# the saved focus mode when the keyboard/mouse takes over.
func _apply_list_focus_policy(pad: bool) -> void:
	var m := get_tree().current_scene
	if m == null:
		return
	for root_path in ["HUD_Right", "HUD_Bottom"]:
		var root := m.get_node_or_null(root_path)
		if root == null:
			continue
		var queue: Array = [root]
		while not queue.is_empty():
			var n: Node = queue.pop_front()
			if n is ItemList:
				if pad:
					if n.focus_mode == Control.FOCUS_ALL:
						n.set_meta("pad_saved_focus_mode", n.focus_mode)
						n.focus_mode = Control.FOCUS_CLICK
					if n.has_focus():
						n.release_focus()
				elif n.has_meta("pad_saved_focus_mode"):
					n.focus_mode = n.get_meta("pad_saved_focus_mode")
					n.remove_meta("pad_saved_focus_mode")
			for child in n.get_children(true):
				queue.append(child)


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
	elif PadActionBar.is_open():
		hints = HINTS_MENU
	elif get_viewport().gui_get_focus_owner() != null:
		hints = HINTS_FOCUS
	else:
		var sc = _shooting_controller_in_shooting_phase()
		if sc != null and str(sc.active_shooter_id) != "":
			hints = HINTS_TARGETS
		elif _deployment_controller_placing() != null:
			hints = HINTS_DEPLOY
		else:
			var cc = _charge_controller_selecting()
			if cc != null:
				hints = HINTS_CHARGE
			elif _movement_menu_available():
				hints = HINTS_MOVE
	PadHintBar.set_hints(hints)


# Movement phase with a selected unit whose move-mode decision is still open
# (the state where ▲ ▼ / A open the action bar).
func _movement_menu_available() -> bool:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or m.current_phase != GameStateData.Phase.MOVEMENT:
		return false
	var mc = m.movement_controller if ("movement_controller" in m) else null
	if mc == null or not is_instance_valid(mc) or not mc.has_method("pad_menu_options"):
		return false
	return not mc.pad_menu_options().is_empty()


# The ChargeController while the charge phase is live with a unit selected
# and its charge not yet being moved (declaration / roll stage), else null.
func _charge_controller_selecting() -> Node:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or not ("charge_controller" in m):
		return null
	if m.current_phase != GameStateData.Phase.CHARGE:
		return null
	var cc = m.charge_controller
	if cc == null or not is_instance_valid(cc):
		return null
	if str(cc.active_unit_id) == "" or bool(cc.awaiting_movement):
		return null
	return cc
