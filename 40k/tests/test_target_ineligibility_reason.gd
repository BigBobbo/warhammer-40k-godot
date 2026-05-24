extends SceneTree

# Regression test for ShootingController target-click feedback.
#
# When a player selects a unit to shoot, picks a weapon from the right-hand
# panel, then clicks an enemy unit on the board, the controller currently
# silently ignores the click if the target isn't in `eligible_targets` — no
# toast, no log, no reason. This pins the new RulesEngine helper that
# returns a human-readable reason for why a target was rejected, which the
# UI then surfaces via ToastManager.

const RulesEngineScript = preload("res://autoloads/RulesEngine.gd")

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
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_target_ineligibility_reason ===\n")

	_test_helper_exists()
	_test_unknown_actor()
	_test_unknown_target()
	_test_friendly_target_rejected()
	_test_attached_character_rejected()
	_test_destroyed_target_rejected()
	_test_empty_string_when_eligible_unknown_path()

	_finish()

func _test_helper_exists() -> void:
	print("\n-- helper exists --")
	_check("RulesEngineScript.get_target_ineligibility_reason is defined",
		RulesEngineScript.new().has_method("get_target_ineligibility_reason"))

func _test_unknown_actor() -> void:
	print("\n-- unknown actor --")
	var board := {"units": {}}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_GHOST", "U_OTHER", board)
	_check("unknown actor returns a non-empty reason", reason != "", "got: '%s'" % reason)

func _test_unknown_target() -> void:
	print("\n-- unknown target --")
	var board := {
		"units": {
			"U_A": {"owner": 1, "models": [{"alive": true, "position": {"x": 0, "y": 0}}]}
		}
	}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_A", "U_MISSING", board)
	_check("unknown target returns a non-empty reason", reason != "", "got: '%s'" % reason)

func _test_friendly_target_rejected() -> void:
	print("\n-- friendly target rejected --")
	var board := {
		"units": {
			"U_A": {"owner": 1, "models": [{"alive": true, "position": {"x": 0, "y": 0}}]},
			"U_B": {"owner": 1, "models": [{"alive": true, "position": {"x": 10, "y": 0}}]}
		}
	}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_A", "U_B", board)
	_check("friendly target reason mentions 'friendly'",
		reason.findn("friendly") >= 0,
		"got: '%s'" % reason)

func _test_attached_character_rejected() -> void:
	print("\n-- attached character rejected --")
	var board := {
		"units": {
			"U_SHOOTER": {"owner": 1, "models": [{"alive": true, "position": {"x": 0, "y": 0}}]},
			"U_CHAR": {
				"owner": 2,
				"attached_to": "U_BG",
				"meta": {"name": "Captain"},
				"models": [{"alive": true, "position": {"x": 50, "y": 0}}]
			}
		}
	}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_SHOOTER", "U_CHAR", board)
	_check("attached character reason mentions 'bodyguard'",
		reason.findn("bodyguard") >= 0,
		"got: '%s'" % reason)

func _test_destroyed_target_rejected() -> void:
	print("\n-- destroyed target rejected --")
	var board := {
		"units": {
			"U_SHOOTER": {"owner": 1, "models": [{"alive": true, "position": {"x": 0, "y": 0}}]},
			"U_DEAD": {
				"owner": 2,
				"meta": {"name": "Ghosts"},
				"models": [
					{"alive": false, "position": {"x": 50, "y": 0}},
					{"alive": false, "position": {"x": 60, "y": 0}}
				]
			}
		}
	}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_SHOOTER", "U_DEAD", board)
	_check("destroyed target reason mentions 'surviving'",
		reason.findn("surviving") >= 0,
		"got: '%s'" % reason)

func _test_empty_string_when_eligible_unknown_path() -> void:
	# Without full weapon profiles wired, the unit-level fallback path may
	# return "No weapons in range...". We just check the contract: when no
	# rule disqualifies the target AND the actor has zero weapons in range,
	# the reason is non-empty (so the UI always has something to show).
	print("\n-- alive enemy with no weapons in range still gets a reason --")
	var board := {
		"units": {
			"U_SHOOTER": {
				"owner": 1,
				"meta": {"name": "Empty"},
				"models": [{"alive": true, "position": {"x": 0, "y": 0}}]
			},
			"U_ENEMY": {
				"owner": 2,
				"meta": {"name": "Enemy"},
				"models": [{"alive": true, "position": {"x": 5000, "y": 0}}]
			}
		}
	}
	var reason: String = RulesEngineScript.get_target_ineligibility_reason("U_SHOOTER", "U_ENEMY", board)
	_check("non-empty reason for enemy that no weapon can reach",
		reason != "",
		"got empty reason — UI would silently swallow the click again")

func _finish() -> void:
	print("\n=== Result: %d passed, %d failed ===\n" % [passed, failed])
	quit(0 if failed == 0 else 1)
