extends RefCounted

## CustodesReactive — WP-G5: the player-controlled form of three Codex:
## Adeptus Custodes (11e) reactive stratagems that WP-C5 auto-resolved.
## Rulings: RULINGS.md § WP-G5.
##
##   NO ESCAPE (Shadowkeepers, 2 CP) — opponent's Movement phase, an enemy
##     unit ended a fall-back move: "Declare a charge with your unit. When
##     selecting charge targets, you can only select enemy units that made a
##     fall-back move this phase and are within the maximum distance."
##   SELFLESS SERVICE (Emissaries Imperatus, 1 CP) — end of the opponent's
##     Charge phase: "Declare a charge with your unit: When making the charge
##     roll, if the result is greater than 6 (after modifiers), change it to 6.
##     When selecting charge targets, you can select any enemy units that are
##     within 6" of your unit and within the maximum distance."
##   RAPID REACTIONS (Aquilan Shield, 1 CP) — opponent's Movement phase, an
##     enemy unit ended a fall-back move: "Your unit shoots using normal
##     shooting, but while doing so your unit can only target that enemy unit."
##
## A HUMAN decider (not AI, not a networked game) gets the interactive flow;
## an AI decider (and a networked game) keeps the WP-C5 auto path in the
## phase. The flow's state lives on the phase (`_cus11e_g5`, a Dictionary):
##   charge: {kind "charge", stage "roll" | "targets" | "move", player, unit_id,
##            source, cap, roll, rolls, uncapped, selectable, targets}
##   shoot:  {kind "shoot", stage "shoot", player, unit_id, target_id, source,
##            options}
## Actions (validated / processed here through thin phase hooks):
##   CUS11E_REACTIVE_CHARGE_ROLL     {player}                — 11.02: the 2D6 charge roll
##   CUS11E_REACTIVE_CHARGE_TARGETS  {player, payload.target_ids} — 11.04 BEFORE MOVING
##   CUS11E_REACTIVE_CHARGE_FAIL     {player}                — the charge fails (no move)
##   CUS11E_REACTIVE_SHOOT           {player, payload.weapons: [{key, weapon_id}]}
## The charge MOVE itself is made with the engine's own drag tools:
##   SELFLESS SERVICE — ChargeController's Heroic Intervention charge path
##     (APPLY_HEROIC_INTERVENTION_MOVE, validated by ChargePhase's charge
##     movement constraints);
##   NO ESCAPE — MovementController's reactive-move drag (the SWIFT AS THE
##     EAGLE machinery: _ork11e_reactive_move) with a charge flag on the
##     active move: models may end engaged, and End This Unit's Move is judged
##     by the same ChargePhase charge movement constraints (confirm_movement_charge).

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const ACT_ROLL := "CUS11E_REACTIVE_CHARGE_ROLL"
const ACT_TARGETS := "CUS11E_REACTIVE_CHARGE_TARGETS"
const ACT_FAIL := "CUS11E_REACTIVE_CHARGE_FAIL"
const ACT_SHOOT := "CUS11E_REACTIVE_SHOOT"
const ACTIONS := [ACT_ROLL, ACT_TARGETS, ACT_FAIL, ACT_SHOOT]

const SRC_NO_ESCAPE := "NO ESCAPE"
const SRC_SELFLESS := "SELFLESS SERVICE"
const SRC_RAPID := "RAPID REACTIONS"

const SELFLESS_CAP := 6
const SELFLESS_RANGE_IN := 6.0
const CHARGE_DECLARE_MAX_IN := 12.0   # 11.04: within 12" AND within the roll
const WITHIN_TOL_IN := 0.02          # ChargeMove11e.WITHIN_TOLERANCE_INCHES

const ACTIVE_MOVE_KEY := "cus11e_charge"   # MovementPhase active_moves[unit] marker (NO ESCAPE)
const FLAG_NO_ESCAPE := "cus11e_no_escape"  # CustodesCodexMovement.FLAG_NO_ESCAPE (expiry marker)

const DIALOG_NAME := "Cus11eReactiveDialog"
const BAR_NAME := "Cus11eReactiveChargeBar"
const DIALOG_SCRIPT := "res://scripts/codex/custodes/CustodesReactiveDialog.gd"


# ===========================================================================
# Who gets the interactive flow
# ===========================================================================

## A human decider in a local (single-player / hot-seat) game. The networked
## turn layer has no mirror for these sub-steps, so online games keep the
## WP-C5 auto path rather than stall (RULINGS WP-G5).
static func interactive(phase, player: int) -> bool:
	if phase == null or player <= 0:
		return false
	if phase.has_method("_is_ai_window_decider") and phase._is_ai_window_decider(player):
		return false
	var nm = Common.autoload("NetworkManager")
	if nm != null and nm.has_method("is_networked") and nm.is_networked():
		return false
	return true


static func pending(phase) -> Dictionary:
	if phase == null:
		return {}
	var g = phase.get("_cus11e_g5")
	return g if typeof(g) == TYPE_DICTIONARY else {}


static func pending_player(phase) -> int:
	return int(pending(phase).get("player", 0))


static func is_charge_phase(phase) -> bool:
	return phase != null and phase.has_method("_cus11e_hi_result")


# ===========================================================================
# Follow-up entry points (thin hooks in MovementPhase / ChargePhase)
# ===========================================================================

## cus11e_reactive_charge (NO ESCAPE) / cus11e_selfless_service follow-up.
## Returns true when the human flow now owns the phase (paused); false = the
## caller runs its auto path.
static func begin_charge(phase, player: int, followup: Dictionary) -> bool:
	if not interactive(phase, player):
		return false
	var head := Common.head_id(str(followup.get("unit_id", "")))
	var u := Common.unit(head)
	if u.is_empty() or not Common.is_alive(u):
		return false
	var source := str(followup.get("source", SRC_NO_ESCAPE))
	var g := {"kind": "charge", "stage": "roll", "player": player, "unit_id": head, "source": source,
		"cap": SELFLESS_CAP if source == SRC_SELFLESS else 0,
		"roll": 0, "rolls": [], "uncapped": 0, "selectable": [], "targets": []}
	phase._cus11e_g5 = g
	if is_charge_phase(phase):
		# The Heroic Intervention machinery owns the end of the Charge phase
		# while SELFLESS SERVICE resolves (_cus11e_hi_result continues it).
		phase._cus11e_selfless_pending = true
		phase.heroic_intervention_player = player
		phase.heroic_intervention_charging_unit_id = ""
	var msg := "%s: Player %d declares a charge with %s — roll the charge (2D6%s)" % [
		source, player, Common.group_label(head), ", capped at 6\"" if source == SRC_SELFLESS else ""]
	_log(phase, player, msg)
	open_ui(phase)
	return true


## cus11e_shoot (RAPID REACTIONS) follow-up. Returns true when paused.
static func begin_shoot(phase, player: int, followup: Dictionary) -> bool:
	if not interactive(phase, player):
		return false
	var head := Common.head_id(str(followup.get("unit_id", "")))
	var foe := Common.head_id(str(followup.get("forced_target_id", "")))
	if Common.unit(head).is_empty() or foe == "":
		return false
	var options := shoot_options(head, foe)
	if options.is_empty():
		return false  # the auto path logs "no ranged weapon can target it"
	phase._cus11e_g5 = {"kind": "shoot", "stage": "shoot", "player": player, "unit_id": head,
		"target_id": foe, "source": str(followup.get("source", SRC_RAPID)), "options": options}
	_log(phase, player, "%s: Player %d selects the weapons %s fires at %s (normal shooting — it can only target that unit)" % [
		str(followup.get("source", SRC_RAPID)), player, Common.group_label(head), Common.group_label(foe)])
	open_ui(phase)
	return true


# ===========================================================================
# Validation gate (both phases): {} = not ours / let the phase decide.
# ===========================================================================

static func gate(phase, action: Dictionary) -> Dictionary:
	var t := str(action.get("type", ""))
	var g := pending(phase)
	if not t in ACTIONS:
		if g.is_empty() or t.begins_with("DEBUG_"):
			return {}
		# The move stage is made with the phase's own move actions (the
		# reactive-move / Heroic Intervention gates judge those).
		if str(g.get("stage", "")) == "move":
			return {}
		return _invalid("Waiting for Player %d to resolve %s" % [int(g.get("player", 0)), str(g.get("source", "the stratagem"))])
	if g.is_empty():
		return _invalid("No reactive Custodes charge or shooting is in progress")
	if action.has("player") and int(action.get("player", 0)) != int(g.get("player", 0)):
		return _invalid("Player %d resolves %s, not Player %d" % [int(g.get("player", 0)), str(g.get("source", "")), int(action.get("player", 0))])
	var stage := str(g.get("stage", ""))
	match t:
		ACT_ROLL:
			if str(g.get("kind", "")) != "charge" or stage != "roll":
				return _invalid("%s: the charge roll has already been made" % str(g.get("source", "")))
		ACT_TARGETS:
			if str(g.get("kind", "")) != "charge" or stage != "targets":
				return _invalid("%s: not selecting charge targets now" % str(g.get("source", "")))
			var ids = _payload(action).get("target_ids", action.get("target_ids", []))
			if typeof(ids) != TYPE_ARRAY or ids.is_empty():
				return _invalid("%s: select one or more charge targets" % str(g.get("source", "")))
			var selectable: Array = g.get("selectable", [])
			for tid in ids:
				if not Common.head_id(str(tid)) in selectable:
					return _invalid("%s: %s is not a legal charge target (%s)" % [str(g.get("source", "")), Common.unit_name(str(tid)), _target_rule(g)])
		ACT_FAIL:
			if str(g.get("kind", "")) != "charge":
				return _invalid("Not a charge")
		ACT_SHOOT:
			if str(g.get("kind", "")) != "shoot":
				return _invalid("Not a reactive shooting")
			var picks = _payload(action).get("weapons", [])
			if typeof(picks) != TYPE_ARRAY:
				return _invalid("payload.weapons must be an array")
			var used_keys := {}
			for p in picks:
				var opt := _option(g, str(p.get("key", "")) if p is Dictionary else "")
				if opt.is_empty():
					return _invalid("%s: unknown weapon choice %s" % [str(g.get("source", "")), str(p)])
				if used_keys.has(opt.key):
					return _invalid("%s: %s is chosen twice (one profile per weapon)" % [str(g.get("source", "")), str(opt.label)])
				used_keys[opt.key] = true
				var wid := str(p.get("weapon_id", ""))
				if not wid in opt.get("profiles", []).map(func(pr): return str(pr.weapon_id)):
					return _invalid("%s: %s cannot target %s with that profile" % [str(g.get("source", "")), str(opt.label), Common.unit_name(str(g.get("target_id", "")))])
	return {"valid": true, "errors": []}


static func process(phase, action: Dictionary) -> Dictionary:
	match str(action.get("type", "")):
		ACT_ROLL:
			return _process_roll(phase)
		ACT_TARGETS:
			return _process_targets(phase, action)
		ACT_FAIL:
			return _process_fail(phase, "%s: Player %d's charge fails — the unit does not move" % [
				str(pending(phase).get("source", "")), pending_player(phase)])
		ACT_SHOOT:
			return _process_shoot(phase, action)
	return phase.create_result(false, [], "Unknown action")


# ===========================================================================
# Charge: roll -> targets -> move
# ===========================================================================

static func _process_roll(phase) -> Dictionary:
	var g := pending(phase)
	var head := str(g.unit_id)
	var unit := Common.unit(head)
	var player := int(g.player)
	var source := str(g.source)
	var rolls: Array = Common.roll_dice(2, 6)
	var raw := int(rolls[0]) + int(rolls[1])
	var other = load("res://scripts/codex/custodes/CustodesCodexOther.gd")
	var total := maxi(0, raw + int(other.charge_roll_modifier(unit, 0)))
	var uncapped := total
	if int(g.cap) > 0 and total > int(g.cap):
		total = int(g.cap)
	var selectable := selectable_targets(source, head, player, total)
	g["roll"] = total
	g["rolls"] = rolls
	g["uncapped"] = uncapped
	g["selectable"] = selectable
	var label := Common.group_label(head)
	var cap_note := " (%d, changed to 6)" % uncapped if uncapped != total else ""
	var dice := {"context": "cus11e_reactive_charge_roll", "unit_id": head, "unit_name": label, "rolls": rolls,
		"total": total, "uncapped_total": uncapped, "capped": uncapped != total, "targets": selectable,
		"charge_failed": selectable.is_empty(), "source": source}
	phase.dice_log.append(dice)
	if phase.has_signal("dice_rolled"):
		phase.emit_signal("dice_rolled", dice)
	if selectable.is_empty():
		var fail_msg := "%s: %s charge roll %d + %d = %d\"%s — no legal charge target within the roll (%s): the charge fails" % [
			source, label, int(rolls[0]), int(rolls[1]), total, cap_note, _target_rule(g)]
		var res := _process_fail(phase, fail_msg)
		res["cus11e_reactive_charge"] = {"source": source, "unit_id": head, "roll": total, "rolls": rolls, "failed": true}
		return res
	g["stage"] = "targets"
	_log(phase, player, "%s: %s charge roll %d + %d = %d\"%s — legal charge targets: %s" % [
		source, label, int(rolls[0]), int(rolls[1]), total, cap_note,
		", ".join(PackedStringArray(selectable.map(func(t): return Common.group_label(str(t)))))])
	refresh_ui(phase)
	var out: Dictionary = phase.create_result(true, [])
	out["cus11e_reactive_charge"] = info(phase)
	out["dice"] = [dice]
	return out


## 11.04 BEFORE MOVING with the stratagem's selection rule: enemy units (heads)
## within min(12, roll) of the unit — NO ESCAPE: only units that made a
## fall-back move this phase; SELFLESS SERVICE: any enemy unit within 6".
static func selectable_targets(source: String, head: String, player: int, roll: int) -> Array:
	var out: Array = []
	var ceiling := minf(CHARGE_DECLARE_MAX_IN, float(roll))
	var pool: Array = []
	if source == SRC_NO_ESCAPE:
		pool = load("res://scripts/codex/custodes/CustodesCodexMovement.gd").fell_back_enemy_heads(player)
	else:
		pool = Common.enemy_heads(player)
	for eid in pool:
		var t := Common.head_id(str(eid))
		if t in out or not Common.is_alive(Common.unit(t)):
			continue
		var d := Common.group_distance_inches(head, t)
		if source == SRC_SELFLESS and d > SELFLESS_RANGE_IN + WITHIN_TOL_IN:
			continue
		if d > ceiling + WITHIN_TOL_IN:
			continue
		out.append(t)
	return out


## Candidates shown greyed-out in the dialog (in range of the rule but beyond
## the roll), with their distance.
static func near_miss_targets(g: Dictionary) -> Array:
	var out: Array = []
	var head := str(g.get("unit_id", ""))
	var player := int(g.get("player", 0))
	var pool: Array = []
	if str(g.get("source", "")) == SRC_NO_ESCAPE:
		pool = load("res://scripts/codex/custodes/CustodesCodexMovement.gd").fell_back_enemy_heads(player)
	else:
		pool = Common.enemy_heads(player)
	for eid in pool:
		var t := Common.head_id(str(eid))
		if t in g.get("selectable", []) or t in out.map(func(e): return e.unit_id):
			continue
		var d := Common.group_distance_inches(head, t)
		if d > CHARGE_DECLARE_MAX_IN + WITHIN_TOL_IN:
			continue
		if str(g.get("source", "")) == SRC_SELFLESS and d > SELFLESS_RANGE_IN + WITHIN_TOL_IN:
			continue
		out.append({"unit_id": t, "distance": d})
	return out


static func _target_rule(g: Dictionary) -> String:
	if str(g.get("source", "")) == SRC_NO_ESCAPE:
		return "an enemy unit that made a fall-back move this phase, within the charge roll"
	return "an enemy unit within 6\" of your unit and within the charge roll"


static func _process_targets(phase, action: Dictionary) -> Dictionary:
	var g := pending(phase)
	var head := str(g.unit_id)
	var player := int(g.player)
	var source := str(g.source)
	var picked: Array = []
	for tid in _payload(action).get("target_ids", action.get("target_ids", [])):
		var h := Common.head_id(str(tid))
		if not h in picked:
			picked.append(h)
	g["targets"] = picked
	g["stage"] = "move"
	# An Attached target is one unit (19.03): the move must end engaged with it,
	# and engaging its leader is not a non-target engagement.
	var target_units: Array = []
	for h in picked:
		for gid in Common.attached_group_ids(str(h)):
			if not str(gid) in target_units:
				target_units.append(str(gid))
	var names := ", ".join(PackedStringArray(picked.map(func(t): return Common.group_label(str(t)))))
	_log(phase, player, "%s: %s charges %s (%d\") — move the models into engagement range" % [source, Common.group_label(head), names, int(g.roll)])
	if is_charge_phase(phase):
		phase.heroic_intervention_unit_id = head
		phase.heroic_intervention_player = player
		phase.heroic_intervention_charging_unit_id = ""
		phase.heroic_intervention_pending_charge = {"targets": target_units, "mode": "cus11e_selfless_service",
			"declared_at": Time.get_unix_time_from_system(), "distance": int(g.roll), "dice_rolls": g.rolls}
		close_dialog()
		show_bar(phase)
		phase.emit_signal("charge_path_tools_enabled", head, int(g.roll))
	else:
		var label := "%s charge" % source
		phase._ork11e_reactive_move = {"player": player, "unit_id": head, "max_inches": float(g.roll), "source": label}
		phase._reactive_move_owner = player
		phase._ork11e_setup_reactive_active_move(head, float(g.roll), label)
		g["charge_info"] = {"targets": target_units, "target_heads": picked, "roll": int(g.roll), "source": source, "player": player}
		phase.active_moves[head][ACTIVE_MOVE_KEY] = g.charge_info.duplicate(true)
		close_dialog()
		show_bar(phase)
		phase.emit_signal("unit_move_begun", head, "NORMAL")
	var out: Dictionary = phase.create_result(true, [])
	out["cus11e_reactive_charge"] = info(phase)
	return out


## The charge ends without a move (no target in reach, given up, or nothing
## moved): 11.04 — a failed charge; the unit does not move.
static func _process_fail(phase, msg: String) -> Dictionary:
	var g := pending(phase)
	var head := str(g.get("unit_id", ""))
	var player := int(g.get("player", 0))
	_log(phase, player, msg)
	if is_charge_phase(phase):
		if str(phase.heroic_intervention_unit_id) == head and not phase.heroic_intervention_pending_charge.is_empty():
			# The move stage: the engine's own HI abort (charge_resolved resets
			# the charge tools) — it continues the end of the phase.
			return phase._process_abort_heroic_intervention_move({"actor_unit_id": head, "payload": {"reason": msg}})
		phase.heroic_intervention_unit_id = ""
		phase.heroic_intervention_pending_charge = {}
		phase.heroic_intervention_player = 0
		phase.emit_signal("charge_resolved", head, false, {"reason": msg, "heroic_intervention": true})
		return phase._cus11e_hi_result(phase.create_result(true, []))
	# Movement phase (NO ESCAPE)
	if phase.active_moves.has(head) and phase.active_moves[head].has(ACTIVE_MOVE_KEY):
		phase.active_moves[head]["completed"] = true
		phase.active_moves[head]["staged_moves"] = []
		phase.emit_signal("unit_move_confirmed", head, {"mode": "NORMAL", "models_moved": 0})
		phase.call_deferred("_ork11e_refresh_board_visuals")
	phase._ork11e_reactive_move = {}
	phase._reactive_move_owner = 0
	phase._cus11e_g5 = {}
	close_ui()
	return phase._finish_window_followup([])


## Movement phase: End This Unit's Move of a NO ESCAPE charge (hook at the top
## of MovementPhase._process_confirm_unit_move). Judged by ChargePhase's own
## charge movement constraints (distance <= roll incl. terrain, engaged with
## every target and no other enemy unit, coherency, base contact where
## possible, every model ends closer). Nothing moved = the charge fails.
static func confirm_movement_charge(phase, action: Dictionary) -> Dictionary:
	var head := str(action.get("actor_unit_id", ""))
	var md: Dictionary = phase.active_moves.get(head, {})
	var info_c: Dictionary = md.get(ACTIVE_MOVE_KEY, {})
	var source := str(info_c.get("source", SRC_NO_ESCAPE))
	var player := int(info_c.get("player", pending_player(phase)))
	var paths := {}
	var rotations := {}
	var last := {}
	for sm in md.get("staged_moves", []):
		var src := str(sm.get("model_source_unit_id", head))
		if src == "":
			src = head
		last["%s:%s" % [src, str(sm.get("model_id", ""))]] = sm
	for k in last:
		var sm: Dictionary = last[k]
		var src := str(k).get_slice(":", 0)
		var mid := str(sm.get("model_id", ""))
		var orig = md.get("original_positions", {}).get(k, sm.get("from"))
		var dest = sm.get("dest")
		if orig == null or dest == null:
			continue
		var o := _v(orig)
		var d := _v(dest)
		if o.distance_to(d) < 0.5:
			continue
		var key := mid if src == head else "%s:%s" % [src, mid]
		paths[key] = [[o.x, o.y], [d.x, d.y]]
		rotations[key] = float(sm.get("rotation", 0.0))
	if paths.is_empty():
		return _process_fail(phase, "%s: %s did not move — the charge fails" % [source, Common.group_label(head)])
	var cp = load("res://phases/ChargePhase.gd").new()
	cp.name = "Cus11eNoEscapeChargeJudge"
	phase.add_child(cp)
	var v: Dictionary = cp._validate_charge_movement_constraints(head, paths, {"distance": int(info_c.get("roll", 0)), "targets": info_c.get("targets", [])})
	if not v.get("valid", false):
		phase.remove_child(cp)
		cp.free()
		var errs: Array = v.get("errors", [])
		var why := str(errs[0]) if not errs.is_empty() else "illegal charge move"
		Common.log_info("[CustodesReactive] %s charge move rejected: %s" % [source, str(errs)])
		return phase.create_result(false, [], "%s: %s — adjust the models, or Reset and End This Unit's Move to let the charge fail" % [source, why])
	var changes: Array = []
	for key in paths:
		var ref: Dictionary = cp._resolve_charge_path_ref(head, str(key))
		var idx: int = cp._get_model_index(str(ref.unit_id), str(ref.model_id))
		if idx < 0:
			continue
		var fin: Array = paths[key][-1]
		changes.append({"op": "set", "path": "units.%s.models.%d.position" % [str(ref.unit_id), idx], "value": {"x": fin[0], "y": fin[1]}})
		changes.append({"op": "set", "path": "units.%s.models.%d.rotation" % [str(ref.unit_id), idx], "value": rotations.get(key, 0.0)})
	changes.append_array(cp._charge_attached_character_changes(head, paths, true))
	phase.remove_child(cp)
	cp.free()
	for gid in Common.attached_group_ids(head):
		changes.append({"op": "set", "path": "units.%s.flags.charged_this_turn" % str(gid), "value": true})
		changes.append({"op": "set", "path": "units.%s.flags.fights_first" % str(gid), "value": true})
		changes.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), FLAG_NO_ESCAPE], "value": true})
	for tg in info_c.get("targets", []):
		changes.append({"op": "set", "path": "units.%s.flags.has_been_charged" % str(tg), "value": true})
	md["completed"] = true
	md["staged_moves"] = []
	phase._ork11e_reactive_move = {}
	phase._reactive_move_owner = 0
	phase._cus11e_g5 = {}
	close_ui()
	var names := ", ".join(PackedStringArray(info_c.get("target_heads", []).map(func(t): return Common.group_label(str(t)))))
	_log(phase, player, "%s: %s charged %s and ends engaged (Fights First)" % [source, Common.group_label(head), names])
	phase.emit_signal("unit_move_confirmed", head, {"mode": "NORMAL", "models_moved": paths.size()})
	var mm = Common.autoload("MissionManager")
	if mm:
		mm.call_deferred("check_all_objectives", false)
	return phase._finish_window_followup(changes)


## MovementPhase RESET_UNIT_MOVE hook: the re-created reactive move is still
## the NO ESCAPE charge (same roll, same targets).
static func on_reactive_move_reset(phase, unit_id: String) -> void:
	var g := pending(phase)
	if g.is_empty() or str(g.get("unit_id", "")) != unit_id or not g.has("charge_info"):
		return
	if phase.active_moves.has(unit_id):
		phase.active_moves[unit_id][ACTIVE_MOVE_KEY] = g.charge_info.duplicate(true)


## ChargePhase._cus11e_hi_result hook: the SELFLESS SERVICE charge ended.
static func on_charge_finished(phase) -> void:
	if pending(phase).is_empty():
		return
	phase._cus11e_g5 = {}
	close_ui()


# ===========================================================================
# RAPID REACTIONS: normal shooting at the forced target
# ===========================================================================

## Every ranged weapon of the (Attached) unit that can target `target_id`,
## one choice per weapon (base name) per component: {key, shooter, base,
## label, model_ids, profiles: [{weapon_id, name}]}.
static func shoot_options(unit_id: String, target_id: String) -> Array:
	var re = Common.rules()
	if re == null:
		return []
	var board: Dictionary = Common.state()
	var out: Array = []
	for gid in Common.attached_group_ids(unit_id):
		var shooter := str(gid)
		var eligible: Dictionary = re.get_eligible_targets(shooter, board)
		var in_range: Array = []
		for tg in Common.attached_group_ids(target_id):
			in_range = eligible.get(str(tg), {}).get("weapons_in_range", [])
			if not in_range.is_empty():
				break
		if in_range.is_empty():
			continue
		var unit_weapons: Dictionary = re.get_unit_weapons(shooter, board)
		var by_base := {}  # base -> {models: [], profiles: [wid]}
		var order: Array = []
		for model_id in unit_weapons:
			for wid in unit_weapons[model_id]:
				if not wid in in_range:
					continue
				var base := _weapon_base_name(str(wid), board)
				if not by_base.has(base):
					by_base[base] = {"models": [], "profiles": []}
					order.append(base)
				if not str(model_id) in by_base[base].models:
					by_base[base].models.append(str(model_id))
				if not str(wid) in by_base[base].profiles:
					by_base[base].profiles.append(str(wid))
		for base in order:
			var profs: Array = []
			for wid in by_base[base].profiles:
				profs.append({"weapon_id": wid, "name": str(re.get_weapon_profile(wid, board).get("name", wid))})
			out.append({"key": "%s|%s" % [shooter, base], "shooter": shooter, "base": base,
				"label": "%s — %s (x%d)" % [Common.unit_name(shooter), base, by_base[base].models.size()],
				"model_ids": by_base[base].models, "profiles": profs})
	return out


static func _option(g: Dictionary, key: String) -> Dictionary:
	for o in g.get("options", []):
		if str(o.get("key", "")) == key:
			return o
	return {}


static func _process_shoot(phase, action: Dictionary) -> Dictionary:
	var g := pending(phase)
	var player := int(g.player)
	var head := str(g.unit_id)
	var foe := str(g.target_id)
	var source := str(g.source)
	var re = Common.rules()
	var board: Dictionary = Common.state()
	var assignments: Array = []
	for p in _payload(action).get("weapons", []):
		var opt := _option(g, str(p.get("key", "")))
		var wid := str(p.get("weapon_id", ""))
		var models: Array = []
		var uw: Dictionary = re.get_unit_weapons(str(opt.shooter), board)
		for mid in opt.model_ids:
			if wid in uw.get(mid, []):
				models.append(mid)
		if models.is_empty():
			continue
		assignments.append({"weapon_id": wid, "target_unit_id": foe, "model_ids": models, "_shooter": str(opt.shooter)})
	phase._cus11e_g5 = {}
	var summary := {}
	if assignments.is_empty():
		_log(phase, player, "%s: %s does not fire" % [source, Common.group_label(head)])
		summary = {"summary": "%s: %s did not fire" % [source, Common.group_label(head)], "hits": 0, "wounds": 0, "casualties": 0, "lines": []}
	else:
		summary = phase._cus11e_followup_shoot(player, {"unit_id": head, "forced_target_id": foe, "source": source}, assignments)
	var out: Dictionary = phase._finish_window_followup([])
	out["cus11e_reactive_shoot"] = summary
	show_shoot_result(summary)
	return out


static func _weapon_base_name(weapon_id: String, board: Dictionary) -> String:
	var re = Common.rules()
	var wname := str(re.get_weapon_profile(weapon_id, board).get("name", weapon_id)) if re else weapon_id
	for sep in [" – ", " — ", " - "]:
		var idx := wname.find(sep)
		if idx > 0:
			return wname.substr(0, idx)
	return wname


# ===========================================================================
# UI (dialog + move bar) — only with a running Main scene
# ===========================================================================

## The dialog's view of the pending flow.
static func info(phase) -> Dictionary:
	var g := pending(phase).duplicate(true)
	if g.is_empty():
		return {}
	g["unit_name"] = Common.group_label(str(g.get("unit_id", "")))
	if str(g.get("kind", "")) == "charge":
		g["target_rule"] = _target_rule(g)
		g["selectable_labels"] = g.get("selectable", []).map(func(t): return {"unit_id": str(t), "label": Common.group_label(str(t)),
			"distance": Common.group_distance_inches(str(g.unit_id), str(t))})
		if str(g.get("stage", "")) == "targets":
			g["near_misses"] = near_miss_targets(g).map(func(e): return {"unit_id": e.unit_id, "label": Common.group_label(e.unit_id), "distance": e.distance})
	else:
		g["target_name"] = Common.group_label(str(g.get("target_id", "")))
	return g


static func _ui_root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or tree.current_scene.name != "Main":
		return null
	return tree.root


static func open_ui(phase) -> void:
	var root := _ui_root()
	if root == null:
		return
	var dlg = root.get_node_or_null(DIALOG_NAME)
	if dlg == null:
		dlg = AcceptDialog.new()
		dlg.set_script(load(DIALOG_SCRIPT))
		dlg.name = DIALOG_NAME
		root.add_child(dlg)
	dlg.call_deferred("show_for", phase)


static func refresh_ui(phase) -> void:
	var root := _ui_root()
	if root == null:
		return
	var dlg = root.get_node_or_null(DIALOG_NAME)
	if dlg != null:
		dlg.call_deferred("show_for", phase)
	else:
		open_ui(phase)


static func close_dialog() -> void:
	var root := _ui_root()
	if root == null:
		return
	var dlg = root.get_node_or_null(DIALOG_NAME)
	if dlg != null and not bool(dlg.get_meta("showing_result", false)):
		dlg.queue_free()


static func close_ui() -> void:
	close_dialog()
	var root := _ui_root()
	if root == null:
		return
	var bar = root.get_node_or_null(BAR_NAME)
	if bar != null:
		bar.queue_free()


static func show_shoot_result(summary: Dictionary) -> void:
	var root := _ui_root()
	if root == null:
		return
	var dlg = root.get_node_or_null(DIALOG_NAME)
	if dlg != null:
		dlg.call_deferred("show_result", summary)


## The move stage's strip: what to do, and a way to let the charge fail.
static func show_bar(phase) -> void:
	var root := _ui_root()
	if root == null:
		return
	var old = root.get_node_or_null(BAR_NAME)
	if old != null:
		old.free()
	var g := pending(phase)
	var bar := CanvasLayer.new()
	bar.name = BAR_NAME
	bar.layer = 90
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = 96
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.05, 0.92)
	sb.border_color = Color.GOLD
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	bar.add_child(panel)
	var row := HBoxContainer.new()
	row.name = "Row"
	panel.add_child(row)
	var lbl := Label.new()
	lbl.name = "Info"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(440, 0)
	lbl.add_theme_color_override("font_color", Color.GOLD)
	var names := ", ".join(PackedStringArray(g.get("targets", []).map(func(t): return Common.group_label(str(t)))))
	var how := "then Confirm Charge Moves" if is_charge_phase(phase) else "then End This Unit's Move"
	lbl.text = "%s (Player %d): %s charges %s — %d\". Drag the models into engagement range, %s." % [
		str(g.get("source", "")), int(g.get("player", 0)), Common.group_label(str(g.get("unit_id", ""))), names, int(g.get("roll", 0)), how]
	row.add_child(lbl)
	var btn := Button.new()
	btn.name = "FailChargeButton"
	btn.text = "Charge fails (don't move)"
	btn.pressed.connect(func(): submit({"type": ACT_FAIL}))
	row.add_child(btn)
	root.add_child(bar)


## Dialog / bar -> the phase (hot-seat routing sets the deciding player).
static func submit(action: Dictionary) -> Dictionary:
	var ni = load("res://utils/NetworkIntegration.gd")
	var res: Dictionary = ni.route_action(action)
	if not res.get("success", false):
		var tm = Common.autoload("ToastManager")
		var err := str(res.get("error", ""))
		if err == "" and not res.get("errors", []).is_empty():
			err = str(res.errors[0])
		if tm and tm.has_method("show_error"):
			tm.show_error(err)
		Common.log_info("[CustodesReactive] %s refused: %s" % [str(action.get("type", "")), err])
	elif str(action.get("type", "")) in [ACT_SHOOT, ACT_FAIL]:
		# Casualties / snapped-back tokens: redraw the board from GameState.
		var main = (Engine.get_main_loop() as SceneTree).current_scene
		if main != null and main.has_method("_recreate_unit_visuals"):
			main.call_deferred("_recreate_unit_visuals")
	return res


# ===========================================================================
# helpers
# ===========================================================================

static func _payload(action: Dictionary) -> Dictionary:
	var p = action.get("payload", {})
	return p if typeof(p) == TYPE_DICTIONARY else {}


static func _invalid(msg: String) -> Dictionary:
	return {"valid": false, "errors": [msg]}


static func _v(p) -> Vector2:
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


static func _log(phase, player: int, msg: String) -> void:
	Common.log_info("[CustodesReactive] " + msg)
	if phase != null and phase.has_method("log_phase_message"):
		phase.log_phase_message(msg)
	Common.game_log(player, msg)
