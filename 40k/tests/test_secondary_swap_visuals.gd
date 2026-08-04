extends SceneTree

# Regression: taking a secondary card out of a player's hand must take that
# card's board markers with it.
#
# Reported bug: the player paid 1 CP to replace A Tempting Target during their
# Command phase. The card left their hand, but "TEMPTING TARGET (P1)" stayed
# burned onto the objective for the rest of the game — so the board kept
# claiming they still held the card. voluntary_discard and the scoring discard
# already cleared these markers; replace_drawn_mission and use_new_orders did
# not.
#
# This test asserts the marker state through SecondaryMissionManager's own
# tracking (headless has no ObjectiveVisual / TokenVisual to inspect), plus the
# per-unit flags that drive the Marked for Death and Beacon badges.
#
# Usage: godot --headless --path . -s tests/test_secondary_swap_visuals.gd

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

	print("\n=== test_secondary_swap_visuals ===\n")

	_test_replace_clears_tempting_target(mgr)
	_test_new_orders_clears_beacon(mgr)
	_test_new_orders_clears_marked_for_death(mgr)
	_test_other_holder_keeps_marker(mgr)

	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Put exactly `ids` in the player's hand, bypassing the deck/when-drawn flow.
## The stacked ids are pulled OUT of the deck: a swap draws a replacement, and
## leaving the deck's own copy of (say) a_tempting_target in there makes the
## replacement randomly redraw the same card and flake the assertions.
func _stack_hand(mgr, player: int, ids: Array) -> void:
	mgr.initialize_for_game()
	mgr.setup_tactical_deck(player)
	var state = mgr._player_state[str(player)]
	state["active"] = []
	for mid in ids:
		state["active"].append(mgr._create_active_mission(SecondaryMissionData.get_mission_by_id(mid)))
		state["deck"].erase(mid)

func _test_replace_clears_tempting_target(mgr) -> void:
	print("-- replace_drawn_mission clears the Tempting Target marker --")
	var vis = _register_objective_visual("obj_nml_1")
	_stack_hand(mgr, 1, ["a_tempting_target", "centre_ground"])
	mgr._player_state["1"]["active"][0]["mission_data"]["tempting_target_id"] = "obj_nml_1"
	mgr._mark_tempting_target_visual("obj_nml_1", 1)
	_check("board marker is up before the swap", _marker_visible(vis),
		str(vis.tempting_target_label.text if vis.tempting_target_label else "<no label>"))

	var res = mgr.replace_drawn_mission(1, 0)
	_check("replace succeeds", res.get("success", false), str(res))
	_check("A Tempting Target left the hand",
		not _hand_has(mgr, 1, "a_tempting_target"), str(_hand_ids(mgr, 1)))
	_check("no active card still claims obj_nml_1 as its tempting target",
		not _any_tempting_target_on(mgr, "obj_nml_1"), str(_hand_ids(mgr, 1)))
	# THE reported bug: the label used to stay up for the rest of the game, so
	# the board kept telling the player they still held the card.
	_check("board marker came down with the card", not _marker_visible(vis),
		"label still visible on obj_nml_1")

func _test_new_orders_clears_beacon(mgr) -> void:
	print("-- use_new_orders clears the Beacon unit badge --")
	var unit_id = _first_unit_id()
	if unit_id == "":
		print("  SKIP: no units in GameState to designate")
		return
	_stack_hand(mgr, 1, ["beacon", "centre_ground"])
	mgr._player_state["1"]["active"][0]["mission_data"]["beacon_unit_id"] = unit_id
	mgr._mark_beacon_visual(unit_id)
	_check("beacon flag set before the swap",
		_gs().state["units"][unit_id].get("flags", {}).get("beacon", false) == true)

	var res = mgr.use_new_orders(1, 0)
	_check("New Orders succeeds", res.get("success", false), str(res))
	_check("Beacon left the hand", not _hand_has(mgr, 1, "beacon"), str(_hand_ids(mgr, 1)))
	_check("beacon flag cleared from the designated unit",
		not _gs().state["units"][unit_id].get("flags", {}).has("beacon"),
		str(_gs().state["units"][unit_id].get("flags", {})))

func _test_new_orders_clears_marked_for_death(mgr) -> void:
	print("-- replace_drawn_mission clears Marked for Death unit flags --")
	var unit_id = _first_unit_id()
	if unit_id == "":
		print("  SKIP: no units in GameState to mark")
		return
	_stack_hand(mgr, 1, ["marked_for_death", "centre_ground"])
	mgr._player_state["1"]["active"][0]["mission_data"] = {
		"alpha_targets": [unit_id], "gamma_target": "",
	}
	mgr._mark_mfd_target_visuals([unit_id], "", 1)
	_check("marked_for_death flag set before the swap",
		_gs().state["units"][unit_id].get("flags", {}).get("marked_for_death", "") == "alpha")

	var res = mgr.replace_drawn_mission(1, 0)
	_check("replace succeeds", res.get("success", false), str(res))
	_check("marked_for_death flag cleared from the alpha target",
		not _gs().state["units"][unit_id].get("flags", {}).has("marked_for_death"),
		str(_gs().state["units"][unit_id].get("flags", {})))

func _test_other_holder_keeps_marker(mgr) -> void:
	print("-- clearing one player's card must not blank the opponent's marker --")
	# Both players can hold A Tempting Target aimed at the same objective, but an
	# objective carries ONE label. P1 swapping theirs away must leave P2's live.
	var vis = _register_objective_visual("obj_nml_1")
	_stack_hand(mgr, 1, ["a_tempting_target", "centre_ground"])
	mgr.setup_tactical_deck(2)
	mgr._player_state["2"]["active"] = [
		mgr._create_active_mission(SecondaryMissionData.get_mission_by_id("a_tempting_target"))
	]
	mgr._player_state["1"]["active"][0]["mission_data"]["tempting_target_id"] = "obj_nml_1"
	mgr._player_state["2"]["active"][0]["mission_data"]["tempting_target_id"] = "obj_nml_1"
	mgr._mark_tempting_target_visual("obj_nml_1", 1)

	var res = mgr.replace_drawn_mission(1, 0)
	_check("replace succeeds", res.get("success", false), str(res))
	_check("P1's card is gone", not _hand_has(mgr, 1, "a_tempting_target"), str(_hand_ids(mgr, 1)))
	_check("P2 still holds a card pointing at obj_nml_1",
		_any_tempting_target_on(mgr, "obj_nml_1"), str(_hand_ids(mgr, 2)))
	_check("marker stays up and re-points at P2", _marker_visible(vis),
		str(vis.tempting_target_label.text if vis.tempting_target_label else "<no label>"))
	_check("marker now names P2",
		vis.tempting_target_label != null and vis.tempting_target_label.text == "TEMPTING TARGET (P2)",
		str(vis.tempting_target_label.text if vis.tempting_target_label else "<no label>"))

# ---------------------------------------------------------------------------

func _hand_ids(mgr, player: int) -> Array:
	var ids = []
	for m in mgr.get_active_missions(player):
		ids.append(m.get("id", "?"))
	return ids

func _hand_has(mgr, player: int, mission_id: String) -> bool:
	return mission_id in _hand_ids(mgr, player)

## Mirrors the guard in _clear_tempting_target_visual: is ANY player's active
## card still aimed at this objective?
func _any_tempting_target_on(mgr, objective_id: String) -> bool:
	for player_key in mgr._player_state:
		for m in mgr._player_state[player_key].get("active", []):
			if m.get("id", "") != "a_tempting_target":
				continue
			if str(m.get("mission_data", {}).get("tempting_target_id", "")) == objective_id:
				return true
	return false

func _first_unit_id() -> String:
	for uid in _gs().state.get("units", {}):
		return str(uid)
	return ""

## `GameState` is not visible as a global identifier from a SceneTree script —
## resolve the autoload off the root instead (same pattern as the other
## tests/test_secondary_*.gd suites).
func _gs():
	return root.get_node_or_null("GameState")

## Stand a real ObjectiveVisual up headlessly and register it where
## SecondaryMissionManager looks for it, so the marker assertions test the
## actual label the player sees rather than a proxy for it.
##
## Loaded at runtime rather than referenced as the `ObjectiveVisual` global:
## that script reaches for the Measurement autoload, which is not resolvable
## while a `-s` script is being parsed, and the dependency makes the first
## compile pass emit a spurious SCRIPT ERROR.
func _register_objective_visual(objective_id: String):
	var mm = root.get_node_or_null("MissionManager")
	var existing = mm.objectives_visual_refs.get(objective_id, null)
	if existing != null and is_instance_valid(existing):
		return existing
	var vis = load("res://scripts/ObjectiveVisual.gd").new()
	vis.objective_data = {"id": objective_id}
	vis.name = objective_id
	root.add_child(vis)
	mm.objectives_visual_refs[objective_id] = vis
	return vis

func _marker_visible(vis) -> bool:
	return vis.tempting_target_label != null and vis.tempting_target_label.visible
