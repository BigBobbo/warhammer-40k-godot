extends SceneTree

# ENEMY SWING BACK: the AI's melee is rolled out through the staged dock.
#
# Reported against the T6 tutorial (2026-07-30): when the Custodian Guard swung
# back, "it skipped the actual rolling" — the AI's attacks resolved hits AND
# wounds in one shot and the player was handed a finished "20 wound(s) to save"
# prompt, with the rolls dumped into the log all at once. The player's OWN
# attacks slow-roll (hit pause → wound pause → saves), so the enemy's should too.
#
# FightPhase now stages an AI attacker whenever the human defender is about to
# roll their own saves. This test pins the gate and the pauses:
#   * AI attacker + human defender + interactive saves  -> stages
#   * AI attacker + AI defender / auto-allocated saves  -> one-shot (unchanged)
#   * no Command Re-roll is ever offered on the AI's dice
#   * ROLL_DICE pauses at "hits", CONTINUE_TO_WOUNDS pauses at "wounds",
#     CONTINUE_TO_SAVES hands the batch to the defender's overlay
#   * AIPlayer reports the pause as a human window, so the AI idles instead of
#     racing the player's dock (that would have made the reveal unwatchable)
#
# Usage: godot --headless --path . -s tests/test_enemy_swing_staged_11e.gd

var passed := 0
var failed := 0
var pauses: Array = []
var saves_required_batches: Array = []


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


# Player 2 (the AI) swings at player 1's mob, in base contact.
func _make_state() -> Dictionary:
	var enemy_models := []
	for i in range(3):
		enemy_models.append({
			"id": "me%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 2, "current_wounds": 2
		})
	var mine_models := []
	for i in range(6):
		mine_models.append({
			"id": "mm%d" % i, "position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 5}
		})
	return {
		"meta": {"phase": 10, "active_player": 1, "battle_round": 2, "turn": 2},
		"board": {"size": {"width": 1760, "height": 2400}, "objectives": []},
		"players": {"1": {"cp": 3, "vp": 0}, "2": {"cp": 3, "vp": 0}},
		"units": {
			"U_ENEMY": {
				"id": "U_ENEMY", "owner": 2, "flags": {},
				"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"],
					"stats": {"toughness": 6, "save": 2, "wounds": 2},
					"weapons": [{
						"name": "Test Spear", "type": "Melee", "range": "Melee",
						"attacks": "3", "weapon_skill": "2", "strength": "7",
						"ap": "-2", "damage": "1", "special_rules": ""
					}]},
				"models": enemy_models
			},
			"U_MINE": {
				"id": "U_MINE", "owner": 1, "flags": {},
				"meta": {"name": "Boyz", "keywords": ["INFANTRY"],
					"stats": {"toughness": 4, "save": 5, "wounds": 1}},
				"models": mine_models
			}
		}
	}


func _arm_ai_attacker(phase, game_state) -> void:
	phase.active_fighter_id = "U_ENEMY"
	if phase.sequencer_11e != null:
		phase.sequencer_11e.select_to_fight("U_ENEMY", game_state.state)
	phase.pending_attacks = [{
		"attacker": "U_ENEMY",
		"target": "U_MINE",
		"weapon": "test_spear_melee",
		"models": ["0", "1", "2"]
	}]


func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_enemy_swing_staged_11e ===\n")

	var game_state = root.get_node_or_null("GameState")
	var ai_player = root.get_node_or_null("AIPlayer")
	var settings = root.get_node_or_null("SettingsService")
	if game_state == null or ai_player == null:
		_check("GameState + AIPlayer autoloads reachable", false)
		_finish()
		return
	GameConstants.edition = 11
	game_state.state = _make_state()

	# Player 2 is the AI, player 1 the human — the reported configuration.
	ai_player.configure({1: "HUMAN", 2: "AI"})
	_check("AIPlayer enabled with player 2 as AI",
		ai_player.enabled and ai_player.is_ai_player(2) and not ai_player.is_ai_player(1))
	if settings != null:
		settings.auto_allocate_wounds = false

	# load() at runtime — naming FightPhase at parse time forces an eager
	# compile before autoloads register.
	var phase = load("res://phases/FightPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(game_state.state)
	phase.fight_stage_paused.connect(func(stage, info): pauses.append({"stage": stage, "info": info}))
	phase.saves_required.connect(func(batch): saves_required_batches.append(batch))

	_arm_ai_attacker(phase, game_state)

	# --- the gate -----------------------------------------------------------
	_check("AI attacker stages while the human defender rolls their own saves",
		phase._should_stage_fight({}, true))
	_check("AI attacker does NOT stage when saves are auto-allocated",
		not phase._should_stage_fight({}, false))
	_check("explicit fast_roll still bypasses staging",
		not phase._should_stage_fight({"payload": {"fast_roll": true}}, true))
	_check("no Command Re-roll offered on the AI's own dice",
		not phase._fight_reroll_available())

	# --- the staged sequence ------------------------------------------------
	var confirm = phase.process_action({"type": "CONFIRM_AND_RESOLVE_ATTACKS", "player": 2})
	_check("CONFIRM_AND_RESOLVE_ATTACKS succeeded", confirm.get("success", false), str(confirm))

	# FightController asks this from `fighting_begun`, i.e. once CONFIRM has
	# moved pending_attacks into confirmed_attacks — the defender is only
	# knowable from the confirmed assignments.
	_check("fight_activation_will_stage() agrees (defender is human)",
		phase.fight_activation_will_stage())

	# AIPlayer reads the live phase off PhaseManager; this harness builds the
	# phase directly, so point it at ours for the window checks below.
	if root.get_node_or_null("PhaseManager") != null:
		root.get_node("PhaseManager").current_phase_instance = phase

	var roll = phase.execute_action({"type": "ROLL_DICE", "player": 2})
	_check("ROLL_DICE succeeded", roll.get("success", false), str(roll.get("error", "")))
	_check("the enemy's hit roll PAUSES instead of resolving through to saves",
		roll.get("staged_pause", "") == "hits", str(roll))
	_check("fight_stage_paused('hits') fired with the rolls",
		pauses.size() >= 1 and pauses[0].stage == "hits" \
			and not (pauses[0].info.get("hit_rolls", []) as Array).is_empty())
	_check("hits pause withholds Command Re-roll (not the player's dice)",
		pauses.size() >= 1 and not pauses[0].info.get("reroll_available", true))

	# AIPlayer must treat the pause as the human's window and idle on it.
	_check("AIPlayer reports the hits pause as the human defender's window",
		ai_player._staged_melee_reveal_defender(phase) == 1,
		"got %d" % ai_player._staged_melee_reveal_defender(phase))
	_check("AIPlayer._human_defender_window_pending() -> player 1 (AI waits)",
		ai_player._human_defender_window_pending() == 1)

	var wounds_step = phase.execute_action({"type": "CONTINUE_TO_WOUNDS", "player": 1})
	_check("CONTINUE_TO_WOUNDS succeeded (the human advances the reveal)",
		wounds_step.get("success", false), str(wounds_step.get("error", "")))
	if wounds_step.get("staged_pause", "") == "wounds":
		_check("the enemy's wound roll pauses too", pauses[-1].stage == "wounds")
		_check("wounds pause withholds Command Re-roll",
			not pauses[-1].info.get("reroll_available", true))
		_check("AIPlayer still idles at the wounds pause",
			ai_player._staged_melee_reveal_defender(phase) == 1)

		var saves_step = phase.execute_action({"type": "CONTINUE_TO_SAVES", "player": 1})
		_check("CONTINUE_TO_SAVES succeeded", saves_step.get("success", false), str(saves_step.get("error", "")))
		_check("the defender is asked for their saves (overlay batch emitted)",
			saves_step.get("awaiting_melee_saves", false) and not saves_required_batches.is_empty(),
			str(saves_step))
		_check("no reveal window while the save overlay owns the decision",
			ai_player._staged_melee_reveal_defender(phase) == 0)
	else:
		# Every attack missed or failed to wound — the sequence auto-advanced,
		# which is still a valid staged run (nothing to save against).
		print("    (0 wounds caused — sequence auto-advanced past the saves step)")
		_check("staged sequence completed without a saves batch",
			pauses[-1].stage == "complete")

	# --- a human attacker is untouched -------------------------------------
	# Flip ownership so U_ENEMY belongs to the human and U_MINE to the AI: the
	# player's own melee must still stage AND still be offered Command Re-roll.
	game_state.state.units["U_MINE"]["owner"] = 2
	game_state.state.units["U_ENEMY"]["owner"] = 1
	var phase2 = load("res://phases/FightPhase.gd").new()
	root.add_child(phase2)
	phase2.enter_phase(game_state.state)
	phase2.active_fighter_id = "U_ENEMY"
	phase2.confirmed_attacks = [{"attacker": "U_ENEMY", "target": "U_MINE", "weapon": "test_spear_melee"}]
	_check("a HUMAN attacker still stages (unchanged behaviour)",
		phase2._should_stage_fight({}, true))
	_check("Command Re-roll is still offered to a human attacker",
		phase2._fight_reroll_available())
	_check("a HUMAN attacker stages even against an AI defender (own merit, not the reveal gate)",
		phase2._should_stage_fight({}, false) and phase2.fight_activation_will_stage())

	_finish()


func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
