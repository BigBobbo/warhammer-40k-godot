extends PanelContainer

# HoverForecast — the shooting-phase hover tooltip (T05, design guidelines §7).
#
# While a shooter is selected and the cursor rests on an eligible enemy unit,
# ShootingController shows this card beside the cursor with what one of the
# shooter's weapons is expected to do to that unit:
#
#   Twin adrathic destructor → Kommandos          weapon → target
#   A 1   BS 3+   S 6 vs T 5   AP -2   D 3         the profile it rolls with
#   [shield] Benefit of cover: BS 2+ → 3+          only when cover applies
#   Hit 3+ · Wound 3+ · Save none                  the dice it needs
#   1 att → 0.67 hit → 0.59 wnd → 0.59 unsaved     the expected chain
#   ≈ 1.8 damage (≈ 1.8 models)                    the expected result
#   Twin-Linked · Best of 3 weapons, all ≈ 4.0      modifiers / other weapons
#
# The numbers are ShootingController.current_hover_forecast, built from
# RulesEngine.preview_attack — the same modifier stack the live roll uses — so
# the benefit of cover (11e 13.08: BS worsened by 1), [HEAVY], plunging fire and
# re-roll / +1 effects are already in them. The card only formats them.
#
# The node is named "HoverForecast" and is a child of the ShootingController
# (/root/Main/ShootingController/HoverForecast), so it goes away with the phase.
# It never takes mouse input. It sits above-right of the cursor, flips to
# another corner when that would leave the viewport, and steers clear of Main's
# TokenHoverTooltip stats card (which opens right of / below the cursor).

const WhiteDwarfThemeScript = preload("res://scripts/WhiteDwarfTheme.gd")
const UIConstantsScript = preload("res://autoloads/UIConstants.gd")

const BODY_FONT_SIZE := 15
const TITLE_FONT_SIZE := 16
const RESULT_FONT_SIZE := 18
const CURSOR_GAP := Vector2(18.0, 14.0)  # card offset from the cursor
const EDGE_MARGIN := 6.0                 # never closer than this to the viewport edge
const MUTED_HEX := "#9A9486"
const LABEL_HEX := "#B8AE97"

## What the card shows (a ShootingController.current_hover_forecast), {} when hidden.
var forecast: Dictionary = {}
## Screen position the card is placed beside (the cursor).
var anchor_screen: Vector2 = Vector2.ZERO

var _body: VBoxContainer
var _title: RichTextLabel
var _stats: RichTextLabel
var _cover_row: HBoxContainer
var _cover_icon: Control
var _cover_label: Label
var _rolls: RichTextLabel
var _chain: RichTextLabel
var _result: RichTextLabel
var _footer: RichTextLabel


func _init() -> void:
	name = "HoverForecast"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Placed in screen space whatever the parent's transform, and drawn above
	# the HUD and the board (same overlay z as Main's TokenHoverTooltip).
	top_level = true
	z_index = 1000
	_build()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.96)
	style.border_color = Color(WhiteDwarfThemeScript.WH_GOLD, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)

	_title = _add_rich("Title", TITLE_FONT_SIZE)
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(WhiteDwarfThemeScript.WH_GOLD, 0.4)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(rule)
	_stats = _add_rich("Stats", BODY_FONT_SIZE)

	_cover_row = HBoxContainer.new()
	_cover_row.name = "CoverRow"
	_cover_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_row.add_theme_constant_override("separation", 6)
	_cover_row.visible = false
	_body.add_child(_cover_row)
	_cover_icon = _ShieldIcon.new()
	_cover_icon.name = "CoverIcon"
	_cover_row.add_child(_cover_icon)
	_cover_label = Label.new()
	_cover_label.name = "CoverLabel"
	_cover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_cover_label.add_theme_color_override("font_color", UIConstantsScript.MARGINAL_YELLOW)
	_cover_row.add_child(_cover_label)

	_rolls = _add_rich("Rolls", BODY_FONT_SIZE)
	_chain = _add_rich("Chain", BODY_FONT_SIZE)
	_result = _add_rich("Result", RESULT_FONT_SIZE)
	_footer = _add_rich("Footer", BODY_FONT_SIZE - 1)


func _add_rich(node_name: String, font_size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.name = node_name
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	r.add_theme_color_override("default_color", WhiteDwarfThemeScript.WH_PARCHMENT)
	_body.add_child(r)
	return r


## Fill the card from a ShootingController.current_hover_forecast and show it
## beside `anchor` (screen px).
func show_forecast(fc: Dictionary, anchor: Vector2) -> void:
	forecast = fc
	anchor_screen = anchor
	_set_rich(_title, "[b]%s[/b] [color=%s]→[/color] [b][color=%s]%s[/color][/b]" % [
		_esc(str(fc.get("weapon_name", "?"))), MUTED_HEX,
		_slot_hex(int(fc.get("target_owner", 0))), _esc(str(fc.get("target_name", "?")))])

	var in_cover: bool = bool(fc.get("in_cover", false))
	var is_torrent: bool = bool(fc.get("is_torrent", false))
	var bs_text: String = "Auto" if is_torrent else "%d+" % int(fc.get("bs", 0))
	if in_cover and not is_torrent:
		# The BS the cover left it with, in the cover row's colour.
		bs_text = "[color=#%s]%s[/color]" % [UIConstantsScript.MARGINAL_YELLOW.to_html(false), bs_text]
	_set_rich(_stats, "%s   %s   %s %s %s   %s   %s" % [
		_stat("A", _num(float(fc.get("attacks", 0.0)))),
		_stat("BS", bs_text),
		_stat("S", str(int(fc.get("s", 0)))),
		"[color=%s]vs[/color]" % LABEL_HEX,
		_stat("T", str(int(fc.get("t", 0)))),
		_stat("AP", _ap_text(int(fc.get("ap", 0)))),
		_stat("D", _esc(str(fc.get("damage_raw", "")))),
	])

	_cover_row.visible = in_cover and not is_torrent
	if _cover_row.visible:
		var plain_bs: int = int(fc.get("bs_no_cover", int(fc.get("bs", 1)) - 1))
		var cover_frac: float = float(fc.get("cover_fraction", 1.0))
		var who := "" if cover_frac >= 0.999 else " (from %d%% of the firing models)" % int(round(cover_frac * 100.0))
		_cover_label.text = "Benefit of cover%s: BS %d+ → %d+" % [who, plain_bs, plain_bs + int(fc.get("cover_bs_delta", 1))]
		_cover_icon.queue_redraw()

	var best_save: int = int(fc.get("best_save", 7))
	var save_text := "none"
	if best_save <= 6:
		save_text = "%d+" % best_save
		var inv: int = int(fc.get("invuln", 0))
		if inv > 0 and inv == best_save and inv < int(fc.get("modified_save", 7)):
			save_text += " inv"
	_set_rich(_rolls, "[color=%s]Hit[/color] [b]%s[/b]  ·  [color=%s]Wound[/color] [b]%s[/b]  ·  [color=%s]Save[/color] [b]%s[/b]" % [
		LABEL_HEX, str(fc.get("hit_display", "?")), LABEL_HEX, str(fc.get("wound_display", "?")), LABEL_HEX, save_text])

	_set_rich(_chain, "[color=%s]%s att → %s hit → %s wnd → %s unsaved[/color]" % [
		MUTED_HEX, _num(float(fc.get("attacks", 0.0))), "%.1f" % float(fc.get("expected_hits", 0.0)),
		"%.1f" % float(fc.get("expected_wounds", 0.0)), "%.1f" % float(fc.get("expected_unsaved", 0.0))])

	_set_rich(_result, "≈ [b][color=#%s]%.1f damage[/color][/b]  [color=%s](≈ %.1f models)[/color]" % [
		WhiteDwarfThemeScript.WH_GOLD.to_html(false), float(fc.get("expected_damage", 0.0)),
		MUTED_HEX, float(fc.get("expected_models_killed", 0.0))])

	var footer_lines: Array = []
	var tags: Array = []
	for t in fc.get("active_tags", []):
		if not str(t).begins_with("Cover"):  # the cover row says it
			tags.append(_esc(str(t)))
	if not tags.is_empty():
		footer_lines.append("[color=#8FA8C8]%s[/color]" % "  ·  ".join(tags))
	var n_weapons: int = int(fc.get("weapons_in_range", 1))
	if n_weapons > 1:
		var which := "Selected weapon" if str(fc.get("weapon_choice", "")) == "selected" else "Best of %d weapons" % n_weapons
		footer_lines.append("[color=%s]%s  ·  all %d weapons ≈ %.1f damage[/color]" % [
			MUTED_HEX, which, n_weapons, float(fc.get("all_weapons_damage", 0.0))])
	_footer.visible = not footer_lines.is_empty()
	_set_rich(_footer, "\n".join(footer_lines))

	visible = true
	_reposition()


## Keep the card beside a moving cursor.
func move_to_anchor(anchor: Vector2) -> void:
	anchor_screen = anchor
	if visible:
		_reposition()


func hide_forecast() -> void:
	forecast = {}
	visible = false


func _process(_delta: float) -> void:
	# Text changes resize the labels a frame later, and the stats card can open
	# under the cursor at any time: re-place every frame while showing.
	if visible:
		_reposition()


## Above-right of the cursor; if that leaves the viewport or covers the stats
## card, the first other corner that fits; failing all, clamped on screen.
func _reposition() -> void:
	reset_size()
	if not is_inside_tree():
		return  # placed once it is in the tree (next _process)
	var vp: Rect2 = get_viewport_rect()
	var sz: Vector2 = get_combined_minimum_size()
	var a := anchor_screen
	var candidates: Array = [
		Vector2(a.x + CURSOR_GAP.x, a.y - CURSOR_GAP.y - sz.y),       # above-right
		Vector2(a.x - CURSOR_GAP.x - sz.x, a.y - CURSOR_GAP.y - sz.y),  # above-left
		Vector2(a.x - CURSOR_GAP.x - sz.x, a.y + CURSOR_GAP.y + 8.0),   # below-left
		Vector2(a.x + CURSOR_GAP.x, a.y + CURSOR_GAP.y + 8.0),          # below-right
	]
	var avoid: Rect2 = _stats_card_rect()
	var chosen = null
	for c in candidates:
		var r := Rect2(c, sz)
		if not _fits(r, vp):
			continue
		if avoid.has_area() and r.intersects(avoid):
			continue
		chosen = c
		break
	if chosen == null:
		var c0: Vector2 = candidates[0]
		chosen = Vector2(
			clampf(c0.x, vp.position.x + EDGE_MARGIN, maxf(vp.position.x + EDGE_MARGIN, vp.end.x - EDGE_MARGIN - sz.x)),
			clampf(c0.y, vp.position.y + EDGE_MARGIN, maxf(vp.position.y + EDGE_MARGIN, vp.end.y - EDGE_MARGIN - sz.y)))
	global_position = chosen


func _fits(r: Rect2, vp: Rect2) -> bool:
	return r.position.x >= vp.position.x + EDGE_MARGIN and r.position.y >= vp.position.y + EDGE_MARGIN \
		and r.end.x <= vp.end.x - EDGE_MARGIN and r.end.y <= vp.end.y - EDGE_MARGIN


func _stats_card_rect() -> Rect2:
	var tip = get_node_or_null("/root/Main/TokenHoverTooltip")
	if tip is Control and tip.visible:
		return tip.get_global_rect()
	return Rect2()


func _set_rich(label: RichTextLabel, bbcode: String) -> void:
	label.clear()
	label.append_text(bbcode)


func _stat(label: String, value: String) -> String:
	return "[color=%s]%s[/color] [b]%s[/b]" % [LABEL_HEX, label, value]


func _ap_text(ap: int) -> String:
	# Profiles store AP as a negative number (-2 = AP2); AP 0 prints as 0.
	return "0" if ap == 0 else "-%d" % absi(ap)


func _num(x: float) -> String:
	if absf(x - roundf(x)) < 0.05:
		return "%d" % int(roundf(x))
	return "%.1f" % x


func _esc(text: String) -> String:
	# Unit / weapon names are data: keep a stray "[" from opening a BBCode tag.
	return text.replace("[", "[lb]")


func _slot_hex(owner: int) -> String:
	var color: Color = UIConstantsScript.FRIENDLY_PLAYER_TEAL if owner == 1 else UIConstantsScript.ENEMY_PLAYER_MAGENTA
	var ml = Engine.get_main_loop()
	var uic = ml.root.get_node_or_null("UIConstants") if ml is SceneTree else null
	if uic != null and uic.has_method("player_slot_color"):
		color = uic.player_slot_color(owner)
	return "#" + color.to_html(false)


## The cover icon: a small filled shield, in the cover row's colour.
class _ShieldIcon extends Control:
	const _UIC = preload("res://autoloads/UIConstants.gd")

	func _init() -> void:
		custom_minimum_size = Vector2(15, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var pts := PackedVector2Array([
			Vector2(1.0, 2.5), Vector2(w * 0.5, 0.5), Vector2(w - 1.0, 2.5),
			Vector2(w - 1.0, h * 0.55), Vector2(w * 0.5, h - 0.5), Vector2(1.0, h * 0.55),
		])
		draw_colored_polygon(pts, _UIC.MARGINAL_YELLOW)
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.85), 1.5, true)
		# A darker inner chevron so it reads as a shield, not a blob.
		draw_line(Vector2(w * 0.5, 4.0), Vector2(w * 0.5, h - 4.0), Color(0.0, 0.0, 0.0, 0.45), 1.5, true)
