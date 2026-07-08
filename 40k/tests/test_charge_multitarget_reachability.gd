extends SceneTree

# Multi-target charge reachability suite.
#
# Pins the fix for the reported "false SUCCESS" bug: a charge must end within
# engagement range of EVERY declared target, but the old roll-resolution only
# checked whether the NEAREST declared target was reachable. An over-declared
# charge (e.g. Vertus Praetors declaring 3 Painboys, roll reaches only 1) was
# logged SUCCESS then either silently failed at move-apply (10e) or had its far
# targets quietly dropped (11e), leaving the unit out of engagement range with
# no fight target and no visible explanation.
#
# Covers:
#   • _per_target_charge_requirements decomposition (per-edition ER).
#   • 10e: over-declared charge is FAILED at roll time, naming the unreachable
#     target(s), instead of a false SUCCESS.
#   • 10e: a charge that reaches ALL declared targets still SUCCEEDS.
#   • 11e: unreachable declared targets are dropped (subset charge) and the
#     drop is surfaced to the player via a GameEventLog entry.
#
# Usage: godot --headless --path . -s tests/test_charge_multitarget_reachability.gd

var passed := 0
var failed := 0

const PX_PER_INCH := 40.0  # project scale (Measurement.inches_to_px)

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s %s" % [label, ("(" + detail + ")") if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run_tests)

func _make_unit(id: String, owner: int, keywords: Array, positions: Array, base_mm: int = 32) -> Dictionary:
	var models = []
	for i in range(positions.size()):
		var pos = positions[i]
		models.append({
			"id": "m%d" % (i + 1),
			"alive": true,
			"current_wounds": 4,
			"wounds": 4,
			"base_mm": base_mm,
			"base_type": "circular",
			"position": ({"x": pos.x, "y": pos.y} if pos != null else null),
		})
	return {
		"id": id, "squad_id": id, "owner": owner,
		"status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": id, "keywords": keywords, "stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 4}},
		"models": models,
		"embarked_in": null,
	}

func _setup_state(units: Dictionary, active_player: int = 2) -> void:
	var gs = root.get_node("GameState")
	gs.state = {
		"meta": {"phase": GameStateData.Phase.CHARGE, "active_player": active_player, "battle_round": 1, "turn_number": 1, "game_id": "test"},
		"units": units,
		"players": {"1": {"cp": 0, "vp": 0}, "2": {"cp": 0, "vp": 0}},
		"board": {"terrain": []},
		"phase_log": [],
	}

func _new_phase() -> Node:
	var phase = load("res://phases/ChargePhase.gd").new()
	root.add_child(phase)
	phase._on_phase_enter()
	return phase

func _tm() -> Node:
	return root.get_node("TerrainManager")

func _event_log() -> Node:
	return root.get_node("GameEventLog")

# Charger at origin_x; near/far enemy targets at edge distances chosen so a
# roll of 3" reaches `near` but not `far`.
func _three_unit_state(origin_x: float, y: float) -> Dictionary:
	var charger = _make_unit("U_CHG", 2, ["INFANTRY"], [Vector2(origin_x, y)])
	# near: ~2.5" edge (center 150px = 3.75", minus two 0.63" radii ≈ 2.49")
	var near = _make_unit("U_NEAR", 1, ["INFANTRY"], [Vector2(origin_x + 150.0, y)])
	# far: ~8" edge (center 370px = 9.25", minus radii ≈ 7.99")
	var far = _make_unit("U_FAR", 1, ["INFANTRY"], [Vector2(origin_x + 370.0, y)])
	return {"U_CHG": charger, "U_NEAR": near, "U_FAR": far}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_multitarget_reachability ===")
	var prev_edition = GameConstants.edition

	_test_per_target_decomposition()
	_test_10e_overdeclare_fails()
	_test_10e_reaches_all_succeeds()
	_test_11e_drops_unreachable_and_reports()

	GameConstants.edition = prev_edition
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

# -- The per-target decomposition the verdict is built on --
func _test_per_target_decomposition() -> void:
	print("\n-- _per_target_charge_requirements: near reachable, far not --")
	GameConstants.edition = 10  # ER = 1"
	_setup_state(_three_unit_state(700.0, 2150.0))
	_tm().terrain_features.clear()
	var phase = _new_phase()

	var reqs = phase._per_target_charge_requirements("U_CHG", ["U_NEAR", "U_FAR"], 3.0)
	_check("near target present in decomposition", reqs.has("U_NEAR"))
	_check("far target present in decomposition", reqs.has("U_FAR"))
	_check("near reachable with a 3\" roll", reqs.get("U_NEAR", {}).get("reachable", false),
		"required=%.2f" % float(reqs.get("U_NEAR", {}).get("required", -1)))
	_check("far NOT reachable with a 3\" roll", not reqs.get("U_FAR", {}).get("reachable", true),
		"required=%.2f" % float(reqs.get("U_FAR", {}).get("required", -1)))
	# far edge ≈ 8", ER 1" -> ~7" needed
	var far_req = float(reqs.get("U_FAR", {}).get("required", 0.0))
	_check("far required ≈ 7\" (edge 8\" − 1\" ER)", far_req > 6.5 and far_req < 7.5, "required=%.2f" % far_req)
	phase.queue_free()

# -- 10e: declaring a target you can't reach FAILS the whole charge (no false SUCCESS) --
func _test_10e_overdeclare_fails() -> void:
	print("\n-- 10e: over-declared charge FAILS, names the unreachable target --")
	GameConstants.edition = 10
	_setup_state(_three_unit_state(700.0, 2150.0))
	_tm().terrain_features.clear()
	_event_log().clear()
	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {
		"targets": ["U_NEAR", "U_FAR"],
		"declared_targets": ["U_NEAR", "U_FAR"],
		"distance": 3,
		"dice_rolls": [2, 1],
	}
	var result = phase._resolve_charge_roll("U_CHG")

	_check("charge reported FAILED", result.get("charge_failed", false) == true,
		str(result.get("charge_failed", "missing")))
	_check("structured failure recorded", phase.failed_charge_attempts.size() == 1,
		"count=%d" % phase.failed_charge_attempts.size())
	var detail := ""
	if phase.failed_charge_attempts.size() > 0:
		var errs = phase.failed_charge_attempts[0].get("errors", [])
		detail = str(errs[0]) if errs.size() > 0 else ""
	_check("failure names the unreachable target (U_FAR)", detail.find("U_FAR") != -1, detail)
	_check("failure explains ALL-targets rule", detail.to_lower().find("all") != -1, detail)
	_check("pending charge cleaned up (cannot retry)", not phase.pending_charges.has("U_CHG"))

	var found_fail_entry := false
	for e in _event_log().get_all_entries():
		var t = str(e.get("text", e))
		if t.find("FAILED") != -1 and t.find("U_FAR") != -1:
			found_fail_entry = true
			break
	_check("player-visible FAILED entry names U_FAR", found_fail_entry)
	phase.queue_free()

# -- 10e: reaching every declared target still SUCCEEDS --
func _test_10e_reaches_all_succeeds() -> void:
	print("\n-- 10e: a roll reaching ALL declared targets SUCCEEDS --")
	GameConstants.edition = 10
	_setup_state(_three_unit_state(700.0, 2150.0))
	_tm().terrain_features.clear()
	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {
		"targets": ["U_NEAR", "U_FAR"],
		"declared_targets": ["U_NEAR", "U_FAR"],
		"distance": 10,  # far needs ~7", near ~1.5" -> both reachable
		"dice_rolls": [5, 5],
	}
	var result = phase._resolve_charge_roll("U_CHG")
	_check("charge NOT failed when all targets reachable", result.get("charge_failed", true) == false,
		str(result.get("charge_failed", "missing")))
	_check("no structured failure recorded", phase.failed_charge_attempts.size() == 0,
		"count=%d" % phase.failed_charge_attempts.size())
	_check("pending charge retained for the move step", phase.pending_charges.has("U_CHG"))
	phase.queue_free()

# -- 11e: unreachable declared targets are dropped, and the drop is surfaced --
func _test_11e_drops_unreachable_and_reports() -> void:
	print("\n-- 11e: subset charge drops far target and REPORTS it --")
	GameConstants.edition = 11  # ER = 2"
	_setup_state(_three_unit_state(700.0, 2150.0))
	_tm().terrain_features.clear()
	_event_log().clear()
	var phase = _new_phase()
	phase.pending_charges["U_CHG"] = {
		"targets": ["U_NEAR", "U_FAR"],
		"declared_targets": ["U_NEAR", "U_FAR"],
		"distance": 3,
		"dice_rolls": [2, 1],
	}
	var result = phase._resolve_charge_roll("U_CHG")
	_check("11e subset charge SUCCEEDS (not failed)", result.get("charge_failed", true) == false,
		str(result.get("charge_failed", "missing")))
	# far target dropped from the active target set, near retained
	var kept = phase.pending_charges.get("U_CHG", {}).get("targets", [])
	_check("far target dropped from active targets", not ("U_FAR" in kept), str(kept))
	_check("near target retained", "U_NEAR" in kept, str(kept))

	var found_partial := false
	for e in _event_log().get_all_entries():
		var t = str(e.get("text", e))
		if t.find("reaches") != -1 and t.find("U_FAR") != -1 and t.find("beyond") != -1:
			found_partial = true
			break
	_check("player-visible partial-charge entry names dropped U_FAR", found_partial)
	phase.queue_free()
