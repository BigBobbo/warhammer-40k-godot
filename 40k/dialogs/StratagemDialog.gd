extends AcceptDialog
class_name StratagemDialog

# StratagemDialog — the ONE dialog for stratagem decision windows.
#
# Two entry points, one button scheme (design .llm/ork_codex_11e_design.md §3.1):
#
#  setup(player, stratagems, targets) — LEGACY opponent-Shooting reactive path
#    (Go to Ground / Smokescreen / faction reactives + the folded-in
#    enemy_targets_unit_shooting window offers). Emits stratagem_selected /
#    stratagem_declined; ShootingController turns those into
#    USE_/DECLINE_REACTIVE_STRATAGEM. Window entries with variants emit
#    stratagem_selected_with_context instead.
#
#  setup_window(player, window_id, offers, ctx) — GENERIC stratagem window
#    opened by BasePhase.open_stratagem_window (stratagem_window_opened). Emits
#    window_stratagem_selected / window_declined; Main turns those into
#    USE_/DECLINE_WINDOW_STRATAGEM. Adds "Don't offer again this phase" and the
#    Examine Board toggle.
#
# Stable node paths for windowed scenarios (sid = stratagem id run through
# validate_node_name(); <uid> = target unit id, "none" for a target-less use):
#   /root/StratagemDialog/Content/StratScroll/StratList/Card_<sid>/Buttons/Use_<sid>_<uid>[_<variant>]
#   /root/StratagemDialog/Content/DeclineButton
#   /root/StratagemDialog/Content/DontOfferAgainButton        (window mode)

signal stratagem_selected(stratagem_id: String, target_unit_id: String)
signal stratagem_selected_with_context(stratagem_id: String, target_unit_id: String, context: Dictionary)
signal stratagem_declined()
# Legacy reactive mode: "Decline — don't offer again this phase" (same meaning
# as the window-mode button; ShootingController sends DECLINE_REACTIVE_STRATAGEM
# with dont_offer_again).
signal stratagem_declined_dont_offer_again()
signal window_stratagem_selected(stratagem_id: String, target_unit_id: String, variant_id: String)
signal window_declined(dont_offer_again: bool)

var available_stratagems: Array = []  # Array of { stratagem: Dictionary, eligible_units: Array[String] [, offer] }
var defending_player: int = 0
var target_unit_ids: Array = []
var selected_stratagem_id: String = ""
var selected_target_unit_id: String = ""

# Window mode
var window_mode: bool = false
var window_id: String = ""
var window_offers: Array = []
var window_ctx: Dictionary = {}
var _window_answered: bool = false

# DEFENDER CONTROL: the old 5-second auto-decline countdown (MA-42) is
# gone — being targeted is a real decision window and the defender keeps it
# until they click Use or Decline. The attacker-side waiting overlay has its
# own stuck-UI safety timer; nothing declines on the defender's behalf.
var _countdown_label: Label = null

func setup(player: int, stratagems: Array, targets: Array) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	defending_player = player
	available_stratagems = stratagems
	target_unit_ids = targets

	title = "Reactive Stratagems - Player %d" % player
	min_size = DialogConstants.MEDIUM

	# Disable default OK button - we use custom buttons
	get_ok_button().visible = false

	_build_ui()

## Generic stratagem window (BasePhase.stratagem_window_opened).
## offers: StratagemManager.get_window_offers format.
func setup_window(player: int, p_window_id: String, offers: Array, ctx: Dictionary) -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	window_mode = true
	defending_player = player
	window_id = p_window_id
	window_offers = offers
	window_ctx = ctx
	title = "Stratagems - Player %d" % player
	min_size = DialogConstants.MEDIUM
	get_ok_button().visible = false
	# Escape / the window ✕ decline (same convention as the Fire Overwatch and
	# Heroic Intervention dialogs) — a hidden-but-pending window would leave the
	# phase waiting on a dialog the player can no longer see.
	close_requested.connect(_on_window_closed_by_player)
	canceled.connect(_on_window_closed_by_player)
	_build_window_ui()
	print("StratagemDialog: window %s for Player %d — %d offer(s)" % [window_id, player, offers.size()])


static func node_safe_id(sid: String) -> String:
	return sid.validate_node_name()


# Best-effort name of the unit whose declared targets opened this reactive
# window. The phase instance replays the attacker's CONFIRM_TARGETS on every
# peer, so active_shooter_id is set on the defender's machine too. Returns ""
# (caller keeps the generic header) when the phase doesn't expose it.
func _attacking_unit_name() -> String:
	var pm = get_node_or_null("/root/PhaseManager")
	if pm == null or not pm.has_method("get_current_phase_instance"):
		return ""
	var phase = pm.get_current_phase_instance()
	if phase == null or not ("active_shooter_id" in phase):
		return ""
	var shooter_id = str(phase.active_shooter_id)
	if shooter_id == "":
		return ""
	return GameState.get_unit_display_name(shooter_id)

## Header line for a window, naming the unit(s) involved where ctx has them.
func _window_header_text() -> String:
	var uid := str(window_ctx.get("unit_id", ""))
	var u_name := GameState.get_unit_display_name(uid) if uid != "" else ""
	var enemy_id := str(window_ctx.get("attacker_unit_id", window_ctx.get("enemy_unit_id", "")))
	var enemy_name := GameState.get_unit_display_name(enemy_id) if enemy_id != "" else ""
	match window_id:
		"unit_selected_to_fight":
			if u_name != "":
				return "%s has been selected to fight" % u_name
		"unit_selected_to_shoot":
			if u_name != "":
				return "%s has been selected to shoot" % u_name
		"unit_selected_to_move":
			if u_name != "":
				return "%s has been selected to move" % u_name
		"unit_has_shot":
			if u_name != "":
				return "%s has shot" % u_name
		"enemy_targets_unit_shooting":
			if enemy_name != "":
				return "Your units are being targeted by %s!" % enemy_name
			return "Your units are being targeted!"
		"enemy_targets_unit_fight":
			if enemy_name != "":
				return "%s is attacking your units in melee!" % enemy_name
		"enemy_has_shot":
			if enemy_name != "":
				return "%s has shot at your units" % enemy_name
		"enemy_ended_move":
			if enemy_name != "":
				return "%s has ended a move" % enemy_name
		"enemy_selected_to_fall_back":
			if enemy_name != "":
				return "%s has been selected to fall back" % enemy_name
		"unit_ended_normal_move":
			if u_name != "":
				return "%s has ended a normal move" % u_name
		"unit_destroyed":
			if u_name != "":
				return "%s has been destroyed" % u_name
		"unit_battle_shocked":
			if u_name != "":
				return "%s has become battle-shocked" % u_name
		"battle_shock_step_start":
			return "Your Battle-shock step is starting"
		"unit_declares_charge":
			if u_name != "":
				return "%s has declared a charge" % u_name
		"unit_ended_charge_move":
			if u_name != "":
				return "%s has ended a charge move" % u_name
		"enemy_unit_has_attacked":
			if enemy_name != "":
				return "%s has finished its attacks" % enemy_name
	var when := StratagemManager.window_when_text(window_id)
	return "Stratagem opportunity: %s" % when

func _build_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	# Header — name the attacking unit when the live shooting phase exposes
	# it ("being targeted" alone never says by WHOM).
	var header = Label.new()
	header.name = "Header"
	var attacker_name = _attacking_unit_name()
	if attacker_name != "":
		header.text = "Your units are being targeted by %s!" % attacker_name
	else:
		header.text = "Your units are being targeted!"
	header.add_theme_font_size_override("font_size", 21)
	header.add_theme_color_override("font_color", Color.YELLOW)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(header)

	var cp_label = Label.new()
	cp_label.name = "CPLabel"
	cp_label.text = "CP Available: %d" % StratagemManager.get_player_cp(defending_player)
	cp_label.add_theme_font_size_override("font_size", 18)
	cp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(cp_label)

	main_container.add_child(HSeparator.new())

	# Scroll container for stratagem cards (stable names so windowed
	# scenarios can click the same affordances a player sees)
	var scroll = ScrollContainer.new()
	scroll.name = "StratScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 180)

	var strat_container = VBoxContainer.new()
	strat_container.name = "StratList"

	for entry in available_stratagems:
		var strat = entry.stratagem
		var card: VBoxContainer
		if entry.has("offer"):
			# Folded-in window offer: same card/button scheme as window mode,
			# variants included.
			card = _create_offer_card(entry.offer, true)
		else:
			card = _create_stratagem_card(strat, entry.eligible_units)
		strat_container.add_child(card)
		strat_container.add_child(HSeparator.new())

	scroll.add_child(strat_container)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())

	# Decline button
	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline All Stratagems"
	decline_button.custom_minimum_size = Vector2(480, 35)
	decline_button.pressed.connect(_on_decline_pressed)
	main_container.add_child(decline_button)

	# Same affordance as window mode: skip the defender prompt for the rest of
	# the phase (enemy_targets_unit_shooting suppression).
	var dont_again = Button.new()
	dont_again.name = "DontOfferAgainButton"
	dont_again.text = "Decline — don't offer again this phase"
	dont_again.tooltip_text = "Skip this kind of stratagem prompt for the rest of the phase."
	dont_again.custom_minimum_size = Vector2(480, 35)
	dont_again.pressed.connect(_on_decline_dont_offer_again_pressed)
	main_container.add_child(dont_again)

	# Defender-control hint: the window stays open until the defender acts.
	_countdown_label = Label.new()
	_countdown_label.name = "WindowHint"
	_countdown_label.text = "Your opponent is waiting on your decision."
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 17)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	main_container.add_child(_countdown_label)

	add_child(main_container)

func _build_window_ui() -> void:
	var main_container = VBoxContainer.new()
	main_container.name = "Content"
	main_container.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)

	var header = Label.new()
	header.name = "Header"
	header.text = _window_header_text()
	header.add_theme_font_size_override("font_size", 21)
	header.add_theme_color_override("font_color", Color.YELLOW)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(header)

	var who = Label.new()
	who.name = "Decider"
	var who_name := "Player %d" % defending_player
	var display := str(GameState.get_player_display_name(defending_player))
	if display != "" and display != who_name:
		who_name = "%s (Player %d)" % [display, defending_player]
	who.text = "%s — use a stratagem?   CP Available: %d" % [who_name, StratagemManager.get_player_cp(defending_player)]
	who.add_theme_font_size_override("font_size", 18)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(who)

	main_container.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.name = "StratScroll"
	scroll.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 180)
	var strat_container = VBoxContainer.new()
	strat_container.name = "StratList"
	strat_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for offer in window_offers:
		strat_container.add_child(_create_offer_card(offer, false))
		strat_container.add_child(HSeparator.new())
	scroll.add_child(strat_container)
	main_container.add_child(scroll)

	main_container.add_child(HSeparator.new())
	ReactiveDecisionUI.add_examine_toggle(self, main_container, "Stratagem")

	var decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(480, 35)
	decline_button.pressed.connect(_on_window_decline_pressed.bind(false))
	main_container.add_child(decline_button)

	var dont_again = Button.new()
	dont_again.name = "DontOfferAgainButton"
	dont_again.text = "Decline — don't offer again this phase"
	dont_again.tooltip_text = "Skip this kind of stratagem prompt for the rest of the phase."
	dont_again.custom_minimum_size = Vector2(480, 35)
	dont_again.pressed.connect(_on_window_decline_pressed.bind(true))
	main_container.add_child(dont_again)

	_countdown_label = ReactiveDecisionUI.window_hint_label("This window waits for you — nothing is declined automatically.")
	main_container.add_child(_countdown_label)

	add_child(main_container)

func _input(event: InputEvent) -> void:
	if window_mode:
		ReactiveDecisionUI.forward_camera_wheel(self, event)

## Card for a window offer ({stratagem_id, name, cp_cost, effect_text, type, targets}).
## legacy_fold: true when rendered inside the legacy shooting reactive dialog.
func _create_offer_card(offer: Dictionary, legacy_fold: bool) -> VBoxContainer:
	var sid := str(offer.get("stratagem_id", "unknown"))
	var safe := node_safe_id(sid)
	var card = VBoxContainer.new()
	card.name = "Card_%s" % safe

	var name_hbox = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = str(offer.get("name", sid))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.CYAN)
	name_hbox.add_child(name_label)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(spacer)
	var cost_label = Label.new()
	cost_label.text = "%d CP" % int(offer.get("cp_cost", 1))
	cost_label.add_theme_font_size_override("font_size", 20)
	cost_label.add_theme_color_override("font_color", Color.GOLD)
	name_hbox.add_child(cost_label)
	card.add_child(name_hbox)

	var type_label = Label.new()
	type_label.text = str(offer.get("type", ""))
	type_label.add_theme_font_size_override("font_size", 16)
	type_label.add_theme_color_override("font_color", Color.GRAY)
	card.add_child(type_label)

	var desc_label = Label.new()
	desc_label.name = "Effect"
	desc_label.text = str(offer.get("effect_text", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 60, 0)
	desc_label.add_theme_font_size_override("font_size", 16)
	card.add_child(desc_label)

	var units_label = Label.new()
	units_label.text = "Select target:"
	# Variant-only offers (e.g. VINDICTIVE ARTILLERISTS) list options, not
	# targets (r3:F8).
	var all_variant_only: bool = not offer.get("targets", []).is_empty()
	for vt in offer.get("targets", []):
		if not (bool(vt.get("require_variant", false)) and not vt.get("variants", []).is_empty()):
			all_variant_only = false
	if all_variant_only:
		units_label.text = "Choose an option:"
	units_label.add_theme_font_size_override("font_size", 16)
	units_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	card.add_child(units_label)

	var button_container = HFlowContainer.new()
	button_container.name = "Buttons"
	for t in offer.get("targets", []):
		var uid := str(t.get("unit_id", ""))
		var uid_part := uid if uid != "" else "none"
		var label := str(t.get("label", GameState.get_unit_display_name(uid) if uid != "" else "Use"))
		# A secondary pick (second unit / objective, e.g. GROT SHIELDS' shielded
		# unit) rides along so the legacy (folded-in) mode can ask for it too —
		# window mode asks in Main from the offer itself.
		var secondary = t.get("secondary", {})
		if typeof(secondary) != TYPE_DICTIONARY:
			secondary = {}
		# require_variant: the stratagem has no plain use — the player must pick
		# one of its variants (e.g. VINDICTIVE ARTILLERISTS' three options).
		var variant_only: bool = bool(t.get("require_variant", false)) and not t.get("variants", []).is_empty()
		if not variant_only:
			var use_button = Button.new()
			use_button.name = "Use_%s_%s" % [safe, uid_part]
			use_button.text = ("Use on %s" % label) if uid != "" else "Use"
			use_button.custom_minimum_size = Vector2(150, 30)
			use_button.pressed.connect(_on_offer_use_pressed.bind(sid, uid, "", legacy_fold, secondary))
			button_container.add_child(use_button)
		for v in t.get("variants", []):
			var vid := str(v.get("id", ""))
			if vid == "":
				continue
			var vb = Button.new()
			vb.name = "Use_%s_%s_%s" % [safe, uid_part, vid.validate_node_name()]
			vb.text = "%s (%d CP)" % [str(v.get("label", vid)), int(v.get("cp_cost", offer.get("cp_cost", 1)))]
			vb.custom_minimum_size = Vector2(150, 30)
			vb.pressed.connect(_on_offer_use_pressed.bind(sid, uid, vid, legacy_fold, secondary))
			button_container.add_child(vb)
	card.add_child(button_container)
	return card

func _create_stratagem_card(strat: Dictionary, eligible_units: Array) -> VBoxContainer:
	var card = VBoxContainer.new()
	card.name = "Card_%s" % node_safe_id(str(strat.get("id", "unknown")))

	# Stratagem name and cost
	var name_hbox = HBoxContainer.new()

	var name_label = Label.new()
	name_label.text = strat.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.CYAN)
	name_hbox.add_child(name_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(spacer)

	var cost_label = Label.new()
	cost_label.text = "%d CP" % strat.get("cp_cost", 0)
	cost_label.add_theme_font_size_override("font_size", 20)
	cost_label.add_theme_color_override("font_color", Color.GOLD)
	name_hbox.add_child(cost_label)

	card.add_child(name_hbox)

	# Type
	var type_label = Label.new()
	type_label.text = strat.get("type", "")
	type_label.add_theme_font_size_override("font_size", 16)
	type_label.add_theme_color_override("font_color", Color.GRAY)
	card.add_child(type_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = strat.get("effect_text", strat.get("description", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 16)
	card.add_child(desc_label)

	# Eligible unit buttons
	var units_label = Label.new()
	units_label.text = "Select target:"
	units_label.add_theme_font_size_override("font_size", 16)
	units_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	card.add_child(units_label)

	var button_container = HBoxContainer.new()
	button_container.name = "Buttons"
	for unit_id in eligible_units:
		var unit = GameState.get_unit(unit_id)
		var _sd_meta = unit.get("meta", {})
		var unit_name = _sd_meta.get("display_name", _sd_meta.get("name", unit_id))

		var use_button = Button.new()
		use_button.name = "Use_%s_%s" % [node_safe_id(str(strat.get("id", "unknown"))), unit_id]
		use_button.text = "Use on %s" % unit_name
		use_button.custom_minimum_size = Vector2(150, 30)
		use_button.pressed.connect(_on_use_pressed.bind(strat.get("id", ""), unit_id))
		button_container.add_child(use_button)

	card.add_child(button_container)

	return card

func _on_use_pressed(stratagem_id: String, target_unit_id: String) -> void:
	selected_stratagem_id = stratagem_id
	selected_target_unit_id = target_unit_id
	print("StratagemDialog: Player %d selected %s on %s" % [defending_player, stratagem_id, target_unit_id])
	# Free the node path + exclusive slot first: a use that leaves another
	# reactive stratagem usable re-opens the dialog from inside this signal.
	name = "StratagemDialogClosing"
	hide()
	emit_signal("stratagem_selected", stratagem_id, target_unit_id)
	queue_free()

func _on_window_closed_by_player() -> void:
	if _window_answered or ReactiveDecisionUI.is_examining(self):
		return
	print("StratagemDialog: window %s closed by Player %d (Escape / ✕) — declining" % [window_id, defending_player])
	_on_window_decline_pressed(false)

func _on_offer_use_pressed(stratagem_id: String, target_unit_id: String, variant_id: String, legacy_fold: bool, secondary: Dictionary = {}) -> void:
	if _window_answered:
		return
	if window_mode:
		_window_answered = true
	selected_stratagem_id = stratagem_id
	selected_target_unit_id = target_unit_id
	print("StratagemDialog: Player %d selected %s on %s%s (%s)" % [
		defending_player, stratagem_id, target_unit_id,
		(" variant " + variant_id) if variant_id != "" else "", window_id if window_mode else "reactive"])
	ReactiveDecisionUI.stop_examining(self)
	# Release the stable node path AND the exclusive-window slot BEFORE
	# emitting: the handlers open the follow-up dialog synchronously (secondary
	# pick, the re-opened reactive dialog when another stratagem is still
	# usable, or the next queued window).
	name = "StratagemDialogClosing"
	hide()
	if legacy_fold:
		var fold_ctx := {}
		if variant_id != "":
			fold_ctx["variant_id"] = variant_id
		if not secondary.get("options", []).is_empty():
			# ShootingController asks for the secondary pick, then sends the
			# USE_REACTIVE_STRATAGEM with context.secondary_id.
			fold_ctx["_secondary"] = secondary
		if not fold_ctx.is_empty():
			emit_signal("stratagem_selected_with_context", stratagem_id, target_unit_id, fold_ctx)
		else:
			emit_signal("stratagem_selected", stratagem_id, target_unit_id)
	else:
		emit_signal("window_stratagem_selected", stratagem_id, target_unit_id, variant_id)
	queue_free()

func _on_decline_pressed() -> void:
	print("StratagemDialog: Player %d declined all reactive stratagems" % defending_player)
	emit_signal("stratagem_declined")
	hide()
	queue_free()

func _on_decline_dont_offer_again_pressed() -> void:
	print("StratagemDialog: Player %d declined all reactive stratagems (don't offer again this phase)" % defending_player)
	emit_signal("stratagem_declined_dont_offer_again")
	name = "StratagemDialogClosing"
	hide()
	queue_free()

func _on_window_decline_pressed(dont_offer_again: bool) -> void:
	if _window_answered:
		return
	_window_answered = true
	print("StratagemDialog: Player %d declined window %s%s" % [defending_player, window_id,
		" (don't offer again this phase)" if dont_offer_again else ""])
	ReactiveDecisionUI.stop_examining(self)
	emit_signal("window_declined", dont_offer_again)
	name = "StratagemDialogClosing"
	hide()
	queue_free()
