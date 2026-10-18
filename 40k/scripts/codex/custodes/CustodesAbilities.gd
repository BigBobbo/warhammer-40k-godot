extends RefCounted

## CustodesAbilities — Codex: Adeptus Custodes (11e) DATASHEET + WARGEAR
## abilities (WP-C7).
##
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md (§2 code layout, §4
## ownership). Printed text: .llm/codex_11e_wahapedia/custodes/wahapedia/
## Datasheets_abilities.csv. Audit + rulings: custodes_abilities_audit.md and
## RULINGS.md (WP-C7).
##
## Everything is static. Engine files only call into this module through thin
## hooks (one line + a comment):
##   RulesEngine        attack modifiers (merge_attack_mods, folded into the
##                      WP-O6 aggregator every resolver path already reads),
##                      incoming -1 to wound (incoming_wound_penalty), the
##                      per-model Praesidium Shield -1 D (allocated_damage),
##                      attached-unit allocation copies (decorate_alloc_model)
##   EffectPrimitives   target-only defences (Living Fortress -1 AP, Guardian
##                      Eternal -1 D, Moment Shackle 3+ InSv), charge / advance
##                      re-rolls, advance-and-charge (Assault Dropship)
##   StratagemManager   activated abilities ride the stratagem-window framework
##                      (window_offers / "cus11e_ab_*" ids routed to use()),
##                      SWIFT RUIN's Rapid Ingress exemption + -1 CP
##   AIDecisionMaker    ai_score() for those offers (synchronous: a window never
##                      waits on the AI)
##   PhaseManager       on_phase_transition() — flag expiry
##   BasePhase          phase_start_entries() — the "start of any phase" window
##   phases             Leadership (Vexilla), move characteristic (Seeker's
##                      Instincts), charge locks (Mobile Hunter), forced ingress
##                      (Archeotech Teleport-shunter), Sweeping Advance
##                      eligibility, fall-back modes (Corner the Quarry)
##
## Ability names are matched FOLDED (case, apostrophes ’/' and punctuation
## ignored, a trailing "(…)" dropped): the army files drop the "(Aura)" and
## "(Once per battle, per unit)" suffixes the codex prints.
##
## Autoloads are reached late-bound through CustodesCommon (the only file the
## Custodes modules preload).

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")

const PX_PER_INCH := 40.0

# Phase enum mirror (GameState.Phase).
const PH_COMMAND := 6
const PH_MOVEMENT := 7
const PH_SHOOTING := 8
const PH_CHARGE := 9
const PH_FIGHT := 10

const KW_CUSTODES := "ADEPTUS CUSTODES"

## slug -> FOLDED printed name (see fold()).
const NAMES := {
	"captain_general": "captain general",
	"moment_shackle": "moment shackle",
	"supreme_commander": "supreme commander",
	"vengeful_surge": "vengeful surge",
	"praesidium_shield": "praesidium shield",
	"archeotech_teleport_shunter": "archeotech teleport shunter",
	"sweeping_advance": "sweeping advance",
	"living_fortress": "living fortress",
	"vexilla": "vexilla",
	"slayer_of_tyrants": "slayer of tyrants",
	"quicksilver_execution": "quicksilver execution",
	"unyielding_ancient": "unyielding ancient",
	"destructor_optics": "destructor optics",
	"repulsor_suspensor_technology": "repulsor suspensor technology",
	"assault_vehicle": "assault vehicle",
	"guardian_eternal": "guardian eternal",
	"mobile_hunter": "mobile hunter",
	"assault_dropship": "assault dropship",
	"infernus_firebombs": "infernus firebombs",
	"swift_onslaught": "swift onslaught",
	"sword_of_the_throne": "sword of the throne",
	"seekers_instincts": "seekers instincts",
	"corner_the_quarry": "corner the quarry",
	"impenetrable_defence": "impenetrable defence",
	"purity_of_execution": "purity of execution",
	"take_wing": "take wing",
	"neutronium_cascade_mine": "neutronium cascade mine",
	"swift_ruin": "swift ruin",
	"dread_foe": "dread foe",
	"stand_vigil": "stand vigil",
	"sanctified_flames": "sanctified flames",
	"death_blow": "death blow",
	"deft_parry": "deft parry",
	"reap_a_terrible_tally": "reap a terrible tally",
	"advanced_firepower": "advanced firepower",
	"strike_from_the_skies": "strike from the skies",
}

## slug -> printed name (cards, logs, the UnitAbilityManager once-per-battle
## ledger key that GILDED CHAMPION restores).
const DISPLAY := {
	"captain_general": "Captain-General", "moment_shackle": "Moment Shackle",
	"supreme_commander": "SUPREME COMMANDER", "vengeful_surge": "Vengeful Surge",
	"praesidium_shield": "Praesidium Shield", "archeotech_teleport_shunter": "Archeotech Teleport-shunter",
	"sweeping_advance": "Sweeping Advance", "living_fortress": "Living Fortress", "vexilla": "Vexilla",
	"slayer_of_tyrants": "Slayer of Tyrants", "quicksilver_execution": "Quicksilver Execution",
	"unyielding_ancient": "Unyielding Ancient", "destructor_optics": "Destructor Optics",
	"repulsor_suspensor_technology": "Repulsor Suspensor Technology", "assault_vehicle": "Assault Vehicle",
	"guardian_eternal": "Guardian Eternal", "mobile_hunter": "Mobile Hunter",
	"assault_dropship": "Assault Dropship", "infernus_firebombs": "Infernus Firebombs",
	"swift_onslaught": "Swift Onslaught", "sword_of_the_throne": "Sword of the Throne",
	"seekers_instincts": "Seeker's Instincts", "corner_the_quarry": "Corner the Quarry",
	"impenetrable_defence": "Impenetrable Defence", "purity_of_execution": "Purity of Execution",
	"take_wing": "Take Wing", "neutronium_cascade_mine": "Neutronium Cascade Mine",
	"swift_ruin": "Swift Ruin", "dread_foe": "Dread Foe", "stand_vigil": "Stand Vigil",
	"sanctified_flames": "Sanctified Flames", "death_blow": "Death Blow", "deft_parry": "Deft Parry",
	"reap_a_terrible_tally": "Reap a Terrible Tally", "advanced_firepower": "Advanced Firepower",
	"strike_from_the_skies": "Strike from the Skies",
}

# --- flags (cus11e_ab_*; none uses the effect_ prefix ShootingPhase wipes) ---
const F_MOMENT_SHACKLE := "cus11e_ab_moment_shackle"   # "attacks" | "invuln": until the end of the phase
## Moment Shackle's (Once per battle, per army) marker. Kept under the name the
## pre-codex FightPhase flow used: GILDED CHAMPION (CustodesCodexOther,
## FLAG_TRACKED_ONCE_PER_BATTLE) and the WP-C5 scenario helper read it.
const F_MOMENT_SHACKLE_USED := "moment_shackle_used"
const F_MARK := "cus11e_ab_mark"                      # Blade Champion: enemy (Attached-unit head) id
const F_MARK_DONE := "cus11e_ab_mark_round1"          # true once the start-of-battle mark was chosen
const F_DETECTED := "cus11e_ab_detected"              # {player}: +3" detection range until the end of the phase
const F_FIREBOMBED := "cus11e_ab_firebombed"          # {player, armed}: ranged attacks vs it [IGNORES COVER]
const F_MUST_INGRESS := "cus11e_ab_must_ingress"      # {player, round}: must make an ingress move this phase
const F_NO_CHARGE := "cus11e_ab_no_charge"            # true: not eligible to declare a charge (end of turn)
const F_DROPSHIP := "cus11e_ab_dropship"              # true: tactical-disembarked from an Orion this turn
const F_FIGHT_ELIGIBLE := "cus11e_ab_fight_eligible"  # true: eligible to fight at the start of this Fight phase
const F_PHASE_USES := "cus11e_ab_phase_uses"          # {slug: phase_key}: once-per-phase per-unit uses

## Army-level ledger on GameState.state.players[p]: {slug: phase_key}.
const ARMY_USES := "cus11e_ab_army_uses"

const SID_PREFIX := "cus11e_ab_"

const NCM_RANGE_IN := 3.0
const PURITY_RANGE_IN := 18.0
const FIREBOMBS_RANGE_IN := 24.0
const CAPTAIN_GENERAL_RANGE_IN := 6.0
const DETECTED_BONUS_IN := 3.0
const SEEKERS_MOVE_BONUS_IN := 2.0
const FIREBOMBS_MW_CAP := 6


# ===========================================================================
# Names / membership
# ===========================================================================

## Lower-case, straight apostrophes removed, a trailing "(…)" dropped, every
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

## True when the unit's datasheet lists the ability of `slug`.
static func has(u: Dictionary, slug: String) -> bool:
	var want := str(NAMES.get(slug, ""))
	if want == "" or u.is_empty():
		return false
	for ab in u.get("meta", {}).get("abilities", []):
		if fold(_ability_name(ab)) == want:
			return true
	return false

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

## The Praesidium Shield wargear prints two different rules: on the
## Shield-Captain (a CHARACTER) "-1 D for attacks allocated to this model", on
## the Sentinel Guard Sodality "-1 to wound for S > T attacks".
static func _shield_is_model_rule(u: Dictionary) -> bool:
	return Common.has_keyword(u, "CHARACTER")

static func _edition_11() -> bool:
	return int(GameConstants.edition) >= 11

static func _phase() -> int:
	return Common.current_phase()

static func _round() -> int:
	return Common.battle_round()

static func _phase_key() -> String:
	return "%d:%d:%d" % [_round(), Common.active_player(), _phase()]

static func _turn_key() -> String:
	return "%d:%d" % [_round(), Common.active_player()]

static func _event_log(player: int, text: String) -> void:
	Common.game_log(player, text)

static func _uam():
	return Common.autoload("UnitAbilityManager")


# ===========================================================================
# Usage limits
# ===========================================================================

## (Once per battle, per unit) — UnitAbilityManager's ledger (persisted with the
## save; GILDED CHAMPION restores it and blocks the same phase). Keyed by the
## holder (the CHARACTER's own id for a leader's ability).
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

## (Once per phase, per army).
static func army_used_this_phase(player: int, slug: String) -> bool:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	return typeof(uses) == TYPE_DICTIONARY and str(uses.get(slug, "")) == _phase_key()

static func _army_use_diff(player: int, slug: String) -> Dictionary:
	var uses = Common.state().get("players", {}).get(str(player), {}).get(ARMY_USES, {})
	var nd: Dictionary = uses.duplicate() if typeof(uses) == TYPE_DICTIONARY else {}
	nd[slug] = _phase_key()
	return {"op": "set", "path": "players.%s.%s" % [str(player), ARMY_USES], "value": nd}

## Moment Shackle is (Once per battle, per army).
static func moment_shackle_spent(player: int) -> bool:
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) == player and bool(u.get("flags", {}).get(F_MOMENT_SHACKLE_USED, false)):
			return true
	return false


# ===========================================================================
# Geometry / target helpers
# ===========================================================================

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

static func _lone_operative(unit_id: String) -> bool:
	var re = Common.rules()
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if re and re.has_method("has_lone_operative") and bool(re.has_lone_operative(u)):
			return true
	return false

## 19.02: the T an attack against the (Attached) unit uses — the highest T of
## its bodyguard models, or of its leader models when only they are left.
static func unit_toughness(unit_id: String) -> int:
	var head := head_id(unit_id)
	var best := 0
	var hu := Common.unit(head)
	if Common.is_alive(hu):
		best = int(hu.get("meta", {}).get("stats", {}).get("toughness", 4))
		return best
	for gid in group(head):
		var u := Common.unit(str(gid))
		if Common.is_alive(u):
			best = maxi(best, int(u.get("meta", {}).get("stats", {}).get("toughness", 4)))
	return best if best > 0 else int(hu.get("meta", {}).get("stats", {}).get("toughness", 4))

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


# ===========================================================================
# PASSIVE COMBAT MODIFIERS
# ===========================================================================
# attack_mods(): every ATTACKER-side Custodes datasheet ability for one attack
# batch (attacker, target, weapon), plus the target-side Deft Parry (-1 to hit
# for melee attacks). Same keys as OrkAbilities11e._empty_mods(); RulesEngine
# merges the result into the WP-O6 aggregator (merge_attack_mods), so every
# resolver path (interactive ranged hit / wound / save prep, auto-resolve,
# overwatch, melee hit / wound / save prep) reads it.

static func _empty_mods() -> Dictionary:
	return {"hit_plus": false, "hit_minus": false, "hit_reroll": "", "ignore_hit_penalties": false,
		"wound_plus": false, "wound_reroll": "", "ap": 0, "damage": 0, "strength": 0, "attacks": 0,
		"ws": 0, "lethal": false, "sustained": 0, "ignores_cover": false, "target_cover": false,
		"hazardous": false, "psychic": false, "sources": []}

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _reroll_max(a: String, b: String) -> String:
	var rank := {"": 0, "ones": 1, "failed": 2}
	return a if int(rank.get(a, 0)) >= int(rank.get(b, 0)) else b

static func _weapon_name(weapon_profile: Dictionary) -> String:
	return str(weapon_profile.get("name", "")).to_lower().replace("’", "'")

## The Codex: Adeptus Custodes contribution, merged INTO `m` (the WP-O6
## aggregator result) — the one-line RulesEngine hook (ork11e_ab_mods).
static func merge_attack_mods(m: Dictionary, actor_unit: Dictionary, target_unit: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, bearer_ids: Array = []) -> void:
	if not _edition_11():
		return
	var c := attack_mods(actor_unit, target_unit, weapon_profile, is_melee, board, bearer_ids)
	if c.sources.is_empty():
		return
	m["hit_plus"] = bool(m.get("hit_plus", false)) or c.hit_plus
	m["hit_minus"] = bool(m.get("hit_minus", false)) or c.hit_minus
	m["hit_reroll"] = _reroll_max(str(m.get("hit_reroll", "")), c.hit_reroll)
	m["wound_plus"] = bool(m.get("wound_plus", false)) or c.wound_plus
	m["wound_reroll"] = _reroll_max(str(m.get("wound_reroll", "")), c.wound_reroll)
	m["ap"] = int(m.get("ap", 0)) + c.ap
	m["damage"] = int(m.get("damage", 0)) + c.damage
	m["strength"] = int(m.get("strength", 0)) + c.strength
	m["attacks"] = int(m.get("attacks", 0)) + c.attacks
	m["lethal"] = bool(m.get("lethal", false)) or c.lethal
	m["sustained"] = maxi(int(m.get("sustained", 0)), c.sustained)
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
	var ranged := not is_melee
	var owner := int(actor_unit.get("owner", 0))
	var own_turn := owner == Common.active_player()
	var phase := _phase()
	var charged := false
	for gid in group(actor_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
			charged = true
	if bool(actor_unit.get("flags", {}).get("charged_this_turn", false)):
		charged = true
	var wname := _weapon_name(weapon_profile)

	# --- target-side (any attacker): Deft Parry, Infernus Firebombs ----------
	if target_id != "":
		if is_melee and group_has(target_id, "deft_parry"):
			m.hit_minus = true
			_src(m, "Deft Parry", "hit", "minus_one", "melee attacks that target the Vigilators")
		var fb = _gflag(target_id, F_FIREBOMBED)
		if ranged and typeof(fb) == TYPE_DICTIONARY and int(fb.get("player", 0)) == owner:
			m.ignores_cover = true
			_src(m, "Infernus Firebombs", "other", "ignores_cover", "ranged attacks that target that unit have [IGNORES COVER]")
	if not Common.group_has_keyword(actor_id, KW_CUSTODES):
		return m

	var target_mv := target_id != "" and _is_mv(target_id)
	var target_ok := target_id != ""

	# --- "this model" abilities -------------------------------------------------
	# Moment Shackle: the Watcher's Axe has +3 A (Trajann's own attacks).
	if is_melee and str(actor_unit.get("flags", {}).get(F_MOMENT_SHACKLE, "")) == "attacks" and wname.contains("watcher's axe"):
		m.attacks += 3
		_src(m, "Moment Shackle", "other", "attacks", "Watcher's Axe +3 A")
	# Sword of the Throne: this model's attacks vs its mark have +1 to wound.
	if target_ok and has(actor_unit, "sword_of_the_throne"):
		var mark := str(actor_unit.get("flags", {}).get(F_MARK, ""))
		if mark != "" and head_id(mark) == head_id(target_id):
			m.wound_plus = true
			_src(m, "Sword of the Throne", "wound", "plus_one", "target is the Blade Champion's mark")

	# --- "this unit" abilities (whole Attached unit) ----------------------------
	if is_melee and target_ok and group_has(actor_id, "slayer_of_tyrants") and unit_toughness(target_id) > unit_toughness(actor_id):
		m.wound_plus = true
		_src(m, "Slayer of Tyrants", "wound", "plus_one", "target has a higher T")
	if is_melee and charged and group_has(actor_id, "quicksilver_execution"):
		m.sustained = maxi(m.sustained, 1)
		_src(m, "Quicksilver Execution", "other", "sustained_hits", "[SUSTAINED HITS 1] after a charge move")
	if ranged and target_ok and not target_mv and group_has(actor_id, "destructor_optics"):
		m.ap += 1
		_src(m, "Destructor Optics", "other", "ap", "+1 AP vs a non-MONSTER/VEHICLE unit")
	if target_ok and not target_mv and group_has(actor_id, "impenetrable_defence") \
			and (Common.group_in_range_of_any_objective(actor_id) or Common.group_in_range_of_any_objective(target_id)):
		m.sustained = maxi(m.sustained, 1)
		_src(m, "Impenetrable Defence", "other", "sustained_hits", "[SUSTAINED HITS 1: non-MONSTER/VEHICLE] (objective range)")
	if is_melee and target_ok and not target_mv and group_has(actor_id, "dread_foe"):
		m.ap += 1
		_src(m, "Dread Foe", "other", "ap", "+1 AP vs a non-MONSTER/VEHICLE unit")
	if target_ok and not target_mv and group_has(actor_id, "stand_vigil") \
			and (Common.group_in_range_of_any_objective(actor_id) or Common.group_in_range_of_any_objective(target_id)):
		m.lethal = true
		_src(m, "Stand Vigil", "other", "lethal_hits", "[LETHAL HITS: non-MONSTER/VEHICLE] (objective range)")
	if is_melee and charged and group_has(actor_id, "death_blow"):
		m.ap += 1
		_src(m, "Death Blow", "other", "ap", "+1 AP after a charge move")
	if target_ok and Common.group_has_keyword(target_id, "INFANTRY") and group_has(actor_id, "reap_a_terrible_tally"):
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
		_src(m, "Reap a Terrible Tally", "hit", "reroll_ones", "target is INFANTRY")
		_src(m, "Reap a Terrible Tally", "wound", "reroll_ones", "target is INFANTRY")
	if ranged and own_turn and phase == PH_SHOOTING and group_has(actor_id, "strike_from_the_skies") and made_ingress_this_turn(actor_id):
		m.hit_reroll = "failed"
		_src(m, "Strike from the Skies", "hit", "reroll_failed", "made an ingress move this turn")

	# --- aura -------------------------------------------------------------------
	var cg := captain_general_source(actor_id)
	if cg != "":
		m.hit_reroll = _reroll_max(m.hit_reroll, "ones")
		m.wound_reroll = _reroll_max(m.wound_reroll, "ones")
		_src(m, "Captain-General", "hit", "reroll_ones", "within 6\" of %s" % Common.unit_name(cg))
		_src(m, "Captain-General", "wound", "reroll_ones", "within 6\" of %s" % Common.unit_name(cg))
	return m

## Captain-General (Aura): the Trajann unit whose model is within 6" of
## `actor_id`'s (Attached) unit — "" when none. ADEPTUS CUSTODES units
## excluding MONSTER/VEHICLE; a model is within range of its own aura (22.01).
static func captain_general_source(actor_id: String) -> String:
	if actor_id == "" or _is_mv(actor_id) or not Common.group_has_keyword(actor_id, KW_CUSTODES):
		return ""
	var owner := int(Common.unit(actor_id).get("owner", 0))
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if int(u.get("owner", 0)) != owner or not has(u, "captain_general") or not Common.is_on_battlefield(u):
			continue
		if head_id(str(uid)) == head_id(actor_id):
			return str(uid)
		if Common.unit_distance_inches(u, Common.group_union(actor_id)) <= CAPTAIN_GENERAL_RANGE_IN + 0.001:
			return str(uid)
	return ""

## "made an ingress move this turn" (the reserves arrival stamp).
static func made_ingress_this_turn(unit_id: String) -> bool:
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if bool(u.get("flags", {}).get("arrived_from_reserves", false)):
			return true
		if int(u.get("owner", 0)) == Common.active_player() and int(u.get("arrived_from_reserves_turn", -1)) == _round():
			return true
	return false


# ===========================================================================
# DEFENSIVE (target-only) — EffectPrimitives / RulesEngine hooks
# ===========================================================================

## {ap_worsen, damage_minus, invuln, sources} for attacks that target the unit.
## is_melee false = ranged (Guardian Eternal).
static func defence_mods(target_unit: Dictionary, is_melee: bool) -> Dictionary:
	var d := {"ap_worsen": 0, "damage_minus": 0, "invuln": 0, "sources": []}
	var tid := _uid(target_unit)
	if tid == "" or target_unit.is_empty() or not _edition_11():
		return d
	if group_has(tid, "living_fortress"):
		d.ap_worsen = 1
		d.sources.append("Living Fortress")
	if not is_melee and group_has(tid, "guardian_eternal"):
		d.damage_minus = 1
		d.sources.append("Guardian Eternal")
	# Moment Shackle 3+ InSv — "This model": only Trajann's own unit dict (the
	# attached-unit allocation copy gets it per model, decorate_alloc_model).
	if str(target_unit.get("flags", {}).get(F_MOMENT_SHACKLE, "")) == "invuln":
		d.invuln = 3
		d.sources.append("Moment Shackle")
	return d

## Phase proxy for the EffectPrimitives getters (no attack context): the Fight
## phase resolves melee attacks, every other phase ranged ones.
static func defence_mods_now(target_unit: Dictionary) -> Dictionary:
	return defence_mods(target_unit, _phase() == PH_FIGHT)

## Unyielding Ancient (Contemptor-Achillus / -Galatus), Praesidium Shield
## (Sentinel Guard Sodality): attacks that target this unit with S > its T
## have -1 to wound.
static func incoming_wound_penalty(target_unit: Dictionary, strength: int, toughness: int) -> bool:
	if strength <= toughness or not _edition_11():
		return false
	var tid := _uid(target_unit)
	if tid == "":
		return false
	if group_has(tid, "unyielding_ancient"):
		return true
	for gid in group(tid):
		var u := Common.unit(str(gid))
		if has(u, "praesidium_shield") and not _shield_is_model_rule(u):
			return true
	return false

## Name of the S > T wound penalty source (ledger / logs), "" when none.
static func incoming_wound_penalty_source(target_unit: Dictionary, strength: int, toughness: int) -> String:
	if not incoming_wound_penalty(target_unit, strength, toughness):
		return ""
	return "Unyielding Ancient" if group_has(_uid(target_unit), "unyielding_ancient") else "Praesidium Shield"

## Praesidium Shield (Shield-Captain): "Attacks allocated to this model have
## -1 D" (minimum 1). `model` is the model the attack was allocated to (an
## attached-unit allocation copy carries cus11e_src_unit_id); `unit_minus` is
## the unit-level -1 D already applied (not cumulative — the engine's -1 D
## sources take the best, WP-O6 ruling). Returns {damage, note}.
static func allocated_damage(damage: int, target_unit: Dictionary, model: Dictionary, unit_minus: int = 0) -> Dictionary:
	var out := {"damage": damage, "note": ""}
	if not _edition_11() or damage <= 1 or model.is_empty() or unit_minus > 0:
		return out
	# The model's own unit: an attached CHARACTER's allocation copy is tagged
	# with it; any other model belongs to the unit being allocated against (a
	# bodyguard model never bears the Shield-Captain's shield).
	var src_id := str(model.get("cus11e_src_unit_id", _uid(target_unit)))
	var src := Common.unit(src_id)
	if src.is_empty():
		src = target_unit
	if not has(src, "praesidium_shield") or not _shield_is_model_rule(src):
		return out
	out.damage = maxi(1, damage - 1)
	out.note = "Praesidium Shield: -1 Damage (%d -> %d) — attack allocated to %s" % [damage, int(out.damage), Common.unit_name(src_id)]
	print("CustodesAbilities: %s" % out.note)
	return out

## Attached-unit allocation copy of a CHARACTER model (RulesEngine
## _build_attached_allocation_unit_11e): tag its source unit (Praesidium
## Shield finds the bearer) and give it Moment Shackle's 3+ InSv ("This model").
static func decorate_alloc_model(cm: Dictionary, char_unit: Dictionary) -> void:
	cm["cus11e_src_unit_id"] = _uid(char_unit)
	if _edition_11() and str(char_unit.get("flags", {}).get(F_MOMENT_SHACKLE, "")) == "invuln":
		var cur := int(cm.get("invuln", 0))
		if cur == 0 or cur > 3:
			cm["invuln"] = 3


# ===========================================================================
# Movement / charge / Leadership / misc passive hooks
# ===========================================================================

## Vexilla: "This unit can ignore modifiers to this unit's Ld" — the engine
## ignores the harmful Ld modifiers (the Salvus "can ignore" convention).
static func ignores_ld_modifiers(unit_id: String) -> bool:
	return _edition_11() and group_has(unit_id, "vexilla")

## Seeker's Instincts: +2" M (Knight-Centura — "This unit": its Attached unit).
static func move_modifier(unit: Dictionary) -> float:
	if not _edition_11() or unit.is_empty():
		return 0.0
	return SEEKERS_MOVE_BONUS_IN if group_has(_uid(unit), "seekers_instincts") else 0.0

## Swift Onslaught (Blade Champion) / Seeker's Instincts (Knight-Centura):
## re-roll charge rolls / advance rolls. Returns the source name or "".
static func charge_reroll_source(unit: Dictionary) -> String:
	if not _edition_11() or unit.is_empty():
		return ""
	var uid := _uid(unit)
	if group_has(uid, "swift_onslaught"):
		return "Swift Onslaught"
	if group_has(uid, "seekers_instincts"):
		return "Seeker's Instincts"
	return ""

static func advance_reroll_source(unit: Dictionary) -> String:
	return charge_reroll_source(unit)

## Assault Dropship: a unit that made a tactical disembark move from an Orion
## this turn can still declare a charge after its advance move.
static func advance_allows_charge(unit: Dictionary) -> bool:
	return _edition_11() and bool(unit.get("flags", {}).get(F_DROPSHIP, false))

## Mobile Hunter: "not eligible to declare a charge until the end of the turn"
## (a hard lock — advance-and-charge effects do not lift it).
static func blocks_charge(unit: Dictionary) -> bool:
	return bool(unit.get("flags", {}).get(F_NO_CHARGE, false))

## Purity of Execution: a detected unit has +3" detection range.
static func detection_range_bonus(unit: Dictionary) -> float:
	var d = unit.get("flags", {}).get(F_DETECTED, null)
	if typeof(d) == TYPE_DICTIONARY:
		return DETECTED_BONUS_IN
	var head := head_id(_uid(unit))
	if head != _uid(unit) and typeof(Common.unit(head).get("flags", {}).get(F_DETECTED, null)) == TYPE_DICTIONARY:
		return DETECTED_BONUS_IN
	return 0.0

## Corner the Quarry: an enemy (non-MONSTER/VEHICLE) unit engaged with a
## Knight-Centura unit must use the desperate escape mode when it falls back.
## Returns the Knight-Centura unit id, or "".
static func corner_the_quarry_source(unit_id: String, board: Dictionary = {}) -> String:
	if not _edition_11():
		return ""
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	var u: Dictionary = units.get(unit_id, {})
	if u.is_empty() or _is_mv(unit_id):
		return ""
	var owner := int(u.get("owner", 0))
	for oid in units:
		var o: Dictionary = units[oid]
		if int(o.get("owner", 0)) == owner or not has(o, "corner_the_quarry") or not Common.is_on_battlefield(o):
			continue
		if Common.group_engaged_with(str(oid), unit_id):
			return str(oid)
	return ""

## -1 to those hazard rolls while that enemy unit is battle-shocked.
static func corner_the_quarry_hazard_modifier(unit_id: String, board: Dictionary = {}) -> int:
	if corner_the_quarry_source(unit_id, board) == "":
		return 0
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	return -1 if bool(units.get(unit_id, {}).get("flags", {}).get("battle_shocked", false)) else 0

## Archeotech Teleport-shunter: units of `player` that must still make their
## ingress move this phase (MovementPhase refuses END_MOVEMENT while any is
## left in reserves).
static func pending_forced_ingress(player: int) -> Array:
	var out: Array = []
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		var f = u.get("flags", {}).get(F_MUST_INGRESS, null)
		if typeof(f) != TYPE_DICTIONARY or int(f.get("player", 0)) != player:
			continue
		if int(u.get("status", 0)) == 7 and Common.is_alive(u) and head_id(str(uid)) == str(uid):  # 7 = IN_RESERVES
			out.append(str(uid))
	return out

## Swift Ruin (Venatari with Verutum Lances, Once per phase, per army): the
## Rapid Ingress stratagem can target the unit regardless of other uses this
## phase, costs 1 CP less, and does not block other uses. True when it applies
## to this use.
static func swift_ruin_applies(player: int, strat: Dictionary, target_unit_id: String) -> bool:
	if not _edition_11() or target_unit_id == "":
		return false
	if str(strat.get("name", "")).to_upper() != "RAPID INGRESS":
		return false
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player or not group_has(target_unit_id, "swift_ruin"):
		return false
	return not army_used_this_phase(player, "swift_ruin")

static func swift_ruin_record(player: int) -> void:
	var d := _army_use_diff(player, "swift_ruin")
	Common.apply_diffs([d])
	Common.log_info("CustodesAbilities: Swift Ruin — Rapid Ingress -1 CP, not counted against the once-per-phase limit (P%d)" % player)

## Sweeping Advance: "if this unit was eligible to fight this phase" — it was
## engaged or had charged at the start of the Fight phase (F_FIGHT_ELIGIBLE),
## it fought, or it is engaged now. Returns the (Attached-unit head) ids of
## units with the ability that qualify, given FightPhase.units_that_fought.
static func sweeping_advance_candidates(units_that_fought: Array) -> Array:
	var out: Array = []
	if not _edition_11():
		return units_that_fought.filter(func(x): return group_has(str(x), "sweeping_advance"))
	for uid in Common.state().get("units", {}):
		var u := Common.unit(str(uid))
		if not has(u, "sweeping_advance") or not Common.is_on_battlefield(u):
			continue
		var head := head_id(str(uid))
		if head in out:
			continue
		var eligible := head in units_that_fought or str(uid) in units_that_fought or _engaged(head)
		if not eligible:
			for gid in group(head):
				if bool(Common.unit(str(gid)).get("flags", {}).get(F_FIGHT_ELIGIBLE, false)):
					eligible = true
		if eligible:
			out.append(head)
	return out

## SUPREME COMMANDER (Trajann Valoris): "If this model is in your army, it
## must be your WARLORD" — FormationsPhase matches the ability folded.
static func is_supreme_commander(u: Dictionary) -> bool:
	return has(u, "supreme_commander")


# ===========================================================================
# EXPIRY — PhaseManager.transition_to_phase (thin hook), before the new phase
# is entered; runs on every peer, mutating in place like the stratagem expiry.
# ===========================================================================

const PHASE_SCOPED := [F_MOMENT_SHACKLE, F_DETECTED, F_MUST_INGRESS]
const END_OF_TURN := [F_NO_CHARGE, F_DROPSHIP]

static func on_phase_transition(old_phase: int, new_phase: int) -> void:
	if not _edition_11():
		return
	var units: Dictionary = Common.state().get("units", {})
	var active := Common.active_player()
	var cleared: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		var flags: Dictionary = u.get("flags", {})
		if flags.is_empty():
			continue
		for f in PHASE_SCOPED:
			if flags.has(f):
				flags.erase(f)
				cleared.append("%s.%s" % [uid, f])
		if old_phase == PH_FIGHT and flags.has(F_FIGHT_ELIGIBLE):
			flags.erase(F_FIGHT_ELIGIBLE)
		if new_phase == PH_COMMAND:
			for f in END_OF_TURN:
				if flags.has(f):
					flags.erase(f)
					cleared.append("%s.%s" % [uid, f])
			# Infernus Firebombs: "until the end of your next turn".
			var fb = flags.get(F_FIREBOMBED, null)
			if typeof(fb) == TYPE_DICTIONARY:
				if int(fb.get("player", 0)) == active:
					fb["armed"] = true   # the user's next turn has begun
				elif bool(fb.get("armed", false)):
					flags.erase(F_FIREBOMBED)
					cleared.append("%s.%s" % [uid, F_FIREBOMBED])
	# Sweeping Advance: who is eligible to fight at the start of the Fight phase.
	if new_phase == PH_FIGHT:
		for uid in units:
			var u: Dictionary = units[uid]
			if not has(u, "sweeping_advance") or not Common.is_on_battlefield(u):
				continue
			var head := head_id(str(uid))
			var eligible := _engaged(head)
			for gid in group(head):
				if bool(Common.unit(str(gid)).get("flags", {}).get("charged_this_turn", false)):
					eligible = true
			if eligible:
				var hu: Dictionary = units.get(head, {})
				if not hu.has("flags"):
					hu["flags"] = {}
				hu["flags"][F_FIGHT_ELIGIBLE] = true
	if not cleared.is_empty():
		Common.log_info("CustodesAbilities: phase %d -> %d expired %s" % [old_phase, new_phase, str(cleared)])


# ===========================================================================
# ACTIVATED ABILITIES — offered through the stratagem-window framework
# ===========================================================================
# An activated ability is an offer in the window dialog the codex stratagems
# use (StratagemDialog Card_<sid>/Buttons/Use_<sid>_<uid>), with stratagem_id
# "cus11e_ab_<slug>", cp_cost 0 and is_ability: true. Picking it sends the
# ordinary USE_WINDOW_STRATAGEM; StratagemManager.use_stratagem routes the id
# here (use()). The AI answers synchronously (ai_score).

## window id -> slugs offered there.
const WINDOW_ABILITIES := {
	"phase_start": ["sword_of_the_throne", "moment_shackle", "neutronium_cascade_mine"],
	"enemy_has_shot": ["vengeful_surge", "repulsor_suspensor_technology"],
	"unit_has_shot": ["sanctified_flames", "mobile_hunter"],
	"unit_selected_to_shoot": ["purity_of_execution"],
	"movement_phase_start": ["archeotech_teleport_shunter"],
	"fight_phase_end": ["take_wing", "infernus_firebombs"],
}

## Short effect text on the card (the printed rule, condensed).
const EFFECT_TEXT := {
	"sword_of_the_throne": "Select one enemy unit to be this model's mark: this model's attacks that target its mark have +1 to wound rolls.",
	"moment_shackle": "Once per battle, per army: until the end of the phase, this model's Watcher's Axe has +3 A, or this model has a 3+ invulnerable save.",
	"neutronium_cascade_mine": "Once per battle: select one enemy unit within 3\" and roll one D6 — on a 2+ it suffers D3 mortal wounds (2D3 if it is a VEHICLE/MONSTER).",
	"vengeful_surge": "Once per battle: a model in this unit lost a wound to those attacks — this unit can make a surge move of up to D6+2\".",
	"repulsor_suspensor_technology": "Once per phase: this unit lost a wound to those attacks — it can make a normal move of up to D6\".",
	"sanctified_flames": "Select one enemy unit hit by those attacks: it makes a battle-shock roll (-1 if it is a PSYKER unit).",
	"mobile_hunter": "This unit can make a normal move of up to D6\"; it is not eligible to declare a charge until the end of the turn.",
	"purity_of_execution": "Select one visible enemy unit within 18\": it is detected (+3\" detection range) until the end of the phase.",
	"archeotech_teleport_shunter": "Once per battle: place this unit in strategic reserves — it must make an ingress move this phase.",
	"take_wing": "This unit is unengaged: place it in strategic reserves.",
	"infernus_firebombs": "Select one visible enemy unit (excluding Lone Operative and AIRCRAFT) within 24\": ranged attacks that target it have [IGNORES COVER] until the end of your next turn; roll one D6 per model — each 6 is 1 mortal wound (max 6).",
}

## Windows that can host several ability uses: after one, the same window is
## offered again with what is still on offer (BasePhase generic follow-up
## "ork11e_reoffer" — WP-O6's re-offer, faction-neutral in behaviour).
const REOFFER_WINDOWS := ["phase_start", "fight_phase_end", "movement_phase_start"]
const REOFFER_IF_ABILITY_LEFT := ["enemy_has_shot", "unit_has_shot", "unit_selected_to_shoot"]

static func handles_id(sid: String) -> bool:
	return str(sid).begins_with(SID_PREFIX)

static func slug_of(sid: String) -> String:
	return str(sid).substr(SID_PREFIX.length())

static func sid_of(slug: String) -> String:
	return SID_PREFIX + slug

## Offers for `player` in `window_id` (StratagemManager.get_all_window_offers).
static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if not _edition_11():
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
		Common.log_info("CustodesAbilities: window %s P%d — ability offers %s" % [window_id, player, str(offers.map(func(o): return o.name))])
	return offers

## "Start of any phase" window entries for BasePhase.enter_phase (event
## windows: active player first, then the opponent; only players with an
## offer). Not in networked games (a window opened outside an action result
## cannot be mirrored — the WP-C5 phase_end ruling).
static func phase_start_entries(phase: int) -> Array:
	var out: Array = []
	if not _edition_11() or not phase in [PH_COMMAND, PH_MOVEMENT, PH_SHOOTING, PH_CHARGE, PH_FIGHT]:
		return out
	var nm = Common.autoload("NetworkManager")
	if nm and nm.has_method("is_networked") and bool(nm.is_networked()):
		return out
	var active := Common.active_player()
	var ctx := {"phase": {PH_COMMAND: "command", PH_MOVEMENT: "movement", PH_SHOOTING: "shooting", PH_CHARGE: "charge", PH_FIGHT: "fight"}[phase]}
	for p in [active, 2 if active == 1 else 1]:
		var c := ctx.duplicate()
		c["window_id"] = "phase_start"
		if not window_offers(p, "phase_start", c).is_empty():
			out.append({"player": p, "window_id": "phase_start", "ctx": ctx.duplicate()})
	return out

static func _entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	return Common.target_entry(unit_id, extra)

## Friendly components of `player` (any status unless on_board) carrying `slug`.
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

## Enemy (Attached-unit heads) of `player` on the battlefield.
static func _enemy_heads(player: int) -> Array:
	return Common.enemy_heads(player)

## The mark a Blade Champion needs now: at the start of the first battle round
## (until one is chosen), and after its mark was destroyed.
static func needs_mark(holder_id: String) -> bool:
	var u := Common.unit(holder_id)
	var flags: Dictionary = u.get("flags", {})
	var mark := str(flags.get(F_MARK, ""))
	if mark != "":
		return not Common.is_alive(Common.unit(mark))
	return _round() == 1 and not bool(flags.get(F_MARK_DONE, false))

static func _targets(slug: String, player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var phase := _phase()
	var active := Common.active_player()
	var own_turn := active == player
	match slug:
		"sword_of_the_throne":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug, false):
				if not needs_mark(hid):
					continue
				var enemies: Array = []
				for uid in Common.state().get("units", {}):
					var eu := Common.unit(str(uid))
					if int(eu.get("owner", 0)) == player or int(eu.get("owner", 0)) == 0 or not Common.is_alive(eu):
						continue
					if head_id(str(uid)) != str(uid):
						continue
					enemies.append(str(uid))
				if enemies.is_empty():
					continue
				enemies = _sorted_by_distance(hid, enemies) if Common.is_on_battlefield(Common.unit(hid)) else enemies
				out.append(_entry(hid, {"label": Common.unit_name(hid),
					"secondary": _unit_options(enemies, "Sword of the Throne: select one enemy unit to be %s's mark" % Common.unit_name(hid))}))
		"moment_shackle":
			if window_id != "phase_start" or moment_shackle_spent(player):
				return out
			if not (phase == PH_FIGHT or (phase == PH_SHOOTING and not own_turn)):
				return out
			for hid in _holders(player, slug):
				out.append(_entry(hid, {"label": Common.unit_name(hid), "require_variant": true,
					"ai_variant": "attacks" if own_turn else "invuln",
					"variants": [
						{"id": "attacks", "label": "Watcher's Axe +3 A", "cp_cost": 0},
						{"id": "invuln", "label": "3+ invulnerable save", "cp_cost": 0}]}))
		"neutronium_cascade_mine":
			if window_id != "phase_start":
				return out
			for hid in _holders(player, slug):
				if used_in_battle(hid, slug):
					continue
				var near: Array = []
				for eid in _enemy_heads(player):
					if _dist(hid, str(eid)) <= NCM_RANGE_IN + 0.001:
						near.append(str(eid))
				if near.is_empty():
					continue
				out.append(_entry(hid, {"secondary": _unit_options(_sorted_by_distance(hid, near),
					"Neutronium Cascade Mine: select one enemy unit within 3\" of %s" % Common.group_label(hid))}))
		"vengeful_surge", "repulsor_suspensor_technology":
			if window_id != "enemy_has_shot" or own_turn or phase != PH_SHOOTING:
				return out
			var wounded: Array = ctx.get("wounded_unit_ids", [])
			for hid in _holders(player, slug):
				var hit_me := false
				var whose: Array = group(hid) if slug == "vengeful_surge" else [hid]
				for gid in whose:
					if str(gid) in wounded:
						hit_me = true
				if not hit_me or _engaged(hid):
					continue
				if slug == "vengeful_surge":
					if used_in_battle(hid, slug) or Common.is_battle_shocked(Common.unit(head_id(hid))):
						continue
				elif used_this_phase(hid, slug):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"sanctified_flames":
			if window_id != "unit_has_shot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter := str(ctx.get("unit_id", ""))
			var hid := group_holder(shooter, slug) if shooter != "" else ""
			# One use per shot (a unit shoots once a phase) — the window
			# re-offers after any use, never this one twice.
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var hit: Array = []
			for tid in ctx.get("hit_unit_ids", []):
				var h := head_id(str(tid))
				var hu := Common.unit(h)
				if int(hu.get("owner", 0)) == player or not Common.is_on_battlefield(hu) or h in hit:
					continue
				hit.append(h)
			if hit.is_empty():
				return out
			hit.sort_custom(func(a, b): return _best_ld(str(a)) > _best_ld(str(b)))
			out.append(_entry(head_id(shooter), {"holder": hid, "secondary": _unit_options(hit,
				"Sanctified Flames: select one enemy unit hit by %s's attacks — it makes a battle-shock roll" % Common.group_label(shooter))}))
		"mobile_hunter":
			if window_id != "unit_has_shot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter := str(ctx.get("unit_id", ""))
			var hid := group_holder(shooter, slug) if shooter != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or _engaged(hid) or not Common.is_on_battlefield(Common.unit(hid)):
				return out
			out.append(_entry(head_id(shooter), {"holder": hid}))
		"purity_of_execution":
			if window_id != "unit_selected_to_shoot" or not own_turn or phase != PH_SHOOTING:
				return out
			var shooter := str(ctx.get("unit_id", ""))
			var hid := group_holder(shooter, slug) if shooter != "" else ""
			if hid == "" or int(Common.unit(hid).get("owner", 0)) != player or used_this_phase(hid, slug):
				return out
			var cands: Array = []
			for eid in _enemy_heads(player):
				if _dist(hid, str(eid)) <= PURITY_RANGE_IN + 0.001 and _visible(hid, str(eid)):
					cands.append(str(eid))
			if cands.is_empty():
				return out
			out.append(_entry(head_id(shooter), {"holder": hid, "secondary": _unit_options(_sorted_by_distance(hid, cands),
				"Purity of Execution: select one visible enemy unit within 18\" — it is detected (+3\" detection range)")}))
		"archeotech_teleport_shunter":
			if window_id != "movement_phase_start" or not own_turn or phase != PH_MOVEMENT or _round() < 2:
				return out
			for hid in _holders(player, slug):
				var head := head_id(hid)
				if used_in_battle(hid, slug) or _engaged(head):
					continue
				var moved := false
				for gid in group(head):
					var gf: Dictionary = Common.unit(str(gid)).get("flags", {})
					if bool(gf.get("moved", false)) or bool(gf.get("movement_active", false)):
						moved = true
				if moved:
					continue
				out.append(_entry(head, {"holder": hid}))
		"take_wing":
			if window_id != "fight_phase_end" or own_turn or phase != PH_FIGHT:
				return out
			for hid in _holders(player, slug):
				if _engaged(hid):
					continue
				out.append(_entry(head_id(hid), {"holder": hid}))
		"infernus_firebombs":
			if window_id != "fight_phase_end" or own_turn or phase != PH_FIGHT:
				return out
			for hid in _holders(player, slug):
				# One trigger per unit at the end of that phase (the window
				# re-offers after any use — never the same unit's bombs twice).
				if used_this_phase(hid, slug):
					continue
				var cands: Array = []
				for eid in _enemy_heads(player):
					if _lone_operative(str(eid)) or Common.group_has_keyword(str(eid), "AIRCRAFT"):
						continue
					if _dist(hid, str(eid)) <= FIREBOMBS_RANGE_IN + 0.001 and _visible(hid, str(eid)):
						cands.append(str(eid))
				if cands.is_empty():
					continue
				cands.sort_custom(func(a, b): return _alive_models(str(a)) > _alive_models(str(b)))
				out.append(_entry(hid, {"secondary": _unit_options(cands,
					"Infernus Firebombs: select one visible enemy unit (excluding Lone Operative and AIRCRAFT) within 24\"")}))
	return out

## 01.06: a leadership roll succeeds on >= ANY of the unit's Ld characteristics
## — the best (lowest) Ld in the Attached unit.
static func _best_ld(unit_id: String) -> int:
	var best := 99
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if Common.is_alive(u):
			best = mini(best, int(u.get("meta", {}).get("stats", {}).get("leadership", 7)))
	return best if best < 99 else 7

## USE_WINDOW_STRATAGEM on an ability (routed by StratagemManager.use_stratagem).
## Returns the use_stratagem result shape: {success, diffs (already applied),
## stratagem_name, followup?, error?}.
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
		Common.log_info("CustodesAbilities: %s" % log_text)
		_event_log(player, log_text)
	var out := {"success": true, "diffs": diffs, "stratagem_name": display(slug), "cp_cost": 0}
	var followup: Dictionary = res.get("followup", {})
	if followup.is_empty() and (window_id in REOFFER_WINDOWS or window_id in REOFFER_IF_ABILITY_LEFT):
		var wctx: Dictionary = context.duplicate(true)
		for k in ["secondary_id", "variant_id", "variant_label"]:
			wctx.erase(k)
		# REOFFER_WINDOWS: re-offered while anything (a stratagem too) is left;
		# the held-action windows only while another ability is.
		var left: Array = window_offers(player, window_id, wctx)
		var sm = Common.stratagem_manager()
		if window_id in REOFFER_WINDOWS and left.is_empty() and sm and sm.has_method("get_all_window_offers"):
			left = sm.get_all_window_offers(player, window_id, wctx)
		if not left.is_empty():
			followup = {"type": "ork11e_reoffer", "player": player, "window_id": window_id, "ctx": wctx}
	if not followup.is_empty():
		out["followup"] = followup
	return out

static func _roll(n: int, sides: int = 6) -> Array:
	return Common.roll_dice(n, sides)

## Mortal wounds (06.02): the bodyguard first, spilling to the Attached unit's
## characters (the OrkDetachments11e / OrkCodexOther convention). FNP via
## RulesEngine.apply_mortal_wounds.
static func _mortal_wounds(unit_id: String, mw: int) -> Dictionary:
	var out := {"diffs": [], "casualties": 0, "wounds_applied": 0}
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
		out.wounds_applied += mini(applied, pool)
		remaining = maxi(0, applied - pool)
	return out

## 20.02: the unit (every component of the Attached unit) leaves the
## battlefield into strategic reserves (the WP-O6 Aerial Manoover diffs).
static func strategic_reserves_diffs(unit_id: String) -> Array:
	var diffs: Array = []
	for gid in group(unit_id):
		var u := Common.unit(str(gid))
		if u.is_empty():
			continue
		diffs.append({"op": "set", "path": "units.%s.status" % gid, "value": 7})  # UnitStatus.IN_RESERVES
		diffs.append({"op": "set", "path": "units.%s.reserve_type" % gid, "value": "strategic_reserves"})
		diffs.append({"op": "set", "path": "units.%s.flags.repositioned_to_reserves" % gid, "value": true})
		var models: Array = u.get("models", [])
		for i in range(models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	return diffs

## 01.07 battle-shock roll: 2D6 + mod vs the best Ld; failure = battle-shocked.
static func battle_shock_roll(unit_id: String, mod: int, source: String) -> Dictionary:
	var head := head_id(unit_id)
	var ld := _best_ld(head)
	var dice := _roll(2)
	var total := int(dice[0]) + int(dice[1]) + mod
	var passed := total >= ld
	var diffs: Array = []
	if not passed:
		for gid in group(head):
			diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % gid, "value": true})
	var mod_txt := (" %+d" % mod) if mod != 0 else ""
	var text := "%s: %s makes a battle-shock roll — 2D6 %d + %d%s = %d vs Ld %d+ — %s" % [
		source, Common.group_label(head), int(dice[0]), int(dice[1]), mod_txt, total, ld,
		"passed" if passed else "FAILED: battle-shocked"]
	return {"diffs": diffs, "passed": passed, "dice": dice, "total": total, "ld": ld, "text": text}

static func _apply(slug: String, player: int, uid: String, holder: String, secondary: String, variant: String, _ctx: Dictionary) -> Dictionary:
	var name := Common.group_label(uid)
	match slug:
		"sword_of_the_throne":
			var diffs: Array = Common.set_flag_diffs([holder], F_MARK, secondary)
			diffs.append_array(Common.set_flag_diffs([holder], F_MARK_DONE, true))
			return {"diffs": diffs, "log": "Sword of the Throne: %s is %s's mark (+1 to wound for its attacks against it)" % [Common.group_label(secondary), Common.unit_name(holder)]}
		"moment_shackle":
			var diffs: Array = Common.set_flag_diffs([holder], F_MOMENT_SHACKLE, variant)
			diffs.append_array(Common.set_flag_diffs([holder], F_MOMENT_SHACKLE_USED, true))
			var what := "the Watcher's Axe has +3 A" if variant == "attacks" else "%s has a 3+ invulnerable save" % Common.unit_name(holder)
			return {"diffs": diffs, "log": "Moment Shackle (once per battle): until the end of the phase, %s" % what}
		"neutronium_cascade_mine":
			_mark_battle_use(holder, slug)
			var roll := int(_roll(1)[0])
			if roll < 2:
				return {"diffs": [], "log": "Neutronium Cascade Mine: %s rolls %d — no effect on %s" % [name, roll, Common.group_label(secondary)]}
			var mv := _is_mv(secondary)
			var dice: Array = _roll(2 if mv else 1, 3)
			var mw := 0
			for d in dice:
				mw += int(d)
			var res := _mortal_wounds(secondary, mw)
			return {"diffs": res.diffs, "log": "Neutronium Cascade Mine: %s rolls %d — %s suffers %s = %d mortal wound(s) (%d model(s) destroyed)" % [
				name, roll, Common.group_label(secondary), "2D3 %s" % str(dice) if mv else "D3 %s" % str(dice), mw, int(res.casualties)]}
		"vengeful_surge":
			_mark_battle_use(holder, slug)
			return {"diffs": [], "followup": {"type": "surge_move", "unit_id": head_id(uid), "source": "Vengeful Surge", "roll_bonus": 2},
				"log": "Vengeful Surge (once per battle): %s makes a surge move of up to D6+2\"" % name}
		"repulsor_suspensor_technology":
			var r := int(_roll(1)[0])
			return {"diffs": [_phase_use_diff(holder, slug)],
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(r), "source": "Repulsor Suspensor Technology"},
				"log": "Repulsor Suspensor Technology: %s rolls D6 = %d — normal move of up to %d\"" % [name, r, r]}
		"sanctified_flames":
			var mod := -1 if Common.group_has_keyword(secondary, "PSYKER") else 0
			var bs := battle_shock_roll(secondary, mod, "Sanctified Flames")
			var sf_diffs: Array = bs.diffs
			sf_diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": sf_diffs, "log": str(bs.text)}
		"mobile_hunter":
			var r := int(_roll(1)[0])
			return {"diffs": Common.set_flag_diffs(group(uid), F_NO_CHARGE, true),
				"followup": {"type": "reactive_normal_move", "unit_id": head_id(uid), "max_inches": float(r), "source": "Mobile Hunter"},
				"log": "Mobile Hunter: %s rolls D6 = %d — normal move of up to %d\"; not eligible to declare a charge this turn" % [name, r, r]}
		"purity_of_execution":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_DETECTED, {"player": player})
			diffs.append(_phase_use_diff(holder, slug))
			return {"diffs": diffs, "log": "Purity of Execution: %s is detected (+3\" detection range) until the end of the phase" % Common.group_label(secondary)}
		"archeotech_teleport_shunter":
			_mark_battle_use(holder, slug)
			var diffs: Array = strategic_reserves_diffs(uid)
			diffs.append_array(Common.set_flag_diffs(group(uid), F_MUST_INGRESS, {"player": player, "round": _round()}))
			return {"diffs": diffs, "log": "Archeotech Teleport-shunter (once per battle): %s is placed in strategic reserves and must make an ingress move this phase" % name}
		"take_wing":
			return {"diffs": strategic_reserves_diffs(uid), "log": "Take Wing: %s is placed in strategic reserves" % name}
		"infernus_firebombs":
			var diffs: Array = Common.set_flag_diffs(group(secondary), F_FIREBOMBED, {"player": player, "armed": false})
			diffs.append(_phase_use_diff(holder, slug))
			var n := _alive_models(secondary)
			var rolls := _roll(n)
			var mw := 0
			for r in rolls:
				if int(r) == 6:
					mw += 1
			mw = mini(mw, FIREBOMBS_MW_CAP)
			var res := _mortal_wounds(secondary, mw)
			diffs.append_array(res.diffs)
			return {"diffs": diffs, "log": "Infernus Firebombs: %s — ranged attacks that target it have [IGNORES COVER] until the end of your next turn; %d D6 %s: %d mortal wound(s) (%d model(s) destroyed)" % [
				Common.group_label(secondary), n, str(rolls), mw, int(res.casualties)]}
	return {"diffs": []}

## Disembark hook (MovementPhase CONFIRM_DISEMBARK, after the 18.04 mode is
## known): Assault Dropship — a tactical disembark from an Orion.
static func on_disembark(unit_id: String, transport_id: String, mode: String) -> Array:
	if not _edition_11() or mode != "tactical" or transport_id == "":
		return []
	if not has_id(transport_id, "assault_dropship") or not Common.group_has_keyword(unit_id, KW_CUSTODES):
		return []
	Common.log_info("CustodesAbilities: Assault Dropship — %s tactical-disembarked from %s: its advance move does not prevent a charge" % [unit_id, transport_id])
	return Common.set_flag_diffs(group(unit_id), F_DROPSHIP, true)


# ===========================================================================
# AI — synchronous scores (AIDecisionMaker.decide_window_stratagem, threshold
# 1.0 for abilities): the window never waits on the AI.
# ===========================================================================

static func ai_score(player: int, sid: String, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var slug := slug_of(sid)
	match slug:
		"sword_of_the_throne", "neutronium_cascade_mine", "infernus_firebombs", "sanctified_flames":
			return 3.0
		"moment_shackle":
			# Only when an enemy is close enough to fight (or be fought) this phase.
			if _phase() == PH_FIGHT:
				return 2.5 if Common.nearest_enemy_inches(Common.group_union(target_unit_id)) <= 6.0 else 0.0
			return 0.0
		"vengeful_surge":
			return 2.0  # a melee unit moving into engagement
		"purity_of_execution":
			return 0.0  # helps only against hidden targets — not modelled by the AI
		"repulsor_suspensor_technology", "mobile_hunter", "archeotech_teleport_shunter", "take_wing":
			return 0.0  # repositioning is a plan-level decision
	return 0.0
