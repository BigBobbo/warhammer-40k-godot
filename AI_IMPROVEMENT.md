# AI Improvement Log

## Session: 2026-02-25 — First Kills Achieved in AI vs AI

### Problem
In AI vs AI matches, neither army was killing any opposing units. After 4+ rounds of play, zero casualties occurred on either side.

### Root Cause Analysis (3 critical bugs found)

#### Bug 1: Shooting failed due to missing Line-of-Sight validation
**File:** `AIDecisionMaker.gd` — `_build_focus_fire_plan()`

The focus fire plan built a damage matrix that checked weapon range but NOT Line of Sight (LoS). The plan would assign weapons to targets behind terrain, and when the SHOOT action was submitted, `RulesEngine.validate_shoot()` rejected it with "No valid targets in range and LoS". The AI then fell back to SKIP_UNIT, meaning the shooting unit did nothing.

**Fix:** Added `_can_shooter_see_target()` helper that calls `RulesEngine._check_target_visibility()` to verify both range AND LoS. Integrated this into:
1. The damage matrix computation (zero damage for unseen targets)
2. The per-unit assignment filtering (drop assignments where LoS is blocked)

#### Bug 2: Charge move models not making base-to-base contact
**File:** `AIDecisionMaker.gd` — `_compute_charge_move()`

The charge move computation had two issues:
1. A 2px safety gap (`+ 2.0`) when computing base contact distance, which placed models just outside the 0.25" (10px) tolerance that `ChargePhase._validate_b2b_contact()` uses
2. The `_adjust_charge_position()` function pushed models AWAY from non-target enemies, inadvertently moving them far from charge targets

**Fix:**
- Changed base contact distance to `my_base_radius + target_base_radius + 1.0` (1px only)
- Added a post-adjustment enforcement that forces base-to-base contact regardless of non-target enemy avoidance, matching the ChargePhase's 10px (0.25") tolerance

#### Bug 3: Multi-model charge overlaps
**File:** `AIDecisionMaker.gd` — `_compute_charge_move()`

When a multi-model unit (e.g., Witchseekers with 3 models) charged, all models were directed toward the same point, causing self-overlap validation failures.

**Fix:** Added angular offset for subsequent models — each model after the first is rotated 60 degrees around the target to spread them into a fan formation, preventing overlap.

### Aggression Improvements

#### Ork Faction Aggression Increased
- `FACTION_AGGRESSION_ORKS`: 1.8 → 2.2 (makes Orks significantly more willing to charge and advance)
- `STRATEGY_EARLY_CHARGE`: 0.6 → 0.4 (much lower charge threshold in rounds 1-2)
- `MELEE_AGGRESSION_ENEMY_SEEK_BONUS`: 8.0 → 12.0 (melee units prioritize closing distance)
- `MELEE_AGGRESSION_CHARGE_RANGE_BONUS`: 12.0 → 16.0 (bigger bonus for reaching charge range)
- `MELEE_AGGRESSION_ADVANCE_THRESHOLD_INCHES`: 18.0 → 30.0 (advance toward enemies from farther away)
- `MELEE_AGGRESSION_MIN_MOVE_RATIO`: 0.5 → 0.7 (always move at least 70% of movement toward enemy)
- `THREAT_MELEE_UNIT_IGNORE`: 0.15 → 0.05 (melee units barely penalized for being near threats)

### Results

**Before changes:** 0 kills across 4+ rounds, all shooting failed, all charges failed
**After changes:**
- Shooting successfully landing hits and dealing damage (Caladius Grav-tank dealing 4+ wounds per shooting phase)
- Blade Champion successfully charged Warboss (97% probability, 4" distance)
- **Warboss DESTROYED** in melee: 5 attacks, 4 hits, 4 wounds, 1 Devastating Wounds, 1 casualty
- Warboss went from 6 wounds → 2 (shooting damage) → 0 (melee kill)

### Files Modified
- `40k/scripts/AIDecisionMaker.gd` — LoS checking, charge positioning, aggression constants
