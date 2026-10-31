extends Node2D
class_name LOSLineVisual

# LOSLineVisual — the LOS line tool (T11, design doc §6).
#
# While a shooter is selected in the Shooting phase and the cursor rests on an
# enemy unit, ShootingController draws ONE line through this node: from a
# shooter model's base centre to a target model's base centre, coloured by
# what the shooter can see.
#   clear    -> CONFIRMED_GREEN  visible, and no benefit of cover
#   obscured -> MARGINAL_YELLOW  visible, but the target has the benefit of
#                                cover (the shots take -1 BS, 11e 13.08)
#   blocked  -> INVALID_RED      no model can see any model: no shot
#
# The verdict comes from the rules engine's own predicates, so the line can
# never disagree with the target list or the hit roll:
#   - visibility: RulesEngine.unit_sight_line(), the predicate target
#     eligibility uses (11e HIDDEN 13.09 + base-aware obscuring / Solid sight
#     lines). Its pair is the line drawn: the nearest pair of models that can
#     see, or the nearest pair when nothing can.
#   - cover: TerrainManager.unit_has_cover_11e(target, firing model), the 13.08
#     test the hit roll applies per firing model, judged for the model the line
#     starts from (the line drawn is the line judged), or a stratagem-granted
#     cover flag. 10e (regression suite only) uses RulesEngine.check_unit_has_cover.
#
# The old version asked LineOfSightManager.check_los (10e point-to-point
# rules) and called any non-tall terrain under the centre line "obscured", so
# an 11e barricade between the units (light terrain: no sight line across it)
# came out yellow for a target the rules said could not be seen at all.
#
# current_line is {from, to, color_slot, los_state, shooter_id, target_id} or
# null when no line is drawn. from / to are board px (the base centres).

const LINE_SCREEN_PX := 3.0       # stroke width on screen, at every camera zoom
const END_DOT_SCREEN_PX := 4.0    # radius of the dot marking each base centre

const SLOT_FOR_STATE := {
	"clear": "CONFIRMED_GREEN",
	"obscured": "MARGINAL_YELLOW",
	"blocked": "INVALID_RED",
}

var current_line = null

var _line2d: Line2D = null
var _color: Color = Color.WHITE
var _applied_scale := -1.0
var _signature := ""
var _terrain_epoch := 0


func _ready() -> void:
	name = "LOSLineVisual"
	# Above the tokens (TokenVisual z_index 10), so the line runs all the way
	# to the base centres instead of vanishing under the token art.
	z_index = 11
	_line2d = Line2D.new()
	_line2d.name = "Line"
	_line2d.width = LINE_SCREEN_PX
	_line2d.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line2d.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line2d.antialiased = true
	_line2d.visible = false
	add_child(_line2d)
	var tm = get_node_or_null("/root/TerrainManager")
	if tm != null and tm.has_signal("terrain_loaded"):
		tm.terrain_loaded.connect(_on_terrain_loaded)
	set_process(false)


func _process(_delta: float) -> void:
	_apply_screen_scale(false)


func _draw() -> void:
	if current_line == null or _applied_scale <= 0.0:
		return
	var r := END_DOT_SCREEN_PX / _applied_scale
	draw_circle(current_line.from, r, _color)
	draw_circle(current_line.to, r, _color)


## Hover entry point (ShootingController._draw_los_line). Mouse motion calls
## this every frame the cursor moves over the target, so the pair is judged
## again only when something the verdict depends on changed: the two units'
## alive model positions or flags, the terrain, or the pair itself.
func show_line(shooter_id: String, target_id: String) -> Variant:
	var sig := _signature_for(shooter_id, target_id)
	if sig != "" and sig == _signature and current_line != null:
		return current_line
	var line = compute_line(shooter_id, target_id)
	if line != null:
		_signature = sig
	return line


## Judge the pair now and draw the line (or hide it: null when either unit has
## no model on the battlefield). Returns current_line.
func compute_line(shooter_id: String, target_id: String) -> Variant:
	_hide()
	var gs = get_node_or_null("/root/GameState")
	var uic = get_node_or_null("/root/UIConstants")
	if gs == null or uic == null or shooter_id == "" or target_id == "" or shooter_id == target_id:
		return null
	var verdict := judge(shooter_id, target_id, gs.create_snapshot(false))
	if verdict.is_empty():
		return null
	var state: String = verdict.los_state
	var slot: String = SLOT_FOR_STATE.get(state, "INVALID_RED")
	_color = uic.all_slots().get(slot, uic.INVALID_RED)
	current_line = {
		"from": verdict.from,
		"to": verdict.to,
		"color_slot": slot,
		"los_state": state,
		"shooter_id": shooter_id,
		"target_id": target_id,
	}
	_line2d.points = PackedVector2Array([verdict.from, verdict.to])
	_line2d.default_color = _color
	_line2d.visible = true
	set_process(true)
	_apply_screen_scale(true)
	DebugLogger.info("LOSLineVisual: T11 %s -> %s %s (%s) from %s to %s" % [
		shooter_id, target_id, state, slot, str(verdict.from), str(verdict.to)])
	return current_line


func clear_line() -> void:
	_hide()


## The verdict for one shooter -> target pair on `board` (a GameState
## snapshot): {from, to, los_state}, or {} when either unit has no model on the
## battlefield. Static so headless tests can judge a synthetic board.
static func judge(shooter_id: String, target_id: String, board: Dictionary) -> Dictionary:
	var units: Dictionary = board.get("units", {})
	var shooter: Dictionary = units.get(shooter_id, {})
	var target: Dictionary = units.get(target_id, {})
	if shooter.is_empty() or target.is_empty():
		return {}
	var sight: Dictionary = RulesEngine.unit_sight_line(shooter_id, target_id, board, false)
	var from_pt: Vector2 = sight.get("from", Vector2.ZERO)
	var to_pt: Vector2 = sight.get("to", Vector2.ZERO)
	var has_los := bool(sight.get("has_los", false))
	# unit_sight_line hands back (0, 0) -> (0, 0) when either unit has no
	# alive, positioned model: there is nothing to draw a line between.
	if not has_los and from_pt == Vector2.ZERO and to_pt == Vector2.ZERO:
		return {}
	var state := "blocked"
	if has_los:
		var firing_model := _model_at(shooter, from_pt)
		state = "obscured" if target_has_cover(target_id, shooter_id, firing_model, board) else "clear"
	return {"from": from_pt, "to": to_pt, "los_state": state}


## Does `target_id` have the benefit of cover against shots from
## `firing_model` (a model of `shooter_id`)? The same sources the hit roll
## applies: 11e 13.08 terrain / not fully visible / STEALTH via
## TerrainManager.unit_has_cover_11e, or a stratagem-granted cover flag.
static func target_has_cover(target_id: String, shooter_id: String, firing_model: Dictionary, board: Dictionary) -> bool:
	var target: Dictionary = board.get("units", {}).get(target_id, {})
	if target.is_empty():
		return false
	if bool(target.get("flags", {}).get("stratagem_cover", false)):
		return true
	if GameConstants.edition >= 11:
		var ml = Engine.get_main_loop()
		var tm = ml.root.get_node_or_null("TerrainManager") if ml != null and ml.root != null else null
		return tm != null and bool(tm.unit_has_cover_11e(target, firing_model))
	return RulesEngine.check_unit_has_cover(target_id, shooter_id, board)


# The alive model of `unit` standing at `pos` (unit_sight_line reports model
# positions, read with the same accessor), or {}.
static func _model_at(unit: Dictionary, pos: Vector2) -> Dictionary:
	for m in unit.get("models", []):
		if not m.get("alive", true):
			continue
		var p = m.get("position", null)
		var v := Vector2.INF
		if p is Vector2:
			v = p
		elif p is Dictionary:
			v = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
		if v.distance_to(pos) < 0.01:
			return m
	return {}


func _hide() -> void:
	current_line = null
	_signature = ""
	if _line2d != null:
		_line2d.visible = false
	set_process(false)
	queue_redraw()


# Keep the stroke and the end dots the same size on screen at every zoom.
func _apply_screen_scale(force: bool) -> void:
	var s := absf(get_global_transform_with_canvas().get_scale().x)
	if s < 0.0001:
		return
	if not force and is_equal_approx(s, _applied_scale):
		return
	_applied_scale = s
	_line2d.width = LINE_SCREEN_PX / s
	queue_redraw()


func _on_terrain_loaded(_features: Array) -> void:
	_terrain_epoch += 1


# Everything the verdict for this pair depends on, as one string ("" when a
# unit is unknown, which never matches, so the pair is judged again).
func _signature_for(shooter_id: String, target_id: String) -> String:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return ""
	var tm = get_node_or_null("/root/TerrainManager")
	var parts := PackedStringArray([shooter_id, target_id, str(_terrain_epoch),
		str(tm.terrain_features.size() if tm != null else -1), str(GameConstants.edition)])
	for uid in [shooter_id, target_id]:
		var unit = gs.get_unit(uid)
		if typeof(unit) != TYPE_DICTIONARY or unit.is_empty():
			return ""
		parts.append(str(hash(unit.get("flags", {}))))
		for m in unit.get("models", []):
			if m.get("alive", true):
				parts.append("%s@%s" % [str(m.get("position", null)), str(m.get("rotation", 0.0))])
	return "|".join(parts)
