extends SceneTree

# RulesEngine.charge_target_ineligibility_reason() — the sentence the charge
# phase shows when a player CLICKS AN ENEMY ON THE BOARD that cannot be charged.
#
# Click-to-target lets a player click any enemy model, not just the ones listed
# in ELIGIBLE TARGETS, so a dead click has to explain itself. This helper is the
# explanation, and its whole contract is that it mirrors
# charge_targets_within_12()'s filters exactly — a target the list accepts must
# return "" here, and every reason the list rejects one must be named.
#
# Covers:
#   • "" (chargeable) for a target charge_targets_within_12 DOES return.
#   • out of the 12" declaration range, with the real measured distance.
#   • AIRCRAFT without FLY on the charger; FLY chargers are allowed.
#   • friendly / destroyed / unknown units.
#   • agreement with charge_targets_within_12 across every enemy on a board.
#
# Usage: godot --headless --path . -s tests/test_charge_target_ineligibility_reason.gd

var passed := 0
var failed := 0

# Autoloads are runtime nodes for a `-s` SceneTree script, not compile-time
# identifiers — reach RulesEngine through the tree.
func _re() -> Node:
	return root.get_node("RulesEngine")

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s %s" % [label, ("(" + detail + ")") if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run_tests)

func _make_unit(id: String, unit_owner: int, keywords: Array, positions: Array, base_mm: int = 32, alive: bool = true) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		var pos = positions[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": alive,
			"current_wounds": 2,
			"wounds": 2,
			"base_mm": base_mm,
			"base_type": "circular",
			"position": ({"x": pos.x, "y": pos.y} if pos != null else null),
		})
	return {
		"id": id, "squad_id": id, "owner": unit_owner,
		"flags": {},
		"meta": {"name": id, "keywords": keywords},
		"models": models,
		"embarked_in": null,
	}

# Charger at (0,0); every enemy laid out on the +x axis at a chosen CENTRE
# distance in px (40 px = 1"). Edge-to-edge subtracts both 32 mm base radii
# (0.63" each), so a 400 px centre gap measures ~8.74".
func _board() -> Dictionary:
	return {"units": {
		"U_CHG": _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(0, 0)]),
		"U_CHG_FLY": _make_unit("U_CHG_FLY", 2, ["INFANTRY", "FLY"], [Vector2(0, 0)]),
		"U_NEAR": _make_unit("U_NEAR", 1, ["INFANTRY"], [Vector2(400, 0)]),
		"U_FAR": _make_unit("U_FAR", 1, ["INFANTRY"], [Vector2(1200, 0)]),
		"U_PLANE": _make_unit("U_PLANE", 1, ["AIRCRAFT"], [Vector2(300, 0)]),
		"U_DEAD": _make_unit("U_DEAD", 1, ["INFANTRY"], [Vector2(200, 0)], 32, false),
		"U_FRIEND": _make_unit("U_FRIEND", 2, ["INFANTRY"], [Vector2(200, 0)]),
	}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_target_ineligibility_reason ===")

	_test_chargeable_returns_empty()
	_test_out_of_range_names_distance()
	_test_aircraft_needs_fly()
	_test_friendly_dead_and_unknown()
	_test_agrees_with_charge_targets_within_12()

	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _test_chargeable_returns_empty() -> void:
	print("\n-- a target the list accepts has no reason --")
	var board = _board()
	var eligible = _re().charge_targets_within_12("U_CHG", board)
	_check("U_NEAR is in charge_targets_within_12", eligible.has("U_NEAR"))
	var reason = _re().charge_target_ineligibility_reason("U_CHG", "U_NEAR", board)
	_check("chargeable target returns \"\"", reason == "", "got '%s'" % reason)

func _test_out_of_range_names_distance() -> void:
	print("\n-- beyond 12\" says so, with the measured distance --")
	var board = _board()
	var eligible = _re().charge_targets_within_12("U_CHG", board)
	_check("U_FAR is NOT in charge_targets_within_12", not eligible.has("U_FAR"))
	var reason = _re().charge_target_ineligibility_reason("U_CHG", "U_FAR", board)
	_check("reason mentions the 12\" limit", reason.find("within 12") != -1, reason)
	_check("reason names the target", reason.find("U_FAR") != -1, reason)
	# 1200 px centres = 30", minus two 0.63" radii ≈ 28.7"
	_check("reason quotes the real distance", reason.find("28.7") != -1, reason)

func _test_aircraft_needs_fly() -> void:
	print("\n-- AIRCRAFT can only be charged by FLY --")
	var board = _board()
	var reason = _re().charge_target_ineligibility_reason("U_CHG", "U_PLANE", board)
	_check("non-FLY charger is told about AIRCRAFT", reason.find("AIRCRAFT") != -1, reason)
	_check("non-FLY charger is told it needs FLY", reason.find("FLY") != -1, reason)
	_check("AIRCRAFT absent from the non-FLY charger's list",
		not _re().charge_targets_within_12("U_CHG", board).has("U_PLANE"))

	var fly_reason = _re().charge_target_ineligibility_reason("U_CHG_FLY", "U_PLANE", board)
	_check("FLY charger gets no objection", fly_reason == "", "got '%s'" % fly_reason)
	_check("AIRCRAFT present in the FLY charger's list",
		_re().charge_targets_within_12("U_CHG_FLY", board).has("U_PLANE"))

func _test_friendly_dead_and_unknown() -> void:
	print("\n-- friendly / destroyed / unknown --")
	var board = _board()
	var friendly = _re().charge_target_ineligibility_reason("U_CHG", "U_FRIEND", board)
	_check("friendly unit refused", friendly.find("friendly") != -1, friendly)

	var dead = _re().charge_target_ineligibility_reason("U_CHG", "U_DEAD", board)
	_check("destroyed unit refused", dead.find("destroyed") != -1, dead)

	var unknown = _re().charge_target_ineligibility_reason("U_CHG", "U_NOPE", board)
	_check("unknown target refused", unknown != "", unknown)
	var no_charger = _re().charge_target_ineligibility_reason("U_NOPE", "U_NEAR", board)
	_check("unknown charger refused", no_charger != "", no_charger)

func _test_agrees_with_charge_targets_within_12() -> void:
	print("\n-- the reason NEVER disagrees with the list it explains --")
	var board = _board()
	for charger_id in ["U_CHG", "U_CHG_FLY"]:
		var eligible = _re().charge_targets_within_12(charger_id, board)
		for target_id in board["units"]:
			if target_id == charger_id:
				continue
			var reason = _re().charge_target_ineligibility_reason(charger_id, target_id, board)
			var listed = eligible.has(target_id)
			_check("%s -> %s: listed=%s matches reason=%s" % [charger_id, target_id, listed, reason == ""],
				listed == (reason == ""), reason)
