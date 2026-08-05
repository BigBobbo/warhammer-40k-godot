extends SceneTree

# LOS-OVERLAY-AGREEMENT — the rules-engine half of the 2026-08 report
# "custodes guard Delta trying to shoot at stormboyz beta and the line of sight
# debug makes it look like there is at least one green line between the two
# squads but the target is not an option".
#
# The overlay was answering "is there a clear sight line?" while the target list
# answered "is this a legal target?". These are different questions: range,
# engagement range, Hidden (13.09), Lone Operative and transports all refuse
# targets the models can see perfectly well. The fix routes both through the
# rules engine, which needs three things to be true:
#
#   1. unit_sight_line() judges unit-to-unit sight with the SAME predicate
#      _check_target_visibility uses (base-aware LoS + the 13.09 hidden gate),
#      ignoring weapon range — and hands back the pair that proves it, or the
#      nearest pair plus where its line dies.
#   2. explain_target_ineligibility() carries a stable `code` so a caller can
#      tell "cannot SEE it" from "can see it but may not shoot it" without
#      pattern-matching English.
#   3. reason == "" agrees with get_eligible_targets() membership — including
#      the two gates the prose version used to miss entirely (embarked units,
#      and Lone Operative ranges other than 12").
#   4. unit_within_weapon_reach() backs Settings > Visual > "LoS Debug: include
#      units out of weapon range". It is a pure distance test against the
#      LONGEST gun in the loadout, so it can only ever over-include — a unit the
#      target list would accept can never be filtered away — and a melee-only
#      unit, having no range to be outside of, is never filtered at all.
#
# The windowed half lives in tests/scenarios/sp/los_overlay_targetable_vs_visible.json.
#
# Usage: godot --headless --path . -s tests/test_los_overlay_targeting_agreement.gd

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

# 24" Guardian spear, mirroring the reported matchup.
func _shooter(models: Array) -> Dictionary:
	return {"owner": 1, "flags": {}, "models": models, "meta": {
		"name": "Custodian Guard", "display_name": "Custodian Guard",
		"keywords": ["INFANTRY"], "stats": {},
		"weapons": [{"id": "spear_bolt", "name": "Guardian spear", "type": "Ranged",
			"range": "24", "attacks": "2", "ballistic_skill": "2", "strength": "4",
			"ap": "-1", "damage": "2"}], "abilities": []}}

func _orks(models: Array, extra: Dictionary = {}) -> Dictionary:
	var u := {"owner": 2, "flags": {}, "models": models, "meta": {
		"name": "Stormboyz", "display_name": "Stormboyz",
		"keywords": ["INFANTRY"], "stats": {"toughness": 5, "save": 5},
		"weapons": [], "abilities": []}}
	for k in extra:
		u[k] = extra[k]
	return u

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_los_overlay_targeting_agreement ===\n")
	var tm = root.get_node_or_null("TerrainManager")
	var rules = root.get_node_or_null("RulesEngine")
	var prev_terrain = tm.terrain_features.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	tm.terrain_features = []
	rules.clear_los_memo()

	# 40px per inch. Shooter at (400, 2000); "near" squad 15" north (in range of
	# the 24" spear), "far" squad 32" north (visible down the same open lane but
	# out of range) — the exact shape of the reported board.
	var shooter_models := [_model("s1", 400, 2000), _model("s2", 400, 2045)]
	var near_models := [_model("n1", 400, 1400), _model("n2", 400, 1355)]
	var far_models := [_model("f1", 400, 720), _model("f2", 400, 675)]

	var board := {
		"units": {
			"U_CUST": _shooter(shooter_models),
			"U_NEAR": _orks(near_models),
			"U_FAR": _orks(far_models),
		},
		"terrain_features": [],
	}

	print("-- open ground: sight is clear to BOTH squads, only one is a target --")
	var sl_near = rules.unit_sight_line("U_CUST", "U_NEAR", board)
	var sl_far = rules.unit_sight_line("U_CUST", "U_FAR", board)
	_check("unit_sight_line sees the near squad", sl_near.has_los)
	_check("unit_sight_line sees the far squad too (range is not its business)", sl_far.has_los)
	_check("a proving sight line reports no block point", not sl_far.has("block_at"))
	_check("sight line runs between real model positions",
		sl_near.from == Vector2(400, 2000) and sl_near.to == Vector2(400, 1400),
		"%s -> %s" % [str(sl_near.from), str(sl_near.to)])

	var elig = rules.get_eligible_targets("U_CUST", board)
	_check("near squad IS a legal target", elig.has("U_NEAR"))
	_check("far squad is NOT a legal target", not elig.has("U_FAR"))
	var why_far = rules.explain_target_ineligibility("U_CUST", "U_FAR", board)
	_check("…because it is out of range, and the code says so", why_far.code == "out_of_range", why_far.code)
	_check("…with player-facing prose to match", why_far.reason.contains("out of range"), why_far.reason)
	_check("the eligible target explains as eligible",
		rules.explain_target_ineligibility("U_CUST", "U_NEAR", board).code == "")
	_check("get_target_ineligibility_reason still returns the prose (wrapper intact)",
		rules.get_target_ineligibility_reason("U_CUST", "U_FAR", board) == why_far.reason)

	print("\n-- a wall: now sight itself fails, and the code distinguishes it --")
	# Dense feature across the lane between shooter and the near squad.
	tm.terrain_features = [{"id": "wall", "type": "ruins", "piece_class": "feature",
		"category": "dense", "height_category": "tall", "polygon": _rect(400, 1700, 900, 60)}]
	var walled := {
		"units": {"U_CUST": _shooter(shooter_models), "U_NEAR": _orks(near_models)},
		"terrain_features": tm.terrain_features,
	}
	rules.clear_los_memo()
	var sl_walled = rules.unit_sight_line("U_CUST", "U_NEAR", walled)
	_check("wall kills the sight line", not sl_walled.has_los)
	_check("blocked line reports WHERE it died", sl_walled.has("block_at"), str(sl_walled))
	if sl_walled.has("block_at"):
		var bp: Vector2 = sl_walled.block_at
		_check("…and the block point sits between the two models, not on an endpoint",
			bp.y < sl_walled.from.y and bp.y > sl_walled.to.y, str(bp))
	_check("blocked pair falls back to the NEAREST models",
		sl_walled.from == Vector2(400, 2000) and sl_walled.to == Vector2(400, 1400),
		"%s -> %s" % [str(sl_walled.from), str(sl_walled.to)])
	var why_walled = rules.explain_target_ineligibility("U_CUST", "U_NEAR", walled)
	_check("code names the sight-line failure, not range", why_walled.code == "no_los", why_walled.code)
	_check("_has_los_to_target_unit agrees with unit_sight_line",
		rules._has_los_to_target_unit("U_CUST", "U_NEAR", walled) == sl_walled.has_los)

	print("\n-- gaps the prose version used to miss vs get_eligible_targets --")
	tm.terrain_features = []
	rules.clear_los_memo()
	# 18.01: a unit inside a transport is off the battlefield. Its models can
	# still carry a stale pre-embark position, which used to make the reason
	# function answer "" — "targetable" — for a unit the list never offers.
	var embarked := {
		"units": {
			"U_CUST": _shooter(shooter_models),
			"U_NEAR": _orks(near_models, {"embarked_in": "U_TRUKK"}),
		},
		"terrain_features": [],
	}
	_check("embarked unit is not in the target list",
		not rules.get_eligible_targets("U_CUST", embarked).has("U_NEAR"))
	var why_emb = rules.explain_target_ineligibility("U_CUST", "U_NEAR", embarked)
	_check("…and the explanation agrees instead of reporting it targetable",
		why_emb.code == "embarked", "%s / %s" % [why_emb.code, why_emb.reason])

	# Lone Operative X": get_eligible_targets reads the datasheet range, the
	# prose version hardcoded 12" — so a 6" Lone Operative sitting 9" away was
	# refused by the list and called eligible by the explanation.
	var lone_models := [_model("l1", 400, 1640)]  # 9" from the shooter
	var lone := {
		"units": {
			"U_CUST": _shooter(shooter_models),
			"U_NEAR": _orks(lone_models, {"attachment_data": {"attached_characters": []}}),
		},
		"terrain_features": [],
	}
	lone["units"]["U_NEAR"]["meta"]["abilities"] = [{"name": "Lone Operative 6\""}]
	rules.clear_los_memo()
	_check("Lone Operative 6\" at 9\" is not in the target list",
		not rules.get_eligible_targets("U_CUST", lone).has("U_NEAR"))
	var why_lone = rules.explain_target_ineligibility("U_CUST", "U_NEAR", lone)
	_check("…and the explanation agrees (was: '' because it assumed 12\")",
		why_lone.code == "lone_operative", "%s / %s" % [why_lone.code, why_lone.reason])
	_check("…quoting the datasheet's own range, not 12\"",
		why_lone.reason.contains("6\""), why_lone.reason)

	print("\n-- Settings > Visual: the out-of-range pre-filter --")
	rules.clear_los_memo()
	_check("longest ranged weapon is read off the loadout (24\" Guardian spear)",
		is_equal_approx(rules.max_ranged_weapon_range_inches("U_CUST", board), 24.0),
		str(rules.max_ranged_weapon_range_inches("U_CUST", board)))
	_check("near squad (15\") is within reach", rules.unit_within_weapon_reach("U_CUST", "U_NEAR", board))
	_check("far squad (32\") is not", not rules.unit_within_weapon_reach("U_CUST", "U_FAR", board))
	# The filter must never hide something the target list would accept: it is a
	# pure distance test against the LONGEST gun, so it can only over-include.
	_check("nothing the target list accepts is filtered out",
		rules.get_eligible_targets("U_CUST", board).keys().all(
			func(uid): return rules.unit_within_weapon_reach("U_CUST", uid, board)))
	# A melee-only unit has no range to be outside of — filtering it to nothing
	# would blank the overlay for every assault unit on the board.
	var melee_only := {
		"units": {
			"U_MELEE": {"owner": 1, "flags": {}, "models": shooter_models, "meta": {
				"name": "Kustodian Blades", "display_name": "Kustodian Blades",
				"keywords": ["INFANTRY"], "stats": {}, "weapons": [], "abilities": []}},
			"U_FAR": _orks(far_models),
		},
		"terrain_features": [],
	}
	_check("a unit with no ranged weapons reports 0\" reach",
		is_equal_approx(rules.max_ranged_weapon_range_inches("U_MELEE", melee_only), 0.0))
	_check("…and is therefore never filtered (its sight lines stay drawn)",
		rules.unit_within_weapon_reach("U_MELEE", "U_FAR", melee_only))

	print("\n-- the overlay's invariant: reason == \"\"  <=>  in the target list --")
	var boards := {"open": board, "walled": walled, "embarked": embarked, "lone": lone}
	var disagreements := 0
	for name in boards:
		var b = boards[name]
		var e = rules.get_eligible_targets("U_CUST", b)
		for uid in b["units"]:
			if uid == "U_CUST":
				continue
			var eligible_here: bool = e.has(uid)
			var says_eligible: bool = rules.explain_target_ineligibility("U_CUST", uid, b).code == ""
			if eligible_here != says_eligible:
				disagreements += 1
				print("    disagreement on %s/%s: eligible=%s explained_eligible=%s" % [name, uid, str(eligible_here), str(says_eligible)])
	_check("no board disagrees", disagreements == 0, "%d disagreement(s)" % disagreements)

	GameConstants.edition = prev_edition
	tm.terrain_features = prev_terrain
	rules.clear_los_memo()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
