extends CanvasLayer

# M0 hint-bar shell (PRPs/steam_deck_controller_support.md §5.1): a
# bottom-center strip of button-glyph hints that appears only while the pad
# is the active device. In M0 it shows one static global hint set; M2's
# PadRouter will drive per-context hints (cycle units / carry model / …)
# through set_hints(), and the M5 design pass owns its final placement.

const GlyphDB := preload("res://scripts/input/GlyphDB.gd")

# One chip per [glyph_id, label] pair. M1 static set — M2's PadRouter makes
# this contextual.
const M0_HINTS := [
	["ls", "Cursor"],
	["dpad", "Focus"],
	["a", "Select / Click"],
	["b", "Back"],
	["x", "Right-Click"],
	["rs", "Pan Camera"],
	["lt", "Zoom Out"],
	["rt", "Zoom In"],
	["menu", "End Phase"],
]

var _panel: PanelContainer
var _row: HBoxContainer


func _ready() -> void:
	layer = 90
	_build()
	set_hints(M0_HINTS)
	InputDeviceManager.device_changed.connect(_on_device_changed)
	_on_device_changed(InputDeviceManager.input_mode)


func set_hints(hints: Array) -> void:
	for child in _row.get_children():
		child.queue_free()
	for hint in hints:
		_row.add_child(GlyphDB.make_chip(str(hint[0]), str(hint[1])))
	_panel.visible = not hints.is_empty() and InputDeviceManager.is_pad_active()


func _on_device_changed(mode: int) -> void:
	_panel.visible = (mode == InputDeviceManager.InputMode.PAD) and _row.get_child_count() > 0


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PadHintPanel"
	# Purely informational — must never swallow clicks aimed at the HUD under it.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_panel)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 16)
	_panel.add_child(_row)
