# LLM critic roster — sent over the MCP bridge once per game (execute_script,
# multiline; no func defs). Static per-unit datasheet lines so the reviewer
# can judge target choice, charges and objective play without the full meta.
# One compact string per unit: stats + keywords + weapons.
var out := {}
for uid in GameState.state.get("units", {}).keys():
	var u = GameState.state.units[uid]
	var m = u.get("meta", {})
	var s = m.get("stats", {})
	var line := "P%d %s (%dpts): M%s T%s Sv%s+%s W%s OC%s Ld%s+" % [
		int(u.get("owner", 0)), GameState.get_unit_display_name(uid), int(m.get("points", 0)),
		str(int(s.get("move", 0))), str(int(s.get("toughness", 0))), str(int(s.get("save", 0))),
		(" inv%s+" % str(int(s.get("invuln", 0)))) if int(s.get("invuln", 0)) > 0 else "",
		str(int(s.get("wounds", 0))), str(int(s.get("objective_control", 0))), str(int(s.get("leadership", 0)))]
	var kws := []
	for k in m.get("keywords", []):
		if str(k) in ["INFANTRY", "VEHICLE", "MONSTER", "CHARACTER", "BATTLELINE", "MOUNTED", "FLY", "TRANSPORT", "EPIC HERO", "BEAST", "SWARM", "WALKER", "AIRCRAFT", "TOWERING", "PSYKER"]:
			kws.append(str(k))
	line += " [" + ", ".join(PackedStringArray(kws)) + "]"
	var ws := []
	for w in m.get("weapons", []):
		var r := str(w.get("range", ""))
		ws.append("%s %s A%s S%s AP%s D%s%s" % [
			str(w.get("name", "")), ("R" + r + "\"") if r != "" and r.to_lower() != "melee" and str(w.get("type", "")) != "Melee" else "melee",
			str(w.get("attacks", "")), str(w.get("strength", "")), str(w.get("ap", "")), str(w.get("damage", "")),
			(" {" + str(w.get("special_rules", "")) + "}") if str(w.get("special_rules", "")) != "" else ""])
	if not ws.is_empty():
		line += " | " + "; ".join(PackedStringArray(ws))
	out[uid] = line
return out
