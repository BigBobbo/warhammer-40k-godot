extends Node

# Installs a Unicode-symbols fallback font (DejaVu Sans) on every preloaded
# UI font in the project, including the project-wide default
# (`gui/theme/custom_font`), the per-faction display fonts, and Godot's
# built-in `ThemeDB.fallback_font`.
#
# Without this, glyphs like █ ░ ⚔ → ▶ ✓ ⚠ that are missing from Rajdhani /
# Caslon / MetalMania / Orbitron / the engine default render as `.notdef`
# hex boxes ("missing glyph" tofu). DejaVu Sans covers Block Elements
# (U+2580-259F), Misc Symbols (U+2600-26FF), arrows, math symbols, and
# Box Drawing - the common cases used across the UI.
#
# Font resources are shared (preload returns the same instance everywhere),
# so mutating .fallbacks here propagates to every existing and future label
# using those fonts. Fallback lookup happens at draw time, so labels
# already constructed before this autoload runs also pick up the fallback.


func _ready() -> void:
	var symbols_fallback: FontFile = FactionPalettes.FONT_SYMBOLS_FALLBACK
	if symbols_fallback == null:
		push_warning("FontFallbackInstaller: FONT_SYMBOLS_FALLBACK is null, skipping")
		return

	var fallback_chain: Array[Font] = [symbols_fallback]
	var targets: Array[Font] = [
		FactionPalettes.FONT_RAJDHANI_BOLD,
		FactionPalettes.FONT_RAJDHANI_SEMIBOLD,
		FactionPalettes.FONT_CASLON,
		FactionPalettes.FONT_METAL_MANIA,
		FactionPalettes.FONT_ORBITRON,
	]
	for font in targets:
		if font != null and font != symbols_fallback:
			font.fallbacks = fallback_chain

	# ThemeDB.fallback_font is the engine-built-in font that Controls use
	# when neither their own theme override nor any ancestor theme provides
	# one. Anything that slips past the Rajdhani default still gets the
	# symbols fallback.
	if ThemeDB.fallback_font != null:
		ThemeDB.fallback_font.fallbacks = fallback_chain
