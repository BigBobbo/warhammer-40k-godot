extends PanelContainer
class_name IntentPainter

# PM-6 — paint per-unit intents (earmarks) onto a finished Plan Editor
# deployment, so a saved plan says what each unit is FOR as well as where it
# stands.
#
# The vocabulary is CLOSED — the five verbs in PlanValidator.VERBS and nothing
# else. Adding a sixth means adding the mechanism that makes it real, in the
# same change (PLAN_FORMAT.md).
#
# Earmarks live in `meta.plan_earmarks` in exactly the shape the plan format
# uses, written through PhaseManager.apply_state_changes so the mutation goes
# down the sanctioned pipeline (ISS-001) rather than poking GameState.state.
# PlanRecorder reads them straight back out at save time.
#
# Node names are stable for windowed scenarios:
#   IntentPainterPanel / IntentUnitList / IntentStatusLabel /
#   IntentVerbHold / IntentVerbPush / IntentVerbScreen /
#   IntentVerbReserve2 / IntentVerbReserve3 / IntentVerbHunt / IntentVerbClear

const IntentOverlayScript = preload("res://scripts/IntentOverlay.gd")

const META_KEY: String = "meta.plan_earmarks"

# Abbreviations shown on the board badge. Keys are the schema verbs.
const BADGE_TEXT := {
	"HOLD_OBJECTIVE": "HOLD",
	"PUSH_CENTER": "PUSH",
	"SCREEN": "SCREEN",
	"RESERVE_UNTIL": "RES",
	"HUNT_CHARACTERS": "HUNT",
}

var unit_list: ItemList = null
var status_label: Label = null
var overlay: Node2D = null

# unit_id of the row currently selected in the list, "" when nothing is picked.
var selected_unit: String = ""
# Set while waiting for the author to click an objective for HOLD_OBJECTIVE.
var awaiting_objective_for: String = ""

var _unit_ids: Array = []      # list row index -> unit_id


# ============================================================
# Build
# ============================================================

func setup() -> void:
	name = "IntentPainterPanel"
	# Bottom-centre, over the half of the board that is always empty in an
	# editor session (there is no opponent), so the panel never covers the
	# units it is annotating.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -470.0
	offset_right = 470.0
	offset_top = -270.0
	offset_bottom = -80.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.05, 0.95)
	style.border_color = Color(1.0, 0.84, 0.35, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.name = "IntentPainterRoot"
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.name = "IntentPainterTitle"
	title.text = "INTENTS — what each unit is for"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	root.add_child(title)

	var body := HBoxContainer.new()
	body.name = "IntentPainterBody"
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	unit_list = ItemList.new()
	unit_list.name = "IntentUnitList"
	unit_list.custom_minimum_size = Vector2(340, 0)
	unit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_list.item_selected.connect(_on_unit_selected)
	body.add_child(unit_list)

	var right := VBoxContainer.new()
	right.name = "IntentVerbColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	var verbs_row := GridContainer.new()
	verbs_row.name = "IntentVerbGrid"
	verbs_row.columns = 3
	verbs_row.add_theme_constant_override("h_separation", 6)
	verbs_row.add_theme_constant_override("v_separation", 6)
	right.add_child(verbs_row)

	_add_verb_button(verbs_row, "IntentVerbHold", "Hold Objective",
		"Sit on a named objective — you pick which by clicking it on the board.",
		func(): _begin_hold_binding())
	_add_verb_button(verbs_row, "IntentVerbPush", "Push Centre",
		"Contest the middle of the board.",
		func(): _set_earmark({"verb": "PUSH_CENTER"}))
	_add_verb_button(verbs_row, "IntentVerbScreen", "Screen",
		"Body-block for the rest of the army instead of grabbing objectives.",
		func(): _set_earmark({"verb": "SCREEN"}))
	_add_verb_button(verbs_row, "IntentVerbReserve2", "Reserve R2",
		"Start in Reserves and arrive in battle round 2. Recorded as a reserve rather than at its board position.",
		func(): _set_earmark({"verb": "RESERVE_UNTIL", "round": 2}))
	_add_verb_button(verbs_row, "IntentVerbReserve3", "Reserve R3",
		"Start in Reserves and arrive in battle round 3.",
		func(): _set_earmark({"verb": "RESERVE_UNTIL", "round": 3}))
	_add_verb_button(verbs_row, "IntentVerbHunt", "Hunt Characters",
		"Prefer enemy CHARACTERs when picking shooting, charge and melee targets.",
		func(): _set_earmark({"verb": "HUNT_CHARACTERS"}))

	var clear_button := Button.new()
	clear_button.name = "IntentVerbClear"
	clear_button.text = "Clear intent"
	clear_button.tooltip_text = "Remove this unit's intent — it goes back to the AI's own judgement."
	clear_button.pressed.connect(_clear_earmark)
	right.add_child(clear_button)

	status_label = Label.new()
	status_label.name = "IntentStatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 40)
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	right.add_child(status_label)

	_ensure_overlay()
	refresh()
	_set_status("Pick a unit, then give it a job. Intents are hints — the AI still decides.")


func _add_verb_button(parent: Node, node_name: String, text: String, tooltip: String, on_press: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(160, 32)
	button.pressed.connect(on_press)
	parent.add_child(button)


func _ensure_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		return
	var main := get_tree().current_scene
	if main == null:
		return
	var board_root := main.get_node_or_null("BoardRoot")
	if board_root == null:
		return
	var existing = board_root.get_node_or_null("IntentOverlay")
	if existing != null:
		overlay = existing
		return
	overlay = IntentOverlayScript.new()
	overlay.name = "IntentOverlay"
	board_root.add_child(overlay)


# ============================================================
# Earmark state (meta.plan_earmarks)
# ============================================================

static func get_earmarks() -> Array:
	var raw = GameState.state.get("meta", {}).get("plan_earmarks", [])
	return raw if raw is Array else []


static func earmark_for(unit_id: String) -> Dictionary:
	for entry in get_earmarks():
		if entry is Dictionary and str(entry.get("unit", "")) == unit_id:
			return entry
	return {}


func _write_earmarks(earmarks: Array) -> void:
	# Through the pipeline, not straight into GameState.state — ISS-001.
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr != null and phase_mgr.has_method("apply_state_changes"):
		phase_mgr.apply_state_changes([{"op": "set", "path": META_KEY, "value": earmarks}])
	else:
		push_warning("IntentPainter: no PhaseManager — cannot record intents")


func _set_earmark(fields: Dictionary) -> void:
	if selected_unit == "":
		_set_status("Pick a unit first.")
		return
	awaiting_objective_for = ""

	var entry := {"unit": selected_unit}
	entry.merge(fields, true)

	var out: Array = []
	for existing in get_earmarks():
		if existing is Dictionary and str(existing.get("unit", "")) == selected_unit:
			continue
		out.append(existing)
	out.append(entry)
	_write_earmarks(out)

	var verb := str(entry.get("verb", ""))
	var suffix := ""
	if verb == "RESERVE_UNTIL":
		suffix = " (round %d) — it will be recorded as a reserve, not at its board position" % int(entry.get("round", 2))
	elif verb == "HOLD_OBJECTIVE":
		suffix = " on %s" % str(entry.get("target", "?"))
	_set_status("%s: %s%s" % [_display_name(selected_unit), verb, suffix])
	refresh()


func _clear_earmark() -> void:
	if selected_unit == "":
		_set_status("Pick a unit first.")
		return
	awaiting_objective_for = ""
	var out: Array = []
	for existing in get_earmarks():
		if existing is Dictionary and str(existing.get("unit", "")) == selected_unit:
			continue
		out.append(existing)
	_write_earmarks(out)
	_set_status("%s: no intent — back to the AI's own judgement." % _display_name(selected_unit))
	refresh()


# ============================================================
# HOLD_OBJECTIVE binding: click an objective on the board
# ============================================================

func _begin_hold_binding() -> void:
	if selected_unit == "":
		_set_status("Pick a unit first.")
		return
	awaiting_objective_for = selected_unit
	_set_status("Click the objective %s should hold." % _display_name(selected_unit))


func _unhandled_input(event: InputEvent) -> void:
	if awaiting_objective_for == "":
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var world := _world_mouse_position()
	var objective_id := _objective_at(world)
	if objective_id == "":
		_set_status("That is not an objective — click one of the markers, or pick a different intent.")
		return

	selected_unit = awaiting_objective_for
	_set_earmark({"verb": "HOLD_OBJECTIVE", "target": objective_id})
	get_viewport().set_input_as_handled()


func _world_mouse_position() -> Vector2:
	var main := get_tree().current_scene
	if main != null and main.has_method("screen_to_world_position"):
		return main.screen_to_world_position(get_viewport().get_mouse_position())
	return get_viewport().get_mouse_position()


func _objective_at(world_pos: Vector2) -> String:
	"""Nearest objective marker under the click.

	ObjectiveVisual is a plain Node2D with no input handling, so the painter
	hit-tests the marker positions itself. The tolerance is the objective's own
	radius plus a little, so a click anywhere on the visible disc counts."""
	var best_id := ""
	var best_dist := INF
	for obj in GameState.state.get("board", {}).get("objectives", []):
		if not (obj is Dictionary):
			continue
		var pos = obj.get("position", null)
		if pos == null:
			continue
		var p: Vector2 = pos if pos is Vector2 else Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
		var radius_px: float = Measurement.mm_to_px(float(obj.get("radius_mm", 40))) + 20.0
		var d: float = world_pos.distance_to(p)
		if d <= radius_px and d < best_dist:
			best_dist = d
			best_id = str(obj.get("id", ""))
	return best_id


# ============================================================
# Refresh
# ============================================================

func refresh() -> void:
	_refresh_unit_list()
	_refresh_overlay()


func _refresh_unit_list() -> void:
	if unit_list == null:
		return
	var previously := selected_unit
	unit_list.clear()
	_unit_ids.clear()

	var units = GameState.state.get("units", {})
	for unit_id in units.keys():
		var unit = units[unit_id]
		if not (unit is Dictionary) or int(unit.get("owner", 0)) != 1:
			continue
		# A character attached to a bodyguard fights as part of that unit, so it
		# is not separately steerable.
		var attached = unit.get("attached_to", null)
		if attached != null and str(attached) != "":
			continue
		var entry := earmark_for(str(unit_id))
		var suffix := ""
		if not entry.is_empty():
			suffix = "  —  %s" % _earmark_label(entry)
		unit_list.add_item("%s%s" % [_display_name(str(unit_id)), suffix])
		_unit_ids.append(str(unit_id))

	var idx := _unit_ids.find(previously)
	if idx >= 0:
		unit_list.select(idx)
		selected_unit = previously
	else:
		selected_unit = ""


func _refresh_overlay() -> void:
	_ensure_overlay()
	if overlay == null:
		return
	var badges: Array = []
	for entry in get_earmarks():
		if not (entry is Dictionary):
			continue
		var unit_id := str(entry.get("unit", ""))
		# NOT `:=` — these helpers return Vector2 OR null, and GDScript refuses
		# to infer a type from an untyped return (the parse error that silently
		# took the whole painter out of the build).
		var centroid = _unit_centroid(unit_id)
		if centroid == null:
			continue
		var badge := {"text": _earmark_label(entry), "at": centroid}
		var link = _link_target(entry)
		if link != null:
			badge["link_to"] = link
		badges.append(badge)
	overlay.set_badges(badges)


func _link_target(entry: Dictionary):
	"""Where the badge's line points: the bound objective for HOLD, the central
	objective for PUSH (which is what PUSH_CENTER actually biases toward — see
	AIDecisionMaker._plan_central_objective_ids), nothing for the rest."""
	var verb := str(entry.get("verb", ""))
	if verb == "HOLD_OBJECTIVE":
		return _objective_position(str(entry.get("target", "")))
	if verb == "PUSH_CENTER":
		var mission_mgr = get_node_or_null("/root/MissionManager")
		if mission_mgr != null and mission_mgr.has_method("get_objective_ids_by_designation"):
			var central: Array = mission_mgr.get_objective_ids_by_designation("central")
			if not central.is_empty():
				return _objective_position(str(central[0]))
	return null


func _objective_position(objective_id: String):
	for obj in GameState.state.get("board", {}).get("objectives", []):
		if obj is Dictionary and str(obj.get("id", "")) == objective_id:
			var pos = obj.get("position", null)
			if pos == null:
				return null
			return pos if pos is Vector2 else Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
	return null


func _unit_centroid(unit_id: String):
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if not (unit is Dictionary):
		return null
	var sum := Vector2.ZERO
	var n := 0
	for model in unit.get("models", []):
		if not (model is Dictionary):
			continue
		var pos = model.get("position", null)
		if pos == null:
			continue
		sum += pos if pos is Vector2 else Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
		n += 1
	if n == 0:
		return null
	return sum / float(n)


func _earmark_label(entry: Dictionary) -> String:
	var verb := str(entry.get("verb", ""))
	var text := str(BADGE_TEXT.get(verb, verb))
	if verb == "HOLD_OBJECTIVE":
		return "%s %s" % [text, str(entry.get("target", "?"))]
	if verb == "RESERVE_UNTIL":
		return "%s R%d" % [text, int(entry.get("round", 2))]
	return text


func _display_name(unit_id: String) -> String:
	"""meta.display_name where the army has one, else meta.name — the same
	resolution the deployment unit list uses. It matters here: recon_stomps has
	four units whose meta.name is bare "Stormboyz", and a painter list that
	cannot tell them apart is unusable."""
	return GameState.get_unit_display_name(unit_id)


func _on_unit_selected(index: int) -> void:
	if index < 0 or index >= _unit_ids.size():
		return
	selected_unit = str(_unit_ids[index])
	awaiting_objective_for = ""
	var entry := earmark_for(selected_unit)
	if entry.is_empty():
		_set_status("%s has no intent yet." % _display_name(selected_unit))
	else:
		_set_status("%s: %s" % [_display_name(selected_unit), _earmark_label(entry)])


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
