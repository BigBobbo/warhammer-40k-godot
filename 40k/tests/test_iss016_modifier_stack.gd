extends SceneTree

# ISS-016: consolidated typed modifier stack.
#  - the ±1 net cap on dice-roll modifiers lives in ONE place
#    (acceptance: +2 worth of hit bonuses nets +1)
#  - characteristic (BS) modifiers accumulate uncapped and the 11e
#    hit-side sources route through the stack: benefit of cover incl.
#    STEALTH (13.08/24.33 — worsen BS), plunging fire (22.05 — improve
#    BS), [HEAVY] (24.16 — +1 to the hit roll)
#  - engine integration: at edition 11 resolve_shoot consumes the stack
#    (stealth = worsened BS, not a -1 hit modifier); edition 10 keeps the
#    bitfield path (golden corpus + stealth/heavy pipeline tests pin it)
#
# Usage: godot --headless --path . -s tests/test_iss016_modifier_stack.gd

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

func _shoot_board(weapon_special: String, target_abilities: Array,
		shooter_flags: Dictionary = {}, attacker_elevation: float = 0.0) -> Dictionary:
	var shooter_model = {
		"id": "ms0", "position": {"x": 100, "y": 100}, "base_mm": 32,
		"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2}
	if attacker_elevation > 0.0:
		shooter_model["elevation_inches"] = attacker_elevation
	var targets = []
	for i in range(4):
		targets.append({"id": "mt%d" % i, "position": {"x": 300, "y": 100 + float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1})
	return {
		"units": {
			"U_SHOOTER": {"id": "U_SHOOTER", "owner": 1, "flags": shooter_flags,
				"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2},
					"weapons": [{
						"name": "Test Gun", "type": "Ranged", "range": "24",
						"attacks": "6", "ballistic_skill": "3", "strength": "8",
						"ap": "0", "damage": "1", "special_rules": weapon_special}]},
				"models": [shooter_model]},
			"U_TARGET": {"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 7, "wounds": 1},
					"abilities": target_abilities},
				"models": targets}},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss016_modifier_stack ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine autoload present", rules != null)

	print("-- the ±1 dice-roll cap lives in the stack --")
	var stack = ModifierStack.new()
	stack.add("hit_roll", 1, "ability_a")
	stack.add("hit_roll", 1, "ability_b")
	_check("+2 worth of hit bonuses nets +1 (acceptance)", stack.net("hit_roll") == 1)
	stack.add("hit_roll", -1, "debuff")
	_check("+2-1 nets +1 (raw sum then cap)", stack.net("hit_roll") == 1
		and stack.raw_sum("hit_roll") == 1)
	stack = ModifierStack.new()
	stack.add("hit_roll", -1, "a")
	stack.add("hit_roll", -1, "b")
	_check("-2 worth of penalties nets -1", stack.net("hit_roll") == -1)
	stack = ModifierStack.new()
	stack.add("bs", 1, "cover")
	stack.add("bs", 1, "something_else")
	_check("characteristic (BS) modifiers accumulate UNcapped", stack.net("bs") == 2)
	stack.add("bs", -1, "plunging_fire")
	_check("worsen + improve sum (3 entries -> +1)", stack.net("bs") == 1)
	_check("sources() lists contributing sources",
		"plunging_fire" in stack.sources("bs") and stack.sources("hit_roll") == [])

	print("\n-- collect_hit_context_11e --")
	GameConstants.edition = 10
	var b = _shoot_board("", ["Stealth"])
	var prof = rules.get_weapon_profile("Test Gun", b)
	var ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("edition 10: empty stack (bitfield path owns 10e)", ctx.entries.is_empty())
	GameConstants.edition = 11
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("STEALTH target grants benefit of cover -> BS worsened by 1 (24.33/13.08)",
		ctx.net("bs") == 1 and "benefit_of_cover" in ctx.sources("bs"), ctx.describe())
	b = _shoot_board("ignores cover", ["Stealth"])
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("IGNORES COVER weapon: no BS worsening", ctx.net("bs") == 0, ctx.describe())
	# Plunging fire: attacker 3" up, target on ground level.
	b = _shoot_board("", ["Stealth"], {}, 3.0)
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b,
		{"attacker_models": b.units["U_SHOOTER"].models})
	_check("cover + plunging fire cancel out (BS +1 -1 = 0, both recorded)",
		ctx.net("bs") == 0 and ctx.sources("bs").size() == 2, ctx.describe())
	b = _shoot_board("", [], {}, 3.0)
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b,
		{"attacker_models": b.units["U_SHOOTER"].models})
	_check("plunging fire alone improves BS by 1 (22.05)",
		ctx.net("bs") == -1 and "plunging_fire" in ctx.sources("bs"), ctx.describe())
	# HEAVY (24.16): stationary + unengaged + not set up this turn.
	b = _shoot_board("heavy", [], {"remained_stationary": true})
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("[HEAVY] stationary unengaged unit: +1 to the hit roll",
		ctx.net("hit_roll") == 1 and "heavy" in ctx.sources("hit_roll"), ctx.describe())
	b = _shoot_board("heavy", [], {"remained_stationary": true, "set_up_this_turn": true})
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("[HEAVY] denied when the unit was set up this turn (24.16)",
		ctx.net("hit_roll") == 0, ctx.describe())
	b = _shoot_board("heavy", [], {})
	prof = rules.get_weapon_profile("Test Gun", b)
	ctx = ModifierStack.collect_hit_context_11e(b.units["U_SHOOTER"], b.units["U_TARGET"], prof, b)
	_check("[HEAVY] denied when the unit moved", ctx.net("hit_roll") == 0, ctx.describe())

	print("\n-- engine integration: resolve_shoot consumes the stack at 11e --")
	# Find a seed whose 6 hit dice contain at least one exact 3 (the roll
	# that a worsened BS flips from hit to miss) so the assertion bites.
	var seed := -1
	var exp_hits_at4 := 0
	for s in range(500):
		var rng = rules.RNGService.new(s)
		var hr = rng.roll_d6(6)
		if 3 in hr:
			seed = s
			for roll in hr:
				if roll >= 4:
					exp_hits_at4 += 1
			break
	_check("seed found (hit dice include a 3)", seed != -1)

	b = _shoot_board("", ["Stealth"])
	var action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Test Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"]}]}}
	var res = rules.resolve_shoot(action, b, rules.RNGService.new(seed))
	var hit_entry = {}
	for d in res.get("dice", []):
		if d.get("context", "") == "to_hit":
			hit_entry = d
	_check("11e stealth: BS worsened to 4+ — hits match the replicated stream",
		hit_entry.get("successes", -1) == exp_hits_at4,
		"successes=%s expected=%d" % [str(hit_entry.get("successes")), exp_hits_at4])
	_check("11e stealth is NOT also a -1 hit modifier (no double-dip)",
		(int(hit_entry.get("modifiers_applied", 0)) & rules.HitModifier.MINUS_ONE) == 0,
		str(hit_entry.get("modifiers_applied")))

	# HEAVY end-to-end at 11e: stationary unengaged unit gets the +1.
	b = _shoot_board("heavy", [], {"remained_stationary": true})
	res = rules.resolve_shoot(action, b, rules.RNGService.new(seed))
	hit_entry = {}
	for d in res.get("dice", []):
		if d.get("context", "") == "to_hit":
			hit_entry = d
	_check("11e [HEAVY]: +1 hit applied via the stack (heavy_bonus_applied)",
		hit_entry.get("heavy_bonus_applied", false), str(hit_entry.keys()))

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
