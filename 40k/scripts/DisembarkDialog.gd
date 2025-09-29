extends ConfirmationDialog

# DisembarkDialog - Confirmation dialog for disembarking units from transports
# Shows movement restrictions if transport has already moved

signal disembark_confirmed()
signal disembark_canceled()

var unit_id: String
var unit_name: String = ""
var transport_id: String
var transport_name: String = ""
var transport_moved: bool = false
var transport_advanced: bool = false
var transport_fell_back: bool = false

func _ready() -> void:
	# Set dialog properties
	title = "Disembark Unit"
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
	unit_name = unit.meta.get("name", unit_id)
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
	transport_name = transport.meta.get("name", transport_id)

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
	if transport_advanced:
		text += "\n\n[color=red]WARNING: Cannot disembark![/color]"
		text += "\nThe transport has Advanced this turn."
		text += "\nUnits cannot disembark from a transport that Advanced."

		# Disable OK button
		get_ok_button().disabled = true

	elif transport_fell_back:
		text += "\n\n[color=red]WARNING: Cannot disembark![/color]"
		text += "\nThe transport has Fallen Back this turn."
		text += "\nUnits cannot disembark from a transport that Fell Back."

		# Disable OK button
		get_ok_button().disabled = true

	elif transport_moved:
		text += "\n\n[color=yellow]WARNING: Movement Restrictions[/color]"
		text += "\nThe transport has already moved this turn."
		text += "\n• The disembarked unit cannot move further"
		text += "\n• The disembarked unit cannot charge"
		text += "\n• The unit can still shoot and fight normally"

	else:
		text += "\n\nThe transport has not moved yet."
		text += "\nThe disembarked unit will be able to move normally."

	# Add disembark rules
	text += "\n\n[color=cyan]Disembark Rules:[/color]"
	text += "\n• Models must be placed wholly within 3\" of the transport"
	text += "\n• Models cannot be placed within Engagement Range of enemies"
	text += "\n• All models must be placed or the unit cannot disembark"

	dialog_text = text

func _on_ok_pressed() -> void:
	emit_signal("disembark_confirmed")
	hide()
	queue_free()

func _on_cancel_pressed() -> void:
	emit_signal("disembark_canceled")
	hide()
	queue_free()