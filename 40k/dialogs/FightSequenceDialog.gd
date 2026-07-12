extends AcceptDialog

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

# FightSequenceDialog — staged melee resolution UI (mirrors WeaponOrderDialog's
# staged section for shooting). Stays open through the whole fight sequence:
#   hit roll  -> pause: dice shown, optional per-die Command Re-roll,
#                "Roll to Wound ▶"
#   wound roll-> pause: dice shown, optional per-die Command Re-roll,
#                "Continue to Saving Throws ▶"
#   saves     -> auto-allocated results appended (or the dialog hides while the
#                defender uses the WoundAllocationOverlay, then re-shows)
#   complete  -> summary + Close
#
# The dialog connects directly to FightPhase signals (dice_rolled,
# fight_stage_paused, saves_required) — same pattern as WeaponOrderDialog.

signal staged_continue_requested(next_step: String)      # "wounds" or "saves"
signal staged_reroll_requested(stage: String, die_index: int)  # Command Re-roll a hit/wound die

var current_phase = null
var current_stage: String = ""       # "hits" | "wounds" while paused

# UI nodes
var vbox: VBoxContainer
var header_label: Label
var progress_label: Label
var dice_log_rich_text: RichTextLabel
var staged_continue_button: Button
var close_button: Button
var reroll_label: Label
var reroll_row: HBoxContainer

func _ready() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	# Stable node name so windowed scenarios can address the dialog + buttons.
	name = "FightSequenceDialog"
	title = "Fight — Melee Resolution"
	dialog_hide_on_ok = false
	min_size = DialogConstants.LARGE
	get_ok_button().hide()

	vbox = VBoxContainer.new()
	vbox.name = "Content"
	vbox.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 20, 0)
	add_child(vbox)

	header_label = Label.new()
	header_label.name = "HeaderLabel"
	header_label.text = "Resolving melee attacks..."
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_label.add_theme_font_size_override("font_size", 14)
	header_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	vbox.add_child(header_label)

	progress_label = Label.new()
	progress_label.name = "ProgressLabel"
	progress_label.text = ""
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.add_theme_font_size_override("font_size", 12)
	progress_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(progress_label)

	_add_gold_separator(vbox)

	# Command Re-roll affordance: a row of per-die buttons the attacker can
	# click to re-roll a single hit/wound die with Command Re-roll (1 CP).
	reroll_label = Label.new()
	reroll_label.name = "RerollLabel"
	reroll_label.add_theme_font_size_override("font_size", 12)
	reroll_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	reroll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reroll_label.visible = false
	vbox.add_child(reroll_label)

	reroll_row = HBoxContainer.new()
	reroll_row.name = "RerollRow"
	reroll_row.visible = false
	var reroll_scroll = ScrollContainer.new()
	reroll_scroll.name = "RerollScroll"
	reroll_scroll.custom_minimum_size = Vector2(DialogConstants.LARGE.x - 40, 44)
	reroll_scroll.add_child(reroll_row)
	vbox.add_child(reroll_scroll)

	# Action buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.name = "Buttons"
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_hbox)

	staged_continue_button = Button.new()
	staged_continue_button.name = "StagedContinueButton"
	staged_continue_button.text = "Continue ▶"
	staged_continue_button.pressed.connect(_on_staged_continue_pressed)
	staged_continue_button.custom_minimum_size = Vector2(260, 42)
	WhiteDwarfTheme.apply_primary_button(staged_continue_button)
	button_hbox.add_child(staged_continue_button)
	staged_continue_button.visible = false

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	close_button.custom_minimum_size = Vector2(100, 42)
	close_button.visible = false
	WhiteDwarfTheme.apply_secondary_button(close_button)
	button_hbox.add_child(close_button)

	_add_gold_separator(vbox)

	var log_label = Label.new()
	log_label.text = "Combat Log:"
	log_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_label)

	dice_log_rich_text = RichTextLabel.new()
	dice_log_rich_text.name = "DiceLog"
	dice_log_rich_text.set_custom_minimum_size(Vector2(DialogConstants.LARGE.x - 40, 200))
	dice_log_rich_text.bbcode_enabled = true
	dice_log_rich_text.scroll_following = true
	vbox.add_child(dice_log_rich_text)

	print("FightSequenceDialog initialized")

func setup(phase, fighter_name: String) -> void:
	current_phase = phase
	header_label.text = "%s — melee attacks" % fighter_name
	if current_phase == null:
		return
	if current_phase.has_signal("dice_rolled") and not current_phase.dice_rolled.is_connected(_on_dice_rolled):
		current_phase.dice_rolled.connect(_on_dice_rolled)
	if current_phase.has_signal("fight_stage_paused") and not current_phase.fight_stage_paused.is_connected(_on_stage_paused):
		current_phase.fight_stage_paused.connect(_on_stage_paused)
	# Hide while the defender allocates wounds in the overlay; the next
	# fight_stage_paused re-shows the dialog.
	if current_phase.has_signal("saves_required") and not current_phase.saves_required.is_connected(_on_saves_required):
		current_phase.saves_required.connect(_on_saves_required)

# --- dice log rendering ---------------------------------------------------

func _on_dice_rolled(dice_data: Dictionary) -> void:
	var context = dice_data.get("context", "")
	match context:
		"weapon_progress":
			_add_to_dice_log("", Color.WHITE)
			_add_to_dice_log("[b]━━━ %s ━━━[/b]" % dice_data.get("message", ""), WhiteDwarfTheme.WH_GOLD)
			if dice_data.get("total_weapons", 0):
				progress_label.text = dice_data.get("message", "")
		"resolution_start":
			_add_to_dice_log(dice_data.get("message", "Beginning melee resolution..."), Color.CYAN)
		"reroll_note":
			_add_to_dice_log("[b][color=orange]↻ %s[/color][/b]" % dice_data.get("message", "Re-roll"), Color.ORANGE)
		"auto_hit_melee", "auto_hit":
			var total = dice_data.get("total_attacks", dice_data.get("successes", 0))
			_add_to_dice_log("[b]Rolling to Hit:[/b] [color=cyan]%d automatic hits[/color]" % total, Color.WHITE)
		"hit_roll_melee", "to_hit":
			_add_to_dice_log(_format_roll_line("hit", dice_data), Color.WHITE)
		"wound_roll_melee", "to_wound":
			_add_to_dice_log(_format_roll_line("wound", dice_data), Color.WHITE)
		"save_roll_melee", "save_roll", "save":
			_add_to_dice_log(_format_save_line(dice_data), Color.WHITE)
		"feel_no_pain":
			var prevented = dice_data.get("wounds_prevented", 0)
			_add_to_dice_log("[b]Feel No Pain[/b] (need %s): %s → [color=cyan]%d prevented[/color]" % [
				dice_data.get("threshold", "?"), _dice_str(dice_data.get("rolls_raw", [])), prevented], Color.WHITE)
		"hazardous_check", "hazardous":
			_add_to_dice_log("[b][color=red]Hazardous:[/color][/b] %s" % dice_data.get("message", str(dice_data.get("rolls_raw", []))), Color.WHITE)
		_:
			# Fallback for any other dice block with rolls.
			var rolls = dice_data.get("rolls_raw", dice_data.get("rolls", []))
			if not (rolls as Array).is_empty():
				var line = "[b]%s[/b]" % context.capitalize().replace("_", " ")
				if dice_data.has("threshold"):
					line += " (need %s)" % dice_data.get("threshold", "")
				line += ": %s" % _dice_str(rolls)
				if dice_data.has("successes"):
					line += " → [b][color=green]%d[/color][/b]" % int(dice_data.get("successes", 0))
				_add_to_dice_log(line, Color.WHITE)

func _format_roll_line(kind: String, dice_data: Dictionary) -> String:
	var threshold = str(dice_data.get("threshold", ""))
	var rolls_raw = dice_data.get("rolls_raw", [])
	var rolls_modified = dice_data.get("rolls_modified", [])
	var display_rolls = rolls_modified if not (rolls_modified as Array).is_empty() else rolls_raw
	var total = (display_rolls as Array).size()
	var successes = int(dice_data.get("successes", 0))

	var label = "Rolling to Hit" if kind == "hit" else "Rolling to Wound"
	var line = "[b]%s[/b] (need %s): %s" % [label, threshold, _dice_str(display_rolls)]
	var rerolls = dice_data.get("rerolls", dice_data.get("wound_rerolls", []))
	if not (rerolls as Array).is_empty():
		line += "  [color=orange]("
		for rr in rerolls:
			line += "%d→%d " % [rr.get("original", 0), rr.get("rerolled_to", 0)]
		line = line.strip_edges() + ")[/color]"
	var fails = max(0, total - successes)
	var noun = kind if successes == 1 else kind + "s"
	line += " → [b][color=green]%d %s[/color][/b]" % [successes, noun]
	if kind == "hit" and total > 0:
		var miss_word = "miss" if fails == 1 else "misses"
		line += "[color=gray], %d %s[/color]" % [fails, miss_word]
	var crits = int(dice_data.get("critical_hits", dice_data.get("critical_wounds", 0)))
	if crits > 0:
		var crit_kind = "critical hit" if kind == "hit" else "critical wound"
		line += "  [color=#c8a24a](%d %s%s)[/color]" % [crits, crit_kind, "" if crits == 1 else "s"]
	var sustained = int(dice_data.get("sustained_bonus_hits", 0))
	if kind == "hit" and sustained > 0:
		line += "  [color=#c8a24a](+%d Sustained)[/color]" % sustained
	var lethal_autos = int(dice_data.get("lethal_hits_auto_wounds", 0))
	if kind == "wound" and lethal_autos > 0:
		line += "  [color=#c8a24a](%d Lethal auto-wound%s)[/color]" % [lethal_autos, "" if lethal_autos == 1 else "s"]
	return line

func _format_save_line(dice_data: Dictionary) -> String:
	var threshold = str(dice_data.get("threshold", "?"))
	var rolls = dice_data.get("rolls_raw", [])
	var saved = int(dice_data.get("successes", 0))
	var failed = int(dice_data.get("failed", max(0, (rolls as Array).size() - saved)))
	var line = "[b]Saving Throws[/b] (need %s): %s → [color=green]%d saved[/color], [color=red]%d failed[/color]" % [
		threshold, _dice_str(rolls), saved, failed]
	var dev = int(dice_data.get("devastating_wounds_bypassed", 0))
	if dev > 0:
		line += "  [color=#c8a24a](%d DEVASTATING — no save)[/color]" % dev
	return line

func _dice_str(rolls: Array) -> String:
	if rolls.is_empty():
		return "[color=gray]—[/color]"
	var parts = []
	for r in rolls:
		var v = int(r)
		if v == 6:
			parts.append("[color=#d4af37]6[/color]")
		elif v == 1:
			parts.append("[color=#a04040]1[/color]")
		else:
			parts.append(str(v))
	return "[ " + " ".join(parts) + " ]"

func _add_to_dice_log(text: String, color: Color) -> void:
	if not dice_log_rich_text:
		return
	var color_hex = color.to_html(false)
	dice_log_rich_text.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])

# --- staged pauses ----------------------------------------------------------

func _on_stage_paused(stage: String, info: Dictionary) -> void:
	current_stage = stage
	if not visible:
		popup_centered()
	if stage == "complete":
		staged_continue_button.visible = false
		reroll_label.visible = false
		reroll_row.visible = false
		_clear_reroll_row()
		var casualties = int(info.get("casualties", 0))
		var cas_label = "model" if casualties == 1 else "models"
		_add_to_dice_log("", Color.WHITE)
		_add_to_dice_log("[b]Melee attacks resolved — %d enemy %s destroyed.[/b]" % [casualties, cas_label], WhiteDwarfTheme.WH_GOLD)
		progress_label.text = "Attacks complete"
		close_button.visible = true
		return

	var reroll_available = bool(info.get("reroll_available", false))
	if stage == "hits":
		staged_continue_button.text = "Roll to Wound ▶"
		staged_continue_button.tooltip_text = "Proceed to the wound roll for this weapon"
	elif stage == "wounds":
		staged_continue_button.text = "Continue to Saving Throws ▶"
		staged_continue_button.tooltip_text = "Resolve the defender's saving throws"
	staged_continue_button.visible = true
	close_button.visible = false

	if reroll_available:
		var rolls = info.get("modified_rolls", [])
		if (rolls as Array).is_empty():
			rolls = info.get("hit_rolls", info.get("wound_rolls", []))
		_populate_reroll_row(stage, rolls)
	else:
		reroll_label.visible = false
		reroll_row.visible = false
		_clear_reroll_row()

func _populate_reroll_row(stage: String, rolls: Array) -> void:
	_clear_reroll_row()
	if rolls.is_empty():
		reroll_label.visible = false
		reroll_row.visible = false
		return
	reroll_label.text = "Command Re-roll (1 CP) — click a %s die to re-roll it (once per phase):" % ("hit" if stage == "hits" else "wound")
	reroll_label.visible = true
	reroll_row.visible = true
	for i in range(rolls.size()):
		var die_btn = Button.new()
		die_btn.name = "Die%d" % i
		die_btn.text = str(int(rolls[i]))
		die_btn.custom_minimum_size = Vector2(38, 38)
		die_btn.tooltip_text = "Re-roll this die with Command Re-roll (1 CP)"
		_WhiteDwarfTheme.apply_to_button(die_btn)
		die_btn.pressed.connect(_on_reroll_die_pressed.bind(i))
		reroll_row.add_child(die_btn)

func _clear_reroll_row() -> void:
	if not reroll_row:
		return
	for child in reroll_row.get_children():
		child.queue_free()

func _on_reroll_die_pressed(die_index: int) -> void:
	print("FightSequenceDialog: re-roll %s die %d requested" % [current_stage, die_index])
	# Disable further clicks immediately (once per phase); the phase confirms.
	reroll_label.visible = false
	reroll_row.visible = false
	_clear_reroll_row()
	emit_signal("staged_reroll_requested", current_stage, die_index)

func _on_staged_continue_pressed() -> void:
	staged_continue_button.visible = false
	reroll_label.visible = false
	reroll_row.visible = false
	_clear_reroll_row()
	if current_stage == "hits":
		emit_signal("staged_continue_requested", "wounds")
	elif current_stage == "wounds":
		emit_signal("staged_continue_requested", "saves")

func _on_saves_required(_save_data_list: Array) -> void:
	# Defender's WoundAllocationOverlay takes over — get out of the way.
	# The next fight_stage_paused (next weapon / complete) re-shows us.
	hide()

func _on_close_pressed() -> void:
	hide()
	queue_free()

# Windowed-scenario helper: ScenarioRunner's execute_script is Expression-only
# (no loops/statements), so the "click continue until the sequence completes"
# loop lives here. Clicks the staged continue button through the remaining
# stages and stops at the completion summary (Close visible). Returns a short
# status string; the scenario asserts/screenshots, then clicks CloseButton.
func debug_click_through(max_clicks: int = 12) -> String:
	var clicks = 0
	while clicks < max_clicks and not close_button.visible:
		if staged_continue_button.visible:
			_on_staged_continue_pressed()
		clicks += 1
	if close_button.visible:
		return "complete after %d step(s)" % clicks
	return "not complete after %d step(s)" % clicks

func _add_gold_separator(parent: Control) -> void:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r, WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sep)
