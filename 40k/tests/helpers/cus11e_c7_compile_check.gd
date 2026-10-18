extends SceneTree

## Compile check for the WP-C7 touched scripts (headless):
##   godot --headless --path 40k -s tests/helpers/cus11e_c7_compile_check.gd

const SCRIPTS := [
	"res://scripts/codex/custodes/CustodesAbilities.gd",
	"res://autoloads/RulesEngine.gd",
	"res://autoloads/StratagemManager.gd",
	"res://autoloads/UnitAbilityManager.gd",
	"res://autoloads/EffectPrimitives.gd",
	"res://autoloads/PhaseManager.gd",
	"res://autoloads/TerrainManager.gd",
	"res://phases/BasePhase.gd",
	"res://phases/FightPhase.gd",
	"res://phases/ShootingPhase.gd",
	"res://phases/MovementPhase.gd",
	"res://phases/ChargePhase.gd",
	"res://phases/CommandPhase.gd",
	"res://phases/FormationsPhase.gd",
	"res://scripts/FightController.gd",
	"res://scripts/ShootingController.gd",
	"res://scripts/MovementController.gd",
	"res://scripts/AIDecisionMaker.gd",
	"res://scripts/DiceLogFormatter.gd",
	"res://scripts/rules/movetypes/FallBackMove.gd",
	"res://scripts/codex/custodes/CustodesCodexOther.gd",
	"res://scripts/rules/movetypes/ChargeMove11e.gd",
	# merged from WP-C46 (integration tip 4700afbf)
	"res://scripts/codex/custodes/CustodesDetachments.gd",
	"res://scripts/codex/custodes/CustodesEnhancements.gd",
	"res://scripts/codex/EnhancementRules11e.gd",
	"res://scripts/CommandController.gd",
]

func _initialize() -> void:
	await create_timer(0.2).timeout
	var bad := 0
	for p in SCRIPTS:
		var s = load(p)
		if s == null or not (s is GDScript) or not s.can_instantiate():
			print("COMPILE FAIL: %s" % p)
			bad += 1
		else:
			print("ok: %s" % p)
	print("=== compile check: %d failure(s) ===" % bad)
	quit(1 if bad > 0 else 0)
