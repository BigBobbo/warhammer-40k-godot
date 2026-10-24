extends RefCounted

## SMCodexAMovement — Codex: Space Marines (11e) generic detachment
## stratagems that MOVE units, embark / redeploy them or change the fight
## order (WP-M3a). Dispatcher: SMCodex11e.gd. Rulings: RULINGS.md § WP-M3a.
##
##   RESPONSIVE TACTICS   (Gladius, 1CP) enemy_ended_move (your opponent's
##                        Movement phase): an unengaged ADEPTUS ASTARTES
##                        INFANTRY/MOUNTED unit within 8" of the enemy unit makes
##                        a normal move of up to D6" (MovementPhase follow-up
##                        reactive_normal_move; D6 rolled here).
##   TRANSHUMAN REACTIONS (Phobos Shock Force, 1CP) enemy_ended_move: the same
##                        for an unengaged PHOBOS unit — up to D6", or up to 6"
##                        if the tactical doctrine is active for it.
##   WIND-SWIFT EVASION   (Stormlance, 1CP) fight_phase_end (either turn): an
##                        ADEPTUS ASTARTES MOUNTED unit that was eligible to
##                        fight this phase makes a normal move (unengaged) or a
##                        fall-back move (engaged) — follow-up sm11e_fight_move,
##                        executed by FightPhase through the functions at the
##                        bottom of this file (human: the reactive-move panel;
##                        AI: solve_fight_move).
##   SUDDEN ONSLAUGHT     (Stormlance, 1CP) unit_selected_to_move (advance):
##                        a MOUNTED/SPEEDER unit's advance roll is a 6
##                        (MovementPhase hook advance_roll_six).
##   DUTY IS NEVER DONE   (Gauntlet, 1CP) fight_phase_end: an unengaged
##                        ADEPTUS ASTARTES INFANTRY unit that was eligible to
##                        fight, wholly within 6" of a friendly TRANSPORT it can
##                        embark within, embarks (FightPhase follow-up embark).
##   AGGRESSIVE DISEMBARKATION (Gauntlet, 1CP) unit_selected_to_move
##                        (move_type "disembark", opened at DISEMBARK_UNIT):
##                        the unit's models may be set up WITHIN (not wholly
##                        within) the TRANSPORT's set-up distance.
##   TACTICAL WITHDRAWAL  (Phobos Shadow Force, 1CP) fight_phase_end (your
##                        opponent's Fight phase): an unengaged PHOBOS / SCOUT
##                        SQUAD unit is placed in strategic reserves (FightPhase
##                        follow-up strategic_reserves).
##   TACTICAL FOCUS       (Tacticus Attack Force, 1CP)
##                        unit_selected_to_consolidate: the TACTICUS unit's
##                        consolidation move is up to D3+3" (the engine's
##                        effect_consolidate_max).
##   TRANSHUMAN SWIFTNESS (Tacticus Attack Force, 1CP) enemy_has_fought (either
##                        player's Fight phase): a TACTICUS unit within range of
##                        an objective and eligible to fight has Fights First
##                        and must be the next unit its player selects to fight.
##
## Flags:
##   sm11e_sudden_onslaught          bool -> advance_roll_six
##   sm11e_aggressive_disembark      bool -> disembark_within
##   sm11e_tactical_focus            int (inches) + effect_consolidate_max
##                                   (sm11e_focus_prev_max: the value it replaced)
##   sm11e_transhuman_swiftness      marker (+ fights_first; sm11e_swiftness_had_ff)

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_RESPONSIVE := "responsive-tactics-gladius-task-force"
const CSV_REACTIONS := "transhuman-reactions-phobos-shock-force"
const CSV_WINDSWIFT := "wind-swift-evasion-stormlance-task-force"
const CSV_ONSLAUGHT := "sudden-onslaught-stormlance-task-force"
const CSV_DUTY := "duty-is-never-done-gauntlet-task-force"
const CSV_AGGRESSIVE := "aggressive-disembarkation-gauntlet-task-force"
const CSV_WITHDRAWAL := "tactical-withdrawal-phobos-shadow-force"
const CSV_FOCUS := "tactical-focus-tacticus-attack-force"
const CSV_SWIFTNESS := "transhuman-swiftness-tacticus-attack-force"

const IDS: Array = [CSV_RESPONSIVE, CSV_REACTIONS, CSV_WINDSWIFT, CSV_ONSLAUGHT, CSV_DUTY, CSV_AGGRESSIVE,
	CSV_WITHDRAWAL, CSV_FOCUS, CSV_SWIFTNESS]

const IMPLEMENTED: Dictionary = {
	CSV_RESPONSIVE: true, CSV_REACTIONS: true, CSV_WINDSWIFT: true, CSV_ONSLAUGHT: true, CSV_DUTY: true,
	CSV_AGGRESSIVE: true, CSV_WITHDRAWAL: true, CSV_FOCUS: true, CSV_SWIFTNESS: true,
}

const AI_KIND: Dictionary = {
	CSV_RESPONSIVE: "utility", CSV_REACTIONS: "utility", CSV_WINDSWIFT: "utility", CSV_ONSLAUGHT: "utility",
	CSV_DUTY: "utility", CSV_AGGRESSIVE: "utility", CSV_WITHDRAWAL: "utility", CSV_FOCUS: "utility",
	CSV_SWIFTNESS: "offensive",
}

const W_ENEMY_ENDED_MOVE := "enemy_ended_move"
const W_FIGHT_END := "fight_phase_end"
const W_SELECTED_TO_MOVE := "unit_selected_to_move"
const W_CONSOLIDATE := "unit_selected_to_consolidate"
const W_ENEMY_HAS_FOUGHT := "enemy_has_fought"

const FLAG_ONSLAUGHT := "sm11e_sudden_onslaught"
const FLAG_AGGRESSIVE := "sm11e_aggressive_disembark"
const FLAG_FOCUS := "sm11e_tactical_focus"
const FLAG_FOCUS_PREV := "sm11e_focus_prev_max"
const FLAG_CONSOLIDATE_MAX := "effect_consolidate_max"   # FightPhase._get_consolidation_distance
const FLAG_SWIFTNESS := "sm11e_transhuman_swiftness"
const FLAG_SWIFTNESS_HAD_FF := "sm11e_swiftness_had_ff"
const FLAG_FIGHTS_FIRST := "fights_first"                 # FightSequencer.is_fights_first
const FLAG_WAS_ELIGIBLE := "was_eligible_to_fight"        # FightPhase 12.08 stamp

const KW_AA := "ADEPTUS ASTARTES"
const REACT_RANGE_IN := 8.0
const DUTY_RANGE_IN := 6.0
const TACTICAL_REACTION_IN := 6.0

const ReactiveMoveLib = preload("res://scripts/rules/ReactiveMove11e.gd")


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if str(uid) == "" or not _check(csv, player, str(uid), window_id, ctx).ok:
			continue
		var extra := {}
		if csv == CSV_DUTY:
			var transports := duty_transports(player, str(uid))
			if transports.size() == 1:
				extra["label"] = "%s → %s" % [Common.group_label(str(uid)), Common.unit_name(str(transports[0]))]
			else:
				var options: Array = []
				for tid in transports:
					options.append({"id": str(tid), "label": Common.unit_name(str(tid))})
				extra["secondary"] = {"kind": "unit", "prompt": "DUTY IS NEVER DONE: embark %s within which TRANSPORT?" % Common.group_label(str(uid)), "options": options}
		out.append(Common.target_entry(str(uid), extra))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	if target_unit_id == "":
		return _no("%s needs a target unit" % strat.get("name", "?"))
	var c := _check(csv, player, target_unit_id, str(ctx.get("window_id", "")), ctx)
	if not c.ok:
		return c
	if csv == CSV_DUTY:
		var chosen := str(ctx.get("secondary_id", ""))
		if chosen != "" and not chosen in duty_transports(player, Common.head_id(target_unit_id)):
			return _no("DUTY IS NEVER DONE: %s cannot embark within %s" % [Common.unit_name(target_unit_id), Common.unit_name(chosen)])
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_RESPONSIVE, CSV_REACTIONS:
			var sname := _name(csv)
			var fixed := csv == CSV_REACTIONS and Common.doctrine_active_id(head, "tactical")
			var roll := 0
			var inches := TACTICAL_REACTION_IN
			if fixed:
				_log(player, "%s: the tactical doctrine is active for %s — it can make a normal move of up to 6\"" % [sname, label])
			else:
				roll = int(Common.roll_dice(1, 6)[0])
				inches = float(roll)
				_log(player, "%s: %s rolls D6 = %d — it can make a normal move of up to %d\"" % [sname, label, roll, roll])
			return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": head, "max_inches": inches,
				"roll": roll, "source": sname, "goal": "", "away_from_unit_id": str(ctx.get("enemy_unit_id", ""))}}
		CSV_WINDSWIFT:
			var engaged := Common.is_engaged(head)
			var kind := "fall_back" if engaged else "normal"
			var m_in := unit_move_inches(head)
			_log(player, "WIND-SWIFT EVASION: %s is %s — it can make a %s move (up to %.0f\")" % [
				label, "engaged" if engaged else "unengaged", "fall-back" if engaged else "normal", m_in])
			return {"diffs": [], "followup": {"type": "sm11e_fight_move", "unit_id": head, "kind": kind,
				"max_inches": m_in, "source": "WIND-SWIFT EVASION"}}
		CSV_ONSLAUGHT:
			_log(player, "SUDDEN ONSLAUGHT: %s's advance roll is changed to a 6" % label)
			return Common.set_flag_diffs(group, FLAG_ONSLAUGHT, true)
		CSV_DUTY:
			var transport := str(ctx.get("secondary_id", ""))
			if transport == "":
				var ts := duty_transports(player, head)
				transport = str(ts[0]) if not ts.is_empty() else ""
			if transport == "":
				Common.log_error("SMCodexAMovement: DUTY IS NEVER DONE — no TRANSPORT for %s at apply time" % head)
				return []
			_log(player, "DUTY IS NEVER DONE: %s embarks within %s" % [label, Common.unit_name(transport)])
			return {"diffs": [], "followup": {"type": "embark", "unit_id": head, "transport_id": transport, "source": "DUTY IS NEVER DONE"}}
		CSV_AGGRESSIVE:
			_log(player, "AGGRESSIVE DISEMBARKATION: %s's models can be set up within (not wholly within) the set-up distance of its TRANSPORT" % label)
			return Common.set_flag_diffs(group, FLAG_AGGRESSIVE, true)
		CSV_WITHDRAWAL:
			_log(player, "TACTICAL WITHDRAWAL: %s is placed in strategic reserves" % label)
			return {"diffs": [], "followup": {"type": "strategic_reserves", "unit_id": head, "source": "TACTICAL WITHDRAWAL"}}
		CSV_FOCUS:
			var d3 := int(Common.roll_dice(1, 3)[0])
			var inches := d3 + 3
			var diffs: Array = []
			for gid in group:
				var prev := float(Common.unit(str(gid)).get("flags", {}).get(FLAG_CONSOLIDATE_MAX, 0.0))
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_FOCUS_PREV], "value": prev})
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_CONSOLIDATE_MAX], "value": maxf(prev, float(inches))})
			diffs.append_array(Common.set_flag_diffs(group, FLAG_FOCUS, inches))
			_log(player, "TACTICAL FOCUS: %s rolls D3 = %d — its consolidation move can be up to %d\"" % [label, d3, inches])
			return diffs
		CSV_SWIFTNESS:
			var d: Array = []
			for gid in group:
				var had_ff := bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_FIGHTS_FIRST, false))
				d.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_SWIFTNESS_HAD_FF], "value": had_ff})
			d.append_array(Common.set_flag_diffs(group, FLAG_FIGHTS_FIRST, true))
			d.append_array(Common.set_flag_diffs(group, FLAG_SWIFTNESS, true))
			_log(player, "TRANSHUMAN SWIFTNESS: %s has Fights First and must be the next unit Player %d selects to fight" % [label, player])
			return d
	Common.log_error("SMCodexAMovement: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	var units: Dictionary = Common.state().get("units", {})
	match csv:
		CSV_ONSLAUGHT:
			Common.erase_flags(group, [FLAG_ONSLAUGHT])
		CSV_AGGRESSIVE:
			Common.erase_flags(group, [FLAG_AGGRESSIVE])
		CSV_FOCUS:
			for gid in group:
				var f = units.get(str(gid), {}).get("flags", null)
				if typeof(f) != TYPE_DICTIONARY or not f.has(FLAG_FOCUS):
					continue
				var prev := float(f.get(FLAG_FOCUS_PREV, 0.0))
				if prev > 0.0:
					f[FLAG_CONSOLIDATE_MAX] = prev
				else:
					f.erase(FLAG_CONSOLIDATE_MAX)
				f.erase(FLAG_FOCUS)
				f.erase(FLAG_FOCUS_PREV)
		CSV_SWIFTNESS:
			for gid in group:
				var f2 = units.get(str(gid), {}).get("flags", null)
				if typeof(f2) != TYPE_DICTIONARY:
					continue
				if f2.has(FLAG_SWIFTNESS) and not bool(f2.get(FLAG_SWIFTNESS_HAD_FF, false)):
					f2.erase(FLAG_FIGHTS_FIRST)
				f2.erase(FLAG_SWIFTNESS)
				f2.erase(FLAG_SWIFTNESS_HAD_FF)
	# RESPONSIVE TACTICS / TRANSHUMAN REACTIONS / WIND-SWIFT EVASION / DUTY IS
	# NEVER DONE / TACTICAL WITHDRAWAL leave no flag behind.
	Common.log_info("SMCodexAMovement: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(_strat: Dictionary, _variant_id: String) -> String:
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, _window_id: String, _ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	match csv:
		CSV_RESPONSIVE, CSV_REACTIONS:
			# The AI's reactive move heads for the nearest objective it does not
			# control: pay only when the move surely reaches one it is not on.
			var reach := 2.0
			if csv == CSV_REACTIONS and Common.doctrine_active_id(uid, "tactical"):
				reach = TACTICAL_REACTION_IN
			var gap := objective_gap_inches(uid)
			return 2.1 if gap > 0.0 and gap <= reach else 0.0
		CSV_WINDSWIFT:
			if Common.is_engaged(uid):
				# Leave a fight the unit is losing: the enemy it is engaged with
				# is worth more than it is.
				var foe_pts := 0
				for eid in Common.engaged_enemy_ids(uid):
					foe_pts += int(Common.unit(str(eid)).get("meta", {}).get("points", 0))
				return 2.1 if foe_pts > Common.group_points(uid) else 0.0
			var gap := objective_gap_inches(uid)
			return 2.1 if gap > 0.0 and gap <= unit_move_inches(uid) - 0.5 else 0.0
		CSV_ONSLAUGHT:
			# The AI already chose to advance: a 6 is +2.5" on average.
			return 2.0
		CSV_DUTY:
			# Safe ride for a unit with no fight left in it: no enemy within 9".
			return 2.0 if Common.nearest_enemy_inches(Common.group_union(uid)) > 9.0 and not Common.group_in_range_of_any_objective(uid) else 0.0
		CSV_AGGRESSIVE:
			# The AI's disembark placement always sets up wholly within (ruling).
			return 0.0
		CSV_WITHDRAWAL:
			if Common.battle_round() >= 5:
				return 0.0
			if Common.nearest_enemy_inches(Common.group_union(uid)) <= 12.0:
				return 0.0
			if Common.group_in_range_of_any_objective(uid):
				return 0.0
			return 2.1
		CSV_FOCUS:
			var gap := objective_gap_inches(uid)
			if gap > 3.0 and gap <= 4.0:
				return 2.1
			var near := Common.nearest_enemy_inches(Common.group_union(uid))
			return 2.0 if near > 3.0 and near <= 4.5 and not Common.is_engaged(uid) else 0.0
		CSV_SWIFTNESS:
			return 2.4 if Common.is_engaged(uid) and Common.group_has_melee_weapons(uid) else 0.0
	return 0.0


# ===========================================================================
# Engine consumers (SMCodex11e hooks)
# ===========================================================================

static func advance_roll_six(unit_id: String) -> bool:
	return _group_flag(unit_id, FLAG_ONSLAUGHT)


static func disembark_within(unit_id: String) -> bool:
	return _group_flag(unit_id, FLAG_AGGRESSIVE)


## TRANSHUMAN SWIFTNESS: the unit `player` must select next — only while it is
## still eligible to fight (it stops binding once it fought).
static func restrict_fight_candidates(player: int, candidates: Array) -> Array:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not bool(u.get("flags", {}).get(FLAG_SWIFTNESS, false)):
			continue
		var head := Common.head_id(str(uid))
		if head in candidates:
			return [head]
	return candidates


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_RESPONSIVE, CSV_REACTIONS:
			return Common.friendly_heads(player) if window_id == W_ENEMY_ENDED_MOVE else []
		CSV_WINDSWIFT, CSV_DUTY, CSV_WITHDRAWAL:
			return Common.friendly_heads(player) if window_id == W_FIGHT_END else []
		CSV_ONSLAUGHT, CSV_AGGRESSIVE:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_MOVE else []
		CSV_FOCUS:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_CONSOLIDATE else []
		CSV_SWIFTNESS:
			return Common.friendly_heads(player) if window_id == W_ENEMY_HAS_FOUGHT else []
	return []


static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var sname := _name(csv)
	var head := Common.head_id(target_unit_id)
	var u := Common.unit(head)
	if u.is_empty():
		return _no("%s needs a target unit" % sname)
	if int(u.get("owner", 0)) != player:
		return _no("%s must target a unit from your army" % sname)
	if csv == CSV_AGGRESSIVE:
		# The unit is still embarked when it is selected to disembark.
		if str(u.get("embarked_in", "")) in ["", "<null>"] or u.get("embarked_in", null) == null:
			return _no("AGGRESSIVE DISEMBARKATION: that unit is not embarked within a TRANSPORT")
		if not Common.group_has_keyword(head, KW_AA):
			return _no("AGGRESSIVE DISEMBARKATION can only target an ADEPTUS ASTARTES unit")
		if window_id == W_SELECTED_TO_MOVE and ctx.has("move_type") and str(ctx.get("move_type", "")) != "disembark":
			return _no("AGGRESSIVE DISEMBARKATION: only when the unit is selected to disembark")
		var sel := str(ctx.get("unit_id", ""))
		if sel != "" and Common.head_id(sel) != head:
			return _no("AGGRESSIVE DISEMBARKATION must target the unit that was selected to move")
		return {"ok": true, "reason": ""}
	if not Common.is_on_battlefield(u):
		return _no("%s: that unit is not on the battlefield" % sname)
	if not Common.group_has_keyword(head, KW_AA):
		return _no("%s can only target an ADEPTUS ASTARTES unit" % sname)
	var my_turn := Common.active_player() == player
	match csv:
		CSV_RESPONSIVE, CSV_REACTIONS:
			if my_turn:
				return _no("%s: only in your opponent's Movement phase" % sname)
			if csv == CSV_RESPONSIVE and not Common.group_has_any_keyword(head, ["INFANTRY", "MOUNTED"]):
				return _no("RESPONSIVE TACTICS can only target an ADEPTUS ASTARTES INFANTRY/MOUNTED unit")
			if csv == CSV_REACTIONS and not Common.group_has_keyword(head, "PHOBOS"):
				return _no("TRANSHUMAN REACTIONS can only target a PHOBOS unit")
			if Common.is_engaged(head):
				return _no("%s: the unit must be unengaged" % sname)
			var foe := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			if foe != "" and Common.group_distance_inches(head, foe) > REACT_RANGE_IN + 0.001:
				return _no("%s: that enemy unit did not end its move within 8\" of %s" % [sname, Common.group_label(head)])
		CSV_WINDSWIFT:
			if not Common.group_has_keyword(head, "MOUNTED"):
				return _no("WIND-SWIFT EVASION can only target an ADEPTUS ASTARTES MOUNTED unit")
			if not _group_flag(head, FLAG_WAS_ELIGIBLE):
				return _no("WIND-SWIFT EVASION: that unit was not eligible to fight this phase")
		CSV_DUTY:
			if Common.is_attached_character(target_unit_id) and target_unit_id != head:
				return _no("DUTY IS NEVER DONE: select the Attached unit's bodyguard")
			if not Common.group_has_keyword(head, "INFANTRY"):
				return _no("DUTY IS NEVER DONE can only target an ADEPTUS ASTARTES INFANTRY unit")
			if Common.is_engaged(head):
				return _no("DUTY IS NEVER DONE can only target an unengaged unit")
			if not _group_flag(head, FLAG_WAS_ELIGIBLE):
				return _no("DUTY IS NEVER DONE: that unit was not eligible to fight this phase")
			if duty_transports(player, head).is_empty():
				return _no("DUTY IS NEVER DONE: no friendly TRANSPORT it can embark within is wholly within 6\"")
		CSV_WITHDRAWAL:
			if my_turn:
				return _no("TACTICAL WITHDRAWAL: only at the end of your opponent's Fight phase")
			if not Common.group_has_any_keyword(head, ["PHOBOS", "SCOUT SQUAD"]):
				return _no("TACTICAL WITHDRAWAL can only target a PHOBOS / SCOUT SQUAD unit")
			if Common.is_engaged(head):
				return _no("TACTICAL WITHDRAWAL can only target an unengaged unit")
		CSV_ONSLAUGHT:
			if not my_turn:
				return _no("SUDDEN ONSLAUGHT: only in your Movement phase")
			if not Common.group_has_any_keyword(head, ["MOUNTED", "SPEEDER"]):
				return _no("SUDDEN ONSLAUGHT can only target an ADEPTUS ASTARTES MOUNTED/SPEEDER unit")
			var sel2 := str(ctx.get("unit_id", ""))
			if sel2 != "" and Common.head_id(sel2) != head:
				return _no("SUDDEN ONSLAUGHT must target the unit that was selected to move")
			if window_id == W_SELECTED_TO_MOVE and ctx.has("move_type") and str(ctx.get("move_type", "")) != "advance":
				return _no("SUDDEN ONSLAUGHT: only when the unit is selected to make an advance move")
		CSV_FOCUS:
			if not Common.group_has_keyword(head, "TACTICUS"):
				return _no("TACTICAL FOCUS can only target a TACTICUS unit")
			var sel3 := str(ctx.get("unit_id", ""))
			if sel3 != "" and Common.head_id(sel3) != head:
				return _no("TACTICAL FOCUS must target the unit that was selected to consolidate")
		CSV_SWIFTNESS:
			if not Common.group_has_keyword(head, "TACTICUS"):
				return _no("TRANSHUMAN SWIFTNESS can only target a TACTICUS unit")
			if not Common.group_in_range_of_any_objective(head):
				return _no("TRANSHUMAN SWIFTNESS: that unit is not within range of an objective")
			if not _eligible_to_fight(head):
				return _no("TRANSHUMAN SWIFTNESS: that unit is not eligible to fight")
	return {"ok": true, "reason": ""}


## DUTY IS NEVER DONE: friendly TRANSPORT ids (nearest first) the unit is
## wholly within 6" of and can embark within (TransportManager.can_embark:
## capacity, keywords, not set up / disembarked this turn — the 18.02 checks
## other than the 3" distance, the KEEP IT RUNNIN' ruling).
static func duty_transports(player: int, unit_id: String) -> Array:
	var tm = Common.autoload("TransportManager")
	var found: Array = []
	for tid_raw in Common.state().get("units", {}):
		var tid := str(tid_raw)
		if tid in Common.attached_group_ids(unit_id):
			continue
		var t = Common.unit(tid)
		if int(t.get("owner", 0)) != player or not t.has("transport_data") or not Common.has_keyword(t, "TRANSPORT"):
			continue
		if not Common.is_on_battlefield(t):
			continue
		if tm != null and tm.has_method("can_embark"):
			var ce: Dictionary = tm.can_embark(unit_id, tid)
			if not ce.get("valid", false):
				continue
		if _group_farthest_inches(unit_id, tid) <= DUTY_RANGE_IN + 0.001:
			found.append({"id": tid, "d": Common.group_distance_inches(unit_id, tid)})
	found.sort_custom(func(a, b): return float(a.d) < float(b.d))
	return found.map(func(e): return e.id)


## "Wholly within": the largest distance from any point of any alive model's
## base in the Attached unit to the nearest model of `other_id` (01.04.01).
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
			var extent_in := float(m.get("base_mm", 32)) / 25.4
			if meas and meas.has_method("base_extent_px"):
				extent_in = 2.0 * float(meas.base_extent_px(m)) / Common.PX_PER_INCH
			worst = maxf(worst, best + extent_in)
	return worst if any else INF


static func _eligible_to_fight(unit_id: String) -> bool:
	var pm = Common.phase_manager()
	var ph = pm.get_current_phase_instance() if pm != null and pm.has_method("get_current_phase_instance") else null
	if ph == null or not ("sequencer_11e" in ph) or ph.sequencer_11e == null:
		return false
	return bool(ph.sequencer_11e.group_eligible_to_fight(unit_id, Common.state()))


## The unit's M (the Movement phase's own computation, so every M modifier —
## detachment rules, enhancements, datasheet abilities — applies).
static func unit_move_inches(unit_id: String) -> float:
	var u := Common.unit(unit_id)
	var mp_script = load("res://phases/MovementPhase.gd")
	var mp = mp_script.new() if mp_script != null else null
	var m := float(u.get("meta", {}).get("stats", {}).get("move", 6))
	if mp != null and mp.has_method("get_unit_movement"):
		m = float(mp.get_unit_movement(u))
	if mp != null:
		mp.free()
	return m


## Smallest distance any model of the unit still has to cover to be within
## range of an objective (0 = already within range; INF = none).
static func objective_gap_inches(unit_id: String) -> float:
	var mm = Common.mission_manager()
	if mm == null or not mm.has_method("model_gap_to_objective_range_px"):
		return INF
	var best := INF
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			for obj in Common.objectives():
				best = minf(best, float(mm.model_gap_to_objective_range_px(m, obj)) / Common.PX_PER_INCH)
	return best


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_RESPONSIVE: return "RESPONSIVE TACTICS"
		CSV_REACTIONS: return "TRANSHUMAN REACTIONS"
		CSV_WINDSWIFT: return "WIND-SWIFT EVASION"
		CSV_ONSLAUGHT: return "SUDDEN ONSLAUGHT"
		CSV_DUTY: return "DUTY IS NEVER DONE"
		CSV_AGGRESSIVE: return "AGGRESSIVE DISEMBARKATION"
		CSV_WITHDRAWAL: return "TACTICAL WITHDRAWAL"
		CSV_FOCUS: return "TACTICAL FOCUS"
		CSV_SWIFTNESS: return "TRANSHUMAN SWIFTNESS"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SMCodexAMovement: " + msg)
	Common.game_log(player, msg)

static func _group_flag(unit_id: String, flag: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get(flag, false)):
			return true
	return false


# ===========================================================================
# WIND-SWIFT EVASION — the normal / fall-back move FightPhase executes for the
# follow-up sm11e_fight_move. FightPhase holds the move in its
# `sm11e_fight_move` var and routes the reactive-move panel's actions
# (ORK11E_REACTIVE_MOVE_STAGE / AUTO / RESET / CONFIRM / SKIP — the same
# actions and panel as the Shooting phase's reactive moves) here. Judged by
# ReactiveMove11e.validate (kind "normal": every model within the maximum,
# no overlaps, on the board, coherent, ending unengaged — which is also what a
# fall-back move must satisfy). A fall-back move by a battle-shocked unit uses
# the desperate escape mode (09.07: hazard roll per model before it moves).
# ===========================================================================

## Start the move. Returns true when it waits for a human (the phase is
## paused until CONFIRM / SKIP), false when it resolved (AI, or no move).
static func fight_move_start(phase, player: int, followup: Dictionary) -> bool:
	var unit_id := Common.head_id(str(followup.get("unit_id", "")))
	var kind := str(followup.get("kind", "normal"))
	var source := str(followup.get("source", "WIND-SWIFT EVASION"))
	var max_in := float(followup.get("max_inches", 0.0))
	var u := Common.unit(unit_id)
	if u.is_empty() or not Common.is_on_battlefield(u) or max_in <= 0.0:
		phase.log_phase_message("%s: no move for %s (unit gone or 0\")" % [source, unit_id])
		return false
	var pre_diffs: Array = []
	if kind == "fall_back":
		pre_diffs.append_array(_fall_back_before_moving(phase, unit_id, source))
		for gid in Common.attached_group_ids(unit_id):
			pre_diffs.append({"op": "set", "path": "units.%s.flags.fell_back" % str(gid), "value": true})
	if not pre_diffs.is_empty():
		Common.phase_manager().apply_state_changes(pre_diffs)
		phase._window_sync_diffs.append_array(pre_diffs)
	if not Common.is_on_battlefield(Common.unit(unit_id)):
		phase.log_phase_message("%s: %s was destroyed by its desperate escape — no move" % [source, unit_id])
		return false
	var label := "%s (%s move)" % [source, "fall-back" if kind == "fall_back" else "normal"]
	var fu := {"player": player, "kind": "normal", "move_kind": kind, "unit_id": unit_id, "source": label,
		"origin": ReactiveMoveLib.current_positions(unit_id, Common.state()), "max_inches": max_in,
		"translation": Vector2.ZERO}
	if phase._is_ai_window_decider(player):
		var proposed := solve_fight_move(unit_id, fu.origin, max_in, kind)
		if proposed.is_empty():
			phase.log_phase_message("%s: %s — no legal placement found, the unit does not move" % [label, Common.group_label(unit_id)])
			return false
		var ai_diffs := ReactiveMoveLib.position_diffs(proposed)
		Common.phase_manager().apply_state_changes(ai_diffs)
		phase._window_sync_diffs.append_array(ai_diffs)
		_log(player, "%s: %s made its move (up to %.0f\")" % [label, Common.group_label(unit_id), max_in])
		return false
	phase.sm11e_fight_move = fu
	phase.log_phase_message("%s: waiting for Player %d to move %s (up to %.0f\")" % [label, player, Common.group_label(unit_id), max_in])
	phase.emit_signal("ork11e_reactive_move_started", fight_move_info(phase))
	return true


static func _fall_back_before_moving(phase, unit_id: String, source: String) -> Array:
	var diffs: Array = []
	var tmpl = MoveTypes.get_type("fall_back")
	if tmpl == null:
		return diffs
	var sel: Dictionary = tmpl.select_mode(unit_id, Common.state())
	var mode := str(sel.get("mode", "ordered_retreat"))
	phase.log_phase_message("[11e] %s fall-back mode for %s: %s" % [source, unit_id, mode])
	if mode != "desperate_escape":
		return diffs
	var re = Common.rules()
	var ctx: Dictionary = tmpl.before_moving(unit_id, Common.state(), re.make_rng(), {"mode": mode})
	var hz: Dictionary = ctx.get("hazard", {})
	phase.log_phase_message("[11e] %s desperate escape hazard rolls for %s: %s (%d failure(s))" % [source, unit_id, str(hz.get("rolls", [])), int(hz.get("failures", 0))])
	if int(hz.get("failures", 0)) <= 0:
		return diffs
	var unit := Common.unit(unit_id)
	var mw := int(hz.get("mortal_wounds", 0))
	mw = re.mortal_wounds_after_fnp(unit, mw, null, [], false, "desperate_escape")
	var out = Allocation.apply_mortal_wounds_11e(unit, mw, CasualtyPreference.engine_auto_preference(unit, Common.state()))
	for ridx in out.remaining:
		diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [unit_id, int(ridx)], "value": int(out.remaining[ridx])})
	for di in out.models_destroyed:
		diffs.append({"op": "set", "path": "units.%s.models.%d.alive" % [unit_id, int(di)], "value": false})
		diffs.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [unit_id, int(di)], "value": 0})
	return diffs


## The move in progress, for the move panel and scenarios ({} = none).
static func fight_move_info(phase, positions: Dictionary = {}) -> Dictionary:
	var fu: Dictionary = phase.sm11e_fight_move
	if fu.is_empty():
		return {}
	var current: Dictionary = positions if not positions.is_empty() else ReactiveMoveLib.current_positions(fu.unit_id, Common.state())
	var moved := 0.0
	for key in fu.origin:
		if current.has(key):
			moved = maxf(moved, fu.origin[key].distance_to(current[key]) / Common.PX_PER_INCH)
	var check := ReactiveMoveLib.validate("normal", fu.unit_id, fu.origin, current, fu.max_inches, {}, Common.state())
	return {"player": fu.player, "kind": "normal", "move_kind": fu.move_kind, "unit_id": fu.unit_id,
		"unit_name": Common.group_label(fu.unit_id), "source": fu.source,
		"max_inches": fu.max_inches, "moved_inches": moved, "roll": 0, "reroll_available": false,
		"surge_target": "", "surge_target_name": "", "end_condition": "", "valid": check.ok, "violations": check.violations,
		"translation": {"x": fu.translation.x, "y": fu.translation.y}}


## FightPhase.validate_action gate: {} = not this move's business.
static func fight_move_gate(phase, action: Dictionary) -> Dictionary:
	var fu: Dictionary = phase.sm11e_fight_move
	var t := str(action.get("type", ""))
	if t.begins_with("ORK11E_REACTIVE_MOVE_"):
		if fu.is_empty():
			return {"valid": false, "errors": ["No move is in progress"]}
		if action.has("player") and int(action.get("player", 0)) != int(fu.player):
			return {"valid": false, "errors": ["Player %d is making this move, not Player %d" % [int(fu.player), int(action.get("player", 0))]]}
		if not t in ["ORK11E_REACTIVE_MOVE_STAGE", "ORK11E_REACTIVE_MOVE_AUTO", "ORK11E_REACTIVE_MOVE_RESET",
				"ORK11E_REACTIVE_MOVE_CONFIRM", "ORK11E_REACTIVE_MOVE_SKIP"]:
			return {"valid": false, "errors": ["Unknown action type: " + t]}
		return {"valid": true, "errors": []}
	if not fu.is_empty() and not t.begins_with("DEBUG_"):
		return {"valid": false, "errors": ["Waiting for Player %d to finish the %s" % [int(fu.player), str(fu.source)]]}
	return {}


## FightPhase.process_action for the ORK11E_REACTIVE_MOVE_* actions.
static func fight_move_action(phase, action: Dictionary) -> Dictionary:
	var fu: Dictionary = phase.sm11e_fight_move
	var t := str(action.get("type", ""))
	var positions: Dictionary = {}
	match t:
		"ORK11E_REACTIVE_MOVE_STAGE":
			var payload = action.get("payload", {})
			if payload.has("model_positions"):
				positions = fu.origin.duplicate()
				for key in payload.model_positions:
					if positions.has(key):
						var p = payload.model_positions[key]
						positions[key] = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
			else:
				var tr = payload.get("translation", {})
				var v := Vector2(float(tr.get("x", 0.0)), float(tr.get("y", 0.0)))
				var max_px := float(fu.max_inches) * Common.PX_PER_INCH
				if v.length() > max_px:
					v = v.normalized() * max_px
				fu.translation = v
				positions = {}
				for key in fu.origin:
					positions[key] = fu.origin[key] + v
		"ORK11E_REACTIVE_MOVE_AUTO":
			positions = solve_fight_move(fu.unit_id, fu.origin, fu.max_inches, str(fu.move_kind))
			if positions.is_empty():
				return phase.create_result(false, [], "%s: no legal placement found for %s — move it by hand or choose Don't move" % [fu.source, Common.group_label(fu.unit_id)])
		"ORK11E_REACTIVE_MOVE_RESET":
			fu.translation = Vector2.ZERO
			positions = fu.origin.duplicate()
		"ORK11E_REACTIVE_MOVE_CONFIRM":
			var current := ReactiveMoveLib.current_positions(fu.unit_id, Common.state())
			var check := ReactiveMoveLib.validate("normal", fu.unit_id, fu.origin, current, fu.max_inches, {}, Common.state())
			if not check.ok:
				return phase.create_result(false, [], "%s: %s" % [fu.source, "; ".join(check.violations)])
			return _finish_fight_move(phase, ReactiveMoveLib.position_diffs(current), true)
		"ORK11E_REACTIVE_MOVE_SKIP":
			return _finish_fight_move(phase, ReactiveMoveLib.position_diffs(fu.origin), false)
	var diffs := ReactiveMoveLib.position_diffs(positions)
	var info := fight_move_info(phase, positions)
	phase.emit_signal("ork11e_reactive_move_updated", info)
	return phase.create_result(true, diffs, "", {"ork11e_reactive_move": info})


static func _finish_fight_move(phase, diffs: Array, moved: bool) -> Dictionary:
	var fu: Dictionary = phase.sm11e_fight_move
	var msg := "%s: %s %s" % [fu.source, Common.group_label(fu.unit_id), "made its move" if moved else "did not move"]
	_log(int(fu.player), msg)
	phase.log_phase_message(msg)
	var ended := {"player": fu.player, "unit_id": fu.unit_id, "source": fu.source, "moved": moved}
	phase.sm11e_fight_move = {}
	phase.emit_signal("ork11e_reactive_move_ended", ended)
	var result: Dictionary = phase._finish_window_followup(diffs)
	result["ork11e_reactive_move_ended"] = ended
	return result


## Auto placement for the move: translate the whole unit (formation kept) —
## a fall-back away from the enemy units it is engaged with, a normal move
## toward the nearest objective it is not within range of (else away from the
## nearest enemy) — the shortest legal distance first for a fall-back, the
## longest for a normal move. {} = no legal placement.
static func solve_fight_move(unit_id: String, origin: Dictionary, max_inches: float, kind: String) -> Dictionary:
	if origin.is_empty():
		return {}
	var board := Common.state()
	var centroid := Vector2.ZERO
	for key in origin:
		centroid += origin[key]
	centroid /= float(origin.size())
	var player := int(Common.unit(unit_id).get("owner", 0))
	var dir := Vector2.ZERO
	if kind == "fall_back":
		var away := Vector2.ZERO
		for eid in Common.engaged_enemy_ids(unit_id):
			var ec := _centroid(Common.head_id(str(eid)))
			if ec != Vector2.INF:
				away += (centroid - ec).normalized()
		dir = away.normalized()
	else:
		var gap := objective_gap_inches(unit_id)
		if gap > 0.0 and gap < INF:
			var best_d := INF
			for obj in Common.objectives():
				var op = obj.get("position", Vector2.ZERO)
				if op is Dictionary:
					op = Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
				var d := (op as Vector2).distance_to(centroid)
				if d < best_d:
					best_d = d
					dir = ((op as Vector2) - centroid).normalized()
		if dir == Vector2.ZERO:
			var near_c := Vector2.INF
			var near_d := INF
			for eid in Common.enemy_heads(player):
				var ec2 := _centroid(str(eid))
				if ec2 != Vector2.INF and ec2.distance_to(centroid) < near_d:
					near_d = ec2.distance_to(centroid)
					near_c = ec2
			if near_c != Vector2.INF:
				dir = (centroid - near_c).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1 if player == 2 else -1)
	var steps: Array = []
	var s := 0.5
	while s <= max_inches - 0.05 + 0.001:
		steps.append(s)
		s += 0.5
	steps.append(maxf(0.1, max_inches - 0.05))
	if kind != "fall_back":
		steps.reverse()
	for dist in steps:
		for ang in [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 90.0, -90.0]:
			var v: Vector2 = dir.rotated(deg_to_rad(ang)) * float(dist) * Common.PX_PER_INCH
			var proposed := {}
			for key in origin:
				proposed[key] = origin[key] + v
			if ReactiveMoveLib.validate("normal", unit_id, origin, proposed, max_inches, {}, board).ok:
				return proposed
	return {}


static func _centroid(unit_id: String) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				sum += Common._pos(m)
				n += 1
	return sum / float(n) if n > 0 else Vector2.INF
