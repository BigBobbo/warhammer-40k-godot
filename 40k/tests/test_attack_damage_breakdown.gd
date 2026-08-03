extends SceneTree

# Damage-breakdown math for the AttackAssignmentDialog's collapsible table.
#
# Reported case (Fight phase, Blade Champion vs Stormboyz): the dialog printed
# `E[D]≈8.3` for Vaultswords – Victus and `E[D]≈3.1` for Hurricanis with no way
# to see where either number came from, so a player could not tell whether the
# forecast was believable — or that "8.3" is raw damage, not 8.3 dead Orks.
#
# These checks pin the chain the table renders, step by step, against the two
# real datasheet profiles:
#
#   Victus     A5  WS2+ S6 AP-3 D3   vs Stormboyz T5 Sv5+ W1
#     5 attacks × 5/6 hit = 4.17 hits × 4/6 wound (S6 > T5 -> 3+) = 2.78 wounds
#     Sv5+ worsened by AP-3 = 8+, i.e. no save at all -> 2.78 unsaved × D3
#     = 8.33 damage — but only ≈2.78 models slain, because two thirds of every
#     3-damage hit is thrown away on a 1-wound model.
#
#   Hurricanis A9  WS2+ S5 AP-1 D1   vs the same Stormboyz
#     9 × 5/6 = 7.5 hits × 3/6 (S5 = T5 -> 4+) = 3.75 wounds
#     Sv5+ worsened by AP-1 = 6+, 5/6 fail -> 3.125 unsaved × D1 = 3.13 damage
#     and ≈3.13 models slain.
#
# The point of the table: Victus wins on damage 8.3 vs 3.1 and LOSES on bodies
# 2.8 vs 3.1. Only the second number is a decision.
#
# Usage: godot --headless --path . -s tests/test_attack_damage_breakdown.gd

# Loaded lazily inside _run_tests, NOT preloaded: a `-s` script is compiled
# before the autoloads are registered, and AttackAssignmentDialog.gd names
# RulesEngine at class scope — preloading it here fails to compile with
# "Identifier not found: RulesEngine" and the SceneTree then idles forever.
var AAD = null

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return abs(a - b) < eps

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _stormboyz(count: int = 6) -> Dictionary:
	var models: Array = []
	for i in range(count):
		models.append({"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1})
	return {
		"id": "U_STORMBOYZ",
		"meta": {
			"name": "Stormboyz",
			"stats": {"toughness": 5, "save": 5, "wounds": 1, "move": 12}
		},
		"models": models
	}

func _victus() -> Dictionary:
	return {
		"name": "Vaultswords – Victus", "type": "Melee", "attacks": "5",
		"weapon_skill": "2", "strength": "6", "ap": "-3", "damage": "3",
		"abilities": [{"id": "devastating_wounds"}]
	}

func _hurricanis() -> Dictionary:
	return {
		"name": "Vaultswords – Hurricanis", "type": "Melee", "attacks": "9",
		"weapon_skill": "2", "strength": "5", "ap": "-1", "damage": "1",
		"abilities": [{"id": "sustained_hits", "x": 1}]
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attack_damage_breakdown ===\n")

	AAD = load("res://dialogs/AttackAssignmentDialog.gd")
	if AAD == null:
		print("  FAIL: could not load AttackAssignmentDialog.gd")
		quit(1)
		return

	var target := _stormboyz()

	print("-- A: Vaultswords – Victus (A5 WS2+ S6 AP-3 D3) vs Stormboyz (T5 Sv5+ W1) --")
	var v: Dictionary = AAD.damage_breakdown(_victus(), target, 1)
	_check("resolves", not v.is_empty())
	_check("5 attacks", _near(v.total_attacks, 5.0), str(v.get("total_attacks")))
	_check("hits on 2+ (83%)", _near(v.p_hit, 5.0 / 6.0), str(v.get("p_hit")))
	_check("4.17 hits", _near(v.expected_hits, 4.1667), str(v.get("expected_hits")))
	_check("S6 vs T5 wounds on 3+", int(v.wound_need) == 3, str(v.get("wound_need")))
	_check("2.78 wounds", _near(v.expected_wounds, 2.7778), str(v.get("expected_wounds")))
	_check("Sv5+ worsened by AP-3 to 8+", int(v.modified_save) == 7, str(v.get("modified_save")))
	_check("no save is possible (100% fail)", _near(v.p_unsaved, 1.0), str(v.get("p_unsaved")))
	_check("2.78 unsaved", _near(v.expected_unsaved, 2.7778), str(v.get("expected_unsaved")))
	_check("E[D] = 8.33 — the figure the dialog already printed",
		_near(v.expected_damage, 8.3333), str(v.get("expected_damage")))
	_check("but only ≈2.78 models slain (D3 on W1 models)",
		_near(v.expected_slain, 2.7778), str(v.get("expected_slain")))
	_check("≈5.56 damage lost to overkill",
		_near(v.wasted_damage, 5.5556), str(v.get("wasted_damage")))
	_check("Devastating Wounds is declared unmodelled",
		"Devastating Wounds" in v.unmodelled, str(v.get("unmodelled")))

	print("\n-- B: Vaultswords – Hurricanis (A9 WS2+ S5 AP-1 D1) vs the same Stormboyz --")
	var h: Dictionary = AAD.damage_breakdown(_hurricanis(), target, 1)
	_check("9 attacks", _near(h.total_attacks, 9.0), str(h.get("total_attacks")))
	_check("7.5 hits", _near(h.expected_hits, 7.5), str(h.get("expected_hits")))
	_check("S5 vs T5 wounds on 4+", int(h.wound_need) == 4, str(h.get("wound_need")))
	_check("3.75 wounds", _near(h.expected_wounds, 3.75), str(h.get("expected_wounds")))
	_check("Sv5+ worsened by AP-1 to 6+", int(h.modified_save) == 6, str(h.get("modified_save")))
	_check("83% of saves fail", _near(h.p_unsaved, 5.0 / 6.0), str(h.get("p_unsaved")))
	_check("E[D] = 3.13 — the figure the dialog already printed",
		_near(h.expected_damage, 3.125), str(h.get("expected_damage")))
	_check("≈3.13 models slain — D1 wastes nothing",
		_near(h.expected_slain, 3.125), str(h.get("expected_slain")))
	_check("no overkill waste", _near(h.wasted_damage, 0.0), str(h.get("wasted_damage")))
	_check("Sustained Hits is declared unmodelled",
		"Sustained Hits" in h.unmodelled, str(h.get("unmodelled")))

	print("\n-- C: the reported comparison, both ways round --")
	_check("Victus wins on raw damage (8.3 > 3.1)", v.expected_damage > h.expected_damage)
	_check("Hurricanis wins on bodies (3.13 > 2.78)", h.expected_slain > v.expected_slain,
		"%.2f vs %.2f" % [h.expected_slain, v.expected_slain])

	print("\n-- D: invulnerable saves ignore AP --")
	# Custodian Guard: T6, Sv2+, 4++ , W3. AP-3 worsens the armour save to 5+,
	# so the 4++ is the better one and the forecast must use it.
	var custodes := {
		"id": "U_CUSTODIAN_GUARD",
		"meta": {"name": "Custodian Guard", "stats": {"toughness": 6, "save": 2, "invuln": 4, "wounds": 3}},
		"models": [{"id": "m0", "alive": true, "wounds": 3, "current_wounds": 3}]
	}
	var c: Dictionary = AAD.damage_breakdown(_victus(), custodes, 1)
	_check("armour would be 5+ after AP-3", int(c.modified_save) == 5, str(c.get("modified_save")))
	_check("the 4++ invuln is used instead", int(c.effective_save) == 4, str(c.get("effective_save")))
	_check("flagged as an invuln save", c.uses_invuln == true)
	_check("50% of saves fail", _near(c.p_unsaved, 0.5), str(c.get("p_unsaved")))
	_check("no overkill vs 3-wound models", _near(c.wasted_damage, 0.0), str(c.get("wasted_damage")))

	print("\n-- E: a datasheet with no invuln is not a 0+ save --")
	# `invuln` is stored as 0 when a unit has none. Reading that literally gives
	# an "effective save 0+", i.e. nothing ever gets through — every forecast
	# against such a unit would have been 0.0.
	var no_invuln := _stormboyz()
	no_invuln.meta.stats["invuln"] = 0
	var n: Dictionary = AAD.damage_breakdown(_hurricanis(), no_invuln, 1)
	_check("still forecasts 3.13 damage", _near(n.expected_damage, 3.125), str(n.get("expected_damage")))

	print("\n-- F: Feel No Pain scales the damage --")
	var fnp_target := _stormboyz()
	var f: Dictionary = AAD.damage_breakdown(_hurricanis(), fnp_target, 1, 5)
	_check("FNP 5+ lets 4/6 of the damage through",
		_near(f.p_damage_through, 4.0 / 6.0), str(f.get("p_damage_through")))
	_check("3.125 damage becomes 2.08", _near(f.expected_damage, 2.0833), str(f.get("expected_damage")))
	_check("FNP is reported so the table can show the row", int(f.fnp) == 5)

	print("\n-- G: several models multiply the attacks, not the chain --")
	var mob: Dictionary = AAD.damage_breakdown(_hurricanis(), target, 3)
	_check("3 models = 27 attacks", _near(mob.total_attacks, 27.0), str(mob.get("total_attacks")))
	_check("damage scales linearly", _near(mob.expected_damage, 3.125 * 3.0), str(mob.get("expected_damage")))
	_check("models slain is capped by the survivors (6 alive)",
		_near(mob.expected_slain, 6.0), str(mob.get("expected_slain")))

	print("\n-- H: dice notation averages --")
	var d6 := _hurricanis()
	d6["attacks"] = "D6"
	d6["damage"] = "D6+1"
	var dd: Dictionary = AAD.damage_breakdown(d6, target, 1)
	_check("D6 attacks average 3.5", _near(dd.total_attacks, 3.5), str(dd.get("total_attacks")))
	_check("D6+1 damage averages 4.5", _near(dd.damage_avg, 4.5), str(dd.get("damage_avg")))

	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
