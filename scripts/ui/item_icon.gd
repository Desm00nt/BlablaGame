class_name ItemIcon
extends Control

## Tiny vector icons drawn with _draw() - no textures anywhere in the project.
## Each icon is a few polygons in the ash-gold/steel palette, sized to the
## control's rect and cheap enough to redraw freely.

var kind: String = "sword"


func _init(icon_kind: String = "sword") -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(28, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	match kind:
		"sword":
			_draw_sword(c)
		"shard":
			_draw_shard(c)
		"note":
			_draw_note(c)
		"rune":
			_draw_rune(c)
		"shield":
			_draw_shield(c)
		"potion":
			_draw_potion(c)
		"stone":
			_draw_stone(c)
		"coin":
			_draw_coin(c)
		_:
			_draw_sword(c)


func _poly(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)


## Vertical blade + guard + grip, centred.
func _draw_sword(c: Vector2) -> void:
	var w := size.x
	var h := size.y
	var steel := Color(0.80, 0.82, 0.86)
	var gold := UIStyle.GOLD
	var grip := Color(0.30, 0.22, 0.14)
	# Blade: long diamond so it has a tip at both ends.
	_poly(PackedVector2Array([
		Vector2(c.x, h * 0.06), Vector2(c.x + w * 0.075, h * 0.24),
		Vector2(c.x + w * 0.045, h * 0.62), Vector2(c.x - w * 0.045, h * 0.62),
		Vector2(c.x - w * 0.075, h * 0.24),
	]), steel)
	# Fuller line.
	draw_line(Vector2(c.x, h * 0.12), Vector2(c.x, h * 0.58),
			Color(0.55, 0.57, 0.62), 1.4)
	# Guard.
	_poly(PackedVector2Array([
		Vector2(c.x - w * 0.24, h * 0.64), Vector2(c.x + w * 0.24, h * 0.64),
		Vector2(c.x + w * 0.19, h * 0.71), Vector2(c.x - w * 0.19, h * 0.71),
	]), gold)
	# Grip + pommel.
	draw_rect(Rect2(c.x - w * 0.035, h * 0.71, w * 0.07, h * 0.17), grip)
	draw_circle(Vector2(c.x, h * 0.92), w * 0.055, gold)


## A crown shard: warm triangle with a cold inner glint.
func _draw_shard(c: Vector2) -> void:
	var w := size.x
	var h := size.y
	_poly(PackedVector2Array([
		Vector2(c.x, h * 0.08), Vector2(c.x + w * 0.30, h * 0.42),
		Vector2(c.x + w * 0.16, h * 0.90), Vector2(c.x - w * 0.18, h * 0.84),
		Vector2(c.x - w * 0.28, h * 0.40),
	]), UIStyle.GOLD)
	_poly(PackedVector2Array([
		Vector2(c.x, h * 0.20), Vector2(c.x + w * 0.14, h * 0.46),
		Vector2(c.x, h * 0.72), Vector2(c.x - w * 0.12, h * 0.44),
	]), Color(0.55, 0.72, 0.95, 0.85))


## Parchment note with three scribbled lines.
func _draw_note(c: Vector2) -> void:
	var w := size.x
	var h := size.y
	var paper := Color(0.84, 0.79, 0.66)
	_poly(PackedVector2Array([
		Vector2(c.x - w * 0.28, h * 0.12), Vector2(c.x + w * 0.20, h * 0.12),
		Vector2(c.x + w * 0.28, h * 0.22), Vector2(c.x + w * 0.28, h * 0.88),
		Vector2(c.x - w * 0.28, h * 0.88),
	]), paper)
	var ink := Color(0.25, 0.22, 0.18)
	for i in 3:
		var yy := h * (0.34 + 0.16 * i)
		draw_line(Vector2(c.x - w * 0.18, yy), Vector2(c.x + w * 0.16, yy), ink, 1.6)


## The hand symbol: a ring with three ascending prongs (the seal on the hero).
func _draw_rune(c: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.34
	draw_arc(c, r, 0.0, TAU, 24, UIStyle.GOLD, 2.0)
	for i in 3:
		var ang := -TAU * 0.5 + TAU * float(i) / 3.0
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * (r * 0.25), c + dir * (r * 1.45), UIStyle.GOLD, 2.0)
	draw_circle(c, r * 0.16, UIStyle.GOLD)


## Round shield: wooden disk, iron rim, steel boss.
func _draw_shield(c: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.4
	draw_circle(c, r, Color(0.40, 0.30, 0.17))
	draw_arc(c, r, 0.0, TAU, 24, UIStyle.STEEL, 2.4)
	# Vertical grain.
	for i in 3:
		var x := c.x + (float(i) - 1.0) * r * 0.42
		draw_line(Vector2(x, c.y - r * 0.82), Vector2(x, c.y + r * 0.82),
					Color(0.30, 0.22, 0.12), 1.4)
	draw_circle(c, r * 0.26, UIStyle.STEEL)
	draw_arc(c, r * 0.26, 0.0, TAU, 12, Color(0.35, 0.36, 0.38), 1.2)


## Potion: round flask, red fill, corked neck, a glass glint.
func _draw_potion(c: Vector2) -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(c.x - w * 0.06, h * 0.10, w * 0.12, h * 0.16), Color(0.5, 0.38, 0.22))
	draw_circle(Vector2(c.x, h * 0.62), w * 0.26, Color(0.72, 0.16, 0.13))
	draw_circle(Vector2(c.x, h * 0.62), w * 0.26, Color(0.75, 0.78, 0.8, 0.35), false, 1.4)
	draw_circle(Vector2(c.x - w * 0.09, h * 0.54), w * 0.05, Color(1, 1, 1, 0.5))


## Whetstone: a grey rectangular bar with a darker worn face.
func _draw_stone(c: Vector2) -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(c.x - w * 0.3, h * 0.34, w * 0.6, h * 0.3), Color(0.48, 0.47, 0.45))
	draw_rect(Rect2(c.x - w * 0.3, h * 0.34, w * 0.6, h * 0.3), UIStyle.GOLD_DIM, false, 1.0)
	draw_line(Vector2(c.x - w * 0.2, h * 0.5), Vector2(c.x + w * 0.2, h * 0.5),
				Color(0.36, 0.35, 0.34), 2.0)


## Gold coin: warm disk with an inner ring.
func _draw_coin(c: Vector2) -> void:
	var r := minf(size.x, size.y) * 0.36
	draw_circle(c, r, Color(0.92, 0.76, 0.28))
	draw_arc(c, r * 0.68, 0.0, TAU, 16, Color(0.72, 0.55, 0.16), 1.6)
	draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.18, Color(1, 0.95, 0.7, 0.8))
