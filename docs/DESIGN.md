# Warring Hands: design notes

*Childhood Game Gone Aggro*: a touch-first, multiplayer rock-paper-scissors RTS, built for tablets (playable on phones).

## Core idea
- Units are hand gestures: **fist (rock)**, **open hand (paper)**, **two fingers (scissors)**.
- Rock beats scissors, scissors beat paper, paper beats rock. Same vs same is an even fight.
- The selling point is **how you see and control the battlefield**: you cut your screen into panes.

## Screen panes
- **Cut**: swipe from a pane's side (or its handle) across it. Cuts snap to straight lines.
- **Resize**: drag a divider.
- **Merge**: drag a divider until one pane closes. Panes too small snap shut.
- Each pane has its own camera and zoom.
- Outer screen edges belong to the OS (back / home), so cuts start from visible handles there.
- Ideas to explore: drag units from one pane to a destination in another; pin a pane to a group.

## Controls
- **One finger, units:** tap to select, draw a loop to lasso, tap ground to move/attack.
- **Two fingers, camera:** drag to pan, pinch to zoom (with limits; fully zoomed out = whole map).
- Zoomed out, units become simple icons.
- Groups: lasso then save to a numbered button; filter a selection by gesture type.
- Tablet: two hands can work two panes at once (multi-touch per pane).

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

## Matches
- Win by destroying the enemy HQ, or when the opponent concedes.
- 10-30 minutes. Ideas against stalemates: HQ armor decays after ~20 min; resource spots run out.
- Tutorial introduces things gradually: open field, then gathering, factories, panes, upgrades, terrain, defences, Shifter.
- Terrain ideas: water slows paper, rocky ground slows scissors.

## Open questions
- Who can hit flyers?
- Typical army size.
- Fairness between tablet and phone players.

## Tech
- Godot 4.6, GL Compatibility renderer (Android, iOS, web).
- Multiplayer: deterministic lockstep (send commands only). Game logic uses integers / fixed point.
- Relay / matchmaking: Nakama (planned).
- Builds: GitHub Actions exports Web (GitHub Pages) and an Android debug APK. iOS builds on the Mac with Xcode.
