extends RefCounted

## OrkCodexShootingReactive — Codex: Orks (11e) stratagems of the SHOOTING-REACTIVE group:
## the own-turn unit_has_shot window (GRAB IT) and the opponent-Shooting windows
## (enemy_targets_unit_shooting, enemy_has_shot).
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
## Windows / hooks (ShootingPhase):
##   enemy_targets_unit_shooting — folded into the defender's reactive dialog
##     (_check_reactive_stratagems); ctx {attacker_unit_id, target_unit_ids}.
##   unit_has_shot  — active player, after a unit's shooting fully resolved;
##     ctx {unit_id}.
##   enemy_has_shot — non-active player, same moment; ctx {attacker_unit_id,
##     hit_unit_ids, wounded_unit_ids}.
## Follow-ups (design §3.2) executed by ShootingPhase._execute_window_followup:
##   reactive_normal_move (GRAB IT), surge_move (GOADED INTO ACTION),
##   shoot (GUN-CRAZY SHOW-OFFS).
##
## Engine consumers (RulesEngine, every ranged resolver path):
##   ork11e_hulking_brutes  -> ork11e_ranged_wound_penalty
##   ork11e_speediest_freeks -> ork11e_ranged_hit_fail_band
##   ork11e_grot_shields    -> ork11e_grot_shields_intercept
##   ork11e_grab_it_no_charge -> charge eligibility (ChargePhase, ChargeMove11e,
##     RulesEngine.eligible_to_charge)
## None of these flags uses the effect_ prefix: ShootingPhase wipes effect_*
## at the end of the phase, and GRAB IT's charge lock must outlive it.

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

## Every csv_id owned by this group (registry). Do not move ids between groups.
const IDS: Array = [
	"grab-it-wreckas",
	"grot-shields-runt-swarm",
	"hulking-brutes-bully-boyz",
	"speediest-freeks-kult-of-speed",
	"gun-crazy-show-offs-wreckas",
	"goaded-into-action-da-big-hunt",
]

## csv_ids whose handler is complete and validated.
const IMPLEMENTED: Dictionary = {
	"grab-it-wreckas": true,
	"grot-shields-runt-swarm": true,
	"hulking-brutes-bully-boyz": true,
	"speediest-freeks-kult-of-speed": true,
	"gun-crazy-show-offs-wreckas": true,
	"goaded-into-action-da-big-hunt": true,
}

const AI_KIND: Dictionary = {
	"grab-it-wreckas": "utility",
	"grot-shields-runt-swarm": "defensive",
	"hulking-brutes-bully-boyz": "defensive",
	"speediest-freeks-kult-of-speed": "defensive",
	"gun-crazy-show-offs-wreckas": "utility",
	"goaded-into-action-da-big-hunt": "utility",
}

# Flag names written by this group's handlers (see the header).
const FLAG_HULKING_BRUTES := "ork11e_hulking_brutes"      # "s_gt_t" | "all"
const FLAG_SPEEDIEST_FREEKS := "ork11e_speediest_freeks"  # bool
const FLAG_GROT_SHIELDS := "ork11e_grot_shields"          # {gretchin_unit_id, attacker_unit_ids, player}
const FLAG_GROT_SHIELDS_SOURCE := "ork11e_grot_shields_source"  # on the Gretchin: shielded unit id
const FLAG_GRAB_IT_NO_CHARGE := "ork11e_grab_it_no_charge"  # bool, until the end of the turn

const HULKING_BRUTES_UPGRADE := "all_ranged"
const GRAB_IT_MOVE_INCHES := 6.0
const GROT_SHIELDS_RANGE_INCHES := 3.0
const GRAB_IT_KEYWORDS: Array = ["BREAKA BOYZ", "FLASH GITZ", "TANKBUSTAS"]
const GUN_CRAZY_KEYWORDS: Array = ["FLASH GITZ", "TANKBUSTAS"]


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	match str(strat.get("csv_id", "")):
		"hulking-brutes-bully-boyz":
			if window_id != "enemy_targets_unit_shooting":
				return []
			return _targeted_unit_entries(strat, player, ctx, true)
		"speediest-freeks-kult-of-speed":
			if window_id != "enemy_targets_unit_shooting":
				return []
			return _targeted_unit_entries(strat, player, ctx, false)
		"grot-shields-runt-swarm":
			if window_id != "enemy_targets_unit_shooting":
				return []
			return _grot_shields_targets(player, ctx)
		"grab-it-wreckas":
			if window_id != "unit_has_shot":
				return []
			var uid := str(ctx.get("unit_id", ""))
			if not _grab_it_validate(player, uid, ctx).ok:
				return []
			return [Common.target_entry(uid)]
		"gun-crazy-show-offs-wreckas":
			if window_id != "enemy_has_shot":
				return []
			return _post_shot_entries(strat, player, ctx, ctx.get("hit_unit_ids", []))
		"goaded-into-action-da-big-hunt":
			if window_id != "enemy_has_shot":
				return []
			return _goaded_entries(_post_shot_entries(strat, player, ctx, ctx.get("wounded_unit_ids", [])))
	return []

## GOADED INTO ACTION on a unit that casualties left OUT OF COHERENCY (LIVE-7):
## the surge, like every move, must end in coherency (03.03), so it is offered
## only when a coherent surge end exists at the maximum D6 (6"), and the button
## warns that the move has to restore coherency.
static func _goaded_entries(entries: Array) -> Array:
	var out: Array = []
	var lib = load("res://scripts/rules/ReactiveMove11e.gd")
	for e in entries:
		var uid := str(e.get("unit_id", ""))
		if lib == null or uid == "":
			out.append(e)
			continue
		var board := Common.state()
		if lib.group_coherent(uid, board):
			out.append(e)
			continue
		var origin: Dictionary = lib.current_positions(uid, board)
		var target := str(lib.surge_target(uid, board))
		var best: Dictionary = lib.solve("surge", uid, origin, 6.0, {"surge_target": target}, board) if target != "" else {}
		if best.is_empty():
			Common.log_info("OrkCodexShootingReactive: GOADED INTO ACTION not offered for %s — out of coherency and no surge of up to 6\" can restore it" % uid)
			continue
		e["label"] = "%s (out of coherency — the surge must restore it)" % Common.unit_name(uid)
		out.append(e)
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match str(strat.get("csv_id", "")):
		"hulking-brutes-bully-boyz":
			return _targeted_validate("HULKING BRUTES", ["MEGANOBZ", "NOBZ"], "MEGANOBZ/NOBZ", player, target_unit_id, ctx)
		"speediest-freeks-kult-of-speed":
			return _targeted_validate("SPEEDIEST FREEKS", ["SPEED FREEKS"], "SPEED FREEKS", player, target_unit_id, ctx)
		"grot-shields-runt-swarm":
			return _grot_shields_validate(player, target_unit_id, ctx)
		"grab-it-wreckas":
			return _grab_it_validate(player, target_unit_id, ctx)
		"gun-crazy-show-offs-wreckas":
			return _gun_crazy_validate(player, target_unit_id, ctx)
		"goaded-into-action-da-big-hunt":
			return _goaded_validate(player, target_unit_id, ctx)
	return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	match str(strat.get("csv_id", "")):
		"hulking-brutes-bully-boyz":
			var mode := "all" if str(ctx.get("variant_id", "")) == HULKING_BRUTES_UPGRADE else "s_gt_t"
			var hb_group = Common.attached_group_ids(target_unit_id)
			Common.log_info("OrkCodexShootingReactive: HULKING BRUTES on %s — %s" % [str(hb_group),
				"every ranged attack that targets the unit has -1 to wound (+1CP)" if mode == "all"
				else "ranged attacks with S > T that target the unit have -1 to wound"])
			return Common.set_flag_diffs(hb_group, FLAG_HULKING_BRUTES, mode)
		"speediest-freeks-kult-of-speed":
			var sf_group = Common.attached_group_ids(target_unit_id)
			Common.log_info("OrkCodexShootingReactive: SPEEDIEST FREEKS on %s — ranged attacks that target the unit fail on an unmodified hit roll of 1-3" % str(sf_group))
			return Common.set_flag_diffs(sf_group, FLAG_SPEEDIEST_FREEKS, true)
		"grot-shields-runt-swarm":
			return _grot_shields_apply(target_unit_id, ctx)
		"grab-it-wreckas":
			var gi_group = Common.attached_group_ids(target_unit_id)
			Common.log_info("OrkCodexShootingReactive: GRAB IT — %s can make a normal move of up to 6\" ending within range of an objective; not eligible to declare a charge until the end of the turn" % str(gi_group))
			return {
				"diffs": Common.set_flag_diffs(gi_group, FLAG_GRAB_IT_NO_CHARGE, true),
				"followup": {"type": "reactive_normal_move", "unit_id": target_unit_id,
					"max_inches": GRAB_IT_MOVE_INCHES, "end_condition": "within_objective_range",
					"source": "GRAB IT"},
			}
		"gun-crazy-show-offs-wreckas":
			var forced := _head_id(str(ctx.get("attacker_unit_id", "")))
			Common.log_info("OrkCodexShootingReactive: GUN-CRAZY SHOW-OFFS — %s shoots (normal shooting) and can only target %s" % [target_unit_id, forced])
			return {"diffs": [], "followup": {"type": "shoot", "unit_id": target_unit_id,
				"forced_target_id": forced, "source": "GUN-CRAZY SHOW-OFFS"}}
		"goaded-into-action-da-big-hunt":
			var riled := Common.is_riled_up(Common.unit(target_unit_id))
			Common.log_info("OrkCodexShootingReactive: GOADED INTO ACTION — %s can make a surge move of up to D6\"%s" % [
				target_unit_id, " (riled up: the D6 can be re-rolled)" if riled else ""])
			return {"diffs": [], "followup": {"type": "surge_move", "unit_id": target_unit_id,
				"dice": "D6", "reroll_allowed": riled, "source": "GOADED INTO ACTION"}}
	Common.log_error("OrkCodexShootingReactive: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	match str(strat.get("csv_id", "")):
		"hulking-brutes-bully-boyz":
			Common.erase_flags(Common.attached_group_ids(unit_id), [FLAG_HULKING_BRUTES])
			Common.log_info("OrkCodexShootingReactive: HULKING BRUTES expired on %s" % unit_id)
		"speediest-freeks-kult-of-speed":
			Common.erase_flags(Common.attached_group_ids(unit_id), [FLAG_SPEEDIEST_FREEKS])
			Common.log_info("OrkCodexShootingReactive: SPEEDIEST FREEKS expired on %s" % unit_id)
		"grot-shields-runt-swarm":
			# unit_id = the Gretchin unit (the stratagem's target); the shield
			# flag lives on the protected unit it names.
			var units = Common.state().get("units", {})
			var shielded := str(units.get(unit_id, {}).get("flags", {}).get(FLAG_GROT_SHIELDS_SOURCE, ""))
			for uid in units:
				var f = units[uid].get("flags", {}).get(FLAG_GROT_SHIELDS, null)
				if typeof(f) == TYPE_DICTIONARY and str(f.get("gretchin_unit_id", "")) == unit_id:
					units[uid]["flags"].erase(FLAG_GROT_SHIELDS)
			Common.erase_flags([unit_id], [FLAG_GROT_SHIELDS_SOURCE])
			Common.log_info("OrkCodexShootingReactive: GROT SHIELDS expired (Gretchin %s, shielded %s)" % [unit_id, shielded])
		"grab-it-wreckas":
			Common.erase_flags(Common.attached_group_ids(unit_id), [FLAG_GRAB_IT_NO_CHARGE])
			Common.log_info("OrkCodexShootingReactive: GRAB IT charge lock expired on %s" % unit_id)


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


## CP cost of a variant offered in a target entry's `variants` — HULKING
## BRUTES' "+1CP Or: ranged attacks that target your unit have -1 to wound".
static func variant_cp_cost(strat: Dictionary, variant_id: String) -> int:
	if str(strat.get("csv_id", "")) == "hulking-brutes-bully-boyz" and variant_id == HULKING_BRUTES_UPGRADE:
		return int(strat.get("cp_cost", 1)) + 1
	return -1


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	match str(strat.get("csv_id", "")):
		"hulking-brutes-bully-boyz":
			return _hulking_brutes_score(target_unit_id, ctx)
		"speediest-freeks-kult-of-speed":
			return _speediest_freeks_score(target_unit_id, ctx)
		"grot-shields-runt-swarm":
			return _grot_shields_score(target_unit_id, ctx)
		"grab-it-wreckas":
			return _grab_it_score(target_unit_id)
		"gun-crazy-show-offs-wreckas":
			return _gun_crazy_score(target_unit_id, ctx)
		"goaded-into-action-da-big-hunt":
			return _goaded_score(target_unit_id)
	return 0.0


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Bodyguard (head) id of an Attached unit — the id shots are declared against.
static func _head_id(unit_id: String) -> String:
	if unit_id == "":
		return ""
	var group = Common.attached_group_ids(unit_id)
	return str(group[0]) if not group.is_empty() else unit_id

## True when `unit_id` (or another component of its Attached unit) is in ids.
static func _group_in(unit_id: String, ids) -> bool:
	if typeof(ids) != TYPE_ARRAY:
		return false
	for gid in Common.attached_group_ids(unit_id):
		if gid in ids:
			return true
	return false

static func _alive_count(u: Dictionary) -> int:
	var n := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			n += 1
	return n


# ---------------------------------------------------------------------------
# HULKING BRUTES (Bully Boyz, 1 CP (+1 upgrade), opponent's Shooting phase)
# WHEN: when an enemy unit targets a friendly MEGANOBZ/NOBZ unit.
# TARGET: That MEGANOBZ/NOBZ unit.
# EFFECT: Ranged attacks that target your unit with a S greater than your
#   unit's T have -1 to wound rolls. +1CP Or: Ranged attacks that target your
#   unit have -1 to wound rolls. (until the end of the phase)
# SPEEDIEST FREEKS (Kult of Speed, 1 CP, opponent's Shooting phase)
# WHEN: when an enemy unit targets a friendly SPEED FREEKS unit.
# TARGET: That SPEED FREEKS unit.
# EFFECT: Ranged attacks that target your unit fail on an unmodified hit roll
#   of 1-3. (until the end of the phase)
# ---------------------------------------------------------------------------

static func _targeted_unit_entries(strat: Dictionary, player: int, ctx: Dictionary, with_upgrade: bool) -> Array:
	var out: Array = []
	for tid in ctx.get("target_unit_ids", []):
		var uid := str(tid)
		if not validate(strat, player, uid, ctx).ok:
			continue
		var extra := {}
		if with_upgrade:
			extra["variants"] = [{"id": HULKING_BRUTES_UPGRADE,
				"label": "+1CP: -1 to wound vs ALL ranged attacks",
				"cp_cost": int(strat.get("cp_cost", 1)) + 1}]
		out.append(Common.target_entry(uid, extra))
	return out

static func _targeted_validate(sname: String, keywords: Array, kw_text: String, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "%s needs a target unit" % sname}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "%s must target a unit from your army" % sname}
	if not Common.has_any_keyword(u, keywords):
		return {"ok": false, "reason": "%s can only target a %s unit" % [sname, kw_text]}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "%s: that unit is not on the battlefield" % sname}
	if ctx.has("target_unit_ids") and not _group_in(target_unit_id, ctx.get("target_unit_ids", [])):
		return {"ok": false, "reason": "%s must target the unit the enemy unit targeted" % sname}
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------------------
# GROT SHIELDS (Runt Swarm, 1 CP, opponent's Shooting phase)
# WHEN: when an enemy unit targets a friendly ORKS INFANTRY unit (excluding
#   GRETCHIN units).
# TARGET: One friendly GRETCHIN unit within 3" of that ORKS INFANTRY unit.
# EFFECT: When a hit roll for that enemy unit's ranged attacks that target
#   that ORKS unit results in a hit, if a model in your GRETCHIN unit is on the
#   battlefield, end the attack sequence for that attack and your GRETCHIN unit
#   suffers 1 mortal wound. (until the end of the phase)
# The stratagem TARGETS the Gretchin unit (15.01, battle-shock). The shielded
# ORKS INFANTRY unit is context: ctx.secondary_id when the player picked one
# (several targeted Ork units within 3" — secondary pick), else the only one.
# ---------------------------------------------------------------------------

static func _is_shieldable(u: Dictionary, player: int) -> bool:
	return not u.is_empty() and int(u.get("owner", 0)) == player \
		and Common.has_keyword(u, "ORKS") and Common.has_keyword(u, "INFANTRY") \
		and not Common.has_keyword(u, "GRETCHIN") and Common.is_on_battlefield(u)

## The targeted ORKS INFANTRY (non-GRETCHIN) units within 3" of the Gretchin unit.
static func _grot_shields_candidates(player: int, gretchin_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	for tid in ctx.get("target_unit_ids", []):
		var pid := str(tid)
		if pid == gretchin_id or pid in out:
			continue
		if not _is_shieldable(Common.unit(pid), player):
			continue
		if _attached_within(gretchin_id, pid, GROT_SHIELDS_RANGE_INCHES):
			out.append(pid)
	return out

## Group-aware "within N inches": every component of either Attached unit
## counts (19.03 — an attached Warboss is part of "that ORKS INFANTRY unit",
## an attached Runtherd part of the GRETCHIN unit; r3:F3). Same measure as
## OrkCodexMovement._attached_within (groups do not preload each other).
static func _attached_within(a_id: String, b_id: String, inches: float) -> bool:
	for ga in Common.attached_group_ids(a_id):
		for gb in Common.attached_group_ids(b_id):
			if Common.within_inches(str(ga), str(gb), inches):
				return true
	return false

static func _grot_shields_targets(player: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var units = Common.state().get("units", {})
	for gid in units:
		var g = units[gid]
		if int(g.get("owner", 0)) != player or not Common.has_keyword(g, "GRETCHIN") or not Common.is_on_battlefield(g):
			continue
		var options := _grot_shields_candidates(player, str(gid), ctx)
		if options.is_empty():
			continue
		var extra := {}
		if options.size() > 1:
			var opts: Array = []
			for pid in options:
				opts.append({"id": pid, "label": Common.unit_name(pid)})
			extra["secondary"] = {"kind": "unit", "prompt": "GROT SHIELDS: which ORKS INFANTRY unit do the Gretchin shield?", "options": opts}
		else:
			extra["label"] = "%s (shield %s)" % [Common.unit_name(str(gid)), Common.unit_name(str(options[0]))]
		out.append(Common.target_entry(str(gid), extra))
	return out

## The shielded unit: the player's pick (ctx.secondary_id — the dialog asks
## whenever more than one targeted unit qualifies), else the only candidate,
## else (a caller that sent no pick, e.g. the reactive AI) the most valuable one.
static func _grot_shields_protected_id(player: int, gretchin_id: String, ctx: Dictionary) -> String:
	var sec := str(ctx.get("secondary_id", ""))
	if sec != "":
		return sec
	var options := _grot_shields_candidates(player, gretchin_id, ctx)
	var best := ""
	var best_pts := -1.0
	for pid in options:
		if _unit_value(str(pid)) > best_pts:
			best_pts = _unit_value(str(pid))
			best = str(pid)
	return best

static func _grot_shields_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = Common.unit(target_unit_id)
	if g.is_empty():
		return {"ok": false, "reason": "GROT SHIELDS needs a GRETCHIN unit"}
	if int(g.get("owner", 0)) != player:
		return {"ok": false, "reason": "GROT SHIELDS must target a unit from your army"}
	if not Common.has_keyword(g, "GRETCHIN"):
		return {"ok": false, "reason": "GROT SHIELDS must target a GRETCHIN unit"}
	if not Common.is_on_battlefield(g):
		return {"ok": false, "reason": "GROT SHIELDS: that GRETCHIN unit is not on the battlefield"}
	if not ctx.has("target_unit_ids"):
		return {"ok": false, "reason": "GROT SHIELDS is used when an enemy unit targets a friendly ORKS INFANTRY unit"}
	var options := _grot_shields_candidates(player, target_unit_id, ctx)
	if options.is_empty():
		return {"ok": false, "reason": "GROT SHIELDS: no targeted ORKS INFANTRY unit (excluding GRETCHIN) within 3\" of that GRETCHIN unit"}
	var protected_id := _grot_shields_protected_id(player, target_unit_id, ctx)
	if not protected_id in options:
		return {"ok": false, "reason": "GROT SHIELDS: %s is not a targeted ORKS INFANTRY unit within 3\" of the Gretchin" % protected_id}
	return {"ok": true, "reason": ""}

static func _grot_shields_apply(gretchin_id: String, ctx: Dictionary) -> Array:
	var player := int(Common.unit(gretchin_id).get("owner", 0))
	var protected_id := _grot_shields_protected_id(player, gretchin_id, ctx)
	var attacker := str(ctx.get("attacker_unit_id", ""))
	var attacker_ids: Array = Common.attached_group_ids(attacker) if attacker != "" else []
	var shield := {"gretchin_unit_id": gretchin_id, "attacker_unit_ids": attacker_ids, "player": player}
	var diffs: Array = Common.set_flag_diffs(Common.attached_group_ids(protected_id), FLAG_GROT_SHIELDS, shield)
	diffs.append_array(Common.set_flag_diffs([gretchin_id], FLAG_GROT_SHIELDS_SOURCE, protected_id))
	Common.log_info("OrkCodexShootingReactive: GROT SHIELDS — %s shields %s from %s's ranged attacks this phase" % [gretchin_id, protected_id, str(attacker_ids)])
	return diffs


# ---------------------------------------------------------------------------
# GRAB IT (Wreckas, 1 CP, your Shooting phase)
# WHEN: when a friendly unengaged BREAKA BOYZ/FLASH GITZ/TANKBUSTAS unit has shot.
# TARGET: That BREAKA BOYZ/FLASH GITZ/TANKBUSTAS unit.
# EFFECT: Your unit can make a normal move of up to 6", and must end that move
#   within range of an objective. Your unit is not eligible to declare a charge
#   until the end of the turn.
# Ruling: offered only when an objective is reachable (some model's base is
# within 6" of being within range of an objective), since a move that cannot
# end within range of an objective cannot be made. "Within range" is the
# engine's own terrain-aware predicate (MissionManager.model_in_objective_range,
# the one ReactiveMove11e.validate judges the move with): a terrain-hosted
# objective (14.01/14.02) is in range only while a base overlaps its hosting
# area, open ground within 3" of the marker (r4:WS-1).
# ---------------------------------------------------------------------------

static func _objectives() -> Array:
	return Common.state().get("board", {}).get("objectives", [])

## Smallest distance (inches) any alive model of the unit (and its attached
## characters) still has to cover to be within range of an objective (0 =
## already within range) — MissionManager.model_gap_to_objective_range_px.
static func objective_range_gap_inches(unit_id: String) -> float:
	var mm = Common.autoload("MissionManager")
	if mm == null or not mm.has_method("model_gap_to_objective_range_px"):
		return INF
	var best := INF
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			for obj in _objectives():
				best = minf(best, float(mm.model_gap_to_objective_range_px(m, obj)) / Common.PX_PER_INCH)
	return best

static func _grab_it_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "GRAB IT needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "GRAB IT must target a unit from your army"}
	if not Common.has_any_keyword(u, GRAB_IT_KEYWORDS):
		return {"ok": false, "reason": "GRAB IT can only target a BREAKA BOYZ/FLASH GITZ/TANKBUSTAS unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "GRAB IT: that unit is not on the battlefield"}
	var shooter := str(ctx.get("unit_id", ""))
	if shooter != "" and _head_id(shooter) != _head_id(target_unit_id):
		return {"ok": false, "reason": "GRAB IT must target the unit that has just shot"}
	if Common.is_engaged(target_unit_id):
		return {"ok": false, "reason": "GRAB IT: the unit must be unengaged"}
	if objective_range_gap_inches(target_unit_id) > GRAB_IT_MOVE_INCHES + 0.001:
		return {"ok": false, "reason": "GRAB IT: no objective can be reached with a 6\" move"}
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------------------
# GUN-CRAZY SHOW-OFFS (Wreckas, 1 CP, opponent's Shooting phase)
# WHEN: when an enemy unit has shot.
# TARGET: One friendly FLASH GITZ/TANKBUSTAS unit hit by those attacks.
# EFFECT: Your unit shoots using normal shooting, but while doing so your unit
#   can only target that enemy unit.
# Normal shooting (10.04): eligible if unengaged and did not advance this turn
# (the opponent's turn — an Ork unit cannot have advanced in it). Ruling: only
# offered when at least one of the unit's ranged weapons can target that enemy
# unit (in range and visible) — otherwise the unit would shoot at nothing.
# GOADED INTO ACTION (Da Big Hunt, 1 CP, opponent's Shooting phase)
# WHEN: when an enemy unit has shot.
# TARGET: One friendly unengaged BEAST SNAGGA unit that lost a wound as a
#   result of those attacks.
# EFFECT: Your unit can make a surge move of up to D6". If your unit is riled
#   up, it can re-roll that D6.
# ---------------------------------------------------------------------------

static func _post_shot_entries(strat: Dictionary, player: int, ctx: Dictionary, candidate_ids) -> Array:
	var out: Array = []
	var seen := {}
	if typeof(candidate_ids) != TYPE_ARRAY:
		return out
	for cid in candidate_ids:
		var uid := _head_id(str(cid))
		if uid == "" or seen.has(uid):
			continue
		seen[uid] = true
		if validate(strat, player, uid, ctx).ok:
			out.append(Common.target_entry(uid))
	return out

static func _gun_crazy_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS must target a unit from your army"}
	if not Common.has_any_keyword(u, GUN_CRAZY_KEYWORDS):
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS can only target a FLASH GITZ/TANKBUSTAS unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS: that unit is not on the battlefield"}
	if not _group_in(target_unit_id, ctx.get("hit_unit_ids", [])):
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS: that unit was not hit by the enemy unit's attacks"}
	var attacker := _head_id(str(ctx.get("attacker_unit_id", "")))
	var a = Common.unit(attacker)
	if a.is_empty() or not Common.is_on_battlefield(a) or int(a.get("owner", 0)) == player:
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS: the enemy unit that shot is no longer on the battlefield"}
	if Common.is_engaged(target_unit_id):
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS: normal shooting needs an unengaged unit"}
	if gun_crazy_weapons_in_range(target_unit_id, attacker).is_empty():
		return {"ok": false, "reason": "GUN-CRAZY SHOW-OFFS: no ranged weapon of that unit can target %s" % Common.unit_name(attacker)}
	return {"ok": true, "reason": ""}

## Ranged weapon ids of `shooter_id` that can target `target_id` right now
## (range + visibility, the engine's own target eligibility).
static func gun_crazy_weapons_in_range(shooter_id: String, target_id: String) -> Array:
	var re = Common.rules()
	if re == null or not re.has_method("get_eligible_targets"):
		return []
	var elig: Dictionary = re.get_eligible_targets(shooter_id, Common.state())
	return elig.get(target_id, {}).get("weapons_in_range", [])

static func _goaded_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "GOADED INTO ACTION needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "GOADED INTO ACTION must target a unit from your army"}
	if not Common.has_keyword(u, "BEAST SNAGGA"):
		return {"ok": false, "reason": "GOADED INTO ACTION can only target a BEAST SNAGGA unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "GOADED INTO ACTION: that unit is not on the battlefield"}
	if not _group_in(target_unit_id, ctx.get("wounded_unit_ids", [])):
		return {"ok": false, "reason": "GOADED INTO ACTION: that unit did not lose a wound to the enemy unit's attacks"}
	if Common.is_engaged(target_unit_id):
		return {"ok": false, "reason": "GOADED INTO ACTION: the unit must be unengaged"}
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------------------
# AI scoring (AIDecisionMaker.decide_window_stratagem / evaluate_reactive_stratagem)
# ---------------------------------------------------------------------------

static func _unit_value(unit_id: String) -> float:
	var u = Common.unit(unit_id)
	return float(Common.points(u)) if not u.is_empty() else 0.0

## Ranged weapon strengths of the attacking unit (meta.weapons).
static func _attacker_ranged_strengths(attacker_id: String) -> Array:
	var out: Array = []
	if attacker_id == "":
		return out
	for gid in Common.attached_group_ids(attacker_id):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() != "ranged":
				continue
			var s = str(w.get("strength", "0"))
			out.append(int(s) if s.is_valid_int() else 0)
	return out

static func _hulking_brutes_score(unit_id: String, ctx: Dictionary) -> float:
	var u = Common.unit(unit_id)
	if u.is_empty():
		return 0.0
	var t := int(float(str(u.get("meta", {}).get("stats", {}).get("toughness", 4))))
	var strengths := _attacker_ranged_strengths(str(ctx.get("attacker_unit_id", "")))
	if strengths.is_empty():
		return 0.0
	var over := 0
	for s in strengths:
		if int(s) > t:
			over += 1
	if over == 0:
		return 0.0
	return (1.0 + _unit_value(unit_id) / 100.0) * float(over) / float(strengths.size()) * 1.5

static func _speediest_freeks_score(unit_id: String, ctx: Dictionary) -> float:
	if _attacker_ranged_strengths(str(ctx.get("attacker_unit_id", ""))).is_empty():
		return 0.0
	# r5:F8: "unmodified hit rolls of 1-3 fail" only costs the attacker hits it
	# would otherwise score — rolls of 2-3 at BS 2+, 3 at BS 3+, nothing at
	# BS 4+ or worse, nothing for [TORRENT] (no hit roll). Scale by the share
	# of the attacker's hits it removes (BS 3+ = the baseline 1/4).
	var lost := _speediest_freeks_lost_hit_share(str(ctx.get("attacker_unit_id", "")))
	if lost <= 0.0:
		return 0.0
	return (1.0 + _unit_value(unit_id) / 80.0) * minf(1.5, lost / 0.25)

## Weighted (by attacks) share of the attacker's expected ranged hits that
## SPEEDIEST FREEKS turns into misses: per weapon, P(unmodified roll in
## [BS..3]) / P(roll >= BS); torrent and BS 4+ weapons lose nothing.
static func _speediest_freeks_lost_hit_share(attacker_id: String) -> float:
	var re = Common.rules()
	if re == null or attacker_id == "":
		return 0.0
	var board := Common.state()
	var total_attacks := 0.0
	var lost_weighted := 0.0
	for gid in Common.attached_group_ids(attacker_id):
		var uw: Dictionary = re.get_unit_weapons(str(gid), board) if re.has_method("get_unit_weapons") else {}
		for mid in uw:
			for wid in uw[mid]:
				var prof = re.get_weapon_profile(str(wid), board)
				if prof.is_empty() or str(prof.get("type", "Ranged")).to_lower() == "melee":
					continue
				var attacks := _avg_value(prof.get("attacks_raw", prof.get("attacks", 1)))
				total_attacks += attacks
				if re.has_method("is_torrent_weapon") and re.is_torrent_weapon(str(wid), board):
					continue
				var bs := clampi(int(prof.get("bs", 4)), 2, 7)
				if bs > 3:
					continue
				var p_hit := float(7 - bs) / 6.0
				var p_lost := float(4 - bs) / 6.0  # unmodified BS..3
				lost_weighted += attacks * (p_lost / p_hit)
	if total_attacks <= 0.0:
		return 0.0
	return lost_weighted / total_attacks

static func _grot_shields_score(gretchin_id: String, ctx: Dictionary) -> float:
	var g = Common.unit(gretchin_id)
	var player := int(g.get("owner", 0))
	var best := 0.0
	for pid in _grot_shields_candidates(player, gretchin_id, ctx):
		best = maxf(best, _unit_value(pid))
	if best <= 0.0:
		return 0.0
	return (1.0 + best / 80.0) * minf(1.0, float(_alive_count(g)) / 5.0)

static func _grab_it_score(unit_id: String) -> float:
	var gap := objective_range_gap_inches(unit_id)
	if gap <= 0.0 or gap > GRAB_IT_MOVE_INCHES:
		return 0.0  # already within range (no gain) or unreachable
	# The cost (r4:WS-7): "not eligible to declare a charge until the end of
	# the turn" — a melee-minded unit with an enemy in charge range keeps its
	# charge instead.
	if _grab_it_forfeits_charge(unit_id):
		Common.log_info("OrkCodexShootingReactive: GRAB IT AI score 0 for %s — melee unit with an enemy within %.0f\" would lose its charge" % [unit_id, GRAB_IT_CHARGE_THREAT_INCHES])
		return 0.0
	# The AI's move is the auto-placement: only pay the CP when it can
	# actually end within range of an objective (r4:WS-1).
	if not _grab_it_auto_move_reaches(unit_id):
		Common.log_info("OrkCodexShootingReactive: GRAB IT AI score 0 for %s — the auto-move finds no legal placement within range of an objective" % unit_id)
		return 0.0
	return 2.5

const GRAB_IT_CHARGE_THREAT_INCHES := 12.0

## True when ReactiveMove11e (the AI decider's auto-move) finds a 6" normal
## move that ends within range of an objective. Loaded late (not preloaded) so
## the dispatcher's preload chain stays free of the rules libraries.
static func _grab_it_auto_move_reaches(unit_id: String) -> bool:
	var lib = load("res://scripts/rules/ReactiveMove11e.gd")
	if lib == null:
		return true
	var board := Common.state()
	var origin: Dictionary = lib.current_positions(unit_id, board)
	if origin.is_empty():
		return false
	var placed: Dictionary = lib.solve("normal", unit_id, origin, GRAB_IT_MOVE_INCHES,
		{"end_condition": "within_objective_range"}, board)
	return not placed.is_empty()

## Average of a dice/number characteristic ("3", "D6", "D3+2", "2D6").
static func _avg_value(v) -> float:
	var s := str(v).to_upper().replace(" ", "")
	if s.is_valid_float():
		return float(s)
	var plus := 0.0
	if "+" in s:
		var p := s.split("+")
		s = p[0]
		plus = float(p[1]) if p[1].is_valid_float() else 0.0
	var d := s.find("D")
	if d < 0:
		return plus
	var n := 1.0 if d == 0 else (float(s.substr(0, d)) if s.substr(0, d).is_valid_float() else 1.0)
	var faces := float(s.substr(d + 1)) if s.substr(d + 1).is_valid_float() else 6.0
	return n * (faces + 1.0) / 2.0 + plus

## Crude output (attacks x damage) of the unit's best melee vs best ranged
## weapon per alive model; true when an enemy unit on the battlefield is within
## a plausible charge distance AND the unit's melee output beats its shooting.
static func _grab_it_forfeits_charge(unit_id: String) -> bool:
	var u = Common.unit(unit_id)
	if u.is_empty():
		return false
	var owner := int(u.get("owner", 0))
	var near := false
	for eid in Common.state().get("units", {}):
		var e = Common.unit(str(eid))
		if int(e.get("owner", 0)) == owner or not Common.is_on_battlefield(e):
			continue
		if Common.unit_distance_inches(unit_id, str(eid)) <= GRAB_IT_CHARGE_THREAT_INCHES:
			near = true
			break
	if not near:
		return false
	var re = Common.rules()
	if re == null:
		return false
	var board := Common.state()
	var by_name := {}
	for w in u.get("meta", {}).get("weapons", []):
		by_name[str(w.get("name", ""))] = w
	var ranged: Dictionary = re.get_unit_weapons(unit_id, board) if re.has_method("get_unit_weapons") else {}
	var melee: Dictionary = re.get_unit_melee_weapons(unit_id, board) if re.has_method("get_unit_melee_weapons") else {}
	var ranged_out := 0.0
	var melee_out := 0.0
	for mid in ranged:
		var best := 0.0
		for wid in ranged[mid]:
			var prof = re.get_weapon_profile(str(wid), board)
			best = maxf(best, _avg_value(prof.get("attacks_raw", prof.get("attacks", 1))) * _avg_value(prof.get("damage_raw", prof.get("damage", 1))))
		ranged_out += best
	for mid in melee:
		var best_m := 0.0
		for wname in melee[mid]:
			var w = by_name.get(str(wname), {})
			best_m = maxf(best_m, _avg_value(w.get("attacks", 1)) * _avg_value(w.get("damage", 1)))
		melee_out += best_m
	return melee_out > ranged_out

static func _gun_crazy_score(unit_id: String, ctx: Dictionary) -> float:
	var attacker := _head_id(str(ctx.get("attacker_unit_id", "")))
	var n := gun_crazy_weapons_in_range(unit_id, attacker).size()
	return 0.0 if n == 0 else 2.0 + minf(1.0, 0.25 * float(n))

static func _goaded_score(unit_id: String) -> float:
	var u = Common.unit(unit_id)
	if u.is_empty():
		return 0.0
	var owner := int(u.get("owner", 0))
	var best := INF
	for eid in Common.state().get("units", {}):
		var e = Common.unit(str(eid))
		if int(e.get("owner", 0)) == owner or not Common.is_on_battlefield(e):
			continue
		best = minf(best, Common.unit_distance_inches(unit_id, str(eid)))
	# A melee unit that can close to engagement on an average roll.
	return 2.5 if best <= 6.0 and Common.has_melee_weapons(unit_id) else 0.0
