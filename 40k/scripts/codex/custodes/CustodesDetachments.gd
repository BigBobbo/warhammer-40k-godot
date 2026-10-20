extends RefCounted

## CustodesDetachments — the 13 Codex: Adeptus Custodes (11th edition)
## detachment rules (WP-C46), each Unique: Shield Host detachment's Favoured
## Ka'tah additional effect, and the façade the engine hooks call for the
## codex enhancements (CustodesEnhancements.gd, loaded lazily — the Custodes
## modules never preload each other, IMPLEMENTATION.md §2).
##
## Source of truth: .llm/codex_11e_wahapedia/custodes/RULES.md ("Rule —" and
## "Favoured ka'tah" lines). Rulings: RULINGS.md § WP-C46.
##
##  Guardians of the Throne — Martial Mastery ... selected to fight: melee
##                     [SUSTAINED HITS 1] or [LETHAL HITS] (free rule choice in
##                     the unit_selected_to_fight window)
##  Aquilan Shield — Gilded Guardians ......... -1 to wound for ranged S > T vs a
##                     friendly non-M/V unit within range of an objective;
##                     Favoured SALVUS: ranged attacks +6" Range
##  Dread Host — Instruments of the Emperor's Wrath  re-roll charge rolls;
##                     Favoured DACATARAI: an enemy unit engaged with the unit
##                     has -2" on its pile-in / consolidation moves
##  Emperor's Chosen — Magna Imperator ......... re-roll one hit roll and one
##                     wound roll when selected to attack; Favoured RENDAX: one
##                     engaged MONSTER/VEHICLE takes 1 / D3 / 3 mortal wounds
##  Emissaries Imperatus — Heralds of the Throne  Fights First; Favoured
##                     CONSERVAI: advance / fall-back keep action eligibility
##  Shadowkeepers — Wardens of the Dark Cells ... -1 to wound for melee S > T vs
##                     a friendly non-M/V unit within range of an objective;
##                     Favoured KAPTARIS: an engaged enemy unit takes a
##                     battle-shock roll at -1 (once per enemy unit per phase)
##  Solar Watch — Talon Sortie ................. fall back and still charge;
##                     Favoured CALISTUS: +2" M
##  Honoured Companions — Companion's Watch .... TRUSTED SENTINEL within range of
##                     an objective re-roll wound rolls of 1
##  Auric Champions — Assemblage of Might ...... dreadful foe (Command phase
##                     rule choice): CHARACTER models' attacks +1 to wound
##  Lions of the Emperor — On Gilded Wings ...... end of the opponent's Fight
##                     phase: an unengaged TERMINATOR unit can go into strategic
##                     reserves (fight_phase_end rule choice)
##  Might of the Moritoi — Moritoi Ancients .... DREADNOUGHT: +2 OC at starting
##                     strength; re-roll hit 1s below it; + wound 1s below half
##  Grav-Assault Force — Flare Shields ......... GRAV-ASSAULT: 4+ InSv vs ranged
##  Null Maiden Vigil — Silent Sisterhood ...... ANATHEMA PSYKANA CHARACTER
##                     WARLORD allowed; PROSECUTOR SQUAD BATTLELINE; Creeping
##                     Dread (Aura) in the opponent's Battle-shock step
##
## Engine files only call the static functions below from one-line, commented
## hooks ("Codex: Adeptus Custodes (11e) … (CustodesDetachments.gd, WP-C46)").

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

const ENHANCEMENTS_PATH := "res://scripts/codex/custodes/CustodesEnhancements.gd"

# ---------------------------------------------------------------------------
# Detachment keys (normalised: lower case, folded apostrophes)
# ---------------------------------------------------------------------------

const GUARDIANS := "guardians of the throne"
const AQUILAN := "aquilan shield"
const DREAD_HOST := "dread host"
const EMPERORS_CHOSEN := "emperor's chosen"
const EMISSARIES := "emissaries imperatus"
const SHADOWKEEPERS := "shadowkeepers"
const SOLAR_WATCH := "solar watch"
const HONOURED := "honoured companions"
const AURIC_CHAMPIONS := "auric champions"
const LIONS := "lions of the emperor"
const MORITOI := "might of the moritoi"
const GRAV_ASSAULT := "grav-assault force"
const NULL_MAIDEN := "null maiden vigil"

const RULE_NAMES := {
	GUARDIANS: "Martial Mastery",
	AQUILAN: "Gilded Guardians",
	DREAD_HOST: "Instruments of the Emperor's Wrath",
	EMPERORS_CHOSEN: "Magna Imperator",
	EMISSARIES: "Heralds of the Throne",
	SHADOWKEEPERS: "Wardens of the Dark Cells",
	SOLAR_WATCH: "Talon Sortie",
	HONOURED: "Companion's Watch",
	AURIC_CHAMPIONS: "Assemblage of Might",
	LIONS: "On Gilded Wings",
	MORITOI: "Moritoi Ancients",
	GRAV_ASSAULT: "Flare Shields",
	NULL_MAIDEN: "Silent Sisterhood",
}

## Unique: Shield Host detachments — Favoured Ka'tah (RULES.md).
const FAVOURED := {
	SHADOWKEEPERS: "kaptaris",
	SOLAR_WATCH: "calistus",
	EMPERORS_CHOSEN: "rendax",
	EMISSARIES: "conservai",
	AQUILAN: "salvus",
	DREAD_HOST: "dacatarai",
}

const FAVOURED_TEXT := {
	SHADOWKEEPERS: "You can select one enemy unit engaged with your unit. That enemy unit must make a battle-shock roll, with -1 to that battle-shock roll. You cannot select the same enemy unit for this effect more than once per phase.",
	SOLAR_WATCH: "Your unit has +2\" M.",
	EMPERORS_CHOSEN: "You can select one enemy MONSTER / VEHICLE unit engaged with your unit and roll one D6: on a 1-2, that enemy unit suffers 1 mortal wound; on a 3-5, D3 mortal wounds; on a 6, 3 mortal wounds.",
	EMISSARIES: "Until the end of the turn, being selected to make an advance / fall-back move does not prevent your unit from being eligible to start an action.",
	AQUILAN: "Your unit's ranged attacks have +6\" R.",
	DREAD_HOST: "When an enemy unit engaged with your unit makes a pile-in / consolidation move, -2\" from that pile-in / consolidation move.",
}

## Ka'tah effect flags (CustodesKatah.gd: OFFER_PREFIX + id). Read here as
## plain flags — this module never loads CustodesKatah.gd.
const KATAH_FLAG_PREFIX := "cus11e_katah_"

# ---------------------------------------------------------------------------
# Rule offers (stratagem-window framework; free, never stratagems)
# ---------------------------------------------------------------------------

const RULE_PREFIX := "cus11e_rule_"
const RULE_MARTIAL_MASTERY := "cus11e_rule_martial_mastery"
const RULE_DREADFUL_FOE := "cus11e_rule_dreadful_foe"
const RULE_GILDED_WINGS := "cus11e_rule_on_gilded_wings"

## Rule-only window opened at the start of every battle phase (BasePhase hook)
## for the "at the start of any phase" enhancements (CustodesEnhancements.gd).
const WINDOW_PHASE_START := "cus11e_phase_start"

# ---------------------------------------------------------------------------
# Flags (no effect_ prefix — ShootingPhase wipes effect_* on exit). Each has
# its clear point next to it and a headless expiry check.
# ---------------------------------------------------------------------------

## Martial Mastery choice on every component: "sustained" | "lethal".
## Cleared at the end of the phase (on_phase_end).
const F_MARTIAL_MASTERY := "cus11e_martial_mastery"
## Dreadful foe on the ENEMY unit (+ its Attached-unit components): the
## Auric Champions player's number. Cleared at the start of that player's next
## Command phase (on_command_phase_start).
const F_DREADFUL_FOE := "cus11e_dreadful_foe_of"
## Shadowkeepers Favoured Kaptaris: phase stamp the enemy unit was selected
## in ("once per phase"). Cleared at the end of the phase.
const F_SK_KAPTARIS := "cus11e_sk_kaptaris_stamp"
## Creeping Dread: phase stamp — the unit takes its battle-shock roll at -1
## this Battle-shock step. Cleared at the end of the Command phase.
const F_CREEPING_DREAD := "cus11e_creeping_dread"
## BATTLELINE written into meta.keywords by Silent Sisterhood.
const F_BATTLELINE_GRANT := "cus11e_battleline_grant"

const CREEPING_DREAD_RANGE_IN := 12.0

## Magna Imperator: "re-roll one hit roll / one wound roll" — per unit, per
## selection to attack (= per phase: a unit is selected to shoot / fight once
## per phase). Host-side ledger keyed "<unit>|<stamp>|<hit|wound>"; cleared at
## the end of every phase.
static var _magna_used: Dictionary = {}

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return GameConstants.edition >= 11

static func det_key(name: String) -> String:
	return name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()

static func _board_or_state(board: Dictionary) -> Dictionary:
	return board if board.has("units") else Common.state()

## Normalised detachment name of `player` ("" below edition 11 / unknown).
static func detachment_of(player: int, board: Dictionary = {}) -> String:
	if not enabled() or player <= 0:
		return ""
	var factions: Dictionary = _board_or_state(board).get("factions", {})
	if factions.is_empty() or not factions.has(str(player)):
		factions = Common.state().get("factions", {})
	return det_key(str(factions.get(str(player), {}).get("detachment", "")))

static func unit_detachment(u: Dictionary, board: Dictionary = {}) -> String:
	if u.is_empty():
		return ""
	return detachment_of(int(u.get("owner", 0)), board)

## 11e multi-detachment armies: EVERY detachment `player` selected is active
## (ArmyDetachments11e) — normalised keys, primary first.
static func detachments_of(player: int, board: Dictionary = {}) -> Array:
	if not enabled() or player <= 0:
		return []
	return ArmyDets.player_detachment_keys(player, _board_or_state(board))

static func has_det(player: int, det: String, board: Dictionary = {}) -> bool:
	return det in detachments_of(player, board)

## Is `det` one of the detachments of the unit's owner?
static func unit_has_det(u: Dictionary, det: String, board: Dictionary = {}) -> bool:
	if u.is_empty():
		return false
	return has_det(int(u.get("owner", 0)), det, board)

## The player's 'Unique: Shield Host' detachment (the one stating a Favoured
## Ka'tah) — at most one: two detachments sharing a tag cannot be combined.
static func shield_host_of(player: int) -> String:
	for det in detachments_of(player):
		if FAVOURED.has(det):
			return det
	return ""

static func rule_name(det: String) -> String:
	return str(RULE_NAMES.get(det, ""))

static func is_codex_detachment(det_name: String) -> bool:
	return RULE_NAMES.has(det_key(det_name))

## The unit and its Attached-unit components (dicts); the caller's own dict
## stands for its unit (a resolver's board copy may differ from GameState).
static func group_units(u: Dictionary, board: Dictionary = {}) -> Array:
	var uid := str(u.get("id", ""))
	if uid == "":
		return [u]
	var units: Dictionary = _board_or_state(board).get("units", {})
	var out: Array = []
	for gid in Common.attached_group_ids(uid):
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

static func group_is_mv(u: Dictionary, board: Dictionary = {}) -> bool:
	return group_kw(u, "MONSTER", board) or group_kw(u, "VEHICLE", board)

static func is_custodes(u: Dictionary, board: Dictionary = {}) -> bool:
	return group_kw(u, "ADEPTUS CUSTODES", board)

static func katah_active(u: Dictionary, katah_id: String, board: Dictionary = {}) -> bool:
	for gu in group_units(u, board):
		if bool(gu.get("flags", {}).get(KATAH_FLAG_PREFIX + katah_id, false)):
			return true
	return false

static func _group_flag(u: Dictionary, flag: String, board: Dictionary = {}):
	for gu in group_units(u, board):
		var v = gu.get("flags", {}).get(flag, null)
		if v != null and not (typeof(v) == TYPE_BOOL and v == false) and str(v) != "":
			return v
	return null

static func _alive_models(u: Dictionary) -> int:
	var n := 0
	for m in u.get("models", []):
		if m.get("alive", true):
			n += 1
	return n

static func stamp() -> String:
	var meta: Dictionary = Common.state().get("meta", {})
	return "%d:%d:%d" % [int(meta.get("battle_round", 1)), int(meta.get("active_player", 1)), int(meta.get("phase", -1))]

static func _log(msg: String) -> void:
	Common.log_info("[CustodesDetachments] " + msg)

static func _event(player: int, msg: String) -> void:
	Common.game_log(player, msg)

static func _toast(msg: String) -> void:
	var tm = Common.autoload("ToastManager")
	if tm and tm.has_method("show_toast"):
		tm.show_toast(msg, Color.GOLD)

static func _apply(diffs: Array) -> void:
	Common.apply_diffs(diffs)

static func _rng():
	var re = Common.rules()
	return re.make_rng() if re else null

static func _d6(rng) -> int:
	return int(rng.roll_d6(1)[0]) if rng else 1

static func _is_ai(player: int) -> bool:
	var ai = Common.autoload("AIPlayer")
	return ai != null and ai.has_method("is_ai_player") and bool(ai.is_ai_player(player))

static func enh():
	if not ResourceLoader.exists(ENHANCEMENTS_PATH):
		return null
	return load(ENHANCEMENTS_PATH)

## A unit is within range of an objective while any of its (Attached unit's)
## models is — the same terrain-aware predicate objective control uses.
static func within_objective_range(u: Dictionary, board: Dictionary = {}) -> bool:
	var src := _board_or_state(board)
	var objectives: Array = src.get("board", {}).get("objectives", [])
	if objectives.is_empty():
		objectives = Common.state().get("board", {}).get("objectives", [])
	if objectives.is_empty():
		return false
	var mm = Common.autoload("MissionManager")
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

## Ruling (RULINGS.md WP-C46): a multi-model unit is below its starting
## strength while any of its models is destroyed; a single-model unit while
## it has lost one or more wounds. Below half-strength = GameState's check
## (fewer than half the models; single model: fewer than half its wounds).
static func below_starting_strength(u: Dictionary) -> bool:
	var models: Array = u.get("models", [])
	if models.is_empty():
		return false
	if models.size() == 1:
		var m: Dictionary = models[0]
		return m.get("alive", true) and int(m.get("current_wounds", m.get("wounds", 1))) < int(m.get("wounds", 1))
	for m in models:
		if not m.get("alive", true):
			return true
	return false

static func below_half_strength(u: Dictionary) -> bool:
	var gs = Common.game_state()
	if gs and gs.has_method("is_below_half_strength"):
		return bool(gs.is_below_half_strength(u))
	return false

# ===========================================================================
# FAVOURED KA'TAH API (called by CustodesKatah.gd — WP-C3 hook)
# ===========================================================================

static func favoured_katah(player: int) -> String:
	return str(FAVOURED.get(shield_host_of(player), ""))

static func favoured_katah_text(player: int, katah_id: String) -> String:
	var det := shield_host_of(player)
	if str(FAVOURED.get(det, "")) != katah_id:
		return ""
	return "%s — %s" % [rule_name(det), str(FAVOURED_TEXT.get(det, ""))]

## Shadowkeepers KAPTARIS: one enemy unit engaged with your unit (not one
## already selected for this effect this phase). Emperor's Chosen RENDAX: one
## engaged enemy MONSTER / VEHICLE unit. {} when there is nothing to pick.
static func favoured_katah_secondary(player: int, katah_id: String, unit_id: String, _ctx: Dictionary) -> Dictionary:
	var det := shield_host_of(player)
	var opts: Array = []
	if det == SHADOWKEEPERS and katah_id == "kaptaris":
		for eid in Common.engaged_enemy_ids(unit_id):
			var head := Common.head_id(str(eid))
			if opts.any(func(o): return o.id == head):
				continue
			if str(Common.unit(head).get("flags", {}).get(F_SK_KAPTARIS, "")) == stamp():
				continue
			opts.append({"id": head, "label": Common.unit_name(head)})
		if opts.is_empty():
			return {}
		return {"kind": "unit", "prompt": "KAPTARIS (Shadowkeepers): select one enemy unit engaged with your unit — it makes a battle-shock roll at -1", "options": opts}
	if det == EMPERORS_CHOSEN and katah_id == "rendax":
		for eid in Common.engaged_enemy_ids(unit_id):
			var head := Common.head_id(str(eid))
			if opts.any(func(o): return o.id == head):
				continue
			if not group_is_mv(Common.unit(head)):
				continue
			opts.append({"id": head, "label": Common.unit_name(head)})
		if opts.is_empty():
			return {}
		return {"kind": "unit", "prompt": "RENDAX (Emperor's Chosen): select one engaged enemy MONSTER / VEHICLE unit — roll one D6 for mortal wounds", "options": opts}
	return {}

## The additional effect of the Favoured Ka'tah, right after the ka'tah's own
## effect is applied. Returns the diffs (CustodesKatah applies them).
static func favoured_katah_extra_effect(player: int, katah_id: String, unit_id: String, ctx: Dictionary) -> Array:
	var det := shield_host_of(player)
	if str(FAVOURED.get(det, "")) != katah_id:
		return []
	var uname := Common.unit_name(unit_id)
	var diffs: Array = []
	match katah_id:
		"kaptaris":
			var eid := str(ctx.get("secondary_id", ""))
			if eid == "":
				return []
			eid = Common.head_id(eid)
			if not eid in Common.engaged_enemy_ids(unit_id).map(func(x): return Common.head_id(str(x))):
				Common.log_error("[CustodesDetachments] Shadowkeepers Kaptaris: %s is not engaged with %s — no battle-shock roll" % [eid, unit_id])
				return []
			for gid in Common.attached_group_ids(eid):
				diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(gid), F_SK_KAPTARIS], "value": stamp()})
			_apply(diffs)
			var fam = Common.autoload("FactionAbilityManager")
			if fam and fam.has_method("force_battle_shock_test"):
				var r: Dictionary = fam.force_battle_shock_test(eid, -1, "Kaptaris (Shadowkeepers)")
				diffs.append_array(r.get("diffs", []))
				var msg := "Favoured Ka'tah (Shadowkeepers): %s makes a battle-shock roll at -1 — %s" % [Common.unit_name(eid),
					"passed" if r.get("passed", true) else "FAILED, battle-shocked"]
				_log(msg)
				_event(player, msg)
		"rendax":
			var vid := str(ctx.get("secondary_id", ""))
			if vid == "":
				return []
			vid = Common.head_id(vid)
			if not group_is_mv(Common.unit(vid)):
				return []
			var rng = _rng()
			var roll := _d6(rng)
			var mw := 1
			if roll >= 6:
				mw = 3
			elif roll >= 3:
				mw = int(ceil(float(_d6(rng)) / 2.0))
			var res := mortal_wounds_to_unit(vid, mw, rng)
			diffs.append_array(res.diffs)
			_apply(res.diffs)
			var msg2 := "Favoured Ka'tah (Emperor's Chosen): RENDAX — %s rolled %d: %s suffers %d mortal wound%s (%d model%s destroyed)" % [uname, roll,
				Common.unit_name(vid), mw, "" if mw == 1 else "s", int(res.casualties), "" if int(res.casualties) == 1 else "s"]
			_log(msg2)
			_event(player, msg2)
			_toast(msg2)
		_:
			# Calistus +2" M, Salvus +6" Range, Conservai actions, Dacatarai -2"
			# for engaged enemies: read live from the ka'tah flag + detachment.
			var msg3 := "Favoured Ka'tah (%s): %s — %s" % [Common.unit_name(unit_id), katah_id.to_upper(), str(FAVOURED_TEXT.get(det, ""))]
			_log(msg3)
			_event(player, "Favoured Ka'tah: %s %s" % [uname, str(FAVOURED_TEXT.get(det, ""))])
	return diffs

## Null Maiden Vigil — Silent Sisterhood: "you can select a friendly ANATHEMA
## PSYKANA CHARACTER model to be your WARLORD" (a WARLORD is a CHARACTER).
static func allows_anathema_psykana_warlord(detachment: String) -> bool:
	return det_key(detachment) == NULL_MAIDEN

## Mortal wounds to a unit (06.02): the bodyguard first, spilling to the
## Attached unit's characters. {diffs, casualties, wounds_applied}.
static func mortal_wounds_to_unit(unit_id: String, mortal_wounds: int, rng) -> Dictionary:
	var out := {"diffs": [], "casualties": 0, "wounds_applied": 0}
	var re = Common.rules()
	var gs = Common.game_state()
	if re == null or gs == null or mortal_wounds <= 0:
		return out
	var remaining := mortal_wounds
	var first := true
	for gid in Common.attached_group_ids(Common.head_id(unit_id)):
		if remaining <= 0:
			break
		var u = Common.unit(str(gid))
		if u.is_empty() or not Common.is_alive(u):
			continue
		var pool := 0
		for m in u.get("models", []):
			if m.get("alive", true):
				pool += int(m.get("current_wounds", m.get("wounds", 1)))
		var res: Dictionary = re.apply_mortal_wounds(str(gid), remaining, gs.create_snapshot(), rng if first else null)
		first = false
		out.diffs.append_array(res.get("diffs", []))
		out.casualties += int(res.get("casualties", 0))
		var applied := int(res.get("wounds_applied", 0))
		out.wounds_applied += mini(applied, pool)
		remaining = maxi(0, applied - pool)
	return out

# ===========================================================================
# Combat modifiers (RulesEngine hooks). Contributions are
# {kind: "plus_one" | "minus_one" | "reroll_ones", source, note}; RulesEngine
# folds them into its HitModifier / WoundModifier bits and the ledger.
# The enhancement contributions (CustodesEnhancements.gd) are appended here,
# so every resolver path needs one call.
# ===========================================================================

## Hit-roll contributions for one attack batch.
static func hit_effects(attacker: Dictionary, target: Dictionary, is_melee: bool, board: Dictionary = {}, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	if not enabled() or attacker.is_empty():
		return out
	# Might of the Moritoi: DREADNOUGHT below starting strength re-rolls hit 1s.
	if unit_has_det(attacker, MORITOI, board) and Common.has_keyword(attacker, "ADEPTUS CUSTODES") \
			and Common.has_keyword(attacker, "DREADNOUGHT") and below_starting_strength(attacker):
		out.append({"kind": "reroll_ones", "source": "Moritoi Ancients", "note": "DREADNOUGHT below its starting strength"})
	var e = enh()
	if e:
		out.append_array(e.hit_effects(attacker, target, is_melee, board, ctx))
	return out

## Wound-roll contributions for one attack batch (strength / toughness are the
## values the resolver uses for the wound threshold).
static func wound_effects(attacker: Dictionary, target: Dictionary, is_melee: bool, strength: int, toughness: int, board: Dictionary = {}, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	if not enabled() or attacker.is_empty():
		return out
	if int(attacker.get("owner", 0)) != int(target.get("owner", -1)) and strength > toughness \
			and is_custodes(target, board) and not group_is_mv(target, board):
		# Aquilan Shield and Shadowkeepers are both 'Unique: Shield Host' — never together.
		if unit_has_det(target, AQUILAN, board) and not is_melee and within_objective_range(target, board):
			out.append({"kind": "minus_one", "source": "Gilded Guardians (Aquilan Shield)", "note": "S %d > T %d, target within range of an objective" % [strength, toughness]})
		elif unit_has_det(target, SHADOWKEEPERS, board) and is_melee and within_objective_range(target, board):
			out.append({"kind": "minus_one", "source": "Wardens of the Dark Cells (Shadowkeepers)", "note": "S %d > T %d, target within range of an objective" % [strength, toughness]})
	if unit_has_det(attacker, HONOURED, board) and group_kw(attacker, "TRUSTED SENTINEL", board) and within_objective_range(attacker, board):
		out.append({"kind": "reroll_ones", "source": "Companion's Watch (Honoured Companions)", "note": "TRUSTED SENTINEL within range of an objective"})
	if unit_has_det(attacker, AURIC_CHAMPIONS, board) and Common.has_keyword(attacker, "ADEPTUS CUSTODES") and is_dreadful_foe_of(target, int(attacker.get("owner", 0)), board) \
			and _attacks_by_character(attacker, board, ctx):
		out.append({"kind": "plus_one", "source": "Assemblage of Might (Auric Champions)", "note": "CHARACTER model's attack vs a dreadful foe"})
	if unit_has_det(attacker, MORITOI, board) and Common.has_keyword(attacker, "ADEPTUS CUSTODES") and Common.has_keyword(attacker, "DREADNOUGHT") \
			and below_half_strength(attacker):
		out.append({"kind": "reroll_ones", "source": "Moritoi Ancients", "note": "DREADNOUGHT below half-strength"})
	var e = enh()
	if e:
		out.append_array(e.wound_effects(attacker, target, is_melee, strength, toughness, board, ctx))
	return out

## True when `target` (any component of its Attached unit) is `player`'s
## dreadful foe.
static func is_dreadful_foe_of(target: Dictionary, player: int, board: Dictionary = {}) -> bool:
	if player <= 0:
		return false
	for gu in group_units(target, board):
		if int(gu.get("flags", {}).get(F_DREADFUL_FOE, 0)) == player:
			return true
	return false

## True when the batch's attacks are made by CHARACTER models: the attacker
## unit is a CHARACTER, or (ranged, Attached unit) every firing model listed in
## ctx.model_ids belongs to an attached CHARACTER component.
static func _attacks_by_character(attacker: Dictionary, board: Dictionary, ctx: Dictionary) -> bool:
	if Common.has_keyword(attacker, "CHARACTER"):
		var mids: Array = ctx.get("model_ids", [])
		for mid in mids:
			if str(mid).find(":") > 0:
				return false
		return true
	var mids2: Array = ctx.get("model_ids", [])
	if mids2.is_empty():
		return false
	var units: Dictionary = _board_or_state(board).get("units", {})
	for mid in mids2:
		var s := str(mid)
		var sep := s.find(":")
		if sep <= 0:
			return false
		if not Common.has_keyword(units.get(s.substr(0, sep), {}), "CHARACTER"):
			return false
	return true

## Melee weapon-ability grants: {sustained: source, lethal: source,
## devastating: source, cleave: int, cleave_source} ("" / 0 = none).
static func melee_weapon_grants(attacker: Dictionary, target: Dictionary, board: Dictionary = {}) -> Dictionary:
	var out := {"sustained": "", "lethal": "", "devastating": "", "cleave": 0, "cleave_source": ""}
	if not enabled() or attacker.is_empty():
		return out
	var mm = _group_flag(attacker, F_MARTIAL_MASTERY, board)
	if mm != null:
		if str(mm) == "sustained":
			out.sustained = "Martial Mastery (Guardians of the Throne)"
		elif str(mm) == "lethal":
			out.lethal = "Martial Mastery (Guardians of the Throne)"
	var e = enh()
	if e:
		var g: Dictionary = e.melee_weapon_grants(attacker, target, board)
		for k in ["sustained", "lethal", "devastating"]:
			if str(out[k]) == "" and str(g.get(k, "")) != "":
				out[k] = str(g[k])
		if int(g.get("cleave", 0)) > int(out.cleave):
			out.cleave = int(g.cleave)
			out.cleave_source = str(g.get("cleave_source", ""))
	return out

## Magna Imperator (Emperor's Chosen): the unit can re-roll one hit roll and
## one wound roll when selected to attack. `kind` "hit" | "wound". True (and
## the use is recorded) when this unit has the re-roll left for this phase.
static func magna_imperator_available(attacker: Dictionary, kind: String, board: Dictionary = {}) -> bool:
	if not enabled() or attacker.is_empty():
		return false
	if not unit_has_det(attacker, EMPERORS_CHOSEN, board) or not Common.has_keyword(attacker, "ADEPTUS CUSTODES"):
		return false
	return not _magna_used.has(_magna_key(attacker, kind, board))

static func magna_imperator_consume(attacker: Dictionary, kind: String, board: Dictionary = {}) -> void:
	_magna_used[_magna_key(attacker, kind, board)] = true

## The Attached unit is one unit: one re-roll for all its components.
static func _magna_key(attacker: Dictionary, kind: String, _board: Dictionary) -> String:
	return "%s|%s|%s" % [Common.head_id(str(attacker.get("id", ""))), stamp(), kind]

## Pick the die to re-roll for Magna Imperator: the first failed roll that was
## not re-rolled already (a dice can only be re-rolled once). -1 = none.
static func magna_pick_index(evals: Array, success_key: String) -> int:
	for i in range(evals.size()):
		var ev = evals[i]
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		if bool(ev.get(success_key, false)) or bool(ev.get("rerolled", false)) or bool(ev.get("auto_fail_locked", false)):
			continue
		return i
	return -1

## RulesEngine ranged hit tally hook: the Auriferous Orb's hits per target
## (BLINDING LIGHT selects "one enemy unit hit by this unit's Auriferous Orb").
static func note_ranged_hits(actor: Dictionary, weapon_id: String, target_unit_id: String, hits: int) -> void:
	if not enabled() or hits <= 0 or weapon_id.to_lower().find("auriferous") < 0:
		return
	var e = enh()
	if e:
		e.note_orb_hits(str(actor.get("id", "")), target_unit_id, hits)

## Range characteristic bonus (inches): Aquilan Shield Favoured SALVUS.
static func range_bonus_inches(actor: Dictionary, weapon_profile: Dictionary = {}) -> float:
	if not enabled() or actor.is_empty():
		return 0.0
	if not weapon_profile.is_empty():
		var wtype := str(weapon_profile.get("type", "Ranged")).to_lower()
		if wtype == "melee" or str(weapon_profile.get("range", "")).to_lower() == "melee":
			return 0.0
	if unit_has_det(actor, AQUILAN) and katah_active(actor, "salvus"):
		return 6.0
	return 0.0

## Best invulnerable save rule effects give `target` against this attack
## (0 = none): Flare Shields 4+ vs ranged, plus the enhancements (Eagle's Eye).
static func invuln_save(target: Dictionary, is_melee: bool, board: Dictionary = {}) -> int:
	var best := 0
	if not enabled() or target.is_empty():
		return 0
	if not is_melee and unit_has_det(target, GRAV_ASSAULT, board) and Common.has_keyword(target, "GRAV-ASSAULT"):
		best = 4
	var e = enh()
	if e:
		var ev := int(e.invuln_save(target, is_melee, board))
		if ev > 0 and (best <= 0 or ev < best):
			best = ev
	return best

## Unconditional Feel No Pain from the enhancements (Genalchemic Warding,
## Augury Uplink: the bearer model 5+). 0 = none.
static func unit_fnp(u: Dictionary) -> int:
	var e = enh()
	return int(e.fnp(u)) if enabled() and e and not u.is_empty() else 0

## The better of an existing invulnerable save and the rule's (0 = none).
static func better_invuln(current: int, target: Dictionary, is_melee: bool, board: Dictionary = {}) -> int:
	var rule := invuln_save(target, is_melee, board)
	if rule <= 0:
		return current
	if current <= 0 or rule < current:
		_log("%s has a %d+ invulnerable save (%s)" % [str(target.get("id", "?")), rule, "codex rule"])
		return rule
	return current

## OC bonus (Might of the Moritoi: DREADNOUGHT at starting strength +2 OC).
static func oc_bonus(u: Dictionary) -> int:
	if not enabled() or u.is_empty():
		return 0
	if unit_has_det(u, MORITOI) and Common.has_keyword(u, "ADEPTUS CUSTODES") and Common.has_keyword(u, "DREADNOUGHT") \
			and Common.is_alive(u) and not below_starting_strength(u):
		return 2
	return 0

## Heralds of the Throne: friendly ADEPTUS CUSTODES units have Fights First.
static func has_fights_first(u: Dictionary) -> bool:
	return enabled() and unit_has_det(u, EMISSARIES) and Common.has_keyword(u, "ADEPTUS CUSTODES")

## Charge re-roll source ("" = none): Dread Host + Combat Deployment.
static func charge_reroll_source(u: Dictionary) -> String:
	if not enabled() or u.is_empty():
		return ""
	if unit_has_det(u, DREAD_HOST) and is_custodes(u):
		return "Instruments of the Emperor's Wrath (Dread Host)"
	var e = enh()
	if e:
		return str(e.charge_reroll_source(u))
	return ""

## Talon Sortie: an ADEPTUS CUSTODES unit's fall-back move does not prevent
## it from being eligible to charge.
static func fall_back_allows_charge(u: Dictionary) -> bool:
	return enabled() and unit_has_det(u, SOLAR_WATCH) and is_custodes(u)

## Fall back and still shoot: Anti-gravitic Mobility (enhancement).
static func fall_back_allows_shoot(u: Dictionary) -> bool:
	var e = enh()
	return enabled() and e != null and bool(e.fall_back_allows_shoot(u))

## Advance and still charge: Sally Forth (enhancement).
static func advance_allows_charge(u: Dictionary) -> bool:
	var e = enh()
	return enabled() and e != null and bool(e.advance_allows_charge(u))

## Move characteristic bonus: Solar Watch Favoured CALISTUS +2" M.
static func move_bonus_inches(u: Dictionary) -> float:
	if not enabled() or u.is_empty():
		return 0.0
	if unit_has_det(u, SOLAR_WATCH) and katah_active(u, "calistus"):
		return 2.0
	return 0.0

## Advance / charge roll modifiers (enhancements: Auric Eagle +1).
static func advance_roll_bonus(u: Dictionary) -> int:
	var e = enh()
	return int(e.advance_roll_bonus(u)) if enabled() and e else 0

static func charge_roll_bonus(u: Dictionary) -> int:
	var e = enh()
	return int(e.charge_roll_bonus(u)) if enabled() and e else 0

## Pile-in / consolidation maximum distance for `unit_id` (base_cap 3"):
## Dread Host Favoured DACATARAI -2" for an enemy unit engaged with a
## Dacatarai unit; Unstoppable Destroyer 4" (enhancement).
static func fight_move_cap(unit_id: String, base_cap: float, board: Dictionary = {}) -> float:
	if not enabled() or unit_id == "":
		return base_cap
	var cap := base_cap
	var e = enh()
	if e:
		cap = float(e.fight_move_cap(unit_id, cap, board))
	var u := Common.unit(unit_id)
	var owner := int(u.get("owner", 0))
	for eid in Common.engaged_enemy_ids(unit_id):
		var eu := Common.unit(str(eid))
		if int(eu.get("owner", 0)) == owner:
			continue
		if unit_has_det(eu, DREAD_HOST) and katah_active(eu, "dacatarai"):
			var before := cap
			cap = maxf(0.0, cap - 2.0)
			_log("Dread Host Favoured Dacatarai: %s is engaged with %s — pile-in / consolidation %.0f\" -> %.0f\"" % [unit_id, str(eid), before, cap])
			break
	return cap

## Favoured CONSERVAI (Emissaries Imperatus): being selected to make an
## advance / fall-back move does not prevent the unit from being eligible to
## start an action (until the end of the turn — the Conservai flag's life).
static func move_keeps_action_eligibility(u: Dictionary) -> bool:
	return enabled() and unit_has_det(u, EMISSARIES) and katah_active(u, "conservai")

# --- Enhancement hooks the engine reaches through this facade ---------------

## Lightning Descent: the bearer's unit can make an ingress move in its
## player's first Movement phase.
static func can_ingress_first_round(u: Dictionary) -> bool:
	var e = enh()
	return enabled() and e != null and not u.is_empty() and bool(e.can_ingress_first_round(u))

## Arae-Shrike: "" or the reason an ingress set-up position is illegal.
static func arae_shrike_violation(arriving_unit_id: String, pos: Vector2, base_radius_px: float) -> String:
	var e = enh()
	if not enabled() or e == null:
		return ""
	return str(e.arae_shrike_violation(arriving_unit_id, pos, base_radius_px))

## Combat Deployment: a disembark from the bearer TRANSPORT (diffs applied).
static func on_unit_disembarked(unit_id: String, transport_id: String) -> Array:
	var e = enh()
	if not enabled() or e == null:
		return []
	return e.on_unit_disembarked(unit_id, transport_id)

## Combat Deployment: enemy units cannot snap-shoot (Fire Overwatch) the unit.
static func blocks_snap_shooting(target: Dictionary) -> bool:
	var e = enh()
	return enabled() and e != null and not target.is_empty() and bool(e.blocks_snap_shooting(target))

## Unstoppable Destroyer: any consolidation mode, regardless of the Before
## Moving restrictions.
static func any_consolidation_mode(unit_id: String) -> bool:
	var e = enh()
	return enabled() and e != null and unit_id != "" and bool(e.any_consolidation_mode(unit_id))

# ===========================================================================
# BATTLELINE grant (Null Maiden Vigil: PROSECUTOR SQUAD)
# ===========================================================================

## Write BATTLELINE into meta.keywords of every PROSECUTOR SQUAD unit of a
## Null Maiden Vigil army (idempotent). Called when the army is applied and at
## the start of each of the player's Command phases. Returns the diffs.
static func apply_keyword_grants(player: int) -> Array:
	var diffs: Array = []
	if not has_det(player, NULL_MAIDEN):
		return diffs
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not _is_prosecutor_squad(u):
			continue
		var kws: Array = u.get("meta", {}).get("keywords", [])
		if "BATTLELINE" in kws:
			continue
		kws.append("BATTLELINE")
		if not u.has("flags"):
			u["flags"] = {}
		u.flags[F_BATTLELINE_GRANT] = rule_name(NULL_MAIDEN)
		diffs.append({"op": "set", "path": "units.%s.meta.keywords" % uid, "value": kws.duplicate()})
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, F_BATTLELINE_GRANT], "value": rule_name(NULL_MAIDEN)})
		_log("Silent Sisterhood — %s (%s) gains BATTLELINE" % [Common.unit_name(str(uid)), uid])
	return diffs

static func _is_prosecutor_squad(u: Dictionary) -> bool:
	if Common.has_keyword(u, "PROSECUTOR SQUAD") or Common.has_keyword(u, "PROSECUTORS"):
		return true
	return str(u.get("meta", {}).get("name", "")).to_lower().begins_with("prosecutor")

# ===========================================================================
# Creeping Dread (Null Maiden Vigil) — Battle-shock step of the OPPONENT's
# Command phase (CommandPhase._identify_units_needing_tests hook)
# ===========================================================================

## Enemy units of `active_player` that must make a battle-shock roll at -1:
## PSYKER units or units below their starting strength within 12" of a friendly
## ANATHEMA PSYKANA unit of a Null Maiden Vigil opponent. Flags them
## (F_CREEPING_DREAD) and returns their ids (heads of Attached units).
static func creeping_dread_units(active_player: int) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var opponent := 2 if active_player == 1 else 1
	if not has_det(opponent, NULL_MAIDEN):
		return out
	var units: Dictionary = Common.state().get("units", {})
	var sources: Array = []
	for sid in units:
		var s: Dictionary = units[sid]
		if int(s.get("owner", 0)) == opponent and Common.has_keyword(s, "ANATHEMA PSYKANA") and Common.is_on_battlefield(s):
			sources.append(s)
	if sources.is_empty():
		return out
	var diffs: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != active_player or not Common.is_on_battlefield(u):
			continue
		if str(u.get("attached_to", "")) != "" and u.get("attached_to", null) != null:
			continue  # an attached CHARACTER tests with its bodyguard
		var grp := group_units(u)
		var psyker := false
		var below := false
		for gu in grp:
			if Common.has_keyword(gu, "PSYKER"):
				psyker = true
		below = below_starting_strength(u)
		if not (psyker or below):
			continue
		var in_range := false
		for s in sources:
			for gu in grp:
				if Common.unit_distance_inches(gu, s) <= CREEPING_DREAD_RANGE_IN + 0.001:
					in_range = true
					break
			if in_range:
				break
		if not in_range:
			continue
		out.append(str(uid))
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(uid), F_CREEPING_DREAD], "value": stamp()})
		_log("Creeping Dread (Silent Sisterhood): %s (%s) is within 12\" of an ANATHEMA PSYKANA unit — battle-shock roll at -1" % [
			Common.unit_name(str(uid)), "PSYKER" if psyker else "below starting strength"])
	if not out.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)
		_event(opponent, "Creeping Dread: %d enemy unit(s) must make a battle-shock roll at -1" % out.size())
	return out

## Battle-shock roll modifier for this Battle-shock step (Creeping Dread -1).
static func battle_shock_roll_modifier(unit_id: String) -> int:
	if not enabled():
		return 0
	if str(Common.unit(unit_id).get("flags", {}).get(F_CREEPING_DREAD, "")) == stamp():
		return -1
	return 0

# ===========================================================================
# Rule offers — StratagemManager / BasePhase / AIDecisionMaker hooks
# ===========================================================================

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

static func is_rule_offer(offer: Dictionary) -> bool:
	return bool(offer.get("cus11e_rule", false)) or is_rule_offer_id(str(offer.get("stratagem_id", "")))

## StratagemManager.get_window_offers hook: the free rule choices (detachment
## rules + enhancements) `player` has in this window.
static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	if not enabled() or player <= 0:
		return out
	match window_id:
		"unit_selected_to_fight":
			out.append_array(_martial_mastery_offers(player, ctx))
		"command_phase_main":
			out.append_array(_dreadful_foe_offers(player, ctx))
		"fight_phase_end":
			out.append_array(_gilded_wings_offers(player, ctx))
	var e = enh()
	if e:
		out.append_array(e.window_offers(player, window_id, ctx))
	if not out.is_empty():
		_log("window %s (P%d): rule offers %s" % [window_id, player, str(out.map(func(o): return str(o.get("name", ""))))])
	return out

static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var res: Dictionary
	match sid:
		RULE_MARTIAL_MASTERY:
			res = _use_martial_mastery(player, target_unit_id, ctx)
		RULE_DREADFUL_FOE:
			res = _use_dreadful_foe(player, target_unit_id)
		RULE_GILDED_WINGS:
			res = _use_gilded_wings(player, target_unit_id)
		_:
			var e = enh()
			if e and e.is_rule_offer_id(sid):
				res = e.use_rule_offer(player, sid, target_unit_id, ctx)
			else:
				res = {"success": false, "error": "unknown Codex: Adeptus Custodes rule offer %s" % sid, "diffs": []}
	if res.get("success", false):
		res["rule_use"] = true
		if not res.has("reopen_window"):
			res["reopen_window"] = true
	return res

## AIDecisionMaker.decide_window_stratagem hook: {} = no rule offer worth
## using (the AI then weighs the window's stratagems). Always synchronous.
static func ai_decide(player: int, window_id: String, offers: Array, ctx: Dictionary) -> Dictionary:
	for offer in offers:
		var sid := str(offer.get("stratagem_id", ""))
		if not is_rule_offer_id(sid):
			continue
		var targets: Array = offer.get("targets", [])
		if targets.is_empty():
			continue
		match sid:
			RULE_MARTIAL_MASTERY:
				var t: Dictionary = targets[0]
				return {"use": true, "stratagem_id": sid, "target_unit_id": str(t.get("unit_id", "")),
					"context": {"variant_id": str(t.get("ai_variant", "sustained"))}, "name": str(offer.get("name", sid))}
			RULE_DREADFUL_FOE:
				var pick := _ai_dreadful_foe_pick(player, targets)
				if pick != "":
					return {"use": true, "stratagem_id": sid, "target_unit_id": pick, "context": {}, "name": str(offer.get("name", sid))}
			RULE_GILDED_WINGS:
				for t in targets:
					var uid := str(t.get("unit_id", ""))
					if _ai_gilded_wings_worth_it(uid):
						return {"use": true, "stratagem_id": sid, "target_unit_id": uid, "context": {}, "name": str(offer.get("name", sid))}
	var e = enh()
	if e:
		var d: Dictionary = e.ai_decide(player, window_id, offers, ctx)
		if not d.is_empty():
			return d
	return {}

# --- Martial Mastery (Guardians of the Throne) ------------------------------

static func _martial_mastery_offers(player: int, ctx: Dictionary) -> Array:
	var uid := str(ctx.get("unit_id", ""))
	if uid == "":
		return []
	var head := Common.head_id(uid)
	var u := Common.unit(head)
	if u.is_empty() or int(u.get("owner", 0)) != player or not has_det(player, GUARDIANS):
		return []
	if not is_custodes(u) or int(Common.current_phase()) != int(GameStateData.Phase.FIGHT):
		return []
	if _group_flag(u, F_MARTIAL_MASTERY) != null:
		return []  # already chosen for this fight
	var label := Common.unit_name(head)
	return [{
		"stratagem_id": RULE_MARTIAL_MASTERY,
		"name": "MARTIAL MASTERY",
		"cp_cost": 0,
		"cus11e_rule": true,
		"rule": true,
		"type": "Detachment rule — Guardians of the Throne (free)",
		"effect_text": "In the Fight phase, when a friendly ADEPTUS CUSTODES unit is selected to fight, that unit's melee attacks have: [SUSTAINED HITS 1]. Or: [LETHAL HITS].",
		"targets": [{"unit_id": head, "label": label, "require_variant": true, "ai_variant": _ai_martial_mastery_variant(head),
			"variants": [
				{"id": "sustained", "label": "[SUSTAINED HITS 1]", "cp_cost": 0},
				{"id": "lethal", "label": "[LETHAL HITS]", "cp_cost": 0},
			]}],
	}]

static func _use_martial_mastery(player: int, unit_id: String, ctx: Dictionary) -> Dictionary:
	var variant := str(ctx.get("variant_id", ""))
	if not variant in ["sustained", "lethal"]:
		return {"success": false, "error": "Martial Mastery: choose [SUSTAINED HITS 1] or [LETHAL HITS]", "diffs": []}
	var head := Common.head_id(unit_id)
	var offers := _martial_mastery_offers(player, {"unit_id": head})
	if offers.is_empty():
		return {"success": false, "error": "Martial Mastery is not available for %s" % unit_id, "diffs": []}
	var diffs := Common.set_flag_diffs(Common.attached_group_ids(head), F_MARTIAL_MASTERY, variant)
	_apply(diffs)
	var msg := "MARTIAL MASTERY — %s's melee attacks have %s this fight" % [Common.unit_name(head), "[SUSTAINED HITS 1]" if variant == "sustained" else "[LETHAL HITS]"]
	_log(msg)
	_event(player, msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Martial Mastery", "message": msg}

## AI: [LETHAL HITS] when the unit's best melee strength is below the toughness
## of the toughest enemy it is engaged with (wounding on 5+ or worse), else
## [SUSTAINED HITS 1] (more hits).
static func _ai_martial_mastery_variant(unit_id: String) -> String:
	var best_s := 0
	var re = Common.rules()
	for gid in Common.attached_group_ids(unit_id):
		for w in Common.unit(str(gid)).get("meta", {}).get("weapons", []):
			if str(w.get("type", "")).to_lower() == "melee":
				best_s = maxi(best_s, int(str(w.get("strength", "0")).to_int()))
	var max_t := 0
	for eid in Common.engaged_enemy_ids(unit_id):
		var eu := Common.unit(str(eid))
		max_t = maxi(max_t, int(eu.get("meta", {}).get("stats", {}).get("toughness", 0)))
	if re and max_t > 0 and best_s > 0 and best_s < max_t:
		return "lethal"
	return "sustained"

# --- Assemblage of Might (Auric Champions) ---------------------------------

static func _dreadful_foe_offers(player: int, _ctx: Dictionary) -> Array:
	if not has_det(player, AURIC_CHAMPIONS) or Common.active_player() != player:
		return []
	if int(Common.current_phase()) != int(GameStateData.Phase.COMMAND):
		return []
	var units: Dictionary = Common.state().get("units", {})
	# Already selected this Command phase: one dreadful foe at a time.
	for uid in units:
		if int(units[uid].get("flags", {}).get(F_DREADFUL_FOE, 0)) == player:
			return []
	var targets: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player or not Common.is_on_battlefield(u):
			continue
		if u.get("attached_to", null) != null and str(u.get("attached_to", "")) != "":
			continue
		targets.append({"unit_id": str(uid), "label": Common.unit_name(str(uid))})
	if targets.is_empty():
		return []
	return [{
		"stratagem_id": RULE_DREADFUL_FOE,
		"name": "ASSEMBLAGE OF MIGHT — select a dreadful foe",
		"cp_cost": 0,
		"cus11e_rule": true,
		"rule": true,
		"type": "Detachment rule — Auric Champions (free)",
		"effect_text": "Select one enemy unit to be a dreadful foe until the start of your next Command phase. Friendly ADEPTUS CUSTODES CHARACTER models' attacks that target a dreadful foe unit have +1 to wound rolls.",
		"targets": targets,
	}]

static func _use_dreadful_foe(player: int, enemy_id: String) -> Dictionary:
	var head := Common.head_id(enemy_id)
	var ok := false
	for o in _dreadful_foe_offers(player, {}):
		for t in o.targets:
			if str(t.unit_id) == head:
				ok = true
	if not ok:
		return {"success": false, "error": "Assemblage of Might: %s cannot be selected as a dreadful foe" % enemy_id, "diffs": []}
	var diffs := Common.set_flag_diffs(Common.attached_group_ids(head), F_DREADFUL_FOE, player)
	_apply(diffs)
	var msg := "ASSEMBLAGE OF MIGHT — %s is a dreadful foe until the start of your next Command phase (CHARACTER attacks +1 to wound)" % Common.unit_name(head)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "Assemblage of Might", "message": msg, "reopen_window": true}

## AI: the enemy unit with the most points per remaining model among those
## closest to the AI's CHARACTER models (within 18" of one, else any).
static func _ai_dreadful_foe_pick(player: int, targets: Array) -> String:
	var chars: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and Common.has_keyword(u, "CHARACTER") and Common.has_keyword(u, "ADEPTUS CUSTODES") and Common.is_on_battlefield(u):
			chars.append(u)
	var best := ""
	var best_score := -INF
	for t in targets:
		var eid := str(t.get("unit_id", ""))
		var e := Common.unit(eid)
		var d := INF
		for c in chars:
			d = minf(d, Common.unit_distance_inches(c, e))
		var pts := float(e.get("meta", {}).get("points", 0))
		var score := pts - (0.0 if d <= 18.0 else 1000.0) - d
		if score > best_score:
			best_score = score
			best = eid
	return best

# --- On Gilded Wings (Lions of the Emperor) ---------------------------------

static func _gilded_wings_offers(player: int, _ctx: Dictionary) -> Array:
	if not has_det(player, LIONS) or Common.active_player() == player:
		return []  # "At the end of your opponent's Fight phase"
	var units: Dictionary = Common.state().get("units", {})
	var targets: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
			continue
		if u.get("attached_to", null) != null and str(u.get("attached_to", "")) != "":
			continue
		if not (is_custodes(u) and group_kw(u, "TERMINATOR")):
			continue
		var engaged := false
		for gid in Common.attached_group_ids(str(uid)):
			if Common.is_engaged(str(gid)):
				engaged = true
		if engaged:
			continue
		targets.append({"unit_id": str(uid), "label": Common.unit_name(str(uid))})
	if targets.is_empty():
		return []
	return [{
		"stratagem_id": RULE_GILDED_WINGS,
		"name": "ON GILDED WINGS",
		"cp_cost": 0,
		"cus11e_rule": true,
		"rule": true,
		"type": "Detachment rule — Lions of the Emperor (free)",
		"effect_text": "At the end of your opponent's Fight phase, if a friendly ADEPTUS CUSTODES TERMINATOR unit is unengaged, you can place that unit in strategic reserves.",
		"targets": targets,
	}]

static func _use_gilded_wings(player: int, unit_id: String) -> Dictionary:
	var head := Common.head_id(unit_id)
	var ok := false
	for o in _gilded_wings_offers(player, {}):
		for t in o.targets:
			if str(t.unit_id) == head:
				ok = true
	if not ok:
		return {"success": false, "error": "On Gilded Wings: %s cannot be placed in strategic reserves now" % unit_id, "diffs": []}
	var diffs := strategic_reserves_diffs(head)
	_apply(diffs)
	var msg := "ON GILDED WINGS — %s is placed in strategic reserves" % Common.unit_name(head)
	_log(msg)
	_event(player, msg)
	_toast(msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "On Gilded Wings", "message": msg}

## 20.02 repositioned unit: the whole Attached unit leaves the battlefield into
## strategic reserves (the FightPhase INSTINCTIVE HUNTERS follow-up shape).
static func strategic_reserves_diffs(unit_id: String) -> Array:
	var diffs: Array = []
	for gid in Common.attached_group_ids(unit_id):
		diffs.append({"op": "set", "path": "units.%s.status" % gid, "value": GameStateData.UnitStatus.IN_RESERVES})
		diffs.append({"op": "set", "path": "units.%s.reserve_type" % gid, "value": "strategic_reserves"})
		diffs.append({"op": "set", "path": "units.%s.flags.repositioned_to_reserves" % gid, "value": true})
		var models: Array = Common.unit(str(gid)).get("models", [])
		for i in range(models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	return diffs

## AI: lift a TERMINATOR unit that is below half-strength, or one that holds
## no objective and has an enemy unit within 9" (it would be charged / shot).
static func _ai_gilded_wings_worth_it(uid: String) -> bool:
	var u := Common.unit(uid)
	if u.is_empty():
		return false
	if below_half_strength(u):
		return true
	if within_objective_range(u):
		return false
	var near := Common.nearest_enemy_inches(u)
	return near <= 9.0

# ===========================================================================
# Lifecycle hooks
# ===========================================================================

## Start of `player`'s Command phase: their dreadful foe expires ("until the
## start of your next Command phase"); BATTLELINE grants refreshed.
static func on_command_phase_start(player: int) -> void:
	if not enabled():
		return
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		if flags.has(F_DREADFUL_FOE) and int(flags.get(F_DREADFUL_FOE, 0)) == player:
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, F_DREADFUL_FOE]})
	if not diffs.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)
		_log("start of P%d's Command phase — dreadful foe expired (%d op(s))" % [player, diffs.size()])
	apply_keyword_grants(player)
	var e = enh()
	if e:
		e.on_command_phase_start(player)

## End of a phase (BasePhase.exit_phase): phase-scoped choices expire.
static func on_phase_end(phase: int) -> void:
	_magna_used.clear()
	if not enabled():
		return
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for uid in units:
		var flags: Dictionary = units[uid].get("flags", {})
		for f in [F_MARTIAL_MASTERY, F_SK_KAPTARIS, F_CREEPING_DREAD]:
			if flags.has(f):
				diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [uid, f]})
	if not diffs.is_empty():
		var gs = Common.game_state()
		if gs and gs.has_method("apply_state_changes"):
			gs.apply_state_changes(diffs)
		_log("end of phase %d — %d phase-scoped detachment flag op(s) cleared" % [phase, diffs.size()])
	var e = enh()
	if e:
		e.on_phase_end(phase)
