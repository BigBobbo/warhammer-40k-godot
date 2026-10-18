class_name FightSequencer
extends RefCounted

## ISS-050 — the 11e Fight step state machine (12.04-12.06).
##
## A unit is ELIGIBLE TO FIGHT if it has not been selected to fight this
## phase and it is engaged, was engaged at the start of the Fight step,
## or made a charge move this turn.
##
## Selection sequence (12.04):
##  1. RESOLVE FIGHTS FIRST COMBATS — starting with the active player,
##     players alternate selecting a friendly Fights First unit that is
##     eligible. If the picker cannot: no FF units eligible at all →
##     move to step 2 with THIS player selecting next; otherwise the
##     other player selects.
##  2. RESOLVE REMAINING COMBATS — same alternation over all eligible
##     units; when the picker cannot select: none eligible at all → the
##     Fight step ends; otherwise the other player selects.
##  After a remaining-combats fight, if Fights First units are now
##  eligible, return to step 1.
##
## Fight types (when selected): NORMAL (12.05, engaged) or OVERRUN
## (12.06, unengaged — e.g. its target died — with one additional
## pile-in move before fighting).
##
## The phase drives: begin() → next_selection() → select_to_fight() →
## (resolve attacks) → repeat until next_selection().done. Engaging
## consolidation's forced fights (12.08) reuse select_to_fight with
## eligibility overridden by the rule itself.

var active_player: int = 1
var picker: int = 1
var step: String = "fights_first"
var fought: Dictionary = {}                 # unit_id -> true
var engaged_at_step_start: Dictionary = {}  # unit_id -> bool
# "Eligible to fight, but unable to fight" (core rules p.74): a player whose
# eligible units are ALL more than 5" from every enemy unit may PASS instead
# of selecting. player -> true while that pass stands — it is cleared when the
# sequence returns to them (their opponent selects a unit). If both players
# pass in succession, or one passes while the opponent has nothing eligible,
# the Fight step ends (next_selection reports done).
var passed: Dictionary = {}

## The pass rule's distance: more than this many inches from ALL enemy units.
const UNABLE_TO_FIGHT_DISTANCE_INCHES := 5.0

## Unit flag holding the turn_key() of the turn in which the unit's fight
## was resolved (fought, skipped, or ended by passes) — see eligible_to_fight.
const FIGHT_DONE_FLAG := "fight_done_turn"

## "<battle round>:<active player>" — identifies one player turn.
static func turn_key(board: Dictionary) -> String:
	var meta: Dictionary = board.get("meta", {})
	return "%d:%d" % [int(meta.get("battle_round", 0)), int(meta.get("active_player", 0))]


static func _rules() -> Node:
	return Engine.get_main_loop().root.get_node("/root/RulesEngine")


# Autoloads are looked up at call time (not referenced by name) so this
# class_name script compiles even before the autoloads exist.
static func _measurement() -> Node:
	return Engine.get_main_loop().root.get_node("/root/Measurement")


## Snapshot engagement state at the start of the Fight step (12.04's
## "was engaged at the start of this step" clause).
func begin(board: Dictionary, p_active_player: int) -> void:
	active_player = p_active_player
	picker = p_active_player
	step = "fights_first"
	fought = {}
	engaged_at_step_start = {}
	passed = {}
	var rules = _rules()
	for unit_id in board.get("units", {}):
		engaged_at_step_start[unit_id] = rules.is_unit_engaged(unit_id, board)


func is_fights_first(unit: Dictionary) -> bool:
	if unit.get("flags", {}).get("fights_first", false):
		return true
	# Codex: Adeptus Custodes (11e) Emissaries Imperatus — Heralds of the
	# Throne: friendly ADEPTUS CUSTODES units have Fights First (WP-C46).
	if load("res://scripts/codex/custodes/CustodesDetachments.gd").has_fights_first(unit):
		return true
	return UnitAbilities.unit_has(unit, "fights first")


func eligible_to_fight(unit_id: String, board: Dictionary) -> bool:
	if fought.get(unit_id, false):
		return false
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty() or not _any_alive(unit):
		return false
	# flags.fight_done_turn is the synced record that this unit's fight is
	# over THIS turn (the host stamps it when an activation resolves or is
	# skipped, and when the Fight step ends with passed units). A multiplayer
	# client's sequencer never sees the host's mark_fought calls, so it reads
	# the stamp instead. Turn-scoped on purpose: flags.has_fought is only
	# cleared for the player whose turn starts, so it leaks into the
	# opponent's Fight phase and cannot be used here.
	if str(unit.get("flags", {}).get(FIGHT_DONE_FLAG, "")) == turn_key(board):
		return false
	if _rules().is_unit_engaged(unit_id, board):
		return true
	if engaged_at_step_start.get(unit_id, false):
		return true
	return unit.get("flags", {}).get("charged_this_turn", false)


## 19.03 — ATTACHED UNITS FIGHT AS ONE.
##
## A CHARACTER attached to a bodyguard is not a unit of its own: the pair get
## ONE entry in the fight list, ONE activation, and the enemy never gets to
## activate in between. The state model keeps them as separate unit dicts, so
## everything below asks the same question of every component and folds the
## answer onto the BODYGUARD, which is the id the phase activates.
##
## The component ids of the Attached unit headed by unit_id.
func group_ids(unit_id: String, board: Dictionary) -> Array:
	return _rules().attached_unit_component_ids(unit_id, board)


## True when unit_id is an attached CHARACTER — it never appears in the fight
## list in its own right, its bodyguard's entry stands for it.
func is_attached_component(unit_id: String, board: Dictionary) -> bool:
	return _rules().is_attached_character(unit_id, board)


## The Attached unit is eligible when ANY of its components is — e.g. a
## bodyguard standing off the enemy while only its Leader's model is engaged.
func group_eligible_to_fight(unit_id: String, board: Dictionary) -> bool:
	for member_id in group_ids(unit_id, board):
		if eligible_to_fight(member_id, board):
			return true
	return false


## Likewise Fights First: one unit, so a charge (or ability) on any component
## gives the whole Attached unit the Fights First step.
func group_is_fights_first(unit_id: String, board: Dictionary) -> bool:
	for member_id in group_ids(unit_id, board):
		var unit = board.get("units", {}).get(member_id, {})
		if not unit.is_empty() and is_fights_first(unit):
			return true
	return false


func eligible_units(board: Dictionary, player: int, only_fights_first: bool) -> Array:
	var out: Array = []
	for unit_id in board.get("units", {}):
		var unit = board.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		# 19.03: an attached CHARACTER is offered through its bodyguard's entry,
		# never as a candidate of its own — otherwise the Warboss leading a mob
		# of Boyz took a SECOND activation after theirs, and the enemy got to
		# swing in between.
		if is_attached_component(unit_id, board):
			continue
		if only_fights_first and not group_is_fights_first(unit_id, board):
			continue
		if group_eligible_to_fight(unit_id, board):
			out.append(unit_id)
	return out


## The units `player` may actually be asked to select from: their eligible
## units, unless they have passed and the sequence has not come back to them.
func selectable_units(board: Dictionary, player: int, only_fights_first: bool) -> Array:
	if passed.get(player, false):
		return []
	# Codex: Adeptus Custodes INDOMITABLE GUARDIANS (CustodesCodex11e.gd): "must be the next unit you select to fight".
	return load("res://scripts/codex/custodes/CustodesCodex11e.gd").restrict_fight_candidates(player, eligible_units(board, player, only_fights_first))


## "Eligible to fight, but unable to fight" (core rules p.74): true when
## `player` has at least one eligible unit and EVERY one of them is more than
## 5" from all enemy units. Only then may the player pass instead of
## selecting a unit — every other eligible unit MUST be selected (12.04).
func can_pass(board: Dictionary, player: int) -> bool:
	var mine = eligible_units(board, player, false)
	if mine.is_empty():
		return false
	for unit_id in mine:
		if within_distance_of_enemy(unit_id, board, UNABLE_TO_FIGHT_DISTANCE_INCHES):
			return false
	return true


## True when any model of the Attached unit headed by unit_id is within
## `inches` (edge to edge, shape aware) of any alive, on-table enemy model.
func within_distance_of_enemy(unit_id: String, board: Dictionary, inches: float) -> bool:
	var units: Dictionary = board.get("units", {})
	var owner := int(units.get(unit_id, {}).get("owner", 0))
	for member_id in group_ids(unit_id, board):
		var member = units.get(member_id, {})
		for model in member.get("models", []):
			if not model.get("alive", true) or model.get("position", null) == null:
				continue
			for other_id in units:
				var other = units[other_id]
				if int(other.get("owner", 0)) == owner:
					continue
				for enemy_model in other.get("models", []):
					if not enemy_model.get("alive", true) or enemy_model.get("position", null) == null:
						continue
					if _measurement().model_to_model_distance_inches(model, enemy_model) <= inches:
						return true
	return false


## `player` passes their selection (see can_pass — the caller validates).
## The sequence returns to their opponent; the pass stands until the
## opponent selects a unit. Returns true when this pass ends the Fight step
## (both players passed in succession, or the opponent has nothing eligible).
func pass_selection(board: Dictionary, player: int) -> bool:
	passed[player] = true
	picker = _other(player)
	return peek_selection(board).done


## True once the Fight step is over: nobody is left to select (everyone has
## fought, or the remaining units' owners have all passed — p.74).
func step_over(board: Dictionary) -> bool:
	return peek_selection(board).done


## Who selects next, and from which candidates. Returns
## {done: bool, player, step, candidates} — call select_to_fight with
## one of the candidates, resolve the fight, then call this again.
func next_selection(board: Dictionary) -> Dictionary:
	while true:
		if step == "fights_first":
			var mine = selectable_units(board, picker, true)
			if not mine.is_empty():
				return {"done": false, "player": picker, "step": step, "candidates": mine}
			var theirs = selectable_units(board, _other(picker), true)
			if not theirs.is_empty():
				picker = _other(picker)
				return {"done": false, "player": picker, "step": step, "candidates": theirs}
			# No Fights First units eligible at all: this player selects
			# next in the remaining-combats step (12.04 step 1).
			step = "remaining"
		else:
			var mine = selectable_units(board, picker, false)
			if not mine.is_empty():
				return {"done": false, "player": picker, "step": step, "candidates": mine}
			var theirs = selectable_units(board, _other(picker), false)
			if not theirs.is_empty():
				picker = _other(picker)
				return {"done": false, "player": picker, "step": step, "candidates": theirs}
			return {"done": true, "player": 0, "step": step, "candidates": []}
	return {"done": true, "player": 0, "step": step, "candidates": []}


## Pure preview of next_selection(): who would select next, and from which
## candidates — WITHOUT advancing picker/step. get_available_actions polls
## this every UI/AI refresh, so the poll must not mutate alternation state;
## the walk is re-derived from (picker, step) + board each call and always
## converges to the same answer next_selection() would return.
func peek_selection(board: Dictionary) -> Dictionary:
	var p := picker
	var s := step
	while true:
		if s == "fights_first":
			var mine = selectable_units(board, p, true)
			if not mine.is_empty():
				return {"done": false, "player": p, "step": s, "candidates": mine}
			var theirs = selectable_units(board, _other(p), true)
			if not theirs.is_empty():
				return {"done": false, "player": _other(p), "step": s, "candidates": theirs}
			s = "remaining"
		else:
			var mine = selectable_units(board, p, false)
			if not mine.is_empty():
				return {"done": false, "player": p, "step": s, "candidates": mine}
			var theirs = selectable_units(board, _other(p), false)
			if not theirs.is_empty():
				return {"done": false, "player": _other(p), "step": s, "candidates": theirs}
			return {"done": true, "player": 0, "step": s, "candidates": []}
	return {"done": true, "player": 0, "step": s, "candidates": []}


## Mark the unit as selected to fight and report its available fight
## types (12.05/12.06): {fight_types: Array, fight_type: String}.
## Alternation passes to the other player (12.04).
func select_to_fight(unit_id: String, board: Dictionary) -> Dictionary:
	# 19.03: selecting the Attached unit spends the WHOLE unit's one fight —
	# marking only the bodyguard left its Leader eligible, so he came back round
	# for a second activation of his own.
	for member_id in group_ids(unit_id, board):
		fought[member_id] = true
	var unit = board.get("units", {}).get(unit_id, {})
	picker = _other(int(unit.get("owner", 0)))
	# The sequence now returns to the other player — a pass they made earlier
	# no longer stands (p.74: "when the sequence returns to a player").
	passed.erase(picker)
	var types: Array = []
	# Engagement is the Attached unit's: the Leader's model counts as this
	# unit's, so a bodyguard engaged only through him fights normally.
	var engaged: bool = false
	var engaged_at_start: bool = false
	for member_id in group_ids(unit_id, board):
		if _rules().is_unit_engaged(member_id, board):
			engaged = true
		if engaged_at_step_start.get(member_id, false):
			engaged_at_start = true
	if engaged:
		types.append("normal")
	# 12.06: unengaged (e.g. its targets died), OR was unengaged at the
	# start of the step but became engaged during the phase (such a unit
	# may choose the overrun fight's extra pile-in instead of a normal
	# fight).
	if not engaged or not engaged_at_start:
		types.append("overrun")
	return {"fight_types": types, "fight_type": types[0]}


## Exact inverse of select_to_fight — the unit was NEVER selected as far as
## the sequencer is concerned: its fought stamp is cleared (so it is offered
## again) and the pick is handed back to its owner (undoing the alternation
## hand-over). Used by the phase's CANCEL_FIGHTER_SELECTION escape hatch,
## which lets a player back out of an activation they mis-picked before any
## attack is assigned. Safe to call for a unit that was never selected.
func unselect_to_fight(unit_id: String, board: Dictionary) -> void:
	fought.erase(unit_id)
	var unit = board.get("units", {}).get(unit_id, {})
	var owner := int(unit.get("owner", 0))
	if owner > 0:
		picker = owner


## Pure query — true while ANY unit (either player) is still eligible to
## fight. Unlike next_selection() this never mutates picker/step, so
## validators and get_available_actions can poll it safely. Used by the
## 11e global Consolidate step (12.07) to tell "fight step still running /
## forced fights pending" apart from "consolidation may proceed".
func has_eligible(board: Dictionary) -> bool:
	for unit_id in board.get("units", {}):
		# Mirror eligible_units: an attached CHARACTER is never a fight of its
		# own, so a Leader left un-marked must not keep the Fight step open
		# (which would stall the 12.07 Consolidate step forever).
		if is_attached_component(unit_id, board):
			continue
		if group_eligible_to_fight(unit_id, board):
			return true
	return false


## Mark a unit as fought without a real selection — used when the Fight
## step ends with passed units still eligible (p.74) or a unit is skipped, so
## the sequencer's candidate list stays consistent (a skipped unit must
## not be offered forever).
## Pass `board` to spend the whole ATTACHED unit's fight (19.03) — without it
## only the named unit is marked, which is right for callers that already walk
## the components themselves.
func mark_fought(unit_id: String, board: Dictionary = {}) -> void:
	fought[unit_id] = true
	if board.is_empty():
		return
	for member_id in group_ids(unit_id, board):
		fought[member_id] = true


## Call after each fight resolved in the remaining-combats step: if
## Fights First units are now eligible, return to step 1 (12.04).
func after_fight_resolved(board: Dictionary) -> void:
	if step != "remaining":
		return
	if not eligible_units(board, 1, true).is_empty() or not eligible_units(board, 2, true).is_empty():
		step = "fights_first"


func _other(player: int) -> int:
	return 2 if player == 1 else 1


func _any_alive(unit: Dictionary) -> bool:
	for m in unit.get("models", []):
		if m.get("alive", true):
			return true
	return false
