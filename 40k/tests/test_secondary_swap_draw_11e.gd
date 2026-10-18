extends SceneTree

# Regression: 1-for-1 secondary swaps must not deal a full 11e turn draw.
#
# At 11e the normal turn draw deals exactly 2 cards with no hand limit.
# replace_drawn_mission (1 CP, back-to-deck) and use_new_orders (discard+draw)
# previously drew the replacement via a plain turn draw — removing 1 card and
# dealing 2, so a turn-one replace left the player with THREE active
# secondaries. Both swaps must be net-neutral: hand size unchanged.
#
# Usage: godot --headless --path . -s tests/test_secondary_swap_draw_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize():
	await create_timer(0.2).timeout
	var mgr = root.get_node_or_null("SecondaryMissionManager")
	if mgr == null:
		print("FAIL: missing SecondaryMissionManager autoload")
		quit(1)
		return
	GameConstants.edition = 11

	print("\n=== test_secondary_swap_draw_11e ===\n")

	# --- Turn-one state: draw the normal 11e two cards -----------------------
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(1)
	var drawn = mgr.draw_missions_to_hand(1)
	_check("turn draw deals exactly 2 cards at 11e", drawn.size() == 2, str(drawn.size()))
	_check("hand is 2 after the turn draw",
		mgr.get_active_missions(1).size() == 2, str(mgr.get_active_missions(1).size()))

	# The deck is shuffled unseeded, so a replacement draw can hit a card whose
	# When Drawn condition discards it and draws again (e.g. no enemy MONSTER /
	# VEHICLE). Those extra cards leave the deck AND land in the discard pile,
	# so the deck/discard checks below compare the two deltas instead of a
	# fixed count (a fixed "-1" failed ~1 run in N on CI, 2026-10-17).
	var st: Dictionary = mgr._player_state["1"]

	# --- replace_drawn_mission is net-neutral --------------------------------
	var deck_before = mgr.get_deck_size(1)
	var discard_before: int = st["discard"].size()
	var res = mgr.replace_drawn_mission(1, 0)
	_check("replace succeeds", res.get("success", false), str(res))
	_check("replace draws exactly ONE card (hand stays 2)",
		mgr.get_active_missions(1).size() == 2, str(mgr.get_active_missions(1).size()))
	var when_drawn_discards: int = st["discard"].size() - discard_before
	_check("deck unchanged after replace (one out, one back in; when-drawn discards aside)",
		mgr.get_deck_size(1) == deck_before - when_drawn_discards,
		"%d -> %d, %d when-drawn discard(s)" % [deck_before, mgr.get_deck_size(1), when_drawn_discards])
	_check("the replaced card went back into the deck, not the discard pile",
		st["deck"].has(res.get("replaced_id", "")) and not st["discard"].has(res.get("replaced_id", "")), str(res))
	_check("replacement differs from the replaced card",
		res.get("drawn", "") != res.get("replaced", ""), str(res))

	# --- use_new_orders is net-neutral ----------------------------------------
	deck_before = mgr.get_deck_size(1)
	discard_before = st["discard"].size()
	var hand_before: Array = []
	for m in mgr.get_active_missions(1):
		hand_before.append(m.get("id", ""))
	var res2 = mgr.use_new_orders(1, 0)
	_check("New Orders succeeds", res2.get("success", false), str(res2))
	_check("New Orders draws exactly ONE card (hand stays 2)",
		mgr.get_active_missions(1).size() == 2, str(mgr.get_active_missions(1).size()))
	var discard_delta: int = st["discard"].size() - discard_before
	_check("deck shrinks by one after New Orders (discarded card does not return; when-drawn discards aside)",
		discard_delta >= 1 and mgr.get_deck_size(1) == deck_before - discard_delta,
		"%d -> %d, discard pile +%d" % [deck_before, mgr.get_deck_size(1), discard_delta])
	_check("the New Orders card is in the discard pile, not the deck",
		hand_before.size() > 0 and st["discard"].has(hand_before[0]) and not st["deck"].has(hand_before[0]),
		"hand_before=%s discard=%s" % [str(hand_before), str(st["discard"])])

	# --- exact-count draw helper ----------------------------------------------
	var one = mgr.draw_missions_to_hand(1, 1)
	_check("draw_missions_to_hand(player, 1) deals exactly one card",
		one.size() == 1 and mgr.get_active_missions(1).size() == 3,
		"drawn=%d active=%d" % [one.size(), mgr.get_active_missions(1).size()])

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
