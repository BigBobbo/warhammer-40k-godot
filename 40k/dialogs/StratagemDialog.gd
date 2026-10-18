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

# LIVE-2 / WH-8 / WS-9: the card list used to sit in a fixed 180 px scroll box,
# so Use / variant buttons (HULKING BRUTES' upgrade, the 3rd VINDICTIVE
# ARTILLERISTS option, a second or third card) were below the fold and a player
# could decline without ever seeing them. After layout the box is grown to its
# content (up to the room left under the top HUD) and the first Use button is
# scrolled into view when the list still has to scroll.
const _SCROLL_MIN_H := 180.0
var _strat_scroll: ScrollContainer = null
var _strat_list: VBoxContainer = null
var _fit_armed: bool = false

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
	_arm_card_list_fit()

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
	_arm_card_list_fit()
	print("StratagemDialog: window %s for Player %d — %d offer(s)" % [window_id, player, offers.size()])


## LIVE-10: 11e cards print a paid upgrade inline ("... -1 to wound rolls.
## +1CP Or: Ranged attacks that target your unit have -1 to wound rolls"). Put
## it on its own line and spell it out.
static func format_effect_text(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\s*\\+\\s*(\\d+)\\s*CP\\s+Or:\\s*")
	return re.sub(text, "\n\nUpgrade (+$1 CP) — instead: ", true).strip_edges()

## A variant label without a leading "+1CP:" cost prefix (the button names the
## cost itself).
static func variant_display_label(label: String) -> String:
	var re := RegEx.new()
	re.compile("^\\s*\\+\\s*\\d+\\s*CP\\s*:\\s*")
	var out := re.sub(label, "", false).strip_edges()
	return out if out != "" else label

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
		# Codex: Adeptus Custodes windows (WP-C3, CustodesKatah.gd)
		"fight_phase_start":
			return "The Fight phase is starting"
		"command_phase_main":
			return "Your Command phase"
		# Codex: Adeptus Custodes windows (WP-C5, CustodesCodex11e.gd)
		"phase_end":
			return "The %s phase is ending" % str(window_ctx.get("phase", "")).capitalize()
		"unit_ended_advance_move":
			if u_name != "":
				return "%s has ended an advance move" % u_name
		"unit_selected_to_ingress":
			if u_name != "":
				return "%s has been selected to make an ingress move" % u_name
		"unit_selected_to_pile_in":
			if u_name != "":
				return "%s has been selected to pile in" % u_name
		"unit_selected_to_consolidate":
			if u_name != "":
				return "%s has been selected to consolidate" % u_name
		"enemy_has_fought":
			if enemy_name != "":
				return "%s has fought" % enemy_name
		"charge_phase_start":
			return "Your opponent's Charge phase is starting"
		"charge_phase_end":
			return "Your opponent's Charge phase is ending"
	var when := StratagemManager.window_when_text(window_id)
	return "Stratagem opportunity: %s" % when

## True when the window carries at least one Martial Ka'tah card
## (CustodesKatah.gd offers: kind "katah", no CP cost).
func _window_has_katah() -> bool:
	for offer in window_offers:
		if typeof(offer) == TYPE_DICTIONARY and str(offer.get("kind", "")) == "katah":
			return true
	return false

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
	_strat_scroll = scroll
	_strat_list = strat_container

	main_container.add_child(HSeparator.new())
	# LIVE-9: the defender of an enemy_targets_unit_shooting attack gets the
	# same Examine Board toggle as window mode — "which of my units is being
	# shot, and is it worth the CP?" is a question about the board.
	ReactiveDecisionUI.add_examine_toggle(self, main_container, "Reactive Stratagem")

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
	var ask := "use a stratagem or ka'tah ability?" if _window_has_katah() else "use a stratagem?"
	who.text = "%s — %s   CP Available: %d" % [who_name, ask, StratagemManager.get_player_cp(defending_player)]
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
	_strat_scroll = scroll
	_strat_list = strat_container

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
	# Both modes carry the Examine Board toggle (LIVE-9) — hand wheel notches
	# outside the dialog to the board camera in either.
	ReactiveDecisionUI.forward_camera_wheel(self, event)

# ---------------------------------------------------------------------------
# Card list sizing (LIVE-2 / WH-8 / WS-9)
# ---------------------------------------------------------------------------

func _arm_card_list_fit() -> void:
	if _fit_armed:
		return
	_fit_armed = true
	# Every show (first popup, return from Examine Board) re-fits: the caller's
	# popup_at_bottom resets the window to its base size each time.
	visibility_changed.connect(_on_visibility_for_fit)
	# The autowrap effect labels settle their wrapped height over the first
	# layout passes after the popup — re-fit whenever the list's minimum size
	# moves (resizing the scroll box never changes it, so this cannot loop).
	if is_instance_valid(_strat_list):
		_strat_list.minimum_size_changed.connect(_on_visibility_for_fit)

func _on_visibility_for_fit() -> void:
	if not visible or not is_inside_tree():
		return
	var t := get_tree()
	if t != null and not t.process_frame.is_connected(_fit_card_list):
		# One frame later the autowrap effect labels have wrapped at the card
		# width, so the list's minimum height is its real content height.
		t.process_frame.connect(_fit_card_list, CONNECT_ONE_SHOT)

## Grow the StratScroll box to the card list's content height, capped so the
## whole dialog still fits between the top HUD strip and the bottom clearance,
## then re-pin the dialog to the bottom edge and make sure the first Use button
## is inside the visible part of the list.
func _fit_card_list() -> void:
	if not is_instance_valid(_strat_scroll) or not is_instance_valid(_strat_list) or not visible or not is_inside_tree():
		return
	var vp := Vector2(DialogConstants.LARGE)
	if get_tree() != null and get_tree().root != null:
		vp = get_tree().root.get_visible_rect().size
	var margin_bottom := int(get_meta("wd_bottom_margin", DialogConstants.BOTTOM_CLEARANCE))
	var max_dialog_h: float = minf(vp.y * 0.9, vp.y - DialogConstants.TOP_HUD_CLEARANCE - margin_bottom)
	var list_h: float = _strat_list.get_combined_minimum_size().y + 8.0
	# Everything else in the window (header, Examine Board, Decline buttons,
	# hint, dialog margins) from the CONTENT minimum — the window's own size is
	# still the oversized first-popup size at this point.
	var other_h: float = maxf(0.0, get_contents_minimum_size().y - _strat_scroll.get_combined_minimum_size().y)
	var room: float = maxf(_SCROLL_MIN_H, max_dialog_h - other_h)
	var want: float = clampf(list_h, _SCROLL_MIN_H, room)
	var before: float = _strat_scroll.custom_minimum_size.y
	if absf(want - before) >= 1.0:
		_strat_scroll.custom_minimum_size.y = want
		print("StratagemDialog: card list %.0f px tall (content %.0f, room %.0f) — was %.0f" % [want, list_h, room, before])
		DialogUtils.refit_bottom(self)
	# After the re-pin has laid the dialog out again (refit_bottom re-measures
	# on the next frame), bring the first action button into view if the list
	# still scrolls.
	_reveal_frames_left = 2
	var t := get_tree()
	if t != null and not t.process_frame.is_connected(_reveal_tick):
		t.process_frame.connect(_reveal_tick)

var _reveal_frames_left: int = 0

func _reveal_tick() -> void:
	_reveal_frames_left -= 1
	if _reveal_frames_left > 0 and is_inside_tree():
		return
	var t := get_tree()
	if t != null and t.process_frame.is_connected(_reveal_tick):
		t.process_frame.disconnect(_reveal_tick)
	_reveal_first_use_button()

func _reveal_first_use_button() -> void:
	if not is_instance_valid(_strat_scroll) or not visible or not is_inside_tree():
		return
	var first: Control = first_use_button()
	if first == null:
		return
	if not first_use_button_in_view():
		_strat_scroll.ensure_control_visible(first)
		print("StratagemDialog: scrolled %s into view" % first.name)

## The first Use / variant button of the first card (scenario + fit helper).
func first_use_button() -> Button:
	if not is_instance_valid(_strat_list):
		return null
	for card in _strat_list.get_children():
		var btns = card.get_node_or_null("Buttons")
		if btns == null:
			continue
		for b in btns.get_children():
			if b is Button and b.visible:
				return b
	return null

## True when `button` (default: the first Use button) lies wholly inside the
## visible part of the card list.
func first_use_button_in_view(button: Control = null) -> bool:
	if button == null:
		button = first_use_button()
	if button == null or not is_instance_valid(_strat_scroll):
		return false
	var view := _strat_scroll.get_global_rect()
	var r := button.get_global_rect()
	return r.position.y >= view.position.y - 0.5 and r.end.y <= view.end.y + 0.5

## How many Use / variant buttons are wholly visible without scrolling, and how
## many there are in total — [visible, total] (scenario helper).
func use_buttons_visibility() -> Array:
	var total := 0
	var shown := 0
	if not is_instance_valid(_strat_list):
		return [0, 0]
	for card in _strat_list.get_children():
		var btns = card.get_node_or_null("Buttons")
		if btns == null:
			continue
		for b in btns.get_children():
			if b is Button and b.visible:
				total += 1
				if first_use_button_in_view(b):
					shown += 1
	return [shown, total]

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
	# Codex: Adeptus Custodes ka'tah card (CustodesKatah.gd): free — it costs
	# the unit's readied state, not CP.
	var is_katah: bool = str(offer.get("kind", "")) == "katah"
	var cost_label = Label.new()
	cost_label.name = "Cost"
	cost_label.text = "KA'TAH" if is_katah else "%d CP" % int(offer.get("cp_cost", 1))
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
	desc_label.text = format_effect_text(str(offer.get("effect_text", "")))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 60, 0)
	desc_label.add_theme_font_size_override("font_size", 16)
	card.add_child(desc_label)

	# LIVE-10: options of a variant-only stratagem (VINDICTIVE ARTILLERISTS'
	# three profiles) are a choice, not a target pick.
	var all_variant_only: bool = not offer.get("targets", []).is_empty()
	for t in offer.get("targets", []):
		if not (bool(t.get("require_variant", false)) and not t.get("variants", []).is_empty()):
			all_variant_only = false
	var units_label = Label.new()
	units_label.name = "TargetPrompt"
	units_label.text = "Select target:"
	if all_variant_only:
		var targets: Array = offer.get("targets", [])
		var only_uid := str(targets[0].get("unit_id", "")) if targets.size() == 1 else ""
		units_label.text = ("Choose one (%s):" % GameState.get_unit_display_name(only_uid)) if only_uid != "" else "Choose an option:"
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
		# LIVE-10: when a plain use and a paid upgrade sit side by side (HULKING
		# BRUTES), both buttons name their cost and the upgrade names its unit.
		var has_upgrade: bool = not variant_only and not t.get("variants", []).is_empty()
		if not variant_only:
			var use_button = Button.new()
			use_button.name = "Use_%s_%s" % [safe, uid_part]
			use_button.text = ("Use on %s" % label) if uid != "" else "Use"
			if has_upgrade:
				use_button.text += " (%d CP)" % int(offer.get("cp_cost", 1))
			use_button.custom_minimum_size = Vector2(150, 30)
			use_button.pressed.connect(_on_offer_use_pressed.bind(sid, uid, "", legacy_fold, secondary))
			button_container.add_child(use_button)
		for v in t.get("variants", []):
			var vid := str(v.get("id", ""))
			if vid == "":
				continue
			var vb = Button.new()
			vb.name = "Use_%s_%s_%s" % [safe, uid_part, vid.validate_node_name()]
			var v_cost := int(v.get("cp_cost", offer.get("cp_cost", 1)))
			var v_text := variant_display_label(str(v.get("label", vid)))
			if is_katah:
				# Master of Ka'tahs (CustodesKatah.gd): the label says it all, no CP.
				vb.text = v_text
			elif has_upgrade:
				vb.text = ("Upgrade on %s (%d CP): %s" % [label, v_cost, v_text]) if uid != "" else ("Upgrade (%d CP): %s" % [v_cost, v_text])
			else:
				vb.text = "%s (%d CP)" % [v_text, v_cost]
			vb.tooltip_text = vb.text
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
	ReactiveDecisionUI.stop_examining(self)
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
			# LIVE-10: the "Used ..." log line names the chosen option.
			fold_ctx["variant_label"] = _offer_variant_label(stratagem_id, target_unit_id, variant_id)
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

## Label of a variant offered on (sid, uid) — legacy folded-in offers.
func _offer_variant_label(sid: String, uid: String, vid: String) -> String:
	var offers: Array = window_offers.duplicate()
	for entry in available_stratagems:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("offer"):
			offers.append(entry.offer)
	for offer in offers:
		if str(offer.get("stratagem_id", "")) != sid:
			continue
		for t in offer.get("targets", []):
			if str(t.get("unit_id", "")) != uid:
				continue
			for v in t.get("variants", []):
				if str(v.get("id", "")) == vid:
					return str(v.get("label", vid))
	return vid

## The window was answered elsewhere (AI took the seat over, network mirror
## cleared): close without emitting a decision.
func close_without_answer() -> void:
	_window_answered = true
	ReactiveDecisionUI.stop_examining(self)
	name = "StratagemDialogClosing"
	hide()
	queue_free()

func _on_decline_pressed() -> void:
	print("StratagemDialog: Player %d declined all reactive stratagems" % defending_player)
	ReactiveDecisionUI.stop_examining(self)
	emit_signal("stratagem_declined")
	hide()
	queue_free()

func _on_decline_dont_offer_again_pressed() -> void:
	print("StratagemDialog: Player %d declined all reactive stratagems (don't offer again this phase)" % defending_player)
	ReactiveDecisionUI.stop_examining(self)
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
