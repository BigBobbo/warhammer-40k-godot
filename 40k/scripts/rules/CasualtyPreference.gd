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
##  ▫ coherency — DOMINANT. The order is built greedily and every step picks
##                the casualty that leaves the FEWEST survivors out of
##                coherency; the value/proximity/objective score above only
##                breaks ties between equally-coherent picks. 03.03 destroys
##                out-of-coherency models at End of Turn, so a careless pick
##                costs a whole extra model — that outranks every soft
##                preference here. Judged over the whole ATTACHED unit
##                (19.03): an attached CHARACTER's model is part of this
##                unit, so a casualty that strands the leader (or strands
##                the squad from it) is scored as the break it is.
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

	var order: Array = _coherency_aware_order(unit, alive, keep, state)

	var parts: Array = []
	for i in order:
		parts.append("%s=%.0f" % [str(models[i].get("id", i)), keep[i]])
	_log("[CasualtyPreference] %s die-first order (idx=%s): %s" % [
		str(unit.get("id", unit.get("meta", {}).get("name", "?"))), str(order), ", ".join(parts)])
	return order


## print() + mirror into the persistent debug log (stdout isn't always
## reachable — see CLAUDE.md).
static func _log(line: String) -> void:
	print(line)
	var loop = Engine.get_main_loop()
	var dl = loop.root.get_node_or_null("DebugLogger") if loop != null and loop.root != null else null
	if dl != null and dl.has_method("info"):
		dl.info(line, {})


## Engine-side hook for the non-interactive resolve paths (AI vs AI, or an
## AI defender resolved without the overlay). Returns [] — "engine default"
## — unless the computer is allocating for this defender: an AI-controlled
## player, or (in local play) a human who enabled "Computer allocates
## wounds". Mirrors AllocationGroupOverlay._compute_auto_mode, so the
## engine paths and the overlay agree on WHO gets the smart order. A
## networked human defender never does (their client owns the choice),
## and headless tests keep today's lowest-index behaviour.
static func engine_auto_preference(target_unit: Dictionary, state: Dictionary) -> Array:
	var loop = Engine.get_main_loop()
	if loop == null or loop.root == null:
		return []
	var owner: int = int(target_unit.get("owner", 0))
	if owner <= 0:
		return []
	var ai = loop.root.get_node_or_null("AIPlayer")
	if ai != null and ai.has_method("is_ai_player") and ai.is_ai_player(owner):
		return compute_preferred_targets(target_unit, state, {"defender_player": owner})
	var nm = loop.root.get_node_or_null("NetworkManager")
	if nm != null and nm.has_method("is_networked") and nm.is_networked():
		return []
	var ss = loop.root.get_node_or_null("SettingsService")
	if ss != null and ss.has_method("get_auto_allocate_wounds") and ss.get_auto_allocate_wounds():
		return compute_preferred_targets(target_unit, state, {"defender_player": owner})
	return []


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

## Incremental coherency evaluator for one ATTACHED unit's models.
##
## Answers "how many models would be out of coherency if THIS one died next?"
## for every candidate, at every step of the greedy order. Doing that straight
## through AttackSequence.check_attached_unit_coherency would be O(n²) distance
## work per candidate; here the pairwise near/far matrix is built ONCE (models
## do not move while wounds are allocated) and each candidate is an O(n) walk of
## cached neighbour counts.
##
## The verdict it reproduces is exactly AttackSequence.attached_coherency_offenders:
## merged neighbours (19.03 — the leader counts as a mate) intersected with the
## per-component envelope (a leader standing off one end must not condemn the
## squad it is attached to). test_casualty_preference cross-checks the two on
## live subsets so this fast path can never silently drift from the rule.
class CoherencyModel extends RefCounted:
	var usable: bool = false          # < 2 positioned models: coherency cannot bind
	var entry_of: Dictionary = {}     # candidate model index -> entry index
	var comp_of: Array = []           # entry -> component index
	var comp_live: Array = []         # component -> live entry count
	var live: Array = []              # entry -> still on the board
	var near: Array = []              # entry -> Array[bool] within 2" (+tol)
	var far: Array = []               # entry -> Array[bool] beyond the 9" envelope
	var nb_all: Array = []            # entry -> live neighbours anywhere in the unit
	var far_all: Array = []           # entry -> live models outside its envelope
	var nb_solo: Array = []           # ditto, restricted to the entry's component
	var far_solo: Array = []
	var n_live: int = 0
	var _legacy_pairs: bool = false   # 10e only: 7+ models need 2 neighbours

	func _init(models: Array, comps: Array, meas: Node) -> void:
		# `models` are the entry model dicts (alive + positioned), `comps` their
		# component indices. Thresholds mirror AttackSequence.check_unit_coherency.
		var n: int = models.size()
		comp_of = comps
		_legacy_pairs = GameConstants.edition < 11
		var tol: float = meas.DISTANCE_TOLERANCE_INCHES
		var coh_px: float = meas.inches_to_px(GameConstants.coherency_distance_inches() + tol)
		var env_px: float = 0.0
		if GameConstants.edition >= 11:
			env_px = meas.inches_to_px(GameConstants.coherency_envelope_inches() + tol)
		var comp_count := 0
		for c in comps:
			comp_count = maxi(comp_count, int(c) + 1)
		comp_live.resize(comp_count)
		comp_live.fill(0)
		for i in range(n):
			live.append(true)
			near.append([])
			far.append([])
			near[i].resize(n)
			far[i].resize(n)
			near[i].fill(false)
			far[i].fill(false)
			comp_live[int(comps[i])] += 1
		for i in range(n):
			for j in range(i + 1, n):
				var d: float = meas.model_to_model_distance_px(models[i], models[j])
				var is_near: bool = d <= coh_px
				var is_far: bool = env_px > 0.0 and d > env_px
				near[i][j] = is_near
				near[j][i] = is_near
				far[i][j] = is_far
				far[j][i] = is_far
		for i in range(n):
			var nb := 0
			var fr := 0
			var nbs := 0
			var frs := 0
			for j in range(n):
				if i == j:
					continue
				var same: bool = int(comps[i]) == int(comps[j])
				if near[i][j]:
					nb += 1
					if same:
						nbs += 1
				if far[i][j]:
					fr += 1
					if same:
						frs += 1
			nb_all.append(nb)
			far_all.append(fr)
			nb_solo.append(nbs)
			far_solo.append(frs)
		n_live = n
		usable = n >= 2

	func _required(count: int) -> int:
		return 2 if (_legacy_pairs and count >= 7) else 1

	## Offenders among the survivors, optionally with entry `skip` treated as
	## already dead (-1 = nobody). A model only counts when BOTH readings
	## condemn it (see AttackSequence.check_attached_unit_coherency).
	func offenders(skip: int = -1) -> int:
		if skip >= 0 and not live[skip]:
			skip = -1  # already dead: removing it again changes nothing
		var total: int = n_live - (1 if skip >= 0 else 0)
		if total <= 1:
			return 0
		var req_all: int = _required(total)
		var count := 0
		for i in range(live.size()):
			if not live[i] or i == skip:
				continue
			var nb: int = nb_all[i]
			var fr: int = far_all[i]
			if skip >= 0:
				if near[i][skip]:
					nb -= 1
				if far[i][skip]:
					fr -= 1
			if nb >= req_all and fr == 0:
				continue  # 19.03 reading clears it
			var c: int = int(comp_of[i])
			var csize: int = comp_live[c] - (1 if skip >= 0 and int(comp_of[skip]) == c else 0)
			if csize <= 1:
				continue  # a 1-model component is always coherent on its own
			var nbs: int = nb_solo[i]
			var frs: int = far_solo[i]
			if skip >= 0 and int(comp_of[skip]) == c:
				if near[i][skip]:
					nbs -= 1
				if far[i][skip]:
					frs -= 1
			if nbs >= _required(csize) and frs == 0:
				continue  # standalone reading clears it
			count += 1
		return count

	## Offenders left if candidate model index `idx` is the next casualty.
	## Models with no position are not on the coherency board at all, so
	## removing them changes nothing.
	func offenders_without(idx: int) -> int:
		return offenders(int(entry_of.get(idx, -1)))

	## Commit a casualty: candidate model index `idx` is dead from here on.
	func kill(idx: int) -> void:
		if not entry_of.has(idx):
			return
		var e: int = int(entry_of[idx])
		if not live[e]:
			return
		live[e] = false
		n_live -= 1
		var c: int = int(comp_of[e])
		comp_live[c] -= 1
		for i in range(live.size()):
			if not live[i]:
				continue
			var same: bool = int(comp_of[i]) == c
			if near[i][e]:
				nb_all[i] -= 1
				if same:
					nb_solo[i] -= 1
			if far[i][e]:
				far_all[i] -= 1
				if same:
					far_solo[i] -= 1


## Resolve the Attached unit (19.03) the passed `unit` belongs to into
## components, and work out which of ITS model indices map where.
##
## Two shapes reach this module and both must work:
##  ▫ the FOLDED allocation unit the overlay builds
##    (RulesEngine._build_attached_allocation_unit_11e) — bodyguard models
##    then each attached CHARACTER's, so every model is a candidate;
##  ▫ the RAW target unit the engine auto-resolve paths pass — only its own
##    models can take wounds, but the attached CHARACTER's model still sits on
##    the board and still has to end up in coherency, so it is folded in as
##    CONTEXT (never as a casualty candidate).
##
## Returns {comp_ids, comp_models, cand: {model index -> [component, local]}}.
static func _attached_layout(unit: Dictionary, state: Dictionary) -> Dictionary:
	var own_models: Array = unit.get("models", [])
	var solo: Dictionary = {
		"comp_ids": [str(unit.get("id", "self"))],
		"comp_models": [own_models],
		"cand": {},
	}
	for i in range(own_models.size()):
		solo.cand[i] = [0, i]
	var units: Dictionary = state.get("units", {})
	var own_id: String = str(unit.get("id", ""))
	if own_id == "" or not units.has(own_id):
		return solo
	var group: Array = AttackSequence.coherency_group_ids(own_id, units)
	if group.size() <= 1:
		return solo
	var comp_models: Array = []
	var total := 0
	for gid in group:
		var ms: Array = units.get(gid, {}).get("models", [])
		comp_models.append(ms)
		total += ms.size()
	var out: Dictionary = {"comp_ids": group, "comp_models": comp_models, "cand": {}}
	if own_models.size() == total:
		# Folded Attached unit: virtual index i walks the components in the
		# same order the fold appended them.
		var i := 0
		for c in range(group.size()):
			var n: int = comp_models[c].size()
			comp_models[c] = own_models.slice(i, i + n)
			for local in range(n):
				out.cand[i] = [c, local]
				i += 1
		return out
	var own_c: int = group.find(own_id)
	if own_c < 0 or comp_models[own_c].size() != own_models.size():
		return solo  # unrecognised shape — measure the unit on its own
	comp_models[own_c] = own_models
	for i in range(own_models.size()):
		out.cand[i] = [own_c, i]
	return out


static func _build_coherency_model(unit: Dictionary, state: Dictionary) -> CoherencyModel:
	var layout: Dictionary = _attached_layout(unit, state)
	var comp_models: Array = layout.comp_models
	var by_slot: Dictionary = {}  # "c|local" -> candidate model index
	for idx in layout.cand:
		var pair: Array = layout.cand[idx]
		by_slot["%d|%d" % [int(pair[0]), int(pair[1])]] = int(idx)
	var models: Array = []
	var comps: Array = []
	var entry_of: Dictionary = {}
	for c in range(comp_models.size()):
		var ms: Array = comp_models[c]
		for local in range(ms.size()):
			var m: Dictionary = ms[local]
			if not m.get("alive", true) or m.get("position") == null:
				continue
			var slot: String = "%d|%d" % [c, local]
			if by_slot.has(slot):
				entry_of[int(by_slot[slot])] = models.size()
			models.append(m)
			comps.append(c)
	var cm := CoherencyModel.new(models, comps, _measurement())
	cm.entry_of = entry_of
	return cm


## Build the die-first order greedily, coherency FIRST: at each step every
## still-standing candidate is scored by how many models would be left out of
## coherency once it dies, and the pick is the one with the fewest — the keep
## score above only breaks ties. 03.03 destroys out-of-coherency models at End
## of Turn, so the "cheapest" chaff model is a bad trade when removing it
## strands two others; and when the formation is ALREADY broken this naturally
## removes the stranded model first, which repairs the unit instead of
## deepening the split.
##
## CHARACTER models are held out of the candidate pool while any bodyguard
## model is standing: 05.04 allocates CHARACTER groups last regardless, so
## letting coherency pull a leader forward would only desync this simulation
## from what the engine actually does.
static func _coherency_aware_order(unit: Dictionary, alive: Array, keep: Dictionary, state: Dictionary) -> Array:
	var models: Array = unit.get("models", [])
	var is_char: Dictionary = {}
	for i in alive:
		is_char[i] = _is_character_model(unit, models[i])
	var cm := _build_coherency_model(unit, state)
	var order: Array = []
	var breaks := 0
	var remaining: Array = alive.duplicate()
	while remaining.size() > 0:
		var ranked: Array = remaining.duplicate()
		ranked.sort_custom(func(a, b):
			if absf(float(keep[a]) - float(keep[b])) > 0.001:
				return float(keep[a]) < float(keep[b])
			return a < b)
		var pool: Array = []
		for i in ranked:
			if not is_char.get(i, false):
				pool.append(i)
		if pool.is_empty():
			pool = ranked
		var chosen = pool[0]
		if cm.usable:
			var best := -1
			for cand in pool:
				var n: int = cm.offenders_without(cand)
				if best < 0 or n < best:
					best = n
					chosen = cand
					if n == 0:
						break  # pool is keep-sorted: the cheapest clean pick
			if best > 0:
				breaks += 1
		order.append(chosen)
		remaining.erase(chosen)
		cm.kill(chosen)
	if breaks > 0:
		_log("[CasualtyPreference] %s — %d/%d casualty step(s) cannot avoid breaking coherency" % [
			str(unit.get("id", "?")), breaks, order.size()])
	return order
