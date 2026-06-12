extends SceneTree

# ISS-041 (step 2): the edition-gated 11e resolution flow in RulesEngine.
#  - 04.03 identical-attack gathering (AttackSequence.gather_identical_attacks)
#    incl. the resolve_shoot merge of identical same-weapon batches
#  - 05.03-05.04 allocation-group save/damage flow inside resolve_shoot:
#    batch save rolls, lowest→highest application, non-CHARACTER groups
#    before CHARACTER groups
#  - 24.10 devastating wounds as per-crit mortal wounds (max one model per
#    crit, excess lost), applied after normal damage
#  - Allocation.apply_save_rolls opts (save_modifier / effect_invuln /
#    damage_provider) used by the engine wiring
# The 10e path is pinned byte-for-byte by tests/test_iss012_attack_goldens.gd.
#
# Usage: godot --headless --path . -s tests/test_iss041b_resolution_11e.gd

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

# -- fixtures ------------------------------------------------------------------

func _gun(name: String, ap: String = "0", special_rules: String = "", damage: String = "1") -> Dictionary:
	return {
		"name": name, "type": "Ranged", "range": "24",
		"attacks": "2", "ballistic_skill": "3", "strength": "8",
		"ap": ap, "damage": damage, "special_rules": special_rules
	}

func _board(weapons: Array, target_models: Array, attacks: String = "6",
		torrent: bool = true) -> Dictionary:
	var ws = []
	for w in weapons:
		var wd = w.duplicate(true)
		wd["attacks"] = attacks
		if torrent and wd.get("special_rules", "") == "":
			wd["special_rules"] = "torrent"
		ws.append(wd)
	var shooters = []
	for i in range(2):
		shooters.append({
			"id": "ms%d" % i, "position": {"x": 100, "y": 100 + float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1, "flags": {},
				"meta": {"name": "Shooters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 4, "wounds": 2},
					"weapons": ws},
				"models": shooters
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 7, "wounds": 1}},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}
	}

## 2 W1 bodyguards + 1 W3 CHARACTER (per-model flag), all save 7 (no save
## possible) so the allocation order is the only thing deciding who dies.
func _attached_target_models() -> Array:
	return [
		{"id": "mt0", "position": {"x": 300, "y": 100}, "base_mm": 32,
			"base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1},
		{"id": "mt1", "position": {"x": 300, "y": 135}, "base_mm": 32,
			"base_type": "circular", "alive": true, "wounds": 1, "current_wounds": 1},
		{"id": "mt2", "position": {"x": 300, "y": 170}, "base_mm": 32,
			"base_type": "circular", "alive": true, "wounds": 3, "current_wounds": 3,
			"is_character": true},
	]

func _plain_target_models(count: int) -> Array:
	var out = []
	for i in range(count):
		out.append({"id": "mt%d" % i, "position": {"x": 300, "y": 100 + float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1})
	return out

func _dice_by_context(res: Dictionary, ctx: String) -> Array:
	var out = []
	for d in res.get("dice", []):
		if d.get("context", "") == ctx:
			out.append(d)
	return out

func _alive_false_indices(res: Dictionary) -> Array:
	var out = []
	for d in res.get("diffs", []):
		var p = str(d.get("path", ""))
		if p.ends_with(".alive") and d.get("value") == false:
			out.append(int(p.split(".")[3]))
	return out

# -- tests ---------------------------------------------------------------------

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss041b_resolution_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine autoload present", rules != null)

	print("-- 04.03 identical-attack gathering --")
	var gboard = _board([_gun("Gun A"), _gun("Gun B"), _gun("Gun C", "-2"),
		_gun("Gun D", "0", "lethal hits")], _plain_target_models(3))
	var assignments = [
		{"weapon_id": "Gun A", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
		{"weapon_id": "Gun B", "target_unit_id": "U_TARGET", "model_ids": ["ms1"]},
	]
	var gathered = AttackSequence.gather_identical_attacks(assignments, gboard)
	_check("identical profiles vs same target gather into ONE batch",
		gathered.size() == 1 and gathered[0].weapon_ids.size() == 2, str(gathered))
	assignments = [
		{"weapon_id": "Gun A", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
		{"weapon_id": "Gun C", "target_unit_id": "U_TARGET", "model_ids": ["ms1"]},
	]
	gathered = AttackSequence.gather_identical_attacks(assignments, gboard)
	_check("different AP: NOT identical (04.03)", gathered.size() == 2)
	assignments = [
		{"weapon_id": "Gun A", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
		{"weapon_id": "Gun D", "target_unit_id": "U_TARGET", "model_ids": ["ms1"]},
	]
	gathered = AttackSequence.gather_identical_attacks(assignments, gboard)
	_check("same stats, different abilities: NOT identical (04.03 box)",
		gathered.size() == 2)
	assignments = [
		{"weapon_id": "Gun A", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
		{"weapon_id": "Gun B", "target_unit_id": "U_SHOOTER", "model_ids": ["ms1"]},
	]
	gathered = AttackSequence.gather_identical_attacks(assignments, gboard)
	_check("different targets: separate batches", gathered.size() == 2)
	assignments = [
		{"weapon_id": "Gun A", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
		{"weapon_id": "Gun B", "target_unit_id": "U_TARGET", "model_ids": ["ms1"], "overwatch": true},
	]
	gathered = AttackSequence.gather_identical_attacks(assignments, gboard)
	_check("overwatch resolves under different rules: separate batches",
		gathered.size() == 2)

	print("\n-- pg-20 worked example: boltguns + bolt pistol gather; heavy bolter apart --")
	# 2 boltguns (A2, BS3+, S4, AP0, D1), 1 bolt pistol (A1, same profile,
	# [PISTOL]) and 1 heavy bolter (A3, BS4+, S5, AP-1, D2). The example
	# gathers FIVE dice for the boltguns + pistol (identical attacks —
	# PISTOL is targeting-only) and THREE for the heavy bolter.
	var wboard = {
		"units": {
			"U_TACTICALS": {"id": "U_TACTICALS", "owner": 1, "flags": {},
				"meta": {"name": "Tacticals", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 3, "wounds": 2},
					"weapons": [
						{"name": "Boltgun", "type": "Ranged", "range": "24", "attacks": "2",
							"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
							"special_rules": ""},
						{"name": "Bolt Pistol", "type": "Ranged", "range": "12", "attacks": "1",
							"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
							"special_rules": "pistol"},
						{"name": "Heavy Bolter", "type": "Ranged", "range": "36", "attacks": "3",
							"ballistic_skill": "4", "strength": "5", "ap": "-1", "damage": "2",
							"special_rules": ""}]},
				"models": [
					{"id": "ms0", "position": {"x": 100, "y": 100}, "base_mm": 32,
						"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2},
					{"id": "ms1", "position": {"x": 100, "y": 135}, "base_mm": 32,
						"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2},
					{"id": "ms2", "position": {"x": 100, "y": 170}, "base_mm": 32,
						"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2},
					{"id": "ms3", "position": {"x": 100, "y": 205}, "base_mm": 32,
						"base_type": "circular", "alive": true, "wounds": 2, "current_wounds": 2}]},
			"U_BLUE": {"id": "U_BLUE", "owner": 2, "flags": {},
				"meta": {"name": "Blue", "keywords": ["INFANTRY"],
					"stats": {"toughness": 3, "save": 3, "wounds": 1}},
				"models": _plain_target_models(5)}},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}}
	var wassignments = [
		{"weapon_id": "Boltgun", "target_unit_id": "U_BLUE", "model_ids": ["ms0", "ms1"]},
		{"weapon_id": "Bolt Pistol", "target_unit_id": "U_BLUE", "model_ids": ["ms2"]},
		{"weapon_id": "Heavy Bolter", "target_unit_id": "U_BLUE", "model_ids": ["ms3"]},
	]
	var wgathered = AttackSequence.gather_identical_attacks(wassignments, wboard)
	_check("two batches: {boltguns + bolt pistol} and {heavy bolter}",
		wgathered.size() == 2 and wgathered[0].weapon_ids == ["Boltgun", "Bolt Pistol"]
		and wgathered[1].weapon_ids == ["Heavy Bolter"], str(wgathered))
	var batch_dice: Array = []
	for group in wgathered:
		var dice := 0
		for ai in group.assignment_indices:
			var prof = rules.get_weapon_profile(wassignments[ai].weapon_id, wboard)
			dice += wassignments[ai].model_ids.size() * int(str(prof.get("attacks_raw", prof.get("attacks", 1))))
		batch_dice.append(dice)
	_check("FIVE attack dice gathered for boltguns+pistol, THREE for the heavy bolter",
		batch_dice == [5, 3], str(batch_dice))

	print("\n-- Allocation.apply_save_rolls opts --")
	var unit = {"id": "U", "owner": 2, "flags": {},
		"meta": {"stats": {"toughness": 4, "save": 3, "wounds": 1}},
		"models": [
			{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1},
			{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1}]}
	var groups = Allocation.build_groups(unit)
	var order = Allocation.default_order(groups)
	# effect_invuln 4+ vs AP-3: armour needs 6, invuln saves on 4+.
	var r = Allocation.apply_save_rolls(unit, groups, order, [4, 3], -3, 1,
		{"effect_invuln": 4})
	_check("effect_invuln: 4 saves via 4++ where AP-3 armour would fail; 3 fails",
		r.casualties == 1 and r.events[1].result == "saved", str(r.events))
	# save_modifier -1: a raw 3 vs Sv3 now fails.
	r = Allocation.apply_save_rolls(unit, groups, order, [3], 0, 1,
		{"save_modifier": -1})
	_check("save_modifier -1: raw 3 vs Sv3 fails", r.casualties == 1, str(r.events))
	# damage_provider returning 0 = fully prevented (FNP-style).
	var prevent_all = func(_roll: int, _mi: int) -> int: return 0
	r = Allocation.apply_save_rolls(unit, groups, order, [1, 1], 0, 1,
		{"damage_provider": prevent_all})
	_check("damage_provider 0: damage prevented, no casualties",
		r.casualties == 0 and r.events[0].result == "prevented", str(r.events))

	print("\n-- 11e resolve_shoot: allocation groups, CHARACTERs last --")
	GameConstants.edition = 11
	# Find a seed producing exactly 4 wounds from 6 torrent attacks (2+ to
	# wound, unmodified 1 fails), then replicate the dice stream.
	var seed := -1
	var exp_saves: Array = []
	for s in range(500):
		var rng = rules.RNGService.new(s)
		var wr = rng.roll_d6(6)
		var w := 0
		for roll in wr:
			if roll >= 2:
				w += 1
		if w == 4:
			seed = s
			exp_saves = rng.roll_d6(4)
			break
	_check("seed found (4 wounds from 6 attacks)", seed != -1)

	var board = _board([_gun("Torrent Gun", "0", "torrent")], _attached_target_models())
	var action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Torrent Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"]}]}}
	var res = rules.resolve_shoot(action, board, rules.RNGService.new(seed))
	_check("resolve succeeds", res.get("success", false))
	var save_entries = _dice_by_context(res, "save")
	_check("ONE batched save dice entry (05.03 step 3)",
		save_entries.size() == 1, "%d entries" % save_entries.size())
	_check("save batch matches the replicated dice stream",
		save_entries.size() == 1 and str(save_entries[0].rolls_raw) == str(exp_saves),
		str(save_entries))
	_check("allocation metadata exposed (order + per-roll events)",
		save_entries.size() == 1 and save_entries[0].has("allocation_11e")
		and save_entries[0].allocation_11e.order.size() == 2)
	var dead = _alive_false_indices(res)
	dead.sort()
	_check("both W1 bodyguards destroyed FIRST (non-CHARACTER group first)",
		dead == [0, 1], str(dead))
	_check("CHARACTER reached only after bodyguards: takes 2, survives on 1 wound",
		not 2 in dead and board.units["U_TARGET"].models[2].current_wounds == 1,
		"char wounds=%s" % str(board.units["U_TARGET"].models[2].get("current_wounds")))

	print("\n-- 11e devastating wounds: per-crit mortals, max one model each --")
	var dseed := -1
	var exp_crits := 0
	var exp_regular := 0
	for s in range(2000):
		var rng = rules.RNGService.new(s)
		var wr = rng.roll_d6(6)
		var c := 0
		var reg := 0
		for roll in wr:
			if roll == 6:
				c += 1
			elif roll >= 2:
				reg += 1
		if c >= 1 and reg >= 1 and c + reg <= 3:
			dseed = s
			exp_crits = c
			exp_regular = reg
			break
	_check("dev seed found (crits=%d regular=%d)" % [exp_crits, exp_regular], dseed != -1)

	var dboard = _board([_gun("Dev Gun", "0", "torrent, devastating wounds", "2")],
		_plain_target_models(4))
	action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Dev Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"]}]}}
	res = rules.resolve_shoot(action, dboard, rules.RNGService.new(dseed))
	var dw_entries = _dice_by_context(res, "devastating_wounds_11e")
	_check("devastating_wounds_11e dice entry with one event per crit",
		dw_entries.size() == 1 and dw_entries[0].events.size() == exp_crits,
		str(dw_entries))
	var per_crit_ok := dw_entries.size() == 1
	for ev in (dw_entries[0].events if dw_entries.size() == 1 else []):
		# D2 vs W1: each crit destroys exactly one model and LOSES the excess.
		if not (ev.get("destroyed", false) and ev.get("lost", -1) == 1 and ev.get("damage", -1) == 1):
			per_crit_ok = false
	_check("each crit damages AT MOST one model; excess lost (24.10 pg-80 semantics)",
		per_crit_ok, str(dw_entries))
	var ddead = _alive_false_indices(res)
	_check("casualties = regular fails + crits (saves impossible at Sv7)",
		ddead.size() == exp_regular + exp_crits,
		"dead=%d expected=%d" % [ddead.size(), exp_regular + exp_crits])

	print("\n-- 11e resolve_shoot merges identical same-weapon batches --")
	var mboard = _board([_gun("Torrent Gun", "0", "torrent")], _plain_target_models(4), "2")
	action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [
			{"weapon_id": "Torrent Gun", "target_unit_id": "U_TARGET", "model_ids": ["ms0"]},
			{"weapon_id": "Torrent Gun", "target_unit_id": "U_TARGET", "model_ids": ["ms1"]}]}}
	res = rules.resolve_shoot(action, mboard, rules.RNGService.new(7))
	var to_wound = _dice_by_context(res, "to_wound")
	_check("two identical assignments resolve as ONE gathered batch (04.03)",
		to_wound.size() == 1 and _dice_by_context(res, "save").size() <= 1,
		"%d wound batches" % to_wound.size())
	_check("gathered batch rolls all 4 attacks together",
		to_wound.size() == 1 and to_wound[0].rolls_raw.size() == 4, str(to_wound))

	print("\n-- edition 10 untouched --")
	GameConstants.edition = 10
	var b10 = _board([_gun("Torrent Gun", "0", "torrent")], _attached_target_models())
	action = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Torrent Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0"]}]}}
	res = rules.resolve_shoot(action, b10, rules.RNGService.new(seed))
	var any_alloc := false
	for d in res.get("dice", []):
		if d.has("allocation_11e") or d.get("context", "") == "devastating_wounds_11e":
			any_alloc = true
	_check("no 11e allocation artifacts at edition 10 (goldens pin the full path)",
		not any_alloc)

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
