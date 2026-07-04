extends SceneTree

# ISS-052 (step 1): the 11e HIDDEN rule (13.09) — INFANTRY/BEASTS/SWARM in
# a dense-containing terrain area that haven't shot recently are visible
# only within 15" detection range. Edition-gated (no effect at 10e).
#
# Usage: godot --headless --path . -s tests/test_iss052_hidden_11e.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss052_hidden_11e ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var prev = tm.terrain_features.duplicate(true)
	tm.terrain_features = [
		{"id": "ruin", "type": "ruins", "polygon": _rect(400, 400, 200, 200), "height_category": "tall"},
		{"id": "crater", "type": "crater", "polygon": _rect(900, 400, 100, 100), "height_category": "low"},
	]

	var in_ruin = {"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 400}}
	var in_crater = {"id": "m1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 900, "y": 400}}
	var in_open = {"id": "m2", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 650, "y": 800}}
	var infantry = {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}
	var vehicle = {"meta": {"keywords": ["VEHICLE"]}, "flags": {}}
	var infantry_shot = {"meta": {"keywords": ["INFANTRY"]}, "flags": {"shot_recently": true}}

	GameConstants.edition = 11
	print("-- hidden qualification (13.09) --")
	_check("infantry in a dense area is hidden", tm.is_model_hidden(in_ruin, infantry))
	_check("infantry in an EXPOSED area (crater) is not hidden", not tm.is_model_hidden(in_crater, infantry))
	_check("infantry in the open is not hidden", not tm.is_model_hidden(in_open, infantry))
	_check("VEHICLE in a dense area is not hidden", not tm.is_model_hidden(in_ruin, vehicle))
	_check("infantry that shot recently is not hidden", not tm.is_model_hidden(in_ruin, infantry_shot))

	print("\n-- detection range (15\") --")
	# 14" away (560px) -> within detection; 16" (640px) -> not visible.
	var near_observer = {"id": "o1", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 14 * 40, "y": 400}}
	var far_observer = {"id": "o2", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 17 * 40, "y": 400}}
	_check("hidden model visible within 15\" detection",
		tm.hidden_model_visible_to(in_ruin, infantry, near_observer))
	_check("hidden model NOT visible beyond detection range",
		not tm.hidden_model_visible_to(in_ruin, infantry, far_observer))
	_check("non-hidden model visible regardless of range",
		tm.hidden_model_visible_to(in_open, infantry, far_observer))

	print("\n-- Gone to Ground (-3\" behind dense) + datasheet modifiers (audit Tier-1 #4) --")
	# near_observer sits 14" center / ~12.7" edge from the hidden model:
	# inside the default 15" detection but OUTSIDE the 12" Gone-to-Ground band.
	_check("base detection range is 15\"",
		tm.detection_range_base_inches(infantry) == 15.0)
	_check("no intervening dense: full 15\" detection",
		tm.detection_range_inches_for(in_ruin, infantry, near_observer) == 15.0)
	var strip := {"id": "gtg_strip", "type": "ruins", "polygon": _rect(650, 400, 20, 60), "height_category": "tall"}
	tm.terrain_features.append(strip)
	_check("intervening dense strip -> obscured (Gone to Ground applies)",
		tm._obscured_by_dense_11e(near_observer, in_ruin))
	_check("Gone to Ground: detection drops to 12\"",
		tm.detection_range_inches_for(in_ruin, infantry, near_observer) == 12.0)
	_check("hidden model at ~12.7\" NOT visible behind dense (12\" detection)",
		not tm.hidden_model_visible_to(in_ruin, infantry, near_observer))
	var close_observer = {"id": "o3", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 13 * 40, "y": 400}}
	_check("hidden model at ~11.7\" still visible behind dense",
		tm.hidden_model_visible_to(in_ruin, infantry, close_observer))
	tm.terrain_features.pop_back()

	var stealthy = {"meta": {"keywords": ["INFANTRY"], "abilities": ["Detection Range 9\""]}, "flags": {}}
	_check("datasheet 'Detection Range 9\"' overrides the 15\" base",
		tm.detection_range_base_inches(stealthy) == 9.0)
	_check("stealthy hidden model at ~12.7\" NOT visible (9\" detection)",
		not tm.hidden_model_visible_to(in_ruin, stealthy, near_observer))
	var point_blank = {"id": "o4", "alive": true, "base_mm": 32, "base_type": "circular", "position": {"x": 400 + 10 * 40, "y": 400}}
	_check("stealthy hidden model at ~8.7\" visible (9\" detection)",
		tm.hidden_model_visible_to(in_ruin, stealthy, point_blank))
	tm.terrain_features.append(strip)
	_check("floor: 9\" datasheet range minus Gone to Ground clamps at 9\", not 6\"",
		tm.detection_range_inches_for(in_ruin, stealthy, point_blank) == 9.0)
	_check("stealthy hidden model at ~8.7\" still visible behind dense (9\" floor)",
		tm.hidden_model_visible_to(in_ruin, stealthy, point_blank))
	tm.terrain_features.pop_back()

	print("\n-- edition gate --")
	GameConstants.edition = 10
	_check("no Hidden rule at edition 10", not tm.is_model_hidden(in_ruin, infantry))
	GameConstants.edition = 10

	GameConstants.edition = 11
	print("\n-- step 2: 06.01 visible vs FULLY visible + 13.08 cover half --")
	# A thin dense strip that crosses the CENTER line between observer
	# (200,1000) and target (1200,1000) but not the off-center edge lines.
	tm.terrain_features = [
		{"id": "strip", "type": "ruins", "polygon": _rect(690, 1035, 20, 90), "height_category": "tall"},
	]
	var obs = {"id": "o1", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 200, "y": 1000}}
	var tgt = {"id": "t1", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 1200, "y": 1000}}
	_check("partial block: still VISIBLE (some lines clear, 06.01)",
		tm.model_visible_11e(obs, tgt))
	_check("partial block: NOT fully visible (a line crosses the strip)",
		not tm.model_fully_visible_11e(obs, tgt))
	tm.terrain_features = []
	_check("open ground: fully visible", tm.model_fully_visible_11e(obs, tgt))
	tm.terrain_features = [
		{"id": "wall", "type": "ruins", "polygon": _rect(600, 1000, 100, 3000), "height_category": "tall"},
	]
	_check("full wall: not visible at all (13.10 every line)",
		not tm.model_visible_11e(obs, tgt))
	var obs_inside = {"id": "o2", "alive": true, "base_mm": 32, "base_type": "circular",
		"position": {"x": 600, "y": 1000}}
	_check("observer INSIDE the area sees out (13.10 exclusion)",
		tm.model_visible_11e(obs_inside, tgt))

	# 13.08's not-fully-visible half: a VEHICLE (no INFANTRY keyword, not
	# within an area) still gets cover when partially blocked.
	tm.terrain_features = [
		{"id": "strip", "type": "ruins", "polygon": _rect(690, 1035, 20, 90), "height_category": "tall"},
	]
	var veh_unit = {"id": "U_V", "owner": 2, "flags": {},
		"meta": {"keywords": ["VEHICLE"], "stats": {}},
		"models": [tgt]}
	_check("cover via not-fully-visible (13.08 second condition, VEHICLE)",
		tm.unit_has_cover_11e(veh_unit, obs))
	tm.terrain_features = []
	_check("fully visible in the open: no cover",
		not tm.unit_has_cover_11e(veh_unit, obs))

	print("\n-- A5: the last_shot_idx turn-stamp (\"did not shoot this or previous turn\") --")
	# ShootingPhase stamps flags.last_shot_idx = battle_round*2 + (P1 ? 0 : 1)
	# on every real ranged attack; is_model_hidden reads it against the live
	# battle-round counter: cur_idx - last_shot_idx < 2 -> not hidden.
	GameConstants.edition = 11
	tm.terrain_features = [
		{"id": "ruin2", "type": "ruins", "polygon": _rect(400, 400, 200, 200), "height_category": "tall"},
	]
	var gs = root.get_node("GameState")
	var prev_round = gs.state["meta"].get("battle_round", 1)
	var prev_active = gs.state["meta"].get("active_player", 1)
	gs.state["meta"]["battle_round"] = 3
	gs.state["meta"]["active_player"] = 1  # cur_idx = 3*2 + 0 = 6
	var shooter = {"meta": {"keywords": ["INFANTRY"]}, "flags": {}}
	_check("no stamp: hidden", tm.is_model_hidden(in_ruin, shooter))
	shooter.flags["last_shot_idx"] = 6
	_check("shot THIS player turn (idx 6): not hidden", not tm.is_model_hidden(in_ruin, shooter))
	shooter.flags["last_shot_idx"] = 5
	_check("shot the PREVIOUS player turn (idx 5): not hidden", not tm.is_model_hidden(in_ruin, shooter))
	shooter.flags["last_shot_idx"] = 4
	_check("shot two player turns ago (idx 4): hidden again", tm.is_model_hidden(in_ruin, shooter))
	gs.state["meta"]["active_player"] = 2  # cur_idx advances to 7
	_check("next player turn: an idx-5 stamp expires too",
		tm.is_model_hidden(in_ruin, {"meta": {"keywords": ["INFANTRY"]}, "flags": {"last_shot_idx": 5}}))
	gs.state["meta"]["battle_round"] = prev_round
	gs.state["meta"]["active_player"] = prev_active

	GameConstants.edition = 10
	tm.terrain_features = prev
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
