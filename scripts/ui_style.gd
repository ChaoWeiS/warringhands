extends RefCounted
## Shared look for on-screen buttons and icons (pastel, rounded, big enough
## for fingers).

const TEXT_COLOR := Color("#4a4560")
const ATLAS := preload("res://assets/units/hands.png")
const CELL := 128
## Hand picture inside an atlas cell (frames sit at the bottom of the cell).
const ICON_INSET := Rect2(8, 12, 112, 114)
## Resource colours: stone, wood, metal.
const RES_COLORS := [Color("#b9b2cc"), Color("#cf9f74"), Color("#8fd6d0")]
const RES_ICONS := [
	preload("res://assets/env/icon_stone.png"),
	preload("res://assets/env/icon_wood.png"),
	preload("res://assets/env/icon_metal.png"),
]
const RES_NAMES := ["stone", "wood", "metal"]
const BUILDING_NAMES := {"hq": "HQ", "quarry": "Quarry", "mill": "Paper Mill", "forge": "Forge"}



static func button(color: Color, pressed_color: Color = Color.TRANSPARENT, font_size: int = 30) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_constant_override("icon_max_width", 60)
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
	icon.region = Rect2(ICON_INSET.position + Vector2(0, kind * 3 * CELL), ICON_INSET.size)
	return icon


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
