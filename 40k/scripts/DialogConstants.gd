class_name DialogConstants

## Standardized dialog size tiers.
## Use these constants instead of hardcoding Vector2 sizes in dialogs.

## Small: simple confirmations, results, single-choice prompts
const SMALL = Vector2(450, 280)

## Medium: lists, selections, stratagems with detail
const MEDIUM = Vector2(550, 400)

## Large: complex multi-section forms, detailed results with logs
const LARGE = Vector2(700, 500)

## Gap kept below bottom-anchored gameplay dialogs so the phase-breadcrumb
## strip stays visible — matches AllocationGroupOverlay's _BOTTOM_CLEARANCE,
## so every bottom bar/dialog sits on the same baseline.
const BOTTOM_CLEARANCE := 48
