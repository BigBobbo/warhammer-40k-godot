extends SceneTree

# ISS-003: structured weapon-ability schema + AbilityRegistry.
#
# Checks:
#   A) Registry parses every legacy token form correctly.
#   B) Converted army JSONs: every weapon's structured `abilities` validates
#      cleanly AND is exactly what the registry parses from its legacy
#      `special_rules` string (converter parity).
#   C) A misspelled ability id is a validation error, and ArmyListManager
#      refuses to load an army containing one.
#   D) Golden equivalence: a weapon defined ONLY by structured abilities
#      produces the same profile, helper outputs, and resolve_shoot dice as
#      the same weapon defined ONLY by the legacy string.
#
# Usage: godot --headless --path . -s tests/test_iss003_ability_schema.gd

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
	print("\n=== test_iss003_ability_schema ===\n")
	_test_registry_parsing()
	_test_army_files_parity()
	_test_bad_id_rejected()
	_test_golden_equivalence()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# -- A ------------------------------------------------------------------------

func _test_registry_parsing() -> void:
	print("\n-- A: registry token parsing --")
	_check("anti-infantry 4+",
		AbilityRegistry.parse_token("Anti-Infantry 4+") == {"id": "anti", "keyword": "INFANTRY", "threshold": 4})
	_check("rapid fire 2",
		AbilityRegistry.parse_token("rapid fire 2") == {"id": "rapid_fire", "x": 2})
	_check("sustained hits d3",
		AbilityRegistry.parse_token("sustained hits d3") == {"id": "sustained_hits", "x": 3, "dice": true})
	_check("sustained hits 1",
		AbilityRegistry.parse_token("Sustained Hits 1") == {"id": "sustained_hits", "x": 1})
	_check("melta 2",
		AbilityRegistry.parse_token("melta 2") == {"id": "melta", "x": 2})
	_check("twin-linked",
		AbilityRegistry.parse_token(" Twin-Linked ") == {"id": "twin_linked"})
	_check("unknown token flagged",
		AbilityRegistry.parse_token("sustaned hits 1").get("id") == "__unknown__")
	var multi = AbilityRegistry.parse_special_rules("pistol, twin-linked")
	_check("multi-token string", multi.size() == 2 and multi[0].id == "pistol" and multi[1].id == "twin_linked")
	_check("validate accepts good entries",
		AbilityRegistry.validate([{"id": "rapid_fire", "x": 1}, {"id": "anti", "keyword": "VEHICLE", "threshold": 4}]).is_empty())
	_check("round-trip display string",
		AbilityRegistry.to_display_string(AbilityRegistry.parse_special_rules("anti-infantry 4+, devastating wounds, rapid fire 1"))
			== "anti-infantry 4+, devastating wounds, rapid fire 1")

# -- B ------------------------------------------------------------------------

func _test_army_files_parity() -> void:
	print("\n-- B: army files validate + converter parity --")
	var dir = DirAccess.open("res://armies")
	if dir == null:
		_check("armies dir readable", false)
		return
	var files_checked := 0
	var weapons_with_abilities := 0
	var validation_errors: Array = []
	var parity_errors: Array = []
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			files_checked += 1
			var f = FileAccess.open("res://armies/" + entry, FileAccess.READ)
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary:
				for unit_id in data.get("units", {}):
					for w in data.units[unit_id].get("meta", {}).get("weapons", []):
						var abilities = w.get("abilities", [])
						if not abilities is Array or abilities.is_empty():
							continue
						weapons_with_abilities += 1
						for err in AbilityRegistry.validate(abilities):
							validation_errors.append("%s/%s: %s" % [entry, w.get("name"), err])
						var parsed = AbilityRegistry.parse_special_rules(str(w.get("special_rules", "")))
						if AbilityRegistry.to_display_string(parsed) != AbilityRegistry.to_display_string(abilities):
							parity_errors.append("%s/%s" % [entry, w.get("name")])
		entry = dir.get_next()
	dir.list_dir_end()
	_check("scanned army files (%d) with structured weapons (%d)" % [files_checked, weapons_with_abilities],
		files_checked > 0 and weapons_with_abilities > 100)
	_check("zero validation errors", validation_errors.is_empty(), str(validation_errors.slice(0, 3)))
	_check("converter parity: abilities == parse(special_rules)", parity_errors.is_empty(), str(parity_errors.slice(0, 3)))

# -- C ------------------------------------------------------------------------

func _test_bad_id_rejected() -> void:
	print("\n-- C: misspelled ability id fails the load --")
	var errs = AbilityRegistry.validate([{"id": "sustaned_hits", "x": 1}])
	_check("validate flags unknown id", not errs.is_empty(), str(errs))
	errs = AbilityRegistry.validate([{"id": "rapid_fire", "y": 1}])
	_check("validate flags unexpected param", not errs.is_empty(), str(errs))

	var alm = root.get_node_or_null("ArmyListManager")
	if alm == null:
		_check("ArmyListManager autoload reachable", false)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://armies"))
	var bad = {
		"faction": {"name": "Bad", "points": 0},
		"units": {
			"U_BAD": {
				"meta": {
					"name": "Bad Unit", "keywords": ["INFANTRY"],
					"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1},
					"weapons": [{
						"name": "Typo Gun", "type": "Ranged", "range": "24",
						"attacks": "1", "ballistic_skill": "4", "strength": "4",
						"ap": "0", "damage": "1",
						"special_rules": "sustaned hits 1",
						"abilities": [{"id": "sustaned_hits", "x": 1}]
					}],
					"abilities": []
				},
				"models": []
			}
		}
	}
	var f = FileAccess.open("user://armies/iss003_bad_test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(bad, "  "))
	f.close()
	var result = alm.load_army_list("iss003_bad_test", 1)
	_check("ArmyListManager refuses army with unknown ability id",
		result is Dictionary and result.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://armies/iss003_bad_test.json"))

# -- D ------------------------------------------------------------------------

const RULES_STRING := "anti-infantry 4+, sustained hits d3, melta 2, rapid fire 1, twin-linked, devastating wounds"

func _make_board(structured: bool) -> Dictionary:
	var weapon = {
		"name": "Golden Gun", "type": "Ranged", "range": "24",
		"attacks": "2", "ballistic_skill": "3", "strength": "5",
		"ap": "-1", "damage": "1"
	}
	if structured:
		weapon["abilities"] = AbilityRegistry.parse_special_rules(RULES_STRING)
	else:
		weapon["special_rules"] = RULES_STRING
	var shooter_models = []
	for i in range(3):
		shooter_models.append({
			"id": "ms%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(6):
		target_models.append({
			"id": "mt%d" % i, "position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1},
					"weapons": [weapon]},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}

func _test_golden_equivalence() -> void:
	print("\n-- D: structured-only weapon == string-only weapon --")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		return
	var board_str = _make_board(false)
	var board_struct = _make_board(true)

	var prof_str = rules.get_weapon_profile("Golden Gun", board_str)
	var prof_struct = rules.get_weapon_profile("Golden Gun", board_struct)
	_check("profiles found", not prof_str.is_empty() and not prof_struct.is_empty())
	_check("synthesized special_rules matches legacy string",
		prof_struct.get("special_rules") == prof_str.get("special_rules"),
		"%s vs %s" % [prof_struct.get("special_rules"), prof_str.get("special_rules")])
	_check("structured abilities attached to both profiles",
		AbilityRegistry.to_display_string(prof_str.get("abilities", []))
			== AbilityRegistry.to_display_string(prof_struct.get("abilities", [])))

	# Helper equivalence across both forms
	var pairs = [
		["sustained", rules.get_sustained_hits_value("Golden Gun", board_str), rules.get_sustained_hits_value("Golden Gun", board_struct)],
		["devastating", rules.has_devastating_wounds("Golden Gun", board_str), rules.has_devastating_wounds("Golden Gun", board_struct)],
		["twin-linked", rules.has_twin_linked("Golden Gun", board_str), rules.has_twin_linked("Golden Gun", board_struct)],
		["rapid fire", rules.is_rapid_fire_weapon("Golden Gun", board_str), rules.is_rapid_fire_weapon("Golden Gun", board_struct)],
	]
	for p in pairs:
		_check("helper parity: %s" % p[0], p[1] == p[2], "%s vs %s" % [str(p[1]), str(p[2])])

	# Full resolve_shoot with identical seed must produce identical dice.
	var action = {
		"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Golden Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2"], "attacks_override": 6
		}]}
	}
	rules.set_test_seed(424242)
	var res_str = rules.resolve_shoot(action, board_str, rules.RNGService.new())
	rules.set_test_seed(424242)
	var res_struct = rules.resolve_shoot(action, board_struct, rules.RNGService.new())
	_check("resolve_shoot success on both",
		res_str.get("success", false) and res_struct.get("success", false))
	_check("identical dice sequences",
		JSON.stringify(res_str.get("dice", [])) == JSON.stringify(res_struct.get("dice", [])))
	_check("identical state diffs",
		JSON.stringify(res_str.get("diffs", [])) == JSON.stringify(res_struct.get("diffs", [])))
