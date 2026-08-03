extends SceneTree

# Attached-character MELEE gate (19.02/19.03). While a CHARACTER unit is
# attached to a bodyguard, the two are ONE Attached unit — the leader is never
# selectable as a melee target in his own right. Attacks are made against the
# Attached unit and the allocation rules (05.03 grouping, 05.04 CHARACTER
# groups last) are what eventually reach him.
#
# Regression for the reported Krumpin' tutorial bug: the Custodian Guard's
# swing-back picked the Warboss — who was attached to the Boyz — as its melee
# target. Nothing stopped it: the fight-phase target list, the engine's
# fight_targets_in_engagement, FightPhase._validate_assign_attacks and the AI's
# fight planner all treated the leader as a unit of his own (and
# _score_fight_target even hands CHARACTER units a +2 preference bonus). Since
# the wound-allocation fold is built FROM the target unit, targeting the
# leader produced a single "CHARACTER — 1 model" allocation group, so all 15
# Guardian spear wounds landed on the Boss and the 10 Boyz were untouched.
# The ranged path had this gate already (test_attached_char_shoot_gate_11e);
# this is the melee half.
#
#  - attached_unit_target_id / is_attached_character resolve BOTH link
#    directions, and stop redirecting once the bodyguard is wiped (19.05)
#  - fight_targets_in_engagement omits the attached character, keeps the
#    bodyguard, and still finds the bodyguard when only the LEADER's model is
#    within Engagement Range
#  - FightPhase._get_eligible_melee_targets mirrors that, and
#    _validate_assign_attacks rejects an attached-character target outright
#  - AIDecisionMaker._assign_fight_attacks retargets onto the bodyguard
#  - _build_attached_allocation_unit_11e folds bodyguard + leader whichever
#    component is passed in, and default_order puts the CHARACTER group last
#
# Usage: godot --headless --path . -s tests/test_attached_char_fight_gate_11e.gd

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

func _model(id: String, x: float, y: float, wounds: int = 1) -> Dictionary:
	return {"id": id, "alive": true, "wounds": wounds, "current_wounds": wounds,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

# 40px = 1". Attacker (P2) sits on a line at y=500; the bodyguard models are
# within Engagement Range of it, the leader's model trails 2" behind them.
func _board(gs) -> void:
	gs.state["units"] = {
		"U_ATK": {"id": "U_ATK", "owner": 2, "status": 2, "flags": {},
			"meta": {"name": "Custodian Guard T", "keywords": ["INFANTRY"],
				"stats": {"move": 6, "toughness": 6, "save": 2, "wounds": 3},
				"weapons": [{"name": "Guardian spear", "type": "Melee", "range": "Melee",
					"attacks": "4", "weapon_skill": "2", "strength": "7", "ap": "-2",
					"damage": "2", "keywords": [], "special_rules": ""}]},
			"models": [_model("a0", 500.0, 500.0, 3), _model("a1", 545.0, 500.0, 3)]},
		"U_BG": {"id": "U_BG", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Boyz T", "keywords": ["INFANTRY", "BOYZ"],
				"stats": {"move": 6, "toughness": 5, "save": 6, "wounds": 1},
				"weapons": [{"name": "Choppa", "type": "Melee", "range": "Melee",
					"attacks": "3", "weapon_skill": "3", "strength": "4", "ap": "-1",
					"damage": "1", "keywords": [], "special_rules": ""}]},
			"models": [_model("b0", 500.0, 545.0), _model("b1", 545.0, 545.0)]},
		"U_LEADER": {"id": "U_LEADER", "owner": 1, "status": 2, "flags": {},
			"attached_to": null, "attachment_data": {"attached_characters": []},
			"meta": {"name": "Warboss T", "keywords": ["CHARACTER", "INFANTRY", "WARBOSS"],
				"leader_data": {"can_lead": ["BOYZ"]},
				"stats": {"move": 6, "toughness": 6, "save": 4, "invuln": 5, "wounds": 6},
				"weapons": [{"name": "Power klaw", "type": "Melee", "range": "Melee",
					"attacks": "3", "weapon_skill": "2", "strength": "9", "ap": "-2",
					"damage": "2", "keywords": [], "special_rules": ""}]},
			"models": [_model("L0", 500.0, 625.0, 6)]},
	}
	gs.state["meta"]["active_player"] = 2
	gs.state["meta"]["phase"] = 10

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_attached_char_fight_gate_11e ===\n")
	var gs = root.get_node_or_null("GameState")
	var pm = root.get_node_or_null("PhaseManager")
	var rules = root.get_node_or_null("RulesEngine")
	var cam = root.get_node_or_null("CharacterAttachmentManager")
	if gs == null or pm == null or rules == null or cam == null:
		_check("autoloads present", false)
		_finish()
		return
	_check("autoloads present", true)

	var prev_state = gs.state.duplicate(true)
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11
	_board(gs)
	cam.attach_character("U_LEADER", "U_BG")
	_check("fixture: leader attached to bodyguard",
		gs.state.units["U_LEADER"].get("attached_to") == "U_BG"
		and "U_LEADER" in gs.state.units["U_BG"].get("attachment_data", {}).get("attached_characters", []),
		str(gs.state.units["U_LEADER"].get("attached_to")))

	var board = gs.create_snapshot()

	print("\n-- 19.02: which unit IS the Attached unit --")
	_check("attached_unit_target_id(leader) -> bodyguard",
		rules.attached_unit_target_id("U_LEADER", board) == "U_BG",
		rules.attached_unit_target_id("U_LEADER", board))
	_check("attached_unit_target_id(bodyguard) -> itself",
		rules.attached_unit_target_id("U_BG", board) == "U_BG")
	_check("attached_unit_target_id(unrelated) -> itself",
		rules.attached_unit_target_id("U_ATK", board) == "U_ATK")
	_check("is_attached_character: leader yes, bodyguard no",
		rules.is_attached_character("U_LEADER", board) and not rules.is_attached_character("U_BG", board))
	_check("attached_unit_models folds leader into the bodyguard's model list",
		rules.attached_unit_models("U_BG", board).size() == 3,
		str(rules.attached_unit_models("U_BG", board).size()))

	# Saves/fixtures exist that wrote only ONE side of the linkage — both must work.
	var fwd_only = board.duplicate(true)
	fwd_only.units["U_LEADER"]["attached_to"] = null
	_check("forward-list-only linkage still resolves",
		rules.attached_unit_target_id("U_LEADER", fwd_only) == "U_BG")
	var back_only = board.duplicate(true)
	back_only.units["U_BG"]["attachment_data"] = {"attached_characters": []}
	_check("back-pointer-only linkage still resolves",
		rules.attached_unit_target_id("U_LEADER", back_only) == "U_BG")

	# 19.05: once the Bodyguard unit is destroyed the Leader is his own unit
	# again — redirecting to a wiped unit would make him untargetable.
	var wiped = board.duplicate(true)
	for m in wiped.units["U_BG"].models:
		m["alive"] = false
	_check("a wiped bodyguard stops redirecting (leader targetable again)",
		rules.attached_unit_target_id("U_LEADER", wiped) == "U_LEADER"
		and not rules.is_attached_character("U_LEADER", wiped))
	_check("a wiped bodyguard stops folding in the leader's models",
		rules.attached_unit_models("U_BG", wiped).size() == 2,
		str(rules.attached_unit_models("U_BG", wiped).size()))
	var wiped_targets = rules.fight_targets_in_engagement("U_ATK", wiped)
	_check("a wiped bodyguard is not offered as a target via its leader",
		not wiped_targets.has("U_BG"), str(wiped_targets.keys()))

	print("\n-- engine melee target list --")
	var etargets = rules.fight_targets_in_engagement("U_ATK", board)
	_check("fight_targets_in_engagement omits the attached leader",
		not etargets.has("U_LEADER") and etargets.has("U_BG"), str(etargets.keys()))

	# The leader-only case: pull the bodyguard's own models out of Engagement
	# Range and leave only the leader's model touching the attacker. The
	# Attached unit is STILL engaged, so its bodyguard entry must remain.
	var leader_only = gs.state.duplicate(true)
	leader_only.units["U_BG"].models[0].position = {"x": 500.0, "y": 900.0}
	leader_only.units["U_BG"].models[1].position = {"x": 545.0, "y": 900.0}
	leader_only.units["U_LEADER"].models[0].position = {"x": 500.0, "y": 545.0}
	var lo_targets = rules.fight_targets_in_engagement("U_ATK", leader_only)
	_check("bodyguard still offered when only the LEADER's model is in ER",
		lo_targets.has("U_BG") and not lo_targets.has("U_LEADER"), str(lo_targets.keys()))

	print("\n-- FightPhase target list + ASSIGN_ATTACKS gate --")
	pm.transition_to_phase(10)  # FIGHT
	var fp = pm.get_current_phase_instance()
	fp.execute_action({"type": "END_PILE_IN", "player": 1})
	fp.execute_action({"type": "END_PILE_IN", "player": 2})
	var ptargets = fp._get_eligible_melee_targets("U_ATK")
	_check("_get_eligible_melee_targets omits the attached leader",
		not ptargets.has("U_LEADER") and ptargets.has("U_BG"), str(ptargets.keys()))

	fp.active_fighter_id = "U_ATK"
	var v_leader = fp._validate_assign_attacks({
		"unit_id": "U_ATK", "target_id": "U_LEADER", "weapon_id": "guardian_spear_melee"})
	_check("ASSIGN_ATTACKS at the attached leader is rejected", not v_leader.valid, str(v_leader))
	var names_rule = false
	for e in v_leader.get("errors", []):
		if "attached character" in str(e):
			names_rule = true
	_check("rejection names the attached-character rule", names_rule, str(v_leader.get("errors")))
	var v_bg = fp._validate_assign_attacks({
		"unit_id": "U_ATK", "target_id": "U_BG", "weapon_id": "guardian_spear_melee"})
	_check("ASSIGN_ATTACKS at the bodyguard is still valid", v_bg.valid, str(v_bg))
	fp.active_fighter_id = ""

	print("\n-- AI fight planner --")
	var aidm = load("res://scripts/AIDecisionMaker.gd")
	_check("_get_enemy_units still sees the leader (movement/charge scoring)",
		aidm._get_enemy_units(board, 2).has("U_LEADER"))
	var plan = aidm._assign_fight_attacks(board, "U_ATK", 2)
	_check("AI targets the bodyguard, not the attached leader",
		str(plan.get("target_id", "")) == "U_BG", str(plan))
	var lo_plan = aidm._assign_fight_attacks(leader_only, "U_ATK", 2)
	_check("AI still finds the Attached unit when only the leader is in ER",
		str(lo_plan.get("target_id", "")) == "U_BG", str(lo_plan))

	print("\n-- 19.03: the ATTACHED unit fights as ONE unit --")
	# The attacker side. Before this the Leader was a candidate of his own, so
	# he took a SECOND activation after his bodyguard's — and because 12.04
	# alternates, the enemy fought in between.
	var seq = fp.sequencer_11e
	_check("fight list offers the bodyguard, never the attached leader",
		"U_BG" in seq.eligible_units(gs.state, 1, false)
		and not "U_LEADER" in seq.eligible_units(gs.state, 1, false),
		str(seq.eligible_units(gs.state, 1, false)))
	_check("the pair are ONE combatant row",
		fp._combatants_11e().count("U_BG") == 1 and not "U_LEADER" in fp._combatants_11e(),
		str(fp._combatants_11e()))
	_check("group display name names both", fp._fight_attached_display_name("U_BG") == "Boyz T + Warboss T",
		fp._fight_attached_display_name("U_BG"))
	_check("_fight_group_ids covers both components",
		fp._fight_group_ids("U_BG") == ["U_BG", "U_LEADER"], str(fp._fight_group_ids("U_BG")))

	# Fights First is the Attached unit's: flag the LEADER only and the whole
	# unit must be offered in the Fights First step.
	gs.state.units["U_LEADER"].flags["fights_first"] = true
	_check("Fights First on the leader lifts the whole Attached unit",
		"U_BG" in seq.eligible_units(gs.state, 1, true), str(seq.eligible_units(gs.state, 1, true)))
	gs.state.units["U_LEADER"].flags.erase("fights_first")

	# Selecting the Attached unit spends BOTH components' fight.
	_check("selecting the leader directly is rejected",
		not fp._validate_select_fighter({"unit_id": "U_LEADER", "player": 1}).valid,
		str(fp._validate_select_fighter({"unit_id": "U_LEADER", "player": 1})))
	seq.select_to_fight("U_BG", gs.state)
	_check("select_to_fight marks the whole group fought",
		seq.fought.get("U_BG", false) and seq.fought.get("U_LEADER", false), str(seq.fought))
	_check("the leader is NOT owed a second activation",
		seq.eligible_units(gs.state, 1, false).is_empty()
		and not seq.group_eligible_to_fight("U_BG", gs.state),
		str(seq.eligible_units(gs.state, 1, false)))
	seq.fought.erase("U_BG")
	seq.fought.erase("U_LEADER")

	# Both components' assignments live in ONE activation's batch.
	fp.active_fighter_id = "U_BG"
	_check("an assignment may name the attached leader",
		fp._validate_assign_attacks({"unit_id": "U_LEADER", "target_id": "U_ATK",
			"weapon_id": "power_klaw_melee", "attacking_models": ["0"]}).valid,
		str(fp._validate_assign_attacks({"unit_id": "U_LEADER", "target_id": "U_ATK",
			"weapon_id": "power_klaw_melee", "attacking_models": ["0"]})))
	# The one-weapon rule is per COMPONENT: model "0" of the bodyguard and
	# model "0" of the leader are different models, and used to collide.
	fp.pending_attacks = [{"attacker": "U_BG", "weapon": "choppa_melee", "target": "U_ATK", "models": ["0"]}]
	_check("one-weapon rule does not collide across components",
		fp._find_one_weapon_rule_conflict("power_klaw_melee", ["0"], "U_LEADER") == "",
		fp._find_one_weapon_rule_conflict("power_klaw_melee", ["0"], "U_LEADER"))
	_check("one-weapon rule still fires WITHIN a component",
		fp._find_one_weapon_rule_conflict("power_klaw_melee", ["0"], "U_BG") == "choppa_melee",
		fp._find_one_weapon_rule_conflict("power_klaw_melee", ["0"], "U_BG"))

	# The AI submits ONE whole-unit assignment naming the bodyguard; the
	# attached leader must still swing in that same activation.
	fp.pending_attacks = []
	fp.confirmed_attacks = [{"attacker": "U_BG", "weapon": "choppa_melee", "target": "U_ATK"}]
	fp._auto_assign_unassigned_models()
	var leader_swings: Array = []
	for a in fp.confirmed_attacks:
		if str(a.get("attacker", "")) == "U_LEADER":
			leader_swings.append(str(a.get("weapon", "")))
	_check("a whole-unit assignment still makes the attached leader swing",
		leader_swings == ["power_klaw_melee"], str(fp.confirmed_attacks))
	fp.confirmed_attacks = []
	fp.active_fighter_id = ""

	print("\n-- 05.03/05.04 allocation fold --")
	var from_bg = rules._build_attached_allocation_unit_11e("U_BG", board)
	var from_leader = rules._build_attached_allocation_unit_11e("U_LEADER", board)
	_check("fold from the bodyguard carries all 3 models",
		from_bg.unit.models.size() == 3, str(from_bg.unit.models.size()))
	_check("fold from the LEADER resolves to the same Attached unit",
		from_leader.unit.models.size() == 3 and from_leader.sources == from_bg.sources,
		str(from_leader.unit.models.size()))
	var groups = Allocation.build_groups(from_bg.unit)
	var chars = 0
	var non_chars = 0
	for g in groups:
		if g.character:
			chars += 1
		else:
			non_chars += 1
	_check("groups: 1 CHARACTER group + the bodyguard group(s)",
		chars == 1 and non_chars >= 1, "chars=%d non=%d" % [chars, non_chars])
	var order = Allocation.default_order(groups)
	var by_id = {}
	for g in groups:
		by_id[str(g.id)] = g
	_check("default_order puts the CHARACTER group LAST (05.04)",
		not by_id[str(order[0])].character and by_id[str(order[-1])].character,
		str(order))

	# Restore
	for uid in ["U_ATK", "U_BG", "U_LEADER"]:
		gs.state.units.erase(uid)
	gs.state = prev_state
	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== RESULTS: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
