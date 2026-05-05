extends SceneTree

# T2-1: STEALTH ability pipeline regression test
#
# Per Warhammer 40,000 10e core rules:
#   "Each time a ranged attack is allocated to a model whose unit has the
#    Stealth ability, subtract 1 from the Hit roll of that attack."
#
# This is the headless analogue to the GUT unit tests in
# tests/unit/test_stealth_ability.gd. Those tests cover the
# has_stealth_ability() helper in isolation; THIS regression test drives the
# full resolve_shoot() / resolve_shoot_until_wounds() / resolve_melee_attacks()
# pipelines so a regression that DROPS the Stealth branch (e.g. a refactor that
# bypasses the hit-modifier section, or fails to OR MINUS_ONE into
# hit_modifiers when the target has Stealth) surfaces here.
#
# Stealth can come from two sources, both of which must apply -1 to hit:
#   1. Base unit ability — meta.abilities contains "Stealth"
#      (RulesEngine.has_stealth_ability)
#   2. Effect-granted — flags.effect_stealth = true (e.g. Smokescreen stratagem,
#      EffectPrimitivesData.has_effect_stealth)
#
# Stealth must NOT apply to melee attacks (10e rule restricts it to ranged).
#
# Coverage:
#   * has_stealth_ability() lookup — string, dict, negative cases
#   * Pipeline ranged (auto-resolve): MINUS_ONE bit set on to_hit dice record
#     when target has Stealth ability
#   * Pipeline ranged (auto-resolve): MINUS_ONE bit set when target has
#     flags.effect_stealth (smokescreen-style effect-granted Stealth)
#   * Pipeline ranged (auto-resolve): MINUS_ONE bit NOT set on a clean target
#   * Pipeline ranged (interactive): MINUS_ONE bit set via
#     resolve_shoot_until_wounds()
#   * Pipeline melee: melee hits are unchanged whether the target has Stealth
#     or not (Stealth must not leak into the fight phase)
#   * Statistical: Stealth target receives strictly fewer hits than a clean
#     target across many seeds (hits drop from 4+ to 5+ for BS3+ shooters)
#
# Usage: godot --headless --path . -s tests/test_stealth_keyword_pipeline.gd

var passed := 0
var failed := 0

const ATTACKS = 80  # Large sample so stealth lift is measurable

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

# ----------------------------------------------------------------------------
# Board factories
# ----------------------------------------------------------------------------
# A 4-shooter / 8-target board placed close enough that bolt_rifle (range=30")
# is comfortably in range. Target unit metadata is parameterised:
#   has_stealth_ability=true   ⇒ meta.abilities contains "Stealth"
#   has_effect_stealth=true    ⇒ flags.effect_stealth = true
#
# Both should drive RulesEngine to set HitModifier.MINUS_ONE.
# ----------------------------------------------------------------------------
func _make_board(has_stealth_ability: bool = false, has_effect_stealth: bool = false) -> Dictionary:
	var px_per_inch = 40.0
	# Place the target ~2" away so we're well inside bolt_rifle (range=30")
	# but outside Rapid Fire half range (15") to avoid +1 attacks confusing
	# the comparison. Actually 2" is INSIDE 15" so rapid fire DOES fire — this
	# doubles attacks but that's fine because BOTH compared boards see the same
	# extra attacks; stealth still subtracts 1 from the same roll set.
	var target_distance_px = 2.0 * px_per_inch
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(8):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": target_distance_px, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	var target_meta = {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}}
	if has_stealth_ability:
		target_meta["abilities"] = ["Stealth"]
	else:
		target_meta["abilities"] = []
	var target_flags = {}
	if has_effect_stealth:
		target_flags["effect_stealth"] = true
	var board = {
		"units": {
			"U_SHOOTER": {
				"id": "U_SHOOTER", "owner": 1,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": target_meta,
				"flags": target_flags,
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
	return board

# ----------------------------------------------------------------------------
# Melee board: shooter 0.5" from target so models are in engagement range (1").
# ----------------------------------------------------------------------------
func _make_melee_board(has_stealth_ability: bool = false) -> Dictionary:
	var px_per_inch = 40.0
	# 0.5" centre-to-centre — both 32mm bases (radius ~0.63") so they're
	# definitely within engagement range (1" edge-to-edge).
	var target_distance_px = 0.5 * px_per_inch
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0.0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(8):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": target_distance_px, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
	var target_meta = {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}}
	if has_stealth_ability:
		target_meta["abilities"] = ["Stealth"]
	else:
		target_meta["abilities"] = []
	var board = {
		"units": {
			"U_ATTACKER": {
				"id": "U_ATTACKER", "owner": 1,
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {"in_engagement_range": true},
				"models": shooter_models
			},
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2,
				"meta": target_meta,
				"flags": {"in_engagement_range": true},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
	return board

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
func _shoot(weapon_id: String, board: Dictionary, seed: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed)
	var rng = rules.RNGService.new()
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": weapon_id,
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"],
			"attacks_override": ATTACKS
		}]}
	}
	return rules.resolve_shoot(action, board, rng)

func _shoot_interactive(weapon_id: String, board: Dictionary, seed: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed)
	var rng = rules.RNGService.new()
	var action := {
		"type": "SHOOT",
		"actor_unit_id": "U_SHOOTER",
		"payload": {"assignments": [{
			"weapon_id": weapon_id,
			"target_unit_id": "U_TARGET",
			"model_ids": ["ms0", "ms1", "ms2", "ms3"],
			"attacks_override": ATTACKS
		}]}
	}
	return rules.resolve_shoot_until_wounds(action, board, rng)

func _melee(weapon_id: String, board: Dictionary, seed: int) -> Dictionary:
	var rules = root.get_node("RulesEngine")
	rules.set_test_seed(seed)
	var rng = rules.RNGService.new()
	# NB: The melee assignment's `models` field expects index-strings ("0",
	# "1", ...) — passing IDs ("ms0", "ms1") filters every model out
	# (eligibility check uses `str(model_index) in attacking_models`).
	# Easiest is to omit `models` entirely so the engine picks all eligible
	# models in engagement range.
	var action := {
		"type": "FIGHT",
		"actor_unit_id": "U_ATTACKER",
		"payload": {"assignments": [{
			"attacker": "U_ATTACKER",
			"target": "U_TARGET",
			"weapon": weapon_id
		}]}
	}
	return rules.resolve_melee_attacks(action, board, rng)

func _aggregate_dice(result: Dictionary, context: String) -> Dictionary:
	"""Find the first dice record with the given context."""
	for d in result.get("dice", []):
		if d.get("context", "") == context:
			return d
	return {}

func _all_dice(result: Dictionary, context: String) -> Array:
	var arr := []
	for d in result.get("dice", []):
		if d.get("context", "") == context:
			arr.append(d)
	return arr

func _collect_contexts(result: Dictionary) -> Array:
	var arr := []
	for d in result.get("dice", []):
		arr.append(d.get("context", ""))
	return arr

# ----------------------------------------------------------------------------
# Run all tests
# ----------------------------------------------------------------------------
func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_stealth_keyword_pipeline ===\n")

	_test_has_stealth_ability_lookup()
	_test_stealth_ability_sets_minus_one_in_pipeline()
	_test_effect_stealth_sets_minus_one_in_pipeline()
	_test_no_stealth_clean_target_has_no_minus_one()
	_test_stealth_in_interactive_resolve_path()
	_test_stealth_does_not_apply_to_melee()
	_test_stealth_statistically_reduces_hits()

	_finish()

# ----------------------------------------------------------------------------
# Sanity: has_stealth_ability() identifies units correctly.
# ----------------------------------------------------------------------------
func _test_has_stealth_ability_lookup() -> void:
	print("\n-- Lookup: has_stealth_ability recognises Stealth in abilities --")
	var rules = root.get_node("RulesEngine")
	# String ability
	_check("String 'Stealth' detected",
		rules.has_stealth_ability({"meta": {"abilities": ["Stealth"]}}))
	# Case-insensitive string
	_check("String 'STEALTH' (uppercase) detected",
		rules.has_stealth_ability({"meta": {"abilities": ["STEALTH"]}}))
	# Dict ability
	_check("Dict {name:'Stealth'} detected",
		rules.has_stealth_ability({"meta": {"abilities": [{"name": "Stealth", "description": "x"}]}}))
	# Negative: empty
	_check("Empty abilities returns false",
		not rules.has_stealth_ability({"meta": {"abilities": []}}))
	# Negative: other ability
	_check("Non-stealth ability returns false",
		not rules.has_stealth_ability({"meta": {"abilities": ["Bolter Discipline"]}}))
	# Negative: substring 'Stealthy Movement' must NOT match 'Stealth'
	_check("'Stealthy Movement' (substring) does NOT match",
		not rules.has_stealth_ability({"meta": {"abilities": ["Stealthy Movement"]}}))

# ----------------------------------------------------------------------------
# T2-1: ability-granted Stealth — to_hit dice record exposes MINUS_ONE bit.
# ----------------------------------------------------------------------------
func _test_stealth_ability_sets_minus_one_in_pipeline() -> void:
	print("\n-- T2-1: ability Stealth applies HitModifier.MINUS_ONE in pipeline --")
	var rules = root.get_node("RulesEngine")
	var board = _make_board(true, false)  # ability stealth, no effect
	var result = _shoot("bolt_rifle", board, 12345)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Stealth (ability): to_hit dice record present",
		not hit_dice.is_empty(),
		"contexts=%s" % str(_collect_contexts(result)))

	var modifiers = int(hit_dice.get("modifiers_applied", 0))
	_check("Stealth (ability): MINUS_ONE bit set in modifiers_applied",
		(modifiers & rules.HitModifier.MINUS_ONE) != 0,
		"got modifiers=%d (MINUS_ONE=%d)" % [modifiers, rules.HitModifier.MINUS_ONE])

# ----------------------------------------------------------------------------
# T2-1: effect-granted Stealth — flags.effect_stealth path also fires.
# ----------------------------------------------------------------------------
func _test_effect_stealth_sets_minus_one_in_pipeline() -> void:
	print("\n-- T2-1: effect_stealth flag (smokescreen-style) applies MINUS_ONE --")
	var rules = root.get_node("RulesEngine")
	var board = _make_board(false, true)  # no ability, but effect_stealth flag
	var result = _shoot("bolt_rifle", board, 12345)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Effect stealth: to_hit dice record present",
		not hit_dice.is_empty())
	var modifiers = int(hit_dice.get("modifiers_applied", 0))
	_check("Effect stealth: MINUS_ONE bit set in modifiers_applied",
		(modifiers & rules.HitModifier.MINUS_ONE) != 0,
		"got modifiers=%d" % modifiers)

# ----------------------------------------------------------------------------
# Negative case: clean target (no Stealth ability, no effect flag) — MINUS_ONE
# bit must NOT be set by the stealth code path.
# ----------------------------------------------------------------------------
func _test_no_stealth_clean_target_has_no_minus_one() -> void:
	print("\n-- T2-1: clean target (no Stealth) does NOT carry MINUS_ONE --")
	var rules = root.get_node("RulesEngine")
	var board = _make_board(false, false)  # no stealth at all
	var result = _shoot("bolt_rifle", board, 12345)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Clean target: to_hit dice record present",
		not hit_dice.is_empty())
	var modifiers = int(hit_dice.get("modifiers_applied", 0))
	# Other modifiers (e.g. heavy bonus, BGNT) shouldn't fire either in this
	# board, so we expect modifiers_applied == HitModifier.NONE (0).
	_check("Clean target: MINUS_ONE bit NOT set",
		(modifiers & rules.HitModifier.MINUS_ONE) == 0,
		"got modifiers=%d (MINUS_ONE bit set unexpectedly)" % modifiers)

# ----------------------------------------------------------------------------
# Stealth must apply via the interactive resolve path too. resolve_shoot()
# auto-resolves saves; resolve_shoot_until_wounds() stops after wound rolls
# for human wound-allocation. Both go through the same hit-modifier section
# (lines 1583/2416) so the bit must be present in either flow.
# ----------------------------------------------------------------------------
func _test_stealth_in_interactive_resolve_path() -> void:
	print("\n-- T2-1: interactive resolve (resolve_shoot_until_wounds) honours Stealth --")
	var rules = root.get_node("RulesEngine")
	var board = _make_board(true, false)
	var result = _shoot_interactive("bolt_rifle", board, 12345)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Interactive: to_hit dice record present",
		not hit_dice.is_empty(),
		"contexts=%s" % str(_collect_contexts(result)))
	var modifiers = int(hit_dice.get("modifiers_applied", 0))
	_check("Interactive: MINUS_ONE bit set in modifiers_applied",
		(modifiers & rules.HitModifier.MINUS_ONE) != 0,
		"got modifiers=%d" % modifiers)

# ----------------------------------------------------------------------------
# Stealth must NOT apply to melee — the rule is range-only. Drive the same
# RNG seed through the melee path with and without Stealth on the target,
# and assert the hit count is identical (i.e. the threshold was unchanged).
# ----------------------------------------------------------------------------
func _test_stealth_does_not_apply_to_melee() -> void:
	print("\n-- T2-1: Stealth does NOT apply to melee attacks --")
	var rules = root.get_node("RulesEngine")
	# Use lance_melee — WS3+ so threshold is 3+. With stealth (-1) it would
	# be 4+ if leaked. We compare hit counts under the same seed.
	var seeds = [11111, 22222, 33333, 44444, 55555]
	var any_diff_seen := false
	var details := []
	for s in seeds:
		var board_clean = _make_melee_board(false)
		var board_stealth = _make_melee_board(true)
		var r_clean = _melee("lance_melee", board_clean, s)
		var r_stealth = _melee("lance_melee", board_stealth, s)
		var hits_clean = 0
		var hits_stealth = 0
		var dice_clean = _aggregate_dice(r_clean, "hit_roll_melee")
		var dice_stealth = _aggregate_dice(r_stealth, "hit_roll_melee")
		# Some seeds may go through auto_hit_melee if torrent — skip those.
		if dice_clean.is_empty() or dice_stealth.is_empty():
			continue
		hits_clean = int(dice_clean.get("successes", -1))
		hits_stealth = int(dice_stealth.get("successes", -1))
		details.append("seed=%d clean=%d stealth=%d" % [s, hits_clean, hits_stealth])
		if hits_clean != hits_stealth:
			any_diff_seen = true
	_check("Melee: hit counts identical with and without Stealth on target across 5 seeds",
		not any_diff_seen,
		"some seeds differed (Stealth leaked into melee?): %s" % str(details))
	# Also assert at least one seed actually ran a hit roll (not all auto_hit)
	_check("Melee: at least one seed produced a hit_roll_melee record (not all torrent)",
		details.size() > 0,
		"no melee hit-roll records seen across %d seeds" % seeds.size())

# ----------------------------------------------------------------------------
# Statistical: Stealth target receives strictly fewer hits than a clean target
# across many seeds. With BS3+ shooters, hit rate falls from ~67% to ~50%
# (or 4+ unmodified). Use the same seed pool for both so the comparison is
# matched.
# ----------------------------------------------------------------------------
func _test_stealth_statistically_reduces_hits() -> void:
	print("\n-- T2-1: Stealth statistically reduces hits vs same-seed baseline --")
	var seeds = [12345, 22345, 32345, 42345, 52345, 62345, 72345, 82345]
	var hits_clean_total := 0
	var hits_stealth_total := 0
	for s in seeds:
		var r_clean = _shoot("bolt_rifle", _make_board(false, false), s)
		var r_stealth = _shoot("bolt_rifle", _make_board(true, false), s)
		var dice_clean = _aggregate_dice(r_clean, "to_hit")
		var dice_stealth = _aggregate_dice(r_stealth, "to_hit")
		hits_clean_total += int(dice_clean.get("successes", 0))
		hits_stealth_total += int(dice_stealth.get("successes", 0))
	_check("Stealth: total hits strictly less than clean across %d seeds" % seeds.size(),
		hits_stealth_total < hits_clean_total,
		"clean=%d stealth=%d (expected stealth < clean)" % [hits_clean_total, hits_stealth_total])
	# Sanity: gap should be substantial. BS3+ hits 4/6 = 0.667. With -1 hits
	# 3/6 = 0.50. Drop is ~25% relative. We require at least 10% drop to guard
	# against single-seed noise.
	if hits_clean_total > 0:
		var drop_pct = (hits_clean_total - hits_stealth_total) * 100 / hits_clean_total
		_check("Stealth: hit count drop ≥ 10%% (~25%% expected at BS3+ → -1)",
			drop_pct >= 10,
			"clean=%d stealth=%d drop=%d%%" % [hits_clean_total, hits_stealth_total, drop_pct])
	else:
		_check("Clean baseline produced any hits", false, "clean_total=0 — board misconfigured")

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
