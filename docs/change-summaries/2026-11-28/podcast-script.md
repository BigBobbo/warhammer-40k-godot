**Alex:** Welcome to the Combat Calc change log. I am Alex.

**Sam:** And I am Sam. Today we look at three days of work, from the twenty-fifth to the twenty-eighth of November.

**Alex:** Fifteen pull requests, thirty-seven commits, and twenty-five releases. Version one point one three zero to version one point one five four.

**Sam:** And all of it is in the Combat Calc web app. The Godot game did not change this time.

**Alex:** Let us start with the Board. The first fix is the shooting danger layer. Before, it hatched every square in move plus range.

**Sam:** Which, on most tables, is the whole board. Not much help.

**Alex:** Now it uses line of sight. The clear squares behind terrain show you where to hide.

**Sam:** Next, you can move models one at a time. Double-tap a unit, drag a base, and a label tells you how far the model moved against its Move.

**Alex:** It also warns you when the unit is out of coherency. And a base can not overlap another base. It stops at the edge and slides along it.

**Sam:** Then there is Models left. The app now keeps one record of losses for each unit, for the whole game, battle round by battle round.

**Alex:** So half a squad makes half the attacks. And the losses take the plain models first. Grey Hunters that lose nine models keep their Pack Leader, and his plasma pistol.

**Sam:** That is how players really do it. Now the big one: the Live table.

**Alex:** The Live table is the real table, as it is now. It follows the round and the turn on the tracker. Every time you tap Turn done, it keeps a copy of the table.

**Sam:** And next to it, two cards. Their next turn tells you which of your units the enemy can shoot or charge, and the chance that each one is destroyed.

**Alex:** Your turn gives one suggestion for each of your units. Hold an objective, take one, and which target to attack.

**Sam:** Then the team connected it to the mission forecast. Each move is played fifteen hundred times, and the card only backs a move that is clearly better than standing still.

**Alex:** There was a good bug here. The first version kept every unit frozen in place to the end of the game. For two equal armies, it said eighty-seven percent to win.

**Sam:** And the Mission tab said forty-eight. So now, the table counts only for the battle round in progress.

**Alex:** You can also tap a suggestion and see it on the map. A blue arrow for the move, a red arrow for the attack.

**Sam:** That one came from a real player. Two Dreadnoughts had the same short name, and they looked at the wrong one.

**Alex:** Each move now also shows the risk after the move. For example, sixty-two percent destroyed after the move, against eight percent where it stands.

**Sam:** Now, plans from Claude. There are two ways. One: copy a prompt, paste it into your own Claude chat, and paste the plan back. The app sends nothing.

**Alex:** Two: Ask Claude directly, from the server. That only shows when the server has an API key, and there are daily limits.

**Sam:** And the plan is drawn on the map. Blue arrows for moves, red for attacks, and green rings for units that hold an objective.

**Alex:** Then the most fun part. Play the game out.

**Sam:** From the table as it is, both players follow the turn cards to the end of round five. You see the result after every player turn.

**Alex:** And you can step through it on the Board with chips. One A, one B, two A, two B, and so on.

**Sam:** Later fixes made it more real. Vehicles go round dense terrain. Units arrive from reserves and get out of transports.

**Alex:** And a unit is only destroyed by attacks that can really reach it. On a test table, the units lost went down from nine of fourteen to six.

**Sam:** Two more features for the live game. Update the table: one tap on the map per unit. And the Prediction record.

**Alex:** The Prediction record keeps what the app predicted at each turn, and checks it against what really happened at the end of the game.

**Sam:** It stays on your device. There is a switch, off by default, to send finished games to help improve the predictions.

**Alex:** There was also an offline fix. On a slow connection, the app could show the new version number but run the old code.

**Sam:** Now it loads one full version, always.

**Alex:** Last, the behind-the-scenes work. Many forty-K data sources went offline on about the twenty-fifth. The team saved a backup of the Wahapedia data and the forty-K-D-C packages in the repo.

**Sam:** Lootas and Burna Boyz, now Warhammer Legends, work again in the Combat Calc and the Army Builder.

**Alex:** The browser tests now run in four parts at the same time. About four minutes, not thirty-five.

**Sam:** And the project rules now say: a change to the web app only uses the web app tests, not the Godot checks.

**Alex:** That is three days, twenty-five releases. Thanks for listening.

**Sam:** See you next time.

