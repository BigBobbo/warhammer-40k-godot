extends RefCounted

## CustodesCommon — shared helpers for the Codex: Adeptus Custodes (11e) modules.
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md §2. The Custodes
## modules (CustodesKatah.gd, CustodesCodex11e.gd + its group scripts,
## CustodesDetachments.gd, CustodesEnhancements.gd, CustodesAbilities.gd)
## preload ONLY this file, never each other, so parallel work packages never
## build preload cycles.
##
## Every autoload is reached late-bound (Engine.get_main_loop().root…): a naked
## autoload global fails to compile when a headless `godot -s` test parses a
## script that references it before the autoloads are registered (the same
## rule OrkCodexCommon.gd and AIDecisionMaker.gd follow).

const GameStateData = preload("res://autoloads/GameState.gd")

const PX_PER_INCH: float = 40.0

# ---------------------------------------------------------------------------
# Late-bound autoload access
# ---------------------------------------------------------------------------

static func autoload(node_name: String) -> Node:
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null(node_name)
	return null

static func game_state() -> Node:
	return autoload("GameState")

static func rules() -> Node:
	return autoload("RulesEngine")

static func phase_manager() -> Node:
	return autoload("PhaseManager")

static func stratagem_manager() -> Node:
	return autoload("StratagemManager")

static func log_info(msg: String) -> void:
	print(msg)
	var dl = autoload("DebugLogger")
	if dl and dl.has_method("info"):
		dl.info(msg, {})

## Loud failure: push_error (stdout) AND an ERROR line in the debug log so
## verify_delivery / scenario log checks catch the gap.
static func log_error(msg: String) -> void:
	push_error(msg)
	var dl = autoload("DebugLogger")
	if dl and dl.has_method("error"):
		dl.error(msg, {})

## Player-visible Game Log line (GameEventLog).
static func game_log(player: int, msg: String) -> void:
	var gel = autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, msg)

# ---------------------------------------------------------------------------
# State access
# ---------------------------------------------------------------------------

static func state() -> Dictionary:
	var gs = game_state()
	if gs == null:
		return {}
	return gs.state

static func unit(unit_id: String) -> Dictionary:
	if unit_id == "":
		return {}
	return state().get("units", {}).get(unit_id, {})

static func unit_name(unit_id: String) -> String:
	var u = unit(unit_id)
	if u.is_empty():
		return unit_id
	var meta = u.get("meta", {})
	return str(meta.get("display_name", meta.get("name", unit_id)))

static func active_player() -> int:
	return int(state().get("meta", {}).get("active_player", 1))

static func battle_round() -> int:
	var gs = game_state()
	if gs and gs.has_method("get_battle_round"):
		return int(gs.get_battle_round())
	return int(state().get("meta", {}).get("battle_round", 1))

static func current_phase() -> int:
	return int(state().get("meta", {}).get("phase", -1))

static func player_cp(player: int) -> int:
	return int(state().get("players", {}).get(str(player), {}).get("cp", 0))

## Straight apostrophes, upper-case: the army data spells "Ka'tah" with a
## straight quote, the Wahapedia export with a curly one.
static func norm_name(n: String) -> String:
	return n.replace("’", "'").replace("‘", "'").strip_edges().to_lower()

static func has_keyword(u: Dictionary, keyword: String) -> bool:
	var kw_upper = keyword.to_upper()
	for kw in u.get("meta", {}).get("keywords", []):
		if str(kw).to_upper() == kw_upper:
			return true
	return false

static func has_any_keyword(u: Dictionary, keywords: Array) -> bool:
	for kw in keywords:
		if has_keyword(u, str(kw)):
			return true
	return false

## True when the unit's datasheet lists an ability with this name (String or
## {name: …} entries; apostrophe- and case-insensitive).
static func has_ability(u: Dictionary, ability_name: String) -> bool:
	var want := norm_name(ability_name)
	for a in u.get("meta", {}).get("abilities", []):
		var n := ""
		if a is String:
			n = a
		elif a is Dictionary:
			n = str(a.get("name", ""))
		if norm_name(n) == want:
			return true
	return false

static func is_monster_or_vehicle(u: Dictionary) -> bool:
	return has_any_keyword(u, ["MONSTER", "VEHICLE"])

static func is_alive(u: Dictionary) -> bool:
	for m in u.get("models", []):
		if m.get("alive", true):
			return true
	return false

static func is_on_battlefield(u: Dictionary) -> bool:
	if u.is_empty() or not is_alive(u):
		return false
	var status = int(u.get("status", GameStateData.UnitStatus.DEPLOYED))
	if status == GameStateData.UnitStatus.IN_RESERVES or status == GameStateData.UnitStatus.UNDEPLOYED:
		return false
	if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
		return false
	for m in u.get("models", []):
		if m.get("alive", true) and m.get("position", null) != null:
			return true
	return false

## The Attached unit's "head" (the bodyguard unit id) for any component id.
static func head_id(unit_id: String) -> String:
	var re = rules()
	if re and re.has_method("attached_unit_target_id"):
		return str(re.attached_unit_target_id(unit_id, state()))
	return unit_id

## The unit plus every component of its Attached unit (19.03). Attached
## CHARACTERs resolve their attacks against their own unit id, so a unit-wide
## effect must be written to every component.
static func attached_group_ids(unit_id: String) -> Array:
	var units = state().get("units", {})
	var head := head_id(unit_id)
	var out: Array = [head]
	for char_id in units.get(head, {}).get("attachment_data", {}).get("attached_characters", []):
		var cid = str(char_id)
		if cid != "" and not cid in out and units.has(cid):
			out.append(cid)
	if not unit_id in out:
		out.append(unit_id)
	return out

static func is_engaged(unit_id: String) -> bool:
	var re = rules()
	if re and re.has_method("is_unit_engaged"):
		return bool(re.is_unit_engaged(unit_id, state()))
	return false

## Enemy unit ids engaged with any component of `unit_id`'s Attached unit.
static func engaged_enemy_ids(unit_id: String) -> Array:
	var out: Array = []
	var units: Dictionary = state().get("units", {})
	var me := unit(unit_id)
	var owner := int(me.get("owner", 0))
	var re = rules()
	if re == null or not re.has_method("check_units_in_engagement_range"):
		return out
	for gid in attached_group_ids(unit_id):
		var gu: Dictionary = units.get(str(gid), {})
		if gu.is_empty() or not is_alive(gu):
			continue
		for eid in units:
			var eu: Dictionary = units[eid]
			if int(eu.get("owner", 0)) == owner or not is_on_battlefield(eu) or eid in out:
				continue
			if re.check_units_in_engagement_range(gu, eu, state()):
				out.append(eid)
	return out

# ---------------------------------------------------------------------------
# Distance helpers (edge-to-edge, inches)
# ---------------------------------------------------------------------------

## Closest edge-to-edge distance between any two alive, placed models.
static func unit_distance_inches(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return INF
	var meas = autoload("Measurement")
	var best := INF
	for ma in a.get("models", []):
		if not ma.get("alive", true) or ma.get("position", null) == null:
			continue
		for mb in b.get("models", []):
			if not mb.get("alive", true) or mb.get("position", null) == null:
				continue
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(ma, mb))
			else:
				d = _pos(ma).distance_to(_pos(mb)) / PX_PER_INCH
			if d < best:
				best = d
	return best

static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position", null)
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.ZERO

## Distance from `u` to the closest enemy unit on the battlefield (INF = none).
static func nearest_enemy_inches(u: Dictionary) -> float:
	var owner := int(u.get("owner", 0))
	var best := INF
	var units: Dictionary = state().get("units", {})
	for eid in units:
		var eu: Dictionary = units[eid]
		if int(eu.get("owner", 0)) == owner or not is_on_battlefield(eu):
			continue
		best = minf(best, unit_distance_inches(u, eu))
	return best

# ---------------------------------------------------------------------------
# Flag helpers — scoped writes as diffs (replay / network safe)
# ---------------------------------------------------------------------------

static func set_flag_diffs(unit_ids: Array, flag: String, value) -> Array:
	var diffs: Array = []
	for uid in unit_ids:
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(uid), flag], "value": value})
	return diffs

## Remove diffs for every unit in `unit_ids` that currently carries `flag`.
static func remove_flag_diffs(unit_ids: Array, flag: String) -> Array:
	var diffs: Array = []
	var units: Dictionary = state().get("units", {})
	for uid in unit_ids:
		if units.get(str(uid), {}).get("flags", {}).has(flag):
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [str(uid), flag]})
	return diffs

## Apply diffs through PhaseManager (network / replay pipeline) when it is
## loaded, otherwise straight into GameState (bare headless tests).
static func apply_diffs(diffs: Array) -> void:
	if diffs.is_empty():
		return
	var pm = phase_manager()
	if pm and pm.has_method("apply_state_changes"):
		pm.apply_state_changes(diffs)
		return
	var gs = game_state()
	if gs and gs.has_method("apply_state_changes"):
		gs.apply_state_changes(diffs)
