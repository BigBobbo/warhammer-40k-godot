extends SceneTree

# MA-LOADOUT: a roster's wargear line names the BASE weapon, the datasheet names
# the PROFILE — match them, or a dual-profile model loses a gun.
#
# Reported 2026-08-03: a 5-model Allarus Custodians squad 16.6" from a Stormboyz
# mob could only assign its 18" balistus grenade launcher. Every Allarus carries
# a balistus grenade launcher AND a castellan axe / guardian spear, whose 24"
# ranged profile should also have been offered.
#
# Root cause: meta.weapons lists a dual-profile weapon with a profile suffix
# ("Guardian spear – Ranged", "Castellan axe – Ranged") while the roster's
# wargear says "5x Guardian spear". _resolve_type_loadout compared the two by
# exact string, so the spear/axe never reached the counts — leaving
# {balistus: 5} against 5 models, which reads as CASE A ("exactly one gun per
# model") and stamped ranged_loadout = [balistus] on every model.
#
# What this pins:
#   * "Nx <base name>" counts towards the suffixed datasheet weapon, so a model
#     carrying two guns is offered both
#   * roster casing does not matter ("5x Castellan Axe" -> "Castellan axe – Ranged")
#   * a base name shared by two profiles of ONE weapon (Gork's Klaw – Strike /
#     – Sweep) stays unreadable rather than being collapsed onto one profile
#   * resolution still never invents a weapon the model_profiles forbid
#   * a save stamped by an older resolver is re-resolved instead of keeping the
#     truncated loadout forever
#   * the real custodes_lions roster offers the Allarus squad both guns
#
# Usage: godot --headless --path 40k --script tests/test_dual_profile_wargear_loadout.gd

var passed := 0
var failed := 0
var RE = null  # RulesEngine autoload, fetched at runtime (not a parse-time identifier under -s)


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)


# An Allarus-shaped squad: N models, each with a balistus grenade launcher plus
# one dual-profile weapon named `big_weapon` ("Castellan axe" / "Guardian spear").
func _allarus(big_weapon: String, wargear: Array, n: int = 5) -> Dictionary:
	var models := []
	for i in range(n):
		models.append({
			"id": "m%d" % i, "position": {"x": 0, "y": float(i * 45)},
			"base_mm": 40, "base_type": "circular", "alive": true,
			"wounds": 4, "current_wounds": 4
		})
	return {
		"id": "U_ALLARUS_T", "owner": 1, "status": 3,
		"meta": {
			"name": "Allarus Custodians",
			"keywords": ["INFANTRY", "TERMINATOR"],
			"stats": {"toughness": 7, "save": 2, "wounds": 4},
			"wargear": wargear,
			"weapons": [
				{"name": "Balistus grenade launcher", "type": "Ranged", "range": "18",
					"attacks": "D6", "ballistic_skill": "2", "strength": "4", "ap": "-1",
					"damage": "1", "special_rules": "blast"},
				{"name": "%s – Ranged" % big_weapon, "type": "Ranged", "range": "24",
					"attacks": "2", "ballistic_skill": "2", "strength": "4", "ap": "-1",
					"damage": "2", "special_rules": "assault"},
				{"name": "%s – Melee" % big_weapon, "type": "Melee", "range": "Melee",
					"attacks": "4", "weapon_skill": "2", "strength": "9", "ap": "-1",
					"damage": "3", "special_rules": ""}
			]
		},
		"models": models
	}


func _ranged_names(unit: Dictionary) -> Array:
	var board = {"units": {unit["id"]: unit}}
	var mw = RE.get_unit_weapons(unit["id"], board)
	var out := []
	for mid in mw:
		out.append(mw[mid])
	return out


func _load_json(path: String):
	var fa = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var txt = fa.get_as_text()
	fa.close()
	return JSON.parse_string(txt)


func _run():
	if passed > 0 or failed > 0:
		return
	RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		_check("RulesEngine autoload present", false)
		quit(1)
		return

	print("\n=== MA-LOADOUT: dual-profile wargear counts ===\n")

	# --- 1: the reported bug — "5x Castellan axe" must reach the 24" profile ---
	print("--- 1: base-name wargear counts towards the suffixed datasheet weapon ---")
	var axe = _allarus("Castellan axe", ["5x Balistus grenade launcher", "5x Castellan axe"])
	var per_model = _ranged_names(axe)
	_check("5 models report a loadout", per_model.size() == 5, str(per_model))
	var all_two := true
	for ids in per_model:
		if ids.size() != 2:
			all_two = false
	_check("every Allarus is offered BOTH ranged guns", all_two, str(per_model))
	var first = per_model[0] if per_model.size() > 0 else []
	_check("balistus offered", RE._generate_weapon_id("Balistus grenade launcher", "Ranged") in first, str(first))
	_check("castellan axe (24\") offered", RE._generate_weapon_id("Castellan axe – Ranged", "Ranged") in first, str(first))
	# The melee half of the same weapon must still be the model's melee gun.
	# NOTE: get_unit_melee_weapons keys by model INDEX ("m0"…) and returns weapon
	# NAMES, unlike get_unit_weapons which returns generated ids.
	var mboard = {"units": {axe["id"]: axe}}
	var melee = RE.get_unit_melee_weapons(axe["id"], mboard)
	var melee_ok := true
	for mid in melee:
		if melee[mid] != ["Castellan axe – Melee"]:
			melee_ok = false
	_check("castellan axe melee profile still offered", melee_ok and melee.size() == 5, str(melee))

	# --- 2: roster casing must not matter ---
	print("\n--- 2: roster casing ('Castellan Axe') still matches ---")
	var cased = _allarus("Castellan axe", ["5x Balistus grenade launcher", "5x Castellan Axe"])
	var cased_ok := true
	for ids in _ranged_names(cased):
		if ids.size() != 2:
			cased_ok = false
	_check("mixed-case wargear resolves the same", cased_ok, str(_ranged_names(cased)))

	# --- 3: guardian spear variant (the shipped custodes_lions roster) ---
	print("\n--- 3: guardian spear variant ---")
	var spear = _allarus("Guardian spear", ["5x Balistus grenade launcher", "5x Guardian spear"])
	var spear_ok := true
	for ids in _ranged_names(spear):
		if ids.size() != 2:
			spear_ok = false
	_check("spear squad offered both guns", spear_ok, str(_ranged_names(spear)))

	# --- 4: an AMBIGUOUS base name must not be collapsed onto one profile ---
	# "1x Gork's Klaw" cannot pick between "– Strike" and "– Sweep"; the unit
	# falls through to the datasheet kit exactly as it did before this change.
	print("\n--- 4: two profiles of ONE weapon stay unreadable by count ---")
	var ghaz = {
		"id": "U_GHAZ_T", "owner": 1, "status": 3,
		"meta": {
			"name": "Ghazghkull Thraka", "keywords": ["INFANTRY", "CHARACTER"],
			"stats": {"toughness": 9, "save": 2, "wounds": 12},
			"wargear": ["1x Gork's Klaw", "1x Mork's Roar", "1x Makari's Stabba"],
			"model_profiles": {
				"ghazghkull": {"label": "Ghazghkull Thraka",
					"weapons": ["Mork's Roar", "Gork's Klaw – Strike", "Gork's Klaw – Sweep"]},
				"makari": {"label": "Makari", "weapons": ["Makari's stabba"]}
			},
			"weapons": [
				{"name": "Mork's Roar", "type": "Ranged", "range": "18", "attacks": "D6",
					"ballistic_skill": "5", "strength": "5", "ap": "-1", "damage": "2", "special_rules": ""},
				{"name": "Gork's Klaw – Strike", "type": "Melee", "range": "Melee", "attacks": "6",
					"weapon_skill": "2", "strength": "14", "ap": "-3", "damage": "3", "special_rules": ""},
				{"name": "Gork's Klaw – Sweep", "type": "Melee", "range": "Melee", "attacks": "12",
					"weapon_skill": "2", "strength": "8", "ap": "-2", "damage": "1", "special_rules": ""},
				{"name": "Makari's stabba", "type": "Melee", "range": "Melee", "attacks": "2",
					"weapon_skill": "5", "strength": "3", "ap": "0", "damage": "1", "special_rules": ""}
			]
		},
		"models": [
			{"id": "m1", "model_type": "ghazghkull", "alive": true, "wounds": 12,
				"current_wounds": 12, "base_mm": 50, "position": {"x": 0, "y": 0}},
			{"id": "m2", "model_type": "makari", "alive": true, "wounds": 1,
				"current_wounds": 1, "base_mm": 25, "position": {"x": 0, "y": 40}}
		]
	}
	var gboard = {"units": {"U_GHAZ_T": ghaz}}
	# Keyed by model INDEX: m0 = Ghazghkull, m1 = Makari.
	var gmelee = RE.get_unit_melee_weapons("U_GHAZ_T", gboard)
	_check("Ghazghkull keeps BOTH klaw profiles",
		"Gork's Klaw – Strike" in gmelee.get("m0", []) and "Gork's Klaw – Sweep" in gmelee.get("m0", []),
		str(gmelee))
	_check("Ghazghkull was NOT handed Makari's stabba",
		not ("Makari's stabba" in gmelee.get("m0", [])), str(gmelee))
	_check("Makari keeps only his stabba", gmelee.get("m1", []) == ["Makari's stabba"], str(gmelee))

	# --- 5: a save stamped by an OLDER resolver is re-resolved ---
	print("\n--- 5: stale stamp from an older resolver is discarded ---")
	var stale = _allarus("Castellan axe", ["5x Balistus grenade launcher", "5x Castellan axe"])
	stale["_loadout_version"] = 2
	stale["_loadout_checked"] = true
	for m in stale["models"]:
		m["ranged_loadout"] = ["Balistus grenade launcher"]  # what v2 wrongly stamped
	var stale_ok := true
	for ids in _ranged_names(stale):
		if ids.size() != 2:
			stale_ok = false
	_check("truncated v2 loadout is re-resolved to both guns", stale_ok, str(_ranged_names(stale)))
	_check("re-resolved unit is stamped at the current version",
		int(stale.get("_loadout_version", 0)) == RE.LOADOUT_RESOLVER_VERSION,
		str(stale.get("_loadout_version", 0)))
	# A unit already at the current version keeps its stamp untouched.
	var current = _allarus("Castellan axe", ["5x Balistus grenade launcher", "5x Castellan axe"])
	current["_loadout_version"] = RE.LOADOUT_RESOLVER_VERSION
	for m in current["models"]:
		m["ranged_loadout"] = ["Balistus grenade launcher"]
	var kept := true
	for ids in _ranged_names(current):
		if ids.size() != 1:
			kept = false
	_check("an up-to-date stamp is NOT re-run", kept, str(_ranged_names(current)))

	# --- 6: the shipped roster the bug was reported against ---
	print("\n--- 6: res://armies/custodes_lions.json Allarus squad ---")
	var data = _load_json("res://armies/custodes_lions.json")
	if typeof(data) != TYPE_DICTIONARY:
		_check("custodes_lions.json loads", false)
	else:
		var unit = data.get("units", {}).get("U_ALLARUS_CUSTODIANS_A", {})
		_check("Allarus squad present in roster", not unit.is_empty())
		if not unit.is_empty():
			var board = {"units": {"U_ALLARUS_CUSTODIANS_A": unit}}
			var mw = RE.get_unit_weapons("U_ALLARUS_CUSTODIANS_A", board)
			var roster_ok: bool = mw.size() == 5
			for mid in mw:
				if mw[mid].size() != 2:
					roster_ok = false
			_check("every roster Allarus offers 2 ranged guns", roster_ok, str(mw))

	print("\n=== test_dual_profile_wargear_loadout: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
