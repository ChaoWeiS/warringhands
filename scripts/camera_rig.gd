extends Camera3D
## Camera for one pane: a Ragnarok-style tilted view looking down at a
## point on the ground.
##
## It doesn't read input itself. The pane layout works out which pane a
## gesture belongs to and calls pan_by_screen / zoom_at on that pane's camera.

## Ground point the camera looks at (y is always 0).
var target: Vector3 = Vector3.ZERO
## Distance from the target. Smaller = zoomed in.
var distance: float = 300.0

## How steeply the camera looks down, in degrees (90 = straight down).
@export var pitch_degrees: float = 50.0
## Closest zoom.
@export var min_distance: float = 25.0
## Furthest zoom (roughly "whole island in view").
@export var max_distance: float = 1100.0
## Area the camera may look at (x, z on the ground).
@export var map_rect: Rect2 = Rect2(0, 0, 820, 820)


func _ready() -> void:
	fov = 35.0
	near = 1.0
	far = 4000.0
	_apply()


## Shows the whole map.
func fit_whole_map() -> void:
	target = Vector3(map_rect.get_center().x, 0, map_rect.get_center().y)
	distance = max_distance
	_apply()


## Copies where another pane's camera is looking.
func copy_view(other: Camera3D) -> void:
	target = other.target
	distance = other.distance
	_apply()


## Moves the view so the ground follows the fingers.
func pan_by_screen(screen_delta: Vector2) -> void:
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var g0: Variant = _ground_at(center)
	var g1: Variant = _ground_at(center + screen_delta)
	if g0 == null or g1 == null:
		return
	target -= (g1 as Vector3) - (g0 as Vector3)
	_apply()


## Zooms by `factor` (>1 = closer), keeping the ground under `screen_point` fixed.
func zoom_at(factor: float, screen_point: Vector2) -> void:
	var before: Variant = _ground_at(screen_point)
	distance = clampf(distance / factor, min_distance, max_distance)
	_apply()
	var after: Variant = _ground_at(screen_point)
	if before != null and after != null:
		target += (before as Vector3) - (after as Vector3)
		_apply()


## Re-applies limits, e.g. after the pane was resized.
func refit() -> void:
	_apply()


func _apply() -> void:
	distance = clampf(distance, min_distance, max_distance)
	target.x = clampf(target.x, map_rect.position.x, map_rect.end.x)
	target.z = clampf(target.z, map_rect.position.y, map_rect.end.y)
	target.y = 0.0
	var pitch: float = deg_to_rad(pitch_degrees)
	rotation = Vector3(-pitch, 0, 0)
	position = target + Vector3(0, sin(pitch), cos(pitch)) * distance


## Where a point on this pane's screen hits the ground, or null.
func _ground_at(screen_point: Vector2) -> Variant:
	var origin: Vector3 = project_ray_origin(screen_point)
	var dir: Vector3 = project_ray_normal(screen_point)
	if dir.y > -0.001:
		return null
	return origin + dir * (-origin.y / dir.y)
