extends RefCounted

## CustodesKatah — Codex: Adeptus Custodes (11e) ARMY RULES (WP-C3).
##
## Source: .llm/codex_11e_wahapedia/custodes/RULES.md ("Army rules" and the
## ka'tah abilities "From the faction page"). Contract:
## .llm/codex_11e_wahapedia/IMPLEMENTATION.md. Rulings: RULINGS.md § WP-C3.
##
## This one module holds every Custodes army rule, so the engine files only
## carry one-line hooks into it (each hook is commented "Codex: Adeptus
## Custodes … (CustodesKatah.gd)"):
##
##  MARTIAL KA'TAH
##   - Readied step: at the start of YOUR Command phase every friendly
##     ADEPTUS CUSTODES unit with the ability is readied (on_command_phase_start).
##     flags.cus11e_readied, written on every component of an Attached unit.
##     A unit still readied in the opponent's turn may use a ka'tah then
##     (Dacatarai / Kaptaris / Rendax are "Fight phase" abilities).
##   - While readied the unit may use ONE of the six ka'tah abilities, in that
##     ability's WHEN; it is then no longer readied. They are offered as cards
##     in the BasePhase stratagem WINDOW of their WHEN (window_offers / use_katah):
##        conservai  command_phase_main      (your Command phase)
##        calistus   unit_selected_to_move   (normal / advance / fall-back)
##        salvus     unit_selected_to_shoot  (your Shooting phase)
##        dacatarai  fight_phase_start       (either player's Fight phase)
##        kaptaris   fight_phase_start
##        rendax     unit_selected_to_fight  (either player's Fight phase)
##     Offer ids "cus11e_katah_<id>" (StratagemDialog cards Card_cus11e_katah_<id>,
##     buttons Use_cus11e_katah_<id>_<unit>), cp_cost 0, kind "katah". Using one
##     does NOT close the window: BasePhase re-opens it with the remaining
##     offers (another readied unit, the stratagems of that window).
##   - Effects: flags.cus11e_katah_<id> on every component, read by the engine
##     hooks below (moves_through_all_models, salvus_*, melee_hit_effects,
##     rendax_lethal_hits, conservai_active). Expiry: Conservai "until the end
##     of the turn" (cleared at the next Command phase start); the other five
##     at the end of the phase they were used in (on_phase_exit).
##   - Master of Ka'tahs (Shield-Captain datasheets; "Once per battle round,
##     per unit: if this unit is not readied, it is readied"): offered as the
##     "master_of_katahs" VARIANT of a ka'tah card for a not-readied unit that
##     has it — it readies the unit and the ka'tah is used at once.
##     flags.cus11e_master_of_katahs_round = battle round it was used.
##   - Favoured Ka'tah (Unique: Shield Host detachments, WP-C46): see
##     favoured_katah() / FAVOURED KA'TAH API below.
##   - AI: ai_pick() (called first by AIDecisionMaker.decide_window_stratagem)
##     — synchronous, never stalls a window.
##  AEGIS OF THE EMPEROR — FNP 5+ vs mortal wounds; DAUGHTERS OF THE ABYSS —
##   FNP 3+ vs psychic attacks + the Psychic Null (Aura) FNP 5+ vs psychic
##   attacks for friendly ADEPTUS CUSTODES units within 6": fnp_vs(), read by
##   RulesEngine.get_unit_fnp_vs on every damage / mortal-wound path (the best
##   applicable FNP wins — they never stack).
##  AQUILA COMMANDER — start of the battle round, +1CP if your WARLORD has it:
##   on_battle_round_start(). 11e has no per-round bonus-CP cap (core rules 08.02;
##   GameState's BONUS_CP_CAP_PER_ROUND is a 10e rule) — same ruling as Da Boss.
##  ANATHEMA PSYKANA — an ANATHEMA PSYKANA model cannot be your WARLORD unless
##   the detachment allows it (Null Maiden Vigil, WP-C46 hook):
##   warlord_block_reason().

const Common = preload("res://scripts/codex/custodes/CustodesCommon.gd")
const GameStateData = preload("res://autoloads/GameState.gd")

# WP-C46 fills this file in (CustodesDetachments.gd). It is loaded lazily, only
# when it exists, and called only through the FAVOURED KA'TAH API functions
# below — this module never needs editing for a detachment.
const DETACHMENTS_PATH := "res://scripts/codex/custodes/CustodesDetachments.gd"

const ABILITY_KATAH := "Martial Ka'tah"
const ABILITY_MASTER := "Master of Ka'tahs"
const ABILITY_AEGIS := "Aegis of the Emperor"
const ABILITY_AQUILA := "Aquila Commander"
const ABILITY_DAUGHTERS := "Daughters of the Abyss"
const KW_CUSTODES := "ADEPTUS CUSTODES"
const KW_ANATHEMA := "ANATHEMA PSYKANA"

const FLAG_READIED := "cus11e_readied"
const FLAG_MASTER_ROUND := "cus11e_master_of_katahs_round"
const FLAG_AQUILA_ROUND := "cus11e_aquila_round"        # battle round Aquila Commander was resolved
const FLAG_AQUILA_CP_ROUND := "cus11e_aquila_cp_round"  # battle round it actually gained the CP
const FLAG_LAST_KATAH := "cus11e_katah_last"
const OFFER_PREFIX := "cus11e_katah_"
const MASTER_VARIANT := "master_of_katahs"

const AEGIS_FNP := 5
const DAUGHTERS_FNP := 3
const PSYCHIC_NULL_FNP := 5
const PSYCHIC_NULL_RANGE_IN := 6.0
## Ruling (RULINGS.md WP-C3): Dacatarai / Kaptaris are offered at the start of
## the Fight phase only for readied units within 6" of an enemy unit — no melee
## attack can involve a unit farther away this phase (pile-in targets must be
## within 5"), so the card would only throw the readied state away.
const FIGHT_START_RANGE_IN := 6.0

const KATAH_ORDER := ["conservai", "calistus", "salvus", "dacatarai", "kaptaris", "rendax"]

const KATAHS := {
	"conservai": {
		"name": "CONSERVAI", "window": "command_phase_main", "phase": GameStateData.Phase.COMMAND,
		"own_turn": true, "expires": "turn",
		"when": "Your Command phase.",
		"target": "One friendly readied unit.",
		"effect": "Until the end of the turn: being engaged / battle-shocked does not prevent your unit from being eligible to start an action. Starting an action does not prevent your unit from being eligible to shoot.",
		"short": "can start actions while engaged / battle-shocked, and still shoot after starting one (this turn)",
	},
	"calistus": {
		"name": "CALISTUS", "window": "unit_selected_to_move", "phase": GameStateData.Phase.MOVEMENT,
		"own_turn": true, "expires": "phase",
		"when": "Your Movement phase, when a friendly readied unit is selected to move.",
		"target": "That readied unit.",
		"effect": "When your unit makes a normal / advance / fall-back move, your unit can move through all types of model.",
		"short": "normal / advance / fall-back moves can move through all models (this phase)",
	},
	"salvus": {
		"name": "SALVUS", "window": "unit_selected_to_shoot", "phase": GameStateData.Phase.SHOOTING,
		"own_turn": true, "expires": "phase",
		"when": "Your Shooting phase, when a friendly readied unit is selected to shoot.",
		"target": "That readied unit.",
		"effect": "Your unit can ignore modifiers to your unit's: BS. Hit rolls and wound rolls.",
		"short": "ignores modifiers to its BS, hit rolls and wound rolls (this phase)",
	},
	"dacatarai": {
		"name": "DACATARAI", "window": "fight_phase_start", "phase": GameStateData.Phase.FIGHT,
		"own_turn": false, "expires": "phase",
		"when": "Start of the Fight phase.",
		"target": "One friendly readied unit.",
		"effect": "Your unit's melee attacks that target an enemy unit (excluding MONSTER / VEHICLE units) can re-roll hit rolls of 1.",
		"short": "melee attacks vs non-MONSTER/VEHICLE units re-roll hit rolls of 1 (this phase)",
	},
	"kaptaris": {
		"name": "KAPTARIS", "window": "fight_phase_start", "phase": GameStateData.Phase.FIGHT,
		"own_turn": false, "expires": "phase",
		"when": "Start of the Fight phase.",
		"target": "One friendly readied unit.",
		"effect": "Melee attacks that target your unit have -1 to hit rolls.",
		"short": "melee attacks that target it have -1 to hit (this phase)",
	},
	"rendax": {
		"name": "RENDAX", "window": "unit_selected_to_fight", "phase": GameStateData.Phase.FIGHT,
		"own_turn": false, "expires": "phase",
		"when": "Fight phase, when a friendly readied unit is selected to fight.",
		"target": "One friendly readied unit.",
		"effect": "Your unit's melee attacks have [LETHAL HITS: MONSTER/VEHICLE].",
		"short": "melee attacks have [LETHAL HITS: MONSTER/VEHICLE] (this phase)",
	},
}

# ===========================================================================
# Identity helpers
# ===========================================================================

static func offer_id(katah_id: String) -> String:
	return OFFER_PREFIX + katah_id

static func flag_for(katah_id: String) -> String:
	return OFFER_PREFIX + katah_id

static func is_katah_offer_id(sid: String) -> bool:
	return sid.begins_with(OFFER_PREFIX) and KATAHS.has(sid.substr(OFFER_PREFIX.length()))

static func katah_id_from_offer(sid: String) -> String:
	if not is_katah_offer_id(sid):
		return ""
	return sid.substr(OFFER_PREFIX.length())

static func is_katah_offer(offer: Dictionary) -> bool:
	return str(offer.get("kind", "")) == "katah" or is_katah_offer_id(str(offer.get("stratagem_id", "")))

static func strip_katah_offers(offers: Array) -> Array:
	return offers.filter(func(o): return typeof(o) == TYPE_DICTIONARY and not is_katah_offer(o))

static func only_katah_offers(offers: Array) -> Array:
	return offers.filter(func(o): return typeof(o) == TYPE_DICTIONARY and is_katah_offer(o))

static func katah_display_name(katah_id: String) -> String:
	return str(KATAHS.get(katah_id, {}).get("name", katah_id.to_upper()))

static func katah_short(katah_id: String) -> String:
	return str(KATAHS.get(katah_id, {}).get("short", ""))

# ===========================================================================
# Readied state
# ===========================================================================

static func has_martial_katah(u: Dictionary) -> bool:
	return Common.has_keyword(u, KW_CUSTODES) and Common.has_ability(u, ABILITY_KATAH)

## True when any component of the (Attached) unit has Martial Ka'tah.
static func group_has_martial_katah(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if has_martial_katah(Common.unit(str(gid))):
			return true
	return false

static func is_readied(unit_id: String) -> bool:
	for gid in Common.attached_group_ids(unit_id):
		if bool(Common.unit(str(gid)).get("flags", {}).get(FLAG_READIED, false)):
			return true
	return false

## A unit dictionary's own readied flag (TokenVisual / hover card).
static func unit_dict_readied(u: Dictionary) -> bool:
	return bool(u.get("flags", {}).get(FLAG_READIED, false))

## Diffs that ready the whole (Attached) unit — also the API for SUPERHUMAN
## FOCUS (WP-C5: "Your unit is readied").
static func ready_diffs(unit_id: String) -> Array:
	return Common.set_flag_diffs(Common.attached_group_ids(unit_id), FLAG_READIED, true)

static func unready_diffs(unit_id: String) -> Array:
	return Common.set_flag_diffs(Common.attached_group_ids(unit_id), FLAG_READIED, false)

## Ka'tah abilities whose effect is active on this unit dictionary.
static func active_katahs(u: Dictionary) -> Array:
	var out: Array = []
	var flags: Dictionary = u.get("flags", {})
	for kid in KATAH_ORDER:
		if bool(flags.get(flag_for(kid), false)):
			out.append(kid)
	return out

static func katah_active(u: Dictionary, katah_id: String) -> bool:
	return bool(u.get("flags", {}).get(flag_for(katah_id), false))

# --- Master of Ka'tahs -----------------------------------------------------

## The component of the (Attached) unit that has Master of Ka'tahs ("" = none).
static func master_component(unit_id: String) -> String:
	for gid in Common.attached_group_ids(unit_id):
		var gu := Common.unit(str(gid))
		if Common.is_alive(gu) and Common.has_ability(gu, ABILITY_MASTER):
			return str(gid)
	return ""

## Once per battle round, per unit: usable while the unit is NOT readied.
static func master_available(unit_id: String) -> bool:
	if master_component(unit_id) == "" or is_readied(unit_id):
		return false
	var rnd := Common.battle_round()
	for gid in Common.attached_group_ids(unit_id):
		if int(Common.unit(str(gid)).get("flags", {}).get(FLAG_MASTER_ROUND, -1)) == rnd:
			return false
	return true

# ===========================================================================
# Phase hooks (CommandPhase / BasePhase)
# ===========================================================================

## Readied step — start of `player`'s Command phase. Also ends the previous
## turn's Conservai (its effect lasted "until the end of the turn"). Applies
## the diffs itself (phase entry has no action result) and returns them.
static func on_command_phase_start(player: int) -> Array:
	var diffs: Array = []
	var units: Dictionary = Common.state().get("units", {})
	# Conservai from the previous turn has expired.
	diffs.append_array(Common.remove_flag_diffs(units.keys(), flag_for("conservai")))
	var readied: Array = []
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) != player or not Common.is_alive(u) or not has_martial_katah(u):
			continue
		readied.append(str(uid))
		if not bool(u.get("flags", {}).get(FLAG_READIED, false)):
			diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(uid), FLAG_READIED], "value": true})
	Common.apply_diffs(diffs)
	if not readied.is_empty():
		Common.log_info("[CustodesKatah] Martial Ka'tah: start of P%d's Command phase — %d unit(s) readied: %s" % [player, readied.size(), str(readied)])
		Common.game_log(player, "Martial Ka'tah: %d unit(s) readied" % readied.size())
	return diffs

## End of a phase: the ka'tah effects that lasted for that phase expire.
## Conservai lasts until the end of the turn (cleared by on_command_phase_start).
static func on_phase_exit(_phase: int) -> void:
	var units: Dictionary = Common.state().get("units", {})
	var diffs: Array = []
	for kid in KATAH_ORDER:
		if str(KATAHS[kid].get("expires", "phase")) != "phase":
			continue
		diffs.append_array(Common.remove_flag_diffs(units.keys(), flag_for(kid)))
	if diffs.is_empty():
		return
	var gs = Common.game_state()
	if gs and gs.has_method("apply_state_changes"):
		gs.apply_state_changes(diffs)
	Common.log_info("[CustodesKatah] end of phase — %d ka'tah effect flag(s) expired" % diffs.size())

## AQUILA COMMANDER — "At the start of the battle round, if a model with this
## ability is your WARLORD, gain 1CP." Not subject to GameState's 10e
## 1-bonus-CP-per-round cap (the 11e core rules have none; Da Boss reads it the
## same way — RULINGS.md WP-O34). Once per battle round per player even if the
## Command phase that starts the round is re-entered (save / load), via
## flags.cus11e_aquila_round on the warlord. Returns the CP / marker diffs
## (already applied).
static func on_battle_round_start(battle_round: int) -> Array:
	var diffs: Array = []
	var gs = Common.game_state()
	for p in [1, 2]:
		var wid := warlord_id(p)
		if wid == "":
			continue
		var w := Common.unit(wid)
		if not Common.is_alive(w) or not Common.has_ability(w, ABILITY_AQUILA):
			continue
		if int(w.get("flags", {}).get(FLAG_AQUILA_ROUND, -1)) == battle_round:
			# Re-entered (save / load re-runs the phase entry): no second CP.
			Common.log_info("[CustodesKatah] Aquila Commander: P%d already resolved for battle round %d" % [p, battle_round])
			continue
		var marker := {"op": "set", "path": "units.%s.flags.%s" % [wid, FLAG_AQUILA_ROUND], "value": battle_round}
		var cp_before := Common.player_cp(p)
		var cp_diff := {"op": "set", "path": "players.%s.cp" % str(p), "value": cp_before + 1}
		var cp_marker := {"op": "set", "path": "units.%s.flags.%s" % [wid, FLAG_AQUILA_CP_ROUND], "value": battle_round}
		Common.apply_diffs([cp_diff, marker, cp_marker])
		diffs.append(cp_diff)
		diffs.append(marker)
		diffs.append(cp_marker)
		Common.log_info("[CustodesKatah] Aquila Commander: P%d's WARLORD %s — +1CP at the start of battle round %d (%d -> %d)" % [p, Common.unit_name(wid), battle_round, cp_before, cp_before + 1])
		Common.game_log(p, "Aquila Commander (%s, Warlord): +1CP" % Common.unit_name(wid))
	return diffs

static func warlord_id(player: int) -> String:
	var units: Dictionary = Common.state().get("units", {})
	for uid in units:
		var u: Dictionary = units[uid]
		if int(u.get("owner", 0)) == player and bool(u.get("meta", {}).get("is_warlord", false)):
			return str(uid)
	return ""

# ===========================================================================
# Ka'tah windows — offers / use (BasePhase window framework)
# ===========================================================================

## The ka'tah cards `player` may use in window `window_id` right now, in the
## StratagemManager.get_window_offers shape (+ kind "katah", katah_id).
static func window_offers(player: int, window_id: String, ctx: Dictionary) -> Array:
	var offers: Array = []
	if GameConstants.edition < 11 or player <= 0:
		return offers
	var phase := Common.current_phase()
	var own_turn := player == Common.active_player()
	for kid in KATAH_ORDER:
		var spec: Dictionary = KATAHS[kid]
		if str(spec.window) != window_id:
			continue
		if int(spec.phase) != phase:
			continue
		if bool(spec.own_turn) and not own_turn:
			continue
		var candidates := _window_candidates(player, kid, window_id, ctx)
		var targets: Array = []
		for uid in candidates:
			var entry := _target_entry(player, kid, uid, ctx)
			if not entry.is_empty():
				targets.append(entry)
		if targets.is_empty():
			continue
		offers.append(_offer(player, kid, targets))
	if not offers.is_empty():
		Common.log_info("[CustodesKatah] window %s (P%d): ka'tah offers %s" % [window_id, player, str(offers.map(func(o): return "%s x%d" % [o.name, o.targets.size()]))])
	return offers

static func _window_candidates(player: int, kid: String, window_id: String, ctx: Dictionary) -> Array:
	var out: Array = []
	match window_id:
		"unit_selected_to_move":
			if not str(ctx.get("move_type", "normal")) in ["normal", "advance", "fall_back"]:
				return out
			out.append(str(ctx.get("unit_id", "")))
		"unit_selected_to_shoot", "unit_selected_to_fight":
			out.append(str(ctx.get("unit_id", "")))
		"command_phase_main", "fight_phase_start":
			var units: Dictionary = Common.state().get("units", {})
			for uid in units:
				var head := Common.head_id(str(uid))
				if head in out:
					continue
				var hu := Common.unit(head)
				if int(hu.get("owner", 0)) != player:
					continue
				if window_id == "fight_phase_start" and Common.nearest_enemy_inches(_group_union(head)) > FIGHT_START_RANGE_IN:
					continue
				out.append(head)
	var filtered: Array = []
	for uid in out:
		if uid == "":
			continue
		var head := Common.head_id(uid)
		if head in filtered:
			continue
		var u := Common.unit(head)
		if int(u.get("owner", 0)) != player or not Common.is_on_battlefield(u):
			continue
		if not group_has_martial_katah(head):
			continue
		# The same ka'tah twice on one unit has no further effect.
		if katah_active(u, kid):
			continue
		filtered.append(head)
	return filtered

## Models of every component, merged — distances from an Attached unit.
static func _group_union(head: String) -> Dictionary:
	var models: Array = []
	var owner := int(Common.unit(head).get("owner", 0))
	for gid in Common.attached_group_ids(head):
		for m in Common.unit(str(gid)).get("models", []):
			models.append(m)
	return {"owner": owner, "models": models}

static func _target_entry(player: int, kid: String, unit_id: String, ctx: Dictionary) -> Dictionary:
	var label := Common.unit_name(unit_id)
	var chars: Array = Common.unit(unit_id).get("attachment_data", {}).get("attached_characters", [])
	if not chars.is_empty():
		var names: Array = [label]
		for cid in chars:
			names.append(Common.unit_name(str(cid)))
		label = " + ".join(names)
	var entry := {"unit_id": unit_id, "label": label}
	if is_readied(unit_id):
		pass
	elif master_available(unit_id):
		entry["variants"] = [{"id": MASTER_VARIANT, "label": "Master of Ka'tahs: ready %s, then use %s" % [label, katah_display_name(kid)], "cp_cost": 0}]
		entry["require_variant"] = true
	else:
		return {}
	var secondary := favoured_katah_secondary(player, kid, unit_id, ctx)
	if not secondary.is_empty():
		entry["secondary"] = secondary
	return entry

static func _offer(player: int, kid: String, targets: Array) -> Dictionary:
	var spec: Dictionary = KATAHS[kid]
	var text := "WHEN: %s\nTARGET: %s\nEFFECT: %s" % [spec.when, spec.target, spec.effect]
	var name := str(spec.name)
	if favoured_katah(player) == kid:
		name += " (Favoured Ka'tah)"
		var extra := favoured_katah_text(player, kid)
		if extra != "":
			text += "\nFAVOURED KA'TAH: %s" % extra
	return {
		"stratagem_id": offer_id(kid),
		"name": name,
		"cp_cost": 0,
		"effect_text": text,
		"type": "Martial Ka'tah ability — the unit is no longer readied",
		"kind": "katah",
		"katah_id": kid,
		"targets": targets,
	}

## Use ka'tah `sid` (offer id) for `unit_id` in the window described by `ctx`
## (ctx.window_id; ctx.variant_id = "master_of_katahs" for Master of Ka'tahs;
## ctx.secondary_id for a Favoured Ka'tah choice). Re-validates against the
## live offers, applies the diffs (state, game log) and returns
## {success, diffs, stratagem_name, error}.
static func use_katah(player: int, sid: String, unit_id: String, ctx: Dictionary) -> Dictionary:
	var kid := katah_id_from_offer(sid)
	var window_id := str(ctx.get("window_id", ""))
	if kid == "":
		return {"success": false, "error": "%s is not a ka'tah ability" % sid, "diffs": []}
	var head := Common.head_id(unit_id)
	var offered: Dictionary = {}
	for o in window_offers(player, window_id, ctx):
		if str(o.get("stratagem_id", "")) != sid:
			continue
		for t in o.get("targets", []):
			if str(t.get("unit_id", "")) == head:
				offered = t
	if offered.is_empty():
		return {"success": false, "error": "%s cannot use %s in %s (not readied, or not its window)" % [Common.unit_name(head), katah_display_name(kid), window_id], "diffs": []}
	var variant := str(ctx.get("variant_id", ""))
	var via_master := false
	if bool(offered.get("require_variant", false)):
		if variant != MASTER_VARIANT:
			return {"success": false, "error": "%s is not readied — use Master of Ka'tahs to ready it" % Common.unit_name(head), "diffs": []}
		via_master = true
	elif variant == MASTER_VARIANT:
		return {"success": false, "error": "%s is already readied" % Common.unit_name(head), "diffs": []}
	var group := Common.attached_group_ids(head)
	var diffs: Array = []
	if via_master:
		diffs.append_array(Common.set_flag_diffs(group, FLAG_MASTER_ROUND, Common.battle_round()))
		Common.log_info("[CustodesKatah] Master of Ka'tahs (%s): %s is readied (once per battle round)" % [Common.unit_name(master_component(head)), Common.unit_name(head)])
	diffs.append_array(unready_diffs(head))
	diffs.append_array(Common.set_flag_diffs(group, flag_for(kid), true))
	diffs.append_array(Common.set_flag_diffs(group, FLAG_LAST_KATAH, kid))
	Common.apply_diffs(diffs)
	var extra := favoured_katah_extra_effect(player, kid, head, ctx)
	if not extra.is_empty():
		Common.apply_diffs(extra)
		diffs.append_array(extra)
	var label := str(offered.get("label", Common.unit_name(head)))
	var msg := "Martial Ka'tah: %s uses %s — %s" % [label, katah_display_name(kid), katah_short(kid)]
	if via_master:
		msg = "Master of Ka'tahs: %s is readied. %s" % [label, msg]
	Common.log_info("[CustodesKatah] P%d %s (%s, %d diff(s))" % [player, msg, window_id, diffs.size()])
	Common.game_log(player, msg)
	return {"success": true, "diffs": diffs, "stratagem_name": "%s (ka'tah)" % katah_display_name(kid), "katah_id": kid, "via_master": via_master}

# ===========================================================================
# Engine hooks — effects
# ===========================================================================

## CALISTUS: a normal / advance / fall-back move of this unit can move
## through all types of model (MovementPhase path-crossing checks).
static func moves_through_all_models(u: Dictionary, move_mode: String) -> bool:
	return katah_active(u, "calistus") and move_mode.to_upper() in ["NORMAL", "ADVANCE", "FALL_BACK"]

## SALVUS: the unit ignores modifiers to its BS, hit rolls and wound rolls.
## Ruling: "can ignore" — the engine ignores exactly the harmful ones (BS
## worsening, -1 to hit, -1 to wound), the same choice [PSYCHIC] makes (24.29).
static func salvus_active(u: Dictionary) -> bool:
	return katah_active(u, "salvus")

## Remove the harmful entries of an 11e ModifierStack (BS worsening, negative
## hit / wound roll modifiers). Returns the sources removed.
static func salvus_filter_stack(u: Dictionary, stack) -> Array:
	var removed: Array = []
	if stack == null or not salvus_active(u):
		return removed
	var kept: Array = []
	for e in stack.entries:
		var t := str(e.get("type", ""))
		var v := int(e.get("value", 0))
		if (t == "bs" and v > 0) or ((t == "hit_roll" or t == "wound_roll") and v < 0):
			removed.append(str(e.get("source", t)))
		else:
			kept.append(e)
	stack.entries = kept
	if not removed.is_empty():
		Common.log_info("[CustodesKatah] SALVUS: ignoring %s for %s" % [str(removed), str(u.get("id", "?"))])
	return removed

## DACATARAI (attacker) / KAPTARIS (target) on one melee attack batch.
## Returns {reroll_ones: bool, minus_one: bool}.
static func melee_hit_effects(attacker: Dictionary, target: Dictionary) -> Dictionary:
	return {
		"reroll_ones": katah_active(attacker, "dacatarai") and not Common.is_monster_or_vehicle(target),
		"minus_one": katah_active(target, "kaptaris"),
	}

## RENDAX: the unit's melee attacks have [LETHAL HITS: MONSTER/VEHICLE] —
## keyword-qualified: only when the target unit is a MONSTER or VEHICLE.
static func rendax_lethal_hits(attacker: Dictionary, target: Dictionary) -> bool:
	return katah_active(attacker, "rendax") and Common.is_monster_or_vehicle(target)

## CONSERVAI: being engaged / battle-shocked does not prevent the unit from
## being eligible to start an action, and starting an action does not prevent
## it from being eligible to shoot (ActionsManager / ShootingPhase).
static func conservai_active(u: Dictionary) -> bool:
	return katah_active(u, "conservai")

# ===========================================================================
# Feel No Pain — Aegis of the Emperor, Daughters of the Abyss, Psychic Null
# ===========================================================================

## Best Feel No Pain the Custodes army rules give `u` against one wound loss
## (0 = none). is_mortal: a mortal wound (any source); is_psychic: a psychic
## attack. RulesEngine.get_unit_fnp_vs takes the best of this and every other
## FNP — never cumulative.
static func fnp_vs(u: Dictionary, is_psychic: bool, is_mortal: bool) -> int:
	var best := 0
	if is_mortal and Common.has_keyword(u, KW_CUSTODES) and Common.has_ability(u, ABILITY_AEGIS):
		best = _better_fnp(best, AEGIS_FNP)
	if is_psychic:
		if Common.has_keyword(u, KW_ANATHEMA) and Common.has_ability(u, ABILITY_DAUGHTERS):
			best = _better_fnp(best, DAUGHTERS_FNP)
		if Common.has_keyword(u, KW_CUSTODES) and psychic_null_covers(u):
			best = _better_fnp(best, PSYCHIC_NULL_FNP)
	return best

static func _better_fnp(a: int, b: int) -> int:
	if a <= 0:
		return b
	if b <= 0:
		return a
	return mini(a, b)

## PSYCHIC NULL (Aura): a friendly ANATHEMA PSYKANA unit with Daughters of the
## Abyss is within 6" of `u`.
static func psychic_null_covers(u: Dictionary) -> bool:
	return psychic_null_source(u) != ""

static func psychic_null_source(u: Dictionary) -> String:
	var owner := int(u.get("owner", 0))
	var units: Dictionary = Common.state().get("units", {})
	for sid in units:
		var s: Dictionary = units[sid]
		if int(s.get("owner", 0)) != owner or not Common.is_on_battlefield(s):
			continue
		if not (Common.has_keyword(s, KW_ANATHEMA) and Common.has_ability(s, ABILITY_DAUGHTERS)):
			continue
		if str(sid) == str(u.get("id", "")):
			return str(sid)
		if Common.unit_distance_inches(u, s) <= PSYCHIC_NULL_RANGE_IN + 0.001:
			return str(sid)
	return ""

# ===========================================================================
# Anathema Psykana — WARLORD restriction
# ===========================================================================

## "" when the model may be the player's WARLORD, else the reason it may not.
## detachment: the army's detachment name (Null Maiden Vigil allows it).
static func warlord_block_reason(u: Dictionary, detachment: String) -> String:
	if not Common.has_keyword(u, KW_ANATHEMA):
		return ""
	if anathema_psykana_warlord_allowed(detachment):
		return ""
	var meta: Dictionary = u.get("meta", {})
	var nm := str(meta.get("display_name", meta.get("name", u.get("id", "this model"))))
	return "Anathema Psykana: an ANATHEMA PSYKANA model cannot be your WARLORD (%s)" % nm

static func player_detachment(player: int) -> String:
	return str(Common.state().get("factions", {}).get(str(player), {}).get("detachment", ""))

# ===========================================================================
# FAVOURED KA'TAH API (WP-C46 fills it in through CustodesDetachments.gd)
# ===========================================================================
# Every function below asks CustodesDetachments.gd (when that file exists and
# defines the function as a `static func` with the same name and arguments)
# and otherwise returns the stub value. CustodesDetachments.gd functions:
#
#   favoured_katah(player: int) -> String
#       The ka'tah id ("conservai", "calistus", "salvus", "dacatarai",
#       "kaptaris", "rendax") that is the Favoured Ka'tah of `player`'s
#       detachment, or "" (stub: "").
#   favoured_katah_text(player: int, katah_id: String) -> String
#       The "Additional Effect" text printed on the ka'tah card (stub: "").
#   favoured_katah_secondary(player: int, katah_id: String, unit_id: String, ctx: Dictionary) -> Dictionary
#       Optional secondary pick for the extra effect, in the window target
#       "secondary" shape {kind: "unit"|"objective", prompt, options: [{id, label}]}
#       (e.g. Shadowkeepers' Kaptaris: one enemy unit engaged with your unit);
#       the chosen id arrives as ctx.secondary_id (stub: {} = no pick).
#   favoured_katah_extra_effect(player: int, katah_id: String, unit_id: String, ctx: Dictionary) -> Array
#       Diffs of the additional effect, called right after the ka'tah's own
#       effect is applied (only when katah_id is the Favoured Ka'tah); this
#       module applies them. Return [] for nothing (stub: []).
#   allows_anathema_psykana_warlord(detachment: String) -> bool
#       Null Maiden Vigil's "you can select a friendly ANATHEMA PSYKANA
#       CHARACTER model to be your WARLORD" (stub: false).

static func favoured_katah(player: int) -> String:
	var k = _detachments_call("favoured_katah", [player], "")
	return str(k) if KATAHS.has(str(k)) else ""

static func favoured_katah_text(player: int, katah_id: String) -> String:
	return str(_detachments_call("favoured_katah_text", [player, katah_id], ""))

static func favoured_katah_secondary(player: int, katah_id: String, unit_id: String, ctx: Dictionary) -> Dictionary:
	if favoured_katah(player) != katah_id:
		return {}
	var s = _detachments_call("favoured_katah_secondary", [player, katah_id, unit_id, ctx], {})
	return s if typeof(s) == TYPE_DICTIONARY else {}

static func favoured_katah_extra_effect(player: int, katah_id: String, unit_id: String, ctx: Dictionary) -> Array:
	if favoured_katah(player) != katah_id:
		return []
	var d = _detachments_call("favoured_katah_extra_effect", [player, katah_id, unit_id, ctx], [])
	return d if typeof(d) == TYPE_ARRAY else []

static func anathema_psykana_warlord_allowed(detachment: String) -> bool:
	return bool(_detachments_call("allows_anathema_psykana_warlord", [detachment], false))

static func _detachments_call(fn: String, args: Array, fallback):
	if not ResourceLoader.exists(DETACHMENTS_PATH):
		return fallback
	var script = load(DETACHMENTS_PATH)
	if script == null:
		return fallback
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == fn:
			return script.callv(fn, args)
	return fallback

# ===========================================================================
# AI — synchronous ka'tah choice (AIDecisionMaker.decide_window_stratagem)
# ===========================================================================

## Pick at most ONE ka'tah use among `offers` for the AI decider, or
## {use: false}. {use, stratagem_id, target_unit_id, context, reason}.
## Heuristics (free, but each unit has one per readying):
##  - Conservai: never (the AI does not start actions).
##  - Calistus: only for a fall-back move (escape through the enemy).
##  - Salvus: when no enemy is within 18" (the unit is unlikely to fight
##    before its next readied step, so the ka'tah would be wasted).
##  - Rendax: when selected to fight while engaged with a MONSTER/VEHICLE.
##  - Dacatarai / Kaptaris: at the start of a Fight phase, for an ENGAGED unit
##    that is not engaged with a MONSTER/VEHICLE (kept for Rendax otherwise):
##    Dacatarai in its own turn, Kaptaris in the opponent's turn.
##  - Master of Ka'tahs is used for a score >= 1.5 only.
static func ai_pick(player: int, window_id: String, offers: Array, ctx: Dictionary) -> Dictionary:
	var best := {"use": false}
	var best_score := 0.0
	for offer in offers:
		if typeof(offer) != TYPE_DICTIONARY or not is_katah_offer(offer):
			continue
		var kid := str(offer.get("katah_id", katah_id_from_offer(str(offer.get("stratagem_id", "")))))
		for t in offer.get("targets", []):
			var uid := str(t.get("unit_id", ""))
			var via_master := bool(t.get("require_variant", false))
			var sc := _ai_score(player, kid, uid, window_id, ctx)
			var need := 1.5 if via_master else 1.0
			if sc < need or sc <= best_score:
				continue
			best_score = sc
			var c := {}
			if via_master:
				c["variant_id"] = MASTER_VARIANT
			var sec = t.get("secondary", {})
			if typeof(sec) == TYPE_DICTIONARY and not sec.get("options", []).is_empty():
				c["secondary_id"] = str(sec.options[0].get("id", ""))
			best = {"use": true, "stratagem_id": str(offer.get("stratagem_id", "")), "target_unit_id": uid,
				"context": c, "reason": "%s for %s (score %.1f%s)" % [katah_display_name(kid), Common.unit_name(uid), sc, ", Master of Ka'tahs" if via_master else ""]}
	return best

static func _ai_score(player: int, kid: String, uid: String, _window_id: String, ctx: Dictionary) -> float:
	var u := Common.unit(uid)
	var engaged := Common.engaged_enemy_ids(uid)
	var engaged_mv := false
	for eid in engaged:
		if Common.is_monster_or_vehicle(Common.unit(str(eid))):
			engaged_mv = true
	match kid:
		"conservai":
			return 0.0
		"calistus":
			return 1.5 if str(ctx.get("move_type", "")) == "fall_back" else 0.0
		"salvus":
			return 1.2 if Common.nearest_enemy_inches(_group_union(uid)) > 18.0 else 0.0
		"rendax":
			return 2.0 if engaged_mv else 0.0
		"dacatarai":
			if engaged.is_empty() or engaged_mv:
				return 0.0
			return 1.5 if int(u.get("owner", 0)) == Common.active_player() else 1.0
		"kaptaris":
			if engaged.is_empty() or engaged_mv:
				return 0.0
			return 1.5 if int(u.get("owner", 0)) != Common.active_player() else 1.0
	return 0.0
