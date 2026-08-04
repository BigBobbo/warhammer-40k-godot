extends AcceptDialog

# BattleShockSequenceDialog — the Command-phase Battle-shock ROLL CALL.
#
# THE PROBLEM THIS SOLVES: battle-shock tests used to resolve invisibly. Pressing
# "End Command Phase" auto-resolved every outstanding test in one silent loop and
# the only trace was a handful of game-log lines. The player never saw WHICH unit
# was testing, never saw the dice, and had no beat in which to spend Insane
# Bravery or a Command Re-roll.
#
# THE SHAPE: one unit at a time, in a fixed order, presented like the
# pre-deployment roll-off — the same big parchment/gold D6 faces (DiceFaceVisual)
# tumbling before they settle on the real values. Per unit the player sees:
#   * where they are in the queue ("TEST 2 OF 4")
#   * the unit, its owner colour, and how chewed up it is ("4 of 10 models")
#   * WHY it has to test (Below Half-strength / At Half-strength / already shocked)
#   * what it needs ("Needs 8+ on 2D6")
#   * the dice landing, then a pass/fail verdict that spells out the consequence
# ...and then clicks Next to walk to the following unit.
#
# The controller (CommandController) owns the camera pan, the board highlight and
# the actual action dispatch; this dialog is the presentation + the buttons. It
# is BOTTOM-ANCHORED on purpose (DialogUtils.popup_at_bottom): the camera is
# parked on the unit being tested, so the board must stay visible.
#
# Signal/API contract (consumed by CommandController + tests/scenarios):
#   signals: roll_requested(unit_id), insane_bravery_requested(unit_id),
#            command_reroll_requested(unit_id), command_reroll_declined(unit_id),
#            next_requested(), auto_resolve_rest_requested(), closed()
#   methods: setup(player), show_entry(entry, index, total), play_roll(...),
#            show_reroll_offer(...), show_auto_pass(...), show_summary(...)
#   button node names: RollButton / InsaneBraveryButton / NextButton /
#            AutoResolveButton / CommandRerollButton / KeepRollButton / CloseButton

signal roll_requested(unit_id: String)
signal insane_bravery_requested(unit_id: String)
signal command_reroll_requested(unit_id: String)
signal command_reroll_declined(unit_id: String)
signal next_requested()
signal auto_resolve_rest_requested()
signal closed()

const DiceFace = preload("res://scripts/DiceFaceVisual.gd")

enum Mode {
	AWAITING_ROLL,
	ROLLING,
	REROLL_OFFER,
	SHOWING_RESULT,
	SUMMARY,
}

# Tumble timing, mirroring RollOffDialog so the two flows feel like the same
# game. Scaled by the player's Animation Speed setting.
const ROLL_ANIM_DURATION := 0.95
const ROLL_TICK_INTERVAL := 0.06

# Verdict banner heights: one line per test, up to three for the closing tally.
# WH_RED (#9A1115) is a parchment colour — on this dark panel the FAILED banner
# was all but unreadable. This is the same red pushed bright enough to carry on
# a dark background while still reading as "bad".
const FAIL_RED := "#E8574E"
const PASS_GREEN := "#7ACB7A"

const VERDICT_H_SINGLE := 34
const VERDICT_H_SUMMARY := 108

var _mode: int = Mode.AWAITING_ROLL
var _player: int = 0
var _entry: Dictionary = {}          # the unit currently under test
var _index: int = 0                  # 0-based position in the queue
var _total: int = 0                  # queue length
var _remaining_after: int = 0        # units still to test after this one
var _result: Dictionary = {}         # the settled test result
var _pending_payload: Dictionary = {}
var _reroll_note: String = ""        # "Re-rolled 3 + 2 = 5" strapline after a Command Re-roll
# The dice start tumbling the instant the player presses Roll and land when the
# real result arrives. Single-player resolves synchronously, but a networked
# seat gets the result a round-trip later — so the tumble is open-ended with a
# MINIMUM duration rather than a fixed one that assumes the answer is already in.
var _tumble_started_ms: int = 0
var _settle_timer: SceneTreeTimer = null

# UI references
var _content: VBoxContainer
var _heading: Label
var _unit_label: Label
var _strength_label: Label
var _reason_label: Label
var _target_label: Label
var _dice_row: HBoxContainer
var _die_a: Control
var _die_b: Control
var _total_label: Label
var _reroll_label: Label
var _verdict: RichTextLabel
var _effects_label: Label
var _button_bar: HBoxContainer
var _tick_timer: Timer


func _init() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)


func setup(player: int) -> void:
	_player = player
	title = "Battle-shock Tests"
	min_size = DialogConstants.MEDIUM
	get_ok_button().visible = false
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
	_build_ui()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.add_theme_constant_override("separation", 8)
	# Fixed width so the autowrap labels measure their real height (see the
	# DialogUtils.popup_centered_capped docs for the bug this avoids).
	_content.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)
	add_child(_content)

	_heading = Label.new()
	_heading.name = "HeadingLabel"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_content.add_child(_heading)

	_content.add_child(_make_rule())

	_unit_label = Label.new()
	_unit_label.name = "UnitLabel"
	_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label.add_theme_font_size_override("font_size", 24)
	_content.add_child(_unit_label)

	_strength_label = Label.new()
	_strength_label.name = "StrengthLabel"
	_strength_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strength_label.add_theme_font_size_override("font_size", 17)
	_strength_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_BONE)
	_content.add_child(_strength_label)

	_reason_label = Label.new()
	_reason_label.name = "ReasonLabel"
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.add_theme_font_size_override("font_size", 17)
	_reason_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_reason_label)

	_target_label = Label.new()
	_target_label.name = "TargetLabel"
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.add_theme_font_size_override("font_size", 19)
	_target_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_content.add_child(_target_label)

	# Two big dice + a running total, laid out like the roll-off.
	_dice_row = HBoxContainer.new()
	_dice_row.name = "DiceRow"
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("separation", 18)
	_dice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_dice_row)

	_die_a = _make_die("DieA")
	_die_b = _make_die("DieB")
	_dice_row.add_child(_die_a)
	_dice_row.add_child(_die_b)

	_total_label = Label.new()
	_total_label.name = "TotalLabel"
	_total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 26)
	_total_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_dice_row.add_child(_total_label)

	_reroll_label = Label.new()
	_reroll_label.name = "RerollNoteLabel"
	_reroll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reroll_label.add_theme_font_size_override("font_size", 16)
	_reroll_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.6))
	_reroll_label.visible = false
	_content.add_child(_reroll_label)

	_verdict = RichTextLabel.new()
	_verdict.name = "VerdictLabel"
	_verdict.bbcode_enabled = true
	# fit_content is DELIBERATELY off. A fit_content RichTextLabel reports its
	# height from the text wrapped at its CURRENT width, so while the window is
	# re-laying-out it briefly measures ~one character per line and returns a
	# towering minimum — which AcceptDialog bakes into the window size and never
	# gives back. That is what made the card balloon to full screen height and
	# climb off the bottom edge the moment a verdict was rendered. A fixed height
	# (bumped only for the multi-line summary) breaks the loop.
	_verdict.fit_content = false
	_verdict.scroll_active = false
	_verdict.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, VERDICT_H_SINGLE)
	_content.add_child(_verdict)

	_effects_label = Label.new()
	_effects_label.name = "EffectsLabel"
	_effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effects_label.add_theme_font_size_override("font_size", 15)
	_effects_label.add_theme_color_override("font_color", Color(0.8, 0.55, 0.55))
	_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Pin the wrap width so the autowrap height is measured against a stable
	# width instead of whatever the window is mid-resize (same trap as above).
	_effects_label.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, 0)
	_effects_label.visible = false
	_content.add_child(_effects_label)

	_button_bar = HBoxContainer.new()
	_button_bar.name = "ButtonBar"
	_button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_bar.add_theme_constant_override("separation", 10)
	_content.add_child(_button_bar)

	_tick_timer = Timer.new()
	_tick_timer.name = "TumbleTimer"
	_tick_timer.one_shot = false
	_tick_timer.wait_time = ROLL_TICK_INTERVAL
	_tick_timer.timeout.connect(_on_roll_tick)
	add_child(_tick_timer)


func _make_rule() -> ColorRect:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g,
		WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sep


func _make_die(node_name: String) -> Control:
	var die := DiceFace.new()
	die.name = node_name
	die.custom_minimum_size = Vector2(84, 84)
	die.value = 1
	die.pivot_offset = Vector2(42, 42)
	return die


# --- Public API --------------------------------------------------------------

## Present unit `entry` (a get_battle_shock_queue() row) as test index+1 of total.
func show_entry(entry: Dictionary, index: int, total: int, remaining_after: int) -> void:
	_entry = entry
	_index = index
	_total = total
	_remaining_after = remaining_after
	_result = {}
	_reroll_note = ""
	_mode = Mode.AWAITING_ROLL
	_refresh()


## Start the dice tumbling. The values are NOT known yet — call settle_result()
## or settle_reroll_offer() when the phase reports back.
func begin_tumble() -> void:
	_mode = Mode.ROLLING
	_pending_payload = {}
	_tumble_started_ms = Time.get_ticks_msec()
	_refresh()
	_tick_timer.start()
	var sm = get_node_or_null("/root/DiceSoundManager")
	if sm and sm.has_method("play_roll_tick"):
		sm.play_roll_tick()


## Land the tumbling dice on `result` and show the pass/fail verdict.
func settle_result(result: Dictionary) -> void:
	_result = result
	_queue_settle("result", int(result.get("die1", 1)), int(result.get("die2", 1)))


## Land on the FAILED roll and offer the Command Re-roll, keeping the dice on
## screen while the player decides — the old flow popped a separate dialog over
## the top with the dice nowhere in sight.
func settle_reroll_offer(roll_context: Dictionary) -> void:
	_pending_payload = roll_context
	var rolls: Array = roll_context.get("original_rolls", [1, 1])
	_queue_settle("reroll_offer",
		int(rolls[0]) if rolls.size() > 0 else 1,
		int(rolls[1]) if rolls.size() > 1 else 1)


## A Command Re-roll was spent: note the discarded roll and tumble again.
func begin_reroll(original_rolls: Array) -> void:
	var old_total := 0
	for r in original_rolls:
		old_total += int(r)
	_reroll_note = "Command Re-roll — discarded %s = %d" % [
		" + ".join(original_rolls.map(func(r): return str(r))), old_total]
	begin_tumble()


## The dispatch was rejected (or never resolved) — put the card back the way it
## was so the player can try again instead of staring at "Rolling…" forever.
func cancel_roll() -> void:
	_tick_timer.stop()
	_settle_timer = null
	_mode = Mode.AWAITING_ROLL
	_refresh()


## Insane Bravery was spent — no dice are rolled at all.
func show_auto_pass(result: Dictionary) -> void:
	_result = result
	_mode = Mode.SHOWING_RESULT
	_refresh()


## End of the queue: a tally of what just happened.
func show_summary(passed: Array, failed: Array, auto_passed: Array) -> void:
	_mode = Mode.SUMMARY
	_result = {
		"summary_passed": passed,
		"summary_failed": failed,
		"summary_auto": auto_passed,
	}
	_refresh()


func is_rolling() -> bool:
	return _mode == Mode.ROLLING


func current_unit_id() -> String:
	return str(_entry.get("unit_id", ""))


# --- Tumble animation --------------------------------------------------------

func _tumble_duration() -> float:
	var speed: float = 1.0
	var settings = get_node_or_null("/root/SettingsService")
	if settings and "animation_speed" in settings:
		speed = maxf(float(settings.animation_speed), 0.25)
	return ROLL_ANIM_DURATION / speed


## Settle now if the dice have already tumbled long enough, otherwise hold the
## reveal until the minimum tumble time is up.
func _queue_settle(kind: String, die1: int, die2: int) -> void:
	if _mode != Mode.ROLLING:
		# settle without a tumble (e.g. a scripted/instant path) — just show it.
		_do_settle(kind, die1, die2)
		return
	var elapsed: float = float(Time.get_ticks_msec() - _tumble_started_ms) / 1000.0
	var remaining: float = maxf(_tumble_duration() - elapsed, 0.0)
	if remaining <= 0.001 or not is_inside_tree():
		_do_settle(kind, die1, die2)
		return
	_settle_timer = get_tree().create_timer(remaining)
	_settle_timer.timeout.connect(_do_settle.bind(kind, die1, die2))


func _on_roll_tick() -> void:
	# Tumble: random faces with a little jitter, exactly like the roll-off.
	_die_a.value = randi_range(1, 6)
	_die_b.value = randi_range(1, 6)
	_die_a.rotation = randf_range(-0.18, 0.18)
	_die_b.rotation = randf_range(-0.18, 0.18)
	_total_label.text = "= ?"


func _do_settle(kind: String, die1: int, die2: int) -> void:
	_settle_timer = null
	_tick_timer.stop()
	_die_a.value = die1
	_die_b.value = die2
	_die_a.rotation = 0.0
	_die_b.rotation = 0.0

	var sm = get_node_or_null("/root/DiceSoundManager")
	if sm and sm.has_method("play_settle"):
		sm.play_settle()

	_mode = Mode.REROLL_OFFER if kind == "reroll_offer" else Mode.SHOWING_RESULT
	_refresh()
	_pop(_die_a)
	_pop(_die_b)


func _pop(die: Control) -> void:
	die.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(die, "scale", Vector2(1.18, 1.18), 0.16)
	tween.tween_property(die, "scale", Vector2(1.0, 1.0), 0.10)


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _content == null:
		return
	# remove_child BEFORE queue_free: queue_free is deferred, so a same-frame
	# rebuild would find the old "RollButton"/"AutoResolveButton" still parented
	# and Godot would rename the new ones to "@RollButton@12". That silently
	# breaks every path-addressed click — the scenario harness, the tutorial
	# overlay and controller focus all look these buttons up by name. The
	# Insane Bravery card rebuilds in the SAME frame as the press, so this is
	# not theoretical.
	for child in _button_bar.get_children():
		_button_bar.remove_child(child)
		child.queue_free()

	if _mode == Mode.SUMMARY:
		_refresh_summary()
		DialogUtils.refit_bottom(self)
		return
	_verdict.custom_minimum_size.y = VERDICT_H_SINGLE

	var unit_name := str(_entry.get("unit_name", "Unit"))
	var ld := int(_entry.get("leadership", 7))
	var bonus := int(_entry.get("battle_shock_bonus", 0))

	# Re-show the per-unit rows the summary hides.
	_strength_label.visible = true
	_reason_label.visible = true
	_target_label.visible = true

	_heading.text = "BATTLE-SHOCK  ·  TEST %d OF %d" % [_index + 1, _total]
	_unit_label.text = unit_name
	_unit_label.add_theme_color_override("font_color",
		FactionPalettes.get_player_color(int(_entry.get("owner", _player))))
	_strength_label.text = str(_entry.get("strength_text", ""))
	_reason_label.text = str(_entry.get("reason_text", ""))

	var target := "Needs %d+ on 2D6  (Leadership %d)" % [ld, ld]
	if bonus > 0:
		target += "   ·   +%d Waaagh! Effigy" % bonus
	_target_label.text = target

	_reroll_label.visible = _reroll_note != ""
	_reroll_label.text = _reroll_note

	match _mode:
		Mode.AWAITING_ROLL:
			_dice_row.visible = true
			_die_a.highlight = DiceFace.Highlight.NONE
			_die_b.highlight = DiceFace.Highlight.NONE
			_die_a.value = 1
			_die_b.value = 1
			_total_label.text = ""
			_verdict.text = ""
			_effects_label.visible = false
			_add_awaiting_roll_buttons()
		Mode.ROLLING:
			_verdict.text = "[center][color=#D49761]Rolling…[/color][/center]"
			_effects_label.visible = false
			_die_a.highlight = DiceFace.Highlight.NONE
			_die_b.highlight = DiceFace.Highlight.NONE
		Mode.REROLL_OFFER:
			_render_dice_total()
			var ctx_total := int(_pending_payload.get("total", 0))
			_die_a.highlight = DiceFace.Highlight.LOSER
			_die_b.highlight = DiceFace.Highlight.LOSER
			_verdict.text = ("[center][color=%s][b]FAILED — %d vs Ld %d[/b][/color][/center]"
				% [FAIL_RED, ctx_total, ld])
			_effects_label.visible = true
			_effects_label.text = "Spend 1 CP to re-roll, or keep the roll and take the Battle-shock."
			_add_reroll_offer_buttons()
		Mode.SHOWING_RESULT:
			_render_result()
	# Re-measure and re-pin: popup_at_bottom()'s size_changed hook only
	# REPOSITIONS, so a card that swapped to taller/shorter content would keep
	# the stale height and drift off the bottom edge.
	DialogUtils.refit_bottom(self)


func _render_dice_total() -> void:
	var d1 := int(_die_a.value)
	var d2 := int(_die_b.value)
	var bonus := int(_entry.get("battle_shock_bonus", 0))
	if bonus > 0:
		_total_label.text = "= %d (+%d) = %d" % [d1 + d2, bonus, d1 + d2 + bonus]
	else:
		_total_label.text = "= %d" % (d1 + d2)


func _render_result() -> void:
	var passed: bool = bool(_result.get("test_passed", false))
	var auto_passed: bool = bool(_result.get("auto_passed", false))
	var ld := int(_entry.get("leadership", _result.get("leadership", 7)))
	var effective := int(_result.get("effective_roll", _result.get("roll_total", 0)))

	if auto_passed:
		# No dice were rolled — hide them rather than showing a meaningless pair.
		_dice_row.visible = false
		_verdict.text = "[center][color=#FFD966][b]AUTO-PASSED — INSANE BRAVERY[/b][/color][/center]"
		_effects_label.visible = true
		_effects_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.55))
		_effects_label.text = "1 CP spent. The test is passed automatically — no dice rolled."
	else:
		_dice_row.visible = true
		_render_dice_total()
		if passed:
			_die_a.highlight = DiceFace.Highlight.WINNER
			_die_b.highlight = DiceFace.Highlight.WINNER
			_effects_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
			if bool(_entry.get("was_battle_shocked", false)):
				_verdict.text = "[center][color=%s][b]PASSED — RECOVERED[/b][/color][/center]" % PASS_GREEN
				_effects_label.visible = true
				_effects_label.text = "%d vs Ld %d — no longer Battle-shocked." % [effective, ld]
			else:
				_verdict.text = "[center][color=%s][b]PASSED — holds its nerve[/b][/color][/center]" % PASS_GREEN
				_effects_label.visible = true
				_effects_label.text = "%d vs Ld %d — the unit is unaffected." % [effective, ld]
		else:
			_die_a.highlight = DiceFace.Highlight.TIE
			_die_b.highlight = DiceFace.Highlight.TIE
			_verdict.text = "[center][color=%s][b]FAILED — BATTLE-SHOCKED[/b][/color][/center]" % FAIL_RED
			_effects_label.visible = true
			_effects_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
			# Same wording as the on-token status tooltip, so the red ring the
			# player is about to see on the board reads as the same thing.
			_effects_label.text = "%d vs Ld %d — OC 0 · no Stratagems · no Actions · Desperate Escape when Falling Back. Re-test next Command phase to recover." % [effective, ld]

	_add_result_buttons()


func _refresh_summary() -> void:
	var passed: Array = _result.get("summary_passed", [])
	var failed: Array = _result.get("summary_failed", [])
	var auto: Array = _result.get("summary_auto", [])

	_heading.text = "BATTLE-SHOCK COMPLETE"
	_unit_label.text = "%d test%s resolved" % [
		passed.size() + failed.size() + auto.size(),
		"" if (passed.size() + failed.size() + auto.size()) == 1 else "s"]
	_unit_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	# HIDE rather than blank: an empty Label still claims a line plus the VBox
	# separation, which left a band of dead space above the tally.
	_strength_label.visible = false
	_reason_label.visible = false
	_target_label.visible = false
	_dice_row.visible = false
	_reroll_label.visible = false

	var lines: Array = []
	if failed.size() > 0:
		lines.append("[color=%s][b]Battle-shocked:[/b] %s[/color]" % [FAIL_RED, ", ".join(failed)])
	if passed.size() > 0:
		lines.append("[color=%s][b]Passed:[/b] %s[/color]" % [PASS_GREEN, ", ".join(passed)])
	if auto.size() > 0:
		lines.append("[color=#FFD966][b]Insane Bravery:[/b] %s[/color]" % ", ".join(auto))
	if lines.is_empty():
		lines.append("[color=#EBE1C7]No tests were required.[/color]")
	_verdict.text = "[center]%s[/center]" % "\n".join(lines)
	# Size the banner to the lines it actually has. A fixed three-line box left a
	# slab of dead space under a one-line tally.
	_verdict.custom_minimum_size.y = min(VERDICT_H_SINGLE * lines.size(), VERDICT_H_SUMMARY)
	_effects_label.visible = false

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(180, 38)
	WhiteDwarfTheme.apply_primary_button(close_btn)
	close_btn.pressed.connect(_on_close_pressed)
	_button_bar.add_child(close_btn)


# --- Buttons -----------------------------------------------------------------

func _add_awaiting_roll_buttons() -> void:
	if bool(_entry.get("insane_bravery_available", false)):
		var ib := Button.new()
		ib.name = "InsaneBraveryButton"
		ib.text = "INSANE BRAVERY (1 CP)"
		ib.tooltip_text = "Spend 1 CP: this unit automatically passes its Battle-shock test (once per battle)."
		ib.custom_minimum_size = Vector2(210, 38)
		WhiteDwarfTheme.apply_secondary_button(ib)
		ib.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		ib.pressed.connect(_on_insane_bravery_pressed)
		_button_bar.add_child(ib)

	var roll := Button.new()
	roll.name = "RollButton"
	roll.text = "⚄  Roll 2D6"
	roll.custom_minimum_size = Vector2(180, 38)
	WhiteDwarfTheme.apply_primary_button(roll)
	roll.pressed.connect(_on_roll_pressed)
	_button_bar.add_child(roll)

	_add_auto_resolve_button()


func _add_reroll_offer_buttons() -> void:
	var reroll := Button.new()
	reroll.name = "CommandRerollButton"
	reroll.text = "⟳  Command Re-roll (1 CP)"
	reroll.custom_minimum_size = Vector2(230, 38)
	WhiteDwarfTheme.apply_primary_button(reroll)
	reroll.pressed.connect(_on_command_reroll_pressed)
	_button_bar.add_child(reroll)

	var keep := Button.new()
	keep.name = "KeepRollButton"
	keep.text = "Keep the roll"
	keep.custom_minimum_size = Vector2(170, 38)
	WhiteDwarfTheme.apply_secondary_button(keep)
	keep.pressed.connect(_on_keep_roll_pressed)
	_button_bar.add_child(keep)


func _add_result_buttons() -> void:
	var next_btn := Button.new()
	next_btn.name = "NextButton"
	if _remaining_after > 0:
		next_btn.text = "Next ▶  (%d to go)" % _remaining_after
	else:
		next_btn.text = "Finish ▶"
	next_btn.custom_minimum_size = Vector2(200, 38)
	WhiteDwarfTheme.apply_primary_button(next_btn)
	next_btn.pressed.connect(_on_next_pressed)
	_button_bar.add_child(next_btn)

	if _remaining_after > 0:
		_add_auto_resolve_button()


func _add_auto_resolve_button() -> void:
	# Escape hatch for a player who does not want to click through six tests.
	# Deliberately the quiet, secondary option — the old behaviour was this, but
	# WITHOUT the player ever choosing it.
	var auto := Button.new()
	auto.name = "AutoResolveButton"
	auto.text = "Roll the rest for me"
	auto.tooltip_text = "Resolve every remaining Battle-shock test at once. Results still go to the game log."
	auto.custom_minimum_size = Vector2(190, 38)
	WhiteDwarfTheme.apply_to_button(auto)
	auto.pressed.connect(_on_auto_resolve_pressed)
	_button_bar.add_child(auto)


# --- Signal handlers ---------------------------------------------------------

func _on_roll_pressed() -> void:
	emit_signal("roll_requested", current_unit_id())


func _on_insane_bravery_pressed() -> void:
	emit_signal("insane_bravery_requested", current_unit_id())


func _on_command_reroll_pressed() -> void:
	emit_signal("command_reroll_requested", current_unit_id())


func _on_keep_roll_pressed() -> void:
	emit_signal("command_reroll_declined", current_unit_id())


func _on_next_pressed() -> void:
	emit_signal("next_requested")


func _on_auto_resolve_pressed() -> void:
	emit_signal("auto_resolve_rest_requested")


func _on_close_pressed() -> void:
	emit_signal("closed")


func _on_close_requested() -> void:
	# The window's X. Battle-shock is mandatory, so closing mid-queue means
	# "resolve the rest for me" rather than "skip them" — the tests still happen.
	if _mode == Mode.SUMMARY:
		emit_signal("closed")
	else:
		emit_signal("auto_resolve_rest_requested")
