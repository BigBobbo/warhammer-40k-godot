extends SceneTree

# ATTACHED-CHARACTER BEARER IDS — regression for the composite-id blind spot.
#
# get_unit_weapons() reports the models of an ATTACHED character under composite
# bearer ids, "<character_unit_id>:<model_id>", so damage routes back to the
# character's own unit. rules._get_model_by_id only ever understood plain
# ids ("m3") and the firing-deck synthetic form ("m1@fd2") — it has no board
# access, so a composite id found no match in the bodyguard unit's models and
# returned {}. EVERY caller that walked get_unit_weapons (or an assignment's
# model_ids) and then looked the bearer up therefore silently skipped an
# attached character's guns.
#
# The reported symptom was assign-time: picking a Warboss's kombi-weapon and
# clicking an enemy answered "can't fire (range / line of sight)" with an EMPTY
# reasons dict — the bearer was dropped before any range test ran. The same
# lookup is used in several resolve-time paths, where the failure is quieter but
# changes combat maths:
#
#   get_eligible_shooter_models    a character's guns were unassignable by hand
#   get_eligible_targets           a character's guns never made a target eligible
#   get_target_ineligibility_reason  ... and never appeared in the explanation
#   RAPID FIRE half-range count    a character never counted as within 1/2 range
#   MELTA half-range count         same, losing the damage bonus
#   CONVERSION X+ distance         all-character assignment -> INF >= 12" -> the
#                                  crit bonus switched ON regardless of distance
#   11e hit modifier stack         all-character assignment -> EMPTY attacker
#                                  model list for cover / STEALTH / plunging fire
#
# rules.resolve_bearer_model / resolve_bearer_unit resolve the composite
# through the board; this test pins each consumer above.
#
# Usage: godot --headless --path . -s tests/test_attached_char_bearer_ids.gd

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

func _model(id: String, x: float, y: float, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attached_char_bearer_ids ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	_check("autoloads present", gs != null and rules != null and cam != null)
	if gs == null or rules == null or cam == null:
		print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	GameConstants.edition = 11

	# Open board: this test is about bearer resolution, not line of sight.
	var tm = root.get_node_or_null("TerrainManager")
	if tm != null:
		tm.terrain_features = []
	if gs.state.has("board"):
		gs.state.board["terrain_features"] = []

	# ---- fixture -----------------------------------------------------------
	# 40px == 1", so the squad sits 4" from the target and the character 5".
	# Both are inside 12" (the RAPID FIRE half of a 24" gun) and inside 12" for
	# MELTA on a 24" gun; both are UNDER 12" from the target, which is what makes
	# the CONVERSION assertion meaningful (INF would read as "12 or more").
	# Measurement is an autoload, not a global class — reach it through the tree
	# (a bare `Measurement` identifier does not compile in a SceneTree script).
	var meas = root.get_node("Measurement")
	var px_per_inch := float(meas.inches_to_px(1.0))

	gs.state.units["U_BG_BR"] = {"id": "U_BG_BR", "owner": 1, "status": 2, "flags": {},
		"meta": {"name": "Boyz BR", "keywords": ["INFANTRY", "BOYZ"],
			"stats": {"toughness": 5, "save": 6, "wounds": 1, "move": 6},
			"weapons": [{"name": "Test slugga", "type": "Ranged", "range": "12",
				"attacks": "1", "ballistic_skill": "5", "strength": "4", "ap": "0",
				"damage": "1", "keywords": [], "special_rules": ""}]},
		"models": [_model("m1", 800.0, 300.0), _model("m2", 840.0, 300.0)]}

	# The character carries a DIFFERENT weapon, so every assertion below is about
	# a weapon whose ONLY bearer is the attached character.
	gs.state.units["U_CHAR_BR"] = {"id": "U_CHAR_BR", "owner": 1, "status": 2, "flags": {}, "attached_to": null,
		"meta": {"name": "Warboss BR", "keywords": ["CHARACTER", "INFANTRY"],
			"leader_data": {"can_lead": ["BOYZ"]},
			"stats": {"toughness": 5, "save": 4, "wounds": 6, "move": 6},
			"weapons": [{"name": "Test bosskannon", "type": "Ranged", "range": "24",
				"attacks": "2", "ballistic_skill": "2", "strength": "8", "ap": "2",
				"damage": "2", "keywords": ["Rapid Fire 2", "Melta 2"],
				"special_rules": "Rapid Fire 2, Melta 2"}]},
		"models": [_model("c1", 880.0, 300.0, 6)]}

	# Target 4" below the squad line.
	gs.state.units["U_TGT_BR"] = {"id": "U_TGT_BR", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Target BR", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 4, "wounds": 2, "move": 6}},
		"models": [_model("t1", 800.0, 300.0 + 4.0 * px_per_inch, 2)]}

	cam.attach_character("U_CHAR_BR", "U_BG_BR")
	_check("fixture: character attached", gs.state.units["U_CHAR_BR"].get("attached_to") == "U_BG_BR",
		str(gs.state.units["U_CHAR_BR"].get("attached_to")))

	var board = gs.create_snapshot()
	var bg_unit: Dictionary = board.units["U_BG_BR"]
	var tgt_unit: Dictionary = board.units["U_TGT_BR"]

	# The composite bearer id the whole test hangs on.
	var uw = rules.get_unit_weapons("U_BG_BR", board)
	var composite_id := ""
	var char_weapon_id := ""
	for bid in uw:
		if ":" in str(bid):
			composite_id = str(bid)
			for wid in uw[bid]:
				char_weapon_id = str(wid)
			break
	_check("fixture: get_unit_weapons reports a composite bearer id",
		composite_id.begins_with("U_CHAR_BR:"), str(uw.keys()))
	_check("fixture: the character's weapon is only on that bearer",
		char_weapon_id != "", str(uw))
	if composite_id == "" or char_weapon_id == "":
		_finish(gs)
		return

	# ---- 1. the resolver itself -------------------------------------------
	var resolved = rules.resolve_bearer_model(bg_unit, composite_id, board)
	_check("resolve_bearer_model finds the character's model",
		not resolved.is_empty() and str(resolved.get("id", "")) == "c1", str(resolved.get("id", "<none>")))
	_check("resolve_bearer_model still handles a plain id",
		str(rules.resolve_bearer_model(bg_unit, "m1", board).get("id", "")) == "m1")
	_check("resolve_bearer_model returns {} for an unknown composite owner",
		rules.resolve_bearer_model(bg_unit, "U_NOPE:m1", board).is_empty())
	_check("resolve_bearer_unit returns the character's own unit",
		str(rules.resolve_bearer_unit(bg_unit, composite_id, board).get("id", "")) == "U_CHAR_BR")
	_check("resolve_bearer_unit returns the actor unit for a plain id",
		str(rules.resolve_bearer_unit(bg_unit, "m1", board).get("id", "")) == "U_BG_BR")

	# ---- 2. assign-time eligibility (the reported bug) ---------------------
	var elig = rules.get_eligible_shooter_models("U_BG_BR", char_weapon_id, "U_TGT_BR", board)
	_check("get_eligible_shooter_models returns the character's bearer",
		composite_id in elig.eligible, "eligible=%s reasons=%s" % [str(elig.eligible), str(elig.reasons)])

	# ---- 3. target eligibility scans --------------------------------------
	var targets = rules.get_eligible_targets("U_BG_BR", board)
	var char_weapon_offered := false
	if targets.has("U_TGT_BR"):
		for wid in targets["U_TGT_BR"].get("weapons_in_range", []):
			if str(wid) == char_weapon_id:
				char_weapon_offered = true
	_check("get_eligible_targets offers the character's weapon",
		char_weapon_offered, str(targets.get("U_TGT_BR", {}).get("weapons_in_range", [])))

	# ---- 4. RAPID FIRE / MELTA half-range counting -------------------------
	# The character is ~5" away; half of the 24" gun is 12". It must count.
	var in_half = rules.count_models_in_half_range(bg_unit, tgt_unit, char_weapon_id, [composite_id], board)
	_check("count_models_in_half_range counts the character's model",
		in_half == 1, "got %d" % in_half)

	# ---- 5. CONVERSION X+ distance ----------------------------------------
	# _get_min_distance_to_target is private; go through the public consumer.
	# With the bearer dropped the helper returned INF, and INF >= 12" switched
	# the bonus on. The character is ~5" away, so a Conversion weapon must NOT
	# get its lowered crit threshold here.
	var conv_unit := {
		"id": "U_CONV_BR", "owner": 1, "status": 2, "flags": {},
		"meta": {"name": "Conv BR", "keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 6, "wounds": 1, "move": 6},
			"weapons": [{"name": "Test conversion gun", "type": "Ranged", "range": "24",
				"attacks": "1", "ballistic_skill": "3", "strength": "5", "ap": "1",
				"damage": "1", "keywords": ["Conversion 5+"], "special_rules": "Conversion 5+"}]},
		"models": [_model("cv1", 880.0, 300.0)]
	}
	gs.state.units["U_CONV_BR"] = conv_unit
	var conv_board = gs.create_snapshot()
	var conv_wid := ""
	var conv_uw = rules.get_unit_weapons("U_CONV_BR", conv_board)
	for bid in conv_uw:
		for wid in conv_uw[bid]:
			conv_wid = str(wid)
	if conv_wid != "" and rules.get_conversion_threshold(conv_wid, conv_board) > 0:
		# Sanity: a REAL (non-composite) bearer 5" away must not trigger it.
		var near_thresh = rules.get_critical_hit_threshold(
			conv_wid, conv_board.units["U_CONV_BR"], conv_board.units["U_TGT_BR"], ["cv1"], conv_board)
		_check("CONVERSION stays off for a real bearer inside 12\"", near_thresh == 6, "got %d" % near_thresh)
		# The regression: a COMPOSITE bearer (resolvable through the board, but
		# invisible to the old actor_unit-only lookup) must not fake a 12\"+
		# distance and switch the bonus on. The character stands ~5\" away.
		var ghost_thresh = rules.get_critical_hit_threshold(
			conv_wid, conv_board.units["U_CONV_BR"], conv_board.units["U_TGT_BR"], ["U_CHAR_BR:c1"], conv_board)
		_check("CONVERSION stays off for a character bearer inside 12\"",
			ghost_thresh == 6, "got %d (INF distance would have switched it on)" % ghost_thresh)
	else:
		print("  SKIP: Conversion keyword not parsed from this fixture profile")

	# ---- 6. resolution actually fires the character's gun ------------------
	# _filter_eligible_model_ids has a fallback that trusts the caller when
	# eligibility returns BOTH an empty list and empty reasons — that fallback is
	# why auto-assigned character guns always fired despite the bug. Now that
	# eligibility resolves them properly, the filter does real work, so pin that
	# it KEEPS the character rather than dropping the shot.
	var filt_kept: Array = []
	var filt = rules._filter_eligible_model_ids(
		[composite_id], "U_BG_BR", char_weapon_id, "U_TGT_BR", board)
	filt_kept = filt.get("kept", [])
	_check("resolve-time filter keeps the character's bearer",
		composite_id in filt_kept, "kept=%s dropped=%s" % [str(filt_kept), str(filt.get("dropped", []))])

	_finish(gs)


func _finish(gs) -> void:
	for uid in ["U_BG_BR", "U_CHAR_BR", "U_TGT_BR", "U_CONV_BR"]:
		gs.state.units.erase(uid)
	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
