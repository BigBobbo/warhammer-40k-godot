extends Node

# DiceHistoryPanel - Centralized dice roll history tracker
# Records all dice rolls from Shooting, Charge, and Fight phases
# Provides data for the scrollable history panel in the UI
#
# P3-117: Add dice roll history panel — scrollable history of past dice rolls for review

signal roll_recorded(entry: Dictionary)

# Maximum number of entries to keep (prevent unbounded memory growth)
const MAX_HISTORY_ENTRIES := 500

# All recorded dice roll entries
var history: Array = []

func _ready() -> void:
	print("DiceHistoryPanel: Initialized")
	var _debug_logger = Engine.get_singleton("DebugLogger") if Engine.has_singleton("DebugLogger") else null
	if _debug_logger == null:
		_debug_logger = get_node_or_null("/root/DebugLogger")
	if _debug_logger:
		_debug_logger.info("DiceHistoryPanel: Initialized", {})

func record_roll(dice_data: Dictionary, phase_name: String) -> void:
	"""Record a dice roll from any phase into the history."""
	var context = dice_data.get("context", "")

	# Skip non-roll contexts that are just informational messages
	if context in ["resolution_start", "weapon_progress"]:
		return

	var game_state = get_node_or_null("/root/GameState")
	var entry = {
		"timestamp": Time.get_ticks_msec(),
		"phase": phase_name,
		"context": context,
		"data": dice_data.duplicate(),
		"round": game_state.get_battle_round() if game_state else 0,
		"player": game_state.get_active_player() if game_state else 0,
	}

	history.append(entry)

	# Trim if over limit
	if history.size() > MAX_HISTORY_ENTRIES:
		history = history.slice(history.size() - MAX_HISTORY_ENTRIES)

	print("DiceHistoryPanel: Recorded %s roll (phase=%s, total=%d entries)" % [context, phase_name, history.size()])
	roll_recorded.emit(entry)

func get_history() -> Array:
	return history.duplicate()

func clear() -> void:
	history.clear()
	print("DiceHistoryPanel: History cleared")

func format_entry_bbcode(entry: Dictionary) -> String:
	"""Format a single history entry as BBCode for display in the UI panel."""
	var data = entry.get("data", {})
	var context = data.get("context", "")
	var phase = entry.get("phase", "")
	var battle_round = entry.get("round", 0)
	var player = entry.get("player", 0)

	var text = ""

	# Phase/round header prefix
	var phase_color = _get_phase_color(phase)
	text += "[color=%s][b]R%d P%d %s[/b][/color] " % [phase_color, battle_round, player, phase]

	match context:
		"to_hit":
			text += _format_standard_roll(data, "Hit", "cyan")
		"to_wound":
			text += _format_standard_roll(data, "Wound", "orange")
		"save_roll":
			text += _format_save_roll(data)
		"feel_no_pain":
			text += _format_fnp_roll(data)
		"charge_roll":
			text += _format_charge_roll(data)
		"auto_hit":
			text += _format_auto_hit(data)
		"variable_damage":
			text += _format_variable_damage(data)
		_:
			text += _format_generic_roll(data, context)

	return text

func _format_standard_roll(data: Dictionary, label: String, color: String) -> String:
	"""Format a standard hit/wound roll with threshold."""
	var rolls_raw = data.get("rolls_raw", [])
	var threshold = data.get("threshold", "")
	var successes = data.get("successes", 0)
	var threshold_int = int(threshold.replace("+", "")) if not str(threshold).is_empty() else 0

	var text = "[b]%s[/b] (%s): " % [label, threshold]

	# Show individual dice with color coding
	text += _format_dice_values(rolls_raw, threshold_int)

	text += " → [color=green]%d[/color]" % successes

	# Show rerolls if any
	var rerolls = data.get("rerolls", [])
	if not rerolls.is_empty():
		text += " [color=yellow](rerolled %d)[/color]" % rerolls.size()

	# Show special mechanics
	var critical_hits = data.get("critical_hits", 0)
	if label == "Hit" and critical_hits > 0:
		text += " [color=magenta]%d crit[/color]" % critical_hits

	var sustained_bonus = data.get("sustained_bonus_hits", 0)
	if label == "Hit" and sustained_bonus > 0:
		text += " [color=cyan]+%d sustained[/color]" % sustained_bonus

	var lethal_auto = data.get("lethal_hits_auto_wounds", 0)
	if label == "Wound" and lethal_auto > 0:
		text += " [color=magenta]+%d lethal[/color]" % lethal_auto

	return text

func _format_save_roll(data: Dictionary) -> String:
	var rolls_raw = data.get("rolls_raw", [])
	var threshold = data.get("threshold", "")
	var threshold_int = int(str(threshold).replace("+", "")) if not str(threshold).is_empty() else 0
	var failed = data.get("failed", 0)
	var using_invuln = data.get("using_invuln", false)

	var text = "[b]Save[/b] (%s" % threshold
	if using_invuln:
		text += " inv"
	text += "): "

	text += _format_dice_values(rolls_raw, threshold_int)

	if failed > 0:
		text += " → [color=red]%d failed[/color]" % failed
	else:
		text += " → [color=green]all saved[/color]"

	return text

func _format_fnp_roll(data: Dictionary) -> String:
	var fnp_val = data.get("fnp_value", 0)
	var rolls_raw = data.get("rolls_raw", [])
	var prevented = data.get("wounds_prevented", 0)
	var remaining = data.get("wounds_remaining", 0)

	var text = "[b]FNP[/b] (%d+): " % fnp_val
	text += _format_dice_values(rolls_raw, fnp_val)

	if prevented > 0:
		text += " → [color=green]%d prevented[/color]" % prevented
	else:
		text += " → [color=red]none prevented[/color]"

	return text

func _format_charge_roll(data: Dictionary) -> String:
	var rolls = data.get("rolls", data.get("rolls_raw", []))
	var total = data.get("total", 0)
	var unit_name = data.get("unit_name", "")
	var charge_failed = data.get("charge_failed", false)

	var text = "[b]Charge[/b]"
	if not unit_name.is_empty():
		text += " (%s)" % unit_name
	text += ": "

	for r in rolls:
		text += "[color=white]%d[/color] " % r
	text += "= %d\"" % total

	if charge_failed:
		text += " [color=red]FAILED[/color]"
	else:
		text += " [color=green]SUCCESS[/color]"

	return text

func _format_auto_hit(data: Dictionary) -> String:
	var hits = data.get("successes", 0)
	return "[b][color=lime]Torrent[/color][/b]: %d auto-hits" % hits

func _format_variable_damage(data: Dictionary) -> String:
	var notation = data.get("notation", "")
	var total_dmg = data.get("total_damage", 0)
	var dmg_rolls = data.get("rolls", [])
	var roll_values = []
	for r in dmg_rolls:
		roll_values.append(str(r.get("value", 0)))
	return "[b]Damage[/b] (%s): [%s] = %d" % [notation, ", ".join(roll_values), total_dmg]

func _format_generic_roll(data: Dictionary, context: String) -> String:
	var rolls_raw = data.get("rolls_raw", data.get("rolls", []))
	var text = "[b]%s[/b]: " % context.capitalize().replace("_", " ")
	for r in rolls_raw:
		text += "%d " % r
	return text

func _format_dice_values(rolls: Array, threshold: int) -> String:
	"""Format dice values with color coding: gold=6, red=1, green=pass, gray=fail."""
	var text = ""
	for r in rolls:
		if r == 6:
			text += "[color=gold]%d[/color] " % r
		elif r == 1:
			text += "[color=red]%d[/color] " % r
		elif threshold > 0 and r >= threshold:
			text += "[color=green]%d[/color] " % r
		elif threshold > 0:
			text += "[color=gray]%d[/color] " % r
		else:
			text += "[color=white]%d[/color] " % r
	return text.strip_edges()

func _get_phase_color(phase: String) -> String:
	match phase:
		"Shooting":
			return "#6699CC"
		"Charge":
			return "#CC9933"
		"Fight":
			return "#CC6666"
		"Movement":
			return "#66CC66"
		_:
			return "#AAAAAA"
