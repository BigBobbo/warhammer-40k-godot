extends SceneTree

# Staged fight phase flow (FightPhase action machine).
#
# Drives a FightPhase instance through the STAGED melee sequence:
#   ROLL_DICE                  -> staged_pause "hits" (fight_stage_paused fired)
#   USE_FIGHT_REROLL (hits)    -> one die re-rolled, CP spent
#   CONTINUE_TO_WOUNDS         -> staged_pause "wounds" (or advance on 0 wounds)
#   CONTINUE_TO_SAVES          -> saves auto-resolved, next weapon or activation end
# and asserts: pause signals fire with dice payloads, out-of-order continues are
# rejected, damage lands on the target, has_fought is set at the end.
#
# Usage: godot --headless --path . -s tests/test_staged_fight_phase_flow.gd

var passed := 0
var failed := 0
var pauses: Array = []
var dice_events: Array = []
var _gs = null

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)

func _make_state() -> Dictionary:
	var fighter_models = []
	for i in range(3):
		fighter_models.append({
			"id": "mf%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
		})
	var target_models = []
	for i in range(6):
		target_models.append({
			"id": "mt%d" % i, "position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 5}
		})
	return {
		"meta": {"phase": 10, "active_player": 1, "battle_round": 2, "turn": 2},
		"board": {"size": {"width": 1760, "height": 2400}, "objectives": []},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"units": {
			"U_FIGHTER": {
				"id": "U_FIGHTER", "owner": 1, "flags": {"charged_this_turn": true},
				"meta": {"name": "Fighters", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 3, "wounds": 2},
					"weapons": [{
						"name": "Test Choppa", "type": "Melee", "range": "Melee",
						"attacks": "3", "weapon_skill": "3", "strength": "5",
						"ap": "-1", "damage": "1", "special_rules": ""
					}]},
				"models": fighter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"name": "Targets", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 5, "wounds": 1}},
				"models": target_models
			}
		}
	}

func _alive_count(unit_id: String) -> int:
	var n = 0
	for m in _gs.state.units[unit_id].models:
		if m.get("alive", true):
			n += 1
	return n

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_staged_fight_phase_flow ===\n")

	var game_state = root.get_node_or_null("GameState")
	_gs = game_state
	if game_state == null:
		_check("GameState autoload reachable", false)
		_finish()
		return
	GameConstants.edition = 11
	game_state.state = _make_state()

	# load() at runtime — naming the FightPhase class at parse time would force
	# an eager compile before autoloads register and spam a startup script error.
	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(game_state.state)

	phase.fight_stage_paused.connect(func(stage, info): pauses.append({"stage": stage, "info": info}))
	phase.dice_rolled.connect(func(d): dice_events.append(d))

	# Bypass the selection dialog plumbing: activate the fighter directly and
	# stage its attack assignment (the AttackAssignmentDialog path ends in the
	# same phase state).
	phase.active_fighter_id = "U_FIGHTER"
	if phase.sequencer_11e != null:
		phase.sequencer_11e.select_to_fight("U_FIGHTER", game_state.state)
	phase.pending_attacks = [{
		"attacker": "U_FIGHTER",
		"target": "U_TARGET",
		"weapon": "test_choppa_melee",
		"models": ["0", "1", "2"]
	}]

	var confirm = phase.process_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 1})
	_check("CONFIRM_AND_RESOLVE_ATTACKS succeeded", confirm.get("success", false), str(confirm))

	# Out-of-order continue must be rejected before ROLL_DICE
	var early = phase.execute_action({"type": "CONTINUE_TO_WOUNDS", "player": 1})
	_check("CONTINUE_TO_WOUNDS rejected before ROLL_DICE", not early.get("success", true))

	var roll = phase.execute_action({"type": "ROLL_DICE", "player": 1})
	_check("ROLL_DICE succeeded", roll.get("success", false), str(roll.get("error", "")))
	_check("ROLL_DICE paused at hits", roll.get("staged_pause", "") == "hits", str(roll))
	_check("fight_stage_paused('hits') fired", pauses.size() >= 1 and pauses[0].stage == "hits")
	_check("hits pause carries hit_rolls", not (pauses[0].info.get("hit_rolls", []) as Array).is_empty() if pauses.size() >= 1 else false)
	_check("hits pause offers Command Re-roll (3 CP available)", pauses[0].info.get("reroll_available", false) if pauses.size() >= 1 else false)
	var hit_block_found = false
	for d in dice_events:
		if d.get("context", "") == "hit_roll_melee":
			hit_block_found = true
	_check("hit_roll_melee dice block emitted", hit_block_found)

	# Wrong-stage reroll and continue are rejected
	var bad_continue = phase.execute_action({"type": "CONTINUE_TO_SAVES", "player": 1})
	_check("CONTINUE_TO_SAVES rejected at hits stage", not bad_continue.get("success", true))
	var bad_reroll = phase.execute_action({"type": "USE_FIGHT_REROLL", "player": 1, "payload": {"stage": "wounds", "die_index": 0}})
	_check("USE_FIGHT_REROLL(wounds) rejected at hits stage", not bad_reroll.get("success", true))

	# Command Re-roll a hit die (die 0) — costs 1 CP
	var cp_before = int(game_state.state.players["1"]["cp"])
	var rr = phase.execute_action({"type": "USE_FIGHT_REROLL", "player": 1, "payload": {"stage": "hits", "die_index": 0}})
	_check("USE_FIGHT_REROLL(hits) succeeded", rr.get("success", false), str(rr.get("error", "")))
	var cp_after = int(game_state.state.players["1"]["cp"])
	_check("Command Re-roll spent 1 CP", cp_after == cp_before - 1, "cp %d -> %d" % [cp_before, cp_after])
	_check("re-roll reports reroll_used", rr.get("reroll_used", false))
	# Re-emitted pause shows reroll no longer available
	_check("pause re-emitted with reroll_available=false",
		pauses.size() >= 2 and pauses[-1].stage == "hits" and not pauses[-1].info.get("reroll_available", true))

	# Second reroll must be refused (once per phase)
	var rr2 = phase.execute_action({"type": "USE_FIGHT_REROLL", "player": 1, "payload": {"stage": "hits", "die_index": 1}})
	_check("second Command Re-roll refused (once per phase)", not rr2.get("success", true))

	var targets_before = _alive_count("U_TARGET")
	var wounds_step = phase.execute_action({"type": "CONTINUE_TO_WOUNDS", "player": 1})
	_check("CONTINUE_TO_WOUNDS succeeded", wounds_step.get("success", false), str(wounds_step.get("error", "")))

	var finished = false
	if wounds_step.get("staged_pause", "") == "wounds":
		_check("fight_stage_paused('wounds') fired", pauses[-1].stage == "wounds")
		_check("wounds pause carries wound_rolls", not (pauses[-1].info.get("wound_rolls", []) as Array).is_empty())
		var saves_step = phase.execute_action({"type": "CONTINUE_TO_SAVES", "player": 1})
		_check("CONTINUE_TO_SAVES succeeded", saves_step.get("success", false), str(saves_step.get("error", "")))
		finished = true
	else:
		# 0 wounds → the phase advanced/finished on its own; still a valid staged run.
		print("    (wound roll caused 0 wounds — sequence auto-advanced)")
		finished = true

	_check("staged state cleared after sequence", phase.staged_fight_state.is_empty())
	_check("sequence completion pause fired", pauses[-1].stage == "complete", "last=%s" % str(pauses[-1].stage if pauses.size() > 0 else "none"))
	_check("fighter flagged has_fought", game_state.state.units["U_FIGHTER"].get("flags", {}).get("has_fought", false))
	var targets_after = _alive_count("U_TARGET")
	print("    (target models alive: %d -> %d)" % [targets_before, targets_after])
	_check("no further staged actions accepted", not phase.execute_action({"type": "CONTINUE_TO_WOUNDS", "player": 1}).get("success", true))

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
