extends SceneTree

# 06_SYNTHESIS launch-blocker #3 / NEW-S2 / issue #371: Indirect Fire
# penalties (-1 to hit, unmodified 1-3 always fail, target gains cover)
# only apply when the target is NOT visible to any model in the firing
# unit. Per Wahapedia 10e RAW.
#
# Pre-#371 the engine applied the penalties unconditionally. Fix gates
# all three on `_has_los_to_target_unit` returning false.
#
# This pin verifies the gate is in place at all three call sites:
#   A) -1 to hit modifier (line ~1613)
#   B) Unmodified 1-3 always fail (line ~1691)
#   C) Target gains Benefit of Cover (line ~3076 in auto-resolve;
#      similar in the manual-resolve path).
#
# Usage: godot --headless --path . -s tests/test_t003_indirect_fire_visibility_pin.gd

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

func _read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_t003_indirect_fire_visibility_pin ===\n")
	_test_hit_minus_one_gated()
	_test_one_three_fail_gated()
	_test_cover_gated()
	_test_helpers_exist()
	_finish()

func _test_hit_minus_one_gated() -> void:
	print("\n-- A: -1 to hit gated on `not visible` --")
	var src = _read("res://autoloads/RulesEngine.gd")
	_check("RulesEngine.gd readable", not src.is_empty())
	# The -1 must be inside a `not indirect_target_visible` branch.
	_check("indirect_target_visible computed via _has_los_to_target_unit",
		"_has_los_to_target_unit(actor_unit_id, target_unit_id, board)" in src
			and "indirect_target_visible" in src)
	_check("-1 hit only when target NOT visible",
		"if is_indirect_fire and not indirect_target_visible:" in src,
		"would apply -1 even when target is visible (silent rule break)")

func _test_one_three_fail_gated() -> void:
	print("\n-- B: unmodified fail band gated on `not visible` --")
	# ba768da refactored the inline `unmodified_roll <= 3` check into the
	# hit_fail_band parameter of AttackSequence.evaluate_hit_roll: band 3 at
	# 10e, _indirect_hit_fail_band_11e (5, or 3 with stationary+spotter) at 11e
	# — still selected ONLY inside the `not indirect_target_visible` branch.
	var src = _read("res://autoloads/RulesEngine.gd")
	_check("fail band selected only when target NOT visible (10e: 3; 11e: band helper)",
		"if is_indirect_fire and not indirect_target_visible:" in src
			and "_indirect_hit_fail_band_11e(actor_unit_id, target_unit_id, board) if GameConstants.edition >= 11 else 3" in src,
		"would force the fail band even with line of sight (NOT RAW in either edition)")

func _test_cover_gated() -> void:
	print("\n-- C: Indirect cover bonus gated on `not visible` --")
	var src = _read("res://autoloads/RulesEngine.gd")
	# In the auto-resolve resolver, cover is set true only when indirect AND
	# no LoS — and (10.07/13.08) the save-side grant is additionally gated to
	# 10e; at 11e indirect cover worsens the attacker's BS on the hit side.
	_check("auto-resolve indirect cover gated",
		"is_indirect_fire and GameConstants.edition < 11 and not _has_los_to_target_unit" in src,
		"target would always gain Benefit of Cover from Indirect Fire — silently wrong")

func _test_helpers_exist() -> void:
	print("\n-- D: helpers reachable on RulesEngine autoload --")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		return
	_check("RulesEngine autoload reachable", true)
	_check("has_indirect_fire helper exists",
		rules.has_method("has_indirect_fire"))
	_check("_has_los_to_target_unit helper exists (private but reachable)",
		rules.has_method("_has_los_to_target_unit"))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
