extends SceneTree

# Headless smoke test for the inline-dice-graphics refactor of GameLogPanel.
# Verifies:
#   1. DiceRowVisual can be instantiated and sized correctly.
#   2. GameLogPanel._on_dice_roll_recorded produces an HBox containing a
#      DiceRowVisual when a combat card is active.
#
# Run with:
#   godot --headless --script res://tests/test_inline_dice_log.gd

const GameLogPanelScript := preload("res://scripts/GameLogPanel.gd")
const DiceRowVisualScript := preload("res://scripts/DiceRowVisual.gd")

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	print("=== Inline Dice Log Smoke Test ===")

	_test_dice_row_visual_basic()
	_test_dice_row_visual_empty()
	_test_dice_row_visual_threshold_colors()
	_test_dice_row_visual_grouping()
	_test_dice_row_visual_grouped_single_row()
	_test_dice_row_visual_single_die_no_count()
	_test_dice_row_visual_ungrouped_wrap_size()
	_test_game_log_panel_records_dice_row()
	_test_game_log_panel_detail_dice_row()
	_test_game_log_panel_simple_card_dice_icons()
	_test_game_log_panel_skips_when_no_combat()

	print("\n=== Result: %d passed / %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  PASS  %s" % name)
	else:
		_failed += 1
		print("  FAIL  %s — %s" % [name, detail])

func _test_dice_row_visual_basic() -> void:
	var d = DiceRowVisualScript.new()
	d.set_dice([1, 3, 6, 4], 3, true)
	_check("DiceRowVisual basic min size > 0", d.custom_minimum_size.x > 0 and d.custom_minimum_size.y > 0,
		"got %s" % str(d.custom_minimum_size))
	d.free()

func _test_dice_row_visual_empty() -> void:
	var d = DiceRowVisualScript.new()
	d.set_dice([], 0, false)
	_check("DiceRowVisual empty min size is zero", d.custom_minimum_size == Vector2.ZERO,
		"got %s" % str(d.custom_minimum_size))
	d.free()

func _test_dice_row_visual_threshold_colors() -> void:
	var d = DiceRowVisualScript.new()
	d.set_dice([1, 3, 6], 3, true)
	# Inspect color logic via private helper
	_check("die value 6 -> CRITICAL gold", d._get_die_color(6) == DiceRowVisualScript.COLOR_CRITICAL)
	_check("die value 1 -> FUMBLE red", d._get_die_color(1) == DiceRowVisualScript.COLOR_FUMBLE)
	_check("die value 3 (>=threshold 3) -> SUCCESS green", d._get_die_color(3) == DiceRowVisualScript.COLOR_SUCCESS)
	_check("die value 2 (<threshold 3) -> FAIL gray", d._get_die_color(2) == DiceRowVisualScript.COLOR_FAIL)
	d.free()

func _test_dice_row_visual_grouping() -> void:
	# [1, 1, 2, 6] -> three groups: (1 x2), (2 x1), (6 x1), sorted ascending.
	var d = DiceRowVisualScript.new()
	d.set_dice([1, 1, 2, 6], 3, true)
	var groups = d.get_value_groups()
	_check("grouping yields 3 distinct values", groups.size() == 3,
		"got %s" % str(groups))
	_check("group order/values/counts correct",
		groups == [[1, 2], [2, 1], [6, 1]],
		"got %s" % str(groups))
	d.free()

func _test_dice_row_visual_grouped_single_row() -> void:
	# 25 identical dice collapse to one group -> a single-row (DIE_SIZE tall) icon.
	var d = DiceRowVisualScript.new()
	var rolls := []
	for i in range(25):
		rolls.append(4)
	d.set_dice(rolls, 3, true)
	_check("25 identical dice -> 1 group", d.get_value_groups() == [[4, 25]],
		"got %s" % str(d.get_value_groups()))
	_check("grouped row is one die tall", d.custom_minimum_size.y == DiceRowVisualScript.DIE_SIZE,
		"got y=%s expected %s" % [str(d.custom_minimum_size.y), str(DiceRowVisualScript.DIE_SIZE)])
	d.free()

func _test_dice_row_visual_single_die_no_count() -> void:
	# A single die (e.g. an Advance roll) shows just the icon, no "x1" label.
	var single = DiceRowVisualScript.new()
	single.set_dice([4], 0, false)
	_check("single die width == DIE_SIZE (no x1 label)",
		single.custom_minimum_size.x == DiceRowVisualScript.DIE_SIZE,
		"got x=%s expected %s" % [str(single.custom_minimum_size.x), str(DiceRowVisualScript.DIE_SIZE)])
	single.free()

	# Count-of-1 groups inside a multi-die roll also drop the "x1" label, so the
	# row is narrower than if every group carried a count.
	var mixed = DiceRowVisualScript.new()
	mixed.set_dice([1, 1, 2, 6], 3, true)
	# Groups: (1 x2 -> labelled), (2 -> bare), (6 -> bare). Width = labelled cell
	# + 2 bare die cells + 2 group gaps.
	var labelled_w = DiceRowVisualScript.DIE_SIZE + DiceRowVisualScript.COUNT_GAP + mixed._measure_count(2)
	var expected_w = labelled_w + DiceRowVisualScript.DIE_SIZE + DiceRowVisualScript.DIE_SIZE \
		+ 2 * DiceRowVisualScript.GROUP_SPACING
	_check("singleton groups omit x1 in width", mixed.custom_minimum_size.x == expected_w,
		"got x=%s expected %s" % [str(mixed.custom_minimum_size.x), str(expected_w)])
	mixed.free()

func _test_dice_row_visual_ungrouped_wrap_size() -> void:
	# Legacy ungrouped mode still wraps 25 dice to 3 rows (MAX_DICE_PER_ROW=10).
	var d = DiceRowVisualScript.new()
	var rolls := []
	for i in range(25):
		rolls.append(4)
	d.set_dice(rolls, 3, true, false)
	var expected_rows := 3
	var expected_h := expected_rows * DiceRowVisualScript.DIE_SIZE + (expected_rows - 1) * DiceRowVisualScript.ROW_SPACING
	_check("ungrouped 25 dice -> 3-row min height", d.custom_minimum_size.y == expected_h,
		"got y=%s expected %s" % [str(d.custom_minimum_size.y), str(expected_h)])
	d.free()

func _test_game_log_panel_records_dice_row() -> void:
	# Build a GameLogPanel and start a combat card so the dice container exists.
	var panel = GameLogPanelScript.new()
	get_root().add_child(panel)
	panel._ready()
	# Manually create the card UI by calling _start_combat_card via the public-ish path
	panel._create_card("Test shooter shoots Target", "combat_header", false)

	if panel._current_combat_dice_container == null:
		_check("combat card creates dice container", false, "container is null")
		panel.queue_free()
		return
	_check("combat card creates dice container", true)

	var before_count: int = panel._current_combat_dice_container.get_child_count()

	# Synthesize a to_hit dice roll entry like DiceHistoryPanel would emit
	var fake_entry := {
		"data": {
			"context": "to_hit",
			"rolls_raw": [1, 3, 4, 6, 5],
			"threshold": "3+",
			"successes": 4
		}
	}
	panel._on_dice_roll_recorded(fake_entry)

	var after_count: int = panel._current_combat_dice_container.get_child_count()
	_check("to_hit roll appends a row", after_count == before_count + 1,
		"before=%d after=%d" % [before_count, after_count])

	# Inspect the appended row's children for a DiceRowVisual instance
	var row = panel._current_combat_dice_container.get_child(after_count - 1)
	var has_dice_visual: bool = false
	for c in row.get_children():
		if c is DiceRowVisualScript:
			has_dice_visual = true
			break
	_check("appended row contains a DiceRowVisual", has_dice_visual)

	panel.queue_free()

func _test_game_log_panel_detail_dice_row() -> void:
	# A combat-detail line containing a dice array must render the array as a
	# grouped DiceRowVisual row in the collapsible details container — NOT as a
	# plain "[1, 1, 2, 6]" number array.
	var panel = GameLogPanelScript.new()
	get_root().add_child(panel)
	panel._ready()
	panel._create_card("Test shooter shoots Target", "combat_header", false)

	if panel._current_combat_details_container == null:
		_check("combat card creates details container", false, "container is null")
		panel.queue_free()
		return
	_check("combat card creates details container", true)

	# A dice-bearing detail line -> grouped DiceRowVisual row.
	panel._create_card("  To Hit: needed 3+ — rolled [1, 1, 2, 6] — 2/4 hit", "combat_detail", false)
	# A text-only detail line -> plain label (no DiceRowVisual).
	panel._create_card("    Modifiers: +1 to hit", "combat_detail", false)

	_check("two detail rows added", panel._current_combat_details_container.get_child_count() == 2,
		"got %d" % panel._current_combat_details_container.get_child_count())
	_check("dice detail line rendered as grouped DiceRowVisual", panel.combat_detail_row_has_visual(0))
	_check("text-only detail line has no DiceRowVisual", not panel.combat_detail_row_has_visual(1))

	panel.queue_free()

func _test_game_log_panel_simple_card_dice_icons() -> void:
	# Non-combat log lines (advance/charge/overwatch) that contain a [n, ...]
	# dice array must render the array as dice icons in their simple card.
	var panel = GameLogPanelScript.new()
	get_root().add_child(panel)
	panel._ready()
	# setup() builds the card container as part of the full UI; for this unit
	# test we just need the container the simple cards are appended to.
	panel._card_container = VBoxContainer.new()
	panel.add_child(panel._card_container)

	# Advance line — single die, no count label.
	panel._create_card("Intercessors advances: rolled [4] — total move = 10\"", "p1_action", false)
	_check("advance simple card renders dice icon", panel.last_simple_card_has_dice_visual())

	# Charge line — two dice.
	panel._create_card("Boyz charge roll: [5, 3] = 8\" vs 6.0\" needed - SUCCESS", "p2_action", false)
	_check("charge simple card renders dice icons", panel.last_simple_card_has_dice_visual())

	# Plain line — no dice array -> no DiceRowVisual.
	panel._create_card("Intercessors holds position", "p1_action", false)
	_check("plain simple card has no dice icon", not panel.last_simple_card_has_dice_visual())

	# line_has_dice_array helper sanity.
	_check("line_has_dice_array true for [4]", panel.line_has_dice_array("rolled [4]"))
	_check("line_has_dice_array false for [+1 STRENGTH]", not panel.line_has_dice_array("gain [+1 STRENGTH]"))

	panel.queue_free()

func _test_game_log_panel_skips_when_no_combat() -> void:
	# Without a combat card, _on_dice_roll_recorded should no-op (not crash).
	var panel = GameLogPanelScript.new()
	get_root().add_child(panel)
	panel._ready()
	# No combat card started.
	panel._on_dice_roll_recorded({
		"data": {"context": "to_hit", "rolls_raw": [3], "threshold": "3+", "successes": 1}
	})
	_check("no-combat-card path no-ops cleanly", true)
	panel.queue_free()
