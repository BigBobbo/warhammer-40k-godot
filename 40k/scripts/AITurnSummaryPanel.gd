extends Node
class_name AITurnSummaryPanel

# AITurnSummaryPanel - Post-turn AI digest emitter (T7-19)
# Originally a right-hand-side pop-up panel, this now writes the AI turn summary
# straight into the GAME LOG as a single collapsible card instead of covering the
# existing menus with a separate window. It still consumes the `ai_turn_ended`
# signal and the `_action_log` from AIPlayer, categorizes the actions per phase
# (units moved, shooting/charge/fight results, stratagems used, reinforcements…),
# and shows the notable moments — but the digest now lives ONLY in the game log
# (via GameEventLog.add_ai_turn_summary) and is shown nowhere else.
#
# NOTE: the class is still named AITurnSummaryPanel (and still referenced from
# Main.gd) for continuity; it is no longer a Control/pop-up, just a lightweight
# node that formats the summary and hands it to the log.

const GameStateData = preload("res://autoloads/GameState.gd")

# Phase name lookup
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
	name = "AITurnSummaryPanel"
	print("[AITurnSummaryPanel] T7-19: Ready (logs to game log, no pop-up)")

# ── Public API ──────────────────────────────────────────────────────────

func show_summary(player: int, action_summary: Array) -> void:
	"""Called when ai_turn_ended fires. Builds the turn summary and appends it to
	the game log as a collapsible card (no pop-up window)."""
	if action_summary.is_empty():
		print("[AITurnSummaryPanel] T7-19: No actions to summarize for player %d" % player)
		return

	var built = _build_summary(player, action_summary)
	var header: String = built.get("header", "AI Turn Summary")
	var lines: Array = built.get("lines", [])

	var gel = get_node_or_null("/root/GameEventLog")
	if gel and gel.has_method("add_ai_turn_summary"):
		gel.add_ai_turn_summary(player, header, lines)
		print("[AITurnSummaryPanel] T7-19: Logged summary for player %d (%d actions)" % [player, action_summary.size()])
	else:
		push_warning("[AITurnSummaryPanel] GameEventLog.add_ai_turn_summary unavailable — summary not logged")

func hide_summary() -> void:
	"""No-op — retained for API compatibility now that there is no pop-up to hide."""
	pass

# ── Private ─────────────────────────────────────────────────────────────

func _build_summary(player: int, action_summary: Array) -> Dictionary:
	"""Parse the action log into a plain-text header + per-phase breakdown lines
	suitable for a game-log card. First element of `lines` follows the header."""
	var lines: Array = []

	# Header — player, faction, battle round
	var faction_name = ""
	var battle_round = 0
	var game_state = _get_game_state()
	if game_state:
		faction_name = game_state.get_faction_name(player)
		battle_round = game_state.get_battle_round()
	var header = "AI Turn Summary — Player %d" % player
	if faction_name != "":
		header += " (%s)" % faction_name
	if battle_round > 0:
		header += ", Battle Round %d" % battle_round

	# Categorize actions by phase, then by type within each phase
	var phase_actions = _categorize_by_phase(action_summary)

	var any_content = false
	if not phase_actions.is_empty():
		for phase_id in phase_actions:
			var phase_name = PHASE_NAMES.get(phase_id, "Phase %d" % phase_id)
			var actions = phase_actions[phase_id]
			var counts = _count_action_categories(actions)
			if counts.is_empty():
				continue
			any_content = true

			# Phase sub-header
			lines.append(phase_name)

			# Category stats (icon + label + count)
			for entry in _format_category_counts(counts):
				lines.append("  " + entry.text)

			# Notable action descriptions (charges, stratagems, reinforcements)
			for desc in _get_notable_actions(actions):
				lines.append("  > " + desc)

	if not any_content:
		lines.append("No significant actions taken.")

	return {"header": header, "lines": lines}

func _categorize_by_phase(actions: Array) -> Dictionary:
	"""Group actions by their phase ID, preserving phase order."""
	var result: Dictionary = {}  # phase_id -> Array of actions
	var phase_order: Array = []  # Track insertion order
	for action in actions:
		var phase_id = action.get("phase", -1)
		if not result.has(phase_id):
			result[phase_id] = []
			phase_order.append(phase_id)
		result[phase_id].append(action)

	# Return in order of appearance (Dictionary insertion order is preserved in Godot 4)
	var ordered: Dictionary = {}
	for pid in phase_order:
		ordered[pid] = result[pid]
	return ordered

func _count_action_categories(actions: Array) -> Dictionary:
	"""Count actions by category within a phase."""
	var counts: Dictionary = {}
	for action in actions:
		var action_type = action.get("action_type", "")
		var category = _categorize_action(action_type)
		if category != "":
			counts[category] = counts.get(category, 0) + 1
	return counts

func _categorize_action(action_type: String) -> String:
	"""Map action types to readable summary categories (matches AIPlayer._categorize_action)."""
	match action_type:
		"DEPLOY_UNIT":
			return "units_deployed"
		"REMAIN_STATIONARY":
			return "units_stationary"
		"CONFIRM_UNIT_MOVE", "BEGIN_NORMAL_MOVE":
			return "units_moved"
		"BEGIN_ADVANCE":
			return "units_advanced"
		"BEGIN_FALL_BACK":
			return "units_fell_back"
		"SHOOT":
			return "units_shot"
		"DECLARE_CHARGE":
			return "charges_declared"
		"SELECT_FIGHTER", "ASSIGN_ATTACKS":
			return "units_fought"
		"USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH", "USE_COUNTER_OFFENSIVE", \
		"USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK", "USE_GRENADE_STRATAGEM", \
		"USE_COMMAND_REROLL":
			return "stratagems_used"
		"SKIP_UNIT", "SKIP_CHARGE":
			return "units_skipped"
		"PLACE_REINFORCEMENT":
			return "reinforcements"
		"CONFIRM_SCOUT_MOVE":
			return "scouts_moved"
		"END_MOVEMENT", "END_SHOOTING", "END_CHARGE", "END_FIGHT", "END_SCORING":
			return ""  # Phase-ending actions are not shown
		_:
			return ""

func _format_category_counts(counts: Dictionary) -> Array:
	"""Format category counts into display entries with labels and icons."""
	var entries: Array = []

	# Define display order and labels
	var display_config = [
		{"key": "units_deployed", "label": "Units deployed", "icon": "+"},
		{"key": "scouts_moved", "label": "Scout moves", "icon": ">"},
		{"key": "units_moved", "label": "Units moved", "icon": ">"},
		{"key": "units_advanced", "label": "Units advanced", "icon": ">>"},
		{"key": "units_fell_back", "label": "Units fell back", "icon": "<"},
		{"key": "units_stationary", "label": "Units remained stationary", "icon": "-"},
		{"key": "reinforcements", "label": "Reinforcements arrived", "icon": "+"},
		{"key": "units_shot", "label": "Units fired", "icon": "*"},
		{"key": "charges_declared", "label": "Charges declared", "icon": "!"},
		{"key": "units_fought", "label": "Units fought", "icon": "x"},
		{"key": "stratagems_used", "label": "Stratagems used", "icon": "#"},
		{"key": "units_skipped", "label": "Units skipped", "icon": "~"},
	]

	for config in display_config:
		var key = config.key
		if counts.has(key) and counts[key] > 0:
			entries.append({
				"text": "%s %s: %d" % [config.icon, config.label, counts[key]]
			})

	return entries

func _get_notable_actions(actions: Array) -> Array:
	"""Extract notable action descriptions for display (charges, stratagems, key fights)."""
	var notable: Array = []
	var notable_types = [
		"DECLARE_CHARGE", "USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH",
		"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK",
		"USE_GRENADE_STRATAGEM", "USE_COMMAND_REROLL", "PLACE_REINFORCEMENT"
	]
	var max_notable = 4

	for action in actions:
		if notable.size() >= max_notable:
			break
		var action_type = action.get("action_type", "")
		if action_type in notable_types:
			var desc = action.get("description", "")
			if desc != "":
				notable.append(desc)

	return notable

func _get_game_state() -> Node:
	"""Get GameState autoload via node tree."""
	var root = get_tree().root if get_tree() else null
	if root:
		return root.get_node_or_null("GameState")
	return null
