extends SceneTree

# LOS-TERRAIN (11e): terrain-AREA grouping + "within" semantics for the
# visibility rules — regression net for the Custodian-vs-Gretchin report
# ("unit on a terrain strip claimed to be out of line of sight").
#
# Rules covered (docs/rules/40k_11th_edition_core_rules.pdf):
#   01.04 — "within" measures from the closest part of the base (any part).
#   13.01 — an authored boundary + its features form ONE terrain area; the
#            converted GW layouts encode this via link_group (paired boundary
#            halves, e.g. the slanted centre strips) and parent_area_id.
#   13.09 — HIDDEN: INFANTRY within a dense-containing area, no recent
#            shooting → visible only within detection range.
#   13.10 — OBSCURING: light/dense terrain areas block sight lines, EXCLUDING
#            areas that one or both models are within.
#   13.11 — SOLID: dense features block ground-level sight lines regardless
#            of area exclusions (walls stay opaque inside your own area).
#
# Usage: godot --headless --path . -s tests/test_terrain_area_visibility_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _rect(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - w / 2, cy - h / 2), Vector2(cx + w / 2, cy - h / 2),
		Vector2(cx + w / 2, cy + h / 2), Vector2(cx - w / 2, cy + h / 2)])

func _model(id: String, x: float, y: float, base_mm: int = 32) -> Dictionary:
	return {"id": id, "alive": true, "base_mm": base_mm, "base_type": "circular",
		"position": {"x": x, "y": y}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_terrain_area_visibility_11e ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var enh = root.get_node_or_null("EnhancedLineOfSight")
	var rules = root.get_node_or_null("RulesEngine")
	var prev = tm.terrain_features.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	# ── The user-report geometry: a slanted strip authored as TWO trapezoid
	# "area" halves sharing link_group, exactly like the converted GW layouts
	# (take_and_hold_mirror_1's area-trapezoid-43/44). Rectangle split along
	# the diagonal (650,1080)→(1110,1320).
	var trap_a = {"id": "trap_a", "type": "ruins", "piece_class": "area",
		"category": "dense", "link_group": "Center",
		"polygon": PackedVector2Array([Vector2(650, 1400), Vector2(650, 1080), Vector2(1110, 1320), Vector2(1110, 1400)])}
	var trap_b = {"id": "trap_b", "type": "ruins", "piece_class": "area",
		"category": "dense", "link_group": "Center",
		"polygon": PackedVector2Array([Vector2(1110, 1000), Vector2(1110, 1320), Vector2(650, 1080), Vector2(650, 1000)])}
	# A light corner feature parented into the strip (like corner-tiny-47).
	var light_corner = {"id": "light_corner", "type": "ruins", "piece_class": "feature",
		"category": "light", "parent_area_id": "trap_a",
		"polygon": _rect(700, 1050, 80, 40)}
	# A dense wall feature parented into the strip.
	var wall_feat = {"id": "wall_feat", "type": "ruins", "piece_class": "feature",
		"category": "dense", "parent_area_id": "trap_a",
		"polygon": _rect(880, 1360, 160, 20)}
	tm.terrain_features = [trap_a, trap_b, light_corner, wall_feat]

	var obs = _model("obs", 620, 900, 40)          # open ground NW, ~12" away
	var tgt_on = _model("tgt_on", 900, 1300, 25)   # standing ON trap_a
	var tgt_behind = _model("tgt_behind", 900, 1460, 25)  # fully behind the strip
	var unit_inf = {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}

	print("-- 13.10 exclusion spans the whole linked terrain area --")
	_check("target on one trapezoid half: visible across the OTHER half (link_group)",
		tm.model_visible_11e(obs, tgt_on))
	_check("light feature of the target's own area does not block",
		tm.model_visible_11e(obs, _model("t2", 740, 1120, 25)))
	_check("model fully behind the area (not within): still blocked",
		not tm.model_visible_11e(obs, tgt_behind))
	var board = {"terrain_features": tm.terrain_features}
	_check("EnhancedLineOfSight agrees at 11e (sees the on-strip model)",
		enh.check_enhanced_visibility(obs, tgt_on, board).get("has_los"))
	_check("EnhancedLineOfSight agrees at 11e (behind stays blocked)",
		not enh.check_enhanced_visibility(obs, tgt_behind, board).get("has_los"))

	print("\n-- 13.11 Solid: dense features stay opaque inside the same area --")
	var obs_north_of_wall = _model("onw", 880, 1250, 25)   # within trap_a, north of wall_feat
	var tgt_south_of_wall = _model("tsw", 880, 1390, 25)   # within trap_a, south of wall_feat (12px gap each side)
	_check("dense wall feature blocks between models in the SAME area",
		not tm.model_visible_11e(obs_north_of_wall, tgt_south_of_wall))

	print("\n-- 01.04 'within' = any part of base (not just center) --")
	# Base 32mm → radius ~25px. Center 12px outside trap_a's west edge (x=650),
	# so the base overlaps the area: the area must not obscure this model.
	var straddler = _model("straddler", 638, 1300, 32)
	_check("base straddling the area edge counts as within (visible)",
		tm.model_visible_11e(obs, straddler))
	_check("straddler is hidden (within a dense-containing area, any part)",
		tm.is_model_hidden(straddler, unit_inf))

	print("\n-- occupying a dense feature (center inside): sees out --")
	# Feature polygon CONTAINING the model, like the mirror_1 catwalk that
	# sticks out past its parent strip.
	var catwalk = {"id": "catwalk", "type": "ruins", "piece_class": "feature",
		"category": "dense", "parent_area_id": "strip_area",
		"polygon": _rect(800, 740, 280, 80)}
	var strip_area = {"id": "strip_area", "type": "ruins", "piece_class": "area",
		"category": "dense", "polygon": _rect(800, 740, 240, 80)}
	tm.terrain_features = [strip_area, catwalk]
	var on_catwalk = _model("oc", 800, 740, 40)
	var out_target = _model("ot", 800, 1200, 25)
	_check("model on the catwalk sees out of its own structure",
		tm.model_visible_11e(on_catwalk, out_target))
	_check("…and is seen from outside (into the occupied structure)",
		tm.model_visible_11e(out_target, on_catwalk))

	print("\n-- legacy bare pieces: own area + Solid structure --")
	# A thin solid wall (no piece_class): a base merely TOUCHING its footprint
	# does not gain X-ray vision through it (iss047 PRECISION semantics).
	var bare_wall = {"id": "bare_wall", "type": "ruins", "height_category": "tall",
		"polygon": _rect(500, 500, 20, 200)}
	tm.terrain_features = [bare_wall]
	var shooter_w = _model("sw", 300, 500, 32)
	var leaner = _model("leaner", 522, 500, 32)  # center 12px east of the wall edge — base overlaps footprint
	_check("leaning against a bare solid wall: still NOT visible through it",
		not tm.model_visible_11e(shooter_w, leaner))
	var occupier = _model("occ", 500, 500, 32)   # center inside the bare piece
	_check("center inside a bare piece: sees out (enterable footprint)",
		tm.model_visible_11e(occupier, shooter_w))

	print("\n-- 13.09 hidden + Gone to Ground use the same exclusions --")
	tm.terrain_features = [trap_a, trap_b, light_corner, wall_feat]
	_check("on-strip infantry is hidden", tm.is_model_hidden(tgt_on, unit_inf))
	_check("no GtG penalty from the target's OWN area: detection stays 15\"",
		tm.detection_range_inches_for(tgt_on, unit_inf, obs) == 15.0)
	_check("hidden model visible at ~11\" (within 15\" detection)",
		tm.hidden_model_visible_to(tgt_on, unit_inf, obs))
	var obs_far = _model("obs_far", 460, 660, 40)  # same bearing, ~18"
	_check("hidden model NOT visible at ~18\" (beyond detection)",
		not tm.hidden_model_visible_to(tgt_on, unit_inf, obs_far))

	print("\n-- end-to-end targeting + the player-facing reason --")
	var mk_board = func(shooter_model: Dictionary, target_models: Array) -> Dictionary:
		return {
			"units": {
				"U_CUST": {"owner": 1, "flags": {}, "meta": {"name": "Custodian Guard",
					"display_name": "Custodian Guard", "keywords": ["INFANTRY"], "stats": {},
					"weapons": [{"id": "spear_bolt", "name": "Guardian spear (bolt)", "type": "Ranged",
						"range": "24", "attacks": "2", "ballistic_skill": "2", "strength": "4",
						"ap": "-1", "damage": "2"}], "abilities": []},
					"models": [shooter_model]},
				"U_GROT": {"owner": 2, "flags": {}, "meta": {"name": "Gretchin",
					"display_name": "Gretchin", "keywords": ["INFANTRY", "GRETCHIN"],
					"stats": {"toughness": 3, "save": 7}, "weapons": [], "abilities": []},
					"models": target_models}
			},
			"terrain_features": tm.terrain_features
		}
	var b_near = mk_board.call(obs, [tgt_on, tgt_behind])
	_check("within detection: Gretchin ARE a legal target (the user's case)",
		rules.get_eligible_targets("U_CUST", b_near).has("U_GROT"))
	var b_far = mk_board.call(obs_far, [tgt_on, tgt_behind])
	_check("beyond detection: not targetable",
		not rules.get_eligible_targets("U_CUST", b_far).has("U_GROT"))
	var reason_far = rules.get_target_ineligibility_reason("U_CUST", "U_GROT", b_far)
	_check("…and the reason names the Hidden rule, not 'no line of sight'",
		reason_far.contains("Hidden"), reason_far)
	var b_behind = mk_board.call(obs, [tgt_behind])
	var reason_behind = rules.get_target_ineligibility_reason("U_CUST", "U_GROT", b_behind)
	_check("fully obscured unit: reason says terrain blocks every sight line",
		reason_behind.contains("terrain blocks every sight line"), reason_behind)

	GameConstants.edition = prev_edition
	tm.terrain_features = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
