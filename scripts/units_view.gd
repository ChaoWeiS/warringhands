extends Node3D
## Draws the units from the simulation: animated 2D hand sprites standing on
## the 3D world (always facing the camera), Ragnarok-style, with a soft
## team-coloured base under each, a selection ring, and a marker where a move
## order was given. Walking units hop along (the move animation). In combat: attack animation when swinging, crying defend
## animation when hit, HP bars once damaged, floating damage numbers, and a
## death animation (it keels over) then a fade-out when a unit dies.
##
## It only reads the sim (and listens to its hit / death signals) and smooths
## positions between ticks. Units added mid-game get visuals automatically.
##
## Sprites: assets/units/hands.png, 5 frames per row, 192 px cells;
## row = kind * 5 + state (kind: rock, paper, scissors; state: idle, move,
## attack, defend, death), cut from art_source/hands_sheet_v2.png by
## tools/cut_hand_sprites.py. Walking plays "move", whose frames hop by
## themselves (with dust puffs).

@export var sim_path: NodePath

const ATLAS := preload("res://assets/units/hands.png")
const CELL := 192
## The ground line in each atlas cell, this many px above its bottom.
const GROUND := 24
const FRAMES := 5
## Atlas rows: kind * 5 + state.
const STATES := ["idle", "move", "attack", "defend", "death"]
const STATE_FPS := {"idle": 6.0, "move": 10.0, "attack": 8.0, "defend": 5.0, "death": 9.0}
## How long each attack frame shows (in frames): wind-up, lunge, then the
## impact frame (POW! / SLAP! / SNIP!) held longest, then recover.
const ATTACK_FRAMES := [1.0, 1.0, 1.0, 3.0, 1.5]
## When the impact frame comes up (s after the swing starts). The damage
## number, the victim's cry and a fall wait for it, so the hit lands there.
const IMPACT_SECONDS := 3.0 / 8.0
const IMPACT_TICKS := 7
## A little size pop on the impact frame.
const IMPACT_POP := 1.18
## Attack and death play once (attack restarts on every swing); idle and
## defend loop.
const LOOPS := {"idle": true, "move": true, "attack": false, "defend": true, "death": false}

## Team colours, used for the base under each unit.
const TEAM_COLORS := [Color("#ff7f9a"), Color("#6fb6ff")]
const RING_COLOR := Color("#ffffff")
const MARKER_COLOR := Color("#fff3b0")
const ATTACK_MARKER_COLOR := Color("#ff7a7a")
## Map units per sprite pixel (a hand is about 6 map units tall).
const SPRITE_PIXEL_SIZE := 0.06
## Height of the team circle under each unit: above every flat ground layer
## (the grass, the sand around lakes, the lakes themselves top out at 0.42),
## so they never fight over which shows (that drew it in stripes).
const GROUND_DECAL_Y := 0.6
## Height of the hand's middle above the ground, for picking.
const SPRITE_HEIGHT := 3.0
## Route lines drawn for selected units: dashed ribbons on the ground.
const ROUTE_COLOR := Color(1, 1, 1, 0.75)
const ROUTE_WIDTH := 0.6
const ROUTE_DASH := 2.2
const ROUTE_GAP := 1.6
## Combat look.
const HURT_TICKS := 20      # play "defend" this long once the hit lands
const SWING_TICKS := 19     # play "attack" this long after swinging (once, from the wind-up)
const DEATH_HOLD := 0.5     # seconds the fallen hand lies there before fading
const HP_BAR_PX := Vector2(90, 10)   # in sprite pixels
const HP_BAR_HEIGHT := 8.4           # above the ground (map units)
const HP_BAR_BG := Color(0.25, 0.22, 0.33, 0.85)
const DAMAGE_COLORS := {1: Color("#ff5a6e"), 0: Color("#ffffff"), -1: Color("#d9d4e6")}
const DAMAGE_SIZES := {1: 115, 0: 85, -1: 68}

var sim: Node
var _views: Dictionary = {}  # unit id -> {root, ring, sprite, base, hp bars, swing}
var _selected: Dictionary = {}
var _dying: Dictionary = {}  # unit id -> view, while its fall plays
## Unit voices (scripts/sounds.gd), set by the game; may be null in tests.
var sounds: Node = null
var _frames_by_kind: Array = []  # SpriteFrames per kind
var _routes_mesh := ImmediateMesh.new()
var _white: ImageTexture


func _ready() -> void:
	sim = get_node(sim_path)
	var img := Image.create(int(HP_BAR_PX.x), int(HP_BAR_PX.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	for kind in 3:
		_frames_by_kind.append(_build_frames(kind))
	sim.unit_hit.connect(_on_unit_hit)
	sim.unit_died.connect(_on_unit_died)
	for u in sim.units:
		_make_view(u)
	var routes := MeshInstance3D.new()
	routes.mesh = _routes_mesh
	routes.material_override = _flat_material(ROUTE_COLOR, true)
	routes.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(routes)
	_update_positions()


func _process(delta: float) -> void:
	_update_positions()
	_update_combat_look()
	_draw_routes()


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


## Plays "idle", "move", "attack" or "defend" for a unit right away. (During play the
## animation follows combat automatically each frame.)
func set_state(id: int, state: String) -> void:
	var view: Dictionary = _views.get(id, {})
	if not view.is_empty() and view.sprite.animation != state:
		view.sprite.play(state)


## A ring that shrinks and fades where a move order was given (red for an
## attack-move).
func show_move_marker(ground: Vector3, attack: bool = false) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 6.2
	marker.mesh = torus
	var mat := _flat_material(ATTACK_MARKER_COLOR if attack else MARKER_COLOR, true)
	marker.material_override = mat
	marker.position = Vector3(ground.x, 0.6 + _ground_height(Vector2(ground.x, ground.z)), ground.z)
	add_child(marker)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(0.3, 1, 0.3), 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(marker.queue_free)


## A red ring that pulses on an enemy you've ordered an attack on.
func show_attack_marker(target_id: int) -> void:
	var view: Dictionary = _views.get(target_id, {})
	if view.is_empty():
		return
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.6
	torus.outer_radius = 4.6
	marker.mesh = torus
	var mat := _flat_material(ATTACK_MARKER_COLOR, true)
	marker.material_override = mat
	marker.position = Vector3(0, 0.5, 0)
	view.root.add_child(marker)
	var tween := create_tween()
	for i in 2:
		tween.tween_property(marker, "scale", Vector3(1.3, 1, 1.3), 0.25)
		tween.tween_property(marker, "scale", Vector3.ONE, 0.25)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(marker.queue_free)


func _update_positions() -> void:
	var t: float = sim.tick_fraction()
	var scale_factor: float = float(sim.SCALE)
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			_make_view(u)  # a unit added mid-game
			view = _views[u.id]
		var x: float = lerpf(u.px, u.x, t) / scale_factor
		var z: float = lerpf(u.pz, u.z, t) / scale_factor
		# Up on a plateau (or partway up a ramp): drawn that high.
		var y: float = sim.field.height_at(Vector2(x, z)) if sim.field != null else 0.0
		view.root.position = Vector3(x, y, z)
		# Face the way we're walking (the art faces right).
		if u.x != u.px:
			view.sprite.flip_h = u.x < u.px


## Idle / move / attack / defend animations, facing the enemy, and HP bars.
func _update_combat_look() -> void:
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			continue
		# A swing beats a flinch, so a duel (both hit at once) shows punches.
		var state := "move" if u.moving else "idle"
		if u.target != 0 and sim.tick - u.attack_tick < SWING_TICKS:
			state = "attack"
		elif sim.tick - u.hurt_tick >= IMPACT_TICKS and sim.tick - u.hurt_tick < IMPACT_TICKS + HURT_TICKS:
			state = "defend"  # from when the blow lands
		if state == "attack" and view.swing != u.attack_tick:
			view.swing = u.attack_tick  # a new swing: start from the wind-up
			view.sprite.play("attack")
			view.sprite.frame = 0
		elif view.sprite.animation != state:
			view.sprite.play(state)
		# Idle bobbing is a little out of step per unit; fights run on time.
		view.sprite.speed_scale = view.idle_speed if state == "idle" else 1.0
		var foe: Dictionary = sim.get_unit(u.target)
		if not foe.is_empty() and not u.moving:
			view.sprite.flip_h = foe.x < u.x
		var damaged: bool = u.hp < sim.MAX_HP
		view.hp_bg.visible = damaged
		view.hp_fill.visible = damaged
		if damaged:
			var width: int = maxi(1, int(HP_BAR_PX.x * u.hp / sim.MAX_HP))
			view.hp_fill.region_rect = Rect2(0, 0, width, HP_BAR_PX.y)


## Floating damage number: big and red for a counter hit, small and pale
## when countered.
func _on_unit_hit(target_id: int, attacker_id: int, damage: int, strength: int) -> void:
	var hitter: Dictionary = _views.get(attacker_id, {})
	if sounds != null and not hitter.is_empty():
		sounds.unit_event("attack", hitter.root.position)  # the swing starts now
	# Shown when the attacker's impact frame comes up.
	get_tree().create_timer(IMPACT_SECONDS).timeout.connect(
			_show_hit.bind(target_id, attacker_id, damage, strength))


func _show_hit(target_id: int, attacker_id: int, damage: int, strength: int) -> void:
	var hitter: Dictionary = _views.get(attacker_id, {})
	if not hitter.is_empty():
		_pop(hitter.sprite)
	var view: Dictionary = _views.get(target_id, _dying.get(target_id, {}))
	if view.is_empty():
		return
	if sounds != null:
		# The blow lands: a cry, or (once, for a fallen unit) its death.
		if not _dying.has(target_id):
			sounds.unit_event("defend", view.root.position)
		elif not view.get("death_sounded", false):
			view.death_sounded = true
			sounds.unit_event("death", view.root.position)
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 3
	label.font_size = DAMAGE_SIZES[strength]
	label.outline_size = 18
	label.outline_modulate = Color(0.3, 0.22, 0.35)
	label.modulate = DAMAGE_COLORS[strength]
	label.pixel_size = 0.03
	label.position = view.root.position + Vector3(randf_range(-1.5, 1.5), 7.5, 0)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	label.scale = Vector3.ONE * 1.6  # punches in, then floats up
	tween.tween_property(label, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y + 4.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## Removes a unit's visuals at once (it was taken out of the game, not killed).
func forget(id: int) -> void:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return
	_views.erase(id)
	_selected.erase(id)
	view.root.queue_free()


## A fallen unit plays its death animation (it keels over, X eyes), lies
## there a moment, then fades away.
func _on_unit_died(id: int) -> void:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return
	_views.erase(id)
	_selected.erase(id)
	view.ring.visible = false
	view.hp_bg.visible = false
	view.hp_fill.visible = false
	var sprite: AnimatedSprite3D = view.sprite
	sprite.speed_scale = 1.0
	_dying[id] = view  # its last damage number still shows
	# It falls when the killing blow lands (the attacker's impact frame).
	var fall: float = FRAMES / STATE_FPS["death"]
	var start := IMPACT_SECONDS
	var tween := create_tween().set_parallel(true)
	tween.tween_callback(sprite.play.bind("death")).set_delay(start)
	tween.tween_property(view.base, "scale", Vector3(0.6, 1.0, 0.6), fall).set_delay(start)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.6).set_delay(start + fall + DEATH_HOLD)
	tween.tween_property(view.base, "scale", Vector3(0.2, 1.0, 0.2), 0.6).set_delay(start + fall + DEATH_HOLD)
	tween.chain().tween_callback(func():
		_dying.erase(id)
		view.root.queue_free())


## Dashed lines on the ground showing where selected units are headed,
## following their planned route around obstacles.
func _draw_routes() -> void:
	_routes_mesh.clear_surfaces()
	var started := false
	var scale_factor: float = float(sim.SCALE)
	for id in _selected:
		var u: Dictionary = sim.get_unit(id)
		if u.is_empty() or not u.moving or u.path.is_empty():
			continue
		var points: Array = [Vector2(_views[id].root.position.x, _views[id].root.position.z)]
		for wp in u.path:
			points.append(Vector2(wp.x, wp.y) / scale_factor)
		if not started:
			_routes_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			started = true
		_add_dashes(points)
	if started:
		_routes_mesh.surface_end()


func _ground_height(p: Vector2) -> float:
	return sim.field.height_at(p) if sim.field != null else 0.0


## Dashes every (ROUTE_DASH + ROUTE_GAP) along the whole route, measured
## from its start, so the pattern carries smoothly around corners.
func _add_dashes(points: Array) -> void:
	var y := 0.55
	var period: float = ROUTE_DASH + ROUTE_GAP
	var travelled := 0.0  # route length before this segment
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var dir: Vector2 = (b - a) / length
		var side: Vector2 = Vector2(-dir.y, dir.x) * ROUTE_WIDTH * 0.5
		var k: int = int(floor(travelled / period))
		while k * period < travelled + length:
			var s0: float = maxf(k * period, travelled) - travelled
			var s1: float = minf(k * period + ROUTE_DASH, travelled + length) - travelled
			if s1 > s0:
				var p0: Vector2 = a + dir * s0
				var p1: Vector2 = a + dir * s1
				var q := [p0 + side, p0 - side, p1 - side, p1 + side]
				# Following the ground: up ramps, across plateau tops.
				var h0: float = _ground_height(p0) + y
				var h1: float = _ground_height(p1) + y
				var hs := [h0, h0, h1, h1]
				for v in [0, 1, 2, 0, 2, 3]:
					_routes_mesh.surface_add_vertex(Vector3(q[v].x, hs[v], q[v].y))
			k += 1
		travelled += length


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
	base.position = Vector3(0, GROUND_DECAL_Y, 0)
	var team_color: Color = TEAM_COLORS[u.team]
	base.material_override = _flat_material(Color(team_color, 0.8), true)
	root.add_child(base)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.3
	torus.outer_radius = 3.9
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(0, GROUND_DECAL_Y + 0.1, 0)
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
	# The cell's ground line on the ground.
	sprite.position = Vector3(0, (CELL * 0.5 - GROUND) * SPRITE_PIXEL_SIZE, 0)
	root.add_child(sprite)
	# Don't let everyone bob in sync.
	sprite.play("idle")
	sprite.frame = u.id % FRAMES
	var idle_speed: float = 0.85 + 0.3 * float((u.id * 37) % 10) / 10.0
	sprite.speed_scale = idle_speed

	# HP bar (shown once damaged): dark back, team-coloured fill shrinking
	# from the right.
	var hp_bg := _hp_bar_sprite(HP_BAR_BG, true)
	var hp_fill := _hp_bar_sprite(TEAM_COLORS[u.team].lightened(0.15), false)
	hp_fill.render_priority = 2
	root.add_child(hp_bg)
	root.add_child(hp_fill)

	_views[u.id] = {
		"root": root, "ring": ring, "sprite": sprite, "base": base,
		"hp_bg": hp_bg, "hp_fill": hp_fill,
		"swing": u.attack_tick,  # last swing whose animation was started
		"idle_speed": idle_speed,
	}


func _hp_bar_sprite(color: Color, back: bool) -> Sprite3D:
	var bar := Sprite3D.new()
	bar.texture = _white
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.pixel_size = SPRITE_PIXEL_SIZE
	bar.modulate = color
	bar.shaded = false
	bar.no_depth_test = true
	bar.render_priority = 1
	bar.position = Vector3(0, HP_BAR_HEIGHT, 0)
	if back:
		bar.region_enabled = false
	else:
		# Left-anchored so it shrinks from the right.
		bar.centered = false
		bar.offset = -HP_BAR_PX * 0.5
		bar.region_enabled = true
		bar.region_rect = Rect2(Vector2.ZERO, HP_BAR_PX)
	bar.visible = false
	return bar


## A quick size pop (the impact frame).
func _pop(sprite: AnimatedSprite3D) -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector3.ONE * IMPACT_POP, 0.06).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", Vector3.ONE, 0.16).set_ease(Tween.EASE_IN_OUT)


func _build_frames(kind: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var rows := {}
	for state_index in STATES.size():
		rows[STATES[state_index]] = kind * STATES.size() + state_index
	for anim in rows:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, STATE_FPS[anim])
		frames.set_animation_loop(anim, LOOPS[anim])
		var row: int = rows[anim]
		for f in FRAMES:
			var region := AtlasTexture.new()
			region.atlas = ATLAS
			region.region = Rect2(f * CELL, row * CELL, CELL, CELL)
			frames.add_frame(anim, region, ATTACK_FRAMES[f] if anim == "attack" else 1.0)
	return frames


func _flat_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
