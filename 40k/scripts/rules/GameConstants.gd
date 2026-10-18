class_name GameConstants
extends RefCounted

## Centralized rules constants (ISS-002).
##
## Every rules distance/threshold that differs between editions — or that was
## previously duplicated as inline literals across phases/controllers/AI —
## lives here. Do NOT re-declare these as local constants; call the static
## functions so the edition switch applies everywhere at once.
##
## This is a static utility class on purpose (not an autoload): RulesEngine
## and AIDecisionMaker are largely static functions, and class_name statics
## are reachable from static contexts without a scene tree.
##
## Edition values:
##   10 — the legacy 10th-edition ruleset (regression suite only; explicit
##        opt-in via WH40K_TEST_EDITION=10 / --edition=10 or a test write).
##   11 — the 11th-edition core rules (default; the only edition players get).
## Enforced by tests/test_iss002_game_constants.gd.

## Active rules edition. The game is 11th edition only — every player launch
## runs at 11 (SettingsService re-asserts this at boot). The variable remains
## writable solely for the legacy regression suite: test harnesses also
## default to 11 (SettingsService._resolve_harness_edition) and reach 10e only
## through an explicit opt-in (WH40K_TEST_EDITION=10, --edition=10, a scenario
## "edition": 10 field, or a test write), until the 10e code paths are deleted.
static var edition: int = 11


# ── Engagement range ────────────────────────────────────────────────
## Horizontal engagement range. 10e: 1". 11e core rules 03.04: 2".
static func engagement_range_inches() -> float:
	return 2.0 if edition >= 11 else 1.0

## Vertical engagement range (both editions: 5").
static func engagement_range_vertical_inches() -> float:
	return 5.0

## T3-9 barricade rule: engagement range measured through a barricade is 2".
static func barricade_engagement_range_inches() -> float:
	return 2.0


# ── Reinforcements / Reserves ───────────────────────────────────────
## Minimum distance a unit set up from Reserves — Deep Strike, Strategic
## Reserves, Rapid Ingress — or via an infiltrate-style redeploy must be
## placed from all enemy models (edge-to-edge, "more than").
## 10e: >9". 11e (20.04 Ingress Move): >8".
static func reinforcement_min_enemy_distance_inches() -> float:
	return 8.0 if edition >= 11 else 9.0

## Minimum distance an INFILTRATORS unit must be set up from the enemy
## deployment zone and all enemy models (edge-to-edge, "more than").
## 10e: >9". 11e (24.20 Infiltrators): >8".
## Same value as the reserves stand-off today, but a separate rule with its own
## errata history — kept as its own accessor so one moving does not move the
## other. DeploymentPhase (the validator) and DeploymentController (the
## placement UI) must both read this: they disagreed for the whole of 11e,
## with the UI blocking legal 8-9" infiltrations the engine would have allowed.
static func infiltrators_min_enemy_distance_inches() -> float:
	return 8.0 if edition >= 11 else 9.0


# ── Unit coherency ──────────────────────────────────────────────────
## Horizontal distance to count as "in coherency" with another model
## (both editions: 2").
static func coherency_distance_inches() -> float:
	return 2.0

## Vertical coherency distance (both editions: 5").
static func coherency_vertical_inches() -> float:
	return 5.0

## 11e only (03.03): every model must ALSO be within this distance of EVERY
## other model in its unit. Exposed now for ISS-042; not used by 10e checks.
static func coherency_envelope_inches() -> float:
	return 9.0


# ── Visibility ──────────────────────────────────────────────────────
## 11e Hidden rule (13.09): default detection range for hidden models.
## Exposed now for ISS-052; not used by 10e checks.
static func hidden_detection_range_inches() -> float:
	return 15.0

## 11e Hidden refinements (review doc Tab 6; audit Tier-1 #4):
## "Gone to Ground" — a hidden model obscured behind a dense/Solid
## feature subtracts 3" from its detection range (15" → 12").
static func gone_to_ground_penalty_inches() -> float:
	return 3.0

## Detection-range modifiers (datasheet or Gone to Ground) can never
## take a model's detection range below 9" (review doc Tab 6).
static func detection_range_floor_inches() -> float:
	return 9.0
