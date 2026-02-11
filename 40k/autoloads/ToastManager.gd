extends CanvasLayer
class_name ToastManagerClass

# ToastManager - Global on-screen toast notification system
# Usage: ToastManager.show_toast("message") or ToastManager.show_error("message")

const MAX_TOASTS: int = 5
const DEFAULT_DURATION: float = 3.0
const ERROR_DURATION: float = 5.0
const WARNING_DURATION: float = 4.0

var toast_container: VBoxContainer
var active_toasts: Array = []

func _ready() -> void:
	layer = 100  # Render above everything
	_create_toast_container()

func _create_toast_container() -> void:
	toast_container = VBoxContainer.new()
	toast_container.name = "ToastContainer"

	# Position at top-center of screen
	toast_container.anchor_left = 0.3
	toast_container.anchor_right = 0.7
	toast_container.anchor_top = 0.0
	toast_container.anchor_bottom = 0.0
	toast_container.offset_top = 120  # Below the top HUD bar
	toast_container.offset_bottom = 500
	toast_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Space between toasts
	toast_container.add_theme_constant_override("separation", 6)

	add_child(toast_container)

func show_toast(message: String, color: Color = Color.WHITE, duration: float = DEFAULT_DURATION) -> void:
	print("[Toast] %s" % message)
	_add_toast(message, color, duration)

func show_error(message: String, duration: float = ERROR_DURATION) -> void:
	print("[Toast ERROR] %s" % message)
	_add_toast(message, Color(1.0, 0.3, 0.3), duration)

func show_warning(message: String, duration: float = WARNING_DURATION) -> void:
	print("[Toast WARNING] %s" % message)
	_add_toast(message, Color(1.0, 0.9, 0.3), duration)

func show_success(message: String, duration: float = DEFAULT_DURATION) -> void:
	print("[Toast SUCCESS] %s" % message)
	_add_toast(message, Color(0.3, 1.0, 0.5), duration)

func _add_toast(message: String, color: Color, duration: float) -> void:
	# Limit active toasts
	if active_toasts.size() >= MAX_TOASTS:
		var oldest = active_toasts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var toast_panel = _create_toast_panel(message, color)
	toast_container.add_child(toast_panel)
	active_toasts.append(toast_panel)

	# Fade in
	toast_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(toast_panel, "modulate:a", 1.0, 0.15)

	# Schedule removal
	_schedule_removal(toast_panel, duration)

func _create_toast_panel(message: String, color: Color) -> PanelContainer:
	var panel = PanelContainer.new()

	# Dark semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_color = color * Color(1, 1, 1, 0.6)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	panel.add_child(label)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	return panel

func _schedule_removal(toast: PanelContainer, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(toast):
		# Fade out
		var tween = create_tween()
		tween.tween_property(toast, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func():
			if is_instance_valid(toast):
				active_toasts.erase(toast)
				toast.queue_free()
		)
