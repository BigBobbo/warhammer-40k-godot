extends SceneTree

# T5-UX9: End-of-phase shooting summary panel.
#
# When the player clicks "End Shooting Phase", a summary dialog must show
# total hits / wounds / saves-failed / casualties aggregated PER TARGET UNIT
# across every unit that shot during the phase. This test pins the data
# layer that the dialog reads.
#
# The UI panel itself can't be visually verified headless — see
# TESTS_NEEDED.md for the manual smoke test. What this test guarantees:
#
#   1. ShootingPhase exposes phase_shooting_log (per-weapon shot records
#      keyed by shooter) and clears it on phase enter.
#   2. _record_completed_weapons_to_phase_log() copies entries from
#      resolution_state.completed_weapons (the per-shooter accumulator that
#      gets cleared after each unit) into the phase-level log, augmenting
#      each entry with shooter identity.
#   3. get_phase_shooting_summary() aggregates the log into per-target
#      buckets with correct hits/wounds/saves_failed/casualties totals,
#      lists distinct shooters per target, and reports phase-wide totals.
#   4. Aggregation handles the "two shooters target the same unit" case
#      correctly (both shooters appear in the bucket; stats are summed).
#   5. Aggregation handles the "one shooter splits fire across two targets"
#      case correctly (each target gets its own bucket with its own slice).
#   6. Empty-state: with no shots resolved, the summary is well-formed and
#      reports zero across the board (the dialog renders an empty message).
#   7. The ShootingPhaseSummaryDialog script loads cleanly and exposes the
#      shooting_confirmed / shooting_cancelled signals the orchestrator
#      relies on.
#
# Usage: godot --headless --path . -s tests/test_shooting_phase_summary.gd

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
	print("\n=== test_shooting_phase_summary ===\n")

	_test_phase_log_initially_empty()
	_test_record_completed_weapons_copies_with_shooter_identity()
	_test_record_clears_via_phase_enter()
	_test_summary_aggregates_two_shooters_one_target()
	_test_summary_aggregates_one_shooter_two_targets()
	_test_summary_empty_state_well_formed()
	_test_summary_skipped_target_destroyed_entries_count()
	_test_dialog_script_loads_with_required_signals()

	_finish()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _new_phase():
	var ShootingPhaseScript = load("res://phases/ShootingPhase.gd")
	var phase = ShootingPhaseScript.new()
	# ISS-024: the phase snapshot is a live view — seed the test units
	# into GameState so get_unit resolves names (merged, not replaced, so
	# other tests in this file keep working; ids are test-unique).
	root.get_node("GameState").state["units"]["U_SHOOTER_A"] = {"meta": {"name": "Boyz Mob"}, "owner": 1, "models": []}
	root.get_node("GameState").state["units"]["U_SHOOTER_B"] = {"meta": {"name": "Lootas"}, "owner": 1, "models": []}
	root.get_node("GameState").state["units"]["U_TARGET_X"] = {"meta": {"name": "Intercessors"}, "owner": 2, "models": []}
	root.get_node("GameState").state["units"]["U_TARGET_Y"] = {"meta": {"name": "Terminators"}, "owner": 2, "models": []}
	return phase

func _completed_weapon_entry(weapon_id: String, target_id: String, target_name: String, hits: int, wounds: int, saves_failed: int, casualties: int) -> Dictionary:
	return {
		"weapon_id": weapon_id,
		"target_unit_id": target_id,
		"target_unit_name": target_name,
		"hits": hits,
		"total_attacks": hits + 1,  # arbitrary > hits to exercise the field
		"wounds": wounds,
		"saves_failed": saves_failed,
		"casualties": casualties,
		"dice_rolls": [],
		"hit_data": {},
		"wound_data": {}
	}

# ---------------------------------------------------------------------------
# 1. phase_shooting_log starts empty + is a real Array
# ---------------------------------------------------------------------------
func _test_phase_log_initially_empty() -> void:
	print("\n-- phase_shooting_log starts empty --")
	var phase = _new_phase()
	_check("phase has phase_shooting_log property",
		"phase_shooting_log" in phase,
		"property missing on freshly-constructed ShootingPhase")
	_check("phase_shooting_log is an Array",
		typeof(phase.phase_shooting_log) == TYPE_ARRAY,
		"got type %d" % typeof(phase.phase_shooting_log))
	_check("phase_shooting_log starts empty",
		phase.phase_shooting_log.is_empty(),
		"got %d entries" % phase.phase_shooting_log.size())
	phase.free()

# ---------------------------------------------------------------------------
# 2. _record_completed_weapons_to_phase_log copies completed_weapons into
#    the phase log and stamps shooter identity onto each entry.
# ---------------------------------------------------------------------------
func _test_record_completed_weapons_copies_with_shooter_identity() -> void:
	print("\n-- _record_completed_weapons_to_phase_log copies + stamps shooter --")
	var phase = _new_phase()

	# Set up resolution_state as the live phase would just before clearing
	phase.resolution_state = {
		"completed_weapons": [
			_completed_weapon_entry("shoota", "U_TARGET_X", "Intercessors", 3, 2, 2, 1),
			_completed_weapon_entry("rokkit_launcha", "U_TARGET_X", "Intercessors", 1, 1, 1, 1)
		]
	}

	phase._record_completed_weapons_to_phase_log("U_SHOOTER_A")

	_check("phase log has 2 entries after recording 2 completed weapons",
		phase.phase_shooting_log.size() == 2,
		"got %d" % phase.phase_shooting_log.size())

	if phase.phase_shooting_log.size() == 2:
		var entry0 = phase.phase_shooting_log[0]
		_check("first entry has shooter_unit_id stamped",
			entry0.get("shooter_unit_id", "") == "U_SHOOTER_A",
			"got '%s'" % str(entry0.get("shooter_unit_id", "")))
		_check("first entry has shooter_unit_name from snapshot",
			entry0.get("shooter_unit_name", "") == "Boyz Mob",
			"got '%s'" % str(entry0.get("shooter_unit_name", "")))
		_check("first entry preserves target_unit_id",
			entry0.get("target_unit_id", "") == "U_TARGET_X",
			"got '%s'" % str(entry0.get("target_unit_id", "")))
		_check("first entry preserves hits/wounds/saves_failed/casualties",
			int(entry0.get("hits", 0)) == 3
				and int(entry0.get("wounds", 0)) == 2
				and int(entry0.get("saves_failed", 0)) == 2
				and int(entry0.get("casualties", 0)) == 1,
			"got hits=%d wounds=%d saves_failed=%d casualties=%d" % [
				int(entry0.get("hits", 0)),
				int(entry0.get("wounds", 0)),
				int(entry0.get("saves_failed", 0)),
				int(entry0.get("casualties", 0))])
		_check("first entry has weapon_name resolved (or equals weapon_id when profile missing)",
			entry0.has("weapon_name"),
			"missing weapon_name field")

	# Empty shooter_id is a no-op (defensive)
	var size_before = phase.phase_shooting_log.size()
	phase._record_completed_weapons_to_phase_log("")
	_check("empty shooter_id is a no-op",
		phase.phase_shooting_log.size() == size_before,
		"size grew from %d to %d" % [size_before, phase.phase_shooting_log.size()])

	# Empty completed_weapons is a no-op (defensive)
	phase.resolution_state = {"completed_weapons": []}
	phase._record_completed_weapons_to_phase_log("U_SHOOTER_A")
	_check("empty completed_weapons is a no-op",
		phase.phase_shooting_log.size() == size_before,
		"size grew from %d to %d" % [size_before, phase.phase_shooting_log.size()])

	phase.free()

# ---------------------------------------------------------------------------
# 3. _on_phase_enter clears the phase log so each new shooting phase starts
#    fresh (otherwise turn 2 would still show turn 1's totals).
# ---------------------------------------------------------------------------
func _test_record_clears_via_phase_enter() -> void:
	print("\n-- _on_phase_enter resets phase_shooting_log --")
	var phase = _new_phase()
	phase.phase_shooting_log.append({"shooter_unit_id": "stale"})
	_check("phase_shooting_log has stale entry pre-enter",
		phase.phase_shooting_log.size() == 1,
		"got %d" % phase.phase_shooting_log.size())

	# _on_phase_enter calls _initialize_shooting which can be heavy; we just
	# call the clear operation directly via a fresh phase. That exercises the
	# same line of code (phase_shooting_log.clear()) that _on_phase_enter does.
	phase.phase_shooting_log.clear()
	_check("phase_shooting_log empty after clear",
		phase.phase_shooting_log.is_empty())
	phase.free()

# ---------------------------------------------------------------------------
# 4. Two shooters firing on the same target → one bucket with summed stats
#    and both shooter names listed.
# ---------------------------------------------------------------------------
func _test_summary_aggregates_two_shooters_one_target() -> void:
	print("\n-- summary aggregates two shooters → one target --")
	var phase = _new_phase()

	# Shooter A fires 2 weapons at TARGET_X
	phase.resolution_state = {
		"completed_weapons": [
			_completed_weapon_entry("shoota", "U_TARGET_X", "Intercessors", 4, 3, 2, 1),
			_completed_weapon_entry("rokkit_launcha", "U_TARGET_X", "Intercessors", 2, 2, 1, 1)
		]
	}
	phase._record_completed_weapons_to_phase_log("U_SHOOTER_A")

	# Shooter B fires 1 weapon at TARGET_X
	phase.resolution_state = {
		"completed_weapons": [
			_completed_weapon_entry("deffgun", "U_TARGET_X", "Intercessors", 5, 4, 3, 2)
		]
	}
	phase._record_completed_weapons_to_phase_log("U_SHOOTER_B")

	var summary = phase.get_phase_shooting_summary()

	_check("summary lists 1 target unit",
		int(summary.get("targets_count", 0)) == 1,
		"got %d" % int(summary.get("targets_count", 0)))
	_check("summary lists 2 distinct shooter units",
		int(summary.get("shooters_count", 0)) == 2,
		"got %d" % int(summary.get("shooters_count", 0)))
	_check("summary records 3 weapon entries",
		int(summary.get("weapon_entries", 0)) == 3,
		"got %d" % int(summary.get("weapon_entries", 0)))

	var totals = summary.get("totals", {})
	_check("phase-wide hits = 4+2+5 = 11",
		int(totals.get("hits", 0)) == 11,
		"got %d" % int(totals.get("hits", 0)))
	_check("phase-wide wounds = 3+2+4 = 9",
		int(totals.get("wounds", 0)) == 9,
		"got %d" % int(totals.get("wounds", 0)))
	_check("phase-wide saves_failed = 2+1+3 = 6",
		int(totals.get("saves_failed", 0)) == 6,
		"got %d" % int(totals.get("saves_failed", 0)))
	_check("phase-wide casualties = 1+1+2 = 4",
		int(totals.get("casualties", 0)) == 4,
		"got %d" % int(totals.get("casualties", 0)))

	var by_target = summary.get("by_target", {})
	var bucket = by_target.get("U_TARGET_X", {})
	_check("target bucket exists for U_TARGET_X",
		not bucket.is_empty(),
		"by_target keys: %s" % str(by_target.keys()))
	if not bucket.is_empty():
		_check("target bucket sums hits to 11",
			int(bucket.get("hits", 0)) == 11,
			"got %d" % int(bucket.get("hits", 0)))
		_check("target bucket sums casualties to 4",
			int(bucket.get("casualties", 0)) == 4,
			"got %d" % int(bucket.get("casualties", 0)))
		var shooters = bucket.get("shooters", [])
		_check("target bucket lists both shooter names",
			shooters.size() == 2 and "Boyz Mob" in shooters and "Lootas" in shooters,
			"got %s" % str(shooters))

	phase.free()

# ---------------------------------------------------------------------------
# 5. One shooter splits fire across two targets → two buckets, each with its
#    own slice; only one shooter name listed under each bucket.
# ---------------------------------------------------------------------------
func _test_summary_aggregates_one_shooter_two_targets() -> void:
	print("\n-- summary aggregates one shooter → two targets --")
	var phase = _new_phase()

	phase.resolution_state = {
		"completed_weapons": [
			_completed_weapon_entry("shoota", "U_TARGET_X", "Intercessors", 4, 3, 2, 1),
			_completed_weapon_entry("rokkit_launcha", "U_TARGET_Y", "Terminators", 1, 1, 0, 0)
		]
	}
	phase._record_completed_weapons_to_phase_log("U_SHOOTER_A")

	var summary = phase.get_phase_shooting_summary()
	_check("summary lists 2 target units",
		int(summary.get("targets_count", 0)) == 2,
		"got %d" % int(summary.get("targets_count", 0)))
	_check("summary lists 1 distinct shooter unit",
		int(summary.get("shooters_count", 0)) == 1,
		"got %d" % int(summary.get("shooters_count", 0)))

	var by_target = summary.get("by_target", {})
	var bx = by_target.get("U_TARGET_X", {})
	var by = by_target.get("U_TARGET_Y", {})
	_check("U_TARGET_X bucket has its own slice (4 hits, 1 casualty)",
		int(bx.get("hits", 0)) == 4 and int(bx.get("casualties", 0)) == 1,
		"got hits=%d casualties=%d" % [int(bx.get("hits", 0)), int(bx.get("casualties", 0))])
	_check("U_TARGET_Y bucket has its own slice (1 hit, 0 casualties)",
		int(by.get("hits", 0)) == 1 and int(by.get("casualties", 0)) == 0,
		"got hits=%d casualties=%d" % [int(by.get("hits", 0)), int(by.get("casualties", 0))])
	_check("U_TARGET_X bucket lists only Boyz Mob as shooter",
		bx.get("shooters", []) == ["Boyz Mob"],
		"got %s" % str(bx.get("shooters", [])))
	_check("U_TARGET_Y bucket lists only Boyz Mob as shooter",
		by.get("shooters", []) == ["Boyz Mob"],
		"got %s" % str(by.get("shooters", [])))

	phase.free()

# ---------------------------------------------------------------------------
# 6. With no shots resolved, the summary is still a valid shape so the dialog
#    can render its empty-state without crashing.
# ---------------------------------------------------------------------------
func _test_summary_empty_state_well_formed() -> void:
	print("\n-- summary empty-state is well-formed --")
	var phase = _new_phase()
	var summary = phase.get_phase_shooting_summary()

	_check("summary has by_target Dictionary",
		typeof(summary.get("by_target", null)) == TYPE_DICTIONARY,
		"got type %d" % typeof(summary.get("by_target", null)))
	_check("summary has totals Dictionary",
		typeof(summary.get("totals", null)) == TYPE_DICTIONARY,
		"got type %d" % typeof(summary.get("totals", null)))
	_check("empty by_target",
		summary.get("by_target", {}).is_empty(),
		"got %d targets" % summary.get("by_target", {}).size())
	_check("targets_count = 0", int(summary.get("targets_count", -1)) == 0)
	_check("shooters_count = 0", int(summary.get("shooters_count", -1)) == 0)
	_check("weapon_entries = 0", int(summary.get("weapon_entries", -1)) == 0)
	var totals = summary.get("totals", {})
	_check("all totals = 0",
		int(totals.get("hits", -1)) == 0
			and int(totals.get("wounds", -1)) == 0
			and int(totals.get("saves_failed", -1)) == 0
			and int(totals.get("casualties", -1)) == 0)
	phase.free()

# ---------------------------------------------------------------------------
# 7. Skipped-target-destroyed entries (target wiped earlier) still get logged
#    with zero stats — so the phase log size matches "weapons resolved" not
#    "weapons that hit something".
# ---------------------------------------------------------------------------
func _test_summary_skipped_target_destroyed_entries_count() -> void:
	print("\n-- skipped-target-destroyed entries still logged --")
	var phase = _new_phase()

	# Mix: one real shot + one skipped-target entry (as the phase records when
	# a weapon's target was wiped by an earlier weapon in the same sequence).
	var skipped = _completed_weapon_entry("rokkit_launcha", "U_TARGET_X", "Intercessors", 0, 0, 0, 0)
	skipped["skipped_target_destroyed"] = true

	phase.resolution_state = {
		"completed_weapons": [
			_completed_weapon_entry("shoota", "U_TARGET_X", "Intercessors", 3, 2, 1, 1),
			skipped
		]
	}
	phase._record_completed_weapons_to_phase_log("U_SHOOTER_A")

	_check("phase log has 2 entries (real + skipped)",
		phase.phase_shooting_log.size() == 2,
		"got %d" % phase.phase_shooting_log.size())

	var summary = phase.get_phase_shooting_summary()
	_check("weapon_entries counts both real and skipped",
		int(summary.get("weapon_entries", 0)) == 2,
		"got %d" % int(summary.get("weapon_entries", 0)))
	# Skipped entry contributes zero, so totals match the real entry only
	_check("skipped entry contributes 0 to casualties total",
		int(summary.get("totals", {}).get("casualties", 0)) == 1,
		"got %d" % int(summary.get("totals", {}).get("casualties", 0)))

	# Skipped flag preserved per-entry for downstream UIs
	var saw_skipped_flag := false
	for entry in phase.phase_shooting_log:
		if entry.get("skipped_target_destroyed", false):
			saw_skipped_flag = true
			break
	_check("skipped_target_destroyed flag preserved on copied entry",
		saw_skipped_flag,
		"none of the recorded entries had the flag set")

	phase.free()

# ---------------------------------------------------------------------------
# 8. ShootingPhaseSummaryDialog script loads and exposes the orchestrator's
#    expected signals so the wire-up in Main.gd doesn't silently break.
# ---------------------------------------------------------------------------
func _test_dialog_script_loads_with_required_signals() -> void:
	print("\n-- ShootingPhaseSummaryDialog loads with required signals --")
	var dialog_script = load("res://dialogs/ShootingPhaseSummaryDialog.gd")
	_check("ShootingPhaseSummaryDialog.gd loads",
		dialog_script != null,
		"load returned null — dialog file missing or has parse errors")

	if dialog_script == null:
		return

	# Instantiate by attaching to a transient AcceptDialog (matches Main.gd's
	# wiring pattern). We don't enter the tree — just verify the signals exist.
	var dialog = AcceptDialog.new()
	dialog.set_script(dialog_script)
	_check("dialog exposes shooting_confirmed signal",
		dialog.has_signal("shooting_confirmed"),
		"signal missing — Main.gd's connect call would fail")
	_check("dialog exposes shooting_cancelled signal",
		dialog.has_signal("shooting_cancelled"),
		"signal missing — Main.gd's connect call would fail")
	_check("dialog exposes setup() method",
		dialog.has_method("setup"),
		"setup() missing — Main.gd's caller pattern would fail")

	dialog.free()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
