extends SceneTree

# 11e 20.04 INGRESS MOVE — "Before the Third Battle Round: while doing so, no
# models can be set up within your opponent's deployment zone."
#
# The rule the player kept beating: arriving from Strategic Reserves in battle
# round 2 along the OPPONENT'S board edge. That strip is within 6" of a
# battlefield edge, so every other ingress check passes it — only the
# opponent-deployment-zone ban stops it, and DeploymentController's placement
# validator never applied that ban (the ghost stayed green and models dropped;
# MovementPhase only rejected the whole set-up on confirm).
#
# Covers, over the REAL MovementPhase._validate_place_reinforcement:
#   ▪ 11e path (IngressMove template) rejects a centre inside the opponent DZ
#   ▪ ...and a base merely OVERHANGING the zone boundary ("within", not
#     "wholly within") — the base-aware test
#   ▪ Deep Strike (24.09) is exempt: it may arrive in the opponent's DZ
#   ▪ from battle round 3 the ban lifts
#   ▪ own-side edge stays legal throughout
#   ▪ the legacy (10e) path enforces the same ban
# plus the shared GameState helpers both the engine and the UI now go through.
#
# Usage: godot --headless --path . -s tests/test_reserve_opponent_dz_11e.gd

var passed := 0
var failed := 0
var _ran := false

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.2).timeout.connect(_run_tests)

const PX := 40.0

func _seed(gs, base_mm: int = 32) -> void:
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["active_player"] = 1
	gs.state["units"] = {
		"U_RES": {"id": "U_RES", "owner": 1, "status": 7,
			"reserve_type": "strategic_reserves", "flags": {"in_reserves": true},
			# Deep Strike so the 24.09 exemption below can actually be exercised
			# (the P2-80 placement_type override refuses units that lack it).
			"meta": {"name": "Reserve Squad", "keywords": ["INFANTRY"], "stats": {"move": 6},
				"abilities": [{"name": "Deep Strike"}]},
			"models": [{"id": "m0", "alive": true, "base_mm": base_mm,
				"base_type": "circular", "position": null}]},
		# Enemy parked mid-board so it never interferes with the 8"/9" bubble.
		"U_FOE": {"id": "U_FOE", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"], "stats": {"move": 6}},
			"models": [{"id": "e0", "alive": true, "base_mm": 32,
				"base_type": "circular", "position": {"x": 220.0, "y": 1200.0}}]},
	}

func _place(mp, x_in: float, y_in: float, placement_type: String = "") -> Dictionary:
	var action := {
		"type": "PLACE_REINFORCEMENT",
		"unit_id": "U_RES",
		"model_positions": [{"x": x_in * PX, "y": y_in * PX}],
		"model_rotations": [0.0],
	}
	if placement_type != "":
		action["placement_type"] = placement_type
	return mp.validate_action(action)

func _rejected_for_dz(res: Dictionary) -> bool:
	for e in res.get("errors", []):
		if "deployment zone" in str(e):
			return true
	return false

func _run_tests():
	if _ran:
		return
	_ran = true
	print("\n=== test_reserve_opponent_dz_11e ===\n")

	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_check("GameState autoload reachable", false)
		_finish()
		return

	var prev_edition: int = gs.get_edition()
	gs.initialize_default_state("hammer_anvil")

	print("-- shared helpers --")
	# hammer_anvil: P1 owns y 0..18", P2 owns y 42..60" — so P2's DZ reaches
	# 18" in from their board edge, swallowing the whole 6" arrival band there.
	var p2_px = gs.get_deployment_zone_poly_px(2)
	_check("get_deployment_zone_poly_px returns px, not inches",
		p2_px.size() == 4 and p2_px[0].y == 42.0 * PX, str(p2_px))
	_check("ban applies in battle round 2", gs.ingress_opponent_dz_ban_applies(2, false))
	_check("ban lifts in battle round 3", not gs.ingress_opponent_dz_ban_applies(3, false))
	_check("Deep Strike is exempt (24.09)", not gs.ingress_opponent_dz_ban_applies(2, true))

	_seed(gs)
	var mp = load("res://phases/MovementPhase.gd").new()
	root.add_child(mp)
	mp.enter_phase(gs.create_snapshot())

	print("\n-- 11e ingress template (20.04) --")
	gs.set_edition(11)

	var v = _place(mp, 22.0, 58.0)
	_check("BR2, centre inside opponent DZ: REJECTED", not v.get("valid", true) and _rejected_for_dz(v), str(v.get("errors")))

	v = _place(mp, 22.0, 2.0)
	_check("BR2, own-side board edge: legal", v.get("valid", false), str(v.get("errors")))

	# Base-aware boundary pair, both set up in the LEFT 6" band (x = 2") so the
	# only thing that can differ between them is the deployment-zone test.
	# A 32mm base is ~0.63" in radius and P2's zone starts at y = 42.0":
	#   centre 41.7" -> base reaches 42.33", i.e. INSIDE the zone. 20.04 says
	#   "within", not "wholly within", so this is an illegal set-up even though
	#   the centre dot is clear of the line.
	v = _place(mp, 2.0, 41.7)
	_check("BR2, base overhangs the DZ boundary: REJECTED (base-aware)",
		not v.get("valid", true) and _rejected_for_dz(v), str(v.get("errors")))

	#   centre 41.0" -> base reaches 41.63", wholly clear of the zone. Legal —
	#   this guards the check against becoming a blanket ban near the line.
	v = _place(mp, 2.0, 41.0)
	_check("BR2, base wholly clear of the DZ boundary: legal", v.get("valid", false), str(v.get("errors")))

	print("\n-- Deep Strike relaxation (24.09) --")
	v = _place(mp, 22.0, 58.0, "deep_strike")
	_check("BR2, Deep Strike into opponent DZ: legal", v.get("valid", false), str(v.get("errors")))

	print("\n-- the ban lifts from battle round 3 --")
	gs.state["meta"]["battle_round"] = 3
	mp.enter_phase(gs.create_snapshot())
	v = _place(mp, 22.0, 58.0)
	_check("BR3, same spot inside opponent DZ: legal", v.get("valid", false), str(v.get("errors")))

	print("\n-- legacy (10e) path enforces the same ban --")
	gs.set_edition(10)
	gs.state["meta"]["battle_round"] = 2
	mp.enter_phase(gs.create_snapshot())
	v = _place(mp, 22.0, 58.0)
	_check("10e, BR2, inside opponent DZ: REJECTED", not v.get("valid", true) and _rejected_for_dz(v), str(v.get("errors")))
	v = _place(mp, 22.0, 2.0)
	_check("10e, BR2, own-side board edge: legal", v.get("valid", false), str(v.get("errors")))

	gs.set_edition(prev_edition)
	mp.queue_free()
	_finish()

func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
