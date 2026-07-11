class_name ChargeMove11e
extends MoveType

## 11.02 / 11.04 CHARGE (11e). Key deltas from the 10e implementation:
##   ▪ charge TARGETS are selected AFTER the 2D6 roll — each target must be
##     within 12" of the unit AND within the rolled maximum distance.
##   ▪ the charge move must end ENGAGED with every target and engaged with
##     no non-target enemy units (engagement is the edition-aware 2" ER).
##   ▪ AFTER MOVING: every model gains the Fights First ABILITY until the
##     end of the turn (24.13) — not a turn-order flag.
##
## ELIGIBLE IF (11.02): on the battlefield, within 12" of one or more
## enemy units, unengaged, and did not advance or fall back this turn —
## unless an ability makes the unit eligible anyway (Waaagh! / Full
## Throttle set effect_advance_and_charge / effect_fall_back_and_charge;
## Kult of Speed's Adrenaline Junkies is detachment-wide). Mirrors the
## overrides in ChargePhase._can_unit_charge so the UI list and the
## DECLARE_CHARGE validator agree.

func _init():
	id = "charge"
	display_name = "Charge"

static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")

static func _has_adrenaline_junkies(unit: Dictionary) -> bool:
	var fam = Engine.get_main_loop().root.get_node_or_null("/root/FactionAbilityManager")
	return fam != null and fam.unit_has_adrenaline_junkies(unit)

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e charge template; 10e uses ChargePhase's legacy path"]}
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["engaged units cannot declare a charge"]}
	var flags = unit.get("flags", {})
	# Turbo Boostas (Speedwaaagh!): a hard charge lock no advance-and-charge
	# effect can override.
	if flags.get("turbo_boosted", false):
		return {"eligible": false, "reasons": ["turbo boost locks charging this turn"]}
	# Adrenaline Junkies does NOT override other charge locks (e.g.
	# Wazblasta's post-shooting move).
	var adrenaline = _has_adrenaline_junkies(unit) and not flags.get("wazblasta_no_charge", false)
	var charge_after_advance = EffectPrimitivesData.has_effect_advance_and_charge(unit) or adrenaline
	var charge_after_fall_back = EffectPrimitivesData.has_effect_fall_back_and_charge(unit) or adrenaline
	if flags.get("advanced", false) and not charge_after_advance:
		return {"eligible": false, "reasons": ["advanced or fell back this turn"]}
	if flags.get("fell_back", false) and not charge_after_fall_back:
		return {"eligible": false, "reasons": ["advanced or fell back this turn"]}
	if flags.get("cannot_charge", false):
		# Advance/Fall Back moves set cannot_charge too — the overrides above
		# clear that source. Standalone locks (actions 16.01, disembark
		# 18.04) have no advanced/fell_back flag and stay locked.
		var overridden = (flags.get("advanced", false) and charge_after_advance) \
			or (flags.get("fell_back", false) and charge_after_fall_back)
		if not overridden:
			return {"eligible": false, "reasons": ["unit cannot charge (action/disembark lock, 16.01/18.04)"]}
	if _closest_enemy_inches(unit_id, board) > 12.0:
		return {"eligible": false, "reasons": ["no enemy unit within 12\""]}
	return {"eligible": true, "reasons": []}

## BEFORE MOVING (11.02 step 2): the 2D6 charge roll IS the maximum
## distance; targets are then selected from enemies within 12" AND within
## that maximum (selectable_targets).
func before_moving(unit_id: String, board: Dictionary, rng, _context: Dictionary) -> Dictionary:
	var dice = rng.roll_d6(2)
	var roll: int = dice[0] + dice[1]
	return {
		"charge_roll": roll, "dice": [{"context": "charge_roll", "rolls": dice}],
		"selectable_targets": _targets_within(unit_id, board, min(12.0, float(roll))),
	}

func max_distance_inches(_unit: Dictionary, context: Dictionary) -> float:
	return float(context.get("charge_roll", 0))

## AFTER MOVING (11.04): engaged with ALL charge targets; engaged with NO
## enemy unit that is not a charge target; plus universal coherency.
func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	var targets: Array = context.get("charge_targets", [])
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	for tid in targets:
		var t = _unit(board, str(tid))
		if t.is_empty() or not _rules().check_units_in_engagement_range(unit, t, board):
			return {"ok": false, "violations": ["charge move must end engaged with every charge target (%s)" % tid]}
	for other_id in board.get("units", {}):
		if other_id == unit_id or targets.has(other_id):
			continue
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		if _rules().check_units_in_engagement_range(unit, other, board):
			return {"ok": false, "violations": ["charge move ended engaged with a non-target unit (%s)" % other_id]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "charged_this_turn"), "value": true},
		# 11.04: until end of turn, every model has the Fights First
		# ability (consumed by the ISS-050 fight-step ordering).
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "fights_first"), "value": true},
	]

# ── helpers ─────────────────────────────────────────────────────────

func _closest_enemy_inches(unit_id: String, board: Dictionary) -> float:
	var m = _measurement()
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	var best := INF
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		for um in unit.get("models", []):
			if not um.get("alive", true) or um.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				best = min(best, m.px_to_inches(m.model_to_model_distance_px(um, em)))
	return best

func _targets_within(unit_id: String, board: Dictionary, max_inches: float) -> Array:
	var m = _measurement()
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	var out: Array = []
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		var found := false
		for um in unit.get("models", []):
			if found or not um.get("alive", true) or um.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				if m.px_to_inches(m.model_to_model_distance_px(um, em)) <= max_inches:
					out.append(other_id)
					found = true
					break
		# (a unit must be within 12" AND within the roll; max_inches is
		# already min(12, roll))
	return out
