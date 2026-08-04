class_name ReactiveDecisionUI

## Shared affordances for the REACTIVE DECISION windows that interrupt the
## opponent's turn — Heroic Intervention ("Leap to Defend" / "Into the Fray"),
## Fire Overwatch, Counter-Offensive and Rapid Ingress.
##
## PLAYER REPORT (2026-08-04):
##   "At the end of my opponent's charge phase a popup appeared asking did I
##    want to use a stratagem like Leap to Defend. That popup covers the screen
##    so it is not clear what is going on on the board. When I tried to zoom out
##    the popup went away and the game continued, meaning I could now not select
##    the Strat."
##
## Two distinct defects, both addressed here:
##
##   (a) THE LOCK-OUT. These windows carried a 5-second MA-42 auto-decline
##       countdown. Five seconds is not a decision window, it is a reflex test —
##       and any second spent reaching for the camera burned it, after which the
##       stratagem was silently declined and unreachable. The countdown is gone
##       from the dialogs that use this helper, matching the DEFENDER CONTROL
##       rule StratagemDialog already follows: the window waits for the player,
##       and nothing ever declines on their behalf. A camera gesture therefore
##       cannot cost the player the stratagem.
##
##   (b) THE BLIND DECISION. "Which of my units should counter-charge, and is it
##       worth 1 CP?" is a question about the BOARD — where the chargers ended
##       up, who is now in range — and both the dialog and the MA-42 blocking
##       overlay hid exactly that. add_examine_toggle() adds an obvious toggle
##       that hides the dialog and un-dims the battlefield so the player can pan
##       and zoom freely, with a permanent "Back to the decision" bar to return.
##       Board CLICKS stay blocked the whole time — looking is not acting, so
##       the reactive window can never be answered by poking the battlefield.
##
## Usage from a dialog's _build_ui():
##     ReactiveDecisionUI.add_examine_toggle(self, main_container, "Heroic Intervention")
##     main_container.add_child(ReactiveDecisionUI.window_hint_label())
## and, on every resolution path (use / decline):
##     ReactiveDecisionUI.stop_examining(self)

## Meta keys stashed on the dialog Window so any code path (including the HUD
## "Back to the decision" button, which lives outside the dialog) can find the
## toggle and the current mode without a back-reference.
const META_TOGGLE := "wd_examine_toggle"
const META_EXAMINING := "wd_examining"
const META_LABEL := "wd_examine_label"

## Standing text shown where the auto-decline countdown used to be. The player
## needs to know the window is NOT on a timer — the old countdown trained them
## to panic-click.
static func window_hint_label(text: String = "") -> Label:
	var hint := Label.new()
	hint.name = "WindowHint"
	hint.text = text if text != "" else "This window waits for you — nothing is declined automatically."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	return hint


## Add the "Examine Board" toggle to `container` (normally the dialog's main
## VBox, just above the Use/Decline buttons). `decision_label` names the window
## in the HUD bar the player sees while examining ("Heroic Intervention", ...).
static func add_examine_toggle(dialog: Window, container: Container, decision_label: String) -> CheckButton:
	if dialog == null or container == null:
		return null
	dialog.set_meta(META_LABEL, decision_label)
	dialog.set_meta(META_EXAMINING, false)

	var row := VBoxContainer.new()
	row.name = "ExamineBoard"
	row.add_theme_constant_override("separation", 2)

	var toggle := CheckButton.new()
	toggle.name = "ExamineBoardToggle"
	toggle.text = "🔍  Examine Board"
	toggle.tooltip_text = "Hide this window and look at the battlefield — pan and zoom freely. Nothing is decided while you look; toggle it back off (or press Escape) to return to this decision."
	toggle.add_theme_font_size_override("font_size", 18)
	toggle.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	toggle.toggled.connect(func(pressed: bool) -> void:
		set_examining(dialog, pressed))
	row.add_child(toggle)

	var sub := Label.new()
	sub.name = "ExamineBoardHint"
	sub.text = "Look around the board before you choose — this window comes straight back."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	row.add_child(sub)

	container.add_child(row)
	dialog.set_meta(META_TOGGLE, toggle)

	# Tell Main which dialog its blocking overlay is being held open FOR. Without
	# the auto-decline the overlay's 120s safety timer would otherwise decide the
	# overlay was orphaned and drop the input block under a player who is simply
	# still thinking — handing the board back to the ACTIVE player mid-decision.
	var main = SceneRefs.main()
	if main and main.has_method("set_reactive_decision_dialog"):
		main.set_reactive_decision_dialog(dialog)
	return toggle


## Forward a mouse-wheel notch that landed OUTSIDE `dialog` to the board camera.
## Call from the dialog's `_input`.
##
## Godot routes every mouse event to a focused embedded sub-window, translated
## into the window's own space — the parent viewport's `_unhandled_input` and
## GUI never see it, and `exclusive = false` does not change that (verified in
## the running game, 2026-08-04). So while a reactive window was open the wheel
## was simply dead: the player's "let me zoom out and look" did nothing, and the
## old auto-decline then took the stratagem away while they were trying. Notches
## over the dialog's own rect are left alone so its unit list still scrolls.
## Returns true if the event was consumed as a camera zoom.
static func forward_camera_wheel(dialog: Window, event: InputEvent) -> bool:
	if not is_instance_valid(dialog) or not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return false
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	if Rect2(Vector2.ZERO, Vector2(dialog.size)).has_point(mb.position):
		return false  # the wheel belongs to the dialog's own scrolling content
	var main = SceneRefs.main()
	if main == null or not main.has_method("zoom_camera_notch"):
		return false
	# mb.position is window-local; the embedder anchor is the window's origin
	# plus that offset, so the point under the cursor stays put while zooming.
	main.zoom_camera_notch(mb.button_index == MOUSE_BUTTON_WHEEL_UP,
		Vector2(dialog.position) + mb.position)
	dialog.set_input_as_handled()
	return true


static func is_examining(dialog: Window) -> bool:
	if not is_instance_valid(dialog):
		return false
	return bool(dialog.get_meta(META_EXAMINING, false))


## Enter / leave board-examine mode for `dialog`. Safe to call from either the
## toggle itself or the HUD "Back to the decision" button (the toggle is kept in
## sync without re-firing this handler).
static func set_examining(dialog: Window, on: bool) -> void:
	if not is_instance_valid(dialog):
		return
	if bool(dialog.get_meta(META_EXAMINING, false)) == on:
		return
	dialog.set_meta(META_EXAMINING, on)

	var toggle = dialog.get_meta(META_TOGGLE, null)
	if is_instance_valid(toggle) and toggle is CheckButton and toggle.button_pressed != on:
		# no_signal: the HUD bar's "Back" button drives this path too, and we
		# must not bounce back into set_examining().
		toggle.set_pressed_no_signal(on)

	var main = SceneRefs.main()
	var label := str(dialog.get_meta(META_LABEL, "stratagem"))

	if on:
		print("ReactiveDecisionUI: examining board — %s decision held open" % label)
		# Hide the dialog WINDOW rather than freeing it: an exclusive sub-window
		# swallows every mouse event outside its own rect, so with it up the
		# wheel can never reach the camera no matter what the overlay does.
		dialog.hide()
		if main and main.has_method("begin_board_examine"):
			main.begin_board_examine(label, func() -> void:
				set_examining(dialog, false))
	else:
		print("ReactiveDecisionUI: returning to the %s decision" % label)
		if main and main.has_method("end_board_examine"):
			main.end_board_examine()
		if dialog.is_inside_tree():
			DialogUtils.popup_at_bottom(dialog)


## Leave examine mode and drop the HUD bar. MUST be called on every resolution
## path (use / decline) so a dialog that resolves while the player is looking at
## the board can't strand the "Back to the decision" bar on screen.
static func stop_examining(dialog: Window) -> void:
	if not is_instance_valid(dialog):
		return
	if not bool(dialog.get_meta(META_EXAMINING, false)):
		return
	dialog.set_meta(META_EXAMINING, false)
	var main = SceneRefs.main()
	if main and main.has_method("end_board_examine"):
		main.end_board_examine()
