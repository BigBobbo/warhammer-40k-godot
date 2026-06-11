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
