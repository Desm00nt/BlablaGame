class_name UIStyle
extends RefCounted

## Shared "ashen crown" visual language for every UI surface: dark iron
## panels, ash-gold trim, muted parchment text. Built in code like the rest
## of the project so there are no theme resources to keep in sync.

const INK := Color(0.055, 0.05, 0.045, 0.94)          # deep charcoal
const INK_SOFT := Color(0.09, 0.082, 0.072, 0.88)
const GOLD := Color(0.78, 0.62, 0.30)                  # ash gold
const GOLD_DIM := Color(0.45, 0.38, 0.22)
const PARCHMENT := Color(0.87, 0.82, 0.70)
const PARCHMENT_DIM := Color(0.62, 0.58, 0.50)
const BLOOD := Color(0.62, 0.16, 0.12)
const STEEL := Color(0.55, 0.57, 0.60)


static func panel(bg: Color = INK, border: Color = GOLD_DIM, radius: int = 8,
		border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	return sb


static func framed_panel(bg: Color = INK) -> StyleBoxFlat:
	# Double frame: wide soft outer border plus a hairline inner one, so the
	# panel reads as forged metal instead of a flat rectangle.
	var sb := panel(bg, GOLD_DIM, 10, 2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	return sb


static func label(text: String, size: int, color: Color = PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title_label(text: String, size: int) -> Label:
	var l := label(text, size, GOLD)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


static func button(text: String, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	var normal := panel(Color(0.13, 0.12, 0.10, 0.9), GOLD_DIM, 6, 1)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 5.0
	normal.content_margin_bottom = 5.0
	var hover := panel(Color(0.20, 0.17, 0.12, 0.95), GOLD, 6, 1)
	hover.content_margin_left = 12.0
	hover.content_margin_right = 12.0
	hover.content_margin_top = 5.0
	hover.content_margin_bottom = 5.0
	var pressed := panel(Color(0.08, 0.07, 0.06, 0.95), GOLD, 6, 1)
	pressed.content_margin_left = 12.0
	pressed.content_margin_right = 12.0
	pressed.content_margin_top = 5.0
	pressed.content_margin_bottom = 5.0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Left-aligned key badge like [E], drawn as a compact label chip.
static func key_badge(text: String) -> Control:
	var l := label(text, 12, GOLD)
	var sb := panel(Color(0, 0, 0, 0.5), GOLD_DIM, 4, 1)
	sb.content_margin_left = 5.0
	sb.content_margin_right = 5.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
