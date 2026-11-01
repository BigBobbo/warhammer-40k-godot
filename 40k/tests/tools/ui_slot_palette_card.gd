extends RefCounted

# T01 windowed-scenario helper (tests/scenarios/visual/T01_uiconstants_present
# .json). Renders the UIConstants slot table as an on-screen "palette card",
# then reads the captured screenshot back, so the scenario proves the slot
# colors and striped_pattern() actually reach the rendered frame — not just
# that the autoload returns the right values.
#
# Test-only, like tests/tools/pixel_diff.gd: game code never calls this.
#
#   build(tree)             -> int         slot rows rendered (7), -1 if no autoload
#   measure(tree, png_path) -> Dictionary  pixel metrics read from the screenshot
#   remove(tree)            -> bool        true once the card is gone
#
# Card layout (canvas units; 1 unit = 1 px at the default 1920x1080 window):
#   - one row per slot: swatch + "SLOT   #LIVE   doc #DOC   match|MISMATCH"
#     (live = the autoload, doc = docs/design_guidelines_2d_topdown.md §9)
#   - the §9 collision case side by side: a solid faction-yellow fill next to
#     striped_pattern(Color.YELLOW) tiled at 1x, then the same texture at 4x.

const DOC_TABLE := preload("res://tests/tools/ui_slot_doc_table.gd")

const CARD_NAME := "T01SlotPaletteCard"
const CARD_RECT := Rect2(24, 24, 600, 652)  # keep in sync with the scenario's "palette_card" region
const BACKING := Color(0.16, 0.16, 0.18, 1.0)
const SLOT_ORDER := [
	"FRIENDLY_PLAYER_TEAL", "ENEMY_PLAYER_MAGENTA", "WARNING_ORANGE",
	"CONFIRMED_GREEN", "MARGINAL_YELLOW", "INVALID_RED", "NEUTRAL_UI_PALE_WHITE",
]
const STRIPE_NODES := ["FactionYellowSolid", "SemanticYellowStriped", "SemanticYellowStripedZoom"]


static func build(tree: SceneTree) -> int:
	remove(tree)
	var ui: Node = tree.root.get_node_or_null("UIConstants")
	if ui == null:
		return -1
	var doc_slots: Dictionary = DOC_TABLE.parse().get("slots", {})
	var slots: Dictionary = ui.all_slots()
	var pale: Color = ui.NEUTRAL_UI_PALE_WHITE

	var layer := CanvasLayer.new()
	layer.name = CARD_NAME
	layer.layer = 128  # above the menu / HUD

	var bg := ColorRect.new()
	bg.name = "Backing"
	bg.color = BACKING
	bg.position = CARD_RECT.position
	bg.size = CARD_RECT.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	_label(layer, "Title", "UIConstants slots: live autoload vs doc §9", Vector2(40, 32), 18, pale)

	var rows := 0
	for i in range(SLOT_ORDER.size()):
		var n: String = SLOT_ORDER[i]
		if not slots.has(n):
			continue
		var c: Color = slots[n]
		var y := 72 + i * 38
		var sw := ColorRect.new()
		sw.name = "Swatch_" + n
		sw.color = c
		sw.position = Vector2(40, y)
		sw.size = Vector2(56, 28)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(sw)
		var live := c.to_html(false).to_upper()
		var doc_hex := str(doc_slots.get(n, "------")).to_upper()
		_label(layer, "Label_" + n, "%s   #%s   doc #%s   %s" % [
			n, live, doc_hex, "match" if doc_hex == live else "MISMATCH"],
			Vector2(108, y + 5), 14, pale)
		rows += 1

	# §9 anti-pattern: a yellow faction and semantic yellow must stay
	# distinguishable — same hue, told apart by the hatch texture.
	_label(layer, "SolidCaption", "Faction yellow (solid)", Vector2(40, 344), 14, pale)
	_label(layer, "StripedCaption", "striped_pattern(Color.YELLOW)", Vector2(320, 344), 14, pale)
	var solid := ColorRect.new()
	solid.name = "FactionYellowSolid"
	solid.color = Color.YELLOW
	solid.position = Vector2(40, 370)
	solid.size = Vector2(256, 64)
	solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(solid)
	var tex: Texture2D = ui.striped_pattern(Color.YELLOW)
	layer.add_child(_tiled(tex, "SemanticYellowStriped", Vector2(320, 370), Vector2(256, 64), 1))
	_label(layer, "ZoomCaption", "same texture at 4x (16 px tile, 4 px stripes)", Vector2(40, 446), 14, pale)
	layer.add_child(_tiled(tex, "SemanticYellowStripedZoom", Vector2(40, 472), Vector2(134, 48), 4))

	tree.root.add_child(layer)
	return rows


# Reads the screenshot at png_path (a user:// or absolute path) and reports,
# for each stripe node, the yellow<->non-yellow transitions and the yellow
# share along the horizontal line through its middle, plus how many slot
# swatches render their slot color (within 2/255 per channel). The tolerance
# is needed: TEAL/MAGENTA's 0.70 channel is exactly 178.5/255 — to_html()
# rounds it to 0xB3, the GL renderer writes 0xB2 (measured 2026-10-30).
static func measure(tree: SceneTree, png_path: String) -> Dictionary:
	var card: Node = tree.root.get_node_or_null(CARD_NAME)
	if card == null:
		return {"error": "palette card not built"}
	var img := Image.load_from_file(ProjectSettings.globalize_path(png_path))
	if img == null or img.is_empty():
		return {"error": "cannot read %s" % png_path}
	# Screenshot pixels per canvas unit (1.0 at the default 1920x1080 window).
	var k := float(img.get_width()) / tree.root.get_visible_rect().size.x
	var out := {"scale": k}
	for node_name in STRIPE_NODES:
		var row := _scan_row(img, (card.get_node(node_name) as Control).get_global_rect(), k)
		out[node_name + "_transitions"] = row["transitions"]
		out[node_name + "_yellow_pct"] = row["yellow_pct"]
	var slots: Dictionary = tree.root.get_node("UIConstants").all_slots()
	var matches := 0
	for n in slots:
		var sw := card.get_node_or_null("Swatch_" + n) as Control
		if sw == null:
			continue
		var px := img.get_pixelv(Vector2i((sw.get_global_rect().get_center() * k).floor()))
		var want: Color = slots[n]
		if absi(px.r8 - want.r8) <= 2 and absi(px.g8 - want.g8) <= 2 and absi(px.b8 - want.b8) <= 2:
			matches += 1
	out["slot_swatch_matches"] = matches
	return out


static func remove(tree: SceneTree) -> bool:
	var card: Node = tree.root.get_node_or_null(CARD_NAME)
	if card != null:
		tree.root.remove_child(card)
		card.free()
	return tree.root.get_node_or_null(CARD_NAME) == null


static func _scan_row(img: Image, r: Rect2, k: float) -> Dictionary:
	var y := int((r.position.y + r.size.y * 0.5) * k)
	var x0 := int(ceil(r.position.x * k))
	var x1 := int(floor((r.position.x + r.size.x) * k))
	var yellow := 0
	var transitions := 0
	var prev := -1
	for x in range(x0, x1):
		var c := img.get_pixel(x, y)
		var on := 1 if (c.r8 > 200 and c.g8 > 200 and c.b8 < 80) else 0
		yellow += on
		if prev != -1 and on != prev:
			transitions += 1
		prev = on
	return {"transitions": transitions,
		"yellow_pct": int(round(100.0 * yellow / float(maxi(1, x1 - x0))))}


static func _tiled(tex: Texture2D, node_name: String, pos: Vector2, size: Vector2, zoom: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = node_name
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.position = pos
	tr.size = size
	tr.scale = Vector2(zoom, zoom)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func _label(parent: Node, node_name: String, text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var lb := Label.new()
	lb.name = node_name
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", font_size)
	lb.add_theme_color_override("font_color", color)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lb)
	return lb
