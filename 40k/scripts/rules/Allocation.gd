class_name Allocation
extends RefCounted

## 11e save-roll allocation groups (ISS-041; core rules 05.03-05.04).
##
## In 11e the DEFENDER divides the target unit into allocation groups,
## declares their order under constraints, batch-rolls saves, and applies
## damage from the lowest save roll to the highest against the current
## group. This module is the engine core consumed by the 11e resolution
## flow (ISS-041 step 2) and the reworked wound-allocation UI (ISS-045).
##
## Group shape: {id, character: bool, model_indices: Array[int],
##               w: int, sv: int, insv: int, has_wounded: bool}

static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")


## 05.03 step 1 — Create Groups: one group per CHARACTER model; one group
## for all other models sharing the same W / Sv / InSv characteristics.
static func build_groups(unit: Dictionary) -> Array:
	var groups: Array = []
	var pool: Dictionary = {}  # "w|sv|insv" -> group
	var unit_stats = unit.get("meta", {}).get("stats", {})
	var unit_keywords: Array = unit.get("meta", {}).get("keywords", [])
	var models: Array = unit.get("models", [])
	for i in range(models.size()):
		var m = models[i]
		if not m.get("alive", true):
			continue
		var w = int(m.get("wounds", unit_stats.get("wounds", 1)))
		var cur_w = int(m.get("current_wounds", w))
		var sv = int(m.get("save", unit_stats.get("save", 7)))
		var insv = int(m.get("invuln", unit_stats.get("invuln", 0)))
		var is_char = "CHARACTER" in m.get("keywords", []) or ("CHARACTER" in unit_keywords and models.size() == 1)
		# In attached units, character models are marked per-model; a
		# single-model CHARACTER unit is its own character group.
		if m.get("is_character", false):
			is_char = true
		if is_char:
			groups.append({
				"id": "char_%d" % i, "character": true, "model_indices": [i],
				"w": w, "sv": sv, "insv": insv, "has_wounded": cur_w < w,
			})
		else:
			var key = "%d|%d|%d" % [w, sv, insv]
			if not pool.has(key):
				pool[key] = {
					"id": "grp_%s" % key.replace("|", "_"), "character": false,
					"model_indices": [], "w": w, "sv": sv, "insv": insv,
					"has_wounded": false,
				}
			pool[key].model_indices.append(i)
			if cur_w < w:
				pool[key].has_wounded = true
	for key in pool:
		groups.append(pool[key])
	return groups


## 05.03 step 2 — Allocation Order constraints:
##  ▫ a non-CHARACTER group containing a wounded model must be FIRST
##  ▫ no CHARACTER group earlier than any non-CHARACTER group
##  ▫ wounded CHARACTER groups before unwounded CHARACTER groups
## Returns {valid: bool, errors: Array}.
static func validate_order(groups: Array, order: Array) -> Dictionary:
	var errors: Array = []
	var by_id: Dictionary = {}
	for g in groups:
		by_id[g.id] = g
	if order.size() != groups.size():
		errors.append("order must include every group exactly once")
		return {"valid": false, "errors": errors}
	for gid in order:
		if not by_id.has(gid):
			errors.append("unknown group id '%s'" % gid)
			return {"valid": false, "errors": errors}

	var seq: Array = []
	for gid in order:
		seq.append(by_id[gid])

	# Wounded non-CHARACTER group must be first in the order.
	for g in groups:
		if not g.character and g.has_wounded and seq[0].id != g.id:
			errors.append("the wounded non-CHARACTER group must be first in the allocation order")
			break

	# No CHARACTER group earlier than a non-CHARACTER group.
	var seen_character := false
	for g in seq:
		if g.character:
			seen_character = true
		elif seen_character:
			errors.append("no CHARACTER group may come before a non-CHARACTER group")
			break

	# Wounded CHARACTER groups before unwounded CHARACTER groups.
	var seen_unwounded_char := false
	for g in seq:
		if not g.character:
			continue
		if not g.has_wounded:
			seen_unwounded_char = true
		elif seen_unwounded_char:
			errors.append("wounded CHARACTER groups must come before unwounded CHARACTER groups")
			break

	return {"valid": errors.is_empty(), "errors": errors}


## A legal default order: wounded non-CHARACTER group first, remaining
## non-CHARACTER groups, then wounded CHARACTER groups, then the rest.
static func default_order(groups: Array) -> Array:
	var wounded_nc: Array = []
	var nc: Array = []
	var wounded_c: Array = []
	var c: Array = []
	for g in groups:
		if g.character:
			(wounded_c if g.has_wounded else c).append(g.id)
		else:
			(wounded_nc if g.has_wounded else nc).append(g.id)
	return wounded_nc + nc + wounded_c + c


## 05.04 — Inflict Damage. Given the ordered groups, the batch of save
## rolls, and the attack profile, apply damage from the LOWEST roll to the
## highest against the current allocation group (next group becomes
## current when the previous one is destroyed). Wounded models are
## selected first within a group. Excess attacks are lost when the unit
## dies.
##
## `unit` models are read for current wounds; the function does NOT mutate
## state — it returns {events: [...], casualties, damage_total,
## models_destroyed: [indices], remaining: {index: wounds}} for the caller
## to turn into diffs.
static func apply_save_rolls(unit: Dictionary, groups: Array, order: Array, save_rolls: Array, ap: int, damage: int) -> Dictionary:
	var by_id: Dictionary = {}
	for g in groups:
		by_id[g.id] = g
	var models: Array = unit.get("models", [])
	var unit_stats = unit.get("meta", {}).get("stats", {})

	# Working copy of remaining wounds per model index.
	var remaining: Dictionary = {}
	for g in groups:
		for i in g.model_indices:
			var w = int(models[i].get("wounds", unit_stats.get("wounds", 1)))
			remaining[i] = int(models[i].get("current_wounds", w))

	var sorted_rolls = save_rolls.duplicate()
	sorted_rolls.sort()  # lowest first (05.04)

	var events: Array = []
	var destroyed: Array = []
	var damage_total := 0
	var group_cursor := 0

	for roll in sorted_rolls:
		# Advance to the current (non-destroyed) group.
		while group_cursor < order.size():
			var g = by_id[order[group_cursor]]
			var alive_in_group := false
			for i in g.model_indices:
				if remaining.get(i, 0) > 0:
					alive_in_group = true
					break
			if alive_in_group:
				break
			group_cursor += 1
		if group_cursor >= order.size():
			events.append({"roll": roll, "result": "lost", "reason": "unit destroyed — excess attacks are lost"})
			continue

		var group = by_id[order[group_cursor]]
		# Select model: a wounded model if possible (05.04 step 1).
		var target_i := -1
		for i in group.model_indices:
			var w = int(models[i].get("wounds", unit_stats.get("wounds", 1)))
			if remaining.get(i, 0) > 0 and remaining[i] < w:
				target_i = i
				break
		if target_i == -1:
			for i in group.model_indices:
				if remaining.get(i, 0) > 0:
					target_i = i
					break

		# Check Save Roll (05.04 step 2): unmodified 1 fails; invuln
		# (unmodified) vs AP-modified armour — best applies.
		var inflicts := false
		if roll == 1:
			inflicts = true
		else:
			var saved := false
			if group.insv > 0 and roll >= group.insv:
				saved = true
			elif roll + ap >= group.sv:  # ap is negative or 0
				saved = true
			inflicts = not saved

		if inflicts:
			var dealt = min(damage, remaining[target_i])
			remaining[target_i] -= damage
			damage_total += dealt
			if remaining[target_i] <= 0:
				remaining[target_i] = 0
				destroyed.append(target_i)
			events.append({"roll": roll, "result": "damage", "model_index": target_i,
				"damage": dealt, "destroyed": remaining[target_i] == 0})
		else:
			events.append({"roll": roll, "result": "saved", "model_index": target_i, "group": group.id})

	return {
		"events": events,
		"casualties": destroyed.size(),
		"models_destroyed": destroyed,
		"damage_total": damage_total,
		"remaining": remaining,
	}


# ── 11e mortal wounds (ISS-046; 06.02 + 24.10) ──────────────────────

## 06.02 model-selection priority for each mortal wound:
##   1. a wounded non-CHARACTER model, else
##   2. any non-CHARACTER model, else
##   3. a wounded CHARACTER model, else
##   4. any CHARACTER model.
## Returns the model index, or -1 when the unit is destroyed.
static func select_mortal_wound_target(unit: Dictionary, remaining: Dictionary) -> int:
	var models: Array = unit.get("models", [])
	var unit_stats = unit.get("meta", {}).get("stats", {})
	var unit_keywords: Array = unit.get("meta", {}).get("keywords", [])
	var candidates := {"wnc": -1, "nc": -1, "wc": -1, "c": -1}
	for i in range(models.size()):
		if remaining.get(i, 0) <= 0:
			continue
		var m = models[i]
		var w = int(m.get("wounds", unit_stats.get("wounds", 1)))
		var wounded: bool = remaining[i] < w
		var is_char: bool = m.get("is_character", false) \
			or "CHARACTER" in m.get("keywords", []) \
			or ("CHARACTER" in unit_keywords and models.size() == 1)
		if not is_char and wounded and candidates.wnc == -1:
			candidates.wnc = i
		elif not is_char and candidates.nc == -1:
			candidates.nc = i
		elif is_char and wounded and candidates.wc == -1:
			candidates.wc = i
		elif is_char and candidates.c == -1:
			candidates.c = i
	for key in ["wnc", "nc", "wc", "c"]:
		if candidates[key] != -1:
			return candidates[key]
	return -1


## 06.02 — apply `count` mortal wounds one at a time (after all normal
## damage), re-selecting the target model per wound, until they are all
## inflicted or the unit is destroyed. Non-mutating; returns
## {applied, lost, models_destroyed, remaining, events}.
static func apply_mortal_wounds_11e(unit: Dictionary, count: int) -> Dictionary:
	var models: Array = unit.get("models", [])
	var unit_stats = unit.get("meta", {}).get("stats", {})
	var remaining: Dictionary = {}
	for i in range(models.size()):
		if models[i].get("alive", true):
			var w = int(models[i].get("wounds", unit_stats.get("wounds", 1)))
			remaining[i] = int(models[i].get("current_wounds", w))
	var out := {"applied": 0, "lost": 0, "models_destroyed": [], "remaining": remaining, "events": []}
	for _n in range(count):
		var target = select_mortal_wound_target(unit, remaining)
		if target == -1:
			out.lost = count - out.applied
			break
		remaining[target] -= 1
		out.applied += 1
		out.events.append({"model_index": target, "destroyed": remaining[target] <= 0})
		if remaining[target] <= 0:
			remaining[target] = 0
			out.models_destroyed.append(target)
	return out


## 24.10 — [DEVASTATING WOUNDS]: each critical wound inflicts D mortal
## wounds that may damage AT MOST ONE model; any of that crit's mortal
## wounds beyond what destroys the selected model are LOST. Worked example
## (pg 80): D3=3 dev wounds vs W2 Intercessors -> 2 MW destroy one model,
## the third is lost. Non-mutating; same return shape as above.
static func apply_devastating_wounds_11e(unit: Dictionary, crit_count: int, damage_per_crit: int) -> Dictionary:
	var models: Array = unit.get("models", [])
	var unit_stats = unit.get("meta", {}).get("stats", {})
	var remaining: Dictionary = {}
	for i in range(models.size()):
		if models[i].get("alive", true):
			var w = int(models[i].get("wounds", unit_stats.get("wounds", 1)))
			remaining[i] = int(models[i].get("current_wounds", w))
	var out := {"applied": 0, "lost": 0, "models_destroyed": [], "remaining": remaining, "events": []}
	for _c in range(crit_count):
		var target = select_mortal_wound_target(unit, remaining)
		if target == -1:
			out.lost += damage_per_crit
			continue
		var dealt = min(damage_per_crit, remaining[target])
		remaining[target] -= dealt
		out.applied += dealt
		out.lost += damage_per_crit - dealt
		out.events.append({"model_index": target, "damage": dealt,
			"lost": damage_per_crit - dealt, "destroyed": remaining[target] <= 0})
		if remaining[target] <= 0:
			remaining[target] = 0
			out.models_destroyed.append(target)
	return out
