extends RefCounted

## SWCodexMovement — Codex: Space Marines (11e) Space Wolves stratagems that
## MOVE units (WP-S3). Dispatcher: SWCodex11e.gd. Rulings: RULINGS.md § WP-S3.
##
##   IMPETUOSITY         (Saga of the Beastslayer, 1CP) enemy_has_shot (your
##                       opponent's Shooting phase): an unengaged BLOOD CLAWS /
##                       THUNDERWOLF CAVALRY / WULFEN unit the enemy unit
##                       targeted makes a surge move of up to D6" (follow-up
##                       surge_move, executed by ShootingPhase — D6 rolled there).
##   BATTLE INSTINCTS    (Saga of the Great Wolf, 1CP) enemy_has_shot: an
##                       unengaged ADEPTUS ASTARTES INFANTRY/MOUNTED unit the
##                       enemy unit targeted makes a normal move of up to D3+3"
##                       (D3 rolled here; follow-up reactive_normal_move).
##   FENRISIAN FEROCITY  (Saga of the Great Wolf, 1CP) unit_selected_to_move /
##                       unit_declares_charge (your turn): the MOUNTED/WALKER
##                       unit has MOBILE (13.06 — moves through dense terrain)
##                       this phase. Written as the engine's MOBILE-grant flag
##                       ork11e_mobile (Movement/Charge phase terrain checks).
##   CO-ORDINATED STRIKE (Saga of the Beastslayer, 1CP) fight_phase_end (your
##                       opponent's Fight phase): an unengaged BLOOD CLAWS /
##                       THUNDERWOLF CAVALRY / WULFEN unit within 9" of a
##                       battlefield edge is placed in strategic reserves
##                       (follow-up strategic_reserves, executed by FightPhase).
##
## The "enemy unit that targeted …" is ctx.targeted_unit_ids of the
## enemy_has_shot window (ShootingPhase._ork11e_post_shot_ctx: every unit a hit
## roll of those attacks was made against), falling back to hit_unit_ids.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_IMPETUOSITY := "impetuosity-saga-of-the-beastslayer"
const CSV_INSTINCTS := "battle-instincts-saga-of-the-great-wolf"
const CSV_FEROCITY := "fenrisian-ferocity-saga-of-the-great-wolf"
const CSV_STRIKE := "co-ordinated-strike-saga-of-the-beastslayer"

const IDS: Array = [CSV_IMPETUOSITY, CSV_INSTINCTS, CSV_FEROCITY, CSV_STRIKE]

const IMPLEMENTED: Dictionary = {
	CSV_IMPETUOSITY: true,
	CSV_INSTINCTS: true,
	CSV_FEROCITY: true,
	CSV_STRIKE: true,
}

const AI_KIND: Dictionary = {
	CSV_IMPETUOSITY: "utility",
	CSV_INSTINCTS: "utility",
	CSV_FEROCITY: "utility",
	CSV_STRIKE: "utility",
}

const W_ENEMY_HAS_SHOT := "enemy_has_shot"
const W_SELECTED_TO_MOVE := "unit_selected_to_move"
const W_DECLARES_CHARGE := "unit_declares_charge"
const W_FIGHT_END := "fight_phase_end"

const FLAG_MOBILE := "ork11e_mobile"                    # the engine's MOBILE grant (13.06 terrain checks)
const FLAG_FEROCITY := "sw11e_fenrisian_ferocity"       # marker: this stratagem wrote the grant
const FLAG_FEROCITY_HAD := "sw11e_ferocity_had_mobile"  # the unit already had the grant

const KW_AA := "ADEPTUS ASTARTES"
const BEAST_KWS: Array = ["BLOOD CLAWS", "THUNDERWOLF CAVALRY", "WULFEN"]
const STRIKE_EDGE_INCHES := 9.0
const MOVE_TYPES: Array = ["normal", "advance", "fall_back"]


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if _check(csv, player, str(uid), window_id, ctx).ok:
			out.append(Common.target_entry(str(uid)))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	if target_unit_id == "":
		return _no("%s needs a target unit" % strat.get("name", "?"))
	return _check(csv, player, target_unit_id, str(ctx.get("window_id", "")), ctx)


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_IMPETUOSITY:
			_log(player, "IMPETUOSITY: %s can make a surge move of up to D6\"" % label)
			return {"diffs": [], "followup": {"type": "surge_move", "unit_id": head, "source": "IMPETUOSITY"}}
		CSV_INSTINCTS:
			var d3 := int(Common.roll_dice(1, 3)[0])
			var inches := d3 + 3
			_log(player, "BATTLE INSTINCTS: %s rolls D3 = %d — it can make a normal move of up to %d\"" % [label, d3, inches])
			return {"diffs": [], "followup": {"type": "reactive_normal_move", "unit_id": head,
				"max_inches": float(inches), "roll": d3, "source": "BATTLE INSTINCTS"}}
		CSV_FEROCITY:
			var diffs: Array = []
			for gid in group:
				var had := bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_MOBILE, false))
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_FEROCITY_HAD], "value": had})
			diffs.append_array(Common.set_flag_diffs(group, FLAG_MOBILE, true))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_FEROCITY, true))
			_log(player, "FENRISIAN FEROCITY: %s has MOBILE (moves through dense terrain) this phase" % label)
			return diffs
		CSV_STRIKE:
			_log(player, "CO-ORDINATED STRIKE: %s is placed in strategic reserves" % label)
			return {"diffs": [], "followup": {"type": "strategic_reserves", "unit_id": head, "source": "CO-ORDINATED STRIKE"}}
	Common.log_error("SWCodexMovement: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	if csv == CSV_FEROCITY:
		var units: Dictionary = Common.state().get("units", {})
		for gid in group:
			var f = units.get(str(gid), {}).get("flags", null)
			if typeof(f) != TYPE_DICTIONARY:
				continue
			if f.has(FLAG_FEROCITY) and not bool(f.get(FLAG_FEROCITY_HAD, false)):
				f.erase(FLAG_MOBILE)
			f.erase(FLAG_FEROCITY)
			f.erase(FLAG_FEROCITY_HAD)
		Common.log_info("SWCodexMovement: FENRISIAN FEROCITY (MOBILE) expired on %s" % str(group))
	# IMPETUOSITY / BATTLE INSTINCTS / CO-ORDINATED STRIKE leave no flag behind.


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(_strat: Dictionary, _variant_id: String) -> String:
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, _player: int, target_unit_id: String, _window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	match csv:
		CSV_IMPETUOSITY:
			# A melee unit that can end engaged on an average roll.
			var near := Common.nearest_enemy_inches(Common.group_union(uid))
			return 2.5 if near <= 6.0 and Common.group_has_melee_weapons(uid) else 0.0
		CSV_INSTINCTS:
			# The AI's move is the auto-placement toward an objective: only pay
			# when the minimum roll (4") already reaches one it is not on.
			return 2.2 if _objective_gap_inches(uid) > 0.0 and _objective_gap_inches(uid) <= 4.0 else 0.0
		CSV_FEROCITY:
			var dest := ""
			var targets: Array = ctx.get("target_unit_ids", [])
			if not targets.is_empty():
				dest = str(targets[0])
			return 2.2 if _mobile_helps(uid, dest) else 0.0
		CSV_STRIKE:
			# Redeploy a unit that is doing nothing: no enemy near, no objective held.
			if Common.battle_round() >= 5:
				return 0.0
			if Common.nearest_enemy_inches(Common.group_union(uid)) <= 12.0:
				return 0.0
			if Common.group_in_range_of_any_objective(uid):
				return 0.0
			return 2.1
	return 0.0


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_IMPETUOSITY, CSV_INSTINCTS:
			if window_id != W_ENEMY_HAS_SHOT:
				return []
			var out: Array = []
			for tid in _targeted_ids(ctx):
				var h := Common.head_id(str(tid))
				if h != "" and not h in out:
					out.append(h)
			return out
		CSV_FEROCITY:
			if window_id != W_SELECTED_TO_MOVE and window_id != W_DECLARES_CHARGE:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
		CSV_STRIKE:
			return Common.friendly_heads(player) if window_id == W_FIGHT_END else []
	return []


static func _targeted_ids(ctx: Dictionary) -> Array:
	var ids: Array = ctx.get("targeted_unit_ids", [])
	if ids.is_empty():
		ids = ctx.get("hit_unit_ids", [])
	return ids


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
	match csv:
		CSV_IMPETUOSITY, CSV_INSTINCTS:
			if csv == CSV_IMPETUOSITY and not Common.group_has_any_keyword(head, BEAST_KWS):
				return _no("IMPETUOSITY can only target a BLOOD CLAWS/THUNDERWOLF CAVALRY/WULFEN unit")
			if csv == CSV_INSTINCTS and not (Common.group_has_keyword(head, KW_AA) and Common.group_has_any_keyword(head, ["INFANTRY", "MOUNTED"])):
				return _no("BATTLE INSTINCTS can only target an ADEPTUS ASTARTES INFANTRY/MOUNTED unit")
			if Common.active_player() == player:
				return _no("%s: only in your opponent's Shooting phase" % sname)
			if (ctx.has("targeted_unit_ids") or ctx.has("hit_unit_ids")) and not Common.group_in(head, _targeted_ids(ctx)):
				return _no("%s: that unit was not targeted by the enemy unit that has shot" % sname)
			if Common.is_engaged(head):
				return _no("%s: the unit must be unengaged" % sname)
		CSV_FEROCITY:
			if not (Common.group_has_keyword(head, KW_AA) and Common.group_has_any_keyword(head, ["MOUNTED", "WALKER"])):
				return _no("FENRISIAN FEROCITY can only target an ADEPTUS ASTARTES MOUNTED/WALKER unit")
			var selected := str(ctx.get("unit_id", ""))
			if selected != "" and Common.head_id(selected) != head:
				return _no("FENRISIAN FEROCITY must target the unit that was selected to move / declared a charge")
			if window_id == W_SELECTED_TO_MOVE and ctx.has("move_type") and not str(ctx.get("move_type", "")) in MOVE_TYPES:
				return _no("FENRISIAN FEROCITY: not for a %s move" % str(ctx.get("move_type", "")))
		CSV_STRIKE:
			if not Common.group_has_any_keyword(head, BEAST_KWS):
				return _no("CO-ORDINATED STRIKE can only target a BLOOD CLAWS/THUNDERWOLF CAVALRY/WULFEN unit")
			if Common.is_engaged(head):
				return _no("CO-ORDINATED STRIKE can only target an unengaged unit")
			if Common.group_edge_distance_inches(head) > STRIKE_EDGE_INCHES + 0.001:
				return _no("CO-ORDINATED STRIKE: that unit is not within 9\" of a battlefield edge")
	return {"ok": true, "reason": ""}


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_IMPETUOSITY: return "IMPETUOSITY"
		CSV_INSTINCTS: return "BATTLE INSTINCTS"
		CSV_FEROCITY: return "FENRISIAN FEROCITY"
		CSV_STRIKE: return "CO-ORDINATED STRIKE"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SWCodexMovement: " + msg)
	Common.game_log(player, msg)

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

## FENRISIAN FEROCITY AI: MOBILE only matters when dense terrain blocks the
## straight line to where the unit is going (the charge target, else the
## nearest enemy unit) and MOBILE would let it through (13.06).
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
