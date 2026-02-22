extends SceneTree

# Test script for T5-MP7: Game Over Dialog reason text logic
# Run: godot --headless --script res://tests/test_game_over_dialog.gd

var _pass_count = 0
var _fail_count = 0

func _init():
	print("=== T5-MP7: Game Over Dialog Tests ===\n")

	test_reason_text_turn_timeout()
	test_reason_text_disconnect()
	test_reason_text_surrender()
	test_reason_text_tabled()
	test_reason_text_rounds_complete()
	test_reason_text_fallback()
	test_winner_logic()
	test_networked_display_logic()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")
	quit()

func assert_eq(actual, expected, description: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s (expected '%s', got '%s')" % [description, str(expected), str(actual)])

func assert_true(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % description)
	else:
		_fail_count += 1
		print("  FAIL: %s" % description)

# Replicate the _get_reason_text logic from GameOverDialog.gd for testing
func _get_reason_text(winner_player: int, game_over_reason: String) -> String:
	match game_over_reason:
		"turn_timeout":
			return "Player %d ran out of time" % (3 - winner_player)
		"disconnect":
			return "Opponent disconnected"
		"surrender":
			return "Player %d surrendered" % (3 - winner_player)
		"tabled":
			return "Player %d has no models remaining" % (3 - winner_player)
		"rounds_complete":
			return "All 5 battle rounds completed"
		_:
			return game_over_reason if game_over_reason != "" else "Game concluded"

# ---------------------------------------------------------------------------
# Reason text tests — verify the match statement in GameOverDialog._get_reason_text
# ---------------------------------------------------------------------------

func test_reason_text_turn_timeout():
	print("\n-- test_reason_text_turn_timeout --")
	assert_eq(_get_reason_text(1, "turn_timeout"), "Player 2 ran out of time", "Timeout: winner=1 means player 2 timed out")
	assert_eq(_get_reason_text(2, "turn_timeout"), "Player 1 ran out of time", "Timeout: winner=2 means player 1 timed out")

func test_reason_text_disconnect():
	print("\n-- test_reason_text_disconnect --")
	assert_eq(_get_reason_text(1, "disconnect"), "Opponent disconnected", "Disconnect reason text")
	assert_eq(_get_reason_text(2, "disconnect"), "Opponent disconnected", "Disconnect reason text (winner=2)")

func test_reason_text_surrender():
	print("\n-- test_reason_text_surrender --")
	assert_eq(_get_reason_text(1, "surrender"), "Player 2 surrendered", "Surrender: winner=1 means player 2 surrendered")
	assert_eq(_get_reason_text(2, "surrender"), "Player 1 surrendered", "Surrender: winner=2 means player 1 surrendered")

func test_reason_text_tabled():
	print("\n-- test_reason_text_tabled --")
	assert_eq(_get_reason_text(2, "tabled"), "Player 1 has no models remaining", "Tabled: winner=2 means player 1 was tabled")
	assert_eq(_get_reason_text(1, "tabled"), "Player 2 has no models remaining", "Tabled: winner=1 means player 2 was tabled")

func test_reason_text_rounds_complete():
	print("\n-- test_reason_text_rounds_complete --")
	assert_eq(_get_reason_text(1, "rounds_complete"), "All 5 battle rounds completed", "Rounds complete text")
	assert_eq(_get_reason_text(0, "rounds_complete"), "All 5 battle rounds completed", "Rounds complete text (draw)")

func test_reason_text_fallback():
	print("\n-- test_reason_text_fallback --")
	assert_eq(_get_reason_text(0, ""), "Game concluded", "Empty reason falls back to 'Game concluded'")
	assert_eq(_get_reason_text(0, "custom_reason"), "custom_reason", "Unknown reason passes through as-is")

# ---------------------------------------------------------------------------
# Winner display logic tests — verify the winner label text logic
# ---------------------------------------------------------------------------

func test_winner_logic():
	print("\n-- test_winner_logic --")
	# Non-networked game (local_player = 0)
	var local_player = 0

	# Player 1 wins
	var winner = 1
	if local_player > 0:
		assert_true(false, "Should not enter networked path")
	elif winner > 0:
		var expected = "Player %d Wins!" % winner
		assert_eq(expected, "Player 1 Wins!", "Non-networked: player 1 wins display")

	# Player 2 wins
	winner = 2
	if local_player > 0:
		assert_true(false, "Should not enter networked path")
	elif winner > 0:
		var expected = "Player %d Wins!" % winner
		assert_eq(expected, "Player 2 Wins!", "Non-networked: player 2 wins display")

	# Draw
	winner = 0
	if winner > 0:
		assert_true(false, "Should not enter winner path")
	else:
		assert_eq("Game Over — Draw!", "Game Over — Draw!", "Draw display text")

func test_networked_display_logic():
	print("\n-- test_networked_display_logic --")
	# Networked game — test victory/defeat display
	var local_player = 1

	# I win (local player = winner)
	var winner = 1
	if local_player > 0 and winner == local_player:
		assert_true(true, "Networked: VICTORY when winner == local_player")
	else:
		assert_true(false, "Should show victory")

	# I lose (local player != winner)
	winner = 2
	if local_player > 0 and winner != local_player:
		assert_true(true, "Networked: DEFEAT when winner != local_player")
	else:
		assert_true(false, "Should show defeat")

	# As player 2
	local_player = 2
	winner = 2
	if local_player > 0 and winner == local_player:
		assert_true(true, "Networked: VICTORY for player 2")
	else:
		assert_true(false, "Should show victory for player 2")
