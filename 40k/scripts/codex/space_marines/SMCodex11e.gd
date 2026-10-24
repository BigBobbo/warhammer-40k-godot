extends RefCounted

## SMCodex11e — dispatcher for the Codex: Space Marines (11e) GENERIC
## detachment stratagems (rows `SM|…` of 40k/data/Stratagems.csv whose
## effects_json is the single marker {"type": "custom:sm11e"}). Every Space
## Marine army uses them (SWCommon.is_sm_army): faction Space Marines /
## Adeptus Astartes or any chapter that takes a generic detachment (the
## FactionStratagemLoader falls back to the SM rows — e.g. a Space Wolves army
## in Gladius Task Force).
##
## Contract: .llm/codex_11e_wahapedia/PLAN_SPACE_MARINES.md + IMPLEMENTATION.md
## (§2, §3); same API as SWCodex11e.gd / CustodesCodex11e.gd / OrkCodex11e.gd.
## Rulings: .llm/codex_11e_wahapedia/RULINGS.md § WP-M3a (and § WP-M3b).
##
## StratagemManager.codex_for() returns this dispatcher for every custom:sm11e
## row, so it is called FIRST — before every legacy name-keyed handler — in
## can_use_stratagem (validate), _apply_stratagem_effects (apply),
## _clear_stratagem_flags (clear), implemented marking (is_implemented) and
## get_window_offers (eligible_targets). Dispatch is keyed by csv_id (names
## printed in several detachments — ARMOUR OF CONTEMPT, STRIKE FROM THE
## SHADOWS, RELENTLESS ASSAULT, ANNIHILATING FORCE — are told apart by their
## detachment-scoped csv_id).
##
## Group scripts:
##   WP-M3a (this package; they preload ONLY SWCommon.gd, never each other):
##     SMCodexACombat.gd    attack / defence buffs (11 rows)
##     SMCodexAMovement.gd  moves, embark, reserves, fight order (9 rows)
##     SMCodexACommand.gd   Command / end-of-Movement-phase rules (4 rows)
##   WP-M3b (parallel package): res://scripts/codex/space_marines/SMCodexB.gd
##     — loaded ONLY when the file exists (ResourceLoader.exists), so this
##     dispatcher works with or without it.
##
## ---------------------------------------------------------------------------
## GROUP-SCRIPT API (published for WP-M3b's SMCodexB.gd — same static API as
## the Space Wolves group scripts SWCodexCombat.gd / SWCodexMovement.gd):
##
##   const IDS: Array                 every csv_id the group owns
##   const IMPLEMENTED: Dictionary    csv_id -> bool (only true rows are used)
##   static func eligible_targets(strat, player: int, window_id: String, ctx: Dictionary) -> Array
##       target entries ({unit_id, label, [variants, require_variant,
##       ai_variant, secondary]}) — SWCommon.target_entry builds one.
##   static func validate(strat, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary
##       {ok: bool, reason: String}. ctx.window_id is set by the window
##       framework ("" for an S-panel use); ctx.variant_id / ctx.secondary_id
##       carry the dialog choices. (The dispatcher already refuses a
##       non-Space-Marine army.)
##   static func apply(strat, target_unit_id: String, ctx: Dictionary) -> Variant
##       Array of diffs, or {diffs: Array, followup: Dictionary}.
##   static func clear(strat, unit_id: String) -> void      expiry (in place)
##   static func ai_kind(strat) -> String       "offensive" | "defensive" | "utility"
##   static func ai_score(strat, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float
##   static func variant_cp_cost(strat, variant_id: String) -> int   (-1 = base cost)
##   static func variant_label(strat, variant_id: String) -> String
##   static func allows_battle_shocked_target(strat, ctx: Dictionary) -> bool
##
## OPTIONAL engine consumers: a group script MAY implement any of the static
## functions below with the same signature; the dispatcher folds every group
## that has it (has_method), so SMCodexB needs no engine hooks of its own for
## these effect kinds:
##   modify_ap(ap: int, attacker_unit, target_unit) -> int
##   hit_bits(bits: int, attacker_unit, target_unit, is_melee: bool, ledger: Array) -> int
##   wound_bits(bits: int, attacker_unit, target_unit, is_melee: bool, ledger: Array) -> int
##   ignores_bs_worsening(attacker_unit, is_melee: bool) -> bool
##   attack_grants(out: Dictionary, attacker_unit, target_unit, is_melee: bool) -> void
##       fills out.lethal (source name), out.sustained (int), out.strength (int)
##   fnp_vs_mortal(unit) -> int
##   on_unit_has_attacked(attacker_unit_id: String) -> void
##   ignores_move_penalties(unit) -> bool
##   advance_roll_six(unit_id: String) -> bool
##   disembark_within(unit_id: String) -> bool
##   restrict_fight_candidates(player: int, candidates: Array) -> Array
## Window ctx notes: unit_selected_to_move may carry move_type "disembark"
## (DISEMBARK_UNIT, opened only when this player has a custom:sm11e row for
## that window) — check ctx.move_type. enemy_has_fought now also opens in the
## active player's own Fight phase when that player has a custom:sm11e row for
## it (TRANSHUMAN SWIFTNESS — "Fight phase", either turn).
## ---------------------------------------------------------------------------
##
## Engine-side effect consumers are at the bottom of this file; the engine
## files call them through one-line hooks commented "Codex: Space Marines
## (11e) … (SMCodex11e.gd)".

const Common = preload("res://scripts/codex/space_wolves/SWCommon.gd")
const GroupCombat = preload("res://scripts/codex/space_marines/SMCodexACombat.gd")
const GroupMovement = preload("res://scripts/codex/space_marines/SMCodexAMovement.gd")
const GroupCommand = preload("res://scripts/codex/space_marines/SMCodexACommand.gd")

const MARKER_EFFECT := "custom:sm11e"
const GROUP_B_PATH := "res://scripts/codex/space_marines/SMCodexB.gd"

# RulesEngine.HitModifier / WoundModifier values (pinned by
# tests/test_sm11e_stratagems_a.gd so a renumbering is caught).
const HIT_MINUS_ONE := 4
const WOUND_MINUS_ONE := 8

static var _group_b = null
static var _group_b_checked := false


## WP-M3b's group script, or null while it does not exist.
static func group_b():
	if not _group_b_checked:
		_group_b_checked = true
		if ResourceLoader.exists(GROUP_B_PATH):
			_group_b = load(GROUP_B_PATH)
			Common.log_info("SMCodex11e: WP-M3b group script loaded (%s)" % GROUP_B_PATH)
	return _group_b


static func _groups() -> Array:
	var out: Array = [GroupCombat, GroupMovement, GroupCommand]
	var b = group_b()
	if b != null:
		out.append(b)
	return out


## True for every Codex: Space Marines (11e) generic row (effects_json marker), registered or not.
static func handles(strat: Dictionary) -> bool:
	var effects = strat.get("effects", [])
	if typeof(effects) != TYPE_ARRAY or effects.is_empty():
		return false
	var first = effects[0]
	return typeof(first) == TYPE_DICTIONARY and str(first.get("type", "")) == MARKER_EFFECT


static func group_for_id(csv_id: String):
	for g in _groups():
		if csv_id in g.IDS:
			return g
	return null


static func group_for(strat: Dictionary):
	return group_for_id(str(strat.get("csv_id", "")))


static func is_registered(strat: Dictionary) -> bool:
	return handles(strat) and group_for(strat) != null


## The registry decides "implemented" — never name lists or regexes.
static func is_implemented(strat: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null:
		return false
	return bool(g.IMPLEMENTED.get(str(strat.get("csv_id", "")), false))


static func all_registered_ids() -> Array:
	var out: Array = []
	for g in _groups():
		out.append_array(g.IDS)
	return out


static func all_implemented_ids() -> Array:
	var out: Array = []
	for g in _groups():
		for k in g.IMPLEMENTED:
			if g.IMPLEMENTED[k]:
				out.append(k)
	return out


## WP-M3a's own csv ids (the A groups only).
static func group_a_ids() -> Array:
	var out: Array = []
	for g in [GroupCombat, GroupMovement, GroupCommand]:
		out.append_array(g.IDS)
	return out


## Candidate targets for a window offer (re-validated by StratagemManager).
static func eligible_targets(strat: Dictionary, player: int, window_id: String, ctx: Dictionary) -> Array:
	if not is_implemented(strat) or not Common.is_sm_army(player):
		return []
	var out = group_for(strat).eligible_targets(strat, player, window_id, ctx)
	return out if typeof(out) == TYPE_ARRAY else []


## Rule-specific target validation. Returns {ok, reason}.
static func validate(strat: Dictionary, player: int, target_unit_id: String, ctx: Dictionary) -> Dictionary:
	var g = group_for(strat)
	if g == null:
		return {"ok": false, "reason": "%s is not registered in the Codex: Space Marines dispatcher" % strat.get("name", "?")}
	if not is_implemented(strat):
		return {"ok": false, "reason": "%s is not yet mechanically implemented" % strat.get("name", "?")}
	if not Common.is_sm_army(player):
		return {"ok": false, "reason": "%s: only a Space Marine army (Codex: Space Marines 11e) can use it" % strat.get("name", "?")}
	var v = g.validate(strat, player, target_unit_id, ctx)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid validate() result"}
	return v


## Apply the effect: an Array of diffs, or {diffs, followup}.
static func apply(strat: Dictionary, target_unit_id: String, ctx: Dictionary) -> Variant:
	var g = group_for(strat)
	if g == null:
		Common.log_error("SMCodex11e: no handler registered for codex stratagem %s (%s) — effect NOT applied" % [
			strat.get("name", "?"), strat.get("csv_id", "?")])
		return []
	return g.apply(strat, target_unit_id, ctx)


static func clear(strat: Dictionary, unit_id: String) -> void:
	var g = group_for(strat)
	if g == null:
		return
	g.clear(strat, unit_id)


static func cp_cost_for(strat: Dictionary, ctx: Dictionary) -> int:
	var base := int(strat.get("cp_cost", 1))
	var variant := str(ctx.get("variant_id", ""))
	if variant == "":
		return base
	var g = group_for(strat)
	if g == null:
		return base
	var v := int(g.variant_cp_cost(strat, variant))
	return v if v >= 0 else base


static func variant_label(strat: Dictionary, variant_id: String) -> String:
	if variant_id == "":
		return ""
	var g = group_for(strat)
	if g == null or not g.has_method("variant_label"):
		return ""
	return str(g.variant_label(strat, variant_id))


static func allows_battle_shocked_target(strat: Dictionary, ctx: Dictionary) -> bool:
	var g = group_for(strat)
	if g == null or not is_implemented(strat):
		return false
	return bool(g.allows_battle_shocked_target(strat, ctx))


static func ai_kind(strat: Dictionary) -> String:
	var g = group_for(strat)
	if g == null:
		return "utility"
	return str(g.ai_kind(strat))


static func ai_score(strat: Dictionary, player: int, target_unit_id: String, window_id: String, ctx: Dictionary) -> float:
	var g = group_for(strat)
	if g == null or not is_implemented(strat):
		return 0.0
	return float(g.ai_score(strat, player, target_unit_id, window_id, ctx))


## True when `player` has an implemented Codex: Space Marines stratagem offered
## in `window_id` (the phases only route a UI step through a window when it
## could offer something — no behaviour change for other armies).
static func player_has_window_stratagem(player: int, window_id: String) -> bool:
	if GameConstants.edition < 11:
		return false
	var sm = Common.stratagem_manager()
	if sm == null or not sm.has_method("get_faction_stratagems_for_player"):
		return false
	for s in sm.get_faction_stratagems_for_player(player):
		if not handles(s) or not is_implemented(s):
			continue
		if window_id in s.get("timing", {}).get("windows", []):
			return true
	return false


# ===========================================================================
# ENGINE HOOKS — called from RulesEngine / the phases / FightSequencer /
# DisembarkController through one-line hooks ("SMCodex11e.gd")
# ===========================================================================

static func _consumers(method: String) -> Array:
	var out: Array = []
	for g in _groups():
		if g.has_method(method):
			out.append(g)
	return out


## AP of one attack batch against `target_unit` (every AP site): ARMOUR OF
## CONTEMPT (-1 AP for attacks that target the unit).
static func modify_ap(ap: int, attacker_unit: Dictionary, target_unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return ap
	var out := ap
	for g in _consumers("modify_ap"):
		out = int(g.modify_ap(out, attacker_unit, target_unit))
	return out


## Hit-roll modifiers on one attack batch (RulesEngine HitModifier bit set +
## the modifier ledger): HURTLING TARGETS / UMBRAL EVASION (-1 to hit for
## ranged attacks that target the unit), then MIGHT OF THE MACHINE SPIRIT
## (the attacker ignores hit-roll penalties). Placed after every other hit
## modifier at each site.
static func apply_hit_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, ledger: Array) -> int:
	if GameConstants.edition < 11:
		return bits
	var out := bits
	for g in _consumers("hit_bits"):
		out = int(g.hit_bits(out, attacker_unit, target_unit, is_melee, ledger))
	if out != bits:
		Common.log_info("[SMCodex11e] hit roll (%s) %s vs %s: bits %d -> %d" % ["melee" if is_melee else "ranged",
			str(attacker_unit.get("id", "?")), str(target_unit.get("id", "?")), bits, out])
	return out


## Wound-roll modifiers (MIGHT OF THE MACHINE SPIRIT ignores -1 to wound).
static func apply_wound_bits(bits: int, attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool, ledger: Array) -> int:
	if GameConstants.edition < 11:
		return bits
	var out := bits
	for g in _consumers("wound_bits"):
		out = int(g.wound_bits(out, attacker_unit, target_unit, is_melee, ledger))
	if out != bits:
		Common.log_info("[SMCodex11e] wound roll (%s) %s vs %s: bits %d -> %d" % ["melee" if is_melee else "ranged",
			str(attacker_unit.get("id", "?")), str(target_unit.get("id", "?")), bits, out])
	return out


## True when the attacker ignores BS worsening (benefit of cover and the other
## harmful BS modifiers) — MIGHT OF THE MACHINE SPIRIT.
static func ignores_bs_worsening(attacker_unit: Dictionary, is_melee: bool) -> bool:
	if GameConstants.edition < 11:
		return false
	for g in _consumers("ignores_bs_worsening"):
		if bool(g.ignores_bs_worsening(attacker_unit, is_melee)):
			return true
	return false


## Remove the harmful BS / hit-roll entries of an 11e hit ModifierStack when
## the attacker ignores them (MIGHT OF THE MACHINE SPIRIT). Returns the
## sources removed.
static func filter_hit_stack(attacker_unit: Dictionary, stack, is_melee: bool) -> Array:
	var removed: Array = []
	if stack == null or not ignores_bs_worsening(attacker_unit, is_melee):
		return removed
	var kept: Array = []
	for e in stack.entries:
		var t := str(e.get("type", ""))
		var v := int(e.get("value", 0))
		if (t == "bs" and v > 0) or (t == "hit_roll" and v < 0):
			removed.append(str(e.get("source", t)))
		else:
			kept.append(e)
	stack.entries = kept
	if not removed.is_empty():
		Common.log_info("[SMCodex11e] MIGHT OF THE MACHINE SPIRIT: ignoring %s for %s" % [str(removed), str(attacker_unit.get("id", "?"))])
	return removed


## Weapon-ability grants for one attack batch: {lethal: source|"" ([LETHAL
## HITS]), sustained: int ([SUSTAINED HITS n]), strength: int (+S)} —
## HEADHUNTER DOCTRINE, RELENTLESS ASSAULT, STRIKE FROM THE SHADOWS.
static func attack_grants(attacker_unit: Dictionary, target_unit: Dictionary, is_melee: bool) -> Dictionary:
	var out := {"lethal": "", "sustained": 0, "strength": 0, "sources": []}
	if GameConstants.edition < 11:
		return out
	for g in _consumers("attack_grants"):
		g.attack_grants(out, attacker_unit, target_unit, is_melee)
	if not out.sources.is_empty():
		Common.log_info("[SMCodex11e] %s attack grants for %s vs %s: %s" % ["melee" if is_melee else "ranged",
			str(attacker_unit.get("id", "?")), str(target_unit.get("id", "?")), str(out)])
	return out


## LAYERED CERAMITE: Feel No Pain 5+ against mortal wounds (RulesEngine._conditional_fnp). 0 = none.
static func fnp_vs_mortal(unit: Dictionary) -> int:
	if GameConstants.edition < 11:
		return 0
	var best := 0
	for g in _consumers("fnp_vs_mortal"):
		var v := int(g.fnp_vs_mortal(unit))
		if v > 0 and (best == 0 or v < best):
			best = v
	return best


## An attacking unit has finished its attacks: ARMOUR OF CONTEMPT ("until
## that enemy unit has attacked") ends for the units it protected against it.
static func on_unit_has_attacked(attacker_unit_id: String) -> void:
	if GameConstants.edition < 11 or attacker_unit_id == "":
		return
	for g in _consumers("on_unit_has_attacked"):
		g.on_unit_has_attacked(attacker_unit_id)


## MIGHT OF THE MACHINE SPIRIT: the unit ignores harmful modifiers to its M.
static func ignores_move_penalties(unit: Dictionary) -> bool:
	if GameConstants.edition < 11:
		return false
	for g in _consumers("ignores_move_penalties"):
		if bool(g.ignores_move_penalties(unit)):
			return true
	return false


## SUDDEN ONSLAUGHT: the unit changes its advance roll to a 6.
static func advance_roll_six(unit_id: String) -> bool:
	if GameConstants.edition < 11:
		return false
	for g in _consumers("advance_roll_six"):
		if bool(g.advance_roll_six(unit_id)):
			return true
	return false


## AGGRESSIVE DISEMBARKATION: the disembarking unit's models are set up WITHIN
## (not wholly within) the set-up distance of the TRANSPORT.
static func disembark_within(unit_id: String) -> bool:
	if GameConstants.edition < 11:
		return false
	for g in _consumers("disembark_within"):
		if bool(g.disembark_within(unit_id)):
			return true
	return false


## TransportManager.is_position_within_disembark_range result, widened to
## "within" (near edge <= set-up distance) for AGGRESSIVE DISEMBARKATION.
static func disembark_range_ok(unit_id: String, range_result: Dictionary, setup_range_inches: float) -> bool:
	if bool(range_result.get("within_range", false)):
		return true
	if not disembark_within(unit_id):
		return false
	return float(range_result.get("distance_inches", INF)) <= setup_range_inches + 0.01


## FightSequencer candidates for `player` — TRANSHUMAN SWIFTNESS: "must be the
## next unit you select to fight".
static func restrict_fight_candidates(player: int, candidates: Array) -> Array:
	if GameConstants.edition < 11:
		return candidates
	var out := candidates
	for g in _consumers("restrict_fight_candidates"):
		out = g.restrict_fight_candidates(player, out)
	return out


## A WORTHY DEATH: the Fight On Death mode this dispatcher owns.
static func is_fod_mode(mode: String) -> bool:
	return mode == GroupCombat.FOD_MODE_WORTHY

## A WORTHY DEATH: "roll one D6: On a 4+, do not remove that model" — no modifier.
static func fod_roll(_unit_id: String, _model_index: int) -> Dictionary:
	return {"mod": 0, "note": "", "pass": GroupCombat.WORTHY_PASS}


## MORTIS SNARES — the action about to run (BasePhase.execute_action, outermost
## action): remember where the enemy units of every snaring player stand.
static func on_action_begin(action_type: String) -> void:
	if GameConstants.edition < 11:
		return
	GroupCommand.snare_baseline(action_type)

## MORTIS SNARES — the action has been applied: an enemy unit that ENDED a move
## within range of a snared objective rolls (D6 2+: D6 mortal wounds) and the
## objective is no longer snared. Returns the diffs it applied (the caller
## merges them into the action's result).
static func on_action_applied(phase_name: String) -> Array:
	if GameConstants.edition < 11:
		return []
	return GroupCommand.snare_detect(phase_name)

## WIND-SWIFT EVASION follow-up solver (AI decider / the move panel's
## Auto-move): positions (key -> Vector2) that end the normal / fall-back move
## unengaged, or {} when none was found.
static func solve_fight_move(unit_id: String, origin: Dictionary, max_inches: float, kind: String) -> Dictionary:
	return GroupMovement.solve_fight_move(unit_id, origin, max_inches, kind)
