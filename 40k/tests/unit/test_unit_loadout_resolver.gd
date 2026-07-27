extends SceneTree

# UnitLoadoutResolver: the datasheet UI must show the weapons a unit is
# EQUIPPED with, not the datasheet's full option menu.
#
# Run: godot --headless --script tests/unit/test_unit_loadout_resolver.gd

const Resolver = preload("res://scripts/UnitLoadoutResolver.gd")
const TUTORIAL_ARMY := "res://armies/tutorial_orks.json"

var pass_count: int = 0
var fail_count: int = 0


func _assert(condition: bool, test_name: String) -> void:
	if condition:
		print("PASS: %s" % test_name)
		pass_count += 1
	else:
		print("FAIL: %s" % test_name)
		fail_count += 1


func _init():
	print("=== UnitLoadoutResolver Test ===")
	call_deferred("_run_tests")


func _run_tests():
	await root.get_tree().process_frame

	_test_tutorial_battlewagon()
	_test_additive_vs_replacement()
	_test_safe_fallbacks()
	_test_slugging()

	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	quit(1 if fail_count > 0 else 0)


# The reported bug: pressing Y on the tutorial Battlewagon listed every weapon
# a Battlewagon *could* take.
func _test_tutorial_battlewagon() -> void:
	print("\n--- Tutorial Battlewagon ---")
	var f := FileAccess.open(TUTORIAL_ARMY, FileAccess.READ)
	if f == null:
		_assert(false, "tutorial_orks.json readable")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_assert(false, "tutorial_orks.json parses")
		return
	var unit = parsed.get("units", {}).get("U_BATTLEWAGON_T", {})
	_assert(not unit.is_empty(), "tutorial roster has U_BATTLEWAGON_T")
	if unit.is_empty():
		return

	var all_names: Array = []
	for w in unit.get("meta", {}).get("weapons", []):
		all_names.append(str(w.get("name", "")))
	var names := Resolver.get_equipped_weapon_names(unit)
	print("   menu    : %s" % str(all_names))
	print("   equipped: %s" % str(names))

	# Wargear: Deff rolla, Grabbin' klaw, Kannon, Lobba, Wreckin' ball, 'Ard Case.
	for expected in ["Kannon – Frag", "Kannon – Shell", "Lobba", "Deff rolla",
			"Grabbin' klaw", "Wreckin' ball"]:
		_assert(expected in names, "keeps equipped weapon '%s'" % expected)
	# Base kit (implicit, never listed in wargear) must survive.
	_assert("Tracks and wheels" in names, "keeps base-kit weapon 'Tracks and wheels'")
	# Unpicked options must be gone.
	for unequipped in ["Big shoota", "Killkannon", "Zzap gun"]:
		_assert(not (unequipped in names), "drops unequipped option '%s'" % unequipped)


# Additive picks keep the base weapon; a like-for-like swap removes it.
func _test_additive_vs_replacement() -> void:
	print("\n--- Additive vs replacement (single-model units) ---")

	# Warboss: base kit is twin sluggas / kombi-weapon / big choppa; the roster
	# swapped the big choppa for a power klaw, so the big choppa must not show.
	var warboss := {
		"models": [{"id": "m1"}],
		"meta": {
			"name": "Warboss",
			"wargear": ["1x Kombi-weapon", "1x Power klaw", "1x Twin sluggas"],
			"weapons": [
				{"name": "Kombi-weapon", "type": "Ranged"},
				{"name": "Twin sluggas", "type": "Ranged"},
				{"name": "Attack squig", "type": "Melee"},
				{"name": "Big choppa", "type": "Melee"},
				{"name": "Power klaw", "type": "Melee"},
			],
		},
	}
	var wb := Resolver.get_equipped_weapon_names(warboss)
	print("   warboss equipped: %s" % str(wb))
	_assert("Power klaw" in wb, "Warboss keeps its power klaw")
	_assert("Kombi-weapon" in wb and "Twin sluggas" in wb, "Warboss keeps its ranged kit")
	_assert(not ("Big choppa" in wb), "Warboss drops the replaced base big choppa")
	_assert(not ("Attack squig" in wb), "Warboss drops the unpicked attack squig")

	# Warboss in Mega Armour: only its melee is in wargear; the base big shoota
	# has no melee competitor and must stay.
	var wbma := {
		"models": [{"id": "m1"}],
		"meta": {
			"name": "Warboss in Mega Armour",
			"wargear": ["1x 'Uge choppa"],
			"weapons": [
				{"name": "Big shoota", "type": "Ranged"},
				{"name": "Uge choppa", "type": "Melee"},
			],
		},
	}
	var mega := Resolver.get_equipped_weapon_names(wbma)
	print("   mega armour equipped: %s" % str(mega))
	_assert("Uge choppa" in mega, "Mega Armour Warboss keeps 'Uge choppa (apostrophe-insensitive match)")
	_assert("Big shoota" in mega, "Mega Armour Warboss keeps its base big shoota")


func _test_safe_fallbacks() -> void:
	print("\n--- Safe fallbacks ---")

	# No wargear at all -> show the datasheet untouched.
	var no_wargear := {
		"models": [{"id": "m1"}],
		"meta": {
			"name": "Battlewagon",
			"weapons": [
				{"name": "Killkannon", "type": "Ranged"},
				{"name": "Tracks and wheels", "type": "Melee"},
			],
		},
	}
	_assert(Resolver.get_equipped_weapon_names(no_wargear).size() == 2,
		"no wargear -> full menu returned")

	# Wargear naming nothing on this datasheet -> show the datasheet untouched.
	var unrelated := {
		"models": [{"id": "m1"}],
		"meta": {
			"name": "Battlewagon",
			"wargear": ["1x 'Ard Case"],
			"weapons": [
				{"name": "Killkannon", "type": "Ranged"},
				{"name": "Tracks and wheels", "type": "Melee"},
			],
		},
	}
	_assert(Resolver.get_equipped_weapon_names(unrelated).size() == 2,
		"unmatched wargear -> full menu returned")

	# No weapons -> empty, no crash.
	_assert(Resolver.get_equipped_weapons({"meta": {"name": "X"}}).is_empty(),
		"weaponless unit -> empty list")
	_assert(Resolver.get_equipped_weapons({}).is_empty(), "empty unit dict -> empty list")


func _test_slugging() -> void:
	print("\n--- Name normalisation ---")
	var cases := {
		"Grabbin' klaw": "grabbin-klaw",
		"'Ard Case": "ard-case",
		"Tracks and wheels": "tracks-and-wheels",
		"Kustom mega-blasta": "kustom-mega-blasta",
		"Kannon – Frag": "kannon-frag",
	}
	for raw in cases:
		_assert(Resolver._slug(raw) == cases[raw],
			"_slug('%s') == '%s' (got '%s')" % [raw, cases[raw], Resolver._slug(raw)])
	_assert(Resolver._base_name("Kannon – Frag") == "Kannon", "_base_name strips the profile suffix")
	_assert(Resolver._base_name("Big shoota") == "Big shoota", "_base_name leaves plain names alone")
