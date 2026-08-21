class_name PlanValidator
extends RefCounted

# PlanValidator — static validation for the `wh40k_ai_plan` v1 format.
#
# A plan is a JSON artifact describing, for a specific army list on a specific
# deployment map, (a) exactly how to deploy and (b) high-level per-unit intents
# ("earmarks") for the game. See 40k/docs/PLAN_FORMAT.md for the authoritative
# format doc.
#
# Style mirrors ProfileManager.gd: all-static RefCounted, push_warning + empty
# dict on error, validate_* returning {valid, errors}. This file adds a
# `warnings` channel because plans degrade gracefully (an unmatched unit is a
# warning, an illegal placement is an error).
#
# IMPORTANT — coordinate frame: plan coordinates are ALWAYS authored in the
# player-1 zone frame. A consumer seated as player 2 transforms every placement
# by the 180 degree board rotation [x, y] -> [44 - x, 60 - y]. The validator
# checks BOTH frames so a plan that cannot be mirrored is rejected at authoring
# time rather than silently degrading to the formula at play time.

# NOTE — no preload of DeploymentZoneData here, deliberately. That script
# references the `Measurement` autoload, and autoload identifiers are not
# resolvable while a `godot --headless -s tests/...` SceneTree script is being
# compiled, so preloading it makes this validator uncompilable in exactly the
# headless harness that tests it ("Compile Error: Identifier not found:
# Measurement"). The zone geometry the validator needs is the same JSON
# DeploymentZoneData itself prefers (DeploymentZoneData.gd:29-34), so we read
# res://deployment_zones/<id>.json directly and stay autoload-free.
# tests/unit/test_plan_validator.gd asserts that every entry of
# DeploymentZoneData.DEPLOYMENT_TYPES really does have such a JSON file, so a
# future JSON-less zone type fails loudly instead of silently going missing.

const FORMAT_TAG: String = "wh40k_ai_plan"
const SCHEMA_VERSION: int = 1

# Board dimensions in inches (mirrors DeploymentZoneData.BOARD_WIDTH/HEIGHT).
const BOARD_WIDTH_IN: float = 44.0
const BOARD_HEIGHT_IN: float = 60.0

# The closed v1 intent vocabulary. Exactly five verbs — see PLAN_FORMAT.md.
const VERBS := [
	"HOLD_OBJECTIVE",
	"PUSH_CENTER",
	"SCREEN",
	"RESERVE_UNTIL",
	"HUNT_CHARACTERS",
]

# Verbs that are recognised but deliberately not implemented in v1. A dead
# button erodes trust, so authoring one is an error with an explicit reason.
const RESERVED_VERBS := {
	"TRADE": "reserved for v2 (no per-unit parameter mechanism exists yet)",
}

const RESERVE_ROUND_MIN: int = 2
const RESERVE_ROUND_MAX: int = 3

# Chapter Approved 2025-26 reserves caps, mirroring FormationsPhase.gd:400-420.
const RESERVES_FRACTION: float = 0.50

# ============================================================
# GEOMETRY HELPERS
# ============================================================

static func mirror_inches(x: float, y: float) -> Vector2:
	"""Player-1 frame -> player-2 frame. 180 degree rotation about board centre."""
	return Vector2(BOARD_WIDTH_IN - x, BOARD_HEIGHT_IN - y)

static var _zone_json_cache: Dictionary = {}

static func zone_json(zone_id: String) -> Dictionary:
	"""Parsed res://deployment_zones/<id>.json, or {} when there is no such file.

	DeploymentZoneData.get_zones() silently falls back to hammer_anvil on an
	unknown id (DeploymentZoneData.gd:48-50), so it is NOT an existence check —
	this is."""
	if zone_id.is_empty():
		return {}
	if _zone_json_cache.has(zone_id):
		return _zone_json_cache[zone_id]
	var path := "res://deployment_zones/%s.json" % zone_id
	var parsed := {}
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var json = JSON.new()
			var err = json.parse(file.get_as_text())
			file.close()
			if err == OK and json.data is Dictionary:
				parsed = json.data
			else:
				push_warning("PlanValidator: Failed to parse deployment zone '%s'" % path)
	_zone_json_cache[zone_id] = parsed
	return parsed

static func clear_zone_cache() -> void:
	_zone_json_cache.clear()

static func zone_exists(zone_id: String) -> bool:
	"""True when the deployment zone id resolves to real geometry."""
	var data := zone_json(zone_id)
	return data.has("zones") and data["zones"] is Array and not data["zones"].is_empty()

static func layout_exists(layout_id: String) -> bool:
	"""True when the terrain layout id resolves to a shipped layout file."""
	if layout_id.is_empty():
		return false
	return FileAccess.file_exists("res://terrain_layouts/%s.json" % layout_id)

static func get_zone_polygon(zone_id: String, player: int) -> PackedVector2Array:
	"""Deployment zone polygon for `player` in INCHES. Empty when unresolvable."""
	var poly := PackedVector2Array()
	var zones = zone_json(zone_id).get("zones", [])
	for zone in zones:
		if not (zone is Dictionary):
			continue
		if int(zone.get("player", 0)) != player:
			continue
		for point in zone.get("poly", []):
			if point is Dictionary:
				poly.append(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))))
			elif point is Array and point.size() >= 2:
				poly.append(Vector2(float(point[0]), float(point[1])))
		break
	return poly

static func point_in_zone(point_in: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point_in, poly)

# ============================================================
# VALIDATION
# ============================================================

static func validate_plan(data, army: Dictionary = {}) -> Dictionary:
	"""Validate a plan dictionary.

	`army` is optional; when supplied (either an ArmyListManager army dict or a
	GameState-style {units: {...}} snapshot fragment) the validator additionally
	checks unit coverage and the 50% reserves caps.

	Returns {valid: bool, errors: Array[String], warnings: Array[String],
	         coverage: Dictionary}."""
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if not (data is Dictionary):
		errors.append("Plan root is not a Dictionary")
		return {"valid": false, "errors": errors, "warnings": warnings, "coverage": {}}

	var plan: Dictionary = data

	# --- Envelope ---------------------------------------------------------
	if plan.get("format", "") != FORMAT_TAG:
		errors.append("Missing or invalid 'format' field (expected '%s')" % FORMAT_TAG)
	if not plan.has("version") or not (plan["version"] is int or plan["version"] is float):
		errors.append("Missing or invalid 'version' field (expected integer)")
	elif int(plan["version"]) != SCHEMA_VERSION:
		errors.append("Unsupported plan version %d (this build understands version %d)" % [int(plan["version"]), SCHEMA_VERSION])
	if str(plan.get("name", "")).strip_edges().is_empty():
		errors.append("Missing or empty 'name'")

	# --- Keys -------------------------------------------------------------
	var keys = plan.get("keys", {})
	if not (keys is Dictionary):
		errors.append("'keys' must be a Dictionary")
		keys = {}
	var army_file := str(keys.get("army_file", ""))
	if army_file.is_empty():
		errors.append("keys.army_file is required (the army list this plan is authored for)")
	var zone_id := str(keys.get("deployment_zone_id", ""))
	if zone_id.is_empty():
		errors.append("keys.deployment_zone_id is required")
	elif not zone_exists(zone_id):
		errors.append("Unknown deployment_zone_id '%s' (no usable res://deployment_zones/%s.json)" % [zone_id, zone_id])
	var layout_id := str(keys.get("terrain_layout_id", ""))
	if not layout_id.is_empty() and not layout_exists(layout_id):
		errors.append("Unknown terrain_layout_id '%s' (no res://terrain_layouts/%s.json)" % [layout_id, layout_id])

	var poly_p1 := get_zone_polygon(zone_id, 1)
	var poly_p2 := get_zone_polygon(zone_id, 2)
	if zone_exists(zone_id) and (poly_p1.size() < 3 or poly_p2.size() < 3):
		errors.append("Deployment zone '%s' did not yield two usable polygons" % zone_id)

	# --- Deployment -------------------------------------------------------
	var deployment = plan.get("deployment", {})
	if not (deployment is Dictionary):
		errors.append("'deployment' must be a Dictionary")
		deployment = {}

	var order = deployment.get("order", [])
	if not (order is Array):
		errors.append("deployment.order must be an Array")
		order = []
	var seen_order := {}
	for i in range(order.size()):
		var oid := str(order[i])
		if oid.is_empty():
			errors.append("deployment.order[%d] is empty" % i)
		elif seen_order.has(oid):
			errors.append("deployment.order lists '%s' more than once" % oid)
		else:
			seen_order[oid] = true

	var placements = deployment.get("placements", [])
	if not (placements is Array):
		errors.append("deployment.placements must be an Array")
		placements = []

	var placed_units := {}
	for i in range(placements.size()):
		var placement = placements[i]
		if not (placement is Dictionary):
			errors.append("deployment.placements[%d] is not a Dictionary" % i)
			continue
		var unit_id := str(placement.get("unit", ""))
		if unit_id.is_empty():
			errors.append("deployment.placements[%d] missing 'unit'" % i)
			continue
		if placed_units.has(unit_id):
			errors.append("deployment.placements has more than one entry for '%s'" % unit_id)
		placed_units[unit_id] = true

		var models = placement.get("models_inches", [])
		if not (models is Array) or models.is_empty():
			errors.append("Placement '%s' has no 'models_inches'" % unit_id)
			continue

		var inside_p1 := 0
		var inside_p2 := 0
		var off_board := 0
		for m in range(models.size()):
			var raw = models[m]
			if not (raw is Array) or raw.size() < 2:
				errors.append("Placement '%s' model %d is not an [x, y] pair" % [unit_id, m])
				continue
			var px := float(raw[0])
			var py := float(raw[1])
			if px < 0.0 or px > BOARD_WIDTH_IN or py < 0.0 or py > BOARD_HEIGHT_IN:
				off_board += 1
			if point_in_zone(Vector2(px, py), poly_p1):
				inside_p1 += 1
			if point_in_zone(mirror_inches(px, py), poly_p2):
				inside_p2 += 1

		if off_board > 0:
			errors.append("Placement '%s' has %d model position(s) off the %.0fx%.0f board" % [unit_id, off_board, BOARD_WIDTH_IN, BOARD_HEIGHT_IN])
		if poly_p1.size() >= 3 and inside_p1 == 0:
			errors.append("Placement '%s' has no model inside the player-1 '%s' deployment zone" % [unit_id, zone_id])
		elif poly_p1.size() >= 3 and inside_p1 < models.size():
			warnings.append("Placement '%s': %d of %d models sit outside the player-1 zone polygon (deployment requires wholly-within — the consumer will repair or fall back)" % [unit_id, models.size() - inside_p1, models.size()])
		if poly_p2.size() >= 3 and inside_p2 == 0:
			errors.append("Placement '%s' does not land inside the player-2 zone after the seat-2 transform [44-x, 60-y] — a seat-2 consumer would degrade to the formula" % unit_id)

		var coherency_note := _placement_coherency_note(unit_id, models, _army_units(army).get(unit_id, {}))
		if not coherency_note.is_empty():
			warnings.append(coherency_note)

	for oid in seen_order.keys():
		if not placed_units.has(oid):
			warnings.append("deployment.order lists '%s' but there is no placement for it (it will deploy via the formula in that slot)" % oid)
	for pid in placed_units.keys():
		if not seen_order.has(pid):
			warnings.append("Placement '%s' is not in deployment.order (it will deploy after the ordered units)" % pid)

	# --- Reserves ---------------------------------------------------------
	var reserves = deployment.get("reserves", [])
	if not (reserves is Array):
		errors.append("deployment.reserves must be an Array")
		reserves = []
	var reserve_rounds := {}
	for i in range(reserves.size()):
		var entry = reserves[i]
		if not (entry is Dictionary):
			errors.append("deployment.reserves[%d] is not a Dictionary" % i)
			continue
		var unit_id := str(entry.get("unit", ""))
		if unit_id.is_empty():
			errors.append("deployment.reserves[%d] missing 'unit'" % i)
			continue
		if reserve_rounds.has(unit_id):
			errors.append("deployment.reserves lists '%s' more than once" % unit_id)
		if not entry.has("arrival_round"):
			errors.append("deployment.reserves entry '%s' missing 'arrival_round'" % unit_id)
			continue
		var arrival := int(entry.get("arrival_round", 0))
		if arrival < RESERVE_ROUND_MIN or arrival > RESERVE_ROUND_MAX:
			errors.append("deployment.reserves entry '%s' has arrival_round %d (expected %d-%d)" % [unit_id, arrival, RESERVE_ROUND_MIN, RESERVE_ROUND_MAX])
		reserve_rounds[unit_id] = arrival
		if placed_units.has(unit_id):
			errors.append("'%s' is both placed on the board and declared in reserves" % unit_id)

	# --- Embarkations / attachments --------------------------------------
	var embarkations = deployment.get("embarkations", [])
	if not (embarkations is Array):
		errors.append("deployment.embarkations must be an Array")
		embarkations = []
	var embarked_units := {}
	for i in range(embarkations.size()):
		var entry = embarkations[i]
		if not (entry is Dictionary):
			errors.append("deployment.embarkations[%d] is not a Dictionary" % i)
			continue
		var unit_id := str(entry.get("unit", ""))
		var transport_id := str(entry.get("transport", ""))
		if unit_id.is_empty() or transport_id.is_empty():
			errors.append("deployment.embarkations[%d] needs both 'unit' and 'transport'" % i)
			continue
		if unit_id == transport_id:
			errors.append("deployment.embarkations[%d]: '%s' cannot embark inside itself" % [i, unit_id])
		if embarked_units.has(unit_id):
			errors.append("deployment.embarkations lists '%s' more than once" % unit_id)
		embarked_units[unit_id] = transport_id

	var attachments = deployment.get("attachments", [])
	if not (attachments is Array):
		errors.append("deployment.attachments must be an Array")
		attachments = []
	var attached_chars := {}
	for i in range(attachments.size()):
		var entry = attachments[i]
		if not (entry is Dictionary):
			errors.append("deployment.attachments[%d] is not a Dictionary" % i)
			continue
		var char_id := str(entry.get("character", ""))
		var body_id := str(entry.get("bodyguard", ""))
		if char_id.is_empty() or body_id.is_empty():
			errors.append("deployment.attachments[%d] needs both 'character' and 'bodyguard'" % i)
			continue
		if char_id == body_id:
			errors.append("deployment.attachments[%d]: '%s' cannot attach to itself" % [i, char_id])
		if attached_chars.has(char_id):
			errors.append("deployment.attachments lists character '%s' more than once" % char_id)
		attached_chars[char_id] = body_id

	# --- Earmarks ---------------------------------------------------------
	var earmarks = plan.get("earmarks", [])
	if not (earmarks is Array):
		errors.append("'earmarks' must be an Array")
		earmarks = []
	var earmarked_units := {}
	for i in range(earmarks.size()):
		var entry = earmarks[i]
		if not (entry is Dictionary):
			errors.append("earmarks[%d] is not a Dictionary" % i)
			continue
		var unit_id := str(entry.get("unit", ""))
		if unit_id.is_empty():
			errors.append("earmarks[%d] missing 'unit'" % i)
			continue
		if earmarked_units.has(unit_id):
			errors.append("earmarks lists '%s' more than once (one earmark per unit in v1)" % unit_id)
		var verb := str(entry.get("verb", ""))
		earmarked_units[unit_id] = verb
		if verb.is_empty():
			errors.append("Earmark for '%s' missing 'verb'" % unit_id)
			continue
		if RESERVED_VERBS.has(verb):
			errors.append("Earmark verb '%s' on '%s' is %s" % [verb, unit_id, RESERVED_VERBS[verb]])
			continue
		if not VERBS.has(verb):
			errors.append("Unknown earmark verb '%s' on '%s' (expected one of %s)" % [verb, unit_id, ", ".join(VERBS)])
			continue
		match verb:
			"HOLD_OBJECTIVE":
				if str(entry.get("target", "")).is_empty():
					errors.append("Earmark HOLD_OBJECTIVE on '%s' requires a 'target' objective id" % unit_id)
			"RESERVE_UNTIL":
				# RESERVE_UNTIL is UI sugar over deployment.reserves; that list is
				# the single source of truth, so the two must agree exactly.
				if not entry.has("round"):
					errors.append("Earmark RESERVE_UNTIL on '%s' requires a 'round'" % unit_id)
				else:
					var want := int(entry.get("round", 0))
					if want < RESERVE_ROUND_MIN or want > RESERVE_ROUND_MAX:
						errors.append("Earmark RESERVE_UNTIL on '%s' has round %d (expected %d-%d)" % [unit_id, want, RESERVE_ROUND_MIN, RESERVE_ROUND_MAX])
					if not reserve_rounds.has(unit_id):
						errors.append("Earmark RESERVE_UNTIL on '%s' contradicts deployment.reserves: the unit is not listed there (the reserves list is the single source of truth)" % unit_id)
					elif int(reserve_rounds[unit_id]) != want:
						errors.append("Earmark RESERVE_UNTIL on '%s' says round %d but deployment.reserves says round %d" % [unit_id, want, int(reserve_rounds[unit_id])])

	# --- Profile fragment -------------------------------------------------
	if plan.has("profile_fragment"):
		var fragment = plan["profile_fragment"]
		if not (fragment is Dictionary):
			errors.append("'profile_fragment' must be a Dictionary")
		else:
			if fragment.has("parameters") and not (fragment["parameters"] is Dictionary):
				errors.append("profile_fragment.parameters must be a Dictionary")
			if fragment.has("rules") and not (fragment["rules"] is Array):
				errors.append("profile_fragment.rules must be an Array")

	# --- Army-dependent checks -------------------------------------------
	var cover := {}
	if not army.is_empty():
		cover = coverage(plan, army)
		for w in cover.get("warnings", []):
			warnings.append(w)
		var cap_result := _validate_reserves_caps(reserve_rounds, attached_chars, army, cover)
		for e in cap_result.get("errors", []):
			errors.append(e)
		for w in _attachment_legality_notes(attached_chars, army):
			warnings.append(w)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"coverage": cover,
	}

static func _attachment_legality_notes(attached_chars: Dictionary, army: Dictionary) -> Array:
	"""PM-F2 — flag a leader/bodyguard pairing the game cannot make.

	Mirrors the checks FormationsPhase applies to DECLARE_LEADER_ATTACHMENT
	(:183-217): the character must have the CHARACTER keyword and a non-empty
	`meta.leader_data.can_lead` (extended by the Taktikal Brigade enhancement
	extras, the same static helper the phase uses), the bodyguard must not be a
	CHARACTER, and one of the can_lead keywords must appear on the bodyguard.

	WARNINGS, not errors — matching the coherency-note precedent: an impossible
	attachment is not an illegal game state, because at play time the phase
	never offers it and the AI silently falls back to its own pairing. That
	silence is exactly the defect: the author sees the plan "work" while the
	attachment they asked for never happens. The warning reaches players
	through the plan browser badge.

	Units that do not resolve in the army are left to coverage(), which
	already reports them."""
	var notes: Array = []
	var units := _army_units(army)
	for char_id in attached_chars:
		var body_id := str(attached_chars[char_id])
		var character: Dictionary = units.get(str(char_id), {})
		var bodyguard: Dictionary = units.get(body_id, {})
		if character.is_empty() or bodyguard.is_empty():
			continue
		var char_kw: Array = character.get("meta", {}).get("keywords", [])
		if not ("CHARACTER" in char_kw):
			notes.append("Attachment '%s' -> '%s': '%s' is not a CHARACTER — the game will never offer this attachment and the AI will pick its own pairing" % [char_id, body_id, char_id])
			continue
		var raw_can_lead = character.get("meta", {}).get("leader_data", {}).get("can_lead", [])
		var can_lead: Array = raw_can_lead.duplicate() if raw_can_lead is Array else []
		# Taktikal Brigade enhancement extras, INLINED from
		# CharacterAttachmentManager.get_enhancement_can_lead_extras rather than
		# loaded from it. load()ing that script here fails in exactly the
		# headless `-s` harness that tests this file (it references autoload
		# identifiers, "Compile Error: Identifier not found: GameState") — and a
		# failed load() inside a static function ABORTS the function, which
		# silently emptied every note this helper exists to produce. Measured,
		# not theorised: the loop body below never ran until this was inlined.
		for enh in character.get("meta", {}).get("enhancements", []):
			var enh_name := str(enh.get("name", "")) if enh is Dictionary else str(enh)
			match enh_name:
				"Skwad Leader":
					if not "KOMMANDOS" in can_lead:
						can_lead.append("KOMMANDOS")
				"Mek Kaptin":
					if not "FLASH GITZ" in can_lead:
						can_lead.append("FLASH GITZ")
		if can_lead.is_empty():
			notes.append("Attachment '%s' -> '%s': '%s' has no Leader ability (empty can_lead) — the game will never offer this attachment and the AI will pick its own pairing" % [char_id, body_id, char_id])
			continue
		var bg_kw_upper: Array = []
		for kw in bodyguard.get("meta", {}).get("keywords", []):
			bg_kw_upper.append(str(kw).to_upper())
		if "CHARACTER" in bg_kw_upper:
			notes.append("Attachment '%s' -> '%s': the bodyguard is itself a CHARACTER — characters cannot attach to characters" % [char_id, body_id])
			continue
		var leads := false
		for kw in can_lead:
			if str(kw).to_upper() in bg_kw_upper:
				leads = true
				break
		if not leads:
			notes.append("Attachment '%s' -> '%s': '%s' can lead %s, and '%s' has none of those keywords — the attachment will silently not happen" % [char_id, body_id, char_id, str(can_lead), body_id])
	return notes

static func _validate_reserves_caps(reserve_rounds: Dictionary, attached_chars: Dictionary, army: Dictionary, cover: Dictionary) -> Dictionary:
	"""Mirror FormationsPhase.gd:400-420 — 50% points and 50% unit-count caps.

	Points include any character the plan attaches to a reserved bodyguard
	(FormationsPhase._get_declared_reserves_points, :802-812). The unit-count
	cap counts reserves ENTRIES only (:814-816)."""
	var errors: Array[String] = []
	var units := _army_units(army)
	if units.is_empty():
		return {"errors": errors}

	var total_points := 0
	var total_units := 0
	for uid in units.keys():
		total_points += int(units[uid].get("meta", {}).get("points", 0))
		total_units += 1
	var max_points := int(total_points * RESERVES_FRACTION)
	var max_units := int(total_units * RESERVES_FRACTION)

	var matched: Dictionary = cover.get("matched", {})
	var reserve_points := 0
	for plan_uid in reserve_rounds.keys():
		var army_uid := str(matched.get(plan_uid, plan_uid))
		if not units.has(army_uid):
			continue
		reserve_points += int(units[army_uid].get("meta", {}).get("points", 0))
		# A character attached to a reserved bodyguard goes into reserves with it.
		for char_id in attached_chars.keys():
			if str(attached_chars[char_id]) != plan_uid:
				continue
			var army_char := str(matched.get(char_id, char_id))
			if units.has(army_char):
				reserve_points += int(units[army_char].get("meta", {}).get("points", 0))

	if reserve_points > max_points:
		errors.append("deployment.reserves exceeds the 50%% points cap: %d > %d (of %d total)" % [reserve_points, max_points, total_points])
	if reserve_rounds.size() > max_units:
		errors.append("deployment.reserves exceeds the 50%% unit cap: %d > %d (of %d total units)" % [reserve_rounds.size(), max_units, total_units])
	return {"errors": errors}

# ============================================================
# COVERAGE
# ============================================================

static func _placement_coherency_note(unit_id: String, models_inches: Array, army_unit: Dictionary) -> String:
	""""" when the placement holds together under the rules the game actually
	plays; otherwise a warning string naming the offending models.

	PM-F4. Two things about this check are deliberate.

	FIRST, it is pinned to edition 11 rather than to whatever the running
	process happens to be set to. A plan is a durable artifact — authored in
	one process and consumed in another — and every PLAYER launch runs 11e
	(SettingsService re-asserts it at boot; the 10e pin exists only for the
	legacy regression harness). Validating against the ambient edition is
	exactly how PM-F4 happened: the PM-10 authoring pass ran as
	`godot -s tests/spikes/...`, which SettingsService treats as an automated
	harness and pins to 10e, so `DeploymentPhase.validate_action` accepted an
	11-model Gretchin line 13.60" across. At play time — edition 11 — the
	consumer refused that same placement and fell back to the formula, in
	every game, on both seats, with nothing to see but a fallback log line.

	SECOND, it calls `AttackSequence.check_unit_coherency` rather than
	restating the rule. That is the same helper `DeploymentPhase` and
	`AIDecisionMaker._plan_positions_legal` both go through, so the
	validator's answer cannot drift from the consumer's — which was the whole
	point of PM-F4.

	Needs the army for base sizes: coherency is measured base edge to base
	edge, so centre-to-centre distances alone would reject legal placements.
	No army, no check."""
	var army_models = army_unit.get("models", [])
	if not (army_models is Array) or army_models.size() < models_inches.size() or models_inches.size() < 2:
		return ""
	# Loaded at call time, not preloaded: see the note at the top of this file
	# about autoload identifiers and `godot -s`.
	var AS = load("res://scripts/rules/AttackSequence.gd")
	if AS == null or not AS.has_method("check_unit_coherency"):
		return ""

	var probe: Array = []
	for i in range(models_inches.size()):
		var raw = models_inches[i]
		if not (raw is Array) or raw.size() < 2:
			return ""  # malformed — already reported as an error above
		var src: Dictionary = army_models[i] if army_models[i] is Dictionary else {}
		probe.append({
			"id": str(src.get("id", "m%d" % i)),
			"alive": true,
			"rotation": 0.0,
			"position": Vector2(float(raw[0]) * 40.0, float(raw[1]) * 40.0),
			"base_mm": src.get("base_mm", 32),
			"base_type": src.get("base_type", null),
			"base_dimensions": src.get("base_dimensions", {}),
		})

	var previous_edition = GameConstants.edition
	GameConstants.edition = 11
	var result: Dictionary = AS.check_unit_coherency({"models": probe})
	GameConstants.edition = previous_edition

	if bool(result.get("coherent", true)):
		return ""
	var offenders: Array = result.get("offenders", [])
	return "Placement '%s': %d of %d models break 11th-edition unit coherency (03.03 — every model within 2\" of another AND within 9\" of every other model in the unit). The consumer will try to repair the placement and otherwise deploy this unit with the formula instead" % [
		unit_id, offenders.size(), models_inches.size()]

static func _army_units(army: Dictionary) -> Dictionary:
	"""Accept an ArmyListManager army dict, a GameState snapshot, or a bare
	{unit_id: unit} map."""
	if army.has("units") and army["units"] is Dictionary:
		return army["units"]
	if army.has("state") and army["state"] is Dictionary:
		var st: Dictionary = army["state"]
		if st.has("units") and st["units"] is Dictionary:
			return st["units"]
	return army

static func _collect_plan_units(plan: Dictionary) -> Dictionary:
	"""Every distinct unit reference in the plan -> {unit_name, role_fallback}."""
	var refs := {}
	var deployment = plan.get("deployment", {})
	if not (deployment is Dictionary):
		deployment = {}

	for oid in deployment.get("order", []):
		var s := str(oid)
		if not s.is_empty() and not refs.has(s):
			refs[s] = {"unit_name": "", "role_fallback": ""}
	for placement in deployment.get("placements", []):
		if not (placement is Dictionary):
			continue
		var s := str(placement.get("unit", ""))
		if s.is_empty():
			continue
		if not refs.has(s):
			refs[s] = {"unit_name": "", "role_fallback": ""}
		if not str(placement.get("unit_name", "")).is_empty():
			refs[s]["unit_name"] = str(placement["unit_name"])
		if not str(placement.get("role_fallback", "")).is_empty():
			refs[s]["role_fallback"] = str(placement["role_fallback"])
	for section in ["reserves"]:
		for entry in deployment.get(section, []):
			if entry is Dictionary:
				var s := str(entry.get("unit", ""))
				if not s.is_empty() and not refs.has(s):
					refs[s] = {"unit_name": "", "role_fallback": ""}
	for entry in deployment.get("embarkations", []):
		if entry is Dictionary:
			for field in ["unit", "transport"]:
				var s := str(entry.get(field, ""))
				if not s.is_empty() and not refs.has(s):
					refs[s] = {"unit_name": "", "role_fallback": ""}
	for entry in deployment.get("attachments", []):
		if entry is Dictionary:
			for field in ["character", "bodyguard"]:
				var s := str(entry.get(field, ""))
				if not s.is_empty() and not refs.has(s):
					refs[s] = {"unit_name": "", "role_fallback": ""}
	for entry in plan.get("earmarks", []):
		if entry is Dictionary:
			var s := str(entry.get("unit", ""))
			if s.is_empty():
				continue
			if not refs.has(s):
				refs[s] = {"unit_name": "", "role_fallback": ""}
			if not str(entry.get("unit_name", "")).is_empty() and str(refs[s]["unit_name"]).is_empty():
				refs[s]["unit_name"] = str(entry["unit_name"])
	return refs

static func coverage(plan: Dictionary, army: Dictionary) -> Dictionary:
	"""How much of the army the plan covers, and how each reference resolves.

	Resolution order per reference (locked design decision 4):
	  1. army-file unit id (exact, no warning) — ids are the stable key,
	  2. `unit_name` matching EXACTLY ONE army unit (warning) — names are NOT
	     unique (recon_stomps has 4x "Stormboyz", 4x "Warbikers"),
	  3. `role_fallback` (warning) — the consumer degrades to role behaviour,
	  4. unmatched."""
	var units := _army_units(army)
	var refs := _collect_plan_units(plan)
	var warnings: Array[String] = []
	var matched := {}
	var matched_by := {}
	var unmatched: Array[String] = []

	# name -> [unit_id, ...] so duplicates can be detected rather than guessed at.
	var by_name := {}
	for uid in units.keys():
		var unit = units[uid]
		if not (unit is Dictionary):
			continue
		var nm := str(unit.get("meta", {}).get("name", ""))
		if nm.is_empty():
			continue
		if not by_name.has(nm):
			by_name[nm] = []
		by_name[nm].append(str(uid))

	for ref in refs.keys():
		if units.has(ref):
			matched[ref] = ref
			matched_by[ref] = "id"
			continue
		var hint: Dictionary = refs[ref]
		var nm := str(hint.get("unit_name", ""))
		if not nm.is_empty() and by_name.has(nm):
			var candidates: Array = by_name[nm]
			if candidates.size() == 1:
				matched[ref] = candidates[0]
				matched_by[ref] = "name"
				warnings.append("Plan unit '%s' is not in the army; matched by unique name '%s' -> '%s'" % [ref, nm, candidates[0]])
				continue
			warnings.append("Plan unit '%s' is not in the army and its name '%s' is ambiguous (%d units share it) — name matching refused" % [ref, nm, candidates.size()])
		var role := str(hint.get("role_fallback", ""))
		if not role.is_empty():
			matched_by[ref] = "role_fallback"
			warnings.append("Plan unit '%s' is not in the army; degrading to role_fallback '%s'" % [ref, role])
			continue
		unmatched.append(ref)
		warnings.append("Plan unit '%s' is not in the army and has no unit_name/role_fallback — this entry will be ignored" % ref)

	unmatched.sort()
	return {
		"units_in_plan": refs.size(),
		"units_in_army": units.size(),
		"matched": matched,
		"matched_by": matched_by,
		"unmatched": unmatched,
		"warnings": warnings,
	}

# ============================================================
# CONVENIENCE
# ============================================================

static func load_plan_file(path: String) -> Dictionary:
	"""Parse a plan JSON file. Returns {} on any failure (ProfileManager style)."""
	if not FileAccess.file_exists(path):
		push_warning("PlanValidator: Plan file not found: %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PlanValidator: Failed to open plan file: %s" % path)
		return {}
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_warning("PlanValidator: Failed to parse plan JSON '%s': %s (line %d)" % [path, json.get_error_message(), json.get_error_line()])
		return {}
	if not (json.data is Dictionary):
		push_warning("PlanValidator: Plan '%s' root is not a Dictionary" % path)
		return {}
	return json.data

static func describe_result(result: Dictionary) -> String:
	"""One-line human summary, for logs and the plan browser badge."""
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])
	if not result.get("valid", false):
		return "INVALID — %d error(s): %s" % [errors.size(), "; ".join(errors)]
	if warnings.is_empty():
		return "VALID"
	return "VALID with %d warning(s): %s" % [warnings.size(), "; ".join(warnings)]
