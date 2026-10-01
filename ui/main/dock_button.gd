class_name DockButton
extends Button

## One tab in the bottom dock: an icon over a word, lit when it is the screen in
## front of you, with a mark when something on that screen wants looking at.

var glyph: StringName = &""
var caption: String = ""
var active := false:
	set(value):
		active = value
		queue_redraw()
## A small red mark — for the incidents tab, when a rupture is close.
var badge := false:
	set(value):
		if badge != value:
			badge = value
			queue_redraw()


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)


func _draw() -> void:
	var tint := Palette.ACCENT if active else Palette.TEXT_MUTED
	if active:
		draw_rect(Rect2(Vector2(size.x * 0.22, 0), Vector2(size.x * 0.56, 3)), Palette.ACCENT)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03))
	Glyph.draw(self, glyph, Vector2(size.x * 0.5, size.y * 0.36), 26, tint)
	var font := get_theme_default_font()
	var font_size := 15
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.86), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
	if badge:
		var at := Vector2(size.x * 0.5 + 15, size.y * 0.2)
		draw_circle(at, 6, Palette.DANGER)
		draw_arc(at, 6, 0, TAU, 16, Palette.BG, 2.0)
