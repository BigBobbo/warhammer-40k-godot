I would like the user to be able to upload their army lists in the same format that is output from apps line new recruit or the GW app. The game would then find the corresponding entries for those units in the downloaded data from Wahapedia and load their complete stats. 
The Wahapedia data is stored in the Wahapedia_Data folder in the following files:
Abilities.csv
Datasheets_keywords.csv
Datasheets_stratagems.csv
Datasheets.csv
Datasheets_leader.csv
Datasheets_unit_composition.csv
Factions.csv
Datasheets_abilities.csv
Datasheets_models.csv
Datasheets_wargear.csv
Last_update.csv
Datasheets_detachment_abilities.csv
Datasheets_models_cost.csv
Detachment_abilities.csv
Source.csv
Datasheets_enhancements.csv
Datasheets_options.csv
Enhancements.csv
Stratagems.csv

And the data description is contained in Export Data Specs.xlsx


An example army list is attached shown below:

Adeptus Custodes
Strike Force (2000 points)
Shield Host


CHARACTERS

Blade Champion (135 points)
• Warlord
• 1x Vaultswords
• Enhancement: Auric Mantle

Blade Champion (120 points)
• 1x Vaultswords


BATTLELINE

Custodian Guard (170 points)
• 4x Custodian Guard
• 2x Guardian spear
1x Misericordia
2x Praesidium Shield
1x Sentinel blade
1x Vexilla


OTHER DATASHEETS

Caladius Grav-tank (215 points)
• 1x Armoured hull
1x Twin arachnus heavy blaze cannon
1x Twin lastrum bolt cannon

Custodian Wardens (260 points)
• 5x Custodian Warden
• 5x Guardian spear
1x Vexilla

Custodian Wardens (260 points)
• 5x Custodian Warden
• 5x Guardian spear
1x Vexilla

Prosecutors (50 points)
• 1x Prosecutor Sister Superior
• 1x Boltgun
1x Close combat weapon
• 4x Prosecutor
• 4x Boltgun
4x Close combat weapon

Venatari Custodians (165 points)
• 3x Venatari Custodian
• 3x Venatari lance

Venatari Custodians (165 points)
• 3x Venatari Custodian
• 3x Venatari lance

Venatari Custodians (165 points)
• 3x Venatari Custodian
• 3x Venatari lance

Witchseekers (50 points)
• 1x Witchseeker Sister Superior
• 1x Close combat weapon
1x Witchseeker flamer
• 3x Witchseeker
• 3x Close combat weapon
3x Witchseeker flamer

Witchseekers (50 points)
• 1x Witchseeker Sister Superior
• 1x Close combat weapon
1x Witchseeker flamer
• 3x Witchseeker
• 3x Close combat weapon
3x Witchseeker flamer


ALLIED UNITS

Callidus Assassin (100 points)
• 1x Neural shredder
1x Phase sword and poison blades

Inquisitor Draxus (95 points)
• 1x Dirgesinger
1x Power fist
1x Psychic Tempest


The output would contain all of the model/list information to be loaded into a godot game. Currently the Godot game uses the following temporary structure for loading units. The output should be very similar to this but include all of the units and models stats/attributes/info/details:
		"units": {
			"U_INTERCESSORS_A": {
				"id": "U_INTERCESSORS_A",
				"squad_id": "U_INTERCESSORS_A",
				"owner": 1,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Intercessor Squad",
					"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_TACTICAL_A": {
				"id": "U_TACTICAL_A",
				"squad_id": "U_TACTICAL_A",
				"owner": 1,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Tactical Squad",
					"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES"],
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_BOYZ_A": {
				"id": "U_BOYZ_A",
				"squad_id": "U_BOYZ_A",
				"owner": 2,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Boyz",
					"keywords": ["INFANTRY", "MOB", "ORKS"],
					"stats": {"move": 6, "toughness": 5, "save": 6}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m6", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m7", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m8", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m9", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m10", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_GRETCHIN_A": {
				"id": "U_GRETCHIN_A",
				"squad_id": "U_GRETCHIN_A",
				"owner": 2,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Gretchin",
					"keywords": ["INFANTRY", "GROTS", "ORKS"],
					"stats": {"move": 5, "toughness": 3, "save": 7}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []}
				]
			}
		},

