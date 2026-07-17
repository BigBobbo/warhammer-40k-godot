extends SceneTree

# ISS-045: defender allocation-group flow (11e 05.03-05.04).
#  - RulesEngine.resolve_allocation_batch_11e: attached characters folded
#    into the virtual unit (per-CHARACTER groups), defender order honored,
#    invalid orders fall back to the default legal order, diffs remapped
#    to the source units, outcome matches an independent reimplementation
#    of the 05.04 walk (lowest→highest vs the current group)
#  - AllocationGroupOverlay: group cards built, illegal orders (CHARACTER
#    before non-CHARACTER) disable Confirm live, confirm applies the batch
#    to GameState and allocation_complete carries the summary
#
# Usage: godot --headless --path . -s tests/test_iss045_allocation_overlay.gd

var passed := 0
var failed := 0
var summary_received: Dictionary = {}

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

## Seraphim-style bodyguard (4 × W1 Sv3+) with an attached Celestine-style
## CHARACTER unit (W6 Sv2+ InSv4+), linked the way
## CharacterAttachmentManager does it.
func _attached_units() -> Dictionary:
	var seraphim_models = []
	for i in range(4):
		seraphim_models.append({"id": "s%d" % i, "alive": true, "wounds": 1,
			"current_wounds": 1, "base_mm": 32, "base_type": "circular",
			"position": {"x": 300, "y": 100 + float(i * 35)}})
	return {
		"U_SERAPHIM": {"id": "U_SERAPHIM", "owner": 2, "flags": {},
			"attachment_data": {"attached_characters": ["U_CELESTINE"]},
			"meta": {"name": "Seraphim", "keywords": ["INFANTRY"],
				"stats": {"toughness": 3, "save": 3, "wounds": 1}},
			"models": seraphim_models},
		"U_CELESTINE": {"id": "U_CELESTINE", "owner": 2, "attached_to": "U_SERAPHIM",
			"flags": {},
			"meta": {"name": "Celestine", "keywords": ["INFANTRY", "CHARACTER"],
				"stats": {"toughness": 3, "save": 2, "wounds": 6, "invuln": 4}},
			"models": [{"id": "c0", "alive": true, "wounds": 6, "current_wounds": 6,
				"invuln": 4, "save": 2, "base_mm": 32, "base_type": "circular",
				"position": {"x": 300, "y": 250}}]},
	}

func _save_data(wounds: int) -> Dictionary:
	return {
		"target_unit_id": "U_SERAPHIM", "target_unit_name": "Seraphim",
		"shooter_unit_id": "U_SHOOTER", "shooter_unit_name": "Ork Lootas",
		"weapon_name": "Test Cannon",
		"wounds_to_save": wounds, "total_wounds": wounds,
		"ap": -3, "damage": 1, "damage_raw": "1", "base_save": 3,
		"is_psychic": false, "has_devastating_wounds": false, "devastating_wounds": 0,
		"melta_bonus": 0,
	}

## Independent 05.04 walk: sorted rolls vs current group (Seraphim Sv3+
## AP-3 -> armour saves on 6+; Celestine InSv4+ unmodified).
func _expected_outcome(rolls: Array) -> Dictionary:
	var sorted_rolls = rolls.duplicate()
	sorted_rolls.sort()
	var seraphim_alive := 4
	var celestine_wounds := 6
	for roll in sorted_rolls:
		if seraphim_alive > 0:
			var saved = roll != 1 and roll + (-3) >= 3
			if not saved:
				seraphim_alive -= 1
		elif celestine_wounds > 0:
			var saved_c = roll != 1 and roll >= 4
			if not saved_c:
				celestine_wounds -= 1
	return {"seraphim_alive": seraphim_alive, "celestine_wounds": celestine_wounds}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss045_allocation_overlay ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	var game_state = root.get_node_or_null("GameState")
	_check("autoloads present", rules != null and game_state != null)
	GameConstants.edition = 11

	print("-- resolve_allocation_batch_11e: attached unit, order honored --")
	var board = {"units": _attached_units(), "meta": {}}
	# Find a seed where the 6 save rolls reach Celestine (>= 5 sub-6 rolls
	# kill the 4 Seraphim, the rest hit Celestine's 4++).
	var seed := -1
	var exp = {}
	for s in range(2000):
		var probe = rules.RNGService.new(s).roll_d6(6)
		var out = _expected_outcome(probe)
		if out.seraphim_alive == 0 and out.celestine_wounds < 6:
			seed = s
			exp = out
			break
	_check("seed found (damage reaches the CHARACTER)", seed != -1)

	var batch = rules.resolve_allocation_batch_11e(_save_data(6), [], board, rules.RNGService.new(seed))
	_check("groups: non-CHARACTER pool + per-CHARACTER group from the ATTACHED unit",
		batch.groups.size() == 2, str(batch.groups))
	_check("default order: CHARACTER last", str(batch.order_used[-1]).begins_with("char"),
		str(batch.order_used))
	_check("save batch is one roll per wound", batch.save_rolls.size() == 6)
	# Apply diffs to a copy and compare against the independent walk.
	var b2 = {"units": _attached_units(), "meta": {}}
	for diff in batch.diffs:
		var parts = str(diff.path).split(".")
		b2.units[parts[1]].models[int(parts[3])][parts[4]] = diff.value
	var alive := 0
	for m in b2.units["U_SERAPHIM"].models:
		if m.get("alive", true):
			alive += 1
	_check("05.04 walk reproduced: Seraphim casualties match (alive=%d)" % exp.seraphim_alive,
		alive == exp.seraphim_alive, "engine alive=%d" % alive)
	_check("CHARACTER diffs remapped to U_CELESTINE (wounds=%d)" % exp.celestine_wounds,
		int(b2.units["U_CELESTINE"].models[0].current_wounds) == exp.celestine_wounds,
		str(b2.units["U_CELESTINE"].models[0]))

	# Invalid order (CHARACTER first) falls back to the default legal order.
	var char_first = [batch.order_used[1], batch.order_used[0]]
	var batch2 = rules.resolve_allocation_batch_11e(_save_data(6), char_first, board, rules.RNGService.new(seed))
	_check("illegal order (CHARACTER first) rejected -> default order used",
		str(batch2.order_used) == str(batch.order_used), str(batch2.order_used))

	print("\n-- AllocationGroupOverlay (headless UI) --")
	# Inject the fixture into live GameState for the overlay path.
	for uid in _attached_units():
		game_state.state.units[uid] = _attached_units()[uid]
	rules.RNGService.test_mode_seed = seed
	var overlay = AllocationGroupOverlay.new()
	root.add_child(overlay)
	overlay.allocation_complete.connect(func(s): summary_received = s)
	overlay.setup(_save_data(6), 2)
	# The info line must name the FIRING unit (not just the weapon) so the
	# defender can tell who is shooting them.
	var info_label = overlay.get_node_or_null("Center/Panel/VBox/Info")
	_check("info line names the firing unit AND the weapon",
		info_label != null and "Ork Lootas" in info_label.text and "Test Cannon" in info_label.text,
		str(info_label.text) if info_label != null else "<no Info label>")
	_check("two group cards rendered", overlay.group_list.get_child_count() == 2)
	_check("default order valid: Confirm enabled", not overlay.confirm_button.disabled)
	overlay._on_move(1, -1)  # try to put the CHARACTER group first
	_check("CHARACTER moved before non-CHARACTER: Confirm DISABLED + error shown",
		overlay.confirm_button.disabled and overlay.error_label.text != "",
		overlay.error_label.text)
	overlay._on_move(0, 1)  # restore
	_check("restored legal order: Confirm re-enabled", not overlay.confirm_button.disabled)
	overlay._on_confirm_pressed()
	_check("results panel shown after confirm", overlay.result_panel.visible)
	# test_mode_seed derives a hashed per-instance seed, so validate the
	# overlay's outcome against the independent 05.04 walk over the rolls
	# the overlay actually batch-rolled.
	var ov_exp = _expected_outcome(overlay.batch_result.get("save_rolls", []))
	var gs_alive := 0
	for m in game_state.state.units["U_SERAPHIM"].models:
		if m.get("alive", true):
			gs_alive += 1
	_check("batch applied to GameState (Seraphim alive=%d)" % ov_exp.seraphim_alive,
		gs_alive == ov_exp.seraphim_alive, "alive=%d" % gs_alive)
	_check("GameState Celestine wounds match the 05.04 walk (%d)" % ov_exp.celestine_wounds,
		int(game_state.state.units["U_CELESTINE"].models[0].current_wounds) == ov_exp.celestine_wounds,
		str(game_state.state.units["U_CELESTINE"].models[0]))
	overlay._on_done_pressed()
	_check("allocation_complete summary: is_allocation_11e + diffs + counts",
		summary_received.get("is_allocation_11e", false)
		and not summary_received.get("diffs", []).is_empty()
		and summary_received.has("saves_failed"), str(summary_received.keys()))

	rules.RNGService.test_mode_seed = -1
	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
