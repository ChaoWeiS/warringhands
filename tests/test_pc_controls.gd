extends SceneTree
## Playing on a computer: the campaign speaks of clicks and keys (not taps
## and fingers) when a mouse is in use, and switches back for touch; A
## switches Attack mode, H is Hold and Shift queues; the buttons show
## their keys.
## Run: godot --headless -s res://tests/test_pc_controls.gd

const Campaign := preload("res://scripts/campaign.gd")
const MatchSetup := preload("res://scripts/match_setup.gd")
const UI := preload("res://scripts/ui_style.gd")
const TOUCH_WORDS := ["tap", "finger", "pinch", "swipe"]

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	create_timer(120.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func has_touch_words(text: String) -> bool:
	var low := text.to_lower()
	for w in TOUCH_WORDS:
		if low.contains(w):
			return true
	return false


func key(code: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _run() -> void:
	# Every step that talks about touch has words for a mouse too, and those
	# don't mention touch.
	var missing: Array = []
	var leaky: Array = []
	for c in Campaign.CHAPTERS.size():
		for s in Campaign.CHAPTERS[c].steps:
			for field in ["text", "holding_text"]:
				if s.has(field) and has_touch_words(s[field]):
					if not s.has("pc_" + field):
						missing.append("%d: %s" % [c + 1, s[field].left(40)])
				if s.has("pc_" + field) and has_touch_words(s["pc_" + field]):
					leaky.append("%d: %s" % [c + 1, s["pc_" + field].left(40)])
	check("every touch instruction has a mouse version %s" % [missing], missing.is_empty())
	check("...which talks about clicks, not taps or fingers %s" % [leaky], leaky.is_empty())

	# Telling a mouse from a finger.
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	UI.mouse_mode = true
	UI.note_input(touch)
	check("a finger on the screen switches to touch", not UI.mouse_mode)
	var fake := InputEventMouseButton.new()
	fake.device = InputEvent.DEVICE_ID_EMULATION
	fake.pressed = true
	UI.note_input(fake)
	check("...the pretend mouse click a finger also makes doesn't switch back", not UI.mouse_mode)
	var click := InputEventMouseButton.new()
	click.pressed = true
	UI.note_input(click)
	check("a real mouse click switches to mouse", UI.mouse_mode)
	var pretend_touch := InputEventScreenTouch.new()
	pretend_touch.device = InputEvent.DEVICE_ID_EMULATION
	pretend_touch.pressed = true
	UI.note_input(pretend_touch)
	check("...and the pretend touch a mouse click makes doesn't switch back", UI.mouse_mode)

	# Chapter 1 with a mouse.
	MatchSetup.map = Campaign.map_of(0)
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	for c in root.get_node("Main/HUD").get_children():
		if c.has_signal("vs_computer"):
			c.queue_free()
	var tut: Control = game.start_tutorial(0)
	sim.set_process(false)
	await frames(2)
	tut.next_step()
	tut.next_step()  # "Move the camera"
	await frames(2)
	check("with a mouse, the camera step says right button (%s)" % tut._text.text,
			tut._text.text.contains("right mouse button"))
	UI.mouse_mode = false
	await frames(2)
	check("a finger: it says drag with one finger, and nothing about a mouse",
			tut._text.text.contains("one finger") and not tut._text.text.to_lower().contains("mouse"))
	UI.mouse_mode = true
	while tut.step < tut.steps.size() and tut.steps[tut.step].get("on", []) != ["lasso"]:
		tut.next_step()
	await frames(2)
	var targets: Array = tut._targets()
	check("the loop step with a mouse doesn't point at the Group button",
			targets.size() == 1 and not targets[0].has("ui"))
	UI.mouse_mode = false
	await frames(1)
	check("...with touch it does", tut._targets().any(func(t): return t.has("ui")))
	UI.mouse_mode = true

	# Keys. Select some hands first.
	var ids: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	game._select(ids)
	await frames(2)
	var bar: Node = game.bar
	tut.free_play = true
	tut._tools = ["minimap", "attack", "hold", "queue"]
	await frames(2)
	check("Attack and Hold show their keys (A, H) when using a mouse",
			bar._key_badges.size() == 3 and bar._key_badges.all(func(k): return k.visible)
			and bar._key_badges[0].text == "A" and bar._key_badges[1].text == "H")
	key(KEY_A)
	await frames(1)
	key(KEY_A, false)
	await frames(1)
	check("A switches Attack mode on", bar.is_attack_armed())
	key(KEY_A)
	await frames(1)
	key(KEY_A, false)
	await frames(1)
	check("...and off again", not bar.is_attack_armed())
	var holds := [0]
	game.did.connect(func(what): if what == "hold": holds[0] += 1)
	key(KEY_H)
	await frames(1)
	key(KEY_H, false)
	await frames(1)
	check("H holds the selected hands", holds[0] == 1)
	UI.mouse_mode = false
	await frames(1)
	check("with touch, the key labels are hidden", bar._key_badges.all(func(k): return not k.visible))

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
