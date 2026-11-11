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
- Unit art: animated hand sprites with five animations of 5 frames each: **idle**, **moving** (hops along with dust puffs), **attack** (wind-up, lunge, POW! / SLAP! / SNIP!), **defend** (crying when hit) and **dying** (dizzy, keels over, a little ghost floats up). On a team-coloured base (pink vs blue). Source: `art_source/hands_sheet_v2.png`, cut by `tools/cut_hand_sprites.py` into `assets/units/hands.png` (192 px cells, row = kind × 5 + animation).
- **One finger:** tap your unit to select it; draw a loop to lasso; tap the ground to move the selection there (they spread into a square formation).
- Selection is shared by all panes: select in one pane, tap the destination in another.
- Selection (right side, level with Build): each selected type as its hand icon with a count ("× 4"); tap one to keep only that type. **Attack** (sword icon; arms an attack-move for the next ground tap, grows while armed) and **Hold** (open palm on a red stop sign: the selection stops and stays put, fighting only what comes within reach, no chasing, until its next order) sit on the left, just under **Build** (hammer and pickaxe; grows a little while picking / placing, tap again to stop). Icons: `art_source/env/button_*.png`; Hold and Settings are built on the Build frame in lilac by `tools/make_buttons.py`.
- Left column: **Build** about a third of the way down (lower on short screens), its options opening upwards; Attack / Hold below it. On phones (short screen side under ~560 CSS px) all game buttons are 35% bigger.
- A game starts zoomed in on your HQ and army (not the whole map).
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
- Look: every swing plays the attack animation once from its wind-up, holding on the impact frame (POW! / SLAP! / SNIP!); the damage number punches in, the attacker pops, and the victim cries or falls right on that frame (a swing shows over a flinch). Purely visual: the sim's timing is unchanged. crying defend animation when hit, HP bar once damaged, floating damage numbers (big red for counter hits). A fallen unit plays its death animation, lies there half a second, then fades. Fallen units leave the selection.
- **Unit voices** (`scripts/sounds.gd`; originals in `art_source/sounds/`, converted by `tools/prep_sounds.sh` to small Ogg files in `assets/sounds/`): *Acknowledge* when selected, *Objective* when given an order (move, attack, gather...), *Attack* when a swing starts, *Defend* when a blow lands, *Death* when a unit falls (once). Every selected unit answers with the same line, together (each a hair apart in pitch and timing, so the words stay clear; quieter per voice in bigger groups; up to 12). Combat sounds only for units on screen in a pane, at most 4 of a kind per 0.3 s, 16 voices in all.
- **Building sounds:** a thud and three wooden hammer knocks when a construction is laid down, a couple of bright knocks and a sparkle when it's finished (on screen only). Synthesised by `tools/make_build_sounds.py`.
- **Music** (`scripts/music.gd`): *Majestic Crescendo* on the start screen, *Antes de la Batalla* in every game mode; both loop and crossfade. Originals in `art_source/music/`; `tools/prep_music.sh` brightens their dull top end (treble lift and a little harmonic sparkle), evens out loudness and makes Ogg files.
- **Settings** (gear button, top right next to full screen, on the start screen and in game): Music volume and Sound effects volume (voices, buildings), on separate "Music" / "SFX" audio buses, remembered on the device (`user://settings.cfg`).
- `combat_enabled` switch on the sim (e.g. for early tutorial steps).

## Economy (prototype)
- Each side has an **HQ**, a town hall (painted art; the red team's has red flag, banners and windows; lose it, lose the game) and starts with **300** stone, wood and metal.
- **Gathering:** tap a resource spot with units selected. They gather 20 at a time and carry it to the nearest drop-off, then repeat: the HQ takes anything, a finished quarry takes stone, a mill wood, a forge metal. So a factory next to a resource doubles as a drop-off. Own resource is twice as fast (2 s vs 4 s): rocks-stone, papers-wood, scissors-metal. Gatherers don't go looking for fights but fight back if attacked.
- **More HQs:** Build → HQ costs 150 of every resource, takes 20 s and can go anywhere on the map (no build range), e.g. as a forward base or a drop-off by far resources. You lose when your last HQ falls.
- **Placing:** after picking a building, touch the map: a see-through preview (50%) of it follows your finger (or the mouse), with a green footprint, or red where it can't go. Lifting the finger builds it there; lifting over a button builds nothing.
- **Build range:** new buildings go within 50 map units of one of your own buildings (HQ, factories, even ones still going up), so a base grows outward step by step. While placing, white circles show the allowed area; tapping outside says it's too far.
- **Factories** (Build button, pick one, tap open ground): Quarry (150 stone, makes rocks), Paper Mill (150 wood, papers), Forge (150 metal, scissors). Drawn with painted art (`assets/env/`, cropped from `art_source/env/` by `tools/prep_env_art.py`) on a patch of the team's colour. 10 s to build; can't train until finished.
- **Double tap a unit:** selects all your units of that type visible in that pane.
- **Tap your HQ with units selected:** each goes to gather what it's fastest at (rock stone, paper wood, scissors metal) from the spot nearest the HQ, dropping off at the nearest HQ or matching factory.
- **Repair:** double tap a damaged building of yours; your units within 40 map units of it (not ones in a fight) walk over and repair it, 10 HP a second each, free. They stop when it's whole. Green numbers show the HP coming back.
- **Cancel / sell:** the building panel's button. Still going up: Cancel, the whole cost back. Finished: Sell, half the cost back. Units queued in it are refunded either way. Tap once ("Sure?"), again within 3 s to do it. Your last HQ can't go.
- **Minimap:** a small map in the top-left of every pane: the island, buildings and hands as dots in team colours, and a white outline of what that pane shows. Touch or drag on it to move that pane's camera. Settings → "Minimap in each pane" turns them off.
- **Queue:** hold the 1-2-3 button (left, under Hold) with one finger, or Shift on a keyboard, and give orders with the other: moves, attack-moves, attacks, gathering and harvesting are added to each unit's plan instead of replacing it, and done in turn (a step whose target is gone is skipped; gathering never ends by itself, so it's a plan's last step). Selected units' dotted routes run through every queued stop. A plain order replaces the plan; Hold cancels it. Lockstep-safe (each unit's steps live in the simulation).
- **Unselect:** tap with two fingers at once (quick, without moving), or right click with a mouse (right drag still pans). Clears hands and buildings.
- **Surrender:** white flag button just left of Settings (in games, not the tutorial). It asks "Surrender?" (Keep playing / Surrender); surrendering loses the game. Pop-up windows (Settings, Surrender?) keep touches off the map while open.
- **Maps:** Hand Island, Twin Lakes, Deep Woods (`scripts/maps.gd`; each mirrored through the centre). Picked on the Play vs Computer / Create Online Game screen (with little previews); the guest gets the host's pick. A different map than the one loaded reloads the scene with the match waiting (`scripts/match_setup.gd`).
- **Hills:** each map says which plateaus are climbable hills and where their hillsides face (with a matching one on the far side). A hillside is a broad grassy slope easing from the hill's edge down to the ground (24 map units; 12 for a second tier), steepening into cliff at its ends; you walk up its gentle middle (its steep flanks and the cliffs are blocked). Level 2 tiers sit on level 1 hills, their hillsides coming down onto the lower top. Tops and gentle hillsides grow trees; resources can sit up there; buildings need flat ground (all on one level). Everything is drawn at the ground's height. Plateaus without hillsides are solid scenery.
- **Difficulty** (vs Computer): Easy (thinks every 2 s, no counter-picking, late small waves), Normal, Hard (thinks twice a second, early big waves, +200 of each resource). Remembered.
- **Countdown:** 3, 2, 1, Fight! before every match (not the tutorial); the game starts moving on Fight!.
- **Online timing:** both players start the countdown together (each says when it has loaded; "Waiting for your opponent…" until then). The host times a few round trips through the relay and both use an order delay to fit (one-way trip + 4 ticks, 6 to 24 ticks), so far-away servers don't cause constant pauses. "Waiting for the other player…" shows only for pauses over ¾ s.
- **End screen:** Rematch and Quit to menu. vs Computer, Rematch restarts the same map and difficulty. Online, the other player sees "Your opponent wants a rematch!" (Accept rematch); both restart when both agree, same seats and map. If they left, Rematch is masked out. Messages carry the match number, so the last match's orders never leak in.
- **Tap priority** with units selected: an enemy unit under the finger comes first (even standing on your HQ's picture), unless one of your own units is closer to the finger.
- Prices in the Build menu and on train buttons show the resource icons ("150 [rocks]").
- **Selecting buildings:** tap a building anywhere on its picture (or its ground circle), or draw a loop around several. A loop with any of your units inside selects the units; otherwise it selects your buildings inside it. The panel shows one row per type ("Paper Mill × 2"); its + button trains at the least busy finished one.
- **Building panel:** appears right beside the selected building(s), in the pane you picked them in, and follows them as you pan (bottom centre if they're out of view).
- **Training:** tap your factory, then the + button: 60 of its resource, 5 s each, up to 5 queued. New units go straight to gathering their own resource (rocks stone, papers wood, scissors metal; nearest spot to the factory) unless a fight is on (one of your units is fighting, or enemies are within 60 of your buildings); then they walk out towards the island centre and wait. The computer opponent decides for its own units.
- Buildings block walking, push units out, can be attacked (10 per hit) and show HP bars. HQ 2000 HP, factories 800. Their footprint covers the ground their picture's base is drawn on (HQ radius 12, factories 9), so units can't walk into a drawing.
- Destroying the enemy's last HQ = **Victory**; losing your last = **Defeat** (Play again).
- Resources have icons (rocks, logs, ingots; `assets/env/icon_*.png`), used in the counter at the top right and on the map.
- Resource spots (`scripts/resources_view.gd`), each on a tinted patch of ground with a floating badge (resource icon + amount left):
  - **Stone**: rock piles (painted art).
  - **Wood**: lumber camps (pines and a log pile), and **every forest tree** (100 wood each). A cut-down tree is gone and its ground opens up for walking (and building), so forests thin out over a match.
  - **Metal**: crystal clusters on rocks (painted art).
- Tap anywhere on a spot's model (crystal tip, tree) or its ground patch to gather.
- Spots hold 2000 (stone, wood) / 1000 (metal) and sink away when empty.
- When a spot or tree runs out, gatherers move on by themselves to the nearest one of the same resource (within 40 map units of where they were working). A gatherer that can't reach its tree (deep in a forest) picks the nearest other one.
- Still to come: more drop-off points.

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
- Terrain on the island (all mirrored): a central lake and two side lakes, six pine forests (172 trees, drawn in two batches), four raised plateaus with cliffs. Lakes, plateaus and standing trees block ground units; cut trees don't.
- Later maps: several islands, rivers, cliffs.

## Matches
- Win by destroying the enemy HQ, or when the opponent concedes.
- 10-30 minutes. Ideas against stalemates: HQ armor decays after ~20 min; resource spots run out.
- **Tutorial** (start menu): opens with a tip to hold the device sideways (landscape); then a card at the top walks through select, loop, move, camera, double tap, gather, build, train, split / merge panes and a first fight (enemies arrive for it); each step moves on when done, or Skip. The on-screen instructions are gone; the tutorial teaches them.
- Later tutorial ideas: upgrades, terrain, defences, Shifter.
- Terrain ideas: shallow water slows paper, rocky ground slows scissors.

## Open questions
- Who can hit flyers?
- Typical army size.
- Fairness between tablet and phone players.

## Tech
- Godot 4.6, GL Compatibility renderer (Android, iOS, web).
- Panes: each is a SubViewport sharing one 3D world, with its own camera. Layout is a tree of splits.
- Multiplayer: deterministic lockstep (send commands only). Game logic uses integers / fixed point.
- **Online play (first version):** start menu → Create Online Game (shows a 4-digit code) or Join Online Game (number pad). Two players, red (creator) vs blue.
  - Relay server `server/index.js` (Node + ws): pairs players by code, passes messages, stamps each with the sender's seat. Free hosting on Render via `render.yaml`. The game's server address lives in `scripts/net/net_config.gd` (or `?server=wss://...` on the web page).
  - `scripts/net/net_session.gd` connects the sim: orders are sent 6 ticks (300 ms) ahead, encoded in Godot's binary format (no JSON floats, no objects); every tick waits for both players' orders, seat 0's applied first. A player's orders only work on their own side.
  - Every second both sides compare a fingerprint of the game; a mismatch ends the game ("out of sync"). The other player leaving ends it too. "Waiting for the other player…" shows while stalled.
  - Tests: `tests/test_lockstep.gd` (two games wired directly), `tests/test_online.gd` (real server, two menus, two games over the network), `server/test.js`.
  - Live relay: wss://warring-hands-relay.onrender.com (Render, free plan).
  - Still to come: reconnecting after a dropped connection, quick match, more than 2 players, chat / emotes.
- Sim (`scripts/sim/sim.gd`): 20 ticks/s, positions in whole sim units (100 per map unit), commands run 2 ticks after they are given. Tested: same orders give identical results. Pathfinding uses a walkable grid (`scripts/sim/nav_grid.gd`) with whole-number routes. Still to do for online play: make sure every device builds the identical grid (it's derived from the island's shapes with decimals), e.g. ship it prebuilt or compare a checksum at match start.
- Tests: `tests/run_tests.sh` (panes, map stillness, units). CI runs them on every push.
- Updates: the installed web app keeps a saved copy of the game. Each web build is stamped with its commit (`scripts/build_info.gd`, `version.txt` on the site); the start menu shows the version and, when the site has a newer one, a "New version: tap to update" button that clears the saved copy and reloads.
- Full screen: a button under the resource counter (browsers only allow full screen from a tap). The web build is also an installable web app (fullscreen, landscape, app icon `assets/icon.png`): "Add to Home Screen" opens it with no address bar, which is the only way on iPhone.
- Builds: GitHub Actions exports Web (GitHub Pages) and an Android debug APK. iOS builds on the Mac with Xcode.
