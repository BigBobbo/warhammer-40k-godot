extends SceneTree

# PM-F4 — the plan-legality coherency check and the deployment phase must never
# disagree, whichever edition is in force, and a plan must be validated against
# the edition it will be PLAYED at rather than the one it happens to be
# authored under.
#
# The defect this guards against was reported as "the AI hardcodes 11e while
# the phase is edition-aware". That diagnosis was wrong — both go through
# AttackSequence.check_unit_coherency, the single source of truth
# (DeploymentPhase.gd:199-202, AIDecisionMaker.gd:603) — and the first half of
# this file pins that agreement down so the claim cannot be made again without
# evidence.
#
# The real defect was an edition SPLIT between authoring and play. A headless
# authoring run (`godot -s …`) is treated as an automated harness by
# SettingsService and pinned to the legacy 10e baseline, which has no 9"
# envelope; every player launch and AIBenchmarkRunner run at 11. So the PM-10
# authoring pass certified an 11-model line 13.60" across that the game then
# refused. The second half of this file covers the fix: PlanValidator checks
# coherency at edition 11 regardless of the ambient setting.
#
# Run with: godot --headless --path . -s tests/unit/test_plan_coherency_editions.gd

const AIDM_PATH := "res://scripts/AIDecisionMaker.gd"
const PV_PATH := "res://scripts/PlanValidator.gd"
const DEPLOYMENT_PHASE_PATH := "res://phases/DeploymentPhase.gd"

const PX := 40.0
const BASE_MM := 25          # 0.98" wide — keeps a 1.2" spacing overlap-free
const BOARD_CENTRE := Vector2(22.0, 30.0)

var AIDM
var PV
var DeploymentPhaseScript

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.3).timeout.connect(_run)

func _run():
	print("\n=== Plan coherency across editions (PM-F4) Tests ===\n")
	AIDM = load(AIDM_PATH)
	PV = load(PV_PATH)
	DeploymentPhaseScript = load(DEPLOYMENT_PHASE_PATH)
	if AIDM == null or PV == null or DeploymentPhaseScript == null:
		_assert(false, "AIDecisionMaker, PlanValidator and DeploymentPhase all load")
	else:
		_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

# ---------------------------------------------------------------------------

func _unit(n: int) -> Dictionary:
	var models: Array = []
	for i in range(n):
		models.append({
			"id": "m%d" % i, "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": BASE_MM, "position": null, "rotation": 0.0,
		})
	return {"id": "U_TEST", "owner": 1, "models": models,
		"meta": {"name": "Test Mob", "keywords": ["INFANTRY"]}}

func _line_positions(n: int, span_in: float) -> Array:
	"""n models on a straight line `span_in` inches end to end, centred on the
	board so no board-edge or wall check can interfere."""
	var out: Array = []
	var step := span_in / float(n - 1)
	for i in range(n):
		var x := BOARD_CENTRE.x - span_in * 0.5 + step * float(i)
		out.append(Vector2(x * PX, BOARD_CENTRE.y * PX))
	return out

func _block_positions(n: int, cols: int, spacing_in: float) -> Array:
	"""n models in a tight block — well inside the 9" envelope under any edition."""
	var out: Array = []
	for i in range(n):
		var c := i % cols
		var r := i / cols
		out.append(Vector2(
			(BOARD_CENTRE.x + float(c) * spacing_in) * PX,
			(BOARD_CENTRE.y + float(r) * spacing_in) * PX))
	return out

func _rotations(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append(0.0)
	return out

func _snapshot() -> Dictionary:
	return {
		"meta": {"deployment_type": "hammer_anvil", "battle_round": 1, "phase": 1},
		"board": {"size": {"width": 44, "height": 60}, "deployment_zones": [], "terrain_features": []},
		"units": {},
	}

func _phase_says_coherent(positions: Array, unit: Dictionary) -> bool:
	var phase = DeploymentPhaseScript.new()
	var verdict: Dictionary = phase._check_deployment_coherency(
		positions, _rotations(positions.size()), unit)
	phase.free()
	return bool(verdict.get("valid", false))

func _ai_accepts(positions: Array, unit: Dictionary) -> bool:
	# Everything except coherency is made trivially legal: an empty zone polygon
	# defers to the phase (AIDecisionMaker._plan_shape_inside_polygon), there are
	# no already-deployed models, and the shapes sit at board centre.
	return AIDM._plan_positions_legal(positions, unit, 1, _snapshot(),
		PackedVector2Array(), [], BASE_MM, "circular", {})

# ---------------------------------------------------------------------------

func _run_tests() -> void:
	var entry_edition = GameConstants.edition
	test_shape_really_does_discriminate()
	test_phase_and_ai_agree_under_both_editions()
	test_validator_is_pinned_to_the_played_edition()
	test_validator_restores_the_ambient_edition()
	GameConstants.edition = entry_edition

func test_shape_really_does_discriminate() -> void:
	# Without this the agreement test below could pass on a shape both editions
	# accept, which would prove nothing at all.
	var unit := _unit(11)
	var wide := _line_positions(11, 13.60)   # the exact PM-10 Gretchin line
	var tight := _block_positions(11, 4, 1.2)

	GameConstants.edition = 10
	_assert(_phase_says_coherent(wide, unit),
		"CONTROL: the 13.60\" line IS coherent under 10e — no 9\" envelope in that edition")
	GameConstants.edition = 11
	_assert(not _phase_says_coherent(wide, unit),
		"…and is NOT coherent under 11e, so the shape genuinely separates the two editions")

	GameConstants.edition = 10
	_assert(_phase_says_coherent(tight, unit), "a tight block is coherent under 10e")
	GameConstants.edition = 11
	_assert(_phase_says_coherent(tight, unit), "…and under 11e")

func test_phase_and_ai_agree_under_both_editions() -> void:
	# The heart of PM-F4: "the AI will accept this placement" and "the phase
	# will accept this action" must not diverge, whichever way edition points.
	var unit := _unit(11)
	var shapes := {
		"13.60\" line": _line_positions(11, 13.60),
		"tight block": _block_positions(11, 4, 1.2),
	}
	for edition in [10, 11]:
		GameConstants.edition = edition
		for label in shapes.keys():
			var positions: Array = shapes[label]
			var phase_ok := _phase_says_coherent(positions, unit)
			var ai_ok := _ai_accepts(positions, unit)
			_assert(phase_ok == ai_ok,
				"edition %d, %s: phase says %s and the plan check says %s — they agree" % [
					edition, label, str(phase_ok), str(ai_ok)])

func test_validator_is_pinned_to_the_played_edition() -> void:
	# A plan is authored in one process and consumed in another. The validator
	# must answer for the edition the game is PLAYED at (11), not the one the
	# authoring process happens to sit in — that split is what PM-F4 was.
	var unit := _unit(11)
	var wide := _line_positions(11, 13.60)
	var models_inches: Array = []
	for p in wide:
		models_inches.append([p.x / PX, p.y / PX])

	for ambient in [10, 11]:
		GameConstants.edition = ambient
		var note: String = PV._placement_coherency_note("U_TEST", models_inches, unit)
		_assert(not note.is_empty(),
			"ambient edition %d: the validator still flags the 13.60\" line, because it answers for 11e" % ambient)
		_assert(note.find("11th-edition") != -1 and note.find("U_TEST") != -1,
			"…and the message names the unit and the rule (got '%s')" % note.substr(0, 60))

	# The same shape inside the envelope is silent under either ambient setting.
	var tight_inches: Array = []
	for p in _block_positions(11, 4, 1.2):
		tight_inches.append([p.x / PX, p.y / PX])
	for ambient in [10, 11]:
		GameConstants.edition = ambient
		_assert(PV._placement_coherency_note("U_TEST", tight_inches, unit).is_empty(),
			"ambient edition %d: a coherent placement produces no note" % ambient)

	# No army models means no base sizes, and coherency is measured base edge to
	# base edge — so the check declines rather than guessing.
	GameConstants.edition = 11
	_assert(PV._placement_coherency_note("U_TEST", models_inches, {}).is_empty(),
		"with no army unit supplied the check declines rather than guessing at base sizes")

func test_validator_restores_the_ambient_edition() -> void:
	# The check writes a global to do its job. If it leaked, every test running
	# after a validation would silently change ruleset.
	var unit := _unit(11)
	var models_inches: Array = []
	for p in _line_positions(11, 13.60):
		models_inches.append([p.x / PX, p.y / PX])
	for ambient in [10, 11]:
		GameConstants.edition = ambient
		PV._placement_coherency_note("U_TEST", models_inches, unit)
		_assert(GameConstants.edition == ambient,
			"edition %d is restored after the check runs (got %d)" % [ambient, GameConstants.edition])
