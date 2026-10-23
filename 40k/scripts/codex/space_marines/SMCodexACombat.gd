extends RefCounted

## SMCodexACombat — Codex: Space Marines (11e) generic detachment stratagems
## that change ATTACKS (WP-M3a). Dispatcher: SMCodex11e.gd. Rulings:
## RULINGS.md § WP-M3a.
##
##   STORM OF DEVASTATION (Gladius, 1CP) unit_selected_to_shoot: ranged
##                        [IGNORES COVER] (engine grant effect_ignores_cover).
##   A WORTHY DEATH       (Gladius, 1CP) enemy_targets_unit_fight: the engine's
##                        Fight On Death (FightPhase._ork11e_fod_intercept,
##                        mode sm11e_worthy_death: D6 4+, no modifier, only
##                        while the unit has not been selected to fight).
##   ARMOUR OF CONTEMPT   (Gladius, 1CP) enemy_targets_unit_shooting (your
##                        opponent's Shooting phase) / enemy_targets_unit_fight:
##                        -1 AP to attacks that target the unit until that
##                        enemy unit has attacked.
##   MIGHT OF ANGELS      (Gladius, 1CP) unit_selected_to_fight: melee [LANCE]
##                        (engine grant effect_grant_lance).
##   HEADHUNTER DOCTRINE  (Ironstorm, 1CP) unit_selected_to_shoot: ranged
##                        [LETHAL HITS: MONSTER/VEHICLE].
##   LAYERED CERAMITE     (Ironstorm, 1CP) S panel, any phase: Feel No Pain 5+
##                        against mortal wounds (this phase) — WOLF TOTEMS ruling.
##   HURTLING TARGETS     (Stormlance, 1CP) enemy_targets_unit_shooting: ranged
##                        attacks that target the unit have -1 to hit (phase).
##   STRIKE FROM THE SHADOWS (Phobos Shadow Force / Phobos Shock Force, 1CP)
##                        unit_selected_to_shoot (your Shooting phase) /
##                        unit_selected_to_fight: a HIDDEN PHOBOS unit's
##                        attacks have +1 S and [LETHAL HITS].
##   RELENTLESS ASSAULT   (Tacticus Attack Force, 1CP) unit_selected_to_shoot /
##                        unit_selected_to_fight: the player picks [SUSTAINED
##                        HITS 1: non-MONSTER/VEHICLE] or [LETHAL HITS:
##                        MONSTER/VEHICLE] (dialog variant).
##   UMBRAL EVASION       (Phobos Shock Force, 1CP) enemy_targets_unit_shooting:
##                        as HURTLING TARGETS for a PHOBOS unit.
##
## Handler API (static; called by the dispatcher only) + the optional engine
## consumers modify_ap / hit_bits / attack_grants / fnp_vs_mortal /
## on_unit_has_attacked (SMCodex11e.gd header).
##
## Flags (written to every component of an Attached unit; expiry through
## StratagemManager's active effect -> clear(), end of the phase unless noted):
##   sm11e_storm_of_devastation  marker + effect_ignores_cover (had: sm11e_storm_had_ic)
##   sm11e_armour_of_contempt    {attacker_ids: [...]} -> modify_ap
##   sm11e_might_of_angels       marker + effect_grant_lance (had: sm11e_angels_had_lance)
##   sm11e_headhunter            bool -> attack_grants (ranged, vs MONSTER/VEHICLE)
##   sm11e_layered_ceramite      int (5) -> fnp_vs_mortal
##   sm11e_hurtling_targets      bool -> hit_bits (-1, ranged attacks that target it)
##   sm11e_umbral_evasion        bool -> hit_bits (-1, ranged attacks that target it)
##   sm11e_strike_shadows        bool -> attack_grants (+1 S, lethal)
##   sm11e_relentless_assault    "sustained" | "lethal" -> attack_grants
##   ork11e_fod_mode / ork11e_fod_source  (A WORTHY DEATH, the engine's FOD keys)

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const CSV_STORM := "storm-of-devastation-gladius-task-force"
const CSV_WORTHY := "a-worthy-death-gladius-task-force"
const CSV_CONTEMPT := "armour-of-contempt-gladius-task-force"
const CSV_ANGELS := "might-of-angels-gladius-task-force"
const CSV_HEADHUNTER := "headhunter-doctrine-ironstorm-spearhead"
const CSV_CERAMITE := "layered-ceramite-ironstorm-spearhead"
const CSV_HURTLING := "hurtling-targets-stormlance-task-force"
const CSV_SHADOWS_A := "strike-from-the-shadows-phobos-shadow-force"
const CSV_SHADOWS_B := "strike-from-the-shadows-phobos-shock-force"
const CSV_RELENTLESS := "relentless-assault-tacticus-attack-force"
const CSV_UMBRAL := "umbral-evasion-phobos-shock-force"

const IDS: Array = [CSV_STORM, CSV_WORTHY, CSV_CONTEMPT, CSV_ANGELS, CSV_HEADHUNTER, CSV_CERAMITE,
	CSV_HURTLING, CSV_SHADOWS_A, CSV_SHADOWS_B, CSV_RELENTLESS, CSV_UMBRAL]

const IMPLEMENTED: Dictionary = {
	CSV_STORM: true, CSV_WORTHY: true, CSV_CONTEMPT: true, CSV_ANGELS: true, CSV_HEADHUNTER: true,
	CSV_CERAMITE: true, CSV_HURTLING: true, CSV_SHADOWS_A: true, CSV_SHADOWS_B: true,
	CSV_RELENTLESS: true, CSV_UMBRAL: true,
}

const AI_KIND: Dictionary = {
	CSV_STORM: "offensive", CSV_WORTHY: "defensive", CSV_CONTEMPT: "defensive", CSV_ANGELS: "offensive",
	CSV_HEADHUNTER: "offensive", CSV_CERAMITE: "defensive", CSV_HURTLING: "defensive",
	CSV_SHADOWS_A: "offensive", CSV_SHADOWS_B: "offensive", CSV_RELENTLESS: "offensive", CSV_UMBRAL: "defensive",
}

const W_SHOOT_TARGETS := "enemy_targets_unit_shooting"
const W_FIGHT_TARGETS := "enemy_targets_unit_fight"
const W_SELECTED_TO_FIGHT := "unit_selected_to_fight"
const W_SELECTED_TO_SHOOT := "unit_selected_to_shoot"

const FLAG_STORM := "sm11e_storm_of_devastation"
const FLAG_STORM_HAD := "sm11e_storm_had_ic"
const FLAG_IGNORES_COVER := "effect_ignores_cover"      # EffectPrimitives.FLAG_IGNORES_COVER
const FLAG_CONTEMPT := "sm11e_armour_of_contempt"
const FLAG_ANGELS := "sm11e_might_of_angels"
const FLAG_ANGELS_HAD := "sm11e_angels_had_lance"
const FLAG_GRANT_LANCE := "effect_grant_lance"          # RulesEngine melee [LANCE] grant
const FLAG_HEADHUNTER := "sm11e_headhunter"
const FLAG_CERAMITE := "sm11e_layered_ceramite"
const FLAG_HURTLING := "sm11e_hurtling_targets"
const FLAG_UMBRAL := "sm11e_umbral_evasion"
const FLAG_SHADOWS := "sm11e_strike_shadows"
const FLAG_RELENTLESS := "sm11e_relentless_assault"
const FLAG_FOD_MODE := "ork11e_fod_mode"                # the engine's Fight On Death keys (FightPhase)
const FLAG_FOD_SOURCE := "ork11e_fod_source"

const FOD_MODE_WORTHY := "sm11e_worthy_death"
const WORTHY_PASS := 4
const CERAMITE_FNP := 5

const KW_AA := "ADEPTUS ASTARTES"
const RA_SUSTAINED := "sustained"
const RA_LETHAL := "lethal"
const RA_LABELS := {
	RA_SUSTAINED: "[SUSTAINED HITS 1] vs non-MONSTER/VEHICLE",
	RA_LETHAL: "[LETHAL HITS] vs MONSTER/VEHICLE",
}

# RulesEngine.HitModifier.MINUS_ONE (pinned by the test through SMCodex11e).
const HIT_MINUS_ONE := 4


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, window_id, ctx):
		if uid == "" or not _check(csv, player, str(uid), window_id, ctx).ok:
			continue
		var extra := {}
		if csv == CSV_RELENTLESS:
			var variants: Array = []
			for v in [RA_SUSTAINED, RA_LETHAL]:
				variants.append({"id": v, "label": str(RA_LABELS[v]), "cp_cost": int(strat.get("cp_cost", 1))})
			extra = {"require_variant": true, "ai_variant": ai_relentless_variant(str(uid), window_id, ctx), "variants": variants}
		out.append(Common.target_entry(str(uid), extra))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	var window_id := str(ctx.get("window_id", ""))
	if target_unit_id == "":
		# S panel probe (no target): LAYERED CERAMITE may be used when one
		# friendly unit qualifies; every other stratagem here is a window one.
		if csv == CSV_CERAMITE:
			for uid in Common.friendly_heads(player):
				if _check(csv, player, str(uid), window_id, ctx).ok:
					return {"ok": true, "reason": ""}
			return _no("LAYERED CERAMITE: no friendly ADEPTUS ASTARTES VEHICLE unit on the battlefield")
		return _no("%s needs a target unit" % strat.get("name", "?"))
	var c := _check(csv, player, target_unit_id, window_id, ctx)
	if not c.ok:
		return c
	if csv == CSV_RELENTLESS:
		var v := str(ctx.get("variant_id", ""))
		if v != "" and not v in [RA_SUSTAINED, RA_LETHAL]:
			return _no("RELENTLESS ASSAULT: unknown option '%s'" % v)
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		CSV_STORM:
			_log(player, "STORM OF DEVASTATION: %s's ranged attacks have [IGNORES COVER]" % label)
			return _grant_with_marker(group, FLAG_IGNORES_COVER, FLAG_STORM_HAD, FLAG_STORM)
		CSV_WORTHY:
			var d: Array = Common.set_flag_diffs(group, FLAG_FOD_MODE, FOD_MODE_WORTHY)
			d.append_array(Common.set_flag_diffs(group, FLAG_FOD_SOURCE, "A WORTHY DEATH"))
			_log(player, "A WORTHY DEATH: when a model of %s is destroyed before it has been selected to fight, roll a D6 — on a 4+ it is not removed until the unit has fought (or the end of the phase)" % label)
			return d
		CSV_CONTEMPT:
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var attacker_ids: Array = Common.attached_group_ids(attacker) if attacker != "" else []
			_log(player, "ARMOUR OF CONTEMPT: attacks that target %s have -1 AP until %s has attacked" % [
				label, Common.group_label(attacker) if attacker != "" else "that enemy unit"])
			return Common.set_flag_diffs(group, FLAG_CONTEMPT, {"attacker_ids": attacker_ids})
		CSV_ANGELS:
			_log(player, "MIGHT OF ANGELS: %s's melee attacks have [LANCE] (+1 to wound after a charge move)" % label)
			return _grant_with_marker(group, FLAG_GRANT_LANCE, FLAG_ANGELS_HAD, FLAG_ANGELS)
		CSV_HEADHUNTER:
			_log(player, "HEADHUNTER DOCTRINE: %s's ranged attacks have [LETHAL HITS: MONSTER/VEHICLE]" % label)
			return Common.set_flag_diffs(group, FLAG_HEADHUNTER, true)
		CSV_CERAMITE:
			_log(player, "LAYERED CERAMITE: %s has Feel No Pain 5+ against mortal wounds (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_CERAMITE, CERAMITE_FNP)
		CSV_HURTLING:
			_log(player, "HURTLING TARGETS: ranged attacks that target %s have -1 to hit (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_HURTLING, true)
		CSV_UMBRAL:
			_log(player, "UMBRAL EVASION: ranged attacks that target %s have -1 to hit (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_UMBRAL, true)
		CSV_SHADOWS_A, CSV_SHADOWS_B:
			_log(player, "STRIKE FROM THE SHADOWS: %s's attacks have +1 Strength and [LETHAL HITS] (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_SHADOWS, true)
		CSV_RELENTLESS:
			var v := str(ctx.get("variant_id", ""))
			if not v in [RA_SUSTAINED, RA_LETHAL]:
				v = ai_relentless_variant(head, str(ctx.get("window_id", "")), ctx)
				Common.log_info("SMCodexACombat: RELENTLESS ASSAULT used without a choice — %s picked" % v)
			_log(player, "RELENTLESS ASSAULT: %s's attacks have %s (this phase)" % [label, str(RA_LABELS[v])])
			return Common.set_flag_diffs(group, FLAG_RELENTLESS, v)
	Common.log_error("SMCodexACombat: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		CSV_STORM:
			_clear_with_marker(group, FLAG_IGNORES_COVER, FLAG_STORM_HAD, FLAG_STORM)
		CSV_WORTHY:
			# The kept models themselves (ork11e_fod_pending) are removed by the
			# FightPhase when the unit has fought / at the end of the phase.
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f = units.get(str(gid), {}).get("flags", null)
				if typeof(f) == TYPE_DICTIONARY and str(f.get(FLAG_FOD_MODE, "")) == FOD_MODE_WORTHY:
					f.erase(FLAG_FOD_MODE)
					f.erase(FLAG_FOD_SOURCE)
		CSV_CONTEMPT:
			Common.erase_flags(group, [FLAG_CONTEMPT])
		CSV_ANGELS:
			_clear_with_marker(group, FLAG_GRANT_LANCE, FLAG_ANGELS_HAD, FLAG_ANGELS)
		CSV_HEADHUNTER:
			Common.erase_flags(group, [FLAG_HEADHUNTER])
		CSV_CERAMITE:
			Common.erase_flags(group, [FLAG_CERAMITE])
		CSV_HURTLING:
			Common.erase_flags(group, [FLAG_HURTLING])
		CSV_UMBRAL:
			Common.erase_flags(group, [FLAG_UMBRAL])
		CSV_SHADOWS_A, CSV_SHADOWS_B:
			Common.erase_flags(group, [FLAG_SHADOWS])
		CSV_RELENTLESS:
			Common.erase_flags(group, [FLAG_RELENTLESS])
	Common.log_info("SMCodexACombat: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if str(strat.get("csv_id", "")) == CSV_RELENTLESS:
		return str(RA_LABELS.get(variant_id, variant_id))
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
		CSV_STORM:
			# [IGNORES COVER] only matters against a target that has the benefit of cover.
			if not Common.group_has_ranged_weapons(uid):
				return 0.0
			return 2.3 if _planned_target_has_cover(uid, ctx) else 0.0
		CSV_HEADHUNTER:
			if not Common.group_has_ranged_weapons(uid):
				return 0.0
			for tid in _planned_or_near_targets(uid, ctx, 36.0):
				if Common.group_is_monster_or_vehicle(str(tid)):
					return 2.4
			return 0.0
		CSV_SHADOWS_A, CSV_SHADOWS_B:
			if window_id == W_SELECTED_TO_SHOOT:
				return 2.5 if Common.group_has_ranged_weapons(uid) and not _planned_or_near_targets(uid, ctx, 30.0).is_empty() else 0.0
			return 2.5 if not engaged.is_empty() and Common.group_has_melee_weapons(uid) else 0.0
		CSV_RELENTLESS:
			if window_id == W_SELECTED_TO_SHOOT:
				return 2.2 if Common.group_has_ranged_weapons(uid) and not _planned_or_near_targets(uid, ctx, 30.0).is_empty() else 0.0
			return 2.2 if not engaged.is_empty() and Common.group_has_melee_weapons(uid) else 0.0
		CSV_ANGELS:
			# [LANCE] only adds +1 to wound after a charge move this turn.
			if engaged.is_empty() or not Common.group_has_melee_weapons(uid) or not _group_flag(uid, "charged_this_turn"):
				return 0.0
			return 2.5
		CSV_CONTEMPT:
			var attacker := Common.head_id(str(ctx.get("attacker_unit_id", "")))
			var share := _ap_share(attacker, window_id == W_FIGHT_TARGETS)
			if share <= 0.0:
				return 0.0
			return (1.5 + float(Common.group_points(uid)) / 60.0) * (0.5 + share)
		CSV_WORTHY:
			# Worth it while the unit can still swing back (not yet fought, has
			# melee weapons) and is valuable enough to lose models.
			if not Common.group_has_melee_weapons(uid) or _group_flag(uid, "has_fought"):
				return 0.0
			return 1.5 + float(Common.group_points(uid)) / 80.0
		CSV_HURTLING, CSV_UMBRAL:
			return 1.6 + float(Common.group_points(uid)) / 100.0
		CSV_CERAMITE:
			return _ceramite_score(uid)
	return 0.0


## AI pick for RELENTLESS ASSAULT: [LETHAL HITS] when the unit's target (the
## planned / engaged / closest enemy unit) is a MONSTER or VEHICLE, else
## [SUSTAINED HITS 1].
static func ai_relentless_variant(unit_id: String, window_id: String, ctx: Dictionary) -> String:
	var targets: Array = []
	if window_id == W_SELECTED_TO_FIGHT:
		targets = Common.engaged_enemy_ids(unit_id)
	if targets.is_empty():
		targets = _planned_or_near_targets(unit_id, ctx, 999.0)
	if not targets.is_empty() and Common.group_is_monster_or_vehicle(Common.head_id(str(targets[0]))):
		return RA_LETHAL
	return RA_SUSTAINED


# ===========================================================================
# Engine consumers (SMCodex11e hooks)
# ===========================================================================

## ARMOUR OF CONTEMPT: -1 AP to attacks that target a protected unit.
static func modify_ap(ap: int, _attacker_unit: Dictionary, target_unit: Dictionary) -> int:
	if typeof(target_unit.get("flags", {}).get(FLAG_CONTEMPT, null)) != TYPE_DICTIONARY or ap == 0:
		return ap
	var out := maxi(0, ap - 1) if ap > 0 else mini(0, ap + 1)
	Common.log_info("[SMCodexACombat] ARMOUR OF CONTEMPT: attacks that target %s have -1 AP (%d -> %d)" % [str(target_unit.get("id", "?")), ap, out])
	return out


## HURTLING TARGETS / UMBRAL EVASION: ranged attacks that target the unit have -1 to hit.
static func hit_bits(bits: int, _attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, ledger: Array) -> int:
	if is_melee:
		return bits
	var flags: Dictionary = target_unit.get("flags", {})
	var src := ""
	if bool(flags.get(FLAG_HURTLING, false)):
		src = "Hurtling Targets"
	elif bool(flags.get(FLAG_UMBRAL, false)):
		src = "Umbral Evasion"
	if src == "":
		return bits
	ModifierLedger.note(ledger, src, ModifierLedger.KIND_HIT, ModifierLedger.MINUS_ONE, "Codex: Space Marines stratagem (attacks that target the unit)")
	return bits | HIT_MINUS_ONE


## HEADHUNTER DOCTRINE / RELENTLESS ASSAULT / STRIKE FROM THE SHADOWS.
static func attack_grants(out: Dictionary, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool) -> void:
	var flags: Dictionary = attacker_unit.get("flags", {})
	var tgt_mv := _target_is_monster_or_vehicle(target_unit)
	if not is_melee and bool(flags.get(FLAG_HEADHUNTER, false)) and tgt_mv:
		if str(out.lethal) == "":
			out.lethal = "Headhunter Doctrine"
		out.sources.append("Headhunter Doctrine")
	if bool(flags.get(FLAG_SHADOWS, false)):
		if str(out.lethal) == "":
			out.lethal = "Strike from the Shadows"
		out.strength = int(out.strength) + 1
		out.sources.append("Strike from the Shadows")
	match str(flags.get(FLAG_RELENTLESS, "")):
		RA_SUSTAINED:
			if not tgt_mv:
				out.sustained = maxi(int(out.sustained), 1)
				out.sources.append("Relentless Assault")
		RA_LETHAL:
			if tgt_mv:
				if str(out.lethal) == "":
					out.lethal = "Relentless Assault"
				out.sources.append("Relentless Assault")


## LAYERED CERAMITE: Feel No Pain 5+ against mortal wounds.
static func fnp_vs_mortal(unit: Dictionary) -> int:
	return int(unit.get("flags", {}).get(FLAG_CERAMITE, 0))


## ARMOUR OF CONTEMPT ends once the enemy unit it was used against has attacked.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	var units: Dictionary = Common.state().get("units", {})
	var ended: Array = []
	for uid in units:
		var f = units[uid].get("flags", {}).get(FLAG_CONTEMPT, null)
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if attacker_unit_id in f.get("attacker_ids", []):
			units[uid]["flags"].erase(FLAG_CONTEMPT)
			ended.append(uid)
	if not ended.is_empty():
		Common.log_info("SMCodexACombat: ARMOUR OF CONTEMPT ended on %s — %s has attacked" % [str(ended), attacker_unit_id])


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		CSV_CONTEMPT, CSV_WORTHY, CSV_HURTLING, CSV_UMBRAL:
			var ok_windows: Array = [W_FIGHT_TARGETS]
			if csv == CSV_CONTEMPT:
				ok_windows = [W_SHOOT_TARGETS, W_FIGHT_TARGETS]
			elif csv == CSV_HURTLING or csv == CSV_UMBRAL:
				ok_windows = [W_SHOOT_TARGETS]
			if not window_id in ok_windows:
				return []
			var out: Array = []
			for tid in ctx.get("target_unit_ids", []):
				var h := Common.head_id(str(tid))
				if h != "" and not h in out:
					out.append(h)
			return out
		CSV_STORM, CSV_HEADHUNTER:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_SHOOT else []
		CSV_ANGELS:
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_FIGHT else []
		CSV_SHADOWS_A, CSV_SHADOWS_B, CSV_RELENTLESS:
			if window_id != W_SELECTED_TO_SHOOT and window_id != W_SELECTED_TO_FIGHT:
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
		CSV_CONTEMPT, CSV_WORTHY, CSV_HURTLING, CSV_UMBRAL:
			if window_id == W_SHOOT_TARGETS and my_turn:
				return _no("%s: only in your opponent's Shooting phase" % sname)
			if ctx.has("target_unit_ids") and not Common.group_in(head, ctx.get("target_unit_ids", [])):
				return _no("%s must target the unit the enemy unit targeted" % sname)
			match csv:
				CSV_WORTHY:
					if _group_flag(head, "has_fought") or _group_selected_to_fight(head):
						return _no("A WORTHY DEATH: that unit has already been selected to fight this phase (no effect)")
				CSV_HURTLING:
					if not Common.group_has_any_keyword(head, ["MOUNTED", "SPEEDER"]):
						return _no("HURTLING TARGETS can only target an ADEPTUS ASTARTES MOUNTED/SPEEDER unit")
				CSV_UMBRAL:
					if not Common.group_has_keyword(head, "PHOBOS"):
						return _no("UMBRAL EVASION can only target a PHOBOS unit")
		CSV_STORM, CSV_HEADHUNTER, CSV_ANGELS, CSV_SHADOWS_A, CSV_SHADOWS_B, CSV_RELENTLESS:
			var selected := str(ctx.get("unit_id", ""))
			if selected != "" and Common.head_id(selected) != head:
				return _no("%s must target the unit that was selected to %s" % [sname, "shoot" if window_id == W_SELECTED_TO_SHOOT else "fight"])
			if window_id == W_SELECTED_TO_SHOOT and not my_turn:
				return _no("%s: only in your Shooting phase" % sname)
			match csv:
				CSV_HEADHUNTER:
					if not _vehicle_excluding_dt_fly_walker(head):
						return _no("HEADHUNTER DOCTRINE can only target an ADEPTUS ASTARTES VEHICLE unit (excluding DEDICATED TRANSPORT/FLY/WALKER units)")
				CSV_SHADOWS_A, CSV_SHADOWS_B:
					if not Common.group_has_keyword(head, "PHOBOS"):
						return _no("STRIKE FROM THE SHADOWS can only target a PHOBOS unit")
					if not unit_is_hidden(head):
						return _no("STRIKE FROM THE SHADOWS: that PHOBOS unit is not hidden")
				CSV_RELENTLESS:
					if not Common.group_has_keyword(head, "TACTICUS"):
						return _no("RELENTLESS ASSAULT can only target a TACTICUS unit")
		CSV_CERAMITE:
			if not Common.group_has_keyword(head, "VEHICLE"):
				return _no("LAYERED CERAMITE can only target an ADEPTUS ASTARTES VEHICLE unit")
	return {"ok": true, "reason": ""}


## 13.09 (Ork ruling, OrkAbilities11e.unit_is_hidden): a unit is hidden while
## every alive model of every component is hidden.
static func unit_is_hidden(unit_id: String) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("is_model_hidden"):
		return false
	var any := false
	for gid in Common.attached_group_ids(unit_id):
		var u := Common.unit(str(gid))
		for m in u.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			any = true
			if not tm.is_model_hidden(m, u):
				return false
	return any


# ===========================================================================
# Helpers
# ===========================================================================

static func _name(csv: String) -> String:
	match csv:
		CSV_STORM: return "STORM OF DEVASTATION"
		CSV_WORTHY: return "A WORTHY DEATH"
		CSV_CONTEMPT: return "ARMOUR OF CONTEMPT"
		CSV_ANGELS: return "MIGHT OF ANGELS"
		CSV_HEADHUNTER: return "HEADHUNTER DOCTRINE"
		CSV_CERAMITE: return "LAYERED CERAMITE"
		CSV_HURTLING: return "HURTLING TARGETS"
		CSV_SHADOWS_A, CSV_SHADOWS_B: return "STRIKE FROM THE SHADOWS"
		CSV_RELENTLESS: return "RELENTLESS ASSAULT"
		CSV_UMBRAL: return "UMBRAL EVASION"
	return csv

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _log(player: int, msg: String) -> void:
	Common.log_info("SMCodexACombat: " + msg)
	Common.game_log(player, msg)

static func _group_flag(unit_id: String, flag: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get(flag, false)):
			return true
	return false

## Selected to fight this phase (the FightPhase's fought list / active fighter).
static func _group_selected_to_fight(unit_id: String) -> bool:
	var pm = Common.phase_manager()
	var phase = pm.current_phase_instance if pm != null and "current_phase_instance" in pm else null
	if phase == null:
		return false
	var group := Common.attached_group_ids(unit_id)
	if "units_that_fought" in phase:
		for gid in group:
			if gid in phase.units_that_fought:
				return true
	if "active_fighter_id" in phase and str(phase.active_fighter_id) in group:
		return true
	return false

static func _vehicle_excluding_dt_fly_walker(unit_id: String) -> bool:
	return Common.group_has_keyword(unit_id, "VEHICLE") and not Common.group_has_any_keyword(unit_id, ["DEDICATED TRANSPORT", "FLY", "WALKER"])

static func _target_is_monster_or_vehicle(target_unit: Dictionary) -> bool:
	if Common.has_any_keyword(target_unit, ["MONSTER", "VEHICLE"]):
		return true
	var tid := str(target_unit.get("id", ""))
	return tid != "" and Common.group_is_monster_or_vehicle(tid)

## Set a generic engine grant (effect_ignores_cover / effect_grant_lance) on
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

## The planned targets (unit_selected_to_shoot ctx) or the enemy units within
## `range_in` (closest first) — what the unit is about to attack.
static func _planned_or_near_targets(unit_id: String, ctx: Dictionary, range_in: float) -> Array:
	var planned: Array = []
	for t in ctx.get("planned_target_unit_ids", []):
		planned.append(Common.head_id(str(t)))
	if not planned.is_empty():
		return planned
	var player := int(Common.unit(unit_id).get("owner", 0))
	var near: Array = []
	for eid in Common.enemy_heads(player):
		var d := Common.group_distance_inches(unit_id, str(eid))
		if d <= range_in:
			near.append({"id": str(eid), "d": d})
	near.sort_custom(func(a, b): return float(a.d) < float(b.d))
	return near.map(func(e): return e.id)

## STORM OF DEVASTATION AI: a planned / near target has the benefit of cover
## against this unit's first model (TerrainManager.unit_has_cover_11e).
static func _planned_target_has_cover(unit_id: String, ctx: Dictionary) -> bool:
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
	for tid in _planned_or_near_targets(unit_id, ctx, 30.0):
		if bool(tm.unit_has_cover_11e(Common.unit(str(tid)), shooter_model)):
			return true
	return false

## Share of the attacker's weapon profiles (melee or ranged) with AP — what a -1 AP blunts.
static func _ap_share(attacker_id: String, melee: bool) -> float:
	if attacker_id == "":
		return 0.0
	var total := 0
	var with_ap := 0
	for gid in Common.attached_group_ids(attacker_id):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			var is_melee := str(w.get("type", "")).to_lower() == "melee"
			if is_melee != melee:
				continue
			total += 1
			var ap_s := str(w.get("ap", "0")).replace("-", "").strip_edges()
			if ap_s.is_valid_int() and int(ap_s) != 0:
				with_ap += 1
	return float(with_ap) / float(total) if total > 0 else 0.0

## LAYERED CERAMITE (proactive, the AI's own phase — WOLF TOTEMS reading): a
## valuable VEHICLE about to suffer mortal wounds — its own [HAZARDOUS]
## weapons in the phase it uses them, or an enemy with [DEVASTATING WOUNDS]
## weapons within 12" in the Fight phase.
static func _ceramite_score(uid: String) -> float:
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
