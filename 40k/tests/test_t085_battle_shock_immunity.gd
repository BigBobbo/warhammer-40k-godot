extends SceneTree

# T-085 (immunity sub-feature): Units with FEARLESS or "And They Shall Know No
# Fear" auto-pass battle-shock tests — _identify_units_needing_tests must skip
# them entirely, never adding them to the test queue.
#
# Already implemented: CommandPhase._has_battle_shock_immunity helper at line
# 268-289. This test pins the helper directly and the integrated identifier
# behaviour.
#
# (The second sub-feature of T-085 — consolidating dual-location
#  flags.battle_shocked vs status_effects.battle_shocked — is NOT covered here;
#  it requires a wider refactor and is left as follow-up.)
#
# Usage: godot --headless --path . -s tests/test_t085_battle_shock_immunity.gd

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
	print("\n=== test_t085_battle_shock_immunity ===\n")
	_test_helper_recognises_immunity()
	_finish()

func _test_helper_recognises_immunity() -> void:
	print("\n-- T-085a: _has_battle_shock_immunity recognises both keyword & ability paths --")
	var phase = load("res://phases/CommandPhase.gd").new()

	# FEARLESS keyword
	_check("FEARLESS keyword grants immunity",
		phase._has_battle_shock_immunity(["FEARLESS", "INFANTRY"], []))
	# Lowercase / mixed case still works
	_check("Mixed-case 'Fearless' keyword grants immunity",
		phase._has_battle_shock_immunity(["Fearless"], []))
	# AND THEY SHALL KNOW NO FEAR keyword
	_check("ATSKNF keyword grants immunity",
		phase._has_battle_shock_immunity(["AND THEY SHALL KNOW NO FEAR", "INFANTRY"], []))
	# Ability path (Dictionary form)
	_check("FEARLESS ability dict grants immunity",
		phase._has_battle_shock_immunity([], [{"name": "Fearless", "type": "Datasheet"}]))
	# Ability path (string form)
	_check("ATSKNF ability string grants immunity",
		phase._has_battle_shock_immunity([], ["And They Shall Know No Fear"]))
	# No immunity — basic infantry
	_check("Plain INFANTRY does NOT grant immunity",
		not phase._has_battle_shock_immunity(["INFANTRY", "TROOPS"], []))
	_check("Empty inputs return false",
		not phase._has_battle_shock_immunity([], []))

	phase.queue_free()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
