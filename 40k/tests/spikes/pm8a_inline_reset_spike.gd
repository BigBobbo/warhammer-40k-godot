extends SceneTree

# PM-8a SPIKE — can this build run two consecutive from-menu AI-vs-AI games in
# ONE process, with a clean state reset between them?
#
# This is the load-bearing unknown of the whole simulator (PM-8b/PM-9):
# AIBenchmarkRunner is one-game-per-process BY DESIGN (cmdline-gated at :95-97,
# fixture-only at :274-277, and it quits on every exit path via _write_and_quit
# at :606-618), and no production code performs an in-session multi-game reset.
# Subprocess-per-game is not an acceptable answer — the only precedent
# (tests/helpers/GameInstance.gd:104) has documented autoload-init flakiness and
# is impossible on the web export.
#
# What it does, per game:
#   bootstrap (mirrors MainMenu._initialize_game_with_config, MainMenu.gd:1499-1591)
#   -> seed the triple -> change_scene into Main.tscn -> let the AI play it out
#      under a wall-clock cap and a stall detector.
#
# The interesting part is BETWEEN the games. It probes autoload state at four
# points, so the report can say exactly which fields the bootstrap alone leaves
# dirty — that difference IS the reset list PM-8b must implement:
#   A after game 1 ends
#   B after the game-2 bootstrap, BEFORE any explicit reset
#   C after the candidate explicit resets
#   D at game 2's first live frame
#
# Run with:
#   godot --headless --path . -s tests/spikes/pm8a_inline_reset_spike.gd
# Writes:  user://pm8a_spike_result.json
#
# NOT part of run_pretrigger_tests.sh — it plays whole games and takes minutes.

# NOTE — no preloads here, deliberately. Preloading res://autoloads/GameState.gd
# from a `-s` script emits, at boot:
#   Compile Error: Identifier not found: Measurement  (DeploymentZoneData.gd:61)
#   Compile Error: Identifier not found: GameState    (FactionPalettes.gd:202)
# because autoload identifiers do not resolve while the `-s` script and its
# preload graph are compiled (autoloads enter the tree afterwards). Everything
# here goes through root.get_node_or_null() / load() at run time instead.

# Smallest shipped Custodes list (3 units / 6 models / 370 pts) so two full
# games fit in a few minutes. Same list both seats, which also exercises the
# `_P2` unit re-key that every mirror match produces.
const ARMY := "A_C_test"
const DEPLOYMENT := "crucible_of_battle"
const TERRAIN := "take_and_hold_mirror_1"
const MISSION := "take_and_hold"
const DIFFICULTY := 1  # Normal — the shipped default

# Three games, seeded [S, S+1, S]. Game 3 repeats game 1's seed: if in-session
# reset is clean enough for the simulator, games 1 and 3 must produce identical
# outcomes. That is a far stronger claim than "two games both finished".
const GAMES := 3
const SEED_BASE := 8100
const TIME_SCALE := 10.0
const MAX_SECONDS_PER_GAME := 480.0
const STALL_SECONDS := 90.0

const OUT_PATH := "user://pm8a_spike_result.json"

var _probes: Array = []
var _games: Array = []
var _notes: Array = []

# Env overrides so the same driver can run the control experiments:
#   PM8A_GAMES=1 PM8A_SEEDS=8100  -> one game per process, for a cross-process
#                                     same-seed comparison
#   PM8A_TIME_SCALE=1             -> is the divergence pacing-dependent?
#   PM8A_OUT=user://foo.json      -> where to write the result
var _games_count: int = GAMES
var _seeds: Array = []
var _time_scale: float = TIME_SCALE
var _out_path: String = OUT_PATH

func _read_env() -> void:
	var g := OS.get_environment("PM8A_GAMES")
	if not g.is_empty():
		_games_count = maxi(1, int(g))
	var s := OS.get_environment("PM8A_SEEDS")
	if not s.is_empty():
		for token in s.split(","):
			_seeds.append(int(token.strip_edges()))
	var ts := OS.get_environment("PM8A_TIME_SCALE")
	if not ts.is_empty():
		_time_scale = maxf(1.0, float(ts))
	var out := OS.get_environment("PM8A_OUT")
	if not out.is_empty():
		_out_path = out

func _init():
	# Autoloads are not in the tree yet during a `-s` script's _init().
	create_timer(0.2).timeout.connect(_run)

func _run() -> void:
	_read_env()
	print("\n=== PM-8a spike: %d back-to-back in-session AI games (time_scale %.1f) ===\n" % [_games_count, _time_scale])
	Engine.time_scale = _time_scale

	for i in range(_games_count):
		if i > 0:
			_probe("A_after_game_%d" % i)
		# Order matters: stand the AI down, clear the autoloads, and ONLY THEN
		# build the new game. Resetting after the bootstrap wipes state the
		# bootstrap just populated (StratagemManager.reset_for_new_game clears
		# the faction stratagems that applying the armies had loaded).
		_quiesce_ai()
		_apply_candidate_resets()
		_probe("B_after_resets_game_%d" % (i + 1))
		_bootstrap(i)
		_probe("C_after_explicit_resets_game_%d" % (i + 1))

		await _enter_main_scene()
		_probe("D_game_%d_first_frame" % (i + 1))
		var outcome = await _watch_game(i)
		_games.append(outcome)
		print("[PM8a] game %d: %s" % [i + 1, JSON.stringify(outcome)])

	_probe("A_after_game_%d" % _games_count)
	Engine.time_scale = 1.0
	_write_result()
	quit(0)

# ---------------------------------------------------------------------------
# Bootstrap — mirrors MainMenu._initialize_game_with_config (MainMenu.gd:1499-1591)
# ---------------------------------------------------------------------------

func _seed_for(game_index: int) -> int:
	if not _seeds.is_empty():
		return int(_seeds[game_index % _seeds.size()])
	# Game 3 deliberately repeats game 1's seed.
	return SEED_BASE + (0 if game_index == 2 else game_index)

func _config() -> Dictionary:
	return {
		"terrain": TERRAIN,
		"mission": MISSION,
		"deployment": DEPLOYMENT,
		"player1_army": ARMY,
		"player2_army": ARMY,
		"player1_type": "AI",
		"player2_type": "AI",
		"player1_difficulty": DIFFICULTY,
		"player2_difficulty": DIFFICULTY,
		"ai_speed": 0,
		"player1_secondary_mode": "tactical",
		"player2_secondary_mode": "tactical",
		"player1_fixed_missions": [],
		"player2_fixed_missions": [],
		"player1_disposition": "",
		"player2_disposition": "",
		"player1_name": "",
		"player2_name": "",
	}

func _quiesce_ai() -> void:
	"""Stand the AI down BEFORE the game is torn down and rebuilt.

	Between games the AIPlayer autoload is still `enabled` with
	`_needs_evaluation`/`_ai_thinking` set, so it keeps acting while the new
	game is being assembled and during the scene change — and then Main's
	configure() wipes `_action_log`, hiding the fact that it did. Configuring
	both seats HUMAN clears every accumulator (AIPlayer.gd:256-302) and sets
	`enabled = false`; Main._initialize_ai_player() turns the AI back on once
	the new scene is ready."""
	var ai = root.get_node_or_null("AIPlayer")
	if ai != null:
		ai.configure({1: "HUMAN", 2: "HUMAN"})
		print("[PM8a] AI quiesced before rebuild (enabled=%s)" % ai.enabled)

func _bootstrap(game_index: int) -> void:
	var config := _config()
	var gs = root.get_node_or_null("GameState")
	var terrain = root.get_node_or_null("TerrainManager")
	var board = root.get_node_or_null("BoardState")
	var mission = root.get_node_or_null("MissionManager")
	var armies = root.get_node_or_null("ArmyListManager")
	var secondary = root.get_node_or_null("SecondaryMissionManager")

	gs.state.clear()
	gs.initialize_default_state(config.deployment)
	gs.state.meta["game_config"] = config

	if terrain != null:
		terrain.current_layout = config.terrain
		terrain.load_terrain_layout(config.terrain)
	if board != null:
		board.initialize_deployment_zones(config.deployment)
	if mission != null:
		mission.initialize_mission(config.mission)

	gs.state.units.clear()
	if armies != null:
		for player in [1, 2]:
			var army = armies.load_army_for_game(config["player%d_army" % player], player)
			if army.is_empty():
				_notes.append("game %d: army '%s' failed to load for player %d" % [game_index + 1, config["player%d_army" % player], player])
			else:
				armies.apply_army_to_game_state(army, player)
	if secondary != null:
		secondary.initialize_for_game()

	gs.state.meta["game_config"] = config
	gs.state.meta["from_menu"] = true

	# Deterministic dice, secondary deck and AI RNG (the seeding triple).
	var game_seed := _seed_for(game_index)
	if true:
		# Fourth channel: GDScript's GLOBAL RNG, which Array.shuffle(), randi(),
		# randf() and randi_range() all draw from. It starts from a fixed
		# default in a fresh process — which is why two separate processes agree
		# on the same seed — but its state carries over between in-session
		# games, so game 2 draws a different sequence from the same "seed".
		seed(game_seed)
	var rules = root.get_node_or_null("RulesEngine")
	if rules != null:
		rules.set_test_seed(game_seed)
	if secondary != null and secondary.has_method("set_test_seed"):
		secondary.set_test_seed(game_seed)
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var ai_seeded := false
	if AIDM != null:
		AIDM.set_ai_seed(game_seed)
		ai_seeded = AIDM.is_ai_seeded()
	if not ai_seeded:
		_notes.append("game %d: AIDecisionMaker.set_ai_seed did NOT take effect" % (game_index + 1))
	print("[PM8a] bootstrapped game %d (seed %d, %d units, ai_seeded=%s)" % [
		game_index + 1, game_seed, gs.state.units.size(), ai_seeded])

func _apply_candidate_resets() -> void:
	"""The candidate between-games reset list from the task text. Whether each
	entry is actually NEEDED is what probes B vs C answer."""
	var strat = root.get_node_or_null("StratagemManager")
	if strat != null and strat.has_method("reset_for_new_game"):
		strat.reset_for_new_game()
	var abilities = root.get_node_or_null("UnitAbilityManager")
	if abilities != null and abilities.has_method("reset_for_new_game"):
		abilities.reset_for_new_game()
	var pm = root.get_node_or_null("PhaseManager")
	if pm != null:
		pm.reset()
	_apply_extra_resets()

func _apply_extra_resets() -> void:
	"""Resets BEYOND the task text's candidate list, each added because a probe
	or an action-trace diff showed it leaking between games."""
	# 1. Autoloads holding per-game state with NO reset entry point at all.
	var fam = root.get_node_or_null("FactionAbilityManager")
	if fam != null:
		# Fixed-shape {"1": .., "2": ..} dictionaries: their SIZE never changes,
		# so the size fingerprint cannot see these leak — the action trace did.
		# Game 2 skipped SELECT_MARTIAL_MASTERY because _active_mastery /
		# _mastery_selected_round still held game 1's values.
		fam._active_effects = {"1": {}, "2": {}}
		fam._player_abilities = {"1": [], "2": []}
		fam._waaagh_used = {"1": false, "2": false}
		fam._waaagh_active = {"1": false, "2": false}
		fam._boss_watchin_used = {"1": false, "2": false}
		fam._plant_waaagh_banner_used = {}
		fam._player_detachment = {"1": "", "2": ""}
		fam._doctrines_used = {"1": [], "2": []}
		fam._active_doctrine = {"1": "", "2": ""}
		fam._active_mastery = {"1": "", "2": ""}
		fam._mastery_selected_round = {"1": 0, "2": 0}
		fam._loot_objective = {"1": "", "2": ""}
		fam._loot_objective_round = {"1": 0, "2": 0}
		fam._da_kaptin_used_round = {"1": 0, "2": 0}
		fam._bionik_workshop_results = {}
		fam._bionik_workshop_resolved = false
		fam._razgit_redeploys_used = {"1": 0, "2": 0}
		fam._razgit_resolved = false
		fam._morks_kunnin_redeploys_used = {"1": 0, "2": 0}
		fam._aao_status = {}

	# 2. Log/record accumulators: unbounded growth across a long run, and
	#    ActionLogger/GameEventLog feed AI-visible context.
	var action_logger = root.get_node_or_null("ActionLogger")
	if action_logger != null and action_logger.has_method("_initialize_session"):
		action_logger.action_sequence = 0
		action_logger.session_actions.clear()
		action_logger.initial_snapshot = {}
		action_logger._initialize_session()
	var event_log = root.get_node_or_null("GameEventLog")
	if event_log != null:
		event_log.entries.clear()
	var replay = root.get_node_or_null("ReplayManager")
	if replay != null and replay.has_method("stop_recording"):
		replay.stop_recording()

	# 3. Fields the existing reset entry points miss.
	var pm = root.get_node_or_null("PhaseManager")
	if pm != null:
		pm._last_round_started = -1
	var mission = root.get_node_or_null("MissionManager")
	if mission != null:
		mission._units_alive_at_round_start.clear()
		# Main._setup_objectives() connects lambdas CAPTURING scene nodes to
		# these autoload signals (Main.gd:5186-5191). The connections outlive
		# the scene, so each game adds N more receivers that then fire on freed
		# objects ("Lambda capture at index 1 was freed", 35 of them in game 2).
		var dropped := 0
		for sig_name in ["objective_control_changed", "objective_removed"]:
			if not mission.has_signal(sig_name):
				continue
			for conn in mission.get_signal_connection_list(sig_name):
				var callable: Callable = conn["callable"]
				var target = callable.get_object()
				# A freed receiver auto-disconnects, but a LAMBDA does not: its
				# bound object outlives the scene while its captures do not, so
				# is_instance_valid(target) is still true and Godot keeps
				# calling it. Drop every lambda receiver — Main._setup_objectives
				# re-creates them for the new scene. Named-method connections
				# from live autoloads are left alone.
				if callable.is_custom() or target == null or not is_instance_valid(target):
					mission.disconnect(sig_name, callable)
					dropped += 1
		mission.objectives_visual_refs.clear()
		if dropped > 0:
			print("[PM8a] dropped %d dead MissionManager signal connection(s)" % dropped)

func _enter_main_scene() -> void:
	change_scene_to_file("res://scenes/Main.tscn")
	var waited := 0
	while waited < 600 and (current_scene == null or not current_scene.is_node_ready()):
		await process_frame
		waited += 1
	for i in range(8):
		await process_frame
	# The AI seats are configured by Main._initialize_ai_player() from
	# meta.game_config; make sure the pacing is the fastest preset and that the
	# decision-record ring is big enough not to drop the deployment batch
	# (AIBenchmarkRunner.gd:324-326 raises it for the same reason).
	var ai = root.get_node_or_null("AIPlayer")
	if ai != null:
		if ai.has_method("set_ai_speed_preset"):
			ai.set_ai_speed_preset(0)
		ai._max_decision_record_batches = 100000

# ---------------------------------------------------------------------------
# Watch
# ---------------------------------------------------------------------------

func _watch_game(game_index: int) -> Dictionary:
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var ai = root.get_node_or_null("AIPlayer")
	var mission = root.get_node_or_null("MissionManager")
	var start_ticks := Time.get_ticks_msec()
	var last_sig := ""
	var last_progress := start_ticks
	var status := "unknown"
	var note := ""

	while true:
		await create_timer(0.5).timeout
		var elapsed := (Time.get_ticks_msec() - start_ticks) / 1000.0
		if pm != null and pm.game_ended:
			status = "completed"
			break
		if elapsed > MAX_SECONDS_PER_GAME:
			status = "timeout"
			note = "max_seconds %.0f exceeded at round %d" % [MAX_SECONDS_PER_GAME, gs.get_battle_round()]
			break
		var sig := "%d|%d|%d" % [gs.get_battle_round(), gs.get_current_phase(),
			ai._action_log.size() if ai != null else 0]
		if sig != last_sig:
			last_sig = sig
			last_progress = Time.get_ticks_msec()
			print("[PM8a] g%d %6.1fs round=%d phase=%d actions=%d" % [
				game_index + 1, elapsed, gs.get_battle_round(), gs.get_current_phase(),
				ai._action_log.size() if ai != null else 0])
		elif (Time.get_ticks_msec() - last_progress) / 1000.0 > STALL_SECONDS:
			status = "stalled"
			note = "no progress for %.0fs at %s" % [STALL_SECONDS, sig]
			break

	var vp = mission.get_vp_summary() if mission != null else {}
	# Compact prefix of the AI's own action log, so two same-seed games can be
	# diffed to the EXACT action where they diverge.
	var trace: Array = []
	if ai != null:
		for i in range(mini(60, ai._action_log.size())):
			var e = ai._action_log[i]
			if e is Dictionary:
				trace.append("%s|%s|%s" % [str(e.get("player", "")), str(e.get("action_type", e.get("type", ""))), str(e.get("unit_id", e.get("unit", "")))])
			else:
				trace.append(str(e))
	return {
		"game": game_index + 1,
		"action_trace": trace,
		"seed": _seed_for(game_index),
		"status": status,
		"note": note,
		"battle_round": gs.get_battle_round(),
		"phase": gs.get_current_phase(),
		"actions": ai._action_log.size() if ai != null else 0,
		"vp_p1": int(vp.get("player1", {}).get("total", 0)),
		"vp_p2": int(vp.get("player2", {}).get("total", 0)),
		"wall_seconds": (Time.get_ticks_msec() - start_ticks) / 1000.0,
	}

# ---------------------------------------------------------------------------
# State probe
# ---------------------------------------------------------------------------

func _probe(label: String) -> void:
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var ai = root.get_node_or_null("AIPlayer")
	var strat = root.get_node_or_null("StratagemManager")
	var abilities = root.get_node_or_null("UnitAbilityManager")
	var mission = root.get_node_or_null("MissionManager")
	var secondary = root.get_node_or_null("SecondaryMissionManager")

	var p1_units := 0
	var p2_units := 0
	for unit_id in gs.state.get("units", {}).keys():
		var owner := int(gs.state["units"][unit_id].get("owner", 0))
		if owner == 1:
			p1_units += 1
		elif owner == 2:
			p2_units += 1

	var vp = mission.get_vp_summary() if mission != null else {}
	var AIDM = load("res://scripts/AIDecisionMaker.gd")
	var probe := {
		"label": label,
		"ai_seeded": AIDM.is_ai_seeded() if AIDM != null else null,
		# Main._setup_objectives() connects a lambda CAPTURING each
		# ObjectiveVisual node to this autoload signal (Main.gd:5186-5191).
		# The connections outlive the scene, so this count is the leak meter.
		"mission_control_changed_connections": mission.objective_control_changed.get_connections().size() if mission != null else -1,
		"mission_objective_visual_refs": mission.objectives_visual_refs.size() if mission != null else -1,
		"units_total": gs.state.get("units", {}).size(),
		"units_p1": p1_units,
		"units_p2": p2_units,
		"battle_round": gs.state.get("meta", {}).get("battle_round", 0),
		"phase": gs.state.get("meta", {}).get("phase", -1),
		"phase_log_len": gs.state.get("phase_log", []).size(),
		"phasemanager_game_ended": pm.game_ended if pm != null else null,
		"phasemanager_has_phase_instance": (pm != null and pm.current_phase_instance != null),
		"strat_usage_p1": strat._usage_history.get("1", []).size() if strat != null else -1,
		"strat_usage_p2": strat._usage_history.get("2", []).size() if strat != null else -1,
		"strat_active_effects": strat.active_effects.size() if strat != null else -1,
		"ability_once_per_battle": abilities._once_per_battle_used.size() if abilities != null else -1,
		"ability_once_per_round": abilities._once_per_round_used.size() if abilities != null else -1,
		"ability_active_effects": abilities._active_ability_effects.size() if abilities != null else -1,
		"ability_active_auras": abilities._active_aura_effects.size() if abilities != null else -1,
		"ai_action_log": ai._action_log.size() if ai != null else -1,
		"ai_decision_records": ai._all_decision_records.size() if ai != null else -1,
		"ai_turn_history": ai._turn_history.size() if ai != null else -1,
		"vp_p1": int(vp.get("player1", {}).get("total", 0)),
		"vp_p2": int(vp.get("player2", {}).get("total", 0)),
		"secondary_state_keys": secondary.get_save_data().size() if (secondary != null and secondary.has_method("get_save_data")) else -1,
	}
	probe["autoloads"] = _autoload_fingerprint()
	_probes.append(probe)
	var printable := probe.duplicate()
	printable.erase("autoloads")
	print("[PM8a] PROBE %s: %s" % [label, JSON.stringify(printable)])

const FINGERPRINT_AUTOLOADS := [
	"GameState", "PhaseManager", "TurnManager", "MissionManager",
	"SecondaryMissionManager", "StratagemManager", "UnitAbilityManager",
	"FactionAbilityManager", "CharacterAttachmentManager", "TransportManager",
	"TerrainManager", "AIPlayer", "GameEventLog", "ActionLogger",
	"ReplayManager", "RulesEngine", "BoardState",
]

func _autoload_fingerprint() -> Dictionary:
	"""Size/value of every script-declared Array, Dictionary, bool and int on the
	autoloads that carry per-game state.

	Diffing this between two games' identical bootstrap points is a systematic
	way to find leaked state, instead of guessing which resets are needed."""
	var out := {}
	for autoload_name in FINGERPRINT_AUTOLOADS:
		var node = root.get_node_or_null(autoload_name)
		if node == null:
			continue
		for prop in node.get_property_list():
			if not (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var prop_name: String = str(prop["name"])
			var value = node.get(prop_name)
			var key := "%s.%s" % [autoload_name, prop_name]
			match typeof(value):
				TYPE_ARRAY, TYPE_DICTIONARY:
					out[key] = value.size()
				TYPE_BOOL, TYPE_INT:
					out[key] = value
				TYPE_STRING:
					out[key] = value
	return out

func _probe_by_label(label: String) -> Dictionary:
	for p in _probes:
		if str(p["label"]) == label:
			return p
	return {}

func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a.keys():
		if k == "label":
			continue
		if not b.has(k):
			continue
		if a[k] != b[k]:
			out[k] = [a[k], b[k]]
	return out

func _write_result() -> void:
	var after_g1 := _probe_by_label("A_after_game_1")
	var after_bootstrap := _probe_by_label("B_after_resets_game_2")
	var after_resets := _probe_by_label("C_after_explicit_resets_game_2")
	var g1_start := _probe_by_label("D_game_1_first_frame")
	var g2_start := _probe_by_label("D_game_2_first_frame")

	# Games 1 and 3 share a seed. If the in-session reset is clean enough for a
	# simulator, they must produce identical outcomes.
	var determinism := {}
	if _games.size() >= 2:
		var g1: Dictionary = _games[0]
		var g3: Dictionary = _games[_games.size() - 1]
		var fields := ["status", "battle_round", "actions", "vp_p1", "vp_p2"]
		var t1: Array = g1.get("action_trace", [])
		var t3: Array = g3.get("action_trace", [])
		var first_divergence := -1
		for i in range(mini(t1.size(), t3.size())):
			if t1[i] != t3[i]:
				first_divergence = i
				break
		var mismatches := {}
		for f in fields:
			if g1.get(f) != g3.get(f):
				mismatches[f] = [g1.get(f), g3.get(f)]
		determinism = {
			"same_seed": g1.get("seed") == g3.get("seed"),
			"identical": mismatches.is_empty(),
			"mismatches": mismatches,
			"first_action_divergence_index": first_divergence,
			"trace_a_at_divergence": t1.slice(maxi(0, first_divergence - 2), first_divergence + 3) if first_divergence >= 0 else [],
			"trace_b_at_divergence": t3.slice(maxi(0, first_divergence - 2), first_divergence + 3) if first_divergence >= 0 else [],
		}

	var result := {
		"driver": "40k/tests/spikes/pm8a_inline_reset_spike.gd",
		"games_count": _games_count,
		"time_scale": _time_scale,
		"determinism_game1_vs_game3": determinism,
		"army": ARMY,
		"deployment": DEPLOYMENT,
		"terrain": TERRAIN,
		"mission": MISSION,
		"difficulty": DIFFICULTY,
		"games": _games,
		"probes": _probes,
		"notes": _notes,
		"diffs": {
			"end_of_game1_vs_after_bootstrap": _diff(after_g1, after_bootstrap),
			"after_bootstrap_vs_after_explicit_resets": _diff(after_bootstrap, after_resets),
			"game1_start_vs_game2_start": _diff(g1_start, g2_start),
		},
		"leaked_autoload_state_at_identical_bootstrap_points": _diff(
			_probe_by_label("C_after_explicit_resets_game_1").get("autoloads", {}),
			_probe_by_label("C_after_explicit_resets_game_2").get("autoloads", {})),
		"leaked_autoload_state_at_first_live_frame": _diff(
			g1_start.get("autoloads", {}), g2_start.get("autoloads", {})),
	}
	var f = FileAccess.open(_out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	print("\n[PM8a] ===== SPIKE RESULT =====")
	print(JSON.stringify(result, "  "))
	print("[PM8a] written: %s" % ProjectSettings.globalize_path(_out_path))
