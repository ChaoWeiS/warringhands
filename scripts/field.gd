extends Node3D
## Battlefield in 2.5D: a pastel 3D island in the sea, with stone / wood /
## metal resource spots. Units are drawn by units_view.gd.
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
const DEEP_SEA := Color("#8ec5e0")
const SHALLOW_SEA := Color("#b9e3f0")
const SAND := Color("#f6e7c1")
const CLIFF := Color("#e8d3a8")
const GRASS := Color("#c3e6ad")
const GRASS_DARK := Color("#addb96")
const STONE := Color("#cbc5da")
const TRUNK := Color("#d9b48f")
const LEAVES := Color("#f6c3d8")
const METAL := Color("#a9e7e2")

# Coastline wobble: [frequency, amplitude, phase]. Only EVEN frequencies, so
# the island looks the same after a 180° turn (fair for two players).
const COAST_WAVES := [
	[2, 0.10, 0.6], [4, 0.07, 2.1], [6, 0.04, 4.0], [8, 0.025, 1.3], [12, 0.012, 5.2],
]

# Resource spots as offsets from the island centre (mirrored for fairness).
const STONES := [Vector2(-170, -170), Vector2(170, 170)]
const WOODS := [Vector2(-170, 170), Vector2(170, -170)]
const METALS := [Vector2(0, -125), Vector2(0, 125), Vector2(-230, 0), Vector2(230, 0)]


var coastline: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	coastline = _build_coastline()
	_build_environment()
	_build_sea()
	_build_island()
	_build_resources()


## True if a ground point (x, z) is on land. Ground units will use this to
## stay out of the sea; flyers can ignore it.
func is_on_land(ground_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(ground_point, coastline)


func get_center() -> Vector2:
	return map_size * 0.5


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


func _build_sea() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = map_size * 6.0
	sea.mesh = plane
	sea.position = Vector3(get_center().x, -2.0, get_center().y)
	sea.material_override = _material(DEEP_SEA)
	add_child(sea)

	_add_flat(_offset(coastline, 22.0), -1.2, SHALLOW_SEA)


func _build_island() -> void:
	var beach: PackedVector2Array = _offset(coastline, 8.0)
	_add_flat(beach, 0.0, SAND)
	_add_skirt(beach, 0.0, -2.5, CLIFF)
	_add_flat(_offset(coastline, -10.0), 0.15, GRASS)
	_add_flat(_offset(coastline, -80.0), 0.3, GRASS_DARK)


func _build_resources() -> void:
	var c := get_center()
	for spot in STONES:
		for i in 3:
			var rock := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 7.0 - i
			sphere.height = 9.0 - i
			sphere.radial_segments = 7
			sphere.rings = 4
			rock.mesh = sphere
			rock.position = _ground(c + spot + Vector2(i * 9 - 9, (i % 2) * 7), 3.0)
			rock.material_override = _material(STONE)
			add_child(rock)
	for spot in WOODS:
		for i in 4:
			_add_tree(c + spot + Vector2((i % 2) * 18 - 9, (i / 2) * 18 - 9))
	for spot in METALS:
		var crystal := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(8, 14, 8)
		crystal.mesh = prism
		crystal.position = _ground(c + spot, 7.3)
		crystal.material_override = _material(METAL)
		add_child(crystal)


func _add_tree(at: Vector2) -> void:
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.6
	cyl.height = 8.0
	trunk.mesh = cyl
	trunk.position = _ground(at, 4.3)
	trunk.material_override = _material(TRUNK)
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 5.5
	ball.height = 9.0
	ball.radial_segments = 10
	ball.rings = 6
	crown.mesh = ball
	crown.position = _ground(at, 11.0)
	crown.material_override = _material(LEAVES)
	add_child(crown)


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


## Vertical band around a shape's edge, so the island has some thickness.
func _add_skirt(polygon: PackedVector2Array, top: float, bottom: float, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := get_center()
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
