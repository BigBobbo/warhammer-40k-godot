# AI Plans — a player's guide

An **AI plan** is a battle plan you write for the computer: where to put each
unit, what to hold back in Reserves, who rides with whom, and what each unit is
*for* once the shooting starts. Hand the computer a plan and it will follow it
instead of working the deployment out from scratch.

You never edit a file. Everything below happens in the game.

There are four things you can do, and they build on each other:

| I want to… | Use |
|---|---|
| Lay out a deployment and save it | **Plan Editor** |
| Say what each unit is for | **INTENTS** panel, inside the Plan Editor |
| Give a plan to the computer for a game | **AI Plan** picker in the game setup |
| Find out whether a plan is any good | **Battle Simulator** |
| See everything you've written | **AI Plans** screen |

---

## 1. Write a plan — the Plan Editor

**Main menu → Plan Editor.**

Next to the button there is a **Plan Editor Zone** picker. Choose the
deployment zone you are writing the plan for. (It needs its own control because
in a real game the zone is decided by the mission and the terrain, and a plan
has to be written for one specific zone.)

Pick the army in **Player 1 Army**, then press Plan Editor. You get a solo
sandbox:

* only your army is on the board — there is no opponent to wait for;
* you go through the normal pre-battle declarations, so you can put units in
  Reserves, load them into transports, and attach characters to units;
* then you deploy exactly as you would in a game.

**The session does not end when you finish deploying.** It stays open with the
board in front of you, which is the whole point — you are looking at the
finished deployment and deciding whether you like it.

Two things to know:

* **You cannot pick a unit back up once it is placed.** If you want to change
  it, exit and start again. (Exit is on the banner at the top.)
* The board you see is the one the computer will reproduce, model for model.

When you are happy: **Save as Plan** on the banner. If the plan has a problem —
too many points in Reserves, say — the dialog stays open and tells you what is
wrong rather than saving something broken.

---

## 2. Say what each unit is for — INTENTS

Once everything is deployed, an **INTENTS** panel appears. Pick a unit, then
pick one of five jobs:

| Job | What the computer does with it |
|---|---|
| **Hold objective** | Sticks to the objective you click. Click the objective marker itself to bind it |
| **Push centre** | Heads for the middle of the board and contests it |
| **Screen** | Hangs back as a body-block instead of running at objectives |
| **Hunt characters** | Prefers enemy characters when picking targets |
| **Reserve until round N** | Starts off the board and arrives on that round |

The unit gets a badge on the board so you can see the whole plan at a glance.
"Reserve until" overrides wherever you put the unit in the sandbox — you are
telling it to start off the board, so that is what gets saved.

Intents are saved with the plan; they are not a separate thing to manage.

---

## 3. Give a plan to the computer

In the game setup, any seat set to **AI** gets an **AI Plan** picker under it.

* The list only offers plans that fit — right army, right deployment zone.
* A plan that nearly fits is still listed, with the reason in brackets, so you
  can see it exists.
* **None (no plan)** makes that seat play the way it always did.

Both seats can have plans, and they can be different plans. During the game the
AI summary panel names the plan the computer is following.

Two plans ship with the game, both for **Recon Stomps**: one for **Crucible of
Battle** and one for **Hammer and Anvil**. They are marked *"claude-draft —
owner review wanted"*, which means exactly what it says: they are a sensible
starting point, not a tested list.

---

## 4. Find out whether a plan is any good — Battle Simulator

**Main menu → Battle Simulator.**

Pick the two armies, a plan for each side (or none), the zone, the terrain and
how many games to play, then press **Run**. The games play out on screen one
after another while the results fill in: who won, the score, how many battle
rounds, and how many units each side deployed from its plan.

* The time estimate appears **after the first game finishes** and is based on
  how long that game actually took — a full 2000-point Ork army takes minutes
  per game, a small list takes seconds, so guessing up front would be useless.
* **Cancel** stops after the game in progress and keeps the results so far.
* Every simulated game is recorded, so you can replay any of them from **Watch
  Replays**.

A word on reading the results: a handful of games cannot tell you whether a
plan is worth 3 points a game. Battles swing by 20 points on the dice alone. If
you want a real answer you need a lot of games — and the honest reason to use a
plan is that the computer does something you can *predict*, not that it wins
more.

---

## 5. See what you have — the AI Plans screen

**Main menu → AI Plans** lists every plan: its army, zone, terrain, where it
came from, and whether it is still valid.

* Plans you wrote can be **renamed** or **deleted** (deleting asks first).
* Plans that ship with the game are read-only — you can use them and look at
  them, but not change them.

---

## Known rough edges

Honest list, so you are not surprised:

* **A plan is written for one zone.** Used on a different one it will not
  match, and the computer falls back to its own judgement.
* **Terrain moves.** A plan is laid out against one terrain layout; on a
  different one some units get nudged, and any that cannot be placed fall back
  to the computer's own choice for that unit only. The rest of the plan still
  applies.
