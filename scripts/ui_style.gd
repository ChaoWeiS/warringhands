extends RefCounted
## Shared look for on-screen buttons and icons (pastel, rounded, big enough
## for fingers).

const TEXT_COLOR := Color("#4a4560")
## Buttons on phones are this much bigger.
const PHONE_SCALE := 1.35
const ATLAS := preload("res://assets/units/hands.png")
const CELL := 192
## Hand picture inside an atlas cell (frames sit at the bottom of the cell).
const ICON_INSET := Rect2(40, 60, 112, 114)
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
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		var is_pressed: bool = state == "pressed" or state == "hover_pressed"
		if is_pressed and pressed_color.a > 0.0:
			box.bg_color = pressed_color
		elif state == "disabled":
			box.bg_color = Color(color, 0.55)
		else:
			box.bg_color = color.darkened(0.08) if is_pressed else color
		box.set_corner_radius_all(22)
		box.content_margin_left = 20
		box.content_margin_right = 24
		box.border_color = Color(1, 1, 1, 0.9)
		box.set_border_width_all(3)
		box.shadow_color = Color(0.3, 0.25, 0.4, 0.18)
		box.shadow_size = 6
		b.add_theme_stylebox_override(state, box)
	return b


## First idle frame of a unit type, cropped to the hand.
static func kind_icon(kind: int) -> AtlasTexture:
	var icon := AtlasTexture.new()
	icon.atlas = ATLAS
	icon.region = Rect2(ICON_INSET.position + Vector2(0, kind * 5 * CELL), ICON_INSET.size)
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
	"cancel": preload("res://assets/env/button_cancel.png"),
}
const ICON_BUTTON_SIZE := 96.0


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


static func set_button_icon(b: Button, icon_name: String) -> void:
	b.icon = BUTTON_ICONS[icon_name]


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
