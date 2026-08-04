extends SceneTree

# 19.03 + 11e Fight "Select Targets": an Attached unit's components can be
# locked with DIFFERENT enemies, and each may only attack what IT is in
# Engagement Range of ("each target must be engaged with the model that has
# that weapon").
#
# Reported bug — the player's Custodian Guard (led by a Blade Champion) was
# still plainly in combat, they activated it, clicked "Best Weapons ✨" and
# confirmed, and the game answered "not within engagement range". Cause:
#   - FightPhase._get_eligible_melee_targets measures the actor as the WHOLE
#     Attached unit, so the dialog's target list held every enemy either
#     component had reached;
#   - AttackAssignmentDialog._apply_best_plan pointed EVERY section at the ONE
#     selected target;
#   - _rebuild_assignments files each section under its own component unit, and
#     FightPhase._validate_assign_attacks measures the ATTACKER as that
#     component alone — so the half that had not reached that enemy was
#     rejected, killing the whole batch.
# The engine gate is right (the rule is per model); the plan-builders were the
# ones that had to narrow. This pins the narrowing.
#
# Board (40px = 1", ER 2" at 11e):
#   U_BG     Custodian Guard, 2 models  @ (500,500) (545,500)
#   U_LEADER Blade Champion  attached   @ (500,800)
#   U_ORK_A  engaged with the BODYGUARD only @ (500,570)   0.49" from b0
#   U_ORK_B  engaged with the LEADER only    @ (500,870)   0.49" from L0
#
# Usage: godot --headless --path . -s tests/test_attached_fight_split_engagement_11e.gd

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
	create_timer(0.1).timeout.connect(_run)

func _model(id: String, x: float, y: float, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

func _board(gs) -> void:
	gs.state["units"] = {
		"U_BG": {"id": "U_BG", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Custodian Guard T", "keywords": ["INFANTRY", "CUSTODIAN"],
				"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3},
				"weapons": [{"name": "Guardian spear", "type": "Melee", "range": "Melee",
					"attacks": "4", "weapon_skill": "2", "strength": "7", "ap": "-2",
					"damage": "2", "keywords": [], "special_rules": ""}]},
			"models": [_model("b0", 500.0, 500.0, 3), _model("b1", 545.0, 500.0, 3)]},
		"U_LEADER": {"id": "U_LEADER", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Blade Champion T", "keywords": ["CHARACTER", "INFANTRY"],
				"leader_data": {"can_lead": ["CUSTODIAN"]},
				"stats": {"move": 6, "toughness": 6, "save": 2, "invuln": 4, "wounds": 6},
				"weapons": [{"name": "Vaultswords", "type": "Melee", "range": "Melee",
					"attacks": "6", "weapon_skill": "2", "strength": "6", "ap": "-2",
					"damage": "2", "keywords": [], "special_rules": ""},
					{"name": "Misericordia", "type": "Melee", "range": "Melee",
					"attacks": "1", "weapon_skill": "2", "strength": "5", "ap": "-2",
					"damage": "1", "keywords": ["Extra Attacks"], "special_rules": "Extra Attacks"}]},
			"models": [_model("L0", 500.0, 800.0, 6)]},
		"U_ORK_A": {"id": "U_ORK_A", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Stormboyz Alpha T", "keywords": ["INFANTRY"],
				"stats": {"move": 12, "toughness": 5, "save": 6, "wounds": 1},
				"weapons": [{"name": "Choppa", "type": "Melee", "range": "Melee",
					"attacks": "3", "weapon_skill": "3", "strength": "4", "ap": "-1",
					"damage": "1", "keywords": [], "special_rules": ""}]},
			"models": [_model("oa0", 500.0, 570.0)]},
		"U_ORK_B": {"id": "U_ORK_B", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Stormboyz Beta T", "keywords": ["INFANTRY"],
				"stats": {"move": 12, "toughness": 5, "save": 6, "wounds": 1},
				"weapons": [{"name": "Choppa", "type": "Melee", "range": "Melee",
					"attacks": "3", "weapon_skill": "3", "strength": "4", "ap": "-1",
					"damage": "1", "keywords": [], "special_rules": ""}]},
			"models": [_model("ob0", 500.0, 870.0)]},
	}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 10

func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attached_fight_split_engagement_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	if gs == null or pm == null or cam == null:
		_check("autoloads present", false)
		_finish()
		return
	_check("autoloads present", true)

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_board(gs)
	cam.attach_character("U_LEADER", "U_BG")
	_check("fixture: Blade Champion attached to the Custodian Guard",
		gs.state.units["U_LEADER"].get("attached_to") == "U_BG")

	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})

	print("\n-- the activation's target list spans both components (19.03) --")
	var targets = fp._get_eligible_melee_targets("U_BG")
	_check("both Ork mobs are targets of the ACTIVATION",
		targets.has("U_ORK_A") and targets.has("U_ORK_B"), str(targets.keys()))

	print("\n-- but each COMPONENT may only attack what it has reached --")
	var bg_reach = fp.melee_targets_for_component("U_BG", targets.keys())
	var ld_reach = fp.melee_targets_for_component("U_LEADER", targets.keys())
	_check("bodyguard reaches only Stormboyz Alpha", bg_reach == ["U_ORK_A"], str(bg_reach))
	_check("leader reaches only Stormboyz Beta", ld_reach == ["U_ORK_B"], str(ld_reach))
	_check("reachable_melee_target_for clamps an out-of-reach preference",
		fp.reachable_melee_target_for("U_BG", "U_ORK_B", targets.keys()) == "U_ORK_A",
		fp.reachable_melee_target_for("U_BG", "U_ORK_B", targets.keys()))
	_check("reachable_melee_target_for keeps a reachable preference",
		fp.reachable_melee_target_for("U_LEADER", "U_ORK_B", targets.keys()) == "U_ORK_B")

	print("\n-- the engine gate that produced the report (unchanged, now explained) --")
	fp.active_fighter_id = "U_BG"
	var bad = fp._validate_assign_attacks({
		"unit_id": "U_BG", "target_id": "U_ORK_B", "weapon_id": "guardian_spear_melee",
		"attacking_models": ["b0", "b1"]})
	_check("bodyguard → the leader's enemy is still rejected", not bad.valid, str(bad))
	var names_units := false
	for e in bad.get("errors", []):
		if "Custodian Guard T" in str(e) and "Stormboyz Beta T" in str(e):
			names_units = true
	_check("the rejection names BOTH units instead of 'Units are not within engagement range'",
		names_units, str(bad.get("errors")))

	print("\n-- THE BUG: the dialog's 'Best Weapons ✨' plan --")
	var dialog := AcceptDialog.new()
	dialog.set_script(load("res://dialogs/AttackAssignmentDialog.gd"))
	root.add_child(dialog)
	dialog.setup("U_BG", targets, fp)

	_check("dialog built one section per component", dialog._groups.size() == 2,
		str(dialog._groups.size()))
	_check("dialog knows each component's reach",
		dialog._component_targets.get("U_BG", []) == ["U_ORK_A"]
		and dialog._component_targets.get("U_LEADER", []) == ["U_ORK_B"],
		str(dialog._component_targets))
	_check("dialog warns that the sections are locked with different enemies",
		dialog._components_disagree_on_targets())

	# The dialog opens on the best plan, and "Best Weapons ✨" re-applies it.
	dialog._on_best_krump_pressed()
	var plan: Array = dialog.assignments
	print("plan: ", plan)
	_check("plan covers both components", plan.size() == 2, str(plan))

	var by_attacker := {}
	for a in plan:
		by_attacker[str(a.get("attacker", ""))] = str(a.get("target", ""))
	_check("bodyguard section swings at the enemy IT is engaged with",
		by_attacker.get("U_BG", "") == "U_ORK_A", str(by_attacker))
	_check("leader section swings at the enemy HE is engaged with",
		by_attacker.get("U_LEADER", "") == "U_ORK_B", str(by_attacker))

	print("\n-- every assignment the dialog submits now passes the engine gate --")
	var all_valid := true
	var first_error := ""
	for a in plan:
		var v = fp._validate_assign_attacks({
			"unit_id": str(a.get("attacker", "")),
			"target_id": str(a.get("target", "")),
			"weapon_id": str(a.get("weapon", "")),
			"attacking_models": a.get("models", [])})
		if not v.valid:
			all_valid = false
			if first_error == "":
				first_error = "%s → %s: %s" % [a.get("attacker"), a.get("target"), str(v.get("errors"))]
	_check("REGRESSION: 'Best Weapons ✨' + Fight! is accepted end to end",
		all_valid, first_error)

	print("\n-- [EXTRA ATTACKS] follow their OWN component, not the shared picker --")
	# The EA target selector is activation-level, but the attacks come from one
	# component's models and are gated per component like any other. Confirming
	# used to file the Champion's Misericordia at the shared pick, which the
	# engine then rejected (and, mid-batch, silently resolved).
	dialog._on_confirmed()
	var ea: Array = []
	for a in dialog.assignments:
		if str(a.get("weapon", "")) == "misericordia_melee":
			ea.append("%s->%s" % [a.get("attacker", ""), a.get("target", "")])
	_check("the leader's Extra Attacks weapon swings at HIS enemy",
		ea == ["U_LEADER->U_ORK_B"], str(dialog.assignments))
	# _on_confirmed hides + queue_frees the dialog; rebuild for the rest.
	dialog = AcceptDialog.new()
	dialog.set_script(load("res://dialogs/AttackAssignmentDialog.gd"))
	root.add_child(dialog)
	dialog.setup("U_BG", targets, fp)
	dialog._on_best_krump_pressed()

	print("\n-- 'All to Target' redirects the section that cannot reach --")
	dialog.target_list.select(dialog.target_list.item_count - 1)  # the LAST target
	dialog._on_all_to_target_pressed()
	var by_attacker2 := {}
	for a in dialog.assignments:
		by_attacker2[str(a.get("attacker", ""))] = str(a.get("target", ""))
	_check("All to Target keeps every section on a reachable enemy",
		by_attacker2.get("U_BG", "") == "U_ORK_A" and by_attacker2.get("U_LEADER", "") == "U_ORK_B",
		str(by_attacker2))

	print("\n-- per-section target cycling stays inside that section's reach --")
	_check("bodyguard's target cycle button is disabled (one reachable enemy)",
		bool(dialog._groups[0].target_button.disabled))
	dialog._on_group_target_cycle(0)
	_check("cycling cannot move the bodyguard off its only reachable enemy",
		str(dialog._groups[0].lines[0].get("target", "")) == "U_ORK_A",
		str(dialog._groups[0].lines))

	dialog.queue_free()

	print("\n-- engine auto-assign for an attached component clamps too --")
	# The AI submits ONE whole-unit assignment naming the bodyguard; the phase
	# then makes the attached component fight alongside it. That component must
	# not inherit a target it never reached.
	fp.confirmed_attacks = [{"attacker": "U_BG", "weapon": "guardian_spear_melee",
		"target": "U_ORK_A", "models": []}]
	fp._auto_assign_unassigned_models()
	var leader_targets: Array = []
	for a in fp.confirmed_attacks:
		if str(a.get("attacker", "")) == "U_LEADER":
			leader_targets.append(str(a.get("target", "")))
	_check("attached leader auto-assigned onto HIS enemy, not the bodyguard's",
		not leader_targets.is_empty() and not ("U_ORK_A" in leader_targets),
		str(fp.confirmed_attacks))
	fp.confirmed_attacks = []
	fp.active_fighter_id = ""

	GameConstants.edition = prev_edition
	gs.state = prev_state
	_finish()

func _finish():
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
