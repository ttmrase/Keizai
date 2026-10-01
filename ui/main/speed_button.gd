class_name SpeedButton
extends Button

## One segment of the clock control: stopped, or one to three arrows.

var arrows := 0
var active := false:
	set(value):
		active = value
		queue_redraw()
var first := false
var last := false


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT if active else Palette.PANEL_RAISED
	box.corner_radius_top_left = 10 if first else 0
	box.corner_radius_bottom_left = 10 if first else 0
	box.corner_radius_top_right = 10 if last else 0
	box.corner_radius_bottom_right = 10 if last else 0
	draw_style_box(box, Rect2(Vector2(1, 0), size - Vector2(2, 0)))
	var ink := Palette.INK if active else Palette.TEXT_MUTED
	var centre := size * 0.5
	if arrows == 0:
		Glyph.draw(self, &"pause", centre, 18, ink)
		return
	var step := 9.0
	var start := centre.x - step * float(arrows - 1) * 0.5
	for i in arrows:
		Glyph.draw(self, &"play", Vector2(start + step * i, centre.y), 16, ink)
