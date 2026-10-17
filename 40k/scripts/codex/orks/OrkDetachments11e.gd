extends RefCounted

## OrkDetachments11e — the 15 Codex: Orks (11th edition) detachment rules
## (WP-O34, plan O4) plus the rule choices the army rules / detachment rules
## offer through the stratagem-window framework.
##
## Source of truth: .llm/codex_11e_wahapedia/orks/RULES.md (each detachment's
## "Rule —" line). Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md.
## Engine files (RulesEngine, EffectPrimitives, ModifierStack, the phases,
## StratagemManager, BasePhase, FactionAbilityManager, AIDecisionMaker, ...)
## only call the static functions below from one-line, commented hooks.
##
##  War Horde — Get Stuck In ............ ORKS melee attacks [SUSTAINED HITS 1]
##  Madcap Meks — Unpredictable Genius .. D6 table when all of a Big Mek / Mek
##                                        Gunz / Morkanaut / Wazbom Blastajet
##                                        unit's ranged attacks target one unit
##  Wurrband — Powers of da Waaagh! ..... [PSYCHIC] attacks +S; Roar of Mork and
##                                        Visions of Violence psychic abilities
##  Runt Swarm — Sneaky Little Gitz ..... Gretchin BATTLELINE; advance/fall back
##                                        keeps them eligible to start actions
##  Wreckas — Wreckin' and Lootin' ...... re-roll hit rolls of 1 near objectives
##  Brute Bosses — 'Ard as Nails ........ a destroyed WARBOSS fights on a 3+
##  Bully Boyz — Displays of Savagery ... Meganobz/Nobz melee [SUSTAINED HITS 1]
##  Da Big Hunt — Da Hunt is On ......... Beast Snagga +1 AP vs MONSTER/VEHICLE
##  Dread Mob — Try Dat Button! ......... one or two D6 when a WALKER is selected
##                                        to attack (+1 A / +2 S / +1 AP)
##  Shoota Boyz — Dakka! Dakka! Dakka! .. ORKS INFANTRY ranged [ASSAULT]; +3"
##                                        range while riled up
##  Flyboyz — Skyborne Loons ............ AIRCRAFT free of the reserves points
##                                        limit; riled-up Aircraft/Deffkoptas +1
##                                        to hit (ranged)
##  Kult of Speed — Adrenaline Junkies .. Warbikers BATTLELINE; Speed Freeks
##                                        advance/fall back: [ASSAULT], can charge
##  Blitz Brigade — Unstoppable Momentum  WAGON re-roll charges; advance rolls
##                                        changed to a 6
##  Green Tide — Mob-handed Brutality ... Boyz melee [SUSTAINED HITS 1]; charged
##                                        ORKS INFANTRY melee [LETHAL HITS] vs
##                                        non-MONSTER/VEHICLE
##  Taktikal Brigade — Suspiciously Well Organised
##                                        Stormboyz BATTLELINE; Boyz / Kommandos
##                                        / Stormboyz fall back and still charge
##
## Rulings are listed in .llm/codex_11e_wahapedia/RULINGS.md (WP-O34).

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")
const ArmyRules = preload("res://scripts/codex/orks/OrkArmyRules11e.gd")

# ---------------------------------------------------------------------------
# Detachment keys (normalised: lower case, folded apostrophes)
# ---------------------------------------------------------------------------

const WAR_HORDE := "war horde"
const MADCAP_MEKS := "madcap meks"
const WURRBAND := "wurrband"
const RUNT_SWARM := "runt swarm"
const WRECKAS := "wreckas"
const BRUTE_BOSSES := "brute bosses"
const BULLY_BOYZ := "bully boyz"
const DA_BIG_HUNT := "da big hunt"
const DREAD_MOB := "dread mob"
const SHOOTA_BOYZ := "shoota boyz"
const FLYBOYZ := "flyboyz"
const KULT_OF_SPEED := "kult of speed"
const BLITZ_BRIGADE := "blitz brigade"
const GREEN_TIDE := "green tide"
const TAKTIKAL_BRIGADE := "taktikal brigade"

const RULE_NAMES := {
	WAR_HORDE: "Get Stuck In",
	MADCAP_MEKS: "Unpredictable Genius",
	WURRBAND: "Powers of da Waaagh!",
	RUNT_SWARM: "Sneaky Little Gitz",
	WRECKAS: "Wreckin' and Lootin'",
	BRUTE_BOSSES: "'Ard as Nails",
	BULLY_BOYZ: "Displays of Savagery",
	DA_BIG_HUNT: "Da Hunt is On",
	DREAD_MOB: "Try Dat Button!",
	SHOOTA_BOYZ: "Dakka! Dakka! Dakka!",
	FLYBOYZ: "Skyborne Loons",
	KULT_OF_SPEED: "Adrenaline Junkies",
	BLITZ_BRIGADE: "Unstoppable Momentum",
	GREEN_TIDE: "Mob-handed Brutality",
	TAKTIKAL_BRIGADE: "Suspiciously Well Organised",
}

## Detachment BATTLELINE grants (keyword of the datasheet that gains it).
const BATTLELINE_GRANTS := {KULT_OF_SPEED: "WARBIKERS", TAKTIKAL_BRIGADE: "STORMBOYZ", RUNT_SWARM: "GRETCHIN"}

# ---------------------------------------------------------------------------
# Rule offers (ride the stratagem-window framework; free, never stratagems)
# ---------------------------------------------------------------------------

const RULE_PREFIX := "ork11e_rule_"
const RULE_TRY_DAT_BUTTON := "ork11e_rule_try_dat_button"
const RULE_HOP_SPLAT := "ork11e_rule_hop_splat"
const RULE_ROAR_OF_MORK := "ork11e_rule_roar_of_mork"
const RULE_VISIONS := "ork11e_rule_visions_of_violence"

## Rule-only windows this module asks the phases to open.
const WINDOW_FIGHT_START := "ork11e_fight_phase_start"  # Visions of Violence
const WINDOW_HOP_SPLAT := "ork11e_hop_splat"            # Unpredictable Genius 2-3

# ---------------------------------------------------------------------------
# Flags (no effect_ prefix: ShootingPhase wipes effect_* on exit; every flag
# has a clear point listed here and a headless expiry check)
# ---------------------------------------------------------------------------

## Try Dat Button! result on every component of the walker unit:
## {phase, stamp, rolls, rows, a, s, ap, two}. Cleared when the unit has
## attacked (shot / fought) — with the hazard roll for two dice — or at the
## end of the phase.
const F_TDB := "ork11e_tdb"
## Unpredictable Genius on the shooter: {result, target, stamp}. Cleared when
## the unit has shot (and at the end of the Shooting phase).
const F_UG := "ork11e_ug"
## On a target Lifted (result 5) that had no FLY: the shooter that granted it
## (FLY is removed again when that unit has shot).
const F_UG_LIFTED_BY := "ork11e_ug_lifted_by"
## Visions of Violence: this module set flags.fights_first (cleared at the
## end of the Fight phase unless the unit charged).
const F_VISIONS_FF := "ork11e_visions_ff"
## BATTLELINE was added to meta.keywords by a detachment grant.
const F_BATTLELINE_GRANT := "ork11e_battleline_grant"

## 'Ard as Nails pass value (Fight On Death roll, +1 if riled up).
const ARD_AS_NAILS_PASS := 3
const ARD_AS_NAILS_MODE := "ard_as_nails"

const TRY_DAT_ROWS := [
	{"row": 0, "label": "+1 A", "a": 1, "s": 0, "ap": 0},  # 1-2
	{"row": 1, "label": "+2 S", "a": 0, "s": 2, "ap": 0},  # 3-4
	{"row": 2, "label": "+1 AP", "a": 0, "s": 0, "ap": 1}, # 5-6
]

const UG_RESULTS := {
	1: "Dat's Weird: the target has a 4+ invulnerable save until your unit has shot",
	2: "Hop Splat: one other enemy unit within 3\" of the target suffers D3 mortal wounds",
	3: "Hop Splat: one other enemy unit within 3\" of the target suffers D3 mortal wounds",
	4: "Seekerz: those attacks have +1 to hit rolls",
	5: "Lifted: the target has FLY and cannot have the benefit of cover until your unit has shot",
	6: "Runtified: the target has -1 T until your unit has shot",
}

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return GameConstants.edition >= 11

static func det_key(name: String) -> String:
	return name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()

static func _board_or_state(board: Dictionary) -> Dictionary:
	return board if board.has("units") else Common.state()

## Normalised detachment name of `player` ("" at 10e or when unknown).
static func detachment_of(player: int, board: Dictionary = {}) -> String:
	if not enabled() or player <= 0:
		return ""
	var factions: Dictionary = _board_or_state(board).get("factions", {})
	if factions.is_empty():
		factions = Common.state().get("factions", {})
	return det_key(str(factions.get(str(player), {}).get("detachment", "")))

static func unit_detachment(u: Dictionary, board: Dictionary = {}) -> String:
	if u.is_empty():
		return ""
	return detachment_of(int(u.get("owner", 0)), board)

static func rule_name(det: String) -> String:
	return str(RULE_NAMES.get(det, ""))

## The unit and its Attached-unit components (dicts). Keyword checks look at
## the whole Attached unit (19.03 — design §7.2 ruling).
static func group_units(u: Dictionary, board: Dictionary = {}) -> Array:
	var uid := str(u.get("id", ""))
	if uid == "":
		return [u]
	var units: Dictionary = _board_or_state(board).get("units", {})
	var out: Array = []
	for gid in Common.attached_group_ids(uid):
		# The caller's own dict stands for its unit (a resolver's board copy
		# may differ from the board the components are read from).
		var gu = u if str(gid) == uid else units.get(str(gid), {})
		if not gu.is_empty():
			out.append(gu)
	if out.is_empty():
		out.append(u)
	return out

static func group_kw(u: Dictionary, kw: String, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if Common.has_keyword(gu, kw):
			return true
	return false

static func group_any_kw(u: Dictionary, kws: Array, board: Dictionary = {}) -> bool:
	for kw in kws:
		if group_kw(u, str(kw), board):
			return true
	return false

static func group_riled_up(u: Dictionary, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if Common.is_riled_up(gu):
			return true
	return false

static func _group_flag(u: Dictionary, flag: String, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if bool(gu.get("flags", {}).get(flag, false)):
			return true
	return false

static func _alive_models(u: Dictionary) -> int:
	var n := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			n += 1
	return n

static func _group_alive_models(u: Dictionary, board: Dictionary = {}) -> int:
	var n := 0
	for gu in group_units(u, board):
		n += _alive_models(gu)
	return n

static func _phase_name() -> String:
	var ph := int(Common.state().get("meta", {}).get("phase", -1))
	var gsd = Common.GameStateData
	if ph == int(gsd.Phase.SHOOTING):
		return "shooting"
	if ph == int(gsd.Phase.FIGHT):
		return "fight"
	if ph == int(gsd.Phase.MOVEMENT):
		return "movement"
	if ph == int(gsd.Phase.COMMAND):
		return "command"
	if ph == int(gsd.Phase.CHARGE):
		return "charge"
	return str(ph)

static func _stamp() -> String:
	var meta: Dictionary = Common.state().get("meta", {})
	return "%d:%d:%d" % [int(meta.get("battle_round", 1)), int(meta.get("active_player", 1)), int(meta.get("phase", -1))]

static func _log(msg: String) -> void:
	Common.log_info("OrkDetachments11e: " + msg)

static func _event(player: int, msg: String) -> void:
	var gel = Common.autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, msg)

static func _toast(msg: String, color: Color = Color.GOLD) -> void:
	var tm = Common.autoload("ToastManager")
	if tm and tm.has_method("show_toast"):
		tm.show_toast(msg, color)

static func _apply(diffs: Array) -> void:
	if diffs.is_empty():
		return
	var pm = Common.autoload("PhaseManager")
	if pm and pm.has_method("apply_state_changes"):
		pm.apply_state_changes(diffs)
	else:
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)

## The engine's RNG (RulesEngine.make_rng: network seed on a host, the static
## test seed under the harness, randomised otherwise).
static func _rng(_seed_value: int = -1):
	var re = Common.rules()
	if re == null:
		return null
	return re.make_rng()

static func _d6(rng) -> int:
	return int(rng.roll_d6(1)[0])

static func _d3(rng) -> int:
	return int(ceil(float(_d6(rng)) / 2.0))

static func _is_target(u: Dictionary) -> bool:
	return Common.has_keyword(u, "MONSTER") or Common.has_keyword(u, "VEHICLE")

static func _group_is_mv(u: Dictionary, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if _is_target(gu):
			return true
	return false

## Mortal wounds to a unit (06.02): the bodyguard first, spilling to the
## Attached unit's characters (same convention as OrkCodexOther).
static func mortal_wounds_to_unit(unit_id: String, mortal_wounds: int, rng) -> Dictionary:
	var out := {"diffs": [], "casualties": 0, "wounds_applied": 0}
	var re = Common.rules()
	var gs = Common.game_state()
	if re == null or gs == null or mortal_wounds <= 0:
		return out
	var remaining := mortal_wounds
	var first := true
	var head := unit_id
	if re.has_method("attached_unit_target_id"):
		head = str(re.attached_unit_target_id(unit_id, Common.state()))
	for gid in Common.attached_group_ids(head):
		if remaining <= 0:
			break
		var u = Common.unit(gid)
		if u.is_empty() or not Common.is_alive(u):
			continue
		var pool := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				pool += int(m.get("current_wounds", m.get("wounds", 1)))
		var res: Dictionary = re.apply_mortal_wounds(gid, remaining, gs.create_snapshot(), rng if first else null)
		first = false
		out.diffs.append_array(res.get("diffs", []))
		out.casualties += int(res.get("casualties", 0))
		var applied := int(res.get("wounds_applied", 0))
		out.wounds_applied += mini(applied, pool)
		remaining = maxi(0, applied - pool)
	return out

static func _battle_shock_diffs(u: Dictionary) -> Array:
	var diffs: Array = []
	for gu in group_units(u):
		diffs.append({"op": "set", "path": "units.%s.flags.battle_shocked" % str(gu.get("id", "")), "value": true})
	return diffs

# ===========================================================================
# BATTLELINE grants (Kult of Speed / Taktikal Brigade / Runt Swarm)
# ===========================================================================

## Write BATTLELINE into meta.keywords of every unit the player's detachment
## grants it to (what the game reads BATTLELINE from: stratagem targeting,
## the AI). Idempotent; returns the applied diffs. Called when the army is
## loaded and at the start of each of the player's Command phases.
static func apply_keyword_grants(player: int) -> Array:
	var diffs: Array = []
	var det := detachment_of(player)
	if not BATTLELINE_GRANTS.has(det):
		return diffs
	var kw := str(BATTLELINE_GRANTS[det])
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not Common.has_keyword(u, kw):
			continue
		var kws: Array = u.get("meta", {}).get("keywords", [])
		if "BATTLELINE" in kws:
			continue
		# In place (army load runs outside any phase action, like the 10e grant
		# it replaces); the diffs are returned for callers that propagate them.
		kws.append("BATTLELINE")
		if not u.has("flags"):
			u["flags"] = {}
		u.flags[F_BATTLELINE_GRANT] = rule_name(det)
		diffs.append({"op": "set", "path": "units.%s.meta.keywords" % uid, "value": kws.duplicate()})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_BATTLELINE_GRANT], "value": rule_name(det)})
		_log("%s — %s (%s) gains BATTLELINE" % [rule_name(det), Common.unit_name(str(uid)), uid])
	return diffs

# ===========================================================================
# Combat modifiers (RulesEngine hooks)
# ===========================================================================

## Melee [SUSTAINED HITS 1] — Get Stuck In (every ORKS unit), Displays of
## Savagery (MEGANOBZ / NOBZ units), Mob-handed Brutality (BOYZ units).
## Returns {value, source}; the caller only applies it when the weapon has no
## SUSTAINED HITS of its own (duplicates do not stack).
static func melee_sustained_hits(attacker: Dictionary, board: Dictionary = {}) -> Dictionary:
	match unit_detachment(attacker, board):
		WAR_HORDE:
			if group_kw(attacker, "ORKS", board):
				return {"value": 1, "source": "Get Stuck In (War Horde)"}
		BULLY_BOYZ:
			if group_any_kw(attacker, ["MEGANOBZ", "NOBZ"], board):
				return {"value": 1, "source": "Displays of Savagery (Bully Boyz)"}
		GREEN_TIDE:
			if group_kw(attacker, "BOYZ", board):
				return {"value": 1, "source": "Mob-handed Brutality (Green Tide)"}
	return {"value": 0, "source": ""}

## Mob-handed Brutality: an ORKS INFANTRY unit that made a charge move this
## turn has melee [LETHAL HITS] against non-MONSTER/VEHICLE targets. Returns
## the source name or "".
static func melee_lethal_hits_source(attacker: Dictionary, target: Dictionary, board: Dictionary = {}) -> String:
	if unit_detachment(attacker, board) != GREEN_TIDE:
		return ""
	if not (group_kw(attacker, "ORKS", board) and group_kw(attacker, "INFANTRY", board)):
		return ""
	if not _group_flag(attacker, "charged_this_turn", board):
		return ""
	if _group_is_mv(target, board):
		return ""
	return "Mob-handed Brutality (Green Tide)"

## +N AP (improve) for an attack — Da Hunt is On (BEAST SNAGGA vs MONSTER /
## VEHICLE) and Try Dat Button! (5-6). Called from every resolver path through
## RulesEngine.get_prey_ap_bonus at edition 11.
static func attack_ap_bonus(attacker: Dictionary, target: Dictionary, board: Dictionary = {}) -> int:
	var bonus := 0
	if unit_detachment(attacker, board) == DA_BIG_HUNT and group_kw(attacker, "BEAST SNAGGA", board) \
			and _group_is_mv(target, board) and int(attacker.get("owner", 0)) != int(target.get("owner", -1)):
		bonus += 1
	bonus += int(_tdb(attacker).get("ap", 0))
	return bonus

## Strength bonus for one weapon's attacks — Try Dat Button! (3-4: +2 S) and
## Powers of da Waaagh! (an ORKS PSYKER model's [PSYCHIC] attacks: +1 S, +1 S
## for every 5 models in its unit or embarked within it). {value, sources}.
static func strength_bonus(attacker: Dictionary, weapon_id: String, board: Dictionary = {}) -> Dictionary:
	var value := 0
	var sources: Array = []
	var tdb_s := int(_tdb(attacker).get("s", 0))
	if tdb_s > 0:
		value += tdb_s
		sources.append("Try Dat Button! +%d S" % tdb_s)
	if unit_detachment(attacker, board) == WURRBAND and group_kw(attacker, "ORKS", board) \
			and group_kw(attacker, "PSYKER", board) and weapon_id != "":
		var re = Common.rules()
		if re and re.has_method("is_psychic_weapon") and re.is_psychic_weapon(weapon_id, _board_or_state(board)):
			var models := _group_alive_models(attacker, board) + _embarked_models(attacker, board)
			var pw := 1 + int(models / 5)
			value += pw
			sources.append("Powers of da Waaagh! +%d S (%d models)" % [pw, models])
	return {"value": value, "sources": sources}

static func _embarked_models(u: Dictionary, board: Dictionary = {}) -> int:
	var uid := str(u.get("id", ""))
	if uid == "":
		return 0
	var n := 0
	var units: Dictionary = _board_or_state(board).get("units", {})
	for oid in units:
		var o: Dictionary = units[oid]
		if str(o.get("embarked_in", "")) == uid:
			n += _alive_models(o)
	return n

## +N Attacks per model — Try Dat Button! (1-2: +1 A).
static func attacks_bonus_per_model(attacker: Dictionary) -> int:
	return int(_tdb(attacker).get("a", 0))

## +1 to hit source ("" = none) — Skyborne Loons (a riled-up ORKS AIRCRAFT /
## DEFFKOPTAS unit's ranged attacks) and Unpredictable Genius 4 (Seekerz).
static func hit_plus_one_source(attacker: Dictionary, target: Dictionary, is_melee: bool, board: Dictionary = {}) -> String:
	if is_melee:
		return ""
	if unit_detachment(attacker, board) == FLYBOYZ and group_kw(attacker, "ORKS", board) \
			and group_any_kw(attacker, ["AIRCRAFT", "DEFFKOPTAS"], board) and group_riled_up(attacker, board):
		return "Skyborne Loons (riled up)"
	var ug := _ug(attacker)
	if int(ug.get("result", 0)) == 4 and str(ug.get("target", "")) == str(target.get("id", "")):
		return "Unpredictable Genius — Seekerz"
	return ""

## Re-roll hit rolls of 1 — Wreckin' and Lootin': in your Shooting phase, a
## Breaka Boyz / Flash Gitz / Tankbustas unit within range of an objective, or
## shooting a target within range of one. Returns the source name or "".
static func hit_reroll_ones_source(attacker: Dictionary, target: Dictionary, is_melee: bool, board: Dictionary = {}) -> String:
	if is_melee or unit_detachment(attacker, board) != WRECKAS:
		return ""
	if not group_any_kw(attacker, ["BREAKA BOYZ", "FLASH GITZ", "TANKBUSTAS"], board):
		return ""
	var meta: Dictionary = Common.state().get("meta", {})
	if int(meta.get("active_player", 0)) != int(attacker.get("owner", -1)):
		return ""  # "In your Shooting phase" — never Overwatch in the opponent's turn
	if int(meta.get("phase", -1)) != int(Common.GameStateData.Phase.SHOOTING):
		return ""
	if unit_within_range_of_objective(attacker, board):
		return "Wreckin' and Lootin' (unit within range of an objective)"
	if unit_within_range_of_objective(target, board):
		return "Wreckin' and Lootin' (target within range of an objective)"
	return ""

## A unit is within range of an objective while any of its models (or its
## Attached unit's) is — the same terrain-aware predicate objective control
## uses (MissionManager.model_in_objective_range).
static func unit_within_range_of_objective(u: Dictionary, board: Dictionary = {}) -> bool:
	var mm = Common.autoload("MissionManager")
	var src := _board_or_state(board)
	var objectives: Array = src.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		objectives = Common.state().get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return false
	for gu in group_units(u, board):
		for m in gu.get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			for obj in objectives:
				if mm and mm.has_method("model_in_objective_range"):
					if mm.model_in_objective_range(m, obj):
						return true
				else:
					var re = Common.rules()
					if re and re.is_unit_near_any_objective({"models": [m]}, src):
						return true
	return false

## Unpredictable Genius 6 (Runtified): the target's T for this shooter's attacks.
static func target_toughness(attacker: Dictionary, target: Dictionary, toughness: int) -> int:
	var ug := _ug(attacker)
	if int(ug.get("result", 0)) == 6 and str(ug.get("target", "")) == str(target.get("id", "")):
		var t := maxi(1, toughness - 1)
		_log("Unpredictable Genius — Runtified: %s T %d -> %d against %s's attacks" % [str(target.get("id", "")), toughness, t, str(attacker.get("id", ""))])
		return t
	return toughness

## Unpredictable Genius 1 (Dat's Weird): the target's invulnerable save for this
## shooter's attacks (0 = none). Returns the better of the two.
static func target_invuln(attacker: Dictionary, target: Dictionary, current_invuln: int) -> int:
	var ug := _ug(attacker)
	if int(ug.get("result", 0)) == 1 and str(ug.get("target", "")) == str(target.get("id", "")):
		var best: int = 4 if (current_invuln <= 0 or current_invuln > 4) else current_invuln
		if best != current_invuln:
			_log("Unpredictable Genius — Dat's Weird: %s has a 4+ invulnerable save against %s's attacks" % [str(target.get("id", "")), str(attacker.get("id", ""))])
		return best
	return current_invuln

## Unpredictable Genius 5 (Lifted): the target cannot have the benefit of
## cover — every attack of this shooter is at that single target.
static func attacks_deny_cover(attacker: Dictionary) -> bool:
	return int(_ug(attacker).get("result", 0)) == 5

## Dakka! Dakka! Dakka!: +3" Range for a riled-up ORKS INFANTRY unit's
## ranged weapons (the Range characteristic, so half range follows).
static func range_bonus_inches(actor: Dictionary, weapon_profile: Dictionary = {}) -> float:
	if actor.is_empty() or unit_detachment(actor) != SHOOTA_BOYZ:
		return 0.0
	if not weapon_profile.is_empty():
		var wtype := str(weapon_profile.get("type", "Ranged")).to_lower()
		if wtype == "melee" or str(weapon_profile.get("range", "")).to_lower() == "melee":
			return 0.0
	if group_kw(actor, "ORKS") and group_kw(actor, "INFANTRY") and group_riled_up(actor):
		return 3.0
	return 0.0

# ===========================================================================
# Movement / shooting / charge eligibility (EffectPrimitives / phase hooks)
# ===========================================================================

## [ASSAULT] on every ranged weapon: Dakka! Dakka! Dakka! (ORKS INFANTRY) and
## Adrenaline Junkies (a SPEED FREEKS unit that was selected to advance / fall
## back this turn — "until the end of the turn"). EffectPrimitives
## .has_effect_advance_and_shoot hook.
static func ranged_attacks_have_assault(u: Dictionary) -> bool:
	match unit_detachment(u):
		SHOOTA_BOYZ:
			return group_kw(u, "ORKS") and group_kw(u, "INFANTRY")
		KULT_OF_SPEED:
			if group_kw(u, "SPEED FREEKS"):
				var flags: Dictionary = u.get("flags", {})
				return bool(flags.get("advanced", false)) or bool(flags.get("fell_back", false))
	return false

## "That (advance) move does not prevent that unit from being eligible to
## declare a charge" — Adrenaline Junkies (SPEED FREEKS). Riled up is the
## Waaagh! flag. EffectPrimitives.has_effect_advance_and_charge hook.
static func advance_allows_charge(u: Dictionary) -> bool:
	return unit_detachment(u) == KULT_OF_SPEED and group_kw(u, "SPEED FREEKS")

## Fall back and still charge — Adrenaline Junkies (SPEED FREEKS) and
## Suspiciously Well Organised (BOYZ / KOMMANDOS / STORMBOYZ).
## EffectPrimitives.has_effect_fall_back_and_charge hook.
static func fall_back_allows_charge(u: Dictionary) -> bool:
	match unit_detachment(u):
		KULT_OF_SPEED:
			return group_kw(u, "SPEED FREEKS")
		TAKTIKAL_BRIGADE:
			return group_any_kw(u, ["BOYZ", "KOMMANDOS", "STORMBOYZ"])
	return false

## Sneaky Little Gitz: a GRETCHIN unit's advance / fall-back move does not
## prevent it from being eligible to start an action.
static func move_keeps_action_eligibility(u: Dictionary) -> bool:
	return unit_detachment(u) == RUNT_SWARM and group_kw(u, "GRETCHIN")

## Unstoppable Momentum: "When a friendly WAGON unit is selected to make an
## advance move, that unit can change advance rolls to a 6." Returns 6 when it
## applies (the change is always taken: the roll is a maximum), else 0.
static func advance_roll_override(u: Dictionary) -> int:
	if unit_detachment(u) == BLITZ_BRIGADE and group_kw(u, "WAGON"):
		return 6
	return 0

## Unstoppable Momentum: "Friendly Wagon units can re-roll charge rolls."
static func charge_reroll_source(u: Dictionary) -> String:
	if unit_detachment(u) == BLITZ_BRIGADE and group_kw(u, "WAGON"):
		return "Unstoppable Momentum"
	return ""

## Skyborne Loons: "Friendly Orks Aircraft units do not count towards the
## combined points value of your strategic reserves units."
static func reserves_points_value(u: Dictionary) -> int:
	var pts := int(u.get("meta", {}).get("points", 0))
	if unit_detachment(u) == FLYBOYZ and Common.has_keyword(u, "ORKS") and Common.has_keyword(u, "AIRCRAFT"):
		return 0
	return pts

# ===========================================================================
# 'Ard as Nails (Brute Bosses) — Fight On Death for WARBOSS models
# ===========================================================================

## "When a friendly Warboss model is destroyed, if this unit has not been
## selected to fight this phase, roll one D6 (+1 if riled up): on a 3+, do not
## remove this WARBOSS model..." — FightPhase._ork11e_fod_intercept hook (the
## selected-to-fight gate and the removal live there).
static func ard_as_nails_applies(u: Dictionary) -> bool:
	return unit_detachment(u) == BRUTE_BOSSES and Common.has_keyword(u, "WARBOSS")

static func ard_as_nails_roll_modifier(u: Dictionary) -> Dictionary:
	if group_riled_up(u):
		return {"mod": 1, "note": "+1 riled up"}
	return {"mod": 0, "note": "not riled up"}

# ===========================================================================
# Try Dat Button! (Dread Mob)
# ===========================================================================

static func _tdb(u: Dictionary) -> Dictionary:
	var v = u.get("flags", {}).get(F_TDB, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func try_dat_eligible(u: Dictionary) -> bool:
	return unit_detachment(u) == DREAD_MOB and group_kw(u, "ORKS") and group_kw(u, "WALKER") \
		and not group_kw(u, "TITANIC") and Common.is_on_battlefield(u)

static func _try_dat_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var uid := str(ctx.get("unit_id", ""))
	var u := Common.unit(uid)
	if u.is_empty() or int(u.get("owner", 0)) != player or not try_dat_eligible(u):
		return []
	if window_id == "unit_selected_to_shoot" and Common.active_player() != player:
		return []  # "In your Shooting phase"
	if str(_tdb(u).get("stamp", "")) == _stamp():
		return []  # already rolled for this selection
	var two_hint: String = "two" if _ai_wants_two_dice(u) else "one"
	return [{
		"stratagem_id": RULE_TRY_DAT_BUTTON,
		"name": "TRY DAT BUTTON!",
		"cp_cost": 0,
		"rule": true,
		"type": "Detachment rule — Dread Mob (free)",
		"effect_text": "Roll one D6 or two D6 (duplicate results are re-rolled). This unit's attacks have: 1-2 +1 A; 3-4 +2 S; 5-6 +1 AP. If you rolled two D6, this unit makes one hazard roll when it has attacked.",
		"targets": [{"unit_id": uid, "label": Common.unit_name(uid), "require_variant": true, "ai_variant": two_hint,
			"variants": [
				{"id": "one", "label": "Roll one D6", "cp_cost": 0},
				{"id": "two", "label": "Roll two D6 (then one hazard roll)", "cp_cost": 0},
			]}],
	}]

static func _ai_wants_two_dice(u: Dictionary) -> bool:
	var wounds := 0
	for gu in group_units(u):
		for m in gu.get("models", []):
			if m.get("alive", true):
				wounds += int(m.get("current_wounds", m.get("wounds", 1)))
	# A failed hazard roll costs a VEHICLE 3 mortal wounds (06.03): only roll
	# two dice with a comfortable wound pool.
	return wounds >= 8

## Roll for Try Dat Button!: one die, or two dice re-rolled until they land
## on different table rows ("keep re-rolling duplicate results" — RULINGS).
static func roll_try_dat(two: bool, rng) -> Dictionary:
	var rolls: Array = []
	var rerolls: Array = []
	var first := _d6(rng)
	rolls.append(first)
	if two:
		var second := _d6(rng)
		var guard := 0
		while _tdb_row(second) == _tdb_row(first) and guard < 50:
			rerolls.append(second)
			second = _d6(rng)
			guard += 1
		rolls.append(second)
	var a := 0
	var s := 0
	var ap := 0
	var rows: Array = []
	for r in rolls:
		var row: Dictionary = TRY_DAT_ROWS[_tdb_row(int(r))]
		rows.append(str(row.label))
		a = maxi(a, int(row.a))
		s = maxi(s, int(row.s))
		ap = maxi(ap, int(row.ap))
	return {"rolls": rolls, "rerolled": rerolls, "rows": rows, "a": a, "s": s, "ap": ap, "two": two}

static func _tdb_row(d: int) -> int:
	return clampi(int((d - 1) / 2), 0, 2)

static func _use_try_dat(player: int, unit_id: String, ctx: Dictionary) -> Dictionary:
	var u := Common.unit(unit_id)
	if u.is_empty() or not try_dat_eligible(u) or int(u.get("owner", 0)) != player:
		return {"success": false, "error": "Try Dat Button! cannot be used on %s" % unit_id, "diffs": []}
	var variant := str(ctx.get("variant_id", ""))
	if variant != "one" and variant != "two":
		return {"success": false, "error": "Try Dat Button!: choose one D6 or two D6", "diffs": []}
	var r := roll_try_dat(variant == "two", _rng())
	var phase := _phase_name()
	var value := {"phase": phase, "stamp": _stamp(), "rolls": r.rolls, "rows": r.rows, "a": r.a, "s": r.s, "ap": r.ap, "two": r.two}
	var diffs: Array = []
	for gu in group_units(u):
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gu.get("id", "")), F_TDB], "value": value})
	_apply(diffs)
	var rr_note: String = (" (re-rolled duplicate %s)" % str(r.rerolled)) if not r.rerolled.is_empty() else ""
	var msg := "TRY DAT BUTTON! — %s rolled %s%s: %s%s" % [Common.unit_name(unit_id), str(r.rolls), rr_note, ", ".join(r.rows),
		" — one hazard roll after it has attacked" if r.two else ""]
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Try Dat Button!", "message": msg, "roll": r}

## When the unit has attacked: the two-dice hazard roll, then the effect ends.
static func _finish_try_dat(unit_id: String, reason: String) -> Array:
	var u := Common.unit(unit_id)
	var tdb := _tdb(u)
	if tdb.is_empty():
		return []
	var diffs: Array = []
	var ids: Array = []
	for gu in group_units(u):
		ids.append(str(gu.get("id", "")))
	if bool(tdb.get("two", false)) and reason != "phase_end" and Common.is_alive(u):
		var rng = _rng()
		var hz: Dictionary = AttackSequence.hazard_rolls(u, 1, rng)
		var mw := int(hz.get("mortal_wounds", 0))
		var msg := "TRY DAT BUTTON! — %s makes its hazard roll: %s — %s" % [Common.unit_name(unit_id), str(hz.get("rolls", [])),
			("failed, %d mortal wound%s" % [mw, "" if mw == 1 else "s"]) if mw > 0 else "passed"]
		_log(msg)
		_event(int(u.get("owner", 0)), msg)
		if mw > 0:
			var res := mortal_wounds_to_unit(unit_id, mw, rng)
			diffs.append_array(res.diffs)
	for gid in ids:
		diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [gid, F_TDB]})
	_apply(diffs)
	_log("Try Dat Button! effect on %s ended (%s)" % [unit_id, reason])
	return diffs

# ===========================================================================
# Unpredictable Genius (Madcap Meks)
# ===========================================================================

static func _ug(u: Dictionary) -> Dictionary:
	var v = u.get("flags", {}).get(F_UG, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func ug_eligible(u: Dictionary) -> bool:
	return unit_detachment(u) == MADCAP_MEKS \
		and group_any_kw(u, ["BIG MEK", "MEK GUNZ", "MORKANAUT", "WAZBOM BLASTAJET"])

## Other enemy units within 3" of the Unpredictable Genius target (Hop Splat).
static func hop_splat_options(shooter: Dictionary, target_id: String) -> Array:
	var out: Array = []
	var owner := int(shooter.get("owner", 0))
	var units: Dictionary = Common.state().get("units", {})
	var target_group: Array = Common.attached_group_ids(target_id)
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == owner or str(uid) in target_group:
			continue
		if not Common.is_on_battlefield(u) or str(u.get("attached_to", "")) != "":
			continue  # attached characters are hit through their unit
		if Common.within_inches(str(uid), target_id, 3.0):
			out.append(str(uid))
	out.sort_custom(func(a, b): return Common.unit_distance_inches(a, target_id) < Common.unit_distance_inches(b, target_id))
	return out

## ShootingPhase hook once a shooter's targets are confirmed (CONFIRM_TARGETS /
## the atomic SHOOT). Rolls the D6 when the rule applies and applies the
## result. Returns {applied, result, diffs, hop_splat_options (when the player
## must pick), target}. `ai_pick` resolves Hop Splat immediately (AI / one or
## no candidate).
static func ug_on_targets_confirmed(shooter_id: String, assignments: Array, rng_seed: int = -1, ai_pick: bool = false) -> Dictionary:
	var out := {"applied": false, "result": 0, "diffs": [], "hop_splat_options": [], "target": ""}
	if not enabled():
		return out
	var shooter := Common.unit(shooter_id)
	if shooter.is_empty() or not ug_eligible(shooter):
		return out
	if Common.active_player() != int(shooter.get("owner", 0)):
		return out
	if assignments.is_empty():
		return out
	var target_id := ""
	for a in assignments:
		var tid := str(a.get("target_unit_id", ""))
		if tid == "":
			continue
		if target_id == "":
			target_id = tid
		elif tid != target_id:
			_log("Unpredictable Genius — %s split its attacks over several units: no roll" % shooter_id)
			return out
	if target_id == "":
		return out
	if str(_ug(shooter).get("stamp", "")) == _stamp() and str(_ug(shooter).get("target", "")) == target_id:
		return out  # already rolled for this shooting
	var rng = _rng(rng_seed)
	var roll := _d6(rng)
	out.applied = true
	out.result = roll
	out.target = target_id
	var diffs: Array = []
	var value := {"result": roll, "target": target_id, "stamp": _stamp()}
	diffs.append({"op": "set", "path": "units.%s.flags.%s" % [shooter_id, F_UG], "value": value})
	var target := Common.unit(target_id)
	var tname := Common.unit_name(target_id)
	var msg := "UNPREDICTABLE GENIUS — %s rolled %d: %s" % [Common.unit_name(shooter_id), roll, str(UG_RESULTS.get(roll, ""))]
	if roll == 5:
		var kws: Array = target.get("meta", {}).get("keywords", [])
		if not "FLY" in kws:
			var nk: Array = kws.duplicate()
			nk.append("FLY")
			diffs.append({"op": "set", "path": "units.%s.meta.keywords" % target_id, "value": nk})
			diffs.append({"op": "set", "path": "units.%s.flags.%s" % [target_id, F_UG_LIFTED_BY], "value": shooter_id})
	_apply(diffs)
	out.diffs = diffs
	_log(msg + " (target %s)" % tname)
	_event(int(shooter.get("owner", 0)), msg + " (target: %s)" % tname)
	_toast(msg)
	if roll == 2 or roll == 3:
		var opts := hop_splat_options(shooter, target_id)
		if opts.is_empty():
			_event(int(shooter.get("owner", 0)), "Hop Splat: no other enemy unit within 3\" of %s — no effect" % tname)
		elif opts.size() == 1 or ai_pick or _is_ai(int(shooter.get("owner", 0))):
			var pick: String = opts[0] if opts.size() == 1 else ai_pick_hop_splat(opts)
			out.diffs.append_array(resolve_hop_splat(shooter_id, pick, rng))
		else:
			out.hop_splat_options = opts
	return out

static func _is_ai(player: int) -> bool:
	var ai = Common.autoload("AIPlayer")
	return ai != null and ai.has_method("is_ai_player") and bool(ai.is_ai_player(player))

static func ai_pick_hop_splat(options: Array) -> String:
	# D3 mortal wounds kill most where models have the fewest wounds left.
	var best := ""
	var best_score := -INF
	for uid in options:
		var u := Common.unit(str(uid))
		var w := 99
		for m in u.get("models", []):
			if m.get("alive", true):
				w = mini(w, int(m.get("current_wounds", m.get("wounds", 1))))
		var score := float(Common.points(u)) / maxf(1.0, float(_alive_models(u))) / float(maxi(1, w))
		if score > best_score:
			best_score = score
			best = str(uid)
	return best if best != "" else str(options[0])

## Hop Splat: the chosen unit suffers D3 mortal wounds.
static func resolve_hop_splat(shooter_id: String, victim_id: String, rng = null) -> Array:
	if victim_id == "":
		return []
	if rng == null:
		rng = _rng()
	var d3 := _d3(rng)
	var res := mortal_wounds_to_unit(victim_id, d3, rng)
	_apply(res.diffs)
	var msg := "Hop Splat — %s suffers %d mortal wound%s (%d model%s destroyed)" % [Common.unit_name(victim_id), d3, "" if d3 == 1 else "s",
		int(res.casualties), "" if int(res.casualties) == 1 else "s"]
	_log(msg)
	_event(int(Common.unit(shooter_id).get("owner", 0)), msg)
	_toast(msg)
	return res.diffs

## The Hop Splat choice window (several candidates, human shooter).
static func hop_splat_window_entry(shooter_id: String, target_id: String, options: Array) -> Dictionary:
	var owner := int(Common.unit(shooter_id).get("owner", 0))
	return {"player": owner, "window_id": WINDOW_HOP_SPLAT, "ctx": {"phase": "shooting", "unit_id": shooter_id,
		"target_unit_id": target_id, "hop_splat_options": options,
		"header": "HOP SPLAT! — pick the enemy unit within 3\" of %s that suffers D3 mortal wounds" % Common.unit_name(target_id),
		"decider_prompt": "pick a unit (Decline = the closest)"}}

static func _hop_splat_offers(player: int, ctx: Dictionary) -> Array:
	var shooter_id := str(ctx.get("unit_id", ""))
	if int(Common.unit(shooter_id).get("owner", 0)) != player:
		return []
	var targets: Array = []
	for uid in ctx.get("hop_splat_options", []):
		var u := Common.unit(str(uid))
		if u.is_empty() or not Common.is_alive(u):
			continue
		targets.append({"unit_id": str(uid), "label": "%s (%.1f\")" % [Common.unit_name(str(uid)),
			Common.unit_distance_inches(str(uid), str(ctx.get("target_unit_id", "")))]})
	if targets.is_empty():
		return []
	return [{
		"stratagem_id": RULE_HOP_SPLAT,
		"name": "HOP SPLAT! (Unpredictable Genius)",
		"cp_cost": 0,
		"rule": true,
		"type": "Detachment rule — Madcap Meks",
		"effect_text": "Select one other enemy unit within 3\" of the target. That unit suffers D3 mortal wounds.",
		"targets": targets,
	}]

## Resume of the Hop Splat window: a decline picks the closest candidate.
static func hop_splat_after_window(ctx: Dictionary, window_result: Dictionary) -> Array:
	if bool(window_result.get("used", false)):
		return []
	var opts: Array = ctx.get("hop_splat_options", [])
	if opts.is_empty():
		return []
	var shooter_id := str(ctx.get("unit_id", ""))
	_event(int(Common.unit(shooter_id).get("owner", 0)), "Hop Splat: no unit picked — the closest, %s, is hit" % Common.unit_name(str(opts[0])))
	return resolve_hop_splat(shooter_id, str(opts[0]))

static func _finish_ug(shooter_id: String, reason: String) -> Array:
	var u := Common.unit(shooter_id)
	var ug := _ug(u)
	var diffs: Array = []
	if not ug.is_empty():
		diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [shooter_id, F_UG]})
	var units: Dictionary = Common.state().get("units", {})
	for tid in units:
		var t: Dictionary = units[tid]
		if str(t.get("flags", {}).get(F_UG_LIFTED_BY, "")) != shooter_id:
			continue
		var kws: Array = (t.get("meta", {}).get("keywords", []) as Array).duplicate()
		kws.erase("FLY")
		diffs.append({"op": "set", "path": "units.%s.meta.keywords" % tid, "value": kws})
		diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [tid, F_UG_LIFTED_BY]})
	if not diffs.is_empty():
		_apply(diffs)
		_log("Unpredictable Genius effects of %s ended (%s)" % [shooter_id, reason])
	return diffs

# ===========================================================================
# Wurrband psychic abilities — Roar of Mork / Visions of Violence
# ===========================================================================

static func _wurrband_psykers(player: int) -> Array:
	var out: Array = []
	if detachment_of(player) != WURRBAND:
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		if not (Common.has_keyword(u, "ORKS") and Common.has_keyword(u, "PSYKER")):
			continue
		if not Common.is_on_battlefield(u):
			continue
		out.append(str(uid))
	return out

static func _psyker_blocked(uid: String, ability: String) -> bool:
	var u := Common.unit(uid)
	if group_battle_shocked(u):
		return true  # "if this unit is not battle-shocked"
	var chk: Dictionary = ArmyRules.can_use_psychic(uid, ability)
	if not chk.get("ok", true):
		# Player-facing feedback only for a spent budget — not for the ability
		# the unit has just used this phase (its window is re-offered).
		if str(chk.get("code", "")) == "budget":
			ArmyRules.report_psychic_block(uid, ability, str(chk.get("reason", "")))
		return true
	return false

static func group_battle_shocked(u: Dictionary) -> bool:
	for gu in group_units(u):
		if Common.is_battle_shocked(gu):
			return true
	return false

static func roar_of_mork_targets(psyker_id: String) -> Array:
	var out: Array = []
	var p := Common.unit(psyker_id)
	var owner := int(p.get("owner", 0))
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == owner or not Common.is_on_battlefield(u):
			continue
		if str(u.get("attached_to", "")) != "":
			continue
		if _group_is_mv(u):
			continue
		var d := INF
		for gid in Common.attached_group_ids(psyker_id):
			d = minf(d, Common.unit_distance_inches(str(gid), str(uid)))
		if d <= 12.0 + 0.001:
			out.append(str(uid))
	return out

static func _roar_offers(player: int, ctx: Dictionary) -> Array:
	if Common.active_player() != player:
		return []  # "In your Movement phase"
	var targets: Array = []
	for uid in _wurrband_psykers(player):
		if _psyker_blocked(uid, "Roar of Mork"):
			continue
		var enemies := roar_of_mork_targets(uid)
		if enemies.is_empty():
			continue
		var opts: Array = []
		for eid in enemies:
			opts.append({"id": eid, "label": "%s (%.1f\")" % [Common.unit_name(eid), Common.unit_distance_inches(uid, eid)]})
		targets.append({"unit_id": uid, "label": Common.unit_name(uid),
			"secondary": {"kind": "unit", "prompt": "ROAR OF MORK: select one enemy unit (not MONSTER/VEHICLE) within 12\" — it makes a battle-shock roll", "options": opts}})
	if targets.is_empty():
		return []
	return [{
		"stratagem_id": RULE_ROAR_OF_MORK,
		"name": "ROAR OF MORK (psychic level 1)",
		"cp_cost": 0,
		"rule": true,
		"type": "Wurrband psychic ability (free)",
		"effect_text": "Psychic roll (D6): on a 1 this unit is battle-shocked. Select one enemy unit (excluding MONSTER/VEHICLE) within 12\": it makes a battle-shock roll, -1 for every 10 models in this unit.",
		"targets": targets,
	}]

static func _use_roar(player: int, psyker_id: String, ctx: Dictionary) -> Dictionary:
	var p := Common.unit(psyker_id)
	if p.is_empty() or int(p.get("owner", 0)) != player:
		return {"success": false, "error": "Roar of Mork: unknown psyker %s" % psyker_id, "diffs": []}
	var chk: Dictionary = ArmyRules.can_use_psychic(psyker_id, "Roar of Mork")
	if not chk.get("ok", true):
		return {"success": false, "error": str(chk.get("reason", "")), "diffs": []}
	var enemy_id := str(ctx.get("secondary_id", ""))
	if enemy_id == "" or not enemy_id in roar_of_mork_targets(psyker_id):
		return {"success": false, "error": "Roar of Mork: pick an enemy unit (not MONSTER/VEHICLE) within 12\"", "diffs": []}
	var diffs: Array = ArmyRules.record_psychic_use(psyker_id, "Roar of Mork")
	var rng = _rng()
	var roll := _d6(rng)
	var lines: Array = ["ROAR OF MORK — %s psychic roll: %d" % [Common.unit_name(psyker_id), roll]]
	if roll == 1:
		diffs.append_array(_battle_shock_diffs(p))
		lines.append("on a 1 %s is battle-shocked" % Common.unit_name(psyker_id))
	_apply(diffs)
	var models := _group_alive_models(p)
	var mod := -int(models / 10)
	var fam = Common.autoload("FactionAbilityManager")
	var cp = load("res://phases/CommandPhase.gd")
	var e := Common.unit(enemy_id)
	var immune: bool = cp != null and bool(cp._has_battle_shock_immunity(e.get("meta", {}).get("keywords", []), e.get("meta", {}).get("abilities", [])))
	if immune:
		lines.append("%s is immune to battle-shock" % Common.unit_name(enemy_id))
	elif fam and fam.has_method("force_battle_shock_test"):
		var r: Dictionary = fam.force_battle_shock_test(enemy_id, mod, "Roar of Mork")
		diffs.append_array(r.get("diffs", []))
		lines.append("%s battle-shock roll %s%s = %d vs Ld %d: %s" % [Common.unit_name(enemy_id), str(r.get("dice", [])),
			(" %d (%d models)" % [mod, models]) if mod != 0 else "", int(r.get("total", 0)), int(r.get("leadership", 0)),
			"passed" if r.get("passed", true) else "FAILED — battle-shocked"])
	var msg := "; ".join(lines)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Roar of Mork", "message": msg}

static func fight_start_window_entries(active_player: int) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var other := 2 if active_player == 1 else 1
	for p in [active_player, other]:
		if _wurrband_psykers(p).is_empty():
			continue
		out.append({"player": p, "window_id": WINDOW_FIGHT_START, "ctx": {"phase": "fight",
			"header": "Start of the Fight phase — Visions of Violence?", "decider_prompt": "use a psychic ability?"}})
	return out

static func _visions_offers(player: int, _ctx: Dictionary) -> Array:
	var targets: Array = []
	for uid in _wurrband_psykers(player):
		if _psyker_blocked(uid, "Visions of Violence"):
			continue
		if bool(Common.unit(uid).get("flags", {}).get(F_VISIONS_FF, false)):
			continue
		targets.append({"unit_id": uid, "label": Common.unit_name(uid)})
	if targets.is_empty():
		return []
	return [{
		"stratagem_id": RULE_VISIONS,
		"name": "VISIONS OF VIOLENCE (psychic level 1)",
		"cp_cost": 0,
		"rule": true,
		"type": "Wurrband psychic ability (free)",
		"effect_text": "Psychic roll (D6): on a 1 this unit is battle-shocked. This unit has Fights First.",
		"targets": targets,
	}]

static func _use_visions(player: int, psyker_id: String) -> Dictionary:
	var p := Common.unit(psyker_id)
	if p.is_empty() or int(p.get("owner", 0)) != player:
		return {"success": false, "error": "Visions of Violence: unknown psyker %s" % psyker_id, "diffs": []}
	var chk: Dictionary = ArmyRules.can_use_psychic(psyker_id, "Visions of Violence")
	if not chk.get("ok", true):
		return {"success": false, "error": str(chk.get("reason", "")), "diffs": []}
	var diffs: Array = ArmyRules.record_psychic_use(psyker_id, "Visions of Violence")
	var roll := _d6(_rng())
	var lines: Array = ["VISIONS OF VIOLENCE — %s psychic roll: %d" % [Common.unit_name(psyker_id), roll]]
	if roll == 1:
		diffs.append_array(_battle_shock_diffs(p))
		lines.append("on a 1 it is battle-shocked")
	for gu in group_units(p):
		var gid := str(gu.get("id", ""))
		if not bool(gu.get("flags", {}).get("fights_first", false)):
			diffs.append({"op": "set", "path": "units.%s.flags.fights_first" % gid, "value": true})
			diffs.append({"op": "set", "path": "units.%s.flags.%s" % [gid, F_VISIONS_FF], "value": true})
	lines.append("%s has Fights First this phase" % Common.unit_name(psyker_id))
	_apply(diffs)
	var msg := "; ".join(lines)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Visions of Violence", "message": msg}

# ===========================================================================
# Rule offers — StratagemManager / BasePhase / AIDecisionMaker hooks
# ===========================================================================

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

## StratagemManager.get_window_offers hook: the free rule choices for this window.
static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	if not enabled():
		return []
	match window_id:
		"unit_selected_to_shoot", "unit_selected_to_fight":
			return _try_dat_offers(player, window_id, ctx)
		"movement_phase_end":
			return _roar_offers(player, ctx)
		WINDOW_FIGHT_START:
			return _visions_offers(player, ctx)
		WINDOW_HOP_SPLAT:
			return _hop_splat_offers(player, ctx)
		ArmyRules.WINDOW_WAR_CRY:
			return ArmyRules.war_cry_offers(player, window_id, ctx)
	return []

## StratagemManager.use_stratagem hook for a rule offer: no CP, no stratagem
## bookkeeping. reopen_window = BasePhase re-offers the window afterwards so
## its stratagems are still available (a rule choice is not a stratagem use).
static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var res: Dictionary
	match sid:
		RULE_TRY_DAT_BUTTON:
			res = _use_try_dat(player, target_unit_id, ctx)
		RULE_ROAR_OF_MORK:
			res = _use_roar(player, target_unit_id, ctx)
		RULE_VISIONS:
			res = _use_visions(player, target_unit_id)
		RULE_HOP_SPLAT:
			var shooter_id := str(ctx.get("unit_id", ""))
			if not target_unit_id in ctx.get("hop_splat_options", []):
				res = {"success": false, "error": "Hop Splat: %s is not within 3\" of the target" % target_unit_id, "diffs": []}
			else:
				res = {"success": true, "diffs": resolve_hop_splat(shooter_id, target_unit_id), "stratagem_name": "Hop Splat!"}
		ArmyRules.RULE_WAR_CRY:
			res = ArmyRules.use_war_cry(player)
		_:
			res = {"success": false, "error": "unknown Codex: Orks rule offer %s" % sid, "diffs": []}
	if res.get("success", false):
		res["reopen_window"] = true
		res["rule_use"] = true
	return res

## AIDecisionMaker.decide_window_stratagem hook: the AI answers rule offers
## first (they are free); {} = no rule offer worth using (the AI then weighs
## the window's stratagems). Never stalls: always synchronous.
static func ai_decide(player: int, window_id: String, offers: Array, _ctx: Dictionary) -> Dictionary:
	for offer in offers:
		var sid := str(offer.get("stratagem_id", ""))
		if not is_rule_offer_id(sid):
			continue
		var targets: Array = offer.get("targets", [])
		if targets.is_empty():
			continue
		match sid:
			RULE_TRY_DAT_BUTTON:
				var t: Dictionary = targets[0]
				return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.get("unit_id", "")),
					"context": {"variant_id": str(t.get("ai_variant", "one"))}, "name": str(offer.get("name", sid))}
			RULE_HOP_SPLAT:
				var ids: Array = targets.map(func(x): return str(x.get("unit_id", "")))
				return {"use": true, "stratagem_id": sid, "target_unit_id": ai_pick_hop_splat(ids), "context": {}, "name": str(offer.get("name", sid))}
			RULE_ROAR_OF_MORK:
				for t in targets:
					var opts: Array = t.get("secondary", {}).get("options", [])
					var pick := _ai_roar_pick(opts)
					if pick != "":
						return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.get("unit_id", "")),
							"context": {"secondary_id": pick}, "name": str(offer.get("name", sid))}
			RULE_VISIONS:
				for t in targets:
					var uid := str(t.get("unit_id", ""))
					if _ai_visions_worth_it(uid):
						return {"use": true, "stratagem_id": sid, "target_unit_id": uid, "context": {}, "name": str(offer.get("name", sid))}
			ArmyRules.RULE_WAR_CRY:
				pass  # the AI calls its Waaagh! in its own Command phase (AIDecisionMaker)
	return {}

static func _ai_roar_pick(options: Array) -> String:
	var best := ""
	var best_score := -1.0
	for o in options:
		var eid := str(o.get("id", ""))
		var e := Common.unit(eid)
		if e.is_empty() or group_battle_shocked(e):
			continue
		var score := float(Common.points(e)) + 1.0
		if score > best_score:
			best_score = score
			best = eid
	return best

static func _ai_visions_worth_it(uid: String) -> bool:
	for gid in Common.attached_group_ids(uid):
		if Common.is_engaged(str(gid)):
			return true
	return false

## Strip rule offers from a list (AI stratagem scoring keeps to real ones).
static func is_rule_offer(offer: Dictionary) -> bool:
	return bool(offer.get("rule", false)) or is_rule_offer_id(str(offer.get("stratagem_id", "")))

# ===========================================================================
# Lifecycle hooks
# ===========================================================================

## ShootingPhase post-shot hook: "when this unit has attacked" — Try Dat
## Button!'s two-dice hazard roll, then its effects and Unpredictable Genius's
## ("until your unit has shot") end. Applied here; returns the diffs.
static func on_unit_has_shot(unit_id: String) -> Array:
	if not enabled():
		return []
	var diffs: Array = []
	diffs.append_array(_finish_try_dat(unit_id, "has shot"))
	diffs.append_array(_finish_ug(unit_id, "has shot"))
	return diffs

## FightPhase activation-end hook ("when this unit has fought").
static func on_unit_has_fought(unit_id: String) -> Array:
	if not enabled():
		return []
	return _finish_try_dat(unit_id, "has fought")

## Phase exit hook: nothing outlives its phase (no hazard roll for a unit that
## never attacked).
static func on_phase_end(phase_name: String) -> void:
	if not enabled():
		return
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		var flags: Dictionary = u.get("flags", {})
		if flags.has(F_TDB):
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_TDB]})
		if phase_name == "shooting" and flags.has(F_UG):
			diffs.append_array(_finish_ug(str(uid), "end of the Shooting phase"))
		if phase_name == "fight" and flags.get(F_VISIONS_FF, false):
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_VISIONS_FF]})
			if not flags.get("charged_this_turn", false):
				diffs.append({"op": "remove", "path": "units.%s.flags.fights_first" % uid})
		if phase_name == "fight" and str(flags.get("ork11e_fod_source", "")) == "'Ard as Nails":
			diffs.append({"op": "remove", "path": "units.%s.flags.ork11e_fod_source" % uid})
	if not diffs.is_empty():
		_apply(diffs)
		_log("end of the %s phase: %d leftover rule flag op(s) cleared" % [phase_name, diffs.size()])
