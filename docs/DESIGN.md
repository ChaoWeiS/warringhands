# Warring Hands: design notes

*Childhood Game Gone Aggro*: a touch-first, multiplayer rock-paper-scissors RTS, built for tablets (playable on phones).

## Core idea
- Units are hand gestures: **fist (rock)**, **open hand (paper)**, **two fingers (scissors)**.
- Rock beats scissors, scissors beat paper, paper beats rock. Same vs same is an even fight.
- The selling point is **how you see and control the battlefield**: you cut your screen into panes.

## Look
- **2.5D**: 2D sprites standing on a 3D world, like Ragnarok Online. Sprites always face the camera.
- Tilted **orthographic** camera (about 50° down, no perspective). Needed so cut / resized panes keep the map exactly still; also makes tapping units precise.
- **Pastel** palette: soft blue sea, cream sand, mint grass, pink-blossom trees, lavender stone, aqua crystals.
- Soft blob shadows under units instead of real-time shadows (cheaper on phones).
- Game logic stays flat 2D (positions on the ground plane); only the visuals are 3D.

## Screen panes
- **Cut**: grab the grip tab in the middle of a pane's side and swipe across the pane. The cut line follows your finger; it happens if you swipe far enough (about halfway). Cuts are straight lines.
- **Resize**: drag a divider.
- **Merge**: drag a divider until one pane closes. Panes too small snap shut.
- Each pane has its own camera and zoom.
- Dividers are wide with a dotted grip knob, and can be grabbed anywhere along them (about 40 px either side). Snap points at 1/3, 1/2, 2/3.
- Cut tabs sit well inside each pane, clear of the divider grab zone (and of the OS back / home gestures at the screen edge).
- If a finger starts a cut by accident and a second finger lands in the pane, it becomes a normal two-finger pan / zoom instead.
- Cutting, resizing and merging never move the map: each pane keeps showing exactly what was already under it, and simply reveals or hides more at its edges, at the same zoom. Only the player's own pinch changes zoom, for better orientation.
- Ideas to explore: drag units from one pane to a destination in another; pin a pane to a group.

## Controls
- **One finger, units:** tap to select, draw a loop to lasso, tap ground to move/attack.
- **Two fingers, camera:** drag to pan, pinch to zoom (with limits; fully zoomed out = whole map).
- Zoomed out, units become simple icons.
- Groups: lasso then save to a numbered button; filter a selection by gesture type.
- Tablet: two hands can work two panes at once (multi-touch per pane).

## Units and orders (prototype)
- Each side starts with 4 rocks, 4 papers, 4 scissors.
- Unit art: animated hand sprites (idle / attack / defend / death, 5 frames each) on a team-coloured base (pink vs blue), all in `assets/units/hands.png`. Idle and defend come from `art_source/hands_sheet.png` (`tools/cut_hand_sprites.py`); attack (wind-up, lunge with a motion trail, recover) and death (keels over, X eyes) from `art_source/attack_sheet.png` and `death_sheet.png` (`tools/cut_grid_sprites.py`, for sheets with one kind per row on a white grid). Units face the way they walk and **hop** while walking (base shrinks like a shadow at the top of a hop, slight squash and stretch; each unit at its own pace; it finishes the hop and lands when it stops).
- **One finger:** tap your unit to select it; draw a loop to lasso; tap the ground to move the selection there (they spread into a square formation).
- Selection is shared by all panes: select in one pane, tap the destination in another.
- Selection bar (bottom): each selected type as its hand icon with a count ("× 4"); tap one to keep only that type; **Attack** arms an attack-move for the next ground tap; Clear to deselect.
- A second finger in the pane cancels a tap or lasso (it becomes a camera gesture).
- **Pathfinding:** units plan a route around lakes, forests, plateaus and resource props (A* on a 4-unit grid, smoothed into straight runs). An order onto blocked ground (e.g. a lake) goes to the nearest open spot. Selected units show their route as a dashed line on the ground.
- **Collision:** each unit has a round body (radius 3.2 map units); bodies don't overlap (pushed apart 8 times a tick, never onto blocked ground).
  - Your idle units **give way**: they step sideways out of a walker's path, just far enough, and the walker carries on.
  - **Enemies hold their ground**: you can't walk through them. A unit pressed against them (or otherwise unable to make progress for ~1.5 s) stops there. Combat will take over from here.
  - Idle units of the same side that end up too close **fan out** slowly until each has its own space.
  - A walker whose exact spot is already taken stops right beside it.
  - Whole-number maths in a fixed order, so it stays lockstep-safe.

## Combat (prototype)
- Every unit: **100 HP**, one hit per second against an enemy it's touching.
- Damage: same type **10**; counter (rock > scissors > paper > rock) **20**; countered **5**. A counter duel ends in ~4 s with the winner on 75 HP.
- Idle units spot enemies within sight (35 map units), walk up and fight; give up chasing beyond 50.
- Orders:
  - **Move** (tap ground): walk there first, fight after. A unit attacked on the way stops and **fights back**.
  - **Attack-move** (Attack button, then tap ground; red marker): walk there, fighting any enemy met on the way, then carry on.
  - **Attack** (tap an enemy with units selected; red ring on the enemy): hunt down that unit until it's dead.
- Charging a mirrored army with attack-move is a roughly even trade; defenders keep a slight edge (they're already in position).
- All hits in a tick land at once (no first-strike advantage from unit ids).
- Look: every swing plays the attack animation once from its wind-up (a swing shows over a flinch), crying defend animation when hit, HP bar once damaged, floating damage numbers (big red for counter hits). A fallen unit plays its death animation, lies there half a second, then fades. Fallen units leave the selection.
- `combat_enabled` switch on the sim (e.g. for early tutorial steps).

## Economy (prototype)
- Each side has an **HQ** (lose it, lose the game) and starts with **300** stone, wood and metal.
- **Gathering:** tap a resource spot with units selected. They gather 20 at a time and carry it to the HQ, then repeat. Own resource is twice as fast (2 s vs 4 s): rocks-stone, papers-wood, scissors-metal. Gatherers don't go looking for fights but fight back if attacked.
- **Factories** (Build button, pick one, tap open ground): Quarry (150 stone, makes rocks), Paper Mill (150 wood, papers), Forge (150 metal, scissors). 10 s to build; can't train until finished.
- **Training:** tap your factory, then the + button: 60 of its resource, 5 s each, up to 5 queued. New units walk out towards the island centre.
- Buildings block walking, push units out, can be attacked (10 per hit) and show HP bars. HQ 2000 HP, factories 800.
- Destroying the enemy HQ = **Victory**; losing yours = **Defeat** (Play again).
- Resource spots hold 2000 (stone, wood) / 1000 (metal) and disappear when empty.
- Still to come: depleted spots should vanish visually; more drop-off points.

## Enemy AI (prototype)
- Plays the blue side by the same rules, giving the same kinds of orders a player can (so it stays lockstep-safe). Thinks once a second (`scripts/sim/ai.gd`).
- Workers: one on each resource (each on its own fastest resource), plus two extra on whatever its favourite unit costs.
- Builds a quarry, mill and forge beside its HQ, the favourite's factory first.
- **Counters you:** its favourite unit is whatever beats your most common type. Other types are only trained while the favourite outnumbers each of them 2 to 1.
- Defends: enemies within 60 of its buildings get its whole idle army sent at them.
- Attacks: first wave at 2.5 min (needs 6+ units), then every 45 s, each wave 2 units bigger, at your HQ.
- Against a player who does nothing it wins in about 3 minutes.
- Ideas: difficulty levels (timings, wave sizes), smarter targeting (go for workers / factories), retreating.

## Upgrades and buildings
- Upgrade with wood: **flight**. With stone: **tougher**. With metal: **hits harder**.
- Upgrade a unit with its own resource: small boost to all stats.
- **Gym**: upgrades specific unit types. **Library**: researches flight / attack / defence.
- **Defence buildings**: ranged attack; units can hide inside. (Idea: the building attacks as whatever gesture is inside.)
- **Shifter**: change a unit's gesture, with a cooldown (and a short helpless moment while switching).

## Map
- An **island surrounded by sea** (8192 x 8192 world, sea included). No hard walls: the sea is the boundary.
- The island looks the same when turned 180°, so two players starting on opposite sides get a fair coastline. Resource spots are mirrored too.
- Ground units cannot enter the sea; flyers (wood upgrade) can cross it.
- Terrain on the island (all mirrored): a central lake and two side lakes, six forests, four raised plateaus with cliffs. Forests, lakes and plateaus block ground units for now.
- Later maps: several islands, rivers, cliffs.

## Matches
- Win by destroying the enemy HQ, or when the opponent concedes.
- 10-30 minutes. Ideas against stalemates: HQ armor decays after ~20 min; resource spots run out.
- Tutorial introduces things gradually: open field, then gathering, factories, panes, upgrades, terrain, defences, Shifter.
- Terrain ideas: shallow water slows paper, rocky ground slows scissors.

## Open questions
- Who can hit flyers?
- Typical army size.
- Fairness between tablet and phone players.

## Tech
- Godot 4.6, GL Compatibility renderer (Android, iOS, web).
- Panes: each is a SubViewport sharing one 3D world, with its own camera. Layout is a tree of splits.
- Multiplayer: deterministic lockstep (send commands only). Game logic uses integers / fixed point.
- Sim (`scripts/sim/sim.gd`): 20 ticks/s, positions in whole sim units (100 per map unit), commands run 2 ticks after they are given. Tested: same orders give identical results. Pathfinding uses a walkable grid (`scripts/sim/nav_grid.gd`) with whole-number routes. Still to do for online play: make sure every device builds the identical grid (it's derived from the island's shapes with decimals), e.g. ship it prebuilt or compare a checksum at match start.
- Tests: `tests/run_tests.sh` (panes, map stillness, units). CI runs them on every push.
- Relay / matchmaking: Nakama (planned).
- Builds: GitHub Actions exports Web (GitHub Pages) and an Android debug APK. iOS builds on the Mac with Xcode.
