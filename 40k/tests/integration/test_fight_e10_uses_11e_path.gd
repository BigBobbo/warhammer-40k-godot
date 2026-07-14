extends "res://addons/gut/test.gd"

# Slice-2 regression guard (Fight 10e→11e cleanup):
# The Fight phase is now 11e-only — the `GameConstants.edition >= 11` gates in
# FightPhase.gd were collapsed to always take the 11e branch. This is a no-op at
# edition 11 (players + the migrated tests already took it); the only path that
# changes is edition 10, which now runs the 11e FightSequencer / global Pile In /
# global Consolidate steps unconditionally. This test drives the fight phase at
# edition 10 and asserts it enters and walks END_FIGHT to completion on the 11e
# path without error.

const FightPhaseScript = preload("res://phases/FightPhase.gd")

var _prev_edition := 11
var _phases: Array = []

func before_each():
	_prev_edition = GameConstants.edition
	GameConstants.edition = 10

func after_each():
	for p in _phases:
		if is_instance_valid(p):
			p.queue_free()
	_phases.clear()
	GameConstants.edition = _prev_edition

func _make_phase(state: Dictionary) -> Node:
	var phase_node = Node.new()
	phase_node.set_script(FightPhaseScript)
	add_child(phase_node)
	_phases.append(phase_node)
	phase_node.game_state_snapshot = GameState.create_snapshot()
	phase_node.enter_phase(state)
	return phase_node

func _state_no_combat() -> Dictionary:
	# Two units far apart — no engagement, so no combats.
	return {
		"meta": {"phase": GameStateData.Phase.FIGHT, "active_player": 1, "turn_number": 1, "battle_round": 1},
		"board": {"objectives": []},
		"units": {
			"u1": {"id": "u1", "owner": 1, "meta": {"name": "A", "keywords": []}, "flags": {}, "status_effects": {},
				"models": [{"id": "m1", "alive": true, "position": {"x": 100, "y": 100}, "base_mm": 32, "wounds": 1, "current_wounds": 1}]},
			"u2": {"id": "u2", "owner": 2, "meta": {"name": "B", "keywords": []}, "flags": {}, "status_effects": {},
				"models": [{"id": "m1", "alive": true, "position": {"x": 4000, "y": 4000}, "base_mm": 32, "wounds": 1, "current_wounds": 1}]}
		}
	}

func test_edition_10_fight_takes_the_11e_path():
	GameState.state = _state_no_combat()
	var fp = _make_phase(GameState.state)
	# The FightSequencer is now created unconditionally (was gated on edition >= 11).
	assert_not_null(fp.sequencer_11e,
		"sequencer_11e must be created at edition 10 — the fight phase is 11e-only now")

func test_edition_10_end_fight_completes_no_combat():
	GameState.state = _state_no_combat()
	var fp = _make_phase(GameState.state)
	var completed := [false]
	fp.phase_completed.connect(func(): completed[0] = true)

	# END_FIGHT walks the phase forward (pile-in halves auto-pass with no eligible
	# units, no fights, consolidate halves auto-pass) to completion. It is always a
	# valid action and must always succeed.
	var guard := 0
	while guard < 15 and not completed[0]:
		guard += 1
		var v = fp.validate_action({"type": "END_FIGHT"})
		assert_true(v.valid, "END_FIGHT should always be valid (iter %d): %s" % [guard, str(v.get("errors", []))])
		var r = fp.process_action({"type": "END_FIGHT"})
		assert_true(r.get("success", false), "END_FIGHT should succeed (iter %d)" % guard)

	assert_true(completed[0], "Fight phase should reach phase_completed after END_FIGHT with no combatants")
