extends RefCounted

## SWArmyRules11e — Codex: Space Marines (11e), Space Wolves ARMY RULES (WP-S2).
##
## Source: .llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md ("Army
## rules"). Plan: PLAN_SPACE_WOLVES.md; contract: IMPLEMENTATION.md; rulings:
## RULINGS.md § WP-S2. Every rule here gates on SWCommon.is_sw_army(player)
## (11e and a Space Wolves army) — other Space Marine armies keep their index
## rules (Oath of Moment, the 10e Gladius doctrines in FactionAbilityManager).
##
##  COMBAT DOCTRINES (army rule; the state API is documented in SWCommon)
##   - Selection: in YOUR Command phase (offered from its start until you pick
##     one or skip — CommandPhase SELECT_COMBAT_DOCTRINE / SKIP_COMBAT_DOCTRINE,
##     the "COMBAT DOCTRINES" block of the Command panel, AI ai_command_action).
##     Writes state.factions[p].sw11e_doctrine; active for friendly units with
##     the ability until the start of p's next Command phase
##     (on_command_phase_start clears it, plus the per-unit doctrine flags
##     whose sw11e_doctrine_expires_player is p).
##   - Each doctrine once per battle (sw11e_doctrines_used = {doctrine: n}).
##     Gladius Task Force (also taken by the army) — CODEX DISCIPLINE: one
##     doctrine may be selected one additional time (doctrine_limit()).
##   - Effects (read through SWCommon.active_doctrines, so the per-unit keys
##     S3 / S4 write — Grimnar's Command, Guile of the Wolf — work too):
##       ASSAULT     advance_allows_charge()  (EffectPrimitives hook)
##       DEVASTATOR  ranged_attacks_have_assault() (EffectPrimitives
##                   has_effect_advance_and_shoot + AssaultShooting hooks)
##       TACTICAL    fall_back_allows_shoot() / fall_back_allows_charge()
##   - An Attached unit is ONE unit: the doctrines of every component count
##     (group_doctrines) — so Logan Grimnar's Guile of the Wolf covers the
##     unit he leads.
##  TRANSHUMAN STRATEGIST — start of the battle round, +1CP if your WARLORD
##   has it: on_battle_round_start() (CommandPhase hook, like Aquila Commander).
##  CURSE OF THE WULFEN — OC aura oc_bonus() (MissionManager hook); Bestial
##   Forms transport_space_per_model() (TransportManager hook).
##  SONS OF RUSS — army validation validate_army() (ArmyListManager hook) and
##   the in-game warning on the Game Log (report_army_problems, FormationsPhase).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")

const ABILITY_DOCTRINES := "Combat Doctrines"
const ABILITY_TRANSHUMAN := "Transhuman Strategist"
const ABILITY_CURSE := "Curse of the Wulfen"
const GLADIUS := "gladius task force"

## state.factions[p] keys (doctrine state is documented in SWCommon).
const FK_DOCTRINE := "sw11e_doctrine"
const FK_USED := "sw11e_doctrines_used"
## Battle round in which p decided (selected or skipped) this Command phase's
## doctrine — the selection is offered once per Command phase.
const FK_DECIDED_ROUND := "sw11e_doctrine_decided_round"
## Doctrine selection history [{round, doctrine}] (Game Log / tests).
const FK_HISTORY := "sw11e_doctrine_history"

## Per-unit doctrine keys (SWCommon) — cleared here at their expiry.
const F_UNIT_DOCTRINE := "sw11e_doctrine"
const F_UNIT_DOCTRINE_EXPIRES := "sw11e_doctrine_expires_player"

## Transhuman Strategist resolved this battle round (on the WARLORD).
const F_TRANSHUMAN_ROUND := "sw11e_transhuman_round"

const CURSE_CHARACTER_RANGE_IN := 6.0
const CURSE_WOLF_PRIEST_RANGE_IN := 12.0

const DOCTRINE_TEXT := {
	"assault": "When this unit is selected to make an advance move, that advance move does not prevent this unit from being eligible to declare a charge.",
	"devastator": "This unit's ranged attacks have [ASSAULT].",
	"tactical": "When this unit is selected to make a fall-back move, that fall-back move does not prevent this unit from being eligible to shoot and eligible to declare a charge.",
}
const DOCTRINE_SHORT := {
	"assault": "advance and still charge",
	"devastator": "ranged attacks have [ASSAULT]",
	"tactical": "fall back and still shoot and charge",
}

## Apothecary keyword (Sons of Russ) and the Adeptus Astartes chapter
## keywords other than SPACE WOLVES (Master of Wolves restriction, read by
## SWDetachments11e through chapter_keyword()).
const KW_APOTHECARY := "APOTHECARY"
const OTHER_CHAPTERS := ["BLOOD ANGELS", "DARK ANGELS", "BLACK TEMPLARS", "DEATHWATCH", "ULTRAMARINES",
	"IMPERIAL FISTS", "WHITE SCARS", "RAVEN GUARD", "SALAMANDERS", "IRON HANDS", "CRIMSON FISTS"]

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func _log(msg: String) -> void:
	Common.log_info("[SWArmyRules11e] " + msg)

static func _faction(player: int) -> Dictionary:
	var f = Common.state().get("factions", {}).get(str(player), {})
	return f if f is Dictionary else {}

static func detachment_keys(player: int) -> Array:
	if player <= 0:
		return []
	return ArmyDets.player_detachment_keys(player, Common.state())

static func has_codex_discipline(player: int) -> bool:
	return GLADIUS in detachment_keys(player)

# ===========================================================================
# COMBAT DOCTRINES — state
# ===========================================================================

static func army_doctrine(player: int) -> String:
	return str(_faction(player).get(FK_DOCTRINE, ""))

static func doctrines_used(player: int) -> Dictionary:
	var u = _faction(player).get(FK_USED, {})
	return u if u is Dictionary else {}

static func times_used(player: int, doctrine: String) -> int:
	return int(doctrines_used(player).get(doctrine, 0))

## How many times `doctrine` may still be selected this battle: once each;
## with Codex Discipline (Gladius Task Force) ONE doctrine one extra time.
## WP-M2b: + Assault / Devastator / Tactical Mastery (SMDetachmentsB) — that
## doctrine one additional time; stacks with Codex Discipline.
static func doctrine_limit(player: int, doctrine: String) -> int:
	var smb = load("res://scripts/codex/space_marines/SMDetachmentsB.gd")
	var base := 1 + int(smb.doctrine_extra_selections(player, doctrine))
	if not has_codex_discipline(player):
		return base
	var used := doctrines_used(player)
	for d in used:
		if str(d) != doctrine and int(used[d]) >= 2 + int(smb.doctrine_extra_selections(player, str(d))):
			return base  # Codex Discipline's extra selection went to another doctrine
	return base + 1

static func doctrine_available(player: int, doctrine: String) -> bool:
	return doctrine in Common.DOCTRINES and times_used(player, doctrine) < doctrine_limit(player, doctrine)

static func decided_this_command_phase(player: int) -> bool:
	return int(_faction(player).get(FK_DECIDED_ROUND, 0)) == Common.battle_round()

## True while `player` may select (or skip) a doctrine: a Space Wolves army,
## in its own Command phase, not decided yet this phase, a doctrine left.
static func selection_open(player: int) -> bool:
	if not enabled() or not Common.is_sw_army(player):
		return false
	if Common.current_phase() != int(GameStateData.Phase.COMMAND) or Common.active_player() != player:
		return false
	if decided_this_command_phase(player):
		return false
	return not available_doctrines(player).is_empty()

## [{key, display, description, short, times_used, extra}] for the doctrines
## `player` can still select (extra = this would be Codex Discipline's
## additional selection).
static func available_doctrines(player: int) -> Array:
	var out: Array = []
	for d in Common.DOCTRINES:
		if not doctrine_available(player, d):
			continue
		out.append({"key": d, "display": str(Common.DOCTRINE_LABELS[d]), "description": str(DOCTRINE_TEXT[d]),
			"short": str(DOCTRINE_SHORT[d]), "times_used": times_used(player, d), "extra": times_used(player, d) >= 1})
	return out

## Units "with this ability" that the army doctrine reaches (on the
## battlefield or not) — Game Log / UI count.
static func doctrine_units(player: int) -> Array:
	var out: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and Common.is_alive(u) and Common.has_combat_doctrines(u):
			out.append(str(uid))
	return out

## The doctrines active for the unit or any component of its Attached unit
## (an Attached unit is one unit, 19.01).
static func group_doctrines(u: Dictionary) -> Array:
	var out: Array = []
	if u.is_empty() or not enabled():
		return out
	var uid := str(u.get("id", ""))
	var comps: Array = [u]
	if uid != "":
		for gid in Common.attached_group_ids(uid):
			if str(gid) != uid:
				var gu := Common.unit(str(gid))
				if not gu.is_empty():
					comps.append(gu)
	for c in comps:
		for d in Common.active_doctrines(c):
			if not d in out:
				out.append(d)
	return out

static func group_doctrine_active(u: Dictionary, doctrine: String) -> bool:
	return doctrine in group_doctrines(u)

# ===========================================================================
# COMBAT DOCTRINES — effects (EffectPrimitives / AssaultShooting hooks)
# ===========================================================================

## ASSAULT DOCTRINE: the advance move does not prevent declaring a charge.
static func advance_allows_charge(u: Dictionary) -> bool:
	return group_doctrine_active(u, "assault")

## DEVASTATOR DOCTRINE: this unit's ranged attacks have [ASSAULT].
static func ranged_attacks_have_assault(u: Dictionary) -> bool:
	return group_doctrine_active(u, "devastator")

## TACTICAL DOCTRINE: the fall-back move does not prevent shooting ...
static func fall_back_allows_shoot(u: Dictionary) -> bool:
	return group_doctrine_active(u, "tactical")

## ... and does not prevent declaring a charge.
static func fall_back_allows_charge(u: Dictionary) -> bool:
	return group_doctrine_active(u, "tactical")

# ===========================================================================
# COMBAT DOCTRINES — selection (CommandPhase actions)
# ===========================================================================

## The Command-phase actions `player` has for the doctrine (CommandPhase
## get_available_actions hook). Same action types the 10e Gladius path used,
## so GameEventLog / the AI recognise them.
static func command_actions(player: int) -> Array:
	var out: Array = []
	if not selection_open(player):
		return out
	for d in available_doctrines(player):
		out.append({"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": d.key, "player": player, "sw11e": true,
			"description": "Combat Doctrines: %s — %s%s" % [d.display, d.short, " (Codex Discipline: second time)" if d.extra else ""]})
	out.append({"type": "SKIP_COMBAT_DOCTRINE", "player": player, "sw11e": true,
		"description": "Combat Doctrines: no doctrine this turn"})
	return out

## Validation for SELECT_COMBAT_DOCTRINE / SKIP_COMBAT_DOCTRINE (errors array).
static func validate_action(player: int, action: Dictionary) -> Array:
	var errors: Array = []
	if not Common.is_sw_army(player):
		errors.append("Player %d is not a Space Wolves army" % player)
		return errors
	if Common.current_phase() != int(GameStateData.Phase.COMMAND) or Common.active_player() != player:
		errors.append("Combat Doctrines: select a doctrine in your own Command phase")
		return errors
	if decided_this_command_phase(player):
		errors.append("Combat Doctrines: already decided this Command phase (%s)" % (Common.DOCTRINE_LABELS.get(army_doctrine(player), "none")))
		return errors
	if str(action.get("type", "")) == "SELECT_COMBAT_DOCTRINE":
		var d := str(action.get("doctrine_key", "")).to_lower()
		if not d in Common.DOCTRINES:
			errors.append("Unknown combat doctrine: %s" % d)
		elif not doctrine_available(player, d):
			errors.append("%s has already been selected this battle%s" % [str(Common.DOCTRINE_LABELS[d]),
				"" if not has_codex_discipline(player) else " (Codex Discipline's extra selection is spent)"])
	return errors

## Select `doctrine` for `player`. Returns {success, diffs, display, message}
## (diffs NOT applied — the phase result carries them).
static func select_doctrine_diffs(player: int, doctrine: String) -> Dictionary:
	var d := doctrine.to_lower()
	var errs := validate_action(player, {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": d})
	if not errs.is_empty():
		return {"success": false, "error": "; ".join(PackedStringArray(errs)), "diffs": []}
	var used := doctrines_used(player).duplicate()
	var extra := int(used.get(d, 0)) >= 1
	used[d] = int(used.get(d, 0)) + 1
	var hist: Array = (_faction(player).get(FK_HISTORY, []) as Array).duplicate() if _faction(player).get(FK_HISTORY, []) is Array else []
	hist.append({"round": Common.battle_round(), "doctrine": d})
	var p := str(player)
	var diffs: Array = [
		{"op": "set", "path": "factions.%s.%s" % [p, FK_DOCTRINE], "value": d},
		{"op": "set", "path": "factions.%s.%s" % [p, FK_USED], "value": used},
		{"op": "set", "path": "factions.%s.%s" % [p, FK_DECIDED_ROUND], "value": Common.battle_round()},
		{"op": "set", "path": "factions.%s.%s" % [p, FK_HISTORY], "value": hist},
	]
	var display := str(Common.DOCTRINE_LABELS[d])
	var n := doctrine_units(player).size()
	var msg := "Combat Doctrines: %s active for %d unit(s) until the start of your next Command phase — %s%s" % [
		display, n, str(DOCTRINE_SHORT[d]), " (Codex Discipline: selected a second time)" if extra else ""]
	_log("P%d selects %s (round %d, used %s)" % [player, display, Common.battle_round(), str(used)])
	return {"success": true, "diffs": diffs, "display": display, "doctrine": d, "message": msg}

static func skip_doctrine_diffs(player: int) -> Dictionary:
	var errs := validate_action(player, {"type": "SKIP_COMBAT_DOCTRINE"})
	if not errs.is_empty():
		return {"success": false, "error": "; ".join(PackedStringArray(errs)), "diffs": []}
	_log("P%d selects no combat doctrine this turn (round %d)" % [player, Common.battle_round()])
	return {"success": true, "message": "Combat Doctrines: no doctrine this turn",
		"diffs": [{"op": "set", "path": "factions.%s.%s" % [str(player), FK_DECIDED_ROUND], "value": Common.battle_round()}]}

## Start of `player`'s Command phase: the doctrine selected in their previous
## Command phase (and every per-unit doctrine that lasts "until the start of
## your next Command phase") ends. Re-entering the same Command phase (a save
## loaded during it) keeps this phase's choice. Applies the diffs itself.
static func on_command_phase_start(player: int) -> Array:
	var diffs: Array = []
	if not enabled() or not Common.is_sw_army(player):
		return diffs
	if decided_this_command_phase(player):
		_log("P%d's Command phase re-entered — doctrine choice of this phase kept (%s)" % [player, army_doctrine(player)])
		return diffs
	if army_doctrine(player) != "":
		diffs.append({"op": "set", "path": "factions.%s.%s" % [str(player), FK_DOCTRINE], "value": ""})
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		if flags.has(F_UNIT_DOCTRINE) and int(flags.get(F_UNIT_DOCTRINE_EXPIRES, player)) == player \
				and int(units[uid].get("owner", 0)) == player:
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_UNIT_DOCTRINE]})
			if flags.has(F_UNIT_DOCTRINE_EXPIRES):
				diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_UNIT_DOCTRINE_EXPIRES]})
	if not diffs.is_empty():
		Common.apply_diffs(diffs)
		_log("start of P%d's Command phase — previous combat doctrine(s) expired (%d op(s))" % [player, diffs.size()])
	return diffs

## AI: which doctrine to pick (SELECT action) or SKIP. Synchronous; always
## returns an action while the selection is open, so the AI never stalls.
## Heuristic: TACTICAL when a doctrine unit is engaged (fall back and still
## act), ASSAULT when an unengaged doctrine unit is within 18" of the enemy
## (advance + charge), DEVASTATOR from round 2 when the army has ranged
## weapons; otherwise keep doctrines for later unless there are fewer turns
## left than doctrines.
static func ai_command_action(player: int) -> Dictionary:
	var acts := command_actions(player)
	if acts.is_empty():
		return {}
	var avail: Array = []
	for d in available_doctrines(player):
		avail.append(str(d.key))
	var engaged := false
	var close := false
	for uid in doctrine_units(player):
		var u := Common.unit(uid)
		if not Common.is_on_battlefield(u) or Common.is_attached_character(uid):
			continue
		if Common.is_engaged(uid):
			engaged = true
		elif Common.nearest_enemy_inches(u) <= 18.0:
			close = true
	var rnd := Common.battle_round()
	var pick := ""
	if engaged and "tactical" in avail:
		pick = "tactical"
	elif close and "assault" in avail:
		pick = "assault"
	elif rnd >= 2 and "devastator" in avail:
		pick = "devastator"
	elif avail.size() >= maxi(1, 6 - rnd):
		pick = str(avail[0])
	if pick == "":
		return {"type": "SKIP_COMBAT_DOCTRINE", "_ai_description": "Combat Doctrines: saving the doctrines (round %d, %s left)" % [rnd, str(avail)]}
	return {"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": pick,
		"_ai_description": "Combat Doctrines: %s (engaged=%s, enemy within 18\"=%s, round %d)" % [str(Common.DOCTRINE_LABELS[pick]), str(engaged), str(close), rnd]}

# ===========================================================================
# Command panel UI (CommandController hook) — the COMBAT DOCTRINES block
# ===========================================================================

## True when the Command panel should show the block for `player`.
static func show_command_ui(player: int) -> bool:
	return enabled() and Common.is_sw_army(player)

## Build the block into `section`. `emit` is a Callable(action: Dictionary)
## that sends the action like the panel's other buttons.
static func build_command_ui(section: VBoxContainer, player: int, emit: Callable) -> void:
	var box := VBoxContainer.new()
	box.name = "SW11eDoctrinesBox"
	box.add_theme_constant_override("separation", 4)
	section.add_child(box)
	var header := Label.new()
	header.name = "SW11eDoctrinesHeader"
	header.text = "COMBAT DOCTRINES"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	box.add_child(header)
	var status := Label.new()
	status.name = "SW11eDoctrineStatus"
	var active := army_doctrine(player)
	if active != "":
		status.text = "Active: %s — %s (until your next Command phase)" % [str(Common.DOCTRINE_LABELS[active]), str(DOCTRINE_SHORT[active])]
		status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	elif decided_this_command_phase(player):
		status.text = "No doctrine selected this turn"
		status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	else:
		status.text = "Select one doctrine for your units with Combat Doctrines (each once per battle%s)." % (
			"; Codex Discipline: one may be selected twice" if has_codex_discipline(player) else "")
		status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	status.add_theme_font_size_override("font_size", 16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var open := selection_open(player)
	for d in Common.DOCTRINES:
		var btn := Button.new()
		btn.name = "SW11eDoctrine_%s" % d
		var used_n := times_used(player, d)
		var can := open and doctrine_available(player, d)
		# WP-M2b: the extra selection is named after the rule that gives it (Assault Mastery, ... or Codex Discipline).
		var extra_src := str(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").doctrine_extra_source(player, d))
		if extra_src == "" or used_n >= 2:
			extra_src = "Codex Discipline" if has_codex_discipline(player) else extra_src
		btn.text = "%s%s" % [str(Common.DOCTRINE_LABELS[d]).to_upper(), "  (used)" if used_n >= doctrine_limit(player, d) else (("  (%s)" % extra_src) if used_n >= 1 else "")]
		btn.tooltip_text = str(DOCTRINE_TEXT[d])
		btn.custom_minimum_size = Vector2(230, 30)
		btn.add_theme_font_size_override("font_size", 16)
		btn.disabled = not can
		if active == d:
			btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
			btn.add_theme_color_override("font_disabled_color", Color(0.4, 1.0, 0.5))
		btn.pressed.connect(func(): emit.call({"type": "SELECT_COMBAT_DOCTRINE", "doctrine_key": d, "player": player}))
		box.add_child(btn)
	if open:
		var skip := Button.new()
		skip.name = "SW11eDoctrine_skip"
		skip.text = "No doctrine this turn"
		skip.custom_minimum_size = Vector2(230, 26)
		skip.add_theme_font_size_override("font_size", 15)
		skip.pressed.connect(func(): emit.call({"type": "SKIP_COMBAT_DOCTRINE", "player": player}))
		box.add_child(skip)

# ===========================================================================
# TRANSHUMAN STRATEGIST
# ===========================================================================

static func warlord_id(player: int) -> String:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and bool(u.get("meta", {}).get("is_warlord", false)):
			return str(uid)
	return ""

## "At the start of the battle round, if a model with this ability is your
## WARLORD, gain 1CP." Not subject to the 10e 1-bonus-CP-per-round cap (11e
## has none — the Aquila Commander / Da Boss ruling). Once per battle round
## even if the round's first Command phase is re-entered (save / load).
## Returns the applied diffs.
static func on_battle_round_start(battle_round: int) -> Array:
	var diffs: Array = []
	if not enabled():
		return diffs
	for p in [1, 2]:
		if not Common.is_sw_army(p):
			continue
		var wid := warlord_id(p)
		if wid == "":
			continue
		var w := Common.unit(wid)
		if not Common.is_alive(w) or not Common.has_ability(w, ABILITY_TRANSHUMAN):
			continue
		if int(w.get("flags", {}).get(F_TRANSHUMAN_ROUND, -1)) == battle_round:
			_log("Transhuman Strategist: P%d already resolved for battle round %d" % [p, battle_round])
			continue
		var cp_before := Common.player_cp(p)
		var d: Array = [
			{"op": "set", "path": "players.%s.cp" % str(p), "value": cp_before + 1},
			{"op": "set", "path": "units.%s.flags.%s" % [wid, F_TRANSHUMAN_ROUND], "value": battle_round},
		]
		Common.apply_diffs(d)
		diffs.append_array(d)
		_log("Transhuman Strategist: P%d's WARLORD %s — +1CP at the start of battle round %d (%d -> %d)" % [p, Common.unit_name(wid), battle_round, cp_before, cp_before + 1])
		Common.game_log(p, "Transhuman Strategist (%s, Warlord): +1CP" % Common.unit_name(wid))
	return diffs

# ===========================================================================
# CURSE OF THE WULFEN
# ===========================================================================

## +1 OC (INFANTRY) / +3 OC (VEHICLE) while within 6" of a friendly SPACE
## WOLVES CHARACTER model (excluding WULFEN models) or within 12" of a friendly
## WOLF PRIEST model, if not battle-shocked. MissionManager adds it to every
## model of the unit (each model's OC characteristic).
static func oc_bonus(u: Dictionary) -> int:
	if not enabled() or u.is_empty() or not Common.has_ability(u, ABILITY_CURSE):
		return 0
	var owner := int(u.get("owner", 0))
	if not Common.is_sw_army(owner) or not Common.is_on_battlefield(u):
		return 0
	var uid := str(u.get("id", ""))
	for gid in (Common.attached_group_ids(uid) if uid != "" else []):
		if Common.is_battle_shocked(Common.unit(str(gid))):
			return 0
	if Common.is_battle_shocked(u):
		return 0
	if curse_source(u) == "":
		return 0
	if Common.has_keyword(u, "VEHICLE"):
		return 3
	if Common.has_keyword(u, "INFANTRY"):
		return 1
	return 0

## The friendly model that switches the curse on ("" = none): a SPACE WOLVES
## CHARACTER (not WULFEN) within 6", else a WOLF PRIEST within 12".
static func curse_source(u: Dictionary) -> String:
	var owner := int(u.get("owner", 0))
	var uid := str(u.get("id", ""))
	var units: Dictionary = Common.state().get("units", {})
	var priest_src := ""
	for sid in units:
		var s: Dictionary = units[sid]
		if str(sid) == uid or int(s.get("owner", 0)) != owner or not Common.is_on_battlefield(s):
			continue
		var is_char := Common.has_keyword(s, "CHARACTER") and Common.has_keyword(s, "SPACE WOLVES") and not Common.has_keyword(s, "WULFEN")
		var is_priest := Common.has_keyword(s, "WOLF PRIEST")
		if not is_char and not is_priest:
			continue
		var d := Common.unit_distance_inches(u, s)
		if is_char and d <= CURSE_CHARACTER_RANGE_IN + 0.001:
			return str(sid)
		if is_priest and d <= CURSE_WOLF_PRIEST_RANGE_IN + 0.001 and priest_src == "":
			priest_src = str(sid)
	return priest_src

## Bestial Forms: "For the purposes of transport capacity, each WULFEN model
## takes up the space of 2 models." 0 = no rule (TransportManager hook).
static func transport_space_per_model(u: Dictionary) -> int:
	if not enabled() or u.is_empty() or not Common.has_keyword(u, "WULFEN"):
		return 0
	return 2 if Common.is_sw_army(int(u.get("owner", 0))) else 0

# ===========================================================================
# SONS OF RUSS — army validation
# ===========================================================================

## Is this army JSON a Space Wolves army (faction "Space Wolves" or a SPACE
## WOLVES unit)? (Army-file twin of SWCommon.is_sw_army.)
static func army_is_sw(army_data: Dictionary) -> bool:
	var fac = army_data.get("faction", {})
	if fac is Dictionary and Common.norm_name(str(fac.get("name", ""))) == "space wolves":
		return true
	for uid in army_data.get("units", {}):
		var u = army_data.units[uid]
		if u is Dictionary and Common.has_keyword(u, "SPACE WOLVES"):
			return true
	return false

## The chapter keyword other than SPACE WOLVES an ADEPTUS ASTARTES unit has
## ("" = none: a Space Wolves or a generic Codex: Space Marines datasheet).
static func other_chapter_keyword(u: Dictionary) -> String:
	if not Common.has_keyword(u, "ADEPTUS ASTARTES"):
		return ""
	for kw in OTHER_CHAPTERS:
		if Common.has_keyword(u, kw):
			return kw
	return ""

## Sons of Russ: "Your army cannot include APOTHECARY units." Errors (army
## construction is illegal) for a Space Wolves army at edition 11.
static func validate_army(army_data: Dictionary) -> Dictionary:
	var out := {"errors": [], "warnings": []}
	if not enabled() or not army_is_sw(army_data):
		return out
	for uid in army_data.get("units", {}):
		var u = army_data.units[uid]
		if u is Dictionary and Common.has_keyword(u, KW_APOTHECARY):
			out.errors.append("Sons of Russ: a Space Wolves army cannot include APOTHECARY units — %s (%s)" % [str(u.get("meta", {}).get("name", uid)), uid])
	return out

## Live-state twin for the game: the Sons of Russ problems of `player`'s army
## on the board (FormationsPhase hook writes them to the Game Log).
static func live_army_problems(player: int) -> Array:
	var out: Array = []
	if not enabled() or not Common.is_sw_army(player):
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and Common.has_keyword(u, KW_APOTHECARY):
			out.append("Sons of Russ: a Space Wolves army cannot include APOTHECARY units — %s is not legal in this army" % Common.unit_name(str(uid)))
	return out
