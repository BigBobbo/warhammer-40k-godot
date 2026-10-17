extends SceneTree

# 11e 15.01 blanket rule: a player cannot use the SAME Stratagem more than
# once in the same phase. Seven of the ten core stratagems declare no explicit
# once_per restriction (EPIC CHALLENGE, CRUSHING IMPACT, SMOKESCREEN, HEROIC
# INTERVENTION, COUNTEROFFENSIVE, RAPID INGRESS, FIRE OVERWATCH — 15.08
# prints no RESTRICTIONS; "Once per turn." was its 10e wording) — the blanket
# default in StratagemManager._check_usage_restriction must cap them at once
# per phase.
#
# Also pins the phase-INSTANCE fix: the "same phase" comparison includes
# whose player-turn it was (usage.active_player), so using a stratagem in
# P1's Shooting phase does not block the same stratagem in P2's Shooting
# phase of the same battle round.
#
# Usage: godot --headless --path . -s tests/test_15_01_once_per_phase.gd

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
	print("\n=== test_15_01_once_per_phase ===\n")
	var sm = root.get_node_or_null("StratagemManager")
	var gs = root.get_node_or_null("GameState")
	if sm == null or gs == null:
		_check("autoloads reachable", false)
		print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return

	var prev_hist = sm._usage_history.duplicate(true)
	var prev_phase = gs.state["meta"].get("phase", 0)
	var prev_active = gs.state["meta"].get("active_player", 1)
	sm._usage_history = {"1": [], "2": []}
	gs.state["players"]["1"]["cp"] = 10
	gs.state["players"]["2"]["cp"] = 10
	GameConstants.edition = 11
	var turn = gs.get_battle_round()

	# SMOKESCREEN declares restrictions:{} — the blanket rule must still cap it.
	gs.state["meta"]["phase"] = 8  # SHOOTING (smokescreen's window)
	gs.state["meta"]["active_player"] = 1
	var v = sm.can_use_stratagem(2, "smokescreen_11e", "")
	_check("no-restriction core stratagem usable the first time", v.can_use, str(v))

	sm._usage_history["2"].append({"stratagem_id": "smokescreen_11e", "player": 2,
		"target_unit_id": "U_A", "turn": turn, "phase": 8, "active_player": 1, "timestamp": 0})
	v = sm.can_use_stratagem(2, "smokescreen_11e", "")
	_check("blanket 15.01: SAME stratagem twice in the same phase is refused (even with restrictions:{})",
		v.can_use == false and "once per phase" in str(v.reason), str(v))

	# Different target unit does not help — the cap is on the stratagem itself.
	v = sm.can_use_stratagem(2, "smokescreen_11e", "U_B")
	_check("blanket 15.01: a different target unit does not bypass the cap",
		v.can_use == false, str(v))

	# Same battle round, same phase enum, but the OTHER player's turn: this is
	# a different phase instance — must be allowed. COMMAND RE-ROLL is usable
	# on either turn (unlike SMOKESCREEN, whose opponent's-turn timing gate
	# would mask the result).
	sm._usage_history["2"].append({"stratagem_id": "command_re_roll_11e", "player": 2,
		"target_unit_id": "", "turn": turn, "phase": 8, "active_player": 1, "timestamp": 0})
	v = sm.can_use_stratagem(2, "command_re_roll_11e", "")
	_check("baseline: same phase instance blocks the re-used COMMAND RE-ROLL",
		v.can_use == false and "once per phase" in str(v.reason), str(v))
	gs.state["meta"]["active_player"] = 2
	v = sm.can_use_stratagem(2, "command_re_roll_11e", "")
	_check("phase instance: P1-turn usage does not block the same stratagem in P2's turn (same round+phase)",
		v.can_use, str(v))
	gs.state["meta"]["active_player"] = 1

	# Explicit stricter caps still win: a definition that declares once_per
	# "turn" (the 10e FIRE OVERWATCH: "Once per turn.") — a usage earlier in
	# the same player-turn (different phase) still blocks it. (This used the
	# 11e FIRE OVERWATCH, which carried the 10e cap over; 15.08 prints no
	# RESTRICTIONS, so the 11e stratagem is checked under 15.01 just below.)
	gs.state["meta"]["phase"] = 7  # MOVEMENT
	var fo10: Dictionary = sm.stratagems.get("fire_overwatch", {})
	_check("10e FIRE OVERWATCH definition declares once_per turn", str(fo10.get("restrictions", {}).get("once_per", "")) == "turn", str(fo10.get("restrictions", {})))
	sm._usage_history["2"].append({"stratagem_id": "fire_overwatch", "player": 2,
		"target_unit_id": "U_C", "turn": turn, "phase": 9, "active_player": 1, "timestamp": 0})
	v = sm._check_usage_restriction(2, "fire_overwatch", fo10)
	_check("explicit once-per-turn still enforced across phases of the same turn",
		v.can_use == false and "once per turn" in str(v.reason), str(v))

	# 11e FIRE OVERWATCH (15.08, no RESTRICTIONS line): the 15.01 blanket rule —
	# a use in this Movement phase blocks a second one. 15.08 is offered in
	# the movement_phase_end window, so the check runs with that window's
	# context (outside it the window gate answers first: "Offered
	# automatically when the Movement phase ends").
	_check("11e FIRE OVERWATCH declares no explicit once_per cap (15.08)",
		not sm.stratagems.get("fire_overwatch_11e", {}).get("restrictions", {}).has("once_per"),
		str(sm.stratagems.get("fire_overwatch_11e", {}).get("restrictions", {})))
	sm._usage_history["2"].append({"stratagem_id": "fire_overwatch_11e", "player": 2,
		"target_unit_id": "U_C", "turn": turn, "phase": 7, "active_player": 1, "timestamp": 0})
	v = sm.can_use_stratagem(2, "fire_overwatch_11e", "", {"window_id": "movement_phase_end"})
	_check("blanket 15.01: a second 11e FIRE OVERWATCH in the same Movement phase is refused",
		v.can_use == false and "once per phase" in str(v.reason), str(v))

	# Legacy history entries without active_player fall back to conservative
	# same-turn blocking (old-save compatibility).
	sm._usage_history["2"] = [{"stratagem_id": "smokescreen_11e", "player": 2,
		"target_unit_id": "U_A", "turn": turn, "phase": 8, "timestamp": 0}]
	gs.state["meta"]["phase"] = 8
	v = sm.can_use_stratagem(2, "smokescreen_11e", "")
	_check("legacy record without active_player still blocks (conservative)",
		v.can_use == false, str(v))

	# 10e path: definitions without once_per stay unrestricted (no blanket).
	GameConstants.edition = 10
	sm._usage_history["2"] = [{"stratagem_id": "smokescreen", "player": 2,
		"target_unit_id": "U_A", "turn": turn, "phase": 8, "active_player": 1, "timestamp": 0}]
	var strat10 = sm.stratagems.get("smokescreen", {})
	if strat10.is_empty() or strat10.get("restrictions", {}).has("once_per"):
		_check("10e: no blanket default (skipped — 10e smokescreen has its own cap)", true)
	else:
		v = sm._check_usage_restriction(2, "smokescreen", strat10)
		_check("10e: no blanket default applied", v.can_use, str(v))

	GameConstants.edition = 10
	sm._usage_history = prev_hist
	gs.state["meta"]["phase"] = prev_phase
	gs.state["meta"]["active_player"] = prev_active
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
