extends CanvasLayer

# PM-9 — the Battle Simulator overlay.
#
# An AUTOLOAD CanvasLayer, not a menu-scene Control: PlanSimulator changes
# scene into Main.tscn for every game, which would free anything owned by the
# menu scene. As a consequence the games play VISIBLY underneath this overlay,
# which is a feature — you can watch the run happen.
#
# Wall-time is the thing to be honest about. The bench baselines are ~2.5
# min/game for Custodes and ~8 min for Orks, and PM-8b measured a 3-unit list
# at ~15-26 s. Rather than guess, the ETA is left blank until the first game
# finishes and is then driven by the MEASURED seconds per game.
#
# Stable node names for windowed scenarios:
#   SimRoot / SimConfigPanel / SimResultsPanel
#   SimArmy1 SimArmy2 SimPlan1 SimPlan2 SimZone SimLayout SimGames SimDifficulty
#   SimRunButton SimCancelButton SimCloseButton SimExportButton
#   SimProgressLabel SimEtaLabel SimSummaryLabel SimResultsTree SimReplayLabel

const PlanManagerScript = preload("res://scripts/PlanManager.gd")
const PlanValidatorScript = preload("res://scripts/PlanValidator.gd")

const MAX_GAMES: int = 20
const LARGE_RUN_WARNING_GAMES: int = 8

var root_panel: PanelContainer = null
var config_panel: VBoxContainer = null
var results_panel: VBoxContainer = null

var army1_picker: OptionButton = null
var army2_picker: OptionButton = null
var plan1_picker: OptionButton = null
var plan2_picker: OptionButton = null
var zone_picker: OptionButton = null
var layout_picker: OptionButton = null
var games_spin: SpinBox = null
var difficulty_picker: OptionButton = null

var run_button: Button = null
var cancel_button: Button = null
var close_button: Button = null
var export_button: Button = null

var progress_label: Label = null
var eta_label: Label = null
var summary_label: RichTextLabel = null
var results_tree: Tree = null
var replay_label: RichTextLabel = null

var _army_ids: Array = []
var _plan1_values: Array = []
var _plan2_values: Array = []
var _zone_ids: Array = []
var _layout_ids: Array = []
var _rows: Array = []
var _poll_timer: Timer = null
var _built: bool = false


func _ready() -> void:
	layer = 128            # above the game scene and its own CanvasLayers
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


# ============================================================
# Open / close
# ============================================================

func open() -> void:
	if not _built:
		_build()
	_refresh_sources()
	visible = true
	_set_running_ui(PlanSimulator.is_running())


func close() -> void:
	"""Close the overlay, and get back to the menu if a run left us in a game.

	Every simulated game changes scene into Main.tscn, so after a run the scene
	underneath the overlay is a finished battle, not the menu. Closing without
	this would drop the player into that dead game."""
	visible = false
	_return_to_menu_if_needed()


func _return_to_menu_if_needed() -> void:
	var scene := get_tree().current_scene
	if scene == null or str(scene.name) == "MainMenu":
		return
	# The same teardown Main._on_main_menu_requested does, from out here.
	var ai = get_tree().root.get_node_or_null("AIPlayer")
	if ai != null:
		ai.enabled = false
		ai.ai_players = {1: false, 2: false}
	var replay = get_tree().root.get_node_or_null("ReplayManager")
	if replay != null and replay.has_method("stop_recording"):
		replay.stop_recording()
	var phase_manager = get_tree().root.get_node_or_null("PhaseManager")
	if phase_manager != null:
		phase_manager.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func is_open() -> bool:
	return visible


func _build() -> void:
	_built = true

	var dim := ColorRect.new()
	dim.name = "SimDim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	root_panel = PanelContainer.new()
	root_panel.name = "SimRoot"
	root_panel.anchor_left = 0.5
	root_panel.anchor_right = 0.5
	root_panel.anchor_top = 0.5
	root_panel.anchor_bottom = 0.5
	root_panel.offset_left = -520.0
	root_panel.offset_right = 520.0
	root_panel.offset_top = -380.0
	root_panel.offset_bottom = 380.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	style.border_color = Color(1.0, 0.84, 0.35, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	root_panel.add_theme_stylebox_override("panel", style)
	add_child(root_panel)

	var column := VBoxContainer.new()
	column.name = "SimColumn"
	column.add_theme_constant_override("separation", 10)
	root_panel.add_child(column)

	var title := Label.new()
	title.name = "SimTitle"
	title.text = "BATTLE SIMULATOR — run the same battle again and again"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	column.add_child(title)

	_build_config(column)
	_build_progress(column)
	_build_results(column)
	_build_actions(column)

	_poll_timer = Timer.new()
	_poll_timer.name = "SimPollTimer"
	_poll_timer.wait_time = 0.5
	_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)

	PlanSimulator.run_started.connect(_on_run_started)
	PlanSimulator.game_finished.connect(_on_game_finished)
	PlanSimulator.run_finished.connect(_on_run_finished)
	PlanSimulator.run_cancelled.connect(_on_run_cancelled)


func _build_config(parent: Node) -> void:
	config_panel = VBoxContainer.new()
	config_panel.name = "SimConfigPanel"
	config_panel.add_theme_constant_override("separation", 6)
	parent.add_child(config_panel)

	var grid := GridContainer.new()
	grid.name = "SimConfigGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	config_panel.add_child(grid)

	army1_picker = _add_picker(grid, "Player 1 army", "SimArmy1")
	army2_picker = _add_picker(grid, "Player 2 army", "SimArmy2")
	plan1_picker = _add_picker(grid, "Player 1 plan", "SimPlan1")
	plan2_picker = _add_picker(grid, "Player 2 plan", "SimPlan2")
	zone_picker = _add_picker(grid, "Deployment", "SimZone")
	layout_picker = _add_picker(grid, "Terrain", "SimLayout")
	difficulty_picker = _add_picker(grid, "AI difficulty", "SimDifficulty")
	for name in ["Easy", "Normal", "Hard", "Competitive"]:
		difficulty_picker.add_item(name)
	difficulty_picker.selected = 1

	var games_label := Label.new()
	games_label.text = "Games"
	games_label.custom_minimum_size = Vector2(120, 0)
	grid.add_child(games_label)
	games_spin = SpinBox.new()
	games_spin.name = "SimGames"
	games_spin.min_value = 1
	games_spin.max_value = MAX_GAMES
	games_spin.value = 5
	games_spin.custom_minimum_size = Vector2(300, 0)
	games_spin.value_changed.connect(func(_v): _refresh_estimate())
	grid.add_child(games_spin)

	# Both plan pickers depend on their seat's army.
	army1_picker.item_selected.connect(func(_i): _refresh_plan_pickers())
	army2_picker.item_selected.connect(func(_i): _refresh_plan_pickers())
	zone_picker.item_selected.connect(func(_i): _refresh_plan_pickers())


func _add_picker(grid: Node, label_text: String, node_name: String) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	grid.add_child(label)
	var picker := OptionButton.new()
	picker.name = node_name
	picker.custom_minimum_size = Vector2(300, 0)
	grid.add_child(picker)
	return picker


func _build_progress(parent: Node) -> void:
	progress_label = Label.new()
	progress_label.name = "SimProgressLabel"
	progress_label.text = "Not running."
	progress_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	parent.add_child(progress_label)

	eta_label = Label.new()
	eta_label.name = "SimEtaLabel"
	eta_label.text = ""
	eta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eta_label.add_theme_color_override("font_color", Color(0.80, 0.74, 0.55))
	parent.add_child(eta_label)


func _build_results(parent: Node) -> void:
	results_panel = VBoxContainer.new()
	results_panel.name = "SimResultsPanel"
	results_panel.add_theme_constant_override("separation", 6)
	results_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(results_panel)

	results_tree = Tree.new()
	results_tree.name = "SimResultsTree"
	results_tree.columns = 7
	results_tree.column_titles_visible = true
	results_tree.hide_root = true
	results_tree.custom_minimum_size = Vector2(0, 220)
	var titles := ["Game", "Seed", "Result", "VP", "Round", "Plan hits P1/P2", "Seconds"]
	for i in range(titles.size()):
		results_tree.set_column_title(i, titles[i])
	results_panel.add_child(results_tree)

	summary_label = RichTextLabel.new()
	summary_label.name = "SimSummaryLabel"
	summary_label.bbcode_enabled = true
	summary_label.fit_content = true
	summary_label.scroll_active = false
	summary_label.custom_minimum_size = Vector2(0, 40)
	results_panel.add_child(summary_label)

	replay_label = RichTextLabel.new()
	replay_label.name = "SimReplayLabel"
	replay_label.bbcode_enabled = true
	replay_label.fit_content = true
	replay_label.scroll_active = false
	replay_label.custom_minimum_size = Vector2(0, 30)
	results_panel.add_child(replay_label)


func _build_actions(parent: Node) -> void:
	var actions := HBoxContainer.new()
	actions.name = "SimActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	parent.add_child(actions)

	export_button = Button.new()
	export_button.name = "SimExportButton"
	export_button.text = "Show results file"
	export_button.disabled = true
	export_button.pressed.connect(_on_export_pressed)
	actions.add_child(export_button)

	close_button = Button.new()
	close_button.name = "SimCloseButton"
	close_button.text = "Close"
	close_button.pressed.connect(close)
	actions.add_child(close_button)

	cancel_button = Button.new()
	cancel_button.name = "SimCancelButton"
	cancel_button.text = "Cancel run"
	cancel_button.disabled = true
	cancel_button.pressed.connect(_on_cancel_pressed)
	actions.add_child(cancel_button)

	run_button = Button.new()
	run_button.name = "SimRunButton"
	run_button.text = "Run"
	run_button.pressed.connect(_on_run_pressed)
	actions.add_child(run_button)


# ============================================================
# Sources
# ============================================================

func _refresh_sources() -> void:
	_army_ids = []
	army1_picker.clear()
	army2_picker.clear()
	if ArmyListManager != null and ArmyListManager.has_method("get_available_armies"):
		for entry in ArmyListManager.get_available_armies():
			var army_id := str(entry.get("id", entry)) if entry is Dictionary else str(entry)
			var label := str(entry.get("name", army_id)) if entry is Dictionary else army_id
			_army_ids.append(army_id)
			army1_picker.add_item(label)
			army2_picker.add_item(label)
	if _army_ids.is_empty():
		army1_picker.add_item("(no armies found)")
		army2_picker.add_item("(no armies found)")

	_zone_ids = []
	zone_picker.clear()
	for zone_id in ["hammer_anvil", "dawn_of_war", "search_and_destroy",
			"sweeping_engagement", "crucible_of_battle", "tipping_point"]:
		_zone_ids.append(zone_id)
		zone_picker.add_item(zone_id.replace("_", " ").capitalize())

	_layout_ids = []
	layout_picker.clear()
	var terrain = get_tree().root.get_node_or_null("TerrainManager")
	if terrain != null and terrain.has_method("get_all_layout_ids"):
		for layout_id in terrain.get_all_layout_ids():
			_layout_ids.append(str(layout_id))
			layout_picker.add_item(str(layout_id))
	if _layout_ids.is_empty():
		layout_picker.add_item("(no layouts)")

	_refresh_plan_pickers()
	_refresh_estimate()


func _refresh_plan_pickers() -> void:
	"""Offer only plans written for that seat's army, exactly as the menu's
	per-seat pickers do — a plan for another army would degrade to the formula
	on every unit and the run would silently measure nothing."""
	var plans: Array = PlanManagerScript.list_plans()
	for player in [1, 2]:
		var picker: OptionButton = plan1_picker if player == 1 else plan2_picker
		var previous := _selected_plan(player)
		var values: Array = ["none"]
		picker.clear()
		picker.add_item("None (no plan)")
		var army_id := _selected_army(player)
		for entry in plans:
			var meta_data: Dictionary = entry.get("metadata", {})
			if str(meta_data.get("army_file", "")) != army_id:
				continue
			var label := str(entry.get("name", ""))
			if str(meta_data.get("deployment_zone_id", "")) != _selected_zone():
				label = "%s  [%s]" % [label, str(meta_data.get("deployment_zone_id", ""))]
			picker.add_item(label)
			values.append(str(entry.get("path", "")))
		if player == 1:
			_plan1_values = values
		else:
			_plan2_values = values
		var idx := values.find(previous)
		picker.selected = idx if idx >= 0 else 0


func _selected_army(player: int) -> String:
	var picker: OptionButton = army1_picker if player == 1 else army2_picker
	if picker == null or picker.selected < 0 or picker.selected >= _army_ids.size():
		return ""
	return str(_army_ids[picker.selected])


func _selected_plan(player: int) -> String:
	var picker: OptionButton = plan1_picker if player == 1 else plan2_picker
	var values: Array = _plan1_values if player == 1 else _plan2_values
	if picker == null or picker.selected < 0 or picker.selected >= values.size():
		return "none"
	return str(values[picker.selected])


func _selected_zone() -> String:
	if zone_picker == null or zone_picker.selected < 0 or zone_picker.selected >= _zone_ids.size():
		return "hammer_anvil"
	return str(_zone_ids[zone_picker.selected])


func _selected_layout() -> String:
	if layout_picker == null or layout_picker.selected < 0 or layout_picker.selected >= _layout_ids.size():
		return ""
	return str(_layout_ids[layout_picker.selected])


# ============================================================
# Run
# ============================================================

func build_run_options() -> Dictionary:
	return {
		"zone_id": _selected_zone(),
		"layout_id": _selected_layout(),
		"mission_id": "take_and_hold",
		"army1": _selected_army(1),
		"army2": _selected_army(2),
		"plan1": _selected_plan(1),
		"plan2": _selected_plan(2),
		"games": int(games_spin.value),
		"seed_base": 1000,
		"difficulty": difficulty_picker.selected,
	}


func _on_run_pressed() -> void:
	if PlanSimulator.is_running():
		return
	_rows = []
	results_tree.clear()
	results_tree.create_item()
	summary_label.text = ""
	replay_label.text = ""
	# The previous run's measured s/game is not an estimate for this one — the
	# armies or the game count may have changed. Clear it and let the new run
	# measure again.
	eta_label.text = ""
	export_button.disabled = true
	PlanSimulator.start(build_run_options())


func _on_cancel_pressed() -> void:
	PlanSimulator.cancel()
	progress_label.text = "Cancelling after this game…"
	cancel_button.disabled = true


func _on_export_pressed() -> void:
	"""Show the absolute path of the results JSON.

	Writes to the progress line, NOT the replay line — overwriting the replay
	guidance would trade one piece of information for another."""
	var path := str(PlanSimulator.last_summary.get("results_path", ""))
	if path == "":
		return
	progress_label.text = ProjectSettings.globalize_path(path)
	var toast = get_tree().root.get_node_or_null("ToastManager")
	if toast != null:
		toast.show_info("Results at %s" % path.get_file())


func _set_running_ui(running: bool) -> void:
	run_button.disabled = running
	cancel_button.disabled = not running
	for control in [army1_picker, army2_picker, plan1_picker, plan2_picker,
			zone_picker, layout_picker, difficulty_picker]:
		control.disabled = running
	games_spin.editable = not running


# ============================================================
# Progress / results
# ============================================================

func _on_run_started(total_games: int) -> void:
	_set_running_ui(true)
	progress_label.text = "Running %d game(s)…" % total_games
	eta_label.text = "Time left is unknown until the first game finishes — a battle takes anywhere from a few seconds to several minutes depending on the armies."
	if _poll_timer != null:
		_poll_timer.start()


func _on_poll() -> void:
	if PlanSimulator.is_running():
		var line := PlanSimulator.get_progress_line()
		if line != "":
			progress_label.text = line


func _on_game_finished(_index: int, result: Dictionary) -> void:
	_rows.append(result)
	_add_result_row(result)
	_refresh_estimate()


func _add_result_row(result: Dictionary) -> void:
	if results_tree.get_root() == null:
		results_tree.create_item()
	var item := results_tree.create_item(results_tree.get_root())
	item.set_text(0, str(result.get("game", "")))
	item.set_text(1, str(result.get("seed", "")))
	var status := str(result.get("status", ""))
	var winner := int(result.get("winner", 0))
	var verdict := "Draw"
	if winner == 1:
		verdict = "Player 1"
	elif winner == 2:
		verdict = "Player 2"
	if status != "completed":
		verdict = "%s (%s)" % [verdict, status]
		item.set_custom_color(2, Color(0.88, 0.42, 0.42))
	item.set_text(2, verdict)
	item.set_text(3, "%d - %d" % [int(result.get("vp_p1", 0)), int(result.get("vp_p2", 0))])
	item.set_text(4, str(result.get("battle_round", "")))
	item.set_text(5, "%d / %d" % [int(result.get("plan_adherence_p1", 0)),
		int(result.get("plan_adherence_p2", 0))])
	item.set_text(6, "%.1f" % float(result.get("wall_seconds", 0.0)))


func _refresh_estimate() -> void:
	"""ETA from the MEASURED seconds per game, never from a guess. Blank until
	there is a measurement to base it on."""
	if _rows.is_empty():
		if not PlanSimulator.is_running():
			var games := int(games_spin.value) if games_spin != null else 0
			if games >= LARGE_RUN_WARNING_GAMES:
				eta_label.text = "%d games is a long run — a single battle can take several minutes with a full army. You can cancel part way through and keep the games already played." % games
			else:
				eta_label.text = ""
		return
	var total := 0.0
	for row in _rows:
		total += float(row.get("wall_seconds", 0.0))
	var per_game := total / float(_rows.size())
	var remaining := maxi(0, int(games_spin.value) - _rows.size())
	if remaining <= 0:
		eta_label.text = "Measured %.0fs per game." % per_game
	else:
		eta_label.text = "Measured %.0fs per game — about %s left for the remaining %d." % [
			per_game, _format_duration(per_game * remaining), remaining]


func _format_duration(seconds: float) -> String:
	if seconds < 90.0:
		return "%.0f seconds" % seconds
	return "%.0f minutes" % (seconds / 60.0)


func _on_run_finished(summary: Dictionary) -> void:
	_finish_run(summary, false)


func _on_run_cancelled(summary: Dictionary) -> void:
	_finish_run(summary, true)


func _finish_run(summary: Dictionary, cancelled: bool) -> void:
	if _poll_timer != null:
		_poll_timer.stop()
	_set_running_ui(false)
	progress_label.text = "Cancelled after %d game(s)." % int(summary.get("games_run", 0)) if cancelled \
		else "Finished %d game(s)." % int(summary.get("games_completed", 0))
	_refresh_estimate()

	var plan1 := str(summary.get("plan1", "(no plan)"))
	var plan2 := str(summary.get("plan2", "(no plan)"))
	summary_label.text = "[b]%s[/b]\n[color=#B9B2A0]P1: %s   ·   P2: %s   ·   %s, %s[/color]" % [
		str(summary.get("headline", "")), plan1, plan2,
		str(summary.get("zone_id", "")), str(summary.get("army1", ""))]

	var path := str(summary.get("results_path", ""))
	if path != "":
		export_button.disabled = false
	# The games auto-record (PlanSimulator leaves ReplayManager.auto_record_ai
	# on), so each one is rewatchable from the menu's Watch Replays screen.
	replay_label.text = "[color=#B9B2A0]Each game was recorded — open [b]Watch Replays[/b] on the main menu to play one back. Results file: %s[/color]" % path


func summary_text() -> String:
	"""Plain-text summary, for scenarios and for a quick copy out."""
	return str(PlanSimulator.last_summary.get("headline", ""))


func row_count() -> int:
	return _rows.size()
