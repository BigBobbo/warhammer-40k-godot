extends "res://addons/gut/test.gd"

# Tests for the Pre-Battle Formations Declaration implementation (T3-6)
#
# Per Warhammer 40k 10th Edition rules:
# Before deployment, each player must declare:
#   1. Leader attachments (which CHARACTER attaches to which bodyguard)
#   2. Transport embarkations (which units start inside which transports)
#   3. Strategic Reserves / Deep Strike declarations
# Then both players simultaneously reveal their choices.
#
# These tests verify:
# 1. FormationsPhase creation and auto-skip when no options
# 2. Leader attachment declarations and validation
# 3. Transport embarkation declarations and validation
# 4. Reserves declarations and 50% point/unit cap
# 5. Confirmation flow (both players must confirm)
# 6. Formations applied to GameState correctly
# 7. Deployment phase skips dialogs when formations declared
# 8. GameState helper functions for formations data

const GameStateData = preload("res://autoloads/GameState.gd")
const FormationsPhaseScript = preload("res://phases/FormationsPhase.gd")

var game_state_node: Node
var phase: Node

# ==========================================
# Setup / Teardown
# ==========================================

func before_each():
	if not AutoloadHelper.verify_autoloads_available():
		push_error("Required autoloads not available - cannot run test")
		return
	game_state_node = AutoloadHelper.get_game_state()
	assert_not_null(game_state_node, "GameState autoload must be available")

func after_each():
	if phase:
		phase.queue_free()
		phase = null

# ==========================================
# Helpers
# ==========================================

func _create_formations_test_state(include_characters: bool = true, include_transports: bool = true) -> Dictionary:
	"""Create a test game state for formations testing."""
	var state = {
		"game_id": "test_formations",
		"meta": {
			"active_player": 1,
			"turn_number": 1,
			"battle_round": 1,
			"phase": GameStateData.Phase.FORMATIONS
		},
		"units": {},
		"board": {
			"size": {"width": 44.0, "height": 60.0},
			"deployment_zones": [
				{"player": 1, "poly": [{"x": 0, "y": 0}, {"x": 44, "y": 0}, {"x": 44, "y": 12}, {"x": 0, "y": 12}]},
				{"player": 2, "poly": [{"x": 0, "y": 48}, {"x": 44, "y": 48}, {"x": 44, "y": 60}, {"x": 0, "y": 60}]}
			],
			"terrain": []
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"factions": {
			"1": {"name": "Space Marines", "points": 1000},
			"2": {"name": "Orks", "points": 1000}
		},
		"phase_log": [],
		"history": []
	}

	# Player 1 bodyguard unit (non-CHARACTER INFANTRY)
	state.units["intercessors_a"] = {
		"id": "intercessors_a",
		"squad_id": "intercessors_a",
		"owner": 1,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Intercessor Squad A",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM"],
			"points": 90
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true}
		]
	}

	# Player 1 second bodyguard unit
	state.units["intercessors_b"] = {
		"id": "intercessors_b",
		"squad_id": "intercessors_b",
		"owner": 1,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Intercessor Squad B",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM"],
			"points": 90
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true}
		]
	}

	if include_characters:
		# Player 1 CHARACTER with Leader ability
		state.units["captain_a"] = {
			"id": "captain_a",
			"squad_id": "captain_a",
			"owner": 1,
			"status": GameStateData.UnitStatus.UNDEPLOYED,
			"meta": {
				"name": "Captain",
				"stats": {"move": 6, "toughness": 4, "save": 3, "wounds": 5},
				"keywords": ["CHARACTER", "INFANTRY", "PRIMARIS", "IMPERIUM"],
				"leader_data": {
					"can_lead": ["INFANTRY", "PRIMARIS"]
				},
				"points": 80
			},
			"models": [
				{"id": "m1", "wounds": 5, "current_wounds": 5, "base_mm": 40, "position": null, "alive": true}
			]
		}

	if include_transports:
		# Player 1 transport
		state.units["impulsor_a"] = {
			"id": "impulsor_a",
			"squad_id": "impulsor_a",
			"owner": 1,
			"status": GameStateData.UnitStatus.UNDEPLOYED,
			"transport_data": {
				"capacity": 6,
				"capacity_keywords": ["INFANTRY"],
				"embarked_units": [],
				"current_capacity_used": 0
			},
			"meta": {
				"name": "Impulsor",
				"stats": {"move": 12, "toughness": 7, "save": 3},
				"keywords": ["VEHICLE", "TRANSPORT", "IMPERIUM"],
				"points": 115
			},
			"models": [
				{"id": "m1", "wounds": 11, "current_wounds": 11, "base_mm": 100, "position": null, "alive": true}
			]
		}

	# Player 1 Deep Strike unit
	state.units["assault_a"] = {
		"id": "assault_a",
		"squad_id": "assault_a",
		"owner": 1,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Assault Intercessors",
			"stats": {"move": 6, "toughness": 4, "save": 3},
			"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM"],
			"abilities": [
				{"name": "Deep Strike", "type": "Core"}
			],
			"points": 80
		},
		"models": [
			{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true},
			{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true}
		]
	}

	# Player 2 basic units
	state.units["boyz_a"] = {
		"id": "boyz_a",
		"squad_id": "boyz_a",
		"owner": 2,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Boyz",
			"stats": {"move": 6, "toughness": 5, "save": 6},
			"keywords": ["INFANTRY", "ORKS"],
			"points": 90
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true}
		]
	}
	state.units["boyz_b"] = {
		"id": "boyz_b",
		"squad_id": "boyz_b",
		"owner": 2,
		"status": GameStateData.UnitStatus.UNDEPLOYED,
		"meta": {
			"name": "Boyz B",
			"stats": {"move": 6, "toughness": 5, "save": 6},
			"keywords": ["INFANTRY", "ORKS"],
			"points": 90
		},
		"models": [
			{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true},
			{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true},
			{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true}
		]
	}

	return state

func _create_phase(state: Dictionary) -> Node:
	"""Create a FormationsPhase instance with the given state."""
	var phase_node = Node.new()
	phase_node.set_script(FormationsPhaseScript)
	add_child(phase_node)
	phase_node.enter_phase(state)
	return phase_node

func _setup_gamestate_for_formations(include_characters: bool = true, include_transports: bool = true) -> Dictionary:
	var state = _create_formations_test_state(include_characters, include_transports)
	game_state_node.state = state
	return state

# ==========================================
# Test: GameState Helper Functions
# ==========================================

func test_get_characters_for_player():
	_setup_gamestate_for_formations()
	var characters = game_state_node.get_characters_for_player(1)
	assert_eq(characters.size(), 1, "Player 1 should have 1 CHARACTER with leader ability")
	assert_eq(characters[0], "captain_a", "Should find captain_a")

func test_get_characters_for_player_no_characters():
	_setup_gamestate_for_formations(false, false)
	var characters = game_state_node.get_characters_for_player(1)
	assert_eq(characters.size(), 0, "Should find no characters when none exist")

func test_get_transports_for_player():
	_setup_gamestate_for_formations()
	var transports = game_state_node.get_transports_for_player(1)
	assert_eq(transports.size(), 1, "Player 1 should have 1 transport")
	assert_eq(transports[0], "impulsor_a", "Should find impulsor_a")

func test_get_transports_for_player_no_transports():
	_setup_gamestate_for_formations(true, false)
	var transports = game_state_node.get_transports_for_player(1)
	assert_eq(transports.size(), 0, "Should find no transports when none exist")

func test_get_eligible_bodyguards_for_character():
	_setup_gamestate_for_formations()
	var eligible = game_state_node.get_eligible_bodyguards_for_character("captain_a")
	assert_gt(eligible.size(), 0, "Captain should have at least one eligible bodyguard")
	assert_has(eligible, "intercessors_a", "Intercessors A should be eligible")
	assert_has(eligible, "intercessors_b", "Intercessors B should be eligible")

func test_formations_declared_default_false():
	_setup_gamestate_for_formations()
	assert_false(game_state_node.formations_declared(), "Formations should not be declared initially")

# ==========================================
# Test: FormationsPhase Validation
# ==========================================

func test_validate_declare_leader_attachment():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_a",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Should allow valid leader attachment: %s" % str(result.errors))

func test_validate_declare_leader_attachment_wrong_player():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_a",
		"player": 2  # Wrong player
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Should reject attachment from wrong player")

func test_validate_declare_leader_attachment_non_character():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "intercessors_a",  # Not a CHARACTER
		"bodyguard_id": "intercessors_b",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Should reject non-CHARACTER as leader")

func test_validate_declare_transport_embarkation():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_TRANSPORT_EMBARKATION",
		"transport_id": "impulsor_a",
		"unit_ids": ["intercessors_a"],
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Should allow valid transport embarkation: %s" % str(result.errors))

func test_validate_declare_transport_overcapacity():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# Try to embark two 5-model units in a 6-capacity transport
	var action = {
		"type": "DECLARE_TRANSPORT_EMBARKATION",
		"transport_id": "impulsor_a",
		"unit_ids": ["intercessors_a", "intercessors_b"],
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Should reject over-capacity embarkation")

func test_validate_declare_reserves():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_RESERVES",
		"unit_id": "assault_a",
		"reserve_type": "deep_strike",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Should allow deep strike declaration: %s" % str(result.errors))

func test_validate_declare_reserves_strategic():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_RESERVES",
		"unit_id": "intercessors_a",
		"reserve_type": "strategic_reserves",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Should allow strategic reserves declaration: %s" % str(result.errors))

func test_validate_declare_deep_strike_without_ability():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_RESERVES",
		"unit_id": "intercessors_a",  # No Deep Strike ability
		"reserve_type": "deep_strike",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_false(result.valid, "Should reject Deep Strike without ability")

func test_validate_confirm_formations():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "CONFIRM_FORMATIONS",
		"player": 1
	}
	var result = phase.validate_action(action)
	assert_true(result.valid, "Should allow confirming formations: %s" % str(result.errors))

# ==========================================
# Test: FormationsPhase Processing
# ==========================================

func test_process_declare_leader_attachment():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_a",
		"player": 1
	}
	var result = phase.process_action(action)
	assert_true(result.success, "Should process leader attachment")

	# Verify it was stored
	assert_eq(phase.player_formations[1]["leader_attachments"]["captain_a"], "intercessors_a")

func test_process_declare_transport_embarkation():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_TRANSPORT_EMBARKATION",
		"transport_id": "impulsor_a",
		"unit_ids": ["intercessors_a"],
		"player": 1
	}
	var result = phase.process_action(action)
	assert_true(result.success, "Should process transport embarkation")

	# Verify it was stored
	assert_has(phase.player_formations[1]["transport_embarkations"]["impulsor_a"], "intercessors_a")

func test_process_declare_reserves():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "DECLARE_RESERVES",
		"unit_id": "assault_a",
		"reserve_type": "deep_strike",
		"player": 1
	}
	var result = phase.process_action(action)
	assert_true(result.success, "Should process reserves declaration")

	# Verify it was stored
	assert_eq(phase.player_formations[1]["reserves"].size(), 1)
	assert_eq(phase.player_formations[1]["reserves"][0]["unit_id"], "assault_a")
	assert_eq(phase.player_formations[1]["reserves"][0]["reserve_type"], "deep_strike")

func test_process_undeclare_leader_attachment():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# First declare
	phase.process_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_a",
		"player": 1
	})
	assert_eq(phase.player_formations[1]["leader_attachments"].size(), 1)

	# Then undeclare
	var result = phase.process_action({
		"type": "UNDECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"player": 1
	})
	assert_true(result.success, "Should process undeclaration")
	assert_eq(phase.player_formations[1]["leader_attachments"].size(), 0)

func test_process_undeclare_reserves():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# First declare
	phase.process_action({
		"type": "DECLARE_RESERVES",
		"unit_id": "assault_a",
		"reserve_type": "deep_strike",
		"player": 1
	})
	assert_eq(phase.player_formations[1]["reserves"].size(), 1)

	# Then undeclare
	var result = phase.process_action({
		"type": "UNDECLARE_RESERVES",
		"unit_id": "assault_a",
		"player": 1
	})
	assert_true(result.success, "Should process undeclaration")
	assert_eq(phase.player_formations[1]["reserves"].size(), 0)

# ==========================================
# Test: Confirmation Flow
# ==========================================

func test_confirm_formations_player_1():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var action = {
		"type": "CONFIRM_FORMATIONS",
		"player": 1
	}
	var result = phase.process_action(action)
	assert_true(result.success, "Should process confirmation")
	assert_true(phase.players_confirmed[1], "Player 1 should be confirmed")
	assert_false(phase.players_confirmed[2], "Player 2 should not be confirmed yet")

func test_double_confirm_rejected():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# First confirm
	phase.process_action({"type": "CONFIRM_FORMATIONS", "player": 1})

	# Second confirm should be rejected
	var result = phase.validate_action({"type": "CONFIRM_FORMATIONS", "player": 1})
	assert_false(result.valid, "Should reject double confirmation")

func test_cannot_modify_after_confirm():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# Confirm
	phase.process_action({"type": "CONFIRM_FORMATIONS", "player": 1})

	# Try to undeclare after confirming
	var result = phase.validate_action({
		"type": "UNDECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"player": 1
	})
	assert_false(result.valid, "Should reject modifications after confirming")

# ==========================================
# Test: Duplicate Declaration Prevention
# ==========================================

func test_cannot_declare_character_twice():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# Declare captain attached to intercessors_a
	phase.process_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_a",
		"player": 1
	})

	# Try to declare captain again to different bodyguard
	var result = phase.validate_action({
		"type": "DECLARE_LEADER_ATTACHMENT",
		"character_id": "captain_a",
		"bodyguard_id": "intercessors_b",
		"player": 1
	})
	assert_false(result.valid, "Should reject duplicate character attachment")

func test_cannot_declare_unit_in_reserves_if_embarked():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	# Embark intercessors_a in impulsor
	phase.process_action({
		"type": "DECLARE_TRANSPORT_EMBARKATION",
		"transport_id": "impulsor_a",
		"unit_ids": ["intercessors_a"],
		"player": 1
	})

	# Try to put intercessors_a in reserves too
	var result = phase.validate_action({
		"type": "DECLARE_RESERVES",
		"unit_id": "intercessors_a",
		"reserve_type": "strategic_reserves",
		"player": 1
	})
	assert_false(result.valid, "Should reject reserves for embarked unit")

# ==========================================
# Test: Available Actions
# ==========================================

func test_available_actions_include_leader_options():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var actions = phase.get_available_actions()
	var has_leader = false
	for action in actions:
		if action.get("type") == "DECLARE_LEADER_ATTACHMENT":
			has_leader = true
			break
	assert_true(has_leader, "Available actions should include leader attachment options")

func test_available_actions_include_confirm():
	var state = _setup_gamestate_for_formations()
	phase = _create_phase(state)

	var actions = phase.get_available_actions()
	var has_confirm = false
	for action in actions:
		if action.get("type") == "CONFIRM_FORMATIONS":
			has_confirm = true
			break
	assert_true(has_confirm, "Available actions should include confirm option")

# ==========================================
# Test: Phase Enum
# ==========================================

func test_formations_phase_enum_exists():
	assert_eq(GameStateData.Phase.FORMATIONS, 0, "FORMATIONS should be the first phase (enum value 0)")
	assert_eq(GameStateData.Phase.DEPLOYMENT, 1, "DEPLOYMENT should be the second phase (enum value 1)")

func test_formations_phase_before_deployment():
	# Verify FORMATIONS comes before DEPLOYMENT in the enum
	assert_lt(GameStateData.Phase.FORMATIONS, GameStateData.Phase.DEPLOYMENT,
		"FORMATIONS should come before DEPLOYMENT in phase ordering")

# ==========================================
# Test: GameState Formations Data
# ==========================================

func test_formations_helpers_with_declared_data():
	_setup_gamestate_for_formations()

	# Simulate formations being applied to GameState
	game_state_node.state["meta"]["formations_declared"] = true
	game_state_node.state["meta"]["formations"] = {
		"1": {
			"leader_attachments": {"captain_a": "intercessors_a"},
			"transport_embarkations": {},
			"reserves": [{"unit_id": "assault_a", "reserve_type": "deep_strike"}]
		},
		"2": {
			"leader_attachments": {},
			"transport_embarkations": {},
			"reserves": []
		}
	}

	assert_true(game_state_node.formations_declared(), "Formations should be declared")
	assert_eq(game_state_node.get_leader_attachments_for_player(1).size(), 1, "P1 should have 1 leader attachment")
	assert_eq(game_state_node.get_reserves_declarations_for_player(1).size(), 1, "P1 should have 1 reserve")
	assert_true(game_state_node.is_unit_pre_declared_attached("captain_a"), "Captain should be pre-declared as attached")
	assert_true(game_state_node.is_unit_pre_declared_in_reserves("assault_a"), "Assault should be pre-declared in reserves")
	assert_false(game_state_node.is_unit_pre_declared_in_reserves("intercessors_a"), "Intercessors should not be in reserves")
