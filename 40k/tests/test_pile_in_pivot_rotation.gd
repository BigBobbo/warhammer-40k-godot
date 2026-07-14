extends SceneTree

# Unit tests for the pile-in / consolidate MODEL PIVOT logic added so models on
# non-circular bases (bikes, vehicles) can rotate about their centre while
# piling in — mirroring the movement phase, with the pivot cost counted against
# the 3" move.
#
# Covers the pure-state helpers on FightPhase:
#   • _fight_pivot_cost_for_model — 2" for any non-round base (or round >32mm
#     flying-stem VEHICLE); 0" otherwise / for AIRCRAFT.
#   • _fight_effective_move_cap — 3" normally, 3"−pivot when the action rotates
#     the model past its stored facing.
#   • _fight_rotations_from_action — normalises the rotations payload.
#   • _fight_rotation_for_key — resolves index or model-id keys.
#
# Usage: godot --headless --path . -s tests/test_pile_in_pivot_rotation.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

func _unit(keywords: Array) -> Dictionary:
	return {"meta": {"keywords": keywords}}

func _model(base_type: String, base_mm: int = 60, flying_stem: bool = false) -> Dictionary:
	var m := {"id": "m1", "alive": true, "base_mm": base_mm, "position": {"x": 0, "y": 0}, "rotation": 0.0}
	if base_type != "circular":
		m["base_type"] = base_type
	if flying_stem:
		m["flying_stem"] = true
	return m

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_pile_in_pivot_rotation ===\n")
	var fp = load("res://phases/FightPhase.gd").new()

	# --- Pivot cost by base type (Pariah Nexus: all non-round bases cost 2") ---
	var vehicle = _unit(["VEHICLE"])
	_check("oval base costs 2\"",
		fp._fight_pivot_cost_for_model(vehicle, _model("oval", 170)) == 2.0)
	_check("rectangular base costs 2\"",
		fp._fight_pivot_cost_for_model(vehicle, _model("rectangular", 180)) == 2.0)
	_check("standard round base costs 0\"",
		fp._fight_pivot_cost_for_model(_unit(["INFANTRY"]), _model("circular", 32)) == 0.0)
	_check("round base >32mm WITHOUT flying stem costs 0\"",
		fp._fight_pivot_cost_for_model(vehicle, _model("circular", 60)) == 0.0)
	_check("round base >32mm WITH flying stem on VEHICLE costs 2\"",
		fp._fight_pivot_cost_for_model(vehicle, _model("circular", 60, true)) == 2.0)
	_check("round flying-stem base on non-VEHICLE costs 0\"",
		fp._fight_pivot_cost_for_model(_unit(["INFANTRY"]), _model("circular", 60, true)) == 0.0)
	_check("AIRCRAFT never pays a pivot cost",
		fp._fight_pivot_cost_for_model(_unit(["AIRCRAFT", "VEHICLE"]), _model("oval", 170)) == 0.0)

	# --- Effective move cap: pivot cost is deducted only when the model rotates ---
	var oval := _model("oval", 170)   # stored rotation 0.0
	# Rotation entry that differs from the stored facing -> pivoted -> cap 1"
	_check("rotated oval: cap = 3\" - 2\" = 1\"",
		abs(fp._fight_effective_move_cap(vehicle, oval, {"m1": 1.2}, "m1") - 1.0) < 0.001)
	# Rotation entry equal to the stored facing -> not pivoted -> full 3"
	_check("un-rotated (same facing) oval: cap stays 3\"",
		abs(fp._fight_effective_move_cap(vehicle, oval, {"m1": 0.0}, "m1") - 3.0) < 0.001)
	# No rotation entry at all -> full 3"
	_check("no rotation payload: cap stays 3\"",
		abs(fp._fight_effective_move_cap(vehicle, oval, {}, "m1") - 3.0) < 0.001)
	# A pivoting round base has 0 cost, so its cap stays 3" even when rotated
	_check("rotated round base: cap stays 3\" (0 pivot cost)",
		abs(fp._fight_effective_move_cap(_unit(["INFANTRY"]), _model("circular", 32), {"m1": 1.0}, "m1") - 3.0) < 0.001)

	# --- Rotation payload plumbing ---
	var act := {"type": "PILE_IN", "unit_id": "U", "rotations": {"0": 0.7, "m2": -0.3}}
	var rots = fp._fight_rotations_from_action(act)
	_check("rotations extracted from action", rots.size() == 2 and rots.get("0") == 0.7)
	_check("rotation_for_key resolves index key", fp._fight_rotation_for_key(rots, "0") == 0.7)
	_check("rotation_for_key resolves model-id key", fp._fight_rotation_for_key(rots, "m2") == -0.3)
	_check("rotation_for_key returns null for unrotated model",
		fp._fight_rotation_for_key(rots, "m9") == null)
	_check("empty action yields empty rotations",
		fp._fight_rotations_from_action({"type": "PILE_IN"}).is_empty())

	_finish()

func _finish():
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
