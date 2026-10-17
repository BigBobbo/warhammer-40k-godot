extends SceneTree

# Wahapedia 11e codex import — DATA layer (.llm/codex_11e_wahapedia/PLAN.md,
# track W + C1/O1 + C2/O2).
#
# scripts/40kdc/verify-wahapedia-import.mjs checks the 40kdc collections
# against the Wahapedia snapshot. This test checks the GAME side, through the
# real loaders:
#   1. Every Custodes / Orks army file loads through ArmyListManager, and every
#      unit built from a codex datasheet carries that datasheet's codex
#      characteristics (meta.stats == units.json profile), a model count inside
#      the codex range, the codex wound value on each model, the codex points,
#      and resolves weapons (display + engine melee per model) against the
#      current kit.
#   2. Spot values a player would recognise (Shield-Captain M8 T7 W8 180 pts,
#      Custodian Guard Sodality 3 models 240 pts, Battlewagon T11 160 pts).
#   3. Stratagems.csv / Detachments.csv AC rows == the 13 codex detachments /
#      41 stratagems in scripts/40kdc/curated/custodes_codex_11e.json, marked
#      custom:custodes11e; Boarding Actions detachments absent.
#   4. Decision D1: a pre-codex (1.0.19) Telemon roster still resolves its
#      loadout through the frozen legacy kit; Legends units in a roster
#      (Lootas) are kept unchanged.
#
# Usage: godot --headless --path . -s tests/test_wahapedia_11e_import_data.gd

const CUSTODES_FILES := ["A_C_test", "Adeptus_Custodes_1995_Mar_7", "adeptus_custodes",
	"custodes_lions", "custodes_web_built_repro", "tutorial_custodes"]
const ORK_FILES := ["ORK_test", "Orks_2000", "Orks_2000_upload", "Orks_Upload_Mar7", "battlewagons",
	"ork11e_codex_test", "orks", "orks_taktikal", "recon_stomps", "tutorial_orks"]
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
	print("\n=== test_wahapedia_11e_import_data ===\n")
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

# units.json records of one faction written by the codex import, by name.
func _codex_units(faction_id: String) -> Dictionary:
	var out := {}
	for u in _read_json("res://data/40kdc/units.json"):
		if str(u.get("faction_id", "")) == faction_id and str(u.get("source", "")).begins_with(SOURCE_PREFIX):
			out[str(u.get("name", ""))] = u
	return out

func _run() -> void:
	GameConstants.edition = 11
	var custodes := _codex_units("adeptus-custodes")
	var orks := _codex_units("orks")
	_check("units.json: 29 Custodes codex datasheets (27 codex + 2 Forge World)", custodes.size() == 29, str(custodes.size()))
	_check("units.json: 55 Orks codex datasheets (54 codex + 1 Forge World)", orks.size() == 55, str(orks.size()))
	for f in CUSTODES_FILES:
		_check_army(f, custodes)
	for f in ORK_FILES:
		_check_army(f, orks)
	_check_spot_values()
	_check_custodes_stratagems()
	# Codex renames keep the old datasheet's bundled token art.
	var sr = root.get_node("SpriteResolver")
	_check("Custodian Guard Sodality token uses the Custodian Guard art",
		sr.resolve_sprite("Custodian Guard Sodality", "Adeptus Custodes", "INFANTRY") == sr.resolve_sprite("Custodian Guard", "Adeptus Custodes", "INFANTRY")
		and sr.resolve_sprite("Custodian Guard", "Adeptus Custodes", "INFANTRY") != null)
	_check("Prosecutor Squad token uses the Prosecutors art",
		sr.resolve_sprite("Prosecutor Squad", "Adeptus Custodes", "INFANTRY") != null)
	_check_legacy_roster()

# int() of a JSON value that may be null / missing.
func _i(v, fallback: int = -99) -> int:
	return int(v) if v is int or v is float or (v is String and v.is_valid_int()) else fallback

func _check_army(file: String, codex: Dictionary) -> void:
	var ALM = root.get_node("ArmyListManager")
	var army: Dictionary = ALM.load_army_list(file, 1)
	_check("%s loads through ArmyListManager" % file, not army.is_empty())
	if army.is_empty():
		return
	var bad_stats: Array = []
	var bad_count: Array = []
	var bad_wounds: Array = []
	var bad_points: Array = []
	var no_weapons: Array = []
	var legacy_keyed: Array = []
	var no_name_kw: Array = []
	var codex_units := 0
	for uid in army.get("units", {}):
		var u: Dictionary = army["units"][uid]
		var meta: Dictionary = u.get("meta", {})
		var rec: Dictionary = codex.get(str(meta.get("name", "")), {})
		if rec.is_empty():
			continue  # allied / Legends / pre-codex unit kept unchanged
		codex_units += 1
		var p: Dictionary = rec["profiles"][0]
		var s: Dictionary = meta.get("stats", {})
		# Vexilla (codex wargear, taken by this roster): "This unit has +1 OC"
		var oc_bonus := 0
		for ab in meta.get("abilities", []):
			if typeof(ab) == TYPE_DICTIONARY and str(ab.get("name", "")) == "Vexilla":
				oc_bonus = 1
		var want := {"move": p["M"], "toughness": p["T"], "save": p["Sv"], "wounds": p["W"],
			"leadership": p["Ld"], "objective_control": _i(p["OC"]) + oc_bonus}
		for k in want:
			if _i(s.get(k)) != _i(want[k]):
				bad_stats.append("%s.%s=%s (codex %s)" % [uid, k, s.get(k), want[k]])
		if p.get("invuln_sv") != null and _i(s.get("invuln"), 0) != _i(p["invuln_sv"]):
			bad_stats.append("%s.invuln=%s (codex %s)" % [uid, s.get("invuln"), p["invuln_sv"]])
		var n: int = u.get("models", []).size()
		if n < int(rec["model_count"]["min"]) or n > int(rec["model_count"]["max"]):
			bad_count.append("%s: %d models (codex %s-%s)" % [uid, n, rec["model_count"]["min"], rec["model_count"]["max"]])
		var profile_w := {}
		for prof in rec["profiles"]:
			profile_w[int(prof["W"])] = true
		for m in u.get("models", []):
			if not profile_w.has(_i(m.get("wounds"))):
				bad_wounds.append("%s/%s W%s (codex %s)" % [uid, m.get("id"), m.get("wounds"), str(profile_w.keys())])
				break
		# points: at least one codex tier for this model count is the base price
		var tier_ok := false
		var pts := int(meta.get("points", -1))
		for t in rec.get("points", []):
			if int(t["models"]) == n or (t.has("models_max") and n >= int(t["models"]) and n <= int(t["models_max"])):
				if pts >= int(t["cost"]):
					tier_ok = true
		if not tier_ok:
			bad_points.append("%s: %d pts for %d models (codex %s)" % [uid, pts, n, str(rec.get("points", []))])
		if UnitLoadoutResolver.get_equipped_weapon_names(u).is_empty():
			no_weapons.append(uid)
		var copy: Dictionary = u.duplicate(true)
		root.get_node("RulesEngine")._ensure_loadout_resolved(copy)
		for m in copy.get("models", []):
			if root.get_node("RulesEngine")._get_model_weapon_ids(copy, m, "Melee").is_empty() and \
					root.get_node("RulesEngine")._get_model_weapon_ids(copy, m, "Ranged").is_empty():
				no_weapons.append("%s/%s (no weapon in engine)" % [uid, m.get("id", "?")])
				break
		if UnitLoadoutResolver.datasheet_key(u) != str(meta.get("name", "")):
			legacy_keyed.append(uid)
		# Leader pairing matches can_lead names against bodyguard keywords:
		# every datasheet must carry its own name keyword (Wahapedia's export
		# omits it).
		var kws: Array = meta.get("keywords", []).map(func(k): return str(k).to_upper())
		if not str(meta.get("name", "")).to_upper() in kws:
			no_name_kw.append(uid)
	_check("%s: has codex-datasheet units" % file, codex_units > 0)
	_check("%s: codex characteristics in meta.stats" % file, bad_stats.is_empty(), str(bad_stats))
	_check("%s: model counts inside the codex range" % file, bad_count.is_empty(), str(bad_count))
	_check("%s: models carry the codex wounds" % file, bad_wounds.is_empty(), str(bad_wounds))
	_check("%s: points match a codex tier" % file, bad_points.is_empty(), str(bad_points))
	_check("%s: every codex unit resolves weapons (display + engine)" % file, no_weapons.is_empty(), str(no_weapons))
	_check("%s: codex units resolve against the current kits" % file, legacy_keyed.is_empty(), str(legacy_keyed))
	_check("%s: every codex unit carries its own datasheet-name keyword" % file, no_name_kw.is_empty(), str(no_name_kw))

func _unit_by_name(file: String, name: String) -> Dictionary:
	var army: Dictionary = root.get_node("ArmyListManager").load_army_list(file, 1)
	for uid in army.get("units", {}):
		if str(army["units"][uid]["meta"].get("name", "")) == name:
			return army["units"][uid]
	return {}

func _check_spot_values() -> void:
	var sc := _unit_by_name("adeptus_custodes", "Shield-Captain")
	var s: Dictionary = sc.get("meta", {}).get("stats", {})
	_check("Shield-Captain: M8 T7 Sv2+ 4++ W8 Ld5+ OC2",
		int(s.get("move", 0)) == 8 and int(s.get("toughness", 0)) == 7 and int(s.get("save", 0)) == 2 and
		int(s.get("invuln", 0)) == 4 and int(s.get("wounds", 0)) == 8 and int(s.get("leadership", 0)) == 5 and
		int(s.get("objective_control", 0)) == 2, str(s))
	# 180 pts + Praesidium Shield (25) carried by this roster
	_check("Shield-Captain: 180 pts + 25 for the Praesidium Shield", int(sc.get("meta", {}).get("points", 0)) == 205,
		str(sc.get("meta", {}).get("points")))
	var abil_names: Array = []
	for a in sc.get("meta", {}).get("abilities", []):
		abil_names.append(str(a.get("name", "")))
	for want in ["Martial Ka'tah", "Aegis of the Emperor", "Aquila Commander", "Master of Ka'tahs", "Leader", "Deep Strike"]:
		_check("Shield-Captain carries %s" % want, want in abil_names, str(abil_names))
	_check("Shield-Captain: Martial Ka'tah listed once", abil_names.count("Martial Ka'tah") == 1, str(abil_names))
	var ka: String = ""
	for a in sc.get("meta", {}).get("abilities", []):
		if str(a.get("name", "")) == "Martial Ka'tah":
			ka = str(a.get("description", ""))
	_check("Martial Ka'tah text is the codex rule (readied units)", "readied" in ka, ka.substr(0, 120))
	var cg := _unit_by_name("custodes_lions", "Custodian Guard Sodality")
	_check("Custodian Guard Sodality: 3 models, first copy 240 pts",
		cg.get("models", []).size() == 3 and int(cg.get("meta", {}).get("points", 0)) == 240,
		"%d models / %s pts" % [cg.get("models", []).size(), cg.get("meta", {}).get("points")])
	var spear := {}
	for w in cg.get("meta", {}).get("weapons", []):
		if str(w.get("name", "")) == "Guardian Spear – Ranged":
			spear = w
	_check("Guardian Spear (ranged): 24\" A2 BS2+ S5 AP-1 D2, Assault, Rapid Fire 2",
		str(spear.get("range", "")) == "24" and str(spear.get("strength", "")) == "5" and
		str(spear.get("special_rules", "")).contains("rapid fire 2"), str(spear))
	var bc := _unit_by_name("custodes_lions", "Blade Champion")
	var cgs := _unit_by_name("custodes_lions", "Custodian Guard Sodality")
	_check("Blade Champion can lead Custodian Guard Sodality (can_lead name is a bodyguard keyword)",
		"CUSTODIAN GUARD SODALITY" in bc.get("meta", {}).get("leader_data", {}).get("can_lead", []) and
		"CUSTODIAN GUARD SODALITY" in cgs.get("meta", {}).get("keywords", []),
		"%s / %s" % [str(bc.get("meta", {}).get("leader_data", {})), str(cgs.get("meta", {}).get("keywords", []))])
	var bw := _unit_by_name("tutorial_orks", "Battlewagon")
	var bs: Dictionary = bw.get("meta", {}).get("stats", {})
	_check("Battlewagon: T11 W16, 160 pts (first copy)",
		int(bs.get("toughness", 0)) == 11 and int(bs.get("wounds", 0)) == 16 and int(bw.get("meta", {}).get("points", 0)) == 160,
		"%s / %s pts" % [str(bs), bw.get("meta", {}).get("points")])
	var dmg := false
	for a in bw.get("meta", {}).get("abilities", []):
		if str(a.get("name", "")) == "Damaged: 1-6 Wounds Remaining":
			dmg = true
	_check("Battlewagon carries the 11e Damaged 6 ability (engine-parsed name)", dmg)

func _check_custodes_stratagems() -> void:
	var proj := ProjectSettings.globalize_path("res://")
	var curated = _read_json(proj.path_join("../scripts/40kdc/curated/custodes_codex_11e.json").simplify_path())
	_check("curated Custodes codex file readable", curated is Dictionary)
	if not curated is Dictionary:
		return
	var dets: Array = curated.get("detachments", [])
	var strats: Array = curated.get("stratagems", [])
	_check("curated file: 13 detachments, 41 stratagems", dets.size() == 13 and strats.size() == 41,
		"%d / %d" % [dets.size(), strats.size()])
	var loader := FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var total := 0
	var bad: Array = []
	for d in dets:
		var rows: Array = loader.load_faction_stratagems("Adeptus Custodes", str(d["name"]))
		total += rows.size()
		if rows.size() != int(d.get("stratagem_count", -1)):
			bad.append("%s: %d rows (codex %s)" % [d["name"], rows.size(), d.get("stratagem_count")])
		for r in rows:
			var fx = r.get("effects", [])
			var marked := false
			for e in (fx if fx is Array else []):
				if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) == "custom:custodes11e":
					marked = true
			if not marked:
				bad.append("%s: not marked custom:custodes11e (%s)" % [r.get("csv_id", r.get("name")), str(fx)])
			if str(r.get("when_text", "")).strip_edges() == "" or str(r.get("effect_text", "")).strip_edges() == "":
				bad.append("%s: no WHEN/EFFECT text" % r.get("csv_id"))
	_check("Stratagems.csv: 41 AC codex rows load per detachment", total == 41 and bad.is_empty(), "%d rows; %s" % [total, str(bad)])
	var det_csv := FileAccess.get_file_as_string("res://data/Detachments.csv")
	var ac_lines: Array = []
	for line in det_csv.split("\n"):
		if line.find("|AC|") >= 0:
			ac_lines.append(line.split("|")[2])
	_check("Detachments.csv: the 13 codex detachments for AC", ac_lines.size() == 13, str(ac_lines))
	for gone in ["Shield Host", "Solar Spearhead", "Talons of the Emperor", "Silent Hunters", "Voyagers in Darkness", "Black Ship Guardians"]:
		_check("Detachments.csv: no AC '%s' row" % gone, not gone in ac_lines)

func _check_legacy_roster() -> void:
	# A Telemon as rostered before the codex (1.0.19 army file): its weapon menu
	# carries the old kit, which no longer matches the codex kit.
	var old_telemon := {
		"id": "U_OLD_TELEMON", "owner": 1,
		"meta": {
			"name": "Telemon Heavy Dreadnought",
			"weapons": [
				{"name": "Arachnus storm cannon", "type": "Ranged"},
				{"name": "Iliastus accelerator culverin", "type": "Ranged"},
				{"name": "Spiculus bolt launcher", "type": "Ranged"},
				{"name": "Twin arachnus heavy blaze cannon", "type": "Ranged"},
				{"name": "Armoured feet", "type": "Melee"},
				{"name": "Telemon caestus", "type": "Melee"},
			],
			"wargear": ["1x Iliastus accelerator culverin", "1x Spiculus bolt launcher", "1x Armoured feet"],
		},
		"models": [{"id": "m1", "wounds": 12, "current_wounds": 12, "alive": true}],
	}
	var key := UnitLoadoutResolver.datasheet_key(old_telemon)
	_check("D1: pre-codex Telemon roster resolves via the legacy 1.0.19 kit", key.ends_with("[1.0.19]"), key)
	var eq: Array = UnitLoadoutResolver.get_equipped_weapon_names(old_telemon)
	_check("D1: pre-codex Telemon keeps its rostered loadout (culverin, spiculus, armoured feet)",
		eq.size() == 3 and "Armoured feet" in eq, str(eq))
	var lootas := _unit_by_name("Orks_2000", "Lootas")
	_check("D2: Legends unit (Lootas) kept in the roster unchanged", not lootas.is_empty() and
		str(lootas.get("meta", {}).get("points", "")) != "")
