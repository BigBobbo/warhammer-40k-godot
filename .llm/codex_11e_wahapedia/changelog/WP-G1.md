# WP-G1 — Redeployment step a human can use (player-facing bullets)

- The Redeployment step now has controls. If your army has a redeploy rule (Castellan's Mark, Kaptin's Hat, Razgit's Magik Map, or the Space Marine / Space Wolves ones such as Cyber-familiar, Hunter's Guile, Chariots of the Storm and Strategium Command), a REDEPLOYMENT panel on the right lists the units you can redeploy, how many uses you have left (up to three), and gives each unit three buttons:
  - Redeploy: pick the unit up and set it up again with the usual deployment ghosts. Each model must be wholly within your deployment zone. Infiltrators instead go more than 8" from the enemy zone and enemy models. Models cannot overlap other models or walls, and the unit must be in coherency. Then press Confirm Redeploy. Undo, Cancel and the Single/Spread/Tight placement buttons work as in deployment.
  - Reserves: put the unit into Strategic Reserves, however many units are already there.
  - Keep: leave the unit where it is.
- A unit with a leader attached is redeployed as one unit. The leader is picked up with it and placed with it (the model-type picker sits in the panel), or goes into reserves with it.
- Done Redeploying ends your redeployments. Players take turns, starting with the Attacker. When you finish, the step passes to your opponent if they have redeployments to make. Otherwise the game moves on to the first-turn roll-off. When nobody has anything to redeploy, the step is skipped as before.
- The step works for either seat, against the AI or in hot-seat. The AI resolves its own redeployments (it keeps its units in place) and never holds the game up.
- The game log records each redeployment ("CASTELLAN'S MARK: Custodian Guard redeployed"), each unit put into reserves, and each unit kept.
- Fix: a unit sent to Strategic Reserves from the Redeployment step now arrives later like any other reserve unit. It was being marked "undeployed", so it could never arrive.
- Fix: the Redeployment step now starts with the Attacker, as the rules say. It used to always start with Player 1.
