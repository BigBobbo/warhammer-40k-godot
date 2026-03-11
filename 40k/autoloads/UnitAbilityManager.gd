extends Node

# UnitAbilityManager - Applies datasheet/faction ability effects using EffectPrimitives
#
# This manager bridges the gap between ability descriptions stored in unit meta.abilities
# and the EffectPrimitives flag system used by RulesEngine during combat resolution.
#
# Architecture:
# - ABILITY_EFFECTS lookup table maps ability names to EffectPrimitives effect definitions
# - At the start of combat-relevant phases (Shooting, Fight), scans all units and applies
#   effect flags for matched abilities (leader abilities, always-on abilities, etc.)
# - At the end of each phase, clears ability-applied effect flags
# - RulesEngine reads the same effect_* flags regardless of whether they came from
#   a stratagem or an ability
#
# Supported ability categories:
# 1. Leader abilities ("while this model is leading a unit") - apply to the led unit
# 2. Always-on unit abilities (Stealth, Ramshackle, etc.) - apply to the unit itself
# 3. Conditional abilities (Waaagh!-dependent, objective-dependent) - apply when condition met
# 4. Aura abilities (affect nearby friendly/enemy units within range) - uses edge-to-edge
#    distance via Measurement.model_to_model_distance_inches(). Same aura from multiple
#    sources does not stack (10th Edition rule).
#
# NOTE: Some abilities are already handled directly in RulesEngine without flags:
# - Stealth: RulesEngine.has_stealth_ability() checks meta.abilities directly
# - Lone Operative: RulesEngine.has_lone_operative() checks meta.abilities directly
# - Deep Strike, Infiltrators, Scouts: handled by deployment phases
# - Transport, Firing Deck: handled by TransportManager
# These are NOT duplicated here to avoid double-application.

# ============================================================================
# ABILITY EFFECTS LOOKUP TABLE
# ============================================================================
# Maps ability names to their EffectPrimitives-based effect definitions.
#
# Each entry:
#   "name": {
#     "condition": String,   # "while_leading", "always", "waaagh_active", "on_objective", "aura"
#     "effects": Array,      # Same format as stratagem effects: [{"type": "...", ...}]
#     "target": String,      # "led_unit" (bodyguard unit), "unit" (self), "model" (self only)
#     "attack_type": String, # "melee", "ranged", "all" — which attacks the effect modifies
#     "implemented": bool,   # Whether we can fully resolve this ability
#     "description": String  # Short description for debugging/UI
#   }
#
# For aura abilities (condition == "aura"), additional fields:
#   "aura_range": float,    # Range in inches (edge-to-edge model distance)
#   "aura_target": String,  # "friendly", "enemy", "all" — which units are affected

const ABILITY_EFFECTS: Dictionary = {
	# ======================================================================
	# LEADER ABILITIES — "While this model is leading a unit..."
	# These apply to the bodyguard unit when the CHARACTER is attached.
	# ======================================================================

	# Ork Warboss / Boss Zagstruk / Speedboss — +1 to melee hit rolls
	"Might is Right": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Warboss on Warbike — same as Might is Right
	"Speedboss": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Boss Zagstruk — same as Might is Right
	"Drill Boss": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Ork Ghazghkull Thraka — +1 to melee Hit AND Wound rolls
	"Prophet of Da Great Waaagh!": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}, {"type": "plus_one_wound"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit and Wound rolls for led unit"
	},

	# Ork Big Mek in Mega Armour — re-roll Hit rolls of 1 (ranged)
	"More Dakka": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_hits", "scope": "ones"}],
		"target": "led_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll ranged Hit rolls of 1 for led unit"
	},

	# Ork Kaptin Badrukk — re-roll Hit rolls (all, ranged)
	"Flashiest Gitz": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_hits", "scope": "all"}],
		"target": "led_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll all ranged Hit rolls for led unit"
	},

	# Ork Boss Snikrot — led unit has Benefit of Cover
	"Red Skull Kommandos": {
		"condition": "while_leading",
		"effects": [{"type": "grant_cover"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Benefit of Cover"
	},

	# Ork Painboy / Mad Dok Grotsnik — led unit has Feel No Pain 5+
	"Dok's Toolz": {
		"condition": "while_leading",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Feel No Pain 5+"
	},

	"Mad Dok": {
		"condition": "while_leading",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit has Feel No Pain 5+"
	},

	# Ork Mad Dok Grotsnik — eligible to charge after falling back
	"One Scalpel Short of a Medpack": {
		"condition": "while_leading",
		"effects": [{"type": "fall_back_and_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit can charge after falling back"
	},

	# Custodes Blade Champion — re-roll Charge rolls
	"Swift Onslaught": {
		"condition": "while_leading",
		"effects": [{"type": "reroll_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Re-roll Charge rolls for led unit"
	},

	# ======================================================================
	# ALWAYS-ON UNIT ABILITIES
	# ======================================================================

	# Custodes Custodian Guard — re-roll Wound rolls of 1
	"Stand Vigil": {
		"condition": "always",
		"effects": [{"type": "reroll_wounds", "scope": "ones"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Re-roll Wound rolls of 1"
	},

	# Ork Battlewagon — worsen AP of incoming attacks by 1
	"Ramshackle": {
		"condition": "always",
		"effects": [{"type": "worsen_ap", "value": 1}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Worsen AP of incoming attacks by 1"
	},

	# Ork Boyz — sticky objectives
	# At end of Command phase, if unit is within range of a controlled objective,
	# that objective remains under your control until opponent controls it.
	# Resolved by MissionManager.apply_sticky_objectives() — not a combat effect.
	"Get Da Good Bitz": {
		"condition": "end_of_command",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Sticky objectives — resolved by MissionManager at end of Command phase"
	},

	# Custodes Witchseekers — FNP 3+ vs Psychic/mortal wounds only
	"Daughters of the Abyss": {
		"condition": "always",
		"effects": [{"type": "grant_fnp_psychic_mortal", "value": 3}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 3+ against Psychic Attacks and mortal wounds only"
	},

	# Custodes Blade Champion — once per battle advance and charge
	"Martial Inspiration": {
		"condition": "while_leading",
		"effects": [{"type": "advance_and_charge"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: charge after advancing"
	},

	# Custodes Custodian Guard — once per battle shoot again after shooting
	"Sentinel Storm": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: shoot again after this unit has shot"
	},

	# Custodes Witchseekers — force Battle-shock test after shooting
	"Sanctified Flames": {
		"condition": "after_shooting",
		"effects": [],
		"target": "enemy_hit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "After shooting, one enemy unit hit must take a Battle-shock test"
	},

	# Deadly Demise — mortal wounds when destroyed (Battlewagon D6, Caladius D3, Telemon D3, Contemptor-Achillus 1)
	# The value (D6/D3/1) is parsed from the ability name, e.g. "Deadly Demise D6"
	# Triggered on unit destruction — resolved by RulesEngine.resolve_deadly_demise()
	"Deadly Demise": {
		"condition": "on_destruction",
		"effects": [],
		"target": "all_within_6",
		"attack_type": "all",
		"implemented": true,
		"description": "When this model is destroyed, roll one D6. On a 6, each unit within 6\" suffers mortal wounds."
	},

	# Ork Kommandos — mortal wounds instead of shooting
	"Throat Slittas": {
		"condition": "start_of_shooting",
		"effects": [],
		"target": "enemy_within_9",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Instead of shooting, roll 1D6 per model within 9\" of enemy: 5+ = 1 mortal wound"
	},

	# Ork Kommandos — cannot be targeted by Fire Overwatch
	"Sneaky Surprise": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Enemy units cannot use Fire Overwatch to shoot at this unit"
	},

	# Ork Kommandos — unit splitting at deployment
	"Patrol Squad": {
		"condition": "deployment",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"description": "At deployment, can split into two 5-model units (requires deployment system changes)"
	},

	# Ork Kommandos wargear — once per battle 5+ invuln save
	"Distraction Grot": {
		"condition": "opponent_shooting",
		"effects": [{"type": "grant_invuln", "value": 5}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: 5+ invulnerable save when targeted in opponent's Shooting phase"
	},

	# Ork Kommandos wargear — once per battle mortal wounds after normal move
	"Bomb Squigs": {
		"condition": "after_normal_move",
		"effects": [],
		"target": "enemy_within_12",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: after Normal move, select enemy within 12\" — on 3+, D3 mortal wounds"
	},

	# Custodes Shield-captain On Dawneagle Jetbike — once per battle move at end of fight phase
	"Sweeping Advance": {
		"condition": "end_of_fight_phase",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: at end of Fight phase, if unit fought — Fall Back (if in engagement) or Normal Move (if not)"
	},

	# Damaged Profile — -1 to hit when at low wounds (Battlewagon, Caladius, Telemon)
	# The wound threshold is parsed from the ability name, e.g. "Damaged: 1-5 Wounds Remaining" -> 5
	# Checked directly by RulesEngine.is_damaged_profile_active() rather than using the flag system,
	# since it depends on dynamic wound state that can change mid-phase.
	"Damaged": {
		"condition": "wounds_below_threshold",
		"effects": [{"type": "minus_one_hit"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "-1 to Hit rolls when at low wounds (checked directly in RulesEngine)"
	},

	# Custodes Caladius Grav-tank — conditional Lethal Hits by weapon/target type
	"Advanced Firepower": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Twin iliastus accelerator cannon: Lethal Hits vs non-MONSTER/VEHICLE. Twin arachnus heavy blaze cannon: Lethal Hits vs MONSTER/VEHICLE. Checked directly in RulesEngine."
	},

	# Custodes Shield-Captain — once per battle, both Ka'tah stances active simultaneously
	# Resolved in FightPhase when unit is selected to fight (during Ka'tah stance selection).
	# When activated, sets BOTH effect_sustained_hits AND effect_lethal_hits flags.
	"Master of the Stances": {
		"condition": "on_fight_selection",
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: both Ka'tah stances active simultaneously during this fight"
	},

	# Custodes Shield-Captain — once per battle round, reduce stratagem CP cost by 1
	# Resolved in StratagemManager when a stratagem targets this unit.
	# The CP discount is applied automatically when the Shield-Captain's unit is targeted.
	"Strategic Mastery": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle_round": true,
		"description": "Once per battle round: reduce CP cost of a Stratagem targeting this unit by 1"
	},

	# Custodes Contemptor-Achillus Dreadnought — mortal wounds on fight selection
	# Resolved directly in FightPhase when unit is selected to fight.
	# Roll 1D6 (+2 if charged): on 4-5, target suffers D3 mortal wounds; on 6+, 3 mortal wounds.
	"Dread Foe": {
		"condition": "on_fight_selection",
		"effects": [],
		"target": "enemy_in_engagement",
		"attack_type": "melee",
		"implemented": true,
		"description": "When selected to fight, select one enemy in Engagement Range and roll D6 (+2 if charged): 4-5 = D3 MW, 6+ = 3 MW"
	},

	# Custodes Telemon Heavy Dreadnought — -1 Damage to incoming attacks
	"Guardian Eternal": {
		"condition": "always",
		"effects": [{"type": "minus_damage", "value": 1}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Each time an attack is allocated to this model, subtract 1 from the Damage characteristic of that attack."
	},

	# Space Marines Intercessor Squad — sticky objectives
	# Same mechanic as Ork Boyz "Get Da Good Bitz" — resolved by MissionManager
	"Objective Secured": {
		"condition": "end_of_command",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Sticky objectives — resolved by MissionManager at end of Command phase"
	},

	# Space Marines Intercessor Squad — +2 bolt rifle attacks vs single target
	# When selected to shoot, can choose to add 2 to Attacks of bolt rifles but must
	# target only one enemy unit with all attacks. Requires ShootingPhase integration.
	"Target Elimination": {
		"condition": "on_shooting_selection",
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": false,
		"description": "+2 bolt rifle Attacks when targeting a single enemy unit — requires ShootingPhase prompt"
	},

	# Space Marines Tactical Squad — unit splitting at deployment
	# Same mechanic as Kommandos "Patrol Squad" — requires deployment system changes.
	"Combat Squads": {
		"condition": "deployment",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"description": "At deployment, can split into two 5-model units (requires deployment system changes)"
	},

	# Space Marines Infiltrator Squad — block enemy deep strike within 12"
	# Not a combat effect — enforced during reinforcement placement validation in
	# MovementPhase, DeploymentController, and AIDecisionMaker.
	# Note: This specific aura doesn't use the flag-based effect system since it's
	# a deployment restriction, not a combat modifier. It remains implemented via
	# direct checks in MovementPhase/DeploymentController/AIDecisionMaker.
	"Omni-scramblers": {
		"condition": "aura",
		"effects": [],
		"aura_range": 12.0,
		"aura_target": "enemy",
		"target": "enemy_reserves",
		"attack_type": "all",
		"implemented": true,
		"description": "Enemy units set up from Reserves cannot be set up within 12\" of this unit"
	},

	# ======================================================================
	# PHASE-TRIGGERED ABILITIES
	# These trigger at specific phase boundaries and require active resolution.
	# ======================================================================

	# Ork Painboss — heal friendly BEAST SNAGGA CHARACTER 3 wounds at end of Movement phase
	"Sawbonez": {
		"condition": "end_of_movement",
		"effects": [],
		"target": "friendly_beast_snagga_character",
		"attack_type": "all",
		"implemented": true,
		"description": "At end of Movement phase, select one friendly BEAST SNAGGA CHARACTER within 3\" — regain up to 3 lost wounds"
	},

	# Ork Painboss wargear — once per battle return D3 destroyed Bodyguard models at start of Command phase
	"Grot Orderly": {
		"condition": "start_of_command",
		"effects": [],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: at start of Command phase, if bearer's unit is below Starting Strength, return up to D3 destroyed Bodyguard models"
	},

	# ======================================================================
	# PHASE-TRIGGERED ABILITIES (Movement phase etc.)
	# ======================================================================

	# Ork Weirdboy — teleport unit at end of Movement phase
	# Once per turn, roll D6: on 1, unit suffers D6 mortal wounds;
	# on 2+, remove unit and redeploy 9"+ from enemies.
	# Requires MovementPhase integration for prompt and resolution.
	"Da Jump": {
		"condition": "end_of_movement",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"once_per_turn": true,
		"description": "Once per turn: at end of Movement phase, roll D6: on 1, unit suffers D6 mortal wounds; on 2+, teleport unit 9\"+ from enemies"
	},

	# ======================================================================
	# LEADER ABILITIES — Weapon modifiers based on unit size
	# ======================================================================

	# Ork Weirdboy — 'Eadbanger gains +1 S and +1 D per 5 models in led unit
	# Hazardous at 10+ models. Requires dynamic weapon stat modification
	# based on attached unit model count. Not auto-applied via flag system.
	"Waaagh! Energy": {
		"condition": "while_leading",
		"effects": [],
		"target": "model",
		"attack_type": "ranged",
		"implemented": false,
		"description": "+1 S and +1 D to 'Eadbanger per 5 models in led unit; Hazardous at 10+ models — requires dynamic weapon modification"
	},

	# ======================================================================
	# COMBAT ABILITIES — Weapon stat modifiers based on targeting conditions
	# ======================================================================

	# Ork Flash Gitz — snazzgun Attacks = 4 when targeting closest eligible enemy
	# Handled directly in RulesEngine._resolve_ranged_assignment() and _resolve_assignment():
	# checks if weapon is a snazzgun and target is closest eligible, then overrides attacks to 4.
	"Gun-crazy Show-offs": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Snazzgun Attacks = 4 when targeting closest eligible enemy — checked directly in RulesEngine"
	},

	# ======================================================================
	# WARGEAR ABILITIES — Ammo Runt (OA-10)
	# ======================================================================

	# Ork Nobz / Flash Gitz — once per battle per ammo runt, Lethal Hits on ranged weapons
	# Nobz can have up to 2 ammo runts; Flash Gitz have 1.
	# Triggered when unit is selected to shoot — prompt offered in ShootingPhase.
	# The ammo runt count is stored in ability dict as "count" field (default 1).
	"Ammo Runt": {
		"condition": "on_shooting_selection",
		"effects": [{"type": "grant_lethal_hits"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle per ammo runt: ranged weapons gain [LETHAL HITS] for the phase"
	},

	# ======================================================================
	# TARGET-CONDITIONAL ABILITIES — bonuses based on target keywords
	# These are checked directly in RulesEngine where both attacker and target are known.
	# ======================================================================

	# Ork Tankbustas — +1 Hit and +1 Wound vs MONSTER or VEHICLE (ranged only)
	"Tank Hunters": {
		"condition": "target_has_keyword",
		"target_keywords": ["MONSTER", "VEHICLE"],
		"effects": [{"type": "plus_one_hit"}, {"type": "plus_one_wound"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "+1 to Hit and +1 to Wound when making ranged attacks against MONSTER or VEHICLE units — checked directly in RulesEngine"
	},

	# Ork Lootas — re-roll Hit rolls of 1 on ranged attacks; full Hit re-roll
	# if target is within range of any objective marker.
	# Checked directly in RulesEngine._resolve_assignment_until_wounds() and
	# _resolve_assignment() where both attacker and target + board are available.
	"Dat's Our Loot!": {
		"condition": "target_near_objective",
		"effects": [{"type": "reroll_hits", "scope": "ones"}],
		"effects_on_objective": [{"type": "reroll_hits", "scope": "failed"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll Hit rolls of 1 on ranged attacks. Full Hit re-roll if target is within range of an objective marker — checked directly in RulesEngine"
	},

	# Ork Warbikers / Wartrakks — improve AP by 1 for ranged attacks vs targets within 9"
	"Drive-by Dakka": {
		"condition": "target_within_range",
		"range_inches": 9.0,
		"effects": [{"type": "improve_ap", "value": 1}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Improve AP by 1 for ranged attacks against targets within 9\" — checked directly in RulesEngine save resolution"
	},

	# Ork Nobz — subtract 1 from incoming Wound rolls when attack S > unit T,
	# but only while a Warboss model is leading the unit.
	# Checked directly in RulesEngine wound modifier collection (all 4 paths).
	"Da Boss' Ladz": {
		"condition": "while_warboss_leading",
		"effects": [{"type": "minus_one_wound_incoming", "requirement": "strength_gt_toughness"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While a Warboss leads this unit, subtract 1 from incoming Wound rolls when attack S > unit T — checked directly in RulesEngine"
	},

	# ======================================================================
	# CONDITIONAL ABILITIES (Waaagh!-dependent etc.)
	# These are tracked but not auto-applied; they require game state conditions.
	# ======================================================================

	# Ork Warboss — +4 attacks while Waaagh! active
	# Handled directly in RulesEngine._resolve_melee_assignment() when waaagh_active flag is set
	"Da Biggest and da Best": {
		"condition": "waaagh_active",
		"effects": [],
		"target": "model",
		"attack_type": "melee",
		"implemented": true,
		"description": "+4 melee Attacks while Waaagh! active — applied in RulesEngine melee resolution"
	},

	# Ork Warboss in Mega Armour — weapon damage 3 while Waaagh! active
	# Handled directly in RulesEngine._resolve_melee_assignment() when waaagh_active flag is set
	"Dead Brutal": {
		"condition": "waaagh_active",
		"effects": [],
		"target": "model",
		"attack_type": "melee",
		"implemented": true,
		"description": "Weapon damage = 3 while Waaagh! active — applied in RulesEngine melee resolution"
	},

	# ======================================================================
	# FREEBOOTER KREW ENHANCEMENT ABILITIES (OA-2)
	# These are checked via unit.meta.enhancements[] rather than abilities[].
	# ======================================================================

	# Git-spotter Squig — bearer's unit ranged weapons gain [IGNORES COVER]
	"Git-spotter Squig": {
		"condition": "enhancement",
		"effects": [{"type": "grant_ignores_cover"}],
		"target": "bearer_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Bearer's unit ranged weapons have [IGNORES COVER]"
	},

	# Bionik Workshop — +1 to melee Hit rolls (when d3 roll = 3)
	# The actual bonus type is determined at battle start by FactionAbilityManager.
	# The "hit" variant uses this effect entry; "move" and "strength" are handled
	# via flags checked directly in MovementPhase and RulesEngine respectively.
	"Bionik Workshop — Hit Bonus": {
		"condition": "enhancement_flag",
		"effects": [{"type": "plus_one_hit"}],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls (Bionik Workshop d3 = 3)"
	},
}

# ============================================================================
# STATE
# ============================================================================

# Active ability effects currently applied to units
# Each entry: { "ability_name": String, "source_unit_id": String (leader),
#               "target_unit_id": String, "effects": Array,
#               "attack_type": String, "condition": String }
var _active_ability_effects: Array = []

# Track which units have had ability flags applied this phase
# { unit_id: [ability_name1, ability_name2, ...] }
var _applied_this_phase: Dictionary = {}

# Track aura effects currently applied to units
# Key: "target_unit_id:ability_name", Value: source_unit_id
# Used to prevent the same aura ability from stacking from multiple sources (10th Ed rule)
var _active_aura_effects: Dictionary = {}

# Track once-per-battle ability usage
# Key: "unit_id:ability_name", Value: true (used)
var _once_per_battle_used: Dictionary = {}

# Track once-per-battle-round ability usage (e.g., Strategic Mastery)
# Key: "player:ability_name", Value: battle_round_number (last used round)
var _once_per_round_used: Dictionary = {}

func _ready() -> void:
	var implemented_count = 0
	for ability_name in ABILITY_EFFECTS:
		if ABILITY_EFFECTS[ability_name].get("implemented", false):
			implemented_count += 1
	print("UnitAbilityManager: Ready — %d ability definitions (%d implemented)" % [ABILITY_EFFECTS.size(), implemented_count])

# ============================================================================
# PHASE LIFECYCLE
# ============================================================================

func on_phase_start(phase: int) -> void:
	"""Called at the start of each phase. Applies ability effects for combat phases."""
	# Apply ability effects at start of combat-relevant phases
	if _is_combat_phase(phase):
		_apply_all_ability_effects(phase)
		var phase_name = _phase_to_string(phase)
		print("UnitAbilityManager: Applied ability effects for %s phase (%d active effects)" % [phase_name, _active_ability_effects.size()])

func on_phase_end(phase: int) -> void:
	"""Called at the end of each phase. Clears ability-applied effect flags."""
	if _is_combat_phase(phase) or _applied_this_phase.size() > 0:
		_clear_all_ability_effects()
		var phase_name = _phase_to_string(phase)
		print("UnitAbilityManager: Cleared ability effects at end of %s phase" % phase_name)

func on_movement_phase_start() -> void:
	"""Called at movement phase start. Applies eligibility abilities (fall_back_and_charge, etc.)."""
	_apply_eligibility_effects()
	print("UnitAbilityManager: Applied eligibility effects for Movement phase")

func on_movement_phase_end() -> void:
	"""Called at movement phase end. Clears eligibility flags."""
	_clear_all_ability_effects()

# ============================================================================
# CORE: APPLY ABILITY EFFECTS
# ============================================================================

func _apply_all_ability_effects(phase: int) -> void:
	"""Scan all units and apply relevant ability effects as flags."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()
	_active_aura_effects.clear()

	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]

		# Skip destroyed units
		if not _has_alive_models(unit):
			continue

		# 1. Check for leader abilities on attached characters
		_apply_leader_abilities(unit_id, unit, phase)

		# 2. Check for always-on unit abilities
		_apply_unit_abilities(unit_id, unit, phase)

	# 3. Check for enhancement abilities (OA-2: Git-spotter Squig, Bionik Workshop)
	_apply_enhancement_abilities(phase)

	# 4. Check for aura abilities (after all units have been scanned,
	#    since auras affect OTHER units within range)
	_apply_aura_abilities(phase)

func _apply_leader_abilities(bodyguard_unit_id: String, bodyguard_unit: Dictionary, phase: int) -> void:
	"""Check if this unit has attached leaders with combat-affecting abilities."""
	var attachment_data = bodyguard_unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	if attached_characters.is_empty():
		return

	var units = GameState.state.get("units", {})

	for char_id in attached_characters:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Character must have alive models
		if not _has_alive_models(char_unit):
			continue

		# Scan the character's abilities
		var abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var ability_name = ""
			if ability is String:
				ability_name = ability
			elif ability is Dictionary:
				ability_name = ability.get("name", "")

			if ability_name == "" or ability_name == "Core":
				continue

			# Look up in our effects table
			var effect_def = ABILITY_EFFECTS.get(ability_name, {})
			if effect_def.is_empty():
				continue
			if not effect_def.get("implemented", false):
				continue
			if effect_def.get("condition", "") != "while_leading":
				continue
			if effect_def.get("target", "") != "led_unit":
				continue

			# Check if this ability is relevant to the current phase
			if not _is_relevant_for_phase(effect_def, phase):
				continue

			# Check once-per-battle restriction
			if effect_def.get("once_per_battle", false):
				var usage_key = bodyguard_unit_id + ":" + ability_name
				if _once_per_battle_used.get(usage_key, false):
					print("UnitAbilityManager: '%s' already used this battle for unit %s — skipping" % [ability_name, bodyguard_unit_id])
					continue

			# Apply the effects to the bodyguard unit
			var effects = effect_def.get("effects", [])
			if effects.is_empty():
				continue

			var diffs = EffectPrimitivesData.apply_effects(effects, bodyguard_unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)

				# Track the active effect
				_active_ability_effects.append({
					"ability_name": ability_name,
					"source_unit_id": char_id,
					"target_unit_id": bodyguard_unit_id,
					"effects": effects,
					"attack_type": effect_def.get("attack_type", "all"),
					"condition": "while_leading"
				})

				# Track for phase cleanup
				if not _applied_this_phase.has(bodyguard_unit_id):
					_applied_this_phase[bodyguard_unit_id] = []
				_applied_this_phase[bodyguard_unit_id].append(ability_name)

				var char_name = char_unit.get("meta", {}).get("name", char_id)
				var bg_name = bodyguard_unit.get("meta", {}).get("name", bodyguard_unit_id)
				var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
				print("UnitAbilityManager: %s (%s) grants '%s' to %s — flags: %s" % [
					char_name, char_id, ability_name, bg_name, str(flag_names)
				])

				# Log ability activation to GameEventLog
				var game_event_log = get_node_or_null("/root/GameEventLog")
				if game_event_log:
					var owner = int(bodyguard_unit.get("owner", 0))
					var desc = effect_def.get("description", ability_name)
					game_event_log.add_player_entry(owner,
						"%s ability '%s' active on %s (%s)" % [char_name, ability_name, bg_name, desc])

func _apply_unit_abilities(unit_id: String, unit: Dictionary, phase: int) -> void:
	"""Check if this unit has always-on abilities that affect combat."""
	var abilities = unit.get("meta", {}).get("abilities", [])

	for ability in abilities:
		var ability_name = ""
		if ability is String:
			ability_name = ability
		elif ability is Dictionary:
			ability_name = ability.get("name", "")

		if ability_name == "" or ability_name == "Core":
			continue

		# Look up in our effects table
		var effect_def = ABILITY_EFFECTS.get(ability_name, {})
		if effect_def.is_empty():
			continue
		if not effect_def.get("implemented", false):
			continue

		# Only handle "always" condition here (leader abilities handled separately)
		var condition = effect_def.get("condition", "")
		if condition != "always":
			continue

		# Target must be "unit" (self)
		if effect_def.get("target", "") != "unit":
			continue

		# Check if relevant for this phase
		if not _is_relevant_for_phase(effect_def, phase):
			continue

		# Don't double-apply if already applied this phase
		if _applied_this_phase.has(unit_id) and ability_name in _applied_this_phase[unit_id]:
			continue

		var effects = effect_def.get("effects", [])
		if effects.is_empty():
			continue

		var diffs = EffectPrimitivesData.apply_effects(effects, unit_id)
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

			_active_ability_effects.append({
				"ability_name": ability_name,
				"source_unit_id": unit_id,
				"target_unit_id": unit_id,
				"effects": effects,
				"attack_type": effect_def.get("attack_type", "all"),
				"condition": "always"
			})

			if not _applied_this_phase.has(unit_id):
				_applied_this_phase[unit_id] = []
			_applied_this_phase[unit_id].append(ability_name)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
			print("UnitAbilityManager: %s (%s) has ability '%s' — flags: %s" % [
				unit_name, unit_id, ability_name, str(flag_names)
			])

			# Log ability activation to GameEventLog
			var game_event_log = get_node_or_null("/root/GameEventLog")
			if game_event_log:
				var owner = int(unit.get("owner", 0))
				var desc = effect_def.get("description", ability_name)
				game_event_log.add_player_entry(owner,
					"%s ability '%s' active (%s)" % [unit_name, ability_name, desc])

# ============================================================================
# ENHANCEMENT ABILITIES (OA-2)
# ============================================================================
# Enhancement abilities are stored in unit.meta.enhancements[] (not abilities[]).
# They apply effects to the bearer's unit (the combined unit if character is attached).

func _apply_enhancement_abilities(phase: int) -> void:
	"""Scan all units for enhancement abilities and apply effects."""
	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if not _has_alive_models(unit):
			continue

		var enhancements = unit.get("meta", {}).get("enhancements", [])
		if enhancements.is_empty():
			continue

		for enhancement_name in enhancements:
			if enhancement_name == "":
				continue

			var effect_def = ABILITY_EFFECTS.get(enhancement_name, {})
			if effect_def.is_empty():
				continue
			if not effect_def.get("implemented", false):
				continue

			var condition = effect_def.get("condition", "")
			if condition != "enhancement":
				continue

			# Determine the target unit (bearer's unit = combined unit)
			var target_unit_id = unit_id
			if effect_def.get("target", "") == "bearer_unit":
				# Find the bodyguard unit the bearer is attached to
				target_unit_id = _get_combined_unit_for_enhancement(unit_id)

			# Don't double-apply
			if _applied_this_phase.has(target_unit_id) and enhancement_name in _applied_this_phase[target_unit_id]:
				continue

			# Check if relevant for this phase
			if not _is_relevant_for_phase(effect_def, phase):
				continue

			var effects = effect_def.get("effects", [])
			if effects.is_empty():
				continue

			var diffs = EffectPrimitivesData.apply_effects(effects, target_unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)

				_active_ability_effects.append({
					"ability_name": enhancement_name,
					"source_unit_id": unit_id,
					"target_unit_id": target_unit_id,
					"effects": effects,
					"attack_type": effect_def.get("attack_type", "all"),
					"condition": "enhancement"
				})

				if not _applied_this_phase.has(target_unit_id):
					_applied_this_phase[target_unit_id] = []
				_applied_this_phase[target_unit_id].append(enhancement_name)

				var bearer_name = unit.get("meta", {}).get("name", unit_id)
				var target_name = units.get(target_unit_id, {}).get("meta", {}).get("name", target_unit_id)
				var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
				print("UnitAbilityManager: Enhancement '%s' (bearer: %s) applied to %s — flags: %s" % [
					enhancement_name, bearer_name, target_name, str(flag_names)])

	# Also apply Bionik Workshop "hit" bonus if the flag is set on any unit
	for unit_id in units:
		var unit = units[unit_id]
		if not _has_alive_models(unit):
			continue
		var bionik_bonus = unit.get("flags", {}).get("bionik_workshop_bonus", "")
		if bionik_bonus == "hit":
			# Apply +1 to melee hit rolls for this unit
			if _applied_this_phase.has(unit_id) and "Bionik Workshop — Hit Bonus" in _applied_this_phase[unit_id]:
				continue
			if not _is_relevant_for_phase(ABILITY_EFFECTS["Bionik Workshop — Hit Bonus"], phase):
				continue
			var effects = ABILITY_EFFECTS["Bionik Workshop — Hit Bonus"]["effects"]
			var diffs = EffectPrimitivesData.apply_effects(effects, unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)
				_active_ability_effects.append({
					"ability_name": "Bionik Workshop — Hit Bonus",
					"source_unit_id": unit_id,
					"target_unit_id": unit_id,
					"effects": effects,
					"attack_type": "melee",
					"condition": "enhancement_flag"
				})
				if not _applied_this_phase.has(unit_id):
					_applied_this_phase[unit_id] = []
				_applied_this_phase[unit_id].append("Bionik Workshop — Hit Bonus")
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("UnitAbilityManager: Bionik Workshop +1 melee Hit applied to %s" % unit_name)

func _get_combined_unit_for_enhancement(char_unit_id: String) -> String:
	"""Get the bodyguard unit this character is attached to, or the char_unit_id if standalone."""
	var units = GameState.state.get("units", {})
	for uid in units:
		var unit = units[uid]
		var attached = unit.get("attachment_data", {}).get("attached_characters", [])
		if char_unit_id in attached:
			return uid
	return char_unit_id

# ============================================================================
# AURA ABILITIES
# ============================================================================
# Aura abilities affect other units within a specified range.
# Per 10th Edition rules:
# - A model with an Aura ability is always within range of its own Aura
# - If a unit is within range of the same Aura ability from multiple sources,
#   the aura only applies once (no stacking)
# - Aura effects are checked at phase start and cleared at phase end

func _apply_aura_abilities(phase: int) -> void:
	"""Scan all units for aura abilities and apply effects to nearby units."""
	var units = GameState.state.get("units", {})
	var aura_count = 0

	for source_unit_id in units:
		var source_unit = units[source_unit_id]

		# Skip destroyed units
		if not _has_alive_models(source_unit):
			continue

		# Collect aura abilities from this unit AND its attached characters
		var aura_sources = _collect_aura_sources(source_unit_id, source_unit, units)

		for aura_source in aura_sources:
			var ability_name = aura_source.ability_name
			var effect_def = aura_source.effect_def
			var aura_owner_unit_id = aura_source.source_unit_id  # The unit with the aura ability
			var aura_position_unit = aura_source.position_unit   # Unit used for range measurement

			# Must have effects to apply (some auras like Omni-scramblers
			# are enforced via separate systems and have empty effects)
			var effects = effect_def.get("effects", [])
			if effects.is_empty():
				continue

			# Check if relevant for this phase
			if not _is_relevant_for_phase(effect_def, phase):
				continue

			var aura_range = effect_def.get("aura_range", 6.0)
			var aura_target = effect_def.get("aura_target", "friendly")
			var source_owner = source_unit.get("owner", 0)

			# Find units within aura range (measured from the position unit)
			var nearby_units = _find_units_in_aura_range(aura_owner_unit_id, aura_position_unit, aura_range, aura_target, source_owner, units)

			# Apply aura effects to the source unit itself if applicable
			# (Per 10th Ed: a model is always within range of its own Aura)
			# For attached characters, "self" means the combined unit they're part of
			if _should_apply_aura_to_self(aura_target, source_owner, source_unit):
				var self_key = source_unit_id + ":" + ability_name
				if not _active_aura_effects.has(self_key):
					_apply_aura_to_unit(source_unit_id, source_unit, ability_name, aura_owner_unit_id, effects, effect_def, phase)
					aura_count += 1

			# Apply to nearby units
			for target_info in nearby_units:
				var target_unit_id = target_info.unit_id
				var aura_key = target_unit_id + ":" + ability_name

				# Check stacking — same aura from multiple sources doesn't stack
				if _active_aura_effects.has(aura_key):
					continue

				var target_unit = units.get(target_unit_id, {})
				_apply_aura_to_unit(target_unit_id, target_unit, ability_name, aura_owner_unit_id, effects, effect_def, phase)
				aura_count += 1

	if aura_count > 0:
		print("UnitAbilityManager: Applied %d aura effects this phase" % aura_count)

func _collect_aura_sources(unit_id: String, unit: Dictionary, all_units: Dictionary) -> Array:
	"""Collect all aura abilities from a unit and its attached characters.
	Returns array of { ability_name, effect_def, source_unit_id, position_unit }.
	For attached characters, the position_unit is the bodyguard unit (since the
	character is physically part of that unit on the table)."""
	var sources: Array = []

	# Check this unit's own abilities
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "" or ability_name == "Core":
			continue

		var effect_def = ABILITY_EFFECTS.get(ability_name, {})
		if effect_def.is_empty():
			continue
		if not effect_def.get("implemented", false):
			continue
		if effect_def.get("condition", "") != "aura":
			continue

		sources.append({
			"ability_name": ability_name,
			"effect_def": effect_def,
			"source_unit_id": unit_id,
			"position_unit": unit  # Range measured from this unit's models
		})

	# Check attached characters for aura abilities
	var attachment_data = unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	for char_id in attached_characters:
		var char_unit = all_units.get(char_id, {})
		if char_unit.is_empty() or not _has_alive_models(char_unit):
			continue

		var char_abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in char_abilities:
			var ability_name = _get_ability_name(ability)
			if ability_name == "" or ability_name == "Core":
				continue

			var effect_def = ABILITY_EFFECTS.get(ability_name, {})
			if effect_def.is_empty():
				continue
			if not effect_def.get("implemented", false):
				continue
			if effect_def.get("condition", "") != "aura":
				continue

			# For an attached character, measure range from the bodyguard unit
			# (the character is physically part of that unit on the table)
			sources.append({
				"ability_name": ability_name,
				"effect_def": effect_def,
				"source_unit_id": char_id,
				"position_unit": unit  # Range measured from bodyguard unit
			})

	return sources

func _find_units_in_aura_range(source_unit_id: String, source_unit: Dictionary,
		aura_range: float, aura_target: String, source_owner: int,
		all_units: Dictionary) -> Array:
	"""Find all eligible units within aura range of the source unit.
	Returns array of { unit_id: String, distance: float }."""
	var results: Array = []

	for other_id in all_units:
		if other_id == source_unit_id:
			continue

		var other_unit = all_units[other_id]

		# Skip destroyed units
		if not _has_alive_models(other_unit):
			continue

		# Skip embarked units (they are inside transports, not on the board)
		if other_unit.get("embarked_in", "") != "":
			continue

		# Check ownership filter
		var other_owner = other_unit.get("owner", 0)
		if aura_target == "friendly" and other_owner != source_owner:
			continue
		if aura_target == "enemy" and other_owner == source_owner:
			continue
		# "all" applies to both friendly and enemy

		# Calculate closest model-to-model distance (edge-to-edge)
		var min_dist = _closest_model_distance(source_unit, other_unit)
		if min_dist <= aura_range:
			results.append({ "unit_id": other_id, "distance": min_dist })

	return results

func _should_apply_aura_to_self(aura_target: String, source_owner: int, source_unit: Dictionary) -> bool:
	"""Check if the aura should apply to its own source unit.
	Per 10th Ed rules, a model is always within range of its own Aura ability."""
	# Auras targeting "friendly" or "all" apply to the source unit itself
	if aura_target == "friendly" or aura_target == "all":
		return true
	# Enemy auras don't apply to the source unit
	return false

func _apply_aura_to_unit(target_unit_id: String, target_unit: Dictionary,
		ability_name: String, source_unit_id: String,
		effects: Array, effect_def: Dictionary, _phase: int) -> void:
	"""Apply aura effects to a single target unit."""
	var diffs = EffectPrimitivesData.apply_effects(effects, target_unit_id)
	if diffs.is_empty():
		return

	PhaseManager.apply_state_changes(diffs)

	# Track the aura effect (for anti-stacking and cleanup)
	var aura_key = target_unit_id + ":" + ability_name
	_active_aura_effects[aura_key] = source_unit_id

	# Track as active ability effect (for phase cleanup)
	_active_ability_effects.append({
		"ability_name": ability_name,
		"source_unit_id": source_unit_id,
		"target_unit_id": target_unit_id,
		"effects": effects,
		"attack_type": effect_def.get("attack_type", "all"),
		"condition": "aura"
	})

	if not _applied_this_phase.has(target_unit_id):
		_applied_this_phase[target_unit_id] = []
	_applied_this_phase[target_unit_id].append(ability_name)

	var source_name = GameState.state.get("units", {}).get(source_unit_id, {}).get("meta", {}).get("name", source_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
	print("UnitAbilityManager: Aura '%s' from %s (%s) applied to %s (%s) — flags: %s" % [
		ability_name, source_name, source_unit_id, target_name, target_unit_id, str(flag_names)
	])

	# Log ability activation to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(target_unit.get("owner", 0))
		var desc = effect_def.get("description", ability_name)
		game_event_log.add_player_entry(owner,
			"Aura '%s' from %s active on %s (%s)" % [ability_name, source_name, target_name, desc])

func _closest_model_distance(unit_a: Dictionary, unit_b: Dictionary) -> float:
	"""Calculate the closest edge-to-edge distance in inches between any alive
	model in unit_a and any alive model in unit_b.
	Uses Measurement.model_to_model_distance_inches() for shape-aware calculation."""
	var min_dist = INF
	var models_a = unit_a.get("models", [])
	var models_b = unit_b.get("models", [])

	for model_a in models_a:
		if not model_a.get("alive", true):
			continue
		if model_a.get("position", null) == null:
			continue

		for model_b in models_b:
			if not model_b.get("alive", true):
				continue
			if model_b.get("position", null) == null:
				continue

			var dist = Measurement.model_to_model_distance_inches(model_a, model_b)
			min_dist = min(min_dist, dist)

	return min_dist

# ============================================================================
# AURA QUERY HELPERS
# ============================================================================

func get_aura_abilities_on_unit(unit_id: String) -> Array:
	"""Get all aura effects currently active on a unit.
	Returns array of { ability_name, source_unit_id }."""
	var results = []
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id and effect.get("condition", "") == "aura":
			results.append({
				"ability_name": effect.get("ability_name", ""),
				"source_unit_id": effect.get("source_unit_id", "")
			})
	return results

func is_unit_in_aura(unit_id: String, ability_name: String) -> bool:
	"""Check if a unit is currently under a specific aura effect."""
	var aura_key = unit_id + ":" + ability_name
	return _active_aura_effects.has(aura_key)

func find_friendly_units_within_aura(source_unit_id: String, aura_range: float) -> Array:
	"""Public helper: Find all friendly units within aura range of the source unit.
	Returns array of unit_id strings. Used by external systems that need aura-style
	range checking (e.g., for abilities resolved outside the flag system)."""
	var units = GameState.state.get("units", {})
	var source_unit = units.get(source_unit_id, {})
	if source_unit.is_empty():
		return []

	var source_owner = source_unit.get("owner", 0)
	var results: Array = []

	for other_id in units:
		if other_id == source_unit_id:
			continue
		var other_unit = units.get(other_id, {})
		if not _has_alive_models(other_unit):
			continue
		if other_unit.get("owner", 0) != source_owner:
			continue
		if other_unit.get("embarked_in", "") != "":
			continue

		var dist = _closest_model_distance(source_unit, other_unit)
		if dist <= aura_range:
			results.append(other_id)

	return results

func find_enemy_units_within_aura(source_unit_id: String, aura_range: float) -> Array:
	"""Public helper: Find all enemy units within aura range of the source unit.
	Returns array of unit_id strings."""
	var units = GameState.state.get("units", {})
	var source_unit = units.get(source_unit_id, {})
	if source_unit.is_empty():
		return []

	var source_owner = source_unit.get("owner", 0)
	var results: Array = []

	for other_id in units:
		if other_id == source_unit_id:
			continue
		var other_unit = units.get(other_id, {})
		if not _has_alive_models(other_unit):
			continue
		if other_unit.get("owner", 0) == source_owner:
			continue
		if other_unit.get("embarked_in", "") != "":
			continue

		var dist = _closest_model_distance(source_unit, other_unit)
		if dist <= aura_range:
			results.append(other_id)

	return results

func _apply_eligibility_effects() -> void:
	"""Apply eligibility abilities (fall_back_and_charge, advance_and_charge, etc.)
	   at the start of the Movement phase so they're available during movement decisions."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()

	var units = GameState.state.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if not _has_alive_models(unit):
			continue

		# Check leader abilities for eligibility effects
		var attachment_data = unit.get("attachment_data", {})
		var attached_characters = attachment_data.get("attached_characters", [])

		for char_id in attached_characters:
			var char_unit = units.get(char_id, {})
			if char_unit.is_empty() or not _has_alive_models(char_unit):
				continue

			var abilities = char_unit.get("meta", {}).get("abilities", [])
			for ability in abilities:
				var ability_name = _get_ability_name(ability)
				if ability_name == "":
					continue

				var effect_def = ABILITY_EFFECTS.get(ability_name, {})
				if effect_def.is_empty() or not effect_def.get("implemented", false):
					continue
				if effect_def.get("condition", "") != "while_leading":
					continue

				# Check once-per-battle restriction
				if effect_def.get("once_per_battle", false):
					var usage_key = unit_id + ":" + ability_name
					if _once_per_battle_used.get(usage_key, false):
						print("UnitAbilityManager: '%s' already used this battle for unit %s — skipping" % [ability_name, unit_id])
						continue

				# Only apply eligibility effects (fall_back_and_*, advance_and_*)
				var effects = effect_def.get("effects", [])
				var eligibility_effects = []
				for effect in effects:
					var etype = effect.get("type", "")
					if etype in [
						EffectPrimitivesData.FALL_BACK_AND_SHOOT,
						EffectPrimitivesData.FALL_BACK_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_SHOOT
					]:
						eligibility_effects.append(effect)

				if eligibility_effects.is_empty():
					continue

				var diffs = EffectPrimitivesData.apply_effects(eligibility_effects, unit_id)
				if not diffs.is_empty():
					PhaseManager.apply_state_changes(diffs)
					_active_ability_effects.append({
						"ability_name": ability_name,
						"source_unit_id": char_id,
						"target_unit_id": unit_id,
						"effects": eligibility_effects,
						"attack_type": "all",
						"condition": "while_leading"
					})
					if not _applied_this_phase.has(unit_id):
						_applied_this_phase[unit_id] = []
					_applied_this_phase[unit_id].append(ability_name)

					var char_name = char_unit.get("meta", {}).get("name", char_id)
					var bg_name = unit.get("meta", {}).get("name", unit_id)
					print("UnitAbilityManager: %s grants eligibility '%s' to %s" % [char_name, ability_name, bg_name])

# ============================================================================
# CLEAR ABILITY EFFECTS
# ============================================================================

func _clear_all_ability_effects() -> void:
	"""Clear all ability-applied effect flags from units."""
	var units = GameState.state.get("units", {})

	for effect_entry in _active_ability_effects:
		var target_unit_id = effect_entry.get("target_unit_id", "")
		var effects = effect_entry.get("effects", [])
		var unit = units.get(target_unit_id, {})
		if unit.is_empty():
			continue

		var flags = unit.get("flags", {})
		EffectPrimitivesData.clear_effects(effects, target_unit_id, flags)

	_active_ability_effects.clear()
	_applied_this_phase.clear()
	_active_aura_effects.clear()

# ============================================================================
# QUERY HELPERS
# ============================================================================

func get_active_ability_effects_for_unit(unit_id: String) -> Array:
	"""Get all active ability effects on a unit. Useful for UI display."""
	var results = []
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id:
			results.append(effect)
	return results

func unit_has_active_ability(unit_id: String, ability_name: String) -> bool:
	"""Check if a unit currently has a specific ability effect active."""
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id and effect.get("ability_name", "") == ability_name:
			return true
	return false

func get_ability_effect_definition(ability_name: String) -> Dictionary:
	"""Get the effect definition for an ability name. Returns empty dict if not found."""
	return ABILITY_EFFECTS.get(ability_name, {})

func is_ability_implemented(ability_name: String) -> bool:
	"""Check if an ability has a mechanical implementation."""
	var def_data = ABILITY_EFFECTS.get(ability_name, {})
	return def_data.get("implemented", false)

func mark_once_per_battle_used(unit_id: String, ability_name: String) -> void:
	"""Mark a once-per-battle ability as used for a specific unit."""
	var usage_key = unit_id + ":" + ability_name
	_once_per_battle_used[usage_key] = true
	print("UnitAbilityManager: Marked '%s' as used for unit %s (once per battle)" % [ability_name, unit_id])

func is_once_per_battle_used(unit_id: String, ability_name: String) -> bool:
	"""Check if a once-per-battle ability has been used for a specific unit."""
	var usage_key = unit_id + ":" + ability_name
	return _once_per_battle_used.get(usage_key, false)

func mark_once_per_round_used(player: int, ability_name: String) -> void:
	"""Mark a once-per-battle-round ability as used for this round."""
	var usage_key = str(player) + ":" + ability_name
	var current_round = GameState.get_battle_round()
	_once_per_round_used[usage_key] = current_round
	print("UnitAbilityManager: Marked '%s' as used for player %d in round %d (once per round)" % [ability_name, player, current_round])

func is_once_per_round_used(player: int, ability_name: String) -> bool:
	"""Check if a once-per-battle-round ability has been used this round."""
	var usage_key = str(player) + ":" + ability_name
	var last_used_round = _once_per_round_used.get(usage_key, 0)
	var current_round = GameState.get_battle_round()
	return last_used_round >= current_round

func has_shoot_again_ability(unit_id: String) -> bool:
	"""Check if a unit has an unused once-per-battle shoot-again ability (e.g. Sentinel Storm).
	Used by ShootingPhase to offer the shoot-again option after a unit completes shooting."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Sentinel Storm":
			if not is_once_per_battle_used(unit_id, "Sentinel Storm"):
				print("UnitAbilityManager: Unit %s has unused Sentinel Storm — shoot-again available" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Sentinel Storm but already used this battle" % unit_id)
	return false

func has_sanctified_flames_ability(unit_id: String) -> bool:
	"""Check if a unit has the Sanctified Flames ability (e.g. Witchseekers).
	Used by ShootingPhase to trigger a forced Battle-shock test after shooting."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Sanctified Flames":
			print("UnitAbilityManager: Unit %s has Sanctified Flames ability" % unit_id)
			return true
	return false

func has_throat_slittas_ability(unit_id: String) -> bool:
	"""Check if a unit has the Throat Slittas ability (e.g. Kommandos).
	Used by ShootingPhase to offer mortal wounds instead of shooting."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Throat Slittas":
			print("UnitAbilityManager: Unit %s has Throat Slittas ability" % unit_id)
			return true
	return false

func has_dread_foe(unit_id: String) -> bool:
	"""Check if a unit has the Dread Foe ability (e.g. Contemptor-Achillus Dreadnought).
	Used by FightPhase to trigger mortal wounds on fight selection."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Dread Foe":
			print("UnitAbilityManager: Unit %s has Dread Foe ability" % unit_id)
			return true
	return false

func has_master_of_the_stances(unit_id: String) -> bool:
	"""Check if a unit has an unused Master of the Stances ability (Shield-Captain).
	Used by FightPhase to offer both Ka'tah stances simultaneously.
	Checks attached leaders for the ability (since Shield-Captain is a leader)."""
	# First check the unit itself
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	# Check the unit's own abilities
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Master of the Stances":
			if not is_once_per_battle_used(unit_id, "Master of the Stances"):
				print("UnitAbilityManager: Unit %s has unused Master of the Stances" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Master of the Stances but already used this battle" % unit_id)
				return false

	# Check attached leaders (Shield-Captain leading Custodian Guard)
	var attachment_data = unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])
	var units = GameState.state.get("units", {})

	for char_id in attached_characters:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		if not _has_alive_models(char_unit):
			continue

		var char_abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in char_abilities:
			var ability_name = _get_ability_name(ability)
			if ability_name == "Master of the Stances":
				# Use the bodyguard unit's ID for tracking (since it's the unit fighting)
				if not is_once_per_battle_used(unit_id, "Master of the Stances"):
					print("UnitAbilityManager: Unit %s has leader with unused Master of the Stances" % unit_id)
					return true
				else:
					print("UnitAbilityManager: Unit %s has leader with Master of the Stances but already used this battle" % unit_id)
					return false

	return false

func has_strategic_mastery(unit_id: String) -> bool:
	"""Check if a unit or its attached leaders have Strategic Mastery (Shield-Captain).
	Used by StratagemManager to offer CP discount when targeting this unit."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	# Check the unit's own abilities
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Strategic Mastery":
			return true

	# Check attached leaders
	var attachment_data = unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])
	var units = GameState.state.get("units", {})

	for char_id in attached_characters:
		var char_unit = units.get(char_id, {})
		if char_unit.is_empty():
			continue
		if not _has_alive_models(char_unit):
			continue

		var char_abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in char_abilities:
			var ability_name = _get_ability_name(ability)
			if ability_name == "Strategic Mastery":
				return true

	return false

func has_sticky_objectives_ability(unit_id: String) -> bool:
	"""Check if a unit has a sticky objectives ability (e.g. Get Da Good Bitz, Objective Secured).
	Used by MissionManager to apply sticky objective locks at end of Command phase."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name in ["Get Da Good Bitz", "Objective Secured"]:
			return true
	return false

func has_omni_scramblers(unit_id: String) -> bool:
	"""Check if a unit has the Omni-scramblers ability (e.g. Infiltrator Squad).
	Used by reinforcement placement validation to enforce 12\" deep strike denial zone."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Omni-scramblers":
			print("UnitAbilityManager: Unit %s has Omni-scramblers ability" % unit_id)
			return true
	return false

func has_sneaky_surprise(unit_id: String) -> bool:
	"""Check if a unit has the Sneaky Surprise ability (e.g. Kommandos).
	Used by ChargePhase/MovementPhase to block Fire Overwatch against this unit."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Sneaky Surprise":
			print("UnitAbilityManager: Unit %s has Sneaky Surprise — immune to Fire Overwatch" % unit_id)
			return true
	return false

func has_distraction_grot(unit_id: String) -> bool:
	"""Check if a unit has the Distraction Grot wargear ability (e.g. Kommandos).
	Used by ShootingPhase to offer once-per-battle 5+ invuln save when targeted."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Distraction Grot":
			if not is_once_per_battle_used(unit_id, "Distraction Grot"):
				print("UnitAbilityManager: Unit %s has unused Distraction Grot" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Distraction Grot but already used this battle" % unit_id)
	return false

func has_ammo_runt(unit_id: String) -> bool:
	"""OA-10: Check if a unit has at least one unused Ammo Runt wargear ability.
	Used by ShootingPhase to offer Lethal Hits when unit is selected to shoot."""
	return get_ammo_runts_remaining(unit_id) > 0

func get_ammo_runt_count(unit_id: String) -> int:
	"""OA-10: Get the total number of ammo runts a unit has.
	Reads count from ability dict (default 1). Nobz can have up to 2."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return 0

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Ammo Runt":
			# Count stored in ability dict, default 1 (Flash Gitz), can be 2 (Nobz)
			if ability is Dictionary:
				return ability.get("count", 1)
			return 1
	return 0

func get_ammo_runts_remaining(unit_id: String) -> int:
	"""OA-10: Get the number of unused ammo runts for a unit.
	Each runt is tracked independently via 'unit_id:Ammo Runt:N' keys."""
	var total = get_ammo_runt_count(unit_id)
	if total == 0:
		return 0

	var remaining = 0
	for i in range(total):
		var usage_key = unit_id + ":Ammo Runt:" + str(i)
		if not _once_per_battle_used.get(usage_key, false):
			remaining += 1

	print("UnitAbilityManager: Unit %s has %d/%d ammo runts remaining" % [unit_id, remaining, total])
	return remaining

func mark_ammo_runt_used(unit_id: String) -> int:
	"""OA-10: Mark the next unused ammo runt as used for a unit.
	Returns the index of the runt that was marked, or -1 if none available."""
	var total = get_ammo_runt_count(unit_id)
	for i in range(total):
		var usage_key = unit_id + ":Ammo Runt:" + str(i)
		if not _once_per_battle_used.get(usage_key, false):
			_once_per_battle_used[usage_key] = true
			var remaining = get_ammo_runts_remaining(unit_id)
			print("UnitAbilityManager: Marked Ammo Runt #%d as used for unit %s (%d remaining)" % [i, unit_id, remaining])
			return i
	print("UnitAbilityManager: No unused ammo runts for unit %s" % unit_id)
	return -1

func has_bomb_squigs(unit_id: String) -> bool:
	"""Check if a unit has the Bomb Squigs wargear ability (e.g. Kommandos).
	Used by MovementPhase to offer once-per-battle mortal wounds after normal move."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Bomb Squigs":
			if not is_once_per_battle_used(unit_id, "Bomb Squigs"):
				print("UnitAbilityManager: Unit %s has unused Bomb Squigs" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Bomb Squigs but already used this battle" % unit_id)
	return false

func has_sawbonez(unit_id: String) -> bool:
	"""Check if a unit has the Sawbonez ability (Painboss).
	Used by MovementPhase at end of movement to offer healing."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Sawbonez":
			print("UnitAbilityManager: Unit %s has Sawbonez ability" % unit_id)
			return true
	return false

func get_sawbonez_targets(painboss_unit_id: String) -> Array:
	"""Get eligible healing targets for Sawbonez ability.
	Returns array of { unit_id, unit_name, model_id, model_index, wounds_lost } for BEAST SNAGGA CHARACTER
	models within 3\" that have lost wounds."""
	var targets = []
	var painboss_unit = GameState.state.get("units", {}).get(painboss_unit_id, {})
	if painboss_unit.is_empty():
		return targets

	# Get Painboss position (first alive model)
	var painboss_pos = null
	for model in painboss_unit.get("models", []):
		if model.get("alive", true) and model.get("position", null) != null:
			painboss_pos = model.get("position")
			break

	if painboss_pos == null:
		print("UnitAbilityManager: Painboss %s has no position — cannot find Sawbonez targets" % painboss_unit_id)
		return targets

	var units = GameState.state.get("units", {})
	var painboss_owner = painboss_unit.get("owner", 0)

	for unit_id in units:
		var unit = units[unit_id]
		# Must be same owner (friendly)
		if unit.get("owner", 0) != painboss_owner:
			continue

		# Must have BEAST SNAGGA and CHARACTER keywords
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_beast_snagga = false
		var has_character = false
		for kw in keywords:
			if kw.to_upper() == "BEAST SNAGGA":
				has_beast_snagga = true
			if kw.to_upper() == "CHARACTER":
				has_character = true
		if not has_beast_snagga or not has_character:
			continue

		# Check each alive model for lost wounds and proximity
		for i in range(unit.get("models", []).size()):
			var model = unit.get("models", [])[i]
			if not model.get("alive", true):
				continue

			var max_wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", max_wounds)
			if current_wounds >= max_wounds:
				continue  # No wounds lost

			var model_pos = model.get("position", null)
			if model_pos == null:
				continue

			# Check distance (3" = 3 * 25.4mm ~ 76.2mm, but the game uses inches for positions typically)
			# Use the same distance calculation as elsewhere in the codebase
			var dist = _calculate_distance(painboss_pos, model_pos)
			if dist <= 3.0:
				targets.append({
					"unit_id": unit_id,
					"unit_name": unit.get("meta", {}).get("name", unit_id),
					"model_id": model.get("id", "m%d" % (i + 1)),
					"model_index": i,
					"current_wounds": current_wounds,
					"max_wounds": max_wounds,
					"wounds_lost": max_wounds - current_wounds
				})
				print("UnitAbilityManager: Sawbonez target found — %s model %s (%d/%d wounds)" % [
					unit.get("meta", {}).get("name", unit_id), model.get("id", ""), current_wounds, max_wounds])

	return targets

func has_grot_orderly(unit_id: String) -> bool:
	"""Check if a unit has an unused Grot Orderly wargear ability (Painboss).
	Used by CommandPhase at start of command to offer model revival."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Grot Orderly":
			if not is_once_per_battle_used(unit_id, "Grot Orderly"):
				print("UnitAbilityManager: Unit %s has unused Grot Orderly" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Grot Orderly but already used this battle" % unit_id)
	return false

func get_grot_orderly_unit(painboss_unit_id: String) -> Dictionary:
	"""Check if the Painboss's led unit is below starting strength for Grot Orderly.
	Returns { eligible: bool, bodyguard_unit_id, destroyed_count, max_return } or empty dict."""
	var units = GameState.state.get("units", {})

	# Find the bodyguard unit the Painboss is leading
	for unit_id in units:
		var unit = units[unit_id]
		var attachment_data = unit.get("attachment_data", {})
		var attached_characters = attachment_data.get("attached_characters", [])
		if painboss_unit_id in attached_characters:
			# Found the bodyguard unit — check if below starting strength
			var models = unit.get("models", [])
			var alive_count = 0
			var destroyed_count = 0
			for model in models:
				if model.get("alive", true):
					alive_count += 1
				else:
					destroyed_count += 1

			if destroyed_count > 0:
				print("UnitAbilityManager: Grot Orderly — bodyguard unit %s is below starting strength (%d destroyed models)" % [unit_id, destroyed_count])
				return {
					"eligible": true,
					"bodyguard_unit_id": unit_id,
					"bodyguard_unit_name": unit.get("meta", {}).get("name", unit_id),
					"destroyed_count": destroyed_count,
					"alive_count": alive_count,
					"total_models": models.size()
				}
			else:
				print("UnitAbilityManager: Grot Orderly — bodyguard unit %s is at full strength" % unit_id)
				return {"eligible": false}

	print("UnitAbilityManager: Grot Orderly — Painboss %s is not leading any unit" % painboss_unit_id)
	return {"eligible": false}

func _calculate_distance(pos_a, pos_b) -> float:
	"""Calculate distance between two positions (in game inches).
	Handles both Vector2 and Dictionary {x, y} formats."""
	var ax = 0.0
	var ay = 0.0
	var bx = 0.0
	var by = 0.0

	if pos_a is Vector2:
		ax = pos_a.x
		ay = pos_a.y
	elif pos_a is Dictionary:
		ax = float(pos_a.get("x", 0))
		ay = float(pos_a.get("y", 0))

	if pos_b is Vector2:
		bx = pos_b.x
		by = pos_b.y
	elif pos_b is Dictionary:
		bx = float(pos_b.get("x", 0))
		by = float(pos_b.get("y", 0))

	return sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

func has_deadly_demise(unit_id: String) -> bool:
	"""Check if a unit has a Deadly Demise ability (e.g. 'Deadly Demise D6', 'Deadly Demise D3', 'Deadly Demise 1').
	Used by _check_kill_diffs to trigger mortal wounds on destruction."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name.begins_with("Deadly Demise"):
			return true
	return false

func get_deadly_demise_value(unit_id: String) -> String:
	"""Get the Deadly Demise damage value string (e.g. 'D6', 'D3', '1').
	Returns empty string if the unit has no Deadly Demise ability."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return ""

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name.begins_with("Deadly Demise"):
			# Extract the value from e.g. "Deadly Demise D6" -> "D6"
			var parts = ability_name.split(" ")
			if parts.size() >= 3:
				return parts[2]  # "D6", "D3", "1", etc.
			return "D3"  # Default if no value specified
	return ""

func get_implemented_abilities() -> Array:
	"""Get all ability names that are mechanically implemented."""
	var result = []
	for ability_name in ABILITY_EFFECTS:
		if ABILITY_EFFECTS[ability_name].get("implemented", false):
			result.append(ability_name)
	return result

func get_unit_ability_summary(unit_id: String) -> Array:
	"""Get a summary of all abilities on a unit and their implementation status.
	Returns array of { name, type, implemented, active }."""
	var summary = []
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return summary

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "" or ability_name == "Core":
			continue

		var ability_type = ""
		if ability is Dictionary:
			ability_type = ability.get("type", "")

		var effect_def = ABILITY_EFFECTS.get(ability_name, {})
		summary.append({
			"name": ability_name,
			"type": ability_type,
			"implemented": effect_def.get("implemented", false),
			"active": unit_has_active_ability(unit_id, ability_name),
			"has_definition": not effect_def.is_empty()
		})

	return summary

func get_leader_abilities_for_unit(unit_id: String) -> Array:
	"""Get leader abilities that are currently active on a unit from attached characters.
	Returns array of { ability_name, source_character_id, attack_type, effects }."""
	var results = []
	for effect in _active_ability_effects:
		if effect.get("target_unit_id", "") == unit_id and effect.get("condition", "") == "while_leading":
			results.append({
				"ability_name": effect.get("ability_name", ""),
				"source_character_id": effect.get("source_unit_id", ""),
				"attack_type": effect.get("attack_type", "all"),
				"effects": effect.get("effects", [])
			})
	return results

# ============================================================================
# STATIC QUERY — Check abilities on units without needing phase flags
# ============================================================================
# These methods check meta.abilities directly for cases where RulesEngine needs
# to know about abilities outside of the flag system.

static func unit_has_leader_ability(bodyguard_unit: Dictionary, ability_name: String, all_units: Dictionary) -> bool:
	"""Check if a bodyguard unit has a leader granting a specific ability.
	Works without requiring phase flag application."""
	var attachment_data = bodyguard_unit.get("attachment_data", {})
	var attached_characters = attachment_data.get("attached_characters", [])

	for char_id in attached_characters:
		var char_unit = all_units.get(char_id, {})
		if char_unit.is_empty():
			continue

		# Character must be alive
		var has_alive = false
		for model in char_unit.get("models", []):
			if model.get("alive", true):
				has_alive = true
				break
		if not has_alive:
			continue

		var abilities = char_unit.get("meta", {}).get("abilities", [])
		for ability in abilities:
			var name = ""
			if ability is String:
				name = ability
			elif ability is Dictionary:
				name = ability.get("name", "")
			if name == ability_name:
				return true

	return false

static func get_ability_attack_type(ability_name: String) -> String:
	"""Get the attack_type restriction for an ability (melee/ranged/all)."""
	var def_data = ABILITY_EFFECTS.get(ability_name, {})
	return def_data.get("attack_type", "all")

# ============================================================================
# HELPERS
# ============================================================================

func _has_alive_models(unit: Dictionary) -> bool:
	"""Check if a unit has at least one alive model."""
	for model in unit.get("models", []):
		if model.get("alive", true):
			return true
	return false

func _get_ability_name(ability) -> String:
	"""Extract ability name from either String or Dictionary format."""
	if ability is String:
		return ability
	elif ability is Dictionary:
		return ability.get("name", "")
	return ""

func _is_combat_phase(phase: int) -> bool:
	"""Check if a phase involves combat resolution (where ability flags matter)."""
	const GameStateData = preload("res://autoloads/GameState.gd")
	return phase in [
		GameStateData.Phase.SHOOTING,
		GameStateData.Phase.FIGHT,
		GameStateData.Phase.CHARGE  # For Tank Shock, Overwatch interactions
	]

func _is_relevant_for_phase(effect_def: Dictionary, phase: int) -> bool:
	"""Check if an ability's effects are relevant for the current phase."""
	var attack_type = effect_def.get("attack_type", "all")
	const GameStateData = preload("res://autoloads/GameState.gd")

	# "all" is always relevant
	if attack_type == "all":
		return true

	# "melee" only relevant in Fight phase
	if attack_type == "melee" and phase == GameStateData.Phase.FIGHT:
		return true

	# "ranged" only relevant in Shooting phase (and Charge for overwatch)
	if attack_type == "ranged" and phase in [GameStateData.Phase.SHOOTING, GameStateData.Phase.CHARGE]:
		return true

	return false

func _phase_to_string(phase: int) -> String:
	const GameStateData = preload("res://autoloads/GameState.gd")
	match phase:
		GameStateData.Phase.DEPLOYMENT: return "deployment"
		GameStateData.Phase.COMMAND: return "command"
		GameStateData.Phase.MOVEMENT: return "movement"
		GameStateData.Phase.SHOOTING: return "shooting"
		GameStateData.Phase.CHARGE: return "charge"
		GameStateData.Phase.FIGHT: return "fight"
		GameStateData.Phase.SCORING: return "scoring"
		_: return "unknown"

# ============================================================================
# SAVE/LOAD SUPPORT
# ============================================================================

func get_state_for_save() -> Dictionary:
	"""Return state data for save games."""
	return {
		"active_ability_effects": _active_ability_effects.duplicate(true),
		"applied_this_phase": _applied_this_phase.duplicate(true),
		"once_per_battle_used": _once_per_battle_used.duplicate(true),
		"once_per_round_used": _once_per_round_used.duplicate(true),
		"active_aura_effects": _active_aura_effects.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_ability_effects = data.get("active_ability_effects", [])
	_applied_this_phase = data.get("applied_this_phase", {})
	_once_per_battle_used = data.get("once_per_battle_used", {})
	_once_per_round_used = data.get("once_per_round_used", {})
	_active_aura_effects = data.get("active_aura_effects", {})
	print("UnitAbilityManager: State loaded — %d active effects, %d aura effects, %d once-per-battle used, %d once-per-round used" % [_active_ability_effects.size(), _active_aura_effects.size(), _once_per_battle_used.size(), _once_per_round_used.size()])

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()
	_once_per_battle_used.clear()
	_once_per_round_used.clear()
	_active_aura_effects.clear()
	print("UnitAbilityManager: Reset for new game")
