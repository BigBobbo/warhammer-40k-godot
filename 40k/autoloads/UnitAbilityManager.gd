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
#
# MA-29: Weapon-targeted ability filtering (optional field):
#   "target_weapon_names": Array[String]  # Only apply effects to attacks using these weapons
#   When present, each effect dict gets target_weapon_names injected before applying,
#   causing EffectPrimitives to store a companion weapon filter flag alongside the effect flag.
#   RulesEngine checks the weapon filter when reading effect flags during combat resolution.
#   If omitted, the ability applies to all weapons (unit-wide) as before.

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

	# Ork Ghazghkull Thraka — +1 to melee Hit AND Wound rolls; Crit Hit 5+ during Waaagh!
	"Prophet of Da Great Waaagh!": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}, {"type": "plus_one_wound"}],
		# OA-20: Waaagh!-conditional effects applied by FactionAbilityManager._apply_waaagh_effects()
		"waaagh_effects": [{"type": "crit_hit_on", "value": 5}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit and Wound rolls for led unit. During Waaagh!: Critical Hits on 5+"
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

	# Ork Big Mek — Kustom Force Field wargear: 4+ invulnerable save vs ranged attacks
	"Kustom Force Field": {
		"condition": "while_leading",
		"effects": [{"type": "grant_invuln", "value": 4}],
		"target": "led_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "4+ invulnerable save against ranged attacks for led unit"
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

	# Custodes Custodian Guard — re-roll Wound rolls of 1; re-roll all Wounds while on controlled objective
	"Stand Vigil": {
		"condition": "always",
		"effects": [{"type": "reroll_wounds", "scope": "ones"}],
		"objective_upgrade_effects": [{"type": "reroll_wounds", "scope": "all"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Re-roll Wound rolls of 1. While within range of controlled objective, re-roll all Wound rolls instead."
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

	# Vertus Praetors, Outrider Squad, etc. — skip advance roll, auto +6" to Move
	"Turbo-boost": {
		"condition": "always",
		"effects": [{"type": "auto_advance_6"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "When advancing, do not roll — add 6\" to Move instead"
	},

	# Deffkilla Wartrike — skip advance roll, auto +6" to Move
	"Fuel-mixa Grot": {
		"condition": "always",
		"effects": [{"type": "auto_advance_6"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "When advancing, do not roll — add 6\" to Move instead"
	},

	# Warboss on Warbike — skip advance roll, auto +6" to Move
	"High-octane Fuel": {
		"condition": "always",
		"effects": [{"type": "auto_advance_6"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "When advancing, do not roll — add 6\" to Move instead"
	},

	# Ork Stormboyz — eligible to charge after Advancing or Falling Back
	"Full Throttle": {
		"condition": "always",
		"effects": [{"type": "advance_and_charge"}, {"type": "fall_back_and_charge"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Unit is eligible to charge in a turn in which it Advanced or Fell Back"
	},

	# OA-23: Boss Zagstruk — re-roll Charge rolls when arriving from Reserves this turn
	"Plummeting Descent": {
		"condition": "arrived_from_reserves",
		"effects": [{"type": "reroll_charge"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Re-roll Charge rolls if this unit was set up from Reserves this turn"
	},

	# OA-24: Boss Snikrot — once per battle, redeploy unit instead of Normal move
	"Kunnin' Infiltrator": {
		"condition": "instead_of_normal_move",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: instead of Normal move, remove unit and redeploy 9\"+ from all enemies"
	},

	# OA-25: Deffkoptas — mortal wounds after Normal move over enemy units
	"Deff from Above": {
		"condition": "after_normal_move",
		"effects": [],
		"target": "enemy_moved_over",
		"attack_type": "all",
		"implemented": true,
		"description": "After Normal move, select one enemy unit moved over — roll D6 per model, 4+ = 1 mortal wound"
	},

	# OA-42: Grot Tanks — reactive 6" Normal move when enemy ends move within 9"
	"Scatter!": {
		"condition": "reactive_enemy_move",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_turn": true,
		"description": "Once per turn, when an enemy unit ends a Normal, Advance or Fall Back move within 9\" of this unit, if not within Engagement Range, can make a Normal move of up to 6\""
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

	# Ork wargear — once per battle per squig, mortal wounds after normal move
	# OA-30: Kommandos have 1 squig, Tankbustas have 2 (tracked independently)
	"Bomb Squigs": {
		"condition": "after_normal_move",
		"effects": [],
		"target": "enemy_within_12",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle per squig: after Normal move, select enemy within 12\" — on 3+, D3 mortal wounds"
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
	# target only one enemy unit with all attacks.
	# MA-29: Uses target_weapon_names to filter the +2 Attacks bonus to bolt rifle weapons only.
	# The single-target constraint is not yet enforced (would need ShootingPhase prompt).
	"Target Elimination": {
		"condition": "on_shooting_selection",
		"effects": [{"type": "plus_attacks", "value": 2}],
		"target": "unit",
		"attack_type": "ranged",
		"target_weapon_names": ["Bolt rifle", "Auto bolt rifle", "Stalker bolt rifle"],
		"implemented": true,
		"description": "+2 Attacks for bolt rifles when targeting a single enemy unit"
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

	# Ork Trukk — regain 1 lost wound at start of Command phase
	"Grot Riggers": {
		"condition": "start_of_command",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "At the start of your Command phase, this model regains 1 lost wound"
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

	# Ork Big Mek in Mega Armour — return 1 destroyed Bodyguard model each Command phase while leading
	"Fix Dat Armour Up": {
		"condition": "start_of_command",
		"effects": [],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While this model is leading a unit, in your Command phase, you can return 1 destroyed Bodyguard model to that unit"
	},

	# ======================================================================
	# PHASE-TRIGGERED ABILITIES (Movement phase etc.)
	# ======================================================================

	# Ork Mek / Big Mek on Warbike / Meka-dread — heal D3 + grant +1 Hit to friendly Orks Vehicle
	# at end of Movement phase. Once per vehicle per turn.
	"Mekaniak": {
		"condition": "end_of_movement",
		"effects": [],
		"target": "friendly_orks_vehicle",
		"attack_type": "all",
		"implemented": true,
		"description": "At end of Movement phase, select one friendly Orks Vehicle within 3\" — regain up to D3 lost wounds and +1 to Hit until start of next Movement phase. Once per vehicle per turn."
	},

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
	# WARGEAR ABILITIES — Pulsa Rokkit (OA-31), Grot Oiler (OA-32)
	# ======================================================================

	# Ork Tankbustas — once per battle, when unit is selected to shoot:
	# +1 Strength and +1 AP to all ranged weapons for the phase.
	# Triggered when unit is selected to shoot — prompt offered in ShootingPhase.
	"Pulsa Rokkit": {
		"condition": "on_shooting_selection",
		"effects": [{"type": "improve_strength"}, {"type": "improve_ap"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: +1 Strength and +1 AP to ranged weapons for the phase"
	},

	# Ork Big Mek / Mek — once per battle, at the end of your Movement phase:
	# One model in the bearer's unit regains D3 lost wounds.
	# Triggered at end of Movement phase — prompt offered in MovementPhase.
	# OA-32: Grot Oiler wargear ability
	"Grot Oiler": {
		"condition": "end_of_movement",
		"effects": [{"type": "heal_d3"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: one model in bearer's unit regains D3 lost wounds at end of Movement phase"
	},

	# ======================================================================
	# WARGEAR ABILITIES — Shooty Power Trip (OA-37)
	# ======================================================================

	# Ork Killa Kans — each time this unit is selected to shoot, player may roll D6:
	# 1-2: Unit suffers D3 mortal wounds.
	# 3-4: +1 Strength to ranged weapons for the phase.
	# 5-6: +1 Attacks to ranged weapons for the phase.
	# Not once per battle — can be used every time the unit shoots.
	"Shooty Power Trip": {
		"condition": "on_shooting_selection",
		"effects": [{"type": "random_d6_effect"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "When selected to shoot, roll D6: 1-2 = D3 mortal wounds to self, 3-4 = +1 Strength, 5-6 = +1 Attacks to ranged weapons"
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

	# ======================================================================
	# CONDITIONAL RE-ROLL ABILITIES — Splat! (OA-38)
	# These are checked directly in RulesEngine where both attacker and target are known.
	# ======================================================================

	# Ork Big Gunz — re-roll Hit rolls of 1 when targeting units with 10+ models.
	# Ork Mek Gunz — re-roll Hit rolls of 1 when at Starting Strength and targeting
	# non-MONSTER/VEHICLE units.
	# The specific condition is determined by the unit's meta.name in RulesEngine.
	"Splat!": {
		"condition": "target_conditional",
		"effects": [{"type": "reroll_hits", "scope": "ones"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Big Gunz: re-roll Hit rolls of 1 vs 10+ model targets. Mek Gunz: re-roll Hit rolls of 1 at Starting Strength vs non-MONSTER/VEHICLE — checked directly in RulesEngine"
	},

	# Ork Wazbom Blastajet — re-roll Hit rolls of 1 when targeting non-FLY units (OA-40)
	# The FLY keyword check is performed directly in RulesEngine.
	"Blastajet Attack Run": {
		"condition": "target_conditional",
		"effects": [{"type": "reroll_hits", "scope": "ones"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Re-roll Hit rolls of 1 when targeting non-FLY units — checked directly in RulesEngine"
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

	# Ork Nobz On Warbikes — Consolidation distance is 6" instead of 3" (OA-26)
	# Checked directly in FightPhase consolidation logic.
	"Drive-by Krumpin'": {
		"condition": "always",
		"effects": [{"type": "consolidation_distance", "value": 6}],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "Consolidation distance is 6\" instead of 3\" — checked directly in FightPhase"
	},

	# Ork Morkanaut/Gorkanaut — can move over non-MONSTER/VEHICLE enemy models and terrain ≤4" (OA-28)
	# Checked directly in MovementPhase movement validation.
	"Clankin' Forward": {
		"condition": "always",
		"effects": [{"type": "move_over_non_monster_vehicle"}, {"type": "move_over_short_terrain", "max_height": 4.0}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Can move over enemy models (excluding MONSTER/VEHICLE) and terrain ≤4\" height during Normal, Advance, or Fall Back moves"
	},

	# Ork Stompa — can move over all non-TITANIC models and terrain ≤4" (OA-29)
	# Checked directly in MovementPhase movement validation.
	"Stompin' Forward": {
		"condition": "always",
		"effects": [{"type": "move_over_non_titanic"}, {"type": "move_over_short_terrain", "max_height": 4.0}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Can move over all non-TITANIC models and terrain ≤4\" height during Normal, Advance, or Fall Back moves"
	},

	# Ork Warbuggies — can deploy in opponent's deployment zone from Strategic Reserves (OA-27)
	# Checked directly in MovementPhase reserve placement validation.
	"Outflank": {
		"condition": "deployment_override",
		"effects": [{"type": "ignore_opponent_zone_restriction"}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "When arriving from Strategic Reserves, can be set up in opponent's deployment zone (Turn 2 restriction bypassed)"
	},

	# Ork Dakkajet — every successful Hit roll scores a Critical Hit (ranged only)
	# Sustained Hits and Lethal Hits trigger on every successful hit.
	# Checked directly in RulesEngine hit resolution (interactive + auto-resolve paths).
	"Dakkastorm": {
		"condition": "always",
		"effects": [{"type": "all_hits_critical"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Every successful Hit roll scores a Critical Hit (ranged attacks only) — checked directly in RulesEngine"
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

	# Ork Burna Boyz / Skorchas — re-roll Wound rolls of 1 with Torrent weapons vs enemies within 6"
	# Full Wound re-roll if target is also within range of an objective marker.
	# Checked directly in RulesEngine where both weapon type and board are available.
	"Pyromaniaks": {
		"condition": "target_within_range",
		"range_inches": 6.0,
		"effects": [{"type": "reroll_wounds", "scope": "ones"}],
		"effects_on_objective": [{"type": "reroll_wounds", "scope": "failed"}],
		"target": "unit",
		"attack_type": "ranged",
		"weapon_filter": "torrent",
		"implemented": true,
		"description": "Re-roll Wound rolls of 1 with Torrent weapons against enemies within 6\". Full Wound re-roll if target is also within range of an objective marker — checked directly in RulesEngine"
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

	# Ork Meganobz — Feel No Pain 5+ while Waaagh! is active (OA-17)
	# Applied/cleared by FactionAbilityManager._apply_waaagh_effects / _clear_waaagh_effects
	# Does not stack with other FNP sources — get_unit_fnp() uses the better (lower) value
	"Krumpin' Time": {
		"condition": "waaagh_active",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 5+ while Waaagh! is active — applied via FactionAbilityManager Waaagh! activation"
	},

	# OA-46: Nob with Waaagh! Banner — once per battle, unit gains Waaagh! effects for one round
	# Activated via FactionAbilityManager.activate_plant_waaagh_banner() during Command Phase.
	# Effects (4+ invuln, OC 5, advance+charge) applied/cleared by FactionAbilityManager.
	"Plant the Waaagh! Banner": {
		"condition": "once_per_battle",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_battle": true,
		"description": "Once per battle: unit gains Waaagh! effects (4+ invuln, OC 5, advance+charge) — applied via FactionAbilityManager"
	},

	# OA-46: Nob with Waaagh! Banner — 4+ invuln and OC 5 while Waaagh! active
	# Applied by FactionAbilityManager when Waaagh! is active for this unit (army or Plant banner).
	"Da Boss Iz Watchin'": {
		"condition": "waaagh_active",
		"effects": [{"type": "grant_invuln", "value": 4}, {"type": "grant_oc", "value": 5}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While Waaagh! active: 4+ invuln save and OC 5 — applied via FactionAbilityManager"
	},

	# Ork Painboy — D6 mortal wounds on Critical Wound with 'urty syringe vs non-VEHICLE (OA-19)
	# Checked in RulesEngine._resolve_melee_assignment() after wound rolls.
	# Only triggers for the 'urty syringe weapon, not other Painboy attacks.
	"Hold Still and Say 'Aargh!'": {
		"condition": "on_critical_wound",
		"effects": [{"type": "mortal_wounds_d6"}],
		"target": "attacked_enemy",
		"attack_type": "melee",
		"weapon_restriction": "'urty syringe",
		"exclude_keywords": ["VEHICLE"],
		"implemented": true,
		"description": "On Critical Wound with 'urty syringe, target suffers D6 mortal wounds (excludes VEHICLE)"
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

	# ======================================================================
	# AURA ABILITIES — Battle-shock modifiers (OA-43)
	# ======================================================================

	# OA-43: Ork Stompa — friendly ORKS units within 12" get +1 to Battle-shock tests.
	# Not a combat flag — enforced directly in CommandPhase._resolve_battle_shock_test()
	# via get_battle_shock_bonus(). The aura condition documents the intent; effects are
	# empty because the bonus is applied to the dice roll, not via the EffectPrimitives system.
	"Waaagh! Effigy (Aura)": {
		"condition": "aura",
		"effects": [],
		"aura_range": 12.0,
		"aura_target": "friendly",
		"target": "friendly_orks_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Friendly ORKS units within 12\" get +1 to Battle-shock tests — checked directly in CommandPhase"
	},

	# ======================================================================
	# AURA ABILITIES — Toughness modifiers (OA-44)
	# ======================================================================

	# OA-44: Kaptin Badrukk — enemy INFANTRY units within 6" suffer -1 Toughness.
	# Not a combat flag applied via EffectPrimitives — enforced directly in RulesEngine
	# via get_ded_glowy_ammo_toughness_penalty(). The aura condition documents the intent;
	# effects are empty because toughness is modified at wound resolution time, not via flags.
	"Ded Glowy Ammo (Aura)": {
		"condition": "aura",
		"effects": [],
		"aura_range": 6.0,
		"aura_target": "enemy",
		"target": "enemy_infantry_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Enemy INFANTRY units within 6\" suffer -1 Toughness — checked directly in RulesEngine"
	},

	# ======================================================================
	# AURA ABILITIES — Lethal Hits (OA-45)
	# ======================================================================

	# OA-45: Ghazghkull Thraka — friendly ORKS units within 12" get Lethal Hits on melee
	# weapons while a Waaagh! is active. Measured from Ghazghkull/Makari's unit.
	# Not a combat flag applied via EffectPrimitives — enforced directly in RulesEngine
	# via unit_has_waaagh_banner_lethal_hits(). The aura condition documents the intent; effects
	# are empty because Lethal Hits is granted at melee resolution time, conditioned on Waaagh!.
	"Ghazghkull's Waaagh! Banner (Aura)": {
		"condition": "aura_waaagh",
		"effects": [],
		"aura_range": 12.0,
		"aura_target": "friendly",
		"target": "friendly_orks_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "Friendly ORKS units within 12\" get Lethal Hits on melee weapons while Waaagh! active — checked directly in RulesEngine"
	},

	# ======================================================================
	# CONDITIONAL TOUGHNESS ABILITIES — Unit composition (OA-48)
	# ======================================================================

	# OA-48: Gretchin/Runtherd — While the unit contains Gretchin models, Runtherd models
	# use T2 (same as unit base T — no change). When all Gretchin die, Runtherd models
	# revert to T4 from their model_profile stats_override.
	# Not a combat flag applied via EffectPrimitives — enforced directly in RulesEngine
	# via get_runtherd_toughness_override(). Effects are empty because toughness is modified
	# at wound resolution time, conditioned on unit composition (alive Gretchin count).
	"Runtherd": {
		"condition": "unit_composition",
		"effects": [],
		"target": "self",
		"attack_type": "all",
		"implemented": true,
		"description": "While unit contains Gretchin models, Runtherd models use T2. Reverts to T4 when all Gretchin die — checked directly in RulesEngine"
	},

	# ======================================================================
	# BEAST SNAGGA SUB-FACTION ABILITIES (OA-49)
	# ======================================================================

	# Beastboss — +1 to melee Hit rolls for led unit
	# While this model is leading a unit, each time a model in that unit makes a
	# melee attack, add 1 to the Hit roll. Same mechanic as "Might is Right".
	"Beastboss": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "+1 to melee Hit rolls for led unit"
	},

	# Beastboss — melee weapons gain [DEVASTATING WOUNDS] after charging
	# Each time this model makes a Charge move, until the end of the turn, melee weapons
	# it is equipped with have the [DEVASTATING WOUNDS] ability.
	# NOTE: This applies to the Beastboss model only, not the whole led unit. Requires
	# model-level weapon keyword tracking — not yet supported by the flag system.
	"Beastly Rage": {
		"condition": "charged_this_turn",
		"effects": [{"type": "grant_devastating_wounds"}],
		"target": "model",
		"attack_type": "melee",
		"implemented": false,
		"description": "After charging, this model's melee weapons gain [DEVASTATING WOUNDS] until end of turn — requires model-level weapon keyword tracking"
	},

	# Squighog Boyz — ignore modifiers to Move characteristic and Advance/Charge rolls
	# You can ignore any or all modifiers to this unit's Move characteristic and to
	# Advance and Charge rolls made for this unit.
	"Wild Ride": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"description": "Ignore any or all modifiers to Move characteristic and Advance/Charge rolls — requires MovementPhase/ChargePhase integration"
	},

	# Kill Rig / Hunta Rig — +2 to Charge rolls and block Fire Overwatch vs hit MONSTER/VEHICLE
	# Each time this weapon scores a hit against a MONSTER or VEHICLE unit, until the end
	# of the turn, if the bearer selects that unit as a target of a charge, add 2 to Charge
	# rolls and enemy units cannot use Fire Overwatch to shoot at the bearer.
	"Snagged": {
		"condition": "weapon_hit_conditional",
		"target_keywords": ["MONSTER", "VEHICLE"],
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": false,
		"description": "After hitting MONSTER or VEHICLE, +2 to Charge rolls vs that unit and cannot be targeted by Fire Overwatch — requires ShootingPhase/ChargePhase integration"
	},

	# Kill Rig — Psychic: start of Fight phase, buff friendly Orks unit within 12"
	# At the start of the Fight phase, select one friendly Orks unit within 12":
	# D6 roll — 1: this model suffers D3 mortal wounds; 2-5: +1 Strength to melee weapons;
	# 6: +1 Strength AND [LETHAL HITS] to melee weapons until end of phase.
	"Spirit of Gork (Psychic)": {
		"condition": "start_of_fight_phase",
		"effects": [],
		"target": "friendly_orks_unit_within_12",
		"attack_type": "melee",
		"implemented": false,
		"description": "Start of Fight phase: select friendly Orks unit within 12\" — roll D6: 1=D3 MW to self, 2-5=+1S to melee weapons, 6=+1S and LETHAL HITS — requires FightPhase integration"
	},

	# Hunta Rig — +1 Attacks per embarked model to butcha boyz weapon (max +6)
	# For each model embarked within this TRANSPORT, add 1 to the Attacks characteristic
	# of this model's butcha boyz weapon (to a maximum of +6).
	"On Da Hunt": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": false,
		"description": "+1 Attacks to butcha boyz per model embarked in this TRANSPORT (max +6) — requires TransportManager and dynamic weapon modification"
	},

	# Beast Snagga Boyz — re-roll Hit rolls when making melee attacks vs MONSTER or VEHICLE
	# Each time a model in this unit makes an attack that targets a MONSTER or VEHICLE unit,
	# you can re-roll the Hit roll.
	# Checked directly in RulesEngine.has_monster_hunters_vs_target() — same pattern as Tank Hunters.
	"Monster Hunters": {
		"condition": "target_has_keyword",
		"target_keywords": ["MONSTER", "VEHICLE"],
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "Re-roll Hit rolls when making melee attacks against MONSTER or VEHICLE units — checked directly in RulesEngine"
	},

	# Wurrboy — Eyez of Mork weapon scales with led unit size; Hazardous at 10+ models
	# While this model is leading a unit, add 2 to the Attacks characteristic of this
	# model's Eyez of Mork weapon for every 5 models in that unit (rounding down), but
	# while that unit contains 10 or more models, that weapon has the [HAZARDOUS] ability.
	"Unstable Oracle": {
		"condition": "while_leading",
		"effects": [],
		"target": "model",
		"attack_type": "ranged",
		"implemented": false,
		"description": "+2 Attacks to Eyez of Mork per 5 models in led unit (round down); HAZARDOUS at 10+ models — requires dynamic weapon modification based on unit size"
	},

	# Wurrboy — Psychic: in opponent's Command phase, debuff enemy unit
	# In your opponent's Command phase, select one enemy unit within 18" and visible:
	# roll D6 — 1: this PSYKER's unit suffers D3 mortal wounds; 2+: target is confrazzled
	# (subtract 2 from Battle-shock and Leadership tests) until opponent's next Command phase.
	"Roar of Mork (Psychic)": {
		"condition": "opponent_command_phase",
		"effects": [],
		"target": "enemy_within_18",
		"attack_type": "all",
		"implemented": false,
		"description": "Opponent's Command phase: select enemy within 18\" — roll D6: 1=D3 MW to self, 2+=confrazzled (−2 to Battle-shock/Leadership tests) — requires CommandPhase integration"
	},

	# Zodgrod Wortsnagga — led unit has Scouts 9", +1 Hit, +1 Wound, -1 incoming Wound
	# While this model is leading a unit:
	# - Models in that unit have the Scouts 9" ability (deployment, not a combat flag).
	# - Each time a model in that unit makes an attack, add 1 to the Hit roll and Wound roll.
	# - Each time an attack targets that unit, subtract 1 from the Wound roll.
	# Combat effects (+1 Hit, +1 Wound) are applied via the flag system on the led unit.
	# Scouts 9" is enforced at deployment. -1 incoming Wound requires RulesEngine integration.
	"Super Runts": {
		"condition": "while_leading",
		"effects": [{"type": "plus_one_hit"}, {"type": "plus_one_wound"}],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Led unit: +1 to Hit rolls, +1 to Wound rolls when attacking. Scouts 9\" handled at deployment. -1 incoming Wound requires RulesEngine integration — checked directly in RulesEngine for full effect"
	},

	# Zodgrod Wortsnagga — +6\" to Move of led unit while Waaagh! is active
	# While the Waaagh! is active for your army, add 6\" to the Move characteristic of
	# models in this model's unit.
	"Special Dose": {
		"condition": "waaagh_active",
		"effects": [],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": false,
		"description": "While Waaagh! active, add 6\" to Move characteristic of models in this model's unit — requires MovementPhase integration"
	},

	# Mozrog Skragbad — led unit models can fight before dying when destroyed by melee (4+)
	# While this model is leading a unit, each time a model in that unit is destroyed by
	# a melee attack, if it has not fought this phase, roll one D6: on a 4+, do not remove
	# it from play. It can fight after the attacking unit has finished making its attacks,
	# then is removed from play.
	"One Last Kill": {
		"condition": "while_leading",
		"effects": [],
		"target": "led_unit",
		"attack_type": "melee",
		"implemented": false,
		"description": "While leading: when led unit model destroyed by melee, on 4+ it fights before removal — requires FightPhase model destruction integration"
	},

	# Mozrog Skragbad — +1 Damage vs MONSTER/VEHICLE, +2 Damage vs TITANIC (melee)
	# Each time this model makes a melee attack that targets a MONSTER or VEHICLE unit,
	# add 1 to the Damage characteristic of that attack. Against TITANIC: add 2 instead.
	"Da Bigger Dey iz...": {
		"condition": "target_has_keyword",
		"target_keywords": ["MONSTER", "VEHICLE"],
		"effects": [],
		"target": "model",
		"attack_type": "melee",
		"implemented": false,
		"description": "+1 Damage to melee attacks vs MONSTER or VEHICLE; +2 Damage vs TITANIC — requires RulesEngine integration for per-model conditional damage bonus"
	},

	# ======================================================================
	# ORK VEHICLE ABILITIES (OA-50)
	# ======================================================================

	# Gorkanaut — Deadly Demise triggered by lifta-droppa fires on 3+ instead of 6
	# Each time an attack made with this model's lifta-droppa destroys an enemy model
	# that has the Deadly Demise ability, that model's Deadly Demise triggers on a D6
	# roll of 3+ instead of 6.
	# Checked in RulesEngine.resolve_deadly_demise() when killer context is provided.
	"Da Bigger Dey Are, da Better Dey Drop": {
		"condition": "on_deadly_demise",
		"effects": [],
		"target": "enemy",
		"attack_type": "ranged",
		"weapon_restriction": "lifta-droppa",
		"implemented": true,
		"description": "When lifta-droppa destroys enemy model with Deadly Demise, Deadly Demise triggers on 3+ instead of 6 — checked in RulesEngine.resolve_deadly_demise() with killer context"
	},

	# Trukk — after Charge move ends, select enemy in Engagement Range, roll D6: 2-5=D3 MW, 6=3 MW
	# Each time this model ends a Charge move, you can select one enemy unit within
	# Engagement Range of it and roll one D6: on a 2-5, that unit suffers D3 mortal wounds;
	# on a 6, that unit suffers 3 mortal wounds.
	# Resolved in ChargePhase._apply_spiked_ram_if_applicable() after charge move.
	"Spiked Ram": {
		"condition": "after_charge_move",
		"effects": [],
		"target": "enemy_in_engagement_range",
		"attack_type": "all",
		"implemented": true,
		"description": "After Charge move ends, select one enemy in Engagement Range — roll D6: 2-5=D3 mortal wounds, 6=3 mortal wounds — resolved in ChargePhase"
	},

	# Battlewagon — concussive wave from supa-kannon: D6 vs target+units within 3", 5+=MW
	# In your Shooting phase, just after selecting the target for this model's supa-kannon,
	# roll one D6 for the target unit and each other unit (friend or foe) within 3\" of it:
	# on a 5+, that unit is struck by the concussive wave. After making all attacks against
	# the target unit, each unit struck by the concussive wave suffers D3 mortal wounds.
	# Requires ShootingPhase integration to roll concussive wave after target selection.
	"Big Booms": {
		"condition": "on_shooting_target_selection",
		"effects": [],
		"target": "enemy_target",
		"attack_type": "ranged",
		"weapon_restriction": "supa-kannon",
		"implemented": false,
		"description": "When targeting with supa-kannon: roll D6 for target and units within 3\" — 5+=concussive wave; after attack resolves each struck unit suffers D3 MW — requires ShootingPhase integration"
	},

	# Bonebreaka — +1 to Hit on ranged attacks vs targets within half weapon range
	# Each time this model makes a ranged attack that targets a unit within half the
	# range of that weapon, add 1 to the Hit roll.
	# Checked directly in RulesEngine hit modifier collection.
	"Wall of Dakka": {
		"condition": "target_within_half_range",
		"effects": [{"type": "plus_one_hit"}],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "+1 to Hit rolls for ranged attacks when target is within half the weapon's range — checked directly in RulesEngine"
	},
}

# ============================================================================
# MA-29: WEAPON FILTER INJECTION HELPER
# ============================================================================

static func _inject_weapon_filter(effects: Array, effect_def: Dictionary) -> Array:
	"""If the ability definition has target_weapon_names, inject it into each effect dict.
	Returns a new array with the filter injected (or the original array if no filter)."""
	var weapon_names = effect_def.get("target_weapon_names", [])
	if weapon_names.is_empty():
		return effects
	var filtered_effects: Array = []
	for effect in effects:
		var copy = effect.duplicate()
		copy["target_weapon_names"] = weapon_names
		filtered_effects.append(copy)
	return filtered_effects

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

# OA-34: Track which vehicles have been selected for Mekaniak this turn
# Key: vehicle_unit_id, Value: true
var _mekaniak_used_this_turn: Dictionary = {}

# OA-42: Track which units have used Scatter! this turn
# Key: unit_id, Value: true
var _scatter_used_this_turn: Dictionary = {}

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

			# MA-29: Inject target_weapon_names into effect dicts if present on the ability
			effects = _inject_weapon_filter(effects, effect_def)

			var diffs = EffectPrimitivesData.apply_effects(effects, bodyguard_unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)

				# Set invuln source for logging/UI if this ability grants an invuln save
				for eff in effects:
					if eff.get("type", "") == "grant_invuln":
						PhaseManager.apply_state_changes([{
							"op": "set",
							"path": "units.%s.flags.effect_invuln_source" % bodyguard_unit_id,
							"value": ability_name
						}])
						break

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

		# Handle unit-level conditions (leader abilities handled separately)
		var condition = effect_def.get("condition", "")
		if condition == "arrived_from_reserves":
			# OA-23: Only apply if unit arrived from reserves THIS battle round
			var arrival_turn = unit.get("arrived_from_reserves_turn", -1)
			var current_round = GameState.get_battle_round()
			if arrival_turn != current_round:
				continue
		elif condition != "always":
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

		# Determine which effects to use — check for objective-conditional upgrade
		var effects = effect_def.get("effects", [])
		var upgrade_effects = effect_def.get("objective_upgrade_effects", [])
		var using_upgrade = false
		if not upgrade_effects.is_empty():
			if _is_unit_within_controlled_objective_range(unit_id, unit):
				effects = upgrade_effects
				using_upgrade = true
				print("UnitAbilityManager: %s — objective-conditional upgrade active for '%s'" % [unit_id, ability_name])

		if effects.is_empty():
			continue

		# MA-29: Inject target_weapon_names into effect dicts if present on the ability
		effects = _inject_weapon_filter(effects, effect_def)

		var diffs = EffectPrimitivesData.apply_effects(effects, unit_id)
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)

			_active_ability_effects.append({
				"ability_name": ability_name,
				"source_unit_id": unit_id,
				"target_unit_id": unit_id,
				"effects": effects,
				"attack_type": effect_def.get("attack_type", "all"),
				"condition": condition
			})

			if not _applied_this_phase.has(unit_id):
				_applied_this_phase[unit_id] = []
			_applied_this_phase[unit_id].append(ability_name)

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var flag_names = EffectPrimitivesData.get_flag_names_for_effects(effects)
			var upgrade_note = " (OBJECTIVE UPGRADE)" if using_upgrade else ""
			print("UnitAbilityManager: %s (%s) has ability '%s'%s — flags: %s" % [
				unit_name, unit_id, ability_name, upgrade_note, str(flag_names)
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

			# MA-29: Inject target_weapon_names into effect dicts if present on the ability
			effects = _inject_weapon_filter(effects, effect_def)

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

# OA-43: Waaagh! Effigy (Aura) — Battle-shock bonus
func get_battle_shock_bonus(unit_id: String) -> int:
	"""Check if a unit benefits from the Waaagh! Effigy (Aura) ability on a nearby Stompa.
	Returns +1 if the unit has the ORKS keyword and is within 12\" edge-to-edge of a
	friendly unit with the 'Waaagh! Effigy (Aura)' ability. Returns 0 otherwise.
	Per 10th Edition: same aura from multiple sources does not stack — returns 1 at most."""
	var units = GameState.state.get("units", {})
	var target_unit = units.get(unit_id, {})
	if target_unit.is_empty():
		return 0

	# Only ORKS keyword units benefit from this aura
	var target_keywords = target_unit.get("meta", {}).get("keywords", [])
	var has_orks_keyword = false
	for kw in target_keywords:
		if kw.to_upper() == "ORKS":
			has_orks_keyword = true
			break
	if not has_orks_keyword:
		return 0

	var target_owner = target_unit.get("owner", 0)
	var target_embarked = target_unit.get("embarked_in", "")

	# Check all friendly units for Waaagh! Effigy (Aura) ability
	for source_unit_id in units:
		var source_unit = units[source_unit_id]

		# Must be a friendly unit owned by the same player
		if source_unit.get("owner", 0) != target_owner:
			continue

		# Must be alive and on the board
		if not _has_alive_models(source_unit):
			continue
		if source_unit.get("embarked_in", "") != "":
			continue

		# Check if this unit has the Waaagh! Effigy (Aura) ability
		var source_abilities = source_unit.get("meta", {}).get("abilities", [])
		var has_effigy = false
		for ability in source_abilities:
			if ability.get("name", "") == "Waaagh! Effigy (Aura)":
				has_effigy = true
				break
		if not has_effigy:
			continue

		# Per 10th Ed rules, a model is always within range of its own aura.
		# If the source and target are the same unit (Stompa taking its own test), apply bonus.
		if source_unit_id == unit_id:
			print("UnitAbilityManager: Waaagh! Effigy aura — %s is source unit, bonus applies (self-aura)" % unit_id)
			return 1

		# Skip range check if target is embarked (positions not meaningful on-board)
		if target_embarked != "":
			continue

		# Calculate closest model-to-model distance (edge-to-edge)
		var dist = _closest_model_distance(target_unit, source_unit)
		if dist <= 12.0:
			print("UnitAbilityManager: Waaagh! Effigy aura — %s within 12\" of %s (%.1f\"), Battle-shock bonus +1 applies" % [
				unit_id, source_unit_id, dist])
			return 1

	return 0

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

				# Only apply eligibility effects (fall_back_and_*, advance_and_*, flat_advance)
				var effects = effect_def.get("effects", [])
				var eligibility_effects = []
				for effect in effects:
					var etype = effect.get("type", "")
					if etype in [
						EffectPrimitivesData.FALL_BACK_AND_SHOOT,
						EffectPrimitivesData.FALL_BACK_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_CHARGE,
						EffectPrimitivesData.ADVANCE_AND_SHOOT,
						EffectPrimitivesData.FLAT_ADVANCE
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

		# Check the unit's own abilities for eligibility effects (condition: "always")
		var unit_abilities = unit.get("meta", {}).get("abilities", [])
		for ability in unit_abilities:
			var ability_name = _get_ability_name(ability)
			if ability_name == "":
				continue

			var effect_def = ABILITY_EFFECTS.get(ability_name, {})
			if effect_def.is_empty() or not effect_def.get("implemented", false):
				continue
			if effect_def.get("condition", "") != "always":
				continue

			# Only apply eligibility effects (fall_back_and_*, advance_and_*, flat_advance)
			var effects = effect_def.get("effects", [])
			var eligibility_effects = []
			for effect in effects:
				var etype = effect.get("type", "")
				if etype in [
					EffectPrimitivesData.FALL_BACK_AND_SHOOT,
					EffectPrimitivesData.FALL_BACK_AND_CHARGE,
					EffectPrimitivesData.ADVANCE_AND_CHARGE,
					EffectPrimitivesData.ADVANCE_AND_SHOOT,
					EffectPrimitivesData.FLAT_ADVANCE
				]:
					eligibility_effects.append(effect)

			if eligibility_effects.is_empty():
				continue

			var diffs = EffectPrimitivesData.apply_effects(eligibility_effects, unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)
				_active_ability_effects.append({
					"ability_name": ability_name,
					"source_unit_id": unit_id,
					"target_unit_id": unit_id,
					"effects": eligibility_effects,
					"attack_type": "all",
					"condition": "always"
				})
				if not _applied_this_phase.has(unit_id):
					_applied_this_phase[unit_id] = []
				_applied_this_phase[unit_id].append(ability_name)

				var unit_name = unit.get("meta", {}).get("name", unit_id)
				print("UnitAbilityManager: %s has own eligibility ability '%s'" % [unit_name, ability_name])

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

		# Clear invuln source if this ability granted an invuln save
		for eff in effects:
			if eff.get("type", "") == "grant_invuln":
				if flags.has("effect_invuln_source"):
					flags.erase("effect_invuln_source")
					print("EffectPrimitives: Cleared effect_invuln_source from %s" % target_unit_id)
				break

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

func has_hold_still_ability(unit_id: String) -> bool:
	"""Check if a unit has the 'Hold Still and Say Aargh!' ability (e.g. Painboy).
	Used by RulesEngine to trigger D6 mortal wounds on Critical Wound with 'urty syringe."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Hold Still and Say 'Aargh!'":
			print("UnitAbilityManager: Unit %s has Hold Still and Say 'Aargh!' ability" % unit_id)
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

func has_pulsa_rokkit(unit_id: String) -> bool:
	"""OA-31: Check if a unit has an unused Pulsa Rokkit wargear ability.
	Used by ShootingPhase to offer +1S/+1AP when unit is selected to shoot."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Pulsa Rokkit":
			if not is_once_per_battle_used(unit_id, "Pulsa Rokkit"):
				print("UnitAbilityManager: Unit %s has unused Pulsa Rokkit" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Pulsa Rokkit but already used this battle" % unit_id)
				return false
	return false

func mark_pulsa_rokkit_used(unit_id: String) -> void:
	"""OA-31: Mark Pulsa Rokkit as used for a unit."""
	mark_once_per_battle_used(unit_id, "Pulsa Rokkit")
	print("UnitAbilityManager: Marked Pulsa Rokkit as used for unit %s" % unit_id)

func has_shooty_power_trip(unit_id: String) -> bool:
	"""OA-37: Check if a unit has the Shooty Power Trip ability (Killa Kans).
	Not once per battle — can be used every time the unit is selected to shoot.
	Used by ShootingPhase to offer the D6 roll when unit is selected to shoot."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Shooty Power Trip":
			print("UnitAbilityManager: Unit %s has Shooty Power Trip" % unit_id)
			return true
	return false

func has_grot_oiler(unit_id: String) -> bool:
	"""OA-32: Check if a unit has an unused Grot Oiler wargear ability.
	Used by MovementPhase at end of movement to offer D3 wound healing."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Grot Oiler":
			if not is_once_per_battle_used(unit_id, "Grot Oiler"):
				print("UnitAbilityManager: Unit %s has unused Grot Oiler" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Grot Oiler but already used this battle" % unit_id)
				return false
	return false

func mark_grot_oiler_used(unit_id: String) -> void:
	"""OA-32: Mark Grot Oiler as used for a unit."""
	mark_once_per_battle_used(unit_id, "Grot Oiler")
	print("UnitAbilityManager: Marked Grot Oiler as used for unit %s" % unit_id)

func get_grot_oiler_targets(bearer_unit_id: String) -> Array:
	"""OA-32: Get eligible healing targets for Grot Oiler wargear ability.
	Returns array of { unit_id, unit_name, model_id, model_index, current_wounds, max_wounds }
	for models in the bearer's unit (including bodyguard models if attached) that have lost wounds."""
	var targets = []
	var bearer_unit = GameState.state.get("units", {}).get(bearer_unit_id, {})
	if bearer_unit.is_empty():
		return targets

	# Collect all unit IDs that form the bearer's unit (character + bodyguard if attached)
	var unit_ids_to_check = [bearer_unit_id]

	# If the bearer is attached to a bodyguard, include the bodyguard unit
	var attached_to = bearer_unit.get("attached_to", null)
	if attached_to != null and attached_to != "":
		unit_ids_to_check.append(attached_to)

	# If the bearer has attached characters (unlikely for Mek but handle generically),
	# include those units too
	var attached_chars = bearer_unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		if char_id != bearer_unit_id and char_id not in unit_ids_to_check:
			unit_ids_to_check.append(char_id)

	# Find models with lost wounds in all units in the combined Attached unit
	for unit_id in unit_ids_to_check:
		var unit = GameState.state.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var models = unit.get("models", [])
		for i in range(models.size()):
			var model = models[i]
			if not model.get("alive", true):
				continue
			var max_wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", max_wounds)
			if current_wounds >= max_wounds:
				continue  # No wounds lost
			targets.append({
				"unit_id": unit_id,
				"unit_name": unit_name,
				"model_id": model.get("id", "m%d" % (i + 1)),
				"model_index": i,
				"current_wounds": current_wounds,
				"max_wounds": max_wounds
			})
			print("UnitAbilityManager: Grot Oiler target — %s model %s (%d/%d wounds)" % [
				unit_name, model.get("id", ""), current_wounds, max_wounds])

	print("UnitAbilityManager: Grot Oiler found %d eligible targets for unit %s" % [targets.size(), bearer_unit_id])
	return targets

func get_bomb_squig_count(unit_id: String) -> int:
	"""OA-30: Get the total number of bomb squigs a unit has.
	Reads count from ability dict (default 1). Tankbustas have 2, Kommandos have 1."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return 0

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Bomb Squigs":
			if ability is Dictionary:
				return ability.get("count", 1)
			return 1
	return 0

func get_bomb_squigs_remaining(unit_id: String) -> int:
	"""OA-30: Get the number of unused bomb squigs for a unit.
	Each squig is tracked independently via 'unit_id:Bomb Squigs:N' keys."""
	var total = get_bomb_squig_count(unit_id)
	if total == 0:
		return 0

	var remaining = 0
	for i in range(total):
		var usage_key = unit_id + ":Bomb Squigs:" + str(i)
		if not _once_per_battle_used.get(usage_key, false):
			remaining += 1

	print("UnitAbilityManager: Unit %s has %d/%d bomb squigs remaining" % [unit_id, remaining, total])
	return remaining

func mark_bomb_squig_used(unit_id: String) -> int:
	"""OA-30: Mark the next unused bomb squig as used for a unit.
	Returns the index of the squig that was marked, or -1 if none available."""
	var total = get_bomb_squig_count(unit_id)
	for i in range(total):
		var usage_key = unit_id + ":Bomb Squigs:" + str(i)
		if not _once_per_battle_used.get(usage_key, false):
			_once_per_battle_used[usage_key] = true
			var remaining = get_bomb_squigs_remaining(unit_id)
			print("UnitAbilityManager: Marked Bomb Squig #%d as used for unit %s (%d remaining)" % [i, unit_id, remaining])
			return i
	print("UnitAbilityManager: No unused bomb squigs for unit %s" % unit_id)
	return -1

func has_bomb_squigs(unit_id: String) -> bool:
	"""Check if a unit has unused Bomb Squigs wargear ability.
	Used by MovementPhase to offer once-per-battle mortal wounds after normal move.
	OA-30: Supports multi-squig (Tankbustas have 2, Kommandos have 1)."""
	var remaining = get_bomb_squigs_remaining(unit_id)
	if remaining > 0:
		print("UnitAbilityManager: Unit %s has %d unused Bomb Squig(s)" % [unit_id, remaining])
		return true
	return false

func has_kunnin_infiltrator(unit_id: String) -> bool:
	"""Check if a unit has the Kunnin' Infiltrator ability (Boss Snikrot).
	Used by MovementPhase to offer once-per-battle redeployment instead of Normal move."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Kunnin' Infiltrator":
			if not is_once_per_battle_used(unit_id, "Kunnin' Infiltrator"):
				print("UnitAbilityManager: Unit %s has unused Kunnin' Infiltrator" % unit_id)
				return true
			else:
				print("UnitAbilityManager: Unit %s has Kunnin' Infiltrator but already used this battle" % unit_id)
	return false

func has_deff_from_above(unit_id: String) -> bool:
	"""Check if a unit has the Deff from Above ability (Deffkoptas).
	Used by MovementPhase to offer mortal wounds after Normal move over enemies."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Deff from Above":
			print("UnitAbilityManager: Unit %s has Deff from Above ability" % unit_id)
			return true
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

func has_grot_riggers(unit_id: String) -> bool:
	"""Check if a unit has the Grot Riggers ability (Trukk).
	Used by CommandPhase at start of command for automatic wound regeneration."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Grot Riggers":
			print("UnitAbilityManager: Unit %s has Grot Riggers" % unit_id)
			return true
	return false

func get_grot_riggers_eligible(unit_id: String) -> Dictionary:
	"""Check if a Trukk with Grot Riggers has lost wounds and is eligible to regain 1.
	Returns { eligible: bool, unit_id, unit_name, current_wounds, max_wounds }."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"eligible": false}

	# For vehicles, check the first (and usually only) model
	var models = unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if not model.get("alive", true):
			continue
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds", 1)
		if current_wounds < max_wounds:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			print("UnitAbilityManager: Grot Riggers — %s has %d/%d wounds (eligible)" % [unit_name, current_wounds, max_wounds])
			return {
				"eligible": true,
				"unit_id": unit_id,
				"unit_name": unit_name,
				"model_index": i,
				"current_wounds": current_wounds,
				"max_wounds": max_wounds
			}

	print("UnitAbilityManager: Grot Riggers — unit %s is at full wounds (not eligible)" % unit_id)
	return {"eligible": false}

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

func has_fix_dat_armour_up(unit_id: String) -> bool:
	"""Check if a unit has the Fix Dat Armour Up ability (Big Mek in Mega Armour).
	Used by CommandPhase to offer model revival each command phase while leading."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Fix Dat Armour Up":
			print("UnitAbilityManager: Unit %s has Fix Dat Armour Up" % unit_id)
			return true
	return false

func get_fix_dat_armour_up_unit(character_unit_id: String) -> Dictionary:
	"""Check if the Big Mek's led unit has destroyed Bodyguard models for Fix Dat Armour Up.
	Returns { eligible: bool, bodyguard_unit_id, bodyguard_unit_name, destroyed_count } or ineligible dict."""
	var units = GameState.state.get("units", {})

	# Find the bodyguard unit the Big Mek is leading
	for unit_id in units:
		var unit = units[unit_id]
		var attachment_data = unit.get("attachment_data", {})
		var attached_characters = attachment_data.get("attached_characters", [])
		if character_unit_id in attached_characters:
			# Found the bodyguard unit — check for destroyed models
			var models = unit.get("models", [])
			var alive_count = 0
			var destroyed_count = 0
			for model in models:
				if model.get("alive", true):
					alive_count += 1
				else:
					destroyed_count += 1

			if destroyed_count > 0:
				print("UnitAbilityManager: Fix Dat Armour Up — bodyguard unit %s has %d destroyed model(s)" % [unit_id, destroyed_count])
				return {
					"eligible": true,
					"bodyguard_unit_id": unit_id,
					"bodyguard_unit_name": unit.get("meta", {}).get("name", unit_id),
					"destroyed_count": destroyed_count,
					"alive_count": alive_count,
					"total_models": models.size()
				}
			else:
				print("UnitAbilityManager: Fix Dat Armour Up — bodyguard unit %s is at full strength" % unit_id)
				return {"eligible": false}

	print("UnitAbilityManager: Fix Dat Armour Up — Big Mek %s is not leading any unit" % character_unit_id)
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

# ============================================================================
# OA-34: MEKANIAK (Mek/Big Mek healing + hit buff at end of Movement phase)
# ============================================================================

func has_mekaniak(unit_id: String) -> bool:
	"""Check if a unit has the Mekaniak ability.
	Used by MovementPhase at end of movement to offer healing/buff."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Mekaniak":
			print("UnitAbilityManager: Unit %s has Mekaniak ability" % unit_id)
			return true
	return false

func get_mekaniak_targets(mek_unit_id: String) -> Array:
	"""Get eligible vehicle targets for Mekaniak ability.
	Returns array of { unit_id, unit_name, model_id, model_index, current_wounds, max_wounds, wounds_lost }
	for friendly ORKS VEHICLE models within 3\" that haven't already been selected this turn."""
	var targets = []
	var mek_unit = GameState.state.get("units", {}).get(mek_unit_id, {})
	if mek_unit.is_empty():
		return targets

	# Get Mek position (first alive model)
	var mek_pos = null
	for model in mek_unit.get("models", []):
		if model.get("alive", true) and model.get("position", null) != null:
			mek_pos = model.get("position")
			break

	if mek_pos == null:
		print("UnitAbilityManager: Mek %s has no position — cannot find Mekaniak targets" % mek_unit_id)
		return targets

	var units = GameState.state.get("units", {})
	var mek_owner = mek_unit.get("owner", 0)

	for unit_id in units:
		var unit = units[unit_id]
		# Must be same owner (friendly)
		if unit.get("owner", 0) != mek_owner:
			continue

		# Skip the Mek itself
		if unit_id == mek_unit_id:
			continue

		# Must have ORKS and VEHICLE keywords
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_orks = false
		var has_vehicle = false
		for kw in keywords:
			if kw.to_upper() == "ORKS":
				has_orks = true
			if kw.to_upper() == "VEHICLE":
				has_vehicle = true
		if not has_orks or not has_vehicle:
			continue

		# Once per vehicle per turn — skip if already selected
		if is_mekaniak_used_this_turn(unit_id):
			print("UnitAbilityManager: Mekaniak — vehicle %s already selected this turn, skipping" % unit_id)
			continue

		# Check each alive model for proximity
		for i in range(unit.get("models", []).size()):
			var model = unit.get("models", [])[i]
			if not model.get("alive", true):
				continue

			var model_pos = model.get("position", null)
			if model_pos == null:
				continue

			var dist = _calculate_distance(mek_pos, model_pos)
			if dist <= 3.0:
				var max_wounds = model.get("wounds", 1)
				var current_wounds = model.get("current_wounds", max_wounds)
				targets.append({
					"unit_id": unit_id,
					"unit_name": unit.get("meta", {}).get("name", unit_id),
					"model_id": model.get("id", "m%d" % (i + 1)),
					"model_index": i,
					"current_wounds": current_wounds,
					"max_wounds": max_wounds,
					"wounds_lost": max_wounds - current_wounds
				})
				print("UnitAbilityManager: Mekaniak target found — %s model %s (%d/%d wounds)" % [
					unit.get("meta", {}).get("name", unit_id), model.get("id", ""), current_wounds, max_wounds])

	return targets

func mark_mekaniak_used_this_turn(vehicle_unit_id: String) -> void:
	"""Mark a vehicle as having been selected for Mekaniak this turn."""
	_mekaniak_used_this_turn[vehicle_unit_id] = true
	print("UnitAbilityManager: Marked vehicle %s as Mekaniak target this turn" % vehicle_unit_id)

func is_mekaniak_used_this_turn(vehicle_unit_id: String) -> bool:
	"""Check if a vehicle has already been selected for Mekaniak this turn."""
	return _mekaniak_used_this_turn.get(vehicle_unit_id, false)

func clear_mekaniak_turn_tracking() -> void:
	"""Clear Mekaniak per-vehicle-per-turn tracking. Called at start of each player's Movement phase."""
	if not _mekaniak_used_this_turn.is_empty():
		print("UnitAbilityManager: Clearing Mekaniak turn tracking (%d vehicles tracked)" % _mekaniak_used_this_turn.size())
	_mekaniak_used_this_turn.clear()

static func has_mekaniak_buff(unit: Dictionary) -> bool:
	"""Check if a unit has the Mekaniak +1 Hit buff active.
	Used by RulesEngine when resolving hit rolls."""
	return unit.get("flags", {}).get("mekaniak_buffed", false)

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

func has_outflank(unit_id: String) -> bool:
	"""Check if a unit has the Outflank ability (Warbuggies).
	Used by MovementPhase to allow deployment in opponent's zone from Strategic Reserves."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Outflank":
			print("UnitAbilityManager: Unit %s has Outflank ability" % unit_id)
			return true
	return false

func has_clankin_forward(unit_id: String) -> bool:
	"""Check if a unit has the Clankin' Forward ability (Morkanaut/Gorkanaut).
	Used by MovementPhase to allow moving over non-MONSTER/VEHICLE enemies and terrain ≤4\"."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Clankin' Forward":
			print("UnitAbilityManager: Unit %s has Clankin' Forward ability" % unit_id)
			return true
	return false

func has_stompin_forward(unit_id: String) -> bool:
	"""Check if a unit has the Stompin' Forward ability (Stompa).
	Used by MovementPhase to allow moving over all non-TITANIC models and terrain ≤4\"."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Stompin' Forward":
			print("UnitAbilityManager: Unit %s has Stompin' Forward ability" % unit_id)
			return true
	return false

# ============================================================================
# OA-42: SCATTER! — Grot Tanks reactive move
# ============================================================================

func has_scatter(unit_id: String) -> bool:
	"""Check if a unit has the Scatter! ability (Grot Tanks).
	Used by MovementPhase to offer reactive 6\" Normal move when enemy ends move within 9\"."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name == "Scatter!":
			return true
	return false

func mark_scatter_used_this_turn(unit_id: String) -> void:
	"""Mark a unit as having used Scatter! this turn."""
	_scatter_used_this_turn[unit_id] = true
	print("UnitAbilityManager: OA-42 Marked unit %s as having used Scatter! this turn" % unit_id)

func is_scatter_used_this_turn(unit_id: String) -> bool:
	"""Check if a unit has already used Scatter! this turn."""
	return _scatter_used_this_turn.get(unit_id, false)

func clear_scatter_turn_tracking() -> void:
	"""Clear Scatter! per-unit-per-turn tracking. Called at start of each player's Movement phase."""
	if not _scatter_used_this_turn.is_empty():
		print("UnitAbilityManager: OA-42 Clearing Scatter! turn tracking (%d units tracked)" % _scatter_used_this_turn.size())
	_scatter_used_this_turn.clear()

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

func _is_unit_within_controlled_objective_range(unit_id: String, unit: Dictionary) -> bool:
	"""Check if any alive model in the unit is within range of an objective
	controlled by the unit's owner. Used for Stand Vigil objective-conditional upgrade."""
	var owner = unit.get("owner", 0)
	if owner == 0:
		return false

	var objectives = GameState.state.board.get("objectives", [])
	if objectives.is_empty():
		return false

	# Same control radius used by MissionManager: 3" + 20mm objective marker radius
	var control_radius = Measurement.inches_to_px(3.78740157)

	# Get objective control state from MissionManager
	var obj_control = MissionManager.objective_control_state

	for obj in objectives:
		var obj_id = obj.get("id", "")
		# Only consider objectives controlled by this unit's owner
		if obj_control.get(obj_id, 0) != owner:
			continue

		var obj_pos = obj.get("position")
		if obj_pos == null:
			continue

		# Check if any alive model is within range
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var model_pos = model.get("position")
			if model_pos == null:
				continue
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.x, model_pos.y)
			if model_pos.distance_to(obj_pos) <= control_radius:
				print("UnitAbilityManager: Unit %s is within range of controlled objective %s" % [unit_id, obj_id])
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
		"active_aura_effects": _active_aura_effects.duplicate(true),
		"mekaniak_used_this_turn": _mekaniak_used_this_turn.duplicate(true),
		"scatter_used_this_turn": _scatter_used_this_turn.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_ability_effects = data.get("active_ability_effects", [])
	_applied_this_phase = data.get("applied_this_phase", {})
	_once_per_battle_used = data.get("once_per_battle_used", {})
	_once_per_round_used = data.get("once_per_round_used", {})
	_active_aura_effects = data.get("active_aura_effects", {})
	_mekaniak_used_this_turn = data.get("mekaniak_used_this_turn", {})
	_scatter_used_this_turn = data.get("scatter_used_this_turn", {})
	print("UnitAbilityManager: State loaded — %d active effects, %d aura effects, %d once-per-battle used, %d once-per-round used" % [_active_ability_effects.size(), _active_aura_effects.size(), _once_per_battle_used.size(), _once_per_round_used.size()])

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()
	_once_per_battle_used.clear()
	_once_per_round_used.clear()
	_active_aura_effects.clear()
	_mekaniak_used_this_turn.clear()
	_scatter_used_this_turn.clear()
	print("UnitAbilityManager: Reset for new game")
