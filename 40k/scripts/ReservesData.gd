extends RefCounted
class_name ReservesData

# ReservesData — the single source of truth for everything the three reserve
# UI tiers display (badge, off-board tray, detail panel).
#
# Why this exists: before this, the only trace of a unit sitting in Reserves
# was (a) a "(N units in reserves)" count line in the Movement phase list and
# (b) the "--- REINFORCEMENTS ---" rows in that same list — active player only,
# Movement phase only. The opponent's reserves were never surfaced anywhere,
# even though on a physical table those models sit in plain view beside the
# board and matched-play rosters are public. All three tiers read from here so
# they can never disagree with each other.

const GameStateData = preload("res://autoloads/GameState.gd")

# 11e: a unit that has not arrived from Reserves by the end of the third
# battle round is destroyed. Implemented in ScoringPhase._destroy_remaining_reserves
# (fires when current_battle_round == 3 during the end-of-round step).
const DEADLINE_ROUND := 3

# Reserves cannot arrive before battle round 2 (MovementPhase rejects earlier
# arrivals with "Reserves cannot arrive until Battle Round 2").
const EARLIEST_ARRIVAL_ROUND := 2


# Resolve a unit's reserve type, tolerating the two ways the field goes bad:
#   • missing entirely (older saves),
#   • present but null — JSON round-trips store "not set" as null, and
#     Dictionary.get(k, default) returns null (not the default) for that.
# Both audit_baseline_postdeploy and ri_pretrigger carry `reserve_type: null`
# on every reserve unit, so a naive read would badge a Deep Strike unit "SR".
# Fall back to the unit's actual Deep Strike ability before defaulting.
static func resolve_reserve_type(unit_id: String, unit: Dictionary) -> String:
	var raw = unit.get("reserve_type", null)
	if raw != null and typeof(raw) == TYPE_STRING and str(raw) != "":
		return str(raw)
	if GameState.unit_has_deep_strike(unit_id):
		return "deep_strike"
	return "strategic_reserves"


static func type_label(reserve_type: String) -> String:
	return "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"


static func type_short(reserve_type: String) -> String:
	return "DS" if reserve_type == "deep_strike" else "SR"


static func type_hint(reserve_type: String) -> String:
	if reserve_type == "deep_strike":
		return "Arrives anywhere more than 9\" horizontally from enemy models."
	return "Arrives wholly within 6\" of a battlefield edge, outside enemy deployment zone."


# One entry per unit this player has in Reserves, richest-first (points desc)
# so the scariest thing waiting off-table reads at the top of every list.
#
# Attached characters are folded into their bodyguard's entry rather than
# listed separately — they arrive together, and listing them apart would
# double-count both the unit total and the points total.
static func collect(player: int) -> Array:
	var out: Array = []
	var units: Dictionary = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if int(unit.get("owner", 0)) != player:
			continue
		if int(unit.get("status", -1)) != GameStateData.UnitStatus.IN_RESERVES:
			continue
		# Attached characters ride along with their bodyguard unit.
		var attached_to = unit.get("attached_to", "")
		if attached_to != null and str(attached_to) != "":
			continue
		out.append(_build_entry(str(unit_id), unit))

	out.sort_custom(func(a, b):
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		return str(a["name"]) < str(b["name"]))
	return out


static func _build_entry(unit_id: String, unit: Dictionary) -> Dictionary:
	var meta: Dictionary = unit.get("meta", {})
	var models: Array = unit.get("models", [])
	var alive := 0
	for m in models:
		if typeof(m) == TYPE_DICTIONARY and m.get("alive", true):
			alive += 1

	var reserve_type := resolve_reserve_type(unit_id, unit)
	var points := int(meta.get("points", 0))

	# Attached characters: names for display, and their points/models roll up
	# into this entry so the tray's per-player total matches the badge.
	var rider_names: Array = []
	var attachment_data = unit.get("attachment_data", {})
	if typeof(attachment_data) == TYPE_DICTIONARY:
		for char_id in attachment_data.get("attached_characters", []):
			var char_unit = GameState.get_unit(str(char_id))
			if char_unit.is_empty():
				continue
			rider_names.append(GameState.get_unit_display_name(str(char_id)))
			points += int(char_unit.get("meta", {}).get("points", 0))
			for m in char_unit.get("models", []):
				if typeof(m) == TYPE_DICTIONARY and m.get("alive", true):
					alive += 1

	# A transport can go into Reserves with a full belly — those passengers are
	# off-table too and are destroyed with it at the end of round 3.
	var passenger_names: Array = []
	var transport_data = unit.get("transport_data", {})
	if typeof(transport_data) == TYPE_DICTIONARY:
		for passenger_id in transport_data.get("embarked_units", []):
			var p_unit = GameState.get_unit(str(passenger_id))
			if p_unit.is_empty():
				continue
			passenger_names.append(GameState.get_unit_display_name(str(passenger_id)))
			points += int(p_unit.get("meta", {}).get("points", 0))

	var color := GameState.get_unit_color(unit_id)
	if color == Color.TRANSPARENT:
		color = GameState.auto_assign_unit_color(unit_id)

	return {
		"unit_id": unit_id,
		"name": GameState.get_unit_display_name(unit_id),
		"models_alive": alive,
		"points": points,
		"reserve_type": reserve_type,
		"type_short": type_short(reserve_type),
		"type_label": type_label(reserve_type),
		"type_hint": type_hint(reserve_type),
		"color": color,
		"label": GameState.get_unit_label(unit_id),
		"riders": rider_names,
		"passengers": passenger_names,
		"keywords": meta.get("keywords", []),
	}


# Headline numbers for the always-on badge and each tray rail header.
static func summary(player: int) -> Dictionary:
	var entries := collect(player)
	var points := 0
	var models := 0
	for e in entries:
		points += int(e["points"])
		models += int(e["models_alive"])
	var battle_round := GameState.get_battle_round()
	return {
		"count": entries.size(),
		"points": points,
		"models": models,
		"battle_round": battle_round,
		"deadline_round": DEADLINE_ROUND,
		# Rounds still available to bring them in, this one included. Hits 0
		# once round 3 has ended and the destruction step has run.
		"rounds_left": max(0, DEADLINE_ROUND - battle_round + 1),
		# Final round to arrive — anything still off-table when it ends dies.
		"final_call": entries.size() > 0 and battle_round >= DEADLINE_ROUND,
	}


# True when this player could legally bring reserves in right now: their
# Movement phase, battle round 2 or later. Used to decide whether a tray chip
# click starts a placement or just opens the datasheet.
static func can_arrive_now(player: int) -> bool:
	if GameState.get_battle_round() < EARLIEST_ARRIVAL_ROUND:
		return false
	if GameState.get_active_player() != player:
		return false
	return int(GameState.state.get("meta", {}).get("phase", -1)) == GameStateData.Phase.MOVEMENT


# Whose eyes are on the screen right now. In a networked game that is the
# local peer's player number; in hot-seat / vs-AI it is whoever is active.
# Used only to mark "(you)" — every tier shows BOTH players' reserves either
# way, so a wrong answer here mislabels a chip, it never hides information.
static func viewing_player() -> int:
	var nm = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
	if nm != null and nm.has_method("is_networked") and nm.is_networked():
		var local = int(nm.get_local_player())
		if local > 0:
			return local
	return GameState.get_active_player()


# Formats 1270 as "1,270" — points totals are the headline number on the badge
# and four-digit runs are hard to read at a glance without a separator.
static func format_points(points: int) -> String:
	var s := str(abs(points))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if points < 0 else "") + out


# Short human-readable status for "when can this arrive", shown on the badge
# and each rail header.
static func timing_text(player: int) -> String:
	var s := summary(player)
	if int(s["count"]) == 0:
		return ""
	var battle_round := int(s["battle_round"])
	if battle_round < EARLIEST_ARRIVAL_ROUND:
		return "arrive R%d+" % EARLIEST_ARRIVAL_ROUND
	if battle_round >= DEADLINE_ROUND:
		return "LAST ROUND — arrive or destroyed"
	return "arrive by end of R%d" % DEADLINE_ROUND
