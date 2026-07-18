extends Control
class_name AllocationGroupOverlay

const _WhiteDwarfTheme = preload("res://scripts/WhiteDwarfTheme.gd")
# Shared d6 face textures (rounded square + pips) — the same dice visuals the
# game log and the other dice UIs use, so save rolls render as icons, not raw
# numbers. Safe to preload: DiceFaceIcons is a RefCounted with static methods and
# references no autoloads, so this overlay still compiles standalone headless.
const _DiceFaceIcons = preload("res://scripts/DiceFaceIcons.gd")
# Runtime-loaded (NOT preload): WoundAllocationBoardHighlights references the
# Measurement autoload at compile time, and this overlay must keep compiling
# standalone in bare headless harness runs (no autoloads).
const _BOARD_HIGHLIGHTS_PATH := "res://scripts/WoundAllocationBoardHighlights.gd"
const _ATTACK_CONTEXT_PATH := "res://scripts/AttackContextVisual.gd"

# The overlay's decision panel is a horizontal command bar along the BOTTOM
# of the screen (above the phase breadcrumb), so neither the battlefield nor
# the right-HUD shooting controls are covered while the defender decides.
const _BAR_MIN_WIDTH := 880.0      # clears the game-log (left) and HUD_Right at 1920px
const _BAR_BAND_HEIGHT := 300.0    # band the bar vertically centers within
const _BOTTOM_CLEARANCE := 48.0    # keeps the phase breadcrumb strip visible

## ISS-045 — the 11e defender allocation UI (core rules 05.03-05.04).
## Replaces WoundAllocationOverlay's per-wound click loop at edition ≥ 11:
## the defender divides the target into allocation groups ONCE per attack
## batch, orders them under the 05.03 constraints (validated live), then
## rolls the save batch and applies damage lowest→highest via
## RulesEngine.resolve_allocation_batch_11e.
##
## DEFENDER CONTROL (2026-07): the flow is now fully defender-driven —
##  1. ORDER  — the defender orders the groups and CLICKS "Roll Saves"
##              (no more instant auto-resolve for single-group units).
##  2. REROLL — if the defender can pay Command Re-roll (1 CP, once per
##              phase) and at least one save failed, they may re-roll ONE
##              save die before damage is applied.
##  3. PICK   — when casualties occur and the group has more models than
##              casualties, the defender clicks the bases to remove on the
##              board (wounded models are locked in per 05.04).
##  4. RESULTS — summary + Done.
## The legacy instant resolve is kept as `auto_mode` for AI defenders and
## for players who enable the "Computer allocates wounds" setting
## (single-player/hotseat only — a networked defender always gets control).
##
## Contract mirrors WoundAllocationOverlay: instantiate, add to tree,
## `setup(save_data, defender_player)`, listen for
## `allocation_complete(summary)`. The overlay applies the outcome to
## GameState directly (single source of dice on the defending peer); the
## summary carries the same idempotent `set` diffs for the APPLY_SAVES
## action path.

signal allocation_complete(summary: Dictionary)

var save_data: Dictionary = {}
var defender_player: int = 0
var groups: Array = []
var order: Array = []  # group ids in the defender's chosen order
var batch_result: Dictionary = {}
var resolved: bool = false
var auto_mode: bool = false

# Two-step dice state: rolls are drawn once, then every engine run replays
# them via forced_save_rolls so the re-roll and casualty-pick re-runs are
# deterministic (same damage/FNP stream — see resolve_allocation_batch_11e).
var _current_rolls: Array = []
var _batch_seed: int = -1
var _command_reroll: Dictionary = {}  # {used, player, die_index, original, new}
# Count of d6 face icons mounted into the results label — lets windowed
# scenarios assert the save rolls rendered as dice icons (not raw numbers).
var _result_dice_icon_count: int = 0

# Casualty pick state (virtual model indices from batch_result.groups/sources)
var _pick_required: Dictionary = {}   # group_id -> casualties in that group
var _pick_locked: Dictionary = {}     # group_id -> [virtual idx] (wounded, forced)
var _pick_selected: Dictionary = {}   # group_id -> [virtual idx] (defender picks)
var _pick_candidates: Array = []      # all clickable virtual indices
var _picking: bool = false
var board_highlighter = null
# Board-space "attacker → target" context (rings + arrow) shown while the
# defender decides; target marks come from the combined allocation unit so
# attached characters are outlined too.
var attack_context_visual = null
var _virtual_target_unit: Dictionary = {}

# Lazy autoload lookups (autoload ids are not compile-time resolvable in
# bare `godot -s` runs).
func _rules() -> Node:
	return get_node("/root/RulesEngine")


func _game_state() -> Node:
	return get_node("/root/GameState")


func _measurement() -> Node:
	return get_node_or_null("/root/Measurement")


var dim: ColorRect = null
var center: CenterContainer = null
var panel: PanelContainer = null
var order_label: Label = null
var group_list: VBoxContainer = null
var error_label: Label = null
var confirm_button: Button = null
var result_panel: VBoxContainer = null
var result_label: RichTextLabel = null
var done_button: Button = null

# REROLL step nodes
var reroll_panel: VBoxContainer = null
var dice_chips: HFlowContainer = null
var keep_rolls_button: Button = null

# PICK step nodes (own top-anchored panel so the board stays visible)
var pick_panel: PanelContainer = null
var pick_label: Label = null
var pick_counter: Label = null
var confirm_removal_button: Button = null
var auto_pick_button: Button = null


# 24.28 [PRECISION] (audit #13): the ATTACKER's promotion pick — an
# OptionButton listing the visibility-gated eligible CHARACTER groups.
var precision_picker: OptionButton = null
var _precision_eligible: Array = []

func setup(p_save_data: Dictionary, p_defender_player: int) -> void:
	save_data = p_save_data
	defender_player = p_defender_player
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	_virtual_target_unit = _rules()._build_attached_allocation_unit_11e(target_unit_id, _game_state().state).unit
	groups = Allocation.build_groups(_virtual_target_unit)
	order = Allocation.default_order(groups)
	auto_mode = _compute_auto_mode()
	_build_ui()
	_rebuild_group_list()
	print("AllocationGroupOverlay: setup — %d group(s), %d wound(s) to save vs %s (auto_mode=%s)" % [
		groups.size(), int(save_data.get("wounds_to_save", 0)), target_unit_id, str(auto_mode)])
	if auto_mode:
		# Legacy fast path: the computer orders, rolls and allocates in one
		# step (AI defender, or the auto-allocate setting in local play).
		print("AllocationGroupOverlay: auto_mode — resolving without defender interaction")
		_on_confirm_pressed()
		return
	if groups.size() <= 1:
		# 05.03: with a single group there is no order decision — but the
		# DEFENDER still rolls their own saves (no instant auto-resolve).
		confirm_button.text = "Roll Saves"
	# Board context for the human defender: outline the attacking unit (red)
	# and the combined target unit (gold) and link them with an attack arrow,
	# so WHO is attacking WHOM stays visible on the battlefield itself.
	_setup_attack_context_visual()


# Auto (no-interaction) mode applies when the defender cannot interact:
# an AI defender in local play, or the player opted into computer
# allocation. A networked human defender ALWAYS gets the interactive flow.
func _compute_auto_mode() -> bool:
	var root = Engine.get_main_loop().root
	var nm = root.get_node_or_null("NetworkManager")
	var networked: bool = nm != null and nm.has_method("is_networked") and nm.is_networked()
	var ai = root.get_node_or_null("AIPlayer")
	if not networked and ai != null and ai.has_method("is_ai_player") and ai.is_ai_player(defender_player):
		return true
	if networked:
		return false
	var ss = root.get_node_or_null("SettingsService")
	return ss != null and ss.has_method("get_auto_allocate_wounds") and ss.get_auto_allocate_wounds()


# ── Attacker context (who is attacking whom) ──────────────────────────

func _attacker_display_name() -> String:
	var attacker_id = str(save_data.get("shooter_unit_id", ""))
	if attacker_id == "":
		return ""
	var gs = _game_state()
	if gs != null and gs.has_method("get_unit_display_name"):
		var display = str(gs.get_unit_display_name(attacker_id))
		if display != "":
			return display
	return attacker_id


func _attacker_context_text() -> String:
	var attacker_name = _attacker_display_name()
	if attacker_name == "":
		attacker_name = "Unknown attacker"
	if save_data.get("is_melee", false):
		return "Struck in melee by %s" % attacker_name
	return "Shot by %s" % attacker_name


# Alive-model board marks ([{pos, radius_px}]) for the units involved. The
# target uses the combined allocation unit so attached characters are
# outlined with their bodyguard.
func _marks_from_models(models: Array) -> Array:
	var marks: Array = []
	var meas = _measurement()
	for m in models:
		if not m.get("alive", true):
			continue
		var pos = m.get("position")
		var v := Vector2.ZERO
		if pos is Dictionary:
			v = Vector2(pos.get("x", 0), pos.get("y", 0))
		elif pos is Vector2:
			v = pos
		else:
			continue
		var base_mm = float(m.get("base_mm", 32))
		var radius_px: float = meas.base_radius_px(base_mm) if meas != null else base_mm
		marks.append({"pos": v, "radius_px": radius_px})
	return marks


func _setup_attack_context_visual() -> void:
	var refs = Engine.get_main_loop().root.get_node_or_null("SceneRefs")
	var board_view = refs.board_view() if refs != null else null
	if board_view == null:
		print("AllocationGroupOverlay: no board_view — skipping attack context visual (headless)")
		return
	var context_script = load(_ATTACK_CONTEXT_PATH)
	if context_script == null:
		print("AllocationGroupOverlay: WARNING — attack context script unavailable")
		return
	var attacker_unit = _game_state().state.get("units", {}).get(str(save_data.get("shooter_unit_id", "")), {})
	var attacker_marks = _marks_from_models(attacker_unit.get("models", []))
	var target_marks = _marks_from_models(_virtual_target_unit.get("models", []))
	if attacker_marks.is_empty() and target_marks.is_empty():
		print("AllocationGroupOverlay: no attacker/target marks — skipping attack context visual")
		return
	attack_context_visual = context_script.new()
	attack_context_visual.name = "AttackContextVisual"
	attack_context_visual.z_index = 850  # under the casualty-pick highlights (900)
	board_view.add_child(attack_context_visual)
	attack_context_visual.setup(attacker_marks, target_marks, bool(save_data.get("is_melee", false)))
	print("AllocationGroupOverlay: attack context visual up — %d attacker / %d target model(s)" % [
		attacker_marks.size(), target_marks.size()])


func _build_ui() -> void:
	name = "AllocationGroupOverlay"
	# Parent is Main (a CanvasLayer): anchors AND offsets must be applied
	# for the rect to fill the viewport (set_anchors_preset alone leaves
	# the size at 0x0).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 2000  # above the phase banner / HUD (UI_MODAL_Z)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# UI-CONSISTENCY: share the White Dwarf chrome with WeaponOrderDialog and
	# the other shooting dialogs. The theme cascades to every Button / Label /
	# OptionButton descendant (including the reorder rows rebuilt later), so the
	# wound-allocation window reads as the same UI as the weapon-order window.
	_WhiteDwarfTheme.apply_to_control_theme(self)

	# BOARD-VISIBLE REDESIGN (2026-07): no full-screen dim any more — the
	# defender must be able to SEE the battlefield (and the attacker/target
	# context drawn on it) while deciding. The Dim node is kept (hidden) so
	# the existing pick-step visibility toggles stay no-ops rather than
	# null-refs, and the full-rect root still swallows stray clicks.
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)

	# BOTTOM COMMAND BAR: full-width band above the phase breadcrumb; the
	# CenterContainer centers the bar horizontally (and within the band
	# vertically), leaving board AND right-HUD controls uncovered.
	# Node stays named "Center" so scenario paths Center/Panel/... survive.
	center = CenterContainer.new()
	center.name = "Center"
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 0
	center.offset_right = 0
	center.offset_top = -_BAR_BAND_HEIGHT
	center.offset_bottom = -_BOTTOM_CLEARANCE
	center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(center)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(_BAR_MIN_WIDTH, 0)
	# Gothic gold-bordered parchment-dark panel + inner padding. Content margins
	# live on the stylebox (not a wrapper node) so the scenario node paths
	# Panel/Row/... stay intact.
	var panel_style = _WhiteDwarfTheme.create_panel_style()
	panel_style.bg_color = Color(0.1, 0.09, 0.07, 0.97)
	panel_style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	# Two columns: WHO/WHAT on the left, the decision (order rows, dice,
	# results + primary button) on the right — a wide, low bar instead of a
	# tall stack, so it reads as a command bar, not a dialog.
	var row = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var context_col = VBoxContainer.new()
	context_col.name = "ContextCol"
	context_col.custom_minimum_size = Vector2(300, 0)
	context_col.add_theme_constant_override("separation", 6)
	row.add_child(context_col)

	var title = Label.new()
	title.name = "Title"
	title.text = "Allocate Attacks — %s" % str(save_data.get("target_unit_name", save_data.get("target_unit_id", "")))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_col.add_child(title)

	# WHO is attacking — the one fact the old dialog never showed. Red like
	# the attacker's board outline so text and battlefield read as one.
	var attacker_line = Label.new()
	attacker_line.name = "AttackerInfo"
	attacker_line.text = _attacker_context_text()
	attacker_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attacker_line.add_theme_font_size_override("font_size", 15)
	attacker_line.add_theme_color_override("font_color", Color(1.0, 0.42, 0.35))
	context_col.add_child(attacker_line)

	var info = Label.new()
	info.name = "Info"
	var dev_txt = ""
	if save_data.get("has_devastating_wounds", false) and int(save_data.get("devastating_wounds", 0)) > 0:
		dev_txt = " + %d devastating" % int(save_data.get("devastating_wounds", 0))
	info.text = "%s: %d wound(s) to save%s   AP %d   D %s" % [
		str(save_data.get("weapon_name", "Attack")),
		int(save_data.get("wounds_to_save", 0)), dev_txt,
		int(save_data.get("ap", 0)),
		str(save_data.get("damage_raw", save_data.get("damage", 1)))]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_col.add_child(info)

	var hint = Label.new()
	hint.name = "Hint"
	hint.text = "Declare the allocation order (05.03). Damage is applied lowest save roll → highest against the current group."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	context_col.add_child(hint)

	# Thin gold rule between the two columns (vertical sibling of the theme's
	# horizontal gold separators).
	var gold_rule = ColorRect.new()
	gold_rule.name = "GoldRule"
	gold_rule.custom_minimum_size = Vector2(2, 0)
	gold_rule.color = Color(_WhiteDwarfTheme.WH_GOLD, 0.55)
	row.add_child(gold_rule)

	var decision_col = VBoxContainer.new()
	decision_col.name = "DecisionCol"
	decision_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decision_col.add_theme_constant_override("separation", 6)
	row.add_child(decision_col)

	# 24.28 [PRECISION]: attacker's promotion choice (visibility-gated).
	_precision_eligible = _rules().precision_eligible_groups_11e(save_data, _game_state().state)
	if not _precision_eligible.is_empty():
		var prec_label = Label.new()
		prec_label.name = "PrecisionLabel"
		prec_label.text = "PRECISION (24.28) — attacker may make a visible CHARACTER group the current allocation group:"
		prec_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prec_label.add_theme_font_size_override("font_size", 13)
		prec_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		decision_col.add_child(prec_label)
		precision_picker = OptionButton.new()
		precision_picker.name = "PrecisionPicker"
		precision_picker.add_item("No promotion", 0)
		for gi in range(_precision_eligible.size()):
			precision_picker.add_item("Promote %s" % str(_precision_eligible[gi].label), gi + 1)
		precision_picker.selected = 1  # default: promote the first eligible group
		decision_col.add_child(precision_picker)

	# Section label so the ordered rows read as "FIRING ORDER" does in the
	# weapon-order window.
	order_label = Label.new()
	order_label.name = "OrderLabel"
	order_label.text = "ALLOCATION ORDER"
	order_label.add_theme_font_size_override("font_size", 13)
	order_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	decision_col.add_child(order_label)

	group_list = VBoxContainer.new()
	group_list.name = "GroupList"
	group_list.add_theme_constant_override("separation", 4)
	decision_col.add_child(group_list)

	error_label = Label.new()
	error_label.name = "ErrorLabel"
	error_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_RED)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.text = ""
	decision_col.add_child(error_label)

	confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "Confirm Order & Roll Saves"
	confirm_button.custom_minimum_size = Vector2(0, 42)
	confirm_button.pressed.connect(_on_confirm_pressed)
	_WhiteDwarfTheme.apply_primary_button(confirm_button)
	decision_col.add_child(confirm_button)

	# ── REROLL step (hidden until the saves are rolled) ────────────────
	reroll_panel = VBoxContainer.new()
	reroll_panel.name = "RerollPanel"
	reroll_panel.add_theme_constant_override("separation", 8)
	reroll_panel.visible = false
	decision_col.add_child(reroll_panel)

	var reroll_title = Label.new()
	reroll_title.name = "RerollTitle"
	reroll_title.text = "SAVE ROLLS"
	reroll_title.add_theme_font_size_override("font_size", 13)
	reroll_title.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	reroll_panel.add_child(reroll_title)

	dice_chips = HFlowContainer.new()
	dice_chips.name = "DiceChips"
	reroll_panel.add_child(dice_chips)

	var reroll_hint = Label.new()
	reroll_hint.name = "RerollHint"
	reroll_hint.text = "COMMAND RE-ROLL (1 CP): click a failed save die to re-roll it, or keep the rolls."
	reroll_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reroll_hint.add_theme_font_size_override("font_size", 13)
	reroll_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	reroll_panel.add_child(reroll_hint)

	keep_rolls_button = Button.new()
	keep_rolls_button.name = "KeepRollsButton"
	keep_rolls_button.text = "Keep Rolls"
	keep_rolls_button.custom_minimum_size = Vector2(0, 42)
	keep_rolls_button.pressed.connect(_on_keep_rolls_pressed)
	_WhiteDwarfTheme.apply_primary_button(keep_rolls_button)
	reroll_panel.add_child(keep_rolls_button)

	result_panel = VBoxContainer.new()
	result_panel.name = "ResultPanel"
	result_panel.add_theme_constant_override("separation", 8)
	result_panel.visible = false
	decision_col.add_child(result_panel)

	result_label = RichTextLabel.new()
	result_label.name = "ResultLabel"
	# bbcode + inline images: the save rolls render as d6 face icons via add_image.
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.custom_minimum_size = Vector2(520, 0)
	result_label.add_theme_color_override("default_color", _WhiteDwarfTheme.WH_PARCHMENT)
	result_panel.add_child(result_label)

	done_button = Button.new()
	done_button.name = "DoneButton"
	done_button.text = "Done"
	done_button.custom_minimum_size = Vector2(0, 42)
	done_button.pressed.connect(_on_done_pressed)
	_WhiteDwarfTheme.apply_primary_button(done_button)
	result_panel.add_child(done_button)

	# ── PICK step: compact banner in the same bottom slot as the order
	# bar, so the whole board is visible and clickable while the defender
	# chooses casualties. ───────────────────────────────────────────────
	pick_panel = PanelContainer.new()
	pick_panel.name = "PickPanel"
	pick_panel.visible = false
	pick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pick_style = _WhiteDwarfTheme.create_panel_style()
	pick_style.bg_color = Color(0.1, 0.09, 0.07, 0.97)
	pick_style.set_content_margin_all(12)
	pick_panel.add_theme_stylebox_override("panel", pick_style)
	pick_panel.anchor_left = 0.5
	pick_panel.anchor_right = 0.5
	pick_panel.anchor_top = 1.0
	pick_panel.anchor_bottom = 1.0
	pick_panel.offset_left = -340
	pick_panel.offset_right = 340
	pick_panel.offset_top = -184
	pick_panel.offset_bottom = -_BOTTOM_CLEARANCE
	pick_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pick_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(pick_panel)

	var pick_vbox = VBoxContainer.new()
	pick_vbox.name = "PickVBox"
	pick_vbox.add_theme_constant_override("separation", 6)
	pick_panel.add_child(pick_vbox)

	pick_label = Label.new()
	pick_label.name = "PickLabel"
	pick_label.text = "Remove casualties"
	pick_label.add_theme_font_size_override("font_size", 16)
	pick_label.add_theme_color_override("font_color", _WhiteDwarfTheme.WH_GOLD)
	pick_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_vbox.add_child(pick_label)

	pick_counter = Label.new()
	pick_counter.name = "PickCounter"
	pick_counter.text = ""
	pick_counter.add_theme_font_size_override("font_size", 13)
	pick_counter.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	pick_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_vbox.add_child(pick_counter)

	var pick_buttons = HBoxContainer.new()
	pick_buttons.name = "PickButtons"
	pick_buttons.add_theme_constant_override("separation", 8)
	pick_vbox.add_child(pick_buttons)

	confirm_removal_button = Button.new()
	confirm_removal_button.name = "ConfirmRemovalButton"
	confirm_removal_button.text = "Confirm Removal"
	confirm_removal_button.custom_minimum_size = Vector2(180, 38)
	confirm_removal_button.disabled = true
	confirm_removal_button.pressed.connect(_on_confirm_removal_pressed)
	_WhiteDwarfTheme.apply_primary_button(confirm_removal_button)
	pick_buttons.add_child(confirm_removal_button)

	auto_pick_button = Button.new()
	auto_pick_button.name = "AutoPickButton"
	auto_pick_button.text = "Auto-pick For Me"
	auto_pick_button.custom_minimum_size = Vector2(140, 38)
	auto_pick_button.pressed.connect(_on_auto_pick_pressed)
	pick_buttons.add_child(auto_pick_button)

	set_process_input(false)


func _group_by_id(gid: String) -> Dictionary:
	for g in groups:
		if g.id == gid:
			return g
	return {}


func _group_label(g: Dictionary, order_index: int) -> String:
	var desc = "%d. " % (order_index + 1)
	if g.character:
		desc += "CHARACTER — "
	desc += "%d model(s)  W%d  Sv%s  InSv%s" % [
		g.model_indices.size(), g.w,
		("%d+" % g.sv) if g.sv < 7 else "-",
		("%d+" % g.insv) if g.insv > 0 else "-"]
	if g.has_wounded:
		desc += "  [wounded]"
	return desc


func _rebuild_group_list() -> void:
	for child in group_list.get_children():
		# Rename before the deferred free so replacement rows keep the
		# canonical Row<N>/Up<N>/Down<N> paths (scenarios click these).
		child.name = "_dying_row"
		child.queue_free()
	for i in range(order.size()):
		var g = _group_by_id(order[i])
		var row = HBoxContainer.new()
		row.name = "Row%d" % i
		var lbl = Label.new()
		lbl.name = "GroupLabel"
		lbl.text = _group_label(g, i)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var up = Button.new()
		up.name = "Up%d" % i
		up.text = "▲"
		up.disabled = i == 0
		up.pressed.connect(_on_move.bind(i, -1))
		row.add_child(up)
		var down = Button.new()
		down.name = "Down%d" % i
		down.text = "▼"
		down.disabled = i == order.size() - 1
		down.pressed.connect(_on_move.bind(i, 1))
		row.add_child(down)
		group_list.add_child(row)
	_validate_order()


func _on_move(index: int, delta: int) -> void:
	var j = index + delta
	if j < 0 or j >= order.size():
		return
	var tmp = order[index]
	order[index] = order[j]
	order[j] = tmp
	_rebuild_group_list()


func _validate_order() -> void:
	var check = Allocation.validate_order(groups, order)
	if check.valid:
		error_label.text = ""
		confirm_button.disabled = false
	else:
		error_label.text = "Illegal order: " + "; ".join(check.errors)
		confirm_button.disabled = true
	print("AllocationGroupOverlay: order %s valid=%s" % [str(order), str(check.valid)])


func _fresh_seed() -> int:
	# Derives from RulesEngine.make_rng so test_mode_seed / network seeds
	# keep the whole flow deterministic in harness runs.
	return absi(_rules().make_rng().rng.randi())


func _run_batch(preferred_targets: Array) -> Dictionary:
	# Every run replays the SAME save dice (forced) with the SAME damage
	# seed, so re-runs (casualty pick) only change WHICH bases die.
	var rng = _rules().RNGService.new(_batch_seed)
	return _rules().resolve_allocation_batch_11e(save_data, order, _game_state().state, rng, {
		"forced_save_rolls": _current_rolls,
		"preferred_targets": preferred_targets,
	})


func _on_confirm_pressed() -> void:
	if resolved:
		return
	var check = Allocation.validate_order(groups, order)
	if not check.valid:
		print("AllocationGroupOverlay: confirm blocked — illegal order %s" % str(order))
		return
	resolved = true
	confirm_button.disabled = true
	# 24.28: carry the attacker's PRECISION promotion pick (or explicit
	# decline) into the engine; "" auto-picks / no-ops as appropriate.
	if precision_picker != null:
		var sel = precision_picker.selected
		if sel >= 1 and sel - 1 < _precision_eligible.size():
			save_data["precision_group_choice"] = str(_precision_eligible[sel - 1].id)
		else:
			save_data["precision_group_choice"] = ""
			save_data["has_precision"] = false  # attacker declined the promotion

	# Roll the save dice ONCE, then resolve with them forced (deterministic
	# re-runs for the re-roll / casualty-pick steps).
	var wounds_to_save = int(save_data.get("wounds_to_save", 0))
	_current_rolls = _rules().RNGService.new(_fresh_seed()).roll_d6(wounds_to_save) if wounds_to_save > 0 else []
	_batch_seed = _fresh_seed()
	batch_result = _run_batch([])
	print("AllocationGroupOverlay: rolled saves %s → %d failed, %d casualties" % [
		str(_current_rolls), batch_result.get("saves_failed", 0), batch_result.get("casualties", 0)])

	if auto_mode:
		_finalize_batch()
		return

	# Offer the save Command Re-roll when the defender can pay and at least
	# one save die failed.
	if batch_result.get("saves_failed", 0) > 0 and _save_reroll_available():
		_show_reroll_step()
	else:
		_enter_pick_or_finalize()


func _save_reroll_available() -> bool:
	var sm = Engine.get_main_loop().root.get_node_or_null("StratagemManager")
	if sm == null or not sm.has_method("is_command_reroll_available"):
		return false
	var check = sm.is_command_reroll_available(defender_player)
	if not check.get("available", false):
		print("AllocationGroupOverlay: Command Re-roll unavailable for player %d — %s" % [
			defender_player, str(check.get("reason", ""))])
	return check.get("available", false)


# The raw-roll indices whose dice FAILED (result damage/prevented). Events
# report sorted values, so map each failed value back to an unconsumed raw
# index (identical values are interchangeable dice).
func _failed_roll_indices() -> Array:
	var failed_values: Array = []
	for d in batch_result.get("dice", []):
		if d.get("context", "") == "save":
			for ev in d.get("allocation_11e", {}).get("events", []):
				var res = str(ev.get("result", ""))
				if res == "damage" or res == "prevented":
					failed_values.append(int(ev.get("roll", 0)))
	var consumed: Array = []
	for v in failed_values:
		for i in range(_current_rolls.size()):
			if int(_current_rolls[i]) == v and i not in consumed:
				consumed.append(i)
				break
	return consumed


func _show_reroll_step() -> void:
	order_label.visible = false
	group_list.visible = false
	confirm_button.visible = false
	error_label.visible = false
	if precision_picker != null:
		precision_picker.disabled = true
	var failed = _failed_roll_indices()
	for child in dice_chips.get_children():
		child.queue_free()
	for i in range(_current_rolls.size()):
		var v = int(_current_rolls[i])
		var chip = Button.new()
		chip.name = "Die%d" % i
		# Show each save as its d6 face icon (pips) rather than a number, matching
		# the combat log and the rest of the game's dice visuals. Failed saves are
		# tinted red (and clickable to re-roll); passed saves green.
		var failed_die: bool = i in failed
		var bg: Color = _DiceFaceIcons.COLOR_FUMBLE if failed_die else _DiceFaceIcons.COLOR_SUCCESS
		chip.icon = _DiceFaceIcons.get_face(v, bg)
		chip.expand_icon = true
		chip.custom_minimum_size = Vector2(44, 44)
		if failed_die:
			chip.tooltip_text = "Failed save (rolled %d) — click to re-roll (1 CP)" % v
			chip.pressed.connect(_on_reroll_die_pressed.bind(i))
		else:
			chip.disabled = true
			chip.tooltip_text = "Passed save (rolled %d)" % v
		dice_chips.add_child(chip)
	reroll_panel.visible = true
	print("AllocationGroupOverlay: Command Re-roll offered — failed dice at raw indices %s" % str(failed))


func _on_reroll_die_pressed(die_index: int) -> void:
	if _command_reroll.get("used", false):
		return
	var original = int(_current_rolls[die_index])
	var new_roll = int(_rules().RNGService.new(_fresh_seed()).roll_d6(1)[0])
	_current_rolls[die_index] = new_roll
	# New damage seed: per the rules the damage/FNP dice are rolled AFTER
	# the re-roll decision, so a fresh stream is correct here.
	_batch_seed = _fresh_seed()
	_command_reroll = {
		"used": true,
		"player": defender_player,
		"die_index": die_index,
		"original": original,
		"new": new_roll,
	}
	batch_result = _run_batch([])
	print("AllocationGroupOverlay: COMMAND RE-ROLL — die %d: %d → %d (now %d failed, %d casualties)" % [
		die_index, original, new_roll, batch_result.get("saves_failed", 0), batch_result.get("casualties", 0)])
	reroll_panel.visible = false
	_enter_pick_or_finalize()


func _on_keep_rolls_pressed() -> void:
	reroll_panel.visible = false
	_enter_pick_or_finalize()


# ── PICK step ─────────────────────────────────────────────────────────

# Per group: how many casualties landed there, and is there a real choice
# (more alive models in the group than casualties)?
func _compute_pick_requirements() -> void:
	_pick_required.clear()
	_pick_locked.clear()
	_pick_selected.clear()
	_pick_candidates.clear()
	var destroyed: Array = batch_result.get("models_destroyed", [])
	var batch_groups: Array = batch_result.get("groups", groups)
	for g in batch_groups:
		var dead_in_group: Array = []
		for vi in destroyed:
			if int(vi) in g.model_indices:
				dead_in_group.append(int(vi))
		if dead_in_group.is_empty():
			continue
		if dead_in_group.size() >= g.model_indices.size():
			continue  # whole group dies — nothing to choose
		_pick_required[g.id] = dead_in_group.size()
		_pick_locked[g.id] = []
		_pick_selected[g.id] = []
		# 05.04: a pre-wounded model must take the first allocation — it is
		# locked into the casualty set (it cannot be spared).
		if g.get("has_wounded", false):
			var wounded_vi = _find_wounded_virtual_index(g)
			if wounded_vi != -1:
				_pick_locked[g.id].append(wounded_vi)
		# Only offer clickable candidates when the locked picks leave a real
		# choice; a required count fully covered by the wounded model needs
		# no input.
		if dead_in_group.size() - _pick_locked[g.id].size() > 0:
			for vi in g.model_indices:
				if int(vi) not in _pick_locked[g.id]:
					_pick_candidates.append(int(vi))


func _find_wounded_virtual_index(g: Dictionary) -> int:
	var sources: Array = batch_result.get("sources", [])
	for vi in g.model_indices:
		var src = _virtual_source(int(vi), sources)
		if src.is_empty():
			continue
		var m = _live_model(src)
		if m.is_empty():
			continue
		var w = int(m.get("wounds", 1))
		if int(m.get("current_wounds", w)) < w:
			return int(vi)
	return -1


func _virtual_source(vi: int, sources: Array) -> Dictionary:
	if vi >= 0 and vi < sources.size():
		return sources[vi]
	return {}


func _live_model(src: Dictionary) -> Dictionary:
	var unit = _game_state().state.get("units", {}).get(str(src.get("unit_id", "")), {})
	var models = unit.get("models", [])
	var mi = int(src.get("model_index", -1))
	if mi >= 0 and mi < models.size():
		return models[mi]
	return {}


func _enter_pick_or_finalize() -> void:
	_compute_pick_requirements()
	if _pick_required.is_empty() or _pick_candidates.is_empty():
		# No choice to make (no casualties, whole groups wiped, or the
		# wounded-model lock already covers every required removal).
		_finalize_batch()
		return
	_picking = true
	center.visible = false
	dim.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick_panel.visible = true
	var total_required := 0
	for gid in _pick_required:
		total_required += int(_pick_required[gid])
	var unit_name = str(save_data.get("target_unit_name", save_data.get("target_unit_id", "")))
	var attacker_name = _attacker_display_name()
	var attacker_txt = " (hit by %s)" % attacker_name if attacker_name != "" else ""
	pick_label.text = "Remove %d model(s) from %s%s — click the bases to remove" % [total_required, unit_name, attacker_txt]
	_setup_pick_highlights()
	_update_pick_counter()
	set_process_input(true)
	print("AllocationGroupOverlay: PICK step — %d casualty pick(s) required across %d group(s)" % [
		total_required, _pick_required.size()])


func _setup_pick_highlights() -> void:
	var refs = Engine.get_main_loop().root.get_node_or_null("SceneRefs")
	var board_view = refs.board_view() if refs != null else null
	if board_view == null:
		print("AllocationGroupOverlay: WARNING — no board_view, casualty picking falls back to Auto-pick only")
		return
	var highlights_script = load(_BOARD_HIGHLIGHTS_PATH)
	if highlights_script == null:
		print("AllocationGroupOverlay: WARNING — board highlight script unavailable")
		return
	board_highlighter = highlights_script.new()
	board_highlighter.name = "AllocationPickHighlights"
	board_highlighter.z_index = 900
	board_view.add_child(board_highlighter)
	_refresh_pick_highlights()


func _refresh_pick_highlights() -> void:
	if board_highlighter == null or not is_instance_valid(board_highlighter):
		return
	board_highlighter.clear_all()
	var ht = board_highlighter.HighlightType
	var sources: Array = batch_result.get("sources", [])
	for gid in _pick_required:
		for vi in _pick_locked[gid]:
			var pos = _virtual_model_position(int(vi), sources)
			if pos != Vector2.ZERO:
				board_highlighter.create_highlight(pos, _virtual_model_base_mm(int(vi), sources),
					ht.PRIORITY, "vi_%d" % int(vi))
	for vi in _pick_candidates:
		var gid = _group_id_for_virtual(vi)
		if gid == "":
			continue
		var pos = _virtual_model_position(vi, sources)
		if pos == Vector2.ZERO:
			continue
		var selected: bool = vi in _pick_selected.get(gid, [])
		board_highlighter.create_highlight(pos, _virtual_model_base_mm(vi, sources),
			ht.SELECTED if selected else ht.SELECTABLE,
			"vi_%d" % vi)


func _group_id_for_virtual(vi: int) -> String:
	for g in batch_result.get("groups", groups):
		if vi in g.model_indices and _pick_required.has(g.id):
			return str(g.id)
	return ""


func _virtual_model_position(vi: int, sources: Array) -> Vector2:
	var m = _live_model(_virtual_source(vi, sources))
	if m.is_empty():
		return Vector2.ZERO
	var pos = m.get("position")
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO


func _virtual_model_base_mm(vi: int, sources: Array) -> float:
	var m = _live_model(_virtual_source(vi, sources))
	return float(m.get("base_mm", 32)) if not m.is_empty() else 32.0


func _input(event: InputEvent) -> void:
	if not _picking:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Ignore clicks on the pick panel itself.
		if pick_panel.get_global_rect().has_point(event.position):
			return
		var refs = Engine.get_main_loop().root.get_node_or_null("SceneRefs")
		var board_view = refs.board_view() if refs != null else null
		if board_view == null:
			return
		var click_pos: Vector2 = board_view.get_local_mouse_position()
		var vi = _find_candidate_at(click_pos)
		if vi != -1:
			_toggle_pick(vi)
			accept_event()


func _find_candidate_at(click_pos: Vector2) -> int:
	var sources: Array = batch_result.get("sources", [])
	var meas = _measurement()
	var closest_vi := -1
	var closest_dist := INF
	for vi in _pick_candidates:
		var pos = _virtual_model_position(vi, sources)
		if pos == Vector2.ZERO:
			continue
		var base_mm = _virtual_model_base_mm(vi, sources)
		var radius_px: float = meas.base_radius_px(base_mm) if meas != null else base_mm
		var click_radius = radius_px + 30.0
		var dist = pos.distance_to(click_pos)
		if dist <= click_radius and dist < closest_dist:
			closest_dist = dist
			closest_vi = vi
	return closest_vi


func _toggle_pick(vi: int) -> void:
	var gid = _group_id_for_virtual(vi)
	if gid == "":
		return
	var selected: Array = _pick_selected[gid]
	if vi in selected:
		selected.erase(vi)
	else:
		var quota = int(_pick_required[gid]) - _pick_locked[gid].size()
		if selected.size() >= quota:
			# Replace the oldest pick so re-picking feels natural.
			if quota <= 0:
				return
			selected.pop_front()
		selected.append(vi)
	print("AllocationGroupOverlay: pick toggle vi=%d — group %s now %s" % [vi, gid, str(selected)])
	_refresh_pick_highlights()
	_update_pick_counter()


func _update_pick_counter() -> void:
	var parts: Array = []
	var complete := true
	for gid in _pick_required:
		var have = _pick_locked[gid].size() + _pick_selected[gid].size()
		var need = int(_pick_required[gid])
		if have < need:
			complete = false
		var locked_txt = " (%d wounded locked in)" % _pick_locked[gid].size() if _pick_locked[gid].size() > 0 else ""
		parts.append("Selected %d / %d%s" % [have, need, locked_txt])
	pick_counter.text = "  •  ".join(parts)
	confirm_removal_button.disabled = not complete


func _on_confirm_removal_pressed() -> void:
	var preferred: Array = []
	for gid in _pick_required:
		preferred.append_array(_pick_locked[gid])
		preferred.append_array(_pick_selected[gid])
	var expected_casualties = int(batch_result.get("casualties", 0))
	var final_batch = _run_batch(preferred)
	if int(final_batch.get("casualties", 0)) != expected_casualties:
		# Model-level FNP differences inside a group can shift the outcome;
		# the re-run is authoritative — log loudly and continue.
		print("AllocationGroupOverlay: WARNING — casualty count changed on pick re-run (%d → %d)" % [
			expected_casualties, int(final_batch.get("casualties", 0))])
	batch_result = final_batch
	print("AllocationGroupOverlay: casualties re-allocated to defender's picks %s" % str(preferred))
	_end_pick_mode()
	_finalize_batch()


func _on_auto_pick_pressed() -> void:
	print("AllocationGroupOverlay: defender chose Auto-pick — keeping engine allocation")
	_end_pick_mode()
	_finalize_batch()


func _end_pick_mode() -> void:
	_picking = false
	set_process_input(false)
	pick_panel.visible = false
	dim.visible = true
	center.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if board_highlighter != null and is_instance_valid(board_highlighter):
		board_highlighter.clear_all()
		board_highlighter.queue_free()
		board_highlighter = null


# ── Finalize: apply the batch to GameState and show results ────────────

func _finalize_batch() -> void:
	_apply_diffs_to_gamestate(batch_result.get("diffs", []))
	var target_unit_id = str(save_data.get("target_unit_id", ""))
	if batch_result.get("casualties", 0) > 0:
		get_node("/root/CharacterAttachmentManager").check_bodyguard_destroyed(target_unit_id)
		get_node("/root/SecondaryMissionManager").check_and_report_unit_destroyed(target_unit_id)
	_refresh_board_visuals()
	_show_results()


func _apply_diffs_to_gamestate(diffs: Array) -> void:
	for diff in diffs:
		var parts = str(diff.get("path", "")).split(".")
		if parts.size() != 5 or parts[0] != "units" or parts[2] != "models":
			continue
		var unit_id = parts[1]
		var mi = int(parts[3])
		var field = parts[4]
		var unit = _game_state().state.get("units", {}).get(unit_id, {})
		var models = unit.get("models", [])
		if mi >= 0 and mi < models.size():
			models[mi][field] = diff.get("value")
			if field == "alive" and diff.get("value") == false:
				print("AllocationGroupOverlay: 💀 %s removed (unit %s, model %d)" % [
					_rules().get_model_display_label(models[mi], unit), unit_id, mi])


func _refresh_board_visuals() -> void:
	# Runtime-node form of the SceneRefs chokepoint: this overlay is also
	# compiled standalone by headless tests, where autoload identifiers
	# don't resolve at parse time.
	var refs = Engine.get_main_loop().root.get_node_or_null("SceneRefs")
	var main = refs.main() if refs != null else null
	if main and main.has_method("refresh_all_model_visuals"):
		main.refresh_all_model_visuals()


func _show_results() -> void:
	order_label.visible = false
	group_list.visible = false
	confirm_button.visible = false
	error_label.visible = false
	reroll_panel.visible = false
	var rolls: Array = batch_result.get("save_rolls", []).duplicate()
	rolls.sort()
	# Render the save rolls as inline d6 face icons (pips) instead of raw numbers,
	# matching the dice visuals used across the rest of the game.
	_result_dice_icon_count = 0
	result_label.clear()
	result_label.append_text("Save rolls (lowest first): ")
	_append_save_dice_icons(rolls)
	result_label.append_text("\n")
	if _command_reroll.get("used", false):
		result_label.append_text("Command Re-roll: ")
		_append_save_dice_icons([int(_command_reroll.get("original", 0))])
		result_label.append_text(" re-rolled into ")
		_append_save_dice_icons([int(_command_reroll.get("new", 0))])
		result_label.append_text(" (1 CP)\n")
	result_label.append_text("%d saved, %d failed — %d damage, %d model(s) destroyed" % [
		batch_result.get("saves_passed", 0), batch_result.get("saves_failed", 0),
		batch_result.get("damage_applied", 0), batch_result.get("casualties", 0)])
	for d in batch_result.get("dice", []):
		if d.get("context", "") == "devastating_wounds_11e":
			result_label.append_text("\nDevastating wounds: %d crit(s) applied as mortal wounds (max one model each)" % d.get("crits", 0))
	result_panel.visible = true
	# Keep a plain-text debug line (icons don't survive to the log).
	print("AllocationGroupOverlay: resolved — save_rolls(lowest first)=%s, %d saved, %d failed, %d damage, %d destroyed%s" % [
		str(rolls), batch_result.get("saves_passed", 0), batch_result.get("saves_failed", 0),
		batch_result.get("damage_applied", 0), batch_result.get("casualties", 0),
		(" | Command Re-roll %d→%d" % [int(_command_reroll.get("original", 0)), int(_command_reroll.get("new", 0))]) if _command_reroll.get("used", false) else ""])


# Append `rolls` to the results RichTextLabel as inline d6 face icons (rounded
# square + pips) — the shared DiceFaceIcons textures used across the game log and
# the other dice UIs. Neutral coloring with a crit threshold of 7 (a 6 on a save
# is not a crit); natural 1s render red. Bumps _result_dice_icon_count so
# windowed scenarios can assert the icons mounted.
func _append_save_dice_icons(rolls: Array) -> void:
	if rolls.is_empty():
		result_label.append_text("—")
		return
	for i in range(rolls.size()):
		var v = int(rolls[i])
		var bg = _DiceFaceIcons.color_for(v, 0, false, 7)
		result_label.add_image(_DiceFaceIcons.get_face(v, bg), 18, 18, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		if i < rolls.size() - 1:
			result_label.append_text(" ")
	_result_dice_icon_count += rolls.size()


func _on_done_pressed() -> void:
	var summary = batch_result.duplicate(true)
	summary["total_damage"] = summary.get("damage_applied", 0)
	summary["models_destroyed"] = summary.get("casualties", 0)
	summary["allocation_order"] = order
	if _command_reroll.get("used", false):
		summary["command_reroll"] = _command_reroll.duplicate(true)
	emit_signal("allocation_complete", summary)
	queue_free()


func _exit_tree() -> void:
	# Never leave board highlights behind if the overlay is freed mid-pick
	# (phase transition, disconnect, scenario teardown).
	if board_highlighter != null and is_instance_valid(board_highlighter):
		board_highlighter.queue_free()
		board_highlighter = null
	if attack_context_visual != null and is_instance_valid(attack_context_visual):
		attack_context_visual.queue_free()
		attack_context_visual = null
