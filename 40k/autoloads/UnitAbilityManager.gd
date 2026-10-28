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
# 2. Always-on unit abilities (Stealth, etc.) - apply to the unit itself
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

	# Might is Right — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Might is Right": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "If this unit made a charge move this turn, this model's melee attacks have +3 A and +2 S (Codex: Orks 11e — OrkAbilities11e)."
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

	# Prophet of Da Great Waaagh! — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Prophet of Da Great Waaagh!": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "Aura: friendly ORKS units within 6\" — melee attacks have +1 to hit and +1 to wound (Codex: Orks 11e — OrkAbilities11e)."
	},

	# More Dakka — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"More Dakka": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "This unit's ranged attacks have [IGNORES COVER]; while riled up, [SUSTAINED HITS 1] (Codex: Orks 11e — OrkAbilities11e)."
	},

	# Kustom Force Field — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Kustom Force Field": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "This unit has a 4+ invulnerable save against ranged attacks (Codex: Orks 11e — OrkAbilities11e)."
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

	# Swift Onslaught — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Swift Onslaught": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit can re-roll advance rolls and charge rolls (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# ======================================================================
	# WP-M4c: Codex: Space Marines (11e) - generic datasheet / wargear
	# abilities of the M4c datasheets. The rules live in
	# scripts/codex/space_marines/SMAbilitiesC.gd; these rows only describe
	# them (condition "sm11e" is never evaluated here). Names shared with the
	# M4a/M4b datasheets (Strategic Acumen, Raise the Banner, Codex Adept)
	# get no row here so the sibling packages' rows never collide.
	# ======================================================================
	"Into the Fray": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Captain on Bike: if this unit made a charge move this turn, its melee attacks have [CLEAVE 1]. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Aquilon Optics": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Gladiator Lancer: ranged attacks that target a MONSTER/VEHICLE unit can re-roll one hit roll, one wound roll and one damage roll. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Tempormortis": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Judiciar: this unit (the Judiciar's Attached unit) has Fights First. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Trifold Path of Shadow": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kayvaan Shrike: this unit has Stealth and -3\" detection range. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Echo of the Ravenspire": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kayvaan Shrike: end of your opponent's Fight phase, unengaged: placed in strategic reserves. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Trophy Taker": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kor'sarro Khan: attacks that target a CHARACTER unit re-roll hit rolls of 1 and wound rolls of 1. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"For the Khan!": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kor'sarro Khan: ranged attacks have [ASSAULT]; melee attacks have [LANCE]. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Purgation Run": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Land Speeder: your Shooting phase, when this unit has shot: a normal move of up to D6\"; then no charge this turn. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Full-throttle Assault": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Outrider Squad: charged this turn - Thunder Hammers +1 to hit and [SUSTAINED HITS 1]; other melee +1 D and [SUSTAINED HITS 1]. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Duty Eternal": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Redemptor Dreadnought: attacks with S greater than this unit's T have -1 to wound. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Terror Troops": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Reiver Squad (aura): enemy models within 3\" have -1 OC. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Fearsome Assault": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Reiver Squad: start of the Fight phase - each engaged enemy unit makes a battle-shock roll at -1. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Grapnel Launchers": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Reiver Squad (wargear): moves through all types of model and ignores vertical distance. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Grav-chutes": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Reiver Squad (wargear): this unit has Deep Strike. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Combat Embarkation": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Repulsor: opponent's Charge phase, a friendly unengaged charge target wholly within 3\" can embark. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Executioner": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Repulsor Executioner: ranged attacks vs a unit not below half-strength have +1 to hit. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Veiling Smoke": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Rhino (once per phase): Smokescreen on this unit regardless of other uses this phase, -1 CP. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Seeker of the Unfound": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Vulkan He'stan: picks an objective the first time he is set up; within range of it OC 10, Ld 5+, Feel No Pain 4+. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Forgefather": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Vulkan He'stan: your Shooting phase - a visible enemy within 24\": friendly [MELTA]/[TORRENT] attacks against it +2 S. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Command Squad": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Company Heroes: attacks that target this unit have -1 to wound. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Narthecium": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Apothecary: your Command phase - this unit heals D3+1 wounds. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Honour of the Company": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ancient: this unit has +1 OC. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Hammer of Wrath": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Assault Intercessors with Jump Packs: end of a charge move - D6 per engaged model vs one engaged enemy, 4+ = 1 mortal wound. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Master of Shadows": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Aethon Shaan: your Command phase - a friendly ADEPTUS ASTARTES INFANTRY unit re-rolls charge rolls until your next Command phase. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Blackwing Mantle": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Aethon Shaan (once per phase, per army): Heroic Intervention on this unit regardless of other uses, -1 CP. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Cold and Calculating": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Caanok Var: when selected to shoot/fight - [LETHAL HITS] vs MONSTER/VEHICLE or [SUSTAINED HITS 1] vs others (both with the tactical doctrine). (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Cerebrex Logic Engine": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Caanok Var: Declare Battle Formations - a friendly ADEPTUS ASTARTES INFANTRY unit has Scouts 6\". (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Spear of Chogoris": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Suboden Khan: ranged [ASSAULT]; advance and still charge; +1 advance and charge rolls with the assault doctrine. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Skilled Riders": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Suboden Khan: this unit has Mobile. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Captain of the Honour Guard": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Cato Sicarius: with a Marneus Calgar in the army, Leader becomes Support. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Knight Champion of Macragge": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Cato Sicarius (once per phase, per army): opponent's Movement phase, an enemy ends a move within 8\" - normal move up to 6\". (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Honour or Death": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Cato Sicarius: Heroic Intervention on this unit is -1 CP. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Glory of Ultramar": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Victrix Honour Guard: opponent's Shooting phase, a model of this unit was destroyed - surge move of up to D6\". (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Honour Guard of Macragge": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Victrix Honour Guard: attacks that target this unit have -1 to wound. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Banner of Macragge": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Victrix Honour Guard (wargear): end of your Movement phase, controlled objective secured; once per battle, selected to fight: melee +1 A and S. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Press the Attack": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Captain Titus: melee [SUSTAINED HITS 1] vs non-MONSTER/VEHICLE ([SUSTAINED HITS 1] vs all with the assault doctrine). (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Righteous Fury": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Captain Titus (once per battle, per army): Fight phase - melee +1 S; when fought, heals D3 (2D3 after a kill). (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Honour of Ultramar": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Captain Titus: Fight phase, destroyed before his unit fought - 2+ it stays until his unit has fought. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Strategium Command": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Wardens of Ultramar: after deployment, redeploy up to three ADEPTUS ASTARTES units (reserves allowed). (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Overlapping Destruction": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Eradicator Squad with Heavy Bolters: your Shooting phase - Heavy Bolters vs one enemy unit have [BLAST 1]. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Master Tactician": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Marneus Calgar: your Movement phase - a visible friendly ADEPTUS ASTARTES unit within 9\" gets a combat doctrine until your next Command phase. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Thunderhawk Insertion": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Marneus Calgar: Declare Battle Formations - a friendly GRAVIS/PHOBOS/TACTICUS unit has Deep Strike. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Aggressive Reconnaissance": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Invader ATVs: your Shooting phase - ranged attacks vs an enemy more than 6\" from other enemies +1 to wound. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Veteran Bodyguard": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kaius Konorius: while attached, other CHARACTER models in this unit have Feel No Pain 4+. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Calgar's Champion": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Kaius Konorius: this model's attacks vs a CHARACTER unit re-roll hit rolls of 1 and wound rolls of 1. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	"Total Obliteration": {
		"condition": "sm11e",  # WP-M4c: Space Marines (11e) rule lives in SMAbilitiesC.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Eradicator Squad with Melta Rifles: ranged attacks can re-roll damage rolls. (Codex: Space Marines 11e \u2014 SMAbilitiesC)."
	},
	# ======================================================================
	# WP-S4: Codex: Space Marines (11e) — Space Wolves datasheet / wargear
	# abilities. The rules live in scripts/codex/space_wolves/SWAbilities11e.gd;
	# these rows only describe them (condition "sw11e" is never evaluated here).
	# ======================================================================
	"High King of Fenris": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle round, in your Movement phase: a friendly SPACE WOLVES unit in strategic reserves ingresses as if the battle round were one higher (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Guile of the Wolf": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "At the start of each phase, the assault, devastator and tactical doctrines are active for this unit (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Battle-lust": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "If this unit made a charge move this turn, this model's melee attacks have +2 A (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"War Howl": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Leading Blood Claws: melee +1 S and [SUSTAINED HITS 1]; leading Wolf Guard Headtakers: advance and still charge (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Wind Walker": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's ranged attacks have [ASSAULT]; its advance rolls can be changed to a 6 (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"High Rune Priest": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psyker level 3 (Librarius): Murderous Hurricane, Storm Caller, Tempest's Wrath (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Murderous Hurricane": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Movement phase: a visible enemy unit within 12\" cannot make snap-shooting attacks this turn (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Storm Caller": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, when an enemy unit targets this unit: -3\" detection range until the end of the phase (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Tempest's Wrath": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Shooting phase: a visible enemy unit within 18\" is suppressed (-1 to hit) until the start of your next turn (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Slayer's Oath": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Start of the first battle round: an enemy CHARACTER/MONSTER/VEHICLE unit becomes the slayer's oath \u2014 attacks against it ignore BS/WS and hit-roll modifiers (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Oathbound": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Melee attacks +1 to hit; +1 to hit and wound against the slayer's oath (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Legendary Tenacity": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit with S greater than its T have -1 to wound (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Ancient Tactician": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per turn, per army: a stratagem that targets this unit is -1 CP (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Berserk Charge": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit can advance and still declare a charge (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Old Greymanes": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Declare Battle Formations: split this unit into two units, as equal as possible (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Cunning Hunters": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fight phase, within range of an objective: melee +1 S and +1 AP (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Gift of the Iron Wolf": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase, start or end of this unit's move: a friendly SPACE WOLVES VEHICLE model within 3\" heals D3 and ignores hit/wound modifiers until your next Movement phase (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Iron Priest": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While within 3\" of a friendly SPACE WOLVES VEHICLE unit, this model has Lone Operative (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Judgement of the Omnissiah": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model's attacks that target an enemy unit engaged with a friendly SPACE WOLVES VEHICLE can re-roll wound rolls (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Savage Frenzy": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Engaged enemy units (not MONSTER/VEHICLE) must fall back with desperate escape (-1 to hazard rolls if battle-shocked) (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Death Totem": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's melee attacks can re-roll hit rolls of 1 (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Murder-maker": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fight phase: a friendly WULFEN model within 6\" that is destroyed before its unit fought stays on a 4+ until its unit has fought (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Bestial Fury": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit can re-roll advance rolls and charge rolls (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Force of Untamed Destruction": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model cannot be your WARLORD (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Champion of the Kingsguard": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model's attacks that target a CHARACTER unit re-roll hit rolls of 1 and wound rolls of 1 (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Anvil of Endurance": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fight phase: a model of this unit destroyed before it fought stays on a 4+ until the unit has fought (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Rugged Resilience": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit with S greater than its T have -1 to wound (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Storm Shield": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Wolf Guard Terminators / Battle Leader: the bearer has +1 W; Thunderwolf Cavalry / Headtakers: the bearer has a 4+ invulnerable save (applied at army load) (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Thunderous Charge": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "If this unit made a charge move this turn, its melee attacks have +1 S and +1 D (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Predatory Instinct": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle round, opponent's Movement phase: an enemy unit ends a move within 8\" \u2014 normal move of up to D6\" (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Hunting Hounds": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Within 6\" of a friendly SPACE WOLVES CHARACTER (not WULFEN), not battle-shocked: +1 OC (Hunting Wolf models) (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Fervour of the Ancients": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Friendly SPACE WOLVES units within 6\" have +1 to advance rolls and charge rolls (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Blizzard Shield": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model has a 4+ invulnerable save (applied at army load) (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Healing Balms": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "In your Command phase, this unit heals D3+1 wounds (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Litany of Hate": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's melee attacks have [LANCE] (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Tempered Ferocity": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's attacks have [SUSTAINED HITS 1]; re-roll hit rolls of 1 against an enemy unit within 6\" (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Heroic Last Stand": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fight phase: this model destroyed before its unit fought stays on a 2+ until the unit has fought (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Headhunters": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Start of the first battle round (and when it is destroyed): select a quarry \u2014 attacks against it have [DEVASTATING WOUNDS] and [PRECISION] (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Let Loose the Wolves": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Declare Battle Formations: split into a Wolf Guard Headtakers unit and a Hunting Wolves unit (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Hammer Blow": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fight phase, when this unit has fought: an enemy MONSTER/VEHICLE unit it hit is suppressed (-1 to hit) until the start of your next turn (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Violent Fury": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Equipped with two melee weapons: this unit's melee attacks have [TWIN-LINKED] (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Bestial Rage": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Opponent's Shooting phase, after an enemy unit shot and this unit lost a wound: surge move of up to D6+1\" (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Deadly Stalkers": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target an enemy unit more than 6\" from any other enemy unit have +1 to wound (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},
	"Haywire Mine": {
		"condition": "sw11e",  # WP-S4: Space Wolves (11e) rule lives in SWAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, your Shooting phase: a visible enemy unit within 6\" \u2014 D6 2+: D3 mortal wounds (2D3 vs a VEHICLE) (Codex: Space Marines 11e, Space Wolves \u2014 SWAbilities11e)."
	},

	# WP-M4a: Codex: Space Marines (11e) — generic datasheet / wargear abilities
	# of the M4a datasheets. The rules live in
	# scripts/codex/space_marines/SMAbilitiesA.gd; these rows only describe
	# them (condition "sm11e_m4a" is never evaluated here).
	# ======================================================================
	"Vivispectral Analysis Targeting": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's attacks have [LETHAL HITS] against non-VEHICLE units (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Assault Ramp": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase, when this unit ends a normal move: embarked units can make an assault disembark move (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Power of the Machine Spirit": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's ranged attacks can re-roll one hit roll and one wound roll (per phase) (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Fury of the Machine Spirit": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a unit within 12\" have [LETHAL HITS] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Bladeguard": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per turn, Fight phase (selected to fight / targeted): melee +1 to hit, or attacks that target this unit -1 to hit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Strategic Acumen": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Command phase: select one combat doctrine to be active for this unit until your next Command phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Finest Hour": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, selected to fight: this model's melee attacks have +3 A and [DEVASTATING WOUNDS] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Relic Shield": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model has +1 W (applied at army load when the roster takes it) (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Priority Target Identified": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, your Command phase: a terrain feature is identified — enemy units within it have +3\" detection range until the end of the turn (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Evade and Survive": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per phase, opponent's Movement phase: an enemy unit ends a move within 8\" — normal move of up to D3+3\" (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Librarian": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psyker level 1 (Librarius): the psychic abilities of this datasheet (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Psychic Hood": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has Feel No Pain 4+ against psychic attacks (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Might of Heroes": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, Fight phase: this unit's melee attacks have +2 S this phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Thunderous Force": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Shooting phase: this unit's ranged attacks have +6\" Range this phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Angel's Wrath": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has +1 to advance rolls and charge rolls (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Sentinel Protocols": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Fire Overwatch on this unit regardless of other uses (once per phase): its snap-shooting attacks hit on unmodified 4+ (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Drop Pod Assault": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Starts in strategic reserves; can ingress in your first Movement phase; embarked units disembark (more than 8\" from enemy units) as it is set up (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Deployment Complete": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once set up and emptied, units cannot embark within this unit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Ballistus Strike": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target an enemy unit within 24\" have [SUSTAINED HITS 1] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Catechism of Fire": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Selected to shoot: a visible enemy unit — this unit's ranged attacks that target it have [DEVASTATING WOUNDS] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Exhortation of Rage": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "At or below half-strength: this unit's melee attacks re-roll wound rolls (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Hammerstrike": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target an enemy unit within a terrain area have [SUSTAINED HITS 1] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Zealous Fortitude": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has Feel No Pain 4+ against mortal wounds (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Teleport Homer": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle: a Teleport Homer token — Rapid Ingress -1 CP, set up within 3\" of it and not within 8\" of an enemy unit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Terminatus Assault": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Charged this turn: Lightning Claws [SUSTAINED HITS 1] vs non-MONSTER/VEHICLE, Thunder Hammers vs MONSTER/VEHICLE (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Shrouding": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, when an enemy unit targets this unit: attacks that target it have -1 to hit until the end of the phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Soul Sight": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Shooting phase: ranged attacks that target the selected enemy unit have [IGNORES COVER] (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Hailstrike": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Has shot: an enemy unit hit — friendly ADEPTUS ASTARTES ranged attacks that target it have [IGNORES COVER] this phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Meteoric Descent": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Made an ingress move this turn: this unit's ranged attacks have +1 to hit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Parabolic Jetleap": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "End of your opponent's Fight phase, unengaged: place this unit in strategic reserves (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Driven from Cover": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Has shot: an enemy unit hit — friendly ADEPTUS ASTARTES ranged attacks that target it have [IGNORES COVER] this phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Master of the Forge": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase, start or end of this unit's move: a friendly AA VEHICLE model within 3\" heals 3 and ignores BS/hit/wound modifiers until your next Movement phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Rites of Tempering": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit with S greater than its T have -1 to wound (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Iron Father": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Within 3\" of a friendly ADEPTUS ASTARTES VEHICLE unit: Lone Operative (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Unstoppable Valour": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "You can re-roll charge rolls for this unit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Brutalis Charge": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per phase: Crushing Impact on this unit regardless of other uses, -1 CP (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Codex Adept": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "The assault, devastator and tactical doctrines are active for this unit (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Primarch of the XIII": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Aura: friendly ADEPTUS ASTARTES units within 6\" re-roll hit rolls of 1 and wound rolls of 1 (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Author of the Codex": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase: a visible friendly AA unit within 12\" gets an additional combat doctrine until your next Command phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Leader of Astartes": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Within 3\" of a friendly ADEPTUS ASTARTES INFANTRY unit: Lone Operative (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Aerial Assault": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase, ends a normal move: embarked units whose models all have Deep Strike can make an assault disembark move (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Thunderhawk Cluster Bombs": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ends a normal/advance move: an enemy unit moved over — six D6, each 3+ is 1 mortal wound (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Techmarine": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Within 3\" of a friendly ADEPTUS ASTARTES VEHICLE unit: Lone Operative (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Blessings of the Omnissiah": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Movement phase, start or end of this unit's move: a friendly AA VEHICLE model within 3\" heals D3 and ignores hit/wound modifiers until your next Movement phase (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Vanguard Assault": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Charged this turn: this unit's melee attacks have +1 A (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Combat Shield": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model has a 5+ invulnerable save (applied at army load) (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},
	"Forward Assault Warsuit": {
		"condition": "sm11e_m4a",  # WP-M4a: rule lives in SMAbilitiesA.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Start of the first battle round: an enemy unit is this unit's mark — re-roll wound rolls of 1 against it (re-selected when destroyed) (Codex: Space Marines 11e \u2014 SMAbilitiesA)."
	},

	# ======================================================================
	# ======================================================================
	# WP-M4b: Codex: Space Marines (11e) datasheet abilities of the M4b datasheets.
	# The rules live in scripts/codex/space_marines/SMAbilitiesB.gd; these rows
	# only describe them (condition "sm11e" is never evaluated here). Names the
	# M4b datasheets share with other packages (Strategic Acumen, Raise the
	# Banner, Teleport Homer, Assault Ramp, Librarian, Psychic Hood, Shield Dome)
	# get no row here: the integrator adds one shared row.
	# ======================================================================
	"Bolter Discipline": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Shooting phase: ranged attacks +1 to hit while this unit or the target is within range of an objective (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Tactical Mainstay": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Engaged / battle-shocked does not prevent starting an action; starting an action does not prevent shooting (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Divinator-class Auspexes": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per phase, your Shooting phase, a friendly ADEPTUS ASTARTES unit is selected to shoot: a visible enemy unit within 18\" is scanned (ranged attacks vs it re-roll hit rolls of 1) (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Flexible Asset": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "An advance / fall-back move does not prevent this unit from being eligible to start an action (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Deeds of Legend": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While within range of an objective: melee +1 A (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Refuse to Yield": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks allocated to this model have -1 D (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Spiritual Leader": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle round, start of any phase: a friendly battle-shocked ADEPTUS ASTARTES unit within 6\" is no longer battle-shocked (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Unyielding in the Face of the Foe": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While controlling an objective: +1 to save rolls (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Fury of the First": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target a unit within 9\" have +1 AP (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Demi-company Commander": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per turn: when a friendly Captain uses Strategic Acumen, the selected doctrine is active for this unit too (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Tactical Precision": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's attacks have [LETHAL HITS] against non-MONSTER/VEHICLE units (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Targeted Intercession": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "If this unit made a charge move this turn: melee +1 S and +1 AP (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Thunderstrike": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a MONSTER/VEHICLE unit have +1 to wound (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Shattered Defences": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Shooting phase, when this unit has shot: an enemy MONSTER/VEHICLE unit hit - friendly ADEPTUS ASTARTES ranged attacks vs it +1 AP (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Chief Librarian": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psyker level 3 (Librarius): Prescience, Telepathic Assault (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Hood of Hellfire": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 4+ against psychic attacks and mortal wounds (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Prescience": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 2, your Movement phase: +1 Sv until the start of your next turn (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Telepathic Assault": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Shooting phase: a visible enemy unit within 24\" suffers 2D3 mortal wounds (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Reaping Tally": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a non-MONSTER/VEHICLE unit have +1 AP (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Chameleoline Cloaks": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has -3\" detection range (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Special-issue Optics and Ammunition": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "When selected to shoot: ranged attacks [IGNORES COVER], or an enemy unit within 24\" has +6\" detection range until this unit has shot (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Priority Target Acquisition": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a unit within 12\" have +1 S (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Rites of Thermal Appeasement": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "+1 to hazard rolls for its Plasma Incinerator and Plasma Pistol weapons (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Close-quarters Firestorm": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target an enemy unit within 9\" have +1 S (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Lord of the Pyroclasts": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "An enemy unit engaged with this unit has -1 OC (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Unto the Anvil": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Melee attacks re-roll wound rolls of 1 (assault doctrine active: re-roll wound rolls) (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Rampart": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle (per army), start of any phase: this model has a 2+ invulnerable save until the end of the phase (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Icon of Obstinacy": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit have -1 to hit (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Wrath of the Machine Spirit": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a unit within 12\" have [DEVASTATING WOUNDS] against non-MONSTER/VEHICLE units (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Veteran Marksmen": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks re-roll hit rolls of 1 (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Veil of Time": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, selected to advance: the advance roll is changed to a 6 (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Force Dome": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic level 1, your Movement phase: 4+ invulnerable save until the start of your next turn (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Targeter Optics": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Ranged attacks that target a visible enemy unit have [IGNORES COVER] (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Siege Captain": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This model's attacks that target a FORTIFICATION/MONSTER/VEHICLE unit have +2 S, AP and D (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Signum Array": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Shooting phase: a visible enemy unit within 18\" cannot have the benefit of cover (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Rapid Disembarkation": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "After this unit's advance move in your Movement phase, embarked units can make a shock disembark move (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Orbital Comms Array": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Wargear: this unit has Scouts 6\" (applied at army load) (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Never Shall the Standard Fall": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While within range of an objective: attacks with S greater than this unit's T have -1 to wound (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Suppression Fire": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Shooting phase, when this unit has shot: an enemy unit hit by its Twin Macro-accelerator Cannon is suppressed (-1 to hit) until the start of your next turn (Codex: Space Marines 11e, SMAbilitiesB)."
	},
	"Tactical Fluidity": {
		"condition": "sm11e",  # WP-M4b: Codex: Space Marines (11e) rule lives in SMAbilitiesB.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle round: after shooting (unengaged) a normal move of up to D6\"; or at the end of your opponent's Fight phase (engaged) a fall-back move of up to 6\" (Codex: Space Marines 11e, SMAbilitiesB)."
	},

	# ======================================================================
	# ALWAYS-ON UNIT ABILITIES
	# ======================================================================

	# Stand Vigil — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Stand Vigil": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While this unit or its target is within range of an objective, its attacks have [LETHAL HITS: non-MONSTER/VEHICLE] (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Vengeful Surge — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Vengeful Surge": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, in your opponent's Shooting phase, when an enemy unit has shot and a model in this unit lost a wound: a surge move of up to D6+2\" (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Praesidium Shield — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Praesidium Shield": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Shield-Captain: attacks allocated to this model have -1 D. Sentinel Guard Sodality: attacks that target this unit with S greater than its T have -1 to wound (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Archeotech Teleport-shunter — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Archeotech Teleport-shunter": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, in your Movement phase, if unengaged and not selected to move: strategic reserves, and it must make an ingress move this phase (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Living Fortress — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Living Fortress": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit have -1 AP (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Vexilla — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Vexilla": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has +1 OC (army list) and can ignore modifiers to its Ld (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Slayer of Tyrants — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Slayer of Tyrants": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This unit's melee attacks that target a unit with a higher T have +1 to wound (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Unyielding Ancient — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Unyielding Ancient": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Attacks that target this unit with S greater than its T have -1 to wound (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Destructor Optics — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Destructor Optics": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "This unit's ranged attacks that target a non-MONSTER/VEHICLE unit have +1 AP (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Repulsor Suspensor Technology — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Repulsor Suspensor Technology": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per phase, in your opponent's Shooting phase, when an enemy unit has shot and this unit lost a wound: a normal move of up to D6\" (unengaged) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Assault Vehicle — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Assault Vehicle": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,  # WP-C7: no shock disembark move in the core rules (custodes_abilities_audit.md)
		"description": "In your Movement phase, when this unit ends an advance move, units embarked within it can make a shock disembark move (not implemented: the core rules in docs/ define no shock disembark move) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Mobile Hunter — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Mobile Hunter": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Your Shooting phase, when this unit has shot: a normal move of up to D6\"; not eligible to declare a charge until the end of the turn (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Assault Dropship — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Assault Dropship": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "A friendly ADEPTUS CUSTODES unit that tactical-disembarks from this unit can advance and still declare a charge (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Infernus Firebombs — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Infernus Firebombs": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "End of your opponent's Fight phase: one visible enemy unit within 24\" — ranged attacks vs it [IGNORES COVER] until the end of your next turn; D6 per model, 6 = 1 mortal wound (max 6) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Sword of the Throne — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Sword of the Throne": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "At the start of the first battle round (and each time it is destroyed) select one enemy unit as this model's mark: its attacks vs the mark have +1 to wound (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Seeker's Instincts — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Seeker's Instincts": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has +2\" M and can re-roll advance rolls and charge rolls (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Corner the Quarry — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Corner the Quarry": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Enemy non-MONSTER/VEHICLE units engaged with this unit must use desperate escape to fall back (-1 to those hazard rolls while battle-shocked) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Impenetrable Defence — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Impenetrable Defence": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While this unit or its target is within range of an objective, its attacks have [SUSTAINED HITS 1: non-MONSTER/VEHICLE] (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Take Wing — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Take Wing": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "End of your opponent's Fight phase, if unengaged: place this unit in strategic reserves (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Neutronium Cascade Mine — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Neutronium Cascade Mine": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, at the start of any phase: one enemy unit within 3\" — D6, on a 2+ D3 mortal wounds (2D3 vs VEHICLE/MONSTER) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Swift Ruin — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Swift Ruin": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per phase, per army: Rapid Ingress can target this unit regardless of other uses, at -1 CP, without blocking other uses (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Death Blow — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Death Blow": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "If this unit made a charge move this turn, its melee attacks have +1 AP (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Deft Parry — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Deft Parry": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Melee attacks that target this unit have -1 to hit (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Reap a Terrible Tally — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Reap a Terrible Tally": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit's attacks that target an INFANTRY unit can re-roll hit rolls of 1 and wound rolls of 1 (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Strike from the Skies — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Strike from the Skies": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "In your Shooting phase, if this unit made an ingress move this turn, its ranged attacks can re-roll hit rolls (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# SUPREME COMMANDER — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"SUPREME COMMANDER": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "If this model is in your army, it must be your WARLORD (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Codex: Adeptus Custodes (11e) ARMY RULES — resolved by
	# scripts/codex/custodes/CustodesKatah.gd (WP-C3), not by flags from this
	# table: Daughters of the Abyss / Psychic Null and Aegis of the Emperor are
	# read by RulesEngine.get_unit_fnp_vs on every damage / mortal-wound path,
	# Martial Ka'tah + Master of Ka'tahs ride the stratagem windows, Aquila
	# Commander resolves at the start of the battle round.
	"Daughters of the Abyss": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 3+ against psychic attacks; Psychic Null (Aura): friendly ADEPTUS CUSTODES units within 6\" have Feel No Pain 5+ against psychic attacks (CustodesKatah.gd)"
	},
	"Aegis of the Emperor": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 5+ against mortal wounds (CustodesKatah.gd)"
	},
	"Martial Ka'tah": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Readied at the start of your Command phase; one ka'tah ability per readying, offered in its window (CustodesKatah.gd)"
	},
	"Master of Ka'tahs": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle round, per unit: if this unit is not readied, it is readied — offered on the ka'tah cards (CustodesKatah.gd)"
	},
	"Aquila Commander": {
		"condition": "passive",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Start of the battle round: +1CP if this model is your WARLORD (CustodesKatah.gd)"
	},

	# Custodes Trajann Valoris — Feel No Pain 5+ (permanent, unconditional)
	"Feel No Pain": {
		"condition": "always",
		"effects": [{"type": "grant_fnp", "value": 5}],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Feel No Pain 5+ — each time this model would lose a wound, roll D6: on 5+ that wound is not lost"
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

	# Fuel-mixa Grot — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Fuel-mixa Grot": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has +1 to advance rolls (Codex: Orks 11e — OrkAbilities11e)."
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

	# Callidus Assassin — end-of-fight-phase Fall Back + end-of-opponent-turn vanish/reappear
	# Handled directly by FightPhase and ScoringPhase (not via effect flags)
	"Acrobatic Escape": {
		"condition": "always",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "End of Fight phase: Fall Back D6\" if in engagement. End of opponent's turn: vanish if not within 3\" of enemies, reappear next Movement phase >9\" from enemies."
	},

	# Full Throttle — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Full Throttle": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Command phase: select one Throttlerokkit Shokka Engine ability (Turbo Engine / Shokk Attack Engine); this unit has it until the start of your next Command phase (Codex: Orks 11e — OrkAbilities11e)."
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

	# Kunnin' Infiltrator — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Kunnin' Infiltrator": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "End of your opponent's Fight phase: if each model in this unit is hidden and unengaged, place it in strategic reserves (Codex: Orks 11e — OrkAbilities11e)."
	},

	# Deff from Above — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Deff from Above": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "In your Shooting phase, if this unit made an ingress move this turn, its ranged attacks have +1 to hit (Codex: Orks 11e — OrkAbilities11e)."
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

	# Sanctified Flames — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Sanctified Flames": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Your Shooting phase, when this unit has shot: select one enemy unit hit — it makes a battle-shock roll (-1 if PSYKER) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
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

	# Ork Kommandos — Taktikal Know-wotz (Codex: Orks 11e; re-key of the
	# pre-codex Patrol Squad): split into two 5-model units (one keeps Bomb
	# Squig, the other Found 'Em!). GameState.split_unit_at_deployment.
	"Taktikal Know-wotz": {
		"condition": "deployment",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Split into two 5-model units: one has Bomb Squig, the other Found 'Em! (GameState.split_unit_at_deployment)"
	},

	# Bomb Squigs — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Bomb Squigs": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per turn, twice per battle: after a normal move, one visible enemy unit within 12\" — D6, on a 3+ it suffers D3 mortal wounds (Codex: Orks 11e — OrkAbilities11e)."
	},

	# Sweeping Advance — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Sweeping Advance": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, at the end of the Fight phase, if this unit was eligible to fight: a normal move (unengaged) or a fall-back move (engaged) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
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

	# Advanced Firepower — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Advanced Firepower": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": false,  # WP-C7: not implemented yet (single-die re-rolls; see custodes_abilities_audit.md)
		"description": "This unit's ranged attacks that target a MONSTER/VEHICLE unit can re-roll one hit roll, one wound roll and one damage roll (Codex: Adeptus Custodes 11e) — NOT IMPLEMENTED yet."
	},

	# Captain-General — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Captain-General": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"aura_range": 6.0,
		"aura_target": "friendly",
		"implemented": true,
		"description": "Aura: friendly ADEPTUS CUSTODES units (excluding MONSTER/VEHICLE) within 6\" can re-roll hit rolls of 1 and wound rolls of 1 (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Moment Shackle — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Moment Shackle": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, per army, at the start of any phase: until the end of the phase the Watcher's Axe has +3 A, or this model has a 3+ invulnerable save (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Purity of Execution — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Purity of Execution": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Your Shooting phase: select one visible enemy unit within 18\" — it is detected (+3\" detection range) (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Quicksilver Execution — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Quicksilver Execution": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "If this unit made a charge move this turn, its melee attacks have [SUSTAINED HITS 1] (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Callidus Assassin — aura: +1 CP to enemy stratagems within 12"
	# Resolved directly in StratagemManager.get_lord_of_deceit_cp_increase().
	"Lord of Deceit (Aura)": {
		"condition": "aura",
		"effects": [],
		"aura_range": 12.0,
		"aura_target": "enemy",
		"target": "enemy_units",
		"attack_type": "all",
		"implemented": true,
		"description": "Enemy stratagems targeting units within 12\" of this model cost +1 CP"
	},

	# Inquisitor Draxus — +1 to Hit vs non-IMPERIUM/CHAOS while leading
	# Resolved directly in RulesEngine.has_xenos_hunter_vs_target().
	"Xenos Hunter": {
		"condition": "while_leading",
		"effects": [],
		"target": "led_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "While leading, +1 to Hit rolls when targeting non-IMPERIUM/CHAOS enemies"
	},

	# Inquisitor Draxus — command phase targeting restriction (psychic)
	# Resolved in CommandPhase.
	"Psychic Veil (Psychic)": {
		"condition": "start_of_command",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_turn": true,
		"description": "Command phase: roll D6. On 1, D3 mortal wounds. On 2+, unit can only be targeted by ranged within 18\" until next Command phase."
	},

	# Inquisitor Draxus — can embark in bodyguard's transport while leading
	# N/A for current army list (no transports for led units).
	"Authority of the Inquisition": {
		"condition": "while_leading",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": false,
		"description": "While leading, can embark in any TRANSPORT the bodyguard can. N/A: no transports in current list."
	},

	# Dread Foe — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Dread Foe": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This unit's melee attacks that target a non-MONSTER/VEHICLE unit have +1 AP (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Guardian Eternal — Codex: Adeptus Custodes (11e) datasheet ability; the rule is in
	# CustodesAbilities.gd (WP-C7), this row only describes it.
	"Guardian Eternal": {
		"condition": "cus11e",  # WP-C7: Codex: Adeptus Custodes (11e) rule lives in CustodesAbilities.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "Ranged attacks that target this unit have -1 D (Codex: Adeptus Custodes 11e — CustodesAbilities)."
	},

	# Space Marines Intercessor Squad — sticky objectives
	# Same mechanic as Ork Boyz "Get Da Good Bitz" — resolved by MissionManager
	# WP-M4b: 10e index ability. No Codex: Space Marines (11e) datasheet carries it
	# (the 11e Intercessor Squad has Bolter Discipline / Tactical Mainstay; the
	# 11e "secured" rule is Raise the Banner — SMAbilitiesB.gd); retired for an
	# 11e Space Marine army in has_sticky_objectives_ability below.
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
	# WP-M4b: 10e index ability, on no Codex: Space Marines (11e) datasheet; its
	# "on_shooting_selection" condition is never evaluated by _apply_unit_abilities,
	# so it applies to nothing (kept only as the 10e description).
	"Target Elimination": {
		"condition": "on_shooting_selection",
		"effects": [{"type": "plus_attacks", "value": 2}],
		"target": "unit",
		"attack_type": "ranged",
		"target_weapon_names": ["Bolt rifle", "Auto bolt rifle", "Stalker bolt rifle"],
		"implemented": true,
		"description": "+2 Attacks for bolt rifles when targeting a single enemy unit"
	},

	# Space Marines Tactical Squad — unit splitting at deployment.
	# Same mechanic as Kommandos "Patrol Squad". Data-layer helper landed in
	# GameState.split_unit_at_deployment (T-026). Marked implemented:true
	# because the rules-engine path is callable; UI prompt during deployment
	# is the remaining UX wedge tracked in AUDIT_REPORT under T-026.
	"Combat Squads": {
		"condition": "deployment",
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "At deployment, can split into two 5-model units via GameState.split_unit_at_deployment"
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

	# Fix Dat Armour Up — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Fix Dat Armour Up": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, in your Command phase: this unit heals 3 wounds (Codex: Orks 11e — OrkAbilities11e)."
	},

	# ======================================================================
	# PHASE-TRIGGERED ABILITIES (Movement phase etc.)
	# ======================================================================

	# Da Jump — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Da Jump": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psychic (level 1, once per army per battle round), Movement phase: psychic roll — on a 1 battle-shocked; place this unit in strategic reserves, it has Deep Strike (Codex: Orks 11e — OrkAbilities11e)."
	},

	# ======================================================================
	# LEADER ABILITIES — Weapon modifiers based on unit size
	# ======================================================================

	# Waaagh! Energy — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Waaagh! Energy": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Psyker level 1: this model has the psychic abilities Da Jump and Warpath (Codex: Orks 11e — OrkAbilities11e)."
	},

	# ======================================================================
	# COMBAT ABILITIES — Weapon stat modifiers based on targeting conditions
	# ======================================================================

	# ======================================================================
	# WARGEAR ABILITIES — Ammo Runt (OA-10)
	# ======================================================================

	# ======================================================================
	# WARGEAR ABILITIES — Pulsa Rokkit (OA-31), Grot Oiler (OA-32)
	# ======================================================================

	# Pulsa Rokkit — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Pulsa Rokkit": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "Once per battle, when selected to shoot: select one enemy MONSTER/VEHICLE unit within 24\" — this unit's attacks that target it have +1 AP and [LETHAL HITS] (Codex: Orks 11e — OrkAbilities11e)."
	},

	# ======================================================================
	# WARGEAR ABILITIES — Shooty Power Trip (OA-37)
	# ======================================================================

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

	# Blastajet Force Field — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Blastajet Force Field": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit has a 5+ invulnerable save (Codex: Orks 11e — OrkAbilities11e)."
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

	# Krumpin' Time — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Krumpin' Time": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "In the Fight phase, while this unit is riled up, its attacks have +1 to hit (Codex: Orks 11e — OrkAbilities11e)."
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

	# Big an' Shooty — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Big an' Shooty": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "In your Shooting phase, this unit's ranged attacks can re-roll hit rolls of 1 (Codex: Orks 11e — OrkAbilities11e)."
	},

	# Big an' Stompy — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Big an' Stompy": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This unit's melee attacks can re-roll hit rolls of 1 (Codex: Orks 11e — OrkAbilities11e)."
	},

	# ======================================================================
	# Issue #374 — P0 enhancements. The 10e Custodes Shield Host entries
	# (Auric Mantle, Castellan's Mark, From the Hall of Armouries,
	# Panoptispex) were retired with that detachment in WP-C46 (the codex
	# enhancements live in scripts/codex/custodes/CustodesEnhancements.gd);
	# the Ork War Horde rows moved to OrkEnhancements11e.gd with WP-O5.
	# Registered with `condition: "enhancement"` so the existing
	# _apply_enhancement_abilities pipeline picks them up via
	# unit.meta.enhancements[]. Each enhancement bearer must be a CHARACTER
	# (validated at army-build).
	# ======================================================================

	# ======================================================================
	# Codex: Orks (11e) ENHANCEMENTS (WP-O5) — the 38 codex enhancements of
	# the 15 codex detachments (War Horde ... Wurrband) are implemented in
	# scripts/codex/orks/OrkEnhancements11e.gd; _apply_enhancement_abilities
	# skips them. The 10e enhancements those detachments no longer have
	# (Supa-Cybork Body, Skwad Leader, Mek Kaptin, Gob Boomer, Raucous
	# Warcaller, Bloodthirsty Belligerence, Skrag Every Stash!, Fasta Than
	# Yooz, Speed Makes Right, Squig-hide Tyres, Wazblasta, Gitfinder Googlez,
	# Press It Fasta!, Runnin' Boots, Blitzkaptin, Supercharged Squig Oil,
	# Tuff Git, ...) are gone. The rows below serve the non-codex detachments
	# the engine still has (More Dakka!, Rollin' Deff, Freebooter Krew).
	# ======================================================================

	# ======================================================================
	# MORE DAKKA! ENHANCEMENT ABILITIES
	# ======================================================================

	# Da Gobshot Thunderbuss — bearer's ranged weapons gain [DEVASTATING
	# WOUNDS] and [HAZARDOUS]. Same unit-wide approximation as Headwoppa's
	# Killchoppa (per-model weapon scoping is a future refactor).
	"Da Gobshot Thunderbuss": {
		"condition": "enhancement",
		"effects": [
			{"type": EffectPrimitivesData.GRANT_DEVASTATING_WOUNDS},
			{"type": EffectPrimitivesData.GRANT_HAZARDOUS}
		],
		"target": "bearer_model",
		"attack_type": "ranged",
		"implemented": true,
		"description": "ORKS only. Bearer's ranged weapons gain DEVASTATING WOUNDS + HAZARDOUS (effect_devastating_wounds, effect_grant_hazardous)"
	},

	# Dead Shiny Shootas — ranged weapons in the bearer's unit gain [RAPID FIRE 1].
	"Dead Shiny Shootas": {
		"condition": "enhancement",
		"effects": [{"type": EffectPrimitivesData.GRANT_RAPID_FIRE_1}],
		"target": "bearer_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "ORKS only. Bearer's unit ranged weapons gain RAPID FIRE 1 (effect_grant_rapid_fire_1 — same consumer as Dakkamek)"
	},

	# Targetin' Squigs — +1 to Hit on the bearer's unit's ranged attacks.
	"Targetin' Squigs": {
		"condition": "enhancement",
		"effects": [{"type": EffectPrimitivesData.PLUS_ONE_HIT_RANGED}],
		"target": "bearer_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "ORKS only. +1 to Hit on the bearer's unit's ranged attacks (effect_plus_one_hit_ranged)"
	},

	# Zog Off and Eat Dakka! — the bearer's unit can shoot after Falling Back.
	"Zog Off and Eat Dakka!": {
		"condition": "enhancement",
		"effects": [{"type": EffectPrimitivesData.FALL_BACK_AND_SHOOT}],
		"target": "bearer_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "ORKS only. The bearer's unit is eligible to shoot in a turn in which it Fell Back (effect_fall_back_and_shoot)"
	},

	# ======================================================================
	# ROLLIN' DEFF ENHANCEMENT ABILITIES (provisional 11e, 40kdc dataset)
	# Dead Shiny Shootas and Da Gobshot Thunderbuss are shared with the
	# More Dakka! entries above (name-keyed, so they serve both detachments).
	# ======================================================================

	# Boarding Ramps — +1 to Charge rolls for units that disembarked this
	# turn from the WAGON bearing the enhancement (ChargePhase live check via
	# FactionAbilityManager.boarding_ramps_charge_bonus).
	"Boarding Ramps": {
		"condition": "enhancement",
		"effects": [],
		"target": "bearer_unit",
		"attack_type": "all",
		"implemented": true,
		"description": "WAGON only. Units disembarking from the bearer this turn get +1 to Charge rolls (ChargePhase live check)"
	},

	# Targetin' Gizmos — bearer's unit ranged weapons gain [IGNORES COVER];
	# while a Waaagh! is active they also gain SUSTAINED HITS 1 (live check
	# via FactionAbilityManager.targetin_gizmos_sustained).
	"Targetin' Gizmos": {
		"condition": "enhancement",
		"effects": [{"type": "grant_ignores_cover"}],
		"target": "bearer_unit",
		"attack_type": "ranged",
		"implemented": true,
		"description": "WAGON only. Ranged weapons have IGNORES COVER; SUSTAINED HITS 1 while a Waaagh! is active (live check)"
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
	# T-104: Optional wargear ABILITY_EFFECTS entries. Bearer must list these in
	# meta.abilities for the effect to fire; the army-builder UI is the
	# remaining wedge. Each entry has the data hook needed for live combat.
	"Helix Gauntlet": {
		"condition": "passive",
		"target": "bearer_unit",
		"attack_type": "all",
		"implemented": true,
		"effects": [
			{"type": "set_effect_fnp", "value": 6}
		],
		"description": "Bearer's unit has Feel No Pain 6+ (10e index row — display only). Codex: Space Marines 11e: in your Command phase, this unit heals D3 wounds (SMAbilitiesA, WP-M4a)."
	},

	"Infiltrator Comms Array": {
		"condition": "command_phase",
		"target": "bearer_unit",
		"attack_type": "all",
		"implemented": true,
		"once_per_turn": true,
		"effects": [
			{"type": "regain_cp_on_5plus", "amount": 1}
		],
		"description": "At the start of your Command phase, roll one D6: on a 5+, you gain 1 CP"
	},

	"Telemon Caestus (Dual)": {
		"condition": "passive",
		"target": "bearer_model",
		"attack_type": "melee",
		"implemented": true,
		"effects": [
			{"type": "melee_attacks_bonus", "value": 2}
		],
		"description": "Telemon equipped with two Telemon Caestus gains +2 melee attacks"
	},

	# Waaagh! Effigy (Aura) — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Waaagh! Effigy (Aura)": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "all",
		"implemented": true,
		"description": "This unit is riled up (Codex: Orks 11e — OrkAbilities11e)."
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

	# ======================================================================
	# BEAST SNAGGA SUB-FACTION ABILITIES (OA-49)
	# ======================================================================

	# Beastboss — melee weapons gain [DEVASTATING WOUNDS] after charging
	# Each time this model makes a Charge move, until the end of the turn, melee weapons
	# it is equipped with have the [DEVASTATING WOUNDS] ability.
	# Checked directly in RulesEngine._resolve_melee_assignment() via has_beastly_rage_active().
	# Since characters fight with their own unit_id (separate from bodyguard), this naturally
	# restricts the effect to the Beastboss's attacks only.
	"Beastly Rage": {
		"condition": "charged_this_turn",
		"effects": [{"type": "grant_devastating_wounds"}],
		"target": "model",
		"attack_type": "melee",
		"implemented": true,
		"description": "After charging, this model's melee weapons gain [DEVASTATING WOUNDS] until end of turn"
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

	# Super Runts — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Super Runts": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This unit is riled up; its Scavenged Shivs have +1 A, WS and S (Codex: Orks 11e — OrkAbilities11e)."
	},

	# One Last Kill — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"One Last Kill": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This model's Fight on Death rolls succeed on a 2+ (Codex: Orks 11e — OrkAbilities11e)."
	},

	# Da Bigger Dey iz... — Codex: Orks (11e) datasheet ability; the rule is in
	# OrkAbilities11e.gd (WP-O6), this row only describes it.
	"Da Bigger Dey iz...": {
		"condition": "ork11e",  # WP-O6: Codex: Orks (11e) rule lives in OrkAbilities11e.gd
		"effects": [],
		"target": "unit",
		"attack_type": "melee",
		"implemented": true,
		"description": "This unit's melee attacks that target a MONSTER/VEHICLE unit can re-roll the wound roll (Codex: Orks 11e — OrkAbilities11e)."
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
		# Issue #386: Wahapedia text (Kannonwagon datasheet, NOT Battlewagon as audit
		# said): "In your Shooting phase, just after selecting a target for this
		# model's supa-kannon, roll one D6 for the target unit and every other unit
		# within 3 inches of that unit: on a 5+, the unit being rolled for is struck
		# by a concussive wave. After this model has finished making its attacks
		# against that target unit this phase, each unit struck by a concussive wave
		# this phase suffers D3 mortal wounds."
		# Active Ork rosters field Battlewagon (no supa-kannon), so this path is
		# unreachable in-scope. Registered for future Kannonwagon rosters.
		"condition": "on_shooting_target_selection",
		"effects": [],
		"target": "enemy_target",
		"attack_type": "ranged",
		"weapon_restriction": "supa-kannon",
		"implemented": true,
		"description": "When targeting with supa-kannon: roll D6 for target+units within 3\" — 5+=concussive wave; D3 MW per struck unit after attacks resolve. Helper: UnitAbilityManager.roll_big_booms_concussive_wave(actor_id, target_id)"
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

# Usage keys in the order they were marked (newest last) — GILDED CHAMPION
# restores the target's most recently spent once-per-battle ability.
var _once_per_battle_order: Array = []

# GILDED CHAMPION (Lions of the Emperor): a restored once-per-battle ability
# cannot be used again in the phase the stratagem was used in.
# Key: "unit_id:ability_name", Value: {"round": int, "phase": int, "player": int}
var _gilded_champion_block: Dictionary = {}

# Track once-per-battle-round ability usage
# Key: "player:ability_name", Value: battle_round_number (last used round)
var _once_per_round_used: Dictionary = {}


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

			# Check once-per-battle restriction (routed through the query so the
			# GILDED CHAMPION same-phase block applies)
			if effect_def.get("once_per_battle", false):
				if is_once_per_battle_used(bodyguard_unit_id, ability_name):
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
					game_event_log.add_ability_entry(owner,
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
				game_event_log.add_ability_entry(owner,
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
			# WP-O5: a Codex: Orks (11e) enhancement of the unit's codex
			# detachment is resolved by OrkEnhancements11e, never by a 10e row
			# of the same name (More Dakka! / Rollin' Deff keep theirs).
			if GameConstants.edition >= 11 and enhancement_name is String \
					and load("res://scripts/codex/orks/OrkEnhancements11e.gd").owns_name(unit, enhancement_name):
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

			# Skwad Leader: the grant only applies while the bearer is leading
			# a unit with the required keyword (e.g. KOMMANDOS).
			var required_bg_kw = str(effect_def.get("requires_bodyguard_keyword", ""))
			if required_bg_kw != "":
				if target_unit_id == unit_id:
					continue  # bearer is not attached to a bodyguard unit
				var bg_unit = units.get(target_unit_id, {})
				if not RulesEngine.unit_has_keyword(bg_unit, required_bg_kw):
					continue

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

		# Skip embarked units (they are inside transports, not on the board).
		# T-029a: defensive null-safe — saved games may store null for unembarked
		# units, and `null != ""` is true.
		var other_embk_aura = other_unit.get("embarked_in", "")
		if other_embk_aura != null and other_embk_aura != "":
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
		game_event_log.add_ability_entry(owner,
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
		# T-029a: defensive null-safe embarked check.
		var other_embk_friendly = other_unit.get("embarked_in", "")
		if other_embk_friendly != null and other_embk_friendly != "":
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
		# T-029a: defensive null-safe embarked check.
		var other_embk_enemy = other_unit.get("embarked_in", "")
		if other_embk_enemy != null and other_embk_enemy != "":
			continue

		var dist = _closest_model_distance(source_unit, other_unit)
		if dist <= aura_range:
			results.append(other_id)

	return results

## Battle-shock test roll bonus for `unit_id` (CommandPhase adds it to the
## 2D6). The only source was the pre-codex Waaagh! Effigy (Aura) +1 within 12";
## the Codex: Orks (11e) Waaagh! Effigy makes the Stompa riled up instead
## (OrkAbilities11e), so no ability grants a bonus here now (WP-O6).
func get_battle_shock_bonus(_unit_id: String) -> int:
	return 0

# Issue #386 Big Booms (Kannonwagon supa-kannon).
# Wahapedia: "In your Shooting phase, just after selecting a target for this
# model's supa-kannon, roll one D6 for the target unit and every other unit
# within 3" of that unit: on a 5+, the unit being rolled for is struck by a
# concussive wave. After this model has finished making its attacks against
# that target unit this phase, each unit struck by a concussive wave this
# phase suffers D3 mortal wounds."
# Returns array of dicts: [{unit_id, roll, struck:bool}].
# ShootingPhase calls this on target selection if actor has a supa-kannon
# weapon and Big Booms ability; struck unit ids are queued and D3 MW per unit
# is applied after attacks against the chosen target finish resolving.
func roll_big_booms_concussive_wave(actor_unit_id: String, target_unit_id: String, rng_seed: int = -1) -> Array:
	var units = GameState.state.get("units", {})
	var actor = units.get(actor_unit_id, {})
	if actor.is_empty():
		return []
	# Verify the actor has Big Booms ability + a supa-kannon weapon. Both are
	# required by the rule so misconfigurations don't silently fire.
	var actor_abilities = actor.get("abilities", [])
	var has_ability = false
	for ab in actor_abilities:
		var ab_name = ""
		if typeof(ab) == TYPE_DICTIONARY:
			ab_name = String(ab.get("name", ""))
		elif typeof(ab) == TYPE_STRING:
			ab_name = String(ab)
		if ab_name == "Big Booms":
			has_ability = true
			break
	if not has_ability:
		return []
	var has_supa_kannon = false
	# Codebase stores weapons primarily on unit.meta.weapons; some flows attach
	# them per-model. Check both.
	var meta_weapons = actor.get("meta", {}).get("weapons", [])
	for w in meta_weapons:
		var wname = ""
		if typeof(w) == TYPE_DICTIONARY:
			wname = String(w.get("name", ""))
		elif typeof(w) == TYPE_STRING:
			wname = String(w)
		if wname.to_lower().find("supa-kannon") != -1:
			has_supa_kannon = true
			break
	if not has_supa_kannon:
		for model in actor.get("models", []):
			for w in model.get("weapons", []):
				var wname2 = ""
				if typeof(w) == TYPE_DICTIONARY:
					wname2 = String(w.get("name", ""))
				elif typeof(w) == TYPE_STRING:
					wname2 = String(w)
				if wname2.to_lower().find("supa-kannon") != -1:
					has_supa_kannon = true
					break
			if has_supa_kannon:
				break
	if not has_supa_kannon:
		return []

	var target_unit = units.get(target_unit_id, {})
	if target_unit.is_empty():
		return []

	# Build candidate set: target + every other unit (friend or foe) with at
	# least one alive model whose closest model is within 3" of any target model.
	var candidates: Array = [target_unit_id]
	for uid in units.keys():
		if uid == target_unit_id or uid == actor_unit_id:
			continue
		var u = units[uid]
		if not _has_alive_models(u):
			continue
		var dist = _closest_model_distance(target_unit, u)
		if dist <= 3.0:
			candidates.append(uid)

	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	var results: Array = []
	for uid in candidates:
		var roll = rng.randi_range(1, 6)
		var struck = roll >= 5
		results.append({
			"unit_id": uid,
			"roll": roll,
			"struck": struck,
		})

	# Optional event-log
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(actor.get("owner", 0))
		var struck_ids: Array = []
		for r in results:
			if r["struck"]:
				struck_ids.append(r["unit_id"])
		game_event_log.add_player_entry(owner,
			"Big Booms supa-kannon concussive wave: rolls=%s struck=%s" % [str(results), str(struck_ids)])
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

				# Check once-per-battle restriction (routed through the query so
				# the GILDED CHAMPION same-phase block applies)
				if effect_def.get("once_per_battle", false):
					if is_once_per_battle_used(unit_id, ability_name):
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
						EffectPrimitivesData.FLAT_ADVANCE,
						EffectPrimitivesData.AUTO_ADVANCE_6
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

			# Only apply eligibility effects (fall_back_and_*, advance_and_*, flat_advance, auto_advance_6)
			var effects = effect_def.get("effects", [])
			var eligibility_effects = []
			for effect in effects:
				var etype = effect.get("type", "")
				if etype in [
					EffectPrimitivesData.FALL_BACK_AND_SHOOT,
					EffectPrimitivesData.FALL_BACK_AND_CHARGE,
					EffectPrimitivesData.ADVANCE_AND_CHARGE,
					EffectPrimitivesData.ADVANCE_AND_SHOOT,
					EffectPrimitivesData.FLAT_ADVANCE,
					EffectPrimitivesData.AUTO_ADVANCE_6
				]:
					eligibility_effects.append(effect)

			if eligibility_effects.is_empty():
				continue

			# If this unit is attached as a character to a bodyguard, apply the flag
			# to the bodyguard unit (since the combined unit moves as the bodyguard).
			var target_unit_id = _get_combined_unit_for_enhancement(unit_id)
			var diffs = EffectPrimitivesData.apply_effects(eligibility_effects, target_unit_id)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)
				_active_ability_effects.append({
					"ability_name": ability_name,
					"source_unit_id": unit_id,
					"target_unit_id": target_unit_id,
					"effects": eligibility_effects,
					"attack_type": "all",
					"condition": "always"
				})
				if not _applied_this_phase.has(target_unit_id):
					_applied_this_phase[target_unit_id] = []
				_applied_this_phase[target_unit_id].append(ability_name)

				var unit_name = unit.get("meta", {}).get("name", unit_id)
				var target_note = "" if target_unit_id == unit_id else " (applied to bodyguard %s)" % target_unit_id
				print("UnitAbilityManager: %s has own eligibility ability '%s'%s" % [unit_name, ability_name, target_note])

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
	_once_per_battle_order.erase(usage_key)
	_once_per_battle_order.append(usage_key)
	print("UnitAbilityManager: Marked '%s' as used for unit %s (once per battle)" % [ability_name, unit_id])

func is_once_per_battle_used(unit_id: String, ability_name: String) -> bool:
	"""Check if a once-per-battle ability has been used for a specific unit.
	Also true while a GILDED CHAMPION restoration is blocked ('one additional
	time ... but not in the same phase')."""
	var usage_key = unit_id + ":" + ability_name
	if _once_per_battle_used.get(usage_key, false):
		return true
	var block = _gilded_champion_block.get(usage_key, {})
	if not block.is_empty() \
			and int(block.get("round", -1)) == GameState.get_battle_round() \
			and int(block.get("phase", -1)) == int(GameState.get_current_phase()) \
			and int(block.get("player", -1)) == GameState.get_active_player():
		return true
	return false

func get_used_once_per_battle_abilities(unit_id: String) -> Array:
	"""All once-per-battle abilities this unit has spent, oldest first."""
	var used: Array = []
	var prefix = unit_id + ":"
	for usage_key in _once_per_battle_order:
		if usage_key.begins_with(prefix) and _once_per_battle_used.get(usage_key, false):
			used.append(usage_key.substr(prefix.length()))
	# Include any marked outside the ordered list (defensive)
	for usage_key in _once_per_battle_used:
		if _once_per_battle_used[usage_key] and usage_key.begins_with(prefix):
			var ability_name = usage_key.substr(prefix.length())
			if ability_name not in used:
				used.append(ability_name)
	return used

func restore_once_per_battle_use(unit_id: String, ability_name: String) -> void:
	"""GILDED CHAMPION (Lions of the Emperor): the model can use the spent
	once-per-battle ability one additional time — but not in the phase the
	stratagem was used in."""
	var usage_key = unit_id + ":" + ability_name
	_once_per_battle_used.erase(usage_key)
	_once_per_battle_order.erase(usage_key)
	_gilded_champion_block[usage_key] = {
		"round": GameState.get_battle_round(),
		"phase": int(GameState.get_current_phase()),
		"player": GameState.get_active_player(),
	}
	print("UnitAbilityManager: GILDED CHAMPION — '%s' restored for unit %s (usable again from the next phase)" % [ability_name, unit_id])

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


func has_sticky_objectives_ability(unit_id: String) -> bool:
	"""Check if a unit has a sticky objectives ability (e.g. Get Da Good Bitz, Objective Secured).
	Used by MissionManager to apply sticky objective locks at end of Command phase."""
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return false

	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var ability_name = _get_ability_name(ability)
		if ability_name in ["Objective Secured"]:  # WP-O6: "Get Da Good Bitz" is on no Codex: Orks (11e) datasheet
			# WP-M4b: retired for a Codex: Space Marines (11e) army (no codex datasheet has it).
			if GameConstants.edition >= 11 and load("res://scripts/codex/space_wolves/SWCommon.gd").is_sm_army(int(unit.get("owner", 0))):
				print("UnitAbilityManager: Objective Secured on %s ignored — retired for Codex: Space Marines (11e) armies" % unit_id)
				continue
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
	# FLYIN' HEADBUTT (Codex: Orks 11e): "Your unit does not have the Deadly
	# Demise ability."
	if unit.get("flags", {}).get("ork11e_no_deadly_demise", false):
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

		# Check if any alive model is within range. OBJ-GAP-2: the shared
		# MissionManager predicate — base touching the hosting area of an 11e
		# terrain objective, base edge within 3" of the marker otherwise (this
		# used the model CENTRE within 3.79", missing large bases and areas).
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			if model.get("position") == null:
				continue
			if MissionManager.model_in_objective_range(model, obj):
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
		"scatter_used_this_turn": _scatter_used_this_turn.duplicate(true)
	}

func load_state(data: Dictionary) -> void:
	"""Restore state from save data."""
	_active_ability_effects = data.get("active_ability_effects", [])
	_applied_this_phase = data.get("applied_this_phase", {})
	_once_per_battle_used = data.get("once_per_battle_used", {})
	_once_per_round_used = data.get("once_per_round_used", {})
	_active_aura_effects = data.get("active_aura_effects", {})
	_scatter_used_this_turn = data.get("scatter_used_this_turn", {})
	print("UnitAbilityManager: State loaded — %d active effects, %d aura effects, %d once-per-battle used, %d once-per-round used" % [_active_ability_effects.size(), _active_aura_effects.size(), _once_per_battle_used.size(), _once_per_round_used.size()])

func reset_for_new_game() -> void:
	"""Reset all tracking for a new game."""
	_active_ability_effects.clear()
	_applied_this_phase.clear()
	_once_per_battle_used.clear()
	_once_per_round_used.clear()
	_active_aura_effects.clear()
	_scatter_used_this_turn.clear()
	print("UnitAbilityManager: Reset for new game")
