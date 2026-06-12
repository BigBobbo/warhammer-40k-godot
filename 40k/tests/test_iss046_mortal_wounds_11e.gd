extends SceneTree

# ISS-046: 11e mortal wounds (06.02) + [DEVASTATING WOUNDS] cap (24.10).
#
# Checks:
#   A) Model-selection priority per mortal wound: wounded non-CHARACTER ->
#      non-CHARACTER -> wounded CHARACTER -> CHARACTER.
#   B) Normal mortal wounds continue model to model; excess lost when the
#      unit dies.
#   C) The rulebook's devastating-wounds example (pg 80): a crit with D3=3
#      vs W2 Intercessors destroys ONE model with 2 MW; the third is LOST.
#
# Usage: godot --headless --path . -s tests/test_iss046_mortal_wounds_11e.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss046_mortal_wounds_11e ===\n")

	print("-- A: selection priority (06.02) --")
	var unit = {"meta": {"keywords": ["INFANTRY"], "stats": {}}, "models": [
		{"id": "char", "alive": true, "wounds": 4, "current_wounds": 4, "is_character": true},
		{"id": "grunt_full", "alive": true, "wounds": 2, "current_wounds": 2},
		{"id": "grunt_hurt", "alive": true, "wounds": 2, "current_wounds": 1},
	]}
	var r = Allocation.apply_mortal_wounds_11e(unit, 1)
	_check("first MW goes to the WOUNDED non-CHARACTER", r.events[0].model_index == 2, str(r.events))
	r = Allocation.apply_mortal_wounds_11e(unit, 2)
	_check("after it dies, next MW goes to the unwounded non-CHARACTER",
		r.events[1].model_index == 1, str(r.events))
	r = Allocation.apply_mortal_wounds_11e(unit, 5)
	_check("CHARACTER only takes MW once non-CHARACTERs are gone",
		r.events[3].model_index == 0 and r.events[4].model_index == 0, str(r.events))

	print("\n-- B: spillover + excess lost --")
	var pair = {"meta": {"keywords": [], "stats": {}}, "models": [
		{"id": "a", "alive": true, "wounds": 2, "current_wounds": 2},
		{"id": "b", "alive": true, "wounds": 2, "current_wounds": 2},
	]}
	r = Allocation.apply_mortal_wounds_11e(pair, 5)
	_check("4 applied across both models, unit destroyed, 1 lost",
		r.applied == 4 and r.lost == 1 and r.models_destroyed.size() == 2, str(r))

	print("\n-- C: devastating wounds cap (24.10, pg 80 example) --")
	var intercessors = {"meta": {"keywords": ["INFANTRY"], "stats": {}}, "models": [
		{"id": "i0", "alive": true, "wounds": 2, "current_wounds": 2},
		{"id": "i1", "alive": true, "wounds": 2, "current_wounds": 2},
		{"id": "i2", "alive": true, "wounds": 2, "current_wounds": 2},
	]}
	r = Allocation.apply_devastating_wounds_11e(intercessors, 1, 3)
	_check("one crit, D=3: exactly one model destroyed", r.models_destroyed.size() == 1, str(r))
	_check("2 MW applied, the third LOST (cap: one model per crit)",
		r.applied == 2 and r.lost == 1, str(r))
	r = Allocation.apply_devastating_wounds_11e(intercessors, 2, 3)
	_check("two crits damage two separate models (one each), 2 lost total",
		r.models_destroyed.size() == 2 and r.applied == 4 and r.lost == 2, str(r))
	r = Allocation.apply_devastating_wounds_11e(intercessors, 5, 3)
	_check("crits beyond the unit's death are fully lost (3x1 capped + 2x3 whole)",
		r.models_destroyed.size() == 3 and r.applied == 6 and r.lost == 9, str(r))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
