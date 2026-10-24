extends RefCounted

## SMCodexB — Codex: Space Marines (11e) stratagems of the eight WP-M2b
## detachments (WP-M3b, 24 stratagems): Terminator Storm Force, Assault
## Brethren, Gravis Linebreaker Force, Devastator Brethren, Gravis Siege
## Force, Tactical Brethren, Ironclad Champions, Tacticus Firestorm Force.
##
## Contract: .llm/codex_11e_wahapedia/PLAN_SPACE_MARINES.md (the dispatcher
## contract between WP-M3a and WP-M3b) + IMPLEMENTATION.md. Rulings:
## RULINGS.md § WP-M3b.
##
## This is ONE group script for M3a's `custom:sm11e` dispatcher
## (SMCodex11e.gd), which loads it when this file exists. It exposes exactly
## the group-script static API SWCodex11e.gd calls on SWCodexCombat /
## SWCodexMovement / SWCodexCommand:
##   const IDS: Array, const IMPLEMENTED: Dictionary,
##   eligible_targets(strat, player, window_id, ctx) -> Array
##   validate(strat, player, target_unit_id, ctx) -> {ok, reason}
##   apply(strat, target_unit_id, ctx) -> Array | {diffs, followup}
##   clear(strat, unit_id) -> void
##   ai_kind(strat) -> String, ai_score(strat, player, target_unit_id, window_id, ctx) -> float
##   variant_cp_cost(strat, variant_id) -> int (-1 = base), variant_label(strat, variant_id) -> String
##   allows_battle_shocked_target(strat, ctx) -> bool
## plus handled_ids() (the csv_ids handled here).
## It delegates by csv_id to SMCodexBCombat.gd (attack modifiers) and
## SMCodexBAction.gd (moves, dice, battle-shock, objectives, OC).
##
## ENGINE HOOKS (bottom of this file) are called directly by one-line hooks in
## the engine files, commented "Codex: Space Marines (11e) WP-M3b
## (SMCodexB.gd)" — they do not go through the dispatcher.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GroupCombat = preload("res://scripts/codex/space_marines/SMCodexBCombat.gd")
const GroupAction = preload("res://scripts/codex/space_marines/SMCodexBAction.gd")

const MARKER_EFFECT := "custom:sm11e"

## Every csv_id handled here (SMCodexBCombat.IDS + SMCodexBAction.IDS —
## pinned equal by tests/test_sm11e_stratagems_b.gd).
const IDS: Array = [
	# Terminator Storm Force
	"tactical-dreadnought-fortitude-terminator-storm-force",
	"merciless-veterans-terminator-storm-force",
	"gunship-extraction-terminator-storm-force",
	# Assault Brethren
	"armour-of-contempt-assault-brethren",
	"duty-in-death-assault-brethren",
	"gene-wrought-might-assault-brethren",
	# Gravis Linebreaker Force
	"armoured-impact-gravis-linebreaker-force",
	"annihilating-force-gravis-linebreaker-force",
	"purgation-push-gravis-linebreaker-force",
	# Devastator Brethren
	"armour-of-contempt-devastator-brethren",
	"hail-of-vengeance-devastator-brethren",
	"storm-of-fire-devastator-brethren",
	# Gravis Siege Force
	"suppression-volleys-gravis-siege-force",
	"stand-unyielding-gravis-siege-force",
	"annihilating-force-gravis-siege-force",
	# Tactical Brethren
	"armour-of-contempt-tactical-brethren",
	"domination-fire-tactical-brethren",
	"masterful-tactics-tactical-brethren",
	# Ironclad Champions
	"adamantine-terror-ironclad-champions",
	"upstoppable-advance-ironclad-champions",
	"mercy-is-weakness-ironclad-champions",
	# Tacticus Firestorm Force
	"point-blank-brutality-tacticus-firestorm-force",
	"for-the-emperor-tacticus-firestorm-force",
	"relentless-assault-tacticus-firestorm-force",
]

const IMPLEMENTED: Dictionary = {
	"tactical-dreadnought-fortitude-terminator-storm-force": true,
	"merciless-veterans-terminator-storm-force": true,
	"gunship-extraction-terminator-storm-force": true,
	"armour-of-contempt-assault-brethren": true,
	"duty-in-death-assault-brethren": true,
	"gene-wrought-might-assault-brethren": true,
	"armoured-impact-gravis-linebreaker-force": true,
	"annihilating-force-gravis-linebreaker-force": true,
	"purgation-push-gravis-linebreaker-force": true,
	"armour-of-contempt-devastator-brethren": true,
	"hail-of-vengeance-devastator-brethren": true,
	"storm-of-fire-devastator-brethren": true,
	"suppression-volleys-gravis-siege-force": true,
	"stand-unyielding-gravis-siege-force": true,
	"annihilating-force-gravis-siege-force": true,
	"armour-of-contempt-tactical-brethren": true,
	"domination-fire-tactical-brethren": true,
	"masterful-tactics-tactical-brethren": true,
	"adamantine-terror-ironclad-champions": true,
	"upstoppable-advance-ironclad-champions": true,
	"mercy-is-weakness-ironclad-champions": true,
	"point-blank-brutality-tacticus-firestorm-force": true,
	"for-the-emperor-tacticus-firestorm-force": true,
	"relentless-assault-tacticus-firestorm-force": true,
}


static func handled_ids() -> Array:
	return IDS.duplicate()


static func _group(strat: Dictionary):
	var csv := str(strat.get("csv_id", ""))
	if csv in GroupCombat.IDS:
		return GroupCombat
	if csv in GroupAction.IDS:
		return GroupAction
	return null


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# ===========================================================================
# Group-script API (called by the SMCodex11e dispatcher)
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var g = _group(strat)
	if g == null or not Common.is_sm_army(player):
		return []
	return g.eligible_targets(strat, player, window_id, ctx)


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = _group(strat)
	if g == null:
		return _no("%s is not handled by SMCodexB" % strat.get("name", "?"))
	if not Common.is_sm_army(player):
		return _no("%s: only a Space Marines army (Codex: Space Marines 11e) can use it" % strat.get("name", "?"))
	return g.validate(strat, player, target_unit_id, ctx)


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = _group(strat)
	if g == null:
		Common.log_error("SMCodexB: no handler for %s (%s) — effect NOT applied" % [strat.get("name", "?"), strat.get("csv_id", "?")])
		return []
	return g.apply(strat, target_unit_id, ctx)


static func clear(strat: Dictionary, unit_id: String) -> void:
	var g = _group(strat)
	if g != null:
		g.clear(strat, unit_id)


static func ai_kind(strat: Dictionary) -> String:
	var g = _group(strat)
	return str(g.ai_kind(strat)) if g != null else "utility"


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var g = _group(strat)
	return float(g.ai_score(strat, player, target_unit_id, window_id, ctx)) if g != null else 0.0


static func variant_cp_cost(strat: Dictionary, variant_id: String) -> int:
	var g = _group(strat)
	return int(g.variant_cp_cost(strat, variant_id)) if g != null else -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	var g = _group(strat)
	return str(g.variant_label(strat, variant_id)) if g != null else ""


static func allows_battle_shocked_target(strat: Dictionary, ctx: Dictionary) -> bool:
	var g = _group(strat)
	return bool(g.allows_battle_shocked_target(strat, ctx)) if g != null else false


# ===========================================================================
# ENGINE HOOKS — one-line hooks in RulesEngine / EffectPrimitives /
# MissionManager / TransportManager / CloseQuartersShooting / the phases.
# Every hook is a no-op unless one of these stratagems wrote its flag.
# ===========================================================================

## TACTICAL DREADNOUGHT FORTITUDE: attacks that target the unit have -1 D
## (EffectPrimitives.get_effect_minus_damage).
static func damage_minus(target_unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return 0
	return GroupCombat.damage_minus(target_unit)

## ARMOUR OF CONTEMPT: attacks that target the unit have -1 AP
## (EffectPrimitives.get_effect_worsen_ap).
static func ap_worsen(target_unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return 0
	return GroupCombat.ap_worsen(target_unit)

## An attacking unit has finished its attacks (Shooting post-shot hook, the
## fighter's activation end, a Fire Overwatch shot): TACTICAL DREADNOUGHT
## FORTITUDE / ARMOUR OF CONTEMPT used against it end.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	GroupCombat.on_unit_has_attacked(attacker_unit_id)

## Attack-batch modifiers (RulesEngine.ork11e_ab_mods aggregator): MERCILESS
## VETERANS, ANNIHILATING FORCE, STORM OF FIRE, GENE-WROUGHT MIGHT (+1 AP),
## MERCY IS WEAKNESS, RELENTLESS ASSAULT, POINT-BLANK BRUTALITY (ignores
## cover) and DOMINATION FIRE (suppressed attacker: -1 to hit).
static func merge_attack_mods(m: Dictionary, actor: Dictionary, target: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> void:
	if GameConstants.edition < 11 or actor.is_empty():
		return
	GroupCombat.merge_attack_mods(m, actor, target, weapon_profile, is_melee)
	GroupAction.merge_attack_mods(m, actor)

## POINT-BLANK BRUTALITY: the unit counts as having [CLOSE-QUARTERS] weapons
## (CloseQuartersShooting.eligible) and its non-[BLAST] ranged weapons have
## [CLOSE-QUARTERS] (CloseQuartersShooting.weapon_allowed / hit_consequences).
static func grants_close_quarters(unit: Dictionary) -> bool:
	return GameConstants.edition >= 11 and GroupCombat.grants_close_quarters(unit)

static func weapon_gets_close_quarters(weapon_profile: Dictionary, unit: Dictionary) -> bool:
	return GameConstants.edition >= 11 and GroupCombat.weapon_gets_close_quarters(weapon_profile, unit)

## DUTY IN DEATH Fight On Death (FightPhase._ork11e_fod_intercept).
static func is_fod_mode(mode: String) -> bool:
	return GroupCombat.is_fod_mode(mode)

static func fod_roll(unit_id: String, model_index: int) -> Dictionary:
	return GroupCombat.fod_roll(unit_id, model_index)

## FOR THE EMPEROR!: +1 OC for every model of the unit this turn (MissionManager.model_oc).
static func oc_bonus(unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return 0
	return GroupAction.oc_bonus(unit)

## PURGATION PUSH: the unit is not eligible to embark this turn (TransportManager.can_embark).
static func embark_blocked(unit: Dictionary) -> bool:
	return GameConstants.edition >= 11 and GroupAction.embark_blocked(unit)

## The opponent's Command phase window (CommandPhase, next to command_phase_main).
static func opponent_command_window_entries(active_player: int) -> Array:
	if GameConstants.edition < 11:
		return []
	return GroupAction.opponent_command_window_entries(active_player, func(p, w): return player_has_window_stratagem(p, w))

## True when `player` has one of these stratagems offered in `window_id`.
static func player_has_window_stratagem(player: int, window_id: String) -> bool:
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_faction_stratagems_for_player") or not Common.is_sm_army(player):
		return false
	for s in sm.get_faction_stratagems_for_player(player):
		if not str(s.get("csv_id", "")) in IDS:
			continue
		if window_id in s.get("timing", {}).get("windows", []):
			return true
	return false
