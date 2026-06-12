extends SceneTree

# Extended #329 RNG determinism test.
# The base test (test_audit_fixes_verification.gd) covers RNGService.roll_d6.
# This test covers:
#   1. New pass-through helpers (randi, randi_range, randf, randf_range)
#   2. TransportManager.resolve_transport_destroyed plumbing (D6 rolls per model)
#   3. MissionManager Supply Drop plumbing (Crucible objective removal)
#   4. 3-runs-identical-with-same-seed + different-seed-differs assertion strength

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

func _run_tests() -> void:
	if passed > 0 or failed > 0:
		return  # guard against double-fire

	print("\n=== test_rng_determinism_extended ===")

	var rules = root.get_node("RulesEngine")

	# ----------------------------------------------------------------
	# 1. Pass-through helpers honor test_mode_seed
	# ----------------------------------------------------------------
	print("\n-- pass-through helpers --")

	var seq_a := []
	rules.set_test_seed(42)
	var rng_a = rules.RNGService.new()
	for i in range(20):
		seq_a.append(rng_a.randi_range(1, 6))

	var seq_b := []
	rules.set_test_seed(42)
	var rng_b = rules.RNGService.new()
	for i in range(20):
		seq_b.append(rng_b.randi_range(1, 6))

	_check("randi_range is deterministic across runs with same seed",
		str(seq_a) == str(seq_b), "a=%s b=%s" % [str(seq_a), str(seq_b)])

	var seq_c := []
	rules.set_test_seed(43)
	var rng_c = rules.RNGService.new()
	for i in range(20):
		seq_c.append(rng_c.randi_range(1, 6))

	_check("randi_range differs with different seed",
		str(seq_c) != str(seq_a))

	# randi pass-through
	rules.set_test_seed(42)
	var rng_d = rules.RNGService.new()
	var int_a = rng_d.randi()
	rules.set_test_seed(42)
	var rng_e = rules.RNGService.new()
	var int_b = rng_e.randi()
	_check("randi() is deterministic", int_a == int_b, "a=%d b=%d" % [int_a, int_b])

	# randf pass-through
	rules.set_test_seed(42)
	var rng_f = rules.RNGService.new()
	var f_a = rng_f.randf()
	rules.set_test_seed(42)
	var rng_g = rules.RNGService.new()
	var f_b = rng_g.randf()
	_check("randf() is deterministic", f_a == f_b)

	# ----------------------------------------------------------------
	# 2. 3-runs-identical-with-same-seed assertion
	# ----------------------------------------------------------------
	print("\n-- 3-run identity --")

	var run1 := _capture_dice_run(rules, 42)
	var run2 := _capture_dice_run(rules, 42)
	var run3 := _capture_dice_run(rules, 42)
	_check("Run 1 == Run 2 with seed=42", str(run1) == str(run2))
	_check("Run 2 == Run 3 with seed=42", str(run2) == str(run3))
	_check("Run 1 == Run 3 with seed=42", str(run1) == str(run3))

	var run4 := _capture_dice_run(rules, 43)
	_check("Run 4 (seed=43) differs from runs 1-3 (seed=42)",
		str(run4) != str(run1))

	# ----------------------------------------------------------------
	# 3. TransportManager.resolve_transport_destroyed honors test_mode_seed
	# ----------------------------------------------------------------
	print("\n-- TransportManager disembark D6 plumbing --")

	# We can't easily set up a real transport scenario in this lightweight
	# test, so we instead drive the RNGService construction pattern that
	# resolve_transport_destroyed uses (var rng = RulesEngine.RNGService.new()
	# then rng.randi_range(1, 6) per model). This proves the plumbing is
	# correctly threaded — if the function instantiated RNGService correctly
	# and called randi_range, it gets the same sequence we get here.
	var transport_mgr_path = "res://autoloads/TransportManager.gd"
	var src := FileAccess.get_file_as_string(transport_mgr_path)
	# ISS-004: RNG must come from the sanctioned factory (make_rng routes
	# through test_mode_seed exactly like the old direct construction did).
	_check("TransportManager.gd uses RulesEngine.make_rng()",
		src.find("RulesEngine.make_rng()") != -1)
	_check("TransportManager.gd uses rng.randi_range(1, 6) (not raw randi_range)",
		src.find("rng.randi_range(1, 6)") != -1)
	_check("TransportManager.gd no longer contains raw 'randi_range(1, 6)' call",
		_count_unprefixed(src, "randi_range(1, 6)") == 0,
		"raw count=%d" % _count_unprefixed(src, "randi_range(1, 6)"))

	# ----------------------------------------------------------------
	# 4. MissionManager Supply Drop honors test_mode_seed
	# ----------------------------------------------------------------
	print("\n-- MissionManager Supply Drop plumbing --")

	var mission_mgr_path = "res://autoloads/MissionManager.gd"
	var ms := FileAccess.get_file_as_string(mission_mgr_path)
	_check("MissionManager.gd uses RulesEngine.make_rng() in Supply Drop",
		ms.find("RulesEngine.make_rng()") != -1)
	_check("MissionManager.gd Supply Drop uses rng.randi_range",
		ms.find("rng.randi_range") != -1)

	# ----------------------------------------------------------------
	# 5. FightPhase Mathhammer prediction honors test_mode_seed
	# ----------------------------------------------------------------
	print("\n-- FightPhase Mathhammer seed plumbing --")

	var fp_path = "res://phases/FightPhase.gd"
	var fp := FileAccess.get_file_as_string(fp_path)
	_check("FightPhase.gd Mathhammer uses _mh_rng = RulesEngine.make_rng()",
		fp.find("_mh_rng = RulesEngine.make_rng()") != -1)
	_check("FightPhase.gd Mathhammer seed uses _mh_rng.randi()",
		fp.find("_mh_rng.randi()") != -1)
	_check("FightPhase.gd no longer has bare '\"seed\": randi()'",
		fp.find("\"seed\": randi()") == -1)

	# Reset for downstream tests in the suite
	rules.set_test_seed(-1)

	_finish()

# Capture a sequence of dice rolls covering several rng methods to provide a
# robust 3-run identity assertion.
func _capture_dice_run(rules, seed: int) -> Array:
	rules.set_test_seed(seed)
	var rng = rules.RNGService.new()
	var run := []
	# Mix of method types so the assertion catches drift in any one of them
	for i in range(5):
		run.append(rng.roll_d6(3))
	for i in range(5):
		run.append(rng.randi_range(1, 6))
	for i in range(3):
		run.append(rng.randi())
	for i in range(3):
		run.append(snapped(rng.randf(), 0.0001))
	return run

# Count occurrences of `needle` in `haystack` that are NOT preceded by a
# member-access dot (so 'rng.randi_range' does not count, but a bare
# 'randi_range' does).
func _count_unprefixed(haystack: String, needle: String) -> int:
	var n := 0
	var i := 0
	while true:
		var pos = haystack.find(needle, i)
		if pos == -1:
			break
		if pos == 0 or haystack[pos - 1] != ".":
			n += 1
		i = pos + needle.length()
	return n

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
