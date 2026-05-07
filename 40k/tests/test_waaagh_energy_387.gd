extends SceneTree

const RulesEngine = preload("res://autoloads/RulesEngine.gd")

# Issue #387: validate Waaagh! Energy ('Eadbanger size scaling).
# Pure-math test of the helper + profile mutation. The integration into
# _resolve_assignment_until_wounds and _resolve_assignment is a single-line
# call to _apply_waaagh_energy_to_profile so a unit test of the mutation is
# representative.
# Run via: godot --headless --path . --script tests/test_waaagh_energy_387.gd

func _initialize():
	print("=== Issue #387: Waaagh! Energy validation ===")
	var failures = 0
	failures += _test_unled_no_bonus()
	failures += _test_5_models_plus_1()
	failures += _test_10_models_plus_2_hazardous()
	failures += _test_profile_mutation()
	failures += _test_non_eadbanger_unmodified()
	failures += _test_no_ability_no_bonus()

	if failures == 0:
		print("\n[OK] all #387 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % failures)
		quit(1)

func _make_board(weirdboy_attached_to: String, bodyguard_count: int) -> Dictionary:
	# Create a board with a Weirdboy + a Boyz bodyguard unit. Optionally attach.
	var weirdboy = {
		"id": "U_WEIRDBOY",
		"owner": 2,
		"abilities": [{"name": "Waaagh! Energy"}],
		"meta": {"weapons": [{"name": "'Eadbanger", "type": "Ranged", "range": "18", "attacks": "D6", "ballistic_skill": "5", "strength": "5", "ap": "-1", "damage": "1"}]},
		"models": [{"id": "m1", "alive": true, "wounds": 4, "current_wounds": 4}],
		"attached_to": weirdboy_attached_to if weirdboy_attached_to != "" else null,
	}
	var boyz_models = []
	for i in range(bodyguard_count):
		boyz_models.append({"id": "m%d" % (i + 1), "alive": true, "wounds": 1, "current_wounds": 1})
	var boyz = {
		"id": "U_BOYZ",
		"owner": 2,
		"models": boyz_models,
		"attachment_data": {"attached_characters": (["U_WEIRDBOY"] if weirdboy_attached_to == "U_BOYZ" else [])},
	}
	return {"units": {"U_WEIRDBOY": weirdboy, "U_BOYZ": boyz}}

func _test_unled_no_bonus() -> int:
	print("\n-- weirdboy not leading -> no bonus --")
	var board = _make_board("", 9)
	var bonus = RulesEngine.get_waaagh_energy_eadbanger_bonus("U_WEIRDBOY", board)
	if bonus.strength_bonus == 0 and bonus.damage_bonus == 0 and not bonus.hazardous:
		print("  [OK] unled returns zero bonus")
		return 0
	push_error("expected zero bonus for unled weirdboy, got %s" % str(bonus))
	return 1

func _test_5_models_plus_1() -> int:
	print("\n-- 5 models in led unit (boyz=4 + weirdboy=1) -> +1 S/D, no hazardous --")
	# 4 Boyz + 1 Weirdboy = 5 alive models in the led unit
	var board = _make_board("U_BOYZ", 4)
	var bonus = RulesEngine.get_waaagh_energy_eadbanger_bonus("U_WEIRDBOY", board)
	if bonus.led_unit_model_count == 5 and bonus.strength_bonus == 1 and bonus.damage_bonus == 1 and not bonus.hazardous:
		print("  [OK] +1 S/D, hazardous=false")
		return 0
	push_error("expected led_unit_model_count=5, S+1, D+1, hazardous=false, got %s" % str(bonus))
	return 1

func _test_10_models_plus_2_hazardous() -> int:
	print("\n-- 10 models in led unit (boyz=9 + weirdboy=1) -> +2 S/D, HAZARDOUS --")
	var board = _make_board("U_BOYZ", 9)
	var bonus = RulesEngine.get_waaagh_energy_eadbanger_bonus("U_WEIRDBOY", board)
	if bonus.led_unit_model_count == 10 and bonus.strength_bonus == 2 and bonus.damage_bonus == 2 and bonus.hazardous:
		print("  [OK] +2 S/D, hazardous=true")
		return 0
	push_error("expected led_unit_model_count=10, S+2, D+2, hazardous=true, got %s" % str(bonus))
	return 1

func _test_profile_mutation() -> int:
	print("\n-- _apply_waaagh_energy_to_profile mutates 'Eadbanger profile --")
	var board = _make_board("U_BOYZ", 9)  # 10 models -> +2 S/D + HAZARDOUS
	var profile = {
		"name": "'Eadbanger",
		"strength": 5,
		"damage": 1,
		"damage_raw": "1",
		"keywords": [],
		"special_rules": "",
	}
	var mutated = RulesEngine._apply_waaagh_energy_to_profile(profile, "Eadbanger", "U_WEIRDBOY", board)
	var fails = 0
	if int(mutated.get("strength", 0)) != 7:
		push_error("expected strength=7 (5+2), got %s" % str(mutated.get("strength")))
		fails += 1
	if int(mutated.get("damage", 0)) != 3:
		push_error("expected damage=3 (1+2), got %s" % str(mutated.get("damage")))
		fails += 1
	if String(mutated.get("damage_raw", "")) != "3":
		push_error("expected damage_raw='3', got %s" % str(mutated.get("damage_raw")))
		fails += 1
	var has_haz = false
	for kw in mutated.get("keywords", []):
		if String(kw).to_upper() == "HAZARDOUS":
			has_haz = true
			break
	if not has_haz:
		push_error("expected HAZARDOUS keyword, got %s" % str(mutated.get("keywords")))
		fails += 1
	if fails == 0:
		print("  [OK] profile mutated: S=7, D=3, damage_raw=3, HAZARDOUS")
	# Verify the original profile was not mutated in place (duplicate(true) used)
	if int(profile.get("strength", 0)) != 5:
		push_error("original profile mutated in place — expected duplicate")
		fails += 1
	return fails

func _test_non_eadbanger_unmodified() -> int:
	print("\n-- non-'Eadbanger weapon profile is unchanged --")
	var board = _make_board("U_BOYZ", 9)
	var profile = {"name": "shoota", "strength": 4, "damage": 1, "damage_raw": "1", "keywords": []}
	var mutated = RulesEngine._apply_waaagh_energy_to_profile(profile, "shoota", "U_WEIRDBOY", board)
	if int(mutated.get("strength", 0)) == 4 and int(mutated.get("damage", 0)) == 1:
		print("  [OK] non-'Eadbanger profile untouched")
		return 0
	push_error("non-'Eadbanger profile was modified: %s" % str(mutated))
	return 1

func _test_no_ability_no_bonus() -> int:
	print("\n-- weirdboy without ability -> no bonus --")
	var board = _make_board("U_BOYZ", 9)
	board.units.U_WEIRDBOY.set("abilities", [])
	var bonus = RulesEngine.get_waaagh_energy_eadbanger_bonus("U_WEIRDBOY", board)
	if bonus.strength_bonus == 0 and not bonus.hazardous:
		print("  [OK] no ability -> no bonus")
		return 0
	push_error("expected zero bonus when ability missing, got %s" % str(bonus))
	return 1
