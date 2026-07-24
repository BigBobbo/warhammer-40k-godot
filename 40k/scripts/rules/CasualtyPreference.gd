class_name CasualtyPreference
extends RefCounted

## Defender casualty-order brain for automatic wound allocation — used when
## the defender is an AI player, or when the human defender enabled the
## "Computer allocates wounds (auto-remove models)" setting.
##
## Produces the `preferred_targets` array consumed by
## Allocation.apply_save_rolls / RulesEngine.resolve_allocation_batch_11e:
## ALIVE model indices ordered die-first. Within an allocation group every
## model shares W/Sv/InSv, so this order only ever changes WHICH base is
## removed — never how much damage the unit takes (test_defender_control
## case C pins that invariant). The 05.04 wounded-model-first rule and the
## 05.03 group order still bind — the engine applies this preference only
## where the rules leave the defender a free choice.
##
## Scoring (higher keep-score = removed later):
##  ▫ value     — CHARACTER models, sergeant-type models and special/heavy
##                weapon carriers are kept longest ("remove lowest value
##                first; sergeants and special weapons last")
##  ▫ proximity — models closest to the enemy die first (front-rank
##                removal: it thins engagement/pile-in reach)
##  ▫ charge    — when an enemy unit is inside charge-threat range, the
##                model it would measure its charge against is worth extra:
##                removing it lengthens next turn's charge roll
##  ▫ objective — models keeping the unit inside control range of an
##                objective whose control would flip are protected
##                (OC counts once per unit — MissionManager math — so what
##                matters is keeping AT LEAST one body in range)
##  ▫ coherency — the final order is built greedily so each casualty leaves
##                the survivors in unit coherency whenever possible (never
##                remove the "bridge" model while an end model will do)
##
## Objective range uses MissionManager.model_in_objective_range — the SAME
## shared predicate objective control itself uses — so terrain-hosted
## objectives (11e 14.01: the hosting AREA is the objective, base-overlap
## counts, the marker radius does not) are measured accurately; the classic
## 3" + 20mm marker radius applies on open ground, and is also the fallback
## when MissionManager is unavailable. Leadership/board-role nuances beyond
## the factors above are out of scope.

const KEEP_CHARACTER: float = 100000.0        # engine group order protects them anyway; belt & braces
const KEEP_SERGEANT: float = 600.0            # sergeant-type models: last non-character picks
const KEEP_SPECIAL_WEAPON_MAX: float = 400.0  # cap for special/heavy wargear carriers
const SPECIAL_WEAPON_WEIGHT: float = 300.0    # per minority weapon, scaled by rarity
const KEEP_OBJECTIVE_AT_STAKE: float = 250.0  # in control range and losing the unit's OC flips the marker
const KEEP_OBJECTIVE_PRESENCE: float = 40.0   # in control range, control not currently at stake
const KEEP_WOUNDED: float = -50.0             # 05.04 forces wounded first anyway; keep our order consistent
const PROXIMITY_MAX: float = 100.0            # farthest-from-enemy keep bonus
const PROXIMITY_NORM_INCHES: float = 24.0     # distance at which the proximity bonus saturates
const CHARGE_DENIAL_MAX: float = 80.0         # per threatening enemy unit, for its closest target model
const CHARGE_DENIAL_CAP: float = 120.0        # total charge-denial a single model can accumulate
const CHARGE_THREAT_RANGE_INCHES: float = 15.0  # enemy closer than this could plausibly charge next turn
const CHARGE_GAIN_NORM_INCHES: float = 2.0    # denial saturates when removal buys 2"+ of charge distance
const OBJECTIVE_CONTROL_RANGE_INCHES: float = 3.78740157  # 3" + 20mm marker radius (mirrors MissionManager)

const SERGEANT_TOKENS: Array = [
	"sergeant", "serjeant", "sarge", "nob", "champion", "superior",
	"exarch", "aspiring", "kaptin", "prime", "leader", "boss", "princeps",
]


static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")


static func _mission_manager() -> Node:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("MissionManager")


## Main entry. `unit` is the (possibly attached-composite) defending unit
## whose model indices the allocation engine will consume; `state` is the
## full game-state dictionary (units + board.objectives). Returns the
## die-first order of all alive model indices.
static func compute_preferred_targets(unit: Dictionary, state: Dictionary, opts: Dictionary = {}) -> Array:
	var models: Array = unit.get("models", [])
	var alive: Array = []
	for i in range(models.size()):
		if models[i].get("alive", true):
			alive.append(i)
	if alive.size() <= 1:
		return alive

	var defender: int = int(opts.get("defender_player", unit.get("owner", 0)))
	var enemy_units: Array = _gather_enemy_units(state, defender)
	var dist_rows: Dictionary = _distance_matrix(models, alive, enemy_units)
	var special_keep: Dictionary = _special_weapon_keep(unit, alive)
	var objective_keep: Dictionary = _objective_keep(unit, alive, state, defender)
	var charge_keep: Dictionary = _charge_denial_keep(alive, enemy_units, dist_rows)
	var unit_stats: Dictionary = unit.get("meta", {}).get("stats", {})

	var keep: Dictionary = {}
	for i in alive:
		var m: Dictionary = models[i]
		var score: float = 0.0
		if _is_character_model(unit, m):
			score += KEEP_CHARACTER
		if _is_sergeant_like(unit, m):
			score += KEEP_SERGEANT
		score += float(special_keep.get(i, 0.0))
		score += float(objective_keep.get(i, 0.0))
		var row: Array = dist_rows.get(i, [])
		if not row.is_empty():
			var nearest: float = row.min()
			score += PROXIMITY_MAX * clampf(nearest / PROXIMITY_NORM_INCHES, 0.0, 1.0)
		score += float(charge_keep.get(i, 0.0))
		var w: int = int(m.get("wounds", unit_stats.get("wounds", 1)))
		if int(m.get("current_wounds", w)) < w:
			score += KEEP_WOUNDED
		keep[i] = score

	var order: Array = _coherency_aware_order(unit, alive, keep)

	var parts: Array = []
	for i in order:
		parts.append("%s=%.0f" % [str(models[i].get("id", i)), keep[i]])
	var line := "[CasualtyPreference] %s die-first order (idx=%s): %s" % [
		str(unit.get("id", unit.get("meta", {}).get("name", "?"))), str(order), ", ".join(parts)]
	print(line)
	# Mirror into the persistent debug log (stdout isn't always reachable).
	var loop = Engine.get_main_loop()
	var dl = loop.root.get_node_or_null("DebugLogger") if loop != null and loop.root != null else null
	if dl != null and dl.has_method("info"):
		dl.info(line, {})
	return order


## Engine-side hook for the non-interactive resolve paths (AI vs AI, or an
## AI defender resolved without the overlay). Returns [] — "engine default"
## — unless the defending player is actually AI-controlled, so human
## defenders and headless tests keep today's lowest-index behaviour.
static func engine_auto_preference(target_unit: Dictionary, state: Dictionary) -> Array:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return []
	var ai = loop.root.get_node_or_null("AIPlayer")
	if ai == null or not ai.has_method("is_ai_player"):
		return []
	var owner: int = int(target_unit.get("owner", 0))
	if owner <= 0 or not ai.is_ai_player(owner):
		return []
	return compute_preferred_targets(target_unit, state, {"defender_player": owner})


# ── factor: model value ─────────────────────────────────────────────

static func _is_character_model(unit: Dictionary, model: Dictionary) -> bool:
	if model.get("is_character", false):
		return true
	if "CHARACTER" in model.get("keywords", []):
		return true
	var unit_keywords: Array = unit.get("meta", {}).get("keywords", [])
	return "CHARACTER" in unit_keywords and unit.get("models", []).size() == 1


static func _is_sergeant_like(unit: Dictionary, model: Dictionary) -> bool:
	var hay: String = (str(model.get("model_type", "")) + "|" + str(model.get("name", ""))).to_lower()
	var profiles = unit.get("meta", {}).get("model_profiles", {})
	if typeof(profiles) == TYPE_DICTIONARY:
		var mt: String = str(model.get("model_type", ""))
		if profiles.has(mt):
			hay += "|" + str(profiles[mt].get("label", "")).to_lower()
	for tok in SERGEANT_TOKENS:
		if tok in hay:
			return true
	return false


## Special/heavy wargear detection from meta.model_profiles: a weapon
## carried by a minority of the unit's (profiled, alive) models marks its
## carrier as high-value — e.g. the one plasma gun in a 10-man squad.
## Units without per-model profiles contribute nothing (all bases equal).
static func _special_weapon_keep(unit: Dictionary, alive: Array) -> Dictionary:
	var out: Dictionary = {}
	var profiles = unit.get("meta", {}).get("model_profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY or profiles.is_empty():
		return out
	var models: Array = unit.get("models", [])
	var carriers: Dictionary = {}
	var profiled: Array = []
	for i in alive:
		var mt: String = str(models[i].get("model_type", ""))
		if mt == "" or not profiles.has(mt):
			continue
		profiled.append(i)
		for w in profiles[mt].get("weapons", []):
			carriers[str(w)] = int(carriers.get(str(w), 0)) + 1
	if profiled.size() <= 1:
		return out
	var minority: int = maxi(1, int(profiled.size() / 3.0))
	for i in profiled:
		var mt: String = str(models[i].get("model_type", ""))
		var bonus: float = 0.0
		for w in profiles[mt].get("weapons", []):
			var c: int = int(carriers.get(str(w), 0))
			if c <= minority and c < profiled.size():
				bonus += SPECIAL_WEAPON_WEIGHT * (1.0 - float(c) / float(profiled.size()))
		if bonus > 0.0:
			out[i] = minf(bonus, KEEP_SPECIAL_WEAPON_MAX)
	return out


# ── factor: enemy proximity + charge denial ─────────────────────────

## Enemy units that exist on the board: alive, positioned, not embarked.
## Returns [{id, models: Array}] with only usable models included.
static func _gather_enemy_units(state: Dictionary, defender: int) -> Array:
	var out: Array = []
	var units: Dictionary = state.get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		var owner: int = int(u.get("owner", 0))
		if owner <= 0 or owner == defender:
			continue
		if u.get("flags", {}).get("embarked", false):
			continue
		var ms: Array = []
		for m in u.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				ms.append(m)
		if not ms.is_empty():
			out.append({"id": str(uid), "models": ms})
	return out


## Per our-model row of min edge-to-edge distances (inches), one column per
## enemy unit. Models without a position get no row (positionless boards —
## e.g. pure-logic tests — degrade to value-only ordering).
static func _distance_matrix(models: Array, alive: Array, enemy_units: Array) -> Dictionary:
	var rows: Dictionary = {}
	if enemy_units.is_empty():
		return rows
	var meas = _measurement()
	for i in alive:
		if models[i].get("position") == null:
			continue
		var row: Array = []
		for eu in enemy_units:
			var best: float = INF
			for em in eu.models:
				var d: float = meas.model_to_model_distance_inches(models[i], em)
				if d < best:
					best = d
			row.append(best)
		rows[i] = row
	return rows


## For each enemy unit inside charge-threat range: our model that is its
## closest charge-measuring point earns a die-first pull, scaled by how
## close the threat is and how much extra charge distance its removal buys
## (distance from the threat to our second-closest model).
static func _charge_denial_keep(alive: Array, enemy_units: Array, dist_rows: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if enemy_units.is_empty():
		return out
	for col in range(enemy_units.size()):
		var closest_i: int = -1
		var d1: float = INF
		var d2: float = INF
		for i in alive:
			if not dist_rows.has(i):
				continue
			var d: float = float(dist_rows[i][col])
			if d < d1:
				d2 = d1
				d1 = d
				closest_i = i
			elif d < d2:
				d2 = d
		if closest_i == -1 or d1 > CHARGE_THREAT_RANGE_INCHES or d2 == INF:
			continue
		var urgency: float = clampf((CHARGE_THREAT_RANGE_INCHES - d1) / CHARGE_THREAT_RANGE_INCHES, 0.0, 1.0)
		var gain: float = clampf((d2 - d1) / CHARGE_GAIN_NORM_INCHES, 0.0, 1.0)
		var pull: float = CHARGE_DENIAL_MAX * urgency * gain
		if pull > 0.0:
			out[closest_i] = maxf(float(out.get(closest_i, 0.0)) - pull, -CHARGE_DENIAL_CAP)
	return out


# ── factor: objective control ───────────────────────────────────────

static func _obj_pos(obj: Dictionary):
	var p = obj.get("position", null)
	if p is Vector2:
		return p
	if p is Dictionary and p.has("x") and p.has("y"):
		return Vector2(float(p.x), float(p.y))
	return null


## Terrain-aware objective-range test: delegates to MissionManager's shared
## predicate (identical to what objective control uses — 11e 14.01 hosting
## areas included). Marker-radius fallback only when MissionManager is
## unavailable (e.g. bare-bones harnesses).
static func _model_in_range_of_objective(model: Dictionary, obj: Dictionary, meas: Node, mm: Node) -> bool:
	if not model.get("alive", true) or model.get("position") == null:
		return false
	if mm != null and mm.has_method("model_in_objective_range"):
		return mm.model_in_objective_range(model, obj)
	var opos = _obj_pos(obj)
	if opos == null:
		return false
	return meas.model_edge_to_point_distance_px(model, opos) <= meas.inches_to_px(OBJECTIVE_CONTROL_RANGE_INCHES)


## MissionManager OC math: a unit contributes its OC once when ANY alive
## model is inside control range; battle-shocked or OC-0 units contribute
## nothing. (Heuristic: terrain-hosted objectives are approximated by the
## marker radius here.)
static func _unit_oc(u: Dictionary) -> int:
	if u.get("flags", {}).get("battle_shocked", false):
		return 0
	var oc: int = int(u.get("flags", {}).get("effect_oc_override", 0))
	if oc == 0:
		oc = int(u.get("meta", {}).get("stats", {}).get("objective_control", 0))
	if oc > 0:
		oc += int(u.get("flags", {}).get(EffectPrimitivesData.FLAG_PLUS_OC, 0))
	return maxi(oc, 0)


static func _objective_oc_totals(state: Dictionary, defender: int, obj: Dictionary, meas: Node, mm: Node) -> Dictionary:
	var friendly: int = 0
	var enemy: int = 0
	var units: Dictionary = state.get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		var owner: int = int(u.get("owner", 0))
		if owner <= 0:
			continue
		if u.get("flags", {}).get("embarked", false):
			continue
		var oc: int = _unit_oc(u)
		if oc <= 0:
			continue
		var any_in: bool = false
		for m in u.get("models", []):
			if _model_in_range_of_objective(m, obj, meas, mm):
				any_in = true
				break
		if not any_in:
			continue
		if owner == defender:
			friendly += oc
		else:
			enemy += oc
	return {"friendly": friendly, "enemy": enemy}


## Keep-bonus for our models inside control range of each objective. Full
## protection when the marker's control genuinely hinges on this unit's OC
## (we control / deny it now, and pulling our contribution would flip it);
## a light presence bonus otherwise. Bonuses across markers don't stack —
## the strongest applies.
static func _objective_keep(unit: Dictionary, alive: Array, state: Dictionary, defender: int) -> Dictionary:
	var out: Dictionary = {}
	var objectives: Array = state.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return out
	var unit_oc: int = _unit_oc(unit)
	if unit_oc <= 0:
		return out
	var models: Array = unit.get("models", [])
	var meas = _measurement()
	var mm = _mission_manager()
	for obj in objectives:
		var in_range: Array = []
		for i in alive:
			if _model_in_range_of_objective(models[i], obj, meas, mm):
				in_range.append(i)
		if in_range.is_empty():
			continue
		var totals: Dictionary = _objective_oc_totals(state, defender, obj, meas, mm)
		var friendly: int = int(totals.friendly)
		var enemy: int = int(totals.enemy)
		var without: int = friendly - unit_oc
		var at_stake: bool = false
		if friendly > enemy and without <= enemy:
			at_stake = true  # we control it; losing this unit's OC loses control
		elif friendly == enemy and friendly > 0 and without < enemy:
			at_stake = true  # we deny it; losing this unit's OC hands it over
		var bonus: float = KEEP_OBJECTIVE_AT_STAKE if at_stake else KEEP_OBJECTIVE_PRESENCE
		for i in in_range:
			out[i] = maxf(float(out.get(i, 0.0)), bonus)
	return out


# ── coherency-aware ordering ────────────────────────────────────────

## Offender count for the remaining alive set with `excluded` removed —
## straight through AttackSequence.check_unit_coherency so the edition's
## real coherency rule applies (11e: 2" to a mate + 9" envelope).
static func _offender_count(unit: Dictionary, remaining: Array, excluded: int) -> int:
	var models: Array = unit.get("models", [])
	var subset: Array = []
	for i in remaining:
		if i == excluded:
			continue
		subset.append(models[i])
	if subset.size() <= 1:
		return 0
	var check: Dictionary = AttackSequence.check_unit_coherency({"models": subset})
	return check.get("offenders", []).size()


## Build the die-first order greedily: at each step take the lowest-keep
## model whose removal does not worsen coherency (never split the unit by
## pulling a bridge model while an end model is available). If every
## candidate worsens it — already-broken formations — fall back to pure
## score order rather than stalling.
static func _coherency_aware_order(unit: Dictionary, alive: Array, keep: Dictionary) -> Array:
	var order: Array = []
	var remaining: Array = alive.duplicate()
	while remaining.size() > 0:
		var ranked: Array = remaining.duplicate()
		ranked.sort_custom(func(a, b):
			if absf(float(keep[a]) - float(keep[b])) > 0.001:
				return float(keep[a]) < float(keep[b])
			return a < b)
		var chosen = ranked[0]
		if remaining.size() > 2:
			var before: int = _offender_count(unit, remaining, -1)
			for cand in ranked:
				if _offender_count(unit, remaining, cand) <= before:
					chosen = cand
					break
		order.append(chosen)
		remaining.erase(chosen)
	return order
