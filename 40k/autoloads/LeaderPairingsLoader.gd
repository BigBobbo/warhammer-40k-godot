extends Node

# Issue #378: load Wahapedia's canonical Datasheets_leader.csv (1,899 rows of
# leader_id|attached_id) at startup so CharacterAttachmentManager can fall back
# to canonical pairings when the per-roster JSON `meta.leader_data.can_lead`
# list is empty or out of sync. Datasheet IDs are translated to unit names
# (and uppercase keyword forms) using Datasheets.csv.

const DATASHEETS_PATH := "res://data/Datasheets.csv"
const DATASHEETS_LEADER_PATH := "res://data/Datasheets_leader.csv"

# datasheet_id -> name (e.g. "000000022" -> "Nob With Waaagh! Banner")
var _id_to_name: Dictionary = {}
# normalized lowercase name -> datasheet_id
var _name_to_id: Dictionary = {}
# leader_id -> Array[String] of attached datasheet ids
var _leader_to_attached: Dictionary = {}

var _loaded: bool = false

func _ready() -> void:
	_load_csvs()
	print("LeaderPairingsLoader: %d datasheets, %d leaders, %d total pairings" % [
		_id_to_name.size(),
		_leader_to_attached.size(),
		_total_pairings(),
	])

func _total_pairings() -> int:
	var total := 0
	for k in _leader_to_attached:
		total += _leader_to_attached[k].size()
	return total

func _load_csvs() -> void:
	# Datasheets.csv: header line + rows of `id|name|...`
	var ds := FileAccess.open(DATASHEETS_PATH, FileAccess.READ)
	if ds:
		var header_skipped := false
		while not ds.eof_reached():
			var line := ds.get_line()
			if not header_skipped:
				header_skipped = true
				continue
			if line.is_empty():
				continue
			var parts := line.split("|", true)
			if parts.size() < 2:
				continue
			var id := String(parts[0]).strip_edges()
			var name := String(parts[1]).strip_edges()
			if id.is_empty() or name.is_empty():
				continue
			_id_to_name[id] = name
			_name_to_id[name.to_lower()] = id
		ds.close()
	else:
		push_warning("LeaderPairingsLoader: cannot open %s" % DATASHEETS_PATH)
		return

	# Datasheets_leader.csv: header + rows of `leader_id|attached_id|`
	var lf := FileAccess.open(DATASHEETS_LEADER_PATH, FileAccess.READ)
	if lf:
		var header_skipped := false
		while not lf.eof_reached():
			var line := lf.get_line()
			if not header_skipped:
				header_skipped = true
				continue
			if line.is_empty():
				continue
			var parts := line.split("|", true)
			if parts.size() < 2:
				continue
			var leader_id := String(parts[0]).strip_edges()
			var attached_id := String(parts[1]).strip_edges()
			if leader_id.is_empty() or attached_id.is_empty():
				continue
			if not _leader_to_attached.has(leader_id):
				_leader_to_attached[leader_id] = []
			if not attached_id in _leader_to_attached[leader_id]:
				_leader_to_attached[leader_id].append(attached_id)
		lf.close()
		_loaded = true
	else:
		push_warning("LeaderPairingsLoader: cannot open %s" % DATASHEETS_LEADER_PATH)

# Returns the canonical Wahapedia bodyguard datasheet names for the given
# leader unit name, e.g. "Nob With Waaagh! Banner" -> ["Boyz", "Breaka Boyz",
# "Nobz"]. Empty if the leader is not in the CSV.
func get_canonical_attached_names(leader_name: String) -> Array:
	if not _loaded or leader_name == "":
		return []
	var leader_id = _name_to_id.get(leader_name.to_lower(), "")
	if leader_id == "":
		return []
	var attached_ids = _leader_to_attached.get(leader_id, [])
	var names: Array = []
	for aid in attached_ids:
		var n = _id_to_name.get(aid, "")
		if n != "":
			names.append(n)
	return names

# Returns the canonical bodyguard names AS UPPER-CASE keyword strings, matching
# the format used in roster `meta.keywords` (e.g. "Boyz" -> "BOYZ"). Useful as
# a drop-in additional `can_lead` list for CharacterAttachmentManager.
func get_canonical_can_lead_keywords(leader_name: String) -> Array:
	var names = get_canonical_attached_names(leader_name)
	var out: Array = []
	for n in names:
		out.append(String(n).to_upper())
	return out

# Convenience: does the canonical CSV say `leader_name` can lead a bodyguard
# whose name is `bodyguard_name`?
func can_lead_canonical(leader_name: String, bodyguard_name: String) -> bool:
	var names = get_canonical_attached_names(leader_name)
	for n in names:
		if String(n).to_lower() == bodyguard_name.to_lower():
			return true
	return false
