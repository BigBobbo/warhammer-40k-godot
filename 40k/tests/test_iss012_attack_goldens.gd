extends SceneTree

# ISS-012 golden-master corpus for the attack resolution paths.
#
# Pins the EXACT dice sequences and state diffs produced by
# RulesEngine.resolve_shoot (ranged path, _resolve_assignment) and
# RulesEngine.resolve_melee_attacks (melee path, _resolve_melee_assignment)
# across a matrix of weapon abilities and fixed seeds.
#
# Purpose: the planned extraction of a unified AttackSequence module must
# reproduce these outputs byte-for-byte. Any unintended change to either
# resolution path fails this test.
#
# Fixture: tests/fixtures/attack_goldens.json (committed).
# To regenerate after an INTENTIONAL rules change, delete the fixture and
# re-run this test once (it will rewrite it and report REGENERATED).
#
# Usage: godot --headless --path . -s tests/test_iss012_attack_goldens.gd

var passed := 0
var failed := 0

const FIXTURE_PATH := "res://tests/fixtures/attack_goldens.json"
const SEEDS := [11, 22, 33]
const RANGED_CONFIGS := [
	"",
	"sustained hits 1",
	"sustained hits d3",
	"lethal hits",
	"devastating wounds",
	"anti-infantry 4+",
	"anti-infantry 4+, devastating wounds",
	"rapid fire 1",
	"blast",
	"torrent",
	"melta 2",
	"twin-linked",
	"heavy",
	"sustained hits 1, lethal hits, twin-linked",
]
const MELEE_CONFIGS := [
	"",
	"sustained hits 1",
	"lethal hits",
	"devastating wounds",
	"twin-linked",
	"lance",
	"precision",
]

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
	print("\n=== test_iss012_attack_goldens ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return

	var current := _capture_all(rules)

	if not FileAccess.file_exists(FIXTURE_PATH):
		var f = FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(current, "  "))
		f.close()
		print("  REGENERATED: fixture written with %d entries" % current.size())
		_check("fixture regenerated (first run)", true)
		_finish()
		return

	var f = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	var golden = JSON.parse_string(f.get_as_text())
	f.close()
	_check("fixture loaded (%d entries)" % golden.size(), golden is Dictionary and golden.size() > 0)

	var mismatches := []
	for key in golden:
		if not current.has(key):
			mismatches.append(key + " (missing)")
		elif _canon(current[key]) != _canon(golden[key]):
			mismatches.append(key)
	for key in current:
		if not golden.has(key):
			mismatches.append(key + " (new)")
	_check("all %d golden entries match current resolution output" % golden.size(),
		mismatches.is_empty(), str(mismatches.slice(0, 5)))
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

## Canonicalize through a JSON round-trip so live GDScript values (int dict
## keys, int vs float) compare equal to fixture data parsed from JSON.
func _canon(v) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))

# -- capture -------------------------------------------------------------------

func _capture_all(rules) -> Dictionary:
	var out := {}
	for cfg in RANGED_CONFIGS:
		for seed in SEEDS:
			var key = "ranged|%s|seed%d" % [cfg if cfg != "" else "plain", seed]
			out[key] = _run_ranged(rules, cfg, seed)
	for cfg in MELEE_CONFIGS:
		for seed in SEEDS:
			var key = "melee|%s|seed%d" % [cfg if cfg != "" else "plain", seed]
			out[key] = _run_melee(rules, cfg, seed)
	return out

func _run_ranged(rules, special_rules: String, seed: int) -> Dictionary:
	var board = _ranged_board(special_rules)
	var action = {
		"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Golden Test Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2"], "attacks_override": 5
		}]}
	}
	var res = rules.resolve_shoot(action, board, rules.RNGService.new(seed))
	return _digest(res)

func _run_melee(rules, special_rules: String, seed: int) -> Dictionary:
	var board = _melee_board(special_rules)
	# NOTE: the melee assignment schema differs from ranged in THREE ways
	# (weapon/target/models vs weapon_id/target_unit_id/model_ids, and
	# `models` holds string indices, not model ids) — exactly the drift the
	# AttackSequence unification must normalize (ISS-012).
	var action = {
		"type": "FIGHT", "actor_unit_id": "U_FIGHTER",
		"payload": {"assignments": [{
			"attacker": "U_FIGHTER",
			"weapon": "Golden Test Blade", "target": "U_DEFENDER",
			"models": ["0", "1"]
		}]}
	}
	var res = rules.resolve_melee_attacks(action, board, rules.RNGService.new(seed))
	return _digest(res)

func _digest(res: Dictionary) -> Dictionary:
	return {
		"success": res.get("success", false),
		"dice": res.get("dice", []),
		"diffs": res.get("diffs", []),
	}

# -- fixtures ------------------------------------------------------------------

func _ranged_board(special_rules: String) -> Dictionary:
	var weapon = {
		"name": "Golden Test Gun", "type": "Ranged", "range": "24",
		"attacks": "2", "ballistic_skill": "3", "strength": "5",
		"ap": "-1", "damage": "2", "special_rules": special_rules
	}
	var shooters = []
	for i in range(3):
		shooters.append({
			"id": "ms%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
		})
	var targets = []
	for i in range(7):
		targets.append({
			"id": "mt%d" % i, "position": {"x": 200, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1, "flags": {},
				"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2},
					"weapons": [weapon]},
				"models": shooters
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2}},
				"models": targets
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}
	}

func _melee_board(special_rules: String) -> Dictionary:
	var weapon = {
		"name": "Golden Test Blade", "type": "Melee", "range": "Melee",
		"attacks": "3", "weapon_skill": "3", "strength": "5",
		"ap": "-1", "damage": "1", "special_rules": special_rules
	}
	var fighters = []
	for i in range(2):
		fighters.append({
			"id": "mf%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
		})
	var defenders = []
	for i in range(5):
		defenders.append({
			"id": "md%d" % i, "position": {"x": 36, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_FIGHTER": {
				"id": "U_FIGHTER", "owner": 1,
				"flags": {"charged_this_turn": true},
				"meta": {"name": "Fighters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2},
					"weapons": [weapon]},
				"models": fighters
			},
			"U_DEFENDER": {
				"id": "U_DEFENDER", "owner": 2, "flags": {},
				"meta": {"name": "Defenders", "keywords": ["INFANTRY", "CHARACTER"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2}},
				"models": defenders
			}
		},
		"meta": {"phase": 10, "active_player": 1, "battle_round": 2}
	}
