extends SceneTree

# Reported bug: Deep Striking a bodyguard squad with an attached CHARACTER
# (Custodian Guard + Blade Champion) let the player place the squad's models but
# never the leader's. The placement UI sized its session off the bodyguard alone,
# and MovementPhase silently teleported the leader to
# `first_bodyguard_model + 1"` — inside the squad's bases, and with NONE of the
# set-up rules (03.02 overlap, 20.04/24.09 ingress distances) ever applied to it.
#
# The UI half is covered by the windowed scenario
# tests/scenarios/sp/deep_strike_attached_character_placement.json. This file
# covers the phase half, which is pure state:
#   1. `character_model_positions` from the placement UI are honoured verbatim.
#   2. The leader's models are validated by the same rules as the squad's —
#      overlapping the board, or landing inside the enemy exclusion, is rejected.
#   3. Arrivals with NO leader positions (AI / scripted) auto-place the leader
#      CLEAR of the squad instead of stacking it on the first model.
#
# Usage: godot --headless --path . -s tests/test_reinforcement_attached_character_11e.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _init():
	create_timer(0.2).timeout.connect(_run)

func _guard_model(id: String) -> Dictionary:
	return {"id": id, "alive": true, "wounds": 3, "current_wounds": 3,
		"base_mm": 40, "base_type": "circular", "position": null}

func _seed_state(gs) -> void:
	gs.state["meta"] = {
		"phase": GameStateData.Phase.MOVEMENT,
		"battle_round": 2,
		"turn_number": 2,
		"active_player": 1,
		"game_config": {"player1_type": "HUMAN", "player2_type": "HUMAN"}
	}
	gs.state["board"] = {
		"size": {"width": 44, "height": 60},
		"terrain": [],
		"deployment_zones": [
			{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 12}, {"x": 0, "y": 12}]},
			{"player": 2, "poly": [{"x": 0, "y": 48}, {"x": 44, "y": 48}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]}
		]
	}
	gs.state["players"] = {"1": {"cp": 3}, "2": {"cp": 3}}
	gs.state["units"] = {
		# The Attached unit: a 3-model Custodian Guard squad led by a Blade
		# Champion, both in Deep Strike reserves.
		"U_GUARD": {"id": "U_GUARD", "owner": 1, "status": GameStateData.UnitStatus.IN_RESERVES,
			"flags": {"in_reserves": true}, "reserve_type": "deep_strike",
			"attachment_data": {"attached_characters": ["U_CHAMPION"]},
			"meta": {"name": "Custodian Guard", "keywords": ["ADEPTUS CUSTODES", "INFANTRY"], "abilities": [],
				"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3, "objective_control": 2}},
			"models": [_guard_model("m1"), _guard_model("m2"), _guard_model("m3")]},
		"U_CHAMPION": {"id": "U_CHAMPION", "owner": 1, "status": GameStateData.UnitStatus.IN_RESERVES,
			"flags": {"in_reserves": true}, "reserve_type": "deep_strike",
			"attached_to": "U_GUARD",
			"meta": {"name": "Blade Champion", "keywords": ["ADEPTUS CUSTODES", "INFANTRY", "CHARACTER"], "abilities": [],
				"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 6, "objective_control": 1}},
			"models": [_guard_model("c1")]},
		# A far-away enemy so a mid-board arrival clears the >8"/9" gates.
		"U_ENEMY": {"id": "U_ENEMY", "owner": 2, "status": GameStateData.UnitStatus.DEPLOYED, "flags": {},
			"meta": {"name": "Enemy", "keywords": ["INFANTRY"], "abilities": [],
				"stats": {"move": 6, "toughness": 4, "save": 4, "wounds": 1, "objective_control": 2}},
			"models": [{"id": "m1", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": {"x": 200.0, "y": 2300.0}}]}
	}

# The squad lands as a triangle around (740, 1200); the leader's own spot is
# passed separately, exactly as Main._split_placement_positions builds it.
const SQUAD := [Vector2(700, 1200), Vector2(780, 1200), Vector2(740, 1130)]

func _action(squad: Array, champion_positions = null) -> Dictionary:
	var a := {"type": "PLACE_REINFORCEMENT", "unit_id": "U_GUARD",
		"model_positions": squad, "model_rotations": [0.0, 0.0, 0.0], "player": 1}
	if champion_positions != null:
		a["character_model_positions"] = {"U_CHAMPION": champion_positions}
		a["character_model_rotations"] = {"U_CHAMPION": [0.0]}
	return a

func _champion_pos(gs) -> Variant:
	var p = gs.state["units"]["U_CHAMPION"]["models"][0].get("position", null)
	if p == null:
		return null
	return Vector2(float(p.x), float(p.y))

func _reset_arrival(gs) -> void:
	for uid in ["U_GUARD", "U_CHAMPION"]:
		gs.state["units"][uid]["status"] = GameStateData.UnitStatus.IN_RESERVES
		gs.state["units"][uid]["flags"] = {"in_reserves": true}
		for m in gs.state["units"][uid]["models"]:
			m["position"] = null

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_reinforcement_attached_character_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	if gs == null or pm == null:
		_check("autoloads present", false)
		_finish()
		return
	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	_seed_state(gs)
	pm.transition_to_phase(GameStateData.Phase.MOVEMENT)
	var phase = pm.get_current_phase_instance()
	if phase == null:
		_check("movement phase instance", false)
		GameConstants.edition = prev_edition
		gs.state = prev_state
		_finish()
		return

	# Measurement is an autoload node, not a global class — resolve it at runtime.
	var meas = root.get_node_or_null("Measurement")

	print("-- the leader's placed position is honoured --")
	var chosen := Vector2(740, 1270)
	var va = phase.validate_action(_action(SQUAD, [chosen]))
	_check("a legal arrival with a placed leader is accepted", va.get("valid", false),
		str(va.get("errors", [])))
	phase.execute_action(_action(SQUAD, [chosen]))
	_check("the leader landed exactly where the player put it",
		_champion_pos(gs) == chosen, str(_champion_pos(gs)))
	_check("the leader is DEPLOYED, not left behind in reserves",
		int(gs.state["units"]["U_CHAMPION"]["status"]) == GameStateData.UnitStatus.DEPLOYED)
	var champ_model = gs.state["units"]["U_CHAMPION"]["models"][0]
	var clear_of_squad := true
	for m in gs.state["units"]["U_GUARD"]["models"]:
		if meas.models_overlap(champ_model, m):
			clear_of_squad = false
	_check("the leader does not overlap the squad it arrived with", clear_of_squad)

	print("\n-- the leader is validated like every other arriving model --")
	_reset_arrival(gs)
	var on_squad = phase.validate_action(_action(SQUAD, [Vector2(700, 1200)]))
	_check("a leader placed on top of its own squad is rejected", not on_squad.get("valid", true),
		str(on_squad.get("errors", [])))
	var near_enemy = phase.validate_action(_action(SQUAD, [Vector2(240, 2300)]))
	_check("a leader inside the enemy exclusion is rejected", not near_enemy.get("valid", true),
		str(near_enemy.get("errors", [])))
	var off_board = phase.validate_action(_action(SQUAD, [Vector2(-50, 1200)]))
	_check("a leader off the battlefield is rejected", not off_board.get("valid", true),
		str(off_board.get("errors", [])))

	print("\n-- AI / scripted arrivals auto-place the leader clear of the squad --")
	_reset_arrival(gs)
	# No character_model_positions at all — the old code dropped the leader at
	# squad_model_0 + 1" (740, 1200), i.e. inside both front guards.
	phase.execute_action(_action(SQUAD))
	var auto_pos = _champion_pos(gs)
	_check("the leader still arrives when no position was supplied", auto_pos != null)
	_check("the auto spot is NOT the old first-model + 1\" offset",
		auto_pos != Vector2(740, 1200), str(auto_pos))
	champ_model = gs.state["units"]["U_CHAMPION"]["models"][0]
	var auto_clear := true
	for m in gs.state["units"]["U_GUARD"]["models"]:
		if meas.models_overlap(champ_model, m):
			auto_clear = false
	_check("the auto-placed leader is clear of every squad base", auto_clear, str(auto_pos))

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
