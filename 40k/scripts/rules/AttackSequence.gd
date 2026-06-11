class_name AttackSequence
extends RefCounted

## Shared per-roll attack evaluation (ISS-012).
##
## The three resolution paths in RulesEngine (ranged interactive
## `_resolve_assignment`, ranged auto-resolve, melee
## `_resolve_melee_assignment`) previously each carried their own copy of
## the hit-roll and wound-roll evaluation bodies. Those bodies now live
## here, parameterized; the paths keep their own orchestration and dice-
## record assembly (pinned byte-for-byte by tests/fixtures/attack_goldens.json
## via tests/test_iss012_attack_goldens.gd).
##
## The 11e attack-sequence rework (ISS-041) replaces the orchestration on
## top of these primitives.

## Evaluate one hit roll.
## - threshold: the BS/WS target for this attack (per-model aware).
## - modifiers: RulesEngine.HitModifier bitfield.
## - crit_threshold: unmodified value that counts as a critical hit
##   (6 normally; lower with Conversion / Martial Mastery).
## - fail_unmodified_at_or_below: unmodified results <= this always miss
##   (1 normally; 3 for INDIRECT FIRE at an unseen target).
## RNG consumption is identical to the legacy inline bodies: exactly the
## re-roll inside RulesEngine.apply_hit_modifiers.
static func evaluate_hit_roll(raw_roll: int, threshold: int, modifiers: int, crit_threshold: int, rng, fail_unmodified_at_or_below: int = 1) -> Dictionary:
	var mod = RulesEngine.apply_hit_modifiers(raw_roll, modifiers, rng, threshold)
	var unmodified: int = mod.reroll_value if mod.rerolled else raw_roll
	var out := {
		"final_roll": mod.modified_roll,
		"unmodified": unmodified,
		"rerolled": mod.rerolled,
		"reroll_from": mod.original_roll if mod.rerolled else 0,
		"reroll_to": mod.reroll_value if mod.rerolled else 0,
		"is_hit": false,
		"is_crit": false,
	}
	# Auto-miss band is checked on the unmodified roll BEFORE the crit check
	# (an unmodified 2 can never crit through Conversion while indirect-unseen).
	if unmodified <= fail_unmodified_at_or_below:
		return out
	if unmodified >= crit_threshold or out.final_roll >= threshold:
		out.is_hit = true
		out.is_crit = unmodified >= crit_threshold
	return out


## Evaluate one wound roll.
## - wound_threshold: from the S-vs-T chart.
## - crit_threshold: unmodified value that counts as a critical wound
##   (6 normally; the X+ of an applicable ANTI keyword).
## Unmodified 1 always fails (auto_fail). Critical wounds are checked on
## the unmodified roll per 10e rules.
static func evaluate_wound_roll(raw_roll: int, modifiers: int, wound_threshold: int, crit_threshold: int, rng) -> Dictionary:
	var mod = RulesEngine.apply_wound_modifiers(raw_roll, modifiers, wound_threshold, rng)
	var unmodified: int = mod.reroll_value if mod.rerolled else raw_roll
	var out := {
		"final_roll": mod.modified_roll,
		"unmodified": unmodified,
		"rerolled": mod.rerolled,
		"reroll_from": mod.original_roll if mod.rerolled else 0,
		"reroll_to": mod.reroll_value if mod.rerolled else 0,
		"auto_fail": unmodified == 1,
		"is_wound": false,
		"is_crit": false,
	}
	if out.auto_fail:
		return out
	var is_crit := unmodified >= crit_threshold
	if is_crit or out.final_roll >= wound_threshold:
		out.is_wound = true
		out.is_crit = is_crit
	return out


# ── Analytic expectations (ISS-014) ─────────────────────────────────
# Single source for the probability math the AI (and any forecaster) uses.
# Semantics match the live evaluators above: an unmodified 1 always fails,
# and an unmodified critical (6) always hits/wounds — so hit/wound
# probabilities are clamped to [1/6, 5/6]. Save rolls have no auto-success,
# so P(save) ranges [0, 5/6].

## The 10e/11e S-vs-T wound chart (2..6). RulesEngine._calculate_wound_threshold
## delegates here so the chart exists exactly once.
static func wound_threshold(strength: int, toughness: int) -> int:
	if strength >= toughness * 2:
		return 2
	elif strength > toughness:
		return 3
	elif strength == toughness:
		return 4
	elif strength * 2 <= toughness:
		return 6
	else:
		return 5


## P(hit) for an attack needing `threshold`+ (engine-true: nat 1 misses,
## nat 6 hits, so clamped to [1/6, 5/6]).
static func hit_probability(threshold: int) -> float:
	return clampf((7.0 - threshold) / 6.0, 1.0 / 6.0, 5.0 / 6.0)


## P(wound) for strength vs toughness (engine-true clamp as above).
static func wound_probability(strength: int, toughness: int) -> float:
	return clampf((7.0 - wound_threshold(strength, toughness)) / 6.0, 1.0 / 6.0, 5.0 / 6.0)


## P(save PASSES) for armour `save_val` modified by `ap`, using an
## invulnerable save instead when better (invulns ignore AP). A natural 1
## always fails, so the ceiling is 5/6; an impossible save is 0.
static func save_probability(save_val: int, ap: int, invuln: int = 0) -> float:
	var modified_save = save_val + abs(ap)
	if invuln > 0 and invuln < modified_save:
		modified_save = invuln
	return clampf((7.0 - modified_save) / 6.0, 0.0, 5.0 / 6.0)
