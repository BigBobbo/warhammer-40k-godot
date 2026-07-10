extends SceneTree

# T12 regression probe: every touched visual script must still load and
# instantiate in headless `-s` mode (the pretrigger-harness context).
#
# NOTE: the load happens in _process, NOT _init — a `-s` script's _init
# runs before autoload registration, where even long-standing bare
# `Measurement` references fail to compile. Real -s tests load scripts
# after startup, so that's the contract probed here. UIConstants access
# in these files goes through get_node_or_null, so instances must come
# up with their fallback colors when the autoload node exists (it does
# in -s mode) or not.

const SCRIPTS := [
	"res://scripts/MovementRangeVisual.gd",
	"res://scripts/EngagementRangeVisual.gd",
	"res://scripts/CoherencyCircleVisual.gd",
	"res://scripts/ChargeTrajectoryPreview.gd",
	"res://scripts/DeepStrikeExclusionVisual.gd",
	"res://scripts/DamageFeedbackVisual.gd",
	"res://scripts/ChargeArrowVisual.gd",
	"res://scripts/DeploymentZoneVisual.gd",
	"res://scripts/AIMovementPathVisual.gd",
]

var _frames := 0
var _done := false

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3 or _done:
		return false
	_done = true

	var failures := 0
	for path in SCRIPTS:
		var s = load(path)
		if s == null or not (s is GDScript) or not s.can_instantiate():
			print("FAIL compile/load: %s" % path)
			failures += 1
			continue
		var inst = s.new()
		if inst == null:
			print("FAIL instantiate: %s" % path)
			failures += 1
			continue
		inst.free()
		print("PASS %s" % path)

	if failures == 0:
		print("=== probe result: ALL PASS (%d scripts) ===" % SCRIPTS.size())
	else:
		print("=== probe result: %d FAILURES ===" % failures)
	quit(1 if failures > 0 else 0)
	return true
