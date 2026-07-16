extends Node

# ScenarioRunner — executes a JSON-defined scenario file against the running
# game, simulating player input via real InputEvents and asserting against
# both the visible scene tree and the underlying GameState.
#
# Activates only when `--scenario-file=PATH` is on the cmdline. Otherwise it
# is a no-op autoload.
#
# See 40k/tests/scenarios/_schema.md for the scenario format.
#
# Wire protocol:
#   godot --path 40k --scenario-file=tests/scenarios/sp/<id>.json
#
# Output:
#   user://test_results/scenarios/<scenario_id>.json     — result summary
#   user://test_results/scenarios/<scenario_id>_<label>.png — screenshots
#   user://test_results/scenarios/<scenario_id>_FAIL_step_<n>.png — auto on failure
#
# Process exit code: 0 on all-pass, 1 on any failure.

signal scenario_finished(scenario_id: String, passed: int, failed: int)

var _scenario_path: String = ""
var _scenario: Dictionary = {}
var _step_results: Array = []
var _last_action_result = null
var _start_cp: Dictionary = {}  # player_id -> cp at scenario start (for delta_from_start)
var _started: bool = false

const RESULTS_SUBDIR := "test_results/scenarios"


func _ready() -> void:
	# Parse cmdline args. We accept either engine args or user args (after `--`).
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if typeof(a) == TYPE_STRING and a.begins_with("--scenario-file="):
			_scenario_path = a.split("=", true, 1)[1]
			break

	if _scenario_path == "":
		return  # not in scenario mode — no-op autoload

	print("[ScenarioRunner] Activating, scenario_file=%s" % _scenario_path)
	# Defer to next idle frame so other autoloads (GameState, SaveLoadManager,
	# PhaseManager, etc.) finish their _ready before we touch them.
	call_deferred("_kick_off")


func _kick_off() -> void:
	if _started:
		return
	_started = true
	await get_tree().process_frame
	await get_tree().process_frame
	_run_scenario()


func _run_scenario() -> void:
	# 1) Read JSON
	var f := FileAccess.open(_scenario_path, FileAccess.READ)
	if f == null:
		_fail_and_quit("could not open scenario file: %s" % _scenario_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_fail_and_quit("scenario JSON failed to parse: %s" % _scenario_path)
		return
	_scenario = parsed

	var scenario_id: String = _scenario.get("id", "unnamed")
	print("[ScenarioRunner] === scenario id=%s ===" % scenario_id)

	# 2) Load fixture (optional)
	var fixture: String = _scenario.get("fixture", "")
	if fixture != "":
		var save_mgr = get_node_or_null("/root/SaveLoadManager")
		var game_state = get_node_or_null("/root/GameState")
		if save_mgr == null or game_state == null:
			_fail_and_quit("autoloads missing (SaveLoadManager / GameState)")
			return
		# SaveLoadManager only resolves res://saves/. The committed fixtures
		# live in res://tests/saves/, so on a fresh clone (CI, containers)
		# every fixture scenario failed with "Save file not found". Stage the
		# fixture into saves/ when it's only present in tests/saves/.
		var fixture_file = fixture if fixture.ends_with(".w40ksave") else fixture + ".w40ksave"
		var saves_path = "res://saves/" + fixture_file
		var tests_path = "res://tests/saves/" + fixture_file
		if not FileAccess.file_exists(saves_path) and FileAccess.file_exists(tests_path):
			var dir = DirAccess.open("res://")
			if dir:
				dir.copy(tests_path, saves_path)
				var meta_src = tests_path.replace(".w40ksave", ".meta")
				if FileAccess.file_exists(meta_src):
					dir.copy(meta_src, saves_path.replace(".w40ksave", ".meta"))
				print("[ScenarioRunner] staged fixture from tests/saves: %s" % fixture_file)
		var ok = save_mgr.load_game(fixture)
		if not ok:
			_fail_and_quit("fixture load failed: %s" % fixture)
			return
		# Critical: tell Main._ready() to honour the loaded state instead of reinitializing
		game_state.state["meta"]["from_save"] = true
		print("[ScenarioRunner] fixture loaded: %s" % fixture)

	# 2b) Set the rules edition BEFORE the phase transition (optional) —
	# 11e scenarios need the edition active when phase controllers build
	# their initial UI, not injected mid-scenario via execute_script.
	var edition = _scenario.get("edition", null)
	if edition != null:
		GameConstants.edition = int(edition)
		print("[ScenarioRunner] edition set to %d" % int(edition))

	# 3) Set RNG seed (optional)
	var rng_seed = _scenario.get("rng_seed", null)
	if rng_seed != null and typeof(rng_seed) == TYPE_FLOAT:
		rng_seed = int(rng_seed)
	if typeof(rng_seed) == TYPE_INT:
		var rules = get_node_or_null("/root/RulesEngine")
		if rules != null:
			rules.set_test_seed(rng_seed)
			print("[ScenarioRunner] rng_seed=%d" % rng_seed)
		# The secondary-mission deck shuffle has its own randomize()'d RNG —
		# unseeded, it made every "AI plays a turn" scenario flaky: whenever
		# the AI player randomly drew a requires-interaction card (e.g.
		# A Tempting Target) the AI paused for a human dialog that never
		# comes, and all later assertions failed. Seed it too.
		var smm = get_node_or_null("/root/SecondaryMissionManager")
		if smm != null and smm.has_method("set_test_seed"):
			smm.set_test_seed(rng_seed)
			print("[ScenarioRunner] secondary deck seeded=%d" % rng_seed)

	# 3b) Disable AI if the scenario opts in. Must neutralise BOTH the
	# AIPlayer.enabled flag AND the player_type fields in the loaded
	# game_config — otherwise the change_scene_to_file below triggers
	# AIPlayer.Reconfigured-after-load, which reads game_config and
	# re-enables AI for any "AI"-typed player, undoing a flag-only
	# disable. By overwriting player1_type/player2_type to HUMAN in
	# GameState before the scene change, the reconfigure path sets
	# ai_players[...] = false naturally. Scenarios that specifically
	# test AI behaviour (e.g. fight_self_targeting) leave this unset.
	if _scenario.get("disable_ai", false):
		var ai_player = get_node_or_null("/root/AIPlayer")
		var gs = get_node_or_null("/root/GameState")
		if gs != null:
			var meta = gs.state.get("meta", {})
			var gc = meta.get("game_config", {})
			gc["player1_type"] = "HUMAN"
			gc["player2_type"] = "HUMAN"
			meta["game_config"] = gc
			gs.state["meta"] = meta
		if ai_player != null:
			ai_player.enabled = false
			ai_player.ai_players = {1: false, 2: false}
			print("[ScenarioRunner] AI disabled (disable_ai=true; player_types→HUMAN)")

	# 4) Switch to the live battle scene so the UI / TokenLayer renders the
	#    loaded fixture — this is the rendering pipeline that headless
	#    state-mutation tests bypassed.
	if fixture != "":
		print("[ScenarioRunner] switching to res://scenes/Main.tscn")
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
		# Wait for the new scene to be ready
		var waited := 0
		while waited < 240 and (get_tree().current_scene == null or not get_tree().current_scene.is_node_ready()):
			await get_tree().process_frame
			waited += 1
		# Extra settling frames for TokenLayer / dialog instantiation
		for i in range(8):
			await get_tree().process_frame

	# 5) Phase transition (optional)
	if _scenario.has("transition_to_phase"):
		var phase_n = _scenario["transition_to_phase"]
		if typeof(phase_n) == TYPE_FLOAT:
			phase_n = int(phase_n)
		if typeof(phase_n) == TYPE_INT:
			var phase_mgr = get_node_or_null("/root/PhaseManager")
			if phase_mgr != null:
				phase_mgr.transition_to_phase(phase_n)
				print("[ScenarioRunner] transitioned to phase %d" % phase_n)
				for i in range(4):
					await get_tree().process_frame

	# 5b) Re-disable AI after the scene change. The scene-change-to-Main
	# above triggers AIPlayer.Reconfigured (which reads game_config and
	# sets enabled=true if any player is AI), undoing the 3b disable.
	# We re-apply here so AI is off for the actual step walk. This is
	# belt-and-braces: 3b suppresses AI during scene init, 5b
	# suppresses for the steps.
	if _scenario.get("disable_ai", false):
		var ai_player2 = get_node_or_null("/root/AIPlayer")
		if ai_player2 != null and ai_player2.enabled:
			ai_player2.enabled = false
			print("[ScenarioRunner] AI re-disabled after scene reconfigure")

	# 6) Capture starting CP for delta_from_start asserts
	_start_cp = _capture_cp_snapshot()

	# 7) Walk steps
	var steps = _scenario.get("steps", [])
	var passed := 0
	var failed := 0
	# Per-step screenshot mode: when SCENARIO_SCREENSHOT_EVERY_STEP=1 the
	# runner takes a screenshot after every step (not just explicit
	# 'screenshot' acts) and records the path + original step input in the
	# result record. Powers the visual-regression-loop critic, which needs a
	# frame per step to judge "did the UI render what the scenario intended."
	var screenshot_every := OS.get_environment("SCENARIO_SCREENSHOT_EVERY_STEP") == "1"
	# Selector dry-run mode: when SCENARIO_SELECTOR_DRY_RUN=1 the runner
	# walks steps but only resolves selectors (click_node, click_unit,
	# expect_node_*, expect_token_visible) without clicking, dispatching,
	# or screenshotting. Each step records selector_status: resolved /
	# not_found / n/a. Catches "scenario silently no-ops because a button
	# moved" before the screenshot loop wastes a turn.
	var selector_dry_run := OS.get_environment("SCENARIO_SELECTOR_DRY_RUN") == "1"
	if selector_dry_run:
		print("[ScenarioRunner] SELECTOR DRY-RUN mode — no UI mutation, only resolution checks")
	for i in range(steps.size()):
		var step = steps[i]
		var act = str(step.get("act", ""))
		print("[ScenarioRunner] step %d/%d: %s" % [i, steps.size() - 1, act])
		var rec: Dictionary
		if selector_dry_run:
			rec = _dry_run_resolve_step(i, act, step)
		else:
			rec = await _execute_step(i, act, step)
		_step_results.append(rec)
		if rec.get("pass", false):
			passed += 1
			print("  PASS")
		else:
			failed += 1
			var detail = rec.get("error", "")
			print("  FAIL  %s" % detail)
			if not selector_dry_run:
				_capture_failure_screenshot(scenario_id, i)
		if screenshot_every and not selector_dry_run:
			var shot_rel := await _capture_per_step_screenshot(scenario_id, i, act)
			if shot_rel != "":
				rec["per_step_screenshot"] = shot_rel
			rec["step_input"] = step

	# 8) Reset RNG so subsequent normal play is unaffected
	var rules2 = get_node_or_null("/root/RulesEngine")
	if rules2 != null:
		rules2.set_test_seed(-1)

	# 9) Write results (and selectors_report.json in dry-run mode)
	if selector_dry_run:
		_write_selectors_report(scenario_id, passed, failed)
	_write_results(scenario_id, passed, failed)
	print("[ScenarioRunner] === %s: %d passed, %d failed ===" % [scenario_id, passed, failed])
	emit_signal("scenario_finished", scenario_id, passed, failed)
	get_tree().quit(0 if failed == 0 else 1)


# ============================================================================
# STEP DISPATCH
# ============================================================================

func _execute_step(i: int, act: String, step: Dictionary) -> Dictionary:
	var rec := {"step": i, "act": act}
	match act:
		"wait_seconds":
			var s = float(step.get("seconds", 0.1))
			await get_tree().create_timer(s).timeout
			rec["pass"] = true
		"wait_frames":
			var n = int(step.get("frames", 1))
			for j in range(n):
				await get_tree().process_frame
			rec["pass"] = true
		"wait_for_tweens":
			# Wait until all active Tweens on the current scene complete,
			# or until timeout_s elapses (default 5s). Use this between
			# dispatch_actions in scenarios where the per-step screenshot
			# would otherwise capture mid-tween state — e.g. camera pans,
			# token repositioning, dialog opens. Returns pass with the
			# observed tween-clear time, fail on timeout.
			var timeout_s := float(step.get("timeout_s", 10.0))
			var elapsed := 0.0
			var poll_s := 0.05
			var tree := get_tree()
			while elapsed < timeout_s:
				var any_running := false
				for tw in tree.get_processed_tweens():
					if tw.is_valid() and tw.is_running():
						any_running = true
						break
				if not any_running:
					rec["pass"] = true
					rec["tween_clear_at"] = elapsed
					break
				await tree.create_timer(poll_s).timeout
				elapsed += poll_s
			if not rec.has("pass"):
				rec["pass"] = false
				rec["error"] = "wait_for_tweens: %.2fs elapsed, tweens still running" % elapsed
		"screenshot":
			rec.merge(await _do_screenshot(step), true)
		"dispatch_action":
			rec.merge(await _do_dispatch_action(step), true)
		"click_unit":
			rec.merge(await _do_click_unit(step), true)
		"click_node":
			rec.merge(await _do_click_node(step), true)
		"click_board_at":
			rec.merge(await _do_click_board_at(step), true)
		"drag_board":
			rec.merge(await _do_drag_board(step), true)
		"hover_unit":
			rec.merge(await _do_hover_unit(step), true)
		"hover_board_at":
			rec.merge(await _do_hover_board_at(step), true)
		"simulate_key":
			rec.merge(await _do_simulate_key(step), true)
		"simulate_wheel":
			rec.merge(await _do_simulate_wheel(step), true)
		"simulate_joy_button":
			rec.merge(await _do_simulate_joy_button(step), true)
		"simulate_joy_axis":
			rec.merge(await _do_simulate_joy_axis(step), true)
		"pad_cursor_glide":
			rec.merge(await _do_pad_cursor_glide(step), true)
		"expect_state":
			rec.merge(_do_expect_state(step), true)
		"expect_cp":
			rec.merge(_do_expect_cp(step), true)
		"expect_action_result":
			rec.merge(_do_expect_action_result(step), true)
		"expect_phase":
			rec.merge(_do_expect_phase(step), true)
		"expect_phase_property":
			rec.merge(_do_expect_phase_property(step), true)
		"expect_node_visible":
			rec.merge(await _do_expect_node_visible(step), true)
		"expect_node_property":
			rec.merge(_do_expect_node_property(step), true)
		"expect_token_visible":
			rec.merge(await _do_expect_token_visible(step), true)
		"execute_script":
			rec.merge(_do_execute_script(step), true)
		"pixel_diff":
			rec.merge(_do_pixel_diff(step), true)
		"expect_baseline_unchanged":
			rec.merge(_do_expect_baseline_unchanged(step), true)
		_:
			rec["pass"] = false
			rec["error"] = "unknown act: %s" % act
	return rec


# ============================================================================
# STEP IMPLEMENTATIONS
# ============================================================================

func _do_screenshot(step: Dictionary) -> Dictionary:
	# Screenshot hygiene: the PhaseTransitionBanner lingers mid-screen and
	# obscures the board in captures — hide it (it re-shows on the next
	# phase change, so live play is unaffected).
	var banner = get_tree().root.find_child("PhaseTransitionBanner", true, false)
	if banner != null and banner.visible:
		banner.visible = false
	var label: String = str(step.get("label", "step"))
	var scenario_id: String = str(_scenario.get("id", "unnamed"))
	var dir_path = "user://%s" % RESULTS_SUBDIR
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	# Yield a frame so any pending render commits
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return {"pass": false, "error": "no viewport"}
	var img := vp.get_texture().get_image()
	if img == null:
		return {"pass": false, "error": "viewport returned no image"}
	var rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, label]
	var abs := ProjectSettings.globalize_path("user://" + rel)
	if step.has("region"):
		var r = step["region"]
		if typeof(r) == TYPE_ARRAY and r.size() == 4:
			img = img.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
	var err := img.save_png(abs)
	if err != OK:
		return {"pass": false, "error": "save_png failed: %d" % err, "path": abs}
	return {"pass": true, "path": rel}


func _do_dispatch_action(step: Dictionary) -> Dictionary:
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr == null:
		return {"pass": false, "error": "no PhaseManager"}
	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		return {"pass": false, "error": "no current phase instance"}
	var action = step.get("action", {})
	# Convert JSON-friendly [x, y] arrays / {x, y} dicts to Vector2 for
	# action fields that the phase code expects as Vector2. Mirrors the
	# logic in addons/godot_mcp/handlers/wh40k_handlers._normalize_action_positions.
	# Without this, per_model_paths arrays sum to 0 inside Measurement and
	# multi-model moves silently no-op while validators report success.
	action = _normalize_action_positions(action)
	if not phase.has_method("execute_action"):
		return {"pass": false, "error": "phase lacks execute_action"}
	var result = phase.execute_action(action)
	# Phases sometimes return a Variant or a Dictionary; normalize
	_last_action_result = result
	# Yield a frame for any signal-driven UI updates
	await get_tree().process_frame
	return {"pass": true, "result_summary": _summarize_result(result)}


func _do_click_unit(step: Dictionary) -> Dictionary:
	var unit_id: String = str(step.get("unit_id", ""))
	if unit_id == "":
		return {"pass": false, "error": "click_unit needs unit_id"}
	var token: Node = _find_unit_token(unit_id)
	if token == null:
		return {"pass": false, "error": "no token found for unit %s" % unit_id}
	var screen_pos := _node2d_to_screen(token)
	if screen_pos == Vector2.INF:
		return {"pass": false, "error": "could not project token to screen"}
	await _send_click(screen_pos)
	return {"pass": true, "screen_position": [screen_pos.x, screen_pos.y]}


func _do_click_node(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	if node_path == "":
		return {"pass": false, "error": "click_node needs node"}
	var node: Node = get_node_or_null(node_path)
	if node == null:
		return {"pass": false, "error": "no node at path %s" % node_path}

	# Shortcut: emit pressed directly on Buttons (skips hit-testing pitfalls)
	if step.get("emit_pressed", false) and node.has_signal("pressed"):
		node.emit_signal("pressed")
		await get_tree().process_frame
		return {"pass": true, "via": "emit_pressed"}

	var screen_pos: Vector2
	if node is Control:
		var rect: Rect2 = (node as Control).get_global_rect()
		screen_pos = rect.position + rect.size * 0.5
	elif node is Node2D:
		screen_pos = _node2d_to_screen(node as Node2D)
	else:
		return {"pass": false, "error": "node is neither Control nor Node2D"}

	if screen_pos == Vector2.INF:
		return {"pass": false, "error": "could not compute click position"}
	await _send_click(screen_pos)
	return {"pass": true, "screen_position": [screen_pos.x, screen_pos.y]}


func _do_click_board_at(step: Dictionary) -> Dictionary:
	# Click an arbitrary BOARD/WORLD position (board px, the coordinate system
	# the scenario author reasons about — e.g. deployment-zone coords). The world
	# point is projected to screen via the scene's world_to_screen_position, the
	# cursor is warped there (so board handlers reading
	# get_viewport().get_mouse_position() act on it), and a real mouse click is
	# injected. Use for model placement, scout-move drops, or any click on empty
	# board where no node/token exists.
	if not (step.has("x") and step.has("y")):
		return {"pass": false, "error": "click_board_at needs x and y (world/board px)"}
	var world_pos := Vector2(float(step["x"]), float(step["y"]))
	var scene := get_tree().current_scene
	if scene == null:
		return {"pass": false, "error": "no current scene"}
	# Project board/world -> screen using the scene's OWN transform (the inverse
	# of its screen_to_world_position), not the viewport canvas transform — the
	# board lives under a BoardRoot node whose pan/zoom the canvas transform does
	# not capture in the runner's context.
	var screen_pos: Vector2
	if scene.has_method("world_to_screen_position"):
		screen_pos = scene.world_to_screen_position(world_pos)
	else:
		var viewport := scene.get_viewport()
		if viewport == null:
			return {"pass": false, "error": "no viewport and no world_to_screen_position"}
		screen_pos = viewport.get_canvas_transform() * world_pos
	await _send_click(screen_pos)
	return {"pass": true, "world": [world_pos.x, world_pos.y], "screen": [screen_pos.x, screen_pos.y]}


func _do_drag_board(step: Dictionary) -> Dictionary:
	# Drag from one BOARD/WORLD position to another with REAL input events:
	# warp + LMB press at `from`, a series of InputEventMouseMotion steps,
	# LMB release at `to`. This is the player path for drag-to-move flows
	# (fight-phase pile-in/consolidate model movement, etc.) — no controller
	# state is poked. Coordinates are board px, projected like click_board_at.
	for k in ["from_x", "from_y", "to_x", "to_y"]:
		if not step.has(k):
			return {"pass": false, "error": "drag_board needs from_x/from_y/to_x/to_y (world/board px)"}
	var from_world := Vector2(float(step["from_x"]), float(step["from_y"]))
	var to_world := Vector2(float(step["to_x"]), float(step["to_y"]))
	var scene := get_tree().current_scene
	if scene == null:
		return {"pass": false, "error": "no current scene"}
	var from_screen: Vector2
	var to_screen: Vector2
	if scene.has_method("world_to_screen_position"):
		from_screen = scene.world_to_screen_position(from_world)
		to_screen = scene.world_to_screen_position(to_world)
	else:
		var viewport := scene.get_viewport()
		if viewport == null:
			return {"pass": false, "error": "no viewport and no world_to_screen_position"}
		from_screen = viewport.get_canvas_transform() * from_world
		to_screen = viewport.get_canvas_transform() * to_world
	from_screen = from_screen.round()
	to_screen = to_screen.round()

	Input.warp_mouse(from_screen)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from_screen
	press.global_position = from_screen
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	await get_tree().process_frame

	var motion_steps: int = int(step.get("steps", 8))
	motion_steps = max(motion_steps, 2)
	var prev := from_screen
	for i in range(1, motion_steps + 1):
		var p := (from_screen.lerp(to_screen, float(i) / float(motion_steps))).round()
		Input.warp_mouse(p)
		var motion := InputEventMouseMotion.new()
		motion.position = p
		motion.global_position = p
		motion.relative = p - prev
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		prev = p
		await get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to_screen
	release.global_position = to_screen
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"pass": true,
		"from_world": [from_world.x, from_world.y], "to_world": [to_world.x, to_world.y],
		"from_screen": [from_screen.x, from_screen.y], "to_screen": [to_screen.x, to_screen.y]}


func _do_hover_unit(step: Dictionary) -> Dictionary:
	# Move the mouse over a unit's token with a REAL buttonless
	# InputEventMouseMotion — the player path for hover-driven UI such as the
	# board token tooltip. Resolves the token like click_unit.
	var unit_id: String = str(step.get("unit_id", ""))
	if unit_id == "":
		return {"pass": false, "error": "hover_unit needs unit_id"}
	var token: Node = _find_unit_token(unit_id)
	if token == null:
		return {"pass": false, "error": "no token found for unit %s" % unit_id}
	var screen_pos := _node2d_to_screen(token)
	if screen_pos == Vector2.INF:
		return {"pass": false, "error": "could not project token to screen"}
	await _send_hover(screen_pos)
	return {"pass": true, "screen_position": [screen_pos.x, screen_pos.y]}


func _do_hover_board_at(step: Dictionary) -> Dictionary:
	# Move the mouse to an arbitrary BOARD/WORLD position (board px) with a
	# real buttonless InputEventMouseMotion. Projected like click_board_at.
	# Use to hover empty board (e.g. assert a tooltip hides) or terrain.
	if not (step.has("x") and step.has("y")):
		return {"pass": false, "error": "hover_board_at needs x and y (world/board px)"}
	var world_pos := Vector2(float(step["x"]), float(step["y"]))
	var scene := get_tree().current_scene
	if scene == null:
		return {"pass": false, "error": "no current scene"}
	var screen_pos: Vector2
	if scene.has_method("world_to_screen_position"):
		screen_pos = scene.world_to_screen_position(world_pos)
	else:
		var viewport := scene.get_viewport()
		if viewport == null:
			return {"pass": false, "error": "no viewport and no world_to_screen_position"}
		screen_pos = viewport.get_canvas_transform() * world_pos
	await _send_hover(screen_pos)
	return {"pass": true, "world": [world_pos.x, world_pos.y], "screen": [screen_pos.x, screen_pos.y]}


func _send_hover(screen_pos: Vector2) -> void:
	# Warp the live cursor (board handlers read it) then inject a buttonless
	# motion event so _input-driven hover UI reacts exactly as with a real
	# mouse. Mirrors _send_click's warp rationale.
	screen_pos = screen_pos.round()
	var prev := get_viewport().get_mouse_position()
	Input.warp_mouse(screen_pos)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	motion.relative = screen_pos - prev
	motion.button_mask = 0
	Input.parse_input_event(motion)
	await get_tree().process_frame
	await get_tree().process_frame


func _do_simulate_key(step: Dictionary) -> Dictionary:
	var keycode = step.get("keycode", "")
	var kc: int = 0
	if typeof(keycode) == TYPE_STRING:
		kc = OS.find_keycode_from_string(keycode)
	elif typeof(keycode) == TYPE_INT:
		kc = int(keycode)
	if kc == 0:
		return {"pass": false, "error": "could not resolve keycode: %s" % str(keycode)}
	# Optional `unicode`: required for text controls (LineEdit/TextEdit) to insert
	# a character — they ignore key events whose unicode is 0. Accepts an int code
	# point or a single-character string.
	var uni: int = 0
	if step.has("unicode"):
		var u = step.get("unicode")
		if typeof(u) == TYPE_STRING and (u as String).length() > 0:
			uni = (u as String).unicode_at(0)
		elif typeof(u) == TYPE_INT or typeof(u) == TYPE_FLOAT:
			uni = int(u)
	var press := InputEventKey.new()
	press.keycode = kc
	press.unicode = uni
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = kc
	release.unicode = uni
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	return {"pass": true}


func _do_simulate_wheel(step: Dictionary) -> Dictionary:
	# Inject mouse-wheel scroll notches (InputEventMouseButton WHEEL_UP/DOWN) at
	# the current cursor position through the OS-event pipeline, so board zoom and
	# any other _unhandled_input wheel consumers react as with a real wheel.
	# `direction`: "up" (default) or "down"; `count`: notches (default 1). Warp
	# the cursor first with hover_board_at to control the zoom anchor.
	var direction: String = str(step.get("direction", "up"))
	var count: int = int(step.get("count", 1))
	var button: int = MOUSE_BUTTON_WHEEL_UP if direction == "up" else MOUSE_BUTTON_WHEEL_DOWN
	var pos: Vector2 = get_viewport().get_mouse_position()
	for i in range(count):
		var press := InputEventMouseButton.new()
		press.button_index = button as MouseButton
		press.pressed = true
		press.position = pos
		press.global_position = pos
		Input.parse_input_event(press)
		await get_tree().process_frame
		var release := InputEventMouseButton.new()
		release.button_index = button as MouseButton
		release.pressed = false
		release.position = pos
		release.global_position = pos
		Input.parse_input_event(release)
		await get_tree().process_frame
	return {"pass": true, "direction": direction, "count": count, "anchor": [pos.x, pos.y]}


func _do_simulate_joy_button(step: Dictionary) -> Dictionary:
	# M0 controller support: inject a raw joypad button press+release through
	# the OS-event pipeline (Input.parse_input_event) so InputMap actions,
	# ui_* focus navigation and InputDeviceManager device detection all react
	# as with a real pad. JoyButton enum: 0=A 1=B 2=X 3=Y 4=Back(View)
	# 6=Start(Menu) 9=LB 10=RB 11-14=D-pad up/down/left/right.
	if not step.has("button_index"):
		return {"pass": false, "error": "simulate_joy_button needs `button_index`"}
	var button_index: int = int(step["button_index"])
	var device: int = int(step.get("device", 0))
	# `state`: "tap" (default, press+release), "press" (hold — e.g. start a
	# cursor drag), "release" (end a held press).
	var state: String = str(step.get("state", "tap"))
	if state in ["tap", "press"]:
		var press := InputEventJoypadButton.new()
		press.device = device
		press.button_index = button_index as JoyButton
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
	if state in ["tap", "release"]:
		var release := InputEventJoypadButton.new()
		release.device = device
		release.button_index = button_index as JoyButton
		release.pressed = false
		Input.parse_input_event(release)
		await get_tree().process_frame
	return {"pass": true, "button_index": button_index, "state": state}


func _do_simulate_joy_axis(step: Dictionary) -> Dictionary:
	# Push a joypad axis to `value`, hold it for `hold_s` seconds, then return
	# it to neutral unless auto_release=false. While held, the axis feeds
	# action strengths so per-frame consumers (pad camera pan / trigger zoom)
	# integrate over the hold. JoyAxis enum: 0/1 left stick, 2/3 right stick,
	# 4/5 triggers (0..1).
	if not step.has("axis"):
		return {"pass": false, "error": "simulate_joy_axis needs `axis`"}
	var axis: int = int(step["axis"])
	var value: float = float(step.get("value", 1.0))
	var hold_s: float = float(step.get("hold_s", 0.3))
	var device: int = int(step.get("device", 0))
	var motion := InputEventJoypadMotion.new()
	motion.device = device
	motion.axis = axis as JoyAxis
	motion.axis_value = value
	Input.parse_input_event(motion)
	if hold_s > 0.0:
		await get_tree().create_timer(hold_s).timeout
	if bool(step.get("auto_release", true)):
		var neutral := InputEventJoypadMotion.new()
		neutral.device = device
		neutral.axis = axis as JoyAxis
		neutral.axis_value = 0.0
		Input.parse_input_event(neutral)
		await get_tree().process_frame
	return {"pass": true, "axis": axis, "value": value, "hold_s": hold_s}


func _do_pad_cursor_glide(step: Dictionary) -> Dictionary:
	# M1 test seam for the virtual cursor: glide the cursor to a target
	# through the SAME per-frame move/warp/motion-synthesis pipeline the left
	# stick uses — only the steering is deterministic. Target one of:
	#   { "unit_id": "U_X" }          — a unit's token
	#   { "node": "/root/Main/..." }  — a Control's centre
	#   { "button_text": "Confirm Move" } — first visible enabled Button with
	#     that exact text (procedurally-built panels have no stable NodePath)
	#   { "x": .., "y": .. }          — board/world px (like click_board_at)
	#   { "x": .., "y": .., "space": "screen" } — raw screen px
	var vc = get_node_or_null("/root/VirtualCursor")
	if vc == null:
		return {"pass": false, "error": "no VirtualCursor autoload"}
	var target := Vector2.INF
	if step.has("button_text"):
		var wanted := str(step["button_text"])
		var btn := _find_visible_button_by_text(wanted)
		if btn == null:
			return {"pass": false, "error": "no visible enabled Button with text '%s'" % wanted}
		target = btn.get_global_rect().get_center()
	elif step.has("unit_id"):
		var token: Node = _find_unit_token(str(step["unit_id"]))
		if token == null:
			return {"pass": false, "error": "no token for unit %s" % str(step["unit_id"])}
		target = _node2d_to_screen(token)
		if target == Vector2.INF:
			return {"pass": false, "error": "could not project token to screen"}
	elif step.has("node"):
		var node: Node = get_node_or_null(NodePath(str(step["node"])))
		if node == null or not (node is Control):
			return {"pass": false, "error": "no Control at path %s" % str(step.get("node"))}
		target = (node as Control).get_global_rect().get_center()
	elif step.has("x") and step.has("y"):
		var p := Vector2(float(step["x"]), float(step["y"]))
		if str(step.get("space", "board")) == "screen":
			target = p
		else:
			var scene := get_tree().current_scene
			if scene == null or not scene.has_method("world_to_screen_position"):
				return {"pass": false, "error": "current scene cannot project board coords"}
			target = scene.world_to_screen_position(p)
	else:
		return {"pass": false, "error": "pad_cursor_glide needs unit_id, node, or x/y"}
	# The cursor's edge-push pans the camera when the target starts off-screen,
	# which moves the target's SCREEN position while the glide is in flight —
	# so re-resolve and re-glide until the cursor rests on the current target.
	var rounds := 0
	while rounds < 8:
		rounds += 1
		var resolved = _resolve_glide_target(step)
		if resolved == null:
			return {"pass": false, "error": "glide target vanished while re-resolving"}
		target = resolved
		if (vc.get_cursor_pos() - target).length() <= 4.0:
			return {"pass": true, "target": [target.x, target.y], "rounds": rounds}
		var ok: bool = await vc.glide_to_screen(target, float(step.get("timeout_s", 4.0)))
		if not ok:
			return {"pass": false, "target": [target.x, target.y],
					"error": "glide did not arrive within timeout (round %d)" % rounds}
	return {"pass": false, "error": "glide target never stabilised after %d rounds" % rounds}


func _resolve_glide_target(step: Dictionary):
	if step.has("button_text"):
		var btn := _find_visible_button_by_text(str(step["button_text"]))
		return null if btn == null else btn.get_global_rect().get_center()
	if step.has("unit_id"):
		var token: Node = _find_unit_token(str(step["unit_id"]))
		if token == null:
			return null
		var p := _node2d_to_screen(token)
		return null if p == Vector2.INF else p
	if step.has("node"):
		var node: Node = get_node_or_null(NodePath(str(step["node"])))
		return null if (node == null or not (node is Control)) else (node as Control).get_global_rect().get_center()
	var world := Vector2(float(step["x"]), float(step["y"]))
	if str(step.get("space", "board")) == "screen":
		return world
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("world_to_screen_position"):
		return null
	return scene.world_to_screen_position(world)


func _find_visible_button_by_text(wanted: String) -> Button:
	var queue: Array = [get_tree().root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Button and n.visible and n.is_visible_in_tree() and not n.disabled and str(n.text).strip_edges() == wanted:
			return n
		for child in n.get_children(true):
			queue.append(child)
	return null


func _do_expect_state(step: Dictionary) -> Dictionary:
	var path: String = str(step.get("path", ""))
	if path == "":
		return {"pass": false, "error": "expect_state needs path"}
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var actual = _walk_path(gs.state, path)
	return _compare(step, actual, "state[%s]" % path)


func _do_expect_cp(step: Dictionary) -> Dictionary:
	var player = step.get("player", null)
	if player == null:
		return {"pass": false, "error": "expect_cp needs player"}
	var pid = str(int(player))
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var actual_cp = gs.state.get("players", {}).get(pid, {}).get("cp", null)
	if step.has("delta_from_start"):
		var start = _start_cp.get(pid, null)
		if start == null:
			return {"pass": false, "error": "no start CP recorded for player %s" % pid}
		var expected_delta = int(step["delta_from_start"])
		var actual_delta = int(actual_cp) - int(start)
		var ok = expected_delta == actual_delta
		return {"pass": ok, "expected_delta": expected_delta, "actual_delta": actual_delta, "start": start, "now": actual_cp,
				"error": "" if ok else "CP delta mismatch"}
	return _compare(step, actual_cp, "players.%s.cp" % pid)


func _do_expect_action_result(step: Dictionary) -> Dictionary:
	if _last_action_result == null:
		return {"pass": false, "error": "no prior dispatch_action result"}
	var path: String = str(step.get("path", ""))
	var actual = _last_action_result if path == "" else _walk_path(_last_action_result, path)
	return _compare(step, actual, "last_result[%s]" % path)


func _do_expect_phase(step: Dictionary) -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {"pass": false, "error": "no GameState"}
	var phase = gs.state.get("meta", {}).get("phase", -1)
	return _compare(step, phase, "meta.phase")


func _do_expect_phase_property(step: Dictionary) -> Dictionary:
	# Assert against a property on the *current phase instance* (e.g.
	# active_fighter_id, awaiting_counter_offensive). These live on the phase
	# Node, not in GameState, but are the canonical way to introspect phase
	# sub-state for tests.
	var prop: String = str(step.get("property", ""))
	if prop == "":
		return {"pass": false, "error": "expect_phase_property needs property"}
	var phase_mgr = get_node_or_null("/root/PhaseManager")
	if phase_mgr == null:
		return {"pass": false, "error": "no PhaseManager"}
	var phase = phase_mgr.get_current_phase_instance()
	if phase == null:
		return {"pass": false, "error": "no current phase instance"}
	if not (prop in phase):
		return {"pass": false, "error": "phase has no property '%s' (script=%s)" % [prop, phase.get_script().resource_path if phase.get_script() else "<none>"]}
	var actual = phase.get(prop)
	return _compare(step, actual, "phase.%s" % prop)


func _do_expect_node_visible(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	if node_path == "":
		return {"pass": false, "error": "expect_node_visible needs node"}
	var timeout_s = float(step.get("timeout_s", 2.0))
	var deadline = Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		var node = get_node_or_null(node_path)
		if node != null:
			var vis: bool = false
			if node.has_method("is_visible_in_tree"):
				vis = node.is_visible_in_tree()
			elif "visible" in node:
				vis = bool(node.visible)
			else:
				vis = true  # exists, no visibility property — accept
			if vis:
				return {"pass": true, "found_after_ms": Time.get_ticks_msec() - (deadline - int(timeout_s * 1000))}
		await get_tree().process_frame
	return {"pass": false, "error": "node not visible within %ss: %s" % [str(timeout_s), node_path]}


func _do_expect_node_property(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node", ""))
	var prop: String = str(step.get("property", ""))
	if node_path == "" or prop == "":
		return {"pass": false, "error": "expect_node_property needs node + property"}
	var node = get_node_or_null(node_path)
	if node == null:
		return {"pass": false, "error": "no node at %s" % node_path}
	if not (prop in node):
		return {"pass": false, "error": "node %s has no property %s" % [node_path, prop]}
	var actual = node.get(prop)
	return _compare(step, actual, "%s.%s" % [node_path, prop])


func _do_expect_token_visible(step: Dictionary) -> Dictionary:
	var unit_id: String = str(step.get("unit_id", ""))
	if unit_id == "":
		return {"pass": false, "error": "expect_token_visible needs unit_id"}
	var timeout_s = float(step.get("timeout_s", 2.0))
	var deadline = Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		var token = _find_unit_token(unit_id)
		if token != null and (token.has_method("is_visible_in_tree") and token.is_visible_in_tree()):
			return {"pass": true}
		await get_tree().process_frame
	return {"pass": false, "error": "no visible token for %s within %ss" % [unit_id, str(timeout_s)]}


# ----------------------------------------------------------------------------
# Tier-A step types (added in T02 for design-guidelines tasks).
#
# These three step types let visual scenarios make falsifiable claims about
# state, rendered pixels, and the regression-baseline file. See
# tests/scenarios/visual/_schema.md.
# ----------------------------------------------------------------------------

func _do_execute_script(step: Dictionary) -> Dictionary:
	# Evaluate a GDScript expression and compare its result against
	# equals / not_equals / exists / expect_min / expect_max.
	#
	# The expression has access to:
	#   - autoloads by name (GameState, PhaseManager, RulesEngine, ...)
	#   - the helper `main` referring to /root/Main if present
	#
	# Example:
	#   { "act": "execute_script",
	#     "script": "MovementController.current_drag_segments[-1].color_slot",
	#     "equals": "MARGINAL_YELLOW" }
	var code: String = str(step.get("script", ""))
	if code == "":
		return {"pass": false, "error": "execute_script needs `script`"}

	# Build input name/value pairs:
	#   - every autoload child of /root (referenced by node name)
	#   - common engine singletons (Engine, OS, Time, Input, RenderingServer)
	#   - `main` -> the live battle scene root, if loaded
	var input_names: Array = []
	var input_values: Array = []
	var root := get_tree().root
	for child in root.get_children():
		input_names.append(child.name)
		input_values.append(child)
	# ResourceLoader/ClassDB let a scenario instantiate a script-backed node
	# (e.g. a dialog) for windowed validation: ResourceLoader.load(path).new().
	input_names.append_array(["Engine", "OS", "Time", "Input", "RenderingServer", "ProjectSettings", "ResourceLoader", "ClassDB", "main"])
	input_values.append_array([Engine, OS, Time, Input, RenderingServer, ProjectSettings, ResourceLoader, ClassDB, get_tree().current_scene])

	var expr := Expression.new()
	var parse_err := expr.parse(code, input_names)
	if parse_err != OK:
		return {"pass": false, "error": "parse failed: %s" % expr.get_error_text()}
	# Pass self as base instance so `self.foo` works and any singletons not in
	# input_names fall through to the runner's context.
	var actual = expr.execute(input_values, self, true)
	if expr.has_execute_failed():
		return {"pass": false, "error": "execute failed: %s" % expr.get_error_text()}

	# Tolerate "no expectation" — caller may just want to drive a side effect.
	if not (step.has("equals") or step.has("not_equals") or step.has("exists")
			or step.has("expect_min") or step.has("expect_max")):
		return {"pass": true, "actual": actual}

	# Numeric bounds
	if step.has("expect_min"):
		var lo = float(step["expect_min"])
		if typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
			var ok = float(actual) >= lo
			return {"pass": ok, "actual": actual, "expect_min": lo,
					"error": "" if ok else "expected >= %s, got %s" % [str(lo), str(actual)]}
		return {"pass": false, "error": "expect_min requires numeric actual, got %s" % typeof(actual)}
	if step.has("expect_max"):
		var hi = float(step["expect_max"])
		if typeof(actual) in [TYPE_INT, TYPE_FLOAT]:
			var ok2 = float(actual) <= hi
			return {"pass": ok2, "actual": actual, "expect_max": hi,
					"error": "" if ok2 else "expected <= %s, got %s" % [str(hi), str(actual)]}
		return {"pass": false, "error": "expect_max requires numeric actual, got %s" % typeof(actual)}

	# equals / not_equals / exists -> reuse _compare
	return _compare(step, actual, "script[%s]" % code.substr(0, 60))


func _do_pixel_diff(step: Dictionary) -> Dictionary:
	# Compare two previously-captured screenshots (by `label`, matching the
	# `screenshot` step's label argument). Optionally clipped to a named region
	# from the scenario-level `regions` dict.
	#
	# Example:
	#   { "act": "pixel_diff",
	#     "before": "T03_at_M", "after": "T03_at_advance",
	#     "region": "drag_path",
	#     "expect_min_pct": 3.0 }
	var before_label: String = str(step.get("before", ""))
	var after_label: String = str(step.get("after", ""))
	if before_label == "" or after_label == "":
		return {"pass": false, "error": "pixel_diff needs `before` and `after` labels"}

	var scenario_id: String = str(_scenario.get("id", "unnamed"))
	var before_rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, before_label]
	var after_rel := "%s/%s_%s.png" % [RESULTS_SUBDIR, scenario_id, after_label]
	var before_abs := ProjectSettings.globalize_path("user://" + before_rel)
	var after_abs := ProjectSettings.globalize_path("user://" + after_rel)

	# Optional region resolution against scenario-level dict
	var regions := {}
	if step.has("region"):
		var region_name: String = str(step["region"])
		var scenario_regions: Dictionary = _scenario.get("regions", {})
		if not scenario_regions.has(region_name):
			return {"pass": false, "error": "scenario has no region named '%s'" % region_name}
		regions[region_name] = scenario_regions[region_name]

	# Load the static utility class. Cannot use class_name PixelDiff here
	# without forcing it into the global namespace at parse time; load by path.
	var pd = load("res://tests/tools/pixel_diff.gd")
	if pd == null:
		return {"pass": false, "error": "could not load pixel_diff.gd"}
	var result: Dictionary = pd.diff(before_abs, after_abs, regions)
	if result.has("error"):
		return {"pass": false, "error": "pixel_diff: %s" % result["error"]}

	# Pick the pct to compare against: region if specified, else total
	var pct: float
	if step.has("region"):
		var region_name2: String = str(step["region"])
		var rr = result.get("regions", {}).get(region_name2, null)
		if typeof(rr) == TYPE_FLOAT or typeof(rr) == TYPE_INT:
			pct = float(rr)
		else:
			return {"pass": false, "error": "region '%s' diff failed: %s" % [region_name2, str(rr)]}
	else:
		pct = float(result.get("total_diff_pct", -1.0))

	# Always emit the diff to the results record so reviewers can see the
	# numbers without re-running.
	var record := {"pass": true, "diff_pct": pct, "result": result}

	if step.has("expect_min_pct"):
		var lo = float(step["expect_min_pct"])
		if pct < lo:
			record["pass"] = false
			record["error"] = "pixel_diff: expected >= %.2f%%, got %.2f%%" % [lo, pct]
	if step.has("expect_max_pct"):
		var hi = float(step["expect_max_pct"])
		if pct > hi:
			record["pass"] = false
			record["error"] = "pixel_diff: expected <= %.2f%%, got %.2f%%" % [hi, pct]
	if not (step.has("expect_min_pct") or step.has("expect_max_pct")):
		record["pass"] = false
		record["error"] = "pixel_diff needs expect_min_pct or expect_max_pct"
	return record


func _do_expect_baseline_unchanged(_step: Dictionary) -> Dictionary:
	# Asserts the regression baseline file exists and is non-empty. The
	# suite-level regression check (PASSED count >= baseline count) is
	# performed by run_scenarios.sh because it has cross-scenario visibility;
	# this step is the in-scenario sanity check that the baseline machinery is
	# wired up at all.
	var baseline_path := "res://tests/scenarios/visual/_baseline.json"
	var abs := ProjectSettings.globalize_path(baseline_path)
	if not FileAccess.file_exists(abs):
		return {"pass": false, "error": "baseline file missing: %s" % baseline_path}
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return {"pass": false, "error": "could not open baseline file"}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"pass": false, "error": "baseline JSON malformed"}
	var passing: Array = parsed.get("passing", [])
	var count: int = int(parsed.get("count", -1))
	if passing.is_empty() or count <= 0:
		return {"pass": false, "error": "baseline is empty (count=%d, passing=%d)" % [count, passing.size()]}
	if passing.size() != count:
		return {"pass": false, "error": "baseline count (%d) != passing array length (%d)" % [count, passing.size()]}
	return {"pass": true, "baseline_count": count}


# ============================================================================
# HELPERS
# ============================================================================

# Test invariant for the pile-in "ghost token" regression: the highest number of
# TokenLayer tokens that share the same (unit_id, model_id). 1 == healthy (every
# model has exactly one token); 2+ == duplicate/overlapping tokens, which an
# interactive pile-in/consolidate drag then splits into a moved token and a
# stranded "ghost" at the original spot. Duplicates arose when the async
# Main._recreate_unit_visuals() ran twice in one frame; a scenario asserts this
# stays 1 even after firing concurrent recreates. Size-independent, so it is
# robust to fixture changes. Callable from `execute_script` steps as a bare
# `max_tokens_per_model()` (the runner is the Expression base instance).
# Shape-aware minimum edge-to-edge distance (inches) between the alive models
# of two units, straight from GameState. Callable from `execute_script` steps
# as `min_edge_distance_between_units("U_A", "U_B")` — e.g. with expect_max 2.0
# to assert a completed charge really stands in engagement range.
func min_edge_distance_between_units(unit_a_id: String, unit_b_id: String) -> float:
	var units = GameState.state.get("units", {})
	var ua = units.get(unit_a_id, {})
	var ub = units.get(unit_b_id, {})
	var best := 9999.0
	for ma in ua.get("models", []):
		if not ma.get("alive", true) or ma.get("position") == null:
			continue
		for mb in ub.get("models", []):
			if not mb.get("alive", true) or mb.get("position") == null:
				continue
			best = min(best, Measurement.model_to_model_distance_inches(ma, mb))
	return best

# Count GameEventLog entries whose text contains `needle`. Callable from
# `execute_script` steps, e.g. `event_log_count_containing("charge move failed")`
# with equals 0 to assert a failure message never reached the player-facing log.
func event_log_count_containing(needle: String) -> int:
	var log_node := get_tree().root.get_node_or_null("GameEventLog")
	if log_node == null:
		return -1
	var n := 0
	for e in log_node.get_all_entries():
		if str(e.get("text", "")).find(needle) != -1:
			n += 1
	return n

# Width in px of the static top-down sprite resolved onto the first token of
# `unit_id`: -1 if no token exists, 0 if the token has no sprite (letter
# fallback). Callable from `execute_script` steps, e.g.
# unit_token_sprite_width("U_CUSTODIAN_GUARD_B") with equals 512 to assert the
# bundled Custodian Guard art landed on the board token.
func unit_token_sprite_width(unit_id: String) -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return -1
	var tl := scene.get_node_or_null("BoardRoot/TokenLayer")
	if tl == null:
		return -1
	for c in tl.get_children():
		if c.has_meta("unit_id") and str(c.get_meta("unit_id")) == unit_id:
			var tex = c._get_unit_sprite_texture()
			return tex.get_width() if tex != null else 0
	return -1

func token_model_rotation(unit_id: String, model_id: String) -> float:
	# Live rotation (radians) baked into a model's ON-SCREEN token, read
	# directly from its model_data — NOT GameState. Regression guard for the
	# charge-phase rotate bug: ChargeController's token-visual updaters reached
	# into child.get_child(0) assuming a wrapper node, but token_layer children
	# ARE the TokenVisual (get_child(0) was its "Label" child), so rotation
	# updates silently no-oped on the real token while the ghost still rotated.
	var tl := SceneRefs.token_layer()
	if tl == null:
		return -999.0
	for c in tl.get_children():
		if c.has_meta("unit_id") and str(c.get_meta("unit_id")) == unit_id \
				and c.has_meta("model_id") and str(c.get_meta("model_id")) == model_id:
			if "model_data" in c and c.model_data is Dictionary:
				return float(c.model_data.get("rotation", -999.0))
	return -999.0

func max_tokens_per_model() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return -1
	var tl := scene.get_node_or_null("BoardRoot/TokenLayer")
	if tl == null:
		return -1
	var counts := {}
	var mx := 0
	for c in tl.get_children():
		if c.has_meta("unit_id") and c.has_meta("model_id"):
			var k := "%s/%s" % [str(c.get_meta("unit_id")), str(c.get_meta("model_id"))]
			counts[k] = int(counts.get(k, 0)) + 1
			mx = max(mx, int(counts[k]))
	return mx

# Regression guard for the auto token-color bug: every SET of same-named units
# (same meta.name) belonging to `player` must end up with DISTINCT colors so two
# "Boyz" squads never render identically. Clears then re-runs
# auto_assign_unit_color for all of the player's units so it tests the
# assignment logic itself, not whatever colors the fixture was saved with (the
# old hex-roundtrip bug returned palette[0] for every unit). Callable from
# execute_script as same_name_colors_distinct(1) with equals true.
func same_name_colors_distinct(player: int) -> bool:
	GameState._ensure_unit_visuals()
	var by_name := {}
	for uid in GameState.state.get("units", {}):
		var u = GameState.state["units"][uid]
		if int(u.get("owner", 0)) != player:
			continue
		GameState.clear_unit_color(uid)
		var nm := str(u.get("meta", {}).get("name", ""))
		if not by_name.has(nm):
			by_name[nm] = []
		by_name[nm].append(uid)
	# Re-assign every one of the player's units (order = dict/id order).
	for uid in GameState.state.get("units", {}):
		if int(GameState.state["units"][uid].get("owner", 0)) == player:
			GameState.auto_assign_unit_color(uid)
	# Within each same-name group, colors must be unique.
	for nm in by_name:
		var ids: Array = by_name[nm]
		if ids.size() < 2:
			continue
		var seen := {}
		for uid in ids:
			var hex := GameState.get_unit_color(uid).to_html(false)
			if seen.has(hex):
				return false
			seen[hex] = true
	return true

# True when the first board token reports "ring" color-display mode — proves the
# SettingsService.unit_color_display_mode setting reaches TokenVisual. Callable
# from execute_script as first_token_ring_mode() with equals true/false.
func first_token_ring_mode() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var tl := scene.get_node_or_null("BoardRoot/TokenLayer")
	if tl == null:
		return false
	for c in tl.get_children():
		if c.has_method("_is_ring_color_mode"):
			return c._is_ring_color_mode()
	return false

# Set the unit color-display mode and return the resulting stored value so an
# execute_script step can both drive the toggle and assert it in one call:
# set_color_display_mode("ring") with equals "ring".
func set_color_display_mode(mode: String) -> String:
	SettingsService.set_unit_color_display_mode(mode)
	return SettingsService.unit_color_display_mode
# Whether the OptionButton at `node_path` carries an item whose metadata equals
# `metadata`. The Burden of Trust guard dropdown stores each candidate unit_id as
# its item metadata, so this asserts a specific unit is offered as a guard.
# Callable from `execute_script`, e.g.
# option_button_has_metadata("/root/GuardSelectionDialog/Content/ObjectiveScroll/ObjectiveRows/Row_obj_center/Guard_obj_center", "U_STRIKE_FORCE_A")
# with equals true to prove a unit that is NOT in range is still selectable.
func option_button_has_metadata(node_path: String, metadata: String) -> bool:
	var ob := get_tree().root.get_node_or_null(node_path)
	if ob == null or not (ob is OptionButton):
		return false
	for i in range(ob.item_count):
		if str(ob.get_item_metadata(i)) == metadata:
			return true
	return false

# The visible item text carrying `metadata` in the OptionButton at `node_path`
# ("" if absent). Lets a scenario assert the "(in range)" / "(embarked)"
# annotation the guard dropdown appends, e.g. checking it contains "in range".
func option_button_text_for_metadata(node_path: String, metadata: String) -> String:
	var ob := get_tree().root.get_node_or_null(node_path)
	if ob == null or not (ob is OptionButton):
		return ""
	for i in range(ob.item_count):
		if str(ob.get_item_metadata(i)) == metadata:
			return ob.get_item_text(i)
	return ""

func _send_click(screen_pos: Vector2) -> void:
	# Warp the live cursor to the target BEFORE injecting the event. GUI Controls
	# route by event position, but board/world handlers (e.g. DeploymentController
	# placement, token hit-testing) read get_viewport().get_mouse_position() — the
	# live cursor — so without the warp a board click acts on the OS cursor's spot
	# and no-ops. Round to a whole pixel: the OS cursor is integer, and
	# warp_mouse truncates, which at high zoom-out shifts the click by a board
	# unit per fractional pixel.
	screen_pos = screen_pos.round()
	Input.warp_mouse(screen_pos)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen_pos
	press.global_position = screen_pos
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen_pos
	release.global_position = screen_pos
	release.pressed = false
	release.button_mask = 0
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_unit_token(unit_id: String) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for r in [tree.current_scene, tree.root]:
		if r == null:
			continue
		var found := _search_node_by_unit_id(r, unit_id)
		if found:
			return found
	return null


func _search_node_by_unit_id(node: Node, unit_id: String) -> Node2D:
	if node is Node2D:
		var n2d := node as Node2D
		if n2d.name == unit_id:
			return n2d
		if "unit_id" in n2d and str(n2d.get("unit_id")) == unit_id:
			return n2d
		if n2d.has_meta("unit_id") and str(n2d.get_meta("unit_id")) == unit_id:
			return n2d
	for child in node.get_children():
		var found := _search_node_by_unit_id(child, unit_id)
		if found:
			return found
	return null


func _normalize_action_positions(action: Dictionary) -> Dictionary:
	# Mirror of wh40k_handlers._normalize_action_positions. Converts
	# JSON-shaped position fields ([x,y] / {x,y}) into Vector2.
	if typeof(action) != TYPE_DICTIONARY:
		return action
	var out: Dictionary = action.duplicate(true)
	for key in ["position", "destination", "dest", "target_position", "stage_position"]:
		if out.has(key):
			var v = _coerce_vector2(out[key])
			if v != null:
				out[key] = v
	if out.has("model_positions") and typeof(out["model_positions"]) == TYPE_ARRAY:
		var positions: Array = out["model_positions"]
		var converted: Array = []
		for p in positions:
			if p == null:
				converted.append(null)
			else:
				var v2 = _coerce_vector2(p)
				converted.append(v2 if v2 != null else p)
		out["model_positions"] = converted
	if out.has("payload") and typeof(out["payload"]) == TYPE_DICTIONARY:
		var payload: Dictionary = out["payload"]
		if payload.has("per_model_paths") and typeof(payload["per_model_paths"]) == TYPE_DICTIONARY:
			var paths: Dictionary = payload["per_model_paths"]
			var converted_paths: Dictionary = {}
			for model_id in paths:
				var p2 = paths[model_id]
				if typeof(p2) == TYPE_ARRAY:
					var converted_path: Array = []
					for q in p2:
						var v3 = _coerce_vector2(q)
						converted_path.append(v3 if v3 != null else q)
					converted_paths[model_id] = converted_path
				else:
					converted_paths[model_id] = p2
			payload["per_model_paths"] = converted_paths
			out["payload"] = payload
	return out


func _coerce_vector2(value):
	if typeof(value) == TYPE_VECTOR2:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		var x = value[0]
		var y = value[1]
		if (typeof(x) in [TYPE_INT, TYPE_FLOAT]) and (typeof(y) in [TYPE_INT, TYPE_FLOAT]):
			return Vector2(float(x), float(y))
	if typeof(value) == TYPE_DICTIONARY and value.has("x") and value.has("y"):
		var x2 = value["x"]
		var y2 = value["y"]
		if (typeof(x2) in [TYPE_INT, TYPE_FLOAT]) and (typeof(y2) in [TYPE_INT, TYPE_FLOAT]):
			return Vector2(float(x2), float(y2))
	return null


func _node2d_to_screen(node: Node2D) -> Vector2:
	# Board tokens live under Main's CanvasLayer, which IGNORES the Camera2D —
	# but viewport.get_canvas_transform() follows it, so the two can drift
	# apart mid-run. Project through the scene's own BoardRoot transform (the
	# exact lens every board input handler inverts) whenever possible.
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("world_to_screen_position"):
		var parent := node.get_parent()
		if parent != null and str(parent.name) == "TokenLayer":
			return scene.world_to_screen_position(node.position)
	var viewport := node.get_viewport()
	if viewport == null:
		return Vector2.INF
	var canvas_xform := viewport.get_canvas_transform()
	return canvas_xform * node.global_position


func _walk_path(root, path: String):
	# Dot-separated path. Accepts numeric segments for arrays.
	if path == "":
		return root
	var cur = root
	for seg in path.split("."):
		if cur == null:
			return null
		if typeof(cur) == TYPE_DICTIONARY:
			if cur.has(seg):
				cur = cur[seg]
			else:
				return null
		elif typeof(cur) == TYPE_ARRAY:
			var idx = seg.to_int()
			if idx < 0 or idx >= cur.size():
				return null
			cur = cur[idx]
		else:
			return null
	return cur


func _compare(step: Dictionary, actual, label: String) -> Dictionary:
	if step.has("equals"):
		var expected = step["equals"]
		var ok = _values_equal(actual, expected)
		return {"pass": ok, "label": label, "expected": expected, "actual": actual,
				"error": "" if ok else "%s: expected %s, got %s" % [label, str(expected), str(actual)]}
	if step.has("not_equals"):
		var expected2 = step["not_equals"]
		var ok2 = not _values_equal(actual, expected2)
		return {"pass": ok2, "label": label, "expected_not": expected2, "actual": actual,
				"error": "" if ok2 else "%s: expected NOT %s, got %s" % [label, str(expected2), str(actual)]}
	if step.has("exists"):
		var expected3: bool = bool(step["exists"])
		var got_exists: bool = actual != null
		var ok3 = got_exists == expected3
		return {"pass": ok3, "label": label, "expected_exists": expected3, "actual": actual,
				"error": "" if ok3 else "%s: expected exists=%s, got actual=%s" % [label, str(expected3), str(actual)]}
	return {"pass": false, "error": "%s: no expectation specified (equals|not_equals|exists)" % label}


func _values_equal(a, b) -> bool:
	# Loose comparison: int/float widen; str is exact; arrays/dicts deep
	if typeof(a) == typeof(b):
		return a == b
	if (typeof(a) in [TYPE_INT, TYPE_FLOAT]) and (typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		return float(a) == float(b)
	# String<->Bool: tolerate "true"/"false" comparisons
	if typeof(a) == TYPE_STRING and typeof(b) == TYPE_BOOL:
		return a == str(b)
	if typeof(a) == TYPE_BOOL and typeof(b) == TYPE_STRING:
		return str(a) == b
	return false


func _capture_cp_snapshot() -> Dictionary:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return {}
	var out := {}
	var players = gs.state.get("players", {})
	for pid in players:
		out[str(pid)] = players[pid].get("cp", 0)
	return out


func _summarize_result(result) -> Variant:
	# Truncate large dicts so the results JSON stays readable
	if typeof(result) == TYPE_DICTIONARY:
		var summary := {}
		for k in result.keys():
			var v = result[k]
			if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
				summary[k] = "<%s len=%d>" % ["dict" if typeof(v) == TYPE_DICTIONARY else "array", v.size()]
			else:
				summary[k] = v
		return summary
	return result


func _dry_run_resolve_step(i: int, act: String, step: Dictionary) -> Dictionary:
	# Selector dry-run: resolve any node-path / unit-id selectors in this
	# step without performing the action. Steps without selectors get
	# selector_status = 'n/a' and pass automatically. Steps with a
	# selector that fails to resolve get pass=false + selector_status =
	# 'not_found'. The driver halts the loop when any selector is missing.
	var rec := {"step": i, "act": act, "step_input": step}
	match act:
		"click_node", "expect_node_visible", "expect_node_property":
			var node_path := str(step.get("node", ""))
			rec["selector_kind"] = "node_path"
			rec["selector_value"] = node_path
			if node_path == "":
				rec["pass"] = false
				rec["selector_status"] = "not_found"
				rec["error"] = "%s step missing 'node' field" % act
			elif get_node_or_null(node_path) == null:
				rec["pass"] = false
				rec["selector_status"] = "not_found"
				rec["error"] = "no node at path %s" % node_path
			else:
				rec["pass"] = true
				rec["selector_status"] = "resolved"
		"click_unit", "expect_token_visible":
			var unit_id := str(step.get("unit_id", ""))
			rec["selector_kind"] = "unit_id"
			rec["selector_value"] = unit_id
			if unit_id == "":
				rec["pass"] = false
				rec["selector_status"] = "not_found"
				rec["error"] = "%s step missing 'unit_id' field" % act
			elif _find_unit_token(unit_id) == null:
				rec["pass"] = false
				rec["selector_status"] = "not_found"
				rec["error"] = "no token found for unit %s" % unit_id
			else:
				rec["pass"] = true
				rec["selector_status"] = "resolved"
		_:
			rec["pass"] = true
			rec["selector_status"] = "n/a"
	return rec


func _write_selectors_report(scenario_id: String, passed: int, failed: int) -> void:
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	var rel := "%s/%s_selectors_report.json" % [RESULTS_SUBDIR, scenario_id]
	var abs := ProjectSettings.globalize_path("user://" + rel)
	var f = FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		print("[ScenarioRunner] could not write selectors_report: %s" % abs)
		return
	# Project just the selector-relevant fields, keep the file small.
	var rows := []
	var resolved := 0
	var not_found := 0
	var na := 0
	for r in _step_results:
		rows.append({
			"step": r.get("step"),
			"act": r.get("act"),
			"selector_status": r.get("selector_status", "n/a"),
			"selector_kind": r.get("selector_kind", null),
			"selector_value": r.get("selector_value", null),
			"error": r.get("error", null),
		})
		match r.get("selector_status", "n/a"):
			"resolved": resolved += 1
			"not_found": not_found += 1
			_: na += 1
	var out := {
		"scenario_id": scenario_id,
		"mode": "selector_dry_run",
		"summary": {"resolved": resolved, "not_found": not_found, "n/a": na},
		"steps": rows,
	}
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[ScenarioRunner] selectors_report: %s  (resolved=%d not_found=%d n/a=%d)" % [abs, resolved, not_found, na])


func _capture_per_step_screenshot(scenario_id: String, step_idx: int, act: String) -> String:
	# Returns the relative-to-user:// path of the screenshot, or "" on failure.
	# Named files are zero-padded so an alpha sort matches step order.
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return ""
	var img := vp.get_texture().get_image()
	if img == null:
		return ""
	var safe_act := act if act != "" else "noop"
	var rel := "%s/%s_step_%02d_%s.png" % [RESULTS_SUBDIR, scenario_id, step_idx, safe_act]
	var abs := ProjectSettings.globalize_path("user://" + rel)
	var err := img.save_png(abs)
	if err != OK:
		print("[ScenarioRunner] per-step screenshot save failed (%d): %s" % [err, abs])
		return ""
	return rel


func _capture_failure_screenshot(scenario_id: String, step_idx: int) -> void:
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	var rel = "%s/%s_FAIL_step_%d.png" % [RESULTS_SUBDIR, scenario_id, step_idx]
	var abs = ProjectSettings.globalize_path("user://" + rel)
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	img.save_png(abs)
	print("[ScenarioRunner] failure screenshot: %s" % abs)


func _write_results(scenario_id: String, passed: int, failed: int) -> void:
	var d = DirAccess.open("user://")
	if d != null:
		d.make_dir_recursive(RESULTS_SUBDIR)
	var rel = "%s/%s.json" % [RESULTS_SUBDIR, scenario_id]
	var abs = ProjectSettings.globalize_path("user://" + rel)
	var f = FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		print("[ScenarioRunner] could not open results file: %s" % abs)
		return
	var out := {
		"scenario_id": scenario_id,
		"passed": passed,
		"failed": failed,
		"total_steps": _step_results.size(),
		"steps": _step_results,
	}
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[ScenarioRunner] results written: %s" % abs)


func _fail_and_quit(reason: String) -> void:
	print("[ScenarioRunner] FATAL: %s" % reason)
	get_tree().quit(2)
