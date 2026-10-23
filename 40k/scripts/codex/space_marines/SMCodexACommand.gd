extends RefCounted

## SMCodexACommand — Codex: Space Marines (11e) generic detachment
## stratagems used in YOUR Command phase or at the END OF YOUR Movement phase
## (WP-M3a). Dispatcher: SMCodex11e.gd. Rulings: RULINGS.md § WP-M3a.
##
##   ADAPTIVE STRATEGY    (Gladius, 1CP) command_phase_main: select one combat
##                        doctrine (dialog variant) — active for the unit until
##                        the start of your next Command phase. Written as the
##                        SWCommon per-unit doctrine keys (flags.sw11e_doctrine,
##                        flags.sw11e_doctrine_expires_player) + the marker
##                        sm11e_adaptive_strategy; read through
##                        SWCommon.doctrine_active (WP-M2a wires the effects).
##   MIGHT OF THE MACHINE SPIRIT (Ironstorm, 1CP) command_phase_main: until the
##                        start of your next Command phase the VEHICLE (excluding
##                        DEDICATED TRANSPORT/FLY/WALKER) ignores the harmful
##                        modifiers to its M, BS, hit rolls and wound rolls.
##   STORM AND SECURE     (Gauntlet, 1CP) movement_phase_end (your Movement
##                        phase): a TRANSPORT with an ADEPTUS ASTARTES BATTLELINE
##                        unit embarked secures one objective it is controlling
##                        (dialog secondary choice; MissionManager 14.03).
##   MORTIS SNARES        (Phobos Shadow Force, 1CP) movement_phase_end: an
##                        unengaged PHOBOS / SCOUT SQUAD unit controlling an
##                        objective snares it; the first enemy unit that ends a
##                        move within range of it rolls a D6 (2+: D6 mortal
##                        wounds) and the objective is no longer snared.
##                        state.factions[p].sm11e_snared_objectives = [obj_id];
##                        triggered from BasePhase.execute_action (every action
##                        that ends a move — SMCodex11e.on_action_applied).
##
## Both Command-phase stratagems re-offer the window after a use (follow-up
## ork11e_reoffer) so the other can still be used in the same phase.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_ADAPTIVE := "adaptive-strategy-gladius-task-force"
const CSV_MACHINE := "might-of-the-machine-spirit-ironstorm-spearhead"
const CSV_SECURE := "storm-and-secure-gauntlet-task-force"
const CSV_SNARES := "mortis-snares-phobos-shadow-force"

const IDS: Array = [CSV_ADAPTIVE, CSV_MACHINE, CSV_SECURE, CSV_SNARES]

const IMPLEMENTED: Dictionary = {
	CSV_ADAPTIVE: true, CSV_MACHINE: true, CSV_SECURE: true, CSV_SNARES: true,
}

const AI_KIND: Dictionary = {
	CSV_ADAPTIVE: "utility", CSV_MACHINE: "utility", CSV_SECURE: "utility", CSV_SNARES: "utility",
}

const W_COMMAND := "command_phase_main"
const W_MOVE_END := "movement_phase_end"

const FLAG_ADAPTIVE := "sm11e_adaptive_strategy"   # the doctrine this stratagem made active
const FLAG_DOCTRINE := "sw11e_doctrine"            # SWCommon per-unit doctrine key
const FLAG_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"
const FLAG_MACHINE := "sm11e_machine_spirit"
const FLAG_SECURED := "sm11e_storm_and_secure"     # marker: objective id secured
const FLAG_SNARED := "sm11e_mortis_snares"         # marker: objective id snared
const FK_SNARED := "sm11e_snared_objectives"       # state.factions[p] key: Array of objective ids

const KW_AA := "ADEPTUS ASTARTES"
const SNARE_PASS := 2

# RulesEngine.HitModifier.MINUS_ONE / WoundModifier.MINUS_ONE (pinned by the test).
const HIT_MINUS_ONE := 4
const WOUND_MINUS_ONE := 8

## Action types that STAGE a move (the move has not ended yet) — MORTIS SNARES
## waits for the action that ends it.
const STAGING_ACTIONS: Array = ["STAGE_MODEL_MOVE", "SET_MODEL_DEST", "UNDO_LAST_MODEL_MOVE", "RESET_UNIT_MOVE",
	"ORK11E_REACTIVE_MOVE_STAGE", "ORK11E_REACTIVE_MOVE_AUTO", "ORK11E_REACTIVE_MOVE_RESET", "DEBUG_MOVE"]

static var _snare_settled: Dictionary = {}    # unit_id -> position signature (last settled)
static var _snare_action_type := ""


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	var ok_window := W_COMMAND if csv in [CSV_ADAPTIVE, CSV_MACHINE] else W_MOVE_END
	if window_id != ok_window:
		return out
	for uid in Common.friendly_heads(player):
		if not _check(csv, player, str(uid), window_id, ctx).ok:
			continue
		var extra := {}
		match csv:
			CSV_ADAPTIVE:
				var variants: Array = []
				for d in Common.DOCTRINES:
					variants.append({"id": d, "label": "%s: %s" % [Common.group_label(str(uid)), str(Common.DOCTRINE_LABELS[d])],
						"cp_cost": int(strat.get("cp_cost", 1))})
				extra = {"require_variant": true, "ai_variant": ai_doctrine(str(uid)), "variants": variants}
			CSV_SECURE, CSV_SNARES:
				var opts: Array = []
				for oid in controlled_objectives(str(uid), player, csv == CSV_SECURE):
					opts.append({"id": str(oid), "label": Common.objective_label(str(oid))})
				var verb := "secured" if csv == CSV_SECURE else "snared"
				extra = {"secondary": {"kind": "objective", "prompt": "%s: select one objective %s is controlling — it becomes %s" % [
					_name(csv), Common.group_label(str(uid)), verb], "options": opts}}
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
	match csv:
		CSV_ADAPTIVE:
			var v := str(ctx.get("variant_id", ""))
			if v != "" and not v in Common.DOCTRINES:
				return _no("ADAPTIVE STRATEGY: unknown combat doctrine '%s'" % v)
		CSV_SECURE, CSV_SNARES:
			var sec := str(ctx.get("secondary_id", ""))
			if sec != "" and not sec in controlled_objectives(Common.head_id(target_unit_id), player, csv == CSV_SECURE):
				return _no("%s: %s is not controlling %s" % [_name(csv), Common.group_label(target_unit_id), Common.objective_label(sec)])
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	var diffs: Array = []
	match csv:
		CSV_ADAPTIVE:
			var doctrine := str(ctx.get("variant_id", ""))
			if not doctrine in Common.DOCTRINES:
				doctrine = ai_doctrine(head)
				Common.log_info("SMCodexACommand: ADAPTIVE STRATEGY used without a doctrine choice — %s picked" % doctrine)
			diffs.append_array(Common.set_flag_diffs(group, FLAG_DOCTRINE, doctrine))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_DOCTRINE_EXPIRES, player))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_ADAPTIVE, doctrine))
			_log(player, "ADAPTIVE STRATEGY: the %s is active for %s until the start of Player %d's next Command phase" % [
				str(Common.DOCTRINE_LABELS.get(doctrine, doctrine)), label, player])
		CSV_MACHINE:
			diffs.append_array(Common.set_flag_diffs(group, FLAG_MACHINE, true))
			_log(player, "MIGHT OF THE MACHINE SPIRIT: %s ignores modifiers to its M, BS, hit rolls and wound rolls until the start of Player %d's next Command phase" % [label, player])
		CSV_SECURE:
			var objs := controlled_objectives(head, player, true)
			var obj_id := str(ctx.get("secondary_id", ""))
			if obj_id == "" and not objs.is_empty():
				obj_id = str(objs[0])
			if obj_id == "" or not obj_id in objs:
				Common.log_error("SMCodexACommand: STORM AND SECURE — %s controls no objective %s; nothing secured" % [head, obj_id])
				return []
			# 14.03: secured by the ARMY (no source unit) — it stays under the
			# player's control even if the TRANSPORT leaves or is destroyed.
			var mm = Common.mission_manager()
			if mm and mm.has_method("secure_objective"):
				mm.secure_objective(obj_id, player, "")
			_log(player, "STORM AND SECURE: %s secures %s" % [label, Common.objective_label(obj_id)])
			return Common.set_flag_diffs([head], FLAG_SECURED, obj_id)
		CSV_SNARES:
			var sobjs := controlled_objectives(head, player, false)
			var sobj := str(ctx.get("secondary_id", ""))
			if sobj == "" and not sobjs.is_empty():
				sobj = str(sobjs[0])
			if sobj == "" or not sobj in sobjs:
				Common.log_error("SMCodexACommand: MORTIS SNARES — %s controls no objective %s; nothing snared" % [head, sobj])
				return []
			var snared: Array = snared_objectives(player).duplicate()
			if not sobj in snared:
				snared.append(sobj)
			diffs.append({"op": "set", "path": "factions.%d.%s" % [player, FK_SNARED], "value": snared})
			diffs.append_array(Common.set_flag_diffs([head], FLAG_SNARED, sobj))
			_log(player, "MORTIS SNARES: %s snares %s — the first enemy unit that ends a move within range of it rolls a D6 (2+: D6 mortal wounds)" % [label, Common.objective_label(sobj)])
			return diffs
		_:
			Common.log_error("SMCodexACommand: apply() called for unimplemented %s" % csv)
			return []
	if str(ctx.get("window_id", "")) == W_COMMAND:
		# Offer the Command-phase window again: the other stratagem (or another
		# Codex: Space Marines rule) may still be used this phase.
		return {"diffs": diffs, "followup": {"type": "ork11e_reoffer", "player": player, "window_id": W_COMMAND,
			"ctx": {"phase": "command"}}}
	return diffs


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var units: Dictionary = Common.state().get("units", {})
	var group := Common.attached_group_ids(unit_id)
	if not unit_id in group:
		group.append(unit_id)
	for gid in group:
		var f = units.get(str(gid), {}).get("flags", null)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		match csv:
			CSV_ADAPTIVE:
				if f.has(FLAG_ADAPTIVE):
					if str(f.get(FLAG_DOCTRINE, "")) == str(f.get(FLAG_ADAPTIVE, "")):
						f.erase(FLAG_DOCTRINE)
						f.erase(FLAG_DOCTRINE_EXPIRES)
					f.erase(FLAG_ADAPTIVE)
			CSV_MACHINE:
				f.erase(FLAG_MACHINE)
			CSV_SECURE:
				# The secured objective itself persists (14.03) — only the marker goes.
				f.erase(FLAG_SECURED)
			CSV_SNARES:
				# The snare persists until an enemy unit triggers it — only the marker goes.
				f.erase(FLAG_SNARED)
	Common.log_info("SMCodexACommand: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if str(strat.get("csv_id", "")) == CSV_ADAPTIVE:
		return str(Common.DOCTRINE_LABELS.get(variant_id, variant_id))
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, _window_id: String, _ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	var near := Common.nearest_enemy_inches(Common.group_union(uid))
	match csv:
		CSV_ADAPTIVE:
			var d := ai_doctrine(uid)
			if Common.doctrine_active_id(uid, d):
				return 0.0  # already active through the army-wide doctrine
			if d == "tactical":
				return 2.2 if Common.is_engaged(uid) else 0.0
			if d == "assault":
				return 2.2 if near > 6.0 and near <= 16.0 else 0.0
			return 2.1 if near <= 30.0 else 0.0
		CSV_MACHINE:
			# Worth it when the vehicle's attacks are penalised: its damaged
			# profile, or an enemy within 30" that has the benefit of cover.
			if not Common.group_has_ranged_weapons(uid):
				return 0.0
			if _is_damaged(uid):
				return 2.2
			return 2.1 if _enemy_in_cover_within(uid, 30.0) else 0.0
		CSV_SECURE:
			return 2.1 if not controlled_objectives(uid, player, true).is_empty() else 0.0
		CSV_SNARES:
			# A snare only bites when an enemy is close enough to come for it.
			if controlled_objectives(uid, player, false).is_empty():
				return 0.0
			return 2.1 if near <= 24.0 else 0.0
	return 0.0


## The doctrine the AI (and a use without a choice) picks for the unit —
## the GRIMNAR'S COMMAND heuristic (SWCodexCommand.ai_doctrine).
static func ai_doctrine(unit_id: String) -> String:
	if Common.is_engaged(unit_id):
		return "tactical"
	var near := Common.nearest_enemy_inches(Common.group_union(unit_id))
	if Common.group_has_melee_weapons(unit_id) and near > 6.0 and near <= 16.0:
		return "assault"
	if Common.group_has_ranged_weapons(unit_id):
		return "devastator"
	return "assault"


# ===========================================================================
# Engine consumers (SMCodex11e hooks) — MIGHT OF THE MACHINE SPIRIT
# ===========================================================================

static func _machine(unit: Dictionary) -> bool:
	return bool(unit.get("flags", {}).get(FLAG_MACHINE, false))

## Hit rolls: ignore -1 to hit (the +1s are kept — "can ignore").
static func hit_bits(bits: int, attacker_unit: Dictionary, _target_unit: Dictionary, _is_melee: bool, ledger: Array) -> int:
	if not _machine(attacker_unit) or not (bits & HIT_MINUS_ONE):
		return bits
	ModifierLedger.note(ledger, "Might of the Machine Spirit", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED, "hit-roll penalties ignored")
	ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_HIT, [ModifierLedger.MINUS_ONE])
	return bits & ~HIT_MINUS_ONE

## Wound rolls: ignore -1 to wound.
static func wound_bits(bits: int, attacker_unit: Dictionary, _target_unit: Dictionary, _is_melee: bool, ledger: Array) -> int:
	if not _machine(attacker_unit) or not (bits & WOUND_MINUS_ONE):
		return bits
	ModifierLedger.note(ledger, "Might of the Machine Spirit", ModifierLedger.KIND_WOUND, ModifierLedger.IGNORED, "wound-roll penalties ignored")
	ModifierLedger.mark_ignored(ledger, ModifierLedger.KIND_WOUND, [ModifierLedger.MINUS_ONE])
	return bits & ~WOUND_MINUS_ONE

## BS: ignore BS worsening (benefit of cover, ...) — ranged attacks only (BS).
static func ignores_bs_worsening(attacker_unit: Dictionary, is_melee: bool) -> bool:
	return not is_melee and _machine(attacker_unit)

## M: ignore the harmful modifiers to the unit's Move characteristic.
static func ignores_move_penalties(unit: Dictionary) -> bool:
	return _machine(unit)


# ===========================================================================
# MORTIS SNARES — trigger
# ===========================================================================

static func snared_objectives(player: int) -> Array:
	var fac = Common.state().get("factions", {}).get(str(player), {})
	var v = fac.get(FK_SNARED, []) if fac is Dictionary else []
	return v if typeof(v) == TYPE_ARRAY else []


static func _any_snare() -> bool:
	return not snared_objectives(1).is_empty() or not snared_objectives(2).is_empty()


static func _signature(unit_id: String) -> String:
	var parts: PackedStringArray = []
	for m in Common.unit(unit_id).get("models", []):
		if not m.get("alive", true) or m.get("position", null) == null:
			parts.append("-")
			continue
		var p := Common._pos(m)
		parts.append("%d,%d" % [roundi(p.x * 10.0), roundi(p.y * 10.0)])
	return "|".join(parts)


static func _all_signatures() -> Dictionary:
	var out := {}
	for uid in Common.state().get("units", {}):
		out[str(uid)] = _signature(str(uid))
	return out


## Outermost action begins: remember the settled positions (once — a staged
## move keeps the baseline from before it started).
static func snare_baseline(action_type: String = "") -> void:
	_snare_action_type = action_type
	if not _any_snare():
		_snare_settled = {}
		return
	if _snare_settled.is_empty():
		_snare_settled = _all_signatures()


## Outermost action applied: trigger every snared objective an enemy unit
## ended a move within range of. Returns the applied diffs.
static func snare_detect(phase_name: String) -> Array:
	var applied: Array = []
	if not _any_snare():
		_snare_settled = {}
		return applied
	if _snare_action_type in STAGING_ACTIONS:
		return applied
	if _snare_settled.is_empty():
		_snare_settled = _all_signatures()
		return applied
	var now := _all_signatures()
	var moved: Array = []
	for uid in now:
		if _snare_settled.has(uid) and str(_snare_settled[uid]) != str(now[uid]):
			moved.append(uid)
		elif not _snare_settled.has(uid):
			moved.append(uid)
	_snare_settled = now
	if moved.is_empty():
		return applied
	for p in [1, 2]:
		var snared: Array = snared_objectives(p).duplicate()
		if snared.is_empty():
			continue
		var heads_done := {}
		for uid in moved:
			var head := Common.head_id(str(uid))
			if heads_done.has(head):
				continue
			heads_done[head] = true
			var hu := Common.unit(head)
			if int(hu.get("owner", 0)) == p or int(hu.get("owner", 0)) == 0 or not Common.is_on_battlefield(hu):
				continue
			for oid in snared.duplicate():
				var obj := Common.objective_by_id(str(oid))
				if obj.is_empty() or not Common.group_in_objective_range(head, obj):
					continue
				applied.append_array(_trigger_snare(p, str(oid), head, phase_name))
				snared.erase(oid)
				break
		if snared.size() != snared_objectives(p).size():
			var d := {"op": "set", "path": "factions.%d.%s" % [p, FK_SNARED], "value": snared}
			Common.phase_manager().apply_state_changes([d])
			applied.append(d)
	if not applied.is_empty():
		_snare_settled = _all_signatures()
	return applied


static func _trigger_snare(player: int, obj_id: String, enemy_head: String, phase_name: String) -> Array:
	var roll := int(Common.roll_dice(1, 6)[0])
	var label := Common.group_label(enemy_head)
	var diffs: Array = []
	if roll >= SNARE_PASS:
		var mw := int(Common.roll_dice(1, 6)[0])
		var re = Common.rules()
		var res: Dictionary = re.apply_mortal_wounds_to_unit(enemy_head, mw, Common.state(), re.make_rng())
		diffs = res.get("diffs", [])
		if not diffs.is_empty():
			Common.phase_manager().apply_state_changes(diffs)
		_log(player, "MORTIS SNARES: %s ended a move within range of %s (%s phase) — D6 = %d: it suffers D6 = %d mortal wounds (%d model(s) destroyed); the objective is no longer snared" % [
			label, Common.objective_label(obj_id), phase_name, roll, mw, int(res.get("casualties", 0))])
	else:
		_log(player, "MORTIS SNARES: %s ended a move within range of %s (%s phase) — D6 = %d: no effect; the objective is no longer snared" % [
			label, Common.objective_label(obj_id), phase_name, roll])
	return diffs


# ===========================================================================
# Checks / helpers
# ===========================================================================

static func _check(csv: String, player: int, target_unit_id: String, window_id: String, _ctx: Dictionary) -> Dictionary:
	var sname := _name(csv)
	var head := Common.head_id(target_unit_id)
	var u := Common.unit(head)
	if u.is_empty():
		return _no("%s needs a target unit" % sname)
	if int(u.get("owner", 0)) != player:
		return _no("%s must target a unit from your army" % sname)
	if not Common.is_on_battlefield(u):
		return _no("%s: that unit is not on the battlefield" % sname)
	if not Common.group_has_keyword(head, KW_AA):
		return _no("%s can only target an ADEPTUS ASTARTES unit" % sname)
	if Common.active_player() != player:
		return _no("%s: only in your own %s phase" % [sname, "Command" if csv in [CSV_ADAPTIVE, CSV_MACHINE] else "Movement"])
	match csv:
		CSV_ADAPTIVE:
			if not Common.has_combat_doctrines(u):
				return _no("ADAPTIVE STRATEGY: that unit does not have the Combat Doctrines ability")
		CSV_MACHINE:
			if not Common.group_has_keyword(head, "VEHICLE") or Common.group_has_any_keyword(head, ["DEDICATED TRANSPORT", "FLY", "WALKER"]):
				return _no("MIGHT OF THE MACHINE SPIRIT can only target an ADEPTUS ASTARTES VEHICLE unit (excluding DEDICATED TRANSPORT/FLY/WALKER units)")
		CSV_SECURE:
			if window_id != "" and window_id != W_MOVE_END:
				return _no("STORM AND SECURE is used at the end of your Movement phase")
			if not Common.group_has_keyword(head, "TRANSPORT"):
				return _no("STORM AND SECURE can only target an ADEPTUS ASTARTES TRANSPORT unit")
			if not _has_battleline_embarked(head):
				return _no("STORM AND SECURE: no ADEPTUS ASTARTES BATTLELINE unit is embarked within %s" % Common.unit_name(head))
			if controlled_objectives(head, player, true).is_empty():
				return _no("STORM AND SECURE: %s is not controlling an objective (that is not already secured)" % Common.unit_name(head))
		CSV_SNARES:
			if window_id != "" and window_id != W_MOVE_END:
				return _no("MORTIS SNARES is used at the end of your Movement phase")
			if not Common.group_has_any_keyword(head, ["PHOBOS", "SCOUT SQUAD"]):
				return _no("MORTIS SNARES can only target a PHOBOS / SCOUT SQUAD unit")
			if Common.is_engaged(head):
				return _no("MORTIS SNARES can only target an unengaged unit")
			if controlled_objectives(head, player, false).is_empty():
				return _no("MORTIS SNARES: %s is not controlling an objective (that is not already snared)" % Common.group_label(head))
	return {"ok": true, "reason": ""}


static func _has_battleline_embarked(transport_id: String) -> bool:
	var t := Common.unit(transport_id)
	var ids: Array = t.get("transport_data", {}).get("embarked_units", [])
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if str(u.get("embarked_in", "")) == transport_id and not str(uid) in ids:
			ids.append(str(uid))
	for eid in ids:
		var eu := Common.unit(str(eid))
		if not eu.is_empty() and Common.is_alive(eu) and Common.has_keyword(eu, KW_AA) and Common.has_keyword(eu, "BATTLELINE"):
			return true
	return false


## The objectives the (Attached) unit is CONTROLLING (ruling): it is within
## range with OC > 0 (not battle-shocked) and its player's level of control
## of that objective is higher than the opponent's right now (14.02, live —
## the stored control state is only refreshed at the end of a phase), or the
## objective is secured by its player. exclude_secured: objectives already
## secured by this player are not offered (STORM AND SECURE); MORTIS SNARES
## leaves out the ones already snared.
static func controlled_objectives(unit_id: String, player: int, exclude_secured: bool) -> Array:
	var out: Array = []
	var head := Common.head_id(unit_id)
	var u := Common.unit(head)
	if u.is_empty() or Common.is_battle_shocked(u):
		return out
	var mm = Common.mission_manager()
	var snared := snared_objectives(player)
	for obj in Common.objectives():
		var oid := str(obj.get("id", ""))
		if oid == "":
			continue
		if mm and mm.has_method("is_objective_active") and not mm.is_objective_active(oid):
			continue
		if not Common.group_in_objective_range(head, obj):
			continue
		if not _group_has_oc(head):
			continue
		if exclude_secured and Common.objective_secured_by(oid) == player:
			continue
		if not exclude_secured and oid in snared:
			continue
		var controls := Common.objective_secured_by(oid) == player
		if not controls and mm and mm.has_method("get_level_of_control"):
			var lvl: Dictionary = mm.get_level_of_control(obj)
			var mine := int(lvl.get(player, 0))
			var theirs := int(lvl.get(2 if player == 1 else 1, 0))
			controls = mine > theirs
		elif not controls:
			controls = Common.objective_controller(oid) == player
		if controls:
			out.append(oid)
	return out


static func _group_has_oc(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if int(Common.unit(str(gid)).get("meta", {}).get("stats", {}).get("objective_control", 0)) > 0:
			return true
	return false


static func _is_damaged(unit_id: String) -> bool:
	var u := Common.unit(unit_id)
	for a in u.get("meta", {}).get("abilities", []):
		var n := str(a.get("name", "")) if a is Dictionary else str(a)
		if not n.to_lower().begins_with("damaged:"):
			continue
		var digits := n.to_lower().replace("damaged:", "").strip_edges().split(" ")[0]  # "1-4"
		var hi := int(digits.split("-")[-1]) if "-" in digits else int(digits)
		var w := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				w += int(m.get("current_wounds", m.get("wounds", 1)))
		return w > 0 and w <= hi
	return false


static func _enemy_in_cover_within(unit_id: String, range_in: float) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("unit_has_cover_11e"):
		return false
	var shooter_model := {}
	for m in Common.unit(unit_id).get("models", []):
		if m.get("alive", true) and m.get("position", null) != null:
			shooter_model = m
			break
	if shooter_model.is_empty():
		return false
	var player := int(Common.unit(unit_id).get("owner", 0))
	for eid in Common.enemy_heads(player):
		if Common.group_distance_inches(unit_id, str(eid)) > range_in:
			continue
		if bool(tm.unit_has_cover_11e(Common.unit(str(eid)), shooter_model)):
			return true
	return false


static func _name(csv: String) -> String:
	match csv:
		CSV_ADAPTIVE: return "ADAPTIVE STRATEGY"
		CSV_MACHINE: return "MIGHT OF THE MACHINE SPIRIT"
		CSV_SECURE: return "STORM AND SECURE"
		CSV_SNARES: return "MORTIS SNARES"
	return csv


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _log(player: int, msg: String) -> void:
	Common.log_info("SMCodexACommand: " + msg)
	Common.game_log(player, msg)
