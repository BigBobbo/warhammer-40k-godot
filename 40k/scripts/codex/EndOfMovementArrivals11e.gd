extends RefCounted
## EndOfMovementArrivals11e — the rows of the end-of-the-opponent's-Movement
## reserves prompt (MovementPhase._continue_end_movement_rapid_ingress, the
## RapidIngressDialog for a human, AIDecisionMaker.evaluate_rapid_ingress for
## the AI). WP-G2.
##
## Two ways for the NON-active player to make an ingress move (20.04) there:
##   RAPID INGRESS (15.07, core stratagem, 1 CP, not in battle round 1, once per
##       phase) — checked PER UNIT, so a per-unit rule changes only that unit's
##       row: Codex: Adeptus Custodes SWIFT RUIN (Venatari with Verutum Lances;
##       once per phase, per army: -1 CP, regardless of / not counting against
##       other uses this phase — CustodesAbilities + StratagemManager), and
##       WP-C46 Leonine Ferocity, both through StratagemManager.can_use_stratagem.
##   Codex: Orks DEFF FROM THE SHADOWS (Boss Snikrot, "First battle round
##       onwards"): a free ingress move, battle round 1 included
##       (OrkAbilities11e). Its row has cp_cost 0 and via "deff_from_the_shadows".
##
## After an arrival is set up the prompt is offered again while a row is left
## (a Swift Ruin use does not block other units; Deff from the Shadows is not a
## stratagem use). Edition 10 keeps the legacy single offer exactly.
##
## Row: {unit_id, unit_name, reserve_type, cp_cost, via, note?}.

const ORK_ABILITIES := "res://scripts/codex/orks/OrkAbilities11e.gd"
const CUS_ABILITIES := "res://scripts/codex/custodes/CustodesAbilities.gd"
const VIA_RAPID_INGRESS := "rapid_ingress"
const VIA_DEFF := "deff_from_the_shadows"


static func _node(name: String) -> Node:
	var ml = Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null(name)


static func _round() -> int:
	var gs = _node("GameState")
	return int(gs.get_battle_round()) if gs != null else 0


## Every row the prompt offers `player` now. `ri_rows` = the phase's Rapid
## Ingress candidates (MovementPhase._get_rapid_ingress_eligible_units: in
## reserves, not attached / embarked, 11e: not AIRCRAFT / battle-shocked).
static func offer_rows(player: int, ri_rows: Array) -> Array:
	var sm = _node("StratagemManager")
	if int(GameConstants.edition) < 11:
		# Legacy (10e): one offer per phase, every candidate at 1 CP.
		if _round() >= 2 and sm != null and sm.can_use_stratagem(player, "rapid_ingress").can_use:
			return ri_rows
		return []
	var out: Array = []
	var gs = _node("GameState")
	var deff: Array = load(ORK_ABILITIES).deff_from_the_shadows_units(player)
	for uid in deff:
		var u: Dictionary = gs.get_unit(str(uid)) if gs != null else {}
		out.append({"unit_id": str(uid), "unit_name": _arrival_name(str(uid), u),
			"reserve_type": str(u.get("reserve_type", "strategic_reserves")), "cp_cost": 0, "via": VIA_DEFF,
			"note": "Deff from the Shadows: free ingress move (no CP; from the first battle round)"})
	if _round() >= 2 and sm != null:
		for r in ri_rows:
			var uid := str(r.get("unit_id", ""))
			if uid == "" or uid in deff:
				continue
			var chk: Dictionary = sm.can_use_stratagem(player, "rapid_ingress", uid)
			if not bool(chk.get("can_use", false)):
				continue
			var row: Dictionary = r.duplicate(true)
			row["cp_cost"] = int(sm.preview_cp_cost(player, "rapid_ingress", uid))
			row["via"] = VIA_RAPID_INGRESS
			var note := str(load(CUS_ABILITIES).swift_ruin_row_note(player, uid))
			if note != "":
				row["note"] = note
			out.append(row)
	if not out.is_empty():
		print("EndOfMovementArrivals11e: P%d end-of-Movement arrivals %s" % [player, str(out.map(func(x): return "%s(%s,%dCP)" % [x.unit_id, x.via, int(x.cp_cost)]))])
	return out


static func _arrival_name(uid: String, u: Dictionary) -> String:
	var n := str(u.get("meta", {}).get("name", uid))
	var gs = _node("GameState")
	for cid in u.get("attachment_data", {}).get("attached_characters", []):
		var cu: Dictionary = gs.get_unit(str(cid)) if gs != null else {}
		if int(cu.get("status", 0)) == 7:
			n += " + " + str(cu.get("meta", {}).get("name", cid))
	return n


static func row_for(rows: Array, unit_id: String) -> Dictionary:
	for r in rows:
		if str(r.get("unit_id", "")) == unit_id:
			return r
	return {}


## USE_RAPID_INGRESS validation for `unit_id` (one of `rows`): {can_use, reason}.
static func use_check(player: int, unit_id: String, rows: Array) -> Dictionary:
	var sm = _node("StratagemManager")
	if int(GameConstants.edition) < 11:
		return sm.can_use_stratagem(player, "rapid_ingress") if sm != null else {"can_use": true, "reason": ""}
	if str(row_for(rows, unit_id).get("via", "")) == VIA_DEFF:
		if unit_id in load(ORK_ABILITIES).deff_from_the_shadows_units(player):
			return {"can_use": true, "reason": ""}
		return {"can_use": false, "reason": "Deff from the Shadows cannot be used on %s now" % unit_id}
	if sm == null:
		return {"can_use": true, "reason": ""}
	return sm.can_use_stratagem(player, "rapid_ingress", unit_id)


## USE_RAPID_INGRESS: spend the stratagem (CP, Swift Ruin record) or record
## the free Deff from the Shadows use. {success, error?, via}.
static func use(player: int, unit_id: String, rows: Array) -> Dictionary:
	if int(GameConstants.edition) >= 11 and str(row_for(rows, unit_id).get("via", "")) == VIA_DEFF:
		load(ORK_ABILITIES).deff_from_the_shadows_use(player, unit_id)
		return {"success": true, "via": VIA_DEFF}
	var sm = _node("StratagemManager")
	if sm == null:
		return {"success": true, "via": VIA_RAPID_INGRESS}
	var r: Dictionary = sm.use_stratagem(player, "rapid_ingress", unit_id)
	r["via"] = VIA_RAPID_INGRESS
	return r


## The ingress set-up of `unit_id` may happen in battle round 1 (20.03 "Unless
## otherwise stated ... from the second battle round onwards"): Deff from the Shadows.
static func round_one_allowed(unit_id: String) -> bool:
	return int(GameConstants.edition) >= 11 and load(ORK_ABILITIES).deff_from_the_shadows_arriving(unit_id)
