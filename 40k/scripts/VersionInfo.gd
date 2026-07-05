extends RefCounted
class_name VersionInfo

# VersionInfo - single access point for the game's version + changelog.
#
# The data lives in res://data/version_history.json (newest release first).
# To record a change, prepend a new entry to that file — see CLAUDE.md
# 'Version / changelog'. This helper is intentionally tiny and defensive so a
# malformed/missing file never blocks the main menu from loading.

const VERSION_FILE := "res://data/version_history.json"

# Cached so we only parse the JSON once per run.
static var _cache: Array = []
static var _loaded: bool = false

static func _load_releases() -> Array:
	if _loaded:
		return _cache
	_loaded = true
	_cache = []

	if not FileAccess.file_exists(VERSION_FILE):
		push_warning("VersionInfo: %s not found" % VERSION_FILE)
		return _cache

	var f := FileAccess.open(VERSION_FILE, FileAccess.READ)
	if f == null:
		push_warning("VersionInfo: could not open %s" % VERSION_FILE)
		return _cache

	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("releases"):
		push_warning("VersionInfo: malformed %s (no 'releases' array)" % VERSION_FILE)
		return _cache

	var releases = parsed.get("releases", [])
	if typeof(releases) == TYPE_ARRAY:
		_cache = releases
	return _cache

## Return the newest release entry, or an empty dict if none exist.
static func get_latest_release() -> Dictionary:
	var releases := _load_releases()
	if releases.is_empty():
		return {}
	var first = releases[0]
	return first if typeof(first) == TYPE_DICTIONARY else {}

## Return the current version string (e.g. "0.1.0"), or "unknown" if unavailable.
static func get_version() -> String:
	var latest := get_latest_release()
	return str(latest.get("version", "unknown"))

## Return the date the current version was published (e.g. "2026-07-05"), or "".
static func get_version_date() -> String:
	var latest := get_latest_release()
	return str(latest.get("date", ""))

## Compact one-line badge, e.g. "v0.1.0 · 2026-07-05".
static func get_version_badge() -> String:
	var v := get_version()
	var d := get_version_date()
	if d.is_empty():
		return "v%s" % v
	return "v%s · %s" % [v, d]

## Return the change bullets for the latest release (Array[String]).
static func get_latest_changes() -> Array:
	var latest := get_latest_release()
	var changes = latest.get("changes", [])
	return changes if typeof(changes) == TYPE_ARRAY else []

## Return the one-line summary for the latest release, or "".
static func get_latest_summary() -> String:
	var latest := get_latest_release()
	return str(latest.get("summary", ""))

## All releases, newest first (Array[Dictionary]).
static func get_all_releases() -> Array:
	return _load_releases()
