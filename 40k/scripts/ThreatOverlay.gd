extends Node2D
class_name ThreatOverlay

# ThreatOverlay — held-key enemy threat view (T10, design doc §6: "a held-key
# threat view (Tab) that paints all enemy units' shooting ranges + their 12"
# charge-threat ring"). Off by default: a permanent enemy threat overlay is a
# doc §6 anti-pattern.
#
# While active, for every ENEMY unit on the battlefield (enemy = not the
# viewer's seat, see viewer_player()):
#   - shooting threat, UIConstants.MARGINAL_YELLOW filled at 15% alpha:
#     everywhere a target's base can be and still be in range of the unit's
#     longest ranged weapon, measured base edge to base edge from every alive
#     model (the engine measures weapon and charge ranges edge to edge);
#   - charge threat, UIConstants.INVALID_RED filled at 10% alpha: everywhere
#     within the 12" charge-declaration range (ChargePhase.CHARGE_RANGE_INCHES),
#     also edge to edge from every model.
#
# Readability rules (doc §5, §6, §9):
#   - One ring per unit, never one per model: a multi-model unit's area is the
#     UNION of its models' circles and is outlined once (union_outline()).
#   - Overlaps never stack: each fill layer is a CanvasGroup whose alpha is
#     applied to the merged shape, so eight overlapping circles still read as
#     one 15% wash instead of saturating into an opaque blob.
#   - Every ring keeps a crisp outline (OUTLINE_SCREEN_PX on screen at any
#     zoom) in its slot colour, so the rings stay distinct where washes merge:
#     shooting rings solid, charge rings dashed (as the Charge phase's T30
#     rings), so a 12" gun's yellow ring still shows under its red one.
#   - Everything is clipped to the battlefield rectangle.
#   - A unit with no ranged weapon has no shooting threat: its "shoot" entry
#     has radius_px 0.0 and nothing yellow is drawn for it (the old code drew
#     a made-up 24" circle round melee-only units).
#   - An attached CHARACTER is part of its bodyguard's unit: one ring pair per
#     Attached unit, keyed by the bodyguard id.
#
# Input (rebindable action "threat_overlay", default Tab), via
# Main._input -> handle_key_event(): press -> on, release -> off. Key repeat
# is swallowed (repeated Tab would otherwise walk GUI focus round the HUD while
# the key is held) and the release counts whatever modifiers are down by then.
# If the key-up never arrives (a dialog or another app took the keyboard),
# _process sees the key is up and turns the view off.
# Shooting phase: Tab is also "cycle shooter" (shoot_cycle_eligible_unit), so
# ShootingController hands that press to begin_tap_or_hold(): a TAP cycles on
# the key-up, a HOLD (HOLD_THRESHOLD_S or longer) shows this view instead.
#
# Public state for scenarios and tests:
#   active : bool                       assignable; same as set_active()
#   rendered_rings : Array[Dictionary]  one "shoot" + one "charge" entry per
#       enemy unit: {unit_id, kind: "shoot"|"charge", color_slot, radius_px,
#       range_inches}. radius_px is the largest model circle (range + base).
#   viewer_player_id : int              whose enemies were painted
#   activation_count : int              off -> on transitions (flicker checks)
#   last_change_reason : String         what last turned it on / off
#
# Self-installs under /root/Main/BoardRoot via
# Main._install_design_guidelines_overlays().

const ACTION_ID := "threat_overlay"
const CHARGE_RANGE_INCHES := 12.0
const SHOOT_FILL_ALPHA := 0.15
const CHARGE_FILL_ALPHA := 0.10
const OUTLINE_ALPHA := 0.9
const OUTLINE_SCREEN_PX := 2.0
const CHARGE_DASH_SCREEN_PX := 10.0
const CHARGE_GAP_SCREEN_PX := 6.0
## Board px between outline / fill vertices (sub-pixel error at any zoom).
const ARC_STEP_PX := 24.0
const MIN_CIRCLE_STEPS := 32
const MAX_CIRCLE_STEPS := 256
## How long the shared Shooting-phase key must be held before it counts as a
## hold (threat view) rather than a tap (cycle shooter).
const HOLD_THRESHOLD_S := 0.2
const SLOT_FOR_KIND := {"shoot": "MARGINAL_YELLOW", "charge": "INVALID_RED"}
const _EPS := 0.01

var _active := false
var active: bool:
	get:
		return _active
	set(value):
		set_active(value)

var rendered_rings: Array[Dictionary] = []
var viewer_player_id: int = 0
var activation_count: int = 0
## Why the view last turned on or off ("key held", "key released", "shared key
## held 0.2s", "key no longer down", "window lost focus", "scripted").
var last_change_reason: String = ""

# Key state: _held_by_key while a held key owns the view (or a tap/hold is
# pending); _key_seen_down once _process has seen that key down, so a key-up
# that never arrived can be detected (synthetic events that bypass Input never
# set it, and so never trip that release).
var _held_by_key := false
var _key_seen_down := false
var _tap_action: Callable = Callable()
var _tap_started_ms := 0

var _fill_polys := {"shoot": [], "charge": []}
var _outlines := {"shoot": [], "charge": []}
var _outline_scale := -1.0
var _refresh_queued := false

var _shoot_fill: CanvasGroup
var _charge_fill: CanvasGroup
var _outline_layer: Node2D


func _init() -> void:
	# Built once and kept: toggling only changes `visible` and redraws, so a
	# rapid press/release never frees or re-adds nodes (no flicker, and the
	# node paths scenarios read never change).
	_shoot_fill = _make_fill_layer("ShootFill", "shoot", SHOOT_FILL_ALPHA)
	_charge_fill = _make_fill_layer("ChargeFill", "charge", CHARGE_FILL_ALPHA)
	_outline_layer = Node2D.new()
	_outline_layer.name = "Outlines"
	_outline_layer.draw.connect(_draw_outlines)
	add_child(_outline_layer)
	visible = false
	set_process(false)


func _ready() -> void:
	name = "ThreatOverlay"
	z_index = 4  # Above terrain (-8) and the cover icons (2), below tokens (10).
	# Units move / die / change hands while the key is held (the opponent's
	# turn, a reaction): rebuild then, at most once a frame.
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null:
		if pm.has_signal("phase_action_taken"):
			pm.phase_action_taken.connect(_queue_refresh)
		if pm.has_signal("phase_changed"):
			pm.phase_changed.connect(_queue_refresh)


# ---------------------------------------------------------------------------
# On / off
# ---------------------------------------------------------------------------

## Scripted on/off (scenarios, tests): not tied to a held key.
func set_active(value: bool) -> void:
	_tap_action = Callable()
	_held_by_key = false
	_apply_active(value, "scripted")


## Rebuild from the current board while shown (no-op when off).
func refresh() -> void:
	if _active:
		_build()


func _apply_active(value: bool, reason: String) -> void:
	if value == _active:
		return
	_active = value
	last_change_reason = reason
	if _active:
		activation_count += 1
		var t0 := Time.get_ticks_usec()
		_build()
		visible = true
		_log("on (%s): %d enemy unit(s) for viewer P%d, %d ring(s), built in %.1f ms" % [
			reason, rendered_rings.size() / 2, viewer_player_id, rendered_rings.size(),
			float(Time.get_ticks_usec() - t0) / 1000.0])
	else:
		_clear()
		visible = false
		_log("off (%s)" % reason)
	_update_processing()


func _update_processing() -> void:
	set_process(_active or _held_by_key)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Main._input hands every key event here (after its text-field and history
## guards). Returns true when the event belonged to the threat view and must
## be consumed.
func handle_key_event(event: InputEventKey) -> bool:
	var km = get_node_or_null("/root/KeybindingManager")
	if km == null:
		return false
	if event.pressed:
		if not km.matches_action(event, ACTION_ID):
			return false
		# Key repeat while held changes nothing, but is consumed: Tab repeats
		# would otherwise reach the GUI as ui_focus_next and hop the focus ring
		# round the HUD for as long as the key is down.
		if not event.echo:
			_tap_action = Callable()
			_held_by_key = true
			_key_seen_down = false
			_apply_active(true, "key held")
		return true
	# Key-up. matches_action() is modifier-strict: a Shift pressed while Tab
	# was held would make the release miss and strand the view on. The bound
	# keycode alone decides here.
	if not _is_bound_keycode(km, event.keycode):
		return false
	if _tap_action.is_valid():
		# Up before HOLD_THRESHOLD_S: a tap of the shared key.
		var tap := _tap_action
		_tap_action = Callable()
		_held_by_key = false
		_update_processing()
		_log("tap of the shared key: running %s" % str(tap.get_method()))
		tap.call()
		return true
	if _active and _held_by_key:
		_held_by_key = false
		_apply_active(false, "key released")
		return true
	return false


## Shooting-phase hand-off: ShootingController calls this on the press of a
## key it shares with the threat view (by default Tab is "cycle shooter" too)
## instead of acting at once. Released within HOLD_THRESHOLD_S, `tap_action`
## runs on the key-up (a normal cycle); held longer, the view shows until the
## key-up and `tap_action` never runs.
func begin_tap_or_hold(tap_action: Callable) -> void:
	_tap_action = tap_action
	_tap_started_ms = Time.get_ticks_msec()
	_held_by_key = true
	_key_seen_down = false
	_update_processing()


func is_tap_pending() -> bool:
	return _tap_action.is_valid()


func _process(_delta: float) -> void:
	if _held_by_key:
		var km = get_node_or_null("/root/KeybindingManager")
		var down: bool = km != null and _bound_key_down(km)
		if down:
			_key_seen_down = true
		elif _key_seen_down:
			# The key is up but its key-up never reached Main: a dialog or
			# another window took the keyboard. Stand down without acting.
			_held_by_key = false
			if _tap_action.is_valid():
				_tap_action = Callable()
				_log("tap/hold dropped: the key went up while focus was elsewhere")
				_update_processing()
			else:
				_apply_active(false, "key no longer down")
			return
		if down and _tap_action.is_valid() \
				and Time.get_ticks_msec() - _tap_started_ms >= int(HOLD_THRESHOLD_S * 1000.0):
			_tap_action = Callable()
			_apply_active(true, "shared key held %.1fs" % HOLD_THRESHOLD_S)
	if _active:
		# Outline widths are in screen px: redraw when the camera zoom changes.
		var s := _screen_scale()
		if absf(s - _outline_scale) > 0.005 * maxf(s, 0.0001):
			_outline_layer.queue_redraw()


func _notification(what: int) -> void:
	# Focus lost while held: Godot drops its "key is down" cache, the key-up
	# goes to whatever took focus, and _process would only notice once it sees
	# the key up. Stand down straight away instead.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _held_by_key:
			_held_by_key = false
			_tap_action = Callable()
			_apply_active(false, "window lost focus")
			_update_processing()


func _is_bound_keycode(km, keycode: int) -> bool:
	if keycode == 0:
		return false
	var b: Dictionary = km.get_binding(ACTION_ID)
	return keycode == int(b.get("key", 0)) or keycode == int(b.get("alt_key", 0))


func _bound_key_down(km) -> bool:
	var b: Dictionary = km.get_binding(ACTION_ID)
	for kc in [int(b.get("key", 0)), int(b.get("alt_key", 0))]:
		if kc != 0 and (Input.is_key_pressed(kc) or Input.is_physical_key_pressed(kc)):
			return true
	return false


# ---------------------------------------------------------------------------
# Who is the enemy, and where are they
# ---------------------------------------------------------------------------

## Whose screen this is. Networked: the local seat. One human against the AI:
## the human's seat, on either player's turn. Hot-seat (or AI vs AI): the
## player whose turn it is.
func viewer_player() -> int:
	var nm = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("is_networked") and nm.is_networked() \
			and nm.has_method("get_local_player"):
		var local := int(nm.get_local_player())
		if local > 0:
			return local
	var ai = get_node_or_null("/root/AIPlayer")
	if ai != null and ai.has_method("is_ai_player"):
		var p1_ai := bool(ai.is_ai_player(1))
		var p2_ai := bool(ai.is_ai_player(2))
		if p1_ai != p2_ai:
			return 2 if p1_ai else 1
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		return int(gs.state.get("meta", {}).get("active_player", 1))
	return 1


## Every enemy unit on the battlefield, sorted by unit id:
## [{unit_id, models: [{pos: Vector2, extent: float, shoot_inches: float}]}].
## An attached CHARACTER's models join its bodyguard's entry (one Attached
## unit = one unit), each keeping its own unit's weapon range.
func threat_units(state: Dictionary, viewer: int) -> Array:
	var units: Dictionary = state.get("units", {})
	var re = get_node_or_null("/root/RulesEngine")
	var groups := {}
	var ids: Array = units.keys()
	ids.sort()
	for uid in ids:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var owner := int(u.get("owner", 0))
		if owner <= 0 or owner == viewer:
			continue
		if not is_on_battlefield(u):
			continue
		var head := str(uid)
		if re != null and re.has_method("attached_unit_target_id"):
			head = str(re.attached_unit_target_id(str(uid), state))
		if not groups.has(head):
			groups[head] = {"unit_id": head, "models": []}
		var shoot_inches := longest_ranged_weapon_inches(u)
		for m in u.get("models", []):
			if typeof(m) != TYPE_DICTIONARY or not m.get("alive", true):
				continue
			var pos := model_position(m)
			if pos == Vector2.INF:
				continue
			groups[head]["models"].append({
				"pos": pos, "extent": _base_extent_px(m), "shoot_inches": shoot_inches})
	var heads: Array = groups.keys()
	heads.sort()
	var out: Array = []
	for h in heads:
		if not groups[h]["models"].is_empty():
			out.append(groups[h])
	return out


## On the table right now: alive, deployed (not in reserves / undeployed), not
## embarked, with at least one alive model that has a position.
static func is_on_battlefield(u: Dictionary) -> bool:
	var status := int(u.get("status", GameStateData.UnitStatus.DEPLOYED))
	if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
		return false
	var emb = u.get("embarked_in", null)
	if emb != null and str(emb) != "":
		return false
	for m in u.get("models", []):
		if typeof(m) == TYPE_DICTIONARY and m.get("alive", true) and model_position(m) != Vector2.INF:
			return true
	return false


## Longest numeric weapon range in inches; 0.0 for a unit with no ranged
## weapon ("Melee" ranges do not count).
static func longest_ranged_weapon_inches(unit: Dictionary) -> float:
	var weapons = unit.get("meta", {}).get("weapons", [])
	if typeof(weapons) != TYPE_ARRAY:
		return 0.0
	var best := 0.0
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var raw = w.get("range", 0)
		var rng := 0.0
		if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
			rng = float(raw)
		elif typeof(raw) == TYPE_STRING:
			var s := String(raw).replace("\"", "").strip_edges()
			if s.is_valid_float():
				rng = float(s)
		best = maxf(best, rng)
	return best


static func model_position(m: Dictionary) -> Vector2:
	var pos = m.get("position", null)
	if typeof(pos) == TYPE_VECTOR2:
		return pos
	if typeof(pos) == TYPE_DICTIONARY and pos.has("x") and pos.has("y"):
		return Vector2(float(pos.x), float(pos.y))
	return Vector2.INF


## The battlefield rectangle in board px, (0, 0) to (width, height).
func board_polygon(state: Dictionary) -> PackedVector2Array:
	var ppi := _px_per_inch()
	var w := 0.0
	var h := 0.0
	var size = state.get("board", {}).get("size", {})
	if typeof(size) == TYPE_DICTIONARY:
		w = float(size.get("width", 0.0)) * ppi
		h = float(size.get("height", 0.0)) * ppi
	if w <= 0.0 or h <= 0.0:
		var ss = get_node_or_null("/root/SettingsService")
		if ss != null and ss.has_method("get_board_width_px"):
			w = float(ss.get_board_width_px())
			h = float(ss.get_board_height_px())
	if w <= 0.0 or h <= 0.0:
		return PackedVector2Array()
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func _build() -> void:
	_clear_geometry()
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_redraw_layers()
		return
	viewer_player_id = viewer_player()
	var ppi := _px_per_inch()
	var board := board_polygon(gs.state)
	for entry in threat_units(gs.state, viewer_player_id):
		var shoot_circles: Array = []
		var charge_circles: Array = []
		var shoot_inches := 0.0
		for m in entry["models"]:
			var extent: float = m["extent"]
			charge_circles.append({"c": m["pos"], "r": CHARGE_RANGE_INCHES * ppi + extent})
			if m["shoot_inches"] > 0.0:
				shoot_circles.append({"c": m["pos"], "r": m["shoot_inches"] * ppi + extent})
				shoot_inches = maxf(shoot_inches, m["shoot_inches"])
		rendered_rings.append(_ring_entry(entry["unit_id"], "shoot", shoot_circles, shoot_inches))
		rendered_rings.append(_ring_entry(entry["unit_id"], "charge", charge_circles, CHARGE_RANGE_INCHES))
		_add_geometry("shoot", shoot_circles, board)
		_add_geometry("charge", charge_circles, board)
	_redraw_layers()


func _ring_entry(unit_id: String, kind: String, circles: Array, range_inches: float) -> Dictionary:
	var radius := 0.0
	for c in circles:
		radius = maxf(radius, float(c["r"]))
	return {
		"unit_id": unit_id,
		"kind": kind,
		"color_slot": SLOT_FOR_KIND[kind],
		"radius_px": radius,
		"range_inches": range_inches if not circles.is_empty() else 0.0,
	}


func _add_geometry(kind: String, circles: Array, board: PackedVector2Array) -> void:
	var clip := board.size() >= 3
	for c in circles:
		var poly := circle_polygon(c["c"], float(c["r"]))
		if not clip:
			_fill_polys[kind].append(poly)
			continue
		for piece in Geometry2D.intersect_polygons(poly, board):
			if piece.size() >= 3:
				_fill_polys[kind].append(piece)
	for line in union_outline(circles):
		if not clip:
			_outlines[kind].append(line)
			continue
		for piece in Geometry2D.intersect_polyline_with_polygon(line, board):
			if piece.size() >= 2:
				_outlines[kind].append(piece)


func _clear() -> void:
	rendered_rings.clear()
	_clear_geometry()
	_redraw_layers()


func _clear_geometry() -> void:
	rendered_rings.clear()
	_fill_polys = {"shoot": [], "charge": []}
	_outlines = {"shoot": [], "charge": []}


## Outline of the union of `circles` ([{c: Vector2, r: float}], board px) as
## open polylines: each circle contributes the arcs no other circle covers.
## Exact — the arcs come from the circle-circle intersection angles — so a
## twenty-model mob gets one smooth outline, not twenty rings (doc §5).
static func union_outline(circles: Array) -> Array:
	var out: Array = []
	var n := circles.size()
	for i in range(n):
		var ci: Vector2 = circles[i]["c"]
		var ri := float(circles[i]["r"])
		if ri <= 0.0:
			continue
		var covered: Array = []
		var swallowed := false
		for j in range(n):
			if j == i:
				continue
			var cj: Vector2 = circles[j]["c"]
			var rj := float(circles[j]["r"])
			if rj <= 0.0:
				continue
			var d := ci.distance_to(cj)
			if d + ri <= rj + _EPS:
				# Wholly inside circle j. Two identical circles would hide each
				# other: the lower index keeps its outline.
				if d <= _EPS and absf(ri - rj) <= _EPS and i < j:
					continue
				swallowed = true
				break
			if d >= ri + rj or d <= _EPS:
				continue  # Disjoint, or j sits concentric inside i.
			var cos_half := (ri * ri + d * d - rj * rj) / (2.0 * ri * d)
			if cos_half >= 1.0:
				continue  # j inside i: covers none of i's edge.
			var half := acos(clampf(cos_half, -1.0, 1.0))
			var mid := (cj - ci).angle()
			covered.append(Vector2(mid - half, mid + half))
		if swallowed:
			continue
		for arc in uncovered_arcs(covered):
			out.append(arc_points(ci, ri, arc.x, arc.y))
	return out


## Complement on [0, TAU) of the angle intervals `covered` (Vector2(start,
## end), any winding). Arcs come back as Vector2(start, end) with start < end;
## an arc across angle 0 is ONE arc whose end exceeds TAU, so its outline is a
## single unbroken polyline.
static func uncovered_arcs(covered: Array) -> Array:
	if covered.is_empty():
		return [Vector2(0.0, TAU)]
	var spans: Array = []
	for iv in covered:
		var length: float = iv.y - iv.x
		if length >= TAU - 1e-6:
			return []
		var s := fposmod(iv.x, TAU)
		var e := s + length
		if e > TAU:
			spans.append(Vector2(s, TAU))
			spans.append(Vector2(0.0, e - TAU))
		else:
			spans.append(Vector2(s, e))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var merged: Array = []
	for sp in spans:
		if not merged.is_empty() and sp.x <= merged[-1].y:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, sp.y))
		else:
			merged.append(sp)
	var gaps: Array = []
	var cursor := 0.0
	for sp in merged:
		if sp.x > cursor + 1e-9:
			gaps.append(Vector2(cursor, sp.x))
		cursor = maxf(cursor, sp.y)
	if cursor < TAU - 1e-9:
		gaps.append(Vector2(cursor, TAU))
	# The gap that ends at TAU and the one that starts at 0 are the same arc.
	if gaps.size() >= 2 and gaps[0].x <= 1e-9 and gaps[-1].y >= TAU - 1e-9:
		var first: Vector2 = gaps.pop_front()
		gaps[-1] = Vector2(gaps[-1].x, TAU + first.y)
	return gaps


static func arc_points(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var steps := clampi(int(ceil((a1 - a0) * r / ARC_STEP_PX)), 2, MAX_CIRCLE_STEPS)
	var pts := PackedVector2Array()
	for k in range(steps + 1):
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func circle_polygon(c: Vector2, r: float) -> PackedVector2Array:
	var steps := clampi(int(ceil(TAU * r / ARC_STEP_PX)), MIN_CIRCLE_STEPS, MAX_CIRCLE_STEPS)
	var pts := PackedVector2Array()
	for k in range(steps):
		var a := TAU * float(k) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _make_fill_layer(node_name: String, kind: String, alpha: float) -> CanvasGroup:
	var group := CanvasGroup.new()
	group.name = node_name
	# The alpha applies to the MERGED children: overlapping circles composite
	# once at `alpha` instead of stacking towards opaque.
	group.self_modulate = Color(1, 1, 1, alpha)
	var shapes := Node2D.new()
	shapes.name = "Shapes"
	shapes.draw.connect(_draw_fill.bind(shapes, kind))
	group.add_child(shapes)
	add_child(group)
	return group


func _draw_fill(shapes: Node2D, kind: String) -> void:
	var col := _slot_color(kind)
	col.a = 1.0
	var item := shapes.get_canvas_item()
	# Every fill polygon is convex (a circle, or a circle cut by the board
	# rectangle), so it is drawn as a triangle fan. draw_colored_polygon()
	# would re-triangulate each one and log an ERROR on a sliver it cannot
	# triangulate where a circle just clips the board edge.
	for poly in _fill_polys[kind]:
		var n: int = poly.size()
		if n < 3:
			continue
		var indices := PackedInt32Array()
		for k in range(1, n - 1):
			indices.append_array([0, k, k + 1])
		var colors := PackedColorArray()
		colors.resize(n)
		colors.fill(col)
		RenderingServer.canvas_item_add_triangle_array(item, indices, poly, colors)


func _draw_outlines() -> void:
	_outline_scale = _screen_scale()
	var px := 1.0 / maxf(_outline_scale, 0.0001)  # one screen px, in board px
	var width := OUTLINE_SCREEN_PX * px
	# Shooting rings solid, charge rings dashed and drawn last (the nearer
	# threat on top). The dashes keep both readable where they coincide — a
	# unit whose longest gun is 12" has its yellow ring exactly under its red
	# one — and match the dashed charge rings of the Charge phase (T30).
	var yellow := _slot_color("shoot")
	yellow.a = OUTLINE_ALPHA
	for line in _outlines["shoot"]:
		_outline_layer.draw_polyline(line, yellow, width, true)
	var red := _slot_color("charge")
	red.a = OUTLINE_ALPHA
	for line in _outlines["charge"]:
		var dashes := dash_polyline(line, CHARGE_DASH_SCREEN_PX * px, CHARGE_GAP_SCREEN_PX * px)
		if dashes.size() >= 2:
			_outline_layer.draw_multiline(dashes, red, width, true)


## Cut `line` into dashes `dash` long with `gap` between them (same units as
## the points), carrying the pattern across vertices so it stays even along a
## curve. Returns point pairs for draw_multiline().
static func dash_polyline(line: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line.size() < 2 or dash <= 0.0:
		return out
	var period := dash + maxf(gap, 0.0)
	var phase := 0.0  # Distance into the current dash + gap period.
	for i in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step: float
			if phase < dash:
				step = minf(dash - phase, seg - t)
				out.append(a.lerp(b, t / seg))
				out.append(a.lerp(b, (t + step) / seg))
			else:
				step = minf(period - phase, seg - t)
			if step <= 0.0:
				break
			t += step
			phase += step
			if phase >= period - 1e-6:
				phase = 0.0
	return out


func _redraw_layers() -> void:
	_shoot_fill.get_node("Shapes").queue_redraw()
	_charge_fill.get_node("Shapes").queue_redraw()
	_outline_layer.queue_redraw()


func _queue_refresh(_payload = null) -> void:
	if not _active or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_run_queued_refresh")


func _run_queued_refresh() -> void:
	_refresh_queued = false
	if _active:
		_build()


# ---------------------------------------------------------------------------
# Helpers (autoloads looked up at runtime, so `godot -s` tests can load this)
# ---------------------------------------------------------------------------

func _slot_color(kind: String) -> Color:
	var uic = get_node_or_null("/root/UIConstants")
	if kind == "charge":
		return uic.INVALID_RED if uic != null else Color(0.90, 0.20, 0.20, 1.0)
	return uic.MARGINAL_YELLOW if uic != null else Color(0.95, 0.85, 0.15, 1.0)


func _px_per_inch() -> float:
	var meas = get_node_or_null("/root/Measurement")
	return float(meas.PX_PER_INCH) if meas != null else 40.0


func _base_extent_px(m: Dictionary) -> float:
	var meas = get_node_or_null("/root/Measurement")
	if meas != null and meas.has_method("base_extent_px"):
		return float(meas.base_extent_px(m))
	return float(m.get("base_mm", 32)) / 25.4 * _px_per_inch() * 0.5


func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return absf(get_global_transform_with_canvas().get_scale().x)


func _log(msg: String) -> void:
	var dl = get_node_or_null("/root/DebugLogger")
	if dl != null:
		dl.info("[ThreatOverlay] T10 " + msg)
	else:
		print("[ThreatOverlay] T10 " + msg)
