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

## Gap kept above full-height pre-battle dialogs so the top HUD bar (the
## 100px phase/status bar that Main._restructure_ui_layout anchors to the
## top of the screen) stays visible, plus a small breathing gap.
const TOP_HUD_CLEARANCE := 108
