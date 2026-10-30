extends SceneTree

# Command-line front end for PixelDiff (tests/tools/pixel_diff.gd), the T02
# visual-harness image diff. Compares two PNGs and emits the result as ONE
# line of JSON on stdout:
#
#   {"regions":{"<name>":<pct>,...},"total_diff_pct":<pct>}
#
# Usage, from the repo root:
#
#   godot --headless --path 40k -s tests/tools/pixel_diff_cli.gd -- \
#       --before=<png> --after=<png> [--region=<name>:<x>,<y>,<w>,<h> ...]
#
# Paths may be absolute, res://, user://, or relative to the directory the
# command was run from ($PWD; Godot itself would resolve them against 40k/
# because of --path). Regions are pixel rects, clipped to the image.
#
# Godot prints its banner and the autoloads' start-up lines on stdout too, so
# take the JSON as the one line that starts with "{":
#
#   godot ... | grep -m1 '^{' | python3 -m json.tool
#
# Exit codes: 0 the diff ran; 2 bad arguments, or the diff failed (missing
# file, size mismatch) — the JSON line is then {"error": "..."}.
#
# The in-scenario `pixel_diff` step (ScenarioRunner) calls the same
# PixelDiff.diff(), so a number from here matches the scenario's
# diff_report.json. This front end is for diffing captures the scenario never
# saw together, e.g. the same T## frame from two runs or two branches.

const USAGE := "usage: godot --headless --path 40k -s tests/tools/pixel_diff_cli.gd -- --before=<png> --after=<png> [--region=<name>:<x>,<y>,<w>,<h> ...]"


func _init() -> void:
	var before := ""
	var after := ""
	var regions := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before="):
			before = _resolve(arg.trim_prefix("--before="))
		elif arg.begins_with("--after="):
			after = _resolve(arg.trim_prefix("--after="))
		elif arg.begins_with("--region="):
			var spec: String = arg.trim_prefix("--region=")
			var parsed = _parse_region(spec)
			if parsed == null:
				_finish({"error": "bad --region '%s' (want <name>:<x>,<y>,<w>,<h>)" % spec}, 2)
				return
			regions[parsed[0]] = parsed[1]
		else:
			_finish({"error": "unknown argument '%s'; %s" % [arg, USAGE]}, 2)
			return
	if before == "" or after == "":
		_finish({"error": "--before and --after are required; %s" % USAGE}, 2)
		return

	var pd = load("res://tests/tools/pixel_diff.gd")
	if pd == null:
		_finish({"error": "could not load res://tests/tools/pixel_diff.gd"}, 2)
		return
	var result: Dictionary = pd.diff(before, after, regions)
	_finish(result, 2 if result.has("error") else 0)


func _finish(payload: Dictionary, code: int) -> void:
	print(JSON.stringify(payload))
	quit(code)


# res:// and user:// and absolute paths pass through; a relative path is taken
# relative to the caller's directory, not the project directory.
func _resolve(path: String) -> String:
	if path == "" or path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	var caller_dir := OS.get_environment("PWD")
	if caller_dir == "":
		return path
	return caller_dir.path_join(path)


# "<name>:<x>,<y>,<w>,<h>" -> [name, [x, y, w, h]], or null if malformed.
func _parse_region(spec: String):
	var colon := spec.rfind(":")
	if colon <= 0:
		return null
	var name := spec.substr(0, colon)
	var nums := spec.substr(colon + 1).split(",")
	if nums.size() != 4:
		return null
	var rect := []
	for n in nums:
		var s := n.strip_edges()
		if not s.is_valid_int():
			return null
		rect.append(int(s))
	return [name, rect]
