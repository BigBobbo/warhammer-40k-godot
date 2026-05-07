extends SceneTree

# T-105: Da Jump (Weirdboy psychic, end of Movement Phase) — was unreachable
# in live game (UNIT_ABILITY_AUDIT U-3 confirmed missing from available_actions).
#
# Pins the wiring:
#   - UnitAbilityManager.ABILITY_EFFECTS["Da Jump"].implemented == true
#   - MovementPhase dispatches USE_DA_JUMP and PLACE_DA_JUMP
#   - MovementPhase.get_available_actions surfaces them for eligible Weirdboys
#
# Usage: godot --headless --path . -s tests/test_t105_da_jump_pin.gd

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
	print("\n=== test_t105_da_jump_pin ===\n")
	_test_ability_marked_implemented()
	_test_movement_phase_dispatches_actions()
	_test_movement_phase_surfaces_actions()
	_test_da_jump_flag_resets_across_turns()
	_test_da_jump_flag_reset_live()
	_test_da_jump_placement_hardening()
	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func _test_ability_marked_implemented() -> void:
	print("\n-- T-105/A: ABILITY_EFFECTS[Da Jump].implemented == true --")
	var src = _read("res://autoloads/UnitAbilityManager.gd")
	_check("UnitAbilityManager.gd readable", not src.is_empty())
	# Find the Da Jump entry and check implemented true
	var idx = src.find("\"Da Jump\":")
	_check("Da Jump entry exists", idx >= 0)
	# Slice from "Da Jump":  to next "}," to inspect just that block
	var end_idx = src.find("},", idx)
	var block = src.substr(idx, end_idx - idx) if idx >= 0 and end_idx > idx else ""
	_check("Da Jump block readable", block.length() > 0)
	_check("implemented: true (not false)",
		"\"implemented\": true" in block,
		"Da Jump still flagged implemented=false")
	_check("once_per_turn marker preserved", "\"once_per_turn\": true" in block)


func _test_movement_phase_dispatches_actions() -> void:
	print("\n-- T-105/B: MovementPhase dispatches USE_DA_JUMP / PLACE_DA_JUMP --")
	var src = _read("res://phases/MovementPhase.gd")
	_check("MovementPhase.gd readable", not src.is_empty())
	_check("USE_DA_JUMP dispatch case", "\"USE_DA_JUMP\":" in src)
	_check("PLACE_DA_JUMP dispatch case", "\"PLACE_DA_JUMP\":" in src)
	_check("_process_use_da_jump defined", "func _process_use_da_jump(action: Dictionary)" in src)
	_check("_process_place_da_jump defined", "func _process_place_da_jump(action: Dictionary)" in src)
	# Roll on D6 with seeded RNG
	_check("USE_DA_JUMP rolls via RNGService",
		"RulesEngine.RNGService.new(rng_seed)" in src and "_process_use_da_jump" in src)
	# Failure path: roll==1 → D6 MW
	_check("On 1, deals D6 mortal wounds",
		"if roll_val == 1" in src and "apply_mortal_wounds" in src,
		"Da Jump backlash branch missing")
	# Success path: 2+ marks awaiting placement
	_check("On 2+, awaiting_da_jump_placement set",
		"awaiting_da_jump_placement" in src)
	# Placement: 9" from enemies. Issue #376 replaced the original
	# Measurement.inches_to_px(9.0) check with an inline edge-to-edge
	# distance computation so each model's base radius is accounted for.
	# The detailed source pins in section F (added with launch-blocker
	# #6) cover the new shape; this check only asserts the >9" semantic
	# is still wired.
	_check("PLACE_DA_JUMP enforces 9\" from enemies",
		"edge_dist_in <= 9.0" in src
			or "Measurement.inches_to_px(9.0)" in src and "enemy_positions" in src,
		"strict >9 rejection missing — see _process_place_da_jump")
	# Once-per-turn flag
	_check("USE_DA_JUMP sets da_jump_used_this_turn",
		"da_jump_used_this_turn" in src)


func _test_movement_phase_surfaces_actions() -> void:
	print("\n-- T-105/C: get_available_actions surfaces Da Jump for eligible Weirdboys --")
	var src = _read("res://phases/MovementPhase.gd")
	# Look for the actions.append block with USE_DA_JUMP
	var has_use = src.find("\"type\": \"USE_DA_JUMP\"") >= 0
	var has_place = src.find("\"type\": \"PLACE_DA_JUMP\"") >= 0
	_check("USE_DA_JUMP appended in available_actions", has_use)
	_check("PLACE_DA_JUMP appended after pending placement", has_place)
	_check("guarded by da_jump_used_this_turn",
		"da_jump_used_this_turn" in src and has_use)


func _test_da_jump_flag_resets_across_turns() -> void:
	print("\n-- T-105/D: GameManager._create_flag_reset_diffs clears Da Jump flags --")
	# 06_SYNTHESIS launch-blocker #5 — `da_jump_used_this_turn` was set in
	# MovementPhase._process_use_da_jump but never cleared, so the Weirdboy
	# was permanently locked after one Da Jump.
	var src = _read("res://autoloads/GameManager.gd")
	_check("GameManager.gd readable", not src.is_empty())
	# Find the flags_to_reset list
	var idx = src.find("var flags_to_reset")
	_check("flags_to_reset list exists", idx >= 0)
	var end_idx = src.find("]", idx)
	var block = src.substr(idx, end_idx - idx) if idx >= 0 and end_idx > idx else ""
	_check("flags_to_reset includes da_jump_used_this_turn",
		"\"da_jump_used_this_turn\"" in block,
		"flag never reset → Weirdboy locked after first Da Jump")
	_check("flags_to_reset includes awaiting_da_jump_placement (safety)",
		"\"awaiting_da_jump_placement\"" in block,
		"placement-pending state could survive a save/turn boundary")


func _test_da_jump_flag_reset_live() -> void:
	print("\n-- T-105/E: live diff for a unit carrying the Da Jump flag --")
	# Drive the actual diff producer rather than just grepping source. We
	# inject a synthetic unit with the flag set and verify the function
	# returns a `remove` op for both Da Jump flags.
	var gm = root.get_node_or_null("GameManager")
	if gm == null:
		_check("GameManager autoload reachable", false, "autoload missing")
		return
	_check("GameManager autoload reachable", true)
	# Stash + replace the units dict so the test is hermetic
	var gs = root.get_node("GameState")
	var prev_units = gs.state.get("units", {}).duplicate(true)
	gs.state["units"] = {
		"U_TEST_WEIRDBOY": {
			"id": "U_TEST_WEIRDBOY",
			"owner": 2,
			"flags": {
				"da_jump_used_this_turn": true,
				"awaiting_da_jump_placement": true,
				"moved": true,
			},
		},
	}
	var diffs: Array = gm._create_flag_reset_diffs(2)
	var removed_paths := []
	for d in diffs:
		if d.get("op", "") == "remove":
			removed_paths.append(d.get("path", ""))
	gs.state["units"] = prev_units  # restore
	_check("remove diff for da_jump_used_this_turn",
		"units.U_TEST_WEIRDBOY.flags.da_jump_used_this_turn" in removed_paths)
	_check("remove diff for awaiting_da_jump_placement",
		"units.U_TEST_WEIRDBOY.flags.awaiting_da_jump_placement" in removed_paths)
	_check("remove diff for moved (regression — generic flag still cleared)",
		"units.U_TEST_WEIRDBOY.flags.moved" in removed_paths)


func _test_da_jump_placement_hardening() -> void:
	print("\n-- T-105/F: _process_place_da_jump validation source pins (issue #376 + #6) --")
	# 06_SYNTHESIS launch-blocker #6 / TLV-1: original code used center-to-
	# center distance with strict <, no board-bounds check, no coherency
	# check. Issue #376 added edge-to-edge >9" + board bounds; this commit
	# adds the coherency leg.
	var src = _read("res://phases/MovementPhase.gd")
	_check("MovementPhase.gd readable", not src.is_empty())
	# Strict >9" rejection (i.e. <=9.0 fails)
	_check("strict >9\" rejection (edge_dist_in <= 9.0)",
		"edge_dist_in <= 9.0" in src,
		"weak <9 check would let exactly-9 placements through")
	# Edge-to-edge distance, not center-to-center
	_check("edge-to-edge distance accounts for both base radii",
		"model_radius_in" in src and "enemy_radius_in" in src
			and "edge_dist_in = dist_in - model_radius_in - enemy_radius_in" in src)
	# Board bounds check
	_check("board-bounds rejection (off-board placement fails)",
		"is off the board" in src)
	# Coherency check
	_check("coherency check on the post-placement model array",
		"_check_models_coherency(post_placement_models)" in src,
		"placements that fragment the squad must be rejected")
	_check("coherency rejection emits a clear reason",
		"Da Jump place: coherency broken" in src)
	# Coherency check should include the un-placed (already-on-board)
	# alive models too, not just the ones being placed this action.
	_check("coherency check seeds with un-placed alive models",
		"placement_ids" in src and "post_placement_models.append(m)" in src,
		"single-model Weirdboys are fine but multi-model units would mis-validate")


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
