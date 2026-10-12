extends RefCounted

## OrkCodexFight — Codex: Orks (11e) stratagems of the FIGHT group.
##
## Contract: .llm/ork_codex_11e_design.md §3–§4 (and §6 "how to add a hook").
## The dispatcher OrkCodex11e.gd routes every csv_id in IDS here. A stratagem
## counts as mechanically implemented ONLY when its csv_id is in IMPLEMENTED —
## everything else stays "not yet mechanically implemented" (S panel) and is
## never offered in a window.
##
## Handler API (all static; called by the dispatcher only):
##   eligible_targets(strat, player, window_id, ctx) -> Array of target entries
##       ({unit_id, label, variants?, secondary?} — see Common.target_entry)
##   validate(strat, player, target_unit_id, ctx) -> {ok: bool, reason: String}
##   apply(strat, target_unit_id, ctx) -> Array of diffs OR {diffs, followup}
##   clear(strat, unit_id) -> void          (effect expiry; mutate flags in place)
##   ai_kind(strat) -> "offensive" | "defensive" | "utility"
##   ai_score(strat, player, target_unit_id, window_id, ctx) -> float
##   variant_cp_cost(strat, variant_id) -> int   (-1 = base cost)
##   allows_battle_shocked_target(strat, ctx) -> bool

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

## Every csv_id owned by this group (registry). Do not move ids between groups.
const IDS: Array = [
	"hit-em-harder-war-horde",
	"mow-em-down-war-horde",
	"unbridled-carnage-green-tide",
	"armed-to-da-teef-bully-boyz",
	"orks-is-never-beaten-war-horde",
	"too-arrogant-to-die-bully-boyz",
	"crazed-rampage-dread-mob",
	"keep-it-runnin-blitz-brigade",
	"instinctive-hunters-da-big-hunt",
]

## csv_ids whose handler is complete and validated.
const IMPLEMENTED: Dictionary = {
	"hit-em-harder-war-horde": true,
}

const AI_KIND: Dictionary = {
	"hit-em-harder-war-horde": "offensive",
}

# Flag names written by this group's handlers.
# HIT 'EM HARDER reuses the generic melee-only LETHAL HITS flag
# (EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE): RulesEngine reads it only in
# melee resolution (_resolve_melee_assignment_hits), which is exactly the
# rule's scope ("Your unit's melee attacks have [Lethal Hits]"). The marker
# flag records the source so clear() only undoes what this handler set.
const FLAG_LETHAL_HITS_MELEE := "effect_lethal_hits_melee"
const FLAG_HIT_EM_HARDER := "ork11e_hit_em_harder"


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_targets(player, window_id, ctx)
	return []


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_validate(player, target_unit_id, ctx)
	return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_apply(target_unit_id)
	Common.log_error("OrkCodexFight: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			var group = Common.attached_group_ids(unit_id)
			Common.erase_flags(group, [FLAG_LETHAL_HITS_MELEE, FLAG_HIT_EM_HARDER])
			Common.log_info("OrkCodexFight: HIT 'EM HARDER expired — cleared melee [LETHAL HITS] on %s" % str(group))


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


## CP cost of a variant offered in a target entry's `variants` (e.g. HULKING
## BRUTES' +1 CP upgrade). -1 = unknown variant (the base cp_cost applies).
static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


## True when the stratagem may target a battle-shocked unit (BREAKIN' HEADS:
## "You can target that unit with this stratagem even though it is
## battle-shocked"). Default false — the core 15.01 battle-shock lock applies.
static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _melee_offense_score(target_unit_id)
	return 0.0


# ---------------------------------------------------------------------------
# HIT 'EM HARDER (War Horde, 1 CP, either turn, Fight phase)
# WHEN: Fight phase, when a friendly ORKS unit is selected to fight.
# TARGET: That ORKS unit.
# EFFECT: Your unit's melee attacks have [Lethal Hits]. (until end of phase)
# ---------------------------------------------------------------------------

static func _hit_em_harder_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "unit_selected_to_fight":
		return []
	var uid = str(ctx.get("unit_id", ""))
	var check = _hit_em_harder_validate(player, uid, ctx)
	if not check.ok:
		return []
	return [Common.target_entry(uid)]


static func _hit_em_harder_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "HIT 'EM HARDER needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "HIT 'EM HARDER must target a unit from your army"}
	if not Common.has_keyword(u, "ORKS"):
		return {"ok": false, "reason": "HIT 'EM HARDER can only target an ORKS unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "HIT 'EM HARDER: that unit is not on the battlefield"}
	var selected = str(ctx.get("unit_id", ""))
	if selected != "" and selected != target_unit_id:
		return {"ok": false, "reason": "HIT 'EM HARDER must target the unit that was selected to fight"}
	return {"ok": true, "reason": ""}


static func _hit_em_harder_apply(target_unit_id: String) -> Array:
	var group = Common.attached_group_ids(target_unit_id)
	var diffs: Array = []
	diffs.append_array(Common.set_flag_diffs(group, FLAG_LETHAL_HITS_MELEE, true))
	diffs.append_array(Common.set_flag_diffs(group, FLAG_HIT_EM_HARDER, true))
	Common.log_info("OrkCodexFight: HIT 'EM HARDER — melee attacks of %s gain [LETHAL HITS] until the end of the phase" % str(group))
	return diffs


# ---------------------------------------------------------------------------
# AI scoring helpers
# ---------------------------------------------------------------------------

## Value of a melee buff on the unit about to fight: needs melee weapons and an
## enemy in Engagement Range; scales with model count and unit value.
static func _melee_offense_score(unit_id: String) -> float:
	var u = Common.unit(unit_id)
	if u.is_empty() or not Common.has_melee_weapons(unit_id):
		return 0.0
	if not Common.is_engaged(unit_id):
		return 0.0
	var alive := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			alive += 1
	var score := 1.0 + minf(float(alive) * 0.25, 2.5)
	if Common.points(u) >= 100:
		score += 0.5
	if Common.has_keyword(u, "CHARACTER"):
		score += 0.5
	return score
