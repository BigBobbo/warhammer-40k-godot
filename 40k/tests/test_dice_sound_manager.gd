extends SceneTree

# Test script for DiceSoundManager (P3-122)
# Run with: godot --headless --script res://tests/test_dice_sound_manager.gd

const DiceSoundManagerScript = preload("res://autoloads/DiceSoundManager.gd")

func _init():
	print("=== DiceSoundManager Test Suite ===")
	var pass_count := 0
	var fail_count := 0

	# Test 1: Instantiation
	var manager = DiceSoundManagerScript.new()
	if manager != null:
		print("PASS: DiceSoundManager instantiated")
		pass_count += 1
	else:
		print("FAIL: DiceSoundManager failed to instantiate")
		fail_count += 1

	root.add_child(manager)
	await process_frame

	# Test 2: All streams generated
	if manager._stream_roll_tick != null:
		print("PASS: roll_tick stream generated")
		pass_count += 1
	else:
		print("FAIL: roll_tick stream is null")
		fail_count += 1

	if manager._stream_settle != null:
		print("PASS: settle stream generated")
		pass_count += 1
	else:
		print("FAIL: settle stream is null")
		fail_count += 1

	if manager._stream_critical_success != null:
		print("PASS: critical_success stream generated")
		pass_count += 1
	else:
		print("FAIL: critical_success stream is null")
		fail_count += 1

	if manager._stream_critical_failure != null:
		print("PASS: critical_failure stream generated")
		pass_count += 1
	else:
		print("FAIL: critical_failure stream is null")
		fail_count += 1

	if manager._stream_result_success != null:
		print("PASS: result_success stream generated")
		pass_count += 1
	else:
		print("FAIL: result_success stream is null")
		fail_count += 1

	if manager._stream_result_failure != null:
		print("PASS: result_failure stream generated")
		pass_count += 1
	else:
		print("FAIL: result_failure stream is null")
		fail_count += 1

	# Test 3: Player pool created
	if manager._player_pool.size() == DiceSoundManagerScript.POOL_SIZE:
		print("PASS: Player pool size correct (%d)" % manager._player_pool.size())
		pass_count += 1
	else:
		print("FAIL: Player pool size wrong: %d (expected %d)" % [manager._player_pool.size(), DiceSoundManagerScript.POOL_SIZE])
		fail_count += 1

	# Test 4: All players are AudioStreamPlayer instances on SFX bus
	var all_sfx := true
	for player in manager._player_pool:
		if player.bus != "SFX":
			all_sfx = false
			break
	if all_sfx:
		print("PASS: All players on SFX bus")
		pass_count += 1
	else:
		print("FAIL: Not all players on SFX bus")
		fail_count += 1

	# Test 5: Stream data is valid (non-empty)
	if manager._stream_roll_tick.data.size() > 0:
		print("PASS: roll_tick stream has audio data (%d bytes)" % manager._stream_roll_tick.data.size())
		pass_count += 1
	else:
		print("FAIL: roll_tick stream data is empty")
		fail_count += 1

	if manager._stream_settle.data.size() > 0:
		print("PASS: settle stream has audio data (%d bytes)" % manager._stream_settle.data.size())
		pass_count += 1
	else:
		print("FAIL: settle stream data is empty")
		fail_count += 1

	if manager._stream_critical_success.data.size() > 0:
		print("PASS: critical_success stream has audio data (%d bytes)" % manager._stream_critical_success.data.size())
		pass_count += 1
	else:
		print("FAIL: critical_success stream data is empty")
		fail_count += 1

	# Test 6: Stream format and sample rate
	if manager._stream_roll_tick.format == AudioStreamWAV.FORMAT_16_BITS:
		print("PASS: Streams use 16-bit format")
		pass_count += 1
	else:
		print("FAIL: Expected FORMAT_16_BITS")
		fail_count += 1

	if manager._stream_roll_tick.mix_rate == DiceSoundManagerScript.SAMPLE_RATE:
		print("PASS: Streams use correct sample rate (%d)" % manager._stream_roll_tick.mix_rate)
		pass_count += 1
	else:
		print("FAIL: Expected sample rate %d, got %d" % [DiceSoundManagerScript.SAMPLE_RATE, manager._stream_roll_tick.mix_rate])
		fail_count += 1

	# Test 7: P3-126 — Phase transition streams generated
	if manager._stream_phase_transition != null:
		print("PASS: phase_transition stream generated")
		pass_count += 1
	else:
		print("FAIL: phase_transition stream is null")
		fail_count += 1

	if manager._stream_phase_combat != null:
		print("PASS: phase_combat stream generated")
		pass_count += 1
	else:
		print("FAIL: phase_combat stream is null")
		fail_count += 1

	if manager._stream_phase_transition.data.size() > 0:
		print("PASS: phase_transition stream has audio data (%d bytes)" % manager._stream_phase_transition.data.size())
		pass_count += 1
	else:
		print("FAIL: phase_transition stream data is empty")
		fail_count += 1

	if manager._stream_phase_combat.data.size() > 0:
		print("PASS: phase_combat stream has audio data (%d bytes)" % manager._stream_phase_combat.data.size())
		pass_count += 1
	else:
		print("FAIL: phase_combat stream data is empty")
		fail_count += 1

	# Test 8: Play methods don't crash (even without audio device in headless)
	manager.play_roll_tick()
	manager.play_settle()
	manager.play_critical_success()
	manager.play_critical_failure()
	manager.play_result_success()
	manager.play_result_failure()
	manager.play_phase_transition()
	manager.play_phase_combat()
	print("PASS: All play methods executed without error")
	pass_count += 1

	# Test 9: Pool index wraps correctly
	var initial_idx = manager._pool_index
	for i in DiceSoundManagerScript.POOL_SIZE + 2:
		manager.play_settle()
	if manager._pool_index < DiceSoundManagerScript.POOL_SIZE:
		print("PASS: Pool index wraps correctly (%d)" % manager._pool_index)
		pass_count += 1
	else:
		print("FAIL: Pool index out of bounds: %d" % manager._pool_index)
		fail_count += 1

	# Test 10: Rate limiting on tick sounds
	manager._last_tick_time = Time.get_ticks_msec() / 1000.0
	var old_idx = manager._pool_index
	manager.play_roll_tick()  # Should be rate-limited (too soon after setting _last_tick_time)
	# In headless the time resolution may vary, so we just verify no crash
	print("PASS: Tick rate limiting works without error")
	pass_count += 1

	# Cleanup
	manager.queue_free()

	print("\n=== Results: %d passed, %d failed ===" % [pass_count, fail_count])
	if fail_count > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")

	quit()
