# M3 sensitivity screen — 2026-08-07

Fixture `mirror_custodes_postdeploy`, Hard, +/-30% one-at-a-time, 4 paired
side-swapped seeds per direction. 336 games, 208 minutes at 3 lanes.

`E` is the paired effect in VP/game (candidate minus baseline). The screen ranks
INFLUENCE; the sign is one noisy sample and is a hint, not a recommendation.

| parameter | default | \|E\| max | up | down |
|---|---|---|---|---|
| `MOVE_REACHABLE_BONUS` | 3 | 9.25 | +1.88 (se 1.875) | -9.25 (se 4.385) |
| `WEIGHT_OC_EFFICIENCY` | 2 | 5.88 | +2.00 (se 1.837) | +5.88 (se 5.23) |
| `WEIGHT_UNCONTROLLED_OBJ` | 10 | 5.38 | -0.12 (se 0.125) | -5.38 (se 3.771) |
| `MOVE_TURNS_AWAY_PENALTY` | 2 | 3.62 | +3.62 (se 2.657) | +1.12 (se 2.145) |
| `MOVE_UNREACHABLE_EARLY_PENALTY` | 2 | 2.75 | -2.75 (se 2.75) | +0.00 (se 0.0) |
| `WEIGHT_VP_PER_POINT` | 1.2 | 1.25 | -0.62 (se 0.625) | -1.25 (se 1.25) |
| `STRATEGY_LATE_OBJECTIVE` | 1.6 | 0.88 | +0.62 (se 0.625) | +0.88 (se 1.231) |
| `STRATEGY_EARLY_OBJECTIVE` | 0.95 | 0.75 | +0.75 (se 0.75) | +0.25 (se 4.702) |
| `MOVE_STAY_BONUS_LATE` *(no decision changed)* | 7 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `MOVE_STAY_BONUS_SCORING` *(no decision changed)* | 6 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `MOVE_HORDE_BONUS_LARGE` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `WEIGHT_CONTESTED_OBJ` *(no decision changed)* | 8 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `WEIGHT_ALREADY_HELD_OBJ` *(no decision changed)* | -3 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `CHARGE_MELEE_DAMAGE_WEIGHT` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `CHARGE_BELOW_HALF_BONUS` *(no decision changed)* | 3 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `CHARGE_TIE_UP_SHOOTER_BONUS` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `FIGHT_MELEE_DAMAGE_WEIGHT` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `FIGHT_CAN_WIPE_BONUS` *(no decision changed)* | 6 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `FIGHT_CHARACTER_BONUS` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `OVERKILL_TOLERANCE` *(no decision changed)* | 1.15 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |
| `KILL_BONUS_MULTIPLIER` *(no decision changed)* | 2 | 0.00 | +0.00 (se 0.0) | +0.00 (se 0.0) |

## What it says

**Five parameters move the margin by >= 2 VP**, so the design document's kill
criterion selects CEM over coordinate descent.

**Three of the top five were bare hardcoded literals this morning.**
`MOVE_REACHABLE_BONUS`, `MOVE_TURNS_AWAY_PENALTY` and
`MOVE_UNREACHABLE_EARLY_PENALTY` had no `get_param` call, so no profile, rule or
optimiser could reach them at any games budget. The single highest-influence
parameter in the whole screen (|E| = 9.25) was invisible to search until it was
promoted. That is the expressiveness audit's F-01/F-02 argument, measured: the
search space was not merely small, it was missing its most influential member.

**`MOVE_TURNS_AWAY_PENALTY` up scores +3.63 VP (se 2.66)** — the direction F-01
predicted from behaviour alone. 49.6% of movement decisions chose a destination
both farther and lower-scoring than an available one, and the reachability
penalty is the mechanism. Suggestive, not established: se 2.66 on 4 pairs.

**Thirteen of twenty-one changed no decision at all at +/-30%.** Every charge,
fight and shooting coefficient in the set is in that group. This does NOT prove
they are unread — a parameter can be read and still never move an argmax,
because it scales a dominated term or the unit had only one option. But it does
mean the *effective* tuning surface on this fixture is far smaller than the 126
parameters the manifest lists.

## Caveats

- One fixture. The Custodes mirror is 9 elite units a side; the charge and fight
  coefficients may well matter on the 16-unit Ork horde.
- 4 pairs gives se of roughly 2-5 VP. This ranks; it does not conclude.
- Common random numbers help less than hoped: an identical candidate reproduces
  exactly, but any candidate that flips one decision reshuffles every subsequent
  dice draw, so the paired spread stays wide.
