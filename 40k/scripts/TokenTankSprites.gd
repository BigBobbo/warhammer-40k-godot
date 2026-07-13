extends RefCounted
class_name TokenTankSprites

# Maps a unit's faction (with player-slot fallback) to one of the Kenney
# top-down tank sprite colorways bundled under res://assets/tilepack/, so
# VEHICLE tokens render as actual vehicles instead of lettered discs.
# All textures are CC0 (see assets/tilepack/CREDITS.md).

const _BODIES := {
	"blue": "res://assets/tilepack/tankBody_blue_outline.png",
	"red": "res://assets/tilepack/tankBody_red_outline.png",
	"green": "res://assets/tilepack/tankBody_green_outline.png",
	"sand": "res://assets/tilepack/tankBody_sand_outline.png",
	"dark": "res://assets/tilepack/tankBody_dark_outline.png",
}

const _BARRELS := {
	"blue": "res://assets/tilepack/tankBlue_barrel2_outline.png",
	"red": "res://assets/tilepack/tankRed_barrel2_outline.png",
	"green": "res://assets/tilepack/tankGreen_barrel2_outline.png",
	"sand": "res://assets/tilepack/tankSand_barrel2_outline.png",
	"dark": "res://assets/tilepack/tankDark_barrel2_outline.png",
}

# Oversized hull for TITANIC vehicles (Stompa, super-heavies).
const _BODY_TITANIC := "res://assets/tilepack/tankBody_darkLarge_outline.png"

static var _cache: Dictionary = {}


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Pick a colorway from the faction name; falls back to the player slot
## (P1 blue, P2 red) when the faction doesn't map to anything obvious.
static func colorway_for(faction: String, owner_player: int) -> String:
	var f := faction.to_lower()
	if f.contains("ork"):
		return "green"
	if f.contains("custodes") or f.contains("talons") or f.contains("sisters"):
		return "sand"
	if f.contains("chaos") or f.contains("khorne") or f.contains("blood"):
		return "red"
	if f.contains("necron") or f.contains("black templar") or f.contains("raven"):
		return "dark"
	if f.contains("marine") or f.contains("ultra") or f.contains("imperial") or f.contains("guard"):
		return "blue"
	return "blue" if owner_player == 1 else "red"


static func body_texture(faction: String, owner_player: int, is_titanic: bool = false) -> Texture2D:
	if is_titanic:
		return _load(_BODY_TITANIC)
	return _load(_BODIES[colorway_for(faction, owner_player)])


static func barrel_texture(faction: String, owner_player: int) -> Texture2D:
	return _load(_BARRELS[colorway_for(faction, owner_player)])
