extends SceneTree

# Regression: every PhaseTransitionBanner phase icon must be a glyph that ships
# in a BUNDLED font (Rajdhani-Bold, DejaVuSans, or NotoColorEmoji).
#
# The SHOOTING PHASE banner shipped with U+2316 (POSITION INDICATOR / crosshair)
# flanking the title. That codepoint is in NONE of the bundled fonts, so it only
# rendered when the player's OS happened to supply the glyph via system-font
# fallback; everyone else saw a .notdef "missing glyph" box (a rectangle showing
# "2316"). The other phase icons all live in the bundled DejaVuSans, which is why
# only the shooting banner was broken.
#
# `Font.has_char()` checks the font resource and its explicit `.fallbacks` only —
# it deliberately does NOT consult the OS system-font fallback. That is exactly
# the property we want: the glyph must ship with the game, not depend on whatever
# fonts a given machine has installed.
#
# The test parses the phase->icon map straight out of PhaseTransitionBanner.gd
# source (rather than instantiating the class, which pulls in autoload globals
# that a `-s` SceneTree run cannot resolve) and loads the fonts directly, so it
# has no autoload dependencies. It auto-discovers every phase icon, guarding all
# phases (present + future) from regressing to a non-bundled glyph.
#
# Usage: godot --headless --path . -s tests/test_phase_banner_icons.gd

const BANNER_SRC := "res://scripts/PhaseTransitionBanner.gd"
const BUNDLED_FONTS := [
	"res://fonts/Rajdhani-Bold.ttf",
	"res://fonts/DejaVuSans.ttf",
	"res://fonts/NotoColorEmoji.ttf",
]

var passed := 0
var failed := 0
var _fonts: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	create_timer(0.1).timeout.connect(_run_tests)

# True if the codepoint is drawable from a font that ships with the game.
func _bundled_has(cp: int) -> bool:
	for f in _fonts:
		if f != null and f.has_char(cp):
			return true
	return false

# Decode a GDScript string-literal body (as it appears in source) into its
# codepoints, expanding \uXXXX escapes and passing literal chars through.
func _codepoints_of(raw: String) -> Array:
	var cps: Array = []
	var i := 0
	while i < raw.length():
		if raw[i] == "\\" and i + 6 <= raw.length() and raw[i + 1] == "u":
			cps.append(raw.substr(i + 2, 4).hex_to_int())
			i += 6
		else:
			cps.append(raw.unicode_at(i))
			i += 1
	return cps

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_phase_banner_icons ===\n")

	for path in BUNDLED_FONTS:
		_fonts.append(load(path))
	_check("bundled fonts loaded", _fonts.size() == 3 and not _fonts.has(null))

	# Pull every `"icon": "..."` value out of the banner source.
	var f := FileAccess.open(BANNER_SRC, FileAccess.READ)
	_check("banner source readable", f != null)
	if f == null:
		_finish()
		return
	var src := f.get_as_text()
	f.close()

	var re := RegEx.new()
	re.compile('"icon"\\s*:\\s*"([^"]+)"')
	var matches := re.search_all(src)
	_check("found phase icons in source (>= 10)", matches.size() >= 10,
		"only found %d" % matches.size())

	var saw_bullseye := false
	for m in matches:
		var raw: String = m.get_string(1)
		for cp in _codepoints_of(raw):
			if cp == 0x25CE:
				saw_bullseye = true
			# ASCII (e.g. the "?" default) is always drawable; only assert on
			# the symbol glyphs that actually depend on font coverage.
			if cp < 0x80:
				continue
			_check("icon U+%04X is in a bundled font" % cp, _bundled_has(cp),
				"absent from Rajdhani/DejaVuSans/NotoColorEmoji -> renders as a .notdef box")

	# The shooting fix specifically: the bundled bullseye (U+25CE) is now used...
	_check("SHOOTING banner uses bundled U+25CE (BULLSEYE)", saw_bullseye,
		"expected the shooting icon to be U+25CE")
	# ...and the old crosshair U+2316 is genuinely NOT bundled, documenting the
	# root cause (the per-icon loop above already fails if any icon uses it).
	_check("old crosshair U+2316 is NOT in any bundled font (why it tofu'd)",
		not _bundled_has(0x2316))

	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
