extends SceneTree

# Attached-character shooting gate (19.02): while a CHARACTER unit is attached
# to a bodyguard, the combined Attached unit is ONE unit — the character can
# never be selected as a separate ranged-attack target.
#
# Regression for the "AI shoots the Blade Champion directly" bug: the AI's
# focus-fire plan enumerated attached leaders as targets (they even score a
# leader-buff bonus) and RulesEngine.validate_shoot did not reject the SHOOT,
# so the defender's allocation dialog opened for the character alone and the
# player could not put the wounds on the bodyguard squad first.
#
#  - validate_shoot must REJECT a SHOOT assignment targeting an attached
#    character, must still ACCEPT the bodyguard, and must still ACCEPT a
#    standalone (unattached) character
#  - AIDecisionMaker._get_shootable_enemy_units must exclude attached
#    characters (while _get_enemy_units keeps them for movement/charge)
#  - get_grenade_eligible_targets must exclude attached characters
#
# Usage: godot --headless --path . -s tests/test_attached_char_shoot_gate_11e.gd

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
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _model(id: String, x: float, y: float, wounds: int = 4) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 40, "base_type": "circular", "position": {"x": x, "y": y}}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attached_char_shoot_gate_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	_check("autoloads present", gs != null and rules != null and cam != null)

	GameConstants.edition = 11

	# Clear any default terrain layout so the synthetic sightlines below are
	# open — this test exercises the targeting gate, not LoS.
	var tm = root.get_node_or_null("TerrainManager")
	if tm != null:
		tm.terrain_features = []
	if gs.state.has("board"):
		gs.state.board["terrain_features"] = []

	# Ork shooter, 20" below the custodes line, clear board (no terrain in
	# synthetic state, so LoS is open).
	gs.state.units["U_SHOOTER_SG"] = {"id": "U_SHOOTER_SG", "owner": 2, "status": 2, "flags": {},
		"meta": {"name": "Shoota Grots", "keywords": ["INFANTRY"],
			"stats": {"toughness": 4, "save": 5, "wounds": 1, "move": 6},
			"weapons": [{"name": "Test shoota", "type": "Ranged", "range": "36",
				"attacks": "2", "ballistic_skill": "4", "strength": "4", "ap": "0",
				"damage": "1", "keywords": [], "special_rules": ""}]},
		"models": [_model("sg0", 800.0, 1100.0, 1)]}

	# Bodyguard squad + its attached character, plus a standalone character.
	gs.state.units["U_BG_SG"] = {"id": "U_BG_SG", "owner": 1, "status": 2, "flags": {},
		"meta": {"name": "Guard Squad", "keywords": ["INFANTRY", "CUSTODIAN GUARD"],
			"stats": {"toughness": 6, "save": 2, "wounds": 4, "move": 6}},
		"models": [_model("b0", 800.0, 300.0), _model("b1", 840.0, 300.0)]}
	gs.state.units["U_CHAR_SG"] = {"id": "U_CHAR_SG", "owner": 1, "status": 2, "flags": {}, "attached_to": null,
		"meta": {"name": "Blade Champion T", "keywords": ["CHARACTER", "INFANTRY"],
			"leader_data": {"can_lead": ["CUSTODIAN GUARD"]},
			"stats": {"toughness": 6, "save": 2, "wounds": 6, "move": 6}},
		"models": [_model("c0", 880.0, 300.0, 6)]}
	gs.state.units["U_LONER_SG"] = {"id": "U_LONER_SG", "owner": 1, "status": 2, "flags": {}, "attached_to": null,
		"meta": {"name": "Standalone Champion T", "keywords": ["CHARACTER", "INFANTRY"],
			"stats": {"toughness": 6, "save": 2, "wounds": 6, "move": 6}},
		"models": [_model("l0", 700.0, 300.0, 6)]}

	cam.attach_character("U_CHAR_SG", "U_BG_SG")
	_check("fixture: character attached to bodyguard",
		gs.state.units["U_CHAR_SG"].get("attached_to") == "U_BG_SG",
		str(gs.state.units["U_CHAR_SG"].get("attached_to")))

	var board = gs.create_snapshot()

	print("-- validate_shoot gate (19.02) --")
	var shoot_at_char = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER_SG", "payload": {"assignments": [
		{"weapon_id": "test_shoota_ranged", "target_unit_id": "U_CHAR_SG", "model_ids": ["sg0"]}]}}
	var v1 = rules.validate_shoot(shoot_at_char, board)
	_check("SHOOT at attached character is rejected", not v1.valid, str(v1))
	var mentions_attached = false
	for e in v1.get("errors", []):
		if "attached character" in str(e):
			mentions_attached = true
	_check("rejection names the attached-character rule", mentions_attached, str(v1.get("errors")))

	var shoot_at_bg = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER_SG", "payload": {"assignments": [
		{"weapon_id": "test_shoota_ranged", "target_unit_id": "U_BG_SG", "model_ids": ["sg0"]}]}}
	var v2 = rules.validate_shoot(shoot_at_bg, board)
	_check("SHOOT at the bodyguard unit is still valid", v2.valid, str(v2))

	var shoot_at_loner = {"type": "SHOOT", "actor_unit_id": "U_SHOOTER_SG", "payload": {"assignments": [
		{"weapon_id": "test_shoota_ranged", "target_unit_id": "U_LONER_SG", "model_ids": ["sg0"]}]}}
	var v3 = rules.validate_shoot(shoot_at_loner, board)
	_check("SHOOT at an unattached character is still valid", v3.valid, str(v3))

	print("-- eligibility mirrors the gate --")
	var elig = rules.get_eligible_targets("U_SHOOTER_SG", board)
	_check("get_eligible_targets omits the attached character",
		not elig.has("U_CHAR_SG") and elig.has("U_BG_SG") and elig.has("U_LONER_SG"),
		str(elig.keys()))

	print("-- AI shooting enumeration --")
	var aidm = load("res://scripts/AIDecisionMaker.gd")
	var all_enemies = aidm._get_enemy_units(board, 2)
	var shootable = aidm._get_shootable_enemy_units(board, 2)
	_check("_get_enemy_units still sees the attached character (movement/charge)",
		all_enemies.has("U_CHAR_SG"), str(all_enemies.keys()))
	_check("_get_shootable_enemy_units excludes the attached character",
		not shootable.has("U_CHAR_SG") and shootable.has("U_BG_SG") and shootable.has("U_LONER_SG"),
		str(shootable.keys()))
	var plan = aidm._build_focus_fire_plan(board, ["U_SHOOTER_SG"], 2)
	var plan_hits_char = false
	for uid in plan:
		for a in plan[uid]:
			if a.get("target_unit_id", "") == "U_CHAR_SG":
				plan_hits_char = true
	_check("focus-fire plan never assigns a weapon to the attached character",
		not plan_hits_char, str(plan))

	print("-- GRENADE eligibility --")
	# Move the shooter to within 8" of the custodes line for the grenade check.
	gs.state.units["U_SHOOTER_SG"].models[0].position = {"x": 820.0, "y": 500.0}
	var gboard = gs.create_snapshot()
	var gtargets = rules.get_grenade_eligible_targets("U_SHOOTER_SG", gboard)
	var gids = []
	var grenade_hits_char = false
	for t in gtargets:
		gids.append(t.get("unit_id", ""))
		if t.get("unit_id", "") == "U_CHAR_SG":
			grenade_hits_char = true
	_check("grenade eligible targets exclude the attached character",
		not grenade_hits_char and "U_BG_SG" in gids, str(gids))

	# Cleanup synthetic units
	for uid in ["U_SHOOTER_SG", "U_BG_SG", "U_CHAR_SG", "U_LONER_SG"]:
		gs.state.units.erase(uid)

	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
