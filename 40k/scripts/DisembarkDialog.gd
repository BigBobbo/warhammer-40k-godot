extends ConfirmationDialog

# DisembarkDialog - Confirmation dialog for disembarking units from transports
# Shows movement restrictions if transport has already moved

signal disembark_confirmed(combat_mode: bool)
signal disembark_canceled()

var unit_id: String
var unit_name: String = ""
var transport_id: String
var transport_name: String = ""
var transport_moved: bool = false
var transport_advanced: bool = false
var transport_fell_back: bool = false
# 11e 18.04: Combat Disembark toggle — 6" set-up, hazard roll per model,
# battle-shocked, no charge; may set up engaged with the transport's foes.
var combat_checkbox: CheckBox = null

func _ready() -> void:
	WhiteDwarfTheme.apply_to_dialog(self)
	# Set dialog properties
	title = "Disembark Unit"
	min_size = DialogConstants.SMALL
	dialog_hide_on_ok = false

	# Connect buttons
	get_ok_button().text = "Disembark"
	get_ok_button().pressed.connect(_on_ok_pressed)

	get_cancel_button().text = "Stay Embarked"
	get_cancel_button().pressed.connect(_on_cancel_pressed)

	print("DisembarkDialog initialized")

func setup(p_unit_id: String) -> void:
	unit_id = p_unit_id
	var unit = GameState.get_unit(unit_id)

	if not unit:
		print("ERROR: Unit not found: ", unit_id)
		queue_free()
		return

	# Get unit info
	unit_name = unit.meta.get("display_name", unit.meta.get("name", unit_id))
	transport_id = unit.get("embarked_in", null)

	if not transport_id:
		print("ERROR: Unit is not embarked: ", unit_id)
		queue_free()
		return

	var transport = GameState.get_unit(transport_id)
	if not transport:
		print("ERROR: Transport not found: ", transport_id)
		queue_free()
		return

	# Get transport info
	transport_name = transport.meta.get("display_name", transport.meta.get("name", transport_id))

	# Check transport movement status
	var flags = transport.get("flags", {})
	transport_moved = flags.get("moved", false)
	transport_advanced = flags.get("advanced", false)
	transport_fell_back = flags.get("fell_back", false)

	# Build dialog text
	_build_dialog_text()

func _build_dialog_text() -> void:
	var text = "Do you want to disembark %s from %s?" % [unit_name, transport_name]

	# Add warnings based on transport status
	# (Plain text only — AcceptDialog's label does not render BBCode.)
	if transport_advanced:
		text += "\n\nWARNING: Cannot disembark!"
		text += "\nThe transport has Advanced this turn."
		text += "\nUnits cannot disembark from a transport that Advanced."

		# Disable OK button
		get_ok_button().disabled = true

	elif transport_fell_back:
		text += "\n\nWARNING: Cannot disembark!"
		text += "\nThe transport has Fallen Back this turn."
		text += "\nUnits cannot disembark from a transport that Fell Back."

		# Disable OK button
		get_ok_button().disabled = true

	elif transport_moved:
		text += "\n\nWARNING: Movement Restrictions"
		text += "\nThe transport has already moved this turn."
		text += "\n• The disembarked unit cannot move further"
		text += "\n• The disembarked unit cannot charge"
		text += "\n• The unit can still shoot and fight normally"

	else:
		text += "\n\nThe transport has not moved yet."
		text += "\nThe disembarked unit will be able to move normally."

	# Add disembark rules
	text += "\n\nDisembark Rules:"
	text += "\n• Models must be placed wholly within 3\" of the transport"
	text += "\n• Models cannot be placed within Engagement Range of enemies"
	text += "\n• All models must be placed or the unit cannot disembark"

	dialog_text = text

	# 11e 18.04: Combat Disembark is mandatory-if-applicable, and it applies
	# only when the unit CANNOT be set up per Tactical Disembark (within 3",
	# outside Engagement Range). Only offer the toggle when enemies are close
	# enough to the transport that a tactical set-up could actually be blocked
	# — with no foes near the 3" ring it always read as "this will be a combat
	# disembark" while being rules-impossible.
	if GameConstants.edition >= 11 and not transport_advanced and not transport_fell_back and not transport_moved \
			and _combat_disembark_could_apply():
		combat_checkbox = CheckBox.new()
		combat_checkbox.text = "Use Combat Disembark (18.04) — only if the unit cannot be set up\nwithin 3\" outside Engagement Range: 6\" set-up, may be placed engaged\nwith the transport's foes; hazard roll per model, battle-shocked, no charge"
		combat_checkbox.tooltip_text = "Tick only when you cannot set up the whole unit outside Engagement Range within 3\". The unit is set up within 6\" instead and may be placed engaged with enemy units the transport is engaged with."
		var label = get_label()
		if label != null and label.get_parent() != null:
			label.get_parent().add_child(combat_checkbox)
		else:
			add_child(combat_checkbox)

## True when an enemy model is close enough to the transport that the 3"
## tactical set-up ring could be inside Engagement Range — i.e. Combat
## Disembark (18.04) could actually be the mandatory mode. A placed model's
## near edge sits within 3" of the hull, so an ER clash needs an enemy edge
## within 3" + ER + the model's own base size of the hull (edge-to-edge).
## Beyond that, a tactical set-up can never be blocked by ER and the combat
## mode is not applicable. (Overlap/terrain crowding can still be dodged by
## cancelling placement and staying embarked.)
func _combat_disembark_could_apply() -> bool:
	var unit = GameState.get_unit(unit_id)
	var transport = GameState.get_unit(transport_id)
	if not unit or not transport:
		return false

	# Largest base dimension among the disembarking unit's alive models.
	var max_base_inches := 0.0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var base_mm = float(model.get("base_mm", 32))
		var dims = model.get("base_dimensions", {})
		if dims is Dictionary and not dims.is_empty():
			base_mm = max(base_mm, float(dims.get("length", base_mm)), float(dims.get("width", base_mm)))
		max_base_inches = max(max_base_inches, base_mm / Measurement.MM_PER_INCH)

	var threshold_inches := 3.0 + GameConstants.engagement_range_inches() + max_base_inches

	var enemy_owner = 3 - int(unit.get("owner", 1))
	for enemy_id in GameState.state.units:
		var enemy = GameState.state.units[enemy_id]
		if int(enemy.get("owner", 0)) != enemy_owner:
			continue
		if enemy.get("embarked_in", null) != null:
			continue
		for enemy_model in enemy.get("models", []):
			if not enemy_model.get("alive", true) or enemy_model.get("position") == null:
				continue
			for transport_model in transport.get("models", []):
				if not transport_model.get("alive", true) or transport_model.get("position") == null:
					continue
				if Measurement.model_to_model_distance_inches(transport_model, enemy_model) <= threshold_inches:
					print("DisembarkDialog: Combat Disembark offered — enemy %s within %.1f\" of transport" % [enemy_id, threshold_inches])
					return true
	return false

func _on_ok_pressed() -> void:
	var combat_mode: bool = combat_checkbox != null and combat_checkbox.button_pressed
	emit_signal("disembark_confirmed", combat_mode)
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	emit_signal("disembark_canceled")
	hide()
	queue_free()