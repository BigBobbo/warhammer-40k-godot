extends SceneTree

# ISS-070 (11e 24.01): keyword-scoped weapon abilities. A scoped ability
# like "lethal hits: vehicle" applies ONLY against targets with that
# keyword. Previously the has_* helpers ignored the target, so a scoped
# ability fired against everything. The helpers now take the target unit
# and the resolution loops pass it. Backward-compatible: unscoped data
# (all current weapons) and no-target callers are unchanged.
#
# Usage: godot --headless --path . -s tests/test_iss070_keyword_scoped_abilities.gd

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

func _weapon(name: String, rules: String) -> Dictionary:
	return {"name": name, "type": "Ranged", "range": "24", "attacks": "2",
		"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1", "special_rules": rules}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss070_keyword_scoped_abilities ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	if gs == null or rules == null:
		_check("autoloads", false); _finish(); return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	gs.state["units"] = {
		"U_A": {"id": "U_A", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Shooter", "keywords": ["INFANTRY"], "stats": {},
				"weapons": [
					_weapon("Scoped LH", "lethal hits: vehicle"),
					_weapon("Plain LH", "lethal hits"),
					_weapon("Scoped Sus", "sustained hits 1: monster"),
				]},
			"models": [{"id": "a0", "alive": true, "position": {"x": 100, "y": 100}, "base_mm": 32}]},
		"U_VEH": {"id": "U_VEH", "owner": 2, "meta": {"name": "Tank", "keywords": ["VEHICLE"], "stats": {}}, "models": []},
		"U_MON": {"id": "U_MON", "owner": 2, "meta": {"name": "Beast", "keywords": ["MONSTER"], "stats": {}}, "models": []},
		"U_INF": {"id": "U_INF", "owner": 2, "meta": {"name": "Troops", "keywords": ["INFANTRY"], "stats": {}}, "models": []},
	}
	var board = gs.state
	var veh = board["units"]["U_VEH"]
	var mon = board["units"]["U_MON"]
	var inf = board["units"]["U_INF"]

	print("-- scope parsing --")
	_check("'lethal hits: vehicle' -> scope [VEHICLE]",
		rules.get_weapon_ability_scope("Scoped LH", board, "lethal hits") == ["VEHICLE"])
	_check("'lethal hits' (unscoped) -> scope []",
		rules.get_weapon_ability_scope("Plain LH", board, "lethal hits") == [])
	_check("'sustained hits 1: monster' -> scope [MONSTER]",
		rules.get_weapon_ability_scope("Scoped Sus", board, "sustained hits") == ["MONSTER"])

	print("\n-- scoped LETHAL HITS gating --")
	_check("scoped LH applies vs VEHICLE", rules.has_lethal_hits("Scoped LH", board, veh))
	_check("scoped LH does NOT apply vs INFANTRY", not rules.has_lethal_hits("Scoped LH", board, inf))
	_check("scoped LH does NOT apply vs MONSTER", not rules.has_lethal_hits("Scoped LH", board, mon))
	_check("scoped LH with NO target -> unchanged (true, legacy callers)",
		rules.has_lethal_hits("Scoped LH", board))

	print("\n-- unscoped ability unchanged for any target (current data) --")
	_check("plain LH applies vs VEHICLE", rules.has_lethal_hits("Plain LH", board, veh))
	_check("plain LH applies vs INFANTRY", rules.has_lethal_hits("Plain LH", board, inf))

	print("\n-- scoped SUSTAINED HITS gating --")
	_check("scoped sustained applies vs MONSTER", rules.has_sustained_hits("Scoped Sus", board, mon))
	_check("scoped sustained does NOT apply vs INFANTRY", not rules.has_sustained_hits("Scoped Sus", board, inf))
	_check("scoped sustained value is 0 vs INFANTRY",
		rules.get_sustained_hits_value("Scoped Sus", board, inf).value == 0)
	_check("scoped sustained value > 0 vs MONSTER",
		rules.get_sustained_hits_value("Scoped Sus", board, mon).value > 0)

	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
