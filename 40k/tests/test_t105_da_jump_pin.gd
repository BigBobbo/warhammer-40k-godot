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
	# Placement: 9" from enemies
	_check("PLACE_DA_JUMP enforces 9\" from enemies",
		"Measurement.inches_to_px(9.0)" in src and "enemy_positions" in src)
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


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
