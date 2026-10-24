extends RefCounted

## SWAbilities11e — Codex: Space Marines (11e), Space Wolves DATASHEET and
## WARGEAR abilities of the 21 SPACE WOLVES datasheets + the Librarius army
## rule's psyker-level budget (WP-S4).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md and PLAN_SPACE_WOLVES.md.
## Printed text: .llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md.
## Audit + rulings: space_wolves_abilities_audit.md and RULINGS.md (## WP-S4).
##
## Everything is static. Engine files only reach this module through thin,
## commented hooks (one line each):
##   RulesEngine        ork11e_ab_mods aggregator (merge_attack_mods), S > T
##                      wound penalty, Lone Operative (Iron Priest), precision /
##                      devastating / ignore-wound-penalty consumers
##   EffectPrimitives   advance-and-charge, advance-and-shoot ([ASSAULT]),
##                      advance / charge re-rolls
##   MovementPhase      advance roll (Wind Walker 6, Fervour +1), ingress round
##                      (High King of Fenris), Savage Frenzy fall-back mode
##   ChargePhase        charge roll +1 (Fervour of the Ancients)
##   FightPhase         Fight On Death (Murder-maker, Anvil of Endurance,
##                      Heroic Last Stand), the unit_has_fought window (Hammer Blow)
##   FormationsPhase    unit splits (Old Greymanes, Let Loose the Wolves),
##                      warlord block (Force of Untamed Destruction)
##   MissionManager     model OC (Hunting Hounds)
##   TerrainManager     detection range (Storm Caller)
##   StratagemManager   ability cards (window_offers / use), Ancient Tactician
##                      -1 CP, FIRE OVERWATCH refusal (Murderous Hurricane)
##   ArmyListManager    wargear stat changes at army load (Storm Shield, Blizzard Shield)
##   PhaseManager       on_phase_transition (expiry, Guile of the Wolf)
##   BasePhase          phase_start_entries (the "start of the phase" cards)
##   AIDecisionMaker    ai_score for the cards (synchronous)
##
## Only SPACE WOLVES units of a Space Wolves army (SWCommon.is_sw_army, 11e)
## have these rules (SW-D1).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const PX_PER_INCH := 40.0

# GameState.Phase mirror.
const PH_FORMATIONS := 0
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const ST_IN_RESERVES := 7  # GameState.UnitStatus.IN_RESERVES
const ST_UNDEPLOYED := 0

const KW_SW := "SPACE WOLVES"

## slug -> FOLDED printed name (see fold()).
const NAMES := {
	"high_king_of_fenris": "high king of fenris",
	"guile_of_the_wolf": "guile of the wolf",
	"battle_lust": "battle lust",
	"war_howl": "war howl",
	"wind_walker": "wind walker",
	"high_rune_priest": "high rune priest",
	"murderous_hurricane": "murderous hurricane",
	"storm_caller": "storm caller",
	"tempests_wrath": "tempests wrath",
	"slayers_oath": "slayers oath",
	"oathbound": "oathbound",
	"legendary_tenacity": "legendary tenacity",
	"ancient_tactician": "ancient tactician",
	"berserk_charge": "berserk charge",
	"old_greymanes": "old greymanes",
	"cunning_hunters": "cunning hunters",
	"gift_of_the_iron_wolf": "gift of the iron wolf",
	"iron_priest": "iron priest",
	"judgement_of_the_omnissiah": "judgement of the omnissiah",
	"savage_frenzy": "savage frenzy",
	"death_totem": "death totem",
	"murder_maker": "murder maker",
	"bestial_fury": "bestial fury",
	"force_of_untamed_destruction": "force of untamed destruction",
	"champion_of_the_kingsguard": "champion of the kingsguard",
	"anvil_of_endurance": "anvil of endurance",
	"rugged_resilience": "rugged resilience",
	"storm_shield": "storm shield",
	"thunderous_charge": "thunderous charge",
	"predatory_instinct": "predatory instinct",
	"hunting_hounds": "hunting hounds",
	"fervour_of_the_ancients": "fervour of the ancients",
	"blizzard_shield": "blizzard shield",
	"healing_balms": "healing balms",
	"litany_of_hate": "litany of hate",
	"tempered_ferocity": "tempered ferocity",
	"heroic_last_stand": "heroic last stand",
	"headhunters": "headhunters",
	"let_loose_the_wolves": "let loose the wolves",
	"hammer_blow": "hammer blow",
	"violent_fury": "violent fury",
	"bestial_rage": "bestial rage",
	"deadly_stalkers": "deadly stalkers",
	"haywire_mine": "haywire mine",
}

## slug -> printed name (cards, logs, the UnitAbilityManager once-per-battle key).
const DISPLAY := {
	"high_king_of_fenris": "High King of Fenris", "guile_of_the_wolf": "Guile of the Wolf",
	"battle_lust": "Battle-lust", "war_howl": "War Howl", "wind_walker": "Wind Walker",
	"high_rune_priest": "High Rune Priest", "murderous_hurricane": "Murderous Hurricane",
	"storm_caller": "Storm Caller", "tempests_wrath": "Tempest's Wrath",
	"slayers_oath": "Slayer's Oath", "oathbound": "Oathbound",
	"legendary_tenacity": "Legendary Tenacity", "ancient_tactician": "Ancient Tactician",
	"berserk_charge": "Berserk Charge", "old_greymanes": "Old Greymanes",
	"cunning_hunters": "Cunning Hunters", "gift_of_the_iron_wolf": "Gift of the Iron Wolf",
	"iron_priest": "Iron Priest", "judgement_of_the_omnissiah": "Judgement of the Omnissiah",
	"savage_frenzy": "Savage Frenzy", "death_totem": "Death Totem", "murder_maker": "Murder-maker",
	"bestial_fury": "Bestial Fury", "force_of_untamed_destruction": "Force of Untamed Destruction",
	"champion_of_the_kingsguard": "Champion of the Kingsguard", "anvil_of_endurance": "Anvil of Endurance",
	"rugged_resilience": "Rugged Resilience", "storm_shield": "Storm Shield",
	"thunderous_charge": "Thunderous Charge", "predatory_instinct": "Predatory Instinct",
	"hunting_hounds": "Hunting Hounds", "fervour_of_the_ancients": "Fervour of the Ancients",
	"blizzard_shield": "Blizzard Shield", "healing_balms": "Healing Balms",
	"litany_of_hate": "Litany of Hate", "tempered_ferocity": "Tempered Ferocity",
	"heroic_last_stand": "Heroic Last Stand", "headhunters": "Headhunters",
	"let_loose_the_wolves": "Let Loose the Wolves", "hammer_blow": "Hammer Blow",
	"violent_fury": "Violent Fury", "bestial_rage": "Bestial Rage",
	"deadly_stalkers": "Deadly Stalkers", "haywire_mine": "Haywire Mine",
}

# --- flags (sw11e_ab_*; none uses the effect_ prefix ShootingPhase wipes) ----
const F_OATH := "sw11e_ab_oath"                   # Ulrik: the enemy unit (head id) of his slayer's oath
const F_OATH_DONE := "sw11e_ab_oath_chosen"       # true once the start-of-battle choice was made
const F_QUARRY := "sw11e_ab_quarry"               # Headtakers: their quarry (head id)
const F_QUARRY_DONE := "sw11e_ab_quarry_round1"   # true once the round-1 quarry was chosen
const F_SUPPRESSED := "sw11e_ab_suppressed"       # {player, source}: -1 to hit until the start of player's next turn
const F_NO_SNAP := "sw11e_ab_no_snap"             # {player}: cannot make snap-shooting attacks (end of turn)
const F_STORM_CALLER := "sw11e_ab_storm_caller"   # true: -3" detection range (end of phase)
const F_GIFTED := "sw11e_ab_gifted"               # {player}: attacks ignore hit/wound modifiers until player's next Movement phase
const F_GIFT_PHASE := "sw11e_ab_gift_phase"       # phase key: this VEHICLE was selected for Gift of the Iron Wolf this phase
const F_HIGH_KING := "sw11e_ab_high_king"         # {round, player}: ingress this phase treats the battle round as one higher
const F_PHASE_USES := "sw11e_ab_phase_uses"       # {slug: phase_key}: once-per-phase per-unit uses
const F_ROUND_USES := "sw11e_ab_round_uses"       # {slug: battle round}: once-per-battle-round per-unit uses
const F_GUILE := "sw11e_ab_guile"                 # true: this unit's sw11e_doctrine_extra was written by Guile of the Wolf
const F_SPLIT := "sw11e_ab_split"                 # "old_greymanes" | "let_loose_the_wolves": this unit is a half of a split
const F_DOCTRINE_EXTRA := "sw11e_doctrine_extra"  # SWCommon doctrine-state key (per-unit additional doctrines)
# Librarius budget (per PSYKER unit, per battle round).
const F_PSY_ROUND := "sw11e_psy_round"
const F_PSY_USED := "sw11e_psy_used"
const F_PSY_PHASE := "sw11e_psy_phase"
const F_PSY_PHASE_NAMES := "sw11e_psy_phase_names"
## Army-level ledger on GameState.state.players[p]: {slug: turn key}.
const ARMY_USES := "sw11e_ab_army_uses"
## A model's list-build marker (Storm Shield / Blizzard Shield applied once).
const M_SHIELD := "sw11e_shield"

const SID_PREFIX := "sw11e_ab_"

const OATH_KEYWORDS := ["CHARACTER", "MONSTER", "VEHICLE"]
const HURRICANE_RANGE_IN := 12.0
const TEMPEST_RANGE_IN := 18.0
const HAYWIRE_RANGE_IN := 6.0
const GIFT_RANGE_IN := 3.0
const IRON_PRIEST_LO_RANGE_IN := 3.0
const PREDATORY_RANGE_IN := 8.0
const HOUNDS_RANGE_IN := 6.0
const FERVOUR_RANGE_IN := 6.0
const TEMPERED_RANGE_IN := 6.0
const STALKERS_RANGE_IN := 6.0
const MURDER_MAKER_RANGE_IN := 6.0
const STORM_CALLER_DETECTION_IN := -3.0

## Librarius: psyker level of the datasheet abilities that grant one (the
## army files drop the printed "(psyker level 3)" suffix).
const PSYKER_LEVEL_ABILITIES := {"high rune priest": 3}
## Psychic level of each Space Wolves psychic ability.
const PSYCHIC_LEVELS := {"murderous_hurricane": 1, "storm_caller": 1, "tempests_wrath": 1}

## Hunting Wolf profile (Wolf Guard Headtakers / Wolf Scouts): M10 T4 Sv6+ W1 Ld8 OC0.
const HUNTING_WOLF_STATS := {"move": 10, "toughness": 4, "save": 6, "wounds": 1, "leadership": 8, "objective_control": 0}


# ===========================================================================
# Names / membership
# ===========================================================================

## Lower-case, apostrophes removed, a trailing "(…)" dropped, every
## non-alphanumeric character a space, spaces collapsed (CustodesAbilities.fold).
static func fold(name: String) -> String:
	var s := name.strip_edges()
	var p := s.find("(")
	if p > 0:
		s = s.substr(0, p)
	s = s.to_lower().replace("’", "").replace("‘", "").replace("'", "")
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		var code := c.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			out += c
		else:
			out += " "
	while out.find("  ") >= 0:
		out = out.replace("  ", " ")
	return out.strip_edges()

static func _ability_name(ab) -> String:
	if ab is String:
		return ab
	if ab is Dictionary:
		return str(ab.get("name", ""))
	return ""

static func _edition_11() -> bool:
	return int(GameConstants.edition) >= 11

## A SPACE WOLVES unit of a Space Wolves army (SW-D1).
static func is_sw_unit(u: Dictionary) -> bool:
	if u.is_empty() or not _edition_11() or not Common.has_keyword(u, KW_SW):
		return false
	return Common.is_sw_army(int(u.get("owner", 0)))

## True when the unit's datasheet lists the ability of `slug` (and the codex
## rules apply to it).
static func has(u: Dictionary, slug: String) -> bool:
	var want := str(NAMES.get(slug, ""))
	if want == "" or u.is_empty():
		return false
	var found := false
	for ab in u.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == want:
			found = true
			break
	return found and is_sw_unit(u)

static func has_id(unit_id: String, slug: String) -> bool:
	return has(Common.unit(unit_id), slug)

static func display(slug: String) -> String:
	return str(DISPLAY.get(slug, slug))

## Every component of the Attached unit (19.03); "this unit" = all of them.
static func group(unit_id: String) -> Array:
	return Common.attached_group_ids(unit_id)

static func head_id(unit_id: String) -> String:
	return Common.head_id(unit_id)

## The first component of the (Attached) unit that has `slug`, or "".
static func group_holder(unit_id: String, slug: String) -> String:
	if unit_id == "":
		return ""
	for gid in group(unit_id):
		if has_id(str(gid), slug):
			return str(gid)
	return ""

static func group_has(unit_id: String, slug: String) -> bool:
	return group_holder(unit_id, slug) != ""

static func _uid(u: Dictionary) -> String:
	return str(u.get("id", ""))

## A flag on any component of the (Attached) unit (null when none has it).
static func _gflag(unit_id: String, flag: String):
	for gid in group(unit_id):
		var f: Dictionary = Common.unit(str(gid)).get("flags", {})
		if f.has(flag):
			return f[flag]
	return null

static func _group_shocked(unit_id: String) -> bool:
	for gid in group(unit_id):
		if Common.is_battle_shocked(Common.unit(str(gid))):
			return true
	return false

static func _group_charged(unit_id: String) -> bool:
	for gid in group(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
			return true
	return false

static func _phase() -> int:
	return Common.current_phase()

static func _round() -> int:
	return Common.battle_round()

static func _phase_key() -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), _phase()]

static func _turn_key() -> String:
	return "%d:%d" % [_round(), Common.active_player()]

static func _uam():
	return Common.autoload("UnitAbilityManager")

static func _dist(a_id: String, b_id: String) -> float:
	return Common.group_distance_inches(a_id, b_id)

static func _visible(from_id: String, to_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("_has_los_to_target_unit"):
		return true
	return bool(re._has_los_to_target_unit(head_id(from_id), head_id(to_id), Common.state()))

static func _engaged(unit_id: String) -> bool:
	for gid in group(unit_id):
		if Common.is_engaged(str(gid)):
			return true
	return false

static func _is_mv(unit_id: String) -> bool:
	return Common.group_has_keyword(unit_id, "MONSTER") or Common.group_has_keyword(unit_id, "VEHICLE")

static func _alive_models(unit_id: String) -> int:
	var n := 0
	for gid in group(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true):
				n += 1
	return n

static func _sorted_by_distance(from_id: String, ids: Array) -> Array:
	var arr := ids.duplicate()
	arr.sort_custom(func(a, b): return _dist(from_id, str(a)) < _dist(from_id, str(b)))
	return arr

static func _unit_options(ids: Array, prompt: String) -> Dictionary:
	var opts: Array = []
	for uid in ids:
		opts.append({"id": str(uid), "label": Common.group_label(str(uid))})
	return {"kind": "unit", "prompt": prompt, "options": opts}

static func _event_log(player: int, text: String) -> void:
	Common.game_log(player, text)


# ===========================================================================
# Usage limits
# ===========================================================================

## (Once per battle, per unit) — UnitAbilityManager's ledger (saved with the game).
static func used_in_battle(holder_id: String, slug: String) -> bool:
	var uam = _uam()
	if uam == null or not uam.has_method("is_once_per_battle_used"):
		return false
	return bool(uam.is_once_per_battle_used(holder_id, display(slug)))

static func _mark_battle_use(holder_id: String, slug: String) -> void:
	var uam = _uam()
	if uam and uam.has_method("mark_once_per_battle_used"):
		uam.mark_once_per_battle_used(holder_id, display(slug))

## (Once per phase, per unit).
static func used_this_phase(holder_id: String, slug: String) -> bool:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _phase_key()

static func _phase_use_diff(holder_id: String, slug: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _phase_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_PHASE_USES], "value": nd}

## (Once per battle round, per unit).
static func used_this_round(holder_id: String, slug: String) -> bool:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_ROUND_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and int(uses.get(slug, -1)) == _round()

static func _round_use_diff(holder_id: String, slug: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_ROUND_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _round()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_ROUND_USES], "value": nd}

## (Once per turn, per army).
static func army_used_this_turn(player: int, slug: String) -> bool:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _turn_key()

static func _army_use_diff(player: int, slug: String) -> Dictionary:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _turn_key()
	return {"op": "set", "path": "players.%s.%s" % [str(player), ARMY_USES], "value": nd}


# ===========================================================================
# LIBRARIUS — psyker level budget (army rule; Njal Stormcaller)
# ===========================================================================
# "In a battle round, a friendly ADEPTUS ASTARTES PSYKER unit can use a number
# of psychic abilities whose total psychic level does not exceed that PSYKER
# unit's psyker level." Budget and the once-per-phase limit per power are
# kept on the PSYKER model's own unit (OrkArmyRules11e Unstable Energies shape).

static func is_budgeted_psyker(u: Dictionary) -> bool:
	return is_sw_unit(u) and Common.has_keyword(u, "ADEPTUS ASTARTES") and Common.has_keyword(u, "PSYKER")

static func psyker_level(u: Dictionary) -> int:
	var level := 0
	for ab in u.get("meta", {}).get("abilities", []):
		var n := _ability_name(ab)
		var re := RegEx.new()
		re.compile("(?i)psyker\\s+level\\s+(\\d+)")
		var m := re.search(n)
		if m:
			level = maxi(level, int(m.get_string(1)))
			continue
		var base := fold(n)
		if PSYKER_LEVEL_ABILITIES.has(base):
			level = maxi(level, int(PSYKER_LEVEL_ABILITIES[base]))
	if level == 0 and is_budgeted_psyker(u):
		level = 1  # "a psyker level of 1 or higher"
	return level

static func psychic_level(slug: String) -> int:
	return int(PSYCHIC_LEVELS.get(slug, 1))

static func psychic_levels_used(u: Dictionary) -> int:
	var flags: Dictionary = u.get("flags", {})
	if int(flags.get(F_PSY_ROUND, -1)) != _round():
		return 0
	return int(flags.get(F_PSY_USED, 0))

## {ok, reason, level, used, cost}
static func can_use_psychic(unit_id: String, slug: String) -> Dictionary:
	var u := Common.unit(unit_id)
	var cost := psychic_level(slug)
	if u.is_empty() or not is_budgeted_psyker(u):
		return {"ok": false, "reason": "not a PSYKER unit", "level": 0, "used": 0, "cost": cost}
	var level := psyker_level(u)
	var used := psychic_levels_used(u)
	var flags: Dictionary = u.get("flags", {})
	if str(flags.get(F_PSY_PHASE, "")) == _phase_key() and slug in flags.get(F_PSY_PHASE_NAMES, []):
		return {"ok": false, "level": level, "used": used, "cost": cost,
			"reason": "%s has already used %s this phase" % [Common.unit_name(unit_id), display(slug)]}
	if used + cost > level:
		return {"ok": false, "level": level, "used": used, "cost": cost,
			"reason": "Librarius: %s (psyker level %d) has used %d psychic level%s this battle round — %s (psychic level %d) would exceed it" % [
				Common.unit_name(unit_id), level, used, "" if used == 1 else "s", display(slug), cost]}
	return {"ok": true, "reason": "", "level": level, "used": used, "cost": cost}

static func record_psychic_use(unit_id: String, slug: String) -> Array:
	var u := Common.unit(unit_id)
	if u.is_empty():
		return []
	var used := psychic_levels_used(u) + psychic_level(slug)
	var flags: Dictionary = u.get("flags", {})
	var names: Array = []
	if str(flags.get(F_PSY_PHASE, "")) == _phase_key():
		names = (flags.get(F_PSY_PHASE_NAMES, []) as Array).duplicate()
	names.append(slug)
	Common.log_info("SWAbilities11e: Librarius — %s used %s (psychic level %d): %d/%d psyker level spent this battle round" % [
		unit_id, display(slug), psychic_level(slug), used, psyker_level(u)])
	return [
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_ROUND], "value": _round()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_USED], "value": used},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE], "value": _phase_key()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE_NAMES], "value": names},
	]

## A psychic ability can be offered: the holder is a budgeted PSYKER with
## budget left, its unit is not battle-shocked.
static func _psychic_ready(holder_id: String, slug: String) -> bool:
	if not can_use_psychic(holder_id, slug).ok:
		return false
	return not _group_shocked(holder_id)

## Roll the psychic D6 (a 1: the unit is battle-shocked) + the budget diffs.
static func _psychic_roll(holder_id: String, slug: String) -> Dictionary:
	var roll := int(Common.roll_dice(1)[0])
	var diffs: Array = record_psychic_use(holder_id, slug)
	var note := "psychic roll %d" % roll
	if roll == 1:
		for gid in group(holder_id):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
		note += " — a 1: the unit is battle-shocked"
	return {"roll": roll, "diffs": diffs, "note": note}


# ===========================================================================
# PASSIVE COMBAT MODIFIERS — merged into RulesEngine's WP-O6 aggregator
# ===========================================================================

static func _empty_mods() -> Dictionary:
	return {"hit_plus": false, "hit_minus": false, "hit_reroll": "", "ignore_hit_penalties": false,
		"wound_plus": false, "wound_reroll": "", "ignore_wound_penalties": false, "ap": 0, "damage": 0,
		"strength": 0, "attacks": 0, "sustained": 0, "devastating": false, "precision": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

## The Space Wolves contribution, merged INTO `m` (the aggregator result) —
## the one-line RulesEngine hook in ork11e_ab_mods.
static func merge_attack_mods(m: Dictionary, actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, bearer_ids: Array = []) -> void:
	if not _edition_11():
		return
	var c := attack_mods(actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)
	if (c.sources as Array).is_empty():
		return
	m["hit_plus"] = bool(m.get("hit_plus", false)) or c.hit_plus
	m["hit_minus"] = bool(m.get("hit_minus", false)) or c.hit_minus
	m["hit_reroll"] = _reroll_max(str(m.get("hit_reroll", "")), c.hit_reroll)
	m["ignore_hit_penalties"] = bool(m.get("ignore_hit_penalties", false)) or c.ignore_hit_penalties
	m["wound_plus"] = bool(m.get("wound_plus", false)) or c.wound_plus
	m["wound_reroll"] = _reroll_max(str(m.get("wound_reroll", "")), c.wound_reroll)
	m["ignore_wound_penalties"] = bool(m.get("ignore_wound_penalties", false)) or c.ignore_wound_penalties
	m["ap"] = int(m.get("ap", 0)) + int(c.ap)
	m["damage"] = int(m.get("damage", 0)) + int(c.damage)
	m["strength"] = int(m.get("strength", 0)) + int(c.strength)
	m["attacks"] = int(m.get("attacks", 0)) + int(c.attacks)
	m["sustained"] = maxi(int(m.get("sustained", 0)), int(c.sustained))
	m["devastating"] = bool(m.get("devastating", false)) or c.devastating
	m["precision"] = bool(m.get("precision", false)) or c.precision
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append_array(c.sources)

static func attack_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> Dictionary:
	var m := _empty_mods()
	var actor_id := _uid(actor_unit)
	if actor_id == "" or actor_unit.is_empty():
		return m
	var target_id := _uid(target_unit)
	var owner := int(actor_unit.get("owner", 0))

	# --- any attacker: suppressed (Tempest's Wrath, Hammer Blow) ---------------
	var sup = _gflag(actor_id, F_SUPPRESSED)
	if typeof(sup) == TYPE_DICTIONARY:
		m.hit_minus = true
		_src(m, str(sup.get("source", "Suppressed")), "hit", "minus_one", "this unit is suppressed (-1 to hit)")

	# --- this VEHICLE model: Gift of the Iron Wolf ----------------------------
	var gift = actor_unit.get("flags", {}).get(F_GIFTED, null)
	if typeof(gift) == TYPE_DICTIONARY and int(gift.get("player", 0)) == owner:
		m.ignore_hit_penalties = true
		m.ignore_wound_penalties = true
		_src(m, "Gift of the Iron Wolf", "hit", "ignored", "this VEHICLE model's attacks ignore modifiers to hit and wound rolls")

	# Every ability below is held by a SPACE WOLVES component (has() checks
	# is_sw_unit per holder) — skip the work for every other attacker.
	if not Common.group_has_keyword(actor_id, KW_SW) and not Common.has_keyword(actor_unit, KW_SW):
		return m
	var target_ok := target_id != "" and not target_unit.is_empty()
	var target_head := head_id(target_id) if target_ok else ""
	var charged := _group_charged(actor_id) or bool(actor_unit.get("flags", {}).get("charged_this_turn", false))

	# --- "this model" abilities (the model's own unit dict) -------------------
	if is_melee and charged and has(actor_unit, "battle_lust"):
		m.attacks += 2
		_src(m, "Battle-lust", "other", "attacks", "made a charge move this turn: +2 A")
	if target_ok and has(actor_unit, "judgement_of_the_omnissiah") and engaged_with_friendly_sw_vehicle(target_head, owner):
		m.wound_reroll = "failed"
		_src(m, "Judgement of the Omnissiah", "wound", "reroll_failed", "target is engaged with a friendly SPACE WOLVES VEHICLE")
	if target_ok and has(actor_unit, "champion_of_the_kingsguard") and Common.group_has_keyword(target_head, "CHARACTER"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
		_src(m, "Champion of the Kingsguard", "hit", "reroll_ones", "target is a CHARACTER unit")
		_src(m, "Champion of the Kingsguard", "wound", "reroll_ones", "target is a CHARACTER unit")
	if is_melee and has(actor_unit, "violent_fury") and has_two_melee_weapons(actor_unit):
		m.wound_reroll = "failed"
		_src(m, "Violent Fury", "wound", "reroll_failed", "two melee weapons: melee attacks have [TWIN-LINKED]")

	# --- "this unit" abilities (the whole Attached unit) -----------------------
	if is_melee and war_howl_mode(actor_id) == "blood_claws":
		m.strength += 1
		m.sustained = maxi(m.sustained, 1)
		_src(m, "War Howl", "other", "strength", "Ragnar leads Blood Claws: melee +1 S and [SUSTAINED HITS 1]")
	var ulrik := group_holder(actor_id, "slayers_oath")
	var oath := str(Common.unit(ulrik).get("flags", {}).get(F_OATH, "")) if ulrik != "" else ""
	var vs_oath := target_ok and oath != "" and head_id(oath) == target_head
	if vs_oath:
		m.ignore_hit_penalties = true
		_src(m, "Slayer's Oath", "hit", "ignored", "target is the slayer's oath: modifiers to BS/WS and hit rolls ignored")
	if is_melee and group_has(actor_id, "oathbound"):
		m.hit_plus = true
		_src(m, "Oathbound", "hit", "plus_one", "melee attacks +1 to hit")
		if vs_oath:
			m.wound_plus = true
			_src(m, "Oathbound", "wound", "plus_one", "melee attacks vs the slayer's oath +1 to wound")
	if is_melee and _phase() == PH_FIGHT and group_has(actor_id, "cunning_hunters") and Common.group_in_range_of_any_objective(actor_id):
		m.strength += 1
		m.ap += 1
		_src(m, "Cunning Hunters", "other", "strength", "Fight phase, within range of an objective: melee +1 S and +1 AP")
	if is_melee and group_has(actor_id, "death_totem"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		_src(m, "Death Totem", "hit", "reroll_ones", "melee attacks re-roll hit rolls of 1")
	if is_melee and charged and group_has(actor_id, "thunderous_charge"):
		m.strength += 1
		m.damage += 1
		_src(m, "Thunderous Charge", "other", "strength", "made a charge move this turn: melee +1 S and +1 D")
	if is_melee and charged and group_has(actor_id, "litany_of_hate"):
		m.wound_plus = true
		_src(m, "Litany of Hate", "wound", "plus_one", "[LANCE]: made a charge move this turn")
	if group_has(actor_id, "tempered_ferocity"):
		m.sustained = maxi(m.sustained, 1)
		_src(m, "Tempered Ferocity", "other", "sustained_hits", "[SUSTAINED HITS 1]")
		if target_ok and _dist(actor_id, target_head) <= TEMPERED_RANGE_IN + 0.001:
			m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
			_src(m, "Tempered Ferocity", "hit", "reroll_ones", "target within 6\"")
	var ht := group_holder(actor_id, "headhunters")
	if target_ok and ht != "":
		var quarry := str(Common.unit(ht).get("flags", {}).get(F_QUARRY, ""))
		if quarry != "" and head_id(quarry) == target_head:
			m.devastating = true
			m.precision = true
			_src(m, "Headhunters", "other", "devastating_wounds", "target is the quarry: [DEVASTATING WOUNDS] and [PRECISION]")
	if target_ok and group_has(actor_id, "deadly_stalkers") and isolated_from_other_enemies(target_head):
		m.wound_plus = true
		_src(m, "Deadly Stalkers", "wound", "plus_one", "target is more than 6\" from any other enemy unit")
	return m

## War Howl: "blood_claws" while Ragnar leads Blood Claws, "headtakers" while
## he leads Wolf Guard Headtakers, "" otherwise.
static func war_howl_mode(unit_id: String) -> String:
	if unit_id == "":
		return ""
	var head := head_id(unit_id)
	var ragnar := ""
	for gid in group(head):
		if str(gid) != head and has_id(str(gid), "war_howl"):
			ragnar = str(gid)
	if ragnar == "":
		return ""
	var hu := Common.unit(head)
	if Common.has_keyword(hu, "BLOOD CLAWS"):
		return "blood_claws"
	if Common.has_keyword(hu, "WOLF GUARD HEADTAKERS"):
		return "headtakers"
	return ""

## Judgement of the Omnissiah: the (Attached) enemy unit is engaged with a
## friendly SPACE WOLVES VEHICLE unit of `player`.
static func engaged_with_friendly_sw_vehicle(enemy_id: String, player: int) -> bool:
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not Common.has_keyword(u, "VEHICLE") or not is_sw_unit(u) or not Common.is_on_battlefield(u):
			continue
		if Common.group_engaged_with(str(uid), enemy_id):
			return true
	return false

## Deadly Stalkers: the enemy unit is more than 6" from every other unit of its army.
static func isolated_from_other_enemies(enemy_head: String) -> bool:
	var eu := Common.unit(enemy_head)
	var eowner := int(eu.get("owner", 0))
	for oid in Common.friendly_heads(eowner):
		if str(oid) == enemy_head:
			continue
		if _dist(enemy_head, str(oid)) <= STALKERS_RANGE_IN + 0.001:
			return false
	return true

## Violent Fury: the model is equipped with two (or more) melee weapons —
## distinct base weapons (a multi-profile weapon is one). The roster's wargear
## list is the loadout when it has one (the Wulfen Dreadnought that swapped its
## Fenrisian Great Axe for a Blizzard Shield lists only the Great Wolf Claw);
## an empty list is the datasheet's default kit (Great Axe + Great Wolf Claw).
static func has_two_melee_weapons(u: Dictionary) -> bool:
	var meta: Dictionary = u.get("meta", {})
	var melee := {}
	for w in meta.get("weapons", []):
		if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == "melee":
			melee[fold(str(w.get("name", "")).split(" – ")[0].split(" - ")[0])] = true
	var wargear: Array = meta.get("wargear", [])
	if wargear.is_empty():
		return melee.size() >= 2
	var listed := {}
	for item in wargear:
		var s := str(item).strip_edges()
		var re := RegEx.new()
		re.compile("^(\\d+)\\s*x\\s*(.+)$")
		var m := re.search(s)
		if m:
			s = m.get_string(2)
		var f := fold(s)
		if melee.has(f):
			listed[f] = true
	return listed.size() >= 2


# ===========================================================================
# DEFENSIVE / MOVEMENT / MISC passive hooks
# ===========================================================================

## Legendary Tenacity (Bjorn) / Rugged Resilience (Wolf Guard Terminators):
## attacks that target this unit with S > its T have -1 to wound.
static func incoming_wound_penalty_source(target_unit: Dictionary, strength: int, toughness: int) -> String:
	if strength <= toughness or not _edition_11():
		return ""
	var tid := _uid(target_unit)
	if tid == "":
		return ""
	if group_has(tid, "legendary_tenacity"):
		return "Legendary Tenacity"
	if group_has(tid, "rugged_resilience"):
		return "Rugged Resilience"
	return ""

static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	return incoming_wound_penalty_source(target_unit, strength, toughness) != ""

## Advance-and-charge: Berserk Charge (Blood Claws), War Howl (Ragnar leading
## Wolf Guard Headtakers).
static func advance_allows_charge(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty():
		return false
	var uid := _uid(unit)
	if uid == "":
		return false
	return group_has(uid, "berserk_charge") or war_howl_mode(uid) == "headtakers"

## Wind Walker: this unit's ranged attacks have [ASSAULT].
static func ranged_attacks_have_assault(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty():
		return false
	return group_has(_uid(unit), "wind_walker")

## Wind Walker: when selected to make an advance move, the advance roll can be
## changed to a 6 (the engine always does — it can only help).
static func advance_roll_six(unit_id: String) -> bool:
	return _edition_11() and group_has(unit_id, "wind_walker")

## Bestial Fury (Murderfang): re-roll advance rolls and charge rolls.
static func reroll_source(unit: Dictionary) -> String:
	if not _edition_11() or unit.is_empty():
		return ""
	return "Bestial Fury" if group_has(_uid(unit), "bestial_fury") else ""

## Fervour of the Ancients: +1 to advance rolls and charge rolls for friendly
## SPACE WOLVES units within 6" of a Venerable Dreadnought (the Dreadnought
## itself included). {bonus, source}
static func fervour_bonus(unit_id: String) -> Dictionary:
	var none := {"bonus": 0, "source": ""}
	if not _edition_11() or unit_id == "":
		return none
	var u := Common.unit(head_id(unit_id))
	if u.is_empty() or not Common.group_has_keyword(unit_id, KW_SW) or not is_sw_unit(u):
		return none
	var owner := int(u.get("owner", 0))
	for vid in Common.state().get("units", {}):
		var v := Common.unit(str(vid))
		if int(v.get("owner", 0)) != owner or not has(v, "fervour_of_the_ancients") or not Common.is_on_battlefield(v):
			continue
		if head_id(str(vid)) == head_id(unit_id) or _dist(str(vid), unit_id) <= FERVOUR_RANGE_IN + 0.001:
			return {"bonus": 1, "source": "Fervour of the Ancients (%s)" % Common.unit_name(str(vid))}
	return none

## High King of Fenris: the battle round an ingress move of this unit uses.
static func ingress_battle_round(unit: Dictionary, battle_round: int) -> int:
	if not _edition_11() or unit.is_empty():
		return battle_round
	var hk = unit.get("flags", {}).get(F_HIGH_KING, null)
	if typeof(hk) == TYPE_DICTIONARY and int(hk.get("round", -1)) == _round():
		Common.log_info("SWAbilities11e: High King of Fenris — %s ingresses as if it were battle round %d" % [_uid(unit), battle_round + 1])
		return battle_round + 1
	return battle_round

## Reserve units of `player` that High King of Fenris lets arrive in battle round 1.
static func high_king_first_round_units(player: int) -> Array:
	var out: Array = []
	if not _edition_11():
		return out
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or int(u.get("status", 0)) != ST_IN_RESERVES:
			continue
		if ingress_battle_round(u, _round()) > _round():
			out.append(str(uid))
	return out

## Iron Priest: while this model is within 3" of a friendly SPACE WOLVES
## VEHICLE unit, it has Lone Operative.
static func conditional_lone_operative(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or not has(unit, "iron_priest") or not Common.is_on_battlefield(unit):
		return false
	var owner := int(unit.get("owner", 0))
	for vid in Common.state().get("units", {}):
		var v := Common.unit(str(vid))
		if str(vid) == _uid(unit) or int(v.get("owner", 0)) != owner or not Common.has_keyword(v, "VEHICLE") or not is_sw_unit(v):
			continue
		if not Common.is_on_battlefield(v):
			continue
		if Common.unit_distance_inches(unit, v) <= IRON_PRIEST_LO_RANGE_IN + 0.001:
			return true
	return false

## Savage Frenzy (Wulfen): an enemy unit (not MONSTER/VEHICLE) engaged with
## this unit must use the desperate escape mode when it falls back. Returns
## the Wulfen unit id, or "".
static func savage_frenzy_source(unit_id: String, board: Dictionary = {}) -> String:
	if not _edition_11():
		return ""
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	var u: Dictionary = units.get(unit_id, {})
	if u.is_empty() or _is_mv(unit_id):
		return ""
	var owner := int(u.get("owner", 0))
	for oid in units:
		var o: Dictionary = units[oid]
		if int(o.get("owner", 0)) == owner or not has(o, "savage_frenzy") or not Common.is_on_battlefield(o):
			continue
		if Common.group_engaged_with(str(oid), unit_id):
			return str(oid)
	return ""

## -1 to those hazard rolls while that enemy unit is battle-shocked.
static func savage_frenzy_hazard_modifier(unit_id: String, board: Dictionary = {}) -> int:
	if savage_frenzy_source(unit_id, board) == "":
		return 0
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	return -1 if bool(units.get(unit_id, {}).get("flags", {}).get("battle_shocked", false)) else 0

## Storm Caller: "This unit has -3\" detection range until the end of the phase."
static func detection_range_bonus(unit: Dictionary) -> float:
	if unit.is_empty():
		return 0.0
	if bool(unit.get("flags", {}).get(F_STORM_CALLER, false)):
		return STORM_CALLER_DETECTION_IN
	var head := head_id(_uid(unit))
	if head != _uid(unit) and bool(Common.unit(head).get("flags", {}).get(F_STORM_CALLER, false)):
		return STORM_CALLER_DETECTION_IN
	return 0.0

## Murderous Hurricane: "That enemy unit cannot make Snap shooting attacks"
## (until the end of the turn) — FIRE OVERWATCH refuses it. "" when allowed.
static func snap_shooting_block_reason(unit_id: String) -> String:
	if unit_id == "":
		return ""
	var f = _gflag(unit_id, F_NO_SNAP)
	if typeof(f) == TYPE_DICTIONARY:
		return "Murderous Hurricane: this unit cannot make snap-shooting attacks this turn"
	return ""

## Force of Untamed Destruction (Murderfang): "This model cannot be your WARLORD."
static func warlord_block_reason(u: Dictionary) -> String:
	if has(u, "force_of_untamed_destruction"):
		return "%s cannot be your WARLORD (Force of Untamed Destruction)" % str(u.get("meta", {}).get("name", "This model"))
	return ""

## Ancient Tactician (Bjorn, once per turn, per army): a stratagem that
## targets this unit is -1 CP. Returns the discount (0 or 1).
static func stratagem_cp_discount(player: int, target_unit_id: String) -> int:
	if not _edition_11() or target_unit_id == "":
		return 0
	var u := Common.unit(target_unit_id)
	if int(u.get("owner", 0)) != player or not group_has(target_unit_id, "ancient_tactician"):
		return 0
	return 0 if army_used_this_turn(player, "ancient_tactician") else 1

## Records the Ancient Tactician use (once per turn, per army).
static func record_cp_discount(player: int, target_unit_id: String, strat_name: String) -> void:
	Common.apply_diffs([_army_use_diff(player, "ancient_tactician")])
	var msg := "Ancient Tactician: %s on %s is -1 CP (once per turn)" % [strat_name, Common.unit_name(target_unit_id)]
	Common.log_info("SWAbilities11e: " + msg)
	_event_log(player, msg)


# ===========================================================================
# OC — Hunting Hounds (MissionManager.model_oc hook)
# ===========================================================================

## A Hunting Wolf model of a Wolf Guard Headtakers / Wolf Scouts unit (its
## W1 profile — the other models there have W2+), or any Fenrisian Wolf.
static func is_hunting_wolf(unit: Dictionary, model: Dictionary) -> bool:
	if not has(unit, "hunting_hounds"):
		return false
	if Common.has_keyword(unit, "FENRISIAN WOLVES"):
		return true
	return int(model.get("wounds", unit.get("meta", {}).get("stats", {}).get("wounds", 1))) == 1

## Hunting Hounds is active: within 6" of a friendly SPACE WOLVES CHARACTER
## model (excluding WULFEN) and not battle-shocked.
static func hunting_hounds_active(unit: Dictionary) -> bool:
	var uid := _uid(unit)
	if uid == "" or not has(unit, "hunting_hounds") or _group_shocked(uid) or not Common.is_on_battlefield(unit):
		return false
	var owner := int(unit.get("owner", 0))
	for cid in Common.state().get("units", {}):
		var c := Common.unit(str(cid))
		if int(c.get("owner", 0)) != owner or not Common.has_keyword(c, "CHARACTER") or Common.has_keyword(c, "WULFEN"):
			continue
		if not is_sw_unit(c) or not Common.is_on_battlefield(c):
			continue
		if Common.unit_distance_inches(c, Common.group_union(uid)) <= HOUNDS_RANGE_IN + 0.001:
			return true
	return false

## The OC of `model` after Hunting Hounds. A Hunting Wolf's printed OC is 0
## (the roster gives every model of a mixed unit the unit's OC 1); +1 while
## Hunting Hounds is active. Other models are unchanged.
static func model_oc(unit: Dictionary, model: Dictionary, oc: int) -> int:
	if not _edition_11() or unit.is_empty() or not is_hunting_wolf(unit, model):
		return oc
	var base := oc if Common.has_keyword(unit, "FENRISIAN WOLVES") else 0
	return base + (1 if hunting_hounds_active(unit) else 0)


# ===========================================================================
# FIGHT ON DEATH (core 05.04.05) — FightPhase intercept hook
# ===========================================================================

## The Space Wolves Fight On Death rule for model `idx` of `unit_id` that was
## just destroyed: {source, pass} or {} when none applies. Murder-maker (a
## friendly WULFEN model within 6" of Murderfang, 4+), Anvil of Endurance (a
## model of Arjac's unit, 4+), Heroic Last Stand (the Battle Leader, 2+).
static func fod_rule(unit_id: String, idx: int) -> Dictionary:
	if not _edition_11() or _phase() != PH_FIGHT:
		return {}
	var u := Common.unit(unit_id)
	if u.is_empty():
		return {}
	if has(u, "heroic_last_stand"):
		return {"source": "Heroic Last Stand", "pass": 2}
	if group_has(unit_id, "anvil_of_endurance"):
		return {"source": "Anvil of Endurance", "pass": 4}
	var models: Array = u.get("models", [])
	if Common.has_keyword(u, "WULFEN") and is_sw_unit(u) and idx >= 0 and idx < models.size():
		var probe: Dictionary = (models[idx] as Dictionary).duplicate()
		probe["alive"] = true
		var owner := int(u.get("owner", 0))
		for mid in Common.state().get("units", {}):
			var mf := Common.unit(str(mid))
			if str(mid) == unit_id or int(mf.get("owner", 0)) != owner or not has(mf, "murder_maker") or not Common.is_on_battlefield(mf):
				continue
			if probe.get("position", null) != null and Common.unit_distance_inches({"models": [probe]}, mf) <= MURDER_MAKER_RANGE_IN + 0.001:
				return {"source": "Murder-maker", "pass": 4}
	return {}


# ===========================================================================
# ARMY LOAD — wargear stat changes (ArmyListManager hook, idempotent)
# ===========================================================================

## Number of `item` the roster's wargear lists ("4x Storm Shield").
static func wargear_count(unit: Dictionary, item: String) -> int:
	var n := 0
	var want := fold(item)
	for w in unit.get("meta", {}).get("wargear", []):
		var s := str(w).strip_edges()
		var cnt := 1
		var re := RegEx.new()
		re.compile("^(\\d+)\\s*x\\s*(.+)$")
		var m := re.search(s)
		if m:
			cnt = int(m.get_string(1))
			s = m.get_string(2)
		if fold(s) == want:
			n += cnt
	return n

## Storm Shield: "+1 W" (Wolf Guard Terminators, Wolf Guard Battle Leader) or
## "4+ InSv" (Thunderwolf Cavalry, Wolf Guard Headtakers — Headtaker models
## only); Blizzard Shield: 4+ InSv. The roster records counts, not bearers:
## the first N eligible models carry the shields.
static func apply_list_build(unit_id: String, unit: Dictionary) -> void:
	if unit.is_empty() or not Common.has_keyword(unit, KW_SW):
		return
	var meta: Dictionary = unit.get("meta", {})
	var abilities: Array = meta.get("abilities", [])
	var shield_text := ""
	var blizzard := false
	for ab in abilities:
		var f := fold(_ability_name(ab))
		if f == "storm shield":
			shield_text = str(ab.get("description", "")) if ab is Dictionary else ""
		elif f == "blizzard shield":
			blizzard = true
	var models: Array = unit.get("models", [])
	if shield_text != "":
		var plus_w := shield_text.to_lower().contains("+1 w")
		var count := wargear_count(unit, "Storm Shield")
		if count <= 0 and models.size() == 1:
			count = 1
		var given := 0
		for m in models:
			if given >= count:
				break
			if typeof(m) != TYPE_DICTIONARY:
				continue
			# Headtakers: the Hunting Wolves (W1) cannot take the option.
			if Common.has_keyword(unit, "WOLF GUARD HEADTAKERS") and int(m.get("wounds", 1)) <= 1:
				continue
			given += 1
			if bool(m.get(M_SHIELD, false)):
				continue
			m[M_SHIELD] = true
			if plus_w:
				m["wounds"] = int(m.get("wounds", 1)) + 1
				m["current_wounds"] = int(m.get("current_wounds", int(m.get("wounds", 1)) - 1)) + 1
			else:
				var cur := int(m.get("invuln", 0))
				if cur == 0 or cur > 4:
					m["invuln"] = 4
		print("SWAbilities11e: Storm Shield on %s (%s): %d model(s) — %s" % [unit_id, meta.get("name", "?"), given, "+1 W" if plus_w else "4+ invulnerable save"])
	if blizzard:
		for m in models:
			if typeof(m) != TYPE_DICTIONARY or bool(m.get(M_SHIELD, false)):
				continue
			m[M_SHIELD] = true
			var cur := int(m.get("invuln", 0))
			if cur == 0 or cur > 4:
				m["invuln"] = 4
		print("SWAbilities11e: Blizzard Shield on %s (%s): 4+ invulnerable save" % [unit_id, meta.get("name", "?")])


# ===========================================================================
# UNIT SPLITS — Old Greymanes / Let Loose the Wolves (Declare Battle Formations)
# ===========================================================================

## "old_greymanes" | "let_loose_the_wolves" | "" — which split this unit can make now.
static func split_kind(unit_id: String) -> String:
	var u := Common.unit(unit_id)
	if u.is_empty() or not _edition_11() or u.has("split_from_combat_squads"):
		return ""
	if u.get("flags", {}).has(F_SPLIT):
		return ""
	if int(u.get("status", 0)) != ST_UNDEPLOYED:
		return ""
	var alive := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			alive += 1
	if has(u, "old_greymanes") and alive >= 2:
		return "old_greymanes"
	if has(u, "let_loose_the_wolves"):
		var wolves := 0
		for m in u.get("models", []):
			if int(m.get("wounds", 1)) <= 1:
				wolves += 1
		if wolves > 0 and wolves < u.get("models", []).size():
			return "let_loose_the_wolves"
	return ""

## Units `player` can split now (Formations dialog / available actions).
static func splittable_units(player: int) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) == player and split_kind(str(uid)) != "":
			out.append(str(uid))
	return out

## A reason the split is refused, "" when it is legal.
static func split_block_reason(unit_id: String, player: int, leader_attachments: Dictionary = {}) -> String:
	var u := Common.unit(unit_id)
	if u.is_empty():
		return "unit %s not found" % unit_id
	if int(u.get("owner", 0)) != player:
		return "%s is not your unit" % unit_id
	if split_kind(unit_id) == "":
		return "%s cannot be split (no Old Greymanes / Let Loose the Wolves, already split, or not undeployed)" % Common.unit_name(unit_id)
	for cid in leader_attachments:
		if str(leader_attachments[cid]) == unit_id:
			return "Undo the leader attachment to %s before splitting it" % Common.unit_name(unit_id)
	return ""

static func _new_split_id(unit_id: String) -> String:
	var units: Dictionary = Common.state().get("units", {})
	var sid := "%s_SPLIT" % unit_id
	var i := 1
	while units.has(sid):
		sid = "%s_SPLIT%d" % [unit_id, i]
		i += 1
	return sid

## The split as state diffs (applied by FormationsPhase through PhaseManager):
## {diffs, new_id, kind, log} or {error}.
static func split_diffs(unit_id: String) -> Dictionary:
	var kind := split_kind(unit_id)
	if kind == "":
		return {"error": "%s cannot be split" % unit_id}
	var src: Dictionary = Common.unit(unit_id)
	var models: Array = src.get("models", [])
	var keep_idx: Array = []
	var move_idx: Array = []
	if kind == "old_greymanes":
		var n := models.size()
		var keep := int(ceil(float(n) / 2.0))
		for i in range(n):
			if i < keep:
				keep_idx.append(i)
			else:
				move_idx.append(i)
	else:
		for i in range(models.size()):
			if int(models[i].get("wounds", 1)) <= 1:
				move_idx.append(i)
			else:
				keep_idx.append(i)
	var new_id := _new_split_id(unit_id)
	var sibling: Dictionary = src.duplicate(true)
	sibling["id"] = new_id
	sibling["squad_id"] = new_id
	var keep_models: Array = []
	var new_models: Array = []
	for i in keep_idx:
		keep_models.append((models[i] as Dictionary).duplicate(true))
	var k := 0
	for i in move_idx:
		k += 1
		var nm: Dictionary = (models[i] as Dictionary).duplicate(true)
		nm["id"] = "m%d" % k
		new_models.append(nm)
	sibling["models"] = new_models
	if not sibling.has("flags") or typeof(sibling.flags) != TYPE_DICTIONARY:
		sibling["flags"] = {}
	sibling.flags[F_SPLIT] = kind
	sibling["split_sibling_of"] = unit_id
	var base_name := str(src.get("meta", {}).get("name", unit_id))
	var src_meta: Dictionary = src.get("meta", {}).duplicate(true)
	var src_display := ""
	var new_display := ""
	if kind == "old_greymanes":
		src_display = "%s (Pack A)" % base_name
		new_display = "%s (Pack B)" % base_name
	else:
		# Headtakers half: no BEASTS / Teeth and Claws; Hunting Wolves half: the
		# Hunting Wolf profile, BEASTS, Teeth and Claws only.
		src_display = "%s (Headtakers)" % base_name
		new_display = "%s (Hunting Wolves)" % base_name
		src_meta["keywords"] = (src_meta.get("keywords", []) as Array).filter(func(x): return str(x).to_upper() != "BEASTS")
		src_meta["weapons"] = (src_meta.get("weapons", []) as Array).filter(func(w): return typeof(w) != TYPE_DICTIONARY or str(w.get("name", "")).to_lower() != "teeth and claws")
		var wolf_meta: Dictionary = sibling.get("meta", {})
		wolf_meta["keywords"] = (wolf_meta.get("keywords", []) as Array).filter(func(x): return not str(x).to_upper() in ["INFANTRY", "TACTICUS"])
		wolf_meta["weapons"] = (wolf_meta.get("weapons", []) as Array).filter(func(w): return typeof(w) == TYPE_DICTIONARY and str(w.get("name", "")).to_lower() == "teeth and claws")
		var st: Dictionary = (wolf_meta.get("stats", {}) as Dictionary).duplicate()
		for key in HUNTING_WOLF_STATS:
			st[key] = HUNTING_WOLF_STATS[key]
		st.erase("invuln")
		wolf_meta["stats"] = st
		wolf_meta["wargear"] = []
		wolf_meta["abilities"] = (wolf_meta.get("abilities", []) as Array).filter(func(a): return not fold(_ability_name(a)) in ["storm shield", "headhunters", "let loose the wolves"])
		sibling["meta"] = wolf_meta
		for nm in new_models:
			nm.erase("ranged_loadout")
			nm.erase("melee_loadout")
		for km in keep_models:
			km.erase("melee_loadout")
	src_meta["display_name"] = src_display
	(sibling["meta"] as Dictionary)["display_name"] = new_display
	# Points follow the models (the 50% reserves cap reads unit points).
	var total_pts := int(src.get("meta", {}).get("points", 0))
	var keep_pts := int(round(float(total_pts) * float(keep_models.size()) / float(maxi(1, models.size()))))
	src_meta["points"] = keep_pts
	sibling["meta"]["points"] = total_pts - keep_pts
	var diffs: Array = [
		{"op": "set", "path": "units.%s" % new_id, "value": sibling},
		{"op": "set", "path": "units.%s.models" % unit_id, "value": keep_models},
		{"op": "set", "path": "units.%s.meta" % unit_id, "value": src_meta},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_SPLIT], "value": kind},
		{"op": "set", "path": "units.%s.split_sibling_id" % unit_id, "value": new_id},
	]
	var log := "%s: %s split into %s (%d models) and %s (%d models)" % [
		display(kind), base_name, src_display, keep_models.size(), new_display, new_models.size()]
	return {"diffs": diffs, "new_id": new_id, "kind": kind, "log": log}


# ===========================================================================
# EXPIRY / per-phase state — PhaseManager.transition_to_phase (thin hook),
# before the new phase is entered (in place, every peer, like the WP-C7 expiry)
# ===========================================================================

const PHASE_SCOPED := [F_STORM_CALLER, F_HIGH_KING]

static func on_phase_transition(old_phase: int, new_phase: int) -> void:
	if not _edition_11():
		return
	var units: Dictionary = Common.state().get("units", {})
	var active := Common.active_player()
	var cleared: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		var flags = u.get("flags", null)
		if typeof(flags) != TYPE_DICTIONARY or flags.is_empty():
			continue
		for f in PHASE_SCOPED:
			if flags.has(f):
				flags.erase(f)
				cleared.append("%s.%s" % [uid, f])
		if new_phase == PH_COMMAND:
			# Murderous Hurricane: end of the turn.
			if flags.has(F_NO_SNAP):
				flags.erase(F_NO_SNAP)
				cleared.append("%s.%s" % [uid, F_NO_SNAP])
			# Suppressed: until the start of the SW player's next turn.
			var sup = flags.get(F_SUPPRESSED, null)
			if typeof(sup) == TYPE_DICTIONARY and int(sup.get("player", 0)) == active:
				flags.erase(F_SUPPRESSED)
				cleared.append("%s.%s" % [uid, F_SUPPRESSED])
		if new_phase == PH_MOVEMENT:
			# Gift of the Iron Wolf: until the start of your next Movement phase.
			var gift = flags.get(F_GIFTED, null)
			if typeof(gift) == TYPE_DICTIONARY and int(gift.get("player", 0)) == active and str(gift.get("phase_key", "")) != _phase_key_for(PH_MOVEMENT):
				flags.erase(F_GIFTED)
				cleared.append("%s.%s" % [uid, F_GIFTED])
		if old_phase == PH_FIGHT and flags.has("ork11e_fod_source") and is_sw_unit(u) and not flags.has("ork11e_fod_mode"):
			flags.erase("ork11e_fod_source")
	_apply_guile_of_the_wolf()
	if not cleared.is_empty():
		Common.log_info("SWAbilities11e: phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])

static func _phase_key_for(phase: int) -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), phase]

## Guile of the Wolf: "At the start of each phase, the assault doctrine,
## devastator doctrine and tactical doctrine are active for this unit" — the
## SWCommon per-unit additional-doctrines key on every component of Logan's
## (Attached) unit; removed from units Logan no longer belongs to.
static func _apply_guile_of_the_wolf() -> void:
	var units: Dictionary = Common.state().get("units", {})
	var want: Dictionary = {}
	for uid in units:
		var u: Dictionary = units[uid]
		if not has(u, "guile_of_the_wolf") or not Common.is_alive(u):
			continue
		for gid in group(str(uid)):
			want[str(gid)] = true
	for uid in units:
		var u: Dictionary = units[uid]
		if not u.has("flags") or typeof(u.flags) != TYPE_DICTIONARY:
			u["flags"] = {}
		var flags: Dictionary = u.flags
		if want.has(str(uid)):
			flags[F_DOCTRINE_EXTRA] = Common.DOCTRINES.duplicate()
			flags[F_GUILE] = true
		elif bool(flags.get(F_GUILE, false)):
			flags.erase(F_DOCTRINE_EXTRA)
			flags.erase(F_GUILE)


# ===========================================================================
# ACTIVATED ABILITIES — ability cards in the stratagem-window framework
# ===========================================================================

## window id -> slugs offered there.
const WINDOW_ABILITIES := {
	"phase_start": ["slayers_oath", "headhunters", "healing_balms", "high_king_of_fenris",
		"murderous_hurricane", "tempests_wrath", "haywire_mine"],
	"unit_selected_to_move": ["gift_of_the_iron_wolf"],
	"unit_ended_normal_move": ["gift_of_the_iron_wolf", "murderous_hurricane"],
	"unit_ended_advance_move": ["gift_of_the_iron_wolf", "murderous_hurricane"],
	"unit_selected_to_shoot": ["haywire_mine"],
	"enemy_ended_move": ["predatory_instinct"],
	"enemy_targets_unit_shooting": ["storm_caller"],
	"enemy_has_shot": ["bestial_rage"],
	"unit_has_fought": ["hammer_blow"],
}

const EFFECT_TEXT := {
	"slayers_oath": "Select one enemy CHARACTER/MONSTER/VEHICLE unit to be this unit's slayer's oath: this unit's attacks that target it ignore modifiers to BS/WS and hit rolls (Oathbound: melee +1 to hit and wound against it).",
	"headhunters": "Select one enemy unit to be this unit's quarry: this unit's attacks that target it have [DEVASTATING WOUNDS] and [PRECISION]. A new quarry is selected each time it is destroyed.",
	"healing_balms": "This unit heals D3+1 wounds.",
	"high_king_of_fenris": "Once per battle round: select one friendly SPACE WOLVES unit in strategic reserves — when it makes an ingress move this phase, treat the battle round as one higher.",
	"murderous_hurricane": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). Select one visible enemy unit within 12\": it cannot make snap-shooting attacks this turn.",
	"tempests_wrath": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). Select one visible enemy unit within 18\": it is suppressed (-1 to hit) until the start of your next turn.",
	"storm_caller": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). This unit has -3\" detection range until the end of the phase.",
	"haywire_mine": "Once per battle: select one visible enemy unit within 6\" and roll one D6 — on a 2+ it suffers D3 mortal wounds (2D3 if it is a VEHICLE).",
	"gift_of_the_iron_wolf": "Select one friendly SPACE WOLVES VEHICLE model within 3\": it heals D3 wounds and its attacks ignore modifiers to hit and wound rolls until the start of your next Movement phase.",
	"predatory_instinct": "Once per battle round: that enemy unit ended a move within 8\" — this unengaged unit can make a normal move of up to D6\".",
	"bestial_rage": "This unit lost a wound to those attacks — it can make a surge move of up to D6+1\".",
	"hammer_blow": "Select one enemy MONSTER/VEHICLE unit hit by those attacks: it is suppressed (-1 to hit) until the start of your next turn.",
}

## Windows that can host several uses: re-offered after a use (BasePhase's
## generic "ork11e_reoffer" follow-up, faction-neutral).
const REOFFER_WINDOWS := ["phase_start"]
const REOFFER_IF_ABILITY_LEFT := ["unit_selected_to_move", "unit_ended_normal_move", "unit_ended_advance_move", "unit_selected_to_shoot", "enemy_has_shot"]

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

## ScenarioRunner policy (like WP-C7's custodes_abilities): scenarios that do
## not opt in ("sw_abilities": true) never answer these cards, so the runner
## switches the OFFERS off; passive abilities still apply. Never set outside a
## scenario run.
static var offers_suppressed := false

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if not _edition_11() or offers_suppressed or not Common.is_sw_army(player):
		return offers
	for slug in WINDOW_ABILITIES.get(window_id, []):
		var targets: Array = _targets(str(slug), player, window_id, ctx)
		if targets.is_empty():
			continue
		offers.append({
			"stratagem_id": sid_of(str(slug)),
			"name": display(str(slug)),
			"cp_cost": 0,
			"cost_text": "Ability",
			"effect_text": str(EFFECT_TEXT.get(str(slug), "")),
			"type": "Datasheet ability",
			"is_ability": true,
			"targets": targets,
		})
	if not offers.is_empty():
		Common.log_info("SWAbilities11e: window %s P%d — ability offers %s" % [window_id, player, str(offers.map(func(o): return o.name))])
	return offers

## "Start of the phase" window entries for BasePhase.enter_phase (players with
## an offer, active player first; `existing` = entries already queued, so a
## player is never queued twice). Not in networked games (WP-C7 ruling).
static func phase_start_entries(phase: int, existing: Array = []) -> Array:
	var out: Array = []
	if not _edition_11() or not phase in [PH_COMMAND, PH_MOVEMENT, PH_SHOOTING, PH_CHARGE, PH_FIGHT]:
		return out
	var nm = Common.autoload("NetworkManager")
	if nm and nm.has_method("is_networked") and bool(nm.is_networked()):
		return out
	var active := Common.active_player()
	var phase_name: String = {PH_COMMAND: "command", PH_MOVEMENT: "movement", PH_SHOOTING: "shooting", PH_CHARGE: "charge", PH_FIGHT: "fight"}[phase]
	for p in [active, 2 if active == 1 else 1]:
		var dup := false
		for e in existing:
			if int(e.get("player", 0)) == p and str(e.get("window_id", "")) == "phase_start":
				dup = true
		if dup:
			continue
		if not window_offers(p, "phase_start", {"phase": phase_name, "window_id": "phase_start"}).is_empty():
			out.append({"player": p, "window_id": "phase_start", "ctx": {"phase": phase_name}})
	return out

static func _entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	return Common.target_entry(unit_id, extra)

## Components of `player` (alive; on the battlefield unless on_board false) carrying `slug`.
static func _holders(player: int, slug: String, on_board: bool = true) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not has(u, slug) or not Common.is_alive(u):
			continue
		if on_board and not Common.is_on_battlefield(u):
			continue
		out.append(str(uid))
	return out

static func _all_enemy_heads(player: int) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var eu := Common.unit(str(uid))
		var o := int(eu.get("owner", 0))
		if o == player or o == 0 or not Common.is_alive(eu) or head_id(str(uid)) != str(uid):
			continue
		out.append(str(uid))
	return out

## Slayer's Oath needs a choice: start of the first battle round, until made.
static func needs_oath(holder_id: String) -> bool:
	var flags: Dictionary = Common.unit(holder_id).get("flags", {})
	return _round() == 1 and not bool(flags.get(F_OATH_DONE, false))

## Headhunters needs a quarry: battle round 1 until chosen, and after the
## quarry was destroyed.
static func needs_quarry(holder_id: String) -> bool:
	var flags: Dictionary = Common.unit(holder_id).get("flags", {})
	var q := str(flags.get(F_QUARRY, ""))
	if q != "":
		return not Common.is_alive(Common.unit(q))
	return _round() == 1 and not bool(flags.get(F_QUARRY_DONE, false))

static func _healable(unit_id: String) -> bool:
	for gid in group(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or int(m.get("current_wounds", m.get("wounds", 1))) < int(m.get("wounds", 1)):
				return true
	return false

static func _enemies_in_range_visible(from_id: String, player: int, range_in: float, need_visible: bool = true) -> Array:
	var out: Array = []
	for eid in Common.enemy_heads(player):
		if _dist(from_id, str(eid)) > range_in + 0.001:
			continue
		if need_visible and not _visible(from_id, str(eid)):
			continue
		out.append(str(eid))
	return _sorted_by_distance(from_id, out)

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := _phase()
	var own_turn := Common.active_player() == player
	match slug:
		"slayers_oath":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug, false):
				if not needs_oath(hid):
					continue
				var cands: Array = []
				for eid in _all_enemy_heads(player):
					var ok := false
					for kw in OATH_KEYWORDS:
						if Common.group_has_keyword(str(eid), kw):
							ok = true
					if ok:
						cands.append(str(eid))
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
				out.append(_entry(hid, {"label": Common.group_label(hid),
					"secondary": _unit_options(cands, "Slayer's Oath: select one enemy CHARACTER/MONSTER/VEHICLE unit to be %s's slayer's oath" % Common.group_label(hid))}))
		"headhunters":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug, false):
				if not needs_quarry(hid):
					continue
				var cands: Array = _all_enemy_heads(player)
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
				out.append(_entry(hid, {"label": Common.group_label(hid),
					"secondary": _unit_options(cands, "Headhunters: select one enemy unit to be %s's quarry" % Common.group_label(hid))}))
		"healing_balms":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug) or not _healable(hid):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"high_king_of_fenris":
			if window_id != "phase_start" or phase != PH_MOVEMENT or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_round(hid, slug):
					continue
				var res: Array = []
				for uid in Common.state().get("units", {}):
					var u := Common.unit(str(uid))
					if int(u.get("owner", 0)) != player or int(u.get("status", 0)) != ST_IN_RESERVES or not Common.is_alive(u):
						continue
					if head_id(str(uid)) != str(uid) or not Common.group_has_keyword(str(uid), KW_SW):
						continue
					if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
						continue
					res.append(str(uid))
				if res.is_empty():
					continue
				out.append(_entry(hid, {"label": Common.unit_name(hid),
					"secondary": _unit_options(res, "High King of Fenris: select one friendly SPACE WOLVES unit in strategic reserves")}))
		"murderous_hurricane", "tempests_wrath":
			if not own_turn:
				return out
			var want_phase := PH_MOVEMENT if slug == "murderous_hurricane" else PH_SHOOTING
			if phase != want_phase:
				return out
			if window_id != "phase_start":
				# unit_ended_*_move: only the moving unit's own psyker.
				var mover := str(ctx.get("unit_id", ""))
				if mover == "" or group_holder(mover, slug) == "":
					return out
			var range_in := HURRICANE_RANGE_IN if slug == "murderous_hurricane" else TEMPEST_RANGE_IN
			for hid in _holders(player, slug):
				if window_id != "phase_start" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if not _psychic_ready(hid, slug):
					continue
				var cands := _enemies_in_range_visible(hid, player, range_in)
				if cands.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid),
					"secondary": _unit_options(cands, "%s: select one visible enemy unit within %d\"" % [display(slug), int(range_in)])}))
		"storm_caller":
			if window_id != "enemy_targets_unit_shooting" or own_turn:
				return out
			var targeted: Array = ctx.get("target_unit_ids", [])
			for hid in _holders(player, slug):
				var hit_me := false
				for gid in group(hid):
					if str(gid) in targeted or head_id(str(gid)) in targeted:
						hit_me = true
				if not hit_me or not _psychic_ready(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"haywire_mine":
			if not own_turn or phase != PH_SHOOTING:
				return out
			if window_id == "unit_selected_to_shoot":
				var shooter := str(ctx.get("unit_id", ""))
				if shooter == "" or group_holder(shooter, slug) == "":
					return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if used_in_battle(hid, slug):
					continue
				var cands := _enemies_in_range_visible(hid, player, HAYWIRE_RANGE_IN)
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return int(Common.group_has_keyword(str(a), "VEHICLE")) > int(Common.group_has_keyword(str(b), "VEHICLE")))
				out.append(_entry(head_id(hid), {"holder": hid,
					"secondary": _unit_options(cands, "Haywire Mine: select one visible enemy unit within 6\" (2D3 mortal wounds vs a VEHICLE)")}))
		"gift_of_the_iron_wolf":
			if not own_turn or phase != PH_MOVEMENT:
				return out
			var mover := str(ctx.get("unit_id", ""))
			var hid := group_holder(mover, slug) if mover != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var cands: Array = []
			for vid in Common.state().get("units", {}):
				var v := Common.unit(str(vid))
				if int(v.get("owner", 0)) != player or not Common.has_keyword(v, "VEHICLE") or not is_sw_unit(v) or not Common.is_on_battlefield(v):
					continue
				if str(v.get("flags", {}).get(F_GIFT_PHASE, "")) == _phase_key():
					continue
				if Common.unit_distance_inches(Common.unit(hid), v) <= GIFT_RANGE_IN + 0.001:
					cands.append(str(vid))
			if cands.is_empty():
				return out
			out.append(_entry(head_id(mover), {"holder": hid,
				"secondary": _unit_options(cands, "Gift of the Iron Wolf: select one friendly SPACE WOLVES VEHICLE model within 3\" of %s" % Common.unit_name(hid))}))
		"predatory_instinct":
			if window_id != "enemy_ended_move" or own_turn or phase != PH_MOVEMENT:
				return out
			var mover := str(ctx.get("enemy_unit_id", ""))
			if mover == "":
				return out
			for hid in _holders(player, slug):
				if used_this_round(hid, slug) or _engaged(hid):
					continue
				if _dist(hid, mover) > PREDATORY_RANGE_IN + 0.001:
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"bestial_rage":
			if window_id != "enemy_has_shot" or own_turn or phase != PH_SHOOTING:
				return out
			var wounded: Array = ctx.get("wounded_unit_ids", [])
			for hid in _holders(player, slug):
				var lost := false
				for gid in group(hid):
					if str(gid) in wounded:
						lost = true
				if not lost or _engaged(hid) or _group_shocked(hid) or used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"hammer_blow":
			if window_id != "unit_has_fought" or phase != PH_FIGHT:
				return out
			var fighter := str(ctx.get("unit_id", ""))
			var hid := group_holder(fighter, slug) if fighter != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var cands: Array = []
			for tid in ctx.get("hit_unit_ids", []):
				var h := head_id(str(tid))
				var hu := Common.unit(h)
				if int(hu.get("owner", 0)) == player or not Common.is_alive(hu) or h in cands or not _is_mv(h):
					continue
				cands.append(h)
			if cands.is_empty():
				return out
			cands.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
			out.append(_entry(head_id(fighter), {"holder": hid,
				"secondary": _unit_options(cands, "Hammer Blow: select one enemy MONSTER/VEHICLE unit hit by those attacks — it is suppressed")}))
	return out

## A rough threat score for ordering pickers best-first (the AI takes the first).
static func _threat(unit_id: String) -> float:
	var s := 0.0
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		s += float(u.get("meta", {}).get("points", 0))
		if Common.has_keyword(u, "CHARACTER"):
			s += 50.0
	return s

## Hammer Blow candidates for the unit_has_fought window (FightPhase hook): the
## window entry when the fighter has Hammer Blow and hit a MONSTER/VEHICLE.
static func unit_has_fought_entries(unit_id: String, hit_unit_ids: Array) -> Array:
	if not _edition_11() or offers_suppressed or unit_id == "" or group_holder(unit_id, "hammer_blow") == "":
		return []
	Common.log_info("SWAbilities11e: Hammer Blow — %s has fought; enemy units hit by those attacks: %s" % [unit_id, str(hit_unit_ids)])
	var owner := int(Common.unit(unit_id).get("owner", 0))
	var ctx := {"phase": "fight", "unit_id": unit_id, "hit_unit_ids": hit_unit_ids.duplicate()}
	var c := ctx.duplicate(true)
	c["window_id"] = "unit_has_fought"
	if window_offers(owner, "unit_has_fought", c).is_empty():
		return []
	return [{"player": owner, "window_id": "unit_has_fought", "ctx": ctx}]

## Enemy units a fight activation's melee attacks hit: the targets of the
## confirmed assignments whose weapon scored a hit in the activation's dice
## (every target when the result carries no hit dice).
static func melee_hit_unit_ids(assignments: Array, dice: Array) -> Array:
	var hit_weapons := {}
	var any_hit_dice := false
	for d in dice:
		if typeof(d) != TYPE_DICTIONARY or str(d.get("context", "")) != "hit_roll_melee":
			continue
		any_hit_dice = true
		if int(d.get("successes", 0)) > 0:
			hit_weapons[str(d.get("weapon", ""))] = true
	var out: Array = []
	for a in assignments:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var tid := str(a.get("target", a.get("target_unit_id", "")))
		if tid == "" or tid in out:
			continue
		if any_hit_dice and not hit_weapons.has(str(a.get("weapon", ""))) and not hit_weapons.has(""):
			continue
		out.append(tid)
	return out

## StratagemManager.can_use_stratagem for an ability card (the reactive
## shooting dialog validates USE_REACTIVE_STRATAGEM through it).
static func can_use(player: int, sid: String, target_unit_id: String, context: Dictionary) -> Dictionary:
	var slug := slug_of(sid)
	for t in _targets(slug, player, str(context.get("window_id", "")), context):
		if str(t.get("unit_id", "")) == target_unit_id:
			return {"can_use": true, "reason": ""}
	return {"can_use": false, "reason": "%s cannot be used on %s now" % [display(slug), Common.unit_name(target_unit_id)]}

## USE_WINDOW_STRATAGEM on an ability (routed by StratagemManager.use_stratagem).
static func use(player: int, sid: String, target_unit_id: String, context: Dictionary) -> Dictionary:
	var slug := slug_of(sid)
	var window_id := str(context.get("window_id", ""))
	var entry: Dictionary = {}
	for t in _targets(slug, player, window_id, context):
		if str(t.get("unit_id", "")) == target_unit_id:
			entry = t
	if entry.is_empty():
		return {"success": false, "error": "%s cannot be used on %s now" % [display(slug), Common.unit_name(target_unit_id)], "diffs": []}
	var secondary := str(context.get("secondary_id", ""))
	if entry.has("secondary"):
		var ok := false
		for o in entry.secondary.get("options", []):
			if str(o.get("id", "")) == secondary:
				ok = true
		if not ok:
			return {"success": false, "error": "%s needs a valid target unit" % display(slug), "diffs": []}
	var holder := str(entry.get("holder", target_unit_id))
	var res := _apply(slug, player, target_unit_id, holder, secondary, context)
	var diffs: Array = res.get("diffs", [])
	var gs = Common.game_state()
	if not diffs.is_empty() and gs:
		gs.apply_state_changes(diffs)
	var log_text := str(res.get("log", ""))
	if log_text != "":
		Common.log_info("SWAbilities11e: %s" % log_text)
		_event_log(player, log_text)
	var out := {"success": true, "diffs": diffs, "stratagem_name": display(slug), "cp_cost": 0}
	var followup: Dictionary = res.get("followup", {})
	if followup.is_empty() and (window_id in REOFFER_WINDOWS or window_id in REOFFER_IF_ABILITY_LEFT):
		var wctx: Dictionary = context.duplicate(true)
		for k in ["secondary_id", "variant_id", "variant_label"]:
			wctx.erase(k)
		var left: Array = window_offers(player, window_id, wctx)
		var sm = Common.stratagem_manager()
		if window_id in REOFFER_WINDOWS and left.is_empty() and sm and sm.has_method("get_all_window_offers"):
			left = sm.get_all_window_offers(player, window_id, wctx)
		if not left.is_empty():
			followup = {"type": "ork11e_reoffer", "player": player, "window_id": window_id, "ctx": wctx}
	if not followup.is_empty():
		out["followup"] = followup
	return out

## Mortal wounds (06.02): the bodyguard first, spilling to the Attached
## unit's characters; FNP via RulesEngine.apply_mortal_wounds.
static func _mortal_wounds(unit_id: String, mw: int) -> Dictionary:
	var out := {"diffs": [], "casualties": 0}
	var re = Common.rules()
	var gs = Common.game_state()
	if re == null or gs == null or mw <= 0:
		return out
	var remaining := mw
	var first := true
	for gid in group(head_id(unit_id)):
		if remaining <= 0:
			break
		var u := Common.unit(str(gid))
		if u.is_empty() or not Common.is_alive(u):
			continue
		var pool := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				pool += int(m.get("current_wounds", m.get("wounds", 1)))
		var res: Dictionary = re.apply_mortal_wounds(str(gid), remaining, gs.create_snapshot(), re.make_rng() if first else null)
		first = false
		out.diffs.append_array(res.get("diffs", []))
		out.casualties += int(res.get("casualties", 0))
		var applied := int(res.get("wounds_applied", 0))
		remaining = maxi(0, applied - pool)
	return out

## Healing (the engine's heal convention: a wounded model first; with none
## wounded, a destroyed model returns with 1 wound) over the Attached unit.
static func heal_diffs(unit_id: String, amount: int) -> Dictionary:
	var diffs: Array = []
	var healed := 0
	var revived := 0
	var sim: Dictionary = {}
	var comps := group(unit_id)
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

static func _apply(slug: String, player: int, uid: String, holder: String, secondary: String, _ctx: Dictionary) -> Dictionary:
	var name := Common.group_label(uid)
	match slug:
		"slayers_oath":
			var diffs: Array = Common.set_flag_diffs([holder], F_OATH, secondary)
			diffs.append_array(Common.set_flag_diffs([holder], F_OATH_DONE, true))
			return {"diffs": diffs, "log": "Slayer's Oath: %s is %s's slayer's oath — attacks against it ignore modifiers to BS/WS and hit rolls (Oathbound: melee +1 to hit and wound)" % [Common.group_label(secondary), Common.unit_name(holder)]}
		"headhunters":
			var diffs: Array = Common.set_flag_diffs([holder], F_QUARRY, secondary)
			diffs.append_array(Common.set_flag_diffs([holder], F_QUARRY_DONE, true))
			return {"diffs": diffs, "log": "Headhunters: %s is %s's quarry — their attacks against it have [DEVASTATING WOUNDS] and [PRECISION]" % [Common.group_label(secondary), Common.group_label(holder)]}
		"healing_balms":
			var d3 := int(Common.roll_dice(1, 3)[0])
			var amount := d3 + 1
			var h := heal_diffs(uid, amount)
			var diffs: Array = h.diffs
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Healing Balms: %s heals D3+1 = %d+1 = %d wound(s) (%d wound(s) restored, %d model(s) returned)" % [name, d3, amount, int(h.healed), int(h.revived)]}
		"high_king_of_fenris":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_HIGH_KING, {"round": _round(), "player": player})
			diffs.append(_round_use_diff(holder, slug))
			return {"diffs": diffs, "log": "High King of Fenris: when %s makes an ingress move this phase, the battle round counts as %d" % [Common.group_label(secondary), _round() + 1]}
		"murderous_hurricane":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			diffs.append_array(Common.set_flag_diffs(group(secondary), F_NO_SNAP, {"player": player}))
			return {"diffs": diffs, "log": "Murderous Hurricane (%s): %s — %s cannot make snap-shooting attacks this turn" % [Common.unit_name(holder), pr.note, Common.group_label(secondary)]}
		"tempests_wrath":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			diffs.append_array(Common.set_flag_diffs(group(secondary), F_SUPPRESSED, {"player": player, "source": "Tempest's Wrath"}))
			return {"diffs": diffs, "log": "Tempest's Wrath (%s): %s — %s is suppressed (-1 to hit) until the start of your next turn" % [Common.unit_name(holder), pr.note, Common.group_label(secondary)]}
		"storm_caller":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			diffs.append_array(Common.set_flag_diffs(group(holder), F_STORM_CALLER, true))
			return {"diffs": diffs, "log": "Storm Caller (%s): %s — %s has -3\" detection range until the end of the phase" % [Common.unit_name(holder), pr.note, name]}
		"haywire_mine":
			_mark_battle_use(holder, slug)
			var roll := int(Common.roll_dice(1)[0])
			if roll < 2:
				return {"diffs": [], "log": "Haywire Mine: %s rolls %d — no effect on %s" % [name, roll, Common.group_label(secondary)]}
			var vehicle := Common.group_has_keyword(secondary, "VEHICLE")
			var dice: Array = Common.roll_dice(2 if vehicle else 1, 3)
			var mw := 0
			for d in dice:
				mw += int(d)
			var res := _mortal_wounds(secondary, mw)
			return {"diffs": res.diffs, "log": "Haywire Mine: %s rolls %d — %s suffers %s = %d mortal wound(s) (%d model(s) destroyed)" % [
				name, roll, Common.group_label(secondary), ("2D3 %s" % str(dice)) if vehicle else ("D3 %s" % str(dice)), mw, int(res.casualties)]}
		"gift_of_the_iron_wolf":
			var d3 := int(Common.roll_dice(1, 3)[0])
			var h := heal_diffs(secondary, d3)
			var diffs: Array = h.diffs
			diffs.append(_phase_use_diff(holder, slug))
			diffs.append_array(Common.set_flag_diffs([secondary], F_GIFT_PHASE, _phase_key()))
			diffs.append_array(Common.set_flag_diffs([secondary], F_GIFTED, {"player": player, "phase_key": _phase_key()}))
			return {"diffs": diffs, "log": "Gift of the Iron Wolf (%s): %s heals D3 = %d (%d wound(s) restored); its attacks ignore modifiers to hit and wound rolls until the start of your next Movement phase" % [
				Common.unit_name(holder), Common.unit_name(secondary), d3, int(h.healed)]}
		"predatory_instinct":
			var r := int(Common.roll_dice(1)[0])
			return {"diffs": [_round_use_diff(holder, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(r), "source": "Predatory Instinct"},
				"log": "Predatory Instinct: %s rolls D6 = %d — normal move of up to %d\"" % [name, r, r]}
		"bestial_rage":
			return {"diffs": [_phase_use_diff(holder, slug)],
				"followup": {"type": "surge_move", "unit_id": head_id(uid), "source": "Bestial Rage", "roll_bonus": 1},
				"log": "Bestial Rage: %s makes a surge move of up to D6+1\"" % name}
		"hammer_blow":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_SUPPRESSED, {"player": player, "source": "Hammer Blow"})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Hammer Blow: %s is suppressed (-1 to hit) until the start of your next turn" % Common.group_label(secondary)}
	return {"diffs": []}


# ===========================================================================
# AI — synchronous scores (AIDecisionMaker.decide_window_stratagem, threshold
# 1.0 for abilities): the window never waits on the AI.
# ===========================================================================

static func ai_score(player: int, sid: String, target_unit_id: String, _window_id: String, _ctx: Dictionary) -> float:
	var slug := slug_of(sid)
	match slug:
		"slayers_oath", "headhunters", "healing_balms", "haywire_mine", "hammer_blow", "tempests_wrath":
			return 3.0
		"gift_of_the_iron_wolf":
			return 2.0
		"murderous_hurricane":
			# Only worth a psychic roll when the target could fire overwatch at us.
			return 1.5
		"storm_caller":
			return 0.0  # -3" detection range rarely changes a later target — not modelled
		"high_king_of_fenris", "predatory_instinct", "bestial_rage":
			return 0.0  # repositioning is a plan-level decision
	return 0.0
