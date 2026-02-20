extends SceneTree

# Test script for T7-20: AI thinking indicator
# Run: godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k --script tests/unit/test_ai_thinking_indicator.gd
#
# Tests the AI thinking state tracking and signal emissions.
# Uses the actual AIPlayer autoload since it's loaded by the project.

var pass_count: int = 0
var fail_count: int = 0

# Signal tracking arrays (use reference types for reliable closure capture)
var _started_players: Array = []
var _ended_players: Array = []
var _ended_summaries: Array = []

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		print("PASS: %s" % test_name)
		pass_count += 1
	else:
		print("FAIL: %s" % test_name)
		fail_count += 1

func _init():
	print("=== T7-20: AI Thinking Indicator Tests ===")
	# Wait for autoloads to initialize
	call_deferred("_run_tests")

func _on_ai_turn_started(player: int) -> void:
	_started_players.append(player)

func _on_ai_turn_ended(player: int, summary: Array) -> void:
	_ended_players.append(player)
	_ended_summaries.append(summary)

func _run_tests():
	var ai = root.get_node_or_null("/root/AIPlayer")
	var game_state = root.get_node_or_null("/root/GameState")
	if ai == null or game_state == null:
		print("FAIL: Required autoloads not found (AIPlayer=%s, GameState=%s)" % [ai != null, game_state != null])
		quit(1)
		return

	# Save original state
	var orig_enabled = ai.enabled
	var orig_players = ai.ai_players.duplicate()
	var orig_thinking = ai._ai_thinking
	var orig_active_player = game_state.state.get("meta", {}).get("active_player", 1)

	# Connect signals using instance methods (more reliable than closures)
	ai.ai_turn_started.connect(_on_ai_turn_started)
	ai.ai_turn_ended.connect(_on_ai_turn_ended)

	# -------------------------------------------------------
	# Test 1: AIPlayer has _ai_thinking property (defaults false)
	# -------------------------------------------------------
	_assert(ai._ai_thinking == false, "AIPlayer._ai_thinking defaults to false")

	# -------------------------------------------------------
	# Test 2: AIPlayer has ai_turn_started signal
	# -------------------------------------------------------
	_assert(ai.has_signal("ai_turn_started"), "AIPlayer has ai_turn_started signal")

	# -------------------------------------------------------
	# Test 3: AIPlayer has ai_turn_ended signal
	# -------------------------------------------------------
	_assert(ai.has_signal("ai_turn_ended"), "AIPlayer has ai_turn_ended signal")

	# -------------------------------------------------------
	# Test 4: _end_ai_thinking is no-op when not thinking
	# -------------------------------------------------------
	ai._ai_thinking = false
	_ended_players.clear()
	ai._end_ai_thinking()
	_assert(ai._ai_thinking == false, "_end_ai_thinking is no-op when not already thinking")
	_assert(_ended_players.size() == 0, "_end_ai_thinking does not emit signal when not thinking")

	# -------------------------------------------------------
	# Test 5: _end_ai_thinking sets flag to false and emits signal
	# -------------------------------------------------------
	ai._ai_thinking = true
	_ended_players.clear()
	_ended_summaries.clear()
	ai._end_ai_thinking()
	_assert(ai._ai_thinking == false, "_end_ai_thinking sets _ai_thinking to false")
	_assert(_ended_players.size() == 1, "_end_ai_thinking emits ai_turn_ended signal (got %d emissions)" % _ended_players.size())

	# -------------------------------------------------------
	# Test 6: _request_evaluation emits ai_turn_started for AI player
	# -------------------------------------------------------
	ai.enabled = true
	ai.ai_players = {2: true}
	ai._ai_thinking = false
	game_state.state["meta"]["active_player"] = 2
	_started_players.clear()

	ai._request_evaluation()
	_assert(ai._ai_thinking == true, "_request_evaluation sets _ai_thinking to true for AI player")
	_assert(_started_players.size() == 1, "ai_turn_started signal emitted once (got %d)" % _started_players.size())
	if _started_players.size() > 0:
		_assert(_started_players[0] == 2, "ai_turn_started emitted with correct player (got %d)" % _started_players[0])
	else:
		_assert(false, "ai_turn_started emitted with correct player (no emission)")

	# -------------------------------------------------------
	# Test 7: _request_evaluation does NOT re-emit when already thinking
	# -------------------------------------------------------
	_started_players.clear()
	ai._ai_thinking = true  # Already thinking
	ai._request_evaluation()
	_assert(_started_players.size() == 0, "ai_turn_started not re-emitted when already thinking (got %d)" % _started_players.size())

	# -------------------------------------------------------
	# Test 8: _request_evaluation does NOT trigger for human player
	# -------------------------------------------------------
	ai._ai_thinking = false
	ai.ai_players = {2: true}  # Player 2 is AI
	game_state.state["meta"]["active_player"] = 1  # Player 1 is active (human)
	_started_players.clear()

	ai._request_evaluation()
	_assert(_started_players.size() == 0, "ai_turn_started NOT emitted for human player")
	_assert(ai._ai_thinking == false, "_ai_thinking stays false for human player")

	# -------------------------------------------------------
	# Test 9: Multiple _end_ai_thinking calls only emit once
	# -------------------------------------------------------
	_ended_players.clear()
	ai._ai_thinking = true
	game_state.state["meta"]["active_player"] = 2
	ai._end_ai_thinking()  # Should emit (count = 1)
	ai._end_ai_thinking()  # Should NOT emit (already false)
	ai._end_ai_thinking()  # Should NOT emit
	_assert(_ended_players.size() == 1, "Multiple _end_ai_thinking calls emit only once (got %d)" % _ended_players.size())

	# -------------------------------------------------------
	# Test 10: ai_turn_ended carries action log summary
	# -------------------------------------------------------
	_ended_summaries.clear()
	ai._ai_thinking = true
	ai._action_log = [{"phase": 0, "action_type": "TEST", "description": "test action"}]
	ai._end_ai_thinking()
	if _ended_summaries.size() > 0:
		_assert(_ended_summaries[0].size() == 1, "ai_turn_ended carries action log (got %d items)" % _ended_summaries[0].size())
	else:
		_assert(false, "ai_turn_ended carries action log (no emission)")

	# -------------------------------------------------------
	# Cleanup — restore original state
	# -------------------------------------------------------
	ai.ai_turn_started.disconnect(_on_ai_turn_started)
	ai.ai_turn_ended.disconnect(_on_ai_turn_ended)
	ai._ai_thinking = false
	ai.enabled = orig_enabled
	ai.ai_players = orig_players
	ai._action_log.clear()
	ai._needs_evaluation = false
	game_state.state["meta"]["active_player"] = orig_active_player

	# -------------------------------------------------------
	# Summary
	# -------------------------------------------------------
	print("")
	print("=== Results: %d/%d passed ===" % [pass_count, pass_count + fail_count])
	if fail_count > 0:
		print("FAILURES: %d tests failed" % fail_count)
	else:
		print("ALL TESTS PASSED")

	quit(1 if fail_count > 0 else 0)
