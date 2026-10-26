extends PanelContainer
class_name AISuggestionBreakdownPanel

# AISuggestionBreakdownPanel — the "why" card for the on-demand AI suggestion (K).
#
# The suggestion used to surface only the final pick plus its narrated thinking
# steps in the game log. AIDecisionMaker already records much more per decision
# (_ai_decision_records): every candidate it scored, the additive score terms
# each was built from, which one it chose, the tunable parameters it read and
# the decision context. None of that reached the player, so a human reviewing
# the AI could see WHAT it would do but not WHY. This card renders all of it:
#
#   * Verdict      — chosen action, player / phase / round / difficulty
#   * Decisions    — one block per decision record: candidates ranked by score,
#                    chosen row marked, gap to the runner-up, each candidate's
#                    score terms (largest contribution first), flags for close
#                    calls and for picks that are not the top-scored option
#   * Reasoning    — the narrated _ai_thinking_steps
#   * Gaps         — explicitly says when a decision produced no scored record,
#                    so un-instrumented decision paths are visible, not silent
#
# Public API:
#   show_decision(decision: Dictionary, meta: Dictionary)
#   close()
#   breakdown_text: String   (plain-text mirror — scenario asserts + Copy button)
#   record_count: int
#   candidate_count: int
#
# Static, side-effect-free: build_breakdown(decision, meta) -> {bbcode, text,
# records, candidates} so the formatting can be unit-tested headless.

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")

const PANEL_WIDTH := 640.0
const SCREEN_MARGIN := 24.0
const TOP_OFFSET := 110.0  # clear of the top bar
const MAX_TERMS_PER_CANDIDATE := 8
const MAX_CONTEXT_ITEMS := 12
# A runner-up within this fraction of the chosen score (or this absolute gap)
# counts as a close call — a small weight change could flip the decision.
const CLOSE_CALL_REL := 0.05
const CLOSE_CALL_ABS := 0.25

# Per-candidate descriptors some records put in score_breakdown that are NOT
# addends of the score (movement: AIDecisionMaker A2 comment). Kept out of the
# Σ check and shown as info.
const DESCRIPTOR_KEYS := ["expected_vp", "distance_inches", "turns_to_reach"]

const COL_CARD_BG := Color(0.07, 0.065, 0.05, 0.97)
const COL_HEADER_BG := Color(0.14, 0.11, 0.075, 1.0)
const COL_DIM := Color(0.78, 0.74, 0.66)

var breakdown_text: String = ""
var record_count: int = 0
var candidate_count: int = 0

var _title: Label = null
var _subtitle: Label = null
var _rich: RichTextLabel = null


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
	_title.text = "AI SUGGESTION — BREAKDOWN"
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
	_rich.add_theme_font_size_override("normal_font_size", 14)
	_rich.add_theme_font_size_override("bold_font_size", 14)
	_rich.add_theme_color_override("default_color", _WhiteDwarfTheme.WH_PARCHMENT)
	content.add_child(_rich)

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
	hint.text = "Preview only — nothing was executed. K refreshes, Esc closes."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frow.add_child(hint)
	var copy_btn := Button.new()
	copy_btn.name = "CopyButton"
	copy_btn.text = "Copy as text"
	copy_btn.tooltip_text = "Copy the full breakdown to the clipboard (paste into a bug report)"
	_WhiteDwarfTheme.apply_to_button(copy_btn)
	copy_btn.pressed.connect(_on_copy_pressed)
	frow.add_child(copy_btn)

	_apply_fit()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _apply_fit):
		vp.connect("size_changed", _apply_fit)
	print("[AISuggestionBreakdownPanel] Ready")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func show_decision(decision: Dictionary, meta: Dictionary = {}) -> void:
	var built := build_breakdown(decision, meta)
	breakdown_text = built.text
	record_count = built.records
	candidate_count = built.candidates
	if _subtitle:
		_subtitle.text = str(built.subtitle)
	if _rich:
		_rich.clear()
		_rich.append_text(built.bbcode)
		_rich.scroll_to_line(0)
	visible = true
	_refit()
	print("[AISuggestionBreakdownPanel] Showing breakdown: %d decision record(s), %d candidate(s)" % [record_count, candidate_count])
	DebugLogger.info("AISuggestionBreakdownPanel shown", {"records": record_count, "candidates": candidate_count, "type": decision.get("type", "")})


func close() -> void:
	visible = false
	print("[AISuggestionBreakdownPanel] Closed")


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(breakdown_text)
	print("[AISuggestionBreakdownPanel] Copied %d chars to clipboard" % breakdown_text.length())


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
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	var w: float = minf(PANEL_WIDTH, maxf(320.0, vp_size.x - 2.0 * SCREEN_MARGIN))
	var h: float = maxf(240.0, vp_size.y - TOP_OFFSET - SCREEN_MARGIN - 60.0)
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	# Right side: the game log owns the left edge and the board stays visible.
	position = Vector2(roundf(vp_size.x - w - SCREEN_MARGIN), TOP_OFFSET)


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

static func build_breakdown(decision: Dictionary, meta: Dictionary = {}) -> Dictionary:
	"""Format a suggest_action() result into bbcode + a plain-text mirror.
	meta: {player, phase_name, round, difficulty}."""
	var bb := PackedStringArray()
	var tx := PackedStringArray()
	var total_cands := 0

	var subtitle := "P%s · %s · Round %s · reasoning at %s difficulty" % [
		str(meta.get("player", "?")), str(meta.get("phase_name", "?")),
		str(meta.get("round", "?")), str(meta.get("difficulty", "?"))]

	# --- Verdict -----------------------------------------------------------
	_section(bb, tx, "VERDICT")
	if decision.is_empty():
		var why := str(meta.get("empty_reason", "The AI could not find a recommended action here."))
		bb.append("[color=#ffb060]%s[/color]" % _esc(why))
		tx.append(why)
		return {"bbcode": "\n".join(bb), "text": "\n".join(tx), "records": 0,
			"candidates": 0, "subtitle": subtitle}
	var desc := str(decision.get("_ai_description", decision.get("type", "unknown")))
	bb.append("[b][color=#9fe8ff]%s[/color][/b]" % _esc(desc))
	bb.append("[color=#a8a294]Action: %s[/color]" % _esc(str(decision.get("type", ""))))
	tx.append("Chosen: %s" % desc)
	tx.append("Action: %s" % str(decision.get("type", "")))

	# --- Decisions ---------------------------------------------------------
	var records: Array = decision.get("_ai_decision_records", [])
	_section(bb, tx, "DECISIONS (%d)" % records.size())
	if records.is_empty():
		var gap := "⚠ No scored alternatives were recorded for this decision. This decision path is not instrumented — the AI's options and scores cannot be inspected here (instrumentation gap)."
		bb.append("[color=#ffb060]%s[/color]" % _esc(gap))
		tx.append(gap)
	for r_i in range(records.size()):
		total_cands += _format_record(bb, tx, records[r_i], r_i + 1)

	# --- Reasoning ---------------------------------------------------------
	var steps: Array = decision.get("_ai_thinking_steps", [])
	_section(bb, tx, "REASONING (%d steps)" % steps.size())
	if steps.is_empty():
		bb.append("[color=#a8a294](no narrated steps)[/color]")
		tx.append("(no narrated steps)")
	for s in steps:
		bb.append("• %s" % _esc(str(s)))
		tx.append("- %s" % str(s))

	return {"bbcode": "\n".join(bb), "text": "\n".join(tx), "records": records.size(),
		"candidates": total_cands, "subtitle": subtitle}


static func _format_record(bb: PackedStringArray, tx: PackedStringArray, rec: Dictionary, n: int) -> int:
	var cands: Array = rec.get("candidates", [])
	var chosen_idx := int(rec.get("chosen_index", -1))
	var ctx: Dictionary = rec.get("context", {})
	var considered := int(ctx.get("options_considered", ctx.get("alternatives_considered", cands.size())))
	var dtype := str(rec.get("decision_type", "?"))
	var unit_name := str(rec.get("unit_name", rec.get("unit_id", "")))

	bb.append("")
	bb.append("[b][color=#d49761]%d. %s[/color][/b] — %s  [color=#a8a294](%d option(s) considered, %d shown)[/color]" % [
		n, _esc(dtype.to_upper()), _esc(unit_name), considered, cands.size()])
	tx.append("")
	tx.append("%d. %s — %s (%d considered, %d shown)" % [n, dtype.to_upper(), unit_name, considered, cands.size()])

	# Rank by score, remember where the chosen row landed
	var order: Array = []
	for i in range(cands.size()):
		order.append(i)
	order.sort_custom(func(a, b): return _score_of(cands[a]) > _score_of(cands[b]))
	var chosen_score := _score_of(cands[chosen_idx]) if chosen_idx >= 0 and chosen_idx < cands.size() else 0.0
	var best_other := -INF
	for i in order:
		if i != chosen_idx:
			best_other = maxf(best_other, _score_of(cands[i]))

	# Flags
	if chosen_idx >= 0 and not order.is_empty() and order[0] != chosen_idx and _score_of(cands[order[0]]) > chosen_score:
		var f := "⚠ Picked a LOWER-scored option than the top candidate (plan / override / constraint chose it)."
		bb.append("[color=#ffb060]%s[/color]" % _esc(f))
		tx.append(f)
	if best_other > -INF and chosen_idx >= 0:
		var gap := chosen_score - best_other
		if absf(gap) <= maxf(CLOSE_CALL_ABS, absf(chosen_score) * CLOSE_CALL_REL):
			var f2 := "⚖ Close call — runner-up within %.2f. A small weight change could flip this." % absf(gap)
			bb.append("[color=#ffe080]%s[/color]" % _esc(f2))
			tx.append(f2)

	for rank in range(order.size()):
		var i: int = order[rank]
		var cand: Dictionary = cands[i]
		var score := _score_of(cand)
		var is_chosen := i == chosen_idx
		var delta := ""
		if not is_chosen and chosen_idx >= 0:
			delta = "  Δ %+.2f" % (score - chosen_score)
		var marker := "▶" if is_chosen else "  "
		var line := "%s #%d  %.2f%s  %s" % [marker, rank + 1, score, delta, str(cand.get("description", cand.get("key", "")))]
		if is_chosen:
			bb.append("[bgcolor=#1d3a40][b][color=#9fe8ff]%s  (CHOSEN)[/color][/b][/bgcolor]" % _esc(line))
		else:
			bb.append(_esc(line))
		tx.append(line + ("  (CHOSEN)" if is_chosen else ""))
		var terms := _format_terms(cand.get("score_breakdown", {}), score)
		if not terms.is_empty():
			bb.append("[indent][color=#a8a294]%s[/color][/indent]" % _esc(terms))
			tx.append("      " + terms)

	# Context + parameters (compact)
	var ctx_items := PackedStringArray()
	for k in ctx.keys():
		var v = ctx[k]
		if v is Array or v is Dictionary or k == "options_considered" or k == "alternatives_considered":
			continue
		ctx_items.append("%s=%s" % [str(k), _fmt_val(v)])
		if ctx_items.size() >= MAX_CONTEXT_ITEMS:
			break
	if not ctx_items.is_empty():
		var c := "Context: " + ", ".join(ctx_items)
		bb.append("[color=#8c8678]%s[/color]" % _esc(c))
		tx.append(c)
	var params: Dictionary = rec.get("parameters_used", {})
	if not params.is_empty():
		var p_items := PackedStringArray()
		for k in params.keys():
			p_items.append("%s=%s" % [str(k), _fmt_val(params[k])])
		var p := "Tunable params read: " + ", ".join(p_items)
		bb.append("[color=#8c8678]%s[/color]" % _esc(p))
		tx.append(p)
	return cands.size()


static func _format_terms(breakdown, score: float) -> String:
	"""One line per candidate. When the numeric terms (minus known per-candidate
	descriptors) sum to the score, the breakdown is an additive ledger and is
	shown signed with a Σ check; otherwise the values are inputs/factors the
	score was computed from and are shown unsigned."""
	if not (breakdown is Dictionary) or breakdown.is_empty():
		return ""
	var addends: Array = []
	var info: Array = []
	var others := PackedStringArray()
	for k in breakdown.keys():
		var v = breakdown[k]
		if v is float or v is int:
			if DESCRIPTOR_KEYS.has(str(k)):
				info.append([str(k), float(v)])
			else:
				addends.append([str(k), float(v)])
		else:
			others.append("%s: %s" % [str(k), str(v)])
	var total := 0.0
	for t in addends:
		total += t[1]
	var additive: bool = addends.size() > 1 and absf(total - score) <= maxf(0.01, absf(score) * 0.001)
	if not additive:
		# Not a ledger: everything numeric is a factor/input
		addends.append_array(info)
		info = []
	addends.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	var parts := PackedStringArray()
	for t in addends.slice(0, MAX_TERMS_PER_CANDIDATE):
		parts.append(("%s %+.2f" if additive else "%s=%.2f") % [t[0], t[1]])
	if addends.size() > MAX_TERMS_PER_CANDIDATE:
		parts.append("…+%d more" % (addends.size() - MAX_TERMS_PER_CANDIDATE))
	var line := ("Terms (Σ=%.2f): " % total if additive else "Factors: ") + " · ".join(parts)
	var tail := PackedStringArray()
	for t in info:
		tail.append("%s=%.2f" % [t[0], t[1]])
	tail.append_array(others)
	if not tail.is_empty():
		line += "  |  " + ", ".join(tail)
	return line


static func _section(bb: PackedStringArray, tx: PackedStringArray, title: String) -> void:
	if not bb.is_empty():
		bb.append("")
		tx.append("")
	bb.append("[b][color=#d49761]━━ %s ━━[/color][/b]" % _esc(title))
	tx.append("== %s ==" % title)


static func _score_of(cand) -> float:
	if cand is Dictionary:
		return float(cand.get("score", 0.0))
	return 0.0


static func _fmt_val(v) -> String:
	if v is float:
		return "%.2f" % v
	return str(v)


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
