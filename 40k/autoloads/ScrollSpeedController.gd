extends Node
## Global menu / panel scroll-speed limiter.
##
## WHY: Godot's built-in ScrollContainer scrolls by `page / 8 * event.factor`
## per mouse-wheel or trackpad notch (see the engine's
## scene/gui/scroll_container.cpp). On a trackpad — and on a fast mouse wheel —
## that felt far too fast in this game's menus and panels. Godot exposes no
## project setting to slow this globally, so this autoload does it.
##
## HOW: `_input()` runs for every input event BEFORE any Control's `_gui_input()`
## (the viewport dispatches node `_input` first and GUI input second — see
## Viewport::push_input). We look at what the mouse is hovering; if the wheel
## notch is about to be handled by a scrolling surface (ScrollContainer,
## ItemList, Tree, TextEdit, RichTextLabel) we scale down the event's `factor`.
## Because the engine's scroll distance is proportional to `factor`, mutating it
## here uniformly slows every menu — no scene or panel script has to change.
##
## WHAT WE DELIBERATELY DO NOT TOUCH:
##   * SpinBox — it ALSO multiplies its step by `factor`
##     (scene/gui/spin_box.cpp), so scaling the factor would corrupt its value
##     increments. SpinBox derives from Range, which we exclude.
##   * Sliders / ScrollBars / ProgressBars (also Range) — excluded for the same
##     safety reason (sliders ignore `factor` entirely so they'd be unaffected
##     anyway, but excluding all Range keeps the rule simple and safe).
##   * The board camera zoom — it lives in Main._unhandled_input, ignores
##     `factor` outright, and only fires when the cursor is over the board (no
##     scroll surface hovered), so it is never rescaled here.

# Master on/off. Kept settable so tests can A/B stock-vs-reduced speed and a
# future Settings toggle can flip it.
var enabled: bool = true

# Fraction of Godot's default scroll distance to keep. 1.0 == stock engine
# speed; lower == slower. 0.4 => menus scroll at 40% of the previous speed.
# Tunable at runtime (and an easy hook for a future Settings slider).
var menu_scroll_speed: float = 0.4

func _ready() -> void:
	# Make sure _input() is delivered to this autoload.
	set_process_input(true)
	if DebugLogger:
		DebugLogger.info("[ScrollSpeedController] Menu scroll limiter active — %.0f%% of default speed" % (menu_scroll_speed * 100.0))

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if not _is_wheel_button(mb.button_index):
		return
	# Only slow the wheel when a genuine scrolling surface is what will react to
	# it. Everything else (board zoom, SpinBox steps, sliders, empty board) keeps
	# stock behaviour.
	var target := _effective_wheel_target()
	if _is_scroll_surface(target):
		mb.factor *= menu_scroll_speed

func _is_wheel_button(button_index: int) -> bool:
	return button_index == MOUSE_BUTTON_WHEEL_UP \
		or button_index == MOUSE_BUTTON_WHEEL_DOWN \
		or button_index == MOUSE_BUTTON_WHEEL_LEFT \
		or button_index == MOUSE_BUTTON_WHEEL_RIGHT

## The control that will actually consume this wheel notch: walk up from the
## hovered control to the first wheel-handling control. Returns null when the
## cursor is over the board / nothing that scrolls (so board zoom is untouched).
func _effective_wheel_target() -> Control:
	var vp := get_viewport()
	if vp == null:
		return null
	var c: Control = vp.gui_get_hovered_control()
	while c != null:
		if _consumes_wheel(c):
			return c
		var parent := c.get_parent()
		c = parent if parent is Control else null
	return null

## Controls whose own _gui_input reacts to the wheel. The notch stops at the
## first of these walking up from the cursor. Range (SpinBox/Slider/ScrollBar)
## is included so the walk stops there — and we then choose NOT to rescale it.
func _consumes_wheel(c: Control) -> bool:
	return _is_scroll_surface(c) or c is Range

## Scrolling surfaces whose scroll distance is proportional to the wheel factor,
## and are therefore safe (and desirable) to slow down.
func _is_scroll_surface(c: Control) -> bool:
	return c is ScrollContainer or c is ItemList or c is Tree or c is TextEdit or c is RichTextLabel

## Pure helper for tests: what factor would we hand `target` for a wheel notch
## whose raw factor is `raw`? Mirrors the decision in _input without needing a
## live hover / input pipeline.
func debug_scaled_factor(target: Control, raw: float) -> float:
	if enabled and _is_scroll_surface(target):
		return raw * menu_scroll_speed
	return raw
