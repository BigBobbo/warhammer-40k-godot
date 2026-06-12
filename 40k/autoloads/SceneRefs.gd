extends Node

## ISS-009: the single chokepoint for Main-scene node lookups.
##
## Systems that need battle-scene nodes resolve them here instead of
## hardcoding "/root/Main/..." paths — renaming a scene node means
## updating ONE function. Every getter is null-safe: it returns null
## whenever the battle scene isn't loaded (menus, headless tests), so
## callers keep their existing `if x != null` guards.
##
## For one-off deep paths, use main_path("HUD_Right/.../SomePanel").

func main() -> Node:
	return get_tree().root.get_node_or_null("Main")

func main_path(relative: String) -> Node:
	var m = main()
	return m.get_node_or_null(relative) if m != null else null

func board_root() -> Node:
	return main_path("BoardRoot")

func token_layer() -> Node:
	return main_path("BoardRoot/TokenLayer")

func board_view() -> Node:
	return main_path("BoardRoot/BoardView")

func terrain_visual() -> Node:
	return main_path("BoardRoot/TerrainVisual")

func hud_right() -> Node:
	return main_path("HUD_Right")

func hud_right_vbox() -> Node:
	return main_path("HUD_Right/VBoxContainer")

func hud_bottom() -> Node:
	return main_path("HUD_Bottom")

func hud_top() -> Node:
	return main_path("HUD_Top")
