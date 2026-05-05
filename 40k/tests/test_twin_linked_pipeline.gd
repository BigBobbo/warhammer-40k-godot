extends SceneTree

# T1-2: TWIN-LINKED keyword pipeline
#
# Verifies the wound-rolling pipeline correctly detects the TWIN-LINKED weapon
# keyword, sets WoundModifier.REROLL_FAILED on the assignment, re-rolls every
# wound roll below the wound threshold exactly once, and surfaces the rerolls
# through the to_wound dice record so downstream UI / dice history can display
# them.
#
# This is the headless analogue to the GUT unit tests in
# tests/unit/test_twin_linked_keyword.gd. The unit tests cover
# apply_wound_modifiers in isolation; this regression test drives the full
# resolve_shoot pipeline so a regression that DROPS the twin-linked branch
# (e.g. a refactor that bypasses apply_wound_modifiers, or fails to OR
# REROLL_FAILED into wound_modifiers) surfaces here.
#
# Each weapon has BS3+ and S4 vs T4 → wounds on 4+. With attacks_override=60
# we expect ~10 critical hits and ~30 wound rolls below threshold (rolls
# 1/2/3) which each get re-rolled.
#
# Usage: godot --headless --path . -s tests/test_twin_linked_pipeline.gd

var passed := 0
var failed := 0

const ATTACKS = 60

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

# Build a board with shooter and target both at the origin (~1" apart) so we
# stay well in the 24" range of the test bolters. Single 8-model target unit
# with 1W each — wounds may kill models but the assignment continues.
func _make_board() -> Dictionary:
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(8):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
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
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
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

func _aggregate_dice(result: Dictionary, context: String) -> Dictionary:
	"""Find the first dice record with the given context."""
	for d in result.get("dice", []):
		if d.get("context", "") == context:
			return d
	return {}

func _collect_contexts(result: Dictionary) -> Array:
	var arr := []
	for d in result.get("dice", []):
		arr.append(d.get("context", ""))
	return arr

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_twin_linked_pipeline ===\n")

	_test_has_twin_linked_lookup()
	_test_twin_linked_bolter_dice_record()
	_test_twin_linked_rerolls_only_failed_wounds()
	_test_twin_linked_no_double_reroll()
	_test_twin_linked_statistically_improves_wound_rate()
	_test_assignment_flag_triggers_reroll()

	_finish()

# ----------------------------------------------------------------------------
# Sanity: has_twin_linked() identifies the test weapons correctly.
# ----------------------------------------------------------------------------
func _test_has_twin_linked_lookup() -> void:
	print("\n-- Lookup: has_twin_linked recognises TWIN-LINKED keyword --")
	var rules = root.get_node("RulesEngine")
	_check("twin_linked_bolter is twin-linked",
		rules.has_twin_linked("twin_linked_bolter"))
	_check("twin_linked_lethal is twin-linked",
		rules.has_twin_linked("twin_linked_lethal"))
	_check("twin_linked_devastating is twin-linked",
		rules.has_twin_linked("twin_linked_devastating"))
	_check("bolt_rifle is NOT twin-linked",
		not rules.has_twin_linked("bolt_rifle"))
	_check("lascannon is NOT twin-linked",
		not rules.has_twin_linked("lascannon"))

# ----------------------------------------------------------------------------
# T1-2: TWIN-LINKED — to_wound dice record exposes the keyword + reroll list.
# ----------------------------------------------------------------------------
func _test_twin_linked_bolter_dice_record() -> void:
	print("\n-- T1-2: TWIN-LINKED dice record contract --")
	var board = _make_board()
	var result = _shoot("twin_linked_bolter", board, 12345)

	var wound_dice = _aggregate_dice(result, "to_wound")
	_check("Twin-linked: to_wound dice record present",
		not wound_dice.is_empty(),
		"contexts=%s" % str(_collect_contexts(result)))
	_check("Twin-linked: wound record flagged twin_linked_weapon=true",
		wound_dice.get("twin_linked_weapon") == true,
		"got %s" % str(wound_dice.get("twin_linked_weapon")))
	_check("Twin-linked: wound_rerolls field present (Array)",
		typeof(wound_dice.get("wound_rerolls", null)) == TYPE_ARRAY,
		"got type=%s" % str(typeof(wound_dice.get("wound_rerolls"))))

	var rules = root.get_node("RulesEngine")
	# REROLL_FAILED must be set in the wound_modifiers_applied bitfield.
	var modifiers_applied = wound_dice.get("wound_modifiers_applied", 0)
	_check("Twin-linked: REROLL_FAILED bit set in wound_modifiers_applied",
		(int(modifiers_applied) & rules.WoundModifier.REROLL_FAILED) != 0,
		"got modifiers=%d (REROLL_FAILED=%d)" % [int(modifiers_applied), rules.WoundModifier.REROLL_FAILED])

# ----------------------------------------------------------------------------
# T1-2: TWIN-LINKED — only rolls below wound threshold are re-rolled.
# ----------------------------------------------------------------------------
func _test_twin_linked_rerolls_only_failed_wounds() -> void:
	print("\n-- T1-2: only rolls < wound threshold get re-rolled --")
	var rules = root.get_node("RulesEngine")
	var board = _make_board()
	# S4 vs T4 → wounds on 4+ ⇒ failures are 1/2/3.
	var wound_threshold = 4

	# Run a deterministic shot and verify every reroll record came from a
	# failed roll. Use multiple seeds to accumulate rerolls so the assertion
	# is meaningful even if any one seed produces few rerolls.
	var any_rerolls = false
	var all_originals_failed = true
	var details: Array = []
	for s in [12345, 22345, 32345, 42345, 52345]:
		var result = _shoot("twin_linked_bolter", _make_board(), s)
		var wound_dice = _aggregate_dice(result, "to_wound")
		var rerolls = wound_dice.get("wound_rerolls", [])
		for r in rerolls:
			any_rerolls = true
			var original = int(r.get("original", -1))
			details.append("seed=%d original=%d rerolled_to=%d" %
				[s, original, int(r.get("rerolled_to", -1))])
			if original >= wound_threshold:
				all_originals_failed = false
	_check("Twin-linked: produced at least one reroll across 5 seeds",
		any_rerolls,
		"no rerolls fired")
	_check("Twin-linked: every recorded reroll came from a failed wound roll (< 4)",
		all_originals_failed,
		"some originals were >= 4: %s" % str(details))

# ----------------------------------------------------------------------------
# T1-2: TWIN-LINKED — rerolls are not themselves re-rolled (cap at one).
#
# We don't have direct visibility into the engine to assert "no double reroll"
# at the rule-engine level (the engine only rolls once per failed wound), but
# we can sanity-check that the wound_rerolls list size never exceeds the
# total wound rolls performed, AND that rerolling-a-reroll cannot happen by
# inspecting apply_wound_modifiers directly.
# ----------------------------------------------------------------------------
func _test_twin_linked_no_double_reroll() -> void:
	print("\n-- T1-2: rerolls are capped at one per die --")
	var rules = root.get_node("RulesEngine")
	# Direct apply_wound_modifiers check: even with REROLL_FAILED set, calling
	# the function once produces exactly one reroll record. There is no path
	# in apply_wound_modifiers that re-rolls a re-roll.
	var rng = rules.RNGService.new(99999)
	var modifiers = rules.WoundModifier.REROLL_FAILED
	var result_one = rules.apply_wound_modifiers(2, modifiers, 4, rng)
	_check("apply_wound_modifiers: single failed roll produces single reroll",
		result_one.rerolled == true,
		"rerolled=%s" % str(result_one.rerolled))
	# Even if the rerolled value is itself a fail (1/2/3), the function does
	# NOT recurse — modified_roll == reroll_value, no further reroll.
	# We can verify by seeding to a state where the reroll lands low.
	# Iterate a few seeds and ensure the result never has more than one reroll
	# step (i.e. there is no `second_reroll` field, and the structure is flat).
	var nested_field_found = false
	for s in [1, 7, 13, 31, 91]:
		var rng_s = rules.RNGService.new(s)
		var r = rules.apply_wound_modifiers(1, rules.WoundModifier.REROLL_FAILED, 4, rng_s)
		if r.has("second_reroll") or r.has("nested_reroll"):
			nested_field_found = true
			break
	_check("apply_wound_modifiers result has no second/nested reroll field",
		not nested_field_found)

	# Pipeline-level sanity: total rerolls ≤ total wound rolls.
	var board = _make_board()
	var pipeline_result = _shoot("twin_linked_bolter", board, 12345)
	var wound_dice = _aggregate_dice(pipeline_result, "to_wound")
	var rerolls = wound_dice.get("wound_rerolls", [])
	var raw_rolls = wound_dice.get("rolls_raw", [])
	_check("Twin-linked: rerolls count never exceeds wound rolls count",
		rerolls.size() <= raw_rolls.size(),
		"rerolls=%d rolls=%d" % [rerolls.size(), raw_rolls.size()])

# ----------------------------------------------------------------------------
# Statistical: Twin-linked produces strictly more wounds than a comparable
# non-twin-linked weapon profile over many trials.
#
# We compare twin_linked_bolter (TWIN-LINKED) vs bolt_rifle (no keyword) using
# the same RNG seed sequence. With wounds on 4+ (S4 vs T4), the expected wound
# rate goes from 0.5 to 0.75 with twin-linked. Across the trial pool we
# require strictly more wounds.
# ----------------------------------------------------------------------------
func _test_twin_linked_statistically_improves_wound_rate() -> void:
	print("\n-- T1-2: twin-linked statistically improves wound rate --")

	var rules = root.get_node("RulesEngine")

	# Direct apply_wound_modifiers comparison over many trials with matched
	# seed pools. This is more controlled than running the full pipeline.
	var trials = 1000
	var threshold = 4
	var normal_wounds = 0
	var twin_wounds = 0
	var rng_normal = rules.RNGService.new(12345)
	var rng_twin = rules.RNGService.new(12345)
	for i in range(trials):
		var roll_n = rng_normal.roll_d6(1)[0]
		var rn = rules.apply_wound_modifiers(roll_n, rules.WoundModifier.NONE, threshold, rng_normal)
		if rn.modified_roll >= threshold and roll_n != 1:
			normal_wounds += 1
		var roll_t = rng_twin.roll_d6(1)[0]
		var rt = rules.apply_wound_modifiers(roll_t, rules.WoundModifier.REROLL_FAILED, threshold, rng_twin)
		var unmod = roll_t if not rt.rerolled else rt.reroll_value
		if rt.modified_roll >= threshold and unmod != 1:
			twin_wounds += 1
	_check("Twin-linked produces strictly more wounds than no-keyword over 1000 trials",
		twin_wounds > normal_wounds,
		"normal=%d twin=%d" % [normal_wounds, twin_wounds])
	# Sanity: the gap should be substantial (~50% improvement at 4+).
	# We require at least 20% lift to guard against single-die noise.
	var lift_ok = twin_wounds >= normal_wounds + (normal_wounds * 20 / 100)
	_check("Twin-linked lift over baseline ≥ 20% (~50% expected)",
		lift_ok,
		"normal=%d twin=%d lift=%d%%" % [normal_wounds, twin_wounds,
			0 if normal_wounds == 0 else (twin_wounds - normal_wounds) * 100 / normal_wounds])

# ----------------------------------------------------------------------------
# Per-assignment opt-in: assignment.twin_linked = true forces twin-linked even
# on a weapon that doesn't carry the keyword. This path is used by ranged
# weapons that gain twin-linked via stratagem / ability.
# ----------------------------------------------------------------------------
func _test_assignment_flag_triggers_reroll() -> void:
	print("\n-- T1-2: assignment.twin_linked flag enables re-roll on plain weapon --")
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(54321)
	var rng = rules.RNGService.new()
	var board = _make_board()
	# bolt_rifle has NO twin-linked keyword. Set assignment-level flag.
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "bolt_rifle",
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"],
			"attacks_override": ATTACKS,
			"twin_linked": true
		}]}
	}
	var result = rules.resolve_shoot(action, board, rng)
	var wound_dice = _aggregate_dice(result, "to_wound")
	_check("Assignment-flag twin-linked: dice record flags twin_linked_weapon=true",
		wound_dice.get("twin_linked_weapon") == true,
		"got %s" % str(wound_dice.get("twin_linked_weapon")))
	_check("Assignment-flag twin-linked: REROLL_FAILED bit set in wound_modifiers_applied",
		(int(wound_dice.get("wound_modifiers_applied", 0)) & rules.WoundModifier.REROLL_FAILED) != 0,
		"modifiers=%d" % int(wound_dice.get("wound_modifiers_applied", 0)))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
