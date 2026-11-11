extends Node2D
## Placeholder battlefield: an open field with a grid and a few
## stone / wood / metal resource spots, so there is something to pan
## and zoom around while the real map and units are built.

@export var map_size: Vector2 = Vector2(4096, 4096)
@export var cell: float = 256.0

const GROUND := Color("#7fa35a")
const GRID := Color(1, 1, 1, 0.12)
const BORDER := Color("#3d5228")
const STONE := Color("#8d8d8d")
const WOOD := Color("#a0703c")
const METAL := Color("#9fc4d6")

# Fixed spots (not random) so every player sees the same map.
const RESOURCES := [
	[Vector2(900, 900), STONE], [Vector2(3196, 3196), STONE],
	[Vector2(900, 3196), WOOD], [Vector2(3196, 900), WOOD],
	[Vector2(2048, 1300), METAL], [Vector2(2048, 2796), METAL],
]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size), GROUND)
	var x: float = cell
	while x < map_size.x:
		draw_line(Vector2(x, 0), Vector2(x, map_size.y), GRID, 2.0)
		x += cell
	var y: float = cell
	while y < map_size.y:
		draw_line(Vector2(0, y), Vector2(map_size.x, y), GRID, 2.0)
		y += cell
	for spot in RESOURCES:
		draw_circle(spot[0], 90.0, spot[1])
	draw_rect(Rect2(Vector2.ZERO, map_size), BORDER, false, 16.0)
