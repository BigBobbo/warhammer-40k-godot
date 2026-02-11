extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# CharacterAttachmentManager - Manages CHARACTER leader attachment to bodyguard units
# Mirrors TransportManager pattern for embark/disembark

signal attach_completed(bodyguard_id: String, character_id: String)
signal detach_completed(character_id: String)

func _ready() -> void:
	print("CharacterAttachmentManager initialized")

# Check if a character can attach to a bodyguard unit
func can_attach(character_id: String, bodyguard_id: String) -> Dictionary:
	var character = GameState.get_unit(character_id)
	var bodyguard = GameState.get_unit(bodyguard_id)

	if character.is_empty():
		return {"valid": false, "reason": "Character unit not found"}

	if bodyguard.is_empty():
		return {"valid": false, "reason": "Bodyguard unit not found"}

	# Check CHARACTER keyword
	var char_keywords = character.get("meta", {}).get("keywords", [])
	if "CHARACTER" not in char_keywords:
		return {"valid": false, "reason": "Unit is not a CHARACTER"}

	# Check leader_data exists with can_lead
	var leader_data = character.get("meta", {}).get("leader_data", {})
	var can_lead = leader_data.get("can_lead", [])
	if can_lead.is_empty():
		return {"valid": false, "reason": "Character has no Leader ability"}

	# Check bodyguard has a matching keyword from can_lead
	var bg_keywords = bodyguard.get("meta", {}).get("keywords", [])
	var has_match = false
	for lead_keyword in can_lead:
		if lead_keyword in bg_keywords:
			has_match = true
			break
	if not has_match:
		return {"valid": false, "reason": "Unit does not have a compatible keyword (%s)" % str(can_lead)}

	# Check same owner
	if character.get("owner", 0) != bodyguard.get("owner", 0):
		return {"valid": false, "reason": "Character and bodyguard belong to different players"}

	# Check character is not already attached
	if character.get("attached_to", null) != null:
		return {"valid": false, "reason": "Character is already attached to another unit"}

	# Check bodyguard doesn't already have a character attached
	var attached_chars = bodyguard.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.size() > 0:
		return {"valid": false, "reason": "Unit already has an attached leader"}

	# Check bodyguard is not itself a CHARACTER
	if "CHARACTER" in bg_keywords:
		return {"valid": false, "reason": "Cannot attach to another CHARACTER unit"}

	return {"valid": true}

# Attach a character to a bodyguard unit
func attach_character(character_id: String, bodyguard_id: String) -> void:
	var validation = can_attach(character_id, bodyguard_id)
	if not validation.valid:
		print("CharacterAttachmentManager: Cannot attach: ", validation.reason)
		return

	var character = GameState.get_unit(character_id)
	var bodyguard = GameState.get_unit(bodyguard_id)

	# Set attached status on character
	character["attached_to"] = bodyguard_id

	# Add character to bodyguard's attached_characters list
	if not bodyguard.has("attachment_data"):
		bodyguard["attachment_data"] = {"attached_characters": []}
	bodyguard.attachment_data.attached_characters.append(character_id)

	# Update GameState directly
	GameState.state.units[character_id] = character
	GameState.state.units[bodyguard_id] = bodyguard

	emit_signal("attach_completed", bodyguard_id, character_id)
	print("CharacterAttachmentManager: Character %s attached to bodyguard %s" % [character_id, bodyguard_id])

# Detach a character from its bodyguard unit
func detach_character(character_id: String) -> void:
	var character = GameState.get_unit(character_id)
	if character.is_empty() or character.get("attached_to", null) == null:
		print("CharacterAttachmentManager: Cannot detach: character not attached")
		return

	var bodyguard_id = character.attached_to
	var bodyguard = GameState.get_unit(bodyguard_id)

	# Clear attached status on character
	character["attached_to"] = null

	# Remove character from bodyguard's attached_characters list
	if not bodyguard.is_empty() and bodyguard.has("attachment_data"):
		var chars = bodyguard.attachment_data.attached_characters.duplicate()
		chars.erase(character_id)
		bodyguard.attachment_data["attached_characters"] = chars
		GameState.state.units[bodyguard_id] = bodyguard

	# Update GameState directly
	GameState.state.units[character_id] = character

	emit_signal("detach_completed", character_id)
	print("CharacterAttachmentManager: Character %s detached from bodyguard %s" % [character_id, bodyguard_id])

# Get eligible CHARACTER units that can attach to a bodyguard unit
func get_attachable_characters(bodyguard_id: String, player: int) -> Array:
	var attachable = []
	var bodyguard = GameState.get_unit(bodyguard_id)

	if bodyguard.is_empty():
		return attachable

	# Bodyguard must not be a CHARACTER itself
	var bg_keywords = bodyguard.get("meta", {}).get("keywords", [])
	if "CHARACTER" in bg_keywords:
		return attachable

	# Check all units for the player
	for unit_id in GameState.state.units:
		var unit = GameState.state.units[unit_id]
		if unit.get("owner", 0) != player:
			continue

		# Skip non-CHARACTER units
		var keywords = unit.get("meta", {}).get("keywords", [])
		if "CHARACTER" not in keywords:
			continue

		# Skip already deployed units (only allow during deployment)
		if unit.get("status", "") != GameStateData.UnitStatus.UNDEPLOYED:
			continue

		# Skip already attached characters
		if unit.get("attached_to", null) != null:
			continue

		# Skip embarked characters
		if unit.get("embarked_in", null) != null:
			continue

		# Check if this character can lead this bodyguard
		var validation = can_attach(unit_id, bodyguard_id)
		if validation.valid:
			attachable.append(unit)

	return attachable

# Check if all non-character models in a bodyguard unit are destroyed
# If so, detach all attached characters (they become independent)
func check_bodyguard_destroyed(bodyguard_id: String) -> void:
	var bodyguard = GameState.get_unit(bodyguard_id)
	if bodyguard.is_empty():
		return

	var attached_chars = bodyguard.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.is_empty():
		return

	# Check if any non-character models are still alive
	var has_alive_bodyguard_models = false
	for model in bodyguard.get("models", []):
		if model.get("alive", true):
			has_alive_bodyguard_models = true
			break

	if has_alive_bodyguard_models:
		return

	# All bodyguard models dead — detach all characters
	print("CharacterAttachmentManager: All bodyguard models destroyed in %s, detaching characters" % bodyguard_id)
	var chars_to_detach = attached_chars.duplicate()
	for char_id in chars_to_detach:
		detach_character(char_id)
		print("CharacterAttachmentManager: Character %s is now an independent unit" % char_id)

# Get number of alive non-character models in a bodyguard unit
func get_alive_bodyguard_model_count(bodyguard_id: String) -> int:
	var bodyguard = GameState.get_unit(bodyguard_id)
	if bodyguard.is_empty():
		return 0

	var count = 0
	for model in bodyguard.get("models", []):
		if model.get("alive", true):
			count += 1
	return count
