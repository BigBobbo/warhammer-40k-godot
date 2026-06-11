extends SceneTree

# ISS-056 (step 1): 11e per-unit stratagem restriction (15.01) — each
# player cannot target the same unit with more than one stratagem in the
# same phase. Edition-gated: 10e behavior unchanged.
#
# Usage: godot --headless --path . -s tests/test_iss056_stratagem_per_unit.gd

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
	print("\n=== test_iss056_stratagem_per_unit ===\n")
	var sm = root.get_node_or_null("StratagemManager")
	var gs = root.get_node_or_null("GameState")
	if sm == null or gs == null:
		_check("autoloads reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	var prev_hist = sm._usage_history.duplicate(true)
	sm._usage_history = {"1": [], "2": []}
	var turn = gs.get_battle_round()
	var phase = gs.get_current_phase()

	# Simulate: player 1 already used a stratagem on U_TARGET this phase.
	sm._usage_history["1"].append({"stratagem_id": "go_to_ground", "player": 1,
		"target_unit_id": "U_TARGET", "turn": turn, "phase": phase, "timestamp": 0})
	# Give player 1 plenty of CP so cost checks pass.
	gs.state["players"]["1"]["cp"] = 10

	GameConstants.edition = 11
	var v = sm.can_use_stratagem(1, "command_re_roll", "U_TARGET")
	_check("11e: second stratagem on the same unit this phase is refused",
		v.can_use == false and "15.01" in str(v.reason), str(v))
	v = sm.can_use_stratagem(1, "command_re_roll", "U_OTHER")
	_check("11e: a different unit is fine", v.can_use, str(v))
	v = sm.can_use_stratagem(2, "command_re_roll", "U_TARGET")
	# player 2 has their own budget per 15.01 ("each player")
	gs.state["players"]["2"]["cp"] = 10
	v = sm.can_use_stratagem(2, "command_re_roll", "U_TARGET")
	_check("11e: the restriction is per player", v.can_use, str(v))

	# A different phase clears it
	sm._usage_history["1"][0]["phase"] = phase + 1 if phase < 12 else phase - 1
	v = sm.can_use_stratagem(1, "command_re_roll", "U_TARGET")
	_check("11e: usage in a different phase does not block", v.can_use, str(v))
	sm._usage_history["1"][0]["phase"] = phase

	GameConstants.edition = 10
	v = sm.can_use_stratagem(1, "command_re_roll", "U_TARGET")
	_check("10e: behavior unchanged (no per-unit restriction)", v.can_use, str(v))
	GameConstants.edition = 10

	sm._usage_history = prev_hist
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
