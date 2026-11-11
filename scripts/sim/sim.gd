extends Node
## The game simulation: where every unit is and what it's doing.
##
## Written for lockstep multiplayer from the start:
##   - It runs in fixed ticks (20 per second), not per frame.
##   - Positions are whole numbers (1 map unit = 100 sim units), so every
##     device computes exactly the same result.
##   - Players never move units directly. They send commands, which run a
##     couple of ticks later (online, that's the time to reach the other player).
## The visuals (units_view.gd) only read from here and smooth between ticks.

signal ticked

const NavGrid := preload("res://scripts/sim/nav_grid.gd")

## Sim units per map unit.
const SCALE := 100
const TICK_RATE := 20
const TICK_TIME := 1.0 / TICK_RATE
## Commands run this many ticks after they're given.
const COMMAND_DELAY := 2
## Gap between units when a group moves together (sim units).
const SPACING := 1000
## Each unit's round body (sim units). Bodies don't overlap: units closer
## than two radii are pushed apart every tick.
const RADIUS := 320
## Overlap passes per tick (more = firmer, a little slower).
const PUSH_PASSES := 2

enum Kind { ROCK, PAPER, SCISSORS }

## Movement per tick, by kind (placeholder numbers until balancing).
const SPEED := [72, 85, 78]
const UNITS_PER_KIND := 4

## The island, for where units can walk.
@export var field_path: NodePath

var field: Node = null
var tick: int = 0
## Every unit: {id, team, kind, x, z, px, pz, tx, tz, moving, path}.
## (px, pz) = position at the previous tick, for smooth drawing.
## path = waypoints (Vector2i, sim units) still to walk; the last is (tx, tz).
var units: Array = []

var _by_id: Dictionary = {}
var _next_id: int = 1
var _pending: Dictionary = {}  # tick -> Array of commands
var _accum: float = 0.0
var _nav = null  # NavGrid, built on first use

## One walkable grid per island, shared by every sim using it (building it
## takes a moment).
static var _nav_cache: Dictionary = {}


func _ready() -> void:
	if field == null and not field_path.is_empty():
		field = get_node(field_path)
	if units.is_empty():
		_spawn_armies()


func _process(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= TICK_TIME and steps < 5:
		_accum -= TICK_TIME
		_step()
		steps += 1


## How far we are between the last tick and the next (0-1), for smoothing.
func tick_fraction() -> float:
	return clampf(_accum / TICK_TIME, 0.0, 1.0)


## Runs `count` ticks immediately (used by tests).
func step_ticks(count: int) -> void:
	for i in count:
		_step()


func get_unit(id: int) -> Dictionary:
	return _by_id.get(id, {})


## Map position (x, z) of a unit at the latest tick.
func unit_ground(id: int) -> Vector2:
	var u: Dictionary = get_unit(id)
	return Vector2(u.x, u.z) / float(SCALE)


## Orders units to move to a ground point. Takes effect COMMAND_DELAY ticks
## from now. The point is turned into whole sim units right here, which is
## exactly what would be sent to the other player online.
func command_move(ids: Array, ground: Vector3) -> void:
	_queue({
		"type": "move",
		"ids": ids.duplicate(),
		"x": roundi(ground.x * SCALE),
		"z": roundi(ground.z * SCALE),
	})


func has_pending_commands() -> bool:
	return not _pending.is_empty()


## The walkable grid (null if there's no island, e.g. in some tests).
func nav():
	if _nav == null and field != null:
		var key: int = field.get_instance_id()
		if not _nav_cache.has(key):
			field.build()
			_nav_cache[key] = NavGrid.new(field, int(field.map_size.x))
		_nav = _nav_cache[key]
	return _nav


# --- Simulation ----------------------------------------------------------------

func _queue(command: Dictionary) -> void:
	var at: int = tick + COMMAND_DELAY
	if not _pending.has(at):
		_pending[at] = []
	_pending[at].append(command)


func _step() -> void:
	for command in _pending.get(tick, []):
		_apply(command)
	_pending.erase(tick)
	for u in units:
		u.px = u.x
		u.pz = u.z
		if u.moving:
			_move(u)
	for pass_index in PUSH_PASSES:
		_separate()
	tick += 1
	ticked.emit()


func _apply(command: Dictionary) -> void:
	match command.type:
		"move":
			_apply_move(command)


## Spreads the group into a square formation around the target point.
func _apply_move(command: Dictionary) -> void:
	var ids: Array = command.ids.duplicate()
	ids.sort()  # same order on every device
	var group: Array = []
	for id in ids:
		if _by_id.has(id):
			group.append(_by_id[id])
	var n: int = group.size()
	if n == 0:
		return
	var cols := 1
	while cols * cols < n:
		cols += 1
	var rows: int = (n + cols - 1) / cols
	for i in n:
		var u: Dictionary = group[i]
		var c: int = i % cols
		var r: int = i / cols
		var tx: int = command.x + (c * 2 - (cols - 1)) * SPACING / 2
		var tz: int = command.z + (r * 2 - (rows - 1)) * SPACING / 2
		_route(u, tx, tz)


## Plans a unit's way to (tx, tz) around lakes, forests and the like. If the
## spot itself is blocked (e.g. in a lake), it goes to the nearest open spot.
func _route(u: Dictionary, tx: int, tz: int) -> void:
	var grid = nav()
	var path: Array = [Vector2i(tx, tz)] if grid == null else grid.find_route(u.x, u.z, tx, tz)
	u.path = path
	u.moving = not path.is_empty()
	if u.moving:
		u.tx = path[path.size() - 1].x
		u.tz = path[path.size() - 1].y


## Walks towards the next waypoint; on reaching it, moves on to the next.
func _move(u: Dictionary) -> void:
	var path: Array = u.path
	if path.is_empty():
		u.moving = false
		return
	var next: Vector2i = path[0]
	var dx: int = next.x - u.x
	var dz: int = next.y - u.z
	var dist: int = _isqrt(dx * dx + dz * dz)
	var speed: int = SPEED[u.kind]
	if dist <= speed:
		u.x = next.x
		u.z = next.y
		path.pop_front()
		if path.is_empty():
			u.moving = false
	else:
		u.x += dx * speed / dist
		u.z += dz * speed / dist


## Pushes overlapping units apart (half each), never into blocked ground.
## A walking unit whose spot is taken by someone already standing there
## stops close by instead of jostling forever.
## Whole numbers and a fixed order (by id), so every device agrees.
func _separate() -> void:
	var min_dist: int = RADIUS * 2
	var buckets := _buckets(min_dist)
	var n: int = units.size()
	for i in n:
		var a: Dictionary = units[i]
		var cell := Vector2i(a.x / min_dist, a.z / min_dist)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				for j in buckets.get(cell + Vector2i(ox, oy), []):
					if j <= i:
						continue  # each pair once
					_push_apart(a, units[j], min_dist)
	for u in units:
		if u.moving and u.path.size() == 1:
			_stop_if_spot_taken(u, min_dist)


## Unit indexes grouped by square cells of `size`, for nearby lookups.
func _buckets(size: int) -> Dictionary:
	var buckets := {}
	for i in units.size():
		var u: Dictionary = units[i]
		var cell := Vector2i(u.x / size, u.z / size)
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(i)
	return buckets


func _push_apart(a: Dictionary, b: Dictionary, min_dist: int) -> void:
	var dx: int = b.x - a.x
	var dz: int = b.z - a.z
	if absi(dx) >= min_dist or absi(dz) >= min_dist:
		return
	var d2: int = dx * dx + dz * dz
	if d2 >= min_dist * min_dist:
		return
	var d: int = _isqrt(d2)
	if d == 0:
		# Exactly on top of each other: split sideways, by id.
		dx = 1 if a.id < b.id else -1
		dz = 0
		d = 1
	var overlap: int = min_dist - d
	# A unit standing still gives way more than one that's walking.
	var share_a: int = overlap / 2
	if a.moving and not b.moving:
		share_a = overlap / 4
	elif b.moving and not a.moving:
		share_a = overlap - overlap / 4
	var share_b: int = overlap - share_a
	_nudge(a, -dx * share_a / d, -dz * share_a / d)
	_nudge(b, dx * share_b / d, dz * share_b / d)


## Moves a unit by (dx, dz) unless that would put it on blocked ground.
func _nudge(u: Dictionary, dx: int, dz: int) -> void:
	if dx == 0 and dz == 0:
		return
	var nx: int = u.x + dx
	var nz: int = u.z + dz
	var grid = nav()
	if grid != null and not grid.is_walkable_cell(grid.cell_of(nx, nz)):
		return
	u.x = nx
	u.z = nz


func _stop_if_spot_taken(u: Dictionary, min_dist: int) -> void:
	var dx: int = u.tx - u.x
	var dz: int = u.tz - u.z
	if dx * dx + dz * dz > min_dist * min_dist:
		return  # not yet up against the spot
	for other in units:
		if other.id == u.id or other.moving:
			continue
		var ox: int = other.x - u.tx
		var oz: int = other.z - u.tz
		if ox * ox + oz * oz < min_dist * min_dist:
			u.moving = false
			u.path.clear()
			return


## Whole-number square root (same result on every device).
static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


# --- Setup -----------------------------------------------------------------------

## Two armies on opposite sides of the island, mirrored for fairness.
func _spawn_armies() -> void:
	var center := Vector2i(410, 410) * SCALE
	var bases := [center + Vector2i(-150, -40) * SCALE, center + Vector2i(150, 40) * SCALE]
	for team in 2:
		var flip: int = 1 if team == 0 else -1
		for kind in 3:
			for i in UNITS_PER_KIND:
				var offset := Vector2i((i * 2 - (UNITS_PER_KIND - 1)) * 500, (kind - 1) * 1200)
				var at: Vector2i = bases[team] + offset * flip
				_add_unit(team, kind, at)


func _add_unit(team: int, kind: int, at: Vector2i) -> void:
	var u := {
		"id": _next_id, "team": team, "kind": kind,
		"x": at.x, "z": at.y, "px": at.x, "pz": at.y,
		"tx": at.x, "tz": at.y, "moving": false, "path": [],
	}
	_next_id += 1
	units.append(u)
	_by_id[u.id] = u
