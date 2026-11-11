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
- Unit art: animated hand sprites (idle / attack / defend, 5 frames each) on a team-coloured base (pink vs blue). Source sheet in `art_source/hands_sheet.png`; `tools/cut_hand_sprites.py` cuts it into `assets/units/hands.png`. Units face the way they walk and **hop** while walking (base shrinks like a shadow at the top of a hop, slight squash and stretch; each unit at its own pace; it finishes the hop and lands when it stops).
- **One finger:** tap your unit to select it; draw a loop to lasso; tap the ground to move the selection there (they spread into a square formation).
- Selection is shared by all panes: select in one pane, tap the destination in another.
- Selection bar (bottom): each selected type as its hand icon with a count ("× 4"); tap one to keep only that type; Clear to deselect.
- A second finger in the pane cancels a tap or lasso (it becomes a camera gesture).
- **Pathfinding:** units plan a route around lakes, forests, plateaus and resource props (A* on a 4-unit grid, smoothed into straight runs). An order onto blocked ground (e.g. a lake) goes to the nearest open spot. Selected units show their route as a dashed line on the ground.
- Units don't bump into each other yet (they can overlap while walking); local avoidance comes later.

## Economy
- Resources: **stone** (rock), **wood** (paper), **metal** (scissors), scattered on the map.
- All units can gather; each is best at its own resource. Gatherers carry back to base (StarCraft-style).
- Players build their own factories (not captured):
  - Quarry: fists, Paper Mill: open hands, Forge: scissors.

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
