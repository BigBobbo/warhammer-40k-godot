extends SceneTree

# ISS-004: uniform per-action RNG seeding.
#
# All dice RNG must come from RulesEngine.rng_for_action(action) (action
# handlers: honors payload.rng_seed, otherwise generates AND RECORDS one) or
# RulesEngine.make_rng() (non-action contexts). Bare RNGService.new() outside
# RulesEngine.gd is a lint failure.
#
# Checks:
#   A) Lint: no bare RNGService.new() outside autoloads/RulesEngine.gd.
#   B) rng_for_action records its seed into the action payload; the same
#      recorded action reproduces the identical roll sequence; explicit
#      payload seeds are honored; test_mode_seed path keeps legacy behavior.
#   C) End-to-end: resolve_shoot driven twice with the seed recorded by
#      rng_for_action on the first run produces identical dice + diffs —
#      i.e. a logged action replays exactly.
#
# Usage: godot --headless --path . -s tests/test_iss004_rng_seeding.gd

var passed := 0
var failed := 0

const SCAN_DIRS = ["res://phases", "res://scripts", "res://autoloads", "res://dialogs"]

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])

func _init():
	root.connect("ready", Callable(self, "_run_tests"))
	create_timer(0.1).timeout.connect(_run_tests)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss004_rng_seeding ===\n")
	_test_lint()
	_test_factory()
	_test_action_replay()
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

# -- A ------------------------------------------------------------------------

func _test_lint() -> void:
	print("\n-- A: no bare RNGService.new() outside RulesEngine.gd --")
	var rx = RegEx.new()
	var err = rx.compile("RNGService\\.new\\(\\)")
	_check("lint regex compiles", err == OK)
	var offenders = []
	for dir_path in SCAN_DIRS:
		_scan_dir(dir_path, rx, offenders)
	_check("no unseeded RNG constructions outside the factories",
		offenders.is_empty(), ", ".join(offenders))

func _scan_dir(dir_path: String, rx: RegEx, offenders: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		var full = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, rx, offenders)
		elif entry.ends_with(".gd") and entry != "RulesEngine.gd":
			var f = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var line_no = 0
				while not f.eof_reached():
					var line = f.get_line()
					line_no += 1
					if line.strip_edges().begins_with("#"):
						continue
					if rx.search(line) != null:
						offenders.append("%s:%d" % [full, line_no])
				f.close()
		entry = dir.get_next()
	dir.list_dir_end()

# -- B ------------------------------------------------------------------------

func _test_factory() -> void:
	print("\n-- B: rng_for_action seed recording + determinism --")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		return
	rules.set_test_seed(-1)  # ensure live-mode behavior

	# Generates and records a seed
	var action = {"type": "X", "payload": {}}
	var rng1 = rules.rng_for_action(action)
	var recorded = action["payload"].get("rng_seed", -1)
	_check("seed recorded into action.payload.rng_seed", recorded >= 0, str(action))
	var rolls1 = rng1.roll_d6(10)

	# Re-running the SAME recorded action reproduces the rolls
	var rng2 = rules.rng_for_action(action)
	_check("recorded action reproduces identical rolls", rng2.roll_d6(10) == rolls1)
	_check("seed unchanged on replay", action["payload"]["rng_seed"] == recorded)

	# Explicit payload seed honored, not overwritten
	var action2 = {"type": "X", "payload": {"rng_seed": 12345}}
	var rng3 = rules.rng_for_action(action2)
	var rng4 = rules.RNGService.new(12345)
	_check("explicit payload seed honored", rng3.roll_d6(10) == rng4.roll_d6(10))
	_check("explicit seed not overwritten", action2["payload"]["rng_seed"] == 12345)

	# Missing payload dict is created
	var action3 = {"type": "X"}
	rules.rng_for_action(action3)
	_check("payload dict created when missing",
		action3.get("payload", {}).get("rng_seed", -1) >= 0)

	# test_mode_seed path: deterministic legacy counter behavior preserved
	rules.set_test_seed(777)
	var a = {"type": "X", "payload": {}}
	var t1 = rules.rng_for_action(a).roll_d6(5)
	_check("test mode does not record a seed", not a["payload"].has("rng_seed"))
	rules.set_test_seed(777)
	var t2 = rules.rng_for_action({"type": "X", "payload": {}}).roll_d6(5)
	_check("test mode stays deterministic", t1 == t2)
	var m1 = rules.make_rng().roll_d6(5)
	rules.set_test_seed(777)
	rules.rng_for_action({"type": "X", "payload": {}})  # consume counter slot 1
	var m2 = rules.make_rng().roll_d6(5)
	_check("make_rng follows test counter sequence", m1 == m2)
	rules.set_test_seed(-1)

# -- C ------------------------------------------------------------------------

func _test_action_replay() -> void:
	print("\n-- C: logged action replays with identical dice + diffs --")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload reachable", false)
		return
	rules.set_test_seed(-1)

	var board = _make_board()
	var action = {
		"type": "SHOOT", "actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": "Replay Gun", "target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1"], "attacks_override": 4
		}]}
	}
	# First (live) run: handler obtains RNG via rng_for_action, which records
	# the seed into the action — this is what the action log would store.
	var rng_live = rules.rng_for_action(action)
	var res_live = rules.resolve_shoot(action, board, rng_live)
	_check("live run succeeded", res_live.get("success", false))
	_check("action now carries the seed used",
		action["payload"].get("rng_seed", -1) >= 0)

	# Replay: fresh board, same logged action.
	var board2 = _make_board()
	var rng_replay = rules.rng_for_action(action)
	var res_replay = rules.resolve_shoot(action, board2, rng_replay)
	_check("replay run succeeded", res_replay.get("success", false))
	_check("identical dice", JSON.stringify(res_live.get("dice", [])) == JSON.stringify(res_replay.get("dice", [])))
	_check("identical diffs", JSON.stringify(res_live.get("diffs", [])) == JSON.stringify(res_replay.get("diffs", [])))

func _make_board() -> Dictionary:
	var shooter_models = []
	for i in range(2):
		shooter_models.append({
			"id": "ms%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(5):
		target_models.append({
			"id": "mt%d" % i, "position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	return {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1},
					"weapons": [{
						"name": "Replay Gun", "type": "Ranged", "range": "24",
						"attacks": "2", "ballistic_skill": "3", "strength": "4",
						"ap": "0", "damage": "1",
						"special_rules": "sustained hits 1"
					}]},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
