extends RefCounted

## SWEnhancements11e — the 8 Codex: Space Marines (11e) Space Wolves
## ENHANCEMENTS (WP-S2). Source: .llm/codex_11e_wahapedia/space-marines/
## SPACE_WOLVES.md; rulings: RULINGS.md § WP-S2.
##
## The engine hooks reach this module through the SWDetachments11e façade,
## except the list-build pass (ArmyListManager), the leader extras
## (CharacterAttachmentManager) and the redeploy table (FactionAbilityManager).
## Every runtime effect is gated on the owner having taken the enhancement's
## detachment (an enhancement is "gated to the owning detachment").
##
##  Champions of Fenris
##   Preyslayer             the bearer's unit can re-roll charge rolls
##   A Giant Amongst Giants +2 W (list build); this model's melee attacks +1 S
##  Saga of the Beastslayer
##   Hunter's Guile         redeploy up to three Blood Claws / Thunderwolf
##                          Cavalry / Wulfen units (redeploy table — engine /
##                          AI side only: the Redeployment step has no player
##                          controls, a known gap shared with Razgit's Magik
##                          Map / Castellan's Mark / Kaptin's Hat)
##   Wolf-Touched           the bearer's unit has WULFEN (keyword; the bearer
##                          can lead Wulfen INFANTRY units) and +2" M
##  Saga of the Great Wolf
##   Howlmaw                once per turn: start of the Fight phase, an enemy
##                          unit within 6" of the bearer makes a battle-shock
##                          roll at -1 (fight_phase_start rule card)
##   Grimnar's Mark         once per battle round per army: RAPID INGRESS /
##                          HEROIC INTERVENTION on this unit regardless of other
##                          uses, -1CP, does not count for other units
##   Chariots of the Storm  redeploy up to three ADEPTUS ASTARTES units (as
##                          Hunter's Guile)
##   Skjald's Foretelling   the bearer's unit's melee attacks have [LANCE]

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")
const ArmyDets = preload("res://scripts/codex/ArmyDetachments11e.gd")

const PREYSLAYER := "preyslayer"
const GIANT := "a giant amongst giants"
const HUNTERS_GUILE := "hunter's guile"
const WOLF_TOUCHED := "wolf-touched"
const HOWLMAW := "howlmaw"
const GRIMNARS_MARK := "grimnar's mark"
const CHARIOTS := "chariots of the storm"
const SKJALD := "skjald's foretelling"

const ENHANCEMENTS := {
	PREYSLAYER: {"detachment": "champions of fenris", "name": "Preyslayer"},
	GIANT: {"detachment": "champions of fenris", "name": "A Giant Amongst Giants"},
	HUNTERS_GUILE: {"detachment": "saga of the beastslayer", "name": "Hunter's Guile"},
	WOLF_TOUCHED: {"detachment": "saga of the beastslayer", "name": "Wolf-Touched"},
	HOWLMAW: {"detachment": "saga of the great wolf", "name": "Howlmaw"},
	GRIMNARS_MARK: {"detachment": "saga of the great wolf", "name": "Grimnar's Mark"},
	CHARIOTS: {"detachment": "saga of the great wolf", "name": "Chariots of the Storm"},
	SKJALD: {"detachment": "saga of the great wolf", "name": "Skjald's Foretelling"},
}

const GIANT_WOUNDS := 2
const GIANT_MELEE_S := 1
const WOLF_TOUCHED_MOVE_IN := 2.0
const HOWLMAW_RANGE_IN := 6.0

const RULE_HOWLMAW := "sw11e_rule_enh_howlmaw"

## Flags (no effect_ prefix — they must outlive the Shooting-phase wipe).
## Howlmaw used this turn (on the bearer): "<round>:<active player>".
const F_HOWLMAW_TURN := "sw11e_howlmaw_turn"
## Grimnar's Mark used (once per battle round, per army): battle round, on the bearer.
const F_GRIMNARS_MARK_ROUND := "sw11e_grimnars_mark_round"
## List-build markers (idempotent): sw11e_listbuild_<slug>.
const F_LISTBUILD_PREFIX := "sw11e_listbuild_"

const SLAYER_KEYWORDS := ["BLOOD CLAWS", "THUNDERWOLF CAVALRY", "WULFEN"]

# ===========================================================================
# Basics
# ===========================================================================

static func enabled() -> bool:
	return int(GameConstants.edition) >= 11

static func enh_key(name: String) -> String:
	var k := name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()
	for suffix in [" (one per army)", " (upgrade)"]:
		if k.ends_with(suffix):
			k = k.substr(0, k.length() - suffix.length()).strip_edges()
	return k

static func display_name(key: String) -> String:
	return str(ENHANCEMENTS.get(key, {}).get("name", key))

static func is_sw_enhancement(name: String) -> bool:
	return ENHANCEMENTS.has(enh_key(name))

static func _log(msg: String) -> void:
	Common.log_info("[SWEnhancements11e] " + msg)

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

## The owner took the enhancement's detachment (and is a Space Wolves army).
static func _owner_has_det(u: Dictionary, key: String) -> bool:
	var owner := int(u.get("owner", 0))
	if owner <= 0 or not Common.is_sw_army(owner):
		return false
	return str(ENHANCEMENTS[key].detachment) in ArmyDets.player_detachment_keys(owner, Common.state())

## True when THIS unit dict carries the enhancement and its detachment is active.
static func has(u: Dictionary, key: String) -> bool:
	return enabled() and not u.is_empty() and key in unit_enhancements(u) and _owner_has_det(u, key)

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

## The component of the (Attached) unit that bears `key` ({} = none).
static func group_bearer(u: Dictionary, key: String) -> Dictionary:
	if not enabled() or u.is_empty():
		return {}
	for gu in group_units(u):
		if has(gu, key):
			return gu
	return {}

static func bearers(player: int, key: String) -> Array:
	var out: Array = []
	if not enabled():
		return out
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and has(u, key):
			out.append(u)
	return out

static func _turn_stamp() -> String:
	return "%d:%d" % [Common.battle_round(), Common.active_player()]

# ===========================================================================
# List build (ArmyListManager hook): A Giant Amongst Giants +2 W,
# Wolf-Touched grants the WULFEN keyword. Idempotent.
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
	for key in unit_enhancements(unit):
		if not ENHANCEMENTS.has(key):
			continue
		if not dets.is_empty() and not str(ENHANCEMENTS[key].detachment) in dets:
			lines.append("%s on %s: not applied — the army did not take %s" % [display_name(key), unit_id, str(ENHANCEMENTS[key].detachment)])
			continue
		var done: String = F_LISTBUILD_PREFIX + str(key).replace(" ", "_").replace("'", "").replace("-", "_")
		if bool(unit.flags.get(done, false)):
			continue
		match key:
			GIANT:
				var meta: Dictionary = unit.meta
				if meta.has("stats") and meta.stats.has("wounds"):
					meta.stats["wounds"] = int(meta.stats["wounds"]) + GIANT_WOUNDS
				for m in unit.get("models", []):
					var old_w := int(m.get("wounds", 1))
					var full: bool = int(m.get("current_wounds", old_w)) >= old_w
					m["wounds"] = old_w + GIANT_WOUNDS
					if full:
						m["current_wounds"] = m["wounds"]
				unit.flags[done] = true
				lines.append("A Giant Amongst Giants on %s: wounds +%d" % [unit_id, GIANT_WOUNDS])
			WOLF_TOUCHED:
				var kws: Array = unit.meta.get("keywords", [])
				if not "WULFEN" in kws:
					kws.append("WULFEN")
					unit.meta["keywords"] = kws
				unit.flags[done] = true
				lines.append("Wolf-Touched on %s: has the WULFEN keyword (+2\" M at runtime)" % unit_id)
	for l in lines:
		_log(str(l))
	return lines

# ===========================================================================
# Attack modifiers (via SWDetachments11e.merge_attack_mods)
# ===========================================================================

static func _src(m: Dictionary, name: String, kind: String, effect: String, note: String = "") -> void:
	if not m.has("sources"):
		m["sources"] = []
	(m["sources"] as Array).append({"name": name, "kind": kind, "effect": effect, "note": note})

static func merge_attack_mods(m: Dictionary, actor: Dictionary, _target: Dictionary, _weapon_profile: Dictionary, is_melee: bool, _board: Dictionary = {}, _bearer_ids: Array = []) -> void:
	if not enabled() or actor.is_empty():
		return
	# A Giant Amongst Giants: "This model's melee attacks have +1 S" — the
	# bearer's own unit id (an attached CHARACTER resolves its attacks as its
	# own unit), so only the bearer's attacks.
	if is_melee and has(actor, GIANT):
		m["strength"] = int(m.get("strength", 0)) + GIANT_MELEE_S
		_src(m, "A Giant Amongst Giants", "other", "strength", "the bearer's melee attacks +%d S" % GIANT_MELEE_S)

## Skjald's Foretelling: "This unit's melee attacks have [Lance]" — every
## component of the bearer's (Attached) unit.
static func melee_lance_source(attacker: Dictionary) -> String:
	if not group_bearer(attacker, SKJALD).is_empty():
		return "Skjald's Foretelling"
	return ""

# ===========================================================================
# Movement / charge
# ===========================================================================

## Preyslayer: "This unit can re-roll charge rolls."
static func charge_reroll_source(u: Dictionary) -> String:
	if not group_bearer(u, PREYSLAYER).is_empty():
		return "Preyslayer"
	return ""

## Wolf-Touched: "This unit has ... +2\" M" — the bearer's (Attached) unit.
static func move_bonus_inches(u: Dictionary) -> float:
	if not group_bearer(u, WOLF_TOUCHED).is_empty():
		return WOLF_TOUCHED_MOVE_IN
	return 0.0

## Wolf-Touched: the bearer can lead Wulfen units (40kdc attachment_bodyguard_ids
## wulfen / wulfen-with-storm-shields) — CharacterAttachmentManager extras.
static func leader_extras(character: Dictionary) -> Array:
	if has(character, WOLF_TOUCHED):
		return ["WULFEN"]
	return []

## Only Wulfen INFANTRY units qualify through Wolf-Touched (the WULFEN keyword
## is also on Murderfang / Wulfen Dreadnoughts). "" = no objection.
static func attach_block_reason(character: Dictionary, bodyguard: Dictionary) -> String:
	if not has(character, WOLF_TOUCHED) or not Common.has_keyword(bodyguard, "WULFEN"):
		return ""
	var native: Array = character.get("meta", {}).get("leader_data", {}).get("can_lead", [])
	for kw in native:
		if str(kw).to_upper() != "WULFEN" and Common.has_keyword(bodyguard, str(kw)):
			return ""
	if Common.has_keyword(bodyguard, "VEHICLE") or not Common.has_keyword(bodyguard, "INFANTRY"):
		return "Wolf-Touched only lets the bearer lead Wulfen INFANTRY units (Wulfen, Wulfen with Storm Shields)"
	return ""

# ===========================================================================
# Redeploy (FactionAbilityManager.get_redeploy_enhancement hook)
# ===========================================================================

## The redeploy-table entry `player` owns ({} = none). "any_keywords": the
## unit must have one of them (Blood Claws / Thunderwolf Cavalry / Wulfen).
## A player with both: Chariots of the Storm (it covers every unit Hunter's
## Guile does) — one redeploy budget (ruling).
static func redeploy_enhancement(player: int) -> Dictionary:
	if not enabled():
		return {}
	if not bearers(player, CHARIOTS).is_empty():
		return {"name": "Chariots of the Storm", "keywords": ["ADEPTUS ASTARTES"]}
	if not bearers(player, HUNTERS_GUILE).is_empty():
		return {"name": "Hunter's Guile", "keywords": ["ADEPTUS ASTARTES"], "any_keywords": SLAYER_KEYWORDS.duplicate()}
	return {}

# ===========================================================================
# Grimnar's Mark (StratagemManager override through SWDetachments11e)
# ===========================================================================

static func stratagem_override(player: int, stratagem_id: String, target_unit_id: String) -> Dictionary:
	var none := {"applies": false}
	if not enabled() or target_unit_id == "":
		return none
	var sid := stratagem_id.replace("_11e", "")
	if sid != "rapid_ingress" and sid != "heroic_intervention":
		return none
	var u := Common.unit(target_unit_id)
	if u.is_empty() or int(u.get("owner", 0)) != player:
		return none
	var b := group_bearer(u, GRIMNARS_MARK)
	if b.is_empty():
		return none
	# (Once per battle round, per army)
	for bb in bearers(player, GRIMNARS_MARK):
		if int(bb.get("flags", {}).get(F_GRIMNARS_MARK_ROUND, -1)) == Common.battle_round():
			return none
	return {"applies": true, "sw11e": true, "source": "Grimnar's Mark", "cost_delta": -1,
		"flag": F_GRIMNARS_MARK_ROUND, "bearer_id": str(b.get("id", "")), "value": Common.battle_round()}

static func record_stratagem_override(ov: Dictionary) -> Array:
	if not bool(ov.get("applies", false)):
		return []
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [str(ov.bearer_id), str(ov.flag)], "value": ov.get("value", Common.battle_round())}]
	Common.apply_diffs(diffs)
	_log("%s: stratagem use at -1CP that does not prevent other uses this phase" % str(ov.source))
	Common.game_log(int(Common.unit(str(ov.bearer_id)).get("owner", 0)), "Grimnar's Mark (%s): stratagem -1CP, regardless of other uses this phase" % Common.unit_name(str(ov.bearer_id)))
	return diffs

# ===========================================================================
# Howlmaw — fight_phase_start rule card
# ===========================================================================

static func _offer(sid: String, name: String, type_text: String, effect: String, targets: Array) -> Dictionary:
	return {"stratagem_id": sid, "name": name, "cp_cost": 0, "sw11e_rule": true, "rule": true,
		"type": type_text, "effect_text": effect, "targets": targets}

static func window_offers(player: int, window_id: String, _ctx: Dictionary) -> Array:
	var out: Array = []
	if not enabled():
		return out
	match window_id:
		"fight_phase_start":
			out.append_array(_howlmaw_offers(player))
	return out

static func _howlmaw_offers(player: int) -> Array:
	if int(Common.current_phase()) != int(GameStateData.Phase.FIGHT):
		return []
	var targets: Array = []
	var units: Dictionary = Common.state().get("units", {})
	for b in bearers(player, HOWLMAW):
		if not Common.is_on_battlefield(b) or str(b.get("flags", {}).get(F_HOWLMAW_TURN, "")) == _turn_stamp():
			continue
		var opts: Array = []
		for eid in units:
			var e: Dictionary = units[eid]
			if int(e.get("owner", 0)) == player or int(e.get("owner", 0)) == 0 or not Common.is_on_battlefield(e):
				continue
			# One row per enemy unit: an attached CHARACTER is part of its bodyguard's unit.
			if e.get("attached_to", null) != null and str(e.get("attached_to", "")) != "":
				continue
			# "within 6\" of this model" — the bearer model to any model of the enemy unit.
			var d := INF
			for gid in Common.attached_group_ids(str(eid)):
				d = minf(d, Common.unit_distance_inches(b, Common.unit(str(gid))))
			if d > HOWLMAW_RANGE_IN + 0.001:
				continue
			opts.append({"id": str(eid), "label": "%s (%.1f\")%s" % [Common.group_label(str(eid)), d, " — battle-shocked" if Common.is_battle_shocked(e) else ""]})
		if opts.is_empty():
			continue
		targets.append({"unit_id": str(b.id), "label": Common.unit_name(str(b.id)),
			"secondary": {"kind": "unit", "prompt": "HOWLMAW: select one enemy unit within 6\" — it makes a battle-shock roll at -1", "options": opts}})
	if targets.is_empty():
		return []
	return [_offer(RULE_HOWLMAW, "HOWLMAW", "Enhancement — Saga of the Great Wolf (once per turn, free)",
		"(Once per turn, per unit) At the start of the fight phase, you can select one enemy unit within 6\" of this model. That unit makes a battle-shock roll with -1 to that battle-shock roll.", targets)]

static func use_rule_offer(player: int, sid: String, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	match sid:
		RULE_HOWLMAW:
			return _use_howlmaw(player, target_unit_id, ctx)
	return {"success": false, "error": "unknown Space Wolves rule offer %s" % sid, "diffs": []}

static func _use_howlmaw(player: int, bearer_id: String, ctx: Dictionary) -> Dictionary:
	var eid := str(ctx.get("secondary_id", ""))
	var ok := false
	for o in _howlmaw_offers(player):
		for t in o.targets:
			if str(t.unit_id) != bearer_id:
				continue
			for opt in t.get("secondary", {}).get("options", []):
				ok = ok or str(opt.id) == eid
	if not ok:
		return {"success": false, "error": "Howlmaw: pick an enemy unit within 6\" of the Wolf Priest (once per turn)", "diffs": []}
	var diffs: Array = [{"op": "set", "path": "units.%s.flags.%s" % [bearer_id, F_HOWLMAW_TURN], "value": _turn_stamp()}]
	Common.apply_diffs(diffs)
	var line := "HOWLMAW — %s howls at %s" % [Common.unit_name(bearer_id), Common.group_label(eid)]
	var fam = Common.autoload("FactionAbilityManager")
	var e := Common.unit(eid)
	var cp = load("res://phases/CommandPhase.gd")
	var immune: bool = cp != null and bool(cp._has_battle_shock_immunity(e.get("meta", {}).get("keywords", []), e.get("meta", {}).get("abilities", [])))
	var passed := true
	if immune:
		line += ": it is immune to battle-shock"
	elif fam and fam.has_method("force_battle_shock_test"):
		var r: Dictionary = fam.force_battle_shock_test(eid, -1, "Howlmaw")
		diffs.append_array(r.get("diffs", []))
		passed = bool(r.get("passed", true))
		line += ": battle-shock roll %s -1 = %d vs Ld %d — %s" % [str(r.get("dice", [])), int(r.get("total", 0)), int(r.get("leadership", 0)),
			"passed" if passed else "FAILED, battle-shocked"]
	_log(line)
	Common.game_log(player, line)
	var tm = Common.autoload("ToastManager")
	if tm and tm.has_method("show_toast"):
		tm.show_toast(line, Color(0.55, 0.78, 1.0))
	return {"success": true, "diffs": diffs, "stratagem_name": "Howlmaw", "message": line, "passed": passed}

## AI: Howlmaw on the most expensive enemy in range that is not already
## battle-shocked (free, so always worth it).
static func ai_decide(_player: int, _window_id: String, offers: Array, _ctx: Dictionary) -> Dictionary:
	for offer in offers:
		if str(offer.get("stratagem_id", "")) != RULE_HOWLMAW:
			continue
		for t in offer.get("targets", []):
			var best := ""
			var best_pts := -1.0
			for o in t.get("secondary", {}).get("options", []):
				var e := Common.unit(str(o.id))
				if Common.is_battle_shocked(e):
					continue
				var pts := float(e.get("meta", {}).get("points", 0))
				if pts > best_pts:
					best_pts = pts
					best = str(o.id)
			if best != "":
				return {"use": true, "stratagem_id": RULE_HOWLMAW, "target_unit_id": str(t.unit_id),
					"context": {"secondary_id": best}, "name": "HOWLMAW"}
	return {}

# ===========================================================================
# Lifecycle
# ===========================================================================

static func on_command_phase_start(_player: int) -> void:
	pass  # Howlmaw's turn stamp and Grimnar's Mark's round stamp expire by comparison.
