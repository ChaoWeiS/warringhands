extends RefCounted
## What the next match is (kept across a scene reload): which map, how hard
## the computer plays, and, when a match is waiting to start after the
## reload, what kind.
##
## The island is built when the scene loads, so picking a different map
## reloads the scene with `pending` set; game_controller.gd then starts that
## match straight away instead of showing the menu.

const Maps := preload("res://scripts/maps.gd")
const DIFFICULTIES := ["easy", "normal", "hard"]

## The map the next field builds (and, after it's built, the one in play).
static var map := "island"
## The map the field in the scene was built with.
static var built_map := ""
## "easy", "normal" or "hard" (vs Computer).
static var difficulty := "normal"
## {} or {"mode": "computer" | "tutorial" | "online", "seat": int}.
static var pending := {}
## An online match's session, carried across the reload.
static var session: Node = null
