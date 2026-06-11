extends SceneTree

# ISS-048 (step 1): the 11e shooting-type templates (10.04-10.07, 15.09,
# 17.03) as ShootingType strategy objects + the engine-side modifier
# integration:
#  - eligibility matrix per type (Normal/Assault/Close-Quarters/Indirect;
#    Snap is rule-granted only)
#  - WHILE constraints: assault-only weapons after advancing; CQ weapon/
#    target rules incl. [PISTOL]=[CLOSE-QUARTERS] (24.27) and the pg-88
#    FAQ cases (no BLAST vs engaged units in either direction)
#  - indirect fail bands (1-5; 1-3 with stationary + spotter), cover, no
#    re-rolls; snap = unmodified 6s only
#  - ModifierStack: 10.06 M/V -1 and 17.03 engaged-M/V-target -1 replace
#    10e's Big Guns Never Tire (gated < 11) and feed both resolve paths
#
# Usage: godot --headless --path . -s tests/test_iss048_shooting_types_11e.gd

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

func _w(name: String, special: String) -> Dictionary:
	return {"name": name, "type": "Ranged", "range": "24", "attacks": "2",
		"ballistic_skill": "3", "strength": "4", "ap": "0", "damage": "1",
		"special_rules": special}

func _model(id: String, x: float, y: float) -> Dictionary:
	return {"id": id, "alive": true, "wounds": 2, "current_wounds": 2,
		"base_mm": 32, "base_type": "circular", "position": {"x": x, "y": y}}

## Squad at (400,400); enemy infantry ENGAGED at (470,400) [~0.5" edge at
## 2" ER]; enemy vehicle far at (1400,400); friendly tank at (400,1400)
## (unengaged); enemy infantry far at (400,2000).
func _board(squad_flags: Dictionary = {}, tank_pos: Dictionary = {"x": 400, "y": 1400}) -> Dictionary:
	return {"units": {
		"U_SQUAD": {"id": "U_SQUAD", "owner": 1, "flags": squad_flags,
			"meta": {"name": "Squad", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 3, "wounds": 2},
				"weapons": [_w("Boltgun", ""), _w("Hand Pistol", "pistol"),
					_w("Assault Rifle", "assault"), _w("Frag Launcher", "blast"),
					_w("Mortar", "indirect fire")]},
			"models": [_model("m0", 400, 400)]},
		"U_TANK": {"id": "U_TANK", "owner": 1, "flags": {},
			"meta": {"name": "Tank", "keywords": ["VEHICLE"],
				"stats": {"toughness": 9, "save": 3, "wounds": 12},
				"weapons": [_w("Battle Cannon", ""), _w("Hull Stubber", "close quarters"),
					_w("Demolisher", "blast")]},
			"models": [{"id": "t0", "alive": true, "wounds": 12, "current_wounds": 12,
				"base_mm": 100, "base_type": "circular", "position": tank_pos}]},
		"U_FOE": {"id": "U_FOE", "owner": 2, "flags": {},
			"meta": {"name": "Foe", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 5, "wounds": 1}},
			"models": [_model("f0", 470, 400)]},
		"U_FOE_TANK": {"id": "U_FOE_TANK", "owner": 2, "flags": {},
			"meta": {"name": "Foe Tank", "keywords": ["VEHICLE"],
				"stats": {"toughness": 9, "save": 3, "wounds": 12}},
			"models": [{"id": "ft0", "alive": true, "wounds": 12, "current_wounds": 12,
				"base_mm": 100, "base_type": "circular", "position": {"x": 1400, "y": 400}}]},
		"U_FOE_FAR": {"id": "U_FOE_FAR", "owner": 2, "flags": {},
			"meta": {"name": "Far Foe", "keywords": ["INFANTRY"],
				"stats": {"toughness": 4, "save": 5, "wounds": 1}},
			"models": [_model("ff0", 400, 2000)]},
	},
	# Non-empty terrain list prevents EnhancedLineOfSight's fallback to the
	# LIVE TerrainManager terrain (ambient state would block fixture LoS);
	# a low feature with no polygon blocks nothing.
	"terrain_features": [{"id": "dummy_low", "height_category": "low", "polygon": [], "walls": []}],
	"meta": {}}

func _profile(rules, weapon_name: String, board: Dictionary) -> Dictionary:
	return rules.get_weapon_profile(weapon_name, board)

func _run_tests():
	if passed > 0 or failed > 0:
		return
	print("\n=== test_iss048_shooting_types_11e ===\n")
	var rules = root.get_node_or_null("RulesEngine")
	_check("RulesEngine present", rules != null)

	print("-- registry + eligibility matrix (10.02/10.04-10.07) --")
	GameConstants.edition = 10
	_check("edition 10: no 11e shooting types offered",
		ShootingTypes.available_for("U_SQUAD", _board()).is_empty())
	GameConstants.edition = 11
	var avail = ShootingTypes.available_for("U_SQUAD", _board())
	_check("engaged squad with [PISTOL]: close-quarters ONLY (10.06; 24.27)",
		avail == ["close_quarters"], str(avail))
	avail = ShootingTypes.available_for("U_TANK", _board())
	_check("unengaged tank, no advance: normal (+ no assault/CQ/indirect)",
		avail == ["normal"], str(avail))
	var b = _board({"advanced": true})
	b.units["U_FOE"].models[0].position = {"x": 400, "y": 2400}  # disengage squad
	avail = ShootingTypes.available_for("U_SQUAD", b)
	_check("unengaged squad that advanced: assault ONLY (10.05)",
		avail == ["assault"], str(avail))
	b = _board()
	b.units["U_FOE"].models[0].position = {"x": 400, "y": 2400}
	avail = ShootingTypes.available_for("U_SQUAD", b)
	_check("unengaged squad, no advance, has [INDIRECT FIRE]: normal + indirect",
		avail == ["normal", "indirect"], str(avail))
	b = _board()
	b.units["U_TANK"].models[0].position = {"x": 540, "y": 400}  # engage tank with U_FOE
	avail = ShootingTypes.available_for("U_TANK", b)
	_check("engaged VEHICLE without CQ requirement: close-quarters (10.06 M/V clause)",
		avail == ["close_quarters"], str(avail))
	_check("snap shooting never freely selectable (15.09)",
		not ShootingTypes.get_type("snap").eligible("U_SQUAD", _board()).eligible)

	print("\n-- WHILE constraints --")
	var board = _board()
	var assault_type = ShootingTypes.get_type("assault")
	_check("assault: [ASSAULT] weapon allowed",
		assault_type.weapon_allowed(_profile(rules, "Assault Rifle", board), board.units["U_SQUAD"], board).allowed)
	_check("assault: plain weapon refused (10.05)",
		not assault_type.weapon_allowed(_profile(rules, "Boltgun", board), board.units["U_SQUAD"], board).allowed)

	var cq = ShootingTypes.get_type("close_quarters")
	_check("CQ non-M/V: [PISTOL] counts as [CLOSE-QUARTERS] (24.27)",
		cq.weapon_allowed(_profile(rules, "Hand Pistol", board), board.units["U_SQUAD"], board).allowed)
	_check("CQ non-M/V: plain weapon refused (10.06)",
		not cq.weapon_allowed(_profile(rules, "Boltgun", board), board.units["U_SQUAD"], board).allowed)
	_check("CQ non-M/V: may target the unit it is engaged with",
		cq.target_allowed("U_SQUAD", "U_FOE", _profile(rules, "Hand Pistol", board), board).allowed)
	_check("CQ non-M/V: may NOT target unengaged units (10.06)",
		not cq.target_allowed("U_SQUAD", "U_FOE_FAR", _profile(rules, "Hand Pistol", board), board).allowed)

	# pg-88 FAQ cases: no BLAST vs engaged units in either direction.
	var bt = _board({}, {"x": 540, "y": 400})  # tank engaged with U_FOE
	_check("FAQ: engaged M/V cannot fire [BLAST] at the unit it is engaged with",
		not cq.target_allowed("U_TANK", "U_FOE", _profile(rules, "Demolisher", bt), bt).allowed)
	var normal_type = ShootingTypes.get_type("normal")
	_check("FAQ: [BLAST] cannot target an engaged enemy M/V either (24.04 over 17.03)",
		not normal_type.target_allowed("U_SQUAD", "U_FOE_TANK", _profile(rules, "Frag Launcher", _eng_tank_board()), _eng_tank_board()).allowed)
	_check("baseline: engaged non-M/V enemies are not eligible targets (17.03)",
		not normal_type.target_allowed("U_TANK", "U_FOE", _profile(rules, "Battle Cannon", board), board).allowed)
	_check("17.03: engaged enemy M/V IS targetable",
		normal_type.target_allowed("U_SQUAD", "U_FOE_TANK", _profile(rules, "Boltgun", _eng_tank_board()), _eng_tank_board()).allowed)

	print("\n-- hit consequences --")
	_check("CQ M/V: -1 to hit with a non-CQ weapon (10.06)",
		cq.hit_consequences(_profile(rules, "Battle Cannon", bt), "U_TANK", "U_FOE", bt).hit_roll_delta == -1)
	_check("CQ M/V: NO penalty with a [CLOSE-QUARTERS] weapon vs the engaged target",
		cq.hit_consequences(_profile(rules, "Hull Stubber", bt), "U_TANK", "U_FOE", bt).hit_roll_delta == 0)
	var ind = ShootingTypes.get_type("indirect")
	var ic = ind.hit_consequences(_profile(rules, "Mortar", board), "U_SQUAD", "U_FOE_FAR", board)
	_check("indirect: cover + no hit re-rolls + unmodified 1-5 fails (10.07)",
		ic.grants_target_cover and ic.no_hit_rerolls and ic.fail_band == 5, str(ic))
	var bs = _board({"remained_stationary": true})
	ic = ind.hit_consequences(_profile(rules, "Mortar", bs), "U_SQUAD", "U_FOE_FAR", bs)
	_check("indirect: stationary + friendly spotter sees target -> 1-3 fails",
		ic.fail_band == 3, str(ic))
	var snap = ShootingTypes.get_type("snap")
	var sc = snap.hit_consequences(_profile(rules, "Boltgun", board), "U_SQUAD", "U_FOE_FAR", board)
	_check("snap: unmodified 6s only + no re-rolls (15.09)",
		sc.snap_only_6s and sc.no_hit_rerolls)
	_check("snap: target beyond 24\" refused",
		not snap.target_allowed("U_SQUAD", "U_FOE_FAR", _profile(rules, "Boltgun", board), board).allowed)
	var sb = _board()
	sb.units["U_FOE"].models[0].position = {"x": 400, "y": 1200}  # unengaged, ~20"
	_check("snap: visible unengaged target within 24\" allowed",
		snap.target_allowed("U_SQUAD", "U_FOE", _profile(rules, "Boltgun", sb), sb).allowed)

	print("\n-- ModifierStack integration (replaces BGNT at 11e) --")
	var mb = _board({}, {"x": 540, "y": 400})
	var stack = ModifierStack.collect_hit_context_11e(mb.units["U_TANK"], mb.units["U_FOE_FAR"],
		_profile(rules, "Battle Cannon", mb), mb)
	_check("engaged VEHICLE shooter, plain weapon: -1 (10.06 via stack)",
		stack.net("hit_roll") == -1 and "close_quarters_monster_vehicle" in stack.sources("hit_roll"),
		stack.describe())
	stack = ModifierStack.collect_hit_context_11e(mb.units["U_TANK"], mb.units["U_FOE"],
		_profile(rules, "Hull Stubber", mb), mb)
	_check("engaged VEHICLE with CQ weapon vs its engaged target: no penalty",
		stack.net("hit_roll") == 0, stack.describe())
	var eb = _eng_tank_board()
	stack = ModifierStack.collect_hit_context_11e(eb.units["U_SQUAD"], eb.units["U_FOE_TANK"],
		_profile(rules, "Boltgun", eb), eb)
	_check("shooting an ENGAGED enemy VEHICLE: -1 (17.03 via stack)",
		stack.net("hit_roll") == -1 and "engaged_monster_vehicle_target" in stack.sources("hit_roll"),
		stack.describe())
	GameConstants.edition = 10
	stack = ModifierStack.collect_hit_context_11e(mb.units["U_TANK"], mb.units["U_FOE_FAR"],
		_profile(rules, "Battle Cannon", mb), mb)
	_check("edition 10: stack empty (BGNT path owns 10e, gated < 11)",
		stack.entries.is_empty())

	GameConstants.edition = 10
	print("\n=== Result: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)

## Board where the squad is unengaged but the enemy TANK is engaged (with
## the friendly tank moved next to it).
func _eng_tank_board() -> Dictionary:
	var b = _board()
	b.units["U_FOE"].models[0].position = {"x": 400, "y": 2400}   # free the squad
	b.units["U_TANK"].models[0].position = {"x": 1290, "y": 400}  # engage the foe tank
	return b
