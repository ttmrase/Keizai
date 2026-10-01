extends Control

## One reading of the world in the status strip: an icon, a word, a bar, and which
## way it is going. The direction matters more than the level for a reader who
## glances up once a minute — a famine starting is news, a famine continuing is
## not — so the arrow is the loudest part when it is there.

var _label: String = ""
var _glyph: StringName = &""
var _value: float = 0.0
var _color: Color = Palette.ACCENT
## What the bar read the last time it moved enough to be worth saying so.
var _anchor: float = -1.0
var _trend: int = 0
## How far the reading has to move before an arrow appears.
const TREND_STEP := 0.025


func set_value(label: String, value: float, color: Color, glyph: StringName = &"") -> void:
	_label = label
	_glyph = glyph
	_value = clampf(value, 0.0, 1.0)
	_color = color
	if _anchor < 0.0:
		_anchor = _value
	elif _value - _anchor > TREND_STEP:
		_trend = 1
		_anchor = _value
	elif _anchor - _value > TREND_STEP:
		_trend = -1
		_anchor = _value
	queue_redraw()


## Resetting the arrow when a world is replaced, so a new world does not open
## with the old one's direction of travel.
func reset_trend() -> void:
	_anchor = -1.0
	_trend = 0


func _draw() -> void:
	var font := get_theme_default_font()
	var x := 0.0
	if _glyph != &"":
		Glyph.draw(self, _glyph, Vector2(8, 9), 17, _color.lerp(Palette.TEXT, 0.25))
		x = 20.0
	draw_string(font, Vector2(x, 15), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Palette.TEXT_MUTED)
	if _trend != 0:
		var tip := Vector2(size.x - 7, 9)
		var up := _trend > 0
		var arrow := PackedVector2Array([
			tip + Vector2(0, -5 if up else 5),
			tip + Vector2(5, 2 if up else -2),
			tip + Vector2(-5, 2 if up else -2)])
		draw_colored_polygon(arrow, _color.lerp(Palette.TEXT, 0.2))

	var bar_top := 22.0
	var bar_height := 5.0
	draw_rect(Rect2(0, bar_top, size.x, bar_height), Palette.PANEL_RAISED)
	draw_rect(Rect2(0, bar_top, size.x * _value, bar_height), _color)
