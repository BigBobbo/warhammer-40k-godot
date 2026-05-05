extends SceneTree

# T5-MP5: Real-time dice log sync to remote player during shooting resolution.
#
# The active player's `ShootingPhase` emits `dice_rolled(dice_block)` signals
# locally so the dice log UI updates immediately. The remote player's only
# window into those rolls is `NetworkManager._emit_client_visual_updates`,
# which reads `result["dice"]` from the broadcast payload and re-emits each
# block on the local phase instance.
#
# Therefore the contract this test enforces is:
#
#   For every ShootingPhase action that emits `dice_rolled` locally, the
#   matching dice block MUST also appear in the result returned from
#   `process_action`, under the `dice` key — otherwise the remote peer's
#   dice log silently desyncs.
#
# This test does NOT spin up two real Godot peers (single-process headless
# limitation). Instead it covers the broadcast pipeline at the dictionary /
# signal level:
#
#   1. NetworkManager._emit_client_visual_updates correctly re-emits every
#      dice block from a synthetic broadcast result onto the active phase.
#   2. ShootingPhase methods that emit `dice_rolled` ALSO bundle the same
#      block into their result["dice"] payload.
#
# The second slice catches the actual pre-fix bugs:
#   - Grenade stratagem (`_process_use_grenade_stratagem`) used to emit
#     dice locally without including them in result["dice"].
#   - FNP and Hazardous dice blocks emitted from `_process_apply_saves`
#     used to be appended to `dice_log` but NOT to `save_dice_blocks`,
#     which is the array bundled into result["dice"].
#
# Usage: godot --headless --path . -s tests/test_dice_broadcast_sync.gd

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
	print("\n=== test_dice_broadcast_sync ===\n")

	_test_network_reemits_dice_blocks_to_remote_phase()
	_test_grenade_action_includes_dice_in_result()
	_test_resolve_shooting_path_prepends_resolution_start_to_dice()
	_test_apply_saves_collects_fnp_into_save_dice_blocks()

	_finish()

# ---------------------------------------------------------------------------
# 1. NetworkManager re-emission contract — verifies the remote peer side.
#
# We swap the PhaseManager's current_phase_instance for a fresh ShootingPhase,
# connect to its dice_rolled signal, hand a synthetic broadcast result with a
# dice array to NetworkManager._emit_client_visual_updates, and assert each
# block is re-emitted in order.
# ---------------------------------------------------------------------------
func _test_network_reemits_dice_blocks_to_remote_phase() -> void:
	print("\n-- NetworkManager re-emits result[\"dice\"] blocks on remote phase --")

	var phase_manager = root.get_node("PhaseManager")
	var network_manager = root.get_node("NetworkManager")

	# Save and replace current_phase_instance so we don't disturb whatever
	# the autoloads booted with.
	var prior_phase = phase_manager.current_phase_instance
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	phase_manager.add_child(phase)
	phase_manager.current_phase_instance = phase

	# Capture every dice_rolled emission.
	var captured = []
	var capture := func(dice_block):
		captured.append(dice_block)
	phase.dice_rolled.connect(capture)

	# Synthetic broadcast result that simulates what the host would send the
	# client after a single-weapon shoot. The two contexts that used to break
	# pre-fix are `resolution_start` and `weapon_progress` — both must reach
	# the remote dice log.
	var synthetic_result := {
		"action_type": "RESOLVE_SHOOTING",
		"action_data": {},
		"success": true,
		"dice": [
			{"context": "resolution_start", "message": "Beginning attack resolution..."},
			{"context": "hit_roll", "rolls_raw": [4,5,6,2,3,1], "successes": 3, "threshold": "3+"},
			{"context": "wound_roll", "rolls_raw": [4,4,3], "successes": 2, "threshold": "4+"},
		]
	}

	captured.clear()
	network_manager._emit_client_visual_updates(synthetic_result)

	_check("Re-emits all 3 dice blocks (resolution_start + hit + wound)",
		captured.size() == 3,
		"got %d, contexts=%s" % [captured.size(), str(_contexts_of(captured))])

	if captured.size() == 3:
		_check("First re-emit is resolution_start",
			captured[0].get("context", "") == "resolution_start",
			"got %s" % str(captured[0].get("context")))
		_check("Second re-emit is hit_roll with 3 successes",
			captured[1].get("context", "") == "hit_roll" and captured[1].get("successes", -1) == 3,
			"got %s" % str(captured[1]))
		_check("Third re-emit is wound_roll with 2 successes",
			captured[2].get("context", "") == "wound_roll" and captured[2].get("successes", -1) == 2,
			"got %s" % str(captured[2]))

	# Also exercise the empty-dice case — must NOT explode and MUST emit 0.
	captured.clear()
	network_manager._emit_client_visual_updates({
		"action_type": "RESOLVE_SHOOTING",
		"action_data": {},
		"success": true,
		"dice": []
	})
	_check("Empty result.dice → no re-emissions",
		captured.size() == 0,
		"got %d unexpected emissions" % captured.size())

	# Restore phase_manager state.
	phase.dice_rolled.disconnect(capture)
	phase_manager.current_phase_instance = prior_phase
	phase.queue_free()

# ---------------------------------------------------------------------------
# 2. Grenade stratagem path — verifies the bug fix.
#
# Pre-fix: `_process_use_grenade_stratagem` emitted dice_rolled locally but
# returned a result whose only payload was `grenade_result` (no `dice` array).
# That meant the remote player's dice log never saw the 6D6 grenade roll.
#
# We drive the path with a real GameState + StratagemManager setup so the
# actual production code runs — then assert result["dice"] contains a single
# `grenade` block matching the dice_rolled emission.
# ---------------------------------------------------------------------------
func _test_grenade_action_includes_dice_in_result() -> void:
	print("\n-- Grenade stratagem result includes dice block for remote sync --")

	var game_state = root.get_node("GameState")
	var stratagem_manager = root.get_node("StratagemManager")

	# Build a minimal state with two units and enough CP for the grenade.
	game_state.initialize_default_state()
	game_state.state["meta"]["battle_round"] = 1
	game_state.state["meta"]["active_player"] = 1
	game_state.state["meta"]["phase"] = 8  # Shooting phase enum value
	game_state.state["players"] = {
		"1": {"cp": 5},
		"2": {"cp": 5}
	}
	game_state.state["units"] = {
		"U_GRENADIER": {
			"id": "U_GRENADIER", "owner": 1, "squad_id": "U_GRENADIER",
			"meta": {
				"name": "Grenadier",
				"keywords": ["INFANTRY", "GRENADES"],
				"stats": {"toughness": 4, "save": 3, "wounds": 1, "move": 6, "leadership": 7, "objective_control": 1}
			},
			"flags": {},
			"status": 3,  # DEPLOYED
			"models": [{
				"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular",
				"position": {"x": 0, "y": 0}
			}]
		},
		"U_TARGET": {
			"id": "U_TARGET", "owner": 2, "squad_id": "U_TARGET",
			"meta": {
				"name": "Target",
				"keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1, "move": 6, "leadership": 7, "objective_control": 1}
			},
			"flags": {},
			"status": 3,
			"models": [
				{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
				 "base_mm": 32, "base_type": "circular", "position": {"x": 100, "y": 0}},
				{"id": "m2", "alive": true, "wounds": 1, "current_wounds": 1,
				 "base_mm": 32, "base_type": "circular", "position": {"x": 130, "y": 0}}
			]
		}
	}
	# Reset stratagem usage so can_use_stratagem permits the grenade this test.
	if "_usage_history" in stratagem_manager:
		stratagem_manager._usage_history = {"1": [], "2": []}
	if "_stratagems_used_this_phase" in stratagem_manager:
		stratagem_manager._stratagems_used_this_phase = []

	# Determinism: pin the dice through RulesEngine test seed so result["dice"]
	# is reproducible.
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(42)

	# Instantiate ShootingPhase fresh for this test.
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	root.add_child(phase)
	phase.game_state_snapshot = game_state.create_snapshot()

	# Capture local dice_rolled signal so we can compare to result["dice"].
	var captured := []
	var capture := func(dice_block):
		captured.append(dice_block)
	phase.dice_rolled.connect(capture)

	# Drive the action under test.
	var action := {
		"type": "USE_GRENADE_STRATAGEM",
		"grenade_unit_id": "U_GRENADIER",
		"target_unit_id": "U_TARGET"
	}
	var result = phase._process_use_grenade_stratagem(action)

	rules.set_test_seed(-1)

	_check("Grenade action returns success",
		result.get("success", false) == true,
		"error=%s" % str(result.get("error", "")))

	var result_dice = result.get("dice", null)
	_check("Grenade result has 'dice' key (Array)",
		typeof(result_dice) == TYPE_ARRAY,
		"got type=%s" % str(typeof(result_dice)))

	if typeof(result_dice) == TYPE_ARRAY:
		_check("Grenade result.dice has exactly 1 block",
			result_dice.size() == 1,
			"got %d blocks" % result_dice.size())
		if result_dice.size() == 1:
			var block = result_dice[0]
			_check("Grenade result block context = 'grenade'",
				block.get("context", "") == "grenade",
				"got context=%s" % str(block.get("context")))
			_check("Grenade result block has rolls_raw (6 dice)",
				typeof(block.get("rolls_raw", null)) == TYPE_ARRAY and block.get("rolls_raw", []).size() == 6,
				"got rolls_raw=%s" % str(block.get("rolls_raw")))
			_check("Grenade result block threshold = '4+'",
				block.get("threshold", "") == "4+",
				"got threshold=%s" % str(block.get("threshold")))

	# Local dice_rolled emission must match result["dice"] (so the local UI
	# and the remote re-emission see the same block).
	_check("Local dice_rolled emitted exactly 1 grenade block",
		captured.size() == 1 and captured[0].get("context", "") == "grenade",
		"emitted %d, contexts=%s" % [captured.size(), str(_contexts_of(captured))])

	if captured.size() == 1 and typeof(result_dice) == TYPE_ARRAY and result_dice.size() == 1:
		_check("Local emit matches result.dice block (rolls_raw)",
			str(captured[0].get("rolls_raw")) == str(result_dice[0].get("rolls_raw")),
			"local=%s result=%s" % [str(captured[0].get("rolls_raw")), str(result_dice[0].get("rolls_raw"))])

	phase.dice_rolled.disconnect(capture)
	phase.queue_free()

# ---------------------------------------------------------------------------
# 3. Resolve-shooting (single weapon, miss) — verifies the resolution_start
# block is bundled into result["dice"] for remote sync.
#
# This regression-tests the existing T5-MP5 fix at ShootingPhase.gd:1024 where
# `dice_data = [resolution_start_block] + result.get("dice", [])` is built and
# returned. If a refactor ever drops the prepend, the remote dice log loses
# the "Beginning attack resolution..." header.
# ---------------------------------------------------------------------------
func _test_resolve_shooting_path_prepends_resolution_start_to_dice() -> void:
	print("\n-- Resolve-shooting result.dice includes resolution_start block --")

	# Reuse a tiny helper: scan ShootingPhase.gd source for the prepend pattern.
	# Static-source assertion — survives even if we can't drive a full shoot
	# end-to-end in the headless harness.
	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	_check("ShootingPhase.gd readable", src != null)
	if src == null:
		return
	var text = src.get_as_text()
	src.close()

	_check("Source contains '[resolution_start_block] + result.get(\"dice\", [])' (resolve_shooting prepend)",
		text.contains("[resolution_start_block] + result.get(\"dice\", [])"),
		"prepend pattern missing — remote dice log will lose resolution_start header")
	_check("Source contains '[weapon_progress_block] + result.get(\"dice\", [])' (sequential prepend)",
		text.contains("[weapon_progress_block] + result.get(\"dice\", [])"),
		"prepend pattern missing — remote dice log will lose weapon progress header")

	# And — critical — the grenade fix itself.
	_check("Source contains '\"dice\": [grenade_dice_block]' (grenade dice in result)",
		text.contains("\"dice\": [grenade_dice_block]"),
		"grenade dice block not bundled into result[\"dice\"] — remote dice log misses grenade rolls")

# ---------------------------------------------------------------------------
# 4. Apply-saves collects FNP + Hazardous into save_dice_blocks.
#
# Pre-fix, FNP and Hazardous dice blocks were emitted via `dice_rolled` and
# pushed onto `dice_log`, but NOT appended to `save_dice_blocks`. Only
# `save_dice_blocks` is bundled into the APPLY_SAVES result["dice"] (lines
# 5352, 5374, 5475), so the remote dice log used to drop FNP & Hazardous.
# ---------------------------------------------------------------------------
func _test_apply_saves_collects_fnp_into_save_dice_blocks() -> void:
	print("\n-- _process_apply_saves appends FNP + Hazardous to save_dice_blocks --")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	if src == null:
		_check("ShootingPhase.gd readable", false)
		return
	var text = src.get_as_text()
	src.close()

	# Grep for the two new save_dice_blocks.append() additions in the FNP
	# branches and the hazardous branch. These are the structural fixes.
	var lines = text.split("\n")

	var fnp_appends = 0
	var haz_appends = 0
	var in_fnp_engine = false
	var in_fnp_overlay = false
	var in_haz_loop = false
	for i in range(lines.size()):
		var l = lines[i]
		# FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path
		if "FEEL NO PAIN: Emit FNP dice blocks from RulesEngine batch path" in l:
			in_fnp_engine = true
		# Overlay path
		if "fnp_overlay_block = {" in l:
			in_fnp_overlay = true
		# Hazardous loop
		if "for haz_dice in haz_result.dice:" in l:
			in_haz_loop = true
		# Detect appends within ~30 lines of the marker.
		if in_fnp_engine and "save_dice_blocks.append(fnp_dice_block)" in l:
			fnp_appends += 1
			in_fnp_engine = false
		if in_fnp_overlay and "save_dice_blocks.append(fnp_overlay_block)" in l:
			fnp_appends += 1
			in_fnp_overlay = false
		if in_haz_loop and "save_dice_blocks.append(haz_dice)" in l:
			haz_appends += 1
			in_haz_loop = false

	_check("FNP (engine path) is appended to save_dice_blocks (1 occurrence)",
		fnp_appends >= 1,
		"got %d FNP append(s); remote dice log loses RulesEngine FNP rolls" % fnp_appends)
	_check("FNP (overlay path) is appended to save_dice_blocks (2 occurrences total expected)",
		fnp_appends >= 2,
		"got %d FNP append(s); remote dice log loses interactive-saves FNP rolls" % fnp_appends)
	_check("Hazardous dice are appended to save_dice_blocks",
		haz_appends >= 1,
		"got %d Hazardous append(s); remote dice log loses self-damage rolls" % haz_appends)

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _contexts_of(blocks: Array) -> Array:
	var out := []
	for b in blocks:
		out.append(b.get("context", "?"))
	return out

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
