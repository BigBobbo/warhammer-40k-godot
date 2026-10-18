extends RefCounted

## CustodesCodexMovement — Codex: Adeptus Custodes (11e) stratagems of the
## MOVEMENT group (WP-C5): own-turn move windows, the opponent's-Movement
## reactive windows and the ingress window. Dispatcher: CustodesCodex11e.gd.
## Rulings: RULINGS.md § WP-C5.
##
## Windows served (hooks in phases/MovementPhase.gd unless noted):
##   unit_selected_to_move     UNSTOPPABLE MOMENTUM, AT SPEAR'S LENGTH,
##                             INEXORABLE, MANOEUVRE AND FIRE
##   unit_declares_charge      UNSTOPPABLE MOMENTUM (ChargePhase)
##   unit_ended_advance_move   UNCEASING ONSLAUGHT, UNLIMITED ENDURANCE,
##                             PRETERNATURAL RAPIDITY
##   enemy_ended_move          SWIFT AS THE EAGLE (x2), NO ESCAPE,
##                             RAPID REACTIONS
##   movement_phase_end        IMPENETRABLE BASTION
##   unit_selected_to_ingress  GOLDEN LIGHT OF THE MOIRAIDES
## Follow-ups (executed by the phase that opened the window):
##   reactive_normal_move {unit_id, max_inches, roll, source}  SWIFT AS THE EAGLE
##   cus11e_reactive_charge {unit_id, target_ids, source}       NO ESCAPE
##   cus11e_shoot {unit_id, forced_target_id, source}           RAPID REACTIONS
##
## Turn-long grants (cus11e_* flags — the Shooting phase's effect_* wipe keeps
## them) are read by EffectPrimitives' has_effect_advance_and_charge /
## advance_and_shoot / fall_back_and_shoot / fall_back_and_charge through
## CustodesCodex11e.grants(...).

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const IDS: Array = [
	"unstoppable-momentum-might-of-the-moritoi",
	"unceasing-onslaught-might-of-the-moritoi",
	"unlimited-endurance-guardians-of-the-throne",
	"preternatural-rapidity-dread-host",
	"swift-as-the-eagle-guardians-of-the-throne",
	"swift-as-the-eagle-honoured-companions",
	"at-spears-length-solar-watch",
	"manoeuvre-and-fire-aquilan-shield",
	"inexorable-solar-watch",
	"impenetrable-bastion-emperors-chosen",
	"no-escape-shadowkeepers",
	"rapid-reactions-aquilan-shield",
	"golden-light-of-the-moiraides-dread-host",
]

const IMPLEMENTED: Dictionary = {
	"unstoppable-momentum-might-of-the-moritoi": true,
	"unceasing-onslaught-might-of-the-moritoi": true,
	"unlimited-endurance-guardians-of-the-throne": true,
	"preternatural-rapidity-dread-host": true,
	"swift-as-the-eagle-guardians-of-the-throne": true,
	"swift-as-the-eagle-honoured-companions": true,
	"at-spears-length-solar-watch": true,
	"manoeuvre-and-fire-aquilan-shield": true,
	"inexorable-solar-watch": true,
	"impenetrable-bastion-emperors-chosen": true,
	"no-escape-shadowkeepers": true,
	"rapid-reactions-aquilan-shield": true,
	"golden-light-of-the-moiraides-dread-host": true,
}

const AI_KIND: Dictionary = {
	"unstoppable-momentum-might-of-the-moritoi": "utility",
	"unceasing-onslaught-might-of-the-moritoi": "utility",
	"unlimited-endurance-guardians-of-the-throne": "utility",
	"preternatural-rapidity-dread-host": "utility",
	"swift-as-the-eagle-guardians-of-the-throne": "defensive",
	"swift-as-the-eagle-honoured-companions": "defensive",
	"at-spears-length-solar-watch": "utility",
	"manoeuvre-and-fire-aquilan-shield": "utility",
	"inexorable-solar-watch": "utility",
	"impenetrable-bastion-emperors-chosen": "utility",
	"no-escape-shadowkeepers": "utility",
	"rapid-reactions-aquilan-shield": "utility",
	"golden-light-of-the-moiraides-dread-host": "defensive",
}

const KW_CUSTODES := "ADEPTUS CUSTODES"

const W_SELECTED_TO_MOVE := "unit_selected_to_move"
const W_DECLARES_CHARGE := "unit_declares_charge"
const W_ENDED_ADVANCE := "unit_ended_advance_move"
const W_ENEMY_ENDED_MOVE := "enemy_ended_move"
const W_PHASE_END := "movement_phase_end"
const W_INGRESS := "unit_selected_to_ingress"

# Flags
const FLAG_MOBILE := "ork11e_mobile"                       # the engine's MOBILE-grant flag (Movement/Charge 13.06 terrain checks)
const FLAG_UNSTOPPABLE := "cus11e_unstoppable_momentum"    # marker: UNSTOPPABLE MOMENTUM set FLAG_MOBILE
const FLAG_UNCEASING := "cus11e_unceasing_onslaught"       # ranged [ASSAULT] + advance-and-charge (turn)
const FLAG_UNLIMITED := "cus11e_unlimited_endurance"       # ranged [ASSAULT] + advance-and-charge (turn)
const FLAG_PRETERNATURAL := "cus11e_preternatural_rapidity" # advance-and-charge (turn)
const FLAG_SPEARS_LENGTH := "cus11e_at_spears_length"      # fall-back-and-shoot (turn)
const FLAG_MANOEUVRE := "cus11e_manoeuvre_and_fire"        # fall-back-and-shoot + fall-back-and-charge (turn)
const FLAG_INEXORABLE := "cus11e_inexorable"               # ignore harmful M / advance / charge modifiers (turn)
const FLAG_BASTION := "cus11e_impenetrable_bastion"        # marker: objective id secured
const FLAG_NO_ESCAPE := "cus11e_no_escape"                 # marker: the charge flags it wrote (expiry)
const FLAG_GOLDEN_LIGHT := "cus11e_golden_light"           # -1 to hit for attacks that target it; no snap shooting at it

const SWIFT_RANGE_IN := 8.0
const NO_ESCAPE_RANGE_IN := 6.0
const NO_ESCAPE_MAX_TARGET_IN := 12.0


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if not _check(csv, player, str(uid), window_id, ctx).ok:
			continue
		out.append(Common.target_entry(str(uid), _entry_extra(csv, str(uid), player, ctx)))
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
	if csv == "impenetrable-bastion-emperors-chosen":
		var sec := str(ctx.get("secondary_id", ""))
		if sec != "" and not sec in controlled_objectives(Common.head_id(target_unit_id), player):
			return _no("IMPENETRABLE BASTION: %s is not controlling %s" % [Common.unit_name(target_unit_id), Common.objective_label(sec)])
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		"unstoppable-momentum-might-of-the-moritoi":
			var d: Array = Common.set_flag_diffs(group, FLAG_MOBILE, true)
			d.append_array(Common.set_flag_diffs(group, FLAG_UNSTOPPABLE, true))
			_log(player, "UNSTOPPABLE MOMENTUM: %s has MOBILE (this phase)" % label)
			return d
		"unceasing-onslaught-might-of-the-moritoi":
			_log(player, "UNCEASING ONSLAUGHT: %s's ranged attacks have [ASSAULT] and its advance move does not prevent it from declaring a charge (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_UNCEASING, true)
		"unlimited-endurance-guardians-of-the-throne":
			_log(player, "UNLIMITED ENDURANCE: %s's ranged attacks have [ASSAULT] and its advance move does not prevent it from declaring a charge (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_UNLIMITED, true)
		"preternatural-rapidity-dread-host":
			_log(player, "PRETERNATURAL RAPIDITY: %s's advance move does not prevent it from declaring a charge (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_PRETERNATURAL, true)
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions":
			var roll := int(Common.roll_dice(1, 3)[0])
			var cap := float(roll + 3)
			_log(player, "SWIFT AS THE EAGLE: %s rolls D3 = %d — it can make a normal move of up to %d\"" % [label, roll, roll + 3])
			return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": head, "max_inches": cap,
				"roll": roll, "source": "SWIFT AS THE EAGLE", "goal": "", "away_from_unit_id": str(ctx.get("enemy_unit_id", ""))}}
		"at-spears-length-solar-watch":
			_log(player, "AT SPEAR'S LENGTH: %s's fall-back move does not prevent it from shooting (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_SPEARS_LENGTH, true)
		"manoeuvre-and-fire-aquilan-shield":
			_log(player, "MANOEUVRE AND FIRE: %s's fall-back move does not prevent it from shooting or declaring a charge (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_MANOEUVRE, true)
		"inexorable-solar-watch":
			_log(player, "INEXORABLE: %s ignores modifiers to its M, advance rolls and charge rolls (this turn)" % label)
			return Common.set_flag_diffs(group, FLAG_INEXORABLE, true)
		"impenetrable-bastion-emperors-chosen":
			return _bastion_apply(head, player, ctx)
		"no-escape-shadowkeepers":
			var enemy := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			_log(player, "NO ESCAPE: %s declares a charge against the units that fell back this phase" % label)
			return {"diffs": [], "followup": {"type": "cus11e_reactive_charge", "unit_id": head,
				"target_ids": fell_back_enemy_heads(player), "preferred_target_id": enemy, "source": "NO ESCAPE"}}
		"rapid-reactions-aquilan-shield":
			var foe := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			_log(player, "RAPID REACTIONS: %s shoots %s (normal shooting; it can only target that unit)" % [label, Common.group_label(foe)])
			return {"diffs": [], "followup": {"type": "cus11e_shoot", "unit_id": head, "forced_target_id": foe, "source": "RAPID REACTIONS"}}
		"golden-light-of-the-moiraides-dread-host":
			_log(player, "GOLDEN LIGHT OF THE MOIRAIDES: until the start of Player %d's next turn, attacks that target %s have -1 to hit and enemy units cannot target it with snap shooting" % [player, label])
			return Common.set_flag_diffs(group, FLAG_GOLDEN_LIGHT, true)
	Common.log_error("CustodesCodexMovement: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		"unstoppable-momentum-might-of-the-moritoi":
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f: Dictionary = units.get(str(gid), {}).get("flags", {})
				if f.has(FLAG_UNSTOPPABLE):
					f.erase(FLAG_MOBILE)
					f.erase(FLAG_UNSTOPPABLE)
		"unceasing-onslaught-might-of-the-moritoi":
			Common.erase_flags(group, [FLAG_UNCEASING])
		"unlimited-endurance-guardians-of-the-throne":
			Common.erase_flags(group, [FLAG_UNLIMITED])
		"preternatural-rapidity-dread-host":
			Common.erase_flags(group, [FLAG_PRETERNATURAL])
		"at-spears-length-solar-watch":
			Common.erase_flags(group, [FLAG_SPEARS_LENGTH])
		"manoeuvre-and-fire-aquilan-shield":
			Common.erase_flags(group, [FLAG_MANOEUVRE])
		"inexorable-solar-watch":
			Common.erase_flags(group, [FLAG_INEXORABLE])
		"impenetrable-bastion-emperors-chosen":
			# The secured objective itself persists (14.03) — only the marker goes.
			Common.erase_flags(group, [FLAG_BASTION])
		"no-escape-shadowkeepers":
			# "until the end of the turn" (curated duration): the charge flags the
			# reactive charge wrote in the opponent's turn end with it, so the unit
			# can still charge in its own turn.
			var units2: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f2: Dictionary = units2.get(str(gid), {}).get("flags", {})
				if bool(f2.get(FLAG_NO_ESCAPE, false)):
					f2.erase("charged_this_turn")
					f2.erase("fights_first")
				f2.erase(FLAG_NO_ESCAPE)
		"golden-light-of-the-moiraides-dread-host":
			Common.erase_flags(group, [FLAG_GOLDEN_LIGHT])
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions", "rapid-reactions-aquilan-shield":
			pass  # instant effects (follow-ups) — nothing to undo
	Common.log_info("CustodesCodexMovement: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	var nearest := Common.nearest_enemy_inches(Common.group_union(uid))
	match csv:
		"unceasing-onslaught-might-of-the-moritoi", "unlimited-endurance-guardians-of-the-throne", "preternatural-rapidity-dread-host":
			# Worth it when an enemy is within charge range after the advance.
			return 2.2 if nearest <= 12.0 else 0.0
		"manoeuvre-and-fire-aquilan-shield", "at-spears-length-solar-watch":
			return 2.0 if str(ctx.get("move_type", "")) == "fall_back" else 0.0
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions":
			return 0.0  # the AI's reactive move has no objective to go for
		"no-escape-shadowkeepers":
			return 2.5 if _has_melee(uid) else 0.0
		"rapid-reactions-aquilan-shield":
			return 2.2
		"impenetrable-bastion-emperors-chosen":
			return 2.1 if not controlled_objectives(uid, player).is_empty() else 0.0
		"golden-light-of-the-moiraides-dread-host":
			return 3.2 if nearest <= 18.0 else 0.0
		"unstoppable-momentum-might-of-the-moritoi", "inexorable-solar-watch":
			return 0.0
	return 0.0


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		"unstoppable-momentum-might-of-the-moritoi":
			if window_id != W_SELECTED_TO_MOVE and window_id != W_DECLARES_CHARGE:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
		"at-spears-length-solar-watch", "manoeuvre-and-fire-aquilan-shield", "inexorable-solar-watch":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_MOVE else []
		"unceasing-onslaught-might-of-the-moritoi", "unlimited-endurance-guardians-of-the-throne", "preternatural-rapidity-dread-host":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_ENDED_ADVANCE else []
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions", \
				"no-escape-shadowkeepers", "rapid-reactions-aquilan-shield":
			return Common.friendly_heads(player) if window_id == W_ENEMY_ENDED_MOVE else []
		"impenetrable-bastion-emperors-chosen":
			return Common.friendly_heads(player) if window_id == W_PHASE_END else []
		"golden-light-of-the-moiraides-dread-host":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_INGRESS else []
	return []


static func _entry_extra(csv: String, unit_id: String, player: int, _ctx: Dictionary) -> Dictionary:
	if csv == "impenetrable-bastion-emperors-chosen":
		var opts: Array = []
		for oid in controlled_objectives(unit_id, player):
			opts.append({"id": str(oid), "label": Common.objective_label(str(oid))})
		return {"secondary": {"kind": "objective", "prompt": "IMPENETRABLE BASTION: select one objective %s is controlling — it becomes secured" % Common.unit_name(unit_id), "options": opts}}
	return {}


static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var name := _display_name(csv)
	var uid := Common.head_id(target_unit_id)
	var u := Common.unit(uid)
	if u.is_empty():
		return _no("%s: unit %s not found" % [name, target_unit_id])
	if int(u.get("owner", 0)) != player:
		return _no("%s: %s is not your unit" % [name, Common.unit_name(uid)])
	# GOLDEN LIGHT is used on a unit that is about to be set up (still in reserves).
	if csv != "golden-light-of-the-moiraides-dread-host" and not Common.is_on_battlefield(u):
		return _no("%s: %s is not on the battlefield" % [name, Common.unit_name(uid)])
	var move_type := str(ctx.get("move_type", ""))
	match csv:
		"unstoppable-momentum-might-of-the-moritoi":
			if window_id != "" and window_id != W_SELECTED_TO_MOVE and window_id != W_DECLARES_CHARGE:
				return _no("%s is used when a DREADNOUGHT unit is selected to move or declares a charge" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "DREADNOUGHT")):
				return _no("%s can only target an ADEPTUS CUSTODES DREADNOUGHT unit" % name)
			if window_id == W_SELECTED_TO_MOVE and not move_type in ["", "normal", "advance", "fall_back"]:
				return _no("%s: only for a normal, advance or fall-back move" % name)
		"at-spears-length-solar-watch", "manoeuvre-and-fire-aquilan-shield":
			if window_id != "" and window_id != W_SELECTED_TO_MOVE:
				return _no("%s is used when a unit is selected to make a fall-back move" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if window_id != "" and move_type != "fall_back":
				return _no("%s is only used for a fall-back move" % name)
		"inexorable-solar-watch":
			if window_id != "" and window_id != W_SELECTED_TO_MOVE:
				return _no("%s is used when an ADEPTUS CUSTODES unit is selected to move" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		"unceasing-onslaught-might-of-the-moritoi":
			if window_id != "" and window_id != W_ENDED_ADVANCE:
				return _no("%s is used when a DREADNOUGHT unit ends an advance move" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "DREADNOUGHT")):
				return _no("%s can only target an ADEPTUS CUSTODES DREADNOUGHT unit" % name)
		"unlimited-endurance-guardians-of-the-throne", "preternatural-rapidity-dread-host":
			if window_id != "" and window_id != W_ENDED_ADVANCE:
				return _no("%s is used when an ADEPTUS CUSTODES unit ends an advance move" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions":
			if window_id != "" and window_id != W_ENEMY_ENDED_MOVE:
				return _no("%s is used when an enemy unit ends a move within 8\" of a TRUSTED SENTINEL unit" % name)
			if not Common.group_has_keyword(uid, "TRUSTED SENTINEL"):
				return _no("%s can only target a TRUSTED SENTINEL unit" % name)
			if Common.is_engaged(uid) or not Common.engaged_enemy_ids(uid).is_empty():
				return _no("%s: %s is engaged" % [name, Common.unit_name(uid)])
			var enemy := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			if window_id != "" and (enemy == "" or Common.group_distance_inches(uid, enemy) > SWIFT_RANGE_IN + 0.001):
				return _no("%s: that enemy unit did not end its move within 8\" of %s" % [name, Common.unit_name(uid)])
		"no-escape-shadowkeepers":
			if window_id != "" and window_id != W_ENEMY_ENDED_MOVE:
				return _no("%s is used when an enemy unit ends a fall-back move" % name)
			if window_id != "" and move_type != "fall_back":
				return _no("%s: that enemy unit did not make a fall-back move" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "INFANTRY")):
				return _no("%s can only target an ADEPTUS CUSTODES INFANTRY unit" % name)
			if not Common.engaged_enemy_ids(uid).is_empty():
				return _no("%s: %s is engaged" % [name, Common.unit_name(uid)])
			var fb := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			if window_id != "" and (fb == "" or Common.group_distance_inches(uid, fb) > NO_ESCAPE_RANGE_IN + 0.001):
				return _no("%s: %s is not within 6\" of that enemy unit" % [name, Common.unit_name(uid)])
			if bool(u.get("flags", {}).get("charged_this_turn", false)):
				return _no("%s: %s has already made a charge move this turn" % [name, Common.unit_name(uid)])
		"rapid-reactions-aquilan-shield":
			if window_id != "" and window_id != W_ENEMY_ENDED_MOVE:
				return _no("%s is used when an enemy unit ends a fall-back move" % name)
			if window_id != "" and move_type != "fall_back":
				return _no("%s: that enemy unit did not make a fall-back move" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "INFANTRY")):
				return _no("%s can only target an ADEPTUS CUSTODES INFANTRY unit" % name)
			var foe := Common.head_id(str(ctx.get("enemy_unit_id", "")))
			if window_id != "" and not _was_engaged_at_phase_start(uid, foe, ctx):
				return _no("%s: %s was not engaged with that enemy unit at the start of the phase" % [name, Common.unit_name(uid)])
			if window_id != "" and forced_shoot_assignments(uid, foe).is_empty():
				return _no("%s: %s has no ranged weapon that can target %s" % [name, Common.unit_name(uid), Common.unit_name(foe)])
		"impenetrable-bastion-emperors-chosen":
			if window_id != "" and window_id != W_PHASE_END:
				return _no("%s is used at the end of your Movement phase" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if Common.group_has_keyword(uid, "MONSTER") or Common.group_has_keyword(uid, "VEHICLE"):
				return _no("%s cannot target a MONSTER or VEHICLE unit" % name)
			if controlled_objectives(uid, player).is_empty():
				return _no("%s: %s is not controlling an objective (that is not already secured)" % [name, Common.unit_name(uid)])
		"golden-light-of-the-moiraides-dread-host":
			if window_id != "" and window_id != W_INGRESS:
				return _no("%s is used when an ADEPTUS CUSTODES unit is selected to make an ingress move" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		_:
			return _no("%s is not yet mechanically implemented" % name)
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _display_name(csv: String) -> String:
	match csv:
		"unstoppable-momentum-might-of-the-moritoi": return "UNSTOPPABLE MOMENTUM"
		"unceasing-onslaught-might-of-the-moritoi": return "UNCEASING ONSLAUGHT"
		"unlimited-endurance-guardians-of-the-throne": return "UNLIMITED ENDURANCE"
		"preternatural-rapidity-dread-host": return "PRETERNATURAL RAPIDITY"
		"swift-as-the-eagle-guardians-of-the-throne", "swift-as-the-eagle-honoured-companions": return "SWIFT AS THE EAGLE"
		"at-spears-length-solar-watch": return "AT SPEAR'S LENGTH"
		"manoeuvre-and-fire-aquilan-shield": return "MANOEUVRE AND FIRE"
		"inexorable-solar-watch": return "INEXORABLE"
		"impenetrable-bastion-emperors-chosen": return "IMPENETRABLE BASTION"
		"no-escape-shadowkeepers": return "NO ESCAPE"
		"rapid-reactions-aquilan-shield": return "RAPID REACTIONS"
		"golden-light-of-the-moiraides-dread-host": return "GOLDEN LIGHT OF THE MOIRAIDES"
	return csv


static func _log(player: int, msg: String) -> void:
	Common.log_info("[CustodesCodexMovement] " + msg)
	Common.game_log(player, msg)


static func _has_melee(unit_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("get_unit_melee_weapons"):
		return true
	for gid in Common.attached_group_ids(unit_id):
		if not re.get_unit_melee_weapons(str(gid), Common.state()).is_empty():
			return true
	return false


## ctx.engagement_at_phase_start (MovementPhase: unit_id -> [enemy ids]).
static func _was_engaged_at_phase_start(unit_id: String, enemy_id: String, ctx: Dictionary) -> bool:
	var snap = ctx.get("engagement_at_phase_start", {})
	if typeof(snap) != TYPE_DICTIONARY:
		return false
	var enemy_group := Common.attached_group_ids(enemy_id)
	for gid in Common.attached_group_ids(unit_id):
		for e in snap.get(str(gid), []):
			if str(e) in enemy_group:
				return true
	return false


## Enemy units (heads) of `player`'s opponent that made a fall-back move this
## phase (NO ESCAPE's only legal charge targets).
static func fell_back_enemy_heads(player: int) -> Array:
	var out: Array = []
	for eid in Common.enemy_heads(player):
		for gid in Common.attached_group_ids(str(eid)):
			if bool(Common.unit(str(gid)).get("flags", {}).get("fell_back", false)):
				out.append(str(eid))
				break
	return out


# ---------------------------------------------------------------------------
# Objectives (IMPENETRABLE BASTION)
# ---------------------------------------------------------------------------

## Objectives `unit_id` is controlling: within range of an objective its
## player controls (14.02), with OC >= 1 and not battle-shocked; excluding
## objectives its army has already secured (re-securing has no effect).
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


static func _bastion_apply(unit_id: String, player: int, ctx: Dictionary) -> Array:
	var objs := controlled_objectives(unit_id, player)
	var obj_id := str(ctx.get("secondary_id", ""))
	if obj_id == "" and not objs.is_empty():
		obj_id = str(objs[0])
	if obj_id == "" or not obj_id in objs:
		Common.log_error("CustodesCodexMovement: IMPENETRABLE BASTION — %s controls no objective %s; nothing secured" % [unit_id, obj_id])
		return []
	var mm = Common.mission_manager()
	# 14.03: secured by the ARMY (no source unit): it stays under the
	# player's control even if this unit leaves or is destroyed.
	mm.secure_objective(obj_id, player, "")
	_log(player, "IMPENETRABLE BASTION: %s secures %s" % [Common.group_label(unit_id), Common.objective_label(obj_id)])
	return Common.set_flag_diffs([unit_id], FLAG_BASTION, obj_id)


# ---------------------------------------------------------------------------
# NO ESCAPE — the charge, auto-resolved for either decider: 2D6 (+ the unit's
# own charge-roll modifiers), the targets are enemy units that fell back this
# phase within that distance (the one the window named first, else the
# closest), and the move is the ReactiveMove11e surge solve toward it (each
# model ends engaged with it if possible, never engaged with another enemy).
# The charge succeeds when the solved placement leaves the unit engaged with
# its target; otherwise the unit does not move (11.04: a failed charge).
# ---------------------------------------------------------------------------

static func resolve_reactive_charge(player: int, followup: Dictionary) -> Dictionary:
	var out := {"diffs": [], "success": false, "roll": 0, "rolls": [], "target_id": "", "message": ""}
	var head := Common.head_id(str(followup.get("unit_id", "")))
	var unit := Common.unit(head)
	var label := Common.group_label(head)
	if unit.is_empty() or not Common.is_alive(unit):
		out.message = "NO ESCAPE: %s is no longer on the battlefield — no charge" % label
		return out
	var rolls: Array = Common.roll_dice(2, 6)
	var raw := int(rolls[0]) + int(rolls[1])
	var roll := maxi(0, raw + int(load("res://scripts/codex/custodes/CustodesCodexOther.gd").charge_roll_modifier(unit, 0)))
	out.rolls = rolls
	out.roll = roll
	var board: Dictionary = Common.state()
	var preferred := Common.head_id(str(followup.get("preferred_target_id", "")))
	var best := ""
	var best_d := INF
	for tid in followup.get("target_ids", []):
		var t := Common.head_id(str(tid))
		if not Common.is_alive(Common.unit(t)):
			continue
		var d := Common.group_distance_inches(head, t)
		if d > float(roll):
			continue
		if t == preferred:
			best = t
			break
		if d < best_d:
			best_d = d
			best = t
	if best == "":
		out.message = "NO ESCAPE: %s charge roll %d (%d + %d) — no unit that fell back is within %d\" — the charge fails" % [label, roll, int(rolls[0]), int(rolls[1]), roll]
		return out
	out.target_id = best
	var rm = load("res://scripts/rules/ReactiveMove11e.gd")
	var origin: Dictionary = rm.current_positions(head, board)
	var solved: Dictionary = rm.solve("surge", head, origin, float(roll), {"surge_target": best}, board)
	var engaged := false
	if not solved.is_empty():
		var hyp: Dictionary = rm.board_with_positions(board, head, solved)
		var re = Common.rules()
		var hyp_units: Dictionary = hyp.get("units", {})
		for gid in rm.group_ids(head, hyp):
			for tg in rm.group_ids(best, hyp):
				if re != null and re.units_in_engagement_range(hyp_units.get(str(gid), {}), hyp_units.get(str(tg), {})):
					engaged = true
	var tlabel := Common.group_label(best)
	if not engaged:
		out.message = "NO ESCAPE: %s charge roll %d (%d + %d) vs %s — cannot end engaged with it, the charge fails" % [label, roll, int(rolls[0]), int(rolls[1]), tlabel]
		return out
	var diffs: Array = rm.position_diffs(solved)
	for gid in Common.attached_group_ids(head):
		diffs.append({"op": "set", "path": "units.%s.flags.charged_this_turn" % str(gid), "value": true})
		diffs.append({"op": "set", "path": "units.%s.flags.fights_first" % str(gid), "value": true})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_NO_ESCAPE], "value": true})
	for tg in Common.attached_group_ids(best):
		diffs.append({"op": "set", "path": "units.%s.flags.has_been_charged" % str(tg), "value": true})
	out.diffs = diffs
	out.success = true
	out.message = "NO ESCAPE: %s charge roll %d (%d + %d) — charges %s and ends engaged with it" % [label, roll, int(rolls[0]), int(rolls[1]), tlabel]
	return out


# ---------------------------------------------------------------------------
# RAPID REACTIONS — auto-resolved normal shooting at the forced target
# (the GUN-CRAZY SHOW-OFFS executor's assignment rules, 04.01.03 / 24.07).
# ---------------------------------------------------------------------------

static func forced_shoot_assignments(unit_id: String, target_id: String) -> Array:
	var re = Common.rules()
	if re == null:
		return []
	var board: Dictionary = Common.state()
	var assignments: Array = []
	for gid in Common.attached_group_ids(unit_id):
		var shooter := str(gid)
		var in_range: Array = re.get_eligible_targets(shooter, board).get(target_id, {}).get("weapons_in_range", [])
		if in_range.is_empty():
			# An Attached target: try any component of it.
			for tg in Common.attached_group_ids(target_id):
				in_range = re.get_eligible_targets(shooter, board).get(str(tg), {}).get("weapons_in_range", [])
				if not in_range.is_empty():
					break
		if in_range.is_empty():
			continue
		var unit_weapons: Dictionary = re.get_unit_weapons(shooter, board)
		var models_for := {}
		for model_id in unit_weapons:
			var best := {}  # weapon base name -> weapon id (one profile per weapon)
			for wid in unit_weapons[model_id]:
				if not wid in in_range:
					continue
				var base := _weapon_base_name(str(wid), board)
				if not best.has(base):
					best[base] = str(wid)
			for chosen in best.values():
				if not models_for.has(chosen):
					models_for[chosen] = []
				models_for[chosen].append(model_id)
		for wid in models_for:
			assignments.append({"weapon_id": wid, "target_unit_id": target_id, "model_ids": models_for[wid], "_shooter": shooter})
	return assignments


static func _weapon_base_name(weapon_id: String, board: Dictionary) -> String:
	var re = Common.rules()
	var wname := str(re.get_weapon_profile(weapon_id, board).get("name", weapon_id)) if re else weapon_id
	for sep in [" – ", " — ", " - "]:
		var idx := wname.find(sep)
		if idx > 0:
			return wname.substr(0, idx)
	return wname


# ===========================================================================
# Effect consumers (CustodesCodex11e engine hooks)
# ===========================================================================

## GOLDEN LIGHT OF THE MOIRAIDES: attacks that target the unit have -1 to hit.
static func hit_roll_effects(out: Dictionary, _attacker_unit: Dictionary, target_unit: Dictionary, _is_melee: bool, _board: Dictionary) -> void:
	if golden_light_on(target_unit):
		out["minus"] = true
		out.sources.append("Golden Light of the Moiraides")


static func golden_light_on(target_unit: Dictionary) -> bool:
	if bool(target_unit.get("flags", {}).get(FLAG_GOLDEN_LIGHT, false)):
		return true
	var tid := str(target_unit.get("id", ""))
	if tid == "":
		return false
	for gid in Common.attached_group_ids(tid):
		if bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_GOLDEN_LIGHT, false)):
			return true
	return false


## GOLDEN LIGHT: "Enemy units cannot target your unit with snap shooting attacks".
static func blocks_snap_shooting_at(target_unit: Dictionary) -> bool:
	return golden_light_on(target_unit)


## INEXORABLE: harmful modifiers to M / advance rolls / charge rolls ignored.
static func ignores_move_penalties(unit: Dictionary) -> bool:
	if bool(unit.get("flags", {}).get(FLAG_INEXORABLE, false)):
		return true
	var uid := str(unit.get("id", ""))
	if uid == "":
		return false
	for gid in Common.attached_group_ids(uid):
		if bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_INEXORABLE, false)):
			return true
	return false


## Turn-long move / shoot / charge grants (EffectPrimitives hooks).
static func grants(unit: Dictionary, what: String) -> bool:
	var f: Dictionary = unit.get("flags", {})
	match what:
		"advance_and_charge":
			return bool(f.get(FLAG_UNCEASING, false)) or bool(f.get(FLAG_UNLIMITED, false)) or bool(f.get(FLAG_PRETERNATURAL, false))
		"advance_and_shoot":
			return bool(f.get(FLAG_UNCEASING, false)) or bool(f.get(FLAG_UNLIMITED, false))
		"fall_back_and_shoot":
			return bool(f.get(FLAG_SPEARS_LENGTH, false)) or bool(f.get(FLAG_MANOEUVRE, false))
		"fall_back_and_charge":
			return bool(f.get(FLAG_MANOEUVRE, false))
	return false


static func on_command_phase_start(_player: int) -> void:
	pass
