extends SceneTree

# Regression test for the Vertus Praetor attachment bug.
#
# When an attached unit (bodyguard + CHARACTER leader) charges, the attached
# character must move WITH the bodyguard. Previously ChargePhase only moved the
# bodyguard's own models, leaving the character behind — which split the
# attached unit apart and made it look like the attachment had broken.
#
# In the Fight phase this game activates an attached unit as two separate
# fighters (the character keeps its own weapons), so once the charge has carried
# the character into combat it piles in / consolidates on its own — the
# bodyguard's pile-in must NOT also drag it (that would move it twice).
#
# Usage: godot --headless --path . -s tests/test_charge_attached_character.gd

var passed := 0
var failed := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

func _make_units(gs) -> void:
	# Bodyguard (Vertus Praetors stand-in): owner 1, 1 model at (500,500)
	gs.state.units["U_BG"] = {
		"id": "U_BG", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {}, "attached_to": null,
		"attachment_data": {"attached_characters": ["U_CHAR"]},
		"meta": {"name": "Vertus Praetors", "keywords": ["MOUNTED", "IMPERIUM"],
			"stats": {"move": 12}},
		"models": [{"id": "m1", "alive": true, "wounds": 3, "current_wounds": 3,
			"base_mm": 40, "base_type": "circular", "position": {"x": 500, "y": 500}}]
	}
	# Character (Shield-Captain stand-in): owner 1, attached to U_BG, 1 model at (460,500)
	gs.state.units["U_CHAR"] = {
		"id": "U_CHAR", "owner": 1, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {}, "attached_to": "U_BG",
		"meta": {"name": "Shield-Captain", "keywords": ["CHARACTER", "MOUNTED", "IMPERIUM"],
			"stats": {"move": 12}},
		"models": [{"id": "m1", "alive": true, "wounds": 5, "current_wounds": 5,
			"base_mm": 40, "base_type": "circular", "position": {"x": 460, "y": 500}}]
	}
	# Target (enemy Painboy stand-in): owner 2, 1 model at (700,500)
	gs.state.units["U_TGT"] = {
		"id": "U_TGT", "owner": 2, "status": GameStateData.UnitStatus.DEPLOYED,
		"flags": {},
		"meta": {"name": "Painboy", "keywords": ["INFANTRY", "ORKS"],
			"stats": {"move": 5}},
		"models": [{"id": "m1", "alive": true, "wounds": 4, "current_wounds": 4,
			"base_mm": 32, "base_type": "circular", "position": {"x": 700, "y": 500}}]
	}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_charge_attached_character ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	_check("GameState present", gs != null)
	_check("PhaseManager present", pm != null)
	if gs == null or pm == null:
		quit(1)
		return

	GameConstants.edition = 11
	gs.set_active_player(1)
	# Clear default board terrain so charge endpoints don't trip the wall check.
	var tm = root.get_node_or_null("TerrainManager")
	if tm:
		tm.terrain_features = []
	_make_units(gs)

	# --- CHARGE ---
	print("-- charge move rides the attached character along --")
	var cphase = load("res://phases/ChargePhase.gd").new()
	cphase.phase_type = GameStateData.Phase.CHARGE
	root.add_child(cphase)
	cphase.pending_charges["U_BG"] = {"targets": ["U_TGT"], "distance": 8, "dice_rolls": [4, 4]}

	# The attached character is NOT independently selectable to charge.
	_check("attached character cannot charge on its own",
		not cphase._can_unit_charge(gs.state.units["U_CHAR"]))
	_check("bodyguard is still eligible to charge",
		cphase._can_unit_charge(gs.state.units["U_BG"]))

	var char_before = gs.state.units["U_CHAR"].models[0].position.duplicate()
	# Endpoint x=643 reaches base-to-base contact with the target at x=700
	# (charge rules require B2B when achievable). Delta from start = +143px.
	var action = {
		"actor_unit_id": "U_BG",
		"payload": {"per_model_paths": {"m1": [[500, 500], [643, 500]]}}
	}
	var result = cphase._process_apply_charge_move(action)
	_check("charge move succeeded", result.get("success", false), str(result))

	var changes = result.get("changes", [])
	var char_change_found = false
	for ch in changes:
		if str(ch.get("path", "")).begins_with("units.U_CHAR.models"):
			char_change_found = true
	_check("charge changes include a position for the attached character",
		char_change_found, "changes=%s" % str(changes))

	pm.apply_state_changes(changes)
	var bg_after = gs.state.units["U_BG"].models[0].position
	var char_after = gs.state.units["U_CHAR"].models[0].position
	var bg_ax = bg_after.x if bg_after is Vector2 else bg_after.get("x", 0)
	var char_ax = char_after.x if char_after is Vector2 else char_after.get("x", 0)
	var char_bx = char_before.x if char_before is Vector2 else char_before.get("x", 0)
	_check("bodyguard moved to charge endpoint (x=643)", abs(bg_ax - 643) < 1.0, str(bg_after))
	_check("attached character moved with the bodyguard (delta +143px)",
		abs(char_ax - (char_bx + 143)) < 1.0,
		"before_x=%s after_x=%s" % [str(char_bx), str(char_ax)])
	_check("attached character marked charged_this_turn",
		gs.state.units["U_CHAR"].get("flags", {}).get("charged_this_turn", false) == true)
	cphase.free()

	# --- PILE IN (Fight phase) ---
	# This game fights an attached unit as TWO separate activations (the
	# character keeps its own weapons — RulesEngine.get_unit_melee_weapons is
	# per-unit). So once the charge has carried the character into combat, the
	# character piles in / consolidates as its OWN fighter — the bodyguard's
	# pile-in must NOT also drag it, or it would move twice. Mirrors how a unit
	# that reaches combat via the Movement phase already behaves.
	print("\n-- attached character piles in as its own fighter (no double-move) --")
	_make_units(gs)
	# Post-charge: bodyguard (P1) + attached character both charged into combat
	# with the P2 target (charged_this_turn makes them pile-in eligible per
	# PileInMove.eligible, exactly as the charge fix leaves them).
	gs.state.units["U_BG"].models[0].position = {"x": 630, "y": 500}
	gs.state.units["U_BG"]["flags"] = {"charged_this_turn": true}
	gs.state.units["U_CHAR"].models[0].position = {"x": 590, "y": 500}
	gs.state.units["U_CHAR"]["flags"] = {"charged_this_turn": true}
	gs.state.units["U_TGT"].models[0].position = {"x": 700, "y": 500}
	var fphase = load("res://phases/FightPhase.gd").new()
	fphase.phase_type = GameStateData.Phase.FIGHT
	root.add_child(fphase)

	# The attached character is offered its own pile-in (it is in combat).
	var pin_eligible = fphase._pile_in_eligible_units_11e(1)
	_check("attached character is offered its own pile-in", "U_CHAR" in pin_eligible,
		"eligible=%s" % str(pin_eligible))
	_check("bodyguard is offered its own pile-in", "U_BG" in pin_eligible)

	# The bodyguard piling in must NOT move the attached character (no ride-along).
	var pin_char_before_x = gs.state.units["U_CHAR"].models[0].position.x
	var pin_result = fphase._process_pile_in({
		"unit_id": "U_BG", "movements": {"0": Vector2(650, 500)}})
	_check("pile-in succeeded", pin_result.get("success", false), str(pin_result))
	pm.apply_state_changes(pin_result.get("changes", []))
	var pin_char_after_x = gs.state.units["U_CHAR"].models[0].position.x
	_check("bodyguard pile-in does NOT drag the attached character (no double-move)",
		abs(pin_char_after_x - pin_char_before_x) < 0.001,
		"before_x=%s after_x=%s" % [str(pin_char_before_x), str(pin_char_after_x)])
	fphase.free()

	for uid in ["U_BG", "U_CHAR", "U_TGT"]:
		gs.state.units.erase(uid)
	GameConstants.edition = 11
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
