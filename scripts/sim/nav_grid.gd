extends RefCounted
## Where ground units can walk, and how to get from A to B.
##
## The map is split into square cells (CELL map units each). A cell is
## walkable if the island says so (not sea, lake, forest, plateau or prop).
## Routes are found with A* over the cells, then smoothed: we skip ahead to
## the furthest cell still in a clear straight line, so units walk in natural
## straight runs instead of zig-zagging cell by cell.
##
## All results are whole numbers (cells, sim units), so every device makes the
## same choices.
## TODO(lockstep): the grid is built from the island's shapes with decimals.
## Before online play, build it once and ship it, or check every device gets
## an identical grid (e.g. compare a checksum when a match starts).

## Map units per cell (whole number).
const CELL := 4
## Sim units per map unit (must match sim.gd).
const SCALE := 100
const SIM_CELL := CELL * SCALE

var size: int = 0
var _walk := PackedByteArray()        # terrain + buildings (1 = walkable)
var _terrain := PackedByteArray()     # terrain only, to restore when a building goes
var _astar := AStarGrid2D.new()


## Builds the grid from the island's shapes (slow-ish; done once per island,
## then each game takes a copy() so its buildings don't leak into others).
func _init(field: Node = null, map_size: int = 0) -> void:
	if field == null:
		return
	size = map_size / CELL
	_walk.resize(size * size)
	for y in size:
		for x in size:
			var centre := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			_walk[y * size + x] = 1 if field.is_walkable(centre) else 0
	_terrain = _walk.duplicate()
	_setup_astar()


## A separate grid with the same terrain (for one game's buildings).
func copy() -> RefCounted:
	var other = get_script().new()
	other.size = size
	other._walk = _terrain.duplicate()
	other._terrain = _terrain.duplicate()  # packed arrays are shared otherwise
	other._setup_astar()
	return other


func _setup_astar() -> void:
	_astar.region = Rect2i(0, 0, size, size)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for i in _walk.size():
		if _walk[i] == 0:
			_astar.set_point_solid(Vector2i(i % size, i / size), true)


## Cells whose centre is within `radius` (sim units) of a point.
func cells_in_circle(cx: int, cz: int, radius: int) -> Array:
	var cells: Array = []
	var c := cell_of(cx, cz)
	var reach: int = radius / SIM_CELL + 1
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			if x < 0 or y < 0 or x >= size or y >= size:
				continue
			var centre := cell_centre(Vector2i(x, y))
			var dx: int = centre.x - cx
			var dz: int = centre.y - cz
			if dx * dx + dz * dz <= radius * radius:
				cells.append(Vector2i(x, y))
	return cells


## True if every cell in the circle is open terrain (no water, trees...).
func circle_is_open(cx: int, cz: int, radius: int) -> bool:
	for cell in cells_in_circle(cx, cz, radius):
		if not is_walkable_cell(cell):
			return false
	return true


## Opens a cell for good (a tree was cut down).
func open_terrain(cell: Vector2i) -> void:
	var i: int = cell.y * size + cell.x
	_terrain[i] = 1
	_walk[i] = 1
	_astar.set_point_solid(cell, false)


## Marks a building's footprint as blocked (or open again when it's gone).
func set_blocked(cx: int, cz: int, radius: int, blocked: bool) -> void:
	for cell in cells_in_circle(cx, cz, radius):
		var i: int = cell.y * size + cell.x
		var open: bool = (not blocked) and _terrain[i] == 1
		_walk[i] = 1 if open else 0
		_astar.set_point_solid(cell, not open)


func is_walkable_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
		return false
	return _walk[cell.y * size + cell.x] == 1


## Cell containing a position in sim units.
func cell_of(x: int, z: int) -> Vector2i:
	return Vector2i(clampi(x / SIM_CELL, 0, size - 1), clampi(z / SIM_CELL, 0, size - 1))


## Centre of a cell, in sim units.
func cell_centre(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * SIM_CELL + SIM_CELL / 2, cell.y * SIM_CELL + SIM_CELL / 2)


## The closest walkable cell (searching outwards in rings), or (-1, -1).
func nearest_walkable(cell: Vector2i, max_radius: int = 60) -> Vector2i:
	if is_walkable_cell(cell):
		return cell
	for r in range(1, max_radius + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1 << 30
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # only the ring
				var c := cell + Vector2i(dx, dy)
				var d: int = dx * dx + dy * dy
				if d < best_d and is_walkable_cell(c):
					best = c
					best_d = d
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Waypoints (sim units) from one position to another, ending exactly at
## the destination if it's walkable, otherwise at the nearest walkable spot.
## Empty if there's no way there.
func find_route(from_x: int, from_z: int, to_x: int, to_z: int) -> Array:
	var start := nearest_walkable(cell_of(from_x, from_z))
	var goal_cell := cell_of(to_x, to_z)
	var goal := nearest_walkable(goal_cell)
	if start.x < 0 or goal.x < 0:
		return []
	var end_point: Vector2i = Vector2i(to_x, to_z) if goal == goal_cell else cell_centre(goal)
	if start == goal:
		return [end_point]
	var cells: Array = _astar.get_id_path(start, goal)
	if cells.is_empty():
		return []
	var route: Array = []
	for cell in _smooth(cells):
		route.append(cell_centre(cell))
	route[route.size() - 1] = end_point
	return route


## Keeps only the turning points: from each point, jump to the furthest
## later cell that can be reached in a clear straight line.
func _smooth(cells: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < cells.size() - 1:
		var j: int = cells.size() - 1
		while j > i + 1 and not _clear_line(cells[i], cells[j]):
			j -= 1
		out.append(cells[j])
		i = j
	return out


## True if every cell a straight line between two cell centres touches is
## walkable (checked with whole numbers; also blocks squeezing through
## diagonal corners).
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if b.x > a.x else -1
	var sy: int = 1 if b.y > a.y else -1
	var x: int = a.x
	var y: int = a.y
	var err: int = dx - dy
	var steps: int = dx + dy
	for k in steps:
		var e2: int = 2 * err
		if e2 > -dy and e2 < dx:
			# Diagonal step: both side cells must be open too.
			if not is_walkable_cell(Vector2i(x + sx, y)) or not is_walkable_cell(Vector2i(x, y + sy)):
				return false
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		if not is_walkable_cell(Vector2i(x, y)):
			return false
		if x == b.x and y == b.y:
			break
	return true
