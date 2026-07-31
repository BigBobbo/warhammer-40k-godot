extends SceneTree

# MA-LOADOUT (melee): a model only swings a weapon it is actually equipped with.
#
# Reported 2026-07-30 via the T6 tutorial: 10 Boyz all swung the Boss Nob's
# Power klaw — 30 attacks at S9 AP-2 D2 where the datasheet gives one model
# three — and wiped the Custodian Guard the lesson needed alive 38% of the time.
# The Shooting phase has always resolved weapons per model; the Fight phase
# applied whatever the attack dialog picked to every eligible model.
#
# What this pins:
#   * carriers come from model_profiles (Boss Nob has the klaw, Boyz do not)
#   * a resolved `melee_loadout` on the model wins over the profile menu
#   * a unit whose data cannot tell its models apart is UNCHANGED (every model
#     still swings the pick) — the fix only narrows where the data supports it
#   * a weapon nobody carries falls back to the old behaviour instead of
#     silently deleting the unit's attacks
#   * an explicit `models` selection still wins, intersected with the carriers
#   * end to end: resolve_melee_attacks rolls the carriers' attacks, not the
#     whole unit's
#
# Usage: godot --headless --path . -s tests/test_melee_per_model_loadout.gd

var passed := 0
var failed := 0
# The autoload, fetched at runtime. Naming RulesEngine at parse time compiles
# this script before the autoloads register (same reason the staged-fight tests
# load() their phase instead of naming the class).
var RE = null


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  PASS: %s" % label)
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, "  --  " + detail if detail != "" else ""])


func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)


# A Boyz-shaped mob: one Boss Nob with a Power klaw, four Boyz without.
func _mob(with_profiles: bool = true) -> Dictionary:
	var models := []
	for i in range(5):
		models.append({
			"id": "m%d" % i, "position": {"x": 0, "y": float(i * 35)},
			"base_mm": 32, "base_type": "circular", "alive": true,
			"wounds": 1, "current_wounds": 1,
			"model_type": "boss_nob" if i == 0 else "boy"
		})
	var meta := {
		"name": "Boyz", "keywords": ["INFANTRY"],
		"stats": {"toughness": 5, "save": 6, "wounds": 1},
		"weapons": [
			{"name": "Power klaw", "type": "Melee", "range": "Melee", "attacks": "3",
				"weapon_skill": "4", "strength": "9", "ap": "-2", "damage": "2", "special_rules": ""},
			{"name": "Choppa", "type": "Melee", "range": "Melee", "attacks": "3",
				"weapon_skill": "3", "strength": "4", "ap": "-1", "damage": "1", "special_rules": ""}
		]
	}
	if with_profiles:
		meta["model_profiles"] = {
			"boss_nob": {"label": "Boss Nob", "weapons": ["Power klaw", "Choppa"]},
			"boy": {"label": "Boy", "weapons": ["Choppa"]}
		}
	return {"id": "U_MOB", "owner": 1, "flags": {}, "meta": meta, "models": models}


func _state(mob: Dictionary) -> Dictionary:
	var target_models := []
	for i in range(4):
		target_models.append({
			"id": "mt%d" % i, "position": {"x": 40, "y": float(i * 35)},
			"base_mm": 40, "base_type": "circular", "alive": true,
			"wounds": 4, "current_wounds": 4
		})
	return {
		"meta": {"phase": 10, "active_player": 1, "battle_round": 1, "turn": 1},
		"board": {"size": {"width": 1760, "height": 2400}, "objectives": []},
		"players": {"1": {"cp": 1, "vp": 0}, "2": {"cp": 1, "vp": 0}},
		"units": {
			"U_MOB": mob,
			"U_TARGET": {
				"id": "U_TARGET", "owner": 2, "flags": {},
				"meta": {"name": "Custodian Guard", "keywords": ["INFANTRY"],
					"stats": {"toughness": 6, "save": 2, "wounds": 4}},
				"models": target_models
			}
		}
	}


func _run():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_melee_per_model_loadout ===\n")
	RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		_check("RulesEngine autoload reachable", false)
		_finish()
		return
	GameConstants.edition = 11

	var klaw: String = RE.generate_weapon_id("Power klaw", "Melee")
	var choppa: String = RE.generate_weapon_id("Choppa", "Melee")

	# --- carriers from model_profiles ---------------------------------------
	var mob := _mob(true)
	var board := _state(mob)
	var eligible: Array = RE.get_eligible_melee_model_indices(mob, board)
	_check("all 5 models are eligible to fight", eligible.size() == 5, str(eligible))

	var klaw_carriers: Array = RE.get_melee_weapon_swingers(mob, klaw, eligible, [])
	_check("only the Boss Nob swings the Power klaw",
		klaw_carriers == [0], str(klaw_carriers))
	var choppa_carriers: Array = RE.get_melee_weapon_swingers(mob, choppa, eligible, [])
	_check("every model swings a Choppa (both profiles list it)",
		choppa_carriers.size() == 5, str(choppa_carriers))

	# --- a resolved melee_loadout overrides the profile menu ----------------
	var pinned := _mob(true)
	pinned.models[1]["melee_loadout"] = ["Power klaw"]
	_check("a roster-resolved melee_loadout wins over model_profiles",
		RE.get_melee_weapon_swingers(pinned, klaw, eligible, []) == [0, 1],
		str(RE.get_melee_weapon_swingers(pinned, klaw, eligible, [])))

	# --- units the data cannot tell apart are untouched ---------------------
	var flat := _mob(false)
	_check("no model_profiles: every model still swings the pick (behaviour unchanged)",
		RE.get_melee_weapon_swingers(flat, klaw, eligible, []).size() == 5)

	# --- a weapon nobody carries keeps the old selection --------------------
	var orphan: String = RE.generate_weapon_id("Thunder hammer", "Melee")
	_check("a weapon no profile lists falls back to the eligible models",
		RE.get_melee_weapon_swingers(mob, orphan, eligible, []).size() == 5,
		"must never resolve to zero attackers")

	# --- an explicit model selection still wins -----------------------------
	_check("explicit models are intersected with the carriers",
		RE.get_melee_weapon_swingers(mob, choppa, eligible, ["1", "2"]) == [1, 2],
		str(RE.get_melee_weapon_swingers(mob, choppa, eligible, ["1", "2"])))
	_check("explicit models that carry nothing fall back to that selection",
		RE.get_melee_weapon_swingers(mob, klaw, eligible, ["3"]) == [3],
		str(RE.get_melee_weapon_swingers(mob, klaw, eligible, ["3"])))

	# --- end to end: the roll only counts the carriers ----------------------
	var klaw_action := {"type": "FIGHT", "actor_unit_id": "U_MOB", "payload": {"assignments": [
		{"attacker": "U_MOB", "weapon": klaw, "target": "U_TARGET"}]}}
	var klaw_result = RE.resolve_melee_attacks(klaw_action, _state(_mob(true)), RE.RNGService.new(7))
	var klaw_attacks := 0
	for block in klaw_result.get("dice", []):
		if str(block.get("context", "")) == "hit_roll_melee":
			klaw_attacks = int(block.get("total_attacks", 0))
	_check("the Power klaw rolls 3 attacks (1 model x A3), not 15",
		klaw_attacks == 3, "rolled %d" % klaw_attacks)

	var choppa_action := {"type": "FIGHT", "actor_unit_id": "U_MOB", "payload": {"assignments": [
		{"attacker": "U_MOB", "weapon": choppa, "target": "U_TARGET"}]}}
	var choppa_result = RE.resolve_melee_attacks(choppa_action, _state(_mob(true)), RE.RNGService.new(7))
	var choppa_attacks := 0
	for block in choppa_result.get("dice", []):
		if str(block.get("context", "")) == "hit_roll_melee":
			choppa_attacks = int(block.get("total_attacks", 0))
	_check("the Choppa still rolls the whole mob's 15 attacks",
		choppa_attacks == 15, "rolled %d" % choppa_attacks)

	# The split plan the attack dialog builds: Nob's klaw + the rest's choppas.
	var split_action := {"type": "FIGHT", "actor_unit_id": "U_MOB", "payload": {"assignments": [
		{"attacker": "U_MOB", "weapon": klaw, "target": "U_TARGET", "models": ["0"]},
		{"attacker": "U_MOB", "weapon": choppa, "target": "U_TARGET", "models": ["1", "2", "3", "4"]}]}}
	var split_result = RE.resolve_melee_attacks(split_action, _state(_mob(true)), RE.RNGService.new(7))
	var split_counts: Array = []
	for block in split_result.get("dice", []):
		if str(block.get("context", "")) == "hit_roll_melee":
			split_counts.append(int(block.get("total_attacks", 0)))
	_check("the split plan rolls 3 klaw attacks and 12 choppa attacks",
		split_counts == [3, 12], str(split_counts))

	_finish()


func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [passed, failed])
	quit(1 if failed > 0 else 0)
