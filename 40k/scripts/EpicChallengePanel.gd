extends PanelContainer

# EpicChallengePanel — side-anchored variant of the Epic Challenge decision
# dialog (T20, doc §3). Mirrors T06's WeaponOrderPanel pattern.
#
# Public API:
#   open_for(challenger_id, defender_id, effect_preview: String)
#   close()
#   signal decision_made(accepted: bool)
#
# Self-installs as /root/Main/EpicChallengePanel via Main._ready().

signal decision_made(accepted: bool)

const PANEL_WIDTH := 340.0

var challenger_id: String = ""
var defender_id: String = ""
var _vbox: VBoxContainer = null
var _effect_label: Label = null


func _ready() -> void:
	name = "EpicChallengePanel"
	visible = false
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_viewport_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", _sync_viewport_size):
		vp.connect("size_changed", _sync_viewport_size)

	_vbox = VBoxContainer.new()
	_vbox.name = "Body"
	_vbox.add_theme_constant_override("separation", 6)
	add_child(_vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "Epic Challenge"
	title.add_theme_font_size_override("font_size", 18)
	_vbox.add_child(title)

	_effect_label = Label.new()
	_effect_label.name = "Effect"
	_effect_label.text = ""
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_effect_label)

	var btns := HBoxContainer.new()
	btns.name = "Buttons"
	_vbox.add_child(btns)
	var use_btn := Button.new()
	use_btn.name = "Use"
	use_btn.text = "Use"
	use_btn.pressed.connect(_on_use_pressed)
	btns.add_child(use_btn)
	var decline_btn := Button.new()
	decline_btn.name = "Decline"
	decline_btn.text = "Decline"
	decline_btn.pressed.connect(_on_decline_pressed)
	btns.add_child(decline_btn)


func _sync_viewport_size() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	position = Vector2(vp_size.x - PANEL_WIDTH, 100.0)
	size = Vector2(PANEL_WIDTH, 320.0)


func open_for(challenger: String, defender: String, effect_preview: String) -> void:
	challenger_id = challenger
	defender_id = defender
	_effect_label.text = effect_preview
	visible = true


func close() -> void:
	visible = false


func _on_use_pressed() -> void:
	emit_signal("decision_made", true)
	close()


func _on_decline_pressed() -> void:
	emit_signal("decision_made", false)
	close()


func t20_anchor_left_ratio() -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var vp_w := vp.get_visible_rect().size.x
	if vp_w <= 0.0:
		return 0.0
	return position.x / vp_w
