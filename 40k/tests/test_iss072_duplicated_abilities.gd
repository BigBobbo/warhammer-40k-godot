extends SceneTree

# ISS-072 (11e 24.02): duplicated weapon abilities are NOT cumulative —
# the player selects which instance applies (auto: the best). A weapon
# with two [SUSTAINED HITS] instances uses the highest, never the sum;
# AbilityRegistry.from_weapon collapses duplicate ids keeping the higher
# numeric param.
#
# Usage: godot --headless --path . -s tests/test_iss072_duplicated_abilities.gd

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
	print("\n=== test_iss072_duplicated_abilities ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or rules == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)

	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Shooter", "keywords": ["INFANTRY"], "stats": {},
				"weapons": [
					{"name": "Dup Sus", "type": "Ranged", "range": "24", "attacks": "2",
						"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
						"special_rules": "sustained hits 1, sustained hits 2"},
					{"name": "Single Sus", "type": "Ranged", "range": "24", "attacks": "2",
						"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
						"special_rules": "sustained hits 1"},
				]},
			"models": [{"id": "a0", "alive": true, "position": {"x": 100, "y": 100}, "base_mm": 32}]},
	}
	var board = gs.state

	print("-- sustained hits: duplicated -> highest, never summed (24.02) --")
	var dup = rules.get_sustained_hits_value("Dup Sus", board)
	_check("duplicated SUSTAINED HITS 1 + 2 -> value 2 (highest, not 3, not 1)", dup.value == 2, str(dup))
	var single = rules.get_sustained_hits_value("Single Sus", board)
	_check("single SUSTAINED HITS 1 -> value 1 (unchanged)", single.value == 1, str(single))

	print("\n-- from_weapon collapses duplicate ids, keeping the higher x --")
	var AR = load("res://scripts/rules/AbilityRegistry.gd")
	var abilities = AR.from_weapon({"special_rules": "sustained hits 1, sustained hits 2"})
	var sus_entries := 0
	var sus_x := 0
	for e in abilities:
		if str(e.get("id", "")) == "sustained_hits":
			sus_entries += 1
			sus_x = int(e.get("x", 0))
	_check("exactly ONE sustained_hits entry (non-cumulative)", sus_entries == 1, str(abilities))
	_check("the kept instance is the higher (x = 2)", sus_x == 2, str(abilities))

	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
