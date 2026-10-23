extends RefCounted

## SMAbilitiesB — Codex: Space Marines (11e), DATASHEET and WARGEAR abilities
## of the generic Space Marine datasheets of package M4b (WP-M4b):
##
##   Intercessor Squad, Incursor Squad, Scout Squad, Bladeguard Ancient,
##   Captain in Gravis Armour, Chaplain, Heavy Intercessor Squad, Terminator
##   Squad, Lieutenant, Assault Intercessor Squad, Storm Speeder Thunderstrike,
##   Chief Librarian Tigurius, Gladiator Reaper, Eliminator Squad, Gladiator
##   Valiant, Hellblaster Squad, Aggressor Squad, Adrax Agatone, Darnath
##   Lysander, Land Raider Redeemer, Sternguard Veteran Squad, Librarian,
##   Desolation Squad, Tor Garadon, Lieutenant in Phobos Armour, Impulsor,
##   Ancient in Terminator Armour, Astraeus, Captain in Phobos Armour.
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md, PLAN_SPACE_MARINES.md.
## Printed text: .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md.
## Audit + rulings: space_marines_abilities_audit_b.md, RULINGS.md (## WP-M4b).
##
## Everything is static. Engine files reach this module only through thin,
## commented hooks (one line each, "WP-M4b"):
##   RulesEngine        ork11e_ab_mods aggregator (merge_attack_mods), S > T
##                      wound penalty (Never Shall the Standard Fall), the
##                      conditional FNP (Hood of Hellfire / Psychic Hood), the
##                      per-model -1 D (Refuse to Yield), the save-roll
##                      modifier (Unyielding in the Face of the Foe), hazard
##                      rolls (Rites of Thermal Appeasement)
##   MovementPhase      Raise the Banner (end of the Movement phase), Veil of
##                      Time (advance roll 6), Flexible Asset (move keeps action
##                      eligibility), Teleport Homer (Rapid Ingress set-up)
##   ActionsManager     Tactical Mainstay / Flexible Asset (start an action)
##   DisembarkMove /    Assault Ramp (assault disembark), Rapid Disembarkation
##   TransportManager   (shock disembark after an advance)
##   TerrainManager     detection range (Chameleoline Cloaks, Special-issue Optics)
##   MissionManager     model OC (Lord of the Pyroclasts)
##   ShootingPhase      on_unit_has_shot ("until this unit has shot"), the
##                      per-weapon hit map (Suppression Fire)
##   StratagemManager   ability cards (window_offers / can_use / use), the
##                      Teleport Homer Rapid Ingress -1 CP
##   ArmyListManager    wargear at army load (Lieutenant Storm Shield, Impulsor
##                      Shield Dome / Orbital Comms Array)
##   PhaseManager       on_phase_transition (expiry)
##   BasePhase          phase_start_entries (the "start of the phase" cards)
##   AIDecisionMaker    ai_score for the cards (synchronous)
##
## Scope gate (SM-D1 + package split): a unit has one of these abilities only
## when its datasheet is one of the M4b datasheets above (by datasheet name —
## M4a / M4c own the same ability names on other datasheets, e.g. Strategic
## Acumen, Litany of Hate, Raise the Banner), the datasheet lists the ability,
## the army is a Space Marine army (SWCommon.is_sm_army) and the edition is 11.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const PX_PER_INCH := 40.0

# GameState.Phase mirror.
const PH_FORMATIONS := 0
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const ST_IN_RESERVES := 7
const ST_UNDEPLOYED := 0

const KW_AA := "ADEPTUS ASTARTES"

## The M4b datasheets (folded names, see fold()).
const DATASHEETS := ["intercessor squad", "incursor squad", "scout squad", "bladeguard ancient",
	"captain in gravis armour", "chaplain", "heavy intercessor squad", "terminator squad",
	"lieutenant", "assault intercessor squad", "storm speeder thunderstrike", "chief librarian tigurius",
	"gladiator reaper", "eliminator squad", "gladiator valiant", "hellblaster squad", "aggressor squad",
	"adrax agatone", "darnath lysander", "land raider redeemer", "sternguard veteran squad", "librarian",
	"desolation squad", "tor garadon", "lieutenant in phobos armour", "impulsor",
	"ancient in terminator armour", "astraeus", "captain in phobos armour"]

## slug -> FOLDED printed name.
const NAMES := {
	"bolter_discipline": "bolter discipline",
	"tactical_mainstay": "tactical mainstay",
	"divinator_class_auspexes": "divinator class auspexes",
	"haywire_mine": "haywire mine",
	"flexible_asset": "flexible asset",
	"raise_the_banner": "raise the banner",
	"deeds_of_legend": "deeds of legend",
	"strategic_acumen": "strategic acumen",
	"refuse_to_yield": "refuse to yield",
	"litany_of_hate": "litany of hate",
	"spiritual_leader": "spiritual leader",
	"unyielding_in_the_face_of_the_foe": "unyielding in the face of the foe",
	"teleport_homer": "teleport homer",
	"fury_of_the_first": "fury of the first",
	"demi_company_commander": "demi company commander",
	"tactical_precision": "tactical precision",
	"storm_shield": "storm shield",
	"targeted_intercession": "targeted intercession",
	"thunderstrike": "thunderstrike",
	"shattered_defences": "shattered defences",
	"chief_librarian": "chief librarian",
	"hood_of_hellfire": "hood of hellfire",
	"prescience": "prescience",
	"telepathic_assault": "telepathic assault",
	"reaping_tally": "reaping tally",
	"chameleoline_cloaks": "chameleoline cloaks",
	"special_issue_optics": "special issue optics and ammunition",
	"priority_target_acquisition": "priority target acquisition",
	"rites_of_thermal_appeasement": "rites of thermal appeasement",
	"close_quarters_firestorm": "close quarters firestorm",
	"lord_of_the_pyroclasts": "lord of the pyroclasts",
	"unto_the_anvil": "unto the anvil",
	"rampart": "rampart",
	"icon_of_obstinacy": "icon of obstinacy",
	"assault_ramp": "assault ramp",
	"wrath_of_the_machine_spirit": "wrath of the machine spirit",
	"veteran_marksmen": "veteran marksmen",
	"librarian": "librarian",
	"psychic_hood": "psychic hood",
	"veil_of_time": "veil of time",
	"force_dome": "force dome",
	"targeter_optics": "targeter optics",
	"siege_captain": "siege captain",
	"signum_array": "signum array",
	"rapid_disembarkation": "rapid disembarkation",
	"orbital_comms_array": "orbital comms array",
	"shield_dome": "shield dome",
	"never_shall_the_standard_fall": "never shall the standard fall",
	"suppression_fire": "suppression fire",
	"tactical_fluidity": "tactical fluidity",
}

## slug -> printed name (cards, logs, the UnitAbilityManager once-per-battle key).
const DISPLAY := {
	"bolter_discipline": "Bolter Discipline", "tactical_mainstay": "Tactical Mainstay",
	"divinator_class_auspexes": "Divinator-class Auspexes", "haywire_mine": "Haywire Mine",
	"flexible_asset": "Flexible Asset", "raise_the_banner": "Raise the Banner",
	"deeds_of_legend": "Deeds of Legend", "strategic_acumen": "Strategic Acumen",
	"refuse_to_yield": "Refuse to Yield", "litany_of_hate": "Litany of Hate",
	"spiritual_leader": "Spiritual Leader", "unyielding_in_the_face_of_the_foe": "Unyielding in the Face of the Foe",
	"teleport_homer": "Teleport Homer", "fury_of_the_first": "Fury of the First",
	"demi_company_commander": "Demi-company Commander", "tactical_precision": "Tactical Precision",
	"storm_shield": "Storm Shield", "targeted_intercession": "Targeted Intercession",
	"thunderstrike": "Thunderstrike", "shattered_defences": "Shattered Defences",
	"chief_librarian": "Chief Librarian", "hood_of_hellfire": "Hood of Hellfire",
	"prescience": "Prescience", "telepathic_assault": "Telepathic Assault",
	"reaping_tally": "Reaping Tally", "chameleoline_cloaks": "Chameleoline Cloaks",
	"special_issue_optics": "Special-issue Optics and Ammunition",
	"priority_target_acquisition": "Priority Target Acquisition",
	"rites_of_thermal_appeasement": "Rites of Thermal Appeasement",
	"close_quarters_firestorm": "Close-quarters Firestorm", "lord_of_the_pyroclasts": "Lord of the Pyroclasts",
	"unto_the_anvil": "Unto the Anvil", "rampart": "Rampart", "icon_of_obstinacy": "Icon of Obstinacy",
	"assault_ramp": "Assault Ramp", "wrath_of_the_machine_spirit": "Wrath of the Machine Spirit",
	"veteran_marksmen": "Veteran Marksmen", "librarian": "Librarian", "psychic_hood": "Psychic Hood",
	"veil_of_time": "Veil of Time", "force_dome": "Force Dome", "targeter_optics": "Targeter Optics",
	"siege_captain": "Siege Captain", "signum_array": "Signum Array",
	"rapid_disembarkation": "Rapid Disembarkation", "orbital_comms_array": "Orbital Comms Array",
	"shield_dome": "Shield Dome", "never_shall_the_standard_fall": "Never Shall the Standard Fall",
	"suppression_fire": "Suppression Fire", "tactical_fluidity": "Tactical Fluidity",
}

## Wargear abilities: the datasheet carries them only with the wargear (the
## roster lists the item in meta.wargear; the army converter may also list the
## ability by name).
const WARGEAR_ABILITIES := {"storm_shield": "Storm Shield", "orbital_comms_array": "Orbital Comms Array", "shield_dome": "Shield Dome"}

# --- flags (sm11e_ab_*; none uses the effect_ prefix ShootingPhase wipes) ----
const F_PHASE_USES := "sm11e_ab_phase_uses"       # {slug: phase_key}
const F_ROUND_USES := "sm11e_ab_round_uses"       # {slug: battle round}
const F_TURN_USES := "sm11e_ab_turn_uses"         # {slug: turn_key}
const F_SCANNED := "sm11e_ab_scanned"             # {player, source}: ranged attacks vs it re-roll hit 1s (end of phase)
const F_SHATTERED := "sm11e_ab_shattered"         # {player}: friendly AA ranged attacks vs it +1 AP (end of phase)
const F_SIGNUM := "sm11e_ab_signum"               # {player}: cannot have the benefit of cover (end of phase)
const F_SUPPRESSED := "sm11e_ab_suppressed"       # {player, source}: -1 to hit until the start of player's next turn
const F_OPTICS_COVER := "sm11e_ab_optics_cover"   # true: ranged attacks [IGNORES COVER] until this unit has shot
const F_OPTICS_DET := "sm11e_ab_optics_det"       # {by}: +6" detection range until unit `by` has shot
const F_INSV := "sm11e_ab_insv"                   # {slug: {player, until}}: model invuln granted (Rampart / Force Dome)
const M_INSV := "sm11e_insv"                      # model backup {slug: prev invuln}
const F_PRESCIENCE := "sm11e_ab_prescience"       # {player, prev}: +1 Sv until the start of player's next turn
const F_VEIL := "sm11e_ab_veil"                   # phase_key: the next advance roll of this unit is a 6
const F_HOMER := "sm11e_ab_homer"                 # {x, y, label}: this unit's Teleport Homer token (px)
const F_HOMER_DONE := "sm11e_ab_homer_decided"    # true once the token was set up
const F_ACUMEN := "sm11e_ab_acumen"               # player: this unit's sw11e_doctrine was written by Strategic Acumen / Demi-company Commander
const F_UNIT_DOCTRINE := "sw11e_doctrine"         # SWCommon per-unit doctrine key
const F_UNIT_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"
# Librarius budget — the SAME per-unit keys as SWAbilities11e (one budget per
# PSYKER unit, whichever module spends it; WP-M2a may re-point librarius_*).
const F_PSY_ROUND := "sw11e_psy_round"
const F_PSY_USED := "sw11e_psy_used"
const F_PSY_PHASE := "sw11e_psy_phase"
const F_PSY_PHASE_NAMES := "sw11e_psy_phase_names"
## Army-level ledger on GameState.state.players[p]: {slug: true} (once per battle, per army).
const ARMY_USES := "sm11e_ab_army_uses"
## A model's list-build marker.
const M_LIST := "sm11e_ab_list"

const SID_PREFIX := "sm11e_ab_b_"

const DIVINATOR_RANGE_IN := 18.0
const HAYWIRE_RANGE_IN := 6.0
const SPIRITUAL_RANGE_IN := 6.0
const FURY_RANGE_IN := 9.0
const FIRESTORM_RANGE_IN := 9.0
const PRIORITY_RANGE_IN := 12.0
const WRATH_RANGE_IN := 12.0
const TELEPATHIC_RANGE_IN := 24.0
const OPTICS_RANGE_IN := 24.0
const SIGNUM_RANGE_IN := 18.0
const HOMER_SETUP_IN := 3.0
const HOMER_REMOVE_IN := 1.0
const CHAMELEOLINE_DETECTION_IN := -3.0
const OPTICS_DETECTION_IN := 6.0
const FLUIDITY_FALL_BACK_IN := 6.0

## Librarius: psyker level of the datasheet abilities that grant one (the
## army files drop the printed "(psyker level N)" suffix).
const PSYKER_LEVEL_ABILITIES := {"chief librarian": 3, "librarian": 1}
## Psychic level of each psychic ability.
const PSYCHIC_LEVELS := {"prescience": 2, "telepathic_assault": 1, "veil_of_time": 1, "force_dome": 1}


# ===========================================================================
# Names / membership
# ===========================================================================

## Lower-case, apostrophes removed, a trailing "(…)" dropped, every
## non-alphanumeric character a space, spaces collapsed (SWAbilities11e.fold).
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

## The unit is one of the M4b datasheets in a Space Marine army (11e).
static func is_m4b_unit(u: Dictionary) -> bool:
	if u.is_empty() or not _edition_11():
		return false
	if not fold(str(u.get("meta", {}).get("name", ""))) in DATASHEETS:
		return false
	return Common.is_sm_army(int(u.get("owner", 0)))

## Number of `item` the roster's wargear lists ("2x Storm Shield").
static func wargear_count(unit: Dictionary, item: String) -> int:
	var n := 0
	var want := fold(item)
	for w in unit.get("meta", {}).get("wargear", []):
		for part in str(w).split(","):
			var s := str(part).strip_edges()
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

## True when the unit's datasheet lists the ability of `slug` (wargear
## abilities: or the roster took the wargear) and the rules apply to it.
static func has(u: Dictionary, slug: String) -> bool:
	var want := str(NAMES.get(slug, ""))
	if want == "" or u.is_empty() or not is_m4b_unit(u):
		return false
	for ab in u.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == want:
			return true
	if WARGEAR_ABILITIES.has(slug) and wargear_count(u, str(WARGEAR_ABILITIES[slug])) > 0:
		return true
	return false

static func has_id(unit_id: String, slug: String) -> bool:
	return has(Common.unit(unit_id), slug)

static func display(slug: String) -> String:
	return str(DISPLAY.get(slug, slug))

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
	Common.log_info("SMAbilitiesB: " + msg)

## Objectives the (Attached) unit is within range of (ids).
static func objectives_in_range(unit_id: String) -> Array:
	var out: Array = []
	for obj in Common.objectives():
		if Common.group_in_objective_range(unit_id, obj):
			out.append(str(obj.get("id", "")))
	return out

## "This unit is controlling an objective": within range of an objective its
## army controls (14.02).
static func controlled_objectives_in_range(unit_id: String) -> Array:
	var out: Array = []
	var owner := int(Common.unit(unit_id).get("owner", 0))
	for oid in objectives_in_range(unit_id):
		if Common.objective_controller(oid) == owner:
			out.append(oid)
	return out


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

static func _uses(holder_id: String, flag: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(flag, {})
	return uses if typeof(uses) == TYPE_DICTIONARY else {}

static func used_this_phase(holder_id: String, slug: String) -> bool:
	return str(_uses(holder_id, F_PHASE_USES).get(slug, "")) == _phase_key()

static func _phase_use_diff(holder_id: String, slug: String) -> Dictionary:
	var nd: Dictionary = _uses(holder_id, F_PHASE_USES).duplicate()
	nd[slug] = _phase_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_PHASE_USES], "value": nd}

static func used_this_round(holder_id: String, slug: String) -> bool:
	return int(_uses(holder_id, F_ROUND_USES).get(slug, -1)) == _round()

static func _round_use_diff(holder_id: String, slug: String) -> Dictionary:
	var nd: Dictionary = _uses(holder_id, F_ROUND_USES).duplicate()
	nd[slug] = _round()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_ROUND_USES], "value": nd}

static func used_this_turn(holder_id: String, slug: String) -> bool:
	return str(_uses(holder_id, F_TURN_USES).get(slug, "")) == _turn_key()

static func _turn_use_diff(holder_id: String, slug: String) -> Dictionary:
	var nd: Dictionary = _uses(holder_id, F_TURN_USES).duplicate()
	nd[slug] = _turn_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_TURN_USES], "value": nd}

static func _army_uses(player: int) -> Dictionary:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	return uses if typeof(uses) == TYPE_DICTIONARY else {}

## (Once per battle, per army).
static func army_used_in_battle(player: int, slug: String) -> bool:
	return bool(_army_uses(player).get(slug, false))

static func _army_use_diff(player: int, slug: String) -> Dictionary:
	var nd: Dictionary = _army_uses(player).duplicate()
	nd[slug] = true
	return {"op": "set", "path": "players.%s.%s" % [str(player), ARMY_USES], "value": nd}


# ===========================================================================
# LIBRARIUS — psyker level budget (army rule; Tigurius, Librarian)
# ===========================================================================
# "In a battle round, a friendly ADEPTUS ASTARTES PSYKER unit can use a number
# of psychic abilities whose total psychic level does not exceed that PSYKER
# unit's psyker level." WP-M2a generalises the army rule for every Space
# Marine army in parallel; until it lands this is the one place the budget is
# read and spent (librarius_can_use / librarius_record) — it keeps the SAME
# per-unit keys as SWAbilities11e, so the integrator can re-point these two
# functions at the M2a API without touching the callers.

static func is_budgeted_psyker(u: Dictionary) -> bool:
	return is_m4b_unit(u) and Common.has_keyword(u, KW_AA) and Common.has_keyword(u, "PSYKER")

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
static func librarius_can_use(unit_id: String, slug: String) -> Dictionary:
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

static func librarius_record(unit_id: String, slug: String) -> Array:
	var u := Common.unit(unit_id)
	if u.is_empty():
		return []
	var used := psychic_levels_used(u) + psychic_level(slug)
	var flags: Dictionary = u.get("flags", {})
	var names: Array = []
	if str(flags.get(F_PSY_PHASE, "")) == _phase_key():
		names = (flags.get(F_PSY_PHASE_NAMES, []) as Array).duplicate()
	names.append(slug)
	_log("Librarius — %s used %s (psychic level %d): %d/%d psyker level spent this battle round" % [
		unit_id, display(slug), psychic_level(slug), used, psyker_level(u)])
	return [
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_ROUND], "value": _round()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_USED], "value": used},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE], "value": _phase_key()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE_NAMES], "value": names},
	]

static func _psychic_ready(holder_id: String, slug: String) -> bool:
	if not librarius_can_use(holder_id, slug).ok:
		return false
	return not _group_shocked(holder_id)

## The psychic D6 (on a 1 the unit is battle-shocked) + the budget diffs.
static func _psychic_roll(holder_id: String, slug: String) -> Dictionary:
	var roll := int(Common.roll_dice(1)[0])
	var diffs: Array = librarius_record(holder_id, slug)
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
		"strength": 0, "attacks": 0, "sustained": 0, "devastating": false, "precision": false,
		"lethal": false, "ignores_cover": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

## The M4b contribution, merged INTO `m` (the aggregator result) — the one-line
## RulesEngine hook in ork11e_ab_mods.
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
	m["lethal"] = bool(m.get("lethal", false)) or c.lethal
	m["ignores_cover"] = bool(m.get("ignores_cover", false)) or c.ignores_cover
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append_array(c.sources)

static func attack_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> Dictionary:
	var m := _empty_mods()
	var actor_id := _uid(actor_unit)
	if actor_id == "" or actor_unit.is_empty():
		return m
	var target_id := _uid(target_unit)
	var target_ok := target_id != "" and not target_unit.is_empty()
	var target_head := head_id(target_id) if target_ok else ""
	var owner := int(actor_unit.get("owner", 0))

	# --- any attacker: suppressed (Suppression Fire) ---------------------------
	var sup = _gflag(actor_id, F_SUPPRESSED)
	if typeof(sup) == TYPE_DICTIONARY:
		m.hit_minus = true
		_src(m, str(sup.get("source", "Suppression Fire")), "hit", "minus_one", "this unit is suppressed (-1 to hit)")

	# --- any attacker: effects on the TARGET -----------------------------------
	if target_ok:
		if group_has(target_head, "icon_of_obstinacy"):
			m.hit_minus = true
			_src(m, "Icon of Obstinacy", "hit", "minus_one", "attacks that target this unit have -1 to hit")
		var tflags_owner := int(Common.unit(target_head).get("owner", 0))
		if not is_melee and tflags_owner != owner:
			var scanned = _gflag(target_head, F_SCANNED)
			if typeof(scanned) == TYPE_DICTIONARY and int(scanned.get("player", 0)) == owner:
				m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
				_src(m, "Divinator-class Auspexes", "hit", "reroll_ones", "the target is scanned: ranged attacks re-roll hit rolls of 1")
			var signum = _gflag(target_head, F_SIGNUM)
			if typeof(signum) == TYPE_DICTIONARY:
				m.ignores_cover = true
				_src(m, "Signum Array", "other", "ignores_cover", "the target cannot have the benefit of cover")
			var shattered = _gflag(target_head, F_SHATTERED)
			if typeof(shattered) == TYPE_DICTIONARY and int(shattered.get("player", 0)) == owner and Common.has_keyword(actor_unit, KW_AA):
				m.ap += 1
				_src(m, "Shattered Defences", "other", "ap", "friendly ADEPTUS ASTARTES ranged attacks vs that unit +1 AP")

	# Every ability below is held by an M4b component (has() checks the gate per
	# holder) — skip the work for every attacker outside a Space Marine army.
	if not Common.is_sm_army(owner):
		return m
	var charged := _group_charged(actor_id) or bool(actor_unit.get("flags", {}).get("charged_this_turn", false))
	var target_mv := target_ok and _is_mv(target_head)
	var dist := _dist(actor_id, target_head) if target_ok else INF
	var own_shooting := _phase() == PH_SHOOTING and Common.active_player() == owner

	# --- "this model" abilities (the model's own unit dict) -------------------
	if target_ok and has(actor_unit, "siege_captain") and (target_mv or Common.group_has_keyword(target_head, "FORTIFICATION")):
		m.strength += 2
		m.ap += 2
		m.damage += 2
		_src(m, "Siege Captain", "other", "strength", "target is a FORTIFICATION/MONSTER/VEHICLE unit: +2 S, AP and D")

	# --- "this unit" abilities (the whole Attached unit) -----------------------
	if not is_melee and own_shooting and group_has(actor_id, "bolter_discipline"):
		if Common.group_in_range_of_any_objective(actor_id) or (target_ok and Common.group_in_range_of_any_objective(target_head)):
			m.hit_plus = true
			_src(m, "Bolter Discipline", "hit", "plus_one", "your Shooting phase: this unit or the target is within range of an objective")
	if is_melee and group_has(actor_id, "deeds_of_legend") and Common.group_in_range_of_any_objective(actor_id):
		m.attacks += 1
		_src(m, "Deeds of Legend", "other", "attacks", "within range of an objective: melee +1 A")
	if is_melee and charged and group_has(actor_id, "litany_of_hate"):
		m.wound_plus = true
		_src(m, "Litany of Hate", "wound", "plus_one", "[LANCE]: made a charge move this turn")
	if target_ok and dist <= FURY_RANGE_IN + 0.001 and group_has(actor_id, "fury_of_the_first"):
		m.ap += 1
		_src(m, "Fury of the First", "other", "ap", "target within 9\": +1 AP")
	if target_ok and not target_mv and group_has(actor_id, "tactical_precision"):
		m.lethal = true
		_src(m, "Tactical Precision", "other", "lethal_hits", "[LETHAL HITS] vs a non-MONSTER/VEHICLE unit")
	if is_melee and charged and group_has(actor_id, "targeted_intercession"):
		m.strength += 1
		m.ap += 1
		_src(m, "Targeted Intercession", "other", "strength", "made a charge move this turn: melee +1 S and +1 AP")
	if not is_melee and target_mv and group_has(actor_id, "thunderstrike"):
		m.wound_plus = true
		_src(m, "Thunderstrike", "wound", "plus_one", "ranged attacks vs a MONSTER/VEHICLE unit +1 to wound")
	if not is_melee and target_ok and not target_mv and group_has(actor_id, "reaping_tally"):
		m.ap += 1
		_src(m, "Reaping Tally", "other", "ap", "ranged attacks vs a non-MONSTER/VEHICLE unit +1 AP")
	if not is_melee and target_ok and dist <= PRIORITY_RANGE_IN + 0.001 and group_has(actor_id, "priority_target_acquisition"):
		m.strength += 1
		_src(m, "Priority Target Acquisition", "other", "strength", "ranged attacks vs a unit within 12\" +1 S")
	if target_ok and dist <= FIRESTORM_RANGE_IN + 0.001 and group_has(actor_id, "close_quarters_firestorm"):
		m.strength += 1
		_src(m, "Close-quarters Firestorm", "other", "strength", "target within 9\": +1 S")
	if is_melee and group_has(actor_id, "unto_the_anvil"):
		var assault := false
		for gid in group(actor_id):
			if Common.doctrine_active(Common.unit(str(gid)), "assault"):
				assault = true
		m.wound_reroll = _reroll_max(m.wound_reroll, "failed" if assault else "ones")
		_src(m, "Unto the Anvil", "wound", "reroll_failed" if assault else "reroll_ones",
			"assault doctrine active: re-roll wound rolls" if assault else "melee attacks re-roll wound rolls of 1")
	if not is_melee and target_ok and not target_mv and dist <= WRATH_RANGE_IN + 0.001 and group_has(actor_id, "wrath_of_the_machine_spirit"):
		m.devastating = true
		_src(m, "Wrath of the Machine Spirit", "other", "devastating_wounds", "target within 12\" (not MONSTER/VEHICLE): [DEVASTATING WOUNDS]")
	if not is_melee and group_has(actor_id, "veteran_marksmen"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		_src(m, "Veteran Marksmen", "hit", "reroll_ones", "ranged attacks re-roll hit rolls of 1")
	if not is_melee and target_ok and group_has(actor_id, "targeter_optics") and _visible(actor_id, target_head):
		m.ignores_cover = true
		_src(m, "Targeter Optics", "other", "ignores_cover", "ranged attacks vs a visible enemy unit [IGNORES COVER]")
	if not is_melee and _gflag(actor_id, F_OPTICS_COVER) != null:
		m.ignores_cover = true
		_src(m, "Special-issue Optics and Ammunition", "other", "ignores_cover", "ranged attacks [IGNORES COVER] (selected when this unit was selected to shoot)")
	return m


# ===========================================================================
# DEFENSIVE / MOVEMENT / MISC passive hooks
# ===========================================================================

## Never Shall the Standard Fall (Ancient in Terminator Armour): while this
## unit is within range of an objective, attacks with S > its T have -1 to wound.
static func incoming_wound_penalty_source(target_unit: Dictionary, strength: int, toughness: int) -> String:
	if strength <= toughness or not _edition_11():
		return ""
	var tid := _uid(target_unit)
	if tid == "" or not group_has(tid, "never_shall_the_standard_fall"):
		return ""
	if not Common.group_in_range_of_any_objective(tid):
		return ""
	return "Never Shall the Standard Fall"

static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	return incoming_wound_penalty_source(target_unit, strength, toughness) != ""

## Hood of Hellfire (Tigurius): FNP 4+ vs psychic attacks and mortal wounds;
## Psychic Hood (Librarian): FNP 4+ vs psychic attacks. "This unit": the
## whole Attached unit. 0 = none.
static func conditional_fnp(unit: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	if not _edition_11() or unit.is_empty() or (not is_psychic and not is_mortal):
		return 0
	var uid := _uid(unit)
	if uid == "":
		return 0
	if group_has(uid, "hood_of_hellfire"):
		return 4
	if is_psychic and group_has(uid, "psychic_hood"):
		return 4
	return 0

## Refuse to Yield (Captain in Gravis Armour): attacks allocated to this
## model have -1 D (min 1). Same shape as CustodesAbilities.allocated_damage.
static func allocated_damage(damage: int, target_unit: Dictionary, model: Dictionary, unit_minus: int = 0) -> Dictionary:
	var out := {"damage": damage, "note": ""}
	if not _edition_11() or damage <= 1 or model.is_empty() or unit_minus > 0:
		return out
	var src_id := str(model.get("cus11e_src_unit_id", _uid(target_unit)))
	var src := Common.unit(src_id)
	if src.is_empty():
		src = target_unit
	if not has(src, "refuse_to_yield"):
		return out
	out.damage = maxi(1, damage - 1)
	out.note = "Refuse to Yield: -1 Damage (%d -> %d) — attack allocated to %s" % [damage, int(out.damage), Common.unit_name(src_id)]
	print("SMAbilitiesB: %s" % out.note)
	return out

## Unyielding in the Face of the Foe (Heavy Intercessor Squad): while this
## unit is controlling an objective, +1 to its save rolls. Added to the
## engine's save_modifier before the ±1 cap.
static func save_roll_bonus(target_unit: Dictionary) -> int:
	if not _edition_11() or target_unit.is_empty():
		return 0
	var tid := _uid(target_unit)
	if tid == "" or not group_has(tid, "unyielding_in_the_face_of_the_foe"):
		return 0
	if controlled_objectives_in_range(tid).is_empty():
		return 0
	print("SMAbilitiesB: Unyielding in the Face of the Foe — %s controls an objective: +1 to save rolls" % tid)
	return 1

## Rites of Thermal Appeasement (Hellblaster Squad): +1 to hazard rolls for
## its Plasma Incinerator and Plasma Pistol weapons.
static func hazard_roll_modifier(actor_unit: Dictionary, weapon_name: String) -> int:
	if not _edition_11() or actor_unit.is_empty():
		return 0
	var wn := weapon_name.to_lower()
	if not (wn.begins_with("plasma incinerator") or wn.begins_with("plasma pistol")):
		return 0
	return 1 if group_has(_uid(actor_unit), "rites_of_thermal_appeasement") else 0

## Lord of the Pyroclasts (Adrax Agatone): while an enemy unit is engaged with
## this unit, that enemy unit has -1 OC (MissionManager.model_oc hook).
static func model_oc(unit: Dictionary, _model: Dictionary, oc: int) -> int:
	if not _edition_11() or unit.is_empty() or oc <= 0:
		return oc
	var uid := _uid(unit)
	var owner := int(unit.get("owner", 0))
	for aid in Common.state().get("units", {}):
		var a := Common.unit(str(aid))
		if int(a.get("owner", 0)) == owner or int(a.get("owner", 0)) == 0 or not has(a, "lord_of_the_pyroclasts") or not Common.is_on_battlefield(a):
			continue
		if Common.group_engaged_with(str(aid), uid):
			return maxi(0, oc - 1)
	return oc

## Detection range: Chameleoline Cloaks (Eliminators, -3"), Special-issue
## Optics (the selected enemy unit, +6" until the Eliminators have shot).
static func detection_range_bonus(unit: Dictionary) -> float:
	if not _edition_11() or unit.is_empty():
		return 0.0
	var uid := _uid(unit)
	var bonus := 0.0
	if uid != "" and group_has(uid, "chameleoline_cloaks"):
		bonus += CHAMELEOLINE_DETECTION_IN
	if uid != "" and _gflag(uid, F_OPTICS_DET) != null:
		bonus += OPTICS_DETECTION_IN
	return bonus

## Tactical Mainstay (Intercessor Squad): being engaged / battle-shocked does
## not prevent this unit from being eligible to start an action.
static func action_ignores_engaged_and_shocked(unit: Dictionary) -> bool:
	return _edition_11() and not unit.is_empty() and group_has(_uid(unit), "tactical_mainstay")

## Tactical Mainstay: starting an action does not prevent this unit from being
## eligible to shoot.
static func action_keeps_shooting(unit: Dictionary) -> bool:
	return action_ignores_engaged_and_shocked(unit)

## Flexible Asset (Scout Squad): the advance / fall-back move does not prevent
## this unit from being eligible to start an action.
static func move_keeps_action_eligibility(unit: Dictionary) -> bool:
	return _edition_11() and not unit.is_empty() and group_has(_uid(unit), "flexible_asset")

## Assault Ramp (Land Raider Redeemer): after this unit ended a normal move in
## your Movement phase, units embarked within it make an assault disembark
## move (DisembarkMove.select_mode hook).
static func transport_grants_assault_disembark(transport: Dictionary) -> bool:
	if not _edition_11() or transport.is_empty() or not has(transport, "assault_ramp"):
		return false
	if _phase() != PH_MOVEMENT or int(transport.get("owner", 0)) != Common.active_player():
		return false
	var f: Dictionary = transport.get("flags", {})
	return bool(f.get("moved_this_phase", false)) and not bool(f.get("advanced", false)) and not bool(f.get("fell_back", false))

## Rapid Disembarkation (Impulsor): after this unit ended an advance move in
## your Movement phase, units embarked within it can make a shock disembark
## move — the advance no longer bars disembarking (TransportManager /
## DisembarkMove hooks); the set-up is 3" and the unit cannot declare a
## charge (the engine's rapid-disembark mode).
static func transport_allows_shock_disembark(transport: Dictionary) -> bool:
	if not _edition_11() or transport.is_empty() or not has(transport, "rapid_disembarkation"):
		return false
	if _phase() != PH_MOVEMENT or int(transport.get("owner", 0)) != Common.active_player():
		return false
	var f: Dictionary = transport.get("flags", {})
	return bool(f.get("advanced", false)) and not bool(f.get("fell_back", false))

## Veil of Time: this unit's advance roll this phase is a 6 (MovementPhase hook).
static func veil_of_time_active(unit_id: String) -> bool:
	if not _edition_11() or unit_id == "":
		return false
	var v = _gflag(unit_id, F_VEIL)
	return v != null and str(v) == _phase_key()

## Raise the Banner (Bladeguard Ancient, Ancient in Terminator Armour): at the
## end of your Movement phase, if this unit is controlling an objective, that
## objective is secured (14.03). MovementPhase hook.
static func on_movement_phase_end(player: int) -> void:
	if not _edition_11():
		return
	var mm = Common.autoload("MissionManager")
	if mm == null or not mm.has_method("secure_objective"):
		return
	if mm.has_method("check_all_objectives"):
		mm.check_all_objectives()
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not has(u, "raise_the_banner") or not Common.is_on_battlefield(u):
			continue
		if _group_shocked(str(uid)):
			continue
		for oid in controlled_objectives_in_range(str(uid)):
			mm.secure_objective(str(oid), player, "")
			_event_log(player, "Raise the Banner: %s secures objective %s" % [Common.unit_name(str(uid)), Common.objective_label(str(oid))])
			_log("Raise the Banner — %s secured %s for P%d" % [uid, oid, player])

## "Until this unit has shot" (Special-issue Optics): ShootingPhase hook after
## each unit's shooting.
static func on_unit_has_shot(shooter_id: String) -> void:
	if not _edition_11() or shooter_id == "":
		return
	var shooters := {}
	for gid in group(shooter_id):
		shooters[str(gid)] = true
	var cleared: Array = []
	for uid in Common.state().get("units", {}):
		var u: Dictionary = Common.state().units[uid]
		var flags = u.get("flags", null)
		if typeof(flags) != TYPE_DICTIONARY:
			continue
		if shooters.has(str(uid)) and flags.has(F_OPTICS_COVER):
			flags.erase(F_OPTICS_COVER)
			cleared.append("%s.%s" % [uid, F_OPTICS_COVER])
		var det = flags.get(F_OPTICS_DET, null)
		if typeof(det) == TYPE_DICTIONARY and shooters.has(str(det.get("by", ""))):
			flags.erase(F_OPTICS_DET)
			cleared.append("%s.%s" % [uid, F_OPTICS_DET])
	if not cleared.is_empty():
		_log("%s has shot — expired %s" % [shooter_id, str(cleared)])


# ===========================================================================
# ARMY LOAD — wargear (ArmyListManager hook, idempotent)
# ===========================================================================

## Lieutenant Storm Shield: this model has a 4+ InSv. Impulsor Shield Dome:
## this unit has a 5+ InSv. Impulsor Orbital Comms Array: this unit has
## Scouts 6" (the engine reads Scouts from the ability list).
static func apply_list_build(unit_id: String, unit: Dictionary) -> void:
	if unit.is_empty() or not fold(str(unit.get("meta", {}).get("name", ""))) in DATASHEETS or not Common.has_keyword(unit, KW_AA):
		return
	var meta: Dictionary = unit.get("meta", {})
	var names := {}
	for ab in meta.get("abilities", []):
		names[fold(_ability_name(ab))] = true
	var models: Array = unit.get("models", [])
	var dname := fold(str(meta.get("name", "")))
	if dname == "lieutenant" and (names.has("storm shield") or wargear_count(unit, "Storm Shield") > 0):
		for m in models:
			if typeof(m) != TYPE_DICTIONARY or bool(m.get(M_LIST, false)):
				continue
			m[M_LIST] = true
			var cur := int(m.get("invuln", 0))
			if cur == 0 or cur > 4:
				m["invuln"] = 4
		print("SMAbilitiesB: Storm Shield on %s (Lieutenant): 4+ invulnerable save" % unit_id)
	if dname == "impulsor":
		if names.has("shield dome") or wargear_count(unit, "Shield Dome") > 0:
			for m in models:
				if typeof(m) != TYPE_DICTIONARY or bool(m.get(M_LIST, false)):
					continue
				m[M_LIST] = true
				var cur2 := int(m.get("invuln", 0))
				if cur2 == 0 or cur2 > 5:
					m["invuln"] = 5
			print("SMAbilitiesB: Shield Dome on %s (Impulsor): 5+ invulnerable save" % unit_id)
		if (names.has("orbital comms array") or wargear_count(unit, "Orbital Comms Array") > 0) and not names.has("scouts 6"):
			var ab_list: Array = meta.get("abilities", [])
			ab_list.append({"name": "Scouts 6\"", "type": "Core", "description": "Orbital Comms Array: this unit has Scouts 6\".", "sm11e_granted_by": "Orbital Comms Array"})
			meta["abilities"] = ab_list
			print("SMAbilitiesB: Orbital Comms Array on %s (Impulsor): Scouts 6\"" % unit_id)


# ===========================================================================
# EXPIRY / per-phase state — PhaseManager.transition_to_phase (thin hook),
# before the new phase is entered (in place, every peer)
# ===========================================================================

const PHASE_SCOPED := [F_SCANNED, F_SHATTERED, F_SIGNUM, F_OPTICS_COVER, F_OPTICS_DET, F_VEIL]

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
		# Granted invulnerable saves: Rampart (end of the phase), Force Dome
		# (until the start of your next turn).
		var insv = flags.get(F_INSV, null)
		if typeof(insv) == TYPE_DICTIONARY:
			for slug in insv.keys():
				var e: Dictionary = insv[slug]
				var expire := str(e.get("until", "")) == "phase" \
					or (str(e.get("until", "")) == "next_turn" and new_phase == PH_COMMAND and int(e.get("player", 0)) == active)
				if expire:
					_restore_insv(u, str(slug))
					insv.erase(slug)
					cleared.append("%s.%s(%s)" % [uid, F_INSV, slug])
			if insv.is_empty():
				flags.erase(F_INSV)
		if new_phase == PH_COMMAND:
			# Suppressed: until the start of the Space Marine player's next turn.
			var sup = flags.get(F_SUPPRESSED, null)
			if typeof(sup) == TYPE_DICTIONARY and int(sup.get("player", 0)) == active:
				flags.erase(F_SUPPRESSED)
				cleared.append("%s.%s" % [uid, F_SUPPRESSED])
			# Prescience: +1 Sv until the start of your next turn.
			var pre = flags.get(F_PRESCIENCE, null)
			if typeof(pre) == TYPE_DICTIONARY and int(pre.get("player", 0)) == active:
				var st: Dictionary = u.get("meta", {}).get("stats", {})
				st["save"] = int(pre.get("prev", st.get("save", 7)))
				flags.erase(F_PRESCIENCE)
				cleared.append("%s.%s" % [uid, F_PRESCIENCE])
			# Strategic Acumen / Demi-company Commander: until the start of your
			# next Command phase (only the doctrines this module wrote).
			if flags.has(F_ACUMEN) and int(flags.get(F_UNIT_DOCTRINE_EXPIRES, flags.get(F_ACUMEN, 0))) == active:
				flags.erase(F_UNIT_DOCTRINE)
				flags.erase(F_UNIT_DOCTRINE_EXPIRES)
				flags.erase(F_ACUMEN)
				cleared.append("%s.%s" % [uid, F_UNIT_DOCTRINE])
	# Teleport Homer: an enemy unit that ended a move within 1" removes it
	# (checked at the end of every phase).
	_check_homer_removal()
	if not cleared.is_empty():
		_log("phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])

## Give every alive model of `unit_ids` an invulnerable save of `value`
## (keeps a better one), with a per-model backup for the expiry.
static func _grant_insv_diffs(unit_ids: Array, value: int, slug: String, player: int, until: String) -> Array:
	var diffs: Array = []
	for gid in unit_ids:
		var u := Common.unit(str(gid))
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			var m: Dictionary = models[i]
			var cur := int(m.get("invuln", 0))
			var backup: Dictionary = (m.get(M_INSV, {}) as Dictionary).duplicate() if typeof(m.get(M_INSV, {})) == TYPE_DICTIONARY else {}
			if not backup.has(slug):
				backup[slug] = cur
			diffs.append({"op": "set", "path": "units.%s.models.%d.%s" % [gid, i, M_INSV], "value": backup})
			if cur == 0 or cur > value:
				diffs.append({"op": "set", "path": "units.%s.models.%d.invuln" % [gid, i], "value": value})
		var insv: Dictionary = (u.get("flags", {}).get(F_INSV, {}) as Dictionary).duplicate() if typeof(u.get("flags", {}).get(F_INSV, {})) == TYPE_DICTIONARY else {}
		insv[slug] = {"player": player, "until": until, "value": value}
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_INSV], "value": insv})
	return diffs

## Undo one granted invulnerable save on a unit (in place).
static func _restore_insv(u: Dictionary, slug: String) -> void:
	for m in u.get("models", []):
		var backup = m.get(M_INSV, null)
		if typeof(backup) != TYPE_DICTIONARY or not backup.has(slug):
			continue
		var prev := int(backup[slug])
		backup.erase(slug)
		# Another grant still active keeps the best of the remaining values.
		var best := prev
		var insv = u.get("flags", {}).get(F_INSV, {})
		if typeof(insv) == TYPE_DICTIONARY:
			for other in insv:
				if str(other) == slug:
					continue
				var v := int(insv[other].get("value", 0))
				if v > 0 and (best == 0 or v < best):
					best = v
		m["invuln"] = best
		if backup.is_empty():
			m.erase(M_INSV)


# ===========================================================================
# TELEPORT HOMER (Terminator Squad, once per battle, per unit)
# ===========================================================================

## The unit's live token {x, y, label} (px) or {}.
static func homer_token(unit_id: String) -> Dictionary:
	var h = Common.unit(unit_id).get("flags", {}).get(F_HOMER, null)
	return h if typeof(h) == TYPE_DICTIONARY else {}

## Positions the token can be set up on (the picker): every objective marker.
static func homer_spots() -> Array:
	var out: Array = []
	for obj in Common.objectives():
		var p = obj.get("position", null)
		var v := Vector2.ZERO
		if p is Vector2:
			v = p
		elif p is Dictionary:
			v = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
		else:
			continue
		out.append({"id": "obj:%s" % str(obj.get("id", "")), "label": "On objective %s" % Common.objective_label(str(obj.get("id", ""))), "x": v.x, "y": v.y})
	return out

static func _check_homer_removal() -> void:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		var tok = u.get("flags", {}).get(F_HOMER, null)
		if typeof(tok) != TYPE_DICTIONARY:
			continue
		var tp := Vector2(float(tok.get("x", 0)), float(tok.get("y", 0)))
		var owner := int(u.get("owner", 0))
		for eid in units:
			var eu: Dictionary = units[eid]
			if int(eu.get("owner", 0)) == owner or int(eu.get("owner", 0)) == 0 or not Common.is_on_battlefield(eu):
				continue
			var hit := false
			for m in eu.get("models", []):
				if not m.get("alive", true) or m.get("position", null) == null:
					continue
				var r := _model_radius_px(m)
				if Common._pos(m).distance_to(tp) - r <= HOMER_REMOVE_IN * PX_PER_INCH + 0.01:
					hit = true
					break
			if hit:
				u.flags.erase(F_HOMER)
				_event_log(owner, "Teleport Homer: %s's token was removed — %s is within 1\" of it" % [Common.unit_name(str(uid)), Common.unit_name(str(eid))])
				_log("Teleport Homer token of %s removed (enemy %s within 1\")" % [uid, eid])
				break

static func _model_radius_px(m: Dictionary) -> float:
	var meas = Common.autoload("Measurement")
	if meas and meas.has_method("base_extent_px"):
		return float(meas.base_extent_px(m))
	return float(m.get("base_mm", 32)) / 25.4 / 2.0 * PX_PER_INCH

## True when every model of the arriving set-up is wholly within 3" of the
## unit's Teleport Homer token: the set-up uses the token (the strategic
## reserves edge / deployment-zone rules are replaced by "within 3" of that
## token and not within 8" of an enemy unit", the 20.04 enemy check stays).
static func homer_setup_ok(unit_id: String, positions: Array, models: Array = []) -> bool:
	if not _edition_11() or unit_id == "":
		return false
	var tok := homer_token(unit_id)
	if tok.is_empty() or positions.is_empty():
		return false
	var tp := Vector2(float(tok.get("x", 0)), float(tok.get("y", 0)))
	var unit_models: Array = models if not models.is_empty() else Common.unit(unit_id).get("models", [])
	var any := false
	for i in range(positions.size()):
		var p = positions[i]
		if p == null:
			continue
		var v := Vector2.ZERO
		if p is Vector2:
			v = p
		elif p is Dictionary:
			v = Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
		elif p is Array and p.size() >= 2:
			v = Vector2(float(p[0]), float(p[1]))
		else:
			continue
		var m: Dictionary = unit_models[i] if i < unit_models.size() else {}
		var r := _model_radius_px(m) if not m.is_empty() else 16.0 / 25.4 * PX_PER_INCH
		if v.distance_to(tp) + r > HOMER_SETUP_IN * PX_PER_INCH + 0.5:
			return false
		any = true
	return any

## After a Rapid Ingress set-up that used the token: remove it, refund 1 CP
## ("that use is -1 CP") and mark the once-per-battle use. Returns diffs.
static func on_rapid_ingress_setup(unit_id: String, positions: Array) -> Array:
	if not homer_setup_ok(unit_id, positions):
		return []
	var owner := int(Common.unit(unit_id).get("owner", 0))
	var cp := Common.player_cp(owner)
	_mark_battle_use(unit_id, "teleport_homer")
	var diffs: Array = [
		{"op": "remove", "path": "units.%s.flags.%s" % [unit_id, F_HOMER]},
		{"op": "set", "path": "players.%s.cp" % str(owner), "value": cp + 1},
	]
	_event_log(owner, "Teleport Homer: %s arrives within 3\" of its token — RAPID INGRESS is -1 CP (1 CP refunded); the token is removed" % Common.unit_name(unit_id))
	_log("Teleport Homer used by %s (Rapid Ingress -1 CP refunded)" % unit_id)
	return diffs


# ===========================================================================
# TACTICAL FLUIDITY — the fall-back move at the end of the opponent's Fight
# phase (auto-placed: straight away from the engaged enemy units)
# ===========================================================================

static func _auto_fall_back_diffs(unit_id: String, max_in: float) -> Dictionary:
	var out := {"diffs": [], "moved": 0.0}
	var re = Common.rules()
	var meas = Common.autoload("Measurement")
	var ids := group(unit_id)
	var enemies := Common.engaged_enemy_ids(unit_id)
	if enemies.is_empty() or re == null:
		return out
	var my_c := Vector2.ZERO
	var n := 0
	for gid in ids:
		for m in Common.unit(str(gid)).get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				my_c += Common._pos(m)
				n += 1
	var en_c := Vector2.ZERO
	var k := 0
	for eid in enemies:
		for m in Common.unit(str(eid)).get("models", []):
			if m.get("alive", true) and m.get("position", null) != null:
				en_c += Common._pos(m)
				k += 1
	if n == 0 or k == 0:
		return out
	my_c /= float(n)
	en_c /= float(k)
	var dir := (my_c - en_c).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	var size = Common.state().get("board", {}).get("size", {})
	var w_px := float(size.get("width", 44.0)) * PX_PER_INCH
	var h_px := float(size.get("height", 60.0)) * PX_PER_INCH
	var step := max_in
	while step >= 0.5:
		var shift := dir * step * PX_PER_INCH
		var ok := true
		var board: Dictionary = Common.state().duplicate(true)
		for gid in ids:
			var bu: Dictionary = board.units.get(str(gid), {})
			for m in bu.get("models", []):
				if not m.get("alive", true) or m.get("position", null) == null:
					continue
				var np := Common._pos(m) + shift
				var r := _model_radius_px(m)
				if np.x - r < 0 or np.y - r < 0 or np.x + r > w_px or np.y + r > h_px:
					ok = false
				m["position"] = {"x": np.x, "y": np.y}
		if ok:
			for gid in ids:
				for eid in board.units:
					var eu: Dictionary = board.units[eid]
					if int(eu.get("owner", 0)) == int(Common.unit(unit_id).get("owner", 0)) or not Common.is_alive(eu):
						continue
					if re.check_units_in_engagement_range(board.units[str(gid)], eu, board):
						ok = false
				# no overlap with any other model
				if ok and meas and meas.has_method("model_to_model_distance_inches"):
					for m in board.units[str(gid)].get("models", []):
						if not m.get("alive", true) or m.get("position", null) == null:
							continue
						for oid in board.units:
							if str(oid) in ids:
								continue
							for om in board.units[oid].get("models", []):
								if om.get("alive", true) and om.get("position", null) != null and float(meas.model_to_model_distance_inches(m, om)) < 0.0:
									ok = false
		if ok:
			for gid in ids:
				var models: Array = Common.unit(str(gid)).get("models", [])
				for i in range(models.size()):
					if not models[i].get("alive", true) or models[i].get("position", null) == null:
						continue
					var np2 := Common._pos(models[i]) + shift
					out.diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": {"x": np2.x, "y": np2.y}})
			out.moved = step
			return out
		step -= 0.5
	return out


# ===========================================================================
# ACTIVATED ABILITIES — ability cards in the stratagem-window framework
# ===========================================================================

## window id -> slugs offered there.
const WINDOW_ABILITIES := {
	"phase_start": ["teleport_homer", "strategic_acumen", "demi_company_commander", "spiritual_leader", "rampart",
		"prescience", "force_dome", "telepathic_assault", "haywire_mine", "signum_array"],
	"unit_selected_to_move": ["veil_of_time"],
	"unit_ended_normal_move": ["prescience", "force_dome"],
	"unit_ended_advance_move": ["prescience", "force_dome"],
	"unit_selected_to_shoot": ["divinator_class_auspexes", "special_issue_optics", "haywire_mine", "telepathic_assault", "signum_array"],
	"unit_has_shot": ["shattered_defences", "suppression_fire", "tactical_fluidity"],
	"fight_phase_end": ["tactical_fluidity"],
}

const EFFECT_TEXT := {
	"teleport_homer": "Start of the battle: set up this unit's Teleport Homer token on the battlefield. RAPID INGRESS on this unit set up wholly within 3\" of it (and not within 8\" of an enemy unit) is -1 CP; the token is then removed. An enemy unit ending a move within 1\" removes it.",
	"strategic_acumen": "Your Command phase: select one combat doctrine to be active for this unit until the start of your next Command phase.",
	"demi_company_commander": "Once per turn: a friendly Captain used Strategic Acumen — the doctrine it selected is active for this unit until the start of your next Command phase.",
	"spiritual_leader": "Once per battle round: one friendly battle-shocked ADEPTUS ASTARTES unit within 6\" of this model is no longer battle-shocked.",
	"rampart": "Once per battle (per army): this model has a 2+ invulnerable save until the end of the phase.",
	"prescience": "Psychic (level 2): psychic roll (D6; on a 1 this unit is battle-shocked). This unit has +1 Sv until the start of your next turn.",
	"force_dome": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). This unit has a 4+ invulnerable save until the start of your next turn.",
	"telepathic_assault": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). One visible enemy unit within 24\" suffers 2D3 mortal wounds.",
	"veil_of_time": "Psychic (level 1): psychic roll (D6; on a 1 this unit is battle-shocked). This unit's advance roll is changed to a 6.",
	"haywire_mine": "Once per battle: one visible enemy unit within 6\" — roll one D6: on a 2+ it suffers D3 mortal wounds (2D3 if it is a VEHICLE).",
	"divinator_class_auspexes": "Once per phase: one visible enemy unit within 18\" of the Incursors is scanned — ranged attacks that target it can re-roll hit rolls of 1 (this phase).",
	"special_issue_optics": "This unit's ranged attacks have [IGNORES COVER]; or one enemy unit within 24\" has +6\" detection range until this unit has shot.",
	"signum_array": "One visible enemy unit within 18\" cannot have the benefit of cover (this phase).",
	"shattered_defences": "One enemy MONSTER/VEHICLE unit hit by those attacks: friendly ADEPTUS ASTARTES ranged attacks that target it have +1 AP (this phase).",
	"suppression_fire": "One enemy unit hit by the Twin Macro-accelerator Cannon is suppressed until the start of your next turn: its attacks have -1 to hit.",
	"tactical_fluidity": "Once per battle round: this unengaged unit has shot — it can make a normal move of up to D6\"; or, at the end of your opponent's Fight phase, this engaged unit can make a fall-back move of up to 6\".",
}

## Windows that can host several uses: re-offered after a use.
const REOFFER_WINDOWS := ["phase_start"]
const REOFFER_IF_ABILITY_LEFT := ["unit_selected_to_shoot", "unit_has_shot", "unit_ended_normal_move", "unit_ended_advance_move"]

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

## ScenarioRunner policy: scenarios that do not opt in ("sm_abilities_b": true)
## never answer these cards, so the runner switches the OFFERS off; passive
## abilities still apply. Never set outside a scenario run.
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

static func _enemies_in_range(from_id: String, player: int, range_in: float, need_visible: bool = true) -> Array:
	var out: Array = []
	for eid in Common.enemy_heads(player):
		if _dist(from_id, str(eid)) > range_in + 0.001:
			continue
		if need_visible and not _visible(from_id, str(eid)):
			continue
		out.append(str(eid))
	return _sorted_by_distance(from_id, out)

## The doctrine Strategic Acumen should take for the AI (variant hint).
static func _ai_doctrine(unit_id: String) -> String:
	if _engaged(unit_id):
		return "tactical"
	if Common.nearest_enemy_inches(Common.group_union(unit_id)) <= 18.0 and Common.group_has_melee_weapons(unit_id):
		return "assault"
	return "devastator"

static func _doctrine_variants(unit_id: String) -> Dictionary:
	var vs: Array = []
	for d in Common.DOCTRINES:
		vs.append({"id": str(d), "label": str(Common.DOCTRINE_LABELS[d]), "cp_cost": 0})
	return {"require_variant": true, "variants": vs, "ai_variant": _ai_doctrine(unit_id)}

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := _phase()
	var own_turn := Common.active_player() == player
	match slug:
		"teleport_homer":
			if window_id != "phase_start" or _round() != 1:
				return out
			var spots := homer_spots()
			if spots.is_empty():
				return out
			for hid in _holders(player, slug, false):
				var hf: Dictionary = Common.unit(hid).get("flags", {})
				if bool(hf.get(F_HOMER_DONE, false)) or used_in_battle(hid, slug):
					continue
				var opts: Array = []
				for s in spots:
					opts.append({"id": str(s.id), "label": str(s.label)})
				out.append(_entry(hid, {"label": Common.unit_name(hid), "holder": hid,
					"secondary": {"kind": "unit", "prompt": "Teleport Homer: where is %s's token set up?" % Common.unit_name(hid), "options": opts}}))
		"strategic_acumen":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var e := _entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid)})
				e.merge(_doctrine_variants(hid), true)
				out.append(e)
		"demi_company_commander":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			var last: Dictionary = Common.sm11e_last_strategic_acumen(player)
			if last.is_empty() or str(last.get("phase_key", "")) != _phase_key():
				return out
			for hid in _holders(player, slug):
				if used_this_turn(hid, slug):
					continue
				if head_id(hid) == head_id(str(last.get("captain", ""))):
					continue  # already in the Captain's unit: the doctrine is active for it
				out.append(_entry(head_id(hid), {"holder": hid, "label": "%s — %s" % [Common.group_label(hid), str(Common.DOCTRINE_LABELS.get(str(last.get("doctrine", "")), ""))]}))
		"spiritual_leader":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug):
				if used_this_round(hid, slug):
					continue
				var cands: Array = []
				for fid in Common.friendly_heads(player):
					if not _group_shocked(str(fid)) or not Common.group_has_keyword(str(fid), KW_AA):
						continue
					if head_id(str(fid)) == head_id(hid) or Common.unit_distance_inches(Common.unit(hid), Common.group_union(str(fid))) <= SPIRITUAL_RANGE_IN + 0.001:
						cands.append(str(fid))
				if cands.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.unit_name(hid),
					"secondary": _unit_options(cands, "Spiritual Leader: select one friendly battle-shocked ADEPTUS ASTARTES unit within 6\" of %s" % Common.unit_name(hid))}))
		"rampart":
			if window_id != "phase_start" or army_used_in_battle(player, slug):
				return out
			for hid in _holders(player, slug):
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.unit_name(hid)}))
		"prescience", "force_dome":
			if not own_turn or phase != PH_MOVEMENT:
				return out
			for hid in _holders(player, slug):
				if window_id != "phase_start" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if not _psychic_ready(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid)}))
		"telepathic_assault":
			if not own_turn or phase != PH_SHOOTING:
				return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if not _psychic_ready(hid, slug):
					continue
				var cands := _enemies_in_range(hid, player, TELEPATHIC_RANGE_IN)
				if cands.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid),
					"secondary": _unit_options(cands, "Telepathic Assault: select one visible enemy unit within 24\" (2D3 mortal wounds)")}))
		"veil_of_time":
			if window_id != "unit_selected_to_move" or not own_turn or phase != PH_MOVEMENT:
				return out
			if str(ctx.get("move_type", "")) != "advance":
				return out
			var mover := str(ctx.get("unit_id", ""))
			var hid := group_holder(mover, slug) if mover != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or not _psychic_ready(hid, slug):
				return out
			out.append(_entry(head_id(mover), {"holder": hid, "label": Common.group_label(hid)}))
		"haywire_mine":
			if not own_turn or phase != PH_SHOOTING:
				return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if used_in_battle(hid, slug):
					continue
				var cands := _enemies_in_range(hid, player, HAYWIRE_RANGE_IN)
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return int(Common.group_has_keyword(str(a), "VEHICLE")) > int(Common.group_has_keyword(str(b), "VEHICLE")))
				out.append(_entry(head_id(hid), {"holder": hid,
					"secondary": _unit_options(cands, "Haywire Mine: select one visible enemy unit within 6\" (2D3 mortal wounds vs a VEHICLE)")}))
		"divinator_class_auspexes":
			if window_id != "unit_selected_to_shoot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter := str(ctx.get("unit_id", ""))
			if shooter == "" or not Common.group_has_keyword(shooter, KW_AA) or int(Common.unit(shooter).get("owner", 0)) != player:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var cands := _enemies_in_range(hid, player, DIVINATOR_RANGE_IN)
				if cands.is_empty():
					continue
				out.append(_entry(head_id(shooter), {"holder": hid, "label": "%s (scan by %s)" % [Common.group_label(shooter), Common.unit_name(hid)],
					"secondary": _unit_options(cands, "Divinator-class Auspexes: select one visible enemy unit within 18\" of %s to be scanned" % Common.unit_name(hid))}))
		"special_issue_optics":
			if window_id != "unit_selected_to_shoot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter2 := str(ctx.get("unit_id", ""))
			var hid2 := group_holder(shooter2, slug) if shooter2 != "" else ""
			if hid2 == "" or used_this_phase(hid2, slug):
				return out
			var e2 := _entry(head_id(shooter2), {"holder": hid2, "label": Common.group_label(hid2), "require_variant": true, "ai_variant": "cover",
				"variants": [{"id": "cover", "label": "[IGNORES COVER]", "cp_cost": 0}]})
			var det_cands := _enemies_in_range(hid2, player, OPTICS_RANGE_IN, false)
			if not det_cands.is_empty():
				(e2.variants as Array).append({"id": "detection", "label": "+6\" detection range on an enemy unit", "cp_cost": 0})
				e2["secondary"] = _unit_options(det_cands, "Special-issue Optics: select one enemy unit within 24\" (+6\" detection range until this unit has shot) — ignored for [IGNORES COVER]")
			out.append(e2)
		"signum_array":
			if not own_turn or phase != PH_SHOOTING:
				return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if used_this_phase(hid, slug):
					continue
				var cands := _enemies_in_range(hid, player, SIGNUM_RANGE_IN)
				if cands.is_empty():
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid),
					"secondary": _unit_options(cands, "Signum Array: select one visible enemy unit within 18\" — it cannot have the benefit of cover")}))
		"shattered_defences", "suppression_fire":
			if window_id != "unit_has_shot" or not own_turn or phase != PH_SHOOTING:
				return out
			var sh := str(ctx.get("unit_id", ""))
			var hid3 := group_holder(sh, slug) if sh != "" else ""
			if hid3 == "" or used_this_phase(hid3, slug):
				return out
			var hit_ids: Array = ctx.get("hit_unit_ids", [])
			if slug == "suppression_fire":
				var by_w: Dictionary = ctx.get("hit_by_weapon", {})
				if not by_w.is_empty():
					hit_ids = []
					for wk in by_w:
						if str(wk).to_lower().replace("_", " ").replace("-", " ").contains("macro accelerator"):
							for t in by_w[wk]:
								if not t in hit_ids:
									hit_ids.append(t)
			var cands: Array = []
			for tid in hit_ids:
				var h := head_id(str(tid))
				var hu := Common.unit(h)
				if int(hu.get("owner", 0)) == player or not Common.is_alive(hu) or h in cands:
					continue
				if slug == "shattered_defences" and not _is_mv(h):
					continue
				cands.append(h)
			if cands.is_empty():
				return out
			cands.sort_custom(func(a, b): return Common.group_points(str(a)) > Common.group_points(str(b)))
			out.append(_entry(head_id(sh), {"holder": hid3, "label": Common.group_label(hid3),
				"secondary": _unit_options(cands, "%s: select one enemy unit hit by those attacks" % display(slug) if slug == "shattered_defences" \
					else "Suppression Fire: select one enemy unit hit by the Twin Macro-accelerator Cannon — it is suppressed")}))
		"tactical_fluidity":
			if window_id == "unit_has_shot":
				if not own_turn or phase != PH_SHOOTING:
					return out
				var sh2 := str(ctx.get("unit_id", ""))
				var hid4 := group_holder(sh2, slug) if sh2 != "" else ""
				if hid4 == "" or used_this_round(hid4, slug) or _engaged(hid4):
					return out
				out.append(_entry(head_id(sh2), {"holder": hid4, "label": "%s — normal move up to D6\"" % Common.group_label(hid4)}))
			elif window_id == "fight_phase_end":
				if own_turn or phase != PH_FIGHT:
					return out
				for hid in _holders(player, slug):
					if used_this_round(hid, slug) or not _engaged(hid):
						continue
					out.append(_entry(head_id(hid), {"holder": hid, "label": "%s — fall-back move up to 6\"" % Common.group_label(hid)}))
	return out

## StratagemManager.can_use_stratagem for an ability card.
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
	var variant := str(context.get("variant_id", ""))
	if bool(entry.get("require_variant", false)):
		var vok := false
		for v in entry.get("variants", []):
			if str(v.get("id", "")) == variant:
				vok = true
		if not vok:
			return {"success": false, "error": "%s needs one of its options" % display(slug), "diffs": []}
	var secondary := str(context.get("secondary_id", ""))
	var needs_secondary := entry.has("secondary") and not (slug == "special_issue_optics" and variant != "detection")
	if needs_secondary:
		var ok := false
		for o in entry.secondary.get("options", []):
			if str(o.get("id", "")) == secondary:
				ok = true
		if not ok:
			return {"success": false, "error": "%s needs a valid target" % display(slug), "diffs": []}
	var holder := str(entry.get("holder", target_unit_id))
	var res := _apply(slug, player, target_unit_id, holder, secondary, variant, context)
	var diffs: Array = res.get("diffs", [])
	var gs = Common.game_state()
	if not diffs.is_empty() and gs:
		gs.apply_state_changes(diffs)
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

static func _set_doctrine_diffs(unit_id: String, doctrine: String, player: int) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_UNIT_DOCTRINE], "value": doctrine})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_UNIT_DOCTRINE_EXPIRES], "value": player})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_ACUMEN], "value": player})
	return diffs

static func _apply(slug: String, player: int, uid: String, holder: String, secondary: String, variant: String, _ctx: Dictionary) -> Dictionary:
	var name := Common.group_label(uid)
	match slug:
		"teleport_homer":
			var spot: Dictionary = {}
			for s in homer_spots():
				if str(s.id) == secondary:
					spot = s
			if spot.is_empty():
				return {"diffs": []}
			var diffs: Array = Common.set_flag_diffs([holder], F_HOMER, {"x": float(spot.x), "y": float(spot.y), "label": str(spot.label)})
			diffs.append_array(Common.set_flag_diffs([holder], F_HOMER_DONE, true))
			return {"diffs": diffs, "log": "Teleport Homer: %s's token is set up %s (%d\", %d\") — RAPID INGRESS within 3\" of it is -1 CP" % [
				Common.unit_name(holder), str(spot.label).to_lower(), roundi(float(spot.x) / PX_PER_INCH), roundi(float(spot.y) / PX_PER_INCH)]}
		"strategic_acumen":
			var diffs: Array = _set_doctrine_diffs(uid, variant, player)
			diffs.append(_phase_use_diff(holder, slug))
			diffs.append(Common.sm11e_record_strategic_acumen(player, holder, variant, _phase_key()))
			return {"diffs": diffs, "log": "Strategic Acumen (%s): %s is active for %s until the start of your next Command phase" % [
				Common.unit_name(holder), str(Common.DOCTRINE_LABELS.get(variant, variant)), name]}
		"demi_company_commander":
			var last: Dictionary = Common.sm11e_last_strategic_acumen(player)
			var d := str(last.get("doctrine", ""))
			var diffs: Array = _set_doctrine_diffs(uid, d, player)
			diffs.append(_turn_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Demi-company Commander (%s): %s (selected by %s's Strategic Acumen) is active for %s until the start of your next Command phase" % [
				Common.unit_name(holder), str(Common.DOCTRINE_LABELS.get(d, d)), Common.unit_name(str(last.get("captain", ""))), name]}
		"spiritual_leader":
			var diffs: Array = []
			for gid in group(secondary):
				diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": false})
			diffs.append(_round_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Spiritual Leader (%s): %s is no longer battle-shocked" % [Common.unit_name(holder), Common.group_label(secondary)]}
		"rampart":
			var diffs: Array = _grant_insv_diffs([holder], 2, slug, player, "phase")
			diffs.append(_army_use_diff(player, slug))
			return {"diffs": diffs, "log": "Rampart: %s has a 2+ invulnerable save until the end of the phase (once per battle)" % Common.unit_name(holder)}
		"prescience":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			for gid in group(holder):
				var gu := Common.unit(str(gid))
				var cur := int(gu.get("meta", {}).get("stats", {}).get("save", 7))
				var pre = gu.get("flags", {}).get(F_PRESCIENCE, null)
				var prev := int(pre.get("prev", cur)) if typeof(pre) == TYPE_DICTIONARY else cur
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_PRESCIENCE], "value": {"player": player, "prev": prev}})
				diffs.append({"op": "set", "path": "units.%s.meta.stats.save" % gid, "value": maxi(2, prev - 1)})
			return {"diffs": diffs, "log": "Prescience (%s): %s — %s has +1 Sv until the start of your next turn" % [Common.unit_name(holder), pr.note, name]}
		"force_dome":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			diffs.append_array(_grant_insv_diffs(group(holder), 4, slug, player, "next_turn"))
			return {"diffs": diffs, "log": "Force Dome (%s): %s — %s has a 4+ invulnerable save until the start of your next turn" % [Common.unit_name(holder), pr.note, name]}
		"telepathic_assault":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			var gs = Common.game_state()
			if gs and not diffs.is_empty():
				gs.apply_state_changes(diffs)
			var dice: Array = Common.roll_dice(2, 3)
			var mw := int(dice[0]) + int(dice[1])
			var res := _mortal_wounds(secondary, mw)
			return {"diffs": res.diffs, "log": "Telepathic Assault (%s): %s — %s suffers 2D3 %s = %d mortal wound(s) (%d model(s) destroyed)" % [
				Common.unit_name(holder), pr.note, Common.group_label(secondary), str(dice), mw, int(res.casualties)]}
		"veil_of_time":
			var pr := _psychic_roll(holder, slug)
			var diffs: Array = pr.diffs
			diffs.append_array(Common.set_flag_diffs(group(holder), F_VEIL, _phase_key()))
			return {"diffs": diffs, "log": "Veil of Time (%s): %s — %s's advance roll is changed to a 6" % [Common.unit_name(holder), pr.note, name]}
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
		"divinator_class_auspexes":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_SCANNED, {"player": player, "source": holder})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Divinator-class Auspexes (%s): %s is scanned — ranged attacks that target it can re-roll hit rolls of 1 this phase" % [Common.unit_name(holder), Common.group_label(secondary)]}
		"special_issue_optics":
			var diffs: Array = [_phase_use_diff(holder, slug)]
			if variant == "detection":
				diffs.append_array(Common.set_flag_diffs(group(secondary), F_OPTICS_DET, {"by": head_id(holder)}))
				return {"diffs": diffs, "log": "Special-issue Optics and Ammunition (%s): %s has +6\" detection range until %s has shot" % [Common.unit_name(holder), Common.group_label(secondary), Common.unit_name(holder)]}
			diffs.append_array(Common.set_flag_diffs(group(holder), F_OPTICS_COVER, true))
			return {"diffs": diffs, "log": "Special-issue Optics and Ammunition (%s): this unit's ranged attacks have [IGNORES COVER]" % Common.unit_name(holder)}
		"signum_array":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_SIGNUM, {"player": player})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Signum Array (%s): %s cannot have the benefit of cover this phase" % [Common.unit_name(holder), Common.group_label(secondary)]}
		"shattered_defences":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_SHATTERED, {"player": player})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Shattered Defences (%s): friendly ADEPTUS ASTARTES ranged attacks that target %s have +1 AP this phase" % [Common.unit_name(holder), Common.group_label(secondary)]}
		"suppression_fire":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_SUPPRESSED, {"player": player, "source": "Suppression Fire"})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Suppression Fire (%s): %s is suppressed (-1 to hit) until the start of your next turn" % [Common.unit_name(holder), Common.group_label(secondary)]}
		"tactical_fluidity":
			if str(_ctx.get("window_id", "")) == "fight_phase_end":
				var fb := _auto_fall_back_diffs(holder, FLUIDITY_FALL_BACK_IN)
				var diffs: Array = fb.diffs
				diffs.append(_round_use_diff(holder, slug))
				if float(fb.moved) <= 0.0:
					return {"diffs": diffs, "log": "Tactical Fluidity: %s found no legal fall-back move (it stays engaged)" % name}
				return {"diffs": diffs, "log": "Tactical Fluidity: %s makes a fall-back move of %.1f\" (straight away from the engaged enemy units)" % [name, float(fb.moved)]}
			var r := int(Common.roll_dice(1)[0])
			return {"diffs": [_round_use_diff(holder, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(r), "source": "Tactical Fluidity"},
				"log": "Tactical Fluidity: %s rolls D6 = %d — normal move of up to %d\"" % [name, r, r]}
	return {"diffs": []}


# ===========================================================================
# AI — synchronous scores (AIDecisionMaker.decide_window_stratagem, threshold
# 1.0 for abilities): the window never waits on the AI.
# ===========================================================================

static func ai_score(player: int, sid: String, target_unit_id: String, window_id: String, _ctx: Dictionary) -> float:
	var slug := slug_of(sid)
	match slug:
		"spiritual_leader", "haywire_mine", "telepathic_assault", "shattered_defences", "suppression_fire":
			return 3.0
		"strategic_acumen", "demi_company_commander", "divinator_class_auspexes", "special_issue_optics", "signum_array":
			return 2.0
		"prescience", "force_dome":
			# Only worth a psychic roll when the enemy can reach this unit soon.
			return 2.0 if Common.nearest_enemy_inches(Common.group_union(target_unit_id)) <= 24.0 else 0.0
		"veil_of_time":
			return 1.5
		"rampart":
			# Once per battle per army: spend it when the unit is fighting in the
			# opponent's Fight phase (its attacks land then).
			return 2.5 if (_phase() == PH_FIGHT and Common.active_player() != player and _engaged(target_unit_id)) else 0.0
		"teleport_homer", "tactical_fluidity":
			return 0.0  # placement / repositioning is a plan-level decision
	return 0.0
