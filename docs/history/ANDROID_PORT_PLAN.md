# Android Port Plan: Warhammer 40k Godot

## Executive Summary

This document analyzes the feasibility and strategy for porting the Warhammer 40k Godot tabletop game from desktop (mouse+keyboard) to Android phones. The project is a 2D top-down strategy game built with Godot 4.6 using the GL Compatibility renderer -- a strong foundation for mobile. The main challenges are **input translation** (mouse/keyboard to touch), **UI scaling** (1920x1080 desktop UI to small phone screens), and **information density** (this is a complex wargame with many panels, stats, and interactions).

---

## 1. Current Codebase Analysis

### 1.1 Project Stats
- **Engine**: Godot 4.6, GL Compatibility renderer
- **Rendering**: 2D only (Node2D + CanvasLayer), no 3D, no shaders
- **Game code**: ~134,000 lines across ~130 GDScript files
- **Scene count**: 7 game scenes (Main, MainMenu, MultiplayerLobby, etc.)
- **Autoloads**: 38 singleton managers
- **Display**: 1920x1080, fullscreen (mode=3), stretch mode `canvas_items`, aspect `expand`
- **Renderer**: Already set for mobile: `renderer/rendering_method.mobile="gl_compatibility"` and `import_etc2_astc=true`

### 1.2 What's Already Mobile-Friendly
- **GL Compatibility renderer** -- Godot's most portable backend, works on all Android devices
- **ETC2/ASTC texture compression** already enabled in project.godot
- **2D only** -- no 3D performance concerns
- **Stretch mode `canvas_items` with aspect `expand`** -- already supports varying screen ratios
- **No platform-specific dependencies** -- pure GDScript, no GDExtension/native code
- **Existing WebSocket multiplayer** -- network code will work unchanged on Android
- **Programmatic UI** -- almost all UI is built in code (not in .tscn scenes), making it easier to adapt dynamically

### 1.3 What Needs Significant Work

#### Input System (HIGH effort)
Every controller uses desktop-only input patterns:

| Pattern | Where Used | Count |
|---------|-----------|-------|
| `InputEventMouseButton` (left click) | All controllers | ~30+ locations |
| `InputEventMouseButton` (right click) | Main.gd, DeploymentController, DisembarkController | ~5 locations |
| `InputEventMouseMotion` (hover/drag) | Movement, Fight, Charge, Deployment, Measuring | ~15 locations |
| `Mouse wheel` (rotate models) | DeploymentController | 2 locations |
| `get_global_mouse_position()` | MovementController | ~15 calls |
| `KeybindingManager` keyboard shortcuts | Main.gd, all phases | ~30 bindings |
| `_input()` / `_unhandled_input()` | 8 scripts | 10+ handlers |

**Key input interactions that need touch equivalents:**
1. **Left click** → Select unit, place model, confirm target → **Single tap**
2. **Right click** → Cancel action, open context menu, undo → **Long press** or **dedicated button**
3. **Mouse hover** → Preview movement range, show LoS lines, tooltip → **No direct equivalent** (biggest challenge)
4. **Mouse drag** → Move models during movement/charge/fight phases → **Touch drag**
5. **Mouse wheel** → Rotate models during deployment → **Two-finger rotate** or **on-screen buttons**
6. **WASD/Arrow keys** → Pan camera → **Touch drag on empty space** or **two-finger pan**
7. **+/- keys** → Zoom → **Pinch to zoom**
8. **Keyboard shortcuts** (30+ bindings) → Various toggles → **On-screen toolbar/menu**

#### UI Layout (HIGH effort)
- All UI is hardcoded to 1920x1080 desktop layout
- Right HUD panel (unit list, unit card, buttons) assumes ~400px width
- Bottom HUD bar with phase info assumes full-width bar
- Font sizes hardcoded (11-22px) -- too small for phone screens
- Button minimum sizes designed for mouse precision, not touch targets (need 48dp+ for Android)
- Multiple side panels (Mathhammer, Save/Load, Army Panel, Settings) are desktop-width popups
- Dialogs (30+ dialog classes) use `AcceptDialog` with small buttons

#### Information Density (MEDIUM effort)
The game shows a lot simultaneously on desktop:
- Game board with unit tokens, terrain, deployment zones, objective markers
- Right panel: unit list + unit stats card + action buttons
- Bottom bar: phase info + status + action button
- Score/CP display, round indicator
- Game event log, dice history panel
- Various overlays (measuring tape, LoS lines, charge trajectories, etc.)

---

## 2. How Similar Games Handle Mobile

### 2.1 Warhammer 40,000: Tacticus (Official mobile game)
- Simplified rules (not full tabletop simulation)
- Large tap targets with unit portraits
- Actions via **bottom action bar** with large icon buttons
- **Tap-to-select, tap-to-move** model (no drag)
- Separate screens for different phases rather than overlays
- Unit stats in expandable bottom sheets

### 2.2 XCOM: Enemy Within (Mobile port)
- Camera: **Two-finger drag to pan, pinch to zoom**
- Unit selection: **Tap to select**
- Movement: **Tap destination** (shows movement range preview on selection, not hover)
- Actions: **Radial menu** around selected unit
- Info: **Tap-and-hold** for tooltips/details
- Minimal persistent UI; most info is contextual

### 2.3 Warhammer Quest / Total War: Medieval (Mobile ports)
- Full-screen board with minimal HUD overlay
- **Bottom drawer/sheet** pattern for unit details (swipe up to expand)
- Phase progression via **large center button**
- Context-sensitive action buttons appear near selected units

### 2.4 Civilization VI (Mobile port)
- Pan via single-finger drag on empty space
- Pinch to zoom
- Tap to select, tap to move
- **Bottom bar** for unit actions (compact icons)
- Long press for info/tooltips
- "Next turn" as prominent button

### 2.5 Chess.com / Lichess (Mobile tabletop reference)
- Board fills most of screen
- Player info in thin bars above/below board
- Minimal buttons; actions are purely tap-based

### Common Patterns Across All:
1. **Tap = Select/Act, Long Press = Info/Context, Pinch = Zoom, Two-finger drag = Pan**
2. **Bottom sheets** for detailed info (not side panels)
3. **Minimal persistent HUD** -- show info contextually
4. **Large touch targets** (minimum 44-48dp)
5. **Phase/turn actions as big centered buttons**
6. **Separate screens** for complex decisions rather than overlays

---

## 3. Recommended Architecture

### 3.1 Input Abstraction Layer

Create a new autoload `InputAdapter` that translates touch events to game actions:

```
InputAdapter (autoload)
├── Detects platform (mobile vs desktop)
├── Translates InputEventScreenTouch → game events
├── Translates InputEventScreenDrag → game events
├── Handles gesture recognition (pinch, long press, two-finger pan)
├── Emits unified signals:
│   ├── unit_tapped(unit_id, world_pos)
│   ├── board_tapped(world_pos)
│   ├── board_long_pressed(world_pos)
│   ├── drag_started(world_pos)
│   ├── drag_moved(world_pos)
│   ├── drag_ended(world_pos)
│   ├── pinch_zoomed(factor)
│   └── pan_moved(delta)
```

**Strategy**: Rather than rewriting every controller, create an abstraction layer that:
1. On desktop: passes through existing mouse/keyboard events unchanged
2. On mobile: translates touch gestures into equivalent mouse events OR emits unified signals

Godot 4.x has a `Project Settings > Input Devices > Pointing > Emulate Mouse from Touch` option that automatically converts single-touch to mouse events. This gets you ~70% of the way for free. The remaining 30% (multi-touch gestures, hover replacement, right-click alternatives) needs custom code.

### 3.2 Camera System for Touch

Replace the current WASD/keyboard zoom with a touch-aware camera:

```
TouchCamera (component added to Main.gd)
├── Single finger drag on empty board → Pan
├── Two-finger drag → Pan (when both fingers move same direction)
├── Pinch → Zoom (0.1x to 3.0x, matching current range)
├── Two-finger rotate → Optional board rotation
├── Double-tap → Quick zoom to point
├── Retains WASD/keyboard when on desktop
```

### 3.3 UI Restructure for Mobile

**Phase 1: Responsive Layout System**

```
Mobile Layout:
┌──────────────────────────┐
│  Score Bar (thin)        │  ← Compact: "P1: 5 CP:3 | R2 | P2: 3 CP:2"
├──────────────────────────┤
│                          │
│                          │
│    GAME BOARD            │  ← Fills ~70% of screen
│    (with tokens)         │
│                          │
│                          │
├──────────────────────────┤
│  Context Action Bar      │  ← Phase button + contextual actions
├──────────────────────────┤
│  Info Panel (bottom      │  ← Expandable bottom sheet
│  sheet - swipe up)       │     (unit card, weapons, targets)
└──────────────────────────┘
```

vs current desktop:
```
Desktop Layout:
┌────────────────────┬─────────┐
│  Score/Phase Top   │         │
├────────────────────┤  Right  │
│                    │  Panel  │
│  GAME BOARD        │  (Unit  │
│                    │  List,  │
│                    │  Card,  │
├────────────────────┤  Btns)  │
│  Bottom Bar        │         │
└────────────────────┴─────────┘
```

**Key changes:**
- Right panel → Bottom sheet (expandable drawer)
- Side panels (Mathhammer, Army) → Full-screen overlays or separate screens
- Dialogs (30+ types) → Resized with larger buttons, or converted to bottom sheets
- All font sizes → Scale factor based on screen DPI
- All buttons → Minimum 48dp touch targets
- Game log → Collapsible notification-style feed

### 3.4 Hover Replacement Strategy

This is the single biggest UX challenge. Desktop hover is used for:
1. **Movement range preview** -- shows possible destinations when hovering over a unit
2. **Line of Sight lines** -- drawn from selected shooter to hovered target
3. **Measuring tape preview** -- live distance while measuring
4. **Deployment hover tooltip** -- shows unit info when hovering in unit list
5. **Target highlighting** -- highlights valid targets when hovering

**Mobile alternatives:**
| Desktop Hover | Mobile Replacement |
|--------------|-------------------|
| Hover to preview movement range | **Show range on tap-select** (always visible while selected) |
| Hover over target for LoS preview | **Tap target to preview**, tap again to confirm (two-tap pattern) |
| Hover for tooltip | **Long press** for tooltip popup |
| Hover for measuring tape | **Tap start, drag to measure** (already works) |
| Hover highlights | **Show all valid targets highlighted** when a unit is selected |

The key insight from XCOM mobile: **show information on selection, not on hover**. When you tap a unit, immediately show its movement range, valid targets, etc. This eliminates most hover needs.

### 3.5 Right-Click Replacement

| Desktop Right-Click | Mobile Replacement |
|---------------------|-------------------|
| Cancel action | **Back button** (Android) or dedicated **Cancel button** in action bar |
| Context menu on unit | **Long press** on unit token |
| Undo placement | **Undo button** in action bar (already exists as a button) |

---

## 4. Implementation Plan (Phased)

### Phase 1: Foundation (Estimated: Large)
**Goal**: Get the game running on Android with basic touch input

1. **Enable "Emulate Mouse from Touch"** in project settings
   - This alone makes single-tap = left-click, touch-drag = mouse-drag
   - Gets deployment, movement, shooting selection mostly working

2. **Create `TouchCameraController`** autoload/component
   - Implement pinch-to-zoom (replacing +/- keys)
   - Implement two-finger-pan (replacing WASD)
   - Detect single-finger-on-empty-space for board panning
   - Keep desktop controls working in parallel

3. **Android export setup**
   - Configure Android export template in Godot
   - Set up signing, permissions, screen orientation (landscape)
   - Test on actual device / emulator

4. **Basic UI scaling**
   - Add DPI-aware font scaling (`OS.get_screen_dpi()`)
   - Increase all button minimum sizes to 48dp
   - Test readability on phone-sized screens

### Phase 2: Touch Input Adaptation (Estimated: Large)
**Goal**: Replace desktop-only interactions with touch equivalents

5. **Create `InputAdapter` autoload**
   - Gesture recognizer: long press (500ms threshold), pinch, two-finger pan
   - Platform detection: `OS.get_name() == "Android"`
   - Event translation layer

6. **Replace right-click with long press**
   - Main.gd `_handle_right_click()` → trigger on long press
   - DisembarkController right-click undo → on-screen undo button
   - DeploymentController right-click cancel → on-screen cancel button

7. **Replace hover interactions**
   - MovementController: show range preview on unit selection (not hover)
   - ShootingController: show LoS on target tap (first tap = preview, second = confirm)
   - DeploymentController: show unit info in bottom panel on list item tap
   - Add "preview mode" where tapping shows info before committing

8. **Replace mouse wheel rotation**
   - DeploymentController model rotation → two on-screen rotation buttons (< >) or two-finger twist
   - Add rotation buttons to the mobile action bar

9. **Replace keyboard shortcuts**
   - Create a floating action toolbar for most-used actions
   - Measuring tape → toggle button in toolbar
   - Toggle terrain/zones → settings sub-menu
   - Quick save/load → accessible from pause menu

### Phase 3: Mobile UI Redesign (Estimated: Very Large)
**Goal**: Redesign the interface to be phone-native

10. **Bottom sheet system**
    - Create reusable `BottomSheet` component (drag handle, snap points)
    - Migrate unit card from right panel to bottom sheet
    - Migrate unit list to a collapsible list in the bottom sheet
    - Migrate weapon assignment UI (ShootingController) to bottom sheet

11. **Compact top bar**
    - Merge score display, round indicator, phase label into single compact bar
    - CP display as small badges
    - Phase action button → large centered button above bottom sheet

12. **Dialog redesign** (30+ dialog classes)
    - All dialogs need larger buttons, better spacing
    - Complex dialogs (AttackAssignment, WoundAllocation) need scroll support
    - Consider converting some to full-screen on mobile
    - Priority dialogs to redesign first:
      - `AttackAssignmentDialog` (weapon-to-target assignment)
      - `WoundAllocationOverlay` (wound allocation per model)
      - `StratagemDialog` (stratagem selection)
      - `FightSelectionDialog` (fight phase target selection)

13. **Mobile-specific overlays**
    - Game event log → notification toasts (already has ToastManager)
    - Dice history → expandable mini-panel
    - AI thinking indicator → already overlay-based, just scale
    - Phase transition banner → already overlay, will scale

14. **Action bar / context menu**
    - Floating action bar at bottom of board area
    - Context-sensitive: changes based on current phase
    - E.g., Movement Phase: [Undo] [Confirm] [End Phase]
    - E.g., Shooting Phase: [Back] [Assign All] [Fire] [End Phase]

### Phase 4: Polish and Optimization (Estimated: Medium)
**Goal**: Performance tuning and mobile UX polish

15. **Performance optimization**
    - Profile on target Android devices
    - Optimize token drawing (TokenVisual, CoherencyCircleVisual)
    - Reduce draw calls if needed (batch similar sprites)
    - Optimize LoS calculations (already heavy on desktop)

16. **Touch feedback**
    - Add haptic feedback on unit selection, dice rolls, damage
    - Add visual touch feedback (ripple effect on tap)
    - Larger selection hitboxes for unit tokens on mobile

17. **Screen orientation**
    - Lock to landscape (matching the board aspect ratio)
    - Handle notch/punch-hole safe areas
    - Handle Android navigation bar (gesture nav vs 3-button)

18. **Quality of life**
    - Auto-save on app backgrounding
    - Handle app lifecycle (pause/resume)
    - Battery optimization (reduce frame rate when idle)
    - Wake lock during active play

---

## 5. Technical Considerations

### 5.1 Godot Android Export Requirements
- Android SDK (API level 33+ recommended)
- Android NDK
- JDK 17
- Godot export templates for Android
- Debug keystore for testing, release keystore for distribution
- `AndroidManifest.xml` permissions: INTERNET (for multiplayer)

### 5.2 Performance Budget
- Target: 60 FPS on mid-range Android (Snapdragon 600-series)
- The game is 2D with no shaders -- should be well within budget
- Main concerns: large token counts (many models on board), LoS ray calculations
- GL Compatibility renderer is the lightest option -- good choice already

### 5.3 Screen Size Targets
- Primary: Phone landscape (2400x1080, 2560x1440 common)
- Secondary: Tablet landscape (2560x1600, 2048x1536)
- Minimum viable: 1280x720 (low-end phones in landscape)
- The existing `stretch/mode="canvas_items"` and `stretch/aspect="expand"` handles this well

### 5.4 What Does NOT Need to Change
- Game logic (all phase managers, rules engine, scoring, etc.)
- Data layer (GameState, ArmyListManager, unit data, JSON configs)
- AI system (AIPlayer, AIDecisionMaker, difficulty configs)
- Network/multiplayer code (WebSocket relay works on all platforms)
- Save/Load system (uses `user://` paths which work on Android)
- Sound (DiceSoundManager)
- All 38 autoloads (game logic singletons)

---

## 6. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Touch precision for small model tokens | HIGH | Increase tap hitbox radius on mobile; auto-zoom to active area |
| Information overload on small screen | HIGH | Bottom sheet pattern; show info progressively; minimize persistent HUD |
| 30+ dialogs need redesign | MEDIUM | Start with most-used dialogs; others can use scaled defaults initially |
| Hover-dependent UX is deeply embedded | MEDIUM | Two-tap pattern (tap to preview, tap to confirm) replaces most hover needs |
| Performance with many models | LOW | Already 2D GL Compat; profile and optimize if needed |
| Multiplayer across phone/desktop | LOW | WebSocket is platform-agnostic; no changes needed |

---

## 7. Recommended Approach: Incremental, Not Rewrite

**Do NOT** fork or create a separate mobile codebase. Instead:

1. Use **platform detection** (`OS.get_name() == "Android"` or `OS.has_feature("mobile")`) to branch UI/input behavior
2. Keep a **single codebase** that works on both desktop and mobile
3. Use **Godot's built-in touch emulation** as the first step (free ~70% compatibility)
4. Create a **responsive UI system** that adapts layout based on screen size
5. Implement changes in **phases** -- each phase results in a playable (if imperfect) mobile build

The game is **absolutely portable to Android** -- the engine supports it natively, the rendering is lightweight, and the architecture is clean. The main investment is in **UI/UX adaptation**, not in engine or logic changes.

---

## 8. Effort Estimate Summary

| Phase | Description | Relative Size |
|-------|-------------|--------------|
| Phase 1 | Foundation (touch emulation, camera, export setup) | Medium |
| Phase 2 | Touch input adaptation (gestures, hover replacement) | Large |
| Phase 3 | Mobile UI redesign (bottom sheets, dialogs, layout) | Very Large |
| Phase 4 | Polish and optimization | Medium |

Phase 1 alone would produce a **playable but rough** mobile experience. Phases 1+2 would be **functional**. All four phases would produce a **polished mobile game**.
