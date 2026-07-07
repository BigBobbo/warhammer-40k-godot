class_name DialogUtils

## Shared helpers for showing dialogs safely.

## Show `dialog` centered, clamped so it can never exceed the viewport, then
## snugly re-fit to its real content on the next frame.
##
## This fixes a recurring layout bug: an autowrap `Label` placed directly in a
## dialog's content reports a towering *minimum height* during the initial
## `popup_centered()` — before it has been laid out to a width it wraps to
## roughly one character per line. `AcceptDialog` then sizes its window to
## thousands of pixels tall and never shrinks it, scrolling the confirm/cancel
## buttons off the bottom of the screen where the player can't reach them.
##
## Fix in two steps:
##   1. `max_size` hard-caps the window to the viewport up front, so it can
##      never open off-screen no matter how tall the transient minimum is.
##   2. One frame later — once the content has been laid out to the capped width
##      and the autowrap Labels have re-wrapped to their real height — the window
##      is re-measured to its genuine content size, re-clamped to the viewport,
##      and re-centered. Dialogs with an inner ScrollContainer keep their scroll;
##      short dialogs shrink to fit their content.
##
## `base_size` is the dialog's intended size (defaults to the MEDIUM tier);
## `desired_height` optionally requests a taller initial height (still capped to
## 90% of the viewport).
static func popup_centered_capped(dialog: Window, base_size: Vector2 = DialogConstants.MEDIUM, desired_height: float = -1.0) -> void:
	if dialog == null:
		return
	if not dialog.is_inside_tree():
		# Can't resolve the screen size before the dialog is in the tree; fall
		# back to a plain centered popup rather than doing nothing.
		dialog.popup_centered(Vector2i(int(base_size.x), int(base_size.y)))
		return
	var vp_size: Vector2 = _screen_size(dialog)
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	# Hard ceiling so the window can never exceed the viewport.
	dialog.max_size = Vector2i(max_w, max_h)
	var want_h: float = desired_height if desired_height > 0.0 else base_size.y
	dialog.popup_centered(Vector2i(
		int(min(base_size.x, float(max_w))),
		int(min(want_h, float(max_h)))))
	# Re-fit once the content has been laid out (autowrap Labels have wrapped).
	var t := dialog.get_tree()
	if t != null:
		t.process_frame.connect(DialogUtils._refit_to_viewport.bind(dialog), CONNECT_ONE_SHOT)


static func _refit_to_viewport(dialog: Window) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or not dialog.is_inside_tree():
		return
	var vp_size: Vector2 = _screen_size(dialog)
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	# Snap to the real content size (Labels have wrapped by now), clamp to the
	# viewport, then re-center via popup_centered so it can't spill off-screen.
	dialog.reset_size()
	var w: int = min(int(dialog.size.x), max_w)
	var h: int = min(int(dialog.size.y), max_h)
	dialog.popup_centered(Vector2i(w, h))


## The size of the screen/root viewport the `dialog` popup is embedded in.
## NOTE: a Window is itself a Viewport, so `dialog.get_viewport()` returns the
## dialog, not the screen — use the SceneTree root viewport instead.
static func _screen_size(dialog: Window) -> Vector2:
	var t := dialog.get_tree()
	if t != null and t.root != null:
		return t.root.get_visible_rect().size
	return DialogConstants.LARGE


## Arm a safety net on `dialog`: whenever it becomes visible, if it has opened
## larger than the viewport (e.g. a tall autowrap Label ballooned its minimum
## height and pushed the action buttons off-screen), clamp it back on-screen.
## Only fires on ACTUAL overflow, so correctly-sized dialogs are never touched.
## Wired into WhiteDwarfTheme.apply_to_dialog() so every themed dialog is covered
## without each having to opt in.
static func arm_overflow_guard(dialog: Window) -> void:
	if dialog == null:
		return
	if not dialog.visibility_changed.is_connected(DialogUtils._on_guarded_visibility.bind(dialog)):
		dialog.visibility_changed.connect(DialogUtils._on_guarded_visibility.bind(dialog))


static func _on_guarded_visibility(dialog: Window) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or not dialog.is_inside_tree():
		return
	# Defer so the content has been laid out (autowrap Labels have wrapped) before
	# we decide whether the window overflows.
	var t := dialog.get_tree()
	if t != null:
		t.process_frame.connect(DialogUtils._cap_if_overflowing.bind(dialog), CONNECT_ONE_SHOT)


static func _cap_if_overflowing(dialog: Window) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or not dialog.is_inside_tree():
		return
	var vp_size: Vector2 = _screen_size(dialog)
	var overflows: bool = (
		dialog.size.x > vp_size.x or dialog.size.y > vp_size.y
		or dialog.position.x < 0 or dialog.position.y < 0
		or dialog.position.x + dialog.size.x > vp_size.x
		or dialog.position.y + dialog.size.y > vp_size.y)
	if not overflows:
		return  # fits on-screen — leave well-sized dialogs alone
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	dialog.max_size = Vector2i(max_w, max_h)
	dialog.reset_size()
	var w: int = min(int(dialog.size.x), max_w)
	var h: int = min(int(dialog.size.y), max_h)
	dialog.popup_centered(Vector2i(w, h))
