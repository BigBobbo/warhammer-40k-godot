extends SceneTree

# ISS-071 (24.14): Firing Deck offers each embarked model ONE ranged
# weapon, EXCLUDING [ONE SHOT] weapons. (Also fixes a stale call to the
# non-existent get_unit_weapon_profiles.) Drives the REAL
# FiringDeckDialog._populate_available_weapons + the one-per-model guard.
#
# Usage: godot --headless --path . -s tests/test_iss071_firing_deck_11e.gd

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

func _w(name: String, rules: String) -> Dictionary:
	return {"name": name, "type": "Ranged", "range": "18", "attacks": "2",
		"ballistic_skill": "5", "strength": "4", "ap": "0", "damage": "1", "special_rules": rules}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss071_firing_deck_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	# Embarked unit with a normal ranged weapon, a [ONE SHOT] ranged
	# weapon, and a melee weapon (should not be offered).
	gs.state["units"] = {
		"U_EMB": {"id": "U_EMB", "owner": 1, "status": 2, "flags": {},
			"embarked_in": "U_TRANSPORT",
			"meta": {"name": "Passengers", "keywords": ["INFANTRY"],
				"weapons": [
					_w("Shoota", ""),
					_w("Rokkit", "one shot"),
					{"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3",
						"weapon_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": ""},
				]},
			"models": [
				{"id": "m0", "alive": true, "position": {"x": 100, "y": 100}, "base_mm": 32},
				{"id": "m1", "alive": true, "position": {"x": 130, "y": 100}, "base_mm": 32},
			]},
	}

	var DialogScript = load("res://scripts/FiringDeckDialog.gd")
	var dlg = DialogScript.new()
	dlg.embarked_unit_ids = ["U_EMB"]
	dlg.firing_deck_capacity = 2
	dlg._populate_available_weapons()

	var names: Array = []
	for w in dlg.available_weapons:
		names.append(str(w.get("weapon_name", "")))
	print("offered weapons: ", names)
	_check("normal ranged weapon (Shoota) is offered", "Shoota" in names)
	_check("[ONE SHOT] weapon (Rokkit) is EXCLUDED (24.14)", not ("Rokkit" in names))
	_check("melee weapon (Choppa) is NOT offered (ranged-only)", not ("Choppa" in names))

	print("\n-- one weapon per model (24.14) --")
	dlg.selected_weapons = [{"unit_id": "U_EMB", "model_idx": 0, "weapon_name": "Shoota"}]
	_check("model 0 already has a selection", dlg._model_already_has_selection("U_EMB", 0))
	_check("model 1 has no selection yet", not dlg._model_already_has_selection("U_EMB", 1))

	dlg.free()
	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
