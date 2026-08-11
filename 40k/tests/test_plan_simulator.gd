extends SceneTree

# PM-8b — the plan-vs-plan simulator backend.
#
# Runs a real 2-game mirror through PlanSimulator and checks the claims the
# gate asks for:
#   - two result rows, with DIFFERENT seeds;
#   - equal unit counts at both game starts (nothing leaked between them);
#   - seat-2 plan adherence > 0 — the one that proves the [44-x, 60-y]
#     transform produced placements the deployment phase actually accepted;
#   - summary arithmetic (wins/draws/mean/sd) agrees with the rows;
#   - zero stalls and zero timeouts;
#   - the same seed_base twice gives identical winners and margins;
#   - a results file is written.
#
# This runs FULL games, so it is slow by test standards (~2 minutes for the
# four games it plays). It is
# deliberately NOT in run_pretrigger_tests.sh — see the note at the bottom of
# the PM-8b evidence block.
#
# Run with: godot --headless --path . -s tests/test_plan_simulator.gd

const ARMY := "A_C_test"          # the 3-unit list the PM-8a spike used: ~15s games
const ZONE := "crucible_of_battle"
const LAYOUT := "take_and_hold_mirror_1"
const MISSION := "take_and_hold"
const PLAN := "res://tests/fixtures/ai_plans/fixture_a_c_test_crucible.json"

const GAMES := 2
const SEED_BASE := 8200
const TIME_SCALE := 10.0
const MAX_SECONDS := 300.0

var _pass_count: int = 0
var _fail_count: int = 0
var _run_a: Dictionary = {}
var _run_b: Dictionary = {}


func _init():
	create_timer(0.3).timeout.connect(_run)


func _run() -> void:
	print("\n=== Plan simulator (PM-8b) Tests ===\n")
	var sim = root.get_node_or_null("PlanSimulator")
	if sim == null:
		_assert(false, "PlanSimulator autoload is registered")
		_finish()
		return

	# The plan is authored for the Custodes list on crucible_of_battle, so it
	# matches BOTH seats here (mirror match) — seat 2 through the transform.
	print("-- run A --")
	_run_a = await _run_once(sim)
	_check_run(_run_a, "A")

	print("\n-- run B (same seed_base) --")
	_run_b = await _run_once(sim)
	_check_run(_run_b, "B")

	_check_determinism()
	_finish()


func _run_once(sim) -> Dictionary:
	sim.start({
		"zone_id": ZONE,
		"layout_id": LAYOUT,
		"mission_id": MISSION,
		"army1": ARMY,
		"army2": ARMY,
		"plan1": PLAN,
		"plan2": PLAN,
		"games": GAMES,
		"seed_base": SEED_BASE,
		"time_scale": TIME_SCALE,
		"max_seconds_per_game": MAX_SECONDS,
	})
	while sim.is_running():
		await create_timer(1.0).timeout
	return {"summary": sim.last_summary.duplicate(true), "games": sim.results.duplicate(true)}


func _check_run(run: Dictionary, label: String) -> void:
	var games: Array = run.get("games", [])
	var summary: Dictionary = run.get("summary", {})

	_assert(games.size() == GAMES,
		"run %s produced %d result row(s)" % [label, games.size()])
	if games.size() != GAMES:
		return

	var seeds: Array = []
	var unit_counts: Array = []
	var statuses: Array = []
	for g in games:
		seeds.append(int(g.get("seed", -1)))
		unit_counts.append(int(g.get("unit_count", -1)))
		statuses.append(str(g.get("status", "")))

	_assert(seeds[0] != seeds[1],
		"run %s: the two games used different seeds (%s)" % [label, str(seeds)])
	_assert(seeds[0] == SEED_BASE and seeds[1] == SEED_BASE + 1,
		"run %s: seeds are seed_base + i (%s)" % [label, str(seeds)])
	_assert(unit_counts[0] == unit_counts[1] and unit_counts[0] > 0,
		"run %s: equal unit counts at both game starts (%s)" % [label, str(unit_counts)])
	_assert(statuses.count("completed") == GAMES,
		"run %s: both games completed (%s)" % [label, str(statuses)])
	_assert(int(summary.get("stalls", -1)) == 0,
		"run %s: zero stalls (%s)" % [label, str(summary.get("stalls", "?"))])
	_assert(int(summary.get("timeouts", -1)) == 0,
		"run %s: zero timeouts (%s)" % [label, str(summary.get("timeouts", "?"))])

	# The claim of the whole feature: a plan authored in the player-1 frame is
	# followed by BOTH seats.
	for g in games:
		_assert(int(g.get("plan_adherence_p2", 0)) > 0,
			"run %s game %d: seat 2 followed the plan (%d placement(s))" % [
				label, int(g.get("game", 0)), int(g.get("plan_adherence_p2", 0))])
		_assert(int(g.get("plan_adherence_p1", 0)) > 0,
			"run %s game %d: seat 1 followed the plan (%d placement(s))" % [
				label, int(g.get("game", 0)), int(g.get("plan_adherence_p1", 0))])

	# Summary arithmetic must agree with the rows, not be reported independently.
	var wins := {1: 0, 2: 0, 0: 0}
	var margins: Array = []
	for g in games:
		wins[int(g.get("winner", 0))] = int(wins.get(int(g.get("winner", 0)), 0)) + 1
		margins.append(float(g.get("margin", 0)))
	_assert(int(summary.get("wins_p1", -1)) == int(wins[1])
			and int(summary.get("wins_p2", -1)) == int(wins[2])
			and int(summary.get("draws", -1)) == int(wins[0]),
		"run %s: summary wins match the rows (%d/%d/%d vs %d/%d/%d)" % [
			label, int(summary.get("wins_p1", -1)), int(summary.get("wins_p2", -1)),
			int(summary.get("draws", -1)), wins[1], wins[2], wins[0]])

	# NOT `:=` — margins is an untyped Array, so its elements are Variant and
	# GDScript refuses to infer from the arithmetic.
	var expected_mean: float = (float(margins[0]) + float(margins[1])) / 2.0
	_assert(abs(float(summary.get("mean_margin", 9999.0)) - expected_mean) < 0.001,
		"run %s: mean margin is the mean of the rows (%.2f vs %.2f)" % [
			label, float(summary.get("mean_margin", 9999.0)), expected_mean])
	var expected_sd: float = sqrt((pow(float(margins[0]) - expected_mean, 2.0)
		+ pow(float(margins[1]) - expected_mean, 2.0)) / 2.0)
	_assert(abs(float(summary.get("sd_margin", 9999.0)) - expected_sd) < 0.001,
		"run %s: sd margin matches the rows (%.2f vs %.2f)" % [
			label, float(summary.get("sd_margin", 9999.0)), expected_sd])
	_assert(float(summary.get("mean_seconds_per_game", 0.0)) > 0.0,
		"run %s: a measured s/game is reported (%.1f) for PM-9's ETA" % [
			label, float(summary.get("mean_seconds_per_game", 0.0))])

	var path := str(summary.get("results_path", ""))
	_assert(path.begins_with("user://plan_sim_results/") and FileAccess.file_exists(path),
		"run %s: results written to %s" % [label, path])


func _check_determinism() -> void:
	print("\n-- determinism: the same seed_base twice --")
	var a: Array = _run_a.get("games", [])
	var b: Array = _run_b.get("games", [])
	if a.size() != b.size() or a.is_empty():
		_assert(false, "both runs produced comparable rows")
		return
	for i in range(a.size()):
		var ga: Dictionary = a[i]
		var gb: Dictionary = b[i]
		_assert(int(ga.get("winner", -1)) == int(gb.get("winner", -2)),
			"game %d: same winner across runs (%s vs %s)" % [
				i + 1, str(ga.get("winner", "?")), str(gb.get("winner", "?"))])
		_assert(int(ga.get("margin", -999)) == int(gb.get("margin", -998)),
			"game %d: same margin across runs (%s vs %s)" % [
				i + 1, str(ga.get("margin", "?")), str(gb.get("margin", "?"))])
		_assert(int(ga.get("vp_p1", -1)) == int(gb.get("vp_p1", -2))
				and int(ga.get("vp_p2", -1)) == int(gb.get("vp_p2", -2)),
			"game %d: same VP across runs (%d-%d vs %d-%d)" % [
				i + 1, int(ga.get("vp_p1", 0)), int(ga.get("vp_p2", 0)),
				int(gb.get("vp_p1", 0)), int(gb.get("vp_p2", 0))])
	# A different seed must give a genuinely different game, or "deterministic"
	# would just mean "every game collapses to the same one".
	if a.size() >= 2:
		var differs: bool = (int(a[0].get("actions", 0)) != int(a[1].get("actions", 0))
			or int(a[0].get("vp_p1", 0)) != int(a[1].get("vp_p1", 0))
			or int(a[0].get("vp_p2", 0)) != int(a[1].get("vp_p2", 0)))
		_assert(differs,
			"a different seed produced a different game (%d actions %d-%d vs %d actions %d-%d)" % [
				int(a[0].get("actions", 0)), int(a[0].get("vp_p1", 0)), int(a[0].get("vp_p2", 0)),
				int(a[1].get("actions", 0)), int(a[1].get("vp_p1", 0)), int(a[1].get("vp_p2", 0))])


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: %s" % label)
	else:
		_fail_count += 1
		print("  FAIL: %s" % label)


func _finish() -> void:
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)
