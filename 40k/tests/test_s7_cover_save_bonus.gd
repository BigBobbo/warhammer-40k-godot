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
# EDITION: cover-improves-the-save is a 10e-only rule. The cover sections
# below are pinned to GameConstants.edition = 10 (legacy regression); the
# edition-neutral AP / invuln checks run at the harness edition; the final
# "11e 13.08" section pins edition 11 and asserts cover never moves the save.
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
	var harness_edition: int = GameConstants.edition

	# Legacy 10e regression: Benefit of Cover improves the armour save by 1
	# (+ the 10e "3+ or better vs AP0" and 2+ caveats) — 11e 13.08 replaced it
	# ("Each time a ranged attack targets a unit that has the benefit of cover
	# against it, worsen the BS characteristic of that attack by 1."), and 11e
	# 05.04 judges the save only on "After modifying the result by the attacking
	# weapon's AP characteristic, it is equal to or greater than the Sv
	# characteristic"; 11e coverage: the "11e 13.08" section at the end of this
	# file (cover never changes the save), tests/test_iss016_modifier_stack.gd
	# ("STEALTH target grants benefit of cover -> BS worsened by 1"),
	# tests/test_iss053_cover_plunging_11e.gd (13.08 qualification).
	# Set here, after the re-entry guard — SettingsService applies the harness
	# edition in _ready, so a write in _init would be overwritten.
	GameConstants.edition = 10
	_check("Legacy 10e pin: GameConstants.edition == 10",
		GameConstants.edition == 10, "got %d" % GameConstants.edition)

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

	# End of the legacy 10e cover sections — the invuln / AP-sign checks below
	# are edition-neutral and run at the harness edition.
	GameConstants.edition = harness_edition

	# Invuln-better takes precedence
	var inv_better = rules._calculate_save_needed(6, 3, false, 4)
	_check("Sv6+ AP3 invuln4+: use_invuln=true",
		inv_better.use_invuln == true,
		"armour=%d inv=%d" % [inv_better.armour, inv_better.inv])

	# AP-sign regression — weapon profiles produced by `get_weapon_profile`
	# return the negative magnitude form (ap=-2 for AP-2). The function must
	# treat both signs identically so the live data path produces the same
	# result as the magnitude form used elsewhere in this test.
	_check("Sv2+, AP-2 (neg form), no cover → 4+ (was 2+ pre-fix)",
		_calc(rules, 2, -2, false) == 4, "got %d" % _calc(rules, 2, -2, false))
	_check("Sv2+, AP-2 == Sv2+, AP+2 (sign-agnostic)",
		_calc(rules, 2, -2, false) == _calc(rules, 2, 2, false))
	_check("Sv3+, AP-1 (neg form), no cover → 4+",
		_calc(rules, 3, -1, false) == 4, "got %d" % _calc(rules, 3, -1, false))
	_check("Sv3+, AP-3 (neg form), no cover → 6+",
		_calc(rules, 3, -3, false) == 6, "got %d" % _calc(rules, 3, -3, false))

	# Legacy 10e regression: these two AP-sign checks also exercise the 10e
	# cover-improves-save rule (see the pin comment above) — 11e 13.08 replaced
	# it; 11e coverage: the "11e 13.08" section below (AP-1 neg form, cover).
	GameConstants.edition = 10
	_check("Legacy 10e pin (AP-sign cover checks): GameConstants.edition == 10",
		GameConstants.edition == 10, "got %d" % GameConstants.edition)
	_check("Sv4+, AP-1 (neg form), cover → 4+ (cover negates AP)",
		_calc(rules, 4, -1, true) == 4, "got %d" % _calc(rules, 4, -1, true))
	_check("Sv2+, AP-1 (neg form), cover → 2+ (cover negates AP, floored at cap)",
		_calc(rules, 2, -1, true) == 2, "got %d" % _calc(rules, 2, -1, true))
	GameConstants.edition = harness_edition

	# 11e 13.08: "Each time a ranged attack targets a unit that has the benefit
	# of cover against it, worsen the BS characteristic of that attack by 1." —
	# cover is hit-side only, so the save must be identical with and without
	# cover. 05.04: the save fails when "After modifying the result by the
	# attacking weapon's AP characteristic, it is equal to or greater than the
	# Sv characteristic" ⇒ the roll needed is Sv + |AP| (7 = no armour save).
	# _calculate_save_needed is still reached at 11e by the overwatch and
	# auto-allocate save paths, so a cover leak here would double-count cover
	# (BS worsened AND save improved).
	GameConstants.edition = 11
	_check("11e pin: GameConstants.edition == 11",
		GameConstants.edition == 11, "got %d" % GameConstants.edition)
	var e11_cases := [
		[4, 0, 4], [4, 1, 5], [4, 2, 6],
		[3, 0, 3], [3, 1, 4],
		[2, 0, 2], [2, 1, 3], [2, 2, 4],
		[6, 1, 7],
		[4, -1, 5], [2, -1, 3],
	]
	for c in e11_cases:
		var with_cover := _calc(rules, c[0], c[1], true)
		var without_cover := _calc(rules, c[0], c[1], false)
		_check("11e: Sv%d+, AP%d, cover → %d+ (13.08: cover worsens BS, never the save)" % [c[0], c[1], c[2]],
			with_cover == c[2] and with_cover == without_cover,
			"cover=%d no_cover=%d expected=%d" % [with_cover, without_cover, c[2]])
	GameConstants.edition = harness_edition

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
