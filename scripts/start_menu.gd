extends Control
## The start screen: the tutorial, play the computer, or play a friend online with a
## 4-digit room code (create one, or type theirs on the number pad, so the
## phone keyboard never pops up).
##
## Emits vs_computer, or online_ready(session, seat) once both players are in.

signal vs_computer
signal tutorial
signal online_ready(session: Node, seat: int)

const UI := preload("res://scripts/ui_style.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const CODE_LENGTH := 4
const BuildInfo := preload("res://scripts/build_info.gd")
const LOGO := preload("res://assets/ui/logo.png")
const Maps := preload("res://scripts/maps.gd")
const MatchSetup := preload("res://scripts/match_setup.gd")
const Settings := preload("res://scripts/settings.gd")
const Field := preload("res://scripts/field.gd")
const Changelog := preload("res://scripts/changelog.gd")
const DIFFICULTY_NAMES := {"easy": "Easy", "normal": "Normal", "hard": "Hard"}

var _header: VBoxContainer     # the logo
var _logo: TextureRect
var _main: VBoxContainer       # the three big choices
var _join: VBoxContainer       # number pad
var _wait: VBoxContainer       # "your code is ..." / "joining ..."
var _setup: VBoxContainer      # map (and difficulty) before a game
var _setup_title: Label
var _setup_go: Button
var _difficulty_row: HBoxContainer
var _map_cards := {}           # map id -> Button
var _difficulty_buttons := {}  # "easy"... -> Button
var _setup_for := ""           # "computer" or "online"
var _code_label: Label
var _status: Label
var _wait_title: Label
var _wait_text: Label
var _typed := ""
var _session: Node = null
## Plays a sample sound (set by the game) when the effects volume changes.
var preview_sfx: Callable = func(): pass
var _update_button: Button
var _version_label: Label
var _checking_update := false
var news_window: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = Color(0.93, 0.97, 0.9, 0.94)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 26)
	add_child(column)
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 20)
	column.add_child(_header)
	# The logo (assets/ui/logo.png, made by tools/make_logo.py), as wide as fits.
	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header.add_child(_logo)
	_fit_logo()
	resized.connect(_fit_logo)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 18)
	_main.add_child(_big_button("Tutorial", Color("#fbf1d6"), func(): tutorial.emit()))
	_main.add_child(_big_button("Play vs Computer", Color("#e7e1f5"), func(): _open_setup("computer")))
	_main.add_child(_big_button("Create Online Game", Color("#fbe3ea"), func(): _open_setup("online")))
	_main.add_child(_big_button("Join Online Game", Color("#d3ece8"), func(): _show(_join)))
	column.add_child(_main)

	_join = VBoxContainer.new()
	_join.add_theme_constant_override("separation", 14)
	var ask := UI.label("Type your friend's code", 34)
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join.add_child(ask)
	_code_label = UI.label("_ _ _ _", 72)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join.add_child(_code_label)
	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 12)
	pad.add_theme_constant_override("v_separation", 12)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "Join"]:
		var b := UI.button(Color(1, 1, 1, 0.9), Color("#e7e1f5"), 40)
		b.text = key
		if key == "⌫":
			# (The font has no such character: a drawn back arrow instead.)
			b.text = ""
			b.icon = _back_arrow()
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.tooltip_text = "Delete"
		b.custom_minimum_size = Vector2(130, 88) * UI.ui_scale()
		b.pressed.connect(_on_key.bind(key))
		pad.add_child(b)
	var pad_row := HBoxContainer.new()
	pad_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad_row.add_child(pad)
	_join.add_child(pad_row)
	var back_button := _big_button("Back", Color(1, 1, 1, 0.9), _back)
	back_button.custom_minimum_size = Vector2(414, 80) * UI.ui_scale()
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_join.add_child(back_button)
	column.add_child(_join)

	_build_setup(column)

	_wait = VBoxContainer.new()
	_wait.add_theme_constant_override("separation", 18)
	_wait_title = UI.label("", 44)
	_wait_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.add_child(_wait_title)
	_wait_text = UI.label("", 96)
	_wait_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.add_child(_wait_text)
	_wait.add_child(_big_button("Cancel", Color(1, 1, 1, 0.9), _back))
	column.add_child(_wait)

	var gear := UI.settings_button(self, 24, func(): preview_sfx.call())
	if OS.has_feature("android") or OS.has_feature("ios"):
		gear.offset_right = -24

	# Full screen from the start (browsers only allow it from a tap).
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		var full := UI.button(Color(1, 1, 1, 0.85), Color("#e7e1f5"))
		full.icon = UI.fullscreen_icon()
		full.custom_minimum_size = Vector2(72, 72) * UI.ui_scale()
		full.anchor_left = 1.0
		full.anchor_right = 1.0
		full.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		full.offset_top = 24
		full.offset_right = -24
		full.pressed.connect(func():
			var on: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN))
		add_child(full)

	# Version, and an update button when the website has a newer one (the
	# installed web app keeps a saved copy, which can lag behind).
	var bottom := VBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_update_button = _big_button("New version: tap to update", Color("#fbe3ea"), _update_now)
	_update_button.visible = false
	bottom.add_child(_update_button)
	var version_row := HBoxContainer.new()
	version_row.alignment = BoxContainer.ALIGNMENT_CENTER
	version_row.add_theme_constant_override("separation", 14)
	_version_label = UI.label("version " + BuildInfo.VERSION, 20)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_row.add_child(_version_label)
	var news := UI.button(Color("#fff3b0"), Color("#ffe9a0"), 20)
	news.text = "What's new"
	news.pressed.connect(show_news)
	version_row.add_child(news)
	bottom.add_child(version_row)
	add_child(bottom)
	_check_for_update()

	# Something new since you last looked: show it once.
	if Settings.get_choice("seen_news", "") != Changelog.latest_id() and get_tree().get_script() == null:
		show_news.call_deferred()

	_status = UI.label("", 28)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("#c0506a"))
	column.add_child(_status)
	_show(_main)


## The logo: up to 1100 px wide, at most 90% of the screen's width and a
## third of its height (the buttons need the rest).
func _fit_logo() -> void:
	if _logo == null:
		return
	var screen: Vector2 = get_viewport_rect().size
	var aspect: float = float(LOGO.get_height()) / LOGO.get_width()
	var w: float = minf(minf(1100.0, screen.x * 0.9), screen.y * 0.34 / aspect)
	_logo.custom_minimum_size = Vector2(w, w * aspect)


## The "What's new" window: every update, newest first. Marks it seen.
func show_news() -> void:
	if is_instance_valid(news_window):
		return
	Settings.set_choice("seen_news", Changelog.latest_id())
	var s: float = UI.ui_scale()
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.2, 0.35, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.add_to_group("modal")
	news_window = shade
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_box(Color(1, 1, 1, 0.97)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(14 * s))
	panel.add_child(column)
	var title := UI.label("What's new", roundi(48 * s))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var scroll := ScrollContainer.new()
	var screen: Vector2 = get_viewport_rect().size
	scroll.custom_minimum_size = Vector2(minf(980.0, screen.x * 0.86), minf(720.0, screen.y * 0.62))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", roundi(10 * s))
	scroll.add_child(list)
	for entry in Changelog.ENTRIES:
		var head := UI.label("%s  ·  %s" % [entry.title, entry.date], roundi(32 * s))
		head.add_theme_color_override("font_color", Color("#b0607a"))
		list.add_child(head)
		for item in entry.items:
			var line := UI.label("•  " + item, roundi(24 * s))
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = scroll.custom_minimum_size.x - 40
			list.add_child(line)
		var gap := Control.new()
		gap.custom_minimum_size.y = 10 * s
		list.add_child(gap)
	var done := UI.button(Color("#e7e1f5"), Color("#d6cdef"), 30)
	done.text = "Got it"
	done.custom_minimum_size.x = 240 * s
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(func(): shade.queue_free())
	column.add_child(done)
	news_window.set_meta("done", done)
	news_window.set_meta("list", list)


## Web only: asks the website (not the saved copy) which version is current.
func _check_for_update() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge") or BuildInfo.VERSION == "dev":
		return
	JavaScriptBridge.eval("""window.__whLatest = undefined;
		fetch('version.txt?t=' + Date.now(), {cache: 'no-store'})
			.then(r => r.ok ? r.text() : '').then(t => window.__whLatest = t.trim())
			.catch(() => window.__whLatest = '');""", true)
	_checking_update = true


func _process(_delta: float) -> void:
	if not _checking_update:
		return
	var latest: Variant = JavaScriptBridge.eval("window.__whLatest === undefined ? null : window.__whLatest", true)
	if latest == null:
		return
	_checking_update = false
	if latest is String and latest != "" and latest != BuildInfo.VERSION:
		_update_button.visible = true
		_version_label.text = "version %s  ·  newest %s" % [BuildInfo.VERSION, latest]


## Drops the saved copy of the game and loads the newest from the website.
func _update_now() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""(async () => {
		try {
			if (navigator.serviceWorker) {
				for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
			}
			if (window.caches) {
				for (const k of await caches.keys()) await caches.delete(k);
			}
		} finally { location.reload(); }
	})();""", true)


## A backspace key picture: an arrow-shaped tag pointing left, with an x.
static func _back_arrow() -> ImageTexture:
	var w := 96
	var h := 64
	var k := 4  # drawn big, then shrunk (smooth edges)
	var outline := PackedVector2Array([Vector2(4, 32), Vector2(30, 6), Vector2(90, 6), Vector2(90, 58), Vector2(30, 58)])
	var img := Image.create(w * k, h * k, false, Image.FORMAT_RGBA8)
	var ink := Color("#4a4560")
	for y in h * k:
		for x in w * k:
			var p := Vector2(x + 0.5, y + 0.5) / k
			var inside: bool = Geometry2D.is_point_in_polygon(p, outline)
			if not inside:
				continue
			# Hollow tag: ink near the edge only.
			var edge := 99.0
			for i in outline.size():
				var a: Vector2 = outline[i]
				var b: Vector2 = outline[(i + 1) % outline.size()]
				edge = minf(edge, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
			# The x in the middle.
			var c := Vector2(58, 32)
			var d: Vector2 = p - c
			var on_x: bool = absf(absf(d.x) - absf(d.y)) < 4.2 and absf(d.x) < 12 and absf(d.y) < 12
			if edge < 5.5 or on_x:
				img.set_pixel(x, y, ink)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _big_button(text: String, color: Color, action: Callable) -> Button:
	var b := UI.button(color, color.darkened(0.12), 38)
	b.text = text
	b.custom_minimum_size = Vector2(460, 100) * UI.ui_scale()
	b.pressed.connect(action)
	return b


func _show(part: Control) -> void:
	for p in [_main, _join, _wait, _setup]:
		p.visible = p == part
	_header.visible = part != _join and part != _setup  # these need the room
	_status.text = ""
	if part == _join:
		_typed = ""
		_refresh_code()


func _back() -> void:
	if _session != null:
		_session.leave()
		_session.queue_free()
		_session = null
	_show(_main)


# --- Match setup: map, difficulty ---------------------------------------------

func _build_setup(column: VBoxContainer) -> void:
	var s: float = UI.ui_scale()
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override("separation", roundi(16 * s))
	_setup_title = UI.label("", 52)
	_setup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup.add_child(_setup_title)
	var map_label := UI.label("Map", 30)
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup.add_child(map_label)
	var maps := HBoxContainer.new()
	maps.alignment = BoxContainer.ALIGNMENT_CENTER
	maps.add_theme_constant_override("separation", roundi(14 * s))
	for id in Maps.ORDER:
		var card := _map_card(id)
		maps.add_child(card)
		_map_cards[id] = card
	_setup.add_child(maps)
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_difficulty_row.add_theme_constant_override("separation", roundi(12 * s))
	var diff_label := UI.label("Difficulty", 30)
	diff_label.custom_minimum_size.x = 170 * s
	_difficulty_row.add_child(diff_label)
	for d in MatchSetup.DIFFICULTIES:
		var b := UI.button(Color(1, 1, 1, 0.9), Color("#d6cdef"), 30)
		b.text = DIFFICULTY_NAMES[d]
		b.custom_minimum_size = Vector2(150, 76) * s
		b.pressed.connect(func(): _pick_difficulty(d))
		_difficulty_row.add_child(b)
		_difficulty_buttons[d] = b
	_setup.add_child(_difficulty_row)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", roundi(16 * s))
	var back := _big_button("Back", Color(1, 1, 1, 0.9), _back)
	back.custom_minimum_size = Vector2(220, 90) * s
	row.add_child(back)
	_setup_go = _big_button("Start", Color("#d3ecbf"), _setup_confirmed)
	_setup_go.custom_minimum_size = Vector2(300, 90) * s
	row.add_child(_setup_go)
	_setup.add_child(row)
	column.add_child(_setup)


## A map choice: its name and a little picture of the island.
func _map_card(id: String) -> Button:
	var s: float = UI.ui_scale()
	var m: Dictionary = Maps.MAPS[id]
	var b := UI.button(Color(1, 1, 1, 0.9), Color("#fff3b0"), 26)
	b.custom_minimum_size = Vector2(250, 330) * s
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 10 * s
	box.offset_bottom = -18 * s  # clear of the raised edge
	box.add_theme_constant_override("separation", roundi(6 * s))
	var pic := Control.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.custom_minimum_size = Vector2(190, 190) * s
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.draw.connect(func(): _draw_map_preview(pic, id))
	box.add_child(pic)
	var name := UI.label(m.name, roundi(28 * s))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var blurb := UI.label(m.blurb, roundi(18 * s))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 220 * s
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(blurb)
	b.add_child(box)
	b.pressed.connect(func(): _pick_map(id))
	return b


## Island outlines for the previews, worked out once per map.
static var _previews := {}


func _draw_map_preview(pic: Control, id: String) -> void:
	if not _previews.has(id):
		var was_built: String = MatchSetup.built_map
		var f: Node3D = Field.new()
		f.map_id = id
		f.build()
		var hq: Vector2 = f.get_center() + Vector2(f.hq_offset)
		_previews[id] = {"coast": f.coastline, "lakes": f.lakes, "plateaus": f.plateaus,
				"forests": f.forests.map(func(x): return [x.center, x.radius]),
				"hqs": [hq, 2.0 * f.get_center() - hq], "size": f.map_size.x}
		MatchSetup.built_map = was_built  # (only the scene's own field counts)
		f.free()
	var p: Dictionary = _previews[id]
	var side: float = pic.size.x
	var k: float = side / p.size
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#b9e3f0")
	box.set_corner_radius_all(roundi(side * 0.1))
	pic.draw_style_box(box, Rect2(Vector2.ZERO, pic.size))
	var scaled := func(poly: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in poly:
			out.append(q * k)
		return out
	pic.draw_colored_polygon(scaled.call(p.coast), Color("#c3e6ad"))
	for poly in p.plateaus:
		pic.draw_colored_polygon(scaled.call(poly), Color("#d3ecbf"))
	for poly in p.lakes:
		pic.draw_colored_polygon(scaled.call(poly), Color("#8ec8e3"))
	for f in p.forests:
		pic.draw_circle(f[0] * k, f[1] * k, Color("#9fd18a"))
	var colors := [Color("#ff7f9a"), Color("#6fb6ff")]
	for i in 2:
		var c: Vector2 = p.hqs[i] * k
		pic.draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color("#5f5873"))
		pic.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), colors[i])


func _open_setup(what: String) -> void:
	_setup_for = what
	_setup_title.text = "Play vs Computer" if what == "computer" else "Create Online Game"
	_setup_go.text = "Start" if what == "computer" else "Create"
	_difficulty_row.visible = what == "computer"
	MatchSetup.difficulty = Settings.get_choice("difficulty", "normal")
	_show(_setup)
	_pick_map(MatchSetup.map)
	_pick_difficulty(MatchSetup.difficulty)


func _pick_map(id: String) -> void:
	MatchSetup.map = id
	for other in _map_cards:
		_highlight(_map_cards[other], other == id)


func _pick_difficulty(d: String) -> void:
	MatchSetup.difficulty = d
	Settings.set_choice("difficulty", d)
	for other in _difficulty_buttons:
		_highlight(_difficulty_buttons[other], other == d)


## The picked choice: a warm fill and a thick border.
func _highlight(b: Button, on: bool) -> void:
	if on:
		UI.set_button_color(b, Color("#fff3b0"), Color("#ffe9a0"), Color("#d08a2e"))
	else:
		UI.set_button_color(b, Color(1, 1, 1, 0.95), Color("#d6cdef"))


func _setup_confirmed() -> void:
	if _setup_for == "computer":
		vs_computer.emit()
	else:
		_create()


## A session to the server, or null (and a message) if there isn't one.
func _new_session() -> Node:
	var url: String = NetSession.server_url()
	if url == "":
		_show(_main)
		_status.text = "Online play isn't set up yet (no game server)."
		return null
	_session = NetSession.new()
	_session.map = MatchSetup.map
	add_child(_session)
	_session.failed.connect(func(message):
		var keep := _status
		_back()
		keep.text = message)
	_session.started.connect(func(seat):
		var session: Node = _session
		_session = null
		remove_child(session)
		online_ready.emit(session, seat))
	_session.connect_to(url)
	return _session


func _create() -> void:
	var session := _new_session()
	if session == null:
		return
	_show(_wait)
	_wait_title.text = "Connecting…"
	_wait_text.text = ""
	session.created.connect(func(code):
		_wait_title.text = "Your game code — tell your friend:"
		_wait_text.text = code)
	session.create_room()


func _on_key(key: String) -> void:
	if key == "⌫":
		_typed = _typed.left(-1) if _typed != "" else ""
	elif key == "Join":
		if _typed.length() == CODE_LENGTH:
			var session := _new_session()
			if session == null:
				return
			_show(_wait)
			_wait_title.text = "Joining game"
			_wait_text.text = _typed
			session.join_room(_typed)
			return
	elif _typed.length() < CODE_LENGTH:
		_typed += key
	_refresh_code()


func _refresh_code() -> void:
	var shown := ""
	for i in CODE_LENGTH:
		shown += (_typed[i] if i < _typed.length() else "_") + (" " if i < CODE_LENGTH - 1 else "")
	_code_label.text = shown
