extends SceneTree

# Codex: Orks (11th edition) — DATA layer (.llm/ork_codex_11e_design.md §1-§2).
#
# Checks, through the real loaders:
#   1. Stratagems.csv ORK rows == scripts/40kdc/curated/orks_codex_11e.json
#      (40 rows, 15 detachments; csv id, name, cp, turn, phase, windows,
#      verbatim WHEN/TARGET/EFFECT text, custom:ork11e marker, duration phrase).
#   2. The optional `window` column: parsed into timing.windows (Array[String]),
#      trigger pinned to the first window; rows WITHOUT the field (every
#      non-Ork row — one field fewer than the header) parse exactly as before
#      (no "windows" key) and parse_csv_file tolerates the short rows.
#   3. Detachment-name matching folds typographic vs straight apostrophes.
#   4. Legacy 10e name lists never mark a codex row implemented.
#   5. Detachments.csv ORK rows == the 15 codex detachments.
#   6. Legacy (1.0.19) datasheet kits: rosters with pre-codex weapon names keep
#      their per-model loadouts; rosters built from the codex datasheets use the
#      current kits.
#
# Usage: godot --headless --path . -s tests/test_ork_codex_11e_data.gd

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
	print("\n=== test_ork_codex_11e_data ===\n")
	_run()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _load_curated() -> Dictionary:
	# The curated file lives outside the Godot project (scripts/40kdc/curated);
	# read it by absolute path next to the project root.
	var proj := ProjectSettings.globalize_path("res://")
	var path := proj.path_join("../scripts/40kdc/curated/orks_codex_11e.json").simplify_path()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _run() -> void:
	GameConstants.edition = 11
	var curated := _load_curated()
	_check("curated codex file readable", not curated.is_empty())
	if curated.is_empty():
		return
	var cur_strats: Array = curated.get("stratagems", [])
	var cur_dets: Array = curated.get("detachments", [])
	_check("curated file: 40 stratagems, 15 detachments", cur_strats.size() == 40 and cur_dets.size() == 15,
		"%d / %d" % [cur_strats.size(), cur_dets.size()])

	var loader := FactionStratagemLoaderData.new()
	loader.load_faction_codes()

	# ---- 1. every curated row, through load_faction_stratagems per detachment
	var by_csv := {}
	var det_counts := {}
	for d in cur_dets:
		var det_name := str(d["name"])
		var rows: Array = loader.load_faction_stratagems("Orks", det_name)
		det_counts[det_name] = rows.size()
		for r in rows:
			by_csv[str(r.get("csv_id", ""))] = r
	var expected_counts := {"War Horde": 6, "Madcap Meks": 1, "Wurrband": 0, "Runt Swarm": 3,
		"Wreckas": 3, "Brute Bosses": 0, "Bully Boyz": 3, "Da Big Hunt": 3, "Dread Mob": 3,
		"Shoota Boyz": 3, "Flyboyz": 3, "Kult of Speed": 3, "Blitz Brigade": 3,
		"Green Tide": 3, "Taktikal Brigade": 3}
	for det_name in expected_counts:
		_check("%s loads %d stratagems" % [det_name, expected_counts[det_name]],
			int(det_counts.get(det_name, -1)) == int(expected_counts[det_name]), str(det_counts.get(det_name, -1)))
	_check("40 distinct codex rows loaded", by_csv.size() == 40, str(by_csv.size()))
	var all_rows: Array = loader.load_faction_stratagems("Orks", "")
	_check("Orks with no detachment filter loads exactly the 40 codex rows", all_rows.size() == 40, str(all_rows.size()))

	var turn_ok := 0
	var phase_ok := 0
	var windows_ok := 0
	var text_ok := 0
	var marker_ok := 0
	var cp_ok := 0
	var name_ok := 0
	var trigger_ok := 0
	var duration_ok := 0
	var problems: Array = []
	for cs in cur_strats:
		var csv_id := str(cs["csv_id"])
		if not by_csv.has(csv_id):
			problems.append("missing %s" % csv_id)
			continue
		var s: Dictionary = by_csv[csv_id]
		if str(s["name"]) == str(cs["name"]): name_ok += 1
		else: problems.append("%s name %s" % [csv_id, s["name"]])
		if int(s["cp_cost"]) == int(cs["cp_cost"]): cp_ok += 1
		else: problems.append("%s cp %s" % [csv_id, s["cp_cost"]])
		if str(s["timing"]["turn"]) == str(cs["turn"]): turn_ok += 1
		else: problems.append("%s turn %s" % [csv_id, s["timing"]["turn"]])
		if str(s["timing"]["phase"]) == str(cs["phase"]): phase_ok += 1
		else: problems.append("%s phase %s" % [csv_id, s["timing"]["phase"]])
		var want_windows: Array = cs.get("windows", [])
		var got_windows = s["timing"].get("windows", null)
		if want_windows.is_empty():
			if got_windows == null and not s["timing"].has("windows"): windows_ok += 1
			else: problems.append("%s should have no windows key" % csv_id)
			trigger_ok += 1
		else:
			if typeof(got_windows) == TYPE_ARRAY and got_windows.size() == want_windows.size():
				var same := true
				for i in want_windows.size():
					if str(got_windows[i]) != str(want_windows[i]):
						same = false
				if same and got_windows.is_typed() and got_windows.get_typed_builtin() == TYPE_STRING:
					windows_ok += 1
				else:
					problems.append("%s windows %s" % [csv_id, str(got_windows)])
			else:
				problems.append("%s windows %s" % [csv_id, str(got_windows)])
			if str(s["timing"]["trigger"]) == str(want_windows[0]): trigger_ok += 1
			else: problems.append("%s trigger %s" % [csv_id, s["timing"]["trigger"]])
		# Verbatim text (newlines collapse to single spaces in the one-line CSV).
		var want_when := _norm(str(cs["when"]))
		var want_target := _norm(str(cs["target"]))
		var want_effect := _norm(str(cs["effect"]))
		if s["when_text"] == want_when and s["target_text"] == want_target and str(s["effect_text"]).begins_with(want_effect):
			text_ok += 1
		else:
			problems.append("%s text mismatch: [%s] / [%s] / [%s]" % [csv_id, s["when_text"], s["target_text"], s["effect_text"]])
		var dur = cs.get("duration_phrase", null)
		if dur == null:
			if str(s["effect_text"]) == want_effect: duration_ok += 1
			else: problems.append("%s unexpected duration suffix" % csv_id)
		else:
			if str(s["effect_text"]).ends_with("(Duration: %s.)" % str(dur)): duration_ok += 1
			else: problems.append("%s duration phrase missing" % csv_id)
		var effs: Array = s.get("effects", [])
		if effs.size() == 1 and str(effs[0].get("type", "")) == "custom:ork11e" and s["implemented"] == false:
			marker_ok += 1
		else:
			problems.append("%s effects %s implemented=%s" % [csv_id, str(effs), str(s["implemented"])])
	_check("names (straight apostrophes, uppercase) match curated", name_ok == 40, str(problems))
	_check("cp_cost matches curated", cp_ok == 40)
	_check("turn (your/opponent/either) matches curated", turn_ok == 40)
	_check("phase (incl. shooting_or_fight / movement_or_charge) matches curated", phase_ok == 40)
	_check("timing.windows typed Array[String] == curated windows (panel rows: no key)", windows_ok == 40)
	_check("window rows: trigger pinned to the first window", trigger_ok == 40)
	_check("WHEN/TARGET/EFFECT text verbatim from the curated file", text_ok == 40)
	_check("duration phrase appended exactly where curated says", duration_ok == 40)
	_check("effects_json custom:ork11e and NOT implemented at parse time", marker_ok == 40)
	if not problems.is_empty():
		print("    problems: %s" % str(problems))

	# Spot checks on specific rows.
	var hb: Dictionary = by_csv.get("hulking-brutes-bully-boyz", {})
	_check("HULKING BRUTES keeps the +1CP upgrade text", "+1CP Or:" in str(hb.get("effect_text", "")))
	var dp: Dictionary = by_csv.get("dread-power-dread-mob", {})
	_check("DREAD POWER effect carries 'until the start of your next Command phase' (expiry next_own_command_phase)",
		"until the start of your next command phase" in str(dp.get("effect_text", "")).to_lower())
	var mm: Dictionary = by_csv.get("mind-mostly-on-the-mission-taktikal-brigade", {})
	_check("MIND MOSTLY ON THE MISSION effect carries 'until the end of the turn'",
		"until the end of the turn" in str(mm.get("effect_text", "")).to_lower())
	var gi: Dictionary = by_csv.get("grab-it-wreckas", {})
	_check("GRAB IT keeps its own 'until the end of the turn' (no phrase added)",
		"until the end of the turn" in str(gi.get("effect_text", "")).to_lower() and not "Duration:" in str(gi.get("effect_text", "")))
	var atdt: Dictionary = by_csv.get("armed-to-da-teef-bully-boyz", {})
	_check("ARMED TO DA TEEF has two windows (shoot + fight)",
		atdt.get("timing", {}).get("windows", []) == ["unit_selected_to_shoot", "unit_selected_to_fight"])
	_check("ids: WHERE D'YA FINK keeps a stable straight-apostrophe-free id",
		by_csv.get("where-dya-fink-youre-going-da-big-hunt", {}).get("id", "") == "faction_ork_da_big_hunt_where_dya_fink_youre_going?")
	_check("ids: 'ERE WE GO -> faction_ork_green_tide_ere_we_go",
		by_csv.get("ere-we-go-green-tide", {}).get("id", "") == "faction_ork_green_tide_ere_we_go")
	_check("removed detachment More Dakka! loads nothing", loader.load_faction_stratagems("Orks", "More Dakka!").is_empty())
	_check("removed detachment Speedwaaagh! loads nothing", loader.load_faction_stratagems("Orks", "Speedwaaagh!").is_empty())

	# ---- 2. window column tolerance + non-Ork rows unchanged
	var rows_all = FactionStratagemLoaderData.parse_csv_file("res://data/Stratagems.csv")
	var short_rows := 0
	var ork_with_window := 0
	for r in rows_all:
		if str(r.get("faction_id", "")) == "ORK":
			if r.has("window"):
				ork_with_window += 1
		elif not r.has("window"):
			short_rows += 1
	_check("every ORK row carries the window field", ork_with_window == 40, str(ork_with_window))
	_check("non-Ork rows have one field fewer (no window key) and still parse", short_rows > 1000, str(short_rows))
	var sm_rows: Array = loader.load_faction_stratagems("Space Marines", "Gladius Task Force")
	var sm_any_windows := false
	for r in sm_rows:
		if r["timing"].has("windows"):
			sm_any_windows = true
	_check("Space Marines Gladius rows load with no windows key", sm_rows.size() > 0 and not sm_any_windows, str(sm_rows.size()))

	var tmp := "user://test_ork11e_window_col.csv"
	var fh := FileAccess.open(tmp, FileAccess.WRITE)
	fh.store_string("faction_id|name|id|type|cp_cost|turn|phase|detachment|detachment_id|description|timing|effects_json|window\n")
	fh.store_string("ORK|SHORT ROW|short-row|Rollin’ Deff Stratagem|1|Your turn|Shooting phase|Rollin’ Deff|rollin-deff|<b>WHEN:</b> Your Shooting phase.<br><br><b>TARGET:</b> One ORKS unit.<br><br><b>EFFECT:</b> Nothing.|once-per-phase|\n")
	fh.store_string("ORK|WINDOW ROW|window-row|Rollin’ Deff Stratagem|2|Opponent's turn|Movement or Charge phase|Rollin’ Deff|rollin-deff|<b>WHEN:</b> X.<br><br><b>TARGET:</b> Y.<br><br><b>EFFECT:</b> Z.|once-per-phase|[{\"type\":\"custom:ork11e\"}]| a , b,a \n")
	fh.close()
	var parsed_tmp = FactionStratagemLoaderData.parse_csv_file(tmp)
	_check("parse_csv_file: a row one field short maps every field it has",
		parsed_tmp.size() == 2 and not parsed_tmp[0].has("window") and str(parsed_tmp[0].get("timing", "")) == "once-per-phase")
	var tmp_rows: Array = loader.load_faction_stratagems("Orks", "Rollin' Deff", tmp)
	_check("detachment match folds typographic vs straight apostrophes ('Rollin' Deff' finds 'Rollin’ Deff')",
		tmp_rows.size() == 2, str(tmp_rows.size()))
	if tmp_rows.size() == 2:
		_check("short row: no windows key, legacy trigger inference kept",
			not tmp_rows[0]["timing"].has("windows") and str(tmp_rows[0]["timing"]["trigger"]) == "shooting_phase_active",
			str(tmp_rows[0]["timing"]))
		_check("window value ' a , b,a ' -> ['a','b'] (trimmed, deduped)",
			tmp_rows[1]["timing"].get("windows", []) == ["a", "b"], str(tmp_rows[1]["timing"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# ---- 4. legacy name lists never mark a codex row implemented — only the
	# Ork codex registry (OrkCodex11e group IMPLEMENTED sets) does.
	var SM = root.get_node("StratagemManager")
	var GS = root.get_node("GameState")
	var Codex = load("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
	var saved_factions = GS.state.get("factions", {}).duplicate(true)
	var leaked: Array = []
	var missing: Array = []
	for d in cur_dets:
		GS.state["factions"] = {"1": {"name": "Orks", "detachment": str(d["name"])}, "2": {"name": "Adeptus Custodes", "detachment": "Shield Host"}}
		SM.load_faction_stratagems_for_player(1)
		for s in SM.get_faction_stratagems_for_player(1):
			var by_registry: bool = Codex.is_implemented(s)
			if s.get("implemented", false) and not by_registry:
				leaked.append("%s (%s)" % [s.get("name", ""), d["name"]])
			elif by_registry and not s.get("implemented", false):
				missing.append("%s (%s)" % [s.get("name", ""), d["name"]])
	_check("no codex row is marked implemented by legacy 10e name lists (DAKKASTORM, ARMED TO DA TEEF, ...)",
		leaked.is_empty(), str(leaked))
	_check("every row the codex registry implements is marked implemented",
		missing.is_empty(), str(missing))
	_check("StratagemManager.is_ork_codex_11e_row recognises the marker",
		SM.is_ork_codex_11e_row({"effects": [{"type": "custom:ork11e"}]}) and not SM.is_ork_codex_11e_row({"effects": [{"type": "custom:other"}]}))
	GS.state["factions"] = saved_factions

	# ---- 5. Detachments.csv
	var det_rows = FactionStratagemLoaderData.parse_csv_file("res://data/Detachments.csv")
	var ork_dets: Array = []
	for r in det_rows:
		if str(r.get("faction_id", "")) == "ORK":
			ork_dets.append(str(r.get("name", "")))
	var want_dets: Array = []
	for d in cur_dets:
		want_dets.append(str(d["name"]))
	_check("Detachments.csv ORK rows == the 15 codex detachments (in curated order)", ork_dets == want_dets, str(ork_dets))

	# ---- 6. legacy (1.0.19) datasheet kits
	_check_legacy_kits()

	# ---- 7. the codex test army (armies/ork11e_codex_test.json)
	_check_test_army()

func _norm(s: String) -> String:
	var t := s.replace("\r", " ").replace("\n", " ")
	while "  " in t:
		t = t.replace("  ", " ")
	return t.strip_edges()

func _w(name: String, type: String) -> Dictionary:
	return {"name": name, "type": type, "range": "Melee" if type == "Melee" else "12", "attacks": "1",
		"ballistic_skill": "5", "weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""}

func _model(i: int) -> Dictionary:
	return {"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32,
		"position": {"x": 100.0 + i * 40.0, "y": 100.0}}

func _check_legacy_kits() -> void:
	var RE = root.get_node("RulesEngine")
	# Pre-codex Boyz roster (army files / fixtures): Boss Nob = big choppa.
	var boyz := {"id": "U_LEGACY_BOYZ", "owner": 1, "meta": {"name": "Boyz",
		"weapons": [_w("Slugga", "Ranged"), _w("Shoota", "Ranged"), _w("Big choppa", "Melee"),
			_w("Choppa", "Melee"), _w("Close combat weapon", "Melee"), _w("Power klaw", "Melee")],
		"wargear": ["9x Slugga", "1x Slugga"]}, "models": []}
	for i in 10:
		boyz["models"].append(_model(i))
	_check("legacy Boyz roster -> datasheet key 'Boyz [1.0.19]'",
		UnitLoadoutResolver.datasheet_key(boyz) == "Boyz" + UnitLoadoutResolver.LEGACY_NAME_SUFFIX,
		UnitLoadoutResolver.datasheet_key(boyz))
	RE._ensure_loadout_resolved(boyz)
	var nob_melee = boyz["models"][0].get("melee_loadout", [])
	var boy_melee = boyz["models"][5].get("melee_loadout", [])
	_check("legacy Boyz: Boss Nob resolves to [Big choppa] (as under 1.0.19)", nob_melee == ["Big choppa"], str(nob_melee))
	_check("legacy Boyz: a Boy resolves to [Choppa]", boy_melee == ["Choppa"], str(boy_melee))

	# Pre-codex Battlewagon: base melee "Tracks and wheels" stays on the display
	# list (two melee picks vs one base melee weapon = additive, not a swap).
	var bw_old := {"id": "U_BW_OLD", "meta": {"name": "Battlewagon",
		"weapons": [_w("Kannon", "Ranged"), _w("Lobba", "Ranged"), _w("Deff rolla", "Melee"), _w("Grabbin' klaw", "Melee"), _w("Tracks and wheels", "Melee")],
		"wargear": ["1x Kannon", "1x Deff rolla", "1x Grabbin' klaw"]}, "models": [_model(0)]}
	var eq_old: Array = UnitLoadoutResolver.get_equipped_weapon_names(bw_old)
	_check("legacy Battlewagon keeps 'Tracks and wheels' (pre-codex base kit)", "Tracks and wheels" in eq_old, str(eq_old))

	# Codex-built Battlewagon (1.4.5 datasheet: base melee "Crushin' bulk"): current kit.
	var bw_new := {"id": "U_BW_NEW", "meta": {"name": "Battlewagon",
		"weapons": [_w("Kannon", "Ranged"), _w("Lobba", "Ranged"), _w("Deff rolla", "Melee"), _w("Grabbin' klaw", "Melee"), _w("Crushin' bulk", "Melee")],
		"wargear": ["1x Kannon", "1x Deff rolla", "1x Grabbin' klaw"]}, "models": [_model(0)]}
	_check("codex Battlewagon roster -> datasheet key 'Battlewagon' (current kit)",
		UnitLoadoutResolver.datasheet_key(bw_new) == "Battlewagon", UnitLoadoutResolver.datasheet_key(bw_new))
	var eq_new: Array = UnitLoadoutResolver.get_equipped_weapon_names(bw_new)
	_check("codex Battlewagon keeps its base 'Crushin' bulk'", "Crushin' bulk" in eq_new, str(eq_new))

	# Removed datasheet (Lootas): only the legacy kit exists.
	var lootas := {"id": "U_LOOTAS", "meta": {"name": "Lootas",
		"weapons": [_w("Big shoota", "Ranged"), _w("Deffgun", "Ranged"), _w("Kustom mega-blasta", "Ranged"), _w("Close combat weapon", "Melee")],
		"wargear": ["8x Deffgun", "2x Kustom mega-blasta"]}, "models": []}
	for i in 10:
		lootas["models"].append(_model(i))
	_check("removed datasheet (Lootas) -> legacy kit",
		UnitLoadoutResolver.datasheet_key(lootas) == "Lootas" + UnitLoadoutResolver.LEGACY_NAME_SUFFIX,
		UnitLoadoutResolver.datasheet_key(lootas))
	# A datasheet the codex did not touch (Custodian Guard) never switches.
	var cg := {"meta": {"name": "Custodian Guard", "weapons": [_w("Guardian spear", "Melee")]}, "models": [_model(0)]}
	_check("non-Ork datasheet never resolves via a legacy kit", UnitLoadoutResolver.datasheet_key(cg) == "Custodian Guard")

## The committed dataset (data/40kdc/units.json) carries the local-patches.mjs
## patch-4 keyword corrections, so the web army builder and future army
## generation produce the codex keywords.
func _check_dataset_keyword_patches() -> void:
	var f := FileAccess.open("res://data/40kdc/units.json", FileAccess.READ)
	_check("data/40kdc/units.json readable", f != null)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	var by_id := {}
	for u in (parsed if parsed is Array else []):
		if str(u.get("faction_id", "")) == "orks":
			by_id[str(u.get("id", ""))] = (u.get("keywords", []) as Array).map(func(k): return str(k).to_upper())
	var want := {
		"trukk": {"has": ["SPEED FREEKS"], "not": []},
		"deffkoptas": {"has": ["MOUNTED"], "not": ["VEHICLE"]},
		"big-mek-dakkarig": {"has": ["VEHICLE"], "not": []},
		"mozrog-skragbad": {"has": ["MONSTER"], "not": ["MOUNTED"]},
		"beastboss-on-squigosaur": {"has": ["MONSTER"], "not": ["MOUNTED"]},
	}
	for id in want:
		var kws: Array = by_id.get(id, [])
		var ok := not kws.is_empty()
		for k in want[id].has:
			ok = ok and k in kws
		for k in want[id]["not"]:
			ok = ok and not k in kws
		_check("units.json %s keywords match the codex list (%s)" % [id, str(want[id])], ok, str(kws))


func _check_test_army() -> void:
	var ALM = root.get_node("ArmyListManager")
	var army: Dictionary = ALM.load_army_list("ork11e_codex_test", 1)
	_check("ork11e_codex_test loads through ArmyListManager", not army.is_empty())
	if army.is_empty():
		return
	var units: Dictionary = army.get("units", {})
	_check("test army: 22 units, War Horde", units.size() == 22 and str(army["faction"]["detachment"]) == "War Horde",
		"%d / %s" % [units.size(), army["faction"].get("detachment", "")])
	var no_weapons: Array = []
	var no_waaagh: Array = []
	var legacy_keyed: Array = []
	var kw_units := {}
	for uid in units:
		var u: Dictionary = units[uid]
		var meta: Dictionary = u["meta"]
		var eq: Array = UnitLoadoutResolver.get_equipped_weapon_names(u)
		if eq.is_empty():
			no_weapons.append(uid)
		var has_waaagh := false
		for ab in meta.get("abilities", []):
			if typeof(ab) == TYPE_DICTIONARY and str(ab.get("name", "")) == "Waaagh!":
				has_waaagh = true
		if not has_waaagh:
			no_waaagh.append(uid)
		if UnitLoadoutResolver.datasheet_key(u) != str(meta.get("name", "")):
			legacy_keyed.append(uid)
		for kw in meta.get("keywords", []):
			if not kw_units.has(kw):
				kw_units[kw] = []
			kw_units[kw].append(uid)
		# Engine path: every model ends up with at least one melee weapon.
		var copy: Dictionary = u.duplicate(true)
		root.get_node("RulesEngine")._ensure_loadout_resolved(copy)
		for m in copy.get("models", []):
			if root.get_node("RulesEngine")._get_model_weapon_ids(copy, m, "Melee").is_empty():
				no_weapons.append("%s/%s (no melee)" % [uid, m.get("id", "?")])
				break
	_check("test army: every unit resolves weapons (display + engine melee per model)", no_weapons.is_empty(), str(no_weapons))
	_check("test army: every unit carries the Waaagh! army rule (faction_rule_ids fix)", no_waaagh.is_empty(), str(no_waaagh))
	_check("test army: codex-built units resolve against the current (codex) kits", legacy_keyed.is_empty(), str(legacy_keyed))
	for kw in ["BOYZ", "BEAST SNAGGA BOYZ", "NOBZ", "MEGANOBZ", "FLASH GITZ", "TANKBUSTAS", "BREAKA BOYZ",
			"MEK GUNZ", "DEFFKOPTAS", "AIRCRAFT", "SPEED FREEKS", "RUKKATRUKK SQUIGBUGGIES", "WAGON", "TRUKK",
			"DEFF DREAD", "KILLA KANS", "STORMBOYZ", "KOMMANDOS", "WALKER"]:
		_check("test army has a %s unit" % kw, kw_units.has(kw))
	_check("test army has two GRETCHIN units", kw_units.get("GRETCHIN", []).size() == 2, str(kw_units.get("GRETCHIN", [])))
	var wagon_tr := false
	for uid in kw_units.get("WAGON", []):
		if uid in kw_units.get("TRANSPORT", []):
			wagon_tr = true
	_check("test army has a WAGON TRANSPORT", wagon_tr)
	var plain_vehicle := false
	for uid in kw_units.get("VEHICLE", []):
		if not uid in kw_units.get("WALKER", []) and not uid in kw_units.get("AIRCRAFT", []):
			plain_vehicle = true
	_check("test army has a non-walker ORKS VEHICLE", plain_vehicle)
	# r5:F2 — codex keyword lists (scripts/40kdc/local-patches.mjs patch 4):
	# the Trukk is SPEED FREEKS (DAKKASTORM / SPEEDIEST FREEKS), Deffkoptas are
	# MOUNTED and not VEHICLE (MOW 'EM DOWN / FUNGUS-FUEL INJECTION gates).
	var trukk_kw: Array = units.get("U_TRUKK_A", {}).get("meta", {}).get("keywords", [])
	_check("Trukk carries SPEED FREEKS (codex keyword list)", "SPEED FREEKS" in trukk_kw, str(trukk_kw))
	var kopta_kw: Array = units.get("U_DEFFKOPTAS_A", {}).get("meta", {}).get("keywords", [])
	_check("Deffkoptas are MOUNTED, not VEHICLE (codex keyword lists)", "MOUNTED" in kopta_kw and not "VEHICLE" in kopta_kw, str(kopta_kw))
	_check_dataset_keyword_patches()
	var jet: Dictionary = units.get("U_DAKKAJET_A", {})
	var jet_dd := false
	for ab in jet.get("meta", {}).get("abilities", []):
		if str(ab.get("name", "")).begins_with("Deadly Demise"):
			jet_dd = true
	_check("test army aircraft (Dakkajet) has Deadly Demise", jet_dd)
	var boss: Dictionary = units.get("U_WARBOSS_A", {})
	_check("Warboss can lead BOYZ (attached-unit pairing)", "BOYZ" in boss.get("meta", {}).get("leader_data", {}).get("can_lead", []))
	var rh: Dictionary = units.get("U_RUNTHERD_A", {})
	_check("Runtherd can lead GRETCHIN", "GRETCHIN" in rh.get("meta", {}).get("leader_data", {}).get("can_lead", []))

