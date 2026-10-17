# Retired tests (10e / pre-codex behaviour the codexes removed)

A test is retired only when the codex removed the behaviour it checks. One
line each: `- <test file or check>: <removed behaviour> (<WP>)`.

## C2/O2 (data migration, integrator)
- test_fullauto_faction_rules.gd "Battlewagon T12 ('Ard Case +2)", "Firing Deck removed", "canonical 'Ramshackle'", "'Firing Deck 11' stripped": the Codex: Orks Battlewagon has no 'Ard Case or Ramshackle but Rugged; replaced by codex checks (T11, Firing Deck 11, Damaged 6).
- test_fullauto_faction_rules.gd "Custodian Guard W4 (Praesidium Shield +1)": Praesidium Shield is -1 D in the codex; replaced by "Custodian Guard Sodality W5".
- test_fullauto_faction_rules.gd "player 2: all 6 [Shield Host] mechanically implemented" and the AVENGE THE FALLEN / MULTIPOTENTIALITY / VIGILANCE ETERNAL effect spot-checks: Shield Host is not a codex detachment; replaced by a check that the 6 Guardians of the Throne rows are codex rows (implementation: WP-C5).
- test_custodes_lions_silent_hunters.gd _test_stratagem_loading (6 Lions of the Emperor 10e stopgap stratagems, 3 Silent Hunters stratagems) and _test_gilded_champion (10e Lions GILDED CHAMPION): the codex replaced the Lions stratagems and removed Silent Hunters; codex GILDED CHAMPION is an Auric Champions stratagem (WP-C5). The file's other groups test 10e engine code WP-C46 replaces — C46 retires or rewrites them.
