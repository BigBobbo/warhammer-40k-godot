extends CanvasLayer

# Tutorial overlay (PRPs/tutorial_system.md §5.1): the instructor card + soft
# spotlight ring. CanvasLayer 93 — above PadActionBar (92), below VirtualCursor
# (95) so the pad cursor stays visible, below ToastManager (100).
#
# The overlay consumes exactly ONE input (the pad input chain order is
# load-bearing otherwise, PadRouter.gd:76-80): the pad's select button while
# the card is waiting on a Continue / Next Lesson press — see _input(). Every
# other control stays a plain button the mouse or the virtual cursor can click.
# Colors come from UIConstants / WhiteDwarfTheme — no new hex literals (design
# guidelines §9).

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")
const UIConstantsData = preload("res://autoloads/UIConstants.gd")
const AnchorResolverLib = preload("res://scripts/tutorial/AnchorResolver.gd")
const GlyphDB = preload("res://scripts/input/GlyphDB.gd")

const CARD_TOP_OFFSET := 96.0
const CARD_BOTTOM_OFFSET := 132.0  # keeps clear of the pad hint bar
const ANCHOR_RERESOLVE_S := 0.5

# --- card sizing (see _dodge_dialog) ---
# Width of the card's text column when nothing is crowding it. The card itself
# is this + CARD_CHROME_W (the Margin container's 12+12 plus the White Dwarf
# panel border), i.e. 588px at the default scale.
const CARD_CONTENT_WIDTH := 560.0
const CARD_CHROME_W := 28.0
const CARD_EDGE_MARGIN := 10.0   # gap between the card and the screen edge
const CARD_DIALOG_GAP := 12.0    # gap between the card and a dialog it dodges
# Absolute backstop for the text column. The REAL floor is whatever the card's
# own buttons need on one row, measured live by _min_content_width() — a fixed
# number here would be silently invalidated by any font change (the Steam Deck
# legibility pass moved the footer's worst case from ~278px to ~339px, which is
# exactly the kind of drift a constant cannot notice).
const CARD_MIN_CONTENT_WIDTH := 200.0
const FOOTER_SEPARATION := 8.0
# Narrower than this and the footer's buttons need the whole row; the step
# counter is the one thing on the card a player can lose without losing the
# instruction, so it goes first.
const CARD_PROGRESS_HIDE_W := 380.0
# How much roomier the right gutter must be before the card crosses the screen.
const CARD_SIDE_SWAP_BIAS := 64.0
const CRAMPED_LOG_INTERVAL_MS := 5000

# The two escape-hatch affordances (see "modal escape hatch" below). Both names
# are excluded from _open_game_windows() so the tutorial's own windows never
# read as "a game dialog is open" — and so the card never tries to dodge the
# hatch that exists to rescue the player from a real dialog.
const MODAL_EXIT_WINDOW_NAME := "TutorialModalExit"
const EXIT_CONFIRM_NAME := "TutorialExitConfirm"
const INJECTED_EXIT_META := "tutorial_exit_button"

var _spotlight: Control
var _card: PanelContainer
var _instructor_chip: Label
var _bark_label: Label
var _body_text: RichTextLabel
var _checklist_text: RichTextLabel
var _hint_label: Label
var _progress_label: Label
var _continue_button: Button
var _skip_button: Button
var _exit_button: Button
var _next_button: Button
var _menu_button: Button
var _ack_glyph: HBoxContainer   # [A] badge shown beside Continue on a pad

var _checklist_label: String = ""
var _anchor_spec: Dictionary = {}
var _anchor_node: Node = null
var _anchor_rect: Rect2 = Rect2()
var _anchor_ok: bool = false
var _spotlight_mode: String = "none"
var _reresolve_accum: float = 0.0
# Empty until _build()'s first _place_card() lands, so that call is never
# swallowed by the "nothing changed" guard.
var _card_mode: String = ""
var _card_content_w: float = -1.0
var _last_cramped_log_ms: int = 0
var _dim_strips: Array = []
# Kept so _min_content_width() can ask them how much room they need.
var _header: HBoxContainer = null
var _footer: HBoxContainer = null
var _modal_exit_window: Window = null   # floating hatch, for non-AcceptDialog modals
var _modal_exit_host: Window = null     # the dialog we added an Exit button INTO
# The in-dialog hatch is ARMED, not always-on — see "modal escape hatch" below.
# Set by note_action_blocked() (the lesson gate really did reject something while
# this dialog was up), cleared when the blocker closes or the step changes.
var _hatch_armed: bool = false
var _hatch_armed_host: Window = null


func _ready() -> void:
	layer = 93
	_build()
	visible = false
	set_process(false)
	# The card's pad affordances (the [A] badge, which button holds focus, the
	# hint-bar promise) are all device-dependent — re-apply them whenever the
	# player swaps between pad and mouse mid-card, and re-render the badge when
	# a controller remap moves the select role to a different button.
	var idm := get_node_or_null("/root/InputDeviceManager")
	if idm != null and idm.has_signal("device_changed"):
		idm.device_changed.connect(func(_mode): _apply_pad_affordances(false))
	var pb := get_node_or_null("/root/PadBindings")
	if pb != null and pb.has_signal("pad_binding_changed"):
		pb.pad_binding_changed.connect(func(_role_id): _rebuild_ack_glyph())


func _mgr() -> Node:
	return get_node_or_null("/root/TutorialManager")


# ------------------------------------------------------------------ build ---

func _build() -> void:
	_spotlight = Control.new()
	_spotlight.name = "Spotlight"
	_spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spotlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spotlight.draw.connect(_draw_spotlight)
	add_child(_spotlight)

	# Strict-mode dimmer: four ColorRect strips framing the anchor cutout.
	# mouse_filter STOP means stray pointer input outside the hole is
	# swallowed; input inside the hole passes to the game untouched
	# (PRPs/tutorial_system.md §4.3). Built BEFORE the card so the card
	# stays on top and clickable.
	for i in range(4):
		var strip := ColorRect.new()
		strip.name = "DimStrip%d" % i
		strip.color = Color(WhiteDwarfThemeData.WH_BLACK, 0.45)
		strip.mouse_filter = Control.MOUSE_FILTER_STOP
		strip.visible = false
		add_child(strip)
		_dim_strips.append(strip)

	# NOTE on stacking: embedded Windows (the AcceptDialog family —
	# Formations, roll-off, command re-roll...) composite ABOVE every
	# CanvasLayer, so no layer number can keep the card on top of them.
	# Hosting the card in its own always-on-top Window renders correctly but
	# synthetic input (virtual cursor clicks, windowed scenarios) cannot
	# reach embedded-window buttons — so instead the card DODGES into the
	# screen gutter beside an open dialog, resized to fit it. See
	# _dodge_dialog(). Found while validating T2.
	_card = PanelContainer.new()
	_card.name = "InstructorCard"
	WhiteDwarfThemeData.apply_to_panel(_card)
	add_child(_card)

	# Stable node names throughout — windowed scenarios address these by path.
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	_header = header
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_instructor_chip = Label.new()
	_instructor_chip.name = "InstructorChip"
	_instructor_chip.text = "DA BOSS"
	_instructor_chip.add_theme_font_size_override("font_size", 16)
	_instructor_chip.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_BLACK)
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = WhiteDwarfThemeData.WH_GOLD
	chip_style.set_corner_radius_all(4)
	chip_style.content_margin_left = 8
	chip_style.content_margin_right = 8
	chip_style.content_margin_top = 2
	chip_style.content_margin_bottom = 2
	var chip_panel := PanelContainer.new()
	chip_panel.name = "ChipPanel"
	chip_panel.add_theme_stylebox_override("panel", chip_style)
	chip_panel.add_child(_instructor_chip)
	header.add_child(chip_panel)

	_bark_label = Label.new()
	_bark_label.name = "BarkLabel"
	# Autowrap so a long bark can never be what forces the card wider than the
	# gutter _dodge_dialog sized it for (a Label without it reports its whole
	# single-line width as a hard minimum).
	_bark_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark_label.add_theme_font_size_override("font_size", 21)
	_bark_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	_bark_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_bark_label)

	_body_text = RichTextLabel.new()
	_body_text.name = "BodyText"
	_body_text.bbcode_enabled = true
	_body_text.fit_content = true
	_body_text.scroll_active = false
	_body_text.custom_minimum_size = Vector2(CARD_CONTENT_WIDTH, 0)
	_body_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# >= 12px effective at 1280x800 (Steam Deck recommendation; PRP §4.3):
	# 15px at 1920x1080 canvas-items scaling ~= 10px physical on Deck before the
	# pad UI-scale boost (x1.2) SettingsService applies in pad mode.
	_body_text.add_theme_font_size_override("normal_font_size", 19)
	_body_text.add_theme_font_size_override("bold_font_size", 19)
	_body_text.add_theme_color_override("default_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_body_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body_text)

	# Live tick list for multi-input steps ("try every camera control"). Hidden
	# on steps with no checklist. One RichTextLabel rather than a row of child
	# controls so the chip BBCode from the prompt vocabulary ({key:...}, {rs})
	# renders the same way here as in the body, and so scenarios can assert the
	# whole list with a single node read.
	_checklist_text = RichTextLabel.new()
	_checklist_text.name = "ChecklistText"
	_checklist_text.bbcode_enabled = true
	_checklist_text.fit_content = true
	_checklist_text.scroll_active = false
	_checklist_text.custom_minimum_size = Vector2(CARD_CONTENT_WIDTH, 0)
	_checklist_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checklist_text.add_theme_font_size_override("normal_font_size", 18)
	_checklist_text.add_theme_font_size_override("bold_font_size", 18)
	_checklist_text.add_theme_color_override("default_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_checklist_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checklist_text.visible = false
	vbox.add_child(_checklist_text)

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(CARD_CONTENT_WIDTH, 0)
	_hint_label.add_theme_font_size_override("font_size", 17)
	_hint_label.add_theme_color_override("font_color", UIConstantsData.MARGINAL_YELLOW)
	_hint_label.visible = false
	vbox.add_child(_hint_label)

	var footer := HBoxContainer.new()
	_footer = footer
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	# Same reason as the bark: wrapped, its minimum width is one word rather
	# than the whole "Step 1 / 8 — Musterin' da Boyz" string, so a narrow card
	# keeps room for the buttons beside it.
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.add_theme_color_override("font_color",
		Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.6))
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_progress_label)

	# Pad players had no way of knowing the card's Continue was reachable at all
	# — the reported "Read da Bar" dead end, where the only way forward was to
	# discover the left-stick cursor and click the button with it. The badge
	# names the button that presses it (kept OUTSIDE the Button so its text
	# stays exactly "Continue" — windowed scenarios address it by text).
	_ack_glyph = HBoxContainer.new()
	_ack_glyph.name = "AckGlyph"
	_ack_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ack_glyph.visible = false
	footer.add_child(_ack_glyph)
	_rebuild_ack_glyph()

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "Continue"
	WhiteDwarfThemeData.apply_primary_button(_continue_button)
	_continue_button.pressed.connect(_on_continue_pressed)
	footer.add_child(_continue_button)

	_next_button = Button.new()
	_next_button.name = "NextLessonButton"
	_next_button.text = "Next Lesson"
	WhiteDwarfThemeData.apply_primary_button(_next_button)
	_next_button.visible = false
	_next_button.pressed.connect(func():
		_next_button.release_focus()
		var m := _mgr()
		if m: m.next_lesson())
	footer.add_child(_next_button)

	_menu_button = Button.new()
	_menu_button.name = "BackToMenuButton"
	_menu_button.text = "Back to Menu"
	WhiteDwarfThemeData.apply_secondary_button(_menu_button)
	_menu_button.visible = false
	_menu_button.pressed.connect(func():
		var m := _mgr()
		if m: m.exit_tutorial())
	footer.add_child(_menu_button)

	_skip_button = Button.new()
	_skip_button.name = "SkipStepButton"
	_skip_button.text = "Skip Step"
	WhiteDwarfThemeData.apply_secondary_button(_skip_button)
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(func():
		var m := _mgr()
		if m: m.skip_step())
	footer.add_child(_skip_button)

	_exit_button = Button.new()
	_exit_button.name = "ExitTutorialButton"
	_exit_button.text = "Exit Tutorial"
	_exit_button.tooltip_text = "Leave the tutorial and go back to the main menu (asks first)."
	WhiteDwarfThemeData.apply_secondary_button(_exit_button)
	_exit_button.focus_mode = Control.FOCUS_NONE
	_exit_button.pressed.connect(_on_exit_pressed)
	footer.add_child(_exit_button)

	_place_card("top")


# ------------------------------------------------------- pad affordances ----
#
# THE PROBLEM THIS SOLVES (reported on the Steam Deck at T1 step 7, "Read da
# Bar"): the card's Continue button was focus-grabbed on pad, but the moment
# the player had touched the left stick — which every earlier step asks them to
# do — VirtualCursor is in CURSOR mode and consumes A as a synthetic click AT
# THE CURSOR (VirtualCursor.gd:248-256). So A did nothing unless the cursor
# happened to be parked on top of Continue, and the ONLY way past an ack step
# was to hunt the button down with the stick. Three fixes, together:
#   1. _input() below: while the card waits on a press, the pad's select button
#      presses it — cursor mode or not, focus or not.
#   2. the [A] badge beside the button + the hint bar's "Ⓐ Continue" chip
#      (PadRouter.HINTS_TUTORIAL_ACK) say so on screen.
#   3. focus is parked on the card and kept there (_wire_card_focus +
#      the _process re-grab), so the gold PadFocusRing marks the button and no
#      D-pad press can strand the player in a HUD panel with no way back.


# "" (nothing pending), "ack" (a Continue step) or "summary" (the end-of-lesson
# card). Read by PadRouter for the hint bar, and by windowed scenarios.
func pad_ack_state() -> String:
	if not visible:
		return ""
	if _continue_button != null and _continue_button.visible:
		return "ack"
	if (_next_button != null and _next_button.visible) or (_menu_button != null and _menu_button.visible):
		return "summary"
	return ""


# The card button the pad's select button should press: whichever of them holds
# focus, else the leading one (Continue on a step, Next Lesson on a summary).
func _pad_ack_button() -> Button:
	if not visible:
		return null
	var focused := get_viewport().gui_get_focus_owner()
	var candidates: Array = []
	for b in [_continue_button, _next_button, _menu_button]:
		if b != null and b.visible and not b.disabled:
			candidates.append(b)
	for b in candidates:
		if b == focused:
			return b
	return candidates[0] if not candidates.is_empty() else null


func _rebuild_ack_glyph() -> void:
	if _ack_glyph == null:
		return
	for child in _ack_glyph.get_children():
		child.queue_free()
	# Label-less chip: the button text next to it already says "Continue".
	_ack_glyph.add_child(GlyphDB.make_chip("a", ""))


# Keep D-pad focus navigation INSIDE the card while it is waiting on a press:
# left/right walk the card's own buttons, up/down/tab stay put. Without this a
# D-pad press walks focus off into the HUD and the player has no way back to
# Continue (the reported "I can't get to the button" trap).
func _wire_card_focus(buttons: Array) -> void:
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		var prev: Button = buttons[max(i - 1, 0)]
		var nxt: Button = buttons[min(i + 1, buttons.size() - 1)]
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(nxt)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_next = b.get_path_to(nxt)
		b.focus_previous = b.get_path_to(prev)


# `grab` = take focus now (a freshly shown card); false only re-applies the
# device-dependent dressing (a mid-card device swap / remap).
func _apply_pad_affordances(grab: bool) -> void:
	if _continue_button == null:
		return  # _build() has not run yet
	var idm := get_node_or_null("/root/InputDeviceManager")
	var pad: bool = idm != null and idm.is_pad_active()
	_ack_glyph.visible = pad and visible and _continue_button.visible
	var buttons: Array = []
	for b in [_continue_button, _next_button, _menu_button]:
		if b.visible:
			buttons.append(b)
	if pad and visible and not buttons.is_empty():
		_wire_card_focus(buttons)
		# Hand the pad back to FOCUS mode: parked, A means "press the
		# highlighted card button" (and the focus ring shows which). A live
		# model carry owns the cursor, so never yank it out from under one.
		var vc := get_node_or_null("/root/VirtualCursor")
		var router := get_node_or_null("/root/PadRouter")
		if vc != null and (router == null or not router.is_carrying()):
			vc.park()
		if grab or get_viewport().gui_get_focus_owner() == null:
			buttons[0].grab_focus()
	_refresh_pad_hints()


# The hint bar reads pad_ack_state() itself; poke it so the promise flips the
# moment the card appears or clears, rather than on the next button press.
func _refresh_pad_hints() -> void:
	var router := get_node_or_null("/root/PadRouter")
	if router != null and router.has_method("refresh_hints"):
		router.refresh_hints()


# The one consumed input (see the header + the block comment above): the pad's
# select button presses the card's pending button. Runs BEFORE VirtualCursor in
# the _input chain (autoload order: … PadRouter, VirtualCursor, … ,
# TutorialOverlay, TutorialManager, Main — _input walks the tree in reverse),
# so it wins over the cursor's synthetic click.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventJoypadButton) or not event.pressed:
		return
	var idm := get_node_or_null("/root/InputDeviceManager")
	if idm == null or not idm.is_pad_active():
		return  # first press of a session claims pad mode (PadRouter); act on the next
	var pb := get_node_or_null("/root/PadBindings")
	var button: int = pb.canonical(event.button_index) if pb != null else event.button_index
	if button != JOY_BUTTON_A:
		return
	# An embedded game dialog and the pad action bar are each modal over the
	# card — they own A while they are up.
	if _any_game_window_open():
		return
	var bar := get_node_or_null("/root/PadActionBar")
	if bar != null and bar.has_method("is_open") and bar.is_open():
		return
	# Cursor mode with the pointer resting ON the card: the aim is explicit, so
	# let the cursor's own click pick the button. Gliding onto "Back to Menu"
	# must not press the focused "Next Lesson", and Skip Step / Exit Tutorial
	# stay clickable. Anywhere else — over the board, over a HUD panel the last
	# step left the cursor on, or parked — A belongs to the card.
	var vc := get_node_or_null("/root/VirtualCursor")
	var hovered := get_viewport().gui_get_hovered_control()
	if vc != null and vc.is_cursor_active() and hovered != null and _card.is_ancestor_of(hovered):
		return
	var target := _pad_ack_button()
	if target == null:
		return
	get_viewport().set_input_as_handled()
	target.emit_signal("pressed")


# Card placement modes: "top" (default), "bottom" (dodging a board anchor),
# "left"/"right" (dodging an open game dialog, in the screen gutter beside it).
# `content_w` is the width of the text column — the side modes shrink it to fit
# the gutter, everything else uses the roomy default.
func _place_card(mode: String, content_w: float = CARD_CONTENT_WIDTH) -> void:
	content_w = clampf(content_w, _min_content_width(), CARD_CONTENT_WIDTH)
	if mode == _card_mode and is_equal_approx(content_w, _card_content_w):
		return  # nothing to re-apply — leave shake()'s tween alone
	_card_mode = mode
	if not is_equal_approx(content_w, _card_content_w):
		_card_content_w = content_w
		for c in [_body_text, _checklist_text, _hint_label]:
			if c != null:
				c.custom_minimum_size.x = content_w
		if _progress_label != null:
			_progress_label.visible = content_w >= CARD_PROGRESS_HIDE_W
	var total_w: float = content_w + CARD_CHROME_W
	match mode:
		"bottom":
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
			_card.offset_bottom = -CARD_BOTTOM_OFFSET
			_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		"left", "right":
			# Width is pinned by BOTH horizontal offsets rather than left by
			# PRESET_MODE_MINSIZE, so the card is exactly as wide as the gutter
			# the caller measured — a minimum size that has not been
			# recalculated yet cannot silently widen it back over the dialog.
			# Vertically: a zero-height rect on the centre line, grown BOTH
			# ways. Control re-clamps that to the real minimum height every
			# time it changes, so the card stays centered and correctly sized
			# WITHOUT reading get_combined_minimum_size() here — which lies
			# right after a width change (the RichTextLabels have not re-wrapped
			# yet, so it reports a many-line height that would then be frozen
			# into these offsets).
			_card.anchor_top = 0.5
			_card.anchor_bottom = 0.5
			_card.offset_top = 0.0
			_card.offset_bottom = 0.0
			_card.grow_vertical = Control.GROW_DIRECTION_BOTH
			if mode == "left":
				_card.anchor_left = 0.0
				_card.anchor_right = 0.0
				_card.offset_left = CARD_EDGE_MARGIN
				_card.offset_right = CARD_EDGE_MARGIN + total_w
				_card.grow_horizontal = Control.GROW_DIRECTION_END
			else:
				_card.anchor_left = 1.0
				_card.anchor_right = 1.0
				_card.offset_left = -(CARD_EDGE_MARGIN + total_w)
				_card.offset_right = -CARD_EDGE_MARGIN
				_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_:
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
			_card.offset_top = CARD_TOP_OFFSET
			_card.grow_vertical = Control.GROW_DIRECTION_END
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH


func card_rect() -> Rect2:
	return _card.get_global_rect()


# Exposed for windowed scenarios: which dodge the card is currently using.
func card_placement() -> String:
	return _card_mode


# The narrowest the text column may get: whatever this step's own buttons need
# to sit on one row, plus whatever the header needs. Measured rather than
# pinned, because a font-size change moves it (the Steam Deck legibility pass
# took the footer's worst case from ~278px to ~339px) and a stale constant
# would quietly start letting the buttons overflow the card.
#
# The progress label is deliberately NOT counted: it autowraps, so its own
# minimum is ~1px, and including it would couple the floor to a visibility this
# very function decides — a 9px oscillation waiting to happen.
func _min_content_width() -> float:
	var buttons := 0.0
	var shown := 0
	for c in [_ack_glyph, _continue_button, _next_button, _menu_button, _skip_button, _exit_button]:
		if c != null and c.visible:
			buttons += c.get_combined_minimum_size().x
			shown += 1
	if shown > 1:
		buttons += FOOTER_SEPARATION * float(shown - 1)
	var need: float = maxf(buttons, _header.get_combined_minimum_size().x if _header != null else 0.0)
	return clampf(need, CARD_MIN_CONTENT_WIDTH, CARD_CONTENT_WIDTH)


# Every visible gameplay Window, in tree order (so the last is the topmost).
# These composite above every CanvasLayer, so the card must dodge them.
#
# The tutorial's OWN windows (the escape hatch, the exit confirm) are skipped:
# they must not read as "a game dialog is open" — that would switch the pad's A
# away from the card — and the card must not dodge the very hatch that exists
# to rescue the player from a real dialog.
func _open_game_windows() -> Array:
	var out: Array = []
	for scope in [get_tree().root, get_tree().root.get_node_or_null("Main")]:
		if scope == null:
			continue
		for child in scope.get_children():
			if not (child is Window) or child == get_tree().root:
				continue
			if not (child as Window).visible:
				continue
			if child.name == MODAL_EXIT_WINDOW_NAME or child.name == EXIT_CONFIRM_NAME:
				continue
			out.append(child as Window)
	return out


# True while any embedded game Window (AcceptDialog family) is showing.
func _any_game_window_open() -> bool:
	return _blocking_window() != null


# The topmost visible gameplay Window, or null.
func _blocking_window() -> Window:
	var open := _open_game_windows()
	return open.back() if not open.is_empty() else null


# Screen-space bounds of everything _open_game_windows() covers, or a zero rect
# when none are up.
func _dialog_bounds() -> Rect2:
	var out := Rect2()
	var found := false
	for w in _open_game_windows():
		var win: Window = w
		var r := Rect2(Vector2(win.position), Vector2(win.size))
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		# An embedded window's `position` is its CLIENT area — the title bar is
		# drawn above it. Count it in, or the card can end up under the title.
		if win.has_theme_constant("title_height", "Window"):
			var title_h := float(win.get_theme_constant("title_height", "Window"))
			r.position.y -= title_h
			r.size.y += title_h
		out = r if not found else out.merge(r)
		found = true
	return out if found else Rect2()


# ------------------------------------------------- modal escape hatch -------
#
# Godot's embedded EXCLUSIVE Windows block every input to the parent viewport,
# so while one is open the card's own Exit Tutorial button is dead — measured,
# not assumed: with a gameplay dialog up, a probe node in the main viewport saw
# zero _input/_shortcut_input/_unhandled_input events and a click on Exit
# Tutorial left the lesson running. That is precisely when a player wants out
# (the reported softlock: the first-turn roll-off opening while the step still
# asked for the grots to be deployed, with the step's allow-list rejecting the
# roll). So the exit has to be re-offered somewhere the modal cannot swallow.
#
# Two mirrored affordances, one per kind of blocker, both verified live:
#   * AcceptDialog (every gameplay dialog in the game) — add_button() puts
#     "Exit Tutorial" in the dialog's OWN button bar, inside the window that
#     holds focus, so mouse and pad both reach it.
#   * anything else — a sibling always-on-top Window floats the button over the
#     top. popup() would steal focus, so it is handed straight back to the
#     blocker; the hatch stays clickable without it (verified).
#
# WHY THE IN-DIALOG BUTTON IS ARMED, NOT ALWAYS-ON (reported on a pad, T2 and
# T5): offering it on EVERY dialog cost the player control of the dialog itself.
# Measured live on the T2 deployment roll-off with the pad active:
#   * AcceptDialog.add_button() lands the button in the dialog's own button bar,
#     which is a SEPARATE FOCUS ROOT from the dialog's content (both are
#     children of the Window, so Control.find_valid_focus_neighbor stops at
#     whichever of the two the focused button lives under). Focus that starts in
#     the button bar can NEVER reach "⚄ Roll the dice" — all four D-pad
#     directions left the focus on TutorialExitButton, verified by probing
#     RollOffDialog.gui_get_focus_owner() after each press.
#   * and focus DID start there: InputDeviceManager's dialog watcher focuses the
#     dialog's confirm button on popup, and its scan found the injected button
#     first — so a pad player opened the roll-off already parked on "Exit
#     Tutorial", with no way off it. Both roll-offs, the command re-roll offered
#     on an Advance and the charge roll all behaved the same way.
# A dice popup is not a place anyone needs to quit from — you press its button,
# it closes, and the card's own Exit Tutorial is live again. So the in-dialog
# button now appears only once the lesson gate has actually REJECTED something
# while this dialog was up (note_action_blocked), which is exactly the reported
# softlock it was built for: the roll-off that opened on a step whose allow-list
# refused the roll. Until then the dialog keeps every one of its own buttons.
func _sync_modal_exit() -> void:
	var host := _blocking_window()
	if host != _hatch_armed_host:
		# A different blocker (or none): whatever the player was blocked on is
		# gone, so the hatch has to re-earn its place.
		_hatch_armed = false
		_hatch_armed_host = host
	# The card's own footer buttons cannot be pressed while a modal is up, so say
	# so: a live-looking Exit Tutorial that swallows every click is what made the
	# reported softlock feel unescapable. Greyed here, re-offered below.
	_set_footer_enabled(host == null, host != null and host is AcceptDialog and not _hatch_armed)
	if host == null:
		clear_modal_exit()
		return
	if host is AcceptDialog:
		_hide_modal_exit_window()
		if not _hatch_armed:
			_clear_injected_button()
			return
		if _modal_exit_host != host or not _injected_button_alive() or not _focus_link_alive():
			_clear_injected_button()
			_inject_exit_button(host as AcceptDialog)
		return
	_clear_injected_button()
	_show_modal_exit_window(host)


# Called by TutorialManager.on_action_blocked: the step's allow-list just refused
# something. If a dialog is what the player is stuck behind, that is the signal
# to offer the escape hatch inside it (see the block comment above).
func note_action_blocked() -> void:
	var host := _blocking_window()
	if host == null:
		return
	_hatch_armed = true
	_hatch_armed_host = host
	_sync_modal_exit()


# `dismissible` = a dialog is up but the player is not stuck behind it (no hatch
# offered), so the tooltip must point at the dialog instead of at a button that
# is not there.
func _set_footer_enabled(enabled: bool, dismissible: bool = false) -> void:
	var blocked_tip := "A dialog is open — use its own Exit Tutorial button."
	if dismissible:
		blocked_tip = "A dialog is open — finish it first, then you can leave."
	var tip := "Leave the tutorial and go back to the main menu (asks first)." if enabled else blocked_tip
	# Called every frame from _process, so bail once both the state AND the reason
	# already match — the tooltip flips between the two blocked wordings when the
	# hatch arms, which a disabled-only check would miss.
	if _exit_button != null and _exit_button.disabled == (not enabled) and _exit_button.tooltip_text == tip:
		return
	for b in [_skip_button, _exit_button]:
		if b == null:
			continue
		b.disabled = not enabled
		if b == _exit_button:
			b.tooltip_text = tip


# A dialog may rebuild its button row while the hatch is up (RollOffDialog goes
# Roll → Re-roll → Deploy First/Second → Continue), freeing the control the
# hatch's focus neighbours point at. Re-inject when that happens, so the way
# back out of the hatch always lands on the button the dialog wants pressed NOW.
func _focus_link_alive() -> bool:
	if _modal_exit_host == null or not _modal_exit_host.has_meta(INJECTED_EXIT_META):
		return false
	var btn = _modal_exit_host.get_meta(INJECTED_EXIT_META)
	if not is_instance_valid(btn) or not btn.has_meta(_LINKED_PRIMARY_META):
		return false
	var primary = btn.get_meta(_LINKED_PRIMARY_META)
	if primary == null:
		return true  # the dialog had nothing to link to; re-injecting would just spin
	return is_instance_valid(primary) and primary.is_visible_in_tree()


func _injected_button_alive() -> bool:
	if _modal_exit_host == null or not is_instance_valid(_modal_exit_host):
		return false
	if not _modal_exit_host.has_meta(INJECTED_EXIT_META):
		return false
	return is_instance_valid(_modal_exit_host.get_meta(INJECTED_EXIT_META))


func _inject_exit_button(dialog: AcceptDialog) -> void:
	# `right: false` keeps it on the LEFT of the button bar, away from the
	# dialog's primary action — leaving is never a fat-finger away from rolling.
	var btn: Button = dialog.add_button("Exit Tutorial", false, "tutorial_exit")
	btn.name = "TutorialExitButton"
	# Never the pad's auto-focus pick: this button is bolted onto someone else's
	# dialog, so focusing it makes A mean "leave the tutorial" while the step is
	# telling the player to press A on the dialog's own action (the reported
	# roll-off / command-reroll trap). InputDeviceManager keeps it as a
	# last-resort target only.
	btn.set_meta(InputDeviceManager.PAD_FOCUS_LAST_META, true)
	btn.tooltip_text = "Leave the tutorial and go back to the main menu (asks first)."
	WhiteDwarfThemeData.apply_secondary_button(btn)
	btn.pressed.connect(_on_exit_pressed)
	dialog.set_meta(INJECTED_EXIT_META, btn)
	_modal_exit_host = dialog
	_link_exit_button_focus(dialog, btn)
	print("TutorialOverlay: added Exit Tutorial to modal '%s'" % str(dialog.name))


# The button bar and the dialog's content are separate focus roots (see the
# block comment above), so without explicit neighbours a D-pad player who lands
# on the hatch can never walk back to the dialog's own action. Explicit
# focus_neighbor NodePaths are honoured across roots — wire both directions.
const _PRIMARY_NEIGHBOR_META := "tutorial_saved_focus_bottom"
const _LINKED_PRIMARY_META := "tutorial_linked_primary"

func _link_exit_button_focus(dialog: AcceptDialog, btn: Button) -> void:
	var primary := _dialog_primary_button(dialog, btn)
	# Always stamp the meta, even with nothing to link — _focus_link_alive() reads
	# it to decide whether to re-inject, and a missing stamp would spin.
	btn.set_meta(_LINKED_PRIMARY_META, primary)
	if primary == null:
		return
	btn.focus_neighbor_top = btn.get_path_to(primary)
	btn.focus_neighbor_bottom = btn.get_path_to(primary)
	btn.focus_neighbor_left = btn.get_path_to(primary)
	btn.focus_neighbor_right = btn.get_path_to(primary)
	# Give the dialog's own button a way back, restoring whatever it had when the
	# hatch goes away (most dialogs leave these empty and rely on geometry).
	# Remember WHICH button we touched — a dialog that rebuilds its button row
	# mid-life (RollOffDialog: Roll → Deploy First/Second) must not have the
	# restore land on a different, untouched control.
	primary.set_meta(_PRIMARY_NEIGHBOR_META, primary.focus_neighbor_bottom)
	primary.focus_neighbor_bottom = primary.get_path_to(btn)


# The button the dialog wants pressed: the first visible, focusable Button that
# is NOT in the dialog's own button bar (where the hatch and the hidden OK live).
func _dialog_primary_button(dialog: AcceptDialog, exclude: Button) -> Button:
	var bar: Node = exclude.get_parent()
	var queue: Array = [dialog]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Button and n != exclude and n.visible and not n.disabled \
				and n.focus_mode != Control.FOCUS_NONE and n.get_parent() != bar:
			return n
		for c in n.get_children(true):
			queue.append(c)
	return null


func _clear_injected_button() -> void:
	if _modal_exit_host != null and is_instance_valid(_modal_exit_host):
		if _modal_exit_host.has_meta(INJECTED_EXIT_META):
			var btn = _modal_exit_host.get_meta(INJECTED_EXIT_META)
			if is_instance_valid(btn):
				if btn.has_meta(_LINKED_PRIMARY_META):
					var primary = btn.get_meta(_LINKED_PRIMARY_META)
					if is_instance_valid(primary) and primary.has_meta(_PRIMARY_NEIGHBOR_META):
						primary.focus_neighbor_bottom = primary.get_meta(_PRIMARY_NEIGHBOR_META)
						primary.remove_meta(_PRIMARY_NEIGHBOR_META)
				btn.queue_free()
			_modal_exit_host.remove_meta(INJECTED_EXIT_META)
	_modal_exit_host = null


func _build_modal_exit_window() -> void:
	_modal_exit_window = Window.new()
	_modal_exit_window.name = MODAL_EXIT_WINDOW_NAME
	_modal_exit_window.borderless = true
	_modal_exit_window.unresizable = true
	_modal_exit_window.transient = true
	_modal_exit_window.always_on_top = true
	_modal_exit_window.exclusive = false
	# A fresh Window is ALREADY visible, so adding it to the tree would show it
	# at the default 100x100 top-left corner — over the top HUD bar — and the
	# "already visible, nothing to do" guard in _show_modal_exit_window would
	# then skip the popup() that places it. Start hidden; popup() does the rest.
	_modal_exit_window.visible = false

	var panel := PanelContainer.new()
	panel.name = "Panel"
	WhiteDwarfThemeData.apply_to_panel(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_exit_window.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	panel.add_child(margin)

	var btn := Button.new()
	btn.name = "ExitTutorialButton"
	btn.text = "Exit Tutorial"
	btn.tooltip_text = "Leave the tutorial and go back to the main menu (asks first)."
	WhiteDwarfThemeData.apply_secondary_button(btn)
	btn.pressed.connect(_on_exit_pressed)
	margin.add_child(btn)

	get_tree().root.add_child(_modal_exit_window)


func _show_modal_exit_window(host: Window) -> void:
	if _modal_exit_window == null or not is_instance_valid(_modal_exit_window):
		_build_modal_exit_window()
	if _modal_exit_window.visible:
		return
	var vp: Vector2 = get_tree().root.get_visible_rect().size
	var win_size := Vector2i(180, 48)
	# Top-right, below the HUD bar: clear of the card (which _dodge_dialog pins
	# to the left flank whenever this hatch is up) and of the centred dialogs
	# the hatch exists to escape.
	_modal_exit_window.popup(Rect2i(
		Vector2i(int(vp.x) - win_size.x - 20, int(CARD_TOP_OFFSET)), win_size))
	# popup() focuses the new window; give focus straight back so the blocking
	# dialog keeps driving keyboard/pad. The hatch stays mouse-clickable either
	# way — that is the whole point of it being a sibling window.
	if is_instance_valid(host):
		host.grab_focus()


func _hide_modal_exit_window() -> void:
	if _modal_exit_window != null and is_instance_valid(_modal_exit_window) and _modal_exit_window.visible:
		_modal_exit_window.hide()


# Public so TutorialManager's teardown can drop the hatch even if the overlay
# has already stopped processing.
func clear_modal_exit() -> void:
	_hide_modal_exit_window()
	_clear_injected_button()


func _on_exit_pressed() -> void:
	var m := _mgr()
	if m:
		m.request_exit_tutorial()


# ------------------------------------------------------------------- API ----

func show_step(view: Dictionary) -> void:
	visible = true
	set_process(true)
	_bark_label.text = str(view.get("bark", ""))
	_body_text.text = str(view.get("body", ""))
	_checklist_label = str(view.get("checklist_label", ""))
	update_checklist(view.get("checklist", []))
	_hint_label.visible = false
	_hint_label.text = ""
	_progress_label.text = str(view.get("progress", ""))
	_continue_button.visible = bool(view.get("ack", false))
	_next_button.visible = false
	_menu_button.visible = false
	_skip_button.visible = true
	_exit_button.visible = true
	_anchor_spec = view.get("anchor", {})
	_spotlight_mode = str(view.get("spotlight", "none"))
	_anchor_node = null
	_anchor_ok = false
	# A new step has a new allow-list, so an earlier step's rejection says nothing
	# about this one — the in-dialog hatch has to be re-armed by a fresh block.
	_hatch_armed = false
	_reresolve_accum = ANCHOR_RERESOLVE_S  # resolve on next frame
	# Reset to the roomy default, then dodge in the SAME frame — otherwise a
	# step that opens over a dialog flashes a full-width card across it before
	# _process gets its turn.
	_place_card("top")
	_update_card_mode()
	_apply_pad_affordances(true)
	_spotlight.queue_redraw()


func show_hint(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = true


# Repaint the multi-input tick list. `items` is [{id, label (BBCode), done}];
# an empty array hides the row. Ticked entries go green, outstanding ones stay
# dim — the whole point of the row is that the player can see, at a glance,
# which controls they have NOT tried yet.
func update_checklist(items) -> void:
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		_checklist_text.visible = false
		_checklist_text.text = ""
		return
	var parts: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var done: bool = bool(it.get("done", false))
		var color: Color = UIConstantsData.CONFIRMED_GREEN if done else Color(WhiteDwarfThemeData.WH_PARCHMENT, 0.55)
		parts.append("[color=#%s]%s %s[/color]" % [
			color.to_html(false), "[b]✔[/b]" if done else "○", str(it.get("label", ""))])
	var prefix := ""
	if _checklist_label != "":
		prefix = "%s  " % _checklist_label
	_checklist_text.text = prefix + "    ".join(parts)
	_checklist_text.visible = true


func show_summary(view: Dictionary) -> void:
	visible = true
	set_process(true)
	_bark_label.text = str(view.get("bark", "PROPPA JOB!"))
	_body_text.text = str(view.get("body", ""))
	_checklist_label = ""
	update_checklist([])
	_hint_label.visible = false
	_progress_label.text = str(view.get("progress", ""))
	_continue_button.visible = false
	_skip_button.visible = false
	_exit_button.visible = false
	_next_button.visible = bool(view.get("has_next", false))
	_menu_button.visible = true
	_anchor_spec = {}
	_anchor_node = null
	_anchor_ok = false
	_spotlight_mode = "none"
	for strip in _dim_strips:
		strip.visible = false
	_place_card("top")
	_update_card_mode()
	_apply_pad_affordances(true)
	_spotlight.queue_redraw()


func hide_all() -> void:
	visible = false
	set_process(false)
	_anchor_spec = {}
	_anchor_node = null
	_anchor_ok = false
	_spotlight_mode = "none"
	for strip in _dim_strips:
		strip.visible = false
	_ack_glyph.visible = false
	# _process is off from here, so the hatch would otherwise be stranded on
	# screen (and the injected button left in a dialog that outlives the lesson).
	clear_modal_exit()
	# Hand the hint bar back to the board context — the card no longer owns A.
	_refresh_pad_hints()


func shake() -> void:
	if not visible:
		return
	var origin := _card.position
	var tween := create_tween()
	tween.tween_property(_card, "position:x", origin.x + 7.0, 0.05)
	tween.tween_property(_card, "position:x", origin.x - 7.0, 0.08)
	tween.tween_property(_card, "position:x", origin.x, 0.05)


# Exposed for windowed scenarios: what the player currently reads.
func current_body_text() -> String:
	return _body_text.text


func current_progress_text() -> String:
	return _progress_label.text


func current_checklist_text() -> String:
	return _checklist_text.text if _checklist_text.visible else ""


# --------------------------------------------------------------- process ----

func _process(delta: float) -> void:
	_update_card_mode()
	_sync_modal_exit()
	_keep_ack_focus()
	if _anchor_spec.is_empty():
		_anchor_ok = false
		_spotlight.queue_redraw()
		return
	_reresolve_accum += delta
	var node_valid: bool = _anchor_node != null and is_instance_valid(_anchor_node) \
		and (not (_anchor_node is CanvasItem) or (_anchor_node as CanvasItem).is_visible_in_tree())
	if node_valid:
		_anchor_rect = AnchorResolverLib.rect_for_node(_anchor_node, get_tree())
		_anchor_ok = _anchor_rect.size != Vector2.ZERO
	elif _reresolve_accum >= ANCHOR_RERESOLVE_S:
		_reresolve_accum = 0.0
		var res: Dictionary = AnchorResolverLib.resolve(_anchor_spec, get_tree())
		_anchor_ok = res.ok
		_anchor_node = res.node
		if res.ok:
			_anchor_rect = res.rect
			# A spotlighted control can sit below the fold of a scrolling side
			# panel (e.g. the Command panel's Waaagh! button once the objective
			# and VP sections are populated). Scroll it into view on first
			# resolve so the ring lands on something the player can actually
			# see and click.
			_scroll_anchor_into_view(res.node)
	_update_dim_strips()
	_spotlight.queue_redraw()


# A B press (PadRouter._handle_back), a stray cursor click on the board or a
# panel rebuild can all drop focus. While the card is waiting on a press the
# ring must come back on its own, or the player is left with no visible
# selection and no obvious way to make one.
func _keep_ack_focus() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	var idm := get_node_or_null("/root/InputDeviceManager")
	if idm == null or not idm.is_pad_active():
		return
	var target := _pad_ack_button()
	if target != null:
		target.grab_focus()


func _scroll_anchor_into_view(node: Node) -> void:
	if node == null or not (node is Control):
		return
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(node as Control)
			return
		parent = parent.get_parent()


# Card placement priority: dodge open game dialogs (screen gutter), then dodge
# the spotlighted anchor (bottom), else top-center (PRP §4.3).
func _update_card_mode() -> void:
	var dlg := _dialog_bounds()
	if dlg.size.x > 0.0:
		_dodge_dialog(dlg)
		return
	var wanted := "top"
	if _anchor_ok:
		var cr := card_rect()
		if _card_mode != "bottom":
			if cr.grow(8).intersects(_anchor_rect):
				wanted = "bottom"
		else:
			var top_rect := Rect2(cr.position.x, CARD_TOP_OFFSET, cr.size.x, cr.size.y)
			wanted = "top" if not top_rect.grow(8).intersects(_anchor_rect) else "bottom"
	_place_card(wanted)


# Keep the card clear of an open embedded dialog.
#
# Embedded Windows composite above every CanvasLayer, so whatever they cover is
# simply gone — no layer number can win. The old fix parked the card on the
# left flank at its full 588px width and assumed the centered dialog left room
# for it; that only holds while the viewport is at least ~1800px wide. Raise
# the UI Scale slider (or let the pad text boost multiply it) and the logical
# viewport shrinks, the dialog slides left with it, and the card's right-hand
# third — the tail of the instruction plus Skip Step / Exit Tutorial — ends up
# behind the dialog. Reported on T2 step 1 against Declare Battle Formations.
#
# So: measure the gutters, take the roomier one, and shrink the text column to
# what actually fits there. And if the dialog does not reach the default top
# placement at all (bottom-docked gameplay popups), just stay there full width.
func _dodge_dialog(dlg: Rect2) -> void:
	var vp := _spotlight.get_viewport_rect().size
	var full_w: float = CARD_CONTENT_WIDTH + CARD_CHROME_W
	# Whichever height reads larger — the minimum size can lag a frame behind a
	# re-wrap either way, and over-estimating only biases us towards the gutter,
	# which is always safe.
	var card_h: float = maxf(_card.get_combined_minimum_size().y, _card.size.y)
	var top_rect := Rect2(
		Vector2(maxf((vp.x - full_w) * 0.5, 0.0), CARD_TOP_OFFSET),
		Vector2(full_w, card_h))
	if not top_rect.grow(CARD_DIALOG_GAP).intersects(dlg):
		_place_card("top")
		return
	var left_room: float = dlg.position.x
	var right_room: float = vp.x - dlg.end.x
	# The left flank is the default — it sits over the game-log panel rather
	# than the unit list the tutorial keeps pointing at, and a centered dialog
	# splits the gutters near-evenly anyway. Only cross the screen when the
	# right side is clearly roomier, or a one-pixel difference in a re-centered
	# dialog would make the card hop sides mid-step.
	var side: String = "right" if right_room > left_room + CARD_SIDE_SWAP_BIAS else "left"
	# The floating escape hatch parks in the top-right corner and assumes the
	# card is not there. Centred dialogs split the gutters evenly so the bias
	# above already keeps us left, but pin it while the hatch is up rather than
	# rely on that.
	if _modal_exit_window != null and is_instance_valid(_modal_exit_window) and _modal_exit_window.visible:
		side = "left"
	var room: float = right_room if side == "right" else left_room
	var content: float = room - CARD_EDGE_MARGIN - CARD_DIALOG_GAP - CARD_CHROME_W
	var floor_w := _min_content_width()
	if content < floor_w:
		_log_cramped(vp, dlg, content, floor_w)
	_place_card(side, content)


# The clamp above can still leave the card overlapping when the viewport is
# genuinely too narrow for both (e.g. UI Scale 2.0 beside a 600px dialog).
# Say so in the log rather than failing silently — throttled, this runs in
# _process.
func _log_cramped(vp: Vector2, dlg: Rect2, content: float, floor_w: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cramped_log_ms < CRAMPED_LOG_INTERVAL_MS:
		return
	_last_cramped_log_ms = now
	var msg := "[TutorialOverlay] card gutter too narrow: viewport=%s dialog=%s fits %.0fpx of text (floor %.0f) — card may overlap the dialog" % [
		str(vp), str(dlg), content, floor_w]
	print(msg)
	var dl := get_node_or_null("/root/DebugLogger")
	if dl != null:
		dl.warn(msg)


func _update_dim_strips() -> void:
	var strict_on: bool = _spotlight_mode == "strict" and _anchor_ok
	for strip in _dim_strips:
		strip.visible = strict_on
	if not strict_on:
		return
	var vp := _spotlight.get_viewport_rect().size
	var hole := _anchor_rect.grow(10.0)
	# top / bottom / left / right frame around the hole
	_dim_strips[0].position = Vector2.ZERO
	_dim_strips[0].size = Vector2(vp.x, max(hole.position.y, 0.0))
	_dim_strips[1].position = Vector2(0, hole.end.y)
	_dim_strips[1].size = Vector2(vp.x, max(vp.y - hole.end.y, 0.0))
	_dim_strips[2].position = Vector2(0, max(hole.position.y, 0.0))
	_dim_strips[2].size = Vector2(max(hole.position.x, 0.0), hole.size.y)
	_dim_strips[3].position = Vector2(hole.end.x, max(hole.position.y, 0.0))
	_dim_strips[3].size = Vector2(max(vp.x - hole.end.x, 0.0), hole.size.y)


func _draw_spotlight() -> void:
	if not _anchor_ok or _spotlight_mode == "none":
		return
	# Soft ring (TM0 scope; "strict" renders the same ring until the dimmer
	# lands in TM1 — see PRPs/tutorial_system.md §6).
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * TAU / UIConstantsData.MOTION_PULSE_LOOP_S)
	var grow := 6.0 + 5.0 * pulse
	var color: Color = UIConstantsData.MARGINAL_YELLOW
	color.a = 0.45 + 0.4 * pulse
	_spotlight.draw_rect(_anchor_rect.grow(grow), color, false, 3.0)
	var inner: Color = UIConstantsData.MARGINAL_YELLOW
	inner.a = 0.18
	_spotlight.draw_rect(_anchor_rect.grow(2.0), inner, false, 1.5)


func _on_continue_pressed() -> void:
	_continue_button.release_focus()
	var m := _mgr()
	if m:
		m.ack()
