extends SceneTree

# T-016 + T-017: Daughters of the Abyss (Witchseekers/Prosecutors) gives the unit
# Feel No Pain 3+ ONLY against Psychic Attacks and mortal wounds.
#
# Pre-fix bugs:
#   T-016: RulesEngine.get_unit_fnp() never reads `effect_fnp_psychic_mortal`,
#          so the flag was set but ignored — DotA gave 0 FNP in practice.
#   T-017: ABILITY_EFFECTS["Daughters of the Abyss"] already uses
#          `grant_fnp_psychic_mortal` (the right primitive), but because it was
#          never read, the audit observed "always-on" behaviour as a side effect
#          of mis-set always-on FNP elsewhere.
#
# This test pins:
#   - get_unit_fnp_for_attack(unit, true)  → returns 3 when only conditional FNP set
#   - get_unit_fnp_for_attack(unit, false) → returns 0 when only conditional FNP set
#   - apply_mortal_wounds rolls FNP 3+ against MW for a unit with conditional FNP
#   - ABILITY_EFFECTS["Daughters of the Abyss"] uses grant_fnp_psychic_mortal
#
# Usage: godot --headless --path . -s tests/test_t016_t017_psychic_mortal_fnp.gd

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
	print("\n=== test_t016_t017_psychic_mortal_fnp ===\n")
	_test_get_unit_fnp_for_attack()
	_test_apply_mortal_wounds_uses_conditional_fnp()
	_test_regular_damage_path_does_not_use_conditional_fnp()
	_test_ability_effects_entry_is_correct()
	_finish()

func _test_get_unit_fnp_for_attack() -> void:
	print("\n-- T-016a: get_unit_fnp_for_attack respects context --")
	var rules = root.get_node("RulesEngine")

	# Witchseekers: only conditional FNP via flags.effect_fnp_psychic_mortal=3
	var witch = {
		"meta": {"stats": {"toughness": 3, "save": 3, "wounds": 1}},
		"flags": {"effect_fnp_psychic_mortal": 3},
		"models": [],
	}
	_check("Witchseekers FNP for psychic/MW = 3",
		rules.get_unit_fnp_for_attack(witch, true) == 3,
		"got %d" % rules.get_unit_fnp_for_attack(witch, true))
	_check("Witchseekers FNP for non-psychic/MW = 0",
		rules.get_unit_fnp_for_attack(witch, false) == 0,
		"got %d" % rules.get_unit_fnp_for_attack(witch, false))

	# Unit with both unconditional FNP 5+ and conditional FNP 3+
	var dual = {
		"meta": {"stats": {"toughness": 4, "save": 3, "wounds": 1}},
		"flags": {"effect_fnp_psychic_mortal": 3, "effect_fnp": 5},
		"models": [],
	}
	_check("Dual FNP for psychic/MW returns the BETTER (lower) = 3",
		rules.get_unit_fnp_for_attack(dual, true) == 3,
		"got %d" % rules.get_unit_fnp_for_attack(dual, true))
	_check("Dual FNP for regular damage returns unconditional 5",
		rules.get_unit_fnp_for_attack(dual, false) == 5,
		"got %d" % rules.get_unit_fnp_for_attack(dual, false))

func _test_apply_mortal_wounds_uses_conditional_fnp() -> void:
	print("\n-- T-016b: apply_mortal_wounds rolls FNP 3+ for DotA unit --")
	var rules = root.get_node("RulesEngine")

	# Build a board with one Witchseeker model. Use seeded RNG so we can
	# count the FNP rolls.
	var board = {
		"units": {
			"U_WITCH": {
				"id": "U_WITCH",
				"owner": 1,
				"meta": {"stats": {"toughness": 3, "save": 3, "wounds": 1}},
				"flags": {"effect_fnp_psychic_mortal": 3},
				"models": [
					{"id": "m1", "alive": true, "current_wounds": 1, "wounds": 1},
					{"id": "m2", "alive": true, "current_wounds": 1, "wounds": 1},
					{"id": "m3", "alive": true, "current_wounds": 1, "wounds": 1},
				],
			},
		},
	}
	# Seeded RNG for determinism. Apply 6 mortal wounds.
	var rng = rules.RNGService.new(424242)
	var result = rules.apply_mortal_wounds("U_WITCH", 6, board, rng)
	var fnp_rolls = result.get("fnp_rolls", [])
	_check("apply_mortal_wounds rolled SOME FNP dice (i.e. FNP fired)",
		fnp_rolls.size() > 0, "fnp_rolls=%s" % str(fnp_rolls))
	# Wounds applied should be ≤ 6 (some prevented by FNP)
	_check("wounds_applied (%d) ≤ mortal_wounds (6)" % result.get("wounds_applied", 0),
		result.get("wounds_applied", 0) <= 6)

func _test_regular_damage_path_does_not_use_conditional_fnp() -> void:
	print("\n-- T-017a: Regular (non-psychic/non-MW) FNP path skips conditional flag --")
	var rules = root.get_node("RulesEngine")
	var witch = {
		"meta": {"stats": {"toughness": 3, "save": 3, "wounds": 1}},
		"flags": {"effect_fnp_psychic_mortal": 3},
		"models": [],
	}
	# get_unit_fnp (the regular damage path) must ignore the conditional flag.
	_check("get_unit_fnp ignores effect_fnp_psychic_mortal",
		rules.get_unit_fnp(witch) == 0,
		"got %d — regular bolter shots must not see DotA FNP" % rules.get_unit_fnp(witch))

func _test_ability_effects_entry_is_correct() -> void:
	print("\n-- T-017b: ABILITY_EFFECTS['Daughters of the Abyss'] uses grant_fnp_psychic_mortal --")
	var f := FileAccess.open("res://autoloads/UnitAbilityManager.gd", FileAccess.READ)
	_check("UnitAbilityManager.gd readable", f != null)
	if f == null:
		return
	var src = f.get_as_text()
	f.close()
	# Naive extract: check that within the DotA block, the effect is grant_fnp_psychic_mortal
	# value 3, and not grant_fnp.
	var dota_idx = src.find("\"Daughters of the Abyss\":")
	_check("DotA entry exists", dota_idx >= 0)
	if dota_idx < 0:
		return
	var dota_block = src.substr(dota_idx, 400)
	_check("DotA effect is grant_fnp_psychic_mortal value 3",
		dota_block.find("grant_fnp_psychic_mortal") >= 0
			and dota_block.find("\"value\": 3") >= 0)
	_check("DotA does NOT use unconditional grant_fnp",
		dota_block.find("\"type\": \"grant_fnp\"") < 0,
		"unconditional grant_fnp would mis-fire on regular damage too")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
