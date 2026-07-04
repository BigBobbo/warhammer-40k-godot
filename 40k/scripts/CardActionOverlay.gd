extends Node2D
class_name CardActionOverlay

# CardActionOverlay - Renders the 11e GDM card-action badges that live on
# TERRAIN features: Booby Traps (Death Trap) and the shared Extract Relic /
# Locate and Deny operation markers. Objective-anchored badges are drawn by
# ObjectiveVisual.set_card_action_badges; this layer covers the rest of the
# board state a player otherwise cannot see.

const BADGE_TRAP_COLOR = Color(1.0, 0.45, 0.25, 1.0)
const BADGE_RELIC_COLOR = Color(0.55, 0.9, 1.0, 1.0)

func _ready() -> void:
	name = "CardActionOverlay"
	z_index = 40
	var mm = get_node_or_null("/root/MissionManager")
	if mm and mm.has_signal("card_action_state_changed") \
			and not mm.card_action_state_changed.is_connected(refresh):
		mm.card_action_state_changed.connect(refresh)
	refresh()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	if GameConstants.edition < 11:
		return
	var mm = get_node_or_null("/root/MissionManager")
	var tm = get_node_or_null("/root/TerrainManager")
	if mm == null or tm == null:
		return
	for feature in tm.terrain_features:
		var fid = str(feature.get("id", ""))
		if fid == "":
			continue
		var lines: Array = mm.get_terrain_badges_11e(fid)
		if lines.is_empty():
			continue
		var label = Label.new()
		label.name = "Badge_%s" % fid
		label.text = " · ".join(PackedStringArray(lines))
		label.add_theme_font_override("font", FactionPalettes.FONT_RAJDHANI_BOLD)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_color_override("font_color",
			BADGE_TRAP_COLOR if "BOOBY TRAP" in label.text else BADGE_RELIC_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(180, 20)
		var fpos = feature.get("position", Vector2.ZERO)
		if fpos is Dictionary:
			fpos = Vector2(fpos.get("x", 0), fpos.get("y", 0))
		label.position = fpos + Vector2(-90, -10)
		add_child(label)
