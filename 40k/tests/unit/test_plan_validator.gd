extends SceneTree

# PM-0 — PlanValidator tests (wh40k_ai_plan v1)
#
# Covers: the two shipped fixture plans validate; every corruption class fails
# with its expected error (bad verb, TRADE, missing HOLD target, unknown zone,
# placement outside the player-1 zone, placement whose seat-2 transform leaves
# the player-2 zone, reserves/earmark contradiction, reserves caps exceeded);
# unit coverage against a real army, including the duplicate-unit-name case
# that motivated keying plans on army-file unit ids.
#
# Run with: godot --headless --path . -s tests/unit/test_plan_validator.gd

const PV = preload("res://scripts/PlanValidator.gd")

# DeploymentZoneData cannot be preloaded OR load()ed from a `-s` SceneTree
# script: it calls the `Measurement` autoload, whose identifier does not resolve
# in this compile context, and the attempt emits
# "SCRIPT ERROR: Compile Error: Identifier not found: Measurement" — an ERROR
# line the project's delivery gates treat as a failure. DEPLOYMENT_TYPES is a
# plain literal const, so the cross-check below reads it out of the source text
# instead. That still fails loudly if someone adds a JSON-less zone type.
const ZONE_DATA_PATH := "res://scripts/data/DeploymentZoneData.gd"

const FIXTURE_MINIMAL := "res://tests/fixtures/ai_plans/fixture_minimal_valid.json"
const FIXTURE_RICH := "res://tests/fixtures/ai_plans/fixture_recon_stomps_rich.json"
const RECON_STOMPS := "res://armies/recon_stomps.json"

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	print("\n=== PlanValidator (PM-0) Tests ===\n")
	_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _has_error(result: Dictionary, needle: String) -> bool:
	for e in result.get("errors", []):
		if str(e).to_lower().find(needle.to_lower()) != -1:
			return true
	return false

func _has_warning(result: Dictionary, needle: String) -> bool:
	for w in result.get("warnings", []):
		if str(w).to_lower().find(needle.to_lower()) != -1:
			return true
	return false

func _dump_errors(result: Dictionary) -> String:
	return "; ".join(result.get("errors", []))

# ---------------------------------------------------------------------------
# Fixtures built in code (so a corruption is a one-line mutation)
# ---------------------------------------------------------------------------

func _base_plan() -> Dictionary:
	return {
		"format": "wh40k_ai_plan",
		"version": 1,
		"name": "Unit-test plan",
		"description": "",
		"author": "test",
		"keys": {
			"army_file": "recon_stomps",
			"detachment_hint": "Speedwaaagh!",
			"deployment_zone_id": "hammer_anvil",
			"terrain_layout_id": "",
			"mission_id": "",
		},
		"deployment": {
			"order": ["U_GRETCHIN_A", "U_STORMBOYZ_B"],
			"placements": [
				{
					"unit": "U_GRETCHIN_A",
					"unit_name": "Gretchin",
					"role_fallback": "screen",
					"models_inches": [[10.0, 6.0], [11.5, 6.0], [13.0, 6.0]],
				},
				{
					"unit": "U_STORMBOYZ_B",
					"unit_name": "Stormboyz",
					"role_fallback": "screen",
					"models_inches": [[20.0, 9.0], [21.5, 9.0]],
				},
			],
			"reserves": [],
			"embarkations": [],
			"attachments": [],
		},
		"earmarks": [
			{"unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE", "target": "obj_home_1"},
		],
		"profile_fragment": {"parameters": {}, "rules": []},
	}

func _tiny_army() -> Dictionary:
	# 2 units, 200 points -> reserves caps are 100 points / 1 unit.
	return {
		"faction": {"name": "Orks", "detachment": "Speedwaaagh!"},
		"units": {
			"U_A": {"meta": {"name": "Alpha", "points": 100}, "models": []},
			"U_B": {"meta": {"name": "Beta", "points": 100}, "models": []},
		},
	}

func _load_army(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		return {}
	return json.data

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_geometry_helpers()
	test_deployment_types_all_have_zone_json()
	test_shipped_zones_are_point_symmetric()
	test_fixture_plans_validate()
	test_base_plan_valid()
	test_envelope_corruptions()
	test_unknown_zone_and_layout()
	test_bad_verb()
	test_trade_reserved()
	test_hold_objective_requires_target()
	test_placement_outside_player1_zone()
	test_placement_fails_seat2_transform()
	test_reserves_earmark_contradiction()
	test_reserves_caps()
	test_coverage_against_real_army()
	test_coverage_duplicate_names()

func test_geometry_helpers() -> void:
	var m = PV.mirror_inches(10.0, 12.0)
	_assert(is_equal_approx(m.x, 34.0) and is_equal_approx(m.y, 48.0),
		"mirror_inches([10,12]) == [34,48] (44-x, 60-y)")

	_assert(PV.zone_exists("hammer_anvil"), "zone_exists('hammer_anvil')")
	_assert(not PV.zone_exists("no_such_zone"),
		"zone_exists rejects an unknown id (get_zones' silent hammer_anvil fallback is not an existence check)")
	_assert(PV.layout_exists("take_and_hold_mirror_1"), "layout_exists('take_and_hold_mirror_1')")
	_assert(not PV.layout_exists("no_such_layout"), "layout_exists rejects an unknown id")

	var p1 = PV.get_zone_polygon("hammer_anvil", 1)
	var p2 = PV.get_zone_polygon("hammer_anvil", 2)
	_assert(p1.size() >= 3 and p2.size() >= 3, "hammer_anvil yields both zone polygons")
	_assert(PV.point_in_zone(Vector2(22.0, 6.0), p1), "point (22,6) is inside the hammer_anvil P1 zone")
	_assert(not PV.point_in_zone(Vector2(22.0, 30.0), p1), "board centre is outside the hammer_anvil P1 zone")

func _deployment_types() -> Array:
	"""Read DeploymentZoneData.DEPLOYMENT_TYPES out of the source text.

	See the ZONE_DATA_PATH note above for why the script itself is not loaded."""
	var file = FileAccess.open(ZONE_DATA_PATH, FileAccess.READ)
	if file == null:
		return []
	var src := file.get_as_text()
	file.close()
	var start := src.find("const DEPLOYMENT_TYPES")
	if start == -1:
		return []
	var open_bracket := src.find("[", start)
	var close_bracket := src.find("]", open_bracket)
	if open_bracket == -1 or close_bracket == -1:
		return []
	var types: Array = []
	for raw in src.substr(open_bracket + 1, close_bracket - open_bracket - 1).split(","):
		var token := str(raw).strip_edges().replace("\"", "").replace("'", "")
		if not token.is_empty() and not token.begins_with("#"):
			types.append(token)
	return types

func test_deployment_types_all_have_zone_json() -> void:
	# PlanValidator resolves zone geometry straight from
	# res://deployment_zones/<id>.json rather than through DeploymentZoneData
	# (which cannot be preloaded headless). That is only equivalent while every
	# selectable deployment type actually has such a file — assert it, so a
	# future JSON-less type fails here instead of going silently unvalidatable.
	var types := _deployment_types()
	_assert(types.size() == 6, "DeploymentZoneData.DEPLOYMENT_TYPES parsed from source (%d types: %s)" % [types.size(), ", ".join(types)])
	var missing: Array[String] = []
	for zone_id in types:
		if not PV.zone_exists(zone_id):
			missing.append(str(zone_id))
	_assert(missing.is_empty(), "every DEPLOYMENT_TYPES entry has deployment_zones/<id>.json%s" % (
		"" if missing.is_empty() else (" — missing: " + ", ".join(missing))))

func test_shipped_zones_are_point_symmetric() -> void:
	# Locked design decision 5 rests on this: every shipped zone is a 180-degree
	# point reflection of its opposite number, so a plan authored in the P1 frame
	# is legal at seat 2 after [x,y] -> [44-x, 60-y]. If a future zone breaks
	# this, the seat-2 placement check in validate_plan is what catches it.
	var failures: Array[String] = []
	var zone_types := _deployment_types()
	for zone_id in zone_types:
		var p1 = PV.get_zone_polygon(zone_id, 1)
		var p2 = PV.get_zone_polygon(zone_id, 2)
		if p1.size() < 3 or p2.size() < 3:
			failures.append("%s: missing polygons" % zone_id)
			continue
		for v in p1:
			var mirrored = PV.mirror_inches(v.x, v.y)
			var found := false
			for w in p2:
				if abs(w.x - mirrored.x) < 0.01 and abs(w.y - mirrored.y) < 0.01:
					found = true
					break
			if not found:
				failures.append("%s: P1 vertex (%.2f, %.2f) has no P2 counterpart at (%.2f, %.2f)" % [zone_id, v.x, v.y, mirrored.x, mirrored.y])
	_assert(failures.is_empty(), "all %d shipped deployment zones are point-symmetric%s" % [
		zone_types.size(),
		"" if failures.is_empty() else (" — " + "; ".join(failures))])

func test_fixture_plans_validate() -> void:
	var army := _load_army(RECON_STOMPS)
	_assert(not army.is_empty(), "recon_stomps army list loads")

	var minimal = PV.load_plan_file(FIXTURE_MINIMAL)
	_assert(not minimal.is_empty(), "minimal fixture plan parses")
	var r_min: Dictionary = PV.validate_plan(minimal, army)
	_assert(r_min.get("valid", false), "minimal fixture plan is valid (%s)" % _dump_errors(r_min))

	var rich = PV.load_plan_file(FIXTURE_RICH)
	_assert(not rich.is_empty(), "rich fixture plan parses")
	var r_rich: Dictionary = PV.validate_plan(rich, army)
	_assert(r_rich.get("valid", false), "rich fixture plan is valid (%s)" % _dump_errors(r_rich))
	_assert(r_rich.get("warnings", []).is_empty(),
		"rich fixture plan produces no warnings (%s)" % "; ".join(r_rich.get("warnings", [])))

	# The rich fixture is the one PM-2b/PM-3 lean on — assert it really carries
	# every section rather than trusting the file name.
	var verbs := {}
	for e in rich.get("earmarks", []):
		verbs[e.get("verb", "")] = true
	for v in PV.VERBS:
		_assert(verbs.has(v), "rich fixture exercises verb %s" % v)
	_assert(rich["deployment"]["reserves"].size() > 0, "rich fixture declares reserves")
	_assert(rich["deployment"]["embarkations"].size() > 0, "rich fixture declares an embarkation")
	_assert(rich["deployment"]["attachments"].size() > 0, "rich fixture declares an attachment")

	var cov: Dictionary = r_rich.get("coverage", {})
	_assert(int(cov.get("units_in_plan", 0)) == 17,
		"rich fixture references all 17 recon_stomps units (got %d)" % int(cov.get("units_in_plan", 0)))
	_assert(cov.get("unmatched", []).is_empty(), "rich fixture has no unmatched units")

func test_base_plan_valid() -> void:
	var r: Dictionary = PV.validate_plan(_base_plan())
	_assert(r.get("valid", false), "hand-built base plan is valid (%s)" % _dump_errors(r))

func test_envelope_corruptions() -> void:
	var p := _base_plan()
	p["format"] = "wh40k_ai_profile"
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "'format'"), "wrong format tag is rejected")

	p = _base_plan()
	p["version"] = 2
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "unsupported plan version"), "future plan version is rejected")

	p = _base_plan()
	p.erase("name")
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "'name'"), "missing name is rejected")

	r = PV.validate_plan(["not", "a", "dict"])
	_assert(not r.get("valid", true) and _has_error(r, "not a Dictionary"), "non-dictionary root is rejected")

func test_unknown_zone_and_layout() -> void:
	var p := _base_plan()
	p["keys"]["deployment_zone_id"] = "not_a_real_zone"
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "Unknown deployment_zone_id"), "unknown deployment_zone_id is rejected")

	p = _base_plan()
	p["keys"]["terrain_layout_id"] = "not_a_real_layout"
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "Unknown terrain_layout_id"), "unknown terrain_layout_id is rejected")

func test_bad_verb() -> void:
	var p := _base_plan()
	p["earmarks"] = [{"unit": "U_GRETCHIN_A", "verb": "FLANK_LEFT"}]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "Unknown earmark verb 'FLANK_LEFT'"), "unknown verb is rejected")

func test_trade_reserved() -> void:
	var p := _base_plan()
	p["earmarks"] = [{"unit": "U_GRETCHIN_A", "verb": "TRADE"}]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "reserved for v2"), "TRADE is rejected as 'reserved for v2'")

func test_hold_objective_requires_target() -> void:
	var p := _base_plan()
	p["earmarks"] = [{"unit": "U_GRETCHIN_A", "verb": "HOLD_OBJECTIVE"}]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "requires a 'target'"), "HOLD_OBJECTIVE without a target is rejected")

func test_placement_outside_player1_zone() -> void:
	var p := _base_plan()
	# Board centre — legal board space, but nowhere near the hammer_anvil P1 zone.
	p["deployment"]["placements"][0]["models_inches"] = [[22.0, 30.0], [23.0, 30.0]]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "no model inside the player-1"), "placement outside the P1 zone is rejected")

	p = _base_plan()
	p["deployment"]["placements"][0]["models_inches"] = [[50.0, 6.0]]
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "off the 44x60 board"), "placement off the board is rejected")

func test_placement_fails_seat2_transform() -> void:
	# res://deployment_zones/crucible_of_battle_new.json is the one shipped zone
	# file whose two polygons are NOT point reflections of each other (P1 is the
	# triangle (0,0)-(44,0)-(0,30); P2 starts at y=33, not y=30). That sliver is
	# exactly what the seat-2 transform check exists to catch.
	var p1 = PV.get_zone_polygon("crucible_of_battle_new", 1)
	var p2 = PV.get_zone_polygon("crucible_of_battle_new", 2)
	var probe := Vector2(4.0, 26.0)
	var mirrored = PV.mirror_inches(probe.x, probe.y)
	_assert(PV.point_in_zone(probe, p1), "probe (4,26) is inside crucible_of_battle_new P1")
	_assert(not PV.point_in_zone(mirrored, p2),
		"probe (4,26) mirrors to (%.1f,%.1f), outside crucible_of_battle_new P2" % [mirrored.x, mirrored.y])

	var p := _base_plan()
	p["keys"]["deployment_zone_id"] = "crucible_of_battle_new"
	p["deployment"]["placements"][0]["models_inches"] = [[4.0, 26.0]]
	p["deployment"]["placements"][1]["models_inches"] = [[4.0, 20.0]]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "seat-2 transform"),
		"placement that mirrors outside the P2 zone is rejected (%s)" % _dump_errors(r))
	_assert(not _has_error(r, "no model inside the player-1"),
		"...and the same placement is accepted in the P1 frame, so only the transform check fires")

func test_reserves_earmark_contradiction() -> void:
	# Earmarked RESERVE_UNTIL but absent from deployment.reserves.
	var p := _base_plan()
	p["earmarks"] = [{"unit": "U_STORMBOYZ_B", "verb": "RESERVE_UNTIL", "round": 2}]
	var r: Dictionary = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "not listed there"),
		"RESERVE_UNTIL earmark with no reserves entry is rejected")

	# Listed in reserves but with a different round.
	p = _base_plan()
	p["deployment"]["order"] = ["U_GRETCHIN_A"]
	p["deployment"]["placements"].remove_at(1)
	p["deployment"]["reserves"] = [{"unit": "U_STORMBOYZ_B", "arrival_round": 3}]
	p["earmarks"] = [{"unit": "U_STORMBOYZ_B", "verb": "RESERVE_UNTIL", "round": 2}]
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "says round 2 but deployment.reserves says round 3"),
		"RESERVE_UNTIL round disagreeing with deployment.reserves is rejected")

	# Agreement passes.
	p["earmarks"] = [{"unit": "U_STORMBOYZ_B", "verb": "RESERVE_UNTIL", "round": 3}]
	r = PV.validate_plan(p)
	_assert(r.get("valid", false), "RESERVE_UNTIL agreeing with deployment.reserves is valid (%s)" % _dump_errors(r))

	# A unit cannot be both placed and reserved.
	p = _base_plan()
	p["deployment"]["reserves"] = [{"unit": "U_GRETCHIN_A", "arrival_round": 2}]
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "both placed on the board and declared in reserves"),
		"a unit that is both placed and reserved is rejected")

	# Out-of-range arrival round.
	p = _base_plan()
	p["deployment"]["order"] = ["U_GRETCHIN_A"]
	p["deployment"]["placements"].remove_at(1)
	p["deployment"]["reserves"] = [{"unit": "U_STORMBOYZ_B", "arrival_round": 4}]
	r = PV.validate_plan(p)
	_assert(not r.get("valid", true) and _has_error(r, "expected 2-3"), "arrival_round outside 2-3 is rejected")

func test_reserves_caps() -> void:
	var army := _tiny_army()
	var p := _base_plan()
	p["deployment"]["order"] = []
	p["deployment"]["placements"] = []
	p["earmarks"] = []
	p["deployment"]["reserves"] = [
		{"unit": "U_A", "arrival_round": 2},
		{"unit": "U_B", "arrival_round": 2},
	]
	var r: Dictionary = PV.validate_plan(p, army)
	_assert(not r.get("valid", true) and _has_error(r, "50% points cap"), "reserves over the 50%% points cap are rejected")
	_assert(_has_error(r, "50% unit cap"), "reserves over the 50%% unit cap are rejected")

	# One of two units is exactly at both caps.
	p["deployment"]["reserves"] = [{"unit": "U_A", "arrival_round": 2}]
	r = PV.validate_plan(p, army)
	_assert(r.get("valid", false), "reserves exactly at the caps are accepted (%s)" % _dump_errors(r))

	# An attached character rides into reserves with its bodyguard and counts
	# toward the points cap (FormationsPhase._get_declared_reserves_points).
	var army2 := _tiny_army()
	army2["units"]["U_CHAR"] = {"meta": {"name": "Gamma", "points": 60}, "models": []}
	p["deployment"]["attachments"] = [{"character": "U_CHAR", "bodyguard": "U_A"}]
	r = PV.validate_plan(p, army2)
	_assert(not r.get("valid", true) and _has_error(r, "50% points cap"),
		"an attached character's points count toward the reserves points cap (%s)" % _dump_errors(r))

func test_coverage_against_real_army() -> void:
	var army := _load_army(RECON_STOMPS)
	var p := _base_plan()
	var r: Dictionary = PV.validate_plan(p, army)
	var cov: Dictionary = r.get("coverage", {})
	_assert(int(cov.get("units_in_army", 0)) == 17, "coverage sees 17 army units (got %d)" % int(cov.get("units_in_army", 0)))
	_assert(int(cov.get("units_in_plan", 0)) == 2, "coverage sees 2 plan units (got %d)" % int(cov.get("units_in_plan", 0)))
	_assert(str(cov.get("matched_by", {}).get("U_GRETCHIN_A", "")) == "id", "U_GRETCHIN_A matched by id")

	# A unit id that no longer exists, but whose name is unique in the army.
	p = _base_plan()
	p["deployment"]["order"] = ["U_RENAMED"]
	p["deployment"]["placements"] = [{
		"unit": "U_RENAMED",
		"unit_name": "Mek",
		"role_fallback": "character",
		"models_inches": [[10.0, 6.0]],
	}]
	p["earmarks"] = []
	r = PV.validate_plan(p, army)
	_assert(r.get("valid", false), "a plan referencing a missing unit is still VALID — matching degrades, it does not fail")
	_assert(_has_warning(r, "matched by unique name"), "missing unit with a unique name is matched by name (warning)")
	_assert(str(r["coverage"]["matched"].get("U_RENAMED", "")) == "U_MEK_A", "…and resolves to U_MEK_A")

	# No name, no role_fallback -> unmatched.
	p["deployment"]["placements"][0]["unit_name"] = ""
	p["deployment"]["placements"][0]["role_fallback"] = ""
	r = PV.validate_plan(p, army)
	_assert(r["coverage"]["unmatched"].has("U_RENAMED"), "a missing unit with no hints is reported unmatched")
	_assert(_has_warning(r, "will be ignored"), "…with a warning that the entry is ignored")

func test_coverage_duplicate_names() -> void:
	# recon_stomps has 4x "Stormboyz" and 4x "Warbikers" — this is the case that
	# forced plans to key on army-file unit ids rather than unit names.
	var army := _load_army(RECON_STOMPS)
	var name_counts := {}
	for uid in army.get("units", {}).keys():
		var nm := str(army["units"][uid].get("meta", {}).get("name", ""))
		name_counts[nm] = int(name_counts.get(nm, 0)) + 1
	_assert(int(name_counts.get("Stormboyz", 0)) == 4, "recon_stomps really does carry 4 units named 'Stormboyz'")

	var p := _base_plan()
	p["deployment"]["order"] = ["U_GONE"]
	p["deployment"]["placements"] = [{
		"unit": "U_GONE",
		"unit_name": "Stormboyz",
		"role_fallback": "screen",
		"models_inches": [[10.0, 6.0]],
	}]
	p["earmarks"] = []
	var r: Dictionary = PV.validate_plan(p, army)
	_assert(_has_warning(r, "ambiguous"), "an ambiguous name refuses to name-match (warning)")
	_assert(str(r["coverage"]["matched_by"].get("U_GONE", "")) == "role_fallback", "…and degrades to role_fallback")
	_assert(not r["coverage"]["matched"].has("U_GONE"), "…binding no army unit at all")

	# Same reference without a role_fallback is simply unmatched.
	p["deployment"]["placements"][0]["role_fallback"] = ""
	r = PV.validate_plan(p, army)
	_assert(r["coverage"]["unmatched"].has("U_GONE"), "an ambiguous name with no role_fallback is unmatched")
