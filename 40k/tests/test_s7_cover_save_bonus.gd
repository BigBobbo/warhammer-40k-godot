extends SceneTree

# T2.S7: Cover save bonus
#
# WH40K 10e BENEFIT OF COVER: each attack allocated to a model with cover has
# its AP worsened by 1 (i.e., the required save is improved by 1). Two caveats
# implemented in RulesEngine._calculate_save_needed:
#   - 3+ or better save vs AP0 does NOT benefit from cover
#   - Save cap of 2+ (cover never produces a better-than-2+ save)
#   - Net improvement capped at +1 total
#
# Tests the static helper directly.
#
# Usage: godot --headless --path . -s tests/test_s7_cover_save_bonus.gd

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

func _calc(rules, base_save: int, ap: int, has_cover: bool, invuln: int = 0) -> int:
	var r = rules._calculate_save_needed(base_save, ap, has_cover, invuln)
	return r.armour

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_s7_cover_save_bonus ===\n")
	var rules = root.get_node("RulesEngine")

	# Sv4+ baseline
	_check("Sv4+, AP0, no cover → 4+",
		_calc(rules, 4, 0, false) == 4, "got %d" % _calc(rules, 4, 0, false))
	_check("Sv4+, AP0, cover → 3+ (cover improves by 1)",
		_calc(rules, 4, 0, true) == 3, "got %d" % _calc(rules, 4, 0, true))
	_check("Sv4+, AP1, no cover → 5+",
		_calc(rules, 4, 1, false) == 5)
	_check("Sv4+, AP1, cover → 4+ (cover negates AP1)",
		_calc(rules, 4, 1, true) == 4, "got %d" % _calc(rules, 4, 1, true))
	_check("Sv4+, AP2, cover → 5+ (cover only +1)",
		_calc(rules, 4, 2, true) == 5, "got %d" % _calc(rules, 4, 2, true))

	# Sv3+ — special-case: vs AP0, cover does NOT improve to 2+
	_check("Sv3+, AP0, cover → 3+ (cover does NOT improve 3+ vs AP0)",
		_calc(rules, 3, 0, true) == 3, "got %d" % _calc(rules, 3, 0, true))
	_check("Sv3+, AP0, no cover → 3+",
		_calc(rules, 3, 0, false) == 3)
	_check("Sv3+, AP1, cover → 3+ (cover negates AP1)",
		_calc(rules, 3, 1, true) == 3, "got %d" % _calc(rules, 3, 1, true))
	_check("Sv3+, AP1, no cover → 4+",
		_calc(rules, 3, 1, false) == 4)

	# Sv2+ — already at the cap, cover never improves below 2+
	_check("Sv2+, AP0, cover → 2+ (already at cap)",
		_calc(rules, 2, 0, true) == 2, "got %d" % _calc(rules, 2, 0, true))
	_check("Sv2+, AP1, cover → 2+ (cover negates AP1)",
		_calc(rules, 2, 1, true) == 2, "got %d" % _calc(rules, 2, 1, true))
	_check("Sv2+, AP2, cover → 3+",
		_calc(rules, 2, 2, true) == 3, "got %d" % _calc(rules, 2, 2, true))

	# Sv6+ heavy AP
	_check("Sv6+, AP1, cover → 6+ (cover negates AP1)",
		_calc(rules, 6, 1, true) == 6, "got %d" % _calc(rules, 6, 1, true))

	# cap_applied is defensive against stacked +1 modifiers and isn't reachable
	# via cover alone (cover only provides -1 to required save). The 2+ floor
	# (max(2, ...)) is the practical guard verified above for Sv2+ cases.

	# Invuln-better takes precedence
	var inv_better = rules._calculate_save_needed(6, 3, false, 4)
	_check("Sv6+ AP3 invuln4+: use_invuln=true",
		inv_better.use_invuln == true,
		"armour=%d inv=%d" % [inv_better.armour, inv_better.inv])

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
