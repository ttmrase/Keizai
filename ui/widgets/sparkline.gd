class_name Sparkline
extends Control

## A few decades of one number as a line: rising, falling or flat at a glance.
##
## The bar beside it already says how large the number is, so the line is drawn
## for its shape — scaled to its own range — but never to a range narrower than
## `min_span`, so a wobble of a point or two stays a flat line rather than being
## blown up into a cliff.

var values := PackedFloat32Array():
	set(v):
		values = v
		queue_redraw()
var colour := Palette.ACCENT
var min_span := 12.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var base := size.y - 1.0
	draw_line(Vector2(0, base), Vector2(size.x, base), Color(colour, 0.18), 1.0)
	if values.size() < 2:
		return
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(hi - lo, min_span)
	var bottom := (lo + hi) * 0.5 - span * 0.5
	var points := PackedVector2Array()
	var step := size.x / float(values.size() - 1)
	for i in values.size():
		var t := clampf((values[i] - bottom) / span, 0.0, 1.0)
		points.append(Vector2(i * step, size.y - 3.0 - t * (size.y - 6.0)))
	# Shaded underneath a strip at a time: each strip is a trapezoid, which
	# always triangulates, where one polygon along a flat line might not.
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		draw_colored_polygon(PackedVector2Array([a, b, Vector2(b.x, base),
			Vector2(a.x, base)]), Color(colour, 0.12))
	draw_polyline(points, colour, 2.0, true)
	draw_circle(points[points.size() - 1], 3.0, colour)
