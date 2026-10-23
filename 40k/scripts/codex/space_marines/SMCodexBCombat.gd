extends RefCounted

## SMCodexBCombat — Codex: Space Marines (11e) generic detachment stratagems
## that change ATTACKS (WP-M3b). Facade: SMCodexB.gd (the group script M3a's
## `custom:sm11e` dispatcher SMCodex11e.gd delegates to). Rulings:
## .llm/codex_11e_wahapedia/RULINGS.md § WP-M3b.
##
##   TACTICAL DREADNOUGHT FORTITUDE (Terminator Storm Force, 2CP)
##       enemy_targets_unit_shooting (opponent's Shooting phase) /
##       enemy_targets_unit_fight: attacks that target the TERMINATOR unit have
##       -1 D until that enemy unit has attacked.
##   MERCILESS VETERANS (Terminator Storm Force, 1CP) unit_selected_to_shoot:
##       TERMINATOR ranged [LETHAL HITS] + [SUSTAINED HITS 1].
##   ARMOUR OF CONTEMPT (Assault / Devastator / Tactical Brethren, 1CP)
##       enemy_targets_unit_shooting / _fight: -1 AP to attacks that target the
##       unit until that enemy unit has attacked.
##   DUTY IN DEATH (Assault Brethren, 1CP) enemy_targets_unit_fight: the
##       engine's Fight On Death (05.04.05) — 4+ (+1 assault doctrine).
##   GENE-WROUGHT MIGHT (Assault Brethren, 1CP) unit_selected_to_fight: melee
##       [LANCE]; with the assault doctrine also +1 AP.
##   ANNIHILATING FORCE (Gravis Linebreaker / Gravis Siege Force, 1CP)
##       unit_selected_to_shoot (your Shooting phase) / unit_selected_to_fight:
##       GRAVIS attacks [LETHAL HITS].
##   STORM OF FIRE (Devastator Brethren, 1CP) unit_selected_to_shoot: ranged
##       [IGNORES COVER]; with the devastator doctrine also +1 AP.
##   MERCY IS WEAKNESS (Ironclad Champions, 1CP) unit_selected_to_shoot /
##       unit_selected_to_fight: DREADNOUGHT attacks [LETHAL HITS] OR
##       [SUSTAINED HITS 1] (dialog variant).
##   POINT-BLANK BRUTALITY (Tacticus Firestorm Force, 1CP)
##       unit_selected_to_shoot: an ENGAGED TACTICUS unit's ranged attacks
##       (excluding [BLAST]) have [CLOSE-QUARTERS] and [IGNORES COVER].
##   RELENTLESS ASSAULT (Tacticus Firestorm Force, 1CP)
##       unit_selected_to_shoot / unit_selected_to_fight: TACTICUS attacks
##       [SUSTAINED HITS 1: non-MONSTER/VEHICLE] OR [LETHAL HITS:
##       MONSTER/VEHICLE] (dialog variant).
##
## Handler API (static; called by the SMCodexB facade only): eligible_targets /
## validate / apply / clear / ai_kind / ai_score / variant_cp_cost /
## variant_label / allows_battle_shocked_target.
##
## Flags (sm11e_ prefix — never effect_, the Shooting phase wipes effect_* —
## they expire through StratagemManager's active-effect expiry, end of phase):
##   sm11e_tdf_fortitude   {attacker_ids}       -> damage_minus()
##   sm11e_aoc             {attacker_ids}       -> ap_worsen()
##   sm11e_merciless       bool                 -> merge_attack_mods (ranged lethal + sustained 1)
##   sm11e_annihilating    bool                 -> merge_attack_mods (lethal)
##   sm11e_storm_of_fire   bool                 -> merge_attack_mods (ranged ignores cover, +1 AP devastator)
##   sm11e_gene_wrought    bool + effect_grant_lance (RulesEngine melee [LANCE]); +1 AP assault (merge_attack_mods)
##   sm11e_mercy           "lethal" | "sustained"
##   sm11e_relentless      "sustained" | "lethal"
##   sm11e_point_blank     bool                 -> close-quarters grant + ignores cover (non-[BLAST])
##   ork11e_fod_mode = "sm11e_duty_in_death" + ork11e_fod_source (FightPhase Fight On Death)

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_TDF := "tactical-dreadnought-fortitude-terminator-storm-force"
const CSV_MERCILESS := "merciless-veterans-terminator-storm-force"
const CSV_AOC_AB := "armour-of-contempt-assault-brethren"
const CSV_AOC_DB := "armour-of-contempt-devastator-brethren"
const CSV_AOC_TB := "armour-of-contempt-tactical-brethren"
const CSV_DUTY := "duty-in-death-assault-brethren"
const CSV_GENE := "gene-wrought-might-assault-brethren"
const CSV_ANNIH_GLF := "annihilating-force-gravis-linebreaker-force"
const CSV_ANNIH_GSF := "annihilating-force-gravis-siege-force"
const CSV_STORM := "storm-of-fire-devastator-brethren"
const CSV_MERCY := "mercy-is-weakness-ironclad-champions"
const CSV_POINT_BLANK := "point-blank-brutality-tacticus-firestorm-force"
const CSV_RELENTLESS := "relentless-assault-tacticus-firestorm-force"

const IDS: Array = [CSV_TDF, CSV_MERCILESS, CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB, CSV_DUTY, CSV_GENE,
	CSV_ANNIH_GLF, CSV_ANNIH_GSF, CSV_STORM, CSV_MERCY, CSV_POINT_BLANK, CSV_RELENTLESS]

const IMPLEMENTED: Dictionary = {
	CSV_TDF: true, CSV_MERCILESS: true, CSV_AOC_AB: true, CSV_AOC_DB: true, CSV_AOC_TB: true,
	CSV_DUTY: true, CSV_GENE: true, CSV_ANNIH_GLF: true, CSV_ANNIH_GSF: true, CSV_STORM: true,
	CSV_MERCY: true, CSV_POINT_BLANK: true, CSV_RELENTLESS: true,
}

const AI_KIND: Dictionary = {
	CSV_TDF: "defensive", CSV_MERCILESS: "offensive", CSV_AOC_AB: "defensive", CSV_AOC_DB: "defensive",
	CSV_AOC_TB: "defensive", CSV_DUTY: "defensive", CSV_GENE: "offensive", CSV_ANNIH_GLF: "offensive",
	CSV_ANNIH_GSF: "offensive", CSV_STORM: "offensive", CSV_MERCY: "offensive",
	CSV_POINT_BLANK: "offensive", CSV_RELENTLESS: "offensive",
}

const AOC_IDS: Array = [CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB]
const ANNIH_IDS: Array = [CSV_ANNIH_GLF, CSV_ANNIH_GSF]

const W_SHOOT_TARGETS := "enemy_targets_unit_shooting"
const W_FIGHT_TARGETS := "enemy_targets_unit_fight"
const W_SELECTED_TO_FIGHT := "unit_selected_to_fight"
const W_SELECTED_TO_SHOOT := "unit_selected_to_shoot"

const FLAG_TDF := "sm11e_tdf_fortitude"
const FLAG_AOC := "sm11e_aoc"
const FLAG_MERCILESS := "sm11e_merciless"
const FLAG_ANNIH := "sm11e_annihilating"
const FLAG_STORM := "sm11e_storm_of_fire"
const FLAG_GENE := "sm11e_gene_wrought"
const FLAG_GENE_HAD := "sm11e_gene_had_lance"
const FLAG_GRANT_LANCE := "effect_grant_lance"   # RulesEngine melee [LANCE] grant
const FLAG_MERCY := "sm11e_mercy"
const FLAG_RELENTLESS := "sm11e_relentless"
const FLAG_POINT_BLANK := "sm11e_point_blank"
# DUTY IN DEATH — FightPhase's Fight On Death (05.04.05) is keyed by these
# flag names (shared with the Ork / Custodes codexes).
const FLAG_FOD_MODE := "ork11e_fod_mode"
const FLAG_FOD_SOURCE := "ork11e_fod_source"
const FOD_MODE_DUTY := "sm11e_duty_in_death"
const DUTY_PASS := 4

const V_LETHAL := "lethal"
const V_SUSTAINED := "sustained"

const KW_AA := "ADEPTUS ASTARTES"


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if _check(csv, player, str(uid), window_id, ctx).ok:
			out.append(Common.target_entry(str(uid), _entry_extra(csv, str(uid), window_id, ctx, strat)))
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
	var v := str(ctx.get("variant_id", ""))
	if v != "" and csv in [CSV_MERCY, CSV_RELENTLESS] and not v in [V_LETHAL, V_SUSTAINED]:
		return _no("%s: unknown choice '%s'" % [_name(csv), v])
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_TDF, CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB:
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var attacker_ids: Array = Common.attached_group_ids(attacker) if attacker != "" else []
			var who := Common.group_label(attacker) if attacker != "" else "that enemy unit"
			if csv == CSV_TDF:
				_log(player, "TACTICAL DREADNOUGHT FORTITUDE: attacks that target %s have -1 Damage until %s has attacked" % [label, who])
				return Common.set_flag_diffs(group, FLAG_TDF, {"attacker_ids": attacker_ids})
			_log(player, "ARMOUR OF CONTEMPT: attacks that target %s have -1 AP until %s has attacked" % [label, who])
			return Common.set_flag_diffs(group, FLAG_AOC, {"attacker_ids": attacker_ids})
		CSV_MERCILESS:
			_log(player, "MERCILESS VETERANS: %s's ranged attacks have [LETHAL HITS] and [SUSTAINED HITS 1]" % label)
			return Common.set_flag_diffs(group, FLAG_MERCILESS, true)
		CSV_DUTY:
			var d: Array = Common.set_flag_diffs(group, FLAG_FOD_MODE, FOD_MODE_DUTY)
			d.append_array(Common.set_flag_diffs(group, FLAG_FOD_SOURCE, "DUTY IN DEATH"))
			_log(player, "DUTY IN DEATH: a model of %s destroyed before the unit has fought rolls a D6%s — on a 4+ it is not removed until the unit has fought / the end of the phase" % [
				label, " (+1, assault doctrine)" if _doctrine(head, "assault") else ""])
			return d
		CSV_GENE:
			var assault := _doctrine(head, "assault")
			_log(player, "GENE-WROUGHT MIGHT: %s's melee attacks have [LANCE]%s" % [label, " and +1 AP (assault doctrine)" if assault else ""])
			return _grant_with_marker(group, FLAG_GRANT_LANCE, FLAG_GENE_HAD, FLAG_GENE)
		CSV_ANNIH_GLF, CSV_ANNIH_GSF:
			_log(player, "ANNIHILATING FORCE: %s's attacks have [LETHAL HITS]" % label)
			return Common.set_flag_diffs(group, FLAG_ANNIH, true)
		CSV_STORM:
			var dev := _doctrine(head, "devastator")
			_log(player, "STORM OF FIRE: %s's ranged attacks have [IGNORES COVER]%s" % [label, " and +1 AP (devastator doctrine)" if dev else ""])
			return Common.set_flag_diffs(group, FLAG_STORM, true)
		CSV_MERCY:
			var mv := _variant_or(ctx, ai_mercy_variant(head))
			_log(player, "MERCY IS WEAKNESS: %s's attacks have %s" % [label, "[LETHAL HITS]" if mv == V_LETHAL else "[SUSTAINED HITS 1]"])
			return Common.set_flag_diffs(group, FLAG_MERCY, mv)
		CSV_POINT_BLANK:
			_log(player, "POINT-BLANK BRUTALITY: %s's ranged attacks (excluding [BLAST]) have [CLOSE-QUARTERS] and [IGNORES COVER]" % label)
			return Common.set_flag_diffs(group, FLAG_POINT_BLANK, true)
		CSV_RELENTLESS:
			var rv := _variant_or(ctx, ai_relentless_variant(head, ctx))
			_log(player, "RELENTLESS ASSAULT: %s's attacks have %s" % [label,
				"[SUSTAINED HITS 1] against non-MONSTER/VEHICLE units" if rv == V_SUSTAINED else "[LETHAL HITS] against MONSTER/VEHICLE units"])
			return Common.set_flag_diffs(group, FLAG_RELENTLESS, rv)
	Common.log_error("SMCodexBCombat: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		CSV_TDF:
			Common.erase_flags(group, [FLAG_TDF])
		CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB:
			Common.erase_flags(group, [FLAG_AOC])
		CSV_MERCILESS:
			Common.erase_flags(group, [FLAG_MERCILESS])
		CSV_DUTY:
			# Only the mode this stratagem wrote (another Fight On Death rule may own it).
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f = units.get(str(gid), {}).get("flags", null)
				if typeof(f) == TYPE_DICTIONARY and str(f.get(FLAG_FOD_MODE, "")) == FOD_MODE_DUTY:
					f.erase(FLAG_FOD_MODE)
					f.erase(FLAG_FOD_SOURCE)
		CSV_GENE:
			_clear_with_marker(group, FLAG_GRANT_LANCE, FLAG_GENE_HAD, FLAG_GENE)
		CSV_ANNIH_GLF, CSV_ANNIH_GSF:
			Common.erase_flags(group, [FLAG_ANNIH])
		CSV_STORM:
			Common.erase_flags(group, [FLAG_STORM])
		CSV_MERCY:
			Common.erase_flags(group, [FLAG_MERCY])
		CSV_POINT_BLANK:
			Common.erase_flags(group, [FLAG_POINT_BLANK])
		CSV_RELENTLESS:
			Common.erase_flags(group, [FLAG_RELENTLESS])
	Common.log_info("SMCodexBCombat: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	match str(strat.get("csv_id", "")):
		CSV_MERCY:
			return "[LETHAL HITS]" if variant_id == V_LETHAL else "[SUSTAINED HITS 1]"
		CSV_RELENTLESS:
			return "[SUSTAINED HITS 1: non-MONSTER/VEHICLE]" if variant_id == V_SUSTAINED else "[LETHAL HITS: MONSTER/VEHICLE]"
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, _player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	if uid == "":
		return 0.0
	var engaged := Common.engaged_enemy_ids(uid)
	var shooting := window_id == W_SELECTED_TO_SHOOT
	match csv:
		CSV_TDF:
			var share := _multi_damage_share(Common.head_id(str(ctx.get("attacker_unit_id", ""))), window_id == W_FIGHT_TARGETS)
			if share <= 0.0:
				return 0.0
			return (1.5 + float(Common.group_points(uid)) / 60.0) * (0.5 + share)
		CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB:
			# -1 AP only matters against attacks that have AP; worth more on a
			# valuable unit with a good save.
			var ap_share := _ap_share(Common.head_id(str(ctx.get("attacker_unit_id", ""))), window_id == W_FIGHT_TARGETS)
			if ap_share <= 0.0:
				return 0.0
			return (1.0 + float(Common.group_points(uid)) / 80.0) * (0.5 + ap_share)
		CSV_DUTY:
			# The unit has not fought yet and can strike back.
			if _group_selected_to_fight(uid) or not Common.group_has_melee_weapons(uid):
				return 0.0
			return 1.6 + float(Common.group_points(uid)) / 150.0
		CSV_MERCILESS:
			return 2.4 if shooting and _has_ranged_target(uid, ctx) else 0.0
		CSV_ANNIH_GLF, CSV_ANNIH_GSF, CSV_MERCY, CSV_RELENTLESS:
			if shooting:
				return 2.3 if _has_ranged_target(uid, ctx) else 0.0
			return 2.3 if not engaged.is_empty() and Common.group_has_melee_weapons(uid) else 0.0
		CSV_GENE:
			if engaged.is_empty() or not Common.group_has_melee_weapons(uid):
				return 0.0
			# [LANCE] only adds +1 to wound after a charge move; the +1 AP always helps.
			if _group_charged(uid) or _doctrine(uid, "assault"):
				return 2.4
			return 0.0
		CSV_STORM:
			if not _has_ranged_target(uid, ctx):
				return 0.0
			return 2.4 if _doctrine(uid, "devastator") else 2.1
		CSV_POINT_BLANK:
			return 2.5 if not engaged.is_empty() and _has_non_blast_ranged(uid) else 0.0
	return 0.0


## AI / no-choice pick for MERCY IS WEAKNESS: [LETHAL HITS] against tough
## targets (T >= 8 near the unit), else [SUSTAINED HITS 1].
static func ai_mercy_variant(unit_id: String) -> String:
	var player := int(Common.unit(unit_id).get("owner", 0))
	var best := INF
	var tough := 0
	for eid in Common.enemy_heads(player):
		var d := Common.group_distance_inches(unit_id, str(eid))
		if d < best:
			best = d
			tough = int(Common.unit(str(eid)).get("meta", {}).get("stats", {}).get("toughness", 4))
	return V_LETHAL if tough >= 8 else V_SUSTAINED


## RELENTLESS ASSAULT pick: [LETHAL HITS: MONSTER/VEHICLE] when the (planned /
## engaged / nearest) target is a MONSTER or VEHICLE, else [SUSTAINED HITS 1].
static func ai_relentless_variant(unit_id: String, ctx: Dictionary) -> String:
	var target := ""
	var planned: Array = ctx.get("planned_target_unit_ids", [])
	if not planned.is_empty():
		target = str(planned[0])
	if target == "":
		var engaged := Common.engaged_enemy_ids(unit_id)
		if not engaged.is_empty():
			target = str(engaged[0])
	if target == "":
		var best := INF
		for eid in Common.enemy_heads(int(Common.unit(unit_id).get("owner", 0))):
			var d := Common.group_distance_inches(unit_id, str(eid))
			if d < best:
				best = d
				target = str(eid)
	return V_LETHAL if target != "" and Common.group_is_monster_or_vehicle(Common.head_id(target)) else V_SUSTAINED


# ===========================================================================
# Engine consumers (SMCodexB hooks)
# ===========================================================================

## TACTICAL DREADNOUGHT FORTITUDE: attacks that target this unit have -1 D.
static func damage_minus(target_unit: Dictionary) -> int:
	return 1 if typeof(target_unit.get("flags", {}).get(FLAG_TDF, null)) == TYPE_DICTIONARY else 0

## ARMOUR OF CONTEMPT: attacks that target this unit have -1 AP.
static func ap_worsen(target_unit: Dictionary) -> int:
	return 1 if typeof(target_unit.get("flags", {}).get(FLAG_AOC, null)) == TYPE_DICTIONARY else 0

## "Until that enemy unit has attacked": the -1 D / -1 AP end once the enemy
## unit they were used against has finished its attacks.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	if attacker_unit_id == "":
		return
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var flags = units[uid].get("flags", null)
		if typeof(flags) != TYPE_DICTIONARY:
			continue
		for fname in [FLAG_TDF, FLAG_AOC]:
			var f = flags.get(fname, null)
			if typeof(f) == TYPE_DICTIONARY and attacker_unit_id in f.get("attacker_ids", []):
				flags.erase(fname)
				Common.log_info("SMCodexBCombat: %s ended on %s — %s has attacked" % [
					"TACTICAL DREADNOUGHT FORTITUDE" if fname == FLAG_TDF else "ARMOUR OF CONTEMPT", str(uid), attacker_unit_id])

## Attack-batch modifiers (RulesEngine.ork11e_ab_mods aggregator): lethal /
## sustained / ignores cover / AP. `m` uses OrkAbilities11e._empty_mods keys.
static func merge_attack_mods(m: Dictionary, actor: Dictionary, target: Dictionary, weapon_profile: Dictionary, is_melee: bool) -> void:
	var flags = actor.get("flags", {})
	if typeof(flags) != TYPE_DICTIONARY or flags.is_empty():
		return
	var ranged := not is_melee
	var aid := str(actor.get("id", ""))
	if ranged and bool(flags.get(FLAG_MERCILESS, false)):
		_lethal(m, "Merciless Veterans")
		_sustained(m, "Merciless Veterans")
	if bool(flags.get(FLAG_ANNIH, false)):
		_lethal(m, "Annihilating Force")
	if ranged and bool(flags.get(FLAG_STORM, false)):
		m["ignores_cover"] = true
		_src(m, "Storm of Fire", "other", "ignores_cover", "[IGNORES COVER]")
		if _doctrine(aid, "devastator"):
			m["ap"] = int(m.get("ap", 0)) + 1
			_src(m, "Storm of Fire", "other", "ap_plus_one", "devastator doctrine — +1 AP")
	if is_melee and bool(flags.get(FLAG_GENE, false)) and _doctrine(aid, "assault"):
		m["ap"] = int(m.get("ap", 0)) + 1
		_src(m, "Gene-wrought Might", "other", "ap_plus_one", "assault doctrine — +1 AP")
	match str(flags.get(FLAG_MERCY, "")):
		V_LETHAL:
			_lethal(m, "Mercy is Weakness")
		V_SUSTAINED:
			_sustained(m, "Mercy is Weakness")
	var rel := str(flags.get(FLAG_RELENTLESS, ""))
	if rel != "" and not target.is_empty():
		var mv := _target_is_mv(target)
		if rel == V_SUSTAINED and not mv:
			_sustained(m, "Relentless Assault")
		elif rel == V_LETHAL and mv:
			_lethal(m, "Relentless Assault")
	if ranged and bool(flags.get(FLAG_POINT_BLANK, false)) and not _weapon_is_blast(weapon_profile):
		m["ignores_cover"] = true
		_src(m, "Point-blank Brutality", "other", "ignores_cover", "[IGNORES COVER] (non-[BLAST])")

## POINT-BLANK BRUTALITY: the unit's ranged weapons (excluding [BLAST]) have
## [CLOSE-QUARTERS] (CloseQuartersShooting hooks).
static func grants_close_quarters(unit: Dictionary) -> bool:
	return bool(unit.get("flags", {}).get(FLAG_POINT_BLANK, false))

static func weapon_gets_close_quarters(weapon_profile: Dictionary, unit: Dictionary) -> bool:
	if not grants_close_quarters(unit):
		return false
	if str(weapon_profile.get("type", "")).to_lower() == "melee":
		return false
	return not _weapon_is_blast(weapon_profile)

## DUTY IN DEATH Fight On Death roll: 4+, +1 if the assault doctrine is active.
static func is_fod_mode(mode: String) -> bool:
	return mode == FOD_MODE_DUTY

static func fod_roll(unit_id: String, _model_index: int) -> Dictionary:
	if _doctrine(Common.head_id(unit_id), "assault"):
		return {"mod": 1, "note": "+1 assault doctrine", "pass": DUTY_PASS}
	return {"mod": 0, "note": "", "pass": DUTY_PASS}


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_TDF, CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB, CSV_DUTY:
			if window_id != W_FIGHT_TARGETS and (csv == CSV_DUTY or window_id != W_SHOOT_TARGETS):
				return []
			var out: Array = []
			for tid in ctx.get("target_unit_ids", []):
				var h := Common.head_id(str(tid))
				if h != "" and not h in out and int(Common.unit(h).get("owner", 0)) == player:
					out.append(h)
			return out
		CSV_GENE:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_FIGHT else []
		CSV_MERCILESS, CSV_STORM, CSV_POINT_BLANK:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_SHOOT else []
		CSV_ANNIH_GLF, CSV_ANNIH_GSF, CSV_MERCY, CSV_RELENTLESS:
			if window_id != W_SELECTED_TO_SHOOT and window_id != W_SELECTED_TO_FIGHT:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
	return []


static func _entry_extra(csv: String, unit_id: String, _window_id: String, ctx: Dictionary, strat: Dictionary) -> Dictionary:
	var cost := int(strat.get("cp_cost", 1))
	match csv:
		CSV_MERCY:
			return {"require_variant": true, "ai_variant": ai_mercy_variant(unit_id), "variants": [
				{"id": V_LETHAL, "label": "[LETHAL HITS]", "cp_cost": cost},
				{"id": V_SUSTAINED, "label": "Or: [SUSTAINED HITS 1]", "cp_cost": cost}]}
		CSV_RELENTLESS:
			return {"require_variant": true, "ai_variant": ai_relentless_variant(unit_id, ctx), "variants": [
				{"id": V_SUSTAINED, "label": "[SUSTAINED HITS 1: non-MONSTER/VEHICLE]", "cp_cost": cost},
				{"id": V_LETHAL, "label": "Or: [LETHAL HITS: MONSTER/VEHICLE]", "cp_cost": cost}]}
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
	if not Common.group_has_keyword(head, KW_AA):
		return _no("%s can only target an ADEPTUS ASTARTES unit" % sname)
	var my_turn := Common.active_player() == player
	match csv:
		CSV_TDF, CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB, CSV_DUTY:
			if csv == CSV_TDF and not Common.group_has_keyword(head, "TERMINATOR"):
				return _no("TACTICAL DREADNOUGHT FORTITUDE can only target an ADEPTUS ASTARTES TERMINATOR unit")
			if window_id == W_SHOOT_TARGETS and my_turn:
				return _no("%s: only in your opponent's Shooting phase (or the Fight phase)" % sname)
			if window_id == W_SHOOT_TARGETS and csv == CSV_DUTY:
				return _no("DUTY IN DEATH: only in the Fight phase")
			if ctx.has("target_unit_ids") and not Common.group_in(head, ctx.get("target_unit_ids", [])):
				return _no("%s must target the unit the enemy unit targeted" % sname)
			if csv == CSV_DUTY and _group_selected_to_fight(head):
				return _no("DUTY IN DEATH: that unit has already been selected to fight this phase (no effect)")
		_:
			var selected := str(ctx.get("unit_id", ""))
			if selected != "" and Common.head_id(selected) != head:
				return _no("%s must target the unit that was selected to %s" % [sname, "shoot" if window_id == W_SELECTED_TO_SHOOT else "fight"])
			if window_id == W_SELECTED_TO_SHOOT and not my_turn:
				return _no("%s: only in your Shooting phase" % sname)
			match csv:
				CSV_MERCILESS:
					if not Common.group_has_keyword(head, "TERMINATOR"):
						return _no("MERCILESS VETERANS can only target an ADEPTUS ASTARTES TERMINATOR unit")
				CSV_ANNIH_GLF, CSV_ANNIH_GSF:
					if not Common.group_has_keyword(head, "GRAVIS"):
						return _no("ANNIHILATING FORCE can only target a GRAVIS unit")
				CSV_MERCY:
					if not Common.group_has_keyword(head, "DREADNOUGHT"):
						return _no("MERCY IS WEAKNESS can only target a DREADNOUGHT unit")
				CSV_POINT_BLANK:
					if not Common.group_has_keyword(head, "TACTICUS"):
						return _no("POINT-BLANK BRUTALITY can only target a TACTICUS unit")
					if not Common.is_engaged(head):
						return _no("POINT-BLANK BRUTALITY: the TACTICUS unit must be engaged")
				CSV_RELENTLESS:
					if not Common.group_has_keyword(head, "TACTICUS"):
						return _no("RELENTLESS ASSAULT can only target a TACTICUS unit")
	return {"ok": true, "reason": ""}


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_TDF: return "TACTICAL DREADNOUGHT FORTITUDE"
		CSV_MERCILESS: return "MERCILESS VETERANS"
		CSV_AOC_AB, CSV_AOC_DB, CSV_AOC_TB: return "ARMOUR OF CONTEMPT"
		CSV_DUTY: return "DUTY IN DEATH"
		CSV_GENE: return "GENE-WROUGHT MIGHT"
		CSV_ANNIH_GLF, CSV_ANNIH_GSF: return "ANNIHILATING FORCE"
		CSV_STORM: return "STORM OF FIRE"
		CSV_MERCY: return "MERCY IS WEAKNESS"
		CSV_POINT_BLANK: return "POINT-BLANK BRUTALITY"
		CSV_RELENTLESS: return "RELENTLESS ASSAULT"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SMCodexBCombat: " + msg)
	Common.game_log(player, msg)

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _lethal(m: Dictionary, source: String) -> void:
	if not bool(m.get("lethal", false)):
		m["lethal"] = true
		_src(m, source, "other", "lethal_hits", "[LETHAL HITS]")

static func _sustained(m: Dictionary, source: String) -> void:
	if int(m.get("sustained", 0)) < 1:
		m["sustained"] = 1
		_src(m, source, "other", "sustained_hits_1", "[SUSTAINED HITS 1]")

static func _variant_or(ctx: Dictionary, fallback: String) -> String:
	var v := str(ctx.get("variant_id", ""))
	if v in [V_LETHAL, V_SUSTAINED]:
		return v
	Common.log_info("SMCodexBCombat: used without a choice — %s picked" % fallback)
	return fallback

## A doctrine active for the (Attached) unit (any component — WP-S2 ruling).
static func _doctrine(unit_id: String, doctrine: String) -> bool:
	if unit_id == "":
		return false
	for gid in Common.attached_group_ids(Common.head_id(unit_id)):
		if Common.doctrine_active_id(str(gid), doctrine):
			return true
	return false

static func _target_is_mv(target: Dictionary) -> bool:
	var tid := str(target.get("id", ""))
	if tid != "" and not Common.unit(tid).is_empty():
		return Common.group_is_monster_or_vehicle(Common.head_id(tid))
	return Common.is_monster_or_vehicle(target)

static func _weapon_is_blast(weapon_profile: Dictionary) -> bool:
	if weapon_profile.is_empty():
		return false
	if AbilityRegistry.has_ability(AbilityRegistry.from_weapon(weapon_profile), "blast"):
		return true
	return "blast" in str(weapon_profile.get("special_rules", "")).to_lower()

static func _group_selected_to_fight(unit_id: String) -> bool:
	var ph = Common.phase_manager().get_current_phase_instance() if Common.phase_manager() else null
	if ph == null or not ("units_that_fought" in ph):
		return false
	if ph.has_method("_ork11e_group_selected_to_fight"):
		return bool(ph._ork11e_group_selected_to_fight(Common.head_id(unit_id)))  # the Fight On Death test itself
	for gid in Common.attached_group_ids(unit_id):
		if str(gid) in ph.units_that_fought:
			return true
	var active := str(ph.get("active_fighter_id")) if "active_fighter_id" in ph else ""
	return active != "" and Common.group_in(unit_id, [active])

static func _group_charged(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
			return true
	return false

static func _has_ranged_target(uid: String, ctx: Dictionary) -> bool:
	if not Common.group_has_ranged_weapons(uid):
		return false
	var planned: Array = ctx.get("planned_target_unit_ids", [])
	return not planned.is_empty() or Common.nearest_enemy_inches(Common.group_union(uid)) <= 24.0

static func _has_non_blast_ranged(uid: String) -> bool:
	for gid in Common.attached_group_ids(uid):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() != "melee" and not _weapon_is_blast(w):
				return true
	return false

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

## Share of the attacker's weapon profiles (melee or ranged) with average D >= 2.
static func _multi_damage_share(attacker_id: String, melee: bool) -> float:
	return _weapon_share(attacker_id, melee, func(w): return _avg(w.get("damage", "1")) >= 2.0)

## Share of the attacker's weapon profiles (melee or ranged) with AP worse than 0.
static func _ap_share(attacker_id: String, melee: bool) -> float:
	return _weapon_share(attacker_id, melee, func(w): return absi(int(str(w.get("ap", "0")).replace("-", "").to_int())) > 0)

static func _weapon_share(attacker_id: String, melee: bool, pred: Callable) -> float:
	if attacker_id == "":
		return 0.0
	var total := 0
	var hit := 0
	for gid in Common.attached_group_ids(attacker_id):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			var is_melee := str(w.get("type", "")).to_lower() == "melee"
			if is_melee != melee:
				continue
			total += 1
			if pred.call(w):
				hit += 1
	return float(hit) / float(total) if total > 0 else 0.0
