extends RefCounted

## SMCodexBAction — Codex: Space Marines (11e) generic detachment stratagems
## that MOVE units, roll dice, force battle-shock tests, secure objectives or
## change OC (WP-M3b). Facade: SMCodexB.gd. Rulings: RULINGS.md § WP-M3b.
##
##   GUNSHIP EXTRACTION (Terminator Storm Force, 1CP) fight_phase_end
##       (opponent's Fight phase): an unengaged TERMINATOR unit is placed in
##       strategic reserves (follow-up strategic_reserves, FightPhase).
##   ARMOURED IMPACT (Gravis Linebreaker Force, 1CP) unit_ended_charge_move
##       (your Charge phase): select one enemy unit engaged with the GRAVIS unit
##       (secondary pick); one D6 per GRAVIS model engaged with it, each 3+ = 1
##       mortal wound.
##   PURGATION PUSH (Gravis Linebreaker Force, 1CP) unit_has_shot (your
##       Shooting phase): an unengaged GRAVIS unit makes a normal move of up to
##       5" that must end within range of an objective (follow-up
##       reactive_normal_move, end_condition within_objective_range); it is not
##       eligible to declare a charge (cannot_charge) or embark (sm11e_no_embark)
##       until the end of the turn.
##   HAIL OF VENGEANCE (Devastator Brethren, 2CP) enemy_has_shot (opponent's
##       Shooting phase): an ADEPTUS ASTARTES unit that lost a model to those
##       attacks shoots (normal shooting, auto-resolved follow-up `shoot`) and
##       can only target that enemy unit.
##   SUPPRESSION VOLLEYS (Gravis Siege Force, 1CP) unit_has_shot: one enemy unit
##       hit by those attacks (secondary pick) makes a battle-shock roll at -1.
##   STAND UNYIELDING (Gravis Siege Force, 1CP) movement_phase_end (your
##       Movement phase): one objective the GRAVIS unit is controlling
##       (secondary pick) becomes secured (MissionManager.secure_objective).
##   DOMINATION FIRE (Tactical Brethren, 1CP) unit_has_shot: one enemy unit hit
##       (secondary pick) is suppressed until the start of your next turn — its
##       attacks have -1 to hit (sm11e_suppressed on the ENEMY, self-expiring).
##   MASTERFUL TACTICS (Tactical Brethren, 1CP) enemy_ended_move (opponent's
##       Movement phase): an unengaged ADEPTUS ASTARTES INFANTRY/MOUNTED unit
##       within 8" of the enemy unit makes a normal move of up to D6" (6" with
##       the tactical doctrine) — follow-up reactive_normal_move (MovementPhase).
##   ADAMANTINE TERROR (Ironclad Champions, 1CP) fight_phase_start (either
##       player's Fight phase): each enemy unit engaged with the DREADNOUGHT unit
##       makes a battle-shock roll at -1.
##   UPSTOPPABLE ADVANCE (Ironclad Champions, 1CP) unit_selected_to_move /
##       unit_declares_charge (your turn): the DREADNOUGHT has MOBILE this phase
##       (the engine's MOBILE grant ork11e_mobile).
##   FOR THE EMPEROR! (Tacticus Firestorm Force, 1CP) command_phase_main (your
##       Command phase) / command_phase_opponent (your opponent's Command phase,
##       window added by WP-M3b): a TACTICUS unit within range of an objective
##       has +1 OC until the end of the turn (sm11e_for_the_emperor = turn stamp,
##       MissionManager.model_oc hook).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_GUNSHIP := "gunship-extraction-terminator-storm-force"
const CSV_IMPACT := "armoured-impact-gravis-linebreaker-force"
const CSV_PUSH := "purgation-push-gravis-linebreaker-force"
const CSV_HAIL := "hail-of-vengeance-devastator-brethren"
const CSV_SUPPRESSION := "suppression-volleys-gravis-siege-force"
const CSV_STAND := "stand-unyielding-gravis-siege-force"
const CSV_DOMINATION := "domination-fire-tactical-brethren"
const CSV_MASTERFUL := "masterful-tactics-tactical-brethren"
const CSV_ADAMANTINE := "adamantine-terror-ironclad-champions"
const CSV_UPSTOPPABLE := "upstoppable-advance-ironclad-champions"
const CSV_EMPEROR := "for-the-emperor-tacticus-firestorm-force"

const IDS: Array = [CSV_GUNSHIP, CSV_IMPACT, CSV_PUSH, CSV_HAIL, CSV_SUPPRESSION, CSV_STAND,
	CSV_DOMINATION, CSV_MASTERFUL, CSV_ADAMANTINE, CSV_UPSTOPPABLE, CSV_EMPEROR]

const IMPLEMENTED: Dictionary = {
	CSV_GUNSHIP: true, CSV_IMPACT: true, CSV_PUSH: true, CSV_HAIL: true, CSV_SUPPRESSION: true,
	CSV_STAND: true, CSV_DOMINATION: true, CSV_MASTERFUL: true, CSV_ADAMANTINE: true,
	CSV_UPSTOPPABLE: true, CSV_EMPEROR: true,
}

const AI_KIND: Dictionary = {
	CSV_GUNSHIP: "utility", CSV_IMPACT: "offensive", CSV_PUSH: "utility", CSV_HAIL: "offensive",
	CSV_SUPPRESSION: "offensive", CSV_STAND: "utility", CSV_DOMINATION: "offensive",
	CSV_MASTERFUL: "utility", CSV_ADAMANTINE: "offensive", CSV_UPSTOPPABLE: "utility",
	CSV_EMPEROR: "utility",
}

const W_FIGHT_END := "fight_phase_end"
const W_FIGHT_START := "fight_phase_start"
const W_ENDED_CHARGE := "unit_ended_charge_move"
const W_HAS_SHOT := "unit_has_shot"
const W_ENEMY_HAS_SHOT := "enemy_has_shot"
const W_MOVEMENT_END := "movement_phase_end"
const W_ENEMY_ENDED_MOVE := "enemy_ended_move"
const W_SELECTED_TO_MOVE := "unit_selected_to_move"
const W_DECLARES_CHARGE := "unit_declares_charge"
const W_COMMAND := "command_phase_main"
const W_COMMAND_OPPONENT := "command_phase_opponent"   # new window (WP-M3b): the opponent's Command phase

const FLAG_MOBILE := "ork11e_mobile"                      # the engine's MOBILE grant (13.06 terrain checks)
const FLAG_UPSTOPPABLE := "sm11e_upstoppable_advance"     # marker: this stratagem wrote the grant
const FLAG_UPSTOPPABLE_HAD := "sm11e_upstoppable_had_mobile"
const FLAG_NO_EMBARK := "sm11e_no_embark"                 # turn stamp: not eligible to embark this turn
const FLAG_CANNOT_CHARGE := "cannot_charge"               # engine flag, cleared at the end of the turn
const FLAG_SUPPRESSED := "sm11e_suppressed"               # on the ENEMY: {player, round}
const FLAG_DOMINATION_TARGET := "sm11e_domination_target" # on the shooter: the enemy it suppressed
const FLAG_EMPEROR := "sm11e_for_the_emperor"             # turn stamp: +1 OC this turn
const FLAG_STAND := "sm11e_stand_unyielding"              # marker: objective id secured

const KW_AA := "ADEPTUS ASTARTES"
const PUSH_INCHES := 5.0
const MASTERFUL_RANGE_IN := 8.0
const IMPACT_PASS := 3
const MOVE_TYPES: Array = ["normal", "advance", "fall_back"]


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if _check(csv, player, str(uid), window_id, ctx).ok:
			out.append(Common.target_entry(str(uid), _entry_extra(csv, player, str(uid), window_id, ctx)))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	if target_unit_id == "":
		return _no("%s needs a target unit" % strat.get("name", "?"))
	var window_id := str(ctx.get("window_id", ""))
	var c := _check(csv, player, target_unit_id, window_id, ctx)
	if not c.ok:
		return c
	var sec := str(ctx.get("secondary_id", ""))
	if sec != "":
		var head := Common.head_id(target_unit_id)
		match csv:
			CSV_IMPACT:
				if not sec in Common.engaged_enemy_ids(head) and not Common.head_id(sec) in _engaged_enemy_heads(head):
					return _no("ARMOURED IMPACT: %s is not engaged with your unit" % Common.unit_name(sec))
			CSV_SUPPRESSION, CSV_DOMINATION:
				if not Common.head_id(sec) in _hit_enemy_heads(player, ctx):
					return _no("%s: %s was not hit by those attacks" % [_name(csv), Common.unit_name(sec)])
			CSV_STAND:
				if not sec in controlled_objectives(head, player):
					return _no("STAND UNYIELDING: your unit is not controlling %s" % Common.objective_label(sec))
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_GUNSHIP:
			_log(player, "GUNSHIP EXTRACTION: %s is placed in strategic reserves" % label)
			return {"diffs": [], "followup": {"type": "strategic_reserves", "unit_id": head, "source": "GUNSHIP EXTRACTION"}}
		CSV_IMPACT:
			return _armoured_impact(player, head, ctx)
		CSV_PUSH:
			var stamp := turn_stamp()
			var pd: Array = Common.set_flag_diffs(group, FLAG_CANNOT_CHARGE, true)
			pd.append_array(Common.set_flag_diffs(group, FLAG_NO_EMBARK, stamp))
			_log(player, "PURGATION PUSH: %s can make a normal move of up to 5\" that must end within range of an objective — it is not eligible to declare a charge or embark this turn" % label)
			return {"diffs": pd, "followup": {"type": "reactive_normal_move", "unit_id": head, "max_inches": PUSH_INCHES,
				"end_condition": "within_objective_range", "source": "PURGATION PUSH"}}
		CSV_HAIL:
			var forced := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			_log(player, "HAIL OF VENGEANCE: %s shoots (normal shooting) and can only target %s" % [label, Common.group_label(forced)])
			return {"diffs": [], "followup": {"type": "shoot", "unit_id": head, "forced_target_id": forced, "source": "HAIL OF VENGEANCE"}}
		CSV_SUPPRESSION:
			var enemy := _pick_hit(player, ctx)
			if enemy == "":
				Common.log_error("SMCodexBAction: SUPPRESSION VOLLEYS — no enemy unit hit by %s's attacks; no roll" % head)
				return []
			return _battle_shock_diffs(player, [enemy], "SUPPRESSION VOLLEYS")
		CSV_STAND:
			return _stand_apply(head, player, ctx)
		CSV_DOMINATION:
			var target := _pick_hit(player, ctx)
			if target == "":
				Common.log_error("SMCodexBAction: DOMINATION FIRE — no enemy unit hit by %s's attacks; nothing suppressed" % head)
				return []
			var dd: Array = Common.set_flag_diffs(Common.attached_group_ids(target), FLAG_SUPPRESSED,
				{"player": player, "round": Common.battle_round()})
			dd.append_array(Common.set_flag_diffs(group, FLAG_DOMINATION_TARGET, target))
			_log(player, "DOMINATION FIRE: %s is suppressed until the start of Player %d's next turn — its attacks have -1 to hit" % [Common.group_label(target), player])
			return dd
		CSV_MASTERFUL:
			var tactical := _doctrine(head, "tactical")
			var inches := 6
			var roll := 0
			if not tactical:
				roll = int(Common.roll_dice(1, 6)[0])
				inches = roll
			_log(player, "MASTERFUL TACTICS: %s %s — it can make a normal move of up to %d\"" % [label,
				"has the tactical doctrine" if tactical else "rolls D6 = %d" % roll, inches])
			return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": head,
				"max_inches": float(inches), "roll": roll, "source": "MASTERFUL TACTICS"}}
		CSV_ADAMANTINE:
			var enemies := _engaged_enemy_heads(head)
			if enemies.is_empty():
				Common.log_error("SMCodexBAction: ADAMANTINE TERROR — no enemy unit engaged with %s; no roll" % head)
				return []
			return _battle_shock_diffs(player, enemies, "ADAMANTINE TERROR")
		CSV_UPSTOPPABLE:
			var diffs: Array = []
			for gid in group:
				var had := bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_MOBILE, false))
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_UPSTOPPABLE_HAD], "value": had})
			diffs.append_array(Common.set_flag_diffs(group, FLAG_MOBILE, true))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_UPSTOPPABLE, true))
			_log(player, "UPSTOPPABLE ADVANCE: %s has MOBILE (moves through dense terrain) this phase" % label)
			return diffs
		CSV_EMPEROR:
			var ed: Array = Common.set_flag_diffs(group, FLAG_EMPEROR, turn_stamp())
			_log(player, "FOR THE EMPEROR!: %s has +1 OC until the end of the turn" % label)
			var wid := str(ctx.get("window_id", ""))
			if wid == W_COMMAND or wid == W_COMMAND_OPPONENT:
				# Offer the Command-phase window again: another stratagem may still be used.
				return {"diffs": ed, "followup": {"type": "ork11e_reoffer", "player": player, "window_id": wid,
					"ctx": {"phase": "command"}}}
			return ed
	Common.log_error("SMCodexBAction: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	var units: Dictionary = Common.state().get("units", {})
	match csv:
		CSV_UPSTOPPABLE:
			for gid in group:
				var f = units.get(str(gid), {}).get("flags", null)
				if typeof(f) != TYPE_DICTIONARY:
					continue
				if f.has(FLAG_UPSTOPPABLE) and not bool(f.get(FLAG_UPSTOPPABLE_HAD, false)):
					f.erase(FLAG_MOBILE)
				f.erase(FLAG_UPSTOPPABLE)
				f.erase(FLAG_UPSTOPPABLE_HAD)
			Common.log_info("SMCodexBAction: UPSTOPPABLE ADVANCE (MOBILE) expired on %s" % str(group))
		CSV_EMPEROR:
			Common.erase_flags(group, [FLAG_EMPEROR])
			Common.log_info("SMCodexBAction: FOR THE EMPEROR! (+1 OC) expired on %s" % str(group))
		CSV_DOMINATION:
			# The phase-scoped expiry fires at the end of the Shooting phase; the
			# suppression itself lasts until the start of your next turn
			# (suppressed_active is self-expiring) — only the marker goes.
			Common.erase_flags(group, [FLAG_DOMINATION_TARGET])
		CSV_STAND:
			# The secured objective itself persists (14.03) — only the marker goes.
			Common.erase_flags(group, [FLAG_STAND])
	# GUNSHIP EXTRACTION / ARMOURED IMPACT / PURGATION PUSH (turn-stamped flags) /
	# HAIL OF VENGEANCE / SUPPRESSION VOLLEYS / MASTERFUL TACTICS / ADAMANTINE
	# TERROR leave nothing that the end of the phase must clear.


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(_strat: Dictionary, _variant_id: String) -> String:
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, _window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	match csv:
		CSV_GUNSHIP:
			# Redeploy a unit that is doing nothing: no enemy near, no objective held.
			if Common.battle_round() >= 5:
				return 0.0
			if Common.nearest_enemy_inches(Common.group_union(uid)) <= 12.0 or Common.group_in_range_of_any_objective(uid):
				return 0.0
			return 2.1
		CSV_IMPACT:
			# Expected mortal wounds: engaged models x 2/3.
			var best := 0
			for eid in _engaged_enemy_heads(uid):
				best = maxi(best, _models_engaged_with(uid, str(eid)).size())
			return 1.2 + 0.4 * float(best) if best >= 2 else 0.0
		CSV_PUSH:
			var gap := _objective_gap_inches(uid)
			return 2.2 if gap > 0.0 and gap <= PUSH_INCHES else 0.0
		CSV_HAIL:
			var n := _weapons_in_range(uid, Common.head_id(str(ctx.get("attacker_unit_id", "")))).size()
			return 0.0 if n == 0 else 3.0 + minf(1.0, 0.25 * float(n))
		CSV_SUPPRESSION:
			var e := _pick_hit(player, ctx)
			return 2.1 if e != "" and not Common.is_battle_shocked(Common.unit(e)) and not _shock_immune(e) else 0.0
		CSV_STAND:
			return 2.3 if not controlled_objectives(uid, player).is_empty() else 0.0
		CSV_DOMINATION:
			var d := _pick_hit(player, ctx)
			if d == "" or Common.is_battle_shocked(Common.unit(d)):
				return 0.0
			# -1 to hit on a unit that will attack before the start of your next turn.
			return 2.1 if Common.group_points(d) >= 80 else 0.0
		CSV_MASTERFUL:
			var g := _objective_gap_inches(uid)
			return 2.2 if g > 0.0 and g <= (6.0 if _doctrine(uid, "tactical") else 2.0) else 0.0
		CSV_ADAMANTINE:
			for eid in _engaged_enemy_heads(uid):
				if not Common.is_battle_shocked(Common.unit(str(eid))) and not _shock_immune(str(eid)):
					return 2.2
			return 0.0
		CSV_UPSTOPPABLE:
			var dest := ""
			var targets: Array = ctx.get("target_unit_ids", [])
			if not targets.is_empty():
				dest = str(targets[0])
			return 2.2 if _mobile_helps(uid, dest) else 0.0
		CSV_EMPEROR:
			# +1 OC matters on a contested objective (enemy within 6" of the unit).
			if not Common.group_in_range_of_any_objective(uid):
				return 0.0
			return 2.1 if Common.nearest_enemy_inches(Common.group_union(uid)) <= 9.0 else 0.0
	return 0.0


# ===========================================================================
# Engine consumers (SMCodexB hooks)
# ===========================================================================

## "<battle round>:<active player>" — a flag stamped with it lasts the turn.
static func turn_stamp() -> String:
	return "%d:%d" % [Common.battle_round(), Common.active_player()]

## FOR THE EMPEROR!: +1 OC this turn.
static func oc_bonus(unit: Dictionary) -> int:
	var s = unit.get("flags", {}).get(FLAG_EMPEROR, null)
	return 1 if s != null and str(s) == turn_stamp() else 0

## PURGATION PUSH: not eligible to embark within a TRANSPORT this turn.
static func embark_blocked(unit: Dictionary) -> bool:
	var s = unit.get("flags", {}).get(FLAG_NO_EMBARK, null)
	return s != null and str(s) == turn_stamp()

## DOMINATION FIRE: is the unit suppressed right now? "Until the start of your
## next turn" (P = the player who used it in battle round R): active through
## the rest of round R and, in round R+1, until P's turn starts.
static func suppressed_active(unit: Dictionary) -> bool:
	var s = unit.get("flags", {}).get(FLAG_SUPPRESSED, null)
	if typeof(s) != TYPE_DICTIONARY:
		return false
	var p := int(s.get("player", 0))
	var r := int(s.get("round", 0))
	var now := Common.battle_round()
	if now == r:
		# Same round: P's own turn (when it was used) or the opponent's turn after it.
		return true
	return now == r + 1 and Common.active_player() != p

## Hit-roll modifier for the attacker's batch (merged into ork11e_ab_mods).
static func merge_attack_mods(m: Dictionary, actor: Dictionary) -> void:
	if suppressed_active(actor):
		m["hit_minus"] = true
		if not m.has("sources"):
			m["sources"] = []
		(m["sources"] as Array).append({"name": "Domination Fire", "kind": "hit", "effect": "minus_one", "note": "attacker is suppressed"})


## The opponent's Command phase window entries (CommandPhase hook): only when
## the non-active player has an implemented stratagem in that window.
static func opponent_command_window_entries(active_player: int, has_window_strat: Callable) -> Array:
	var other := 2 if active_player == 1 else 1
	if not bool(has_window_strat.call(other, W_COMMAND_OPPONENT)):
		return []
	return [{"player": other, "window_id": W_COMMAND_OPPONENT, "ctx": {"phase": "command",
		"header": "Player %d's Command phase — your stratagems" % active_player}}]


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_GUNSHIP:
			return Common.friendly_heads(player) if window_id == W_FIGHT_END else []
		CSV_IMPACT:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_ENDED_CHARGE else []
		CSV_PUSH, CSV_SUPPRESSION, CSV_DOMINATION:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_HAS_SHOT else []
		CSV_HAIL:
			if window_id != W_ENEMY_HAS_SHOT:
				return []
			var out: Array = []
			for tid in ctx.get("destroyed_unit_ids", []):
				var h := Common.head_id(str(tid))
				if h != "" and not h in out:
					out.append(h)
			return out
		CSV_STAND:
			return Common.friendly_heads(player) if window_id == W_MOVEMENT_END else []
		CSV_MASTERFUL:
			return Common.friendly_heads(player) if window_id == W_ENEMY_ENDED_MOVE else []
		CSV_ADAMANTINE:
			return Common.friendly_heads(player) if window_id == W_FIGHT_START else []
		CSV_UPSTOPPABLE:
			if window_id != W_SELECTED_TO_MOVE and window_id != W_DECLARES_CHARGE:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
		CSV_EMPEROR:
			return Common.friendly_heads(player) if window_id == W_COMMAND or window_id == W_COMMAND_OPPONENT else []
	return []


static func _entry_extra(csv: String, player: int, unit_id: String, _window_id: String, ctx: Dictionary) -> Dictionary:
	var opts: Array = []
	match csv:
		CSV_IMPACT:
			for eid in _engaged_enemy_heads(unit_id):
				opts.append({"id": str(eid), "label": "%s (%d of your models engaged)" % [Common.group_label(str(eid)), _models_engaged_with(unit_id, str(eid)).size()]})
			opts.sort_custom(func(a, b): return int(str(a.label).get_slice("(", 1).to_int()) > int(str(b.label).get_slice("(", 1).to_int()))
			return {"secondary": {"kind": "unit", "prompt": "ARMOURED IMPACT: select one enemy unit engaged with %s — one D6 per engaged model, 3+ = 1 mortal wound" % Common.unit_name(unit_id), "options": opts}}
		CSV_SUPPRESSION, CSV_DOMINATION:
			for eid in _hit_enemy_heads(player, ctx):
				opts.append({"id": str(eid), "label": Common.group_label(str(eid))})
			var what := "it makes a battle-shock roll at -1" if csv == CSV_SUPPRESSION else "it is suppressed (-1 to hit) until the start of your next turn"
			return {"secondary": {"kind": "unit", "prompt": "%s: select one enemy unit hit by those attacks — %s" % [_name(csv), what], "options": opts}}
		CSV_STAND:
			for oid in controlled_objectives(unit_id, player):
				opts.append({"id": str(oid), "label": Common.objective_label(str(oid))})
			return {"secondary": {"kind": "objective", "prompt": "STAND UNYIELDING: select one objective %s is controlling — it becomes secured" % Common.unit_name(unit_id), "options": opts}}
	return {}


static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var sname := _name(csv)
	var head := Common.head_id(target_unit_id)
	var u := Common.unit(head)
	if u.is_empty():
		return _no("%s needs a target unit" % sname)
	if int(u.get("owner", 0)) != player:
		return _no("%s must target a unit from your army" % sname)
	if not Common.is_on_battlefield(u):
		return _no("%s: that unit is not on the battlefield" % sname)
	var my_turn := Common.active_player() == player
	match csv:
		CSV_GUNSHIP:
			if not (Common.group_has_keyword(head, KW_AA) and Common.group_has_keyword(head, "TERMINATOR")):
				return _no("GUNSHIP EXTRACTION can only target an ADEPTUS ASTARTES TERMINATOR unit")
			if my_turn:
				return _no("GUNSHIP EXTRACTION: only at the end of your opponent's Fight phase")
			if Common.is_engaged(head):
				return _no("GUNSHIP EXTRACTION can only target an unengaged unit")
		CSV_IMPACT:
			if not Common.group_has_keyword(head, "GRAVIS"):
				return _no("ARMOURED IMPACT can only target a GRAVIS unit")
			if not my_turn:
				return _no("ARMOURED IMPACT: only in your Charge phase")
			if _engaged_enemy_heads(head).is_empty():
				return _no("ARMOURED IMPACT: your unit is not engaged with an enemy unit")
		CSV_PUSH:
			if not Common.group_has_keyword(head, "GRAVIS"):
				return _no("PURGATION PUSH can only target a GRAVIS unit")
			if not my_turn:
				return _no("PURGATION PUSH: only in your Shooting phase")
			if Common.is_engaged(head):
				return _no("PURGATION PUSH: your unit must be unengaged")
			var gap := _objective_gap_inches(head)
			if gap > PUSH_INCHES + 0.001:
				return _no("PURGATION PUSH: no objective within reach of a 5\" move (the move must end within range of one)")
		CSV_HAIL:
			if not Common.group_has_keyword(head, KW_AA):
				return _no("HAIL OF VENGEANCE can only target an ADEPTUS ASTARTES unit")
			if my_turn:
				return _no("HAIL OF VENGEANCE: only in your opponent's Shooting phase")
			if ctx.has("destroyed_unit_ids") and not Common.group_in(head, ctx.get("destroyed_unit_ids", [])):
				return _no("HAIL OF VENGEANCE: those attacks destroyed no model in that unit")
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var a := Common.unit(attacker)
			if a.is_empty() or not Common.is_on_battlefield(a) or int(a.get("owner", 0)) == player:
				return _no("HAIL OF VENGEANCE: the enemy unit that shot is no longer on the battlefield")
			if Common.is_engaged(head):
				return _no("HAIL OF VENGEANCE: normal shooting needs an unengaged unit")
			if _weapons_in_range(head, attacker).is_empty():
				return _no("HAIL OF VENGEANCE: no ranged weapon of that unit can target %s" % Common.unit_name(attacker))
		CSV_SUPPRESSION, CSV_DOMINATION:
			if csv == CSV_SUPPRESSION and not Common.group_has_keyword(head, "GRAVIS"):
				return _no("SUPPRESSION VOLLEYS can only target a GRAVIS unit")
			if csv == CSV_DOMINATION and not Common.group_has_keyword(head, KW_AA):
				return _no("DOMINATION FIRE can only target an ADEPTUS ASTARTES unit")
			if not my_turn:
				return _no("%s: only in your Shooting phase" % sname)
			var selected := str(ctx.get("unit_id", ""))
			if selected != "" and Common.head_id(selected) != head:
				return _no("%s must target the unit that has shot" % sname)
			if ctx.has("hit_unit_ids") and _hit_enemy_heads(player, ctx).is_empty():
				return _no("%s: those attacks hit no enemy unit" % sname)
		CSV_STAND:
			if not Common.group_has_keyword(head, "GRAVIS"):
				return _no("STAND UNYIELDING can only target a GRAVIS unit")
			if not my_turn:
				return _no("STAND UNYIELDING: only at the end of your Movement phase")
			if controlled_objectives(head, player).is_empty():
				return _no("STAND UNYIELDING: %s is not controlling an objective (that is not already secured)" % Common.unit_name(head))
		CSV_MASTERFUL:
			if not (Common.group_has_keyword(head, KW_AA) and Common.group_has_any_keyword(head, ["INFANTRY", "MOUNTED"])):
				return _no("MASTERFUL TACTICS can only target an ADEPTUS ASTARTES INFANTRY/MOUNTED unit")
			if my_turn:
				return _no("MASTERFUL TACTICS: only in your opponent's Movement phase")
			if Common.is_engaged(head):
				return _no("MASTERFUL TACTICS: the unit must be unengaged")
			var enemy := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			if ctx.has("enemy_unit_id"):
				if enemy == "" or Common.unit(enemy).is_empty():
					return _no("MASTERFUL TACTICS: no enemy unit ended a move")
				if Common.group_distance_inches(head, enemy) > MASTERFUL_RANGE_IN + 0.001:
					return _no("MASTERFUL TACTICS: the enemy unit did not end its move within 8\" of that unit")
		CSV_ADAMANTINE:
			if not Common.group_has_keyword(head, "DREADNOUGHT"):
				return _no("ADAMANTINE TERROR can only target a DREADNOUGHT unit")
			if _engaged_enemy_heads(head).is_empty():
				return _no("ADAMANTINE TERROR: no enemy unit is engaged with your unit")
		CSV_UPSTOPPABLE:
			if not Common.group_has_keyword(head, "DREADNOUGHT"):
				return _no("UPSTOPPABLE ADVANCE can only target a DREADNOUGHT unit")
			if not my_turn:
				return _no("UPSTOPPABLE ADVANCE: only in your Movement or Charge phase")
			var selected_u := str(ctx.get("unit_id", ""))
			if selected_u != "" and Common.head_id(selected_u) != head:
				return _no("UPSTOPPABLE ADVANCE must target the unit that was selected to move / declared a charge")
			if window_id == W_SELECTED_TO_MOVE and ctx.has("move_type") and not str(ctx.get("move_type", "")) in MOVE_TYPES:
				return _no("UPSTOPPABLE ADVANCE: not for a %s move" % str(ctx.get("move_type", "")))
		CSV_EMPEROR:
			if not Common.group_has_keyword(head, "TACTICUS"):
				return _no("FOR THE EMPEROR! can only target a TACTICUS unit")
			if not Common.group_in_range_of_any_objective(head):
				return _no("FOR THE EMPEROR!: that unit is not within range of an objective")
			if window_id == W_COMMAND and not my_turn:
				return _no("FOR THE EMPEROR!: the Command phase window of the active player")
			if window_id == W_COMMAND_OPPONENT and my_turn:
				return _no("FOR THE EMPEROR!: the opponent's Command phase window")
	return {"ok": true, "reason": ""}


# ===========================================================================
# Effects
# ===========================================================================

static func _armoured_impact(player: int, head: String, ctx: Dictionary) -> Variant:
	var enemies := _engaged_enemy_heads(head)
	var enemy := Common.head_id(str(ctx.get("secondary_id", "")))
	if enemy == "" or not enemy in enemies:
		var best := -1
		for eid in enemies:
			var n := _models_engaged_with(head, str(eid)).size()
			if n > best:
				best = n
				enemy = str(eid)
	if enemy == "":
		Common.log_error("SMCodexBAction: ARMOURED IMPACT — %s is engaged with no enemy unit; no roll" % head)
		return []
	var n_models := _models_engaged_with(head, enemy).size()
	var rolls := Common.roll_dice(n_models, 6)
	var mw := 0
	for r in rolls:
		if int(r) >= IMPACT_PASS:
			mw += 1
	var res := _mortal_wounds(enemy, mw)
	var msg := "ARMOURED IMPACT: %s rolls %d D6 (one per model engaged with %s) %s — %d x 3+ = %d mortal wound(s), %d model(s) destroyed" % [
		Common.group_label(head), n_models, Common.group_label(enemy), str(rolls), mw, mw, int(res.casualties)]
	_log(player, msg)
	return res.diffs


## Battle-shock rolls at -1 for each unit (immune units make no roll).
static func _battle_shock_diffs(player: int, unit_ids: Array, source: String) -> Array:
	var diffs: Array = []
	var fam = Common.autoload("FactionAbilityManager")
	for eid in unit_ids:
		var line := "%s: %s" % [source, Common.group_label(str(eid))]
		if _shock_immune(str(eid)):
			line += " is immune to battle-shock — no roll"
		elif fam and fam.has_method("force_battle_shock_test"):
			var r: Dictionary = fam.force_battle_shock_test(str(eid), -1, source)
			diffs.append_array(r.get("diffs", []))
			line += " makes a battle-shock roll: %s -1 = %d vs Ld %d — %s" % [str(r.get("dice", [])), int(r.get("total", 0)),
				int(r.get("leadership", 0)), "passed" if bool(r.get("passed", true)) else "FAILED, battle-shocked"]
		_log(player, line)
	return diffs


static func _stand_apply(head: String, player: int, ctx: Dictionary) -> Array:
	var objs := controlled_objectives(head, player)
	var obj_id := str(ctx.get("secondary_id", ""))
	if obj_id == "" and not objs.is_empty():
		obj_id = str(objs[0])
	if obj_id == "" or not obj_id in objs:
		Common.log_error("SMCodexBAction: STAND UNYIELDING — %s controls no objective %s; nothing secured" % [head, obj_id])
		return []
	var mm = Common.mission_manager()
	# 14.03: secured by the ARMY (no source unit): it stays under the player's
	# control even if this unit leaves or is destroyed.
	mm.secure_objective(obj_id, player, "")
	_log(player, "STAND UNYIELDING: %s secures %s" % [Common.group_label(head), Common.objective_label(obj_id)])
	return Common.set_flag_diffs([head], FLAG_STAND, obj_id)


## Objectives the unit is controlling: within range of an objective its player
## controls, OC >= 1, not battle-shocked; excluding already-secured ones.
static func controlled_objectives(unit_id: String, player: int) -> Array:
	var out: Array = []
	var head := Common.head_id(unit_id)
	var u := Common.unit(head)
	if u.is_empty() or Common.is_battle_shocked(u):
		return out
	var oc := int(u.get("meta", {}).get("stats", {}).get("objective_control", 0))
	if oc <= 0:
		return out
	var mm = Common.mission_manager()
	for obj in Common.objectives():
		var oid := str(obj.get("id", ""))
		if oid == "":
			continue
		if mm and mm.has_method("is_objective_active") and not mm.is_objective_active(oid):
			continue
		if Common.objective_controller(oid) != player:
			continue
		if Common.objective_secured_by(oid) == player:
			continue
		if Common.group_in_objective_range(head, obj):
			out.append(oid)
	return out


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_GUNSHIP: return "GUNSHIP EXTRACTION"
		CSV_IMPACT: return "ARMOURED IMPACT"
		CSV_PUSH: return "PURGATION PUSH"
		CSV_HAIL: return "HAIL OF VENGEANCE"
		CSV_SUPPRESSION: return "SUPPRESSION VOLLEYS"
		CSV_STAND: return "STAND UNYIELDING"
		CSV_DOMINATION: return "DOMINATION FIRE"
		CSV_MASTERFUL: return "MASTERFUL TACTICS"
		CSV_ADAMANTINE: return "ADAMANTINE TERROR"
		CSV_UPSTOPPABLE: return "UPSTOPPABLE ADVANCE"
		CSV_EMPEROR: return "FOR THE EMPEROR!"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SMCodexBAction: " + msg)
	Common.game_log(player, msg)

static func _doctrine(unit_id: String, doctrine: String) -> bool:
	for gid in Common.attached_group_ids(Common.head_id(unit_id)):
		if Common.doctrine_active_id(str(gid), doctrine):
			return true
	return false

static func _shock_immune(unit_id: String) -> bool:
	var e := Common.unit(unit_id)
	var cp = load("res://phases/CommandPhase.gd")
	return cp != null and bool(cp._has_battle_shock_immunity(e.get("meta", {}).get("keywords", []), e.get("meta", {}).get("abilities", [])))

## Enemy (Attached) units engaged with any component of the unit, by head id.
static func _engaged_enemy_heads(unit_id: String) -> Array:
	var out: Array = []
	for eid in Common.engaged_enemy_ids(unit_id):
		var h := Common.head_id(str(eid))
		if h != "" and not h in out:
			out.append(h)
	return out

## The models (component:index keys) of `unit_id`'s Attached unit engaged with
## any component of `enemy_id` (engagement range, model to model).
static func _models_engaged_with(unit_id: String, enemy_id: String) -> Array:
	var out: Array = []
	var meas = Common.autoload("Measurement")
	var er_in := float(GameConstants.engagement_range_inches())
	for gid in Common.attached_group_ids(unit_id):
		var models: Array = Common.unit(str(gid)).get("models", [])
		for i in range(models.size()):
			var m: Dictionary = models[i]
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			var engaged := false
			for eg in Common.attached_group_ids(Common.head_id(enemy_id)):
				for em in Common.unit(str(eg)).get("models", []):
					if not em.get("alive", true) or em.get("position", null) == null:
						continue
					if meas and float(meas.model_to_model_distance_inches(m, em)) <= er_in + 0.001:
						engaged = true
						break
				if engaged:
					break
			if engaged:
				out.append("%s:%d" % [str(gid), i])
	return out

## Enemy units (heads) the shot hit — ctx.hit_unit_ids from the post-shot window.
static func _hit_enemy_heads(player: int, ctx: Dictionary) -> Array:
	var out: Array = []
	for tid in ctx.get("hit_unit_ids", []):
		var h := Common.head_id(str(tid))
		var hu := Common.unit(h)
		if hu.is_empty() or int(hu.get("owner", 0)) == player or h in out or not Common.is_on_battlefield(hu):
			continue
		out.append(h)
	return out

static func _pick_hit(player: int, ctx: Dictionary) -> String:
	var hit := _hit_enemy_heads(player, ctx)
	var sec := Common.head_id(str(ctx.get("secondary_id", "")))
	if sec != "" and sec in hit:
		return sec
	return str(hit[0]) if not hit.is_empty() else ""

static func _weapons_in_range(shooter_id: String, target_id: String) -> Array:
	var re = Common.rules()
	if re == null or not re.has_method("get_eligible_targets") or target_id == "":
		return []
	var elig: Dictionary = re.get_eligible_targets(shooter_id, Common.state())
	return elig.get(target_id, {}).get("weapons_in_range", [])

## Mortal wounds (06.02): the bodyguard first, spilling to the Attached
## unit's characters; FNP via RulesEngine.apply_mortal_wounds.
static func _mortal_wounds(unit_id: String, mw: int) -> Dictionary:
	var out := {"diffs": [], "casualties": 0}
	var re = Common.rules()
	var gs = Common.game_state()
	if re == null or gs == null or mw <= 0:
		return out
	var remaining := mw
	var first := true
	for gid in Common.attached_group_ids(Common.head_id(unit_id)):
		if remaining <= 0:
			break
		var u := Common.unit(str(gid))
		if u.is_empty() or not Common.is_alive(u):
			continue
		var pool := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				pool += int(m.get("current_wounds", m.get("wounds", 1)))
		var res: Dictionary = re.apply_mortal_wounds(str(gid), remaining, gs.create_snapshot(), re.make_rng() if first else null)
		first = false
		out.diffs.append_array(res.get("diffs", []))
		out.casualties += int(res.get("casualties", 0))
		var applied := int(res.get("wounds_applied", 0))
		remaining = maxi(0, applied - pool)
	return out

## Smallest distance any model of the unit still has to cover to be within
## range of an objective (0 = already within range; INF = none).
static func _objective_gap_inches(unit_id: String) -> float:
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

static func _centroid(unit_id: String) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				sum += Common._pos(m)
				n += 1
	return sum / float(n) if n > 0 else Vector2.INF

## UPSTOPPABLE ADVANCE AI: MOBILE only matters when dense terrain blocks the
## straight line to where the unit is going and MOBILE would let it through.
static func _mobile_helps(unit_id: String, dest_unit_id: String) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("can_move_through_11e"):
		return false
	var dest := dest_unit_id
	if dest == "":
		var best := INF
		for eid in Common.enemy_heads(int(Common.unit(unit_id).get("owner", 0))):
			var d := Common.group_distance_inches(unit_id, str(eid))
			if d < best:
				best = d
				dest = str(eid)
	if dest == "":
		return false
	var a := _centroid(unit_id)
	var b := _centroid(Common.head_id(dest))
	if a == Vector2.INF or b == Vector2.INF:
		return false
	var kws: Array = Common.unit(unit_id).get("meta", {}).get("keywords", [])
	var without: Dictionary = tm.can_move_through_11e(kws, a, b)
	if bool(without.get("allowed", true)):
		return false
	var with_mobile: Dictionary = tm.can_move_through_11e(kws, a, b, ["MOBILE"])
	return bool(with_mobile.get("allowed", false))
