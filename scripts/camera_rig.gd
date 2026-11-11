extends Camera3D
## Camera for one pane: a tilted, orthographic view (classic 2.5D RTS look,
## Ragnarok-style angle) looking down at a point on the ground.
##
## Orthographic (no perspective) means a pane's picture can be cut, resized
## or merged and every bit of the map stays exactly where it was on screen.
##
## It doesn't read input itself. The pane layout works out which pane a
## gesture belongs to and calls pan_by_screen / zoom_at on that pane's camera.

## Ground point at the centre of the pane (y is always 0).
var target: Vector3 = Vector3.ZERO
## Zoom: map units per screen pixel. Smaller = zoomed in. Only pinching /
## the mouse wheel change it; resizing a pane never does.
var units_per_pixel: float = 0.25
## Height of the pane on screen, in pixels.
var pane_height: float = 1200.0

## How steeply the camera looks down, in degrees (90 = straight down).
@export var pitch_degrees: float = 50.0
## Closest zoom (map units per pixel).
## (0.045: unit sprites show at most about 1.3x the size they're drawn, so
## they never go blocky.)
@export var min_units_per_pixel: float = 0.045
## Furthest zoom (roughly "whole island in a full-screen pane").
@export var max_units_per_pixel: float = 0.6
## Area the camera may look at (x, z on the ground).
@export var map_rect: Rect2 = Rect2(0, 0, 820, 820)

## How far back the camera sits. Only affects clipping, not the picture.
const BACK_OFF := 1500.0


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	keep_aspect = Camera3D.KEEP_HEIGHT
	near = 1.0
	far = 4000.0
	_apply()


## Shows the whole map.
func fit_whole_map() -> void:
	target = Vector3(map_rect.get_center().x, 0, map_rect.get_center().y)
	units_per_pixel = max_units_per_pixel
	_apply()


## Copies where another pane's camera is looking.
func copy_view(other: Camera3D) -> void:
	target = other.target
	units_per_pixel = other.units_per_pixel
	pane_height = other.pane_height
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
	units_per_pixel = clampf(units_per_pixel / factor, min_units_per_pixel, max_units_per_pixel)
	_apply()
	var after: Variant = _ground_at(screen_point)
	if before != null and after != null:
		target += (before as Vector3) - (after as Vector3)
		_apply()


## Re-applies limits.
func refit() -> void:
	_apply()


## Tells the camera how tall its pane is (without moving the map).
func set_pane_height(height: float) -> void:
	pane_height = maxf(height, 1.0)
	_apply()


## Keeps the map still on screen when this pane's rectangle changes
## (cut, resize, merge). `old_rect` and `new_rect` are the pane's position
## on the whole screen before and after. The ground that was under the new
## pane's centre moves to its centre, at the same scale, so the pane simply
## shows more or less of the map around what was already there. Zoom is
## not touched.
func reanchor(old_rect: Rect2, new_rect: Rect2) -> void:
	target = _ground_at_in(new_rect.get_center() - old_rect.position, old_rect.size)
	pane_height = maxf(new_rect.size.y, 1.0)
	_apply()


func _apply() -> void:
	units_per_pixel = clampf(units_per_pixel, min_units_per_pixel, max_units_per_pixel)
	target.x = clampf(target.x, map_rect.position.x, map_rect.end.x)
	target.z = clampf(target.z, map_rect.position.y, map_rect.end.y)
	target.y = 0.0
	var pitch: float = deg_to_rad(pitch_degrees)
	rotation = Vector3(-pitch, 0, 0)
	position = target + Vector3(0, sin(pitch), cos(pitch)) * BACK_OFF
	size = units_per_pixel * pane_height


## Where a point of a pane with the given size hits the ground. Works even
## before the viewport is resized, and for points outside the pane.
func _ground_at_in(point: Vector2, pane_size: Vector2) -> Vector3:
	var half_h: float = units_per_pixel * pane_size.y * 0.5
	var aspect: float = pane_size.x / pane_size.y
	var ndc := Vector2(2.0 * point.x / pane_size.x - 1.0, 1.0 - 2.0 * point.y / pane_size.y)
	var origin: Vector3 = transform * Vector3(ndc.x * half_h * aspect, ndc.y * half_h, 0.0)
	var dir: Vector3 = -transform.basis.z
	return origin + dir * (-origin.y / dir.y)


## Where a point on this pane's screen hits the ground, or null.
func ground_at(screen_point: Vector2) -> Variant:
	return _ground_at(screen_point)


func _ground_at(screen_point: Vector2) -> Variant:
	var origin: Vector3 = project_ray_origin(screen_point)
	var dir: Vector3 = project_ray_normal(screen_point)
	if dir.y > -0.001:
		return null
	return origin + dir * (-origin.y / dir.y)
