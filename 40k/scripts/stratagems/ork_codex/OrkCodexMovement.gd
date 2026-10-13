extends RefCounted

## OrkCodexMovement — Codex: Orks (11e) stratagems of the MOVEMENT group:
## Movement-phase stratagems (own-turn move windows, opponent-Movement reactive moves and the two panel stratagems).
##
## Contract: .llm/ork_codex_11e_design.md §3–§4 (and §6 "how to add a hook").
## The dispatcher OrkCodex11e.gd routes every csv_id in IDS here. A stratagem
## counts as mechanically implemented ONLY when its csv_id is in IMPLEMENTED —
## everything else stays "not yet mechanically implemented" (S panel) and is
## never offered in a window. See OrkCodexFight.gd (HIT 'EM HARDER) for a
## complete worked handler.
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
## Hook points (MovementPhase.gd, "Codex: Orks (11e)" blocks):
##   unit_selected_to_move      BEGIN_NORMAL_MOVE / BEGIN_ADVANCE / BEGIN_FALL_BACK,
##                              before any roll or cap (ctx unit_id, move_type)
##   enemy_selected_to_fall_back BEGIN_FALL_BACK, queued after the active
##                              player's window (ctx enemy_unit_id)
##   unit_ended_normal_move     CONFIRM_UNIT_MOVE of a normal move (ctx unit_id)
##   enemy_ended_move           CONFIRM_UNIT_MOVE of the active player's unit, after
##                              the overwatch / Krump and Run / Scatter! prompts
##                              (ctx enemy_unit_id, move_type)
##   movement_phase_start/end   phase entry / END_MOVEMENT (both players, active first;
##                              end ctx engaged_at_phase_start)
##   unit_declares_charge       ChargePhase (other group) — STOMPING JUGGERNAUT only
## Follow-ups executed by MovementPhase._execute_window_followup:
##   reactive_normal_move {unit_id, max_inches, roll, source, away_from_unit_id?, goal?}
##   assault_disembark   {transport_id, source}
##
## Rulings (also in the group report):
##   'ERE WE GO is offered only for advance moves (it only modifies advance rolls).
##   MIND MOSTLY ON THE MISSION is offered only for advance / fall-back moves (its WHEN).
##   DUBIOUS RESTRAINT lists only objectives the unit controls that are not already
##     secured by its army (re-securing has no effect).
##   DELICIOUS EATING SQUIGS selects EVERY eligible ORKS INFANTRY unit within 3"
##     automatically (healing has no downside); it needs at least one such unit.
##   READIED BRAWLERS needs at least one unit embarked in the WAGON that is eligible
##     to disembark; the assault disembark is made right away (one unit at a time).
##   SCARPER! / WHIRLIGIG EVASION: the 6" alternative is used whenever its condition
##     holds (6" >= any D6); otherwise one D6 is rolled for the maximum distance.
##   WHERE D'YA FINK YOU'RE GOING?: the -1 applies to the three additional hazard
##     rolls only ("those hazard rolls"); every enemy BEAST SNAGGA unit the falling
##     back MONSTER/VEHICLE is engaged with adds three rolls.

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

## Every csv_id owned by this group (registry). Do not move ids between groups.
const IDS: Array = [
	"fungus-fuel-injection-war-horde",
	"ere-we-go-green-tide",
	"stomping-juggernaut-dread-mob",
	"mind-mostly-on-the-mission-taktikal-brigade",
	"dubious-restraint-taktikal-brigade",
	"readied-brawlers-blitz-brigade",
	"scarper-runt-swarm",
	"whirligig-evasion-flyboyz",
	"where-dya-fink-youre-going-da-big-hunt",
	"while-their-backs-are-turned-taktikal-brigade",
	"dread-power-dread-mob",
	"delicious-eating-squigs-kult-of-speed",
]

## csv_ids whose handler is complete and validated.
const IMPLEMENTED: Dictionary = {
	"fungus-fuel-injection-war-horde": true,
	"ere-we-go-green-tide": true,
	"stomping-juggernaut-dread-mob": true,
	"mind-mostly-on-the-mission-taktikal-brigade": true,
	"dubious-restraint-taktikal-brigade": true,
	"readied-brawlers-blitz-brigade": true,
	"scarper-runt-swarm": true,
	"whirligig-evasion-flyboyz": true,
	"where-dya-fink-youre-going-da-big-hunt": true,
	"while-their-backs-are-turned-taktikal-brigade": true,
	"dread-power-dread-mob": true,
	"delicious-eating-squigs-kult-of-speed": true,
}

const AI_KIND: Dictionary = {
	"fungus-fuel-injection-war-horde": "utility",
	"ere-we-go-green-tide": "utility",
	"stomping-juggernaut-dread-mob": "utility",
	"mind-mostly-on-the-mission-taktikal-brigade": "utility",
	"dubious-restraint-taktikal-brigade": "utility",
	"readied-brawlers-blitz-brigade": "utility",
	"scarper-runt-swarm": "defensive",
	"whirligig-evasion-flyboyz": "defensive",
	"where-dya-fink-youre-going-da-big-hunt": "offensive",
	"while-their-backs-are-turned-taktikal-brigade": "utility",
	"dread-power-dread-mob": "utility",
	"delicious-eating-squigs-kult-of-speed": "utility",
}

# Window ids used by this group.
const W_SELECTED_TO_MOVE := "unit_selected_to_move"
const W_DECLARES_CHARGE := "unit_declares_charge"
const W_ENDED_NORMAL_MOVE := "unit_ended_normal_move"
const W_ENEMY_ENDED_MOVE := "enemy_ended_move"
const W_ENEMY_FALL_BACK := "enemy_selected_to_fall_back"
const W_PHASE_START := "movement_phase_start"
const W_PHASE_END := "movement_phase_end"

# Flag names written by this group's handlers. None uses the effect_ prefix
# except where an existing EffectPrimitives consumer matches the rule exactly
# (DREAD POWER's riled-up grants, which mirror the Waaagh!/GRAB AND BASH set).
const FLAG_PLUS_MOVE := "ork11e_plus_move"            # FUNGUS-FUEL INJECTION: +N" M (MovementPhase.get_unit_movement)
const FLAG_ERE_WE_GO := "ork11e_ere_we_go"            # 'ERE WE GO: +N to advance rolls (MovementPhase._resolve_advance_roll)
const FLAG_MOBILE := "ork11e_mobile"                  # STOMPING JUGGERNAUT: unit has MOBILE (13.06 terrain checks)
const FLAG_MIND_ON_MISSION := "ork11e_mind_on_mission" # MIND MOSTLY ON THE MISSION (ActionsManager.can_start_action)
const FLAG_READIED_BRAWLERS := "ork11e_readied_brawlers" # on the WAGON: assault disembark mode (DisembarkMove.select_mode)
const FLAG_WHERE_DYA_FINK := "ork11e_where_dya_fink"  # on the BEAST SNAGGA unit (FallBackMove.select_mode / before_moving)
const FLAG_DUBIOUS_RESTRAINT := "ork11e_dubious_restraint" # marker: objective id secured this phase
const FLAG_RILED_UP := "ork11e_riled_up"              # Common.is_riled_up
const FLAG_DREAD_POWER := "ork11e_dread_power"        # marker: DREAD POWER owns the riled-up grants below
const FLAG_DREAD_POWER_ADV_SHOOT := "ork11e_dread_power_assault"  # marker: DREAD POWER set effect_advance_and_shoot
const DREAD_POWER_SOURCE := "Dread Power"

const KW_BOYZ_KOMMANDOS_STORMBOYZ: Array = ["BOYZ", "KOMMANDOS", "STORMBOYZ"]


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidate_units(csv, player, window_id, ctx):
		var check := _check(csv, player, str(uid), window_id, ctx)
		if not check.ok:
			continue
		var extra := {}
		if csv == "dubious-restraint-taktikal-brigade":
			var objs := controlled_objectives(str(uid), player)
			if objs.size() > 1:
				var opts: Array = []
				for oid in objs:
					opts.append({"id": oid, "label": objective_label(oid)})
				extra["secondary"] = {"kind": "objective",
					"prompt": "DUBIOUS RESTRAINT — select the objective to secure", "options": opts}
			elif objs.size() == 1:
				extra["label"] = "%s (secure %s)" % [Common.unit_name(str(uid)), objective_label(str(objs[0]))]
		out.append(Common.target_entry(str(uid), extra))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not csv in IDS:
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	var window_id := str(ctx.get("window_id", ""))
	if target_unit_id == "":
		# S panel probe (no target, no context): the two panel stratagems are
		# usable when at least one friendly unit could be targeted (design §6.3).
		if csv in ["dread-power-dread-mob", "delicious-eating-squigs-kult-of-speed"]:
			for uid in Common.state().get("units", {}):
				if _check(csv, player, str(uid), window_id, ctx).ok:
					return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "%s: no eligible unit" % strat.get("name", "?")}
		return {"ok": false, "reason": "%s needs a target unit" % strat.get("name", "?")}
	return _check(csv, player, target_unit_id, window_id, ctx)


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var u := Common.unit(target_unit_id)
	var player := int(u.get("owner", 0))
	var group := Common.attached_group_ids(target_unit_id)
	match csv:
		"fungus-fuel-injection-war-horde":
			Common.log_info("OrkCodexMovement: FUNGUS-FUEL INJECTION — %s has +2\" M until the end of the phase" % str(group))
			_event_log(player, "FUNGUS-FUEL INJECTION: %s has +2\" M this phase" % Common.unit_name(target_unit_id))
			return Common.set_flag_diffs(group, FLAG_PLUS_MOVE, 2)
		"ere-we-go-green-tide":
			Common.log_info("OrkCodexMovement: 'ERE WE GO — %s has +2 to advance rolls until the end of the phase" % str(group))
			_event_log(player, "'ERE WE GO: %s has +2 to advance rolls this phase" % Common.unit_name(target_unit_id))
			return Common.set_flag_diffs(group, FLAG_ERE_WE_GO, 2)
		"stomping-juggernaut-dread-mob":
			Common.log_info("OrkCodexMovement: STOMPING JUGGERNAUT — %s has MOBILE until the end of the phase" % str(group))
			_event_log(player, "STOMPING JUGGERNAUT: %s has MOBILE (moves through dense terrain) this phase" % Common.unit_name(target_unit_id))
			return Common.set_flag_diffs(group, FLAG_MOBILE, true)
		"mind-mostly-on-the-mission-taktikal-brigade":
			Common.log_info("OrkCodexMovement: MIND MOSTLY ON THE MISSION — %s's %s move does not stop it starting an action" % [str(group), str(ctx.get("move_type", "?"))])
			_event_log(player, "MIND MOSTLY ON THE MISSION: %s's %s move does not prevent it from starting an action" % [
				Common.unit_name(target_unit_id), str(ctx.get("move_type", "")).replace("_", "-")])
			return Common.set_flag_diffs(group, FLAG_MIND_ON_MISSION, true)
		"dubious-restraint-taktikal-brigade":
			return _dubious_restraint_apply(target_unit_id, player, ctx)
		"readied-brawlers-blitz-brigade":
			Common.log_info("OrkCodexMovement: READIED BRAWLERS — units embarked in %s can make an assault disembark move" % target_unit_id)
			_event_log(player, "READIED BRAWLERS: units embarked within %s can make an assault disembark move" % Common.unit_name(target_unit_id))
			return {"diffs": Common.set_flag_diffs([target_unit_id], FLAG_READIED_BRAWLERS, true),
				"followup": {"type": "assault_disembark", "transport_id": target_unit_id, "source": "READIED BRAWLERS"}}
		"scarper-runt-swarm":
			return _reactive_move_apply("SCARPER!", target_unit_id, player, is_attached_unit(target_unit_id),
				"attached unit", ctx, "away")
		"whirligig-evasion-flyboyz":
			return _reactive_move_apply("WHIRLIGIG EVASION", target_unit_id, player, Common.is_riled_up(u),
				"riled up", ctx, "away")
		"where-dya-fink-youre-going-da-big-hunt":
			Common.log_info("OrkCodexMovement: WHERE D'YA FINK YOU'RE GOING? — enemies engaged with %s must Desperate Escape this phase" % str(group))
			_event_log(player, "WHERE D'YA FINK YOU'RE GOING?: enemy units engaged with %s must use the desperate escape mode" % Common.unit_name(target_unit_id))
			return Common.set_flag_diffs(group, FLAG_WHERE_DYA_FINK, true)
		"while-their-backs-are-turned-taktikal-brigade":
			var w_name := Common.unit_name(target_unit_id)
			Common.log_info("OrkCodexMovement: WHILE THEIR BACKS ARE TURNED — %s can make a normal move of up to 6\"" % target_unit_id)
			_event_log(player, "WHILE THEIR BACKS ARE TURNED: %s can make a normal move of up to 6\"" % w_name)
			return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": target_unit_id,
				"max_inches": 6.0, "roll": 0, "source": "WHILE THEIR BACKS ARE TURNED", "goal": "objective"}}
		"dread-power-dread-mob":
			return _dread_power_apply(target_unit_id, player)
		"delicious-eating-squigs-kult-of-speed":
			return _delicious_squigs_apply(target_unit_id, player)
	Common.log_error("OrkCodexMovement: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var group := Common.attached_group_ids(unit_id)
	match str(strat.get("csv_id", "")):
		"fungus-fuel-injection-war-horde":
			Common.erase_flags(group, [FLAG_PLUS_MOVE])
			Common.log_info("OrkCodexMovement: FUNGUS-FUEL INJECTION expired on %s" % str(group))
		"ere-we-go-green-tide":
			Common.erase_flags(group, [FLAG_ERE_WE_GO])
			Common.log_info("OrkCodexMovement: 'ERE WE GO expired on %s" % str(group))
		"stomping-juggernaut-dread-mob":
			Common.erase_flags(group, [FLAG_MOBILE])
			Common.log_info("OrkCodexMovement: STOMPING JUGGERNAUT (MOBILE) expired on %s" % str(group))
		"mind-mostly-on-the-mission-taktikal-brigade":
			Common.erase_flags(group, [FLAG_MIND_ON_MISSION])
			Common.log_info("OrkCodexMovement: MIND MOSTLY ON THE MISSION expired on %s" % str(group))
		"dubious-restraint-taktikal-brigade":
			# The secured objective itself persists (14.03) — only the marker goes.
			Common.erase_flags(group, [FLAG_DUBIOUS_RESTRAINT])
		"readied-brawlers-blitz-brigade":
			Common.erase_flags([unit_id], [FLAG_READIED_BRAWLERS])
		"where-dya-fink-youre-going-da-big-hunt":
			Common.erase_flags(group, [FLAG_WHERE_DYA_FINK])
			Common.log_info("OrkCodexMovement: WHERE D'YA FINK YOU'RE GOING? expired on %s" % str(group))
		"dread-power-dread-mob":
			_dread_power_clear(group)


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
	var csv := str(strat.get("csv_id", ""))
	var u := Common.unit(target_unit_id)
	if u.is_empty():
		return 0.0
	var cp := Common.player_cp(player)
	match csv:
		"fungus-fuel-injection-war-horde", "ere-we-go-green-tide":
			# The AI re-plans an Advance from the real move cap (AIPlayer
			# _execute_pending_advance_move), so the bonus is used there.
			if cp < 2:
				return 0.0
			if str(ctx.get("move_type", "")) == "advance":
				return 2.5
			# A Normal move is pre-planned from the datasheet M, but AIPlayer
			# re-plans it when the cap came out higher (FUNGUS-FUEL INJECTION).
			# Spend the CP only when the extra 2" is what matters (AI-08).
			if csv == "fungus-fuel-injection-war-horde" and str(ctx.get("move_type", "")) == "normal":
				return 2.5 if _ffi_normal_move_gain(target_unit_id, player) else 0.0
			return 0.0
		"stomping-juggernaut-dread-mob", "mind-mostly-on-the-mission-taktikal-brigade":
			# The AI movement planner does not path through dense terrain, and it
			# never starts actions — neither effect would be used.
			return 0.0
		"dubious-restraint-taktikal-brigade":
			if window_id != W_PHASE_END or cp < 2:
				return 0.0
			return 2.5 if not controlled_objectives(target_unit_id, player).is_empty() else 0.0
		"readied-brawlers-blitz-brigade":
			if cp < 2 or assault_disembark_candidates(target_unit_id).is_empty():
				return 0.0
			return 2.5 if _enemy_within(target_unit_id, player, 12.0) else 0.0
		"scarper-runt-swarm", "whirligig-evasion-flyboyz":
			# Evade the threat unless the unit is holding an objective — and only
			# when there is a threat: the enemy that ended its move could still
			# charge this unit this turn (AI-08: don't spend CP running from a
			# unit that advanced / fell back / is out of 2D6 range).
			if _unit_in_range_of_any_objective(target_unit_id):
				return 0.0
			return 2.0 if _charge_threat(str(ctx.get("enemy_unit_id", "")), target_unit_id) else 0.0
		"where-dya-fink-youre-going-da-big-hunt":
			return _where_dya_fink_score(str(ctx.get("enemy_unit_id", "")), target_unit_id)
		"while-their-backs-are-turned-taktikal-brigade":
			return 2.2 if _uncontrolled_objective_within(target_unit_id, player, 9.0) else 0.0
		"dread-power-dread-mob":
			if Common.is_riled_up(u) or cp < 2:
				return 0.0
			return 2.5
		"delicious-eating-squigs-kult-of-speed":
			var healable := 0
			for iid in delicious_squigs_targets(target_unit_id, player):
				healable += mini(3, _healable_wounds(str(iid)))
			return float(healable)
	return 0.0


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

## Candidate target units for a window (each is then checked by _check).
static func _candidate_units(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var uid := str(ctx.get("unit_id", ""))
	match csv:
		"fungus-fuel-injection-war-horde", "ere-we-go-green-tide", "mind-mostly-on-the-mission-taktikal-brigade":
			return [uid] if window_id == W_SELECTED_TO_MOVE and uid != "" else []
		"stomping-juggernaut-dread-mob":
			return [uid] if window_id in [W_SELECTED_TO_MOVE, W_DECLARES_CHARGE] and uid != "" else []
		"readied-brawlers-blitz-brigade":
			return [uid] if window_id == W_ENDED_NORMAL_MOVE and uid != "" else []
		"dubious-restraint-taktikal-brigade":
			return _friendly_unit_ids(player) if window_id in [W_PHASE_START, W_PHASE_END] else []
		"scarper-runt-swarm", "whirligig-evasion-flyboyz":
			return _friendly_unit_ids(player) if window_id == W_ENEMY_ENDED_MOVE else []
		"where-dya-fink-youre-going-da-big-hunt":
			return _friendly_unit_ids(player) if window_id == W_ENEMY_FALL_BACK else []
		"while-their-backs-are-turned-taktikal-brigade":
			return _friendly_unit_ids(player) if window_id == W_PHASE_END else []
	return []


## Friendly on-battlefield units, excluding attached CHARACTERs (their
## bodyguard id stands for the Attached unit, 19.01).
static func _friendly_unit_ids(player: int) -> Array:
	var out: Array = []
	var units = Common.state().get("units", {})
	for uid in units:
		var u = units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		var att = u.get("attached_to", null)
		if att != null and str(att) != "":
			continue
		if not Common.is_on_battlefield(u):
			continue
		out.append(str(uid))
	return out


## Rule check for one target. window_id == "" = no window context (S panel).
static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var name := _display_name(csv)
	var u := Common.unit(target_unit_id)
	if u.is_empty():
		return _no("%s needs a target unit" % name)
	if int(u.get("owner", 0)) != player:
		return _no("%s must target a unit from your army" % name)
	if not Common.is_on_battlefield(u):
		return _no("%s: that unit is not on the battlefield" % name)
	var selected := str(ctx.get("unit_id", ""))
	match csv:
		"fungus-fuel-injection-war-horde":
			if not Common.has_keyword(u, "ORKS") or not Common.has_any_keyword(u, ["MOUNTED", "VEHICLE"]):
				return _no("%s can only target an ORKS MOUNTED/VEHICLE unit" % name)
			if selected != "" and selected != target_unit_id:
				return _no("%s must target the unit that was selected to move" % name)
		"ere-we-go-green-tide":
			if not Common.has_any_keyword(u, ["BOYZ", "BEAST SNAGGA BOYZ"]):
				return _no("%s can only target a BEAST SNAGGA BOYZ/BOYZ unit" % name)
			if selected != "" and selected != target_unit_id:
				return _no("%s must target the unit that was selected to move" % name)
			if window_id == W_SELECTED_TO_MOVE and str(ctx.get("move_type", "")) != "advance":
				return _no("%s only affects advance rolls — offered when the unit advances" % name)
		"stomping-juggernaut-dread-mob":
			if not Common.has_keyword(u, "ORKS") or not Common.has_keyword(u, "WALKER"):
				return _no("%s can only target an ORKS WALKER unit" % name)
			if selected != "" and selected != target_unit_id:
				return _no("%s must target the unit that was selected to move / declared the charge" % name)
		"mind-mostly-on-the-mission-taktikal-brigade":
			if not Common.has_any_keyword(u, KW_BOYZ_KOMMANDOS_STORMBOYZ):
				return _no("%s can only target a BOYZ/KOMMANDOS/STORMBOYZ unit" % name)
			if selected != "" and selected != target_unit_id:
				return _no("%s must target the unit that was selected to move" % name)
			if window_id == W_SELECTED_TO_MOVE and not str(ctx.get("move_type", "")) in ["advance", "fall_back"]:
				return _no("%s: the unit must be selected to make an advance/fall-back move" % name)
		"dubious-restraint-taktikal-brigade":
			if not Common.has_any_keyword(u, KW_BOYZ_KOMMANDOS_STORMBOYZ):
				return _no("%s can only target a BOYZ/KOMMANDOS/STORMBOYZ unit" % name)
			var objs := controlled_objectives(target_unit_id, player)
			if objs.is_empty():
				return _no("%s: that unit is not controlling an objective (that is not already secured)" % name)
			var sec := str(ctx.get("secondary_id", ""))
			if sec != "" and not sec in objs:
				return _no("%s: %s is not an objective that unit is controlling" % [name, sec])
		"readied-brawlers-blitz-brigade":
			if not Common.has_keyword(u, "WAGON"):
				return _no("%s can only target a WAGON unit" % name)
			if selected != "" and selected != target_unit_id:
				return _no("%s must target the WAGON that ended the normal move" % name)
			if assault_disembark_candidates(target_unit_id).is_empty():
				return _no("%s: no unit embarked within that WAGON can disembark" % name)
		"scarper-runt-swarm", "whirligig-evasion-flyboyz":
			var kw := "GRETCHIN" if csv == "scarper-runt-swarm" else "DEFFKOPTAS"
			if not Common.has_keyword(u, kw):
				return _no("%s can only target a %s unit" % [name, kw])
			if is_attached_unit_engaged(target_unit_id):
				return _no("%s: that unit is engaged" % name)
			var enemy_id := str(ctx.get("enemy_unit_id", ""))
			var enemy := Common.unit(enemy_id)
			if window_id != "" and (enemy.is_empty() or int(enemy.get("owner", 0)) == player):
				return _no("%s: no enemy unit has just ended a move" % name)
			if enemy_id != "" and not _attached_within(target_unit_id, enemy_id, 8.0):
				return _no("%s: the enemy unit did not end its move within 8\" of that unit" % name)
		"where-dya-fink-youre-going-da-big-hunt":
			if not Common.has_keyword(u, "BEAST SNAGGA"):
				return _no("%s can only target a BEAST SNAGGA unit" % name)
			var fb_id := str(ctx.get("enemy_unit_id", ""))
			var fb := Common.unit(fb_id)
			if window_id != "" and (fb.is_empty() or int(fb.get("owner", 0)) == player):
				return _no("%s: no enemy unit has been selected to fall back" % name)
			if fb_id != "" and not units_engaged_with_each_other(target_unit_id, fb_id):
				return _no("%s: that enemy unit is not engaged with that BEAST SNAGGA unit" % name)
		"while-their-backs-are-turned-taktikal-brigade":
			if not Common.has_any_keyword(u, KW_BOYZ_KOMMANDOS_STORMBOYZ):
				return _no("%s can only target a BOYZ/KOMMANDOS/STORMBOYZ unit" % name)
			if is_attached_unit_engaged(target_unit_id):
				return _no("%s: that unit is engaged" % name)
			if window_id != "":
				var engaged_start: Array = ctx.get("engaged_at_phase_start", [])
				var was_engaged := false
				for gid in Common.attached_group_ids(target_unit_id):
					if str(gid) in engaged_start:
						was_engaged = true
				if not was_engaged:
					return _no("%s: that unit was not engaged at the start of the phase" % name)
		"dread-power-dread-mob":
			if not Common.has_keyword(u, "ORKS") or not Common.has_keyword(u, "WALKER"):
				return _no("%s can only target an ORKS WALKER unit" % name)
		"delicious-eating-squigs-kult-of-speed":
			if not Common.has_keyword(u, "RUKKATRUKK SQUIGBUGGIES"):
				return _no("%s can only target a RUKKATRUKK SQUIGBUGGIES unit" % name)
			if delicious_squigs_targets(target_unit_id, player).is_empty():
				return _no("%s: no friendly ORKS INFANTRY unit within 3\"" % name)
		_:
			return _no("%s is not yet mechanically implemented" % name)
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _display_name(csv: String) -> String:
	match csv:
		"fungus-fuel-injection-war-horde": return "FUNGUS-FUEL INJECTION"
		"ere-we-go-green-tide": return "'ERE WE GO"
		"stomping-juggernaut-dread-mob": return "STOMPING JUGGERNAUT"
		"mind-mostly-on-the-mission-taktikal-brigade": return "MIND MOSTLY ON THE MISSION"
		"dubious-restraint-taktikal-brigade": return "DUBIOUS RESTRAINT"
		"readied-brawlers-blitz-brigade": return "READIED BRAWLERS"
		"scarper-runt-swarm": return "SCARPER!"
		"whirligig-evasion-flyboyz": return "WHIRLIGIG EVASION"
		"where-dya-fink-youre-going-da-big-hunt": return "WHERE D'YA FINK YOU'RE GOING?"
		"while-their-backs-are-turned-taktikal-brigade": return "WHILE THEIR BACKS ARE TURNED"
		"dread-power-dread-mob": return "DREAD POWER"
		"delicious-eating-squigs-kult-of-speed": return "DELICIOUS EATING SQUIGS"
	return csv


# ---------------------------------------------------------------------------
# Shared geometry / state helpers (public: MovementPhase / FallBackMove /
# DisembarkMove / tests call them)
# ---------------------------------------------------------------------------

## 19.01: an Attached unit is engaged when any component is.
static func is_attached_unit_engaged(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if Common.is_engaged(str(gid)):
			return true
	return false

## True when the unit is an Attached unit (has a leader attached, or is one).
static func is_attached_unit(unit_id: String) -> bool:
	return Common.attached_group_ids(unit_id).size() > 1

## Closest distance between any component of unit A's Attached unit and unit B's.
static func _attached_within(a_id: String, b_id: String, inches: float) -> bool:
	for ga in Common.attached_group_ids(a_id):
		for gb in Common.attached_group_ids(b_id):
			if Common.within_inches(str(ga), str(gb), inches):
				return true
	return false

## Are the two (Attached) units engaged with each other? (11e 03.04)
static func units_engaged_with_each_other(a_id: String, b_id: String, board: Dictionary = {}) -> bool:
	var st: Dictionary = board if not board.is_empty() else Common.state()
	var re = Common.rules()
	if re == null:
		return false
	var units = st.get("units", {})
	for ga in Common.attached_group_ids(a_id):
		for gb in Common.attached_group_ids(b_id):
			var ua = units.get(str(ga), {})
			var ub = units.get(str(gb), {})
			if ua.is_empty() or ub.is_empty() or not Common.is_alive(ua) or not Common.is_alive(ub):
				continue
			if re.check_units_in_engagement_range(ua, ub, st):
				return true
	return false

## AI (FUNGUS-FUEL INJECTION on a Normal move): true when the extra 2" is what
## puts an objective its army does not control within control range (3"), or
## an enemy within an average (7") charge of a unit with melee weapons — the
## re-planned move (AIPlayer) can then use it. False otherwise (wasted CP).
static func _ffi_normal_move_gain(unit_id: String, player: int) -> bool:
	var u := Common.unit(unit_id)
	if u.is_empty() or Common.is_engaged(unit_id):
		return false
	var m := float(u.get("meta", {}).get("stats", {}).get("move", 0))
	if m <= 0.0:
		return false
	var oc := int(u.get("meta", {}).get("stats", {}).get("objective_control", 0))
	if oc > 0 and _uncontrolled_objective_within(unit_id, player, m + 2.0 + 3.0) \
			and not _uncontrolled_objective_within(unit_id, player, m + 3.0):
		return true
	if _charge_worthy_melee(unit_id) and _enemy_within(unit_id, player, m + 2.0 + 7.0) \
			and not _enemy_within(unit_id, player, m + 7.0):
		return true
	return false

## AI (FUNGUS-FUEL INJECTION): does the unit fight with a melee weapon worth
## charging with (S5+ or 3+ attacks)? A Mek Gunz crew's S2 A1 shivs or a bare
## S4 A2 close combat weapon is not a reason to spend CP on charge range.
static func _charge_worthy_melee(unit_id: String) -> bool:
	var re = Common.rules()
	var u := Common.unit(unit_id)
	if re == null or u.is_empty() or not re.has_method("get_unit_melee_weapons"):
		return false
	var profiles := {}
	for w in u.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee":
			profiles[str(w.get("name", ""))] = w
	for names in re.get_unit_melee_weapons(unit_id, Common.state()).values():
		for wname in names:
			var w: Dictionary = profiles.get(str(wname), {})
			if w.is_empty():
				continue
			var s_str := str(w.get("strength", "0"))
			var a_str := str(w.get("attacks", "0")).to_upper()
			var a := int(a_str) if a_str.is_valid_int() else (2 if a_str == "D3" else 3)
			if (s_str.is_valid_int() and int(s_str) >= 5) or a >= 3:
				return true
	return false

## AI (SCARPER! / WHIRLIGIG EVASION): can the enemy unit that just ended its
## move still charge `unit_id` this turn — eligible to declare a charge
## (RulesEngine: not advanced / fell back without a rule allowing it, ...) and
## within 12" (the 2D6 maximum)? Unknown enemy -> true (old behaviour).
static func _charge_threat(enemy_id: String, unit_id: String) -> bool:
	if enemy_id == "":
		return true
	var e := Common.unit(enemy_id)
	if e.is_empty() or not Common.is_on_battlefield(e):
		return false
	var re = Common.rules()
	if re != null and re.has_method("eligible_to_charge") and not re.eligible_to_charge(enemy_id, Common.state()):
		return false
	return _attached_within(enemy_id, unit_id, 12.0)

static func _enemy_within(unit_id: String, player: int, inches: float) -> bool:
	var units = Common.state().get("units", {})
	for eid in units:
		var e = units[eid]
		if int(e.get("owner", 0)) == player or not Common.is_on_battlefield(e):
			continue
		if _attached_within(unit_id, str(eid), inches):
			return true
	return false


# ---------------------------------------------------------------------------
# Objectives (DUBIOUS RESTRAINT / AI helpers)
# ---------------------------------------------------------------------------

## Objectives `unit_id` is controlling (14.02: within range of an objective its
## player controls, with at least one OC >= 1 model), excluding objectives its
## army has already secured. Ordered by board order (the AI takes the first).
static func controlled_objectives(unit_id: String, player: int) -> Array:
	var out: Array = []
	var mm = Common.autoload("MissionManager")
	if mm == null:
		return out
	var u := Common.unit(unit_id)
	if u.is_empty() or Common.is_battle_shocked(u):
		return out
	var oc := int(u.get("meta", {}).get("stats", {}).get("objective_control", 0))
	if oc <= 0:
		return out
	for obj in Common.state().get("board", {}).get("objectives", []):
		var oid := str(obj.get("id", ""))
		if oid == "":
			continue
		if mm.has_method("is_objective_active") and not mm.is_objective_active(oid):
			continue
		if int(mm.objective_control_state.get(oid, 0)) != player:
			continue
		var sec: Dictionary = mm.is_objective_secured(oid) if mm.has_method("is_objective_secured") else {}
		if bool(sec.get("secured", false)) and int(sec.get("player", 0)) == player:
			continue
		if _unit_in_range_of_objective(unit_id, obj):
			out.append(oid)
	return out

static func _unit_in_range_of_objective(unit_id: String, obj: Dictionary) -> bool:
	var mm = Common.autoload("MissionManager")
	if mm == null:
		return false
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			if mm.model_in_objective_range(m, obj):
				return true
	return false

static func _unit_in_range_of_any_objective(unit_id: String) -> bool:
	for obj in Common.state().get("board", {}).get("objectives", []):
		if _unit_in_range_of_objective(unit_id, obj):
			return true
	return false

static func _uncontrolled_objective_within(unit_id: String, player: int, inches: float) -> bool:
	var mm = Common.autoload("MissionManager")
	if mm == null:
		return false
	for obj in Common.state().get("board", {}).get("objectives", []):
		var oid := str(obj.get("id", ""))
		if int(mm.objective_control_state.get(oid, 0)) == player:
			continue
		for gid in Common.attached_group_ids(unit_id):
			for m in Common.unit(str(gid)).get("models", []):
				if m.get("alive", true) and m.get("position", null) != null \
						and mm.model_within_inches_of_objective(m, obj, inches):
					return true
	return false

static func objective_label(obj_id: String) -> String:
	var mm = Common.autoload("MissionManager")
	var desig := ""
	if mm and mm.has_method("get_objective_designation"):
		desig = str(mm.get_objective_designation(obj_id))
	# Where it is on the board, so the player can tell the markers apart.
	var where := ""
	var gs = Common.autoload("GameState")
	if gs:
		for obj in gs.state.get("board", {}).get("objectives", []):
			if str(obj.get("id", "")) == obj_id:
				var p = obj.get("position", null)
				if p is Dictionary:
					where = "%d\", %d\"" % [roundi(float(p.get("x", 0)) / 40.0), roundi(float(p.get("y", 0)) / 40.0)]
				elif p is Vector2:
					where = "%d\", %d\"" % [roundi(p.x / 40.0), roundi(p.y / 40.0)]
				break
	var label := "Objective %s" % obj_id
	if desig != "":
		label += " (%s)" % desig
	if where != "":
		label += " at %s" % where
	return label

static func _dubious_restraint_apply(unit_id: String, player: int, ctx: Dictionary) -> Array:
	var objs := controlled_objectives(unit_id, player)
	var obj_id := str(ctx.get("secondary_id", ""))
	if obj_id == "" and not objs.is_empty():
		obj_id = str(objs[0])
	if obj_id == "" or not obj_id in objs:
		Common.log_error("OrkCodexMovement: DUBIOUS RESTRAINT — %s controls no objective %s; nothing secured" % [unit_id, obj_id])
		return []
	var mm = Common.autoload("MissionManager")
	# 14.03: secured by the ARMY (empty source unit) — it stays under the
	# player's control until the opponent's level of control is greater at the
	# end of a phase, even if this unit leaves or dies.
	mm.secure_objective(obj_id, player, "")
	Common.log_info("OrkCodexMovement: DUBIOUS RESTRAINT — %s secures %s for player %d" % [unit_id, obj_id, player])
	_event_log(player, "DUBIOUS RESTRAINT: %s secures %s" % [Common.unit_name(unit_id), objective_label(obj_id)])
	return Common.set_flag_diffs([unit_id], FLAG_DUBIOUS_RESTRAINT, obj_id)


# ---------------------------------------------------------------------------
# Reactive normal moves (SCARPER! / WHIRLIGIG EVASION / WHILE THEIR BACKS ARE TURNED)
# ---------------------------------------------------------------------------

static func _reactive_move_apply(source: String, unit_id: String, player: int, six_inch: bool, six_reason: String, ctx: Dictionary, goal: String) -> Dictionary:
	var cap := 6.0
	var roll := 0
	var uname := Common.unit_name(unit_id)
	if six_inch:
		Common.log_info("OrkCodexMovement: %s — %s is %s: normal move of up to 6\"" % [source, unit_id, six_reason])
		_event_log(player, "%s: %s (%s) can make a normal move of up to 6\"" % [source, uname, six_reason])
	else:
		var re = Common.rules()
		var rng = re.make_rng() if re else null
		roll = int(rng.roll_d6(1)[0]) if rng else randi_range(1, 6)
		cap = float(roll)
		Common.log_info("OrkCodexMovement: %s — %s rolls D6 = %d: normal move of up to %d\"" % [source, unit_id, roll, roll])
		_event_log(player, "%s: %s rolls D6 = %d — normal move of up to %d\"" % [source, uname, roll, roll])
	return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": unit_id, "max_inches": cap,
		"roll": roll, "source": source, "goal": goal, "away_from_unit_id": str(ctx.get("enemy_unit_id", ""))}}


# ---------------------------------------------------------------------------
# READIED BRAWLERS — assault disembark (18.06)
# ---------------------------------------------------------------------------

## Units embarked within `transport_id` that are eligible to disembark now
## (18.06 ELIGIBLE IF: transport on the battlefield, did not embark this
## phase, transport has not advanced / fallen back this phase). Attached
## CHARACTERs ride with their bodyguard and are not listed separately.
static func assault_disembark_candidates(transport_id: String) -> Array:
	var out: Array = []
	var t := Common.unit(transport_id)
	if t.is_empty() or not Common.is_on_battlefield(t):
		return out
	var tf = t.get("flags", {})
	if tf.get("advanced", false) or tf.get("fell_back", false):
		return out
	for uid in t.get("transport_data", {}).get("embarked_units", []):
		var u := Common.unit(str(uid))
		if u.is_empty() or not Common.is_alive(u):
			continue
		if str(u.get("embarked_in", "")) != transport_id:
			continue
		var att = u.get("attached_to", null)
		if att != null and str(att) != "":
			continue
		if u.get("flags", {}).get("embarked_this_phase", false):
			continue
		out.append(str(uid))
	return out

## DisembarkMove.select_mode consumer: an embarked unit whose transport has
## READIED BRAWLERS active makes an assault disembark move (18.06).
static func transport_grants_assault_disembark(transport: Dictionary) -> bool:
	return bool(transport.get("flags", {}).get(FLAG_READIED_BRAWLERS, false))


# ---------------------------------------------------------------------------
# WHERE D'YA FINK YOU'RE GOING? — FallBackMove consumers
# ---------------------------------------------------------------------------

## The falling-back unit is engaged with an enemy unit that has the
## stratagem's effect this phase -> desperate escape is mandatory.
static func where_dya_fink_forces_desperate_escape(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var u = units.get(unit_id, {})
	if u.is_empty():
		return false
	var owner := int(u.get("owner", 0))
	for oid in units:
		var o = units[oid]
		if int(o.get("owner", 0)) == owner or not o.get("flags", {}).get(FLAG_WHERE_DYA_FINK, false):
			continue
		if units_engaged_with_each_other(str(oid), unit_id, board):
			return true
	return false

## Additional desperate-escape hazard rolls for a MONSTER/VEHICLE unit forced
## by the stratagem: 3 per enemy BEAST SNAGGA unit it is engaged with, -1 to
## those rolls while it is battle-shocked. {count, modifier}
static func where_dya_fink_extra_hazard(unit_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var u = units.get(unit_id, {})
	if u.is_empty() or not where_dya_fink_forces_desperate_escape(unit_id, board):
		return {"count": 0, "modifier": 0}
	if not Common.has_any_keyword(u, ["MONSTER", "VEHICLE"]):
		return {"count": 0, "modifier": 0}
	var owner := int(u.get("owner", 0))
	var bs_units := 0
	for oid in units:
		var o = units[oid]
		if int(o.get("owner", 0)) == owner or not Common.has_keyword(o, "BEAST SNAGGA"):
			continue
		var att = o.get("attached_to", null)
		if att != null and str(att) != "":
			continue  # an attached BEAST SNAGGA leader is part of its bodyguard's unit
		if units_engaged_with_each_other(str(oid), unit_id, board):
			bs_units += 1
	var shocked: bool = bool(u.get("flags", {}).get("battle_shocked", false))
	return {"count": 3 * bs_units, "modifier": -1 if shocked else 0}

static func _where_dya_fink_score(enemy_id: String, _bs_unit_id: String) -> float:
	var e := Common.unit(enemy_id)
	if e.is_empty():
		return 0.0
	var alive := 0
	for m in e.get("models", []):
		if m.get("alive", true):
			alive += 1
	var mv := Common.has_any_keyword(e, ["MONSTER", "VEHICLE"])
	var per_mw := 3.0 if mv else 1.0
	var shocked := Common.is_battle_shocked(e)
	var expected := 0.0
	if not shocked:
		expected += float(alive) / 3.0 * per_mw   # forced desperate escape (2/6 fail)
	if mv:
		var p_fail := 3.0 / 6.0 if shocked else 2.0 / 6.0
		expected += 3.0 * p_fail * 3.0             # at least one BEAST SNAGGA unit
	return 1.0 + expected if expected > 0.0 else 0.0


# ---------------------------------------------------------------------------
# DREAD POWER — riled up (= the 11e Waaagh! state) until the start of your next turn
# ---------------------------------------------------------------------------

## The riled-up benefits mirror the single-unit Waaagh! of GRAB AND BASH
## (waaagh_active: every engine consumer of the Waaagh! state; 5+ invulnerable
## save; advance and still charge) plus the 11e riled-up [ASSAULT] on ranged
## weapons (effect_advance_and_shoot). ork11e_riled_up feeds Common.is_riled_up.
static func _dread_power_apply(unit_id: String, player: int) -> Array:
	var diffs: Array = []
	for gid in Common.attached_group_ids(unit_id):
		var g := Common.unit(str(gid))
		var flags: Dictionary = g.get("flags", {})
		diffs.append_array(Common.set_flag_diffs([gid], "waaagh_active", true))
		diffs.append_array(Common.set_flag_diffs([gid], FLAG_RILED_UP, true))
		diffs.append_array(Common.set_flag_diffs([gid], FLAG_DREAD_POWER, true))
		diffs.append_array(Common.set_flag_diffs([gid], "effect_advance_and_charge", true))
		if not bool(flags.get("effect_advance_and_shoot", false)):
			diffs.append_array(Common.set_flag_diffs([gid], "effect_advance_and_shoot", true))
			diffs.append_array(Common.set_flag_diffs([gid], FLAG_DREAD_POWER_ADV_SHOOT, true))
		var inv := int(flags.get("effect_invuln", 0))
		if inv == 0 or inv > 5:
			diffs.append_array(Common.set_flag_diffs([gid], "effect_invuln", 5))
			diffs.append_array(Common.set_flag_diffs([gid], "effect_invuln_source", DREAD_POWER_SOURCE))
	Common.log_info("OrkCodexMovement: DREAD POWER — %s is riled up until the start of player %d's next turn (5+ invuln, [ASSAULT], advance and charge)" % [unit_id, player])
	_event_log(player, "DREAD POWER: %s is riled up until the start of your next turn (5+ invulnerable save, ranged [ASSAULT], can charge after advancing)" % Common.unit_name(unit_id))
	return diffs

static func _dread_power_clear(group: Array) -> void:
	var fam = Common.autoload("FactionAbilityManager")
	for gid in group:
		var g := Common.unit(str(gid))
		if g.is_empty():
			continue
		var flags: Dictionary = g.get("flags", {})
		if not flags.get(FLAG_DREAD_POWER, false):
			continue
		var owner := int(g.get("owner", 0))
		# The army-wide Waaagh! may still cover this unit (it has the ability and
		# the player's Waaagh! is active) — leave its flags alone then.
		var army_waaagh: bool = fam != null and fam.has_method("is_waaagh_active") and fam.is_waaagh_active(owner) \
				and fam.has_method("_unit_has_waaagh_ability") and fam._unit_has_waaagh_ability(g)
		if not army_waaagh:
			flags.erase("waaagh_active")
			flags.erase("effect_advance_and_charge")
		if flags.get("effect_invuln_source", "") == DREAD_POWER_SOURCE:
			flags.erase("effect_invuln")
			flags.erase("effect_invuln_source")
		if flags.get(FLAG_DREAD_POWER_ADV_SHOOT, false):
			flags.erase("effect_advance_and_shoot")
		flags.erase(FLAG_DREAD_POWER_ADV_SHOOT)
		flags.erase(FLAG_DREAD_POWER)
		flags.erase(FLAG_RILED_UP)
		Common.log_info("OrkCodexMovement: DREAD POWER expired on %s (army Waaagh! still active: %s)" % [gid, str(army_waaagh)])


# ---------------------------------------------------------------------------
# DELICIOUS EATING SQUIGS — heal 3 (02.02.04)
# ---------------------------------------------------------------------------

## Friendly ORKS INFANTRY units (Attached units by bodyguard id) within 3" of
## the RUKKATRUKK SQUIGBUGGIES unit.
static func delicious_squigs_targets(buggies_id: String, player: int) -> Array:
	var out: Array = []
	for uid in _friendly_unit_ids(player):
		if uid == buggies_id:
			continue
		var u := Common.unit(uid)
		if not Common.has_keyword(u, "ORKS") or not Common.has_keyword(u, "INFANTRY"):
			continue
		if _attached_within(buggies_id, uid, 3.0):
			out.append(uid)
	return out

static func _delicious_squigs_apply(buggies_id: String, player: int) -> Array:
	var diffs: Array = []
	var summary: Array = []
	for uid in delicious_squigs_targets(buggies_id, player):
		var res := heal_unit_diffs(str(uid), 3)
		diffs.append_array(res.diffs)
		var part := "%s %d" % [Common.unit_name(str(uid)), int(res.healed) + int(res.revived)]
		if int(res.revived) > 0:
			part += " (%d model(s) revived, set up in coherency)" % int(res.revived)
		if int(res.no_room) > 0:
			part += " (%d revive(s) lost: no legal set-up spot)" % int(res.no_room)
		summary.append(part)
		Common.log_info("OrkCodexMovement: DELICIOUS EATING SQUIGS — %s heals %d wound(s), revives %d model(s) at %s, %d revive(s) without a legal spot" % [uid, int(res.healed), int(res.revived), str(res.placements), int(res.no_room)])
	_event_log(player, "DELICIOUS EATING SQUIGS (%s): units heal 3 wounds — %s" % [Common.unit_name(buggies_id), ", ".join(PackedStringArray(summary)) if not summary.is_empty() else "none"])
	return diffs

## What DELICIOUS EATING SQUIGS would do right now, without changing state:
## [{unit_id, healed, revived, no_room, placements: [{unit_id, model_id, position: Vector2}]}].
## Main shows it to a human before the stratagem is used (the revived models
## are auto-placed; apply recomputes the same placement deterministically).
static func delicious_squigs_preview(buggies_id: String, player: int) -> Array:
	var out: Array = []
	for uid in delicious_squigs_targets(buggies_id, player):
		var res := heal_unit_diffs(str(uid), 3)
		out.append({"unit_id": str(uid), "healed": int(res.healed), "revived": int(res.revived),
			"no_room": int(res.no_room), "placements": res.placements})
	return out

## Wounds the unit could regain (lost wounds + revivable non-CHARACTER models).
static func _healable_wounds(unit_id: String) -> int:
	var n := 0
	for gid in Common.attached_group_ids(unit_id):
		var g := Common.unit(str(gid))
		var is_char := Common.has_keyword(g, "CHARACTER")
		for m in g.get("models", []):
			if m.get("alive", true):
				n += maxi(0, int(m.get("wounds", 1)) - int(m.get("current_wounds", m.get("wounds", 1))))
			elif not is_char:
				n += 1
	return n

## 02.02.04: for each wound — a wounded model regains one wound; if every model
## is at full wounds, a destroyed non-CHARACTER model is revived with 1 wound;
## excess is lost. 01.02.03: a revived model is SET UP in coherency with models
## of its unit that started the phase on the battlefield, not overlapping any
## model, on the battlefield, and engaged only with enemy units that were
## already engaged with its unit — it does not reappear where it died (the
## survivors may have moved since). The set-up spot is chosen automatically
## (_revive_position); a model with no legal spot is not revived and the next
## destroyed model is tried, else the wound is lost.
## Returns {diffs, healed, revived, no_room, placements} (state is not mutated).
static func heal_unit_diffs(unit_id: String, amount: int) -> Dictionary:
	var sim: Array = []   # [{uid, idx, alive, cur, max, char, touched, pos, unplaceable}]
	var group: Array = Common.attached_group_ids(unit_id)
	for gid in group:
		var g := Common.unit(str(gid))
		var is_char := Common.has_keyword(g, "CHARACTER")
		var models: Array = g.get("models", [])
		for i in range(models.size()):
			var m = models[i]
			sim.append({"uid": str(gid), "idx": i, "alive": bool(m.get("alive", true)),
				"cur": int(m.get("current_wounds", m.get("wounds", 1))), "max": int(m.get("wounds", 1)),
				"char": is_char, "touched": false, "pos": null, "unplaceable": false})
	var healed := 0
	var revived := 0
	var no_room := 0
	var placed: Array = []    # revived models already set up by this heal: [{uid, idx, pos}]
	var placements: Array = []
	for _i in range(amount):
		var done := false
		for s in sim:
			if s.alive and s.cur < s.max:
				s.cur += 1
				s.touched = true
				healed += 1
				done = true
				break
		if done:
			continue
		var had_candidate := false
		for s in sim:
			if s.alive or s.char or s.unplaceable:
				continue
			had_candidate = true
			var spot = _revive_position(group, str(s.uid), int(s.idx), placed)
			if spot == null:
				s.unplaceable = true
				no_room += 1
				Common.log_info("OrkCodexMovement: revive — no legal set-up spot for %s model %d (01.02.03); not revived" % [s.uid, int(s.idx)])
				continue
			s.alive = true
			s.cur = 1
			s.touched = true
			s.pos = spot
			placed.append({"uid": s.uid, "idx": s.idx, "pos": spot})
			var mdl: Dictionary = Common.unit(str(s.uid)).get("models", [])[int(s.idx)]
			placements.append({"unit_id": str(s.uid), "model_id": str(mdl.get("id", s.idx)), "position": spot})
			revived += 1
			done = true
			break
		if not done:
			if had_candidate:
				continue   # this wound found no placeable model; the next wound has none either
			break
	var diffs: Array = []
	for s in sim:
		if not s.touched:
			continue
		diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [s.uid, s.idx], "value": s.cur})
		if s.pos != null:
			var p: Vector2 = s.pos
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [s.uid, s.idx], "value": {"x": p.x, "y": p.y}})
		diffs.append({"op": "set", "path": "units.%s.models.%d.alive" % [s.uid, s.idx], "value": s.alive})
	return {"diffs": diffs, "healed": healed, "revived": revived, "no_room": no_room, "placements": placements}

## 01.02.03 set-up spot for a revived model (Vector2 px) or null when there is
## no legal one. Candidates: the spot where it died first (if it is still
## legal), then rings around each anchor model (alive models of its unit that
## started the phase on the battlefield), nearest to where it died first.
## A candidate must: be on the battlefield, not overlap any model or a wall,
## be within coherency range of an anchor, keep the whole Attached unit in
## coherency (2" + the 11e 9" envelope, AttackSequence's End-of-Turn verdict),
## and not be within Engagement Range of an enemy unit that is not already
## engaged with the unit.
static func _revive_position(group: Array, uid: String, idx: int, placed: Array):
	var meas = Common.autoload("Measurement")
	if meas == null:
		return null
	var units: Dictionary = Common.state().get("units", {})
	var model: Dictionary = (units.get(uid, {}).get("models", [])[idx] as Dictionary).duplicate(true)
	var kws: Array = units.get(uid, {}).get("meta", {}).get("keywords", [])
	var anchors: Array = []
	for gid in group:
		var gu: Dictionary = units.get(str(gid), {})
		if not Common.is_on_battlefield(gu) or not _started_phase_on_battlefield(gu):
			continue
		for m in gu.get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				anchors.append(m)
	if anchors.is_empty():
		return null
	# Every other model on the battlefield (overlap) and the enemy models
	# (engagement), split by whether their unit is already engaged with ours.
	var others: Array = []
	var enemy_free: Array = []
	var my_owner := int(units.get(uid, {}).get("owner", 0))
	for ouid in units:
		var ou: Dictionary = units[ouid]
		if not Common.is_on_battlefield(ou):
			continue
		var is_enemy := int(ou.get("owner", 0)) != my_owner
		var engaged_already := false
		if is_enemy:
			for em in ou.get("models", []):
				if not em.get("alive", true) or em.get("position", null) == null:
					continue
				for am in anchors:
					if meas.is_in_engagement_range_shape_aware(am, em):
						engaged_already = true
						break
				if engaged_already:
					break
		for om in ou.get("models", []):
			if om.get("alive", true) and om.get("position", null) != null:
				others.append(om)
				if is_enemy and not engaged_already:
					enemy_free.append(om)
	for p in placed:
		var pm: Dictionary = (units.get(str(p.uid), {}).get("models", [])[int(p.idx)] as Dictionary).duplicate(true)
		pm["position"] = p.pos
		pm["alive"] = true
		others.append(pm)
	var death_pos = _model_pos_or_null(model)
	var ref: Vector2 = death_pos if death_pos != null else Common._pos(anchors[0])
	var r_m := float(meas.base_extent_px(model))
	# Where it died first; then rings around the anchors, tightest ring first
	# (keeps the unit compact), each ring nearest to where the model died.
	var candidates: Array = []
	if death_pos != null:
		candidates.append(death_pos)
	for gap_in in [0.3, 0.9, 1.5]:
		var ring: Array = []
		for am in anchors:
			var c: Vector2 = Common._pos(am)
			var r_a := float(meas.base_extent_px(am))
			var dist: float = r_a + r_m + float(meas.inches_to_px(gap_in))
			for k in range(24):
				var ang := TAU * float(k) / 24.0
				ring.append(c + Vector2(cos(ang), sin(ang)) * dist)
		ring.sort_custom(func(a, b): return a.distance_squared_to(ref) < b.distance_squared_to(ref))
		candidates.append_array(ring)
	var AttackSeq = load("res://scripts/rules/AttackSequence.gd")
	for cand in candidates:
		var test := model.duplicate(true)
		test["position"] = cand
		test["alive"] = true
		if meas.model_outside_board(cand, test):
			continue
		if meas.model_overlaps_any(test, others):
			continue
		if meas.has_method("model_overlaps_any_wall") and meas.model_overlaps_any_wall(test, kws):
			continue
		var near_anchor := false
		for am in anchors:
			if meas.is_within_coherency(test, am):
				near_anchor = true
				break
		if not near_anchor:
			continue
		var engages_new := false
		for em in enemy_free:
			if meas.is_in_engagement_range_shape_aware(test, em):
				engages_new = true
				break
		if engages_new:
			continue
		# Whole Attached unit coherent with the model (and earlier revives) set up.
		var components: Array = []
		for gid in group:
			var ms: Array = (units.get(str(gid), {}).get("models", []) as Array).duplicate(true)
			for p in placed:
				if str(p.uid) == str(gid):
					ms[int(p.idx)]["position"] = p.pos
					ms[int(p.idx)]["alive"] = true
			if str(gid) == uid:
				ms[idx] = test
			components.append({"unit_id": str(gid), "models": ms})
		if AttackSeq != null and not bool(AttackSeq.attached_coherency_offenders(components).get("coherent", true)):
			continue
		return cand
	return null

## False for a unit that was set up on the battlefield during this Movement
## phase (disembarked, or arrived from reserves this battle round): its models
## did not start the phase on the battlefield (01.02.03 anchor rule).
static func _started_phase_on_battlefield(u: Dictionary) -> bool:
	if bool(u.get("disembarked_this_phase", false)):
		return false
	var gs = Common.game_state()
	var arrived := int(u.get("arrived_from_reserves_turn", -1))
	if arrived > 0 and gs != null and gs.has_method("get_battle_round") and arrived == int(gs.get_battle_round()) \
			and gs.has_method("get_current_phase") and int(gs.get_current_phase()) == int(GameStateData.Phase.MOVEMENT):
		return false
	return true

static func _model_pos_or_null(m: Dictionary):
	var p = m.get("position", null)
	if p == null:
		return null
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	if p is Vector2:
		return p
	return null


# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

static func _event_log(player: int, text: String) -> void:
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, text)
