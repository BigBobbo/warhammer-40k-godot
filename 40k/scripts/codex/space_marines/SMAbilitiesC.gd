extends RefCounted

## SMAbilitiesC — Codex: Space Marines (11e), DATASHEET and WARGEAR abilities
## of the 29 generic datasheets of work package WP-M4c (PLAN_SPACE_MARINES.md
## § "M4 split", M4c list).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md, PLAN_SPACE_MARINES.md.
## Printed text: .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md.
## Audit + rulings: space_marines_abilities_audit_c.md, RULINGS.md (## WP-M4c).
##
## Everything is static. Engine files reach this module only through thin,
## commented hooks (one line each, "WP-M4c"):
##   RulesEngine        ork11e_ab_mods aggregator (merge_attack_mods), S > T
##                      wound penalty (Duty Eternal), cleave (Into the Fray),
##                      damage re-roll (Total Obliteration), FNP (Seeker of
##                      the Unfound, Veteran Bodyguard), Stealth (Trifold Path)
##   EffectPrimitives   -1 to wound defence (Command Squad, Honour Guard of
##                      Macragge), advance-and-charge / [ASSAULT] (For the
##                      Khan!, Spear of Chogoris), charge re-roll (Master of
##                      Shadows)
##   MovementPhase      advance roll (Spear of Chogoris), move through models /
##                      vertical distance (Grapnel Launchers), end of the
##                      Movement phase (Raise the Banner)
##   ChargePhase        charge roll (Spear of Chogoris), charge lock (Purgation
##                      Run), the enemy_declares_charge window (Combat Embarkation)
##   ShootingPhase      models destroyed by a shot (Glory of Ultramar)
##   FightPhase         start of the Fight phase (Fearsome Assault), has fought
##                      (Righteous Fury), Fight On Death (Honour of Ultramar)
##   FightSequencer     Fights First of the whole Attached unit (Tempormortis)
##   GameState          Deep Strike (Grav-chutes, Thunderhawk Insertion),
##                      Scouts (Cerebrex Logic Engine)
##   MissionManager     model OC (Terror Troops, Honour of the Company, Seeker)
##   CommandPhase       Leadership (Seeker of the Unfound)
##   TerrainManager     detection range (Trifold Path of Shadow)
##   StratagemManager   ability cards, Veiling Smoke / Blackwing Mantle
##                      overrides, Honour or Death -1 CP
##   CharacterAttachmentManager  Captain of the Honour Guard (Leader -> Support)
##   FactionAbilityManager  Strategium Command redeploys
##   FormationsPhase    Thunderhawk Insertion / Cerebrex Logic Engine choices
##   PhaseManager       on_phase_transition (expiry, Codex Adept, Skilled Riders)
##   BasePhase          phase_start_entries (the "start of the phase" cards)
##   AIDecisionMaker    ai_score for the cards (synchronous)
##
## Only ADEPTUS ASTARTES units of a Space Marine army (SWCommon.is_sm_army,
## 11e) of the M4c datasheets have these rules (SM-D1). Shared ability names
## (Strategic Acumen, Raise the Banner, Codex Adept) are scoped to the M4c
## datasheets so the sibling packages' datasheets never get a second copy.

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")

const PX_PER_INCH := 40.0

# GameState.Phase mirror.
const PH_FORMATIONS := 0
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const ST_UNDEPLOYED := 0
const ST_IN_RESERVES := 7

const KW_AA := "ADEPTUS ASTARTES"

## The M4c datasheets (folded names, see fold()).
const SHEETS := ["captain on bike", "gladiator lancer", "judiciar", "kayvaan shrike", "korsarro khan",
	"land speeder", "outrider squad", "redemptor dreadnought", "reiver squad", "repulsor",
	"repulsor executioner", "rhino", "vulkan hestan", "company heroes", "apothecary", "ancient",
	"assault intercessors with jump packs", "aethon shaan", "caanok var", "suboden khan",
	"cato sicarius", "victrix honour guard", "captain titus", "wardens of ultramar",
	"eradicator squad with heavy bolters", "marneus calgar", "invader atvs", "kaius konorius",
	"eradicator squad with melta rifles"]

## slug -> [folded printed ability name, [datasheets that print it]].
const ABILITIES := {
	"strategic_acumen": ["strategic acumen", ["captain on bike"]],
	"into_the_fray": ["into the fray", ["captain on bike"]],
	"aquilon_optics": ["aquilon optics", ["gladiator lancer"]],
	"tempormortis": ["tempormortis", ["judiciar"]],
	"trifold_path_of_shadow": ["trifold path of shadow", ["kayvaan shrike"]],
	"echo_of_the_ravenspire": ["echo of the ravenspire", ["kayvaan shrike"]],
	"trophy_taker": ["trophy taker", ["korsarro khan"]],
	"for_the_khan": ["for the khan", ["korsarro khan"]],
	"purgation_run": ["purgation run", ["land speeder"]],
	"full_throttle_assault": ["full throttle assault", ["outrider squad"]],
	"duty_eternal": ["duty eternal", ["redemptor dreadnought"]],
	"terror_troops": ["terror troops", ["reiver squad"]],
	"fearsome_assault": ["fearsome assault", ["reiver squad"]],
	"grapnel_launchers": ["grapnel launchers", ["reiver squad"]],
	"grav_chutes": ["grav chutes", ["reiver squad"]],
	"combat_embarkation": ["combat embarkation", ["repulsor"]],
	"executioner": ["executioner", ["repulsor executioner"]],
	"veiling_smoke": ["veiling smoke", ["rhino"]],
	"seeker_of_the_unfound": ["seeker of the unfound", ["vulkan hestan"]],
	"forgefather": ["forgefather", ["vulkan hestan"]],
	"raise_the_banner": ["raise the banner", ["company heroes", "ancient", "wardens of ultramar"]],
	"command_squad": ["command squad", ["company heroes"]],
	"narthecium": ["narthecium", ["apothecary"]],
	"honour_of_the_company": ["honour of the company", ["ancient"]],
	"hammer_of_wrath": ["hammer of wrath", ["assault intercessors with jump packs"]],
	"master_of_shadows": ["master of shadows", ["aethon shaan"]],
	"blackwing_mantle": ["blackwing mantle", ["aethon shaan"]],
	"cold_and_calculating": ["cold and calculating", ["caanok var"]],
	"cerebrex_logic_engine": ["cerebrex logic engine", ["caanok var"]],
	"spear_of_chogoris": ["spear of chogoris", ["suboden khan"]],
	"skilled_riders": ["skilled riders", ["suboden khan"]],
	"captain_of_the_honour_guard": ["captain of the honour guard", ["cato sicarius"]],
	"knight_champion_of_macragge": ["knight champion of macragge", ["cato sicarius"]],
	"honour_or_death": ["honour or death", ["cato sicarius"]],
	"glory_of_ultramar": ["glory of ultramar", ["victrix honour guard"]],
	"honour_guard_of_macragge": ["honour guard of macragge", ["victrix honour guard"]],
	"banner_of_macragge": ["banner of macragge", ["victrix honour guard"]],
	"press_the_attack": ["press the attack", ["captain titus"]],
	"righteous_fury": ["righteous fury", ["captain titus"]],
	"honour_of_ultramar": ["honour of ultramar", ["captain titus"]],
	"strategium_command": ["strategium command", ["wardens of ultramar"]],
	"overlapping_destruction": ["overlapping destruction", ["eradicator squad with heavy bolters"]],
	"codex_adept": ["codex adept", ["marneus calgar"]],
	"master_tactician": ["master tactician", ["marneus calgar"]],
	"thunderhawk_insertion": ["thunderhawk insertion", ["marneus calgar"]],
	"aggressive_reconnaissance": ["aggressive reconnaissance", ["invader atvs"]],
	"veteran_bodyguard": ["veteran bodyguard", ["kaius konorius"]],
	"calgars_champion": ["calgars champion", ["kaius konorius"]],
	"total_obliteration": ["total obliteration", ["eradicator squad with melta rifles"]],
}

## Wargear abilities: also present when the roster's wargear lists the item.
const WARGEAR_ITEMS := {"grapnel_launchers": "grapnel launchers", "grav_chutes": "grav chutes", "banner_of_macragge": "banner of macragge"}

const DISPLAY := {
	"strategic_acumen": "Strategic Acumen", "into_the_fray": "Into the Fray", "aquilon_optics": "Aquilon Optics",
	"tempormortis": "Tempormortis", "trifold_path_of_shadow": "Trifold Path of Shadow",
	"echo_of_the_ravenspire": "Echo of the Ravenspire", "trophy_taker": "Trophy Taker", "for_the_khan": "For the Khan!",
	"purgation_run": "Purgation Run", "full_throttle_assault": "Full-throttle Assault", "duty_eternal": "Duty Eternal",
	"terror_troops": "Terror Troops", "fearsome_assault": "Fearsome Assault", "grapnel_launchers": "Grapnel Launchers",
	"grav_chutes": "Grav-chutes", "combat_embarkation": "Combat Embarkation", "executioner": "Executioner",
	"veiling_smoke": "Veiling Smoke", "seeker_of_the_unfound": "Seeker of the Unfound", "forgefather": "Forgefather",
	"raise_the_banner": "Raise the Banner", "command_squad": "Command Squad", "narthecium": "Narthecium",
	"honour_of_the_company": "Honour of the Company", "hammer_of_wrath": "Hammer of Wrath",
	"master_of_shadows": "Master of Shadows", "blackwing_mantle": "Blackwing Mantle",
	"cold_and_calculating": "Cold and Calculating", "cerebrex_logic_engine": "Cerebrex Logic Engine",
	"spear_of_chogoris": "Spear of Chogoris", "skilled_riders": "Skilled Riders",
	"captain_of_the_honour_guard": "Captain of the Honour Guard", "knight_champion_of_macragge": "Knight Champion of Macragge",
	"honour_or_death": "Honour or Death", "glory_of_ultramar": "Glory of Ultramar",
	"honour_guard_of_macragge": "Honour Guard of Macragge", "banner_of_macragge": "Banner of Macragge",
	"press_the_attack": "Press the Attack", "righteous_fury": "Righteous Fury", "honour_of_ultramar": "Honour of Ultramar",
	"strategium_command": "Strategium Command", "overlapping_destruction": "Overlapping Destruction",
	"codex_adept": "Codex Adept", "master_tactician": "Master Tactician", "thunderhawk_insertion": "Thunderhawk Insertion",
	"aggressive_reconnaissance": "Aggressive Reconnaissance", "veteran_bodyguard": "Veteran Bodyguard",
	"calgars_champion": "Calgar's Champion", "total_obliteration": "Total Obliteration",
}

# --- flags (sm11e_abc_*; none uses the effect_ prefix ShootingPhase wipes) ---
const F_PHASE_USES := "sm11e_abc_phase_uses"        # {slug: phase_key}: once-per-phase per-unit uses
const F_DOCTRINE_SRC := "sm11e_abc_doctrine_src"    # name of the M4c rule that wrote sw11e_doctrine on this unit
const F_CODEX_ADEPT := "sm11e_abc_codex_adept"      # true: sw11e_doctrine_extra was written by Codex Adept
const F_MOBILE := "sm11e_abc_mobile"                 # true: ork11e_mobile was written by Skilled Riders
const F_NO_CHARGE := "sm11e_abc_no_charge"           # turn key: not eligible to declare a charge (Purgation Run)
const F_SEEKER_OBJ := "sm11e_abc_seeker_objective"   # Vulkan: the objective id chosen by Seeker of the Unfound
const F_FORGEFATHER := "sm11e_abc_forgefather"       # on the ENEMY unit: {player, phase_key, source}
const F_OVERLAP := "sm11e_abc_overlap"               # on the Eradicators: {target, phase_key}
const F_COLD := "sm11e_abc_cold"                     # Caanok's unit: {mode, phase_key}
const F_RF := "sm11e_abc_righteous_fury"             # Titus's unit: {phase_key, targets: {uid: alive}}
const F_BANNER := "sm11e_abc_banner_of_macragge"     # Victrix: phase_key (+1 A and S this activation's phase)
const F_SHADOWS := "sm11e_abc_master_of_shadows"     # target unit: {player}: re-roll charge rolls until next Command phase
const F_AQUILON := "sm11e_abc_aquilon"               # Lancer: {hit, wound, damage, key}: Aquilon re-rolls still unused
const F_DEEP_STRIKE := "sm11e_abc_deep_strike"       # Thunderhawk Insertion: this unit has Deep Strike
const F_SCOUTS := "sm11e_abc_scouts"                 # Cerebrex Logic Engine: this unit has Scouts 6"
const F_FORMATION_PICK := "sm11e_abc_formation_pick" # on the holder: {slug: unit_id} chosen in Declare Battle Formations
const PT_FLAG := "cus11e_prime_target"               # the engine's single-re-roll grant (Custodes PRIME TARGET mechanism)
const SW_DOCTRINE := "sw11e_doctrine"
const SW_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"
const SW_DOCTRINE_EXTRA := "sw11e_doctrine_extra"
const ORK_MOBILE := "ork11e_mobile"
## Army-level ledger on GameState.state.players[p]: {slug: battle | phase key}.
const ARMY_USES := "sm11e_abc_army_uses"

const SID_PREFIX := "sm11e_abc_"

const MASTER_TACTICIAN_RANGE_IN := 9.0
const FORGEFATHER_RANGE_IN := 24.0
const KNIGHT_CHAMPION_RANGE_IN := 8.0
const KNIGHT_CHAMPION_MOVE_IN := 6.0
const TERROR_RANGE_IN := 3.0
const ISOLATED_RANGE_IN := 6.0
const EMBARK_RANGE_IN := 3.0
const TRIFOLD_DETECTION_IN := -3.0
const SEEKER_OC := 10
const SEEKER_LD := 5
const SEEKER_FNP := 4
const VETERAN_BODYGUARD_FNP := 4
const HONOUR_OF_ULTRAMAR_PASS := 2


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

static func sheet_of(u: Dictionary) -> String:
	return fold(str(u.get("meta", {}).get("name", "")))

static func is_m4c_sheet(u: Dictionary) -> bool:
	return sheet_of(u) in SHEETS

## An ADEPTUS ASTARTES unit of a Space Marine army (SM-D1).
static func is_sm_unit(u: Dictionary) -> bool:
	if u.is_empty() or not _edition_11() or not Common.has_keyword(u, KW_AA):
		return false
	return Common.is_sm_army(int(u.get("owner", 0)))

## The roster lists a wargear item ("1x Grav-chutes").
static func _wargear_has(u: Dictionary, item_fold: String) -> bool:
	for w in u.get("meta", {}).get("wargear", []):
		var s := str(w).strip_edges()
		var re := RegEx.new()
		re.compile("^(\\d+)\\s*x\\s*(.+)$")
		var m := re.search(s)
		if m:
			s = m.get_string(2)
		if fold(s) == item_fold:
			return true
	return false

## True when the unit is an M4c datasheet that lists the ability of `slug`
## (and the codex rules apply to it).
static func has(u: Dictionary, slug: String) -> bool:
	var row = ABILITIES.get(slug, null)
	if row == null or u.is_empty():
		return false
	if not sheet_of(u) in (row[1] as Array):
		return false
	var want := str(row[0])
	var found := false
	for ab in u.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == want:
			found = true
			break
	if not found and WARGEAR_ITEMS.has(slug):
		found = _wargear_has(u, str(WARGEAR_ITEMS[slug]))
	return found and is_sm_unit(u)

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

## "round:active:phase" — the same stamp as CustodesEnhancements.stamp().
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

static func _log(msg: String) -> void:
	Common.log_info("SMAbilitiesC: " + msg)


# ===========================================================================
# Usage limits
# ===========================================================================

## (Once per battle, per army) — UnitAbilityManager's ledger, keyed on the
## player (saved with the game).
static func army_used_in_battle(player: int, slug: String) -> bool:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == "battle"

static func _army_battle_diff(player: int, slug: String) -> Dictionary:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = "battle"
	return {"op": "set", "path": "players.%s.%s" % [str(player), ARMY_USES], "value": nd}

## (Once per phase, per army).
static func army_used_this_phase(player: int, slug: String) -> bool:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _phase_key()

static func _army_phase_diff(player: int, slug: String) -> Dictionary:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _phase_key()
	return {"op": "set", "path": "players.%s.%s" % [str(player), ARMY_USES], "value": nd}

## (Once per phase, per unit) — kept on the holder.
static func used_this_phase(holder_id: String, slug: String) -> bool:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _phase_key()

static func _phase_use_diff(holder_id: String, slug: String) -> Dictionary:
	var uses = Common.unit(holder_id).get("flags", {}).get(F_PHASE_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _phase_key()
	return {"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_PHASE_USES], "value": nd}


# ===========================================================================
# PASSIVE COMBAT MODIFIERS — merged into RulesEngine's WP-O6 aggregator
# ===========================================================================

static func _empty_mods() -> Dictionary:
	return {"hit_plus": false, "hit_minus": false, "hit_reroll": "", "ignore_hit_penalties": false,
		"wound_plus": false, "wound_reroll": "", "ap": 0, "damage": 0, "strength": 0, "attacks": 0,
		"sustained": 0, "lethal": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

## The M4c contribution, merged INTO `m` (the aggregator result) — the
## one-line RulesEngine hook in ork11e_ab_mods. Also projects Aquilon Optics'
## single re-rolls onto the attacker for this target (see _aquilon_project).
static func merge_attack_mods(m: Dictionary, actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, bearer_ids: Array = []) -> void:
	if not _edition_11() or actor_unit.is_empty():
		return
	_aquilon_project(actor_unit, target_unit, is_melee)
	var c := attack_mods(actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)
	if (c.sources as Array).is_empty():
		return
	m["hit_plus"] = bool(m.get("hit_plus", false)) or c.hit_plus
	m["hit_minus"] = bool(m.get("hit_minus", false)) or c.hit_minus
	m["hit_reroll"] = _reroll_max(str(m.get("hit_reroll", "")), c.hit_reroll)
	m["ignore_hit_penalties"] = bool(m.get("ignore_hit_penalties", false)) or c.ignore_hit_penalties
	m["wound_plus"] = bool(m.get("wound_plus", false)) or c.wound_plus
	m["wound_reroll"] = _reroll_max(str(m.get("wound_reroll", "")), c.wound_reroll)
	m["ap"] = int(m.get("ap", 0)) + int(c.ap)
	m["damage"] = int(m.get("damage", 0)) + int(c.damage)
	m["strength"] = int(m.get("strength", 0)) + int(c.strength)
	m["attacks"] = int(m.get("attacks", 0)) + int(c.attacks)
	m["sustained"] = maxi(int(m.get("sustained", 0)), int(c.sustained))
	m["lethal"] = bool(m.get("lethal", false)) or c.lethal
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append_array(c.sources)

static func _weapon_text(weapon_profile: Dictionary) -> String:
	var parts: Array = [str(weapon_profile.get("name", "")), str(weapon_profile.get("special_rules", ""))]
	for kw in weapon_profile.get("keywords", []):
		parts.append(str(kw))
	return " ".join(PackedStringArray(parts)).to_lower()

static func attack_mods(actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> Dictionary:
	var m := _empty_mods()
	var actor_id := _uid(actor_unit)
	if actor_id == "" or actor_unit.is_empty():
		return m
	var owner := int(actor_unit.get("owner", 0))
	var target_id := _uid(target_unit)
	var target_ok := target_id != "" and not target_unit.is_empty()
	var target_head := head_id(target_id) if target_ok else ""

	# --- Forgefather: any friendly ADEPTUS ASTARTES attacker vs the marked unit --
	if target_ok and not is_melee and Common.has_keyword(actor_unit, KW_AA) and Common.is_sm_army(owner):
		var ff = _gflag(target_head, F_FORGEFATHER)
		if typeof(ff) == TYPE_DICTIONARY and int(ff.get("player", 0)) == owner and str(ff.get("phase_key", "")) == _phase_key():
			var wt := _weapon_text(weapon_profile)
			if "melta" in wt or "torrent" in wt:
				m.strength += 2
				_src(m, "Forgefather", "other", "strength", "[MELTA]/[TORRENT] attack vs the Forgefather's chosen unit: +2 S")

	# Every ability below is held by an M4c component — skip other attackers fast.
	var any_m4c := false
	for gid in group(actor_id):
		if is_m4c_sheet(Common.unit(str(gid))):
			any_m4c = true
			break
	if not any_m4c and not is_m4c_sheet(actor_unit):
		return m
	var charged := _group_charged(actor_id) or bool(actor_unit.get("flags", {}).get("charged_this_turn", false))
	var target_char := target_ok and Common.group_has_keyword(target_head, "CHARACTER")
	var target_mv := target_ok and _is_mv(target_head)

	# --- "this model" abilities (the model's own unit dict) -------------------
	if target_char and has(actor_unit, "calgars_champion"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
		_src(m, "Calgar's Champion", "hit", "reroll_ones", "target is a CHARACTER unit")
		_src(m, "Calgar's Champion", "wound", "reroll_ones", "target is a CHARACTER unit")

	# --- "this unit" abilities (the whole Attached unit) -----------------------
	if target_char and group_has(actor_id, "trophy_taker"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
		_src(m, "Trophy Taker", "hit", "reroll_ones", "target is a CHARACTER unit")
		_src(m, "Trophy Taker", "wound", "reroll_ones", "target is a CHARACTER unit")
	if is_melee and charged and group_has(actor_id, "for_the_khan"):
		m.wound_plus = true
		_src(m, "For the Khan!", "wound", "plus_one", "[LANCE]: made a charge move this turn")
	if is_melee and charged and group_has(actor_id, "full_throttle_assault"):
		var wname := str(weapon_profile.get("name", "")).to_lower()
		m.sustained = maxi(m.sustained, 1)
		if "thunder hammer" in wname:
			m.hit_plus = true
			_src(m, "Full-throttle Assault", "hit", "plus_one", "charged: Thunder Hammer +1 to hit and [SUSTAINED HITS 1]")
		else:
			m.damage += 1
			_src(m, "Full-throttle Assault", "other", "damage", "charged: melee +1 D and [SUSTAINED HITS 1]")
	if not is_melee and target_ok and group_has(actor_id, "executioner"):
		var gs = Common.game_state()
		var below: bool = gs != null and gs.has_method("is_below_half_strength_combined") and bool(gs.is_below_half_strength_combined(target_head))
		if not below:
			m.hit_plus = true
			_src(m, "Executioner", "hit", "plus_one", "target is not below half-strength")
	if not is_melee and target_ok and _phase() == PH_SHOOTING and Common.active_player() == owner \
			and group_has(actor_id, "aggressive_reconnaissance") and isolated_from_other_enemies(target_head):
		m.wound_plus = true
		_src(m, "Aggressive Reconnaissance", "wound", "plus_one", "your Shooting phase: target is more than 6\" from any other enemy unit")
	if is_melee and group_has(actor_id, "press_the_attack"):
		var titus := group_holder(actor_id, "press_the_attack")
		if Common.doctrine_active_id(titus, "assault") or Common.doctrine_active_id(actor_id, "assault"):
			m.sustained = maxi(m.sustained, 1)
			_src(m, "Press the Attack", "other", "sustained_hits", "assault doctrine active: melee [SUSTAINED HITS 1]")
		elif target_ok and not target_mv:
			m.sustained = maxi(m.sustained, 1)
			_src(m, "Press the Attack", "other", "sustained_hits", "melee [SUSTAINED HITS 1] vs a non-MONSTER/VEHICLE unit")
	if is_melee:
		var rf = _gflag(actor_id, F_RF)
		if typeof(rf) == TYPE_DICTIONARY and str(rf.get("phase_key", "")) == _phase_key():
			m.strength += 1
			_src(m, "Righteous Fury", "other", "strength", "melee +1 S this phase")
		if str(_gflag(actor_id, F_BANNER)) == _phase_key():
			m.strength += 1
			m.attacks += 1
			_src(m, "Banner of Macragge", "other", "attacks", "melee +1 A and +1 S")
	var cold = _gflag(actor_id, F_COLD)
	if typeof(cold) == TYPE_DICTIONARY and str(cold.get("phase_key", "")) == _phase_key() and target_ok:
		var mode := str(cold.get("mode", ""))
		if target_mv and mode in ["lethal", "both"]:
			m.lethal = true
			_src(m, "Cold and Calculating", "other", "lethal_hits", "[LETHAL HITS] vs MONSTER/VEHICLE")
		if not target_mv and mode in ["sustained", "both"]:
			m.sustained = maxi(m.sustained, 1)
			_src(m, "Cold and Calculating", "other", "sustained_hits", "[SUSTAINED HITS 1] vs non-MONSTER/VEHICLE")
	if not is_melee and target_ok:
		var ov = _gflag(actor_id, F_OVERLAP)
		if typeof(ov) == TYPE_DICTIONARY and str(ov.get("phase_key", "")) == _phase_key() and head_id(str(ov.get("target", ""))) == target_head \
				and "heavy bolter" in str(weapon_profile.get("name", "")).to_lower() and group_has(actor_id, "overlapping_destruction"):
			var bonus := int(_alive_models(target_head) / 5)
			if bonus > 0:
				m.attacks += bonus
			_src(m, "Overlapping Destruction", "other", "attacks", "Heavy Bolter [BLAST 1] vs the selected unit: +%d attack(s) (%d models)" % [bonus, _alive_models(target_head)])
	return m

## Aggressive Reconnaissance: the enemy unit is more than 6" from every other unit of its army.
static func isolated_from_other_enemies(enemy_head: String) -> bool:
	var eu := Common.unit(enemy_head)
	var eowner := int(eu.get("owner", 0))
	for oid in Common.friendly_heads(eowner):
		if str(oid) == enemy_head:
			continue
		if _dist(enemy_head, str(oid)) <= ISOLATED_RANGE_IN + 0.001:
			return false
	return true

## AQUILON OPTICS (Gladiator Lancer): "ranged attacks that target a
## MONSTER/VEHICLE unit can: re-roll one hit roll, one wound roll, one damage
## roll". Rides the engine's single-re-roll grant (the Custodes PRIME TARGET
## flag cus11e_prime_target {hit, wound, damage}, read by every ranged
## resolver path): projected onto the attacker dict for each target the
## aggregator is asked about — present (with the unspent re-rolls) vs a
## MONSTER/VEHICLE target, absent otherwise. Spent re-rolls are synced back
## into the per-phase ledger F_AQUILON so they stay spent across targets.
static func _aquilon_project(actor_unit: Dictionary, target_unit: Dictionary, is_melee: bool) -> void:
	if is_melee or not has(actor_unit, "aquilon_optics"):
		return
	_aquilon_project_one(actor_unit, target_unit)
	# The interactive shooting dialog reads the LIVE unit (ShootingPhase
	# _cus11e_prime_target_reroll) while the resolver works on a board copy:
	# mirror the projection onto the live unit too.
	var live := Common.unit(_uid(actor_unit))
	if not live.is_empty() and not is_same(live, actor_unit):
		_aquilon_project_one(live, target_unit)

static func _aquilon_project_one(actor_unit: Dictionary, target_unit: Dictionary) -> void:
	if not actor_unit.has("flags") or typeof(actor_unit.flags) != TYPE_DICTIONARY:
		actor_unit["flags"] = {}
	var flags: Dictionary = actor_unit.flags
	var key := _phase_key()
	var led = flags.get(F_AQUILON, null)
	if typeof(led) != TYPE_DICTIONARY or str(led.get("key", "")) != key:
		led = {"hit": true, "wound": true, "damage": true, "key": key}
	else:
		led = (led as Dictionary).duplicate()
	var pt = flags.get(PT_FLAG, null)
	if typeof(pt) == TYPE_DICTIONARY and bool(pt.get("sm11e_aquilon", false)):
		for st in ["hit", "wound", "damage"]:
			if not bool(pt.get(st, true)):
				led[st] = false
	flags[F_AQUILON] = led
	var tid := _uid(target_unit)
	if tid != "" and _is_mv(head_id(tid)):
		flags[PT_FLAG] = {"hit": bool(led.hit), "wound": bool(led.wound), "damage": bool(led.damage), "sm11e_aquilon": true}
	elif typeof(pt) == TYPE_DICTIONARY and bool(pt.get("sm11e_aquilon", false)):
		flags.erase(PT_FLAG)


# ===========================================================================
# DEFENSIVE / MOVEMENT / MISC passive hooks
# ===========================================================================

## Duty Eternal (Redemptor): attacks with S > this unit's T have -1 to wound.
static func incoming_wound_penalty_source(target_unit: Dictionary, strength: int, toughness: int) -> String:
	if strength <= toughness or not _edition_11():
		return ""
	var tid := _uid(target_unit)
	if tid != "" and group_has(tid, "duty_eternal"):
		return "Duty Eternal"
	return ""

static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	return incoming_wound_penalty_source(target_unit, strength, toughness) != ""

## Command Squad (Company Heroes) / Honour Guard of Macragge (Victrix Honour
## Guard): "Attacks that target this unit have -1 to wound rolls" — the whole
## Attached unit (the target of an attack is the unit).
static func incoming_minus_one_wound(target_unit: Dictionary) -> bool:
	if not _edition_11() or target_unit.is_empty():
		return false
	var tid := _uid(target_unit)
	if tid == "":
		return false
	return group_has(tid, "command_squad") or group_has(tid, "honour_guard_of_macragge")

## Advance-and-charge: Spear of Chogoris (Suboden's Attached unit).
static func advance_allows_charge(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return false
	return group_has(_uid(unit), "spear_of_chogoris")

## Ranged [ASSAULT]: For the Khan! (Kor'sarro), Spear of Chogoris (Suboden).
static func ranged_attacks_have_assault(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return false
	return group_has(_uid(unit), "for_the_khan") or group_has(_uid(unit), "spear_of_chogoris")

## Spear of Chogoris: "If the assault doctrine is active for this unit, this
## unit has +1 to advance rolls and charge rolls." {bonus, source}
static func roll_bonus(unit_id: String) -> Dictionary:
	var none := {"bonus": 0, "source": ""}
	if not _edition_11() or unit_id == "":
		return none
	var h := group_holder(unit_id, "spear_of_chogoris")
	if h == "":
		return none
	for gid in group(unit_id):
		if Common.doctrine_active_id(str(gid), "assault"):
			return {"bonus": 1, "source": "Spear of Chogoris (assault doctrine)"}
	return none

## Master of Shadows: the selected unit can re-roll charge rolls until the
## start of its player's next Command phase. "" or the source name.
static func charge_reroll_source(unit: Dictionary) -> String:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return ""
	var f = _gflag(_uid(unit), F_SHADOWS)
	if typeof(f) == TYPE_DICTIONARY:
		return "Master of Shadows"
	return ""

## Purgation Run: "This unit is not eligible to declare a charge until the end
## of the turn" — a hard lock (no advance-and-charge override).
static func blocks_charge(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty():
		return false
	return str(unit.get("flags", {}).get(F_NO_CHARGE, "")) == _turn_key()

## Trifold Path of Shadow: "This unit has Stealth" (the whole Attached unit).
static func grants_stealth(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return false
	return group_has(_uid(unit), "trifold_path_of_shadow")

## Trifold Path of Shadow: "-3\" detection range" (the 9" floor still applies).
static func detection_range_bonus(unit: Dictionary) -> float:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return 0.0
	return TRIFOLD_DETECTION_IN if group_has(_uid(unit), "trifold_path_of_shadow") else 0.0

## Grapnel Launchers: "When this unit makes a move, this unit can move through
## all types of model" (Movement-phase normal / advance moves).
static func moves_through_models(unit_id: String) -> bool:
	return _edition_11() and unit_id != "" and group_has(unit_id, "grapnel_launchers")

## Grapnel Launchers: "ignore all vertical distance for the purposes of how far
## this unit has moved".
static func ignores_vertical_distance(unit_id: String) -> bool:
	return moves_through_models(unit_id)

## Grav-chutes (Reivers) / Thunderhawk Insertion (picked unit): Deep Strike.
static func grants_deep_strike(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty():
		return false
	if has(unit, "grav_chutes"):
		return true
	return bool(unit.get("flags", {}).get(F_DEEP_STRIKE, false)) and is_sm_unit(unit)

## Cerebrex Logic Engine: the selected unit has Scouts 6". 0 = none.
static func scouts_distance(unit: Dictionary) -> float:
	if not _edition_11() or unit.is_empty():
		return 0.0
	return 6.0 if bool(unit.get("flags", {}).get(F_SCOUTS, false)) and is_sm_unit(unit) else 0.0

## Tempormortis (Judiciar): "This unit has Fights First" — the whole Attached
## unit the Judiciar belongs to.
static func group_fights_first(unit: Dictionary) -> bool:
	if not _edition_11() or unit.is_empty() or _uid(unit) == "":
		return false
	return group_has(_uid(unit), "tempormortis")

## Captain of the Honour Guard: "If your army includes a Marneus Calgar unit,
## replace this unit's Leader ability with the Support ability."
static func leader_becomes_support(character: Dictionary) -> bool:
	if not has(character, "captain_of_the_honour_guard"):
		return false
	var owner := int(character.get("owner", 0))
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) == owner and Common.has_keyword(u, "MARNEUS CALGAR") and Common.is_alive(u):
			return true
	return false

## Feel No Pain grants: Seeker of the Unfound (Vulkan within range of his
## objective, 4+), Veteran Bodyguard (other CHARACTER models of Kaius's unit, 4+).
static func unit_fnp(unit: Dictionary) -> int:
	if not _edition_11() or unit.is_empty():
		return 0
	var best := 0
	if seeker_active(unit):
		best = SEEKER_FNP
	var uid := _uid(unit)
	if uid != "" and Common.has_keyword(unit, "CHARACTER") and not has(unit, "veteran_bodyguard"):
		for gid in group(uid):
			if str(gid) != uid and has_id(str(gid), "veteran_bodyguard") and Common.is_alive(Common.unit(str(gid))):
				best = VETERAN_BODYGUARD_FNP if best == 0 else mini(best, VETERAN_BODYGUARD_FNP)
	return best

## Seeker of the Unfound: Vulkan is within range of the objective he chose.
static func seeker_active(unit: Dictionary) -> bool:
	if not has(unit, "seeker_of_the_unfound") or not Common.is_on_battlefield(unit):
		return false
	var oid := str(unit.get("flags", {}).get(F_SEEKER_OBJ, ""))
	if oid == "":
		return false
	var obj := Common.objective_by_id(oid)
	if obj.is_empty():
		return false
	var mm = Common.mission_manager()
	if mm and mm.has_method("_model_in_objective_range"):
		for m in unit.get("models", []):
			if m.get("alive", true) and m.get("position", null) != null and bool(mm._model_in_objective_range(m, obj, [])):
				return true
		return false
	return Common.group_in_objective_range(_uid(unit), obj)

## Seeker of the Unfound: 5+ Ld while within range (Ld characteristic).
static func leadership(unit: Dictionary, ld: int) -> int:
	if seeker_active(unit):
		return mini(ld, SEEKER_LD)
	return ld

## OC after Terror Troops (enemy model within 3" of Reivers: -1), Honour of
## the Company (Ancient's Attached unit: +1) and Seeker of the Unfound (10).
static func model_oc(unit: Dictionary, model: Dictionary, oc: int) -> int:
	if not _edition_11() or unit.is_empty():
		return oc
	var uid := _uid(unit)
	if uid == "":
		return oc
	var out := oc
	if seeker_active(unit):
		out = SEEKER_OC
	if group_has(uid, "honour_of_the_company") and Common.is_sm_army(int(unit.get("owner", 0))):
		out += 1
	if out > 0 and model.get("position", null) != null and terror_troops_source(unit, model) != "":
		out -= 1
	return maxi(out, 0)

## Terror Troops (Aura): the Reiver unit within 3" of this ENEMY model, or "".
static func terror_troops_source(unit: Dictionary, model: Dictionary) -> String:
	var owner := int(unit.get("owner", 0))
	for rid in Common.state().get("units", {}):
		var r := Common.unit(str(rid))
		if int(r.get("owner", 0)) == owner or int(r.get("owner", 0)) == 0 or not has(r, "terror_troops") or not Common.is_on_battlefield(r):
			continue
		if Common.unit_distance_inches({"models": [model]}, r) <= TERROR_RANGE_IN + 0.001:
			return str(rid)
	return ""

## Rhino Veiling Smoke / Aethon Shaan Blackwing Mantle: "You can target this
## unit with the X stratagem, regardless of any other uses of that stratagem
## this phase. That use is -1 CP and does not prevent other uses" — the
## CustodesEnhancements.stratagem_override shape (recorded through its
## record_stratagem_override: flag = phase stamp on the bearer).
static func stratagem_override(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	var none := {"applies": false}
	if not _edition_11() or target_unit_id == "":
		return none
	var sid := stratagem_id.replace("_11e", "")
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return none
	if sid == "smokescreen":
		var rh := group_holder(target_unit_id, "veiling_smoke")
		if rh == "":
			return none
		# (Once per phase, per unit)
		if str(Common.unit(rh).get("flags", {}).get("sm11e_abc_veiling_smoke_stamp", "")) == _phase_key():
			return none
		return {"applies": true, "source": "Veiling Smoke", "cost_delta": -1, "flag": "sm11e_abc_veiling_smoke_stamp", "bearer_id": rh}
	if sid == "heroic_intervention":
		var ah := group_holder(target_unit_id, "blackwing_mantle")
		if ah == "":
			return none
		# (Once per phase, per army)
		for hid in _holders(player, "blackwing_mantle", false):
			if str(Common.unit(hid).get("flags", {}).get("sm11e_abc_blackwing_stamp", "")) == _phase_key():
				return none
		return {"applies": true, "source": "Blackwing Mantle", "cost_delta": -1, "flag": "sm11e_abc_blackwing_stamp", "bearer_id": ah}
	return none

## Honour or Death (Cato Sicarius): "When you target this unit with the Heroic
## Intervention stratagem, that use is -1 CP." Returns the discount (0 or 1).
static func stratagem_cp_discount(player: int, stratagem_id: String, target_unit_id: String) -> int:
	if not _edition_11() or target_unit_id == "":
		return 0
	if stratagem_id.replace("_11e", "") != "heroic_intervention":
		return 0
	var u := Common.unit(target_unit_id)
	if int(u.get("owner", 0)) != player or not group_has(target_unit_id, "honour_or_death"):
		return 0
	return 1

## Total Obliteration (Eradicators with Melta Rifles): "This unit's ranged
## attacks can re-roll damage rolls" — the engine re-rolls a variable damage
## roll below the dice average (never worse on average), once per roll.
static func reroll_damage(dmg_result: Dictionary, damage_raw: String, attacker_unit: Dictionary, rng, is_melee: bool) -> Dictionary:
	if is_melee or not bool(dmg_result.get("rolled", false)) or attacker_unit.is_empty() or dmg_result.has("sm11e_reroll_from"):
		return dmg_result
	var aid := _uid(attacker_unit)
	if aid == "" or not (has(attacker_unit, "total_obliteration") or group_has(aid, "total_obliteration")):
		return dmg_result
	if float(dmg_result.get("value", 0)) >= _avg_dice(damage_raw):
		return dmg_result
	var re = Common.rules()
	if re == null:
		return dmg_result
	var again: Dictionary = re.roll_variable_characteristic(damage_raw, rng)
	_log("Total Obliteration: damage roll %s re-rolled %d -> %d" % [damage_raw, int(dmg_result.get("value", 0)), int(again.get("value", 0))])
	again["sm11e_reroll_from"] = int(dmg_result.get("value", 0))
	return again

static func _avg_dice(raw: String) -> float:
	var s := raw.to_upper().replace(" ", "")
	var plus := 0.0
	if "+" in s:
		var parts := s.split("+")
		s = parts[0]
		plus = float(parts[1]) if parts[1].is_valid_float() else 0.0
	var d := s.find("D")
	if d < 0:
		return float(s) + plus if s.is_valid_float() else plus
	var n := 1.0 if d == 0 else (float(s.substr(0, d)) if s.substr(0, d).is_valid_float() else 1.0)
	var faces := float(s.substr(d + 1)) if s.substr(d + 1).is_valid_float() else 6.0
	return n * (faces + 1.0) / 2.0 + plus

## Transport capacity keywords (ArmyListManager hook, Rhino / Repulsor /
## Repulsor Executioner and every other Space Marine transport): the army
## files print the capacity as "14 SPACE MARINES INFANTRY models" (the codex:
## "Adeptus Astartes Infantry"); the parser splits words, so SPACE + MARINES
## (or ADEPTUS + ASTARTES) became two keywords no unit has and nothing could
## embark. They are the one faction keyword ADEPTUS ASTARTES.
static func transport_capacity_keywords(words: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < words.size():
		var w := str(words[i]).to_upper()
		var nxt := str(words[i + 1]).to_upper() if i + 1 < words.size() else ""
		if (w == "SPACE" and nxt == "MARINES") or (w == "ADEPTUS" and nxt == "ASTARTES"):
			if not KW_AA in out:
				out.append(KW_AA)
			i += 2
			continue
		out.append(str(words[i]))
		i += 1
	return out

## Into the Fray (Captain on Bike): "If this unit made a charge move this
## turn, this unit's melee attacks have [CLEAVE 1]" — the whole Attached unit.
static func melee_cleave(attacker_unit: Dictionary) -> int:
	if not _edition_11() or attacker_unit.is_empty():
		return 0
	var aid := _uid(attacker_unit)
	if aid == "" or not group_has(aid, "into_the_fray"):
		return 0
	return 1 if (_group_charged(aid) or bool(attacker_unit.get("flags", {}).get("charged_this_turn", false))) else 0

## Honour of Ultramar (Captain Titus): Fight On Death (core 05.04.05) 2+ for
## his own model. {source, pass} or {}.
static func fod_rule(unit_id: String, _idx: int) -> Dictionary:
	if not _edition_11() or _phase() != PH_FIGHT:
		return {}
	if has_id(unit_id, "honour_of_ultramar"):
		return {"source": "Honour of Ultramar", "pass": HONOUR_OF_ULTRAMAR_PASS}
	return {}


# ===========================================================================
# AUTOMATIC triggers
# ===========================================================================

## Raise the Banner (Company Heroes, Ancient, Wardens of Ultramar) and the
## Banner of Macragge (Victrix Honour Guard): "At the end of your Movement
## phase, if this unit is controlling an objective, that objective is
## secured" — MovementPhase hook next to Thievin' Scavengers.
static func on_movement_phase_end(player: int) -> void:
	if not _edition_11():
		return
	var mm = Common.autoload("MissionManager")
	if mm == null or not mm.has_method("secure_objective"):
		return
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u) or Common.is_battle_shocked(u):
			continue
		var src := ""
		if has(u, "raise_the_banner"):
			src = "Raise the Banner"
		elif has(u, "banner_of_macragge"):
			src = "Banner of Macragge"
		if src == "":
			continue
		for obj in Common.objectives():
			var oid := str(obj.get("id", ""))
			if oid == "" or Common.objective_controller(oid) != player:
				continue
			if not Common.group_in_objective_range(str(uid), obj):
				continue
			mm.secure_objective(oid, player, "")
			_event_log(player, "%s: %s secures objective %s" % [src, Common.unit_name(str(uid)), Common.objective_label(oid)])
			_log("%s — %s secured %s for P%d" % [src, uid, oid, player])

## Fearsome Assault (Reivers): "At the start of the Fight phase, each enemy
## unit engaged with a unit with this ability makes a battle-shock roll, with
## -1 to that battle-shock roll." FightPhase hook (single-player / host).
static func on_fight_phase_start() -> Array:
	var all: Array = []
	if not _edition_11():
		return all
	var nm = Common.autoload("NetworkManager")
	if nm and nm.has_method("is_networked") and bool(nm.is_networked()) and nm.has_method("is_host") and not bool(nm.is_host()):
		return all
	var tested := {}
	var re = Common.rules()
	var rng = re.make_rng() if re and re.has_method("make_rng") else null
	for rid in Common.state().get("units", {}):
		var r := Common.unit(str(rid))
		if not has(r, "fearsome_assault") or not Common.is_on_battlefield(r):
			continue
		var player := int(r.get("owner", 0))
		for eid in Common.engaged_enemy_ids(str(rid)):
			var eh := head_id(str(eid))
			if tested.has(eh):
				continue
			tested[eh] = true
			var bs := _battle_shock_roll(eh, -1, rng)
			all.append_array(bs.diffs)
			var msg := "Fearsome Assault (%s): %s battle-shock roll %d+%d -1 = %d vs Ld %d+ — %s" % [
				Common.unit_name(str(rid)), Common.group_label(eh), bs.roll[0], bs.roll[1], bs.total, bs.ld,
				"passed" if bs.passed else "FAILED, battle-shocked"]
			_event_log(player, msg)
			_log(msg)
	if not all.is_empty():
		Common.apply_diffs(all)
	return all

static func _best_leadership(unit_id: String) -> int:
	var ld := 0
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		var v := int(u.get("meta", {}).get("stats", {}).get("leadership", 7))
		v = leadership(u, v)
		ld = maxi(ld, v)
	return ld if ld > 0 else 7

static func _battle_shock_roll(unit_id: String, mod: int, rng) -> Dictionary:
	var d1 := int(rng.roll_d6(1)[0]) if rng else int(Common.roll_dice(1)[0])
	var d2 := int(rng.roll_d6(1)[0]) if rng else int(Common.roll_dice(1)[0])
	var total := d1 + d2 + mod
	var ld := _best_leadership(unit_id)
	var passed := total >= ld
	var diffs: Array = []
	if not passed:
		for gid in group(unit_id):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
	return {"diffs": diffs, "roll": [d1, d2], "total": total, "ld": ld, "passed": passed}

## Righteous Fury: "when this unit has fought: this model heals D3, or 2D3 if
## this model destroyed an enemy model this phase" — FightPhase hook at the
## end of the activation. Returns diffs (applied).
static func on_unit_has_fought(unit_id: String) -> Array:
	var diffs: Array = []
	if not _edition_11() or unit_id == "":
		return diffs
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		var rf = u.get("flags", {}).get(F_RF, null)
		if typeof(rf) != TYPE_DICTIONARY or str(rf.get("phase_key", "")) != _phase_key() or bool(rf.get("healed", false)):
			continue
		if not has(u, "righteous_fury") or not Common.is_alive(u):
			continue
		var killed := false
		var before: Dictionary = rf.get("targets", {})
		for eid in before:
			if _alive_models(str(eid)) < int(before[eid]):
				killed = true
		var dice: Array = Common.roll_dice(2 if killed else 1, 3)
		var amount := 0
		for d in dice:
			amount += int(d)
		var h := heal_diffs(str(gid), amount, true)
		diffs.append_array(h.diffs)
		var nrf: Dictionary = (rf as Dictionary).duplicate(true)
		nrf["healed"] = true
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), F_RF], "value": nrf})
		var msg := "Righteous Fury: %s has fought — heals %s %s = %d wound(s)%s" % [Common.unit_name(str(gid)),
			"2D3" if killed else "D3", str(dice), int(h.healed), " (an enemy model was destroyed this phase)" if killed else ""]
		_event_log(int(u.get("owner", 0)), msg)
		_log(msg)
	if not diffs.is_empty():
		Common.apply_diffs(diffs)
	return diffs


# ===========================================================================
# EXPIRY / permanent states — PhaseManager.transition_to_phase (thin hook)
# ===========================================================================

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
		# phase-scoped grants
		for f in [F_FORGEFATHER, F_OVERLAP, F_COLD, F_BANNER, F_RF]:
			if flags.has(f):
				flags.erase(f)
				cleared.append("%s.%s" % [uid, f])
		if flags.has(PT_FLAG) and typeof(flags[PT_FLAG]) == TYPE_DICTIONARY and bool(flags[PT_FLAG].get("sm11e_aquilon", false)):
			flags.erase(PT_FLAG)
		if new_phase == PH_COMMAND and int(u.get("owner", 0)) == active:
			# "until the start of your next Command phase"
			if flags.has(F_SHADOWS):
				flags.erase(F_SHADOWS)
				cleared.append("%s.%s" % [uid, F_SHADOWS])
			if flags.has(F_DOCTRINE_SRC):
				if str(flags.get(SW_DOCTRINE, "")) != "" and int(flags.get(SW_DOCTRINE_EXPIRES, 0)) == active:
					flags.erase(SW_DOCTRINE)
					flags.erase(SW_DOCTRINE_EXPIRES)
				flags.erase(F_DOCTRINE_SRC)
				cleared.append("%s.%s" % [uid, F_DOCTRINE_SRC])
		if old_phase == PH_FIGHT and flags.has("ork11e_fod_source") and str(flags.get("ork11e_fod_source", "")) == "Honour of Ultramar" and not flags.has("ork11e_fod_mode"):
			flags.erase("ork11e_fod_source")
	_apply_permanent_grants()
	if not cleared.is_empty():
		_log("phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])

## Codex Adept (Marneus Calgar): the assault, devastator and tactical doctrines
## are active for this unit — the SWCommon per-unit additional-doctrines key on
## every component of Calgar's (Attached) unit. Skilled Riders (Suboden Khan):
## "This unit has Mobile" — the engine's MOBILE grant on every component.
static func _apply_permanent_grants() -> void:
	var units: Dictionary = Common.state().get("units", {})
	var want_ca: Dictionary = {}
	var want_mob: Dictionary = {}
	for uid in units:
		var u: Dictionary = units[uid]
		if not Common.is_alive(u):
			continue
		if has(u, "codex_adept"):
			for gid in group(str(uid)):
				want_ca[str(gid)] = true
		if has(u, "skilled_riders"):
			for gid in group(str(uid)):
				want_mob[str(gid)] = true
	for uid in units:
		var u: Dictionary = units[uid]
		if not u.has("flags") or typeof(u.flags) != TYPE_DICTIONARY:
			u["flags"] = {}
		var flags: Dictionary = u.flags
		if want_ca.has(str(uid)):
			flags[SW_DOCTRINE_EXTRA] = Common.DOCTRINES.duplicate()
			flags[F_CODEX_ADEPT] = true
		elif bool(flags.get(F_CODEX_ADEPT, false)):
			flags.erase(SW_DOCTRINE_EXTRA)
			flags.erase(F_CODEX_ADEPT)
		if want_mob.has(str(uid)):
			if not bool(flags.get(ORK_MOBILE, false)):
				flags[ORK_MOBILE] = true
				flags[F_MOBILE] = true
		elif bool(flags.get(F_MOBILE, false)):
			flags.erase(ORK_MOBILE)
			flags.erase(F_MOBILE)


# ===========================================================================
# ACTIVATED ABILITIES — ability cards in the stratagem-window framework
# ===========================================================================

## window id -> slugs offered there.
const WINDOW_ABILITIES := {
	"phase_start": ["strategic_acumen", "narthecium", "master_of_shadows", "seeker_of_the_unfound",
		"forgefather", "overlapping_destruction", "master_tactician"],
	"unit_selected_to_shoot": ["overlapping_destruction", "cold_and_calculating"],
	"unit_has_shot": ["purgation_run"],
	"unit_selected_to_fight": ["cold_and_calculating", "righteous_fury", "banner_of_macragge"],
	"unit_ended_charge_move": ["hammer_of_wrath"],
	"enemy_ended_move": ["knight_champion_of_macragge"],
	"enemy_has_shot": ["glory_of_ultramar"],
	"fight_phase_end": ["echo_of_the_ravenspire"],
	"enemy_declares_charge": ["combat_embarkation"],
}

const EFFECT_TEXT := {
	"strategic_acumen": "Select one combat doctrine to be active for this unit until the start of your next Command phase.",
	"narthecium": "This unit heals D3+1 wounds.",
	"master_of_shadows": "Select one friendly ADEPTUS ASTARTES INFANTRY unit: it can re-roll charge rolls until the start of your next Command phase.",
	"seeker_of_the_unfound": "Select one objective: while this model is within range of it, it has OC 10, Ld 5+ and Feel No Pain 4+.",
	"forgefather": "Select one visible enemy unit within 24\": friendly ADEPTUS ASTARTES units' [MELTA]/[TORRENT] attacks that target it have +2 S this phase.",
	"overlapping_destruction": "Select one enemy unit: this unit's Heavy Bolter weapons that target it have [BLAST 1] this phase.",
	"master_tactician": "Select one visible friendly ADEPTUS ASTARTES unit within 9\" and one combat doctrine: that doctrine is active for that unit until the start of your next Command phase.",
	"cold_and_calculating": "This unit's attacks have [LETHAL HITS] vs MONSTER/VEHICLE, or [SUSTAINED HITS 1] vs other units — or both while the tactical doctrine is active.",
	"purgation_run": "This unit can make a normal move of up to D6\"; it is then not eligible to declare a charge until the end of the turn.",
	"righteous_fury": "Once per battle: this unit's melee attacks have +1 S; when it has fought, this model heals D3 (2D3 if it destroyed an enemy model this phase).",
	"banner_of_macragge": "Once per battle: this unit's melee attacks have +1 A and +1 S.",
	"hammer_of_wrath": "Select one enemy unit engaged with this unit: roll one D6 per model of this unit engaged with it — each 4+ inflicts 1 mortal wound.",
	"knight_champion_of_macragge": "Once per phase: that enemy unit ended a move within 8\" — this unengaged unit can make a normal move of up to 6\".",
	"glory_of_ultramar": "A model of this unit was destroyed by those attacks — this unit can make a surge move of up to D6\".",
	"echo_of_the_ravenspire": "This unengaged unit is placed in strategic reserves.",
	"combat_embarkation": "A friendly unengaged ADEPTUS ASTARTES unit that was a charge target, wholly within 3\" of this TRANSPORT, embarks within it.",
}

const REOFFER_WINDOWS := ["phase_start"]
const REOFFER_IF_ABILITY_LEFT := ["unit_selected_to_shoot", "unit_selected_to_fight", "enemy_has_shot", "enemy_declares_charge"]

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

## ScenarioRunner policy (WP-C7 / WP-S4 shape): scenarios that do not opt in
## ("sm_abilities_c": true) never answer these cards, so the runner switches
## the OFFERS off; passive abilities still apply.
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

## "Start of the phase" window entries for BasePhase.enter_phase.
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

static func _doctrine_variants(ai_pick: String) -> Array:
	var out: Array = []
	for d in Common.DOCTRINES:
		out.append({"id": str(d), "label": str(Common.DOCTRINE_LABELS.get(d, d))})
	return out

## The AI's doctrine for a unit: tactical when engaged, assault for a melee
## unit 6-16" from the enemy, else devastator (the WP-S3 Grimnar's Command shape).
static func ai_doctrine(unit_id: String) -> String:
	if _engaged(unit_id):
		return "tactical"
	var d := Common.nearest_enemy_inches(Common.group_union(unit_id))
	if Common.group_has_melee_weapons(unit_id) and d >= 6.0 and d <= 16.0:
		return "assault"
	return "devastator"

static func _threat(unit_id: String) -> float:
	var s := 0.0
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		s += float(u.get("meta", {}).get("points", 0))
		if Common.has_keyword(u, "CHARACTER"):
			s += 50.0
	return s

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := _phase()
	var own_turn := Common.active_player() == player
	match slug:
		"strategic_acumen":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug) or not Common.has_combat_doctrines(Common.unit(hid)):
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid),
					"variants": _doctrine_variants(""), "require_variant": true, "ai_variant": ai_doctrine(hid)}))
		"narthecium":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug) or not _healable(hid):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"master_of_shadows":
			if window_id != "phase_start" or phase != PH_COMMAND or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var cands: Array = []
				for fid in Common.friendly_heads(player):
					var fu := Common.unit(str(fid))
					if not Common.group_has_keyword(str(fid), KW_AA) or not Common.group_has_keyword(str(fid), "INFANTRY") or not Common.is_on_battlefield(fu):
						continue
					cands.append(str(fid))
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return Common.nearest_enemy_inches(Common.group_union(str(a))) < Common.nearest_enemy_inches(Common.group_union(str(b))))
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid),
					"secondary": _unit_options(cands, "Master of Shadows: select one friendly ADEPTUS ASTARTES INFANTRY unit — it can re-roll charge rolls until your next Command phase")}))
		"seeker_of_the_unfound":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug):
				var f: Dictionary = Common.unit(hid).get("flags", {})
				if str(f.get(F_SEEKER_OBJ, "")) != "":
					continue
				var opts: Array = []
				var objs: Array = Common.objectives().duplicate()
				objs.sort_custom(func(a, b): return _obj_dist(hid, a) < _obj_dist(hid, b))
				for obj in objs:
					var oid := str(obj.get("id", ""))
					if oid != "":
						opts.append({"id": oid, "label": Common.objective_label(oid)})
				if opts.is_empty():
					continue
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid),
					"secondary": {"kind": "objective", "prompt": "Seeker of the Unfound: select one objective on the battlefield", "options": opts}}))
		"forgefather":
			if window_id != "phase_start" or phase != PH_SHOOTING or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				var cands := _enemies_in_range_visible(hid, player, FORGEFATHER_RANGE_IN)
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return int(_is_mv(str(a))) > int(_is_mv(str(b))))
				out.append(_entry(hid, {"holder": hid, "label": Common.unit_name(hid),
					"secondary": _unit_options(cands, "Forgefather: select one visible enemy unit within 24\" — [MELTA]/[TORRENT] attacks against it have +2 S")}))
		"overlapping_destruction":
			if not own_turn or phase != PH_SHOOTING or not window_id in ["phase_start", "unit_selected_to_shoot"]:
				return out
			for hid in _holders(player, slug):
				if window_id == "unit_selected_to_shoot" and head_id(hid) != head_id(str(ctx.get("unit_id", ""))):
					continue
				if used_this_phase(hid, slug):
					continue
				var cands: Array = Common.enemy_heads(player).duplicate()
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return _alive_models(str(a)) > _alive_models(str(b)))
				out.append(_entry(head_id(hid), {"holder": hid,
					"secondary": _unit_options(cands, "Overlapping Destruction: select one enemy unit — Heavy Bolters that target it have [BLAST 1]")}))
		"master_tactician":
			if window_id != "phase_start" or phase != PH_MOVEMENT or not own_turn:
				return out
			for hid in _holders(player, slug):
				if used_this_phase(hid, slug):
					continue
				for fid in Common.friendly_heads(player):
					var fu := Common.unit(str(fid))
					if not Common.is_on_battlefield(fu) or not Common.group_has_keyword(str(fid), KW_AA):
						continue
					var any_cd := false
					for gid in group(str(fid)):
						if Common.has_combat_doctrines(Common.unit(str(gid))):
							any_cd = true
					if not any_cd:
						continue
					if head_id(str(fid)) != head_id(hid) and (_dist(hid, str(fid)) > MASTER_TACTICIAN_RANGE_IN + 0.001 or not _visible(hid, str(fid))):
						continue
					out.append(_entry(str(fid), {"holder": hid, "label": Common.group_label(str(fid)),
						"variants": _doctrine_variants(""), "require_variant": true, "ai_variant": ai_doctrine(str(fid))}))
		"cold_and_calculating":
			if window_id == "unit_selected_to_shoot":
				if not own_turn or phase != PH_SHOOTING:
					return out
			elif window_id == "unit_selected_to_fight":
				if phase != PH_FIGHT:
					return out
			else:
				return out
			var unit_id := str(ctx.get("unit_id", ""))
			var hid := group_holder(unit_id, slug) if unit_id != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player:
				return out
			var cold = _gflag(hid, F_COLD)
			if typeof(cold) == TYPE_DICTIONARY and str(cold.get("phase_key", "")) == _phase_key():
				return out
			var vars: Array = [{"id": "lethal", "label": "[LETHAL HITS] vs MONSTER/VEHICLE"}, {"id": "sustained", "label": "[SUSTAINED HITS 1] vs non-MONSTER/VEHICLE"}]
			var tactical := Common.doctrine_active_id(hid, "tactical")
			if tactical:
				vars.append({"id": "both", "label": "Tactical doctrine: both"})
			out.append(_entry(head_id(unit_id), {"holder": hid, "variants": vars, "require_variant": true,
				"ai_variant": "both" if tactical else _ai_cold_mode(head_id(unit_id), player)}))
		"purgation_run":
			if window_id != "unit_has_shot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter := str(ctx.get("unit_id", ""))
			var hid := group_holder(shooter, slug) if shooter != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug) or _engaged(hid):
				return out
			out.append(_entry(head_id(shooter), {"holder": hid}))
		"righteous_fury", "banner_of_macragge":
			if window_id != "unit_selected_to_fight" or phase != PH_FIGHT:
				return out
			var fighter := str(ctx.get("unit_id", ""))
			var hid := group_holder(fighter, slug) if fighter != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or army_used_in_battle(player, slug):
				return out
			out.append(_entry(head_id(fighter), {"holder": hid}))
		"hammer_of_wrath":
			if window_id != "unit_ended_charge_move":
				return out
			var charger := str(ctx.get("unit_id", ""))
			var hid := group_holder(charger, slug) if charger != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var cands: Array = []
			for eid in Common.engaged_enemy_ids(hid):
				var eh := head_id(str(eid))
				if not eh in cands:
					cands.append(eh)
			if cands.is_empty():
				return out
			cands.sort_custom(func(a, b): return _engaged_model_count(hid, str(a)) > _engaged_model_count(hid, str(b)))
			out.append(_entry(head_id(charger), {"holder": hid,
				"secondary": _unit_options(cands, "Hammer of Wrath: select one enemy unit engaged with this unit")}))
		"knight_champion_of_macragge":
			if window_id != "enemy_ended_move" or own_turn or phase != PH_MOVEMENT:
				return out
			var mover := str(ctx.get("enemy_unit_id", ""))
			if mover == "" or army_used_this_phase(player, slug):
				return out
			for hid in _holders(player, slug):
				if _engaged(hid) or _dist(hid, mover) > KNIGHT_CHAMPION_RANGE_IN + 0.001:
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"glory_of_ultramar":
			if window_id != "enemy_has_shot" or own_turn or phase != PH_SHOOTING:
				return out
			var destroyed: Array = ctx.get("models_destroyed_unit_ids", [])
			for hid in _holders(player, slug):
				var lost := false
				for gid in group(hid):
					if str(gid) in destroyed:
						lost = true
				if not lost or _engaged(hid) or _group_shocked(hid) or used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"echo_of_the_ravenspire":
			if window_id != "fight_phase_end" or own_turn or phase != PH_FIGHT:
				return out
			for hid in _holders(player, slug):
				if _engaged(hid) or used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid, "label": Common.group_label(hid)}))
		"combat_embarkation":
			if window_id != "enemy_declares_charge" or own_turn or phase != PH_CHARGE:
				return out
			var targets: Array = ctx.get("target_unit_ids", [])
			for tid in _holders(player, slug):
				if used_this_phase(tid, slug):
					continue
				var cands: Array = []
				for t in targets:
					var th := head_id(str(t))
					if th in cands or int(Common.unit(th).get("owner", 0)) != player:
						continue
					if not Common.group_has_keyword(th, KW_AA) or _engaged(th) or not Common.is_on_battlefield(Common.unit(th)):
						continue
					if not _wholly_within(th, tid, EMBARK_RANGE_IN):
						continue
					var tm = Common.autoload("TransportManager")
					if tm and tm.has_method("can_embark") and not bool(tm.can_embark(th, tid).get("valid", false)):
						continue
					cands.append(th)
				if cands.is_empty():
					continue
				out.append(_entry(tid, {"holder": tid, "label": Common.unit_name(tid),
					"secondary": _unit_options(cands, "Combat Embarkation: select the charged unit that embarks within %s" % Common.unit_name(tid))}))
	return out

static func _obj_dist(unit_id: String, obj: Dictionary) -> float:
	var pos = obj.get("position", null)
	if pos == null:
		return INF
	var p := Vector2(float(pos.get("x", 0.0)) if pos is Dictionary else float(pos.x), float(pos.get("y", 0.0)) if pos is Dictionary else float(pos.y))
	var best := INF
	for m in Common.unit(unit_id).get("models", []):
		if m.get("position", null) == null or not m.get("alive", true):
			continue
		var mp := Vector2(float(m.position.get("x", 0.0)), float(m.position.get("y", 0.0)))
		best = minf(best, mp.distance_to(p) / PX_PER_INCH)
	return best

## "If every model in that unit is within 3\" of this TRANSPORT" — every alive
## model of the (Attached) unit within 3" (edge to edge) of the transport.
static func _wholly_within(unit_id: String, transport_id: String, range_in: float) -> bool:
	var t := Common.unit(transport_id)
	for gid in group(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			if Common.unit_distance_inches({"models": [m]}, t) > range_in + 0.001:
				return false
	return true

static func _engaged_model_count(unit_id: String, enemy_id: String) -> int:
	var n := 0
	var e := Common.group_union(enemy_id)
	for gid in group(unit_id):
		for m in Common.unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			if Common.unit_distance_inches({"models": [m]}, e) <= 1.0 + 0.001:
				n += 1
	return n

static func _ai_cold_mode(unit_id: String, player: int) -> String:
	var best := ""
	var best_d := INF
	for eid in Common.enemy_heads(player):
		var d := _dist(unit_id, str(eid))
		if d < best_d:
			best_d = d
			best = str(eid)
	return "lethal" if best != "" and _is_mv(best) else "sustained"

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
	var secondary := str(context.get("secondary_id", ""))
	if entry.has("secondary"):
		var ok := false
		for o in entry.secondary.get("options", []):
			if str(o.get("id", "")) == secondary:
				ok = true
		if not ok:
			return {"success": false, "error": "%s needs a valid target" % display(slug), "diffs": []}
	var variant := str(context.get("variant_id", ""))
	if bool(entry.get("require_variant", false)):
		var vok := false
		for v in entry.get("variants", []):
			if str(v.get("id", "")) == variant:
				vok = true
		if not vok:
			return {"success": false, "error": "%s needs one of its options" % display(slug), "diffs": []}
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

## Mortal wounds (06.02) over the Attached unit (bodyguard first).
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

## Healing over the (Attached) unit — a wounded model first, else a destroyed
## model returns with 1 W (the engine's heal convention). own_model_only: only
## the unit's own models (Righteous Fury's "this model").
static func heal_diffs(unit_id: String, amount: int, own_model_only: bool = false) -> Dictionary:
	var diffs: Array = []
	var healed := 0
	var revived := 0
	var sim: Dictionary = {}
	var comps: Array = [unit_id] if own_model_only else group(unit_id)
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
		if own_model_only:
			break
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

static func _doctrine_diffs(unit_id: String, doctrine: String, player: int, source: String) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		if not Common.has_combat_doctrines(Common.unit(str(gid))):
			continue
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, SW_DOCTRINE], "value": doctrine})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, SW_DOCTRINE_EXPIRES], "value": player})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_DOCTRINE_SRC], "value": source})
	return diffs

## 18.02 embark diffs: the unit and every CHARACTER attached to it board together.
static func _embark_diffs(unit_id: String, transport_id: String) -> Array:
	var diffs: Array = []
	var transport := Common.unit(transport_id)
	var embarked: Array = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
	for gid in group(unit_id):
		diffs.append({"op": "set", "path": "units.%s.embarked_in" % gid, "value": transport_id})
		diffs.append({"op": "set", "path": "units.%s.flags.embarked_this_phase" % gid, "value": true})
		if not gid in embarked:
			embarked.append(gid)
		var g_models: Array = Common.unit(str(gid)).get("models", [])
		for i in range(g_models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	diffs.append({"op": "set", "path": "units.%s.transport_data.embarked_units" % transport_id, "value": embarked})
	return diffs

static func _apply(slug: String, player: int, uid: String, holder: String, secondary: String, variant: String, _ctx: Dictionary) -> Dictionary:
	var name := Common.group_label(uid)
	match slug:
		"strategic_acumen":
			var diffs: Array = _doctrine_diffs(uid, variant, player, "Strategic Acumen")
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Strategic Acumen: the %s is active for %s until the start of your next Command phase" % [str(Common.DOCTRINE_LABELS.get(variant, variant)), name]}
		"master_tactician":
			var diffs2: Array = _doctrine_diffs(uid, variant, player, "Master Tactician")
			diffs2.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs2, "log": "Master Tactician (%s): the %s is active for %s until the start of your next Command phase" % [Common.unit_name(holder), str(Common.DOCTRINE_LABELS.get(variant, variant)), name]}
		"narthecium":
			var d3 := int(Common.roll_dice(1, 3)[0])
			var amount := d3 + 1
			var h := heal_diffs(uid, amount)
			var diffs3: Array = h.diffs
			diffs3.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs3, "log": "Narthecium: %s heals D3+1 = %d+1 = %d wound(s) (%d wound(s) restored, %d model(s) returned)" % [name, d3, amount, int(h.healed), int(h.revived)]}
		"master_of_shadows":
			var diffs4: Array = Common.set_flag_diffs(group(secondary), F_SHADOWS, {"player": player})
			diffs4.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs4, "log": "Master of Shadows: %s can re-roll charge rolls until the start of your next Command phase" % Common.group_label(secondary)}
		"seeker_of_the_unfound":
			return {"diffs": Common.set_flag_diffs([holder], F_SEEKER_OBJ, secondary),
				"log": "Seeker of the Unfound: %s seeks objective %s — within range of it he has OC 10, Ld 5+ and Feel No Pain 4+" % [Common.unit_name(holder), Common.objective_label(secondary)]}
		"forgefather":
			var diffs5: Array = Common.set_flag_diffs(group(secondary), F_FORGEFATHER, {"player": player, "phase_key": _phase_key(), "source": holder})
			diffs5.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs5, "log": "Forgefather: friendly ADEPTUS ASTARTES [MELTA]/[TORRENT] attacks that target %s have +2 S this phase" % Common.group_label(secondary)}
		"overlapping_destruction":
			var diffs6: Array = Common.set_flag_diffs(group(holder), F_OVERLAP, {"target": secondary, "phase_key": _phase_key()})
			diffs6.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs6, "log": "Overlapping Destruction: %s's Heavy Bolters that target %s have [BLAST 1] this phase" % [Common.group_label(holder), Common.group_label(secondary)]}
		"cold_and_calculating":
			var labels := {"lethal": "[LETHAL HITS: MONSTER/VEHICLE]", "sustained": "[SUSTAINED HITS 1: non-MONSTER/VEHICLE]", "both": "[LETHAL HITS: MONSTER/VEHICLE] and [SUSTAINED HITS 1: non-MONSTER/VEHICLE] (tactical doctrine)"}
			return {"diffs": Common.set_flag_diffs(group(uid), F_COLD, {"mode": variant, "phase_key": _phase_key()}),
				"log": "Cold and Calculating: %s's attacks have %s" % [name, str(labels.get(variant, variant))]}
		"purgation_run":
			var r := int(Common.roll_dice(1)[0])
			var diffs7: Array = [_phase_use_diff(holder, slug)]
			diffs7.append_array(Common.set_flag_diffs(group(uid), F_NO_CHARGE, _turn_key()))
			return {"diffs": diffs7, "followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(r), "source": "Purgation Run"},
				"log": "Purgation Run: %s rolls D6 = %d — normal move of up to %d\" (not eligible to declare a charge this turn)" % [name, r, r]}
		"righteous_fury":
			var before := {}
			for eid in Common.engaged_enemy_ids(holder):
				var eh := head_id(str(eid))
				before[eh] = _alive_models(eh)
			var diffs8: Array = Common.set_flag_diffs(group(uid), F_RF, {"phase_key": _phase_key(), "targets": before})
			diffs8.append(_army_battle_diff(player, slug))
			return {"diffs": diffs8, "log": "Righteous Fury: %s's melee attacks have +1 S; when it has fought, Titus heals D3 (2D3 if he destroyed an enemy model)" % name}
		"banner_of_macragge":
			var diffs9: Array = Common.set_flag_diffs(group(uid), F_BANNER, _phase_key())
			diffs9.append(_army_battle_diff(player, slug))
			return {"diffs": diffs9, "log": "Banner of Macragge: %s's melee attacks have +1 A and +1 S" % name}
		"hammer_of_wrath":
			var n := _engaged_model_count(holder, secondary)
			var dice: Array = Common.roll_dice(n) if n > 0 else []
			var mw := 0
			for d in dice:
				if int(d) >= 4:
					mw += 1
			var res := _mortal_wounds(secondary, mw)
			var diffs10: Array = res.diffs
			diffs10.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs10, "log": "Hammer of Wrath: %d engaged model(s) roll %s — %s suffers %d mortal wound(s) (%d model(s) destroyed)" % [n, str(dice), Common.group_label(secondary), mw, int(res.casualties)]}
		"knight_champion_of_macragge":
			return {"diffs": [_army_phase_diff(player, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": KNIGHT_CHAMPION_MOVE_IN, "source": "Knight Champion of Macragge"},
				"log": "Knight Champion of Macragge: %s makes a normal move of up to 6\"" % name}
		"glory_of_ultramar":
			return {"diffs": [_phase_use_diff(holder, slug)],
				"followup": {"type": "surge_move", "unit_id": head_id(uid), "source": "Glory of Ultramar"},
				"log": "Glory of Ultramar: %s makes a surge move of up to D6\"" % name}
		"echo_of_the_ravenspire":
			return {"diffs": [_phase_use_diff(holder, slug)],
				"followup": {"type": "strategic_reserves", "unit_id": head_id(uid), "source": "Echo of the Ravenspire"},
				"log": "Echo of the Ravenspire: %s is placed in strategic reserves" % name}
		"combat_embarkation":
			var diffs11: Array = _embark_diffs(secondary, holder)
			diffs11.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs11, "log": "Combat Embarkation: %s embarks within %s — the charging unit can select new charge targets" % [Common.group_label(secondary), Common.unit_name(holder)]}
	return {"diffs": []}


# ===========================================================================
# DECLARE BATTLE FORMATIONS — Thunderhawk Insertion / Cerebrex Logic Engine
# ===========================================================================

const FORMATION_SLUGS := ["thunderhawk_insertion", "cerebrex_logic_engine"]

## Units `holder_id` may pick for `slug` in the Declare Battle Formations step.
static func formation_candidates(holder_id: String, slug: String) -> Array:
	var out: Array = []
	var h := Common.unit(holder_id)
	if not has(h, slug):
		return out
	var player := int(h.get("owner", 0))
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != player or not Common.is_alive(u) or not Common.has_keyword(u, KW_AA):
			continue
		if slug == "thunderhawk_insertion" and not Common.has_any_keyword(u, ["GRAVIS", "PHOBOS", "TACTICUS"]):
			continue
		if slug == "cerebrex_logic_engine" and not Common.has_keyword(u, "INFANTRY"):
			continue
		out.append(str(uid))
	return out

## {holder_id: [slug, ...]} — the formation choices `player` can still make.
static func formation_choices(player: int) -> Dictionary:
	var out := {}
	if not _edition_11():
		return out
	for slug in FORMATION_SLUGS:
		for hid in _holders(player, str(slug), false):
			var picked: Dictionary = Common.unit(hid).get("flags", {}).get(F_FORMATION_PICK, {})
			if picked.has(str(slug)):
				continue
			if formation_candidates(hid, str(slug)).is_empty():
				continue
			var arr: Array = out.get(hid, [])
			arr.append(str(slug))
			out[hid] = arr
	return out

static func formation_block_reason(player: int, holder_id: String, slug: String, unit_id: String) -> String:
	var h := Common.unit(holder_id)
	if h.is_empty() or int(h.get("owner", 0)) != player:
		return "%s is not your unit" % holder_id
	if not slug in FORMATION_SLUGS or not has(h, slug):
		return "%s does not have %s" % [Common.unit_name(holder_id), display(slug)]
	if (h.get("flags", {}).get(F_FORMATION_PICK, {}) as Dictionary).has(slug):
		return "%s was already used" % display(slug)
	if not unit_id in formation_candidates(holder_id, slug):
		return "%s cannot be selected for %s" % [Common.unit_name(unit_id), display(slug)]
	return ""

## The choice as state diffs (FormationsPhase applies them).
static func formation_diffs(holder_id: String, slug: String, unit_id: String) -> Dictionary:
	var picked: Dictionary = (Common.unit(holder_id).get("flags", {}).get(F_FORMATION_PICK, {}) as Dictionary).duplicate()
	picked[slug] = unit_id
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [holder_id, F_FORMATION_PICK], "value": picked}]
	var flag := F_DEEP_STRIKE if slug == "thunderhawk_insertion" else F_SCOUTS
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [unit_id, flag], "value": true})
	var log := "%s (%s): %s has %s" % [display(slug), Common.unit_name(holder_id), Common.unit_name(unit_id),
		"Deep Strike" if slug == "thunderhawk_insertion" else "Scouts 6\""]
	return {"diffs": diffs, "log": log}

## AI: Thunderhawk Insertion on the costliest eligible non-Deep-Strike unit;
## Cerebrex Logic Engine on the costliest eligible unit without Scouts.
static func ai_formation_pick(holder_id: String, slug: String) -> String:
	var best := ""
	var best_pts := -1
	var gs = Common.game_state()
	for uid in formation_candidates(holder_id, slug):
		if slug == "thunderhawk_insertion" and gs and gs.has_method("unit_has_deep_strike") and bool(gs.unit_has_deep_strike(str(uid))):
			continue
		if slug == "cerebrex_logic_engine" and gs and gs.has_method("unit_has_scout") and bool(gs.unit_has_scout(str(uid))):
			continue
		var pts := int(Common.unit(str(uid)).get("meta", {}).get("points", 0))
		if pts > best_pts:
			best_pts = pts
			best = str(uid)
	return best


# ===========================================================================
# STRATEGIUM COMMAND — the Redeployment step (FactionAbilityManager hook)
# ===========================================================================

## The redeploy entry for FactionAbilityManager.get_redeploy_enhancement:
## "When both players have deployed their armies, you can redeploy up to three
## friendly ADEPTUS ASTARTES units ... set them up in strategic reserves,
## regardless of how many units are already in strategic reserves."
static func redeploy_entry(player: int) -> Dictionary:
	if not _edition_11():
		return {}
	var hs := _holders(player, "strategium_command")
	if hs.is_empty():
		return {}
	return {"name": "Strategium Command", "keywords": [KW_AA], "bearer_id": hs[0], "ignore_reserve_cap": true}


# ===========================================================================
# AI — synchronous scores (AIDecisionMaker.decide_window_stratagem, threshold
# 1.0 for abilities): the window never waits on the AI.
# ===========================================================================

static func ai_score(player: int, sid: String, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var slug := slug_of(sid)
	match slug:
		"strategic_acumen", "master_tactician", "narthecium", "seeker_of_the_unfound", "forgefather", "cold_and_calculating", "hammer_of_wrath":
			return 3.0
		"overlapping_destruction":
			# Worth it when a 5+ model target is in Heavy Bolter range.
			for eid in Common.enemy_heads(player):
				if _alive_models(str(eid)) >= 5 and _dist(target_unit_id, str(eid)) <= 36.0:
					return 2.0
			return 0.0
		"master_of_shadows":
			return 2.0
		"righteous_fury", "banner_of_macragge":
			# Once per battle: spend it when the unit is engaged with a 100+ pt enemy or a CHARACTER.
			for eid in Common.engaged_enemy_ids(target_unit_id):
				var eh := head_id(str(eid))
				if Common.group_points(eh) >= 100 or Common.group_has_keyword(eh, "CHARACTER"):
					return 2.5
			return 0.0
		"echo_of_the_ravenspire":
			# No enemy within 12" and no objective in range, before battle round 5.
			if _round() >= 5 or Common.group_in_range_of_any_objective(target_unit_id):
				return 0.0
			return 1.5 if Common.nearest_enemy_inches(Common.group_union(target_unit_id)) > 12.0 else 0.0
		"combat_embarkation":
			return 2.5
		"purgation_run", "knight_champion_of_macragge", "glory_of_ultramar":
			return 0.0  # repositioning is a plan-level decision
	return 0.0
