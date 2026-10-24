extends RefCounted

## SWCodexCombat — Codex: Space Marines (11e) Space Wolves stratagems that
## change ATTACKS (WP-S3). Dispatcher: SWCodex11e.gd. Rulings: RULINGS.md § WP-S3.
##
##   HEROIC RESOLVE      (Champions of Fenris, 2CP) enemy_targets_unit_shooting
##                       (opponent's Shooting phase — folded into the defender's
##                       reactive dialog) / enemy_targets_unit_fight (either
##                       Fight phase): -1 D to attacks that target the unit until
##                       that enemy unit has attacked.
##   CHAMPION'S GUIDANCE (Champions of Fenris, 1CP) unit_selected_to_fight:
##                       melee re-roll hit rolls of 1 and wound rolls of 1.
##   UNBRIDLED FEROCITY  (Saga of the Beastslayer, 1CP) unit_selected_to_fight:
##                       melee [LANCE].
##   FANGS OF THE PACK   (Saga of the Great Wolf, 1CP) unit_selected_to_fight:
##                       melee [PRECISION].
##   EYE OF THE PACK     (Saga of the Great Wolf, 1CP) unit_selected_to_shoot
##                       (your Shooting phase) / unit_selected_to_fight: the
##                       unit's attacks re-roll wound rolls of 1 and 2.
##   WOLF TOTEMS         (Saga of the Great Wolf, 1CP) S panel, any phase:
##                       Feel No Pain 5+ against mortal wounds (this phase).
##
## Handler API (static; called by the dispatcher only): eligible_targets /
## validate / apply / clear / ai_kind / ai_score / variant_cp_cost /
## variant_label / allows_battle_shocked_target.
##
## Flags (no effect_ prefix on the sw11e_ markers — they expire through
## StratagemManager's active-effect expiry, end of the phase):
##   sw11e_heroic_resolve        {attacker_ids: [...]} -> damage_minus()
##   sw11e_champions_guidance    bool                  -> hit/wound re-roll 1s (melee)
##   sw11e_unbridled_ferocity    bool + effect_grant_lance (RulesEngine melee [LANCE])
##   sw11e_fangs_of_the_pack     bool + effect_precision_melee (the engine's melee [PRECISION])
##   sw11e_eye_of_the_pack       bool                  -> WoundModifier.REROLL_ONES_TWOS
##   sw11e_wolf_totems           int (5)               -> fnp_vs_mortal()
## The *_had_* markers remember a generic grant the unit already had so the
## expiry never strips another rule's [LANCE] / [PRECISION].

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_HEROIC := "heroic-resolve-champions-of-fenris"
const CSV_GUIDANCE := "champions-guidance-champions-of-fenris"
const CSV_UNBRIDLED := "unbridled-ferocity-saga-of-the-beastslayer"
const CSV_FANGS := "fangs-of-the-pack-saga-of-the-great-wolf"
const CSV_EYE := "eye-of-the-pack-saga-of-the-great-wolf"
const CSV_TOTEMS := "wolf-totems-saga-of-the-great-wolf"

const IDS: Array = [CSV_HEROIC, CSV_GUIDANCE, CSV_UNBRIDLED, CSV_FANGS, CSV_EYE, CSV_TOTEMS]

const IMPLEMENTED: Dictionary = {
	CSV_HEROIC: true,
	CSV_GUIDANCE: true,
	CSV_UNBRIDLED: true,
	CSV_FANGS: true,
	CSV_EYE: true,
	CSV_TOTEMS: true,
}

const AI_KIND: Dictionary = {
	CSV_HEROIC: "defensive",
	CSV_GUIDANCE: "offensive",
	CSV_UNBRIDLED: "offensive",
	CSV_FANGS: "offensive",
	CSV_EYE: "offensive",
	CSV_TOTEMS: "defensive",
}

const W_SHOOT_TARGETS := "enemy_targets_unit_shooting"
const W_FIGHT_TARGETS := "enemy_targets_unit_fight"
const W_SELECTED_TO_FIGHT := "unit_selected_to_fight"
const W_SELECTED_TO_SHOOT := "unit_selected_to_shoot"

const FLAG_HEROIC := "sw11e_heroic_resolve"
const FLAG_GUIDANCE := "sw11e_champions_guidance"
const FLAG_UNBRIDLED := "sw11e_unbridled_ferocity"
const FLAG_UNBRIDLED_HAD := "sw11e_unbridled_had_lance"
const FLAG_GRANT_LANCE := "effect_grant_lance"            # RulesEngine melee [LANCE] grant
const FLAG_FANGS := "sw11e_fangs_of_the_pack"
const FLAG_FANGS_HAD := "sw11e_fangs_had_precision"
const FLAG_PRECISION_MELEE := "effect_precision_melee"    # EffectPrimitives.FLAG_PRECISION_MELEE
const FLAG_EYE := "sw11e_eye_of_the_pack"
const FLAG_TOTEMS := "sw11e_wolf_totems"

const KW_AA := "ADEPTUS ASTARTES"
const BEAST_KWS: Array = ["BLOOD CLAWS", "THUNDERWOLF CAVALRY", "WULFEN"]
const TOTEMS_FNP := 5


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, window_id, ctx):
		if _check(csv, player, str(uid), window_id, ctx).ok:
			out.append(Common.target_entry(str(uid)))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	var window_id := str(ctx.get("window_id", ""))
	if target_unit_id == "":
		# S panel probe (no target): WOLF TOTEMS may be used when one friendly
		# unit qualifies; every other stratagem here is a window stratagem.
		if csv == CSV_TOTEMS:
			for uid in Common.friendly_heads(player):
				if _check(csv, player, str(uid), window_id, ctx).ok:
					return {"ok": true, "reason": ""}
			return _no("WOLF TOTEMS: no friendly ADEPTUS ASTARTES INFANTRY/MOUNTED unit on the battlefield")
		return _no("%s needs a target unit" % strat.get("name", "?"))
	return _check(csv, player, target_unit_id, window_id, ctx)


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_HEROIC:
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var attacker_ids: Array = Common.attached_group_ids(attacker) if attacker != "" else []
			_log(player, "HEROIC RESOLVE: attacks that target %s have -1 Damage until %s has attacked" % [
				label, Common.group_label(attacker) if attacker != "" else "that enemy unit"])
			return Common.set_flag_diffs(group, FLAG_HEROIC, {"attacker_ids": attacker_ids})
		CSV_GUIDANCE:
			_log(player, "CHAMPION'S GUIDANCE: %s's melee attacks can re-roll hit rolls of 1 and wound rolls of 1" % label)
			return Common.set_flag_diffs(group, FLAG_GUIDANCE, true)
		CSV_UNBRIDLED:
			_log(player, "UNBRIDLED FEROCITY: %s's melee attacks have [LANCE] (+1 to wound after a charge move)" % label)
			return _grant_with_marker(group, FLAG_GRANT_LANCE, FLAG_UNBRIDLED_HAD, FLAG_UNBRIDLED)
		CSV_FANGS:
			_log(player, "FANGS OF THE PACK: %s's melee attacks have [PRECISION]" % label)
			return _grant_with_marker(group, FLAG_PRECISION_MELEE, FLAG_FANGS_HAD, FLAG_FANGS)
		CSV_EYE:
			_log(player, "EYE OF THE PACK: %s's attacks can re-roll wound rolls of 1 and 2" % label)
			return Common.set_flag_diffs(group, FLAG_EYE, true)
		CSV_TOTEMS:
			_log(player, "WOLF TOTEMS: %s has Feel No Pain 5+ against mortal wounds (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_TOTEMS, TOTEMS_FNP)
	Common.log_error("SWCodexCombat: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		CSV_HEROIC:
			Common.erase_flags(group, [FLAG_HEROIC])
		CSV_GUIDANCE:
			Common.erase_flags(group, [FLAG_GUIDANCE])
		CSV_UNBRIDLED:
			_clear_with_marker(group, FLAG_GRANT_LANCE, FLAG_UNBRIDLED_HAD, FLAG_UNBRIDLED)
		CSV_FANGS:
			_clear_with_marker(group, FLAG_PRECISION_MELEE, FLAG_FANGS_HAD, FLAG_FANGS)
		CSV_EYE:
			Common.erase_flags(group, [FLAG_EYE])
		CSV_TOTEMS:
			Common.erase_flags(group, [FLAG_TOTEMS])
	Common.log_info("SWCodexCombat: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(_strat: Dictionary, _variant_id: String) -> String:
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, _player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	var engaged := Common.engaged_enemy_ids(uid)
	match csv:
		CSV_HEROIC:
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var share := _multi_damage_share(attacker, window_id == W_FIGHT_TARGETS)
			if share <= 0.0:
				return 0.0
			return (1.5 + float(Common.group_points(uid)) / 60.0) * (0.5 + share)
		CSV_GUIDANCE:
			return 2.5 if not engaged.is_empty() and Common.group_has_melee_weapons(uid) else 0.0
		CSV_UNBRIDLED:
			# [LANCE] only adds +1 to wound after a charge move this turn.
			if engaged.is_empty() or not Common.group_has_melee_weapons(uid) or not _group_charged(uid):
				return 0.0
			return 2.5
		CSV_FANGS:
			# [PRECISION] matters only against an Attached unit with a CHARACTER in it.
			if not Common.group_has_melee_weapons(uid):
				return 0.0
			for eid in engaged:
				var e_head := Common.head_id(str(eid))
				if not Common.unit(e_head).get("attachment_data", {}).get("attached_characters", []).is_empty():
					return 2.4
			return 0.0
		CSV_EYE:
			if window_id == W_SELECTED_TO_SHOOT:
				if not Common.group_has_ranged_weapons(uid):
					return 0.0
				var planned: Array = ctx.get("planned_target_unit_ids", [])
				if not planned.is_empty() or Common.nearest_enemy_inches(Common.group_union(uid)) <= 24.0:
					return 2.3
				return 0.0
			return 2.3 if not engaged.is_empty() and Common.group_has_melee_weapons(uid) else 0.0
		CSV_TOTEMS:
			return _totems_score(uid)
	return 0.0


# ===========================================================================
# Engine consumers (SWCodex11e hooks)
# ===========================================================================

## Source name of a "re-roll hit rolls of 1" on this attack batch ("" = none).
static func hit_reroll_ones_source(attacker_unit: Dictionary, is_melee: bool) -> String:
	if is_melee and bool(attacker_unit.get("flags", {}).get(FLAG_GUIDANCE, false)):
		return "Champion's Guidance"
	return ""

## {ones: source|"" (re-roll wound 1s), ones_twos: source|"" (re-roll 1s and 2s)}.
static func wound_reroll_effects(attacker_unit: Dictionary, is_melee: bool) -> Dictionary:
	var flags: Dictionary = attacker_unit.get("flags", {})
	var out := {"ones": "", "ones_twos": ""}
	if is_melee and bool(flags.get(FLAG_GUIDANCE, false)):
		out.ones = "Champion's Guidance"
	if bool(flags.get(FLAG_EYE, false)):
		out.ones_twos = "Eye of the Pack"
	return out

static func damage_minus(target_unit: Dictionary) -> int:
	return 1 if typeof(target_unit.get("flags", {}).get(FLAG_HEROIC, null)) == TYPE_DICTIONARY else 0

static func fnp_vs_mortal(unit: Dictionary) -> int:
	return int(unit.get("flags", {}).get(FLAG_TOTEMS, 0))

## HEROIC RESOLVE ends once the enemy unit it was used against has attacked.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	if attacker_unit_id == "":
		return
	var units: Dictionary = Common.state().get("units", {})
	var ended: Array = []
	for uid in units:
		var f = units[uid].get("flags", {}).get(FLAG_HEROIC, null)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if attacker_unit_id in f.get("attacker_ids", []):
			units[uid]["flags"].erase(FLAG_HEROIC)
			ended.append(uid)
	if not ended.is_empty():
		Common.log_info("SWCodexCombat: HEROIC RESOLVE ended on %s — %s has attacked" % [str(ended), attacker_unit_id])


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_HEROIC:
			if window_id != W_SHOOT_TARGETS and window_id != W_FIGHT_TARGETS:
				return []
			var out: Array = []
			for tid in ctx.get("target_unit_ids", []):
				var h := Common.head_id(str(tid))
				if h != "" and not h in out:
					out.append(h)
			return out
		CSV_GUIDANCE, CSV_UNBRIDLED, CSV_FANGS:
			if window_id != W_SELECTED_TO_FIGHT:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
		CSV_EYE:
			if window_id != W_SELECTED_TO_FIGHT and window_id != W_SELECTED_TO_SHOOT:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
	return []


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
	if not Common.group_has_keyword(head, KW_AA):
		return _no("%s can only target an ADEPTUS ASTARTES unit" % sname)
	var my_turn := Common.active_player() == player
	match csv:
		CSV_HEROIC:
			if not Common.group_has_keyword(head, "CHARACTER"):
				return _no("HEROIC RESOLVE can only target an ADEPTUS ASTARTES CHARACTER unit")
			if window_id == W_SHOOT_TARGETS and my_turn:
				return _no("HEROIC RESOLVE: only in your opponent's Shooting phase")
			if ctx.has("target_unit_ids") and not Common.group_in(head, ctx.get("target_unit_ids", [])):
				return _no("HEROIC RESOLVE must target the unit the enemy unit targeted")
		CSV_GUIDANCE, CSV_UNBRIDLED, CSV_FANGS, CSV_EYE:
			var selected := str(ctx.get("unit_id", ""))
			if selected != "" and Common.head_id(selected) != head:
				return _no("%s must target the unit that was selected to %s" % [sname, "shoot" if window_id == W_SELECTED_TO_SHOOT else "fight"])
			match csv:
				CSV_GUIDANCE:
					if not Common.group_has_keyword(head, "CHARACTER"):
						return _no("CHAMPION'S GUIDANCE can only target an ADEPTUS ASTARTES CHARACTER unit")
				CSV_UNBRIDLED:
					if not Common.group_has_any_keyword(head, BEAST_KWS):
						return _no("UNBRIDLED FEROCITY can only target a BLOOD CLAWS/THUNDERWOLF CAVALRY/WULFEN unit")
				CSV_FANGS:
					if not Common.group_has_any_keyword(head, ["INFANTRY", "MOUNTED"]):
						return _no("FANGS OF THE PACK can only target an ADEPTUS ASTARTES INFANTRY/MOUNTED unit")
				CSV_EYE:
					if not Common.group_has_keyword(head, "INFANTRY"):
						return _no("EYE OF THE PACK can only target an ADEPTUS ASTARTES INFANTRY unit")
					if window_id == W_SELECTED_TO_SHOOT and not my_turn:
						return _no("EYE OF THE PACK: only in your Shooting phase (or the Fight phase)")
		CSV_TOTEMS:
			if not Common.group_has_any_keyword(head, ["INFANTRY", "MOUNTED"]):
				return _no("WOLF TOTEMS can only target an ADEPTUS ASTARTES INFANTRY/MOUNTED unit")
	return {"ok": true, "reason": ""}


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_HEROIC: return "HEROIC RESOLVE"
		CSV_GUIDANCE: return "CHAMPION'S GUIDANCE"
		CSV_UNBRIDLED: return "UNBRIDLED FEROCITY"
		CSV_FANGS: return "FANGS OF THE PACK"
		CSV_EYE: return "EYE OF THE PACK"
		CSV_TOTEMS: return "WOLF TOTEMS"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SWCodexCombat: " + msg)
	Common.game_log(player, msg)

## Set a generic engine grant (effect_grant_lance / effect_precision_melee) on
## every component, remembering whether it was already there.
static func _grant_with_marker(group: Array, grant_flag: String, had_flag: String, marker_flag: String) -> Array:
	var diffs: Array = []
	for gid in group:
		var had := bool(Common.unit(str(gid)).get("flags", {}).get(grant_flag, false))
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), had_flag], "value": had})
	diffs.append_array(Common.set_flag_diffs(group, grant_flag, true))
	diffs.append_array(Common.set_flag_diffs(group, marker_flag, true))
	return diffs

static func _clear_with_marker(group: Array, grant_flag: String, had_flag: String, marker_flag: String) -> void:
	var units: Dictionary = Common.state().get("units", {})
	for gid in group:
		var f = units.get(str(gid), {}).get("flags", null)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if f.has(marker_flag) and not bool(f.get(had_flag, false)):
			f.erase(grant_flag)
		f.erase(marker_flag)
		f.erase(had_flag)

static func _group_charged(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
			return true
	return false

## Average of a dice/number characteristic ("2", "D3", "D6+1", "2D6").
static func _avg(v) -> float:
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

## Share of the attacker's weapon profiles (melee or ranged) whose average
## Damage is 2 or more — what a -1 D actually blunts.
static func _multi_damage_share(attacker_id: String, melee: bool) -> float:
	if attacker_id == "":
		return 0.0
	var total := 0
	var multi := 0
	for gid in Common.attached_group_ids(attacker_id):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			var is_melee := str(w.get("type", "")).to_lower() == "melee"
			if is_melee != melee:
				continue
			total += 1
			if _avg(w.get("damage", "1")) >= 2.0:
				multi += 1
	return float(multi) / float(total) if total > 0 else 0.0

## WOLF TOTEMS (proactive, the AI's own phase): worth it on a valuable unit
## that is about to suffer mortal wounds — its own [HAZARDOUS] weapons, or an
## enemy within 12" with [DEVASTATING WOUNDS] weapons.
## It lasts only until the end of the phase it is used in, so it is worth
## it only where those mortal wounds come: [HAZARDOUS] ranged weapons in the
## Shooting phase, [HAZARDOUS] melee or enemy [DEVASTATING WOUNDS] in the Fight
## phase (never the Command / Movement / Charge phase — WP-S5: the AI spent it
## in its Command phase, where it expired unused).
static func _totems_score(uid: String) -> float:
	if Common.group_points(uid) < 80:
		return 0.0
	var phase := Common.current_phase()
	var shooting := phase == Common.GameStateData.Phase.SHOOTING
	var fight := phase == Common.GameStateData.Phase.FIGHT
	if not shooting and not fight:
		return 0.0
	for gid in Common.attached_group_ids(uid):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			if not "hazardous" in str(w.get("special_rules", "")).to_lower():
				continue
			var melee := str(w.get("type", "")).to_lower() == "melee"
			if (shooting and not melee) or (fight and melee):
				return 2.2
	if not fight:
		return 0.0
	var player := int(Common.unit(uid).get("owner", 0))
	for eid in Common.enemy_heads(player):
		if Common.group_distance_inches(uid, str(eid)) > 12.0:
			continue
		for gid in Common.attached_group_ids(str(eid)):
			for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
				if "devastating" in str(w.get("special_rules", "")).to_lower():
					return 2.2
	return 0.0
