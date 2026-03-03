class_name FactionPalettes
extends RefCounted

# Faction fonts - preloaded for letter-mode tokens
const FONT_CASLON = preload("res://fonts/CaslonAntique.ttf")
const FONT_METAL_MANIA = preload("res://fonts/MetalMania-Regular.ttf")
const FONT_ORBITRON = preload("res://fonts/Orbitron-Bold.ttf")

# UI font - used for map labels, objectives, banners, damage numbers
const FONT_RAJDHANI_BOLD = preload("res://fonts/Rajdhani-Bold.ttf")
const FONT_RAJDHANI_SEMIBOLD = preload("res://fonts/Rajdhani-SemiBold.ttf")

# Mapping from faction key to font resource
const FACTION_FONTS: Dictionary = {
	"space_marines": FONT_CASLON,
	"custodes": FONT_CASLON,
	"chaos": FONT_CASLON,
	"aeldari": FONT_CASLON,
	"tyranids": FONT_CASLON,
	"orks": FONT_METAL_MANIA,
	"tau": FONT_ORBITRON,
	"necrons": FONT_ORBITRON,
	"generic": FONT_CASLON,
}

# Faction color palettes - 8-12 colors each, curated for tabletop readability
const PALETTES: Dictionary = {
	"space_marines": [
		Color(0.15, 0.25, 0.55),  # Ultramarine blue
		Color(0.75, 0.6, 0.15),   # Imperial Fist yellow
		Color(0.55, 0.1, 0.1),    # Blood Angel red
		Color(0.2, 0.35, 0.2),    # Dark Angel green
		Color(0.1, 0.1, 0.1),     # Raven Guard black
		Color(0.7, 0.7, 0.72),    # Iron Hands silver
		Color(0.4, 0.2, 0.5),     # Emperor's Children purple
		Color(0.85, 0.55, 0.15),  # Imperial gold
		Color(0.3, 0.5, 0.6),     # Space Wolves grey-blue
		Color(0.6, 0.3, 0.15),    # Salamander bronze
	],
	"custodes": [
		Color(0.85, 0.7, 0.2),    # Auramite gold
		Color(0.65, 0.15, 0.15),  # Crimson
		Color(0.9, 0.8, 0.4),     # Bright gold
		Color(0.45, 0.1, 0.1),    # Dark red
		Color(0.7, 0.55, 0.15),   # Burnished gold
		Color(0.3, 0.05, 0.05),   # Deep burgundy
		Color(0.8, 0.65, 0.3),    # Pale gold
		Color(0.5, 0.2, 0.2),     # Warm maroon
	],
	"orks": [
		Color(0.2, 0.5, 0.15),    # Ork green
		Color(0.55, 0.45, 0.1),   # Yellow
		Color(0.6, 0.15, 0.1),    # Red (goes fasta)
		Color(0.35, 0.55, 0.2),   # Bright green
		Color(0.1, 0.3, 0.1),     # Dark green
		Color(0.5, 0.35, 0.15),   # Rusty orange
		Color(0.15, 0.15, 0.15),  # Black
		Color(0.7, 0.5, 0.2),     # Dirty yellow
		Color(0.3, 0.2, 0.1),     # Mud brown
	],
	"aeldari": [
		Color(0.85, 0.85, 0.85),  # Ghost white
		Color(0.15, 0.2, 0.5),    # Ulthwe blue-black
		Color(0.7, 0.2, 0.15),    # Saim-Hann red
		Color(0.2, 0.45, 0.2),    # Biel-Tan green
		Color(0.6, 0.5, 0.15),    # Iyanden yellow
		Color(0.5, 0.15, 0.5),    # Purple
		Color(0.1, 0.3, 0.4),     # Alaitoc blue
		Color(0.8, 0.6, 0.3),     # Wraithbone
	],
	"tyranids": [
		Color(0.5, 0.15, 0.4),    # Leviathan purple
		Color(0.6, 0.55, 0.35),   # Chitin tan
		Color(0.15, 0.35, 0.2),   # Behemoth green
		Color(0.65, 0.2, 0.15),   # Kraken red
		Color(0.1, 0.1, 0.3),     # Dark blue
		Color(0.4, 0.3, 0.15),    # Carapace brown
		Color(0.7, 0.35, 0.5),    # Flesh pink
		Color(0.25, 0.15, 0.35),  # Deep purple
	],
	"chaos": [
		Color(0.55, 0.1, 0.1),    # Khorne red
		Color(0.15, 0.3, 0.15),   # Nurgle green
		Color(0.5, 0.15, 0.5),    # Slaanesh pink
		Color(0.2, 0.25, 0.5),    # Tzeentch blue
		Color(0.1, 0.1, 0.1),     # Black Legion
		Color(0.65, 0.55, 0.15),  # Gold trim
		Color(0.45, 0.2, 0.1),    # Rust
		Color(0.6, 0.6, 0.6),     # Silver
	],
	"necrons": [
		Color(0.2, 0.2, 0.2),     # Dark metal
		Color(0.15, 0.5, 0.15),   # Gauss green
		Color(0.7, 0.7, 0.7),     # Silver
		Color(0.85, 0.7, 0.2),    # Gold
		Color(0.1, 0.3, 0.35),    # Teal
		Color(0.35, 0.35, 0.35),  # Gun metal
		Color(0.5, 0.5, 0.15),    # Sickly yellow
		Color(0.4, 0.2, 0.1),     # Bronze
	],
	"tau": [
		Color(0.8, 0.65, 0.4),    # T'au ochre
		Color(0.7, 0.7, 0.75),    # Vior'la white
		Color(0.15, 0.2, 0.35),   # Sa'cea blue
		Color(0.55, 0.3, 0.1),    # Burnt orange
		Color(0.6, 0.15, 0.1),    # Farsight red
		Color(0.3, 0.35, 0.2),    # Olive
		Color(0.1, 0.1, 0.15),    # Dark grey
		Color(0.5, 0.5, 0.3),     # Tan
	],
	"generic": [
		Color(0.2, 0.35, 0.6),    # Blue
		Color(0.6, 0.2, 0.15),    # Red
		Color(0.2, 0.5, 0.2),     # Green
		Color(0.7, 0.6, 0.15),    # Yellow
		Color(0.5, 0.15, 0.45),   # Purple
		Color(0.15, 0.45, 0.45),  # Teal
		Color(0.7, 0.4, 0.15),    # Orange
		Color(0.6, 0.6, 0.6),     # Silver
		Color(0.35, 0.2, 0.1),    # Brown
		Color(0.8, 0.4, 0.5),     # Pink
		Color(0.15, 0.15, 0.3),   # Navy
		Color(0.4, 0.5, 0.3),     # Olive
	],
}

# Fuzzy faction name matching - returns palette key
static func _match_faction(faction_name: String) -> String:
	var lower = faction_name.to_lower()
	if lower.find("custode") >= 0:
		return "custodes"
	if lower.find("space marine") >= 0 or lower.find("astartes") >= 0:
		return "space_marines"
	if lower.find("ork") >= 0:
		return "orks"
	if lower.find("aeldari") >= 0 or lower.find("eldar") >= 0 or lower.find("craftworld") >= 0:
		return "aeldari"
	if lower.find("tyranid") >= 0 or lower.find("nid") >= 0:
		return "tyranids"
	if lower.find("chaos") >= 0 or lower.find("heretic") >= 0 or lower.find("daemon") >= 0:
		return "chaos"
	if lower.find("necron") >= 0:
		return "necrons"
	if lower.find("tau") >= 0 or lower.find("t'au") >= 0:
		return "tau"
	return "generic"


static func get_palette(faction_name: String) -> Array:
	var key = _match_faction(faction_name)
	return PALETTES.get(key, PALETTES["generic"])


static func get_auto_color(faction_name: String, used_colors: Array) -> Color:
	var palette = get_palette(faction_name)
	# Return first unused palette color
	for color in palette:
		var is_used = false
		for used in used_colors:
			if used is Color and color.is_equal_approx(used):
				is_used = true
				break
		if not is_used:
			return color
	# All palette colors used - return first color as fallback
	return palette[0] if palette.size() > 0 else Color(0.4, 0.4, 0.4)


static func get_contrast_text_color(bg_color: Color) -> Color:
	# Perceived luminance using standard formula
	var luminance = 0.299 * bg_color.r + 0.587 * bg_color.g + 0.114 * bg_color.b
	if luminance > 0.5:
		return Color(0.05, 0.05, 0.05)  # Dark text on light bg
	else:
		return Color(0.95, 0.95, 0.95)  # Light text on dark bg


static func get_faction_font(faction_name: String) -> Font:
	var key = _match_faction(faction_name)
	return FACTION_FONTS.get(key, FONT_CASLON)
