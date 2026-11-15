class_name WarBar
extends Control

## The tug of war: how far each side has pushed the line. Side A's colour fills
## from the left up to where the front stands, side B's from the right, and the
## line itself is marked — so a war going one way reads as one colour eating the
## other, and a stalemate as a line that does not move.

var front := 0.0
var colour_a := Palette.POLITY
var colour_b := Palette.DANGER


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 18)


func setup(a: Color, b: Color, value: float) -> WarBar:
	colour_a = a
	colour_b = b
	front = clampf(value, -1.0, 1.0)
	queue_redraw()
	return self


func _draw() -> void:
	var h := size.y
	var line_x := size.x * (0.5 + front * 0.5)
	var radius := h * 0.5
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(radius))
	box.bg_color = colour_b.darkened(0.15)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if line_x > 1.0:
		var left := StyleBoxFlat.new()
		left.bg_color = colour_a.darkened(0.05)
		left.corner_radius_top_left = int(radius)
		left.corner_radius_bottom_left = int(radius)
		if line_x >= size.x - 1.0:
			left.corner_radius_top_right = int(radius)
			left.corner_radius_bottom_right = int(radius)
		draw_style_box(left, Rect2(Vector2.ZERO, Vector2(line_x, h)))
	# Where the war began, and where the line is now.
	draw_line(Vector2(size.x * 0.5, -2), Vector2(size.x * 0.5, h + 2), Color(Palette.TEXT, 0.35), 1.0)
	draw_line(Vector2(line_x, -4), Vector2(line_x, h + 4), Palette.TEXT, 3.0)
	Glyph.draw(self, &"swords", Vector2(line_x, h * 0.5), h * 1.1, Palette.INK)
