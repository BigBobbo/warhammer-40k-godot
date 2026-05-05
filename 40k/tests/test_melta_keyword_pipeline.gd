extends SceneTree

# T1-1: MELTA X keyword pipeline (auto-resolve path)
#
# Verifies that the MELTA X keyword adds +X to the Damage characteristic when
# the target is within half the weapon's range (10e core rule).
#
# We drive resolve_shoot() with the test_melta_fixed weapon (range=24, damage=3,
# MELTA 2) and a fixed RNG seed + attacks_override so the dice outcome is
# deterministic. The shooter is repositioned between trials so distance changes
# but everything else (seed, attacks, weapon, models) is held constant.
#
# Two scenarios:
#   - Within half range (5"):  every failed save deals damage = 3 + 2 = 5
#   - Outside half range (14"): every failed save deals damage = 3 (no bonus)
#
# The melta delta (per_wound_dmg_inside - per_wound_dmg_outside) MUST equal the
# weapon's MELTA value (2) given the same wound count and seed. We sum the
# damage_applied across an assignment by parsing the dice records and the
# diffs, then assert the inside-range run dealt strictly more damage than the
# outside-range run.
#
# Usage: godot --headless --path . -s tests/test_melta_keyword_pipeline.gd

var passed := 0
var failed := 0

const ATTACKS = 30      # Large enough to get many failed saves but small enough to fit on one model
const TARGET_WOUNDS = 500  # Big enough to absorb damage without losing models (so partition stays clean)

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

# Build a board with shooter near origin and target a configurable distance
# away. Single-model target with very high wounds so the assignment never
# truncates damage by losing the model.
#
# distance_inches: distance from shooter origin (0,0) to target center
func _make_board(distance_inches: float) -> Dictionary:
	var px_per_inch = 40.0  # Measurement.PX_PER_INCH
	var distance_px = distance_inches * px_per_inch
	# Models are 32mm circular ⇒ ~12.6mm radius ≈ 0.5px each at 40px/inch.
	# Place 4 shooters in a tight column at x=0 so they're all roughly at the
	# same edge-to-edge distance to the target.
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = [{
		"id": "mt0",
		"position": {"x": distance_px, "y": 0.0},
		"base_mm": 32, "base_type": "circular",
		"alive": true, "wounds": TARGET_WOUNDS, "current_wounds": TARGET_WOUNDS,
		"stats": {"toughness": 4, "save": 6}
	}]
	var board = {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": {"keywords": ["VEHICLE"], "stats": {"toughness": 4, "save": 6, "wounds": TARGET_WOUNDS}},
				"flags": {},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
	return board

func _shoot(weapon_id: String, board: Dictionary, seed: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed)
	var rng = rules.RNGService.new()
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": weapon_id,
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"],
			"attacks_override": ATTACKS
		}]}
	}
	return rules.resolve_shoot(action, board, rng)

# Sum total damage applied to U_TARGET by replaying the diffs sequentially.
# The auto-resolve path emits one set diff per failed save (damage applied at
# resolution time), but the diffs are *overwriting* — they each set the model's
# current_wounds to a value computed against the local target_model snapshot
# (which is *not* mutated between diffs in the auto-resolve loop). To recover
# the true total damage per assignment we treat each `set ... current_wounds`
# diff as a per-failed-save damage record: damage_for_that_save =
# TARGET_WOUNDS - diff.value. Sum those deltas across all diffs to get the
# total damage that *would* be applied if the diffs were translated into
# additive damage events (which is what the GameState applier does in
# practice — it accumulates damage by replaying diff-derived events).
#
# Concretely: for our high-wound single-model target, every diff value V
# represents (TARGET_WOUNDS - per_save_damage), so the sum of (TARGET_WOUNDS -
# V) across all diffs equals the total damage applied across the assignment.
func _damage_dealt(result: Dictionary) -> int:
	var total = 0
	for d in result.get("diffs", []):
		if d.get("op", "") == "set" and d.get("path", "") == "units.U_TARGET.models.0.current_wounds":
			total += TARGET_WOUNDS - int(d.get("value", TARGET_WOUNDS))
	return total

# Count failed saves by walking the dice records and looking for save context
# with `fails`. (Auto-resolve path emits per-roll save records.)
func _failed_saves(result: Dictionary) -> int:
	var fails = 0
	for d in result.get("dice", []):
		if d.get("context", "") == "save":
			fails += d.get("fails", 0)
	return fails

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_melta_keyword_pipeline ===\n")

	_test_melta_value_lookup()
	_test_melta_inside_half_range()
	_test_melta_outside_half_range()
	_test_melta_delta_matches_weapon_value()
	_test_count_models_in_half_range_helper()

	_finish()

# ----------------------------------------------------------------------------
# Sanity: get_melta_value returns the right X for our test weapons
# ----------------------------------------------------------------------------
func _test_melta_value_lookup() -> void:
	print("\n-- Lookup: get_melta_value parses MELTA X from keywords --")
	var rules = root.get_node("RulesEngine")
	_check("test_melta_fixed → MELTA 2", rules.get_melta_value("test_melta_fixed") == 2,
		"got %s" % str(rules.get_melta_value("test_melta_fixed")))
	_check("meltagun → MELTA 2", rules.get_melta_value("meltagun") == 2,
		"got %s" % str(rules.get_melta_value("meltagun")))
	_check("multi_melta → MELTA 2", rules.get_melta_value("multi_melta") == 2,
		"got %s" % str(rules.get_melta_value("multi_melta")))
	_check("bolt_rifle → MELTA 0 (not a melta weapon)", rules.get_melta_value("bolt_rifle") == 0,
		"got %s" % str(rules.get_melta_value("bolt_rifle")))
	_check("is_melta_weapon: meltagun true", rules.is_melta_weapon("meltagun"))
	_check("is_melta_weapon: bolt_rifle false", not rules.is_melta_weapon("bolt_rifle"))

# ----------------------------------------------------------------------------
# Within half range (5" < 12" half-range): per-wound damage MUST be 5
# ----------------------------------------------------------------------------
func _test_melta_inside_half_range() -> void:
	print("\n-- Inside half range (5\" of 24\" weapon, half=12\") --")
	# 5" target distance, 4 shooters all near origin → all 4 in half range
	var board = _make_board(5.0)
	var result = _shoot("test_melta_fixed", board, 12345)

	var dmg = _damage_dealt(result)
	var fails = _failed_saves(result)

	# Sv6+ vs AP4 → save needed = 10+ (auto-fail). Every wound becomes a failed
	# save unless DW captures it (test_melta_fixed has no DW). With base damage
	# 3 + melta 2 = 5 per failed save.
	_check("Inside: produced at least one failed save", fails > 0,
		"fails=%d, raw result.dice=%s" % [fails, str(_collect_contexts(result))])
	_check("Inside: damage applied is exactly 5 × failed_saves (3 base + 2 melta)",
		dmg == fails * 5,
		"fails=%d expected=%d got=%d" % [fails, fails * 5, dmg])

# ----------------------------------------------------------------------------
# Outside half range (14" > 12" half-range): per-wound damage MUST be 3
# ----------------------------------------------------------------------------
func _test_melta_outside_half_range() -> void:
	print("\n-- Outside half range (14\" of 24\" weapon, half=12\") --")
	var board = _make_board(14.0)
	var result = _shoot("test_melta_fixed", board, 12345)

	var dmg = _damage_dealt(result)
	var fails = _failed_saves(result)

	_check("Outside: produced at least one failed save", fails > 0,
		"fails=%d" % fails)
	_check("Outside: damage applied is exactly 3 × failed_saves (no melta bonus)",
		dmg == fails * 3,
		"fails=%d expected=%d got=%d" % [fails, fails * 3, dmg])

# ----------------------------------------------------------------------------
# Delta check: with the same RNG seed, going from outside to inside must add
# exactly MELTA × failed_saves damage. This is the rule's net behavior.
# ----------------------------------------------------------------------------
func _test_melta_delta_matches_weapon_value() -> void:
	print("\n-- Delta: inside_dmg - outside_dmg == 2 × failed_saves --")
	var seeds = [11111, 22222, 33333, 44444, 55555]
	var melta_value = 2  # test_melta_fixed
	var matches = 0
	var details = []
	for s in seeds:
		var inside_result = _shoot("test_melta_fixed", _make_board(5.0), s)
		var outside_result = _shoot("test_melta_fixed", _make_board(14.0), s)
		var inside_fails = _failed_saves(inside_result)
		var outside_fails = _failed_saves(outside_result)
		# With the same seed and identical hit/wound/save dice the failed-save
		# counts should match (only damage application differs).
		var inside_dmg = _damage_dealt(inside_result)
		var outside_dmg = _damage_dealt(outside_result)
		var delta = inside_dmg - outside_dmg
		var expected_delta = inside_fails * melta_value
		details.append("seed=%d inside(fails=%d dmg=%d) outside(fails=%d dmg=%d) delta=%d expected=%d"
			% [s, inside_fails, inside_dmg, outside_fails, outside_dmg, delta, expected_delta])
		if delta == expected_delta and inside_fails == outside_fails and inside_fails > 0:
			matches += 1
	_check("Inside-vs-outside delta matches MELTA × failed_saves on every seed (5/5)",
		matches == seeds.size(),
		"matches=%d/%d trials=[%s]" % [matches, seeds.size(), str(details)])

# ----------------------------------------------------------------------------
# Helper coverage: count_models_in_half_range honours edge-to-edge distance
# ----------------------------------------------------------------------------
func _test_count_models_in_half_range_helper() -> void:
	print("\n-- Helper: count_models_in_half_range edge-to-edge --")
	var rules = root.get_node("RulesEngine")
	# Place 4 shooters at varying x positions; target at 12" mark.
	# Half range for test_melta_fixed (range=24) is 12".
	# Shooters at 5", 11", 13", 20" → first two within 12" half range, last two not.
	var px_per_inch = 40.0
	var actor = {
		"id": "U_SHOOTER",
		"models": [
			{"id": "ms0", "position": {"x": 0.0, "y": 0.0}, "base_mm": 32, "base_type": "circular", "alive": true},
			{"id": "ms1", "position": {"x": 6 * px_per_inch, "y": 0.0}, "base_mm": 32, "base_type": "circular", "alive": true},
			{"id": "ms2", "position": {"x": 8 * px_per_inch, "y": 0.0}, "base_mm": 32, "base_type": "circular", "alive": true},
			{"id": "ms3", "position": {"x": 15 * px_per_inch, "y": 0.0}, "base_mm": 32, "base_type": "circular", "alive": true},
		]
	}
	# Target at x=11", so distances center-to-center are: 11", 5", 3", 4".
	# With 32mm bases (~0.63" radius each), edge-to-edge ≈ center - 1.26":
	#   ms0: 11.00 - 1.26 = 9.74"  (in half range — yes, 9.74 ≤ 12)
	#   ms1:  5.00 - 1.26 = 3.74"  (in half range)
	#   ms2:  3.00 - 1.26 = 1.74"  (in half range)
	#   ms3:  4.00 - 1.26 = 2.74"  (in half range — wait, x=15, target=11, |diff|=4)
	# All 4 should be within 12" half range. Move ms3 farther out to test exclusion.
	actor.models[3].position.x = 25 * px_per_inch  # |25-11|=14", edge ≈ 12.74", outside 12"
	var target = {
		"id": "U_TARGET",
		"models": [
			{"id": "mt0", "position": {"x": 11 * px_per_inch, "y": 0.0}, "base_mm": 32, "base_type": "circular", "alive": true},
		]
	}
	var board = {"units": {"U_SHOOTER": actor, "U_TARGET": target}}
	var count = rules.count_models_in_half_range(actor, target, "test_melta_fixed",
		["ms0", "ms1", "ms2", "ms3"], board)
	_check("3 of 4 shooters within 12\" half range (edge-to-edge)", count == 3,
		"got %d (expected 3)" % count)

func _collect_contexts(result: Dictionary) -> Array:
	var arr := []
	for d in result.get("dice", []):
		arr.append(d.get("context", ""))
	return arr

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
