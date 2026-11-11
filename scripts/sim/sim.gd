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

## Sim units per map unit.
const SCALE := 100
const TICK_RATE := 20
const TICK_TIME := 1.0 / TICK_RATE
## Commands run this many ticks after they're given.
const COMMAND_DELAY := 2
## Gap between units when a group moves together (sim units).
const SPACING := 1000

enum Kind { ROCK, PAPER, SCISSORS }

## Movement per tick, by kind (placeholder numbers until balancing).
const SPEED := [110, 130, 120]
const UNITS_PER_KIND := 4

## The island, for "is this on land?".
@export var field_path: NodePath

var field: Node = null
var tick: int = 0
## Every unit: {id, team, kind, x, z, px, pz, tx, tz, moving}.
## (px, pz) = position at the previous tick, for smooth drawing.
var units: Array = []

var _by_id: Dictionary = {}
var _next_id: int = 1
var _pending: Dictionary = {}  # tick -> Array of commands
var _accum: float = 0.0


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
		u.tx = command.x + (c * 2 - (cols - 1)) * SPACING / 2
		u.tz = command.z + (r * 2 - (rows - 1)) * SPACING / 2
		u.moving = true


func _move(u: Dictionary) -> void:
	var dx: int = u.tx - u.x
	var dz: int = u.tz - u.z
	var dist: int = _isqrt(dx * dx + dz * dz)
	var speed: int = SPEED[u.kind]
	var nx: int
	var nz: int
	var arrived := false
	if dist <= speed:
		nx = u.tx
		nz = u.tz
		arrived = true
	else:
		nx = u.x + dx * speed / dist
		nz = u.z + dz * speed / dist
	# Ground units stop at the shore.
	# TODO(lockstep): the land test uses floats; replace with a whole-number
	# land grid before online play so every device agrees at the coastline.
	if not _on_land(nx, nz):
		u.moving = false
		return
	u.x = nx
	u.z = nz
	if arrived:
		u.moving = false


func _on_land(x: int, z: int) -> bool:
	if field == null:
		return true
	return field.is_on_land(Vector2(x, z) / float(SCALE))


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
		"tx": at.x, "tz": at.y, "moving": false,
	}
	_next_id += 1
	units.append(u)
	_by_id[u.id] = u
