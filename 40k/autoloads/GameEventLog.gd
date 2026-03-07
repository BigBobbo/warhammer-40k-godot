extends Node

const GameStateData = preload("res://autoloads/GameState.gd")

# GameEventLog - Converts raw game actions into human-readable log entries
# Listens to PhaseManager signals and maintains a persistent log across all phases

signal entry_added(text: String, entry_type: String)

# entry_type: "phase_header", "p1_action", "p2_action", "ai_thinking", "info",
#             "combat_header", "combat_detail", "combat_result"
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
	"SELECT_CHARGE_UNIT",
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
		"RESOLVE_SHOOTING":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return prefix + "%s shooting resolved" % unit_name
		"APPLY_SAVES":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return prefix + "Saves resolved"
		"APPLY_MELEE_SAVES":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return prefix + "Melee saves resolved"
		"DECLARE_CHARGE":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return ""
		"CHARGE_ROLL":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return ""
		"BEGIN_ADVANCE":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return ""
		"FALL_BACK":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s fell back" % unit_name
		"SWEEPING_ADVANCE":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s used Sweeping Advance" % unit_name
		"DECLINE_SWEEPING_ADVANCE":
			if ai_desc != "":
				return prefix + ai_desc
			return prefix + "%s declined Sweeping Advance" % unit_name
		"BATCH_FIGHT_ACTIONS":
			var log_text = action.get("_log_text", "")
			if log_text != "":
				return prefix + log_text
			return ""
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

func add_info_entry(text: String) -> void:
	"""Add a general information entry (VP scoring, mission status, CP generation, etc.)."""
	_add_entry(text, "info")

func add_player_entry(player: int, text: String) -> void:
	"""Add a player-attributed entry to the game log."""
	var prefix = "P%d: " % player
	var entry_type = "p1_action" if player == 1 else "p2_action"
	_add_entry(prefix + text, entry_type)

func add_overwatch_entry(text: String) -> void:
	"""Add a Fire Overwatch entry to the game log with distinctive styling."""
	_add_entry(text, "overwatch")

func add_combat_header(text: String) -> void:
	"""Add a combat section header (e.g. 'Unit A shoots at Unit B')."""
	_add_entry(text, "combat_header")

func add_combat_detail(text: String) -> void:
	"""Add a combat detail line (indented, smaller text for dice breakdowns)."""
	_add_entry(text, "combat_detail")

func add_combat_result(text: String) -> void:
	"""Add a combat result line (outcome summary — bold, colored)."""
	_add_entry(text, "combat_result")

func add_shooting_combat_log(shooter_name: String, target_name: String, weapon_name: String,
		total_attacks: int, hit_data: Dictionary, wound_data: Dictionary,
		save_info: Dictionary, result_info: Dictionary, player: int) -> void:
	"""Add a full verbose combat log card for a shooting attack sequence.
	hit_data: {rolls, threshold, successes, total, rerolls, modifiers_desc, critical_hits}
	wound_data: {rolls, threshold, successes, total, rerolls, auto_wounds, modifiers_desc, devastating_wounds}
	save_info: {rolls, threshold, passed, failed, using_invuln, invuln_value, ap, fnp_rolls, fnp_threshold, fnp_prevented}
	result_info: {wounds_inflicted, models_destroyed, damage_per_wound}"""

	var prefix = "P%d" % player

	# Header line
	add_combat_header("%s: %s shoots at %s" % [prefix, shooter_name, target_name])

	# Weapon and attacks
	add_combat_detail("  Weapon: %s (%d attacks)" % [weapon_name, total_attacks])

	# Hit roll details
	if hit_data.get("is_torrent", false):
		add_combat_detail("  To Hit: Auto-hit (Torrent) — %d hits" % hit_data.get("successes", 0))
	else:
		var hit_rolls_str = _format_dice_rolls(hit_data.get("rolls", []))
		var hit_line = "  To Hit: needed %s — rolled %s" % [hit_data.get("threshold", "?"), hit_rolls_str]
		hit_line += " — %d/%d hit" % [hit_data.get("successes", 0), hit_data.get("total", 0)]
		add_combat_detail(hit_line)

		# Hit modifiers
		var hit_mods = hit_data.get("modifiers_desc", "")
		if hit_mods != "":
			add_combat_detail("    Modifiers: %s" % hit_mods)

		# Hit rerolls
		var hit_rerolls = hit_data.get("rerolls", [])
		if not hit_rerolls.is_empty():
			var reroll_strs = []
			for rr in hit_rerolls:
				reroll_strs.append("%d→%d" % [rr.get("original", 0), rr.get("rerolled_to", rr.get("new", 0))])
			add_combat_detail("    Re-rolls: %s" % ", ".join(reroll_strs))

		# Critical hits
		var crits = hit_data.get("critical_hits", 0)
		if crits > 0:
			add_combat_detail("    Critical hits: %d" % crits)

		# Sustained hits
		var sustained = hit_data.get("sustained_bonus", 0)
		if sustained > 0:
			add_combat_detail("    Sustained Hits: +%d bonus hits" % sustained)

	# Wound roll details
	var wound_total = wound_data.get("total", 0)
	if wound_total > 0:
		var wound_rolls_str = _format_dice_rolls(wound_data.get("rolls", []))
		var wound_line = "  To Wound: needed %s — rolled %s" % [wound_data.get("threshold", "?"), wound_rolls_str]
		wound_line += " — %d/%d wounded" % [wound_data.get("successes", 0), wound_total]
		add_combat_detail(wound_line)

		# Wound modifiers
		var wound_mods = wound_data.get("modifiers_desc", "")
		if wound_mods != "":
			add_combat_detail("    Modifiers: %s" % wound_mods)

		# Wound rerolls
		var wound_rerolls = wound_data.get("rerolls", [])
		if not wound_rerolls.is_empty():
			var wrr_strs = []
			for wrr in wound_rerolls:
				wrr_strs.append("%d→%d" % [wrr.get("original", 0), wrr.get("rerolled_to", wrr.get("new", 0))])
			add_combat_detail("    Re-rolls: %s" % ", ".join(wrr_strs))

		# Auto-wounds from Lethal Hits
		var auto_wounds = wound_data.get("auto_wounds", 0)
		if auto_wounds > 0:
			add_combat_detail("    Lethal Hits: %d auto-wounds (no roll needed)" % auto_wounds)

		# Devastating Wounds
		var dw = wound_data.get("devastating_wounds", 0)
		if dw > 0:
			add_combat_detail("    DEVASTATING WOUNDS: %d (bypass saves)" % dw)

	# Save roll details
	var save_rolls = save_info.get("rolls", [])
	if not save_rolls.is_empty():
		var save_rolls_str = _format_dice_rolls(save_rolls)
		var save_type = ""
		if save_info.get("using_invuln", false):
			save_type = "Invulnerable Save %s" % save_info.get("threshold", "?")
		else:
			save_type = "Armour Save %s (AP -%d)" % [save_info.get("threshold", "?"), save_info.get("ap", 0)]
		var save_line = "  Saves: %s — rolled %s" % [save_type, save_rolls_str]
		save_line += " — %d passed, %d failed" % [save_info.get("passed", 0), save_info.get("failed", 0)]
		add_combat_detail(save_line)

	# Feel No Pain
	var fnp_rolls = save_info.get("fnp_rolls", [])
	if not fnp_rolls.is_empty():
		var fnp_str = _format_dice_rolls(fnp_rolls)
		var fnp_threshold = save_info.get("fnp_threshold", "?")
		var fnp_prevented = save_info.get("fnp_prevented", 0)
		add_combat_detail("  Feel No Pain %s+: rolled %s — %d wounds prevented" % [fnp_threshold, fnp_str, fnp_prevented])

	# Result summary
	var wounds_inflicted = result_info.get("wounds_inflicted", 0)
	var models_destroyed = result_info.get("models_destroyed", 0)
	var dmg_per = result_info.get("damage_per_wound", 1)
	var result_line = "  Result: %d wound(s) inflicted" % wounds_inflicted
	if dmg_per > 1:
		result_line += " (%d damage each)" % dmg_per
	result_line += " — %d model(s) destroyed" % models_destroyed
	add_combat_result(result_line)

func _format_dice_rolls(rolls: Array) -> String:
	"""Format an array of dice rolls as [3, 5, 2, 6] style string."""
	if rolls.is_empty():
		return "[]"
	return "[%s]" % ", ".join(rolls.map(func(r): return str(r)))

func get_all_entries() -> Array:
	return entries.duplicate()

func clear() -> void:
	entries.clear()
