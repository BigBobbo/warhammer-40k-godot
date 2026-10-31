extends SceneTree

# T10 — held-key threat overlay (design doc §6).
#
# Covers the parts of ThreatOverlay that do not need a window:
#   - longest_ranged_weapon_inches(): melee-only units have NO shooting range
#     (the old code drew a made-up 24" circle round them).
#   - is_on_battlefield(): reserves, undeployed, embarked and wiped-out units
#     are not threats.
#   - union_outline() / uncovered_arcs(): one outline per unit — the boundary
#     of the union of its models' circles (holes included), never a ring per
#     model; identical circles keep exactly one outline.
#   - dash_polyline(): the charge ring's dash pattern runs evenly across
#     vertices.
#   - threat_units() + the built rings on a synthetic board: enemies of the
#     viewer only, an attached leader folded into its bodyguard's entry,
#     radius = range x 40 px + base extent (edge-to-edge, as the engine
#     measures), slots MARGINAL_YELLOW / INVALID_RED, CanvasGroup fills at
#     0.15 / 0.10, everything clipped to the board, persistent layer nodes,
#     the `active` property setter, the deferred refresh on board changes.
#   - handle_key_event(): press on, echo consumed without toggling, release
#     honoured with a modifier down, unrelated keys ignored, strict press.
#   - begin_tap_or_hold(): a tap runs the shared action on key-up and never
#     shows the view; a hold past HOLD_THRESHOLD_S shows it and never runs the
#     action.
#   - stuck-key safety: a key-up that never reaches Main (Input says the key
#     is up) and a focus loss both turn the view off.
#   - viewer_player(): the human's seat against the AI, the active player in
#     hot-seat.
#
# Usage: godot --headless --path . -s tests/test_threat_overlay.gd

var passed := 0
var failed := 0
var _ran := false
var _tap_calls := 0
# GameState's enums, read at runtime: naming GameStateData here would make this
# script depend on GameState.gd during the pre-autoload compile.
var _US: Dictionary = {}
var _PHASE: Dictionary = {}


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	create_timer(0.1).timeout.connect(_run_tests)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _count_tap() -> void:
	_tap_calls += 1


func _key(keycode: int, pressed: bool, echo: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.echo = echo
	ev.shift_pressed = shift
	return ev


## Push a key state into Input's "is this key down" cache, as the OS would.
func _input_key(keycode: int, pressed: bool) -> void:
	Input.parse_input_event(_key(keycode, pressed))
	Input.flush_buffered_events()


func _run_tests() -> void:
	if _ran:
		return
	_ran = true
	print("\n=== test_threat_overlay (T10) ===\n")
	var gs_node = root.get_node_or_null("GameState")
	if gs_node == null:
		_check("GameState autoload reachable", false)
		_finish()
		return
	_US = gs_node.UnitStatus
	_PHASE = gs_node.Phase
	# Loaded at runtime (not preloaded): the overlay looks its autoloads up by
	# path, and a compile before autoload registration would be noise.
	var Overlay = load("res://scripts/ThreatOverlay.gd")
	_check("ThreatOverlay script loads", Overlay != null)
	if Overlay == null:
		_finish()
		return
	var api := []
	for m in Overlay.get_script_method_list():
		api.append(str(m.get("name", "")))
	var missing := []
	for fn in ["set_active", "refresh", "handle_key_event", "begin_tap_or_hold", "is_tap_pending",
			"union_outline", "uncovered_arcs", "dash_polyline", "arc_points", "circle_polygon",
			"threat_units", "is_on_battlefield", "longest_ranged_weapon_inches", "model_position",
			"viewer_player", "board_polygon"]:
		if not api.has(fn):
			missing.append(fn)
	_check("public API present", missing.is_empty(), str(missing))
	if not missing.is_empty():
		_finish()
		return

	_test_weapon_ranges(Overlay)
	_test_on_battlefield(Overlay)
	_test_union_outline(Overlay)
	_test_arcs_and_dashes(Overlay)
	await _test_board_and_rings(Overlay)
	_finish()


# ---------------------------------------------------------------------------

func _test_weapon_ranges(Overlay) -> void:
	print("-- longest_ranged_weapon_inches --")
	var w := func(ranges: Array) -> Dictionary:
		var weapons := []
		for r in ranges:
			weapons.append({"name": "w", "range": r})
		return {"meta": {"weapons": weapons}}
	_check("melee-only unit: 0 (no shooting threat)", Overlay.longest_ranged_weapon_inches(w.call(["Melee", "Melee"])) == 0.0)
	_check("24\" gun + melee: 24", Overlay.longest_ranged_weapon_inches(w.call(["24", "Melee"])) == 24.0)
	_check("int and inch-marked strings: 48", Overlay.longest_ranged_weapon_inches(w.call([36, "48\""])) == 48.0)
	_check("non-numeric range ignored", Overlay.longest_ranged_weapon_inches(w.call(["N/A"])) == 0.0)
	_check("no weapons: 0", Overlay.longest_ranged_weapon_inches({"meta": {"weapons": []}}) == 0.0)
	_check("no meta: 0", Overlay.longest_ranged_weapon_inches({}) == 0.0)


func _test_on_battlefield(Overlay) -> void:
	print("\n-- is_on_battlefield --")
	var placed := {"alive": true, "position": Vector2(100, 100)}
	_check("deployed with a placed model", Overlay.is_on_battlefield({"status": _US.DEPLOYED, "models": [placed]}))
	_check("{x, y} snapshot position counts", Overlay.is_on_battlefield({"status": _US.MOVED, "models": [{"alive": true, "position": {"x": 5, "y": 6}}]}))
	_check("in reserves: not a threat", not Overlay.is_on_battlefield({"status": _US.IN_RESERVES, "models": [placed]}))
	_check("undeployed: not a threat", not Overlay.is_on_battlefield({"status": _US.UNDEPLOYED, "models": [placed]}))
	_check("embarked: not a threat", not Overlay.is_on_battlefield({"status": _US.DEPLOYED, "embarked_in": "U_TRUKK", "models": [placed]}))
	_check("every model dead: not a threat", not Overlay.is_on_battlefield({"status": _US.DEPLOYED, "models": [{"alive": false, "position": Vector2(1, 1)}]}))
	_check("alive but never placed: not a threat", not Overlay.is_on_battlefield({"status": _US.DEPLOYED, "models": [{"alive": true, "position": null}]}))


## True when every point of `lines` lies on one of `circles` and strictly
## inside none of them — i.e. on the boundary of their union.
func _on_union_boundary(lines: Array, circles: Array, tol: float = 0.05) -> String:
	for line in lines:
		for p in line:
			var on_some := false
			for c in circles:
				var d: float = p.distance_to(c.c)
				if d < float(c.r) - tol:
					return "point %s inside circle %s r=%.1f" % [p, c.c, c.r]
				if absf(d - float(c.r)) <= tol:
					on_some = true
			if not on_some:
				return "point %s on no circle" % [p]
	return ""


func _test_union_outline(Overlay) -> void:
	print("\n-- union_outline: one outline per unit --")
	var one := [{"c": Vector2(0, 0), "r": 100.0}]
	var o1: Array = Overlay.union_outline(one)
	_check("single circle: one closed outline", o1.size() == 1 and o1[0][0].distance_to(o1[0][o1[0].size() - 1]) < 0.01, str(o1.size()))
	_check("single circle: every point on it", _on_union_boundary(o1, one) == "")

	var two := [{"c": Vector2(0, 0), "r": 100.0}, {"c": Vector2(100, 0), "r": 100.0}]
	var o2: Array = Overlay.union_outline(two)
	_check("two overlapping circles: two arcs", o2.size() == 2, str(o2.size()))
	_check("two overlapping circles: on the union boundary", _on_union_boundary(o2, two) == "", _on_union_boundary(o2, two))
	var ends_ok := true
	for arc in o2:
		for p in [arc[0], arc[arc.size() - 1]]:
			if p.distance_to(Vector2(50, 86.6025)) > 0.05 and p.distance_to(Vector2(50, -86.6025)) > 0.05:
				ends_ok = false
	_check("two overlapping circles: arcs end at the intersection points", ends_ok)

	var nested := [{"c": Vector2(0, 0), "r": 200.0}, {"c": Vector2(30, 0), "r": 50.0}]
	var o3: Array = Overlay.union_outline(nested)
	_check("circle inside another: only the outer outline", o3.size() == 1 and _on_union_boundary(o3, nested) == "" and absf(o3[0][0].length() - 200.0) < 0.05)

	var dup := [{"c": Vector2(10, 10), "r": 80.0}, {"c": Vector2(10, 10), "r": 80.0}]
	_check("identical circles: exactly one outline (not none, not two)", Overlay.union_outline(dup).size() == 1)

	var apart := [{"c": Vector2(0, 0), "r": 100.0}, {"c": Vector2(500, 0), "r": 100.0}]
	_check("disjoint circles: two full outlines", Overlay.union_outline(apart).size() == 2)

	# A ring of six overlapping circles encloses an untouched hole: its edge is
	# part of the union boundary too.
	var hexa := []
	for k in range(6):
		hexa.append({"c": Vector2.from_angle(k * TAU / 6.0) * 200.0, "r": 110.0})
	var oh: Array = Overlay.union_outline(hexa)
	var inner := false
	var outer := false
	for line in oh:
		for p in line:
			if p.length() < 150.0:
				inner = true
			if p.length() > 250.0:
				outer = true
	_check("ring of circles: outer AND hole outlines", inner and outer and _on_union_boundary(oh, hexa) == "", _on_union_boundary(oh, hexa))

	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var mob := []
	for k in range(12):
		mob.append({"c": Vector2(rng.randf_range(0, 300), rng.randf_range(0, 300)), "r": rng.randf_range(60, 140)})
	var om: Array = Overlay.union_outline(mob)
	_check("random 12-model cluster: every outline point on the union boundary", not om.is_empty() and _on_union_boundary(om, mob) == "", _on_union_boundary(om, mob))


func _test_arcs_and_dashes(Overlay) -> void:
	print("\n-- uncovered_arcs / dash_polyline --")
	var full: Array = Overlay.uncovered_arcs([])
	_check("nothing covered: the whole circle", full.size() == 1 and full[0].is_equal_approx(Vector2(0, TAU)))
	var a: Array = Overlay.uncovered_arcs([Vector2(-0.5, 0.5)])
	_check("cover across angle 0: one arc", a.size() == 1 and a[0].is_equal_approx(Vector2(0.5, TAU - 0.5)), str(a))
	var b: Array = Overlay.uncovered_arcs([Vector2(1, 2)])
	_check("free arc across angle 0 comes back as ONE arc", b.size() == 1 and b[0].is_equal_approx(Vector2(2, TAU + 1)), str(b))
	var c: Array = Overlay.uncovered_arcs([Vector2(1, 2), Vector2(1.5, 3)])
	_check("overlapping covers merge", c.size() == 1 and c[0].is_equal_approx(Vector2(3, TAU + 1)), str(c))
	var d: Array = Overlay.uncovered_arcs([Vector2(1, 2), Vector2(4, 5)])
	_check("two covers: two free arcs", d.size() == 2 and d[0].is_equal_approx(Vector2(2, 4)) and d[1].is_equal_approx(Vector2(5, TAU + 1)), str(d))
	_check("covered all round: no arc", Overlay.uncovered_arcs([Vector2(0, TAU)]).is_empty())

	var straight := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var dashes: PackedVector2Array = Overlay.dash_polyline(straight, 10.0, 5.0)
	_check("100 px line, 10 on / 5 off: 7 dashes", dashes.size() == 14, str(dashes.size()))
	var fine := PackedVector2Array()
	for k in range(25):
		fine.append(Vector2(100.0 * k / 24.0, 0))
	var drawn := 0.0
	for k in range(0, Overlay.dash_polyline(fine, 10.0, 5.0).size(), 2):
		var pair: PackedVector2Array = Overlay.dash_polyline(fine, 10.0, 5.0)
		drawn += pair[k].distance_to(pair[k + 1])
	_check("pattern carries across vertices: 70 px drawn of 100", absf(drawn - 70.0) < 0.01, "%.3f" % drawn)
	_check("degenerate line: no dashes", Overlay.dash_polyline(PackedVector2Array([Vector2.ZERO]), 10.0, 5.0).is_empty())


# ---------------------------------------------------------------------------

func _unit(owner: int, models: Array, ranges: Array, extra: Dictionary = {}) -> Dictionary:
	var weapons := []
	for r in ranges:
		weapons.append({"name": "w", "range": r})
	var u := {"owner": owner, "status": _US.DEPLOYED, "models": models,
		"meta": {"name": "u", "weapons": weapons}, "flags": {}}
	u.merge(extra, true)
	return u


func _model(pos, base_mm: int = 32, alive: bool = true) -> Dictionary:
	return {"id": "m", "alive": alive, "position": pos, "base_mm": base_mm, "wounds": 1, "current_wounds": 1}


func _test_board_and_rings(Overlay) -> void:
	print("\n-- rings on a synthetic board (viewer P2) --")
	var gs = root.get_node_or_null("GameState")
	var km = root.get_node_or_null("KeybindingManager")
	var meas = root.get_node_or_null("Measurement")
	if gs == null or km == null or meas == null:
		_check("GameState / KeybindingManager / Measurement reachable", false)
		return
	var saved_state: Dictionary = gs.state.duplicate(true)
	var saved_binding: Dictionary = km.bindings["threat_overlay"].duplicate(true)
	km.bindings["threat_overlay"]["key"] = KEY_TAB
	km.bindings["threat_overlay"]["alt_key"] = 0
	for mod in ["shift", "ctrl", "alt", "meta"]:
		km.bindings["threat_overlay"][mod] = false

	gs.state = {
		"meta": {"active_player": 2, "phase": _PHASE.MOVEMENT, "turn_number": 1, "battle_round": 1},
		"board": {"size": {"width": 44.0, "height": 60.0}},
		"units": {
			"U_GUN": _unit(1, [_model(Vector2(400, 400))], ["24", "Melee"]),
			"U_MOB": _unit(1, [_model(Vector2(800, 800)), _model(Vector2(840, 800)), _model(Vector2(880, 800))], ["18", "Melee"],
				{"attachment_data": {"attached_characters": ["U_LEADER"]}}),
			"U_LEADER": _unit(1, [_model(Vector2(860, 840), 40)], ["36"], {"attached_to": "U_MOB"}),
			"U_MELEE": _unit(1, [_model(Vector2(1200, 400), 40)], ["Melee"]),
			"U_RESERVE": _unit(1, [_model(null)], ["24"], {"status": _US.IN_RESERVES}),
			"U_EMBARKED": _unit(1, [_model(Vector2(400, 400))], ["24"], {"embarked_in": "U_GUN"}),
			"U_DEAD": _unit(1, [_model(Vector2(100, 100), 32, false)], ["24"]),
			"U_MINE": _unit(2, [_model(Vector2(500, 2000))], ["24"]),
		},
	}

	var board := Node2D.new()
	board.name = "T10Board"
	root.add_child(board)
	var ov = Overlay.new()
	board.add_child(ov)
	await process_frame

	_check("named ThreatOverlay, off by default", ov.name == "ThreatOverlay" and not ov.active and not ov.visible and ov.rendered_rings.is_empty())
	_check("draws below the tokens (TokenVisual z 10)", ov.z_index < 10, str(ov.z_index))
	var names := []
	for ch in ov.get_children():
		names.append(str(ch.name))
	_check("three persistent layers", names == ["ShootFill", "ChargeFill", "Outlines"], str(names))
	_check("fill layers are CanvasGroups at 0.15 / 0.10 alpha (overlaps never stack)",
		ov.get_node("ShootFill") is CanvasGroup and ov.get_node("ChargeFill") is CanvasGroup
		and is_equal_approx(ov.get_node("ShootFill").self_modulate.a, 0.15)
		and is_equal_approx(ov.get_node("ChargeFill").self_modulate.a, 0.10))
	_check("board rectangle from state.board.size (44x60\")",
		ov.board_polygon(gs.state) == PackedVector2Array([Vector2(0, 0), Vector2(1760, 0), Vector2(1760, 2400), Vector2(0, 2400)]))
	_check("hot-seat viewer = active player (2)", ov.viewer_player() == 2)

	var tu: Array = ov.threat_units(gs.state, 2)
	var ids := []
	for e in tu:
		ids.append(e.unit_id)
	_check("enemy units on the table only, leader folded into its bodyguard", ids == ["U_GUN", "U_MELEE", "U_MOB"], str(ids))
	var mob_models := 0
	for e in tu:
		if e.unit_id == "U_MOB":
			mob_models = e.models.size()
	_check("the Attached unit has the bodyguard's 3 models + the leader", mob_models == 4, str(mob_models))

	ov.set_active(true)
	_check("set_active(true): on, shown, counted", ov.active and ov.visible and ov.activation_count == 1 and ov.last_change_reason == "scripted")
	_check("one shoot + one charge entry per enemy unit (3 units -> 6)", ov.rendered_rings.size() == 6, str(ov.rendered_rings.size()))
	var ring := {}
	var slots_ok := true
	for r in ov.rendered_rings:
		ring[r.unit_id + "/" + r.kind] = r
		if (r.kind == "shoot" and r.color_slot != "MARGINAL_YELLOW") or (r.kind == "charge" and r.color_slot != "INVALID_RED"):
			slots_ok = false
	_check("slots: shoot MARGINAL_YELLOW, charge INVALID_RED", slots_ok)
	var ext32: float = meas.base_extent_px({"base_mm": 32})
	var ext40: float = meas.base_extent_px({"base_mm": 40})
	_check("24\" gun: radius = 24 x 40 + base extent (edge to edge)", is_equal_approx(ring["U_GUN/shoot"].radius_px, 960.0 + ext32), str(ring["U_GUN/shoot"]))
	_check("charge: radius = 12 x 40 + base extent", is_equal_approx(ring["U_GUN/charge"].radius_px, 480.0 + ext32) and ring["U_GUN/charge"].range_inches == 12.0)
	_check("melee-only unit: shoot entry with radius 0, nothing to draw",
		ring["U_MELEE/shoot"].radius_px == 0.0 and ring["U_MELEE/shoot"].range_inches == 0.0, str(ring["U_MELEE/shoot"]))
	_check("Attached unit: the leader's 36\" gun from the leader's 40 mm base",
		is_equal_approx(ring["U_MOB/shoot"].radius_px, 1440.0 + ext40) and ring["U_MOB/shoot"].range_inches == 36.0, str(ring["U_MOB/shoot"]))
	_check("Attached unit: charge ring from its biggest base", is_equal_approx(ring["U_MOB/charge"].radius_px, 480.0 + ext40))
	var inside := true
	var n_pts := 0
	for kind in ["shoot", "charge"]:
		for poly in ov._fill_polys[kind]:
			for p in poly:
				n_pts += 1
				if p.x < -0.5 or p.y < -0.5 or p.x > 1760.5 or p.y > 2400.5:
					inside = false
		for line in ov._outlines[kind]:
			for p in line:
				if p.x < -0.5 or p.y < -0.5 or p.x > 1760.5 or p.y > 2400.5:
					inside = false
	_check("fills and outlines clipped to the battlefield", inside and n_pts > 0)
	_check("melee-only unit: no yellow drawn for it (2 shooting units -> fills only from them)",
		ov._fill_polys["shoot"].size() == 1 + 4 and ov._fill_polys["charge"].size() == 1 + 4 + 1,
		"%d shoot / %d charge fill polygons" % [ov._fill_polys["shoot"].size(), ov._fill_polys["charge"].size()])

	ov.set_active(false)
	names = []
	for ch in ov.get_children():
		names.append(str(ch.name))
	_check("set_active(false): off, hidden, empty, same layer nodes",
		not ov.active and not ov.visible and ov.rendered_rings.is_empty() and names == ["ShootFill", "ChargeFill", "Outlines"])
	ov.active = true
	_check("assigning .active = true builds the rings", ov.rendered_rings.size() == 6 and ov.activation_count == 2)

	print("\n-- refresh while shown --")
	var pm = root.get_node_or_null("PhaseManager")
	_check("wired to PhaseManager.phase_action_taken / phase_changed",
		pm != null and pm.phase_action_taken.is_connected(ov._queue_refresh) and pm.phase_changed.is_connected(ov._queue_refresh))
	gs.state.units["U_MELEE"].models[0].alive = false
	ov._queue_refresh({})
	ov._queue_refresh({})
	await process_frame
	_check("a board change rebuilds the rings (the destroyed unit drops out)", ov.rendered_rings.size() == 4, str(ov.rendered_rings.size()))
	gs.state.units["U_MELEE"].models[0].alive = true
	ov.active = false
	_check("assigning .active = false clears them", ov.rendered_rings.is_empty() and not ov.visible)

	print("\n-- handle_key_event --")
	var count0: int = ov.activation_count
	_check("Tab press: consumed", ov.handle_key_event(_key(KEY_TAB, true)))
	_check("Tab press: on immediately (outside the Shooting phase)", ov.active and ov.last_change_reason == "key held" and ov.activation_count == count0 + 1)
	_check("Tab key repeat: consumed", ov.handle_key_event(_key(KEY_TAB, true, true)))
	_check("Tab key repeat: no toggle", ov.active and ov.activation_count == count0 + 1)
	await process_frame
	await process_frame
	_check("a press that bypassed Input is not auto-released by the stuck-key check", ov.active)
	_check("release with Shift down: consumed", ov.handle_key_event(_key(KEY_TAB, false, false, true)))
	_check("release with Shift down: off", not ov.active and ov.last_change_reason == "key released")
	_check("stray Tab release while off: not consumed", not ov.handle_key_event(_key(KEY_TAB, false)))
	_check("other key press: not consumed", not ov.handle_key_event(_key(KEY_A, true)) and not ov.active)
	_check("other key release: not consumed", not ov.handle_key_event(_key(KEY_A, false)))
	_check("Shift+Tab press does not match the bare-Tab binding", not ov.handle_key_event(_key(KEY_TAB, true, false, true)) and not ov.active)

	print("\n-- begin_tap_or_hold (Shooting phase hand-off) --")
	_tap_calls = 0
	count0 = ov.activation_count
	ov.begin_tap_or_hold(Callable(self, "_count_tap"))
	_check("tap pending after the hand-off", ov.is_tap_pending() and not ov.active)
	_check("quick key-up: consumed", ov.handle_key_event(_key(KEY_TAB, false)))
	_check("tap: the shared action ran once, the view never showed",
		_tap_calls == 1 and not ov.active and ov.activation_count == count0 and not ov.is_tap_pending())

	_tap_calls = 0
	_input_key(KEY_TAB, true)
	_check("Input sees Tab down", Input.is_key_pressed(KEY_TAB))
	ov.begin_tap_or_hold(Callable(self, "_count_tap"))
	await create_timer(ov.HOLD_THRESHOLD_S + 0.15).timeout
	_check("hold past %.1fs: the view shows" % ov.HOLD_THRESHOLD_S,
		ov.active and not ov.is_tap_pending() and ov.last_change_reason.begins_with("shared key held"), ov.last_change_reason)
	_check("hold: the shared action did not run", _tap_calls == 0)
	_check("hold then key-up: consumed", ov.handle_key_event(_key(KEY_TAB, false)))
	_check("hold then key-up: off, action still not run", not ov.active and _tap_calls == 0)
	_input_key(KEY_TAB, false)

	print("\n-- stuck-key safety --")
	_input_key(KEY_TAB, true)
	ov.handle_key_event(_key(KEY_TAB, true))
	# Two frames: an awaited process_frame resumes BEFORE that frame's _process,
	# so this guarantees one _process has seen the key down.
	await process_frame
	await process_frame
	_input_key(KEY_TAB, false)  # The key-up goes to Input only, never to handle_key_event.
	await process_frame
	await process_frame
	_check("key-up lost to a dialog: off once Input says the key is up",
		not ov.active and ov.last_change_reason == "key no longer down", ov.last_change_reason)
	ov.handle_key_event(_key(KEY_TAB, true))
	ov.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("focus lost while held: off", not ov.active and ov.last_change_reason == "window lost focus", ov.last_change_reason)
	_check("no processing left running while off", not ov.is_processing())

	print("\n-- viewer_player against the AI --")
	var ai = root.get_node_or_null("AIPlayer")
	if ai != null:
		# Synchronous set / read / restore: no frame passes with the AI enabled.
		var saved_enabled: bool = ai.enabled
		var saved_ai: Dictionary = ai.ai_players.duplicate()
		ai.enabled = true
		ai.ai_players = {1: true, 2: false}
		gs.state.meta.active_player = 1
		var v_ai_p1: int = ov.viewer_player()
		ai.ai_players = {1: false, 2: true}
		gs.state.meta.active_player = 2
		var v_ai_p2: int = ov.viewer_player()
		ai.ai_players = saved_ai
		ai.enabled = saved_enabled
		_check("AI is P1: the human P2 is the viewer even on the AI's turn", v_ai_p1 == 2, str(v_ai_p1))
		_check("AI is P2: the human P1 is the viewer even on the AI's turn", v_ai_p2 == 1, str(v_ai_p2))
	else:
		_check("AIPlayer reachable", false)

	board.queue_free()
	km.bindings["threat_overlay"] = saved_binding
	gs.state = saved_state
	await process_frame
