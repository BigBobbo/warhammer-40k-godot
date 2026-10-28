extends PanelContainer
class_name AISuggestionBreakdownPanel

# AISuggestionBreakdownPanel — the "why" card for the on-demand AI suggestion (K).
#
# AIDecisionMaker records, per decision, every option it scored, the values the
# score was built from, which option it chose, the tuning settings it read and
# the decision context (_ai_decision_records). This card turns that into
# something a player can review, built around the question a reviewer actually
# asks — "why THIS and not THAT?":
#
#   * The AI would …  — the chosen action, in words
#   * Per decision    — what it picked and a one-line "mostly because" summary;
#                       "Why not <runner-up>?" listing only the factors that
#                       DIFFERED between the two (▲ favoured the pick, ▼ the
#                       runner-up); every option as a bar with "% below the pick";
#                       click "details" on any option for all its factors.
#                       Flags: close calls, picks that are not top-scored, and
#                       decisions where nothing recorded explains the difference.
#   * AI's notes      — the narrated thinking steps
#   * Developer details (collapsed) — raw keys/values, context, the tuning
#                       settings read, and any value with no plain-English label
#                       yet (add it to AIReasoningGlossary.gd)
#
# Every value name, unit and tooltip comes from AIReasoningGlossary.gd.
#
# Public API:
#   show_decision(decision: Dictionary, meta: Dictionary)
#   close()
#   refresh_requested  (K pressed while the card has input — Main re-asks the AI)
#   save_case_requested(verdict, note)  ("Good call" / "Bad call" — Main saves
#                      an AISuggestionTestCases case); show_case_saved(result)
#   toggle_section(key: String)  (same as clicking a link: "dev", "notes", "opt:R:I")
#   unit_focus_requested(unit_id)  (a unit in the move/shoot/charge/fight/deploy order clicked,
#                      or ◀ / ▶ pressed — Main re-asks the AI about that unit)
#   cycle_unit(step: int)  (same as ◀ (-1) / ▶ (+1))
#   closed             (card hidden — Main clears the board overlay)
#   option_hovered(record, cand_index, chosen) / option_unhovered
#                      (pointer over an option row — Main previews it on the
#                      board via AISuggestionBoardOverlay); hover_option(key)
#   breakdown_text: String   (plain-text mirror of what is on screen)
#   full_text: String        (everything expanded — what Copy puts on the clipboard)
#   record_count: int
#   candidate_count: int
#
# Static, side-effect-free: build_breakdown(decision, meta, expanded, everything)
# -> {bbcode, text, records, candidates, subtitle}.

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
const _Glossary = preload("res://scripts/AIReasoningGlossary.gd")

const PANEL_WIDTH := 660.0
const SCREEN_MARGIN := 24.0
const TOP_OFFSET := 168.0  # clear of the top bar AND the toast row (e.g. "Game autosaved" sat on the title)
const BAR_CELLS := 12
const MAX_WHY_ROWS := 4
const MAX_SUMMARY_FACTS := 4
# A runner-up within this fraction of the chosen score counts as a close call —
# a small weight change could flip the decision.
const CLOSE_CALL_REL := 0.05
# Factors that differ by less than this (relative) are not worth listing.
const MIN_REL_DIFF := 0.05

const COL_CARD_BG := Color(0.07, 0.065, 0.05, 0.97)
const COL_HEADER_BG := Color(0.14, 0.11, 0.075, 1.0)
const COL_DIM := Color(0.78, 0.74, 0.66)

const HEX_GOLD := "#d49761"
const HEX_CYAN := "#9fe8ff"
const HEX_DIM := "#a8a294"
const HEX_FAINT := "#7d786c"
const HEX_GOOD := "#8fd18f"
const HEX_BAD := "#e98a7a"
const HEX_WARN := "#ffc070"
const HEX_LINK := "#7fc8e8"

# Main re-hosts the card in a Window tagged with this meta when a modal dialog
# is open (a plain Control would draw underneath the dialog and get no input).
const HOST_META := "ai_suggestion_host"

signal refresh_requested
signal save_case_requested(verdict: String, note: String)
signal unit_focus_requested(unit_id: String)
signal closed
signal option_hovered(record: Dictionary, cand_index: int, chosen: bool)
signal option_unhovered

var breakdown_text: String = ""
var full_text: String = ""
var record_count: int = 0
var candidate_count: int = 0

var _title: Label = null
var _subtitle: Label = null
var _rich: RichTextLabel = null
var _decision: Dictionary = {}
var _meta: Dictionary = {}
var _expanded: Dictionary = {}
var _note_edit: LineEdit = null
var _review_status: Label = null
# UNIT-ORDER: the unit order of the AI's own (unfocused) pick, kept while the
# player cycles so ◀ / ▶ walk a stable list (lower difficulties add random
# noise to tie-breaks, so re-asking can reshuffle level units).
var _cycle_order: Array = []
var _prev_unit_btn: Button = null
var _next_unit_btn: Button = null


func _ready() -> void:
	name = "AISuggestionBreakdownPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COL_CARD_BG
	card_style.border_color = Color(0.6, 0.9, 1.0)  # cyan — matches the Suggest button
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", card_style)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 0)
	add_child(body)

	# Header
	var header := PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", _bar_style(COL_HEADER_BG, 12, 8, false))
	body.add_child(header)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 2)
	header.add_child(hcol)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hcol.add_child(hrow)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "WHY THE AI SUGGESTS THIS"
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(_title)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.tooltip_text = "Close (Esc)"
	_WhiteDwarfTheme.apply_to_button(close_btn)
	close_btn.pressed.connect(close)
	hrow.add_child(close_btn)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", COL_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hcol.add_child(_subtitle)

	# Content
	var content := MarginContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 10)
	body.add_child(content)
	_rich = RichTextLabel.new()
	_rich.name = "BreakdownText"
	_rich.bbcode_enabled = true
	_rich.scroll_active = true
	_rich.selection_enabled = true
	_rich.fit_content = false
	_rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rich.add_theme_font_size_override("normal_font_size", 15)
	_rich.add_theme_font_size_override("bold_font_size", 15)
	_rich.add_theme_constant_override("table_h_separation", 10)
	_rich.add_theme_color_override("default_color", _WhiteDwarfTheme.WH_PARCHMENT)
	_rich.meta_clicked.connect(_on_meta_clicked)
	_rich.meta_hover_started.connect(func(m): hover_option(str(m)))
	_rich.meta_hover_ended.connect(func(_m): option_unhovered.emit())
	content.add_child(_rich)

	# Review row: turn this suggestion into a regression test case
	var review := PanelContainer.new()
	review.name = "Review"
	review.add_theme_stylebox_override("panel", _bar_style(COL_HEADER_BG, 12, 6, true))
	body.add_child(review)
	var rcol := VBoxContainer.new()
	rcol.name = "Col"
	rcol.add_theme_constant_override("separation", 4)
	review.add_child(rcol)
	var rrow := HBoxContainer.new()
	rrow.name = "Row"
	rrow.add_theme_constant_override("separation", 8)
	rcol.add_child(rrow)
	_note_edit = LineEdit.new()
	_note_edit.name = "NoteEdit"
	_note_edit.placeholder_text = "Note: what should it have done? (optional)"
	_note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_edit.add_theme_font_size_override("font_size", 14)
	rrow.add_child(_note_edit)
	var good_btn := Button.new()
	good_btn.name = "GoodCallButton"
	good_btn.text = "Good call"
	good_btn.tooltip_text = "Save this position as a test case the AI must keep getting right"
	_WhiteDwarfTheme.apply_to_button(good_btn)
	good_btn.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	good_btn.pressed.connect(func(): save_case_requested.emit("good", _note_edit.text.strip_edges()))
	rrow.add_child(good_btn)
	var bad_btn := Button.new()
	bad_btn.name = "BadCallButton"
	bad_btn.text = "Bad call"
	bad_btn.tooltip_text = "Save this position as a test case that fails until the AI chooses differently"
	_WhiteDwarfTheme.apply_to_button(bad_btn)
	bad_btn.add_theme_color_override("font_color", Color(0.95, 0.6, 0.55))
	bad_btn.pressed.connect(func(): save_case_requested.emit("bad", _note_edit.text.strip_edges()))
	rrow.add_child(bad_btn)
	_review_status = Label.new()
	_review_status.name = "ReviewStatus"
	_review_status.add_theme_font_size_override("font_size", 13)
	_review_status.add_theme_color_override("font_color", COL_DIM)
	_review_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_status.text = "Mark this call to save the position as an AI test case (re-checked by tests/run_ai_test_cases.sh)."
	rcol.add_child(_review_status)

	# Footer
	var footer := PanelContainer.new()
	footer.name = "Footer"
	footer.add_theme_stylebox_override("panel", _bar_style(COL_HEADER_BG, 12, 6, true))
	body.add_child(footer)
	var frow := HBoxContainer.new()
	frow.name = "Row"
	frow.add_theme_constant_override("separation", 10)
	footer.add_child(frow)
	var hint := Label.new()
	hint.text = "Preview only — nothing was executed. The board shows the suggested unit (cyan), its target (red) and where it would move; hover an option to see it on the board. K refreshes, Esc closes."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frow.add_child(hint)
	_prev_unit_btn = Button.new()
	_prev_unit_btn.name = "PrevUnitButton"
	_prev_unit_btn.text = "◀ Unit"
	_prev_unit_btn.tooltip_text = "Show what the AI would do with the previous unit in its order"
	_WhiteDwarfTheme.apply_to_button(_prev_unit_btn)
	_prev_unit_btn.pressed.connect(func(): cycle_unit(-1))
	_prev_unit_btn.visible = false
	frow.add_child(_prev_unit_btn)
	_next_unit_btn = Button.new()
	_next_unit_btn.name = "NextUnitButton"
	_next_unit_btn.text = "Unit ▶"
	_next_unit_btn.tooltip_text = "Show what the AI would do with the next unit in its order"
	_WhiteDwarfTheme.apply_to_button(_next_unit_btn)
	_next_unit_btn.pressed.connect(func(): cycle_unit(1))
	_next_unit_btn.visible = false
	frow.add_child(_next_unit_btn)
	var copy_btn := Button.new()
	copy_btn.name = "CopyButton"
	copy_btn.text = "Copy as text"
	copy_btn.tooltip_text = "Copy the full breakdown, including developer details, to the clipboard (paste into a bug report)"
	_WhiteDwarfTheme.apply_to_button(copy_btn)
	copy_btn.pressed.connect(_on_copy_pressed)
	frow.add_child(copy_btn)

	_apply_fit()
	# The ROOT window's size, not get_viewport(): when a modal dialog is open
	# the card is re-hosted in its own small window (see Main), whose viewport
	# is the card itself.
	var root := get_tree().root
	if not root.is_connected("size_changed", _apply_fit):
		root.connect("size_changed", _apply_fit)
	print("[AISuggestionBreakdownPanel] Ready")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _note_edit != null and _note_edit.has_focus() and event.keycode != KEY_ESCAPE:
		return  # typing a note — 'k' is a letter here, not the hotkey
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif KeybindingManager and KeybindingManager.matches_action(event, "ai_suggestion"):
		# K while the card is open = refresh. Handled here because, when the
		# card sits above a modal dialog in its own window, Main never sees it.
		get_viewport().set_input_as_handled()
		refresh_requested.emit()


func show_decision(decision: Dictionary, meta: Dictionary = {}) -> void:
	_decision = decision
	_meta = meta
	_expanded = {}
	if _review_status:
		_review_status.text = "Mark this call to save the position as an AI test case (re-checked by tests/run_ai_test_cases.sh)."
		_review_status.add_theme_color_override("font_color", COL_DIM)
	_update_cycle_order(decision)
	full_text = build_breakdown(decision, meta, {}, true).text
	_render(true)
	visible = true
	_refit()
	print("[AISuggestionBreakdownPanel] Showing breakdown: %d decision record(s), %d candidate(s)" % [record_count, candidate_count])
	DebugLogger.info("AISuggestionBreakdownPanel shown", {"records": record_count, "candidates": candidate_count, "type": decision.get("type", "")})


func show_case_saved(result: Dictionary) -> void:
	"""Feedback after Main saved (or failed to save) a test case."""
	if _review_status == null:
		return
	if bool(result.get("ok", false)):
		_review_status.text = "Saved test case %s\n%s" % [str(result.get("id", "")), str(result.get("json_path", ""))]
		_review_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		if _note_edit:
			_note_edit.text = ""
	else:
		_review_status.text = "Could not save: " + str(result.get("error", "unknown error"))
		_review_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.55))


func toggle_section(key: String) -> void:
	_expanded[key] = not bool(_expanded.get(key, false))
	_render(false)
	print("[AISuggestionBreakdownPanel] Toggled '%s' -> %s" % [key, str(_expanded[key])])


func close() -> void:
	visible = false
	# Hosted above a modal dialog: hide the host so the dialog gets input back.
	var host := get_parent() as Window
	if host != null and host.has_meta(HOST_META):
		host.hide()
	closed.emit()
	print("[AISuggestionBreakdownPanel] Closed")


func hover_option(key: String) -> void:
	"""Pointer over an option ("opt:R:I") — ask Main to preview it on the board."""
	var parts := key.split(":")
	if parts.size() != 3 or parts[0] != "opt":
		return
	var records: Array = _decision.get("_ai_decision_records", [])
	var r_i := int(parts[1])
	if r_i < 0 or r_i >= records.size() or not (records[r_i] is Dictionary):
		return
	var rec: Dictionary = records[r_i]
	var i := int(parts[2])
	option_hovered.emit(rec, i, i == int(rec.get("chosen_index", -1)))


func _render(reset_scroll: bool) -> void:
	var built := build_breakdown(_decision, _meta, _expanded, false)
	breakdown_text = built.text
	record_count = built.records
	candidate_count = built.candidates
	if _subtitle:
		_subtitle.text = str(built.subtitle)
	if _rich == null:
		return
	var bar := _rich.get_v_scroll_bar()
	var keep: float = 0.0 if reset_scroll or bar == null else bar.value
	_rich.clear()
	_rich.append_text(built.bbcode)
	if reset_scroll:
		_rich.scroll_to_line(0)
	elif bar != null and is_inside_tree():
		# Expanding a section re-renders the whole text; keep the reader's place.
		await get_tree().process_frame
		bar.value = keep


func _on_meta_clicked(meta) -> void:
	var key := str(meta)
	if key.begins_with("unit:"):
		_request_unit(key.trim_prefix("unit:"))
		return
	toggle_section(key)


func cycle_unit(step: int) -> void:
	"""◀ / ▶: re-ask the AI about the previous / next unit in its move order."""
	if _cycle_order.size() < 2:
		return
	var acting := str(_decision.get("_ai_unit_order", {}).get("acting_unit_id", ""))
	var i := _cycle_order.find(acting)
	var next_i := posmod((i if i >= 0 else 0) + step, _cycle_order.size())
	_request_unit(str(_cycle_order[next_i]))


func _request_unit(unit_id: String) -> void:
	if unit_id == "":
		return
	print("[AISuggestionBreakdownPanel] Unit focus requested: %s" % unit_id)
	unit_focus_requested.emit(unit_id)


func _update_cycle_order(decision: Dictionary) -> void:
	var mo: Dictionary = decision.get("_ai_unit_order", {})
	var ids: Array = []
	for e in mo.get("order", []):
		ids.append(str(e.get("unit_id", "")))
	# Keep the list from the AI's own pick while cycling through it; replace it
	# on a fresh (unfocused) ask, or when the board changed under it.
	var acting := str(mo.get("acting_unit_id", ""))
	if not bool(mo.get("focused", false)) or not (acting in _cycle_order) or ids.size() != _cycle_order.size():
		_cycle_order = ids
	var show_nav := _cycle_order.size() >= 2
	if _prev_unit_btn:
		_prev_unit_btn.visible = show_nav
	if _next_unit_btn:
		_next_unit_btn.visible = show_nav


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(full_text)
	print("[AISuggestionBreakdownPanel] Copied %d chars to clipboard" % full_text.length())


func _refit() -> void:
	# RichTextLabel reports its full content height for a frame after new text
	# is appended, which grows the card past the screen bottom (a container
	# never shrinks back on its own). Fit now, then again once layout settles.
	_apply_fit()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree():
		_apply_fit()


func _apply_fit() -> void:
	if not is_inside_tree():
		return
	var vp_size := get_tree().root.get_visible_rect().size
	var w: float = minf(PANEL_WIDTH, maxf(320.0, vp_size.x - 2.0 * SCREEN_MARGIN))
	var h: float = maxf(240.0, vp_size.y - TOP_OFFSET - SCREEN_MARGIN - 60.0)
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	# Right side: the game log owns the left edge and the board stays visible.
	var pos := Vector2(roundf(vp_size.x - w - SCREEN_MARGIN), TOP_OFFSET)
	var host := get_parent() as Window
	if host != null and host.has_meta(HOST_META):
		host.position = Vector2i(pos)
		host.size = Vector2i(roundi(w), roundi(h))
		position = Vector2.ZERO
	else:
		position = pos


func _bar_style(bg: Color, h: int, v: int, top_border: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(_WhiteDwarfTheme.WH_GOLD, 0.65)
	if top_border:
		style.border_width_top = 1
	else:
		style.border_width_bottom = 1
	style.content_margin_left = h
	style.content_margin_right = h
	style.content_margin_top = v
	style.content_margin_bottom = v
	return style


# ---------------------------------------------------------------------------
# Pure formatting
# ---------------------------------------------------------------------------

# Two parallel outputs: bbcode for the card, plain text for asserts / clipboard.
class _Out:
	var bb := PackedStringArray()
	var tx := PackedStringArray()

	func line(b: String, t = null) -> void:
		bb.append(b)
		if t != null:
			tx.append(str(t))

	func gap() -> void:
		bb.append("")
		tx.append("")


static func build_breakdown(decision: Dictionary, meta: Dictionary = {},
		expanded: Dictionary = {}, everything: bool = false) -> Dictionary:
	"""Format a suggest_action() result. `expanded` holds the open sections
	("dev", "notes_closed", "opt:R:I"); `everything` opens all of them (Copy)."""
	var o := _Out.new()
	var total_cands := 0
	var subtitle := "Player %s · %s phase · Round %s · thinking at %s difficulty" % [
		str(meta.get("player", "?")), str(meta.get("phase_name", "?")),
		str(meta.get("round", "?")), str(meta.get("difficulty", "?"))]
	if str(meta.get("refreshed_after", "")) != "":
		subtitle += " · updated after %s acted" % str(meta.refreshed_after)

	_heading(o, "THE AI WOULD")
	if decision.is_empty():
		var why := str(meta.get("empty_reason", "The AI could not find a recommended action here."))
		o.line("[color=%s]%s[/color]" % [HEX_WARN, _esc(why)], why)
		return {"bbcode": "\n".join(o.bb), "text": "\n".join(o.tx), "records": 0,
			"candidates": 0, "subtitle": subtitle}
	var desc := str(decision.get("_ai_description", decision.get("type", "unknown")))
	o.line("[font_size=17][b][color=%s]%s[/color][/b][/font_size]" % [HEX_CYAN, _esc(desc)], desc)
	# MOVE-SHAPE: why this turn's move does not head straight at its objective
	var adj: Array = decision.get("_ai_move_adjustments", [])
	if not adj.is_empty():
		o.line("[color=%s]How this turn's move was shaped:[/color]" % HEX_WARN, "How this turn's move was shaped:")
		for a in adj:
			o.line("  [color=%s]↳[/color] %s" % [HEX_DIM, _esc(str(a))], "  -> " + str(a))
	_render_move_order(o, decision.get("_ai_unit_order", {}))

	var records: Array = decision.get("_ai_decision_records", [])
	var analyses: Array = []
	for r in records:
		analyses.append(_analyse(r))

	if records.is_empty():
		o.gap()
		var types: Array = meta.get("available_types", [])
		var n_avail := int(meta.get("available_count", -1))
		if n_avail == 1 or (types.size() == 1 and n_avail <= 1):
			var only := "This was the only thing that could be done here (%s) — there was nothing to weigh." % (str(types[0]).replace("_", " ").to_lower() if not types.is_empty() else "one action")
			o.line("[color=%s]%s[/color]" % [HEX_DIM, _esc(only)], only)
		else:
			var gap := "The AI did not record the other options it weighed for this decision, so only its final choice can be shown. (This decision type is not instrumented yet.)"
			if n_avail > 1:
				gap += " It had %d possible actions (%s)." % [n_avail, ", ".join(PackedStringArray(types)).replace("_", " ").to_lower()]
			o.line("[color=%s]⚠ %s[/color]" % [HEX_WARN, _esc(gap)], "! " + gap)
	for r_i in range(records.size()):
		_render_record(o, records[r_i], analyses[r_i], r_i, records.size(), expanded, everything)
		total_cands += (records[r_i].get("candidates", []) as Array).size()

	# AI's notes (narrated steps) — open by default
	var steps: Array = decision.get("_ai_thinking_steps", [])
	if not steps.is_empty():
		var notes_open: bool = everything or not bool(expanded.get("notes_closed", false))
		_heading(o, "AI'S NOTES", "notes_closed", notes_open, "hide" if notes_open else "show %d" % steps.size())
		if notes_open:
			for s in steps:
				var st := str(s).strip_edges()
				o.line("[color=%s]•[/color] %s" % [HEX_DIM, _esc(st)], "- " + st)

	# Developer details — closed by default
	var dev_open: bool = everything or bool(expanded.get("dev", false))
	_heading(o, "DEVELOPER DETAILS", "dev", dev_open, "hide" if dev_open else "show")
	if not dev_open:
		o.line("[color=%s]Raw values, tuning settings and unlabelled values.[/color]" % HEX_FAINT)
	else:
		_render_dev(o, records, analyses)

	return {"bbcode": "\n".join(o.bb), "text": "\n".join(o.tx), "records": records.size(),
		"candidates": total_cands, "subtitle": subtitle}


static func _render_move_order(o: _Out, mo: Dictionary) -> void:
	"""UNIT-ORDER: which unit acts, why it goes first, and the rest of the queue
	(each a link that shows what the plan has that unit do). Movement, shooting,
	charge, fight and deployment each fill it (AIDecisionMaker._build_*_order)."""
	var order: Array = mo.get("order", [])
	if order.is_empty():
		return
	var acting := str(mo.get("acting_unit_id", ""))
	var first: Dictionary = order[0]
	var more := order.size() - 1
	o.gap()
	if acting == str(first.get("unit_id", "")):
		var t := "%s: %s — %s." % [str(mo.get("first_label", "Moving first")), str(first.get("name", "")), str(mo.get("first_reason", ""))]
		if more > 0:
			t += " %d more queued — click a unit below (or ◀ / ▶) to see its plan." % more
		o.line("[color=%s]%s[/color]" % [HEX_WARN, _esc(t)], t)
	else:
		var pos := 0
		var acting_name := acting
		for i in range(order.size()):
			if str(order[i].get("unit_id", "")) == acting:
				pos = i + 1
				acting_name = str(order[i].get("name", acting))
		var t := "Showing %s — %s in the order. Not what the AI does next: it would %s %s first (%s). This is what %s does once its turn comes." % [
			acting_name, _ordinal(pos), str(mo.get("verb", "move")), str(first.get("name", "")), str(mo.get("first_reason", "")), acting_name]
		o.line("[color=%s]%s[/color] [url=unit:%s]Back to the AI's next move[/url]" % [
			HEX_WARN, _esc(t), str(first.get("unit_id", ""))], t)
	for i in range(order.size()):
		var e: Dictionary = order[i]
		var what := str(e.get("action", "move"))
		if str(e.get("target", "")) != "":
			what += " " + str(e.get("target", ""))
		var tag := str(e.get("tag", ""))
		if e.has("tag"):
			pass
		elif bool(e.get("engaged", false)):
			tag = "engaged"
		elif int(e.get("tier", 1)) == 0:
			tag = "just disembarked"
		elif int(e.get("tier", 1)) == 2:
			tag = "transport — moves last"
		elif float(e.get("behind_front_in", -1.0)) > 0.05:
			tag = "%.1f\" behind the front" % float(e.get("behind_front_in", 0.0))
		elif float(e.get("behind_front_in", -1.0)) >= 0.0:
			tag = "front"
		var nm := str(e.get("name", ""))
		var uid := str(e.get("unit_id", ""))
		var is_acting := uid == acting
		var mark := "[color=%s]▶[/color]" % HEX_GOOD if is_acting else " "
		var name_bb := "[b]%s[/b]" % _esc(nm) if is_acting else "[url=unit:%s]%s[/url]" % [uid, _esc(nm)]
		var tail := " — %s" % what + ((" · %s" % tag) if tag != "" else "")
		o.line("%s %d. %s[color=%s]%s[/color]" % [mark, i + 1, name_bb, HEX_DIM, _esc(tail)],
			"%s %d. %s%s" % [">" if is_acting else " ", i + 1, nm, tail])


static func _ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return "%d%s" % [n, suf]


static func _analyse(rec: Dictionary) -> Dictionary:
	"""Rank the options and work out how to read their values: an additive
	ledger (the values add up to the score) or a set of factors."""
	var cands: Array = rec.get("candidates", [])
	var chosen := int(rec.get("chosen_index", -1))
	if chosen < 0 or chosen >= cands.size():
		chosen = 0 if not cands.is_empty() else -1
	var order: Array = range(cands.size())
	order.sort_custom(func(a, b): return _score_of(cands[a]) > _score_of(cands[b]))
	# Runner-up = the best option that could actually have been picked; ones
	# ruled out before scoring mattered (below the bar to use a stratagem,
	# under 3% to charge, keeping CP) are listed but not compared against.
	var runner := -1
	for i in order:
		if i != chosen and bool(cands[i].get("eligible", true)):
			runner = i
			break
	# Ledger check on the chosen option: do its additive ("pts" or unlabelled)
	# values sum to its score?
	var ledger := false
	var sum_ok := {}
	for i in range(cands.size()):
		var total := 0.0
		var n := 0
		var bd = cands[i].get("score_breakdown", {})
		if bd is Dictionary:
			for k in bd.keys():
				var v = bd[k]
				if not (v is float or v is int):
					continue
				if _Glossary.is_addend(str(k)):
					total += float(v)
					n += 1
		sum_ok[i] = n >= 1 and absf(total - _score_of(cands[i])) <= maxf(0.01, absf(_score_of(cands[i])) * 0.001)
	if chosen >= 0:
		ledger = bool(sum_ok.get(chosen, false))
	# Duplicate labels (two units with the same name) get a suffix
	var labels: Array = []
	var seen := {}
	for c in cands:
		var d := str(c.get("description", c.get("key", "option")))
		seen[d] = int(seen.get(d, 0)) + 1
	var nth := {}
	for c in cands:
		var d := str(c.get("description", c.get("key", "option")))
		if int(seen[d]) > 1:
			nth[d] = int(nth.get(d, 0)) + 1
			d += " (%s)" % _disambiguator(c, int(nth[d]))
		labels.append(d)
	return {"cands": cands, "chosen": chosen, "runner": runner, "order": order,
		"ledger": ledger, "sum_ok": sum_ok, "labels": labels}


static func _disambiguator(c: Dictionary, n: int) -> String:
	"""Tell apart two options that read the same (two units both called
	'Boyz'): the unit's squad letter (U_BOYZ_F → F) and, when recorded, how
	many wounds it has left — something a player can match on the board."""
	var bits := PackedStringArray()
	var tid := str(c.get("target_unit_id", ""))
	if tid != "":
		var parts := tid.split("_")
		var tail := parts[parts.size() - 1] if parts.size() > 1 else ""
		bits.append("squad %s" % tail if tail.length() <= 2 and tail != "" else tid)
	var bd: Dictionary = _bd(c)
	for wk in ["kill_threshold", "target_hp"]:
		if bd.has(wk):
			bits.append("%s W left" % _Glossary.format_value("target_hp", bd[wk]))
			break
	if bits.is_empty():
		bits.append("#%d" % n)
	return ", ".join(bits)


static func _render_record(o: _Out, rec: Dictionary, a: Dictionary, r_i: int, n_records: int,
		expanded: Dictionary, everything: bool) -> void:
	var cands: Array = a.cands
	var chosen: int = a.chosen
	var runner: int = a.runner
	var dtype := str(rec.get("decision_type", "decision")).replace("_", " ").to_upper()
	if dtype == "RULE BASED":
		dtype = "RULE-BASED DECISION"
	var who := str(rec.get("unit_name", rec.get("unit_id", "")))
	var title := dtype + ((" · " + who) if who != "" else "")
	if n_records > 1:
		title = "%d. %s" % [r_i + 1, title]
	_heading(o, title)
	if chosen < 0:
		o.line("[color=%s](no options recorded)[/color]" % HEX_DIM, "(no options recorded)")
		return
	var c_bd: Dictionary = _bd(cands[chosen])
	o.line("[color=%s]✔[/color] [b]%s[/b]" % [HEX_GOOD, _esc(a.labels[chosen])], "Picked: " + str(a.labels[chosen]))
	if str(rec.get("decision_type", "")) == "rule_based":
		var rb := "This decision is made by a fixed order of checks, not by comparing scores — the AI's notes below are the checks it made. Other actions it could have taken:"
		o.line("[color=%s]%s[/color]" % [HEX_DIM, _esc(rb)], rb)
		for i in range(cands.size()):
			if i != chosen:
				o.line("  [color=%s]•[/color] %s" % [HEX_DIM, _esc(str(a.labels[i]))], "  - " + str(a.labels[i]))
		return

	# One-line summary of the pick
	var summary := _summary(c_bd, a.ledger)
	if summary[0] != "":
		o.line("[color=%s]%s[/color]" % [HEX_DIM, summary[0]], summary[1])

	# Flags
	var top: int = a.order[0]
	if top != chosen and _score_of(cands[top]) > _score_of(cands[chosen]):
		var f := "The AI picked this even though \"%s\" scored higher — a plan, a rule or a separate scoring step chose it." % a.labels[top]
		# OBJ-EXPLAIN-1: when the decision recorded WHY it overrode the top
		# score (e.g. "obj_nml_1 is already taken by Telemon"), say that instead.
		var override_reason := str(rec.get("context", {}).get("override_reason", ""))
		if override_reason != "":
			f = "The AI picked this even though \"%s\" scored higher: %s." % [a.labels[top], override_reason]
		o.line("[color=%s]⚠ %s[/color]" % [HEX_WARN, _esc(f)], "! " + f)
	if runner >= 0:
		var cs := _score_of(cands[chosen])
		var rs := _score_of(cands[runner])
		if absf(cs - rs) <= absf(cs) * CLOSE_CALL_REL:
			var f2 := "Close call: \"%s\" scored almost the same — a small change in the AI's weighting would flip this." % a.labels[runner]
			o.line("[color=%s]⚖ %s[/color]" % [HEX_WARN, _esc(f2)], "~ " + f2)

	# Free rule / ability picks are a take-it-or-skip-it choice, not a ranking
	if str(rec.get("decision_type", "")) == "window_rule":
		var fr := "A free rule or ability choice: the AI takes it whenever its codex rule handler picks it, before weighing any paid stratagem. The reason above is the handler's own."
		o.line("[color=%s]%s[/color]" % [HEX_DIM, _esc(fr)], fr)
		runner = -1
	# Why not the runner-up?
	if runner >= 0:
		o.gap()
		o.line("[b]Why not \"%s\"?[/b] [color=%s]It scored %s.[/color]" % [_esc(a.labels[runner]), HEX_DIM, _gap_words(_score_of(cands[chosen]), _score_of(cands[runner]))],
			"Why not \"%s\"? It scored %s." % [a.labels[runner], _gap_words(_score_of(cands[chosen]), _score_of(cands[runner]))])
		var rows := _why_rows(c_bd, _bd(cands[runner]), a.ledger)
		if rows.is_empty():
			var none := "Nothing the AI recorded differs between the two — the gap comes from something it does not report yet."
			if is_equal_approx(_score_of(cands[chosen]), _score_of(cands[runner])):
				none = "Exact tie — the AI kept the first option it evaluated. Nothing it scores tells these apart."
			elif not _shares_numeric_key(c_bd, _bd(cands[runner])):
				none = "These two are measured differently, so there is nothing to line up — compare their details below."
			o.line("[color=%s]  %s[/color]" % [HEX_WARN, _esc(none)], "  " + none)
		for row in rows:
			o.line(row[0], row[1])
	elif cands.size() == 1:
		o.line("[color=%s]This was the only option it considered.[/color]" % HEX_DIM, "Only option considered.")
	else:
		var ro := "Every other option was ruled out before scores were compared (see the reasons below)."
		o.line("[color=%s]%s[/color]" % [HEX_DIM, _esc(ro)], ro)

	# All options as bars
	var considered := int(rec.get("context", {}).get("options_considered", rec.get("context", {}).get("alternatives_considered", cands.size())))
	o.gap()
	var more := "" if considered <= cands.size() else " (top %d of %d shown)" % [cands.size(), considered]
	o.line("[b]All options[/b][color=%s]%s — bar = how much the AI liked it[/color]" % [HEX_DIM, more], "All options%s:" % more)
	# Bar scale runs from 0 (or the lowest score, when scores go negative —
	# secondary discards score -achievability) to the highest score.
	var max_s := -INF
	var lo := 0.0
	for c in cands:
		max_s = maxf(max_s, _score_of(c))
		lo = minf(lo, _score_of(c))
	var cs2 := _score_of(cands[chosen])
	for rank in range(a.order.size()):
		var i: int = a.order[rank]
		var s := _score_of(cands[i])
		var frac := clampf((s - lo) / (max_s - lo), 0.0, 1.0) if max_s > lo else 1.0
		var cells := roundi(frac * BAR_CELLS)
		var is_c := i == chosen
		var col := HEX_GOOD if is_c else HEX_GOLD
		var bar := "[color=%s]%s[/color][color=#3a352c]%s[/color]" % [col, "█".repeat(cells), "█".repeat(BAR_CELLS - cells)]
		var rel := "picked" if is_c else _gap_words(cs2, s)
		var key := "opt:%d:%d" % [r_i, i]
		var open: bool = everything or bool(expanded.get(key, false))
		var link := "[url=%s][color=%s]%s[/color][/url]" % [key, HEX_LINK, "▾ hide" if open else "▸ details"]
		# The name is a link too: hovering it previews this option on the board.
		var name_b := ("[url=%s][b]%s[/b][/url]" if is_c else "[url=%s]%s[/url]") % [key, _esc(a.labels[i])]
		o.line("%s  %s  [color=%s]%s[/color]  %s" % [bar, name_b, HEX_DIM, rel, link],
			"  %s %s — %s" % ["*" if is_c else "-", a.labels[i], rel])
		if open:
			for row in _detail_rows(_bd(cands[i]), a.ledger):
				o.line(row[0], row[1])
			for row in _sub_rows(cands[i]):
				o.line(row[0], row[1])

	# Player-relevant context
	var ctx: Dictionary = rec.get("context", {})
	var bits := PackedStringArray()
	for k in _Glossary.CONTEXT_LABELS.keys():
		if ctx.has(k) and str(ctx[k]) != "":
			bits.append("%s: %s" % [_Glossary.CONTEXT_LABELS[k], str(ctx[k]).replace("_", " ")])
	if not bits.is_empty():
		o.line("[color=%s]%s[/color]" % [HEX_FAINT, _esc(" · ".join(bits))], " · ".join(bits))


static func _summary(bd: Dictionary, ledger: bool) -> Array:
	"""['Mostly because: …' bbcode, plain] for the chosen option."""
	var nums := _numeric_terms(bd)
	if nums.is_empty():
		return ["", ""]
	if ledger:
		var pos: Array = []
		var neg: Array = []
		for t in nums:
			if not _Glossary.is_addend(t[0]):
				continue
			if t[1] > 0.0:
				pos.append(t)
			elif t[1] < 0.0:
				neg.append(t)
		pos.sort_custom(func(x, y): return x[1] > y[1])
		neg.sort_custom(func(x, y): return x[1] < y[1])
		var p := PackedStringArray()
		for t in pos.slice(0, 3):
			p.append("%s %s" % [_Glossary.label(t[0]), _Glossary.format_value(t[0], t[1])])
		var n := PackedStringArray()
		for t in neg.slice(0, 2):
			n.append("%s %s" % [_Glossary.label(t[0]), _Glossary.format_value(t[0], t[1])])
		var s := ""
		if not p.is_empty():
			s = "Mostly because of: " + ", ".join(p) + "."
		if not n.is_empty():
			s += (" " if s != "" else "") + "Held back by: " + ", ".join(n) + "."
		var facts := _facts(bd, true)
		if facts != "":
			s += " (" + facts + ")"
		return [_esc(s), s]
	var f := _facts(bd, false)
	return [_esc(f), f]


static func _facts(bd: Dictionary, descriptors_only: bool) -> String:
	var parts := PackedStringArray()
	for k in _Glossary.TERMS.keys():  # glossary order = reading order
		if not bd.has(k) or _Glossary.is_hidden(k):
			continue
		var v = bd[k]
		if not (v is float or v is int):
			continue
		if descriptors_only and _Glossary.is_addend(k):
			continue
		if is_zero_approx(float(v)):
			continue  # "Damage already assigned 0" says nothing
		parts.append("%s %s" % [_Glossary.label(k), _Glossary.format_value(k, v)])
		if parts.size() >= MAX_SUMMARY_FACTS:
			break
	return " · ".join(parts)


static func _why_rows(a_bd: Dictionary, b_bd: Dictionary, ledger: bool) -> Array:
	"""Values that differ between the pick (a) and the runner-up (b), biggest
	difference first. ▲ = favoured the pick, ▼ = favoured the runner-up."""
	var diffs: Array = []
	var keys := {}
	for k in a_bd.keys():
		keys[k] = true
	for k in b_bd.keys():
		keys[k] = true
	for k in keys.keys():
		var ks := str(k)
		if _Glossary.is_hidden(ks):
			continue
		var av = a_bd.get(k, 0.0)
		var bv = b_bd.get(k, 0.0)
		if not ((av is float or av is int) and (bv is float or bv is int)):
			continue
		var af := float(av)
		var bf := float(bv)
		var is_pts: bool = ledger and _Glossary.is_addend(ks)
		# A missing score part is a real 0; a missing fact is unknown, not 0.
		if not is_pts and not (a_bd.has(k) and b_bd.has(k)):
			continue
		var favour := 0  # +1 pick, -1 runner-up, 0 neutral
		var weight := 0.0
		if is_pts:
			var d := af - bf
			if absf(d) < 0.005:
				continue
			favour = 1 if d > 0.0 else -1
			weight = absf(d) * 1000.0  # contributions outrank descriptive facts
		else:
			var denom := maxf(maxf(absf(af), absf(bf)), 0.0001)
			var rel := (af - bf) / denom
			if absf(rel) < MIN_REL_DIFF:
				continue
			match _Glossary.good_direction(ks):
				"high":
					favour = 1 if af > bf else -1
				"low":
					favour = 1 if af < bf else -1
			weight = absf(rel)
		diffs.append([ks, af, bf, favour, weight])
	diffs.sort_custom(func(x, y): return x[4] > y[4])
	var rows: Array = []
	for d in diffs:
		if rows.size() >= MAX_WHY_ROWS:
			break
		var k: String = d[0]
		var sym := "▲" if d[3] > 0 else ("▼" if d[3] < 0 else "•")
		var col := HEX_GOOD if d[3] > 0 else (HEX_BAD if d[3] < 0 else HEX_DIM)
		var fa := _Glossary.format_value(k, d[1])
		var fb := _Glossary.format_value(k, d[2])
		if fa == fb:
			continue  # differs only below display precision — "1% vs 1%" reads as noise
		var vals := "%s vs %s" % [fa, fb]
		rows.append(["  [color=%s]%s[/color] %s: %s" % [col, sym, _hint(k), _esc(vals)],
			"  %s %s: %s" % [sym, _Glossary.label(k), vals]])
	return rows


static func _detail_rows(bd: Dictionary, ledger: bool) -> Array:
	"""Every labelled value for one option. In a ledger the score parts come
	first (largest first, with a small bar), then the descriptive facts."""
	var rows: Array = []
	var parts: Array = []
	var facts: Array = []
	for t in _numeric_terms(bd):
		if _Glossary.is_hidden(t[0]):
			continue
		if ledger and _Glossary.is_addend(t[0]):
			if not is_zero_approx(t[1]):  # "Crowding +0.0" is noise
				parts.append(t)
		else:
			facts.append(t)
	parts.sort_custom(func(x, y): return absf(x[1]) > absf(y[1]))
	var max_abs := 0.0
	for t in parts:
		max_abs = maxf(max_abs, absf(t[1]))
	if not parts.is_empty():
		rows.append(["      [color=%s]Score made of:[/color]" % HEX_DIM, "      Score made of:"])
	for t in parts:
		var cells := maxi(1, roundi(absf(t[1]) / maxf(max_abs, 0.0001) * 6.0))
		var bar := "[color=%s]%s[/color]" % [HEX_GOOD if t[1] >= 0.0 else HEX_BAD, "▮".repeat(cells)]
		rows.append(["        %s %s: %s" % [bar, _hint(t[0]), _esc(_Glossary.format_value(t[0], t[1]))],
			"        %s: %s" % [_Glossary.label(t[0]), _Glossary.format_value(t[0], t[1])]])
	if not facts.is_empty():
		var fb := PackedStringArray()
		var ft := PackedStringArray()
		for t in facts:
			fb.append("%s %s" % [_hint(t[0]), _esc(_Glossary.format_value(t[0], t[1]))])
			ft.append("%s %s" % [_Glossary.label(t[0]), _Glossary.format_value(t[0], t[1])])
		var lead := "Facts: " if ledger else ""
		rows.append(["      [color=%s]%s[/color]%s" % [HEX_DIM, lead, " · ".join(fb)], "      %s%s" % [lead, " · ".join(ft)]])
	if rows.is_empty():
		rows.append(["      [color=%s](no values recorded for this option)[/color]" % HEX_FAINT, "      (no values)"])
	return rows


static func _sub_rows(cand: Dictionary) -> Array:
	"""A value that is itself built from parts (e.g. shooting's Target
	priority) — show what it was made of, under the option's details."""
	var rows: Array = []
	var subs = cand.get("sub_breakdowns", {})
	if not (subs is Dictionary):
		return rows
	for sk in subs.keys():
		var terms: Dictionary = subs[sk]
		if terms.is_empty():
			continue
		var parts := _numeric_terms(terms)
		parts.sort_custom(func(x, y): return absf(x[1]) > absf(y[1]))
		var total := 0.0
		for t in parts:
			total += t[1]
		rows.append(["      [color=%s]%s %.1f made of:[/color]" % [HEX_DIM, _hint(str(sk)), total],
			"      %s %.1f made of:" % [_Glossary.label(str(sk)), total]])
		for t in parts:
			if absf(t[1]) < 0.05:
				continue  # "+0.0" lines are noise
			rows.append(["        %s %s: %s" % ["[color=%s]+[/color]" % HEX_GOOD if t[1] >= 0.0 else "[color=%s]−[/color]" % HEX_BAD,
				_hint(t[0]), _esc("%+.1f" % t[1])], "        %s: %+.1f" % [_Glossary.label(t[0]), t[1]]])
	return rows


static func _render_dev(o: _Out, records: Array, analyses: Array) -> void:
	var unlabelled := {}
	for r_i in range(records.size()):
		var rec: Dictionary = records[r_i]
		var a: Dictionary = analyses[r_i]
		o.line("[color=%s][b]%s[/b] (%s)[/color]" % [HEX_GOLD, _esc(str(rec.get("decision_type", "?"))), _esc(str(rec.get("unit_id", "")))],
			"[%s] %s" % [str(rec.get("decision_type", "?")), str(rec.get("unit_id", ""))])
		o.line("[color=%s]Values read as: %s[/color]" % [HEX_DIM, "additive score terms (they sum to the score)" if a.ledger else "factors (they do not sum to the score)"],
			"  read as: %s" % ("ledger" if a.ledger else "factors"))
		for i in a.order:
			var c: Dictionary = a.cands[i]
			var raw := PackedStringArray()
			var bd := _bd(c)
			for k in bd.keys():
				raw.append("%s=%s" % [str(k), _fmt_raw(bd[k])])
				if not _Glossary.has_term(str(k)):
					unlabelled[str(k)] = true
			if raw.is_empty():
				# No score terms (rule-based pick) — name the option so the row isn't blank
				raw.append(str(c.get("description", "")))
			var chk := ""
			if a.ledger and not bool(a.sum_ok.get(i, false)):
				chk = "  ✗ terms do not sum to score"
			var line := "  %s score=%.3f%s  %s" % ["*" if i == a.chosen else "-", _score_of(c), chk, ", ".join(raw)]
			o.line("[color=%s]%s[/color]" % [HEX_FAINT, _esc(line)], line)
		var ctx: Dictionary = rec.get("context", {})
		var cbits := PackedStringArray()
		for k in ctx.keys():
			cbits.append("%s=%s" % [str(k), _fmt_raw(ctx[k])])
		if not cbits.is_empty():
			var l2 := "  context: " + ", ".join(cbits)
			o.line("[color=%s]%s[/color]" % [HEX_FAINT, _esc(l2)], l2)
		var params: Dictionary = rec.get("parameters_used", {})
		if not params.is_empty():
			var pbits := PackedStringArray()
			for k in params.keys():
				pbits.append("%s=%s" % [str(k), _fmt_raw(params[k])])
			var l3 := "  tuning settings read (AIDecisionMaker get_param): " + ", ".join(pbits)
			o.line("[color=%s]%s[/color]" % [HEX_FAINT, _esc(l3)], l3)
	if not unlabelled.is_empty():
		var l4 := "Unlabelled values (add to AIReasoningGlossary.gd): " + ", ".join(PackedStringArray(unlabelled.keys()))
		o.line("[color=%s]%s[/color]" % [HEX_WARN, _esc(l4)], l4)


# --- helpers ---------------------------------------------------------------

static func _heading(o: _Out, title: String, link_key: String = "", _open: bool = true, link_text: String = "") -> void:
	if not o.bb.is_empty():
		o.gap()
	var link := ""
	if link_key != "":
		link = "  [url=%s][color=%s][font_size=13]%s[/font_size][/color][/url]" % [link_key, HEX_LINK, link_text]
	o.line("[b][color=%s]%s[/color][/b]%s" % [HEX_GOLD, _esc(title), link], "== %s ==" % title)


static func _hint(key: String) -> String:
	# Hover tooltip with the glossary explanation
	return "[hint=\"%s\"]%s[/hint]" % [_Glossary.help(key).replace("\"", "'").replace("]", ")").replace("[", "("), _esc(_Glossary.label(key))]


static func _gap_words(chosen: float, other: float) -> String:
	if is_equal_approx(chosen, other):
		return "the same"
	if chosen > 0.0:
		var pct := roundi((chosen - other) / chosen * 100.0)
		if pct > 0:
			return "%d%% lower" % pct
		return "%d%% higher" % -pct
	var d := absf(chosen - other)
	return ("%.2f points %s" if d < 1.0 else "%.1f points %s") % [d, "lower" if other < chosen else "higher"]


static func _shares_numeric_key(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if b.has(k) and (a[k] is float or a[k] is int):
			return true
	return false


static func _numeric_terms(bd: Dictionary) -> Array:
	var out: Array = []
	for k in bd.keys():
		var v = bd[k]
		if v is float or v is int:
			out.append([str(k), float(v)])
	return out


static func _bd(cand) -> Dictionary:
	if cand is Dictionary and cand.get("score_breakdown", {}) is Dictionary:
		return cand.get("score_breakdown", {})
	return {}


static func _score_of(cand) -> float:
	if cand is Dictionary:
		return float(cand.get("score", 0.0))
	return 0.0


static func _fmt_raw(v) -> String:
	if v is float:
		return "%.3f" % v
	return str(v)


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
