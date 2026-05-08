# Stage 6 — Synthesis

**Read first:** every file in `.llm/audit_2026_launch/findings/` plus `05_scorecard.md`.
**Output:** `.llm/audit_2026_launch/findings/06_SYNTHESIS.md` — this is the canonical steering document.

## Goal

Reduce the audit to a small set of decisions a project lead can act on. **Do not restate findings — link to them.** Cap at ~300 lines.

## Required sections

### 1. Launch-blocker shortlist (≤15 items)

Rules / features that come up every game and are at depth `< U`, or marked `🐛`/`❌`. Ranked by play frequency: **every turn / every game / common matchup / rare**.

For each: one-line description, file:line of the code touchpoint, link to the finding, estimated effort (S/M/L).

### 2. Invisible-feature list (top 15)

Features at `C` or `W` but not `U`. These are likely cheap wins — the engine already works, just need to surface in UI.

For each: one-line description, where the engine implements it, the missing UI affordance, link to finding.

### 3. Divergence list (top 10)

`🐛` findings where code runs but produces the wrong rule outcome. Most dangerous — silent.

For each: rule, what code does, what Wahapedia says, file:line, link to finding.

### 4. Data gaps (top 10)

Factions/units/weapons/abilities whose data references engine features that don't exist, or vice versa.

### 5. 9e carryovers

Anything verified (with Wahapedia URL) as removed in 10e but still active in code. Should be empty after the 2026-05 audit but verify.

### 6. Per-phase scorecard table

Pulled from `05_scorecard.md` Table 2. One row per phase.

### 7. Per-faction launch-readiness table

Pulled from `05_scorecard.md` Table 1. One row per faction.

### 8. Recommended sequencing

Three suggested rollup paths the project lead can pick from:

- **A. Polish 3 factions to ship-quality** — focus on the `🐛`/`❌` items in active-roster scope. Ignore catalog-only entities. Smallest scope.
- **B. Add a 4th faction to ship** — pick the closest-to-ready non-playable faction (likely Tyranids or Aeldari given catalog completeness). Estimate work.
- **C. Full 26-faction launch** — list the 23 unplayable factions sorted by estimated effort to add.

### 9. Confidence note

What fraction of audit findings were live-validated vs. classified at depth `C/W` only. Where confidence is low (e.g., MCP couldn't validate a stratagem because the timing window can't be triggered without specific game state), flag the residual risk.

### 10. Open questions for the project lead

A short list of decisions only the lead can make:
- Scope for launch (3 vs 4 vs 26 factions)
- Mission pack to encode as canonical (Leviathan / Pariah Nexus / Chapter Approved)
- Boarding Actions: in-scope or deferred
- Whether the catalog-only data should be removed or kept as future-work spec

---

## Process notes

- **Cap length at ~300 lines.** This is a steering document, not a report. The findings docs are the report.
- **No new audit work in this stage.** If a finding is missing, go back to Stage 3 or 4.
- **Cite issue/PR IDs from the 2026-05 audit** where overlap exists, but only if the item is still load-bearing.

## Hand-off

Once `06_SYNTHESIS.md` is written, the audit is complete. The project lead converts items into GitHub issues / PR work and proceeds.
