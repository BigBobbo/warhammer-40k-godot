# Unattended end-to-end loop run — 2026-05-19

Companion to `validation_2026-05-19.md`. That report validated the
critic and fixer protocols individually. This one validates the
**full playbook** running as one uninterrupted pipeline:
driver → diff → critic → fixer → re-verify, with no manual
intervention during the critic/fixer phases.

## TL;DR

Unattended pipeline works. Full loop closed against a synthetic
`WH_PARCHMENT` color regression on scenario `378_leader_pairing_formations`:

1. Driver run 1 → diff exit 1 (drift on all 12 steps, max-tile
   hd=8)
2. Critic agent invoked per playbook §"Invoking the critic
   subagent" → 12-entry critique JSON, all `wrong_color` /
   severity=medium
3. Fixer agent invoked per playbook §"Invoking the fixer
   subagent" → commit `af1cc7d9` restoring `WH_PARCHMENT` to
   `#EBE1C7`
4. Driver run 2 → diff exit 0 (12/12 match)

End-to-end wall clock: ~6 minutes (driver: ~80s × 2 + critic
~85s + fixer ~100s + commit/push overhead).

## Per-step trace

**Step 0 — regression seed.** Branched
`loop/realworld-validation-1` off main, swapped
`WH_PARCHMENT` from `Color(0.922, 0.882, 0.780)` (`#EBE1C7`
parchment) to `Color(0.2, 0.7, 0.3)` (green) in
`40k/scripts/WhiteDwarfTheme.gd:11`. Committed so the fixer
agent works against committed state (per the lesson from
`validation_2026-05-19.md`: "host session must preserve the
regressed state between critic and fixer invocations").

**Step 1 — driver, run 1.**
`bash scripts/loop/run_one_scenario_loop.sh 40k/tests/scenarios/sp/378_leader_pairing_formations.json`
Result:
- scenario exit: 0 (engine accepts the dispatched actions)
- golden_diff: drift=12, match=0, drifted_steps=[0..11]
- Per-tile distance signature was identical across all 12 steps
  (tile 1=8, tiles 2/4/7=6, rest 0), strongly suggesting one
  static UI theme change rather than per-step state divergence.

**Step 2 — critic.** Spawned via `Agent` tool with the prompt
from `scripts/loop/critic_prompt.md` and the inputs spec from
`scripts/loop/playbook.md` §"Invoking the critic subagent".
Critic returned a 12-entry JSON array. All entries:
- `severity: medium`
- `category: wrong_color`
- expected: "amber/yellow parchment Confirm Formations CTA"
- observed: "red/orange filled buttons" — *the critic
  misnamed the actual color (it's green, not red/orange)*

The critic correctly identified that a color regression exists
and that it's identical across all 12 steps. It did NOT correctly
identify the actual replacement hue. This is consistent with the
critic-reliability finding in the prior validation report:
multimodal Claude is unreliable at fine color discrimination on
downsampled screenshots.

**Step 3 — fixer.** Spawned via `Agent` tool with the prompt
from `scripts/loop/fixer_prompt.md` and the inputs spec from
the playbook §"Invoking the fixer subagent". Fixer:
- Identified the per-tile-signature-is-identical clue
- Read `40k/scripts/WhiteDwarfTheme.gd`
- Noticed the comment `# #EBE1C7` after `WH_PARCHMENT` didn't
  match the value, used that as a hint
- Restored `WH_PARCHMENT` to `Color(0.922, 0.882, 0.780)`
- Committed `af1cc7d9` with a proper `Justification:` block

Despite the critic's incorrect hue description, the fixer landed
the correct fix because the fixer has source-code access and used
the comment hint + the validated per-tile-signature reasoning.

**Step 4 — driver, run 2.** Same command. Result:
- scenario exit: 0
- golden_diff: drift=0, match=12
- Loop exit 0 ⇒ scenario clean ⇒ end of loop iteration

## Findings

### 1. The playbook works as specified

Critic invocation, fixer invocation, and the "if driver exit !=
0 then critic round" decision tree from the playbook all worked
end-to-end without modification.

### 2. pHash luminance-blindness is real but partial

Before the parchment test I tried a `WH_GOLD` swap (gold →
identical-luminance blue) — the diff missed it entirely (hd=2,
under threshold). pHash is luminance-based; equal-luminance
color swaps are invisible to it.

The parchment regression worked because parchment → green
changes luminance substantially (`luminance(0.85) → luminance(0.55)`).

**Implication**: the loop is reliable for luminance-affecting
regressions (layout, content presence/absence, color swaps with
significant L delta) but blind to equal-luminance color shifts.
This belongs in the loop's marketing material — operators
should not assume the diff catches "every visual regression."

### 3. Critic-reliability still imperfect, but fixer compensates

The critic mis-described the regression color (red/orange instead
of green). The fixer succeeded anyway because:
- Source code access lets the fixer cross-reference against
  reality
- The per-tile-signature hint pointed at a single static value
- The constant's comment (`# #EBE1C7`) anchored the correct value

This is a robust failure mode: even when the critic hallucinates
specifics, the fixer can land the right change if the diff
report's structure points at the right area.

### 4. Bless-at-1/4-resolution destroys signal

The `WH_GOLD` test (which the diff missed) failed primarily
because `WH_GOLD` is used in 1-2px borders. At the golden's
480×270 resolution, those borders are sub-pixel artefacts and
pHash sees them as identical to the originals. A higher-res
golden would have caught the gold swap.

This is filed as a known limitation in the validation report's
"Diff prefilter findings" section. Worth re-emphasising:
**1/4-resolution goldens are not a sensitivity choice, they're a
file-size choice, and they cost the diff real signal**.

## Artefacts

- Branch: `loop/realworld-validation-1`
- Regression commit: `[validation] inject WH_PARCHMENT regression…`
- Fix commit: `af1cc7d9` (`Loop fix: restore WH_PARCHMENT…`)
- Critique JSON (ephemeral): `/tmp/critique_378_parchment.json`
- Driver logs (ephemeral): `/tmp/host_run3.log`, `/tmp/host_run_final.log`

## Conclusion

The unattended end-to-end loop works. The single full pipeline
closes against a real-looking color regression with no manual
intervention between phases. Known limitations (pHash luminance,
critic color-discrimination, bless-resolution) are quantified
and documented but do not block the loop from being deployable
as a CI gate.

Recommended deployment posture:

- Run the loop unattended on every PR that touches
  `40k/scripts/` or `40k/scenes/`.
- Treat the diff as a high-precision low-recall prefilter:
  drift = real, but absence-of-drift ≠ no regression.
- Always run the critic on every PR even when diff is clean
  (the playbook §"If driver exit == 0: → CRITIC round (sanity)"
  is doing real work).
- Plan a follow-up to stop downsampling goldens. The
  file-size argument no longer applies at 240 goldens × ~16KB =
  ~4MB — well within reasonable git limits.
