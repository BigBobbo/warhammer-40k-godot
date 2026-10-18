extends RefCounted

## CustodesCodex11e — dispatcher for the Codex: Adeptus Custodes (11e)
## stratagems (WP-C5).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md (§2, §3) and the
## pattern of .llm/ork_codex_11e_design.md §3–§6 (OrkCodex11e.gd is the model:
## the API below is the same). Rulings: RULINGS.md § WP-C5.
##
## StratagemManager calls this dispatcher FIRST — before every legacy
## name-keyed handler — in can_use_stratagem (validate), _apply_stratagem_effects
## (apply), _clear_stratagem_flags (clear), implemented marking
## (is_implemented) and get_window_offers (eligible_targets). Dispatch is keyed
## by csv_id (the CSV `id` column): the 10e handlers that share a NAME with a
## codex stratagem (GILDED CHAMPION, UNLEASH THE LIONS, SWIFT AS THE EAGLE,
## MANOEUVRE AND FIRE, ...) can never fire for a codex row, and the three names
## printed twice with different text (IN AURAMITE CLAD, SUPERHUMAN FOCUS, SWIFT
## AS THE EAGLE) are told apart by their detachment-scoped csv_id.
##
## A codex row = a stratagem whose effects_json is the single marker
## {"type": "custom:custodes11e"}. handles() is true for EVERY codex row, even
## one whose csv_id is missing from the registry: an unregistered row is
## reported loudly and does nothing.
##
## Group scripts (one per implementation group; they preload ONLY
## CustodesCommon.gd, never each other or this file):
##   CustodesCodexFight.gd, CustodesCodexShooting.gd,
##   CustodesCodexMovement.gd, CustodesCodexOther.gd
## Each lists its csv_ids in IDS and the finished ones in IMPLEMENTED.
##
## The engine-side effect consumers are at the bottom of this file: the engine
## files call them through one-line hooks (`_cus11e_codex().<hook>(...)`, each
## commented "Codex: Adeptus Custodes stratagems (CustodesCodex11e.gd)").

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")
const GroupFight = preload("res://scripts/codex/custodes/CustodesCodexFight.gd")
const GroupShooting = preload("res://scripts/codex/custodes/CustodesCodexShooting.gd")
const GroupMovement = preload("res://scripts/codex/custodes/CustodesCodexMovement.gd")
const GroupOther = preload("res://scripts/codex/custodes/CustodesCodexOther.gd")

const MARKER_EFFECT := "custom:custodes11e"


static func _groups() -> Array:
	return [GroupFight, GroupShooting, GroupMovement, GroupOther]


## True for every Codex: Adeptus Custodes (11e) row (effects_json marker), registered or not.
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


## The registry decides "implemented" — never name lists or regexes.
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
		return {"ok": false, "reason": "%s is not registered in the Adeptus Custodes codex dispatcher" % strat.get("name", "?")}
	if not is_implemented(strat):
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	var v = g.validate(strat, player, target_unit_id, ctx)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid validate() result"}
	return v


## Apply the effect. Returns an Array of diffs, or {diffs: Array, followup: Dictionary}
## when the phase that opened the window must execute a follow-up.
static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = group_for(strat)
	if g == null:
		Common.log_error("CustodesCodex11e: no handler registered for codex stratagem %s (%s) — effect NOT applied" % [
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


## Player-facing label of a chosen variant for the game log ("" = none).
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


## AI helpers used by AIDecisionMaker.decide_window_stratagem / the panel AI.
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


# ===========================================================================
# ENGINE HOOKS — called from RulesEngine / EffectPrimitives / the phases
# through one-line hooks. Each delegates to the group that owns the flag.
# ===========================================================================

# == RulesEngine.HitModifier / WoundModifier values (pinned by
# tests/test_custodes_codex_framework.gd so a renumbering is caught).
const HIT_REROLL_ONES := 1
const HIT_PLUS_ONE := 2
const HIT_MINUS_ONE := 4
const WOUND_PLUS_ONE := 4
const WOUND_MINUS_ONE := 8

## AP of one attack batch against `target_unit` (every AP site: ranged
## interactive / auto / overwatch, melee auto / interactive saves).
## PSY-CHAFF VOLLEY (+1 AP vs a prosecuted unit) and IN AURAMITE CLAD (-1 AP).
static func modify_ap(ap: int, attacker_unit: Dictionary, target_unit: Dictionary) -> int:
	return GroupShooting.modify_ap(ap, attacker_unit, target_unit)

## Hit-roll effects of the Custodes stratagems on one attack batch:
## {minus, reroll_ones, ignore_minus, sources}.
static func hit_roll_effects(attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, board: Dictionary = {}) -> Dictionary:
	var out := {"minus": false, "reroll_ones": false, "ignore_minus": false, "sources": []}
	GroupShooting.hit_roll_effects(out, attacker_unit, target_unit, is_melee, board)
	GroupFight.hit_roll_effects(out, attacker_unit, target_unit, is_melee, board)
	GroupMovement.hit_roll_effects(out, attacker_unit, target_unit, is_melee, board)
	return out

## Apply hit_roll_effects to a RulesEngine HitModifier bit set (+ the modifier
## ledger). Placed after every other hit modifier at each site, so "ignore
## modifiers" (BEARERS OF HIS LIGHT, INEVITABLE ANNIHILATION) sees them all.
static func apply_hit_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, board: Dictionary, ledger: Array) -> int:
	var fx := hit_roll_effects(attacker_unit, target_unit, is_melee, board)
	var out := bits
	if bool(fx.get("reroll_ones", false)):
		out |= HIT_REROLL_ONES
		ModifierLedger.note(ledger, _src(fx, "Honoured Interred"), ModifierLedger.KIND_HIT, ModifierLedger.REROLL_ONES, "Codex: Adeptus Custodes stratagem")
	if bool(fx.get("minus", false)):
		out |= HIT_MINUS_ONE
		ModifierLedger.note(ledger, _src(fx, "Shield of Honour", "Golden Light"), ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "Codex: Adeptus Custodes stratagem")
	if bool(fx.get("ignore_minus", false)) and (out & HIT_MINUS_ONE):
		out = out & ~HIT_MINUS_ONE
		ModifierLedger.note(ledger, _src(fx, "Bearers of His Light", "Inevitable Annihilation"), ModifierLedger.KIND_HIT, ModifierLedger.IGNORED, "hit-roll penalties ignored")
		ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
	if not fx.sources.is_empty():
		Common.log_info("[CustodesCodex11e] hit roll (%s): %s -> bits %d" % ["melee" if is_melee else "ranged", str(fx.sources), out])
	return out

## Wound-roll effects of the Custodes stratagems: {plus, minus, ignore_minus, sources}.
static func wound_roll_effects(attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, strength: int, toughness: int) -> Dictionary:
	var out := {"plus": false, "minus": false, "ignore_minus": false, "sources": []}
	GroupFight.wound_roll_effects(out, attacker_unit, target_unit, is_melee, strength, toughness)
	return out

## Apply wound_roll_effects to a RulesEngine WoundModifier bit set (+ ledger).
static func apply_wound_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, strength: int, toughness: int, ledger: Array) -> int:
	var fx := wound_roll_effects(attacker_unit, target_unit, is_melee, strength, toughness)
	var out := bits
	if bool(fx.get("plus", false)):
		out |= WOUND_PLUS_ONE
		ModifierLedger.note(ledger, _src(fx, "Slayers of Nightmares"), ModifierLedger.KIND_WOUND, ModifierLedger.PLUS_ONE, "Codex: Adeptus Custodes stratagem")
	if bool(fx.get("minus", false)):
		out |= WOUND_MINUS_ONE
		ModifierLedger.note(ledger, _src(fx, "Shield of Honour"), ModifierLedger.KIND_WOUND, ModifierLedger.MINUS_ONE, "Codex: Adeptus Custodes stratagem")
	if bool(fx.get("ignore_minus", false)) and (out & WOUND_MINUS_ONE):
		out = out & ~WOUND_MINUS_ONE
		ModifierLedger.note(ledger, _src(fx, "Bearers of His Light"), ModifierLedger.KIND_WOUND, ModifierLedger.IGNORED, "wound-roll penalties ignored")
		ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_WOUND, [ModifierLedger.MINUS_ONE])
	if not fx.sources.is_empty():
		Common.log_info("[CustodesCodex11e] wound roll (%s): %s -> bits %d" % ["melee" if is_melee else "ranged", str(fx.sources), out])
	return out

## The first source naming one of `names` (ledger label), else the first source.
static func _src(fx: Dictionary, a: String, b: String = "") -> String:
	for s in fx.get("sources", []):
		if str(s).begins_with(a) or (b != "" and str(s).begins_with(b)):
			return str(s)
	var srcs: Array = fx.get("sources", [])
	return str(srcs[0]) if not srcs.is_empty() else a

## Remove the harmful entries (BS worsening, negative hit-roll modifiers) of an
## 11e hit ModifierStack when a stratagem lets the attacker ignore them
## (INEVITABLE ANNIHILATION). Returns the sources removed.
static func filter_hit_stack(attacker_unit: Dictionary, stack, is_melee: bool) -> Array:
	return GroupShooting.filter_hit_stack(attacker_unit, stack, is_melee)

## True when a stratagem lets the attacker ignore BS worsening (cover).
static func ignores_bs_worsening(attacker_unit: Dictionary, is_melee: bool) -> bool:
	return GroupShooting.ignores_bs_worsening(attacker_unit, is_melee)

## Extra attacks per model for one weapon batch (ranged: PURGATION SWEEP on
## [TORRENT] weapons; melee: AVENGE THE FALLEN, non-CHARACTER models only).
static func bonus_attacks_per_model(attacker_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_torrent: bool, is_melee: bool) -> int:
	if is_melee:
		return GroupFight.bonus_melee_attacks_per_model(attacker_unit, target_unit)
	return GroupShooting.bonus_ranged_attacks_per_model(attacker_unit, target_unit, weapon_profile, is_torrent)

## Strength bonus for one ranged batch (TIP OF THE TALON: +1 S vs within 9").
static func ranged_strength_bonus(attacker_unit: Dictionary, target_unit: Dictionary, board: Dictionary = {}) -> int:
	return GroupShooting.ranged_strength_bonus(attacker_unit, target_unit, board)

## [LETHAL HITS: CHARACTER/MONSTER] (GRIM RESPONSIBILITY) for one melee batch.
static func melee_lethal_hits(attacker_unit: Dictionary, target_unit: Dictionary) -> bool:
	return GroupFight.melee_lethal_hits(attacker_unit, target_unit)

## PRIME TARGET: the single re-roll still available to this unit's ranged
## attacks for `stage` ("hit" | "wound" | "damage").
static func single_reroll_available(attacker_unit: Dictionary, stage: String, is_melee: bool = false) -> bool:
	return GroupShooting.single_reroll_available(attacker_unit, stage, is_melee)

## Diffs that spend the single re-roll of `stage` (PRIME TARGET).
static func single_reroll_spend_diffs(attacker_unit_id: String, stage: String) -> Array:
	return GroupShooting.single_reroll_spend_diffs(attacker_unit_id, stage)

## Spend PRIME TARGET's single re-roll of `stage` in place (auto-resolved
## attacks: RulesEngine works on a board copy, the live state is updated here).
static func spend_single_reroll(attacker_unit_id: String, stage: String) -> void:
	var diffs := GroupShooting.single_reroll_spend_diffs(attacker_unit_id, stage)
	Common.apply_diffs(diffs)
	Common.log_info("[CustodesCodex11e] PRIME TARGET: %s spent its %s re-roll" % [attacker_unit_id, stage])

## PRIME TARGET in auto-resolved ranged attacks (one line at each RulesEngine
## site): re-roll the first FAILED hit roll / wound roll of the unit (a die
## that was already re-rolled cannot be re-rolled again; indirect shooting
## forbids hit re-rolls), and a variable damage roll below the dice average.
static func auto_single_reroll_hit(hit_eval: Dictionary, raw_roll: int, attacker_unit: Dictionary, bs: int, mods: int, crit: int, rng, fail_band: int, no_hit_rerolls: bool) -> Dictionary:
	if bool(hit_eval.get("is_hit", false)) or bool(hit_eval.get("rerolled", false)) or no_hit_rerolls:
		return hit_eval
	if not GroupShooting.take_single_reroll(attacker_unit, "hit"):
		return hit_eval
	var new_roll := int(rng.roll_d6(1)[0])
	var out: Dictionary = AttackSequence.evaluate_hit_roll(new_roll, bs, mods & ~(HIT_REROLL_ONES | 8 | 16), crit, rng, fail_band)
	out["rerolled"] = true
	out["reroll_from"] = raw_roll
	out["reroll_to"] = new_roll
	Common.log_info("[CustodesCodex11e] PRIME TARGET: hit roll %d re-rolled -> %d (%s)" % [raw_roll, new_roll, "hit" if out.is_hit else "miss"])
	return out

static func auto_single_reroll_wound(wound_eval: Dictionary, raw_roll: int, attacker_unit: Dictionary, mods: int, threshold: int, crit: int, rng) -> Dictionary:
	if bool(wound_eval.get("is_wound", false)) or bool(wound_eval.get("rerolled", false)):
		return wound_eval
	if not GroupShooting.take_single_reroll(attacker_unit, "wound"):
		return wound_eval
	var new_roll := int(rng.roll_d6(1)[0])
	# 2 = WoundModifier.REROLL_FAILED, 1 = REROLL_ONES: a re-rolled die is final.
	var out: Dictionary = AttackSequence.evaluate_wound_roll(new_roll, mods & ~(1 | 2), threshold, crit, rng)
	out["rerolled"] = true
	out["reroll_from"] = raw_roll
	out["reroll_to"] = new_roll
	Common.log_info("[CustodesCodex11e] PRIME TARGET: wound roll %d re-rolled -> %d (%s)" % [raw_roll, new_roll, "wound" if out.is_wound else "fail"])
	return out

## dmg_result: RulesEngine.roll_variable_characteristic's {value, rolled, ...}.
static func auto_single_reroll_damage(dmg_result: Dictionary, damage_raw: String, attacker_unit: Dictionary, rng) -> Dictionary:
	if not bool(dmg_result.get("rolled", false)):
		return dmg_result
	var re = Common.rules()
	if re == null:
		return dmg_result
	var avg := _avg_dice(damage_raw)
	if float(dmg_result.get("value", 0)) >= avg:
		return dmg_result
	if not GroupShooting.take_single_reroll(attacker_unit, "damage"):
		return dmg_result
	var again: Dictionary = re.roll_variable_characteristic(damage_raw, rng)
	Common.log_info("[CustodesCodex11e] PRIME TARGET: damage roll %s re-rolled %d -> %d" % [damage_raw, int(dmg_result.get("value", 0)), int(again.get("value", 0))])
	again["prime_target_reroll_from"] = int(dmg_result.get("value", 0))
	return again

static func _avg_dice(raw: String) -> float:
	var s := raw.to_upper().replace(" ", "")
	var plus := 0.0
	if "+" in s:
		var parts := s.split("+")
		s = parts[0]
		plus = float(parts[1]) if parts[1].is_valid_float() else 0.0
	var d := s.find("D")
	if d < 0:
		return float(s) + plus if s.is_valid_float() else plus
	var n := 1.0 if d == 0 else (float(s.substr(0, d)) if s.substr(0, d).is_valid_float() else 1.0)
	var faces := float(s.substr(d + 1)) if s.substr(d + 1).is_valid_float() else 6.0
	return n * (faces + 1.0) / 2.0 + plus

## GOLDEN LIGHT OF THE MOIRAIDES: enemy units cannot target this unit with
## snap shooting attacks (Fire Overwatch).
static func blocks_snap_shooting_at(target_unit: Dictionary) -> bool:
	return GroupMovement.blocks_snap_shooting_at(target_unit)

## The 2D6 of a charge a stratagem declares (SELFLESS SERVICE, NO ESCAPE).
static func roll_charge_dice() -> Array:
	return Common.roll_dice(2, 6)

## NO ESCAPE's charge, auto-resolved (CustodesCodexMovement.resolve_reactive_charge):
## {diffs (not applied), success, roll, target_id, message}.
static func resolve_reactive_charge(player: int, followup: Dictionary) -> Dictionary:
	return GroupMovement.resolve_reactive_charge(player, followup)

## Charge-roll modifier for `unit` (FURY OF THE EMPEROR +2, GRAVIMETRIC
## GRENADE -1, INEXORABLE ignores the harmful part). `base_bonus` = the
## modifier the engine already computed; returns the total to add.
static func charge_roll_modifier(unit: Dictionary, base_bonus: int) -> int:
	return GroupOther.charge_roll_modifier(unit, base_bonus)

## INEXORABLE: the unit ignores harmful modifiers to its M / advance rolls.
static func ignores_move_penalties(unit: Dictionary) -> bool:
	return GroupMovement.ignores_move_penalties(unit)

## Turn-long grants read by EffectPrimitives' has_effect_* helpers:
## what = advance_and_charge | advance_and_shoot | fall_back_and_shoot |
## fall_back_and_charge.
static func grants(unit: Dictionary, what: String) -> bool:
	if GroupMovement.grants(unit, what):
		return true
	return what == "advance_and_shoot" and GroupShooting.grants_ranged_assault(unit)

## FightSequencer candidates for `player` — INDOMITABLE GUARDIANS: "must be the
## next unit you select to fight".
static func restrict_fight_candidates(player: int, candidates: Array) -> Array:
	var forced := GroupFight.forced_next_fighter(player)
	if forced != "" and forced in candidates:
		return [forced]
	return candidates

static func forced_next_fighter(player: int) -> String:
	return GroupFight.forced_next_fighter(player)

## LIGHTNING WRATH: the pile-in distance of this unit's pile-in move (0 = the
## core 3").
static func pile_in_inches(unit_id: String) -> float:
	return GroupFight.pile_in_inches(unit_id)

## EMPEROR'S DOMAIN: the objective consolidation mode may be chosen
## regardless of the Before Moving restrictions.
static func consolidation_objective_override(unit_id: String) -> bool:
	return GroupFight.consolidation_objective_override(unit_id)

## DUTY UNTO DEATH Fight On Death roll ({mod, note, pass}) — FightPhase asks
## this when the unit's ork11e_fod_mode is "cus11e_duty_unto_death".
static func fod_roll(unit_id: String, model_index: int) -> Dictionary:
	return GroupFight.fod_roll(unit_id, model_index)

static func is_fod_mode(mode: String) -> bool:
	return mode == GroupFight.FOD_MODE_DUTY

## ADVANCED STABILISERS: an Advanced GRAV-ASSAULT unit may be selected to
## shoot when the stratagem could make its weapons [ASSAULT].
static func may_select_advanced_unit_to_shoot(unit: Dictionary) -> bool:
	return GroupShooting.may_select_advanced_unit_to_shoot(unit)

## An attacking unit has finished its attacks (BasePhase event detection):
## the effects that last "until that enemy unit has attacked" end (VIGIL
## UNENDING, IN AURAMITE CLAD).
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	GroupShooting.on_unit_has_attacked(attacker_unit_id)

## RAPID REACTIONS follow-up: auto-resolved normal shooting assignments.
static func forced_shoot_assignments(unit_id: String, target_id: String) -> Array:
	return GroupMovement.forced_shoot_assignments(unit_id, target_id)

## NO ESCAPE follow-up: the fell-back enemy units (heads) for `player`.
static func fell_back_enemy_heads(player: int) -> Array:
	return GroupMovement.fell_back_enemy_heads(player)

## True when `player` has an implemented Custodes codex stratagem offered in
## `window_id` (the phases only route a UI step through a new window action
## when it could offer something — no behaviour change for other armies).
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
