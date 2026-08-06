class_name AIGameRecord
extends RefCounted

# M1 — the `wh40k_ai_game_record` schema.
#
# One record per benchmark game: the AI's own decision records joined to the
# outcome they produced, the intermediate VP awards along the way, and enough
# provenance to know exactly what environment produced them.
#
# Why this file exists separately from AIBenchmarkRunner: the runner is an
# autoload that touches GameState/MissionManager/AIPlayer, so it cannot be
# compiled outside a running game — which would make the schema untestable
# without standing up a 6-minute match. Everything here is pure data assembly
# with no autoload dependencies, so tests/test_game_record_export.gd can
# exercise it directly.
#
# What the record is FOR: before M1, `AIDecisionMaker._add_decision_record`
# built a complete "here were my options, here is how I scored each one, here
# is what I picked, here are the parameters I used" trace for every decision —
# and every one of them was discarded when the process exited. The outcome was
# written to a separate JSON that had no idea the decisions existed. Nothing
# ever joined them, so nothing could ever learn from them.
#
# Provenance is NOT optional. Every AI baseline predating 2026-08-06 was tuned
# on a fixture that contained an army-list header row imported as a unit
# (points 2000, keywords ["UNKNOWN"]), which inflated army totals and doubled
# the Strategic Reserves cap. Nothing recorded which fixture a result came
# from, so the corruption was invisible and every historical tuning decision
# became suspect at once. fixture_sha256 + git_sha + inline profiles make a
# record auditable on its own and make cross-era pooling detectable.

const SCHEMA := "wh40k_ai_game_record"
const SCHEMA_VERSION := 1


## Assemble one game record.
##
## game_id      stable identity, derived from the result file's basename
## provenance   see build_provenance() — fixture/profile/engine/git identity
## outcome      the benchmark result dict verbatim (AIBenchmarkRunner._collect_result)
## vp_events    [{round, phase, player, points, reason, wall_seconds}, ...]
## decisions    AIPlayer._all_decision_records verbatim (batches of records)
## action_log   AIPlayer._action_log verbatim
## batches_total / batches_dropped
##              monotonic counters. A nonzero dropped count means the ring
##              buffer ate decisions and this game's trace is biased toward
##              its END — it must be visible to the analysis layer, never
##              silently swallowed.
static func build(game_id: String, provenance: Dictionary, outcome: Dictionary,
		vp_events: Array, decisions: Array, action_log: Array,
		batches_total: int, batches_dropped: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"game_id": game_id,
		"provenance": provenance,
		"outcome": outcome,
		"vp_events": vp_events,
		"decisions": decisions,
		"action_log": action_log,
		"decision_batches_total": batches_total,
		"decision_batches_dropped": batches_dropped,
	}


## Build the provenance block. Kept here (rather than in the runner) so the
## required key set is defined in one place and can be asserted by tests.
static func build_provenance(git_sha: String, engine: String, fixture: String,
		fixture_path: String, fixture_sha256: String, p1_profile: Dictionary,
		p2_profile: Dictionary, difficulty: int, seed_value: int,
		time_scale: float, arm: String) -> Dictionary:
	return {
		"git_sha": git_sha,
		"engine": engine,
		"fixture": fixture,
		"fixture_path": fixture_path,
		"fixture_sha256": fixture_sha256,
		"p1_profile": p1_profile,
		"p2_profile": p2_profile,
		"difficulty": {"1": difficulty, "2": difficulty},
		"seed": seed_value,
		"time_scale": time_scale,
		"arm": arm,
		"schema_note": "decision records cover: movement, shooting, charge, fight",
	}


## The keys every record's provenance must carry for a game to be poolable
## with any other game. build_index.py reads all of these.
static func required_provenance_keys() -> Array:
	return ["git_sha", "engine", "fixture", "fixture_sha256",
		"p1_profile", "p2_profile", "difficulty", "seed", "time_scale"]


## Structural validation, so a malformed record is caught at write time rather
## than surfacing as a confusing gap three thousand games into a season.
## Returns an array of human-readable problems; empty means valid.
static func validate(record: Dictionary) -> Array:
	var errors: Array = []
	if record.get("schema", "") != SCHEMA:
		errors.append("schema is %s, expected %s" % [record.get("schema", "<missing>"), SCHEMA])
	if int(record.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version is %s, expected %d" % [
			record.get("schema_version", "<missing>"), SCHEMA_VERSION])
	if str(record.get("game_id", "")) == "":
		errors.append("game_id is empty")
	for key in ["provenance", "outcome"]:
		if not (record.get(key) is Dictionary):
			errors.append("%s is missing or not a Dictionary" % key)
	for key in ["vp_events", "decisions", "action_log"]:
		if not (record.get(key) is Array):
			errors.append("%s is missing or not an Array" % key)
	var prov = record.get("provenance", {})
	if prov is Dictionary:
		for key in required_provenance_keys():
			if not prov.has(key):
				errors.append("provenance is missing %s" % key)
	var outcome = record.get("outcome", {})
	if outcome is Dictionary and not outcome.has("status"):
		errors.append("outcome is missing status")
	return errors
