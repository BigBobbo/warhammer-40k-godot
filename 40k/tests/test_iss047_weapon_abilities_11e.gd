extends SceneTree

# ISS-047 (step 1): 11e weapon-ability primitives.
#   A) 24.01 keyword scoping: [LETHAL HITS: VEHICLE] applies only vs
#      VEHICLE targets; unscoped entries always apply; scope validated.
#   B) 24.05 [BLAST X] worked example: A3 [BLAST 2] vs 12 models -> +4
#      dice (total 7).
#   C) 24.06 [CLEAVE X] worked example: A3 [CLEAVE 1] vs 16 models,
#      single target -> +3 dice (total 6); split targets -> +0.
#
# Usage: godot --headless --path . -s tests/test_iss047_weapon_abilities_11e.gd

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
	print("\n=== test_iss047_weapon_abilities_11e ===\n")

	print("-- A: keyword scoping (24.01) --")
	var lethal_scoped = {"id": "lethal_hits", "scope": ["VEHICLE"]}
	var sustained_scoped = {"id": "sustained_hits", "x": 1, "scope": ["INFANTRY", "BEASTS"]}
	var plain = {"id": "twin_linked"}
	_check("scoped ability applies vs matching keyword",
		AbilityRegistry.entry_applies_to_target(lethal_scoped, ["VEHICLE", "TITANIC"]))
	_check("scoped ability does NOT apply vs non-matching target",
		not AbilityRegistry.entry_applies_to_target(lethal_scoped, ["INFANTRY"]))
	_check("multi-keyword scope: any match applies",
		AbilityRegistry.entry_applies_to_target(sustained_scoped, ["BEASTS"]))
	_check("unscoped ability always applies",
		AbilityRegistry.entry_applies_to_target(plain, []))
	var vs = AbilityRegistry.abilities_vs_target([lethal_scoped, sustained_scoped, plain], ["vehicle"])
	_check("abilities_vs_target filters (case-insensitive)",
		vs.size() == 2 and vs[0].id == "lethal_hits" and vs[1].id == "twin_linked", str(vs))
	_check("scope param accepted by validation",
		AbilityRegistry.validate([lethal_scoped]).is_empty())
	_check("non-array scope rejected by validation",
		not AbilityRegistry.validate([{"id": "lethal_hits", "scope": "VEHICLE"}]).is_empty())

	print("\n-- B: BLAST X (24.05) --")
	_check("[BLAST 2] A3 vs 12 models: +4 dice (worked example)",
		AbilityRegistry.blast_bonus_dice(2, 12) == 4)
	_check("plain [BLAST] vs 11 models: +2", AbilityRegistry.blast_bonus_dice(1, 11) == 2)
	_check("BLAST vs 4 models: +0 (rounds down)", AbilityRegistry.blast_bonus_dice(1, 4) == 0)

	print("\n-- C: CLEAVE X (24.06) --")
	_check("[CLEAVE 1] A3 vs 16 models, single target: +3 (worked example)",
		AbilityRegistry.cleave_bonus_dice(1, 16, true) == 3)
	_check("CLEAVE disabled when attacks were split between targets",
		AbilityRegistry.cleave_bonus_dice(1, 16, false) == 0)
	_check("[CLEAVE 2] vs 10 models single target: +4",
		AbilityRegistry.cleave_bonus_dice(2, 10, true) == 4)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
