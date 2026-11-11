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
var _walk := PackedByteArray()
var _astar := AStarGrid2D.new()


func _init(field: Node, map_size: int) -> void:
	size = map_size / CELL
	_walk.resize(size * size)
	_astar.region = Rect2i(0, 0, size, size)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in size:
		for x in size:
			var centre := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			var ok: bool = field.is_walkable(centre)
			_walk[y * size + x] = 1 if ok else 0
			if not ok:
				_astar.set_point_solid(Vector2i(x, y), true)


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
