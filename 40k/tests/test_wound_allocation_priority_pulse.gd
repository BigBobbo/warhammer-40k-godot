extends SceneTree

# T5-V7: Priority-model pulse highlight on WoundAllocationOverlay (added 2026-05-05).
#
# 10e wound allocation rules force the defender to keep wounding any
# already-wounded ("priority") model until it dies. T5-V6 visualised that
# constraint with red highlights + a sine-wave _process() pulse on
# WoundAllocationBoardHighlights. T5-V7 adds a *Tween-driven* scale pulse
# bound to the specific priority model's highlight, owned by the overlay
# itself so its lifetime is bounded by the allocation state — created when
# allocation begins, killed when it ends.
#
# This test pins:
#
#   1. get_priority_model_id() returns the first wounded body model when
#      no character is involved (the typical case).
#   2. get_priority_model_id() returns "" when the unit is at full health
#      — the overlay should NOT pulse anything in that state.
#   3. _start_priority_pulse(model_id) creates a live Tween bound to the
#      highlight sprite registered in board_highlighter.active_highlights.
#   4. _stop_priority_pulse() kills the tween (is_valid() → false) and
#      clears the priority_pulse_target reference so allocation cleanup
#      doesn't leave a dangling reference behind.
#   5. _start_priority_pulse("") with no priority is a no-op — does NOT
#      create a tween (otherwise we'd burn cycles pulsing nothing).
#   6. _start_priority_pulse() called twice for the same model_id reuses
#      the existing tween rather than restarting it (prevents stutter on
#      every _highlight_valid_models() pass).
#   7. _start_priority_pulse() with a fresh model_id when one is already
#      pulsing kills the old tween and starts a new one bound to the new
#      sprite (priority shifted mid-allocation, e.g. wounded model died
#      and the next wound rolls over to a different model).
#   8. _stop_priority_pulse() restores the highlight's resting scale so a
#      kill mid-tick doesn't leave the sprite frozen at the puffed-up
#      keyframe.
#
# Tests work entirely on the overlay's public surface — we hand it a
# minimal `target_unit` Dictionary and a stand-in `board_highlighter` with
# a hand-rolled active_highlights map, so we don't need GameState, the
# real WoundAllocationBoardHighlights node, or a BoardView.
#
# Usage: godot --headless --path . -s tests/test_wound_allocation_priority_pulse.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_wound_allocation_priority_pulse ===\n")

	_test_priority_model_id_picks_first_wounded()
	_test_priority_model_id_empty_when_unit_full_hp()
	_test_start_pulse_creates_live_tween()
	_test_stop_pulse_kills_tween()
	_test_start_pulse_with_empty_id_is_noop()
	_test_start_pulse_same_model_reuses_tween()
	_test_start_pulse_different_model_replaces_tween()
	_test_stop_pulse_restores_resting_scale()

	_finish()

func _finish() -> void:
	print("\n--- Result: %d passed, %d failed ---" % [passed, failed])
	if failed > 0:
		quit(1)
	else:
		quit(0)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a fresh overlay (NOT added to tree — _ready() touches paths the
# headless context can't resolve) plus a real WoundAllocationBoardHighlights
# instance with hand-rolled active_highlights entries. We use the real
# class because the overlay's `board_highlighter` field is strongly typed.
func _make_overlay_with_highlights(model_ids: Array) -> Dictionary:
	var OverlayScript = load("res://scripts/WoundAllocationOverlay.gd")
	var overlay: Control = OverlayScript.new()

	var HighlighterScript = load("res://scripts/WoundAllocationBoardHighlights.gd")
	var highlighter = HighlighterScript.new()
	root.add_child(highlighter)
	overlay.board_highlighter = highlighter

	var highlights_by_id := {}
	for model_id in model_ids:
		var h = Sprite2D.new()
		h.name = "Highlight_" + model_id
		h.scale = Vector2(2.0, 2.0)  # arbitrary non-1 base scale
		highlighter.add_child(h)
		highlighter.active_highlights[model_id] = h
		highlights_by_id[model_id] = h

	return {"overlay": overlay, "highlighter": highlighter, "highlights": highlights_by_id}

func _teardown(ctx: Dictionary) -> void:
	if ctx.has("overlay") and ctx["overlay"] != null:
		ctx["overlay"].free()
	if ctx.has("highlighter") and ctx["highlighter"] != null and is_instance_valid(ctx["highlighter"]):
		ctx["highlighter"].queue_free()

# ---------------------------------------------------------------------------
# 1. get_priority_model_id() picks the first wounded body model.
# ---------------------------------------------------------------------------
func _test_priority_model_id_picks_first_wounded() -> void:
	print("\n-- get_priority_model_id() returns first wounded model id --")
	var ctx = _make_overlay_with_highlights([])
	var overlay = ctx["overlay"]
	overlay.target_unit = {
		"models": [
			{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2},
			{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 1},  # wounded
			{"id": "m2", "alive": true, "wounds": 2, "current_wounds": 2},
		]
	}
	var pri = overlay.get_priority_model_id()
	_check("priority is m1", pri == "m1", "got '%s'" % pri)
	_teardown(ctx)

# ---------------------------------------------------------------------------
# 2. get_priority_model_id() is "" when nothing is wounded.
# ---------------------------------------------------------------------------
func _test_priority_model_id_empty_when_unit_full_hp() -> void:
	print("\n-- get_priority_model_id() returns '' when no model is wounded --")
	var ctx = _make_overlay_with_highlights([])
	var overlay = ctx["overlay"]
	overlay.target_unit = {
		"models": [
			{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2},
			{"id": "m1", "alive": true, "wounds": 2, "current_wounds": 2},
		]
	}
	var pri = overlay.get_priority_model_id()
	_check("priority is empty string", pri == "", "got '%s'" % pri)
	_teardown(ctx)

# ---------------------------------------------------------------------------
# 3. _start_priority_pulse() creates a live tween bound to the sprite.
# ---------------------------------------------------------------------------
func _test_start_pulse_creates_live_tween() -> void:
	print("\n-- _start_priority_pulse() creates a live Tween on the highlight --")
	var ctx = _make_overlay_with_highlights(["m1"])
	var overlay = ctx["overlay"]

	overlay._start_priority_pulse("m1")
	_check("priority_pulse_tween is non-null after start",
		overlay.priority_pulse_tween != null,
		"tween was null after _start_priority_pulse")
	_check("priority_pulse_tween.is_valid() is true after start",
		overlay.priority_pulse_tween != null and overlay.priority_pulse_tween.is_valid(),
		"tween was not valid after _start_priority_pulse")
	_check("priority_pulse_target points at the highlight sprite",
		overlay.priority_pulse_target == ctx["highlights"]["m1"],
		"target was %s" % overlay.priority_pulse_target)
	_check("priority_pulse_model_id is m1",
		overlay.priority_pulse_model_id == "m1",
		"got '%s'" % overlay.priority_pulse_model_id)
	_check("highlight sprite stored its base_scale meta",
		ctx["highlights"]["m1"].has_meta("priority_base_scale"),
		"meta was missing — _stop_priority_pulse() will not restore scale")

	overlay._stop_priority_pulse()
	_teardown(ctx)

# ---------------------------------------------------------------------------
# 4. _stop_priority_pulse() kills the tween and clears state.
# ---------------------------------------------------------------------------
func _test_stop_pulse_kills_tween() -> void:
	print("\n-- _stop_priority_pulse() kills the tween and clears state --")
	var ctx = _make_overlay_with_highlights(["m1"])
	var overlay = ctx["overlay"]

	overlay._start_priority_pulse("m1")
	var tween_ref = overlay.priority_pulse_tween
	_check("precondition: tween is live before stop",
		tween_ref != null and tween_ref.is_valid())

	overlay._stop_priority_pulse()
	_check("priority_pulse_tween is null after stop",
		overlay.priority_pulse_tween == null,
		"tween reference was not cleared")
	_check("captured tween reference is no longer valid",
		tween_ref == null or not tween_ref.is_valid(),
		"the tween we created is still running after _stop_priority_pulse")
	_check("priority_pulse_target is null after stop",
		overlay.priority_pulse_target == null,
		"target was %s" % overlay.priority_pulse_target)
	_check("priority_pulse_model_id is '' after stop",
		overlay.priority_pulse_model_id == "",
		"got '%s'" % overlay.priority_pulse_model_id)

	_teardown(ctx)

# ---------------------------------------------------------------------------
# 5. _start_priority_pulse("") is a no-op — must NOT create a tween.
# ---------------------------------------------------------------------------
func _test_start_pulse_with_empty_id_is_noop() -> void:
	print("\n-- _start_priority_pulse('') does not create a tween --")
	var ctx = _make_overlay_with_highlights(["m1"])
	var overlay = ctx["overlay"]

	overlay._start_priority_pulse("")
	_check("priority_pulse_tween stays null when no priority",
		overlay.priority_pulse_tween == null,
		"a tween was created for an empty model_id")
	_check("priority_pulse_model_id stays '' when no priority",
		overlay.priority_pulse_model_id == "",
		"got '%s'" % overlay.priority_pulse_model_id)

	_teardown(ctx)

# ---------------------------------------------------------------------------
# 6. _start_priority_pulse() called twice for the same model reuses the tween.
# ---------------------------------------------------------------------------
func _test_start_pulse_same_model_reuses_tween() -> void:
	print("\n-- repeat _start_priority_pulse(same id) reuses the existing tween --")
	var ctx = _make_overlay_with_highlights(["m1"])
	var overlay = ctx["overlay"]

	overlay._start_priority_pulse("m1")
	var first = overlay.priority_pulse_tween
	overlay._start_priority_pulse("m1")
	var second = overlay.priority_pulse_tween
	_check("repeated call kept the same Tween instance",
		first == second and first != null,
		"first=%s second=%s — restarting pulses every frame would stutter" % [first, second])

	overlay._stop_priority_pulse()
	_teardown(ctx)

# ---------------------------------------------------------------------------
# 7. _start_priority_pulse() with a different id swaps the tween.
# ---------------------------------------------------------------------------
func _test_start_pulse_different_model_replaces_tween() -> void:
	print("\n-- _start_priority_pulse(new id) replaces the previous tween --")
	var ctx = _make_overlay_with_highlights(["m1", "m2"])
	var overlay = ctx["overlay"]

	overlay._start_priority_pulse("m1")
	var first = overlay.priority_pulse_tween
	_check("precondition: m1 tween is live", first != null and first.is_valid())

	overlay._start_priority_pulse("m2")
	var second = overlay.priority_pulse_tween
	_check("model_id switched to m2",
		overlay.priority_pulse_model_id == "m2",
		"got '%s'" % overlay.priority_pulse_model_id)
	_check("new tween is a different instance",
		first != second,
		"_start_priority_pulse re-used the old tween across model switch")
	_check("old tween was killed when priority shifted",
		first == null or not first.is_valid(),
		"old m1 tween is still live after switching priority to m2")
	_check("target switched to m2's highlight",
		overlay.priority_pulse_target == ctx["highlights"]["m2"])

	overlay._stop_priority_pulse()
	_teardown(ctx)

# ---------------------------------------------------------------------------
# 8. _stop_priority_pulse() restores the highlight's resting scale.
# ---------------------------------------------------------------------------
func _test_stop_pulse_restores_resting_scale() -> void:
	print("\n-- _stop_priority_pulse() restores the highlight's resting scale --")
	var ctx = _make_overlay_with_highlights(["m1"])
	var overlay = ctx["overlay"]
	var highlight = ctx["highlights"]["m1"]
	var resting_scale = highlight.scale

	overlay._start_priority_pulse("m1")
	# Mutate the sprite's scale to simulate the tween being killed mid-tick
	# at the puffed-up keyframe.
	highlight.scale = resting_scale * 1.18

	overlay._stop_priority_pulse()
	_check("highlight.scale restored to resting value",
		highlight.scale == resting_scale,
		"got %s, expected %s" % [highlight.scale, resting_scale])
	_check("priority_base_scale meta cleared",
		not highlight.has_meta("priority_base_scale"),
		"stale meta would prevent re-arming on the next pulse")

	_teardown(ctx)
