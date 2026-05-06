extends SceneTree

# T-058: AIRCRAFT cannot declare charges; only FLY units can charge AIRCRAFT
# targets. The audit asks for both filters; ChargePhase already implements
# T2-9 — this test pins the behaviour.
#
# Usage: godot --headless --path . -s tests/test_t058_aircraft_charge.gd

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
	print("\n=== test_t058_aircraft_charge ===\n")
	_test_aircraft_cannot_charge()
	_test_only_fly_can_charge_aircraft()
	_finish()

func _make_unit(id: String, owner: int, keywords: Array, position: Vector2) -> Dictionary:
	return {
		"id": id,
		"squad_id": id,
		"owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {
			"name": id,
			"keywords": keywords,
			"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1},
		},
		"models": [{
			"id": "m1",
			"alive": true,
			"current_wounds": 1,
			"wounds": 1,
			"base_mm": 32,
			"position": {"x": position.x, "y": position.y},
		}],
		"embarked_in": null,
	}

func _new_charge_phase() -> Node:
	var phase = load("res://phases/ChargePhase.gd").new()
	# Provide minimal snapshot so methods that consult game_state_snapshot work.
	phase.game_state_snapshot = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": 1},
		"units": {},
	}
	return phase

func _test_aircraft_cannot_charge() -> void:
	print("\n-- T-058a: AIRCRAFT cannot declare a charge --")
	var phase = _new_charge_phase()
	var aircraft = _make_unit("U_AIRCRAFT", 1, ["AIRCRAFT", "VEHICLE", "FLY"], Vector2(100, 100))
	var infantry = _make_unit("U_GROUNDED", 1, ["INFANTRY"], Vector2(100, 100))
	# Both deployed, in ChargePhase
	_check("AIRCRAFT cannot charge", not phase._can_unit_charge(aircraft),
		"keywords=%s" % str(aircraft.meta.keywords))
	_check("Non-AIRCRAFT INFANTRY can charge",
		phase._can_unit_charge(infantry),
		"keywords=%s" % str(infantry.meta.keywords))
	phase.queue_free()

func _test_only_fly_can_charge_aircraft() -> void:
	print("\n-- T-058b: only FLY units can charge AIRCRAFT targets --")
	var phase = _new_charge_phase()
	# Set up GameState too so get_active_player works.
	var gs = root.get_node("GameState")
	var prev_state = gs.state
	gs.state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": 1, "battle_round": 1, "turn_number": 1},
		"units": {},
		"players": {"1": {"cp": 3, "vp": 0}, "2": {"cp": 3, "vp": 0}},
	}

	# Space far enough apart that the units are not "already engaged" but close
	# enough that a charge is theoretically possible (12" = ~480 px).
	var grounded_charger = _make_unit("U_GROUND_CHARGER", 1, ["INFANTRY"], Vector2(0, 0))
	var fly_charger = _make_unit("U_FLY_CHARGER", 1, ["INFANTRY", "FLY"], Vector2(0, 200))
	var aircraft_target = _make_unit("U_AIRCRAFT_TARGET", 2, ["AIRCRAFT", "VEHICLE", "FLY"], Vector2(300, 0))

	gs.state.units = {
		"U_GROUND_CHARGER": grounded_charger,
		"U_FLY_CHARGER": fly_charger,
		"U_AIRCRAFT_TARGET": aircraft_target,
	}
	phase.game_state_snapshot.units = gs.state.units

	var grounded_action = {
		"type": "DECLARE_CHARGE",
		"actor_unit_id": "U_GROUND_CHARGER",
		"payload": {"target_unit_ids": ["U_AIRCRAFT_TARGET"]},
	}
	var grounded_validation = phase._validate_declare_charge(grounded_action)
	var has_aircraft_error = false
	for err in grounded_validation.get("errors", []):
		if "AIRCRAFT" in str(err):
			has_aircraft_error = true
	_check("Non-FLY charger cannot target AIRCRAFT", has_aircraft_error,
		"errors=%s" % str(grounded_validation.get("errors", [])))

	var fly_action = {
		"type": "DECLARE_CHARGE",
		"actor_unit_id": "U_FLY_CHARGER",
		"payload": {"target_unit_ids": ["U_AIRCRAFT_TARGET"]},
	}
	var fly_validation = phase._validate_declare_charge(fly_action)
	var has_aircraft_error_fly = false
	for err in fly_validation.get("errors", []):
		if "AIRCRAFT" in str(err):
			has_aircraft_error_fly = true
	_check("FLY charger has NO AIRCRAFT-target error",
		not has_aircraft_error_fly,
		"errors=%s" % str(fly_validation.get("errors", [])))

	# Restore state
	gs.state = prev_state
	phase.queue_free()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
