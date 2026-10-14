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
##
## Windows served (hooks in phases/FightPhase.gd unless noted):
##   unit_selected_to_fight   — HIT 'EM HARDER, MOW 'EM DOWN, UNBRIDLED CARNAGE,
##                              ARMED TO DA TEEF (FightPhase._process_select_fighter)
##   unit_selected_to_shoot   — ARMED TO DA TEEF (ShootingPhase hook, Shooting group)
##   enemy_targets_unit_fight — ORKS IS NEVER BEATEN, TOO ARROGANT TO DIE,
##                              CRAZED RAMPAGE (FightPhase._process_confirm_and_resolve_attacks)
##   fight_phase_end          — KEEP IT RUNNIN' (embark follow-up), INSTINCTIVE
##                              HUNTERS (strategic_reserves follow-up)
##                              (FightPhase._run_end_of_fight_triggers)
##
## The three enemy_targets_unit_fight stratagems share ONE 11e mechanic
## (05.04.05 Fight On Death, "do not remove that model from the battlefield"):
## apply() only marks the unit (FLAG_FOD_MODE / FLAG_FOD_SOURCE); the Fight
## phase rolls the D6 for every model of a marked unit that is destroyed while
## the unit has not been selected to fight (FightPhase._ork11e_fod_intercept,
## modifier from fod_roll_modifier()), keeps a passing model on the battlefield
## (alive, 0 wounds, listed in FLAG_FOD_PENDING) and removes it when the unit
## has fought or at the end of the phase (FightPhase._ork11e_fod_remove).

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
	"mow-em-down-war-horde": true,
	"unbridled-carnage-green-tide": true,
	"armed-to-da-teef-bully-boyz": true,
	"orks-is-never-beaten-war-horde": true,
	"too-arrogant-to-die-bully-boyz": true,
	"crazed-rampage-dread-mob": true,
	"keep-it-runnin-blitz-brigade": true,
	"instinctive-hunters-da-big-hunt": true,
}

const AI_KIND: Dictionary = {
	"hit-em-harder-war-horde": "offensive",
	"mow-em-down-war-horde": "offensive",
	"unbridled-carnage-green-tide": "offensive",
	"armed-to-da-teef-bully-boyz": "offensive",
	"orks-is-never-beaten-war-horde": "defensive",
	"too-arrogant-to-die-bully-boyz": "defensive",
	"crazed-rampage-dread-mob": "defensive",
	"keep-it-runnin-blitz-brigade": "utility",
	"instinctive-hunters-da-big-hunt": "utility",
}

# Flag names written by this group's handlers.
# HIT 'EM HARDER reuses the generic melee-only LETHAL HITS flag
# (EffectPrimitivesData.FLAG_LETHAL_HITS_MELEE): RulesEngine reads it only in
# melee resolution (_resolve_melee_assignment_hits), which is exactly the
# rule's scope ("Your unit's melee attacks have [Lethal Hits]"). The marker
# flag records the source so clear() only undoes what this handler set.
const FLAG_LETHAL_HITS_MELEE := "effect_lethal_hits_melee"
const FLAG_HIT_EM_HARDER := "ork11e_hit_em_harder"
# MOW 'EM DOWN: read in RulesEngine._resolve_melee_assignment_hits ([CLEAVE]
# block, melee only) — [CLEAVE 1], or +1 to an existing [CLEAVE X].
const FLAG_MOW_EM_DOWN := "ork11e_mow_em_down"
# UNBRIDLED CARNAGE: +N A to melee weapons, read only by the melee resolver
# (the generic effect_plus_attacks is also read by ranged resolvers and holds
# one shared value, so a dedicated melee-scoped flag is used).
const FLAG_PLUS_ATTACKS_MELEE := "ork11e_plus_attacks_melee"
const FLAG_UNBRIDLED_CARNAGE := "ork11e_unbridled_carnage"
# ARMED TO DA TEEF reuses EffectPrimitives REROLL_HITS (effect_reroll_hits),
# read by the interactive and auto ranged resolvers, the melee resolver and
# the shooting previews — the stratagem lasts until the end of the phase it was
# used in (Shooting or Fight), so the generic consumer has exactly its scope.
# The marker holds the scope this handler wrote ("" = it did not overwrite a
# better existing re-roll) so clear() only removes its own grant.
const FLAG_REROLL_HITS := "effect_reroll_hits"
const FLAG_ARMED_TO_DA_TEEF := "ork11e_armed_to_da_teef"
# The weaker re-roll scope another source held when ARMED TO DA TEEF upgraded
# it — restored by clear() so that source is not cut short.
const FLAG_ARMED_TO_DA_TEEF_PREV := "ork11e_armed_to_da_teef_prev"
# Riled up = "re-roll hit rolls" (any of them). Plain use: every FAILED hit roll
# is re-rolled. This variant: the controller also re-rolls successful
# NON-critical hits to fish for critical hits — applied by the engine to the
# weapons whose critical hits matter ([LETHAL HITS] / [SUSTAINED HITS]);
# RulesEngine.REROLL_HITS_SCOPE_NON_CRIT.
const ATDT_VARIANT_NON_CRIT := "non_crit"
const REROLL_SCOPE_NON_CRIT := "non_crit"  # == RulesEngine.REROLL_HITS_SCOPE_NON_CRIT
# Re-roll scopes from weakest to strongest (never downgrade an existing grant).
const _REROLL_RANK := {"": 0, "ones": 1, "failed": 2, "all": 2, "non_crit": 3}
# Fight On Death (ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE / CRAZED RAMPAGE)
const FLAG_FOD_MODE := "ork11e_fod_mode"        # "riled_up" (+1 if riled up) | "deff_dread" (+3 if DEFF DREAD)
const FLAG_FOD_SOURCE := "ork11e_fod_source"    # stratagem name, for the logs
const FLAG_FOD_PENDING := "ork11e_fod_pending"  # Array[int] model indices kept on the battlefield (FightPhase)
const FOD_PASS := 4

const KIR_RANGE_INCHES := 6.0
const IH_EDGE_INCHES := 6.0


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_targets(player, window_id, ctx)
		"mow-em-down-war-horde", "unbridled-carnage-green-tide":
			if window_id != "unit_selected_to_fight":
				return []
			return _selected_unit_targets(strat, player, ctx)
		"armed-to-da-teef-bully-boyz":
			if window_id != "unit_selected_to_fight" and window_id != "unit_selected_to_shoot":
				return []
			return _armed_to_da_teef_targets(strat, player, window_id, ctx)
		"orks-is-never-beaten-war-horde", "too-arrogant-to-die-bully-boyz", "crazed-rampage-dread-mob":
			if window_id != "enemy_targets_unit_fight":
				return []
			return _targeted_unit_targets(strat, player, ctx)
		"keep-it-runnin-blitz-brigade":
			if window_id != "fight_phase_end":
				return []
			return _keep_it_runnin_targets(player)
		"instinctive-hunters-da-big-hunt":
			if window_id != "fight_phase_end":
				return []
			return _instinctive_hunters_targets(player, ctx)
	return []


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_validate(player, target_unit_id, ctx)
		"mow-em-down-war-horde":
			return _mow_em_down_validate(player, target_unit_id, ctx)
		"unbridled-carnage-green-tide":
			return _unbridled_carnage_validate(player, target_unit_id, ctx)
		"armed-to-da-teef-bully-boyz":
			return _armed_to_da_teef_validate(player, target_unit_id, ctx)
		"orks-is-never-beaten-war-horde", "too-arrogant-to-die-bully-boyz", "crazed-rampage-dread-mob":
			return _fod_validate(strat, player, target_unit_id, ctx)
		"keep-it-runnin-blitz-brigade":
			return _keep_it_runnin_validate(player, target_unit_id, ctx)
		"instinctive-hunters-da-big-hunt":
			return _instinctive_hunters_validate(player, target_unit_id, ctx)
	return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			return _hit_em_harder_apply(target_unit_id)
		"mow-em-down-war-horde":
			return _mow_em_down_apply(target_unit_id)
		"unbridled-carnage-green-tide":
			return _unbridled_carnage_apply(target_unit_id)
		"armed-to-da-teef-bully-boyz":
			return _armed_to_da_teef_apply(target_unit_id, ctx)
		"orks-is-never-beaten-war-horde", "too-arrogant-to-die-bully-boyz", "crazed-rampage-dread-mob":
			return _fod_apply(strat, target_unit_id)
		"keep-it-runnin-blitz-brigade":
			return _keep_it_runnin_apply(target_unit_id, ctx)
		"instinctive-hunters-da-big-hunt":
			return _instinctive_hunters_apply(target_unit_id)
	Common.log_error("OrkCodexFight: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	match str(strat.get("csv_id", "")):
		"hit-em-harder-war-horde":
			var group = Common.attached_group_ids(unit_id)
			Common.erase_flags(group, [FLAG_LETHAL_HITS_MELEE, FLAG_HIT_EM_HARDER])
			Common.log_info("OrkCodexFight: HIT 'EM HARDER expired — cleared melee [LETHAL HITS] on %s" % str(group))
		"mow-em-down-war-horde":
			var mow_group = Common.attached_group_ids(unit_id)
			Common.erase_flags(mow_group, [FLAG_MOW_EM_DOWN])
			Common.log_info("OrkCodexFight: MOW 'EM DOWN expired — cleared melee [CLEAVE] bonus on %s" % str(mow_group))
		"unbridled-carnage-green-tide":
			var uc_group = Common.attached_group_ids(unit_id)
			Common.erase_flags(uc_group, [FLAG_PLUS_ATTACKS_MELEE, FLAG_UNBRIDLED_CARNAGE])
			Common.log_info("OrkCodexFight: UNBRIDLED CARNAGE expired — cleared melee +1 A on %s" % str(uc_group))
		"armed-to-da-teef-bully-boyz":
			var atdt_group = Common.attached_group_ids(unit_id)
			var units = Common.state().get("units", {})
			for gid in atdt_group:
				var flags: Dictionary = units.get(str(gid), {}).get("flags", {})
				if not flags.has(FLAG_ARMED_TO_DA_TEEF):
					continue
				var written := str(flags.get(FLAG_ARMED_TO_DA_TEEF, ""))
				if written != "" and str(flags.get(FLAG_REROLL_HITS, "")) == written:
					# Hand back the weaker re-roll another source granted before
					# this one upgraded it (e.g. 'ones' that outlasts the phase).
					var prev := str(flags.get(FLAG_ARMED_TO_DA_TEEF_PREV, ""))
					if prev != "":
						flags[FLAG_REROLL_HITS] = prev
					else:
						flags.erase(FLAG_REROLL_HITS)
				flags.erase(FLAG_ARMED_TO_DA_TEEF)
				flags.erase(FLAG_ARMED_TO_DA_TEEF_PREV)
			Common.log_info("OrkCodexFight: ARMED TO DA TEEF expired — cleared hit re-rolls on %s" % str(atdt_group))
		"orks-is-never-beaten-war-horde", "too-arrogant-to-die-bully-boyz", "crazed-rampage-dread-mob":
			# The kept models themselves (FLAG_FOD_PENDING) are removed by the
			# Fight phase before it ends — only the effect marker expires here.
			var fod_group = Common.attached_group_ids(unit_id)
			Common.erase_flags(fod_group, [FLAG_FOD_MODE, FLAG_FOD_SOURCE])
			Common.log_info("OrkCodexFight: %s expired on %s" % [strat.get("name", "?"), str(fod_group)])
		"keep-it-runnin-blitz-brigade", "instinctive-hunters-da-big-hunt":
			pass  # instant effects (follow-ups) — nothing to undo


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
		"mow-em-down-war-horde":
			var mow_score := _melee_offense_score(target_unit_id)
			if mow_score > 0.0 and _engaged_with_unit_of_size(target_unit_id, 5):
				mow_score += 0.5  # [CLEAVE] adds dice per 5 models in the target
			return mow_score
		"unbridled-carnage-green-tide":
			return _melee_offense_score(target_unit_id)
		"armed-to-da-teef-bully-boyz":
			if window_id == "unit_selected_to_shoot":
				return _ranged_offense_score(target_unit_id)
			return _melee_offense_score(target_unit_id)
		"orks-is-never-beaten-war-horde", "too-arrogant-to-die-bully-boyz", "crazed-rampage-dread-mob":
			return _fod_defense_score(str(strat.get("csv_id", "")), target_unit_id, str(ctx.get("attacker_unit_id", "")))
		"keep-it-runnin-blitz-brigade", "instinctive-hunters-da-big-hunt":
			return _reposition_utility_score(target_unit_id, player)
	return 0.0


# ---------------------------------------------------------------------------
# Shared target / unit checks
# ---------------------------------------------------------------------------

## Target entry for the unit named in ctx.unit_id (the unit selected to
## fight / shoot) when it passes the stratagem's validate().
static func _selected_unit_targets(strat: Dictionary, player: int, ctx: Dictionary) -> Array:
	var uid = str(ctx.get("unit_id", ""))
	if uid == "":
		return []
	var check = validate(strat, player, uid, ctx)
	if not check.ok:
		return []
	return [Common.target_entry(uid)]


## Target entries for every friendly unit the enemy fighter targets
## (ctx.target_unit_ids, Attached units already folded to their bodyguard).
static func _targeted_unit_targets(strat: Dictionary, player: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for tid_raw in ctx.get("target_unit_ids", []):
		var tid := _head_id(str(tid_raw))
		if seen.has(tid):
			continue
		seen[tid] = true
		var check = validate(strat, player, tid, ctx)
		if not check.ok:
			continue
		# "if your unit has not been selected to fight this phase": once it
		# has been, the effect can never apply — do not offer it (a human
		# would spend 1 CP for nothing). validate() stays permissive (RAW the
		# stratagem may still be used).
		if _group_selected_to_fight_this_phase(tid):
			Common.log_info("OrkCodexFight: %s not offered on %s — it has already been selected to fight this phase" % [strat.get("name", "?"), tid])
			continue
		out.append(Common.target_entry(tid))
	return out


## The Attached unit has been selected to fight in the current Fight phase
## (FightPhase tracks selections; has_fought is the fallback outside it).
static func _group_selected_to_fight_this_phase(unit_id: String) -> bool:
	var pm = Common.autoload("PhaseManager")
	var phase = pm.get("current_phase_instance") if pm != null else null
	if phase != null and phase.has_method("_ork11e_group_selected_to_fight"):
		return bool(phase._ork11e_group_selected_to_fight(unit_id))
	return _group_has_flag(unit_id, "has_fought")


## The Attached unit's bodyguard id (the unit itself when not attached).
static func _head_id(unit_id: String) -> String:
	var re = Common.rules()
	if re and re.has_method("attached_unit_target_id"):
		return str(re.attached_unit_target_id(unit_id, Common.state()))
	return unit_id


## Common gates: the unit exists, is from `player`'s army and is on the battlefield.
static func _friendly_unit_check(name: String, player: int, target_unit_id: String) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "%s needs a target unit" % name}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "%s must target a unit from your army" % name}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "%s: that unit is not on the battlefield" % name}
	return {"ok": true, "reason": ""}


## The target must be the unit named by the window (ctx.unit_id), or a
## component of that unit's Attached unit.
static func _matches_selected_unit(target_unit_id: String, ctx: Dictionary) -> bool:
	var selected = str(ctx.get("unit_id", ""))
	if selected == "" or selected == target_unit_id:
		return true
	return target_unit_id in Common.attached_group_ids(selected)


## Keyword check over the whole Attached unit (19.03: one unit — a keyword on
## the bodyguard or on an attached CHARACTER counts for the unit).
static func _group_has_keyword(unit_id: String, keyword: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if Common.has_keyword(Common.unit(str(gid)), keyword):
			return true
	return false


static func _group_has_flag(unit_id: String, flag: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get(flag, false)):
			return true
	return false


## "Unengaged" for the whole Attached unit.
static func _group_is_engaged(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if Common.is_on_battlefield(Common.unit(str(gid))) and Common.is_engaged(str(gid)):
			return true
	return false


static func _group_riled_up(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if Common.is_riled_up(Common.unit(str(gid))):
			return true
	return false


static func _is_attached_character(unit_id: String) -> bool:
	var at = Common.unit(unit_id).get("attached_to", null)
	return at != null and str(at) != ""


# ---------------------------------------------------------------------------
# HIT 'EM HARDER (War Horde, 1 CP, either turn, Fight phase)
# WHEN: Fight phase, when a friendly ORKS unit is selected to fight.
# TARGET: That ORKS unit.
# EFFECT: Your unit’s melee attacks have [Lethal Hits]. (until end of phase)
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
# MOW 'EM DOWN (War Horde, 1 CP, either turn, Fight phase)
# WHEN: Fight phase, when a friendly ORKS VEHICLE unit (excluding WALKER units)
#       that made a charge move this turn is selected to fight.
# TARGET: That ORKS VEHICLE unit.
# EFFECT: Your unit’s melee attacks have: • [Cleave 1]. • Or: If that attack
#         already has [CLEAVE], +1 to the value of that [CLEAVE].
# ---------------------------------------------------------------------------

static func _mow_em_down_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var base = _friendly_unit_check("MOW 'EM DOWN", player, target_unit_id)
	if not base.ok:
		return base
	if not _group_has_keyword(target_unit_id, "ORKS") or not _group_has_keyword(target_unit_id, "VEHICLE"):
		return {"ok": false, "reason": "MOW 'EM DOWN can only target an ORKS VEHICLE unit"}
	if _group_has_keyword(target_unit_id, "WALKER"):
		return {"ok": false, "reason": "MOW 'EM DOWN cannot target a WALKER unit"}
	if not _group_has_flag(target_unit_id, "charged_this_turn"):
		return {"ok": false, "reason": "MOW 'EM DOWN: that unit has not made a charge move this turn"}
	if not _matches_selected_unit(target_unit_id, ctx):
		return {"ok": false, "reason": "MOW 'EM DOWN must target the unit that was selected to fight"}
	return {"ok": true, "reason": ""}


static func _mow_em_down_apply(target_unit_id: String) -> Array:
	var group = Common.attached_group_ids(target_unit_id)
	var diffs: Array = Common.set_flag_diffs(group, FLAG_MOW_EM_DOWN, true)
	Common.log_info("OrkCodexFight: MOW 'EM DOWN — melee attacks of %s gain [CLEAVE 1] (or +1 to an existing [CLEAVE]) until the end of the phase" % str(group))
	return diffs


# ---------------------------------------------------------------------------
# UNBRIDLED CARNAGE (Green Tide, 1 CP, either turn, Fight phase)
# WHEN: Fight phase, when a friendly BOYZ unit that made a charge move this
#       turn is selected to fight.
# TARGET: That BOYZ unit.
# EFFECT: Your unit’s melee attacks have +1 A.
# ---------------------------------------------------------------------------

static func _unbridled_carnage_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var base = _friendly_unit_check("UNBRIDLED CARNAGE", player, target_unit_id)
	if not base.ok:
		return base
	if not _group_has_keyword(target_unit_id, "BOYZ"):
		return {"ok": false, "reason": "UNBRIDLED CARNAGE can only target a BOYZ unit"}
	if not _group_has_flag(target_unit_id, "charged_this_turn"):
		return {"ok": false, "reason": "UNBRIDLED CARNAGE: that unit has not made a charge move this turn"}
	if not _matches_selected_unit(target_unit_id, ctx):
		return {"ok": false, "reason": "UNBRIDLED CARNAGE must target the unit that was selected to fight"}
	return {"ok": true, "reason": ""}


static func _unbridled_carnage_apply(target_unit_id: String) -> Array:
	var group = Common.attached_group_ids(target_unit_id)
	var diffs: Array = []
	diffs.append_array(Common.set_flag_diffs(group, FLAG_PLUS_ATTACKS_MELEE, 1))
	diffs.append_array(Common.set_flag_diffs(group, FLAG_UNBRIDLED_CARNAGE, true))
	Common.log_info("OrkCodexFight: UNBRIDLED CARNAGE — melee attacks of %s have +1 A until the end of the phase" % str(group))
	return diffs


# ---------------------------------------------------------------------------
# ARMED TO DA TEEF (Bully Boyz, 1 CP, Shooting or Fight phase)
# WHEN: Your Shooting phase or the Fight phase, when a friendly MEGANOBZ/NOBZ
#       unit is selected to attack.
# TARGET: That MEGANOBZ/NOBZ unit.
# EFFECT: Your unit’s attacks can: • Re-roll hit rolls of 1. • If your unit is
#         riled up, re-roll hit rolls.
# ---------------------------------------------------------------------------

static func _armed_to_da_teef_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var base = _friendly_unit_check("ARMED TO DA TEEF", player, target_unit_id)
	if not base.ok:
		return base
	if not _group_has_keyword(target_unit_id, "MEGANOBZ") and not _group_has_keyword(target_unit_id, "NOBZ"):
		return {"ok": false, "reason": "ARMED TO DA TEEF can only target a MEGANOBZ or NOBZ unit"}
	# "YOUR Shooting phase": the selected-to-shoot window is the active
	# player's; in the opponent's Shooting phase the stratagem is not usable.
	if str(ctx.get("window_id", "")) == "unit_selected_to_shoot" and player != Common.active_player():
		return {"ok": false, "reason": "ARMED TO DA TEEF can only be used in your own Shooting phase"}
	if not _matches_selected_unit(target_unit_id, ctx):
		return {"ok": false, "reason": "ARMED TO DA TEEF must target the unit that was selected to attack"}
	return {"ok": true, "reason": ""}


## Target entry for the selected MEGANOBZ/NOBZ unit. While it is riled up
## ("re-roll hit rolls" — any hit roll) and the attacks of this window
## (melee in the Fight phase, ranged when selected to shoot) include a weapon
## whose critical hits matter, a variant lets the player also re-roll
## successful non-critical hits to fish for critical hits; the plain Use
## re-rolls every failed hit roll.
static func _armed_to_da_teef_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var uid = str(ctx.get("unit_id", ""))
	if uid == "" or not validate(strat, player, uid, ctx).ok:
		return []
	var extra := {}
	if _group_riled_up(uid) and _group_has_crit_hit_payoff(uid, window_id == "unit_selected_to_fight"):
		extra["variants"] = [{"id": ATDT_VARIANT_NON_CRIT,
			"label": "Re-roll non-critical hits too (fish for 6s)",
			"cp_cost": int(strat.get("cp_cost", 1))}]
	return [Common.target_entry(uid, extra)]


## True when a weapon of the given kind (melee / ranged) in the Attached unit
## has [LETHAL HITS] or [SUSTAINED HITS], or the unit holds a granted
## Lethal / Sustained Hits effect for those attacks.
static func _group_has_crit_hit_payoff(unit_id: String, melee: bool) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		var u = Common.unit(str(gid))
		var flags: Dictionary = u.get("flags", {})
		if melee and (bool(flags.get("effect_lethal_hits_melee", false)) or bool(flags.get("effect_sustained_hits_melee", false))):
			return true
		if not melee and (bool(flags.get("effect_lethal_hits", false)) or bool(flags.get("effect_sustained_hits", false))):
			return true
		for w in u.get("meta", {}).get("weapons", []):
			var is_melee_w := str(w.get("type", "")).to_lower() == "melee"
			if is_melee_w != melee:
				continue
			var txt := (str(w.get("special_rules", "")) + " " + str(w.get("abilities", ""))).to_lower()
			if "lethal hits" in txt or "sustained hits" in txt:
				return true
	return false


static func _armed_to_da_teef_apply(target_unit_id: String, ctx: Dictionary = {}) -> Array:
	var group = Common.attached_group_ids(target_unit_id)
	var riled := _group_riled_up(target_unit_id)
	var scope := "ones"
	if riled:
		scope = REROLL_SCOPE_NON_CRIT if str(ctx.get("variant_id", "")) == ATDT_VARIANT_NON_CRIT else "all"
	var diffs: Array = []
	for gid in group:
		var existing := str(Common.unit(str(gid)).get("flags", {}).get(FLAG_REROLL_HITS, ""))
		var written := ""
		# Never downgrade a better re-roll the unit already has, and only claim
		# the grant (written != "") when this handler actually changed it — so
		# clear() never erases a re-roll another source gave.
		if existing != scope and int(_REROLL_RANK.get(scope, 0)) > int(_REROLL_RANK.get(existing, 0)):
			written = scope
			diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_REROLL_HITS], "value": scope})
			if existing != "":
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_ARMED_TO_DA_TEEF_PREV], "value": existing})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_ARMED_TO_DA_TEEF], "value": written})
	var what := "hit rolls of 1"
	if scope == "all":
		what = "every failed hit roll (riled up)"
	elif scope == REROLL_SCOPE_NON_CRIT:
		what = "every non-critical hit roll of its critical-hit weapons and every failed hit roll (riled up, fishing for 6s)"
	Common.log_info("OrkCodexFight: ARMED TO DA TEEF — %s re-roll %s until the end of the phase" % [str(group), what])
	return diffs


# ---------------------------------------------------------------------------
# ORKS IS NEVER BEATEN (War Horde) / TOO ARROGANT TO DIE (Bully Boyz) /
# CRAZED RAMPAGE (Dread Mob) — 1 CP, either turn, Fight phase
# WHEN: Fight phase, when an enemy unit targets a friendly ORKS unit (excluding
#       TITANIC units) / MEGANOBZ/NOBZ unit / ORKS WALKER unit (excluding TITANIC).
# TARGET: That unit.
# EFFECT: When a model in your unit is destroyed, if your unit has not been
#         selected to fight this phase, roll one D6, with +1 to that roll if your
#         unit is riled up (CRAZED RAMPAGE: +3 to the result if your unit has
#         DEFF DREAD): on a 4+, do not remove that model from the battlefield.
#         When your unit has fought, or at the end of the phase (whichever comes
#         first), that model is removed from the battlefield.
# ---------------------------------------------------------------------------

static func _fod_validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var sname := str(strat.get("name", "?"))
	var base = _friendly_unit_check(sname, player, target_unit_id)
	if not base.ok:
		return base
	match str(strat.get("csv_id", "")):
		"orks-is-never-beaten-war-horde":
			if not _group_has_keyword(target_unit_id, "ORKS"):
				return {"ok": false, "reason": "%s can only target an ORKS unit" % sname}
			if _group_has_keyword(target_unit_id, "TITANIC"):
				return {"ok": false, "reason": "%s cannot target a TITANIC unit" % sname}
		"too-arrogant-to-die-bully-boyz":
			if not _group_has_keyword(target_unit_id, "MEGANOBZ") and not _group_has_keyword(target_unit_id, "NOBZ"):
				return {"ok": false, "reason": "%s can only target a MEGANOBZ or NOBZ unit" % sname}
		"crazed-rampage-dread-mob":
			if not _group_has_keyword(target_unit_id, "ORKS") or not _group_has_keyword(target_unit_id, "WALKER"):
				return {"ok": false, "reason": "%s can only target an ORKS WALKER unit" % sname}
			if _group_has_keyword(target_unit_id, "TITANIC"):
				return {"ok": false, "reason": "%s cannot target a TITANIC unit" % sname}
	# The unit must be one the enemy fighter is targeting.
	var targeted = ctx.get("target_unit_ids", [])
	if typeof(targeted) == TYPE_ARRAY and not targeted.is_empty():
		var hit := false
		for tid in targeted:
			if _head_id(str(tid)) == _head_id(target_unit_id):
				hit = true
				break
		if not hit:
			return {"ok": false, "reason": "%s must target a unit that the enemy unit is attacking" % sname}
	return {"ok": true, "reason": ""}


static func _fod_apply(strat: Dictionary, target_unit_id: String) -> Array:
	var group = Common.attached_group_ids(target_unit_id)
	var mode := "deff_dread" if str(strat.get("csv_id", "")) == "crazed-rampage-dread-mob" else "riled_up"
	var sname := str(strat.get("name", "?"))
	var diffs: Array = []
	diffs.append_array(Common.set_flag_diffs(group, FLAG_FOD_MODE, mode))
	diffs.append_array(Common.set_flag_diffs(group, FLAG_FOD_SOURCE, sname))
	Common.log_info("OrkCodexFight: %s — models of %s destroyed before the unit is selected to fight roll a D6 (%s): 4+ = not removed until it has fought / the end of the phase" % [
		sname, str(group), "+3 if DEFF DREAD" if mode == "deff_dread" else "+1 if riled up"])
	return diffs


## Modifier to the Fight On Death D6 for a model of `unit_id` (FightPhase).
## Returns {mod: int, note: String}. ORKS IS NEVER BEATEN / TOO ARROGANT TO
## DIE: +1 if the unit is riled up. CRAZED RAMPAGE: +3 if the unit has DEFF
## DREAD (no riled-up bonus in its text).
static func fod_roll_modifier(unit_id: String) -> Dictionary:
	var mode := str(Common.unit(unit_id).get("flags", {}).get(FLAG_FOD_MODE, ""))
	if mode == "deff_dread":
		if _group_has_keyword(unit_id, "DEFF DREAD"):
			return {"mod": 3, "note": "+3 DEFF DREAD"}
		return {"mod": 0, "note": "no DEFF DREAD"}
	if _group_riled_up(unit_id):
		return {"mod": 1, "note": "+1 riled up"}
	return {"mod": 0, "note": "not riled up"}


# ---------------------------------------------------------------------------
# KEEP IT RUNNIN' (Blitz Brigade, 1 CP, either turn, Fight phase)
# WHEN: End of the Fight phase.
# TARGET: One friendly unengaged ORKS INFANTRY unit that was eligible to fight
#         this phase and is wholly within 6" of a friendly TRANSPORT unit that
#         INFANTRY unit is able to embark within.
# EFFECT: Your INFANTRY unit embarks within that TRANSPORT unit.
# Ruling: "able to embark within" = the 18.02 conditions other than the 3"
# distance (capacity, datasheet keywords, not set up this turn —
# TransportManager.can_embark); the stratagem's "wholly within 6"" replaces the
# 3" distance condition (otherwise the 6" would be meaningless).
# ---------------------------------------------------------------------------

static func _keep_it_runnin_targets(player: int) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var unit_id := str(uid)
		if int(Common.unit(unit_id).get("owner", 0)) != player:
			continue
		if _is_attached_character(unit_id):
			continue  # boards with its bodyguard's entry
		var check = _keep_it_runnin_unit_check(player, unit_id)
		if not check.ok:
			continue
		var transports: Array = check.transports
		var extra := {}
		if transports.size() == 1:
			extra["label"] = "%s → %s" % [Common.unit_name(unit_id), Common.unit_name(str(transports[0]))]
		else:
			var options: Array = []
			for tid in transports:
				options.append({"id": str(tid), "label": Common.unit_name(str(tid))})
			extra["secondary"] = {"kind": "unit", "prompt": "Embark %s within which TRANSPORT?" % Common.unit_name(unit_id), "options": options}
		out.append(Common.target_entry(unit_id, extra))
	return out


## Every rule gate except the CP/turn ones. Returns {ok, reason, transports}
## (qualifying TRANSPORT ids, nearest first).
static func _keep_it_runnin_unit_check(player: int, unit_id: String) -> Dictionary:
	var base = _friendly_unit_check("KEEP IT RUNNIN'", player, unit_id)
	if not base.ok:
		return {"ok": false, "reason": base.reason, "transports": []}
	if _is_attached_character(unit_id):
		return {"ok": false, "reason": "KEEP IT RUNNIN': select the Attached unit's bodyguard", "transports": []}
	if not _group_has_keyword(unit_id, "ORKS") or not _group_has_keyword(unit_id, "INFANTRY"):
		return {"ok": false, "reason": "KEEP IT RUNNIN' can only target an ORKS INFANTRY unit", "transports": []}
	if _group_is_engaged(unit_id):
		return {"ok": false, "reason": "KEEP IT RUNNIN' can only target an unengaged unit", "transports": []}
	if not _group_has_flag(unit_id, "was_eligible_to_fight"):
		return {"ok": false, "reason": "KEEP IT RUNNIN': that unit was not eligible to fight this phase", "transports": []}
	var transports := _keep_it_runnin_transports(player, unit_id)
	if transports.is_empty():
		return {"ok": false, "reason": "KEEP IT RUNNIN': no friendly TRANSPORT it can embark within is wholly within 6\"", "transports": []}
	return {"ok": true, "reason": "", "transports": transports}


static func _keep_it_runnin_transports(player: int, unit_id: String) -> Array:
	var tm = Common.autoload("TransportManager")
	var found: Array = []
	for tid_raw in Common.state().get("units", {}):
		var tid := str(tid_raw)
		if tid == unit_id:
			continue
		var t = Common.unit(tid)
		if int(t.get("owner", 0)) != player or not t.has("transport_data"):
			continue
		if not Common.is_on_battlefield(t):
			continue
		if tm != null and tm.has_method("can_embark"):
			var ce: Dictionary = tm.can_embark(unit_id, tid)
			if not ce.get("valid", false):
				continue
		var far := _group_farthest_inches(unit_id, tid)
		if far <= KIR_RANGE_INCHES + 0.001:
			found.append({"id": tid, "d": Common.unit_distance_inches(unit_id, tid)})
	found.sort_custom(func(a, b): return float(a.d) < float(b.d))
	return found.map(func(e): return e.id)


## "Wholly within": the largest distance from any point of any alive model's
## base in the Attached unit to the nearest model of `other_id` (01.04.01).
## A base point is at most (edge-to-edge distance + base diameter) away.
static func _group_farthest_inches(unit_id: String, other_id: String) -> float:
	var meas = Common.autoload("Measurement")
	var other = Common.unit(other_id)
	var worst := 0.0
	var any := false
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			any = true
			var best := INF
			for om in other.get("models", []):
				if not om.get("alive", true) or om.get("position", null) == null:
					continue
				var d := INF
				if meas and meas.has_method("model_to_model_distance_inches"):
					d = float(meas.model_to_model_distance_inches(m, om))
				else:
					d = Common._pos(m).distance_to(Common._pos(om)) / Common.PX_PER_INCH
				best = minf(best, d)
			var extent_in := 2.0 * _base_extent_inches(m)
			worst = maxf(worst, best + extent_in)
	return worst if any else INF


static func _base_extent_inches(model: Dictionary) -> float:
	var meas = Common.autoload("Measurement")
	if meas and meas.has_method("base_extent_px"):
		return float(meas.base_extent_px(model)) / Common.PX_PER_INCH
	return float(model.get("base_mm", 32)) / 25.4 / 2.0


static func _keep_it_runnin_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var check = _keep_it_runnin_unit_check(player, target_unit_id)
	if not check.ok:
		return {"ok": false, "reason": check.reason}
	var chosen := str(ctx.get("secondary_id", ctx.get("transport_id", "")))
	if chosen != "" and not chosen in check.transports:
		return {"ok": false, "reason": "KEEP IT RUNNIN': %s cannot embark within %s" % [Common.unit_name(target_unit_id), Common.unit_name(chosen)]}
	return {"ok": true, "reason": ""}


static func _keep_it_runnin_apply(target_unit_id: String, ctx: Dictionary) -> Variant:
	var player := int(Common.unit(target_unit_id).get("owner", 0))
	var transport := str(ctx.get("secondary_id", ctx.get("transport_id", "")))
	if transport == "":
		var transports := _keep_it_runnin_transports(player, target_unit_id)
		transport = str(transports[0]) if not transports.is_empty() else ""
	if transport == "":
		Common.log_error("OrkCodexFight: KEEP IT RUNNIN' — no TRANSPORT for %s at apply time" % target_unit_id)
		return []
	Common.log_info("OrkCodexFight: KEEP IT RUNNIN' — %s embarks within %s (embark follow-up)" % [target_unit_id, transport])
	return {"diffs": [], "followup": {"type": "embark", "unit_id": target_unit_id, "transport_id": transport}}


# ---------------------------------------------------------------------------
# INSTINCTIVE HUNTERS (Da Big Hunt, 1 CP, opponent's turn, Fight phase)
# WHEN: End of your opponent’s Fight phase.
# TARGET: One friendly unengaged BEAST SNAGGA unit within 6" of a battlefield edge.
# EFFECT: Place your unit in strategic reserves.
# (Turn gate "opponent" comes from the CSV turn column via can_use_stratagem.)
# ---------------------------------------------------------------------------

static func _instinctive_hunters_targets(player: int, ctx: Dictionary) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var unit_id := str(uid)
		if int(Common.unit(unit_id).get("owner", 0)) != player or _is_attached_character(unit_id):
			continue
		if _instinctive_hunters_validate(player, unit_id, ctx).ok:
			out.append(Common.target_entry(unit_id))
	return out


static func _instinctive_hunters_validate(player: int, target_unit_id: String, _ctx: Dictionary) -> Dictionary:
	var base = _friendly_unit_check("INSTINCTIVE HUNTERS", player, target_unit_id)
	if not base.ok:
		return base
	if not _group_has_keyword(target_unit_id, "BEAST SNAGGA"):
		return {"ok": false, "reason": "INSTINCTIVE HUNTERS can only target a BEAST SNAGGA unit"}
	if _group_is_engaged(target_unit_id):
		return {"ok": false, "reason": "INSTINCTIVE HUNTERS can only target an unengaged unit"}
	if _group_edge_distance_inches(target_unit_id) > IH_EDGE_INCHES + 0.001:
		return {"ok": false, "reason": "INSTINCTIVE HUNTERS: that unit is not within 6\" of a battlefield edge"}
	return {"ok": true, "reason": ""}


## Closest distance (inches) from any alive model's base in the Attached unit
## to any battlefield edge ("within": any part of one model's base, 01.04.01).
static func _group_edge_distance_inches(unit_id: String) -> float:
	var size = Common.state().get("board", {}).get("size", {})
	var w_in := float(size.get("width", 44.0))
	var h_in := float(size.get("height", 60.0))
	var best := INF
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			var p := Common._pos(m) / Common.PX_PER_INCH
			var r := _base_extent_inches(m)
			var d := minf(minf(p.x - r, w_in - p.x - r), minf(p.y - r, h_in - p.y - r))
			best = minf(best, maxf(d, 0.0))
	return best


static func _instinctive_hunters_apply(target_unit_id: String) -> Variant:
	Common.log_info("OrkCodexFight: INSTINCTIVE HUNTERS — %s is placed in strategic reserves (strategic_reserves follow-up)" % target_unit_id)
	return {"diffs": [], "followup": {"type": "strategic_reserves", "unit_id": target_unit_id}}


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


## Value of a hit re-roll on a unit about to shoot: needs ranged weapons.
static func _ranged_offense_score(unit_id: String) -> float:
	var u = Common.unit(unit_id)
	if u.is_empty():
		return 0.0
	var has_ranged := false
	for w in u.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "ranged":
			has_ranged = true
			break
	if not has_ranged:
		return 0.0
	var alive := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			alive += 1
	var score := 1.0 + minf(float(alive) * 0.25, 2.5)
	if _group_riled_up(unit_id):
		score += 0.5  # full hit re-rolls
	return score


static func _engaged_with_unit_of_size(unit_id: String, min_models: int) -> bool:
	var u = Common.unit(unit_id)
	var owner := int(u.get("owner", 0))
	var units = Common.state().get("units", {})
	for oid in units:
		var o = units[oid]
		if int(o.get("owner", 0)) == owner or not Common.is_on_battlefield(o):
			continue
		var alive := 0
		for m in o.get("models", []):
			if m.get("alive", true):
				alive += 1
		if alive >= min_models and Common.within_inches(unit_id, str(oid), 2.0):
			return true
	return false


## Defensive value of the Fight On Death stratagems: worth it when the unit can
## still swing back (melee weapons, not yet fought) and the attacker is likely
## to destroy a real share of it. Crude expected-damage estimate.
static func _fod_defense_score(csv_id: String, unit_id: String, attacker_id: String) -> float:
	var u = Common.unit(unit_id)
	if u.is_empty() or not Common.has_melee_weapons(unit_id):
		return 0.0
	if _group_has_flag(unit_id, "has_fought"):
		return 0.0
	# The defender: alive models, their wounds and their own swing.
	var alive := 0
	var wounds_total := 0.0
	var swing_total := 0.0
	for gid in Common.attached_group_ids(unit_id):
		var du = Common.unit(str(gid))
		var du_best_a := 1.0
		for w in du.get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() == "melee":
				du_best_a = maxf(du_best_a, _num(w.get("attacks", 1), 1.0))
		for m in du.get("models", []):
			if m.get("alive", true) and int(m.get("current_wounds", m.get("wounds", 1))) > 0:
				alive += 1
				wounds_total += float(m.get("wounds", 1))
				swing_total += du_best_a
	if alive <= 0:
		return 0.0
	# The attacker's expected damage (crude: 60% hit, 55% wound, 60% unsaved).
	var expected := 0.0
	for gid in Common.attached_group_ids(attacker_id):
		var a = Common.unit(str(gid))
		var best_a := 0.0
		var best_d := 1.0
		for w in a.get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() != "melee":
				continue
			best_a = maxf(best_a, _num(w.get("attacks", 2), 2.0))
			best_d = maxf(best_d, _num(w.get("damage", 1), 1.0))
		for m in a.get("models", []):
			if m.get("alive", true):
				expected += best_a * 0.6 * 0.55 * 0.6 * best_d
	# Models likely destroyed x chance each is kept x what a kept model swings
	# back with (half its melee Attacks as a hit/wound proxy).
	var avg_w := wounds_total / float(alive)
	var destroyed := minf(float(alive), expected / maxf(1.0, avg_w))
	var mod := fod_roll_modifier_for_mode(csv_id, unit_id)
	var pass_chance := clampf(float(7 - (FOD_PASS - mod)) / 6.0, 0.0, 1.0)
	var swing := maxf(0.5, (swing_total / float(alive)) * 0.5)
	return destroyed * pass_chance * swing


## fod_roll_modifier() before the flag is set (AI scoring at offer time).
static func fod_roll_modifier_for_mode(csv_id: String, unit_id: String) -> int:
	if csv_id == "crazed-rampage-dread-mob":
		return 3 if _group_has_keyword(unit_id, "DEFF DREAD") else 0
	return 1 if _group_riled_up(unit_id) else 0


static func _num(v, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	var s := str(v).strip_edges()
	if s.is_valid_float():
		return float(s)
	if s.to_upper().begins_with("D6"):
		return 3.5
	if s.to_upper().begins_with("D3"):
		return 2.0
	return fallback


## KEEP IT RUNNIN' / INSTINCTIVE HUNTERS: pull an exposed unit off the board
## when enemies are close; otherwise keep the CP.
static func _reposition_utility_score(unit_id: String, player: int) -> float:
	# Never pull a unit off an objective its player controls or contests:
	# embarking / going into reserves gives up that level of control.
	if _unit_holds_objective(unit_id, player):
		return 0.0
	var units = Common.state().get("units", {})
	for oid in units:
		var o = units[oid]
		if int(o.get("owner", 0)) == player or not Common.is_on_battlefield(o):
			continue
		if Common.within_inches(unit_id, str(oid), 12.0):
			return 2.5
	return 0.5


## True when a model of the (Attached) unit is within range of an objective
## that `player` controls or that is contested (MissionManager's last
## level-of-control determination).
static func _unit_holds_objective(unit_id: String, player: int) -> bool:
	var mm = Common.autoload("MissionManager")
	if mm == null or not mm.has_method("model_in_objective_range"):
		return false
	for obj in Common.state().get("board", {}).get("objectives", []):
		var oid := str(obj.get("id", ""))
		if oid == "":
			continue
		var controller := int(mm.objective_control_state.get(oid, 0))
		var contested: bool = mm.has_method("is_objective_contested") and bool(mm.is_objective_contested(oid))
		if controller != player and not contested:
			continue
		for gid in Common.attached_group_ids(unit_id):
			for m in Common.unit(str(gid)).get("models", []):
				if not m.get("alive", true) or m.get("position", null) == null:
					continue
				if mm.model_in_objective_range(m, obj):
					return true
	return false
