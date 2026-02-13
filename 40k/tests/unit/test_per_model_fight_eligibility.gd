extends "res://addons/gut/test.gd"

# Tests for per-model fight eligibility (10e rules, audit item 2.1)
#
# Per 10e rules: A model can make melee attacks if, after pile-in, it is:
# 1. Within Engagement Range (1") of any enemy model, OR
# 2. In base-to-base contact with a friendly model that is itself in
#    base-to-base contact with an enemy model.
#
# Position math for 32mm circular bases:
#   base_radius_px ≈ 25.2 px  (32mm / 25.4 * 40 / 2)
#   Two models touching: center distance ≈ 50.4 px (edge-to-edge ≈ 0")
#   1" edge gap: center distance ≈ 90.4 px

var rules_engine: Node

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	rules_engine = AutoloadHelper.get_rules_engine()
	assert_not_null(rules_engine, "RulesEngine autoload must be available")

# ==========================================
# Helper: Build a board with positioned models
# ==========================================

func _make_model(pos_x: float, pos_y: float, alive: bool = true) -> Dictionary:
	return {
		"alive": alive,
		"current_wounds": 1,
		"wounds": 1,
		"base_mm": 32,
		"base_type": "circular",
		"position": {"x": pos_x, "y": pos_y}
	}

func _make_unit(owner: int, models: Array, weapons: Array = []) -> Dictionary:
	if weapons.is_empty():
		weapons = [{
			"name": "Chainsword",
			"type": "Melee",
			"range": "Melee",
			"attacks": "3",
			"weapon_skill": "3",
			"strength": "4",
			"ap": "0",
			"damage": "1",
			"special_rules": ""
		}]
	return {
		"owner": owner,
		"models": models,
		"meta": {
			"name": "Test Unit (owner %d)" % owner,
			"stats": {
				"toughness": 4,
				"save": 3,
				"wounds": 1
			},
			"weapons": weapons,
			"keywords": ["INFANTRY"]
		}
	}

func _make_action(weapon_id: String = "chainsword", attacker_id: String = "attacker", target_id: String = "enemy") -> Dictionary:
	return {
		"actor_unit_id": attacker_id,
		"payload": {
			"assignments": [{
				"attacker": attacker_id,
				"target": target_id,
				"weapon": weapon_id
			}]
		}
	}

# ==========================================
# Test: All models in engagement range
# ==========================================

func test_all_models_in_er_are_eligible():
	"""All models within 1\" of an enemy should be eligible"""
	# Enemy at (200, 200), all attackers within 1" (close together)
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # ~0" edge-to-edge (overlapping/touching)
				_make_model(260, 200),  # ~0.25" edge-to-edge
				_make_model(270, 200),  # ~0.49" edge-to-edge
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 3, "All 3 models should be eligible (all in ER)")
	assert_has(result, 0, "Model 0 should be eligible")
	assert_has(result, 1, "Model 1 should be eligible")
	assert_has(result, 2, "Model 2 should be eligible")

# ==========================================
# Test: Only models in ER are eligible (no chain)
# ==========================================

func test_only_models_in_er_eligible_no_chain():
	"""Models outside ER with no base-contact chain should not be eligible"""
	# Enemy at (200, 200)
	# Model 0 at (250, 200) - in ER (~0" edge-to-edge)
	# Model 1 at (400, 200) - far away (~3.7" edge-to-edge), no chain
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # In ER
				_make_model(400, 200),  # Far away, not in ER
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 1, "Only 1 model should be eligible")
	assert_has(result, 0, "Model 0 should be eligible (in ER)")
	assert_does_not_have(result, 1, "Model 1 should NOT be eligible (out of ER, no chain)")

# ==========================================
# Test: Model eligible via base-contact chain
# ==========================================

func test_model_eligible_via_base_contact_chain():
	"""Model in base contact with friendly that is in base contact with enemy should be eligible"""
	# Enemy at (200, 200)
	# Model A at (250, 200) - touching enemy (base contact ✓, ~0" edge-to-edge)
	# Model B at (300, 200) - touching Model A (base contact ✓), 1.24" from enemy (NOT in ER)
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # Base contact with enemy
				_make_model(300, 200),  # Base contact with Model A, NOT in ER of enemy
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 2, "Both models should be eligible")
	assert_has(result, 0, "Model 0 eligible via direct ER")
	assert_has(result, 1, "Model 1 eligible via base-contact chain")

# ==========================================
# Test: Chain requires base contact with enemy, NOT just ER (the key bug fix)
# ==========================================

func test_chain_requires_base_contact_with_enemy_not_just_er():
	"""Chain model must be in base-to-base contact with enemy, not merely within ER"""
	# Enemy at (200, 200)
	# Model A at (282, 200) - in ER (~0.79") but NOT in base contact (>0.25")
	# Model B at (332, 200) - in base contact with A (~0" edge-to-edge), NOT in ER of enemy (~2.04")
	#
	# Under correct rules: Model A eligible (criterion 1), Model B NOT eligible
	# (Model A is not in base contact with enemy, so chain doesn't apply)
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(282, 200),  # In ER but NOT base contact with enemy
				_make_model(332, 200),  # Base contact with Model A, but A not in btb with enemy
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 1, "Only Model A should be eligible")
	assert_has(result, 0, "Model 0 should be eligible (in ER)")
	assert_does_not_have(result, 1, "Model 1 should NOT be eligible (chain requires btb with enemy)")

# ==========================================
# Test: Dead models are excluded
# ==========================================

func test_dead_models_excluded():
	"""Dead models should not be eligible regardless of position"""
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200, true),   # Alive, in ER
				_make_model(260, 200, false),  # Dead, in ER position
				_make_model(270, 200, true),   # Alive, in ER
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 2, "Only 2 alive models should be eligible")
	assert_has(result, 0, "Model 0 should be eligible (alive, in ER)")
	assert_does_not_have(result, 1, "Model 1 should NOT be eligible (dead)")
	assert_has(result, 2, "Model 2 should be eligible (alive, in ER)")

# ==========================================
# Test: No models in ER → empty result
# ==========================================

func test_no_models_in_er_returns_empty():
	"""If no models are in ER, no models should be eligible"""
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(400, 200),  # ~3.7" from enemy
				_make_model(450, 200),  # ~5" from enemy
			]),
			"enemy": _make_unit(2, [
				_make_model(200, 200)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 0, "No models should be eligible (none in ER)")

# ==========================================
# Test: Multiple enemy units considered
# ==========================================

func test_eligibility_checks_all_enemy_units():
	"""Models should be eligible if in ER of ANY enemy unit, not just the first"""
	# Model 0 near enemy_a, Model 1 near enemy_b, Model 2 far from both
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # Near enemy_a
				_make_model(250, 400),  # Near enemy_b
				_make_model(500, 500),  # Far from both
			]),
			"enemy_a": _make_unit(2, [
				_make_model(200, 200)
			]),
			"enemy_b": _make_unit(2, [
				_make_model(200, 400)
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 2, "2 models should be eligible")
	assert_has(result, 0, "Model 0 eligible (near enemy_a)")
	assert_has(result, 1, "Model 1 eligible (near enemy_b)")
	assert_does_not_have(result, 2, "Model 2 not eligible (far from both)")

# ==========================================
# Test: Friendly units are skipped
# ==========================================

func test_friendly_units_not_considered_for_er():
	"""Being near a friendly unit should not make a model eligible"""
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # Near friendly_unit, far from enemy
			]),
			"friendly_unit": _make_unit(1, [
				_make_model(200, 200)   # Same owner, close by
			]),
			"enemy": _make_unit(2, [
				_make_model(500, 500)   # Far away
			])
		}
	}

	var attacker = board.units.attacker
	var result = rules_engine.get_eligible_melee_model_indices(attacker, board)

	assert_eq(result.size(), 0, "No models should be eligible (friendly units don't count)")

# ==========================================
# Integration: resolve_melee_attacks respects eligibility
# ==========================================

func test_resolve_melee_only_counts_eligible_model_attacks():
	"""Only models in ER should contribute attacks to melee resolution"""
	# 3 attacker models, each with 3 attacks, but only 1 in ER
	# Expected: 3 attacks (not 9)
	var weapons = [{
		"name": "Chainsword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "3",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": ""
	}]
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # In ER (~0" from enemy)
				_make_model(400, 200),  # Far away (~3.7")
				_make_model(450, 200),  # Far away (~5")
			], weapons),
			"enemy": _make_unit(2, [
				_make_model(200, 200),
				_make_model(210, 200),
				_make_model(220, 200),
				_make_model(230, 200),
				_make_model(240, 200),
			])
		}
	}

	var action = _make_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.total_attacks, 3, "Only 1 eligible model * 3 attacks = 3 total (not 9)")

func test_resolve_melee_chain_eligible_model_contributes_attacks():
	"""Model eligible via base-contact chain should contribute attacks"""
	var weapons = [{
		"name": "Chainsword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "2",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": ""
	}]
	# Model 0 in base contact with enemy, Model 1 in base contact with Model 0
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(250, 200),  # Base contact with enemy
				_make_model(300, 200),  # Base contact with Model 0, not in ER of enemy
			], weapons),
			"enemy": _make_unit(2, [
				_make_model(200, 200),
				_make_model(210, 200),
				_make_model(220, 200),
			])
		}
	}

	var action = _make_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	assert_true(result.success, "Resolution should succeed")
	var hit_dice = result.dice[0]
	assert_eq(hit_dice.total_attacks, 4, "2 eligible models * 2 attacks = 4 total")

func test_resolve_melee_zero_eligible_fails_gracefully():
	"""If no models are eligible, resolution should handle it gracefully"""
	var weapons = [{
		"name": "Chainsword",
		"type": "Melee",
		"range": "Melee",
		"attacks": "3",
		"weapon_skill": "3",
		"strength": "4",
		"ap": "0",
		"damage": "1",
		"special_rules": ""
	}]
	var board = {
		"units": {
			"attacker": _make_unit(1, [
				_make_model(400, 200),  # Far from enemy
				_make_model(450, 200),  # Far from enemy
			], weapons),
			"enemy": _make_unit(2, [
				_make_model(200, 200),
			])
		}
	}

	var action = _make_action("chainsword")
	var result = rules_engine.resolve_melee_attacks(action, board)

	# With 0 eligible models, total attacks = 0, should return early with log
	assert_true(result.has("log_text"), "Should have log text")
	assert_string_contains(result.log_text, "0", "Log should mention 0 eligible models")
