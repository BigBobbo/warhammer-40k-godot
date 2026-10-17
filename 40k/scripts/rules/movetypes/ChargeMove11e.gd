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
	# GRAB IT (Codex: Orks 11e): hard charge lock until the end of the turn.
	if flags.get("ork11e_grab_it_no_charge", false):
		return {"eligible": false, "reasons": ["GRAB IT: not eligible to declare a charge this turn"]}
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
## the roll (selectable_targets — see selectable_distance_ceiling).
func before_moving(unit_id: String, board: Dictionary, rng, _context: Dictionary) -> Dictionary:
	var dice = rng.roll_d6(2)
	var roll: int = dice[0] + dice[1]
	return {
		"charge_roll": roll, "dice": [{"context": "charge_roll", "rolls": dice}],
		"selectable_targets": _targets_within(unit_id, board, selectable_distance_ceiling(float(roll))),
	}

## Float tolerance (inches) for "within" in _targets_within — the same value
## as ChargePhase.MOVEMENT_CAP_EPSILON, which caps the charge move itself at
## roll + 0.02". Shape-aware edge distances come back a hair either side of an
## exact value (7.0002", 8.899998"), so a target sitting exactly at the roll
## must not be lost to float drift. Pinned by test_charge_target_within_roll_11e.
const WITHIN_TOLERANCE_INCHES: float = 0.02

## Raw base-to-base distance ceiling (inches) for a target to be selectable after
## a charge roll: min(12, roll).
##   ▪ Core 11.04 BEFORE MOVING: "Select one or more enemy units that are within
##     12" of your unit and within the maximum distance of your unit" — and the
##     maximum distance IS the charge roll (11.02 step 2 / 11.04 MAXIMUM DISTANCE).
##   ▪ pg-37 MAKING A CHARGE MOVE example B: a unit "more than 7" from the
##     charging unit ... cannot be selected as a charge target, even though the
##     charging unit could end its charge move within 2" of this unit".
##   ▪ FAILED CHARGES sidebar (11.02): an unmodified roll of 2 "is never
##     sufficient for a unit to complete a charge move" — a unit cannot be within
##     ER (2") when it declares, so no target is ever within a 2" roll.
## Engagement range does NOT extend the ceiling. This deliberately REVERTS the
## earlier "Deffkopta 9\" roll vs a target 9.6\" away" change (PR #859, which set
## the ceiling to min(12, roll + ER) on the reading that a charger only has to
## close to ER): under 11.04 that target is beyond the roll and cannot be
## selected, so the charge fails. Whether a selected target can then actually
## be reached (ER, terrain) is the separate move check.
static func selectable_distance_ceiling(roll: float) -> float:
	return min(12.0, roll)

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

## Every model of the Attached unit headed by unit_id: its own models plus its
## attached CHARACTER(s)'. 19.01: "An attached unit is a single unit for all
## rules purposes", so "within 12" of your unit" (11.02) and "within the maximum
## distance of your unit" (11.04) measure from the leader's models too — and
## the charge move already carries them (<char_unit>:<model> path keys).
## A unit that leads nobody yields just its own models.
func _unit_group_models(unit_id: String, board: Dictionary) -> Array:
	var out: Array = []
	for gid in _rules().attached_unit_component_ids(unit_id, board):
		out.append_array(_unit(board, str(gid)).get("models", []))
	return out

func _closest_enemy_inches(unit_id: String, board: Dictionary) -> float:
	var m = _measurement()
	var unit = _unit(board, unit_id)
	var owner = int(unit.get("owner", 0))
	var group_models := _unit_group_models(unit_id, board)
	var best := INF
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		for um in group_models:
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
	var group_models := _unit_group_models(unit_id, board)
	var out: Array = []
	for other_id in board.get("units", {}):
		var other = board.units[other_id]
		if int(other.get("owner", 0)) == owner:
			continue
		var found := false
		for um in group_models:
			if found or not um.get("alive", true) or um.get("position") == null:
				continue
			for em in other.get("models", []):
				if not em.get("alive", true) or em.get("position") == null:
					continue
				# Inclusive "within", with the float tolerance documented
				# on WITHIN_TOLERANCE_INCHES.
				if m.px_to_inches(m.model_to_model_distance_px(um, em)) <= max_inches + WITHIN_TOLERANCE_INCHES:
					out.append(other_id)
					found = true
					break
		# (11.04: a unit must be within 12" AND within the roll; callers pass
		# selectable_distance_ceiling(roll) == min(12, roll))
	return out
