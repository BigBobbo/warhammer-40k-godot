extends SceneTree

# T04 — PhaseBar (six-pill battle-phase tracker) state contract.
#
# 1. The bar builds exactly six pills, named PhasePill_<GameStateData.Phase key>,
#    in turn order Command -> Movement -> Shooting -> Charge -> Fight -> Score.
# 2. For every battle phase: the active pill's modulate is the active player's
#    UIConstants slot colour (P1 TEAL, P2 MAGENTA), earlier pills modulate to
#    Color(0.5, 0.5, 0.5, 1.0), later pills have modulate.a == 0.4.
# 3. Outside the battle round (deployment) no pill is lit.
# 4. The bar is hooked to PhaseManager.phase_changed (connected on entering the
#    tree, disconnected on leaving it) and the handler lights the phase it is
#    passed; refresh() with no argument reads GameState's phase and player.
# 5. Pill styles differ by state (solid glowing chip / solid grey chip / hollow
#    outline) and every pill keeps the same size in every state, so the row
#    never shifts when the phase advances.
#
# Usage: godot --headless --path . -s tests/test_phase_bar.gd

const PhaseBarScript := preload("res://scripts/PhaseBar.gd")

const EXPECTED_NAMES := [
	"PhasePill_COMMAND", "PhasePill_MOVEMENT", "PhasePill_SHOOTING",
	"PhasePill_CHARGE", "PhasePill_FIGHT", "PhasePill_SCORING",
]
const EXPECTED_LABELS := ["Command", "Movement", "Shooting", "Charge", "Fight", "Score"]

var passed := 0
var failed := 0


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init() -> void:
	# Autoloads are added after SceneTree._init — run once they are live.
	call_deferred("_run")


func _run() -> void:
	print("\n=== test_phase_bar ===\n")
	var ui: Node = root.get_node_or_null("UIConstants")
	var pm: Node = root.get_node_or_null("PhaseManager")
	var gs: Node = root.get_node_or_null("GameState")
	_check("UIConstants, PhaseManager and GameState autoloads are live",
		ui != null and pm != null and gs != null)
	if ui == null or pm == null or gs == null:
		_finish()
		return

	var bar: HBoxContainer = PhaseBarScript.new()
	root.add_child(bar)
	await process_frame

	_test_structure(bar)
	_test_states(bar, ui)
	_test_signal_hook(bar, pm, gs, ui)
	_test_styles_and_layout(bar)

	# Hook lifecycle: leaving the tree drops the connection, re-entering
	# restores it (the bar is never left listening while detached).
	var hook := Callable(bar, "_on_phase_changed")
	root.remove_child(bar)
	_check("leaving the tree disconnects the phase_changed hook", not pm.phase_changed.is_connected(hook))
	root.add_child(bar)
	_check("re-entering the tree reconnects it", pm.phase_changed.is_connected(hook))
	bar.queue_free()
	await process_frame
	_finish()


func _phase_order() -> Array:
	return [
		GameStateData.Phase.COMMAND, GameStateData.Phase.MOVEMENT,
		GameStateData.Phase.SHOOTING, GameStateData.Phase.CHARGE,
		GameStateData.Phase.FIGHT, GameStateData.Phase.SCORING,
	]


func _grey_delta(c: Color) -> float:
	var want: Color = PhaseBarScript.COMPLETED_MODULATE
	return maxf(maxf(absf(c.r - want.r), absf(c.g - want.g)), maxf(absf(c.b - want.b), absf(c.a - want.a)))


# ---------------------------------------------------------------------------
# 1. Structure
# ---------------------------------------------------------------------------

func _test_structure(bar: HBoxContainer) -> void:
	print("-- structure --")
	_check("bar is named PhaseBar", String(bar.name) == "PhaseBar", "name=%s" % bar.name)
	var pill_names: Array = []
	for c in bar.get_children():
		if String(c.name).begins_with("PhasePill_"):
			pill_names.append(String(c.name))
	_check("exactly six pills, named and ordered as the battle phases",
		pill_names == EXPECTED_NAMES, "got %s" % str(pill_names))
	var texts: Array = []
	for n in EXPECTED_NAMES:
		var pill = bar.get_node_or_null(n)
		var lbl = pill.get_node_or_null("Label") if pill != null else null
		texts.append(lbl.text if lbl != null else "<missing>")
	_check("pill labels read Command / Movement / Shooting / Charge / Fight / Score",
		texts == EXPECTED_LABELS, "got %s" % str(texts))
	var order := _phase_order()
	var named_ok := true
	for i in range(order.size()):
		if PhaseBarScript.pill_name(order[i]) != EXPECTED_NAMES[i] or bar.get_pill(order[i]) != bar.get_node_or_null(EXPECTED_NAMES[i]):
			named_ok = false
	_check("pill_name()/get_pill() resolve each phase to its pill", named_ok)
	var no_morale: bool = bar.get_pill(GameStateData.Phase.MORALE) == null and bar.pill_state(GameStateData.Phase.MORALE) == ""
	_check("the deprecated MORALE phase has no pill", no_morale)
	var ignores: bool = bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
	for c in bar.get_children():
		if c is Control and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			ignores = false
	_check("bar, pills and arrows ignore the mouse (board clicks pass through)", ignores)


# ---------------------------------------------------------------------------
# 2./3. Active / completed / future for every phase, both players
# ---------------------------------------------------------------------------

func _test_states(bar: HBoxContainer, ui: Node) -> void:
	print("-- states --")
	var order := _phase_order()
	for player in [1, 2]:
		var slot: Color = ui.player_slot_color(player)
		for i in range(order.size()):
			bar.apply_state(order[i], player)
			var bad: Array = []
			for j in range(order.size()):
				var pill: Control = bar.get_pill(order[j])
				var m: Color = pill.modulate
				if j < i:
					if _grey_delta(m) > 0.05 or bar.pill_state(order[j]) != PhaseBarScript.STATE_COMPLETED:
						bad.append("%s completed? %s" % [EXPECTED_NAMES[j], str(m)])
				elif j == i:
					if m != slot or bar.pill_state(order[j]) != PhaseBarScript.STATE_ACTIVE:
						bad.append("%s active? %s want %s" % [EXPECTED_NAMES[j], str(m), str(slot)])
				else:
					if not is_equal_approx(m.a, 0.4) or bar.pill_state(order[j]) != PhaseBarScript.STATE_FUTURE:
						bad.append("%s future? %s" % [EXPECTED_NAMES[j], str(m)])
			_check("P%d in %s: earlier pills grey, this pill the slot colour, later pills a=0.4" % [player, EXPECTED_LABELS[i]],
				bad.is_empty(), "; ".join(bad))
		_check("P%d: active_color() is UIConstants.player_slot_color(%d)" % [player, player],
			bar.active_color() == slot)
	_check("P1 lights TEAL and P2 lights MAGENTA (the slot table, not a fixed colour)",
		ui.player_slot_color(1) == ui.FRIENDLY_PLAYER_TEAL and ui.player_slot_color(2) == ui.ENEMY_PLAYER_MAGENTA
		and ui.FRIENDLY_PLAYER_TEAL != ui.ENEMY_PLAYER_MAGENTA)

	bar.apply_state(GameStateData.Phase.DEPLOYMENT, 1)
	var all_future: bool = bar.active_phase == -1
	for p in order:
		if bar.pill_state(p) != PhaseBarScript.STATE_FUTURE or not is_equal_approx(bar.get_pill(p).modulate.a, 0.4):
			all_future = false
	_check("deployment (outside the battle round) lights no pill", all_future)


# ---------------------------------------------------------------------------
# 4. PhaseManager.phase_changed hook + GameState-driven refresh
# ---------------------------------------------------------------------------

func _test_signal_hook(bar: HBoxContainer, pm: Node, gs: Node, ui: Node) -> void:
	print("-- phase_changed hook --")
	_check("bar is connected to PhaseManager.phase_changed",
		pm.phase_changed.is_connected(bar._on_phase_changed))
	# The handler is what phase_changed calls. (Emitting the real signal here
	# would also wake every autoload listening to it: AI, autosave, replay.)
	bar.apply_state(GameStateData.Phase.COMMAND, 1)
	bar._on_phase_changed(GameStateData.Phase.SHOOTING)
	var player: int = int(gs.get_active_player())
	_check("phase_changed(SHOOTING) lights Shooting in the active player's slot colour",
		bar.active_phase == GameStateData.Phase.SHOOTING
		and bar.get_pill(GameStateData.Phase.SHOOTING).modulate == ui.player_slot_color(player)
		and _grey_delta(bar.get_pill(GameStateData.Phase.MOVEMENT).modulate) <= 0.05
		and is_equal_approx(bar.get_pill(GameStateData.Phase.CHARGE).modulate.a, 0.4),
		"active_phase=%d player=%d" % [bar.active_phase, player])

	var saved_state: Dictionary = gs.state.duplicate(true)
	var meta: Dictionary = gs.state.get("meta", {})
	meta["phase"] = GameStateData.Phase.FIGHT
	meta["active_player"] = 2
	gs.state["meta"] = meta
	bar.refresh()
	_check("refresh() reads GameState: Fight lit in P2 MAGENTA, Charge completed, Score future",
		bar.active_phase == GameStateData.Phase.FIGHT and bar.active_player == 2
		and bar.get_pill(GameStateData.Phase.FIGHT).modulate == ui.ENEMY_PLAYER_MAGENTA
		and bar.pill_state(GameStateData.Phase.CHARGE) == PhaseBarScript.STATE_COMPLETED
		and bar.pill_state(GameStateData.Phase.SCORING) == PhaseBarScript.STATE_FUTURE,
		"active_phase=%d player=%d" % [bar.active_phase, bar.active_player])
	gs.state = saved_state


# ---------------------------------------------------------------------------
# 5. Styles per state + no layout shift
# ---------------------------------------------------------------------------

func _test_styles_and_layout(bar: HBoxContainer) -> void:
	print("-- styles and layout --")
	var order := _phase_order()
	var sizes_by_state: Array = []
	var bar_widths: Array = []
	for i in range(order.size()):
		bar.apply_state(order[i], 1)
		var sizes: Array = []
		for p in order:
			sizes.append(bar.get_pill(p).get_combined_minimum_size())
		sizes_by_state.append(sizes)
		bar_widths.append(bar.get_combined_minimum_size().x)

	var uniform := true
	var first: Vector2 = sizes_by_state[0][0]
	for sizes in sizes_by_state:
		for s in sizes:
			if s != first:
				uniform = false
	_check("all six pills share one size in every phase (no shift on advance)", uniform,
		"sizes=%s" % str(sizes_by_state))
	var widths_same := true
	for w in bar_widths:
		if w != bar_widths[0]:
			widths_same = false
	_check("the bar's own width never changes across phases", widths_same, "widths=%s" % str(bar_widths))
	# (Pixel heights are not checked here: headless font metrics are not the
	# rendered ones — Rajdhani reports 32 px at size 16 headless, 21 px in the
	# window. tests/scenarios/visual/T04_phase_bar.json measures the live row.)
	var widest := 0.0
	var font: Font = PhaseBarScript.PILL_FONT
	for t in EXPECTED_LABELS:
		widest = maxf(widest, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, PhaseBarScript.FONT_SIZE).x)
	_check("every label fits its pill untruncated (pill wider than the widest word)",
		first.x >= widest + 2 * PhaseBarScript.PILL_PADDING_X, "pill=%s widest=%.1f" % [str(first), widest])

	bar.apply_state(GameStateData.Phase.MOVEMENT, 1)
	var active_style: StyleBoxFlat = bar.get_pill(GameStateData.Phase.MOVEMENT).get_theme_stylebox("panel")
	var done_style: StyleBoxFlat = bar.get_pill(GameStateData.Phase.COMMAND).get_theme_stylebox("panel")
	var future_style: StyleBoxFlat = bar.get_pill(GameStateData.Phase.SHOOTING).get_theme_stylebox("panel")
	_check("active pill: solid fill with a glow", active_style.bg_color.a == 1.0 and active_style.shadow_size > 0)
	_check("completed pill: solid fill, no glow, no outline",
		done_style.bg_color.a == 1.0 and done_style.shadow_size == 0 and done_style.border_width_left == 0)
	_check("future pill: hollow outline (no fill)",
		future_style.bg_color.a == 0.0 and future_style.border_width_left == 1)
	_check("each pill owns its style (one pill's state never repaints another)",
		active_style != done_style and done_style != future_style)


func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
