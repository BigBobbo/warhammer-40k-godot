extends AcceptDialog

# RollOffDialog - Dramatic UI for the pre-deployment roll-off (issue #85)
#
# 10th edition: BEFORE deployment, both players roll a D6. The winner
# chooses to be the Attacker or the Defender:
#   - Defender deploys first (and takes the second turn)
#   - Attacker deploys second (and takes the first turn)
#
# This dialog is presented centre-screen and shows two large animated D6
# dice — one per player. When the player rolls, both dice tumble through
# random faces for a beat before settling on the real result; the winning
# die then glows gold and scales up while the loser's die dims. The winner
# (if local) is then offered "Deploy First" / "Deploy Second".
#
# When the roll ties, both dice settle on the same value, a red "TIED"
# banner appears and a single "Re-roll" button is shown.
#
# Signal/API contract (consumed by Main.gd + tests/scenarios/85_*):
#   signals: roll_initiated, choice_made(choice), reroll_requested
#   methods: setup(local_player), show_result(p1, p2, winner), show_tie(p1, p2)
#   button node names: RollButton / DeployFirstButton / DeploySecondButton / RerollButton

signal roll_initiated()
signal choice_made(choice: String)  # "first" (deploy second) or "second" (deploy first)
signal reroll_requested()

enum Mode {
	AWAITING_ROLL,
	ROLLING,
	SHOWING_RESULT,
	SHOWING_TIE,
}

# How long the dice tumble before settling on the real values.
const ROLL_ANIM_DURATION := 1.1
const ROLL_TICK_INTERVAL := 0.06

var _mode: int = Mode.AWAITING_ROLL
var _winner: int = 0
var _local_player: int = 0
var _p1_roll: int = 0
var _p2_roll: int = 0
var _pending_tie: bool = false  # true while animating toward a tied result

# UI references built in _build_ui()
var _content_vbox: VBoxContainer
var _heading_label: Label
var _status_label: Label
var _dice_row: HBoxContainer
var _p1_die: Control
var _p2_die: Control
var _result_banner: RichTextLabel
var _button_bar: HBoxContainer

var _tick_timer: Timer


func _init() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)


func setup(local_player: int) -> void:
	_local_player = local_player
	title = "Determine First Turn"
	min_size = DialogConstants.MEDIUM
	get_ok_button().visible = false
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)
	_build_ui()
	_refresh_for_mode()


func show_awaiting() -> void:
	_mode = Mode.AWAITING_ROLL
	_refresh_for_mode()


func show_result(p1_roll: int, p2_roll: int, winner: int) -> void:
	_p1_roll = p1_roll
	_p2_roll = p2_roll
	_winner = winner
	_pending_tie = false
	_begin_roll_animation()


func show_tie(p1_roll: int, p2_roll: int) -> void:
	_p1_roll = p1_roll
	_p2_roll = p2_roll
	_winner = 0
	_pending_tie = true
	_begin_roll_animation()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_content_vbox = VBoxContainer.new()
	_content_vbox.name = "Content"
	_content_vbox.add_theme_constant_override("separation", 14)
	# Constrain the width so autowrap labels compute their height correctly and
	# the dialog stays a compact, centre-screen panel (mirrors CommandRerollDialog).
	_content_vbox.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 20, 0)
	add_child(_content_vbox)

	_heading_label = Label.new()
	_heading_label.text = "WHO SEIZES THE INITIATIVE?"
	_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading_label.add_theme_font_size_override("font_size", 22)
	_heading_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_GOLD)
	_content_vbox.add_child(_heading_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_PARCHMENT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_status_label)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(WhiteDwarfTheme.WH_GOLD.r,
		WhiteDwarfTheme.WH_GOLD.g, WhiteDwarfTheme.WH_GOLD.b, 0.4)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(sep)

	# Two big dice side by side, each with the player label above it.
	_dice_row = HBoxContainer.new()
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("separation", 48)
	_dice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_dice_row)

	_p1_die = _make_die_column(1)
	_p2_die = _make_die_column(2)
	_dice_row.add_child(_p1_die.get_parent())
	_dice_row.add_child(_p2_die.get_parent())

	_result_banner = RichTextLabel.new()
	_result_banner.bbcode_enabled = true
	_result_banner.fit_content = true
	_result_banner.scroll_active = false
	_result_banner.custom_minimum_size = Vector2(DialogConstants.MEDIUM.x - 40, 50)
	_content_vbox.add_child(_result_banner)

	_button_bar = HBoxContainer.new()
	_button_bar.name = "ButtonBar"
	_button_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_bar.add_theme_constant_override("separation", 12)
	_content_vbox.add_child(_button_bar)

	_tick_timer = Timer.new()
	_tick_timer.one_shot = false
	_tick_timer.wait_time = ROLL_TICK_INTERVAL
	_tick_timer.timeout.connect(_on_roll_tick)
	add_child(_tick_timer)


# Builds a VBox containing a "Player N" label and a DiceFace. Returns the
# DiceFace control (its parent is the column VBox).
func _make_die_column(player: int) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = "Player %d" % player
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", WhiteDwarfTheme.WH_BONE)
	col.add_child(name_label)

	var die := DiceFace.new()
	die.name = "Player%dDie" % player
	die.custom_minimum_size = Vector2(110, 110)
	die.value = 1
	die.pivot_offset = Vector2(55, 55)
	col.add_child(die)

	return die


func _refresh_for_mode() -> void:
	if _button_bar == null:
		return
	for child in _button_bar.get_children():
		child.queue_free()

	match _mode:
		Mode.AWAITING_ROLL:
			_heading_label.text = "WHO SEIZES THE INITIATIVE?"
			_status_label.text = "Both players roll a D6. Winner chooses to be Attacker (go first) or Defender (deploy first)."
			_result_banner.text = ""
			_p1_die.value = 1
			_p2_die.value = 1
			_p1_die.highlight = DiceFace.Highlight.NONE
			_p2_die.highlight = DiceFace.Highlight.NONE
			_p1_die.modulate = Color.WHITE
			_p2_die.modulate = Color.WHITE
			var roll_button := Button.new()
			roll_button.name = "RollButton"
			roll_button.text = "⚄  Roll for First Turn"
			roll_button.pressed.connect(_on_roll_pressed)
			WhiteDwarfTheme.apply_primary_button(roll_button)
			_button_bar.add_child(roll_button)
		Mode.ROLLING:
			_heading_label.text = "ROLLING…"
			_status_label.text = "The dice are cast!"
			_result_banner.text = ""
		Mode.SHOWING_RESULT:
			_heading_label.text = "FIRST TURN DECIDED"
			_status_label.text = "Roll-off result"
			var winner_color := "#D49761"
			_result_banner.text = (
				"[center][color=%s][b]Player %d wins the roll-off — %d vs %d![/b][/color][/center]"
				% [winner_color, _winner, _p1_roll, _p2_roll]
			)
			if _winner == _local_player:
				var first_button := Button.new()
				first_button.name = "DeployFirstButton"
				first_button.text = "Deploy first (Defender)"
				first_button.pressed.connect(_on_deploy_first_pressed)
				WhiteDwarfTheme.apply_secondary_button(first_button)
				_button_bar.add_child(first_button)

				var second_button := Button.new()
				second_button.name = "DeploySecondButton"
				second_button.text = "Go first (Attacker)"
				second_button.pressed.connect(_on_deploy_second_pressed)
				WhiteDwarfTheme.apply_primary_button(second_button)
				_button_bar.add_child(second_button)
			else:
				var waiting := Label.new()
				waiting.text = "Waiting for Player %d to choose…" % _winner
				waiting.add_theme_color_override("font_color",
					WhiteDwarfTheme.WH_BONE)
				_button_bar.add_child(waiting)
		Mode.SHOWING_TIE:
			_heading_label.text = "A DEAD HEAT!"
			_status_label.text = "Both warlords matched — the gods demand a re-roll."
			_result_banner.text = (
				"[center][color=#9A1115][b]TIED at %d — re-roll required![/b][/color][/center]"
				% _p1_roll
			)
			var reroll_button := Button.new()
			reroll_button.name = "RerollButton"
			reroll_button.text = "⟳  Re-roll"
			reroll_button.pressed.connect(_on_reroll_pressed)
			WhiteDwarfTheme.apply_primary_button(reroll_button)
			_button_bar.add_child(reroll_button)


# --- Roll animation ----------------------------------------------------------

func _begin_roll_animation() -> void:
	_mode = Mode.ROLLING
	_refresh_for_mode()
	# Clear any prior highlight while tumbling.
	_p1_die.highlight = DiceFace.Highlight.NONE
	_p2_die.highlight = DiceFace.Highlight.NONE
	_p1_die.modulate = Color.WHITE
	_p2_die.modulate = Color.WHITE
	_tick_timer.start()
	# Settle after the tumble duration, then reveal the real result.
	var settle := get_tree().create_timer(ROLL_ANIM_DURATION)
	settle.timeout.connect(_on_roll_settle)


func _on_roll_tick() -> void:
	# Tumble: show random faces and give each die a little jitter.
	_p1_die.value = randi_range(1, 6)
	_p2_die.value = randi_range(1, 6)
	_p1_die.rotation = randf_range(-0.18, 0.18)
	_p2_die.rotation = randf_range(-0.18, 0.18)


func _on_roll_settle() -> void:
	_tick_timer.stop()
	_p1_die.value = _p1_roll
	_p2_die.value = _p2_roll
	_p1_die.rotation = 0.0
	_p2_die.rotation = 0.0

	if _pending_tie:
		_mode = Mode.SHOWING_TIE
		_p1_die.highlight = DiceFace.Highlight.TIE
		_p2_die.highlight = DiceFace.Highlight.TIE
		_refresh_for_mode()
		_pop_die(_p1_die)
		_pop_die(_p2_die)
		return

	# Highlight winner gold, dim the loser, and give the winner a pop.
	var winner_die: Control = _p1_die if _winner == 1 else _p2_die
	var loser_die: Control = _p2_die if _winner == 1 else _p1_die
	winner_die.highlight = DiceFace.Highlight.WINNER
	loser_die.highlight = DiceFace.Highlight.LOSER
	loser_die.modulate = Color(0.6, 0.6, 0.6, 1.0)
	_mode = Mode.SHOWING_RESULT
	_refresh_for_mode()
	_pop_die(winner_die)


# A quick scale-up-and-settle "pop" so the reveal feels dramatic.
func _pop_die(die: Control) -> void:
	die.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(die, "scale", Vector2(1.25, 1.25), 0.18)
	tween.tween_property(die, "scale", Vector2(1.0, 1.0), 0.12)


# --- Signal handlers ---------------------------------------------------------

func _on_roll_pressed() -> void:
	emit_signal("roll_initiated")


func _on_deploy_first_pressed() -> void:
	# "Deploy first" = defender = CHOOSE_TURN_ORDER choice "second" (go
	# second in turn order). Map to the action contract the phase expects.
	emit_signal("choice_made", "second")


func _on_deploy_second_pressed() -> void:
	# "Deploy second / go first" = attacker = CHOOSE_TURN_ORDER choice "first".
	emit_signal("choice_made", "first")


func _on_reroll_pressed() -> void:
	emit_signal("reroll_requested")


func _on_close_requested() -> void:
	# Ignore close attempts — the roll-off must complete to proceed.
	pass


# -----------------------------------------------------------------------------
# DiceFace — a Control that draws a single D6 face with pips, themed to match
# the parchment/gold White Dwarf styling. `value` (1-6) drives the pip layout;
# `highlight` tints the face for winner/loser/tie states.
# -----------------------------------------------------------------------------
class DiceFace extends Control:
	enum Highlight { NONE, WINNER, LOSER, TIE }

	var value: int = 1:
		set(v):
			value = clampi(v, 1, 6)
			queue_redraw()
	var highlight: int = Highlight.NONE:
		set(h):
			highlight = h
			queue_redraw()

	func _draw() -> void:
		var sz := size
		var rect := Rect2(Vector2.ZERO, sz)

		# Face colour + border depend on highlight state.
		var face_color := Color(0.922, 0.882, 0.780)   # WH_PARCHMENT
		var border_color := Color(0.833, 0.588, 0.376)  # WH_GOLD
		var border_w := 3.0
		match highlight:
			Highlight.WINNER:
				face_color = Color(1.0, 0.93, 0.74)
				border_color = Color(1.0, 0.78, 0.30)
				border_w = 6.0
			Highlight.LOSER:
				face_color = Color(0.78, 0.75, 0.66)
				border_color = Color(0.55, 0.50, 0.42)
			Highlight.TIE:
				border_color = Color(0.604, 0.067, 0.082)  # WH_RED
				border_w = 5.0

		# Soft drop shadow for depth.
		var shadow_rect := Rect2(rect.position + Vector2(4, 5), rect.size)
		_draw_round_rect(shadow_rect, Color(0, 0, 0, 0.35), 14.0)
		# Die body + border.
		_draw_round_rect(rect, face_color, 14.0)
		_draw_round_rect_outline(rect, border_color, 14.0, border_w)

		# Pips.
		var pip_color := Color(0.12, 0.10, 0.09)
		var pip_r: float = min(sz.x, sz.y) * 0.085
		for p in _pip_positions(value):
			draw_circle(Vector2(p.x * sz.x, p.y * sz.y), pip_r, pip_color)

	# Normalised pip positions (0..1) for each die value.
	func _pip_positions(v: int) -> Array:
		var c := Vector2(0.5, 0.5)
		var tl := Vector2(0.28, 0.28)
		var tr := Vector2(0.72, 0.28)
		var bl := Vector2(0.28, 0.72)
		var br := Vector2(0.72, 0.72)
		var ml := Vector2(0.28, 0.5)
		var mr := Vector2(0.72, 0.5)
		match v:
			1: return [c]
			2: return [tl, br]
			3: return [tl, c, br]
			4: return [tl, tr, bl, br]
			5: return [tl, tr, c, bl, br]
			6: return [tl, tr, ml, mr, bl, br]
		return [c]

	func _draw_round_rect(rect: Rect2, color: Color, radius: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(int(radius))
		draw_style_box(sb, rect)

	func _draw_round_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_corner_radius_all(int(radius))
		sb.set_border_width_all(int(width))
		sb.border_color = color
		draw_style_box(sb, rect)
