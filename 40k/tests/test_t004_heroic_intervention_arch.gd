extends SceneTree

# T-004: Heroic Intervention is no longer the unimplemented placeholder
# described by the audit. Architecture: HI is now handled inside the Charge
# phase (USE_HEROIC_INTERVENTION, DECLINE_HEROIC_INTERVENTION,
# HEROIC_INTERVENTION_CHARGE_ROLL, APPLY_HEROIC_INTERVENTION_MOVE), and the
# FightPhase HEROIC_INTERVENTION action returns a redirect error rather than
# the legacy "not implemented" stub.
#
# This test pins:
#   (a) ChargePhase has the four HI action types wired in its action router
#   (b) ChargePhase.awaiting_heroic_intervention state field exists
#   (c) StratagemManager has the eligibility helper
#   (d) FightPhase still routes HEROIC_INTERVENTION but with a redirect message
#
# It does NOT exercise the runtime flow — that's done by the existing
# test_hi_pretrigger.gd suite (which currently has its own unrelated failures
# tracked under that test).
#
# Usage: godot --headless --path . -s tests/test_t004_heroic_intervention_arch.gd

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
	print("\n=== test_t004_heroic_intervention_arch ===\n")
	_test_charge_phase_has_hi_actions()
	_test_charge_phase_state_fields()
	_test_stratagem_manager_eligibility_helper()
	_test_fight_phase_redirect_not_stub()
	_finish()

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text = f.get_as_text()
	f.close()
	return text

func _test_charge_phase_has_hi_actions() -> void:
	print("\n-- T-004/A: ChargePhase action router covers all 4 HI action types --")
	var src = _read_text("res://phases/ChargePhase.gd")
	_check("ChargePhase.gd readable", not src.is_empty())
	_check("USE_HEROIC_INTERVENTION action wired",
		"\"USE_HEROIC_INTERVENTION\":" in src or "'USE_HEROIC_INTERVENTION':" in src)
	_check("DECLINE_HEROIC_INTERVENTION action wired",
		"\"DECLINE_HEROIC_INTERVENTION\":" in src or "'DECLINE_HEROIC_INTERVENTION':" in src)
	_check("HEROIC_INTERVENTION_CHARGE_ROLL action wired",
		"HEROIC_INTERVENTION_CHARGE_ROLL" in src)
	_check("APPLY_HEROIC_INTERVENTION_MOVE action wired",
		"APPLY_HEROIC_INTERVENTION_MOVE" in src)
	# Pin existence of the validators/processors.
	_check("_validate_use_heroic_intervention defined",
		"_validate_use_heroic_intervention" in src)
	_check("_process_use_heroic_intervention defined",
		"_process_use_heroic_intervention" in src)
	_check("_validate_apply_heroic_intervention_move defined",
		"_validate_apply_heroic_intervention_move" in src)

func _test_charge_phase_state_fields() -> void:
	print("\n-- T-004/B: ChargePhase has the HI state machine fields --")
	var src = _read_text("res://phases/ChargePhase.gd")
	_check("awaiting_heroic_intervention field declared",
		"awaiting_heroic_intervention: bool" in src)
	_check("heroic_intervention_player field declared",
		"heroic_intervention_player: int" in src)
	_check("heroic_intervention_charging_unit_id field declared",
		"heroic_intervention_charging_unit_id: String" in src)
	_check("heroic_intervention_unit_id field declared",
		"heroic_intervention_unit_id: String" in src)
	_check("heroic_intervention_pending_charge field declared",
		"heroic_intervention_pending_charge: Dictionary" in src)

func _test_stratagem_manager_eligibility_helper() -> void:
	print("\n-- T-004/C: StratagemManager exposes HI eligibility helper --")
	var src = _read_text("res://autoloads/StratagemManager.gd")
	_check("StratagemManager.gd readable", not src.is_empty())
	_check("get_heroic_intervention_eligible_units defined",
		"get_heroic_intervention_eligible_units" in src)
	# Pin the rule constraints from the function docstring (regression guard
	# that the gates aren't accidentally removed).
	_check("eligibility checks 6\" range",
		"6\\\"" in src or "Within 6\"" in src or "6.0" in src)
	_check("eligibility checks battle_shocked",
		"battle_shocked" in src)
	_check("eligibility checks VEHICLE/WALKER",
		"WALKER" in src and "VEHICLE" in src)

func _test_fight_phase_redirect_not_stub() -> void:
	print("\n-- T-004/D: FightPhase HI handler is a redirect, not a 'not implemented' stub --")
	var src = _read_text("res://phases/FightPhase.gd")
	_check("FightPhase.gd readable", not src.is_empty())
	_check("FightPhase still routes HEROIC_INTERVENTION action",
		"\"HEROIC_INTERVENTION\":" in src or "'HEROIC_INTERVENTION':" in src)
	# The original audit-flagged stub was a literal string "not implemented".
	# After the move-to-ChargePhase, the validator returns a redirect message
	# pointing at the new location. Pin both invariants.
	_check("validator no longer returns the 'not implemented' literal",
		not ("\"not implemented\"" in src and "_validate_heroic_intervention_action" in src
			and src.find("\"not implemented\"", src.find("_validate_heroic_intervention_action")) >= 0))
	_check("validator now redirects to Charge phase",
		"now handled during the Charge phase" in src
		or "use USE_HEROIC_INTERVENTION during Charge phase" in src)

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
