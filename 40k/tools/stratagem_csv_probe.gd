extends SceneTree

# Stratagem CSV probe: parses res://data/Stratagems.csv through the real
# FactionStratagemLoaderData for EVERY faction code present in the file and
# dumps the parsed dictionaries (grouped faction -> detachment -> [strat]) to
# JSON. Used to prove that a data refresh changed only the rows it meant to
# (e.g. non-ORK rows parse byte-for-byte the same before and after the
# Ork codex splice).
#
# Usage: godot --headless --path 40k -s tools/stratagem_csv_probe.gd -- --out=/abs/path.json
# Not a pass/fail test.

func _initialize():
	await create_timer(0.2).timeout
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--out="):
			out_path = str(a).substr(6)
	var loader = FactionStratagemLoaderData.new()
	loader.load_faction_codes()
	var rows = FactionStratagemLoaderData.parse_csv_file("res://data/Stratagems.csv")
	var by_code := {}
	for row in rows:
		var code := str(row.get("faction_id", "")).strip_edges()
		if code == "" or by_code.has(code):
			continue
		by_code[code] = true
	var codes: Array = by_code.keys()
	codes.sort()
	var out := {"row_count": rows.size(), "factions": {}}
	for code in codes:
		var groups := {}
		for row in rows:
			if str(row.get("faction_id", "")).strip_edges() != code:
				continue
			var det := str(row.get("detachment", "")).strip_edges()
			if not groups.has(det):
				groups[det] = []
			var s = loader._parse_stratagem_row(row, code)
			if not s.is_empty():
				groups[det].append(s)
		out["factions"][code] = groups
		print("STRAT-PROBE|%s|detachments=%d" % [code, groups.size()])
	if out_path != "":
		var fh := FileAccess.open(out_path, FileAccess.WRITE)
		fh.store_string(JSON.stringify(out, "  ", true))
		fh.close()
		print("STRAT-PROBE wrote %s" % out_path)
	quit(0)
