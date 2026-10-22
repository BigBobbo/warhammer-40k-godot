extends SceneTree

# Codex: Space Marines (11e), Space Wolves scope — DATA layer (WP-S1).
#
# scripts/40kdc/verify-wahapedia-import.mjs --faction adeptus-astartes checks
# the 40kdc collections against the Wahapedia snapshot. This test checks the
# GAME side through the real loaders:
#   1. armies/sw11e_codex_test.json (every Space Wolves datasheet, plus a
#      second copy of each datasheet with a wargear option taken) loads
#      through ArmyListManager; every codex unit carries its codex
#      characteristics, model count, wounds, points and resolves weapons.
#   2. Wargear options resolve PER MODEL in the engine (Grey Hunter Pack
#      Leader's Power Fist + Plasma Pistol, Thunderwolf boltgun + storm
#      shield models, Terminator assault cannons, Venerable Dreadnought
#      Fenrisian Great Axe, ...).
#   3. Army rule: units of a Space Wolves army carry Combat Doctrines, not
#      the index Oath of Moment.
#   4. Stratagems.csv SW rows == the 12 codex stratagems of the three Space
#      Wolves detachments (custom:sw11e); the pre-codex Space Wolves
#      detachments are gone from Detachments.csv.
#
# Usage: godot --headless --path . -s tests/test_sw11e_codex_data.gd

const ARMY := "sw11e_codex_test"
const SOURCE_PREFIX := "wahapedia-11e@"

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
	print("\n=== test_sw11e_codex_data ===\n")
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
		if str(u.get("faction_id", "")) == "adeptus-astartes" and str(u.get("source", "")).begins_with(SOURCE_PREFIX):
			out[str(u.get("name", ""))] = u
	return out

func _run() -> void:
	GameConstants.edition = 11
	var codex := _codex_units()
	_check("units.json: 21 Space Wolves codex datasheets", codex.size() == 21, str(codex.size()))
	var army: Dictionary = root.get_node("ArmyListManager").load_army_list(ARMY, 1)
	_check("%s loads through ArmyListManager" % ARMY, not army.is_empty())
	if army.is_empty():
		return
	_check_units(army, codex)
	_check_wargear(army)
	_check_army_rule(army)
	_check_spot_values(army)
	_check_stratagems()

func _check_units(army: Dictionary, codex: Dictionary) -> void:
	var bad := []
	var covered := {}
	for uid in army["units"]:
		var u: Dictionary = army["units"][uid]
		var meta: Dictionary = u.get("meta", {})
		var rec: Dictionary = codex.get(str(meta.get("name", "")), {})
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
			if RE._get_model_weapon_ids(copy, m, "Melee").is_empty() and RE._get_model_weapon_ids(copy, m, "Ranged").is_empty():
				bad.append("%s/%s: no weapon in engine" % [uid, m.get("id", "?")])
				break
		var kws: Array = meta.get("keywords", []).map(func(k): return str(k).to_upper())
		if not str(meta.get("name", "")).to_upper() in kws:
			bad.append("%s: no own-name keyword" % uid)
		if not "SPACE WOLVES" in kws:
			bad.append("%s: no SPACE WOLVES keyword" % uid)
	_check("every Space Wolves datasheet is in the test army", covered.size() == 21, str(covered.keys()))
	_check("codex stats / counts / points / engine weapons / keywords", bad.is_empty(), str(bad))

# weapon name -> number of models carrying it (engine view)
func _per_model(army: Dictionary, uid: String, weapon_type: String) -> Dictionary:
	var u: Dictionary = army["units"][uid].duplicate(true)
	var RE = root.get_node("RulesEngine")
	RE._ensure_loadout_resolved(u)
	var out := {}
	for m in u.get("models", []):
		var seen := {}
		for wid in RE._get_model_weapon_ids(u, m, weapon_type):
			var nm := str(wid)
			var cut := nm.find("–")
			if cut > 0:
				nm = nm.substr(0, cut)
			var key := nm.to_lower().replace("_", " ").replace("-", " ").split("   ")[0].trim_suffix(" ranged").trim_suffix(" melee")
			if seen.has(key):
				continue
			seen[key] = true
			out[key] = int(out.get(key, 0)) + 1
	return out

# Hunting Wolf models (W1) that carry no ranged weapon.
func _wolves_unarmed(army: Dictionary, uid: String) -> int:
	var u: Dictionary = army["units"][uid].duplicate(true)
	var RE = root.get_node("RulesEngine")
	RE._ensure_loadout_resolved(u)
	var n := 0
	for m in u.get("models", []):
		if int(m.get("wounds", 0)) == 1 and RE._get_model_weapon_ids(u, m, "Ranged").is_empty():
			n += 1
	return n

func _count(d: Dictionary, needle: String) -> int:
	var n := 0
	for k in d:
		if needle in str(k):
			n += int(d[k])
	return n

func _check_wargear(army: Dictionary) -> void:
	var gh_m := _per_model(army, "U_GREY_HUNTERS_B", "Melee")
	var gh_r := _per_model(army, "U_GREY_HUNTERS_B", "Ranged")
	_check("Grey Hunters: Pack Leader's Power Fist on 1 model, Chainswords on 9",
		_count(gh_m, "power fist") == 1 and _count(gh_m, "chainsword") == 9, str(gh_m))
	_check("Grey Hunters: Plasma Pistol on 1 model, Bolt Pistols on 9",
		_count(gh_r, "plasma pistol") == 1 and _count(gh_r, "bolt pistol") == 9, str(gh_r))
	var gh_default := _per_model(army, "U_GREY_HUNTERS_A", "Melee")
	_check("Grey Hunters (default kit): no Power Fist", _count(gh_default, "power fist") == 0 and _count(gh_default, "chainsword") == 10, str(gh_default))
	var tw_r := _per_model(army, "U_THUNDERWOLF_CAVALRY_B", "Ranged")
	_check("Thunderwolf Cavalry: 2 Boltguns, 2 Plasma Pistols, 2 Bolt Pistols",
		_count(tw_r, "boltgun") == 2 and _count(tw_r, "plasma pistol") == 2 and _count(tw_r, "bolt pistol") == 2, str(tw_r))
	var tm_r := _per_model(army, "U_WOLF_GUARD_TERMINATORS_B", "Ranged")
	var tm_m := _per_model(army, "U_WOLF_GUARD_TERMINATORS_B", "Melee")
	_check("Wolf Guard Terminators (10): 2 Assault Cannons + 2 Power Fists",
		_count(tm_r, "assault cannon") == 2 and _count(tm_m, "power fist") == 2, "%s %s" % [tm_r, tm_m])
	var vd_m := _per_model(army, "U_VENERABLE_DREADNOUGHT_B", "Melee")
	var vd_r := _per_model(army, "U_VENERABLE_DREADNOUGHT_B", "Ranged")
	_check("Venerable Dreadnought: Fenrisian Great Axe replaces Assault Cannon + combat weapon; Heavy Flamer",
		_count(vd_m, "fenrisian great axe") == 1 and _count(vd_r, "assault cannon") == 0 and _count(vd_r, "heavy flamer") == 1, "%s %s" % [vd_m, vd_r])
	var bj_r := _per_model(army, "U_BJORN_THE_FELL_HANDED_B", "Ranged")
	_check("Bjorn: Helfrost Cannon instead of Assault Cannon",
		_count(bj_r, "helfrost cannon") == 1 and _count(bj_r, "assault cannon") == 0, str(bj_r))
	var ws_r := _per_model(army, "U_WOLF_SCOUTS_B", "Ranged")
	_check("Wolf Scouts: 1 Plasma Gun, 1 Thunderclap",
		_count(ws_r, "plasma gun") == 1 and _count(ws_r, "thunderclap") == 1, str(ws_r))
	_check("Wolf Guard Terminators (10): 4 Storm Shields replace 4 Storm Bolters (4 left + 2 Assault Cannons)",
		_count(tm_r, "storm bolter") == 4 and _count(tm_r, "assault cannon") == 2, str(tm_r))
	_check("Wolf Scouts (12 = 1 Pack Leader, 2 Hunting Wolves, 9 Scouts): the wolves carry no gun",
		_count(_per_model(army, "U_WOLF_SCOUTS_A", "Ranged"), "plasma pistol") == 10 and _wolves_unarmed(army, "U_WOLF_SCOUTS_A") == 2,
		str(_per_model(army, "U_WOLF_SCOUTS_A", "Ranged")))
	_check("Wolf Scouts: the Thunderclap goes to a Wolf Scout, not the Hunting Wolf", _wolves_unarmed(army, "U_WOLF_SCOUTS_B") == 1)
	var wl_m := _per_model(army, "U_WOLF_GUARD_BATTLE_LEADER_B", "Melee")
	_check("Wolf Guard Battle Leader: Thunder Hammer", _count(wl_m, "thunder hammer") == 1 and _count(wl_m, "master crafted") == 0, str(wl_m))
	var bc_m := _per_model(army, "U_BLOOD_CLAWS_B", "Melee")
	_check("Blood Claws: Pack Leader's Power Weapon", _count(bc_m, "power weapon") == 1 and _count(bc_m, "chainsword") == 9, str(bc_m))
	# Storm Shield wargear ability listed only when taken
	var names := func(uid): return army["units"][uid]["meta"]["abilities"].map(func(a): return str(a.get("name", "")) if a is Dictionary else str(a))
	_check("Storm Shield ability on the Thunderwolves that took shields, not on the default unit",
		"Storm Shield" in names.call("U_THUNDERWOLF_CAVALRY_B") and not "Storm Shield" in names.call("U_THUNDERWOLF_CAVALRY_A"))
	_check("Blizzard Shield ability on the Venerable Dreadnought that took it",
		"Blizzard Shield" in names.call("U_VENERABLE_DREADNOUGHT_B") and not "Blizzard Shield" in names.call("U_VENERABLE_DREADNOUGHT_A"))
	# points include priced wargear (storm shields)
	_check("Thunderwolf Cavalry 6 models = 230 + priced storm shields",
		int(army["units"]["U_THUNDERWOLF_CAVALRY_B"]["meta"]["points"]) > 230, str(army["units"]["U_THUNDERWOLF_CAVALRY_B"]["meta"]["points"]))

func _check_army_rule(army: Dictionary) -> void:
	var oath := []
	var no_doctrines := []
	for uid in army["units"]:
		var names: Array = army["units"][uid]["meta"].get("abilities", []).map(func(a): return str(a.get("name", "")) if a is Dictionary else str(a))
		if "Oath of Moment" in names:
			oath.append(uid)
		if names.count("Combat Doctrines") != 1:
			no_doctrines.append("%s x%d" % [uid, names.count("Combat Doctrines")])
	_check("no Space Wolves army unit carries the index Oath of Moment", oath.is_empty(), str(oath))
	_check("every unit carries Combat Doctrines exactly once", no_doctrines.is_empty(), str(no_doctrines))

func _check_spot_values(army: Dictionary) -> void:
	var logan: Dictionary = army["units"]["U_LOGAN_GRIMNAR_A"]["meta"]
	_check("Logan Grimnar: T6 W8 Sv2+ 4++, 150 pts",
		_i(logan["stats"]["toughness"]) == 6 and _i(logan["stats"]["wounds"]) == 8 and _i(logan["stats"]["invuln"]) == 4 and _i(logan["points"]) == 150,
		str([logan["stats"], logan["points"]]))
	var gh: Dictionary = army["units"]["U_GREY_HUNTERS_A"]["meta"]
	_check("Grey Hunters: T5 OC3, 10 models 180 pts", _i(gh["stats"]["toughness"]) == 5 and _i(gh["stats"]["objective_control"]) == 3 and _i(gh["points"]) == 180,
		str([gh["stats"], gh["points"]]))
	var ws: Dictionary = army["units"]["U_WOLF_SCOUTS_A"]["meta"]
	_check("Wolf Scouts card shows the Wolf Scout profile (M8 Sv3), not the Hunting Wolf",
		_i(ws["stats"]["move"]) == 8 and _i(ws["stats"]["save"]) == 3, str(ws["stats"]))
	var ulrik_name: String = army["units"]["U_ULRIK_THE_SLAYER_A"]["meta"]["name"]
	_check("Ulrik the Slayer keeps its printed spelling", ulrik_name == "Ulrik the Slayer", ulrik_name)

func _check_stratagems() -> void:
	var cur = _read_json("res://../scripts/40kdc/curated/space_wolves_codex_11e.json")
	var f := FileAccess.open("res://data/Stratagems.csv", FileAccess.READ)
	var rows := []
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("SW|"):
			rows.append(line.split("|"))
	f.close()
	_check("Stratagems.csv: 12 SW rows", rows.size() == 12, str(rows.size()))
	var all_custom := true
	var dets := {}
	for r in rows:
		if not "custom:sw11e" in r[11]:
			all_custom = false
		dets[r[7]] = true
	_check("every SW row is marked custom:sw11e", all_custom)
	_check("SW rows cover the three codex detachments",
		dets.size() == 3 and dets.has("Champions of Fenris") and dets.has("Saga of the Beastslayer") and dets.has("Saga of the Great Wolf"), str(dets.keys()))
	var df := FileAccess.open("res://data/Detachments.csv", FileAccess.READ)
	var stale := []
	while not df.eof_reached():
		var l := df.get_line()
		var parts := l.split("|")
		if parts.size() > 2 and parts[1] == "SW" and parts[2] in ["Saga of the Hunter", "Saga of the Bold", "Legends of Saga and Song", "Veterans of the Fang"]:
			stale.append(parts[2])
	df.close()
	_check("pre-codex Space Wolves detachments gone from Detachments.csv", stale.is_empty(), str(stale))
	var FSL = root.get_node_or_null("FactionStratagemLoader")
	if FSL == null:
		FSL = load("res://autoloads/FactionStratagemLoader.gd").new()
		FSL.load_faction_codes()
	_check("faction 'Space Wolves' maps to stratagem code SW", FSL.get_faction_code("Space Wolves") == "SW")
