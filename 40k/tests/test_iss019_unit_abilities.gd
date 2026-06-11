extends SceneTree

# ISS-019: unified unit-ability queries (UnitAbilities) — datasheet
# abilities AND dynamically granted effect flags answer through one call.
#
# Usage: godot --headless --path . -s tests/test_iss019_unit_abilities.gd

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
	print("\n=== test_iss019_unit_abilities ===\n")
	var rules = root.get_node_or_null("RulesEngine")

	var unit_ds = {"meta": {"abilities": [{"name": "Stealth"}, {"name": "Lone Operative"}]}, "flags": {}}
	var unit_str = {"meta": {"abilities": ["stealth"]}, "flags": {}}
	var unit_dyn = {"meta": {"abilities": []}, "flags": {"effect_stealth": true}}
	var unit_none = {"meta": {"abilities": [{"name": "Deep Strike"}]}, "flags": {}}

	_check("datasheet dict-entry ability found", UnitAbilities.unit_has(unit_ds, "stealth"))
	_check("datasheet string-entry ability found (case-insensitive)", UnitAbilities.unit_has(unit_str, "Stealth"))
	_check("dynamically granted (effect_stealth flag) found", UnitAbilities.unit_has(unit_dyn, "stealth"))
	_check("absent ability not found", not UnitAbilities.unit_has(unit_none, "stealth"))
	_check("lone operative found", UnitAbilities.unit_has(unit_ds, "lone operative"))

	# RulesEngine delegations behave identically
	_check("RulesEngine.has_stealth_ability via datasheet", rules.has_stealth_ability(unit_ds))
	_check("RulesEngine.has_stealth_ability via dynamic grant (NEW capability)",
		rules.has_stealth_ability(unit_dyn))
	_check("RulesEngine.has_lone_operative", rules.has_lone_operative(unit_ds))
	_check("RulesEngine negative case", not rules.has_lone_operative(unit_none))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
