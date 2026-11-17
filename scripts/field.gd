extends Node3D
## Battlefield in 2.5D: a pastel 3D island in the sea, with lakes, forests,
## raised plateaus and stone / wood / metal resource spots. Units are drawn
## by units_view.gd.
##
## Every feature is placed twice, mirrored through the island's centre, so
## both players get the same terrain. `is_walkable()` tells the pathfinding
## (scripts/sim/nav_grid.gd) where ground units can go.
##
## Ground positions are 2D (x, z). Game logic will work on that flat plane;
## only the visuals are 3D. The coastline is built from fixed numbers so every
## device builds exactly the same island (needed for lockstep multiplayer).

## Whole world on the ground plane (x, z), sea included.
@export var map_size: Vector2 = Vector2(820, 820)
## Average island radius.
@export var island_radius: float = 330.0
## Points on the coastline (more = smoother).
@export var coast_points: int = 180

# Pastel palette
const SKY := Color("#a9d6eb")
const DEEP_SEA := Color("#5386c1")
const SHALLOW_SEA := Color("#97cbd6")
const SAND := Color("#f0e4c4")
const CLIFF := Color("#d4bf93")
const GRASS := Color("#c8e0b7")
const GRASS_DARK := Color("#99c184")
const STONE := Color("#cbc5da")
const TRUNK := Color("#d9b48f")
const LEAVES := Color("#f6c3d8")
const METAL := Color("#a9e7e2")
const LAKE := Color("#a3d5ea")
const LAKE_DEEP := Color("#8cc3dd")
const PLATEAU_TOP := Color("#a8d493")
const HILLSIDE := Color("#88bd6f")
const CROWNS := [Color("#b8e0a0"), Color("#a6d68f"), Color("#cfe8b4"), Color("#b8e0a0"), Color("#f6c3d8")]

## Which map (scripts/maps.gd); empty = MatchSetup.map. The layout below
## comes from it: coastline wobble, lakes, forests, plateaus and resource
## spots, as offsets from the island centre, each also placed mirrored
## (turned 180° around the centre) for the other side.
var map_id := ""
var COAST_WAVES: Array = []
var LAKES: Array = []
var FORESTS: Array = []
var PLATEAUS: Array = []
const PLATEAU_HEIGHT := 5.0
## Hills: plateaus you can climb have hillsides (the map says where): broad
## grassy slopes easing down from the edge to the ground over HILLSIDE_WIDTH
## (steepening into cliff at their ends); the rest of the edge is cliff
## (CLIFF_BAND wide, blocked). A level 2 tier sits on a level 1 hill (twice
## as high), its hillsides coming down onto the lower top. Plateaus without
## hillsides are solid scenery.
const HILLSIDE_WIDTH := 24.0
const HILLSIDE_WIDTH_TIER := 12.0
## A hillside's default span round the hill (degrees), and how far at each
## end it steepens into cliff.
const HILLSIDE_SPAN := 70.0
const HILLSIDE_TAPER := 18.0
## Gentle enough to walk: this share of the full width or more.
const WALKABLE_SLOPE := 0.55
const CLIFF_BAND := 3.0
# Shape wobble for lakes and plateaus (even frequencies only).
const BLOB_WAVES := [[2, 0.12, 0.4], [4, 0.08, 1.7], [6, 0.05, 3.1]]

## Room kept around obstacles and the shore so units don't clip into them.
const UNIT_CLEARANCE := 3.0
## Trunk size of a forest tree (map units).
const TREE_RADIUS := 3.5
const SHORE_CLEARANCE := 6.0

# Resource spots as offsets from the island centre (already listed for
# both sides in the map, or mirrored here: see _load_map).
var STONES: Array = []
var WOODS: Array = []
var METALS: Array = []
## Team 0's HQ and army start (offsets; team 1's are mirrored).
var hq_offset := Vector2i(-200, -30)
var army_offset := Vector2i(-150, -40)


var coastline: PackedVector2Array = PackedVector2Array()
var lakes: Array = []      # PackedVector2Array outlines
var plateaus: Array = []   # PackedVector2Array outlines
var forests: Array = []    # {center, radius, trees: Array[Vector2]}
## Ramps up the plateaus: {plateau (index), edge: Vector2 (top of the ramp,
## on the cliff), dir: Vector2 (downhill), half_width, length}.
var ramps: Array = []
## Indices (in `plateaus`) of the ones with ramps.
var climbable: Array = []
## Per plateau (same order as `plateaus`): {level, height, base}.
var plateau_info: Array = []
var _plateau_tops: Array = []   # climbable plateaus shrunk by CLIFF_BAND: walkable
var _plateau_outer: Array = []  # plateaus grown by UNIT_CLEARANCE: cliff + top

# Shapes ground units can't enter, already grown by UNIT_CLEARANCE.
var _blocked_polys: Array = []    # {poly, box}
var _blocked_circles: Array = []  # {center, radius}
var _walk_coast := PackedVector2Array()
var _built := false


func _ready() -> void:
	build()
	_build_environment()
	_build_sea()
	_build_island()
	_build_terrain()


## Works out the island and its terrain. Safe to call more than once; the
## pathfinding calls it if it needs the terrain before this node is ready.
func build() -> void:
	if _built:
		return
	_built = true
	_load_map()
	coastline = _build_coastline()
	_walk_coast = _offset(coastline, -SHORE_CLEARANCE)
	var c := get_center()
	for lake in LAKES:
		for poly in _mirrored_blob(lake[0], lake[1], lake[2], lake[3]):
			lakes.append(poly)
			_block_poly(poly)
	for plateau in PLATEAUS:
		var blobs: Array = _mirrored_blob(plateau[0], plateau[1], plateau[2], plateau[3])
		var angles: Array = plateau[4] if plateau.size() > 4 else []
		var level: int = plateau[5] if plateau.size() > 5 else 1
		for i in blobs.size():
			var poly: PackedVector2Array = blobs[i]
			plateaus.append(poly)
			plateau_info.append({"level": level, "height": PLATEAU_HEIGHT * level,
					"base": PLATEAU_HEIGHT * (level - 1)})
			if angles.is_empty():
				_block_poly(poly)  # scenery: can't be climbed
				continue
			climbable.append(plateaus.size() - 1)
			_plateau_tops.append(_offset(poly, -CLIFF_BAND))
			_plateau_outer.append(_offset(poly, UNIT_CLEARANCE))
			# Each hillside listed (degrees round the hill, or {"at", "span"}):
			# one there and one on the far side, all turned with the twin.
			var arcs: Array = []
			for spec in angles:
				var at: float = spec if spec is float or spec is int else spec.at
				var span: float = HILLSIDE_SPAN if spec is float or spec is int else spec.get("span", HILLSIDE_SPAN)
				for way in [at, at + 180.0]:
					var turned: float = fposmod(way if i == 0 else way + 180.0, 360.0)
					if not arcs.any(func(o): return absf(angle_difference(o[0], deg_to_rad(turned))) < 0.01):
						arcs.append([deg_to_rad(turned), deg_to_rad(span) * 0.5])
			var info: Dictionary = plateau_info[plateau_info.size() - 1]
			var width: float = HILLSIDE_WIDTH_TIER if info.level > 1 else HILLSIDE_WIDTH
			var middle: Vector2 = _poly_center(poly)
			var reach: float = 0.0
			for q in poly:
				reach = maxf(reach, q.distance_to(middle))
			ramps.append({"plateau": plateaus.size() - 1, "poly": poly, "center": middle,
					"top": info.height, "base": info.base, "width": width, "arcs": arcs,
					"reach": reach + width + 2.0})
	for forest in FORESTS:
		var trees := _forest_trees(c + forest[0], forest[1], forest[2])
		var mirrored: Array = []
		for t in trees:
			mirrored.append(2.0 * c - t)
		forests.append({"center": c + forest[0], "radius": forest[1], "trees": trees})
		forests.append({"center": c - forest[0], "radius": forest[1], "trees": mirrored})
		for t in trees + mirrored:
			_blocked_circles.append({"center": t, "radius": TREE_RADIUS + UNIT_CLEARANCE, "tree": true})
	for spot in STONES:
		_blocked_circles.append({"center": c + spot, "radius": 13.0 + UNIT_CLEARANCE})
	for spot in WOODS:
		_blocked_circles.append({"center": c + spot, "radius": 16.0 + UNIT_CLEARANCE})
	for spot in METALS:
		_blocked_circles.append({"center": c + spot, "radius": 5.0 + UNIT_CLEARANCE})


func _load_map() -> void:
	var MatchSetup = load("res://scripts/match_setup.gd")
	if map_id == "":
		map_id = MatchSetup.map
	var m: Dictionary = load("res://scripts/maps.gd").get_map(map_id)
	MatchSetup.built_map = map_id
	island_radius = m.radius
	COAST_WAVES = m.coast
	LAKES = m.lakes
	FORESTS = m.forests
	PLATEAUS = m.plateaus
	hq_offset = m.hq
	army_offset = m.army
	# Resource spots: every one listed gets its mirrored twin too (unless the
	# map lists both already, as the first map does).
	STONES = _with_twins(m.stones)
	WOODS = _with_twins(m.woods)
	METALS = _with_twins(m.metals)


func _with_twins(spots: Array) -> Array:
	var out: Array = []
	for p in spots:
		if not out.has(p):
			out.append(p)
		if not out.has(-p) and not spots.has(-p):
			out.append(-p)
	return out


## No tree here? The cliff edges of climbable hills, their steep hillside
## ends, and the whole of scenery plateaus. (Tops and gentle hillsides are
## fine: trees grow there like on the grassland.)
func _on_plateau_or_ramp(p: Vector2, margin: float) -> bool:
	for i in plateaus.size():
		var poly: PackedVector2Array = plateaus[i]
		if not Geometry2D.is_point_in_polygon(p, _offset(poly, UNIT_CLEARANCE + margin)):
			continue
		if not climbable.has(i):
			return true  # scenery
		if not Geometry2D.is_point_in_polygon(p, _offset(poly, -CLIFF_BAND - margin)) \
				and _gentleness(p) < WALKABLE_SLOPE:
			return true  # on its cliff edge
	var hs: Dictionary = hillside_at(p)
	if not hs.is_empty() and hs.w < WALKABLE_SLOPE + 0.1:
		return true  # too steep
	return false


## Where a ray from the middle of a shape in direction `dir` leaves it.
func _edge_point(poly: PackedVector2Array, dir: Vector2) -> Vector2:
	var c: Vector2 = _poly_center(poly)
	var far: Vector2 = c + dir * 1000.0
	for i in poly.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(c, far, poly[i], poly[(i + 1) % poly.size()])
		if hit != null:
			return hit
	return c


## How much of a hillside the direction from hill `h`'s middle towards `p`
## is on: 1 well inside one, easing to 0 at its ends, 0 on the cliffs.
static func _arc_weight(h: Dictionary, p: Vector2) -> float:
	var ang: float = (p - h.center).angle()
	var best := 0.0
	for arc in h.arcs:
		var off: float = absf(angle_difference(arc[0], ang))
		var taper: float = deg_to_rad(HILLSIDE_TAPER)
		if off <= arc[1] - taper:
			return 1.0
		if off < arc[1]:
			var x: float = (arc[1] - off) / taper
			best = maxf(best, x * x * (3.0 - 2.0 * x))
	return best


## Where the hill's edge is, straight out from its middle towards `p`.
func _rim(h: Dictionary, p: Vector2) -> Vector2:
	return _edge_point(h.poly, (p - h.center).normalized())


## The hillside a point outside a hill is on: {hill, w (gentleness 0..1),
## d (how far out from the edge), width (of the slope there), height}, or
## {} (not on one). The slope eases down from the top at the edge to the
## base `width` out.
func hillside_at(p: Vector2) -> Dictionary:
	var found := {}
	for h in ramps:
		if p.distance_to(h.center) > h.reach:
			continue
		if Geometry2D.is_point_in_polygon(p, h.poly):
			continue
		var w: float = _arc_weight(h, p)
		if w <= 0.0:
			continue
		var rim: Vector2 = _rim(h, p)
		var d: float = p.distance_to(h.center) - rim.distance_to(h.center)
		var width: float = h.width * w
		if d < 0.0 or d >= width:
			continue
		var height: float = lerpf(h.base, h.top, 0.5 + 0.5 * cos(PI * d / width))
		if found.is_empty() or height > found.height:
			found = {"hill": h, "w": w, "d": d, "width": width, "height": height}
	return found


## On the steep side of a hillside (where it narrows into cliff), out to
## the hillside's full width: you can't walk there, so the gentle part is
## only reached from the top or across its foot.
func _on_flank(p: Vector2) -> bool:
	for h in ramps:
		if p.distance_to(h.center) > h.reach:
			continue
		var w: float = _arc_weight(h, p)
		if w <= 0.0 or w >= WALKABLE_SLOPE:
			continue
		if Geometry2D.is_point_in_polygon(p, h.poly):
			continue
		var d: float = p.distance_to(h.center) - _rim(h, p).distance_to(h.center)
		if d >= 0.0 and d < h.width:
			return true
	return false


## How gentle the hill edge is at `p` (on or near a climbable hill's edge):
## the hillside weight in that direction, 0 on cliffs.
func _gentleness(p: Vector2) -> float:
	var g := 0.0
	for h in ramps:
		if p.distance_to(h.center) <= h.reach:
			g = maxf(g, _arc_weight(h, p))
	return g


## On a hillside gentle enough to walk (returns its hill index), or -1.
func ramp_at(p: Vector2) -> int:
	var hs: Dictionary = hillside_at(p)
	if hs.is_empty() or hs.w < WALKABLE_SLOPE:
		return -1
	return hs.hill.plateau


## Where a hillside (hill `h`, arc `arc`) meets the ground: a point just
## beyond its foot, and its base level there.
func hillside_foot(h: Dictionary, arc: Array) -> Vector2:
	var dir := Vector2.from_angle(arc[0])
	var rim: Vector2 = _edge_point(h.poly, dir)
	return rim + dir * (h.width + 3.0)


## Height of the ground (map units): a hill top is PLATEAU_HEIGHT per
## level up, hillsides ease down from there to the hill's base, everything
## else is 0.
func height_at(p: Vector2) -> float:
	build()
	var h := 0.0
	for i in plateaus.size():
		if plateau_info[i].height > h and Geometry2D.is_point_in_polygon(p, plateaus[i]):
			h = plateau_info[i].height
	var hs: Dictionary = hillside_at(p)
	if not hs.is_empty():
		h = maxf(h, hs.height)
	return h


## Is this point up on a plateau or a hillside?
func is_raised(p: Vector2) -> bool:
	return height_at(p) > 0.01


## Is this point on a hillside, or on a hill's cliff edge? (No building.)
func is_slope_or_edge(p: Vector2) -> bool:
	if not hillside_at(p).is_empty():
		return true
	for i in _plateau_outer.size():
		if Geometry2D.is_point_in_polygon(p, _plateau_outer[i]) \
				and not Geometry2D.is_point_in_polygon(p, _plateau_tops[i]):
			return true
	return false


## On a hillside you can walk (for tests and the view).
func on_slope(p: Vector2) -> bool:
	return ramp_at(p) >= 0


## Resource spots on both sides: [{res, pos, radius}] (map units).
## res: 0 stone, 1 wood, 2 metal (matching rock, paper, scissors).
func resource_spots() -> Array:
	build()
	var c := get_center()
	var spots: Array = []
	for spot in STONES:
		spots.append({"res": 0, "pos": c + spot, "radius": 13.0})
	for spot in WOODS:
		spots.append({"res": 1, "pos": c + spot, "radius": 16.0})
	for spot in METALS:
		spots.append({"res": 2, "pos": c + spot, "radius": 5.0})
	# Every forest tree can be cut for wood.
	for forest in forests:
		for t in forest.trees:
			spots.append({"res": 1, "pos": t, "radius": TREE_RADIUS, "tree": true})
	return spots


## Can a ground unit stand here? (On the island, away from the shore, and
## not in a lake, forest tree, plateau or resource prop.) Trees in
## `cut_trees` (positions as keys) have been cut down and no longer block.
func is_walkable(p: Vector2, cut_trees: Dictionary = {}) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _walk_coast):
		return false
	for circle in _blocked_circles:
		if p.distance_squared_to(circle.center) < circle.radius * circle.radius:
			if circle.has("tree") and cut_trees.has(circle.center):
				continue
			return false
	for blocked in _blocked_polys:
		if blocked.box.has_point(p) and Geometry2D.is_point_in_polygon(p, blocked.poly):
			return false
	# Steep hillside ends and their flanks: no.
	if _on_flank(p):
		return false
	# Hills: the top is open, the cliff edge isn't (except where a gentle
	# hillside comes up to it).
	for i in _plateau_outer.size():
		if Geometry2D.is_point_in_polygon(p, _plateau_outer[i]) \
				and not Geometry2D.is_point_in_polygon(p, _plateau_tops[i]):
			if _gentleness(p) < WALKABLE_SLOPE:
				return false
	return true


## True if a ground point (x, z) is on land. Ground units will use this to
## stay out of the sea; flyers can ignore it.
func is_on_land(ground_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(ground_point, coastline)


func get_center() -> Vector2:
	return map_size * 0.5


# --- Terrain shapes -----------------------------------------------------------

func _block_poly(poly: PackedVector2Array) -> void:
	var grown := _offset(poly, UNIT_CLEARANCE)
	var box := Rect2(grown[0], Vector2.ZERO)
	for p in grown:
		box = box.expand(p)
	_blocked_polys.append({"poly": grown, "box": box})


## A wobbly oval at `offset` from the centre, plus its mirrored twin
## (just one if it sits on the centre, since it's its own mirror).
func _mirrored_blob(offset: Vector2, rx: float, rz: float, rot: float) -> Array:
	var c := get_center()
	var blob := PackedVector2Array()
	for i in 48:
		var a: float = TAU * i / 48.0
		var wobble: float = 1.0
		for wave in BLOB_WAVES:
			wobble += wave[1] * sin(wave[0] * a + wave[2])
		var local := Vector2(cos(a) * rx, sin(a) * rz) * wobble
		blob.append(c + offset + local.rotated(rot))
	if offset == Vector2.ZERO:
		return [blob]
	var twin := PackedVector2Array()
	for p in blob:
		twin.append(2.0 * c - p)
	return [blob, twin]


## Tree positions in a forest, from a fixed seed (same on every device).
func _forest_trees(center: Vector2, radius: float, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees: Array = []
	var inside_shore := _offset(coastline, -12.0)
	for attempt in 400:
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * (radius - 3.0)
		var p: Vector2 = center + Vector2.from_angle(a) * d
		if not Geometry2D.is_point_in_polygon(p, inside_shore):
			continue
		if _on_plateau_or_ramp(p, 4.0):
			continue  # trees stay off the plateaus and their ramps
		var crowded := false
		for t in trees:
			if p.distance_to(t) < 7.0:
				crowded = true
				break
		if not crowded:
			trees.append(p)
	return trees


# --- Building the world ----------------------------------------------------

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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.5
	# Real-time shadows are off: in the Compatibility renderer they wash the
	# pastel colours out to white, and they're costly on phones. Units get
	# soft blob shadows instead (see units_view.gd), like Ragnarok Online.
	sun.shadow_enabled = false
	add_child(sun)


## How far the shore is moved out (+) or in (-) from the coastline at
## angle `a` (radians round the island), for `which` edge: the waterline
## ("water") or where grass starts ("grass"). Looks only: walking still
## follows the coastline.
func _shore_shift(a: float, which: String) -> float:
	if which == "water":
		# Coves and spits: from 3 in to 7 out.
		return 2.0 + 3.0 * sin(3.0 * a + 0.7) + 2.0 * sin(7.0 * a + 2.1)
	# Grass: narrow sand in places, broad beaches in others (4 to 30 in).
	var wide: float = 0.5 + 0.5 * sin(2.0 * a + 4.0) * sin(5.0 * a + 1.3)
	return -(4.0 + 22.0 * wide * wide + 3.0 * sin(11.0 * a))


## The coastline pushed out (or in) by `shift(angle) + extra`, straight
## away from the island centre (so rings never fold over themselves).
func _shore_ring(which: String, extra: float = 0.0) -> PackedVector2Array:
	var c := get_center()
	var ring := PackedVector2Array()
	for p in coastline:
		var d: Vector2 = p - c
		var a: float = d.angle()
		var shift: float = (_shore_shift(a, which) if which != "" else 0.0) + extra
		ring.append(c + d.normalized() * (d.length() + shift))
	return ring


const SEA_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;
uniform vec4 foam : source_color = vec4(1.0, 0.99, 0.95, 1.0);
varying float dist;
varying float along;
void vertex() {
	dist = UV.y;
	along = UV.x;
}
void fragment() {
	vec3 c = COLOR.rgb;
	float t = TIME;
	// Foam at the waterline, lapping in and out.
	float lap = 1.2 + 1.3 * sin(t * 0.9 + along * 0.11) + 0.5 * sin(t * 1.7 + along * 0.31);
	float edge = 1.0 - smoothstep(lap, lap + 1.6, dist);
	// Soft wave lines rolling in towards the beach.
	float w = fract(dist / 10.0 + t * 0.10 + 0.25 * sin(along * 0.045));
	float line = smoothstep(0.0, 0.05, w) * (1.0 - smoothstep(0.05, 0.16, w));
	line *= (1.0 - smoothstep(5.0, 34.0, dist)) * 0.4;
	// A little sparkle further out.
	float glint = pow(max(0.0, sin(along * 0.37 + dist * 0.9 + t * 1.3) * sin(along * 0.23 - dist * 0.6 - t * 0.7)), 60.0);
	glint *= smoothstep(12.0, 40.0, dist) * 0.3;
	ALBEDO = mix(c, foam.rgb, clamp(edge * 0.9 + line + glint, 0.0, 1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Clear near the beach, so the sand shows through.
	ALPHA = mix(0.45, 1.0, smoothstep(0.0, 10.0, dist)) + edge * 0.5;
}
"""


## The sea: rings out from the waterline, shallow turquoise by the beach
## fading to deep blue, with foam, rolling waves and a few glints.
func _build_sea() -> void:
	var c := get_center()
	var water: PackedVector2Array = _shore_ring("water")
	# Distance out from the waterline for each ring, and its colour.
	var steps := [0.0, 2.0, 5.0, 9.0, 14.0, 20.0, 28.0, 38.0, 52.0, 70.0, 95.0, map_size.x * 3.0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n: int = water.size()
	var along := PackedFloat32Array()
	var total := 0.0
	for i in n + 1:
		along.append(total)
		total += water[i % n].distance_to(water[(i + 1) % n])
	var rows: Array = []
	for d in steps:
		var row: Array = []
		for i in n + 1:
			var p: Vector2 = water[i % n]
			var out: Vector2 = (p - c).normalized()
			row.append(p + out * d)
		rows.append(row)
	for r in steps.size() - 1:
		for i in n:
			for tri in [[[r, i], [r + 1, i], [r + 1, i + 1]], [[r, i], [r + 1, i + 1], [r, i + 1]]]:
				var pts: Array = tri.map(func(v): return Vector3(rows[v[0]][v[1]].x, 0.05, rows[v[0]][v[1]].y))
				for q in _front_up(pts):
					var v: Array = tri[pts.find(q)]
					var d: float = steps[v[0]]
					st.set_color(_sea_colour(d))
					st.set_uv(Vector2(along[v[1]], d))
					st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var shader := Shader.new()
	shader.code = SEA_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _sea_colour(d: float) -> Color:
	var shallow: Color = SHALLOW_SEA.lerp(Color("#bfe9e4"), 0.35)
	if d < 30.0:
		return shallow.lerp(SHALLOW_SEA, smoothstep(0.0, 30.0, d))
	return SHALLOW_SEA.lerp(DEEP_SEA, smoothstep(30.0, 110.0, d))


## The island: sand from under the water up to a wandering grass edge
## (wet and darker at the water), then grass.
func _build_island() -> void:
	var c := get_center()
	var outer: PackedVector2Array = _shore_ring("water", 14.0)
	_add_flat(outer, -0.6, SAND.darkened(0.12))
	_add_skirt(outer, -0.6, -3.0, SAND.darkened(0.2))
	# Wet sand by the water, drying towards the grass.
	var rows: Array = []
	for k in 5:
		var t: float = k / 4.0
		var row: Array = []
		var water: PackedVector2Array = _shore_ring("water", lerpf(10.0, -3.0, t))
		for i in water.size() + 1:
			var p: Vector2 = water[i % water.size()]
			row.append(Vector3(p.x, lerpf(-0.6, 0.0, t), p.y))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in rows.size() - 1:
		for i in rows[r].size() - 1:
			for tri in [[[r, i], [r + 1, i], [r + 1, i + 1]], [[r, i], [r + 1, i + 1], [r, i + 1]]]:
				var pts: Array = tri.map(func(v): return rows[v[0]][v[1]])
				for q in _front_up(pts):
					var v: Array = tri[pts.find(q)]
					st.set_color(SAND.darkened(lerpf(0.12, 0.0, v[0] / 4.0)))
					st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mi.material_override = m
	add_child(mi)
	_add_flat(_shore_ring("water", -3.0), 0.0, SAND)
	_add_flat(_shore_ring("grass"), 0.15, GRASS)
	# Grass darkens gradually inland (no hard line).
	var fade_rows: Array = []
	var cols: Array = []
	for k in INLAND_FADE.size():
		var ring: PackedVector2Array = _shore_ring("", -INLAND_FADE[k])
		var row: Array = []
		var col_row: Array = []
		for i in ring.size() + 1:
			var p: Vector2 = ring[i % ring.size()]
			row.append(Vector3(p.x, 0.3, p.y))
			col_row.append(_ground_colour(p))
		fade_rows.append(row)
		cols.append(col_row)
	_strip_mesh(fade_rows, GRASS, cols)
	_add_flat(_shore_ring("", -INLAND_FADE[-1]), 0.3, GRASS_DARK)


func _build_terrain() -> void:
	for lake in lakes:
		_add_flat(_offset(lake, 5.0), 0.36, SAND)
		_add_flat(lake, 0.4, LAKE)
		_add_flat(_offset(lake, -9.0), 0.42, LAKE_DEEP)
	for i in plateaus.size():
		var plateau: PackedVector2Array = plateaus[i]
		var info: Dictionary = plateau_info[i]
		var top_color: Color = PLATEAU_TOP if info.level == 1 else PLATEAU_TOP.lightened(0.18)
		_add_flat(_offset(plateau, 2.5), info.base + (0.34 if info.base == 0.0 else 0.04), CLIFF)
		_add_skirt(plateau, info.height, info.base, CLIFF, _poly_center(plateau))
		_add_flat(plateau, info.height, top_color)
	for hill in ramps:
		_add_hillsides(hill)


## A ramp: a sloped path from the plateau top down to the ground, with its
## sides filled in down to the ground.
func _add_hillsides(h: Dictionary) -> void:
	# Each hillside: rows from the hill's edge (a touch inside, at the top)
	# out to the ground, easing down; the slope narrows (steepens) into the
	# cliff at both ends. Smooth shading, grassy colour.
	var lift: float = 0.45 if h.base == 0.0 else 0.03
	# Colours blend from the hilltop, through the hillside green, into the
	# ground at the foot, with a little unevenness so it looks grown, not
	# built.
	var lower: bool = h.base == 0.0
	var top_col: Color = PLATEAU_TOP if lower else PLATEAU_TOP.lightened(0.18)
	var mid_col: Color = HILLSIDE if lower else HILLSIDE.lerp(PLATEAU_TOP, 0.5)
	for arc in h.arcs:
		var rows: Array = []
		var cols: Array = []
		var steps := 28
		for k in steps + 1:
			var ang: float = arc[0] + lerpf(-arc[1], arc[1], float(k) / steps)
			var dir := Vector2.from_angle(ang)
			var rim: Vector2 = _edge_point(h.poly, dir)
			var w: float = _arc_weight(h, rim + dir)
			var width: float = maxf(h.width * w, 0.4)
			var row: Array = []
			var col_row: Array = []
			var foot_col: Color = _ground_colour(rim + dir * width) if lower else PLATEAU_TOP
			for j in 9:
				var f: float = j / 8.0
				var p: Vector2 = rim + dir * (lerpf(-0.8, width, f))
				var y: float = lerpf(h.base, h.top, 0.5 + 0.5 * cos(PI * clampf(f, 0.0, 1.0)))
				y = h.top + 0.02 if j == 0 else maxf(y, h.base + lift)
				row.append(Vector3(p.x, y, p.y))
				# Top -> hillside green (steepest part) -> the ground below.
				var col: Color = top_col.lerp(mid_col, smoothstep(0.0, 0.45, f)) if f < 0.5 \
						else mid_col.lerp(foot_col, smoothstep(0.5, 1.0, f))
				if j > 0 and j < 8:
					var n: float = sin(p.x * 0.21 + p.y * 0.13) * sin(p.x * 0.07 - p.y * 0.17)
					col = col.lightened(0.05 * n) if n > 0.0 else col.darkened(-0.05 * n)
				col_row.append(col)
			rows.append(row)
			cols.append(col_row)
		_strip_mesh(rows, mid_col, cols)


## How far in from the coast the grass starts darkening, and where it's
## fully dark.
const INLAND_FADE := [45.0, 60.0, 75.0, 90.0, 105.0, 120.0]


## The ground colour at `p`: light grass by the coast, darkening inland.
func _ground_colour(p: Vector2) -> Color:
	var d: Vector2 = p - get_center()
	var a: float = d.angle()
	var wobble: float = 1.0
	for wave in COAST_WAVES:
		wobble += wave[1] * sin(wave[0] * a + wave[2])
	var depth: float = island_radius * wobble - d.length()
	return GRASS.lerp(GRASS_DARK, smoothstep(INLAND_FADE[0], INLAND_FADE[-1], depth))


## The triangle's corners in the order that makes it face up.
static func _up_facing(tri: Array) -> Array:
	var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0])
	return tri if n.y > 0 else [tri[0], tri[2], tri[1]]


## The triangle wound so its front faces up (Godot's front faces are
## clockwise seen from the front), for meshes given an up normal.
static func _front_up(tri: Array) -> Array:
	var up: Array = _up_facing(tri)
	return [up[0], up[2], up[1]]


## A smooth-shaded surface through rows of points (each row across, the
## rows following on).
func _strip_mesh(rows: Array, color: Color, colors: Array = []) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tinted: bool = not colors.is_empty()
	for i in rows.size() - 1:
		var a_row: Array = rows[i]
		var b_row: Array = rows[i + 1]
		for k in a_row.size() - 1:
			var a0: Vector3 = a_row[k]
			var a1: Vector3 = a_row[k + 1]
			var b0: Vector3 = b_row[k]
			var b1: Vector3 = b_row[k + 1]
			var tint := {}
			if tinted:
				tint = {a0: colors[i][k], a1: colors[i][k + 1], b0: colors[i + 1][k], b1: colors[i + 1][k + 1]}
			for v in _up_facing([a0, b1, a1]) + _up_facing([a0, b0, b1]):
				if tinted:
					st.set_color(tint[v])
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _material(Color.WHITE if tinted else color)
	m.vertex_color_use_as_albedo = tinted
	m.vertex_color_is_srgb = tinted
	mi.material_override = m
	add_child(mi)


## Triangles with one colour and normal (drawn from both sides, like the
## rest of the terrain).
func _add_tris(points: Array, normal: Vector3, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(normal)
	for v in points:
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)


func _multimesh(mesh: Mesh, count: int, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mmi


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / poly.size()


# --- Helpers ---------------------------------------------------------------

func _ground(at: Vector2, height: float) -> Vector3:
	return Vector3(at.x, height, at.y)


func _offset(polygon: PackedVector2Array, amount: float) -> PackedVector2Array:
	var shapes: Array = Geometry2D.offset_polygon(polygon, amount, Geometry2D.JOIN_ROUND)
	return shapes[0] if not shapes.is_empty() else polygon


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A flat shape lying on the ground at height `y`.
func _add_flat(polygon: PackedVector2Array, y: float, color: Color) -> void:
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if tris.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for index in tris:
		st.add_vertex(Vector3(polygon[index].x, y, polygon[index].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)


## Vertical band around a shape's edge (island thickness, plateau cliffs).
func _add_skirt(polygon: PackedVector2Array, top: float, bottom: float, color: Color,
		center: Vector2 = Vector2.INF) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if center == Vector2.INF:
		center = get_center()
	var n: int = polygon.size()
	for i in n:
		var p0: Vector2 = polygon[i]
		var p1: Vector2 = polygon[(i + 1) % n]
		var out: Vector2 = ((p0 + p1) * 0.5 - center).normalized()
		st.set_normal(Vector3(out.x, 0, out.y))
		var a := Vector3(p0.x, top, p0.y)
		var b := Vector3(p1.x, top, p1.y)
		var c := Vector3(p1.x, bottom, p1.y)
		var d := Vector3(p0.x, bottom, p0.y)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)
