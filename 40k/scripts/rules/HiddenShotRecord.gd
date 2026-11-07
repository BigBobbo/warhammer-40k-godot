extends RefCounted

## 13.09 HIDDEN, second bullet — "That model's unit did not make one or more
## ranged attacks during this turn or during the previous turn."
##
## The ONE shot record that every path making ranged attacks writes — the
## Shooting phase completions, FIRE OVERWATCH and any other snap shooting
## (15.08 / 15.09: "Your unit shoots as described in Making Attacks (04)"),
## RAPID REACTIONS and the other out-of-phase "your unit shoots" follow-ups —
## and that TerrainManager.is_model_hidden / detection_range_inches_for read.
##
## Turns are GameState.get_player_turn_index() (play order, keyed on the
## first-turn player: battle round R's first turn = 2R, its second = 2R + 1).
## 19.01 — "An attached unit is a single unit for all rules purposes": EVERY
## component of an Attached unit carries the record, so an attached leader that
## shot with its bodyguard is not left looking as if it never fired.
##
## Flags (per component):
##   last_shot_idx           latest turn whose ranged attacks count against
##                           Hidden.
##   prev_shot_idx           last_shot_idx as it was before this turn's first
##                           stamp, so a waiver ("those attacks do not prevent
##                           that unit from being hidden" — Shadow Masters)
##                           drops only THIS turn's attacks: a FIRE OVERWATCH in
##                           the previous turn still counts.
##   last_ranged_attack_idx  latest turn the unit made ranged attacks at all,
##                           waived or not. 13.11.01 Gone to Ground, Designer's
##                           Note: "Units that made ranged attacks in the current
##                           or previous turn cannot go to ground, regardless of
##                           any abilities that allow them to shoot and remain
##                           hidden."
##
## No compile-time autoload references (callers preload this from autoloads and
## from scripts that headless tests compile before the autoloads exist).

const F_LAST := "last_shot_idx"
const F_PREV := "prev_shot_idx"
const F_ATTACK := "last_ranged_attack_idx"
const F_LEGACY := "shot_recently"
## "Never shot" — what an absent stamp reads as.
const NEVER := -100
## No live turn counter (no GameState): only the legacy shot_recently flag counts.
const NO_TURN := -1000000

static func _autoload(node_name: String) -> Node:
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(node_name)
	return null

## The current player turn's play-order index, or NO_TURN without a GameState.
static func current_turn_index() -> int:
	var gs = _autoload("GameState")
	if gs != null and gs.has_method("get_player_turn_index"):
		return int(gs.get_player_turn_index())
	return NO_TURN

## 13.09: did the unit make ranged attacks that count against Hidden during
## this turn or the previous turn? `shot_recently` (set directly by headless
## tests and effect code) always counts.
static func shot_this_or_previous_turn(unit: Dictionary, cur_idx: int) -> bool:
	var f: Dictionary = unit.get("flags", {})
	if f.get(F_LEGACY, false):
		return true
	if cur_idx == NO_TURN:
		return false
	return cur_idx - int(f.get(F_LAST, NEVER)) < 2

## 13.11.01: did the unit make ANY ranged attacks during this turn or the
## previous turn — including attacks a rule says do not prevent it from being
## hidden? Such a unit cannot go to ground.
static func attacked_this_or_previous_turn(unit: Dictionary, cur_idx: int) -> bool:
	if shot_this_or_previous_turn(unit, cur_idx):
		return true
	if cur_idx == NO_TURN:
		return false
	return cur_idx - int(unit.get("flags", {}).get(F_ATTACK, NEVER)) < 2

static func _live_board() -> Dictionary:
	var gs = _autoload("GameState")
	if gs != null and "state" in gs:
		return gs.state
	return {}

## The component unit ids of unit_id's Attached unit (head first), or [unit_id].
static func component_ids(unit_id: String, board: Dictionary) -> Array:
	var re = _autoload("RulesEngine")
	if re == null:
		return [unit_id]
	var head := str(re.attached_unit_target_id(unit_id, board))
	var ids: Array = re.attached_unit_component_ids(head, board)
	if not unit_id in ids:
		ids.append(unit_id)
	return ids

static func _flag_diff(unit_id: String, flag: String, value) -> Dictionary:
	return {"op": "set", "path": "units.%s.flags.%s" % [unit_id, flag], "value": value}

## The diffs recording that unit_id's Attached unit made ranged attacks in the
## current turn — one stamp per component. `board` defaults to the live
## GameState; its flags are read to keep prev_shot_idx (the record from before
## this turn) on the turn's first stamp.
static func stamp_diffs(unit_id: String, board: Dictionary = {}) -> Array:
	var b: Dictionary = board if not board.is_empty() else _live_board()
	var idx := current_turn_index()
	if idx == NO_TURN:
		return []
	var units: Dictionary = b.get("units", {})
	var out: Array = []
	for cid in component_ids(unit_id, b):
		var u: Dictionary = units.get(str(cid), {})
		if u.is_empty():
			continue
		var last := int(u.get("flags", {}).get(F_LAST, NEVER))
		if last < idx:
			out.append(_flag_diff(str(cid), F_PREV, last))
		out.append(_flag_diff(str(cid), F_LAST, idx))
		out.append(_flag_diff(str(cid), F_ATTACK, idx))
	return out

## "Those attacks do not prevent that unit from being hidden" (Shadow Masters,
## SUPPRESSED WEAPONS): drop THIS turn's attacks from the Hidden record of
## every component — last_shot_idx goes back to what it was before this turn
## (prev_shot_idx), so an earlier turn's attacks still count. The legacy
## shot_recently flag is cleared too. last_ranged_attack_idx is kept: the unit
## still cannot go to ground (13.11.01).
static func waive_this_turn_diffs(unit_id: String, board: Dictionary = {}) -> Array:
	var b: Dictionary = board if not board.is_empty() else _live_board()
	var idx := current_turn_index()
	var units: Dictionary = b.get("units", {})
	var out: Array = []
	for cid in component_ids(unit_id, b):
		var f: Dictionary = units.get(str(cid), {}).get("flags", {})
		if idx != NO_TURN and f.has(F_LAST) and int(f.get(F_LAST, NEVER)) >= idx:
			out.append(_flag_diff(str(cid), F_LAST, int(f.get(F_PREV, NEVER))))
		if f.has(F_LEGACY):
			out.append({"op": "remove", "path": "units.%s.flags.%s" % [str(cid), F_LEGACY]})
	return out
