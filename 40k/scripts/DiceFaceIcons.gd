extends RefCounted
class_name DiceFaceIcons

# DiceFaceIcons - generates small d6 face textures (rounded square + pips) for
# embedding inline in RichTextLabels via add_image(). Mirrors the look of
# DiceRowVisual (the Control-drawn dice in the game log) so dice appear
# consistent across the UI. Textures are cached per (value, background color).

const TEX_SIZE := 36          # rendered at 2x for crispness; embed at ~18px
const CORNER := 6.0
const PIP_RADIUS := 3.6
const BORDER := 2

# Default palette (matches DiceRowVisual / pass-fail semantics)
const COLOR_CRITICAL := Color(1.0, 0.84, 0.0)   # natural 6 / crit
const COLOR_FUMBLE := Color(0.9, 0.15, 0.15)    # natural 1
const COLOR_SUCCESS := Color(0.2, 0.75, 0.2)    # passed threshold
const COLOR_FAIL := Color(0.5, 0.18, 0.18)      # failed threshold
const COLOR_NEUTRAL := Color(0.25, 0.45, 0.7)   # no threshold context

static var _cache: Dictionary = {}

static func get_face(value: int, bg: Color) -> ImageTexture:
	var key := "%d_%s" % [value, bg.to_html(true)]
	if _cache.has(key):
		return _cache[key]
	var tex := _make_face(value, bg)
	_cache[key] = tex
	return tex

static func color_for(value: int, threshold: int, use_threshold: bool = true, crit_threshold: int = 6) -> Color:
	# Standard d6 coloring shared with the game log: crit (gold), fumble (red),
	# else pass/fail by threshold, else neutral.
	if value >= crit_threshold:
		return COLOR_CRITICAL
	if value == 1:
		return COLOR_FUMBLE
	if use_threshold and threshold > 0:
		if value >= threshold:
			return COLOR_SUCCESS
		return COLOR_FAIL
	return COLOR_NEUTRAL

static func _make_face(value: int, bg: Color) -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var border_col := Color(0.0, 0.0, 0.0, 0.6)
	# Pips are dark on light faces (gold), white otherwise.
	var pip_col := Color(0.1, 0.1, 0.1) if bg.get_luminance() > 0.6 else Color(1, 1, 1)

	# Body: rounded square with a 1px-ish dark border.
	for y in range(TEX_SIZE):
		for x in range(TEX_SIZE):
			if not _in_rounded_rect(x, y, TEX_SIZE, CORNER):
				continue
			if _in_rounded_rect(x, y, TEX_SIZE, CORNER, BORDER):
				img.set_pixel(x, y, bg)
			else:
				img.set_pixel(x, y, border_col)

	# Pips
	var c := TEX_SIZE * 0.5
	var off := TEX_SIZE * 0.27
	var pip_positions := _pip_positions(value, c, off)
	for p in pip_positions:
		_draw_disc(img, p.x, p.y, PIP_RADIUS, pip_col)

	return ImageTexture.create_from_image(img)

static func _pip_positions(value: int, c: float, off: float) -> Array:
	var pts := []
	if value == 1 or value == 3 or value == 5:
		pts.append(Vector2(c, c))
	if value >= 2:
		pts.append(Vector2(c - off, c - off))
		pts.append(Vector2(c + off, c + off))
	if value >= 4:
		pts.append(Vector2(c + off, c - off))
		pts.append(Vector2(c - off, c + off))
	if value == 6:
		pts.append(Vector2(c - off, c))
		pts.append(Vector2(c + off, c))
	return pts

static func _in_rounded_rect(x: int, y: int, size: int, corner: float, inset: int = 0) -> bool:
	var lo := float(inset)
	var hi := float(size - 1 - inset)
	var fx := float(x)
	var fy := float(y)
	if fx < lo or fx > hi or fy < lo or fy > hi:
		return false
	var r := corner - float(inset)
	if r <= 0.0:
		return true
	# Check the four corner quadrants against the corner radius.
	var cx := clampf(fx, lo + r, hi - r)
	var cy := clampf(fy, lo + r, hi - r)
	var dx := fx - cx
	var dy := fy - cy
	return dx * dx + dy * dy <= r * r

static func _draw_disc(img: Image, cx: float, cy: float, radius: float, col: Color) -> void:
	var r2 := radius * radius
	var x0 := int(floor(cx - radius))
	var x1 := int(ceil(cx + radius))
	var y0 := int(floor(cy - radius))
	var y1 := int(ceil(cy + radius))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, col)
