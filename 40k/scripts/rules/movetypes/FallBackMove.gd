class_name FallBackMove
extends MoveType

# Codex: Orks (11e) WHERE D'YA FINK YOU'RE GOING? consumers (select_mode / before_moving).
# Loaded at call time, not preloaded: OrkCodexMovement depends on autoloads,
# and MoveTypes is compiled before the autoloads exist in `--script` runs.
static func _ork_codex_movement():
	return load("res://scripts/stratagems/ork_codex/OrkCodexMovement.gd")

# Codex: Adeptus Custodes (11e) CORNER THE QUARRY consumers (WP-C7), loaded the same way.
static func _cus11e_abilities():
	return load("res://scripts/codex/custodes/CustodesAbilities.gd")
# WP-S4: Codex: Space Marines (11e) Space Wolves SAVAGE FRENZY — same load-at-call-time rule.
static func _sw11e_abilities():
	return load("res://scripts/codex/space_wolves/SWAbilities11e.gd")
# Codex: Orks (11e) Wimp-kickaz (WP-O5) — same load-at-call-time rule.
static func _ork11e_enh():
	return load("res://scripts/codex/orks/OrkEnhancements11e.gd")

## 09.07 FALL-BACK MOVE — eligible if ENGAGED; max distance M; must end
## unengaged; afterwards not eligible to shoot/charge (and 11e: start an
## action) until end of turn.
##
## 11e adds MODES (assessed in order):
##   ▪ ordered_retreat   — selectable if the unit is NOT battle-shocked
##                         (not mandatory: desperate escape may be chosen)
##   ▪ desperate_escape  — otherwise mandatory. BEFORE: one hazard roll per
##                         model (06.03). WHILE: models may move through
##                         enemies. AFTER: if not battle-shocked, make a
##                         battle-shock roll.
## 10e has no modes here (its desperate-escape tests are per-model when
## crossing enemies, handled in the legacy movement path).

func _init():
	id = "fall_back"
	display_name = "Fall Back"

func eligible(unit_id: String, board: Dictionary) -> Dictionary:
	var unit = _unit(board, unit_id)
	if unit.is_empty() or not _on_battlefield(unit):
		return {"eligible": false, "reasons": ["unit not on the battlefield"]}
	if not _rules().is_unit_engaged(unit_id, board):
		return {"eligible": false, "reasons": ["unit is not engaged"]}
	return {"eligible": true, "reasons": []}

func max_distance_inches(unit: Dictionary, _context: Dictionary) -> float:
	return float(unit.get("meta", {}).get("stats", {}).get("move", 0))

func mode_ids() -> Array:
	return ["ordered_retreat", "desperate_escape"] if GameConstants.edition >= 11 else []

func select_mode(unit_id: String, board: Dictionary, _context: Dictionary = {}) -> Dictionary:
	if GameConstants.edition < 11:
		return {"mode": "", "mandatory": false, "available": []}
	var unit = _unit(board, unit_id)
	var shocked: bool = unit.get("flags", {}).get("battle_shocked", false)
	# CUT' EM DOWN (Bully Boyz): the marked enemy unit must take Desperate
	# Escape tests for all models when it Falls Back.
	# Codex: Orks (11e) WHERE D'YA FINK YOU'RE GOING?: an enemy unit engaged
	# with the stratagem's BEAST SNAGGA unit must use the desperate escape mode.
	# Codex: Orks (11e) Wimp-kickaz (WP-O5): an enemy unit engaged with the
	# NOBZ unit must select the desperate escape mode.
	if shocked or unit.get("flags", {}).get("effect_cut_em_down", false) \
			or _ork_codex_movement().where_dya_fink_forces_desperate_escape(unit_id, board) \
			or _ork11e_enh().forces_desperate_escape(unit_id, board) \
			or _cus11e_abilities().corner_the_quarry_source(unit_id, board) != "" \
			or _sw11e_abilities().savage_frenzy_source(unit_id, board) != "":  # Codex: Adeptus Custodes CORNER THE QUARRY; WP-S4 Space Wolves SAVAGE FRENZY
		# 09.07: "Otherwise, you must select this mode."
		return {"mode": "desperate_escape", "mandatory": true, "available": ["desperate_escape"]}
	# Ordered retreat is selectable but NOT mandatory (sidebar): the player
	# may pick desperate escape instead. Default to ordered retreat.
	return {"mode": "ordered_retreat", "mandatory": false, "available": ["ordered_retreat", "desperate_escape"]}

func before_moving(unit_id: String, board: Dictionary, rng, context: Dictionary) -> Dictionary:
	if GameConstants.edition < 11 or context.get("mode", "") != "desperate_escape":
		return {}
	# Desperate Escape BEFORE MOVING: a hazard roll for each model (06.03).
	var unit = _unit(board, unit_id)
	var alive := 0
	for m in unit.get("models", []):
		if m.get("alive", true):
			alive += 1
	# CUT' EM DOWN (Bully Boyz): -1 to each test while a Waaagh! was active
	# for the Nobz/Meganobz unit when the stratagem was used.
	var cut_mod: int = -1 if unit.get("flags", {}).get("effect_cut_em_down_minus1", false) else 0
	# Codex: Adeptus Custodes CORNER THE QUARRY: -1 to those hazard rolls while battle-shocked.
	cut_mod += _cus11e_abilities().corner_the_quarry_hazard_modifier(unit_id, board)
	cut_mod += _sw11e_abilities().savage_frenzy_hazard_modifier(unit_id, board)  # WP-S4 Savage Frenzy: -1 if battle-shocked
	# Codex: Orks (11e) Wimp-kickaz (WP-O5): -1 to these hazard rolls while the
	# NOBZ unit is riled up.
	var wk_mod: int = int(_ork11e_enh().desperate_escape_hazard_modifier(unit_id, board))
	if wk_mod != 0:
		print("FallBackMove: Wimp-kickaz — %d to %s's desperate escape hazard rolls (the Nobz are riled up)" % [wk_mod, unit_id])
	cut_mod += wk_mod
	var hz = AttackSequence.hazard_rolls(unit, alive, rng, cut_mod)
	# Codex: Orks (11e) WHERE D'YA FINK YOU'RE GOING?: a MONSTER/VEHICLE unit
	# makes three ADDITIONAL hazard rolls per BEAST SNAGGA unit it is engaged
	# with, -1 to those rolls while it is battle-shocked. All rolls are made
	# simultaneously (06.03); the extra ones are reported separately.
	var wdyf: Dictionary = _ork_codex_movement().where_dya_fink_extra_hazard(unit_id, board)
	if int(wdyf.get("count", 0)) > 0:
		var extra = AttackSequence.hazard_rolls(unit, int(wdyf.count), rng, int(wdyf.modifier) + cut_mod)
		hz["extra_rolls"] = extra.rolls
		hz["extra_failures"] = extra.failures
		hz["extra_modifier"] = int(wdyf.modifier)
		hz.rolls = hz.rolls + extra.rolls
		hz.failures = int(hz.failures) + int(extra.failures)
		hz.mortal_wounds = int(hz.mortal_wounds) + int(extra.mortal_wounds)
	return {
		"hazard": hz,
		"mortal_wounds": hz.mortal_wounds,
		"can_move_through_enemies": true,  # WHILE MOVING (desperate escape)
		"dice": [{"context": "desperate_escape_hazard", "rolls": hz.rolls}],
	}

func after_moving_conditions(unit_id: String, board: Dictionary, context: Dictionary) -> Dictionary:
	var base = super.after_moving_conditions(unit_id, board, context)
	if not base.ok:
		return base
	if _rules().is_unit_engaged(unit_id, board):
		return {"ok": false, "violations": ["unit must end a fall-back move unengaged"]}
	return {"ok": true, "violations": []}

func after_moving_effects(unit_id: String, context: Dictionary) -> Array:
	var effects = [
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "moved"), "value": true},
		{"op": "set", "path": StateSchema.path_unit_flag(unit_id, "fell_back"), "value": true},
	]
	if GameConstants.edition >= 11:
		effects.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "cannot_start_action"), "value": true})
		if context.get("mode", "") == "desperate_escape":
			# 09.07 AFTER MOVING (desperate escape): if not battle-shocked,
			# a battle-shock roll must be made — surfaced as a required
			# follow-up for the phase to resolve via leadership_roll.
			effects.append({"op": "set", "path": StateSchema.path_unit_flag(unit_id, "pending_battleshock_roll"), "value": true})
	return effects
