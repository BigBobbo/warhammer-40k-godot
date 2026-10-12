extends RefCounted
class_name OrkCodex11e

## OrkCodex11e — dispatcher for the Codex: Orks (11e) stratagems.
##
## Contract: .llm/ork_codex_11e_design.md §3–§4, §6.
##
## StratagemManager calls this dispatcher FIRST — before every legacy
## name-keyed handler — in can_use_stratagem (validate), _apply_stratagem_effects
## (apply), _clear_stratagem_flags (clear), implemented marking
## (is_implemented) and get_window_offers (eligible_targets). Dispatch is keyed
## by csv_id (the CSV `id` column), so a legacy 10e handler that shares a NAME
## with a codex stratagem (TOO ARROGANT TO DIE, ARMED TO DA TEEF, DAKKASTORM,
## …) can never fire for a codex row.
##
## A codex row = a stratagem whose effects_json is the single marker
## {"type": "custom:ork11e"}. handles() is true for EVERY codex row, even one
## whose csv_id is missing from the registry: an unregistered row is reported
## loudly and does nothing, rather than falling through to a 10e handler.
##
## Group scripts (one per implementation group, edited in parallel):
##   OrkCodexFight.gd, OrkCodexShooting.gd, OrkCodexMovement.gd, OrkCodexOther.gd
## Each lists its csv_ids in IDS and the finished ones in IMPLEMENTED.

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
const GroupFight = preload("res://scripts/stratagems/ork_codex/OrkCodexFight.gd")
const GroupShooting = preload("res://scripts/stratagems/ork_codex/OrkCodexShooting.gd")
const GroupMovement = preload("res://scripts/stratagems/ork_codex/OrkCodexMovement.gd")
const GroupOther = preload("res://scripts/stratagems/ork_codex/OrkCodexOther.gd")

const MARKER_EFFECT := "custom:ork11e"


static func _groups() -> Array:
	return [GroupFight, GroupShooting, GroupMovement, GroupOther]


## True for every Codex: Orks (11e) row (effects_json marker), registered or not.
static func handles(strat: Dictionary) -> bool:
	var effects = strat.get("effects", [])
	if typeof(effects) != TYPE_ARRAY or effects.is_empty():
		return false
	var first = effects[0]
	return typeof(first) == TYPE_DICTIONARY and str(first.get("type", "")) == MARKER_EFFECT


## Group script that owns csv_id, or null.
static func group_for_id(csv_id: String):
	for g in _groups():
		if csv_id in g.IDS:
			return g
	return null


static func group_for(strat: Dictionary):
	return group_for_id(str(strat.get("csv_id", "")))


static func is_registered(strat: Dictionary) -> bool:
	return handles(strat) and group_for(strat) != null


## The registry decides "implemented" (design §1): never name lists or regexes.
static func is_implemented(strat: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null:
		return false
	return bool(g.IMPLEMENTED.get(str(strat.get("csv_id", "")), false))


## Every registered csv_id (for tests / coverage reports).
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


## Candidate targets for a window offer. Only implemented stratagems produce
## any; StratagemManager.get_window_offers re-validates each candidate through
## can_use_stratagem (CP, once-per-phase, 15.01, turn/phase, window, validate).
static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	if not is_implemented(strat):
		return []
	var g = group_for(strat)
	var out = g.eligible_targets(strat, player, window_id, ctx)
	return out if typeof(out) == TYPE_ARRAY else []


## Rule-specific target validation. Returns {ok, reason}.
static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = group_for(strat)
	if g == null:
		return {"ok": false, "reason": "%s is not registered in the Ork codex dispatcher" % strat.get("name", "?")}
	if not is_implemented(strat):
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	var v = g.validate(strat, player, target_unit_id, ctx)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid validate() result"}
	return v


## Apply the effect. Returns an Array of diffs, or {diffs: Array, followup: Dictionary}
## when the phase that opened the window must execute a follow-up (design §3.2).
static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = group_for(strat)
	if g == null:
		Common.log_error("OrkCodex11e: no handler registered for codex stratagem %s (%s) — effect NOT applied" % [
			strat.get("name", "?"), strat.get("csv_id", "?")])
		return []
	return g.apply(strat, target_unit_id, ctx)


## Undo the effect's flags when it expires.
static func clear(strat: Dictionary, unit_id: String) -> void:
	var g = group_for(strat)
	if g == null:
		return
	g.clear(strat, unit_id)


## Effective CP cost, honouring a chosen variant (ctx.variant_id).
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


static func allows_battle_shocked_target(strat: Dictionary, ctx: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null or not is_implemented(strat):
		return false
	return bool(g.allows_battle_shocked_target(strat, ctx))


## AI helpers used by AIDecisionMaker.decide_window_stratagem.
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


# ---------------------------------------------------------------------------
# Shared helpers re-exported for callers outside the codex scripts.
# ---------------------------------------------------------------------------

static func is_riled_up(unit: Dictionary) -> bool:
	return Common.is_riled_up(unit)

static func has_keyword(unit: Dictionary, keyword: String) -> bool:
	return Common.has_keyword(unit, keyword)

static func unit_distance_inches(a_id: String, b_id: String) -> float:
	return Common.unit_distance_inches(a_id, b_id)
