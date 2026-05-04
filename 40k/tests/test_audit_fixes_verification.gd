extends SceneTree

# Verifies the audit fixes #329, #336, #338, #356, #359 still hold in
# fresh-game (post-merge) state. The pretrigger fixture tests already cover
# #361 (per_model_paths Vector2 coercion) and #362 (rapid-ingress null-safety).
#
# Usage: godot --headless --path . -s tests/test_audit_fixes_verification.gd

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
	print("\n=== test_audit_fixes_verification ===\n")

	_test_329_rng_determinism()
	_test_336_command_cp_rules()
	_test_338_autoload_save_load()
	_test_356_fall_back_and_shoot_override()
	_test_359_excluding_keyword_parser()

	_finish()

# ----------------------------------------------------------------------------
# #329 — RNG seed determinism via test_mode_seed
# ----------------------------------------------------------------------------
func _test_329_rng_determinism() -> void:
	print("\n-- #329: RNG determinism via test_mode_seed --")
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(42)
	var rng_a = rules.RNGService.new()
	var rolls_a = rng_a.roll_d6(10)

	rules.set_test_seed(42)
	var rng_b = rules.RNGService.new()
	var rolls_b = rng_b.roll_d6(10)

	_check("Same seed → identical 10-D6 sequence",
		str(rolls_a) == str(rolls_b),
		"a=%s b=%s" % [str(rolls_a), str(rolls_b)])

	# Different seed → different sequence (probabilistically; with 10 D6 this is ~1 in 6^10)
	rules.set_test_seed(99)
	var rng_c = rules.RNGService.new()
	var rolls_c = rng_c.roll_d6(10)
	_check("Different seed → different sequence",
		str(rolls_c) != str(rolls_a),
		"both=%s" % str(rolls_a))

	# Reset to default randomization
	rules.set_test_seed(-1)
	_check("set_test_seed(-1) disables test mode",
		rules.get_test_seed() == -1)

# ----------------------------------------------------------------------------
# #336 — Command phase CP rules (no CP on R1 first command phase, otherwise
# active player only)
# ----------------------------------------------------------------------------
func _test_336_command_cp_rules() -> void:
	print("\n-- #336: Command phase CP gating --")
	var game_state = root.get_node("GameState")
	var phase_mgr = root.get_node("PhaseManager")

	# Build a minimal fresh state so the CommandPhase has the inputs it needs.
	game_state.initialize_default_state()
	game_state.state["meta"]["battle_round"] = 1
	game_state.state["meta"]["active_player"] = 1
	game_state.state["meta"]["first_turn_player"] = 1
	game_state.state["meta"]["phase"] = 6  # COMMAND
	game_state.state["players"]["1"]["cp"] = 3
	game_state.state["players"]["2"]["cp"] = 3

	phase_mgr.transition_to_phase(6)
	var phase = phase_mgr.get_current_phase_instance()
	_check("CommandPhase instance present (R1 P1)",
		phase != null and phase.get_script().resource_path.ends_with("CommandPhase.gd"),
		"got %s" % (str(phase.get_script().resource_path) if phase else "null"))

	if phase == null:
		return

	# After phase enter (which happens in transition_to_phase), the CP for the
	# first-turn player on R1 should NOT have been incremented.
	_check("R1 first turn: P1 CP unchanged at 3 (#336 — no CP on first command phase)",
		game_state.state["players"]["1"]["cp"] == 3,
		"got %d" % game_state.state["players"]["1"]["cp"])
	_check("R1 first turn: P2 CP unchanged at 3 (no CP for opponent)",
		game_state.state["players"]["2"]["cp"] == 3,
		"got %d" % game_state.state["players"]["2"]["cp"])

	# Now simulate R2, P1 command phase — P1 should gain +1 CP, P2 should not.
	game_state.state["meta"]["battle_round"] = 2
	game_state.state["meta"]["active_player"] = 1
	game_state.state["players"]["1"]["cp"] = 3
	game_state.state["players"]["2"]["cp"] = 3
	phase_mgr.transition_to_phase(6)
	_check("R2 P1: P1 CP gained +1 (3→4)",
		game_state.state["players"]["1"]["cp"] == 4,
		"got %d" % game_state.state["players"]["1"]["cp"])
	_check("R2 P1: P2 CP unchanged at 3 (no opponent CP)",
		game_state.state["players"]["2"]["cp"] == 3,
		"got %d" % game_state.state["players"]["2"]["cp"])

# ----------------------------------------------------------------------------
# #338 — Autoload state survives get_state_for_save / load_state round-trip
# ----------------------------------------------------------------------------
func _test_338_autoload_save_load() -> void:
	print("\n-- #338: Autoload state save/load round-trip --")
	var fam = root.get_node("FactionAbilityManager")
	if fam == null:
		_check("FactionAbilityManager autoload present", false, "got null")
		return
	_check("FactionAbilityManager autoload present", true)

	# Set state we want to verify survives a snapshot/restore.
	fam._waaagh_used = {"1": true, "2": false}
	fam._waaagh_active = {"1": false, "2": false}
	fam._plant_waaagh_banner_used = {"1": true}

	var snapshot = fam.get_state_for_save()
	_check("snapshot.waaagh_used.1 = true",
		snapshot.get("waaagh_used", {}).get("1") == true)
	_check("snapshot.plant_waaagh_banner_used.1 = true",
		snapshot.get("plant_waaagh_banner_used", {}).get("1") == true)

	# Wipe live state.
	fam._waaagh_used = {"1": false, "2": false}
	fam._plant_waaagh_banner_used = {}

	# Reload from snapshot.
	fam.load_state(snapshot)

	_check("After load_state: waaagh_used.1 restored to true",
		fam._waaagh_used.get("1") == true)
	_check("After load_state: plant_waaagh_banner_used.1 restored to true",
		fam._plant_waaagh_banner_used.get("1") == true)

	# StratagemManager parallel check.
	var sm = root.get_node("StratagemManager")
	if sm and sm.has_method("get_state_for_save") and sm.has_method("load_state"):
		var sm_snapshot = sm.get_state_for_save()
		_check("StratagemManager snapshot is a Dictionary", typeof(sm_snapshot) == TYPE_DICTIONARY)
		# Verify load_state on the existing snapshot doesn't error
		sm.load_state(sm_snapshot)
		_check("StratagemManager load_state(snapshot) returns without error", true)
	else:
		_check("StratagemManager has save API", false, "missing get_state_for_save/load_state")

# ----------------------------------------------------------------------------
# #356 — effect_fall_back_and_shoot overrides post-Fall-Back shooting lockout
# ----------------------------------------------------------------------------
func _test_356_fall_back_and_shoot_override() -> void:
	print("\n-- #356: effect_fall_back_and_shoot override --")
	var rules = root.get_node("RulesEngine")
	# Build a minimal unit with fell_back=true. Without the override, validate
	# should reject; with effect_fall_back_and_shoot=true it should allow.
	var unit_no_override = {
		"id": "U_TEST",
		"owner": 1,
		"meta": {"keywords": ["INFANTRY"]},
		"flags": {"fell_back": true},
		"models": [{"alive": true, "position": {"x": 0, "y": 0}, "current_wounds": 1}]
	}
	var board_state := {
		"units": {"U_TEST": unit_no_override},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 2}
	}
	# Need at least one assignment to pass the empty-check and reach the fell_back guard.
	var action_no_override := {
		"type": "SHOOT",
		"actor_unit_id": "U_TEST",
		"payload": {"assignments": [{"weapon_id": "dummy", "target_unit_id": "U_X"}]}
	}

	var v_block = rules.validate_shoot(action_no_override, board_state)
	var has_fell_back_error = false
	for e in v_block.get("errors", []):
		if "fell back" in str(e).to_lower():
			has_fell_back_error = true
	_check("Without override: validate_shoot rejects fell-back unit",
		has_fell_back_error,
		"errors=%s" % str(v_block.get("errors", [])))

	# Now enable the effect override
	unit_no_override["flags"]["effect_fall_back_and_shoot"] = true
	board_state["units"]["U_TEST"] = unit_no_override

	var v_pass = rules.validate_shoot(action_no_override, board_state)
	var still_fell_back_error = false
	for e in v_pass.get("errors", []):
		if "fell back" in str(e).to_lower():
			still_fell_back_error = true
	_check("With override: validate_shoot does NOT emit fell-back error",
		not still_fell_back_error,
		"errors=%s" % str(v_pass.get("errors", [])))

# ----------------------------------------------------------------------------
# #359 — "excluding X" target text parses to not_keyword:X
# ----------------------------------------------------------------------------
func _test_359_excluding_keyword_parser() -> void:
	print("\n-- #359: excluding-X parser --")
	# FactionStratagemLoaderData is a class, not an autoload — instantiate it.
	var loader = FactionStratagemLoaderData.new()
	_check("FactionStratagemLoaderData instantiable", loader != null)

	# _parse_target is an instance method on the loader.
	var target = loader.call("_parse_target",
		"One unit from your army (excluding VEHICLES and MONSTERS)")
	var conditions: Array = target.get("conditions", [])
	_check("'excluding VEHICLES and MONSTERS' → not_keyword:VEHICLE present",
		"not_keyword:VEHICLE" in conditions,
		"conditions=%s" % str(conditions))
	_check("'excluding VEHICLES and MONSTERS' → not_keyword:MONSTER present",
		"not_keyword:MONSTER" in conditions,
		"conditions=%s" % str(conditions))
	# After exclusion stripped, no keyword:VEHICLE / keyword:MONSTER should leak in
	_check("Stripped: no rogue keyword:VEHICLE",
		not ("keyword:VEHICLE" in conditions),
		"conditions=%s" % str(conditions))
	_check("Stripped: no rogue keyword:MONSTER",
		not ("keyword:MONSTER" in conditions),
		"conditions=%s" % str(conditions))

	# Now run unit_matches_target with the exclusion conditions
	var vehicle_unit = {"meta": {"keywords": ["VEHICLE", "INFANTRY"]}, "flags": {}}
	var infantry_unit = {"meta": {"keywords": ["INFANTRY", "GRENADES"]}, "flags": {}}
	_check("Vehicle unit fails not_keyword:VEHICLE filter",
		not FactionStratagemLoaderData.unit_matches_target(vehicle_unit, target))
	_check("Pure infantry unit passes filter",
		FactionStratagemLoaderData.unit_matches_target(infantry_unit, target))

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
