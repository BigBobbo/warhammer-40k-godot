class_name SnapShooting
extends ShootingType

## 15.09 — ELIGIBLE IF: as stated by the granting rule (e.g. FIRE
## OVERWATCH 15.08). WHILE: one visible enemy unit within 24"; attacks
## hit only on an unmodified 6 (regardless of BS/modifiers); no hit
## re-rolls.

func _init():
	id = "snap"
	display_name = "Snap Shooting"


func eligible(_unit_id: String, _board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["11e shooting types"]}
	# Granted situationally (15.08 Fire Overwatch etc.) — the granting
	# rule performs its own checks; the type itself never self-qualifies.
	return {"eligible": false, "reasons": ["snap shooting is granted by a rule (15.09), not selected freely"]}


func target_allowed(unit_id: String, target_id: String, weapon_profile: Dictionary, board: Dictionary) -> Dictionary:
	var base = super.target_allowed(unit_id, target_id, weapon_profile, board)
	if not base.allowed:
		return base
	# Codex: Adeptus Custodes GOLDEN LIGHT OF THE MOIRAIDES (CustodesCodex11e.gd).
	if load("res://scripts/codex/custodes/CustodesCodex11e.gd").blocks_snap_shooting_at(board.get("units", {}).get(target_id, {})):
		return {"allowed": false, "reason": "GOLDEN LIGHT OF THE MOIRAIDES: cannot be targeted with snap shooting"}
	var rules = _rules()
	if not rules._has_los_to_target_unit(unit_id, target_id, board):
		return {"allowed": false, "reason": "target not visible (15.09)"}
	if _closest_distance_inches(unit_id, target_id, board) > 24.0:
		return {"allowed": false, "reason": "target beyond 24\" (15.09)"}
	return {"allowed": true, "reason": ""}


func hit_consequences(_weapon_profile: Dictionary, _unit_id: String, _target_id: String, _board: Dictionary) -> Dictionary:
	var out = super.hit_consequences(_weapon_profile, _unit_id, _target_id, _board)
	out.snap_only_6s = true
	out.no_hit_rerolls = true
	return out


## 15.09 "within 24\"": the closest distance between the two ATTACHED units —
## 19.01, "an Attached unit is a single unit for all rules purposes", so a
## leader 20" away puts its unit within 24" even when every bodyguard model is
## farther. Measured exactly as the live FIRE OVERWATCH gate
## (RulesEngine.snap_shooting_targets_11e) measures it: every component of the
## shooter's and of the target's Attached unit, both link directions
## (attached_unit_target_id / attached_unit_component_ids). This used to read
## only board.units[target_id].models, so it refused such a target ("target
## beyond 24\"") that the live gate offers. Note: live play never reaches this
## template (eligible() never qualifies, so ShootingPhase never selects
## "snap"); FIRE OVERWATCH offers and resolves targets through
## snap_shooting_targets_11e.
func _closest_distance_inches(unit_id: String, target_id: String, board: Dictionary) -> float:
	var rules = _rules()
	var shooter_components: Array = rules.attached_unit_component_ids(rules.attached_unit_target_id(unit_id, board), board)
	var target_components: Array = rules.attached_unit_component_ids(rules.attached_unit_target_id(target_id, board), board)
	return float(rules._snap_min_distance_inches(shooter_components, target_components, board))
