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

var _header: VBoxContainer     # title, subtitle, hands
var _main: VBoxContainer       # the three big choices
var _join: VBoxContainer       # number pad
var _wait: VBoxContainer       # "your code is ..." / "joining ..."
var _code_label: Label
var _status: Label
var _wait_title: Label
var _wait_text: Label
var _typed := ""
var _session: Node = null
var _update_button: Button
var _version_label: Label
var _checking_update := false


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
	var title := UI.label("Warring Hands", 96)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_child(title)
	var subtitle := UI.label("Childhood Game Gone Aggro", 34)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_child(subtitle)
	var hands := HBoxContainer.new()
	hands.alignment = BoxContainer.ALIGNMENT_CENTER
	for kind in 3:
		var icon := TextureRect.new()
		icon.texture = UI.kind_icon(kind)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(110, 110)
		hands.add_child(icon)
	_header.add_child(hands)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 18)
	_main.add_child(_big_button("Tutorial", Color("#fbf1d6"), func(): tutorial.emit()))
	_main.add_child(_big_button("Play vs Computer", Color("#e7e1f5"), func(): vs_computer.emit()))
	_main.add_child(_big_button("Create Online Game", Color("#fbe3ea"), _create))
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
	_version_label = UI.label("version " + BuildInfo.VERSION, 20)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_version_label)
	add_child(bottom)
	_check_for_update()

	_status = UI.label("", 28)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("#c0506a"))
	column.add_child(_status)
	_show(_main)


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


func _big_button(text: String, color: Color, action: Callable) -> Button:
	var b := UI.button(color, color.darkened(0.12), 38)
	b.text = text
	b.custom_minimum_size = Vector2(460, 100) * UI.ui_scale()
	b.pressed.connect(action)
	return b


func _show(part: Control) -> void:
	for p in [_main, _join, _wait]:
		p.visible = p == part
	_header.visible = part != _join  # the pad needs the room
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


## A session to the server, or null (and a message) if there isn't one.
func _new_session() -> Node:
	var url: String = NetSession.server_url()
	if url == "":
		_show(_main)
		_status.text = "Online play isn't set up yet (no game server)."
		return null
	_session = NetSession.new()
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
