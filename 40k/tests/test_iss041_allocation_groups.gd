extends SceneTree

# ISS-041 (step 1): 11e allocation groups (core rules 05.03-05.04).
#
# Reproduces the rulebook's attached-unit worked example (pp. 22-23):
# Saint Celestine + 2 Geminae Superia + Seraphim take 5 wounding hits from
# heavy bolters (AP-1, D2). The defender orders: Geminae first, Seraphim
# second, Celestine (CHARACTER) last — and damage applies lowest save roll
# to highest: the two 1s destroy both Geminae, the 3 (modified to 2 by
# AP-1) destroys one Seraphim, the remaining rolls save.
#
# Plus: group partitioning, all three ordering constraints, wounded-model
# priority, invuln-vs-AP choice, and excess-attacks-lost.
#
# Usage: godot --headless --path . -s tests/test_iss041_allocation_groups.gd

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

func _celestine_unit() -> Dictionary:
	# Attached unit: 4 Seraphim (W1 Sv3+), 2 Geminae (W1 Sv3+ InSv4+),
	# Celestine (CHARACTER, W6 Sv2+ InSv4+).
	var models = []
	for i in range(4):
		models.append({"id": "ser%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"save": 3, "invuln": 0})
	for i in range(2):
		models.append({"id": "gem%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"save": 3, "invuln": 4})
	models.append({"id": "celestine", "alive": true, "wounds": 6, "current_wounds": 6,
		"save": 2, "invuln": 4, "is_character": true})
	return {"meta": {"keywords": ["INFANTRY", "CHARACTER"], "stats": {}}, "models": models}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss041_allocation_groups ===\n")
	var unit = _celestine_unit()

	print("-- 05.03 step 1: create groups --")
	var groups = Allocation.build_groups(unit)
	_check("three groups: Seraphim, Geminae, Celestine", groups.size() == 3, str(groups.size()))
	var char_groups = groups.filter(func(g): return g.character)
	var nc_groups = groups.filter(func(g): return not g.character)
	_check("one CHARACTER group (Celestine alone)",
		char_groups.size() == 1 and char_groups[0].model_indices == [6])
	_check("non-CHARACTER models grouped by identical W/Sv/InSv",
		nc_groups.size() == 2 and nc_groups[0].model_indices.size() + nc_groups[1].model_indices.size() == 6)

	print("\n-- 05.03 step 2: ordering constraints --")
	var gem_id = ""
	var ser_id = ""
	for g in nc_groups:
		if g.insv == 4: gem_id = g.id
		else: ser_id = g.id
	var char_id = char_groups[0].id
	_check("defender's chosen order (Geminae, Seraphim, Celestine) is legal",
		Allocation.validate_order(groups, [gem_id, ser_id, char_id]).valid)
	_check("CHARACTER before a non-CHARACTER group is illegal",
		not Allocation.validate_order(groups, [gem_id, char_id, ser_id]).valid)
	_check("default_order is legal",
		Allocation.validate_order(groups, Allocation.default_order(groups)).valid)

	# Wounded non-CHARACTER group must be first
	unit.models[0].current_wounds = 0  # leave alive=true? no — wound, not kill:
	unit.models[0].current_wounds = 1
	var unit2 = _celestine_unit()
	unit2.models[5].current_wounds = 0  # can't be: wounded means lost SOME wounds; W1 models can't be wounded-but-alive.
	# Use a W2 variant to test wounded-first:
	var unit3 = _celestine_unit()
	for m in unit3.models:
		if str(m.id).begins_with("ser"):
			m.wounds = 2
			m.current_wounds = 2
	unit3.models[0].current_wounds = 1  # a wounded Seraphim
	var groups3 = Allocation.build_groups(unit3)
	var ser3 = ""
	var gem3 = ""
	var char3 = ""
	for g in groups3:
		if g.character: char3 = g.id
		elif g.insv == 4: gem3 = g.id
		else: ser3 = g.id
	_check("wounded non-CHARACTER group must be first (Geminae-first now illegal)",
		not Allocation.validate_order(groups3, [gem3, ser3, char3]).valid
		and Allocation.validate_order(groups3, [ser3, gem3, char3]).valid)

	print("\n-- 05.04: the worked example (pg 22-23) --")
	# 5 wounding heavy-bolter hits, AP-1 D2; save rolls 1,1,3,5,6.
	var res = Allocation.apply_save_rolls(unit, groups, [gem_id, ser_id, char_id],
		[6, 1, 3, 1, 5], -1, 2)
	_check("two 1s destroy both Geminae (auto-fail, lowest first)",
		res.models_destroyed.has(4) and res.models_destroyed.has(5),
		str(res.models_destroyed))
	_check("the 3 (AP-1 -> 2 vs Sv3+) destroys one Seraphim",
		res.casualties == 3, str(res))
	_check("the 5 and 6 save (5-1=4 and 6-1=5 vs 3+; Geminae gone, Seraphim current)",
		res.events.filter(func(e): return e.result == "saved").size() == 2)
	_check("Celestine untouched (CHARACTER group last, never reached)",
		res.remaining[6] == 6)

	print("\n-- invuln choice + wounded priority + excess lost --")
	# Geminae-only: AP-4 makes armour impossible; InSv4+ ignores AP.
	var gem_unit = {"meta": {"keywords": [], "stats": {}}, "models": [
		{"id": "g0", "alive": true, "wounds": 2, "current_wounds": 1, "save": 3, "invuln": 4},
		{"id": "g1", "alive": true, "wounds": 2, "current_wounds": 2, "save": 3, "invuln": 4},
	]}
	var gg = Allocation.build_groups(gem_unit)
	var r2 = Allocation.apply_save_rolls(gem_unit, gg, Allocation.default_order(gg), [4, 2], -4, 1)
	_check("invuln 4+ ignores AP-4 (the 4 saves)",
		r2.events.filter(func(e): return e.result == "saved").size() == 1, str(r2.events))
	_check("damage goes to the wounded model first",
		r2.events.filter(func(e): return e.result == "damage")[0].model_index == 0)
	var r3 = Allocation.apply_save_rolls(gem_unit, gg, Allocation.default_order(gg),
		[1, 1, 1, 1, 1, 1, 1, 1], 0, 2)
	_check("excess attacks lost once the unit is destroyed",
		r3.casualties == 2 and r3.events.filter(func(e): return e.result == "lost").size() == 6,
		str(r3.events.size()))

	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
