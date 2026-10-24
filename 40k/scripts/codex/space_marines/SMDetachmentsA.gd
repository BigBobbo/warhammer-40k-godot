extends RefCounted

## SMDetachmentsA — Codex: Space Marines (11e), generic DETACHMENT RULES +
## ENHANCEMENTS, group A (WP-M2a): Gladius Task Force, Ironstorm Spearhead,
## Stormlance Task Force, Gauntlet Task Force, Phobos Shadow Force, Tacticus
## Attack Force, Phobos Shock Force.
##
## Source: .llm/codex_11e_wahapedia/space-marines/SPACE_MARINES_GENERIC.md.
## Plan: PLAN_SPACE_MARINES.md (SM-D1..D4); contract: IMPLEMENTATION.md;
## rulings: RULINGS.md § WP-M2a. Every rule gates on SWCommon.is_sm_army
## (11e, any Space Marine army) AND the player having taken the detachment
## (an 11e army may take several — ArmyDetachments11e). Enhancements are
## active only while their detachment is taken (runtime + list build).
##
##  GLADIUS TASK FORCE — CODEX DISCIPLINE: one combat doctrine one additional
##   time per battle (lives with the army rule: SWArmyRules11e.doctrine_limit).
##   Standard of the Emperor Ascendant  +1 OC, Ld improved by 1, FNP 5+ (list
##       build); ANCIENT EXHORTATION (once per battle, per army): when the
##       bearer's unit is selected to fight, its melee attacks +1 A this phase
##       (unit_selected_to_fight rule card).
##   Laurels of Triumph   the bearer's melee attacks +1 S and AP (+2 with the
##       assault doctrine active for its unit).
##   Adept of the Codex   the tactical doctrine is active for the bearer's unit
##       in addition to any other (SWCommon per-unit extra key, refreshed at
##       every phase transition).
##   Artificer Armour     2+ Sv, FNP 5+ (list build).
##  IRONSTORM SPEARHEAD — IRONSTORM AUTO-TARGETERS: AA VEHICLE (not WALKER)
##   ranged attacks re-roll one hit roll and one wound roll (RulesEngine
##   single-die re-roll hooks, once per unit per phase each).
##   Redoubtable Machine Spirit  5+ InSv (list build); heals 1 wound at the end
##       of your Command phase.
##   Gunnery Honours             the unit's ranged attacks have [HEAVY].
##  STORMLANCE TASK FORCE — LIGHTNING-FAST STRIKE: AA MOUNTED / SPEEDER +2" M.
##   Supercharged Engines   the unit can re-roll advance rolls (free re-roll).
##   Auspex Triangulation Shrines  start of your Shooting phase: one visible
##       enemy within 12" is spotted (+3" detection range) until end of turn.
##  GAUNTLET TASK FORCE — COMBINED DEPLOYMENT: when an AA TRANSPORT has shot
##   (your Shooting phase), one enemy unit hit is assailed until the end of
##   the turn: attacks from AA units that disembarked this turn have
##   [SUSTAINED HITS 1] against it (unit_has_shot rule card).
##   Linebreaker Onslaught  disembarked this turn: re-roll charge rolls; no
##       snap shooting at this unit.
##   Damocles-class Uplink  your Movement phase, bearer embarked: one AA
##       INFANTRY unit within 6" of the TRANSPORT gets a chosen doctrine
##       (phase_start rule card).
##  PHOBOS SHADOW FORCE — SHADOW MASTERS: when a PHOBOS / SCOUT SQUAD unit has
##   shot: those attacks do not prevent it from being hidden, OR a normal move
##   of up to D6" (no charge this turn) (unit_has_shot rule card).
##   Venator Omni-auspex    attacks vs a hidden unit re-roll wound rolls of 1
##       (1-2 with the assault doctrine).
##   Execute and Redeploy   after the unit has shot (your Shooting phase,
##       unengaged): a normal move of up to 6" (no charge this turn).
##  TACTICUS ATTACK FORCE — WRATH OF THE CHAPTER: TACTICUS units re-roll
##   advance rolls (free re-roll).
##   Martial Paragon        the unit's attacks re-roll one hit roll and one
##       wound roll.
##   Spearpoint War Leader  the unit has Scouts 6".
##  PHOBOS SHOCK FORCE — VANGUARD AMBUSHERS: end of your Movement phase, a
##   hidden PHOBOS unit's attacks re-roll wound rolls of 1 until end of turn.
##   Seal of Shrouding      no snap shooting at this unit.
##   Venator Omni-auspex    (as above).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")

const GLADIUS := "gladius task force"
const IRONSTORM := "ironstorm spearhead"
const STORMLANCE := "stormlance task force"
const GAUNTLET := "gauntlet task force"
const SHADOW := "phobos shadow force"
const TACTICUS := "tacticus attack force"
const SHOCK := "phobos shock force"

const DETACHMENTS := [GLADIUS, IRONSTORM, STORMLANCE, GAUNTLET, SHADOW, TACTICUS, SHOCK]
const RULE_NAMES := {
	GLADIUS: "Codex Discipline",
	IRONSTORM: "Ironstorm Auto-targeters",
	STORMLANCE: "Lightning-fast Strike",
	GAUNTLET: "Combined Deployment",
	SHADOW: "Shadow Masters",
	TACTICUS: "Wrath of the Chapter",
	SHOCK: "Vanguard Ambushers",
}

# --- enhancements ----------------------------------------------------------
const STANDARD := "standard of the emperor ascendant"
const LAURELS := "laurels of triumph"
const ADEPT := "adept of the codex"
const ARTIFICER := "artificer armour"
const REDOUBTABLE := "redoubtable machine spirit"
const GUNNERY := "gunnery honours"
const SUPERCHARGED := "supercharged engines"
const AUSPEX := "auspex triangulation shrines"
const LINEBREAKER := "linebreaker onslaught"
const DAMOCLES := "damocles-class uplink"
const VENATOR := "venator omni-auspex"
const EXECUTE := "execute and redeploy"
const PARAGON := "martial paragon"
const SPEARPOINT := "spearpoint war leader"
const SEAL := "seal of shrouding"

const ENHANCEMENTS := {
	STANDARD: {"name": "Standard of the Emperor Ascendant", "dets": [GLADIUS]},
	LAURELS: {"name": "Laurels of Triumph", "dets": [GLADIUS]},
	ADEPT: {"name": "Adept of the Codex", "dets": [GLADIUS]},
	ARTIFICER: {"name": "Artificer Armour", "dets": [GLADIUS]},
	REDOUBTABLE: {"name": "Redoubtable Machine Spirit", "dets": [IRONSTORM]},
	GUNNERY: {"name": "Gunnery Honours", "dets": [IRONSTORM]},
	SUPERCHARGED: {"name": "Supercharged Engines", "dets": [STORMLANCE]},
	AUSPEX: {"name": "Auspex Triangulation Shrines", "dets": [STORMLANCE]},
	LINEBREAKER: {"name": "Linebreaker Onslaught", "dets": [GAUNTLET]},
	DAMOCLES: {"name": "Damocles-class Uplink", "dets": [GAUNTLET]},
	VENATOR: {"name": "Venator Omni-auspex", "dets": [SHADOW, SHOCK]},
	EXECUTE: {"name": "Execute and Redeploy", "dets": [SHADOW]},
	PARAGON: {"name": "Martial Paragon", "dets": [TACTICUS]},
	SPEARPOINT: {"name": "Spearpoint War Leader", "dets": [TACTICUS]},
	SEAL: {"name": "Seal of Shrouding", "dets": [SHOCK]},
}

const LIGHTNING_MOVE_IN := 2.0
const AUSPEX_RANGE_IN := 12.0
const AUSPEX_DETECTION_IN := 3.0
const DAMOCLES_RANGE_IN := 6.0
const EXECUTE_MOVE_IN := 6.0
const SPEARPOINT_SCOUTS_IN := 6.0

# --- rule-card ids (StratagemManager window framework, free, no CP) --------
const RULE_PREFIX := "sm11e_rule_"
const RULE_EXHORTATION := "sm11e_rule_ancient_exhortation"
const RULE_COMBINED := "sm11e_rule_combined_deployment"
const RULE_SHADOW := "sm11e_rule_shadow_masters"
const RULE_EXECUTE := "sm11e_rule_execute_and_redeploy"
const RULE_AUSPEX := "sm11e_rule_auspex_triangulation"
const RULE_DAMOCLES := "sm11e_rule_damocles_uplink"

# --- flags (no effect_ prefix: they must outlive the Shooting-phase wipe) --
## Ancient Exhortation: phase stamp on every component of the bearer's unit.
const F_EXHORTATION := "sm11e_exhortation"
## Combined Deployment: the enemy unit is assailed — turn stamp "<round>:<active>".
const F_ASSAILED := "sm11e_assailed"
## Auspex Triangulation Shrines: the enemy unit is spotted — turn stamp.
const F_SPOTTED := "sm11e_spotted"
## Vanguard Ambushers: re-roll wound rolls of 1 — turn stamp.
const F_AMBUSH := "sm11e_vanguard_ambush"
## Adept of the Codex wrote this unit's SWCommon per-unit extra doctrine.
const F_ADEPT := "sm11e_adept_codex"
const F_DOCTRINE_EXTRA := "sw11e_doctrine_extra"      # SWCommon per-unit additional doctrines
const F_DOCTRINE := "sw11e_doctrine"                  # SWCommon per-unit doctrine
const F_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"
## Damocles-class Uplink wrote this unit's per-unit doctrine (= the doctrine).
const F_DAMOCLES := "sm11e_damocles_doctrine"
## Once-per-phase rule cards: phase stamp on the bearer / transport.
const F_AUSPEX_PHASE := "sm11e_auspex_phase"
const F_DAMOCLES_PHASE := "sm11e_damocles_phase"
const F_EXECUTE_PHASE := "sm11e_execute_phase"
## Redoubtable Machine Spirit healed this Command phase (phase stamp).
const F_REDOUBTABLE_PHASE := "sm11e_redoubtable_phase"
## state.factions[p]: Ancient Exhortation used (once per battle, per army).
const FK_EXHORTATION_USED := "sm11e_exhortation_used"
## List-build markers (idempotent): sm11e_listbuild_<slug>.
const F_LISTBUILD_PREFIX := "sm11e_listbuild_"

## Single-die re-rolls (Ironstorm Auto-targeters / Martial Paragon): once per
## unit per phase for each roll type — {head|phase stamp|kind|source: true}.
static var _reroll_one_used: Dictionary = {}

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func _log(msg: String) -> void:
	Common.log_info("[SMDetachmentsA] " + msg)

static func detachments_of(player: int) -> Array:
	if not enabled() or player <= 0:
		return []
	return ArmyDets.player_detachment_keys(player, Common.state())

## `player` is a Space Marine army (11e) that took `det`.
static func has_det(player: int, det: String) -> bool:
	return enabled() and det in detachments_of(player) and Common.is_sm_army(player)

static func unit_has_det(u: Dictionary, det: String) -> bool:
	return not u.is_empty() and has_det(int(u.get("owner", 0)), det)

static func _faction(player: int) -> Dictionary:
	var f = Common.state().get("factions", {}).get(str(player), {})
	return f if f is Dictionary else {}

static func turn_stamp() -> String:
	return "%d:%d" % [Common.battle_round(), Common.active_player()]

static func phase_stamp() -> String:
	return "%d:%d:%d" % [Common.battle_round(), Common.active_player(), Common.current_phase()]

## Once per shot (integration fix): COMBINED DEPLOYMENT / SHADOW MASTERS trigger
## "when a unit has shot" — one use per shooting unit per phase. Without this the
## card was re-offered on every window reopen and the AI used it forever.
const F_SHOT_RULE_USED := "sm11e_shot_rule_used"  # {sid: phase_stamp} on the shooter's head unit

static func _shot_rule_used(shooter: String, sid: String) -> bool:
	var f = Common.unit(Common.head_id(shooter)).get("flags", {}).get(F_SHOT_RULE_USED, {})
	return f is Dictionary and str(f.get(sid, "")) == phase_stamp()

static func _shot_rule_used_diffs(shooter: String, sid: String) -> Array:
	var head := Common.head_id(shooter)
	var f = Common.unit(head).get("flags", {}).get(F_SHOT_RULE_USED, {})
	var d: Dictionary = (f as Dictionary).duplicate() if f is Dictionary else {}
	d[sid] = phase_stamp()
	return [{"op": "set", "path": "units.%s.flags.%s" % [head, F_SHOT_RULE_USED], "value": d}]

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

static func group_flag(u: Dictionary, flag: String):
	for gu in group_units(u):
		var f = gu.get("flags", {}).get(flag, null)
		if f != null:
			return f
	return null

## The doctrine is active for the unit or any component of its Attached unit.
static func group_doctrine(u: Dictionary, doctrine: String) -> bool:
	for gu in group_units(u):
		if Common.doctrine_active(gu, doctrine):
			return true
	return false

## "disembarked this turn" — the 11e flags.disembarked_this_turn marker
## (DisembarkMove) or the TransportManager disembarked_this_phase marker.
static func group_disembarked_this_turn(u: Dictionary) -> bool:
	for gu in group_units(u):
		if bool(gu.get("flags", {}).get("disembarked_this_turn", false)) or bool(gu.get("disembarked_this_phase", false)):
			return true
	return false

## 13.09: a unit is hidden while every one of its alive, placed models is
## hidden (the Ork Kunnin' Infiltrator ruling).
static func unit_is_hidden(u: Dictionary) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("is_model_hidden") or u.is_empty():
		return false
	var any := false
	for gu in group_units(u):
		for m in gu.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			any = true
			if not tm.is_model_hidden(m, gu):
				return false
	return any

static func _visible(from_id: String, to_id: String) -> bool:
	var re = Common.rules()
	if re == null or not re.has_method("_has_los_to_target_unit"):
		return true
	return bool(re._has_los_to_target_unit(Common.head_id(from_id), Common.head_id(to_id), Common.state()))

# ===========================================================================
# Enhancements — ownership
# ===========================================================================

static func enh_key(name: String) -> String:
	var k := name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()
	for suffix in [" (one per army)", " (upgrade)"]:
		if k.ends_with(suffix):
			k = k.substr(0, k.length() - suffix.length()).strip_edges()
	return k

static func display_name(key: String) -> String:
	return str(ENHANCEMENTS.get(key, {}).get("name", key))

static func is_sm_a_enhancement(name: String) -> bool:
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

## The owner (a Space Marine army) took one of the enhancement's detachments.
static func _owner_has_det(u: Dictionary, key: String) -> bool:
	var owner := int(u.get("owner", 0))
	for d in ENHANCEMENTS[key].dets:
		if has_det(owner, str(d)):
			return true
	return false

## THIS unit dict carries the enhancement and its detachment is active.
static func has_enh(u: Dictionary, key: String) -> bool:
	return enabled() and not u.is_empty() and key in unit_enhancements(u) and _owner_has_det(u, key)

## The component of the (Attached) unit that bears `key` ({} = none).
static func group_bearer(u: Dictionary, key: String) -> Dictionary:
	if not enabled() or u.is_empty():
		return {}
	for gu in group_units(u):
		if has_enh(gu, key):
			return gu
	return {}

static func bearers(player: int, key: String) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and has_enh(u, key):
			out.append(u)
	return out

# ===========================================================================
# List build (ArmyListManager hook) — Standard of the Emperor Ascendant,
# Artificer Armour, Redoubtable Machine Spirit. Idempotent.
# ===========================================================================

static func apply_list_build(unit_id: String, unit: Dictionary, detachment_names: Array = []) -> Array:
	var lines: Array = []
	if not enabled() or not unit.has("meta"):
		return lines
	var dets: Array = []
	for n in detachment_names:
		dets.append(ArmyDets.det_key(str(n)))
	if not unit.has("flags") or not (unit.flags is Dictionary):
		unit["flags"] = {}
	var meta: Dictionary = unit.meta
	if not meta.has("stats") or not (meta.stats is Dictionary):
		meta["stats"] = {}
	var st: Dictionary = meta.stats
	for key in unit_enhancements(unit):
		if not key in [STANDARD, ARTIFICER, REDOUBTABLE]:
			continue
		var det_ok := dets.is_empty()
		for d in ENHANCEMENTS[key].dets:
			if str(d) in dets:
				det_ok = true
		if not det_ok:
			lines.append("%s on %s: not applied — the army did not take %s" % [display_name(key), unit_id, str(ENHANCEMENTS[key].dets)])
			continue
		var done: String = F_LISTBUILD_PREFIX + str(key).replace(" ", "_").replace("'", "").replace("-", "_")
		if bool(unit.flags.get(done, false)):
			continue
		match key:
			STANDARD:
				st["objective_control"] = int(st.get("objective_control", 0)) + 1
				# "+1 Ld": an improvement — Ld 6+ becomes 5+ (ruling).
				st["leadership"] = maxi(2, int(st.get("leadership", 7)) - 1)
				if int(st.get("fnp", 0)) <= 0 or int(st.get("fnp", 0)) > 5:
					st["fnp"] = 5
				lines.append("Standard of the Emperor Ascendant on %s: OC %d, Ld %d+, Feel No Pain 5+" % [unit_id, int(st.objective_control), int(st.leadership)])
			ARTIFICER:
				if int(st.get("save", 7)) > 2:
					st["save"] = 2
				if int(st.get("fnp", 0)) <= 0 or int(st.get("fnp", 0)) > 5:
					st["fnp"] = 5
				lines.append("Artificer Armour on %s: Sv 2+, Feel No Pain 5+" % unit_id)
			REDOUBTABLE:
				if int(st.get("invuln", 0)) <= 0 or int(st.get("invuln", 0)) > 5:
					st["invuln"] = 5
				for m in unit.get("models", []):
					if int(m.get("invuln", 0)) <= 0 or int(m.get("invuln", 0)) > 5:
						m["invuln"] = 5
				lines.append("Redoubtable Machine Spirit on %s: 5+ invulnerable save" % unit_id)
		unit.flags[done] = true
	for l in lines:
		_log(str(l))
	return lines

# ===========================================================================
# Attack modifiers (RulesEngine.ork11e_ab_mods aggregator — every attack path)
# ===========================================================================

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func _wound_reroll_up(m: Dictionary, want: String) -> void:
	var rank := {"": 0, "ones": 1, "ones_twos": 2, "failed": 3}
	if int(rank.get(want, 0)) > int(rank.get(str(m.get("wound_reroll", "")), 0)):
		m["wound_reroll"] = want

static func _weapon_has_heavy(wp: Dictionary) -> bool:
	for kw in wp.get("keywords", []):
		if str(kw).to_upper() == "HEAVY":
			return true
	for a in wp.get("abilities", []):
		if a is Dictionary and str(a.get("id", "")).to_lower() == "heavy":
			return true
		if a is String and str(a).to_lower() == "heavy":
			return true
	return str(wp.get("special_rules", "")).to_lower().contains("heavy")

static func merge_attack_mods(m: Dictionary, actor: Dictionary, target: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, _bearer_ids: Array = []) -> void:
	if not enabled() or actor.is_empty():
		return
	var owner := int(actor.get("owner", 0))
	if owner <= 0 or not Common.is_sm_army(owner):
		return
	# Laurels of Triumph: "This model's melee attacks have +1 S and AP. Or: if
	# the assault doctrine is active for this unit, +2 S and AP." The bearer's
	# own attacks (an attached CHARACTER resolves its attacks as its own unit).
	if is_melee and has_enh(actor, LAURELS):
		var n := 2 if group_doctrine(actor, "assault") else 1
		m["strength"] = int(m.get("strength", 0)) + n
		m["ap"] = int(m.get("ap", 0)) + n
		_src(m, "Laurels of Triumph", "other", "strength_ap", "+%d S and AP%s" % [n, " (assault doctrine)" if n == 2 else ""])
	# Ancient Exhortation: this unit's melee attacks +1 A until the end of the phase.
	if is_melee and str(group_flag(actor, F_EXHORTATION)) == phase_stamp():
		m["attacks"] = int(m.get("attacks", 0)) + 1
		_src(m, "Ancient Exhortation (Standard of the Emperor Ascendant)", "other", "attacks", "+1 A (melee)")
	# Gunnery Honours: this unit's ranged attacks have [HEAVY] (+1 to hit while it qualifies).
	if not is_melee and not group_bearer(actor, GUNNERY).is_empty() and not _weapon_has_heavy(weapon_profile):
		var ms = load("res://scripts/rules/ModifierStack.gd")
		var b: Dictionary = board if not board.is_empty() else Common.state()
		if ms != null and bool(ms.heavy_applies_11e(actor, b)):
			m["hit_plus"] = true
			_src(m, "Gunnery Honours", "hit", "plus_one", "[HEAVY] — unengaged, no model moved more than 3\"")
	if target.is_empty():
		return
	# Combined Deployment: AA units that disembarked this turn vs an assailed unit: [SUSTAINED HITS 1].
	if str(group_flag(target, F_ASSAILED)) == turn_stamp() and group_kw(actor, "ADEPTUS ASTARTES") \
			and group_disembarked_this_turn(actor):
		m["sustained"] = maxi(int(m.get("sustained", 0)), 1)
		_src(m, "Combined Deployment (Gauntlet Task Force)", "other", "sustained_hits_1", "disembarked this turn vs an assailed unit")
	# Vanguard Ambushers: re-roll wound rolls of 1 until the end of the turn.
	if str(group_flag(actor, F_AMBUSH)) == turn_stamp():
		_wound_reroll_up(m, "ones")
		_src(m, "Vanguard Ambushers (Phobos Shock Force)", "wound", "reroll_ones", "hidden at the end of the Movement phase")
	# Venator Omni-auspex: attacks vs a hidden unit re-roll wound rolls of 1 (1-2 with the assault doctrine).
	if not group_bearer(actor, VENATOR).is_empty() and unit_is_hidden(target):
		var assault := group_doctrine(actor, "assault")
		_wound_reroll_up(m, "ones_twos" if assault else "ones")
		_src(m, "Venator Omni-auspex", "wound", "reroll_ones_twos" if assault else "reroll_ones", "target is hidden%s" % (" (assault doctrine: 1-2)" if assault else ""))

# ===========================================================================
# Single-die re-rolls: Ironstorm Auto-targeters, Martial Paragon
# (RulesEngine.sm11e_reroll_one_hit / _wound — every resolver path)
# ===========================================================================

## The rule that lets this attack batch re-roll one `kind` ("hit" / "wound")
## roll and has not been spent this phase ("" = none).
static func reroll_one_source(actor: Dictionary, kind: String, is_melee: bool) -> String:
	if not enabled() or actor.is_empty():
		return ""
	var owner := int(actor.get("owner", 0))
	if owner <= 0 or not Common.is_sm_army(owner):
		return ""
	var head := Common.head_id(str(actor.get("id", "")))
	# Ironstorm Auto-targeters: AA VEHICLE units (excluding WALKER) — ranged attacks.
	if not is_melee and has_det(owner, IRONSTORM) and Common.has_keyword(actor, "ADEPTUS ASTARTES") \
			and Common.has_keyword(actor, "VEHICLE") and not Common.has_keyword(actor, "WALKER"):
		if not _reroll_one_used.has(_rr_key(head, kind, "ironstorm")):
			return "Ironstorm Auto-targeters"
	# Martial Paragon: "This unit's attacks can re-roll one hit roll / one wound roll."
	if not group_bearer(actor, PARAGON).is_empty():
		if not _reroll_one_used.has(_rr_key(head, kind, "paragon")):
			return "Martial Paragon"
	return ""

static func _rr_key(head: String, kind: String, src: String) -> String:
	return "%s|%s|%s|%s" % [head, phase_stamp(), kind, src]

static func reroll_one_consume(actor: Dictionary, kind: String, source: String) -> void:
	var head := Common.head_id(str(actor.get("id", "")))
	_reroll_one_used[_rr_key(head, kind, "ironstorm" if source.begins_with("Ironstorm") else "paragon")] = true
	_log("%s — %s re-rolls one %s roll (once this phase)" % [source, head, kind])

static func reset_reroll_ledger() -> void:
	_reroll_one_used.clear()

# ===========================================================================
# Movement / charge / scouts / detection / snap shooting hooks
# ===========================================================================

## Lightning-fast Strike: friendly AA MOUNTED / SPEEDER units have +2" M.
static func move_bonus_inches(u: Dictionary) -> float:
	if u.is_empty() or not unit_has_det(u, STORMLANCE):
		return 0.0
	if not group_kw(u, "ADEPTUS ASTARTES"):
		return 0.0
	if group_kw(u, "MOUNTED") or group_kw(u, "SPEEDER"):
		return LIGHTNING_MOVE_IN
	return 0.0

## "Can re-roll advance rolls": Wrath of the Chapter (TACTICUS units),
## Supercharged Engines (the bearer unit). The MovementPhase free re-roll.
static func free_advance_reroll_source(u: Dictionary) -> String:
	if u.is_empty() or not enabled():
		return ""
	if unit_has_det(u, TACTICUS) and group_kw(u, "TACTICUS"):
		return "Wrath of the Chapter"
	if not group_bearer(u, SUPERCHARGED).is_empty():
		return "Supercharged Engines"
	return ""

## Linebreaker Onslaught: "If this unit disembarked this turn: this unit can re-roll charge rolls."
static func charge_reroll_source(u: Dictionary) -> String:
	if u.is_empty() or group_bearer(u, LINEBREAKER).is_empty():
		return ""
	return "Linebreaker Onslaught" if group_disembarked_this_turn(u) else ""

## Linebreaker Onslaught (disembarked this turn) / Seal of Shrouding: "Enemy
## units cannot target this unit with snap shooting attacks." "" = allowed.
static func snap_block_reason(target: Dictionary) -> String:
	if target.is_empty() or not enabled():
		return ""
	if not group_bearer(target, SEAL).is_empty():
		return "Seal of Shrouding"
	if not group_bearer(target, LINEBREAKER).is_empty() and group_disembarked_this_turn(target):
		return "Linebreaker Onslaught (disembarked this turn)"
	return ""

## Spearpoint War Leader: "This unit has Scouts 6"" (0 = no rule).
static func scouts_distance(u: Dictionary) -> float:
	if u.is_empty() or group_bearer(u, SPEARPOINT).is_empty():
		return 0.0
	if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
		return 0.0
	return SPEARPOINT_SCOUTS_IN

## Auspex Triangulation Shrines: a spotted unit has +3" detection range.
static func detection_range_bonus(u: Dictionary) -> float:
	if u.is_empty() or not enabled():
		return 0.0
	return AUSPEX_DETECTION_IN if str(group_flag(u, F_SPOTTED)) == turn_stamp() else 0.0

# ===========================================================================
# Phase lifecycle hooks
# ===========================================================================

## PhaseManager transition hook: Adept of the Codex — the tactical doctrine is
## active for the bearer's unit in addition to any other (SWCommon per-unit
## extra key, written on every component; removed when the bearer is gone).
static func on_phase_transition(_from_phase: int, _to_phase: int) -> void:
	if not enabled():
		return
	refresh_adept_of_the_codex()

static func refresh_adept_of_the_codex() -> void:
	var units: Dictionary = Common.state().get("units", {})
	var covered: Dictionary = {}
	for uid in units:
		var u: Dictionary = units[uid]
		if not has_enh(u, ADEPT) or not Common.is_alive(u):
			continue
		for gid in Common.attached_group_ids(str(uid)):
			covered[str(gid)] = true
	for uid in units:
		var u: Dictionary = units[uid]
		if not u.has("flags") or not (u.flags is Dictionary):
			u["flags"] = {}
		var flags: Dictionary = u.flags
		var extra: Array = (flags.get(F_DOCTRINE_EXTRA, []) as Array).duplicate() if flags.get(F_DOCTRINE_EXTRA, []) is Array else []
		if covered.has(str(uid)):
			if not "tactical" in extra:
				extra.append("tactical")
				flags[F_DOCTRINE_EXTRA] = extra
			if not bool(flags.get(F_ADEPT, false)):
				flags[F_ADEPT] = true
				_log("Adept of the Codex: the tactical doctrine is active for %s in addition to any other" % str(uid))
		elif bool(flags.get(F_ADEPT, false)):
			flags.erase(F_ADEPT)
			if not bool(flags.get("sw11e_ab_guile", false)):
				extra.erase("tactical")
				if extra.is_empty():
					flags.erase(F_DOCTRINE_EXTRA)
				else:
					flags[F_DOCTRINE_EXTRA] = extra
			_log("Adept of the Codex no longer covers %s" % str(uid))

## CommandPhase END_COMMAND hook — Redoubtable Machine Spirit: "At the end of
## your Command phase, heals 1 wound." Applies its diffs; returns them.
static func on_command_phase_end(player: int) -> Array:
	var diffs: Array = []
	if not enabled():
		return diffs
	for b in bearers(player, REDOUBTABLE):
		if not Common.is_on_battlefield(b):
			continue
		var bid := str(b.get("id", ""))
		if str(b.get("flags", {}).get(F_REDOUBTABLE_PHASE, "")) == phase_stamp():
			continue
		var models: Array = b.get("models", [])
		for idx in range(models.size()):
			var mm: Dictionary = models[idx]
			if not mm.get("alive", true):
				continue
			var cw := int(mm.get("current_wounds", mm.get("wounds", 1)))
			if cw < int(mm.get("wounds", 1)):
				var d: Array = [
					{"op": "set", "path": "units.%s.models.%d.current_wounds" % [bid, idx], "value": cw + 1},
					{"op": "set", "path": "units.%s.flags.%s" % [bid, F_REDOUBTABLE_PHASE], "value": phase_stamp()},
				]
				Common.apply_diffs(d)
				diffs.append_array(d)
				var line := "Redoubtable Machine Spirit: %s heals 1 wound (%d -> %d W)" % [Common.unit_name(bid), cw, cw + 1]
				_log(line)
				Common.game_log(player, line)
				break
	return diffs

## MovementPhase end hook — Vanguard Ambushers: "At the end of your Movement
## phase, if a friendly PHOBOS unit is hidden, that unit's attacks can re-roll
## wound rolls of 1 until the end of the turn." Applies its diffs.
static func on_movement_phase_end(player: int) -> Array:
	var diffs: Array = []
	if not has_det(player, SHOCK):
		return diffs
	var names: Array = []
	for head in Common.friendly_heads(player):
		var u := Common.unit(head)
		if not group_kw(u, "PHOBOS") or not unit_is_hidden(u):
			continue
		diffs.append_array(Common.set_flag_diffs(Common.attached_group_ids(head), F_AMBUSH, turn_stamp()))
		names.append(Common.group_label(head))
	if not diffs.is_empty():
		Common.apply_diffs(diffs)
		var line := "Vanguard Ambushers (Phobos Shock Force): %s hidden — re-roll wound rolls of 1 until the end of the turn" % ", ".join(PackedStringArray(names))
		_log(line)
		Common.game_log(player, line)
	else:
		_log("Vanguard Ambushers: no hidden PHOBOS unit at the end of P%d's Movement phase" % player)
	return diffs

# ===========================================================================
# Rule cards in stratagem windows (StratagemManager / AI hooks)
# ===========================================================================

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

static func _offer(sid: String, name: String, type_text: String, effect: String, targets: Array) -> Dictionary:
	return {"stratagem_id": sid, "name": name, "cp_cost": 0, "sm11e_rule": true, "rule": true,
		"type": type_text, "effect_text": effect, "targets": targets}

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	if not enabled() or player <= 0 or not Common.is_sm_army(player):
		return out
	match window_id:
		"unit_selected_to_fight":
			out.append_array(_exhortation_offers(player, ctx))
		"unit_has_shot":
			out.append_array(_combined_offers(player, ctx))
			out.append_array(_shadow_offers(player, ctx))
			out.append_array(_execute_offers(player, ctx))
		"phase_start":
			var ph := str(ctx.get("phase", ""))
			if ph == "shooting":
				out.append_array(_auspex_offers(player))
			elif ph == "movement":
				out.append_array(_damocles_offers(player))
	return out

## BasePhase.enter_phase hook: queue a phase_start window for a player with an
## offer (skipped when another module already queued one for that player — the
## window lists every module's offers).
static func phase_start_entries(phase: int, existing: Array = []) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var phase_name := ""
	if phase == int(GameStateData.Phase.SHOOTING):
		phase_name = "shooting"
	elif phase == int(GameStateData.Phase.MOVEMENT):
		phase_name = "movement"
	else:
		return out
	var nm = Common.autoload("NetworkManager")
	if nm and nm.has_method("is_networked") and bool(nm.is_networked()):
		return out
	var p := Common.active_player()
	for e in existing:
		if int(e.get("player", 0)) == p and str(e.get("window_id", "")) == "phase_start":
			return out
	if not window_offers(p, "phase_start", {"phase": phase_name, "window_id": "phase_start"}).is_empty():
		out.append({"player": p, "window_id": "phase_start", "ctx": {"phase": phase_name}})
	return out

# --- Ancient Exhortation ---------------------------------------------------

static func _exhortation_offers(player: int, ctx: Dictionary) -> Array:
	if Common.current_phase() != int(GameStateData.Phase.FIGHT) or bool(_faction(player).get(FK_EXHORTATION_USED, false)):
		return []
	var uid := str(ctx.get("unit_id", ""))
	var u := Common.unit(uid)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return []
	var b := group_bearer(u, STANDARD)
	if b.is_empty():
		return []
	var head := Common.head_id(uid)
	return [_offer(RULE_EXHORTATION, "ANCIENT EXHORTATION", "Enhancement — Standard of the Emperor Ascendant (once per battle, free)",
		"When this unit is selected to fight, you can use this ability. If you do, this unit's melee attacks have +1 A until the end of the phase.",
		[Common.target_entry(head)])]

static func _use_exhortation(player: int, uid: String) -> Dictionary:
	if _exhortation_offers(player, {"unit_id": uid}).is_empty():
		return {"success": false, "error": "Ancient Exhortation: the Standard of the Emperor Ascendant's unit, when selected to fight (once per battle)", "diffs": []}
	var head := Common.head_id(uid)
	var diffs: Array = Common.set_flag_diffs(Common.attached_group_ids(head), F_EXHORTATION, phase_stamp())
	diffs.append({"op": "set", "path": "factions.%s.%s" % [str(player), FK_EXHORTATION_USED], "value": true})
	Common.apply_diffs(diffs)
	var line := "ANCIENT EXHORTATION — %s: melee attacks +1 A until the end of the phase" % Common.group_label(head)
	_log(line)
	Common.game_log(player, line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Ancient Exhortation", "message": line}

# --- Combined Deployment ---------------------------------------------------

static func _combined_offers(player: int, ctx: Dictionary) -> Array:
	if not has_det(player, GAUNTLET) or Common.current_phase() != int(GameStateData.Phase.SHOOTING) or Common.active_player() != player:
		return []
	var shooter := Common.head_id(str(ctx.get("unit_id", "")))
	var su := Common.unit(shooter)
	if su.is_empty() or int(su.get("owner", 0)) != player or not group_kw(su, "ADEPTUS ASTARTES") or not group_kw(su, "TRANSPORT"):
		return []
	if _shot_rule_used(shooter, RULE_COMBINED):
		return []
	var opts: Array = []
	var seen: Dictionary = {}
	for hid in ctx.get("hit_unit_ids", []):
		var eh := Common.head_id(str(hid))
		var eu := Common.unit(eh)
		if seen.has(eh) or eu.is_empty() or int(eu.get("owner", 0)) == player or not Common.is_alive(eu):
			continue
		seen[eh] = true
		opts.append({"id": eh, "label": "%s%s" % [Common.group_label(eh), " — already assailed" if str(group_flag(eu, F_ASSAILED)) == turn_stamp() else ""]})
	if opts.is_empty():
		return []
	return [_offer(RULE_COMBINED, "COMBINED DEPLOYMENT", "Detachment rule — Gauntlet Task Force (free)",
		"When a friendly ADEPTUS ASTARTES TRANSPORT unit has shot, you can select one enemy unit hit by those attacks. That enemy unit is assailed until the end of the turn: when an ADEPTUS ASTARTES unit that disembarked this turn targets it, those attacks have [SUSTAINED HITS 1].",
		[Common.target_entry(shooter, {"secondary": {"kind": "unit", "prompt": "COMBINED DEPLOYMENT: select one enemy unit hit by those attacks — it is assailed until the end of the turn", "options": opts}})])]

static func _use_combined(player: int, shooter: String, ctx: Dictionary) -> Dictionary:
	var eid := str(ctx.get("secondary_id", ""))
	var ok := false
	for o in _combined_offers(player, {"unit_id": shooter, "hit_unit_ids": ctx.get("hit_unit_ids", [eid])}):
		for t in o.targets:
			for opt in t.get("secondary", {}).get("options", []):
				ok = ok or str(opt.id) == eid
	if not ok:
		return {"success": false, "error": "Combined Deployment: select an enemy unit hit by the TRANSPORT's attacks (your Shooting phase, Gauntlet Task Force)", "diffs": []}
	var diffs: Array = Common.set_flag_diffs(Common.attached_group_ids(eid), F_ASSAILED, turn_stamp())
	Common.apply_diffs(diffs)
	var line := "COMBINED DEPLOYMENT — %s is assailed until the end of the turn (units that disembarked this turn get [SUSTAINED HITS 1] against it)" % Common.group_label(eid)
	_log(line)
	Common.game_log(player, line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Combined Deployment", "message": line}

# --- Shadow Masters --------------------------------------------------------

static func _shadow_offers(player: int, ctx: Dictionary) -> Array:
	if not has_det(player, SHADOW) or Common.current_phase() != int(GameStateData.Phase.SHOOTING):
		return []
	var shooter := Common.head_id(str(ctx.get("unit_id", "")))
	var su := Common.unit(shooter)
	if su.is_empty() or int(su.get("owner", 0)) != player or not Common.is_on_battlefield(su):
		return []
	if not (group_kw(su, "PHOBOS") or group_kw(su, "SCOUT SQUAD")):
		return []
	if _shot_rule_used(shooter, RULE_SHADOW):
		return []
	var variants: Array = [{"id": "hidden", "label": "Stay hidden: those attacks do not prevent it from being hidden"}]
	if Common.engaged_enemy_ids(shooter).is_empty():
		variants.append({"id": "move", "label": "Normal move of up to D6\" (no charge this turn)"})
	return [_offer(RULE_SHADOW, "SHADOW MASTERS", "Detachment rule — Phobos Shadow Force (free)",
		"When a friendly PHOBOS or SCOUT SQUAD unit has shot: those attacks do not prevent that unit from being hidden. Or: that unit can make a normal move of up to D6\"; it is not eligible to declare a charge until the end of the turn.",
		[Common.target_entry(shooter, {"variants": variants, "require_variant": true, "ai_variant": "hidden"})])]

static func _use_shadow(player: int, shooter: String, ctx: Dictionary) -> Dictionary:
	var offers := _shadow_offers(player, {"unit_id": shooter})
	if offers.is_empty():
		return {"success": false, "error": "Shadow Masters: a PHOBOS / SCOUT SQUAD unit that has just shot (Phobos Shadow Force)", "diffs": []}
	var v := str(ctx.get("variant_id", "hidden"))
	var allowed: Array = []
	for vv in offers[0].targets[0].get("variants", []):
		allowed.append(str(vv.id))
	if not v in allowed:
		return {"success": false, "error": "Shadow Masters: '%s' is not available (an engaged unit cannot make a normal move)" % v, "diffs": []}
	var head := Common.head_id(shooter)
	var group := Common.attached_group_ids(head)
	var label := Common.group_label(head)
	if v == "hidden":
		# "Those attacks do not prevent that unit from being hidden": the
		# shot's 13.09 stamp is rolled back to "not shot this or the previous
		# turn" (the engine stamps only Shooting-phase shots — ruling).
		var idx := Common.battle_round() * 2 + (0 if Common.active_player() == 1 else 1)
		var diffs: Array = []
		for gid in group:
			var f: Dictionary = Common.unit(str(gid)).get("flags", {})
			if f.has("last_shot_idx") and int(f.get("last_shot_idx", -100)) >= idx - 1:
				diffs.append({"op": "set", "path": "units.%s.flags.last_shot_idx" % str(gid), "value": idx - 2})
			if f.has("shot_recently"):
				diffs.append({"op": "remove", "path": "units.%s.flags.shot_recently" % str(gid)})
		Common.apply_diffs(diffs)
		var line := "SHADOW MASTERS — %s: those attacks do not prevent it from being hidden" % label
		_log(line)
		Common.game_log(player, line)
		return {"success": true, "diffs": diffs, "stratagem_name": "Shadow Masters", "message": line}
	var d6 := int(Common.roll_dice(1)[0])
	var cdiffs: Array = Common.set_flag_diffs(group, "cannot_charge", true)
	Common.apply_diffs(cdiffs)
	var mline := "SHADOW MASTERS — %s rolls D6 = %d: a normal move of up to %d\" (not eligible to declare a charge this turn)" % [label, d6, d6]
	_log(mline)
	Common.game_log(player, mline)
	return {"success": true, "diffs": cdiffs, "stratagem_name": "Shadow Masters", "message": mline, "roll": d6,
		"followup": {"type": "reactive_normal_move", "unit_id": head, "max_inches": float(d6), "roll": d6, "source": "SHADOW MASTERS"}}

# --- Execute and Redeploy --------------------------------------------------

static func _execute_offers(player: int, ctx: Dictionary) -> Array:
	if Common.current_phase() != int(GameStateData.Phase.SHOOTING) or Common.active_player() != player:
		return []
	var shooter := Common.head_id(str(ctx.get("unit_id", "")))
	var su := Common.unit(shooter)
	if su.is_empty() or int(su.get("owner", 0)) != player or not Common.is_on_battlefield(su):
		return []
	var b := group_bearer(su, EXECUTE)
	if b.is_empty() or str(b.get("flags", {}).get(F_EXECUTE_PHASE, "")) == phase_stamp():
		return []
	if not Common.engaged_enemy_ids(shooter).is_empty():
		return []
	return [_offer(RULE_EXECUTE, "EXECUTE AND REDEPLOY", "Enhancement — Phobos Shadow Force (free)",
		"In your Shooting phase, after this unit has shot, if this unit is unengaged, this unit can make a normal move of up to 6\". If it does, this unit is not eligible to declare a charge until the end of the turn.",
		[Common.target_entry(shooter)])]

static func _use_execute(player: int, shooter: String) -> Dictionary:
	if _execute_offers(player, {"unit_id": shooter}).is_empty():
		return {"success": false, "error": "Execute and Redeploy: the bearer's unit, unengaged, after it has shot (once per phase)", "diffs": []}
	var head := Common.head_id(shooter)
	var b := group_bearer(Common.unit(head), EXECUTE)
	var group := Common.attached_group_ids(head)
	var diffs: Array = Common.set_flag_diffs(group, "cannot_charge", true)
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(b.get("id", head)), F_EXECUTE_PHASE], "value": phase_stamp()})
	Common.apply_diffs(diffs)
	var line := "EXECUTE AND REDEPLOY — %s can make a normal move of up to 6\" (not eligible to declare a charge this turn)" % Common.group_label(head)
	_log(line)
	Common.game_log(player, line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Execute and Redeploy", "message": line,
		"followup": {"type": "reactive_normal_move", "unit_id": head, "max_inches": EXECUTE_MOVE_IN, "source": "EXECUTE AND REDEPLOY"}}

# --- Auspex Triangulation Shrines ------------------------------------------

static func _auspex_offers(player: int) -> Array:
	if Common.current_phase() != int(GameStateData.Phase.SHOOTING) or Common.active_player() != player:
		return []
	var targets: Array = []
	for b in bearers(player, AUSPEX):
		var bid := str(b.get("id", ""))
		if not Common.is_on_battlefield(b) or str(b.get("flags", {}).get(F_AUSPEX_PHASE, "")) == phase_stamp():
			continue
		var opts: Array = []
		for eh in Common.enemy_heads(player):
			var d := Common.group_distance_inches(bid, eh)
			if d > AUSPEX_RANGE_IN + 0.001 or not _visible(bid, eh):
				continue
			opts.append({"id": eh, "label": "%s (%.1f\")%s" % [Common.group_label(eh), d, " — hidden" if unit_is_hidden(Common.unit(eh)) else ""]})
		if opts.is_empty():
			continue
		targets.append(Common.target_entry(Common.head_id(bid), {"bearer_id": bid,
			"secondary": {"kind": "unit", "prompt": "AUSPEX TRIANGULATION SHRINES: select one visible enemy unit within 12\" — it is spotted (+3\" detection range)", "options": opts}}))
	if targets.is_empty():
		return []
	return [_offer(RULE_AUSPEX, "AUSPEX TRIANGULATION SHRINES", "Enhancement — Stormlance Task Force (free)",
		"At the start of your Shooting phase, select one visible enemy unit within 12\" of this unit. That enemy unit is spotted: while a unit is spotted, that unit has +3\" detection range.",
		targets)]

static func _use_auspex(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var eid := str(ctx.get("secondary_id", ""))
	var bid := ""
	for o in _auspex_offers(player):
		for t in o.targets:
			if str(t.unit_id) != Common.head_id(target_unit_id):
				continue
			for opt in t.get("secondary", {}).get("options", []):
				if str(opt.id) == eid:
					bid = str(t.get("bearer_id", t.unit_id))
	if bid == "":
		return {"success": false, "error": "Auspex Triangulation Shrines: select a visible enemy unit within 12\" (start of your Shooting phase)", "diffs": []}
	var diffs: Array = Common.set_flag_diffs(Common.attached_group_ids(eid), F_SPOTTED, turn_stamp())
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [bid, F_AUSPEX_PHASE], "value": phase_stamp()})
	Common.apply_diffs(diffs)
	var line := "AUSPEX TRIANGULATION SHRINES — %s spots %s: +3\" detection range until the end of the turn" % [Common.unit_name(bid), Common.group_label(eid)]
	_log(line)
	Common.game_log(player, line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Auspex Triangulation Shrines", "message": line}

# --- Damocles-class Uplink -------------------------------------------------

static func _damocles_offers(player: int) -> Array:
	if Common.current_phase() != int(GameStateData.Phase.MOVEMENT) or Common.active_player() != player:
		return []
	var targets: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for b in bearers(player, DAMOCLES):
		var bid := str(b.get("id", ""))
		var tid := str(b.get("embarked_in", "")) if b.get("embarked_in", null) != null else ""
		if tid == "" or not Common.is_alive(b) or str(b.get("flags", {}).get(F_DAMOCLES_PHASE, "")) == phase_stamp():
			continue
		var tu := Common.unit(tid)
		if not Common.is_on_battlefield(tu):
			continue
		for head in Common.friendly_heads(player):
			var hu := Common.unit(head)
			if not group_kw(hu, "ADEPTUS ASTARTES") or not group_kw(hu, "INFANTRY"):
				continue
			var d := Common.group_distance_inches(head, tid)
			if d > DAMOCLES_RANGE_IN + 0.001:
				continue
			var variants: Array = []
			for doc in Common.DOCTRINES:
				variants.append({"id": doc, "label": "%s: %s" % [Common.group_label(head), str(Common.DOCTRINE_LABELS[doc])]})
			targets.append(Common.target_entry(head, {"bearer_id": bid, "variants": variants, "require_variant": true,
				"ai_variant": ai_doctrine_for(head), "label": "%s (%.1f\" from %s)" % [Common.group_label(head), d, Common.unit_name(tid)]}))
	if targets.is_empty():
		return []
	return [_offer(RULE_DAMOCLES, "DAMOCLES-CLASS UPLINK", "Enhancement — Gauntlet Task Force (free)",
		"In your Movement phase, if this unit is embarked within a TRANSPORT unit, you can select one friendly ADEPTUS ASTARTES INFANTRY unit within 6\" of that TRANSPORT unit and select one combat doctrine. That combat doctrine is active for that INFANTRY unit.",
		targets)]

static func _use_damocles(player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var head := Common.head_id(target_unit_id)
	var doc := str(ctx.get("variant_id", "")).to_lower()
	var bid := ""
	for o in _damocles_offers(player):
		for t in o.targets:
			if str(t.unit_id) == head:
				bid = str(t.get("bearer_id", ""))
	if bid == "":
		return {"success": false, "error": "Damocles-class Uplink: an ADEPTUS ASTARTES INFANTRY unit within 6\" of the Captain's TRANSPORT (your Movement phase, once)", "diffs": []}
	if not doc in Common.DOCTRINES:
		doc = ai_doctrine_for(head)
	var group := Common.attached_group_ids(head)
	var diffs: Array = Common.set_flag_diffs(group, F_DOCTRINE, doc)
	diffs.append_array(Common.set_flag_diffs(group, F_DOCTRINE_EXPIRES, player))
	diffs.append_array(Common.set_flag_diffs(group, F_DAMOCLES, doc))
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [bid, F_DAMOCLES_PHASE], "value": phase_stamp()})
	Common.apply_diffs(diffs)
	var line := "DAMOCLES-CLASS UPLINK (%s): %s active for %s until the start of your next Command phase" % [Common.unit_name(bid), str(Common.DOCTRINE_LABELS[doc]), Common.group_label(head)]
	_log(line)
	Common.game_log(player, line)
	return {"success": true, "diffs": diffs, "stratagem_name": "Damocles-class Uplink", "message": line, "doctrine": doc}

## The doctrine the AI (and a use without a choice) picks for a unit:
## tactical when engaged, assault within 12" of the enemy, else devastator.
static func ai_doctrine_for(unit_id: String) -> String:
	if not Common.engaged_enemy_ids(unit_id).is_empty():
		return "tactical"
	if Common.nearest_enemy_inches(Common.group_union(unit_id)) <= 12.0:
		return "assault"
	return "devastator"

# --- dispatch --------------------------------------------------------------

static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var res: Dictionary
	match sid:
		RULE_EXHORTATION:
			res = _use_exhortation(player, target_unit_id)
		RULE_COMBINED:
			res = _use_combined(player, target_unit_id, ctx)
		RULE_SHADOW:
			res = _use_shadow(player, target_unit_id, ctx)
		RULE_EXECUTE:
			res = _use_execute(player, target_unit_id)
		RULE_AUSPEX:
			res = _use_auspex(player, target_unit_id, ctx)
		RULE_DAMOCLES:
			res = _use_damocles(player, target_unit_id, ctx)
		_:
			res = {"success": false, "error": "unknown Codex: Space Marines rule offer %s" % sid, "diffs": []}
	if res.get("success", false) and sid in [RULE_COMBINED, RULE_SHADOW]:
		var used := _shot_rule_used_diffs(target_unit_id, sid)
		Common.apply_diffs(used)
		var all_diffs: Array = res.get("diffs", [])
		all_diffs.append_array(used)
		res["diffs"] = all_diffs
	if res.get("success", false):
		res["rule_use"] = true
		if not res.has("reopen_window"):
			res["reopen_window"] = true
	return res

## AI choices (synchronous; {} = decline). Every card is free.
##  - Ancient Exhortation: always, the first time the bearer's unit fights
##    while engaged (once per battle).
##  - Combined Deployment: always — the most expensive enemy unit hit.
##  - Shadow Masters: "stay hidden" when the unit stands where it can be
##    hidden (an INFANTRY model in dense terrain); otherwise declined.
##  - Execute and Redeploy: when the unit is out of range of every objective
##    and a 6" move reaches one (the engine's reactive-move solver).
##  - Auspex Triangulation Shrines: the most expensive candidate, a hidden one first.
##  - Damocles-class Uplink: the first unit offered, ai_doctrine_for(unit) —
##    never the doctrine already active for it.
static func ai_decide(_player: int, _window_id: String, offers: Array, _ctx: Dictionary) -> Dictionary:
	for offer in offers:
		var sid := str(offer.get("stratagem_id", ""))
		if not is_rule_offer_id(sid):
			continue
		var targets: Array = offer.get("targets", [])
		if targets.is_empty():
			continue
		var t: Dictionary = targets[0]
		match sid:
			RULE_EXHORTATION:
				if not Common.engaged_enemy_ids(str(t.unit_id)).is_empty():
					return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.unit_id), "context": {}, "name": "ANCIENT EXHORTATION"}
			RULE_COMBINED, RULE_AUSPEX:
				var best := ""
				var best_score := -1.0
				for o in t.get("secondary", {}).get("options", []):
					var eu := Common.unit(str(o.id))
					var score := float(eu.get("meta", {}).get("points", 0))
					if sid == RULE_AUSPEX and unit_is_hidden(eu):
						score += 10000.0
					if score > best_score:
						best_score = score
						best = str(o.id)
				if best != "":
					return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.unit_id), "context": {"secondary_id": best}, "name": str(offer.get("name", sid))}
			RULE_SHADOW:
				if _could_be_hidden(str(t.unit_id)):
					return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.unit_id), "context": {"variant_id": "hidden"}, "name": "SHADOW MASTERS"}
			RULE_EXECUTE:
				if _move_reaches_objective(str(t.unit_id), EXECUTE_MOVE_IN):
					return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.unit_id), "context": {}, "name": "EXECUTE AND REDEPLOY"}
			RULE_DAMOCLES:
				for tt in targets:
					var d := str(tt.get("ai_variant", "devastator"))
					if not Common.doctrine_active_id(str(tt.unit_id), d):
						return {"use": true, "stratagem_id": sid, "target_unit_id": str(tt.unit_id), "context": {"variant_id": d}, "name": "DAMOCLES-CLASS UPLINK"}
	return {}

## Would the unit be hidden if its shot did not count? (INFANTRY / BEASTS /
## SWARM in a dense terrain area — every alive model.)
static func _could_be_hidden(unit_id: String) -> bool:
	var tm = Common.autoload("TerrainManager")
	if tm == null or not tm.has_method("is_model_hidden"):
		return false
	var any := false
	for gid in Common.attached_group_ids(unit_id):
		var gu: Dictionary = Common.unit(str(gid)).duplicate(true)
		var f: Dictionary = gu.get("flags", {})
		f.erase("last_shot_idx")
		f.erase("shot_recently")
		gu["flags"] = f
		for m in gu.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			any = true
			if not tm.is_model_hidden(m, gu):
				return false
	return any

static func _move_reaches_objective(unit_id: String, inches: float) -> bool:
	if Common.group_in_range_of_any_objective(unit_id):
		return false
	var rm = load("res://scripts/rules/ReactiveMove11e.gd")
	if rm == null:
		return false
	var origin: Dictionary = rm.current_positions(unit_id, Common.state())
	var sol: Dictionary = rm.solve("normal", unit_id, origin, inches, {}, Common.state())
	return not sol.is_empty() and sol != origin
