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

func game_log_panel() -> Node:
	# The left-side event log panel. Also hosts the shared "Dice Log" tab that
	# the shooting/charge/fight controllers write their dice output to.
	return main_path("GameLogPanel")

func hud_right() -> Node:
	return main_path("HUD_Right")

func hud_right_vbox() -> Node:
	return main_path("HUD_Right/VBoxContainer")

func hud_bottom() -> Node:
	return main_path("HUD_Bottom")

func hud_top() -> Node:
	return main_path("HUD_Top")

## Where the battlefield currently sits on screen (viewport coordinates) — the
## board's "used rect". BoardRoot carries the camera transform (pan, zoom), so
## its canvas transform maps the board's pixel extent straight to the screen.
## Rect2() when the battle scene isn't loaded. Pass `main_node` when the caller
## already holds it (the reserves tray rails); otherwise /root/Main is used.
## Also the T06 check that a side panel never covers the board it asks about.
func board_screen_rect(main_node: Node = null) -> Rect2:
	var m: Node = main_node if main_node != null else main()
	var root = m.get_node_or_null("BoardRoot") if m != null else null
	if root == null or not (root is Node2D):
		return Rect2()
	var w := 1760.0
	var h := 2400.0
	var settings = get_node_or_null("/root/SettingsService")
	if settings != null:
		w = settings.get_board_width_px()
		h = settings.get_board_height_px()
	var xf: Transform2D = (root as Node2D).get_global_transform_with_canvas()
	var top_left: Vector2 = xf * Vector2.ZERO
	var bottom_right: Vector2 = xf * Vector2(w, h)
	return Rect2(top_left, bottom_right - top_left).abs()
