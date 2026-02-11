# Deployment Phase UI Audit

Tracks outstanding UI/UX improvements for the Deployment Phase based on the design spec in `INITIAL.md`.

## Completed

### Deployment Progress Indicator
**Status:** DONE
**Files Modified:**
- `40k/autoloads/GameState.gd` - Added `get_deployment_progress(player)` helper returning `{deployed, total}` counts per player (skips embarked/attached units)
- `40k/scripts/Main.gd` - Added programmatic deployment progress panel with:
  - Per-player progress bars (Player 1 blue, Player 2 red) using WhiteDwarfTheme colors
  - Labels showing "Player N (Defender/Attacker): X/Y units deployed"
  - Auto-shows during DEPLOYMENT phase, hidden during all other phases
  - Updates on every `update_ui()` call and phase transitions
  - Positioned between left/right HUD panels below the top bar
  - Themed with gothic WhiteDwarfTheme styling (gold borders, dark background)

## Outstanding Items

### 1. Coherency Warning Display
**Priority:** Medium
**Description:** Per INITIAL.md spec, placement should show a non-blocking yellow banner warning when models are placed >2" from unit mates (2-6 model units) or when models lack 2 neighbors within 2" (7+ model units). Currently coherency is not enforced or warned about during deployment.
**Effort:** Medium - requires distance calculations between placed models during ghost placement.

### 2. Ghost Preview Color Feedback
**Priority:** Medium
**Description:** The ghost cursor should turn red when outside the deployment zone and yellow when a coherency warning would trigger. Currently the ghost is a static semi-transparent preview.
**Effort:** Low-Medium - extend ghost rendering with zone/coherency checks.

### 3. Deployment Zone Tooltips
**Priority:** Low
**Description:** Per spec, hovering over a deployment zone should show a tooltip ("Your zone"). Not currently implemented.
**Effort:** Low - add tooltip to Polygon2D zones.

### 4. Collapsible HUD Panels
**Priority:** Low
**Description:** INITIAL.md specifies both bottom and right HUD panels should be collapsible with toggle buttons. The left panel has a toggle, but the right panel and top bar do not.
**Effort:** Low - add toggle visibility buttons.

### 5. Red Toast for Invalid Placement
**Priority:** Medium
**Description:** Clicks outside the deployment zone during placement should show a red toast message ("Must be wholly within deployment zone"). Currently this is logged but no visual toast is shown to the user.
**Effort:** Low - create a temporary popup label with fade animation.

### 6. Unit Card Characteristics Display
**Priority:** Low
**Description:** The UnitCard in the right HUD should show full unit characteristics (T, W, Sv, etc.) in addition to name, keywords, and model count. Currently only name, keywords, and model count are shown.
**Effort:** Medium - needs stat rendering in the card panel.

## Suggested Next Task

**Coherency Warning Display** (Item #1) is the most impactful next task. It implements a core 10th edition rule (unit coherency at setup) and provides important visual feedback during model placement. It builds on the existing placement validation in `DeploymentController.try_place_at()` and the ghost preview system.
