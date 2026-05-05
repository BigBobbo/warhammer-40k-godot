extends SceneTree

# T5-MP4-RELIABILITY: Save dialog timing reliability for the defender on a
# remote client.
#
# Background: ShootingPhase emits `saves_required` carrying a save_data_list.
# In multiplayer the host bundles that list into result["save_data_list"];
# NetworkManager._emit_client_visual_updates re-emits the signal on the
# defender's phase instance. If the broadcast is delayed or lost, the
# defender's WoundAllocationOverlay never appears and the game stalls.
#
# Earlier reliability work (T5-MP4) added a save_dialog_ack RPC plus a
# one-shot retry. That helped, but lacked:
#   1. a unique identity per broadcast — the ack matched on (target, weapon)
#      which is ambiguous for repeated weapons / retries.
#   2. a multi-attempt retry budget — a single retry that immediately cleared
#      the cache meant a second loss left the defender stranded.
#   3. defender-side idempotency — a re-broadcast that DID arrive after the
#      first one would pop a duplicate dialog.
#
# This test pins those three protocol invariants at the dictionary / signal
# level. It does NOT spin up two real Godot peers (single-process headless
# limitation), so it cannot prove that ENet/web-relay actually delivers the
# packets. What it *can* do — and what it asserts here — is that the public
# protocol surface is structured so that those guarantees hold whenever the
# transport delivers the messages it accepts. See `test_dice_broadcast_sync.gd`
# for the same pattern applied to the dice-log sync slice.
#
# Specifically:
#   1. Every save_data entry emitted by ShootingPhase carries a
#      `save_broadcast_id` after the broadcast helper stamps it.
#   2. The `_stamp_save_broadcast_id` helper is idempotent — re-running it on
#      a previously stamped list does NOT overwrite the original id (the
#      retry path requires this).
#   3. The defender-side `_on_saves_required` dedupes by `save_broadcast_id`
#      so a retry does not pop a second dialog.
#   4. The attacker-side retry honors the MAX_SAVE_RETRY_ATTEMPTS budget
#      (no infinite retry loop, no zero-retry regression).
#   5. NetworkManager.send_save_dialog_ack carries the save_broadcast_id and
#      on_save_dialog_acknowledged refuses to clear state for a stale id.
#
# Usage: godot --headless --path . -s tests/test_save_broadcast_reliability.gd

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
	print("\n=== test_save_broadcast_reliability ===\n")

	_test_broadcast_id_helper_stamps_and_is_idempotent()
	_test_resolve_shooting_emit_includes_save_broadcast_id()
	_test_resolve_next_weapon_emit_includes_save_broadcast_id()
	_test_defender_dedupes_repeat_broadcast_id()
	_test_retry_budget_constants_present()
	_test_ack_signature_carries_broadcast_id()
	_test_stale_ack_ignored_by_attacker()

	_finish()

# ---------------------------------------------------------------------------
# 1. _stamp_save_broadcast_id — direct unit test of the helper.
# Idempotency matters because the retry path resends the SAME save_data_list,
# and we must not generate a fresh id mid-flight (that would defeat the
# defender's dedupe).
# ---------------------------------------------------------------------------
func _test_broadcast_id_helper_stamps_and_is_idempotent() -> void:
	print("\n-- _stamp_save_broadcast_id stamps once, idempotent on retry --")

	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")

	var entries := [
		{"target_unit_id": "U_A", "weapon_name": "Bolter"},
		{"target_unit_id": "U_A", "weapon_name": "Bolter"},
	]
	var first_id := "sbid-test-1"
	ShootingPhaseScript._stamp_save_broadcast_id(entries, first_id)

	_check("First entry stamped with broadcast id",
		entries[0].get("save_broadcast_id", "") == first_id,
		"got %s" % str(entries[0].get("save_broadcast_id")))
	_check("Second entry stamped with the same broadcast id",
		entries[1].get("save_broadcast_id", "") == first_id,
		"got %s" % str(entries[1].get("save_broadcast_id")))

	# Re-stamping with a NEW id must NOT overwrite — the retry path relies
	# on this (the original id flows through unchanged so the defender can
	# dedupe).
	var second_id := "sbid-test-2"
	ShootingPhaseScript._stamp_save_broadcast_id(entries, second_id)

	_check("Re-stamp does NOT overwrite first entry's id",
		entries[0].get("save_broadcast_id", "") == first_id,
		"got %s, expected %s (retry would lose dedupe key)" % [str(entries[0].get("save_broadcast_id")), first_id])
	_check("Re-stamp does NOT overwrite second entry's id",
		entries[1].get("save_broadcast_id", "") == first_id,
		"got %s, expected %s" % [str(entries[1].get("save_broadcast_id")), first_id])

	# Generator should produce monotonically distinct ids when called twice.
	var id_a = ShootingPhaseScript._generate_save_broadcast_id()
	var id_b = ShootingPhaseScript._generate_save_broadcast_id()
	_check("Generator returns non-empty ids",
		id_a != "" and id_b != "",
		"got '%s' and '%s'" % [id_a, id_b])
	_check("Generator returns distinct ids on consecutive calls",
		id_a != id_b,
		"got duplicate id %s" % id_a)

# ---------------------------------------------------------------------------
# 2. _process_resolve_shooting source contains the stamp call.
# Static-source assertion — survives even if we can't drive a full shoot
# end-to-end in the headless harness. This catches the common regression of
# someone refactoring the emit path and dropping the stamp call.
# ---------------------------------------------------------------------------
func _test_resolve_shooting_emit_includes_save_broadcast_id() -> void:
	print("\n-- ShootingPhase._process_resolve_shooting stamps broadcast id before emit --")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	_check("ShootingPhase.gd readable", src != null)
	if src == null:
		return
	var text = src.get_as_text()
	src.close()

	# Both emit sites must call _generate_save_broadcast_id() before the emit
	# AND call _stamp_save_broadcast_id on the list.
	_check("Source contains _generate_save_broadcast_id() call",
		text.contains("_generate_save_broadcast_id()"),
		"broadcast id generator never called — defender cannot dedupe")
	_check("Source contains _stamp_save_broadcast_id(save_data_list, broadcast_id)",
		text.contains("_stamp_save_broadcast_id(save_data_list, broadcast_id)"),
		"stamp helper not invoked on save_data_list — id never propagates")

	# The emit must happen AFTER stamping. Cheap check: stamp call appears
	# before each emit_signal("saves_required", ...) in the file.
	var stamp_idx = text.find("_stamp_save_broadcast_id(save_data_list, broadcast_id)")
	var first_emit_idx = text.find('emit_signal("saves_required"')
	_check("Stamp call appears before first saves_required emit",
		stamp_idx != -1 and first_emit_idx != -1 and stamp_idx < first_emit_idx,
		"stamp_idx=%d emit_idx=%d (emit must come after stamp)" % [stamp_idx, first_emit_idx])

# ---------------------------------------------------------------------------
# 3. The second emit site (resolve_next_weapon) must also stamp.
# We assert there are TWO occurrences of the stamp call in the file — one
# per emit site. If a refactor consolidates emits but forgets one stamp, the
# count drops and this fires.
# ---------------------------------------------------------------------------
func _test_resolve_next_weapon_emit_includes_save_broadcast_id() -> void:
	print("\n-- Both ShootingPhase emit sites stamp broadcast id --")

	var src = FileAccess.open("res://phases/ShootingPhase.gd", FileAccess.READ)
	if src == null:
		_check("ShootingPhase.gd readable (resolve_next_weapon)", false)
		return
	var text = src.get_as_text()
	src.close()

	var stamp_count := 0
	var search_from := 0
	while true:
		var idx = text.find("_stamp_save_broadcast_id(save_data_list, broadcast_id)", search_from)
		if idx == -1:
			break
		stamp_count += 1
		search_from = idx + 1

	_check("ShootingPhase.gd has >= 2 stamp calls (one per emit site)",
		stamp_count >= 2,
		"got %d stamp call(s); each emit_signal(\"saves_required\") site must stamp first" % stamp_count)

	# emit_signal("saves_required") count — ensure stamp count keeps pace.
	var emit_count := 0
	search_from = 0
	while true:
		var idx = text.find('emit_signal("saves_required"', search_from)
		if idx == -1:
			break
		emit_count += 1
		search_from = idx + 1

	_check("Stamp count >= emit_signal(\"saves_required\") count",
		stamp_count >= emit_count,
		"%d stamps vs %d emits — at least one emit is unstamped" % [stamp_count, emit_count])

# ---------------------------------------------------------------------------
# 4. ShootingController._on_saves_required dedupes by save_broadcast_id.
# We can't run the controller live (it needs the Main scene), so we assert on
# the structural invariant in source: the dedupe block must look up the id in
# the recorded history before showing the dialog, AND the broadcast id must
# be appended to that history when the dialog IS shown.
# ---------------------------------------------------------------------------
func _test_defender_dedupes_repeat_broadcast_id() -> void:
	print("\n-- ShootingController dedupes repeat save_broadcast_id (defender idempotency) --")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	_check("ShootingController.gd readable", src != null)
	if src == null:
		return
	var text = src.get_as_text()
	src.close()

	_check("Source declares _shown_save_broadcast_ids history array",
		text.contains("_shown_save_broadcast_ids"),
		"defender has nowhere to record handled broadcast ids")
	_check("Source declares MAX_SAVE_RETRY_ATTEMPTS constant",
		text.contains("MAX_SAVE_RETRY_ATTEMPTS"),
		"retry budget constant missing — retries become unbounded or zero")
	_check("Source dedupes incoming sbid against history",
		text.contains("incoming_sbid in _shown_save_broadcast_ids"),
		"defender does not check for duplicate broadcast id — retry pops 2 dialogs")
	_check("Source records sbid into history when showing dialog",
		text.contains("_shown_save_broadcast_ids.append(local_sbid)"),
		"defender never records shown broadcast ids — dedupe will fail")

# ---------------------------------------------------------------------------
# 5. Retry budget is wired into _retry_save_data_broadcast.
# The single-shot retry must be replaced by an attempt counter that respects
# the budget, and `_pending_save_data_for_retry` must NOT be cleared on a
# successful retry attempt (it must survive until ack OR exhaustion).
# ---------------------------------------------------------------------------
func _test_retry_budget_constants_present() -> void:
	print("\n-- Attacker retry honors MAX_SAVE_RETRY_ATTEMPTS budget --")

	var src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	if src == null:
		_check("ShootingController.gd readable (retry budget)", false)
		return
	var text = src.get_as_text()
	src.close()

	_check("Retry function increments _save_retry_attempts",
		text.contains("_save_retry_attempts += 1"),
		"retry counter never advances — budget is not enforced")
	_check("Retry function checks budget before sending",
		text.contains("_save_retry_attempts >= MAX_SAVE_RETRY_ATTEMPTS"),
		"no budget check — retries either zero or unbounded")
	_check("MAX_SAVE_RETRY_ATTEMPTS is a positive constant",
		text.contains("MAX_SAVE_RETRY_ATTEMPTS: int = ") and not text.contains("MAX_SAVE_RETRY_ATTEMPTS: int = 0"),
		"budget must be > 0")
	_check("Retry timer is re-armed inside _retry_save_data_broadcast",
		text.contains("_save_processing_timeout_timer.start()") and text.contains("_save_retry_attempts += 1"),
		"timer never re-arms — only one retry possible regardless of budget")
	# The single-shot regression: ensure the bad pre-fix line is gone — i.e.
	# we no longer clear pending data BEFORE the budget is exhausted.
	# The exhaustion branch IS allowed to clear, so we look for the absence of
	# an unconditional clear immediately after the retry RPC.
	# Detect via: the pattern "NetworkManager.retry_save_data_broadcast" must
	# NOT be immediately followed by "_pending_save_data_for_retry.clear()".
	var rpc_idx = text.find("NetworkManager.retry_save_data_broadcast(_pending_save_data_for_retry)")
	_check("Retry RPC call is present", rpc_idx != -1)
	if rpc_idx != -1:
		# Look at the next 400 chars after the call — clear() must NOT appear
		# before the next blank-line / closing brace of the same block. We
		# approximate: the next clear() must be preceded by either a budget
		# check or the success branch.
		var window = text.substr(rpc_idx, 600)
		var clear_in_window = window.contains("_pending_save_data_for_retry.clear()")
		# If the unconditional single-shot regression were back, the clear
		# would appear within the very next few lines. We allow it ONLY if
		# the budget-exhausted block (which DOES clear) appears in the window
		# above as well. The simplest, most stable test: the clear() inside
		# the retry happy path must not exist — verify by checking that the
		# only clear() reachable from the RPC call is gated by an "exhausted"
		# log line.
		_check("Retry RPC is NOT followed by an unconditional clear() (single-shot regression)",
			not clear_in_window or window.contains("Retry budget exhausted"),
			"unconditional clear after retry — falls back to single-shot retry")

# ---------------------------------------------------------------------------
# 6. NetworkManager save-dialog ack carries the broadcast id end-to-end.
# Both the ENet RPC and the relay dispatcher must accept a third arg, and the
# controller's on_save_dialog_acknowledged must accept it as well.
# ---------------------------------------------------------------------------
func _test_ack_signature_carries_broadcast_id() -> void:
	print("\n-- send_save_dialog_ack + handler signature carry save_broadcast_id --")

	var nm_src = FileAccess.open("res://autoloads/NetworkManager.gd", FileAccess.READ)
	_check("NetworkManager.gd readable", nm_src != null)
	if nm_src == null:
		return
	var nm_text = nm_src.get_as_text()
	nm_src.close()

	_check("send_save_dialog_ack signature accepts save_broadcast_id",
		nm_text.contains("func send_save_dialog_ack(target_unit_id: String, weapon_name: String, save_broadcast_id: String"),
		"ack outbound API does not carry id — ack remains target+weapon only")
	_check("_receive_save_dialog_ack RPC accepts save_broadcast_id",
		nm_text.contains("func _receive_save_dialog_ack(target_unit_id: String, weapon_name: String, save_broadcast_id: String"),
		"ENet RPC does not propagate id — defender's ack is dropped on attacker side match")
	_check("Web-relay dispatcher reads save_broadcast_id from payload",
		nm_text.contains('var ack_sbid = data.get("save_broadcast_id", "")'),
		"relay path does not extract id — web-relay games regress to legacy match")
	_check("Web-relay dispatcher forwards id to controller",
		nm_text.contains("on_save_dialog_acknowledged(ack_target, ack_weapon, ack_sbid)"),
		"relay path does not pass id to controller")
	_check("retry_save_data_broadcast logs broadcast id from cached entries",
		nm_text.contains('save_data_list[0].get("save_broadcast_id", "")'),
		"retry helper drops the id — defender cannot match the retry to its dedupe history")

	var sc_src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	if sc_src == null:
		_check("ShootingController.gd readable (ack handler)", false)
		return
	var sc_text = sc_src.get_as_text()
	sc_src.close()

	_check("on_save_dialog_acknowledged accepts save_broadcast_id",
		sc_text.contains("func on_save_dialog_acknowledged(target_unit_id: String, weapon_name: String, save_broadcast_id: String"),
		"controller ack handler signature stale — id never reaches state-clear logic")
	_check("Defender send_save_dialog_ack call passes local_sbid",
		sc_text.contains("NetworkManager.send_save_dialog_ack(target_unit_id, weapon, local_sbid)"),
		"defender ack outbound drops id — attacker can't match ack precisely")

# ---------------------------------------------------------------------------
# 7. Stale ack with a different broadcast id must NOT clear retry state.
# This is the protocol-level guarantee that protects the attacker from a
# late-arriving ack for a previous broadcast clobbering the active one.
# ---------------------------------------------------------------------------
func _test_stale_ack_ignored_by_attacker() -> void:
	print("\n-- Attacker ignores stale ack (different save_broadcast_id) --")

	var sc_src = FileAccess.open("res://scripts/ShootingController.gd", FileAccess.READ)
	if sc_src == null:
		_check("ShootingController.gd readable (stale ack)", false)
		return
	var sc_text = sc_src.get_as_text()
	sc_src.close()

	_check("Source declares _expected_save_ack_broadcast_id field",
		sc_text.contains("_expected_save_ack_broadcast_id"),
		"no expected-id state — cannot detect stale acks")
	_check("Source compares incoming ack id to expected before clearing",
		sc_text.contains("save_broadcast_id != _expected_save_ack_broadcast_id"),
		"ack handler does not check id — stale ack clears active retry state")
	# The early-return on stale ack must come BEFORE _save_ack_received = true.
	var early_return = sc_text.find("⚠️ Ack id does not match expected")
	var ack_clear = sc_text.find("_save_ack_received = true")
	_check("Stale-ack early return appears before ack-state clear",
		early_return != -1 and ack_clear != -1 and early_return < ack_clear,
		"stale ack still falls through to clear retry state")

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
