extends RefCounted

## CustodesCodexFight — Codex: Adeptus Custodes (11e) stratagems of the FIGHT
## group (WP-C5). Dispatcher: CustodesCodex11e.gd; contract:
## .llm/codex_11e_wahapedia/IMPLEMENTATION.md + the Ork pattern
## (.llm/ork_codex_11e_design.md §6). Rulings: RULINGS.md § WP-C5.
##
## A stratagem counts as mechanically implemented ONLY when its csv_id is in
## IMPLEMENTED. Handler API (static; called by the dispatcher only):
##   eligible_targets / validate / apply / clear / ai_kind / ai_score /
##   variant_cp_cost / variant_label / allows_battle_shocked_target
##
## Windows served (hooks in phases/FightPhase.gd):
##   unit_selected_to_fight       ANATHEMA BLADEMASTERY, GRIM RESPONSIBILITY,
##                                AVENGE THE FALLEN, BEARERS OF HIS LIGHT,
##                                SLAYERS OF NIGHTMARES
##   enemy_targets_unit_fight     DUTY UNTO DEATH
##   fight_phase_start            SHIELD OF HONOUR
##   enemy_has_fought             INDOMITABLE GUARDIANS (opponent's Fight phase)
##   unit_selected_to_pile_in     LIGHTNING WRATH (Pile In step)
##   unit_selected_to_consolidate EMPEROR'S DOMAIN (Consolidate step)
##   (S panel)                    HONOURED INTERRED (your Shooting phase or
##                                either Fight phase)
##
## Effect consumers (CustodesCodex11e engine hooks, read by RulesEngine /
## FightPhase / FightSequencer / ConsolidationMove):
##   hit_roll_effects / wound_roll_effects / bonus_melee_attacks_per_model /
##   melee_lethal_hits / forced_next_fighter / pile_in_inches /
##   consolidation_objective_override
## DUTY UNTO DEATH writes the engine's Fight On Death flags (ork11e_fod_mode /
## ork11e_fod_source — the 05.04.05 mechanic in FightPhase is keyed by them);
## FightPhase asks fod_roll(...) for the roll modifier and pass mark.

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const IDS: Array = [
	"anathema-blademastery-null-maiden-vigil",
	"duty-unto-death-auric-champions",
	"grim-responsibility-shadowkeepers",
	"shield-of-honour-guardians-of-the-throne",
	"avenge-the-fallen-honoured-companions",
	"emperors-domain-honoured-companions",
	"bearers-of-his-light-emissaries-imperatus",
	"slayers-of-nightmares-emissaries-imperatus",
	"indomitable-guardians-shadowkeepers",
	"lightning-wrath-dread-host",
	"honoured-interred-might-of-the-moritoi",
]

const IMPLEMENTED: Dictionary = {
	"anathema-blademastery-null-maiden-vigil": true,
	"duty-unto-death-auric-champions": true,
	"grim-responsibility-shadowkeepers": true,
	"shield-of-honour-guardians-of-the-throne": true,
	"avenge-the-fallen-honoured-companions": true,
	"emperors-domain-honoured-companions": true,
	"bearers-of-his-light-emissaries-imperatus": true,
	"slayers-of-nightmares-emissaries-imperatus": true,
	"indomitable-guardians-shadowkeepers": true,
	"lightning-wrath-dread-host": true,
	"honoured-interred-might-of-the-moritoi": true,
}

const AI_KIND: Dictionary = {
	"anathema-blademastery-null-maiden-vigil": "offensive",
	"duty-unto-death-auric-champions": "defensive",
	"grim-responsibility-shadowkeepers": "offensive",
	"shield-of-honour-guardians-of-the-throne": "defensive",
	"avenge-the-fallen-honoured-companions": "offensive",
	"emperors-domain-honoured-companions": "utility",
	"bearers-of-his-light-emissaries-imperatus": "offensive",
	"slayers-of-nightmares-emissaries-imperatus": "offensive",
	"indomitable-guardians-shadowkeepers": "utility",
	"lightning-wrath-dread-host": "utility",
	"honoured-interred-might-of-the-moritoi": "offensive",
}

const KW_CUSTODES := "ADEPTUS CUSTODES"

# Window ids
const W_SELECTED_TO_FIGHT := "unit_selected_to_fight"
const W_ENEMY_TARGETS_FIGHT := "enemy_targets_unit_fight"
const W_FIGHT_START := "fight_phase_start"
const W_ENEMY_HAS_FOUGHT := "enemy_has_fought"
const W_PILE_IN := "unit_selected_to_pile_in"
const W_CONSOLIDATE := "unit_selected_to_consolidate"

# Flags (all cus11e_*, no effect_ prefix unless an existing generic consumer
# is exactly the rule's scope).
# ANATHEMA BLADEMASTERY: the melee-only generic grants (read only by the
# melee resolver) + the marker holding the variant this handler wrote.
const FLAG_LETHAL_HITS_MELEE := "effect_lethal_hits_melee"
const FLAG_SUSTAINED_HITS_MELEE := "effect_sustained_hits_melee"
const FLAG_BLADEMASTERY := "cus11e_anathema_blademastery"   # "sustained" | "lethal"
const BM_SUSTAINED := "sustained_hits"
const BM_LETHAL := "lethal_hits"
const FLAG_GRIM := "cus11e_grim_responsibility"
const FLAG_SHIELD_OF_HONOUR := "cus11e_shield_of_honour"
const FLAG_AVENGE := "cus11e_avenge_the_fallen"             # int: +A per non-CHARACTER model
const FLAG_EMPERORS_DOMAIN := "cus11e_emperors_domain"
const FLAG_BEARERS := "cus11e_bearers_of_his_light"
const FLAG_SLAYERS := "cus11e_slayers_of_nightmares"
const FLAG_INDOMITABLE := "cus11e_indomitable_guardians"     # marker: the unit must be the next one its player selects
const FLAG_INDOMITABLE_HAD_FF := "cus11e_indomitable_had_ff" # it already had Fights First (do not strip it)
const FLAG_FIGHTS_FIRST := "fights_first"                    # FightSequencer.is_fights_first
const FLAG_LIGHTNING_WRATH := "cus11e_lightning_wrath"       # int: pile-in distance (D3+3")
const FLAG_HONOURED_INTERRED := "cus11e_honoured_interred"   # on the DREADNOUGHT: the aura source
# DUTY UNTO DEATH — FightPhase's Fight On Death mechanic (05.04.05) is keyed
# by these flag names (shared with the Ork codex, OrkCodexFight.FLAG_FOD_*).
const FLAG_FOD_MODE := "ork11e_fod_mode"
const FLAG_FOD_SOURCE := "ork11e_fod_source"
const FOD_MODE_DUTY := "cus11e_duty_unto_death"
const DUTY_PASS := 3

const SHIELD_OF_HONOUR_RANGE_IN := 6.0   # same filter as Dacatarai / Kaptaris (RULINGS WP-C3)
const HONOURED_INTERRED_AURA_IN := 6.0
const AVENGE_BONUS_A := 2


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		var c := _check(csv, player, str(uid), window_id, ctx)
		if not c.ok:
			continue
		out.append(Common.target_entry(str(uid), _entry_extra(csv, str(uid), ctx)))
	return out


static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var csv := str(strat.get("csv_id", ""))
	var window_id := str(ctx.get("window_id", ""))
	if not IMPLEMENTED.get(csv, false):
		return _no("%s is not yet mechanically implemented" % strat.get("name", "?"))
	if target_unit_id == "":
		# S panel probe (no target, no context): the panel stratagem may be
		# used when at least one friendly unit qualifies.
		if csv == "honoured-interred-might-of-the-moritoi":
			for uid in Common.friendly_heads(player):
				if _check(csv, player, str(uid), window_id, ctx).ok:
					return {"ok": true, "reason": ""}
			return _no("HONOURED INTERRED: no friendly ADEPTUS CUSTODES DREADNOUGHT unit on the battlefield")
		return _no("%s needs a target unit" % strat.get("name", "?"))
	return _check(csv, player, target_unit_id, window_id, ctx)


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		"anathema-blademastery-null-maiden-vigil":
			var variant := str(ctx.get("variant_id", BM_SUSTAINED))
			var diffs: Array = []
			if variant == BM_LETHAL:
				diffs.append_array(Common.set_flag_diffs(group, FLAG_LETHAL_HITS_MELEE, true))
			else:
				variant = BM_SUSTAINED
				diffs.append_array(Common.set_flag_diffs(group, FLAG_SUSTAINED_HITS_MELEE, true))
			diffs.append_array(Common.set_flag_diffs(group, FLAG_BLADEMASTERY, variant))
			_log(player, "ANATHEMA BLADEMASTERY: %s's attacks have %s" % [label, "[LETHAL HITS]" if variant == BM_LETHAL else "[SUSTAINED HITS 1]"])
			return diffs
		"duty-unto-death-auric-champions":
			var d: Array = Common.set_flag_diffs(group, FLAG_FOD_MODE, FOD_MODE_DUTY)
			d.append_array(Common.set_flag_diffs(group, FLAG_FOD_SOURCE, "DUTY UNTO DEATH"))
			_log(player, "DUTY UNTO DEATH: a model of %s destroyed before the unit has fought rolls a D6 (+1 for a CHARACTER model) — on a 3+ it is not removed until the unit has fought / the end of the phase" % label)
			return d
		"grim-responsibility-shadowkeepers":
			_log(player, "GRIM RESPONSIBILITY: %s's melee attacks have [LETHAL HITS: CHARACTER/MONSTER]" % label)
			return Common.set_flag_diffs(group, FLAG_GRIM, true)
		"shield-of-honour-guardians-of-the-throne":
			_log(player, "SHIELD OF HONOUR: enemy models engaged with %s that do not target it with all of their attacks have -1 to hit and -1 to wound (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_SHIELD_OF_HONOUR, true)
		"avenge-the-fallen-honoured-companions":
			_log(player, "AVENGE THE FALLEN: %s's melee attacks (excluding CHARACTER models) have +2 A" % label)
			return Common.set_flag_diffs(group, FLAG_AVENGE, AVENGE_BONUS_A)
		"emperors-domain-honoured-companions":
			_log(player, "EMPEROR'S DOMAIN: %s may use the objective consolidation mode regardless of the Before Moving restrictions" % label)
			return Common.set_flag_diffs(group, FLAG_EMPERORS_DOMAIN, true)
		"bearers-of-his-light-emissaries-imperatus":
			_log(player, "BEARERS OF HIS LIGHT: %s's melee attacks ignore modifiers to hit and wound rolls" % label)
			return Common.set_flag_diffs(group, FLAG_BEARERS, true)
		"slayers-of-nightmares-emissaries-imperatus":
			_log(player, "SLAYERS OF NIGHTMARES: %s's melee attacks vs a unit with a higher T have +1 to wound" % label)
			return Common.set_flag_diffs(group, FLAG_SLAYERS, true)
		"indomitable-guardians-shadowkeepers":
			var ig: Array = []
			for gid in group:
				var had_ff := bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_FIGHTS_FIRST, false))
				ig.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_INDOMITABLE_HAD_FF], "value": had_ff})
			ig.append_array(Common.set_flag_diffs(group, FLAG_FIGHTS_FIRST, true))
			ig.append_array(Common.set_flag_diffs(group, FLAG_INDOMITABLE, true))
			_log(player, "INDOMITABLE GUARDIANS: %s has Fights First and must be the next unit Player %d selects to fight" % [label, player])
			return ig
		"lightning-wrath-dread-host":
			var roll := int(Common.roll_dice(1, 3)[0])
			var inches := roll + 3
			_log(player, "LIGHTNING WRATH: %s rolls D3 = %d — its pile-in move is up to %d\"" % [label, roll, inches])
			return Common.set_flag_diffs(group, FLAG_LIGHTNING_WRATH, inches)
		"honoured-interred-might-of-the-moritoi":
			_log(player, "HONOURED INTERRED: friendly ADEPTUS CUSTODES units within 6\" of %s can re-roll hit rolls of 1 (this phase)" % label)
			return Common.set_flag_diffs(group, FLAG_HONOURED_INTERRED, true)
	Common.log_error("CustodesCodexFight: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		"anathema-blademastery-null-maiden-vigil":
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var flags: Dictionary = units.get(str(gid), {}).get("flags", {})
				var v := str(flags.get(FLAG_BLADEMASTERY, ""))
				if v == BM_LETHAL:
					flags.erase(FLAG_LETHAL_HITS_MELEE)
				elif v == BM_SUSTAINED:
					flags.erase(FLAG_SUSTAINED_HITS_MELEE)
				flags.erase(FLAG_BLADEMASTERY)
		"duty-unto-death-auric-champions":
			# The kept models (ork11e_fod_pending) are removed by the Fight phase
			# before it ends — only the marker expires here.
			Common.erase_flags(group, [FLAG_FOD_MODE, FLAG_FOD_SOURCE])
		"grim-responsibility-shadowkeepers":
			Common.erase_flags(group, [FLAG_GRIM])
		"shield-of-honour-guardians-of-the-throne":
			Common.erase_flags(group, [FLAG_SHIELD_OF_HONOUR])
		"avenge-the-fallen-honoured-companions":
			Common.erase_flags(group, [FLAG_AVENGE])
		"emperors-domain-honoured-companions":
			Common.erase_flags(group, [FLAG_EMPERORS_DOMAIN])
		"bearers-of-his-light-emissaries-imperatus":
			Common.erase_flags(group, [FLAG_BEARERS])
		"slayers-of-nightmares-emissaries-imperatus":
			Common.erase_flags(group, [FLAG_SLAYERS])
		"indomitable-guardians-shadowkeepers":
			var units2: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f2: Dictionary = units2.get(str(gid), {}).get("flags", {})
				if f2.has(FLAG_INDOMITABLE) and not bool(f2.get(FLAG_INDOMITABLE_HAD_FF, false)):
					f2.erase(FLAG_FIGHTS_FIRST)
				f2.erase(FLAG_INDOMITABLE)
				f2.erase(FLAG_INDOMITABLE_HAD_FF)
		"lightning-wrath-dread-host":
			Common.erase_flags(group, [FLAG_LIGHTNING_WRATH])
		"honoured-interred-might-of-the-moritoi":
			Common.erase_flags(group, [FLAG_HONOURED_INTERRED])
	Common.log_info("CustodesCodexFight: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if str(strat.get("csv_id", "")) == "anathema-blademastery-null-maiden-vigil":
		return "[LETHAL HITS]" if variant_id == BM_LETHAL else "[SUSTAINED HITS 1]"
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	var engaged := Common.engaged_enemy_ids(uid)
	match csv:
		"anathema-blademastery-null-maiden-vigil", "avenge-the-fallen-honoured-companions":
			return 2.5 if not engaged.is_empty() and _has_melee(uid) else 0.0
		"grim-responsibility-shadowkeepers":
			for eid in engaged:
				if Common.group_has_keyword(str(eid), "CHARACTER") or Common.group_has_keyword(str(eid), "MONSTER"):
					return 2.5
			return 0.0
		"slayers-of-nightmares-emissaries-imperatus":
			var my_t := _toughness(uid)
			for eid in engaged:
				if _toughness(str(eid)) > my_t:
					return 2.5
			return 0.0
		"bearers-of-his-light-emissaries-imperatus":
			# Only worth it when something imposes a penalty on this unit's melee.
			for eid in engaged:
				var ef: Dictionary = Common.unit(str(eid)).get("flags", {})
				if bool(ef.get("effect_minus_one_hit_defense_melee", false)) or bool(ef.get("effect_minus_one_wound_defense", false)) \
						or bool(ef.get("cus11e_katah_kaptaris", false)):
					return 2.2
			return 0.0
		"duty-unto-death-auric-champions":
			if _group_selected_to_fight(uid):
				return 0.0
			var pts := 0
			for gid in Common.attached_group_ids(uid):
				pts += int(Common.unit(str(gid)).get("meta", {}).get("points", 0))
			return clampf(float(pts) / 100.0, 0.0, 4.0)
		"shield-of-honour-guardians-of-the-throne":
			return 1.6 if engaged.size() >= 2 else 0.0
		"indomitable-guardians-shadowkeepers":
			return 2.5 if not engaged.is_empty() else 0.0
		"lightning-wrath-dread-host":
			# Worth it when some model cannot reach base contact with a 3" pile-in
			# but could with D3+3" (an enemy 3-6" from it).
			return 1.8 if _models_between(uid, 3.0, 6.0) > 0 else 0.0
		"emperors-domain-honoured-companions":
			# Engaged (the engagement mode would apply) next to an objective the
			# army does not control yet: step onto it instead.
			if engaged.is_empty():
				return 0.0
			for obj in Common.objectives():
				var oid := str(obj.get("id", ""))
				if Common.objective_controller(oid) != player and _group_within_inches_of_objective(uid, obj, 3.0 + 3.0):
					return 1.6
			return 0.0
		"honoured-interred-might-of-the-moritoi":
			# S panel: friendly Custodes units near the Dreadnought about to attack.
			var near := 0
			for fid in Common.friendly_heads(player):
				if Common.group_distance_inches(uid, str(fid)) <= HONOURED_INTERRED_AURA_IN and Common.nearest_enemy_inches(Common.group_union(str(fid))) <= 12.0:
					near += 1
			return 1.5 if near >= 2 else 0.0
	return 0.0


## Alive models of the group whose nearest enemy model is between lo and hi
## inches away (edge to edge).
static func _models_between(unit_id: String, lo: float, hi: float) -> int:
	var count := 0
	var player := int(Common.unit(unit_id).get("owner", 0))
	var enemies: Array = []
	for eid in Common.enemy_heads(player):
		enemies.append(Common.group_union(str(eid)))
	for gid in Common.attached_group_ids(unit_id):
		var u := Common.unit(str(gid))
		for m in u.get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			var single := {"models": [m]}
			var best := INF
			for e in enemies:
				best = minf(best, Common.unit_distance_inches(single, e))
			if best > lo and best <= hi:
				count += 1
	return count


static func _group_within_inches_of_objective(unit_id: String, obj: Dictionary, inches: float) -> bool:
	var op = obj.get("position", null)
	if op == null:
		return false
	if op is Dictionary:
		op = Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
	var meas = Common.autoload("Measurement")
	if meas == null:
		return false
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position") == null:
				continue
			if float(meas.px_to_inches(Common._pos(m).distance_to(op))) <= inches:
				return true
	return false


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		"anathema-blademastery-null-maiden-vigil", "grim-responsibility-shadowkeepers", \
				"avenge-the-fallen-honoured-companions", "bearers-of-his-light-emissaries-imperatus", \
				"slayers-of-nightmares-emissaries-imperatus":
			if window_id != W_SELECTED_TO_FIGHT:
				return []
			return [Common.head_id(str(ctx.get("unit_id", "")))]
		"duty-unto-death-auric-champions":
			if window_id != W_ENEMY_TARGETS_FIGHT:
				return []
			var out: Array = []
			for tid in ctx.get("target_unit_ids", []):
				var h := Common.head_id(str(tid))
				if not h in out:
					out.append(h)
			return out
		"shield-of-honour-guardians-of-the-throne":
			return Common.friendly_heads(player) if window_id == W_FIGHT_START else []
		"indomitable-guardians-shadowkeepers":
			return Common.friendly_heads(player) if window_id == W_ENEMY_HAS_FOUGHT else []
		"lightning-wrath-dread-host":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_PILE_IN else []
		"emperors-domain-honoured-companions":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_CONSOLIDATE else []
		"honoured-interred-might-of-the-moritoi":
			return Common.friendly_heads(player)
	return []


static func _entry_extra(csv: String, _unit_id: String, _ctx: Dictionary) -> Dictionary:
	if csv == "anathema-blademastery-null-maiden-vigil":
		return {"require_variant": true, "ai_variant": BM_LETHAL, "variants": [
			{"id": BM_SUSTAINED, "label": "[SUSTAINED HITS 1]", "cp_cost": 1},
			{"id": BM_LETHAL, "label": "Or: [LETHAL HITS]", "cp_cost": 1}]}
	return {}


static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var name := _display_name(csv)
	var uid := Common.head_id(target_unit_id)
	var u := Common.unit(uid)
	if u.is_empty():
		return _no("%s: unit %s not found" % [name, target_unit_id])
	if int(u.get("owner", 0)) != player:
		return _no("%s: %s is not your unit" % [name, Common.unit_name(uid)])
	if not Common.is_on_battlefield(u):
		return _no("%s: %s is not on the battlefield" % [name, Common.unit_name(uid)])
	match csv:
		"anathema-blademastery-null-maiden-vigil":
			if window_id != "" and window_id != W_SELECTED_TO_FIGHT:
				return _no("%s is used when a VIGILATOR SQUAD unit is selected to fight" % name)
			if not Common.group_has_keyword(uid, "VIGILATOR SQUAD"):
				return _no("%s can only target a VIGILATOR SQUAD unit" % name)
		"duty-unto-death-auric-champions":
			if window_id != "" and window_id != W_ENEMY_TARGETS_FIGHT:
				return _no("%s is used when an enemy unit targets one of your units in melee" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if window_id != "" and not uid in _ctx_heads(ctx.get("target_unit_ids", [])):
				return _no("%s: %s is not a target of that enemy unit's attacks" % [name, Common.unit_name(uid)])
			# The effect only works while the unit has not been selected to
			# fight this phase (Ork ruling for the same 05.04.05 text).
			if _group_selected_to_fight(uid):
				return _no("%s: %s has already been selected to fight this phase" % [name, Common.unit_name(uid)])
		"grim-responsibility-shadowkeepers":
			if window_id != "" and window_id != W_SELECTED_TO_FIGHT:
				return _no("%s is used when an ADEPTUS CUSTODES INFANTRY unit is selected to fight" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "INFANTRY")):
				return _no("%s can only target an ADEPTUS CUSTODES INFANTRY unit" % name)
		"shield-of-honour-guardians-of-the-throne":
			if window_id != "" and window_id != W_FIGHT_START:
				return _no("%s is used at the start of the Fight phase" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES) or not (Common.group_has_keyword(uid, "INFANTRY") or Common.group_has_keyword(uid, "MOUNTED")):
				return _no("%s can only target an ADEPTUS CUSTODES INFANTRY or MOUNTED unit" % name)
			if Common.nearest_enemy_inches(Common.group_union(uid)) > SHIELD_OF_HONOUR_RANGE_IN + 0.001:
				return _no("%s: no enemy unit within 6\" of %s (no enemy model can be engaged with it this phase)" % [name, Common.unit_name(uid)])
		"avenge-the-fallen-honoured-companions":
			if window_id != "" and window_id != W_SELECTED_TO_FIGHT:
				return _no("%s is used when a TRUSTED SENTINEL unit is selected to fight" % name)
			if not Common.group_has_keyword(uid, "TRUSTED SENTINEL"):
				return _no("%s can only target a TRUSTED SENTINEL unit" % name)
			if not Common.is_below_starting_strength(uid):
				return _no("%s: %s is not below its starting strength" % [name, Common.unit_name(uid)])
		"emperors-domain-honoured-companions":
			if window_id != "" and window_id != W_CONSOLIDATE:
				return _no("%s is used when a TRUSTED SENTINEL unit is selected to make a consolidation move" % name)
			if not Common.group_has_keyword(uid, "TRUSTED SENTINEL"):
				return _no("%s can only target a TRUSTED SENTINEL unit" % name)
			# Ruling: the objective mode still needs an objective within 3" of
			# the unit (the mode's own condition) — only the mandatory order of
			# the Before Moving modes is lifted.
			if not _objective_within(uid, 3.0):
				return _no("%s: no objective within 3\" of %s" % [name, Common.unit_name(uid)])
		"bearers-of-his-light-emissaries-imperatus", "slayers-of-nightmares-emissaries-imperatus":
			if window_id != "" and window_id != W_SELECTED_TO_FIGHT:
				return _no("%s is used when an ADEPTUS CUSTODES unit is selected to fight" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		"indomitable-guardians-shadowkeepers":
			if window_id != "" and window_id != W_ENEMY_HAS_FOUGHT:
				return _no("%s is used in your opponent's Fight phase when an enemy unit has fought" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if not Common.group_in_range_of_any_objective(uid):
				return _no("%s: %s is not within range of an objective" % [name, Common.unit_name(uid)])
			if not _eligible_to_fight(uid):
				return _no("%s: %s is not eligible to fight" % [name, Common.unit_name(uid)])
		"lightning-wrath-dread-host":
			if window_id != "" and window_id != W_PILE_IN:
				return _no("%s is used when an ADEPTUS CUSTODES unit is selected to make a pile-in move" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		"honoured-interred-might-of-the-moritoi":
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "DREADNOUGHT")):
				return _no("%s can only target an ADEPTUS CUSTODES DREADNOUGHT unit" % name)
			# "Your Shooting phase or the Fight phase": the turn column says
			# either player's turn — your own Shooting phase only.
			var phase_name := _phase_name()
			if phase_name == "shooting" and player != Common.active_player():
				return _no("%s can only be used in YOUR Shooting phase (or either Fight phase)" % name)
			if phase_name != "shooting" and phase_name != "fight":
				return _no("%s can only be used in your Shooting phase or the Fight phase" % name)
		_:
			return _no("%s is not yet mechanically implemented" % name)
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _display_name(csv: String) -> String:
	match csv:
		"anathema-blademastery-null-maiden-vigil": return "ANATHEMA BLADEMASTERY"
		"duty-unto-death-auric-champions": return "DUTY UNTO DEATH"
		"grim-responsibility-shadowkeepers": return "GRIM RESPONSIBILITY"
		"shield-of-honour-guardians-of-the-throne": return "SHIELD OF HONOUR"
		"avenge-the-fallen-honoured-companions": return "AVENGE THE FALLEN"
		"emperors-domain-honoured-companions": return "EMPEROR'S DOMAIN"
		"bearers-of-his-light-emissaries-imperatus": return "BEARERS OF HIS LIGHT"
		"slayers-of-nightmares-emissaries-imperatus": return "SLAYERS OF NIGHTMARES"
		"indomitable-guardians-shadowkeepers": return "INDOMITABLE GUARDIANS"
		"lightning-wrath-dread-host": return "LIGHTNING WRATH"
		"honoured-interred-might-of-the-moritoi": return "HONOURED INTERRED"
	return csv


static func _log(player: int, msg: String) -> void:
	Common.log_info("[CustodesCodexFight] " + msg)
	Common.game_log(player, msg)


static func _ctx_heads(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		var h := Common.head_id(str(i))
		if not h in out:
			out.append(h)
	return out


static func _phase_name() -> String:
	var sm = Common.stratagem_manager()
	if sm and sm.has_method("_phase_to_string"):
		return str(sm._phase_to_string(Common.current_phase()))
	return ""


static func _has_melee(unit_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("get_unit_melee_weapons"):
		return true
	for gid in Common.attached_group_ids(unit_id):
		if not re.get_unit_melee_weapons(str(gid), Common.state()).is_empty():
			return true
	return false


static func _toughness(unit_id: String) -> int:
	var head := Common.head_id(unit_id)
	return int(Common.unit(head).get("meta", {}).get("stats", {}).get("toughness", 0))


## The live Fight phase instance, or null.
static func _fight_phase():
	var pm = Common.phase_manager()
	if pm == null or not pm.has_method("get_current_phase_instance"):
		return null
	var ph = pm.get_current_phase_instance()
	if ph == null or not ("sequencer_11e" in ph):
		return null
	return ph


static func _group_selected_to_fight(unit_id: String) -> bool:
	var ph = _fight_phase()
	if ph == null:
		return false
	if ph.has_method("_ork11e_group_selected_to_fight"):
		return bool(ph._ork11e_group_selected_to_fight(unit_id))
	return false


static func _eligible_to_fight(unit_id: String) -> bool:
	var ph = _fight_phase()
	if ph == null or ph.sequencer_11e == null:
		return false
	return bool(ph.sequencer_11e.group_eligible_to_fight(unit_id, Common.state()))


static func _objective_within(unit_id: String, inches: float) -> bool:
	var mm = Common.mission_manager()
	if mm == null:
		return false
	for obj in Common.objectives():
		for gid in Common.attached_group_ids(unit_id):
			for m in Common.unit(str(gid)).get("models", []):
				if not m.get("alive", true) or m.get("position", null) == null:
					continue
				if mm.has_method("model_within_inches_of_objective") and mm.model_within_inches_of_objective(m, obj, inches):
					return true
	return false


# ===========================================================================
# Effect consumers (CustodesCodex11e engine hooks)
# ===========================================================================

## Fills `out` (CustodesCodex11e.hit_roll_effects shape) for one attack batch.
##  - SHIELD OF HONOUR (melee): an enemy model engaged with a SHIELD OF HONOUR
##    unit that does not target that unit with ALL of its attacks has -1 to hit.
##  - BEARERS OF HIS LIGHT (melee): the attacker ignores hit-roll penalties.
##  - HONOURED INTERRED (ranged + melee): friendly ADEPTUS CUSTODES units within
##    6" of the DREADNOUGHT can re-roll hit rolls of 1.
static func hit_roll_effects(out: Dictionary, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, _board: Dictionary) -> void:
	if is_melee:
		var soh := shield_of_honour_penalty(attacker_unit, target_unit)
		if soh != "":
			out["minus"] = true
			out.sources.append("Shield of Honour (%s)" % soh)
		if bool(attacker_unit.get("flags", {}).get(FLAG_BEARERS, false)):
			out["ignore_minus"] = true
			out.sources.append("Bearers of His Light")
	var hi := honoured_interred_source(attacker_unit)
	if hi != "":
		out["reroll_ones"] = true
		out.sources.append("Honoured Interred (%s)" % Common.unit_name(hi))


## {plus, minus, ignore_minus, sources} for one melee wound batch.
##  - SHIELD OF HONOUR: -1 to wound (same condition as the hit penalty).
##  - BEARERS OF HIS LIGHT: wound-roll penalties ignored.
##  - SLAYERS OF NIGHTMARES: +1 to wound vs a target with T greater than the
##    attacking unit's T.
static func wound_roll_effects(out: Dictionary, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, _strength: int, toughness: int) -> void:
	if not is_melee:
		return
	var aflags: Dictionary = attacker_unit.get("flags", {})
	var soh := shield_of_honour_penalty(attacker_unit, target_unit)
	if soh != "":
		out["minus"] = true
		out.sources.append("Shield of Honour (%s)" % soh)
	if bool(aflags.get(FLAG_BEARERS, false)):
		out["ignore_minus"] = true
		out.sources.append("Bearers of His Light")
	if bool(aflags.get(FLAG_SLAYERS, false)):
		var my_t := _toughness(str(attacker_unit.get("id", "")))
		var their_t := toughness if toughness > 0 else _toughness(str(target_unit.get("id", "")))
		if their_t > my_t:
			out["plus"] = true
			out.sources.append("Slayers of Nightmares (T%d > T%d)" % [their_t, my_t])


## SHIELD OF HONOUR — the SoH unit's name when the batch's attacking models
## are engaged with an enemy SoH unit and the batch is NOT entirely aimed at
## it ("" = no penalty). Ruling: judged per attack batch — a batch aimed at
## another unit by models engaged with the SoH unit takes the penalty; a batch
## aimed at the SoH unit takes it only when the same attacker also has
## confirmed attacks against another unit this activation.
static func shield_of_honour_penalty(attacker_unit: Dictionary, target_unit: Dictionary) -> String:
	var attacker_owner := int(attacker_unit.get("owner", 0))
	var attacker_id := str(attacker_unit.get("id", ""))
	var target_head := Common.head_id(str(target_unit.get("id", "")))
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var su: Dictionary = units[uid]
		if int(su.get("owner", 0)) == attacker_owner or not bool(su.get("flags", {}).get(FLAG_SHIELD_OF_HONOUR, false)):
			continue
		var soh_head := Common.head_id(str(uid))
		if not Common.group_engaged_with(attacker_id, soh_head):
			continue
		if target_head != soh_head:
			return Common.unit_name(soh_head)
		if _attacker_also_targets_other_than(attacker_id, soh_head):
			return Common.unit_name(soh_head)
	return ""


static func _attacker_also_targets_other_than(attacker_id: String, soh_head: String) -> bool:
	var ph = _fight_phase()
	if ph == null or not ("confirmed_attacks" in ph):
		return false
	var mine := Common.attached_group_ids(attacker_id)
	for a in ph.confirmed_attacks:
		if not str(a.get("attacker", "")) in mine:
			continue
		if Common.head_id(str(a.get("target", ""))) != soh_head:
			return true
	return false


## The DREADNOUGHT whose HONOURED INTERRED aura covers `attacker_unit` ("" = none).
static func honoured_interred_source(attacker_unit: Dictionary) -> String:
	var owner := int(attacker_unit.get("owner", 0))
	if owner == 0 or not Common.has_keyword(attacker_unit, KW_CUSTODES):
		return ""
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var su: Dictionary = units[uid]
		if int(su.get("owner", 0)) != owner or not bool(su.get("flags", {}).get(FLAG_HONOURED_INTERRED, false)):
			continue
		if not Common.is_on_battlefield(su):
			continue
		if str(uid) == str(attacker_unit.get("id", "")) or Common.unit_distance_inches(attacker_unit, su) <= HONOURED_INTERRED_AURA_IN + 0.001:
			return str(uid)
	return ""


## AVENGE THE FALLEN: +2 A per swinging model — 0 for a CHARACTER component
## ("excluding those made by CHARACTER models").
static func bonus_melee_attacks_per_model(attacker_unit: Dictionary, _target_unit: Dictionary) -> int:
	var bonus := int(attacker_unit.get("flags", {}).get(FLAG_AVENGE, 0))
	if bonus <= 0 or Common.has_keyword(attacker_unit, "CHARACTER"):
		return 0
	return bonus


## GRIM RESPONSIBILITY [LETHAL HITS: CHARACTER/MONSTER] — keyword-qualified:
## only vs a CHARACTER or MONSTER target (Rendax ruling, WP-C3).
static func melee_lethal_hits(attacker_unit: Dictionary, target_unit: Dictionary) -> bool:
	if not bool(attacker_unit.get("flags", {}).get(FLAG_GRIM, false)):
		return false
	var th := Common.head_id(str(target_unit.get("id", "")))
	return Common.group_has_keyword(th, "CHARACTER") or Common.group_has_keyword(th, "MONSTER") \
		or Common.has_any_keyword(target_unit, ["CHARACTER", "MONSTER"])


## INDOMITABLE GUARDIANS: the unit `player` must select next ("" = none) —
## only while it is still eligible to fight (it stops binding once it fought).
static func forced_next_fighter(player: int) -> String:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not bool(u.get("flags", {}).get(FLAG_INDOMITABLE, false)):
			continue
		var head := Common.head_id(str(uid))
		if _eligible_to_fight(head):
			return head
	return ""


## LIGHTNING WRATH pile-in distance (0 = the core 3").
static func pile_in_inches(unit_id: String) -> float:
	var best := 0.0
	for gid in Common.attached_group_ids(unit_id):
		best = maxf(best, float(Common.unit(str(gid)).get("flags", {}).get(FLAG_LIGHTNING_WRATH, 0)))
	return best


static func consolidation_objective_override(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_EMPERORS_DOMAIN, false)):
			return true
	return false


## DUTY UNTO DEATH Fight On Death roll for model `model_index` of `unit_id`:
## {mod, note, pass} (+1 if that model is a CHARACTER model, 3+ keeps it).
static func fod_roll(unit_id: String, _model_index: int) -> Dictionary:
	var u := Common.unit(unit_id)
	if Common.has_keyword(u, "CHARACTER"):
		return {"mod": 1, "note": "+1 CHARACTER model", "pass": DUTY_PASS}
	return {"mod": 0, "note": "", "pass": DUTY_PASS}
