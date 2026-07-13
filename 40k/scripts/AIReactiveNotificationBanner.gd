extends PanelContainer
class_name AIReactiveNotificationBanner

# AIReactiveNotificationBanner — a prominent, non-blocking heads-up shown when the
# AI takes a REACTIVE action during the human player's own turn: Fire Overwatch,
# Counter-Offensive, Heroic Intervention, a defensive reactive stratagem
# (Go to Ground / Smokescreen), Rapid Ingress, etc.
#
# These happen out-of-band while the human is mid-turn, so a line in the game log
# is easy to miss. This banner slides down from the top-centre, holds, then fades
# out. It never blocks input (MOUSE_FILTER_IGNORE) — if the reactive action also
# needs the player to respond (e.g. a Counter-Offensive / Heroic Intervention
# decision dialog) that dialog appears independently and stays fully usable.

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

const BANNER_WIDTH: float = 640.0
const RESTING_TOP: float = 112.0   # sits just below the top HUD bar
const SLIDE_OFFSET: float = 60.0   # how far above the resting spot it starts
const SLIDE_IN_DURATION: float = 0.30
const HOLD_DURATION: float = 4.0
const SLIDE_OUT_DURATION: float = 0.45

# Accent colours: red for incoming attacks, gold for other reactive plays.
const ACCENT_ATTACK: Color = Color(0.90, 0.32, 0.26)
const ACCENT_PLAY: Color = Color(0.85, 0.63, 0.30)

var _panel_style: StyleBoxFlat
var _badge_label: Label
var _headline_label: Label
var _detail_label: Label
var _tween: Tween

func _ready() -> void:
	_build_ui()
	visible = false
	modulate.a = 0.0
	# Never intercept clicks — the player keeps interacting with the board and any
	# reactive decision dialog underneath/over this banner.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[AIReactiveNotificationBanner] Ready")

func _build_ui() -> void:
	name = "AIReactiveNotificationBanner"

	# Anchor to the top-centre of the screen.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -BANNER_WIDTH / 2.0
	offset_right = BANNER_WIDTH / 2.0
	offset_top = RESTING_TOP
	offset_bottom = RESTING_TOP + 70.0

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.09, 0.07, 0.06, 0.96)
	_panel_style.border_color = ACCENT_ATTACK
	_panel_style.set_border_width_all(2)
	_panel_style.border_width_left = 6  # thick accent bar on the left
	_panel_style.set_corner_radius_all(5)
	_panel_style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", _panel_style)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# Alert badge (kept to ASCII so it renders in the game's gothic font).
	var badge = Label.new()
	badge.text = "!"
	badge.custom_minimum_size = Vector2(40, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 34)
	badge.add_theme_color_override("font_color", ACCENT_ATTACK)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.name = "Badge"
	_badge_label = badge
	row.add_child(badge)

	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	_headline_label = Label.new()
	_headline_label.text = "AI REACTION"
	_headline_label.add_theme_font_size_override("font_size", 20)
	_headline_label.add_theme_color_override("font_color", ACCENT_ATTACK)
	_headline_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_headline_label)

	_detail_label = Label.new()
	_detail_label.text = ""
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("font_size", 14)
	_detail_label.add_theme_color_override("font_color", WhiteDwarfThemeData.WH_PARCHMENT)
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_detail_label)

# ── Public API ──────────────────────────────────────────────────────────────

func show_reaction(headline: String, detail: String, is_attack: bool = true) -> void:
	"""Announce an AI reactive action. `headline` is a short all-caps label
	(e.g. 'FIRE OVERWATCH'); `detail` is the AI's own description of what it did.
	`is_attack` tints the banner red (incoming attack) vs gold (other play)."""
	var accent := ACCENT_ATTACK if is_attack else ACCENT_PLAY
	if _panel_style:
		_panel_style.border_color = accent
	if _headline_label:
		_headline_label.text = headline
		_headline_label.add_theme_color_override("font_color", accent)
	if _badge_label:
		_badge_label.add_theme_color_override("font_color", accent)
	if _detail_label:
		_detail_label.text = detail

	# Restart cleanly if a previous banner is still animating.
	if _tween and _tween.is_valid():
		_tween.kill()

	visible = true
	modulate.a = 0.0
	offset_top = RESTING_TOP - SLIDE_OFFSET
	offset_bottom = RESTING_TOP - SLIDE_OFFSET + 70.0

	_tween = create_tween()
	# Slide down + fade in
	_tween.tween_property(self, "offset_top", RESTING_TOP, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(self, "offset_bottom", RESTING_TOP + 70.0, SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, SLIDE_IN_DURATION)
	# Hold
	_tween.tween_interval(HOLD_DURATION)
	# Slide up + fade out
	_tween.tween_property(self, "offset_top", RESTING_TOP - SLIDE_OFFSET, SLIDE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, SLIDE_OUT_DURATION)
	_tween.tween_callback(_on_hidden)

	print("[AIReactiveNotificationBanner] %s — %s" % [headline, detail])

func _on_hidden() -> void:
	visible = false
	modulate.a = 0.0

# ── Accessors (used by windowed scenarios) ───────────────────────────────────

func get_detail_text() -> String:
	return _detail_label.text if _detail_label else ""

func get_headline_text() -> String:
	return _headline_label.text if _headline_label else ""
