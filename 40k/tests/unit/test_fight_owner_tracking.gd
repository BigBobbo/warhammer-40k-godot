extends SceneTree

# Regression: the Fight-phase attack-allocation dialog must NOT be shown to the
# human for the AI's fighters.
#
# Reported bug: playing Orks (human, P1) vs Custodes (AI, P2), when the AI's
# Custodes were selected to fight, the game popped up the "who do you want to
# allocate the Custodes' models' attacks to" dialog (AttackAssignmentDialog) for
# the human. Same class of bug would also mis-show the pile-in / consolidate
# dialogs for the AI's fighters.
#
# Root cause: FightController tracked current_fighter_owner only in the human
# dialog paths (_on_fighter_selected_from_dialog, the 11e step pickers). The AI
# selects fighters by submitting SELECT_FIGHTER directly, which reaches the
# controller as the phase's `fighter_selected` signal -> _on_fighter_selected,
# and that handler set current_fighter_id but never refreshed
# current_fighter_owner. So after a human unit fought, current_fighter_owner
# stayed on the human's player number; when the AI's unit then fought, the
# dialog handlers' is_ai_player(current_fighter_owner) gate saw the human and
# showed the dialog.
#
# The fix makes _on_fighter_selected (which fires for EVERY fighter selection,
# AI or human) refresh current_fighter_owner from the selected unit's owner.
#
# This test drives the real FightController._on_fighter_selected and asserts the
# owner tracks whichever unit is fighting, and that the resulting is_ai_player
# gate (used by _on_attack_assignment_required / _on_pile_in_required /
# _on_consolidate_required to skip the dialog) resolves correctly.
#
# Usage: godot --headless --path 40k -s tests/unit/test_fight_owner_tracking.gd

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
	create_timer(0.1).timeout.connect(_run)

func _board(gs) -> void:
	# U_ORK (P1, human) and U_CUST (P2, AI), engaged and eligible to fight.
	gs.state["units"] = {
		"U_ORK": {"id": "U_ORK", "owner": 1, "status": 2, "flags": {},
			"meta": {"name": "Ork Boyz", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 1}},
			"models": [
				{"id": "m0", "alive": true, "wounds": 1, "current_wounds": 1, "base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 500}},
			]},
		"U_CUST": {"id": "U_CUST", "owner": 2, "status": 2, "flags": {"charged_this_turn": true},
			"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"], "stats": {"move": 6, "wounds": 3}},
			"models": [
				{"id": "e0", "alive": true, "wounds": 3, "current_wounds": 3, "base_mm": 40, "base_type": "circular", "position": {"x": 540, "y": 500}},
			]},
	}
	gs.state["meta"]["active_player"] = 2   # the AI's turn (Custodes charged)
	gs.state["meta"]["phase"] = 10

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_fight_owner_tracking ===\n")
	var gs = root.get_node_or_null("GameState")
	var ai = root.get_node_or_null("AIPlayer")
	if gs == null or ai == null:
		_check("autoloads present", false, "gs=%s ai=%s" % [gs, ai]); _finish(); return

	var prev_enabled = ai.enabled
	var prev_players = ai.ai_players.duplicate(true)
	ai.enabled = true
	ai.ai_players = {1: false, 2: true}  # P1 human (Orks), P2 AI (Custodes)

	_board(gs)

	# Build a bare FightController. We do NOT add it to the tree: _ready() would
	# try to resolve SceneRefs UI nodes that don't exist headless. The handler
	# under test only reads GameState + its own member vars; every UI helper it
	# calls is null-guarded, so a bare instance exercises the real code path.
	var FightControllerScript = load("res://scripts/FightController.gd")
	var fc = FightControllerScript.new()

	_check("controller starts with no owner", fc.current_fighter_owner == -1,
		"got %d" % fc.current_fighter_owner)

	# --- The human's Ork unit is selected to fight first ---
	fc._on_fighter_selected("U_ORK")
	_check("after human fighter selected: current_fighter_id == U_ORK",
		fc.current_fighter_id == "U_ORK", "got %s" % fc.current_fighter_id)
	_check("after human fighter selected: owner tracks P1 (human)",
		fc.current_fighter_owner == 1, "got %d" % fc.current_fighter_owner)
	_check("human fighter: is_ai_player(owner) is FALSE -> human dialog would show (correct)",
		not ai.is_ai_player(fc.current_fighter_owner))

	# --- The AI's Custodes unit is now selected to fight ---
	# THE BUG: pre-fix, current_fighter_owner stayed 1 here (never refreshed),
	# so the dialog handlers' is_ai_player() gate saw the human and popped the
	# AttackAssignmentDialog for the AI's attacks. The fix refreshes it to 2.
	fc._on_fighter_selected("U_CUST")
	_check("after AI fighter selected: current_fighter_id == U_CUST",
		fc.current_fighter_id == "U_CUST", "got %s" % fc.current_fighter_id)
	_check("FIX: after AI fighter selected: owner switches to P2 (AI)",
		fc.current_fighter_owner == 2, "got %d (pre-fix this stayed 1)" % fc.current_fighter_owner)
	_check("FIX: AI fighter: is_ai_player(owner) is TRUE -> dialog is skipped for AI",
		ai.is_ai_player(fc.current_fighter_owner))

	# --- Back to the human's unit: the owner must switch back ---
	fc._on_fighter_selected("U_ORK")
	_check("owner switches back to P1 when the human fighter is re-selected",
		fc.current_fighter_owner == 1, "got %d" % fc.current_fighter_owner)
	_check("human fighter again: is_ai_player(owner) is FALSE",
		not ai.is_ai_player(fc.current_fighter_owner))

	# --- Robustness: a missing/unknown unit must not corrupt a valid owner ---
	fc._on_fighter_selected("U_CUST")
	_check("owner is P2 before the bad-id call", fc.current_fighter_owner == 2)
	fc._on_fighter_selected("DOES_NOT_EXIST")
	_check("unknown unit id does not clobber the last valid owner",
		fc.current_fighter_owner == 2, "got %d" % fc.current_fighter_owner)

	fc.free()
	ai.enabled = prev_enabled
	ai.ai_players = prev_players
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
