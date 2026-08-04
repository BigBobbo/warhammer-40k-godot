extends SceneTree

# "Auto-allocate for maximum damage" must stop counting damage that cannot land.
#
# REPORTED: in the Fight phase, the attack dialog's auto-allocation ("Best
# Weapons ✨", which is also the plan the dialog opens on) pointed the WHOLE
# activation at one target and scored it on RAW expected damage. Raw damage
# counts points that never happen:
#
#   * damage past a model's last wound is lost — no spillover to the next model
#     (10e/11e);
#   * damage past the UNIT's last wound is lost too, and never spills onto
#     another unit at all.
#
# So the suggested plan cheerfully threw a whole squad's attacks at a unit it
# killed several times over, wasting most of them while other engaged enemies
# stood untouched — and the dialog reported the wasted damage as if it had
# landed.
#
# Asserted here (pure math + plan construction, no UI):
#   1. damage_breakdown() reports `effective_damage` — raw damage with BOTH
#      caps applied — alongside the raw figure it always printed.
#   2. The allocator fills a small target only up to its wound pool and sends
#      the surplus at the other engaged unit, SPLITTING one uniform section
#      across two targets when that is what it takes.
#   3. It still puts everything on one target when that target can absorb it
#      (no gratuitous spreading).
#   4. The weapon choice itself is overkill-aware: a D6 weapon no longer beats
#      a multi-attack D1 weapon against 1-wound models.
#
# Player-path coverage (the real dialog, real buttons, real screenshot) is
# tests/scenarios/sp/fight_auto_allocate_spillover.json.
#
# Usage: godot --headless --path . -s tests/test_fight_auto_allocate_overkill_11e.gd

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


# ── fixture ─────────────────────────────────────────────────────────────────
# A 10-model mob on one uniform melee weapon (ONE loadout section — the shape a
# uniform squad always has, and the one that cannot be spread by re-targeting a
# different section) engaged with a 3-wound chaff unit and a 15-wound elite one.

func _weapon(name: String, attacks: String, ws: String, s: String, ap: String, dmg: String) -> Dictionary:
	return {"name": name, "type": "Melee", "attacks": attacks, "weapon_skill": ws,
		"strength": s, "ap": ap, "damage": dmg, "abilities": []}

func _models(prefix: String, count: int, wounds: int, x: float, y: float) -> Array:
	var out: Array = []
	for i in range(count):
		out.append({"id": "%s_m%d" % [prefix, i], "alive": true, "wounds": wounds,
			"current_wounds": wounds, "base_mm": 32, "base_type": "circular",
			"position": {"x": x + float(i) * 2.0, "y": y}})
	return out

func _board() -> Dictionary:
	var b = {"units": {}, "meta": {}}
	b.units["MOB"] = {
		"id": "MOB", "owner": 1, "flags": {"charged_this_turn": true},
		"meta": {"name": "Mob", "keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 5, "wounds": 1},
			"weapons": [_weapon("Choppa", "3", "3", "5", "0", "1")]},
		"models": _models("MOB", 10, 1, 400, 400),
	}
	# 3 wounds in total: two models' worth of choppas already overkills it.
	b.units["GROTS"] = {
		"id": "GROTS", "owner": 2, "flags": {},
		"meta": {"name": "Grots", "keywords": ["INFANTRY"],
			"stats": {"toughness": 3, "save": 7, "wounds": 1},
			"weapons": [_weapon("Close combat weapon", "1", "5", "2", "0", "1")]},
		"models": _models("GROTS", 3, 1, 400, 424),
	}
	# 15 wounds — somewhere for the surplus to go.
	b.units["NOBZ"] = {
		"id": "NOBZ", "owner": 2, "flags": {},
		"meta": {"name": "Nobz", "keywords": ["INFANTRY"],
			"stats": {"toughness": 5, "save": 4, "wounds": 3},
			"weapons": [_weapon("Choppa", "3", "3", "5", "0", "1")]},
		"models": _models("NOBZ", 5, 3, 400, 376),
	}
	return b


func _plan_of(dialog) -> Dictionary:
	# target_id -> models assigned to it, off the dialog's own submitted plan.
	var out: Dictionary = {}
	for a in dialog.assignments:
		var tid := str(a.get("target", ""))
		out[tid] = int(out.get(tid, 0)) + (a.get("models", []) as Array).size()
	return out


func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_auto_allocate_overkill_11e ===\n")
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("-- damage_breakdown(): raw E[D] vs what actually lands --")
	var AAD = load("res://dialogs/AttackAssignmentDialog.gd")
	var board = _board()

	# Ten Boyz of choppas into three 1-wound Grots.
	var bd_grots: Dictionary = AAD.damage_breakdown(
		board.units.MOB.meta.weapons[0], board.units.GROTS, 10)
	_check("raw expected damage is unchanged (it is what the dice will show)",
		bd_grots.expected_damage > 12.0,
		"E[D]=%.2f" % float(bd_grots.expected_damage))
	_check("the defender's remaining wound pool is reported",
		is_equal_approx(float(bd_grots.wounds_remaining), 3.0),
		"pool=%.2f" % float(bd_grots.wounds_remaining))
	_check("effective damage is capped at the pool — the rest cannot land",
		is_equal_approx(float(bd_grots.effective_damage), 3.0),
		"effective=%.2f" % float(bd_grots.effective_damage))
	_check("the surplus is reported as overkill — most of this swing is thrown away",
		float(bd_grots.overkill_damage) > 0.7 * float(bd_grots.expected_damage),
		"overkill=%.2f of raw %.2f" % [float(bd_grots.overkill_damage), float(bd_grots.expected_damage)])

	# The same weapon into a target big enough to absorb it: nothing is wasted.
	var bd_nobz: Dictionary = AAD.damage_breakdown(
		board.units.MOB.meta.weapons[0], board.units.NOBZ, 10)
	_check("against a target that can absorb it, effective == raw",
		is_equal_approx(float(bd_nobz.effective_damage), float(bd_nobz.expected_damage)),
		"effective=%.2f raw=%.2f" % [float(bd_nobz.effective_damage), float(bd_nobz.expected_damage)])
	_check("and nothing is reported as overkill",
		float(bd_nobz.overkill_damage) < 0.05, "overkill=%.2f" % float(bd_nobz.overkill_damage))

	# PER-MODEL overkill (the older half of the leak) is inside the same figure:
	# a D6 weapon can still only take one wound off a 1-wound Grot.
	var d6_weapon = _weapon("Killsaw", "3", "3", "5", "0", "D6")
	var bd_d6: Dictionary = AAD.damage_breakdown(d6_weapon, board.units.GROTS, 1)
	var bd_d1: Dictionary = AAD.damage_breakdown(board.units.MOB.meta.weapons[0], board.units.GROTS, 1)
	_check("raw damage flatters the D6 weapon against 1-wound models",
		float(bd_d6.expected_damage) > float(bd_d1.expected_damage),
		"D6 raw=%.2f vs D1 raw=%.2f" % [float(bd_d6.expected_damage), float(bd_d1.expected_damage)])
	_check("effective damage does not — a D6 hit still removes exactly one Grot",
		is_equal_approx(float(bd_d6.effective_uncapped), float(bd_d1.effective_uncapped)),
		"D6 eff=%.3f vs D1 eff=%.3f" % [float(bd_d6.effective_uncapped), float(bd_d1.effective_uncapped)])

	print("\n-- the auto-allocated plan spreads instead of overkilling --")
	var game_state = root.get_node_or_null("GameState")
	if game_state == null:
		_check("GameState autoload reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		GameConstants.edition = prev_edition
		quit(1)
		return
	game_state.state = {
		"meta": {"phase": GameStateData.Phase.FIGHT, "active_player": 1, "battle_round": 1, "turn": 1},
		"units": board.units,
		"board": {"size": {"width": 44, "height": 60}},
		"players": {"1": {"cp": 0}, "2": {"cp": 0}},
	}
	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(game_state.state)

	var targets: Dictionary = phase._get_eligible_melee_targets("MOB")
	_check("both enemies are legal melee targets for the mob",
		targets.has("GROTS") and targets.has("NOBZ"), str(targets.keys()))

	# GROTS first in the list is the reported case exactly: the dialog opens on
	# the first target and used to dump the whole mob onto it.
	var ordered := {"GROTS": targets.get("GROTS", {"name": "Grots"}),
		"NOBZ": targets.get("NOBZ", {"name": "Nobz"})}
	var dialog = AAD.new()
	root.add_child(dialog)
	dialog.setup("MOB", ordered, phase)

	_check("the mob is ONE uniform loadout section (the shape that could not be spread before)",
		dialog._groups.size() == 1, "%d section(s)" % dialog._groups.size())

	var plan := _plan_of(dialog)
	print("  plan: %s" % str(plan))
	_check("the plan no longer sends the whole mob at the 3-wound unit",
		int(plan.get("GROTS", 0)) < 10, str(plan))
	_check("the chaff unit gets only the models it takes to clear its 3 wounds",
		int(plan.get("GROTS", 0)) > 0 and int(plan.get("GROTS", 0)) <= 3, str(plan))
	_check("every remaining model is sent at the OTHER engaged unit",
		int(plan.get("NOBZ", 0)) == 10 - int(plan.get("GROTS", 0)) and int(plan.get("NOBZ", 0)) > 0,
		str(plan))
	_check("all ten models are still in the plan exactly once",
		int(plan.get("GROTS", 0)) + int(plan.get("NOBZ", 0)) == 10, str(plan))

	var seen := {}
	var dupes := ""
	for a in dialog.assignments:
		for m in a.get("models", []):
			if seen.has(str(m)):
				dupes = str(m)
			seen[str(m)] = true
	_check("11e one-weapon-per-model still holds — no model appears twice",
		dupes == "", "duplicate model %s" % dupes)

	# The split plan has to survive the engine, not just the dialog: drive the
	# phase to a real MOB activation and validate BOTH halves of the split.
	phase.execute_action({"type": "END_PILE_IN", "player": 1})
	phase.execute_action({"type": "END_PILE_IN", "player": 2})
	var sel = phase.execute_action({"type": "SELECT_FIGHTER", "unit_id": "MOB", "player": 1})
	_check("the mob can be activated", sel.get("success", false), str(sel.get("error", "")))
	for a in dialog.assignments:
		var v = phase.validate_action({"type": "ASSIGN_ATTACKS", "unit_id": str(a.get("attacker", "")),
			"target_id": str(a.get("target", "")), "weapon_id": str(a.get("weapon", "")),
			"attacking_models": a.get("models", []), "player": 1})
		_check("the engine accepts the split plan's %s assignment" % str(a.get("target", "")),
			v.get("valid", false), str(v.get("errors", [])))

	print("\n-- a target that CAN absorb the mob still gets all of it --")
	# Same mob, only the elite unit engaged: there is nothing to spread onto and
	# nothing wasted, so the plan must stay whole.
	var dialog2 = AAD.new()
	root.add_child(dialog2)
	dialog2.setup("MOB", {"NOBZ": targets.get("NOBZ", {"name": "Nobz"})}, phase)
	var plan2 := _plan_of(dialog2)
	_check("single-target activation is unchanged — all ten models, one target",
		int(plan2.get("NOBZ", 0)) == 10 and plan2.size() == 1, str(plan2))
	_check("and it is not split for no reason", not bool(dialog2._groups[0].split),
		"split=%s" % str(dialog2._groups[0].split))

	print("\n-- the surplus is reported, not silently counted as damage --")
	# Force the reported plan (everything onto the 3-wound unit) and read the
	# dialog's own summary back: it must say what is being thrown away.
	dialog._groups[0].split = false
	dialog._groups[0].lines = [{"weapon": "choppa_melee", "count": 10, "target": "GROTS"}]
	dialog._rebuild_split_rows()
	dialog._rebuild_assignments()
	var summary_text := str(dialog.assignments_display.get_parsed_text())
	print("  summary: %s" % summary_text.replace("\n", " | "))
	_check("the assignments box warns that the plan overkills its target",
		"Overkill" in summary_text, summary_text)
	_check("and names the unit it is over-committed against",
		"Grots" in summary_text, summary_text)
	_check("and prints what actually lands next to the raw total",
		"lands" in summary_text, summary_text)

	dialog.queue_free()
	dialog2.queue_free()
	GameConstants.edition = prev_edition
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
