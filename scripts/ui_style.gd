extends RefCounted
## Shared look for on-screen buttons and icons (pastel, rounded, big enough
## for fingers).

const TEXT_COLOR := Color("#4a4560")
## Buttons on phones are this much bigger.
const PHONE_SCALE := 1.35
const ATLAS := preload("res://assets/units/hands.png")
const CELL := 192
## Each kind's icon: which idle frame, and the hand picture inside that atlas
## cell. Paper uses its 4th frame: the others are drawn with an extra finger.
const ICON_FRAME := [0, 3, 0]
const ICON_INSET := [Rect2(40, 52, 112, 126), Rect2(40, 35, 112, 126), Rect2(40, 52, 112, 126)]
## Resource colours: stone, wood, metal.
const RES_COLORS := [Color("#b9b2cc"), Color("#cf9f74"), Color("#8fd6d0")]
const RES_ICONS := [
	preload("res://assets/env/icon_stone.png"),
	preload("res://assets/env/icon_wood.png"),
	preload("res://assets/env/icon_metal.png"),
]
const RES_NAMES := ["stone", "wood", "metal"]
const BUILDING_NAMES := {"hq": "HQ", "quarry": "Quarry", "mill": "Paper Mill", "forge": "Forge"}



## Tests can pretend to be a phone (1) or not (0); -1 = detect.
static var phone_override := -1
static var _phone_cache := -1


## Is this a phone (small screen)? Buttons get bigger there.
static func is_phone() -> bool:
	if phone_override >= 0:
		return phone_override == 1
	if _phone_cache < 0:
		var small := false
		if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
			# Shorter side of the screen in CSS pixels: phones ~360-430.
			var side: Variant = JavaScriptBridge.eval("Math.min(screen.width, screen.height)", true)
			small = (side is int or side is float) and float(side) < 560.0
		elif OS.has_feature("mobile"):
			var px: Vector2i = DisplayServer.screen_get_size()
			small = mini(px.x, px.y) / float(maxi(DisplayServer.screen_get_dpi(), 1)) < 3.6  # inches
		_phone_cache = 1 if small else 0
	return _phone_cache == 1


## How much bigger buttons are on this device.
static func ui_scale() -> float:
	return PHONE_SCALE if is_phone() else 1.0


static func button(color: Color, pressed_color: Color = Color.TRANSPARENT, font_size: int = 30) -> Button:
	var b := Button.new()
	var s := ui_scale()
	b.custom_minimum_size = Vector2(0, roundf(84 * s))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", roundi(font_size * s))
	b.add_theme_constant_override("icon_max_width", roundi(60 * s))
	b.add_theme_constant_override("h_separation", 8)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(state, TEXT_COLOR if state != "font_disabled_color" else Color(TEXT_COLOR, 0.45))
	set_button_color(b, color, pressed_color)
	return b


## Gives a button the plaque look in a colour (and its pressed colour).
## `outline` other than the usual brown marks a picked choice.
static func set_button_color(b: Button, color: Color, pressed_color: Color = Color.TRANSPARENT,
		outline: Color = OUTLINE) -> void:
	var down: Color = pressed_color if pressed_color.a > 0.0 else color.darkened(0.08)
	b.add_theme_stylebox_override("normal", plaque(color, false, outline))
	b.add_theme_stylebox_override("hover", plaque(color.lightened(0.06), false, outline))
	b.add_theme_stylebox_override("pressed", plaque(down, true, outline))
	b.add_theme_stylebox_override("hover_pressed", plaque(down, true, outline))
	b.add_theme_stylebox_override("disabled", plaque(color.lerp(Color(0.85, 0.83, 0.88), 0.6), false, outline.lerp(Color(0.6, 0.57, 0.65), 0.6)))


## Button plaque: a chunky rounded tile in the logo's style: dark brown
## outline, a darker raised edge along the bottom (it sinks when pressed),
## a soft gloss on top and a little shadow. Made once per colour and kept.
const OUTLINE := Color("#5a3b2e")
const PLAQUE_SIZE := 72
const PLAQUE_RADIUS := 20.0
const PLAQUE_LIP := 7
static var _plaques := {}


static func plaque(face: Color, pressed: bool, outline: Color = OUTLINE) -> StyleBoxTexture:
	var key := "%s %s %s" % [face.to_html(), pressed, outline.to_html()]
	if _plaques.has(key):
		return _plaques[key]
	var n: int = PLAQUE_SIZE
	var lip: int = 2 if pressed else PLAQUE_LIP
	var shade := 3  # shadow below
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var line: float = 3.5 if outline == OUTLINE else 5.0
	var edge_color: Color = face.darkened(0.32)
	var top: float = float(PLAQUE_LIP - lip)  # pressed: the face sits lower
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var c := Color(0, 0, 0, 0)
			# Shadow, then outline, then the raised edge, then the face.
			var d_shadow: float = _round_rect(p, Rect2(1, top + shade, n - 2, n - top - shade - 1), PLAQUE_RADIUS)
			c = _over(c, Color(0.25, 0.18, 0.3, 0.22), clampf(0.5 - d_shadow / 2.0, 0, 1))
			var body := Rect2(1, top + 1, n - 2, n - top - shade - 2)
			c = _over(c, outline, clampf(0.5 - _round_rect(p, body, PLAQUE_RADIUS), 0, 1))
			var inner := body.grow(-line)
			c = _over(c, edge_color, clampf(0.5 - _round_rect(p, inner, PLAQUE_RADIUS - line), 0, 1))
			var face_rect := Rect2(inner.position, inner.size - Vector2(0, lip))
			var d_face: float = _round_rect(p, face_rect, PLAQUE_RADIUS - line)
			var shine: float = clampf(1.0 - (p.y - face_rect.position.y) / (face_rect.size.y * 0.5), 0, 1)
			var face_px: Color = face.lerp(face.lightened(0.45), shine * 0.55)
			c = _over(c, face_px, clampf(0.5 - d_face, 0, 1))
			# A thin light line just inside the top of the face.
			var rim: float = clampf(0.5 - absf(d_face + 2.5) + 0.5, 0, 1) * clampf(1.0 - (p.y - face_rect.position.y) / 14.0, 0, 1)
			c = _over(c, Color(1, 1, 1, 0.75), rim)
			img.set_pixel(x, y, c)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	var corner: float = PLAQUE_RADIUS + 4
	box.texture_margin_left = corner
	box.texture_margin_right = corner
	box.texture_margin_top = corner
	box.texture_margin_bottom = corner + PLAQUE_LIP
	box.content_margin_left = 22
	box.content_margin_right = 24
	box.content_margin_top = 8 + (PLAQUE_LIP - lip)
	box.content_margin_bottom = 8 + lip + shade
	_plaques[key] = box
	return box


## Signed distance from p to a rounded rectangle (negative inside).
static func _round_rect(p: Vector2, r: Rect2, radius: float) -> float:
	var half: Vector2 = r.size * 0.5
	var q: Vector2 = (p - r.get_center()).abs() - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## `top` laid over `base` with this much coverage.
static func _over(base: Color, top: Color, amount: float) -> Color:
	var a: float = top.a * amount
	var out_a: float = a + base.a * (1.0 - a)
	if out_a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb: Color = (top * a + base * base.a * (1.0 - a)) / out_a
	return Color(rgb.r, rgb.g, rgb.b, out_a)


## First idle frame of a unit type, cropped to the hand.
static func kind_icon(kind: int) -> AtlasTexture:
	var icon := AtlasTexture.new()
	icon.atlas = ATLAS
	var inset: Rect2 = ICON_INSET[kind]
	icon.region = Rect2(inset.position + Vector2(ICON_FRAME[kind] * CELL, kind * 5 * CELL), inset.size)
	return icon


## Four corner brackets: the "full screen" sign.
static func fullscreen_icon() -> ImageTexture:
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := TEXT_COLOR
	var arm := 13
	var w := 4
	for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var x0: int = 2 if corner.x == 0 else n - 2 - arm
		var y0: int = 2 if corner.y == 0 else n - 2 - arm
		var ex: int = 2 if corner.x == 0 else n - 2 - w   # vertical stroke x
		var ey: int = 2 if corner.y == 0 else n - 2 - w   # horizontal stroke y
		img.fill_rect(Rect2i(x0, ey, arm, w), c)
		img.fill_rect(Rect2i(ex, y0, w, arm), c)
	return ImageTexture.create_from_image(img)


## Round icon buttons (assets/env/button_*.png).
const BUTTON_ICONS := {
	"build": preload("res://assets/env/button_build.png"),
	"attack": preload("res://assets/env/button_attack.png"),
	"hold": preload("res://assets/env/button_hold.png"),
	"queue": preload("res://assets/env/button_queue.png"),
	"group": preload("res://assets/env/button_group.png"),
	"settings": preload("res://assets/env/button_settings.png"),
	"surrender": preload("res://assets/env/button_surrender.png"),
}
const ICON_BUTTON_SIZE := 96.0
## Health bars: green, yellow from 40% down, red from 20% down.
const HEALTH_GREEN := Color("#5cc85a")
const HEALTH_YELLOW := Color("#f2c84b")
const HEALTH_RED := Color("#e5534b")


static func health_color(fraction: float) -> Color:
	if fraction <= 0.2:
		return HEALTH_RED
	if fraction <= 0.4:
		return HEALTH_YELLOW
	return HEALTH_GREEN


## A square button that's just a picture (the picture has its own frame).
## Toggle buttons grow a little and glow while switched on.
static func icon_button(icon_name: String) -> Button:
	var b := Button.new()
	b.icon = BUTTON_ICONS[icon_name]
	b.expand_icon = true
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2.ONE * roundf(ICON_BUTTON_SIZE * ui_scale())
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("icon_pressed_color", Color(1.12, 1.05, 1.05))
	b.add_theme_color_override("icon_hover_pressed_color", Color(1.12, 1.05, 1.05))
	b.toggled.connect(func(on):
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (1.12 if on else 1.0))
	return b


## The gear button (top right, left of the full screen button): opens
## Settings on top of `parent`. `preview_sfx` plays a sample sound.
static func settings_button(parent: Control, top: float, preview_sfx: Callable = func(): pass) -> Button:
	var b := icon_button("settings")
	var size: float = 72.0 * ui_scale()
	b.custom_minimum_size = Vector2(size, size)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.offset_top = top
	b.offset_right = -24 - size - 12  # left of the full screen button
	b.tooltip_text = "Settings"
	b.pressed.connect(func():
		var panel: Control = load("res://scripts/settings.gd").new()
		panel.preview_sfx = preview_sfx
		parent.add_child(panel))
	parent.add_child(b)
	return b


## A small picture for inside a button's content.
static func icon_rect(texture: Texture2D, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size) * ui_scale()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## "150 [stone icon]" (or several icons): an amount with its resource
## pictures instead of words. `res` = -1 means all three.
static func cost_row(amount: int, res: int, font_size: int = 24, icon_size: float = 32.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(4 * ui_scale()))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number := label(str(amount), roundi(font_size * ui_scale()))
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(number)
	for r in ([0, 1, 2] if res < 0 else [res]):
		row.add_child(icon_rect(res_icon(r), icon_size))
	return row


## Puts any layout inside a button (instead of its text and icon) and makes
## the button wide enough for it. Dim it with set_content_dimmed().
static func fill_button(b: Button, content: Control) -> void:
	b.text = ""
	b.icon = null
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 20)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(content)
	b.add_child(margin)
	b.set_meta("content", content)
	_fit_button(b)


static func _fit_button(b: Button) -> void:
	var content: Control = b.get_meta("content")
	var need: Vector2 = content.get_combined_minimum_size() + Vector2(36, 16)
	b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, need.x), maxf(b.custom_minimum_size.y, need.y))


static func set_content_dimmed(b: Button, dimmed: bool) -> void:
	if b.has_meta("content"):
		(b.get_meta("content") as Control).modulate.a = 0.45 if dimmed else 1.0


## A resource's icon: rocks (stone), logs (wood), ingots (metal).
static func res_icon(res: int) -> Texture2D:
	return RES_ICONS[res]


static func label(text: String, size: int = 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	return l


## A rounded pastel backing panel.
static func panel_box(color: Color = Color(1, 1, 1, 0.85)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(22)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.shadow_color = Color(0.3, 0.25, 0.4, 0.15)
	box.shadow_size = 6
	return box


## A question over everything, with two answers ("Keep going" / "Leave"):
## the first just closes it, the second runs `on_yes`. Returns the dialog.
static func confirm(parent: Control, title: String, text: String, no_text: String, yes_text: String,
		on_yes: Callable) -> Control:
	var s: float = ui_scale()
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.2, 0.35, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.add_to_group("modal")
	parent.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_box(Color(1, 1, 1, 0.96)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(18 * s))
	panel.add_child(column)
	var heading := label(title, roundi(44 * s))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var body := label(text, roundi(26 * s))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 560 * s
	column.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", roundi(16 * s))
	column.add_child(row)
	var no := button(Color("#e7e1f5"), Color("#d6cdef"), 30)
	no.text = no_text
	no.custom_minimum_size.x = 240 * s
	no.pressed.connect(shade.queue_free)
	row.add_child(no)
	if yes_text != "":
		var yes := button(Color("#fbe3ea"), Color("#f2c4d2"), 30)
		yes.text = yes_text
		yes.custom_minimum_size.x = 240 * s
		yes.pressed.connect(func():
			shade.queue_free()
			on_yes.call())
		row.add_child(yes)
	return shade


## On an iPhone or iPad (in a browser).
static func is_apple_web() -> bool:
	if not OS.has_feature("web"):
		return false
	if OS.has_feature("web_ios"):
		return true
	if not Engine.has_singleton("JavaScriptBridge"):
		return false
	# (iPads say they're Macs, but have touch.)
	return bool(JavaScriptBridge.eval(
			"/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)", true))


## Playing from the home screen icon (already full screen).
static func is_installed_app() -> bool:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	return bool(JavaScriptBridge.eval(
			"window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches || window.matchMedia('(display-mode: fullscreen)').matches", true))


## The full screen button. Apple's browsers mostly don't let a web game go
## full screen (iPhone never does; iPad sometimes): there it tries Safari's
## own way, and if that can't work, explains Add to Home Screen instead.
static func toggle_fullscreen(parent: Control) -> void:
	if is_apple_web():
		var ok: bool = bool(JavaScriptBridge.eval("""(function () {
			var d = document, c = d.querySelector('canvas') || d.documentElement;
			if (d.fullscreenElement || d.webkitFullscreenElement) {
				(d.exitFullscreen || d.webkitExitFullscreen).call(d); return true;
			}
			if (!(d.fullscreenEnabled || d.webkitFullscreenEnabled)) return false;
			var go = c.requestFullscreen || c.webkitRequestFullscreen;
			if (!go) return false;
			try { var p = go.call(c); if (p && p.catch) p.catch(function () {}); return true; } catch (e) { return false; }
		})()""", true))
		if not ok:
			confirm(parent, "Full screen", "Safari can't make a web game full screen. To play full screen: tap Share, then Add to Home Screen, and open the game from its new icon.", "Got it", "", func(): pass)
		return
	var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
