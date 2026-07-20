extends PhaseControllerBase
class_name ChargeController

const GameStateData = preload("res://autoloads/GameState.gd")
const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# Floating-point tolerance for distance cap checks (< 1px)
const MOVEMENT_CAP_EPSILON: float = 0.02

# ChargeController - Handles UI interactions for the Charge Phase
# Manages charge declarations, target selection, dice rolling, and movement validation

signal charge_action_requested(action: Dictionary)
signal charge_preview_updated(unit_id: String, target_ids: Array, valid: bool)
signal ui_update_requested()

# Charge state
var current_phase = null  # Can be ChargePhase or null
var active_unit_id: String = ""
var eligible_targets: Dictionary = {}  # target_unit_id -> target_data
var selected_targets: Array = []
var charge_distance: int = 0
var awaiting_roll: bool = false
var awaiting_movement: bool = false
var last_processed_charge_roll: Dictionary = {}  # Tracks last processed roll to prevent duplicates
var _pending_complete_unit_id: String = ""  # Unit awaiting COMPLETE_UNIT_CHARGE after charge_resolved
var pending_ability_reroll_name: String = ""  # Ability granting the current free charge reroll (e.g. "Swift Onslaught") — used in dice-log copy
var _last_apply_rejection: Dictionary = {}  # Set by Main via on_charge_move_rejected when APPLY_CHARGE_MOVE fails validation

# Charge movement tracking
#
# KEYING: an Attached unit charges as ONE unit, so its attached CHARACTER models
# (e.g. a Blade Champion leading Custodian Guard) are draggable alongside the
# bodyguard's own models. Model ids collide between the two units (both use
# "m1", "m2", …), so every dictionary/array below is keyed by a *charge key*:
#   - bodyguard model:            "m3"                  (bare model id)
#   - attached character model:   "<char_unit_id>:m1"   (composite)
# The same keys are sent to ChargePhase inside per_model_paths — the phase
# resolves them via _resolve_charge_path_ref. Use _charge_model_key /
# _charge_key_parts to convert between (unit_id, model_id) and keys.
var models_to_move: Array = []  # Models that still need to move
var moved_models: Dictionary = {}  # charge key -> new_position
# T-092: per-model undo state for charge pile-in
var _moved_model_order: Array = []  # Order in which models were moved (for last-undone)
var _model_origin_positions: Dictionary = {}  # charge key -> Vector2 pre-charge position
var _model_origin_rotations: Dictionary = {}  # charge key -> float pre-charge rotation
# Multi-step charge movement (mirrors the Movement phase): a charging model may be
# dragged in several hops around terrain/obstacles, each hop adding to the total
# distance until the charge roll is spent or the move is confirmed. This holds the
# full waypoint list (origin first) per model so (a) the accumulated distance is
# capped against the charge roll and (b) the real multi-segment polyline is sent to
# ChargePhase for terrain-aware validation instead of a straight line that could cut
# back through terrain the player carefully routed around.
var _model_charge_paths: Dictionary = {}  # charge key -> Array[Vector2] waypoints incl. origin
var undo_charge_model_button: Button = null
var auto_path_charge_button: Button = null  # T-092: auto-suggests valid charge positions
# T-092: Snap-to-contact fallback sweep — approach-direction offsets (degrees)
# tried in order when the straight-line spot is blocked (e.g. by a squadmate
# already snapped to the same target). Most direct placement wins.
const SNAP_ANGLE_SWEEP_DEG: Array = [
	0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 75.0, -75.0,
	90.0, -90.0, 105.0, -105.0, 120.0, -120.0, 135.0, -135.0, 150.0, -150.0,
	165.0, -165.0, 180.0,
]
var dragging_model = null  # Currently dragging model
# Unit the dragging model belongs to: the charging unit itself, or one of its
# attached character units. Kept OUTSIDE dragging_model — that dict is a live
# GameState reference and must not grow controller-only keys.
var dragging_model_source_unit_id: String = ""
var ghost_visual: Node2D = null  # Ghost visual for dragging
var movement_lines: Dictionary = {}  # charge key -> Line2D for movement path

# Multi-select state (mirrors the Movement phase UX): Shift+drag on empty board
# rubber-bands a box over the charging unit's models, Ctrl+click toggles single
# models, Ctrl+A selects all — then dragging any selected model moves the whole
# group as one, with each model's move validated against the charge roll.
var selected_models: Array = []  # entries: {model_id: String, position: Vector2}
var drag_box_active: bool = false
var drag_box_start: Vector2 = Vector2.ZERO  # board-local
var drag_box_end: Vector2 = Vector2.ZERO  # board-local
var selection_box_visual: Node2D = null  # drawn rect while shift-dragging
var selection_indicators: Array = []  # pulsing rings on selected models
var group_dragging: bool = false
var group_drag_start_pos: Vector2 = Vector2.ZERO  # board-local point where the group drag began
var group_drag_start_positions: Dictionary = {}  # model_id -> Vector2 at drag start
var group_ghost_container: Node2D = null  # ghost previews for the group drag
var confirm_button: Button = null  # Button to confirm charge moves
var charge_direction_visual: Node2D = null  # P3-99: Live direction validation feedback

# Base-to-base snap state
var snap_active: bool = false  # Whether snap is currently engaged
var snap_position: Vector2 = Vector2.ZERO  # The snapped base-to-base position
var snap_target_model_id: String = ""  # Which enemy model we're snapped to
const SNAP_ZONE_INCHES: float = 1.5  # How close (beyond base contact) to trigger snap
const SNAP_BREAK_INCHES: float = 2.0  # How far to drag away from snap point to break out
var target_engagement_visuals: Array = []  # Engagement range circles around charge targets

# UI References (board_view / hud_bottom / hud_right live in PhaseControllerBase)
var charge_line_visual: Line2D
var range_visual: Node2D
var target_highlights: Node2D

# T7-58: Charge arrow visuals - animated arrows from charger to targets
var charge_arrow_visuals: Array = []  # Array of ChargeArrowVisual instances

# P3-127: Charge trajectory preview - shows expected charge paths during target selection
var charge_trajectory_preview: ChargeTrajectoryPreview = null

# Pre-roll charge threat envelope (union of every alive model's 12" reach) in
# world-space px. Kept as members (not locals) so windowed scenarios can assert
# the drawn geometry directly instead of walking the dash nodes in range_visual.
var charge_threat_outlines: Array = []  # Array of PackedVector2Array, one per boundary loop
var charge_threat_bounds: Rect2 = Rect2()  # bounding box over all loops (also anchors the label)

# UI Elements
var unit_selector: ItemList
var target_list: ItemList
var target_hint_label: RichTextLabel  # Teaches click-vs-Ctrl+Click target selection under the target list
var charge_requirement_label: RichTextLabel  # Option 2: pre-roll "needs 2D6 >= N to reach ALL targets" hint
var charge_info_label: Label
var charge_distance_label: Label
var charge_used_label: Label
var charge_left_label: Label
var charge_terrain_label: Label  # P3-98: Shows terrain penalty breakdown
var declare_button: Button
var roll_button: Button
var skip_button: Button
var next_unit_button: Button
var charge_status_label: Label
var dice_log_display: RichTextLabel
var dice_roll_visual: DiceRollVisual  # T5-V1: Animated dice roll visualization
var failed_charges_container: VBoxContainer  # Container for failed charge tooltip entries

# Visual settings
const HIGHLIGHT_COLOR_ELIGIBLE = Color.GREEN
const HIGHLIGHT_COLOR_SELECTED = Color.YELLOW
const CHARGE_LINE_COLOR = Color.ORANGE
const CHARGE_LINE_WIDTH = 3.0
const RANGE_CIRCLE_COLOR = Color(1.0, 0.5, 0.0, 0.3)

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	_setup_ui_references()
	_create_charge_visuals()
	print("ChargeController ready")

func _exit_tree() -> void:
	# Clean up visual elements
	if charge_line_visual and is_instance_valid(charge_line_visual):
		charge_line_visual.queue_free()
	if range_visual and is_instance_valid(range_visual):
		range_visual.queue_free()
	if target_highlights and is_instance_valid(target_highlights):
		target_highlights.queue_free()
	_clear_charge_arrow_visuals()  # T7-58
	_clear_charge_trajectory_preview()  # P3-127
	_clear_movement_visuals()
	
	# Clean up bottom HUD elements (End Charge Phase button and related)
	var hud_bottom = SceneRefs.hud_bottom()
	if hud_bottom:
		var main_container = hud_bottom.get_node_or_null("HBoxContainer")
		if main_container and is_instance_valid(main_container):
			# Main.gd now handles phase action button cleanup
			
			# Remove any spacer controls we added
			for child in main_container.get_children():
				if child is Control and not (child is Button or child is Label or child is VSeparator):
					if child.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
						main_container.remove_child(child)
						child.queue_free()
	
	# ENHANCEMENT: Comprehensive right panel cleanup
	var container = SceneRefs.hud_right_vbox()
	if container and is_instance_valid(container):
		var charge_elements = ["ChargePanel", "ChargeScrollContainer", "ChargeActions"]
		for element in charge_elements:
			var node = container.get_node_or_null(element)
			if node and is_instance_valid(node):
				print("ChargeController: Removing element: ", element)
				container.remove_child(node)
				node.queue_free()

# ISS-008: deliberately _input (not _unhandled_input) — the charge-move
# confirm button is hit-tested at input level so confirming works even while
# overlays/dialogs hold GUI focus. Guarded by awaiting_movement.
func _input(event: InputEvent) -> void:
	if not awaiting_movement:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Let the charge-panel action buttons (Confirm / Undo Last Model /
			# Snap to Contact) receive their own clicks. The
			# get_viewport().set_input_as_handled() below marks this press handled
			# BEFORE Godot's GUI pass runs, so any charge-panel button sitting
			# under the cursor would never fire its `pressed` signal and the click
			# would silently do nothing. Originally only confirm_button was
			# whitelisted here — that is why "Undo Last Model" appeared dead when a
			# player clicked it (and why "Snap to Contact" only worked via the
			# test's emit_pressed shortcut, not a real mouse click).
			for panel_button in [confirm_button, undo_charge_model_button, auto_path_charge_button]:
				if is_instance_valid(panel_button) and panel_button.visible:
					if panel_button.get_global_rect().has_point(mouse_event.global_position):
						print("DEBUG: Click is within a charge-panel button, not handling")
						return  # Let the button handle this click

			print("DEBUG: ChargeController _input - Left mouse button, pressed: ", mouse_event.pressed)
			if mouse_event.pressed:
				_handle_mouse_down(mouse_event.global_position)
			else:
				_handle_mouse_release(mouse_event.global_position)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and (dragging_model or drag_box_active or group_dragging):
		_handle_mouse_motion(event.global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		# MA-41: Skip keyboard input when a text input has focus
		var focused = get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
		# Keyboard rotation controls during charge movement
		if event.pressed and dragging_model:
			if KeybindingManager.matches_action(event, "rotate_left"):
				_rotate_dragging_model(-PI/12)  # Rotate 15 degrees left
				get_viewport().set_input_as_handled()
			elif KeybindingManager.matches_action(event, "rotate_right"):
				_rotate_dragging_model(PI/12)  # Rotate 15 degrees right
				get_viewport().set_input_as_handled()
		elif event.pressed and not dragging_model:
			# Multi-selection keyboard shortcuts (mirrors the Movement phase)
			if KeybindingManager.matches_action(event, "select_all"):
				_select_all_charge_models()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE and selected_models.size() > 0:
				_clear_charge_selection()
				get_viewport().set_input_as_handled()

func _handle_mouse_down(global_pos: Vector2) -> void:
	print("DEBUG: Mouse down at global pos: ", global_pos)
	var board_root = SceneRefs.board_root()

	# Shift+press on empty board space starts drag-box multi-selection of the
	# charging unit's models (mirrors the Movement phase multi-select UX).
	# Pressing ON a model with Shift held falls through to a normal drag.
	if Input.is_key_pressed(KEY_SHIFT) and _find_draggable_charge_model_at(global_pos).is_empty():
		if board_root:
			_start_drag_box_selection(board_root.to_local(global_pos))
		return

	# Ctrl+click toggles a single charging model in/out of the multi-selection
	if Input.is_key_pressed(KEY_CTRL):
		_toggle_charge_model_selection(global_pos)
		return

	print("DEBUG: Models to move: ", models_to_move)
	var hit = _find_draggable_charge_model_at(global_pos)

	# Clicking one of the selected models while 2+ are selected drags the group
	if selected_models.size() > 1 and not hit.is_empty() \
			and _find_selected_charge_model_index(hit.get("model_id", "")) >= 0:
		if board_root:
			_start_group_drag(board_root.to_local(global_pos))
		return

	# Any other press clears the multi-selection and behaves as before
	if selected_models.size() > 0:
		_clear_charge_selection()

	if hit.is_empty():
		print("DEBUG: No model found at click position")
		return

	var model = hit.model
	var model_id = hit.model_id
	# Source unit of the picked model: the charging unit, or one of its attached
	# character units (a Blade Champion attached to Custodian Guard). Kept so the
	# whole drag/confirm path writes to the right unit and uses the right charge key.
	dragging_model_source_unit_id = hit.get("unit_id", active_unit_id)
	print("DEBUG: Clicked on model ", _charge_model_key(dragging_model_source_unit_id, model_id))

	# Log the complete model data from GameState
	print("DEBUG: Model data from GameState:")
	print("  id: ", model.get("id", "NOT SET"))
	print("  base_mm: ", model.get("base_mm", "NOT SET"))
	print("  base_type: ", model.get("base_type", "NOT SET"))
	print("  base_dimensions: ", model.get("base_dimensions", "NOT SET"))
	print("  rotation: ", model.get("rotation", "NOT SET"))
	print("  position: ", model.get("position", "NOT SET"))
	print("  Full model keys: ", model.keys())

	dragging_model = model
	# Convert token position to BoardRoot local coordinates
	if board_root:
		var local_pos = board_root.to_local(hit.token_global_pos)
		_start_model_drag(model, local_pos)

func _find_draggable_charge_model_at(global_pos: Vector2) -> Dictionary:
	"""Hit-test the charging unit's draggable tokens at a global screen position.
	Draggable = still to move OR already placed (multi-step pickups). Returns
	{model_id, token_global_pos, model} or {} when nothing draggable is there.
	The test runs in BOARD space against each model's real base radius — a
	fixed screen-px radius balloons at zoomed-out camera scales (25.2 screen px
	at the default fitted zoom is >2\" of board!), which both made fat-finger
	pickups of the wrong model possible and left no 'empty board' anywhere near
	the unit for the Shift+drag-box gesture to start on."""
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		print("DEBUG: TokenLayer not found")
		return {}
	var board_root = SceneRefs.board_root()
	var board_pos: Vector2 = board_root.to_local(global_pos) if board_root else global_pos
	var grab_margin_px := 4.0  # small forgiveness ring around the base edge

	# The charge group: the charging unit itself plus its attached character
	# units (a Blade Champion attached to Custodian Guard drags with the squad).
	var group_unit_ids: Array = [active_unit_id]
	group_unit_ids.append_array(_get_attached_character_ids())

	# Scan every pickable token and keep the NEAREST hit, so tightly packed
	# formations resolve to the model actually under the cursor.
	var best_child = null
	var best_unit_id := ""
	var best_model_id := ""
	var best_distance := INF
	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or not child.has_meta("model_id"):
			continue

		var unit_id = str(child.get_meta("unit_id"))
		var model_id = str(child.get_meta("model_id"))

		# Check if this is a model of the charge group we can move. Multi-step:
		# a model that has already been placed (in moved_models) can be picked up
		# again to continue its move around terrain until the charge distance is
		# spent or the move is confirmed — not just models still at their origin.
		if unit_id not in group_unit_ids:
			continue
		var charge_key = _charge_model_key(unit_id, model_id)
		if charge_key not in models_to_move and charge_key not in moved_models:
			continue

		# Board-local token position (TokenLayer sits at the BoardRoot origin).
		# Nearest-wins so tightly packed formations resolve to the model actually
		# under the cursor (a fixed screen-px radius mis-picked when zoomed).
		var token_board_pos: Vector2 = child.position
		var base_radius := 25.2
		if child.has_method("get_base_radius"):
			base_radius = child.get_base_radius()
		elif child.has_meta("base_mm"):
			base_radius = Measurement.base_radius_px(child.get_meta("base_mm"))

		var distance = token_board_pos.distance_to(board_pos)
		print("DEBUG: Token ", charge_key, " at board ", token_board_pos, " distance from click: ", distance, " (radius ", base_radius, ")")

		if distance <= base_radius + grab_margin_px and distance < best_distance:
			best_child = child
			best_unit_id = unit_id
			best_model_id = model_id
			best_distance = distance

	if best_child != null:
		# Get the model data from GameState (from the model's OWN unit — an
		# attached character model lives in the character's unit entry, not the
		# bodyguard's)
		var unit = GameState.get_unit(best_unit_id)
		for model in unit.get("models", []):
			if model.get("id", "") == best_model_id:
				return {"model_id": best_model_id, "unit_id": best_unit_id, "token_global_pos": best_child.global_position, "model": model}

	return {}

func _handle_mouse_motion(global_pos: Vector2) -> void:
	# Convert global position to BoardRoot local coordinates
	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	var local_pos = board_root.to_local(global_pos)

	if drag_box_active:
		_update_drag_box_selection(local_pos)
		return
	if group_dragging:
		_update_group_drag(local_pos)
		return
	if not dragging_model:
		return
	_update_model_drag(local_pos)

func _handle_mouse_release(global_pos: Vector2) -> void:
	# Convert global position to BoardRoot local coordinates
	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	var local_pos = board_root.to_local(global_pos)

	if drag_box_active:
		_complete_drag_box_selection(local_pos)
		return
	if group_dragging:
		_end_group_drag(local_pos)
		return
	if not dragging_model:
		return
	_end_model_drag(local_pos)

# ============================================================================
# MULTI-SELECT + GROUP DRAG (charge movement) — mirrors the Movement phase:
# Shift+drag box / Ctrl+click / Ctrl+A select several charging models, then
# dragging any selected model moves the whole group by the same offset. Each
# model's hop is validated like a single drag (accumulated distance vs the
# charge roll, overlaps, board edge, ends-closer-to-target).
# ============================================================================

func _get_gamestate_model(model_id: String) -> Dictionary:
	"""Live model dict for the charging unit from GameState (current staged position)."""
	var unit = GameState.get_unit(active_unit_id)
	for model in unit.get("models", []):
		if model.get("id", "") == model_id:
			return model
	return {}

func _is_model_draggable_for_charge(model_id: String) -> bool:
	return model_id in models_to_move or model_id in moved_models

func _find_selected_charge_model_index(model_id: String) -> int:
	for i in range(selected_models.size()):
		if selected_models[i].get("model_id", "") == model_id:
			return i
	return -1

func _toggle_charge_model_selection(global_pos: Vector2) -> void:
	"""Ctrl+click: add/remove a charging model from the multi-selection."""
	var hit = _find_draggable_charge_model_at(global_pos)
	if hit.is_empty():
		return
	var model_id: String = hit.model_id
	var idx = _find_selected_charge_model_index(model_id)
	if idx >= 0:
		selected_models.remove_at(idx)
		print("ChargeController: Deselected model ", model_id)
	else:
		selected_models.append({"model_id": model_id, "position": _get_model_position(hit.model)})
		print("ChargeController: Selected model ", model_id, " (", selected_models.size(), " selected)")
	_update_charge_selection_visuals()

func _select_all_charge_models() -> void:
	"""Ctrl+A: select every draggable model of the charging unit."""
	if active_unit_id == "" or not awaiting_movement:
		return
	_clear_charge_selection()
	var unit = GameState.get_unit(active_unit_id)
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var model_id = model.get("id", "")
		if not _is_model_draggable_for_charge(model_id):
			continue
		selected_models.append({"model_id": model_id, "position": _get_model_position(model)})
	_update_charge_selection_visuals()
	print("ChargeController: Selected all ", selected_models.size(), " charging models")

func _clear_charge_selection() -> void:
	selected_models.clear()
	_clear_selection_indicators()

func _clear_selection_indicators() -> void:
	for indicator in selection_indicators:
		if indicator and is_instance_valid(indicator):
			indicator.queue_free()
	selection_indicators.clear()

func _update_charge_selection_visuals() -> void:
	"""Redraw the pulsing selection rings on the currently selected models."""
	_clear_selection_indicators()
	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	for entry in selected_models:
		var model = _get_gamestate_model(entry.get("model_id", ""))
		if model.is_empty():
			continue
		var pos = _get_model_position(model)
		entry["position"] = pos
		var indicator = _SelectionRingIndicator.new()
		indicator.position = pos
		indicator.ring_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		board_root.add_child(indicator)
		selection_indicators.append(indicator)

func _start_drag_box_selection(local_pos: Vector2) -> void:
	drag_box_active = true
	drag_box_start = local_pos
	drag_box_end = local_pos
	var board_root = SceneRefs.board_root()
	if not selection_box_visual or not is_instance_valid(selection_box_visual):
		selection_box_visual = _SelectionBoxVisual.new()
		selection_box_visual.name = "ChargeMultiSelectionBox"
		if board_root:
			board_root.add_child(selection_box_visual)
	selection_box_visual.visible = false  # shown once the box has some size
	print("ChargeController: Started drag-box selection at ", local_pos)

func _update_drag_box_selection(local_pos: Vector2) -> void:
	if not drag_box_active:
		return
	drag_box_end = local_pos
	_update_drag_box_visual()

func _update_drag_box_visual() -> void:
	if not selection_box_visual or not is_instance_valid(selection_box_visual):
		return
	var min_pos = Vector2(min(drag_box_start.x, drag_box_end.x), min(drag_box_start.y, drag_box_end.y))
	var max_pos = Vector2(max(drag_box_start.x, drag_box_end.x), max(drag_box_start.y, drag_box_end.y))
	var box_size = max_pos - min_pos
	if box_size.length() > 10.0:
		selection_box_visual.position = min_pos
		selection_box_visual.box_size = box_size
		selection_box_visual.visible = true
		selection_box_visual.queue_redraw()
		# Live preview of which models the box would select
		_update_drag_box_preview(min_pos, max_pos)
	else:
		selection_box_visual.visible = false
		_clear_selection_indicators()

func _update_drag_box_preview(min_pos: Vector2, max_pos: Vector2) -> void:
	_clear_selection_indicators()
	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	for model_id in _draggable_charge_model_ids_in_box(min_pos, max_pos):
		var model = _get_gamestate_model(model_id)
		if model.is_empty():
			continue
		var indicator = _SelectionRingIndicator.new()
		indicator.position = _get_model_position(model)
		indicator.ring_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		board_root.add_child(indicator)
		selection_indicators.append(indicator)

func _complete_drag_box_selection(local_pos: Vector2) -> void:
	if not drag_box_active:
		return
	drag_box_end = local_pos
	drag_box_active = false
	if selection_box_visual and is_instance_valid(selection_box_visual):
		selection_box_visual.visible = false

	var min_pos = Vector2(min(drag_box_start.x, drag_box_end.x), min(drag_box_start.y, drag_box_end.y))
	var max_pos = Vector2(max(drag_box_start.x, drag_box_end.x), max(drag_box_start.y, drag_box_end.y))

	_clear_charge_selection()
	for model_id in _draggable_charge_model_ids_in_box(min_pos, max_pos):
		var model = _get_gamestate_model(model_id)
		if model.is_empty():
			continue
		selected_models.append({"model_id": model_id, "position": _get_model_position(model)})
	_update_charge_selection_visuals()

	if is_instance_valid(charge_info_label) and selected_models.size() > 1:
		charge_info_label.text = "%d models selected — drag any of them to move the group" % selected_models.size()
	print("ChargeController: Drag-box selected ", selected_models.size(), " models")

func _draggable_charge_model_ids_in_box(min_pos: Vector2, max_pos: Vector2) -> Array:
	"""Model ids of the charging unit inside a board-local rect, draggable ones only.
	Uses GameState positions — during charge staging they match the token visuals."""
	var ids: Array = []
	if active_unit_id == "":
		return ids
	var unit = GameState.get_unit(active_unit_id)
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var model_id = model.get("id", "")
		if not _is_model_draggable_for_charge(model_id):
			continue
		var pos = _get_model_position(model)
		if pos.x >= min_pos.x and pos.x <= max_pos.x and pos.y >= min_pos.y and pos.y <= max_pos.y:
			ids.append(model_id)
	return ids

func _start_group_drag(local_pos: Vector2) -> void:
	if selected_models.is_empty():
		return
	print("ChargeController: Starting group drag with ", selected_models.size(), " models")
	group_dragging = true
	group_drag_start_pos = local_pos
	group_drag_start_positions.clear()
	for entry in selected_models:
		var model = _get_gamestate_model(entry.get("model_id", ""))
		if model.is_empty():
			continue
		group_drag_start_positions[entry.model_id] = _get_model_position(model)
	# Rings would lag behind the drag — hide them; the ghosts preview the move
	_clear_selection_indicators()
	_create_group_ghost_visuals()

func _create_group_ghost_visuals() -> void:
	_clear_group_ghost_visuals()
	var board_root = SceneRefs.board_root()
	if not board_root:
		return
	group_ghost_container = Node2D.new()
	group_ghost_container.name = "ChargeGroupGhost"
	board_root.add_child(group_ghost_container)
	var unit = GameState.get_unit(active_unit_id)
	for entry in selected_models:
		var model = _get_gamestate_model(entry.get("model_id", ""))
		if model.is_empty():
			continue
		var ghost_token = preload("res://scripts/GhostVisual.gd").new()
		ghost_token.owner_player = unit.get("owner", 1)
		ghost_token.set_model_data(model)
		if model.has("rotation"):
			ghost_token.set_base_rotation(model.get("rotation", 0.0))
		ghost_token.position = group_drag_start_positions.get(entry.model_id, Vector2.ZERO)
		ghost_token.set_meta("model_id", entry.model_id)
		group_ghost_container.add_child(ghost_token)
	group_ghost_container.modulate = Color(0, 1, 0, 0.7)  # Green like the single-drag ghost

func _clear_group_ghost_visuals() -> void:
	if group_ghost_container and is_instance_valid(group_ghost_container):
		group_ghost_container.queue_free()
	group_ghost_container = null

func _update_group_drag(local_pos: Vector2) -> void:
	if not group_dragging:
		return
	var drag_vector = local_pos - group_drag_start_pos
	var validation = _validate_group_charge_move(drag_vector)

	# Move the ghosts, keeping formation
	if group_ghost_container and is_instance_valid(group_ghost_container):
		for child in group_ghost_container.get_children():
			var model_id = child.get_meta("model_id", "")
			var start_pos: Vector2 = group_drag_start_positions.get(model_id, Vector2.ZERO)
			child.position = start_pos + drag_vector
		group_ghost_container.modulate = Color(0, 1, 0, 0.7) if validation.valid else Color(1, 0, 0, 0.7)

	# Worst-case Used/Left across the group against the charge roll
	_update_charge_distance_display_with_preview(validation.max_total_inches, validation.valid, 0.0)

func _end_group_drag(local_pos: Vector2) -> void:
	if not group_dragging:
		return
	group_dragging = false
	var drag_vector = local_pos - group_drag_start_pos
	var validation = _validate_group_charge_move(drag_vector)
	_clear_group_ghost_visuals()

	if not validation.valid:
		print("ChargeController: Group charge move invalid - ", validation.reason)
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Invalid group move! %s" % validation.reason
		# Nothing moved yet — just restore the selection rings
		group_drag_start_positions.clear()
		_update_charge_selection_visuals()
		return

	# Commit every model exactly like a single-model drop
	var max_total := 0.0
	for entry in selected_models:
		var model_id: String = entry.get("model_id", "")
		var model = _get_gamestate_model(model_id)
		if model.is_empty() or not group_drag_start_positions.has(model_id):
			continue
		var start_pos: Vector2 = group_drag_start_positions[model_id]
		var final_pos: Vector2 = start_pos + drag_vector

		# Multi-step: append this hop's endpoint to the model's recorded path so
		# accumulated distance and the real polyline survive to the confirm.
		var hop_path: Array = _model_charge_paths.get(model_id, [])
		if hop_path.is_empty():
			hop_path = [start_pos]
		hop_path.append(final_pos)
		_model_charge_paths[model_id] = hop_path
		max_total = max(max_total, _get_model_charge_accumulated(model_id))

		var model_rotation: float = model.get("rotation", 0.0)
		moved_models[model_id] = {
			"position": final_pos,
			"rotation": model_rotation
		}
		# T-092: track ordering for per-model undo
		if model_id in _moved_model_order:
			_moved_model_order.erase(model_id)
		_moved_model_order.append(model_id)

		# GameState first, then the token visual (same order as _end_model_drag)
		_update_model_position_in_gamestate(active_unit_id, model_id, final_pos)
		_move_token_visual(active_unit_id, model_id, final_pos, model_rotation)
		models_to_move.erase(model_id)
		entry["position"] = final_pos

	group_drag_start_positions.clear()
	print("ChargeController: Group drag committed ", selected_models.size(), " models (max used %.1f\")" % max_total)

	# Worst-case accumulated distance across the group
	_update_charge_distance_display_with_preview(max_total, true, 0.0)

	# Same button/info bookkeeping as a single-model drop
	if moved_models.size() > 0 and is_instance_valid(confirm_button):
		confirm_button.disabled = false
	if undo_charge_model_button and is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.disabled = _moved_model_order.is_empty()
	if is_instance_valid(charge_info_label):
		charge_info_label.text = _remaining_models_message()

	# Keep the selection (rings at the new positions) so the player can keep
	# nudging the same group in further hops until the charge roll is spent.
	_update_charge_selection_visuals()

func _validate_group_charge_move(drag_vector: Vector2) -> Dictionary:
	"""Validate every selected model at (current position + drag_vector).
	Group-aware: squadmates in the selection are tested against their PROSPECTIVE
	positions so a tight formation doesn't false-collide with spots its own
	members are vacating. Returns {valid, reason, max_total_inches}."""
	var group_new_positions: Dictionary = {}
	for entry in selected_models:
		var model = _get_gamestate_model(entry.get("model_id", ""))
		if model.is_empty():
			continue
		group_new_positions[entry.model_id] = _get_model_position(model) + drag_vector

	var all_valid := true
	var reason := ""
	var max_total := 0.0
	for entry in selected_models:
		var model_id: String = entry.get("model_id", "")
		var model = _get_gamestate_model(model_id)
		if model.is_empty() or not group_new_positions.has(model_id):
			continue
		var new_pos: Vector2 = group_new_positions[model_id]
		var old_pos: Vector2 = _get_model_position(model)
		var hop_inches = Measurement.px_to_inches(old_pos.distance_to(new_pos)) \
			+ _calculate_terrain_penalty_for_path(old_pos, new_pos)
		max_total = max(max_total, _get_model_charge_accumulated(model_id) + hop_inches)
		# Group multi-select drags the charging unit's own models, so the charge
		# key is the bare model_id; pass the group overrides as the 4th arg.
		if all_valid and not _validate_charge_position(model, new_pos, model_id, group_new_positions):
			all_valid = false
			reason = "Model %s: must stay within %d\" and end closer to a target" % [model_id, charge_distance]
	return {"valid": all_valid, "reason": reason, "max_total_inches": max_total}

func _create_charge_visuals() -> void:
	var board_root = SceneRefs.board_root()
	if not board_root:
		print("ERROR: Cannot find BoardRoot for visual layers")
		return
	
	# Create charge line visualization
	charge_line_visual = Line2D.new()
	charge_line_visual.name = "ChargeLineVisual"
	charge_line_visual.width = CHARGE_LINE_WIDTH
	charge_line_visual.default_color = CHARGE_LINE_COLOR
	charge_line_visual.add_point(Vector2.ZERO)
	charge_line_visual.clear_points()
	board_root.add_child(charge_line_visual)
	
	# Create range visualization node
	range_visual = Node2D.new()
	range_visual.name = "ChargeRangeVisual"
	board_root.add_child(range_visual)
	
	# Create target highlight container
	target_highlights = Node2D.new()
	target_highlights.name = "ChargeTargetHighlights"
	board_root.add_child(target_highlights)

	# P3-127: Create charge trajectory preview
	charge_trajectory_preview = ChargeTrajectoryPreview.new()
	board_root.add_child(charge_trajectory_preview)
	print("[ChargeController] P3-127: Created charge trajectory preview")

func _setup_bottom_hud() -> void:
	# NOTE: Main.gd now handles the phase action button
	# ChargeController only manages charge-specific UI in the right panel
	pass

func _setup_right_panel() -> void:
	# Main.gd already handles cleanup before controller creation
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		container = VBoxContainer.new()
		container.name = "VBoxContainer"
		hud_right.add_child(container)
	
	# Clean up existing charge scroll container
	var existing_scroll = container.get_node_or_null("ChargeScrollContainer")
	if existing_scroll:
		container.remove_child(existing_scroll)
		existing_scroll.free()
	
	# Create scroll container for better layout
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "ChargeScrollContainer"
	scroll_container.custom_minimum_size = Vector2(250, 400)  # Standard size across all phases
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Take available space
	container.add_child(scroll_container)
	
	# Create charge panel
	var charge_panel = VBoxContainer.new()
	charge_panel.name = "ChargePanel"
	charge_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the scroll viewport vertically so the dice log (the only
	# vertically-expanding child) can absorb any leftover panel height.
	charge_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(charge_panel)
	
	# Unit selector
	var unit_label = Label.new()
	unit_label.text = "UNITS THAT CAN CHARGE"
	unit_label.add_theme_font_size_override("font_size", 13)
	unit_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		unit_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	charge_panel.add_child(unit_label)
	
	unit_selector = ItemList.new()
	unit_selector.name = "ChargeUnitSelector"
	unit_selector.custom_minimum_size = Vector2(200, 150)
	unit_selector.item_selected.connect(_on_unit_selected)
	_WhiteDwarfTheme.apply_to_item_list(unit_selector)
	charge_panel.add_child(unit_selector)

	_add_charge_gold_separator(charge_panel)

	# Target list
	var target_label = Label.new()
	target_label.text = "ELIGIBLE TARGETS"
	target_label.add_theme_font_size_override("font_size", 13)
	target_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		target_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	charge_panel.add_child(target_label)
	
	target_list = ItemList.new()
	target_list.name = "ChargeTargetList"
	target_list.custom_minimum_size = Vector2(200, 100)
	target_list.select_mode = ItemList.SELECT_MULTI
	# The list's own selection state is the single source of truth for
	# selected_targets. A SELECT_MULTI ItemList emits multi_selected — never
	# item_selected (that is single-select only), which is why the old
	# item_selected hookup "wasn't working" and grew a gui_input hack. That hack
	# appended every clicked row to selected_targets without ever removing the
	# previous one, so clicking target B after target A silently declared a
	# charge against BOTH while only B stayed highlighted.
	#
	# We OWN left-clicks via gui_input rather than leaning on the built-in
	# SELECT_MULTI toggle: Godot's built-in reads only the mouse event's
	# ctrl_pressed field, so on platforms/WMs that do not stamp the Ctrl
	# modifier onto the mouse button event, holding Ctrl and clicking did
	# nothing (the reported "Ctrl+Click doesn't select a second target" bug).
	# Our handler detects Ctrl from BOTH the event AND the live key state
	# (Input.is_key_pressed) so a held Ctrl toggles regardless of platform.
	# multi_selected stays connected so KEYBOARD selection (arrows + space)
	# still syncs; empty_clicked handles right-clicks on empty space.
	target_list.gui_input.connect(_on_target_list_gui_input)
	target_list.multi_selected.connect(_on_target_multi_selected)
	target_list.empty_clicked.connect(_on_target_list_empty_clicked)
	_WhiteDwarfTheme.apply_to_item_list(target_list)
	charge_panel.add_child(target_list)

	# Interaction hint: plain click picks ONE target; Ctrl+Click builds a
	# multi-charge. Made deliberately prominent (boxed, gold-accented, bbcode
	# emphasis on "Ctrl+Click") and DYNAMIC — once a first target is picked the
	# copy actively prompts "hold Ctrl and click another to charge both" — so the
	# multi-target affordance is impossible to miss. See _update_target_hint_label.
	target_hint_label = RichTextLabel.new()
	target_hint_label.name = "ChargeTargetHintLabel"
	target_hint_label.bbcode_enabled = true
	target_hint_label.fit_content = true
	target_hint_label.scroll_active = false
	target_hint_label.custom_minimum_size = Vector2(200, 0)
	target_hint_label.add_theme_font_size_override("normal_font_size", 12)
	target_hint_label.add_theme_font_size_override("bold_font_size", 12)
	# Boxed background so the instruction reads as a callout, not body text.
	var hint_box := StyleBoxFlat.new()
	hint_box.bg_color = Color(0.16, 0.12, 0.05, 0.85)
	hint_box.border_color = _WhiteDwarfTheme.WH_GOLD
	hint_box.set_border_width_all(1)
	hint_box.set_corner_radius_all(3)
	hint_box.content_margin_left = 6
	hint_box.content_margin_right = 6
	hint_box.content_margin_top = 4
	hint_box.content_margin_bottom = 4
	target_hint_label.add_theme_stylebox_override("normal", hint_box)
	charge_panel.add_child(target_hint_label)
	_update_target_hint_label()

	# Option 2: declaration-time reachability hint. Updates as targets are
	# (de)selected to show the roll needed to reach EVERY selected target — so an
	# out-of-reach declared target is obvious BEFORE rolling.
	charge_requirement_label = RichTextLabel.new()
	charge_requirement_label.bbcode_enabled = true
	charge_requirement_label.fit_content = true
	charge_requirement_label.custom_minimum_size = Vector2(200, 0)
	charge_requirement_label.scroll_active = false
	charge_requirement_label.add_theme_font_size_override("normal_font_size", 12)
	charge_panel.add_child(charge_requirement_label)

	_add_charge_gold_separator(charge_panel)

	# Dice log display
	var dice_label = Label.new()
	dice_label.text = "DICE LOG"
	dice_label.add_theme_font_size_override("font_size", 13)
	dice_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		dice_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	charge_panel.add_child(dice_label)
	
	# T5-V1: Animated dice roll visualization
	dice_roll_visual = DiceRollVisual.new()
	dice_roll_visual.custom_minimum_size = Vector2(200, 0)
	dice_roll_visual.visible = false  # Hidden until first roll
	charge_panel.add_child(dice_roll_visual)

	dice_log_display = RichTextLabel.new()
	dice_log_display.custom_minimum_size = Vector2(200, 100)
	dice_log_display.bbcode_enabled = true
	# Expand to fill any unused right-panel height instead of leaving dead space.
	dice_log_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	charge_panel.add_child(dice_log_display)

	_add_charge_gold_separator(charge_panel)

	# Charge status display
	var status_label = Label.new()
	status_label.text = "CHARGE ACTIONS"
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		status_label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	charge_panel.add_child(status_label)
	
	# Charge info label (moved from top bar)
	charge_info_label = Label.new()
	charge_info_label.text = "Step 1: Select a unit from the list above to begin charge"
	charge_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	charge_panel.add_child(charge_info_label)
	
	# Action buttons container
	var action_button_container = VBoxContainer.new()
	action_button_container.name = "ChargeActionButtons"
	
	# First row: Main action buttons
	var main_buttons = HBoxContainer.new()
	main_buttons.name = "MainButtons"

	declare_button = Button.new()
	declare_button.name = "DeclareChargeButton"
	declare_button.text = "Declare Charge"
	declare_button.disabled = true
	declare_button.pressed.connect(_on_declare_charge_pressed)
	_WhiteDwarfTheme.apply_primary_button(declare_button)
	main_buttons.add_child(declare_button)

	roll_button = Button.new()
	roll_button.name = "RollChargeButton"
	roll_button.text = "Roll 2D6"
	roll_button.disabled = true
	roll_button.pressed.connect(_on_roll_charge_pressed)
	_WhiteDwarfTheme.apply_primary_button(roll_button)
	main_buttons.add_child(roll_button)
	
	action_button_container.add_child(main_buttons)
	
	# Second row: Secondary buttons
	var secondary_buttons = HBoxContainer.new()
	
	skip_button = Button.new()
	skip_button.text = "Skip Charge"
	skip_button.disabled = true
	skip_button.pressed.connect(_on_skip_charge_pressed)
	_WhiteDwarfTheme.apply_to_button(skip_button)
	secondary_buttons.add_child(skip_button)

	next_unit_button = Button.new()
	next_unit_button.text = "Select Next Unit"
	next_unit_button.disabled = true
	next_unit_button.visible = false
	next_unit_button.pressed.connect(_on_next_unit_pressed)
	_WhiteDwarfTheme.apply_to_button(next_unit_button)
	secondary_buttons.add_child(next_unit_button)
	
	action_button_container.add_child(secondary_buttons)
	
	charge_panel.add_child(action_button_container)
	
	# Distance tracking section (moved from top bar, initially hidden)
	var distance_container = VBoxContainer.new()
	distance_container.name = "DistanceTracking"
	
	charge_distance_label = Label.new()
	charge_distance_label.text = "Charge: 0\""
	charge_distance_label.visible = false
	distance_container.add_child(charge_distance_label)
	
	charge_used_label = Label.new()
	charge_used_label.text = "Used: 0.0\""
	charge_used_label.visible = false
	distance_container.add_child(charge_used_label)
	
	charge_left_label = Label.new()
	charge_left_label.text = "Left: 0.0\""
	charge_left_label.visible = false
	distance_container.add_child(charge_left_label)

	# P3-98: Terrain penalty breakdown label
	charge_terrain_label = Label.new()
	charge_terrain_label.text = ""
	charge_terrain_label.visible = false
	charge_terrain_label.add_theme_font_size_override("font_size", 11)
	charge_terrain_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))  # Yellow/amber for terrain info
	distance_container.add_child(charge_terrain_label)

	charge_panel.add_child(distance_container)
	
	# Charge status (moved from top bar)
	charge_status_label = Label.new()
	charge_status_label.text = ""
	charge_status_label.add_theme_font_size_override("font_size", 12)
	charge_panel.add_child(charge_status_label)

	_add_charge_gold_separator(charge_panel)

	# Failed Charges section
	var failed_header = Label.new()
	failed_header.text = "FAILED CHARGES"
	failed_header.add_theme_font_size_override("font_size", 13)
	failed_header.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	if FactionPalettes:
		failed_header.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
	charge_panel.add_child(failed_header)

	failed_charges_container = VBoxContainer.new()
	failed_charges_container.name = "FailedChargesContainer"
	charge_panel.add_child(failed_charges_container)

	# Start with a placeholder message
	var no_failures_label = Label.new()
	no_failures_label.name = "NoFailuresLabel"
	no_failures_label.text = "No failed charges yet"
	no_failures_label.add_theme_font_size_override("font_size", 11)
	no_failures_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	failed_charges_container.add_child(no_failures_label)

func _add_charge_gold_separator(parent: VBoxContainer) -> void:
	var spacer_top = Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 2)
	parent.add_child(spacer_top)
	var sep = ColorRect.new()
	sep.color = Color(_WhiteDwarfTheme.WH_GOLD, 0.3)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)
	var spacer_bot = Control.new()
	spacer_bot.custom_minimum_size = Vector2(0, 2)
	parent.add_child(spacer_bot)

func set_phase(phase_instance) -> void:
	current_phase = phase_instance
	
	# Connect to charge phase signals
	if current_phase.has_signal("unit_selected_for_charge"):
		if not current_phase.unit_selected_for_charge.is_connected(_on_unit_selected_for_charge):
			current_phase.unit_selected_for_charge.connect(_on_unit_selected_for_charge)
	
	if current_phase.has_signal("charge_targets_available"):
		if not current_phase.charge_targets_available.is_connected(_on_charge_targets_available):
			current_phase.charge_targets_available.connect(_on_charge_targets_available)
	
	if current_phase.has_signal("charge_roll_made"):
		if not current_phase.charge_roll_made.is_connected(_on_charge_roll_made):
			current_phase.charge_roll_made.connect(_on_charge_roll_made)

	if current_phase.has_signal("dice_rolled"):
		if not current_phase.dice_rolled.is_connected(_on_dice_rolled):
			current_phase.dice_rolled.connect(_on_dice_rolled)

	if current_phase.has_signal("charge_resolved"):
		if not current_phase.charge_resolved.is_connected(_on_charge_resolved):
			current_phase.charge_resolved.connect(_on_charge_resolved)

	# T-092: defender-side charge arrows — connect to targets_declared so the
	# defender's client renders the same arrow-from-charger-to-target visual
	# whenever ANY player declares a charge (local human / remote human / AI)
	if current_phase.has_signal("targets_declared"):
		if not current_phase.targets_declared.is_connected(_on_targets_declared_remote_visual):
			current_phase.targets_declared.connect(_on_targets_declared_remote_visual)

	if current_phase.has_signal("charge_unit_completed"):
		if not current_phase.charge_unit_completed.is_connected(_on_charge_unit_completed):
			current_phase.charge_unit_completed.connect(_on_charge_unit_completed)

	if current_phase.has_signal("charge_unit_skipped"):
		if not current_phase.charge_unit_skipped.is_connected(_on_charge_unit_skipped):
			current_phase.charge_unit_skipped.connect(_on_charge_unit_skipped)

	if current_phase.has_signal("ability_reroll_opportunity"):
		if not current_phase.ability_reroll_opportunity.is_connected(_on_ability_reroll_opportunity):
			current_phase.ability_reroll_opportunity.connect(_on_ability_reroll_opportunity)

	if current_phase.has_signal("command_reroll_opportunity"):
		if not current_phase.command_reroll_opportunity.is_connected(_on_command_reroll_opportunity):
			current_phase.command_reroll_opportunity.connect(_on_command_reroll_opportunity)

	if current_phase.has_signal("overwatch_opportunity"):
		if not current_phase.overwatch_opportunity.is_connected(_on_overwatch_opportunity):
			current_phase.overwatch_opportunity.connect(_on_overwatch_opportunity)


	if current_phase.has_signal("heroic_intervention_opportunity"):
		if not current_phase.heroic_intervention_opportunity.is_connected(_on_heroic_intervention_opportunity):
			current_phase.heroic_intervention_opportunity.connect(_on_heroic_intervention_opportunity)

	# The HI success path emits ONLY charge_path_tools_enabled (never
	# charge_roll_made) — without this connection the defender is told the
	# counter-charge roll succeeded but gets no way to move the models.
	if current_phase.has_signal("charge_path_tools_enabled"):
		if not current_phase.charge_path_tools_enabled.is_connected(_on_charge_path_tools_enabled):
			current_phase.charge_path_tools_enabled.connect(_on_charge_path_tools_enabled)

	if current_phase.has_signal("tank_shock_opportunity"):
		if not current_phase.tank_shock_opportunity.is_connected(_on_tank_shock_opportunity):
			current_phase.tank_shock_opportunity.connect(_on_tank_shock_opportunity)

	if current_phase.has_signal("tank_shock_result"):
		if not current_phase.tank_shock_result.is_connected(_on_tank_shock_result):
			current_phase.tank_shock_result.connect(_on_tank_shock_result)

	# Refresh UI with current phase data
	_refresh_ui()

func _refresh_ui() -> void:
	if not current_phase:
		print("ChargeController: No current_phase in _refresh_ui")
		return
	
	# Ensure UI components exist
	if not is_instance_valid(unit_selector):
		print("DEBUG: Unit selector missing, recreating UI...")
		_setup_right_panel()
		if not is_instance_valid(unit_selector):
			print("ERROR: Still no unit selector after recreating UI")
			return
	
	# Clear and populate unit selector with units that can charge
	unit_selector.clear()
	
	# Use ChargePhase's eligible units method which respects completed_charges
	var eligible_unit_ids = current_phase.get_eligible_charge_units()
	# Only surface units that actually have an enemy within 12" (a chargeable
	# target). A unit can be "eligible to charge" per the rules yet have no target
	# in range, which was reported as confusing — it appears chargeable but
	# selecting it shows an empty ELIGIBLE TARGETS list. Filtering here keeps the
	# UNITS THAT CAN CHARGE list consistent with the targets each unit can reach.
	var chargeable_unit_ids = _filter_units_with_charge_targets(eligible_unit_ids)
	var current_player = current_phase.get_current_player()
	var units = current_phase.get_units_for_player(current_player)

	print("ChargeController: Refreshing UI for player ", current_player)
	print("ChargeController: Eligible units from phase: ", eligible_unit_ids)
	print("ChargeController: Chargeable (target within 12\") units: ", chargeable_unit_ids)
	print("ChargeController: Completed charges: ", current_phase.get_completed_charges() if current_phase.has_method("get_completed_charges") else "N/A")
	
	# Debug help: Show why units might not be eligible
	if eligible_unit_ids.is_empty():
		print("ChargeController: No units eligible for charge. Checking reasons...")
		for unit_id in units:
			var unit = units[unit_id]
			var status = unit.get("status", 0)
			var flags = unit.get("flags", {})
			var status_name = GameStateData.UnitStatus.keys()[status] if status < GameStateData.UnitStatus.size() else "UNKNOWN"
			
			print("  Unit ", unit_id, " (", unit.get("meta", {}).get("name", unit_id), "):")
			print("    Status: ", status, " (", status_name, ")")
			print("    Flags: ", flags)
			
			# Check specific blocking conditions
			if not (status == GameStateData.UnitStatus.DEPLOYED or status == GameStateData.UnitStatus.MOVED or status == GameStateData.UnitStatus.SHOT):
				print("    BLOCKED: Status must be DEPLOYED, MOVED, or SHOT")
			elif flags.get("cannot_charge", false):
				print("    BLOCKED: Unit has 'cannot_charge' flag")
			elif flags.get("advanced", false) and not flags.get("effect_advance_and_charge", false):
				print("    BLOCKED: Unit has 'advanced' flag (Advanced units cannot charge without advance_and_charge effect)")
			elif flags.get("fell_back", false):
				print("    BLOCKED: Unit has 'fell_back' flag")
			elif unit_id in current_phase.get_completed_charges():
				print("    BLOCKED: Unit has already charged this phase")
			else:
				print("    SHOULD BE ELIGIBLE - this might be a bug")
	elif chargeable_unit_ids.is_empty():
		# Units can charge per the rules but none has an enemy within 12".
		print("ChargeController: ", eligible_unit_ids.size(), " unit(s) can charge but none has a target within 12\" — none shown.")

	var can_charge_count = 0
	for unit_id in chargeable_unit_ids:
		if unit_id in units:
			var unit = units[unit_id]
			can_charge_count += 1
			# display_name keeps duplicate squads (e.g. "... Alpha"/"... Beta") distinct.
			var _uname_meta = unit.get("meta", {})
			var unit_name = _uname_meta.get("display_name", _uname_meta.get("name", unit_id))
			unit_selector.add_item(unit_name)
			unit_selector.set_item_metadata(unit_selector.get_item_count() - 1, unit_id)
			print("    Added eligible unit ", unit_id, " (", unit_name, ") to selector")

	print("ChargeController: Found ", can_charge_count, " units that can still charge")
	
	# CRITICAL: Ensure charge buttons exist and remain visible after refresh
	_ensure_charge_buttons_exist()
	
	# Update UI state
	_update_button_states()

func _can_unit_charge(unit: Dictionary) -> bool:
	# Use RulesEngine to check if unit can charge
	var unit_id = unit.get("id", "")
	var board = GameState.create_snapshot(false)
	return RulesEngine.eligible_to_charge(unit_id, board)

func get_displayed_charge_unit_ids() -> Array:
	# The unit ids currently listed in the UNITS THAT CAN CHARGE selector, i.e.
	# after the target-within-12" filter. Read-only accessor exposed for windowed
	# scenario tests / tooling so they can assert exactly which units are shown.
	var ids: Array = []
	if not is_instance_valid(unit_selector):
		return ids
	for i in range(unit_selector.get_item_count()):
		ids.append(unit_selector.get_item_metadata(i))
	return ids

func _filter_units_with_charge_targets(unit_ids: Array) -> Array:
	# Keep only units that have at least one enemy within 12" (a chargeable
	# target). Uses the SAME RulesEngine query that populates the ELIGIBLE TARGETS
	# list (charge_targets_within_12), so a unit is shown in UNITS THAT CAN CHARGE
	# only when selecting it would actually offer a target to charge. This is a
	# display-only refinement; the phase's own eligibility (used by AI / phase
	# logic) is unchanged.
	var result: Array = []
	var board = GameState.create_snapshot(false)
	for unit_id in unit_ids:
		if not RulesEngine.charge_targets_within_12(unit_id, board).is_empty():
			result.append(unit_id)
	return result

func _update_button_states() -> void:
	if not current_phase:
		print("DEBUG: _update_button_states() - no current_phase")
		return
	
	var has_selected_unit = active_unit_id != ""
	var has_selected_targets = selected_targets.size() > 0
	var can_declare = has_selected_unit and has_selected_targets and not awaiting_roll and not awaiting_movement
	var can_roll = awaiting_roll
	var can_skip = has_selected_unit and not awaiting_movement
	
	print("DEBUG: Button states - unit:", active_unit_id, " targets:", selected_targets.size(), " awaiting_roll:", awaiting_roll, " awaiting_movement:", awaiting_movement)
	print("DEBUG: has_selected_unit:", has_selected_unit, " has_selected_targets:", has_selected_targets, " can_declare:", can_declare)
	
	if is_instance_valid(declare_button):
		declare_button.disabled = not can_declare
		# Surface the multi-target count ON the commit button so accidentally
		# declaring a charge against several units is impossible to miss.
		if selected_targets.size() > 1:
			declare_button.text = "Declare Charge (%d targets)" % selected_targets.size()
		else:
			declare_button.text = "Declare Charge"

	# Keep the prominent Click / Ctrl+Click hint in sync with the selection.
	_update_target_hint_label()
	if is_instance_valid(roll_button):
		roll_button.disabled = not can_roll
	if is_instance_valid(skip_button):
		skip_button.disabled = not can_skip

	# T-092 fix: the confirm-row buttons (Snap to Contact + Undo Last Model)
	# must only be interactable while an active charge move is in progress.
	# Previously only confirm_button's visibility was toggled (in
	# _enable_charge_movement / _on_confirm_charge_moves); the Snap and Undo
	# buttons were never hidden or disabled after creation, so they lingered
	# visible + ENABLED after a charge was confirmed, between charges, and
	# while a Command Re-roll decision was still pending. Clicking Snap in any
	# of those states does nothing — _on_auto_path_charge early-returns on the
	# empty models_to_move — which reads to the player as "the Snap to Contact
	# button doesn't do anything". Gate both on awaiting_movement here so they
	# track the charge-move state everywhere _update_button_states runs (unit
	# select, reset, next-charge refresh, roll made, decline reroll, ...).
	if is_instance_valid(auto_path_charge_button):
		auto_path_charge_button.visible = awaiting_movement
		# Only snap-able while there are still models left to place.
		auto_path_charge_button.disabled = models_to_move.is_empty()
	if is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.visible = awaiting_movement
		undo_charge_model_button.disabled = _moved_model_order.is_empty()

	# Update charge status
	_update_charge_status()

	# Option 2: refresh the pre-roll reachability hint for the current selection.
	_update_charge_requirement_hint()

	if is_instance_valid(declare_button):
		print("DEBUG: Declare button disabled:", declare_button.disabled)
	
	# Update info label with clear step-by-step instructions
	if is_instance_valid(charge_info_label):
		if awaiting_movement:
			charge_info_label.text = "Use UI to move models into engagement range"
		elif awaiting_roll:
			charge_info_label.text = "Click 'Roll 2D6' for charge distance"
		elif has_selected_unit and not has_selected_targets:
			charge_info_label.text = "Step 2: Click a target below (Ctrl+Click adds more for a multi-charge)"
		elif has_selected_unit and has_selected_targets:
			if selected_targets.size() > 1:
				charge_info_label.text = "Step 3: Click 'Declare Charge' to charge ALL %d selected targets" % selected_targets.size()
			else:
				charge_info_label.text = "Step 3: Click 'Declare Charge' to proceed"
		else:
			charge_info_label.text = "Step 1: Select a unit from the list below to begin charge"

func _on_unit_selected(index: int) -> void:
	print("ChargeController: Unit selected at index ", index)
	if index >= 0 and index < unit_selector.get_item_count():
		active_unit_id = unit_selector.get_item_metadata(index)
		print("Selected unit for charge: ", active_unit_id)
		
		# Reset charge state for the new unit
		awaiting_roll = false
		awaiting_movement = false
		selected_targets.clear()
		
		# Ensure buttons are visible when selecting a unit
		if is_instance_valid(declare_button):
			declare_button.visible = true
		if is_instance_valid(roll_button):
			roll_button.visible = true
		if is_instance_valid(skip_button):
			skip_button.visible = true
			skip_button.disabled = false  # Can always skip once a unit is selected
		
		# Get eligible targets for this unit
		var board = GameState.create_snapshot(false)
		eligible_targets = RulesEngine.charge_targets_within_12(active_unit_id, board)
		
		print("Found ", eligible_targets.size(), " eligible targets for unit ", active_unit_id)
		for target_id in eligible_targets:
			print("  - ", target_id, ": ", eligible_targets[target_id])
		
		# Update target list
		_refresh_target_list()
		_update_button_states()
		_update_visuals()

func _refresh_target_list() -> void:
	if not is_instance_valid(target_list):
		return
	target_list.clear()
	selected_targets.clear()
	pad_target_cursor = -1  # rows rebuilt — pad ▲ ▼ cursor restarts
	
	print("DEBUG: _refresh_target_list - adding ", eligible_targets.size(), " targets")
	for target_id in eligible_targets:
		var target_data = eligible_targets[target_id]
		var display_text = "%s (%.1f\")" % [target_data.name, target_data.distance]
		target_list.add_item(display_text)
		var item_index = target_list.get_item_count() - 1
		target_list.set_item_metadata(item_index, target_id)
		print("DEBUG: Added target item ", item_index, ": '", display_text, "' with metadata: ", target_id)
	
	print("DEBUG: Target list now has ", target_list.get_item_count(), " items")

func _on_target_list_gui_input(event: InputEvent) -> void:
	# Own the LEFT-click selection so multi-target charge works on every platform.
	# Godot's built-in ItemList SELECT_MULTI toggle only fires when the mouse
	# event itself carries ctrl_pressed; some platforms/WMs never stamp that onto
	# the button event, so a player holding Ctrl and clicking got a plain single
	# select and could never build a multi-charge. Here we read Ctrl from BOTH the
	# event AND the live keyboard state, so a held Ctrl always toggles.
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# Rows are locked once the charge is declared — let nothing change then.
	if awaiting_roll or awaiting_movement:
		return
	# Act on press; consume press+release so the built-in selection never also
	# runs (which would fight our own select/deselect below).
	get_viewport().set_input_as_handled()
	target_list.accept_event()
	if not mb.pressed:
		return
	target_list.grab_focus()  # normal list behaviour: click focuses it for keyboard nav

	var idx: int = target_list.get_item_at_position(mb.position, true)
	if idx < 0:
		# Clicked empty space inside the list — clear the selection.
		target_list.deselect_all()
		_sync_selected_targets_from_list()
		return

	# Ctrl / Cmd (or Shift) held → toggle this row in/out for a multi-charge;
	# no modifier → select only this row. Detect the modifier from the event
	# and, as a platform-robust fallback, from the live key state.
	var additive: bool = mb.ctrl_pressed or mb.meta_pressed or mb.shift_pressed \
		or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) \
		or Input.is_key_pressed(KEY_SHIFT)

	if additive:
		if target_list.is_selected(idx):
			target_list.deselect(idx)
		else:
			target_list.select(idx, false)  # false = keep existing selection
	else:
		target_list.select(idx, true)  # true = single-select (clears others)
	_sync_selected_targets_from_list()

func _on_target_multi_selected(_index: int, _selected: bool) -> void:
	# Keyboard selection (arrow keys + Space/Enter on the focused ItemList) still
	# routes through the built-in and emits this — keep it synced. Mouse clicks
	# are handled in _on_target_list_gui_input, which accept_event()s so the
	# built-in never emits this for a click (no double-handling).
	if awaiting_roll or awaiting_movement:
		return  # declaration already committed — rows are locked
	_sync_selected_targets_from_list()

func _on_target_list_empty_clicked(_at_position: Vector2, mouse_button_index: int) -> void:
	# Clicking empty space below the rows clears the whole selection.
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if awaiting_roll or awaiting_movement:
		return
	target_list.deselect_all()
	_sync_selected_targets_from_list()

func _on_target_selected(index: int) -> void:
	# Back-compat entry point: scenario tests and tooling call
	# target_list.select(i) followed by _on_target_selected(i). The list's
	# selection state is the source of truth, so just resync from it.
	if index < 0 or index >= target_list.get_item_count():
		print("DEBUG: _on_target_selected invalid index:", index, " item_count:", target_list.get_item_count())
		return
	_sync_selected_targets_from_list()

func _sync_selected_targets_from_list() -> void:
	selected_targets.clear()
	for idx in target_list.get_selected_items():
		var target_id = target_list.get_item_metadata(idx)
		if target_id != null and str(target_id) != "":
			selected_targets.append(str(target_id))
	print("ChargeController: selected_targets now ", selected_targets)
	_update_button_states()
	_update_visuals()

# ============================================================================
# Pad (controller) support: D-pad ▲ ▼ walks the ELIGIBLE TARGETS rows with a
# gold cursor tint, A toggles the walked row in/out of the declaration (pad
# equivalent of Click / Ctrl+Click), Start declares then rolls, X skips.
# Driven by PadRouter; windowed scenarios assert pad_target_cursor.
# ============================================================================
var pad_target_cursor: int = -1

func pad_step_target(dir: int) -> bool:
	if active_unit_id == "" or awaiting_roll or awaiting_movement:
		return false
	if not is_instance_valid(target_list) or target_list.get_item_count() == 0:
		return false
	var n = target_list.get_item_count()
	if pad_target_cursor < 0 or pad_target_cursor >= n:
		pad_target_cursor = 0 if dir > 0 else n - 1
	else:
		pad_target_cursor = wrapi(pad_target_cursor + dir, 0, n)
	_update_pad_target_cursor_visual()
	return true

func pad_toggle_target() -> bool:
	if active_unit_id == "" or awaiting_roll or awaiting_movement:
		return false
	if not is_instance_valid(target_list):
		return false
	if pad_target_cursor < 0 or pad_target_cursor >= target_list.get_item_count():
		return false
	# Additive toggle, exactly like Ctrl+Click — stepping to another row and
	# pressing A again builds a multi-charge; A on a selected row removes it.
	if target_list.is_selected(pad_target_cursor):
		target_list.deselect(pad_target_cursor)
	else:
		target_list.select(pad_target_cursor, false)
	_sync_selected_targets_from_list()
	return true

# Start: walk the charge flow forward — Roll 2D6 once declared, otherwise
# Declare Charge when the selection allows it. Mirrors the two primary
# buttons, honoring their disabled state.
func pad_primary_action() -> bool:
	if awaiting_roll and is_instance_valid(roll_button) and not roll_button.disabled:
		_on_roll_charge_pressed()
		return true
	if is_instance_valid(declare_button) and not declare_button.disabled:
		_on_declare_charge_pressed()
		return true
	return false

# X: same as the Skip Charge button.
func pad_skip() -> bool:
	if not is_instance_valid(skip_button) or skip_button.disabled or not skip_button.visible:
		return false
	_on_skip_charge_pressed()
	return true

func _update_pad_target_cursor_visual() -> void:
	if not is_instance_valid(target_list):
		return
	for i in range(target_list.get_item_count()):
		if i == pad_target_cursor:
			target_list.set_item_custom_bg_color(i, Color(0.94, 0.78, 0.31, 0.25))
		else:
			target_list.set_item_custom_bg_color(i, Color(0, 0, 0, 0))

func _update_target_hint_label() -> void:
	# Prominent, DYNAMIC teaching copy for the ELIGIBLE TARGETS list. The whole
	# point is that a player must never accidentally charge two units, nor fail
	# to discover that charging several at once is possible — so the hint spells
	# out Ctrl+Click and changes to match what is currently selected.
	if not is_instance_valid(target_hint_label):
		return
	# Once the charge is declared the rows are locked and the player is rolling —
	# the selection hint no longer applies.
	if awaiting_roll or awaiting_movement:
		target_hint_label.visible = false
		return
	target_hint_label.visible = true

	var gold := "#f0c850"
	# "Ctrl / Cmd" so Mac players see their modifier too (the input path already
	# matches meta as well as ctrl).
	var ck := "[color=%s][b]Ctrl+Click[/b][/color]" % gold
	var body: String
	if selected_targets.size() >= 2:
		body = "Charging [color=%s][b]%d units[/b][/color] at once.  %s a unit to add or remove it." % [gold, selected_targets.size(), ck]
	elif selected_targets.size() == 1:
		body = "1 target selected.  To charge [b]more than one[/b] unit, hold %s another target." % ck
	else:
		body = "[b]Click[/b] a target to charge it.  To charge [b]several units[/b] at once, %s each one." % ck
	target_hint_label.text = body

func _update_charge_requirement_hint() -> void:
	"""Option 2: show the roll needed to reach EVERY selected target before the
	player commits, so an out-of-reach declared target is obvious pre-roll and
	the 'a charge must reach ALL declared targets' rule is taught in context.
	Uses the raw edge distance minus engagement range as a terrain-free pre-roll
	estimate (the actual path — and any terrain penalty — is unknown until the
	player draws the move)."""
	if not is_instance_valid(charge_requirement_label):
		return
	# Only meaningful while choosing targets (before the roll / the move).
	if selected_targets.is_empty() or awaiting_roll or awaiting_movement:
		charge_requirement_label.text = ""
		charge_requirement_label.visible = false
		return
	charge_requirement_label.visible = true

	var er: float = GameConstants.engagement_range_inches()
	var worst_name: String = ""
	var worst_need: float = -1.0
	var per_lines: Array = []
	for tid in selected_targets:
		var data: Dictionary = eligible_targets.get(tid, {})
		var dist: float = float(data.get("distance", 0.0))
		var need: float = maxf(0.0, dist - er)
		var tname: String = str(data.get("name", tid))
		per_lines.append("  • %s — %.1f\" away, needs roll ≥ %.1f\"" % [tname, dist, need])
		if need > worst_need:
			worst_need = need
			worst_name = tname

	# Probability-informed colour (2D6: ≥7 ≈ 58%, ≥9 ≈ 28%, ≥11 ≈ 8%, >12 impossible).
	var color_hex: String = "#5fe36a"  # green — likely
	var tail: String = ""
	if worst_need > 12.0:
		color_hex = "#f25a5a"  # red — impossible on a raw 2D6
		tail = "  ✖ beyond a 2D6 charge — this WILL fail"
	elif worst_need >= 11.0:
		color_hex = "#f0803c"  # orange — very unlikely
		tail = "  ⚠ needs 11+ — very unlikely"
	elif worst_need >= 8.0:
		color_hex = "#f0d84a"  # yellow — risky
		tail = "  ⚠ risky"

	var verdict: String
	if selected_targets.size() == 1:
		verdict = "Needs 2D6 ≥ %.1f\" to reach %s%s" % [worst_need, worst_name, tail]
	else:
		verdict = "Needs 2D6 ≥ %.1f\" to reach ALL %d targets (farthest: %s)%s" % [
			worst_need, selected_targets.size(), worst_name, tail]

	var bb: String = "[color=%s]%s[/color]" % [color_hex, verdict]
	if selected_targets.size() > 1:
		bb += "\n[color=#b9b9b9]%s\nA charge must end within engagement range of EVERY declared target.[/color]" % "\n".join(per_lines)
	charge_requirement_label.text = bb

func _update_visuals() -> void:
	# Clear existing visuals
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()
	_clear_highlights()
	_clear_charge_arrow_visuals()  # T7-58: Clear old arrows
	_clear_charge_trajectory_preview()  # P3-127: Clear old trajectories
	_clear_charge_range_circle()  # T-092: Clear 12" range overlay

	if active_unit_id == "":
		return

	# Get unit position
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return

	var unit_center = _get_unit_center_position(unit)

	# T-092: Show the pre-roll 12" charge-range overlay around the active charging
	# unit. Once the roll is made and models are being dragged (awaiting_movement),
	# the per-model reach rings from _show_per_model_charge_ranges() apply instead,
	# so don't redraw the threat envelope over them.
	if not awaiting_movement:
		_show_charge_range_overlay(unit)

	# Draw lines to selected targets
	for target_id in selected_targets:
		var target_unit = GameState.get_unit(target_id)
		if not target_unit.is_empty():
			var target_center = _get_unit_center_position(target_unit)
			if is_instance_valid(charge_line_visual):
				charge_line_visual.add_point(unit_center)
				charge_line_visual.add_point(target_center)

			# T7-58: Create animated charge arrow visual
			_create_charge_arrow_visual(unit_center, target_center, false)

			# Add highlight to target
			_highlight_unit(target_id, HIGHLIGHT_COLOR_SELECTED)

	# P3-127: Show charge trajectory preview when targets are selected
	if not selected_targets.is_empty() and not awaiting_roll and not awaiting_movement:
		_update_charge_trajectory_preview(unit, unit_center)

	# Highlight eligible targets
	for target_id in eligible_targets:
		if target_id not in selected_targets:
			_highlight_unit(target_id, HIGHLIGHT_COLOR_ELIGIBLE)

func _get_unit_center_position(unit: Dictionary) -> Vector2:
	var models = unit.get("models", [])
	if models.is_empty():
		return Vector2.ZERO
	
	var center = Vector2.ZERO
	var count = 0
	
	for model in models:
		if model.get("alive", true):
			var pos = model.get("position")
			if pos:
				center += Vector2(pos.get("x", 0), pos.get("y", 0))
				count += 1
	
	if count > 0:
		center /= count
	
	return center

func _highlight_unit(unit_id: String, color: Color) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var pos = model.get("position")
		if not pos:
			continue
		
		var highlight = ColorRect.new()
		highlight.position = Vector2(pos.get("x", 0), pos.get("y", 0)) - Vector2(16, 16)
		highlight.size = Vector2(32, 32)
		highlight.color = color
		target_highlights.add_child(highlight)

func _clear_highlights() -> void:
	for child in target_highlights.get_children():
		child.queue_free()

func _log_unit_positions(unit_id: String, label: String) -> void:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("DEBUG: ", label, " (", unit_id, ") - Unit not found")
		return
	
	print("DEBUG: ", label, " (", unit_id, ") positions:")
	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		var pos = model.get("position", {})
		if pos.has("x") and pos.has("y"):
			print("  Model ", i, " (", model.get("id", ""), "): (", pos.x, ", ", pos.y, ")")
		else:
			print("  Model ", i, " (", model.get("id", ""), "): no position")

func _get_charge_targets_from_phase(unit_id: String) -> Array:
	"""Get the declared charge targets from ChargePhase's synced game state.

	This ensures both charging and defending players use the same target list
	when determining charge success, fixing the bug where defending players
	always see "charge failed" due to empty local selected_targets.

	NOTE: This only works on the host where pending_charges is populated.
	Clients should use targets from dice_data instead.
	"""
	if not current_phase:
		print("WARNING: No current_phase available to get charge targets")
		return []

	# Heroic Intervention: the counter-charge targets live on the phase's HI
	# pending charge, not in pending_charges.
	if str(current_phase.get("heroic_intervention_unit_id")) == unit_id:
		var hi_pending = current_phase.get("heroic_intervention_pending_charge")
		if hi_pending is Dictionary and not hi_pending.is_empty():
			return hi_pending.get("targets", [])

	if not current_phase.has_method("get_pending_charges"):
		print("ERROR: current_phase doesn't have get_pending_charges method")
		return []

	var pending = current_phase.get_pending_charges()
	if not pending.has(unit_id):
		print("WARNING: No pending charge found for unit ", unit_id, " (this is expected on clients)")
		return []

	var charge_data = pending[unit_id]
	var targets = charge_data.get("targets", [])

	print("Retrieved ", targets.size(), " targets from phase for unit ", unit_id, ": ", targets)
	return targets

func _is_charge_successful(unit_id: String, rolled_distance: int, target_ids: Array) -> bool:
	# Check if at least one model can reach engagement range (1") of any target.
	# T1-8 fix: Use inches (same unit as ChargePhase._is_charge_roll_sufficient)
	# to ensure deterministic results and avoid pixel/inch conversion divergence.
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return false

	# T2-8: Check FLY keyword for terrain penalty calculation
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# Check each model in the charging unit
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue

		# Check against each target unit
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue

			# Find closest enemy model using shape-aware edge-to-edge distance
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == null:
					continue

				# Edge-to-edge distance in inches, minus the edition's engagement range
				var distance_inches = Measurement.model_to_model_distance_inches(model, target_model)
				var distance_to_close = distance_inches - GameConstants.engagement_range_inches()

				# T2-8: Add terrain penalty for straight-line path
				var terrain_penalty = _calculate_terrain_penalty_for_path(model_pos, target_pos)
				var effective_distance = distance_to_close + terrain_penalty

				# Check if this model could reach engagement range with the rolled distance
				if effective_distance <= rolled_distance:
					print("Charge successful: Model can reach engagement range with roll of ", rolled_distance)
					return true

	print("Charge failed: No models can reach engagement range with roll of ", rolled_distance)
	return false

func _calculate_min_distance_to_targets(unit_id: String, target_ids: Array) -> float:
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return INF

	var min_distance = INF
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		for target_id in target_ids:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue
				var dist = Measurement.model_to_model_distance_inches(model, target_model)
				min_distance = min(min_distance, dist)

	return min_distance

func _enable_charge_movement(unit_id: String, max_distance: int) -> void:
	print("Enabling charge movement for ", unit_id, " with max distance ", max_distance)
	
	# Clear any previous movement tracking
	models_to_move.clear()
	moved_models.clear()
	_moved_model_order.clear()  # T-092: reset undo stack
	_model_origin_positions.clear()  # T-092: reset origin cache
	_model_origin_rotations.clear()  # T-092
	_model_charge_paths.clear()  # multi-step: reset per-model hop paths
	_clear_movement_visuals()

	# Get all alive models in the unit
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("ERROR: Unit ", unit_id, " not found in GameState!")
		return

	print("DEBUG: Unit has ", unit.get("models", []).size(), " models total")
	for model in unit.get("models", []):
		if model.get("alive", true):
			var model_id = model.get("id", "")
			models_to_move.append(model_id)
			# T-092: capture pre-charge origin position + rotation for undo
			var pos = model.get("position")
			if pos != null:
				var p: Vector2
				if pos is Dictionary:
					p = Vector2(pos.get("x", 0), pos.get("y", 0))
				else:
					p = pos
				_model_origin_positions[model_id] = p
				_model_origin_rotations[model_id] = model.get("rotation", 0.0)
				_model_charge_paths[model_id] = [p]  # multi-step: path starts at the origin
			print("DEBUG: Added model ", model_id, " to models_to_move")

	# Attached CHARACTER models charge with the squad — make them draggable too
	# (keyed "<char_unit_id>:<model_id>" to dodge model-id collisions). Any left
	# unmoved at confirm still auto-ride the bodyguard's delta in ChargePhase.
	for char_id in _get_attached_character_ids(unit_id):
		var char_unit = GameState.get_unit(char_id)
		for model in char_unit.get("models", []):
			if not model.get("alive", true):
				continue
			var key = _charge_model_key(char_id, model.get("id", ""))
			models_to_move.append(key)
			var pos = model.get("position")
			if pos != null:
				var p: Vector2
				if pos is Dictionary:
					p = Vector2(pos.get("x", 0), pos.get("y", 0))
				else:
					p = pos
				_model_origin_positions[key] = p
				_model_origin_rotations[key] = model.get("rotation", 0.0)
				_model_charge_paths[key] = [p]
			print("DEBUG: Added attached character model ", key, " to models_to_move")

	print("Models to move: ", models_to_move)

	# Swap the pre-roll 12" threat envelope for one per-model reach ring
	# (radius = the rolled distance) so the player can see how far each model can
	# actually be dragged, not a 12" boundary that no longer applies post-roll.
	_show_per_model_charge_ranges(unit_id, float(max_distance))

	# Show engagement range circles around charge target models
	_show_target_engagement_visuals(unit_id)

	# Add confirm button if not already present
	if not confirm_button:
		_add_confirm_button()
	
	if confirm_button and is_instance_valid(confirm_button):
		confirm_button.visible = true
		confirm_button.disabled = true  # Enable when at least one model moved
		print("DEBUG: Confirm button made visible and disabled")
		print("DEBUG: Confirm button position: ", confirm_button.position)
		print("DEBUG: Confirm button size: ", confirm_button.size)
	else:
		print("WARNING: Confirm button not created!")

	# T-092 fix: reveal the Snap to Contact + Undo Last Model buttons alongside
	# confirm now that a charge move is active. _update_button_states() (called
	# right after the roll resolves) keeps them in sync from here on, but show
	# them explicitly so they appear even on any path that skips that refresh.
	if is_instance_valid(auto_path_charge_button):
		auto_path_charge_button.visible = true
		auto_path_charge_button.disabled = models_to_move.is_empty()
	if is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.visible = true
		undo_charge_model_button.disabled = _moved_model_order.is_empty()

func _clear_movement_visuals() -> void:
	# Clear ghost visual
	if ghost_visual and is_instance_valid(ghost_visual):
		ghost_visual.queue_free()
		ghost_visual = null

	# Clear movement lines
	for line in movement_lines.values():
		if is_instance_valid(line):
			line.queue_free()
	movement_lines.clear()

	# P3-99: Clear direction validation visual
	if charge_direction_visual and is_instance_valid(charge_direction_visual):
		charge_direction_visual.queue_free()
		charge_direction_visual = null

	# Clear target engagement range visuals
	_clear_target_engagement_visuals()

	# Clear multi-select state (rings, drag box, group ghosts)
	_clear_charge_selection()
	_clear_group_ghost_visuals()
	if selection_box_visual and is_instance_valid(selection_box_visual):
		selection_box_visual.queue_free()
	selection_box_visual = null
	drag_box_active = false
	group_dragging = false
	group_drag_start_positions.clear()

func _show_target_engagement_visuals(unit_id: String) -> void:
	# Show engagement range circles around all charge target models
	_clear_target_engagement_visuals()

	var charge_targets = selected_targets
	if charge_targets.is_empty() and current_phase:
		charge_targets = _get_charge_targets_from_phase(unit_id)

	var board_root = SceneRefs.board_root()
	if not board_root:
		return

	for target_id in charge_targets:
		var target_unit = GameState.get_unit(target_id)
		if target_unit.is_empty():
			continue

		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == null or target_pos == Vector2.ZERO:
				continue

			# Create an engagement range visual around this target model
			var er_visual = preload("res://scripts/EngagementRangeVisual.gd").new()
			var base_mm = target_model.get("base_mm", 32)
			var base_radius_px = Measurement.base_radius_px(base_mm)
			var er_px = Measurement.inches_to_px(GameConstants.engagement_range_inches())  # edition-aware ER
			er_visual.setup_engagement_range(base_radius_px + er_px, Color(1.0, 0.5, 0.0, 0.5))
			er_visual.position = target_pos
			board_root.add_child(er_visual)
			target_engagement_visuals.append(er_visual)

	print("DEBUG: Created ", target_engagement_visuals.size(), " engagement range visuals around charge targets")

func _clear_target_engagement_visuals() -> void:
	for visual in target_engagement_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	target_engagement_visuals.clear()

func _add_confirm_button() -> void:
	# Add confirm button to right panel instead of top bar
	var right_container = hud_right.get_node_or_null("VBoxContainer")
	if not right_container:
		print("DEBUG: No VBoxContainer found in right panel for confirm button")
		return
	
	var charge_scroll = right_container.get_node_or_null("ChargeScrollContainer")
	if not charge_scroll:
		print("DEBUG: No ChargeScrollContainer found for confirm button")
		return
	
	var charge_panel = charge_scroll.get_node_or_null("ChargePanel")
	if not charge_panel:
		print("DEBUG: No ChargePanel found for confirm button")
		return
	
	# Find the action buttons container to add confirm button
	var action_container = charge_panel.get_node_or_null("ChargeActionButtons")
	if not action_container:
		print("DEBUG: No ChargeActionButtons container found for confirm button")
		return
	
	confirm_button = Button.new()
	confirm_button.name = "ConfirmChargeButton"
	confirm_button.text = "Confirm Charge Moves"
	confirm_button.visible = false
	_WhiteDwarfTheme.apply_to_button(confirm_button)
	print("DEBUG: Connecting confirm button signal...")
	confirm_button.pressed.connect(_on_confirm_charge_moves)
	print("DEBUG: Signal connected, adding to right panel...")

	# Add confirm button as a separate row in action container
	var confirm_row = HBoxContainer.new()
	confirm_row.name = "ConfirmRow"
	confirm_row.add_child(confirm_button)

	# T-092: per-model undo button next to confirm
	undo_charge_model_button = Button.new()
	undo_charge_model_button.name = "UndoLastModelButton"
	undo_charge_model_button.text = "Undo Last Model"
	undo_charge_model_button.disabled = true
	_WhiteDwarfTheme.apply_to_button(undo_charge_model_button)
	undo_charge_model_button.pressed.connect(_on_undo_last_charge_model)
	confirm_row.add_child(undo_charge_model_button)

	# T-092: bulk-snap button — places every unmoved model in base-to-base contact
	# with its nearest declared target (falls back to a legal gap if contact is
	# blocked). Satisfies the 11.04 "within 1 inch" rule in one click.
	auto_path_charge_button = Button.new()
	auto_path_charge_button.name = "SnapToContactButton"
	auto_path_charge_button.text = "Snap to Contact"
	auto_path_charge_button.tooltip_text = "Move all remaining models into base-to-base contact with the nearest charge target"
	_WhiteDwarfTheme.apply_to_button(auto_path_charge_button)
	auto_path_charge_button.pressed.connect(_on_auto_path_charge)
	confirm_row.add_child(auto_path_charge_button)

	action_container.add_child(confirm_row)
	print("DEBUG: Confirm button + undo-last-model button created and added to right panel")

# T-092: Undo the most recently placed charge model — restores its origin position
# and re-adds it to models_to_move so the player can retry that single placement.
func _on_undo_last_charge_model() -> void:
	if _moved_model_order.is_empty():
		return
	var charge_key: String = _moved_model_order.pop_back()
	var key_parts = _charge_key_parts(charge_key)
	moved_models.erase(charge_key)
	if charge_key not in models_to_move:
		models_to_move.append(charge_key)
	# Restore GameState position + rotation
	var origin_pos: Vector2 = _model_origin_positions.get(charge_key, Vector2.ZERO)
	var origin_rot: float = _model_origin_rotations.get(charge_key, 0.0)
	# Multi-step: undo removes ALL of this model's hops — discard its recorded path
	# so it re-drags fresh from the origin with the full charge distance available.
	if origin_pos != Vector2.ZERO:
		_model_charge_paths[charge_key] = [origin_pos]
	else:
		_model_charge_paths[charge_key] = []
	if origin_pos != Vector2.ZERO and active_unit_id != "":
		_update_model_position_in_gamestate(key_parts.unit_id, key_parts.model_id, origin_pos)
		_move_token_visual(key_parts.unit_id, key_parts.model_id, origin_pos, origin_rot)
	# Update charge info label
	if is_instance_valid(charge_info_label):
		charge_info_label.text = _remaining_models_message()
	# The per-model Used/Left readout described the model we just reverted, so
	# reset it — otherwise it keeps showing a distance for a model now back at
	# its origin, which reads as "undo did nothing".
	if is_instance_valid(charge_used_label):
		charge_used_label.text = "Used: 0.0\""
		charge_used_label.modulate = Color.WHITE
	if is_instance_valid(charge_left_label):
		charge_left_label.text = "Left: %.1f\"" % charge_distance
		charge_left_label.modulate = Color.WHITE
	if is_instance_valid(charge_terrain_label):
		charge_terrain_label.visible = false
	# Disable confirm if nothing has been moved
	if confirm_button and is_instance_valid(confirm_button):
		confirm_button.disabled = moved_models.is_empty()
	# Disable undo button if no more moves to undo
	if undo_charge_model_button and is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.disabled = _moved_model_order.is_empty()
	# Keep multi-select rings in sync — the undone model is back at its origin
	if selected_models.size() > 0:
		_update_charge_selection_visuals()
	print("[T-092] Undid charge model %s, restored to %s" % [charge_key, str(origin_pos)])

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# ── Attached-character charge keys ──────────────────────────────────
# The charging unit's attached CHARACTER models are dragged with the squad, but
# their model ids collide with the bodyguard's ("m1" vs "m1"). All movement
# bookkeeping is therefore keyed by a charge key: bare model id for the
# charging unit's own models, "<char_unit_id>:<model_id>" for character models.

func _get_attached_character_ids(of_unit_id: String = "") -> Array:
	var uid = of_unit_id if of_unit_id != "" else active_unit_id
	if uid == "":
		return []
	var unit = GameState.get_unit(uid)
	if unit.is_empty():
		return []
	var out: Array = []
	for cid in unit.get("attachment_data", {}).get("attached_characters", []):
		out.append(str(cid))
	return out

func _charge_model_key(unit_id: String, model_id: String) -> String:
	if unit_id == "" or unit_id == active_unit_id:
		return model_id
	return "%s:%s" % [unit_id, model_id]

func _charge_key_parts(key: String) -> Dictionary:
	# Returns {"unit_id": ..., "model_id": ...} for a charge key.
	var idx = key.find(":")
	if idx == -1:
		return {"unit_id": active_unit_id, "model_id": key}
	return {"unit_id": key.substr(0, idx), "model_id": key.substr(idx + 1)}

func _get_charge_group_model(key: String) -> Dictionary:
	# Model dict (live GameState reference) for a charge key.
	var parts = _charge_key_parts(key)
	var unit = GameState.get_unit(parts.unit_id)
	for model in unit.get("models", []):
		if model.get("id", "") == parts.model_id:
			return model
	return {}

func _get_model_at_position(world_pos: Vector2) -> Dictionary:
	# Find model under the cursor
	print("DEBUG: Looking for model at position ", world_pos, " for unit ", active_unit_id)
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		print("DEBUG: Unit ", active_unit_id, " not found in GameState")
		return {}
	
	print("DEBUG: Unit has ", unit.get("models", []).size(), " models")
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position(model)
		if model_pos == null:
			continue
		
		var base_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var distance = model_pos.distance_to(world_pos)
		print("DEBUG: Model ", model.get("id", ""), " at ", model_pos, " distance: ", distance, " radius: ", base_radius)
		
		if distance <= base_radius:
			print("DEBUG: Found model ", model.get("id", ""))
			return model
	
	print("DEBUG: No model found at position")
	return {}

func _start_model_drag(model: Dictionary, world_pos: Vector2) -> void:
	var model_id = model.get("id", "")
	if dragging_model_source_unit_id == "":
		dragging_model_source_unit_id = active_unit_id
	var charge_key = _charge_model_key(dragging_model_source_unit_id, model_id)
	print("Starting drag for model ", charge_key)

	# Reset snap state for new drag
	snap_active = false
	snap_position = Vector2.ZERO
	snap_target_model_id = ""

	# DEBUG: Verify model data completeness
	print("DEBUG: Model Dictionary keys: ", model.keys())
	print("DEBUG: Model base_type: ", model.get("base_type", "NOT SET"))
	print("DEBUG: Model base_mm: ", model.get("base_mm", "NOT SET"))
	print("DEBUG: Model base_dimensions: ", model.get("base_dimensions", "NOT SET"))
	print("DEBUG: Model rotation: ", model.get("rotation", 0.0))

	# Store the original position in case we need to revert
	var original_pos = _get_model_position(model)
	if original_pos:
		# Store original position in the model for reverting if needed
		dragging_model["original_position"] = original_pos

	# Create ghost visual to show where the model will be moved
	var board_root = SceneRefs.board_root()
	if board_root:
		# Create ghost visual
		ghost_visual = Node2D.new()
		ghost_visual.name = "ChargeGhost_" + model_id
		board_root.add_child(ghost_visual)

		# Use GhostVisual for consistent ghost rendering across all controllers
		var ghost_token = preload("res://scripts/GhostVisual.gd").new()
		var unit = GameState.get_unit(dragging_model_source_unit_id)
		ghost_token.owner_player = unit.get("owner", 1)
		# Set the complete model data for shape handling
		ghost_token.set_model_data(model)
		# Set initial rotation if model has one
		if model.has("rotation"):
			ghost_token.set_base_rotation(model.get("rotation", 0.0))

		# Set ghost appearance
		ghost_token.position = Vector2.ZERO
		ghost_visual.add_child(ghost_token)
		ghost_visual.modulate = Color(0, 1, 0, 0.7)  # Semi-transparent green
		ghost_visual.position = world_pos

		# Create movement line to show the path
		var line = Line2D.new()
		line.width = 2
		line.default_color = Color.YELLOW
		line.add_point(original_pos)
		line.add_point(world_pos)
		board_root.add_child(line)
		movement_lines[charge_key] = line

		# P3-99: Create direction validation visual
		if not charge_direction_visual or not is_instance_valid(charge_direction_visual):
			charge_direction_visual = preload("res://scripts/ChargeDirectionVisual.gd").new()
			board_root.add_child(charge_direction_visual)
			print("P3-99: Created ChargeDirectionVisual for live direction feedback")

		print("DEBUG: Created ghost visual and movement line for ", model_id)

func _update_model_drag(world_pos: Vector2) -> void:
	if not dragging_model:
		return

	var model_id = dragging_model.get("id", "")
	var charge_key = _charge_model_key(dragging_model_source_unit_id, model_id)
	var effective_pos = world_pos  # Position that may be adjusted by snap

	# Base-to-base snap: check if cursor is close enough to snap to a target
	if snap_active:
		# Check if we should break out of snap
		var break_distance_px = Measurement.inches_to_px(SNAP_BREAK_INCHES)
		if world_pos.distance_to(snap_position) > break_distance_px:
			snap_active = false
			snap_target_model_id = ""
			print("DEBUG: Snap broken - cursor moved too far from snap point")
		else:
			effective_pos = snap_position  # Stay snapped

	if not snap_active:
		# Try to engage snap
		var snap_result = _calculate_snap_to_base_contact(dragging_model, world_pos)
		if snap_result.get("snap", false):
			snap_active = true
			snap_position = snap_result["position"]
			snap_target_model_id = snap_result.get("target_model_id", "")
			effective_pos = snap_position
			print("DEBUG: Snapped to base contact with target model ", snap_target_model_id)

	# Update ghost visual position (uses snapped position when active)
	if ghost_visual:
		ghost_visual.position = effective_pos

	# Update movement line
	if charge_key in movement_lines:
		var line = movement_lines[charge_key]
		if line.get_point_count() > 1:
			line.set_point_position(1, effective_pos)

	# Check if position is valid (within charge distance and rules)
	var is_valid = _validate_charge_position(dragging_model, effective_pos, charge_key)

	# Update ghost visual color based on validity and snap state
	if ghost_visual:
		if snap_active:
			ghost_visual.modulate = Color(0, 0.8, 1.0, 0.8)  # Cyan for snapped to base contact
		elif is_valid:
			ghost_visual.modulate = Color(0, 1, 0, 0.7)  # Green for valid
		else:
			ghost_visual.modulate = Color(1, 0, 0, 0.7)  # Red for invalid

	# Calculate distance moved for display (including terrain penalty - T2-8).
	# original_pos is this HOP's start; add the distance already committed on
	# earlier hops so the preview shows the running total against the charge roll.
	var original_pos = dragging_model.get("original_position")
	if original_pos:
		var distance_moved_px = original_pos.distance_to(effective_pos)
		var distance_moved_inches = Measurement.px_to_inches(distance_moved_px)
		var terrain_penalty = _calculate_terrain_penalty_for_path(original_pos, effective_pos)
		var prior_distance = _get_model_charge_accumulated(charge_key)
		var effective_distance = prior_distance + distance_moved_inches + terrain_penalty

		# P3-98: Update distance display with preview (show effective distance including terrain breakdown)
		_update_charge_distance_display_with_preview(effective_distance, is_valid, terrain_penalty)

		# P3-99: Update live direction validation visual
		if charge_direction_visual and is_instance_valid(charge_direction_visual):
			var charge_targets = selected_targets
			if charge_targets.is_empty() and current_phase:
				charge_targets = _get_charge_targets_from_phase(active_unit_id)
			if not charge_targets.is_empty():
				charge_direction_visual.update_direction(effective_pos, original_pos, charge_targets)

func _end_model_drag(world_pos: Vector2) -> void:
	if not dragging_model:
		return

	var model_id = dragging_model.get("id", "")
	var source_unit_id = dragging_model_source_unit_id if dragging_model_source_unit_id != "" else active_unit_id
	var charge_key = _charge_model_key(source_unit_id, model_id)

	# Use snapped position if snap is active
	var final_pos = world_pos
	if snap_active:
		final_pos = snap_position
		print("DEBUG: Using snapped position for model ", charge_key, " at ", final_pos)

	# Reset snap state
	snap_active = false
	snap_position = Vector2.ZERO
	snap_target_model_id = ""

	# Validate final position
	if _validate_charge_position(dragging_model, final_pos, charge_key):
		print("Model ", charge_key, " moved to valid position")

		# Calculate and store distance moved. start_pos is the model's position at
		# the START of this hop (GameState is not updated until below), which is the
		# origin on the first hop and the previous drop on later hops.
		var start_pos = _get_model_position(dragging_model)
		if start_pos:
			# Multi-step: append this hop's endpoint to the model's recorded path so
			# the accumulated distance and the real polyline survive to the confirm.
			# The path's last point is this hop's start (origin on the first hop).
			var hop_path: Array = _model_charge_paths.get(charge_key, [])
			if hop_path.is_empty():
				hop_path = [start_pos]
			hop_path.append(final_pos)
			_model_charge_paths[charge_key] = hop_path

			# Show the TOTAL distance spent across all hops (not just this one) so the
			# player can see how much of the charge roll remains for further steps.
			var accumulated_inches = _get_model_charge_accumulated(charge_key)
			_update_charge_distance_display(model_id, accumulated_inches, 0.0)

		# Store the new position AND rotation
		moved_models[charge_key] = {
			"position": final_pos,
			"rotation": dragging_model.get("rotation", 0.0)
		}
		# T-092: track ordering for per-model undo
		if charge_key in _moved_model_order:
			_moved_model_order.erase(charge_key)
		_moved_model_order.append(charge_key)
		# Enable undo button now that at least one model has moved
		if undo_charge_model_button and is_instance_valid(undo_charge_model_button):
			undo_charge_model_button.disabled = false

		# IMPORTANT: Update GameState FIRST with position and rotation
		# This ensures GameState has the correct data before we update visuals
		print("DEBUG: Updating GameState position and rotation FIRST")
		_update_model_position_in_gamestate(source_unit_id, model_id, final_pos)

		# NOW update the visual token (after GameState has been updated)
		print("DEBUG: Moving token visual after GameState update")
		var model_rotation = dragging_model.get("rotation", 0.0)
		_move_token_visual(source_unit_id, model_id, final_pos, model_rotation)

		# Remove from models to move
		models_to_move.erase(charge_key)

		# Update button state
		if moved_models.size() > 0 and is_instance_valid(confirm_button):
			confirm_button.disabled = false
			print("DEBUG: Confirm button enabled - moved_models.size() = ", moved_models.size())
			print("DEBUG: Confirm button global position: ", confirm_button.global_position)
			print("DEBUG: Confirm button global rect: ", confirm_button.get_global_rect())
			print("DEBUG: Confirm button visible: ", confirm_button.visible)
		else:
			print("DEBUG: Confirm button not enabled - moved_models.size() = ", moved_models.size(), " confirm_button valid = ", is_instance_valid(confirm_button))

		# Update info
		if is_instance_valid(charge_info_label):
			charge_info_label.text = _remaining_models_message()
	else:
		print("Model ", charge_key, " position invalid - reverting")
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Invalid position! Must be within %d\" and reach engagement range" % charge_distance

		# Revert token to original position and rotation if drag was invalid
		var original_pos = dragging_model.get("original_position")
		if original_pos:
			# Get original rotation from GameState
			var original_rotation = 0.0
			var unit = GameState.get_unit(source_unit_id)
			for model in unit.get("models", []):
				if model.get("id", "") == model_id:
					original_rotation = model.get("rotation", 0.0)
					break
			_move_token_visual(source_unit_id, model_id, original_pos, original_rotation)
			print("DEBUG: Reverted token ", charge_key, " to original position ", original_pos, " and rotation ", rad_to_deg(original_rotation), " degrees")

	# Clean up ghost visual and movement line
	if ghost_visual:
		ghost_visual.queue_free()
		ghost_visual = null

	# Clean up movement line
	if charge_key in movement_lines:
		var line = movement_lines[charge_key]
		if is_instance_valid(line):
			line.queue_free()
		movement_lines.erase(charge_key)

	# P3-99: Deactivate direction visual (hide but keep for next drag)
	if charge_direction_visual and is_instance_valid(charge_direction_visual):
		charge_direction_visual.deactivate()

	dragging_model = null
	dragging_model_source_unit_id = ""

func _move_token_visual(unit_id: String, model_id: String, new_pos: Vector2, rotation: float = 0.0) -> void:
	# Find and move the actual token visual on screen
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		print("ERROR: TokenLayer not found, cannot move token visual")
		return
	
	print("DEBUG: Looking for token with unit_id=", unit_id, " model_id=", model_id)
	print("DEBUG: TokenLayer has ", token_layer.get_child_count(), " children")
	
	# Find the specific token for this model
	var found = false
	for i in range(token_layer.get_child_count()):
		var child = token_layer.get_child(i)
		
		# Debug what we're looking at
		if child.has_meta("unit_id") and child.has_meta("model_id"):
			var token_unit_id = child.get_meta("unit_id")
			var token_model_id = child.get_meta("model_id")
			print("DEBUG: Child ", i, " has unit_id=", token_unit_id, " model_id=", token_model_id)
			
			if token_unit_id == unit_id and token_model_id == model_id:
				# Found the token! Check current state
				print("DEBUG: FOUND TOKEN! Current position: ", child.global_position)
				print("DEBUG: Current visibility: ", child.visible, " modulate: ", child.modulate)
				
				# Move it using local position (since token is child of TokenLayer)
				child.position = new_pos
				child.visible = true  # Ensure it stays visible
				child.modulate = Color.WHITE  # Ensure it's not faded
				child.z_index = 10  # Bring to front to ensure it's not hidden

				# Always update rotation when we're moving a model during charge
				# Priority: Use dragging_model rotation if available, otherwise use passed rotation
				var new_rotation = 0.0
				var should_update_rotation = false

				if dragging_model and dragging_model.get("id", "") == model_id:
					# This is the model we're dragging - use its current rotation
					new_rotation = dragging_model.get("rotation", 0.0)
					should_update_rotation = true
					print("DEBUG: Using rotation from dragging_model: ", rad_to_deg(new_rotation), " degrees")
				else:
					# Use the rotation parameter that was passed
					new_rotation = rotation
					should_update_rotation = true
					print("DEBUG: Using passed rotation: ", rad_to_deg(new_rotation), " degrees")

				# Apply rotation update if needed. `child` IS the TokenVisual (meta
				# is set directly on it by Main._create_token_visual, not on a
				# wrapper) — child.get_child(0) is its "Label" child node (added in
				# TokenVisual._ready()), not a nested TokenVisual, so reaching into
				# it silently no-oped every rotation update here.
				if should_update_rotation and child.has_method("set_model_data"):
					# IMPORTANT: Use dragging_model if available (has correct rotation)
					var model_data = null
					if dragging_model and dragging_model.get("id", "") == model_id:
						# Use dragging_model which has all the current data
						model_data = dragging_model.duplicate()
					else:
						# Fall back to GameState but update rotation
						var unit = GameState.get_unit(unit_id)
						for model in unit.get("models", []):
							if model.get("id", "") == model_id:
								model_data = model.duplicate()
								model_data["rotation"] = new_rotation
								break

					if model_data:
						child.set_model_data(model_data)
						child.queue_redraw()
						print("DEBUG: Updated token rotation to ", rad_to_deg(new_rotation), " degrees")
					else:
						print("WARNING: No model data found for rotation update")

				# Double-check final state
				print("DEBUG: Token moved to position: ", child.position)
				print("DEBUG: Token global_position: ", child.global_position)
				print("DEBUG: Final visibility: ", child.visible, " modulate: ", child.modulate)
				print("DEBUG: Token name: ", child.name, " z_index: ", child.z_index)
				found = true
				return
	
	if not found:
		print("WARNING: Could not find token visual for unit=", unit_id, " model=", model_id)
		print("DEBUG: Available tokens in TokenLayer:")
		for i in range(token_layer.get_child_count()):
			var child = token_layer.get_child(i)
			if child.has_meta("unit_id") and child.has_meta("model_id"):
				print("  - unit_id=", child.get_meta("unit_id"), " model_id=", child.get_meta("model_id"))

func _update_model_position_in_gamestate(unit_id: String, model_id: String, new_pos: Vector2) -> void:
	# Directly update the model position in GameState for immediate persistence
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		print("ERROR: Cannot find unit ", unit_id, " in GameState")
		return

	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if model.get("id", "") == model_id:
			# Update the position directly in GameState
			GameState.state.units[unit_id].models[i].position = {"x": new_pos.x, "y": new_pos.y}

			# Also update rotation if this model has been rotated
			if dragging_model and dragging_model.get("id", "") == model_id:
				var new_rotation = dragging_model.get("rotation", 0.0)
				GameState.state.units[unit_id].models[i].rotation = new_rotation
				print("DEBUG: Updated GameState position and rotation for ", model_id, " to ", new_pos, " and ", rad_to_deg(new_rotation), " degrees")
				# NOTE: We don't update the token visual here because _move_token_visual will be called after this
			else:
				print("DEBUG: Updated GameState position for ", model_id, " to ", new_pos)
			return

	print("ERROR: Could not find model ", model_id, " in unit ", unit_id)

func _calculate_snap_to_base_contact(model: Dictionary, cursor_pos: Vector2) -> Dictionary:
	# Calculate if the cursor is close enough to snap to base-to-base contact with a target model.
	# Returns {"snap": true, "position": Vector2, "target_model_id": String} or {"snap": false}

	var charge_targets = selected_targets
	if charge_targets.is_empty() and current_phase:
		charge_targets = _get_charge_targets_from_phase(active_unit_id)
	if charge_targets.is_empty():
		return {"snap": false}

	var model_shape = Measurement.create_base_shape(model)
	var model_rotation = model.get("rotation", 0.0)
	var model_id = model.get("id", "")
	# Only ever called with dragging_model, so the drag's source unit gives the
	# charge key (self-skip + wall keywords must use the model's OWN unit).
	var snap_source_unit = dragging_model_source_unit_id if dragging_model_source_unit_id != "" else active_unit_id
	var snap_charge_key = _charge_model_key(snap_source_unit, model_id)

	var best_snap = {"snap": false}
	var best_distance = INF

	for target_id in charge_targets:
		var target_unit = GameState.get_unit(target_id)
		if target_unit.is_empty():
			continue

		for target_model in target_unit.get("models", []):
			if not target_model.get("alive", true):
				continue

			var target_pos = _get_model_position(target_model)
			if target_pos == null or target_pos == Vector2.ZERO:
				continue

			var target_model_id_str = target_model.get("id", "")

			# Calculate the edge-to-edge distance if we placed our model at cursor_pos
			var test_model = model.duplicate()
			test_model["position"] = cursor_pos
			var edge_distance_px = Measurement.model_to_model_distance_px(test_model, target_model)
			var edge_distance_inches = Measurement.px_to_inches(edge_distance_px)

			# If cursor is already overlapping the target or within snap zone, trigger snap
			if edge_distance_inches <= SNAP_ZONE_INCHES:
				# Calculate the snap position: place our model's base touching the target's base
				# Direction from target center to cursor position
				var direction = (cursor_pos - target_pos).normalized()
				if direction == Vector2.ZERO:
					direction = Vector2.RIGHT  # Default direction if exactly on top

				# Use shape-aware edge point calculation to find exact contact point
				var target_shape = Measurement.create_base_shape(target_model)
				var target_rotation = target_model.get("rotation", 0.0)

				# Find the closest edge point on the target model's base in the direction of the cursor
				var target_edge = target_shape.get_closest_edge_point(cursor_pos, target_pos, target_rotation)

				# Find how far from the target edge point our model's center needs to be
				# We need to place our model so its edge touches the target edge
				# To do this: place our center along the direction, then check/adjust
				var approx_snap_pos = target_edge + direction * _get_model_half_size(model)

				# Refine: iteratively find exact base contact position
				var snap_pos = _refine_snap_position(model, target_model, approx_snap_pos, target_pos, direction)

				# Check if this snap position is within charge movement range
				var original_pos = model.get("original_position")
				if original_pos:
					var snap_distance_px = original_pos.distance_to(snap_pos)
					var snap_distance_inches = Measurement.px_to_inches(snap_distance_px)
					var terrain_penalty = _calculate_terrain_penalty_for_path(original_pos, snap_pos)
					if snap_distance_inches + terrain_penalty > charge_distance:
						continue  # Can't reach this snap point within charge distance

				# Check if snap position would overlap with friendly models
				var would_overlap = _check_position_would_overlap(model, snap_pos, snap_charge_key)
				if would_overlap:
					continue  # Can't snap here, would overlap

				# Track the closest snap candidate
				var cursor_to_snap = cursor_pos.distance_to(snap_pos)
				if cursor_to_snap < best_distance:
					best_distance = cursor_to_snap
					best_snap = {
						"snap": true,
						"position": snap_pos,
						"target_model_id": target_model_id_str
					}

	return best_snap

func _get_model_half_size(model: Dictionary) -> float:
	# Get approximate half-size of a model base in pixels (for snap positioning)
	var base_type = model.get("base_type", "circular")
	var base_mm = model.get("base_mm", 32)
	if base_type == "circular":
		return Measurement.base_radius_px(base_mm)
	else:
		# For non-circular bases, use the average of dimensions
		var dims = model.get("base_dimensions", {})
		var length_mm = dims.get("length", base_mm)
		var width_mm = dims.get("width", base_mm * 0.6)
		return Measurement.mm_to_px((length_mm + width_mm) / 4.0)

func _refine_snap_position(model: Dictionary, target_model: Dictionary, initial_pos: Vector2, target_pos: Vector2, direction: Vector2) -> Vector2:
	# Iteratively refine the snap position so the model base exactly touches the target base.
	# Direction points from target center toward where we want to place our model.
	# We binary-search along the direction to find the exact contact point.
	var test = model.duplicate()

	# Start with a position far enough to definitely not overlap, and one close enough to overlap
	var far_pos = initial_pos
	var near_pos = target_pos  # Definitely overlapping (same center)

	# First verify far_pos is actually not overlapping; if it is, push it out more
	test["position"] = far_pos
	var far_dist = Measurement.model_to_model_distance_px(test, target_model)
	if far_dist <= 0:
		far_pos = target_pos + direction * (target_pos.distance_to(initial_pos) + Measurement.inches_to_px(2.0))

	# Binary search: find position where edge distance is ~0
	for i in range(16):
		var mid_pos = (far_pos + near_pos) * 0.5
		test["position"] = mid_pos
		var edge_dist = Measurement.model_to_model_distance_px(test, target_model)

		if abs(edge_dist) < 0.5:  # Sub-pixel accuracy
			return mid_pos

		if edge_dist > 0:
			# Still separated, move closer (toward near_pos)
			far_pos = mid_pos
		else:
			# Overlapping, move away (toward far_pos)
			near_pos = mid_pos

	# Return the midpoint of our final range (should be very close to contact)
	return (far_pos + near_pos) * 0.5

# Multi-step charge: total inches already committed by a model across every
# previous hop this charge (straight-line + per-segment terrain penalty), matching
# how ChargePhase measures the confirmed polyline path. Returns 0 for a model that
# is still at its origin (path has only the origin point).
func _get_model_charge_accumulated(charge_key: String) -> float:
	var path = _model_charge_paths.get(charge_key, [])
	if path.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(1, path.size()):
		total += Measurement.px_to_inches(path[i - 1].distance_to(path[i]))
		total += _calculate_terrain_penalty_for_path(path[i - 1], path[i])
	return total

# Label text for the charge-move panel. Attached character models left unmoved
# are not blocking — they auto-ride the squad's move on confirm — so call that
# out instead of implying the player MUST drag them.
func _remaining_models_message() -> String:
	if models_to_move.is_empty():
		return "All models moved! Click 'Confirm Charge Moves' to complete"
	var char_keys_remaining := 0
	for key in models_to_move:
		if _charge_key_parts(key).unit_id != active_unit_id:
			char_keys_remaining += 1
	if char_keys_remaining == models_to_move.size():
		return "Squad moved! Drag the leader too, or confirm — unmoved leaders follow automatically"
	return "Move remaining %d models into engagement range" % models_to_move.size()

func _validate_charge_position(model: Dictionary, new_pos: Vector2, charge_key: String = "", group_overrides: Dictionary = {}) -> bool:
	# group_overrides (model_id -> Vector2): prospective positions of squadmates
	# moving in the same group drag — they occupy those spots, not their current ones.
	var model_id = model.get("id", "")
	# Movement bookkeeping is keyed by charge key ("<unit>:<model>" for attached
	# character models). Callers that predate keys pass nothing — fall back to
	# the bare model id, which is the key for the charging unit's own models.
	if charge_key == "":
		charge_key = model_id

	# Check 1: Movement distance (including terrain penalty - T2-8).
	# old_pos is the model's CURRENT position — its origin on the first hop, or the
	# previous drop position on later hops of a multi-step charge move.
	var old_pos = _get_model_position(model)
	if old_pos == null:
		return false

	var distance_moved = Measurement.px_to_inches(old_pos.distance_to(new_pos))

	# T2-8: Add terrain vertical distance penalty
	var terrain_penalty = _calculate_terrain_penalty_for_path(old_pos, new_pos)
	var effective_distance = distance_moved + terrain_penalty

	# Multi-step: this hop is capped by whatever charge distance remains after the
	# hops already committed — the whole path must fit inside the charge roll, just
	# like accumulated movement in the Movement phase.
	var prior_distance = _get_model_charge_accumulated(charge_key)
	var total_distance = prior_distance + effective_distance

	if total_distance > charge_distance + MOVEMENT_CAP_EPSILON:
		if terrain_penalty > 0.0:
			print("Movement too far with terrain: %.1f\" prior + %.1f\" + %.1f\" terrain = %.1f\" > %d\"" % [
				prior_distance, distance_moved, terrain_penalty, total_distance, charge_distance])
		else:
			print("Movement too far: %.1f\" prior + %.1f\" = %.1f\" > %d\"" % [
				prior_distance, distance_moved, total_distance, charge_distance])
		return false

	# Check 2: Model overlap detection
	if _check_position_would_overlap(model, new_pos, charge_key, group_overrides):
		print("Position would overlap with another model")
		return false

	# Check 2b (issue #87): no part of the model's base may extend off
	# the battlefield during a charge move.
	if Measurement.model_outside_board(new_pos, model):
		print("Charge move would place model off the board")
		return false

	# Check 3: Must end closer to at least one declared target (10e rule).
	# The rule is about the WHOLE charge move, so this compares the candidate
	# position to the model's PRE-CHARGE ORIGIN, not to the current hop's start.
	# That lets a multi-step move take an intermediate hop that isn't itself closer
	# than the previous hop (e.g. a sideways step around terrain) as long as the
	# model still ends up closer than where it began. Final enforcement is in
	# ChargePhase against path[0] -> path[-1]. On the first hop origin == old_pos,
	# so single-step behaviour is unchanged.
	var charge_origin = _model_origin_positions.get(charge_key, old_pos)
	var model_at_old = model.duplicate()
	model_at_old["position"] = charge_origin
	var model_at_new = model.duplicate()
	model_at_new["position"] = new_pos

	var charge_targets = selected_targets
	if charge_targets.is_empty() and current_phase:
		charge_targets = _get_charge_targets_from_phase(active_unit_id)

	# Only enforce if the model actually moved a meaningful distance from its origin
	if charge_origin.distance_to(new_pos) > 1.0 and not charge_targets.is_empty():  # > 1 pixel
		var ends_closer = false
		for target_id in charge_targets:
			var target = GameState.get_unit(target_id)
			if target.is_empty():
				continue
			for target_model in target.get("models", []):
				if not target_model.get("alive", true):
					continue
				var start_dist = Measurement.model_to_model_distance_inches(model_at_old, target_model)
				var end_dist = Measurement.model_to_model_distance_inches(model_at_new, target_model)
				if end_dist < start_dist:
					ends_closer = true
					break
			if ends_closer:
				break
		if not ends_closer:
			print("T3-8: Model must end charge move closer to at least one charge target")
			return false

	print("DEBUG: Model position validation passed for individual drag")

	return true

func _on_confirm_charge_moves() -> void:
	print("DEBUG: _on_confirm_charge_moves called!")
	print("Confirming charge moves for ", active_unit_id)

	# Build the per-model paths and rotations for the charge action.
	# Keys pass through as-is: bare model ids for the charging unit's models,
	# "<char_unit_id>:<model_id>" for attached character models the player
	# dragged (ChargePhase resolves both via _resolve_charge_path_ref).
	var per_model_paths = {}
	var per_model_rotations = {}
	print("DEBUG: Building per_model_paths from moved_models: ", moved_models.keys())
	for charge_key in moved_models:
		var key_parts = _charge_key_parts(charge_key)
		var move_data = moved_models[charge_key]
		var new_pos = move_data["position"] if move_data is Dictionary else move_data
		var new_rotation = move_data["rotation"] if move_data is Dictionary and move_data.has("rotation") else 0.0
		print("DEBUG: Processing moved model ", charge_key, " to position ", new_pos, " with rotation ", rad_to_deg(new_rotation), " degrees")
		# Path start must be the PRE-DRAG origin (T-092 cache). The drag
		# already wrote the drop position into GameState (_end_model_drag), so
		# reading the live model here yields start == end — a degenerate path
		# the phase validator rightly rejects ("must end closer to a target").
		var old_pos = _model_origin_positions.get(charge_key, null)
		if old_pos == null:
			var unit = GameState.get_unit(key_parts.unit_id)
			for model in unit.get("models", []):
				if model.get("id", "") == key_parts.model_id:
					old_pos = _get_model_position(model)
					break

		# Multi-step: emit the FULL recorded hop path (origin -> ... -> final) so the
		# phase validates the real polyline the player dragged — its per-segment
		# terrain sweep and total-distance measure only make sense on the actual
		# route. A straight origin->final line could cut back through terrain the
		# player routed around and be wrongly rejected (or wrongly accepted).
		var hop_path: Array = _model_charge_paths.get(charge_key, [])
		if hop_path.size() >= 2 and old_pos and new_pos:
			var pts: Array = []
			for p in hop_path:
				pts.append([p.x, p.y])
			# Pin the endpoints to the authoritative origin/drop positions.
			pts[0] = [old_pos.x, old_pos.y]
			pts[pts.size() - 1] = [new_pos.x, new_pos.y]
			per_model_paths[charge_key] = pts
			per_model_rotations[charge_key] = new_rotation
			print("DEBUG: Created multi-step path for ", charge_key, " (%d points): " % pts.size(), per_model_paths[charge_key], " with rotation: ", rad_to_deg(new_rotation))
		elif old_pos and new_pos:
			per_model_paths[charge_key] = [[old_pos.x, old_pos.y], [new_pos.x, new_pos.y]]
			per_model_rotations[charge_key] = new_rotation
			print("DEBUG: Created path for ", charge_key, ": ", per_model_paths[charge_key], " with rotation: ", rad_to_deg(new_rotation))
		else:
			print("DEBUG: Failed to create path for ", charge_key, " - old_pos: ", old_pos, " new_pos: ", new_pos)

	# The APPLY action is the authoritative state mutation: restore the
	# pre-drag origins so the phase validates against the real start state
	# and its result diffs perform the actual move. Token visuals stay at
	# the drop position (no flicker); a validation failure snaps them back
	# via charge_resolved.
	for charge_key in per_model_paths:
		var origin = _model_origin_positions.get(charge_key, null)
		if origin != null:
			var key_parts = _charge_key_parts(charge_key)
			_update_model_position_in_gamestate(key_parts.unit_id, key_parts.model_id, origin)

	# A Heroic Intervention counter-charge has its own apply action — its
	# charge data lives in heroic_intervention_pending_charge, so
	# APPLY_CHARGE_MOVE would fail with "No pending charge data found". It
	# also never sends COMPLETE_UNIT_CHARGE (that is charger bookkeeping).
	var is_hi_move: bool = current_phase != null \
		and str(current_phase.get("heroic_intervention_unit_id")) == active_unit_id \
		and active_unit_id != ""

	# Store the unit_id so the charge_resolved handler can send COMPLETE_UNIT_CHARGE
	if not is_hi_move:
		_pending_complete_unit_id = active_unit_id

	# Send APPLY_CHARGE_MOVE action with the paths and rotations we built
	# NOTE: COMPLETE_UNIT_CHARGE is now sent from _on_charge_resolved() after
	# the server confirms the charge succeeded, preventing state corruption if
	# APPLY_CHARGE_MOVE fails validation.
	var action = {
		"type": "APPLY_HEROIC_INTERVENTION_MOVE" if is_hi_move else "APPLY_CHARGE_MOVE",
		"actor_unit_id": active_unit_id,
		"payload": {
			"per_model_paths": per_model_paths,
			"per_model_rotations": per_model_rotations
		}
	}

	# ISS-049 (11e 11.02): targets are SELECTED WITH THE MOVE — send the enemy
	# units the final positions actually engage. Without this the server keeps
	# whatever survived the pre-roll declaration; if the roll dropped them all,
	# the confirm was rejected ("No charge targets selected") with no UI to fix it.
	if GameConstants.edition >= 11 and not is_hi_move:
		var inferred_targets = _infer_11e_targets_from_moves(per_model_paths)
		if not inferred_targets.is_empty():
			action.payload["target_unit_ids"] = inferred_targets
			print("ChargeController: [11e] targets selected with the move: ", inferred_targets)

	print("Requesting apply charge move: ", action)
	_last_apply_rejection = {}
	charge_action_requested.emit(action)

	# Single-player processes the action synchronously — if the server rejected
	# the move (Main calls on_charge_move_rejected), the charge and its roll are
	# still pending: keep movement mode alive so the player can re-position,
	# instead of silently pretending the charge concluded.
	if not _last_apply_rejection.is_empty():
		_last_apply_rejection = {}
		moved_models.clear()
		_moved_model_order.clear()
		# Token visuals are re-synced to GameState (pre-drag origins) by
		# Main.update_after_charge_action(); drag ghosts/lines are stale now.
		_clear_movement_visuals()
		# Re-arm every charging model for re-positioning from its origin: their
		# GameState positions have been reset to the pre-charge origins, so clear
		# each recorded hop path back to [origin] and make them all pickable again
		# (they were removed from models_to_move as they were dragged, and
		# moved_models was just cleared, so without this nothing would be draggable).
		models_to_move.clear()
		for mid in _model_origin_positions:
			if mid not in models_to_move:
				models_to_move.append(mid)
			_model_charge_paths[mid] = [_model_origin_positions[mid]]
		awaiting_movement = true
		_pending_complete_unit_id = ""
		if is_instance_valid(confirm_button):
			confirm_button.visible = true
		_update_button_states()
		return

	# Clear the movement state
	moved_models.clear()
	models_to_move.clear()

	# Reset movement state
	awaiting_movement = false
	_clear_movement_visuals()
	if is_instance_valid(confirm_button):
		confirm_button.visible = false
	# T-092 fix: hide the Snap to Contact + Undo buttons together with confirm
	# so they don't linger visible + clickable (and silently no-op) once this
	# charge is done. _update_ui_for_next_charge() → _update_button_states()
	# also enforces this, but hide here so there's no one-frame flash.
	if is_instance_valid(auto_path_charge_button):
		auto_path_charge_button.visible = false
	if is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.visible = false

	# Update UI for next charge selection
	_update_ui_for_next_charge()

func on_charge_move_rejected(action: Dictionary, result: Dictionary) -> void:
	"""Called by Main when the server rejects APPLY_CHARGE_MOVE validation.
	Records the rejection (consumed by _on_confirm_charge_moves to keep the
	movement mode alive) and tells the player why in the dice log."""
	_last_apply_rejection = {"action": action, "result": result}
	var errs: Array = result.get("errors", [])
	var msg: String = str(errs[0]) if not errs.is_empty() else str(result.get("error", "move does not satisfy charge constraints"))
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=red]Charge move rejected:[/color] %s — re-position the models and confirm again.\n" % msg)
	if is_instance_valid(charge_info_label):
		charge_info_label.text = "Move rejected: %s" % msg
	print("ChargeController: charge move rejected — %s" % msg)

func _infer_11e_targets_from_moves(per_model_paths: Dictionary) -> Array:
	"""11e 11.02: the charge targets are the enemy units the unit actually ends
	engaged with. Derive them from the final model positions; when the phase's
	selectable list is available (host), filter to it so an accidental brush
	against a non-selectable unit still surfaces as a non-target-ER error."""
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return []

	# Final-position model dicts for the shape-aware ER test. Keys may name
	# attached character models ("<char_unit>:<model>") — resolve from the
	# model's own unit so its base shape is right.
	var final_models: Array = []
	for charge_key in per_model_paths:
		var path = per_model_paths[charge_key]
		if path is Array and path.size() > 0:
			var model = _get_charge_group_model(charge_key)
			if model.is_empty():
				continue
			var at_final = model.duplicate()
			at_final["position"] = Vector2(path[-1][0], path[-1][1])
			final_models.append(at_final)
	if final_models.is_empty():
		return []

	var selectable: Array = []
	if current_phase != null and current_phase.has_method("get_pending_charges"):
		var pending = current_phase.get_pending_charges()
		if pending.has(active_unit_id):
			selectable = pending[active_unit_id].get("selectable_targets", [])

	var my_owner = int(unit.get("owner", 0))
	var out: Array = []
	var er_inches = GameConstants.engagement_range_inches()
	for enemy_id in GameState.state.get("units", {}):
		var enemy = GameState.state.units[enemy_id]
		if int(enemy.get("owner", 0)) == my_owner:
			continue
		if not selectable.is_empty() and not (enemy_id in selectable):
			continue
		var engaged := false
		for fm in final_models:
			for em in enemy.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				if Measurement.is_in_engagement_range_shape_aware(fm, em, er_inches):
					engaged = true
					break
			if engaged:
				break
		if engaged:
			out.append(enemy_id)
	return out

func _on_declare_charge_pressed() -> void:
	if active_unit_id == "" or selected_targets.is_empty():
		return
	
	# DEBUG: Log positions before charge declaration
	print("=== CHARGE DEBUG: Before Declare Charge ===")
	_log_unit_positions(active_unit_id, "CHARGING UNIT")
	for target_id in selected_targets:
		_log_unit_positions(target_id, "TARGET UNIT")
	print("=== End Position Logging ===")
	
	var action = {
		"type": "DECLARE_CHARGE",
		"actor_unit_id": active_unit_id,
		"payload": {
			# duplicate(): the phase stores this array in pending_charges. Passing
			# the live selected_targets reference would let every later clear()
			# (unit re-select, next-charge reset) silently wipe the declared
			# targets out of the pending charge.
			"target_unit_ids": selected_targets.duplicate()
		}
	}

	print("Requesting charge declaration: ", action)
	charge_action_requested.emit(action)

	# Update state
	awaiting_roll = true
	# The declaration is committed — lock the rows so idle clicks can't desync
	# the highlighted targets from the declared charge. Rows come back enabled
	# with the next _refresh_target_list (unit re-select / next charge).
	_set_target_list_locked(true)
	_clear_charge_trajectory_preview()  # P3-127: Clear trajectory once charge is declared
	_update_button_states()

func _set_target_list_locked(locked: bool) -> void:
	if not is_instance_valid(target_list):
		return
	for i in range(target_list.get_item_count()):
		target_list.set_item_disabled(i, locked)

func _on_roll_charge_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "CHARGE_ROLL",
		"actor_unit_id": active_unit_id
	}
	
	print("Requesting charge roll: ", action)
	charge_action_requested.emit(action)

func _on_skip_charge_pressed() -> void:
	if active_unit_id == "":
		return
	
	var action = {
		"type": "SKIP_CHARGE",
		"actor_unit_id": active_unit_id
	}
	
	print("Requesting skip charge: ", action)
	charge_action_requested.emit(action)
	
	# Check for more eligible units
	_update_ui_for_next_charge()

func _on_next_unit_pressed() -> void:
	_reset_unit_selection()
	_refresh_ui()

func _on_end_phase_pressed() -> void:
	var action = {
		"type": "END_CHARGE"
	}
	
	print("Requesting end charge phase: ", action)
	charge_action_requested.emit(action)

func _update_ui_for_next_charge() -> void:
	# Clear current unit selection
	active_unit_id = ""
	selected_targets.clear()
	eligible_targets.clear()
	awaiting_roll = false
	awaiting_movement = false
	
	if is_instance_valid(unit_selector):
		unit_selector.deselect_all()
	if is_instance_valid(target_list):
		target_list.clear()
	_clear_highlights()
	_clear_charge_trajectory_preview()  # P3-127
	_clear_charge_range_circle()  # clear 12" ring / per-model reach rings
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()

	# Reset button states for charge buttons (keep them visible but disabled initially)
	if is_instance_valid(declare_button):
		declare_button.visible = true
		declare_button.disabled = true
	if is_instance_valid(roll_button):
		roll_button.visible = true
		roll_button.disabled = true
	if is_instance_valid(skip_button):
		skip_button.visible = true
		skip_button.disabled = true
	
	# Hide charge distance display
	_hide_charge_distance_display()
	
	# Ensure the charge panel and buttons are visible
	_ensure_charge_panel_visible()
	_ensure_charge_buttons_exist()
	
	# Check if more units can charge (only those with a target within 12", to
	# match what UNITS THAT CAN CHARGE now shows).
	if current_phase and is_instance_valid(current_phase):
		var eligible_units = _filter_units_with_charge_targets(current_phase.get_eligible_charge_units())
		if eligible_units.size() > 0:
			# Immediately show available units and update status
			if is_instance_valid(charge_info_label):
				charge_info_label.text = "Charge complete! Select another unit to charge or end phase."
			_update_charge_status()
			_refresh_ui()  # Refresh immediately to show available units
			
			# Hide next unit button since units are already available
			if is_instance_valid(next_unit_button):
				next_unit_button.visible = false
		else:
			# No more units can charge
			if is_instance_valid(next_unit_button):
				next_unit_button.visible = false
			if is_instance_valid(charge_info_label):
				charge_info_label.text = "All eligible units have charged."
			_update_charge_status()
			_refresh_ui()
	else:
		_refresh_ui()

func _ensure_charge_buttons_exist() -> void:
	# Make sure charge action buttons exist and are properly set up
	if not hud_bottom:
		print("ERROR: No hud_bottom reference in _ensure_charge_buttons_exist")
		return
		
	var main_container = hud_bottom.get_node_or_null("HBoxContainer")
	if not main_container:
		print("ERROR: No HBoxContainer in HUD_Bottom")
		return
		
	var charge_controls = main_container.get_node_or_null("ChargeControls")
	
	# If ChargeControls container doesn't exist or buttons are missing, recreate them
	if not charge_controls or not is_instance_valid(declare_button) or not is_instance_valid(roll_button) or not is_instance_valid(skip_button):
		print("DEBUG: Charge buttons missing, recreating bottom HUD")
		_setup_bottom_hud()
		return
	
	# Ensure the container and all buttons are visible
	charge_controls.visible = true
	
	if is_instance_valid(declare_button):
		declare_button.visible = true
		print("DEBUG: Declare button ensured visible")
	else:
		print("ERROR: Declare button not valid!")
		
	if is_instance_valid(roll_button):
		roll_button.visible = true
		print("DEBUG: Roll button ensured visible")
	else:
		print("ERROR: Roll button not valid!")
		
	if is_instance_valid(skip_button):
		skip_button.visible = true
		print("DEBUG: Skip button ensured visible")
	else:
		print("ERROR: Skip button not valid!")

func _ensure_charge_panel_visible() -> void:
	# Make sure the charge panel and its contents are visible
	if not hud_right:
		print("ERROR: No hud_right reference")
		return
		
	var container = hud_right.get_node_or_null("VBoxContainer")
	if not container:
		print("DEBUG: No VBoxContainer found, recreating right panel")
		_setup_right_panel()
		return
	
	var charge_scroll = container.get_node_or_null("ChargeScrollContainer")
	if not charge_scroll:
		print("DEBUG: No ChargeScrollContainer found, recreating right panel")
		_setup_right_panel()
		return
	
	var charge_panel = charge_scroll.get_node_or_null("ChargePanel")
	if not charge_panel:
		print("DEBUG: No ChargePanel found, recreating right panel")
		_setup_right_panel()
		return
	
	# Ensure all components are visible
	hud_right.visible = true
	container.visible = true
	charge_scroll.visible = true
	charge_panel.visible = true
	
	# Also ensure unit_selector exists and is visible
	if is_instance_valid(unit_selector):
		unit_selector.visible = true
		print("DEBUG: Charge panel hierarchy made visible, unit_selector ready")
	else:
		print("ERROR: unit_selector not valid after ensuring panel visibility")
		_setup_right_panel()
		
	# Ensure HUD_Bottom and charge buttons are visible
	if hud_bottom:
		hud_bottom.visible = true
		var bottom_container = hud_bottom.get_node_or_null("HBoxContainer")
		if bottom_container:
			bottom_container.visible = true
			var charge_controls = bottom_container.get_node_or_null("ChargeControls")
			if charge_controls:
				charge_controls.visible = true
				print("DEBUG: Bottom HUD charge controls made visible")
				
	# Ensure charge action buttons are visible
	if is_instance_valid(declare_button):
		declare_button.visible = true
		print("DEBUG: Declare button made visible")
	if is_instance_valid(roll_button):
		roll_button.visible = true
		print("DEBUG: Roll button made visible") 
	if is_instance_valid(skip_button):
		skip_button.visible = true
		print("DEBUG: Skip button made visible")

func _update_charge_status() -> void:
	if not current_phase or not is_instance_valid(current_phase):
		return

	var completed = current_phase.get_completed_charges().size()
	# Count only units with a target within 12", matching the filtered list.
	var eligible = _filter_units_with_charge_targets(current_phase.get_eligible_charge_units()).size()

	if is_instance_valid(charge_status_label):
		charge_status_label.text = "Charges: %d completed, %d eligible" % [completed, eligible]

	# Also refresh failed charges display
	_refresh_failed_charges_display()

func _refresh_failed_charges_display() -> void:
	if not is_instance_valid(failed_charges_container):
		return
	if not current_phase or not current_phase.has_method("get_failed_charge_attempts"):
		return

	var failures = current_phase.get_failed_charge_attempts()

	# Clear existing children
	for child in failed_charges_container.get_children():
		child.queue_free()

	if failures.is_empty():
		var no_failures_label = Label.new()
		no_failures_label.name = "NoFailuresLabel"
		no_failures_label.text = "No failed charges yet"
		no_failures_label.add_theme_font_size_override("font_size", 11)
		no_failures_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		failed_charges_container.add_child(no_failures_label)
		return

	for failure in failures:
		var entry = _create_failure_tooltip_entry(failure)
		failed_charges_container.add_child(entry)

func _create_failure_tooltip_entry(failure: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()

	# Style the panel with a subtle dark background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.1, 0.9)
	style.border_color = Color(0.6, 0.2, 0.2, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	# Header line: [CATEGORY] Unit Name (rolled X")
	var header = RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.custom_minimum_size = Vector2(220, 0)

	var unit_name = failure.get("unit_name", failure.get("unit_id", "Unknown"))
	var roll = failure.get("roll", 0)
	var primary_cat = failure.get("primary_category", "UNKNOWN")
	var cat_color = _get_category_color(primary_cat)
	var cat_tag = "[color=%s][%s][/color]" % [cat_color, primary_cat]

	header.text = "%s %s (rolled %d\")" % [cat_tag, unit_name, roll]
	vbox.add_child(header)

	# Detail lines for each categorized error
	var categorized = failure.get("categorized_errors", [])
	for cat_error in categorized:
		var detail_label = RichTextLabel.new()
		detail_label.bbcode_enabled = true
		detail_label.fit_content = true
		detail_label.scroll_active = false
		detail_label.custom_minimum_size = Vector2(220, 0)

		var cat = cat_error.get("category", "UNKNOWN")
		var detail = cat_error.get("detail", "")
		var detail_color = _get_category_color(cat)
		detail_label.text = " [color=%s]•[/color] %s" % [detail_color, detail]
		vbox.add_child(detail_label)

	# Tooltip text: shows the full rule explanation on hover
	var tooltip_lines = []
	var seen_categories = {}
	for cat_error in categorized:
		var cat = cat_error.get("category", "")
		if cat != "" and not seen_categories.has(cat):
			seen_categories[cat] = true
			if current_phase and current_phase.has_method("get_failure_category_tooltip"):
				tooltip_lines.append("[%s] %s" % [cat, current_phase.get_failure_category_tooltip(cat)])
	if tooltip_lines.size() > 0:
		panel.tooltip_text = "\n\n".join(tooltip_lines)
	else:
		panel.tooltip_text = "Charge failed. Hover for details."

	return panel

func _get_category_color(category: String) -> String:
	match category:
		"INSUFFICIENT_ROLL":
			return "#FF6666"  # Light red
		"DISTANCE":
			return "#FF9944"  # Orange
		"ENGAGEMENT":
			return "#FFCC00"  # Yellow
		"NON_TARGET_ER":
			return "#FF44FF"  # Magenta
		"COHERENCY":
			return "#44AAFF"  # Light blue
		"OVERLAP":
			return "#FF4444"  # Red
		"BASE_CONTACT":
			return "#44FF44"  # Green
		_:
			return "#AAAAAA"  # Grey

func _reset_unit_selection() -> void:
	active_unit_id = ""
	selected_targets.clear()
	eligible_targets.clear()
	awaiting_roll = false
	awaiting_movement = false
	
	if is_instance_valid(unit_selector):
		unit_selector.deselect_all()
	if is_instance_valid(target_list):
		target_list.clear()
	_clear_highlights()
	_clear_charge_range_circle()  # clear 12" ring / per-model reach rings
	if is_instance_valid(charge_line_visual):
		charge_line_visual.clear_points()

	# Hide charge distance display
	_hide_charge_distance_display()
	_update_button_states()

# Signal handlers from ChargePhase
func _on_charge_unit_completed(unit_id: String) -> void:
	print("ChargeController: Charge unit completed signal received for ", unit_id)
	# Refresh the unit list so the completed unit is removed from eligible list
	_update_ui_for_next_charge()

func _on_charge_unit_skipped(unit_id: String) -> void:
	print("ChargeController: Charge unit skipped signal received for ", unit_id)
	# Refresh the unit list so the skipped unit is removed from eligible list
	_update_ui_for_next_charge()

func _on_unit_selected_for_charge(unit_id: String) -> void:
	print("Phase selected unit for charge: ", unit_id)
	# UI already handled the selection

func _on_charge_targets_available(unit_id: String, targets: Dictionary) -> void:
	print("Charge targets available for ", unit_id, ": ", targets.keys())
	# UI already updated targets

func _on_charge_roll_made(unit_id: String, distance: int, dice: Array) -> void:
	print("Charge roll made: ", unit_id, " rolled ", distance, " (", dice, ")")

	charge_distance = distance
	awaiting_roll = false

	# Mark that we've processed this charge roll (prevents duplicate processing from dice_rolled signal)
	last_processed_charge_roll = {"unit_id": unit_id, "distance": distance}

	# Update dice log
	var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
		unit_id, distance, dice[0], dice[1]
	]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(dice_text)

	# Server-side failure detection: if the phase already determined the roll was
	# insufficient, it will have cleaned up pending_charges and emitted charge_resolved.
	# In that case, skip the local success check — _on_charge_resolved handles the rest.
	if current_phase and current_phase.has_method("has_pending_charge"):
		if not current_phase.has_pending_charge(unit_id):
			print("ChargeController: Phase already determined charge failure for %s — deferring to charge_resolved" % unit_id)
			# T7-58: Update arrows with failure result
			_update_charge_arrow_roll_results(distance, false)
			_update_button_states()
			return

	# Phase says charge is still pending → roll was sufficient, enable movement
	awaiting_movement = true
	if is_instance_valid(charge_info_label):
		charge_info_label.text = "Success! Rolled %d\" - Drag models toward targets (Shift+drag box selects several to move together, max %d\" each)" % [distance, distance]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=green]Charge successful! Move models into engagement range.[/color]\n")
	# T7-58: Update arrows with success result (roll sufficient)
	_update_charge_arrow_roll_results(distance, true)

	# Enable charge movement for this unit
	_enable_charge_movement(unit_id, distance)

	# Show charge distance tracking
	_show_charge_distance_display(distance)

	_update_button_states()

func _on_dice_rolled(dice_data: Dictionary) -> void:
	"""Handle dice_rolled signal from ChargePhase - critical for multiplayer sync.
	On clients, this is the primary handler (fires before charge_roll_made).
	The server-side charge_failed flag from the phase determines success/failure
	rather than recomputing locally, ensuring both players agree."""
	# P3-117: Record roll in centralized dice history
	if DiceHistoryPanel:
		DiceHistoryPanel.record_roll(dice_data, "Charge")

	if not is_instance_valid(dice_log_display):
		return

	# T5-V1: Trigger animated dice visualization for charge rolls
	if dice_roll_visual and dice_data.get("context", "") == "charge_roll":
		var charge_rolls = dice_data.get("rolls", [])
		if charge_rolls.size() == 2:
			# P3-118: Show reroll comparison if this was a command reroll
			if dice_data.get("command_reroll", false):
				var original_rolls = dice_data.get("original_rolls", [])
				if not original_rolls.is_empty():
					dice_roll_visual.show_reroll_comparison(original_rolls, charge_rolls, "charge_roll")
					print("ChargeController: Showing reroll comparison %s → %s" % [str(original_rolls), str(charge_rolls)])
				else:
					# Fallback to normal display if original_rolls missing
					var visual_data = {"context": "charge_roll", "rolls_raw": charge_rolls, "threshold": ""}
					dice_roll_visual.show_dice_roll(visual_data)
			else:
				# Standard display — no reroll
				var visual_data = {
					"context": "charge_roll",
					"rolls_raw": charge_rolls,
					"threshold": "",  # No threshold for charge rolls
				}
				dice_roll_visual.show_dice_roll(visual_data)

	print("ChargeController: _on_dice_rolled called with data: ", dice_data)

	# Extract dice data
	var context = dice_data.get("context", "")
	var unit_id = dice_data.get("unit_id", "")
	var unit_name = dice_data.get("unit_name", unit_id)
	var rolls = dice_data.get("rolls", [])
	var total = dice_data.get("total", 0)
	var targets = dice_data.get("targets", [])
	var charge_failed = dice_data.get("charge_failed", false)
	var min_distance = dice_data.get("min_distance", 0.0)

	# Only process charge rolls
	if context != "charge_roll" or rolls.size() != 2:
		return

	# Check if this charge roll was already processed by _on_charge_roll_made
	# This prevents duplicate processing on the host (which receives both signals)
	if last_processed_charge_roll.get("unit_id", "") == unit_id and last_processed_charge_roll.get("distance", -1) == total:
		print("ChargeController: Skipping duplicate charge roll processing (already handled by charge_roll_made)")
		return

	# Update dice log display
	var dice_text = "[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
		unit_name, total, rolls[0], rolls[1]
	]
	dice_log_display.append_text(dice_text)
	print("ChargeController: Added dice roll to display: ", dice_text.strip_edges())

	charge_distance = total
	awaiting_roll = false

	# Use the server-side charge_failed flag from the phase result.
	# This avoids local recomputation and ensures host and client agree.
	if charge_failed:
		# Server determined charge roll insufficient — show failure, let charge_resolved
		# (re-emitted by NetworkManager) handle the full UI update.
		awaiting_movement = false
		var er_inches = GameConstants.engagement_range_inches()
		var needed = max(0.0, min_distance - er_inches)

		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Failed! Rolled %d\" but needed ~%.1f\" to reach engagement range" % [total, needed]
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=red][INSUFFICIENT_ROLL] Charge failed![/color] Rolled %d\" but nearest target is %.1f\" away (need ~%.1f\" to reach %.0f\" engagement range).\n" % [total, min_distance, needed, er_inches])

		# T7-58: Update arrows with failure result
		_update_charge_arrow_roll_results(total, false)

		print("ChargeController: Server determined charge failed for %s (rolled %d, min dist %.1f\")" % [unit_id, total, min_distance])
		# charge_resolved signal will fire next and handle _reset_unit_selection + display refresh
		_update_button_states()
		return

	# Charge roll sufficient — enable movement
	# Fall back to local check if charge_failed flag was absent (backwards compat)
	var success = true
	if not dice_data.has("charge_failed"):
		print("ChargeController: No charge_failed flag in dice_data, using local success check")
		success = _is_charge_successful(unit_id, total, targets)

	if success:
		awaiting_movement = true
		if is_instance_valid(charge_info_label):
			charge_info_label.text = "Success! Rolled %d\" - Drag models toward targets (Shift+drag box selects several to move together, max %d\" each)" % [total, total]
		if is_instance_valid(dice_log_display):
			dice_log_display.append_text("[color=green]Charge successful! Move models into engagement range.[/color]\n")

		# T7-58: Update arrows with success result
		_update_charge_arrow_roll_results(total, true)

		_enable_charge_movement(unit_id, total)
		_show_charge_distance_display(total)

	_update_button_states()

func _on_charge_resolved(unit_id: String, success: bool, result: Dictionary) -> void:
	print("Charge resolved: ", unit_id, " success: ", success)

	# T7-58: Update charge arrows with the final result (they will fade on their own)
	var distance = result.get("distance", charge_distance)
	_update_charge_arrow_roll_results(distance, success)

	# DEBUG: Log positions after charge resolution
	print("=== CHARGE DEBUG: After Charge Resolved ===")
	_log_unit_positions(unit_id, "CHARGING UNIT")
	for target_id in selected_targets:
		_log_unit_positions(target_id, "TARGET UNIT")
	print("=== End Position Logging ===")

	var result_text = ""
	if success:
		result_text = "[color=green]Successful charge![/color] %s moved into engagement range\n" % unit_id
	else:
		# Use structured failure data if available
		var failure_record = result.get("failure_record", {})
		var categorized = failure_record.get("categorized_errors", [])

		if categorized.size() > 0:
			# Build rich failure text with category tags
			var primary_cat = failure_record.get("primary_category", "UNKNOWN")
			var cat_color = _get_category_color(primary_cat)
			result_text = "[color=%s][%s][/color] [color=red]Charge failed:[/color] %s\n" % [cat_color, primary_cat, unit_id]

			for cat_error in categorized:
				var cat = cat_error.get("category", "")
				var detail = cat_error.get("detail", "")
				var c = _get_category_color(cat)
				result_text += "  [color=%s]•[/color] %s\n" % [c, detail]
		else:
			# Fallback to plain reason string
			var reason = result.get("reason", "Failed")
			result_text = "[color=red]Charge failed:[/color] %s - %s\n" % [unit_id, reason]

	if is_instance_valid(dice_log_display):
		dice_log_display.append_text(result_text)

	# A Heroic Intervention resolution never completes a charger's activation
	if result.get("heroic_intervention", false):
		_pending_complete_unit_id = ""

	# Send COMPLETE_UNIT_CHARGE only after charge_resolved confirms the result.
	# This prevents state corruption that occurred when both APPLY_CHARGE_MOVE and
	# COMPLETE_UNIT_CHARGE were fired simultaneously without waiting for confirmation.
	if _pending_complete_unit_id != "" and _pending_complete_unit_id == unit_id:
		var complete_action = {
			"type": "COMPLETE_UNIT_CHARGE",
			"actor_unit_id": _pending_complete_unit_id
		}
		print("Requesting complete unit charge (after charge_resolved): ", complete_action)
		charge_action_requested.emit(complete_action)
		_pending_complete_unit_id = ""

	# Reset UI state
	_reset_unit_selection()
	# Refresh UI (which also refreshes failed charges display)
	_refresh_ui()

func process_action(action: Dictionary) -> void:
	if not current_phase:
		return
	
	print("ChargeController processing action: ", action.get("type", ""))
	
	# Validate action with current phase
	var validation = current_phase.validate_action(action)
	if not validation.get("valid", false):
		print("Action validation failed: ", validation.get("errors", []))
		return
	
	# Process action through current phase
	var result = current_phase.process_action(action)
	if result.get("success", false):
		print("Action processed successfully")
		
		# Apply state changes if any
		var changes = result.get("changes", [])
		if not changes.is_empty():
			PhaseManager.apply_state_changes(changes)
		
		# Refresh UI after action
		_refresh_ui()
	else:
		print("Action processing failed: ", result.get("error", "Unknown error"))

func _process(delta: float) -> void:
	# Update available actions periodically
	if current_phase:
		var actions = current_phase.get_available_actions()
		# Could update UI based on available actions if needed

# Charge movement distance display functions
func _show_charge_distance_display(max_distance: int) -> void:
	if is_instance_valid(charge_distance_label):
		charge_distance_label.text = "Charge: %d\"" % max_distance
		charge_distance_label.visible = true

	if is_instance_valid(charge_used_label):
		charge_used_label.text = "Used: 0.0\""
		charge_used_label.visible = true

	if is_instance_valid(charge_left_label):
		charge_left_label.text = "Left: %d.0\"" % max_distance
		charge_left_label.visible = true

	# P3-98: Reset terrain label on new charge
	if is_instance_valid(charge_terrain_label):
		charge_terrain_label.visible = false

func _hide_charge_distance_display() -> void:
	if is_instance_valid(charge_distance_label):
		charge_distance_label.visible = false
	if is_instance_valid(charge_used_label):
		charge_used_label.visible = false
	if is_instance_valid(charge_left_label):
		charge_left_label.visible = false
	# P3-98: Hide terrain label
	if is_instance_valid(charge_terrain_label):
		charge_terrain_label.visible = false

func _update_charge_distance_display(model_id: String, distance_moved: float, terrain_penalty: float = 0.0) -> void:
	if not is_instance_valid(charge_used_label) or not is_instance_valid(charge_left_label):
		return

	# P3-98: Include terrain penalty in effective distance
	var effective_distance = distance_moved + terrain_penalty
	var left = charge_distance - effective_distance
	var valid = left >= 0

	# Update labels
	charge_used_label.text = "Used: %.1f\"" % effective_distance
	charge_used_label.modulate = Color.WHITE if valid else Color.RED

	charge_left_label.text = "Left: %.1f\"" % left
	charge_left_label.modulate = Color.WHITE if left >= 0 else Color.RED

	# P3-98: Show terrain penalty breakdown when terrain affects the charge
	if is_instance_valid(charge_terrain_label):
		if terrain_penalty > 0.0:
			charge_terrain_label.text = "Effective: %.1f\" (%.1f\" - %.1f\" terrain)" % [effective_distance, distance_moved, terrain_penalty]
			charge_terrain_label.visible = true
		else:
			charge_terrain_label.visible = false

func _update_charge_distance_display_with_preview(distance_moved: float, valid: bool, terrain_penalty: float = 0.0) -> void:
	if not is_instance_valid(charge_used_label) or not is_instance_valid(charge_left_label):
		return

	var left = charge_distance - distance_moved

	# Update labels with preview
	charge_used_label.text = "Used: %.1f\"" % distance_moved
	charge_used_label.modulate = Color.WHITE if valid else Color.RED

	charge_left_label.text = "Left: %.1f\"" % left
	charge_left_label.modulate = Color.WHITE if left >= 0 else Color.RED

	# P3-98: Show terrain penalty breakdown when terrain affects the charge
	if is_instance_valid(charge_terrain_label):
		if terrain_penalty > 0.0:
			var actual_move = distance_moved - terrain_penalty
			charge_terrain_label.text = "Effective: %.1f\" (%.1f\" - %.1f\" terrain)" % [distance_moved, actual_move, terrain_penalty]
			charge_terrain_label.visible = true
		else:
			charge_terrain_label.visible = false

# Rotation functions for charge movement
func _check_position_would_overlap(model: Dictionary, new_pos: Vector2, charge_key: String = "", group_overrides: Dictionary = {}) -> bool:
	# Check if placing the model at the given position would overlap.
	# group_overrides (model_id -> Vector2): prospective positions of squadmates
	# moving in the same group drag (see _validate_group_charge_move).
	if not current_phase:
		return false

	var model_id = model.get("id", "")
	if charge_key == "":
		charge_key = model_id
	# Which unit the model being placed belongs to — the charging unit, or an
	# attached character unit ("<unit>:<model>" key).
	var self_unit_id = _charge_key_parts(charge_key).unit_id

	# Build a test model with the new position
	var test_model = model.duplicate()
	test_model["position"] = new_pos

	# Get all units and check for overlaps
	# Access the game state units directly
	var units = {}
	if current_phase and current_phase.has_method("get_game_state_snapshot"):
		var state_snapshot = current_phase.get_game_state_snapshot()
		units = state_snapshot.get("units", {})
	else:
		# Fallback to GameState if phase not available
		units = GameState.state.get("units", {})

	for check_unit_id in units:
		var check_unit = units[check_unit_id]
		var check_models = check_unit.get("models", [])

		for check_model in check_models:
			var check_model_id = check_model.get("id", "")

			# Skip self
			if check_unit_id == self_unit_id and check_model_id == model_id:
				continue

			# Skip dead models
			if not check_model.get("alive", true):
				continue

			# Get the current position of the other model.
			# Models of the charge group that already staged a move (bodyguard
			# AND attached characters) are checked at their staged positions.
			var other_position = _get_model_position(check_model)
			var other_key = _charge_model_key(check_unit_id, check_model_id)
			if moved_models.has(other_key):
				var moved_data = moved_models[other_key]
				if moved_data is Dictionary and moved_data.has("position"):
					other_position = moved_data["position"]
				elif moved_data is Vector2:
					other_position = moved_data

			# Squadmates moving in the same group drag occupy their prospective
			# positions, not the spots they are vacating. Group drag operates on
			# the charging unit's own models (keyed by bare model_id).
			if check_unit_id == active_unit_id and group_overrides.has(check_model_id):
				other_position = group_overrides[check_model_id]

			if other_position == null:
				continue

			# Build other model dict with position
			var other_model_check = check_model.duplicate()
			other_model_check["position"] = other_position

			# Check for overlap
			if Measurement.models_overlap(test_model, other_model_check):
				return true

	# Also check wall collision, honoring the model's own unit's traversal
	# keywords (e.g. INFANTRY can pass through ruin walls in 10e).
	var charger_keywords: Array = []
	if self_unit_id != "":
		charger_keywords = GameState.get_unit(self_unit_id).get("meta", {}).get("keywords", [])
	if Measurement.model_overlaps_any_wall(test_model, charger_keywords):
		return true

	return false

## T2-8: Calculate terrain vertical distance penalty for a straight-line path.
## Uses TerrainManager to check if the path crosses terrain >2" high.
## FLY units get diagonal measurement (shorter penalty).
func _calculate_terrain_penalty_for_path(from_pos: Vector2, to_pos: Vector2) -> float:
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if not terrain_manager:
		return 0.0

	# Check the charging unit's keywords (FLY skips climb diff; INFANTRY traverses ruins)
	var has_fly = false
	var keywords: Array = []
	if active_unit_id != "":
		var unit = GameState.get_unit(active_unit_id)
		keywords = unit.get("meta", {}).get("keywords", [])
		has_fly = "FLY" in keywords

	return terrain_manager.calculate_charge_terrain_penalty(from_pos, to_pos, has_fly, keywords)

func _rotate_dragging_model(angle: float) -> void:
	if not dragging_model:
		return

	# Check if model has a non-circular base
	var base_type = dragging_model.get("base_type", "circular")
	if base_type == "circular":
		return  # No rotation needed for circular bases

	# Update the models rotation
	var current_rotation = dragging_model.get("rotation", 0.0)
	var new_rotation = current_rotation + angle
	dragging_model["rotation"] = new_rotation

	# Update the ghost visual if it exists - use GhostVisual's set_base_rotation method
	if ghost_visual and ghost_visual.get_child_count() > 0:
		var ghost_token = ghost_visual.get_child(0)
		if ghost_token.has_method("set_base_rotation"):
			ghost_token.set_base_rotation(new_rotation)
		elif ghost_token.has_method("set_model_data"):
			# Fallback for compatibility
			ghost_token.set_model_data(dragging_model)
			ghost_token.queue_redraw()

	# IMPORTANT: Also update the actual token visual immediately during rotation
	# This ensures the rotation is visible right away, not just when drag ends
	var model_id = dragging_model.get("id", "")
	var rot_unit_id = dragging_model_source_unit_id if dragging_model_source_unit_id != "" else active_unit_id
	if model_id != "" and rot_unit_id != "":
		_update_token_rotation(rot_unit_id, model_id, new_rotation)

	print("DEBUG: Rotated charge model by ", rad_to_deg(angle), " degrees. New rotation: ", rad_to_deg(new_rotation))

func _update_token_rotation(unit_id: String, model_id: String, new_rotation: float) -> void:
	# Find and update the actual token visual with new model data including rotation
	var token_layer = SceneRefs.token_layer()
	if not token_layer:
		print("ERROR: TokenLayer not found, cannot update token rotation")
		return

	# Find the specific token for this model
	for child in token_layer.get_children():
		if not child.has_meta("unit_id") or not child.has_meta("model_id"):
			continue

		var token_unit_id = child.get_meta("unit_id")
		var token_model_id = child.get_meta("model_id")

		if token_unit_id == unit_id and token_model_id == model_id:
			# Found the token! `child` IS the TokenVisual (meta is set directly on
			# it by Main._create_token_visual, not on a wrapper) — child.get_child(0)
			# is its "Label" child node (added in TokenVisual._ready()), not a
			# nested TokenVisual, so reaching into it silently no-oped every
			# rotation update here.
			if child.has_method("set_model_data"):
				# IMPORTANT: Use dragging_model if available (it has the updated rotation)
				# Otherwise fall back to GameState (but update rotation)
				var model_data = null
				if dragging_model and dragging_model.get("id", "") == model_id:
					# Use dragging_model which has the current rotation
					model_data = dragging_model.duplicate()
				else:
					# Get from GameState but update the rotation
					var unit = GameState.get_unit(unit_id)
					for model in unit.get("models", []):
						if model.get("id", "") == model_id:
							model_data = model.duplicate()
							model_data["rotation"] = new_rotation
							break

				if model_data:
					child.set_model_data(model_data)
					print("DEBUG: Updated token visual rotation for ", model_id, " to ", rad_to_deg(new_rotation), " degrees")
					return

	print("WARNING: Could not find token visual for rotation update: unit=", unit_id, " model=", model_id)

# ============================================================================
# ABILITY REROLL HANDLERS (e.g. Swift Onslaught — free charge reroll)
# ============================================================================

func _on_ability_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle ability reroll opportunity — show dialog to the charging player."""
	var ability_name = roll_context.get("ability_name", "Ability")
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: ABILITY REROLL OPPORTUNITY (%s)" % ability_name)
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Original rolls: %s = %d" % [str(roll_context.get("original_rolls", [])), roll_context.get("total", 0)])
	print("╚═══════════════════════════════════════════════════════════════")

	# Show the dice in the log first
	var rolls = roll_context.get("original_rolls", [])
	var total = roll_context.get("total", 0)
	var unit_name = roll_context.get("unit_name", unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
			unit_name, total, rolls[0] if rolls.size() > 0 else 0, rolls[1] if rolls.size() > 1 else 0
		])
		dice_log_display.append_text("[color=cyan]%s: Free re-roll available![/color]\n" % ability_name)

	# Skip UI dialog for AI players — AIPlayer autoload handles the decision
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(player):
		print("ChargeController: Player %d is AI — skipping ability reroll dialog" % player)
		return

	# Reuse CommandRerollDialog in free-ability mode: the ability name becomes
	# the header and the button reads "Re-roll (Free)" — before this the dialog
	# kept its stratagem branding ("Re-roll (1 CP)" / "You have 0 CP"), so a
	# 0-CP player reasonably concluded the free re-roll was unusable.
	var dialog_script = load("res://dialogs/CommandRerollDialog.gd")
	if not dialog_script:
		push_error("Failed to load CommandRerollDialog.gd for ability reroll")
		_on_ability_reroll_declined(unit_id, player)
		return

	pending_ability_reroll_name = ability_name
	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(
		unit_id,
		player,
		"charge_roll",
		roll_context.get("original_rolls", []),
		roll_context.get("context_text", "Re-roll the charge dice for free"),
		ability_name
	)
	# Override the dialog title to show ability name instead of "Command Re-roll"
	dialog.title = "%s — Free Charge Re-roll" % ability_name
	dialog.command_reroll_used.connect(_on_ability_reroll_used)
	dialog.command_reroll_declined.connect(_on_ability_reroll_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("ChargeController: Ability reroll dialog shown for player %d (%s)" % [player, ability_name])

func _on_ability_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use ability reroll."""
	print("ChargeController: Ability reroll USED for %s" % unit_id)
	var used_name = pending_ability_reroll_name if pending_ability_reroll_name != "" else "Ability"
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=cyan]%s used! Re-rolling charge (free)...[/color]\n" % used_name.to_upper())
	emit_signal("charge_action_requested", {
		"type": "USE_ABILITY_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_ability_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining ability reroll."""
	print("ChargeController: Ability reroll DECLINED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Declined free re-roll.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_ABILITY_REROLL",
		"actor_unit_id": unit_id,
	})

# ============================================================================
# COMMAND RE-ROLL HANDLERS
# ============================================================================

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""Handle Command Re-roll opportunity — show dialog to the charging player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: COMMAND RE-ROLL OPPORTUNITY")
	print("║ Unit: %s (player %d)" % [roll_context.get("unit_name", unit_id), player])
	print("║ Roll type: %s" % roll_context.get("roll_type", "unknown"))
	print("║ Original rolls: %s = %d" % [str(roll_context.get("original_rolls", [])), roll_context.get("total", 0)])
	print("╚═══════════════════════════════════════════════════════════════")

	# Show the dice in the log first
	var rolls = roll_context.get("original_rolls", [])
	var total = roll_context.get("total", 0)
	var unit_name = roll_context.get("unit_name", unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange]Charge Roll:[/color] %s rolled 2D6 = %d (%d + %d)\n" % [
			unit_name, total, rolls[0] if rolls.size() > 0 else 0, rolls[1] if rolls.size() > 1 else 0
		])
		dice_log_display.append_text("[color=gold]Command Re-roll available! (1 CP)[/color]\n")

	# Skip dialog for AI players — AIPlayer handles the decision via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("ChargeController: Skipping command reroll dialog for AI player %d" % player)
		return

	# Multiplayer: the re-roll decision belongs to the CHARGING player — only
	# their seat shows the dialog (it previously popped on whichever machine
	# ran the handler, i.e. always the host).
	if NetworkManager and NetworkManager.is_networked() \
			and NetworkManager.get_local_player() != player:
		print("ChargeController: Command Re-roll is P%d's decision — local seat waits" % player)
		return

	# Load and show the dialog
	var dialog_script = load("res://dialogs/CommandRerollDialog.gd")
	if not dialog_script:
		push_error("Failed to load CommandRerollDialog.gd")
		_on_command_reroll_declined(unit_id, player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(
		unit_id,
		player,
		roll_context.get("roll_type", "charge_roll"),
		roll_context.get("original_rolls", []),
		roll_context.get("context_text", "")
	)
	dialog.command_reroll_used.connect(_on_command_reroll_used)
	dialog.command_reroll_declined.connect(_on_command_reroll_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("ChargeController: Command Re-roll dialog shown for player %d" % player)

func _on_command_reroll_used(unit_id: String, player: int) -> void:
	"""Handle player choosing to use Command Re-roll."""
	print("ChargeController: Command Re-roll USED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gold]COMMAND RE-ROLL used! Re-rolling charge...[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "USE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

func _on_command_reroll_declined(unit_id: String, player: int) -> void:
	"""Handle player declining Command Re-roll."""
	print("ChargeController: Command Re-roll DECLINED for %s" % unit_id)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Kept original roll.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_COMMAND_REROLL",
		"actor_unit_id": unit_id,
	})

# ===================================================
# FIRE OVERWATCH HANDLING (during Charge Phase)
# ===================================================

func _on_overwatch_opportunity(charging_unit_id: String, defending_player: int, eligible_units: Array) -> void:
	"""Handle Fire Overwatch opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: FIRE OVERWATCH OPPORTUNITY (Charge Phase)")
	print("║ Charging unit: %s (defending player %d)" % [charging_unit_id, defending_player])
	print("║ Eligible units: %d" % eligible_units.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip UI dialog for AI players — AIPlayer autoload handles the decision
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(defending_player):
		print("ChargeController: Defending player %d is AI — skipping overwatch dialog" % defending_player)
		return

	# Auto-decline if the player has toggled auto-decline overwatch
	var auto_decline_btn = SceneRefs.main_path("HUD_Bottom/HBoxContainer/AutoDeclineOverwatch")
	if auto_decline_btn and auto_decline_btn.button_pressed:
		print("ChargeController: Auto-declining Fire Overwatch for player %d (toggle enabled)" % defending_player)
		_on_fire_overwatch_declined(defending_player)
		return

	if eligible_units.is_empty():
		_on_fire_overwatch_declined(defending_player)
		return

	var dialog_script = load("res://dialogs/FireOverwatchDialog.gd")
	if not dialog_script:
		push_error("Failed to load FireOverwatchDialog.gd")
		_on_fire_overwatch_declined(defending_player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(defending_player, charging_unit_id, eligible_units)
	dialog.fire_overwatch_used.connect(_on_fire_overwatch_used)
	dialog.fire_overwatch_declined.connect(_on_fire_overwatch_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

	# MA-42: Show blocking overlay to active player
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("show_reactive_stratagem_waiting"):
		main_node.show_reactive_stratagem_waiting("Fire Overwatch")

	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange_red]FIRE OVERWATCH available for Player %d![/color]\n" % defending_player)

func _on_fire_overwatch_used(shooter_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Fire Overwatch during charge."""
	print("ChargeController: Fire Overwatch USED by %s" % shooter_unit_id)
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=orange_red]FIRE OVERWATCH! Player %d fires with %s[/color]\n" % [player, shooter_unit_id])
	emit_signal("charge_action_requested", {
		"type": "USE_FIRE_OVERWATCH",
		"actor_unit_id": shooter_unit_id,
		"payload": {
			"shooter_unit_id": shooter_unit_id
		}
	})

func _on_fire_overwatch_declined(player: int) -> void:
	"""Handle player declining Fire Overwatch during charge."""
	print("ChargeController: Fire Overwatch DECLINED by player %d" % player)
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Fire Overwatch declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_FIRE_OVERWATCH",
		"actor_unit_id": "",
	})

# ============================================================================
# HEROIC INTERVENTION HANDLERS
# ============================================================================

func _on_heroic_intervention_opportunity(player: int, eligible_units: Array, charging_unit_id: String) -> void:
	"""Handle Heroic Intervention opportunity — show dialog to the defending player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: HEROIC INTERVENTION OPPORTUNITY")
	print("║ Defending player: %d" % player)
	print("║ Charging enemy unit: %s" % charging_unit_id)
	print("║ Eligible units: %d" % eligible_units.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("ChargeController: Skipping Heroic Intervention dialog for AI player %d" % player)
		return

	if eligible_units.is_empty():
		_on_heroic_intervention_declined(player)
		return

	if is_instance_valid(dice_log_display):
		var hi_cp := 1 if GameConstants.edition >= 11 else 2
		dice_log_display.append_text("[color=gold]HEROIC INTERVENTION available for Player %d! (%d CP)[/color]\n" % [player, hi_cp])

	# Load and show the dialog
	var dialog_script = load("res://dialogs/HeroicInterventionDialog.gd")
	if not dialog_script:
		push_error("Failed to load HeroicInterventionDialog.gd")
		_on_heroic_intervention_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.name = "HeroicInterventionDialog"
	dialog.setup(player, charging_unit_id, eligible_units)
	dialog.heroic_intervention_used.connect(_on_heroic_intervention_used)
	dialog.heroic_intervention_declined.connect(_on_heroic_intervention_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("ChargeController: Heroic Intervention dialog shown for player %d" % player)

	# MA-42: Show blocking overlay to active player
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("show_reactive_stratagem_waiting"):
		main_node.show_reactive_stratagem_waiting("Heroic Intervention")

func _on_heroic_intervention_used(unit_id: String, player: int, mode: String = "leap_to_defend") -> void:
	"""Handle player choosing to use Heroic Intervention."""
	print("ChargeController: Heroic Intervention USED: player %d selects %s (mode: %s)" % [player, unit_id, mode])
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()

	if is_instance_valid(dice_log_display):
		var unit_name = GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id)
		dice_log_display.append_text("[color=gold]HEROIC INTERVENTION used — %s will counter-charge![/color]\n" % unit_name)

	emit_signal("charge_action_requested", {
		"type": "USE_HEROIC_INTERVENTION",
		"unit_id": unit_id,
		"player": player,
		"mode": mode,
	})

func _on_charge_path_tools_enabled(unit_id: String, distance: int) -> void:
	"""Enable board movement for a HEROIC INTERVENTION counter-charge.

	Normal charges enter movement mode via charge_roll_made; the HI flow
	emits only charge_path_tools_enabled, so this is the defender's single
	entry point into dragging the counter-charging models."""
	if not current_phase:
		return
	var hi_unit = str(current_phase.get("heroic_intervention_unit_id"))
	if hi_unit == "" or hi_unit != unit_id:
		return  # normal charge — handled by _on_charge_roll_made

	print("ChargeController: HI charge roll sufficient — enabling movement for %s (max %d\")" % [unit_id, distance])
	active_unit_id = unit_id
	charge_distance = distance
	awaiting_roll = false
	awaiting_movement = true
	# The counter-charge target list lives on the phase's HI pending charge,
	# not in the local selection (the defender never clicked targets).
	var hi_pending = current_phase.get("heroic_intervention_pending_charge")
	if hi_pending is Dictionary:
		selected_targets = hi_pending.get("targets", []).duplicate()
	if is_instance_valid(charge_info_label):
		charge_info_label.text = "Heroic Intervention! Rolled %d\" - Drag models toward %s - they auto-snap to base contact (max %d\" each)" % [distance, str(selected_targets), distance]
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gold]Heroic Intervention charge successful! Move models into engagement range.[/color]\n")
	_enable_charge_movement(unit_id, distance)
	_show_charge_distance_display(distance)
	_update_button_states()

func _on_heroic_intervention_declined(player: int) -> void:
	"""Handle player declining Heroic Intervention."""
	print("ChargeController: Heroic Intervention DECLINED by player %d" % player)
	# MA-42: Hide blocking overlay
	var main_node = SceneRefs.main()
	if main_node and main_node.has_method("hide_reactive_stratagem_waiting"):
		main_node.hide_reactive_stratagem_waiting()
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Heroic Intervention declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_HEROIC_INTERVENTION",
		"player": player,
	})

# ============================================================================
# TANK SHOCK HANDLERS
# ============================================================================

func _on_tank_shock_opportunity(player: int, vehicle_unit_id: String, eligible_targets: Array) -> void:
	"""Handle Tank Shock opportunity — show dialog to the charging player."""
	print("╔═══════════════════════════════════════════════════════════════")
	print("║ ChargeController: TANK SHOCK OPPORTUNITY")
	print("║ Player: %d" % player)
	print("║ Vehicle: %s" % vehicle_unit_id)
	print("║ Eligible targets: %d" % eligible_targets.size())
	print("╚═══════════════════════════════════════════════════════════════")

	# Skip dialog for AI players — AIPlayer handles via signal
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(player):
		print("ChargeController: Skipping Tank Shock dialog for AI player %d" % player)
		return

	if eligible_targets.is_empty():
		_on_tank_shock_declined(player)
		return

	if is_instance_valid(dice_log_display):
		var vehicle_unit = GameState.get_unit(vehicle_unit_id)
		var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
		var toughness = int(vehicle_unit.get("meta", {}).get("toughness", 4))
		dice_log_display.append_text("[color=orange_red]TANK SHOCK available for %s (T%d, 1 CP)![/color]\n" % [vehicle_name, toughness])

	# Load and show the dialog
	var dialog_script = load("res://dialogs/TankShockDialog.gd")
	if not dialog_script:
		push_error("Failed to load TankShockDialog.gd")
		_on_tank_shock_declined(player)
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup(player, vehicle_unit_id, eligible_targets)
	dialog.tank_shock_used.connect(_on_tank_shock_used)
	dialog.tank_shock_declined.connect(_on_tank_shock_declined)
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)
	print("ChargeController: Tank Shock dialog shown for player %d" % player)

func _on_tank_shock_used(target_unit_id: String, player: int) -> void:
	"""Handle player choosing to use Tank Shock."""
	print("ChargeController: Tank Shock USED targeting %s" % target_unit_id)
	if is_instance_valid(dice_log_display):
		var target_unit = GameState.get_unit(target_unit_id)
		var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
		dice_log_display.append_text("[color=orange_red]TANK SHOCK! Ramming %s![/color]\n" % target_name)
	emit_signal("charge_action_requested", {
		"type": "USE_TANK_SHOCK",
		"actor_unit_id": "",
		"payload": {
			"target_unit_id": target_unit_id
		}
	})

func _on_tank_shock_declined(player: int) -> void:
	"""Handle player declining Tank Shock."""
	print("ChargeController: Tank Shock DECLINED by player %d" % player)
	if is_instance_valid(dice_log_display):
		dice_log_display.append_text("[color=gray]Tank Shock declined.[/color]\n")
	emit_signal("charge_action_requested", {
		"type": "DECLINE_TANK_SHOCK",
		"actor_unit_id": "",
	})

func _on_tank_shock_result(vehicle_unit_id: String, target_unit_id: String, result: Dictionary) -> void:
	"""Handle Tank Shock result — show result dialog."""
	print("ChargeController: Tank Shock result received — %d mortal wounds" % result.get("mortal_wounds", 0))

	if is_instance_valid(dice_log_display):
		var rolls = result.get("dice_rolls", [])
		var mw = result.get("mortal_wounds", 0)
		var dice_count = result.get("dice_count", 0)
		dice_log_display.append_text("[color=orange_red]Rolled %dD6: %s — %d mortal wound(s)[/color]\n" % [dice_count, str(rolls), mw])

	# Skip result dialog for AI players — informational only, would pile up
	var charging_player = GameState.get_active_player()
	var ai_player_node = get_node_or_null("/root/AIPlayer")
	if ai_player_node and ai_player_node.is_ai_player(charging_player):
		print("ChargeController: Skipping Tank Shock result dialog for AI player %d" % charging_player)
		return

	# Show result dialog
	var dialog_script = load("res://dialogs/TankShockResultDialog.gd")
	if not dialog_script:
		push_error("Failed to load TankShockResultDialog.gd")
		return

	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	dialog.setup({
		"dice_rolls": result.get("dice_rolls", []),
		"mortal_wounds": result.get("mortal_wounds", 0),
		"casualties": result.get("casualties", 0),
		"toughness": result.get("toughness", 0),
		"dice_count": result.get("dice_count", 0),
		"vehicle_unit_id": vehicle_unit_id,
		"target_unit_id": target_unit_id,
	})
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

# --- T7-58: Charge Arrow Visual Management ---

func _create_charge_arrow_visual(from_pos: Vector2, to_pos: Vector2, animate: bool) -> ChargeArrowVisual:
	"""Create and display a charge arrow visual from charger to target."""
	var board_root = SceneRefs.board_root()
	if not board_root:
		print("[ChargeController] T7-58: Cannot find BoardRoot for charge arrow")
		return null

	var visual = ChargeArrowVisual.new()
	visual.name = "ChargeArrowVisual_%d" % charge_arrow_visuals.size()
	board_root.add_child(visual)
	charge_arrow_visuals.append(visual)

	if animate:
		visual.play(from_pos, to_pos)
	else:
		visual.show_static(from_pos, to_pos)

	print("[ChargeController] T7-58: Created charge arrow %s -> %s (animate=%s)" % [str(from_pos), str(to_pos), str(animate)])
	return visual

func _clear_charge_arrow_visuals() -> void:
	"""Remove all charge arrow visuals from the scene."""
	for visual in charge_arrow_visuals:
		if is_instance_valid(visual):
			visual.clear_now()
			visual.queue_free()
	charge_arrow_visuals.clear()

func _update_charge_arrow_roll_results(roll_total: int, success: bool) -> void:
	"""Update all active charge arrow visuals with the roll result."""
	for visual in charge_arrow_visuals:
		if is_instance_valid(visual):
			visual.set_roll_result(roll_total, success)
	print("[ChargeController] T7-58: Updated %d arrow(s) with roll result: %d\" (%s)" % [charge_arrow_visuals.size(), roll_total, "success" if success else "failed"])

func show_ai_charge_arrows(charger_unit_id: String, target_unit_ids: Array) -> void:
	"""Show animated charge arrows for an AI charge declaration.
	Called from external code (e.g. AIPlayer or Main) when AI declares a charge."""
	_clear_charge_arrow_visuals()

	var charger = GameState.get_unit(charger_unit_id)
	if charger.is_empty():
		print("[ChargeController] T7-58: Cannot find charger unit %s for arrow visual" % charger_unit_id)
		return

	var from_pos = _get_unit_center_position(charger)
	if from_pos == Vector2.ZERO:
		return

	for target_id in target_unit_ids:
		var target_unit = GameState.get_unit(target_id)
		if not target_unit.is_empty():
			var to_pos = _get_unit_center_position(target_unit)
			if to_pos != Vector2.ZERO:
				_create_charge_arrow_visual(from_pos, to_pos, true)

	print("[ChargeController] T7-58: Showing %d AI charge arrow(s) for %s" % [charge_arrow_visuals.size(), charger_unit_id])

# --- T-092: 12" Charge Range Overlay ---

const CHARGE_RANGE_OVERLAY_INCHES: float = 12.0
const CHARGE_RANGE_OVERLAY_COLOR: Color = Color(1.0, 0.6, 0.1, 0.55)
const CHARGE_RANGE_OVERLAY_WIDTH: float = 12.0  # Width in board-space px (board scale ~0.3)

# Per-model charge-move reach overlay (shown AFTER the 2D6 roll, while dragging).
# Green to read as "you can move here" vs the orange pre-roll 12" threat ring.
const CHARGE_MODEL_RANGE_COLOR: Color = Color(0.3, 0.9, 0.45, 0.55)
const CHARGE_MODEL_RANGE_LABEL_COLOR: Color = Color(0.45, 1.0, 0.55, 0.95)
const CHARGE_MODEL_RANGE_WIDTH: float = 8.0  # Width in board-space px (thinner than the 12" ring)

func _draw_charge_dashed_circle(center: Vector2, radius_px: float, color: Color, width: float) -> void:
	# Draw a dashed circle (alternating visible/invisible arcs) into range_visual.
	# Used by the post-roll per-model reach rings; the pre-roll threat envelope
	# dashes arbitrary loops via _draw_charge_dashed_loop instead.
	var total_arcs: int = 10
	var arc_length: float = TAU / float(total_arcs)
	var dash_fraction: float = 0.7
	for arc_idx in range(total_arcs):
		var arc_start: float = arc_idx * arc_length
		var arc_dash_end: float = arc_start + arc_length * dash_fraction
		var dash := Line2D.new()
		dash.name = "ChargeRangeCircle"
		dash.width = width
		dash.default_color = color
		dash.begin_cap_mode = Line2D.LINE_CAP_ROUND
		dash.end_cap_mode = Line2D.LINE_CAP_ROUND
		var pts: int = 8
		for i in range(pts + 1):
			var theta: float = arc_start + (arc_dash_end - arc_start) * float(i) / float(pts)
			dash.add_point(center + Vector2(cos(theta), sin(theta)) * radius_px)
		range_visual.add_child(dash)

func _show_charge_range_overlay(unit: Dictionary) -> void:
	# 11.02: a unit may declare a charge when a target is within 12" of the UNIT
	# — i.e. of ANY of its models, measured edge-to-edge (shape-aware, exactly
	# like ChargePhase._is_target_within_charge_range). A single 12" ring centred
	# on the unit's centroid both understates the reach of models far from the
	# centroid and ignores base sizes, so it disagreed with the eligible-target
	# list. Draw instead the union envelope of every alive model's base outline
	# inflated by 12": the dashed boundary marks exactly where an enemy base
	# edge can sit and still be a legal charge declaration target.
	if not is_instance_valid(range_visual):
		return
	_clear_charge_range_circle()
	var range_px := Measurement.inches_to_px(CHARGE_RANGE_OVERLAY_INCHES)
	var threat_polys: Array = []
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		if _get_model_position(model) == Vector2.ZERO:
			continue  # embarked / not-yet-deployed models carry no board position
		var poly := _charge_threat_polygon_for_model(model, range_px)
		if poly.size() >= 3:
			threat_polys.append(poly)
	if threat_polys.is_empty():
		return

	charge_threat_outlines = _union_outline_polygons(threat_polys)
	var bounds := Rect2(charge_threat_outlines[0][0], Vector2.ZERO)
	for outline in charge_threat_outlines:
		for point in outline:
			bounds = bounds.expand(point)
	charge_threat_bounds = bounds

	for outline in charge_threat_outlines:
		_draw_charge_dashed_loop(outline, CHARGE_RANGE_OVERLAY_COLOR, CHARGE_RANGE_OVERLAY_WIDTH)

	# Distance label, anchored above the top of the envelope
	var range_label := Label.new()
	range_label.name = "ChargeRangeCircle"
	range_label.text = "12\" charge"
	range_label.add_theme_font_size_override("font_size", 36)
	range_label.add_theme_color_override("font_color", CHARGE_RANGE_OVERLAY_COLOR)
	range_label.position = Vector2(bounds.get_center().x - 60, bounds.position.y - 40)
	range_label.z_index = 55
	range_visual.add_child(range_label)

func _charge_threat_polygon_for_model(model: Dictionary, range_px: float) -> PackedVector2Array:
	# "Every point within range_px of the model's base edge" — the Minkowski sum
	# of the base outline with a disc. A circular base stays a circle (radius +
	# range); rectangular/oval bases inflate their outline polygon with round
	# joins via Geometry2D.offset_polygon (probe-verified: positive delta grows
	# outward regardless of input winding).
	var pos := _get_model_position(model)
	var shape = Measurement.create_base_shape(model)
	if shape == null:
		return PackedVector2Array()
	if shape.get_type() == "circular":
		var radius: float = shape.radius + range_px
		var circle := PackedVector2Array()
		var segments: int = 48
		for i in range(segments):
			var theta := TAU * float(i) / float(segments)
			circle.append(pos + Vector2(cos(theta), sin(theta)) * radius)
		return circle

	var rot: float = model.get("rotation", 0.0)
	var base_pts := PackedVector2Array()
	if shape.get_type() == "oval":
		# OvalBase.length/width store the SEMI-axes (halved in _init)
		var samples: int = 32
		for i in range(samples):
			var theta := TAU * float(i) / float(samples)
			base_pts.append(shape.to_world_space(Vector2(shape.length * cos(theta), shape.width * sin(theta)), pos, rot))
	else:
		# rectangular (and any future shape): bounding-box corners
		var bb: Rect2 = shape.get_bounds()
		for corner in [bb.position, Vector2(bb.end.x, bb.position.y), bb.end, Vector2(bb.position.x, bb.end.y)]:
			base_pts.append(shape.to_world_space(corner, pos, rot))

	var inflated: Array = Geometry2D.offset_polygon(base_pts, range_px, Geometry2D.JOIN_ROUND)
	# Convex input inflates to exactly one polygon; pick the largest defensively.
	var best := PackedVector2Array()
	var best_area: float = -1.0
	for p in inflated:
		var area := _polygon_area_abs(p)
		if area > best_area:
			best_area = area
			best = p
	return best

func _polygon_area_abs(poly: PackedVector2Array) -> float:
	var doubled: float = 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		doubled += a.x * b.y - b.x * a.y
	return absf(doubled) * 0.5

func _union_outline_polygons(polys: Array) -> Array:
	# Merge overlapping polygons into their union's outer boundary loops.
	# Greedy island merge: try to absorb each polygon into an existing island; a
	# successful merge restarts the scan since the grown island may now touch an
	# island it previously missed. merge_polygons returns enclosed holes as
	# clockwise outlines — with 12" reach discs on models held in 2" coherency a
	# hole is geometrically impossible, so hole outlines are dropped rather than
	# drawn (drawing one would mark interior area as a charge boundary).
	var islands: Array = []
	for poly in polys:
		var current: PackedVector2Array = poly
		var i: int = 0
		while i < islands.size():
			var res := Geometry2D.merge_polygons(current, islands[i])
			var outers: Array = []
			for r in res:
				if not Geometry2D.is_polygon_clockwise(r):
					outers.append(r)
			if outers.size() == 1:
				# Overlap (or containment): absorbed into one boundary
				current = outers[0]
				islands.remove_at(i)
				i = 0
			else:
				# Disjoint: merge_polygons returned both inputs unchanged
				i += 1
		islands.append(current)
	return islands

func _draw_charge_dashed_loop(loop: PackedVector2Array, color: Color, width: float) -> void:
	# Dash a closed polyline with the same look as _draw_charge_dashed_circle
	# (70% on / 30% off), scaling the dash count to the loop's perimeter so the
	# envelope matches the old fixed-radius ring's density (10 dashes on a bare
	# 12" circle ≈ one dash cycle per ~300 px).
	var n := loop.size()
	if n < 3:
		return
	var seg_lens: Array = []
	var perimeter: float = 0.0
	for i in range(n):
		var seg_len := loop[i].distance_to(loop[(i + 1) % n])
		seg_lens.append(seg_len)
		perimeter += seg_len
	if perimeter <= 0.0:
		return
	var total_dashes: int = clampi(int(round(perimeter / 300.0)), 8, 64)
	var cycle := perimeter / float(total_dashes)
	var dash_fraction: float = 0.7
	for d in range(total_dashes):
		var pts := _loop_sub_path(loop, seg_lens, d * cycle, (float(d) + dash_fraction) * cycle)
		if pts.size() < 2:
			continue
		var dash := Line2D.new()
		dash.name = "ChargeRangeCircle"
		dash.width = width
		dash.default_color = color
		dash.begin_cap_mode = Line2D.LINE_CAP_ROUND
		dash.end_cap_mode = Line2D.LINE_CAP_ROUND
		dash.points = pts
		range_visual.add_child(dash)

func _loop_sub_path(loop: PackedVector2Array, seg_lens: Array, s0: float, s1: float) -> PackedVector2Array:
	# Points along the closed loop between arc-lengths s0 and s1 (s1 <= perimeter):
	# interpolated entry point, every interior vertex, interpolated exit point.
	var out := PackedVector2Array()
	var n := loop.size()
	var acc: float = 0.0
	for i in range(n):
		var seg_len: float = seg_lens[i]
		var seg_start := acc
		acc += seg_len
		if seg_len <= 0.0 or acc < s0:
			continue
		if seg_start > s1:
			break
		var a := loop[i]
		var b := loop[(i + 1) % n]
		if out.is_empty():
			out.append(a.lerp(b, clampf((s0 - seg_start) / seg_len, 0.0, 1.0)))
		if acc >= s1:
			out.append(a.lerp(b, clampf((s1 - seg_start) / seg_len, 0.0, 1.0)))
			break
		out.append(b)
	return out

func _show_per_model_charge_ranges(unit_id: String, max_distance: float) -> void:
	# After the charge roll, EACH model may move up to the rolled distance from its
	# OWN origin (the per-model cap enforced in _validate_charge_position). Replace
	# the pre-roll 12" threat envelope — which no longer reflects how
	# far a model can actually go — with one reach ring per model centred on that
	# model's pre-charge origin, so the player can see the real drag range of each
	# individual model. Anchored on the origin (not the live position) so the ring
	# stays put as a fixed reference while the model is dragged; the panel's
	# Used/Left readout tracks the live remaining budget.
	if not is_instance_valid(range_visual):
		return
	_clear_charge_range_circle()
	if max_distance <= 0.0:
		return
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	var radius_px := Measurement.inches_to_px(max_distance)
	var centers: Array = []
	# Charging unit's own models, plus its attached CHARACTER models — they are
	# draggable too (keyed "<char_unit>:<model>"), so show their reach as well.
	var ring_units: Array = [[unit_id, unit]]
	for char_id in _get_attached_character_ids(unit_id):
		var char_unit = GameState.get_unit(char_id)
		if not char_unit.is_empty():
			ring_units.append([char_id, char_unit])
	for entry in ring_units:
		var ring_unit_id: String = entry[0]
		var ring_unit: Dictionary = entry[1]
		for model in ring_unit.get("models", []):
			if not model.get("alive", true):
				continue
			var key = _charge_model_key(ring_unit_id, model.get("id", ""))
			# Anchor on the cached pre-charge origin (set in _enable_charge_movement);
			# fall back to the live position for any model without a cached origin.
			var center: Vector2 = _model_origin_positions.get(key, _get_model_position(model))
			if center == Vector2.ZERO:
				continue
			centers.append(center)
			_draw_charge_dashed_circle(center, radius_px, CHARGE_MODEL_RANGE_COLOR, CHARGE_MODEL_RANGE_WIDTH)

	# One summary label above the group — every model shares the same rolled reach,
	# so a per-model number would just be the same value repeated N times.
	if not centers.is_empty():
		var group_center := Vector2.ZERO
		var top_y: float = INF
		for c in centers:
			group_center += c
			top_y = minf(top_y, c.y)
		group_center /= centers.size()
		var range_label := Label.new()
		range_label.name = "ChargeRangeCircle"
		range_label.text = "%d\" charge move (each model)" % int(round(max_distance))
		range_label.add_theme_font_size_override("font_size", 32)
		range_label.add_theme_color_override("font_color", CHARGE_MODEL_RANGE_LABEL_COLOR)
		range_label.position = Vector2(group_center.x - 150, top_y - (radius_px + 40))
		range_label.z_index = 55
		range_visual.add_child(range_label)

func _clear_charge_range_circle() -> void:
	charge_threat_outlines = []
	charge_threat_bounds = Rect2()
	if not is_instance_valid(range_visual):
		return
	# range_visual (ChargeRangeVisual) is a dedicated container used ONLY for the
	# 12" overlay, so free every child. We deliberately do NOT filter by
	# name == "ChargeRangeCircle": _show_charge_range_overlay() adds many children
	# (dash segments + the label) all named "ChargeRangeCircle", and Godot
	# auto-renames colliding siblings ("ChargeRangeCircle2", "ChargeRangeCircle3",
	# …). An exact-name match therefore only removed ONE node per clear, so the
	# rest leaked and accumulated on every unit re-selection — leaving stale
	# bubbles cluttering the board (mirrors _clear_highlights on target_highlights).
	for child in range_visual.get_children():
		child.queue_free()

# --- P3-127: Charge Trajectory Preview Management ---

func _update_charge_trajectory_preview(unit: Dictionary, unit_center: Vector2) -> void:
	"""Build and display charge trajectory paths from each model to closest target model."""
	if not is_instance_valid(charge_trajectory_preview):
		return

	var trajectories: Array = []
	var min_charge_needed: float = INF

	# Get charging unit's FLY keyword for terrain penalty
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue

		var model_pos = _get_model_position(model)
		if model_pos == Vector2.ZERO:
			continue

		# Find the closest target model across all selected targets
		var closest_dist_inches: float = INF
		var closest_target_pos: Vector2 = Vector2.ZERO

		for target_id in selected_targets:
			var target_unit = GameState.get_unit(target_id)
			if target_unit.is_empty():
				continue

			for target_model in target_unit.get("models", []):
				if not target_model.get("alive", true):
					continue

				var target_pos = _get_model_position(target_model)
				if target_pos == Vector2.ZERO:
					continue

				# Edge-to-edge distance in inches
				var dist_inches = Measurement.model_to_model_distance_inches(model, target_model)
				if dist_inches < closest_dist_inches:
					closest_dist_inches = dist_inches
					closest_target_pos = target_pos

		if closest_target_pos != Vector2.ZERO and closest_dist_inches < INF:
			# Distance needed = edge-to-edge minus the edition's engagement range
			var charge_distance_needed = maxf(closest_dist_inches - GameConstants.engagement_range_inches(), 0.0)

			# Add terrain penalty for straight-line path
			var terrain_penalty = _calculate_terrain_penalty_for_path(model_pos, closest_target_pos)
			var effective_distance = charge_distance_needed + terrain_penalty

			trajectories.append({
				"from": model_pos,
				"to": closest_target_pos,
				"distance_inches": effective_distance
			})

			if effective_distance < min_charge_needed:
				min_charge_needed = effective_distance

	if min_charge_needed == INF:
		min_charge_needed = 0.0

	charge_trajectory_preview.update_trajectories(trajectories, min_charge_needed, unit_center)
	print("[ChargeController] P3-127: Showing %d trajectory path(s), min charge needed: %.1f\"" % [trajectories.size(), min_charge_needed])

func _clear_charge_trajectory_preview() -> void:
	"""Clear the charge trajectory preview."""
	if charge_trajectory_preview and is_instance_valid(charge_trajectory_preview):
		charge_trajectory_preview.clear_now()

# T-092: Auto-path — for each unmoved charging model, suggest the closest
# valid position adjacent to the nearest target model and stage the move.
# Uses a simple heuristic: place each model at distance (target_base_radius
# + own_base_radius + 0.5") from the nearest target model along the
# straight-line approach.
func _on_auto_path_charge() -> void:
	# T-092 fix: the button is now hidden/disabled unless a charge move is
	# active (see _update_button_states), but guard defensively — if it is ever
	# triggered with nothing to place, tell the player instead of silently
	# doing nothing (the original "Snap to Contact does nothing" symptom).
	if active_unit_id == "" or not awaiting_movement or models_to_move.is_empty():
		print("[T-092 auto-path] Snap to Contact ignored — no active charge move (active_unit=%s, awaiting_movement=%s, models_to_move=%d)" % [active_unit_id, str(awaiting_movement), models_to_move.size()])
		if is_instance_valid(charge_info_label) and awaiting_movement and models_to_move.is_empty():
			charge_info_label.text = "All models already in engagement range — click 'Confirm Charge Moves'"
		return
	var unit = GameState.get_unit(active_unit_id)
	if unit.is_empty():
		return
	# Declared charge targets: local selection first, then the phase's pending
	# charge (covers Heroic Intervention too). current_phase is an Object, so
	# pending_charges must be read as a property — Object.get() takes a single
	# argument, and a two-argument Dictionary-style get() aborts this handler.
	var charge_targets: Array = selected_targets
	if charge_targets.is_empty():
		charge_targets = _get_charge_targets_from_phase(active_unit_id)
	# Build a list of candidate target model positions (alive enemies in declared targets)
	var target_positions: Array = []
	for target_id in charge_targets:
		var target_unit = GameState.get_unit(target_id)
		for tmodel in target_unit.get("models", []):
			if not tmodel.get("alive", true):
				continue
			var tpos = tmodel.get("position")
			if tpos == null:
				continue
			var t_radius = Measurement.base_radius_px(tmodel.get("base_mm", 32))
			var tp: Vector2
			if tpos is Dictionary:
				tp = Vector2(tpos.get("x", 0), tpos.get("y", 0))
			else:
				tp = tpos
			# Carry the target model dict too so fallback placement can measure
			# shape-aware edge distances, not just circle math.
			target_positions.append({"pos": tp, "radius": t_radius, "model": tmodel})
	if target_positions.is_empty():
		print("[T-092 auto-path] No target positions available")
		return
	# Iterate models still needing to move, place each adjacent to a target.
	# Prefer BASE-TO-BASE contact (0" gap) — it always satisfies the 11.04
	# "within 1 inch" requirement and produces the cleanest engagement — and only
	# fall back to progressively larger gaps if NO contact spot exists on any
	# target (overlap / off board / out of charge range). Within each gap, try
	# targets nearest-first and sweep angles around the approach direction so a
	# straight-line spot blocked by an already-placed squadmate falls back to
	# the next position around the target's base instead of giving up.
	# Models for which NO contact spot is reachable at all (charge roll too
	# short) are then moved AS CLOSE AS POSSIBLE to the nearest target instead
	# of being silently left in place — see _find_closest_charge_position.
	var to_move_copy = models_to_move.duplicate()
	var unplaced: Array = []
	var contact_placed: int = 0
	var closest_placed: int = 0
	# Built once: alive models of enemy units NOT declared as charge targets.
	# A charge move may not END within engagement range of any of them (the
	# phase rejects the confirm), so both placement stages must avoid them.
	var non_target_enemies: Array = _collect_non_target_enemy_models(charge_targets)
	for charge_key in to_move_copy:
		# Keys may name attached character models ("<char_unit>:<model>") — the
		# leader snaps into contact right alongside its squad.
		var model: Dictionary = _get_charge_group_model(charge_key)
		if model.is_empty():
			continue
		var origin: Vector2 = _get_model_position(model)
		var own_radius: float = Measurement.base_radius_px(model.get("base_mm", 32))
		# Targets nearest-first for this model
		var targets_sorted: Array = target_positions.duplicate()
		targets_sorted.sort_custom(func(a, b): return origin.distance_to(a["pos"]) < origin.distance_to(b["pos"]))
		var placed := false
		for gap_inches in [0.0, 0.25, 0.5, 0.9]:
			var gap_px: float = Measurement.inches_to_px(gap_inches)
			for tp_data in targets_sorted:
				var dir_vec: Vector2 = (tp_data["pos"] - origin)
				if dir_vec.length() < 1.0:
					dir_vec = Vector2(1, 0)
				dir_vec = dir_vec.normalized()
				var place_distance_from_target: float = tp_data["radius"] + own_radius + gap_px
				for angle_deg in SNAP_ANGLE_SWEEP_DEG:
					var candidate: Vector2 = tp_data["pos"] - dir_vec.rotated(deg_to_rad(angle_deg)) * place_distance_from_target
					if not _validate_charge_position(model, candidate, charge_key):
						continue
					if _position_within_enemy_er(model, candidate, non_target_enemies):
						continue
					_stage_auto_path_placement(charge_key, model, origin, candidate)
					print("[T-092 auto-path] Placed %s at %s (gap=%.2f\", angle=%+.0f deg, target dist=%.1f\")" % [charge_key, str(candidate), gap_inches, angle_deg, Measurement.px_to_inches(candidate.distance_to(tp_data["pos"]))])
					placed = true
					break
				if placed:
					break
			if placed:
				break
		if placed:
			contact_placed += 1
			continue
		# No contact/near-contact spot reachable (roll too short, or every ring
		# spot blocked). Best-effort: close the gap as far as the remaining
		# charge distance legally allows — 11e only requires the model to end
		# closer + in coherency, so an out-of-engagement approach is legal.
		var fallback: Dictionary = _find_closest_charge_position(model, origin, targets_sorted, non_target_enemies, charge_key)
		if fallback.get("found", false):
			var fb_pos: Vector2 = fallback["position"]
			_stage_auto_path_placement(charge_key, model, origin, fb_pos)
			print("[T-092 auto-path] No contact spot for %s — moved as close as possible to %s (gap now %.2f\")" % [charge_key, str(fb_pos), fallback.get("gap", -1.0)])
			closest_placed += 1
			placed = true
		if not placed:
			unplaced.append(charge_key)
			print("[T-092 auto-path] No valid placement found for %s" % charge_key)
	# Refresh button states
	if confirm_button and is_instance_valid(confirm_button):
		confirm_button.disabled = moved_models.is_empty()
	if undo_charge_model_button and is_instance_valid(undo_charge_model_button):
		undo_charge_model_button.disabled = _moved_model_order.is_empty()
	# Refresh info
	if is_instance_valid(charge_info_label):
		if models_to_move.is_empty():
			if closest_placed > 0 and contact_placed > 0:
				charge_info_label.text = "Snapped %d model(s) to contact; %d couldn't reach — moved as close as possible. Confirm or adjust" % [contact_placed, closest_placed]
			elif closest_placed > 0:
				charge_info_label.text = "No model could reach base contact — all moved as close as possible. Confirm or adjust"
			else:
				charge_info_label.text = "All models auto-pathed! Click 'Confirm Charge Moves' to complete"
		elif not unplaced.is_empty():
			charge_info_label.text = "Snap to Contact: %d model(s) have no legal move within %d\" — drag them manually" % [unplaced.size(), charge_distance]
		else:
			charge_info_label.text = _remaining_models_message()


# Stage a suggested charge position exactly like a completed drag would
# (moved_models, hop path, undo order, GameState write, token visual) and
# remove the model from the still-to-move list. Keyed by charge key so an
# attached character's placement is written to the character's own unit.
func _stage_auto_path_placement(charge_key: String, model: Dictionary, origin: Vector2, candidate: Vector2) -> void:
	var key_parts = _charge_key_parts(charge_key)
	moved_models[charge_key] = {"position": candidate, "rotation": model.get("rotation", 0.0)}
	# Multi-step: record the single-hop path (origin -> placement) so the
	# accumulated distance and confirmed polyline match dragged models.
	_model_charge_paths[charge_key] = [origin, candidate]
	if charge_key in _moved_model_order:
		_moved_model_order.erase(charge_key)
	_moved_model_order.append(charge_key)
	_update_model_position_in_gamestate(key_parts.unit_id, key_parts.model_id, candidate)
	_move_token_visual(key_parts.unit_id, key_parts.model_id, candidate, model.get("rotation", 0.0))
	models_to_move.erase(charge_key)

# All alive models of enemy units that are NOT among the declared charge
# targets. Ending a charge move within engagement range of any of these is
# illegal (ChargePhase rejects the whole confirm), so auto-path placement
# must filter candidate spots against them.
func _collect_non_target_enemy_models(charge_targets: Array) -> Array:
	var out: Array = []
	var unit = GameState.get_unit(active_unit_id)
	var my_owner = unit.get("owner", 0)
	var units = GameState.state.get("units", {})
	for enemy_id in units:
		if enemy_id in charge_targets:
			continue
		var enemy = units[enemy_id]
		if enemy.get("owner", 0) == my_owner:
			continue
		for em in enemy.get("models", []):
			if em.get("alive", true):
				out.append(em)
	return out

func _position_within_enemy_er(model: Dictionary, pos: Vector2, enemy_models: Array) -> bool:
	if enemy_models.is_empty():
		return false
	var test_model = model.duplicate()
	test_model["position"] = pos
	for em in enemy_models:
		if Measurement.is_in_engagement_range_shape_aware(test_model, em, GameConstants.engagement_range_inches()):
			return true
	return false

# Fallback for "Snap to Contact" when no base-contact spot is reachable within
# the charge roll: find a position that brings the model AS CLOSE AS POSSIBLE
# to a declared target while staying legal (within remaining charge distance
# incl. terrain penalty, no overlap, on the board, ends closer to a target,
# not inside a non-target unit's engagement range).
#
# Pass A pushes the model straight at each target model, aiming just inside
# the 1" engagement band (0.95" gap) when the budget reaches it and spending
# the whole remaining budget otherwise; the valid candidate ending nearest a
# target wins. Straight-line-first deliberately mirrors the candidate that
# RulesEngine.validate_base_to_base_possible_rules (11.04 WHILE MOVING)
# constructs, so any model that check would oblige to close into the 1" band
# is handed exactly that placement and the confirm cannot bounce on it.
# Pass B only runs when every straight lane is blocked (squadmate, wall,
# terrain budget): it sweeps small approach-angle offsets and shorter travels
# and takes the first legal candidate.
func _find_closest_charge_position(model: Dictionary, origin: Vector2, targets_sorted: Array, non_target_enemies: Array, charge_key: String = "") -> Dictionary:
	# charge_key keys the accumulated-distance lookup; falls back to the bare
	# model id (the key for the charging unit's own models).
	if charge_key == "":
		charge_key = model.get("id", "")
	var remaining: float = max(0.0, float(charge_distance) - _get_model_charge_accumulated(charge_key))
	if remaining <= 0.05:
		return {"found": false}

	# Pass A: straight push toward each target model.
	var best_pos: Vector2 = Vector2.ZERO
	var best_gap: float = INF
	for tp_data in targets_sorted:
		var edge0: float = _edge_gap_to_target(model, origin, tp_data)
		var travel: float = min(edge0 - 0.95, remaining)
		if travel <= 0.05:
			continue
		var dir_vec: Vector2 = tp_data["pos"] - origin
		if dir_vec.length() < 1.0:
			continue
		dir_vec = dir_vec.normalized()
		var candidate: Vector2 = origin + dir_vec * Measurement.inches_to_px(travel)
		if not _validate_charge_position(model, candidate):
			continue
		if _position_within_enemy_er(model, candidate, non_target_enemies):
			continue
		var gap_after: float = _edge_gap_to_target(model, candidate, tp_data)
		if gap_after >= edge0 - 0.05:
			continue  # not meaningfully closer to this target
		if gap_after < best_gap:
			best_gap = gap_after
			best_pos = candidate
	if best_gap < INF:
		return {"found": true, "position": best_pos, "gap": best_gap}

	# Pass B: straight lanes all blocked — angle/travel sweep, first legal wins
	# (targets nearest-first, longest travel first).
	var max_targets: int = min(targets_sorted.size(), 6)
	for frac in [0.85, 0.7, 0.55, 0.4, 0.25]:
		for i in range(max_targets):
			var tp_data = targets_sorted[i]
			var dir_vec: Vector2 = tp_data["pos"] - origin
			if dir_vec.length() < 1.0:
				continue
			dir_vec = dir_vec.normalized()
			var edge0: float = _edge_gap_to_target(model, origin, tp_data)
			# Never aim past the target's base: cap travel just short of contact.
			var travel: float = min(remaining * frac, max(edge0 - 0.1, 0.0))
			if travel <= 0.05:
				continue
			for angle_deg in [0.0, 12.0, -12.0, 25.0, -25.0, 38.0, -38.0]:
				var candidate: Vector2 = origin + dir_vec.rotated(deg_to_rad(angle_deg)) * Measurement.inches_to_px(travel)
				var gap_after: float = _edge_gap_to_target(model, candidate, tp_data)
				if gap_after >= edge0 - 0.05:
					continue
				if not _validate_charge_position(model, candidate):
					continue
				if _position_within_enemy_er(model, candidate, non_target_enemies):
					continue
				return {"found": true, "position": candidate, "gap": gap_after}
	return {"found": false}

# Shape-aware edge-to-edge gap (inches) between `model` placed at `at_pos` and
# the target model captured in a target_positions entry. Falls back to circle
# math if the entry carries no model dict.
func _edge_gap_to_target(model: Dictionary, at_pos: Vector2, tp_data: Dictionary) -> float:
	var tmodel = tp_data.get("model", {})
	if tmodel is Dictionary and not tmodel.is_empty():
		var test_model = model.duplicate()
		test_model["position"] = at_pos
		return Measurement.model_to_model_distance_inches(test_model, tmodel)
	var own_r: float = Measurement.base_radius_px(model.get("base_mm", 32))
	return Measurement.px_to_inches(at_pos.distance_to(tp_data["pos"]) - tp_data["radius"] - own_r)


# T-092: When ANY player (local, remote human, AI) declares a charge,
# render the charge arrows from charger to target on this client. The
# arrow visualization auto-fades after the existing hold/fade timing in
# ChargeArrowVisual. Skips re-drawing if the local player owns the
# charging unit (the local _update_visuals path already drew them).
func _on_targets_declared_remote_visual(unit_id: String, target_ids: Array) -> void:
	if unit_id == "" or target_ids.is_empty():
		return
	# Skip if local player owns the charging unit — local UI already drew arrows
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return
	var owner_player = int(unit.get("owner", 0))
	var local_player = GameState.get_active_player() if GameState else 0
	if owner_player == local_player:
		# Locally driven; _update_visuals handled it.
		return
	show_ai_charge_arrows(unit_id, target_ids)


# ============================================================================
# Multi-select drawing helpers (same look as the Movement phase versions)
# ============================================================================

class _SelectionBoxVisual extends Node2D:
	"""Custom drawn selection rectangle with fill + corner markers"""
	var box_size: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if box_size.length() < 1.0:
			return
		var rect = Rect2(Vector2.ZERO, box_size)
		# Semi-transparent blue fill
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.15))
		# Solid border
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 2.0)
		# Corner markers for clarity
		var corner_len = min(12.0, min(box_size.x, box_size.y) * 0.3)
		var c = Color(0.5, 0.85, 1.0, 1.0)
		var w = 3.0
		# Top-left
		draw_line(Vector2.ZERO, Vector2(corner_len, 0), c, w)
		draw_line(Vector2.ZERO, Vector2(0, corner_len), c, w)
		# Top-right
		draw_line(Vector2(box_size.x, 0), Vector2(box_size.x - corner_len, 0), c, w)
		draw_line(Vector2(box_size.x, 0), Vector2(box_size.x, corner_len), c, w)
		# Bottom-left
		draw_line(Vector2(0, box_size.y), Vector2(corner_len, box_size.y), c, w)
		draw_line(Vector2(0, box_size.y), Vector2(0, box_size.y - corner_len), c, w)
		# Bottom-right
		draw_line(box_size, Vector2(box_size.x - corner_len, box_size.y), c, w)
		draw_line(box_size, Vector2(box_size.x, box_size.y - corner_len), c, w)


class _SelectionRingIndicator extends Node2D:
	"""Pulsing selection ring drawn around a selected model"""
	var ring_radius: float = 16.0
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pulse = (sin(_time * 5.0) + 1.0) / 2.0  # 0..1 oscillation
		var alpha = 0.5 + pulse * 0.5
		# Outer glow ring
		draw_arc(Vector2.ZERO, ring_radius + 5.0, 0, TAU, 48, Color(0.3, 0.7, 1.0, alpha * 0.3), 4.0)
		# Main selection ring
		draw_arc(Vector2.ZERO, ring_radius + 3.0, 0, TAU, 48, Color(0.4, 0.8, 1.0, alpha), 2.5)
		# Inner fill circle
		draw_circle(Vector2.ZERO, ring_radius, Color(0.3, 0.6, 1.0, 0.1))
