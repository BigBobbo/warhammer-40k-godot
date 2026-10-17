extends SceneTree

# The start-of-Command steps (CP gain 08.01/#382, secondary draw — 11e GDM
# "Tactical (draw 2/turn, no hand limit)" — battle-shock clear, turn-start
# snapshots) run ONCE per player turn. Re-entering the same turn's Command
# phase — loading a save made during it, a reconnect, a scripted re-entry —
# used to apply them again: +1 CP to both players and two more secondary cards
# on every reload (probe 2026-10-17: a save at CP 4/4 with a 2-card hand
# loaded as CP 5/5 with 4 cards). The marker meta.command_start_resolved,
# saved with the game, records that the steps ran for this turn.
#
# Usage: godot --headless --path . -s tests/test_command_phase_start_once.gd

# Literal (not GameState.COMMAND_START_RESOLVED_KEY) so this file still runs —
# and fails on the CP/hand checks — against a tree without the fix.
const MARKER_KEY := "command_start_resolved"

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

func _cp(gs, p: int) -> int:
	return int(gs.state["players"][str(p)]["cp"])

func _enter(gs) -> Node:
	var phase = load("res://phases/CommandPhase.gd").new()
	root.add_child(phase)
	phase.enter_phase(gs.state)
	return phase

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_command_phase_start_once ===\n")
	GameConstants.edition = 11
	_check("edition is 11", GameConstants.edition == 11)
	var gs = root.get_node_or_null("GameState")
	var sm = root.get_node_or_null("SecondaryMissionManager")
	_check("autoloads present", gs != null and sm != null)
	if gs == null or sm == null:
		_finish()
		return

	gs.initialize_default_state()
	gs.state["meta"]["phase"] = GameStateData.Phase.COMMAND
	gs.state["meta"]["battle_round"] = 2
	gs.state["meta"]["active_player"] = 1
	gs.state["meta"]["first_turn_player"] = 1
	gs.state["meta"].erase(MARKER_KEY)
	gs.state["players"]["1"]["cp"] = 3
	gs.state["players"]["2"]["cp"] = 3
	sm.initialize_for_game()
	sm.setup_tactical_deck(1)
	sm.setup_tactical_deck(2)

	print("-- first entry of P1's round-2 Command phase applies the steps --")
	var p1 := _enter(gs)
	_check("CP +1 for both players (3 -> 4)", _cp(gs, 1) == 4 and _cp(gs, 2) == 4, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	var hand_after_first: int = sm.get_active_missions(1).size()
	_check("11e: P1 draws 2 secondaries", hand_after_first == 2, str(hand_after_first))
	_check("marker R2P1 recorded in meta", str(gs.state["meta"].get(MARKER_KEY, "")) == "R2P1",
		str(gs.state["meta"].get(MARKER_KEY, "")))
	p1.queue_free()

	print("-- re-entering the same turn's Command phase applies nothing again --")
	var p2 := _enter(gs)
	_check("CP unchanged on re-entry (still 4/4)", _cp(gs, 1) == 4 and _cp(gs, 2) == 4, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	_check("no second draw on re-entry", sm.get_active_missions(1).size() == hand_after_first,
		str(sm.get_active_missions(1).size()))
	p2.queue_free()

	print("-- a save written by this build, restored mid-Command phase --")
	var snap: Dictionary = gs.create_snapshot()
	_check("snapshot carries the marker", str(snap["meta"].get(MARKER_KEY, "")) == "R2P1",
		str(snap["meta"].get(MARKER_KEY, "")))
	gs.load_from_snapshot(snap)
	var p3 := _enter(gs)
	_check("restored Command phase: CP unchanged (4/4)", _cp(gs, 1) == 4 and _cp(gs, 2) == 4, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	_check("restored Command phase: no extra cards", sm.get_active_missions(1).size() == hand_after_first,
		str(sm.get_active_missions(1).size()))
	p3.queue_free()

	# An unmarked Command-phase save is AUTHORED at the start of the phase
	# (tutorial saves, hand-built fixtures) or comes from an older build —
	# indistinguishable, so it keeps the old contract: the start steps run
	# once on entry (the T7 tutorial relies on its mission draw), then never
	# again for that turn.
	print("-- an unmarked Command-phase save runs the start steps once --")
	var hand_before_unmarked: int = sm.get_active_missions(1).size()
	var snap_unmarked: Dictionary = gs.create_snapshot()
	snap_unmarked["meta"].erase(MARKER_KEY)
	gs.load_from_snapshot(snap_unmarked)
	_check("load does not invent a marker", not gs.state["meta"].has(MARKER_KEY),
		str(gs.state["meta"].get(MARKER_KEY, "")))
	var p3b := _enter(gs)
	_check("unmarked save: CP +1 for both (4 -> 5)", _cp(gs, 1) == 5 and _cp(gs, 2) == 5, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	_check("unmarked save: P1 draws 2", sm.get_active_missions(1).size() == hand_before_unmarked + 2,
		"%d -> %d" % [hand_before_unmarked, sm.get_active_missions(1).size()])
	_check("unmarked save: marker now R2P1", str(gs.state["meta"].get(MARKER_KEY, "")) == "R2P1",
		str(gs.state["meta"].get(MARKER_KEY, "")))
	p3b.queue_free()
	var p3c := _enter(gs)
	_check("unmarked save, re-entered: CP unchanged (5/5)", _cp(gs, 1) == 5 and _cp(gs, 2) == 5, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	_check("unmarked save, re-entered: no extra cards", sm.get_active_missions(1).size() == hand_before_unmarked + 2,
		str(sm.get_active_missions(1).size()))
	p3c.queue_free()

	print("-- the next player's turn still runs its own steps --")
	gs.state["meta"]["active_player"] = 2
	var p4 := _enter(gs)
	_check("P2's Command phase: CP +1 for both (5 -> 6)", _cp(gs, 1) == 6 and _cp(gs, 2) == 6, "%d/%d" % [_cp(gs, 1), _cp(gs, 2)])
	_check("P2 draws 2 secondaries", sm.get_active_missions(2).size() == 2, str(sm.get_active_missions(2).size()))
	_check("marker R2P2 recorded", str(gs.state["meta"].get(MARKER_KEY, "")) == "R2P2",
		str(gs.state["meta"].get(MARKER_KEY, "")))
	p4.queue_free()

	print("-- a non-Command save gets no marker on load --")
	var snap2: Dictionary = gs.create_snapshot()
	snap2["meta"]["phase"] = GameStateData.Phase.MOVEMENT
	snap2["meta"].erase(MARKER_KEY)
	gs.load_from_snapshot(snap2)
	_check("Movement-phase save: no marker added", not gs.state["meta"].has(MARKER_KEY))
	_finish()

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
