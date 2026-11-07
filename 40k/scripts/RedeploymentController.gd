extends Node

## WP-G1 (Codex 11e gaps) — the Redeployment step a HUMAN player can use.
##
## Rules served (phases/RedeploymentPhase.gd resolves them):
##   Castellan's Mark (Codex: Adeptus Custodes) / Kaptin's Hat (Codex: Orks) /
##   Razgit's Magik Map: "When both players have deployed their armies, you can
##   redeploy up to three friendly <KEYWORD> units. When doing so, you can set
##   those units up in strategic reserves, regardless of how many units are
##   already in strategic reserves." Units with a datasheet redeploy ability
##   resolve here too. Core rules: resolved after Deploy Armies, before the
##   first turn; players alternate, starting with the Attacker; normal
##   deployment rules apply.
##
## UI: a right-panel list of the active player's eligible units (keyword
## filter and the three-use limit come from the phase's get_redeploy_menu()),
## with per-unit [Redeploy] [Reserves] [Keep] buttons and [Done Redeploying].
## [Redeploy] picks the unit (and its attached CHARACTERs) up and re-places it
## with the DeploymentController ghost UI (zone / Infiltrators / overlap /
## walls / coherency); [Confirm] dispatches the atomic REDEPLOY_UNIT. While the
## AI or a remote player is resolving, the panel says so.
##
## Main.gd creates this in setup_phase_controllers() for the REDEPLOYMENT phase
## (thin hook) and frees it on the next phase change.

const PANEL_SCROLL_NAME := "RedeploymentScrollContainer"
const PANEL_NAME := "RedeploymentPanel"

var main: Node = null
var _scroll: ScrollContainer = null
var _panel: VBoxContainer = null
var _picker_host: VBoxContainer = null
var _placer: Node = null            # DeploymentController instance while placing
var _placing_unit_id: String = ""
var _placing_group: Array = []      # unit ids picked up (unit + attached characters)
var _coherency_msg: String = ""
var _refresh_queued := false

func setup(p_main: Node) -> void:
	main = p_main
	_build_panel()
	var pm = get_node_or_null("/root/PhaseManager")
	if pm and not pm.phase_action_taken.is_connected(_on_state_changed):
		pm.phase_action_taken.connect(_on_state_changed)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("result_applied") and not gm.result_applied.is_connected(_on_state_changed):
		gm.result_applied.connect(_on_state_changed)
	# Deployment rules apply: show the deployment zones for the whole step.
	if main and main.has_method("update_deployment_zone_visibility"):
		main.update_deployment_zone_visibility()
	_queue_refresh()
	print("[RedeploymentController] WP-G1 Redeployment step UI ready (active player %d)" % GameState.get_active_player())

func _exit_tree() -> void:
	_teardown_placer(true)
	var pm = get_node_or_null("/root/PhaseManager")
	if pm and pm.phase_action_taken.is_connected(_on_state_changed):
		pm.phase_action_taken.disconnect(_on_state_changed)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("result_applied") and gm.result_applied.is_connected(_on_state_changed):
		gm.result_applied.disconnect(_on_state_changed)
	# The panel is removed by Main._clear_right_panel_phase_ui on the next
	# phase change (it matches "ScrollContainer"); free it here too.
	if _scroll and is_instance_valid(_scroll):
		_scroll.queue_free()

# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

func _phase():
	var pm = get_node_or_null("/root/PhaseManager")
	if pm == null:
		return null
	var ph = pm.get_current_phase_instance()
	if ph == null or not ph.has_method("get_redeploy_menu"):
		return null
	return ph

func is_local_human_turn() -> bool:
	var ap := GameState.get_active_player()
	var ai = get_node_or_null("/root/AIPlayer")
	if ai and ai.is_ai_player(ap):
		return false
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.is_networked() and not nm.is_local_player_turn():
		return false
	return true

func is_placing() -> bool:
	return _placing_unit_id != ""

func get_placing_unit_id() -> String:
	return _placing_unit_id

func _on_state_changed(_payload = null) -> void:
	_queue_refresh()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_refresh")

func _do_refresh() -> void:
	_refresh_queued = false
	refresh()

# ---------------------------------------------------------------------------
# Panel
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	var container = get_node_or_null("/root/Main/HUD_Right/VBoxContainer")
	if container == null and main:
		container = main.get_node_or_null("HUD_Right/VBoxContainer")
	if container == null:
		push_warning("[RedeploymentController] HUD_Right/VBoxContainer not found — no panel")
		return
	var old = container.get_node_or_null(PANEL_SCROLL_NAME)
	if old:
		container.remove_child(old)
		old.queue_free()
	_scroll = ScrollContainer.new()
	_scroll.name = PANEL_SCROLL_NAME
	_scroll.custom_minimum_size = Vector2(250, 360)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(_scroll)
	var outer := VBoxContainer.new()
	outer.name = "RedeploymentOuter"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(outer)
	_panel = VBoxContainer.new()
	_panel.name = PANEL_NAME
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	outer.add_child(_panel)
	# Persistent host for the DeploymentController's model-type picker (an
	# Attached unit = bodyguard + leader types); _panel is rebuilt on refresh.
	_picker_host = VBoxContainer.new()
	_picker_host.name = "PickerHost"
	_picker_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_picker_host)
	# The deployment unit list / unit card have nothing to offer here.
	for n in ["UnitListPanel", "UnitCard"]:
		var c = container.get_node_or_null(n)
		if c is CanvasItem:
			c.visible = false

func _label(text: String, size: int = 14, color: Color = WhiteDwarfTheme.WH_PARCHMENT, node_name: String = "") -> Label:
	var l := Label.new()
	if node_name != "":
		l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, node_name: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		WhiteDwarfTheme.apply_primary_button(b)
	else:
		WhiteDwarfTheme.apply_to_button(b)
	b.pressed.connect(cb)
	return b

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	var ph = _phase()
	if ph == null:
		return
	var ap := GameState.get_active_player()
	var title := _label("REDEPLOYMENT", 19, WhiteDwarfTheme.WH_GOLD, "Title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)
	WhiteDwarfTheme.add_gold_separator(_panel)

	if not is_local_human_turn():
		_panel.add_child(_label("Player %d is resolving their redeployments..." % ap, 15, WhiteDwarfTheme.WH_BONE, "WaitingLabel"))
		return

	var menu: Dictionary = ph.get_redeploy_menu(ap)
	var enh := str(menu.get("enhancement", ""))
	var kw := " ".join(menu.get("keywords", []))
	var head := "Player %d" % ap
	if enh != "":
		head += " — %s: redeploy up to three %s units, or set them up in Strategic Reserves (%d left)" % [enh, kw if kw != "" else "eligible", int(menu.get("uses_left", 0))]
	_panel.add_child(_label(head, 14, WhiteDwarfTheme.WH_PARCHMENT, "HeaderLabel"))

	if is_placing():
		_build_placing_section()
		return

	var units: Array = menu.get("units", [])
	if units.is_empty():
		_panel.add_child(_label("Nothing left to redeploy.", 14, WhiteDwarfTheme.WH_BONE, "EmptyLabel"))
	var list := VBoxContainer.new()
	list.name = "UnitRows"
	list.add_theme_constant_override("separation", 8)
	_panel.add_child(list)
	for row in units:
		var uid := str(row.unit_id)
		var box := VBoxContainer.new()
		box.name = "Row_%s" % uid
		var tags := []
		if bool(row.get("infiltrators", false)):
			tags.append("Infiltrators")
		if bool(row.get("ability", false)):
			tags.append("own ability")
		var text := "%s (%d models)%s" % [str(row.label), int(row.models), (" [" + ", ".join(tags) + "]") if tags.size() > 0 else ""]
		box.add_child(_label(text, 14, WhiteDwarfTheme.WH_BONE, "Name"))
		var btns := HBoxContainer.new()
		btns.name = "Buttons"
		var rb := _button("Redeploy", "Redeploy_%s" % uid, _on_redeploy_pressed.bind(uid), true)
		rb.disabled = not bool(row.get("can_redeploy", false))
		btns.add_child(rb)
		if bool(row.get("can_reserve", false)) or not bool(row.get("ability", false)):
			var sb := _button("Reserves", "Reserves_%s" % uid, _on_reserves_pressed.bind(uid))
			sb.disabled = not bool(row.get("can_reserve", false))
			sb.tooltip_text = "Set this unit up in Strategic Reserves (ignores the reserves limit)"
			btns.add_child(sb)
		btns.add_child(_button("Keep", "Skip_%s" % uid, _on_skip_pressed.bind(uid)))
		box.add_child(btns)
		list.add_child(box)
	WhiteDwarfTheme.add_gold_separator(_panel)
	var done_text := "Done Redeploying"
	if int(menu.get("opponent_pending", 0)) > 0:
		done_text += " (Player %d next)" % (3 - ap)
	_panel.add_child(_button(done_text, "DoneButton", _on_done_pressed, true))

func _build_placing_section() -> void:
	var unit = GameState.get_unit(_placing_unit_id)
	var name_s := str(unit.get("meta", {}).get("name", _placing_unit_id))
	var placed: int = _placer.get_placed_count() if _placer else 0
	var total: int = _placer.get_total_model_count() if _placer else 0
	_panel.add_child(_label("Re-placing %s" % name_s, 16, WhiteDwarfTheme.WH_GOLD, "PlacingTitle"))
	var hint := "Click to set up each model wholly within your deployment zone (Q/E or wheel rotate, Shift+click a model to move it)."
	if GameState.unit_has_infiltrators(_placing_unit_id):
		hint = "Infiltrators: set up each model more than %d\" from the enemy deployment zone and enemy models." % (8 if GameConstants.edition >= 11 else 9)
	_panel.add_child(_label(hint, 13, WhiteDwarfTheme.WH_BONE, "PlacingHint"))
	_panel.add_child(_label("Models placed: %d / %d" % [placed, total], 14, WhiteDwarfTheme.WH_PARCHMENT, "PlacedCount"))
	if _coherency_msg != "":
		_panel.add_child(_label(_coherency_msg, 13, Color(1.0, 0.45, 0.35), "CoherencyLabel"))
	var row := HBoxContainer.new()
	row.name = "FormationButtons"
	for mode in ["SINGLE", "SPREAD", "TIGHT"]:
		var b := _button(mode.capitalize(), "Formation_%s" % mode, _on_formation_pressed.bind(mode))
		b.toggle_mode = true
		b.button_pressed = _placer != null and str(_placer.formation_mode) == mode
		row.add_child(b)
	_panel.add_child(row)
	var cb := _button("Confirm Redeploy", "ConfirmRedeployButton", _on_confirm_pressed, true)
	cb.disabled = placed < total or total == 0
	_panel.add_child(cb)
	var row2 := HBoxContainer.new()
	row2.name = "PlacingButtons"
	row2.add_child(_button("Undo", "UndoRedeployButton", _on_undo_pressed))
	row2.add_child(_button("Cancel", "CancelRedeployButton", _on_cancel_pressed))
	_panel.add_child(row2)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _route(action: Dictionary) -> Dictionary:
	action["player"] = GameState.get_active_player()
	var r = NetworkIntegration.route_action(action)
	if not (r is Dictionary):
		return {}
	if not r.get("success", false) and not r.get("pending", false):
		var errs: Array = r.get("errors", [])
		var msg := str(errs[0]) if errs.size() > 0 else str(r.get("error", r.get("message", "Action rejected")))
		var tm = get_node_or_null("/root/ToastManager")
		if tm:
			tm.show_error(msg)
		print("[RedeploymentController] %s rejected: %s" % [action.get("type", ""), str(r)])
	return r

func _on_skip_pressed(unit_id: String) -> void:
	print("[RedeploymentController] Keep (skip redeploy) %s" % unit_id)
	_route({"type": "SKIP_REDEPLOY", "unit_id": unit_id})
	_queue_refresh()

func _on_reserves_pressed(unit_id: String) -> void:
	print("[RedeploymentController] Send %s to Strategic Reserves" % unit_id)
	var r := _route({"type": "SEND_TO_STRATEGIC_RESERVES", "unit_id": unit_id})
	if r.get("success", false):
		var tm = get_node_or_null("/root/ToastManager")
		if tm:
			tm.show_success("%s set up in Strategic Reserves" % str(GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id)))
		_refresh_visuals()
	_queue_refresh()

func _on_done_pressed() -> void:
	print("[RedeploymentController] Done redeploying (Player %d)" % GameState.get_active_player())
	cancel_placement()
	_route({"type": "END_REDEPLOYMENT_PHASE"})
	_queue_refresh()

## Main's End Redeployment button calls this before ending the step.
func cancel_placement() -> void:
	if is_placing():
		_teardown_placer(true)
		_refresh_visuals()

func _on_redeploy_pressed(unit_id: String) -> void:
	if is_placing() or not is_local_human_turn():
		return
	var ph = _phase()
	if ph == null:
		return
	var v: Dictionary = ph.validate_action({"type": "BEGIN_REDEPLOY", "unit_id": unit_id, "player": GameState.get_active_player()})
	if not v.get("valid", false):
		var tm = get_node_or_null("/root/ToastManager")
		if tm:
			tm.show_error(str(v.get("errors", ["Cannot redeploy"])[0]))
		return
	begin_placement(unit_id)

func begin_placement(unit_id: String) -> void:
	_teardown_placer(true)
	var ph = _phase()
	_placing_group = ph._redeploy_group_unit_ids(unit_id) if ph else [unit_id]
	_placing_unit_id = unit_id
	_coherency_msg = ""
	# Pick the unit (and its leaders) up: DEPLOYING hides their tokens and
	# takes them out of the overlap checks while they are re-placed (the same
	# local marker the deployment / scout-reserves set-ups use).
	_set_group_status(GameStateData.UnitStatus.DEPLOYING)
	var dc_script = load("res://scripts/DeploymentController.gd")
	_placer = dc_script.new()
	_placer.name = "RedeployPlacement"
	add_child(_placer)
	_placer.set_layers(main.token_layer, main.ghost_layer)
	_placer.is_redeploy_mode = true
	_placer.unit_id = unit_id
	_placer.model_idx = 0
	_placer.placement_order.clear()
	_placer.setup_placement_models(unit_id)
	_placer.formation_mode = "SINGLE"
	_placer.formation_rotation = 0.0
	_placer.setup_model_type_picker()
	_placer.is_infiltrators_mode = GameState.unit_has_infiltrators(unit_id)
	if _placer.is_infiltrators_mode:
		_placer._show_infiltrator_exclusion()
	_placer.models_placed_changed.connect(_queue_refresh)
	_placer.coherency_warning_changed.connect(_on_coherency_warning)
	# The picker docks in the (hidden) unit card; show it in this panel.
	var picker = _placer.model_type_picker_panel
	if picker and is_instance_valid(picker) and _picker_host and picker.get_parent() != _picker_host:
		if picker.get_parent():
			picker.get_parent().remove_child(picker)
		_picker_host.add_child(picker)
	var wait_pick := false
	if _placer.has_model_type_picker and not _placer._try_auto_select_model_type():
		_placer.model_idx = _placer.temp_positions.size()
		wait_pick = true
	if not wait_pick:
		_placer._create_ghost()
	if main and main.has_method("update_deployment_zone_visibility"):
		main.update_deployment_zone_visibility()
	_refresh_visuals()
	print("[RedeploymentController] Begin re-placing %s (%d models incl. attached characters)" % [unit_id, _placer.get_total_model_count()])
	_queue_refresh()

func _on_coherency_warning(is_incoherent: bool, message: String) -> void:
	_coherency_msg = message if is_incoherent else ""
	_queue_refresh()

func _on_formation_pressed(mode: String) -> void:
	if _placer:
		_placer.set_formation_mode(mode)
	_queue_refresh()

func _on_undo_pressed() -> void:
	if _placer:
		_placer.undo_last_model()
	_queue_refresh()

func _on_cancel_pressed() -> void:
	print("[RedeploymentController] Cancel re-placing %s" % _placing_unit_id)
	cancel_placement()
	_queue_refresh()

## The placements the DeploymentController holds, as REDEPLOY_UNIT wants them.
func collect_placements() -> Array:
	var out: Array = []
	if _placer == null:
		return out
	for i in range(_placer.temp_positions.size()):
		var pos = _placer.temp_positions[i]
		if pos == null:
			continue
		var muid := _placing_unit_id
		var model: Dictionary = {}
		if _placer.is_combined_deployment and i < _placer.combined_models.size():
			muid = str(_placer.combined_models[i].unit_id)
			model = GameState.get_unit(muid).get("models", [])[int(_placer.combined_models[i].model_idx)]
		else:
			model = GameState.get_unit(muid).get("models", [])[i]
		var rot := float(_placer.temp_rotations[i]) if i < _placer.temp_rotations.size() else 0.0
		out.append({"unit_id": muid, "model_id": str(model.get("id", "")), "x": pos.x, "y": pos.y, "rotation": rot})
	return out

func _on_confirm_pressed() -> void:
	if not is_placing():
		return
	var unit_id := _placing_unit_id
	var placements := collect_placements()
	print("[RedeploymentController] Confirm redeploy %s with %d placements" % [unit_id, placements.size()])
	var r := _route({"type": "REDEPLOY_UNIT", "unit_id": unit_id, "placements": placements})
	if r.get("success", false) or r.get("pending", false):
		_teardown_placer(false)
		var tm = get_node_or_null("/root/ToastManager")
		if tm:
			tm.show_success("%s redeployed" % str(GameState.get_unit(unit_id).get("meta", {}).get("name", unit_id)))
		_refresh_visuals()
	_queue_refresh()

func _set_group_status(status: int) -> void:
	var changes: Array = []
	for uid in _placing_group:
		changes.append({"op": "set", "path": "units.%s.status" % uid, "value": status})
	var pm = get_node_or_null("/root/PhaseManager")
	if pm and pm.current_phase_instance and changes.size() > 0:
		pm.apply_state_changes(changes)

## restore_units: put the picked-up units back where they were (cancel).
func _teardown_placer(restore_units: bool) -> void:
	if _placer and is_instance_valid(_placer):
		_placer._clear_previews()
		_placer._clear_formation_ghosts()
		_placer._remove_ghost()
		_placer._hide_infiltrator_exclusion()
		_placer._hide_model_type_picker()
		_placer.unit_id = ""
		_placer.queue_free()
	_placer = null
	if restore_units and _placing_unit_id != "":
		for uid in _placing_group:
			if int(GameState.get_unit(uid).get("status", 0)) == GameStateData.UnitStatus.DEPLOYING:
				var pm = get_node_or_null("/root/PhaseManager")
				if pm and pm.current_phase_instance:
					pm.apply_state_changes([{"op": "set", "path": "units.%s.status" % uid, "value": GameStateData.UnitStatus.DEPLOYED}])
	_placing_unit_id = ""
	_placing_group = []
	_coherency_msg = ""

func _refresh_visuals() -> void:
	if main and main.has_method("_recreate_unit_visuals"):
		main._recreate_unit_visuals()
	if main and main.has_method("refresh_reserves_ui"):
		main.refresh_reserves_ui()
