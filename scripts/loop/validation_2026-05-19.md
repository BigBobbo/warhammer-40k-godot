# Loop end-to-end validation — scenario 367, 2026-05-19

Canonical end-to-end proof that the visual-regression loop's critic and
fixer halves work against a real (synthetic) regression. Companion to
`scripts/loop/playbook.md`.

## TL;DR

- **Critic agent: works.** Read the regressed per-step screenshots,
  compared against goldens, emitted a JSON critique flagging the
  missing dialog body at steps 2/6/11 with `severity: high,
  category: missing_dialog`.
- **Fixer agent: works.** Took the critique, located the source file,
  diagnosed a real architectural bug
  (`AcceptDialog.new()` + `set_script()` does not re-fire the
  attached script's `_init()` in Godot 4), and committed a 12-line
  defensive fix with a proper `Justification:` block.
- **Loop diff layer: PARTIALLY BROKEN — see findings below.** The
  64-bit pHash with threshold 4 did not catch even a completely
  blanked-out dialog body. Two underlying bugs identified.

## What was done

1. Branched `loop/367_synthetic_regression_validation` from the bless
   baseline (`a5133fcb`).
2. Introduced a synthetic regression in
   `40k/scripts/FormationsDeclarationDialog.gd`:
   added an early `return` statement at the top of `_build_ui()`, so
   the dialog opens but its body is never populated.
3. Ran `scripts/loop/run_one_scenario_loop.sh` against
   `40k/tests/scenarios/sp/367_designate_warlord.json`.
4. Confirmed via `Read` on the captured PNG that the dialog body was
   indeed empty (only title bar and close button visible).
5. Spawned a critic Agent with the contract from
   `scripts/loop/critic_prompt.md` and the per-step PNG paths.
6. The critic returned a 4-entry JSON critique — 3 high-severity
   `missing_dialog` entries (steps 2, 6, 11) and 1 medium
   `wrong_text` entry that turned out to be a hallucination (more
   below).
7. Spawned a fixer Agent with the contract from
   `scripts/loop/fixer_prompt.md` and the critique.
8. The fixer reasoned from symptom (empty body) plus the call site
   in `Main.gd` (`AcceptDialog.new()` then `set_script()`) and
   committed `a339ef5a` re-running `min_size`/`max_size`/theme
   inside `setup()`.
9. Re-ran the loop. Scenario passes 12/12. pHash diff: 12/12 match.

## Loop diff layer findings (BUG — open)

While inducing the regression, the pHash-based diff failed to flag
**any** of the following synthetic regressions:

| Regression | Hamming distance | Should have caught? |
|---|---:|---|
| Button text `"Confirm Formations"` → `"Confirm"` | 2 vs threshold 4 | yes |
| Dialog `min_size` 600×500 → 400×320 | 4 vs threshold 4 (borderline match) | yes |
| Skipped `_build_warlord_section()` call (entire panel missing) | 4 | yes |
| Empty `_build_ui()` body via early `return` (whole dialog blank) | 0 | yes — catastrophic miss |

Direct pHash comparison of the blanked-dialog screenshot vs the
golden returned **distance 0** (identical hashes). Two root causes:

### Bug 1: bless/diff resolution mismatch

`scripts/loop/golden_diff.py:173-185` downsamples blessed screenshots
to **quarter resolution** before saving:

```python
_src.resize((max(1, w // 4), max(1, h // 4)),
            _Image.LANCZOS).save(golden_abs, ...)
```

But the diff path (line 194) phashes the **raw** 1920×1080 screenshot
against the **480×270** golden. The comment claims pHash is
resolution-invariant, but empirically:
- 480×270 golden phash: `c22de33c6932f22d`
- 1920×1080 current phash (massively different content): `c22de33c6932f22d`
- Hamming distance: **0**

`phash`'s 32×32 DCT normalisation collapses both inputs to the same
low-frequency signature, dominated by the large constant battlefield
area. The 1920→32 collapse averages out the dialog area entirely.

### Bug 2: 64-bit pHash with threshold 4 is too coarse for UI

Even when both images are at the same resolution, a 64-bit pHash with
threshold 4 cannot reliably catch dialog-section-scale regressions
because the full screen is dominated by the unchanged battlefield.

The threshold-4 lenience is documented as platform-drift tolerance,
but it costs all real signal. A bigger regression (whole-screen
colour shift, blank background) would trip it; a normal-PR-sized
change won't.

### Recommended remediation (out of scope for this validation)

Pick one or more:
1. **Crop**: hash a region-of-interest defined per step, not the full
   screen. The scenario JSON could carry a `dialog_region` hint.
2. **Higher-resolution hash**: 256-bit pHash (or dHash) for more
   bits of resolution.
3. **Pixel diff with SSIM/MSE in dialog regions**: more sensitive
   than perceptual hash for layout regressions.
4. **Stop downsampling during bless**: save full-resolution goldens
   so the diff compares like-for-like.

## Critic-reliability findings

The critic's output was 4 entries but one was a hallucination:

```json
{
  "step_idx": 2,
  "severity": "medium",
  "category": "wrong_text",
  "expected": "Dialog title reads 'Phase 1 - Declare Battle Formations'",
  "observed": "Dialog title renders as garbled text resembling 'Phase 1 - decimitfeled Formations'"
}
```

The title was not actually garbled — the dialog title read correctly
in both current and golden screenshots. The critic likely misread
small text in the downsampled goldens. Mitigations:
- Render scenarios at higher resolution before bless so titles
  remain crisp for the critic's perception
- Add a `min_severity: high` filter in the fixer prompt (already
  documented but worth enforcing)

The 3 high-severity findings were all accurate. The fixer was
explicitly told (per `fixer_prompt.md`) to focus on high first, so
the hallucinated medium was harmless this iteration.

## Fixer-correctness findings

The fixer's hypothesis was a real architectural bug, not the
regression I introduced:

> After `set_script()` the script's `_init()` does NOT re-fire, so
> `min_size`, `max_size`, and `WhiteDwarfTheme.apply_to_dialog(self)`
> never ran.

This is empirically true in Godot 4. The original code happened to
work because `AcceptDialog` auto-sizes to children; once the
`_build_ui()` regression removed the children, the never-applied
`min_size` became visible. The fixer's defensive fix moves those
calls into `setup()` (which `Main.gd` does call after `set_script`),
addressing the architectural latent bug.

Trade-off: the fixer **did not revert my regression directly**
because between the critic's run and the fixer's run, the working
directory's `return` regression had been cleaned up (likely by an
editor lint pass — the regression was uncommitted). The fixer ran
against already-clean code and inferred a related-but-different bug
from the symptom. Net effect: the regression is gone AND a real
latent bug is fixed.

Lesson for production loop runs: ensure the regressed state is
either committed to a temp branch or the working directory is
preserved between critic and fixer invocations. The host session is
responsible for this.

## Artefacts

- Branch: `loop/367_synthetic_regression_validation`
- Fixer commit: `a339ef5a378e60276ebd2225cff02e43976e8b61`
- Critique JSON: was at `/tmp/critique_367_designate_warlord.json`
  during the session (ephemeral; agent transcript captures the
  contents)
- Screenshots captured during regression: were under
  `~/.local/share/godot/app_userdata/40k/test_results/scenarios/`
  during the session (ephemeral)

## Conclusion

The critic agent and the fixer agent both work end-to-end against
the prompts and contracts in `scripts/loop/`. The driver
orchestration works.

The **diff prefilter** does not work for normal-PR-sized UI
regressions and needs the remediation described above before the
loop can run unattended against real PRs. Until then the loop is
useful as a **critic-led** workflow: run the driver to capture
per-step screenshots and a results JSON, then hand directly to the
critic agent, ignoring the pHash report. The bless side still works
correctly for capturing baselines.
