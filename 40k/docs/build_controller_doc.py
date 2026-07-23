#!/usr/bin/env python3
"""Generate the Controller Controls Map — the source-of-truth HTML doc.

Reads the hint-set constants dumped live from PadRouter (hints_dump.json) plus
the narrative metadata defined below, and emits:
  - 40k/docs/controller_hint_sets.json   (machine-readable mirror of the code
    constants; checked by the drift-test)
  - 40k/docs/CONTROLLER_CONTROLS_MAP.html (repo copy, relative image refs)
  - a self-contained copy (embedded data-URI images) for publishing as an Artifact
"""
import json, os, base64, html

# Reproducible generator (committed alongside the doc).
# Regenerate the doc after an intentional control change:
#   1. re-dump PadRouter.HINTS_* into docs/controller_hint_sets.json
#      (via the addons/godot_mcp bridge or a headless dump), then
#   2. python3 docs/build_controller_doc.py
# The drift-test (tests/test_controller_controls_doc_sync.gd) enforces that the
# JSON matches the live constants, so this stays honest.
DOCS = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(DOCS, "controller_shots")
SP = DOCS  # self-contained copy is written next to the repo doc

# Button glyph display names — mirrors scripts/input/GlyphDB.gd GLYPHS.
GLYPHS = {
    "a": "A",
    "b": "B",
    "dpad": "✚",
    "l3": "L3",
    "l4": "L4",
    "lb": "LB",
    "ls": "LS",
    "lt": "LT",
    "menu": "☰",
    "r3": "R3",
    "r4": "R4",
    "rb": "RB",
    "rs": "RS",
    "rt": "RT",
    "view": "⧉",
    "x": "X",
    "y": "Y"
}

with open(os.path.join(DOCS, "controller_hint_sets.json")) as f:
    HINTS = json.load(f)

# ---------------------------------------------------------------------------
# Narrative metadata. `hint_set` keys index into HINTS (the live code dump), so
# the button rows are never hand-transcribed — they come straight from the code.
# ---------------------------------------------------------------------------

# Physical button map (always-on meanings). glyph -> (name, meaning)
PHYSICAL = [
    ("ls",  "Left stick",        "Virtual cursor — point at the board, drag models, aim placement"),
    ("l3",  "L3 (click LS)",     "Next model — cycle the active unit's individual models (Movement / Charge; in Movement the D-pad ◀▶ do this too)"),
    ("rs",  "Right stick",       "Pan the camera"),
    ("r3",  "R3 (hold RS)",      "Precision modifier — hold to slow the cursor for fine placement"),
    ("lt",  "Left trigger",      "Zoom out"),
    ("rt",  "Right trigger",     "Zoom in"),
    ("lb",  "Left bumper",       "Previous unit (cycle the acting unit) · rotate ⟲ while carrying a model"),
    ("rb",  "Right bumper",      "Next unit (cycle the acting unit) · rotate ⟳ while carrying a model"),
    ("a",   "A",                 "Context confirm — select / assign / place / pick-up / drop / press"),
    ("b",   "B",                 "Back — deselect / cancel / undo / release panel focus"),
    ("x",   "X",                 "Context action — skip unit / undo model / finish model / snap to contact"),
    ("y",   "Y",                 "Toggle the datasheet of the highlighted unit / target"),
    ("dpad","D-pad",             "Menus & steppers — phase sub-menu, target/weapon steps, move models (Movement: ◀▶ switch · ▲ all · ▼ one), or focus the panels"),
    ("menu","Start (☰)",         "Context confirm / End Phase (pad_phase_action)"),
    ("view","View / Select (⧉)", "Pause menu — Save/Load, Settings, Return to Main Menu (pad_menu_action)"),
    ("l4",  "L4 / R4 paddles",   "Prev / next model — same as L3, only if Steam Input forwards the Deck paddles"),
]

# Right-panel accessibility verdicts
RP_YES = ("yes", "Yes — D-pad enters panel focus; buttons only (unit lists are bumper-only)")
RP_LISTONLY = ("list", "Units via bumpers only — the list itself can't be walked on pad")
RP_NO_PREEMPT = ("no", "No — the D-pad is consumed by this state's steppers/menu; back out (B) first")
RP_NO_STANDDOWN = ("no", "No — panel focus stands down mid-carry / locked; act on the board first")
RP_SELECTORS = ("partial", "The card's Model-type / Formation selectors ARE the D-pad target here")
RP_FIGHT = ("yes", "Yes — bumpers cycle the fight-panel buttons, D-pad navigates the panel")
RP_INPANEL = ("yes", "You are in the panel — D-pad navigates, A presses, B returns to board")
RP_DIALOG = ("dialog", "A dialog owns the pad — A confirms, B cancels, D-pad walks its buttons")

SECTIONS = [
    # ---- pre-battle & menus ----
    {
        "id": "main-menu", "group": "Menus & shell", "title": "Main menu",
        "blurb": "The army/mission setup screen shown on launch. Pure native Godot focus navigation — no board router involved.",
        "shot": "01_main_menu.png",
        "states": [{
            "name": "Setup screen",
            "when": "On launch, before a game starts.",
            "custom": [
                ("dpad", "Move focus between dropdowns and buttons (ui_up/down/left/right)"),
                ("a", "Press the focused button / open the focused dropdown"),
                ("b", "Nothing — this is the root screen, there is no 'back'"),
            ],
            "rp": ("na", "N/A — no in-game panels yet"),
            "notes": ["Start Game is the default-focused control (grab_focus on load).",
                      "The top-right 'Controller: not detected / ACTIVE' label is a live diagnostic."],
        }],
    },
    {
        "id": "pause", "group": "Menus & shell", "title": "Pause / Settings menu",
        "blurb": "There is no separate pause panel: View (⧉) runs a cascade that closes the top open overlay, or opens the Settings menu (which hosts Save/Load and Return to Main Menu).",
        "shot": "09_pause_settings_menu.png",
        "states": [{
            "name": "Settings menu open",
            "when": "After pressing View (⧉) with nothing else open.",
            "custom": [
                ("view", "Open the menu (and closes the top overlay if one is up)"),
                ("dpad", "Move between tabs (Audio / Visual / Gameplay / Controls) and controls"),
                ("a", "Activate the focused tab / slider / checkbox / button"),
                ("b", "Close the menu (ui_cancel)"),
            ],
            "rp": ("dialog", "The menu is modal and traps pad focus until closed"),
            "notes": ["Full controller navigation; Close is default-focused.",
                      "The Controls tab shows a read-only controller reference.",
                      "GAP: keybinding remap only captures keyboard keys — you cannot rebind actions to gamepad buttons.",
                      "Save/Load dialog: the saves list is walkable with the D-pad; A loads, B closes."],
        }],
    },
    {
        "id": "datasheet", "group": "Menus & shell", "title": "Datasheet overlay",
        "blurb": "The unit stat card. Opened anywhere with Y over a highlighted / selected unit.",
        "shot": "10_datasheet_modal.png",
        "states": [{
            "name": "Datasheet shown",
            "when": "After pressing Y with a unit highlighted or selected.",
            "custom": [
                ("y", "Open — and press again to close (toggle)"),
                ("b", "Does NOT close it — B is board 'back', not the datasheet (keyboard Esc closes it)"),
            ],
            "rp": ("na", "N/A — display-only overlay"),
            "notes": ["GAP: closes only with Y on pad (not the console-standard B).",
                      "GAP: no scroll container — a datasheet taller than the card is clipped (pad or mouse)."],
        }],
    },
    {
        "id": "formations", "group": "Pre-battle", "title": "Formations / setup dialogs",
        "blurb": "Formations, Roll-off, First-turn roll-off and the deployment sub-dialogs (attach leader / embark) are AcceptDialogs. A lands on the confirm button, B cancels, and once a button is focused the D-pad walks the rest.",
        "shot": "02_formations_or_prebattle.png",
        "states": [{
            "name": "Declaration / roll dialog open",
            "when": "Formations declaration, roll-off, first-turn roll-off, and confirm dialogs.",
            "hint_set": "HINTS_FOCUS",
            "rp": RP_DIALOG,
            "notes": ["The pad hint bar shows the focus set (✚ Navigate · A Press · B Back To Board).",
                      "Start (☰) fires the phase action — e.g. Confirm Formations — shown top-right.",
                      "Roll-off winner picks deploy order by D-pad'ing to the choice button and pressing A."],
        }],
    },
    {
        "id": "deployment", "group": "Pre-battle", "title": "Deployment",
        "blurb": "Placing models on the table. The one phase where LB/RB additionally lock once you place a model of the current unit (undo them all to switch units).",
        "shot": "03_deployment_placing.png",
        "states": [{
            "name": "Placing a unit",
            "when": "After a unit is chosen to deploy and a placement session is live.",
            "hint_set": "HINTS_DEPLOY",
            "rp": RP_SELECTORS,
            "notes": ["LB/RB switch which unit is being deployed — but lock once any model is placed (undo to unlock).",
                      "D-pad ▲▼ moves the ▶ between the Model-type and Formation rows; ◀▶ changes the highlighted row's value.",
                      "X undoes the last placed model; B undoes the whole unit; Start confirms once every model is placed.",
                      "GAP: repositioning an already-placed model (mouse Shift+click) has no pad equivalent — undo and re-place."],
        }],
    },
    {
        "id": "redeploy-scout", "group": "Pre-battle", "title": "Redeployment & Scout",
        "blurb": "Two short optional phases after deployment.",
        "shot": None,
        "states": [
            {
                "name": "Redeployment",
                "when": "Immediately after deployment, if any unit can redeploy.",
                "custom": [("menu", "End Redeployment (the only affordance for any input device)")],
                "rp": ("na", "No redeploy UI on any device"),
                "notes": ["The pad can end the phase (no soft-lock), but performing an actual redeploy move has no UI for mouse OR pad — the ability is AI-only."],
            },
            {
                "name": "Scout moves",
                "when": "The Scout pre-battle phase.",
                "hint_set": "HINTS_BOARD",
                "rp": ("yes", "Confirm/Skip Scout buttons are panel-focusable (no stepper consumes the D-pad here)"),
                "notes": ["Select a scout unit with the bumpers, move with the LS cursor, End with Start.",
                          "Reserves reuse the deployment placement flow (HINTS_DEPLOY)."],
            },
        ],
    },
    # ---- battle phases ----
    {
        "id": "command", "group": "Battle phases", "title": "Command",
        "blurb": "CP, battle-shock, stratagems and faction abilities. Most human controls are HUD buttons reachable via panel focus, plus AcceptDialog prompts.",
        "shot": "04_command_board.png",
        "states": [{
            "name": "Command board",
            "when": "The default Command-phase state.",
            "hint_set": "HINTS_BOARD",
            "rp": RP_YES,
            "notes": ["Battle-shock roll, Insane Bravery, Waaagh!, Plant Banner, Oath target, New Orders live in the panels — reach them with the D-pad (Focus Panels).",
                      "Command Re-roll and the GDM 'pick on board' prompts are dialogs (A confirms).",
                      "GAP (not pad-specific): faction command choices — Combat Doctrine, Martial Mastery / Ka'tah, Issue Taktik, Da Kaptin, Psychic Veil, Unleash the Lions — are AI-only, no human path.",
                      "The Stratagem panel has no dedicated pad button; it is only reachable by focusing the bottom-bar button."],
        }],
    },
    {
        "id": "movement", "group": "Battle phases", "title": "Movement",
        "blurb": "The richest controller flow: a pop-up action menu, single- and group-model carry, per-model finishing, and a locked-move state.",
        "shot": "05_movement_selected_move.png",
        "states": [
            {
                "name": "Unit selected — mode still open",
                "when": "A unit is selected and its move mode hasn't been chosen yet.",
                "hint_set": "HINTS_MOVE",
                "rp": RP_NO_PREEMPT,
                "notes": ["Both A and D-pad open the Move Menu (Normal / Advance / Fall Back / Stay Still) — so the D-pad does NOT enter panel focus here.",
                          "Bumpers still cycle units; L3 picks which model will lead the move."],
            },
            {
                "name": "Move Menu open",
                "when": "After A / D-pad opens the action bar.",
                "hint_set": "HINTS_MENU", "shot": "06_movement_action_bar.png",
                "rp": ("dialog", "The action bar owns the pad — D-pad chooses, A confirms, B cancels"),
                "notes": ["Bumpers still cycle units (the menu follows the new unit); L3 previews the lead model.",
                          "Choosing Normal/Fall Back hands you the first model; Advance rolls first, then hands it over."],
            },
            {
                "name": "Carrying a model",
                "when": "A model is picked up and rides the cursor.",
                "hint_set": "HINTS_CARRY_MOVE", "shot": "07_movement_carry.png",
                "rp": RP_NO_STANDDOWN,
                "notes": ["LS moves the model, RS/hold = precision, LB/RB rotate.",
                          "D-pad ◀▶ switch which model you're carrying (same as L3 / the back paddles); D-pad ▲ grabs EVERY unmoved model as one group ('move all together').",
                          "A drops a waypoint (keeps the model — A again re-picks it); X finishes the model and hands over the next."],
            },
            {
                "name": "Group carry",
                "when": "After D-pad ▲ (grab all) — the whole squad rides the cursor.",
                "hint_set": "HINTS_CARRY_GROUP",
                "rp": RP_NO_STANDDOWN,
                "notes": ["A places every model that fits; leftovers are handed back individually. B cancels.",
                          "D-pad ▼ drops the group back to carrying just one model."],
            },
            {
                "name": "Mid-move, model dropped (staged)",
                "when": "A model was dropped with A and models remain unplaced.",
                "hint_set": "HINTS_MOVE_STAGED",
                "rp": RP_NO_STANDDOWN,
                "notes": ["A re-picks the dropped model, X finishes it, D-pad ◀▶ switch model / ▲ lifts the rest as a group, B undoes the last stage.",
                          "L3 keeps its single label 'Next Model' — the model-switcher never jumps onto X."],
            },
            {
                "name": "Move locked — all models placed",
                "when": "Every model is placed; waiting on confirmation.",
                "hint_set": "HINTS_MOVE_LOCKED",
                "rp": RP_NO_STANDDOWN,
                "notes": ["Start confirms the whole move; A picks a model back up to adjust; D-pad ◀▶ / L3 cycle models and ▲ re-grabs them all; B undoes the last stage.",
                          "Bumpers stay locked to this unit until the move is confirmed or fully undone."],
            },
        ],
    },
    {
        "id": "shooting", "group": "Battle phases", "title": "Shooting",
        "blurb": "Pick a shooter with the bumpers, then the armed shooter's targets and weapons become the D-pad sub-menu, with a gold reticle on the board.",
        "shot": "08_shooting_targets.png",
        "states": [
            {
                "name": "No shooter armed",
                "when": "Shooting phase before/after a shooter is selected.",
                "hint_set": "HINTS_BOARD",
                "rp": RP_YES,
                "notes": ["Bumpers cycle eligible shooters; A / board-click arms one."],
            },
            {
                "name": "Shooter armed — picking targets",
                "when": "A shooter is armed and has eligible targets.",
                "hint_set": "HINTS_TARGETS",
                "rp": RP_NO_PREEMPT,
                "notes": ["D-pad ◀▶ walks the target ring (gold reticle + camera follow); ▲▼ steps the weapon rows.",
                          "A assigns the highlighted target to the current weapon; X skips the unit; Start confirms.",
                          "GAP (pad-specific): while a shooter is armed the D-pad is captured by target/weapon stepping, so the HUD buttons (Grenade, Perform/Start Action, Burn Objective, Clear All, Undo Last) can't be reached by D-pad — B (deselect) is the only way out. Code-traced; not yet runtime-confirmed."],
            },
        ],
    },
    {
        "id": "charge", "group": "Battle phases", "title": "Charge",
        "blurb": "Stage-accurate hints: the Start button always names exactly what it will do (Declare / Roll / Confirm). Every D-pad direction lands in the charge flow.",
        "shot": None,
        "states": [
            {
                "name": "Selecting — picking targets",
                "when": "A charging unit is selected, no targets chosen yet.",
                "hint_set": "HINTS_CHARGE_SELECT",
                "rp": RP_NO_PREEMPT,
                "notes": ["D-pad steps the ELIGIBLE TARGETS rows; A toggles a row in/out (pad Click / Ctrl+Click).",
                          "X skips the charge; Start ends the phase when nothing is declared."],
            },
            {
                "name": "Targets chosen — ready to declare",
                "when": "At least one target toggled on.",
                "hint_set": "HINTS_CHARGE_READY",
                "rp": RP_NO_PREEMPT,
                "notes": ["Start = Declare Charge. D-pad keeps stepping targets; A toggles."],
            },
            {
                "name": "Declared — awaiting roll",
                "when": "Charge declared, dice not yet rolled.",
                "hint_set": "HINTS_CHARGE_ROLL",
                "rp": RP_NO_STANDDOWN,
                "notes": ["Start = Roll 2D6; X skips. A committed charge locks the bumpers to this unit."],
            },
            {
                "name": "Rolled — moving into engagement",
                "when": "Roll made, models heading into base contact.",
                "hint_set": "HINTS_CHARGE_MOVE",
                "rp": RP_NO_STANDDOWN,
                "notes": ["A grabs a model, L3 next model, X snap-to-contact, B undoes a model, Start confirms.",
                          "Carrying a charge model uses the plain carry set (HINTS_CARRY) — no per-model finish, no group grab."],
            },
            {
                "name": "Carrying a charge model",
                "when": "A charge model is in hand during the charge move.",
                "hint_set": "HINTS_CARRY",
                "rp": RP_NO_STANDDOWN,
                "notes": ["LS moves, LB/RB rotate, L3 swaps model, A drops, B cancels, Start confirms the charge."],
            },
        ],
    },
    {
        "id": "fight", "group": "Battle phases", "title": "Fight",
        "blurb": "Selection is button-based (alternating fighters, pile-in, consolidate), so the bumpers cycle the fight-panel BUTTONS rather than a unit list.",
        "shot": None,
        "states": [{
            "name": "Fight board",
            "when": "Pile-in, fighter selection and consolidate steps.",
            "hint_set": "HINTS_FIGHT",
            "rp": RP_FIGHT,
            "notes": ["Bumpers cycle the panel's action buttons; A commits the focused one; D-pad navigates the panel.",
                      "Pile-in / consolidate model moves use the LS cursor.",
                      "The attack-assignment dialog carries its own on-dialog hint row (▲▼ Weapon · ◀▶ Target · A Assign · ☰ Fight!).",
                      "GAP (not pad-specific): per-model weapon choice, splitting attacks across targets, and SELECT_MELEE_WEAPON have no human UI."],
        }],
    },
    {
        "id": "scoring", "group": "Battle phases", "title": "Scoring / End turn",
        "blurb": "Mostly automatic. Discards and 11e card actions are HUD buttons and dialogs.",
        "shot": None,
        "states": [{
            "name": "Scoring board",
            "when": "The end-of-turn scoring phase.",
            "hint_set": "HINTS_BOARD",
            "rp": RP_YES,
            "notes": ["Primary and secondary scoring resolve automatically.",
                      "Discard (+1 CP) is a panel button; the mission-discard and 11e card dialogs are pad-navigable.",
                      "Start = End Turn."],
        }],
    },
]


def chip(glyph):
    label = GLYPHS.get(glyph, glyph.upper())
    return f'<span class="chip"><span class="chip-g">{html.escape(label)}</span></span>'


def hint_rows(hint_set_name):
    rows = []
    for g, lab in HINTS[hint_set_name]:
        rows.append((g, lab))
    return rows


RP_BADGE = {
    "yes": ("rp-yes", "Yes"),
    "partial": ("rp-part", "Partial"),
    "list": ("rp-part", "Bumper-only"),
    "no": ("rp-no", "No"),
    "dialog": ("rp-dialog", "Dialog"),
    "na": ("rp-na", "N/A"),
}


def render_state(st, section_shot):
    parts = []
    # controls table
    if "hint_set" in st:
        rows = hint_rows(st["hint_set"])
        src = f'<code>PadRouter.{st["hint_set"]}</code>'
    else:
        rows = st["custom"]
        src = "native focus / phase handler"
    tr = "".join(
        f'<tr><td class="c-glyph">{chip(g)}</td><td class="c-act">{html.escape(lab)}</td></tr>'
        for g, lab in rows
    )
    rp_cls, rp_txt = RP_BADGE[st["rp"][0]]
    notes = "".join(f"<li>{html.escape(n)}</li>" for n in st.get("notes", []))
    shot = st.get("shot", section_shot)
    fig = ""
    if shot:
        fig = (f'<figure class="shot"><img loading="lazy" src="__IMG__{shot}" '
               f'alt="{html.escape(st["name"])}"><figcaption>Live capture — hint bar shows '
               f'this state</figcaption></figure>')
    else:
        fig = ('<div class="shot noshot"><span>No live screenshot</span>'
               '<p>Controls documented from the code constants; this state needs a contrived '
               'tactical setup to stage on screen.</p></div>')
    return f'''
    <article class="state">
      <div class="state-head">
        <h4>{html.escape(st["name"])}</h4>
        <span class="rp-badge {rp_cls}" title="Can you drive the right-hand panel with the pad here?">Right panel: {rp_txt}</span>
      </div>
      <p class="when"><strong>When:</strong> {html.escape(st["when"])} <span class="src">Source: {src}</span></p>
      <div class="state-body">
        <table class="controls">
          <thead><tr><th>Button</th><th>Does</th></tr></thead>
          <tbody>{tr}</tbody>
        </table>
        {fig}
      </div>
      <p class="rp-note"><strong>Right panel on pad:</strong> {html.escape(st["rp"][1])}</p>
      {'<ul class="notes">'+notes+'</ul>' if notes else ''}
    </article>'''


def render_section(sec):
    states = "".join(render_state(s, sec.get("shot")) for s in sec["states"])
    return f'''
  <section id="{sec['id']}" class="doc-section">
    <div class="sec-eyebrow">{html.escape(sec['group'])}</div>
    <h3>{html.escape(sec['title'])}</h3>
    <p class="sec-blurb">{html.escape(sec['blurb'])}</p>
    {states}
  </section>'''


# ---- coverage summary rows ----
COVERAGE = [
    ("Menus & shell", "Main menu, pause, settings, save/load", "full", "Native focus nav throughout"),
    ("Datasheet", "Y opens/closes the stat card", "partial", "No pad-B close; no scroll"),
    ("Deployment", "Place, rotate, undo, formation/type", "full", "Reposition-placed-model is mouse-only"),
    ("Redeployment", "End phase only", "gap", "Redeploy move has no UI (AI-only)"),
    ("Command", "Battle-shock, stratagems, abilities", "partial", "Faction choices AI-only; stratagem panel awkward"),
    ("Movement", "Menu, carry, group carry, finish", "full", "Deepest controller flow — fully mapped"),
    ("Shooting", "Cycle shooter, target ring, weapons", "partial", "HUD action buttons unreachable while armed"),
    ("Charge", "Declare, roll, move into engagement", "full", "11e declare-then-target path is UI-less (all inputs)"),
    ("Fight", "Bumper-cycle fight buttons, assign", "partial", "Per-model weapon / split attacks have no UI"),
    ("Scoring", "Auto + discard buttons", "full", "Mostly automatic"),
]
COV_BADGE = {"full": ("cov-full", "Full"), "partial": ("cov-part", "Partial"), "gap": ("cov-gap", "Gap")}

# ---- pad-specific gaps (agent B highlights) ----
GAPS = [
    ("critical", "Shooting HUD buttons unreachable while a shooter is armed",
     "Grenade, Perform/Start Secondary Action, Burn Objective, Clear All, Undo Last — the D-pad is captured by target/weapon stepping so panel-focus entry never fires. Only B (deselect) escapes, losing the shooting context.",
     "ShootingController.gd:3948-3966 · PadRouter.gd:419-444 — code-traced, not yet runtime-confirmed"),
    ("warning", "Stratagem panel has no dedicated pad affordance",
     "Opened only by the S key or the bottom-bar button; no hint-bar chip. Technically reachable by focusing the button, but undiscoverable and pre-empted by phase steppers in most phases.",
     "Main.gd:5847-5849 · StratagemPanel.gd"),
    ("warning", "Deployment: can't reposition an already-placed model",
     "The mouse Shift+click pick-up/drop has no pad equivalent during placement — X and B only undo. A pad player must undo and re-place.",
     "DeploymentController.gd:119-146"),
    ("warning", "Datasheet: pad-B doesn't close it, and it can't scroll",
     "Only Y toggles it closed on pad (Esc on keyboard). A datasheet taller than the fixed card is clipped with no scroll (pad or mouse).",
     "DatasheetModal.gd:18-19 · Main.gd:5829-5832"),
    ("warning", "Can't bind actions to gamepad buttons",
     "The keybinding remap UI only captures keyboard keys; the pad scheme is fixed and non-rebindable.",
     "SettingsMenu.gd:831"),
    ("info", "No-human-path items (pad simply also can't)",
     "Command faction choices; Movement Da Jump / Deff From Above / Grot Oiler / Mekaniak / Sawbonez / Quicksilver / Surge; Shooting Ritual/Terraform, Ammo Runt, Pulsa Rokkit, Shooty Power Trip, Swift, Wazblasta; Fight per-model weapon / split attacks; Charge 11e declare-then-target; Deployment Castellan's Mark / Place-in-Reserves; Redeployment moves. These are AI-only for every input device — see CONTROLLER_AUDIT_2026-07.md.",
     "CONTROLLER_AUDIT_2026-07.md"),
]

GAP_BADGE = {"critical": ("g-crit", "Pad blocker"), "warning": ("g-warn", "Pad gap"),
             "info": ("g-info", "No human path")}


def nav_html():
    groups = {}
    for s in SECTIONS:
        groups.setdefault(s["group"], []).append(s)
    out = []
    for g, secs in groups.items():
        links = "".join(f'<a href="#{s["id"]}">{html.escape(s["title"])}</a>' for s in secs)
        out.append(f'<div class="nav-group"><span class="nav-h">{html.escape(g)}</span>{links}</div>')
    return "".join(out)


def coverage_html():
    rows = ""
    for area, what, lvl, note in COVERAGE:
        cls, txt = COV_BADGE[lvl]
        rows += (f'<tr><td class="cov-area">{html.escape(area)}</td>'
                 f'<td>{html.escape(what)}</td>'
                 f'<td><span class="cov {cls}">{txt}</span></td>'
                 f'<td class="cov-note">{html.escape(note)}</td></tr>')
    return rows


def gaps_html():
    out = ""
    for sev, title, body, ev in GAPS:
        cls, txt = GAP_BADGE[sev]
        out += (f'<div class="gap {cls}"><div class="gap-top"><span class="gap-badge">{txt}</span>'
                f'<h4>{html.escape(title)}</h4></div>'
                f'<p>{html.escape(body)}</p>'
                f'<p class="gap-ev">{html.escape(ev)}</p></div>')
    return out


def physical_html():
    out = ""
    for g, name, meaning in PHYSICAL:
        out += (f'<div class="prow"><div class="pk">{chip(g)}<span class="pk-n">{html.escape(name)}</span></div>'
                f'<div class="pm">{html.escape(meaning)}</div></div>')
    return out


def legend_html():
    order = ["a","b","x","y","lb","rb","lt","rt","ls","rs","l3","r3","dpad","menu","view","l4"]
    out = ""
    for g in order:
        out += f'<div class="leg">{chip(g)}<span>{html.escape(GLYPHS.get(g,g.upper()))}</span></div>'
    return out


PAGE = '''<title>Controller Controls Map — WH40k Battle Simulator</title>
<style>
:root{{
  --bg:#f4efe4; --panel:#fffdf7; --panel-2:#efe7d6; --ink:#241f17; --ink-soft:#5b5343;
  --line:#d9ccb3; --accent:#b9702a; --accent-soft:#c98a44; --gold:#9a7b2e;
  --chip-bg:#241f17; --chip-ink:#f2e4c2; --chip-line:#000;
  --good:#4f7d46; --warn:#a9762a; --crit:#b0472f; --info:#5b6b86;
  --shadow:0 1px 2px rgba(60,45,20,.09),0 6px 18px rgba(60,45,20,.07);
  --serif:"Iowan Old Style","Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  --mono:ui-monospace,"SF Mono","Cascadia Mono",Menlo,Consolas,monospace;
}}
@media (prefers-color-scheme:dark){{:root{{
  --bg:#14110c; --panel:#1d1810; --panel-2:#241d13; --ink:#ece3d0; --ink-soft:#a99e88;
  --line:#3a3021; --accent:#d98a3a; --accent-soft:#e0a05a; --gold:#d8c078;
  --chip-bg:#0c0a06; --chip-ink:#e8d9b2; --chip-line:#4a3d26;
  --good:#6faf63; --warn:#d6a445; --crit:#d06a54; --info:#8fa0bf;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 26px rgba(0,0,0,.35);
}}}}
:root[data-theme="light"]{{
  --bg:#f4efe4; --panel:#fffdf7; --panel-2:#efe7d6; --ink:#241f17; --ink-soft:#5b5343;
  --line:#d9ccb3; --accent:#b9702a; --accent-soft:#c98a44; --gold:#9a7b2e;
  --chip-bg:#241f17; --chip-ink:#f2e4c2; --chip-line:#000;
  --good:#4f7d46; --warn:#a9762a; --crit:#b0472f; --info:#5b6b86;
}}
:root[data-theme="dark"]{{
  --bg:#14110c; --panel:#1d1810; --panel-2:#241d13; --ink:#ece3d0; --ink-soft:#a99e88;
  --line:#3a3021; --accent:#d98a3a; --accent-soft:#e0a05a; --gold:#d8c078;
  --chip-bg:#0c0a06; --chip-ink:#e8d9b2; --chip-line:#4a3d26;
  --good:#6faf63; --warn:#d6a445; --crit:#d06a54; --info:#8fa0bf;
}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
  line-height:1.55;font-size:16px;-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1180px;margin:0 auto;padding:0 24px}}
a{{color:var(--accent);text-decoration:none}}
a:hover{{text-decoration:underline}}
:focus-visible{{outline:2px solid var(--accent);outline-offset:2px;border-radius:3px}}

header.hero{{border-bottom:1px solid var(--line);background:
  linear-gradient(180deg,var(--panel-2),transparent);padding:56px 0 30px}}
.eyebrow{{font-family:var(--mono);font-size:12px;letter-spacing:.22em;text-transform:uppercase;
  color:var(--accent);margin:0 0 12px}}
h1{{font-family:var(--serif);font-weight:600;font-size:clamp(30px,5vw,46px);line-height:1.05;
  margin:0 0 14px;text-wrap:balance;letter-spacing:-.01em}}
.lede{{font-size:18px;color:var(--ink-soft);max-width:66ch;margin:0 0 8px}}
.meta{{font-family:var(--mono);font-size:12.5px;color:var(--ink-soft);margin-top:16px;
  display:flex;gap:18px;flex-wrap:wrap}}
.meta b{{color:var(--ink)}}

.layout{{display:grid;grid-template-columns:230px 1fr;gap:40px;align-items:start;
  padding:36px 0 80px}}
nav.toc{{position:sticky;top:18px;font-size:14px;max-height:calc(100vh - 36px);overflow:auto}}
.nav-group{{margin-bottom:16px;display:flex;flex-direction:column;gap:3px}}
.nav-h{{font-family:var(--mono);font-size:11px;letter-spacing:.16em;text-transform:uppercase;
  color:var(--ink-soft);margin-bottom:4px}}
nav.toc a{{color:var(--ink-soft);padding:2px 0}}
nav.toc a:hover{{color:var(--accent);text-decoration:none}}
main{{min-width:0}}

.card{{background:var(--panel);border:1px solid var(--line);border-radius:12px;
  padding:24px 26px;box-shadow:var(--shadow);margin-bottom:34px}}
.card h2{{font-family:var(--serif);font-size:24px;margin:0 0 4px;font-weight:600}}
.card .sub{{color:var(--ink-soft);margin:0 0 20px;font-size:15px}}

/* physical map */
.pgrid{{display:grid;grid-template-columns:1fr 1fr;gap:4px 30px}}
@media(max-width:720px){{.pgrid{{grid-template-columns:1fr}}}}
.prow{{display:grid;grid-template-columns:150px 1fr;gap:12px;padding:7px 0;
  border-bottom:1px solid var(--line);align-items:start}}
.pk{{display:flex;align-items:center;gap:8px}}
.pk-n{{font-size:13.5px;font-weight:600}}
.pm{{font-size:13.5px;color:var(--ink-soft)}}
.legend{{display:flex;flex-wrap:wrap;gap:10px 16px;margin-top:6px}}
.leg{{display:flex;align-items:center;gap:6px;font-size:12.5px;color:var(--ink-soft);font-family:var(--mono)}}

/* chips — mirrors the in-game GlyphDB hint chip */
.chip{{display:inline-flex;align-items:center}}
.chip-g{{font-family:var(--mono);font-size:12px;font-weight:700;color:var(--chip-ink);
  background:var(--chip-bg);border:1px solid var(--chip-line);border-radius:4px;
  padding:1px 7px;min-width:22px;text-align:center;line-height:1.5}}

/* coverage table */
table{{border-collapse:collapse;width:100%;font-size:14px}}
.cov-table th,.cov-table td{{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}}
.cov-table th{{font-family:var(--mono);font-size:11px;letter-spacing:.12em;text-transform:uppercase;
  color:var(--ink-soft);font-weight:600}}
.cov-area{{font-weight:600;white-space:nowrap}}
.cov-note{{color:var(--ink-soft);font-size:13px}}
.cov{{display:inline-block;font-family:var(--mono);font-size:11px;font-weight:700;letter-spacing:.04em;
  padding:2px 9px;border-radius:20px;white-space:nowrap}}
.cov-full{{color:var(--good);background:color-mix(in srgb,var(--good) 16%,transparent)}}
.cov-part{{color:var(--warn);background:color-mix(in srgb,var(--warn) 18%,transparent)}}
.cov-gap{{color:var(--crit);background:color-mix(in srgb,var(--crit) 18%,transparent)}}

/* sections */
.doc-section{{padding:14px 0 6px;border-top:1px solid var(--line);margin-top:26px;scroll-margin-top:14px}}
.sec-eyebrow{{font-family:var(--mono);font-size:11px;letter-spacing:.18em;text-transform:uppercase;
  color:var(--accent);margin-bottom:6px}}
.doc-section h3{{font-family:var(--serif);font-size:27px;font-weight:600;margin:0 0 8px}}
.sec-blurb{{color:var(--ink-soft);max-width:70ch;margin:0 0 18px}}

.state{{background:var(--panel);border:1px solid var(--line);border-radius:11px;
  padding:18px 20px;margin-bottom:16px;box-shadow:var(--shadow)}}
.state-head{{display:flex;justify-content:space-between;align-items:center;gap:14px;flex-wrap:wrap}}
.state-head h4{{font-family:var(--serif);font-size:19px;margin:0;font-weight:600}}
.when{{font-size:13px;color:var(--ink-soft);margin:4px 0 14px}}
.when .src{{font-family:var(--mono);font-size:11.5px;opacity:.8;margin-left:8px}}
.when .src code{{background:var(--panel-2);padding:1px 5px;border-radius:4px}}
.state-body{{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.05fr);gap:20px;align-items:start}}
@media(max-width:760px){{.state-body{{grid-template-columns:1fr}}}}
table.controls{{background:var(--panel-2);border-radius:8px;overflow:hidden}}
table.controls th{{font-family:var(--mono);font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;
  color:var(--ink-soft);text-align:left;padding:8px 12px;border-bottom:1px solid var(--line)}}
table.controls td{{padding:7px 12px;border-bottom:1px solid var(--line);font-size:13.5px;vertical-align:top}}
table.controls tr:last-child td{{border-bottom:none}}
.c-glyph{{width:52px;white-space:nowrap}}
.c-act{{color:var(--ink)}}

figure.shot{{margin:0}}
figure.shot img{{width:100%;height:auto;border:1px solid var(--line);border-radius:8px;display:block;
  background:var(--panel-2)}}
figure.shot figcaption{{font-family:var(--mono);font-size:11px;color:var(--ink-soft);margin-top:6px;text-align:center}}
.noshot{{border:1px dashed var(--line);border-radius:8px;padding:20px;text-align:center;
  color:var(--ink-soft);background:var(--panel-2);display:flex;flex-direction:column;gap:6px;justify-content:center}}
.noshot span{{font-family:var(--mono);font-size:12px;letter-spacing:.08em;text-transform:uppercase}}
.noshot p{{font-size:12.5px;margin:0}}

.rp-badge{{font-family:var(--mono);font-size:11px;font-weight:700;padding:3px 10px;border-radius:20px;white-space:nowrap}}
.rp-yes{{color:var(--good);background:color-mix(in srgb,var(--good) 16%,transparent)}}
.rp-part{{color:var(--warn);background:color-mix(in srgb,var(--warn) 18%,transparent)}}
.rp-no{{color:var(--crit);background:color-mix(in srgb,var(--crit) 16%,transparent)}}
.rp-dialog{{color:var(--info);background:color-mix(in srgb,var(--info) 18%,transparent)}}
.rp-na{{color:var(--ink-soft);background:color-mix(in srgb,var(--ink-soft) 15%,transparent)}}
.rp-note{{font-size:13px;color:var(--ink-soft);margin:14px 0 0;border-left:2px solid var(--accent);padding-left:12px}}
.notes{{font-size:13px;color:var(--ink-soft);margin:12px 0 0;padding-left:18px}}
.notes li{{margin:3px 0}}

/* gaps */
.gap{{background:var(--panel);border:1px solid var(--line);border-left-width:4px;border-radius:8px;
  padding:14px 18px;margin-bottom:12px}}
.gap-top{{display:flex;align-items:center;gap:12px;flex-wrap:wrap}}
.gap-top h4{{font-family:var(--serif);font-size:17px;margin:0;font-weight:600}}
.gap-badge{{font-family:var(--mono);font-size:10.5px;font-weight:700;letter-spacing:.06em;
  padding:2px 8px;border-radius:5px;text-transform:uppercase;white-space:nowrap}}
.gap p{{font-size:13.5px;color:var(--ink-soft);margin:8px 0 0}}
.gap-ev{{font-family:var(--mono);font-size:11.5px;opacity:.8;margin-top:8px!important}}
.g-crit{{border-left-color:var(--crit)}} .g-crit .gap-badge{{color:#fff;background:var(--crit)}}
.g-warn{{border-left-color:var(--warn)}} .g-warn .gap-badge{{color:#231a08;background:var(--warn)}}
.g-info{{border-left-color:var(--info)}} .g-info .gap-badge{{color:#fff;background:var(--info)}}

footer{{border-top:1px solid var(--line);padding:26px 0 60px;color:var(--ink-soft);font-size:13px}}
footer code{{font-family:var(--mono);background:var(--panel-2);padding:1px 6px;border-radius:4px}}
.callout{{background:var(--panel-2);border:1px solid var(--line);border-radius:10px;padding:16px 20px;margin:18px 0}}
.callout h4{{margin:0 0 6px;font-family:var(--serif);font-size:17px}}
.callout p{{margin:6px 0;font-size:13.5px;color:var(--ink-soft)}}
@media(max-width:900px){{.layout{{grid-template-columns:1fr}} nav.toc{{position:static;max-height:none}}}}
@media(prefers-reduced-motion:reduce){{*{{scroll-behavior:auto}}}}
</style>

<header class="hero"><div class="wrap">
  <p class="eyebrow">Source of truth · Gamepad</p>
  <h1>Controller Controls Map</h1>
  <p class="lede">Every point where a player gives input on a game controller, and exactly what each
  button does at that instant — across menus, pre-battle, and all seven battle phases of the
  Warhammer 40,000 Battle Simulator.</p>
  <p class="lede">The button tables are generated straight from <code style="font-family:var(--mono);font-size:.85em">PadRouter</code>'s
  live hint-set constants, so a control listed here is a control the code actually renders. A drift-check
  test fails CI if the code changes without this document being updated — so these controls only change
  when we intend them to.</p>
  <div class="meta">
    <span><b>Layout:</b> Xbox / Steam Deck (SDL)</span>
    <span><b>Generated:</b> {DATE}</span>
    <span><b>Scope:</b> controller-first (mouse/keyboard-only steps flagged as gaps)</span>
  </div>
</div></header>

<div class="wrap"><div class="layout">
  <nav class="toc" aria-label="Contents">
    <div class="nav-group"><span class="nav-h">Start here</span>
      <a href="#how">How to read this</a><a href="#layout">Controller layout</a>
      <a href="#coverage">Coverage summary</a><a href="#gaps">Controller gaps</a>
    </div>
    {NAV}
  </nav>

  <main>
    <section id="how" class="card">
      <h2>How to read this</h2>
      <p class="sub">The controls are contextual: the same button means different things in different states.</p>
      <ul class="notes" style="font-size:14px">
        <li><strong>The pad only drives the game while it is the active device.</strong> Any joypad press claims control (the on-screen hint bar appears); any mouse move or key press hands control back to keyboard &amp; mouse.</li>
        <li><strong>LB / RB are the only unit-switcher.</strong> They cycle the acting unit in every phase. Unit lists on the right are deliberately NOT walkable with the D-pad or stick — cycling is the bumpers' job alone.</li>
        <li><strong>The D-pad is context-dependent.</strong> With nothing selected it enters panel focus; with a phase sub-menu open (targets, weapons, move mode, deploy rows) it drives that instead; and while you are moving a unit it switches models (◀▶), grabs all (▲), or drops back to one (▼).</li>
        <li><strong>Each state below lists its buttons, whether the right-hand panel can be driven on the pad, and any gaps.</strong> The "Right panel on pad?" badge is the answer to "can I control the menu on the right here?"</li>
      </ul>
    </section>

    <section id="layout" class="card">
      <h2>Controller layout — always-on meanings</h2>
      <p class="sub">These hold across the game unless a state below overrides them. Glyphs match the in-game hint bar.</p>
      <div class="pgrid">{PHYSICAL}</div>
      <div class="legend">{LEGEND}</div>
    </section>

    <section id="coverage" class="card">
      <h2>Coverage at a glance</h2>
      <p class="sub">How completely each area is playable on a controller today.</p>
      <div style="overflow-x:auto"><table class="cov-table">
        <thead><tr><th>Area</th><th>What the pad does</th><th>Coverage</th><th>Caveat</th></tr></thead>
        <tbody>{COVERAGE}</tbody>
      </table></div>
    </section>

    {SECTIONS}

    <section id="gaps" class="card">
      <h2>Controller coverage gaps</h2>
      <p class="sub">Where a controller can't (yet) do something. <span style="color:var(--crit)">Pad blocker</span> = mouse/keyboard can, pad can't. <span style="color:var(--info)">No human path</span> = AI-only for every input device.</p>
      {GAPS}
    </section>

    <footer>
      <p><strong>Keeping this a source of truth.</strong> The per-state button tables are generated from
      <code>PadRouter.HINTS_*</code> (dumped live from the running game). The companion file
      <code>controller_hint_sets.json</code> mirrors those constants and is asserted equal by
      <code>tests/test_controller_controls_doc_sync.gd</code> — if a hint set changes in code, CI fails until
      this document is regenerated. To change the controls deliberately: edit the code, re-dump, regenerate.</p>
      <p>Narrative, screenshots and gap analysis are hand-authored and safe to edit directly. Screenshots are
      live captures from the running game via the <code>addons/godot_mcp</code> bridge. Related:
      <code>CONTROLLER_AUDIT_2026-07.md</code> (phase↔action drift &amp; AI-only abilities).</p>
    </footer>
  </main>
</div></div>

<script>
// theme toggle parity: honor a stamped data-theme over the media query (handled in CSS);
// nothing else needed — the page is static.
</script>'''


def build(img_prefix, inline_images):
    body = PAGE.format(
        DATE="2026-07-22",
        NAV=nav_html(),
        PHYSICAL=physical_html(),
        LEGEND=legend_html(),
        COVERAGE=coverage_html(),
        SECTIONS="".join(render_section(s) for s in SECTIONS),
        GAPS=gaps_html(),
    )
    if inline_images:
        # replace __IMG__<file> with data URIs
        import re
        def repl(m):
            fn = m.group(1)
            p = os.path.join(SHOTS, fn)
            with open(p, "rb") as fh:
                b64 = base64.b64encode(fh.read()).decode()
            return f"data:image/png;base64,{b64}"
        body = re.sub(r'__IMG__([\w./-]+\.png)', repl, body)
    else:
        body = body.replace("__IMG__", img_prefix)
    return body


os.makedirs(DOCS, exist_ok=True)

# machine-readable mirror of the code constants (checked by the drift test)
with open(os.path.join(DOCS, "controller_hint_sets.json"), "w") as f:
    json.dump({k: HINTS[k] for k in sorted(HINTS)}, f, indent=2, ensure_ascii=False)

# repo HTML — relative image refs
repo_html = build("controller_shots/", inline_images=False)
with open(os.path.join(DOCS, "CONTROLLER_CONTROLS_MAP.html"), "w") as f:
    f.write(repo_html)

print("wrote:")
print(" ", os.path.join(DOCS, "controller_hint_sets.json"))
print(" ", os.path.join(DOCS, "CONTROLLER_CONTROLS_MAP.html"), os.path.getsize(os.path.join(DOCS,'CONTROLLER_CONTROLS_MAP.html')), "bytes")

# Optional self-contained copy (images inlined as data URIs) for publishing as a
# shareable Artifact. Large (~18 MB) — NOT committed. Set SELFCONTAINED_OUT=<path>.
sc_out = os.environ.get("SELFCONTAINED_OUT")
if sc_out:
    with open(sc_out, "w") as f:
        f.write(build("", inline_images=True))
    print(" ", sc_out, os.path.getsize(sc_out), "bytes (self-contained, not committed)")
