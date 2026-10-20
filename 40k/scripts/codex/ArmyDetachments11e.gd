extends RefCounted
## 11e multi-detachment armies (core rules 25.03 / 25.04).
##
## An army may select several detachments while their Detachment Points fit
## the battle-size pool (Incursion 2 DP, Strike Force 3 DP; at Incursion a
## 3 DP detachment may be the ONLY detachment). Every selected detachment is
## active: its rule, enhancements, stratagems and keyword grants all apply.
## Two detachments sharing a tag ("Unique: Shield Host") cannot be combined,
## and the army picks ONE Force Disposition from those its detachments give.
##
## Army JSON (army builder export): faction.detachment = the primary (first
## selected), faction.detachments = every name (primary first), top-level
## detachments = [{name, dp_cost}]. Older single-detachment armies carry only
## faction.detachment — every helper here falls back to it.
##
## The JS twin is server/public/js/lib/detachment-rules.mjs. Pure static
## module; reads GameState through the scene tree only when no board is given.

const Rules := preload("res://scripts/codex/EnhancementRules11e.gd")


## Normalised detachment key (lower case, curly quotes / NBSP folded) — the
## same key CustodesDetachments / OrkDetachments11e compare against.
static func det_key(name: String) -> String:
	return name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()


## Every detachment name in an army JSON / faction block, primary first, deduped.
static func names_from_army(army_data: Dictionary) -> Array:
	var raw: Array = []
	var faction = army_data.get("faction", {})
	if faction is Dictionary:
		raw.append_array(names_from_faction(faction))
	var top = army_data.get("detachments", [])
	if top is Array:
		for d in top:
			raw.append(d.get("name", "") if d is Dictionary else d)
	return _dedupe(raw)


## Detachment names of a faction block (GameState.state.factions[p]).
## detachments[0] is the primary's slot: when faction.detachment no longer
## matches it (the primary was swapped after load), the swapped-in primary
## replaces it rather than both being active.
static func names_from_faction(faction: Dictionary) -> Array:
	var primary := str(faction.get("detachment", "")).strip_edges()
	var raw: Array = [primary]
	var fd = faction.get("detachments", [])
	if fd is Array and not fd.is_empty():
		var rest: Array = fd.duplicate()
		if primary != "" and det_key(str(rest[0])) != det_key(primary):
			rest.remove_at(0)
		raw.append_array(rest)
	return _dedupe(raw)


static func _dedupe(raw: Array) -> Array:
	var out: Array = []
	var seen := {}
	for n in raw:
		var nm := str(n).strip_edges()
		if nm == "" or seen.has(det_key(nm)):
			continue
		seen[det_key(nm)] = true
		out.append(nm)
	return out


static func _state() -> Dictionary:
	var tree = Engine.get_main_loop()
	if tree is SceneTree and tree.root.has_node("GameState"):
		return tree.root.get_node("GameState").state
	return {}


## The faction block of `player` (board's, else the live GameState's).
static func faction_of(player: int, board: Dictionary = {}) -> Dictionary:
	var factions = board.get("factions", {}) if board.has("factions") else {}
	if not (factions is Dictionary) or not factions.has(str(player)):
		factions = _state().get("factions", {})
	var f = factions.get(str(player), {}) if factions is Dictionary else {}
	return f if f is Dictionary else {}


## Every detachment `player` took (display names, primary first).
static func player_detachments(player: int, board: Dictionary = {}) -> Array:
	if player <= 0:
		return []
	return names_from_faction(faction_of(player, board))


## Normalised keys of every detachment `player` took.
static func player_detachment_keys(player: int, board: Dictionary = {}) -> Array:
	var out: Array = []
	for n in player_detachments(player, board):
		out.append(det_key(str(n)))
	return out


## Did `player` take the detachment `det_name` (any of them, not just the primary)?
static func player_has(player: int, det_name: String, board: Dictionary = {}) -> bool:
	return det_key(det_name) in player_detachment_keys(player, board)


# ---------------------------------------------------------------------------
# Army construction (DP pool, tags, Force Disposition)
# ---------------------------------------------------------------------------

static func dp_pool(points_limit: int) -> int:
	return 2 if points_limit <= 1000 else 3


## Dataset records of the army's detachments ({} entries dropped).
static func records(names: Array) -> Array:
	var out: Array = []
	for n in names:
		var rec: Dictionary = Rules.find_detachment(str(n))
		if not rec.is_empty():
			out.append(rec)
	return out


## DP cost of one detachment: the army's declared dp_cost, else the dataset's.
static func _dp_costs(army_data: Dictionary, names: Array) -> Array:
	var declared := {}
	var top = army_data.get("detachments", [])
	if top is Array:
		for d in top:
			if d is Dictionary and d.has("dp_cost"):
				declared[det_key(str(d.get("name", "")))] = int(d.get("dp_cost", 1))
	var out: Array = []
	for n in names:
		var k := det_key(str(n))
		if declared.has(k):
			out.append(declared[k])
		else:
			var rec: Dictionary = Rules.find_detachment(str(n))
			out.append(int(rec.get("detachment_points", 1)) if not rec.is_empty() else 1)
	return out


## Every detachment-selection rule the army breaks ([] when legal).
static func construction_problems(army_data: Dictionary) -> Array:
	var out: Array = []
	var names := names_from_army(army_data)
	if names.is_empty():
		return out
	var faction = army_data.get("faction", {})
	var points_limit := int(faction.get("points", 2000)) if faction is Dictionary else 2000
	var pool := dp_pool(points_limit)
	var used := 0
	for c in _dp_costs(army_data, names):
		used += int(c)
	# Core rules: "If you are playing an Incursion battle, you can select a
	# 3DP detachment as your only detachment."
	var lone_ok := names.size() == 1 and used <= 3
	if used > pool and not lone_ok:
		out.append("detachments cost %d DP, pool is %d at %d pts" % [used, pool, points_limit])
	var recs := records(names)
	for i in range(recs.size()):
		for t in recs[i].get("tags", []):
			for j in range(i):
				if t in recs[j].get("tags", []):
					out.append("%s and %s share the Unique: %s tag" % [recs[j].get("name", ""), recs[i].get("name", ""), str(t).replace("-", " ").capitalize()])
	return out


## Force Disposition ids (game form: "take_and_hold") the army's detachments
## give, primary first. [] when no detachment resolves (any disposition).
static func allowed_dispositions(army_data: Dictionary) -> Array:
	return allowed_dispositions_for(names_from_army(army_data))


static func allowed_dispositions_for(names: Array) -> Array:
	var out: Array = []
	for rec in records(names):
		for fd in rec.get("force_dispositions", []):
			var id := str(fd).replace("-", "_")
			if not id in out:
				out.append(id)
	return out


## The army's own Force Disposition pick (army builder export), game form.
static func declared_disposition(army_data: Dictionary) -> String:
	var faction = army_data.get("faction", {})
	if not faction is Dictionary:
		return ""
	return str(faction.get("force_disposition", "")).replace("-", "_")


## Grey out, in a Force Disposition OptionButton whose items follow
## `dispositions` (PrimaryMissionData11e.DISPOSITIONS), every disposition the
## army's detachments do not give. Returns the disposition id the dropdown
## should switch to ("" = keep the current one): the army's own pick when the
## seat's army just changed, else a legal one when the current is not.
static func restrict_disposition_dropdown(dropdown: OptionButton, army_data: Dictionary, dispositions: Array, army_changed: bool) -> String:
	if dropdown == null:
		return ""
	var allowed := allowed_dispositions(army_data)
	var declared := declared_disposition(army_data)
	for i in range(mini(dropdown.item_count, dispositions.size())):
		dropdown.set_item_disabled(i, not allowed.is_empty() and not str(dispositions[i]) in allowed)
	var current := ""
	if dropdown.selected >= 0 and dropdown.selected < dispositions.size():
		current = str(dispositions[dropdown.selected])
	var target := current
	if army_changed and declared != "" and (allowed.is_empty() or declared in allowed):
		target = declared
	elif not allowed.is_empty() and not current in allowed:
		target = declared if declared in allowed else str(allowed[0])
	return "" if target == current else target
