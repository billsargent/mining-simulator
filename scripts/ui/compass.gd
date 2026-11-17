extends Control
## Compass strip across the top of the screen: heading letters, plus markers for waypoints,
## home and parked vehicles with their distances.

const SPAN := 1.4            # radians shown either side of straight ahead (about 80 degrees)
const LETTERS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var heading := 0.0           # radians clockwise from north (map up, -z)
var origin := Vector2.ZERO   # player position (x, z)
var markers: Array = []      # [Vector2 position, Color, String label]


func update_view(h: float, pos: Vector2, list: Array) -> void:
	heading = h
	origin = pos
	markers = list
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var cx := w * 0.5
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2(0, 0), Vector2(w, 34)), Color(0.05, 0.06, 0.05, 0.5))
	for k in 16:
		var rel := wrapf(k * TAU / 16.0 - heading, -PI, PI)
		if absf(rel) > SPAN:
			continue
		var x := cx + rel / SPAN * cx
		if k % 2 == 0:
			var text: String = LETTERS[k / 2]
			var fs := 18 if k % 4 == 0 else 14
			var col := Color(1.0, 0.85, 0.5) if k == 0 else Color(1, 1, 1, 0.9)
			draw_string(font, Vector2(x - 6.0 * text.length(), 24), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			draw_line(Vector2(x, 8), Vector2(x, 16), Color(1, 1, 1, 0.5), 1.0)
	draw_line(Vector2(cx, 0), Vector2(cx, 6), Color(1, 1, 1, 0.9), 2.0)
	var label_xs: Array[float] = []
	for m in markers:
		var d: Vector2 = (m[0] as Vector2) - origin
		var rel := wrapf(atan2(d.x, -d.y) - heading, -PI, PI)
		var col: Color = m[1]
		var edge := absf(rel) > SPAN
		if edge:
			rel = signf(rel) * SPAN
			col.a = 0.5
		var x := cx + rel / SPAN * cx
		draw_colored_polygon(PackedVector2Array([Vector2(x, 34), Vector2(x - 6, 26), Vector2(x + 6, 26)]), col)
		if not edge:
			var label := "%s %s" % [m[2], _dist(d.length())]
			# Stack labels that would overlap.
			var row := 0
			for lx in label_xs:
				if absf(lx - x) < 70.0:
					row += 1
			label_xs.append(x)
			var y := 50.0 + row * 14.0
			draw_string_outline(font, Vector2(x - 3.4 * label.length(), y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(x - 3.4 * label.length(), y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _dist(m: float) -> String:
	return "%d m" % roundi(m) if m < 1000.0 else "%.1f km" % (m / 1000.0)
