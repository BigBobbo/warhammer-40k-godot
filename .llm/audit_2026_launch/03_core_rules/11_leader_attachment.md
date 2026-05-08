# 03.11 — Leader / Character Attachment

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_11_leader.md`

## Scope

Cover the Leader keyword mechanic and CHARACTER attachment rules. Wahapedia + Designers' Commentary. At minimum:
- Attach declared at army-list time
- Datasheet's `Leader` ability lists which units the CHARACTER can lead — cross-reference against `40k/data/Datasheets_leader.csv`
- Attached unit moves/acts as one
- Look Out, Sir applies to the CHARACTER while bodyguard alive (10e behaviour, no 9e wounds-threshold)
- Precision bypasses LOS! to allocate to the CHARACTER
- Detach when bodyguard reduced to 0 — character continues alone
- Character abilities transfer to bodyguard? — verify per Wahapedia (most do not; only those that say "while leading")
- Multi-character attachment (Warlord + Lieutenant) where allowed
- Battle-shock test target (Ldr of CHARACTER if attached?) — verify
- Lone Operative cannot be attached (verified 2026-05)
- Epic Hero / 1-model attachment exceptions

## Data source

**`40k/data/Datasheets_leader.csv`** — header `leader_id|attached_id|`, 1,899 rows. This is the canonical mapping. Verify the in-game CHARACTER attachment UI surfaces every legal pairing for the loaded faction's roster.

## Codebase entry points

`40k/autoloads/CharacterAttachmentManager.gd`, `40k/autoloads/RulesEngine.gd` (LOS!, Lone Operative checks), `40k/scripts/AttachmentPanel.gd` (if exists), `40k/dialogs/LeaderAttachDialog.gd` (if exists), `40k/autoloads/ArmyListManager.gd` (load-time validation).

## Live-validation focus

- Attach a Captain to an Intercessor squad → confirm merged movement/scoring
- Allocate a Precision attack to the attached CHARACTER → confirm bypasses LOS!
- Reduce the bodyguard to 0 models → CHARACTER detaches, continues alone, gains/loses correct keywords
- Attempt to attach a Lone Operative CHARACTER → reject
- Battle-shock a led unit → confirm test uses CHARACTER's Ld

## Prior-audit overlap

- Lone Operative cannot be attached — verified 2026-05 in `CharacterAttachmentManager.gd`
- Look Out, Sir 10e behaviour — verified 2026-05 in `RulesEngine.gd`
- Leader attachment AI synergy — `T7-17`

## Output prose

Top 3 launch-blocker leader gaps; top 3 invisible features. Particularly: leader pairings legal per `Datasheets_leader.csv` but unreachable in the in-game attachment UI. This is the single most important "invisible feature" surface for the audit because it gates every CHARACTER ability the player would expect to use.
