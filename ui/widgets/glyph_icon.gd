class_name GlyphIcon
extends Control

## A Glyph in a box, for putting an icon inside a container.

@export var glyph: StringName = &"":
	set(value):
		glyph = value
		queue_redraw()
@export var colour: Color = Palette.TEXT:
	set(value):
		colour = value
		queue_redraw()
@export var weight: float = 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if glyph == &"":
		return
	var side: float = minf(size.x, size.y)
	Glyph.draw(self, glyph, size * 0.5, side * 0.9, colour, weight)


static func make(name: StringName, tint: Color, side: float) -> GlyphIcon:
	var icon := GlyphIcon.new()
	icon.glyph = name
	icon.colour = tint
	icon.custom_minimum_size = Vector2(side, side)
	return icon
