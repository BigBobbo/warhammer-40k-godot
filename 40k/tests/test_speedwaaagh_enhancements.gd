extends SceneTree

# Speedwaaagh! enhancement rule effects (list-build weapon mutations) + the
# 3D6 dice support they rely on.
#
#   Master Meknologist  — +1 BS to the bearer's ranged weapons (min 2+).
#   Supa-burny Fuel      — killa jet – burna Attacks -> 3D6, cutta -> 3.
#
# Run via: godot --headless --path 40k --script tests/test_speedwaaagh_enhancements.gd

var _alm = null
var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.1).timeout
	_alm = root.get_node_or_null("ArmyListManager")
	if _alm == null:
		print("FAIL: missing ArmyListManager autoload")
		quit(1)
		return
	_run_tests()
	print("\n=== RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[PASS] %s" % label)
		_passed += 1
	else:
		print("[FAIL] %s" % label)
		_failed += 1


func _weapon(name: String, wtype: String, attacks: String, bs = null) -> Dictionary:
	var w := {"name": name, "type": wtype, "attacks": attacks}
	if bs != null:
		w["ballistic_skill"] = str(bs)
	return w


func _unit(enh: Array, weapons: Array) -> Dictionary:
	return {"meta": {"name": "Test Unit", "enhancements": enh, "weapons": weapons}}


func _run_tests():
	print("\n=== Speedwaaagh! enhancement weapon effects ===\n")

	# --- Master Meknologist: +1 BS to ranged weapons only ---
	print("--- Master Meknologist ---")
	var mm = _unit(["Master Meknologist"], [
		_weapon("Shokk attack gun", "Ranged", "D6+1", 5),   # 5+ -> 4+
		_weapon("Big shoota", "Ranged", "3", 4),            # 4+ -> 3+
		_weapon("Burna", "Ranged", "D6", "N/A"),            # Torrent: no numeric BS -> skip
		_weapon("Choppa", "Melee", "4", null),              # melee -> unaffected (no BS)
	])
	_alm._apply_enhancement_weapon_bonuses("U_TEST", mm)
	var w = mm.meta.weapons
	_check("ranged BS 5+ -> 4+", str(w[0].ballistic_skill) == "4")
	_check("ranged BS 4+ -> 3+", str(w[1].ballistic_skill) == "3")
	_check("Torrent/no-BS weapon skipped", str(w[2].ballistic_skill) == "N/A")
	_check("melee weapon untouched (no BS key added)", not w[3].has("ballistic_skill"))

	# BS floor: a 2+ weapon cannot improve past 2+.
	var mm2 = _unit(["Master Meknologist"], [_weapon("Elite gun", "Ranged", "1", 2)])
	_alm._apply_enhancement_weapon_bonuses("U_TEST2", mm2)
	_check("BS floor holds (2+ stays 2+)", str(mm2.meta.weapons[0].ballistic_skill) == "2")

	# --- Supa-burny Fuel: killa jet Attacks changes ---
	print("\n--- Supa-burny Fuel ---")
	var sf = _unit(["Supa-burny Fuel"], [
		_weapon("Killa jet – Burna", "Ranged", "D6", "N/A"),  # A -> 3D6
		_weapon("Killa jet – Cutta", "Ranged", "1", 5),       # A -> 3
		_weapon("Boomstikks", "Ranged", "6", 5),              # untouched
		_weapon("Snagga klaw", "Melee", "4", null),           # untouched
	])
	_alm._apply_enhancement_weapon_bonuses("U_DEFF", sf)
	var sw = sf.meta.weapons
	_check("killa jet burna Attacks -> 3D6", str(sw[0].attacks) == "3D6")
	_check("killa jet cutta Attacks -> 3", str(sw[1].attacks) == "3")
	_check("Boomstikks Attacks untouched (6)", str(sw[2].attacks) == "6")
	_check("melee Attacks untouched (4)", str(sw[3].attacks) == "4")

	# --- No enhancement: nothing changes ---
	print("\n--- No enhancement ---")
	var none = _unit([], [_weapon("Big shoota", "Ranged", "3", 4)])
	_alm._apply_enhancement_weapon_bonuses("U_NONE", none)
	_check("no enhancement -> BS unchanged", str(none.meta.weapons[0].ballistic_skill) == "4")

	# --- 3D6 dice support (RulesEngine.roll_variable_characteristic) ---
	print("\n--- 3D6 dice support ---")
	var RE = load("res://autoloads/RulesEngine.gd")
	var rng = RE.RNGService.new(7)
	var in_range := true
	var saw_above_3 := false
	for i in range(40):
		var r = RE.roll_variable_characteristic("3D6", rng)
		var v = int(r.get("value"))
		if v < 3 or v > 18:
			in_range = false
		if v > 3:
			saw_above_3 = true
	_check("3D6 stays within [3,18]", in_range)
	_check("3D6 actually rolls (not flat 3 fallback)", saw_above_3)
	var flat = RE.roll_variable_characteristic("3", rng)
	_check("flat '3' returns 3, not rolled", int(flat.get("value")) == 3 and flat.get("rolled") == false)
	var burna = RE.roll_variable_characteristic("3D6", rng)
	_check("3D6 reports rolled=true", burna.get("rolled") == true)
