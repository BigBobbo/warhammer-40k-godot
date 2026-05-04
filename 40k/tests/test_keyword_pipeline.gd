extends SceneTree

# T2.S4-S6: Sustained Hits / Lethal Hits / Devastating Wounds keyword pipeline
#
# Verifies the dice-record contract for the three offensive keywords by running
# resolve_shoot through the test weapons (sustained_bolter, lethal_bolter,
# devastating_bolter) with a fixed RNG seed and a high attack count override.
#
# We assert on the structured tracking fields the dice records expose so a
# regression in the wound/hit pipeline that drops one of these counters surfaces
# as a failed assertion, not silently as a missing damage bonus.
#
# Each weapon has BS3+, so on a unmodified roll of 6 (1/6 of attacks) the keyword
# triggers. With attacks_override=60 we expect ~10 critical hits — enough that
# both the deterministic-seed run and the multi-trial sampling are stable.
#
# Usage: godot --headless --path . -s tests/test_keyword_pipeline.gd

var passed := 0
var failed := 0

const ATTACKS = 60

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

# Build a minimal board with shooter at (0,0), target at (40,0) (~1" — well in
# range of the 24" test bolters). All models are 32mm circular, alive, T4, 1W,
# Sv4+. Weapons override attacks via attacks_override so we don't depend on the
# variable-attacks roll.
func _make_board() -> Dictionary:
	var shooter_models = []
	for i in range(4):
		shooter_models.append({
			"id": "ms%d" % i,
			"position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1
		})
	var target_models = []
	for i in range(8):
		target_models.append({
			"id": "mt%d" % i,
			"position": {"x": 40, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular",
			"alive": true, "wounds": 1, "current_wounds": 1,
			"stats": {"toughness": 4, "save": 4}
		})
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
				"meta": {"keywords": ["INFANTRY"], "stats": {"toughness": 4, "save": 4, "wounds": 1}},
				"flags": {},
				"models": target_models
			}
		},
		"meta": {"phase": 8, "active_player": 1, "battle_round": 1}
	}
	return board

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

func _aggregate_dice(result: Dictionary, context: String) -> Dictionary:
	"""Find the first dice record with the given context."""
	for d in result.get("dice", []):
		if d.get("context", "") == context:
			return d
	return {}

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_keyword_pipeline ===\n")

	_test_sustained_hits()
	_test_lethal_hits()
	_test_devastating_wounds()

	_finish()

# ----------------------------------------------------------------------------
# T2.S4: SUSTAINED HITS — unmodified 6 to hit generates +1 hit
# ----------------------------------------------------------------------------
func _test_sustained_hits() -> void:
	print("\n-- T2.S4: SUSTAINED HITS --")
	var board = _make_board()
	var result = _shoot("sustained_bolter", board, 12345)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Sustained: to_hit dice record present",
		not hit_dice.is_empty(),
		"dice contexts: %s" % str(_collect_contexts(result)))
	_check("Sustained: weapon flagged sustained_hits_weapon=true",
		hit_dice.get("sustained_hits_weapon") == true)
	_check("Sustained: sustained_hits_value=1 reflected in dice record",
		hit_dice.get("sustained_hits_value") == 1,
		"got %s" % str(hit_dice.get("sustained_hits_value")))

	# Check that bonus hits actually fired for at least one trial across 5 seeds.
	# Field name is `sustained_bonus_hits` in to_hit record (different from
	# to_wound's `sustained_bonus_hits_rolled`).
	var any_bonus = false
	var attempts := []
	for s in [12345, 22345, 32345, 42345, 52345]:
		var r = _shoot("sustained_bolter", _make_board(), s)
		var hd = _aggregate_dice(r, "to_hit")
		var bonus = hd.get("sustained_bonus_hits", 0)
		var crits = hd.get("critical_hits", 0)
		attempts.append("seed=%d crits=%d bonus=%d" % [s, crits, bonus])
		if bonus > 0:
			any_bonus = true
			break
	_check("Sustained: at least one trial across 5 seeds rolled a bonus hit",
		any_bonus,
		"trials: %s" % str(attempts))

# ----------------------------------------------------------------------------
# T2.S5: LETHAL HITS — unmodified 6 to hit auto-wounds (skips wound roll)
# ----------------------------------------------------------------------------
func _test_lethal_hits() -> void:
	print("\n-- T2.S5: LETHAL HITS --")
	var board = _make_board()
	var result = _shoot("lethal_bolter", board, 67890)

	var hit_dice = _aggregate_dice(result, "to_hit")
	_check("Lethal: to_hit dice record present", not hit_dice.is_empty())
	_check("Lethal: weapon flagged lethal_hits_weapon=true",
		hit_dice.get("lethal_hits_weapon") == true)

	var wound_dice = _aggregate_dice(result, "to_wound")
	_check("Lethal: to_wound dice record present", not wound_dice.is_empty())
	_check("Lethal: lethal_hits_weapon=true on wound record",
		wound_dice.get("lethal_hits_weapon") == true)

	# auto_wounds should be > 0 in at least one of 5 trials
	var any_auto = false
	for s in [67890, 77890, 87890, 97890, 107890]:
		var r = _shoot("lethal_bolter", _make_board(), s)
		var wd = _aggregate_dice(r, "to_wound")
		if wd.get("lethal_hits_auto_wounds", 0) > 0:
			any_auto = true
			break
	_check("Lethal: at least one trial across 5 seeds produced auto-wounds",
		any_auto)

# ----------------------------------------------------------------------------
# T2.S6: DEVASTATING WOUNDS — unmodified 6 to wound becomes mortal (bypasses save)
# ----------------------------------------------------------------------------
func _test_devastating_wounds() -> void:
	print("\n-- T2.S6: DEVASTATING WOUNDS --")
	var board = _make_board()
	var result = _shoot("devastating_bolter", board, 13579)

	var wound_dice = _aggregate_dice(result, "to_wound")
	_check("Devastating: to_wound dice record present", not wound_dice.is_empty())
	_check("Devastating: weapon flagged devastating_wounds_weapon=true",
		wound_dice.get("devastating_wounds_weapon") == true)

	# critical_wounds count should be > 0 across 5 trials
	var any_crit = false
	for s in [13579, 23579, 33579, 43579, 53579]:
		var r = _shoot("devastating_bolter", _make_board(), s)
		var wd = _aggregate_dice(r, "to_wound")
		if wd.get("critical_wounds", 0) > 0:
			any_crit = true
			break
	_check("Devastating: at least one trial across 5 seeds produced a critical wound",
		any_crit)

	# Sanity: when DW triggers, the regular_wounds count tracks the non-critical
	# wounds (that do go to saves). Verify the partition: critical + regular ≤
	# wounds_caused-equivalent (auto+rolls).
	var partition_ok = true
	for s in [13579, 23579, 33579]:
		var r = _shoot("devastating_bolter", _make_board(), s)
		var wd = _aggregate_dice(r, "to_wound")
		var crit = wd.get("critical_wounds", 0)
		var reg = wd.get("regular_wounds", 0)
		var auto = wd.get("lethal_hits_auto_wounds", 0)
		var rolls = wd.get("wounds_from_rolls", 0)
		# For non-LH weapons, auto=0 and partition is crit+reg == rolls
		if (crit + reg) != rolls:
			partition_ok = false
			break
	_check("Devastating: critical + regular partition matches wounds_from_rolls",
		partition_ok)

func _collect_contexts(result: Dictionary) -> Array:
	var arr := []
	for d in result.get("dice", []):
		arr.append(d.get("context", ""))
	return arr

func _finish():
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
