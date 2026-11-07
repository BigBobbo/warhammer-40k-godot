extends RefCounted

## OrkFortification11e — Codex: Orks (11e) BIG'ED BOSSBUNKA datasheet rules
## (WP-G4). Printed text: .llm/codex_11e_wahapedia/orks/wahapedia/
## Datasheets_abilities.csv (datasheet 000002499); rulings: RULINGS.md "## WP-G4".
##
##   RAUCOUS OCCUPANTS  "While this model is within range of your home objective,
##                      add the OC of models embarked within this model to this
##                      model's OC."            -> raucous_occupants_oc()
##                      (hook: MissionManager.model_oc)
##   FORTIFICATION      "While an enemy unit is engaged with only FORTIFICATION
##                      units: that enemy unit can be selected as a target of
##                      ranged attacks; ranged attacks that target it have -1 to
##                      hit (excluding [CLOSE-QUARTERS] attacks); when it is
##                      selected to fall back, if it is only engaged with
##                      FORTIFICATION units and not battle-shocked, its hazard
##                      rolls are automatically passed."
##                      -> lifts_engaged_target() (hooks: RulesEngine
##                         _is_target_in_friendly_engagement, ShootingType
##                         .target_allowed, RulesEngine.snap_shooting_targets_11e),
##                         merge_attack_mods() (hook: RulesEngine.ork11e_ab_mods
##                         aggregator), fall_back_hazard() (hook: FallBackMove
##                         .before_moving)
##   RAMSHACKLE COVER   "When an attack targets a unit that is not fully visible
##                      to the attacking model because of this unit, the target
##                      has the benefit of cover against that attack."
##                      -> ramshackle_cover() (hook: TerrainManager
##                         .unit_has_cover_11e — the single 13.08 cover choke
##                         point every resolver path and the LoS cover badge use)
##
## Everything is static and edition-gated (>= 11). Engine files call in through
## one-line commented hooks only. Board-aware where the caller passes a board
## (the phases resolve on snapshot copies).

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

const PX_PER_INCH := 40.0
const KW_FORTIFICATION := "FORTIFICATION"

## slug -> FOLDED printed name (OrkAbilities11e.fold: case / apostrophes /
## punctuation ignored).
const NAMES := {
	"raucous_occupants": "raucous occupants",
	"fortification": "fortification",
	"ramshackle_cover": "ramshackle cover",
}
const DISPLAY := {
	"raucous_occupants": "Raucous Occupants",
	"fortification": "Fortification",
	"ramshackle_cover": "Ramshackle Cover",
}


# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func _ab():
	return load("res://scripts/codex/orks/OrkAbilities11e.gd")

static func has(u: Dictionary, slug: String) -> bool:
	var want := str(NAMES.get(slug, ""))
	if want == "" or u.is_empty():
		return false
	var ab = _ab()
	for a in u.get("meta", {}).get("abilities", []):
		var n := ""
		if a is String:
			n = a
		elif a is Dictionary:
			n = str(a.get("name", ""))
		if str(ab.fold(n)) == want:
			return true
	return false

static func _uid(u: Dictionary) -> String:
	return str(u.get("id", ""))

static func _units(board: Dictionary) -> Dictionary:
	if board.has("units"):
		return board.units
	return Common.state().get("units", {})

static func _board(board: Dictionary) -> Dictionary:
	return board if board.has("units") else Common.state()

static func _kw(u: Dictionary, kw: String) -> bool:
	for k in u.get("meta", {}).get("keywords", []):
		if str(k).to_upper() == kw:
			return true
	return false

static func _alive(u: Dictionary) -> bool:
	for m in u.get("models", []):
		if m.get("alive", true):
			return true
	return false

static func _on_battlefield(u: Dictionary) -> bool:
	if u.is_empty() or not _alive(u):
		return false
	var status := int(u.get("status", GameStateData.UnitStatus.DEPLOYED))
	if status == GameStateData.UnitStatus.IN_RESERVES or status == GameStateData.UnitStatus.UNDEPLOYED:
		return false
	return u.get("embarked_in", null) == null or str(u.get("embarked_in", "")) == ""

static func _v(p) -> Vector2:
	if p == null:
		return Vector2.INF
	if p is Vector2:
		return p
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))

static func _log(msg: String) -> void:
	Common.log_info("[OrkFortification11e] " + msg)

static func _game_log(player: int, msg: String) -> void:
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry") and player > 0:
		gel.add_player_entry(player, msg)


# ===========================================================================
# FORTIFICATION — "engaged with only FORTIFICATION units"
# ===========================================================================

## Every component of the (Attached) unit `unit_id` on `board` (19.01: one unit).
static func _components(unit_id: String, board: Dictionary) -> Array:
	var re = Common.rules()
	if re and re.has_method("attached_unit_component_ids"):
		var b := _board(board)
		return re.attached_unit_component_ids(str(re.attached_unit_target_id(unit_id, b)), b)
	return [unit_id]

## Enemy units engaged with any component of `unit_id`'s (Attached) unit.
static func engaged_enemy_ids(unit_id: String, board: Dictionary = {}) -> Array:
	var units := _units(board)
	var me: Dictionary = units.get(unit_id, {})
	if me.is_empty():
		return []
	var owner := int(me.get("owner", 0))
	var re = Common.rules()
	if re == null:
		return []
	var b := _board(board)
	var comps := _components(unit_id, board)
	var out: Array = []
	for oid in units:
		var o: Dictionary = units[oid]
		if int(o.get("owner", 0)) == owner or int(o.get("owner", 0)) <= 0 or not _on_battlefield(o):
			continue
		for cid in comps:
			var c: Dictionary = units.get(str(cid), {})
			if c.is_empty() or not _alive(c):
				continue
			if re._check_units_in_engagement_range(c, o, b):
				out.append(str(oid))
				break
	return out

## Cheap pre-check (the targeting hooks run per candidate target): is a
## FORTIFICATION unit with this rule on the battlefield at all?
static func _any_fortification_rule(board: Dictionary) -> bool:
	var units := _units(board)
	for uid in units:
		var u: Dictionary = units[uid]
		if _kw(u, KW_FORTIFICATION) and _on_battlefield(u) and has(u, "fortification"):
			return true
	return false

## FORTIFICATION's condition: the unit is engaged, every unit it is engaged with
## is a FORTIFICATION unit, and at least one of those carries this datasheet
## rule (Big'ed Bossbunka).
static func engaged_only_with_fortifications(unit_id: String, board: Dictionary = {}) -> bool:
	if not enabled() or unit_id == "" or not _any_fortification_rule(board):
		return false
	var engaged := engaged_enemy_ids(unit_id, board)
	if engaged.is_empty():
		return false
	var units := _units(board)
	var has_rule := false
	for eid in engaged:
		var e: Dictionary = units.get(str(eid), {})
		if not _kw(e, KW_FORTIFICATION):
			return false
		if has(e, "fortification"):
			has_rule = true
	return has_rule

## Targeting hooks: an engaged enemy unit that is engaged with only
## FORTIFICATION units "can be selected as a target of ranged attacks" — the
## 04.02 "Unengaged" target requirement is lifted for it ([BLAST] still cannot
## target it: 17.03's rule for engaged units, enforced separately).
static func lifts_engaged_target(target_unit_id: String, board: Dictionary = {}) -> bool:
	if not enabled():
		return false
	var ok := engaged_only_with_fortifications(target_unit_id, board)
	if ok:
		_log("Fortification — %s is engaged with only FORTIFICATION units: it can be selected as a target of ranged attacks" % target_unit_id)
	return ok

static func _is_close_quarters(weapon_profile: Dictionary) -> bool:
	var abilities: Array = AbilityRegistry.from_weapon(weapon_profile)
	return AbilityRegistry.has_ability(abilities, "close_quarters") or AbilityRegistry.has_ability(abilities, "pistol")  # 24.27: [PISTOL] is [CLOSE-QUARTERS]

## Aggregator contribution (one line in RulesEngine.ork11e_ab_mods): -1 to hit
## for ranged attacks (excluding [CLOSE-QUARTERS]) that target an enemy unit
## engaged with only FORTIFICATION units. The attacker is that unit's enemy by
## construction (it is the one shooting it).
static func merge_attack_mods(m: Dictionary, actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, _bearer_ids: Array = []) -> void:
	if not enabled() or is_melee or actor_unit.is_empty() or target_unit.is_empty():
		return
	if _is_close_quarters(weapon_profile):
		return
	var tid := _uid(target_unit)
	if tid == "" or not engaged_only_with_fortifications(tid, board):
		return
	m["hit_minus"] = true
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": "Fortification", "kind": "hit", "effect": "minus_one", "note": "target is engaged with only FORTIFICATION units"})
	_log("Fortification — ranged attacks of %s that target %s have -1 to hit" % [_uid(actor_unit), tid])

## Fall-back hook (FallBackMove.before_moving, after the hazard rolls are
## built): "if that enemy unit is only engaged with FORTIFICATION units, and
## that enemy unit is not battle-shocked, hazard rolls made for that enemy unit
## are automatically passed." Returns `hz` with every roll passed (no failure,
## no mortal wound) when the rule applies; otherwise `hz` unchanged.
static func fall_back_hazard(unit_id: String, board: Dictionary, hz: Dictionary) -> Dictionary:
	if not enabled() or hz.is_empty():
		return hz
	var u: Dictionary = _units(board).get(unit_id, {})
	if u.is_empty() or bool(u.get("flags", {}).get("battle_shocked", false)):
		return hz
	if not engaged_only_with_fortifications(unit_id, board):
		return hz
	var n: int = (hz.get("rolls", []) as Array).size()
	var out: Dictionary = hz.duplicate(true)
	out["failures"] = 0
	out["mortal_wounds"] = 0
	out["extra_failures"] = 0
	out["auto_passed"] = n
	out["auto_passed_source"] = "Fortification"
	var msg := "Fortification: %s is engaged with only FORTIFICATION units and is not battle-shocked — its %d hazard roll(s) are automatically passed" % [Common.unit_name(unit_id), n]
	_log(msg)
	_game_log(int(u.get("owner", 0)), msg)
	return out


# ===========================================================================
# RAUCOUS OCCUPANTS — OC while within range of your home objective
# ===========================================================================

static func _mission():
	return Common.autoload("MissionManager")

## Units embarked within `transport_id` (status-independent: `embarked_in`).
static func embarked_unit_ids(transport_id: String) -> Array:
	var out: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		if str(units[uid].get("embarked_in", "")) == transport_id:
			out.append(str(uid))
	return out

## The home objective of `player` (the objective in their deployment zone,
## MissionManager's 11e designation), {} if the mission has none.
static func home_objective(player: int) -> Dictionary:
	var mm = _mission()
	if mm == null or not mm.has_method("_get_home_objective_id_11e"):
		return {}
	var oid := str(mm._get_home_objective_id_11e(player))
	if oid == "":
		return {}
	return mm._get_objective_by_id(oid)

## The OC Raucous Occupants adds to this model (MissionManager.model_oc hook):
## the summed OC of every alive model embarked within it, while it is within
## range of its controller's home objective. Battle-shocked embarked units add
## nothing (01.07: their models' OC is '-'). 0 otherwise.
static func raucous_occupants_oc(unit: Dictionary, model: Dictionary) -> int:
	if not enabled() or unit.is_empty() or model.is_empty() or not has(unit, "raucous_occupants"):
		return 0
	if not model.get("alive", true) or model.get("position", null) == null or not _on_battlefield(unit):
		return 0
	var mm = _mission()
	if mm == null:
		return 0
	var home := home_objective(int(unit.get("owner", 0)))
	if home.is_empty() or not bool(mm.model_in_objective_range(model, home)):
		return 0
	var total := 0
	var units: Dictionary = Common.state().get("units", {})
	for eid in embarked_unit_ids(_uid(unit)):
		var eu: Dictionary = units.get(eid, {})
		if bool(eu.get("flags", {}).get("battle_shocked", false)):
			continue
		for em in eu.get("models", []):
			if em.get("alive", true):
				total += int(mm.model_oc(eu, em))
	return total


# ===========================================================================
# RAMSHACKLE COVER — "not fully visible to the attacking model because of this unit"
# ===========================================================================
# The engine's 06.01 visibility is terrain-only (other models never block a
# sight line). For THIS rule only, the Bossbunka's footprint is an obscuring
# shape: the target is "not fully visible to the attacking model because of
# this unit" when any sight line from the attacking model to a target model's
# sight points (TerrainManager._sight_points: centre + 8 base points — the same
# lines 06.01 FULLY VISIBLE uses) crosses the Bossbunka's base. Same geometry as
# WP-O5's Smoky Gubbinz.

static func _base_radius_px(m: Dictionary) -> float:
	var mm := float(m.get("base_mm", 32))
	var dims = m.get("base_dimensions", null)
	if typeof(dims) == TYPE_DICTIONARY:
		mm = (float(dims.get("length", mm)) + float(dims.get("width", mm))) / 2.0
	return mm / 25.4 / 2.0 * PX_PER_INCH

static func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return a.distance_to(c) < r
	var t := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r

## The Bossbunka (Ramshackle Cover holder) whose footprint hides part of
## `target_unit` from `attacker_model`, or "".
static func ramshackle_cover_source(target_unit: Dictionary, attacker_model: Dictionary) -> String:
	if not enabled() or attacker_model.is_empty() or target_unit.is_empty():
		return ""
	var a := _v(attacker_model.get("position", null))
	if a == Vector2.INF:
		return ""
	var units: Dictionary = Common.state().get("units", {})
	var tid := _uid(target_unit)
	var tm = Common.autoload("TerrainManager")
	for bid in units:
		var bu: Dictionary = units[bid]
		# cheap keyword gate first (every Ramshackle Cover datasheet is a FORTIFICATION): this runs per cover check
		if str(bid) == tid or not _kw(bu, KW_FORTIFICATION) or not _on_battlefield(bu) or not has(bu, "ramshackle_cover"):
			continue
		var blockers: Array = []
		var attacker_inside := false
		for bm in bu.get("models", []):
			if not bm.get("alive", true) or bm.get("position", null) == null:
				continue
			var c := _v(bm.position)
			var r := _base_radius_px(bm)
			if c.distance_to(a) <= r:
				attacker_inside = true  # the attacking model is this unit's own (or stands in it)
			blockers.append({"c": c, "r": r})
		if attacker_inside or blockers.is_empty():
			continue
		for tmodel in target_unit.get("models", []):
			if not tmodel.get("alive", true) or tmodel.get("position", null) == null:
				continue
			var pts: Array = [_v(tmodel.position)]
			if tm and tm.has_method("_sight_points"):
				pts = tm._sight_points(tmodel)
			for p in pts:
				var pv := _v(p)
				for bl in blockers:
					if _segment_hits_circle(a, pv, bl.c, bl.r):
						return str(bid)
	return ""

## TerrainManager.unit_has_cover_11e hook: the target has the benefit of cover
## against an attack by `attacker_model`.
static func ramshackle_cover(target_unit: Dictionary, attacker_model: Dictionary) -> bool:
	var src := ramshackle_cover_source(target_unit, attacker_model)
	if src == "":
		return false
	_log("Ramshackle Cover — %s is not fully visible to the attacking model because of %s: benefit of cover" % [Common.unit_name(_uid(target_unit)), Common.unit_name(src)])
	return true
