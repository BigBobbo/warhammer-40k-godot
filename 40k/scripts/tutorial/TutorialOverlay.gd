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

# The two escape-hatch affordances (see "modal escape hatch" below). Both names
# are excluded from _blocking_window() so the tutorial's own windows never read
# as "a game dialog is open".
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
var _card_mode: String = "top"
var _dim_strips: Array = []
var _modal_exit_window: Window = null   # floating hatch, for non-AcceptDialog modals
var _modal_exit_host: Window = null     # the dialog we added an Exit button INTO


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
	# reach embedded-window buttons — so instead the card DODGES to the left
	# flank (over the game-log panel) whenever a game dialog is open; the
	# centered dialogs never cover that strip. Found while validating T2.
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
	_bark_label.add_theme_font_size_override("font_size", 21)
	_bark_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_GOLD)
	_bark_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_bark_label)

	_body_text = RichTextLabel.new()
	_body_text.name = "BodyText"
	_body_text.bbcode_enabled = true
	_body_text.fit_content = true
	_body_text.scroll_active = false
	_body_text.custom_minimum_size = Vector2(560, 0)
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
	_checklist_text.custom_minimum_size = Vector2(560, 0)
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
	_hint_label.custom_minimum_size = Vector2(560, 0)
	_hint_label.add_theme_font_size_override("font_size", 17)
	_hint_label.add_theme_color_override("font_color", UIConstantsData.MARGINAL_YELLOW)
	_hint_label.visible = false
	vbox.add_child(_hint_label)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
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
# "left" (dodging an open game dialog — dialogs are centered, the strip over
# the game-log panel stays clear).
func _place_card(mode: String) -> void:
	_card_mode = mode
	match mode:
		"bottom":
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
			_card.offset_bottom = -CARD_BOTTOM_OFFSET
			_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		"left":
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
			_card.offset_left = 10
			_card.grow_vertical = Control.GROW_DIRECTION_BOTH
			_card.grow_horizontal = Control.GROW_DIRECTION_END
		_:
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
			_card.offset_top = CARD_TOP_OFFSET
			_card.grow_vertical = Control.GROW_DIRECTION_END
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH


func card_rect() -> Rect2:
	return _card.get_global_rect()


# True while any embedded game Window (AcceptDialog family) is showing —
# those composite above every CanvasLayer, so the card must dodge them.
func _any_game_window_open() -> bool:
	return _blocking_window() != null


# The topmost visible gameplay Window, or null. The tutorial's OWN windows (the
# escape hatch, the exit confirm) are skipped: they must not make the card dodge
# to the left flank, and must not switch the pad's A away from the card.
func _blocking_window() -> Window:
	var top: Window = null
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
			top = child as Window
	return top


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
func _sync_modal_exit() -> void:
	var host := _blocking_window()
	# The card's own footer buttons cannot be pressed while a modal is up, so say
	# so: a live-looking Exit Tutorial that swallows every click is what made the
	# reported softlock feel unescapable. Greyed here, re-offered below.
	_set_footer_enabled(host == null)
	if host == null:
		clear_modal_exit()
		return
	if host is AcceptDialog:
		_hide_modal_exit_window()
		if _modal_exit_host != host or not _injected_button_alive():
			_clear_injected_button()
			_inject_exit_button(host as AcceptDialog)
		return
	_clear_injected_button()
	_show_modal_exit_window(host)


func _set_footer_enabled(enabled: bool) -> void:
	var blocked_tip := "A dialog is open — use its own Exit Tutorial button."
	for b in [_skip_button, _exit_button]:
		if b == null or b.disabled == (not enabled):
			continue
		b.disabled = not enabled
		if b == _exit_button:
			b.tooltip_text = "Leave the tutorial and go back to the main menu (asks first)." if enabled else blocked_tip


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
	print("TutorialOverlay: added Exit Tutorial to modal '%s'" % str(dialog.name))


func _clear_injected_button() -> void:
	if _modal_exit_host != null and is_instance_valid(_modal_exit_host):
		if _modal_exit_host.has_meta(INJECTED_EXIT_META):
			var btn = _modal_exit_host.get_meta(INJECTED_EXIT_META)
			if is_instance_valid(btn):
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
	# Top-right, below the HUD bar: clear of the card (which has dodged to the
	# left flank) and of the centred dialogs the hatch exists to escape.
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
	_reresolve_accum = ANCHOR_RERESOLVE_S  # resolve on next frame
	if _card_mode != "top":
		_place_card("top")
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


# Card placement priority: dodge open game dialogs (left flank), then dodge
# the spotlighted anchor (bottom), else top-center (PRP §4.3).
func _update_card_mode() -> void:
	var wanted := "top"
	if _any_game_window_open():
		wanted = "left"
	elif _anchor_ok:
		var cr := card_rect()
		if _card_mode != "bottom":
			if cr.grow(8).intersects(_anchor_rect):
				wanted = "bottom"
		else:
			var top_rect := Rect2(cr.position.x, CARD_TOP_OFFSET, cr.size.x, cr.size.y)
			wanted = "top" if not top_rect.grow(8).intersects(_anchor_rect) else "bottom"
	if wanted != _card_mode:
		_place_card(wanted)


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
