extends SceneTree

# Audit (.llm/audit_2026_launch/03_core_rules/13_save_load_state.md):
# For each pretrigger fixture, do a 2-pass round-trip and diff.
#   1. load fixture → snapshot A
#   2. save_game("audit_rt_<id>") + load_game("audit_rt_<id>") → snapshot B
#   3. diff A vs B; any non-empty diff is a finding
#
# This is the headless regression net for autoload-state persistence
# (Issue #338 follow-up): not just FactionAbilityManager / StratagemManager,
# but every gameplay-bearing autoload.
#
# Usage: godot --headless --path . -s tests/test_save_load_audit_roundtrip.gd

var passed := 0
var failed := 0
var findings := []

const FIXTURES := [
	"co_pretrigger",
	"hi_pretrigger",
	"ri_pretrigger",
]

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		findings.append(label + (" -- " + detail if detail != "" else ""))
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

func _run_tests() -> void:
	if passed > 0 or failed > 0:
		return
	print("\n=== test_save_load_audit_roundtrip ===\n")

	for fixture_id in FIXTURES:
		_test_fixture_roundtrip(fixture_id)

	_test_rng_seed_persistence()
	_test_phase_manager_persistence()
	_test_unit_ability_manager_wiring()
	_test_mission_manager_persistence()
	_test_turn_manager_persistence()

	_finish()

func _test_fixture_roundtrip(fixture_id: String) -> void:
	print("\n-- Fixture: %s --" % fixture_id)
	var slm = root.get_node("SaveLoadManager")
	var gs = root.get_node("GameState")

	# Step 1: load fixture
	# fixture lives at 40k/saves/<id>.w40ksave (project-relative res://saves/<id>.w40ksave)
	var ok_load = slm.load_game(fixture_id)
	_check("load fixture %s" % fixture_id, ok_load)
	if not ok_load:
		return

	# Pre-save snapshot
	var snap_a = gs.create_snapshot()

	# Step 2: save under audit_rt_<id> then load it back
	var rt_name = "audit_rt_%s" % fixture_id
	var ok_save = slm.save_game(rt_name)
	_check("save round-trip %s" % rt_name, ok_save)
	if not ok_save:
		return

	# Mutate live state to be sure load actually replaces it.
	gs.state["meta"]["audit_marker"] = "should_be_overwritten"

	var ok_reload = slm.load_game(rt_name)
	_check("reload round-trip %s" % rt_name, ok_reload)
	if not ok_reload:
		return

	# Step 3: snapshot B and diff
	var snap_b = gs.create_snapshot()

	# Allow timestamps inside meta to drift — they're metadata not gameplay.
	# Compare top-level gameplay sections explicitly.
	_check("%s: meta.phase round-trip" % fixture_id,
		snap_a.get("meta", {}).get("phase") == snap_b.get("meta", {}).get("phase"),
		"a=%s b=%s" % [str(snap_a.get("meta", {}).get("phase")), str(snap_b.get("meta", {}).get("phase"))])
	_check("%s: meta.active_player round-trip" % fixture_id,
		snap_a.get("meta", {}).get("active_player") == snap_b.get("meta", {}).get("active_player"))
	_check("%s: meta.battle_round round-trip" % fixture_id,
		snap_a.get("meta", {}).get("battle_round") == snap_b.get("meta", {}).get("battle_round"))
	_check("%s: audit_marker NOT in reloaded state (load really replaced)" % fixture_id,
		not snap_b.get("meta", {}).has("audit_marker"))

	# Players (CP, VP)
	for pk in ["1", "2"]:
		var a_cp = snap_a.get("players", {}).get(pk, {}).get("cp", -1)
		var b_cp = snap_b.get("players", {}).get(pk, {}).get("cp", -1)
		_check("%s: P%s CP round-trip" % [fixture_id, pk], a_cp == b_cp,
			"a=%d b=%d" % [a_cp, b_cp])
		var a_vp = snap_a.get("players", {}).get(pk, {}).get("vp", -1)
		var b_vp = snap_b.get("players", {}).get(pk, {}).get("vp", -1)
		_check("%s: P%s VP round-trip" % [fixture_id, pk], a_vp == b_vp,
			"a=%d b=%d" % [a_vp, b_vp])

	# Unit count
	_check("%s: unit count round-trip" % fixture_id,
		snap_a.get("units", {}).size() == snap_b.get("units", {}).size(),
		"a=%d b=%d" % [snap_a.get("units", {}).size(), snap_b.get("units", {}).size()])

	# Per-unit flags — sample first 3 deployed units
	var a_units = snap_a.get("units", {})
	var b_units = snap_b.get("units", {})
	var sampled := 0
	for unit_id in a_units:
		if sampled >= 3:
			break
		var a_u = a_units[unit_id]
		var b_u = b_units.get(unit_id, {})
		if a_u.get("status", 0) == 0:
			continue
		sampled += 1
		# Flags
		var a_flags = a_u.get("flags", {})
		var b_flags = b_u.get("flags", {})
		var keys_to_check = ["moved", "advanced", "fell_back", "charged_this_turn",
			"battle_shocked", "remained_stationary", "fired_overwatch"]
		for k in keys_to_check:
			var av = a_flags.get(k, null)
			var bv = b_flags.get(k, null)
			_check("%s: unit %s flag '%s' round-trip" % [fixture_id, unit_id, k],
				av == bv, "a=%s b=%s" % [str(av), str(bv)])

	# FactionAbilityManager state — once-per-battle locks
	var fam_a = snap_a.get("faction_ability_manager", {})
	var fam_b = snap_b.get("faction_ability_manager", {})
	_check("%s: faction_ability_manager.waaagh_used round-trip" % fixture_id,
		str(fam_a.get("waaagh_used", {})) == str(fam_b.get("waaagh_used", {})),
		"a=%s b=%s" % [str(fam_a.get("waaagh_used", {})), str(fam_b.get("waaagh_used", {}))])
	_check("%s: faction_ability_manager.plant_waaagh_banner_used round-trip" % fixture_id,
		str(fam_a.get("plant_waaagh_banner_used", {})) == str(fam_b.get("plant_waaagh_banner_used", {})))

	# StratagemManager state — usage_history (once-per-battle stratagem locks)
	var sm_a = snap_a.get("stratagem_manager", {})
	var sm_b = snap_b.get("stratagem_manager", {})
	_check("%s: stratagem_manager.usage_history round-trip" % fixture_id,
		str(sm_a.get("usage_history", {})) == str(sm_b.get("usage_history", {})))

# RNG determinism after save/restore — issue #348 audit follow-up.
# The test_mode_seed is static on RNGService; it is NOT serialized into a save
# snapshot. Therefore, set a seed, save, mutate, reload — the seed is whatever
# was last set at process scope, not what was in the save. Validation here is
# that the seed survives normal game flow, which it currently does NOT.
func _test_rng_seed_persistence() -> void:
	print("\n-- RNG seed persistence (#348 follow-up) --")
	var slm = root.get_node("SaveLoadManager")
	var gs = root.get_node("GameState")
	var rules = root.get_node("RulesEngine")

	# Save the current seed value.
	var initial_seed = rules.get_test_seed()

	rules.set_test_seed(12345)
	# Save now
	gs.initialize_default_state()
	var ok_save = slm.save_game("audit_rt_rng_seed")
	_check("save with test_mode_seed=12345", ok_save)

	# Mutate test_mode_seed in process
	rules.set_test_seed(99999)
	var ok_load = slm.load_game("audit_rt_rng_seed")
	_check("reload of audit_rt_rng_seed", ok_load)

	# After reload, what is the seed?
	var seed_after_reload = rules.get_test_seed()

	# Find: seed is NOT restored from save — it's whatever was last set in process.
	_check("RNG seed is restored from save (expected: 12345 if persisted)",
		seed_after_reload == 12345,
		"got %d (state.meta has no rng_seed; static var unchanged by load)" % seed_after_reload)

	# Reset
	rules.set_test_seed(initial_seed)

func _test_phase_manager_persistence() -> void:
	print("\n-- PhaseManager.game_ended persistence --")
	var slm = root.get_node("SaveLoadManager")
	var gs = root.get_node("GameState")
	var pm = root.get_node("PhaseManager")

	gs.initialize_default_state()

	# Save first
	var ok_save = slm.save_game("audit_rt_pm_baseline")
	_check("baseline save", ok_save)

	# Force PhaseManager.game_ended = true (e.g. previous Round-5 finish lingering)
	pm.game_ended = true

	# Reload baseline
	var ok_load = slm.load_game("audit_rt_pm_baseline")
	_check("reload baseline", ok_load)

	# After reload, has game_ended been reset?
	# If it has not, the autoload-state pattern bug applies to PhaseManager too.
	_check("PhaseManager.game_ended is cleared on load (baseline meta.game_ended=false)",
		not pm.game_ended,
		"PhaseManager.game_ended remained true after loading a baseline save -- autoload-state pattern bug")

func _test_unit_ability_manager_wiring() -> void:
	print("\n-- UnitAbilityManager.get_state_for_save wiring (audit-discovered) --")
	# Verify the API exists on UnitAbilityManager and is plumbed into the snapshot.
	var uam = root.get_node("UnitAbilityManager")
	_check("UnitAbilityManager autoload present", uam != null)
	if uam == null:
		return
	_check("UnitAbilityManager.get_state_for_save exists", uam.has_method("get_state_for_save"))
	_check("UnitAbilityManager.load_state exists", uam.has_method("load_state"))

	# Mutate state
	uam._once_per_battle_used = {"U_TEST_UNIT_1": ["MeltaBomb", "Vox"]}
	uam._once_per_round_used = {"U_TEST_UNIT_2": ["Stomp"]}

	# Snapshot via GameState
	var gs = root.get_node("GameState")
	var snap = gs.create_snapshot()
	_check("snapshot includes 'unit_ability_manager' key (NOT WIRED — audit gap)",
		snap.has("unit_ability_manager"),
		"GameState.create_snapshot does not call UnitAbilityManager.get_state_for_save() at GameState.gd:979-1037")

func _test_mission_manager_persistence() -> void:
	print("\n-- MissionManager autoload state persistence (audit-discovered) --")
	var mm = root.get_node("MissionManager")
	if mm == null:
		_check("MissionManager autoload present", false)
		return

	# MissionManager has many member-vars holding gameplay state:
	# - _sticky_objectives, _kills_this_round, _burned_objectives, _ritual_objectives,
	#   _terraformed_objectives, _vp_timeline, supply_drop_resolved_round_4,
	#   character_claimed_objectives, kills_per_round, removed_objectives, etc.
	# Verify whether get_save_data / get_state_for_save exists.
	_check("MissionManager has get_save_data or get_state_for_save (NOT PRESENT — audit gap)",
		mm.has_method("get_save_data") or mm.has_method("get_state_for_save"),
		"MissionManager holds _sticky_objectives, _kills_this_round, _burned_objectives, etc. which are reset on save/load")

func _test_turn_manager_persistence() -> void:
	print("\n-- TurnManager autoload state persistence (audit-discovered) --")
	var tm = root.get_node("TurnManager")
	if tm == null:
		_check("TurnManager autoload present", false)
		return
	_check("TurnManager has get_state_for_save (NOT PRESENT — audit gap)",
		tm.has_method("get_state_for_save"),
		"TurnManager._titanic_skip_turns held in member var; never serialized into snapshot")

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	if findings.size() > 0:
		print("\nFindings:")
		for f in findings:
			print("  - %s" % f)
	quit(1 if failed > 0 else 0)
