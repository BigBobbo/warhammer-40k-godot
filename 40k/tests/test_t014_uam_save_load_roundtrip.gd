extends SceneTree

# 06_SYNTHESIS launch-blocker #14 / issue #380:
# UnitAbilityManager.get_state_for_save / load_state are wired into
# GameState.create_snapshot + GameState.load_state. Once-per-battle and
# once-per-round ability locks must survive a save/load round-trip so a
# player cannot bypass them by saving + reloading.
#
# This pin verifies the wiring stays intact:
#   A) UnitAbilityManager exposes get_state_for_save + load_state.
#   B) GameState.create_snapshot includes the "unit_ability_manager" key.
#   C) GameState.load_from_snapshot restores the serialized values back
#      onto the autoload (round-trip identity).
#   D) The on-disk save written via SaveLoadManager round-trips through
#      reload back into UnitAbilityManager._once_per_battle_used /
#      _once_per_round_used.
#
# Usage: godot --headless --path . -s tests/test_t014_uam_save_load_roundtrip.gd

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
	print("\n=== test_t014_uam_save_load_roundtrip ===\n")
	_test_api_exists()
	_test_snapshot_includes_uam()
	_test_load_state_restores()
	_test_full_disk_round_trip()
	_finish()

func _test_api_exists() -> void:
	print("\n-- A: UnitAbilityManager exposes get_state_for_save / load_state --")
	var uam = root.get_node_or_null("UnitAbilityManager")
	if uam == null:
		_check("UnitAbilityManager autoload reachable", false)
		return
	_check("UnitAbilityManager autoload reachable", true)
	_check("get_state_for_save exists", uam.has_method("get_state_for_save"))
	_check("load_state exists", uam.has_method("load_state"))

func _test_snapshot_includes_uam() -> void:
	print("\n-- B: create_snapshot includes 'unit_ability_manager' --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	# Mutate canonical state vars
	uam._once_per_battle_used = {"U_TEST_X:Some Ability": true}
	uam._once_per_round_used = {"1:Strategic Mastery": 3}
	uam._mekaniak_used_this_turn = {"U_VEHICLE_X": true}
	uam._scatter_used_this_turn = {"U_BOY_X": true}
	var snap = gs.create_snapshot()
	_check("snapshot has 'unit_ability_manager' key",
		snap.has("unit_ability_manager"))
	if snap.has("unit_ability_manager"):
		var blob: Dictionary = snap["unit_ability_manager"]
		_check("snapshot.once_per_battle_used preserved",
			blob.get("once_per_battle_used", {}).get("U_TEST_X:Some Ability", false) == true)
		_check("snapshot.once_per_round_used preserved",
			blob.get("once_per_round_used", {}).get("1:Strategic Mastery", -1) == 3)
		_check("snapshot.mekaniak_used_this_turn preserved",
			blob.get("mekaniak_used_this_turn", {}).get("U_VEHICLE_X", false) == true)
		_check("snapshot.scatter_used_this_turn preserved",
			blob.get("scatter_used_this_turn", {}).get("U_BOY_X", false) == true)

func _test_load_state_restores() -> void:
	print("\n-- C: GameState.load_from_snapshot restores onto autoload --")
	var uam = root.get_node("UnitAbilityManager")
	var gs = root.get_node("GameState")
	# Build a synthetic minimal state with our values, then load it.
	var minimal = gs.create_snapshot()
	minimal["unit_ability_manager"] = {
		"active_ability_effects": [],
		"applied_this_phase": {},
		"once_per_battle_used": {"U_LOAD_X:Final Burst": true},
		"once_per_round_used": {"2:Counter-attack": 5},
		"active_aura_effects": {},
		"mekaniak_used_this_turn": {},
		"scatter_used_this_turn": {},
	}
	# Clear the autoload first so we can prove load actually wrote.
	uam._once_per_battle_used.clear()
	uam._once_per_round_used.clear()
	gs.load_from_snapshot(minimal)
	_check("once_per_battle_used restored from load",
		uam._once_per_battle_used.get("U_LOAD_X:Final Burst", false) == true,
		"got %s" % str(uam._once_per_battle_used))
	_check("once_per_round_used restored from load",
		uam._once_per_round_used.get("2:Counter-attack", -1) == 5,
		"got %s" % str(uam._once_per_round_used))

func _test_full_disk_round_trip() -> void:
	print("\n-- D: SaveLoadManager full disk round-trip --")
	var slm = root.get_node_or_null("SaveLoadManager")
	if slm == null:
		_check("SaveLoadManager autoload reachable", false)
		return
	_check("SaveLoadManager autoload reachable", true)
	var uam = root.get_node("UnitAbilityManager")
	uam._once_per_battle_used = {"U_DISK_X:Stomp": true, "U_DISK_Y:Headbutt": true}
	uam._once_per_round_used = {"1:Tactical Doctrine": 4}
	var save_name = "test_t014_uam_roundtrip"
	var saved = slm.save_game(save_name)
	_check("save_game returned true", saved == true)
	# Mutate so we can prove the load really replaces.
	uam._once_per_battle_used = {"U_DISK_Z:Ignored": true}
	uam._once_per_round_used = {}
	var loaded = slm.load_game(save_name)
	_check("load_game returned true", loaded == true)
	_check("once_per_battle_used reloaded from disk",
		uam._once_per_battle_used.get("U_DISK_X:Stomp", false) == true
			and uam._once_per_battle_used.get("U_DISK_Y:Headbutt", false) == true,
		"got %s" % str(uam._once_per_battle_used))
	_check("once_per_battle_used.U_DISK_Z (mutated post-save) is GONE after load",
		not uam._once_per_battle_used.has("U_DISK_Z:Ignored"))
	_check("once_per_round_used reloaded from disk",
		uam._once_per_round_used.get("1:Tactical Doctrine", -1) == 4)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
