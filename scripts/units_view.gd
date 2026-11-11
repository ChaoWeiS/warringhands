extends Node3D
## Draws the units from the simulation: flat 2D sprites standing on the 3D
## world (always facing the camera), with soft blob shadows, a selection
## ring, and a marker where a move order was given.
##
## It only reads the sim and smooths positions between ticks. Placeholder
## look until real hand sprites exist: a team-coloured disc with an icon
## (lump = rock, sheet = paper, X = scissors).

@export var sim_path: NodePath

const TEAM_COLORS := [Color("#ffb3ba"), Color("#bae1ff")]
const ICON_COLOR := Color("#5a5470")
const RING_COLOR := Color("#ffffff")
const MARKER_COLOR := Color("#fff3b0")
## Height of the sprite's centre above the ground (map units), so its
## bottom just touches the ground.
const SPRITE_HEIGHT := 2.5
const SPRITE_PIXEL_SIZE := 0.07

var sim: Node
var _views: Dictionary = {}  # unit id -> {root, ring}
var _selected: Dictionary = {}
var _textures: Dictionary = {}  # "team:kind" -> texture


func _ready() -> void:
	sim = get_node(sim_path)
	for u in sim.units:
		_make_view(u)
	_update_positions()


func _process(_delta: float) -> void:
	_update_positions()


## Where a unit is drawn right now (centre of its sprite), for picking.
func world_position(id: int) -> Vector3:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return Vector3.ZERO
	return view.root.position + Vector3(0, SPRITE_HEIGHT, 0)


func set_selected(ids: Array) -> void:
	_selected.clear()
	for id in ids:
		_selected[id] = true
	for id in _views:
		_views[id].ring.visible = _selected.has(id)


## A ring that shrinks and fades where a move order was given.
func show_move_marker(ground: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 6.2
	marker.mesh = torus
	var mat := _flat_material(MARKER_COLOR)
	marker.material_override = mat
	marker.position = Vector3(ground.x, 0.6, ground.z)
	add_child(marker)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(0.3, 1, 0.3), 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(marker.queue_free)


func _update_positions() -> void:
	var t: float = sim.tick_fraction()
	var scale_factor: float = float(sim.SCALE)
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			continue
		var x: float = lerpf(u.px, u.x, t) / scale_factor
		var z: float = lerpf(u.pz, u.z, t) / scale_factor
		view.root.position = Vector3(x, 0, z)


func _make_view(u: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)

	var blob := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 2.3
	disc_mesh.bottom_radius = 2.3
	disc_mesh.height = 0.02
	blob.mesh = disc_mesh
	blob.position = Vector3(0, 0.35, 0)
	blob.material_override = _flat_material(Color(0.25, 0.22, 0.35, 0.25))
	root.add_child(blob)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.7
	torus.outer_radius = 3.2
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(0, 0.45, 0)
	ring.material_override = _flat_material(RING_COLOR)
	ring.visible = false
	root.add_child(ring)

	var sprite := Sprite3D.new()
	sprite.texture = _unit_texture(u.team, u.kind)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = SPRITE_PIXEL_SIZE
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.position = Vector3(0, SPRITE_HEIGHT, 0)
	root.add_child(sprite)

	_views[u.id] = {"root": root, "ring": ring}


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0 or color == MARKER_COLOR:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Disc in the team colour with a simple icon for the unit type.
func _unit_texture(team: int, kind: int) -> ImageTexture:
	var key := "%d:%d" % [team, kind]
	if _textures.has(key):
		return _textures[key]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c)
			if d > c.x - 1.0:
				continue
			var color: Color = Color.WHITE if d > c.x - 5.0 else TEAM_COLORS[team]
			if _icon_hit(kind, p - c):
				color = ICON_COLOR
			img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Is point `p` (relative to the disc centre, pixels) part of the icon?
func _icon_hit(kind: int, p: Vector2) -> bool:
	match kind:
		0:  # rock: a lumpy blob
			return p.distance_to(Vector2(-4, 3)) < 11.0 or p.distance_to(Vector2(6, 1)) < 9.0 \
					or p.distance_to(Vector2(1, -6)) < 8.0
		1:  # paper: a sheet with two lines of "writing"
			var inside := absf(p.x) <= 11.0 and absf(p.y) <= 14.0
			var border := inside and (absf(p.x) >= 8.0 or absf(p.y) >= 11.0)
			var lines := absf(p.x) <= 6.0 and (absf(p.y + 3.0) <= 1.2 or absf(p.y - 3.0) <= 1.2)
			return border or lines
		_:  # scissors: two crossed blades
			var on_blade_a := absf(p.x - p.y) <= 3.5 and absf(p.x + p.y) <= 26.0
			var on_blade_b := absf(p.x + p.y) <= 3.5 and absf(p.x - p.y) <= 26.0
			return (on_blade_a or on_blade_b) and p.length() <= 15.0
