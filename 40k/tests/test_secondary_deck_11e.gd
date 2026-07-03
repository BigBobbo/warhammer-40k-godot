extends SceneTree

# 11e (GDM 2026) secondary mission deck — source:
# docs/rules/11th_edition_missions_gdm2026.md.
#  - 18-card deck: four returning fixed-eligible cards + returning tacticals
#    + the new GDM cards; retired 10e cards are absent.
#  - Tactical: draw 2/turn with NO hand limit (10e: fill to 2).
#  - Fixed: only Assassination / A Grievous Blow / Bring it Down /
#    Engage on All Fronts may be taken.
#  - Caps: 45 VP secondary total, 15 VP per turn (10e: 40 total).
#
# Usage: godot --headless --path . -s tests/test_secondary_deck_11e.gd

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

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_secondary_deck_11e ===\n")
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	var gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)

	print("-- deck composition --")
	var deck = SecondaryMissionData.get_mission_ids_for_deck_11e()
	_check("11e tactical deck has 18 cards", deck.size() == 18, str(deck))
	for nid in ["a_grievous_blow", "forward_position", "burden_of_trust", "centre_ground", "beacon", "outflank", "plunder"]:
		_check("new card %s present with data" % nid,
			nid in deck and not SecondaryMissionData.get_mission_by_id(nid).is_empty())
	for gone in ["area_denial", "extend_battle_lines", "storm_hostile_objective", "cull_the_horde", "marked_for_death", "establish_locus", "deploy_teleport_homer"]:
		_check("retired 10e card %s absent" % gone, not gone in deck)
	_check("approximate cards are flagged",
		SecondaryMissionData.get_mission_by_id("beacon").get("approximate", false)
		and SecondaryMissionData.get_mission_by_id("forward_position").get("approximate", false))

	print("\n-- draw rules: 2/turn, no hand limit (11e) --")
	GameConstants.edition = 11
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var st = mgr._player_state["1"]
	_check("deck built with 18 cards at e11", st["deck"].size() == 18, str(st["deck"].size()))
	mgr.draw_missions_to_hand(1)
	_check("first draw: 2 cards in hand", st["active"].size() == 2, str(st["active"].size()))
	mgr.draw_missions_to_hand(1)
	_check("second draw: hand grows to 4 (no hand limit)", st["active"].size() == 4, str(st["active"].size()))
	GameConstants.edition = 10
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var st10 = mgr._player_state["1"]
	mgr.draw_missions_to_hand(1)
	mgr.draw_missions_to_hand(1)
	_check("10e unchanged: hand capped at 2", st10["active"].size() == 2, str(st10["active"].size()))

	print("\n-- fixed eligibility (11e) --")
	GameConstants.edition = 11
	mgr.initialize_for_game()
	var bad = mgr.setup_fixed_missions(1, ["no_prisoners", "assassination"])
	_check("11e fixed: non-eligible card rejected", not bad.get("success", true), str(bad))
	var good = mgr.setup_fixed_missions(1, ["assassination", "a_grievous_blow"])
	_check("11e fixed: two fixed-eligible cards accepted", good.get("success", false), str(good))

	print("\n-- caps: 15/turn and 45 total (11e) --")
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var award1 = mgr._award_secondary_vp(1, 14, "test_a")
	var award2 = mgr._award_secondary_vp(1, 5, "test_b")
	_check("14 VP awarded freely", award1 == 14, str(award1))
	_check("next 5 VP clipped to 1 by the 15/turn cap", award2 == 1, str(award2))
	mgr.on_turn_start(1)
	var s1 = mgr._player_state["1"]
	_check("turn window resets on turn start", int(s1.get("secondary_vp_this_turn", -1)) == 0)
	# Pump to the 45 total cap in 15-per-turn windows.
	for _t in range(2):
		mgr._award_secondary_vp(1, 15, "test_c")
		mgr.on_turn_start(1)
	# Windows so far: 15 (turn 1) + 15 + 15 = 45 — the total cap is reached.
	var final_award = mgr._award_secondary_vp(1, 15, "test_d")
	_check("45 total cap: nothing awarded beyond it", final_award == 0, str(final_award))
	mgr.on_turn_start(1)
	var over_cap = mgr._award_secondary_vp(1, 5, "test_e")
	_check("fresh turn window does not bypass the total cap", over_cap == 0, str(over_cap))
	_check("secondary_vp settled at exactly 45", int(s1["secondary_vp"]) == 45, str(s1["secondary_vp"]))

	print("\n-- new condition checkers --")
	gs.state["units"]["U_HV"] = {"id": "U_HV", "owner": 2,
		"meta": {"name": "BigThing", "keywords": ["VEHICLE"], "points": 180, "stats": {}},
		"models": [{"id": "m1", "alive": false, "wounds": 12, "current_wounds": 0,
			"base_mm": 100, "base_type": "circular", "position": {"x": 500, "y": 500}}]}
	mgr._units_destroyed_this_turn.clear()
	mgr.check_and_report_unit_destroyed("U_HV")
	_check("high-value kill detected (180 pts / 12W model)",
		mgr._check_high_value_unit_destroyed(1, {"min_points": 100, "min_wounds": 10}))
	_check("high-value threshold respected",
		not mgr._check_high_value_unit_destroyed(1, {"min_points": 500, "min_wounds": 20}))
	gs.state.units.erase("U_HV")

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
