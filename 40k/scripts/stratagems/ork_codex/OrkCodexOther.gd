extends RefCounted

## OrkCodexOther — Codex: Orks (11e) stratagems of the OTHER group:
## Command / Charge / any-phase stratagems.
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
## Windows / hooks used by this group (BasePhase framework):
##   battle_shock_step_start  CommandPhase._open_battle_shock_step_window (phase start)
##   unit_battle_shocked      BasePhase event detection (every place a unit becomes battle-shocked)
##   unit_ended_charge_move   ChargePhase._process_apply_charge_move
##   unit_destroyed           BasePhase event detection; Deadly Demise held until it closes
##   enemy_unit_has_attacked  BasePhase event detection (attacker's attacks over)

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

## Every csv_id owned by this group (registry). Do not move ids between groups.
const IDS: Array = [
	"mob-mentality-green-tide",
	"breakin-heads-war-horde",
	"impending-krunch-blitz-brigade",
	"flyin-headbutt-flyboyz",
	"infested-war-zone-runt-swarm",
]

## csv_ids whose handler is complete and validated.
const IMPLEMENTED: Dictionary = {
	"mob-mentality-green-tide": true,
	"breakin-heads-war-horde": true,
	"impending-krunch-blitz-brigade": true,
	"flyin-headbutt-flyboyz": true,
	"infested-war-zone-runt-swarm": true,
}

const AI_KIND: Dictionary = {
	"mob-mentality-green-tide": "utility",
	"breakin-heads-war-horde": "utility",
	"impending-krunch-blitz-brigade": "utility",
	"flyin-headbutt-flyboyz": "utility",
	"infested-war-zone-runt-swarm": "utility",
}

# Flags written by this group's handlers (never effect_-prefixed: the
# Shooting phase wipes every effect_* flag when it ends).
## MOB MENTALITY: battle-shock rolls automatically successful (read by
## CommandPhase._handle_battle_shock_test and FactionAbilityManager.force_battle_shock_test).
const FLAG_MOB_MENTALITY := "ork11e_mob_mentality"
## On the 13+ model unit: the unit it selected (for expiry).
const FLAG_MOB_MENTALITY_SELECTED := "ork11e_mob_mentality_selected"
## FLYIN' HEADBUTT: "Your unit does not have the Deadly Demise ability" (read by
## UnitAbilityManager.has_deadly_demise).
const FLAG_NO_DEADLY_DEMISE := "ork11e_no_deadly_demise"
## Result records (log / UI / tests): what the effect rolled and did.
const FLAG_FLYIN_HEADBUTT := "ork11e_flyin_headbutt"
const FLAG_BREAKIN_HEADS := "ork11e_breakin_heads"
const FLAG_IMPENDING_KRUNCH := "ork11e_impending_krunch"
const FLAG_INFESTED_WAR_ZONE := "ork11e_infested_war_zone"

const MOB_MENTALITY_MIN_MODELS := 13
const MOB_MENTALITY_RANGE := 12.0
const FLYIN_HEADBUTT_RANGE := 12.0
const FLYIN_HEADBUTT_DICE := 8


static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	match str(strat.get("csv_id", "")):
		"mob-mentality-green-tide":
			return _mob_mentality_targets(player, window_id, ctx)
		"breakin-heads-war-horde":
			return _breakin_heads_targets(player, window_id, ctx)
		"impending-krunch-blitz-brigade":
			return _impending_krunch_targets(player, window_id, ctx)
		"flyin-headbutt-flyboyz":
			return _flyin_headbutt_targets(player, window_id, ctx)
		"infested-war-zone-runt-swarm":
			return _infested_war_zone_targets(player, window_id, ctx)
	return []


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match str(strat.get("csv_id", "")):
		"mob-mentality-green-tide":
			return _mob_mentality_validate(player, target_unit_id, ctx)
		"breakin-heads-war-horde":
			return _breakin_heads_validate(player, target_unit_id, ctx)
		"impending-krunch-blitz-brigade":
			return _impending_krunch_validate(player, target_unit_id, ctx)
		"flyin-headbutt-flyboyz":
			return _flyin_headbutt_validate(player, target_unit_id, ctx)
		"infested-war-zone-runt-swarm":
			return _infested_war_zone_validate(player, target_unit_id, ctx)
	return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	match str(strat.get("csv_id", "")):
		"mob-mentality-green-tide":
			return _mob_mentality_apply(target_unit_id, ctx)
		"breakin-heads-war-horde":
			return _breakin_heads_apply(target_unit_id)
		"impending-krunch-blitz-brigade":
			return _impending_krunch_apply(target_unit_id)
		"flyin-headbutt-flyboyz":
			return _flyin_headbutt_apply(target_unit_id, ctx)
		"infested-war-zone-runt-swarm":
			return _infested_war_zone_apply(target_unit_id)
	Common.log_error("OrkCodexOther: apply() called for unimplemented %s" % strat.get("csv_id", "?"))
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	match str(strat.get("csv_id", "")):
		"mob-mentality-green-tide":
			var selected := str(Common.unit(unit_id).get("flags", {}).get(FLAG_MOB_MENTALITY_SELECTED, ""))
			if selected != "":
				Common.erase_flags(Common.attached_group_ids(selected), [FLAG_MOB_MENTALITY])
			Common.erase_flags(Common.attached_group_ids(unit_id), [FLAG_MOB_MENTALITY_SELECTED])
			Common.log_info("OrkCodexOther: MOB MENTALITY expired — %s's battle-shock rolls are no longer automatically successful" % (selected if selected != "" else unit_id))
		"breakin-heads-war-horde":
			Common.erase_flags(Common.attached_group_ids(unit_id), [FLAG_BREAKIN_HEADS])
		"impending-krunch-blitz-brigade":
			Common.erase_flags([unit_id], [FLAG_IMPENDING_KRUNCH])
		"flyin-headbutt-flyboyz":
			Common.erase_flags([unit_id], [FLAG_NO_DEADLY_DEMISE, FLAG_FLYIN_HEADBUTT])
		"infested-war-zone-runt-swarm":
			Common.erase_flags([unit_id], [FLAG_INFESTED_WAR_ZONE])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


## CP cost of a variant offered in a target entry's `variants` (e.g. HULKING
## BRUTES' +1 CP upgrade). -1 = unknown variant (the base cp_cost applies).
static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


## BREAKIN' HEADS: "You can target that unit with this stratagem even though it
## is battle-shocked." FLYIN' HEADBUTT / INFESTED WAR ZONE target a unit that
## was just destroyed: a destroyed unit has no models left that could carry
## the battle-shocked descriptor (core 02.03 descriptors), so a flag left over
## from before its destruction must not block them.
static func allows_battle_shocked_target(strat: Dictionary, _ctx: Dictionary) -> bool:
	return str(strat.get("csv_id", "")) in ["breakin-heads-war-horde", "flyin-headbutt-flyboyz", "infested-war-zone-runt-swarm"]


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	match str(strat.get("csv_id", "")):
		"mob-mentality-green-tide":
			return _mob_mentality_ai_score(player, target_unit_id, ctx)
		"breakin-heads-war-horde":
			return _breakin_heads_ai_score(target_unit_id)
		"impending-krunch-blitz-brigade":
			return _impending_krunch_ai_score(target_unit_id)
		"flyin-headbutt-flyboyz":
			return _flyin_headbutt_ai_score(player, target_unit_id)
		"infested-war-zone-runt-swarm":
			return _infested_war_zone_ai_score(player, target_unit_id)
	return 0.0


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Alive models of a unit plus every component of its Attached unit (19.03:
## an Attached unit is one unit for "unit of N+ models").
static func _group_model_count(unit_id: String) -> int:
	var n := 0
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(gid).get("models", []):
			if m.get("alive", true):
				n += 1
	return n

static func _group_has_keywords(unit_id: String, keywords: Array) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		var u = Common.unit(gid)
		var ok := true
		for kw in keywords:
			if not Common.has_keyword(u, str(kw)):
				ok = false
				break
		if ok:
			return true
	return false

## The unit id an Attached unit resolves to (its bodyguard) — the id the
## engine tests battle-shock on and the one a window ctx carries.
static func _head_id(unit_id: String) -> String:
	var re = Common.rules()
	if re and re.has_method("attached_unit_target_id"):
		return str(re.attached_unit_target_id(unit_id, Common.state()))
	return unit_id

static func _same_unit(a: String, b: String) -> bool:
	if a == "" or b == "":
		return false
	return a == b or _head_id(a) == _head_id(b) or a in Common.attached_group_ids(b)

static func _group_distance(a_id: String, b_id: String) -> float:
	var best := INF
	for ga in Common.attached_group_ids(a_id):
		for gb in Common.attached_group_ids(b_id):
			best = minf(best, Common.unit_distance_inches(ga, gb))
	return best

## True when any component of a_id can see any component of b_id (the
## engine's 11e unit-to-unit sight line).
static func _group_visible(a_id: String, b_id: String) -> bool:
	if _same_unit(a_id, b_id):
		return true
	var re = Common.rules()
	if re == null or not re.has_method("unit_sight_line"):
		return true
	for ga in Common.attached_group_ids(a_id):
		for gb in Common.attached_group_ids(b_id):
			if bool(re.unit_sight_line(ga, gb, Common.state(), false).get("has_los", false)):
				return true
	return false

static func _was_on_battlefield(u: Dictionary) -> bool:
	if u.is_empty():
		return false
	var status = int(u.get("status", Common.GameStateData.UnitStatus.DEPLOYED))
	if status == Common.GameStateData.UnitStatus.IN_RESERVES or status == Common.GameStateData.UnitStatus.UNDEPLOYED:
		return false
	return u.get("embarked_in", null) == null or str(u.get("embarked_in", "")) == ""

static func _is_destroyed(u: Dictionary) -> bool:
	return not u.is_empty() and not Common.is_alive(u)

static func _rng():
	var re = Common.rules()
	return re.make_rng() if re else null

## D3 = one D6 halved, rounding up (core 01.05).
static func _roll_d3(rng) -> int:
	return int(ceil(float(rng.roll_d6(1)[0]) / 2.0))

## Mortal wounds to a unit (06.02). An Attached unit takes them on its
## bodyguard first; wounds that exceed what a component can lose spill to the
## next component (its characters). Feel No Pain is rolled by the engine
## (RulesEngine.apply_mortal_wounds) for the first component.
static func _mortal_wounds_to_unit(unit_id: String, mortal_wounds: int, rng) -> Dictionary:
	var out := {"diffs": [], "casualties": 0, "wounds_applied": 0}
	var re = Common.rules()
	var gs = Common.game_state()
	if re == null or gs == null or mortal_wounds <= 0:
		return out
	var remaining := mortal_wounds
	var first := true
	for gid in Common.attached_group_ids(_head_id(unit_id)):
		if remaining <= 0:
			break
		var u = Common.unit(gid)
		if u.is_empty() or not Common.is_alive(u):
			continue
		var pool := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				pool += int(m.get("current_wounds", m.get("wounds", 1)))
		var res: Dictionary = re.apply_mortal_wounds(gid, remaining, gs.create_snapshot(), rng if first else null)
		first = false
		out.diffs.append_array(res.get("diffs", []))
		out.casualties += int(res.get("casualties", 0))
		var applied := int(res.get("wounds_applied", 0))
		out.wounds_applied += mini(applied, pool)
		remaining = maxi(0, applied - pool)
	return out

## Probability that 2D6 + modifier fails against Ld (roll < Ld fails).
static func _fail_probability(ld: int, modifier: int) -> float:
	var fails := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if a + b + modifier < ld:
				fails += 1
	return float(fails) / 36.0

## The engine's effective Leadership (best of an Attached unit's models) —
## CommandPhase's static helper, shared with every battle-shock roll.
static func _effective_leadership(unit_id: String) -> int:
	var cp = load("res://phases/CommandPhase.gd")
	if cp == null:
		return int(Common.unit(unit_id).get("meta", {}).get("stats", {}).get("leadership", 7))
	return int(cp._get_effective_leadership(unit_id))

## The engine's battle-shock immunity check (CommandPhase, static).
static func _battle_shock_immune(u: Dictionary) -> bool:
	var cp = load("res://phases/CommandPhase.gd")
	if cp == null:
		return false
	return bool(cp._has_battle_shock_immunity(u.get("meta", {}).get("keywords", []), u.get("meta", {}).get("abilities", [])))


# ---------------------------------------------------------------------------
# MOB MENTALITY (Green Tide, 1 CP, your Command phase)
# WHEN: Start of the Battle-shock step of your Command phase.
# TARGET: One friendly ORKS INFANTRY unit of 13+ models.
# EFFECT: Select one visible friendly ORKS unit within 12" of your unit. That
#         unit's battle-shock rolls are automatically successful.
#         (Duration: until the end of the phase.)
# Rulings: models of an Attached unit count towards the 13+ (19.03); the
# selected unit may be the target itself (the rule does not say "another");
# the window only lists — and is only offered for — units that must make a
# battle-shock roll in this step (selecting any other unit has no effect).
# ---------------------------------------------------------------------------

static func _mob_mentality_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "battle_shock_step_start":
		return []
	var needing: Array = ctx.get("units_needing_test", [])
	if needing.is_empty():
		return []
	var out: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or _head_id(uid) != uid:
			continue
		if not _mob_mentality_validate(player, uid, {}).ok:
			continue
		var options := _mob_mentality_options(uid, player, needing)
		if options.is_empty():
			continue
		out.append(Common.target_entry(uid, {"label": "%s (%d models)" % [Common.unit_name(uid), _group_model_count(uid)],
			"secondary": {"kind": "unit",
				"prompt": "MOB MENTALITY: select one visible friendly ORKS unit within 12\" — its battle-shock rolls are automatically successful",
				"options": options}}))
	return out

## Units the 13+ model unit can select, best first (most likely to fail).
static func _mob_mentality_options(target_id: String, player: int, needing: Array) -> Array:
	var scored: Array = []
	for nid in needing:
		var sid := str(nid)
		var check := _mob_mentality_selection_check(target_id, player, sid)
		if not check.ok:
			continue
		var ld := _effective_leadership(sid)
		var shocked := Common.is_battle_shocked(Common.unit(sid))
		var p := _fail_probability(ld, 0)
		scored.append({"id": sid, "p": p,
			"label": "%s — Ld %d, %s" % [Common.unit_name(sid), ld, "battle-shocked, must test" if shocked else "must test"]})
	scored.sort_custom(func(a, b): return a.p > b.p)
	var out: Array = []
	for s in scored:
		out.append({"id": s.id, "label": s.label})
	return out

static func _mob_mentality_selection_check(target_id: String, player: int, selected_id: String) -> Dictionary:
	var s = Common.unit(selected_id)
	if s.is_empty() or int(s.get("owner", 0)) != player:
		return {"ok": false, "reason": "MOB MENTALITY must select a friendly unit"}
	if not _group_has_keywords(selected_id, ["ORKS"]):
		return {"ok": false, "reason": "MOB MENTALITY must select an ORKS unit"}
	if not Common.is_on_battlefield(s):
		return {"ok": false, "reason": "MOB MENTALITY: the selected unit is not on the battlefield"}
	if _group_distance(target_id, selected_id) > MOB_MENTALITY_RANGE + 0.001:
		return {"ok": false, "reason": "MOB MENTALITY: the selected unit must be within 12\" of %s" % Common.unit_name(target_id)}
	if not _group_visible(target_id, selected_id):
		return {"ok": false, "reason": "MOB MENTALITY: the selected unit must be visible to %s" % Common.unit_name(target_id)}
	return {"ok": true, "reason": ""}

static func _mob_mentality_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "MOB MENTALITY needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "MOB MENTALITY must target a unit from your army"}
	if not _group_has_keywords(target_unit_id, ["ORKS", "INFANTRY"]):
		return {"ok": false, "reason": "MOB MENTALITY can only target an ORKS INFANTRY unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "MOB MENTALITY: that unit is not on the battlefield"}
	var models := _group_model_count(target_unit_id)
	if models < MOB_MENTALITY_MIN_MODELS:
		return {"ok": false, "reason": "MOB MENTALITY needs a unit of 13+ models (%s has %d)" % [Common.unit_name(target_unit_id), models]}
	var selected := str(ctx.get("secondary_id", ""))
	if selected != "":
		var check := _mob_mentality_selection_check(target_unit_id, player, selected)
		if not check.ok:
			return check
	return {"ok": true, "reason": ""}

static func _mob_mentality_apply(target_unit_id: String, ctx: Dictionary) -> Array:
	var selected := str(ctx.get("secondary_id", ""))
	if selected == "":
		Common.log_error("OrkCodexOther: MOB MENTALITY used without a selected unit (context.secondary_id) — no effect")
		return []
	var diffs: Array = []
	diffs.append_array(Common.set_flag_diffs(Common.attached_group_ids(selected), FLAG_MOB_MENTALITY, true))
	diffs.append_array(Common.set_flag_diffs([target_unit_id], FLAG_MOB_MENTALITY_SELECTED, selected))
	Common.log_info("OrkCodexOther: MOB MENTALITY — %s (%d models) selects %s: its battle-shock rolls are automatically successful until the end of the phase" % [
		Common.unit_name(target_unit_id), _group_model_count(target_unit_id), Common.unit_name(selected)])
	return diffs

static func _mob_mentality_ai_score(player: int, target_unit_id: String, ctx: Dictionary) -> float:
	var options := _mob_mentality_options(target_unit_id, player, ctx.get("units_needing_test", []))
	if options.is_empty():
		return 0.0
	var best := str(options[0].id)
	var p := _fail_probability(_effective_leadership(best), 0)
	return 1.0 + 5.0 * p


# ---------------------------------------------------------------------------
# BREAKIN' HEADS (War Horde, 1 CP, either player's turn, any phase)
# WHEN: Any phase, when a friendly attached ORKS INFANTRY unit becomes
#       battle-shocked.
# TARGET: That ORKS INFANTRY unit. You can target that unit with this
#         stratagem even though it is battle-shocked.
# EFFECT: Roll one D3: your unit suffers that many mortal wounds; your unit is
#         no longer battle-shocked.
# ---------------------------------------------------------------------------

static func _is_attached_unit(unit_id: String) -> bool:
	var head := _head_id(unit_id)
	if head != unit_id:
		return true
	for cid in Common.unit(head).get("attachment_data", {}).get("attached_characters", []):
		if Common.is_alive(Common.unit(str(cid))):
			return true
	return false

static func _breakin_heads_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "unit_battle_shocked":
		return []
	var uid := _head_id(str(ctx.get("unit_id", "")))
	if not _breakin_heads_validate(player, uid, ctx).ok:
		return []
	return [Common.target_entry(uid)]

static func _breakin_heads_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "BREAKIN' HEADS needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "BREAKIN' HEADS must target a unit from your army"}
	if not _is_attached_unit(target_unit_id):
		return {"ok": false, "reason": "BREAKIN' HEADS can only target an attached unit"}
	if not _group_has_keywords(target_unit_id, ["ORKS", "INFANTRY"]):
		return {"ok": false, "reason": "BREAKIN' HEADS can only target an ORKS INFANTRY unit"}
	if not Common.is_on_battlefield(Common.unit(_head_id(target_unit_id))):
		return {"ok": false, "reason": "BREAKIN' HEADS: that unit is not on the battlefield"}
	var shocked := false
	for gid in Common.attached_group_ids(target_unit_id):
		if Common.is_battle_shocked(Common.unit(gid)):
			shocked = true
	if not shocked:
		return {"ok": false, "reason": "BREAKIN' HEADS: that unit is not battle-shocked"}
	var event_unit := str(ctx.get("unit_id", ""))
	if event_unit != "" and not _same_unit(event_unit, target_unit_id):
		return {"ok": false, "reason": "BREAKIN' HEADS must target the unit that just became battle-shocked"}
	return {"ok": true, "reason": ""}

static func _breakin_heads_apply(target_unit_id: String) -> Array:
	var head := _head_id(target_unit_id)
	var rng = _rng()
	var d3 := _roll_d3(rng)
	var mw := _mortal_wounds_to_unit(head, d3, rng)
	var diffs: Array = []
	diffs.append_array(mw.diffs)
	# "Your unit is no longer battle-shocked" — every component of the unit.
	diffs.append_array(Common.set_flag_diffs(Common.attached_group_ids(head), "battle_shocked", false))
	diffs.append_array(Common.set_flag_diffs([head], FLAG_BREAKIN_HEADS, {"d3": d3, "casualties": int(mw.casualties)}))
	Common.log_info("OrkCodexOther: BREAKIN' HEADS — %s rolls D3 = %d: %d mortal wound(s) (%d model(s) destroyed) and is no longer battle-shocked" % [
		Common.unit_name(head), d3, d3, int(mw.casualties)])
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(int(Common.unit(head).get("owner", 0)),
			"BREAKIN' HEADS: %s suffers %d mortal wound(s) (D3) and is no longer battle-shocked" % [Common.unit_name(head), d3])
	return diffs

static func _breakin_heads_ai_score(target_unit_id: String) -> float:
	var head := _head_id(target_unit_id)
	var wounds := 0
	var oc := 0
	for gid in Common.attached_group_ids(head):
		var u = Common.unit(gid)
		var unit_oc := int(u.get("meta", {}).get("stats", {}).get("objective_control", 1))
		for m in u.get("models", []):
			if m.get("alive", true):
				wounds += int(m.get("current_wounds", m.get("wounds", 1)))
				oc += unit_oc
	# D3 mortal wounds must not wipe the unit; worth it while the unit's OC
	# (lost while battle-shocked) is meaningful.
	if wounds <= 3:
		return 0.0
	return 2.5 if oc >= 6 else 1.0


# ---------------------------------------------------------------------------
# IMPENDING KRUNCH (Blitz Brigade, 1 CP, your Charge phase)
# WHEN: Your Charge phase, when a friendly WAGON unit ends a charge move.
# TARGET: That WAGON unit.
# EFFECT: Each enemy unit engaged with your unit makes a battle-shock roll,
#         with -1 to that battle-shock roll.
# The rolls use the engine's out-of-Command-phase battle-shock roll
# (FactionAbilityManager.force_battle_shock_test, 2D6 vs effective Ld). A unit
# that fails becomes battle-shocked — which opens ITS owner's
# unit_battle_shocked window (BasePhase event windows, nested safely).
# ---------------------------------------------------------------------------

## Enemy units (Attached units resolved to their bodyguard) engaged with unit_id.
static func _engaged_enemy_units(unit_id: String) -> Array:
	var re = Common.rules()
	var u = Common.unit(unit_id)
	if re == null or u.is_empty():
		return []
	var owner := int(u.get("owner", 0))
	var out: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for eid in units:
		var e: Dictionary = units[eid]
		if int(e.get("owner", 0)) == owner or not Common.is_on_battlefield(e):
			continue
		if re.check_units_in_engagement_range(u, e, Common.state()):
			var head := _head_id(eid)
			if not head in out:
				out.append(head)
	return out

static func _impending_krunch_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "unit_ended_charge_move":
		return []
	var uid := str(ctx.get("unit_id", ""))
	if not _impending_krunch_validate(player, uid, ctx).ok:
		return []
	var engaged := _engaged_enemy_units(uid)
	if engaged.is_empty():
		return []
	return [Common.target_entry(uid, {"label": "%s (%d engaged enemy unit%s)" % [Common.unit_name(uid), engaged.size(), "" if engaged.size() == 1 else "s"]})]

static func _impending_krunch_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "IMPENDING KRUNCH needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "IMPENDING KRUNCH must target a unit from your army"}
	if not Common.has_keyword(u, "WAGON"):
		return {"ok": false, "reason": "IMPENDING KRUNCH can only target a WAGON unit"}
	if not Common.is_on_battlefield(u):
		return {"ok": false, "reason": "IMPENDING KRUNCH: that unit is not on the battlefield"}
	var moved := str(ctx.get("unit_id", ""))
	if moved != "" and moved != target_unit_id:
		return {"ok": false, "reason": "IMPENDING KRUNCH must target the WAGON unit that just ended a charge move"}
	return {"ok": true, "reason": ""}

static func _impending_krunch_apply(target_unit_id: String) -> Array:
	var fam = Common.autoload("FactionAbilityManager")
	var diffs: Array = []
	var results: Array = []
	for eid in _engaged_enemy_units(target_unit_id):
		var e = Common.unit(eid)
		if _battle_shock_immune(e):
			Common.log_info("OrkCodexOther: IMPENDING KRUNCH — %s is immune to battle-shock, no roll" % Common.unit_name(eid))
			results.append({"unit_id": eid, "immune": true})
			continue
		if fam == null or not fam.has_method("force_battle_shock_test"):
			Common.log_error("OrkCodexOther: IMPENDING KRUNCH — FactionAbilityManager.force_battle_shock_test unavailable")
			break
		var r: Dictionary = fam.force_battle_shock_test(eid, -1, "IMPENDING KRUNCH")
		diffs.append_array(r.get("diffs", []))
		results.append({"unit_id": eid, "dice": r.get("dice", []), "total": int(r.get("total", 0)),
			"leadership": int(r.get("leadership", 0)), "passed": bool(r.get("passed", true))})
		Common.log_info("OrkCodexOther: IMPENDING KRUNCH — %s battle-shock roll %s -1 = %d vs Ld %d: %s" % [
			Common.unit_name(eid), str(r.get("dice", [])), int(r.get("total", 0)), int(r.get("leadership", 0)),
			"passed" if r.get("passed", true) else "FAILED (battle-shocked)"])
	diffs.append_array(Common.set_flag_diffs([target_unit_id], FLAG_IMPENDING_KRUNCH, results))
	return diffs

static func _impending_krunch_ai_score(target_unit_id: String) -> float:
	var score := 0.0
	for eid in _engaged_enemy_units(target_unit_id):
		var e = Common.unit(eid)
		if Common.is_battle_shocked(e) or _battle_shock_immune(e):
			continue
		score += 5.0 * _fail_probability(_effective_leadership(eid), -1)
	return score


# ---------------------------------------------------------------------------
# FLYIN' HEADBUTT (Flyboyz, 1 CP, either player's turn, any phase)
# WHEN: Any phase, when a friendly ORKS AIRCRAFT unit is destroyed, before
#       rolling for any Deadly Demise.
# TARGET: That ORKS unit.
# EFFECT: Your unit does not have the Deadly Demise ability. Select one enemy
#         unit within 12" of your unit and roll eight D6: for each 4+, that
#         enemy unit suffers 1 mortal wound. Then remove your unit from the
#         battlefield.
# The unit_destroyed window opens before Deadly Demise is rolled (BasePhase
# holds the roll until the window closes). "Within 12" of your unit" is
# measured from the destroyed models (still on the battlefield until removed,
# core 05.04.04). Ruling: with no enemy unit within 12" the stratagem can still
# be used (it removes Deadly Demise) and no dice are rolled.
# ---------------------------------------------------------------------------

## Edge-to-edge distance from the destroyed unit's models (alive or not) to
## the closest alive model of enemy_id.
static func _wreck_distance(wreck_id: String, enemy_id: String) -> float:
	var meas = Common.autoload("Measurement")
	var best := INF
	for wm in Common.unit(wreck_id).get("models", []):
		if wm.get("position", null) == null:
			continue
		for gid in Common.attached_group_ids(enemy_id):
			for em in Common.unit(gid).get("models", []):
				if not em.get("alive", true) or em.get("position", null) == null:
					continue
				var d := INF
				if meas and meas.has_method("model_to_model_distance_inches"):
					d = float(meas.model_to_model_distance_inches(wm, em))
				else:
					d = Common._pos(wm).distance_to(Common._pos(em)) / Common.PX_PER_INCH
				best = minf(best, d)
	return best

static func _flyin_headbutt_options(wreck_id: String, player: int) -> Array:
	var scored: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for eid in units:
		var e: Dictionary = units[eid]
		if int(e.get("owner", 0)) == player or _head_id(eid) != eid or not Common.is_on_battlefield(e):
			continue
		var d := _wreck_distance(wreck_id, eid)
		if d > FLYIN_HEADBUTT_RANGE + 0.001:
			continue
		scored.append({"id": eid, "value": _flyin_headbutt_value(eid),
			"label": "%s (%.1f\")" % [Common.unit_name(eid), d]})
	scored.sort_custom(func(a, b): return a.value > b.value)
	var out: Array = []
	for s in scored:
		out.append({"id": s.id, "label": s.label})
	return out

## AI value of 4 expected mortal wounds on a unit: points of the models they kill.
static func _flyin_headbutt_value(enemy_id: String) -> float:
	var u = Common.unit(enemy_id)
	var alive := 0
	var total := 0
	var wpm := 1
	for m in u.get("models", []):
		total += 1
		if m.get("alive", true):
			alive += 1
			wpm = maxi(1, int(m.get("wounds", 1)))
	if alive == 0:
		return 0.0
	var killed := minf(float(alive), 4.0 / float(wpm))
	return killed * float(Common.points(u)) / float(maxi(1, total))

static func _flyin_headbutt_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "unit_destroyed":
		return []
	var uid := str(ctx.get("unit_id", ""))
	if not _flyin_headbutt_validate(player, uid, ctx).ok:
		return []
	var options := _flyin_headbutt_options(uid, player)
	if options.is_empty():
		return [Common.target_entry(uid, {"label": "%s (no enemy unit within 12\" — removes Deadly Demise)" % Common.unit_name(uid)})]
	return [Common.target_entry(uid, {"secondary": {"kind": "unit",
		"prompt": "FLYIN' HEADBUTT: select one enemy unit within 12\" — roll eight D6, 1 mortal wound per 4+",
		"options": options}})]

static func _flyin_headbutt_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "FLYIN' HEADBUTT needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "FLYIN' HEADBUTT must target a unit from your army"}
	if not Common.has_keyword(u, "ORKS") or not Common.has_keyword(u, "AIRCRAFT"):
		return {"ok": false, "reason": "FLYIN' HEADBUTT can only target an ORKS AIRCRAFT unit"}
	if not _is_destroyed(u):
		return {"ok": false, "reason": "FLYIN' HEADBUTT: that unit has not been destroyed"}
	if not _was_on_battlefield(u):
		return {"ok": false, "reason": "FLYIN' HEADBUTT: that unit was not on the battlefield"}
	var destroyed := str(ctx.get("unit_id", ""))
	if destroyed != "" and destroyed != target_unit_id:
		return {"ok": false, "reason": "FLYIN' HEADBUTT must target the unit that was just destroyed"}
	var enemy := str(ctx.get("secondary_id", ""))
	if enemy != "":
		var e = Common.unit(enemy)
		if e.is_empty() or int(e.get("owner", 0)) == player or not Common.is_on_battlefield(e):
			return {"ok": false, "reason": "FLYIN' HEADBUTT must select an enemy unit on the battlefield"}
		if _wreck_distance(target_unit_id, enemy) > FLYIN_HEADBUTT_RANGE + 0.001:
			return {"ok": false, "reason": "FLYIN' HEADBUTT: %s is not within 12\" of your unit" % Common.unit_name(enemy)}
	return {"ok": true, "reason": ""}

static func _flyin_headbutt_apply(target_unit_id: String, ctx: Dictionary) -> Array:
	var diffs: Array = []
	# Your unit does not have the Deadly Demise ability (UnitAbilityManager
	# .has_deadly_demise reads the flag; BasePhase resolves the held roll after).
	diffs.append_array(Common.set_flag_diffs([target_unit_id], FLAG_NO_DEADLY_DEMISE, true))
	var enemy := _head_id(str(ctx.get("secondary_id", "")))
	var record := {"enemy_unit_id": enemy, "rolls": [], "mortal_wounds": 0, "casualties": 0}
	if enemy != "":
		var rng = _rng()
		var rolls: Array = rng.roll_d6(FLYIN_HEADBUTT_DICE)
		var hits := 0
		for r in rolls:
			if int(r) >= 4:
				hits += 1
		var mw := _mortal_wounds_to_unit(enemy, hits, rng)
		diffs.append_array(mw.diffs)
		record = {"enemy_unit_id": enemy, "rolls": rolls, "mortal_wounds": hits, "casualties": int(mw.casualties)}
		Common.log_info("OrkCodexOther: FLYIN' HEADBUTT — %s rams %s: 8D6 %s → %d mortal wound(s), %d model(s) destroyed; no Deadly Demise" % [
			Common.unit_name(target_unit_id), Common.unit_name(enemy), str(rolls), hits, int(mw.casualties)])
		var gel = Common.autoload("GameEventLog")
		if gel and gel.has_method("add_player_entry"):
			gel.add_player_entry(int(Common.unit(target_unit_id).get("owner", 0)),
				"FLYIN' HEADBUTT: %s rams %s — 8D6 %s: %d mortal wound(s)" % [Common.unit_name(target_unit_id), Common.unit_name(enemy), str(rolls), hits])
	else:
		Common.log_info("OrkCodexOther: FLYIN' HEADBUTT — %s loses Deadly Demise (no enemy unit within 12\" selected)" % Common.unit_name(target_unit_id))
	diffs.append_array(Common.set_flag_diffs([target_unit_id], FLAG_FLYIN_HEADBUTT, record))
	return diffs

static func _flyin_headbutt_ai_score(player: int, target_unit_id: String) -> float:
	# Eight D6 at 4+ = 4 expected mortal wounds for 1 CP; without an enemy in
	# range the only gain is skipping Deadly Demise (not worth a CP).
	return 4.0 if not _flyin_headbutt_options(target_unit_id, player).is_empty() else 0.0


# ---------------------------------------------------------------------------
# INFESTED WAR ZONE (Runt Swarm, 2 CP, either player's turn, any phase)
# WHEN: Any phase, when an enemy unit has attacked.
# TARGET: One friendly GRETCHIN unit that was just destroyed. You can target
#         that unit with this stratagem even though that unit was just destroyed.
# EFFECT: Add a new GRETCHIN unit to your army identical to your destroyed
#         unit, in strategic reserves, at its starting strength, with its full
#         wounds remaining.
# "Just destroyed" = destroyed during that enemy unit's attacks (ctx
# destroyed_unit_ids, BasePhase enemy_unit_has_attacked). The new unit is the
# new_reserve_unit follow-up (BasePhase._followup_new_reserve_unit): fresh unit
# id, every model alive at full wounds, Strategic Reserves.
# Ruling: only the GRETCHIN unit itself is copied (an attached CHARACTER is a
# different unit and is not "your destroyed GRETCHIN unit").
# ---------------------------------------------------------------------------

static func _infested_war_zone_targets(player: int, window_id: String, ctx: Dictionary) -> Array:
	if window_id != "enemy_unit_has_attacked":
		return []
	var out: Array = []
	for did in ctx.get("destroyed_unit_ids", []):
		var uid := str(did)
		if _infested_war_zone_validate(player, uid, ctx).ok:
			out.append(Common.target_entry(uid))
	return out

static func _infested_war_zone_validate(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var u = Common.unit(target_unit_id)
	if u.is_empty():
		return {"ok": false, "reason": "INFESTED WAR ZONE needs a target unit"}
	if int(u.get("owner", 0)) != player:
		return {"ok": false, "reason": "INFESTED WAR ZONE must target a unit from your army"}
	if not Common.has_keyword(u, "GRETCHIN"):
		return {"ok": false, "reason": "INFESTED WAR ZONE can only target a GRETCHIN unit"}
	if not _is_destroyed(u):
		return {"ok": false, "reason": "INFESTED WAR ZONE: that unit has not been destroyed"}
	var just: Array = ctx.get("destroyed_unit_ids", [])
	if ctx.has("destroyed_unit_ids") and not target_unit_id in just:
		return {"ok": false, "reason": "INFESTED WAR ZONE must target a unit that was just destroyed"}
	return {"ok": true, "reason": ""}

static func _infested_war_zone_apply(target_unit_id: String) -> Dictionary:
	Common.log_info("OrkCodexOther: INFESTED WAR ZONE — a new %s joins the army in Strategic Reserves at starting strength" % Common.unit_name(target_unit_id))
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(int(Common.unit(target_unit_id).get("owner", 0)),
			"INFESTED WAR ZONE: a new %s is added to Strategic Reserves" % Common.unit_name(target_unit_id))
	return {"diffs": Common.set_flag_diffs([target_unit_id], FLAG_INFESTED_WAR_ZONE, true),
		"followup": {"type": "new_reserve_unit", "source_unit_id": target_unit_id}}

static func _infested_war_zone_ai_score(player: int, target_unit_id: String) -> float:
	var score := float(Common.points(Common.unit(target_unit_id))) / 15.0
	# Two CP is a lot: keep one CP back for reactions.
	if Common.player_cp(player) - 2 < 1:
		score *= 0.6
	return score
