# LLM critic mission context — execute_script once per game (multiline, no
# func defs). Each player's Force Disposition and resolved primary mission
# card (MissionManager), so critic.py can tell the reviewer exactly how the
# acting player scores primary VP (awards come from data/40kdc/missionCards.json).
var out := {}
for p in [1, 2]:
	var pk := str(p)
	var card: Dictionary = MissionManager.get_primary_mission_for_player(p)
	out[pk] = {
		"disposition": str(MissionManager.player_dispositions.get(pk, "")),
		"card_id": str(card.get("id", "")),
		"card_name": str(card.get("name", "")),
	}
out["mission"] = str(MissionManager.current_mission.get("name", ""))
return out
