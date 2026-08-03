extends SceneTree

# Modifier provenance — every hit/wound roll modifier the engine applies now
# records WHERE IT CAME FROM (ModifierLedger), so the Dice Log and the two
# resolution docks can name the rule instead of printing an anonymous "+1".
#
# Motivating bug report: a Lions of the Emperor player wounding on 2+ off
# Against All Odds had no way to tell whether the detachment rule had fired.
#
# Covers:
#  1. ModifierLedger formatting (effect text, de-dup, cancelled entries)
#  2. Against All Odds provenance reaches BOTH the melee hit and wound contexts
#  3. The same attack WITHOUT the Lions detachment records no AAO entry
#  4. evaluate_against_all_odds reports the nearest friendly (drives the
#     board sparkle + hover readout), and agrees with check_against_all_odds
#  5. A non-AAO modifier ([LANCE]) is also named, proving the mechanism is
#     general rather than special-cased for one rule
#
# Usage: godot --headless --path . -s tests/test_modifier_provenance.gd

var passed := 0
var failed := 0

const PX_PER_INCH := 40.0


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


func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_modifier_provenance ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return
	var fam = root.get_node_or_null("FactionAbilityManager")
	if fam == null:
		_check("FactionAbilityManager autoload reachable", false)
		_finish()
		return

	_test_ledger_formatting()
	_test_aao_named_in_melee(rules, fam)
	_test_no_aao_without_detachment(rules)
	_test_aao_evaluator(fam)
	_test_lance_named(rules)
	_finish()


func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)


# -- 1. ledger formatting ------------------------------------------------------

func _test_ledger_formatting() -> void:
	print("-- ModifierLedger formatting --")
	var led: Array = []
	ModifierLedger.note(led, "Against All Odds", ModifierLedger.KIND_WOUND,
		ModifierLedger.PLUS_ONE, "no other friendly unit within 6\"")
	ModifierLedger.note(led, "[TWIN-LINKED]", ModifierLedger.KIND_WOUND, ModifierLedger.REROLL_FAILED)
	# Duplicate of the first — must collapse, not print twice.
	ModifierLedger.note(led, "Against All Odds", ModifierLedger.KIND_WOUND,
		ModifierLedger.PLUS_ONE, "no other friendly unit within 6\"")

	var lines := ModifierLedger.lines(led, ModifierLedger.KIND_WOUND)
	_check("de-duplicates repeated source+effect (3 notes -> 2 lines)", lines.size() == 2,
		"got %d" % lines.size())
	_check("names the source and the effect",
		str(lines[0].get("text", "")).begins_with("Against All Odds: +1 to wound"),
		str(lines[0].get("text", "")))
	_check("carries the reason", "within 6\"" in str(lines[0].get("text", "")))
	_check("re-roll effect reads naturally",
		"re-roll failed wound rolls" in str(lines[1].get("text", "")), str(lines[1].get("text", "")))
	_check("kind filter excludes the other third",
		ModifierLedger.lines(led, ModifierLedger.KIND_HIT).is_empty())
	_check("has_source finds a recorded rule", ModifierLedger.has_source(led, "Against All Odds"))
	_check("has_source rejects an absent rule", not ModifierLedger.has_source(led, "Oath of Moment"))

	# Suppression: Captain-General strips ±1, so the stripped entry must read as
	# cancelled rather than silently continuing to claim a bonus.
	var led2: Array = []
	ModifierLedger.note(led2, "Against All Odds", ModifierLedger.KIND_HIT, ModifierLedger.PLUS_ONE)
	ModifierLedger.note(led2, "Captain-General", ModifierLedger.KIND_HIT, ModifierLedger.IGNORED)
	ModifierLedger.mark_ignored(led2, ModifierLedger.KIND_HIT,
		[ModifierLedger.PLUS_ONE, ModifierLedger.MINUS_ONE])
	var l2 := ModifierLedger.lines(led2, ModifierLedger.KIND_HIT)
	_check("a stripped modifier is marked cancelled",
		"(cancelled)" in str(l2[0].get("text", "")), str(l2[0].get("text", "")))
	_check("the suppressing rule itself is not cancelled",
		not ("(cancelled)" in str(l2[1].get("text", ""))), str(l2[1].get("text", "")))

	# Stack sources arrive as snake_case ids from ModifierStack.
	var led3: Array = []
	ModifierLedger.note_stack(led3, ["benefit_of_cover", "heavy"], ModifierLedger.KIND_HIT,
		ModifierLedger.MINUS_ONE)
	var texts := ""
	for e in ModifierLedger.lines(led3, ModifierLedger.KIND_HIT):
		texts += str(e.get("text", "")) + "|"
	_check("11e stack source ids become display names",
		"Benefit of cover" in texts and "[HEAVY]" in texts, texts)


# -- 2/3/5. provenance through a real melee resolution -------------------------

## Two Custodes units, `gap_inches` apart edge-to-edge. The fighter swings at an
## enemy; the second friendly unit is what decides Against All Odds.
func _custodes_board(gap_inches: float, detachment: String, lance: bool = false) -> Dictionary:
	var blade := {
		"name": "Guardian spear", "type": "Melee", "range": "Melee",
		"attacks": "4", "weapon_skill": "2", "strength": "7",
		"ap": "-2", "damage": "2", "special_rules": "lance" if lance else ""
	}
	# Fighter at x=0; the friendly sits gap + both base radii to the right so the
	# EDGE-to-edge distance is exactly gap_inches (matching the rule's measure).
	var base_r_px := 32.0 / 2.0 * PX_PER_INCH / 25.4
	var friend_x := gap_inches * PX_PER_INCH + base_r_px * 2.0
	return {
		"units": {
			"U_FIGHTER": {
				"id": "U_FIGHTER", "owner": 1, "flags": {"charged_this_turn": lance},
				"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY", "ADEPTUS CUSTODES"],
					"stats": {"toughness": 6, "save": 2, "wounds": 3},
					"weapons": [blade]},
				"models": [
					{"id": "m0", "position": {"x": 0, "y": 0}, "base_mm": 32,
					 "base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3},
				]
			},
			"U_FRIEND": {
				"id": "U_FRIEND", "owner": 1, "flags": {},
				"meta": {"name": "Prosecutors", "keywords": ["INFANTRY", "ADEPTUS CUSTODES"],
					"stats": {"toughness": 3, "save": 4, "wounds": 1}},
				"models": [
					{"id": "f0", "position": {"x": friend_x, "y": 0}, "base_mm": 32,
					 "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1},
				]
			},
			"U_ENEMY": {
				"id": "U_ENEMY", "owner": 2, "flags": {},
				"meta": {"name": "Stormboyz", "keywords": ["INFANTRY", "ORKS"],
					"stats": {"toughness": 5, "save": 5, "wounds": 1}},
				"models": [
					{"id": "e0", "position": {"x": 20, "y": 0}, "base_mm": 32,
					 "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1},
					{"id": "e1", "position": {"x": 20, "y": 40}, "base_mm": 32,
					 "base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1},
				]
			}
		},
		"factions": {"1": {"detachment": detachment}, "2": {"detachment": "War Horde"}},
		"meta": {"phase": 12, "active_player": 1, "battle_round": 2}
	}


func _melee_action() -> Dictionary:
	return {
		"type": "FIGHT", "actor_unit_id": "U_FIGHTER",
		"payload": {"assignments": [{
			"attacker": "U_FIGHTER", "weapon": "Guardian spear",
			"target": "U_ENEMY", "models": ["0"]
		}]}
	}


## Pull every ledger entry out of a resolution result's dice blocks.
func _ledger_sources(res: Dictionary, kind: String) -> Array:
	var out: Array = []
	for db in res.get("dice", []):
		for e in db.get("modifier_ledger", []):
			if str(e.get("kind", "")) == kind:
				out.append(str(e.get("source", "")))
	return out


func _test_aao_named_in_melee(rules, fam) -> void:
	print("\n-- Against All Odds named in a real melee resolution --")
	# 9" of clear air: the rule is ON.
	var board := _custodes_board(9.0, "Lions of the Emperor")
	var res = rules.resolve_melee_attacks(_melee_action(), board, rules.RNGService.new(7))
	_check("melee resolution succeeded", res.get("success", false), str(res.get("log_text", "")))

	var hit_sources := _ledger_sources(res, ModifierLedger.KIND_HIT)
	var wound_sources := _ledger_sources(res, ModifierLedger.KIND_WOUND)
	_check("hit ledger names Against All Odds", "Against All Odds" in hit_sources, str(hit_sources))
	_check("wound ledger names Against All Odds", "Against All Odds" in wound_sources, str(wound_sources))

	# The provenance must agree with the maths it is explaining.
	var fighter: Dictionary = board["units"]["U_FIGHTER"]
	_check("engine agrees the bonus is active",
		fam.check_against_all_odds(fighter, board))


func _test_no_aao_without_detachment(rules) -> void:
	print("\n-- no Against All Odds without the Lions detachment --")
	# Same 9" spacing, Shield Host instead — the rule must not fire, and must
	# not be claimed in the readout either.
	var board := _custodes_board(9.0, "Shield Host")
	var res = rules.resolve_melee_attacks(_melee_action(), board, rules.RNGService.new(7))
	_check("melee resolution succeeded", res.get("success", false))
	var hit_sources := _ledger_sources(res, ModifierLedger.KIND_HIT)
	var wound_sources := _ledger_sources(res, ModifierLedger.KIND_WOUND)
	_check("hit ledger does NOT claim Against All Odds",
		not ("Against All Odds" in hit_sources), str(hit_sources))
	_check("wound ledger does NOT claim Against All Odds",
		not ("Against All Odds" in wound_sources), str(wound_sources))

	# And with the Lions detachment but a friendly parked 3" away, likewise off.
	var close_board := _custodes_board(3.0, "Lions of the Emperor")
	var res2 = rules.resolve_melee_attacks(_melee_action(), close_board, rules.RNGService.new(7))
	_check("crowded Lions unit records no Against All Odds",
		not ("Against All Odds" in _ledger_sources(res2, ModifierLedger.KIND_WOUND)))


func _test_lance_named(rules) -> void:
	print("\n-- a non-AAO modifier is named too (mechanism is general) --")
	# Shield Host (so AAO cannot fire) + [LANCE] on the charge.
	var board := _custodes_board(9.0, "Shield Host", true)
	var res = rules.resolve_melee_attacks(_melee_action(), board, rules.RNGService.new(3))
	_check("melee resolution succeeded", res.get("success", false))
	var wound_sources := _ledger_sources(res, ModifierLedger.KIND_WOUND)
	_check("wound ledger names [LANCE]", "[LANCE]" in wound_sources, str(wound_sources))


# -- 4. the evaluator behind the board sparkle ---------------------------------

func _test_aao_evaluator(fam) -> void:
	print("\n-- evaluate_against_all_odds (board sparkle + hover) --")
	var far := _custodes_board(9.0, "Lions of the Emperor")
	var st_far = fam.evaluate_against_all_odds(far["units"]["U_FIGHTER"], far, true)
	_check("isolated unit is applicable", st_far.get("applicable", false))
	_check("isolated unit is active", st_far.get("active", false))
	_check("names the nearest friendly", st_far.get("nearest_name", "") == "Prosecutors",
		str(st_far.get("nearest_name", "")))
	_check("measures the gap (~9\")", abs(float(st_far.get("nearest_inches", 0.0)) - 9.0) < 0.15,
		"got %.2f" % float(st_far.get("nearest_inches", 0.0)))

	var near := _custodes_board(3.0, "Lions of the Emperor")
	var st_near = fam.evaluate_against_all_odds(near["units"]["U_FIGHTER"], near, true)
	_check("crowded unit is still applicable (so it gets an explanation)",
		st_near.get("applicable", false))
	_check("crowded unit is NOT active", not st_near.get("active", false))
	_check("crowded unit reports the spoiler's distance (~3\")",
		abs(float(st_near.get("nearest_inches", 0.0)) - 3.0) < 0.15,
		"got %.2f" % float(st_near.get("nearest_inches", 0.0)))

	# Non-Lions army: no marker at all, not merely an inactive one.
	var sh := _custodes_board(9.0, "Shield Host")
	var st_sh = fam.evaluate_against_all_odds(sh["units"]["U_FIGHTER"], sh, true)
	_check("Shield Host unit is not applicable", not st_sh.get("applicable", false))

	# The fast path the engine uses and the full path the UI uses must agree.
	for b in [far, near, sh]:
		var quick: bool = fam.check_against_all_odds(b["units"]["U_FIGHTER"], b)
		var full: bool = fam.evaluate_against_all_odds(b["units"]["U_FIGHTER"], b, true).get("active", false)
		_check("fast path agrees with full evaluation", quick == full,
			"quick=%s full=%s" % [quick, full])
