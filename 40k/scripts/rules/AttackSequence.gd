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
## Runtime autoload lookup: referencing the RulesEngine identifier at
## compile time fails when this class_name script is compiled in bare
## `godot -s` contexts before autoloads register (benign in-game, but the
## ERROR line trips the no-errors validation gate).
static func _rules() -> Node:
	return Engine.get_main_loop().root.get_node("/root/RulesEngine")


static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")


static func evaluate_hit_roll(raw_roll: int, threshold: int, modifiers: int, crit_threshold: int, rng, fail_unmodified_at_or_below: int = 1) -> Dictionary:
	var mod = _rules().apply_hit_modifiers(raw_roll, modifiers, rng, threshold)
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
	var mod = _rules().apply_wound_modifiers(raw_roll, modifiers, wound_threshold, rng)
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


# ── 11e hazard rolls (ISS-044, core rules 06.03) ────────────────────
## Make `count` hazard rolls for a unit, all rolled simultaneously
## (06.03). Each roll fails on a 1-2; each failure inflicts 1 mortal
## wound — or 3 mortal wounds if EVERY model in the unit is a
## MONSTER/VEHICLE model.
##
## Consumers (when their 11e issues land): [HAZARDOUS] weapons after
## attacks resolve (24.15), desperate-escape fall-backs (09.07), combat
## and emergency disembarks (18.04/18.05).
##
## Returns {rolls: Array[int], failures: int, mortal_wounds: int,
## per_model_mw: int}.
static func hazard_rolls(unit: Dictionary, count: int, rng, roll_modifier: int = 0) -> Dictionary:
	# roll_modifier is added to each die before the fail check — CUT' EM DOWN
	# (Bully Boyz) subtracts 1 from Desperate Escape tests while a Waaagh! is
	# active for the Nobz/Meganobz unit.
	var out := {"rolls": [], "failures": 0, "mortal_wounds": 0, "per_model_mw": 1}
	if count <= 0:
		return out
	# "3 mortal wounds instead if each model in that unit is a
	# MONSTER/VEHICLE model" — checked on the unit's alive models.
	var all_mv := true
	var any_alive := false
	var unit_keywords: Array = unit.get("meta", {}).get("keywords", [])
	var unit_is_mv := "MONSTER" in unit_keywords or "VEHICLE" in unit_keywords
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		any_alive = true
		var kw = model.get("keywords", [])
		var model_is_mv = unit_is_mv or "MONSTER" in kw or "VEHICLE" in kw
		if not model_is_mv:
			all_mv = false
			break
	if any_alive and all_mv:
		out.per_model_mw = 3
	# 06.03: simultaneous rolls.
	out.rolls = rng.roll_d6(count)
	for roll in out.rolls:
		if roll + roll_modifier <= 2:
			out.failures += 1
	out.mortal_wounds = out.failures * out.per_model_mw
	return out


# ── Leadership & battle-shock primitives (ISS-043, 01.06-01.07, 08.03) ──
## Make a leadership roll for a unit: 2D6, succeeds if the result is >= the
## (best/lowest) Ld characteristic in the unit. The mechanic is identical
## in 10e and 11e; what changes at edition 11 is WHO tests in the
## battle-shock step and the recovery effect (see battleshock_step_required
## below). Returns {dice: [d1, d2], total, threshold, success}.
static func leadership_roll(unit: Dictionary, rng) -> Dictionary:
	var threshold := 7  # conventional default when no Ld present
	var st = unit.get("meta", {}).get("stats", {})
	if st.has("leadership"):
		threshold = int(st.leadership)
	var dice = rng.roll_d6(2)
	var total: int = dice[0] + dice[1]
	return {"dice": dice, "total": total, "threshold": threshold, "success": total >= threshold}


## Battle-shock step eligibility (Command phase).
## 10e: units BELOW half-strength must test; battle-shock persists until
##      the controlling player's next Command phase (no recovery roll).
## 11e (08.03): units that are battle-shocked OR at-or-below half-strength
##      must test, and a battle-shocked unit that passes RECOVERS.
## `below_half` / `at_half` are computed by the caller (GameState owns the
## starting-strength bookkeeping).
static func battleshock_test_required(is_battle_shocked: bool, below_half: bool, at_half: bool) -> bool:
	if GameConstants.edition >= 11:
		return is_battle_shocked or below_half or at_half
	return below_half


## State after a battle-shock roll: pass -> not shocked, fail -> shocked.
## The 11e recovery rule (08.03) emerges from ELIGIBILITY, not outcome:
## 11e offers already-shocked units the roll (pass recovers them); 10e
## never retests a shocked unit, so the pass-while-shocked case cannot
## occur there.
static func battleshock_outcome(roll_success: bool) -> bool:
	return not roll_success


# ── Unit coherency (ISS-042, 10e rules / 11e 03.03) ─────────────────
## Edition-aware coherency check for a unit's alive, positioned models.
## 10e: every model within 2" (5" vertical) of at least 1 other model
##      (2 other models when the unit has 7+ models).
## 11e (03.03): every model within 2"/5" of at least ONE other model AND
##      within 9" (horizontal) of EVERY other model in the unit.
## Returns {coherent: bool, offenders: [model ids]}. Single-model units
## are always coherent.
static func check_unit_coherency(unit: Dictionary) -> Dictionary:
	var models: Array = []
	for m in unit.get("models", []):
		if m.get("alive", true) and m.get("position") != null:
			models.append(m)
	if models.size() <= 1:
		return {"coherent": true, "offenders": []}

	var coh_px = _measurement().inches_to_px(GameConstants.coherency_distance_inches())
	var required_neighbors := 1
	if GameConstants.edition < 11 and models.size() >= 7:
		required_neighbors = 2
	var envelope_px := 0.0
	if GameConstants.edition >= 11:
		envelope_px = _measurement().inches_to_px(GameConstants.coherency_envelope_inches())

	var offenders: Array = []
	for i in range(models.size()):
		var neighbors := 0
		var envelope_ok := true
		for j in range(models.size()):
			if i == j:
				continue
			var dist_px = _measurement().model_to_model_distance_px(models[i], models[j])
			if dist_px <= coh_px:
				neighbors += 1
			if envelope_px > 0.0 and dist_px > envelope_px:
				envelope_ok = false
		if neighbors < required_neighbors or not envelope_ok:
			offenders.append(str(models[i].get("id", i)))
	return {"coherent": offenders.is_empty(), "offenders": offenders}


# ── Identical-attack gathering (ISS-041 step 2; 11e 04.03) ──────────
## 04.03 box: "Identical attacks are those that have the same BS/WS, S,
## AP and D characteristics, and which are affected by the same
## applicable abilities and rules." Attacks can only be gathered together
## when they also target the same unit.
##
## The key canonicalizes the weapon profile's skill / S / AP / D-notation
## plus its structured ability list (AbilityRegistry); two weapons with
## the same key targeting the same unit may have their attack dice
## gathered and resolved as one batch.
##
## Targeting/eligibility-only abilities do NOT change what an attack does
## once it is being resolved, so they are excluded from the identity —
## the pg-20 worked example gathers a bolt pistol's attack die together
## with the boltguns'.
const NON_RESOLUTION_ABILITIES := ["pistol", "assault", "extra_attacks"]

static func attack_identity_key(weapon_profile: Dictionary, target_unit_id: String) -> String:
	var skill = weapon_profile.get("ws", weapon_profile.get("bs", 4))
	var strength = weapon_profile.get("strength", 4)
	var ap = weapon_profile.get("ap", 0)
	var damage_raw = str(weapon_profile.get("damage_raw", str(weapon_profile.get("damage", 1))))
	var ability_parts: Array = []
	for entry in AbilityRegistry.from_weapon(weapon_profile):
		if entry is Dictionary:
			if str(entry.get("id", "")) in NON_RESOLUTION_ABILITIES:
				continue
			var keys = entry.keys()
			keys.sort()
			var fields: Array = []
			for k in keys:
				fields.append("%s=%s" % [str(k), str(entry[k])])
			ability_parts.append(",".join(fields))
	ability_parts.sort()
	return "%s|skill=%s|s=%s|ap=%s|d=%s|abilities=[%s]" % [
		target_unit_id, str(skill), str(strength), str(ap), damage_raw,
		";".join(ability_parts)]


## Group weapon assignments ({weapon_id, target_unit_id, model_ids, …})
## into gatherable batches per 04.03. Returns an Array of
## {key, target_unit_id, assignment_indices: [int], weapon_ids: [String]}
## in first-seen order; assignments whose weapon profile cannot be
## resolved get a group of their own.
static func gather_identical_attacks(assignments: Array, board: Dictionary) -> Array:
	var groups: Array = []
	var by_key: Dictionary = {}
	for i in range(assignments.size()):
		var assignment = assignments[i]
		var weapon_id = str(assignment.get("weapon_id", ""))
		var target_unit_id = str(assignment.get("target_unit_id", ""))
		var profile = _rules().get_weapon_profile(weapon_id, board)
		var key: String
		if profile.is_empty():
			key = "__unresolved_%d" % i
		else:
			key = attack_identity_key(profile, target_unit_id)
		# Overwatch/override flags change the applicable rules (04.03):
		# only gather attacks resolved under the same special conditions.
		if assignment.get("overwatch", false):
			key += "|overwatch"
		if assignment.has("attacks_override") and assignment.attacks_override != null:
			key += "|override_%d" % i
		if not by_key.has(key):
			by_key[key] = {"key": key, "target_unit_id": target_unit_id,
				"assignment_indices": [], "weapon_ids": []}
			groups.append(by_key[key])
		by_key[key].assignment_indices.append(i)
		if not weapon_id in by_key[key].weapon_ids:
			by_key[key].weapon_ids.append(weapon_id)
	return groups
