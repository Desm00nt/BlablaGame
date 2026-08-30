class_name CompassBar
extends Control

## Skyrim-style compass strip. Ticks every 15 degrees, cardinal letters in
## Russian (С/В/Ю/З), and a gold diamond for the current quest marker.
##
## Yaw convention everywhere in the project: a body faces its local -Z, and
## the yaw that faces a world direction d is atan2(-d.x, -d.z). yaw 0 = north.
##
## Redraws every frame while visible - a few dozen draw primitives is noise
## even at 144 fps, and it keeps the marker perfectly glued to the world.

const WIDTH_PX: float = 460.0
const HEIGHT_PX: float = 34.0
const PIXELS_PER_RAD: float = 150.0
const HALF_SPAN: float = 1.35  # radians shown left/right of the heading

var player: Player = null
var marker_pos: Vector3 = Vector3.INF
var marker_valid: bool = false

const CARDINALS := [["С", 0.0], ["В", -PI * 0.5], ["Ю", PI], ["З", PI * 0.5]]


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH_PX, HEIGHT_PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible and player != null:
		queue_redraw()


func set_marker(pos: Vector3, valid: bool) -> void:
	marker_pos = pos
	marker_valid = valid


func _wrap(angle: float) -> float:
	var a := angle
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var c := Vector2(size.x * 0.5, size.y)
	var heading: float = player.rotation.y

	# Frame.
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.05, 0.05, 0.045, 0.62))
	draw_rect(Rect2(0, 0, size.x, size.y), UIStyle.GOLD_DIM, false, 1.0)

	# Ticks every 15 degrees across the visible window.
	var step := PI / 12.0
	var i0 := floorf((heading - HALF_SPAN) / step)
	var i1 := ceilf((heading + HALF_SPAN) / step)
	var i := i0
	while i <= i1:
		var off := _wrap(i * step - heading)
		var x := c.x + off * PIXELS_PER_RAD
		if int(i) % 2 == 0:
			draw_line(Vector2(x, c.y - 10), Vector2(x, c.y - 3), Color(1, 1, 1, 0.5), 1.6)
		else:
			draw_line(Vector2(x, c.y - 7), Vector2(x, c.y - 3), Color(1, 1, 1, 0.2), 1.0)
		i += 1.0

	for card in CARDINALS:
		var d := _wrap(float(card[1]) - heading)
		if absf(d) <= HALF_SPAN:
			var xc := c.x + d * PIXELS_PER_RAD
			draw_string(ThemeDB.fallback_font, Vector2(xc - 6, c.y - 8), str(card[0]),
					HORIZONTAL_ALIGNMENT_CENTER, 12, 13, Color(0.92, 0.88, 0.78))

	if marker_valid and marker_pos != Vector3.INF:
		var to_marker: Vector3 = marker_pos - player.global_position
		to_marker.y = 0.0
		if to_marker.length() > 0.5:
			var yaw_to := atan2(-to_marker.x, -to_marker.z)
			var dm := _wrap(yaw_to - heading)
			if absf(dm) <= HALF_SPAN:
				var xm := c.x + dm * PIXELS_PER_RAD
				var pts := PackedVector2Array([
					Vector2(xm, c.y - 22), Vector2(xm + 5, c.y - 16),
					Vector2(xm, c.y - 10), Vector2(xm - 5, c.y - 16),
				])
				draw_colored_polygon(pts, UIStyle.GOLD)
			elif dm > 0.0:
				_draw_edge_arrow(c, -1)
			else:
				_draw_edge_arrow(c, 1)

	# Center needle.
	draw_line(Vector2(c.x, c.y - 12), Vector2(c.x, c.y - 2), Color(0.95, 0.85, 0.5, 0.9), 2.0)


func _draw_edge_arrow(c: Vector2, side: float) -> void:
	var x := c.x + side * (size.x * 0.5 - 12.0)
	var pts := PackedVector2Array([
		Vector2(x + side * 5, c.y - 16), Vector2(x - side * 3, c.y - 21),
		Vector2(x - side * 3, c.y - 11),
	])
	draw_colored_polygon(pts, UIStyle.GOLD)
