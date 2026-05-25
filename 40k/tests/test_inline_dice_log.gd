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
	_test_dice_row_visual_wrap_size()
	_test_game_log_panel_records_dice_row()
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

func _test_dice_row_visual_wrap_size() -> void:
	var d = DiceRowVisualScript.new()
	# 25 dice should wrap to 3 rows (MAX_DICE_PER_ROW=10)
	var rolls := []
	for i in range(25):
		rolls.append(4)
	d.set_dice(rolls, 3, true)
	var expected_rows := 3
	var expected_h := expected_rows * DiceRowVisualScript.DIE_SIZE + (expected_rows - 1) * DiceRowVisualScript.ROW_SPACING
	_check("25 dice -> 3-row min height", d.custom_minimum_size.y == expected_h,
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
