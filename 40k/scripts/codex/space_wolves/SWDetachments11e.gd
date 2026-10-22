extends RefCounted

## SWDetachments11e — Codex: Space Marines (11e), the three Space Wolves
## DETACHMENT RULES (WP-S2), and the façade the engine hooks call for the
## Space Wolves detachment rules + enhancements (SWEnhancements11e.gd is
## loaded lazily by path and folded in here, like CustodesDetachments).
##
## Source: .llm/codex_11e_wahapedia/space-marines/SPACE_WOLVES.md. Rulings:
## RULINGS.md § WP-S2. Every rule is active while the player took that
## detachment (11e armies can take several — ArmyDetachments11e).
##
##  CHAMPIONS OF FENRIS — THE GREAT WOLF WATCHES: friendly ADEPTUS ASTARTES
##   CHARACTER units have Countercharge: (once per battle round, per unit)
##   targeting the unit with HEROIC INTERVENTION is -1CP.
##   stratagem_cp_discount() / record_cp_discount() (StratagemManager hooks).
##  SAGA OF THE BEASTSLAYER — LEGENDARY SLAYERS: attacks by friendly Blood
##   Claws / Thunderwolf Cavalry / Wulfen units have [LETHAL HITS:
##   CHARACTER/MONSTER/VEHICLE]. merge_attack_mods() (RulesEngine aggregator).
##  SAGA OF THE GREAT WOLF — MASTER OF WOLVES: friendly ADEPTUS ASTARTES units
##   (excluding MONSTER / VEHICLE) — Encircling Jaws (assault doctrine: +1 to
##   advance and charge rolls), Hunter's Eye (devastator: ranged re-roll hit
##   rolls of 1), Ferocious Strike (tactical: attacks vs a target within 9"
##   have [SUSTAINED HITS 1]). Logan Grimnar's HOWLING ONSLAUGHT (once per
##   battle, your Command phase): MONSTER / VEHICLE units benefit too until the
##   start of your next Command phase. Restriction: no ADEPTUS ASTARTES unit of
##   another Chapter (validate_army).

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")

const ENHANCEMENTS_PATH := "res://scripts/codex/space_wolves/SWEnhancements11e.gd"
const ARMY_RULES_PATH := "res://scripts/codex/space_wolves/SWArmyRules11e.gd"

const CHAMPIONS := "champions of fenris"
const BEASTSLAYER := "saga of the beastslayer"
const GREAT_WOLF := "saga of the great wolf"

const RULE_NAMES := {
	CHAMPIONS: "The Great Wolf Watches",
	BEASTSLAYER: "Legendary Slayers",
	GREAT_WOLF: "Master of Wolves",
}

const SLAYER_KEYWORDS := ["BLOOD CLAWS", "THUNDERWOLF CAVALRY", "WULFEN"]
const SLAYER_TARGET_KEYWORDS := ["CHARACTER", "MONSTER", "VEHICLE"]
const FEROCIOUS_STRIKE_RANGE_IN := 9.0

## Countercharge used: battle round, on the (head) unit.
const F_COUNTERCHARGE_ROUND := "sw11e_countercharge_round"
## state.factions[p] keys — Howling Onslaught.
const FK_HOWLING_USED := "sw11e_howling_onslaught_used"
const FK_HOWLING_ROUND := "sw11e_howling_onslaught_round"   # round it was used; 0 / absent = not active

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func det_key(name: String) -> String:
	return ArmyDets.det_key(name)

static func detachments_of(player: int) -> Array:
	if not enabled() or player <= 0:
		return []
	return ArmyDets.player_detachment_keys(player, Common.state())

static func has_det(player: int, det: String) -> bool:
	return det in detachments_of(player)

static func unit_has_det(u: Dictionary, det: String) -> bool:
	return not u.is_empty() and has_det(int(u.get("owner", 0)), det) and Common.is_sw_army(int(u.get("owner", 0)))

static func enh():
	if not ResourceLoader.exists(ENHANCEMENTS_PATH):
		return null
	return load(ENHANCEMENTS_PATH)

static func army_rules():
	return load(ARMY_RULES_PATH)

static func _log(msg: String) -> void:
	Common.log_info("[SWDetachments11e] " + msg)

static func _faction(player: int) -> Dictionary:
	var f = Common.state().get("factions", {}).get(str(player), {})
	return f if f is Dictionary else {}

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

static func group_is_mv(u: Dictionary) -> bool:
	return group_kw(u, "MONSTER") or group_kw(u, "VEHICLE")

## Distance (inches) between two (Attached) units, edge to edge.
static func _group_distance(a: Dictionary, b: Dictionary) -> float:
	var am: Array = []
	for gu in group_units(a):
		am.append_array(gu.get("models", []))
	var bm: Array = []
	for gu in group_units(b):
		bm.append_array(gu.get("models", []))
	return Common.unit_distance_inches({"models": am}, {"models": bm})

# ===========================================================================
# CHAMPIONS OF FENRIS — The Great Wolf Watches (Countercharge)
# ===========================================================================

## Countercharge discount for this stratagem use: {discount: 1, source,
## head_id} or {} (StratagemManager can_use_stratagem / use_stratagem hooks).
## An Attached unit that includes an ADEPTUS ASTARTES CHARACTER is an
## ADEPTUS ASTARTES CHARACTER unit (keyword checks see the whole unit).
static func stratagem_cp_discount(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	if not enabled() or target_unit_id == "":
		return {}
	if stratagem_id.replace("_11e", "") != "heroic_intervention":
		return {}
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player or not unit_has_det(u, CHAMPIONS):
		return {}
	if not (group_kw(u, "ADEPTUS ASTARTES") and group_kw(u, "CHARACTER")):
		return {}
	var head := Common.head_id(target_unit_id)
	for gu in group_units(Common.unit(head)):
		if int(gu.get("flags", {}).get(F_COUNTERCHARGE_ROUND, -1)) == Common.battle_round():
			return {}
	return {"discount": 1, "source": "Countercharge (The Great Wolf Watches)", "head_id": head}

static func record_cp_discount(disc: Dictionary) -> Array:
	if disc.is_empty():
		return []
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [str(disc.head_id), F_COUNTERCHARGE_ROUND], "value": Common.battle_round()}]
	Common.apply_diffs(diffs)
	_log("Countercharge: HEROIC INTERVENTION on %s is -1CP (once this battle round)" % Common.unit_name(str(disc.head_id)))
	Common.game_log(int(Common.unit(str(disc.head_id)).get("owner", 0)), "Countercharge (The Great Wolf Watches): Heroic Intervention on %s costs 1CP less" % Common.group_label(str(disc.head_id)))
	return diffs

## Grimnar's Mark (enhancement): the "regardless of other uses" override,
## same shape as CustodesEnhancements.stratagem_override (+ sw11e: true).
static func stratagem_override(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	var e = enh()
	if e == null or not enabled():
		return {"applies": false}
	return e.stratagem_override(player, stratagem_id, target_unit_id)

static func record_stratagem_override(ov: Dictionary) -> Array:
	var e = enh()
	return e.record_stratagem_override(ov) if e else []

# ===========================================================================
# SAGA OF THE GREAT WOLF — Master of Wolves / Howling Onslaught
# ===========================================================================

static func howling_onslaught_active(player: int) -> bool:
	return int(_faction(player).get(FK_HOWLING_ROUND, 0)) > 0

## True when the unit benefits from Master of Wolves: Saga of the Great Wolf,
## ADEPTUS ASTARTES, excluding MONSTER / VEHICLE units (unless Howling
## Onslaught is active for its army).
static func has_master_of_wolves(u: Dictionary) -> bool:
	if not enabled() or u.is_empty() or not unit_has_det(u, GREAT_WOLF):
		return false
	if not group_kw(u, "ADEPTUS ASTARTES"):
		return false
	if group_is_mv(u) and not howling_onslaught_active(int(u.get("owner", 0))):
		return false
	return true

static func _doctrine(u: Dictionary, d: String) -> bool:
	return bool(army_rules().group_doctrine_active(u, d))

## Encircling Jaws (assault doctrine): +1 to advance rolls.
static func advance_roll_bonus(u: Dictionary) -> int:
	var b := 0
	if has_master_of_wolves(u) and _doctrine(u, "assault"):
		b += 1
	return b

## Encircling Jaws (assault doctrine): +1 to charge rolls.
static func charge_roll_bonus(u: Dictionary) -> int:
	var b := 0
	if has_master_of_wolves(u) and _doctrine(u, "assault"):
		b += 1
	return b

static func encircling_jaws_source(u: Dictionary) -> String:
	return "Encircling Jaws (Master of Wolves)" if advance_roll_bonus(u) > 0 else ""

## Logan Grimnar's Howling Onslaught: offered in `player`'s Command phase,
## once per battle, while a LOGAN GRIMNAR unit is on the battlefield.
static func howling_onslaught_available(player: int) -> bool:
	if not enabled() or not has_det(player, GREAT_WOLF) or not Common.is_sw_army(player):
		return false
	if Common.current_phase() != int(GameStateData.Phase.COMMAND) or Common.active_player() != player:
		return false
	if bool(_faction(player).get(FK_HOWLING_USED, false)):
		return false
	return logan_id(player) != ""

static func logan_id(player: int) -> String:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and Common.has_keyword(u, "LOGAN GRIMNAR") and Common.is_on_battlefield(u):
			return str(uid)
	return ""

static func command_actions(player: int) -> Array:
	if not howling_onslaught_available(player):
		return []
	return [{"type": "USE_HOWLING_ONSLAUGHT", "player": player, "sw11e": true,
		"description": "Howling Onslaught (Logan Grimnar, once per battle): MONSTER / VEHICLE units benefit from Master of Wolves until your next Command phase"}]

static func use_howling_onslaught_diffs(player: int) -> Dictionary:
	if not howling_onslaught_available(player):
		return {"success": false, "error": "Howling Onslaught is not available (Saga of the Great Wolf, Logan Grimnar on the battlefield, once per battle, your Command phase)", "diffs": []}
	var p := str(player)
	var diffs: Array = [
		{"op": "set", "path": "factions.%s.%s" % [p, FK_HOWLING_USED], "value": true},
		{"op": "set", "path": "factions.%s.%s" % [p, FK_HOWLING_ROUND], "value": Common.battle_round()},
	]
	var msg := "Howling Onslaught (%s): friendly ADEPTUS ASTARTES MONSTER / VEHICLE units benefit from Master of Wolves until the start of your next Command phase" % Common.unit_name(logan_id(player))
	_log("P%d uses %s" % [player, msg])
	return {"success": true, "diffs": diffs, "message": msg}

## AI: use Howling Onslaught once the army has a doctrine running and an
## ADEPTUS ASTARTES MONSTER / VEHICLE unit on the battlefield.
static func ai_command_action(player: int) -> Dictionary:
	if not howling_onslaught_available(player):
		return {}
	if str(army_rules().army_doctrine(player)) == "":
		return {}
	for uid in Common.friendly_heads(player):
		var u := Common.unit(uid)
		if Common.has_keyword(u, "ADEPTUS ASTARTES") and Common.is_monster_or_vehicle(u):
			return {"type": "USE_HOWLING_ONSLAUGHT", "_ai_description": "Howling Onslaught: %s benefits from Master of Wolves" % Common.unit_name(uid)}
	return {}

## Start of `player`'s Command phase: Howling Onslaught ends (it lasted until
## the start of this Command phase). Re-entering the phase it was used in
## keeps it. Applies the diffs itself.
static func on_command_phase_start(player: int) -> Array:
	var diffs: Array = []
	if not enabled():
		return diffs
	var rnd := int(_faction(player).get(FK_HOWLING_ROUND, 0))
	if rnd > 0 and rnd != Common.battle_round():
		diffs.append({"op": "set", "path": "factions.%s.%s" % [str(player), FK_HOWLING_ROUND], "value": 0})
		Common.apply_diffs(diffs)
		_log("start of P%d's Command phase — Howling Onslaught ended" % player)
	var e = enh()
	if e:
		e.on_command_phase_start(player)
	return diffs

## Command panel block (CommandController hook, below the doctrines).
static func build_command_ui(section: VBoxContainer, player: int, emit: Callable) -> void:
	if not enabled() or not has_det(player, GREAT_WOLF) or not Common.is_sw_army(player):
		return
	if logan_id(player) == "" and not howling_onslaught_active(player):
		return
	var lbl := Label.new()
	lbl.name = "SW11eHowlingStatus"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if howling_onslaught_active(player):
		lbl.text = "HOWLING ONSLAUGHT active: MONSTER / VEHICLE units benefit from Master of Wolves"
		lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		section.add_child(lbl)
		return
	if not howling_onslaught_available(player):
		return
	var btn := Button.new()
	btn.name = "SW11eHowlingOnslaughtButton"
	btn.text = "HOWLING ONSLAUGHT (Logan Grimnar)"
	btn.tooltip_text = "Once per battle: friendly ADEPTUS ASTARTES MONSTER / VEHICLE units benefit from the Master of Wolves rule until the start of your next Command phase."
	btn.custom_minimum_size = Vector2(230, 30)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func(): emit.call({"type": "USE_HOWLING_ONSLAUGHT", "player": player}))
	section.add_child(btn)

# ===========================================================================
# Attack modifiers (RulesEngine.ork11e_ab_mods aggregator — every attack path)
# ===========================================================================

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

## Fold the Space Wolves detachment rules + enhancements into the shared
## datasheet-ability modifier dict (keys of OrkAbilities11e._empty_mods).
static func merge_attack_mods(m: Dictionary, actor: Dictionary, target: Dictionary, weapon_profile: Dictionary, is_melee: bool, board: Dictionary = {}, bearer_ids: Array = []) -> void:
	if not enabled() or actor.is_empty():
		return
	var owner := int(actor.get("owner", 0))
	if owner <= 0 or not Common.is_sw_army(owner):
		return
	# Legendary Slayers: [LETHAL HITS: CHARACTER/MONSTER/VEHICLE].
	if unit_has_det(actor, BEASTSLAYER) and not target.is_empty() and not bool(m.get("lethal", false)):
		var slayer := false
		for kw in SLAYER_KEYWORDS:
			if group_kw(actor, kw):
				slayer = true
		var tgt_ok := false
		for kw in SLAYER_TARGET_KEYWORDS:
			if group_kw(target, kw):
				tgt_ok = true
		if slayer and tgt_ok:
			m["lethal"] = true
			_src(m, "Legendary Slayers (Saga of the Beastslayer)", "other", "lethal_hits", "[LETHAL HITS: CHARACTER/MONSTER/VEHICLE] vs %s" % str(target.get("id", "?")))
	if has_master_of_wolves(actor):
		# Hunter's Eye: devastator doctrine — ranged attacks re-roll hit rolls of 1.
		if not is_melee and _doctrine(actor, "devastator"):
			var rank := {"": 0, "ones": 1, "failed": 2}
			if int(rank.get(str(m.get("hit_reroll", "")), 0)) < 1:
				m["hit_reroll"] = "ones"
			_src(m, "Hunter's Eye (Master of Wolves)", "hit", "reroll_ones", "devastator doctrine — ranged hit rolls of 1")
		# Ferocious Strike: tactical doctrine — attacks vs a target within 9" have [SUSTAINED HITS 1].
		if _doctrine(actor, "tactical") and not target.is_empty():
			var dist := _group_distance(actor, target)
			if dist <= FEROCIOUS_STRIKE_RANGE_IN + 0.001:
				m["sustained"] = maxi(int(m.get("sustained", 0)), 1)
				_src(m, "Ferocious Strike (Master of Wolves)", "other", "sustained_hits_1", "tactical doctrine — target %.1f\" away" % dist)
	var e = enh()
	if e:
		e.merge_attack_mods(m, actor, target, weapon_profile, is_melee, board, bearer_ids)

## Melee [LANCE] grant (Skjald's Foretelling) — RulesEngine melee hook.
static func melee_lance_source(attacker: Dictionary) -> String:
	var e = enh()
	return str(e.melee_lance_source(attacker)) if e and enabled() else ""

# ===========================================================================
# Movement / charge hooks (façade over the enhancements)
# ===========================================================================

## Charge re-roll source ("" = none): Preyslayer.
static func charge_reroll_source(u: Dictionary) -> String:
	var e = enh()
	return str(e.charge_reroll_source(u)) if e and enabled() else ""

## Move characteristic bonus: Wolf-Touched +2" M.
static func move_bonus_inches(u: Dictionary) -> float:
	var e = enh()
	return float(e.move_bonus_inches(u)) if e and enabled() else 0.0

# ===========================================================================
# Rule offers in stratagem windows (Howlmaw) — StratagemManager / AI hooks
# ===========================================================================

const RULE_PREFIX := "sw11e_rule_"

static func is_rule_offer_id(sid: String) -> bool:
	return sid.begins_with(RULE_PREFIX)

static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var e = enh()
	if e == null or not enabled() or not Common.is_sw_army(player):
		return []
	return e.window_offers(player, window_id, ctx)

static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var e = enh()
	var res: Dictionary = e.use_rule_offer(player, sid, target_unit_id, ctx) if e else {"success": false, "error": "no SW enhancement module", "diffs": []}
	if res.get("success", false):
		res["rule_use"] = true
		if not res.has("reopen_window"):
			res["reopen_window"] = true
	return res

static func ai_decide(player: int, window_id: String, offers: Array, ctx: Dictionary) -> Dictionary:
	var e = enh()
	if e == null or not enabled():
		return {}
	return e.ai_decide(player, window_id, offers, ctx)

# ===========================================================================
# Army construction — Master of Wolves restriction
# ===========================================================================

## Saga of the Great Wolf: "Your army can include SPACE WOLVES units, but it
## cannot include any ADEPTUS ASTARTES units drawn from any other Chapter."
## A generic Codex: Space Marines datasheet (no chapter keyword) is allowed.
static func validate_army(army_data: Dictionary) -> Dictionary:
	var out := {"errors": [], "warnings": []}
	if not enabled():
		return out
	var dets: Array = []
	for n in ArmyDets.names_from_army(army_data):
		dets.append(det_key(str(n)))
	if not GREAT_WOLF in dets:
		return out
	var ar = army_rules()
	for uid in army_data.get("units", {}):
		var u = army_data.units[uid]
		if not u is Dictionary:
			continue
		var ch := str(ar.other_chapter_keyword(u))
		if ch != "":
			out.errors.append("Master of Wolves (Saga of the Great Wolf): the army cannot include ADEPTUS ASTARTES units of another Chapter — %s (%s) is %s" % [str(u.get("meta", {}).get("name", uid)), uid, ch])
	return out

static func live_army_problems(player: int) -> Array:
	var out: Array = []
	if not enabled() or not has_det(player, GREAT_WOLF):
		return out
	var ar = army_rules()
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player:
			continue
		var ch := str(ar.other_chapter_keyword(u))
		if ch != "":
			out.append("Master of Wolves (Saga of the Great Wolf): %s is a %s unit — not allowed in this army" % [Common.unit_name(str(uid)), ch])
	return out
