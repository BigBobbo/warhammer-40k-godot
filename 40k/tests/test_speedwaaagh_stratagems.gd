extends SceneTree

# Speedwaaagh! stratagem rule effects that touch combat resolution:
#   SPESHUL AMMO           — non-Torrent ranged weapons gain [ANTI-VEHICLE 4+]
#                            (crit wound on 4+ vs VEHICLE -> more wounds get through).
#   DED KILLY CONSTRUCTION — melee weapons gain [LANCE] (+1 to wound on a charge).
#
# Each effect is proven by running the SAME seed with the flag off vs on and
# asserting the flagged run lands strictly more wounds (the flag changes which
# rolls succeed without consuming extra RNG).
#
# Run via: godot --headless --path 40k --script tests/test_speedwaaagh_stratagems.gd

var _passed = 0
var _failed = 0


func _initialize():
	await create_timer(0.2).timeout
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


func _sum_wounds(result: Dictionary) -> int:
	var total := 0
	for d in result.get("dice", []):
		var ctx = str(d.get("context", "")).to_lower()
		if "wound" in ctx and d.has("successes"):
			total += int(d.get("successes", 0))
	return total


# --- SPESHUL AMMO: shooter vs a tough VEHICLE ---------------------------------
func _ranged_board(shooter_flags: Dictionary) -> Dictionary:
	var shooters = []
	for i in range(10):
		shooters.append({"id": "ms%d" % i, "position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var targets = []
	for i in range(1):
		targets.append({"id": "mt%d" % i, "position": {"x": 200.0, "y": 0.0},
			"base_mm": 100, "base_type": "circular", "alive": true, "wounds": 20, "current_wounds": 20,
			"stats": {"toughness": 12, "save": 3}})
	return {"units": {
		"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": shooter_flags, "models": shooters},
		"U_VEHICLE": {"id": "U_VEHICLE", "owner": 2,
			"meta": {"keywords": ["VEHICLE"], "stats": {"toughness": 12, "save": 3, "wounds": 20}, "abilities": []},
			"flags": {}, "models": targets}
	}, "meta": {"phase": 8, "active_player": 1, "battle_round": 1}}


func _shoot(flags: Dictionary, seed_val: int) -> int:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{"weapon_id": "bolt_rifle", "target_unit_id": "U_VEHICLE",
			"model_ids": ["ms0","ms1","ms2","ms3","ms4","ms5","ms6","ms7","ms8","ms9"]}]}}
	return _sum_wounds(rules.resolve_shoot(action, _ranged_board(flags), rng))


# --- DED KILLY: charged attacker with a plain (non-Lance) choppa --------------
func _melee_board(attacker_flags: Dictionary) -> Dictionary:
	var atk = []
	for i in range(10):
		atk.append({"id": "ma%d" % i, "position": {"x": 0.0, "y": float(i * 30)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1})
	var tgt = []
	for i in range(10):
		tgt.append({"id": "mt%d" % i, "position": {"x": 20.0, "y": float(i * 30)},
			"base_mm": 32, "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"stats": {"toughness": 8, "save": 3}})
	return {"units": {
		"U_ATK": {"id": "U_ATK", "owner": 1,
			"meta": {"keywords": ["INFANTRY", "ORKS"], "stats": {"toughness": 5, "save": 6, "wounds": 1}, "abilities": []},
			"flags": attacker_flags, "models": atk},
		"U_TGT": {"id": "U_TGT", "owner": 2,
			"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 8, "save": 3, "wounds": 3}, "abilities": []},
			"flags": {}, "models": tgt}
	}, "meta": {"phase": 10, "active_player": 1, "battle_round": 1}}


func _fight(flags: Dictionary, seed_val: int) -> int:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed_val)
	var rng = rules.RNGService.new()
	var action := {"type": "FIGHT", "actor_unit_id": "U_ATK",
		"payload": {"assignments": [{"attacker": "U_ATK", "target": "U_TGT", "weapon": "choppa"}]}}
	return _sum_wounds(rules.resolve_melee_attacks(action, _melee_board(flags), rng))


func _run_tests():
	print("\n=== SPESHUL AMMO — Anti-Vehicle 4+ (bolt_rifle S4 vs T12 VEHICLE) ===")
	var seeds = [11, 42, 77]
	var sa_better := 0
	for s in seeds:
		var off = _shoot({}, s)
		var on = _shoot({"effect_speshul_ammo": true}, s)
		print("  seed %d: wounds off=%d on=%d" % [s, off, on])
		if on > off:
			sa_better += 1
		_check("seed %d: SPESHUL AMMO does not reduce wounds" % s, on >= off)
	_check("SPESHUL AMMO increases wounds vs VEHICLE on most seeds", sa_better >= 2)

	print("\n=== DED KILLY CONSTRUCTION — LANCE +1 wound on charge (choppa, charged) ===")
	var dk_better := 0
	for s in seeds:
		var off = _fight({"charged_this_turn": true}, s)
		var on = _fight({"charged_this_turn": true, "effect_grant_lance": true}, s)
		print("  seed %d: wounds off=%d on=%d" % [s, off, on])
		if on > off:
			dk_better += 1
		_check("seed %d: LANCE grant does not reduce wounds" % s, on >= off)
	_check("effect_grant_lance increases wounds on a charge on most seeds", dk_better >= 2)

	# LANCE only helps on a charge — no charge, no difference.
	var nc_off = _fight({"charged_this_turn": false}, 42)
	var nc_on = _fight({"charged_this_turn": false, "effect_grant_lance": true}, 42)
	_check("LANCE grant is inert without a charge", nc_on == nc_off)
