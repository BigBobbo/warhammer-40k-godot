extends RefCounted

## CustodesCodexOther — Codex: Adeptus Custodes (11e) stratagems of the OTHER
## group (WP-C5): Charge phase, any phase, Command phase and the panel
## stratagems. Dispatcher: CustodesCodex11e.gd. Rulings: RULINGS.md § WP-C5.
##
## Windows served:
##   unit_declares_charge   FURY OF THE EMPEROR (ChargePhase)
##   charge_phase_start     GRAVIMETRIC GRENADE (start of the opponent's Charge phase)
##   charge_phase_end       SELFLESS SERVICE (end of the opponent's Charge phase;
##                          follow-up cus11e_selfless_service, ChargePhase)
##   phase_end              SUPERHUMAN FOCUS (x2) — end of any phase, both players
##   unit_destroyed         VICTORY BEFORE DEATH
##   (S panel)              UNLEASH THE LIONS (your Command phase),
##                          GILDED CHAMPION (any phase)
##
## Effect consumers: charge_roll_modifier (ChargePhase charge roll).

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const IDS: Array = [
	"fury-of-the-emperor-lions-of-the-emperor",
	"unleash-the-lions-lions-of-the-emperor",
	"gravimetric-grenade-solar-watch",
	"selfless-service-emissaries-imperatus",
	"superhuman-focus-guardians-of-the-throne",
	"superhuman-focus-emperors-chosen",
	"victory-before-death-grav-assault-force",
	"gilded-champion-auric-champions",
]

const IMPLEMENTED: Dictionary = {
	"fury-of-the-emperor-lions-of-the-emperor": true,
	"unleash-the-lions-lions-of-the-emperor": true,
	"gravimetric-grenade-solar-watch": true,
	"selfless-service-emissaries-imperatus": true,
	"superhuman-focus-guardians-of-the-throne": true,
	"superhuman-focus-emperors-chosen": true,
	"victory-before-death-grav-assault-force": true,
	"gilded-champion-auric-champions": true,
}

const AI_KIND: Dictionary = {
	"fury-of-the-emperor-lions-of-the-emperor": "utility",
	"unleash-the-lions-lions-of-the-emperor": "utility",
	"gravimetric-grenade-solar-watch": "defensive",
	"selfless-service-emissaries-imperatus": "utility",
	"superhuman-focus-guardians-of-the-throne": "utility",
	"superhuman-focus-emperors-chosen": "utility",
	"victory-before-death-grav-assault-force": "utility",
	"gilded-champion-auric-champions": "utility",
}

const KW_CUSTODES := "ADEPTUS CUSTODES"
const KATAH_PATH := "res://scripts/codex/custodes/CustodesKatah.gd"

const W_DECLARES_CHARGE := "unit_declares_charge"
const W_CHARGE_START := "charge_phase_start"
const W_CHARGE_END := "charge_phase_end"
const W_PHASE_END := "phase_end"
const W_DESTROYED := "unit_destroyed"

const FLAG_FURY := "cus11e_fury_of_the_emperor"            # +2 to charge rolls
const FLAG_GRAV_ON_ENEMY := "cus11e_gravimetric_grenade"   # on the ENEMY: -1 to its charge rolls (this phase)
const FLAG_GRAV_TARGET := "cus11e_gravimetric_target"      # on the Custodes unit: the enemy it marked (expiry)
const FLAG_SF_ROUND := "cus11e_superhuman_focus_round"     # battle round SUPERHUMAN FOCUS targeted the unit
const FLAG_VBD := "cus11e_victory_before_death"            # marker: objective id secured
const FLAG_GILDED := "cus11e_gilded_champion"              # once per battle per model: the ability restored
const FLAG_UNLEASHED := "cus11e_unleashed_from"            # on a split-off unit: the unit it came from

const FURY_BONUS := 2
const GRAV_RANGE_IN := 12.0
const SELFLESS_RANGE_IN := 6.0


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
		# S panel probe (no target): usable when at least one unit qualifies.
		if csv in ["unleash-the-lions-lions-of-the-emperor", "gilded-champion-auric-champions"]:
			for uid in _panel_candidates(csv, player):
				if _check(csv, player, str(uid), "", ctx).ok:
					return {"ok": true, "reason": ""}
			return _no(_panel_none_reason(csv))
		return _no("%s needs a target unit" % strat.get("name", "?"))
	var c := _check(csv, player, target_unit_id, str(ctx.get("window_id", "")), ctx)
	if not c.ok:
		return c
	match csv:
		"gravimetric-grenade-solar-watch":
			var sec := str(ctx.get("secondary_id", ""))
			if sec != "" and not sec in _grav_enemy_options(Common.head_id(target_unit_id)):
				return _no("GRAVIMETRIC GRENADE: %s is not a visible enemy unit within 12\"" % Common.unit_name(sec))
		"victory-before-death-grav-assault-force":
			var vsec := str(ctx.get("secondary_id", ""))
			if vsec != "" and not vsec in vbd_objectives(Common.head_id(target_unit_id), player):
				return _no("VICTORY BEFORE DEATH: %s does not qualify" % Common.objective_label(vsec))
	return c


static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var csv := str(strat.get("csv_id", ""))
	var head := Common.head_id(target_unit_id)
	var group := Common.attached_group_ids(head)
	var player := int(Common.unit(head).get("owner", 0))
	var label := Common.group_label(head)
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor":
			_log(player, "FURY OF THE EMPEROR: %s has +2 to charge rolls" % label)
			return Common.set_flag_diffs(group, FLAG_FURY, FURY_BONUS)
		"unleash-the-lions-lions-of-the-emperor":
			return _unleash_apply(head, player)
		"gravimetric-grenade-solar-watch":
			var opts := _grav_enemy_options(head)
			var enemy := str(ctx.get("secondary_id", ""))
			if enemy == "" and not opts.is_empty():
				enemy = str(opts[0])
			if enemy == "" or not enemy in opts:
				Common.log_error("CustodesCodexOther: GRAVIMETRIC GRENADE — no visible enemy unit within 12\" of %s; nothing marked" % head)
				return []
			var d: Array = Common.set_flag_diffs(Common.attached_group_ids(enemy), FLAG_GRAV_ON_ENEMY, player)
			d.append_array(Common.set_flag_diffs(group, FLAG_GRAV_TARGET, enemy))
			_log(player, "GRAVIMETRIC GRENADE: when %s declares a charge this phase it has -1 to its charge roll" % Common.group_label(enemy))
			return d
		"selfless-service-emissaries-imperatus":
			_log(player, "SELFLESS SERVICE: %s declares a charge (charge roll capped at 6; targets: enemy units within 6\")" % label)
			return {"diffs": [], "followup": {"type": "cus11e_selfless_service", "unit_id": head, "source": "SELFLESS SERVICE"}}
		"superhuman-focus-guardians-of-the-throne", "superhuman-focus-emperors-chosen":
			var katah = load(KATAH_PATH)
			var sd: Array = katah.ready_diffs(head)
			sd.append_array(Common.set_flag_diffs(group, FLAG_SF_ROUND, Common.battle_round()))
			_log(player, "SUPERHUMAN FOCUS: %s is readied" % label)
			return sd
		"victory-before-death-grav-assault-force":
			return _vbd_apply(head, player, ctx)
		"gilded-champion-auric-champions":
			return _gilded_apply(head, player)
	Common.log_error("CustodesCodexOther: apply() called for unimplemented %s" % csv)
	return []


static func clear(strat: Dictionary, unit_id: String) -> void:
	var csv := str(strat.get("csv_id", ""))
	var group := Common.attached_group_ids(unit_id)
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor":
			Common.erase_flags(group, [FLAG_FURY])
		"gravimetric-grenade-solar-watch":
			var units: Dictionary = Common.state().get("units", {})
			for gid in group:
				var f: Dictionary = units.get(str(gid), {}).get("flags", {})
				var enemy := str(f.get(FLAG_GRAV_TARGET, ""))
				if enemy != "":
					Common.erase_flags(Common.attached_group_ids(enemy), [FLAG_GRAV_ON_ENEMY])
				f.erase(FLAG_GRAV_TARGET)
		"victory-before-death-grav-assault-force":
			Common.erase_flags(group, [FLAG_VBD])
		_:
			pass  # instant effects (readied, split, follow-up, restored ability)
	Common.log_info("CustodesCodexOther: %s expired on %s" % [strat.get("name", csv), str(group)])


static func ai_kind(strat: Dictionary) -> String:
	return str(AI_KIND.get(str(strat.get("csv_id", "")), "utility"))


static func variant_cp_cost(_strat: Dictionary, _variant_id: String) -> int:
	return -1


static func allows_battle_shocked_target(_strat: Dictionary, _ctx: Dictionary) -> bool:
	return false


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var csv := str(strat.get("csv_id", ""))
	var uid := Common.head_id(target_unit_id)
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor":
			return 2.5
		"gravimetric-grenade-solar-watch":
			return 1.6 if not _grav_enemy_options(uid).is_empty() else 0.0
		"selfless-service-emissaries-imperatus":
			return 2.2
		"superhuman-focus-guardians-of-the-throne", "superhuman-focus-emperors-chosen":
			# Ready a unit that is about to fight (Rendax / Kaptaris next phase).
			return 2.1 if Common.nearest_enemy_inches(Common.group_union(uid)) <= 6.0 else 0.0
		"victory-before-death-grav-assault-force":
			return 2.5 if not vbd_objectives(uid, player).is_empty() else 0.0
		"unleash-the-lions-lions-of-the-emperor", "gilded-champion-auric-champions":
			return 0.0
	return 0.0


# ===========================================================================
# Targets / checks
# ===========================================================================

static func _candidates(csv: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor":
			return [Common.head_id(str(ctx.get("unit_id", "")))] if window_id == W_DECLARES_CHARGE else []
		"gravimetric-grenade-solar-watch":
			return Common.friendly_heads(player) if window_id == W_CHARGE_START else []
		"selfless-service-emissaries-imperatus":
			return Common.friendly_heads(player) if window_id == W_CHARGE_END else []
		"superhuman-focus-guardians-of-the-throne", "superhuman-focus-emperors-chosen":
			return Common.friendly_heads(player) if window_id == W_PHASE_END else []
		"victory-before-death-grav-assault-force":
			# The destroyed unit itself ("you can target that unit even though it
			# is destroyed").
			return [str(ctx.get("unit_id", ""))] if window_id == W_DESTROYED else []
	return []


static func _panel_candidates(csv: String, player: int) -> Array:
	var out: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
			continue
		if csv == "unleash-the-lions-lions-of-the-emperor" and Common.is_attached_character(str(uid)):
			continue
		out.append(str(uid))
	return out


static func _panel_none_reason(csv: String) -> String:
	if csv == "unleash-the-lions-lions-of-the-emperor":
		return "UNLEASH THE LIONS: no friendly ADEPTUS CUSTODES TERMINATOR unit with 2+ models (your Command phase)"
	return "GILDED CHAMPION: no friendly ADEPTUS CUSTODES CHARACTER has used a (Once per battle, per unit) datasheet ability"


static func _entry_extra(csv: String, unit_id: String, player: int, _ctx: Dictionary) -> Dictionary:
	match csv:
		"gravimetric-grenade-solar-watch":
			var opts: Array = []
			for eid in _grav_enemy_options(unit_id):
				opts.append({"id": str(eid), "label": Common.group_label(str(eid))})
			return {"secondary": {"kind": "unit", "prompt": "GRAVIMETRIC GRENADE: select one visible enemy unit within 12\" of %s — it has -1 to its charge roll this phase" % Common.unit_name(unit_id), "options": opts}}
		"victory-before-death-grav-assault-force":
			var vopts: Array = []
			for oid in vbd_objectives(unit_id, player):
				vopts.append({"id": str(oid), "label": Common.objective_label(str(oid))})
			return {"secondary": {"kind": "objective", "prompt": "VICTORY BEFORE DEATH: select one objective %s was controlling — it becomes secured" % Common.unit_name(unit_id), "options": vopts}}
	return {}


static func _check(csv: String, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> Dictionary:
	var name := _display_name(csv)
	var uid := target_unit_id if csv == "victory-before-death-grav-assault-force" else Common.head_id(target_unit_id)
	var u := Common.unit(uid)
	if u.is_empty():
		return _no("%s: unit %s not found" % [name, target_unit_id])
	if int(u.get("owner", 0)) != player:
		return _no("%s: %s is not your unit" % [name, Common.unit_name(uid)])
	if csv != "victory-before-death-grav-assault-force" and not Common.is_on_battlefield(u):
		return _no("%s: %s is not on the battlefield" % [name, Common.unit_name(uid)])
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor":
			if window_id != "" and window_id != W_DECLARES_CHARGE:
				return _no("%s is used when a TERMINATOR unit declares a charge" % name)
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "TERMINATOR")):
				return _no("%s can only target an ADEPTUS CUSTODES TERMINATOR unit" % name)
			if not _made_ingress_this_turn(uid):
				return _no("%s: %s did not make an ingress move this turn" % [name, Common.unit_name(uid)])
		"unleash-the-lions-lions-of-the-emperor":
			if not (Common.group_has_keyword(uid, KW_CUSTODES) and Common.group_has_keyword(uid, "TERMINATOR")):
				return _no("%s can only target an ADEPTUS CUSTODES TERMINATOR unit" % name)
			if Common.current_phase() != Common.GameStateData.Phase.COMMAND or player != Common.active_player():
				return _no("%s can only be used in your Command phase" % name)
			if _alive_model_count(uid) < 2:
				return _no("%s: %s does not have 2+ models" % [name, Common.unit_name(uid)])
		"gravimetric-grenade-solar-watch":
			if window_id != "" and window_id != W_CHARGE_START:
				return _no("%s is used at the start of your opponent's Charge phase" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if not Common.engaged_enemy_ids(uid).is_empty():
				return _no("%s: %s is engaged" % [name, Common.unit_name(uid)])
			if _grav_enemy_options(uid).is_empty():
				return _no("%s: no visible enemy unit within 12\" of %s" % [name, Common.unit_name(uid)])
		"selfless-service-emissaries-imperatus":
			if window_id != "" and window_id != W_CHARGE_END:
				return _no("%s is used at the end of your opponent's Charge phase" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			if Common.group_has_keyword(uid, "VEHICLE") and not (Common.group_has_keyword(uid, "CHARACTER") or Common.group_has_keyword(uid, "WALKER")):
				return _no("%s: a VEHICLE unit can only be selected if it is a CHARACTER or WALKER unit" % name)
			if not Common.engaged_enemy_ids(uid).is_empty():
				return _no("%s: %s is engaged" % [name, Common.unit_name(uid)])
			if Common.nearest_enemy_inches(Common.group_union(uid)) > SELFLESS_RANGE_IN + 0.001:
				return _no("%s: no enemy unit within 6\" of %s" % [name, Common.unit_name(uid)])
			if Common.group_has_keyword(uid, "AIRCRAFT"):
				return _no("%s: AIRCRAFT cannot declare a charge" % name)
		"superhuman-focus-guardians-of-the-throne", "superhuman-focus-emperors-chosen":
			if window_id != "" and window_id != W_PHASE_END:
				return _no("%s is used at the end of a phase" % name)
			if not Common.group_has_keyword(uid, KW_CUSTODES):
				return _no("%s can only target an ADEPTUS CUSTODES unit" % name)
			var katah = load(KATAH_PATH)
			# Being readied only matters to a unit with Martial Ka'tah.
			if not katah.group_has_martial_katah(uid):
				return _no("%s: %s does not have the Martial Ka'tah ability" % [name, Common.unit_name(uid)])
			if katah.is_readied(uid):
				return _no("%s: %s is already readied" % [name, Common.unit_name(uid)])
			for gid in Common.attached_group_ids(uid):
				if int(Common.unit(str(gid)).get("flags", {}).get(FLAG_SF_ROUND, -1)) == Common.battle_round():
					return _no("%s: %s was already targeted by SUPERHUMAN FOCUS this battle round" % [name, Common.unit_name(uid)])
		"victory-before-death-grav-assault-force":
			if window_id != "" and window_id != W_DESTROYED:
				return _no("%s is used when a GRAV-ASSAULT unit is destroyed" % name)
			if not Common.group_has_keyword(uid, "GRAV-ASSAULT"):
				return _no("%s can only target a GRAV-ASSAULT unit" % name)
			if vbd_objectives(uid, player).is_empty():
				return _no("%s: no objective %s was controlling that has no enemy units within range" % [name, Common.unit_name(uid)])
		"gilded-champion-auric-champions":
			if not (Common.has_keyword(u, KW_CUSTODES) and Common.has_keyword(u, "CHARACTER")):
				return _no("%s can only target an ADEPTUS CUSTODES CHARACTER model" % name)
			if u.get("flags", {}).has(FLAG_GILDED):
				return _no("%s has already been used on %s this battle" % [name, Common.unit_name(uid)])
			if _spent_ability(uid) == "":
				return _no("%s: %s has not used a (Once per battle, per unit) datasheet ability" % [name, Common.unit_name(uid)])
		_:
			return _no("%s is not yet mechanically implemented" % name)
	return {"ok": true, "reason": ""}


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _display_name(csv: String) -> String:
	match csv:
		"fury-of-the-emperor-lions-of-the-emperor": return "FURY OF THE EMPEROR"
		"unleash-the-lions-lions-of-the-emperor": return "UNLEASH THE LIONS"
		"gravimetric-grenade-solar-watch": return "GRAVIMETRIC GRENADE"
		"selfless-service-emissaries-imperatus": return "SELFLESS SERVICE"
		"superhuman-focus-guardians-of-the-throne", "superhuman-focus-emperors-chosen": return "SUPERHUMAN FOCUS"
		"victory-before-death-grav-assault-force": return "VICTORY BEFORE DEATH"
		"gilded-champion-auric-champions": return "GILDED CHAMPION"
	return csv


static func _log(player: int, msg: String) -> void:
	Common.log_info("[CustodesCodexOther] " + msg)
	Common.game_log(player, msg)



static func _alive_model_count(unit_id: String) -> int:
	var n := 0
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true):
				n += 1
	return n


static func _made_ingress_this_turn(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("arrived_from_reserves", false)):
			return true
	return false


## Visible enemy units within 12" of the unit (GRAVIMETRIC GRENADE), nearest first.
static func _grav_enemy_options(unit_id: String) -> Array:
	var player := int(Common.unit(unit_id).get("owner", 0))
	var re = Common.rules()
	var pairs: Array = []
	for eid in Common.enemy_heads(player):
		var d := Common.group_distance_inches(unit_id, str(eid))
		if d > GRAV_RANGE_IN + 0.001:
			continue
		var visible := true
		if re and re.has_method("_has_los_to_target_unit"):
			visible = false
			for gid in Common.attached_group_ids(unit_id):
				if re._has_los_to_target_unit(str(gid), str(eid), Common.state()):
					visible = true
					break
		if visible:
			pairs.append([d, str(eid)])
	pairs.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return pairs.map(func(p): return p[1])


# ---------------------------------------------------------------------------
# VICTORY BEFORE DEATH
# ---------------------------------------------------------------------------

## Objectives the destroyed unit was controlling (its models stood within
## range when it was destroyed and its army controlled the objective) that
## have no enemy units (excluding AIRCRAFT) within range of them.
static func vbd_objectives(unit_id: String, player: int) -> Array:
	var out: Array = []
	for obj in Common.objectives():
		var oid := str(obj.get("id", ""))
		if oid == "":
			continue
		if not Common.group_in_objective_range(unit_id, obj, true):
			continue
		if Common.objective_controller(oid) != player:
			continue
		var enemy_in_range := false
		for eid in Common.enemy_heads(player):
			if Common.group_has_keyword(str(eid), "AIRCRAFT"):
				continue
			if Common.group_in_objective_range(str(eid), obj):
				enemy_in_range = true
				break
		if not enemy_in_range:
			out.append(oid)
	return out


static func _vbd_apply(unit_id: String, player: int, ctx: Dictionary) -> Array:
	var objs := vbd_objectives(unit_id, player)
	var obj_id := str(ctx.get("secondary_id", ""))
	if obj_id == "" and not objs.is_empty():
		obj_id = str(objs[0])
	if obj_id == "" or not obj_id in objs:
		Common.log_error("CustodesCodexOther: VICTORY BEFORE DEATH — no qualifying objective for %s (%s)" % [unit_id, obj_id])
		return []
	var mm = Common.mission_manager()
	mm.secure_objective(obj_id, player, "")
	_log(player, "VICTORY BEFORE DEATH: %s secures %s" % [Common.unit_name(unit_id), Common.objective_label(obj_id)])
	return Common.set_flag_diffs([unit_id], FLAG_VBD, obj_id)


# ---------------------------------------------------------------------------
# GILDED CHAMPION — the (Once per battle, per unit) ability UnitAbilityManager
# tracks as spent for the CHARACTER (or for the unit it leads: abilities of an
# attached character are tracked under its bodyguard's id).
# ---------------------------------------------------------------------------

## (Once per battle) datasheet abilities the engine tracks with a unit flag
## instead of UnitAbilityManager's once-per-battle ledger: ability -> flag.
## Moment Shackle (Trajann Valoris) is offered at the start of a phase (the
## phase_start window, CustodesAbilities.gd — WP-C7) unless
## flags.moment_shackle_used is set.
const FLAG_TRACKED_ONCE_PER_BATTLE := {"Moment Shackle": "moment_shackle_used"}

static func _spent_ability(unit_id: String) -> String:
	for ab in FLAG_TRACKED_ONCE_PER_BATTLE:
		if bool(Common.unit(unit_id).get("flags", {}).get(FLAG_TRACKED_ONCE_PER_BATTLE[ab], false)):
			return str(ab)
	var uam = Common.autoload("UnitAbilityManager")
	if uam == null or not uam.has_method("get_used_once_per_battle_abilities"):
		return ""
	for owner_id in [unit_id, Common.head_id(unit_id)]:
		var used: Array = uam.get_used_once_per_battle_abilities(str(owner_id))
		if not used.is_empty():
			return str(used[used.size() - 1])
	return ""


static func _gilded_apply(unit_id: String, player: int) -> Array:
	var uam = Common.autoload("UnitAbilityManager")
	var ability := _spent_ability(unit_id)
	if FLAG_TRACKED_ONCE_PER_BATTLE.has(ability):
		# The ability is offered again from the next phase that offers it
		# (Moment Shackle: the next phase_start window) — never this one.
		_log(player, "GILDED CHAMPION: %s can use %s one additional time (not in this phase)" % [Common.unit_name(unit_id), ability])
		var fd: Array = [{"op": "remove", "path": "units.%s.flags.%s" % [unit_id, FLAG_TRACKED_ONCE_PER_BATTLE[ability]]}]
		fd.append_array(Common.set_flag_diffs([unit_id], FLAG_GILDED, ability))
		return fd
	if uam == null or ability == "":
		Common.log_error("CustodesCodexOther: GILDED CHAMPION — %s has no spent once-per-battle ability" % unit_id)
		return []
	var owner_id := unit_id
	if uam.get_used_once_per_battle_abilities(unit_id).is_empty():
		owner_id = Common.head_id(unit_id)
	uam.restore_once_per_battle_use(owner_id, ability)
	_log(player, "GILDED CHAMPION: %s can use %s one additional time (not in this phase)" % [Common.unit_name(unit_id), ability])
	return Common.set_flag_diffs([unit_id], FLAG_GILDED, ability)


# ---------------------------------------------------------------------------
# UNLEASH THE LIONS — the unit becomes one-model units (starting strength 1)
# ---------------------------------------------------------------------------

static func _unleash_apply(unit_id: String, player: int) -> Array:
	var units: Dictionary = Common.state().get("units", {})
	var src: Dictionary = units.get(unit_id, {})
	if src.is_empty():
		return []
	var diffs: Array = []
	var alive_idx: Array = []
	var models: Array = src.get("models", [])
	for i in range(models.size()):
		if models[i].get("alive", true):
			alive_idx.append(i)
	if alive_idx.size() < 2:
		return []
	var meta: Dictionary = src.get("meta", {})
	var base_name := str(meta.get("display_name", meta.get("name", unit_id)))
	var new_ids: Array = []
	var n := 2
	for k in range(1, alive_idx.size()):
		var new_id := "%s_L%d" % [unit_id, n]
		while units.has(new_id) or new_id in new_ids:
			n += 1
			new_id = "%s_L%d" % [unit_id, n]
		var nu: Dictionary = src.duplicate(true)
		nu["id"] = new_id
		if nu.has("squad_id"):
			nu["squad_id"] = new_id
		nu["models"] = [models[alive_idx[k]].duplicate(true)]
		nu["attachment_data"] = {"attached_characters": []}
		nu["attached_to"] = null
		var nmeta: Dictionary = nu.get("meta", {})
		nmeta["display_name"] = "%s #%d" % [base_name, n]
		nu["meta"] = nmeta
		var nflags: Dictionary = nu.get("flags", {}).duplicate(true)
		nflags[FLAG_UNLEASHED] = unit_id
		nu["flags"] = nflags
		diffs.append({"op": "set", "path": "units.%s" % new_id, "value": nu})
		new_ids.append(new_id)
		n += 1
	# The original unit keeps its first living model only (starting strength 1).
	diffs.append({"op": "set", "path": "units.%s.models" % unit_id, "value": [models[alive_idx[0]].duplicate(true)]})
	# An attached CHARACTER leaves the split unit and becomes a unit of its own.
	for cid in src.get("attachment_data", {}).get("attached_characters", []):
		diffs.append({"op": "set", "path": "units.%s.attached_to" % str(cid), "value": null})
	if not src.get("attachment_data", {}).get("attached_characters", []).is_empty():
		diffs.append({"op": "set", "path": "units.%s.attachment_data" % unit_id, "value": {"attached_characters": []}})
	_log(player, "UNLEASH THE LIONS: %s splits into %d one-model units (%s)" % [base_name, new_ids.size() + 1, ", ".join([unit_id] + new_ids)])
	return diffs


# ===========================================================================
# Effect consumers (CustodesCodex11e engine hooks)
# ===========================================================================

## Charge-roll modifier for the charging unit: FURY OF THE EMPEROR +2,
## GRAVIMETRIC GRENADE -1, plus the engine's own `base_bonus`. INEXORABLE
## ignores the harmful part (the unit "can ignore modifiers to charge rolls" —
## the engine ignores only the penalties, as for Salvus).
static func charge_roll_modifier(unit: Dictionary, base_bonus: int) -> int:
	var flags: Dictionary = unit.get("flags", {})
	var plus := maxi(0, base_bonus)
	var minus := mini(0, base_bonus)
	if int(flags.get(FLAG_FURY, 0)) > 0:
		plus += int(flags.get(FLAG_FURY, 0))
	if int(flags.get(FLAG_GRAV_ON_ENEMY, 0)) > 0:
		minus -= 1
	if minus < 0 and bool(flags.get("cus11e_inexorable", false)):
		Common.log_info("[CustodesCodexOther] INEXORABLE: %s ignores a %d charge-roll penalty" % [str(unit.get("id", "?")), minus])
		minus = 0
	return plus + minus


static func on_command_phase_start(_player: int) -> void:
	pass
