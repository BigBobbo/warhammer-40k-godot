extends Node

# M2 pad router (PRPs/steam_deck_controller_support.md §4.1/§5.1, milestone
# M2): the native-controls layer on top of the M1 virtual cursor.
#
#   LB/RB  — THE unit-cycling control, and the only one (BUMPER-ONLY rule):
#            cycle the ACTING unit in every phase — eligible shooters
#            (shooting, reusing the shipped shoot_* semantics) or the
#            right-panel unit list (other phases; same entry point a mouse
#            row-click uses). Never the target ring: targets are the armed
#            unit's sub-menu on the D-pad. Deployment: cycling switches which
#            unit is being deployed, but locks once any model of the current
#            unit is placed (undo them all to unlock — mirrors the mouse rule).
#            Works while the action bar is open too — the menu follows.
#   D-pad ◀ ▶ — shooting with an armed shooter: walk the eligible-target ring
#            (highlight rings + camera follow; A assigns to the current
#            weapon). Placement (deployment / reinforcement / scout reserves):
#            cycle the value of the highlighted selector row — model type
#            (multi-profile units) or formation (Single / Spread / Tight).
#            Movement with an open move-mode decision: open the action bar,
#            exactly like ▲ ▼ — EVERY D-pad direction lands in the on-screen
#            menu, so a ◀/▶ press can never dump the player into right-panel
#            focus while the hint bar promises "Move Menu"; otherwise panel
#            focus entry
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
#            deselect (the shoot_cancel_target semantic). Movement: a clean B
#            (nothing to release/park) undoes the last staged model — the
#            mouse "Undo Last Model" button (X used to hold this job).
#   X      — context action: skip the active shooter (shoot_skip_unit).
#            Movement: "this model is finished" — mid-carry it drops the held
#            model AND hands over the unit's next un-placed model; after an
#            A-drop it does the same from the parked state. This is the
#            multi-step seam: A taps waypoints (drop, re-pick, drop — the
#            model keeps focus and its staged budget accumulates), X seals
#            the model and advances. Otherwise only when the virtual cursor
#            is parked — cursor mode owns X as right-click (VirtualCursor
#            consumes it first, except mid-carry where the router owns X)
#   Y      — toggle the datasheet of the highlighted target / selected unit
#   L3     — click the left thumbstick: cycle to the NEXT model of the active
#            unit, consistently in every phase that positions individual models
#            (Movement + Charge, via _hop_model). THE model-switch control — the
#            one free, reliable button, chosen over the Steam Deck L4/R4 paddles
#            which reach the game as JOY_BUTTON_PADDLE* only when Steam Input is
#            configured to forward them (still bound below as a bonus)
#   D-pad  — with nothing focused: enter panel focus (right panel, then
#            bottom bar); with focus: normal ui_* navigation (not consumed).
#            Panel-focus entry stands down mid-move (model in hand or the
#            move session locked): those states advertise no D-pad affordance
#            and focus would strand the player out of the carry flow. Focus a
#            panel control still holds — mouse-click residue included — is
#            released whenever the pad takes over as the active device and
#            whenever a bumper cycles units, so stale focus can never hijack
#            the D-pad away from the board flow (dialogs are never touched).
#
# Input-order note: _input runs in REVERSE tree order, so the order is
# Main (scene) -> VirtualCursor -> PadRouter -> PadHintBar -> IDM. Main only
# consumes pad_phase_action; VirtualCursor consumes A/X while the cursor is
# active. Everything here acts on what falls through.

const HINTS_BOARD := [
	["rb", "Cycle Units"],
	["a", "Select"],
	["ls", "Point"],
	["lt/rt", "Zoom"],
	["y", "Datasheet"],
	["dpad", "Focus Panels"],
	["menu", "End Phase"],
	["view", "Pause Menu"],
]
const HINTS_TARGETS := [
	["rb", "Cycle Units"],
	["dpad", "Target ◀▶ · Weapon ▲▼"],
	["a", "Assign Target"],
	["x", "Skip Unit"],
	["y", "Datasheet"],
	["menu", "Confirm Targets"],
	["b", "Deselect"],
]
# Charge hints are per-stage so the ☰ chip NEVER promises an action Start
# can't deliver (the old static "Declare / Roll" chip showed even when neither
# was possible and Start fell through to the End-Phase confirm — the reported
# "it says declare or roll but it ends the phase" trap).
const HINTS_CHARGE_SELECT := [
	["rb", "Cycle Units"],
	["dpad", "Pick Target"],
	["a", "Toggle Target"],
	["x", "Skip Charge"],
	["y", "Datasheet"],
	["menu", "End Phase"],
]
const HINTS_CHARGE_READY := [
	["dpad", "Pick Target"],
	["a", "Toggle Target"],
	["menu", "Declare Charge"],
	["x", "Skip Charge"],
	["y", "Datasheet"],
]
const HINTS_CHARGE_ROLL := [
	["menu", "Roll 2D6"],
	["x", "Skip Charge"],
	["y", "Datasheet"],
]
# Rolled successfully, models not all in engagement yet (no model in hand):
# A picks a model up, X bulk-snaps, B undoes the last placed model, Start
# confirms once every declared target is reached.
const HINTS_CHARGE_MOVE := [
	["a", "Grab Model"],
	["l3", "Next Model"],
	["x", "Snap to Contact"],
	["b", "Undo Model"],
	["menu", "Confirm Charge"],
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
# Charge carry (one model at a time): the plain set — no per-model advance and
# no group grab, so neither "X Finish Model" nor "dpad Grab All". Start drops
# the held model and confirms the charge when every declared target is reached.
const HINTS_CARRY := [
	["ls", "Move Model"],
	["rs", "Precision"],
	["a", "Drop"],
	["l3", "Swap Model"],
	["lb", "Rotate ⟲"],
	["rb", "Rotate ⟳"],
	["b", "Cancel"],
	["menu", "Confirm Charge"],
]
# Movement carry: the plain set plus the multi-step contract — A drops a
# waypoint (the model KEEPS focus; A again picks it back up to keep going with
# whatever movement it has left), X drops AND seals the model, advancing to the
# unit's next un-placed model — and "dpad Grab All", which lifts every unmoved
# model of the unit into one group carry.
const HINTS_CARRY_MOVE := [
	["ls", "Move Model"],
	["rs", "Precision"],
	["a", "Drop"],
	["x", "Finish Model"],
	["dpad", "Grab All"],
	["l3", "Swap Model"],
	["lb", "Rotate ⟲"],
	["rb", "Rotate ⟳"],
	["b", "Cancel"],
	["menu", "Confirm / End"],
]
# Group carry (every unmoved model of the unit in hand at once): the whole
# formation rides the stick; A places every model that fits at the drop spot
# (models that don't fit stay behind and are handed back individually).
const HINTS_CARRY_GROUP := [
	["ls", "Move Models"],
	["rs", "Precision"],
	["a", "Place Models"],
	["b", "Cancel"],
	["menu", "Confirm / End"],
]
const HINTS_MENU := [
	["dpad", "Choose Action"],
	["rb", "Cycle Units"],
	["l3", "Next Model"],
	["a", "Confirm"],
	["b", "Cancel"],
]
# Movement with a selected unit whose move-mode decision is still open: ▲ ▼
# opens the same action bar A does, so the D-pad browses the unit's phase
# options instead of the unit list. (No X/undo chip: nothing can be staged
# while the mode decision is still open.)
const HINTS_MOVE := [
	["rb", "Cycle Units"],
	["a", "Move Menu"],
	["dpad", "Move Menu"],
	["l3", "Next Model"],
	["ls", "Point"],
	["lt/rt", "Zoom"],
	["y", "Datasheet"],
	["menu", "End Phase"],
]
# Movement mid-move with a model just dropped and models still un-placed (the
# multi-step state): the dropped model KEEPS focus — A picks it back up to keep
# spending its remaining move, X seals it and hands over the next un-placed
# model, B undoes the last staged model, L3 (and the paddles where Steam Input
# forwards them) browses models freely. The bumpers stay locked to this unit
# until the move is confirmed or undone.
const HINTS_MOVE_STAGED := [
	["a", "Move Model"],
	["x", "Next Model"],
	["l3", "Browse Models"],
	["b", "Undo Model"],
	["y", "Datasheet"],
	["menu", "Confirm Move"],
]
# Movement with a committed move where every model has been placed (X's
# finish-model advance lands here after the last model): Start confirms the
# whole move, A picks a model back up to adjust it, L3 (and the back paddles,
# where Steam Input forwards them) cycles between models and B undoes the last
# staged model. The bumpers stay locked to this unit until the move is confirmed
# or undone.
const HINTS_MOVE_LOCKED := [
	["menu", "Confirm Move"],
	["a", "Move a Model"],
	["dpad", "Grab All Unmoved"],
	["l3", "Next Model"],
	["b", "Undo Model"],
	["y", "Datasheet"],
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
# Group carry: EVERY unmoved model of the unit rides the cursor as one
# formation (MovementController's mouse group-drag machinery runs underneath).
# Entered from the move menu's "Move All Together" or any D-pad press while a
# model is in hand / the unit is mid-move. Windowed scenarios assert this.
var group_carry_active: bool = false


func is_carrying() -> bool:
	return carry_active


func _ready() -> void:
	InputDeviceManager.device_changed.connect(_on_device_changed)


func _on_device_changed(mode: int) -> void:
	# BUMPER-ONLY rule: while the pad drives, unit lists leave the focus
	# chain (and give up any focus they already hold); on KBM they restore.
	var pad := mode == InputDeviceManager.InputMode.PAD
	_apply_list_focus_policy(pad)
	# Focus a mouse click left behind on a panel button must not hijack the
	# pad: with any focus owner alive every router affordance stands down (the
	# focus guards) and the first D-pad presses silently walk the OLD focus
	# chain instead of opening the unit's menu. Picking up the pad returns to
	# the board context; deliberate panel focus is one D-pad press away.
	# Dialogs keep their focus (the IDM watcher needs it for A-to-confirm) —
	# only the HUD panel subtrees release.
	if pad:
		_release_panel_focus()
	_update_hints()


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	# A joypad event IS pad input — claim inline so the session's very first
	# press acts instead of being dropped (the _process poll runs after us).
	InputDeviceManager.claim_pad()
	# Diagnostic (debug level): log the raw button index of every joypad press.
	# A player whose Steam Deck L4/R4 "do nothing" can read the debug log to see
	# whether the paddles arrive at all — on a stock Deck the game sees a virtual
	# Xbox pad with NO paddle buttons, so Steam Input must be configured to
	# forward them or they never reach here. PADDLE1..4 = indices 16..19.
	DebugLogger.debug("PadRouter: joypad button pressed", {"button_index": event.button_index})
	# A menu-level modal (the Save/Load dialog, …) drives itself entirely with
	# Godot's native focus navigation. This board router must stay out of its way:
	# bumper unit-cycling, D-pad panel-focus entry and — above all — the ItemList
	# focus-release at the tail of this handler would each break the dialog's own
	# D-pad list/button navigation (the saves list could never keep focus). Let
	# the event flow untouched to the UI system; the pad is already claimed above.
	if _native_nav_modal_open():
		return
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
			# L3 (and the back paddles, where Steam Input forwards them) keeps its
			# one meaning with the menu up: hop the selected unit's models
			# (camera-follow) so the player can pick WHICH model leads before
			# choosing Move — the carry starts at this index.
			JOY_BUTTON_LEFT_STICK:
				_hop_model(1)
			JOY_BUTTON_PADDLE1, JOY_BUTTON_PADDLE3:
				_hop_model(1)
			JOY_BUTTON_PADDLE2, JOY_BUTTON_PADDLE4:
				_hop_model(-1)
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
		JOY_BUTTON_LEFT_STICK:
			# L3 (press the left thumbstick in) is THE model-cycle button — the one
			# free, reliable controller button, so it means "next model" identically
			# in every phase that positions a unit's individual models (Movement +
			# Charge, via _hop_model). Reliable where the Steam Deck L4/R4 paddles are
			# not (those reach the game as JOY_BUTTON_PADDLE* only when Steam Input is
			# configured to forward them). _hop_model returns false elsewhere, so L3
			# is a harmless no-op in phases without per-model positioning.
			if _hop_model(1):
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
			if _pad_deploy_row_cycle(-1) or _pad_step_secondary(-1) or _charge_dpad_consume() or _try_open_move_menu() or _try_grab_all_remaining() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_DOWN:
			if _pad_deploy_row_cycle(1) or _pad_step_secondary(1) or _charge_dpad_consume() or _try_open_move_menu() or _try_grab_all_remaining() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_LEFT:
			# Model-switching lives on L3 (left-stick click — the one free, reliable
			# button; the Steam Deck paddles only reach the game when Steam Input
			# forwards them). D-pad ◀ ▶ stays free for menu / option navigation and
			# never fights the move-mode menu. Deployment option-cycle keeps it;
			# shooting uses ◀ ▶ to walk the armed shooter's target ring (bumpers stay
			# on shooter cycling); charge steps the ELIGIBLE TARGETS rows so every
			# D-pad direction lands in the charge flow, matching ▲ ▼ — a ◀/▶ press
			# must never dump the player into right-panel focus while the hint bar
			# says "Pick Target". With a selected unit mid-move, ◀ also grabs every
			# unmoved model (_try_grab_all_remaining), matching ▲ ▼ ▶.
			if _pad_step_shoot_target(-1) or _pad_step_charge_target(-1) or _charge_dpad_consume() or _pad_deploy_option_cycle(-1) or _try_open_move_menu() or _try_grab_all_remaining() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		JOY_BUTTON_DPAD_RIGHT:
			# _try_open_move_menu before panel focus (matching ▲ ▼): with an
			# open move-mode decision ◀ ▶ must open the same on-screen menu the
			# hint bar advertises for "dpad", never strand the player in the
			# right-panel focus chain — the panel is a mouse surface, and once
			# focused every following D-pad press walks it instead of the menu.
			if _pad_step_shoot_target(1) or _pad_step_charge_target(1) or _charge_dpad_consume() or _pad_deploy_option_cycle(1) or _try_open_move_menu() or _try_grab_all_remaining() or _enter_panel_focus():
				get_viewport().set_input_as_handled()
		# Steam Deck back paddles hop between the selected unit's models (Movement
		# / Charge) — the job D-pad ◀ ▶ used to do. Works at every stage of the
		# Movement phase: browsing/menu = camera hop to pick the lead model;
		# mid-carry = revert the un-dropped model in hand and take the prev/next
		# one (staged drops keep their spot). Both back pairs are bound so
		# whichever the player's config exposes works: right paddles (commonly
		# R4/R5 → PADDLE1/3) = next model, left paddles (L4/L5 → PADDLE2/4) = prev.
		JOY_BUTTON_PADDLE1, JOY_BUTTON_PADDLE3:
			if _hop_model(1):
				get_viewport().set_input_as_handled()
		JOY_BUTTON_PADDLE2, JOY_BUTTON_PADDLE4:
			if _hop_model(-1):
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
	if carry_active:
		# A model is in hand — the mode decision is being EXECUTED, not open.
		# Opening the bar mid-carry (possible when the cursor reads parked in
		# the same event that would have parked it) had A activating a menu
		# chip instead of dropping the model.
		return false
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
	# anyway, so gating here is just intent. "Move All Together" flows into the
	# GROUP carry: the whole unit rides the stick as one formation.
	if choice_id == "NORMAL_ALL":
		call_deferred("_auto_group_carry_after_menu")
	elif choice_id == "NORMAL" or choice_id == "FALL_BACK":
		call_deferred("_auto_carry_after_menu")


func _auto_carry_after_menu() -> void:
	if not carry_active and _try_begin_carry():
		_update_hints()


func _auto_group_carry_after_menu() -> void:
	if not carry_active and _try_begin_group_carry():
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
	# Bumpers are a BOARD action: cycling while a side-panel control holds
	# focus (mouse-click residue, or deliberate D-pad panel work) releases
	# that focus first, so the pad lands back in the unit flow. Without this,
	# the focus guards keep the D-pad walking panel buttons instead of opening
	# the NEW unit's move menu, and a following A would press the still-focused
	# control of the previous context. Dialog focus is untouched.
	_release_panel_focus()
	var sc = _shooting_controller_in_shooting_phase()
	if sc != null:
		# BUMPER-ONLY rule holds in shooting too: LB/RB always cycles the
		# SHOOTER (the acting unit), never the target ring. The old behavior —
		# bumpers flipping to target-cycling the instant a shooter was armed —
		# meant the first bumper press locked you out of browsing shooters
		# entirely (deselect + press just re-armed the first one again).
		# Targets are the armed shooter's sub-menu now: D-pad ◀ ▶, next to the
		# weapon rows on ▲ ▼ (mirrors charge's target stepping).
		sc._keyboard_cycle_units(dir < 0)  # reuses the Tab / Shift+Tab path
		target_highlight_id = ""
		if str(sc.active_shooter_id) != "":
			_center_camera_on_unit(str(sc.active_shooter_id))
		return
	# Deployment: once any model of the current unit is on the table the unit
	# is committed — LB/RB can't switch away until every model is undone
	# (mirrors the mouse rule in Main._deploy_try_switch_unit).
	var dc = _deployment_controller_placing()
	if dc != null and dc.get_placed_count() > 0:
		ToastManager.show_warning("Undo the placed models before switching units")
		return
	# Movement: a unit committed to its move (mode locked or a model staged) can't
	# be bumped away until it's confirmed (Start) or reset (undo) — mirrors the
	# deployment lock above so a mis-cycle can't strand a half-moved unit.
	var mc := _movement_controller()
	if mc != null and mc.has_method("pad_is_move_session_locked") and mc.pad_is_move_session_locked():
		ToastManager.show_warning("Confirm or reset this unit's move before switching")
		return
	# Charge: same lock once the charge is committed (declared / rolling /
	# moving). Cycling would re-fire _on_unit_selected, which resets
	# awaiting_roll/awaiting_movement locally while the PHASE keeps the pending
	# charge — leaving a disabled Roll button and no way forward (the reported
	# "Roll 2D6 is shaded out and Start ends the phase" dead-end).
	if _charge_session_locked():
		ToastManager.show_warning("Resolve this charge first — Start rolls / confirms")
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
	# Camera-follow on bumper cycling (rows carry the unit id as metadata).
	# Phase selection handlers don't move the camera themselves, so without
	# this a pad player cycles "blind" — worst right after loading a save,
	# where the whole-board overview (~0.3 zoom) leaves every unit unreadably
	# small; _center_camera_on_unit frames-with-zoom in that regime.
	var uid = list.get_item_metadata(found)
	if uid != null and str(uid) != "":
		_center_camera_on_unit(str(uid))


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


# Shooting: D-pad ◀ ▶ walks the armed shooter's target ring (on-board highlight
# rings + camera-follow via _cycle_target). Falls through when there is no armed
# shooter / no targets, so deployment option-cycling and panel-focus entry keep
# their ◀ ▶ meanings in every other context.
func _pad_step_shoot_target(dir: int) -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var sc = _shooting_controller_in_shooting_phase()
	if sc == null or str(sc.active_shooter_id) == "" or sc.eligible_targets.is_empty():
		return false
	_cycle_target(sc, dir)
	return true


# Charge: D-pad ◀ ▶ steps the ELIGIBLE TARGETS rows exactly like ▲ ▼ — all
# four directions land in the charge flow, so no direction can dump the player
# into panel focus while a target is being picked.
func _pad_step_charge_target(dir: int) -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var cc := _charge_controller_any()
	if cc == null or not cc.has_method("pad_step_target"):
		return false
	return cc.pad_step_target(dir)


# D-pad fall-through while a charge is mid-resolution: target stepping is
# locked (rows frozen after the declaration), and panel-focus entry would
# strand the player in the mouse panels — consume the press and say what the
# pad CAN do instead. Inert (false) outside those locked charge states.
func _charge_dpad_consume() -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var cc := _charge_controller_any()
	if cc == null:
		return false
	if bool(cc.awaiting_movement):
		ToastManager.show_toast("Charge rolled — A grabs a model, X snaps to contact, Start confirms")
		return true
	if bool(cc.awaiting_roll):
		ToastManager.show_toast("Charge declared — Start rolls 2D6")
		return true
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
	# Mid-carry X (the cursor is live but VirtualCursor stands down — see its
	# carry guard): Movement = "finish this model" — drop it here and hand
	# over the unit's next un-placed model. Any other carry (charge) consumes
	# the press inert so a stray X can't fire the skip-charge action or a
	# synthetic right-click underneath a held model.
	if carry_active:
		# Group carry: A places the whole group and B cancels — X has no per-model
		# meaning (there is no single "current" model to finish), so consume it
		# inert rather than firing _finish_model_and_advance on the group.
		if group_carry_active:
			return true
		if _movement_controller() != null:
			return _finish_model_and_advance()
		return true
	if VirtualCursor.is_cursor_active():
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
	# Charge, moving models into engagement (no model in hand): X = Snap to
	# Contact — the one-press "place every unmoved model base-to-base with its
	# nearest declared target" helper, the pad's answer to per-model dragging.
	var cc := _charge_controller_any()
	if cc != null and cc.has_method("pad_snap_to_contact") and cc.pad_snap_to_contact():
		return true
	# Charge: X = skip the selected unit's charge (same as the Skip Charge
	# button; only enabled while no charge move is being resolved).
	if cc != null and cc.has_method("pad_skip") and cc.pad_skip():
		return true
	# Movement, parked after an A-drop (the multi-step state): X = "this model
	# is finished" — advance to the unit's next un-placed model. The undo that
	# used to live here moved to B (_handle_back).
	return _finish_model_and_advance()


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
	# Movement: a clean B (no focus to release, cursor already parked) backs the
	# move out one model — the mouse "Undo Last Model" button. X used to hold
	# this job; it now seals models in the multi-step flow, and B is the natural
	# back-out. Only with something actually staged, so B stays inert otherwise.
	var mc := _movement_controller()
	if mc != null and str(mc.active_unit_id) != "" \
			and _movement_staged_count(str(mc.active_unit_id)) > 0 \
			and mc.has_method("_on_undo_model_pressed"):
		mc._on_undo_model_pressed()
		return true
	# Charge, moving models (no model in hand): the same clean-B back-out —
	# the Undo Last Model button under the charge panel.
	var cc := _charge_controller_any()
	if cc != null and cc.has_method("pad_undo_model") and cc.pad_undo_model():
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
			# Charge models are only draggable while the phase is executing the
			# charge move (roll made, models heading into engagement). Starting a
			# carry in the declare/roll stages warped the cursor and held a
			# synthetic LMB that ChargeController ignores — a junk carry whose
			# hint bar then promised affordances that did nothing.
			if m.current_phase == GameStateData.Phase.CHARGE and not bool(ctrl.awaiting_movement):
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


func _drop_carry(regrab_group := true) -> bool:
	# Movement phase: consult the controller BEFORE releasing. An illegal drop
	# (over a wall, past the move cap, overlapping) keeps the model in hand — the
	# "you can't put the piece on an illegal square" rule — instead of snapping it
	# back and stranding the still-active cursor, which used to swallow the next A
	# press as a raw board click and silently switch the selected unit. Returns
	# true when the model was actually released (false = illegal, still carried).
	# Group carry: the drop only stays refused when NOT A SINGLE model fits at
	# the spot — otherwise the release stages every model that fits and the
	# leftovers are handed back (partial placement).
	var mc := _movement_controller()
	if group_carry_active:
		if mc != null and mc.has_method("pad_group_drop_rejection"):
			var group_reason := str(mc.pad_group_drop_rejection(VirtualCursor.get_cursor_pos()))
			if group_reason != "":
				ToastManager.show_warning(group_reason)
				return false  # still carrying the whole group
	elif mc != null and mc.has_method("pad_carry_drop_rejection"):
		var reason := str(mc.pad_carry_drop_rejection(VirtualCursor.get_cursor_pos()))
		if reason != "":
			ToastManager.show_warning(reason)
			return false  # still carrying: A re-checks, the stick keeps steering
	var was_group := group_carry_active
	VirtualCursor.set_left_button(false)
	carry_active = false
	group_carry_active = false
	# Park so the cursor can't consume the next A as a stray click; with it
	# parked, A routes back through the router (pick the model up again / confirm).
	VirtualCursor.park()
	if was_group:
		# Group drop (partial placement): hand back the models the drop couldn't
		# fit as a smaller group once the async staging settles — the group edition
		# of moving-by-default. Suppressed when Start drove the drop (regrab_group
		# false — the player asked to confirm, not to keep moving) and under the
		# scenario runner (it asserts the manual contract); those just refresh hints.
		if regrab_group and _movement_controller() != null and not _in_windowed_scenario():
			call_deferred("_auto_regrab_after_group_drop")
		else:
			call_deferred("_refresh_hints_settled")
	else:
		# Single model (#713 multi-step): the dropped model KEEPS the focus
		# (carry_model_index untouched) — a drop is a waypoint, not a hand-off. A
		# picks the same model back up to spend its remaining move in another leg;
		# X seals the model and advances to the next un-placed one; L4/R4/L3 browse.
		# Nothing is auto-grabbed. The hint bar refreshes once the queued release
		# has staged — the _input-tail refresh runs too early (pre-drop set).
		call_deferred("_refresh_hints_settled")
	return true


func _refresh_hints_settled() -> void:
	# A drop's synthetic release travels the input queue and its
	# STAGE_MODEL_MOVE lands a frame or two later; refresh the hint bar after
	# that so the multi-step affordances (A Move Model / X Next Model / B Undo
	# Model) appear right at the drop instead of only on the next press.
	await get_tree().process_frame
	await get_tree().process_frame
	_update_hints()


# X in the Movement phase: "this model is finished". Mid-carry it first drops
# the held model (same legality gate as A — an illegal spot keeps it in hand);
# from the parked multi-step state it advances directly. Either way the unit's
# next un-placed model is then handed to the stick. Returns true when the press
# was consumed (movement context existed), false to let X fall through.
func _finish_model_and_advance() -> bool:
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "":
		return false
	if carry_active:
		if not _drop_carry():
			return true  # illegal spot: toast shown, model stays in hand
	elif not _movement_session_locked():
		return false  # no move in progress — nothing to finish
	# Browsing with the pad after mouse-staged moves (or a unit switch) can leave
	# the carry bookkeeping on another unit; re-anchor before the deferred scan.
	if str(mc.active_unit_id) != _carry_unit_id:
		_carry_unit_id = str(mc.active_unit_id)
		carry_model_index = 0
	call_deferred("_carry_next_unplaced_model")
	return true


func _carry_next_unplaced_model() -> void:
	# Runs a couple frames after X so the STAGE_MODEL_MOVE from a just-released
	# model lands first (and so a Start/B pressed in the same frame wins). Advances
	# in alive-model order within the SAME unit; with every model placed it leaves
	# the player in the locked state where Start confirms the move.
	await get_tree().process_frame
	await get_tree().process_frame
	if carry_active:
		return  # player already picked something up again
	# Never yank a model into the player's hand while a modal owns the pad, the
	# cursor was re-activated, or a panel grabbed focus — those states mean the
	# player is doing something else, and auto-grabbing would fight them.
	if PadActionBar.is_open() or VirtualCursor.is_cursor_active():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "":
		return
	var unit_id := str(mc.active_unit_id)
	if unit_id != _carry_unit_id:
		return  # unit changed under us — don't drag the camera to a new unit
	var roster := _unit_move_roster(unit_id)
	var alive := roster.size()
	# Hand over the next model that has NOT been placed yet, scanning forward
	# with wrap-around and skipping staged ones — paddle hops let models be
	# placed out of order, and handing back a model the player already dropped
	# would silently threaten its kept position. The roster spans the bodyguard
	# AND attached characters, so an attached leader is offered here by default.
	var next_index := -1
	for step in range(1, alive + 1):
		var candidate := wrapi(carry_model_index + step, 0, alive)
		if _roster_entry_staged_pos(unit_id, roster[candidate]) == null:
			next_index = candidate
			break
	if next_index == -1:
		# Whole unit placed — tell the player what X can't do any more and where
		# the flow goes next, then leave them in the locked state to Confirm.
		ToastManager.show_toast("All models placed — Start confirms the move")
		return
	carry_model_index = next_index
	if _try_begin_carry():
		_update_hints()


# The active unit's combined move roster: its own alive models plus those of
# every attached character, as ordered {source_unit_id, model_id} entries. An
# attached leader forms one unit with its bodyguard and moves WITH it, so the
# per-model pad flow (L3/paddle browse, X "Next Model", the auto-advance after a
# drop) hands you the leader's model too — the leader is included by default, not
# only via "Move All Together". Model ids collide between the two units, so each
# entry keeps its source unit id; staging routes through the active unit's move
# data with model_source_unit_id (see _staged_model_pos_for).
func _unit_move_roster(active_unit_id: String) -> Array:
	var roster: Array = []
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return roster
	var unit_ids := [active_unit_id]
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		unit_ids.append(str(char_id))
	for source_uid in unit_ids:
		var models = GameState.get_unit(source_uid).get("models", [])
		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue
			roster.append({
				"source_unit_id": source_uid,
				"model_id": str(model.get("id", "m%d" % (i + 1))),
			})
	return roster


func _alive_model_count(unit_id: String) -> int:
	return _unit_move_roster(unit_id).size()


# The staged dest of a roster entry (null = not placed yet this move). Wraps
# _staged_model_pos_for with the entry's own source unit.
func _roster_entry_staged_pos(active_unit_id: String, entry: Dictionary):
	return _staged_model_pos_for(active_unit_id, str(entry.get("source_unit_id", active_unit_id)), str(entry.get("model_id", "")))


# ============================================================================
# Group carry — every unmoved model of the unit in one hand
# ============================================================================

# D-pad fall-through (Movement, after the move-menu check): grab EVERY model of
# the active unit that has not been placed yet and carry them as one formation.
# Reachable mid-carry (the in-hand model reverts first, like a paddle swap) and
# in the locked mid-move state; while the move menu is open the same feature is
# the "Move All Together" menu entry instead.
func _try_grab_all_remaining() -> bool:
	if group_carry_active:
		return true  # already carrying the whole group — consume the press
	if get_viewport().gui_get_focus_owner() != null:
		return false
	if _deployment_controller_placing() != null:
		return false  # reinforcement/scout placement owns the pad here
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "":
		return false
	if not mc.has_method("pad_select_unmoved_models") or not mc.has_method("pad_can_grab_group"):
		return false
	if not mc.pad_can_grab_group():
		return false  # no live move session (mode not begun / already completed)
	if carry_active:
		_grab_all_from_carry()
		return true
	return _try_begin_group_carry()


func _try_begin_group_carry() -> bool:
	if carry_active or PadActionBar.is_open():
		return false
	if get_viewport().gui_get_focus_owner() != null:
		return false
	var m := get_tree().current_scene
	if m == null or not m.has_method("world_to_screen_position"):
		return false
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "" or not mc.has_method("pad_select_unmoved_models"):
		return false
	if mc.has_method("pad_can_grab_group") and not mc.pad_can_grab_group():
		return false
	var count := int(mc.pad_select_unmoved_models())
	if count <= 0:
		return false  # every model already placed — nothing to grab
	var anchor = mc.pad_group_anchor_world_pos()
	if not (anchor is Vector2):
		if mc.has_method("pad_abort_group_drag"):
			mc.pad_abort_group_drag()
		return false
	_carry_unit_id = str(mc.active_unit_id)
	# Center first, THEN project — the warp target must use the final camera
	# transform. The synthetic press lands ON the anchor model (it is part of
	# the selection), so MovementController starts its group drag underneath.
	_center_camera_on_world(anchor)
	var screen: Vector2 = m.world_to_screen_position(anchor)
	VirtualCursor.warp_to(screen)
	VirtualCursor.set_left_button(true)
	_carry_pickup_screen = screen
	carry_active = true
	group_carry_active = true
	return true


# Grab-all pressed while a single model is in hand: revert that model to its
# pickup spot (same contract as a paddle swap — staged drops keep their spot),
# wait out the cancel's synthetic release + junk-stage undo (see
# _swap_carry_to_index for the 3-frame timing), then take the whole group.
func _grab_all_from_carry() -> void:
	_cancel_carry()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if carry_active or PadActionBar.is_open():
		return  # something else re-claimed the pad mid-grab
	if get_viewport().gui_get_focus_owner() != null:
		return
	if VirtualCursor.is_cursor_active():
		VirtualCursor.park()
	if _try_begin_group_carry():
		_update_hints()


# The auto-regrab of group-drop leftovers is a real-play smoothness affordance.
# The committed pad_group_move_all scenario asserts the manual contract, and the
# partial-placement regrab is validated live via the MCP bridge — so suppress the
# auto-hand-off under the scenario runner (mirrors how #713's single-model drop
# stays manual there too).
func _in_windowed_scenario() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if typeof(a) == TYPE_STRING and a.begins_with("--scenario-file="):
			return true
	return false


# After a group drop settles: hand the player the models the drop could NOT
# place, as a smaller group — moving-by-default for the leftovers. When
# everything was placed, clear the selection rings and leave the player in the
# locked state to Confirm (Start).
func _auto_regrab_after_group_drop() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _await_group_drop_settled()
	if carry_active:
		return  # player already picked something up again
	if PadActionBar.is_open() or VirtualCursor.is_cursor_active():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "" or str(mc.active_unit_id) != _carry_unit_id:
		return
	if not _try_begin_group_carry():
		# Whole unit placed — drop the leftover selection rings so the locked
		# state's affordances (A = pick ONE model, paddles hop) read clean.
		if mc.has_method("pad_abort_group_drag"):
			mc.pad_abort_group_drag()
	_update_hints()


# Public seam for Main's Start (End-Phase / Confirm) handler: when Start is
# pressed while a model is in hand (movement OR charge carry), Main routes here
# instead of confirming directly. Placing the held model first — then confirming
# once it has staged — avoids clearing the active unit out from under a live
# carry, which left the synthetic LMB / cursor stranded with no owner. Returns
# true when it took over the press (a carry was active), so Main knows to stop
# and consume.
func confirm_from_carry() -> bool:
	if not carry_active:
		return false
	# regrab_group=false: Start places the held model/group to END the move — do
	# not hand the leftovers back for more moving underneath the confirm.
	if _drop_carry(false):
		call_deferred("_confirm_move_after_drop")
	# Even if the drop was illegal (still carrying) we've handled the press — the
	# player gets the "can't place here" toast rather than a stray phase confirm.
	return true


# Start pressed mid-carry: place the held model, then confirm the whole unit's
# move. Deferred so the synthetic release from _drop_carry stages first — without
# the wait, pad_confirm_move could confirm before the just-placed model registers.
# A group drop stages through an async pipeline (per-model dispatch + verify /
# retry), so also wait for that to drain — confirming mid-pipeline would commit
# a half-staged unit. In the charge phase the same seam confirms the charge move
# (or, when models are still short of engagement, toasts what's left to do).
func _confirm_move_after_drop() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _await_group_drop_settled()
	if carry_active:
		return  # something re-armed a carry in between — don't confirm underneath it
	var mc := _movement_controller()
	if mc != null and mc.has_method("pad_confirm_move"):
		mc.pad_confirm_move()
	else:
		var cc := _charge_controller_any()
		if cc != null and cc.has_method("pad_primary_action"):
			cc.pad_primary_action()
	_update_hints()


# Wait (bounded) for MovementController's group-drop staging pipeline to finish.
func _await_group_drop_settled() -> void:
	for _i in range(180):  # ≤ ~3s — the pipeline itself is ~0.25s + 10ms/model
		var mc := _movement_controller()
		if mc == null or not mc.has_method("pad_group_drop_busy") or not mc.pad_group_drop_busy():
			return
		await get_tree().process_frame


func _cancel_carry() -> void:
	# Group carry cancel: nothing has moved yet (only ghosts ride the cursor),
	# so tear the drag down WITHOUT releasing over the board — releasing would
	# stage a zero/short move for every member. Abort first (group_dragging goes
	# false), then the queued synthetic release arrives as a no-op.
	if group_carry_active:
		var group_mc := _movement_controller()
		if group_mc != null and group_mc.has_method("pad_abort_group_drag"):
			group_mc.pad_abort_group_drag()
		VirtualCursor.set_left_button(false)
		carry_active = false
		group_carry_active = false
		VirtualCursor.park()
		return
	# The mouse-parity cancel: put the model back where it was picked up and
	# release (there is no dedicated drag-cancel in the mouse flow either).
	var unit_id := _carry_unit_id
	var staged_before := _movement_staged_count(unit_id)
	# Warp target: re-project the drag's authoritative world origin rather than
	# trusting the remembered screen point — edge-panning during the carry makes
	# that stale, and a release at a stale point stages a WRONG-position move.
	# For an unstaged model the count-check undo below would still rescue it,
	# but for a re-picked staged model the release REPLACES its stage in place
	# (count unchanged → no undo), silently corrupting the kept position.
	# Center the camera on the origin first so the projection is on-screen —
	# the cursor warp clamps to the viewport.
	var back_screen := _carry_pickup_screen
	var m := get_tree().current_scene
	var mc := _movement_controller()
	if mc != null and ("dragging_model" in mc) and mc.dragging_model \
			and ("drag_start_pos" in mc) and m != null and m.has_method("world_to_screen_position"):
		_center_camera_on_world(mc.drag_start_pos)
		back_screen = m.world_to_screen_position(mc.drag_start_pos)
	VirtualCursor.warp_to(back_screen)
	VirtualCursor.set_left_button(false)
	carry_active = false
	# Park (warp_to above re-activated the cursor) so the next A re-arms through
	# the router instead of firing as a stray click at the pickup point.
	VirtualCursor.park()
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
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m):
		return false
	if m.current_phase != GameStateData.Phase.MOVEMENT and m.current_phase != GameStateData.Phase.CHARGE:
		return false
	var ctrl = m.movement_controller if m.current_phase == GameStateData.Phase.MOVEMENT else m.charge_controller
	if ctrl == null or not is_instance_valid(ctrl) or str(ctrl.active_unit_id) == "":
		return false
	if carry_active:
		# Whole group in hand: there is no "other model" to swap to — every
		# unmoved model is already carried. Consume the paddle so it can't fall
		# through to another affordance.
		if group_carry_active:
			return true
		# Mid-carry hop (Movement + Charge): put the in-hand model back where it
		# was picked up — an un-dropped move reverts; a model already dropped
		# with A keeps its placed spot (movement's cancel count-check leaves
		# prior stages alone; a charge release at the pickup point fails the
		# ends-closer validation and reverts) — then hand the player the
		# prev/next model. The HINTS_CARRY "L3 Swap Model" chip shows in both
		# phases, so L3 must deliver in both.
		if _movement_controller() == null and _charge_controller_any() == null:
			return false
		var alive_c := _alive_model_count(_carry_unit_id)
		if alive_c <= 1:
			return true  # nothing to swap to — consume without a pointless regrab
		carry_model_index = wrapi(carry_model_index + dir, 0, alive_c)
		_swap_carry_to_index()
		return true
	if str(ctrl.active_unit_id) != _carry_unit_id:
		_carry_unit_id = str(ctrl.active_unit_id)
		carry_model_index = 0
	var alive := _alive_model_count(str(ctrl.active_unit_id))
	if alive == 0:
		return false
	carry_model_index = wrapi(carry_model_index + dir, 0, alive)
	var pos = _model_world_pos(str(ctrl.active_unit_id), carry_model_index)
	if pos != null:
		_center_camera_on_world(pos)
	return true


# Mid-carry paddle hop: cancel the live carry (reverting an un-staged model to
# its pickup spot), wait for the synthetic release + junk-stage undo to settle,
# then pick up the model now at carry_model_index. 3 frames: _cancel_carry's
# undo coroutine runs at frame 2, so frame 3 is safely after it — re-arming
# earlier would make that coroutine bail on its carry_active guard and leave
# the junk 0" stage in place. Serves Movement AND the charge move stage.
func _swap_carry_to_index() -> void:
	_cancel_carry()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if carry_active or PadActionBar.is_open():
		return  # something else re-claimed the pad mid-swap
	if get_viewport().gui_get_focus_owner() != null:
		return
	var mc = _movement_controller()
	if mc == null:
		mc = _charge_controller_any()
	if mc == null or str(mc.active_unit_id) == "" or str(mc.active_unit_id) != _carry_unit_id:
		return
	# The player is often still deflecting the stick when the paddle clicks,
	# which re-activates the parked cursor and would make _try_begin_carry bail.
	# The paddle press claimed this hop — park again and take the model.
	if VirtualCursor.is_cursor_active():
		VirtualCursor.park()
	if _try_begin_carry():
		_update_hints()


# Returns the world-space position (Vector2) of the unit's Nth alive model,
# or null when out of range. In the Movement phase a model that has already
# been dropped this move sits at its STAGED dest (GameState only updates on
# confirm), so prefer that — hopping to / picking up a staged model must land
# where its token visually is, not at its pre-move position.
func _model_world_pos(unit_id: String, alive_index: int):
	var roster := _unit_move_roster(unit_id)
	if alive_index < 0 or alive_index >= roster.size():
		return null
	var entry = roster[alive_index]
	var source_uid := str(entry.get("source_unit_id", unit_id))
	var model_id := str(entry.get("model_id", ""))
	# A model already dropped this move sits at its STAGED dest (GameState only
	# updates on confirm), so prefer that — hopping to / picking up a staged model
	# must land where its token visually is, not its pre-move position.
	var staged = _staged_model_pos_for(unit_id, source_uid, model_id)
	if staged != null:
		return staged
	var model := _roster_model(source_uid, model_id)
	var pos = model.get("position", null)
	if pos is Dictionary and pos.has("x"):
		return Vector2(float(pos.x), float(pos.y))
	elif pos is Vector2:
		return pos
	return null


# The model dict for source_uid's model_id, or {} when absent.
func _roster_model(source_uid: String, model_id: String) -> Dictionary:
	for model in GameState.get_unit(source_uid).get("models", []):
		if str(model.get("id", "")) == model_id:
			return model
	return {}


# The staged (uncommitted) destination of source_unit_id's model_id within the
# ACTIVE unit's move data, in the Movement phase, or null when it has no staged
# move / not in Movement. Attached-character models stage under the bodyguard's
# move (actor = active_unit_id) with model_source_unit_id set, so the move data
# is always the active unit's; source_unit_id disambiguates the colliding ids.
func _staged_model_pos_for(active_unit_id: String, source_unit_id: String, model_id: String):
	if model_id == "":
		return null
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or m.current_phase != GameStateData.Phase.MOVEMENT:
		return null
	var phase = PhaseManager.get_current_phase_instance()
	if phase == null or not phase.has_method("get_active_move_data"):
		return null
	var staged: Array = phase.get_active_move_data(active_unit_id).get("staged_moves", [])
	for i in range(staged.size() - 1, -1, -1):
		var sm = staged[i]
		if str(sm.get("model_id", "")) != model_id:
			continue
		if str(sm.get("model_source_unit_id", active_unit_id)) != source_unit_id:
			continue
		var dest = sm.get("dest")
		if dest is Vector2:
			return dest
		if dest is Array and dest.size() >= 2:
			return Vector2(float(dest[0]), float(dest[1]))
		return null
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

# True while a self-navigating menu modal (Save/Load dialog, …) is on screen.
# Such dialogs join the "pad_native_nav_modal" group and want Godot's native
# ui_* focus navigation, NOT this board router — see the guard in _input.
func _native_nav_modal_open() -> bool:
	for n in get_tree().get_nodes_in_group("pad_native_nav_modal"):
		if is_instance_valid(n) and n is CanvasItem and n.is_visible_in_tree():
			return true
	return false


func _enter_panel_focus() -> bool:
	if get_viewport().gui_get_focus_owner() != null:
		return false  # already navigating — let ui_* handle the press
	# Mid-move the pad lives on the board: while a model is in hand (movement /
	# charge carry) or the active unit's move session is locked (mode locked or
	# models staged, waiting on Start), those states advertise no D-pad
	# affordance in the hint bar and a stray press must not teleport focus into
	# the mouse panels, stranding the player out of the carry flow. Deliberate
	# panel work stays reachable via the virtual cursor; D-pad entry re-arms
	# the moment the move is confirmed or fully undone. The same stand-down
	# covers a committed charge (declared / rolling / moving into engagement).
	if carry_active or _movement_session_locked() or _charge_session_locked():
		return false
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


# Release GUI focus IF the owner lives inside one of the HUD panel subtrees
# (right panel / bottom bar). Dialog and popup focus is never touched — the
# InputDeviceManager dialog watcher depends on it for A-to-confirm. Returns
# true when focus was actually released.
func _release_panel_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	var m := get_tree().current_scene
	if m == null:
		return false
	for root_path in ["HUD_Right", "HUD_Bottom"]:
		var root := m.get_node_or_null(root_path)
		if root != null and (root == focused or root.is_ancestor_of(focused)):
			focused.release_focus()
			return true
	return false


func _find_first_focusable(root: Node) -> Control:
	var queue: Array = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		# ItemLists never take pad focus: lists are driven by their dedicated
		# affordances (LB/RB unit cycling, ▲ ▼ steppers) — focusing one would
		# turn ui_up/ui_down into unit cycling, the exact bug the bumper-only
		# rule exists to prevent. Text inputs (LineEdit/TextEdit) are skipped
		# too: the pad can't type into them, their focus styling is invisible,
		# and a focused text field silently disabled keyboard camera keys — the
		# "loaded a save, pressed D-pad, now nothing zooms" trap. The Deck's own
		# on-screen keyboard flow still works via cursor-click on the field.
		if n is Control and not (n is ItemList) and not (n is LineEdit) and not (n is TextEdit) \
				and n.focus_mode == Control.FOCUS_ALL \
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
			# Text inputs leave the pad focus chain along with ItemLists: the pad
			# cannot type into them, their focus styling is invisible, and a
			# focused text field silently disabled the keyboard camera keys (the
			# "loaded a save, pressed D-pad, now nothing zooms" trap). FOCUS_CLICK
			# keeps mouse / virtual-cursor click focus working for KBM and for
			# deliberate pad clicks (Deck OSK flow).
			if n is ItemList or n is LineEdit or n is TextEdit:
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


# Public seam for phase controllers (shooting auto-select, …): frame the
# camera on unit_id, but ONLY while the pad is the active device. Automatic
# camera jumps are hostile to mouse players — they can already see what they
# clicked — so KBM callers are a no-op.
func follow_unit_if_pad(unit_id: String) -> void:
	if unit_id == "" or not InputDeviceManager.is_pad_active():
		return
	_center_camera_on_unit(unit_id)


# Below this zoom the board is a fit-whole-table overview (a loaded save starts
# at ~0.3) and individual models are unreadable — cycling to a unit there must
# zoom IN on it, not just pan the overview sideways.
const CYCLE_FRAME_MIN_ZOOM := 0.5

func _center_camera_on_unit(unit_id: String) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	# Zoomed far out (e.g. right after loading a save): frame the cycled unit
	# properly — fit_view_to_selection centers AND zooms to its bounding box —
	# so bumper-cycling is usable without ever touching the zoom triggers. At
	# normal zoom keep the player's chosen zoom and just pan (as before).
	var m := get_tree().current_scene
	if m != null and ("view_zoom" in m) and float(m.view_zoom) < CYCLE_FRAME_MIN_ZOOM \
			and m.has_method("fit_view_to_selection"):
		if m.fit_view_to_selection(unit_id):
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
		if group_carry_active:
			hints = HINTS_CARRY_GROUP
		else:
			# Movement carries advertise the multi-step X (Finish Model) + Grab All;
			# charge carries keep the plain set (no per-model advance, no group grab).
			hints = HINTS_CARRY_MOVE if _movement_controller() != null else HINTS_CARRY
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
			var cc = _charge_controller_any()
			if cc != null:
				# Stage-accurate charge hints: the ☰ chip always names exactly
				# what Start will do in the current state (End Phase / Declare
				# Charge / Roll 2D6 / Confirm Charge), so the promise can never
				# diverge from the action again.
				if bool(cc.awaiting_movement):
					hints = HINTS_CHARGE_MOVE
				elif bool(cc.awaiting_roll):
					hints = HINTS_CHARGE_ROLL
				elif cc.selected_targets.size() > 0:
					hints = HINTS_CHARGE_READY
				else:
					hints = HINTS_CHARGE_SELECT
			elif _movement_menu_available():
				hints = HINTS_MOVE
			elif _movement_session_locked():
				# Mid-move with models still to place = the multi-step state
				# (A re-picks the dropped model, X advances); all placed = the
				# locked state waiting on Start.
				hints = HINTS_MOVE_STAGED if _movement_has_unplaced_models() else HINTS_MOVE_LOCKED
	PadHintBar.set_hints(hints)


# Public seam: phase controllers call this when their state changes outside a
# pad press (async declare/roll/resolve signals), so the hint bar re-renders
# from live state instead of going stale until the next button press.
func refresh_hints() -> void:
	_update_hints()


# The MovementController while the Movement phase is live, else null. Used by the
# bumper lock, the drop-rejection check and the locked-session hint so each reads
# the same authoritative move state.
func _movement_controller() -> Node:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or m.current_phase != GameStateData.Phase.MOVEMENT:
		return null
	if not ("movement_controller" in m):
		return null
	var mc = m.movement_controller
	if mc == null or not is_instance_valid(mc):
		return null
	return mc


# True while the active unit has a committed move (mode locked or a model staged)
# — the state where the bumpers are locked and the locked-session hints apply.
func _movement_session_locked() -> bool:
	var mc := _movement_controller()
	return mc != null and mc.has_method("pad_is_move_session_locked") and mc.pad_is_move_session_locked()


# True while the active movement unit still has at least one alive model with
# no staged destination — the multi-step state where X ("Next Model") has
# somewhere to advance to.
func _movement_has_unplaced_models() -> bool:
	var mc := _movement_controller()
	if mc == null or str(mc.active_unit_id) == "":
		return false
	var unit_id := str(mc.active_unit_id)
	for entry in _unit_move_roster(unit_id):
		if _roster_entry_staged_pos(unit_id, entry) == null:
			return true
	return false


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


# The ChargeController while the charge phase is live with a unit selected —
# ANY stage (picking targets, awaiting the roll, or moving models), else null.
func _charge_controller_any() -> Node:
	var m := get_tree().current_scene
	if m == null or not ("current_phase" in m) or not ("charge_controller" in m):
		return null
	if m.current_phase != GameStateData.Phase.CHARGE:
		return null
	var cc = m.charge_controller
	if cc == null or not is_instance_valid(cc):
		return null
	if str(cc.active_unit_id) == "":
		return null
	return cc


# The ChargeController while the charge phase is live with a unit selected
# and its charge not yet being moved (declaration / roll stage), else null.
func _charge_controller_selecting() -> Node:
	var cc := _charge_controller_any()
	if cc == null or bool(cc.awaiting_movement):
		return null
	return cc


# True while the selected unit's charge is committed (declared / rolling /
# moving) — the state where bumper cycling and panel-focus entry stand down,
# mirroring the movement phase's locked-session guards.
func _charge_session_locked() -> bool:
	var cc := _charge_controller_any()
	return cc != null and cc.has_method("pad_is_charge_locked") and cc.pad_is_charge_locked()
