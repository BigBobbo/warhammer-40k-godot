extends SceneTree

# VISION-MAP-AGREEMENT — headless half of the Vision Map feature (the
# whole-board "what can this unit see" shading used for deployment planning).
#
# The L-overlay bug taught us that a debug view carrying its own private LoS
# logic eventually contradicts the rules engine (2026-08 report). The vision
# map therefore mirrors EnhancedLineOfSight._check_single_line_of_sight_11e
# per line, with precomputed piece data for speed — and this test holds the
# mirror to the canon:
#
#   1. run_self_check(): on the real default terrain layout, sampled cells
#      re-judged straight through the canonical per-line function must agree
#      with the stored grid — zero mismatches.
#   2. Directed probes on the default layout (behind the centre ruins, open
#      ground) must agree with a canonical re-judgement of the same cell.
#   3. Synthetic-terrain semantic pins that isolate each 11e branch: obscuring
#      areas + the "within" exclusion (13.10), Solid dense features + the
#      occupies exception (13.11), light features not blocking, elevated
#      observers ignoring Solid but not Obscuring, wall segments.
#   4. Lifecycle: a unit with no models on the board reports a status reason
#      instead of shading garbage; clear_map() empties everything.
#
# The windowed half lives in tests/scenarios/sp/los_vision_map_deployment.json.
#
# NOTE: `-s` main-loop scripts compile before autoloads register, so autoloads
# are fetched via root.get_node_or_null (same pattern as
# test_los_overlay_targeting_agreement.gd). class_name globals resolve fine.
#
# Usage: godot --headless --path . -s tests/test_vision_map_agreement.gd

var passed := 0
var failed := 0

# Autoload handles (resolved at run time)
var gs = null      # GameState
var tm = null      # TerrainManager
var elos = null    # EnhancedLineOfSight

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	create_timer(0.25).timeout.connect(_run_tests)

func _model(id: String, x: float, y: float, base_mm: int = 32, elevation: float = 0.0) -> Dictionary:
	var m := {"id": id, "alive": true, "base_mm": base_mm, "base_type": "circular",
		"position": {"x": x, "y": y}}
	if elevation > 0.0:
		m["elevation_inches"] = elevation
	return m

func _inject_unit(uid: String, models: Array) -> void:
	gs.state["units"][uid] = {
		"owner": 1,
		"status": 2,  # UnitStatus.DEPLOYED (enum ref avoided: -s scripts compile before autoloads)
		"flags": {},
		"models": models,
		"meta": {"name": uid, "keywords": ["INFANTRY"]},
	}

func _compute_all(overlay) -> void:
	# Deterministic: pump the chunked compute directly instead of racing frames.
	var guard := 0
	while not overlay.is_compute_done() and guard < 10000:
		overlay._compute_chunk()
		guard += 1

# Canonical unit-level verdict for one probed point: same observer ray set the
# overlay uses, every line judged by the CANONICAL 11e function.
func _canonical_visible(overlay, target: Vector2) -> bool:
	var cell_groups := {}
	var cell_feats := {}
	for piece in overlay._pieces:
		if Geometry2D.is_point_in_polygon(target, piece.polygon):
			cell_groups[piece.group_key] = true
			cell_feats[piece.id] = true
	for op in overlay._obs_points:
		var obs: Dictionary = overlay._observers[op[1]]
		var e11 := {
			"group_map": overlay._group_map,
			"exclude_groups": overlay._merged(obs.groups, cell_groups),
			"exclude_feature_ids": overlay._merged(obs.feats, cell_feats),
			"ground_level": obs.ground,
		}
		var res: Dictionary = elos._check_single_line_of_sight_11e(op[0], target, overlay._raw_features, e11)
		if res.has_los:
			return true
	return false

# Snap a board pos to its cell centre so directed probes judge the exact point
# the grid judged.
func _cell_centre(overlay, pos: Vector2) -> Vector2:
	var cx := int(pos.x / overlay._cell_px)
	var cy := int(pos.y / overlay._cell_px)
	return Vector2((float(cx) + 0.5) * overlay._cell_px, (float(cy) + 0.5) * overlay._cell_px)

func _probe_agrees(overlay, label: String, pos: Vector2) -> void:
	var centre := _cell_centre(overlay, pos)
	var stored: int = overlay.cell_state_at(pos)
	var canon := _canonical_visible(overlay, centre)
	_check(label + " agrees with canonical", (stored == overlay.CELL_VISIBLE) == canon,
		"stored=%d canonical_visible=%s at %s" % [stored, canon, str(centre)])

func _rect_piece(id: String, cx: float, cy: float, w: float, h: float, cat: String, pclass: String, height: float = 6.0) -> Dictionary:
	return {
		"id": id,
		"type": "ruins",
		"polygon": PackedVector2Array([
			Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
			Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)]),
		"category": cat,
		"piece_class": pclass,
		"height_inches": height,
		"height_category": "tall",
	}

func _run_tests() -> void:
	print("\n===== VISION MAP ↔ RULES-ENGINE AGREEMENT =====\n")
	gs = root.get_node_or_null("GameState")
	tm = root.get_node_or_null("TerrainManager")
	elos = root.get_node_or_null("EnhancedLineOfSight")
	if gs == null or tm == null or elos == null:
		print("FAIL: autoloads missing (GameState=%s TerrainManager=%s EnhancedLineOfSight=%s)" % [gs, tm, elos])
		quit(1)
		return
	# The automated harness pins GameConstants.edition to the legacy 10e
	# baseline (SettingsService._is_automated_harness); this feature ships on
	# 11e rules, so opt in explicitly like the other *_11e tests do.
	GameConstants.edition = 11

	print("-- Part 1: real default layout (%s, %d pieces) --" % [
		tm.current_layout, tm.terrain_features.size()])
	_check("default terrain layout loaded", tm.terrain_features.size() > 0)

	# Two-model unit near the south edge (a P2-ish deployment spot, mid-board x)
	_inject_unit("U_VISION_TEST", [
		_model("m1", 880.0, 2160.0),          # 22", 54"
		_model("m2", 960.0, 2200.0, 40),      # 24", 55"
	])
	var overlay = load("res://scripts/VisionMapOverlay.gd").new()
	root.add_child(overlay)
	overlay.show_for_unit("U_VISION_TEST")
	_compute_all(overlay)

	_check("compute completes", overlay.is_compute_done())
	_check("grid fully classified", overlay.visible_cell_count() + overlay.hidden_cell_count() == overlay._cells.size(),
		"visible=%d hidden=%d cells=%d" % [overlay.visible_cell_count(), overlay.hidden_cell_count(), overlay._cells.size()])
	_check("some cells visible", overlay.visible_cell_count() > 0)
	_check("some cells hidden (44-piece layout must cast shadows)", overlay.hidden_cell_count() > 0)

	var self_check: Dictionary = overlay.run_self_check(400)
	_check("self-check ran on real cells", int(self_check.checked) > 300, "checked=%d" % int(self_check.checked))
	_check("zero mismatches vs canonical per-line judge", int(self_check.mismatches) == 0,
		"mismatches=%d examples=%s" % [int(self_check.mismatches), str(self_check.examples)])

	# Directed probes: dead behind the centre trapezoid ruins / open own corner.
	_probe_agrees(overlay, "probe behind centre ruins (22\",20\")", Vector2(880, 800))
	_probe_agrees(overlay, "probe open ground (40\",55\")", Vector2(1600, 2200))
	_probe_agrees(overlay, "probe far corner (2\",2\")", Vector2(80, 80))
	_probe_agrees(overlay, "probe inside a dense area (37\",42\")", Vector2(1480, 1680))

	# Own cells: a unit always sees where it stands.
	_check("observer's own cell visible", overlay.cell_state_at(Vector2(880, 2160)) == overlay.CELL_VISIBLE)

	print("\n-- Part 2: synthetic terrain semantic pins --")
	var saved_features = tm.terrain_features
	var saved_layout: String = tm.current_layout

	# One legacy dense piece (no piece_class → both its own area AND solid)
	# spanning x 18..26", y 28..32", observer at (22", 44").
	tm.terrain_features = [_rect_piece("blk", 880.0, 1200.0, 320.0, 160.0, "dense", "")]
	_inject_unit("U_VISION_ONE", [_model("m1", 880.0, 1760.0)])  # 22", 44"
	overlay.show_for_unit("U_VISION_ONE")
	_compute_all(overlay)
	_check("legacy dense blocks the far side", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_HIDDEN)
	_check("near side stays visible", overlay.cell_state_at(Vector2(880, 1600)) == overlay.CELL_VISIBLE)
	_check("point INSIDE the dense piece is visible (within-exclusion, 13.10/13.11)",
		overlay.cell_state_at(Vector2(880, 1200)) == overlay.CELL_VISIBLE)
	_probe_agrees(overlay, "synthetic blocked probe", Vector2(880, 400))
	_probe_agrees(overlay, "synthetic inside probe", Vector2(880, 1200))

	# Observer INSIDE the dense piece sees out (its own area/piece excluded).
	_inject_unit("U_VISION_INSIDE", [_model("m1", 880.0, 1200.0)])
	overlay.show_for_unit("U_VISION_INSIDE")
	_compute_all(overlay)
	_check("observer inside dense piece sees out", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_VISIBLE)

	# Light FEATURE (barricade): features never obscure, light never Solid → no block.
	tm.terrain_features = [_rect_piece("bar", 880.0, 1200.0, 320.0, 160.0, "light", "feature", 2.0)]
	overlay.show_for_unit("U_VISION_ONE")
	_compute_all(overlay)
	_check("light feature (barricade) does not block", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_VISIBLE)

	# Light AREA: obscures (13.10) → blocked; unless the probed point is within it.
	tm.terrain_features = [_rect_piece("larea", 880.0, 1200.0, 320.0, 160.0, "light", "area", 2.0)]
	overlay.show_for_unit("U_VISION_ONE")
	_compute_all(overlay)
	_check("light AREA obscures the far side", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_HIDDEN)
	_check("point within the light area is visible", overlay.cell_state_at(Vector2(880, 1200)) == overlay.CELL_VISIBLE)

	# Solid vs elevation: dense FEATURE blocks ground observers, not elevated ones
	# (13.11 is ground-level only); a dense AREA would still obscure regardless.
	tm.terrain_features = [_rect_piece("wall", 880.0, 1200.0, 320.0, 160.0, "dense", "feature")]
	overlay.show_for_unit("U_VISION_ONE")
	_compute_all(overlay)
	_check("dense feature blocks ground observer", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_HIDDEN)
	_inject_unit("U_VISION_UP", [_model("m1", 880.0, 1760.0, 32, 4.0)])  # 4" up a ruin
	overlay.show_for_unit("U_VISION_UP")
	_compute_all(overlay)
	_check("elevated observer sees over the dense feature", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_VISIBLE)
	_probe_agrees(overlay, "elevated probe", Vector2(880, 400))

	# Explicit wall segment (legacy walls[] array) blocks on its own.
	tm.terrain_features = [{
		"id": "wallpiece", "type": "ruins", "polygon": PackedVector2Array(),
		"category": "exposed", "walls": [{"start": Vector2(720, 1200), "end": Vector2(1040, 1200), "blocks_los": true}],
	}]
	overlay.show_for_unit("U_VISION_ONE")
	_compute_all(overlay)
	_check("explicit wall segment blocks", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_HIDDEN)
	_check("off the wall's line stays visible", overlay.cell_state_at(Vector2(200, 400)) == overlay.CELL_VISIBLE)

	print("\n-- Part 3: lifecycle --")
	tm.terrain_features = saved_features
	tm.current_layout = saved_layout
	_inject_unit("U_VISION_EMPTY", [])
	overlay.show_for_unit("U_VISION_EMPTY")
	_check("unit with no models reports a reason", overlay.status_reason() != "")
	_check("no-model map counts nothing", overlay.visible_cell_count() == 0 and overlay.hidden_cell_count() == 0)
	overlay.show_for_unit("U_MISSING_UNIT")
	_check("missing unit reports a reason", overlay.status_reason() != "")
	overlay.clear_map()
	_check("clear_map deactivates", not overlay.is_active())
	_check("clear_map resets cells", overlay.cell_state_at(Vector2(880, 400)) == overlay.CELL_UNKNOWN)

	# Cleanup injected units
	for uid in ["U_VISION_TEST", "U_VISION_ONE", "U_VISION_INSIDE", "U_VISION_UP", "U_VISION_EMPTY"]:
		gs.state["units"].erase(uid)

	print("\n===== RESULT: %d passed, %d failed =====" % [passed, failed])
	quit(1 if failed > 0 else 0)
