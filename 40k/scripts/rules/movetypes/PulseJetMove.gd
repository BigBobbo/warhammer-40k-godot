extends MoveType

## WP-G3 — Codex: Orks (11e) army rule "Special Move Types": PULSE JET MOVE.
## Made by Wazdakka Gutsmek while Full Throttle gave it the Pulse Jet engine
## ("In your Movement phase, when this unit is selected to move, if this unit
## is unengaged, this unit can make a pulse jet move").
##
##   MAXIMUM DISTANCE  pulse roll + 18".
##   ELIGIBLE IF       as stated in the rule allowing it (Pulse Jet: own Movement
##                     phase, selected to move, unengaged) — OrkAbilities11e.
##                     pulse_jet_granted + the checks below.
##   BEFORE MOVING     pulse roll: one D6.
##   WHILE MOVING      ignore all vertical distance; move through all types of
##                     model; move horizontally and vertically through all
##                     categories of terrain feature (MovementPhase reads
##                     moves_through_everything() for its model / terrain gates).
##   AFTER MOVING      must be unengaged; until the end of the turn not eligible
##                     to declare a charge or start an action; until the start of
##                     your next turn attacks that target the unit have -1 to hit
##                     (OrkAbilities11e.pulse_jet_after_effects / F_PULSE_JET).
##
## MovementPhase drives it as mode "PULSE_JET" (action BEGIN_PULSE_JET_MOVE).
## Registered in MoveTypes as "pulse_jet" (no class_name: preloaded there).

const OrkAbilities := preload("res://scripts/codex/orks/OrkAbilities11e.gd")

const MODE := "PULSE_JET"

func _init():
	id = "pulse_jet"
	display_name = "Pulse Jet"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"eligible": false, "reasons": ["pulse jet moves are a Codex: Orks (11e) move type"]}
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	var emb = unit.get("embarked_in", null)
	if emb != null and str(emb) != "":
		return {"eligible": false, "reasons": ["unit is embarked"]}
	var att = unit.get("attached_to", null)
	if att != null and str(att) != "":
		return {"eligible": false, "reasons": ["an attached character moves with its bodyguard unit"]}
	if not OrkAbilities.pulse_jet_granted(unit_id):
		return {"eligible": false, "reasons": ["Full Throttle did not select the Pulse Jet engine for this unit"]}
	if unit.get("flags", {}).get("moved", false):
		return {"eligible": false, "reasons": ["unit has already moved this phase"]}
	if _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is engaged (Pulse Jet: if this unit is unengaged)"]}
	return {"eligible": true, "reasons": []}

## BEFORE MOVING: make a pulse roll (one D6).
func before_moving(_unit_id: String, _board: Dictionary, rng, _context: Dictionary) -> Dictionary:
	var roll: int = int(rng.roll_d6(1)[0])
	return {"pulse_roll": roll, "dice": [{"context": "pulse_roll", "rolls": [roll]}]}

## MAXIMUM DISTANCE: pulse roll + 18".
func max_distance_inches(_unit: Dictionary, context: Dictionary) -> float:
	return OrkAbilities.PULSE_JET_BASE_INCHES + float(context.get("pulse_roll", 0))

## WHILE MOVING: true for a move record (MovementPhase.active_moves entry) of
## a pulse jet move — ignore vertical distance, move through all models and all
## terrain categories.
static func moves_through_everything(move_data: Dictionary) -> bool:
	return str(move_data.get("mode", "")) == MODE

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	if _rules().is_unit_engaged(unit_id, board):
		return {"ok": false, "violations": ["a pulse jet move must end unengaged"]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, _context: Dictionary) -> Array:
	return OrkAbilities.pulse_jet_after_effects(unit_id)
