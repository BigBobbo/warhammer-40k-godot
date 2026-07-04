extends SceneTree

# 10.07 (11e) INDIRECT shooting through the REAL resolve path
# (RulesEngine.resolve_shoot_until_wounds — the function ShootingPhase
# calls), not module methods or source pins:
#   1. Unseen target, unit moved: unmodified 1-5 fail (only 6s hit).
#   2. Unseen target, remained stationary + friendly spotter sees the
#      target: 1-3 fail, AND the attack takes the benefit of cover on the
#      HIT side (BS worsened by 1 — 13.08), so BS4 needs 5s.
#   3. Hit re-rolls are suppressed while shooting indirect at an unseen
#      target (10.07 "cannot be re-rolled") — the same effect flag DOES
#      re-roll at 10e.
#   4. 10e sensitivity: -1 to hit + 1-3 fail band (5s hit for BS4) and the
#      save-side cover grant stays 10e-only.
#
# Usage: godot --headless --path . -s tests/test_indirect_fire_band_11e.gd

var passed := 0
var failed := 0

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

func _board(mortar_flags: Dictionary = {}, spotter_pos: Dictionary = {"x": 700, "y": 1400}) -> Dictionary:
	# Mortar (400,400) -> Foe (400,1400): the tall wall strip at y=690-710
	# blocks every line. Spotter (700,1400) sees the Foe along y=1400 (foe far from the wall so TERRAIN grants no cover of its own).
	return {"units": {
		"U_MORTAR": {"id": "U_MORTAR", "owner": 1, "flags": mortar_flags,
			"meta": {"name": "Mortar Team", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 2},
				"weapons": [{"name": "Mortar", "type": "Ranged", "range": "48",
					"attacks": "6", "ballistic_skill": "4", "strength": "4",
					"ap": "0", "damage": "1", "special_rules": "indirect fire"}]},
			"models": [{"id": "m0", "alive": true, "wounds": 2, "current_wounds": 2,
				"base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 400}}]},
		"U_SPOT": {"id": "U_SPOT", "owner": 1, "flags": {},
			"meta": {"name": "Spotter", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 4, "wounds": 1}},
			"models": [{"id": "s0", "alive": true, "wounds": 1, "current_wounds": 1,
				"base_mm": 32, "base_type": "circular", "position": spotter_pos}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 5, "wounds": 1}},
			"models": [
				{"id": "f0", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 400, "y": 1400}},
				{"id": "f1", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 440, "y": 1400}},
				{"id": "f2", "alive": true, "wounds": 1, "current_wounds": 1,
					"base_mm": 32, "base_type": "circular", "position": {"x": 360, "y": 1400}}]},
	},
	"terrain_features": [{"id": "wall", "type": "ruins", "height_category": "tall",
		"polygon": PackedVector2Array([Vector2(200, 690), Vector2(600, 690), Vector2(600, 710), Vector2(200, 710)])}],
	"meta": {}}

func _shoot_action(mods: Dictionary = {}) -> Dictionary:
	var assignment = {"weapon_id": "Mortar", "target_unit_id": "U_FOE", "model_ids": ["m0"]}
	if not mods.is_empty():
		assignment["modifiers"] = mods
	return {"actor_unit_id": "U_MORTAR", "payload": {"assignments": [assignment]}}

func _to_hit(result: Dictionary) -> Dictionary:
	for d in result.get("dice", []):
		if d.get("context", "") == "to_hit":
			return d
	return {}

func _count(rolls: Array, at_least: int) -> int:
	var n := 0
	for r in rolls:
		if int(r) >= at_least:
			n += 1
	return n

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_indirect_fire_band_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	if rules == null:
		_check("RulesEngine autoload", false); _finish(); return
	var prev_edition = GameConstants.edition
	GameConstants.edition = 11

	print("-- geometry sanity --")
	var b = _board()
	_check("wall blocks mortar -> foe", not rules._has_los_to_target_unit("U_MORTAR", "U_FOE", b))
	_check("spotter sees the foe", rules._has_los_to_target_unit("U_SPOT", "U_FOE", b))

	print("\n-- band selection (10.07) --")
	_check("moved: fail band 5 (only 6s hit)",
		rules._indirect_hit_fail_band_11e("U_MORTAR", "U_FOE", b) == 5)
	var b_stat = _board({"remained_stationary": true})
	_check("stationary + spotter: fail band 3",
		rules._indirect_hit_fail_band_11e("U_MORTAR", "U_FOE", b_stat) == 3)
	var b_nospot = _board({"remained_stationary": true}, {"x": 400, "y": 400})
	_check("stationary but NO spotter LoS: fail band 5",
		rules._indirect_hit_fail_band_11e("U_MORTAR", "U_FOE", b_nospot) == 5)

	# Pre-roll the same seed to derive the expected raw dice.
	var seed := 1
	var expected: Array = rules.RNGService.new(seed).roll_d6(6)
	print("\n-- live resolve, moved (band 5): seed %d rolls %s --" % [seed, str(expected)])
	var res = rules.resolve_shoot_until_wounds(_shoot_action(), _board(), rules.RNGService.new(seed))
	var th = _to_hit(res)
	_check("hit rolls consumed first (raw rolls match the seed)",
		th.get("rolls_raw", []) == expected, str(th.get("rolls_raw")))
	_check("only unmodified 6s hit (%d of %s)" % [_count(expected, 6), str(expected)],
		int(th.get("successes", -1)) == _count(expected, 6), str(th))
	_check("no 10e -1 modifier at e11", not th.get("indirect_fire_applied", true))

	print("\n-- live resolve, stationary + spotter (band 3 + cover worsens BS4 -> 5) --")
	res = rules.resolve_shoot_until_wounds(_shoot_action(), _board({"remained_stationary": true}), rules.RNGService.new(seed))
	th = _to_hit(res)
	_check("4s fail to cover-worsened BS; 5s and 6s hit (%d of %s)" % [_count(expected, 5), str(expected)],
		int(th.get("successes", -1)) == _count(expected, 5), str(th))

	print("\n-- 10.07: hit re-rolls suppressed at an unseen target --")
	res = rules.resolve_shoot_until_wounds(_shoot_action(),
		_board({"remained_stationary": true, "effect_reroll_hits": "failed"}), rules.RNGService.new(seed))
	th = _to_hit(res)
	_check("effect_reroll_hits=failed does NOT re-roll (11e indirect unseen)",
		th.get("rerolls", [1]).is_empty() and int(th.get("successes", -1)) == _count(expected, 5), str(th))

	print("\n-- 10e sensitivity --")
	GameConstants.edition = 10
	res = rules.resolve_shoot_until_wounds(_shoot_action(), _board(), rules.RNGService.new(seed))
	th = _to_hit(res)
	_check("10e: -1 to hit applied", th.get("indirect_fire_applied", false))
	_check("10e: band 3 + minus-one => 5s hit (%d of %s)" % [_count(expected, 5), str(expected)],
		int(th.get("successes", -1)) == _count(expected, 5), str(th))
	_check("10e band (5s hit) differs from 11e moved band (6s only) for this stream",
		_count(expected, 5) != _count(expected, 6),
		"seed %d stream has no 5s — pick another seed" % seed)
	res = rules.resolve_shoot_until_wounds(_shoot_action(),
		_board({"effect_reroll_hits": "failed"}), rules.RNGService.new(seed))
	th = _to_hit(res)
	_check("10e: the same re-roll effect DOES re-roll (control)",
		not th.get("rerolls", []).is_empty(), str(th.get("rerolls")))

	print("\n-- save-side INDIRECT cover grant is 10e-only --")
	# The unconditional save-side grant can't be isolated behaviorally: any
	# unseen-target geometry has intervening terrain, so the 10e terrain
	# check (check_benefit_of_cover) also reports cover — and THAT check's
	# edition-gating is the separate 13.08 latent-risk item (the 11e save
	# overlay rebuilds saves from base). Assert the 10e positive plus the
	# source gate on the two indirect grants.
	var wprofile = rules.get_weapon_profile("Mortar", _board())
	GameConstants.edition = 10
	var prep10 = rules.prepare_save_resolution(2, "U_FOE", "U_MORTAR", wprofile, _board())
	var cover10 = false
	for p in prep10.get("model_save_profiles", []):
		if p.get("has_cover", false):
			cover10 = true
	_check("10e: indirect at an unseen target grants save-side cover", cover10,
		str(prep10.get("model_save_profiles")))
	var src_f = FileAccess.open("res://autoloads/RulesEngine.gd", FileAccess.READ)
	var src = src_f.get_as_text() if src_f != null else ""
	_check("interactive save prep: indirect save-cover grant gated to edition < 11",
		"weapon_is_indirect_fire and GameConstants.edition < 11 and not _has_los_to_target_unit" in src)
	_check("auto-resolve: indirect save-cover grant gated to edition < 11",
		"is_indirect_fire and GameConstants.edition < 11 and not _has_los_to_target_unit" in src)

	GameConstants.edition = prev_edition
	_finish()

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
