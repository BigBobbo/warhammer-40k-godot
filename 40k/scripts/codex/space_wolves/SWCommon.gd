extends RefCounted

## SWCommon — shared helpers for the Codex: Space Marines (11e) Space Wolves
## modules (scripts/codex/space_wolves/). Plan + contract:
## .llm/codex_11e_wahapedia/PLAN_SPACE_WOLVES.md and IMPLEMENTATION.md.
##
## The Space Wolves modules (SWArmyRules11e.gd, SWDetachments11e.gd,
## SWEnhancements11e.gd, SWCodex11e.gd + group scripts, SWAbilities11e.gd)
## preload ONLY this file, never each other, so parallel work packages never
## build preload cycles.
##
## The generic helpers below are a copy of CustodesCommon.gd (same contract);
## the Space Wolves specifics — which armies the codex rules apply to, and the
## COMBAT DOCTRINES state every package reads — are at the end.
##
## Every autoload is reached late-bound (Engine.get_main_loop().root…): a naked
## autoload global fails to compile when a headless `godot -s` test parses a
## script that references it before the autoloads are registered.

const GameStateData = preload("res://autoloads/GameState.gd")

const PX_PER_INCH: float = 40.0

# ---------------------------------------------------------------------------
# Late-bound autoload access
# ---------------------------------------------------------------------------

static func autoload(node_name: String) -> Node:
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null(node_name)
	return null

static func game_state() -> Node:
	return autoload("GameState")

static func rules() -> Node:
	return autoload("RulesEngine")

static func phase_manager() -> Node:
	return autoload("PhaseManager")

static func stratagem_manager() -> Node:
	return autoload("StratagemManager")

static func log_info(msg: String) -> void:
	print(msg)
	var dl = autoload("DebugLogger")
	if dl and dl.has_method("info"):
		dl.info(msg, {})

## Loud failure: push_error (stdout) AND an ERROR line in the debug log so
## verify_delivery / scenario log checks catch the gap.
static func log_error(msg: String) -> void:
	push_error(msg)
	var dl = autoload("DebugLogger")
	if dl and dl.has_method("error"):
		dl.error(msg, {})

## Player-visible Game Log line (GameEventLog).
static func game_log(player: int, msg: String) -> void:
	var gel = autoload("GameEventLog")
	if gel and gel.has_method("add_player_entry"):
		gel.add_player_entry(player, msg)

# ---------------------------------------------------------------------------
# State access
# ---------------------------------------------------------------------------

static func state() -> Dictionary:
	var gs = game_state()
	if gs == null:
		return {}
	return gs.state

static func unit(unit_id: String) -> Dictionary:
	if unit_id == "":
		return {}
	return state().get("units", {}).get(unit_id, {})

static func unit_name(unit_id: String) -> String:
	var u = unit(unit_id)
	if u.is_empty():
		return unit_id
	var meta = u.get("meta", {})
	return str(meta.get("display_name", meta.get("name", unit_id)))

static func active_player() -> int:
	return int(state().get("meta", {}).get("active_player", 1))

static func battle_round() -> int:
	var gs = game_state()
	if gs and gs.has_method("get_battle_round"):
		return int(gs.get_battle_round())
	return int(state().get("meta", {}).get("battle_round", 1))

static func current_phase() -> int:
	return int(state().get("meta", {}).get("phase", -1))

static func player_cp(player: int) -> int:
	return int(state().get("players", {}).get(str(player), {}).get("cp", 0))

## Straight apostrophes, upper-case: the army data spells "Ka'tah" with a
## straight quote, the Wahapedia export with a curly one.
static func norm_name(n: String) -> String:
	return n.replace("’", "'").replace("‘", "'").strip_edges().to_lower()

static func has_keyword(u: Dictionary, keyword: String) -> bool:
	var kw_upper = keyword.to_upper()
	for kw in u.get("meta", {}).get("keywords", []):
		if str(kw).to_upper() == kw_upper:
			return true
	return false

static func has_any_keyword(u: Dictionary, keywords: Array) -> bool:
	for kw in keywords:
		if has_keyword(u, str(kw)):
			return true
	return false

## True when the unit's datasheet lists an ability with this name (String or
## {name: …} entries; apostrophe- and case-insensitive).
static func has_ability(u: Dictionary, ability_name: String) -> bool:
	var want := norm_name(ability_name)
	for a in u.get("meta", {}).get("abilities", []):
		var n := ""
		if a is String:
			n = a
		elif a is Dictionary:
			n = str(a.get("name", ""))
		if norm_name(n) == want:
			return true
	return false

static func is_monster_or_vehicle(u: Dictionary) -> bool:
	return has_any_keyword(u, ["MONSTER", "VEHICLE"])

static func is_alive(u: Dictionary) -> bool:
	for m in u.get("models", []):
		if m.get("alive", true):
			return true
	return false

static func is_on_battlefield(u: Dictionary) -> bool:
	if u.is_empty() or not is_alive(u):
		return false
	var status = int(u.get("status", GameStateData.UnitStatus.DEPLOYED))
	if status == GameStateData.UnitStatus.IN_RESERVES or status == GameStateData.UnitStatus.UNDEPLOYED:
		return false
	if u.get("embarked_in", null) != null and str(u.get("embarked_in", "")) != "":
		return false
	for m in u.get("models", []):
		if m.get("alive", true) and m.get("position", null) != null:
			return true
	return false

## The Attached unit's "head" (the bodyguard unit id) for any component id.
static func head_id(unit_id: String) -> String:
	var re = rules()
	if re and re.has_method("attached_unit_target_id"):
		return str(re.attached_unit_target_id(unit_id, state()))
	return unit_id

## The unit plus every component of its Attached unit (19.03). Attached
## CHARACTERs resolve their attacks against their own unit id, so a unit-wide
## effect must be written to every component.
static func attached_group_ids(unit_id: String) -> Array:
	var units = state().get("units", {})
	var head := head_id(unit_id)
	var out: Array = [head]
	for char_id in units.get(head, {}).get("attachment_data", {}).get("attached_characters", []):
		var cid = str(char_id)
		if cid != "" and not cid in out and units.has(cid):
			out.append(cid)
	if not unit_id in out:
		out.append(unit_id)
	return out

static func is_engaged(unit_id: String) -> bool:
	var re = rules()
	if re and re.has_method("is_unit_engaged"):
		return bool(re.is_unit_engaged(unit_id, state()))
	return false

## Enemy unit ids engaged with any component of `unit_id`'s Attached unit.
static func engaged_enemy_ids(unit_id: String) -> Array:
	var out: Array = []
	var units: Dictionary = state().get("units", {})
	var me := unit(unit_id)
	var owner := int(me.get("owner", 0))
	var re = rules()
	if re == null or not re.has_method("check_units_in_engagement_range"):
		return out
	for gid in attached_group_ids(unit_id):
		var gu: Dictionary = units.get(str(gid), {})
		if gu.is_empty() or not is_alive(gu):
			continue
		for eid in units:
			var eu: Dictionary = units[eid]
			if int(eu.get("owner", 0)) == owner or not is_on_battlefield(eu) or eid in out:
				continue
			if re.check_units_in_engagement_range(gu, eu, state()):
				out.append(eid)
	return out

# ---------------------------------------------------------------------------
# Distance helpers (edge-to-edge, inches)
# ---------------------------------------------------------------------------

## Closest edge-to-edge distance between any two alive, placed models.
static func unit_distance_inches(a: Dictionary, b: Dictionary) -> float:
	if a.is_empty() or b.is_empty():
		return INF
	var meas = autoload("Measurement")
	var best := INF
	for ma in a.get("models", []):
		if not ma.get("alive", true) or ma.get("position", null) == null:
			continue
		for mb in b.get("models", []):
			if not mb.get("alive", true) or mb.get("position", null) == null:
				continue
			var d := INF
			if meas and meas.has_method("model_to_model_distance_inches"):
				d = float(meas.model_to_model_distance_inches(ma, mb))
			else:
				d = _pos(ma).distance_to(_pos(mb)) / PX_PER_INCH
			if d < best:
				best = d
	return best

static func _pos(m: Dictionary) -> Vector2:
	var p = m.get("position", null)
	if p is Vector2:
		return p
	if p is Dictionary:
		return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return Vector2.ZERO

## Distance from `u` to the closest enemy unit on the battlefield (INF = none).
static func nearest_enemy_inches(u: Dictionary) -> float:
	var owner := int(u.get("owner", 0))
	var best := INF
	var units: Dictionary = state().get("units", {})
	for eid in units:
		var eu: Dictionary = units[eid]
		if int(eu.get("owner", 0)) == owner or not is_on_battlefield(eu):
			continue
		best = minf(best, unit_distance_inches(u, eu))
	return best

# ---------------------------------------------------------------------------
# Stratagem helpers (WP-C5: CustodesCodex11e.gd and its group scripts).
# An Attached unit is ONE unit (19.03): every check below looks at all of its
# components (the Ork codex ruling "keyword checks look at the whole Attached
# unit").
# ---------------------------------------------------------------------------

## True when any component of the (Attached) unit has the keyword.
static func group_has_keyword(unit_id: String, keyword: String) -> bool:
	for gid in attached_group_ids(unit_id):
		var gu := unit(str(gid))
		if not gu.is_empty() and has_keyword(gu, keyword):
			return true
	return false

## Models of every component, merged — distances from an Attached unit.
static func group_union(unit_id: String) -> Dictionary:
	var models: Array = []
	var owner := int(unit(unit_id).get("owner", 0))
	for gid in attached_group_ids(unit_id):
		for m in unit(str(gid)).get("models", []):
			models.append(m)
	return {"owner": owner, "models": models, "id": head_id(unit_id)}

## Closest edge-to-edge distance between two (Attached) units, inches.
static func group_distance_inches(a_id: String, b_id: String) -> float:
	return unit_distance_inches(group_union(a_id), group_union(b_id))

## True when any component of `a_id` is engaged with any component of `b_id`.
static func group_engaged_with(a_id: String, b_id: String) -> bool:
	var re = rules()
	if re == null or not re.has_method("check_units_in_engagement_range"):
		return false
	for ga in attached_group_ids(a_id):
		var ua := unit(str(ga))
		if ua.is_empty() or not is_alive(ua):
			continue
		for gb in attached_group_ids(b_id):
			var ub := unit(str(gb))
			if ub.is_empty() or not is_alive(ub):
				continue
			if re.check_units_in_engagement_range(ua, ub, state()):
				return true
	return false

## "Below its starting strength": the (Attached) unit has lost a model.
static func is_below_starting_strength(unit_id: String) -> bool:
	for gid in attached_group_ids(unit_id):
		for m in unit(str(gid)).get("models", []):
			if not m.get("alive", true):
				return true
	return false

static func is_battle_shocked(u: Dictionary) -> bool:
	return bool(u.get("flags", {}).get("battle_shocked", false))

static func is_attached_character(unit_id: String) -> bool:
	var re = rules()
	if re and re.has_method("is_attached_character"):
		return bool(re.is_attached_character(unit_id, state()))
	return false

## The (Attached) units `player` has on the battlefield, one id per unit
## (the bodyguard / head id), in board order.
static func friendly_heads(player: int) -> Array:
	var out: Array = []
	var units: Dictionary = state().get("units", {})
	for uid in units:
		var head := head_id(str(uid))
		if head in out:
			continue
		var hu := unit(head)
		if int(hu.get("owner", 0)) != player or not is_on_battlefield(hu):
			continue
		out.append(head)
	return out

## Enemy (Attached) units of `player` on the battlefield, one id per unit.
static func enemy_heads(player: int) -> Array:
	var out: Array = []
	var units: Dictionary = state().get("units", {})
	for uid in units:
		var head := head_id(str(uid))
		if head in out:
			continue
		var hu := unit(head)
		if int(hu.get("owner", 0)) == player or int(hu.get("owner", 0)) == 0 or not is_on_battlefield(hu):
			continue
		out.append(head)
	return out

## "Guard + Blade Champion" for an Attached unit, else the unit name.
static func group_label(unit_id: String) -> String:
	var head := head_id(unit_id)
	var label := unit_name(head)
	var chars: Array = unit(head).get("attachment_data", {}).get("attached_characters", [])
	if not chars.is_empty():
		var names: Array = [label]
		for cid in chars:
			names.append(unit_name(str(cid)))
		label = " + ".join(names)
	return label

## Standard target entry shape for StratagemManager.get_window_offers.
static func target_entry(unit_id: String, extra: Dictionary = {}) -> Dictionary:
	var entry := {"unit_id": unit_id, "label": group_label(unit_id) if unit_id != "" else "Use"}
	entry.merge(extra, true)
	return entry

## Dice through the engine's seedable RNG (scenario / test seeds apply).
static func roll_dice(count: int, sides: int = 6) -> Array:
	var out: Array = []
	var re = rules()
	var rng = re.make_rng() if re and re.has_method("make_rng") else null
	for _i in range(count):
		var r := 0
		if rng == null:
			r = randi_range(1, sides)
		elif sides == 6:
			r = int(rng.roll_d6(1)[0])
		else:
			# D3 = ceil(D6 / 2) — the same convention as roll_variable_characteristic.
			r = int(ceil(float(rng.roll_d6(1)[0]) * float(sides) / 6.0))
		out.append(r)
	return out

# --- objectives (secured objectives 14.03, objective range 14.01) ----------

static func mission_manager() -> Node:
	return autoload("MissionManager")

static func objectives() -> Array:
	return state().get("board", {}).get("objectives", [])

static func objective_by_id(obj_id: String) -> Dictionary:
	for obj in objectives():
		if str(obj.get("id", "")) == obj_id:
			return obj
	return {}

## Any model of the (Attached) unit within range of the objective. Models that
## were destroyed count when include_dead (VICTORY BEFORE DEATH reads where the
## unit stood when it was destroyed).
static func group_in_objective_range(unit_id: String, obj: Dictionary, include_dead: bool = false) -> bool:
	var mm = mission_manager()
	if mm == null or not mm.has_method("model_in_objective_range"):
		return false
	for gid in attached_group_ids(unit_id):
		for m in unit(str(gid)).get("models", []):
			if m.get("position", null) == null:
				continue
			if not include_dead and not m.get("alive", true):
				continue
			var probe: Dictionary = m
			if not m.get("alive", true):
				probe = m.duplicate()
				probe["alive"] = true
			if mm.model_in_objective_range(probe, obj):
				return true
	return false

static func group_in_range_of_any_objective(unit_id: String) -> bool:
	for obj in objectives():
		if group_in_objective_range(unit_id, obj):
			return true
	return false

static func objective_controller(obj_id: String) -> int:
	var mm = mission_manager()
	if mm == null:
		return 0
	return int(mm.objective_control_state.get(obj_id, 0))

static func objective_secured_by(obj_id: String) -> int:
	var mm = mission_manager()
	if mm == null or not mm.has_method("is_objective_secured"):
		return 0
	var sec: Dictionary = mm.is_objective_secured(obj_id)
	return int(sec.get("player", 0)) if bool(sec.get("secured", false)) else 0

## Player-facing objective name — the board marker's / HUD panel's name
## ("CENTER [NML]") plus where it is.
static func objective_label(obj_id: String) -> String:
	var obj := objective_by_id(obj_id)
	var label := obj_id.replace("obj_", "").to_upper().replace("_", " ")
	match str(obj.get("zone", "")):
		"player1": label += " [P1]"
		"player2": label += " [P2]"
		"no_mans_land": label += " [NML]"
	var p = obj.get("position", null)
	if p is Dictionary:
		label += " at %d\", %d\"" % [roundi(float(p.get("x", 0)) / PX_PER_INCH), roundi(float(p.get("y", 0)) / PX_PER_INCH)]
	elif p is Vector2:
		label += " at %d\", %d\"" % [roundi(p.x / PX_PER_INCH), roundi(p.y / PX_PER_INCH)]
	return label

# ---------------------------------------------------------------------------
# Flag helpers — scoped writes as diffs (replay / network safe)
# ---------------------------------------------------------------------------

static func set_flag_diffs(unit_ids: Array, flag: String, value) -> Array:
	var diffs: Array = []
	for uid in unit_ids:
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [str(uid), flag], "value": value})
	return diffs

## Remove diffs for every unit in `unit_ids` that currently carries `flag`.
static func remove_flag_diffs(unit_ids: Array, flag: String) -> Array:
	var diffs: Array = []
	var units: Dictionary = state().get("units", {})
	for uid in unit_ids:
		if units.get(str(uid), {}).get("flags", {}).has(flag):
			diffs.append({"op": "remove", "path": "units.%s.flags.%s" % [str(uid), flag]})
	return diffs

## In-place flag removal (StratagemManager._clear_stratagem_flags convention:
## an expiry mutates GameState directly). WP-C5.
static func erase_flags(unit_ids: Array, flag_names: Array) -> void:
	var units: Dictionary = state().get("units", {})
	for uid in unit_ids:
		var u = units.get(str(uid), {})
		if u.is_empty() or not u.has("flags"):
			continue
		for f in flag_names:
			u.flags.erase(str(f))

## Apply diffs through PhaseManager (network / replay pipeline) when it is
## loaded, otherwise straight into GameState (bare headless tests).
static func apply_diffs(diffs: Array) -> void:
	if diffs.is_empty():
		return
	var pm = phase_manager()
	if pm and pm.has_method("apply_state_changes"):
		pm.apply_state_changes(diffs)
		return
	var gs = game_state()
	if gs and gs.has_method("apply_state_changes"):
		gs.apply_state_changes(diffs)


# ===========================================================================
# Space Wolves (Codex: Space Marines 11e) specifics
# ===========================================================================

const DOCTRINES := ["assault", "devastator", "tactical"]
const DOCTRINE_LABELS := {
	"assault": "Assault Doctrine",
	"devastator": "Devastator Doctrine",
	"tactical": "Tactical Doctrine",
}

## True when `player`'s army follows Codex: Space Marines as a Space Wolves
## army (11e, faction "Space Wolves" or any SPACE WOLVES unit). Every Space
## Wolves codex rule gates on this; other Space Marine armies keep their
## current (index) rules until their chapter is imported.
static func is_sw_army(player: int) -> bool:
	if int(_game_constants_edition()) < 11:
		return false
	var fac = state().get("factions", {}).get(str(player), {})
	if fac is Dictionary and norm_name(str(fac.get("name", ""))) == "space wolves":
		return true
	for uid in state().get("units", {}):
		var u: Dictionary = state()["units"][uid]
		if int(u.get("owner", 0)) == player and has_keyword(u, "SPACE WOLVES"):
			return true
	return false

static func _game_constants_edition() -> int:
	return int(GameConstants.edition)

## Units "with this ability" (Combat Doctrines): every Codex: Space Marines
## datasheet of a Space Wolves army carries it (the army converter lists the
## chapter's army rule on every unit).
static func has_combat_doctrines(u: Dictionary) -> bool:
	return has_ability(u, "Combat Doctrines") and is_sm_army(int(u.get("owner", 0)))

# ---------------------------------------------------------------------------
# Combat Doctrines state (owned by WP-S2, SWArmyRules11e.gd; read by all)
# ---------------------------------------------------------------------------
#
# Army-wide selection (start of your Command phase):
#   state.factions[p].sw11e_doctrine        = "assault" | "devastator" | "tactical" | ""
#     active for friendly units with Combat Doctrines until the start of p's
#     next Command phase.
#   state.factions[p].sw11e_doctrines_used  = {doctrine: times selected}
# Per-unit (a rule "makes a doctrine active for a unit" — Grimnar's Command,
# Adaptive Strategy; replaces the army doctrine for that unit, 11e "only one
# combat doctrine can be active for each unit"):
#   unit.flags.sw11e_doctrine               = doctrine name
#   unit.flags.sw11e_doctrine_expires_player = p (cleared at the start of p's
#     next Command phase)
# Per-unit ADDITIONAL doctrines ("in addition to any other combat doctrine":
# Logan Grimnar's Guile of the Wolf, "at the start of each phase … are
# active") — written by the module that owns the rule, with its own expiry:
#   unit.flags.sw11e_doctrine_extra         = [doctrine, ...]

## The doctrines active for this unit right now (empty when none).
static func active_doctrines(u: Dictionary) -> Array:
	var out: Array = []
	if u.is_empty() or not has_combat_doctrines(u):
		return out
	var flags: Dictionary = u.get("flags", {})
	var own := str(flags.get("sw11e_doctrine", ""))
	if own != "":
		out.append(own)
	else:
		var fac = state().get("factions", {}).get(str(int(u.get("owner", 0))), {})
		var army := str(fac.get("sw11e_doctrine", "")) if fac is Dictionary else ""
		if army != "":
			out.append(army)
	for d in flags.get("sw11e_doctrine_extra", []):
		if str(d) not in out:
			out.append(str(d))
	return out

## Is `doctrine` ("assault" / "devastator" / "tactical") active for the unit?
static func doctrine_active(u: Dictionary, doctrine: String) -> bool:
	return doctrine.to_lower() in active_doctrines(u)

static func doctrine_active_id(unit_id: String, doctrine: String) -> bool:
	return doctrine_active(unit(unit_id), doctrine)


# ===========================================================================
# WP-S3 (stratagems, SWCodex11e.gd + group scripts) helpers
# ===========================================================================

## True when any component of the (Attached) unit has any of the keywords.
static func group_has_any_keyword(unit_id: String, keywords: Array) -> bool:
	for kw in keywords:
		if group_has_keyword(unit_id, str(kw)):
			return true
	return false

## True when any component of the (Attached) unit is a MONSTER or VEHICLE.
static func group_is_monster_or_vehicle(unit_id: String) -> bool:
	return group_has_any_keyword(unit_id, ["MONSTER", "VEHICLE"])

## Melee / ranged weapons on any component of the (Attached) unit.
static func group_has_melee_weapons(unit_id: String) -> bool:
	var re = rules()
	if re == null or not re.has_method("get_unit_melee_weapons"):
		return false
	for gid in attached_group_ids(unit_id):
		if not re.get_unit_melee_weapons(str(gid), state()).is_empty():
			return true
	return false

static func group_has_ranged_weapons(unit_id: String) -> bool:
	var re = rules()
	if re == null or not re.has_method("get_unit_weapons"):
		return false
	for gid in attached_group_ids(unit_id):
		var w: Dictionary = re.get_unit_weapons(str(gid), state())
		for mid in w:
			for wid in w[mid]:
				if not str(wid).ends_with("_melee"):
					return true
	return false

## Points of every component of the (Attached) unit.
static func group_points(unit_id: String) -> int:
	var pts := 0
	for gid in attached_group_ids(unit_id):
		pts += int(unit(str(gid)).get("meta", {}).get("points", 0))
	return pts

## Closest distance (inches) from any alive model's base of the (Attached)
## unit to any battlefield edge ("within": any part of a base, 01.04.01).
static func group_edge_distance_inches(unit_id: String) -> float:
	var size = state().get("board", {}).get("size", {})
	var w_in := float(size.get("width", 44.0))
	var h_in := float(size.get("height", 60.0))
	var meas = autoload("Measurement")
	var best := INF
	for gid in attached_group_ids(unit_id):
		for m in unit(str(gid)).get("models", []):
			if not m.get("alive", true) or m.get("position", null) == null:
				continue
			var p := _pos(m) / PX_PER_INCH
			var r := float(m.get("base_mm", 32)) / 25.4 / 2.0
			if meas and meas.has_method("base_extent_px"):
				r = float(meas.base_extent_px(m)) / PX_PER_INCH
			var d := minf(minf(p.x - r, w_in - p.x - r), minf(p.y - r, h_in - p.y - r))
			best = minf(best, maxf(d, 0.0))
	return best

## True when `unit_id` (or another component of its Attached unit) is in ids.
static func group_in(unit_id: String, ids) -> bool:
	if typeof(ids) != TYPE_ARRAY:
		return false
	for gid in attached_group_ids(unit_id):
		if gid in ids:
			return true
	return false

# ===========================================================================
# Codex: Space Marines (11e) — every Space Marine army (WP-M1)
# ===========================================================================

const SM_ARMY_NAMES := ["space marines", "adeptus astartes", "black templars", "blood angels",
	"crimson fists", "dark angels", "deathwatch", "imperial fists", "iron hands", "raven guard",
	"salamanders", "space wolves", "ultramarines", "white scars"]

## True when `player`'s army follows Codex: Space Marines (11e): its faction
## is Space Marines / Adeptus Astartes or a Space Marine chapter, or (an army
## file without a faction block) its units are ADEPTUS ASTARTES. The generic
## Codex: Space Marines rules (Combat Doctrines, Transhuman Strategist,
## Librarius, the generic detachments, datasheet abilities) gate on this;
## the Space Wolves specifics keep gating on is_sw_army.
static func is_sm_army(player: int) -> bool:
	if int(_game_constants_edition()) < 11:
		return false
	var fac = state().get("factions", {}).get(str(player), {})
	var fname := norm_name(str(fac.get("name", ""))) if fac is Dictionary else ""
	if fname in SM_ARMY_NAMES:
		return true
	if fname != "":
		return false
	for uid in state().get("units", {}):
		var u: Dictionary = state()["units"][uid]
		if int(u.get("owner", 0)) == player and has_keyword(u, "ADEPTUS ASTARTES"):
			return true
	return false
