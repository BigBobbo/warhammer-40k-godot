extends SceneTree

# Generates the detachment-sweep windowed fixtures from fullauto_pretrigger
# (orks vs custodes, 11e armies, all deployed, command phase R1P1):
#
#   fullauto_dethunt    — p1 detachment "Da Big Hunt", p2 "Auric Champions"
#                         (designated-target rules: Prey / Assemblage of Might)
#   fullauto_bullyboyz  — p1 detachment "Bully Boyz", p2 "Might of the Moritoi"
#                         (Da Boss Is Watchin' action + passive +2" Move sweep)
#
# The armies are unchanged — only state.factions[*].detachment and the
# FactionAbilityManager detachment cache differ from the base fixture.
#
# Usage (writes res://saves/<name>.w40ksave; copy both files to tests/saves/):
#   godot --headless --path . -s tests/helpers/gen_detachment_fixtures.gd

const BASE_FIXTURE := "fullauto_pretrigger"

var _ran := false

func _init() -> void:
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)

func _run() -> void:
	if _ran:
		return
	_ran = true
	print("=== gen_detachment_fixtures ===")
	var slm := root.get_node_or_null("SaveLoadManager")
	var gs := root.get_node_or_null("GameState")
	var fam := root.get_node_or_null("FactionAbilityManager")
	if slm == null or gs == null or fam == null:
		push_error("autoloads missing (SaveLoadManager/GameState/FactionAbilityManager)")
		quit(1)
		return

	var jobs := [
		{"out": "fullauto_dethunt", "det1": "Da Big Hunt", "det2": "Auric Champions",
			"note": "detachment sweep: Prey/Assemblage designations"},
		{"out": "fullauto_bullyboyz", "det1": "Bully Boyz", "det2": "Might of the Moritoi",
			"note": "detachment sweep: Da Boss Is Watchin' + Moritoi passives"},
	]
	for job in jobs:
		if not slm.load_game(BASE_FIXTURE):
			push_error("could not load base fixture %s" % BASE_FIXTURE)
			quit(1)
			return
		var factions = gs.state.get("factions", {})
		if not factions.has("1") or not factions.has("2"):
			push_error("base fixture has no factions dict")
			quit(1)
			return
		factions["1"]["detachment"] = job.det1
		factions["2"]["detachment"] = job.det2
		# Refresh the manager cache so save_game snapshots the new detachments
		fam.detect_player_detachment(1)
		fam.detect_player_detachment(2)
		if not slm.save_game(job.out, {"type": "test_fixture", "note": job.note,
				"description": "Fixture: orks (%s) vs custodes (%s), from fullauto_pretrigger" % [job.det1, job.det2]}):
			push_error("save_game(%s) failed" % job.out)
			quit(1)
			return
		print("wrote res://saves/%s.w40ksave (p1=%s, p2=%s)" % [job.out, job.det1, job.det2])
	print("=== done ===")
	quit(0)
