extends SceneTree

# SecondaryMissionManager.draw_missions_to_hand must TERMINATE when every card
# left in the deck is a "when drawn in the first battle round, shuffle it back
# and draw another" card. It used to spin forever (25M "shuffled ... back into
# deck" lines in 5 minutes — the test_e2e_workflow hang that surfaced once the
# GUT harness ran 11e). A shuffle-back card mixed with a drawable card must
# still yield the drawable card, and the same shuffle-back card is drawable
# from round 2.
#
# Usage: godot --headless --path . -s tests/test_secondary_draw_shuffle_back_terminates.gd

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

func _prime(mgr, player: int, deck: Array) -> void:
	var st: Dictionary = mgr._player_state[str(player)]
	st["initialized"] = true
	st["deck"] = deck.duplicate()
	st["active"] = []
	st["discard"] = []

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_secondary_draw_shuffle_back_terminates ===\n")
	GameConstants.edition = 11
	_check("edition is 11", GameConstants.edition == 11)
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	var gs = root.get_node_or_null("GameState")
	_check("autoloads present", mgr != null and gs != null)
	if mgr == null or gs == null:
		_finish()
		return
	var sb_id := "behind_enemy_lines"
	var sb = SecondaryMissionData.get_mission_by_id(sb_id)
	_check("%s is a round-1 shuffle-back card" % sb_id,
		SecondaryMissionData.get_when_drawn(sb).get("condition", "") == "first_battle_round")

	gs.state["meta"]["battle_round"] = 1
	_prime(mgr, 1, [sb_id])
	var drawn: Array = mgr.draw_missions_to_hand(1)
	_check("round 1, deck = [shuffle-back only]: draw returns (no hang) with nothing drawn",
		drawn.is_empty(), str(drawn))
	_check("the shuffle-back card stays in the deck", mgr._player_state["1"]["deck"] == [sb_id],
		str(mgr._player_state["1"]["deck"]))

	var other_id := "assassination"
	if SecondaryMissionData.get_mission_by_id(other_id).is_empty():
		other_id = SecondaryMissionData.get_mission_ids_for_deck_11e()[0]
	_prime(mgr, 1, [sb_id, other_id])
	drawn = mgr.draw_missions_to_hand(1)
	var drawn_ids: Array = []
	for m in drawn:
		drawn_ids.append(m.get("id", ""))
	_check("round 1, deck = [shuffle-back, %s]: the drawable card is drawn" % other_id,
		drawn_ids == [other_id], str(drawn_ids))
	_check("…and the shuffle-back card is back in the deck", mgr._player_state["1"]["deck"] == [sb_id],
		str(mgr._player_state["1"]["deck"]))

	gs.state["meta"]["battle_round"] = 2
	_prime(mgr, 1, [sb_id])
	drawn = mgr.draw_missions_to_hand(1)
	drawn_ids = []
	for m in drawn:
		drawn_ids.append(m.get("id", ""))
	_check("round 2: the same card is drawn normally", drawn_ids == [sb_id], str(drawn_ids))
	_finish()

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
