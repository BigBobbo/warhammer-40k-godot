extends Node

const GameStateData = preload("res://autoloads/GameState.gd")

# GameEventLog - Converts raw game actions into human-readable log entries
# Listens to PhaseManager signals and maintains a persistent log across all phases

signal entry_added(text: String, entry_type: String)

# entry_type: "phase_header", "p1_action", "p2_action", "ai_thinking", "info"
var entries: Array = []

# Noisy internal actions to filter out
const FILTERED_ACTIONS = [
	"STAGE_MODEL_MOVE",
	"UNDO_MODEL_MOVE",
	"RESET_UNIT_MOVE",
	"SELECT_UNIT",
	"DESELECT_UNIT",
	"DEBUG_MOVE",
	"SELECT_SHOOTER",
	"ASSIGN_TARGET",
	"CLEAR_ASSIGNMENT",
	"CLEAR_ALL_ASSIGNMENTS",
	"COMPLETE_SHOOTING_FOR_UNIT",
	"SELECT_FIGHTER",
	"SELECT_MELEE_WEAPON",
	"ASSIGN_ATTACKS",
	"CONFIRM_AND_RESOLVE_ATTACKS",
	"DECLINE_REACTIVE_STRATAGEM",
]

const PHASE_NAMES = {
	GameStateData.Phase.DEPLOYMENT: "Deployment",
	GameStateData.Phase.ROLL_OFF: "Roll-Off",
	GameStateData.Phase.COMMAND: "Command",
	GameStateData.Phase.MOVEMENT: "Movement",
	GameStateData.Phase.SHOOTING: "Shooting",
	GameStateData.Phase.CHARGE: "Charge",
	GameStateData.Phase.FIGHT: "Fight",
	GameStateData.Phase.SCORING: "Scoring",
	GameStateData.Phase.MORALE: "Morale",
}

func _ready() -> void:
	if PhaseManager:
		PhaseManager.phase_action_taken.connect(_on_action_taken)
		PhaseManager.phase_changed.connect(_on_phase_changed)
	print("GameEventLog: Initialized")

func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	var phase_name = PHASE_NAMES.get(new_phase, "Unknown")
	var turn = GameState.get_battle_round()
	var player = GameState.get_active_player()
	var header = "--- %s Phase (Round %d, P%d) ---" % [phase_name, turn, player]
	_add_entry(header, "phase_header")

func _on_action_taken(action: Dictionary) -> void:
	var action_type = action.get("type", "")

	# Filter out noisy internal actions
	if action_type in FILTERED_ACTIONS:
		return

	var player = action.get("player", 0)
	var text = _format_action(action, action_type, player)
	if text == "":
		return

	var entry_type = "p1_action" if player == 1 else "p2_action"
	_add_entry(text, entry_type)

func _format_action(action: Dictionary, action_type: String, player: int) -> String:
	var unit_id = action.get("unit_id", action.get("actor_unit_id", ""))
	var unit_name = _get_unit_name(unit_id)
	var prefix = "P%d: " % player

	# Prefer AI description when present — it includes decision reasons
	var ai_desc = action.get("_ai_description", "")

	match action_type:
		"DEPLOY_UNIT":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "Deployed %s" % unit_name
		"BEGIN_NORMAL_MOVE", "CONFIRM_UNIT_MOVE":
			if action_type == "CONFIRM_UNIT_MOVE":
				if ai_desc != "":
					return prefix + ai_desc
				return prefix + "%s moved" % unit_name
			return ""
		"REMAIN_STATIONARY":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s remained stationary" % unit_name
		"ADVANCE":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s advanced" % unit_name
		"SHOOT":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			if ai_desc != "":
				return prefix + ai_desc
			var target_name = _get_unit_name(action.get("target_unit_id", action.get("target_id", "")))
			return prefix + "%s shot at %s" % [unit_name, target_name]
		"FIGHT", "ROLL_DICE":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			if ai_desc != "":
				return prefix + ai_desc
			var target_name = _get_unit_name(action.get("target_unit_id", action.get("target_id", "")))
			return prefix + "%s fought %s" % [unit_name, target_name]
		"CHARGE":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			if ai_desc != "":
				return prefix + ai_desc
			var target_name = _get_unit_name(action.get("target_unit_id", action.get("target_id", "")))
			return prefix + "%s charged %s" % [unit_name, target_name]
		"PILE_IN":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s piled in" % unit_name
		"CONSOLIDATE":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s consolidated" % unit_name
		"END_DEPLOYMENT":
			return prefix + "Ended Deployment Phase"
		"END_MOVEMENT":
			return prefix + "Ended Movement Phase"
		"END_SHOOTING":
			return prefix + "Ended Shooting Phase"
		"END_CHARGE":
			return prefix + "Ended Charge Phase"
		"END_FIGHT":
			return prefix + "Ended Fight Phase"
		"END_TURN":
			return prefix + "Ended Turn"
		"SKIP_UNIT", "SKIP_CHARGE":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "Skipped %s" % unit_name
		"BATTLE_SHOCK_TEST":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return prefix + "%s took Battle-shock test" % unit_name
		"SCORE_PRIMARY", "SCORE_SECONDARY":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return prefix + "Scored points"
		"DECLARE_STRATEGIC_RESERVES":
			return prefix + "%s placed in Strategic Reserves" % unit_name
		_:
			# For any other action with log_text or ai_desc, show it
			if ai_desc != "":
				return prefix + ai_desc
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			# Skip unknown actions without log text to avoid noise
			return ""

func _get_unit_name(unit_id: String) -> String:
	if unit_id == "":
		return "Unknown"
	var units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	# Unit name is stored in meta.name for army-loaded units, or top-level name for defaults
	var meta = unit.get("meta", {})
	var name = meta.get("name", unit.get("name", ""))
	if name != "":
		return name
	return unit_id

func _add_entry(text: String, entry_type: String) -> void:
	entries.append({"text": text, "type": entry_type})
	print("[GameEventLog] %s" % text)
	DebugLogger.info("GameEventLog: %s" % text, {})
	emit_signal("entry_added", text, entry_type)

func add_ai_entry(player: int, text: String) -> void:
	"""Called directly by AIPlayer to log AI-specific events (failures, fallbacks, reasons)."""
	var prefix = "P%d: " % player
	var entry_type = "p1_action" if player == 1 else "p2_action"
	_add_entry(prefix + text, entry_type)

func add_ai_thinking_entry(player: int, text: String) -> void:
	"""Called by AIPlayer to log AI thinking/reasoning steps so the user can follow AI logic."""
	var prefix = "P%d AI: " % player
	_add_entry(prefix + text, "ai_thinking")

func get_all_entries() -> Array:
	return entries.duplicate()

func clear() -> void:
	entries.clear()
