# Product Requirement Prompt (PRP) Best Practices for Claude

## Overview

This document provides best practices for creating effective Product Requirement Prompts that maximize Claude's ability to understand, plan, and implement your project requirements.

---

## 1. Structure Your PRD/PRP with Clear Sections

Use predictable, clearly labeled sections that Claude can parse:

```markdown
- Introduction / Project Overview
- Problem Statement
- Solution / Feature Overview
- User Stories
- Technical Requirements
- Acceptance Criteria
- Constraints & Non-Negotiables
- Technical Specs & Business Logic
```

**Why it matters:** Claude can be prompted to fetch specific sections, which works best when sections are clearly labeled with consistent headings.

---

## 2. Write Atomic User Stories

Keep each user story focused on a single requirement:

**Good:**
```
As a project manager, I want to tag tasks with priority levels so I can filter them easily.
```

**Avoid:**
Long paragraphs containing multiple requirements—Claude may miss or blend details.

---

## 3. Use Explicit Acceptance Criteria as Bullet Points

List criteria as discrete, checkable items:

```markdown
- The "High Priority" tag appears in red
- Tasks can be filtered by priority on the main dashboard
- Filtering persists on page refresh
- Error message displays if filter fails
```

**Why:** Bullets act like discrete checkboxes Claude can "tick off" during implementation.

---

## 4. State Constraints and Non-Negotiables Clearly

Call out hard boundaries explicitly:

```markdown
## Constraints
- Must use OAuth 2.0 for authentication
- Support at least 10,000 concurrent sessions
- No external cloud services due to compliance
- Must follow Warhammer 40K 10th Edition core rules
```

Claude will avoid suggesting anything that violates clearly stated constraints.

---

## 5. Include Technical Specs & Business Logic

Document specifics Claude needs to implement correctly:

- APIs and their parameters
- Data models with field names and types
- Architecture diagrams or descriptions
- Key formulas or rules (e.g., damage calculations, point costs)
- File structure and naming conventions

---

## 6. Use Consistent Formatting

- If you number user stories (US1, US2), maintain that pattern
- If acceptance criteria start with verbs, do so throughout
- Use consistent markdown heading levels

Pattern consistency makes parsing easier for both humans and Claude.

---

## 7. Create a CLAUDE.md File

While your PRP explains **what** to build, `CLAUDE.md` tells Claude **how** to build it:

```markdown
# CLAUDE.md - Project Guidelines

## Tech Stack
- Engine: Godot 4.3
- Language: GDScript
- Architecture: Component-based with signals

## Code Style
- Use snake_case for variables and functions
- PascalCase for class names
- All game rules must reference WH40K 10th Edition

## Commands
- `godot --headless --script run_tests.gd` - Run tests
- `godot --export-release` - Build release

## Do Not
- Modify files in `/core/rules/` without explicit approval
- Use global state for game logic
- Hard-code unit stats (use data files)
```

---

## 8. Leverage Extended Thinking

Use trigger words to activate deeper reasoning:

| Phrase | Thinking Level |
|--------|----------------|
| "think" | Basic extended thinking |
| "think hard" | Moderate depth |
| "think harder" | Deep analysis |
| "ultrathink" | Maximum reasoning |

**Example:** "Ultrathink about how to implement the shooting phase rules while maintaining multiplayer sync."

---

## 9. Use Plan Mode Before Coding

Ask Claude to plan before implementing:

```
Before writing any code, create a detailed implementation plan for the movement phase. 
Include:
1. Which files need to be created/modified
2. The sequence of implementation steps
3. Potential edge cases to handle
4. How it integrates with existing systems

Do not write code until I approve the plan.
```

---

## 10. Break Complex Features into Phases

For large features, structure implementation in phases:

```markdown
## Feature: Combat Resolution System

### Phase 1: Basic Hit Resolution
- Implement dice rolling system
- Calculate hit rolls based on BS/WS
- Display hit results

### Phase 2: Wound Resolution
- Implement strength vs toughness table
- Calculate wound rolls
- Track wounds per unit

### Phase 3: Save Resolution
- Implement armor saves
- Handle invulnerable saves
- Apply damage to models
```

---

## 11. Reference External Documentation

Point Claude to authoritative sources:

```markdown
## Reference Documents
- @docs/wh40k_core_rules.md - Core game mechanics
- @docs/unit_datasheet_format.md - Unit data structure
- @docs/architecture.md - System architecture

When implementing rules, always verify against the core rules document.
```

---

## 12. Use Checkboxes for Task Tracking

Create trackable implementation lists:

```markdown
## Implementation Tasks

### Movement Phase
- [ ] Implement unit selection
- [ ] Calculate movement range
- [ ] Handle terrain modifiers
- [ ] Validate legal moves
- [ ] Sync movement across network

### Shooting Phase  
- [ ] Target selection UI
- [ ] Line of sight calculation
- [ ] Weapon range validation
- [ ] Hit roll resolution
```

Claude can check these off as it completes them.

---

## 13. Maintain Context Efficiency

**Keep CLAUDE.md lean:**
- Only include what's needed in EVERY session
- Use `/clear` between tasks
- Store detailed docs in `docs/` and reference with `@docs/filename.md`

**Avoid:**
- Generic instructions like "write clean code"
- Redundant information
- Outdated context

---

## 14. Sample PRP Template for Your Warhammer 40K Godot Game

```markdown
# Product Requirement Prompt: [Feature Name]

## Context
Brief description of what this feature does and why it's needed.
Reference: This implements [specific WH40K rule from page X].

## User Stories
- As a player, I want to [action] so that [benefit]
- As an opponent, I want to [action] so that [benefit]

## Technical Requirements
- Must sync across network for multiplayer
- Must follow existing signal architecture
- Must use data-driven unit stats from `/data/units/`

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Constraints
- Must match WH40K 10th Edition rules exactly
- Maximum 16ms frame time impact
- Must work with existing undo system

## Implementation Notes
Any specific technical guidance or gotchas.

## Related Files
- @src/combat/shooting_phase.gd
- @docs/combat_rules.md
```

---

## Quick Reference: Prompt Patterns

| Goal | Prompt Pattern |
|------|----------------|
| Get a plan | "Create a plan for X. Do not code yet." |
| Deep analysis | "Ultrathink about how to implement X" |
| Iterate safely | "Make changes on a new branch first" |
| Verify understanding | "Summarize your understanding of X before proceeding" |
| Reference docs | "Read @docs/X.md before implementing" |
| Track progress | "Update the checklist in plan.md as you complete items" |

---

## Summary

1. **Structure clearly** - Use consistent sections and formatting
2. **Be specific** - Atomic user stories, explicit acceptance criteria
3. **State constraints** - Non-negotiables up front
4. **Use CLAUDE.md** - Persistent project context
5. **Plan first** - Use plan mode before coding
6. **Track progress** - Checkboxes and external plan files
7. **Manage context** - Keep files lean, clear often
8. **Reference docs** - Point to authoritative sources

Following these practices ensures Claude always has the right context, in the right format, at the right time.
