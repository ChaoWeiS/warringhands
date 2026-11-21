extends Control
## The campaign (the tutorial): plays one chapter of campaign.gd, a step at a
## time, on a card at the top of the screen. Bouncing arrows point at what a
## step is about (a building, a resource, a hand, a button), and some steps
## show a picture. Each step moves on when the player has done it (or taps
## Skip / Next). At the end: Next chapter, Keep playing or Menu.
##
## Started by game_controller.gd (start_tutorial) for MatchSetup.chapter.

signal finished                 # back to the menu
signal next_chapter(index: int)  # play this chapter next

const UI := preload("res://scripts/ui_style.gd")
const Campaign := preload("res://scripts/campaign.gd")
const ResourcesView := preload("res://scripts/resources_view.gd")
const HANDS := preload("res://assets/units/hands.png")
const ICONS := [preload("res://assets/env/icon_stone.png"), preload("res://assets/env/icon_wood.png"),
		preload("res://assets/env/icon_metal.png")]
const BUILDING_ART := {"hq": preload("res://assets/env/hq.png"), "quarry": preload("res://assets/env/quarry.png"),
		"mill": preload("res://assets/env/mill.png"), "forge": preload("res://assets/env/forge.png")}
const FACTORY := ["quarry", "mill", "forge"]
const VICTORY := preload("res://assets/ui/victory.png")
const CHEERS := ["Nice!", "Well done!", "Great!", "You got it!", "Perfect!"]
const FACTORY_NAME := ["Quarry", "Paper Mill", "Forge"]
const KIND_NAME := ["rocks", "papers", "scissors"]
const RES_NAME := ["stone", "wood", "metal"]
const ARROW_FILL := Color("#ffd35a")
const ARROW_INK := Color("#480c0a")
## How far from your HQ the lessons' own resource spots go (map units).
const SPOT_DISTANCE := 46.0
## A factory counts as "right beside" its resource within this gap.
const NEAR_GAP := 14.0

var game: Node
var sim: Node
var panes: Control
var hud: Control

var chapter := 0
var steps: Array = []
var step := -1
var _card: PanelContainer
var _count: Label
var _picture_slot: CenterContainer
var _text: Label
var _skip: Button
var _next_chapter: Button
var _quit: Button
## After a chapter (or while its battle is on): the card shrinks to just its
## buttons and you keep playing.
var free_play := false
var _camera_start := {}      # where each pane's camera was when the step began
var _enemies: Array = []     # the current lesson's enemies
var _spots := [{}, {}, {}]   # the lesson's resource spot for stone, wood, metal
var _build_at := [Vector2.INF, Vector2.INF, Vector2.INF]  # where its factory should go
var _delivered := {}         # "stone_hq", "stone_quarry"... -> loads
var _kinds_at_start := [0, 0, 0]
var _pointed_units := {}     # kind -> unit id the arrow follows
var _time := 0.0
var _tools: Array = []       # the buttons this chapter shows
var _cheer: Label
var _shade: ColorRect         # darkens everything but what the step is about
var _marks: Control           # arrows, rings and circles drawn over the shade
var _dim := 0.0               # how dark the shade is now (fades in and out)
var _holes: Array = []        # spotlight circles this frame: Vector3(x, y, radius)
var _step_time := 0.0         # seconds on this step (Skip shows after a while)
var _marked: Array = []       # the step's designated spots (Vector2, map units)
var _visited := {}            # unit id -> how many marked spots it has reached, in order
var _queue_used := false
var _quarry_done_for := 0.0  # seconds the Quarry has been finished
var _leave_dialog: Control = null
## Action steps can only be skipped after this long (in case someone's stuck).
const SKIP_AFTER := 60.0
## How dark the spotlight shade gets.
const DIM := 0.62
const SPOTLIGHT := """
shader_type canvas_item;
uniform vec4 holes[24];
uniform int count = 0;
uniform float dim = 0.0;
uniform vec2 area = vec2(1.0);
void fragment() {
	vec2 p = UV * area;
	float a = dim;
	for (int i = 0; i < 24; i++) {
		if (i >= count) { break; }
		float d = distance(p, holes[i].xy);
		float r = holes[i].z;
		a *= smoothstep(r * 0.8, r * 1.25, d);
	}
	COLOR = vec4(0.06, 0.03, 0.1, a);
}
"""


func setup(game_controller: Node, simulation: Node, pane_layout: Control, hud_control: Control,
		chapter_index: int = 0) -> void:
	game = game_controller
	sim = simulation
	panes = pane_layout
	hud = hud_control
	chapter = clampi(chapter_index, 0, Campaign.CHAPTERS.size() - 1)
	steps = Campaign.CHAPTERS[chapter].steps
	_tools = Campaign.CHAPTERS[chapter].get("tools", [])
	panes.cutting = "panes" in _tools
	game.did.connect(_on_did)
	sim.delivered.connect(_on_delivered)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Layers, bottom to top: the spotlight shade, the arrows and circles, the card.
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SPOTLIGHT
	_shade.material = ShaderMaterial.new()
	_shade.material.shader = shader
	add_child(_shade)
	_marks = Control.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UI.panel_box(Color(1, 1, 1, 0.94)))
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 16
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_card.add_child(column)
	_count = UI.label("", 20)
	_count.add_theme_color_override("font_color", Color("#8d6fc0"))
	column.add_child(_count)
	_picture_slot = CenterContainer.new()
	column.add_child(_picture_slot)
	_text = UI.label("", 28)
	_text.custom_minimum_size = Vector2(660, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text)
	# Back to Menu on the left (out of the way), Skip / Next on the right.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_quit = _card_button("Back to Menu", 200)
	_quit.pressed.connect(_ask_leave)
	row.add_child(_quit)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	_skip = _card_button("Skip step", 150)
	_skip.pressed.connect(_on_skip)
	row.add_child(_skip)
	_next_chapter = _card_button("Next chapter", 190, Color("#fff3b0"), Color("#ffe9a0"))
	_next_chapter.visible = false
	_next_chapter.pressed.connect(func(): next_chapter.emit(chapter + 1))
	row.add_child(_next_chapter)
	column.add_child(row)
	# "Nice!" when a step is done.
	_cheer = UI.label("", 64)
	_cheer.add_theme_color_override("font_color", Color("#ffd35a"))
	_cheer.add_theme_color_override("font_outline_color", Color("#480c0a"))
	_cheer.add_theme_constant_override("outline_size", 18)
	_cheer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cheer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_cheer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cheer.offset_top = 260 * UI.ui_scale()
	_cheer.modulate.a = 0.0
	_cheer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cheer)
	if Campaign.CHAPTERS[chapter].has("setup"):
		call(Campaign.CHAPTERS[chapter].setup)
	if Campaign.map_of(chapter) == "training":
		_frame_base()
	next_step()


## The camera shows your whole little base: HQ, army and the resources by
## it, a bit low on screen so the card doesn't cover it.
func _frame_base(extra: Array = []) -> void:
	var hq: Dictionary = sim.hq_of(game.player_team)
	if hq.is_empty():
		return
	var box := Rect2(Vector2(hq.x, hq.z) / float(sim.SCALE), Vector2.ZERO)
	for n in sim.nodes:
		var p := Vector2(n.x, n.z) / float(sim.SCALE)
		if not n.tree and p.distance_to(box.position) < 80.0:
			box = box.expand(p)
	for u in sim.units:
		if u.team == game.player_team:
			box = box.expand(Vector2(u.x, u.z) / float(sim.SCALE))
	for p in extra:
		box = box.expand(p)
	box = box.grow(22.0)
	for leaf in panes._leaves():
		var cam: Camera3D = leaf.camera
		var px: Vector2 = leaf.rect.size
		# Room for the card at the top: use the lower three quarters.
		var upp: float = maxf(box.size.x / px.x, box.size.y / (px.y * 0.62))
		cam.units_per_pixel = clampf(upp, 0.05, cam.max_units_per_pixel)
		var c: Vector2 = box.get_center()
		var lift: float = px.y * 0.14 * cam.units_per_pixel
		cam.target = Vector3(c.x, 0, c.y - lift)
		cam.refit()


func _card_button(label: String, width: float, color := Color("#f2eefb"), pressed := Color("#e7e1f5")) -> Button:
	var b := UI.button(color, pressed, 22)
	b.text = label
	b.custom_minimum_size = Vector2(width, 56) * UI.ui_scale()
	return b


func card() -> Control:
	return _card


## Skip / Next. On a chapter's last step: Keep playing (close the card).
func _on_skip() -> void:
	if _is_end():
		_set_compact(true)
		return
	next_step()


func _is_end() -> bool:
	return step >= 0 and step < steps.size() and steps[step].get("end", false)


func next_step() -> void:
	# A step done by the player (not just read): a little celebration.
	if step >= 0 and step < steps.size() and not steps[step].get("next", false) and not steps[step].get("end", false) \
			and steps[step].text != "":
		_celebrate()
	step += 1
	if step >= steps.size():
		finished.emit()
		return
	var s: Dictionary = steps[step]
	_set_compact(false)
	var title: String = Campaign.CHAPTERS[chapter].title
	_count.text = "Chapter %d  ·  %s  ·  %d of %d" % [chapter + 1, title, mini(step + 1, steps.size() - 1), steps.size() - 1]
	_text.text = s.text
	var end: bool = s.get("end", false)
	_skip.text = "Keep playing" if end else ("Next" if s.get("next", false) else "Skip step")
	_step_time = 0.0
	_marked.clear()
	_visited.clear()
	_queue_used = false
	_next_chapter.visible = end and chapter + 1 < Campaign.CHAPTERS.size()
	if end:
		_count.text = "Chapter %d  ·  %s" % [chapter + 1, title]
		Campaign.mark_done(chapter)
		if not Campaign.CHAPTERS[chapter].get("enemies", false):
			_victory_banner()  # (a real battle has its own Victory)
	_show_picture(s.get("picture", ""))
	_pointed_units.clear()
	for kind in 3:
		_kinds_at_start[kind] = _count_kind(kind)
	if s.has("enter"):
		call(s.enter)
	_update_skip()
	_bring_into_view.call_deferred()
	# A little bounce so the new instruction gets noticed.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2.ONE * 1.06
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)


## Compact: only the buttons (Next chapter / Menu), so the map is free.
func _set_compact(on: bool) -> void:
	free_play = on
	_count.visible = not on
	_text.visible = not on
	_picture_slot.visible = not on
	_skip.visible = not on
	if not on:
		_update_skip()
	_card.offset_left = 0
	_card.offset_right = 0
	_card.reset_size.call_deferred()


## "Nice!" over the map, with a sparkle sound.
func _celebrate() -> void:
	if _cheer == null:
		return
	_cheer.text = CHEERS[randi() % CHEERS.size()]
	_cheer.pivot_offset = _cheer.size * 0.5
	_cheer.scale = Vector2.ONE * 0.4
	_cheer.modulate.a = 1.0
	var t := _cheer.create_tween()
	t.tween_property(_cheer, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(_cheer, "modulate:a", 0.0, 0.4)
	if game.get("sounds") != null:
		game.sounds.cue("build_done", 1.15)


## The Victory sign, popping in for a moment when a chapter is done.
func _victory_banner() -> void:
	var sign := TextureRect.new()
	sign.texture = VICTORY
	sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sign.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = minf(get_viewport_rect().size.x * 0.5, 700.0 * UI.ui_scale())
	sign.custom_minimum_size = Vector2(w, w * VICTORY.get_height() / VICTORY.get_width())
	sign.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sign.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sign.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(sign)
	sign.reset_size()
	sign.position = (get_rect().size - sign.size) * 0.5
	sign.pivot_offset = sign.size * 0.5
	sign.scale = Vector2.ONE * 0.3
	var t := sign.create_tween()
	t.tween_property(sign, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.6)
	t.tween_property(sign, "modulate:a", 0.0, 0.5)
	t.tween_callback(sign.queue_free)
	if game.get("sounds") != null:
		game.sounds.cue("build_done", 0.9)


## Only the buttons this chapter has taught: the rest stay hidden, so
## there's less to get lost in.
func _limit_tools() -> void:
	var bar: Node = game.bar
	if bar._attack != null:
		bar._attack.visible = "attack" in _tools
	if bar.actions.get_child_count() > 1:
		bar.actions.get_child(1).visible = "hold" in _tools
	if bar.queue_button != null:
		bar.queue_button.visible = "queue" in _tools
	if hud._build_toggle != null:
		hud._build_toggle.visible = "build" in _tools
	if hud._build_options.has("hq") and not "build_hq" in _tools:
		hud._build_options.hq.visible = false  # (the menu shows the rest when open)
	if game.minimap != null:
		game.minimap.visible = "minimap" in _tools


func _on_did(action: String) -> void:
	if action == "queue":
		_queue_used = true
	if step < 0 or step >= steps.size() or free_play:
		return
	var s: Dictionary = steps[step]
	if s.has("on") and action in s.on:
		if action == "lasso" and s.on == ["lasso"] and game.selection.size() < 2:
			return  # a loop around just one hand doesn't count here
		next_step()


func _on_delivered(team: int, res: int, _amount: int, building_id: int) -> void:
	if team != game.player_team:
		return
	var b: Dictionary = sim.get_entity(building_id)
	var key: String = RES_NAME[res] + "_" + (b.btype if not b.is_empty() else "?")
	_delivered[key] = _delivered.get(key, 0) + 1


func _process(delta: float) -> void:
	_time += delta
	# Some steps say what to do next while Group is held.
	if step >= 0 and step < steps.size() and steps[step].has("holding_text") and not free_play:
		var want: String = steps[step].holding_text if panes.grouping else steps[step].text
		if _text.text != want:
			_text.text = want
	_step_time += delta
	_holes.clear()
	_marks.queue_redraw()
	_limit_tools()
	_track_route()
	if _skip.visible == false and not free_play and _needs_doing() and _step_time >= SKIP_AFTER:
		_skip.visible = true
	if step < 0 or step >= steps.size():
		return
	var s: Dictionary = steps[step]
	if s.has("poll") and call(s.poll):
		next_step()


# --- Pictures on the card ----------------------------------------------------------

func _show_picture(which: String) -> void:
	for c in _picture_slot.get_children():
		c.queue_free()
	_picture_slot.visible = which != ""
	match which:
		"hq":
			_picture_slot.add_child(_art(BUILDING_ART.hq, 130))
		"rps":
			_picture_slot.add_child(RpsPicture.new())
		"gather":
			var row := _row()
			for kind in 3:
				var cell := _row(6)
				cell.add_child(_art(_hand(kind), 70))
				cell.add_child(ArrowGlyph.new())
				cell.add_child(_art(ICONS[kind], 52))
				row.add_child(cell)
			_picture_slot.add_child(row)
		"factories":
			var row := _row(28)
			for kind in 3:
				var cell := VBoxContainer.new()
				cell.alignment = BoxContainer.ALIGNMENT_CENTER
				cell.add_child(_art(BUILDING_ART[FACTORY[kind]], 86))
				var name := UI.label(FACTORY_NAME[kind], 22)
				name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.add_child(name)
				var takes := _row(4)
				takes.add_child(UI.label("takes", 18))
				takes.add_child(_art(ICONS[kind], 30))
				takes.add_child(UI.label("makes", 18))
				takes.add_child(_art(_hand(kind), 40))
				cell.add_child(takes)
				row.add_child(cell)
			_picture_slot.add_child(row)
		"balance":
			var row := _row(14)
			for kind in 3:
				row.add_child(_art(_hand(kind), 60))
			row.add_child(UI.label("gather  ·  or  ·  fight", 24))
			for kind in 3:
				row.add_child(_art(ICONS[kind], 40))
			_picture_slot.add_child(row)


func _row(gap: int = 22) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", gap)
	return row


func _art(tex: Texture2D, height: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var h: float = height * UI.ui_scale()
	r.custom_minimum_size = Vector2(h * tex.get_width() / tex.get_height(), h)
	return r


## A hand's idle picture.
static func _hand(kind: int) -> Texture2D:
	var a := AtlasTexture.new()
	a.atlas = HANDS
	a.region = Rect2(0, kind * 5 * 192, 192, 192)
	return a


## A small drawn arrow pointing right (the font has no arrow character).
class ArrowGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(34, 30) * UI.ui_scale()

	func _draw() -> void:
		var s: float = UI.ui_scale()
		var mid: float = size.y * 0.5
		var ink := Color("#8d6fc0")
		draw_line(Vector2(2 * s, mid), Vector2(size.x - 12 * s, mid), ink, 5 * s, true)
		draw_colored_polygon(PackedVector2Array([Vector2(size.x - 2 * s, mid),
				Vector2(size.x - 16 * s, mid - 10 * s), Vector2(size.x - 16 * s, mid + 10 * s)]), ink)


## The rock-paper-scissors circle: each hand with an arrow to the one it beats.
class RpsPicture extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(470, 330) * UI.ui_scale()

	func _draw() -> void:
		var s: float = UI.ui_scale()
		var c: Vector2 = size * 0.5 + Vector2(0, 10 * s)
		var r: float = 96 * s
		# Rock at the top, scissors bottom right, paper bottom left: arrows
		# go round clockwise, each from a hand to the one it beats.
		var at := [c + Vector2(0, -r), c + Vector2(-r * 1.25, r * 0.6), c + Vector2(r * 1.25, r * 0.6)]
		var beats := [2, 0, 1]  # rock > scissors, paper > rock, scissors > paper
		var font: Font = ThemeDB.fallback_font
		var ink := Color("#8d6fc0")
		for kind in 3:
			var from: Vector2 = at[kind]
			var to: Vector2 = at[beats[kind]]
			var d: Vector2 = (to - from).normalized()
			var a: Vector2 = from + d * 52 * s
			var b: Vector2 = to - d * 56 * s
			draw_line(a, b - d * 6 * s, ink, 6 * s, true)
			var n := d.orthogonal()
			draw_colored_polygon(PackedVector2Array([b + d * 10 * s, b - d * 12 * s + n * 12 * s, b - d * 12 * s - n * 12 * s]), ink)
			# "beats" beside the arrow, on the outside of the circle.
			var mid: Vector2 = (a + b) * 0.5
			var out: Vector2 = (mid - c).normalized()
			var size_px := int(22 * s)
			var w: float = font.get_string_size("beats", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			draw_string(font, mid + out * 26 * s - Vector2(w * 0.5, -size_px * 0.35), "beats", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, ink)
		for kind in 3:
			var h: float = 124 * s
			draw_texture_rect(Tutorial_hand(kind), Rect2(at[kind] - Vector2(h, h) * 0.5, Vector2(h, h)), false)

	static func Tutorial_hand(kind: int) -> Texture2D:
		var a := AtlasTexture.new()
		a.atlas = HANDS
		a.region = Rect2(0, kind * 5 * 192, 192, 192)
		return a


# --- Arrows ------------------------------------------------------------------------------

## What the current step's arrows point at: [{"world": Vector3}] or [{"ui": Control}].
func _targets() -> Array:
	if step < 0 or step >= steps.size() or free_play:
		return []
	var out: Array = []
	for what in steps[step].get("point", []):
		var t: Dictionary = _resolve(what)
		if not t.is_empty():
			out.append(t)
	return out


## One arrow target:
##   "hq", "enemies", "kind:K" (one of your hands), "node:R" (the lesson's
##   resource spot), "spot:R" (where its factory should go),
##   "building:TYPE" (your first of that type),
##   "ui:build", "ui:build:TYPE" (the hammer, then that option once open),
##   "ui:attack", "ui:hold", "ui:queue", "ui:train", "ui:resources", "ui:minimap".
func _resolve(what: String) -> Dictionary:
	var parts: PackedStringArray = what.split(":")
	match parts[0]:
		"hq":
			var hq: Dictionary = sim.hq_of(game.player_team)
			return {} if hq.is_empty() else {"world": _ground(hq, 15.0), "ring": 14.0}
		"enemies":
			var middle := Vector3.ZERO
			var n := 0
			for id in _enemies:
				var u: Dictionary = sim.get_unit(id)
				if not u.is_empty():
					middle += _ground(u, 0.0)
					n += 1
			return {} if n == 0 else {"world": middle / n + Vector3(0, 6, 0), "ring": 10.0}
		"kind":
			# The arrow on one of them; the spotlight on all of that kind
			# (a double tap picks them all).
			var kind: int = int(parts[1])
			var id: int = _unit_to_point(kind)
			if id < 0:
				return {}
			var lit: Array = []
			for u in sim.units:
				if u.team == game.player_team and u.kind == kind:
					lit.append(Vector2(u.x, u.z) / float(sim.SCALE))
			return {"world": _ground(sim.get_unit(id), 5.5), "ring": 4.0, "lit": lit}
		"node":
			var node: Dictionary = _spots[int(parts[1])]
			if node.is_empty() or sim.get_node_by_id(node.id).is_empty():
				return {}
			return {"world": _ground(node, ResourcesView.top_of(node) + 1.0), "ring": node.radius / float(sim.SCALE)}
		"spot":
			var res: int = int(parts[1])
			if _has_factory_near(res) or _build_at[res] == Vector2.INF:
				return {}
			var p: Vector2 = _build_at[res]
			return {"world": Vector3(p.x, sim.field.height_at(p) + 2.0, p.y), "ring": 9.0, "ghost": true}
		"army":
			# All your hands, with a dashed loop round them: "draw it like this".
			var centre: Vector2 = _army_centre()
			var reach := 0.0
			for u in sim.units:
				if u.team == game.player_team:
					reach = maxf(reach, centre.distance_to(Vector2(u.x, u.z) / float(sim.SCALE)))
			return {"world": Vector3(centre.x, sim.field.height_at(centre) + 2.0, centre.y),
					"ring": reach + 5.0, "loop": true, "no_arrow": true}
		"mark":
			var i: int = int(parts[1])
			if i >= _marked.size():
				return {}
			var p: Vector2 = _marked[i]
			var done: bool = _furthest_visit() > i
			if done:
				return {}
			return {"world": Vector3(p.x, sim.field.height_at(p) + 2.0, p.y), "ring": MARK_RADIUS, "ghost": true,
					"label": str(i + 1) if _marked.size() > 1 else ""}
		"building":
			for b in sim.buildings:
				if b.team == game.player_team and b.btype == parts[1]:
					# Pointed at from the side, so the arrow doesn't cover its health bar.
					return {"world": _ground(b, 8.0), "ring": b.radius / float(sim.SCALE), "side": true}
			return {}
		"ui":
			return _ui_target(parts)
	return {}


func _ui_target(parts: PackedStringArray) -> Dictionary:
	var c: Control = null
	match parts[1]:
		"build":
			c = hud._build_toggle
			if parts.size() > 2 and hud._build_options.has(parts[2]) and hud._build_options[parts[2]].is_visible_in_tree():
				c = hud._build_options[parts[2]]
			elif parts.size() > 2 and panes.placing:
				return {}  # placing now: the spot's arrow is enough
		"attack":
			c = game.bar._attack
		"hold":
			c = game.bar.actions.get_child(1)
		"queue":
			c = game.bar.queue_button
		"train":
			c = hud._train_button
		"resources":
			c = hud.resource_bar
		"group":
			c = hud.group_button
		"minimap":
			var leaves: Array = panes._leaves()
			c = game.minimap.map_of(leaves[0]) if not leaves.is_empty() else null
	if c == null or not c.is_visible_in_tree():
		return {}
	return {"ui": c}


func _ground(e: Dictionary, lift: float) -> Vector3:
	var p := Vector2(e.x, e.z) / float(sim.SCALE)
	return Vector3(p.x, sim.field.height_at(p) + lift, p.y)


## The hand of this kind the arrow follows (stays on the same one while it lives).
func _unit_to_point(kind: int) -> int:
	var id: int = _pointed_units.get(kind, -1)
	if id >= 0 and not sim.get_unit(id).is_empty():
		return id
	var hq: Dictionary = sim.hq_of(game.player_team)
	var best := -1
	var best_d := INF
	for u in sim.units:
		if u.team != game.player_team or u.kind != kind:
			continue
		var d: float = 0.0 if hq.is_empty() else float(sim._dist2(u, hq))
		if d < best_d:
			best_d = d
			best = u.id
	_pointed_units[kind] = best
	return best


func _draw_marks() -> void:
	_draw_targets()
	_update_shade()


## The spotlight: dark everywhere except round the things the arrows point
## at (fades in and out).
func _update_shade() -> void:
	var lit: bool = step >= 0 and step < steps.size() and steps[step].get("spotlight", true)
	var want: float = DIM if not _holes.is_empty() and not free_play and lit else 0.0
	_dim = move_toward(_dim, want, get_process_delta_time() * 1.5)
	var m: ShaderMaterial = _shade.material
	var packed: Array = []
	for i in mini(_holes.size(), 24):
		var h: Vector3 = _holes[i]
		packed.append(Vector4(h.x, h.y, h.z, 0))
	while packed.size() < 24:
		packed.append(Vector4.ZERO)
	m.set_shader_parameter("holes", packed)
	m.set_shader_parameter("count", mini(_holes.size(), 24))
	m.set_shader_parameter("dim", _dim)
	m.set_shader_parameter("area", _shade.size)


func _draw_targets() -> void:
	var s: float = UI.ui_scale()
	var bounce: float = absf(sin(_time * 4.0)) * 14.0 * s
	var me: Vector2 = get_global_rect().position
	for t in _targets():
		if t.has("ui"):
			var r: Rect2 = t.ui.get_global_rect()
			r.position -= me
			var centre: Vector2 = get_rect().size * 0.5
			var c: Vector2 = r.get_center()
			# Point at it from the middle of the screen's side.
			var dir: Vector2 = (c - centre).normalized()
			if absf(dir.x) > absf(dir.y):
				dir = Vector2(signf(dir.x), 0)
			else:
				dir = Vector2(0, signf(dir.y))
			var tip: Vector2 = c - dir * (absf(dir.x) * r.size.x + absf(dir.y) * r.size.y) * 0.5 - dir * 6 * s
			_arrow(tip - dir * bounce, dir, s)
			_marks.draw_rect(r.grow(6 * s), Color(ARROW_FILL, 0.9), false, 5 * s)
			_holes.append(Vector3(c.x, c.y, maxf(r.size.x, r.size.y) * 0.75 + 18 * s))
			continue
		var shown := false
		var leaves: Array = panes._leaves()
		for leaf in leaves:
			var cam: Camera3D = leaf.camera
			var rect: Rect2 = leaf.rect
			rect.position += panes.get_global_rect().position - me
			var p: Vector2 = cam.unproject_position(t.world) + rect.position
			var inner: Rect2 = rect.grow(-40 * s)
			if inner.has_point(p):
				shown = true
				var foot: Vector2 = cam.unproject_position(t.world - Vector3(0, t.world.y - sim.field.height_at(Vector2(t.world.x, t.world.z)), 0)) + rect.position
				if t.get("loop", false):
					_dashed_loop(foot, _px(cam, t.ring), s)
					_holes.append(Vector3(foot.x, foot.y, maxf(_px(cam, t.ring) * 1.35, 90.0 * s)))
					continue
				_ring(cam, t, rect, s)
				_holes.append(Vector3(foot.x, foot.y, maxf(_px(cam, t.get("ring", 4.0)) * 1.6, 70.0 * s)))
				for q in t.get("lit", []):
					var at: Vector2 = cam.unproject_position(Vector3(q.x, sim.field.height_at(q), q.y)) + rect.position
					if at.distance_to(foot) > 4.0:
						_holes.append(Vector3(at.x, at.y, maxf(_px(cam, 4.0) * 1.8, 48.0 * s)))
				if t.get("label", "") != "":
					var font: Font = ThemeDB.fallback_font
					var size_px := int(48 * s)
					var w: float = font.get_string_size(t.label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
					_marks.draw_string_outline(font, foot + Vector2(-w * 0.5, size_px * 0.35), t.label,
							HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, int(10 * s), ARROW_INK)
					_marks.draw_string(font, foot + Vector2(-w * 0.5, size_px * 0.35), t.label,
							HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, ARROW_FILL)
				if t.get("ghost", false):
					_marks.draw_circle(foot, maxf(8.0, _px(cam, t.ring)), Color(1, 1, 1, 0.25))
				if t.get("side", false):
					# Light up its health bar too (it floats above the building).
					var bar: Vector2 = cam.unproject_position(Vector3(t.world.x, t.world.y + 17.0, t.world.z)) + rect.position
					_holes.append(Vector3(bar.x, bar.y, 70.0 * s))
					var half: float = _px(cam, t.ring)
					_arrow(p - Vector2(half + 8.0 * s + bounce, 0), Vector2.RIGHT, s)
				else:
					_arrow(p - Vector2(0, bounce), Vector2.DOWN, s)
		if not shown and not leaves.is_empty() and not t.get("no_arrow", false):
			# Off screen: an arrow at the edge of the first pane, pointing its way.
			var leaf = leaves[0]
			var rect: Rect2 = leaf.rect
			rect.position += panes.get_global_rect().position - me
			var p: Vector2 = leaf.camera.unproject_position(t.world) + rect.position
			var c: Vector2 = rect.get_center()
			var dir: Vector2 = (p - c).normalized()
			var inner: Rect2 = rect.grow(-70 * s)
			var k: float = INF
			if absf(dir.x) > 0.001:
				k = minf(k, (inner.size.x * 0.5) / absf(dir.x))
			if absf(dir.y) > 0.001:
				k = minf(k, (inner.size.y * 0.5) / absf(dir.y))
			_arrow(c + dir * (k - bounce), dir, s)


## A dashed loop that slowly goes round, showing where to draw one.
func _dashed_loop(centre: Vector2, radius: float, s: float) -> void:
	var r: float = maxf(radius, 30.0 * s)
	var dashes := 28
	var turn: float = _time * 0.6
	for k in dashes:
		var a0: float = turn + k * TAU / dashes
		var a1: float = a0 + TAU / dashes * 0.55
		var pts := PackedVector2Array()
		for j in 5:
			var a: float = lerpf(a0, a1, j / 4.0)
			pts.append(centre + Vector2(cos(a) * r, sin(a) * r * 0.62))
		_marks.draw_polyline(pts, Color(ARROW_INK, 0.7), 8 * s, true)
		_marks.draw_polyline(pts, ARROW_FILL, 5 * s, true)


func _ring(cam: Camera3D, t: Dictionary, rect: Rect2, s: float) -> void:
	var g := Vector2(t.world.x, t.world.z)
	var foot: Vector2 = cam.unproject_position(Vector3(g.x, sim.field.height_at(g), g.y)) + rect.position
	var r: float = maxf(14.0 * s, _px(cam, t.get("ring", 4.0) + 3.0)) + absf(sin(_time * 4.0)) * 5 * s
	# An ellipse (the ground is seen at an angle).
	var pts := PackedVector2Array()
	for k in 33:
		var a: float = k * TAU / 32
		pts.append(foot + Vector2(cos(a) * r, sin(a) * r * 0.62))
	_marks.draw_polyline(pts, Color(ARROW_INK, 0.6), 7 * s, true)
	_marks.draw_polyline(pts, ARROW_FILL, 4 * s, true)


## Map units to screen pixels for this camera.
func _px(cam: Camera3D, units: float) -> float:
	return cam.unproject_position(Vector3(units, 0, 0)).distance_to(cam.unproject_position(Vector3.ZERO))


## A fat cartoon arrow whose tip is at `tip`, pointing along `dir`.
func _arrow(tip: Vector2, dir: Vector2, s: float) -> void:
	var n: Vector2 = dir.orthogonal()
	var head := 46.0 * s
	var half := 32.0 * s
	var shaft := 14.0 * s
	var length := 110.0 * s
	var base: Vector2 = tip - dir * head
	var tail: Vector2 = tip - dir * length
	var pts := PackedVector2Array([tip, base + n * half, base + n * shaft, tail + n * shaft,
			tail - n * shaft, base - n * shaft, base - n * half])
	_marks.draw_colored_polygon(pts, ARROW_FILL)
	pts.append(tip)
	_marks.draw_polyline(pts, ARROW_INK, 4.5 * s, true)


# --- Chapter setups ----------------------------------------------------------------

func _setup_basic() -> void:
	pass


## Lessons about gathering: a stone pile, a lumber camp and crystals near
## your HQ, each with room for its factory beside it.
func _setup_resources() -> void:
	_place_spots()


## Factories already built beside each resource, and every hand gathering.
func _setup_economy() -> void:
	_place_spots()
	for res in 3:
		if _build_at[res] != Vector2.INF:
			var p: Vector2 = _build_at[res]
			sim._add_building(game.player_team, FACTORY[res], Vector2i(roundi(p.x * sim.SCALE), roundi(p.y * sim.SCALE)), true)
	for kind in 3:
		var ids: Array = []
		for u in sim.units:
			if u.team == game.player_team and u.kind == kind:
				ids.append(u.id)
		if not _spots[kind].is_empty() and not ids.is_empty():
			sim.command_gather(ids, _spots[kind].id)


func _setup_repairs() -> void:
	_setup_economy()
	for b in sim.buildings:
		if b.team == game.player_team and b.btype == "mill":
			b.hp = roundi(b.max_hp * 0.35)


## The real thing: the computer plays the other side.
func _setup_battle() -> void:
	sim.enable_ai(1 - game.player_team, "easy")


func _place_spots() -> void:
	var hq: Dictionary = sim.hq_of(game.player_team)
	if hq.is_empty():
		return
	var home := Vector2(hq.x, hq.z) / float(sim.SCALE)
	var taken: Array = []
	for res in 3:
		# A spot of the map's own close enough, with room for its factory?
		var found: Dictionary = {}
		for n in sim.nodes:
			if n.res == res and not n.tree and home.distance_to(Vector2(n.x, n.z) / float(sim.SCALE)) < 70.0:
				var at: Vector2 = _factory_spot(n, FACTORY[res])
				if at != Vector2.INF:
					found = n
					_build_at[res] = at
					break
		if found.is_empty():
			found = _new_spot(res, home, taken)
		_spots[res] = found
		if not found.is_empty():
			taken.append(Vector2(found.x, found.z) / float(sim.SCALE))


## A new resource spot about SPOT_DISTANCE from home, clear of everything,
## with room for its factory between it and the HQ.
func _new_spot(res: int, home: Vector2, taken: Array) -> Dictionary:
	var radius: float = [13.0, 16.0, 5.0][res]
	var grid = sim.nav()
	for k in 36:
		var a: float = k * TAU / 36.0 + res * 2.1
		var p: Vector2 = home + Vector2.from_angle(a) * SPOT_DISTANCE
		if not sim.field.is_walkable(p) or sim.field.is_slope_or_edge(p):
			continue
		if grid != null and not grid.circle_is_open(roundi(p.x * sim.SCALE), roundi(p.y * sim.SCALE), roundi((radius + 4.0) * sim.SCALE)):
			continue
		var clear := true
		for q in taken:
			clear = clear and p.distance_to(q) > radius + 40.0
		for n in sim.nodes:
			clear = clear and p.distance_to(Vector2(n.x, n.z) / float(sim.SCALE)) > radius + n.radius / float(sim.SCALE) + 12.0
		for u in sim.units:
			clear = clear and p.distance_to(Vector2(u.x, u.z) / float(sim.SCALE)) > radius + 6.0
		if not clear:
			continue
		var node: Dictionary = sim.add_node(res, p, radius)
		var at: Vector2 = _factory_spot(node, FACTORY[res])
		if at != Vector2.INF:
			_build_at[res] = at
			return node
		# No room for its factory: take it away again and try elsewhere.
		sim.nodes.erase(node)
		sim._nodes_by_id.erase(node.id)
		if grid != null:
			grid.set_blocked(node.x, node.z, node.radius, false)
	return {}


## A place for this factory right beside the resource spot (on the HQ's
## side first), where it can be built now; or Vector2.INF.
func _factory_spot(node: Dictionary, btype: String) -> Vector2:
	var hq: Dictionary = sim.hq_of(game.player_team)
	var c := Vector2(node.x, node.z) / float(sim.SCALE)
	var towards: float = (Vector2(hq.x, hq.z) / float(sim.SCALE) - c).angle()
	var gap: float = node.radius / float(sim.SCALE) + sim.BUILDINGS[btype].radius / float(sim.SCALE) + 7.0
	# Beside it, a little off the line to the HQ (where gatherers walk), so
	# nobody is standing in the way when it's built.
	for k in 16:
		var a: float = towards + PI * 0.35 * (1 if k % 2 == 0 else -1) + (k / 2) * TAU / 16.0 * (1 if k % 2 == 0 else -1)
		var p: Vector2 = c + Vector2.from_angle(a) * gap
		if sim.can_place(btype, p, game.player_team):
			return p
	return Vector2.INF


## The lesson's factory has been laid down (anywhere: the circle is a
## suggestion).
func _has_factory_near(res: int) -> bool:
	for b in sim.buildings:
		if b.team == game.player_team and b.btype == FACTORY[res]:
			return true
	return false


# --- Step helpers ------------------------------------------------------------------

func _note_cameras() -> void:
	_camera_start.clear()
	for leaf in panes._leaves():
		_camera_start[leaf.camera] = [leaf.camera.target, leaf.camera.units_per_pixel]


func _camera_change(moved: float, zoomed: float) -> bool:
	for leaf in panes._leaves():
		var start: Array = _camera_start.get(leaf.camera, [])
		if start.is_empty():
			continue
		if moved > 0.0 and leaf.camera.target.distance_to(start[0]) > moved:
			return true
		if zoomed > 0.0 and absf(leaf.camera.units_per_pixel - start[1]) > start[1] * zoomed:
			return true
	return false


func _camera_panned() -> bool:
	return _camera_change(8.0, 0.0)


func _camera_zoomed() -> bool:
	return _camera_change(0.0, 0.15)


func _camera_jumped() -> bool:
	return _camera_change(60.0, 0.0)


func _go_home() -> void:
	game.focus_home()


func _split_done() -> bool:
	return panes.pane_count() >= 2


func _merged_done() -> bool:
	return panes.pane_count() == 1


func _count_kind(kind: int) -> int:
	var n := 0
	for u in sim.units:
		if u.team == game.player_team and u.kind == kind:
			n += 1
	return n


## Some of your `kind` hands are gathering this resource.
func _gathering(res: int) -> bool:
	for u in sim.units:
		if u.team == game.player_team and u.job == "gather":
			var node: Dictionary = sim.get_node_by_id(u.node)
			if not node.is_empty() and node.res == res:
				return true
	return false


func _gathering_stone() -> bool:
	return _gathering(0)


func _gathering_wood() -> bool:
	return _gathering(1)


func _gathering_metal() -> bool:
	return _gathering(2)


func _stone_at_hq() -> bool:
	return _delivered.get("stone_hq", 0) > 0


## Stone dropped at the Quarry; or, if it was built far from the pile (so
## the rocks still go to the HQ), a while after it's finished.
func _stone_at_quarry() -> bool:
	if _delivered.get("stone_quarry", 0) > 0:
		return true
	for b in sim.buildings:
		if b.team == game.player_team and b.btype == "quarry" and b.progress >= sim.BUILDINGS.quarry.build:
			_quarry_done_for += get_process_delta_time()
			return _quarry_done_for > 15.0
	return false


func _quarry_near() -> bool:
	return _has_factory_near(0)


func _mill_near() -> bool:
	return _has_factory_near(1)


func _forge_near() -> bool:
	return _has_factory_near(2)


func _new_rock() -> bool:
	return _count_kind(0) > _kinds_at_start[0]


func _new_paper_and_scissors() -> bool:
	return _count_kind(1) > _kinds_at_start[1] and _count_kind(2) > _kinds_at_start[2]


func _mill_repaired() -> bool:
	for b in sim.buildings:
		if b.team == game.player_team and b.btype == "mill":
			return b.hp >= b.max_hp
	return true


func _battle_won() -> bool:
	return sim.winner == game.player_team


func _tuck_card() -> void:
	_set_compact(true)


# --- Designated spots, skipping, leaving, the camera ----------------------------------

## How close a hand must get to a marked spot (map units).
const MARK_RADIUS := 6.0


## One circle a little way out from your army, toward the middle of the
## island: "send them there".
func _mark_move_spot() -> void:
	var c: Vector2 = _army_centre()
	var out: Vector2 = (sim.field.get_center() - c).normalized()
	_marked = [_open_near(c + out * 24.0)]


## Three numbered circles for a queued route.
func _mark_queue_spots() -> void:
	var c: Vector2 = _army_centre()
	var out: Vector2 = (sim.field.get_center() - c).normalized()
	var side: Vector2 = out.orthogonal()
	_marked = [_open_near(c + out * 20.0 + side * 20.0), _open_near(c + out * 40.0),
			_open_near(c + out * 20.0 - side * 20.0)]


func _army_centre() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for u in sim.units:
		if u.team == game.player_team:
			sum += Vector2(u.x, u.z) / float(sim.SCALE)
			n += 1
	if n == 0:
		var hq: Dictionary = sim.hq_of(game.player_team)
		return Vector2(hq.x, hq.z) / float(sim.SCALE)
	return sum / n


## Keeps track of which marked spots each hand has reached, in order.
func _track_route() -> void:
	if _marked.is_empty():
		return
	for u in sim.units:
		if u.team != game.player_team:
			continue
		var at: int = _visited.get(u.id, 0)
		if at < _marked.size() and (Vector2(u.x, u.z) / float(sim.SCALE)).distance_to(_marked[at]) <= MARK_RADIUS:
			_visited[u.id] = at + 1


func _furthest_visit() -> int:
	var best := 0
	for id in _visited:
		best = maxi(best, _visited[id])
	return best


## A hand got to the (first) circle.
func _reached_mark() -> bool:
	return _furthest_visit() >= 1


## A hand went through all the circles, in order, using Queue.
func _queue_route_done() -> bool:
	return _queue_used and _furthest_visit() >= _marked.size()


## This step needs the player to do something (not just read).
func _needs_doing() -> bool:
	if step < 0 or step >= steps.size():
		return false
	var s: Dictionary = steps[step]
	return not s.get("next", false) and not s.get("end", false)


## Skip only for reading (Next) at once; a step to do shows Skip only after
## a while, in case someone is stuck.
func _update_skip() -> void:
	if free_play:
		return
	_skip.visible = not _needs_doing() or _step_time >= SKIP_AFTER


## Leaving needs a second tap, so it can't happen by accident.
func _ask_leave() -> void:
	if is_instance_valid(_leave_dialog):
		return
	_leave_dialog = UI.confirm(self, "Leave the campaign?",
			"You'll go back to the menu. Chapters you've finished stay done.",
			"Keep going", "Leave", func(): finished.emit())


## When a new step starts, the camera glides to show what it's about (in
## case the player had wandered off).
func _bring_into_view() -> void:
	var points: Array = []
	for t in _targets():
		if t.has("world"):
			points.append(Vector2(t.world.x, t.world.z))
	var leaves: Array = panes._leaves()
	if points.is_empty() or leaves.is_empty():
		return
	var leaf = leaves[0]
	var cam: Camera3D = leaf.camera
	var view: Rect2 = Rect2(Vector2.ZERO, leaf.rect.size).grow(-60.0 * UI.ui_scale())
	view.position.y += leaf.rect.size.y * 0.22  # below the card
	view.size.y -= leaf.rect.size.y * 0.22
	var all_in := true
	for p in points:
		all_in = all_in and view.has_point(cam.unproject_position(Vector3(p.x, sim.field.height_at(p), p.y)))
	if all_in:
		return
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	box = box.grow(25.0)
	var px: Vector2 = leaf.rect.size
	var upp: float = maxf(cam.units_per_pixel, maxf(box.size.x / px.x, box.size.y / (px.y * 0.62)))
	upp = minf(upp, cam.max_units_per_pixel)
	var c: Vector2 = box.get_center()
	var goal := Vector3(c.x, 0, c.y - px.y * 0.14 * upp)
	var from_target: Vector3 = cam.target
	var from_upp: float = cam.units_per_pixel
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float):
		cam.target = from_target.lerp(goal, k)
		cam.units_per_pixel = lerpf(from_upp, upp, k)
		cam.refit(), 0.0, 1.0, 0.7)


# --- Enemies ------------------------------------------------------------------------

func _wave_scissors() -> void:
	_wave([2, 2, 2], true)


func _wave_papers() -> void:
	_wave([1, 1, 1], true)


func _wave_rocks() -> void:
	_wave([0, 0, 0], true)


func _wave_mixed() -> void:
	_wave([0, 1, 2, 0, 1, 2], true)


func _wave_raid() -> void:
	_wave([0, 1, 2], false)


## Enemies of these kinds show up a little way from your base. Waiting
## (`hold`) for you to come, or marching on your HQ. Your army is healed
## and topped up to three of each kind first.
func _wave(kinds: Array, hold: bool) -> void:
	var team: int = game.player_team
	var hq: Dictionary = sim.hq_of(team)
	if hq.is_empty():
		return
	var home := Vector2(hq.x, hq.z) / float(sim.SCALE)
	for u in sim.units:
		if u.team == team:
			u.hp = sim.MAX_HP
	for kind in 3:
		for i in maxi(0, 3 - _count_kind(kind)):
			sim.add_unit(team, kind, _open_near(home + Vector2(18, 10 + i * 6)))
	var towards: Vector2 = (sim.field.get_center() - home).normalized()
	# Out past your army (beyond its sight), so the fight starts when you
	# send the right hands, not by itself.
	var start: Vector2 = home + towards * 125.0
	_enemies.clear()
	for i in kinds.size():
		var at: Vector2 = start + towards.orthogonal() * (i - (kinds.size() - 1) * 0.5) * 8.0
		var id: int = sim.add_unit(1 - team, kinds[i], _open_near(at))
		_enemies.append(id)
		if hold:
			sim.get_unit(id).hold = true
	if not hold:
		sim.command_attack_move(_enemies, Vector3(home.x, 0, home.y) + Vector3(towards.x, 0, towards.y) * 20.0)
	if Campaign.map_of(chapter) == "training":
		_frame_base([start])  # your base and them, both on screen


func _open_near(p: Vector2) -> Vector2:
	var grid = sim.nav()
	if grid == null:
		return p
	var cell: Vector2i = grid.nearest_walkable(grid.cell_of(roundi(p.x * sim.SCALE), roundi(p.y * sim.SCALE)))
	return Vector2(grid.cell_centre(cell)) / float(sim.SCALE)


func _enemies_beaten() -> bool:
	for id in _enemies:
		if not sim.get_unit(id).is_empty():
			return false
	return not _enemies.is_empty()
