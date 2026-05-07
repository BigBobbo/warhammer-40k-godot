extends SceneTree

# Issue #393: validate AVENGE THE FALLEN +1/+2 conditional on Below Half-strength.
#
# Test 1: 5-model unit at full strength (5 alive) with both flags set
#         (effect_plus_attacks=1, effect_plus_attacks_below_half=2).
#         Expected: +1 per model (default; not below half).
# Test 2: same unit reduced to 2 alive of 5 (below half).
#         Expected: +2 per model (variant override).
# Test 3: parser splitting — verify FactionStratagemLoader emits BOTH
#         PLUS_ATTACKS=1 AND PLUS_ATTACKS_BELOW_HALF=2 for AVENGE-style text
#         containing "below half-strength" clause.
#
# Run via: godot --headless --path 40k --script tests/test_avenge_the_fallen_below_half_393.gd

var _re = null
var _gs = null
var _ep = null


func _initialize():
	await create_timer(0.1).timeout
	_re = root.get_node_or_null("RulesEngine")
	_gs = root.get_node_or_null("GameState")
	_ep = preload("res://autoloads/EffectPrimitives.gd")
	if _re == null or _gs == null:
		print("FAIL: missing autoloads (re=%s gs=%s)" % [str(_re), str(_gs)])
		quit(1)
		return
	_run_tests()


func _run_tests():
	print("\n=== Issue #393: AVENGE THE FALLEN +1/+2 Below-Half conditional ===\n")
	var passed = 0
	var failed = 0

	# --- Setup: 5-model unit, attacker model 0 in engagement, all 5 alive ---
	var board = _make_board(5)
	# Seed GameState so is_below_half_strength_combined can see the unit.
	_gs.state.units = board.units
	_gs.state.board = {}
	# Apply both flags (mimicking AVENGE THE FALLEN being used).
	board.units.U_AVENGE_TEST.flags["effect_plus_attacks"] = 1
	board.units.U_AVENGE_TEST.flags["effect_plus_attacks_below_half"] = 2

	# --- Test 1: full strength → +1 per model ---
	print("--- Test 1: 5/5 alive (above half) — +1 per model expected ---")
	var rng_full = _re.RNGService.new(42)
	var assignment = {
		"attacker": "U_AVENGE_TEST",
		"target": "U_AVENGE_VICTIM",
		"weapon": "Avenge test blade",
		"models": ["0"]
	}
	var result_full = _re._resolve_melee_assignment(assignment, "U_AVENGE_TEST", board, rng_full)
	var attacks_full = _count_total_attacks(result_full)
	# Base attacks=1, +1 from effect, model_count=1 (only model 0 attacks) = 2 attacks
	if attacks_full == 2:
		print("[PASS] full-strength: %d total attacks (base 1 + bonus 1)" % attacks_full)
		passed += 1
	else:
		print("[FAIL] full-strength: expected 2, got %d" % attacks_full)
		failed += 1

	# --- Test 2: kill 3 of 5 — 2 alive = below half → +2 per model ---
	print("\n--- Test 2: 2/5 alive (below half) — +2 per model expected ---")
	var unit = board.units.U_AVENGE_TEST
	for i in range(1, 4):
		unit.models[i].alive = false
	# Re-seed GameState so is_below_half_strength_combined sees updated state.
	_gs.state.units = board.units
	# Use only the surviving attacker model 0.
	var rng_below = _re.RNGService.new(42)
	var result_below = _re._resolve_melee_assignment(assignment, "U_AVENGE_TEST", board, rng_below)
	var attacks_below = _count_total_attacks(result_below)
	# Base attacks=1, +2 from below-half override = 3 attacks
	if attacks_below == 3:
		print("[PASS] below-half: %d total attacks (base 1 + bonus 2)" % attacks_below)
		passed += 1
	else:
		print("[FAIL] below-half: expected 3, got %d" % attacks_below)
		failed += 1

	# --- Test 3: parser emits both effects on AVENGE-style text ---
	print("\n--- Test 3: parser emits PLUS_ATTACKS=1 + PLUS_ATTACKS_BELOW_HALF=2 ---")
	var loader = preload("res://autoloads/FactionStratagemLoader.gd").new()
	var avenge_text = "until the end of the phase, add 1 to the attacks characteristic of melee weapons equipped by models in that unit. if your unit is below half-strength, until the end of the phase, add 2 to the attacks characteristic of those melee weapons instead."
	var avenge_effects = loader._map_effects(avenge_text)
	var saw_plus1 = false
	var saw_plus2_below = false
	for e in avenge_effects:
		if e.get("type", "") == _ep.PLUS_ATTACKS and int(e.get("value", 0)) == 1:
			saw_plus1 = true
		if e.get("type", "") == _ep.PLUS_ATTACKS_BELOW_HALF and int(e.get("value", 0)) == 2:
			saw_plus2_below = true
	if saw_plus1 and saw_plus2_below:
		print("[PASS] parser emitted both default +1 and below-half +2")
		passed += 1
	else:
		print("[FAIL] expected both PLUS_ATTACKS=1 and PLUS_ATTACKS_BELOW_HALF=2; got %s" % str(avenge_effects))
		failed += 1

	# --- Test 4: parser does NOT emit below-half variant when no clause ---
	print("\n--- Test 4: parser without below-half clause emits PLUS_ATTACKS only ---")
	var simple_text = "add 1 to the attacks characteristic of melee weapons equipped by models in that unit."
	var simple_effects = loader._map_effects(simple_text)
	var simple_has_variant = false
	var simple_has_default = false
	for e in simple_effects:
		if e.get("type", "") == _ep.PLUS_ATTACKS_BELOW_HALF:
			simple_has_variant = true
		if e.get("type", "") == _ep.PLUS_ATTACKS:
			simple_has_default = true
	if simple_has_default and not simple_has_variant:
		print("[PASS] simple text emits PLUS_ATTACKS only (no variant)")
		passed += 1
	else:
		print("[FAIL] simple_has_default=%s simple_has_variant=%s; got %s" % [str(simple_has_default), str(simple_has_variant), str(simple_effects)])
		failed += 1

	print("\n=== Results: %d passed, %d failed ===" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)


func _count_total_attacks(result: Dictionary) -> int:
	# Sum hit-roll dice raw counts. _resolve_melee_assignment emits a hit_roll
	# entry per assignment; the rolls_raw size = total attacks.
	var total = 0
	for d in result.get("dice", []):
		var ctx = d.get("context", "")
		if ctx == "hit_roll_melee":
			total += d.get("rolls_raw", []).size()
	return total


func _make_board(model_count: int) -> Dictionary:
	var attacker_models = []
	# Attacker model 0 within engagement of target; the rest are non-eligible
	# but contribute to total_models for below-half check.
	for i in range(model_count):
		var pos = Vector2(200, 200) if i == 0 else Vector2(2000, 2000)
		attacker_models.append({"id": "m%d" % (i + 1), "wounds": 1, "current_wounds": 1, "alive": true, "position": {"x": pos.x, "y": pos.y}, "base_mm": 32})

	var target_models = [
		{"id": "t1", "wounds": 5, "current_wounds": 5, "alive": true, "position": {"x": 200, "y": 252}, "base_mm": 32}
	]

	return {
		"units": {
			"U_AVENGE_TEST": {
				"id": "U_AVENGE_TEST",
				"owner": 1,
				"status": 2,
				"meta": {
					"name": "Avenge Tester",
					"keywords": ["INFANTRY"],
					"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 1, "objective_control": 1},
					"weapons": [{
						"id": "avenge_blade",
						"name": "Avenge test blade",
						"type": "Melee",
						"range": "Melee",
						"attacks": "1",
						"weapon_skill": "3",
						"strength": "5",
						"ap": "0",
						"damage": "1"
					}],
					"abilities": []
				},
				"models": attacker_models,
				"flags": {}
			},
			"U_AVENGE_VICTIM": {
				"id": "U_AVENGE_VICTIM",
				"owner": 2,
				"status": 2,
				"meta": {
					"name": "Avenge Victim",
					"keywords": ["INFANTRY"],
					"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 5, "objective_control": 0},
					"weapons": [],
					"abilities": []
				},
				"models": target_models,
				"flags": {}
			}
		},
		"meta": {"battle_round": 1, "active_player": 1}
	}
