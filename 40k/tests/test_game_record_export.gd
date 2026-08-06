extends SceneTree

# M1: `wh40k_ai_game_record` schema tests.
#
# The record is what turns a benchmark game from "a final score" into a
# training example: the AI's own candidate scoring joined to the outcome it
# produced, plus enough provenance to know what environment produced it.
#
# These exercise AIGameRecord.build/validate — deliberately STATIC and fully
# parameterised so the schema can be tested without standing up a 6-minute
# game. The live end-to-end path (a real benchmark writing a real record,
# on both the completed and the stalled exit) is covered by running
# run_ai_benchmark.sh and indexing the result with tools/ai_lab/build_index.py.
#
# Run via:
#   godot --headless --path 40k --script tests/test_game_record_export.gd

# The schema lives in its own dependency-free script precisely so this test
# can compile it. Preloading the AIBenchmarkRunner autoload instead would
# drag in GameState/MissionManager, which do not resolve under --script.
const RECORD := preload("res://scripts/AIGameRecord.gd")

var _passed := 0
var _failed := 0


func _initialize():
	await create_timer(0.2).timeout
	_run_tests()


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s%s" % [label, ("  — " + detail) if detail != "" else ""])
		_failed += 1


func _sample_provenance() -> Dictionary:
	return {
		"git_sha": "deadbee",
		"engine": "4.4.1.stable",
		"fixture": "mirror_orks_postdeploy",
		"fixture_sha256": "abc123",
		"p1_profile": {"path": "", "sha256": "", "inline": {}},
		"p2_profile": {"path": "p2.json", "sha256": "def456",
			"inline": {"parameters": {"MACRO_OBJECTIVE_WEIGHT": 1.5}}},
		"difficulty": {"1": 2, "2": 2},
		"seed": 4242,
		"time_scale": 6.0,
		"arm": "candidate",
	}


func _sample_outcome() -> Dictionary:
	return {
		"status": "completed", "note": "", "winner": 1,
		"vp": {"player1": {"total": 66, "primary": 39, "secondary": 27},
			"player2": {"total": 59, "primary": 32, "secondary": 27}},
		"vp_diff_p2_minus_p1": -7, "battle_round": 5,
		"actions_taken": 762, "wall_seconds": 414.8, "time_scale": 6.0,
	}


func _sample_batches() -> Array:
	# Shaped exactly like AIPlayer._all_decision_records entries
	# (autoloads/AIPlayer.gd:2043-2050).
	return [{
		"round": 1, "phase_name": "movement", "player": 1,
		"records": [{
			"decision_type": "movement", "unit_id": "U_BOYZ_A", "unit_name": "Boyz",
			"candidates": [
				{"description": "advance to obj_1", "score": 12.5,
					"score_breakdown": {"objective": 10.0, "threat": 2.5}},
				{"description": "hold position", "score": 9.0,
					"score_breakdown": {"objective": 9.0}},
			],
			"chosen_index": 0,
			"parameters_used": {"MACRO_OBJECTIVE_WEIGHT": 1.5},
			"difficulty": "Hard",
			"context": {"phase": 2, "round": 1},
		}],
		"thinking_steps": ["Boyz heads for obj_1"],
		"actions": [{"type": "BEGIN_NORMAL_MOVE", "description": "Boyz moves"}],
	}]


func _run_tests():
	print("\n=== M1: wh40k_ai_game_record export tests ===\n")

	var prov = _sample_provenance()
	var outcome = _sample_outcome()
	var batches = _sample_batches()
	var vp_events = [
		{"round": 2, "phase": 9, "player": 1, "points": 5, "reason": "Primary", "wall_seconds": 61.0},
		{"round": 3, "phase": 9, "player": 2, "points": 3, "reason": "Behind Enemy Lines", "wall_seconds": 140.2},
	]
	var action_log = [{"phase": 2, "action_type": "BEGIN_NORMAL_MOVE",
		"description": "Boyz moves", "player": 1}]

	var rec = RECORD.build("20260806_g1", prov, outcome, vp_events,
		batches, action_log, 1, 0)

	# --- 1. schema identity -------------------------------------------------
	_check("schema tag is wh40k_ai_game_record", rec.get("schema") == "wh40k_ai_game_record",
		str(rec.get("schema")))
	_check("schema_version is 1", int(rec.get("schema_version", -1)) == 1)
	_check("game_id preserved", rec.get("game_id") == "20260806_g1")

	# --- 2. provenance is complete -----------------------------------------
	# Non-negotiable: the corrupt-fixture episode invalidated every historical
	# baseline precisely because nothing recorded WHICH fixture was played.
	var p = rec.get("provenance", {})
	var required = ["git_sha", "engine", "fixture", "fixture_sha256",
		"p1_profile", "p2_profile", "difficulty", "seed", "time_scale"]
	var missing = []
	for key in required:
		if not p.has(key):
			missing.append(key)
	_check("provenance carries all required keys", missing.is_empty(),
		"missing: %s" % str(missing))
	_check("fixture sha256 recorded", p.get("fixture_sha256", "") == "abc123")
	_check("profile is inlined, not just referenced by path",
		p.get("p2_profile", {}).get("inline", {}).get("parameters", {}).has("MACRO_OBJECTIVE_WEIGHT"))

	# --- 3. outcome passthrough --------------------------------------------
	_check("outcome preserved verbatim", rec.get("outcome", {}).get("vp_diff_p2_minus_p1", 999) == -7)
	_check("outcome keeps the vp split",
		rec.get("outcome", {}).get("vp", {}).get("player1", {}).get("primary", 0) == 39)

	# --- 4. decision batch passthrough -------------------------------------
	var decisions = rec.get("decisions", [])
	_check("one decision batch retained", decisions.size() == 1, "got %d" % decisions.size())
	var first_record = decisions[0].get("records", [])[0] if decisions.size() > 0 else {}
	_check("candidate scoring survives", first_record.get("candidates", []).size() == 2)
	_check("score_breakdown survives",
		first_record.get("candidates", [{}])[0].get("score_breakdown", {}).has("objective"))
	_check("parameters_used survives",
		first_record.get("parameters_used", {}).has("MACRO_OBJECTIVE_WEIGHT"))
	_check("chosen_index survives", int(first_record.get("chosen_index", -1)) == 0)

	# --- 5. vp_events + action_log -----------------------------------------
	_check("vp_events preserved", rec.get("vp_events", []).size() == 2)
	_check("vp_event carries a reason",
		rec.get("vp_events", [{}])[1].get("reason", "") == "Behind Enemy Lines")
	_check("action_log preserved", rec.get("action_log", []).size() == 1)

	# --- 6. data-quality counters ------------------------------------------
	_check("decision_batches_total recorded", int(rec.get("decision_batches_total", -1)) == 1)
	_check("decision_batches_dropped recorded", int(rec.get("decision_batches_dropped", -1)) == 0)

	# A game whose ring buffer dropped batches is a BIASED sample (the tail of
	# the game survives, the opening does not). The counter must survive so
	# build_index.py's data_quality view can flag it.
	var lossy = RECORD.build("g2", prov, outcome, vp_events, batches, action_log, 700, 200)
	_check("dropped-batch count is surfaced, not silently swallowed",
		int(lossy.get("decision_batches_dropped", -1)) == 200)

	# --- 7. stalled game still yields a valid record ------------------------
	# The pre-existing export hook fired on game-complete and so never ran for
	# a stalled game — the most informative kind. The record is written from
	# _write_and_quit instead, which covers every exit path.
	var stalled_outcome = _sample_outcome()
	stalled_outcome["status"] = "stalled"
	stalled_outcome["note"] = "no progress for 90s at 3|8|478"
	var stalled = RECORD.build("g3", prov, stalled_outcome, [], [], [], 0, 0)
	_check("stalled game produces a schema-valid record",
		stalled.get("schema") == "wh40k_ai_game_record"
		and stalled.get("outcome", {}).get("status", "") == "stalled")
	_check("empty decisions is representable (not an error)",
		stalled.get("decisions", null) != null and stalled.get("decisions", [""]).size() == 0)

	# --- 8. JSON round-trip -------------------------------------------------
	# The record is written to disk as JSON, so anything that does not survive
	# stringify -> parse is not really in the dataset.
	var text = JSON.stringify(rec)
	var reparsed = JSON.parse_string(text)
	_check("record round-trips through JSON", reparsed is Dictionary)
	if reparsed is Dictionary:
		_check("round-trip keeps the candidate scores",
			reparsed.get("decisions", [{}])[0].get("records", [{}])[0]
				.get("candidates", [{}])[0].get("score", 0.0) == 12.5)
		_check("round-trip keeps provenance hashes",
			reparsed.get("provenance", {}).get("fixture_sha256", "") == "abc123")
		_check("record is compact (not pretty-printed)", not text.contains("\n"),
			"a pretty-printed record roughly doubles season size")

	# --- 9. structural validation ------------------------------------------
	# A malformed record must be caught at write time, not discovered as a
	# confusing gap three thousand games into a season.
	_check("a well-formed record validates clean", RECORD.validate(rec).is_empty(),
		str(RECORD.validate(rec)))
	_check("a stalled record still validates clean", RECORD.validate(stalled).is_empty(),
		str(RECORD.validate(stalled)))
	
	var no_prov = rec.duplicate(true)
	no_prov["provenance"].erase("fixture_sha256")
	_check("validation catches missing fixture_sha256",
		RECORD.validate(no_prov).size() == 1)
	
	var wrong_schema = rec.duplicate(true)
	wrong_schema["schema"] = "something_else"
	_check("validation catches a foreign schema tag",
		not RECORD.validate(wrong_schema).is_empty())
	
	var not_array = rec.duplicate(true)
	not_array["decisions"] = {}
	_check("validation catches decisions that is not an Array",
		not RECORD.validate(not_array).is_empty())
	
	_check("validation rejects an empty dict outright",
		RECORD.validate({}).size() >= 4)
	
	print("\n=== Results: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
