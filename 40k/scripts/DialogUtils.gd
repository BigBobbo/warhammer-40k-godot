class_name DialogUtils

## Shared helpers for showing dialogs safely.

## Human-readable label for a unit in a picker/list: the display name (which
## carries the Alpha/Beta suffix for duplicate squads) plus the model count, so
## two same-named squads (e.g. two "Boyz") are distinguishable — matching the
## roster panel's "Name (N models)" convention. Model count uses total models
## (units.models.size()), the same as the roster, so the numbers line up.
static func unit_label(unit: Dictionary) -> String:
	var meta = unit.get("meta", {})
	var name = str(meta.get("display_name", meta.get("name", "Unit")))
	return "%s (%d models)" % [name, unit.get("models", []).size()]

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


## Show `dialog` anchored to the BOTTOM-CENTER of the screen instead of the
## middle. This is the CANONICAL way to show an in-battle popup: gameplay
## decisions (rerolls, overwatch, coherency removal, weapon order, ...) must
## stay OUT of the way of the battlefield, hugging the bottom edge like a
## docked control bar — the same slot as the armour-save allocation bar —
## rather than sitting on top of the action. Centered popups are reserved for
## menu/meta contexts (main menu, save manager, game over, disconnects).
##
## `base_size` defaults to Vector2.ZERO which means "derive from the dialog's
## own min_size (at least the SMALL tier)" so call sites don't restate a size
## the dialog already declares. Clamped to the viewport, then re-anchored one
## frame later (once the content has settled its real height) so the window
## keeps hugging the bottom no matter how its content measures. It also stays
## pinned: if the dialog later grows (staged flows swapping content), it is
## re-anchored so it grows UP from the bottom edge instead of spilling
## off-screen. `margin_bottom` is the gap left below the window — the default
## keeps the phase-breadcrumb strip visible, matching the allocation bar.
static func popup_at_bottom(dialog: Window, base_size: Vector2 = Vector2.ZERO, margin_bottom: int = DialogConstants.BOTTOM_CLEARANCE) -> void:
	if dialog == null:
		return
	if base_size == Vector2.ZERO:
		base_size = Vector2(
			max(float(dialog.min_size.x), DialogConstants.SMALL.x),
			max(float(dialog.min_size.y), DialogConstants.SMALL.y))
	# Mark the window so the shared overflow guard re-pins it to the bottom
	# instead of re-centering it (see _cap_if_overflowing).
	dialog.set_meta("wd_bottom_anchored", true)
	dialog.set_meta("wd_bottom_margin", margin_bottom)
	if not dialog.is_inside_tree():
		# Can't resolve the screen size before the dialog is in the tree; fall
		# back to a plain popup rather than doing nothing.
		dialog.popup(Rect2i(Vector2i.ZERO, Vector2i(int(base_size.x), int(base_size.y))))
		return
	var vp_size: Vector2 = _screen_size(dialog)
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	# Hard ceiling so the window can never exceed the viewport.
	dialog.max_size = Vector2i(max_w, max_h)
	var w: int = min(int(base_size.x), max_w)
	var h: int = min(int(base_size.y), max_h)
	dialog.popup(Rect2i(_bottom_position(vp_size, w, h, margin_bottom), Vector2i(w, h)))
	# Keep the window pinned to the bottom if its content later resizes it
	# (e.g. staged dialogs swapping panels while open). Repositions only —
	# never resizes — so it cannot feed back into size_changed.
	if not dialog.size_changed.is_connected(DialogUtils._repin_bottom_on_resize.bind(dialog)):
		dialog.size_changed.connect(DialogUtils._repin_bottom_on_resize.bind(dialog))
	# Re-anchor once the content has been laid out to its real height.
	var t := dialog.get_tree()
	if t != null:
		t.process_frame.connect(DialogUtils._reanchor_bottom.bind(dialog, margin_bottom), CONNECT_ONE_SHOT)


static func _repin_bottom_on_resize(dialog: Window) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or not dialog.is_inside_tree():
		return
	var margin: int = int(dialog.get_meta("wd_bottom_margin", DialogConstants.BOTTOM_CLEARANCE))
	dialog.position = _bottom_position(_screen_size(dialog), int(dialog.size.x), int(dialog.size.y), margin)


static func _reanchor_bottom(dialog: Window, margin_bottom: int) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or not dialog.is_inside_tree():
		return
	var vp_size: Vector2 = _screen_size(dialog)
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	# Snap to the real content size, clamp to the viewport, then re-pin to the
	# bottom edge so it never spills off-screen and never drifts to the middle.
	dialog.reset_size()
	# Bottom popups should read as a slim command bar, not a half-screen panel
	# with dead space: dialogs that declared a tall min_size (e.g. the MEDIUM
	# tier) but whose content is shorter shrink to their real content height.
	# Dialogs with an internal ScrollContainer keep their declared height —
	# their content min is meaningless (the scroll collapses), so shrinking
	# would crush the scroll area into unusability.
	if int(dialog.min_size.y) > 0 and not _has_scroll_container(dialog):
		dialog.min_size = Vector2i(int(dialog.min_size.x), 0)
		dialog.reset_size()
	var w: int = min(int(dialog.size.x), max_w)
	var h: int = min(int(dialog.size.y), max_h)
	dialog.size = Vector2i(w, h)
	dialog.position = _bottom_position(vp_size, w, h, margin_bottom)


static func _has_scroll_container(n: Node) -> bool:
	if n is ScrollContainer:
		return true
	for c in n.get_children():
		if _has_scroll_container(c):
			return true
	return false


static func _bottom_position(vp_size: Vector2, w: int, h: int, margin_bottom: int) -> Vector2i:
	var x: int = int((vp_size.x - w) / 2.0)
	var y: int = int(vp_size.y - h - margin_bottom)
	return Vector2i(max(x, 0), max(y, 0))


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
	# Bottom-anchored gameplay dialogs must stay pinned to the bottom edge —
	# re-clamping them via popup_centered would drag them back over the board.
	if dialog.get_meta("wd_bottom_anchored", false):
		_reanchor_bottom(dialog, int(dialog.get_meta("wd_bottom_margin", DialogConstants.BOTTOM_CLEARANCE)))
		return
	var max_w: int = int(vp_size.x * 0.95)
	var max_h: int = int(vp_size.y * 0.9)
	dialog.max_size = Vector2i(max_w, max_h)
	dialog.reset_size()
	var w: int = min(int(dialog.size.x), max_w)
	var h: int = min(int(dialog.size.y), max_h)
	dialog.popup_centered(Vector2i(w, h))
