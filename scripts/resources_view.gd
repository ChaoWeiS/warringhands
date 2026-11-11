extends Node3D
## Draws the resource spots from the simulation, each clearly unlike the
## scenery around it, with a tinted patch of ground and a floating badge
## (resource colour + amount left). An emptied spot fades away.
##
##   Stone (rocks gather fastest):    a pile of lavender boulders.
##   Wood (papers gather fastest):    a lumber camp: golden trees, a log pile
##                                    and a stump (forests are just scenery).
##   Metal (scissors gather fastest): a cluster of aqua crystals.

const UI := preload("res://scripts/ui_style.gd")

@export var sim_path: NodePath

const STONE := Color("#cbc5da")
const TRUNK := Color("#d9b48f")
const LOG_END := Color("#f3dcb8")
const GOLD_LEAVES := Color("#f5c76e")
const METAL := Color("#a9e7e2")
const METAL_DARK := Color("#7fd0ca")
## Height (map units) of each kind of spot, for its badge and for tapping.
const TOPS := [9.0, 19.0, 15.0]
const BADGE_GAP := 3.0
const FADE := 0.8

var sim: Node
var _views: Dictionary = {}  # node id -> {root, label}


func _ready() -> void:
	sim = get_node(sim_path)
	_sync()


func _process(_delta: float) -> void:
	_sync()


## Top of a spot (map units), for tapping it on screen.
static func top_of(res: int) -> float:
	return TOPS[res]


func _sync() -> void:
	var alive := {}
	for n in sim.nodes:
		alive[n.id] = true
		var view: Dictionary = _views.get(n.id, {})
		if view.is_empty():
			view = _make(n)
			_views[n.id] = view
		var text := str(n.amount)
		if view.label.text != text:
			view.label.text = text
	for id in _views.keys():
		if not alive.has(id):
			_fade_out(_views[id])
			_views.erase(id)


func _make(n: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(n.x / float(sim.SCALE), 0, n.z / float(sim.SCALE))
	add_child(root)
	var radius: float = n.radius / float(sim.SCALE)
	var color: Color = UI.RES_COLORS[n.res]

	# Tinted ground patch, so the spot reads as "something here".
	var patch := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius + 3.0
	disc.bottom_radius = radius + 3.0
	disc.height = 0.02
	disc.radial_segments = 32
	patch.mesh = disc
	patch.position.y = 0.5  # above the inner grass (0.3)
	patch.material_override = _material(Color(color, 0.3), true)
	root.add_child(patch)

	match n.res:
		0: _make_stone(root)
		1: _make_wood(root)
		2: _make_metal(root)

	# Badge: resource dot + amount left, always facing the camera.
	var top: float = TOPS[n.res] + BADGE_GAP
	var icon := Sprite3D.new()
	icon.texture = UI.res_icon(n.res)
	icon.pixel_size = 0.1
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.render_priority = 2
	icon.position = Vector3(-3.0, top, 0)
	root.add_child(icon)
	var label := Label3D.new()
	label.text = str(n.amount)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 2
	label.font_size = 64
	label.pixel_size = 0.05
	label.outline_size = 16
	label.outline_modulate = Color.WHITE
	label.modulate = UI.TEXT_COLOR
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = Vector3(-0.8, top, 0)
	root.add_child(label)
	return {"root": root, "label": label}


func _make_stone(root: Node3D) -> void:
	var boulders := [[Vector2(-5, 1), 6.0], [Vector2(4, -2), 5.0], [Vector2(3, 6), 4.0],
			[Vector2(-3, -7), 3.0], [Vector2(9, 5), 2.2]]
	for b in boulders:
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = b[1]
		sphere.height = b[1] * 1.4
		sphere.radial_segments = 7
		sphere.rings = 4
		rock.mesh = sphere
		rock.position = Vector3(b[0].x, b[1] * 0.5, b[0].y)
		rock.material_override = _material(STONE, false)
		root.add_child(rock)


func _make_wood(root: Node3D) -> void:
	for t in [Vector2(-8, -7), Vector2(8, -9), Vector2(-10, 7)]:
		_tree(root, t)
	# Stump.
	var stump := _cylinder(1.6, 1.9, 2.0, TRUNK)
	stump.position = Vector3(9, 1.0, 8)
	root.add_child(stump)
	# Log pile: three logs with two on top, lying sideways, cut ends showing.
	var logs := [[-2.7, 1.3], [0.0, 1.3], [2.7, 1.3], [-1.35, 3.6], [1.35, 3.6]]
	for l in logs:
		var log := _cylinder(1.35, 1.35, 9.0, TRUNK)
		log.rotation = Vector3(0, 0, PI / 2)
		log.position = Vector3(1, l[1], 3 + l[0])
		root.add_child(log)
		for side in [-1, 1]:
			var cap := _cylinder(1.0, 1.0, 0.1, LOG_END)
			cap.rotation = Vector3(0, 0, PI / 2)
			cap.position = Vector3(1 + side * 4.55, l[1], 3 + l[0])
			root.add_child(cap)


func _make_metal(root: Node3D) -> void:
	var crystals := [[Vector2(0, 0), Vector3(6, 15, 6), 0.0, METAL],
			[Vector2(-4.5, 2.5), Vector3(4.5, 10, 4.5), 0.35, METAL_DARK],
			[Vector2(4.5, 2), Vector3(4, 8, 4), -0.4, METAL],
			[Vector2(1, -4), Vector3(3, 6, 3), 0.2, METAL_DARK]]
	for c in crystals:
		var crystal := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = c[1]
		crystal.mesh = prism
		crystal.rotation = Vector3(0, 0, c[2])
		crystal.position = Vector3(c[0].x, c[1].y * 0.5 - 0.3, c[0].y)
		crystal.material_override = _material(c[3], false)
		root.add_child(crystal)


func _tree(root: Node3D, at: Vector2) -> void:
	var trunk := _cylinder(1.2, 1.6, 8.0, TRUNK)
	trunk.position = Vector3(at.x, 4.0, at.y)
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 5.0
	ball.height = 8.5
	ball.radial_segments = 10
	ball.rings = 6
	crown.mesh = ball
	crown.position = Vector3(at.x, 11.0, at.y)
	crown.material_override = _material(GOLD_LEAVES, false)
	root.add_child(crown)


func _cylinder(top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top
	cyl.bottom_radius = bottom
	cyl.height = height
	cyl.radial_segments = 10
	m.mesh = cyl
	m.material_override = _material(color, false)
	return m


func _fade_out(view: Dictionary) -> void:
	var root: Node3D = view.root
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector3(1.0, 0.05, 1.0), FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(root.queue_free)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
