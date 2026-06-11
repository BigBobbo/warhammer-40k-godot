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


static func _rules() -> Node:
	return Engine.get_main_loop().root.get_node("/root/RulesEngine")


## Snapshot engagement state at the start of the Fight step (12.04's
## "was engaged at the start of this step" clause).
func begin(board: Dictionary, p_active_player: int) -> void:
	active_player = p_active_player
	picker = p_active_player
	step = "fights_first"
	fought = {}
	engaged_at_step_start = {}
	var rules = _rules()
	for unit_id in board.get("units", {}):
		engaged_at_step_start[unit_id] = rules.is_unit_engaged(unit_id, board)


func is_fights_first(unit: Dictionary) -> bool:
	if unit.get("flags", {}).get("fights_first", false):
		return true
	return UnitAbilities.unit_has(unit, "fights first")


func eligible_to_fight(unit_id: String, board: Dictionary) -> bool:
	if fought.get(unit_id, false):
		return false
	var unit = board.get("units", {}).get(unit_id, {})
	if unit.is_empty() or not _any_alive(unit):
		return false
	if _rules().is_unit_engaged(unit_id, board):
		return true
	if engaged_at_step_start.get(unit_id, false):
		return true
	return unit.get("flags", {}).get("charged_this_turn", false)


func eligible_units(board: Dictionary, player: int, only_fights_first: bool) -> Array:
	var out: Array = []
	for unit_id in board.get("units", {}):
		var unit = board.units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if only_fights_first and not is_fights_first(unit):
			continue
		if eligible_to_fight(unit_id, board):
			out.append(unit_id)
	return out


## Who selects next, and from which candidates. Returns
## {done: bool, player, step, candidates} — call select_to_fight with
## one of the candidates, resolve the fight, then call this again.
func next_selection(board: Dictionary) -> Dictionary:
	while true:
		if step == "fights_first":
			var mine = eligible_units(board, picker, true)
			if not mine.is_empty():
				return {"done": false, "player": picker, "step": step, "candidates": mine}
			var theirs = eligible_units(board, _other(picker), true)
			if not theirs.is_empty():
				picker = _other(picker)
				return {"done": false, "player": picker, "step": step, "candidates": theirs}
			# No Fights First units eligible at all: this player selects
			# next in the remaining-combats step (12.04 step 1).
			step = "remaining"
		else:
			var mine = eligible_units(board, picker, false)
			if not mine.is_empty():
				return {"done": false, "player": picker, "step": step, "candidates": mine}
			var theirs = eligible_units(board, _other(picker), false)
			if not theirs.is_empty():
				picker = _other(picker)
				return {"done": false, "player": picker, "step": step, "candidates": theirs}
			return {"done": true, "player": 0, "step": step, "candidates": []}
	return {"done": true, "player": 0, "step": step, "candidates": []}


## Mark the unit as selected to fight and report its available fight
## types (12.05/12.06): {fight_types: Array, fight_type: String}.
## Alternation passes to the other player (12.04).
func select_to_fight(unit_id: String, board: Dictionary) -> Dictionary:
	fought[unit_id] = true
	var unit = board.get("units", {}).get(unit_id, {})
	picker = _other(int(unit.get("owner", 0)))
	var types: Array = []
	var engaged: bool = _rules().is_unit_engaged(unit_id, board)
	if engaged:
		types.append("normal")
	# 12.06: unengaged (e.g. its targets died), OR was unengaged at the
	# start of the step but became engaged during the phase (such a unit
	# may choose the overrun fight's extra pile-in instead of a normal
	# fight).
	if not engaged or not engaged_at_step_start.get(unit_id, false):
		types.append("overrun")
	return {"fight_types": types, "fight_type": types[0]}


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
