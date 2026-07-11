extends SceneTree

# Waaagh! advance-and-charge (bug report 2026-07-10): Ork units that Advanced
# while the Waaagh! is active must be able to declare a charge, but the 11e
# charge template (ChargeMove11e.eligible) rejected every unit with the
# advanced/fell_back/cannot_charge flags without checking the ability
# overrides (effect_advance_and_charge / effect_fall_back_and_charge from
# Waaagh! or Full Throttle, Adrenaline Junkies detachment rule) that the
# legacy path (ChargePhase._can_unit_charge) honours. The UI listed the unit
# as eligible, then DECLARE_CHARGE failed with "advanced or fell back this
# turn".
#
# Usage: godot --headless --path . -s tests/test_waaagh_advance_charge.gd

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

func _board() -> Dictionary:
	return {"units": {
		"U_BOYZ": {"id": "U_BOYZ", "owner": 1, "flags": {},
			"meta": {"name": "Boyz", "keywords": ["INFANTRY", "ORKS"], "stats": {}},
			"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 500, "y": 500}}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "e0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 700, "y": 500}}]},
	}, "meta": {}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_waaagh_advance_charge ===\n")
	GameConstants.edition = 11
	var chg: MoveType = MoveTypes.get_type("charge")

	print("-- 11e template: advance/fall-back overrides --")
	var b = _board()
	_check("baseline: unit with no flags is eligible", chg.eligible("U_BOYZ", b).eligible,
		str(chg.eligible("U_BOYZ", b)))

	# Advance with no ability: blocked (11.02).
	b = _board()
	b.units["U_BOYZ"].flags["advanced"] = true
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	var el = chg.eligible("U_BOYZ", b)
	_check("advanced without ability cannot charge", not el.eligible, str(el))

	# Advance while Waaagh!/Full Throttle grants advance-and-charge: eligible.
	# The Advance move sets BOTH advanced and cannot_charge — both must be
	# overridden by the effect flag.
	b = _board()
	b.units["U_BOYZ"].flags["advanced"] = true
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	b.units["U_BOYZ"].flags["effect_advance_and_charge"] = true
	el = chg.eligible("U_BOYZ", b)
	_check("advanced WITH advance_and_charge effect (Waaagh!) is eligible", el.eligible, str(el))

	# Fall back with fall_back_and_charge (Full Throttle): eligible.
	b = _board()
	b.units["U_BOYZ"].flags["fell_back"] = true
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	b.units["U_BOYZ"].flags["effect_fall_back_and_charge"] = true
	el = chg.eligible("U_BOYZ", b)
	_check("fell back WITH fall_back_and_charge effect is eligible", el.eligible, str(el))

	# The advance effect does NOT excuse a fall back (and vice versa).
	b = _board()
	b.units["U_BOYZ"].flags["fell_back"] = true
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	b.units["U_BOYZ"].flags["effect_advance_and_charge"] = true
	el = chg.eligible("U_BOYZ", b)
	_check("advance effect does not override a fall back", not el.eligible, str(el))

	# Turbo Boostas: hard lock that no advance-and-charge effect overrides.
	b = _board()
	b.units["U_BOYZ"].flags["advanced"] = true
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	b.units["U_BOYZ"].flags["effect_advance_and_charge"] = true
	b.units["U_BOYZ"].flags["turbo_boosted"] = true
	el = chg.eligible("U_BOYZ", b)
	_check("turbo_boosted is a hard lock (effect cannot override)", not el.eligible, str(el))

	# A standalone cannot_charge lock (action 16.01 / disembark 18.04 — no
	# advanced/fell_back flag) is NOT overridable by the effect.
	b = _board()
	b.units["U_BOYZ"].flags["cannot_charge"] = true
	b.units["U_BOYZ"].flags["effect_advance_and_charge"] = true
	el = chg.eligible("U_BOYZ", b)
	_check("standalone cannot_charge lock (action/disembark) stays locked", not el.eligible, str(el))

	print("\n-- real Waaagh! activation path (FactionAbilityManager) --")
	var fam = root.get_node_or_null("FactionAbilityManager")
	var gs = root.get_node_or_null("GameState")
	_check("FactionAbilityManager + GameState autoloads present", fam != null and gs != null)
	if fam != null and gs != null:
		gs.state.units["U_WAAAGH_TEST"] = {"id": "U_WAAAGH_TEST", "owner": 2, "flags": {},
			"meta": {"name": "Test Boyz", "keywords": ["INFANTRY", "ORKS"],
				"abilities": [{"name": "Waaagh!", "type": "Faction"}], "stats": {}},
			"models": [{"id": "m0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 500, "y": 500}}]}
		gs.state.units["U_WAAAGH_FOE"] = {"id": "U_WAAAGH_FOE", "owner": 1, "flags": {},
			"meta": {"name": "Test Foe", "keywords": ["INFANTRY"], "stats": {}},
			"models": [{"id": "e0", "alive": true, "base_mm": 32, "base_type": "circular",
				"position": {"x": 700, "y": 500}}]}
		fam.detect_faction_abilities(2)
		_check("player 2 detected as having Waaagh!", fam.player_has_ability(2, "Waaagh!"))
		var act = fam.activate_waaagh(2)
		_check("activate_waaagh succeeds", act.get("success", false), str(act))
		var test_unit = gs.state.units["U_WAAAGH_TEST"]
		_check("Waaagh! sets effect_advance_and_charge on the unit",
			test_unit.flags.get("effect_advance_and_charge", false), str(test_unit.flags))
		# Simulate the Advance move's flags, then ask the 11e template.
		test_unit.flags["advanced"] = true
		test_unit.flags["cannot_charge"] = true
		el = chg.eligible("U_WAAAGH_TEST", gs.state)
		_check("advanced unit is charge-eligible while Waaagh! is active", el.eligible, str(el))
		# Waaagh! over: the unit goes back to being blocked after advancing.
		fam.deactivate_waaagh(2)
		el = chg.eligible("U_WAAAGH_TEST", gs.state)
		_check("after Waaagh! ends, advanced unit is blocked again", not el.eligible, str(el))
		gs.state.units.erase("U_WAAAGH_TEST")
		gs.state.units.erase("U_WAAAGH_FOE")

	print("\n-- Shooting-phase blanket clear preserves Waaagh! effects --")
	# Bug 2026-07: ShootingPhase._clear_stratagem_phase_flags blanket-erased
	# every effect_* flag at end of phase, stripping the Waaagh!'s
	# effect_advance_and_charge + effect_invuln (which last until the owner's
	# next Command phase) — so a unit that Advanced under a Waaagh! could not
	# charge, and its 5+ invuln vanished. Reproduce the snapshot→wipe→restore.
	if fam != null:
		# A Waaagh! unit that ALSO has a genuine phase-scoped stratagem effect
		# (effect_cover from Go to Ground): Waaagh! flags survive, cover clears.
		var waaagh_flags = {
			"waaagh_active": true,
			"effect_advance_and_charge": true,
			"effect_invuln": 5,
			"effect_invuln_source": "Waaagh!",
			"effect_cover": true,
		}
		var preserved = fam.snapshot_persistent_ability_flags(waaagh_flags)
		EffectPrimitivesData.clear_all_effect_flags(waaagh_flags)
		for k in preserved:
			waaagh_flags[k] = preserved[k]
		_check("Waaagh! effect_advance_and_charge survives the blanket clear",
			waaagh_flags.get("effect_advance_and_charge", false), str(waaagh_flags))
		_check("Waaagh! effect_invuln survives the blanket clear",
			int(waaagh_flags.get("effect_invuln", 0)) == 5, str(waaagh_flags))
		_check("phase-scoped effect_cover is still cleared for the Waaagh! unit",
			not waaagh_flags.has("effect_cover"), str(waaagh_flags))

		# A unit WITHOUT an active Waaagh! keeps the old behaviour: everything
		# effect_* is wiped (no preservation).
		var plain_flags = {"effect_advance_and_charge": true, "effect_cover": true}
		var plain_preserved = fam.snapshot_persistent_ability_flags(plain_flags)
		EffectPrimitivesData.clear_all_effect_flags(plain_flags)
		for k in plain_preserved:
			plain_flags[k] = plain_preserved[k]
		_check("non-Waaagh unit's effect flags are fully cleared",
			not plain_flags.has("effect_advance_and_charge") and not plain_flags.has("effect_cover"),
			str(plain_flags))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
