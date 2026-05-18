extends AcceptDialog

# ShootingPhaseSummaryDialog - T5-UX9: Shooting summary before ending phase
#
# Shows aggregated total hits / wounds / saves-failed / casualties per
# target unit, plus phase-wide totals, before the player ends the
# Shooting phase. Modeled after DeploymentSummaryDialog (T5-UX8).
#
# Data shape consumed (as produced by ShootingPhase.get_phase_shooting_summary):
#   {
#     "by_target": { tid: { target_unit_name, hits, total_attacks, wounds,
#                           saves_failed, casualties, shooters: [name,...] } },
#     "totals":     { hits, total_attacks, wounds, saves_failed, casualties },
#     "shooters_count": int,
#     "targets_count":  int,
#     "weapon_entries": int,
#     "raw_entries":    Array
#   }

signal shooting_confirmed()
signal shooting_cancelled()

var summary_data: Dictionary = {}

func setup(p_summary_data: Dictionary) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	summary_data = p_summary_data

	title = "Shooting Phase Summary"

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

func _build_ui() -> void:
	min_size = DialogConstants.MEDIUM
	var main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header
	var header = Label.new()
	header.text = "SHOOTING PHASE SUMMARY"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color.GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header)

	main_container.add_child(HSeparator.new())

	var by_target = summary_data.get("by_target", {})
	var totals = summary_data.get("totals", {})
	var shooters_count = int(summary_data.get("shooters_count", 0))
	var targets_count = int(summary_data.get("targets_count", 0))
	var weapon_entries = int(summary_data.get("weapon_entries", 0))

	# Empty-state message: no shots resolved this phase
	if weapon_entries == 0 or targets_count == 0:
		var empty_label = Label.new()
		empty_label.text = "No shooting was resolved this phase."
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(empty_label)
	else:
		# Phase-wide overview line
		var overview = Label.new()
		overview.text = "%d shooter(s) → %d target unit(s)  |  %d weapon resolution(s)" % [
			shooters_count, targets_count, weapon_entries]
		overview.add_theme_font_size_override("font_size", 13)
		overview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(overview)

		var totals_line = Label.new()
		totals_line.text = "Totals: %d hits  |  %d wounds  |  %d failed saves  |  %d casualties" % [
			int(totals.get("hits", 0)),
			int(totals.get("wounds", 0)),
			int(totals.get("saves_failed", 0)),
			int(totals.get("casualties", 0))
		]
		totals_line.add_theme_font_size_override("font_size", 13)
		totals_line.add_theme_color_override("font_color", Color.LIGHT_GRAY)
		totals_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(totals_line)

		main_container.add_child(HSeparator.new())

		# Per-target breakdown header
		var per_target_label = Label.new()
		per_target_label.text = "Per-target breakdown:"
		per_target_label.add_theme_font_size_override("font_size", 14)
		per_target_label.add_theme_color_override("font_color", Color.GOLD)
		main_container.add_child(per_target_label)

		# Scrollable per-target list
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 220)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var content_list = VBoxContainer.new()
		content_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Stable display order: targets with most casualties first, then most wounds, then name
		var ordered_keys = by_target.keys()
		ordered_keys.sort_custom(func(a, b):
			var ba = by_target[a]
			var bb = by_target[b]
			if int(ba.casualties) != int(bb.casualties):
				return int(ba.casualties) > int(bb.casualties)
			if int(ba.wounds) != int(bb.wounds):
				return int(ba.wounds) > int(bb.wounds)
			return String(ba.target_unit_name) < String(bb.target_unit_name)
		)

		for tid in ordered_keys:
			var bucket = by_target[tid]
			var target_name = bucket.get("target_unit_name", tid)
			var hits = int(bucket.get("hits", 0))
			var wounds = int(bucket.get("wounds", 0))
			var saves_failed = int(bucket.get("saves_failed", 0))
			var casualties = int(bucket.get("casualties", 0))
			var shooters = bucket.get("shooters", [])

			# Target header line
			var target_label = Label.new()
			target_label.text = "  %s" % target_name
			target_label.add_theme_font_size_override("font_size", 14)
			target_label.add_theme_color_override("font_color", Color.WHITE)
			content_list.add_child(target_label)

			# Stat line
			var stat_label = Label.new()
			stat_label.text = "    %d hits  |  %d wounds  |  %d failed saves  |  %d casualties" % [
				hits, wounds, saves_failed, casualties]
			stat_label.add_theme_font_size_override("font_size", 12)
			# Color casualty count to draw the eye
			if casualties > 0:
				stat_label.add_theme_color_override("font_color", Color.LIGHT_CORAL)
			elif wounds > 0:
				stat_label.add_theme_color_override("font_color", Color.LIGHT_YELLOW)
			else:
				stat_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
			content_list.add_child(stat_label)

			# Per-weapon breakdown within this target
			var raw_entries = summary_data.get("raw_entries", [])
			var target_weapons: Array = []
			for re in raw_entries:
				if re.get("target_unit_id", "") == tid:
					target_weapons.append(re)
			if target_weapons.size() > 1:
				for tw in target_weapons:
					var tw_name = tw.get("weapon_name", "?")
					var tw_shooter = tw.get("shooter_unit_name", "")
					var tw_hits = int(tw.get("hits", 0))
					var tw_wounds = int(tw.get("wounds", 0))
					var tw_cas = int(tw.get("casualties", 0))
					var tw_text = "      %s" % tw_name
					if tw_shooter != "":
						tw_text += " (%s)" % tw_shooter
					tw_text += ": %dH / %dW / %dK" % [tw_hits, tw_wounds, tw_cas]
					var tw_label = Label.new()
					tw_label.text = tw_text
					tw_label.add_theme_font_size_override("font_size", 11)
					tw_label.add_theme_color_override("font_color", Color.DARK_GRAY)
					content_list.add_child(tw_label)
			elif shooters.size() > 0:
				var shooters_text = "    Shot by: %s" % ", ".join(shooters)
				var shooters_label = Label.new()
				shooters_label.text = shooters_text
				shooters_label.add_theme_font_size_override("font_size", 11)
				shooters_label.add_theme_color_override("font_color", Color.DIM_GRAY)
				content_list.add_child(shooters_label)

		scroll.add_child(content_list)
		main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var cancel_button = Button.new()
	cancel_button.text = "Go Back"
	cancel_button.custom_minimum_size = Vector2(150, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	button_container.add_child(spacer)

	var confirm_button = Button.new()
	confirm_button.text = "End Shooting Phase"
	confirm_button.custom_minimum_size = Vector2(200, 40)
	confirm_button.add_theme_color_override("font_color", Color.GREEN)
	confirm_button.pressed.connect(_on_confirm_pressed)
	button_container.add_child(confirm_button)

	main_container.add_child(button_container)

	add_child(main_container)

func _on_confirm_pressed() -> void:
	print("ShootingPhaseSummaryDialog: Player confirmed ending shooting phase")
	emit_signal("shooting_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	print("ShootingPhaseSummaryDialog: Player cancelled ending shooting phase")
	emit_signal("shooting_cancelled")
	hide()
	queue_free()
