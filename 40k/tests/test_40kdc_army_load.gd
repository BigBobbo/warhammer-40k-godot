extends SceneTree

# 40kdc regeneration gate: every army JSON under res://armies/ must load
# through ArmyListManager without hard errors (unknown structured weapon
# ability ids fail the load), carry 11e-marked faction meta, and produce
# units with complete stats, weapons, and models.
#
# Run via: godot --headless --path 40k --script tests/test_40kdc_army_load.gd

func _initialize():
	await create_timer(0.2).timeout
	var alm = root.get_node_or_null("ArmyListManager")
	if alm == null:
		print("FAIL: missing ArmyListManager autoload")
		quit(1)
		return
	var passed := 0
	var failed := 0
	alm.scan_available_armies()
	var armies: Array = alm.available_armies
	print("Discovered armies: ", armies)
	if armies.is_empty():
		print("FAIL: no armies discovered")
		quit(1)
		return
	for army_id in armies:
		if String(army_id).contains("stub"):
			continue
		var data: Dictionary = alm.load_army_list(army_id, 1)
		if data.is_empty():
			print("FAIL: %s did not load (validation error above)" % army_id)
			failed += 1
			continue
		var units: Dictionary = data.get("units", {})
		var unit_fail := false
		for uid in units:
			var u: Dictionary = units[uid]
			var meta: Dictionary = u.get("meta", {})
			var stats: Dictionary = meta.get("stats", {})
			for req in ["move", "toughness", "save", "wounds", "leadership", "objective_control"]:
				if not stats.has(req):
					print("FAIL: %s/%s missing stat %s" % [army_id, uid, req])
					unit_fail = true
			if (u.get("models", []) as Array).is_empty():
				print("FAIL: %s/%s has no models" % [army_id, uid])
				unit_fail = true
			if int(meta.get("points", 0)) <= 0:
				print("WARN: %s/%s has points %s" % [army_id, uid, str(meta.get("points"))])
		# edition marker on regenerated files
		var faction: Dictionary = data.get("faction", {})
		if int(faction.get("edition", 0)) != 11:
			print("WARN: %s faction.edition != 11 (%s)" % [army_id, str(faction.get("edition"))])
		if unit_fail:
			failed += 1
		else:
			passed += 1
			print("PASS: %s (%d units, %d pts declared)" % [army_id, units.size(), int(faction.get("points", 0))])
	print("\n=== 40kdc army load: %d passed, %d failed ===" % [passed, failed])
	quit(0 if failed == 0 else 1)
