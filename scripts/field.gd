extends Node2D
## Placeholder battlefield: an island surrounded by sea, with a few
## stone / wood / metal resource spots.
##
## The coastline is generated from fixed numbers (no randomness), so every
## player's device builds exactly the same island. That matters later for
## lockstep multiplayer.

## Whole world, sea included. The camera is limited to this area.
@export var map_size: Vector2 = Vector2(8192, 8192)
## Average island radius. Leaves a band of open sea around the island.
@export var island_radius: float = 3300.0
## Number of points on the coastline (more = smoother).
@export var coast_points: int = 180

const DEEP_SEA := Color("#1f5f8b")
const SHALLOW_SEA := Color("#3a8fb7")
const SAND := Color("#e3cf94")
const GRASS := Color("#7fa35a")
const GRASS_DARK := Color("#6d9149")
const STONE := Color("#8d8d8d")
const WOOD := Color("#a0703c")
const METAL := Color("#9fc4d6")

# Coastline wobble: [frequency, amplitude, phase]. Fixed so the island is
# the same every time. Change these to reshape the island.
# Only EVEN frequencies: that makes the island look the same after a 180°
# turn, so two players starting on opposite sides get a fair coastline.
const COAST_WAVES := [
	[2, 0.10, 0.6], [4, 0.07, 2.1], [6, 0.04, 4.0], [8, 0.025, 1.3], [12, 0.012, 5.2],
]

# Resource spots, as offsets from the island centre (mirrored for fairness).
const RESOURCES := [
	[Vector2(-1700, -1700), STONE], [Vector2(1700, 1700), STONE],
	[Vector2(-1700, 1700), WOOD], [Vector2(1700, -1700), WOOD],
	[Vector2(0, -1250), METAL], [Vector2(0, 1250), METAL],
	[Vector2(-2300, 0), METAL], [Vector2(2300, 0), METAL],
]

var coastline: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	coastline = _build_coastline()
	queue_redraw()


## True if `world_point` is on land. Ground units will use this to stay
## out of the sea; flying units can ignore it.
func is_on_land(world_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(world_point, coastline)


func get_center() -> Vector2:
	return map_size * 0.5


func _build_coastline() -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := get_center()
	for i in coast_points:
		var angle: float = TAU * i / coast_points
		var wobble: float = 1.0
		for wave in COAST_WAVES:
			wobble += wave[1] * sin(wave[0] * angle + wave[2])
		points.append(center + Vector2.from_angle(angle) * island_radius * wobble)
	return points


func _draw() -> void:
	if coastline.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, map_size), DEEP_SEA)
	_draw_ring(260.0, SHALLOW_SEA)
	_draw_ring(90.0, SAND)
	draw_colored_polygon(coastline, SAND)
	_draw_ring(-120.0, GRASS)
	_draw_ring(-900.0, GRASS_DARK)

	var center := get_center()
	for spot in RESOURCES:
		draw_circle(center + spot[0], 140.0, spot[1])


## Draws the island grown (positive) or shrunk (negative) by `offset`.
func _draw_ring(offset: float, color: Color) -> void:
	var shapes: Array = Geometry2D.offset_polygon(coastline, offset, Geometry2D.JOIN_ROUND)
	for shape in shapes:
		draw_colored_polygon(shape, color)
