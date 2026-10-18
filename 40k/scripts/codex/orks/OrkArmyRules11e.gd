extends RefCounted

## OrkArmyRules11e — Codex: Orks (11th edition) army rules (WP-O34, plan O3).
##
## Source of truth: .llm/codex_11e_wahapedia/orks/RULES.md ("Army rules").
## Contract: .llm/codex_11e_wahapedia/IMPLEMENTATION.md. Engine files only call
## the static functions below from thin, commented hooks; every rule decision
## lives here.
##
##  - WAAAGH!  "Friendly ORKS units with this ability can: Re-roll advance rolls.
##    Become riled up ... While a unit is riled up: 5+ InSv; ranged attacks have
##    [ASSAULT]; an advance move does not prevent it from declaring a charge.
##    War Cry (Once per battle, per army): At the start of the Command phase,
##    you can use this ability. If you do, friendly ORKS units with the Waaagh!
##    ability are riled up until the end of the next turn."
##    The riled-up flags themselves are written by
##    FactionAbilityManager._apply_waaagh_effects (PR #917). This module adds:
##      * the free, optional advance re-roll (MovementPhase re-roll dialog),
##      * War Cry in EITHER player's Command phase ("the Command phase", not
##        "your") — the opponent's is offered as a rule window,
##      * the "until the end of the next turn" expiry.
##  - DA BOSS  "At the start of the battle round, if a model with this ability
##    is your WARLORD, gain 1CP."
##  - UNSTABLE ENERGIES  psyker level budget per battle round for ORKS PSYKER
##    units; enforced on every psychic-ability path the game implements (Da
##    Jump, Roar of Mork, Visions of Violence). WP-O6 calls can_use_psychic /
##    record_psychic_use for the datasheet powers it adds (Warpath, Beastscent).
##
## Every autoload is reached late-bound through OrkCodexCommon (see its header).

const Common = preload("res://scripts/stratagems/ork_codex/OrkCodexCommon.gd")

# ---------------------------------------------------------------------------
# Ids / state keys
# ---------------------------------------------------------------------------

## Rule offer id (rides the stratagem-window framework, never a real stratagem).
const RULE_WAR_CRY := "ork11e_rule_war_cry"
## Rule-only window opened for the NON-active player in the opponent's Command phase.
const WINDOW_WAR_CRY := "ork11e_war_cry"

## players.<p>.<key>: the turn index whose END the War Cry lasts until.
const P_WAR_CRY_UNTIL := "ork11e_war_cry_until_turn"
## players.<p>.<key>: battle round in which Da Boss last granted its CP.
const P_DA_BOSS_ROUND := "ork11e_da_boss_round"

## Unstable Energies bookkeeping on the PSYKER unit (the unit that carries the
## psyker-level ability — an attached Weirdboy keeps its own unit id).
const F_PSY_ROUND := "ork11e_psy_round"              # battle round of F_PSY_USED
const F_PSY_USED := "ork11e_psy_used"                # psychic levels used that round
const F_PSY_PHASE := "ork11e_psy_phase"              # phase stamp of F_PSY_PHASE_NAMES
const F_PSY_PHASE_NAMES := "ork11e_psy_phase_names"  # abilities used in that phase (22.03.01)
## Optional override other packages may write (e.g. WP-O5's Warphead: "Has
## psyker level 2"); the highest of override and datasheet level is used.
const F_PSYKER_LEVEL_OVERRIDE := "ork11e_psyker_level"

## Psyker level of the datasheet abilities that grant one (the army files drop
## the "(psyker level N)" suffix the codex prints, so the codex value is kept
## here; a name/description that still carries the suffix wins).
const PSYKER_LEVEL_ABILITIES := {"waaagh! energy": 1, "wurrboy": 1}
## Psychic level of every Ork psychic ability (codex: "(psychic level 1...)").
const PSYCHIC_ABILITY_LEVELS := {
	"da jump": 1,
	"warpath": 1,
	"beastscent": 1,
	"roar of mork": 1,
	"visions of violence": 1,
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

static func enabled() -> bool:
	return GameConstants.edition >= 11

static func _fam() -> Node:
	return Common.autoload("FactionAbilityManager")

static func _gel() -> Node:
	return Common.autoload("GameEventLog")

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

static func ability_names(u: Dictionary) -> Array:
	var out: Array = []
	for ab in u.get("meta", {}).get("abilities", []):
		var n := ""
		if ab is String:
			n = ab
		elif ab is Dictionary:
			n = str(ab.get("name", ""))
		if n != "":
			out.append(n)
	return out

static func has_ability(u: Dictionary, name: String) -> bool:
	var want := name.to_lower()
	for n in ability_names(u):
		var nl := str(n).to_lower()
		if nl == want or nl.begins_with(want + " ("):
			return true
	return false

## The unit plus its Attached unit components (dicts), from `board` when given.
static func group_units(unit_id: String, board: Dictionary = {}) -> Array:
	var units: Dictionary = board.get("units", {}) if not board.is_empty() else Common.state().get("units", {})
	var out: Array = []
	for gid in Common.attached_group_ids(unit_id):
		var u = units.get(str(gid), {})
		if not u.is_empty():
			out.append(u)
	return out

static func _tutorial_active() -> bool:
	var tm = Common.autoload("TutorialManager")
	if tm != null and "active" in tm and bool(tm.active):
		return true
	return bool(Common.state().get("meta", {}).get("tutorial", false))

static func battle_round() -> int:
	return int(Common.state().get("meta", {}).get("battle_round", 1))

## 0-based index of the current player turn: battle round 1 first turn = 0.
static func turn_index() -> int:
	var meta: Dictionary = Common.state().get("meta", {})
	var rnd := int(meta.get("battle_round", 1))
	var active := int(meta.get("active_player", 1))
	var first := int(meta.get("first_turn_player", 1))
	var gs = Common.game_state()
	if gs and gs.has_method("get_first_turn_player"):
		first = int(gs.get_first_turn_player())
	return (maxi(rnd, 1) - 1) * 2 + (0 if active == first else 1)

static func _player_dict(player: int) -> Dictionary:
	return Common.state().get("players", {}).get(str(player), {})

# ===========================================================================
# WAAAGH! — free advance re-roll
# ===========================================================================

## "Friendly ORKS units with this ability can: Re-roll advance rolls." Returns
## the ability name to brand the free re-roll with ("" = not offered). The
## whole Attached unit counts (an attached Warboss lends it to its unit).
## Not offered while a tutorial lesson runs (scripted lessons, like stratagem
## windows, keep their taught flow — the T3 lesson teaches Command Re-roll).
static func free_advance_reroll_source(unit: Dictionary) -> String:
	if not enabled() or unit.is_empty():
		return ""
	if _tutorial_active():
		return ""
	var uid := str(unit.get("id", ""))
	var comps: Array = group_units(uid) if uid != "" else [unit]
	if comps.is_empty():
		comps = [unit]
	for u in comps:
		if Common.has_keyword(u, "ORKS") and has_ability(u, "Waaagh!"):
			return "Waaagh!"
	return ""

## AI policy for the free advance re-roll: re-roll a 1-3 (expected value 3.5).
static func ai_take_free_advance_reroll(roll_total: int) -> bool:
	return roll_total <= 3

# ===========================================================================
# WAAAGH! — War Cry (either player's Command phase, until the end of the next turn)
# ===========================================================================

## FactionAbilityManager.activate_waaagh hook: record "riled up until the end
## of the next turn" (the turn after the one whose Command phase it is).
static func on_war_cry_used(player: int) -> Array:
	if not enabled():
		return []
	var until := turn_index() + 1
	var pd = Common.state().get("players", {}).get(str(player), null)
	if pd is Dictionary:
		pd[P_WAR_CRY_UNTIL] = until
	Common.log_info("OrkArmyRules11e: War Cry — Player %d's Waaagh! units are riled up until the end of turn #%d (now turn #%d)" % [player, until, turn_index()])
	return [{"op": "set", "path": "players.%d.%s" % [player, P_WAR_CRY_UNTIL], "value": until}]

## Start of every Command phase (FactionAbilityManager.on_command_phase_start
## hook): end each player's War Cry whose "next turn" is over. A Waaagh! with
## no recorded expiry (a pre-WP-O34 save) keeps the old behaviour: it ends at
## the start of its owner's next Command phase.
static func expire_war_cry_if_due() -> void:
	if not enabled():
		return
	var fam = _fam()
	if fam == null:
		return
	var now := turn_index()
	var active := Common.active_player()
	for p in [1, 2]:
		if not fam.is_waaagh_active(p):
			continue
		var pd := _player_dict(p)
		var until := int(pd.get(P_WAR_CRY_UNTIL, -1))
		var due: bool = (now > until) if until >= 0 else (p == active)
		if not due:
			Common.log_info("OrkArmyRules11e: War Cry — Player %d stays riled up (lasts until the end of turn #%d, now turn #%d)" % [p, until, now])
			continue
		fam.deactivate_waaagh(p)
		var live = Common.state().get("players", {}).get(str(p), null)
		if live is Dictionary:
			live.erase(P_WAR_CRY_UNTIL)
		Common.log_info("OrkArmyRules11e: War Cry — Player %d's riled-up state ended (the next turn is over)" % p)
		var gel = _gel()
		if gel:
			gel.add_player_entry(p, "War Cry ends — Waaagh! units are no longer riled up")

## True when `player` can use War Cry now (has the Waaagh!, not used, not active).
static func war_cry_available(player: int) -> bool:
	if not enabled():
		return false
	var fam = _fam()
	if fam == null:
		return false
	if fam.has_method("detect_faction_abilities"):
		fam.detect_faction_abilities(player)
	return bool(fam.is_waaagh_available(player))

## CommandPhase hook (start of the Battle-shock step queue): the NON-active
## player's War Cry window — "At the start of the Command phase" is not "your".
static func war_cry_window_entries(active_player: int) -> Array:
	var other := 2 if active_player == 1 else 1
	if _tutorial_active():
		return []  # scripted lessons keep their taught flow (as for the free advance re-roll)
	if not war_cry_available(other):
		return []
	return [{"player": other, "window_id": WINDOW_WAR_CRY, "ctx": {"phase": "command",
		"header": "Start of Player %d's Command phase — WAR CRY?" % active_player,
		"decider_prompt": "use War Cry?"}}]

static func war_cry_offers(player: int, window_id: String, _ctx: Dictionary) -> Array:
	if window_id != WINDOW_WAR_CRY or not war_cry_available(player):
		return []
	return [{
		"stratagem_id": RULE_WAR_CRY,
		"name": "WAR CRY (Waaagh!)",
		"cp_cost": 0,
		"rule": true,
		"type": "Army rule — Waaagh! (once per battle, per army)",
		"effect_text": "Friendly ORKS units with the Waaagh! ability are riled up until the end of the next turn: 5+ invulnerable save, ranged attacks have [ASSAULT], an advance move does not prevent declaring a charge.",
		"targets": [{"unit_id": "", "label": "Use War Cry"}],
	}]

static func use_war_cry(player: int) -> Dictionary:
	var fam = _fam()
	if fam == null:
		return {"success": false, "error": "FactionAbilityManager unavailable", "diffs": []}
	if not war_cry_available(player):
		return {"success": false, "error": "War Cry is not available for Player %d" % player, "diffs": []}
	var res: Dictionary = fam.activate_waaagh(player)
	if not res.get("success", false):
		return {"success": false, "error": str(res.get("error", "War Cry failed")), "diffs": []}
	# activate_waaagh writes the riled-up flags in place; mirror them as diffs
	# so replay / a network client converge (set ops are idempotent).
	var diffs: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not u.get("flags", {}).get("waaagh_active", false):
			continue
		for f in ["waaagh_active", "effect_invuln", "effect_invuln_source", "effect_advance_and_charge",
				"effect_advance_and_shoot", "waaagh_assault_granted"]:
			if u.flags.has(f):
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, f], "value": u.flags[f]})
	var until := int(_player_dict(player).get(P_WAR_CRY_UNTIL, turn_index() + 1))
	diffs.append({"op": "set", "path": "players.%d.%s" % [player, P_WAR_CRY_UNTIL], "value": until})
	var msg := "WAR CRY — Player %d's Waaagh! units are riled up until the end of the next turn (called in the opponent's Command phase)" % player
	Common.log_info("OrkArmyRules11e: " + msg)
	var gel = _gel()
	if gel:
		gel.add_player_entry(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "War Cry", "message": msg}

# ===========================================================================
# DA BOSS — +1CP at the start of the battle round when the WARLORD has it
# ===========================================================================

## The player's WARLORD carrying Da Boss: {unit_id, name} or {}. The warlord
## must still be alive (a destroyed model's abilities are not in play); it can
## be on the battlefield, embarked or in reserves.
static func da_boss_warlord(player: int) -> Dictionary:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		if not bool(u.get("meta", {}).get("is_warlord", false)):
			continue
		if not has_ability(u, "Da Boss") or not Common.is_alive(u):
			continue
		return {"unit_id": str(uid), "name": Common.unit_name(str(uid))}
	return {}

## CommandPhase hook at the start of the battle round (the first-turn player's
## Command phase entry). Grants each qualifying player +1CP once per round and
## returns the applied diffs. Not subject to the engine's 10e-era "1 bonus CP
## per battle round" cap: the 11e core rules have no such cap (RULINGS).
static func on_battle_round_start(round_no: int) -> Array:
	var diffs: Array = []
	if not enabled():
		return diffs
	for p in [1, 2]:
		var info := da_boss_warlord(p)
		if info.is_empty():
			continue
		var pd := _player_dict(p)
		if int(pd.get(P_DA_BOSS_ROUND, 0)) == round_no:
			Common.log_info("OrkArmyRules11e: Da Boss — Player %d already gained its CP in battle round %d" % [p, round_no])
			continue
		var cp := int(pd.get("cp", 0))
		var d := [
			{"op": "set", "path": "players.%d.cp" % p, "value": cp + 1},
			{"op": "set", "path": "players.%d.%s" % [p, P_DA_BOSS_ROUND], "value": round_no},
		]
		_apply(d)
		diffs.append_array(d)
		var msg := "Da Boss: %s is your Warlord — +1 CP (start of battle round %d, %d -> %d CP)" % [info.name, round_no, cp, cp + 1]
		Common.log_info("OrkArmyRules11e: Player %d %s" % [p, msg])
		var gel = _gel()
		if gel:
			gel.add_player_entry(p, msg)
	return diffs

# ===========================================================================
# UNSTABLE ENERGIES — psyker level budget per battle round
# ===========================================================================

static func _level_from_text(text: String, word: String) -> int:
	var re := RegEx.new()
	re.compile("(?i)" + word + "\\s+level\\s+(\\d+)")
	var m := re.search(text)
	return int(m.get_string(1)) if m else 0

## An ORKS PSYKER unit with the Unstable Energies ability (its psyker level is
## budgeted); other units are not limited by this rule.
static func is_budgeted_psyker(u: Dictionary) -> bool:
	return enabled() and Common.has_keyword(u, "ORKS") and Common.has_keyword(u, "PSYKER") \
		and has_ability(u, "Unstable Energies")

## Psyker level "specified in that unit's abilities" (codex: Waaagh! Energy /
## Wurrboy "(psyker level 1)"). 0 for a unit without one.
static func psyker_level(u: Dictionary) -> int:
	var level := 0
	# Only ability NAMES carry the level ("Waaagh! Energy (psyker level 1)");
	# descriptions are never parsed (Unstable Energies' own text has a "psyker
	# level 3" example).
	for ab in u.get("meta", {}).get("abilities", []):
		var n := ""
		if ab is String:
			n = ab
		elif ab is Dictionary:
			n = str(ab.get("name", ""))
		var from_name := _level_from_text(n, "psyker")
		if from_name > 0:
			level = maxi(level, from_name)
			continue
		var base := n.to_lower().split(" (")[0].strip_edges()
		if PSYKER_LEVEL_ABILITIES.has(base):
			level = maxi(level, int(PSYKER_LEVEL_ABILITIES[base]))
	level = maxi(level, int(u.get("flags", {}).get(F_PSYKER_LEVEL_OVERRIDE, 0)))
	if level == 0 and is_budgeted_psyker(u):
		level = 1  # "a psyker level of 1 or higher"
	return level

## Psychic level of an ability ("specified in that ability's name").
static func psychic_level(ability_name: String) -> int:
	var from_name := _level_from_text(ability_name, "psychic")
	if from_name > 0:
		return from_name
	var base := ability_name.to_lower().split(" (")[0].strip_edges()
	return int(PSYCHIC_ABILITY_LEVELS.get(base, 1))

static func _phase_stamp() -> String:
	var meta: Dictionary = Common.state().get("meta", {})
	return "%d:%d:%d" % [int(meta.get("battle_round", 1)), int(meta.get("active_player", 1)), int(meta.get("phase", -1))]

## Psychic levels this unit has used in the current battle round.
static func psychic_levels_used(u: Dictionary) -> int:
	var flags: Dictionary = u.get("flags", {})
	if int(flags.get(F_PSY_ROUND, -1)) != battle_round():
		return 0  # a new battle round resets the budget
	return int(flags.get(F_PSY_USED, 0))

## Can `unit_id` use psychic ability `ability_name` now? {ok, reason, level,
## used, cost}. Units outside the budget (non-PSYKER, 10e) are always ok here.
static func can_use_psychic(unit_id: String, ability_name: String) -> Dictionary:
	var u := Common.unit(unit_id)
	var cost := psychic_level(ability_name)
	if u.is_empty() or not is_budgeted_psyker(u):
		return {"ok": true, "reason": "", "level": 0, "used": 0, "cost": cost}
	var level := psyker_level(u)
	var used := psychic_levels_used(u)
	var flags: Dictionary = u.get("flags", {})
	var base := ability_name.split(" (")[0].strip_edges()
	if str(flags.get(F_PSY_PHASE, "")) == _phase_stamp() and base in flags.get(F_PSY_PHASE_NAMES, []):
		return {"ok": false, "level": level, "used": used, "cost": cost, "code": "same_phase",
			"reason": "%s has already used %s this phase (22.03.01)" % [Common.unit_name(unit_id), base]}
	if used + cost > level:
		return {"ok": false, "level": level, "used": used, "cost": cost, "code": "budget",
			"reason": "Unstable Energies: %s (psyker level %d) has used %d psychic level%s this battle round — %s (psychic level %d) would exceed it" % [
				Common.unit_name(unit_id), level, used, "" if used == 1 else "s", base, cost]}
	return {"ok": true, "reason": "", "level": level, "used": used, "cost": cost}

## Diffs recording that `unit_id` used `ability_name` (budget + 22.03.01).
## Applied by the caller with the rest of the ability's diffs.
static func record_psychic_use(unit_id: String, ability_name: String) -> Array:
	var u := Common.unit(unit_id)
	if u.is_empty() or not is_budgeted_psyker(u):
		return []
	var cost := psychic_level(ability_name)
	var used := psychic_levels_used(u) + cost
	var flags: Dictionary = u.get("flags", {})
	var stamp := _phase_stamp()
	var names: Array = []
	if str(flags.get(F_PSY_PHASE, "")) == stamp:
		names = (flags.get(F_PSY_PHASE_NAMES, []) as Array).duplicate()
	names.append(ability_name.split(" (")[0].strip_edges())
	Common.log_info("OrkArmyRules11e: Unstable Energies — %s used %s (psychic level %d): %d/%d psyker level spent this battle round" % [
		unit_id, ability_name, cost, used, psyker_level(u)])
	return [
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_ROUND], "value": battle_round()},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_USED], "value": used},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE], "value": stamp},
		{"op": "set", "path": "units.%s.flags.%s" % [unit_id, F_PSY_PHASE_NAMES], "value": names},
	]

static var _reported_blocks: Dictionary = {}

## Player-facing feedback when the budget (or 22.03.01) stops a psychic
## ability the unit could otherwise use: one Game Log line + toast per unit /
## ability / phase.
static func report_psychic_block(unit_id: String, ability_name: String, reason: String) -> void:
	var key := "%s|%s|%s" % [unit_id, ability_name, _phase_stamp()]
	if _reported_blocks.has(key):
		return
	_reported_blocks[key] = true
	var owner := int(Common.unit(unit_id).get("owner", 0))
	Common.log_info("OrkArmyRules11e: %s — %s not available: %s" % [unit_id, ability_name, reason])
	var gel = _gel()
	if gel:
		gel.add_player_entry(owner, "%s — %s unavailable" % [reason, ability_name])
	_toast("%s" % reason, Color(1.0, 0.6, 0.3))
