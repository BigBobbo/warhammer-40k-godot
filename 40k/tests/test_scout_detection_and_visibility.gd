extends SceneTree

# Scout step legibility + detection fixes.
#
# Reported bug: "I had <unit> who are scouts in my list and deployed them, but
# I did not appear to get the option to make a scout move with them. The first
# interaction I have is showing what secondary I've drawn." Reproduced: when no
# unit is recognised as having Scouts, ScoutPhase auto-completes on enter with
# nothing but a phase header in the log, so the player is dropped straight onto
# the secondary-mission draw with no way to tell why.
#
# Covers:
#   (A) Scout distance parsing — the old regex "scout\s+(\d+)" could not match
#       the PLURAL name form ("Scouts 9\""), so every Scouts 7"/8"/9" unit
#       silently made a 6" scout move.
#   (B) The Issue #389 description fallback — it required the literal substring
#       "scouts x", which no real datasheet text contains, so a mis-tagged
#       ability (name "Core", description "Scouts 6\": ...") was never detected.
#   (C) get_scout_eligibility_report() — per-unit "why can't this Scout?".
#   (D) ScoutPhase pushes player-visible GameEventLog entries on enter, both
#       when Scout moves are available and when the step is skipped.
#
# Usage: godot --headless --path . -s tests/test_scout_detection_and_visibility.gd

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

func _model(mid: String, pos) -> Dictionary:
	return {"id": mid, "alive": true, "wounds": 1, "current_wounds": 1,
		"base_mm": 32, "base_type": "circular", "position": pos}

func _setup(gs) -> void:
	gs.state["board"]["deployment_zones"] = [
		{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 20, "y": 0}, {"x": 20, "y": 60}, {"x": 0, "y": 60}]},
		{"player": 2, "poly": [{"x": 24, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 60}, {"x": 24, "y": 60}]},
	]
	gs.state["units"] = {
		# Plural name with a non-6" distance — the (A) regression.
		"U_FAST": {"id": "U_FAST", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Outriders", "keywords": ["INFANTRY"],
				"abilities": [{"name": "Scouts 9\""}], "stats": {"move": 6}},
			"models": [_model("m0", {"x": 400, "y": 400})]},
		# Mis-tagged ability: the name is not "Scouts", the rule text is in the
		# description — the (B) regression.
		"U_MISTAG": {"id": "U_MISTAG", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Mistagged Scouts", "keywords": ["INFANTRY"],
				"abilities": [{"name": "Core", "description": "Scouts 8\": This unit can make a pre-battle move."}],
				"stats": {"move": 6}},
			"models": [_model("m0", {"x": 300, "y": 900})]},
		# Has Scouts but is still in reserves — reported as blocked, not silent.
		"U_RES": {"id": "U_RES", "owner": 1, "status": 7, "reserve_type": "deep_strike", "flags": {},
			"meta": {"name": "Reserved Scouts", "keywords": ["INFANTRY"],
				"abilities": [{"name": "Scouts 6\""}], "stats": {"move": 6}},
			"models": [_model("m0", null)]},
		# No Scouts at all — the reported army's situation.
		"U_PLAIN": {"id": "U_PLAIN", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Plain Infantry", "keywords": ["INFANTRY"],
				"abilities": [{"name": "Purity of Execution"}], "stats": {"move": 6}},
			"models": [_model("e0", {"x": 1400, "y": 400})]},
	}
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["phase"] = 4

func _log_texts(gel, since: int) -> String:
	var out := ""
	for i in range(since, gel.entries.size()):
		out += str(gel.entries[i].get("text", "")) + "\n"
	return out

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_scout_detection_and_visibility ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var gel = root.get_node_or_null("GameEventLog")
	if gs == null or pm == null or gel == null:
		_check("autoloads (GameState/PhaseManager/GameEventLog)", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_setup(gs)

	# ---- (A) plural Scout distance parsing ----
	print("-- (A) Scout distance parsing --")
	_check("\"Scouts 9\\\"\" parses as 9\" (was 6\")",
		gs._get_scout_distance_from_abilities([{"name": "Scouts 9\""}]) == 9.0,
		str(gs._get_scout_distance_from_abilities([{"name": "Scouts 9\""}])))
	_check("\"Scouts 8\\\"\" parses as 8\" (was 6\")",
		gs._get_scout_distance_from_abilities([{"name": "Scouts 8\""}]) == 8.0,
		str(gs._get_scout_distance_from_abilities([{"name": "Scouts 8\""}])))
	_check("singular \"Scout 9\\\"\" still parses as 9\"",
		gs._get_scout_distance_from_abilities([{"name": "Scout 9\""}]) == 9.0)
	_check("\"Scouts 6\\\"\" still parses as 6\"",
		gs._get_scout_distance_from_abilities([{"name": "Scouts 6\""}]) == 6.0)
	_check("bare \"Scouts\" falls back to the 6\" default",
		gs._get_scout_distance_from_abilities([{"name": "Scouts"}]) == 6.0)
	_check("a non-Scout ability yields 0.0",
		gs._get_scout_distance_from_abilities([{"name": "Purity of Execution"}]) == 0.0)
	_check("web-roster `parameter` field is read",
		gs._get_scout_distance_from_abilities([{"name": "Scouts 7\"", "type": "Core", "parameter": "7\""}]) == 7.0)
	_check("unit-level get_scout_distance sees the plural distance",
		gs.get_scout_distance("U_FAST") == 9.0, str(gs.get_scout_distance("U_FAST")))

	# ---- (B) mis-tagged ability detected via description ----
	print("\n-- (B) mis-tagged ability (Issue #389 fallback) --")
	_check("mis-tagged Scouts ability is detected", gs.unit_has_scout("U_MISTAG"))
	_check("mis-tagged Scouts distance comes from the description",
		gs.get_scout_distance("U_MISTAG") == 8.0, str(gs.get_scout_distance("U_MISTAG")))
	_check("flavour text mentioning scouts is NOT read as the ability",
		not gs._get_scout_distance_from_abilities([
			{"name": "Recon", "description": "The scouts range ahead of the army."}]) > 0.0)

	# ---- (C) eligibility report ----
	print("\n-- (C) get_scout_eligibility_report --")
	var r1 = gs.get_scout_eligibility_report(1)
	var eligible_ids := []
	for e in r1.get("eligible", []):
		eligible_ids.append(e.get("unit_id", ""))
	var blocked_ids := []
	for b in r1.get("blocked", []):
		blocked_ids.append(b.get("unit_id", ""))
	_check("P1 eligible lists both deployed Scout units",
		"U_FAST" in eligible_ids and "U_MISTAG" in eligible_ids, str(eligible_ids))
	_check("P1 blocked lists the reserved Scout unit with a reason",
		"U_RES" in blocked_ids and str(r1.get("blocked", [])).to_lower().contains("reserves"),
		str(r1.get("blocked", [])))
	var r2 = gs.get_scout_eligibility_report(2)
	_check("P2 (no Scouts ability anywhere) reports nothing eligible and nothing blocked",
		r2.get("eligible", []).is_empty() and r2.get("blocked", []).is_empty(), str(r2))

	# ---- (D) player-visible narration on phase enter ----
	print("\n-- (D) ScoutPhase narration --")
	var mark = gel.entries.size()
	pm.transition_to_phase(4)  # SCOUT
	var text = _log_texts(gel, mark)
	_check("log names the units P1 may Scout with",
		text.contains("Outriders") and text.contains("Player 1 may make Scout moves"), text)
	_check("log explains the blocked reserve Scout",
		text.contains("Reserved Scouts") and text.contains("cannot move"), text)
	_check("log states P2 has no unit with the Scouts ability",
		text.contains("Player 2: no unit in this army has the Scouts ability"), text)

	# Now the reported case: nobody has Scouts at all.
	print("\n-- (D2) skipped step is announced, not silent --")
	for uid in ["U_FAST", "U_MISTAG", "U_RES"]:
		gs.state["units"][uid]["meta"]["abilities"] = []
	gs.state["meta"]["active_player"] = 1
	var mark2 = gel.entries.size()
	pm.transition_to_phase(4)  # SCOUT — auto-completes
	var text2 = _log_texts(gel, mark2)
	_check("skip is spelled out in the player-visible log",
		text2.contains("No Scout moves are available"), text2)
	_check("skip log says why for each player",
		text2.contains("Player 1: no unit in this army has the Scouts ability")
		and text2.contains("Player 2: no unit in this army has the Scouts ability"), text2)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
