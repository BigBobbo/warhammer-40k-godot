extends SceneTree

# Issue #378: validate that Datasheets_leader.csv is loaded and provides a
# canonical fallback for can_lead lookups. Pure-data test against the loader.
# Run via: godot --headless --path 40k --script tests/test_leader_pairings_378.gd

func _initialize():
	# Defer to a frame after autoloads have run.
	call_deferred("_run_tests")

func _run_tests():
	print("=== Issue #378: LeaderPairingsLoader validation ===")
	var failures = 0
	failures += _test_loader_initialized()
	failures += _test_nob_with_banner_pairings()
	failures += _test_warboss_in_mega_armour_pairings()
	failures += _test_kaptin_badrukk_pairings()
	failures += _test_ghazghkull_pairings()
	failures += _test_can_lead_canonical_helper()
	failures += _test_unknown_leader_returns_empty()
	failures += _test_can_attach_uses_canonical_fallback()

	if failures == 0:
		print("\n[OK] all #378 validations passed")
		quit(0)
	else:
		print("\n[FAIL] %d validation(s) failed" % failures)
		quit(1)

var _cached_loader = null

func _get_loader():
	if _cached_loader != null:
		return _cached_loader
	if root != null and root.has_node("LeaderPairingsLoader"):
		_cached_loader = root.get_node("LeaderPairingsLoader")
		return _cached_loader
	# Fallback: instantiate the script directly. Same semantics — this is a
	# pure data loader that just reads two CSV files.
	var script = load("res://autoloads/LeaderPairingsLoader.gd")
	_cached_loader = script.new()
	_cached_loader._load_csvs()
	return _cached_loader

func _test_loader_initialized() -> int:
	print("\n-- LeaderPairingsLoader autoload exists + loaded data --")
	var l = _get_loader()
	if l == null:
		print("[FAIL] " +"LeaderPairingsLoader autoload missing")
		return 1
	if not l._loaded:
		print("[FAIL] " +"LeaderPairingsLoader did not finish loading CSVs")
		return 1
	if l._id_to_name.size() < 100:
		print("[FAIL] " +"expected >100 datasheets loaded, got %d" % l._id_to_name.size())
		return 1
	if l._leader_to_attached.size() < 50:
		print("[FAIL] " +"expected >50 leaders, got %d" % l._leader_to_attached.size())
		return 1
	print("  [OK] loaded %d datasheets, %d leaders" % [l._id_to_name.size(), l._leader_to_attached.size()])
	return 0

func _test_nob_with_banner_pairings() -> int:
	print("\n-- Nob With Waaagh! Banner -> Boyz, Breaka Boyz, Nobz --")
	var l = _get_loader()
	var names = l.get_canonical_attached_names("Nob With Waaagh! Banner")
	# Expect at least Boyz + Nobz (plus possibly Breaka Boyz, others)
	var has_boyz = false
	var has_nobz = false
	for n in names:
		if String(n).to_lower() == "boyz":
			has_boyz = true
		if String(n).to_lower() == "nobz":
			has_nobz = true
	if has_boyz and has_nobz:
		print("  [OK] canonical pairings include Boyz + Nobz: %s" % str(names))
		return 0
	print("[FAIL] " +"expected Boyz + Nobz in pairings, got %s" % str(names))
	return 1

func _test_warboss_in_mega_armour_pairings() -> int:
	print("\n-- Warboss in Mega Armour -> Meganobz (audit row 1) --")
	var l = _get_loader()
	var names = l.get_canonical_attached_names("Warboss in Mega Armour")
	var has_meganobz = false
	for n in names:
		if String(n).to_lower() == "meganobz":
			has_meganobz = true
			break
	if has_meganobz:
		print("  [OK] canonical pairings include Meganobz: %s" % str(names))
		return 0
	print("[FAIL] " +"expected Meganobz in Warboss in Mega Armour pairings, got %s" % str(names))
	return 1

func _test_kaptin_badrukk_pairings() -> int:
	print("\n-- Kaptin Badrukk -> Flash Gitz --")
	var l = _get_loader()
	var names = l.get_canonical_attached_names("Kaptin Badrukk")
	var has_flash = false
	for n in names:
		if String(n).to_lower() == "flash gitz":
			has_flash = true
			break
	if has_flash:
		print("  [OK] canonical pairings include Flash Gitz: %s" % str(names))
		return 0
	print("[FAIL] " +"expected Flash Gitz in Kaptin Badrukk pairings, got %s" % str(names))
	return 1

func _test_ghazghkull_pairings() -> int:
	print("\n-- Ghazghkull Thraka has at least one canonical pairing --")
	var l = _get_loader()
	var names = l.get_canonical_attached_names("Ghazghkull Thraka")
	if names.size() > 0:
		print("  [OK] %d pairings: %s" % [names.size(), str(names)])
		return 0
	print("[FAIL] " +"expected non-empty pairings for Ghazghkull Thraka, got %s" % str(names))
	return 1

func _test_can_lead_canonical_helper() -> int:
	print("\n-- can_lead_canonical(leader, bodyguard) returns true for known pairing --")
	var l = _get_loader()
	if not l.can_lead_canonical("Nob With Waaagh! Banner", "Boyz"):
		print("[FAIL] " +"can_lead_canonical(Nob With Banner, Boyz) returned false, expected true")
		return 1
	if l.can_lead_canonical("Nob With Waaagh! Banner", "Caladius Grav-tank"):
		print("[FAIL] " +"can_lead_canonical(Nob With Banner, Caladius) returned true, expected false")
		return 1
	print("  [OK] can_lead_canonical positive + negative cases")
	return 0

func _test_can_attach_uses_canonical_fallback() -> int:
	# Drop a Nob with Waaagh! Banner + a Boyz unit with empty can_lead JSON
	# into GameState and verify CharacterAttachmentManager.can_attach succeeds
	# via the canonical CSV fallback.
	print("\n-- CharacterAttachmentManager falls back to canonical when JSON can_lead is empty --")
	var cam = root.get_node_or_null("/root/CharacterAttachmentManager")
	if cam == null:
		print("[FAIL] CharacterAttachmentManager autoload missing")
		return 1
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("[FAIL] GameState autoload missing")
		return 1
	gs.state["units"] = {
		"U_NOB_BANNER": {
			"id": "U_NOB_BANNER",
			"owner": 2,
			"meta": {
				"name": "Nob With Waaagh! Banner",
				"keywords": ["ORKS", "INFANTRY", "CHARACTER", "NOB WITH WAAAGH! BANNER"],
				"leader_data": {"can_lead": []},  # empty -> must hit canonical fallback
			},
			"models": [{"id": "m1", "alive": true}],
		},
		"U_BOYZ_TEST": {
			"id": "U_BOYZ_TEST",
			"owner": 2,
			"meta": {
				"name": "Boyz",
				"keywords": ["ORKS", "INFANTRY", "BOYZ", "BATTLELINE"],
			},
			"models": [{"id": "m1", "alive": true}],
		},
		"U_DREAD_TEST": {
			"id": "U_DREAD_TEST",
			"owner": 2,
			"meta": {
				"name": "Deff Dread",
				"keywords": ["ORKS", "VEHICLE", "DEFF DREAD"],
			},
			"models": [{"id": "m1", "alive": true}],
		},
	}
	var positive = cam.can_attach("U_NOB_BANNER", "U_BOYZ_TEST")
	if not positive.get("valid", false):
		print("[FAIL] expected can_attach(NobBanner -> Boyz) valid, got %s" % str(positive))
		return 1
	var negative = cam.can_attach("U_NOB_BANNER", "U_DREAD_TEST")
	if negative.get("valid", true):
		print("[FAIL] expected can_attach(NobBanner -> Deff Dread) invalid, got %s" % str(negative))
		return 1
	print("  [OK] canonical fallback: NobBanner -> Boyz=valid, NobBanner -> DeffDread=invalid")
	return 0


func _test_unknown_leader_returns_empty() -> int:
	print("\n-- get_canonical_attached_names('NotARealLeader') -> [] --")
	var l = _get_loader()
	var names = l.get_canonical_attached_names("NotARealLeader 9999")
	if names.is_empty():
		print("  [OK] unknown leader -> empty list")
		return 0
	print("[FAIL] " +"expected empty for unknown leader, got %s" % str(names))
	return 1
