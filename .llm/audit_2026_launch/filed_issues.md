# Filed issues (2026-05-06 launch audit, Path A)

**Filed 26 of 26 drafts.**

| Alias | Issue | Title |
|---|---|---|
| A1-1 | [#364](https://github.com/BigBobbo/warhammer-40k-godot/issues/364) | AP-sign bug in `_calculate_save_needed` improves saves under negative AP |
| A1-2 | [#365](https://github.com/BigBobbo/warhammer-40k-godot/issues/365) | `da_jump_used_this_turn` flag never resets — Weirdboy permanently locked |
| A1-3 | [#366](https://github.com/BigBobbo/warhammer-40k-godot/issues/366) | NBSP in detachment names silently drops every Lions stratagem |
| A1-4 | [#367](https://github.com/BigBobbo/warhammer-40k-godot/issues/367) | DESIGNATE_WARLORD action defined but no UI button — multi-CHARACTER rosters cannot complete Formations |
| A1-5 | [#368](https://github.com/BigBobbo/warhammer-40k-godot/issues/368) | MULTIPOTENTIALITY expires `end_of_phase` instead of `end_of_turn` |
| A1-6 | [#369](https://github.com/BigBobbo/warhammer-40k-godot/issues/369) | Battle-shock test reads bodyguard's Ld only, never `max(bodyguard_ld, leader_ld)` for attached units |
| A2-1 | [#370](https://github.com/BigBobbo/warhammer-40k-godot/issues/370) | NEW-S1: BGNT seam — `validate_shoot` rejects MONSTER/VEHICLE in ER even though eligibility allows them |
| A2-2 | [#371](https://github.com/BigBobbo/warhammer-40k-godot/issues/371) | NEW-S2: Indirect Fire applies -1 hit / 1-3-fail / cover unconditionally — RAW: only when target invisible |
| A2-3 | [#372](https://github.com/BigBobbo/warhammer-40k-godot/issues/372) | Charge-roll modifier primitive missing in `_map_effects` — 'ERE WE GO + 12 stratagems silently rejected |
| A2-4 | [#373](https://github.com/BigBobbo/warhammer-40k-godot/issues/373) | Lone Operative attachment guard absent from `FormationsPhase._validate_declare_leader_attachment` |
| A3-1 | [#374](https://github.com/BigBobbo/warhammer-40k-godot/issues/374) | P0 enhancement effect handlers absent — 0 of 16 in-scope enhancements have effects (display-only labels) |
| A3-2 | [#375](https://github.com/BigBobbo/warhammer-40k-godot/issues/375) | P0 detachment stratagems silently `implemented:false` — 12 of 24 in-scope unreachable |
| A3-3 | [#376](https://github.com/BigBobbo/warhammer-40k-godot/issues/376) | Da Jump placement validation skips coherency / board / ER / strict-9 — pin test masked the bug |
| A3-4 | [#377](https://github.com/BigBobbo/warhammer-40k-godot/issues/377) | Deployment alternation always seats P1 first — CA 25-26 says defender deploys first |
| A3-5 | [#378](https://github.com/BigBobbo/warhammer-40k-godot/issues/378) | `Datasheets_leader.csv` (1,899 canonical pairings) never consumed — game uses hand-curated `armies/*.json can_lead` |
| A4-1 | [#379](https://github.com/BigBobbo/warhammer-40k-godot/issues/379) | `MissionManager` runtime state (sticky objectives, kill counters, supply-drop) reset on save/load |
| A4-2 | [#380](https://github.com/BigBobbo/warhammer-40k-godot/issues/380) | `UnitAbilityManager.get_state_for_save()` exists but is never called — once-per-battle ability locks reset on save/load |
| A5-1 | [#381](https://github.com/BigBobbo/warhammer-40k-godot/issues/381) | ARCHEOTECH MUNITIONS grants both LETHAL HITS and SUSTAINED HITS — should be either/or |
| A5-2 | [#382](https://github.com/BigBobbo/warhammer-40k-godot/issues/382) | CP-grant rule diverges from current Wahapedia text |
| A5-3 | [#383](https://github.com/BigBobbo/warhammer-40k-godot/issues/383) | Battle-shocked unit cannot shoot — 9e carryover, not in 10e RAW |
| A5-4 | [#384](https://github.com/BigBobbo/warhammer-40k-godot/issues/384) | Aircraft / Towering wall-LoS exception not honoured — wall fall-back in `EnhancedLineOfSight` ignores keyword exemptions |
| A5-5 | [#385](https://github.com/BigBobbo/warhammer-40k-godot/issues/385) | `state.board.terrain` permanently empty — impassable check is a no-op |
| A5-6 | [#386](https://github.com/BigBobbo/warhammer-40k-godot/issues/386) | Big Booms (Battlewagon supa-kannon) `implemented:false` — Battlewagon in active Ork roster |
| A5-7 | [#387](https://github.com/BigBobbo/warhammer-40k-godot/issues/387) | Waaagh! Energy ('Eadbanger size scaling) `implemented:false` — Weirdboy in active Ork roster |
| A5-8 | [#388](https://github.com/BigBobbo/warhammer-40k-godot/issues/388) | Daughters of the Abyss FNP-vs-Psychic flag set but never read in damage path |
| A5-9 | [#389](https://github.com/BigBobbo/warhammer-40k-godot/issues/389) | Witchseekers Scouts ability stored as `name:"Core"` — `_unit_has_scout_own` regex never matches |
