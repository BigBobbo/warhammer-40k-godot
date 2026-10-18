# Retired tests (10e / pre-codex behaviour the codexes removed)

A test is retired only when the codex removed the behaviour it checks. One
line each: `- <test file or check>: <removed behaviour> (<WP>)`.

## C2/O2 (data migration, integrator)
- test_fullauto_faction_rules.gd "Battlewagon T12 ('Ard Case +2)", "Firing Deck removed", "canonical 'Ramshackle'", "'Firing Deck 11' stripped": the Codex: Orks Battlewagon has no 'Ard Case or Ramshackle but Rugged; replaced by codex checks (T11, Firing Deck 11, Damaged 6).
- test_fullauto_faction_rules.gd "Custodian Guard W4 (Praesidium Shield +1)": Praesidium Shield is -1 D in the codex; replaced by "Custodian Guard Sodality W5".
- test_fullauto_faction_rules.gd "player 2: all 6 [Shield Host] mechanically implemented" and the AVENGE THE FALLEN / MULTIPOTENTIALITY / VIGILANCE ETERNAL effect spot-checks: Shield Host is not a codex detachment; replaced by a check that the 6 Guardians of the Throne rows are codex rows (implementation: WP-C5).
- test_custodes_lions_silent_hunters.gd _test_stratagem_loading (6 Lions of the Emperor 10e stopgap stratagems, 3 Silent Hunters stratagems) and _test_gilded_champion (10e Lions GILDED CHAMPION): the codex replaced the Lions stratagems and removed Silent Hunters; codex GILDED CHAMPION is an Auric Champions stratagem (WP-C5). The file's other groups test 10e engine code WP-C46 replaces — C46 retires or rewrites them.

## WP-O34 (Codex: Orks army rules + detachment rules)
- tests/scenarios/sp/bully_boyz_da_boss_is_watchin.json (edition 11): the Bully Boyz second Waaagh! (Da Boss Is Watchin') is a 10e rule the codex replaced with Displays of Savagery; scenario pinned to edition 10 (where the rule still runs, PASS), 11e covered by ork11e_det_bully_boyz.
- tests/scenarios/sp/dread_mob_try_dat_button.json (edition 11): the automatic Button Effect roll (SUSTAINED HITS / LETHAL HITS / +2 AP) is the 10e Dread Mob rule; the codex Try Dat Button! is a one/two-D6 player choice (+1 A / +2 S / +1 AP); pinned to edition 10 (PASS), 11e covered by ork11e_det_dread_mob.
- tests/scenarios/sp/taktikal_lissen_ere_taktiks.json (edition 11): Lissen 'Ere (Taktiks) is the 10e Taktikal Brigade rule; the codex rule is Suspiciously Well Organised; pinned to edition 10 (PASS), 11e covered by ork11e_det_taktikal_brigade.
- test_ork_codex_shooting_fixes.gd G "PREY (BEAST SNAGGA vs its Prey)": the 10e Prey rule (is_prey_of_N flag, +1 AP) is gone from the codex Da Big Hunt; the check is ported to the codex rule's "+1 AP" (DA HUNT IS ON: Beast Snagga vs a VEHICLE), same AP-sign plumbing.
- test_ork_codex_turn_flow_fixes.gd J "no Command Re-roll prompt for its advance roll": not removed, adjusted — the 11e Waaagh! army rule adds a FREE advance re-roll (not a stratagem, so 15.01 does not bar it); the check now accepts that pause (and declines it) while still refusing the Command Re-roll; same adjustment in the windowed ork11e_ere_we_go / ork11e_mind_mostly_on_the_mission.
