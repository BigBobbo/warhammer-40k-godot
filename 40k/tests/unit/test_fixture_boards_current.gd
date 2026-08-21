extends SceneTree

# PM-F3 — the benchmark fixtures must carry the board a menu game would play.
#
# The 2000-point fixtures are built on a shell save whose board was captured
# whenever the shell was made. The zone JSONs have been regenerated since
# (crucible_of_battle went from a stepped band to a triangle), and
# SaveLoadManager restores the baked board verbatim — so every benchmark game
# on the stale fixtures played geometry no menu game can produce, and the
# PM-10 A/B was measured on it. make_2000pt_fixture.gd now refreshes the
# board from DeploymentZoneData + MissionManager at build time; this test is
# the rot-guard: it applies THAT SAME refresh to each shipped fixture and
# asserts nothing changes. If a zone JSON is regenerated again, this fails
# loudly until the fixtures are rebuilt.
#
# Also asserts every deployed model sits wholly inside its own zone polygon,
# which is what the refreshed packer guarantees at build time.
#
# `staleboard_orks_2000_predeploy` is EXEMPT by design: it is the deliberately
# preserved pre-refresh board, kept because it is the only known reproduction
# of the PM-F6 deployment stall (see .llm/plan-maker-todo.md PM-F6 evidence).
#
# Run with: godot --headless --path . -s tests/unit/test_fixture_boards_current.gd

const FIXTURES := [
	"mirror_custodes_2000_predeploy",
	"mirror_orks_2000_predeploy",
	"mirror_custodes_2000_postdeploy",
	"mirror_orks_2000_postdeploy",
	"asym_2000_predeploy",
	"asym_2000_postdeploy",
]

const PX_PER_INCH := 40.0

var _pass_count: int = 0
var _fail_count: int = 0

func _init():
	create_timer(0.5).timeout.connect(_run)

func _run():
	print("\n=== Fixture boards are current (PM-F3) Tests ===\n")
	_run_tests()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	print("ALL TESTS PASSED" if _fail_count == 0 else "SOME TESTS FAILED")
	quit(1 if _fail_count > 0 else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: %s" % message)
	else:
		_fail_count += 1
		print("FAIL: %s" % message)

func _run_tests() -> void:
	var slm = root.get_node_or_null("SaveLoadManager")
	var gs = root.get_node_or_null("GameState")
	var mm = root.get_node_or_null("MissionManager")
	var DZD = load("res://scripts/data/DeploymentZoneData.gd")
	if slm == null or gs == null or mm == null or DZD == null:
		_assert(false, "SaveLoadManager / GameState / MissionManager / DeploymentZoneData available")
		return

	# The fixtures live in tests/saves; SaveLoadManager reads user://saves and
	# legacy-copies res://saves at startup. Mirror the pretrigger runner's copy
	# so this test is self-sufficient from a fresh checkout.
	var user_dir := DirAccess.open("user://")
	if user_dir != null and not user_dir.dir_exists("saves"):
		user_dir.make_dir("saves")
	for f in FIXTURES:
		for ext in [".w40ksave", ".meta"]:
			var src := "res://tests/saves/%s%s" % [f, ext]
			var dst := "user://saves/%s%s" % [f, ext]
			if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
				DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))

	for fixture in FIXTURES:
		_check_fixture(fixture, slm, gs, mm, DZD)

func _check_fixture(fixture: String, slm, gs, mm, DZD) -> void:
	if not slm.load_game(fixture):
		_assert(false, "%s loads" % fixture)
		return
	var dep_type := str(gs.state.meta.get("deployment_type", ""))
	_assert(not dep_type.is_empty(), "%s carries a deployment_type (%s)" % [fixture, dep_type])

	# The builder's own refresh, applied to the loaded fixture. A current
	# fixture is a fixed point of it.
	var zones_before := JSON.stringify(gs.state.board.get("deployment_zones", []))
	var objs_before := _normalised_objectives(gs.state.board.get("objectives", []))
	gs.state.board["deployment_zones"] = DZD.get_zones(dep_type)
	mm._setup_objectives_for_deployment(dep_type)
	var zones_after := JSON.stringify(gs.state.board.get("deployment_zones", []))
	var objs_after := _normalised_objectives(gs.state.board.get("objectives", []))
	_assert(zones_before == zones_after,
		"%s: deployment_zones match DeploymentZoneData.get_zones('%s')" % [fixture, dep_type])
	_assert(objs_before == objs_after,
		"%s: objectives match MissionManager's setup for '%s' (%s vs %s)" % [fixture, dep_type, objs_before, objs_after])

	# Every deployed model wholly inside its own zone polygon — what the
	# polygon-aware packer guarantees at build time. Predeploy fixtures have
	# no deployed models and pass vacuously; the count line says which.
	var polys := {}
	for z in gs.state.board.get("deployment_zones", []):
		var poly := PackedVector2Array()
		for p in z.get("poly", []):
			poly.append(Vector2(float(p.x) * PX_PER_INCH, float(p.y) * PX_PER_INCH))
		polys[int(z.player)] = poly
	var checked := 0
	var outside := 0
	for uid in gs.state.units:
		var u = gs.state.units[uid]
		if int(u.get("status", 0)) != 2:  # UnitStatus.DEPLOYED
			continue
		var poly: PackedVector2Array = polys.get(int(u.get("owner", 0)), PackedVector2Array())
		if poly.size() < 3:
			continue
		for m in u.get("models", []):
			var pos = m.get("position")
			if pos == null:
				continue
			var pt := Vector2(float(pos.x), float(pos.y)) if not (pos is Array) else Vector2(float(pos[0]), float(pos[1]))
			var r := float(m.get("base_mm", 32)) / 25.4 * PX_PER_INCH / 2.0
			checked += 1
			if not _wholly_inside(pt, r, poly):
				outside += 1
	_assert(outside == 0,
		"%s: deployed models wholly inside their zone (%d checked, %d outside)" % [fixture, checked, outside])

func _normalised_objectives(objs: Array) -> String:
	"""id@x,y/radius/zone per objective, sorted — VALUE comparison only. A
	freshly-computed objective carries a Vector2 `position` while one restored
	from a save carries whatever StateSerializer round-tripped it to, so a
	stringify comparison fails on TYPE even when every value matches (measured:
	all six rebuilt fixtures failed the naive comparison while agreeing on
	every coordinate)."""
	var parts: Array = []
	for o in objs:
		if not (o is Dictionary):
			continue
		var pos = o.get("position")
		var v := Vector2.ZERO
		if pos is Vector2:
			v = pos
		elif pos is Dictionary:
			v = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
		elif pos is Array and pos.size() >= 2:
			v = Vector2(float(pos[0]), float(pos[1]))
		elif pos is String:
			# StateSerializer may render a Vector2 as "(x, y)".
			var trimmed := str(pos).trim_prefix("(").trim_suffix(")")
			var bits := trimmed.split(",")
			if bits.size() >= 2:
				v = Vector2(float(bits[0]), float(bits[1]))
		parts.append("%s@%.1f,%.1f/%d/%s" % [str(o.get("id", "?")), v.x, v.y,
			int(o.get("radius_mm", 40)), str(o.get("zone", "?"))])
	parts.sort()
	return "|".join(parts)


func _wholly_inside(pt: Vector2, r: float, poly: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(pt, poly):
		return false
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if pt.distance_to(Geometry2D.get_closest_point_to_segment(pt, a, b)) < r:
			return false
	return true
