extends Node3D
## Draws the units from the simulation: animated 2D hand sprites standing on
## the 3D world (always facing the camera), Ragnarok-style, with a soft
## team-coloured base under each, a selection ring, and a marker where a move
## order was given.
##
## It only reads the sim and smooths positions between ticks.
##
## Sprites: assets/units/hands.png, cut from art_source/hands_sheet.png by
## tools/cut_hand_sprites.py. 5 frames per row, 128 px cells;
## row = kind * 3 + state (kind: rock, paper, scissors; state: idle, attack, defend).

@export var sim_path: NodePath

const ATLAS := preload("res://assets/units/hands.png")
const CELL := 128
const FRAMES := 5
const STATES := ["idle", "attack", "defend"]
const STATE_FPS := {"idle": 6.0, "attack": 10.0, "defend": 8.0}

## Team colours, used for the base under each unit.
const TEAM_COLORS := [Color("#ff7f9a"), Color("#6fb6ff")]
const RING_COLOR := Color("#ffffff")
const MARKER_COLOR := Color("#fff3b0")
## Map units per sprite pixel (a hand is about 6 map units tall).
const SPRITE_PIXEL_SIZE := 0.06
## Height of the hand's middle above the ground, for picking.
const SPRITE_HEIGHT := 3.0

var sim: Node
var _views: Dictionary = {}  # unit id -> {root, ring, sprite}
var _selected: Dictionary = {}
var _frames_by_kind: Array = []  # SpriteFrames per kind


func _ready() -> void:
	sim = get_node(sim_path)
	for kind in 3:
		_frames_by_kind.append(_build_frames(kind))
	for u in sim.units:
		_make_view(u)
	_update_positions()


func _process(_delta: float) -> void:
	_update_positions()


## Where a unit is drawn right now (middle of its sprite), for picking.
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


## Plays "idle", "attack" or "defend" for a unit (combat will use this).
func set_state(id: int, state: String) -> void:
	var view: Dictionary = _views.get(id, {})
	if not view.is_empty() and view.sprite.animation != state:
		view.sprite.play(state)


## A ring that shrinks and fades where a move order was given.
func show_move_marker(ground: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 6.2
	marker.mesh = torus
	var mat := _flat_material(MARKER_COLOR, true)
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
		# Face the way we're walking (the art faces right).
		if u.x != u.px:
			view.sprite.flip_h = u.x < u.px


func _make_view(u: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)

	# Soft team-coloured base (doubles as the blob shadow).
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.02
	disc.radial_segments = 24
	base.mesh = disc
	base.position = Vector3(0, 0.35, 0)
	var team_color: Color = TEAM_COLORS[u.team]
	base.material_override = _flat_material(Color(team_color, 0.8), true)
	root.add_child(base)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.3
	torus.outer_radius = 3.9
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(0, 0.45, 0)
	ring.material_override = _flat_material(RING_COLOR, false)
	ring.visible = false
	root.add_child(ring)

	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = _frames_by_kind[u.kind]
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = SPRITE_PIXEL_SIZE
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Bottom of the cell on the ground (frames are drawn 2 px above it).
	sprite.position = Vector3(0, (CELL * 0.5 - 2.0) * SPRITE_PIXEL_SIZE, 0)
	root.add_child(sprite)
	# Don't let everyone bob in sync.
	sprite.play("idle")
	sprite.frame = u.id % FRAMES
	sprite.speed_scale = 0.85 + 0.3 * float((u.id * 37) % 10) / 10.0

	_views[u.id] = {"root": root, "ring": ring, "sprite": sprite}


func _build_frames(kind: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for state_index in STATES.size():
		var anim: String = STATES[state_index]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, STATE_FPS[anim])
		frames.set_animation_loop(anim, true)
		var row: int = kind * 3 + state_index
		for f in FRAMES:
			var region := AtlasTexture.new()
			region.atlas = ATLAS
			region.region = Rect2(f * CELL, row * CELL, CELL, CELL)
			frames.add_frame(anim, region)
	return frames


func _flat_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
