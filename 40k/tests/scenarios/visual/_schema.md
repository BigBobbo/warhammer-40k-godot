# Visual scenario format (design-guidelines tasks)

Visual scenarios live under `40k/tests/scenarios/visual/` and follow the same
JSON shape as `tests/scenarios/sp/` (see `../_schema.md`). This file documents
the **extra rules** that apply to scenarios for design-guidelines tasks
(T01–T45 in `.llm/todo.md`).

## Why a separate directory

Design-guidelines tasks have two acceptance tiers — machine-checkable (Tier A)
and human visual checklist (Tier B). The `run_scenarios.sh` wrapper detects
paths under `tests/scenarios/visual/` and:

- Copies captured screenshots to `40k/test_results/design_guidelines/T##/`
  so reviewers have a stable location to walk through.
- Compares the passing-scenario count to `_baseline.json` and exits with
  code **3** on regression (distinct from 1 for assertion failure and 2 for
  infra).

## Required steps in every visual scenario

A visual scenario MUST include all of the following:

1. **Initial screenshot** with label `T##_before` (or any label suffixed
   `_before`).
2. **Final screenshot** with label `T##_after` (or `_after` suffixed).
3. **At least one falsifiable assertion** — `expect_state`,
   `expect_action_result`, `expect_phase`, `expect_node_property`, or one of
   the Tier-A step types below. Screenshot-only scenarios are rejected.
4. **An `expect_baseline_unchanged` step** to assert the baseline file is in
   good shape.

## Tier-A step types (added in T02)

### `execute_script`

Evaluate a GDScript expression and compare its result.

```json
{ "act": "execute_script",
  "script": "MovementController.current_drag_segments[-1].color_slot",
  "equals": "MARGINAL_YELLOW" }

{ "act": "execute_script",
  "script": "ThreatOverlay.rendered_rings.size()",
  "expect_min": 2 }

{ "act": "execute_script",
  "script": "DiceRollVisual.is_skippable_with_space",
  "exists": true }
```

Supported comparisons: `equals`, `not_equals`, `exists`, `expect_min`,
`expect_max`. The expression has access to every autoload by name plus
`main` (the live battle scene root, if present).

### `pixel_diff`

Compare two previously-captured screenshots from this scenario. Both
screenshots must have been captured by earlier `screenshot` steps in the
same scenario.

```json
{ "act": "pixel_diff",
  "before": "T03_before",
  "after":  "T03_after",
  "expect_max_pct": 1.0 }

{ "act": "pixel_diff",
  "before": "T03_at_M",
  "after":  "T03_at_advance",
  "region": "drag_path",
  "expect_min_pct": 3.0 }
```

For `region`, the scenario top-level must declare a `regions` dict:

```json
{
  "id": "T03_drag_ruler",
  "regions": {
    "drag_path": [400, 200, 600, 400]
  },
  "steps": [...]
}
```

Exactly one of `expect_min_pct` / `expect_max_pct` is required. Without a
bound the step fails — a `pixel_diff` with no expectation is a screenshot
in disguise (false positive) and is banned by the playbook.

### `expect_baseline_unchanged`

```json
{ "act": "expect_baseline_unchanged" }
```

Asserts `_baseline.json` exists, is well-formed, and contains a non-empty
`passing` array whose length matches the `count` field. Cross-scenario
regression checks live in the shell wrapper.

## File naming

`T##_<slug>.json` where `T##` matches the task ID in `.llm/todo.md` and
`<slug>` is a short kebab-case description.

Example: `T03_drag_ruler.json`, `T07_terrain_cover_icons.json`.

## Test-seam convention (`tNN_*` helpers)

Many T## tasks expose small "test-seam" methods on the script they're
extending. These follow a strict naming convention so reviewers can
distinguish them from production API:

| Pattern | Purpose | Example |
| --- | --- | --- |
| `tNN_synthesize_<action>(args)` | Synthesize a user-input event and route it through `_input` directly. Used because headless+xvfb can't reliably deliver synthetic key events through `Input.parse_input_event` (Control nodes consume them before they reach the target). | `t13_synthesize_f_press()` builds an `InputEventKey`, sets `keycode = KEY_F`, calls `_input(ev)`, returns `last_camera_fit_action`. |
| `tNN_set_<state>(args)` | Inject scenario-driven state into a system that normally derives it from gameplay. | `t33_set_columns([{"name":"Hits",...}, ...])` populates `DiceRollVisual.columns` without running a real combat resolution. |
| `tNN_<query>()` | Read derived state that's not a plain property. | `t06_anchor_left_ratio()` computes `position.x / viewport.size.x` so scenarios can assert layout without simulating a viewport resize. |

Rules:

1. Test seams are NEVER called from user code or other production code —
   only from `tests/scenarios/visual/T##_*.json` step scripts.
2. The `tNN_` prefix is mandatory. Reviewers grep `t[0-9]+_` to find them.
3. Seams must be additive — they may NOT change behavior of production
   paths. If production needs the same logic, refactor the production
   path so the seam can call it.
4. Document any seam in its host script with a comment `# T## test seam:`
   explaining what it bypasses and why.

Rationale: the playbook bans pin tests and screenshot-only acceptance.
Some tasks need to drive UI from JSON scenarios where the input
pipeline is unreliable in headless mode. The test-seam pattern lets us
keep Tier A falsifiable (we read the *property the user would see*,
just synthesized through a controlled path).

## Banned patterns

These produce false positives and are rejected on review:

1. **Screenshot-only scenarios.** No assertions = no proof.
2. **`pixel_diff` without an `expect_*_pct` bound.** A diff that isn't
   compared is a screenshot in disguise.
3. **`execute_script` without an expectation AND without a side effect.** If
   the script is just `return null`, the step is meaningless.
4. **Subjective adjectives in step labels.** "looks_good", "smooth",
   "performant" — Tier A is numeric only. Save those for Tier B.

## Example minimum-viable visual scenario

See `T02_harness_self_check.json` in this directory — it exercises every
Tier-A step type and is the integration test for the harness itself.
