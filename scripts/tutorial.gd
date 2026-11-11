extends Control
## Tutorial mode: one step at a time, on a card at the top of the screen.
## Each step moves on when the player has done it (or taps Skip). Your army
## alone on the island at first; enemies show up for the last lesson.
##
## Started by game_controller.gd from the start menu.

signal finished

const UI := preload("res://scripts/ui_style.gd")

var game: Node
var sim: Node
var panes: Control
var hud: Control

var step := -1
var _card: PanelContainer
var _count: Label
var _text: Label
var _skip: Button
var _done_buttons: HBoxContainer
var _quit: Button
## After the last step: the card shrinks to just "Quit tutorial" and you
## keep playing on the island.
var free_play := false
var _camera_start := {}      # where each pane's camera was when the step began
var _enemies: Array = []     # the last lesson's enemies


## Each step: text, and how it's done:
##   "on": a player action (game_controller `did`), or
##   "poll": a method name checked every frame, or
##   "next": just a Next button (a tip).
## "enter" (optional): a method run when the step starts.
var STEPS: Array = [
	{"text": "Welcome to Warring Hands!\nFor the best experience, hold your device sideways (landscape).", "next": true},
	{"text": "Tap one of your hands to select it.", "on": ["select", "lasso", "select_kind"]},
	{"text": "Draw a loop around several hands with one finger to select them all.", "on": ["lasso"]},
	{"text": "Tap the ground to send them there.\nTo unselect, tap the screen with two fingers at once (mouse: right click).", "on": ["move", "attack_move"]},
	{"text": "Hold: with hands selected, press the stop-sign button on the left (under the sword). They stop and stay put, and only fight what comes within reach.", "on": ["hold"]},
	{"text": "Queue: keep a finger on the 1-2-3 button (or hold Shift) and tap a few places: your hands go to each in turn. Hold cancels the plan.", "on": ["queue"]},
	{"text": "Move the camera: drag with two fingers, pinch to zoom.\n(Mouse: right-drag to move, wheel to zoom.)", "poll": "_camera_moved", "enter": "_note_cameras"},
	{"text": "Double tap a hand: every hand of that kind on screen gets selected.", "on": ["select_kind"]},
	{"text": "Gather: with hands selected, tap your HQ (the town hall).\nRocks dig stone, papers cut wood, scissors mine metal.", "on": ["harvest", "gather"]},
	{"text": "Build: tap the hammer button (on the left), pick Quarry, then touch open ground inside the circles (drag to adjust, lift to build).", "on": ["build_quarry", "build_mill", "build_forge"]},
	{"text": "Train: when your factory is finished, tap it and press + to make a new hand.\nNew hands go gathering by themselves.", "on": ["train"]},
	{"text": "Split the screen: grab the white tab on a side of the screen and swipe across.\nEach pane has its own camera.", "poll": "_split_done"},
	{"text": "Drag the divider between the panes all the way to an edge to merge them again.", "poll": "_merged_done"},
	{"text": "Enemies are coming! Rock beats scissors, scissors beat paper, paper beats rock.\nSelect your army, tap the sword button (on the left), then tap near the enemies.", "poll": "_enemies_beaten", "enter": "_send_enemies"},
	{"text": "Well done! You know the basics.\nDouble tap a damaged building to repair it, and build more HQs anywhere.", "end": true},
]


func setup(game_controller: Node, simulation: Node, pane_layout: Control, hud_control: Control) -> void:
	game = game_controller
	sim = simulation
	panes = pane_layout
	hud = hud_control
	game.did.connect(_on_did)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UI.panel_box(Color(1, 1, 1, 0.92)))
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 16
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_card.add_child(column)
	_count = UI.label("", 20)
	column.add_child(_count)
	_text = UI.label("", 28)
	_text.custom_minimum_size = Vector2(620, 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_skip = UI.button(Color("#f2eefb"), Color("#e7e1f5"), 22)
	_skip.text = "Skip"
	_skip.custom_minimum_size = Vector2(120, 56) * UI.ui_scale()
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_skip.pressed.connect(_on_skip)
	row.add_child(_skip)
	var quit := UI.button(Color("#f2eefb"), Color("#e7e1f5"), 22)
	_quit = quit
	quit.text = "Quit tutorial"
	quit.custom_minimum_size = Vector2(170, 56) * UI.ui_scale()
	quit.pressed.connect(func(): finished.emit())
	row.add_child(quit)
	_done_buttons = row
	column.add_child(row)
	next_step()


func card() -> Control:
	return _card


## Skip / Next, or on the last step, Continue Tutorial: close the lesson card
## and keep playing (only a small Quit tutorial button stays, to leave).
func _on_skip() -> void:
	if step >= 0 and step < STEPS.size() and STEPS[step].get("end", false):
		free_play = true
		_count.visible = false
		_text.visible = false
		_skip.visible = false
		_quit.text = "Quit tutorial"
		_card.offset_left = 0
		_card.offset_right = 0
		_card.reset_size()
		return
	next_step()


func next_step() -> void:
	step += 1
	if step >= STEPS.size():
		finished.emit()
		return
	var s: Dictionary = STEPS[step]
	_count.text = "Tutorial  ·  step %d of %d" % [step + 1, STEPS.size()]
	_text.text = s.text
	_skip.text = "Continue Tutorial" if s.get("end", false) else ("Next" if s.get("next", false) else "Skip")
	if s.has("enter"):
		call(s.enter)
	# A little bounce so the new instruction gets noticed.
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2.ONE * 1.06
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT)


func _on_did(action: String) -> void:
	if step < 0 or step >= STEPS.size():
		return
	var s: Dictionary = STEPS[step]
	if s.has("on") and action in s.on:
		if action == "lasso" and s.on == ["lasso"] and game.selection.size() < 2:
			return  # a loop around just one hand doesn't count here
		next_step()


func _process(_delta: float) -> void:
	if step < 0 or step >= STEPS.size():
		return
	var s: Dictionary = STEPS[step]
	if s.has("poll") and call(s.poll):
		next_step()


# --- Step helpers ---------------------------------------------------------------

func _note_cameras() -> void:
	_camera_start.clear()
	for leaf in panes._leaves():
		_camera_start[leaf.camera] = [leaf.camera.target, leaf.camera.units_per_pixel]


func _camera_moved() -> bool:
	for leaf in panes._leaves():
		var start: Array = _camera_start.get(leaf.camera, [])
		if start.is_empty():
			continue
		if leaf.camera.target.distance_to(start[0]) > 8.0 or absf(leaf.camera.units_per_pixel - start[1]) > start[1] * 0.15:
			return true
	return false


func _split_done() -> bool:
	return panes.pane_count() >= 2


func _merged_done() -> bool:
	return panes.pane_count() == 1


## A few enemies walk up to your base: one of each kind.
func _send_enemies() -> void:
	var hq: Dictionary = sim.hq_of(game.player_team)
	if hq.is_empty():
		return
	var home := Vector2(hq.x, hq.z) / float(sim.SCALE)
	var towards: Vector2 = (Vector2(410, 410) - home).normalized()
	var start: Vector2 = home + towards * 75.0
	var grid = sim.nav()
	_enemies.clear()
	for kind in 3:
		var at: Vector2 = start + towards.orthogonal() * (kind - 1) * 8.0
		if grid != null:
			var cell: Vector2i = grid.nearest_walkable(grid.cell_of(roundi(at.x * sim.SCALE), roundi(at.y * sim.SCALE)))
			at = Vector2(grid.cell_centre(cell)) / float(sim.SCALE)
		_enemies.append(sim.add_unit(1 - game.player_team, kind, at))
	sim.command_attack_move(_enemies, Vector3(home.x, 0, home.y) + Vector3(towards.x, 0, towards.y) * 25.0)


func _enemies_beaten() -> bool:
	for id in _enemies:
		if not sim.get_unit(id).is_empty():
			return false
	return not _enemies.is_empty()
