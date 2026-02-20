extends RefCounted
class_name WeaponKeywordIcons

# WeaponKeywordIcons - Generates small color-coded icon badges for weapon keywords
# T5-V7: Visual keyword icons displayed next to weapon names in the shooting UI
#
# Each keyword gets a small colored badge with a symbolic letter/shape.
# Multiple keyword badges are composited into a single horizontal strip texture.
# This replaces the text-based [T/P/LH] indicators with visually distinct icons.

const BADGE_SIZE := 16  # Width and height of each badge
const BADGE_GAP := 2    # Gap between badges
const BADGE_RADIUS := 3 # Corner rounding (visual only, drawn as rect)

# Keyword color palette - each keyword has a distinct, recognizable color
# Colors are chosen to be visually distinct and match thematic associations
const KEYWORD_COLORS := {
	"torrent": Color(1.0, 0.4, 0.1),        # Orange-red (fire/flame)
	"one_shot": Color(0.6, 0.6, 0.6),        # Gray (single use)
	"pistol": Color(0.3, 0.6, 1.0),          # Blue (close combat flexibility)
	"assault": Color(1.0, 0.2, 0.2),          # Red (aggressive advance)
	"heavy": Color(0.9, 0.75, 0.0),           # Gold/yellow (steady/planted)
	"rapid_fire": Color(0.2, 0.8, 0.2),       # Green (extra shots)
	"lethal_hits": Color(1.0, 0.84, 0.0),     # Bright gold (lethal/critical)
	"sustained_hits": Color(0.8, 0.4, 1.0),   # Purple (sustained damage)
	"devastating_wounds": Color(1.0, 0.0, 0.3), # Crimson (devastating)
	"blast": Color(1.0, 0.6, 0.0),            # Amber (explosion)
}

# Badge label text (short, fits in small badge)
const KEYWORD_LABELS := {
	"torrent": "T",
	"one_shot": "1",
	"pistol": "P",
	"assault": "A",
	"heavy": "H",
	"rapid_fire": "RF",
	"lethal_hits": "LH",
	"sustained_hits": "SH",
	"devastating_wounds": "DW",
	"blast": "B",
}

# Full keyword names for tooltip text
const KEYWORD_NAMES := {
	"torrent": "TORRENT – Auto-hits, no hit roll needed",
	"one_shot": "ONE SHOT – Can only fire once per battle",
	"pistol": "PISTOL – Can fire in Engagement Range",
	"assault": "ASSAULT – Can fire after Advancing",
	"heavy": "HEAVY – +1 to hit if Remained Stationary",
	"rapid_fire": "RAPID FIRE – Extra attacks at half range",
	"lethal_hits": "LETHAL HITS – Unmodified 6 to hit auto-wounds",
	"sustained_hits": "SUSTAINED HITS – Bonus hits on critical hits",
	"devastating_wounds": "DEVASTATING WOUNDS – Mortal wounds on critical wound rolls",
	"blast": "BLAST – Bonus attacks vs larger units",
}

# Cache for generated textures to avoid recreating them every frame
static var _icon_cache: Dictionary = {}
static var _strip_cache: Dictionary = {}


## Build a list of active keyword keys for a given weapon.
## Returns an Array of keyword string keys (e.g. ["assault", "rapid_fire", "lethal_hits"])
static func get_weapon_keywords(weapon_id: String) -> Array:
	var keywords := []

	if RulesEngine.is_torrent_weapon(weapon_id):
		keywords.append("torrent")
	if RulesEngine.is_one_shot_weapon(weapon_id):
		keywords.append("one_shot")
	if RulesEngine.is_pistol_weapon(weapon_id):
		keywords.append("pistol")
	if RulesEngine.is_assault_weapon(weapon_id):
		keywords.append("assault")
	if RulesEngine.is_heavy_weapon(weapon_id):
		keywords.append("heavy")
	if RulesEngine.get_rapid_fire_value(weapon_id) > 0:
		keywords.append("rapid_fire")
	if RulesEngine.has_lethal_hits(weapon_id):
		keywords.append("lethal_hits")
	if RulesEngine.get_sustained_hits_display(weapon_id) != "":
		keywords.append("sustained_hits")
	if RulesEngine.has_devastating_wounds(weapon_id):
		keywords.append("devastating_wounds")
	if RulesEngine.is_blast_weapon(weapon_id):
		keywords.append("blast")

	return keywords


## Generate a single keyword badge as an Image (BADGE_SIZE x BADGE_SIZE).
## The badge is a colored rounded rectangle with a 1px darker border and white text.
static func _generate_badge_image(keyword: String) -> Image:
	if _icon_cache.has(keyword):
		return _icon_cache[keyword]

	var img := Image.create(BADGE_SIZE, BADGE_SIZE, false, Image.FORMAT_RGBA8)
	var base_color: Color = KEYWORD_COLORS.get(keyword, Color(0.5, 0.5, 0.5))
	var border_color := base_color.darkened(0.4)

	# Fill with transparent
	img.fill(Color(0, 0, 0, 0))

	# Draw rounded rectangle background
	for y in range(BADGE_SIZE):
		for x in range(BADGE_SIZE):
			var is_border := false
			var is_inside := false

			# Simple rounded rect: skip corners for rounding effect
			var in_corner := false
			if (x < BADGE_RADIUS and y < BADGE_RADIUS):
				# Top-left corner
				var dx := BADGE_RADIUS - x - 1
				var dy := BADGE_RADIUS - y - 1
				if dx * dx + dy * dy > BADGE_RADIUS * BADGE_RADIUS:
					continue
				in_corner = true
			elif (x >= BADGE_SIZE - BADGE_RADIUS and y < BADGE_RADIUS):
				# Top-right corner
				var dx := x - (BADGE_SIZE - BADGE_RADIUS)
				var dy := BADGE_RADIUS - y - 1
				if dx * dx + dy * dy > BADGE_RADIUS * BADGE_RADIUS:
					continue
				in_corner = true
			elif (x < BADGE_RADIUS and y >= BADGE_SIZE - BADGE_RADIUS):
				# Bottom-left corner
				var dx := BADGE_RADIUS - x - 1
				var dy := y - (BADGE_SIZE - BADGE_RADIUS)
				if dx * dx + dy * dy > BADGE_RADIUS * BADGE_RADIUS:
					continue
				in_corner = true
			elif (x >= BADGE_SIZE - BADGE_RADIUS and y >= BADGE_SIZE - BADGE_RADIUS):
				# Bottom-right corner
				var dx := x - (BADGE_SIZE - BADGE_RADIUS)
				var dy := y - (BADGE_SIZE - BADGE_RADIUS)
				if dx * dx + dy * dy > BADGE_RADIUS * BADGE_RADIUS:
					continue
				in_corner = true

			# Border (1px edge)
			if x == 0 or x == BADGE_SIZE - 1 or y == 0 or y == BADGE_SIZE - 1:
				is_border = true
			else:
				is_inside = true

			if is_border:
				img.set_pixel(x, y, border_color)
			elif is_inside:
				img.set_pixel(x, y, base_color)

	# Draw the label letter(s) as simple pixel patterns
	var label: String = KEYWORD_LABELS.get(keyword, "?")
	_draw_text_on_image(img, label, Color.WHITE)

	_icon_cache[keyword] = img
	return img


## Draw simple text characters onto a badge image.
## Uses a minimal pixel font for 1-2 character labels.
static func _draw_text_on_image(img: Image, text: String, color: Color) -> void:
	# For single characters, center them. For 2 chars, offset slightly.
	if text.length() == 1:
		_draw_char(img, text[0], 4, 3, color)
	elif text.length() == 2:
		_draw_char(img, text[0], 1, 3, color)
		_draw_char(img, text[1], 8, 3, color)
	else:
		# 3+ chars - use smaller spacing
		var start_x := 0
		for i in range(mini(text.length(), 3)):
			_draw_char(img, text[i], start_x, 3, color, true)
			start_x += 5


## Draw a single character at (ox, oy) using a minimal 7x10 pixel font.
## If small=true, uses a 4x7 font for tighter packing.
static func _draw_char(img: Image, ch: String, ox: int, oy: int, color: Color, small: bool = false) -> void:
	var pattern: Array = _get_char_pattern(ch, small)
	for row_idx in range(pattern.size()):
		var row: String = pattern[row_idx]
		for col_idx in range(row.length()):
			if row[col_idx] == "#":
				var px := ox + col_idx
				var py := oy + row_idx
				if px >= 1 and px < BADGE_SIZE - 1 and py >= 1 and py < BADGE_SIZE - 1:
					img.set_pixel(px, py, color)


## Returns a pixel art pattern for a character.
## Each string in the array represents a row; '#' = filled pixel.
static func _get_char_pattern(ch: String, small: bool = false) -> Array:
	if small:
		return _get_small_char_pattern(ch)

	# 7-wide x 10-tall patterns (but we only use ~8 rows to fit in badge)
	match ch:
		"T":
			return [
				"#######",
				"  ###  ",
				"  ###  ",
				"  ###  ",
				"  ###  ",
				"  ###  ",
				"  ###  ",
				"  ###  ",
			]
		"P":
			return [
				"#####  ",
				"##  ## ",
				"##  ## ",
				"#####  ",
				"##     ",
				"##     ",
				"##     ",
				"##     ",
			]
		"A":
			return [
				"  ###  ",
				" ## ## ",
				"##   ##",
				"##   ##",
				"#######",
				"##   ##",
				"##   ##",
				"##   ##",
			]
		"H":
			return [
				"##   ##",
				"##   ##",
				"##   ##",
				"#######",
				"##   ##",
				"##   ##",
				"##   ##",
				"##   ##",
			]
		"R":
			return [
				"#####  ",
				"##  ## ",
				"##  ## ",
				"#####  ",
				"## ##  ",
				"##  ## ",
				"##  ## ",
				"##   ##",
			]
		"F":
			return [
				"#######",
				"##     ",
				"##     ",
				"#####  ",
				"##     ",
				"##     ",
				"##     ",
				"##     ",
			]
		"L":
			return [
				"##     ",
				"##     ",
				"##     ",
				"##     ",
				"##     ",
				"##     ",
				"##     ",
				"#######",
			]
		"S":
			return [
				" ##### ",
				"##     ",
				"##     ",
				" ##### ",
				"     ##",
				"     ##",
				"     ##",
				" ##### ",
			]
		"D":
			return [
				"####   ",
				"##  ## ",
				"##   ##",
				"##   ##",
				"##   ##",
				"##   ##",
				"##  ## ",
				"####   ",
			]
		"W":
			return [
				"##   ##",
				"##   ##",
				"##   ##",
				"## # ##",
				"## # ##",
				"## # ##",
				" ## ## ",
				"  ###  ",
			]
		"B":
			return [
				"#####  ",
				"##  ## ",
				"##  ## ",
				"#####  ",
				"##  ## ",
				"##  ## ",
				"##  ## ",
				"#####  ",
			]
		"1":
			return [
				"  ##   ",
				" ###   ",
				"  ##   ",
				"  ##   ",
				"  ##   ",
				"  ##   ",
				"  ##   ",
				" ####  ",
			]
		_:
			return [
				" ##### ",
				"##   ##",
				"    ## ",
				"   ##  ",
				"  ##   ",
				"  ##   ",
				"       ",
				"  ##   ",
			]


## Smaller 4-wide x 7-tall character patterns for tight labels
static func _get_small_char_pattern(ch: String) -> Array:
	match ch:
		"R":
			return ["###  ", "# # ", "###  ", "# #  ", "# # "]
		"F":
			return ["#### ", "#    ", "###  ", "#    ", "#    "]
		"D":
			return ["###  ", "#  # ", "#  # ", "#  # ", "###  "]
		"W":
			return ["# # #", "# # #", "# # #", " # # ", " # # "]
		_:
			return _get_char_pattern(ch, false)


## Generate a horizontal strip image containing all keyword badges for a weapon.
## Returns null if the weapon has no keywords.
static func generate_keyword_strip(weapon_id: String) -> ImageTexture:
	var keywords := get_weapon_keywords(weapon_id)
	if keywords.is_empty():
		return null

	# Check cache
	var cache_key := "/".join(keywords)
	if _strip_cache.has(cache_key):
		return _strip_cache[cache_key]

	# Calculate strip dimensions
	var total_width := keywords.size() * BADGE_SIZE + (keywords.size() - 1) * BADGE_GAP
	var strip_img := Image.create(total_width, BADGE_SIZE, false, Image.FORMAT_RGBA8)
	strip_img.fill(Color(0, 0, 0, 0))

	# Composite each badge onto the strip
	var x_offset := 0
	for keyword in keywords:
		var badge := _generate_badge_image(keyword)
		# Blit badge onto strip at x_offset
		strip_img.blit_rect(badge, Rect2i(0, 0, BADGE_SIZE, BADGE_SIZE), Vector2i(x_offset, 0))
		x_offset += BADGE_SIZE + BADGE_GAP

	var texture := ImageTexture.create_from_image(strip_img)
	_strip_cache[cache_key] = texture
	return texture


## Build a tooltip string listing all keywords with their full descriptions.
static func get_keyword_tooltip(weapon_id: String) -> String:
	var keywords := get_weapon_keywords(weapon_id)
	if keywords.is_empty():
		return ""

	var lines := PackedStringArray()
	for keyword in keywords:
		var name_desc: String = KEYWORD_NAMES.get(keyword, keyword)
		# Add rapid fire value or sustained hits value where applicable
		if keyword == "rapid_fire":
			var rf_val := RulesEngine.get_rapid_fire_value(weapon_id)
			name_desc = "RAPID FIRE %d – Extra %d attacks at half range" % [rf_val, rf_val]
		elif keyword == "sustained_hits":
			var sh_display := RulesEngine.get_sustained_hits_display(weapon_id)
			name_desc = "SUSTAINED HITS %s – Bonus hits on critical hits" % sh_display

		lines.append(name_desc)

	return "\n".join(lines)


## Convenience: apply keyword icon and tooltip to a TreeItem.
## Sets the icon on column 0 and the tooltip with keyword descriptions.
static func apply_to_tree_item(weapon_item: TreeItem, weapon_id: String) -> void:
	var icon := generate_keyword_strip(weapon_id)
	if icon:
		weapon_item.set_icon(0, icon)
		weapon_item.set_icon_max_width(0, icon.get_width())

	var tooltip := get_keyword_tooltip(weapon_id)
	if tooltip != "":
		weapon_item.set_tooltip_text(0, tooltip)


## Clear the caches (call when weapons change or on cleanup).
static func clear_cache() -> void:
	_icon_cache.clear()
	_strip_cache.clear()
