extends SceneTree

# 06_SYNTHESIS launch-blocker #2 / NEW-S1: Big Guns Never Tire eligibility ↔
# validate alignment.
#
# Wahapedia 10e: a MONSTER or VEHICLE unit in Engagement Range can shoot
# with any weapon (subject to a -1 to hit penalty). Other units in ER can
# only fire Pistol weapons.
#
# Pre-issue #370 the eligibility checker silently let MONSTER/VEHICLE
# actors through but the validator rejected the same actor's non-Pistol
# weapon assignments — players got "OK to shoot" then "weapon rejected"
# and the action was unfireable. Both paths must agree on the BGNT carve-
# out.
#
# Pin verifies:
#   A) ShootingPhase eligibility allows MONSTER/VEHICLE in ER (line ~3088).
#   B) RulesEngine.validate_shoot does NOT add the
#      "Non-Pistol weapon ... cannot be fired while in engagement range"
#      error for is_monster_or_vehicle actors (line ~3334).
#   C) RulesEngine.validate_shoot does NOT add the Pistol-target ER
#      restriction for is_monster_or_vehicle actors (line ~3397).
#   D) BGNT helper functions exist and are reachable.
#
# Usage: godot --headless --path . -s tests/test_t002_bgnt_eligibility_validate_pin.gd

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

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t002_bgnt_eligibility_validate_pin ===\n")
	_test_eligibility_carve_out()
	_test_validate_carve_out()
	_test_helpers_exist()
	_finish()

func _test_eligibility_carve_out() -> void:
	print("\n-- A: ShootingPhase eligibility allows BGNT MONSTER/VEHICLE in ER --")
	var src = _read("res://phases/ShootingPhase.gd")
	_check("ShootingPhase.gd readable", not src.is_empty())
	_check("eligibility reads in_engagement flag",
		"in_engagement" in src)
	_check("eligibility carve-out: is_monster_or_vehicle returns true",
		"RulesEngine.is_monster_or_vehicle(unit)" in src
			and "return true" in src.substr(src.find("is_monster_or_vehicle(unit)"), 200),
		"BGNT actor in ER must report eligible without needing Pistol weapons")

func _test_validate_carve_out() -> void:
	print("\n-- B/C: validate_shoot exempts BGNT actors from ER restrictions --")
	var src = _read("res://autoloads/RulesEngine.gd")
	_check("RulesEngine.gd readable", not src.is_empty())
	# Non-Pistol weapon rejection must not fire for BGNT actors
	_check("non-Pistol-in-ER rejection is gated on `not is_monster_or_vehicle(actor_unit)`",
		"not is_pistol_weapon(weapon_id, board) and not is_monster_or_vehicle(actor_unit)" in src,
		"would reject Big Guns Never Tire firing non-Pistol weapons")
	# Pistol-only target restriction must not fire for BGNT actors
	_check("Pistol-only target ER restriction gated on `not is_monster_or_vehicle(actor_unit)`",
		"actor_in_engagement and not is_monster_or_vehicle(actor_unit)" in src,
		"would force BGNT actor to target only the unit it is locked with")

func _test_helpers_exist() -> void:
	print("\n-- D: BGNT helpers reachable on RulesEngine --")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		return
	_check("RulesEngine autoload reachable", true)
	_check("is_monster_or_vehicle helper exists",
		rules.has_method("is_monster_or_vehicle"))
	_check("big_guns_never_tire_applies helper exists",
		rules.has_method("big_guns_never_tire_applies"))
	_check("big_guns_never_tire_penalty_applies helper exists",
		rules.has_method("big_guns_never_tire_penalty_applies"))
	# Drive the helpers against synthetic units.
	var monster_unit = {"meta": {"keywords": ["MONSTER", "INFANTRY"]}}
	var vehicle_unit = {"meta": {"keywords": ["VEHICLE"]}}
	var infantry_unit = {"meta": {"keywords": ["INFANTRY"]}}
	_check("MONSTER classifier returns true",
		rules.call("is_monster_or_vehicle", monster_unit) == true)
	_check("VEHICLE classifier returns true",
		rules.call("is_monster_or_vehicle", vehicle_unit) == true)
	_check("INFANTRY classifier returns false",
		rules.call("is_monster_or_vehicle", infantry_unit) == false)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
