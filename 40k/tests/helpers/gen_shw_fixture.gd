extends SceneTree

# Generates the `shw_walker_11e` test fixture: the audit post-deployment
# baseline plus a single SUPER-HEAVY WALKER unit deployed for player 1. The
# default Custodes/Orks armies contain no SUPER-HEAVY WALKER datasheet, so
# ISS-073's MOBILE-gamble movement toggle (24.35) has no naturally-reachable
# unit to drive. This bakes one in so the windowed scenario
# tests/scenarios/sp/iss073_shw_mobile_gamble_11e.json can select it (token
# renders at load) and click the real toggle + Confirm Movement Mode button.
#
# Usage (writes res://saves/shw_walker_11e.w40ksave):
#   godot --headless --path . -s tests/helpers/gen_shw_fixture.gd
#
# Re-run after regenerating audit_baseline_postdeploy. Commit the produced
# .w40ksave (and its .meta) to tests/saves/ so the fixture is reproducible.

const BASE_FIXTURE := "audit_baseline_postdeploy"
const OUT_FIXTURE := "shw_walker_11e"
const SHW_UNIT_ID := "U_STOMPA_TEST"

var _ran := false

func _init() -> void:
	# Defer until autoloads have run their _ready (next idle frame), mirroring
	# the pretrigger test harness.
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)

func _run() -> void:
	if _ran:
		return
	_ran = true
	print("=== gen_shw_fixture ===")
	var slm := root.get_node_or_null("SaveLoadManager")
	var gs := root.get_node_or_null("GameState")
	if slm == null or gs == null:
		push_error("autoloads missing (SaveLoadManager/GameState)")
		quit(1)
		return

	if not slm.load_game(BASE_FIXTURE):
		push_error("could not load base fixture %s — is it in res://saves/?" % BASE_FIXTURE)
		quit(1)
		return
	print("loaded base fixture: %s" % BASE_FIXTURE)

	# A SUPER-HEAVY WALKER deployed for player 1, modelled on the baseline's
	# Telemon (owner 1, status DEPLOYED=2, large circular base). Placed in clear
	# space in player 1's deployment zone, away from existing tokens.
	var shw := {
		"id": SHW_UNIT_ID,
		"squad_id": SHW_UNIT_ID,
		"owner": 1,
		"status": 2,  # GameState.UnitStatus.DEPLOYED
		"attached_to": null,
		"attachment_data": {"attached_characters": []},
		"disembarked_this_phase": false,
		"embarked_in": null,
		"flags": {},
		"meta": {
			"name": "Gorkanaut (test SHW)",
			"display_name": "Gorkanaut (test SHW)",
			"keywords": ["ORKS", "WALKER", "TITANIC", "VEHICLE", "SUPER-HEAVY WALKER"],
			"abilities": [],
			"enhancements": [],
			"is_warlord": false,
			"points": 0,
			"stats": {
				"move": 8.0,
				"toughness": 12.0,
				"save": 3.0,
				"wounds": 24.0,
				"leadership": 7.0,
				"objective_control": 10.0,
			},
			"unit_composition": {},
			"wargear": [],
			"weapons": [],
		},
		"models": [
			{
				"id": "m1",
				"alive": true,
				"base_mm": 160.0,
				"base_type": "circular",
				"current_wounds": 24.0,
				"wounds": 24.0,
				"position": {"x": 980.0, "y": 250.0},
				"status_effects": [],
			}
		],
	}
	gs.state["units"][SHW_UNIT_ID] = shw
	print("injected SHW unit %s (owner 1, DEPLOYED, SUPER-HEAVY WALKER)" % SHW_UNIT_ID)

	if not slm.save_game(OUT_FIXTURE, {"type": "test_fixture", "note": "ISS-073 SHW gamble"}):
		push_error("save_game(%s) failed" % OUT_FIXTURE)
		quit(1)
		return
	print("=== wrote res://saves/%s.w40ksave ===" % OUT_FIXTURE)
	quit(0)
