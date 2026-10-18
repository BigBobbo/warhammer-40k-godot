extends RefCounted

## CustodesCodexShooting — Codex: Adeptus Custodes (11e) stratagems of the
## SHOOTING group (WP-C5): own-turn Shooting windows and the reactive
## "an enemy unit targets your unit" windows (shooting AND fight).
## Dispatcher: CustodesCodex11e.gd. Rulings: RULINGS.md § WP-C5.
##
## Windows served:
##   unit_has_shot                 PSY-CHAFF VOLLEY (ShootingPhase post-shot)
##   unit_selected_to_shoot        PURGATION SWEEP, PRIME TARGET, TIP OF THE TALON,
##                                 ADVANCED STABILISERS, INEVITABLE ANNIHILATION
##   enemy_targets_unit_shooting   VIGIL UNENDING, IN AURAMITE CLAD (x2)
##   enemy_targets_unit_fight      VIGIL UNENDING, IN AURAMITE CLAD (x2)
##
## Effect consumers (CustodesCodex11e engine hooks): modify_ap,
## hit_roll_effects, filter_hit_stack, ignores_bs_worsening,
## bonus_ranged_attacks_per_model, ranged_strength_bonus,
## single_reroll_available / single_reroll_spend_diffs,
## may_select_advanced_unit_to_shoot, grants_ranged_assault,
## on_unit_has_attacked.

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const IDS: Array = [
	"psy-chaff-volley-null-maiden-vigil",
	"purgation-sweep-null-maiden-vigil",
	"prime-target-guardians-of-the-throne",
	"tip-of-the-talon-aquilan-shield",
	"advanced-stabilisers-grav-assault-force",
	"inevitable-annihilation-grav-assault-force",
	"vigil-unending-lions-of-the-emperor",
	"in-auramite-clad-guardians-of-the-throne",
	"in-auramite-clad-emperors-chosen",
]

const IMPLEMENTED: Dictionary = {
	"psy-chaff-volley-null-maiden-vigil": true,
	"purgation-sweep-null-maiden-vigil": true,
	"prime-target-guardians-of-the-throne": true,
	"tip-of-the-talon-aquilan-shield": true,
	"advanced-stabilisers-grav-assault-force": true,
	"inevitable-annihilation-grav-assault-force": true,
	"vigil-unending-lions-of-the-emperor": true,
	"in-auramite-clad-guardians-of-the-throne": true,
	"in-auramite-clad-emperors-chosen": true,
}

const AI_KIND: Dictionary = {
	"psy-chaff-volley-null-maiden-vigil": "offensive",
	"purgation-sweep-null-maiden-vigil": "offensive",
	"prime-target-guardians-of-the-throne": "offensive",
	"tip-of-the-talon-aquilan-shield": "offensive",
	"advanced-stabilisers-grav-assault-force": "utility",
	"inevitable-annihilation-grav-assault-force": "offensive",
	"vigil-unending-lions-of-the-emperor": "defensive",
	"in-auramite-clad-guardians-of-the-throne": "defensive",
	"in-auramite-clad-emperors-chosen": "defensive",
}

const KW_CUSTODES := "ADEPTUS CUSTODES"

const W_HAS_SHOT := "unit_has_shot"
const W_SELECTED_TO_SHOOT := "unit_selected_to_shoot"
const W_TARGETS_SHOOTING := "enemy_targets_unit_shooting"
const W_TARGETS_FIGHT := "enemy_targets_unit_fight"

# Flags
const FLAG_PROSECUTED := "cus11e_prosecuted"             # on the ENEMY unit: player whose stratagem made it prosecuted
const FLAG_PSY_CHAFF_TARGET := "cus11e_psy_chaff_target" # on the PROSECUTOR SQUAD: the enemy it prosecuted (for expiry)
const FLAG_PURGATION := "cus11e_purgation_sweep"         # variant: "plus_one" | "plus_two"
const PS_PLUS_ONE := "plus_one"
const PS_PLUS_TWO := "plus_two_psyker"
const FLAG_PRIME_TARGET := "cus11e_prime_target"         # {hit: bool, wound: bool, damage: bool} re-rolls still unused
const FLAG_TIP_OF_THE_TALON := "cus11e_tip_of_the_talon"
const FLAG_ADVANCED_STABILISERS := "cus11e_advanced_stabilisers"
const FLAG_INEVITABLE := "cus11e_inevitable_annihilation"
const FLAG_VIGIL := "cus11e_vigil_unending"              # {attackers: [ids], prev: int} — the effect_minus_damage it added
const FLAG_AURAMITE := "cus11e_in_auramite_clad"         # {attackers: [ids]}
const FLAG_MINUS_DAMAGE := "effect_minus_damage"         # EffectPrimitives FLAG_MINUS_DAMAGE (read on every damage path)

const TIP_OF_THE_TALON_RANGE_IN := 9.0


# ===========================================================================
# Handler API
# ===========================================================================

static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	var csv := str(strat.get("csv_id", ""))
	var out: Array = []
	for uid in _candidates(csv, player, window_id, ctx):
		if not _check(csv, player, str(uid), window_id, ctx).ok:
			continue
		out.append(Common.target_entry(str(uid), _entry_extra(csv, str(uid), window_id, ctx)))
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
	if csv == "psy-chaff-volley-null-maiden-vigil":
		var sec := str(ctx.get("secondary_id", ""))
		if sec != "" and not sec in _hit_enemy_heads(player, ctx):
			return _no("PSY-CHAFF VOLLEY: %s was not hit by those attacks" % Common.unit_name(sec))
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		"psy-chaff-volley-null-maiden-vigil":
			var hit := _hit_enemy_heads(player, ctx)
			var enemy := str(ctx.get("secondary_id", ""))
			if enemy == "" and not hit.is_empty():
				enemy = str(hit[0])
			if enemy == "" or not enemy in hit:
				Common.log_error("CustodesCodexShooting: PSY-CHAFF VOLLEY — no enemy unit hit by %s's attacks (%s); nothing prosecuted" % [head, str(hit)])
				return []
			var d: Array = Common.set_flag_diffs(Common.attached_group_ids(enemy), FLAG_PROSECUTED, player)
			d.append_array(Common.set_flag_diffs(group, FLAG_PSY_CHAFF_TARGET, enemy))
			_log(player, "PSY-CHAFF VOLLEY: %s is prosecuted until the end of the turn — attacks that target it have +1 AP" % Common.group_label(enemy))
			return d
		"purgation-sweep-null-maiden-vigil":
			var v := str(ctx.get("variant_id", PS_PLUS_ONE))
			if v != PS_PLUS_TWO:
				v = PS_PLUS_ONE
			_log(player, "PURGATION SWEEP: %s's [TORRENT] attacks have %s" % [label, "+1 A" if v == PS_PLUS_ONE else "+2 A against a PSYKER / battle-shocked target"])
			return Common.set_flag_diffs(group, FLAG_PURGATION, v)
		"prime-target-guardians-of-the-throne":
			_log(player, "PRIME TARGET: %s's ranged attacks can re-roll one hit roll, one wound roll and one damage roll" % label)
			return Common.set_flag_diffs(group, FLAG_PRIME_TARGET, {"hit": true, "wound": true, "damage": true})
		"tip-of-the-talon-aquilan-shield":
			_log(player, "TIP OF THE TALON: %s's ranged attacks that target an enemy unit within 9\" have +1 S" % label)
			return Common.set_flag_diffs(group, FLAG_TIP_OF_THE_TALON, true)
		"advanced-stabilisers-grav-assault-force":
			_log(player, "ADVANCED STABILISERS: %s's ranged attacks have [ASSAULT]" % label)
			return Common.set_flag_diffs(group, FLAG_ADVANCED_STABILISERS, true)
		"inevitable-annihilation-grav-assault-force":
			_log(player, "INEVITABLE ANNIHILATION: %s ignores modifiers to its BS and hit rolls" % label)
			return Common.set_flag_diffs(group, FLAG_INEVITABLE, true)
		"vigil-unending-lions-of-the-emperor":
			var attackers := Common.attached_group_ids(str(ctx.get("attacker_unit_id", "")))
			var vd: Array = []
			for gid in group:
				var prev := int(Common.unit(str(gid)).get("flags", {}).get(FLAG_MINUS_DAMAGE, 0))
				vd.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_MINUS_DAMAGE], "value": prev + 1})
				vd.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_VIGIL], "value": {"attackers": attackers, "prev": prev}})
			_log(player, "VIGIL UNENDING: attacks that target %s have -1 D until %s has attacked" % [label, Common.unit_name(str(ctx.get("attacker_unit_id", "")))])
			return vd
		"in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen":
			var atk := Common.attached_group_ids(str(ctx.get("attacker_unit_id", "")))
			_log(player, "IN AURAMITE CLAD: attacks that target %s have -1 AP until %s has attacked" % [label, Common.unit_name(str(ctx.get("attacker_unit_id", "")))])
			return Common.set_flag_diffs(group, FLAG_AURAMITE, {"attackers": atk})
	Common.log_error("CustodesCodexShooting: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		"psy-chaff-volley-null-maiden-vigil":
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f: Dictionary = units.get(str(gid), {}).get("flags", {})
				var enemy := str(f.get(FLAG_PSY_CHAFF_TARGET, ""))
				if enemy != "":
					Common.erase_flags(Common.attached_group_ids(enemy), [FLAG_PROSECUTED])
				f.erase(FLAG_PSY_CHAFF_TARGET)
		"purgation-sweep-null-maiden-vigil":
			Common.erase_flags(group, [FLAG_PURGATION])
		"prime-target-guardians-of-the-throne":
			Common.erase_flags(group, [FLAG_PRIME_TARGET])
		"tip-of-the-talon-aquilan-shield":
			Common.erase_flags(group, [FLAG_TIP_OF_THE_TALON])
		"advanced-stabilisers-grav-assault-force":
			Common.erase_flags(group, [FLAG_ADVANCED_STABILISERS])
		"inevitable-annihilation-grav-assault-force":
			Common.erase_flags(group, [FLAG_INEVITABLE])
		"vigil-unending-lions-of-the-emperor":
			for gid in group:
				_end_vigil(str(gid))
		"in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen":
			Common.erase_flags(group, [FLAG_AURAMITE])
	Common.log_info("CustodesCodexShooting: %s expired on %s" % [strat.get("name", csv), str(group)])


## VIGIL UNENDING over on one component: hand back the -1 D it added.
static func _end_vigil(unit_id: String) -> void:
	var u := Common.unit(unit_id)
	if u.is_empty() or not u.get("flags", {}).has(FLAG_VIGIL):
		return
	var flags: Dictionary = u.flags
	var marker = flags.get(FLAG_VIGIL, {})
	var prev := int(marker.get("prev", 0)) if typeof(marker) == TYPE_DICTIONARY else 0
	var cur := int(flags.get(FLAG_MINUS_DAMAGE, 0))
	var restored := maxi(prev, cur - 1)
	if restored <= 0:
		flags.erase(FLAG_MINUS_DAMAGE)
	else:
		flags[FLAG_MINUS_DAMAGE] = restored
	flags.erase(FLAG_VIGIL)


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if str(strat.get("csv_id", "")) == "purgation-sweep-null-maiden-vigil":
		return "+1 A" if variant_id != PS_PLUS_TWO else "+2 A vs PSYKER / battle-shocked"
	return ""


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	match csv:
		"psy-chaff-volley-null-maiden-vigil":
			return 2.2 if not _hit_enemy_heads(player, ctx).is_empty() else 0.0
		"purgation-sweep-null-maiden-vigil":
			return 2.0 if Common.nearest_enemy_inches(Common.group_union(uid)) <= 12.0 else 0.0
		"prime-target-guardians-of-the-throne":
			return 2.0 if Common.nearest_enemy_inches(Common.group_union(uid)) <= 24.0 else 0.0
		"tip-of-the-talon-aquilan-shield":
			return 2.2 if Common.nearest_enemy_inches(Common.group_union(uid)) <= TIP_OF_THE_TALON_RANGE_IN else 0.0
		"advanced-stabilisers-grav-assault-force":
			# Only matters after an Advance (otherwise every weapon may shoot).
			return 2.5 if bool(Common.unit(uid).get("flags", {}).get("advanced", false)) else 0.0
		"inevitable-annihilation-grav-assault-force":
			# Worth it when the nearest target is likely to be in cover / far.
			return 2.0 if Common.nearest_enemy_inches(Common.group_union(uid)) > 18.0 else 0.0
		"vigil-unending-lions-of-the-emperor", "in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen":
			var pts := 0
			for gid in Common.attached_group_ids(uid):
				pts += int(Common.unit(str(gid)).get("meta", {}).get("points", 0))
			var base := clampf(float(pts) / 120.0, 0.0, 4.0)
			return base
	return 0.0


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		"psy-chaff-volley-null-maiden-vigil":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_HAS_SHOT else []
		"purgation-sweep-null-maiden-vigil", "prime-target-guardians-of-the-throne", "tip-of-the-talon-aquilan-shield", \
				"advanced-stabilisers-grav-assault-force", "inevitable-annihilation-grav-assault-force":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_SELECTED_TO_SHOOT else []
		"vigil-unending-lions-of-the-emperor", "in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen":
			if window_id != W_TARGETS_SHOOTING and window_id != W_TARGETS_FIGHT:
				return []
			var out: Array = []
			for tid in ctx.get("target_unit_ids", []):
				var h := Common.head_id(str(tid))
				if not h in out and int(Common.unit(h).get("owner", 0)) == player:
					out.append(h)
			return out
	return []


static func _entry_extra(csv: String, unit_id: String, _window_id: String, ctx: Dictionary) -> Dictionary:
	match csv:
		"purgation-sweep-null-maiden-vigil":
			return {"require_variant": true, "ai_variant": PS_PLUS_ONE, "variants": [
				{"id": PS_PLUS_ONE, "label": "+1 A", "cp_cost": 1},
				{"id": PS_PLUS_TWO, "label": "Or: +2 A if those attacks target a PSYKER / battle-shocked unit", "cp_cost": 1}]}
		"psy-chaff-volley-null-maiden-vigil":
			var player := int(Common.unit(unit_id).get("owner", 0))
			var opts: Array = []
			for eid in _hit_enemy_heads(player, ctx):
				opts.append({"id": str(eid), "label": Common.group_label(str(eid))})
			return {"secondary": {"kind": "unit", "prompt": "PSY-CHAFF VOLLEY: select one enemy unit hit by those attacks — it is prosecuted (+1 AP) until the end of the turn", "options": opts}}
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
		"psy-chaff-volley-null-maiden-vigil":
			if window_id != "" and window_id != W_HAS_SHOT:
				return _no("%s is used when a PROSECUTOR SQUAD unit has shot" % name)
			if not Common.group_has_keyword(uid, "PROSECUTOR SQUAD"):
				return _no("%s can only target a PROSECUTOR SQUAD unit" % name)
			if _hit_enemy_heads(player, ctx).is_empty():
				return _no("%s: those attacks hit no enemy unit" % name)
		"purgation-sweep-null-maiden-vigil":
			if window_id != "" and window_id != W_SELECTED_TO_SHOOT:
				return _no("%s is used when a WITCHSEEKER SQUAD unit is selected to shoot" % name)
			if not Common.group_has_keyword(uid, "WITCHSEEKER SQUAD"):
				return _no("%s can only target a WITCHSEEKER SQUAD unit" % name)
			if not _has_torrent_weapon(uid):
				return _no("%s: %s has no [TORRENT] weapon" % [name, Common.unit_name(uid)])
		"prime-target-guardians-of-the-throne", "tip-of-the-talon-aquilan-shield":
			if window_id != "" and window_id != W_SELECTED_TO_SHOOT:
				return _no("%s is used when an ADEPTUS CUSTODES unit is selected to shoot" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
		"advanced-stabilisers-grav-assault-force", "inevitable-annihilation-grav-assault-force":
			if window_id != "" and window_id != W_SELECTED_TO_SHOOT:
				return _no("%s is used when a GRAV-ASSAULT unit is selected to shoot" % name)
			if not Common.group_has_keyword(uid, "GRAV-ASSAULT"):
				return _no("%s can only target a GRAV-ASSAULT unit" % name)
		"vigil-unending-lions-of-the-emperor":
			if window_id != "" and window_id != W_TARGETS_SHOOTING and window_id != W_TARGETS_FIGHT:
				return _no("%s is used when an enemy unit targets one of your TERMINATOR units" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "TERMINATOR")):
				return _no("%s can only target an ADEPTUS CUSTODES TERMINATOR unit" % name)
			if window_id != "" and not uid in _ctx_heads(ctx.get("target_unit_ids", [])):
				return _no("%s: %s is not a target of that enemy unit's attacks" % [name, Common.unit_name(uid)])
		"in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen":
			if window_id != "" and window_id != W_TARGETS_SHOOTING and window_id != W_TARGETS_FIGHT:
				return _no("%s is used when an enemy unit targets one of your ADEPTUS CUSTODES units" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if Common.group_has_keyword(uid, "CUSTODIAN WARDENS"):
				return _no("%s cannot target a CUSTODIAN WARDENS unit" % name)
			if window_id != "" and not uid in _ctx_heads(ctx.get("target_unit_ids", [])):
				return _no("%s: %s is not a target of that enemy unit's attacks" % [name, Common.unit_name(uid)])
		_:
			return _no("%s is not yet mechanically implemented" % name)
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _display_name(csv: String) -> String:
	match csv:
		"psy-chaff-volley-null-maiden-vigil": return "PSY-CHAFF VOLLEY"
		"purgation-sweep-null-maiden-vigil": return "PURGATION SWEEP"
		"prime-target-guardians-of-the-throne": return "PRIME TARGET"
		"tip-of-the-talon-aquilan-shield": return "TIP OF THE TALON"
		"advanced-stabilisers-grav-assault-force": return "ADVANCED STABILISERS"
		"inevitable-annihilation-grav-assault-force": return "INEVITABLE ANNIHILATION"
		"vigil-unending-lions-of-the-emperor": return "VIGIL UNENDING"
		"in-auramite-clad-guardians-of-the-throne", "in-auramite-clad-emperors-chosen": return "IN AURAMITE CLAD"
	return csv


static func _log(player: int, msg: String) -> void:
	Common.log_info("[CustodesCodexShooting] " + msg)
	Common.game_log(player, msg)


static func _ctx_heads(ids: Array) -> Array:
	var out: Array = []
	for i in ids:
		var h := Common.head_id(str(i))
		if not h in out:
			out.append(h)
	return out


## Enemy units (heads) the shot hit — ctx.hit_unit_ids from the post-shot window.
static func _hit_enemy_heads(player: int, ctx: Dictionary) -> Array:
	var out: Array = []
	for tid in ctx.get("hit_unit_ids", []):
		var h := Common.head_id(str(tid))
		var hu := Common.unit(h)
		if hu.is_empty() or int(hu.get("owner", 0)) == player or h in out:
			continue
		if not Common.is_alive(hu):
			continue
		out.append(h)
	return out


static func _has_torrent_weapon(unit_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("get_unit_weapons"):
		return true
	for gid in Common.attached_group_ids(unit_id):
		var weapons: Dictionary = re.get_unit_weapons(str(gid), Common.state())
		for mid in weapons:
			for wid in weapons[mid]:
				if re.has_method("is_torrent_weapon") and re.is_torrent_weapon(str(wid), Common.state()):
					return true
	return false


# ===========================================================================
# Effect consumers (CustodesCodex11e engine hooks)
# ===========================================================================

## AP for one batch: +1 AP (improve) vs a prosecuted unit (PSY-CHAFF VOLLEY:
## "Attacks that target a prosecuted unit have +1 AP" — any attacker), then
## -1 AP (worsen) vs a unit under IN AURAMITE CLAD ("attacks that target your
## unit have -1 AP until that enemy unit has attacked"). Signed 11e AP
## convention (RulesEngine.improve_ap / worsen_ap).
static func modify_ap(ap: int, _attacker_unit: Dictionary, target_unit: Dictionary) -> int:
	var flags: Dictionary = target_unit.get("flags", {})
	var out := ap
	if int(flags.get(FLAG_PROSECUTED, 0)) > 0:
		out = (out + 1) if out > 0 else (out - 1)
		Common.log_info("[CustodesCodexShooting] PSY-CHAFF VOLLEY: %s is prosecuted — AP %d -> %d" % [str(target_unit.get("id", "?")), ap, out])
	if flags.has(FLAG_AURAMITE) and out != 0:
		var before := out
		out = maxi(0, out - 1) if out > 0 else mini(0, out + 1)
		Common.log_info("[CustodesCodexShooting] IN AURAMITE CLAD: attacks that target %s have -1 AP (%d -> %d)" % [str(target_unit.get("id", "?")), before, out])
	return out


## INEVITABLE ANNIHILATION (ranged): ignore modifiers to BS and hit rolls —
## the engine ignores exactly the harmful ones (Salvus ruling, WP-C3).
static func hit_roll_effects(out: Dictionary, attacker_unit: Dictionary, _target_unit: Dictionary, is_melee: bool, _board: Dictionary) -> void:
	if not is_melee and bool(attacker_unit.get("flags", {}).get(FLAG_INEVITABLE, false)):
		out["ignore_minus"] = true
		out.sources.append("Inevitable Annihilation")


static func ignores_bs_worsening(attacker_unit: Dictionary, is_melee: bool) -> bool:
	return not is_melee and bool(attacker_unit.get("flags", {}).get(FLAG_INEVITABLE, false))


## Remove the harmful BS / hit-roll entries of an 11e ModifierStack
## (INEVITABLE ANNIHILATION). Returns the sources removed.
static func filter_hit_stack(attacker_unit: Dictionary, stack, is_melee: bool) -> Array:
	var removed: Array = []
	if stack == null or not ignores_bs_worsening(attacker_unit, is_melee):
		return removed
	var kept: Array = []
	for e in stack.entries:
		var t := str(e.get("type", ""))
		var v := int(e.get("value", 0))
		if (t == "bs" and v > 0) or (t == "hit_roll" and v < 0):
			removed.append(str(e.get("source", t)))
		else:
			kept.append(e)
	stack.entries = kept
	if not removed.is_empty():
		Common.log_info("[CustodesCodexShooting] INEVITABLE ANNIHILATION: ignoring %s for %s" % [str(removed), str(attacker_unit.get("id", "?"))])
	return removed


## PURGATION SWEEP: per-model +A for [TORRENT] weapons.
static func bonus_ranged_attacks_per_model(attacker_unit: Dictionary, target_unit: Dictionary, _weapon_profile: Dictionary, is_torrent: bool) -> int:
	if not is_torrent:
		return 0
	match str(attacker_unit.get("flags", {}).get(FLAG_PURGATION, "")):
		PS_PLUS_ONE:
			return 1
		PS_PLUS_TWO:
			var th := Common.head_id(str(target_unit.get("id", "")))
			if Common.group_has_keyword(th, "PSYKER") or Common.has_keyword(target_unit, "PSYKER") \
					or Common.is_battle_shocked(target_unit) or Common.is_battle_shocked(Common.unit(th)):
				return 2
	return 0


## TIP OF THE TALON: +1 S for ranged attacks vs a target within 9" of the unit.
static func ranged_strength_bonus(attacker_unit: Dictionary, target_unit: Dictionary, _board: Dictionary) -> int:
	if not bool(attacker_unit.get("flags", {}).get(FLAG_TIP_OF_THE_TALON, false)):
		return 0
	var a_head := Common.head_id(str(attacker_unit.get("id", "")))
	var t_head := Common.head_id(str(target_unit.get("id", "")))
	if Common.group_distance_inches(a_head, t_head) <= TIP_OF_THE_TALON_RANGE_IN + 0.001:
		return 1
	return 0


## PRIME TARGET: is the single re-roll of `stage` still unused?
static func single_reroll_available(attacker_unit: Dictionary, stage: String, is_melee: bool) -> bool:
	if is_melee:
		return false
	var pt = attacker_unit.get("flags", {}).get(FLAG_PRIME_TARGET, null)
	return typeof(pt) == TYPE_DICTIONARY and bool(pt.get(stage, false))


## Spend the single re-roll of `stage` on every component (one per UNIT).
static func single_reroll_spend_diffs(attacker_unit_id: String, stage: String) -> Array:
	var diffs: Array = []
	for gid in Common.attached_group_ids(attacker_unit_id):
		var pt = Common.unit(str(gid)).get("flags", {}).get(FLAG_PRIME_TARGET, null)
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var nd: Dictionary = pt.duplicate()
		nd[stage] = false
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_PRIME_TARGET], "value": nd})
	return diffs


## PRIME TARGET, automatic use (auto-resolved attacks — the AI, Fast Roll,
## the defender-rolled save path): take the single re-roll of `stage` if it is
## still unused. Marks it spent on the board dict the engine resolves on AND on
## the live unit (the board is usually the live state; a copy must not keep a
## second use). Returns true when the re-roll may be made.
static func take_single_reroll(attacker_unit: Dictionary, stage: String) -> bool:
	if not single_reroll_available(attacker_unit, stage, false):
		return false
	var uid := str(attacker_unit.get("id", ""))
	var pt: Dictionary = attacker_unit.get("flags", {}).get(FLAG_PRIME_TARGET, {}).duplicate()
	pt[stage] = false
	attacker_unit["flags"][FLAG_PRIME_TARGET] = pt
	for gid in Common.attached_group_ids(uid):
		var live := Common.unit(str(gid))
		var lpt = live.get("flags", {}).get(FLAG_PRIME_TARGET, null)
		if typeof(lpt) == TYPE_DICTIONARY:
			var nd: Dictionary = lpt.duplicate()
			nd[stage] = false
			live["flags"][FLAG_PRIME_TARGET] = nd
	Common.log_info("[CustodesCodexShooting] PRIME TARGET: %s uses its single %s re-roll" % [uid, stage])
	return true


## ADVANCED STABILISERS: an Advanced GRAV-ASSAULT unit may be selected to shoot
## while its player can still use the stratagem on it (it then fires every
## ranged weapon as [ASSAULT]); a unit that already has it is eligible anyway.
static func may_select_advanced_unit_to_shoot(unit: Dictionary) -> bool:
	if not bool(unit.get("flags", {}).get("advanced", false)):
		return false
	var uid := str(unit.get("id", ""))
	if not Common.group_has_keyword(uid, "GRAV-ASSAULT"):
		return false
	if bool(unit.get("flags", {}).get(FLAG_ADVANCED_STABILISERS, false)):
		return true
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_faction_stratagems_for_player"):
		return false
	var player := int(unit.get("owner", 0))
	for s in sm.get_faction_stratagems_for_player(player):
		if str(s.get("csv_id", "")) != "advanced-stabilisers-grav-assault-force":
			continue
		var chk: Dictionary = sm.can_use_stratagem(player, str(s.get("id", "")), Common.head_id(uid), {"window_id": W_SELECTED_TO_SHOOT})
		return bool(chk.get("can_use", false))
	return false


## [ASSAULT] on the unit's ranged weapons this phase (ADVANCED STABILISERS).
static func grants_ranged_assault(unit: Dictionary) -> bool:
	return bool(unit.get("flags", {}).get(FLAG_ADVANCED_STABILISERS, false))


## An attacking unit's attacks are over: VIGIL UNENDING / IN AURAMITE CLAD
## that waited for it end ("until that enemy unit has attacked").
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	if attacker_unit_id == "":
		return
	var attackers := Common.attached_group_ids(attacker_unit_id)
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		for fname in [FLAG_VIGIL, FLAG_AURAMITE]:
			var m = flags.get(fname, null)
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var hit := false
			for a in m.get("attackers", []):
				if str(a) in attackers:
					hit = true
			if not hit:
				continue
			if fname == FLAG_VIGIL:
				_end_vigil(str(uid))
				Common.log_info("[CustodesCodexShooting] VIGIL UNENDING on %s ended — %s has attacked" % [str(uid), attacker_unit_id])
			else:
				flags.erase(FLAG_AURAMITE)
				Common.log_info("[CustodesCodexShooting] IN AURAMITE CLAD on %s ended — %s has attacked" % [str(uid), attacker_unit_id])
