extends RefCounted

## SWCodexCommand — Codex: Space Marines (11e) Space Wolves COMMAND PHASE
## stratagems (WP-S3). Dispatcher: SWCodex11e.gd. Rulings: RULINGS.md § WP-S3.
##
## Both are offered in the active player's command_phase_main window ("Your
## Command phase", CommandPhase — just before the Battle-shock step); after a
## use the window is offered again (follow-up ork11e_reoffer) so the other one
## can still be used in the same phase.
##
##   BIRTH OF A SAGA   (Champions of Fenris, 1CP): one friendly ADEPTUS
##                     ASTARTES unit (excluding MONSTER/VEHICLE) has CHARACTER
##                     until the start of your next Command phase. Written as
##                     the CHARACTER keyword on meta.keywords (every engine
##                     keyword check sees it: HEROIC RESOLVE / CHAMPION'S
##                     GUIDANCE targets, Epic Challenge, [PRECISION] ...); the
##                     marker sw11e_birth_of_a_saga says which components got
##                     it, so the expiry removes exactly that.
##   GRIMNAR'S COMMAND (Saga of the Great Wolf, 1CP): select one combat
##                     doctrine (dialog variant); it is active for the unit
##                     until the start of your next Command phase. Writes the
##                     per-unit doctrine keys documented in SWCommon
##                     (flags.sw11e_doctrine, flags.sw11e_doctrine_expires_player)
##                     + the marker sw11e_grimnars_command; every package reads
##                     it through SWCommon.doctrine_active (WP-S2 wires the
##                     doctrine effects).
## Expiry: StratagemManager's "until the start of your next Command phase"
## active effect (next_own_command_phase) -> clear().

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_BIRTH := "birth-of-a-saga-champions-of-fenris"
const CSV_GRIMNAR := "grimnars-command-saga-of-the-great-wolf"

const IDS: Array = [CSV_BIRTH, CSV_GRIMNAR]

const IMPLEMENTED: Dictionary = {
	CSV_BIRTH: true,
	CSV_GRIMNAR: true,
}

const AI_KIND: Dictionary = {
	CSV_BIRTH: "utility",
	CSV_GRIMNAR: "utility",
}

const W_COMMAND := "command_phase_main"

const FLAG_BIRTH := "sw11e_birth_of_a_saga"      # this component was given CHARACTER
const FLAG_GRIMNAR := "sw11e_grimnars_command"   # the doctrine this stratagem made active
const FLAG_DOCTRINE := "sw11e_doctrine"          # SWCommon per-unit doctrine key
const FLAG_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"

const KW_AA := "ADEPTUS ASTARTES"
const KW_CHARACTER := "CHARACTER"


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	if window_id != W_COMMAND:
		return out
	for uid in Common.friendly_heads(player):
		if not _check(csv, player, str(uid), ctx).ok:
			continue
		var extra := {}
		if csv == CSV_GRIMNAR:
			# One button per (unit, doctrine): the label names the unit, as
			# every unit's three buttons sit in the same card.
			var variants: Array = []
			for d in Common.DOCTRINES:
				variants.append({"id": d, "label": "%s: %s" % [Common.group_label(str(uid)), str(Common.DOCTRINE_LABELS[d])],
					"cp_cost": int(strat.get("cp_cost", 1))})
			extra = {"require_variant": true, "ai_variant": ai_doctrine(str(uid)), "variants": variants}
		out.append(Common.target_entry(str(uid), extra))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	if target_unit_id == "":
		return _no("%s needs a target unit" % strat.get("name", "?"))
	var c := _check(csv, player, target_unit_id, ctx)
	if not c.ok:
		return c
	if csv == CSV_GRIMNAR:
		var v := str(ctx.get("variant_id", ""))
		if v != "" and not v in Common.DOCTRINES:
			return _no("GRIMNAR'S COMMAND: unknown combat doctrine '%s'" % v)
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	var diffs: Array = []
	match csv:
		CSV_BIRTH:
			for gid in group:
				var u := Common.unit(str(gid))
				var kws: Array = u.get("meta", {}).get("keywords", []).duplicate()
				if Common.has_keyword(u, KW_CHARACTER):
					continue
				kws.append(KW_CHARACTER)
				diffs.append({"op": "set", "path": "units.%s.meta.keywords" % str(gid), "value": kws})
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_BIRTH], "value": true})
			_log(player, "BIRTH OF A SAGA: %s has CHARACTER until the start of Player %d's next Command phase" % [label, player])
		CSV_GRIMNAR:
			var doctrine := str(ctx.get("variant_id", ""))
			if not doctrine in Common.DOCTRINES:
				doctrine = ai_doctrine(head)
				Common.log_info("SWCodexCommand: GRIMNAR'S COMMAND used without a doctrine choice — %s picked" % doctrine)
			diffs.append_array(Common.set_flag_diffs(group, FLAG_DOCTRINE, doctrine))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_DOCTRINE_EXPIRES, player))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_GRIMNAR, doctrine))
			_log(player, "GRIMNAR'S COMMAND: the %s is active for %s until the start of Player %d's next Command phase" % [
				str(Common.DOCTRINE_LABELS.get(doctrine, doctrine)), label, player])
		_:
			Common.log_error("SWCodexCommand: apply() called for unimplemented %s" % csv)
			return []
	if str(ctx.get("window_id", "")) == W_COMMAND:
		# Offer the Command-phase window again: the other stratagem (or another
		# Space Wolves rule) may still be used this phase.
		return {"diffs": diffs, "followup": {"type": "ork11e_reoffer", "player": player, "window_id": W_COMMAND,
			"ctx": {"phase": "command"}}}
	return diffs


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var units: Dictionary = Common.state().get("units", {})
	var group := Common.attached_group_ids(unit_id)
	# The Attached unit may have changed since (a CHARACTER detached / died):
	# also sweep the target id itself.
	if not unit_id in group:
		group.append(unit_id)
	for gid in group:
		var u = units.get(str(gid), {})
		var f = u.get("flags", null)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		match csv:
			CSV_BIRTH:
				if bool(f.get(FLAG_BIRTH, false)):
					var kws: Array = u.get("meta", {}).get("keywords", [])
					for i in range(kws.size() - 1, -1, -1):
						if str(kws[i]).to_upper() == KW_CHARACTER:
							kws.remove_at(i)
							break
					f.erase(FLAG_BIRTH)
			CSV_GRIMNAR:
				if f.has(FLAG_GRIMNAR):
					if str(f.get(FLAG_DOCTRINE, "")) == str(f.get(FLAG_GRIMNAR, "")):
						f.erase(FLAG_DOCTRINE)
						f.erase(FLAG_DOCTRINE_EXPIRES)
					f.erase(FLAG_GRIMNAR)
	Common.log_info("SWCodexCommand: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if str(strat.get("csv_id", "")) == CSV_GRIMNAR:
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
		CSV_BIRTH:
			# CHARACTER opens CHAMPION'S GUIDANCE / HEROIC RESOLVE / Epic
			# Challenge to a valuable melee unit that will fight soon.
			if Common.group_points(uid) < 100 or not Common.group_has_melee_weapons(uid) or near > 12.0:
				return 0.0
			return 2.1 if _has_character_stratagems(player) else 0.0
		CSV_GRIMNAR:
			var d := ai_doctrine(uid)
			if Common.doctrine_active_id(uid, d):
				return 0.0  # already active through the army-wide doctrine
			if d == "tactical":
				return 2.2 if Common.is_engaged(uid) else 0.0
			if d == "assault":
				return 2.2 if near > 6.0 and near <= 16.0 else 0.0
			return 2.1 if near <= 30.0 else 0.0
	return 0.0


## The doctrine the AI (and a use without a choice) picks for the unit:
## engaged -> tactical (fall back and still shoot / charge); a melee unit
## 6-16" from the enemy -> assault (advance and still charge); otherwise a
## unit with guns -> devastator (ranged [ASSAULT]).
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
# Checks / helpers
# ===========================================================================

static func _check(csv: String, player: int, target_unit_id: String, _ctx: Dictionary) -> Dictionary:
	var sname := "BIRTH OF A SAGA" if csv == CSV_BIRTH else "GRIMNAR'S COMMAND"
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
	if Common.group_is_monster_or_vehicle(head):
		return _no("%s cannot target a MONSTER or VEHICLE unit" % sname)
	match csv:
		CSV_BIRTH:
			if Common.group_has_keyword(head, KW_CHARACTER):
				return _no("BIRTH OF A SAGA: that unit already has CHARACTER")
		CSV_GRIMNAR:
			if not Common.has_combat_doctrines(u):
				return _no("GRIMNAR'S COMMAND: that unit does not have the Combat Doctrines ability")
	return {"ok": true, "reason": ""}


static func _has_character_stratagems(player: int) -> bool:
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_faction_stratagems_for_player"):
		return false
	for s in sm.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) in ["champions-guidance-champions-of-fenris", "heroic-resolve-champions-of-fenris"]:
			return true
	return false


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _log(player: int, msg: String) -> void:
	Common.log_info("SWCodexCommand: " + msg)
	Common.game_log(player, msg)
