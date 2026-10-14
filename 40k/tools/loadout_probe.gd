extends SceneTree

# Loadout probe: loads EVERY army file under res://armies through the real
# ArmyListManager.load_army_list path and records, per unit, what the game will
# actually arm it with:
#   - menu:      meta.weapons names (the datasheet menu in the army file)
#   - equipped:  UnitLoadoutResolver.get_equipped_weapon_names (display + single
#                model engine narrowing)
#   - models:    per-model ranged_loadout / melee_loadout stamped by
#                RulesEngine._ensure_loadout_resolved (engine path), or "menu"
#   - waaagh:    whether the unit carries the army rule ability
# plus per army: faction, detachment, # detachment stratagems loaded via the
# real FactionStratagemLoader, # load errors.
#
# Usage: godot --headless --path 40k -s tools/loadout_probe.gd -- --out=/abs/path.json
# Not a pass/fail test: it is a data dump used to diff resolved loadouts across
# a data refresh (see .llm/ork_codex_11e_design.md §1).

func _initialize():
	await create_timer(0.3).timeout
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--out="):
			out_path = str(a).substr(6)
	var ALM = root.get_node("ArmyListManager")
	var result := {}
	var dir := DirAccess.open("res://armies")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	for f in files:
		var army_name: String = f.trim_suffix(".json")
		var data: Dictionary = ALM.load_army_list(army_name, 1)
		var entry := {"loaded": not data.is_empty(), "units": {}}
		if data.is_empty():
			result[f] = entry
			continue
		var faction = data.get("faction", {})
		if typeof(faction) == TYPE_DICTIONARY:
			entry["faction"] = str(faction.get("name", ""))
			entry["detachment"] = str(faction.get("detachment", ""))
		else:
			entry["faction"] = str(faction)
			entry["detachment"] = ""
		var strats = loader.load_faction_stratagems(entry["faction"], entry["detachment"])
		entry["detachment_stratagems"] = strats.size()
		var total_pts := 0
		var ids: Array = data.get("units", {}).keys()
		ids.sort()
		for uid in ids:
			var unit: Dictionary = data["units"][uid]
			var rec := _unit_record(unit)
			total_pts += int(rec["points"])
			entry["units"][uid] = rec
		entry["total_points"] = total_pts
		result[f] = entry
		print("LOADOUT-PROBE|%s|units=%d|det=%s|strats=%d|pts=%d" % [f, ids.size(), entry["detachment"], entry["detachment_stratagems"], total_pts])
	# Test fixtures (tests/saves/*.w40ksave, plain or compressed): their units
	# carry their own meta.weapons, but per-model loadouts are re-resolved at
	# runtime from data/40kdc/unitCompositions.json, so a dataset bump can
	# change them too.
	var fixtures := {}
	var sdir := DirAccess.open("res://tests/saves")
	var sfiles: Array = []
	if sdir:
		for f in sdir.get_files():
			if f.ends_with(".w40ksave"):
				sfiles.append(f)
	sfiles.sort()
	var serializer = root.get_node("StateSerializer")
	for f in sfiles:
		var fh0 := FileAccess.open("res://tests/saves/" + f, FileAccess.READ)
		if fh0 == null:
			continue
		var raw := fh0.get_as_text()
		fh0.close()
		var st: Dictionary = serializer.deserialize_game_state(raw)
		var fx := {"units": {}}
		var units: Dictionary = st.get("units", {}) if typeof(st.get("units", {})) == TYPE_DICTIONARY else {}
		var fids: Array = units.keys()
		fids.sort()
		for uid in fids:
			var unit = units[uid]
			if typeof(unit) != TYPE_DICTIONARY:
				continue
			fx["units"][uid] = _unit_record(unit)
		fixtures[f] = fx
	result["__fixtures__"] = fixtures
	print("LOADOUT-PROBE|fixtures=%d" % fixtures.size())
	var txt := JSON.stringify(result, "  ", true)
	if out_path != "":
		var fh := FileAccess.open(out_path, FileAccess.WRITE)
		fh.store_string(txt)
		fh.close()
		print("LOADOUT-PROBE wrote %s" % out_path)
	quit(0)


func _unit_record(unit: Dictionary) -> Dictionary:
	var meta: Dictionary = unit.get("meta", {}) if typeof(unit.get("meta", {})) == TYPE_DICTIONARY else {}
	var menu: Array = []
	for w in meta.get("weapons", []):
		if typeof(w) == TYPE_DICTIONARY:
			menu.append(str(w.get("name", "")))
	var equipped: Array = UnitLoadoutResolver.get_equipped_weapon_names(unit)
	var copy: Dictionary = unit.duplicate(true)
	copy.erase("_loadout_version")
	copy.erase("_loadout_checked")
	root.get_node("RulesEngine")._ensure_loadout_resolved(copy)
	var per_model: Array = []
	for m in copy.get("models", []):
		if typeof(m) != TYPE_DICTIONARY:
			per_model.append({"raw": str(m)})
			continue
		per_model.append({"type": str(m.get("model_type", "")), "ranged": m.get("ranged_loadout", "menu"), "melee": m.get("melee_loadout", "menu")})
	var has_waaagh := false
	var abil_names: Array = []
	for ab in meta.get("abilities", []):
		var n := str(ab.get("name", "")) if typeof(ab) == TYPE_DICTIONARY else str(ab)
		abil_names.append(n)
		if n.to_lower().begins_with("waaagh"):
			has_waaagh = true
	return {
		"name": str(meta.get("name", "")),
		"models": copy.get("models", []).size(),
		"points": int(meta.get("points", 0)),
		"menu": menu,
		"equipped": equipped,
		"per_model": per_model,
		"waaagh": has_waaagh,
		"abilities": abil_names,
		"enhancements": meta.get("enhancements", []),
	}
