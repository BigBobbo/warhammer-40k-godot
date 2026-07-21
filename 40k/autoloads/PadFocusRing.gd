extends CanvasLayer

# Pad focus ring: while a controller is the active device, draw a bright ring
# around whichever Control currently owns keyboard/pad focus, so D-pad panel
# navigation is visible. The HUD's custom-styled buttons have no legible focus
# stylebox of their own, which left pad players guessing what (if anything) the
# D-pad had selected — the ring makes the focused control unmistakable.
#
# Layer 94: above the hint bar (90) and action bar (92), below the virtual
# cursor (95). Screen-space, so it tracks Controls in the HUD CanvasLayers;
# focus inside embedded dialog Windows keeps Godot's own focus styling (those
# dialogs auto-focus their confirm button via InputDeviceManager already).

const WhiteDwarfThemeData = preload("res://scripts/WhiteDwarfTheme.gd")

const RING_GROW := 3.0     # px beyond the control's rect
const RING_WIDTH := 3      # border width px
const RING_RADIUS := 5     # corner radius px

var _ring: Panel = null

func _ready() -> void:
	layer = 94
	_ring = Panel.new()
	_ring.name = "FocusRing"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = WhiteDwarfThemeData.WH_GOLD
	style.set_border_width_all(RING_WIDTH)
	style.set_corner_radius_all(RING_RADIUS)
	_ring.add_theme_stylebox_override("panel", style)
	_ring.visible = false
	add_child(_ring)

func _process(_delta: float) -> void:
	if not InputDeviceManager.is_pad_active():
		_ring.visible = false
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not is_instance_valid(owner) or not owner.is_visible_in_tree():
		_ring.visible = false
		return
	# Track every frame — panels scroll, lists rebuild, buttons move.
	var rect := owner.get_global_rect().grow(RING_GROW)
	_ring.position = rect.position
	_ring.size = rect.size
	_ring.visible = true

# Scenario/verify seam: whether the ring is currently shown (and where).
func is_ring_visible() -> bool:
	return _ring != null and _ring.visible

func ring_rect() -> Rect2:
	return Rect2(_ring.position, _ring.size) if is_ring_visible() else Rect2()
