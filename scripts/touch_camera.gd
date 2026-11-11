extends Camera2D
## Camera for one pane of the battlefield.
##
## Two fingers move the camera: drag together to pan, pinch to zoom.
## One-finger input is deliberately ignored here, so it stays free for
## selecting, lassoing and commanding units.
##
## On desktop (for testing): mouse wheel zooms, right-drag pans.

## Most zoomed out (smaller = see more of the map).
@export var min_zoom: float = 0.25
## Most zoomed in.
@export var max_zoom: float = 2.5
## The playable map area. The camera never shows beyond it.
@export var map_rect: Rect2 = Rect2(0, 0, 4096, 4096)

var _touches: Dictionary = {}  # finger index -> screen position
var _last_center: Vector2 = Vector2.ZERO
var _last_distance: float = 0.0
var _right_dragging: bool = false


func _ready() -> void:
	limit_left = int(map_rect.position.x)
	limit_top = int(map_rect.position.y)
	limit_right = int(map_rect.end.x)
	limit_bottom = int(map_rect.end.y)
	_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_reset_gesture()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			_update_two_finger_gesture()
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventPanGesture:
		_pan_by_screen(-event.delta * 20.0)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_dragging = event.pressed
	elif event is InputEventMouseMotion and _right_dragging:
		_pan_by_screen(event.relative)


func _reset_gesture() -> void:
	_last_distance = 0.0
	if _touches.size() == 2:
		var points: Array = _touches.values()
		_last_center = (points[0] + points[1]) * 0.5
		_last_distance = points[0].distance_to(points[1])


func _update_two_finger_gesture() -> void:
	var points: Array = _touches.values()
	var center: Vector2 = (points[0] + points[1]) * 0.5
	var distance: float = points[0].distance_to(points[1])

	if _last_distance > 0.0:
		# Fingers moving together pans; fingers spreading/closing zooms.
		_pan_by_screen(center - _last_center)
		_zoom_at(distance / _last_distance, center)

	_last_center = center
	_last_distance = distance


## Moves the view so the map follows the fingers.
func _pan_by_screen(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp_position()


## Zooms by `factor`, keeping the world point under `screen_point` fixed.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var before: Vector2 = _screen_to_world(screen_point)
	var new_zoom: float = clampf(zoom.x * factor, _effective_min_zoom(), max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	var after: Vector2 = _screen_to_world(screen_point)
	position += before - after
	_clamp_position()


func _screen_to_world(screen_point: Vector2) -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	return position + (screen_point - view_size * 0.5) / zoom.x


## Never zoom out further than "whole map fits in this pane".
func _effective_min_zoom() -> float:
	var view_size: Vector2 = get_viewport_rect().size
	var fit: float = minf(view_size.x / map_rect.size.x, view_size.y / map_rect.size.y)
	return maxf(min_zoom, fit)


func _clamp_position() -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom.x
	var min_pos: Vector2 = map_rect.position + half_view
	var max_pos: Vector2 = map_rect.end - half_view
	# If the view is wider than the map, centre on that axis.
	position.x = map_rect.get_center().x if min_pos.x > max_pos.x else clampf(position.x, min_pos.x, max_pos.x)
	position.y = map_rect.get_center().y if min_pos.y > max_pos.y else clampf(position.y, min_pos.y, max_pos.y)
