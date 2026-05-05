extends ShootingController

# Test stub used by tests/test_shooting_phase_shortcuts.gd to exercise the
# keyboard-shortcut dispatch in ShootingController without instantiating the
# full UI scene tree.
#
# We override the five action callbacks the dispatcher routes to and have
# them write to `recorded` so assertions can verify which callback fired.
# Returning early (no UI interaction) keeps the test hermetic.

var recorded: String = ""

func _reset_recorded() -> void:
	recorded = ""

# Bypass the parent's _ready (it expects HUD nodes that don't exist in the
# test harness). The dispatcher we're testing doesn't depend on _ready
# having run — it only reads active_shooter_id / weapon_assignments which
# the test sets explicitly.
func _ready() -> void:
	pass

# ---------------------------------------------------------------------------
# Action callback overrides — record which one was invoked.
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	recorded = "confirm"

func _keyboard_deselect_shooter() -> void:
	recorded = "deselect"

func _keyboard_cycle_units(_reverse: bool) -> void:
	recorded = "cycle"

func _keyboard_skip_unit() -> void:
	recorded = "skip"

func _on_end_phase_pressed() -> void:
	recorded = "end_phase"
