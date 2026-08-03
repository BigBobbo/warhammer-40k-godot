extends SceneTree

# ARMOUR SAVES IN THE GAME LOG.
#
# The 11e allocation-group flow resolves the whole save batch inside
# AllocationGroupOverlay and hands the phase one summary back. Nothing in that
# path ever emitted a save dice block, so the game log's combat card showed the
# hit roll and the wound roll and then jumped straight to "No models destroyed"
# — the armour saves that were the REASON nothing died never appeared.
#
# This covers the engine half of the fix:
#   1. Allocation.apply_save_rolls records, per die, the roll the defender
#      actually needed (AP + save modifier applied, invuln when better).
#   2. RulesEngine's 11e batch carries that threshold plus successes/failed on
#      its save dice block.
#   3. Rules.normalize_allocation_11e_dice rewrites the batch's blocks
#      into the "save_roll" / "feel_no_pain" shapes the log renderers match.
#   4. GameLogPanel._build_realtime_dice_row builds a real dice row from the
#      normalized block (the visible "Save (N+)" row on the combat card).
#
# Usage: godot --headless --path . -s tests/test_armor_saves_in_game_log.gd

const GameLogPanelScript := preload("res://scripts/GameLogPanel.gd")
const DiceRowVisualScript := preload("res://scripts/DiceRowVisual.gd")
# Autoload identifiers do not resolve at parse time in a `-s` SceneTree script,
# so reach the engine's statics through the script itself.
const Rules := preload("res://autoloads/RulesEngine.gd")

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init() -> void:
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

# 5 Boyz, Sv6+, no invuln — the "Custodian Guard shoots Stormboyz" shape from
# the reported screenshot.
func _boyz_unit() -> Dictionary:
	var models := []
	for i in range(5):
		models.append({"id": "boy%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"save": 6, "invuln": 0})
	return {"meta": {"keywords": ["INFANTRY"], "stats": {}}, "models": models}

# 3 Custodians, Sv2+ / InSv4+ — proves the invuln branch wins when AP makes
# the armour save the worse of the two.
func _custodian_unit() -> Dictionary:
	var models := []
	for i in range(3):
		models.append({"id": "cust%d" % i, "alive": true, "wounds": 3, "current_wounds": 3,
			"save": 2, "invuln": 4})
	return {"meta": {"keywords": ["INFANTRY"], "stats": {}}, "models": models}

func _run_tests() -> void:
	if passed > 0 or failed > 0:
		return
	print("\n=== test_armor_saves_in_game_log ===\n")

	_test_events_record_needed_roll()
	_test_events_record_invuln_when_better()
	_test_batch_block_carries_threshold_and_counts()
	_test_normalize_save_block()
	_test_normalize_fnp_block()
	_test_normalize_passes_unknown_contexts_through()
	_test_game_log_panel_builds_save_row()
	_test_result_line_carries_save_tally()
	_test_save_detail_line_prints_ap_once()

	print("\n=== Result: %d passed / %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_events_record_needed_roll() -> void:
	print("\n-- per-die 'needed' threshold --")
	var unit := _boyz_unit()
	var groups = Allocation.build_groups(unit)
	# Sv6+ vs AP-1 → needs a 7+ (impossible, but that IS the number to show).
	var res = Allocation.apply_save_rolls(unit, groups, Allocation.default_order(groups),
		[3, 5], -1, 1)
	_check("two save events recorded", res.events.size() == 2, str(res.events))
	_check("Sv6+ vs AP-1 needs 7+", int(res.events[0].get("needed", 0)) == 7,
		str(res.events[0]))
	_check("armour save is not flagged as invuln", res.events[0].get("using_invuln", true) == false,
		str(res.events[0]))

	# Same unit with no AP: Sv6+ needs a 6+ and a 6 saves.
	var unit2 := _boyz_unit()
	var groups2 = Allocation.build_groups(unit2)
	var res2 = Allocation.apply_save_rolls(unit2, groups2, Allocation.default_order(groups2),
		[6, 2], 0, 1)
	_check("Sv6+ with no AP needs 6+", int(res2.events[0].get("needed", 0)) == 6,
		str(res2.events[0]))
	var saved_events := 0
	for ev in res2.events:
		if ev.get("result", "") == "saved":
			saved_events += 1
	_check("the 6 saved, the 2 did not", saved_events == 1, str(res2.events))

func _test_events_record_invuln_when_better() -> void:
	print("\n-- invulnerable save wins when AP makes armour worse --")
	var unit := _custodian_unit()
	var groups = Allocation.build_groups(unit)
	# Sv2+ vs AP-4 → armour needs 6+; InSv4+ is better, so 4+ is the number.
	var res = Allocation.apply_save_rolls(unit, groups, Allocation.default_order(groups),
		[4, 3], -4, 1)
	_check("invuln threshold used", int(res.events[0].get("needed", 0)) == 4,
		str(res.events[0]))
	_check("invuln flagged on the event", res.events[0].get("using_invuln", false) == true,
		str(res.events[0]))

	# AP-1: armour is 3+, better than the 4+ invuln → armour wins.
	var unit2 := _custodian_unit()
	var groups2 = Allocation.build_groups(unit2)
	var res2 = Allocation.apply_save_rolls(unit2, groups2, Allocation.default_order(groups2),
		[5], -1, 1)
	_check("armour threshold used when better", int(res2.events[0].get("needed", 0)) == 3,
		str(res2.events[0]))
	_check("armour not flagged as invuln", res2.events[0].get("using_invuln", true) == false,
		str(res2.events[0]))

func _test_batch_block_carries_threshold_and_counts() -> void:
	print("\n-- 11e batch save block --")
	var board := {"units": {"U_T": _boyz_unit()}}
	board.units.U_T["owner"] = 2
	var save_data := {
		"target_unit_id": "U_T", "wounds_to_save": 4, "ap": 0,
		"damage": 1, "damage_raw": "1",
	}
	# Forced rolls: two 6s save (Sv6+), a 1 and a 2 fail.
	var out = Rules.resolve_allocation_batch_11e(save_data, [], board,
		Rules.RNGService.new(7), {"forced_save_rolls": [6, 1, 6, 2]})
	var save_block := {}
	for d in out.get("dice", []):
		if d.get("context", "") == "save":
			save_block = d
			break
	_check("batch emitted a save dice block", not save_block.is_empty(), str(out.get("dice", [])))
	if save_block.is_empty():
		return
	_check("block carries the threshold", str(save_block.get("threshold", "")) == "6+",
		str(save_block))
	_check("block carries successes", int(save_block.get("successes", -1)) == 2, str(save_block))
	_check("block carries failed", int(save_block.get("failed", -1)) == 2, str(save_block))
	_check("summary agrees with the block",
		int(out.get("saves_passed", -1)) == 2 and int(out.get("saves_failed", -1)) == 2,
		str(out))

func _test_normalize_save_block() -> void:
	print("\n-- normalize_allocation_11e_dice: save --")
	var summary := {"dice": [{
		"context": "save", "sv": "6+", "ap": -1, "save_modifier": 0,
		"rolls_raw": [6, 2, 3], "fails": 2, "failed": 2, "successes": 1,
		"threshold": "7+", "using_invuln": false,
		"allocation_11e": {"order": ["grp_1_6_0"], "events": []},
	}]}
	var blocks = Rules.normalize_allocation_11e_dice(summary, {
		"target_unit_name": "Stormboyz Beta", "weapon_name": "Guardian spear - Ranged"})
	_check("one block out", blocks.size() == 1, str(blocks))
	var b: Dictionary = blocks[0]
	_check("context rewritten to save_roll", b.get("context", "") == "save_roll", str(b))
	_check("threshold preserved", str(b.get("threshold", "")) == "7+", str(b))
	_check("original_save parsed from sv", int(b.get("original_save", 0)) == 6, str(b))
	_check("target name attributed", b.get("target_unit_name", "") == "Stormboyz Beta", str(b))
	_check("weapon name attributed", b.get("weapon_name", "") == "Guardian spear - Ranged", str(b))
	_check("rolls carried over", b.get("rolls_raw", []) == [6, 2, 3], str(b))
	_check("counts carried over",
		int(b.get("successes", -1)) == 1 and int(b.get("failed", -1)) == 2, str(b))

	# Legacy block with only `fails` and `sv` must still normalize cleanly.
	var legacy := {"dice": [{"context": "save", "sv": "5+", "ap": 0,
		"rolls_raw": [4, 2], "fails": 1}]}
	var lb: Dictionary = Rules.normalize_allocation_11e_dice(legacy)[0]
	_check("legacy fails → failed", int(lb.get("failed", -1)) == 1, str(lb))
	_check("legacy successes derived", int(lb.get("successes", -1)) == 1, str(lb))
	_check("legacy threshold falls back to sv", str(lb.get("threshold", "")) == "5+", str(lb))

func _test_normalize_fnp_block() -> void:
	print("\n-- normalize_allocation_11e_dice: feel no pain --")
	var summary := {"dice": [{
		"context": "feel_no_pain", "source": "failed_save", "rolls": [5, 2, 6],
		"fnp_value": 5, "wounds_prevented": 2, "wounds_remaining": 1, "total_wounds": 3,
	}]}
	var b: Dictionary = Rules.normalize_allocation_11e_dice(summary,
		{"target_unit_name": "Stormboyz Beta"})[0]
	_check("context kept", b.get("context", "") == "feel_no_pain", str(b))
	_check("rolls promoted to rolls_raw", b.get("rolls_raw", []) == [5, 2, 6], str(b))
	_check("threshold built from fnp_value", str(b.get("threshold", "")) == "5+", str(b))
	_check("target attributed", b.get("target_unit_name", "") == "Stormboyz Beta", str(b))

func _test_normalize_passes_unknown_contexts_through() -> void:
	print("\n-- normalize_allocation_11e_dice: passthrough --")
	var summary := {"dice": [{"context": "devastating_wounds_11e", "crits": 2}]}
	var blocks = Rules.normalize_allocation_11e_dice(summary)
	_check("unknown context untouched",
		blocks.size() == 1 and blocks[0].get("context", "") == "devastating_wounds_11e",
		str(blocks))

func _test_game_log_panel_builds_save_row() -> void:
	print("\n-- GameLogPanel save row --")
	var panel = GameLogPanelScript.new()
	var row = panel._build_realtime_dice_row({
		"context": "save_roll", "rolls_raw": [6, 2, 3], "threshold": "6+",
		"successes": 1, "failed": 2, "using_invuln": false}, "save_roll")
	_check("save_roll builds a row", row != null)
	if row != null:
		var has_dice := false
		for c in row.get_children():
			if c is DiceRowVisualScript:
				has_dice = true
		_check("save row mounts DiceRowVisual", has_dice)
		row.free()

	# Defensive alias: an un-normalized engine block still renders, reading the
	# threshold from `sv` and the fail count from `fails`.
	var raw_row = panel._build_realtime_dice_row({
		"context": "save", "rolls_raw": [1, 4], "sv": "5+", "fails": 1}, "save")
	_check("raw 'save' context builds a row too", raw_row != null)
	if raw_row != null:
		var raw_has_dice := false
		for c in raw_row.get_children():
			if c is DiceRowVisualScript:
				raw_has_dice = true
		_check("raw save row mounts DiceRowVisual", raw_has_dice)
		raw_row.free()
	panel.free()

func _shooting_phase() -> Node:
	# A bare ShootingPhase instance is enough for the log emitters: they only
	# read the dice blocks handed to them and write through GameEventLog.
	var phase = preload("res://phases/ShootingPhase.gd").new()
	root.add_child(phase)
	return phase

func _last_entry_of_type(entry_type: String) -> String:
	var gel = root.get_node_or_null("GameEventLog")
	if gel == null:
		return ""
	var out := ""
	for e in gel.get_all_entries():
		if e.get("type", "") == entry_type:
			out = str(e.get("text", ""))
	return out

func _test_result_line_carries_save_tally() -> void:
	# The reported complaint: the card said "No models destroyed" and nothing
	# explained why. The result line must now carry the save tally in BOTH
	# outcomes so the number of saves that held is right there.
	print("\n-- result line save tally --")
	var phase = _shooting_phase()
	var blocks := [{
		"context": "save_roll", "threshold": "5+", "rolls_raw": [5, 6],
		"successes": 2, "failed": 0, "ap": -1,
		"target_unit_name": "Stormboyz Beta", "weapon_name": "Guardian spear - Ranged"}]
	phase._emit_verbose_combat_log("U_X", [], blocks, 0, "shooting_saves")
	var none_line := _last_entry_of_type("combat_result")
	_check("zero-casualty result names the saves",
		none_line == "  Result: No models destroyed (2/2 saves passed)", none_line)

	var blocks2 := [{
		"context": "save_roll", "threshold": "6+", "rolls_raw": [2, 1, 3, 4],
		"successes": 0, "failed": 4, "ap": -1,
		"target_unit_name": "Boyz Alpha", "weapon_name": "Guardian spear - Ranged"}]
	phase._emit_verbose_combat_log("U_X", [], blocks2, 4, "shooting_saves")
	var some_line := _last_entry_of_type("combat_result")
	_check("casualty result names the saves too",
		some_line == "  Result: 4 models destroyed (0/4 saves passed)", some_line)

	# Hit/wound-only stages must NOT emit a result line at all.
	phase._emit_verbose_combat_log("U_X", [], [], 0, "sequential_hits")
	_check("hit-only stage leaves the result line alone",
		_last_entry_of_type("combat_result") == some_line, _last_entry_of_type("combat_result"))
	phase.queue_free()

func _test_save_detail_line_prints_ap_once() -> void:
	# AP is stored negative (-1), and the old "(AP -%d)" format printed
	# "(AP --1)". The 11e path made that line visible for the first time.
	print("\n-- save detail AP formatting --")
	var phase = _shooting_phase()
	phase._emit_save_detail_log({
		"context": "save_roll", "threshold": "6+", "rolls_raw": [2, 1],
		"successes": 0, "failed": 2, "ap": -1, "using_invuln": false,
		"target_unit_name": "Boyz Alpha", "weapon_name": "Guardian spear - Ranged"})
	var line := _last_entry_of_type("combat_detail")
	_check("AP renders as a single minus", "(AP -1)" in line and "--" not in line, line)
	_check("detail names target, weapon and tally",
		"Boyz Alpha" in line and "Guardian spear - Ranged" in line and "0 passed, 2 failed" in line,
		line)

	phase._emit_save_detail_log({
		"context": "save_roll", "threshold": "4+", "rolls_raw": [5],
		"successes": 1, "failed": 0, "ap": 0, "using_invuln": true,
		"target_unit_name": "Custodian Guard", "weapon_name": "Rokkit launcha"})
	var inv_line := _last_entry_of_type("combat_detail")
	_check("invulnerable saves are named as such",
		"Invulnerable Save 4+" in inv_line and "AP" not in inv_line, inv_line)
	phase.queue_free()
