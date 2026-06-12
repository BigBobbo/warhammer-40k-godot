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


func _closest_distance_inches(unit_id: String, target_id: String, board: Dictionary) -> float:
	var meas = Engine.get_main_loop().root.get_node("/root/Measurement")
	var a = board.get("units", {}).get(unit_id, {})
	var b = board.get("units", {}).get(target_id, {})
	var best := INF
	for ma in a.get("models", []):
		if not ma.get("alive", true) or ma.get("position") == null:
			continue
		for mb in b.get("models", []):
			if not mb.get("alive", true) or mb.get("position") == null:
				continue
			best = min(best, meas.px_to_inches(meas.model_to_model_distance_px(ma, mb)))
	return best
