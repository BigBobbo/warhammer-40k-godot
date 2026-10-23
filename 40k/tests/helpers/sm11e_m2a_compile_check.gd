extends SceneTree

## Compile check for the WP-M2a modules (Codex: Space Marines 11e army rules +
## detachments A): loads each script and reports a parse failure loudly.
## Usage: godot --headless --path 40k -s tests/helpers/sm11e_m2a_compile_check.gd

const SCRIPTS := [
	"res://scripts/codex/space_wolves/SWCommon.gd",
	"res://scripts/codex/space_wolves/SWArmyRules11e.gd",
	"res://scripts/codex/space_marines/SMDetachmentsA.gd",
	"res://autoloads/RulesEngine.gd",
	"res://phases/CommandPhase.gd",
	"res://phases/MovementPhase.gd",
	"res://phases/ChargePhase.gd",
	"res://phases/BasePhase.gd",
	"res://autoloads/StratagemManager.gd",
	"res://autoloads/GameState.gd",
	"res://autoloads/TerrainManager.gd",
	"res://autoloads/FactionAbilityManager.gd",
	"res://autoloads/ArmyListManager.gd",
	"res://autoloads/PhaseManager.gd",
	"res://scripts/AIDecisionMaker.gd",
]


func _initialize() -> void:
	await create_timer(0.3).timeout
	var bad := 0
	for p in SCRIPTS:
		var s = load(p)
		if s == null or not (s is Script) or not s.can_instantiate():
			print("COMPILE FAIL: %s" % p)
			bad += 1
		else:
			print("ok: %s" % p)
	print("=== compile check: %d failed ===" % bad)
	quit(1 if bad > 0 else 0)
