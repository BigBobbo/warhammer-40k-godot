extends RefCounted

## OrkCodexCommon — shared helpers for the Codex: Orks (11e) stratagem handlers.
##
## Design contract: .llm/ork_codex_11e_design.md §4. The dispatcher
## (OrkCodex11e.gd) and the four group scripts (OrkCodexFight/Shooting/
## Movement/Other.gd) all preload THIS file, never each other, so the group
## scripts can be edited in parallel without preload cycles.
##
## Every autoload is reached late-bound (Engine.get_main_loop().root…): naked
## autoload globals fail to compile when a headless `--script` test parses a
## script that references them before the autoloads are registered (the same
## rule AIDecisionMaker.gd follows).

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

static func player_cp(player: int) -> int:
	return int(state().get("players", {}).get(str(player), {}).get("cp", 0))

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
	return true

## "Riled up" = the 11e Waaagh! state (design §4): the army-wide Waaagh! flag
## OR a per-unit riled-up flag set by a codex effect (e.g. DREAD POWER).
static func is_riled_up(u: Dictionary) -> bool:
	var flags = u.get("flags", {})
	return bool(flags.get("waaagh_active", false)) or bool(flags.get("ork11e_riled_up", false))

static func is_battle_shocked(u: Dictionary) -> bool:
	return bool(u.get("flags", {}).get("battle_shocked", false))

## The unit plus every component of its Attached unit (19.03). Attached
## CHARACTERs resolve their attacks against their own unit id, so a unit-wide
## grant (e.g. HIT 'EM HARDER) must be written to every component.
static func attached_group_ids(unit_id: String) -> Array:
	var units = state().get("units", {})
	var head = unit_id
	var re = rules()
	if re and re.has_method("attached_unit_target_id"):
		head = str(re.attached_unit_target_id(unit_id, state()))
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

static func has_melee_weapons(unit_id: String) -> bool:
	var re = rules()
	if re and re.has_method("get_unit_melee_weapons"):
		return not re.get_unit_melee_weapons(unit_id, state()).is_empty()
	return false

static func points(u: Dictionary) -> int:
	return int(u.get("meta", {}).get("points", 0))

# ---------------------------------------------------------------------------
# Distance helpers (edge-to-edge, inches)
# ---------------------------------------------------------------------------

## Closest edge-to-edge distance between any two alive models of two units.
static func unit_distance_inches(a_id: String, b_id: String) -> float:
	var a = unit(a_id)
	var b = unit(b_id)
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

static func within_inches(a_id: String, b_id: String, inches: float) -> bool:
	return unit_distance_inches(a_id, b_id) <= inches + 0.001

# ---------------------------------------------------------------------------
# Flag helpers — scoped writes as diffs (replay/network safe) and in-place
# clears (StratagemManager._clear_stratagem_flags convention).
# ---------------------------------------------------------------------------

static func set_flag_diffs(unit_ids: Array, flag: String, value) -> Array:
	var diffs: Array = []
	for uid in unit_ids:
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(uid), flag], "value": value})
	return diffs

static func erase_flags(unit_ids: Array, flag_names: Array) -> void:
	var units = state().get("units", {})
	for uid in unit_ids:
		var u = units.get(str(uid), {})
		if u.is_empty():
			continue
		var flags = u.get("flags", {})
		for f in flag_names:
			flags.erase(str(f))

## Standard target entry shape for StratagemManager.get_window_offers.
static func target_entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	var entry = {"unit_id": unit_id, "label": unit_name(unit_id) if unit_id != "" else "Use"}
	entry.merge(extra, true)
	return entry
