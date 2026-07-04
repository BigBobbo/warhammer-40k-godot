extends SceneTree

# 11e Force Disposition primary missions — source:
# 40k/data/40kdc/missionCards.json (official 11e launch dataset,
# @alpaca-software/40kdc-data 1.0.19, effective 2026-06-20).
#  - 5 dispositions; each player's card = own deck paired vs opponent's
#    disposition (25-card table, PrimaryMissionData11e).
#  - Command conditions score at end of your Command phase R1-4, switching
#    to end of turn in R5; EOT every turn; EOG once at game end.
#  - exclusive_group rules are OR tiers: only the highest applies.
#  - Caps: 45 primary total, 15 per turn.
#
# Usage: godot --headless --path . -s tests/test_primary_missions_11e.gd

var passed := 0
var failed := 0
var gs = null
var mgr = null

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

func _find_obj_by_zone(zone: String) -> String:
	for obj in gs.state.board.get("objectives", []):
		if obj.get("zone", "") == zone:
			return obj.get("id", "")
	return ""

func _reset_vp(_m) -> void:
	for pk in ["1", "2"]:
		gs.state.players[pk]["vp"] = 0
		gs.state.players[pk]["primary_vp"] = 0
	mgr._primary_vp_this_turn = {"1": 0, "2": 0}

func _clear_control() -> void:
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 0

## Compact signature of a rule dict for the 25-card table pin.
func _rule_sig(rule: Dictionary) -> String:
	var bits = [str(rule.get("when", "?")), str(rule.get("type", "?"))]
	if rule.has("min"):
		bits.append("min=%d" % int(rule["min"]))
	if rule.has("vp_per"):
		bits.append("per=%d" % int(rule["vp_per"]))
	if rule.has("vp"):
		bits.append("vp=%d" % int(rule["vp"]))
	if rule.has("rounds"):
		bits.append("r%d-%d" % [int(rule["rounds"][0]), int(rule["rounds"][1])])
	if rule.has("exclusive_group"):
		bits.append("x")
	return "|".join(PackedStringArray(bits))

# Official award table (40kdc missionCards.json) as rule signatures, in card
# rule order. A silent revert of any number/trigger/window breaks this pin.
const EXPECTED_AWARDS := {
	"battlefield_dominance": [
		"eot|hold_more|vp=2|r1-2",
		"command|per_objective|per=3|r2-5",
		"command|per_objective|per=2|r2-5",
	],
	"immovable_object": [
		"eot|hold_central|vp=3",
		"command|per_objective|per=5|r2-5",
	],
	"purge_and_secure": [
		"eot|destroyed_started_on_objective|vp=3|x",
		"command|per_objective|per=4|r2-5",
		"eot|hold_new|vp=3|r2-5",
	],
	"inescapable_dominion": [
		"eot|hold_min|min=3|vp=4",
		"command|hold_min|min=2|vp=5|r2-5",
		"command|hold_more|vp=4|r2-5",
		"eog|hold_enemy_home|vp=5",
	],
	"determined_acquisition": [
		"eot|per_new_objective|per=2",
		"command|per_objective|per=3|r2-5",
		"command|per_objective|per=3|r2-5",
	],
	"unstoppable_force": [
		"eot|destroyed_min|min=1|vp=3",
		"command|per_objective|per=4|r2-5",
		"eot|hold_new|vp=3|r2-5",
		"eog|hold_central|vp=5",
	],
	"meatgrinder": [
		"eot|destroyed_min|min=1|vp=3",
		"command|hold_min|min=1|vp=4|r2-5",
		"eot|killed_more_than_opponent_last_turn|vp=5|r2-5",
		"eot|hold_enemy_home|vp=5|r2-5",
	],
	"punishment": [
		"eot_any|condemned_left|vp=5",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_more|vp=5|r2-5",
		"eog|hold_enemy_home|vp=8",
	],
	"consecrate": [
		"eot|consecrated_count|vp=3|x",
		"eot|consecrated_count|vp=6|x",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_more|vp=4|r2-5",
		"eog|consecrated_enemy_home|vp=5",
	],
	"destroyers_wrath": [
		"eot|destroyed_min|min=1|vp=3",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_more|vp=6|r2-5",
		"eot|killed_more_than_opponent_last_turn|vp=4|r2-5",
	],
	"reconnaissance_sweep": [
		"eot|quarters|min=3|vp=3|x",
		"eot|quarters|min=4|vp=6|x",
		"eot|destroyed_per_unit|per=1",
		"command|hold_min|min=1|vp=3|r2-5",
	],
	"triangulation": [
		"command|hold_min|min=1|vp=4|r2-5",
		"eot|triangulated_count|vp=3|r2-5|x",
		"eot|triangulated_count|vp=6|r2-5|x",
		"eot|triangulated_count|vp=10|r2-5|x",
		"eog|hold_min|min=4|vp=10",
	],
	"gather_intel": [
		"eot|hold_central|vp=6|r1-1",
		"command|hold_min|min=1|vp=4|r2-5",
		"eot|intel_tokens_placed|per=7|r2-5",
		"eog|operation_markers_min|min=3|vp=5",
		"eog|intel_token_on_enemy_home|vp=5",
	],
	"search_and_scour": [
		"eot|hold_central|vp=3",
		"eot|destroyed_in_terrain_area|vp=2",
		"command|per_objective|per=4|r2-5",
		"eog|no_enemy_wholly_in_my_dz|vp=5",
	],
	"surveil_the_foe": [
		"eot|action|vp=4",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_more|vp=4|r2-5",
		"eot|no_enemy_markers|vp=5|r2-5",
	],
	"secure_asset": [
		"eot|hold_min|min=1|vp=4",
		"eot|destroyed_near_central|vp=2",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_min|min=3|vp=4|r2-5",
	],
	"vital_link": [
		"eot|central_operation_markers|vp=2",
		"command|hold_min|min=1|vp=4|r2-5",
		"command|hold_central|vp=4|r2-5",
		"eog|hold_enemy_home|vp=10",
	],
	"vanguard_operation": [
		"eot|vanguard_terrain_area|vp=4",
		"eot|destroyed_min|min=1|vp=2",
		"command|hold_min|min=1|vp=4|r2-5",
		"eog|hold_enemy_home|vp=10",
	],
	"sabotage": [
		"eot|sabotage_per_objective|per=3",
		"command|hold_min|min=1|vp=4|r2-5",
	],
	"extract_relic": [
		"eot|sensor_sweep_vp|vp=4",
		"eot|destroyed_started_on_objective|vp=3",
		"eot|relic_final_marker|vp=4",
		"command|hold_min|min=1|vp=4|r2-5",
		"eog|relic_final_marker|vp=5",
	],
	"death_trap": [
		"eot|trapped_score|per=2",
		"eot|destroyed_in_terrain_area|vp=3",
		"command|hold_min|min=1|vp=4|r2-5",
	],
	"delaying_action": [
		"eot|destroyed_per_unit|per=2",
		"command|hold_min|min=1|vp=4|r2-5",
		"eot|hold_central_plus_nml|vp=3|r2-5",
	],
	"outmanoeuvre": [
		"eot|hold_enemy_home|vp=10",
		"eot|per_objective|per=4|r1-1",
		"command|per_objective|per=5|r2-3",
		"eot|per_objective|per=6|r4-5",
	],
	"smoke_and_mirrors": [
		"eot|decoyed_score|per=2",
		"command|hold_min|min=1|vp=4|r2-5",
		"eog|decoyed_total_eog|min=4|vp=10",
	],
	"locate_and_deny": [
		"eot|destroyed_started_on_objective|vp=4",
		"eot|relic_final_marker|vp=4",
		"command|hold_min|min=1|vp=4|r2-5",
		"eog|relic_final_marker|vp=5",
	],
}

# Cards that keep an approximate rule (engine stand-ins) — everything else
# is an exact translation of the official awards and must NOT be flagged.
const EXPECTED_APPROX := [
	"purge_and_secure", "gather_intel", "search_and_scour", "surveil_the_foe",
	"secure_asset", "vital_link", "vanguard_operation", "extract_relic",
	"death_trap", "locate_and_deny",
]

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_primary_missions_11e ===\n")
	mgr = root.get_node_or_null("MissionManager")
	gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)

	print("-- pairing table --")
	var cards = PrimaryMissionData11e.get_all_cards()
	_check("25 primary mission cards", cards.size() == 25, str(cards.size()))
	var ids = {}
	var complete = true
	for own in PrimaryMissionData11e.DISPOSITIONS:
		for opp in PrimaryMissionData11e.DISPOSITIONS:
			var card = PrimaryMissionData11e.get_card(own, opp)
			if card.is_empty():
				complete = false
			else:
				ids[card["id"]] = true
	_check("all 25 disposition pairings resolve", complete)
	_check("all card ids unique", ids.size() == 25, str(ids.size()))
	_check("TH vs TH is Battlefield Dominance",
		PrimaryMissionData11e.get_card("take_and_hold", "take_and_hold").get("id", "") == "battlefield_dominance")
	_check("DI vs PF is Delaying Action",
		PrimaryMissionData11e.get_card("disruption", "purge_the_foe").get("id", "") == "delaying_action")

	print("\n-- official award table pin (40kdc missionCards.json) --")
	var table_ok = true
	for cid in EXPECTED_AWARDS:
		var card = PrimaryMissionData11e.get_card_by_id(cid)
		var sigs = []
		for rule in card.get("rules", []):
			sigs.append(_rule_sig(rule))
		if sigs != EXPECTED_AWARDS[cid]:
			table_ok = false
			print("    MISMATCH %s:\n      got      %s\n      expected %s" % [
				cid, str(sigs), str(EXPECTED_AWARDS[cid])])
	_check("all 25 cards carry the official award rows", table_ok)
	var flags_ok = true
	for card in cards:
		var cid2 = str(card.get("id", ""))
		var flagged = card.get("approximate", false)
		if flagged != (cid2 in EXPECTED_APPROX):
			flags_ok = false
			print("    FLAG MISMATCH %s: approximate=%s" % [cid2, str(flagged)])
	_check("approximate flags only on cards with engine stand-ins", flags_ok)

	print("\n-- disposition initialization --")
	GameConstants.edition = 11
	mgr.initialize_dispositions_11e("take_and_hold", "disruption")
	_check("P1 (TH vs DI) plays Determined Acquisition",
		mgr.get_primary_mission_for_player(1).get("id", "") == "determined_acquisition")
	_check("P2 (DI vs TH) plays Death Trap",
		mgr.get_primary_mission_for_player(2).get("id", "") == "death_trap")
	_check("dispositions stored in meta",
		gs.state.meta.get("dispositions_11e", {}).get("1", "") == "take_and_hold")
	mgr.initialize_dispositions_11e("bogus", "priority_assets")
	_check("unknown disposition falls back to take_and_hold",
		mgr.get_primary_mission_for_player(1).get("id", "") == "inescapable_dominion")

	print("\n-- command scoring: Battlefield Dominance --")
	mgr.initialize_dispositions_11e("take_and_hold", "take_and_hold")
	var home1 = _find_obj_by_zone("player1")
	var home2 = _find_obj_by_zone("player2")
	var nml = _find_obj_by_zone("no_mans_land")
	_check("board has home + NML objectives", home1 != "" and home2 != "" and nml != "")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	_clear_control()
	mgr.objective_control_state[home1] = 1
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	# R2 command: 3x2 per objective + home-held bonus 2x1 non-home = 8
	# (objective majority moved to EOT per the official trigger)
	_check("R2 command: 3x2 objectives + 2x1 home-held bonus = 8 VP",
		int(gs.state.players["1"]["primary_vp"]) == 8, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	# R1-2 EOT: objective majority (2 held vs 0) pays 2 more
	_check("R2 EOT adds the majority award (total 10)",
		int(gs.state.players["1"]["primary_vp"]) == 10, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	mgr.objective_control_state[home1] = 0
	mgr.score_primary_objectives()
	# Without the home objective the +2/objective bonus row is off: 3x1 = 3
	_check("home objective lost: bonus row off (3 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 3, str(gs.state.players["1"]["primary_vp"]))
	mgr.objective_control_state[home1] = 1

	print("\n-- caps: 15/turn and 45 total --")
	_reset_vp(null)
	mgr._award_primary_vp_11e(1, 12, "test", "command")
	mgr._award_primary_vp_11e(1, 9, "test", "command")
	_check("second award clipped to the 15/turn window",
		int(gs.state.players["1"]["primary_vp"]) == 15, str(gs.state.players["1"]["primary_vp"]))
	mgr.on_turn_start_11e(1)
	_check("turn window resets on turn start", int(mgr._primary_vp_this_turn["1"]) == 0)
	gs.state.players["1"]["primary_vp"] = 44
	mgr._award_primary_vp_11e(1, 10, "test", "command")
	_check("45 total cap respected", int(gs.state.players["1"]["primary_vp"]) == 45,
		str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Round 5: command scoring switches to end of turn --")
	mgr.initialize_dispositions_11e("take_and_hold", "take_and_hold")
	gs.state.meta["battle_round"] = 5
	_reset_vp(null)
	_clear_control()
	mgr.objective_control_state[home1] = 1
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	_check("R5 Command phase awards nothing", int(gs.state.players["1"]["primary_vp"]) == 0,
		str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	# R5 EOT: majority window is R1-2 (skipped); command rows 3x2 + 2x1 = 8
	_check("R5 EOT scores the command conditions (3x2 + 2x1 = 8 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 8, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- EOT kill conditions: Delaying Action --")
	mgr.initialize_dispositions_11e("disruption", "purge_the_foe")
	gs.state.meta["battle_round"] = 3
	_reset_vp(null)
	mgr.kills_per_round["3"] = {"1": 2, "2": 0}
	mgr._kills_this_round = {"1": 0, "2": 0}
	_clear_control()
	mgr.score_primary_eot_11e(1)
	_check("EOT: 2 VP per destroyed unit x2 = 4 VP",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))
	mgr.kills_per_round.clear()

	print("\n-- hold_new: Unstoppable Force (per-objective command + EOT seize) --")
	mgr.initialize_dispositions_11e("purge_the_foe", "take_and_hold")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	mgr._kills_this_round = {"1": 0, "2": 0}
	mgr.kills_per_round.clear()
	_clear_control()
	mgr._control_at_turn_start["1"] = []
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	_check("command: 4 VP per non-home objective x1 = 4 VP",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	_check("EOT adds 3 VP for the newly captured objective (total 7)",
		int(gs.state.players["1"]["primary_vp"]) == 7, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	mgr._control_at_turn_start["1"] = [nml]
	mgr.score_primary_objectives()
	mgr.score_primary_eot_11e(1)
	_check("already-held objective: per-objective hold only (4 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- per_new_objective: Determined Acquisition --")
	mgr.initialize_dispositions_11e("take_and_hold", "disruption")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	_clear_control()
	mgr._control_at_turn_start["1"] = []
	mgr.objective_control_state[home1] = 1
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	# NML objective is not in enemy territory, so the +3 zone row stays off
	_check("command: 3 VP per controlled objective x2 = 6 VP",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	_check("EOT: 2 VP per objective newly controlled this turn x2 (total 10)",
		int(gs.state.players["1"]["primary_vp"]) == 10, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	mgr._control_at_turn_start["1"] = [home1, nml]
	mgr.score_primary_objectives()
	mgr.score_primary_eot_11e(1)
	_check("no new captures: command row only (6 VP)",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- EOG conditions: enemy home (Inescapable Dominion) --")
	mgr.initialize_dispositions_11e("take_and_hold", "priority_assets")
	gs.state.meta["battle_round"] = 5
	_reset_vp(null)
	_clear_control()
	mgr.objective_control_state[home2] = 1
	mgr.score_primary_eog_11e()
	_check("EOG: 5 VP for holding the enemy home objective",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eog_11e()
	_check("EOG scoring is idempotent",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Outmanoeuvre escalation (official triggers: EOT R1, command R2-3, EOT R4+) --")
	mgr.initialize_dispositions_11e("disruption", "disruption")
	_clear_control()
	mgr.objective_control_state[nml] = 1
	gs.state.meta["battle_round"] = 1
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	mgr.score_primary_objectives()
	_check("R1 command: nothing (the R1 rate pays at EOT)",
		int(gs.state.players["1"]["primary_vp"]) == 0, str(gs.state.players["1"]["primary_vp"]))
	mgr.score_primary_eot_11e(1)
	_check("R1 EOT: 4 VP per non-home objective",
		int(gs.state.players["1"]["primary_vp"]) == 4, str(gs.state.players["1"]["primary_vp"]))
	gs.state.meta["battle_round"] = 2
	_reset_vp(null)
	mgr.score_primary_objectives()
	_check("R2 command: 5 VP per non-home objective",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))
	gs.state.meta["battle_round"] = 4
	_reset_vp(null)
	mgr.score_primary_objectives()
	mgr.score_primary_eot_11e(1)
	_check("R4: rate escalates to 6 VP at EOT (command row closed)",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))
	gs.state.meta["battle_round"] = 5
	_reset_vp(null)
	mgr.score_primary_objectives()
	mgr.score_primary_eot_11e(1)
	_check("R5 EOT still pays the 6 VP rate",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- objective designations (Home / Expansion / Central) --")
	_check("home objectives designated", mgr.get_objective_designation(home1) == "home"
		and mgr.get_objective_designation(home2) == "home")
	var centrals = mgr.get_objective_ids_by_designation("central")
	var expansions = mgr.get_objective_ids_by_designation("expansion")
	_check("exactly one central objective", centrals.size() == 1, str(centrals))
	_check("remaining NML objectives are expansions", expansions.size() == 2, str(expansions))

	print("\n-- marker mechanics: Triangulation tiers 3/6/10 (exclusive) --")
	mgr.initialize_dispositions_11e("reconnaissance", "purge_the_foe")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	mgr._kills_this_round = {"1": 0, "2": 0}
	mgr.kills_per_round.clear()
	_clear_control()
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_eot_11e(1)
	var st1t = mgr._primary_state_11e["1"]
	_check("Triangulate auto-marks the controlled objective",
		st1t["triangulated"] == [nml], str(st1t["triangulated"]))
	_check("1 triangulated objective scores 3 VP at EOT",
		int(gs.state.players["1"]["primary_vp"]) == 3, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	st1t["triangulated"] = [nml, home1, home2]
	mgr.score_primary_eot_11e(1)
	# 3 triangulated -> only the 10 VP tier of the exclusive group applies
	# (NOT 3+6+10); nml is already marked so the auto-pick adds nothing.
	_check("3+ triangulated: only the best tier pays (10 VP, not 19)",
		int(gs.state.players["1"]["primary_vp"]) == 10, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	mgr._eog_primary_scored = false
	for obj_id in mgr.objective_control_state:
		mgr.objective_control_state[obj_id] = 1
	mgr.score_primary_eog_11e()
	_check("EOG: holding 4+ objectives pays 10 VP",
		int(gs.state.players["1"]["primary_vp"]) == 10, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- exclusive tiers: Consecrate 3/6 --")
	mgr.initialize_dispositions_11e("purge_the_foe", "reconnaissance")
	gs.state.meta["battle_round"] = 3
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	mgr._kills_this_round = {"1": 0, "2": 0}
	mgr.kills_per_round.clear()
	_clear_control()
	var st1c = mgr._primary_state_11e["1"]
	st1c["consecrated"] = ["obj_a"]
	mgr.score_primary_eot_11e(1)
	_check("1-2 consecrated objectives pay the 3 VP tier",
		int(gs.state.players["1"]["primary_vp"]) == 3, str(gs.state.players["1"]["primary_vp"]))
	_reset_vp(null)
	st1c["consecrated"] = ["obj_a", "obj_b", "obj_c"]
	mgr.score_primary_eot_11e(1)
	_check("3+ consecrated: only the 6 VP tier pays (not 9)",
		int(gs.state.players["1"]["primary_vp"]) == 6, str(gs.state.players["1"]["primary_vp"]))

	print("\n-- Death Trap: trapped_score pays per terrain trapped THIS TURN --")
	mgr.initialize_dispositions_11e("disruption", "take_and_hold")
	var st1d = mgr._primary_state_11e["1"]
	st1d["trapped"] = ["T_OLD", "T_NEW"]
	st1d["trapped_this_turn"] = ["T_NEW"]
	var dt_rule = {"type": "trapped_score", "vp_per": 2, "objective_bonus": 3}
	_check("only this turn's trap pays (2 VP)",
		int(mgr._evaluate_primary_rule_11e(1, dt_rule, 2)) == 2,
		str(mgr._evaluate_primary_rule_11e(1, dt_rule, 2)))
	st1d.erase("trapped_this_turn")
	_check("legacy saves without the per-turn key fall back to all traps (4 VP)",
		int(mgr._evaluate_primary_rule_11e(1, dt_rule, 2)) == 4,
		str(mgr._evaluate_primary_rule_11e(1, dt_rule, 2)))

	print("\n-- Gather Intel: EOG operation-marker awards --")
	mgr.initialize_dispositions_11e("reconnaissance", "reconnaissance")
	var st1g = mgr._primary_state_11e["1"]
	var om_rule = {"type": "operation_markers_min", "min": 3, "vp": 5}
	var eh_rule = {"type": "intel_token_on_enemy_home", "vp": 5}
	st1g["intel_tokens"] = [nml]
	_check("fewer than 3 markers score 0",
		int(mgr._evaluate_primary_rule_11e(1, om_rule, 5)) == 0)
	_check("no token near the opponent's home scores 0",
		int(mgr._evaluate_primary_rule_11e(1, eh_rule, 5)) == 0)
	st1g["intel_tokens"] = [nml, home1, home2]
	_check("3+ markers on the battlefield pay 5 VP at EOG",
		int(mgr._evaluate_primary_rule_11e(1, om_rule, 5)) == 5)
	_check("a marker at the opponent's home objective pays 5 VP at EOG",
		int(mgr._evaluate_primary_rule_11e(1, eh_rule, 5)) == 5)

	print("\n-- Smoke and Mirrors: decoyed objectives keep paying after a scrub --")
	mgr.initialize_dispositions_11e("disruption", "reconnaissance")
	var st1s = mgr._primary_state_11e["1"]
	st1s["decoyed_ever"] = [nml]
	st1s["decoyed"] = []  # marker scrubbed — the Decoyed tag never clears
	var sm_rule = {"type": "decoyed_score", "vp_per": 2, "enemy_territory_bonus": 2}
	var sm_expected = 2 + (2 if mgr._objective_in_enemy_territory_11e(nml, 1) else 0)
	_check("decoyed_score reads the never-clearing tag (decoyed_ever)",
		int(mgr._evaluate_primary_rule_11e(1, sm_rule, 2)) == sm_expected,
		"%s vs %d" % [str(mgr._evaluate_primary_rule_11e(1, sm_rule, 2)), sm_expected])

	print("\n-- marker mechanics: Sabotage per-objective + territory bonus --")
	mgr.initialize_dispositions_11e("priority_assets", "priority_assets")
	gs.state.meta["battle_round"] = 2
	gs.state.meta["active_player"] = 1
	_reset_vp(null)
	_clear_control()
	mgr.objective_control_state[nml] = 1
	var central_id = mgr.get_objective_ids_by_designation("central")[0]
	mgr.objective_control_state[central_id] = 1
	mgr.score_primary_eot_11e(1)
	# Compute the expectation over the unique controlled non-home objectives
	var sab_ids = [nml]
	if central_id != nml:
		sab_ids.append(central_id)
	var expected_sab = 0
	for oid in sab_ids:
		expected_sab += 3
		if mgr._objective_in_enemy_territory_11e(oid, 1):
			expected_sab += 2
	_check("Sabotage: 3 VP per non-home + 2 territory/central bonus",
		int(gs.state.players["1"]["primary_vp"]) == expected_sab,
		"%s vs %d" % [gs.state.players["1"]["primary_vp"], expected_sab])

	print("\n-- marker mechanics: Vital Link operation markers --")
	mgr.initialize_dispositions_11e("priority_assets", "purge_the_foe")
	_reset_vp(null)
	_clear_control()
	mgr.objective_control_state[central_id] = 1
	mgr.score_primary_eot_11e(1)
	# turn 1: marker placed (1), EOT central 2 + 1 marker = 3
	var vl1 = int(gs.state.players["1"]["primary_vp"])
	mgr.score_primary_eot_11e(1)
	var vl2 = int(gs.state.players["1"]["primary_vp"]) - vl1
	_check("Vital Link escalates: 2nd sweep scores 1 more than the 1st",
		vl2 == vl1 + 1, "first %d then %d" % [vl1, vl2])

	print("\n-- marker mechanics: Punishment condemned-left --")
	mgr.initialize_dispositions_11e("purge_the_foe", "disruption")
	_reset_vp(null)
	gs.state["units"]["U_COND"] = {"id": "U_COND", "owner": 2,
		"meta": {"name": "Runner", "keywords": [], "stats": {"objective_control": 1}},
		"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular",
			"position": {"x": gs.state.board.objectives[0].position.x, "y": gs.state.board.objectives[0].position.y}}]}
	mgr.on_turn_start_11e(1)
	_check("enemy unit on an objective is auto-condemned",
		"U_COND" in mgr._primary_state_11e["1"]["condemned"],
		str(mgr._primary_state_11e["1"]["condemned"]))
	gs.state.units["U_COND"]["models"][0]["alive"] = false
	mgr.score_primary_eot_11e(1)
	_check("condemned unit leaving the battlefield scores 5 VP",
		int(gs.state.players["1"]["primary_vp"]) >= 5, str(gs.state.players["1"]["primary_vp"]))
	gs.state.units.erase("U_COND")

	print("\n-- 10e regression: dispatch unchanged --")
	GameConstants.edition = 10
	gs.state.meta["battle_round"] = 2
	_reset_vp(null)
	mgr.initialize_mission("take_and_hold")
	_clear_control()
	mgr.objective_control_state[nml] = 1
	mgr.score_primary_objectives()
	_check("10e Take and Hold still scores 5 VP/objective",
		int(gs.state.players["1"]["primary_vp"]) == 5, str(gs.state.players["1"]["primary_vp"]))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
