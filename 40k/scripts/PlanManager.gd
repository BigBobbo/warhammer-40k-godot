class_name PlanManager
extends RefCounted

# PlanManager — storage, listing and matching for `wh40k_ai_plan` artifacts.
#
# Pure storage + matching. It answers one question for the AI:
#   "which plan, if any, applies to this game for player N?"
# Consumption (following a plan's deployment order, mirroring coordinates for
# seat 2, applying earmarks) lives in AIDecisionMaker, mirroring how
# ProfileManager stores profiles while load_player_profile/clear_player_profile
# live on the decision maker.
#
# Style mirrors ProfileManager.gd: all-static RefCounted, user:// bootstrap,
# push_warning + empty dict on error.
#
# Search path (NON-recursive, both directories):
#   user://ai_plans/       player-authored plans (writable)
#   res://data/ai_plans/   shipped plans (read-only; may not exist yet)
# Test fixtures under res://tests/fixtures/ai_plans/ are deliberately OUTSIDE
# the search path — they are loaded by explicit path and must never appear in
# the player-facing plan browser.

const _Validator = preload("res://scripts/PlanValidator.gd")

const USER_PLANS_DIR: String = "user://ai_plans/"
const SHIPPED_PLANS_DIR: String = "res://data/ai_plans/"

# Match ranks, best first. Kept as named constants so callers and logs agree.
const MATCH_EXACT: int = 0        # army + zone + layout all match
const MATCH_LAYOUT_WILDCARD: int = 1  # army + zone match, plan names no layout
const MATCH_NONE: int = -1

# ============================================================
# LOGGING
# ============================================================

static func _log(message: String) -> void:
	"""Console + debug file. Godot stdout is not always reachable, so every
	matching decision also goes through DebugLogger (CLAUDE.md)."""
	print("PlanManager: %s" % message)
	var main_loop = Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return
	var logger = (main_loop as SceneTree).root.get_node_or_null("DebugLogger")
	if logger != null and logger.has_method("info"):
		logger.info("[PlanManager] %s" % message)

# ============================================================
# PATHS AND STORAGE
# ============================================================

static func get_user_plans_dir() -> String:
	return USER_PLANS_DIR

static func get_shipped_plans_dir() -> String:
	return SHIPPED_PLANS_DIR

static func ensure_user_plans_dir() -> void:
	var dir = DirAccess.open("user://")
	if dir == null:
		push_warning("PlanManager: Cannot open user:// directory")
		return
	if not dir.dir_exists("ai_plans"):
		var err = dir.make_dir("ai_plans")
		if err != OK:
			push_warning("PlanManager: Failed to create ai_plans directory: %s" % err)
		else:
			_log("Created ai_plans directory at %s" % USER_PLANS_DIR)

static func slugify(plan_name: String) -> String:
	"""Lowercase; every non-alphanumeric run becomes a single underscore."""
	var out := ""
	var last_was_sep := false
	for i in range(plan_name.length()):
		var c := plan_name[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			last_was_sep = false
		elif not last_was_sep:
			out += "_"
			last_was_sep = true
	out = out.strip_edges().lstrip("_").rstrip("_")
	if out.is_empty():
		out = "plan"
	return out

static func _list_dir_json(dir_path: String) -> Array:
	"""Non-recursive listing of *.json in dir_path. Missing dir -> []."""
	var paths: Array = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			paths.append(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths

static func list_plans() -> Array:
	"""All plans on the search path as
	{name, path, source, plan, metadata:{...}} entries, user:// first.

	Metadata carries the browser row: description, author, army_file, zone,
	layout, and the PlanValidator badge (valid/errors/warnings)."""
	ensure_user_plans_dir()
	var entries: Array = []
	for source in [{"dir": USER_PLANS_DIR, "tag": "user"}, {"dir": SHIPPED_PLANS_DIR, "tag": "shipped"}]:
		for path in _list_dir_json(source["dir"]):
			var plan := load_plan_file(path)
			if plan.is_empty():
				push_warning("PlanManager: Skipping unreadable plan %s" % path)
				continue
			var keys: Dictionary = plan.get("keys", {}) if plan.get("keys", {}) is Dictionary else {}
			# PM-F4: hand the validator the army named in the plan's own keys.
			# Base sizes are what the coherency check needs, and without them it
			# declines — so the badge would read a clean "OK" for a plan whose
			# unit is too spread out for the AI to deploy as drawn.
			var result: Dictionary = _Validator.validate_plan(plan,
				{"units": army_units_for_file(str(keys.get("army_file", "")))})
			entries.append({
				"name": str(plan.get("name", path.get_file().get_basename())),
				"path": path,
				"source": source["tag"],
				"plan": plan,
				"metadata": {
					"description": str(plan.get("description", "")),
					"author": str(plan.get("author", "")),
					"army_file": str(keys.get("army_file", "")),
					"deployment_zone_id": str(keys.get("deployment_zone_id", "")),
					"terrain_layout_id": str(keys.get("terrain_layout_id", "")),
					"valid": result.get("valid", false),
					"errors": result.get("errors", []),
					"warnings": result.get("warnings", []),
				},
			})
	_log("Found %d plan(s) on the search path" % entries.size())
	return entries

static func load_plan_file(path: String) -> Dictionary:
	"""Load a plan by EXPLICIT path (this is how test fixtures are loaded)."""
	return _Validator.load_plan_file(path)

static func find_plan_path(slug_or_name: String) -> String:
	"""Resolve a slug (or plan name) to a path, user:// winning over res://."""
	var slug := slugify(slug_or_name)
	for dir_path in [USER_PLANS_DIR, SHIPPED_PLANS_DIR]:
		var candidate: String = str(dir_path) + slug + ".json"
		if FileAccess.file_exists(candidate):
			return candidate
	# Fall back to a name match across the search path.
	for entry in list_plans():
		if str(entry["name"]) == slug_or_name:
			return str(entry["path"])
	return ""

static func load_plan(slug_or_name: String) -> Dictionary:
	var path := find_plan_path(slug_or_name)
	if path.is_empty():
		push_warning("PlanManager: No plan found for '%s'" % slug_or_name)
		return {}
	return load_plan_file(path)

static func save_plan(plan: Dictionary, army: Dictionary = {}) -> Dictionary:
	"""Validate then write to user://ai_plans/<slug>.json.

	An INVALID plan is refused — the whole point of the format is that a plan
	cannot describe an illegal game state, so saving one would defeat it.
	Returns {success, path, errors, warnings}."""
	var result: Dictionary = _Validator.validate_plan(plan, army)
	if not result.get("valid", false):
		push_warning("PlanManager: Refusing to save invalid plan '%s': %s" % [
			plan.get("name", "?"), "; ".join(result.get("errors", []))])
		_log("Refused to save invalid plan '%s' (%d error(s))" % [plan.get("name", "?"), result.get("errors", []).size()])
		return {"success": false, "path": "", "errors": result.get("errors", []), "warnings": result.get("warnings", [])}

	ensure_user_plans_dir()
	var path := USER_PLANS_DIR + slugify(str(plan.get("name", ""))) + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := "Failed to open plan file for writing: %s" % path
		push_warning("PlanManager: %s" % err)
		return {"success": false, "path": "", "errors": [err], "warnings": result.get("warnings", [])}
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()
	_log("Saved plan '%s' to %s" % [plan.get("name", "?"), path])
	return {"success": true, "path": path, "errors": [], "warnings": result.get("warnings", [])}

static func rename_plan(path: String, new_name: String) -> Dictionary:
	"""Rename a user:// plan: rewrite `name` and move the file to the new slug.

	Shipped res:// plans cannot be renamed — they do not exist as writable files
	in an export. Returns {success, path, error}."""
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return {"success": false, "path": path, "error": "A plan needs a name."}
	if not path.begins_with(USER_PLANS_DIR):
		return {"success": false, "path": path,
			"error": "Shipped plans cannot be renamed — save a copy of your own instead."}
	var plan := load_plan_file(path)
	if plan.is_empty():
		return {"success": false, "path": path, "error": "Could not read %s" % path}

	var new_path := USER_PLANS_DIR + slugify(trimmed) + ".json"
	if new_path != path and FileAccess.file_exists(new_path):
		return {"success": false, "path": path,
			"error": "A plan called '%s' already exists." % trimmed}

	plan["name"] = trimmed
	var file = FileAccess.open(new_path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "path": path, "error": "Could not write %s" % new_path}
	file.store_string(JSON.stringify(plan, "\t"))
	file.close()

	# Only unlink the old file once the new one is safely on disk, so a failed
	# write can never lose the plan.
	if new_path != path:
		var dir = DirAccess.open(USER_PLANS_DIR)
		if dir != null:
			dir.remove(path.get_file())
	_log("Renamed plan '%s' -> '%s' (%s)" % [path.get_file(), trimmed, new_path])
	return {"success": true, "path": new_path, "error": ""}

static func delete_plan(path: String) -> bool:
	"""Delete a user:// plan. Shipped res:// plans cannot be deleted (they do
	not exist as files in an exported build)."""
	if not path.begins_with(USER_PLANS_DIR):
		push_warning("PlanManager: Refusing to delete non-user plan: %s" % path)
		return false
	if not FileAccess.file_exists(path):
		push_warning("PlanManager: Cannot delete — plan not found: %s" % path)
		return false
	var dir = DirAccess.open(USER_PLANS_DIR)
	if dir == null:
		push_warning("PlanManager: Cannot open plans directory for deletion")
		return false
	var err = dir.remove(path.get_file())
	if err != OK:
		push_warning("PlanManager: Failed to delete plan '%s': %s" % [path, err])
		return false
	_log("Deleted plan %s" % path)
	return true

# ============================================================
# UNIT-ID RESOLUTION
# ============================================================

static func resolve_unit_id(plan_unit_id: String, player: int, units: Dictionary) -> String:
	"""Map a plan's army-file unit id onto the id this game actually uses.

	When both seats pick the SAME army list, ArmyListManager re-keys the second
	copy with a deterministic `_P<player>` suffix so the two players' units do
	not collide (ArmyListManager.gd:333-346). A plan authored against the army
	file therefore has to look through that suffix when it is consumed at the
	re-keyed seat — every mirror match hits this. Returns "" when neither form
	is owned by `player`.

	The suffixed form is tried FIRST: in a mirror match both forms exist, and
	the plain id belongs to the OTHER player."""
	if plan_unit_id.is_empty():
		return ""
	var suffixed := "%s_P%d" % [plan_unit_id, player]
	if _is_owned_by(units, suffixed, player):
		return suffixed
	if _is_owned_by(units, plan_unit_id, player):
		return plan_unit_id
	return ""

static func _is_owned_by(units: Dictionary, unit_id: String, player: int) -> bool:
	if not units.has(unit_id):
		return false
	var unit = units[unit_id]
	if not (unit is Dictionary) or not unit.has("owner"):
		return true  # ownerless fixtures: presence is enough
	return int(unit.get("owner", 0)) == player

static func units_for_player(snapshot: Dictionary, player: int) -> Dictionary:
	"""The player's units, re-keyed back to their army-file ids.

	Strips the `_P<player>` mirror suffix so a plan authored on the army file
	lines up with the live state at either seat."""
	var out := {}
	var units = snapshot.get("units", {})
	if not (units is Dictionary):
		return out
	var suffix := "_P%d" % player
	for unit_id in units.keys():
		var unit = units[unit_id]
		if not (unit is Dictionary):
			continue
		if int(unit.get("owner", 0)) != player:
			continue
		var key := str(unit_id)
		if key.ends_with(suffix):
			key = key.substr(0, key.length() - suffix.length())
		out[key] = unit
	return out

# ============================================================
# MATCHING
# ============================================================

static func resolve_game_identity(player: int, snapshot: Dictionary) -> Dictionary:
	"""What game is this, for player N?

	Menu-started games carry meta.game_config with the selected army file names.
	Fixtures do NOT: the shipped predeploy saves have no `game_config` key at
	all (verified by decompressing mirror_orks_2000_predeploy.w40ksave), so the
	only identity available there is state.factions[str(player)] plus
	meta.deployment_type and board.terrain_layout."""
	var meta = snapshot.get("meta", {})
	if not (meta is Dictionary):
		meta = {}
	var board = snapshot.get("board", {})
	if not (board is Dictionary):
		board = {}
	var game_config = meta.get("game_config", {})
	if not (game_config is Dictionary):
		game_config = {}

	var factions = snapshot.get("factions", {})
	if not (factions is Dictionary):
		factions = {}
	# state.factions is keyed by the STRING player number (GameState.gd:162/211).
	var faction = factions.get(str(player), {})
	if not (faction is Dictionary):
		faction = {}

	var army_key := str(game_config.get("player%d_army" % player, ""))
	return {
		"army_key": army_key,
		"identity_source": "game_config" if not army_key.is_empty() else "factions",
		"faction_name": str(faction.get("name", "")),
		"detachment": str(faction.get("detachment", "")),
		"zone_id": str(meta.get("deployment_type", "")),
		"layout_id": str(board.get("terrain_layout", "")),
	}

static var _army_faction_cache: Dictionary = {}
static var _army_json_cache: Dictionary = {}

static func _army_json(army_file: String) -> Dictionary:
	"""res://armies/<army_file>.json (user:// fallback, as
	ArmyListManager.load_army_list does). Cached; {} when unreadable."""
	if army_file.is_empty():
		return {}
	if _army_json_cache.has(army_file):
		return _army_json_cache[army_file]
	var data := {}
	for path in ["res://armies/%s.json" % army_file, "user://armies/%s.json" % army_file]:
		if not FileAccess.file_exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var json = JSON.new()
		var err = json.parse(file.get_as_text())
		file.close()
		if err == OK and json.data is Dictionary:
			data = json.data
		break
	_army_json_cache[army_file] = data
	return data

static func _army_faction(army_file: String) -> Dictionary:
	"""faction dict of the army list. Cached; {} when unreadable."""
	if army_file.is_empty():
		return {}
	if _army_faction_cache.has(army_file):
		return _army_faction_cache[army_file]
	var faction = _army_json(army_file).get("faction", {})
	if not (faction is Dictionary):
		faction = {}
	_army_faction_cache[army_file] = faction
	return faction

static func army_units_for_file(army_file: String) -> Dictionary:
	"""The army's units, keyed by unit id — what PlanValidator needs to check
	anything that depends on a model's BASE, coherency included (PM-F4).

	The browser badge is built from a plan file alone, with no game running, so
	the army has to be resolved from the plan's own `keys.army_file`. Without
	it `validate_plan` has no base sizes and declines the coherency check, and
	the row reads a clean "OK" for a plan the AI will refuse to deploy as
	drawn — which is exactly the silence PM-F4 was about."""
	var units = _army_json(army_file).get("units", {})
	return units if units is Dictionary else {}

static func clear_army_faction_cache() -> void:
	_army_faction_cache.clear()
	_army_json_cache.clear()

static func _army_matches(plan_keys: Dictionary, identity: Dictionary) -> Dictionary:
	"""{matched: bool, reason: String}. Two paths, never mixed:
	  - menu games: the army FILE NAME must match exactly;
	  - fixtures (no game_config): the plan's army file's faction name must
	    match the live faction, and the detachment must agree when both are
	    known."""
	var plan_army := str(plan_keys.get("army_file", ""))
	if plan_army.is_empty():
		return {"matched": false, "reason": "plan has no keys.army_file"}

	if str(identity.get("identity_source", "")) == "game_config":
		var army_key := str(identity.get("army_key", ""))
		if plan_army == army_key:
			return {"matched": true, "reason": "army_file == game_config army '%s'" % army_key}
		return {"matched": false, "reason": "army_file '%s' != game_config army '%s'" % [plan_army, army_key]}

	var live_name := str(identity.get("faction_name", ""))
	if live_name.is_empty():
		return {"matched": false, "reason": "no game_config and no faction name in the snapshot"}
	var plan_faction := _army_faction(plan_army)
	var plan_faction_name := str(plan_faction.get("name", ""))
	if plan_faction_name.is_empty():
		return {"matched": false, "reason": "army file '%s' is unreadable, cannot fall back to faction matching" % plan_army}
	if plan_faction_name.to_lower() != live_name.to_lower():
		return {"matched": false, "reason": "faction '%s' != live faction '%s'" % [plan_faction_name, live_name]}

	var plan_detachment := str(plan_keys.get("detachment_hint", ""))
	if plan_detachment.is_empty():
		plan_detachment = str(plan_faction.get("detachment", ""))
	var live_detachment := str(identity.get("detachment", ""))
	if not plan_detachment.is_empty() and not live_detachment.is_empty():
		if plan_detachment.to_lower() != live_detachment.to_lower():
			return {"matched": false, "reason": "detachment '%s' != live detachment '%s'" % [plan_detachment, live_detachment]}
	return {"matched": true, "reason": "faction fallback: '%s'/'%s'" % [plan_faction_name, live_detachment]}

static func rank_plan(plan: Dictionary, identity: Dictionary) -> Dictionary:
	"""{rank, reason}. rank == MATCH_NONE when the plan does not apply."""
	var keys = plan.get("keys", {})
	if not (keys is Dictionary):
		return {"rank": MATCH_NONE, "reason": "plan has no keys block"}

	var zone_id := str(identity.get("zone_id", ""))
	if zone_id.is_empty():
		return {"rank": MATCH_NONE, "reason": "snapshot has no meta.deployment_type"}

	var army := _army_matches(keys, identity)
	if not army.get("matched", false):
		return {"rank": MATCH_NONE, "reason": str(army.get("reason", ""))}

	if str(keys.get("deployment_zone_id", "")) != zone_id:
		return {"rank": MATCH_NONE, "reason": "zone '%s' != live zone '%s'" % [str(keys.get("deployment_zone_id", "")), zone_id]}

	var plan_layout := str(keys.get("terrain_layout_id", ""))
	var live_layout := str(identity.get("layout_id", ""))
	if plan_layout.is_empty():
		return {"rank": MATCH_LAYOUT_WILDCARD, "reason": "%s, zone '%s', layout wildcard" % [str(army.get("reason", "")), zone_id]}
	if plan_layout == live_layout:
		return {"rank": MATCH_EXACT, "reason": "%s, zone '%s', layout '%s'" % [str(army.get("reason", "")), zone_id, live_layout]}
	return {"rank": MATCH_NONE, "reason": "layout '%s' != live layout '%s'" % [plan_layout, live_layout]}

static func find_plan_match_for(player: int, snapshot: Dictionary) -> Dictionary:
	"""Best matching plan for player N, as {plan, path, name, rank, reason}.

	Matching is SEAT-AGNOSTIC: a plan authored in the player-1 frame matches at
	either seat, and the [44-x, 60-y] coordinate transform is consumption's job
	(PM-2a), not matching's.

	Only VALID plans are considered — a plan the validator rejects must never
	drive the AI. Ties break deterministically: rank, then SOURCE (a plan you
	wrote beats a shipped one), then plan name, then path.

	The source tie-break is load-bearing, not tidiness. Before PM-10 there were
	no shipped plans, so a user plan was always the only candidate at its rank
	and the name comparison never had to arbitrate between the two. The moment
	plans shipped, a player who wrote their own plan for a matchup a shipped
	plan also covers would silently get the SHIPPED one whenever its name sorted
	earlier — 'Orks — Recon Stomps on Crucible' beats 'PM1 Real Fixture' on 'o'
	< 'p', which is how this was found. Your own plan wins."""
	var identity := resolve_game_identity(player, snapshot)
	if str(identity.get("zone_id", "")).is_empty():
		_log("No plan for player %d: snapshot carries no meta.deployment_type" % player)
		return {}

	var army_units := units_for_player(snapshot, player)
	var candidates: Array = []
	var rejected: Array = []
	for entry in list_plans():
		var plan: Dictionary = entry["plan"]
		var verdict := rank_plan(plan, identity)
		if int(verdict["rank"]) == MATCH_NONE:
			rejected.append("%s (%s)" % [entry["name"], verdict["reason"]])
			continue
		var validation: Dictionary = _Validator.validate_plan(plan, {"units": army_units})
		if not validation.get("valid", false):
			rejected.append("%s (INVALID: %s)" % [entry["name"], "; ".join(validation.get("errors", []))])
			continue
		candidates.append({
			"plan": plan,
			"path": str(entry["path"]),
			"name": str(entry["name"]),
			"source": str(entry.get("source", "")),
			"rank": int(verdict["rank"]),
			"reason": str(verdict["reason"]),
			"warnings": validation.get("warnings", []),
		})

	if candidates.is_empty():
		_log("No plan matches for player %d (identity: army '%s' via %s, zone '%s', layout '%s'); considered %d, rejected: %s" % [
			player, identity.get("army_key", identity.get("faction_name", "?")),
			identity.get("identity_source", "?"), identity.get("zone_id", ""), identity.get("layout_id", ""),
			rejected.size(), "; ".join(rejected) if not rejected.is_empty() else "(none on search path)"])
		return {}

	candidates.sort_custom(func(a, b):
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		# A plan the player wrote beats a shipped one at the same rank. Rank
		# still dominates: a more specific shipped plan beats a vaguer one of
		# your own, which is the right way round.
		var a_mine: bool = str(a.get("source", "")) == "user"
		var b_mine: bool = str(b.get("source", "")) == "user"
		if a_mine != b_mine:
			return a_mine
		var an: String = str(a["name"]).to_lower()
		var bn: String = str(b["name"]).to_lower()
		if an != bn:
			return an < bn
		return str(a["path"]) < str(b["path"]))

	var winner: Dictionary = candidates[0]
	_log("Player %d -> plan '%s' (%s, rank %d: %s)%s" % [
		player, winner["name"], winner["path"], winner["rank"], winner["reason"],
		"" if winner["warnings"].is_empty() else (" [%d warning(s): %s]" % [winner["warnings"].size(), "; ".join(winner["warnings"])])])
	return winner

static func find_plan_for(player: int, snapshot: Dictionary) -> Dictionary:
	"""The plan dictionary that applies to player N, or {} when none does."""
	var match_result := find_plan_match_for(player, snapshot)
	return match_result.get("plan", {}) if not match_result.is_empty() else {}
