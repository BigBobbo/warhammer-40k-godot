extends Node

# UIConstants — strict color-slot allocation per
# 40k/docs/design_guidelines_2d_topdown.md §9.
#
# Every UI script that paints an overlay, ring, or status indicator MUST
# reference one of these slots instead of writing a hex literal. The slot
# table is the single source of truth for "which color means what".
#
# Faction colors stay per-army (read from army data); they are intentionally
# NOT in this table.

# ---------------------------------------------------------------------------
# Slot table (canonical hex values, fully opaque)
# ---------------------------------------------------------------------------

const FRIENDLY_PLAYER_TEAL     := Color(0.00, 0.70, 0.70, 1.0)  # #00B3B3
const ENEMY_PLAYER_MAGENTA     := Color(0.90, 0.20, 0.70, 1.0)  # #E633B3
const WARNING_ORANGE           := Color(1.00, 0.55, 0.00, 1.0)  # #FF8C00
const CONFIRMED_GREEN          := Color(0.20, 0.85, 0.30, 1.0)  # #33D94D
const MARGINAL_YELLOW          := Color(0.95, 0.85, 0.15, 1.0)  # #F2D926
const INVALID_RED              := Color(0.90, 0.20, 0.20, 1.0)  # #E63333
const NEUTRAL_UI_PALE_WHITE    := Color(0.95, 0.95, 0.95, 1.0)  # #F2F2F2

# Slot-name table for round-trip lookups (used by assertions).
const _SLOT_TABLE := {
	"FRIENDLY_PLAYER_TEAL":  FRIENDLY_PLAYER_TEAL,
	"ENEMY_PLAYER_MAGENTA":  ENEMY_PLAYER_MAGENTA,
	"WARNING_ORANGE":        WARNING_ORANGE,
	"CONFIRMED_GREEN":       CONFIRMED_GREEN,
	"MARGINAL_YELLOW":       MARGINAL_YELLOW,
	"INVALID_RED":           INVALID_RED,
	"NEUTRAL_UI_PALE_WHITE": NEUTRAL_UI_PALE_WHITE,
}


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

# Returns the slot name (e.g. "WARNING_ORANGE") for a known slot color, or
# "" if the color is not in the slot table. Allowed delta per channel: 0.005
# (tolerates 8-bit/float round-tripping through saved scenes).
func slot_name(color: Color) -> String:
	for name in _SLOT_TABLE:
		var slot: Color = _SLOT_TABLE[name]
		if _color_eq(color, slot):
			return name
	return ""


# Returns every slot as a Dictionary {name: Color}. For T12-style audits.
func all_slots() -> Dictionary:
	return _SLOT_TABLE.duplicate()


# T41: canonical player-SLOT color lookup. Slot colors are perspective-
# independent: player 1 is always TEAL ("friendly active"), player 2 is
# always MAGENTA ("enemy"). Faction colors are read separately, per army,
# via FactionPalettes — do NOT use this for faction tint.
func player_slot_color(player: int) -> Color:
	if player == 1:
		return FRIENDLY_PLAYER_TEAL
	return ENEMY_PLAYER_MAGENTA


# T43: canonical primary-CTA color. Use this exactly ONCE per screen for
# the single highest-priority call to action; other clickable controls
# revert to the default chrome. The audit policy is documented in
# 40k/docs/design_guidelines_2d_topdown.md §9. This helper exists so
# every CTA in the codebase references one named slot rather than ad-hoc
# orange literals — making future grep audits possible.
func primary_cta_color() -> Color:
	return WARNING_ORANGE  # WARNING_ORANGE is already the canonical CTA hue


# T41: canonical faction color lookup. Delegates to the existing
# FactionPalettes static API (40k/scripts/FactionPalettes.gd) so this
# autoload doesn't fork the palette model. Falls back to gold/bone if
# the static lookup yields something invalid.
func faction_color_for_player(player: int) -> Color:
	var c: Color = FactionPalettes.get_player_color(player)
	if typeof(c) == TYPE_COLOR and c.a > 0.0:
		return c
	if player == 1:
		return Color(0.83, 0.59, 0.38, 1.0)  # gold
	return Color(0.85, 0.8, 0.65, 1.0)  # bone


# ---------------------------------------------------------------------------
# striped_pattern — diagonal hatched fill for the semantic-yellow-vs-faction-
# yellow collision case (doc §9 anti-pattern). Returns an ImageTexture of a
# 16x16 tile alternating the input color and transparency along diagonal
# stripes. Tile horizontally/vertically in the caller.
# ---------------------------------------------------------------------------

func striped_pattern(color: Color, tile_size: int = 16, stripe_width: int = 4) -> Texture2D:
	var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(tile_size):
		for x in range(tile_size):
			# Diagonal: stripe index = (x + y) / stripe_width mod 2
			var on: bool = int(floor(float(x + y) / float(max(stripe_width, 1)))) % 2 == 0
			if on:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Shared chrome (T12) — NOT semantic slots (all_slots() stays at 7). These are
# the repeated non-semantic plate/scrim colors that used to be duplicated as
# per-file literals.
# ---------------------------------------------------------------------------

const LABEL_BG_DARK := Color(0.1, 0.08, 0.05, 0.9)   # dark label plate behind overlay text
const SCRIM_DARK    := Color(0.0, 0.0, 0.0, 0.7)     # dark scrim behind floating notifications


# T12: alpha-override helper — replaces Color(c.r, c.g, c.b, a) recombination
# literals at call sites that already hold the UIConstants autoload. Visual
# scripts that must also compile in headless -s harnesses keep a local static
# equivalent instead (bare autoload names do not compile there).
func with_alpha(c: Color, a: float) -> Color:
	var out := c
	out.a = a
	return out


# T12 audit hooks — scenario `execute_script` steps are single Expressions
# (no statements), so tree-attached instantiate/read/free sequences live
# here. Adds the visual to the live tree so its _ready-time slot resolution
# runs (the exact path a real game instance takes), reads `property`, then
# tears it down.
func probe_visual_property(script_path: String, property: String) -> Variant:
	var s = load(script_path)
	if s == null:
		return null
	var n = s.new()
	get_tree().root.add_child(n)
	var v = n.get(property)
	get_tree().root.remove_child(n)
	n.queue_free()
	return v


# Same as probe_visual_property, but calls `method(args)` first — for colors
# that are only assigned by a setter path (e.g. CoherencyCircle.set_in_range).
func probe_visual_method_property(script_path: String, method: String, args: Array, property: String) -> Variant:
	var s = load(script_path)
	if s == null:
		return null
	var n = s.new()
	get_tree().root.add_child(n)
	n.callv(method, args)
	var v = n.get(property)
	get_tree().root.remove_child(n)
	n.queue_free()
	return v


# ---------------------------------------------------------------------------
# Motion budget constants (doc §9 — referenced by Tween call sites in T44)
# ---------------------------------------------------------------------------

const MOTION_DICE_MAX_S        := 1.5
const MOTION_SLIDE_PER_INCH_S  := 0.4
const MOTION_FADE_S            := 0.15
const MOTION_PULSE_LOOP_S      := 2.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _color_eq(a: Color, b: Color) -> bool:
	const TOL := 0.005
	return (abs(a.r - b.r) < TOL
			and abs(a.g - b.g) < TOL
			and abs(a.b - b.b) < TOL
			and abs(a.a - b.a) < TOL)
