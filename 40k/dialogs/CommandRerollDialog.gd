extends AcceptDialog

# CommandRerollDialog - UI for Command Re-roll stratagem
#
# COMMAND RE-ROLL (Core – Battle Tactic Stratagem, 1 CP)
# WHEN: Any phase, just after you make a roll for a unit from your army.
# TARGET: That unit or model from your army.
# EFFECT: You re-roll that roll, test or saving throw.
# RESTRICTION: Once per phase.
#
# Shows the original roll and lets the player choose to re-roll or keep it.
#
# FREE-ABILITY MODE: pass a non-empty p_free_ability_name to setup() (e.g.
# "Swift Onslaught") and the dialog rebrands as that ability's FREE re-roll —
# no stratagem header, no CP cost on the button, and an explicit "costs no CP"
# line. The signals are unchanged, so callers wire used/declined the same way.

signal command_reroll_used(unit_id: String, player: int)
signal command_reroll_declined(unit_id: String, player: int)

var unit_id: String = ""
var player: int = 0
var unit_name: String = ""
var roll_type: String = ""
var original_rolls: Array = []
var roll_total: int = 0
var roll_context_text: String = ""
var free_ability_name: String = ""
var _choice_made: bool = false

func setup(p_unit_id: String, p_player: int, p_roll_type: String, p_original_rolls: Array, p_context_text: String = "", p_free_ability_name: String = "") -> void:
	# Stable node name so windowed scenarios can address the dialog and its
	# buttons regardless of which controller spawned it.
	name = "CommandRerollDialog"
	WhiteDwarfTheme.apply_to_dialog(self)
	unit_id = p_unit_id
	player = p_player
	roll_type = p_roll_type
	original_rolls = p_original_rolls
	roll_context_text = p_context_text
	free_ability_name = p_free_ability_name

	roll_total = 0
	for r in original_rolls:
		roll_total += r

	var unit = GameState.get_unit(unit_id)
	var _crd_meta = unit.get("meta", {})
	unit_name = _crd_meta.get("display_name", _crd_meta.get("name", unit_id))

	if free_ability_name != "":
		title = "%s — Free Re-roll - Player %d" % [free_ability_name, player]
	else:
		title = "Command Re-roll Available - Player %d" % player
	min_size = DialogConstants.SMALL

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	# The pending reroll decision pauses the phase, so the dialog must always
	# resolve to used/declined. Closing it any other way (✕ button, ESC) counts
	# as keeping the roll — otherwise the phase waits forever on a decision the
	# player can no longer give.
	canceled.connect(_on_dialog_dismissed)
	close_requested.connect(_on_dialog_dismissed)

	_build_ui()

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.SMALL.x - 20, 0)
	main_container.add_theme_constant_override("separation", 8)

	# Header
	var header = Label.new()
	header.name = "HeaderLabel"
	header.text = ("%s — FREE RE-ROLL" % free_ability_name.to_upper()) if free_ability_name != "" else "COMMAND RE-ROLL"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	# Subheader
	var subheader = Label.new()
	subheader.name = "SubheaderLabel"
	subheader.text = "Unit Ability — Free Re-roll" if free_ability_name != "" else "Core — Battle Tactic Stratagem (1 CP)"
	subheader.add_theme_font_size_override("font_size", 12)
	subheader.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(subheader)

	main_container.add_child(HSeparator.new())

	# Roll info
	var roll_label = Label.new()
	var roll_type_display = _get_roll_type_display()
	roll_label.text = "%s — %s" % [unit_name, roll_type_display]
	roll_label.add_theme_font_size_override("font_size", 14)
	roll_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	roll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(roll_label)

	# Dice display with styled die faces
	var dice_container = HBoxContainer.new()
	dice_container.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_container.add_theme_constant_override("separation", 8)

	for i in range(original_rolls.size()):
		var die_val = int(original_rolls[i])
		# Show each die as its d6 face icon (pips) rather than a number, matching
		# the combat log and the rest of the game's dice visuals. This is a generic
		# reroll dialog (charge / advance / hit / wound / save / damage), so colour
		# by value: crit (gold), fumble (red), else neutral.
		var die := TextureRect.new()
		die.name = "Die%d" % i
		var bg := DiceFaceIcons.color_for(die_val, 0, false, 6)
		die.texture = DiceFaceIcons.get_face(die_val, bg)
		die.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		die.custom_minimum_size = Vector2(40, 40)
		die.tooltip_text = "Rolled %d" % die_val
		dice_container.add_child(die)

	var total_label = Label.new()
	total_label.text = "= %d" % roll_total
	total_label.add_theme_font_size_override("font_size", 20)
	total_label.add_theme_color_override("font_color", Color.WHITE)
	dice_container.add_child(total_label)

	main_container.add_child(dice_container)

	# Context text (e.g., "Need 7+ to pass" or "Need 5 to reach target")
	if roll_context_text != "":
		var context_label = Label.new()
		context_label.text = roll_context_text
		context_label.add_theme_font_size_override("font_size", 13)
		context_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(context_label)

	# CP availability — or, for a free ability reroll, make it unmissable that
	# no CP is needed (a 0-CP player must still be able to use it).
	var cp_label = Label.new()
	cp_label.name = "CpLabel"
	if free_ability_name != "":
		cp_label.text = "FREE — costs no CP"
		cp_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	else:
		cp_label.text = "You have %d CP" % StratagemManager.get_player_cp(player)
		cp_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	cp_label.add_theme_font_size_override("font_size", 11)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Action buttons
	var button_container = HBoxContainer.new()
	button_container.name = "ButtonRow"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 16)

	# "Keep Roll" is the safe, non-destructive choice, so it is the highlighted
	# default on the LEFT. This prevents a player from instinctively clicking the
	# prominent left-hand button and accidentally spending a CP (or burning a good
	# roll on a free re-roll that might come back worse) — especially after a
	# successful charge, where re-rolling almost never makes sense.
	var decline_button = Button.new()
	decline_button.name = "KeepRollButton"
	decline_button.text = "Keep Roll"
	decline_button.custom_minimum_size = Vector2(160, 42)
	decline_button.pressed.connect(_on_decline_pressed)
	WhiteDwarfTheme.apply_primary_button(decline_button)
	button_container.add_child(decline_button)

	var use_button = Button.new()
	use_button.name = "UseRerollButton"
	use_button.text = "Re-roll (Free)" if free_ability_name != "" else "Re-roll (1 CP)"
	use_button.custom_minimum_size = Vector2(130, 42)
	use_button.pressed.connect(_on_use_pressed)
	WhiteDwarfTheme.apply_secondary_button(use_button)
	button_container.add_child(use_button)

	main_container.add_child(button_container)

	add_child(main_container)

	# Focus the safe default so a keyboard/controller confirm (Enter/Space) keeps
	# the roll rather than spending a CP. Deferred because the buttons are not in
	# the scene tree until the dialog is added and popped up by the caller.
	decline_button.grab_focus.call_deferred()

func _get_roll_type_display() -> String:
	match roll_type:
		"charge_roll":
			return "Charge Roll (2D6)"
		"battle_shock_test":
			return "Battle-shock Test (2D6)"
		"advance_roll":
			return "Advance Roll (D6)"
		"hit_roll":
			return "Hit Roll"
		"wound_roll":
			return "Wound Roll"
		"save_roll":
			return "Saving Throw"
		"damage_roll":
			return "Damage Roll"
		_:
			return roll_type

func _on_use_pressed() -> void:
	if _choice_made:
		return
	_choice_made = true
	print("CommandRerollDialog: Player %d uses %s on %s (%s)" % [player, "FREE RE-ROLL (%s)" % free_ability_name if free_ability_name != "" else "COMMAND RE-ROLL", unit_name, roll_type])
	emit_signal("command_reroll_used", unit_id, player)
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	if _choice_made:
		return
	_choice_made = true
	print("CommandRerollDialog: Player %d keeps original roll for %s (%s)" % [player, unit_name, roll_type])
	emit_signal("command_reroll_declined", unit_id, player)
	hide()
	queue_free()

func _on_dialog_dismissed() -> void:
	# ✕ button or ESC — treat as "Keep Roll" so the paused phase gets its
	# decision instead of waiting forever (the buttons guard on _choice_made,
	# so a dismiss after a real click is a no-op).
	if _choice_made:
		return
	_choice_made = true
	print("CommandRerollDialog: Player %d dismissed the dialog — keeping original roll for %s (%s)" % [player, unit_name, roll_type])
	emit_signal("command_reroll_declined", unit_id, player)
	queue_free()
