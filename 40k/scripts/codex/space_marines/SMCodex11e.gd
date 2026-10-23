extends RefCounted

# WP-M3b stub — the integrator keeps M3a's version.
#
## SMCodex11e — MINIMAL stand-in for WP-M3a's `custom:sm11e` dispatcher (same
## API as SWCodex11e.gd), written by WP-M3b only so the in-game path of the
## SMCodexB.gd stratagems can be driven before M3a lands. It knows no group
## script but SMCodexB.gd (loaded when the file exists, as the M3a contract
## says). M3a's real dispatcher replaces this file wholesale on merge.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const MARKER_EFFECT := "custom:sm11e"
const GROUP_B_PATH := "res://scripts/codex/space_marines/SMCodexB.gd"


static func _groups() -> Array:
	var out: Array = []
	if ResourceLoader.exists(GROUP_B_PATH):
		out.append(load(GROUP_B_PATH))
	return out


static func handles(strat: Dictionary) -> bool:
	var effects = strat.get("effects", [])
	if typeof(effects) != TYPE_ARRAY or effects.is_empty():
		return false
	var first = effects[0]
	return typeof(first) == TYPE_DICTIONARY and str(first.get("type", "")) == MARKER_EFFECT


static func group_for_id(csv_id: String):
	for g in _groups():
		if csv_id in g.IDS:
			return g
	return null


static func group_for(strat: Dictionary):
	return group_for_id(str(strat.get("csv_id", "")))


static func is_registered(strat: Dictionary) -> bool:
	return handles(strat) and group_for(strat) != null


static func is_implemented(strat: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null:
		return false
	return bool(g.IMPLEMENTED.get(str(strat.get("csv_id", "")), false))


static func all_registered_ids() -> Array:
	var out: Array = []
	for g in _groups():
		out.append_array(g.IDS)
	return out


static func all_implemented_ids() -> Array:
	var out: Array = []
	for g in _groups():
		for k in g.IMPLEMENTED:
			if g.IMPLEMENTED[k]:
				out.append(k)
	return out


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	if not is_implemented(strat):
		return []
	var out = group_for(strat).eligible_targets(strat, player, window_id, ctx)
	return out if typeof(out) == TYPE_ARRAY else []


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = group_for(strat)
	if g == null:
		return {"ok": false, "reason": "%s is not registered in the Space Marines codex dispatcher" % strat.get("name", "?")}
	if not is_implemented(strat):
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	if not Common.is_sm_army(player):
		return {"ok": false, "reason": "%s: only a Space Marines army (Codex: Space Marines 11e) can use it" % strat.get("name", "?")}
	var v = g.validate(strat, player, target_unit_id, ctx)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid validate() result"}
	return v


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = group_for(strat)
	if g == null:
		Common.log_error("SMCodex11e: no handler registered for codex stratagem %s (%s) — effect NOT applied" % [
			strat.get("name", "?"), strat.get("csv_id", "?")])
		return []
	return g.apply(strat, target_unit_id, ctx)


static func clear(strat: Dictionary, unit_id: String) -> void:
	var g = group_for(strat)
	if g != null:
		g.clear(strat, unit_id)


static func cp_cost_for(strat: Dictionary, ctx: Dictionary) -> int:
	var base := int(strat.get("cp_cost", 1))
	var variant := str(ctx.get("variant_id", ""))
	if variant == "":
		return base
	var g = group_for(strat)
	if g == null:
		return base
	var v := int(g.variant_cp_cost(strat, variant))
	return v if v >= 0 else base


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if variant_id == "":
		return ""
	var g = group_for(strat)
	if g == null or not g.has_method("variant_label"):
		return ""
	return str(g.variant_label(strat, variant_id))


static func allows_battle_shocked_target(strat: Dictionary, ctx: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null or not is_implemented(strat):
		return false
	return bool(g.allows_battle_shocked_target(strat, ctx))


static func ai_kind(strat: Dictionary) -> String:
	var g = group_for(strat)
	if g == null:
		return "utility"
	return str(g.ai_kind(strat))


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var g = group_for(strat)
	if g == null or not is_implemented(strat):
		return 0.0
	return float(g.ai_score(strat, player, target_unit_id, window_id, ctx))


static func player_has_window_stratagem(player: int, window_id: String) -> bool:
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_faction_stratagems_for_player"):
		return false
	for s in sm.get_faction_stratagems_for_player(player):
		if not handles(s) or not is_implemented(s):
			continue
		if window_id in s.get("timing", {}).get("windows", []):
			return true
	return false
