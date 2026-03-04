# Save/Load System Audit — Implementation Review

> **Audit v1** (2026-03-03) of `SaveLoadManager.gd`, `StateSerializer.gd`, `GameState.gd`, `SaveLoadDialog.gd`, `Main.gd`, `NetworkManager.gd`
>
> Focus: Desktop save/load, AI game persistence, multiplayer sync, cloud saves, autosave, validation.

---

## Executive Summary

The save/load system has a **solid desktop single-player foundation**: snapshot creation, JSON serialization with type conversion, file I/O with backups, quick save/load, autosave, and a functional UI dialog. However, **multiplayer sync is fragile**, **AI game loading is incomplete**, and **there is no save format migration system** for handling schema changes. Cloud saves exist in skeleton form but lack robustness.

**Overall system score: ~5.5/10** — Functional for single-player desktop but needs significant work for multiplayer and AI game reliability.

---

## 1. What's Implemented and Working

| Feature | Status | Location |
|---------|--------|----------|
| Game state snapshot creation | ✅ | `GameState.gd:create_snapshot()` |
| Snapshot restoration | ✅ | `GameState.gd:load_from_snapshot()` |
| JSON serialization with Vector2/Vector3/PackedVector2Array conversion | ✅ | `StateSerializer.gd` |
| Desktop file save/load (`.w40ksave` + `.meta` sidecar) | ✅ | `SaveLoadManager.gd` |
| Quick save/load (single slot) | ✅ | `SaveLoadManager.gd` |
| Backup creation on overwrite (last 5) | ✅ | `SaveLoadManager.gd` |
| Autosave on round end | ✅ | `SaveLoadManager.gd` |
| Autosave rotation (max 10 files) | ✅ | `SaveLoadManager.gd` |
| Save/Load dialog UI with listing and metadata | ✅ | `SaveLoadDialog.gd` |
| Basic validation of serialized data (required sections/fields) | ✅ | `StateSerializer.gd` |
| Formation metadata backfill for old saves | ✅ | `GameState.gd` |
| Terrain layout reload from file or fallback | ✅ | `GameState.gd` |
| Secondary mission state persistence | ✅ | `GameState.gd` |
| Measuring tape persistence (configurable) | ✅ | `GameState.gd` |
| Phase restoration on load (skips to saved phase) | ✅ | `Main.gd` |
| Unit visual recreation after load | ✅ | `Main.gd` |
| Desktop save/load notifications | ✅ | `Main.gd` |

---

## 2. Critical Issues

### 2.1 CRITICAL: AI Game Load Does Not Re-initialize AI Player

**Problem:** When loading a saved AI game, `_initialize_ai_player()` runs during initial scene setup but is NOT re-invoked after a mid-session load. If the loaded save has different AI config (difficulty, player types), the running AI won't reflect the loaded state. AI signals may not be reconnected, and AI thinking state is not cleaned up before load.

**Missing:**
- `reconfigure_ai_after_load(game_config)` function
- AI thinking cancellation before load
- AI signal reconnection after load

**Impact:** Loading an AI game mid-session may produce broken AI behavior or crashes.

### 2.2 CRITICAL: Multiplayer Load Sync Has No Confirmation

**Problem:** `NetworkManager.sync_loaded_state()` broadcasts the loaded snapshot to clients via RPC, but:
- No confirmation that clients received and applied the state
- No timeout handling if clients are unreachable
- No error handling if RPC delivery fails
- Host proceeds immediately after broadcast without waiting
- Web relay path uses different code path than direct RPC

**Impact:** Host and client state can silently diverge after a multiplayer load.

### 2.3 CRITICAL: No Save Format Versioning/Migration

**Problem:** `StateSerializer` hardcodes version "1.0.0" with `SUPPORTED_VERSIONS = ["1.0.0"]`. There is no migration system to upgrade old saves when the game data format changes.

**Impact:** Any schema change (new fields, renamed enums, restructured data) will make all existing saves incompatible with no upgrade path.

### 2.4 HIGH: `_refresh_after_load()` Does Not Fully Restore Game State

**Problem:** `Main._refresh_after_load()` updates UI elements but:
- Does not clear old unit visuals before recreating them (potential duplicates)
- Does not reinitialize phase controllers for the loaded phase
- Does not refresh dependent systems (EffectChainManager, DiceHistoryPanel, etc.)
- Does not reinitialize AI player if loaded game has AI
- Does not validate loaded state before applying

**Impact:** Visual glitches, stale UI state, and broken phase controllers after load.

### 2.5 HIGH: Web Platform `save_exists()` Always Returns False

**Problem:** `SaveLoadManager.save_exists()` returns `false` on web platforms because cloud storage is async. This means the overwrite confirmation dialog never triggers for web saves.

**Impact:** Cloud saves can be silently overwritten without user confirmation.

---

## 3. Multiplayer-Specific Issues

### 3.1 HIGH: Client UI Not Properly Refreshed After Load

When the host loads a save and syncs state to clients:
- `NetworkManager._refresh_client_ui_after_load()` calls `main_scene._refresh_after_load()`
- But this doesn't clear stale visuals, reset phase controllers, or handle unit changes between old and new state
- Old unit tokens may remain on screen alongside newly loaded ones

### 3.2 HIGH: No Multiplayer Load Restriction UI

- Only the host can initiate loads (clients blocked with error)
- But the Save/Load dialog is still accessible to clients — they get an error only after attempting to load
- Should hide or disable the Load button for non-host players in multiplayer

### 3.3 MEDIUM: Multiplayer Autosave Behavior Undefined

- Autosave triggers (round end, phase transition, timer) don't check if in a multiplayer session
- If autosave fires on the host, it saves correctly — but clients may also autosave independently
- Client autosaves would be host-state snapshots from the client's perspective, which may be stale

### 3.4 MEDIUM: No "Load Game" Flow for Resuming Multiplayer

When two players want to resume a previously saved multiplayer game:
- Host loads the save and starts hosting
- Client connects and receives the game state
- But there's no dedicated "Resume Multiplayer Game" flow — the client must connect first, then the host must load
- No UI guidance for this workflow

---

## 4. AI-Specific Issues

### 4.1 HIGH: AI Turn History Not Saved

`AIPlayer` maintains turn history that informs decision-making, but this is not included in the game state snapshot. After loading, the AI has no memory of previous turns and may make suboptimal or inconsistent decisions.

### 4.2 HIGH: Autosave Can Fire During AI Turn

Autosave on phase transition can trigger while the AI is mid-action, capturing an incomplete intermediate state. Loading such a save would start with a half-completed AI turn.

### 4.3 MEDIUM: AI Speed/Config Not Shown in Save Metadata

The `.meta` sidecar stores player types (HUMAN/AI) but not AI difficulty level or speed settings. Save file listing doesn't show this information.

---

## 5. Quality of Life Improvements

### 5.1 No Save File Preview/Summary

The save list shows name, timestamp, turn, and phase — but no information about:
- Army compositions (factions, total points)
- Board state preview (minimap thumbnail)
- VP scores
- Number of units remaining per player

### 5.2 No Save Slot System

Only a single quicksave slot exists. No numbered save slots (Save 1, Save 2, etc.) for players who want multiple save points in a single game.

### 5.3 No Load Confirmation Dialog

Loading a save replaces the current game state without warning about unsaved progress. Should prompt "You have unsaved changes. Load anyway?"

### 5.4 No Save File Export/Import

No way to share save files between players (e.g., email a save to a friend). Would need a portable file format with embedded army data.

### 5.5 Save/Load Dialog Lacks Sorting and Filtering

Save files are listed chronologically. No way to sort by name, filter by game type (AI vs multiplayer), or search.

---

## 6. Visual Improvements

### 6.1 No Save/Load Animation or Progress Indicator

Save and load operations happen instantly with no visual feedback during the operation (just a success/failure toast after). For cloud saves especially, a progress indicator would be appropriate.

### 6.2 No "Game Loaded" Transition

After loading, the game state snaps to the loaded state with no transition. A brief overlay showing "Loading save... [save name]" with a fade transition would be smoother.

### 6.3 Autosave Has No Visual Indicator

When autosave triggers, there's no visual indicator (like a floppy disk icon or brief notification) to let the player know the game was saved.

---

## 7. Code Quality Observations

### 7.1 No Unit Data Validation on Load

StateSerializer validates structure (required sections/fields) but not data integrity:
- No check that unit IDs are unique
- No check that model positions are valid (on board, not overlapping)
- No check that unit statuses are consistent (e.g., deployed unit has positions)
- No check that player CP/VP values are reasonable

### 7.2 Deep Copy Could Miss Nested References

`GameState._deep_copy_dict()` handles Dictionary and Array but may not catch all Godot-specific types that need deep copying (e.g., PackedVector2Array).

### 7.3 StateSerializer Compression Disabled

GZIP compression support exists but is disabled. For large games with many units, save files could benefit from compression.

---

## 8. Priority Summary

### P0 — Must Fix (Correctness)
1. **Fix AI re-initialization after load** — Add `reconfigure_ai_after_load()` call in load completion path (SAVE-1) — **DONE**
2. **Fix multiplayer load sync confirmation** — Add client acknowledgment mechanism (SAVE-2)
3. **Implement save format migration system** — Version tracking + upgrade functions (SAVE-3) — **DONE**
4. **Fix `_refresh_after_load()` to fully restore state** — Clear old visuals, reinit controllers, reinit AI (SAVE-4)
5. **Fix web `save_exists()` for overwrite protection** — Async check before cloud save (SAVE-5) — **DONE**

### P1 — Should Fix (Robustness)
6. **Prevent autosave during AI turn** — Guard autosave triggers with AI thinking check (SAVE-6) — **DONE**
7. **Save AI turn history in snapshot** — Add AI decision history to save data (SAVE-7) — **DONE**
8. **Hide Load button for non-host in multiplayer** — UI restriction (SAVE-8) — **DONE**
9. **Add load confirmation dialog** — Warn about unsaved progress (SAVE-9) — **DONE**
10. **Add autosave visual indicator** — Brief icon/toast when autosave triggers (SAVE-10) — **DONE**

### P2 — Should Improve (QoL/Visual)
11. **Add save file preview** — Show army compositions, VP scores, unit counts (SAVE-11) — **DONE**
12. **Add "Game Loaded" transition** — Fade overlay during load (SAVE-12) — **DONE**
13. **Add AI difficulty to save metadata** — Show in save file listing (SAVE-13) — **DONE**
14. **Add save list sorting/filtering** — By name, date, game type (SAVE-14) — **DONE**
15. **Add multiplayer resume flow** — Dedicated UI for resuming saved multiplayer games (SAVE-15) — **DONE**

### P3 — Nice to Have
16. **Add multiple save slots** — Beyond single quicksave (SAVE-16)
17. **Enable save file compression** — Activate GZIP for large saves (SAVE-17)
18. **Add unit data validation on load** — Integrity checks beyond structure (SAVE-18)
19. **Add save file export/import** — Portable format for sharing (SAVE-19)
20. **Add save/load progress indicator** — For cloud saves especially (SAVE-20)

---

## Appendix A: File Inventory

| File | Purpose |
|------|---------|
| `40k/autoloads/SaveLoadManager.gd` | High-level save/load interface, file management, cloud sync, autosave |
| `40k/autoloads/StateSerializer.gd` | JSON serialization/deserialization, type conversion, validation |
| `40k/autoloads/GameState.gd` | Game state model, snapshot creation/restoration |
| `40k/scripts/SaveLoadDialog.gd` | UI for save/load operations |
| `40k/scripts/Main.gd` | Phase restoration, unit visual recreation, AI re-init |
| `40k/autoloads/NetworkManager.gd` | Multiplayer state sync via RPC/relay |
| `40k/scripts/MainMenu.gd` | Load button UI, save file listing |
