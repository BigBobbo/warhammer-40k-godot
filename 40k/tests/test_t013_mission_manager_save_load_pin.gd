extends SceneTree

# 06_SYNTHESIS launch-blocker #13: MissionManager runtime state save/load.
#
# 17+ runtime tracking dicts on MissionManager (sticky objectives, kill
# counters, supply-drop flag, _units_alive_at_round_start, vp_timeline,
# burned/ritual/terraformed objectives, etc.) used to be reset on save/
# load because the autoload had no get_state_for_save / load_state and
# wasn't included in the snapshot. The fix already landed -- this commit
# only adds regression coverage so it stays wired.
#
# Pin verifies:
#   A) MissionManager exposes get_state_for_save + load_state.
#   B) GameState.create_snapshot includes "mission_manager" with all the
#      runtime tracking dicts populated.
#   C) GameState.load_from_snapshot restores them onto the autoload.
#   D) End-to-end SaveLoadManager disk round-trip preserves the state.
#
# Usage: godot --headless --path . -s tests/test_t013_mission_manager_save_load_pin.gd

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
	print("\n=== test_t013_mission_manager_save_load_pin ===\n")
	_test_api_exists()
	_test_snapshot_includes_mm()
	_test_load_from_snapshot_restores()
	_test_full_disk_round_trip()
	_finish()

func _test_api_exists() -> void:
	print("\n-- A: MissionManager exposes get_state_for_save / load_state --")
	var mm = root.get_node_or_null("MissionManager")
	if mm == null:
		_check("MissionManager autoload reachable", false)
		return
	_check("MissionManager autoload reachable", true)
	_check("get_state_for_save exists", mm.has_method("get_state_for_save"))
	_check("load_state exists", mm.has_method("load_state"))

func _test_snapshot_includes_mm() -> void:
	print("\n-- B: create_snapshot includes 'mission_manager' --")
	var mm = root.get_node("MissionManager")
	var gs = root.get_node("GameState")
	# Mutate canonical state vars
	mm._sticky_objectives = {"obj_center": 1}  # player 1 claimed
	mm._kills_this_round = {"1": 3, "2": 1}
	mm.supply_drop_resolved_round_4 = true
	mm._vp_timeline = {"r1_p1": 5, "r1_p2": 0}
	mm._units_alive_at_round_start = {"1": {"U_FOO": 1}}
	var snap = gs.create_snapshot()
	_check("snapshot has 'mission_manager' key",
		snap.has("mission_manager"))
	if snap.has("mission_manager"):
		var blob: Dictionary = snap["mission_manager"]
		_check("sticky_objectives preserved",
			blob.get("sticky_objectives", {}).get("obj_center", -1) == 1)
		_check("kills_this_round preserved",
			int(blob.get("kills_this_round", {}).get("1", -1)) == 3)
		_check("supply_drop_resolved_round_4 preserved",
			blob.get("supply_drop_resolved_round_4", false) == true)
		_check("vp_timeline preserved",
			int(blob.get("vp_timeline", {}).get("r1_p1", -1)) == 5)
		_check("units_alive_at_round_start preserved",
			blob.get("units_alive_at_round_start", {}).has("1"))

func _test_load_from_snapshot_restores() -> void:
	print("\n-- C: GameState.load_from_snapshot restores onto autoload --")
	var mm = root.get_node("MissionManager")
	var gs = root.get_node("GameState")
	# Build snapshot with custom MM state
	var minimal = gs.create_snapshot()
	minimal["mission_manager"] = {
		"current_mission": {},
		"objective_control_state": {},
		"sticky_objectives": {"obj_load_test": 2},
		"kills_this_round": {"1": 7, "2": 2},
		"burned_objectives_meta": {},
		"pending_burns": {},
		"ritual_objectives": {},
		"pending_rituals": {},
		"terraformed_objectives": {},
		"pending_terraforms": {},
		"vp_timeline": {"r3_p2": 11},
		"burn_in_progress": {},
		"burned_objectives_arr": ["obj_burned_test"],
		"removed_objectives": [],
		"supply_drop_resolved_round_4": true,
		"kills_per_round": {},
		"character_claimed_objectives": {},
		"units_alive_at_round_start": {"2": {"U_LOAD_TEST": 2}},
	}
	# Clear so we can prove the load wrote something
	mm._sticky_objectives.clear()
	mm._kills_this_round = {"1": 0, "2": 0}
	mm.supply_drop_resolved_round_4 = false
	mm.burned_objectives = []
	mm._units_alive_at_round_start.clear()
	gs.load_from_snapshot(minimal)
	_check("sticky_objectives restored",
		mm._sticky_objectives.get("obj_load_test", -1) == 2,
		"got %s" % str(mm._sticky_objectives))
	_check("kills_this_round restored",
		int(mm._kills_this_round.get("1", -1)) == 7)
	_check("supply_drop_resolved_round_4 restored",
		mm.supply_drop_resolved_round_4 == true)
	_check("burned_objectives (arr) restored",
		"obj_burned_test" in mm.burned_objectives,
		"got %s" % str(mm.burned_objectives))
	_check("units_alive_at_round_start restored",
		mm._units_alive_at_round_start.has("2"))

func _test_full_disk_round_trip() -> void:
	print("\n-- D: SaveLoadManager full disk round-trip --")
	var slm = root.get_node_or_null("SaveLoadManager")
	if slm == null:
		_check("SaveLoadManager autoload reachable", false)
		return
	_check("SaveLoadManager autoload reachable", true)
	var mm = root.get_node("MissionManager")
	mm._sticky_objectives = {"obj_disk_a": 1, "obj_disk_b": 2}
	mm.supply_drop_resolved_round_4 = true
	var save_name = "test_t013_mm_roundtrip"
	var saved = slm.save_game(save_name)
	_check("save_game returned true", saved == true)
	# Mutate so we can prove the load really replaces.
	mm._sticky_objectives = {"obj_pollution": 9}
	mm.supply_drop_resolved_round_4 = false
	var loaded = slm.load_game(save_name)
	_check("load_game returned true", loaded == true)
	_check("sticky_objectives reloaded from disk",
		mm._sticky_objectives.get("obj_disk_a", -1) == 1
			and mm._sticky_objectives.get("obj_disk_b", -1) == 2,
		"got %s" % str(mm._sticky_objectives))
	_check("post-save mutation 'obj_pollution' is GONE after load",
		not mm._sticky_objectives.has("obj_pollution"))
	_check("supply_drop_resolved_round_4 reloaded from disk",
		mm.supply_drop_resolved_round_4 == true)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
