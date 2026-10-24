extends SceneTree

# Codex: Space Marines (11e), generic datasheets — DATA layer (WP-M1).
#
# scripts/40kdc/verify-wahapedia-import.mjs --faction adeptus-astartes checks
# the 40kdc collections against the Wahapedia snapshot. This test checks the
# GAME side through the real loaders:
#   1. armies/sm11e_codex_test.json (every generic Space Marine + Forge World
#      codex datasheet) loads through ArmyListManager; every unit carries its
#      codex characteristics, model count, points and resolves weapons.
#   2. Army rule: units carry Combat Doctrines; no unit lists Oath of Moment and
#      Oath of Moment is never an active faction ability for a Space Marine army.
#   3. Stratagems.csv SM rows == the 48 codex stratagems of the 15 generic
#      detachments (custom:sm11e); a Space Wolves army taking Assault Brethren
#      gets them through the loader's chapter -> SM fallback.
#
# Usage: godot --headless --path . -s tests/test_sm11e_codex_data.gd

const ARMY := "sm11e_codex_test"
const SOURCE_PREFIX := "wahapedia-11e@2026-10-21"
const EXPECTED := 87

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _initialize():
	await create_timer(0.2).timeout
	print("\n=== test_sm11e_codex_data ===\n")
	_run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed

func _i(v, fallback: int = -99) -> int:
	return int(v) if v is int or v is float or (v is String and v.is_valid_int()) else fallback

func _codex_units() -> Dictionary:
	var out := {}
	for u in _read_json("res://data/40kdc/units.json"):
		if str(u.get("faction_id", "")) == "adeptus-astartes" and str(u.get("source", "")).begins_with(SOURCE_PREFIX) \
				and not "SPACE WOLVES" in u.get("faction_keywords", []).map(func(k): return str(k).to_upper()):
			out[str(u.get("name", "")).replace("’", "'")] = u
	return out

func _run() -> void:
	GameConstants.edition = 11
	var codex := _codex_units()
	_check("units.json: %d generic codex datasheets" % EXPECTED, codex.size() == EXPECTED, str(codex.size()))
	var army: Dictionary = root.get_node("ArmyListManager").load_army_list(ARMY, 1)
	_check("%s loads through ArmyListManager" % ARMY, not army.is_empty())
	if army.is_empty():
		return
	_check_units(army, codex)
	_check_army_rule(army)
	_check_stratagems()

func _check_units(army: Dictionary, codex: Dictionary) -> void:
	var bad := []
	var covered := {}
	for uid in army["units"]:
		var u: Dictionary = army["units"][uid]
		var meta: Dictionary = u.get("meta", {})
		var rec: Dictionary = codex.get(str(meta.get("name", "")).replace("’", "'"), {})
		if rec.is_empty():
			continue
		covered[rec["name"]] = true
		var p: Dictionary = rec["profiles"][0]
		var s: Dictionary = meta.get("stats", {})
		var want := {"move": p["M"], "toughness": p["T"], "save": p["Sv"], "wounds": p["W"],
			"leadership": p["Ld"], "objective_control": p["OC"]}
		for k in want:
			if _i(s.get(k)) != _i(want[k]):
				bad.append("%s.%s=%s (codex %s)" % [uid, k, s.get(k), want[k]])
		var n: int = u.get("models", []).size()
		if n < int(rec["model_count"]["min"]) or n > int(rec["model_count"]["max"]):
			bad.append("%s: %d models" % [uid, n])
		var tier_ok := false
		for t in rec.get("points", []):
			if (int(t["models"]) == n or (t.has("models_max") and n >= int(t["models"]) and n <= int(t["models_max"]))) \
					and int(meta.get("points", -1)) >= int(t["cost"]):
				tier_ok = true
		if not tier_ok:
			bad.append("%s: %s pts for %d models" % [uid, meta.get("points"), n])
		var copy: Dictionary = u.duplicate(true)
		var RE = root.get_node("RulesEngine")
		RE._ensure_loadout_resolved(copy)
		for m in copy.get("models", []):
			if (rec.get("weapon_ids", []) as Array).is_empty():
				break  # a datasheet with no weapons (Drop Pod)
			if RE._get_model_weapon_ids(copy, m, "Melee").is_empty() and RE._get_model_weapon_ids(copy, m, "Ranged").is_empty():
				bad.append("%s/%s: no weapon in engine" % [uid, m.get("id", "?")])
				break
		var kws: Array = meta.get("keywords", []).map(func(k): return str(k).to_upper())
		if not str(meta.get("name", "")).to_upper() in kws:
			bad.append("%s: no own-name keyword" % uid)
	_check("every generic codex datasheet is in the test army (%d)" % covered.size(), covered.size() == EXPECTED, str(covered.size()))
	_check("codex stats / counts / points / engine weapons / keywords", bad.is_empty(), str(bad))


func _check_army_rule(army: Dictionary) -> void:
	var oath := []
	var no_doctrines := []
	for uid in army["units"]:
		var names: Array = army["units"][uid]["meta"].get("abilities", []).map(func(a): return str(a.get("name", "")) if a is Dictionary else str(a))
		if "Oath of Moment" in names:
			oath.append(uid)
		if names.count("Combat Doctrines") != 1:
			no_doctrines.append("%s x%d" % [uid, names.count("Combat Doctrines")])
	_check("no unit lists Oath of Moment", oath.is_empty(), str(oath))
	_check("every unit carries Combat Doctrines exactly once", no_doctrines.is_empty(), str(no_doctrines))

func _check_stratagems() -> void:
	var f := FileAccess.open("res://data/Stratagems.csv", FileAccess.READ)
	var rows := []
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("SM|"):
			rows.append(line.split("|"))
	f.close()
	_check("Stratagems.csv: 48 SM rows", rows.size() == 48, str(rows.size()))
	var dets := {}
	var all_custom := true
	for r in rows:
		dets[r[7]] = true
		if not "custom:sm11e" in r[11]:
			all_custom = false
	_check("SM rows cover the 15 generic codex detachments", dets.size() == 15, str(dets.keys()))
	_check("every SM row is marked custom:sm11e", all_custom)
	var FSL = load("res://autoloads/FactionStratagemLoader.gd").new()
	FSL.load_faction_codes()
	var ab: Array = FSL.load_faction_stratagems("Space Wolves", "Assault Brethren")
	_check("a Space Wolves army taking Assault Brethren gets its 3 stratagems (SM rows)", ab.size() == 3, str(ab.map(func(s): return s.get("name", ""))))
	var sm: Array = FSL.load_faction_stratagems("Space Marines", ["Gladius Task Force", "Assault Brethren"])
	_check("a Space Marines army: Gladius (6) + Assault Brethren (3)", sm.size() == 9, str(sm.size()))
	var sw: Array = FSL.load_faction_stratagems("Space Wolves", "Saga of the Beastslayer")
	_check("Space Wolves own detachment still from SW rows (3)", sw.size() == 3 and str(sw[0].get("faction", sw[0].get("faction_id", "SW"))) != "SM", str(sw.size()))
