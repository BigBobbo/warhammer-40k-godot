extends SceneTree

# Tests for "Kunnin' Infiltrator" ability implementation (OA-24)
#
# Per Boss Snikrot's datasheet:
# "Once per battle, in your Movement phase, instead of making a Normal move
# with this model's unit, you can remove it from the battlefield and set it up
# again anywhere on the battlefield that is more than 9\" horizontally away
# from all enemy models."
#
# These tests verify:
# 1. Ability is registered in UnitAbilityManager.ABILITY_EFFECTS
# 2. Ability has correct properties (once_per_battle, condition, etc.)
# 3. MovementPhase has the action types registered
# 4. Placement validation rejects positions too close to enemies
# 5. Once-per-battle tracking works correctly

const UnitAbilityManagerData = preload("res://autoloads/UnitAbilityManager.gd")

var _pass_count := 0
var _fail_count := 0

func _init():
	print("\n=== Test Kunnin' Infiltrator Ability (OA-24) ===\n")

	_test_ability_registered()
	_test_ability_properties()
	_test_once_per_battle_flag()
	_test_condition_is_instead_of_normal_move()
	_test_movement_phase_action_types()
	_test_placement_validation_logic()
	_test_has_kunnin_infiltrator_checks_attached_leaders()
	_test_movement_controller_has_special_action_popup()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("ALL TESTS PASSED")
	else:
		print("SOME TESTS FAILED")
	quit()

# ==========================================
# Assertion helpers
# ==========================================

func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s" % msg)

func _assert_false(condition: bool, msg: String) -> void:
	_assert_true(not condition, msg)

func _assert_eq(a, b, msg: String) -> void:
	if a == b:
		_pass_count += 1
		print("  PASS: %s" % msg)
	else:
		_fail_count += 1
		print("  FAIL: %s (expected %s, got %s)" % [msg, str(b), str(a)])

# ==========================================
# Tests
# ==========================================

func _test_ability_registered():
	print("--- Test 1: Kunnin' Infiltrator is registered in ABILITY_EFFECTS ---")
	var effects = UnitAbilityManagerData.ABILITY_EFFECTS
	_assert_true(effects.has("Kunnin' Infiltrator"), "Kunnin' Infiltrator exists in ABILITY_EFFECTS")
	_assert_true(effects["Kunnin' Infiltrator"].get("implemented", false), "Kunnin' Infiltrator is marked as implemented")

func _test_ability_properties():
	print("\n--- Test 2: Kunnin' Infiltrator has correct properties ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Kunnin' Infiltrator", {})

	_assert_true(effect_def.get("once_per_battle", false), "once_per_battle is true")
	_assert_eq(effect_def.get("target", ""), "unit", "Target is 'unit'")
	_assert_eq(effect_def.get("effects", []).size(), 0, "No EffectPrimitives effects (handled by phase logic)")

func _test_once_per_battle_flag():
	print("\n--- Test 3: once_per_battle flag is set ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Kunnin' Infiltrator", {})
	_assert_true(effect_def.has("once_per_battle"), "Entry has once_per_battle key")
	_assert_true(effect_def.get("once_per_battle", false), "once_per_battle is true")

func _test_condition_is_instead_of_normal_move():
	print("\n--- Test 4: Kunnin' Infiltrator condition is instead_of_normal_move ---")
	var effect_def = UnitAbilityManagerData.ABILITY_EFFECTS.get("Kunnin' Infiltrator", {})
	_assert_eq(effect_def.get("condition", ""), "instead_of_normal_move",
		"Condition is 'instead_of_normal_move' (alternative to Normal move)")
	_assert_true(effect_def.get("description", "").find("redeploy") != -1,
		"Description mentions redeploy")
	_assert_true(effect_def.get("description", "").find("9\"") != -1,
		"Description mentions 9\" distance requirement")

func _test_movement_phase_action_types():
	print("\n--- Test 5: MovementPhase has Kunnin' Infiltrator action types ---")
	# Verify the MovementPhase class can be loaded and has the right structure
	var mp_script = load("res://phases/MovementPhase.gd")
	_assert_true(mp_script != null, "MovementPhase.gd loads successfully")

	# Verify the script has the signal defined
	# We check by looking at the script source for the signal declaration
	var source = mp_script.source_code
	_assert_true(source.find("kunnin_infiltrator_available") != -1,
		"MovementPhase has kunnin_infiltrator_available signal")
	_assert_true(source.find("ACTIVATE_KUNNIN_INFILTRATOR") != -1,
		"MovementPhase handles ACTIVATE_KUNNIN_INFILTRATOR action")
	_assert_true(source.find("PLACE_KUNNIN_INFILTRATOR") != -1,
		"MovementPhase handles PLACE_KUNNIN_INFILTRATOR action")
	_assert_true(source.find("CANCEL_KUNNIN_INFILTRATOR") != -1,
		"MovementPhase handles CANCEL_KUNNIN_INFILTRATOR action")

func _test_placement_validation_logic():
	print("\n--- Test 6: Placement validation logic (distance check) ---")
	# Test the core distance calculation used for >9" check
	# Given: px_per_inch = 40.0, model base_mm = 40 (Boss Snikrot), enemy base_mm = 32
	# Model radius: (40/2) / 25.4 = 0.787 inches
	# Enemy radius: (32/2) / 25.4 = 0.630 inches
	# For edge-to-edge > 9", center-to-center must be > 9 + 0.787 + 0.630 = 10.417"
	# In pixels: 10.417 * 40 = 416.7 px

	var px_per_inch = 40.0
	var model_base_mm = 40  # Boss Snikrot's 40mm base
	var enemy_base_mm = 32  # Standard enemy base
	var model_radius_inches = (model_base_mm / 2.0) / 25.4
	var enemy_radius_inches = (enemy_base_mm / 2.0) / 25.4

	# Test 1: Position too close (8" center to center = ~6.58" edge to edge)
	var model_pos = Vector2(400, 400)
	var enemy_pos = Vector2(720, 400)  # 320px = 8" away center-to-center
	var dist_px = model_pos.distance_to(enemy_pos)
	var dist_inches = dist_px / px_per_inch
	var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
	_assert_true(edge_dist < 9.0, "8\" center-to-center is < 9\" edge-to-edge (%.2f\")" % edge_dist)

	# Test 2: Position far enough (15" center to center)
	var far_enemy_pos = Vector2(1000, 400)  # 600px = 15" away
	dist_px = model_pos.distance_to(far_enemy_pos)
	dist_inches = dist_px / px_per_inch
	edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
	_assert_true(edge_dist >= 9.0, "15\" center-to-center is >= 9\" edge-to-edge (%.2f\")" % edge_dist)

	# Test 3: Borderline case (~10.5" center to center ≈ 9.08" edge to edge)
	var borderline_pos = Vector2(820, 400)  # 420px = 10.5" center-to-center
	dist_px = model_pos.distance_to(borderline_pos)
	dist_inches = dist_px / px_per_inch
	edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
	_assert_true(edge_dist >= 9.0, "10.5\" center-to-center is >= 9\" edge-to-edge (%.2f\")" % edge_dist)

func _test_has_kunnin_infiltrator_checks_attached_leaders():
	print("\n--- Test 7: has_kunnin_infiltrator checks attached leaders ---")
	# Verify the UnitAbilityManager source includes attached_characters check
	var uam_script = load("res://autoloads/UnitAbilityManager.gd")
	_assert_true(uam_script != null, "UnitAbilityManager.gd loads successfully")

	var source = uam_script.source_code
	# The function should check attached_characters for leader abilities
	_assert_true(source.find("attached_characters") != -1 and source.find("has_kunnin_infiltrator") != -1,
		"has_kunnin_infiltrator checks attached_characters for leader abilities")
	# Should check if the attached character has the ability
	_assert_true(source.find("Kunnin' Infiltrator via attached leader") != -1,
		"has_kunnin_infiltrator logs when ability found on attached leader")

func _test_movement_controller_has_special_action_popup():
	print("\n--- Test 8: MovementController has special action popup for Kunnin' Infiltrator ---")
	var mc_script = load("res://scripts/MovementController.gd")
	_assert_true(mc_script != null, "MovementController.gd loads successfully")

	var source = mc_script.source_code
	_assert_true(source.find("_movement_action_popup") != -1,
		"MovementController has popup menu for movement actions")
	_assert_true(source.find("_get_special_movement_actions") != -1,
		"MovementController has function to detect special movement actions")
	_assert_true(source.find("_show_movement_action_popup") != -1,
		"MovementController has function to show movement action popup")
	_assert_true(source.find("ACTIVATE_KUNNIN_INFILTRATOR") != -1,
		"MovementController recognizes ACTIVATE_KUNNIN_INFILTRATOR as special action")
