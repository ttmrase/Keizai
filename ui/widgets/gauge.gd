extends Control

## A labelled bar. Used for the world indicators in the status strip and for the
## resource readouts in the settlement panel.

var _label: String = ""
var _value: float = 0.0
var _color: Color = Palette.ACCENT


func set_value(label: String, value: float, color: Color) -> void:
	_label = label
	_value = clampf(value, 0.0, 1.0)
	_color = color
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 16
	draw_string(font, Vector2(0, 14), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Palette.TEXT_MUTED)

	var bar_top := 20.0
	var bar_height := 6.0
	draw_rect(Rect2(0, bar_top, size.x, bar_height), Palette.PANEL_RAISED)
	draw_rect(Rect2(0, bar_top, size.x * _value, bar_height), _color)
