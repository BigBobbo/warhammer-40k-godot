extends RefCounted

# M0 glyph helper (PRPs/steam_deck_controller_support.md §5.1): renders
# controller-button "chips" (a small dark badge with the button name) for the
# hint bar and, later, inline button labels. Programmatic rather than a
# texture pack so the chips scale with UI Scale and stay crisp on the Deck's
# 800p panel; a texture-glyph set can replace the visuals later without
# changing callers.
#
# Text uses the NEUTRAL_UI_PALE_WHITE slot (design guidelines §9 — no new
# hex literals for status/indicator paint). The slot is read off the script
# resource because autoload singletons are not reachable from static funcs.
const _UIConstants := preload("res://autoloads/UIConstants.gd")

# Display names for the Deck/Xbox-style layout. Keyed by semantic glyph id so
# a PlayStation/Switch variant is a table swap, not a caller change.
const GLYPHS := {
	"a": "A",
	"b": "B",
	"x": "X",
	"y": "Y",
	"lb": "LB",
	"rb": "RB",
	"lt": "LT",
	"rt": "RT",
	"ls": "LS",
	"rs": "RS",
	"l3": "L3",
	"r3": "R3",
	"l4": "L4",
	"r4": "R4",
	"dpad": "✚",
	"menu": "☰",
	"view": "⧉",
}


static func glyph_text(glyph_id: String) -> String:
	# Hint glyph ids name the CANONICAL layout ("a" = the select role, "menu" =
	# end phase, …). When the player has remapped roles in Settings › Controller,
	# show the button the role is ACTUALLY on now — PadBindings.display_glyph
	# returns "" for non-role ids (dpad / sticks / triggers), which fall back to
	# the static table below.
	var pb := _pad_bindings()
	if pb != null:
		var live: String = pb.display_glyph(glyph_id)
		if live != "":
			return live
	return GLYPHS.get(glyph_id, glyph_id.to_upper())


# Autoload lookup from a static func (singleton globals are not reachable
# here); null in bare headless harnesses that run without the autoload set.
static func _pad_bindings() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("PadBindings")
	return null


# Expand "{id}" tokens in a hint label to the button that glyph id currently
# sits on: "Hold {a}: Box Select" -> "Hold A: Box Select", and "Hold Y: Box
# Select" once the select role has been rebound onto Y in Settings › Controller.
# Lets a chip name a SECOND button in its label without hardcoding a layout —
# the hint sets stay const arrays and still follow a remap.
static func expand_label(label_text: String) -> String:
	if not label_text.contains("{"):
		return label_text
	var out := label_text
	for glyph_id in GLYPHS:
		var token := "{%s}" % glyph_id
		if out.contains(token):
			out = out.replace(token, glyph_text(glyph_id))
	return out


# A single "⟨glyph⟩ label" hint chip, e.g. [RS] Pan Camera.
static func make_chip(glyph_id: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)

	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	style.border_color = Color(0.95, 0.95, 0.95, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)

	var glyph_label := Label.new()
	glyph_label.text = glyph_text(glyph_id)
	glyph_label.add_theme_font_size_override("font_size", 13)
	glyph_label.add_theme_color_override("font_color", _UIConstants.NEUTRAL_UI_PALE_WHITE)
	badge.add_child(glyph_label)
	row.add_child(badge)

	var text_label := Label.new()
	text_label.text = expand_label(label_text)
	text_label.add_theme_font_size_override("font_size", 13)
	text_label.add_theme_color_override("font_color", Color(_UIConstants.NEUTRAL_UI_PALE_WHITE, 0.8))
	row.add_child(text_label)

	return row
