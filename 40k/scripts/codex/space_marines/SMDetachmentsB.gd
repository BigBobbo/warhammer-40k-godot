extends RefCounted

## SMDetachmentsB — Codex: Space Marines (11e), generic detachments group B
## (WP-M2b): the DETACHMENT RULES and every ENHANCEMENT of Terminator Storm
## Force, Assault Brethren, Gravis Linebreaker Force, Devastator Brethren,
## Gravis Siege Force, Tactical Brethren, Ironclad Champions and Tacticus
## Firestorm Force.
##
## Source: .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md.
## Plan: PLAN_SPACE_MARINES.md (SM-D1: every Space Marine army —
## SWCommon.is_sm_army); contract IMPLEMENTATION.md; rulings RULINGS.md § WP-M2b.
## Every rule / enhancement is active only while its owner took that
## detachment (11e armies can take several — ArmyDetachments11e; a chapter
## army such as Space Wolves can take them too). Combat doctrines are read
## ONLY through SWCommon.active_doctrines (the doctrine-state API).
## Engine files reach this module through one-line commented hooks.
##
##  TERMINATOR STORM FORCE — Death Blow: ADEPTUS ASTARTES TERMINATOR units +1
##   to charge rolls (charge_roll_bonus, ChargePhase).
##   Champion of the First Company: the bearer's unit's melee attacks have
##   [LETHAL HITS] (merge_attack_mods). Corporeum Reliquary: in your first
##   Movement phase the bearer's unit can make an ingress move
##   (can_ingress_first_round — MovementPhase / Main reinforcement list).
##  ASSAULT / DEVASTATOR / TACTICAL BRETHREN — Assault / Devastator / Tactical
##   Mastery: that doctrine can be selected one additional time per battle
##   (doctrine_extra_selections — SWArmyRules11e.doctrine_limit hook).
##   Imperium's Sword: the weapon profile is missing from the source export —
##   NOT implemented (ruling); bearer restriction validated (data-driven).
##   Furious Assault: melee [SUSTAINED HITS 1] vs non-MONSTER/VEHICLE targets.
##   Master-forged Firearms: the bearer model's ranged attacks (not [PSYCHIC])
##   +1 A / S / AP (aggregator) and +1 D (ranged_damage_bonus, RulesEngine).
##   Honour of Vigilance: the unit's ranged attacks have [LETHAL HITS]; with
##   the devastator doctrine active it can re-roll advance rolls (free re-roll
##   in the advance dialog — free_advance_reroll_source, MovementPhase).
##   Laurels of Vigilance: (once per battle round, per army) FIRE OVERWATCH /
##   HEROIC INTERVENTION on an ADEPTUS ASTARTES BATTLELINE unit within 12" of
##   the bearer is -1CP (stratagem_cp_discount, StratagemManager).
##   Tactical Insight: the tactical doctrine is active for the bearer's unit in
##   addition to any other doctrine (SWCommon per-unit sw11e_doctrine_extra,
##   written at every phase start — on_phase_enter, BasePhase).
##  GRAVIS LINEBREAKER FORCE — Walking Fortress: in a turn a GRAVIS unit made a
##   normal move, its ranged attacks have +1 to hit and no [HEAVY]
##   (merge_attack_mods). Indefatigable Fortitude: S > T attacks that target
##   the bearer's unit have -1 to wound (incoming_wound_penalty). Relentless
##   Advance: the bearer's unit has Scouts 5" (scouts_distance, GameState).
##  GRAVIS SIEGE FORCE — Indomitable Defence: a GRAVIS unit within range of an
##   objective: S > T attacks that target it have -1 to wound. Immovable
##   Conquerors: +1 OC (oc_bonus, MissionManager). Narthecis Gauntlet: in your
##   Command phase the bearer's unit heals D3+1 wounds (a free rule card in the
##   phase_start window of your Command phase).
##  IRONCLAD CHAMPIONS — Enduring Vengeance: ADEPTUS ASTARTES DREADNOUGHT units
##   re-roll hit rolls of 1. Artificer Sarcophagus: attacks that target the
##   unit have -1 D (damage_minus, EffectPrimitives). Venerable Champion
##   (Aura): friendly ADEPTUS ASTARTES INFANTRY / MOUNTED units within 6" of
##   the bearer re-roll hit rolls of 1.
##  TACTICUS FIRESTORM FORCE — Codex Fire-patterns: a TACTICUS unit's [RAPID
##   FIRE] attacks benefit from [RAPID FIRE] up to the attack's maximum range
##   (full_range_rapid_fire, RulesEngine + ShootingController forecast).
##   Cyber-familiar: redeploy up to three ADEPTUS ASTARTES INFANTRY units
##   (redeploy table, FactionAbilityManager — engine / AI side, as Castellan's
##   Mark / Chariots of the Storm). Tempered in Battle (Aura): friendly
##   ADEPTUS ASTARTES units within 6" of the bearer re-roll a failed
##   battle-shock / leadership roll (battle_shock_reroll_source).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")

# --- detachments (det_key) ---------------------------------------------------
const TERMINATOR_STORM := "terminator storm force"
const ASSAULT_BRETHREN := "assault brethren"
const GRAVIS_LINEBREAKER := "gravis linebreaker force"
const DEVASTATOR_BRETHREN := "devastator brethren"
const GRAVIS_SIEGE := "gravis siege force"
const TACTICAL_BRETHREN := "tactical brethren"
const IRONCLAD := "ironclad champions"
const TACTICUS_FIRESTORM := "tacticus firestorm force"

const DETACHMENTS := [TERMINATOR_STORM, ASSAULT_BRETHREN, GRAVIS_LINEBREAKER, DEVASTATOR_BRETHREN,
	GRAVIS_SIEGE, TACTICAL_BRETHREN, IRONCLAD, TACTICUS_FIRESTORM]

const RULE_NAMES := {
	TERMINATOR_STORM: "Death Blow",
	ASSAULT_BRETHREN: "Assault Mastery",
	GRAVIS_LINEBREAKER: "Walking Fortress",
	DEVASTATOR_BRETHREN: "Devastator Mastery",
	GRAVIS_SIEGE: "Indomitable Defence",
	TACTICAL_BRETHREN: "Tactical Mastery",
	IRONCLAD: "Enduring Vengeance",
	TACTICUS_FIRESTORM: "Codex Fire-patterns",
}

## Assault / Devastator / Tactical Mastery: detachment -> doctrine.
const MASTERY := {ASSAULT_BRETHREN: "assault", DEVASTATOR_BRETHREN: "devastator", TACTICAL_BRETHREN: "tactical"}

# --- enhancements (enh_key) --------------------------------------------------
const CHAMPION_FIRST_CO := "champion of the first company"
const CORPOREUM := "corporeum reliquary"
const IMPERIUMS_SWORD := "imperium's sword"
const FURIOUS_ASSAULT := "furious assault"
const INDEFATIGABLE := "indefatigable fortitude"
const RELENTLESS_ADVANCE := "relentless advance"
const MASTER_FORGED := "master-forged firearms"
const HONOUR_VIGILANCE := "honour of vigilance"
const IMMOVABLE := "immovable conquerors"
const NARTHECIS := "narthecis gauntlet"
const LAURELS_VIGILANCE := "laurels of vigilance"
const TACTICAL_INSIGHT := "tactical insight"
const ARTIFICER_SARCOPHAGUS := "artificer sarcophagus"
const VENERABLE_CHAMPION := "venerable champion"
const CYBER_FAMILIAR := "cyber-familiar"
const TEMPERED := "tempered in battle"

const ENHANCEMENTS := {
	CHAMPION_FIRST_CO: {"detachment": TERMINATOR_STORM, "name": "Champion of the First Company"},
	CORPOREUM: {"detachment": TERMINATOR_STORM, "name": "Corporeum Reliquary"},
	IMPERIUMS_SWORD: {"detachment": ASSAULT_BRETHREN, "name": "Imperium's Sword"},
	FURIOUS_ASSAULT: {"detachment": ASSAULT_BRETHREN, "name": "Furious Assault"},
	INDEFATIGABLE: {"detachment": GRAVIS_LINEBREAKER, "name": "Indefatigable Fortitude"},
	RELENTLESS_ADVANCE: {"detachment": GRAVIS_LINEBREAKER, "name": "Relentless Advance"},
	MASTER_FORGED: {"detachment": DEVASTATOR_BRETHREN, "name": "Master-forged Firearms"},
	HONOUR_VIGILANCE: {"detachment": DEVASTATOR_BRETHREN, "name": "Honour of Vigilance"},
	IMMOVABLE: {"detachment": GRAVIS_SIEGE, "name": "Immovable Conquerors"},
	NARTHECIS: {"detachment": GRAVIS_SIEGE, "name": "Narthecis Gauntlet"},
	LAURELS_VIGILANCE: {"detachment": TACTICAL_BRETHREN, "name": "Laurels of Vigilance"},
	TACTICAL_INSIGHT: {"detachment": TACTICAL_BRETHREN, "name": "Tactical Insight"},
	ARTIFICER_SARCOPHAGUS: {"detachment": IRONCLAD, "name": "Artificer Sarcophagus"},
	VENERABLE_CHAMPION: {"detachment": IRONCLAD, "name": "Venerable Champion (Aura)"},
	CYBER_FAMILIAR: {"detachment": TACTICUS_FIRESTORM, "name": "Cyber-familiar"},
	TEMPERED: {"detachment": TACTICUS_FIRESTORM, "name": "Tempered in Battle (Aura)"},
}

const RELENTLESS_SCOUTS_IN := 5.0
const LAURELS_RANGE_IN := 12.0
const VENERABLE_RANGE_IN := 6.0
const TEMPERED_RANGE_IN := 6.0

## Rule-card ids (StratagemManager window offers; free).
const RULE_PREFIX := "sm11e_rule_"
const RULE_NARTHECIS := "sm11e_rule_enh_narthecis_gauntlet"

## state.factions[p] keys (no effect_ prefix: they outlive the Shooting-phase wipe).
const FK_LAURELS_ROUND := "sm11e_laurels_of_vigilance_round"   # battle round of the last -1CP use
## Narthecis Gauntlet used: "<round>:<player>" stamp on the bearer (once per Command phase).
const F_NARTHECIS_TURN := "sm11e_narthecis_gauntlet_turn"
## Tactical Insight wrote "tactical" into SWCommon's sw11e_doctrine_extra on this component.
const F_TACTICAL_INSIGHT := "sm11e_tactical_insight"
const F_DOCTRINE_EXTRA := "sw11e_doctrine_extra"

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func _log(msg: String) -> void:
	Common.log_info("[SMDetachmentsB] " + msg)

static func det_key(name: String) -> String:
	return ArmyDets.det_key(name)

static func detachments_of(player: int) -> Array:
	if not enabled() or player <= 0:
		return []
	return ArmyDets.player_detachment_keys(player, Common.state())

## `player` is a Space Marine army (SM-D1) that took detachment `det`.
static func has_det(player: int, det: String) -> bool:
	return enabled() and player > 0 and det in detachments_of(player) and Common.is_sm_army(player)

static func unit_has_det(u: Dictionary, det: String) -> bool:
	return not u.is_empty() and has_det(int(u.get("owner", 0)), det)

static func enh_key(name: String) -> String:
	var k := name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()
	for suffix in [" (one per army)", " (upgrade)", " (aura)"]:
		if k.ends_with(suffix):
			k = k.substr(0, k.length() - suffix.length()).strip_edges()
	return k

static func display_name(key: String) -> String:
	return str(ENHANCEMENTS.get(key, {}).get("name", key))

static func is_group_b_enhancement(name: String) -> bool:
	return ENHANCEMENTS.has(enh_key(name))

static func unit_enhancements(u: Dictionary) -> Array:
	var out: Array = []
	for e in u.get("meta", {}).get("enhancements", []):
		var n := ""
		if e is String:
			n = e
		elif e is Dictionary:
			n = str(e.get("name", ""))
		if n != "":
			out.append(enh_key(n))
	return out

## THIS unit dict carries enhancement `key` and its owner took its detachment.
static func has_enh(u: Dictionary, key: String) -> bool:
	if not enabled() or u.is_empty() or not key in unit_enhancements(u):
		return false
	return unit_has_det(u, str(ENHANCEMENTS[key].detachment))

## The unit and its Attached-unit components as dicts. The caller's own dict
## stands for its unit (a resolver's board copy may differ from GameState).
static func group_units(u: Dictionary) -> Array:
	var uid := str(u.get("id", ""))
	if uid == "":
		return [u]
	var out: Array = []
	for gid in Common.attached_group_ids(uid):
		var gu = u if str(gid) == uid else Common.unit(str(gid))
		if not gu.is_empty():
			out.append(gu)
	if out.is_empty():
		out.append(u)
	return out

static func group_kw(u: Dictionary, kw: String) -> bool:
	for gu in group_units(u):
		if Common.has_keyword(gu, kw):
			return true
	return false

static func group_is_mv(u: Dictionary) -> bool:
	return group_kw(u, "MONSTER") or group_kw(u, "VEHICLE")

## The component of the (Attached) unit that bears `key` ({} = none).
static func group_bearer(u: Dictionary, key: String) -> Dictionary:
	if not enabled() or u.is_empty():
		return {}
	for gu in group_units(u):
		if has_enh(gu, key):
			return gu
	return {}

## Every unit of `player` (on the battlefield when on_board) bearing `key`.
static func bearers(player: int, key: String, on_board: bool = true) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not has_enh(u, key):
			continue
		if on_board and not Common.is_on_battlefield(u):
			continue
		out.append(u)
	return out

## Distance (inches) between two (Attached) units, edge to edge.
static func _group_distance(a: Dictionary, b: Dictionary) -> float:
	var am: Array = []
	for gu in group_units(a):
		am.append_array(gu.get("models", []))
	var bm: Array = []
	for gu in group_units(b):
		bm.append_array(gu.get("models", []))
	return Common.unit_distance_inches({"models": am}, {"models": bm})

## The combat doctrines active for the (Attached) unit (any component —
## an Attached unit is one unit, 19.01). Read through SWCommon only.
static func group_doctrines(u: Dictionary) -> Array:
	var out: Array = []
	for gu in group_units(u):
		for d in Common.active_doctrines(gu):
			if not d in out:
				out.append(d)
	return out

static func _turn_stamp() -> String:
	return "%d:%d" % [Common.battle_round(), Common.active_player()]

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_at_least_ones(m: Dictionary) -> void:
	var rank := {"": 0, "ones": 1, "failed": 2}
	if int(rank.get(str(m.get("hit_reroll", "")), 0)) < 1:
		m["hit_reroll"] = "ones"

static func _is_psychic_weapon(wp: Dictionary) -> bool:
	var blob := (str(wp.get("special_rules", "")) + " " + str(wp.get("keywords", [])) + " " + str(wp.get("abilities", []))).to_lower()
	return blob.contains("psychic")

# ===========================================================================
# ASSAULT / DEVASTATOR / TACTICAL MASTERY (SWArmyRules11e.doctrine_limit hook)
# ===========================================================================

## Additional selections of `doctrine` this player may make in the battle
## (0 or 1 per Mastery detachment taken). Stacks with Codex Discipline.
static func doctrine_extra_selections(player: int, doctrine: String) -> int:
	var n := 0
	for det in MASTERY:
		if str(MASTERY[det]) == doctrine.to_lower() and has_det(player, det):
			n += 1
	return n

## "Assault Mastery" etc. — the rule that gives `doctrine` its extra selection ("" = none).
static func doctrine_extra_source(player: int, doctrine: String) -> String:
	for det in MASTERY:
		if str(MASTERY[det]) == doctrine.to_lower() and has_det(player, det):
			return str(RULE_NAMES[det])
	return ""

# ===========================================================================
# TERMINATOR STORM FORCE — Death Blow (+1 to charge rolls)
# ===========================================================================

static func charge_roll_bonus(u: Dictionary) -> int:
	if not unit_has_det(u, TERMINATOR_STORM):
		return 0
	if group_kw(u, "ADEPTUS ASTARTES") and group_kw(u, "TERMINATOR"):
		return 1
	return 0

static func charge_roll_bonus_source(u: Dictionary) -> String:
	return "Death Blow (Terminator Storm Force)" if charge_roll_bonus(u) > 0 else ""

## Corporeum Reliquary: "In your first Movement phase, this unit can make an
## ingress move" — the bearer's (Attached) unit, battle round 1, its owner's
## own Movement phase.
static func can_ingress_first_round(u: Dictionary) -> bool:
	if not enabled() or u.is_empty() or group_bearer(u, CORPOREUM).is_empty():
		return false
	return Common.battle_round() == 1 and int(Common.current_phase()) == int(GameStateData.Phase.MOVEMENT) \
		and Common.active_player() == int(u.get("owner", 0))

# ===========================================================================
# Attack modifiers (RulesEngine.ork11e_ab_mods aggregator — every attack path)
# ===========================================================================

## "In a turn a friendly GRAVIS unit made a normal move" — flags of any
## component this turn (the Scoring phase clears them at the end of the turn).
static func made_normal_move_this_turn(u: Dictionary) -> bool:
	for gu in group_units(u):
		var f: Dictionary = gu.get("flags", {})
		if bool(f.get("moved", false)) and not bool(f.get("advanced", false)) and not bool(f.get("fell_back", false)) \
				and not bool(f.get("remained_stationary", false)) and not bool(f.get("arrived_from_reserves", false)) \
				and not bool(f.get("set_up_this_turn", false)):
			return true
	return false

static func walking_fortress_applies(u: Dictionary) -> bool:
	return unit_has_det(u, GRAVIS_LINEBREAKER) and group_kw(u, "GRAVIS") and made_normal_move_this_turn(u)

static func merge_attack_mods(m: Dictionary, actor: Dictionary, target: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> void:
	if not enabled() or actor.is_empty():
		return
	var owner := int(actor.get("owner", 0))
	if owner <= 0 or not Common.is_sm_army(owner):
		return
	var ranged := not is_melee
	# --- Ironclad Champions — Enduring Vengeance: DREADNOUGHT re-roll hit rolls of 1.
	if unit_has_det(actor, IRONCLAD) and group_kw(actor, "ADEPTUS ASTARTES") and group_kw(actor, "DREADNOUGHT"):
		_reroll_at_least_ones(m)
		_src(m, "Enduring Vengeance (Ironclad Champions)", "hit", "reroll_ones", "DREADNOUGHT unit — hit rolls of 1")
	# --- Venerable Champion (Aura): AA INFANTRY / MOUNTED within 6" of the bearer.
	if group_kw(actor, "ADEPTUS ASTARTES") and (group_kw(actor, "INFANTRY") or group_kw(actor, "MOUNTED")):
		for b in bearers(owner, VENERABLE_CHAMPION):
			if str(b.get("id", "")) in Common.attached_group_ids(str(actor.get("id", ""))):
				continue
			var d := _group_distance(actor, b)
			if d <= VENERABLE_RANGE_IN + 0.001:
				_reroll_at_least_ones(m)
				_src(m, "Venerable Champion (Aura)", "hit", "reroll_ones", "within %.1f\" of %s" % [d, Common.unit_name(str(b.get("id", "")))])
				break
	# --- Gravis Linebreaker Force — Walking Fortress: normal move -> ranged +1 to hit (no [HEAVY]).
	if ranged and walking_fortress_applies(actor):
		m["hit_plus"] = true
		_src(m, "Walking Fortress (Gravis Linebreaker Force)", "hit", "plus_one", "GRAVIS unit made a normal move this turn — ranged attacks +1 to hit, no [HEAVY]")
	# --- Champion of the First Company: the unit's melee attacks have [LETHAL HITS].
	if is_melee and not group_bearer(actor, CHAMPION_FIRST_CO).is_empty():
		m["lethal"] = true
		_src(m, "Champion of the First Company", "other", "lethal_hits", "melee [LETHAL HITS]")
	# --- Furious Assault: melee [SUSTAINED HITS 1: non-MONSTER/VEHICLE].
	if is_melee and not target.is_empty() and not group_is_mv(target) and not group_bearer(actor, FURIOUS_ASSAULT).is_empty():
		m["sustained"] = maxi(int(m.get("sustained", 0)), 1)
		_src(m, "Furious Assault", "other", "sustained_hits_1", "melee vs a non-MONSTER/VEHICLE unit")
	# --- Honour of Vigilance: the unit's ranged attacks have [LETHAL HITS].
	if ranged and not group_bearer(actor, HONOUR_VIGILANCE).is_empty():
		m["lethal"] = true
		_src(m, "Honour of Vigilance", "other", "lethal_hits", "ranged [LETHAL HITS]")
	# --- Master-forged Firearms: THIS MODEL's ranged attacks (not [PSYCHIC]) +1 A, S, AP (D: ranged_damage_bonus).
	if ranged and has_enh(actor, MASTER_FORGED) and not _is_psychic_weapon(weapon_profile):
		m["attacks"] = int(m.get("attacks", 0)) + 1
		m["strength"] = int(m.get("strength", 0)) + 1
		m["ap"] = int(m.get("ap", 0)) + 1
		_src(m, "Master-forged Firearms", "other", "profile", "the bearer's ranged attacks +1 A, S, AP and D")

## Master-forged Firearms +1 D for the bearer's ranged (non-[PSYCHIC]) attacks
## (RulesEngine ranged damage_raw hook — overwatch / auto / interactive paths).
static func ranged_damage_bonus(shooter: Dictionary, weapon_profile: Dictionary) -> int:
	if not enabled() or shooter.is_empty() or str(weapon_profile.get("type", "Ranged")).to_lower() == "melee":
		return 0
	if has_enh(shooter, MASTER_FORGED) and not _is_psychic_weapon(weapon_profile):
		return 1
	return 0

# ===========================================================================
# Defence (RulesEngine S > T wound penalty; EffectPrimitives -1 D)
# ===========================================================================

## Indefatigable Fortitude / Indomitable Defence source for an attack with
## strength S against `target` (toughness T); "" = no -1 to wound.
static func incoming_wound_penalty_source(target: Dictionary, strength: int, toughness: int) -> String:
	if not enabled() or target.is_empty() or strength <= toughness:
		return ""
	if not group_bearer(target, INDEFATIGABLE).is_empty():
		return "Indefatigable Fortitude"
	if unit_has_det(target, GRAVIS_SIEGE) and group_kw(target, "GRAVIS"):
		var tid := str(target.get("id", ""))
		if tid != "" and Common.group_in_range_of_any_objective(tid):
			return "Indomitable Defence (Gravis Siege Force)"
	return ""

static func incoming_wound_penalty(target: Dictionary, strength: int, toughness: int) -> bool:
	return incoming_wound_penalty_source(target, strength, toughness) != ""

## Artificer Sarcophagus: attacks that target this unit have -1 D.
static func damage_minus(target: Dictionary) -> int:
	if not enabled() or target.is_empty():
		return 0
	return 1 if not group_bearer(target, ARTIFICER_SARCOPHAGUS).is_empty() else 0

# ===========================================================================
# Tacticus Firestorm Force — Codex Fire-patterns
# ===========================================================================

## [RAPID FIRE] benefits up to the attack's maximum range (RulesEngine /
## ShootingController: the "half range" test uses the full range).
static func full_range_rapid_fire(actor: Dictionary) -> bool:
	return unit_has_det(actor, TACTICUS_FIRESTORM) and group_kw(actor, "ADEPTUS ASTARTES") and group_kw(actor, "TACTICUS")

# ===========================================================================
# Movement (Relentless Advance Scouts 5", Honour of Vigilance advance re-roll)
# ===========================================================================

## Relentless Advance: "This unit has Scouts 5\"" (0 = none).
static func scouts_distance(u: Dictionary) -> float:
	if not enabled() or u.is_empty():
		return 0.0
	return RELENTLESS_SCOUTS_IN if not group_bearer(u, RELENTLESS_ADVANCE).is_empty() else 0.0

## Honour of Vigilance: with the devastator doctrine active for this unit, it
## can re-roll advance rolls ("" = no free re-roll).
static func free_advance_reroll_source(u: Dictionary) -> String:
	if not enabled() or u.is_empty() or group_bearer(u, HONOUR_VIGILANCE).is_empty():
		return ""
	return "Honour of Vigilance" if "devastator" in group_doctrines(u) else ""

# ===========================================================================
# Objective control — Immovable Conquerors (+1 OC)
# ===========================================================================

static func oc_bonus(u: Dictionary) -> int:
	if not enabled() or u.is_empty():
		return 0
	return 1 if not group_bearer(u, IMMOVABLE).is_empty() else 0

# ===========================================================================
# Leadership — Tempered in Battle (Aura): re-roll leadership rolls
# ===========================================================================

## The bearer whose aura covers `unit_id` ("" = none): friendly ADEPTUS
## ASTARTES unit within 6" of the bearer model.
static func battle_shock_reroll_source(unit_id: String) -> String:
	if not enabled() or unit_id == "":
		return ""
	var u := Common.unit(unit_id)
	if u.is_empty() or not group_kw(u, "ADEPTUS ASTARTES"):
		return ""
	var owner := int(u.get("owner", 0))
	for b in bearers(owner, TEMPERED):
		var d := 0.0 if str(b.get("id", "")) in Common.attached_group_ids(unit_id) else Common.unit_distance_inches(b, Common.group_union(unit_id))
		if d <= TEMPERED_RANGE_IN + 0.001:
			return "Tempered in Battle (%s)" % Common.unit_name(str(b.get("id", "")))
	return ""

# ===========================================================================
# Tactical Brethren — Laurels of Vigilance (-1CP Fire Overwatch / Heroic Intervention)
# ===========================================================================

static func stratagem_cp_discount(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	if not enabled() or target_unit_id == "":
		return {}
	var sid := stratagem_id.replace("_11e", "")
	if sid != "fire_overwatch" and sid != "heroic_intervention":
		return {}
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return {}
	if not (group_kw(u, "ADEPTUS ASTARTES") and group_kw(u, "BATTLELINE")):
		return {}
	var f = Common.state().get("factions", {}).get(str(player), {})
	if f is Dictionary and int(f.get(FK_LAURELS_ROUND, 0)) == Common.battle_round():
		return {}
	for b in bearers(player, LAURELS_VIGILANCE):
		var d := 0.0 if str(b.get("id", "")) in Common.attached_group_ids(target_unit_id) else Common.unit_distance_inches(b, Common.group_union(target_unit_id))
		if d <= LAURELS_RANGE_IN + 0.001:
			return {"discount": 1, "source": "Laurels of Vigilance (%s)" % Common.unit_name(str(b.get("id", ""))), "player": player, "target": target_unit_id}
	return {}

## True when a Laurels of Vigilance discount could still apply to some unit of
## `player` this battle round (StratagemManager: a player short of the base CP
## is offered the window and the per-target check decides).
static func cp_discount_possible(player: int, stratagem_id: String) -> bool:
	var sid := stratagem_id.replace("_11e", "")
	if not enabled() or (sid != "fire_overwatch" and sid != "heroic_intervention"):
		return false
	var f = Common.state().get("factions", {}).get(str(player), {})
	if f is Dictionary and int(f.get(FK_LAURELS_ROUND, 0)) == Common.battle_round():
		return false
	return not bearers(player, LAURELS_VIGILANCE).is_empty()

static func record_cp_discount(disc: Dictionary) -> Array:
	if disc.is_empty():
		return []
	var p := int(disc.get("player", 0))
	var diffs: Array = [{"op": "set", "path": "factions.%s.%s" % [str(p), FK_LAURELS_ROUND], "value": Common.battle_round()}]
	Common.apply_diffs(diffs)
	var msg := "%s: the stratagem on %s costs 1CP less (once this battle round)" % [str(disc.source), Common.group_label(str(disc.target))]
	_log(msg)
	Common.game_log(p, msg)
	return diffs

# ===========================================================================
# Tacticus Firestorm Force — Cyber-familiar (redeploy table)
# ===========================================================================

## The redeploy-table entry ({} = none). "name" is the bearer's own spelling
## of the enhancement (FactionAbilityManager finds the bearer by exact name).
static func redeploy_enhancement(player: int) -> Dictionary:
	if not enabled():
		return {}
	for b in bearers(player, CYBER_FAMILIAR, false):
		for e in b.get("meta", {}).get("enhancements", []):
			var n := str(e.get("name", "")) if e is Dictionary else str(e)
			if enh_key(n) == CYBER_FAMILIAR:
				return {"name": n, "keywords": ["ADEPTUS ASTARTES", "INFANTRY"]}
	return {}

# ===========================================================================
# Tactical Insight — the tactical doctrine in addition (BasePhase hook)
# ===========================================================================

## Write / clear SWCommon's per-unit additional doctrine for every component
## of each Tactical Insight bearer's (Attached) unit. Idempotent; called at
## every phase start. Only "tactical" entries this rule wrote are removed.
static func on_phase_enter(_phase: int) -> void:
	if not enabled():
		return
	var units: Dictionary = Common.state().get("units", {})
	var want: Dictionary = {}
	for uid in units:
		var u: Dictionary = units[uid]
		if not has_enh(u, TACTICAL_INSIGHT) or not Common.is_alive(u):
			continue
		for gid in Common.attached_group_ids(str(uid)):
			want[str(gid)] = true
	var diffs: Array = []
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		var extra: Array = (flags.get(F_DOCTRINE_EXTRA, []) as Array).duplicate() if flags.get(F_DOCTRINE_EXTRA, []) is Array else []
		var mine := bool(flags.get(F_TACTICAL_INSIGHT, false))
		if want.has(str(uid)):
			if not "tactical" in extra:
				extra.append("tactical")
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_DOCTRINE_EXTRA], "value": extra})
			if not mine:
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_TACTICAL_INSIGHT], "value": true})
		elif mine:
			extra.erase("tactical")
			if extra.is_empty():
				diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_DOCTRINE_EXTRA]})
			else:
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_DOCTRINE_EXTRA], "value": extra})
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_TACTICAL_INSIGHT]})
	if not diffs.is_empty():
		Common.apply_diffs(diffs)
		_log("Tactical Insight: tactical doctrine (in addition) synced — %d op(s)" % diffs.size())

# ===========================================================================
# Narthecis Gauntlet — free rule card, phase_start of your Command phase
# ===========================================================================

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

static func _healable(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) and m.get("position", null) != null:
				return true
			if m.get("alive", true) and int(m.get("current_wounds", m.get("wounds", 1))) < int(m.get("wounds", 1)):
				return true
	return false

static func _narthecis_targets(player: int) -> Array:
	var out: Array = []
	if int(Common.current_phase()) != int(GameStateData.Phase.COMMAND) or Common.active_player() != player:
		return out
	for b in bearers(player, NARTHECIS):
		var bid := str(b.get("id", ""))
		if str(b.get("flags", {}).get(F_NARTHECIS_TURN, "")) == _turn_stamp():
			continue
		if not _healable(bid):
			continue
		out.append(Common.target_entry(bid, {"label": "%s — heal D3+1" % Common.group_label(bid)}))
	return out

static func window_offers(player: int, window_id: String, _ctx: Dictionary) -> Array:
	if not enabled() or not Common.is_sm_army(player) or window_id != "phase_start":
		return []
	var targets := _narthecis_targets(player)
	if targets.is_empty():
		return []
	return [{"stratagem_id": RULE_NARTHECIS, "name": "NARTHECIS GAUNTLET", "cp_cost": 0, "sm11e_rule": true, "rule": true,
		"type": "Enhancement — Gravis Siege Force (your Command phase, free)",
		"effect_text": "In your Command phase, this unit heals D3+1 wounds.", "targets": targets}]

## BasePhase.enter_phase: queue a phase_start window for the Command phase
## when a player has a Narthecis Gauntlet card (skipped when another module
## already queued that player's phase_start window — the offers are merged).
static func phase_start_entries(phase: int, existing: Array = []) -> Array:
	var out: Array = []
	if not enabled() or phase != int(GameStateData.Phase.COMMAND):
		return out
	var nm = Common.autoload("NetworkManager")
	if nm and nm.has_method("is_networked") and bool(nm.is_networked()):
		return out
	var p := Common.active_player()
	for e in existing:
		if int(e.get("player", 0)) == p and str(e.get("window_id", "")) == "phase_start":
			return out
	if not window_offers(p, "phase_start", {}).is_empty():
		out.append({"player": p, "window_id": "phase_start", "ctx": {"phase": "command"}})
	return out

static func use_rule_offer(player: int, sid: String, target_unit_id: String, _ctx: Dictionary) -> Dictionary:
	var res: Dictionary
	match sid:
		RULE_NARTHECIS:
			res = _use_narthecis(player, target_unit_id)
		_:
			res = {"success": false, "error": "unknown Codex: Space Marines rule offer %s" % sid, "diffs": []}
	if res.get("success", false):
		res["rule_use"] = true
		if not res.has("reopen_window"):
			res["reopen_window"] = true
	return res

static func _use_narthecis(player: int, bearer_id: String) -> Dictionary:
	var ok := false
	for t in _narthecis_targets(player):
		ok = ok or str(t.unit_id) == bearer_id
	if not ok:
		return {"success": false, "error": "Narthecis Gauntlet: the bearer's unit must have lost wounds (your Command phase, once)", "diffs": []}
	var d3 := int(Common.roll_dice(1, 3)[0])
	var amount := d3 + 1
	var h := heal_diffs(bearer_id, amount)
	var diffs: Array = h.diffs
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_NARTHECIS_TURN], "value": _turn_stamp()})
	Common.apply_diffs(diffs)
	var line := "NARTHECIS GAUNTLET — %s heals D3+1 = %d+1 = %d wound(s) (%d wound(s) restored, %d model(s) returned)" % [
		Common.group_label(bearer_id), d3, amount, int(h.healed), int(h.revived)]
	_log(line)
	Common.game_log(player, line)
	var tm = Common.autoload("ToastManager")
	if tm and tm.has_method("show_toast"):
		tm.show_toast(line, Color(0.55, 1.0, 0.6))
	return {"success": true, "diffs": diffs, "stratagem_name": "Narthecis Gauntlet", "message": line, "healed": int(h.healed), "revived": int(h.revived)}

## Healing over the (Attached) unit — the engine's heal convention: a wounded
## model first; with none wounded, a destroyed model returns with 1 wound.
static func heal_diffs(unit_id: String, amount: int) -> Dictionary:
	var diffs: Array = []
	var healed := 0
	var revived := 0
	var sim: Dictionary = {}
	var comps := Common.attached_group_ids(unit_id)
	for _i in range(amount):
		var done := false
		for gid in comps:
			var models: Array = Common.unit(str(gid)).get("models", [])
			for idx in range(models.size()):
				var key := "%s:%d" % [gid, idx]
				var m: Dictionary = models[idx]
				var st: Dictionary = sim.get(key, {"alive": m.get("alive", true), "cw": int(m.get("current_wounds", m.get("wounds", 1)))})
				if st.alive and int(st.cw) < int(m.get("wounds", 1)):
					st.cw = int(st.cw) + 1
					sim[key] = st
					healed += 1
					done = true
					break
			if done:
				break
		if done:
			continue
		for gid in comps:
			var models2: Array = Common.unit(str(gid)).get("models", [])
			for idx in range(models2.size()):
				var key2 := "%s:%d" % [gid, idx]
				var m2: Dictionary = models2[idx]
				var st2: Dictionary = sim.get(key2, {"alive": m2.get("alive", true), "cw": int(m2.get("current_wounds", m2.get("wounds", 1)))})
				if not st2.alive and m2.get("position", null) != null:
					st2.alive = true
					st2.cw = 1
					sim[key2] = st2
					revived += 1
					done = true
					break
			if done:
				break
		if not done:
			break
	for key in sim:
		var parts := str(key).rsplit(":", true, 1)
		var st3: Dictionary = sim[key]
		diffs.append({"op": "set", "path": "units.%s.models.%s.current_wounds" % [parts[0], parts[1]], "value": int(st3.cw)})
		diffs.append({"op": "set", "path": "units.%s.models.%s.alive" % [parts[0], parts[1]], "value": bool(st3.alive)})
	return {"diffs": diffs, "healed": healed, "revived": revived}

## AI: always use the free Narthecis Gauntlet card (it is only offered when
## the bearer's unit has something to heal). Synchronous; {} = not mine.
static func ai_decide(_player: int, _window_id: String, offers: Array, _ctx: Dictionary) -> Dictionary:
	for offer in offers:
		if str(offer.get("stratagem_id", "")) != RULE_NARTHECIS:
			continue
		for t in offer.get("targets", []):
			return {"use": true, "stratagem_id": RULE_NARTHECIS, "target_unit_id": str(t.unit_id), "context": {}, "name": "NARTHECIS GAUNTLET"}
	return {}
