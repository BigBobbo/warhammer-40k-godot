extends SceneTree

# ISS-059: 11e attached units (19.01-19.04, 24.22, 24.34).
#  - one LEADER and one SUPPORT slot per bodyguard (19.01); a second
#    unit of the same role is refused; 10e single-slot unchanged
#  - keyword union (19.03): the attached unit has ALL component units'
#    keywords — the pg-67 example reproduces: [ANTI-PSYKER 4+] crits on
#    4+ against a non-PSYKER bodyguard led by a PSYKER leader
#
# Usage: godot --headless --path . -s tests/test_iss059_attached_units_11e.gd

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

func _char(id: String, abilities: Array, keywords: Array) -> Dictionary:
	return {"id": id, "owner": 1, "flags": {}, "attached_to": null,
		"meta": {"name": id, "keywords": keywords,
			"abilities": abilities,
			"leader_data": {"can_lead": ["RETRIBUTOR"]},
			"stats": {"toughness": 3, "wounds": 4}},
		"models": [{"id": "m0", "alive": true, "wounds": 4, "current_wounds": 4,
			"base_mm": 32, "base_type": "circular", "position": {"x": 500, "y": 500}}]}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss059_attached_units_11e ===\n")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	var gs = root.get_node_or_null("GameState")
	var rules = root.get_node_or_null("RulesEngine")
	_check("autoloads present", cam != null and gs != null and rules != null)

	gs.state.units["U_BG59"] = {"id": "U_BG59", "owner": 1, "flags": {},
		"meta": {"name": "Retributors", "keywords": ["INFANTRY", "RETRIBUTOR"],
			"stats": {"toughness": 3, "save": 3, "wounds": 1}},
		"models": [{"id": "b0", "alive": true, "wounds": 1, "current_wounds": 1,
			"base_mm": 32, "base_type": "circular", "position": {"x": 480, "y": 500}}]}
	gs.state.units["U_LEADER59"] = _char("U_LEADER59", ["Leader"], ["CHARACTER", "INFANTRY", "PSYKER"])
	gs.state.units["U_LEADER59B"] = _char("U_LEADER59B", ["Leader"], ["CHARACTER", "INFANTRY"])
	gs.state.units["U_SUPPORT59"] = _char("U_SUPPORT59", ["Support"], ["CHARACTER", "INFANTRY"])

	print("-- roles + slots (19.01 / 24.22 / 24.34) --")
	_check("Support datasheet ability -> support role; otherwise leader",
		cam.attachment_role(gs.state.units["U_SUPPORT59"]) == "support"
		and cam.attachment_role(gs.state.units["U_LEADER59"]) == "leader")
	GameConstants.edition = 10
	cam.attach_character("U_LEADER59", "U_BG59")
	_check("leader attached", gs.state.units["U_BG59"].attachment_data.attached_characters == ["U_LEADER59"])
	var v = cam.can_attach("U_SUPPORT59", "U_BG59")
	_check("10e: any second attachment refused", not v.valid, str(v))
	GameConstants.edition = 11
	v = cam.can_attach("U_SUPPORT59", "U_BG59")
	_check("11e: a SUPPORT unit may join a bodyguard that already has a leader",
		v.valid, str(v))
	v = cam.can_attach("U_LEADER59B", "U_BG59")
	_check("11e: a second LEADER is refused (one per role, 19.01)",
		not v.valid and "19.01" in str(v.reason), str(v))
	cam.attach_character("U_SUPPORT59", "U_BG59")
	_check("attached unit holds both characters",
		gs.state.units["U_BG59"].attachment_data.attached_characters.size() == 2)

	print("\n-- keyword union (19.03) + the pg-67 ANTI-PSYKER example --")
	var union = cam.attached_unit_keywords("U_BG59")
	_check("attached unit gains the leader's PSYKER keyword",
		"PSYKER" in union and "RETRIBUTOR" in union, str(union))
	_check("character queried directly also carries the bodyguard's keywords",
		"RETRIBUTOR" in cam.attached_unit_keywords("U_LEADER59"))
	var anti_board = {"units": {"U_X": {"id": "U_X", "owner": 1, "flags": {},
		"meta": {"stats": {}, "weapons": [{"name": "Witch Rifle", "type": "Ranged",
			"range": "24", "attacks": "2", "ballistic_skill": "3", "strength": "4",
			"ap": "0", "damage": "1", "special_rules": "anti-psyker 4+"}]},
		"models": []}}, "meta": {}}
	var threshold = rules.get_critical_wound_threshold("Witch Rifle", gs.state.units["U_BG59"], anti_board)
	_check("pg-67: [ANTI-PSYKER 4+] crits on 4+ vs the non-PSYKER bodyguard (leader's keyword counts)",
		threshold == 4, "threshold=%d" % threshold)
	GameConstants.edition = 10
	threshold = rules.get_critical_wound_threshold("Witch Rifle", gs.state.units["U_BG59"], anti_board)
	_check("edition 10: no keyword union (threshold stays 6)", threshold == 6)
	GameConstants.edition = 11
	# After the leader dies and detaches, the union loses PSYKER.
	gs.state.units["U_LEADER59"].models[0]["alive"] = false
	cam.detach_character("U_LEADER59")
	union = cam.attached_unit_keywords("U_BG59")
	_check("leader destroyed + detached: the union loses PSYKER (19.04 expiry)",
		not "PSYKER" in union, str(union))
	threshold = rules.get_critical_wound_threshold("Witch Rifle", gs.state.units["U_BG59"], anti_board)
	_check("ANTI-PSYKER reverts to 6+ once the leader is gone", threshold == 6)

	print("\n-- B6: per-role slots in the deploy diff/network pipeline --")
	# DeploymentPhase._validate_attach_character_deployment is the gate for
	# ATTACH_CHARACTER_DEPLOYMENT actions arriving without UI (composite
	# deploys, multiplayer). The raw count cap (max 2 at e11) must not let
	# two LEADERS through; roles mirror CharacterAttachmentManager.
	gs.state.units["U_LEADER59"].models[0]["alive"] = true
	gs.state.units["U_LEADER59"]["attached_to"] = null
	gs.state.units["U_BG59"]["attachment_data"] = {"attached_characters": []}
	for uid in ["U_LEADER59", "U_LEADER59B", "U_SUPPORT59"]:
		gs.state.units[uid]["status"] = GameStateData.UnitStatus.UNDEPLOYED
	var dp = load("res://phases/DeploymentPhase.gd").new()
	dp.game_state_snapshot = gs.state
	GameConstants.edition = 11
	var dv = dp._validate_attach_character_deployment({
		"bodyguard_id": "U_BG59", "character_ids": ["U_LEADER59", "U_SUPPORT59"]})
	_check("deploy pipeline: leader + support batch accepted at e11", dv.valid, str(dv))
	dv = dp._validate_attach_character_deployment({
		"bodyguard_id": "U_BG59", "character_ids": ["U_LEADER59", "U_LEADER59B"]})
	_check("deploy pipeline: two LEADERS in one batch refused (24.22)",
		not dv.valid and "24.22" in str(dv.errors), str(dv))
	gs.state.units["U_BG59"]["attachment_data"] = {"attached_characters": ["U_LEADER59"]}
	dv = dp._validate_attach_character_deployment({
		"bodyguard_id": "U_BG59", "character_ids": ["U_LEADER59B"]})
	_check("deploy pipeline: second LEADER refused when one is already attached",
		not dv.valid and "24.22" in str(dv.errors), str(dv))
	dv = dp._validate_attach_character_deployment({
		"bodyguard_id": "U_BG59", "character_ids": ["U_SUPPORT59"]})
	_check("deploy pipeline: SUPPORT joins a leader-attached bodyguard", dv.valid, str(dv))
	GameConstants.edition = 10
	gs.state.units["U_BG59"]["attachment_data"] = {"attached_characters": []}
	dv = dp._validate_attach_character_deployment({
		"bodyguard_id": "U_BG59", "character_ids": ["U_LEADER59", "U_SUPPORT59"]})
	_check("deploy pipeline: 10e keeps the single-slot cap",
		not dv.valid and "cap" in str(dv.errors), str(dv))
	dp.free()

	for uid in ["U_BG59", "U_LEADER59", "U_LEADER59B", "U_SUPPORT59"]:
		gs.state.units.erase(uid)
	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
