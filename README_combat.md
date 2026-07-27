Here’s a concise design summary of the gameplay system we’ve developed so far.
Strategy game battle system (Lords of the Realm–style, no RTS)
Core goal
Create a grand strategy game with tactical battles that:
feels like Lords of the Realm 2,
is fully turn-based,
works well in hotseat multiplayer,
avoids RTS micromanagement,
still preserves the tension of maneuver and prediction.
Battle model: WEGO (simultaneous turns)
Each battle turn has two stages:
1. Planning phase
All players secretly assign one order per formation.
Possible orders:
Advance
Hold
Wheel left/right
Charge
Withdraw
Attack nearest
Attack specific target
Players do not see enemy orders.
2. Resolution phase
Orders are executed in a fixed sequence:
Phase
What happens
Ranged
Archers fire at targets in their current positions.
Movement
Formations move simultaneously.
Charge
Cavalry and charge orders resolve.
Melee
Adjacent formations fight.
Morale
Shaken, retreat, or rout checks.
A short animated replay shows the turn after all phases resolve.
Important rule: archers fire before movement
Archers target the enemy’s current tile, not the tile it will move to.
This represents a volley being loosed before the enemy advances.
It keeps the rules simple and readable.
Formations, not individual soldiers
The player never controls hundreds of separate units.
A formation is the smallest controllable battlefield element.
Example formation sizes
Type
Men
Militia
80–120
Spearmen
100–150
Archers
80–100
Knights
20–80
A 1000-man army is represented by roughly 10 formations.
Command-capacity system (key mechanic)
The game is balanced around the number of orders a player can comfortably issue per turn.
Target
Optimal: 8–12 controllable formations per player.
This keeps hotseat turns under about 60 seconds.
Commander capacity
Commander
Max formations
Village reeve
6
Knight
8
Baron
10
Earl
12
King
15
Better commanders can control more formations, not necessarily more soldiers.
Automatic formation chunking
Before battle, the army is automatically organized.
Step 1 — group by troop type
Example:
Spearmen: 420
Archers: 260
Militia: 240
Knights: 80

Step 2 — split into formations
With a capacity of 10:
Spearmen -> 4 formations
Archers  -> 3 formations
Militia  -> 2 formations
Knights  -> 1 formation
Total    -> 10 formations

The player commands 10 counters, not 1000 men.
Scaling to huge battles
If the army exceeds command capacity, the number of formations stays roughly the same.
2400 men, capacity 10
10 formations of ~240 men each.
Larger formations become:
slower,
harder to turn,
more vulnerable to flanking,
but stronger in a frontal fight.
This creates a natural tradeoff between army size and controllability.
Battlefield and movement
Map
Grid size: 20×15 (roughly).
Each tile represents 50–100 meters.
One formation occupies 1 tile.
Movement conflicts
When two formations try to enter the same tile:
Contest rule (recommended)
Compare initiative / formation weight.
Winner enters the tile.
Loser stays in place and becomes Disrupted.
Disrupted formations fight worse next turn.
Combat system
Strength points
A formation has 0–10 strength.
10 = full formation
5 = half strength
0 = destroyed
Damage is applied in chunks, not individual deaths.
Frontage
A formation normally engages one enemy directly ahead.
Rear formations provide support bonuses.
Flanking grants large combat and morale bonuses.
Cavalry charges are especially powerful against exposed sides or rear.
Morale (the main battle decider)
Each turn, formations make a morale check based on:
casualties,
flank/rear attacks,
nearby routing allies,
commander presence,
support from friendly formations.
States
State
Effect
Steady
Fights normally
Shaken
Combat penalties
Retreating
Forced backward movement
Routed
Formation leaves the battle
Battles are expected to end through morale collapse, not total annihilation.
Turn-length targets
Battle size
Planning time
20 vs 20
15–30 sec
200 vs 200
30–45 sec
1000 vs 1000
45–60 sec
The core gameplay loop
Secret orders
Simultaneous resolution
Morale shifts
Next planning phase
The intended feel is:
RTS-style anticipation and maneuver, but with turn-based planning and hotseat-friendly pacing.
Players win by:
predicting enemy movements,
maintaining formation,
protecting flanks,
timing charges,
and preserving morale under pressure.

