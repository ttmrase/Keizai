class_name Glyph
extends RefCounted

## Small vector icons, drawn rather than loaded.
##
## A phone screen spans everything from a 16px status-bar mark to a 60px card
## header, and a font of symbols that covers both the shapes this game needs and
## Japanese is not something the bundled font is. So each icon is a handful of
## strokes and polygons in a unit box, drawn at whatever size is asked for, in
## whatever colour the caller is using — which also means they inherit the
## palette rather than fighting it.
##
## Every shape is authored on a box from -1 to 1 and scaled by half the size.

static func draw(ci: CanvasItem, glyph: StringName, centre: Vector2, size: float,
		colour: Color, weight: float = 1.0) -> void:
	var r := size * 0.5
	var w: float = maxf(1.0, size * 0.085 * weight)
	match glyph:
		&"map":
			_poly_line(ci, centre, r, [Vector2(-0.9, -0.6), Vector2(-0.3, -0.85),
				Vector2(0.3, -0.6), Vector2(0.9, -0.85), Vector2(0.9, 0.6),
				Vector2(0.3, 0.85), Vector2(-0.3, 0.6), Vector2(-0.9, 0.85),
				Vector2(-0.9, -0.6)], colour, w)
			_line(ci, centre, r, Vector2(-0.3, -0.85), Vector2(-0.3, 0.6), colour, w * 0.7)
			_line(ci, centre, r, Vector2(0.3, -0.6), Vector2(0.3, 0.85), colour, w * 0.7)
		&"scroll":
			_poly_line(ci, centre, r, [Vector2(-0.6, -0.8), Vector2(0.7, -0.8),
				Vector2(0.7, 0.8), Vector2(-0.6, 0.8), Vector2(-0.6, -0.8)], colour, w)
			for y in [-0.4, 0.0, 0.4]:
				_line(ci, centre, r, Vector2(-0.3, y), Vector2(0.45, y), colour, w * 0.7)
			ci.draw_arc(centre + Vector2(-0.6, -0.8) * r, r * 0.22, PI * 0.5, PI * 2.0, 10,
				colour, w)
		&"tree":
			var top := Vector2(0, -0.7)
			for leaf in [Vector2(-0.65, 0.65), Vector2(0, 0.65), Vector2(0.65, 0.65)]:
				_line(ci, centre, r, top + Vector2(0, 0.25), Vector2(leaf.x, 0.15), colour, w * 0.8)
				_line(ci, centre, r, Vector2(leaf.x, 0.15), leaf, colour, w * 0.8)
			for node in [top, Vector2(-0.65, 0.65), Vector2(0, 0.65), Vector2(0.65, 0.65)]:
				ci.draw_circle(centre + node * r, r * 0.2, colour)
		&"web":
			var a := Vector2(0, -0.65)
			var b := Vector2(-0.68, 0.5)
			var c := Vector2(0.68, 0.5)
			_line(ci, centre, r, a, b, colour, w * 0.8)
			_line(ci, centre, r, b, c, colour, w * 0.8)
			_line(ci, centre, r, c, a, colour, w * 0.8)
			for node in [a, b, c]:
				ci.draw_circle(centre + node * r, r * 0.26, colour)
		&"flame":
			_fill(ci, centre, r, [Vector2(0, -0.95), Vector2(0.35, -0.35),
				Vector2(0.62, 0.15), Vector2(0.5, 0.65), Vector2(0, 0.9),
				Vector2(-0.5, 0.65), Vector2(-0.62, 0.15), Vector2(-0.2, -0.15),
				Vector2(-0.05, -0.5)], colour)
			_fill(ci, centre, r, [Vector2(0.05, -0.05), Vector2(0.28, 0.35),
				Vector2(0.2, 0.68), Vector2(0, 0.78), Vector2(-0.2, 0.68),
				Vector2(-0.25, 0.4)], colour.darkened(0.45))
		&"bars":
			for i in 3:
				var x: float = -0.6 + 0.6 * i
				var h: float = [0.6, 1.2, 0.9][i]
				ci.draw_rect(Rect2(centre + Vector2(x - 0.2, 0.8 - h) * r,
					Vector2(0.4, h) * r), colour)
		&"sun":
			ci.draw_circle(centre, r * 0.38, colour)
			for i in 8:
				var angle := TAU * i / 8.0
				var dir := Vector2(cos(angle), sin(angle))
				ci.draw_line(centre + dir * r * 0.58, centre + dir * r * 0.92, colour, w)
		&"claw":
			for i in 3:
				var x: float = -0.5 + 0.5 * i
				var points: Array = []
				for t in 7:
					var f := float(t) / 6.0
					points.append(Vector2(x + 0.35 * f - 0.15, -0.85 + 1.7 * f
						+ 0.0) + Vector2(sin(f * PI) * -0.12, 0))
				_poly_line(ci, centre, r, points, colour, w * (1.1 - 0.15 * absf(i - 1)))
		&"unrest":
			var points: Array = []
			for i in 16:
				var angle := TAU * i / 16.0 - PI / 2.0
				var reach: float = 0.92 if i % 2 == 0 else 0.48
				points.append(Vector2(cos(angle), sin(angle)) * reach)
			_fill(ci, centre, r, points, colour)
		&"wheat":
			_line(ci, centre, r, Vector2(0, 0.95), Vector2(0, -0.55), colour, w)
			for i in 4:
				var y: float = -0.7 + 0.32 * i
				_leaf(ci, centre, r, Vector2(0, y), Vector2(-0.38, y - 0.22), colour)
				_leaf(ci, centre, r, Vector2(0, y), Vector2(0.38, y - 0.22), colour)
			_leaf(ci, centre, r, Vector2(0, -0.6), Vector2(0, -0.98), colour)
		&"gem":
			_fill(ci, centre, r, [Vector2(-0.55, -0.55), Vector2(0.55, -0.55),
				Vector2(0.9, -0.1), Vector2(0, 0.88), Vector2(-0.9, -0.1)], colour)
			_poly_line(ci, centre, r, [Vector2(-0.9, -0.1), Vector2(0.9, -0.1)],
				colour.darkened(0.45), w * 0.6)
			_poly_line(ci, centre, r, [Vector2(-0.3, -0.55), Vector2(-0.25, -0.1),
				Vector2(0, 0.88), Vector2(0.25, -0.1), Vector2(0.3, -0.55)],
				colour.darkened(0.45), w * 0.6)
		&"pine":
			_fill(ci, centre, r, [Vector2(0, -0.95), Vector2(0.45, -0.3),
				Vector2(0.22, -0.3), Vector2(0.65, 0.35), Vector2(-0.65, 0.35),
				Vector2(-0.22, -0.3), Vector2(-0.45, -0.3)], colour)
			ci.draw_rect(Rect2(centre + Vector2(-0.12, 0.35) * r, Vector2(0.24, 0.55) * r),
				colour.darkened(0.3))
		&"crown":
			_fill(ci, centre, r, [Vector2(-0.85, 0.55), Vector2(-0.85, -0.45),
				Vector2(-0.42, 0.0), Vector2(0, -0.75), Vector2(0.42, 0.0),
				Vector2(0.85, -0.45), Vector2(0.85, 0.55)], colour)
			ci.draw_rect(Rect2(centre + Vector2(-0.85, 0.6) * r, Vector2(1.7, 0.25) * r),
				colour)
		&"coin":
			ci.draw_circle(centre, r * 0.85, colour)
			ci.draw_arc(centre, r * 0.55, 0, TAU, 20, colour.darkened(0.4), w * 0.8)
		&"tower":
			_fill(ci, centre, r, [Vector2(-0.45, 0.9), Vector2(-0.35, -0.4),
				Vector2(-0.55, -0.4), Vector2(-0.55, -0.85), Vector2(-0.3, -0.85),
				Vector2(-0.3, -0.65), Vector2(-0.1, -0.65), Vector2(-0.1, -0.85),
				Vector2(0.1, -0.85), Vector2(0.1, -0.65), Vector2(0.3, -0.65),
				Vector2(0.3, -0.85), Vector2(0.55, -0.85), Vector2(0.55, -0.4),
				Vector2(0.35, -0.4), Vector2(0.45, 0.9)], colour)
		&"keep":
			_fill(ci, centre, r, [Vector2(-0.9, 0.85), Vector2(-0.9, -0.2),
				Vector2(-0.6, -0.2), Vector2(-0.6, -0.75), Vector2(-0.3, -0.75),
				Vector2(-0.3, -0.45), Vector2(0.3, -0.45), Vector2(0.3, -0.75),
				Vector2(0.6, -0.75), Vector2(0.6, -0.2), Vector2(0.9, -0.2),
				Vector2(0.9, 0.85)], colour)
			_fill(ci, centre, r, [Vector2(-0.2, 0.85), Vector2(-0.2, 0.3),
				Vector2(0, 0.12), Vector2(0.2, 0.3), Vector2(0.2, 0.85)],
				colour.darkened(0.55))
		&"mountain":
			_fill(ci, centre, r, [Vector2(-0.95, 0.75), Vector2(-0.3, -0.6),
				Vector2(0.05, 0.05), Vector2(0.4, -0.35), Vector2(0.95, 0.75)], colour)
			_fill(ci, centre, r, [Vector2(-0.3, -0.6), Vector2(-0.12, -0.25),
				Vector2(-0.3, -0.18), Vector2(-0.45, -0.3)], colour.lightened(0.35))
		&"plague":
			for i in 3:
				var angle := TAU * i / 3.0
				var dir := Vector2(cos(angle), sin(angle))
				ci.draw_arc(centre + dir * r * 0.32, r * 0.42, angle + 0.6, angle + 3.6,
					12, colour, w)
			ci.draw_circle(centre, r * 0.16, colour)
		&"drought":
			ci.draw_arc(centre + Vector2(0, -0.15) * r, r * 0.42, PI, TAU, 14, colour, w)
			for i in 5:
				var angle := PI + PI * i / 4.0
				var dir := Vector2(cos(angle), sin(angle))
				ci.draw_line(centre + Vector2(0, -0.15) * r + dir * r * 0.58,
					centre + Vector2(0, -0.15) * r + dir * r * 0.82, colour, w * 0.8)
			_poly_line(ci, centre, r, [Vector2(-0.9, 0.25), Vector2(-0.4, 0.25),
				Vector2(-0.15, 0.6), Vector2(0.1, 0.3), Vector2(0.4, 0.75),
				Vector2(0.9, 0.25)], colour, w * 0.8)
		&"sparkle":
			_fill(ci, centre, r, [Vector2(0, -0.95), Vector2(0.2, -0.2),
				Vector2(0.95, 0), Vector2(0.2, 0.2), Vector2(0, 0.95),
				Vector2(-0.2, 0.2), Vector2(-0.95, 0), Vector2(-0.2, -0.2)], colour)
		&"pause":
			ci.draw_rect(Rect2(centre + Vector2(-0.55, -0.7) * r, Vector2(0.35, 1.4) * r), colour)
			ci.draw_rect(Rect2(centre + Vector2(0.2, -0.7) * r, Vector2(0.35, 1.4) * r), colour)
		&"play":
			_fill(ci, centre, r, [Vector2(-0.5, -0.75), Vector2(0.75, 0),
				Vector2(-0.5, 0.75)], colour)
		&"people":
			ci.draw_circle(centre + Vector2(0, -0.5) * r, r * 0.3, colour)
			_fill(ci, centre, r, [Vector2(-0.7, 0.85), Vector2(-0.55, 0.05),
				Vector2(0, -0.12), Vector2(0.55, 0.05), Vector2(0.7, 0.85)], colour)
		&"banner":
			_line(ci, centre, r, Vector2(-0.6, -0.95), Vector2(-0.6, 0.95), colour, w)
			_fill(ci, centre, r, [Vector2(-0.55, -0.85), Vector2(0.75, -0.85),
				Vector2(0.45, -0.45), Vector2(0.75, -0.05), Vector2(-0.55, -0.05)], colour)
		&"altar":
			_line(ci, centre, r, Vector2(0, -0.95), Vector2(0, 0.4), colour, w)
			_line(ci, centre, r, Vector2(-0.45, -0.5), Vector2(0.45, -0.5), colour, w)
			ci.draw_rect(Rect2(centre + Vector2(-0.75, 0.45) * r, Vector2(1.5, 0.4) * r), colour)
		_:
			ci.draw_circle(centre, r * 0.5, colour)


static func _p(centre: Vector2, r: float, p: Vector2) -> Vector2:
	return centre + p * r


static func _line(ci: CanvasItem, centre: Vector2, r: float, a: Vector2, b: Vector2,
		colour: Color, w: float) -> void:
	ci.draw_line(_p(centre, r, a), _p(centre, r, b), colour, w, true)


static func _poly_line(ci: CanvasItem, centre: Vector2, r: float, points: Array,
		colour: Color, w: float) -> void:
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(_p(centre, r, p))
	ci.draw_polyline(scaled, colour, w, true)


static func _fill(ci: CanvasItem, centre: Vector2, r: float, points: Array,
		colour: Color) -> void:
	var scaled := PackedVector2Array()
	for p in points:
		scaled.append(_p(centre, r, p))
	ci.draw_colored_polygon(scaled, colour)


static func _leaf(ci: CanvasItem, centre: Vector2, r: float, from: Vector2, to: Vector2,
		colour: Color) -> void:
	var mid := (from + to) * 0.5
	var side := (to - from).orthogonal().normalized() * 0.1
	_fill(ci, centre, r, [from, mid + side, to, mid - side], colour)


## Which icon belongs to each disaster and blessing.
const DISASTER_GLYPHS := {
	&"drought": &"drought",
	&"plague": &"plague",
	&"wildfire": &"flame",
	&"monster_incursion": &"claw",
	&"bountiful_harvest": &"wheat",
	&"mineral_strike": &"gem",
	&"blessed_grove": &"pine",
}

## And to each kind of land.
const INDUSTRY_GLYPHS := {
	&"mining": &"mountain",
	&"forestry": &"pine",
	&"farming": &"wheat",
	&"trade": &"coin",
	&"frontier": &"tower",
}
