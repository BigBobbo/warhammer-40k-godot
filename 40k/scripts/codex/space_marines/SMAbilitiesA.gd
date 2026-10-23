extends RefCounted

## SMAbilitiesA — Codex: Space Marines (11e), DATASHEET and WARGEAR abilities
## of the generic Space Marine datasheets of work package M4a (29 datasheets:
## Apothecary Biologis, Land Raider, Land Raider Crusader, Bladeguard Veteran
## Squad, Captain, Lieutenant with Combi-weapon, Librarian in Terminator Armour,
## Captain with Jump Pack, Firestrike Servo-turrets, Drop Pod, Ballistus
## Dreadnought, Chaplain on Bike, Chaplain with Jump Pack, Storm Speeder
## Hammerstrike, Chaplain in Terminator Armour, Terminator Assault Squad,
## Librarian in Phobos Armour, Storm Speeder Hailstrike, Inceptor Squad,
## Infernus Squad, Iron Father Feirros, Infiltrator Squad, Captain in Terminator
## Armour, Brutalis Dreadnought, Roboute Guilliman, Thunderhawk Gunship,
## Techmarine, Vanguard Veteran Squad with Jump Packs, Invictor Tactical Warsuit).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md, PLAN_SPACE_MARINES.md.
## Printed text: .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md.
## Audit + rulings: space_marines_abilities_audit_a.md, RULINGS.md (## WP-M4a).
##
## Everything is static. Engine files only reach this module through thin,
## commented hooks ("WP-M4a" one-liners):
##   RulesEngine        ork11e_ab_mods aggregator (merge_attack_mods), range
##                      bonus, S > T wound penalty, conditional FNP, Lone
##                      Operative, re-roll-one (Power of the Machine Spirit),
##                      snap-shooting 4+ (Sentinel Protocols)
##   EffectPrimitives   charge re-roll (Unstoppable Valour)
##   MovementPhase      advance roll +1 (Angel's Wrath), first-round ingress +
##                      set-up disembark (Drop Pod Assault), assault-disembark
##                      candidates (Aerial Assault), Teleport Homer set-up, the
##                      unit_ended_*_move ctx (Thunderhawk Cluster Bombs path)
##   ChargePhase        charge roll +1 (Angel's Wrath)
##   DisembarkMove      assault-disembark mode (Assault Ramp / Aerial Assault / Drop Pod)
##   TransportManager   embark block (Deployment Complete)
##   FormationsPhase    Drop Pods start in strategic reserves
##   TerrainManager     detection range (Priority Target Identified, Omni-scramblers)
##   GameState / AI     10e Omni-scramblers 12" denial retired for SM armies
##   StratagemManager   ability cards (window_offers / can_use / use), stratagem
##                      overrides (Brutalis Charge, Sentinel Protocols),
##                      Rapid Ingress -1 CP (Teleport Homer), Fire Overwatch eligibility
##   ArmyListManager    list build (Relic Shield, Storm Shield, Combat Shield,
##                      default-kit wargear for single-model datasheets)
##   PhaseManager       on_phase_transition (expiry, Codex Adept)
##   BasePhase          phase_start_entries
##   AIDecisionMaker    ai_score for the cards (synchronous)
##   ScenarioRunner     "sm_abilities_a" opt-in policy
##
## Gate: the unit lists the ability, its datasheet is one of the 29 above, and
## it belongs to a Space Marine army (SWCommon.is_sm_army, 11e) — SM-D1.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const PX_PER_INCH := 40.0

# GameState.Phase mirror.
const PH_FORMATIONS := 0
const PH_DEPLOYMENT := 1
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const ST_UNDEPLOYED := 0
const ST_IN_RESERVES := 7

const KW_AA := "ADEPTUS ASTARTES"

## The M4a datasheets (folded names, see fold()).
const DATASHEETS := [
	"apothecary biologis", "land raider", "land raider crusader", "bladeguard veteran squad",
	"captain", "lieutenant with combi weapon", "librarian in terminator armour",
	"captain with jump pack", "firestrike servo turrets", "drop pod", "ballistus dreadnought",
	"chaplain on bike", "chaplain with jump pack", "storm speeder hammerstrike",
	"chaplain in terminator armour", "terminator assault squad", "librarian in phobos armour",
	"storm speeder hailstrike", "inceptor squad", "infernus squad", "iron father feirros",
	"infiltrator squad", "captain in terminator armour", "brutalis dreadnought",
	"roboute guilliman", "thunderhawk gunship", "techmarine",
	"vanguard veteran squad with jump packs", "invictor tactical warsuit",
]

## slug -> FOLDED printed ability name.
const NAMES := {
	"vivispectral_analysis_targeting": "vivispectral analysis targeting",
	"assault_ramp": "assault ramp",
	"power_of_the_machine_spirit": "power of the machine spirit",
	"fury_of_the_machine_spirit": "fury of the machine spirit",
	"bladeguard": "bladeguard",
	"strategic_acumen": "strategic acumen",
	"finest_hour": "finest hour",
	"relic_shield": "relic shield",
	"priority_target_identified": "priority target identified",
	"evade_and_survive": "evade and survive",
	"librarian": "librarian",
	"psychic_hood": "psychic hood",
	"might_of_heroes": "might of heroes",
	"thunderous_force": "thunderous force",
	"angels_wrath": "angels wrath",
	"sentinel_protocols": "sentinel protocols",
	"drop_pod_assault": "drop pod assault",
	"deployment_complete": "deployment complete",
	"ballistus_strike": "ballistus strike",
	"litany_of_hate": "litany of hate",
	"catechism_of_fire": "catechism of fire",
	"exhortation_of_rage": "exhortation of rage",
	"hammerstrike": "hammerstrike",
	"zealous_fortitude": "zealous fortitude",
	"teleport_homer": "teleport homer",
	"terminatus_assault": "terminatus assault",
	"storm_shield": "storm shield",
	"shrouding": "shrouding",
	"soul_sight": "soul sight",
	"hailstrike": "hailstrike",
	"meteoric_descent": "meteoric descent",
	"parabolic_jetleap": "parabolic jetleap",
	"driven_from_cover": "driven from cover",
	"master_of_the_forge": "master of the forge",
	"rites_of_tempering": "rites of tempering",
	"iron_father": "iron father",
	"omni_scramblers": "omni scramblers",
	"helix_gauntlet": "helix gauntlet",
	"unstoppable_valour": "unstoppable valour",
	"brutalis_charge": "brutalis charge",
	"codex_adept": "codex adept",
	"primarch_of_the_xiii": "primarch of the xiii",
	"author_of_the_codex": "author of the codex",
	"leader_of_astartes": "leader of astartes",
	"aerial_assault": "aerial assault",
	"thunderhawk_cluster_bombs": "thunderhawk cluster bombs",
	"techmarine": "techmarine",
	"blessings_of_the_omnissiah": "blessings of the omnissiah",
	"vanguard_assault": "vanguard assault",
	"combat_shield": "combat shield",
	"forward_assault_warsuit": "forward assault warsuit",
}

## slug -> printed name (cards, logs, the UnitAbilityManager once-per-battle key).
const DISPLAY := {
	"vivispectral_analysis_targeting": "Vivispectral Analysis Targeting", "assault_ramp": "Assault Ramp",
	"power_of_the_machine_spirit": "Power of the Machine Spirit", "fury_of_the_machine_spirit": "Fury of the Machine Spirit",
	"bladeguard": "Bladeguard", "strategic_acumen": "Strategic Acumen", "finest_hour": "Finest Hour",
	"relic_shield": "Relic Shield", "priority_target_identified": "Priority Target Identified",
	"evade_and_survive": "Evade and Survive", "librarian": "Librarian", "psychic_hood": "Psychic Hood",
	"might_of_heroes": "Might of Heroes", "thunderous_force": "Thunderous Force", "angels_wrath": "Angel's Wrath",
	"sentinel_protocols": "Sentinel Protocols", "drop_pod_assault": "Drop Pod Assault",
	"deployment_complete": "Deployment Complete", "ballistus_strike": "Ballistus Strike",
	"litany_of_hate": "Litany of Hate", "catechism_of_fire": "Catechism of Fire",
	"exhortation_of_rage": "Exhortation of Rage", "hammerstrike": "Hammerstrike",
	"zealous_fortitude": "Zealous Fortitude", "teleport_homer": "Teleport Homer",
	"terminatus_assault": "Terminatus Assault", "storm_shield": "Storm Shield", "shrouding": "Shrouding",
	"soul_sight": "Soul Sight", "hailstrike": "Hailstrike", "meteoric_descent": "Meteoric Descent",
	"parabolic_jetleap": "Parabolic Jetleap", "driven_from_cover": "Driven from Cover",
	"master_of_the_forge": "Master of the Forge", "rites_of_tempering": "Rites of Tempering",
	"iron_father": "Iron Father", "omni_scramblers": "Omni-scramblers", "helix_gauntlet": "Helix Gauntlet",
	"unstoppable_valour": "Unstoppable Valour", "brutalis_charge": "Brutalis Charge",
	"codex_adept": "Codex Adept", "primarch_of_the_xiii": "Primarch of the XIII",
	"author_of_the_codex": "Author of the Codex", "leader_of_astartes": "Leader of Astartes",
	"aerial_assault": "Aerial Assault", "thunderhawk_cluster_bombs": "Thunderhawk Cluster Bombs",
	"techmarine": "Techmarine", "blessings_of_the_omnissiah": "Blessings of the Omnissiah",
	"vanguard_assault": "Vanguard Assault", "combat_shield": "Combat Shield",
	"forward_assault_warsuit": "Forward Assault Warsuit",
}

# --- flags (sm11e_aba_*; never the effect_ prefix ShootingPhase wipes) --------
const F_PHASE_USES := "sm11e_aba_phase_uses"       # {slug: phase_key}: once-per-phase per-unit uses
const F_TURN_USES := "sm11e_aba_turn_uses"         # {slug: turn_key}: once-per-turn per-unit uses
const F_BLADEGUARD := "sm11e_aba_bladeguard"       # {mode: attack|defend, phase_key}
const F_FINEST_HOUR := "sm11e_aba_finest_hour"     # phase_key: this model's melee +3 A, [DEVASTATING WOUNDS]
const F_MIGHT := "sm11e_aba_might_of_heroes"       # phase_key: melee +2 S
const F_THUNDEROUS := "sm11e_aba_thunderous_force" # phase_key: ranged +6" R
const F_SHROUDED := "sm11e_aba_shrouding"          # phase_key: attacks that target this unit -1 to hit
const F_SOUL_SIGHT := "sm11e_aba_soul_sight"       # phase_key: ranged attacks that target this unit [IGNORES COVER]
const F_DRIVEN := "sm11e_aba_driven"               # {player, phase_key, source}: that player's AA ranged attacks vs this unit [IGNORES COVER]
const F_CATECHISM := "sm11e_aba_catechism"         # {target, phase_key}: ranged vs target [DEVASTATING WOUNDS]
const F_DETECTED := "sm11e_aba_detected"           # {player, phase_key}: Omni-scramblers +3" detection range
const F_BLESSED := "sm11e_aba_blessed"             # {player, phase_key, bs, source}: VEHICLE ignores hit/wound (+BS) modifiers until player's next Movement phase
const F_BLESS_PHASE := "sm11e_aba_bless_phase"     # phase_key: this VEHICLE was selected for a blessing this phase
const F_MARK := "sm11e_aba_mark"                   # Invictor: the head id of its mark
const F_MARK_DONE := "sm11e_aba_mark_round1"       # true once the round-1 mark choice was made / declined
const F_ACUMEN := "sm11e_aba_acumen"               # {player}: sw11e_doctrine on this unit was written by Strategic Acumen
const F_AUTHOR := "sm11e_aba_author"               # {doctrine, player}: Author of the Codex additional doctrine
const F_EXTRA_MINE := "sm11e_aba_extra"            # [doctrine]: what this module added to sw11e_doctrine_extra
const F_ASSAULT_RAMP := "sm11e_aba_assault_ramp"   # on a TRANSPORT: its disembarks this follow-up are assault disembark moves
const F_AERIAL := "sm11e_aba_aerial"               # on a TRANSPORT: only Deep Strike units may assault disembark (Aerial Assault)
const F_DROP_POD_LANDED := "sm11e_aba_drop_pod_landed"  # on a Drop Pod: set up and emptied — no embarking (Deployment Complete)
const F_DROP_POD_DISEMBARK := "sm11e_aba_drop_pod_disembark" # on a unit: disembarking from a Drop Pod — set up > 8" from enemies
const F_SENTINEL := "sm11e_aba_sentinel"           # phase_key: snap-shooting attacks hit on unmodified 4+
const F_HOMER := "sm11e_aba_homer"                 # {x, y, player} (px): this unit's Teleport Homer token
const F_HOMER_DONE := "sm11e_aba_homer_decided"    # true once the start-of-battle token decision was made
const F_HOMER_ACTIVE := "sm11e_aba_homer_active"   # phase_key: Rapid Ingress uses the token (-1 CP, set up within 3")
## Doctrine-state keys owned by SWCommon / SWArmyRules11e.
const F_UNIT_DOCTRINE := "sw11e_doctrine"
const F_UNIT_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"
const F_DOCTRINE_EXTRA := "sw11e_doctrine_extra"
## Librarius budget keys — the SAME keys SWAbilities11e writes (one budget per PSYKER unit).
const F_PSY_ROUND := "sw11e_psy_round"
const F_PSY_USED := "sw11e_psy_used"
const F_PSY_PHASE := "sw11e_psy_phase"
const F_PSY_PHASE_NAMES := "sw11e_psy_phase_names"
## Model list-build marker (shared with SWAbilities11e: one shield application per model).
const M_SHIELD := "sw11e_shield"
const M_RELIC := "sm11e_relic_shield"
const M_COMBAT_SHIELD := "sm11e_combat_shield"
## Army ledger on state.players[p]: {key: value}.
const ARMY_STATE := "sm11e_aba_army"
## Faction state: the terrain feature identified by Priority Target Identified.
const FK_PRIORITY := "sm11e_aba_priority_target"   # {feature_id, turn_key, player}

const SID_PREFIX := "sm11e_ab_a_"

const FURY_RANGE_IN := 12.0
const BALLISTUS_RANGE_IN := 24.0
const THUNDEROUS_RANGE_IN := 6.0
const EVADE_RANGE_IN := 8.0
const OMNI_RANGE_IN := 18.0
const DETECTION_BONUS_IN := 3.0
const BLESS_RANGE_IN := 3.0
const LONE_OP_RANGE_IN := 3.0
const PRIMARCH_RANGE_IN := 6.0
const AUTHOR_RANGE_IN := 12.0
const HOMER_SETUP_IN := 3.0
const HOMER_ENEMY_IN := 1.0
const DROP_POD_ENEMY_IN := 8.0

## Librarius: the psyker level of "Librarian" (the army data drops the printed
## "(psyker level 1)" suffix).
const PSYKER_LEVEL_ABILITIES := {"librarian": 1}
const PSYCHIC_LEVELS := {"might_of_heroes": 1, "thunderous_force": 1, "shrouding": 1, "soul_sight": 1}
const PSYCHIC_SLUGS := ["might_of_heroes", "thunderous_force", "shrouding", "soul_sight"]

## Default kit (the printed "Loadout") of the single-model datasheets whose
## weapon list is the option MENU — stamped as roster wargear when the roster
## lists none, so the engine fires the default kit, not every option.
const DEFAULT_KIT := {
	"land raider": ["2x Godhammer Lascannon", "1x Twin Heavy Bolter", "1x Armoured Tracks"],
	"land raider crusader": ["2x Hurricane Bolter", "1x Twin Assault Cannon", "1x Armoured Tracks"],
	"captain": ["1x Heavy Bolt Pistol", "1x Master-crafted Bolter", "1x Master-crafted Power Weapon"],
	"captain with jump pack": ["1x Heavy Bolt Pistol", "1x Chainsword"],
	"firestrike servo turrets": ["1x Twin Firestrike Las-talon", "1x Hovering Bulk"],
	"captain in terminator armour": ["1x Relic Weapon", "1x Storm Bolter"],
	"brutalis dreadnought": ["1x Bolt Rifles", "1x Brutalis Fists", "1x Twin Heavy Bolter", "1x Twin Icarus Ironhail Heavy Stubber"],
	"thunderhawk gunship": ["1x Armoured Hull", "1x Hellstrike Missile Battery", "2x Lascannon", "1x Thunderhawk Heavy Cannon", "4x Twin Heavy Bolter"],
	"invictor tactical warsuit": ["1x Fragstorm Grenade Launcher", "1x Heavy Bolter", "1x Incendium Cannon", "1x Invictor Fist", "1x Ironhail Heavy Stubbers"],
	"chaplain in terminator armour": ["1x Crozius Arcanum", "1x Storm Bolter"],
}


# ===========================================================================
# Names / membership
# ===========================================================================

## Lower-case, apostrophes removed, a trailing "(…)" dropped, every
## non-alphanumeric character a space, spaces collapsed.
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

static func datasheet_key(u: Dictionary) -> String:
	return fold(str(u.get("meta", {}).get("name", "")))

## One of the M4a datasheets of a Space Marine army (SM-D1).
static func is_m4a_unit(u: Dictionary) -> bool:
	if u.is_empty() or not _edition_11() or not datasheet_key(u) in DATASHEETS:
		return false
	return Common.is_sm_army(int(u.get("owner", 0)))

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
	return found and is_m4a_unit(u)

static func has_id(unit_id: String, slug: String) -> bool:
	return has(Common.unit(unit_id), slug)

static func display(slug: String) -> String:
	return str(DISPLAY.get(slug, slug))

static func group(unit_id: String) -> Array:
	return Common.attached_group_ids(unit_id)

static func head_id(unit_id: String) -> String:
	return Common.head_id(unit_id)

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

static func phase_key() -> String:
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

static func _log(msg: String) -> void:
	Common.log_info("SMAbilitiesA: " + msg)

## A phase-stamped flag value is live in the current phase.
static func _live(v) -> bool:
	if typeof(v) == TYPE_STRING:
		return str(v) == phase_key()
	if typeof(v) == TYPE_DICTIONARY:
		return str(v.get("phase_key", "")) == phase_key()
	return false


# ===========================================================================
# Usage limits
# ===========================================================================

static func used_in_battle(holder_id: String, slug: String) -> bool:
	var uam = _uam()
	if uam == null or not uam.has_method("is_once_per_battle_used"):
		return false
	return bool(uam.is_once_per_battle_used(holder_id, display(slug)))

static func _mark_battle_use(holder_id: String, slug: String) -> void:
	var uam = _uam()
	if uam and uam.has_method("mark_once_per_battle_used"):
		uam.mark_once_per_battle_used(holder_id, display(slug))

static func used_this_phase(holder_id: String, slug: String) -> bool:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == phase_key()

static func _phase_use_diff(holder_id: String, slug: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = phase_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_PHASE_USES], "value": nd}

static func used_this_turn(holder_id: String, slug: String) -> bool:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_TURN_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _turn_key()

static func _turn_use_diff(holder_id: String, slug: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_TURN_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _turn_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_TURN_USES], "value": nd}

static func _army(player: int) -> Dictionary:
	var a = Common.state().get("players", {}).get(str(player), {}).get(ARMY_STATE, {})
	return a if typeof(a) == TYPE_DICTIONARY else {}


# ===========================================================================
# LIBRARIUS — psyker level budget (army rule)
# ===========================================================================
# The ONE place the budget is read / written (PLAN M2a generalises Librarius
# for every Space Marine army in parallel — re-point psychic_budget_check /
# psychic_budget_record to its API at integration). Same flag keys as
# SWAbilities11e, so a PSYKER unit has one budget whichever module spends it.

static func is_budgeted_psyker(u: Dictionary) -> bool:
	return is_m4a_unit(u) and Common.has_keyword(u, KW_AA) and Common.has_keyword(u, "PSYKER")

static func psyker_level(u: Dictionary) -> int:
	var level := 0
	var re := RegEx.new()
	re.compile("(?i)psyker\\s+level\\s+(\\d+)")
	for ab in u.get("meta", {}).get("abilities", []):
		var n := _ability_name(ab)
		var m := re.search(n)
		if m:
			level = maxi(level, int(m.get_string(1)))
			continue
		var base := fold(n)
		if PSYKER_LEVEL_ABILITIES.has(base):
			level = maxi(level, int(PSYKER_LEVEL_ABILITIES[base]))
	if level == 0 and is_budgeted_psyker(u):
		level = 1
	return level

static func psychic_level(slug: String) -> int:
	return int(PSYCHIC_LEVELS.get(slug, 1))

static func psychic_levels_used(u: Dictionary) -> int:
	var flags: Dictionary = u.get("flags", {})
	if int(flags.get(F_PSY_ROUND, -1)) != _round():
		return 0
	return int(flags.get(F_PSY_USED, 0))

## {ok, reason, level, used, cost} — the budget call (see the section header).
static func psychic_budget_check(unit_id: String, slug: String) -> Dictionary:
	var u := Common.unit(unit_id)
	var cost := psychic_level(slug)
	if u.is_empty() or not is_budgeted_psyker(u):
		return {"ok": false, "reason": "not a PSYKER unit", "level": 0, "used": 0, "cost": cost}
	var level := psyker_level(u)
	var used := psychic_levels_used(u)
	var flags: Dictionary = u.get("flags", {})
	if str(flags.get(F_PSY_PHASE, "")) == phase_key() and slug in flags.get(F_PSY_PHASE_NAMES, []):
		return {"ok": false, "level": level, "used": used, "cost": cost,
			"reason": "%s has already used %s this phase" % [Common.unit_name(unit_id), display(slug)]}
	if used + cost > level:
		return {"ok": false, "level": level, "used": used, "cost": cost,
			"reason": "Librarius: %s (psyker level %d) has used %d psychic level(s) this battle round — %s (psychic level %d) would exceed it" % [
				Common.unit_name(unit_id), level, used, display(slug), cost]}
	return {"ok": true, "reason": "", "level": level, "used": used, "cost": cost}

static func psychic_budget_record(unit_id: String, slug: String) -> Array:
	var u := Common.unit(unit_id)
	if u.is_empty():
		return []
	var used := psychic_levels_used(u) + psychic_level(slug)
	var flags: Dictionary = u.get("flags", {})
	var names: Array = []
	if str(flags.get(F_PSY_PHASE, "")) == phase_key():
		names = (flags.get(F_PSY_PHASE_NAMES, []) as Array).duplicate()
	names.append(slug)
	_log("Librarius — %s used %s (psychic level %d): %d/%d psyker level spent this battle round" % [
		unit_id, display(slug), psychic_level(slug), used, psyker_level(u)])
	return [
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_ROUND], "value": _round()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_USED], "value": used},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE], "value": phase_key()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE_NAMES], "value": names},
	]

static func _psychic_ready(holder_id: String, slug: String) -> bool:
	return psychic_budget_check(holder_id, slug).ok and not _group_shocked(holder_id)

## The psychic D6 (a 1: the unit is battle-shocked — the effect still resolves) + budget diffs.
static func _psychic_roll(holder_id: String, slug: String) -> Dictionary:
	var roll := int(Common.roll_dice(1)[0])
	var diffs: Array = psychic_budget_record(holder_id, slug)
	var note := "psychic roll %d" % roll
	if roll == 1:
		for gid in group(holder_id):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
		note += " — a 1: the unit is battle-shocked"
	return {"roll": roll, "diffs": diffs, "note": note}


# ===========================================================================
# PASSIVE COMBAT MODIFIERS — merged into RulesEngine's ork11e_ab_mods aggregator
# ===========================================================================

static func _empty_mods() -> Dictionary:
	return {"hit_plus": false, "hit_minus": false, "hit_reroll": "", "ignore_hit_penalties": false,
		"wound_plus": false, "wound_reroll": "", "ignore_wound_penalties": false, "ap": 0, "damage": 0,
		"strength": 0, "attacks": 0, "sustained": 0, "lethal": false, "ignores_cover": false,
		"devastating": false, "precision": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

## The M4a contribution, merged INTO `m` — the one-line RulesEngine hook.
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
	m["lethal"] = bool(m.get("lethal", false)) or c.lethal
	m["ignores_cover"] = bool(m.get("ignores_cover", false)) or c.ignores_cover
	m["devastating"] = bool(m.get("devastating", false)) or c.devastating
	m["precision"] = bool(m.get("precision", false)) or c.precision
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append_array(c.sources)

static func _weapon_base_name(weapon_profile: Dictionary) -> String:
	return fold(str(weapon_profile.get("name", "")).split(" – ")[0].split(" - ")[0])

static func attack_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> Dictionary:
	var m := _empty_mods()
	var actor_id := _uid(actor_unit)
	if actor_id == "" or actor_unit.is_empty() or not _edition_11():
		return m
	var target_id := _uid(target_unit)
	var target_ok := target_id != "" and not target_unit.is_empty()
	var target_head := head_id(target_id) if target_ok else ""
	var owner := int(actor_unit.get("owner", 0))

	# --- target-side effects (any attacker) ---------------------------------
	if target_ok:
		# Bladeguard (defend) / Shrouding: attacks that target this unit have -1 to hit.
		var bg = _gflag(target_head, F_BLADEGUARD)
		if typeof(bg) == TYPE_DICTIONARY and _live(bg) and str(bg.get("mode", "")) == "defend":
			m.hit_minus = true
			_src(m, "Bladeguard", "hit", "minus_one", "attacks that target the Bladeguard Veterans have -1 to hit")
		if _live(_gflag(target_head, F_SHROUDED)):
			m.hit_minus = true
			_src(m, "Shrouding", "hit", "minus_one", "attacks that target this unit have -1 to hit (Shrouding)")
		if not is_melee:
			if _live(_gflag(target_head, F_SOUL_SIGHT)):
				m.ignores_cover = true
				_src(m, "Soul Sight", "other", "ignores_cover", "ranged attacks that target this unit have [IGNORES COVER]")
			var dr = _gflag(target_head, F_DRIVEN)
			if typeof(dr) == TYPE_DICTIONARY and _live(dr) and int(dr.get("player", 0)) == owner and Common.has_keyword(actor_unit, KW_AA):
				m.ignores_cover = true
				_src(m, str(dr.get("source", "Driven from Cover")), "other", "ignores_cover", "friendly ADEPTUS ASTARTES ranged attacks that target this unit have [IGNORES COVER]")

	# --- this VEHICLE model: Master of the Forge / Blessings of the Omnissiah --
	var bl = actor_unit.get("flags", {}).get(F_BLESSED, null)
	if typeof(bl) == TYPE_DICTIONARY and int(bl.get("player", 0)) == owner:
		m.ignore_hit_penalties = true
		m.ignore_wound_penalties = true
		_src(m, str(bl.get("source", "Blessings of the Omnissiah")), "hit", "ignored",
			"this VEHICLE model's attacks ignore modifiers to %shit rolls and wound rolls" % ("BS, " if bool(bl.get("bs", false)) else ""))

	# --- Primarch of the XIII (Aura): friendly AA unit within 6" of Guilliman ---
	if Common.has_keyword(actor_unit, KW_AA) or Common.group_has_keyword(actor_id, KW_AA):
		var pg := primarch_aura_source(actor_id)
		if pg != "":
			m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
			m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
			_src(m, "Primarch of the XIII", "hit", "reroll_ones", "within 6\" of %s: re-roll hit rolls of 1" % Common.unit_name(pg))
			_src(m, "Primarch of the XIII", "wound", "reroll_ones", "within 6\" of %s: re-roll wound rolls of 1" % Common.unit_name(pg))

	# Every ability below is held by a component of an M4a datasheet.
	var any_m4a := false
	for gid in group(actor_id):
		if is_m4a_unit(Common.unit(str(gid))):
			any_m4a = true
	if not any_m4a and not is_m4a_unit(actor_unit):
		return m
	var charged := _group_charged(actor_id) or bool(actor_unit.get("flags", {}).get("charged_this_turn", false))
	var dist_to_target := _dist(actor_id, target_head) if target_ok else INF

	# --- "this model" abilities ---------------------------------------------
	if is_melee and has(actor_unit, "finest_hour") and _live(actor_unit.get("flags", {}).get(F_FINEST_HOUR, null)):
		m.attacks += 3
		m.devastating = true
		_src(m, "Finest Hour", "other", "attacks", "this model's melee attacks +3 A and [DEVASTATING WOUNDS]")

	# --- "this unit" abilities (the whole Attached unit) -----------------------
	if target_ok and group_has(actor_id, "vivispectral_analysis_targeting") and not Common.group_has_keyword(target_head, "VEHICLE"):
		m.lethal = true
		_src(m, "Vivispectral Analysis Targeting", "other", "lethal_hits", "[LETHAL HITS] against a non-VEHICLE target")
	if not is_melee and target_ok and group_has(actor_id, "fury_of_the_machine_spirit") and dist_to_target <= FURY_RANGE_IN + 0.001:
		m.lethal = true
		_src(m, "Fury of the Machine Spirit", "other", "lethal_hits", "ranged attacks vs a unit within 12\": [LETHAL HITS]")
	var bg_own = _gflag(actor_id, F_BLADEGUARD)
	if is_melee and typeof(bg_own) == TYPE_DICTIONARY and _live(bg_own) and str(bg_own.get("mode", "")) == "attack" and group_has(actor_id, "bladeguard"):
		m.hit_plus = true
		_src(m, "Bladeguard", "hit", "plus_one", "melee attacks +1 to hit")
	if is_melee and _live(_gflag(actor_id, F_MIGHT)):
		m.strength += 2
		_src(m, "Might of Heroes", "other", "strength", "melee attacks +2 S")
	if not is_melee and target_ok and group_has(actor_id, "ballistus_strike") and dist_to_target <= BALLISTUS_RANGE_IN + 0.001:
		m.sustained = maxi(m.sustained, 1)
		_src(m, "Ballistus Strike", "other", "sustained_hits", "ranged attacks vs a unit within 24\": [SUSTAINED HITS 1]")
	if is_melee and charged and group_has(actor_id, "litany_of_hate"):
		m.wound_plus = true
		_src(m, "Litany of Hate", "wound", "plus_one", "[LANCE]: made a charge move this turn")
	var cat = _gflag(actor_id, F_CATECHISM)
	if not is_melee and target_ok and typeof(cat) == TYPE_DICTIONARY and _live(cat) and head_id(str(cat.get("target", ""))) == target_head:
		m.devastating = true
		_src(m, "Catechism of Fire", "other", "devastating_wounds", "ranged attacks vs the selected unit: [DEVASTATING WOUNDS]")
	if is_melee and group_has(actor_id, "exhortation_of_rage") and at_or_below_half_strength(actor_id):
		m.wound_reroll = "failed"
		_src(m, "Exhortation of Rage", "wound", "reroll_failed", "at or below half-strength: melee attacks re-roll wound rolls")
	if not is_melee and target_ok and group_has(actor_id, "hammerstrike") and unit_within_terrain_area(target_head):
		m.sustained = maxi(m.sustained, 1)
		_src(m, "Hammerstrike", "other", "sustained_hits", "target is within a terrain area: [SUSTAINED HITS 1]")
	if is_melee and charged and target_ok and group_has(actor_id, "terminatus_assault"):
		var wn := _weapon_base_name(weapon_profile)
		var mv := _is_mv(target_head)
		if wn.contains("lightning claw") and not mv:
			m.sustained = maxi(m.sustained, 1)
			_src(m, "Terminatus Assault", "other", "sustained_hits", "charged: Lightning Claws [SUSTAINED HITS 1] vs non-MONSTER/VEHICLE")
		elif wn.contains("thunder hammer") and mv:
			m.sustained = maxi(m.sustained, 1)
			_src(m, "Terminatus Assault", "other", "sustained_hits", "charged: Thunder Hammer [SUSTAINED HITS 1] vs MONSTER/VEHICLE")
	if not is_melee and group_has(actor_id, "meteoric_descent") and made_ingress_this_turn(actor_id):
		m.hit_plus = true
		_src(m, "Meteoric Descent", "hit", "plus_one", "made an ingress move this turn: ranged attacks +1 to hit")
	if is_melee and charged and group_has(actor_id, "vanguard_assault"):
		m.attacks += 1
		_src(m, "Vanguard Assault", "other", "attacks", "made a charge move this turn: melee +1 A")
	var inv := group_holder(actor_id, "forward_assault_warsuit")
	if target_ok and inv != "":
		var mark := str(Common.unit(inv).get("flags", {}).get(F_MARK, ""))
		if mark != "" and head_id(mark) == target_head:
			m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
			_src(m, "Forward Assault Warsuit", "wound", "reroll_ones", "target is this unit's mark: re-roll wound rolls of 1")
	return m

## "At or below half-strength" (the Attached unit's combined starting strength).
static func at_or_below_half_strength(unit_id: String) -> bool:
	var gs = Common.game_state()
	if gs == null:
		return false
	var head := head_id(unit_id)
	return bool(gs.is_below_half_strength_combined(head)) or bool(gs.is_at_half_strength_combined(head))

## Hammerstrike: any model of the (Attached) unit is within a terrain area
## (any part of its base inside a terrain piece's footprint — 13.01).
static func unit_within_terrain_area(unit_id: String) -> bool:
	return not terrain_pieces_unit_within(unit_id).is_empty()

static func terrain_pieces_unit_within(unit_id: String) -> Array:
	var out: Array = []
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("pieces_model_within"):
		return out
	for gid in group(unit_id):
		for mm in Common.unit(str(gid)).get("models", []):
			if not mm.get("alive", true) or mm.get("position", null) == null:
				continue
			for piece in tm.pieces_model_within(mm):
				var pid := str(piece.get("id", ""))
				if pid != "" and not pid in out:
					out.append(pid)
	return out

## "made an ingress move this turn" (the reserves arrival stamp).
static func made_ingress_this_turn(unit_id: String) -> bool:
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if bool(u.get("flags", {}).get("arrived_from_reserves", false)):
			return true
		if int(u.get("owner", 0)) == Common.active_player() and int(u.get("arrived_from_reserves_turn", -1)) == _round():
			return true
	return false

## Primarch of the XIII: the Guilliman unit whose 6" aura reaches `unit_id`, or "".
static func primarch_aura_source(unit_id: String) -> String:
	var u := Common.unit(unit_id)
	if u.is_empty():
		return ""
	var owner := int(u.get("owner", 0))
	for gid in Common.state().get("units", {}):
		var g := Common.unit(str(gid))
		if int(g.get("owner", 0)) != owner or not has(g, "primarch_of_the_xiii") or not Common.is_on_battlefield(g):
			continue
		if head_id(str(gid)) == head_id(unit_id) or _dist(str(gid), unit_id) <= PRIMARCH_RANGE_IN + 0.001:
			return str(gid)
	return ""


# ===========================================================================
# DEFENSIVE / MOVEMENT / MISC passive hooks
# ===========================================================================

## Rites of Tempering (Iron Father Feirros): S > T attacks that target this unit -1 to wound.
static func incoming_wound_penalty_source(target_unit: Dictionary, strength: int, toughness: int) -> String:
	if strength <= toughness or not _edition_11():
		return ""
	var tid := _uid(target_unit)
	if tid != "" and group_has(tid, "rites_of_tempering"):
		return "Rites of Tempering"
	return ""

static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	return incoming_wound_penalty_source(target_unit, strength, toughness) != ""

## Psychic Hood (FNP 4+ vs psychic attacks) / Zealous Fortitude (FNP 4+ vs
## mortal wounds) — "this unit": the whole Attached unit. 0 = none.
static func fnp_vs(unit: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	if not _edition_11() or unit.is_empty():
		return 0
	var uid := _uid(unit)
	if uid == "":
		return 0
	var best := 0
	if is_psychic and group_has(uid, "psychic_hood"):
		best = 4
	if is_mortal and group_has(uid, "zealous_fortitude"):
		best = 4
	return best

## Range characteristic bonus (inches): Thunderous Force +6" (ranged, this unit, this phase).
static func range_bonus_inches(actor_unit: Dictionary, weapon_profile: Dictionary = {}) -> float:
	if not _edition_11() or actor_unit.is_empty():
		return 0.0
	if str(weapon_profile.get("type", "Ranged")).to_lower() == "melee":
		return 0.0
	if _live(_gflag(_uid(actor_unit), F_THUNDEROUS)):
		return THUNDEROUS_RANGE_IN
	return 0.0

## Angel's Wrath (Captain with Jump Pack): +1 to advance rolls and charge rolls (this unit).
static func roll_bonus(unit_id: String) -> Dictionary:
	if not _edition_11() or unit_id == "":
		return {"bonus": 0, "source": ""}
	if group_has(unit_id, "angels_wrath"):
		return {"bonus": 1, "source": "Angel's Wrath"}
	return {"bonus": 0, "source": ""}

## Unstoppable Valour (Captain in Terminator Armour): re-roll charge rolls.
static func charge_reroll_source(unit: Dictionary) -> String:
	if not _edition_11() or unit.is_empty():
		return ""
	return "Unstoppable Valour" if group_has(_uid(unit), "unstoppable_valour") else ""

## Iron Father / Techmarine (within 3" of a friendly AA VEHICLE unit) and
## Leader of Astartes (within 3" of a friendly AA INFANTRY unit): Lone Operative.
static func conditional_lone_operative(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or not Common.is_on_battlefield(unit):
		return false
	var kw := ""
	if has(unit, "iron_father") or has(unit, "techmarine"):
		kw = "VEHICLE"
	elif has(unit, "leader_of_astartes"):
		kw = "INFANTRY"
	if kw == "":
		return false
	var owner := int(unit.get("owner", 0))
	for vid in Common.state().get("units", {}):
		var v := Common.unit(str(vid))
		if str(vid) == _uid(unit) or int(v.get("owner", 0)) != owner or not Common.has_keyword(v, kw) or not Common.has_keyword(v, KW_AA):
			continue
		if not Common.is_on_battlefield(v):
			continue
		if Common.unit_distance_inches(unit, v) <= LONE_OP_RANGE_IN + 0.001:
			return true
	return false

## Detection range bonus of a unit: Omni-scramblers' detected (+3", this phase)
## and Priority Target Identified (+3" while within the identified terrain feature).
static func detection_range_bonus(unit: Dictionary) -> float:
	if not _edition_11() or unit.is_empty():
		return 0.0
	var uid := _uid(unit)
	var bonus := 0.0
	var det = _gflag(uid, F_DETECTED) if uid != "" else unit.get("flags", {}).get(F_DETECTED, null)
	if typeof(det) == TYPE_DICTIONARY and _live(det):
		bonus += DETECTION_BONUS_IN
	var owner := int(unit.get("owner", 0))
	var enemy := 2 if owner == 1 else 1
	var pt = Common.state().get("factions", {}).get(str(enemy), {}).get(FK_PRIORITY, null) if owner > 0 else null
	if typeof(pt) == TYPE_DICTIONARY and str(pt.get("turn_key", "")) == _turn_key() and uid != "":
		if str(pt.get("feature_id", "")) in terrain_pieces_unit_within(uid):
			bonus += DETECTION_BONUS_IN
	return bonus

## Sentinel Protocols: this unit's snap-shooting attacks hit on unmodified 4+
## while its Fire Overwatch use is resolved (this phase). 0 = the normal 6.
static func snap_hit_threshold(actor_unit: Dictionary) -> int:
	if not _edition_11() or actor_unit.is_empty():
		return 0
	return 4 if _live(actor_unit.get("flags", {}).get(F_SENTINEL, null)) else 0

## Omni-scramblers (11e): the 10e 12" reinforcement-denial ring is retired for
## M4a Infiltrator Squads of a Space Marine army (the codex text is different).
static func omni_scramblers_denial_retired(unit: Dictionary) -> bool:
	return _edition_11() and has(unit, "omni_scramblers")


# ===========================================================================
# POWER OF THE MACHINE SPIRIT (Land Raider): "This unit's ranged attacks can:
# re-roll one hit roll; re-roll one wound roll" — per unit, per phase (a unit
# is selected to shoot once per phase). RulesEngine's re-roll-one hook
# (cus11e_magna_reroll_hit / _wound) asks here when Magna Imperator does not
# apply. Host-side ledger keyed "<head>|<phase_key>|<hit|wound>".
# ===========================================================================

static var _machine_spirit_used: Dictionary = {}

static func machine_spirit_available(attacker: Dictionary, kind: String) -> bool:
	if not _edition_11() or attacker.is_empty():
		return false
	var uid := _uid(attacker)
	if uid == "" or not group_has(uid, "power_of_the_machine_spirit"):
		return false
	return not _machine_spirit_used.has("%s|%s|%s" % [head_id(uid), phase_key(), kind])

static func machine_spirit_consume(attacker: Dictionary, kind: String) -> void:
	var uid := _uid(attacker)
	_machine_spirit_used["%s|%s|%s" % [head_id(uid), phase_key(), kind]] = true
	_log("Power of the Machine Spirit — %s re-rolls one %s roll this phase" % [uid, kind])

static func reset_machine_spirit() -> void:
	_machine_spirit_used = {}


# ===========================================================================
# STRATAGEM OVERRIDES — Brutalis Charge (CRUSHING IMPACT), Sentinel Protocols
# (FIRE OVERWATCH): "regardless of any other uses of that stratagem this
# phase … does not prevent any uses of that stratagem on other units".
# StratagemManager._cus11e_stratagem_override shape.
# ===========================================================================

static func stratagem_override(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	var none := {"applies": false}
	if not _edition_11() or target_unit_id == "":
		return none
	var u := Common.unit(target_unit_id)
	if int(u.get("owner", 0)) != player:
		return none
	var sid := stratagem_id
	if sid == "crushing_impact" or sid == "tank_shock" or sid == "crushing_impact_11e":
		var h := group_holder(target_unit_id, "brutalis_charge")
		if h != "" and not used_this_phase(h, "brutalis_charge"):
			return {"applies": true, "cost_delta": -1, "source": "Brutalis Charge", "sm11e_m4a": true, "holder": h, "slug": "brutalis_charge"}
	if sid.begins_with("fire_overwatch"):
		var h2 := group_holder(target_unit_id, "sentinel_protocols")
		if h2 != "" and not used_this_phase(h2, "sentinel_protocols"):
			return {"applies": true, "cost_delta": 0, "source": "Sentinel Protocols", "sm11e_m4a": true, "holder": h2, "slug": "sentinel_protocols"}
	return none

## A Sentinel Protocols unit of `player` that has not used it this phase.
static func has_sentinel_holder(player: int) -> bool:
	if not _edition_11():
		return false
	for hid in _holders(player, "sentinel_protocols"):
		if not used_this_phase(hid, "sentinel_protocols"):
			return true
	return false

## After a FIRE OVERWATCH (MovementPhase._snap_finish): when another use is
## still possible because of Sentinel Protocols, the movement_phase_end window
## entry to queue again ({} = none). Bounded: every re-offer needs a Sentinel
## unit that has not used it, or the limit a Sentinel use did not spend.
static func fire_overwatch_reoffer(player: int, ctx: Dictionary) -> Dictionary:
	if not _edition_11() or player <= 0 or _holders(player, "sentinel_protocols").is_empty():
		return {}
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_window_offers"):
		return {}
	for o in sm.get_window_offers(player, "movement_phase_end", ctx):
		if str(o.get("stratagem_id", "")).begins_with("fire_overwatch") and not (o.get("targets", []) as Array).is_empty():
			_log("Sentinel Protocols — FIRE OVERWATCH can still be used this phase: movement_phase_end offered again to P%d" % player)
			return {"player": player, "window_id": "movement_phase_end", "ctx": ctx}
	return {}

## The override was used: record the once-per-phase use (+ Sentinel's 4+ snap stamp).
static func record_stratagem_override(ov: Dictionary) -> Array:
	var holder := str(ov.get("holder", ""))
	var slug := str(ov.get("slug", ""))
	if holder == "" or slug == "":
		return []
	var diffs: Array = [_phase_use_diff(holder, slug)]
	if slug == "sentinel_protocols":
		diffs.append_array(Common.set_flag_diffs(group(holder), F_SENTINEL, phase_key()))
	var msg := "%s: %s uses the stratagem regardless of its other uses this phase%s" % [display(slug), Common.unit_name(holder),
		" (-1 CP)" if int(ov.get("cost_delta", 0)) < 0 else " — its snap-shooting attacks hit on unmodified 4+"]
	_log(msg)
	_event_log(int(Common.unit(holder).get("owner", 0)), msg)
	return diffs

## Teleport Homer: RAPID INGRESS on a unit whose token is on the battlefield
## (and can be used — a legal set-up near it may exist) is -1 CP. 0 or 1.
static func stratagem_cp_discount(player: int, stratagem_id: String, target_unit_id: String) -> int:
	if not _edition_11() or target_unit_id == "" or not stratagem_id.begins_with("rapid_ingress"):
		return 0
	var u := Common.unit(target_unit_id)
	if int(u.get("owner", 0)) != player or int(u.get("status", 0)) != ST_IN_RESERVES:
		return 0
	return 1 if homer_usable(target_unit_id) else 0

## A Rapid Ingress use with the token: the unit must set up within 3" of it.
static func record_cp_discount(player: int, target_unit_id: String) -> void:
	var holder := _homer_holder(target_unit_id)
	if holder == "":
		return
	Common.apply_diffs(Common.set_flag_diffs([holder], F_HOMER_ACTIVE, phase_key()))
	var msg := "Teleport Homer: %s's Rapid Ingress uses the token (-1 CP) — it must be set up within 3\" of it and not within 8\" of an enemy unit" % Common.unit_name(holder)
	_log(msg)
	_event_log(player, msg)


# ===========================================================================
# TELEPORT HOMER (Terminator Assault Squad, once per battle)
# ===========================================================================

static func _homer_holder(unit_id: String) -> String:
	for gid in group(unit_id):
		var f: Dictionary = Common.unit(str(gid)).get("flags", {})
		if typeof(f.get(F_HOMER, null)) == TYPE_DICTIONARY:
			return str(gid)
	return ""

static func homer_position_px(unit_id: String) -> Vector2:
	var h := _homer_holder(unit_id)
	if h == "":
		return Vector2.INF
	var t: Dictionary = Common.unit(h).get("flags", {}).get(F_HOMER, {})
	return Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0)))

## The token can be used: on the battlefield and more than 8" + a model's base
## from every enemy model (so a set-up within 3" of it can exist).
static func homer_usable(unit_id: String) -> bool:
	var p := homer_position_px(unit_id)
	if p == Vector2.INF:
		return false
	var owner := int(Common.unit(unit_id).get("owner", 0))
	for eid in Common.enemy_heads(owner):
		for gid in group(str(eid)):
			for mm in Common.unit(str(gid)).get("models", []):
				if not mm.get("alive", true) or mm.get("position", null) == null:
					continue
				var mp := Vector2(float(mm.position.x), float(mm.position.y))
				var r := float(mm.get("base_mm", 32)) / 25.4 / 2.0
				if mp.distance_to(p) / PX_PER_INCH - r < DROP_POD_ENEMY_IN + 0.5:
					return false
	return true

## The token is in use for this unit's set-up (this phase).
static func homer_active(unit_id: String) -> bool:
	var h := _homer_holder(unit_id)
	return h != "" and _live(Common.unit(h).get("flags", {}).get(F_HOMER_ACTIVE, null))

## Set-up errors for a reinforcement that uses the token: at least one model
## within 3" of it (a unit is "within" when any of its models is). [] = fine.
static func homer_setup_errors(unit_id: String, positions: Array) -> Array:
	if not homer_active(unit_id):
		return []
	var p := homer_position_px(unit_id)
	var models: Array = Common.unit(unit_id).get("models", [])
	for i in range(positions.size()):
		var pos = positions[i]
		if pos == null:
			continue
		var v := Vector2(float(pos.x), float(pos.y)) if (pos is Dictionary or pos is Vector2) else Vector2.INF
		if v == Vector2.INF:
			continue
		var r := float(models[i].get("base_mm", 32)) / 25.4 / 2.0 if i < models.size() else 0.6
		if v.distance_to(p) / PX_PER_INCH - r <= HOMER_SETUP_IN + 0.001:
			return []
	return ["Teleport Homer: the unit must be set up within 3\" of its Teleport Homer token"]

## After a set-up that used the token: it is removed (and the use spent).
static func on_reinforcement_set_up(unit_id: String) -> Array:
	var diffs: Array = []
	if not _edition_11():
		return diffs
	var h := _homer_holder(unit_id)
	if h != "" and homer_active(unit_id):
		diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [h, F_HOMER]})
		diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [h, F_HOMER_ACTIVE]})
		_log("Teleport Homer: %s set up next to its token — the token is removed" % h)
	return diffs

## "If an enemy unit ends a move within 1\" of that token, it is removed":
## checked when a unit ends a move (MovementPhase hook) and at every phase change.
static func check_homers_after_move(_moved_unit_id: String = "") -> Array:
	var diffs: Array = []
	if not _edition_11():
		return diffs
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		var t = u.get("flags", {}).get(F_HOMER, null)
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var p := Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0)))
		var owner := int(u.get("owner", 0))
		for eid in Common.enemy_heads(owner):
			var hit := false
			for gid in group(str(eid)):
				for mm in Common.unit(str(gid)).get("models", []):
					if not mm.get("alive", true) or mm.get("position", null) == null:
						continue
					var mp := Vector2(float(mm.position.x), float(mm.position.y))
					var r := float(mm.get("base_mm", 32)) / 25.4 / 2.0
					if mp.distance_to(p) / PX_PER_INCH - r <= HOMER_ENEMY_IN + 0.001:
						hit = true
			if hit:
				diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_HOMER]})
				var msg := "Teleport Homer: %s ended a move within 1\" of %s's token — the token is removed" % [Common.group_label(str(eid)), Common.unit_name(str(uid))]
				_log(msg)
				_event_log(owner, msg)
				break
	return diffs

## Candidate token positions (px): the objective markers and the centre of
## every friendly unit on the battlefield. [{id, label, x, y}]
static func homer_spots(player: int) -> Array:
	var out: Array = []
	for obj in Common.objectives():
		var p = obj.get("position", null)
		if p == null:
			continue
		var v := Vector2(float(p.x), float(p.y)) if (p is Dictionary or p is Vector2) else Vector2.ZERO
		out.append({"id": "objective_%s" % str(obj.get("id", "")), "label": "On objective %s" % Common.objective_label(str(obj.get("id", ""))), "x": v.x, "y": v.y})
	for fid in Common.friendly_heads(player):
		var c := _unit_centre_px(str(fid))
		if c == Vector2.INF:
			continue
		out.append({"id": "unit_%s" % str(fid), "label": "Next to %s (%d\", %d\")" % [Common.group_label(str(fid)), roundi(c.x / PX_PER_INCH), roundi(c.y / PX_PER_INCH)], "x": c.x, "y": c.y})
	return out

static func _unit_centre_px(unit_id: String) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for gid in group(unit_id):
		for mm in Common.unit(str(gid)).get("models", []):
			if mm.get("alive", true) and mm.get("position", null) != null:
				s += Vector2(float(mm.position.x), float(mm.position.y))
				n += 1
	return s / float(n) if n > 0 else Vector2.INF


# ===========================================================================
# TRANSPORTS — Assault Ramp / Aerial Assault / Drop Pod Assault / Deployment Complete
# ===========================================================================

## DisembarkMove.select_mode hook: units embarked in this transport make an
## ASSAULT DISEMBARK MOVE (18.06) during the M4a follow-up.
static func transport_grants_assault_disembark(transport: Dictionary) -> bool:
	if not _edition_11() or transport.is_empty():
		return false
	var f: Dictionary = transport.get("flags", {})
	return _live(f.get(F_ASSAULT_RAMP, null)) or _live(f.get(F_AERIAL, null))

## Aerial Assault: only embarked units whose every model has Deep Strike.
static func filter_assault_disembark(transport_id: String, units: Array) -> Array:
	var t := Common.unit(transport_id)
	if not _live(t.get("flags", {}).get(F_AERIAL, null)):
		return units
	var gs = Common.game_state()
	var out: Array = []
	for uid in units:
		var ok := true
		for gid in group(str(uid)):
			if gs and gs.has_method("unit_has_deep_strike") and not bool(gs.unit_has_deep_strike(str(gid))):
				ok = false
		if ok:
			out.append(uid)
	return out

## The follow-up ended: the transport's assault-disembark grant is spent.
static func assault_disembark_off_diffs(transport_id: String) -> Array:
	var diffs: Array = []
	var t := Common.unit(transport_id)
	for f in [F_ASSAULT_RAMP, F_AERIAL]:
		if t.get("flags", {}).has(f):
			t.flags.erase(f)
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [transport_id, f]})
	return diffs

static func _embarked_units(transport_id: String) -> Array:
	var out: Array = []
	var t := Common.unit(transport_id)
	for uid in t.get("transport_data", {}).get("embarked_units", []):
		var u := Common.unit(str(uid))
		if u.is_empty() or not Common.is_alive(u) or str(u.get("embarked_in", "")) != transport_id:
			continue
		var att = u.get("attached_to", null)
		if att != null and str(att) != "":
			continue
		if bool(u.get("flags", {}).get("embarked_this_phase", false)):
			continue
		out.append(str(uid))
	return out

## Drop Pod Assault: "must start the battle in strategic reserves" — the
## FormationsPhase hook adds every Drop Pod of `player` that is not declared yet.
static func forced_reserves(player: int, declared: Array) -> Array:
	var out: Array = []
	if not _edition_11():
		return out
	var have := {}
	for e in declared:
		have[str(e.get("unit_id", ""))] = true
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not has(u, "drop_pod_assault") or have.has(str(uid)):
			continue
		out.append({"unit_id": str(uid), "reserve_type": "strategic_reserves", "attached_character_ids": [], "sm11e_drop_pod": true})
		_log("Drop Pod Assault: %s must start the battle in strategic reserves — declared automatically" % uid)
	return out

## Drop Pod Assault: "In your first Movement phase, this unit can make an ingress move."
static func can_ingress_first_round(unit: Dictionary) -> bool:
	return _edition_11() and has(unit, "drop_pod_assault")

## Drop Pod Assault: the Drop Pod was just set up — its embarked units must
## disembark (assault disembark move) more than 8" from every enemy unit.
## Returns the follow-up dictionary for MovementPhase, or {}.
static func drop_pod_landed(unit_id: String) -> Dictionary:
	var u := Common.unit(unit_id)
	if not has(u, "drop_pod_assault"):
		return {}
	var emb := _embarked_units(unit_id)
	var diffs: Array = Common.set_flag_diffs([unit_id], F_DROP_POD_LANDED, true)
	if emb.is_empty():
		return {"diffs": diffs, "units": []}
	diffs.append_array(Common.set_flag_diffs([unit_id], F_ASSAULT_RAMP, phase_key()))
	for e in emb:
		diffs.append_array(Common.set_flag_diffs(group(str(e)), F_DROP_POD_DISEMBARK, phase_key()))
	_log("Drop Pod Assault: %s set up — %s must disembark (assault disembark, more than 8\" from enemy units)" % [unit_id, str(emb)])
	return {"diffs": diffs, "units": emb, "followup": {"type": "assault_disembark", "transport_id": unit_id, "source": "Drop Pod Assault"}}

## Disembark set-up errors: a unit leaving a Drop Pod as it lands must be set
## up more than 8" from every enemy model. [] = fine.
static func disembark_setup_errors(unit_id: String, positions) -> Array:
	if not _edition_11() or not _live(Common.unit(unit_id).get("flags", {}).get(F_DROP_POD_DISEMBARK, null)):
		return []
	var owner := int(Common.unit(unit_id).get("owner", 0))
	var models: Array = Common.unit(unit_id).get("models", [])
	var idxs: Array = positions.keys() if positions is Dictionary else range((positions as Array).size())
	for i in idxs:
		var pos = positions[i]
		if pos is Array and (pos as Array).size() >= 2:
			pos = Vector2(float(pos[0]), float(pos[1]))
		if pos == null:
			continue
		var v := Vector2(float(pos.x), float(pos.y)) if (pos is Dictionary or pos is Vector2) else Vector2.INF
		if v == Vector2.INF:
			continue
		var r := float(models[i].get("base_mm", 32)) / 25.4 / 2.0 if i < models.size() else 0.6
		for eid in Common.enemy_heads(owner):
			for gid in group(str(eid)):
				for mm in Common.unit(str(gid)).get("models", []):
					if not mm.get("alive", true) or mm.get("position", null) == null:
						continue
					var mp := Vector2(float(mm.position.x), float(mm.position.y))
					var er := float(mm.get("base_mm", 32)) / 25.4 / 2.0
					if v.distance_to(mp) / PX_PER_INCH - r - er <= DROP_POD_ENEMY_IN + 0.001:
						return ["Drop Pod Assault: models disembarking from a Drop Pod must be set up more than 8\" away from all enemy units"]
	return []

## Deployment Complete: once set up and emptied, units cannot embark within the Drop Pod.
static func embark_block_reason(transport_id: String) -> String:
	var t := Common.unit(transport_id)
	if not has(t, "deployment_complete"):
		return ""
	if bool(t.get("flags", {}).get(F_DROP_POD_LANDED, false)) and _embarked_units(transport_id).is_empty():
		return "Deployment Complete: units cannot embark within this Drop Pod"
	return ""


# ===========================================================================
# ARMY LOAD — wargear stat changes + default kits (ArmyListManager hook, idempotent)
# ===========================================================================

static func wargear_count(unit: Dictionary, item: String) -> int:
	var n := 0
	var want := fold(item)
	var re := RegEx.new()
	re.compile("^(\\d+)\\s*x\\s*(.+)$")
	for w in unit.get("meta", {}).get("wargear", []):
		for part in str(w).split(","):
			var s := str(part).strip_edges()
			var cnt := 1
			var m := re.search(s)
			if m:
				cnt = int(m.get_string(1))
				s = m.get_string(2)
			if fold(s) == want:
				n += cnt
	return n

static func _has_ability_name(unit: Dictionary, folded: String) -> bool:
	for ab in unit.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == folded:
			return true
	return false

## Relic Shield (+1 W), Storm Shield (Terminator Assault Squad, +1 W), Combat
## Shield (5+ InSv) on the models that took them; the default kit stamped as
## wargear for single-model datasheets whose roster lists none. Runs before
## the faction gate is known (army load): datasheet + 11e only.
static func apply_list_build(unit_id: String, unit: Dictionary) -> void:
	if unit.is_empty() or not _edition_11():
		return
	var key := datasheet_key(unit)
	if not key in DATASHEETS:
		return
	var meta: Dictionary = unit.get("meta", {})
	var models: Array = unit.get("models", [])
	# Transport capacity keywords: the army data prints "SPACE MARINES INFANTRY
	# models" (the codex: "Adeptus Astartes Infantry") and the loader splits it
	# into SPACE / MARINES / INFANTRY — no unit carries SPACE or MARINES, so
	# nothing could embark. Read it as ADEPTUS ASTARTES + INFANTRY.
	var td = unit.get("transport_data", null)
	if typeof(td) == TYPE_DICTIONARY:
		var ck: Array = td.get("capacity_keywords", [])
		if "SPACE" in ck and "MARINES" in ck:
			var nk: Array = ["ADEPTUS ASTARTES"]
			for k in ck:
				if not str(k) in ["SPACE", "MARINES"]:
					nk.append(str(k))
			td["capacity_keywords"] = nk
			print("SMAbilitiesA: %s (%s): transport capacity keywords %s -> %s" % [unit_id, meta.get("name", "?"), str(ck), str(nk)])
	# Default kit (single-model menus): only when the roster lists no wargear.
	if DEFAULT_KIT.has(key) and models.size() == 1 and (meta.get("wargear", []) as Array).is_empty():
		meta["wargear"] = (DEFAULT_KIT[key] as Array).duplicate()
		meta["sm11e_default_kit"] = true
		print("SMAbilitiesA: %s (%s): no roster wargear — default kit %s" % [unit_id, meta.get("name", "?"), str(meta.wargear)])
	# Relic Shield: +1 W (the bearer is the single model). The ability is listed
	# on the datasheet; the model has it when the roster's wargear names it.
	if _has_ability_name(unit, "relic shield") and wargear_count(unit, "Relic Shield") > 0:
		for m in models:
			if typeof(m) != TYPE_DICTIONARY or bool(m.get(M_RELIC, false)):
				continue
			m[M_RELIC] = true
			m["wounds"] = int(m.get("wounds", 1)) + 1
			m["current_wounds"] = int(m.get("current_wounds", int(m.get("wounds", 1)) - 1)) + 1
		print("SMAbilitiesA: Relic Shield on %s (%s): +1 W" % [unit_id, meta.get("name", "?")])
	# Storm Shield (Terminator Assault Squad): +1 W on the first N models.
	if key == "terminator assault squad" and _has_ability_name(unit, "storm shield"):
		var count := wargear_count(unit, "Storm Shield")
		var given := 0
		for m in models:
			if given >= count:
				break
			if typeof(m) != TYPE_DICTIONARY:
				continue
			given += 1
			if bool(m.get(M_SHIELD, false)):
				continue
			m[M_SHIELD] = true
			m["wounds"] = int(m.get("wounds", 1)) + 1
			m["current_wounds"] = int(m.get("current_wounds", int(m.get("wounds", 1)) - 1)) + 1
		print("SMAbilitiesA: Storm Shield on %s: %d model(s) +1 W" % [unit_id, given])
	# Combat Shield (Vanguard Veterans): 5+ invulnerable save on the first N models.
	if _has_ability_name(unit, "combat shield"):
		var cs := wargear_count(unit, "Combat Shield")
		var given2 := 0
		for m in models:
			if given2 >= cs:
				break
			if typeof(m) != TYPE_DICTIONARY:
				continue
			given2 += 1
			if bool(m.get(M_COMBAT_SHIELD, false)):
				continue
			m[M_COMBAT_SHIELD] = true
			var cur := int(m.get("invuln", 0))
			if cur == 0 or cur > 5:
				m["invuln"] = 5
		print("SMAbilitiesA: Combat Shield on %s: %d model(s) 5+ invulnerable save" % [unit_id, given2])


# ===========================================================================
# EXPIRY / per-phase state — PhaseManager.transition_to_phase (thin hook)
# ===========================================================================

const PHASE_SCOPED := [F_BLADEGUARD, F_FINEST_HOUR, F_MIGHT, F_THUNDEROUS, F_SHROUDED, F_SOUL_SIGHT,
	F_DRIVEN, F_CATECHISM, F_DETECTED, F_SENTINEL, F_ASSAULT_RAMP, F_AERIAL, F_DROP_POD_DISEMBARK, F_HOMER_ACTIVE]

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
		if new_phase == PH_MOVEMENT:
			# Master of the Forge / Blessings: until the start of your next Movement phase.
			var bl = flags.get(F_BLESSED, null)
			if typeof(bl) == TYPE_DICTIONARY and int(bl.get("player", 0)) == active and str(bl.get("phase_key", "")) != _phase_key_for(PH_MOVEMENT):
				flags.erase(F_BLESSED)
				cleared.append("%s.%s" % [uid, F_BLESSED])
		if new_phase == PH_COMMAND:
			# Strategic Acumen / Author of the Codex: until the start of your next Command phase.
			var ac = flags.get(F_ACUMEN, null)
			if typeof(ac) == TYPE_DICTIONARY and int(ac.get("player", 0)) == active:
				flags.erase(F_ACUMEN)
				if int(flags.get(F_UNIT_DOCTRINE_EXPIRES, 0)) == active:
					flags.erase(F_UNIT_DOCTRINE)
					flags.erase(F_UNIT_DOCTRINE_EXPIRES)
				cleared.append("%s.%s" % [uid, F_ACUMEN])
			var au = flags.get(F_AUTHOR, null)
			if typeof(au) == TYPE_DICTIONARY and int(au.get("player", 0)) == active:
				flags.erase(F_AUTHOR)
				cleared.append("%s.%s" % [uid, F_AUTHOR])
	_apply_extra_doctrines()
	var hd := check_homers_after_move()
	if not hd.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(hd)
	if not cleared.is_empty():
		_log("phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])

static func _phase_key_for(phase: int) -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), phase]

## Codex Adept (Guilliman: the three doctrines are active for this unit) and
## Author of the Codex (an additional doctrine) through the SWCommon per-unit
## additional-doctrines key; what this module added is remembered in
## F_EXTRA_MINE so another writer's entries (Guile of the Wolf) are kept.
static func _apply_extra_doctrines() -> void:
	var units: Dictionary = Common.state().get("units", {})
	var want: Dictionary = {}
	for uid in units:
		var u: Dictionary = units[uid]
		if has(u, "codex_adept") and Common.is_alive(u):
			for gid in group(str(uid)):
				want[str(gid)] = Common.DOCTRINES.duplicate()
	for uid in units:
		var au = units[uid].get("flags", {}).get(F_AUTHOR, null)
		if typeof(au) == TYPE_DICTIONARY:
			var d := str(au.get("doctrine", ""))
			for gid in group(str(uid)):
				var cur: Array = want.get(str(gid), [])
				if d != "" and not d in cur:
					cur.append(d)
				want[str(gid)] = cur
	for uid in units:
		var u: Dictionary = units[uid]
		if not u.has("flags") or typeof(u.flags) != TYPE_DICTIONARY:
			u["flags"] = {}
		var flags: Dictionary = u.flags
		var mine: Array = flags.get(F_EXTRA_MINE, [])
		var extra: Array = (flags.get(F_DOCTRINE_EXTRA, []) as Array).duplicate()
		for d in mine:
			extra.erase(d)
		var add: Array = want.get(str(uid), [])
		var added: Array = []
		for d in add:
			if not d in extra:
				extra.append(d)
				added.append(d)
		if extra.is_empty():
			flags.erase(F_DOCTRINE_EXTRA)
		else:
			flags[F_DOCTRINE_EXTRA] = extra
		if added.is_empty():
			flags.erase(F_EXTRA_MINE)
		else:
			flags[F_EXTRA_MINE] = added


# ===========================================================================
# ACTIVATED ABILITIES — ability cards in the stratagem-window framework
# ===========================================================================

const WINDOW_ABILITIES := {
	"command_phase_main": ["strategic_acumen", "priority_target_identified", "helix_gauntlet"],
	"phase_start": ["teleport_homer", "forward_assault_warsuit", "author_of_the_codex", "thunderous_force",
		"soul_sight", "omni_scramblers", "might_of_heroes"],
	"unit_selected_to_move": ["master_of_the_forge", "blessings_of_the_omnissiah"],
	"unit_ended_normal_move": ["assault_ramp", "aerial_assault", "thunderhawk_cluster_bombs", "master_of_the_forge", "blessings_of_the_omnissiah"],
	"unit_ended_advance_move": ["thunderhawk_cluster_bombs", "master_of_the_forge", "blessings_of_the_omnissiah"],
	"unit_selected_to_shoot": ["thunderous_force", "soul_sight", "catechism_of_fire"],
	"unit_has_shot": ["hailstrike", "driven_from_cover"],
	"enemy_ended_move": ["evade_and_survive"],
	"enemy_targets_unit_shooting": ["shrouding"],
	"enemy_targets_unit_fight": ["shrouding", "bladeguard"],
	"unit_selected_to_fight": ["bladeguard", "finest_hour", "might_of_heroes"],
	"fight_phase_end": ["parabolic_jetleap"],
	"sm11e_drop_pod_landed": ["drop_pod_assault"],
}

const EFFECT_TEXT := {
	"strategic_acumen": "Select one combat doctrine: it is active for this unit until the start of your next Command phase.",
	"priority_target_identified": "Once per battle: select one visible terrain feature — until the end of the turn, an enemy unit within it has +3\" detection range.",
	"helix_gauntlet": "This unit heals D3 wounds.",
	"teleport_homer": "Once per battle: set up this unit's Teleport Homer token. Rapid Ingress on this unit can use it (-1 CP; set up within 3\" of it, not within 8\" of an enemy unit). An enemy unit ending a move within 1\" removes it.",
	"forward_assault_warsuit": "Select one enemy unit to be this unit's mark: its attacks that target the mark re-roll wound rolls of 1. Re-selected each time the mark is destroyed.",
	"author_of_the_codex": "Select one visible friendly ADEPTUS ASTARTES unit within 12\" and one combat doctrine: it is active for that unit in addition to its other doctrines until the start of your next Command phase.",
	"thunderous_force": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). This unit's ranged attacks have +6\" Range this phase.",
	"soul_sight": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). Select one visible enemy unit: ranged attacks that target it have [IGNORES COVER] this phase.",
	"omni_scramblers": "Select one visible enemy unit within 18\": it is detected (+3\" detection range) this phase.",
	"might_of_heroes": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). This unit's melee attacks have +2 S this phase.",
	"master_of_the_forge": "Select one friendly ADEPTUS ASTARTES VEHICLE model within 3\": it heals 3 wounds and its attacks ignore modifiers to BS, hit rolls and wound rolls until the start of your next Movement phase.",
	"blessings_of_the_omnissiah": "Select one friendly ADEPTUS ASTARTES VEHICLE model within 3\": it heals D3 wounds and its attacks ignore modifiers to hit rolls and wound rolls until the start of your next Movement phase.",
	"assault_ramp": "Units embarked within this unit can make an assault disembark move.",
	"aerial_assault": "Embarked units whose every model has Deep Strike can make an assault disembark move.",
	"thunderhawk_cluster_bombs": "Select one enemy unit this unit moved over and roll six D6: each 3+ inflicts 1 mortal wound.",
	"catechism_of_fire": "Select one visible enemy unit: this unit's ranged attacks that target it have [DEVASTATING WOUNDS].",
	"hailstrike": "Select one enemy unit hit by those attacks: friendly ADEPTUS ASTARTES units' ranged attacks that target it have [IGNORES COVER] this phase.",
	"driven_from_cover": "Select one enemy unit hit by those attacks: friendly ADEPTUS ASTARTES units' ranged attacks that target it have [IGNORES COVER] this phase.",
	"evade_and_survive": "Once per phase: that enemy unit ended a move within 8\" — this unengaged unit can make a normal move of up to D3+3\".",
	"shrouding": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). Attacks that target this unit have -1 to hit until the end of the phase.",
	"bladeguard": "Once per turn: +1 to hit for this unit's melee attacks, or -1 to hit for attacks that target this unit, until the end of the phase.",
	"finest_hour": "Once per battle: this model's melee attacks have +3 A and [DEVASTATING WOUNDS] this phase.",
	"parabolic_jetleap": "This unit is unengaged: place it in strategic reserves.",
	"drop_pod_assault": "The Drop Pod is set up: every unit embarked within it must disembark (assault disembark move), set up more than 8\" away from all enemy units.",
}

const REOFFER_WINDOWS := ["phase_start", "command_phase_main"]
const REOFFER_IF_ABILITY_LEFT := ["unit_selected_to_move", "unit_ended_normal_move", "unit_ended_advance_move",
	"unit_selected_to_shoot", "unit_has_shot", "unit_selected_to_fight", "fight_phase_end"]

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

## ScenarioRunner policy ("sm_abilities_a": true opts in); never set outside a scenario run.
static var offers_suppressed := false

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if not _edition_11() or offers_suppressed or not Common.is_sm_army(player):
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
		_log("window %s P%d — ability offers %s" % [window_id, player, str(offers.map(func(o): return o.name))])
	return offers

## "Start of the phase" window entries for BasePhase.enter_phase (active
## player first; never a player already queued). Not in networked games.
static func phase_start_entries(phase: int, existing: Array = []) -> Array:
	var out: Array = []
	if not _edition_11() or offers_suppressed or not phase in [PH_COMMAND, PH_MOVEMENT, PH_SHOOTING, PH_CHARGE, PH_FIGHT]:
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

static func _enemies_in_range_visible(from_id: String, player: int, range_in: float, need_visible: bool = true) -> Array:
	var out: Array = []
	for eid in Common.enemy_heads(player):
		if range_in < 999.0 and _dist(from_id, str(eid)) > range_in + 0.001:
			continue
		if need_visible and not _visible(from_id, str(eid)):
			continue
		out.append(str(eid))
	return _sorted_by_distance(from_id, out)

static func _healable(unit_id: String) -> bool:
	for gid in group(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or int(m.get("current_wounds", m.get("wounds", 1))) < int(m.get("wounds", 1)):
				return true
	return false

static func _doctrine_variants() -> Array:
	var out: Array = []
	for d in Common.DOCTRINES:
		out.append({"id": str(d), "label": str(Common.DOCTRINE_LABELS[d])})
	return out

## AI doctrine pick: assault when an enemy is within 12" and the unit has
## melee weapons, devastator when it has ranged weapons, else tactical.
static func _ai_doctrine(unit_id: String) -> String:
	var owner := int(Common.unit(unit_id).get("owner", 0))
	var near := false
	for eid in Common.enemy_heads(owner):
		if _dist(unit_id, str(eid)) <= 12.0:
			near = true
	if _engaged(unit_id):
		return "tactical"
	if near and Common.group_has_melee_weapons(unit_id):
		return "assault"
	if Common.group_has_ranged_weapons(unit_id):
		return "devastator"
	return "tactical"

static func needs_mark(holder_id: String) -> bool:
	var flags: Dictionary = Common.unit(holder_id).get("flags", {})
	var mk := str(flags.get(F_MARK, ""))
	if mk != "":
		return not Common.is_alive(Common.unit(mk))
	return _round() == 1 and not bool(flags.get(F_MARK_DONE, false))

static func _threat(unit_id: String) -> float:
	var s := 0.0
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		s += float(u.get("meta", {}).get("points", 0))
		if Common.has_keyword(u, "CHARACTER"):
			s += 50.0
	return s

static func _blessing_candidates(player: int, holder: String) -> Array:
	var cands: Array = []
	for vid in Common.state().get("units", {}):
		var v := Common.unit(str(vid))
		if int(v.get("owner", 0)) != player or not Common.has_keyword(v, "VEHICLE") or not Common.has_keyword(v, KW_AA) or not Common.is_on_battlefield(v):
			continue
		if str(v.get("flags", {}).get(F_BLESS_PHASE, "")) == phase_key():
			continue
		if Common.unit_distance_inches(Common.unit(holder), v) <= BLESS_RANGE_IN + 0.001:
			cands.append(str(vid))
	return cands

## Terrain features (id, label) — every piece on the battlefield; the ones
## with enemy units in them first.
static func _terrain_options(player: int) -> Array:
	var out: Array = []
	var tm = Common.autoload("TerrainManager")
	if tm == null:
		return out
	var counts := {}
	for eid in Common.enemy_heads(player):
		for pid in terrain_pieces_unit_within(str(eid)):
			counts[pid] = int(counts.get(pid, 0)) + 1
	for piece in tm.terrain_features:
		var pid := str(piece.get("id", ""))
		if pid == "":
			continue
		var c := Vector2.ZERO
		var poly = piece.get("polygon", [])
		var n := 0
		for v in poly:
			c += Vector2(float(v.x), float(v.y))
			n += 1
		if n > 0:
			c /= float(n)
		var kind := str(piece.get("type", piece.get("name", "terrain")))
		var lbl := "%s %s at %d\", %d\"%s" % [kind.capitalize(), pid, roundi(c.x / PX_PER_INCH), roundi(c.y / PX_PER_INCH),
			(" — %d enemy unit(s) within" % int(counts[pid])) if counts.has(pid) else ""]
		out.append({"id": pid, "label": lbl, "enemies": int(counts.get(pid, 0))})
	out.sort_custom(func(a, b): return int(a.enemies) > int(b.enemies))
	return out

## Enemy units a straight move from the recorded start positions to the end
## positions passed over (any part of a base within the swept base of a
## moving model — the straight-line path is used).
static func moved_over_enemies(unit_id: String, from_positions: Dictionary) -> Array:
	var out: Array = []
	var u := Common.unit(unit_id)
	var owner := int(u.get("owner", 0))
	var models: Array = u.get("models", [])
	for i in range(models.size()):
		var mm: Dictionary = models[i]
		if not mm.get("alive", true) or mm.get("position", null) == null:
			continue
		var key := str(mm.get("id", "m%d" % (i + 1)))
		var fp = from_positions.get(key, from_positions.get(str(i), null))
		if fp == null:
			continue
		var a := Vector2(float(fp.x), float(fp.y))
		var b := Vector2(float(mm.position.x), float(mm.position.y))
		var r := float(mm.get("base_mm", 32)) / 25.4 / 2.0 * PX_PER_INCH
		var meas = Common.autoload("Measurement")
		if meas and meas.has_method("base_extent_px"):
			r = float(meas.base_extent_px(mm))
		for eid in Common.enemy_heads(owner):
			if str(eid) in out:
				continue
			for gid in group(str(eid)):
				for em in Common.unit(str(gid)).get("models", []):
					if not em.get("alive", true) or em.get("position", null) == null:
						continue
					var ep := Vector2(float(em.position.x), float(em.position.y))
					var er := float(em.get("base_mm", 32)) / 25.4 / 2.0 * PX_PER_INCH
					var cp := Geometry2D.get_closest_point_to_segment(ep, a, b)
					if cp.distance_to(ep) <= r + er and not str(eid) in out:
						out.append(str(eid))
	return out

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := _phase()
	var own_turn := Common.active_player() == player
	match slug:
		"strategic_acumen":
			if window_id != "command_phase_main" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "require_variant": true, "variants": _doctrine_variants(), "ai_variant": _ai_doctrine(hid)}))
		"priority_target_identified":
			if window_id != "command_phase_main" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_in_battle(hid, slug):
					continue
				var opts := _terrain_options(player)
				if opts.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "secondary": {"kind": "terrain",
					"prompt": "Priority Target Identified: select one visible terrain feature — enemy units within it have +3\" detection range until the end of the turn",
					"options": opts.map(func(o): return {"id": o.id, "label": o.label})}}))
		"helix_gauntlet":
			if window_id != "command_phase_main" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug) or not _healable(hid):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"teleport_homer":
			if window_id != "phase_start" or _round() != 1:
				return out
			for hid in _holders(player, slug, false):
				var f: Dictionary = Common.unit(hid).get("flags", {})
				if bool(f.get(F_HOMER_DONE, false)) or used_in_battle(hid, slug):
					continue
				var spots := homer_spots(player)
				if spots.is_empty():
					continue
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid), "secondary": {"kind": "spot",
					"prompt": "Teleport Homer: where is %s's Teleport Homer token set up?" % Common.unit_name(hid),
					"options": spots.map(func(s): return {"id": s.id, "label": s.label})}}))
		"forward_assault_warsuit":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug, false):
				if not needs_mark(hid):
					continue
				var cands: Array = _all_enemy_heads(player)
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid),
					"secondary": _unit_options(cands, "Forward Assault Warsuit: select one enemy unit to be %s's mark" % Common.unit_name(hid))}))
		"author_of_the_codex":
			if window_id != "phase_start" or phase != PH_MOVEMENT or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var cands: Array = []
				for fid in Common.friendly_heads(player):
					if not Common.group_has_keyword(str(fid), KW_AA) or not Common.has_combat_doctrines(Common.unit(str(fid))):
						continue
					if head_id(str(fid)) != head_id(hid) and (_dist(hid, str(fid)) > AUTHOR_RANGE_IN + 0.001 or not _visible(hid, str(fid))):
						continue
					cands.append(str(fid))
				if cands.is_empty():
					continue
				cands = _sorted_by_distance(hid, cands)
				var ai_pick := ""
				for c in cands:
					if head_id(str(c)) != head_id(hid):
						ai_pick = str(c)
						break
				if ai_pick == "":
					ai_pick = str(cands[0])
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid), "require_variant": true,
					"variants": _doctrine_variants(), "ai_variant": _ai_doctrine(ai_pick),
					"secondary": _unit_options(cands, "Author of the Codex: select one visible friendly ADEPTUS ASTARTES unit within 12\"")}))
		"thunderous_force", "soul_sight":
			if not own_turn or phase != PH_SHOOTING:
				return out
			if window_id == "unit_selected_to_shoot":
				var shooter := str(ctx.get("unit_id", ""))
				if shooter == "" or group_holder(shooter, slug) == "":
					return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if not _psychic_ready(hid, slug):
					continue
				if slug == "soul_sight":
					var cands := _enemies_in_range_visible(hid, player, 9999.0)
					if cands.is_empty():
						continue
					cands.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
					out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid),
						"secondary": _unit_options(cands, "Soul Sight: select one visible enemy unit — ranged attacks that target it have [IGNORES COVER] this phase")}))
				else:
					out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid)}))
		"omni_scramblers":
			if window_id != "phase_start" or phase != PH_SHOOTING or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var cands := _enemies_in_range_visible(hid, player, OMNI_RANGE_IN)
				if cands.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid,
					"secondary": _unit_options(cands, "Omni-scramblers: select one visible enemy unit within 18\" — it is detected (+3\" detection range)")}))
		"might_of_heroes":
			if phase != PH_FIGHT:
				return out
			if window_id == "unit_selected_to_fight":
				var fighter := str(ctx.get("unit_id", ""))
				if fighter == "" or group_holder(fighter, slug) == "":
					return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_fight" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if not _psychic_ready(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid)}))
		"master_of_the_forge", "blessings_of_the_omnissiah":
			if not own_turn or phase != PH_MOVEMENT:
				return out
			var mover := str(ctx.get("unit_id", ""))
			var hid := group_holder(mover, slug) if mover != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var cands := _blessing_candidates(player, hid)
			if cands.is_empty():
				return out
			out.append(_entry(head_id(mover), {"holder": hid,
				"secondary": _unit_options(cands, "%s: select one friendly ADEPTUS ASTARTES VEHICLE model within 3\" of %s" % [display(slug), Common.unit_name(hid)])}))
		"assault_ramp", "aerial_assault":
			if window_id != "unit_ended_normal_move" or not own_turn or phase != PH_MOVEMENT:
				return out
			var uid := str(ctx.get("unit_id", ""))
			if uid == "" or not has_id(uid, slug) or int(Common.unit(uid).get("owner", 0)) != player or used_this_phase(uid, slug):
				return out
			var emb := _embarked_units(uid)
			if slug == "aerial_assault":
				var gs = Common.game_state()
				emb = emb.filter(func(e): return gs == null or bool(gs.unit_has_deep_strike(str(e))))
			if emb.is_empty():
				return out
			out.append(_entry(uid, {"holder": uid}))
		"thunderhawk_cluster_bombs":
			if not window_id in ["unit_ended_normal_move", "unit_ended_advance_move"] or not own_turn or phase != PH_MOVEMENT:
				return out
			var uid2 := str(ctx.get("unit_id", ""))
			if uid2 == "" or not has_id(uid2, slug) or used_this_phase(uid2, slug):
				return out
			var from: Dictionary = ctx.get("sm11e_from_positions", {})
			var over := moved_over_enemies(uid2, from)
			if over.is_empty():
				return out
			over.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
			out.append(_entry(uid2, {"holder": uid2,
				"secondary": _unit_options(over, "Thunderhawk Cluster Bombs: select one enemy unit this unit moved over")}))
		"catechism_of_fire":
			if window_id != "unit_selected_to_shoot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter2 := str(ctx.get("unit_id", ""))
			var hid2 := group_holder(shooter2, slug) if shooter2 != "" else ""
			if hid2 == "" or used_this_phase(hid2, slug):
				return out
			var cands2 := _enemies_in_range_visible(hid2, player, 9999.0)
			if cands2.is_empty():
				return out
			var planned: Array = ctx.get("planned_target_unit_ids", [])
			cands2.sort_custom(func(a, b): return int(head_id(str(a)) in planned) > int(head_id(str(b)) in planned))
			out.append(_entry(head_id(shooter2), {"holder": hid2,
				"secondary": _unit_options(cands2, "Catechism of Fire: select one visible enemy unit — this unit's ranged attacks that target it have [DEVASTATING WOUNDS]")}))
		"hailstrike", "driven_from_cover":
			if window_id != "unit_has_shot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter3 := str(ctx.get("unit_id", ""))
			var hid3 := group_holder(shooter3, slug) if shooter3 != "" else ""
			if hid3 == "" or used_this_phase(hid3, slug):
				return out
			var cands3: Array = []
			for tid in ctx.get("hit_unit_ids", []):
				var h := head_id(str(tid))
				var hu := Common.unit(h)
				if int(hu.get("owner", 0)) == player or not Common.is_alive(hu) or h in cands3:
					continue
				cands3.append(h)
			if cands3.is_empty():
				return out
			cands3.sort_custom(func(a, b): return _threat(str(a)) > _threat(str(b)))
			out.append(_entry(head_id(shooter3), {"holder": hid3,
				"secondary": _unit_options(cands3, "%s: select one enemy unit hit by those attacks — friendly ADEPTUS ASTARTES ranged attacks that target it have [IGNORES COVER]" % display(slug))}))
		"evade_and_survive":
			if window_id != "enemy_ended_move" or own_turn or phase != PH_MOVEMENT:
				return out
			var mover2 := str(ctx.get("enemy_unit_id", ""))
			if mover2 == "":
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug) or _engaged(hid):
					continue
				if _dist(hid, mover2) > EVADE_RANGE_IN + 0.001:
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"shrouding":
			if own_turn or not window_id in ["enemy_targets_unit_shooting", "enemy_targets_unit_fight"]:
				return out
			var targeted: Array = ctx.get("target_unit_ids", [])
			for hid in _holders(player, slug):
				if not Common.group_in(hid, targeted) and not head_id(hid) in targeted:
					continue
				if not _psychic_ready(hid, slug) or _live(_gflag(hid, F_SHROUDED)):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"bladeguard":
			if phase != PH_FIGHT:
				return out
			var unit_ids: Array = []
			if window_id == "unit_selected_to_fight":
				unit_ids = [str(ctx.get("unit_id", ""))]
			elif window_id == "enemy_targets_unit_fight":
				unit_ids = ctx.get("target_unit_ids", [])
			for tu in unit_ids:
				var hid4 := group_holder(str(tu), slug)
				if hid4 == "" or int(Common.unit(hid4).get("owner", 0)) != player or used_this_turn(hid4, slug):
					continue
				if out.any(func(e): return str(e.get("holder", "")) == hid4):
					continue
				out.append(_entry(head_id(hid4), {"holder": hid4, "require_variant": true,
					"variants": [{"id": "attack", "label": "+1 to hit (melee)"}, {"id": "defend", "label": "-1 to hit against us"}],
					"ai_variant": "attack" if window_id == "unit_selected_to_fight" else "defend"}))
		"finest_hour":
			if window_id != "unit_selected_to_fight" or phase != PH_FIGHT:
				return out
			var fighter2 := str(ctx.get("unit_id", ""))
			for gid in group(fighter2):
				var g := Common.unit(str(gid))
				if int(g.get("owner", 0)) != player or not has(g, slug) or used_in_battle(str(gid), slug):
					continue
				out.append(_entry(head_id(fighter2), {"holder": str(gid), "label": Common.unit_name(str(gid))}))
		"drop_pod_assault":
			if window_id != "sm11e_drop_pod_landed":
				return out
			var pod := str(ctx.get("unit_id", ""))
			if pod == "" or not has_id(pod, slug) or int(Common.unit(pod).get("owner", 0)) != player or _embarked_units(pod).is_empty():
				return out
			out.append(_entry(pod, {"holder": pod, "label": Common.unit_name(pod)}))
		"parabolic_jetleap":
			if window_id != "fight_phase_end" or own_turn or phase != PH_FIGHT:
				return out
			for hid in _holders(player, slug):
				if _engaged(hid) or used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
	return out

static func can_use(player: int, sid: String, target_unit_id: String, context: Dictionary) -> Dictionary:
	var slug := slug_of(sid)
	for t in _targets(slug, player, str(context.get("window_id", "")), context):
		if str(t.get("unit_id", "")) == target_unit_id:
			return {"can_use": true, "reason": ""}
	return {"can_use": false, "reason": "%s cannot be used on %s now" % [display(slug), Common.unit_name(target_unit_id)]}

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
			return {"success": false, "error": "%s needs a valid selection" % display(slug), "diffs": []}
	var variant := str(context.get("variant_id", ""))
	if bool(entry.get("require_variant", false)):
		var vok := false
		for v in entry.get("variants", []):
			if str(v.get("id", "")) == variant:
				vok = true
		if not vok:
			return {"success": false, "error": "%s needs an option (%s)" % [display(slug), ", ".join(PackedStringArray(entry.get("variants", []).map(func(v): return str(v.get("label", "")))))], "diffs": []}
	var holder := str(entry.get("holder", target_unit_id))
	var res := _apply(slug, player, target_unit_id, holder, secondary, variant, context)
	var diffs: Array = res.get("diffs", [])
	var gs = Common.game_state()
	if not diffs.is_empty() and gs:
		gs.apply_state_changes(diffs)
	if str(res.get("post", "")) == "extra_doctrines":
		_apply_extra_doctrines()
	var log_text := str(res.get("log", ""))
	if log_text != "":
		_log(log_text)
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

## Mortal wounds: the bodyguard first, spilling to the Attached unit's
## characters; FNP via RulesEngine.apply_mortal_wounds.
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

## Healing (a wounded model first; with none wounded, a destroyed model
## returns with 1 wound — the engine's heal convention) over the Attached unit.
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

## Per-unit doctrine (Strategic Acumen): every component of the Attached unit.
static func _unit_doctrine_diffs(unit_id: String, doctrine: String, player: int) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_UNIT_DOCTRINE], "value": doctrine})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_UNIT_DOCTRINE_EXPIRES], "value": player})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_ACUMEN], "value": {"player": player}})
	return diffs

static func _apply(slug: String, player: int, uid: String, holder: String, secondary: String, variant: String, ctx: Dictionary) -> Dictionary:
	var name := Common.group_label(uid)
	match slug:
		"strategic_acumen":
			var diffs: Array = _unit_doctrine_diffs(uid, variant, player)
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Strategic Acumen (%s): %s is active for %s until the start of your next Command phase" % [
				Common.unit_name(holder), str(Common.DOCTRINE_LABELS.get(variant, variant)), name]}
		"priority_target_identified":
			_mark_battle_use(holder, slug)
			var val := {"feature_id": secondary, "turn_key": _turn_key(), "player": player}
			return {"diffs": [{"op": "set", "path": "factions.%d.%s" % [player, FK_PRIORITY], "value": val}],
				"log": "Priority Target Identified (once per battle): terrain feature %s is identified until the end of the turn — enemy units within it have +3\" detection range" % secondary}
		"helix_gauntlet":
			var d3 := int(Common.roll_dice(1, 3)[0])
			var h := heal_diffs(uid, d3)
			var diffs2: Array = h.diffs
			diffs2.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs2, "log": "Helix Gauntlet: %s heals D3 = %d wound(s) (%d restored, %d model(s) returned)" % [name, d3, int(h.healed), int(h.revived)]}
		"teleport_homer":
			var spot := {}
			for s in homer_spots(player):
				if str(s.id) == secondary:
					spot = s
			_mark_battle_use(holder, slug)
			var diffs3: Array = Common.set_flag_diffs([holder], F_HOMER, {"x": float(spot.get("x", 0.0)), "y": float(spot.get("y", 0.0)), "player": player, "label": str(spot.get("label", ""))})
			diffs3.append_array(Common.set_flag_diffs([holder], F_HOMER_DONE, true))
			return {"diffs": diffs3, "log": "Teleport Homer: %s's token is set up — %s (%d\", %d\")" % [Common.unit_name(holder), str(spot.get("label", secondary)),
				roundi(float(spot.get("x", 0.0)) / PX_PER_INCH), roundi(float(spot.get("y", 0.0)) / PX_PER_INCH)]}
		"forward_assault_warsuit":
			var diffs4: Array = Common.set_flag_diffs([holder], F_MARK, secondary)
			diffs4.append_array(Common.set_flag_diffs([holder], F_MARK_DONE, true))
			return {"diffs": diffs4, "log": "Forward Assault Warsuit: %s is %s's mark — its attacks against it re-roll wound rolls of 1" % [Common.group_label(secondary), Common.unit_name(holder)]}
		"author_of_the_codex":
			var diffs5: Array = []
			for gid in group(secondary):
				diffs5.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_AUTHOR], "value": {"doctrine": variant, "player": player}})
			diffs5.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs5, "post": "extra_doctrines", "log": "Author of the Codex: %s is active for %s in addition to its other doctrines until the start of your next Command phase" % [
				str(Common.DOCTRINE_LABELS.get(variant, variant)), Common.group_label(secondary)]}
		"thunderous_force":
			var pr := _psychic_roll(holder, slug)
			var diffs6: Array = pr.diffs
			diffs6.append_array(Common.set_flag_diffs(group(holder), F_THUNDEROUS, phase_key()))
			return {"diffs": diffs6, "log": "Thunderous Force (%s): %s — %s's ranged attacks have +6\" Range this phase" % [Common.unit_name(holder), pr.note, name]}
		"soul_sight":
			var pr2 := _psychic_roll(holder, slug)
			var diffs7: Array = pr2.diffs
			diffs7.append_array(Common.set_flag_diffs(group(secondary), F_SOUL_SIGHT, phase_key()))
			return {"diffs": diffs7, "log": "Soul Sight (%s): %s — ranged attacks that target %s have [IGNORES COVER] this phase" % [Common.unit_name(holder), pr2.note, Common.group_label(secondary)]}
		"omni_scramblers":
			var diffs8: Array = Common.set_flag_diffs(group(secondary), F_DETECTED, {"player": player, "phase_key": phase_key()})
			diffs8.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs8, "log": "Omni-scramblers: %s is detected (+3\" detection range) until the end of the phase" % Common.group_label(secondary)}
		"might_of_heroes":
			var pr3 := _psychic_roll(holder, slug)
			var diffs9: Array = pr3.diffs
			diffs9.append_array(Common.set_flag_diffs(group(holder), F_MIGHT, phase_key()))
			return {"diffs": diffs9, "log": "Might of Heroes (%s): %s — %s's melee attacks have +2 S this phase" % [Common.unit_name(holder), pr3.note, name]}
		"master_of_the_forge", "blessings_of_the_omnissiah":
			var amount := 3 if slug == "master_of_the_forge" else int(Common.roll_dice(1, 3)[0])
			var h2 := heal_diffs(secondary, amount)
			var diffs10: Array = h2.diffs
			diffs10.append(_phase_use_diff(holder, slug))
			diffs10.append_array(Common.set_flag_diffs([secondary], F_BLESS_PHASE, phase_key()))
			diffs10.append_array(Common.set_flag_diffs([secondary], F_BLESSED, {"player": player, "phase_key": phase_key(), "bs": slug == "master_of_the_forge", "source": display(slug)}))
			return {"diffs": diffs10, "log": "%s (%s): %s heals %s%d (%d wound(s) restored); its attacks ignore modifiers to %shit and wound rolls until the start of your next Movement phase" % [
				display(slug), Common.unit_name(holder), Common.unit_name(secondary), "" if slug == "master_of_the_forge" else "D3 = ", amount, int(h2.healed),
				"BS, " if slug == "master_of_the_forge" else ""]}
		"assault_ramp", "aerial_assault":
			var flag := F_ASSAULT_RAMP if slug == "assault_ramp" else F_AERIAL
			var diffs11: Array = Common.set_flag_diffs([uid], flag, phase_key())
			diffs11.append(_phase_use_diff(uid, slug))
			return {"diffs": diffs11, "followup": {"type": "assault_disembark", "transport_id": uid, "source": display(slug)},
				"log": "%s: units embarked within %s can make an assault disembark move" % [display(slug), Common.unit_name(uid)]}
		"thunderhawk_cluster_bombs":
			var rolls: Array = Common.roll_dice(6)
			var mw := 0
			for r in rolls:
				if int(r) >= 3:
					mw += 1
			var diffs12: Array = [_phase_use_diff(holder, slug)]
			var res := _mortal_wounds(secondary, mw)
			diffs12.append_array(res.diffs)
			return {"diffs": diffs12, "log": "Thunderhawk Cluster Bombs: six D6 %s against %s — %d mortal wound(s) (%d model(s) destroyed)" % [str(rolls), Common.group_label(secondary), mw, int(res.casualties)]}
		"catechism_of_fire":
			var diffs13: Array = Common.set_flag_diffs(group(holder), F_CATECHISM, {"target": secondary, "phase_key": phase_key()})
			diffs13.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs13, "log": "Catechism of Fire: %s's ranged attacks that target %s have [DEVASTATING WOUNDS]" % [name, Common.group_label(secondary)]}
		"hailstrike", "driven_from_cover":
			var diffs14: Array = Common.set_flag_diffs(group(secondary), F_DRIVEN, {"player": player, "phase_key": phase_key(), "source": display(slug)})
			diffs14.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs14, "log": "%s: friendly ADEPTUS ASTARTES ranged attacks that target %s have [IGNORES COVER] this phase" % [display(slug), Common.group_label(secondary)]}
		"evade_and_survive":
			var r1 := int(Common.roll_dice(1, 3)[0])
			var dist := r1 + 3
			return {"diffs": [_phase_use_diff(holder, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(dist), "source": "Evade and Survive"},
				"log": "Evade and Survive: %s rolls D3+3 = %d+3 = %d — normal move of up to %d\"" % [name, r1, dist, dist]}
		"shrouding":
			var pr4 := _psychic_roll(holder, slug)
			var diffs15: Array = pr4.diffs
			diffs15.append_array(Common.set_flag_diffs(group(holder), F_SHROUDED, phase_key()))
			return {"diffs": diffs15, "log": "Shrouding (%s): %s — attacks that target %s have -1 to hit until the end of the phase" % [Common.unit_name(holder), pr4.note, name]}
		"bladeguard":
			var diffs16: Array = Common.set_flag_diffs(group(holder), F_BLADEGUARD, {"mode": variant, "phase_key": phase_key()})
			diffs16.append(_turn_use_diff(holder, slug))
			return {"diffs": diffs16, "log": "Bladeguard (once per turn): %s" % (
				("%s's melee attacks have +1 to hit this phase" % name) if variant == "attack" else ("attacks that target %s have -1 to hit this phase" % name))}
		"finest_hour":
			_mark_battle_use(holder, slug)
			return {"diffs": Common.set_flag_diffs([holder], F_FINEST_HOUR, phase_key()),
				"log": "Finest Hour (once per battle): %s's melee attacks have +3 A and [DEVASTATING WOUNDS] this phase" % Common.unit_name(holder)}
		"drop_pod_assault":
			var dp_diffs: Array = Common.set_flag_diffs([uid], F_ASSAULT_RAMP, phase_key())
			return {"diffs": dp_diffs, "followup": {"type": "assault_disembark", "transport_id": uid, "source": "Drop Pod Assault"},
				"log": "Drop Pod Assault: the units embarked within %s disembark (assault disembark move, more than 8\" from enemy units)" % Common.unit_name(uid)}
		"parabolic_jetleap":
			var diffs17: Array = [_phase_use_diff(holder, slug)]
			diffs17.append_array(strategic_reserves_diffs(uid))
			return {"diffs": diffs17, "log": "Parabolic Jetleap: %s is placed in strategic reserves" % name}
	return {"diffs": []}

## 20.02: the unit (every component of the Attached unit) leaves the battlefield into strategic reserves.
static func strategic_reserves_diffs(unit_id: String) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if u.is_empty():
			continue
		diffs.append({"op": "set", "path": "units.%s.status" % gid, "value": ST_IN_RESERVES})
		diffs.append({"op": "set", "path": "units.%s.reserve_type" % gid, "value": "strategic_reserves"})
		diffs.append({"op": "set", "path": "units.%s.flags.repositioned_to_reserves" % gid, "value": true})
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	return diffs

## After a use whose effect is a doctrine grant, rebuild the per-unit additional doctrines.
static func after_use_refresh() -> void:
	_apply_extra_doctrines()


# ===========================================================================
# AI — synchronous scores (AIDecisionMaker.decide_window_stratagem, threshold
# 1.0 for abilities): the window never waits on the AI.
# ===========================================================================

static func ai_score(player: int, sid: String, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var slug := slug_of(sid)
	match slug:
		"drop_pod_assault", "helix_gauntlet", "hailstrike", "driven_from_cover", "catechism_of_fire", "thunderhawk_cluster_bombs", "forward_assault_warsuit":
			return 3.0
		"master_of_the_forge", "blessings_of_the_omnissiah", "bladeguard", "might_of_heroes":
			if slug == "might_of_heroes" and not _engaged(target_unit_id):
				return 0.0
			return 2.0
		"strategic_acumen", "author_of_the_codex", "omni_scramblers", "soul_sight", "shrouding":
			return 1.5
		"thunderous_force":
			# Worth the psychic roll only when an enemy is out of range now but within +6".
			return 1.5 if _thunderous_helps(target_unit_id, player) else 0.0
		"priority_target_identified":
			var opts := _terrain_options(player)
			return 1.5 if not opts.is_empty() and int(opts[0].enemies) > 0 else 0.0
		"finest_hour":
			for eid in Common.engaged_enemy_ids(target_unit_id):
				if Common.group_has_any_keyword(str(eid), ["CHARACTER", "MONSTER", "VEHICLE"]) or Common.group_points(str(eid)) >= 150:
					return 2.0
			return 0.0
		"assault_ramp", "aerial_assault":
			for eid in Common.enemy_heads(player):
				if _dist(target_unit_id, str(eid)) <= 12.0:
					return 2.0
			return 0.0
		"teleport_homer", "evade_and_survive", "parabolic_jetleap":
			return 0.0  # repositioning is a plan-level decision
	return 0.0

static func _thunderous_helps(unit_id: String, player: int) -> bool:
	var re = Common.rules()
	if re == null:
		return false
	var max_r := 0.0
	for gid in group(unit_id):
		var w: Dictionary = re.get_unit_weapons(str(gid), Common.state())
		for mid in w:
			for wid in w[mid]:
				if str(wid).ends_with("_melee"):
					continue
				var prof: Dictionary = re.get_weapon_profile(str(wid), Common.state())
				max_r = maxf(max_r, float(str(prof.get("range", 0)).to_float()))
	if max_r <= 0.0:
		return false
	var best := INF
	for eid in Common.enemy_heads(player):
		best = minf(best, _dist(unit_id, str(eid)))
	return best > max_r and best <= max_r + THUNDEROUS_RANGE_IN
