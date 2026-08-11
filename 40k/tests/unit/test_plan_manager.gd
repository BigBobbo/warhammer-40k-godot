extends SceneTree

# PM-1 — PlanManager tests (storage, listing, matching)
#
# Covers: fixtures load by explicit path and are NEVER listed; save -> load
# round-trip; an invalid plan is refused; exact match beats the layout
# wildcard; a mismatched army matches nothing; a fabricated meta.game_config
# snapshot matches by army file name; a fixture-style snapshot with NO
# game_config matches through the faction fallback; and the `_P<player>` mirror
# re-keying that every same-army-both-seats game produces.
#
# The test is hermetic: any pre-existing user://ai_plans/*.json are moved aside
# before it runs and moved back afterwards, so a developer's own plans neither
# perturb the matching assertions nor get destroyed.
#
# Run with: godot --headless --path . -s tests/unit/test_plan_manager.gd

const PM = preload("res://scripts/PlanManager.gd")

const FIXTURE_MINIMAL := "res://tests/fixtures/ai_plans/fixture_minimal_valid.json"
const FIXTURE_RICH := "res://tests/fixtures/ai_plans/fixture_recon_stomps_rich.json"
const ORK_PREDEPLOY := "res://tests/saves/mirror_orks_2000_predeploy.w40ksave"

const BACKUP_DIR := "user://ai_plans_pm1_backup/"

var _pass_count: int = 0
var _fail_count: int = 0
var _moved_aside: Array[String] = []

func _init():
	# Autoloads are NOT in the tree yet when a `-s` script's _init() runs — the
	# StateSerializer cross-check below needs them. Defer the way
	# tests/test_new_game_reaches_rolloff.gd does.
	create_timer(0.2).timeout.connect(_run)

func _run():
	print("\n=== PlanManager (PM-1) Tests ===\n")
	_hermetic_begin()
	_run_tests()
	_hermetic_end()
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

# ---------------------------------------------------------------------------
# Hermetic user://ai_plans/
# ---------------------------------------------------------------------------

func _plan_files_in(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return out

func _hermetic_begin() -> void:
	PM.ensure_user_plans_dir()
	DirAccess.make_dir_absolute(BACKUP_DIR)
	for f in _plan_files_in(PM.USER_PLANS_DIR):
		var err = DirAccess.rename_absolute(PM.USER_PLANS_DIR + f, BACKUP_DIR + f)
		if err == OK:
			_moved_aside.append(f)
	if not _moved_aside.is_empty():
		print("  (moved %d pre-existing user plan(s) aside for the duration)" % _moved_aside.size())

func _hermetic_end() -> void:
	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)
	for f in _moved_aside:
		DirAccess.rename_absolute(BACKUP_DIR + f, PM.USER_PLANS_DIR + f)
	DirAccess.remove_absolute(BACKUP_DIR)
	if not _moved_aside.is_empty():
		print("  (restored %d pre-existing user plan(s))" % _moved_aside.size())

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _make_plan(plan_name: String, layout_id: String) -> Dictionary:
	# Placements sit inside the crucible_of_battle player-1 triangle
	# ((0,0)-(44,30)-(44,0)); (28,4) mirrors to (16,56), inside the P2 triangle.
	return {
		"format": "wh40k_ai_plan",
		"version": 1,
		"name": plan_name,
		"description": "PM-1 test plan",
		"author": "test",
		"keys": {
			"army_file": "recon_stomps",
			"detachment_hint": "Speedwaaagh!",
			"deployment_zone_id": "crucible_of_battle",
			"terrain_layout_id": layout_id,
			"mission_id": "",
		},
		"deployment": {
			"order": ["U_GRETCHIN_A"],
			"placements": [{
				"unit": "U_GRETCHIN_A",
				"unit_name": "Gretchin",
				"role_fallback": "screen",
				"models_inches": [[28.0, 4.0], [29.5, 4.0], [31.0, 4.0]],
			}],
			"reserves": [],
			"embarkations": [],
			"attachments": [],
		},
		"earmarks": [],
		"profile_fragment": {"parameters": {}, "rules": []},
	}

func _make_unit(unit_id: String, owner: int, unit_name: String, points: int) -> Dictionary:
	return {
		"id": unit_id,
		"owner": owner,
		"meta": {"name": unit_name, "points": points},
		"models": [],
	}

func _make_snapshot(game_config, faction_name: String = "Orks", detachment: String = "Speedwaaagh!") -> Dictionary:
	var meta := {"deployment_type": "crucible_of_battle"}
	if game_config != null:
		meta["game_config"] = game_config
	return {
		"meta": meta,
		"board": {"terrain_layout": "take_and_hold_mirror_1"},
		"factions": {
			"1": {"name": faction_name, "detachment": detachment, "points": 2000},
			"2": {"name": faction_name, "detachment": detachment, "points": 2000},
		},
		# Same army both seats: ArmyListManager re-keys player 2's copy with a
		# deterministic _P2 suffix (ArmyListManager.gd:333-346).
		"units": {
			"U_GRETCHIN_A": _make_unit("U_GRETCHIN_A", 1, "Gretchin", 45),
			"U_STOMPA_A": _make_unit("U_STOMPA_A", 1, "Stompa", 600),
			"U_GRETCHIN_A_P2": _make_unit("U_GRETCHIN_A_P2", 2, "Gretchin", 45),
			"U_STOMPA_A_P2": _make_unit("U_STOMPA_A_P2", 2, "Stompa", 600),
		},
	}

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	test_slugify()
	test_fixtures_load_by_path_and_are_not_listed()
	test_save_roundtrip_and_refusal()
	test_delete_only_user_plans()
	test_unit_id_resolution()
	test_match_by_game_config()
	test_match_mismatched_army()
	test_exact_beats_wildcard()
	test_faction_fallback_matches_fixture_style_snapshot()
	test_real_predeploy_fixture_has_no_game_config()
	test_missing_identity_returns_empty()

func test_slugify() -> void:
	_assert(PM.slugify("Recon Stomps — Hammer & Anvil") == "recon_stomps_hammer_anvil",
		"slugify collapses punctuation runs (got '%s')" % PM.slugify("Recon Stomps — Hammer & Anvil"))
	_assert(PM.slugify("  ...  ") == "plan", "slugify never produces an empty file name")
	_assert(PM.slugify("A1 b2") == "a1_b2", "slugify keeps alphanumerics and lowercases")

func test_fixtures_load_by_path_and_are_not_listed() -> void:
	var minimal := PM.load_plan_file(FIXTURE_MINIMAL)
	var rich := PM.load_plan_file(FIXTURE_RICH)
	_assert(not minimal.is_empty() and str(minimal.get("format", "")) == "wh40k_ai_plan",
		"minimal fixture loads by explicit path")
	_assert(not rich.is_empty(), "rich fixture loads by explicit path")

	# res://data/ai_plans/ does not exist yet — listing must survive that.
	var entries := PM.list_plans()
	_assert(entries.is_empty(), "search path is empty to start with (got %d entries)" % entries.size())

	# Now put one plan on the search path and confirm ONLY it is listed.
	PM.save_plan(_make_plan("PM1 Listing Probe", ""))
	entries = PM.list_plans()
	_assert(entries.size() == 1, "exactly the one saved plan is listed (got %d)" % entries.size())
	var listed_fixture := false
	for e in entries:
		if str(e["path"]).find("tests/fixtures") != -1:
			listed_fixture = true
	_assert(not listed_fixture, "test fixtures are never listed by the search path")
	_assert(str(entries[0]["source"]) == "user", "a saved plan is tagged source 'user'")
	_assert(bool(entries[0]["metadata"]["valid"]), "listing carries the PlanValidator badge")
	_assert(str(entries[0]["metadata"]["army_file"]) == "recon_stomps", "listing carries keys.army_file for the browser row")

	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)

func test_save_roundtrip_and_refusal() -> void:
	var plan := _make_plan("PM1 Round Trip", "take_and_hold_mirror_1")
	var saved: Dictionary = PM.save_plan(plan)
	_assert(bool(saved["success"]), "valid plan saves (%s)" % "; ".join(saved.get("errors", [])))
	_assert(str(saved["path"]) == "user://ai_plans/pm1_round_trip.json",
		"saved to the slugified path (got '%s')" % saved["path"])
	_assert(FileAccess.file_exists(str(saved["path"])), "plan file exists on disk")

	var reloaded := PM.load_plan("PM1 Round Trip")
	_assert(str(reloaded.get("name", "")) == "PM1 Round Trip", "plan reloads by name")
	_assert(str(reloaded.get("keys", {}).get("deployment_zone_id", "")) == "crucible_of_battle",
		"round-tripped plan keeps its keys")
	_assert(reloaded["deployment"]["placements"][0]["models_inches"].size() == 3,
		"round-tripped plan keeps all model positions")

	# An invalid plan must be refused — the format's whole promise is that a
	# plan cannot describe an illegal game state.
	var bad := _make_plan("PM1 Invalid", "")
	bad["earmarks"] = [{"unit": "U_GRETCHIN_A", "verb": "TRADE"}]
	var refused: Dictionary = PM.save_plan(bad)
	_assert(not bool(refused["success"]), "invalid plan is refused")
	_assert("; ".join(refused["errors"]).find("reserved for v2") != -1, "…with the validator's reason")
	_assert(not FileAccess.file_exists("user://ai_plans/pm1_invalid.json"), "…and no file is written")

func test_delete_only_user_plans() -> void:
	var saved: Dictionary = PM.save_plan(_make_plan("PM1 Deletable", ""))
	_assert(PM.delete_plan(str(saved["path"])), "a user:// plan deletes")
	_assert(not FileAccess.file_exists(str(saved["path"])), "…and the file is gone")
	_assert(not PM.delete_plan("res://data/ai_plans/anything.json"),
		"a shipped res:// plan is refused for deletion (res files cannot be removed in an export)")
	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)

func test_unit_id_resolution() -> void:
	var snap := _make_snapshot(null)
	var units: Dictionary = snap["units"]
	_assert(PM.resolve_unit_id("U_GRETCHIN_A", 1, units) == "U_GRETCHIN_A", "seat 1 resolves the plain army-file id")
	_assert(PM.resolve_unit_id("U_GRETCHIN_A", 2, units) == "U_GRETCHIN_A_P2",
		"seat 2 resolves through the mirror re-key suffix")
	_assert(PM.resolve_unit_id("U_NOT_THERE", 1, units) == "", "an absent unit resolves to empty")

	var p1 := PM.units_for_player(snap, 1)
	var p2 := PM.units_for_player(snap, 2)
	_assert(p1.size() == 2 and p1.has("U_GRETCHIN_A"), "units_for_player(1) returns the player's units by army-file id")
	_assert(p2.size() == 2 and p2.has("U_GRETCHIN_A") and not p2.has("U_GRETCHIN_A_P2"),
		"units_for_player(2) strips the _P2 suffix so a plan lines up at either seat")

func test_match_by_game_config() -> void:
	PM.save_plan(_make_plan("PM1 Exact", "take_and_hold_mirror_1"))
	var snap := _make_snapshot({"player1_army": "recon_stomps", "player2_army": "recon_stomps"})

	var result := PM.find_plan_match_for(1, snap)
	_assert(not result.is_empty(), "a fabricated meta.game_config snapshot matches")
	_assert(str(result.get("name", "")) == "PM1 Exact", "…the expected plan")
	_assert(int(result.get("rank", -1)) == PM.MATCH_EXACT, "…at exact rank")
	_assert(str(result.get("reason", "")).find("game_config") != -1,
		"…via the game_config identity path (reason: %s)" % result.get("reason", ""))

	# Matching is seat-agnostic: the same plan applies at seat 2, and the
	# coordinate transform is consumption's job (PM-2a), not matching's.
	var result2 := PM.find_plan_match_for(2, snap)
	_assert(not result2.is_empty() and str(result2.get("name", "")) == "PM1 Exact",
		"the same plan matches at seat 2 (matching is seat-agnostic)")

	_assert(not PM.find_plan_for(1, snap).is_empty(), "find_plan_for returns the plan dictionary")

func test_match_mismatched_army() -> void:
	var snap := _make_snapshot({"player1_army": "custodes_lions", "player2_army": "custodes_lions"})
	var result := PM.find_plan_match_for(1, snap)
	_assert(result.is_empty(), "a different army in game_config matches nothing")
	_assert(PM.find_plan_for(1, snap).is_empty(), "find_plan_for returns {} for a mismatched army")

	# Wrong zone.
	var snap_zone := _make_snapshot({"player1_army": "recon_stomps"})
	snap_zone["meta"]["deployment_type"] = "hammer_anvil"
	_assert(PM.find_plan_match_for(1, snap_zone).is_empty(), "a different deployment zone matches nothing")

	# Wrong layout, with no wildcard plan available.
	var snap_layout := _make_snapshot({"player1_army": "recon_stomps"})
	snap_layout["board"]["terrain_layout"] = "take_and_hold_mirror_2"
	_assert(PM.find_plan_match_for(1, snap_layout).is_empty(),
		"a layout-keyed plan does not match a different layout")

func test_exact_beats_wildcard() -> void:
	# "AAA" sorts before "PM1 Exact", so if rank were ignored the wildcard would
	# win the alphabetical tie-break. It must not.
	PM.save_plan(_make_plan("AAA Wildcard", ""))
	var snap := _make_snapshot({"player1_army": "recon_stomps"})
	var result := PM.find_plan_match_for(1, snap)
	_assert(str(result.get("name", "")) == "PM1 Exact",
		"exact (army+zone+layout) beats the layout wildcard even when the wildcard sorts first (got '%s')" % result.get("name", ""))

	# With the exact plan gone, the wildcard is used.
	PM.delete_plan("user://ai_plans/pm1_exact.json")
	result = PM.find_plan_match_for(1, snap)
	_assert(str(result.get("name", "")) == "AAA Wildcard", "the wildcard plan is used when no exact plan exists")
	_assert(int(result.get("rank", -1)) == PM.MATCH_LAYOUT_WILDCARD, "…at wildcard rank")

	# Deterministic tie-break between two wildcards: alphabetical by name.
	PM.save_plan(_make_plan("AAB Wildcard", ""))
	result = PM.find_plan_match_for(1, snap)
	_assert(str(result.get("name", "")) == "AAA Wildcard", "ties break alphabetically by plan name")

	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)

func test_faction_fallback_matches_fixture_style_snapshot() -> void:
	PM.save_plan(_make_plan("PM1 Fallback", "take_and_hold_mirror_1"))
	# No game_config at all — exactly what the shipped predeploy fixtures look
	# like. Identity has to come from state.factions + meta.deployment_type.
	var snap := _make_snapshot(null)
	var result := PM.find_plan_match_for(1, snap)
	_assert(not result.is_empty(), "a fixture-style snapshot with no game_config still matches")
	_assert(str(result.get("reason", "")).find("faction fallback") != -1,
		"…through the faction fallback (reason: %s)" % result.get("reason", ""))

	# A different faction must not match.
	var other := _make_snapshot(null, "Adeptus Custodes", "Lions of the Emperor")
	_assert(PM.find_plan_match_for(1, other).is_empty(), "a different live faction matches nothing")

	# Same faction, different detachment must not match either.
	var other_det := _make_snapshot(null, "Orks", "Bully Boyz")
	_assert(PM.find_plan_match_for(1, other_det).is_empty(), "a different detachment matches nothing")

	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)

func test_real_predeploy_fixture_has_no_game_config() -> void:
	# The fabricated snapshots above are only worth anything if they are
	# faithful. Decode the real fixture and read its identity the same way
	# PlanManager does.
	var main_loop = Engine.get_main_loop()
	var serializer = (main_loop as SceneTree).root.get_node_or_null("StateSerializer") if main_loop is SceneTree else null
	if serializer == null:
		_assert(false, "StateSerializer autoload is reachable for the fixture cross-check")
		return
	var file = FileAccess.open(ORK_PREDEPLOY, FileAccess.READ)
	if file == null:
		_assert(false, "predeploy fixture %s is readable" % ORK_PREDEPLOY)
		return
	var text := file.get_as_text()
	file.close()
	var state: Dictionary = serializer.deserialize_game_state(text)
	_assert(not state.is_empty(), "mirror_orks_2000_predeploy deserializes")

	var identity := PM.resolve_game_identity(1, state)
	_assert(str(identity["identity_source"]) == "factions",
		"the real predeploy fixture has NO meta.game_config — identity falls back to factions")
	_assert(str(identity["zone_id"]) == "crucible_of_battle",
		"…its deployment zone really is crucible_of_battle (got '%s')" % identity["zone_id"])
	_assert(str(identity["layout_id"]) == "take_and_hold_mirror_1",
		"…its terrain layout really is take_and_hold_mirror_1 (got '%s')" % identity["layout_id"])
	_assert(str(identity["faction_name"]) == "Orks" and str(identity["detachment"]) == "Speedwaaagh!",
		"…and its player-1 faction is Orks / Speedwaaagh! (got '%s' / '%s')" % [identity["faction_name"], identity["detachment"]])

	# A plan keyed to that real identity matches the real fixture state.
	PM.save_plan(_make_plan("PM1 Real Fixture", "take_and_hold_mirror_1"))
	var result := PM.find_plan_match_for(1, state)
	_assert(str(result.get("name", "")) == "PM1 Real Fixture",
		"a plan keyed to the fixture's real identity matches the real fixture state")
	# And it matches at seat 2, whose units carry the _P2 mirror suffix.
	var result2 := PM.find_plan_match_for(2, state)
	_assert(str(result2.get("name", "")) == "PM1 Real Fixture", "…and at seat 2 of the mirror match")

	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)

func test_missing_identity_returns_empty() -> void:
	PM.save_plan(_make_plan("PM1 Orphan", ""))
	var snap := _make_snapshot(null)
	snap["meta"].erase("deployment_type")
	_assert(PM.find_plan_match_for(1, snap).is_empty(), "a snapshot with no deployment_type matches nothing")

	var snap2 := _make_snapshot(null)
	snap2.erase("factions")
	_assert(PM.find_plan_match_for(1, snap2).is_empty(),
		"a snapshot with no game_config and no factions matches nothing")

	for f in _plan_files_in(PM.USER_PLANS_DIR):
		DirAccess.remove_absolute(PM.USER_PLANS_DIR + f)
