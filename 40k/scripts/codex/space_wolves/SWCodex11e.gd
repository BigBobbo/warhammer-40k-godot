extends RefCounted

## SWCodex11e — dispatcher for the Codex: Space Marines (11e) SPACE WOLVES
## detachment stratagems (WP-S3: Champions of Fenris, Saga of the Beastslayer,
## Saga of the Great Wolf — 12 stratagems).
##
## Contract: .llm/codex_11e_wahapedia/PLAN_SPACE_WOLVES.md + IMPLEMENTATION.md
## (§2, §3); same API as CustodesCodex11e.gd / OrkCodex11e.gd. Rulings:
## .llm/codex_11e_wahapedia/RULINGS.md § WP-S3.
##
## StratagemManager.codex_for() returns this dispatcher for every row whose
## effects_json is the single marker {"type": "custom:sw11e"} (40k/data/
## Stratagems.csv, SW|… rows), so it is called FIRST — before every legacy
## name-keyed handler — in can_use_stratagem (validate), _apply_stratagem_effects
## (apply), _clear_stratagem_flags (clear), implemented marking (is_implemented)
## and get_window_offers (eligible_targets). Dispatch is keyed by csv_id.
##
## Group scripts (they preload ONLY SWCommon.gd, never each other / this file):
##   SWCodexCombat.gd   HEROIC RESOLVE, CHAMPION'S GUIDANCE, UNBRIDLED FEROCITY,
##                      FANGS OF THE PACK, EYE OF THE PACK, WOLF TOTEMS
##   SWCodexMovement.gd IMPETUOSITY, BATTLE INSTINCTS, FENRISIAN FEROCITY,
##                      CO-ORDINATED STRIKE
##   SWCodexCommand.gd  BIRTH OF A SAGA, GRIMNAR'S COMMAND
##
## Engine-side effect consumers are at the bottom of this file; the engine
## files call them through one-line hooks commented "Codex: Space Marines (11e)
## Space Wolves … (SWCodex11e.gd)".

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GroupCombat = preload("res://scripts/codex/space_wolves/SWCodexCombat.gd")
const GroupMovement = preload("res://scripts/codex/space_wolves/SWCodexMovement.gd")
const GroupCommand = preload("res://scripts/codex/space_wolves/SWCodexCommand.gd")

const MARKER_EFFECT := "custom:sw11e"

# RulesEngine.HitModifier / WoundModifier values (pinned by
# tests/test_sw11e_stratagems.gd so a renumbering is caught).
const HIT_REROLL_ONES := 1
const WOUND_REROLL_ONES := 1
const WOUND_REROLL_ONES_TWOS := 16


static func _groups() -> Array:
	return [GroupCombat, GroupMovement, GroupCommand]


## True for every Codex: Space Marines (11e) Space Wolves row (effects_json marker), registered or not.
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


## The registry decides "implemented" — never name lists or regexes.
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


## Candidate targets for a window offer (re-validated by StratagemManager).
static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	if not is_implemented(strat):
		return []
	var out = group_for(strat).eligible_targets(strat, player, window_id, ctx)
	return out if typeof(out) == TYPE_ARRAY else []


## Rule-specific target validation. Returns {ok, reason}.
static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = group_for(strat)
	if g == null:
		return {"ok": false, "reason": "%s is not registered in the Space Wolves codex dispatcher" % strat.get("name", "?")}
	if not is_implemented(strat):
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	if not Common.is_sw_army(player):
		return {"ok": false, "reason": "%s: only a Space Wolves army (Codex: Space Marines 11e) can use it" % strat.get("name", "?")}
	var v = g.validate(strat, player, target_unit_id, ctx)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid validate() result"}
	return v


## Apply the effect: an Array of diffs, or {diffs, followup}.
static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = group_for(strat)
	if g == null:
		Common.log_error("SWCodex11e: no handler registered for codex stratagem %s (%s) — effect NOT applied" % [
			strat.get("name", "?"), strat.get("csv_id", "?")])
		return []
	return g.apply(strat, target_unit_id, ctx)


static func clear(strat: Dictionary, unit_id: String) -> void:
	var g = group_for(strat)
	if g == null:
		return
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


## True when `player` has an implemented Space Wolves stratagem offered in `window_id`.
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


# ===========================================================================
# ENGINE HOOKS — called from RulesEngine / EffectPrimitives / the phases
# ===========================================================================

## CHAMPION'S GUIDANCE: the unit's melee attacks can re-roll hit rolls of 1.
## Folded into a RulesEngine HitModifier bit set (+ the modifier ledger).
static func apply_hit_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, ledger: Array) -> int:
	if GameConstants.edition < 11:
		return bits
	var src := GroupCombat.hit_reroll_ones_source(attacker_unit, is_melee)
	if src == "":
		return bits
	ModifierLedger.note(ledger, src, ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "Codex: Space Marines stratagem")
	Common.log_info("[SWCodex11e] %s — %s re-rolls %s hit rolls of 1 (vs %s)" % [src, str(attacker_unit.get("id", "?")),
		"melee" if is_melee else "ranged", str(target_unit.get("id", "?"))])
	return bits | HIT_REROLL_ONES

## CHAMPION'S GUIDANCE (melee: re-roll wound rolls of 1) and EYE OF THE PACK
## (every attack: re-roll wound rolls of 1 and 2 — WoundModifier.REROLL_ONES_TWOS).
static func apply_wound_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, ledger: Array) -> int:
	if GameConstants.edition < 11:
		return bits
	var fx := GroupCombat.wound_reroll_effects(attacker_unit, is_melee)
	var out := bits
	if str(fx.get("ones_twos", "")) != "":
		out |= WOUND_REROLL_ONES_TWOS
		ModifierLedger.note(ledger, str(fx.ones_twos), ModifierLedger.KIND_WOUND, "re-roll wound rolls of 1 and 2", "Codex: Space Marines stratagem")
	if str(fx.get("ones", "")) != "":
		out |= WOUND_REROLL_ONES
		ModifierLedger.note(ledger, str(fx.ones), ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_ONES, "Codex: Space Marines stratagem")
	if out != bits:
		Common.log_info("[SWCodex11e] wound re-rolls (%s) for %s vs %s: %s -> bits %d" % ["melee" if is_melee else "ranged",
			str(attacker_unit.get("id", "?")), str(target_unit.get("id", "?")), str(fx), out])
	return out

## HEROIC RESOLVE: attacks that target this unit have -1 D (EffectPrimitives.get_effect_minus_damage).
static func damage_minus(target_unit: Dictionary) -> int:
	return GroupCombat.damage_minus(target_unit)

## WOLF TOTEMS: Feel No Pain 5+ against mortal wounds (RulesEngine._conditional_fnp). 0 = none.
static func fnp_vs_mortal(unit: Dictionary) -> int:
	return GroupCombat.fnp_vs_mortal(unit)

## An attacking unit has finished its attacks: HEROIC RESOLVE ("until that
## enemy unit has attacked") ends for the units it protected against it.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	GroupCombat.on_unit_has_attacked(attacker_unit_id)
