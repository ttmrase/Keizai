class_name HelpButton
extends Button

## 「？」— what am I looking at. The same place on every screen.

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(40, 44)


func _draw() -> void:
	var centre := size * 0.5
	var lit := button_pressed or is_hovered()
	draw_circle(centre, 16.0, Color(1, 1, 1, 0.1 if lit else 0.05))
	draw_arc(centre, 16.0, 0.0, TAU, 32, Color(Palette.TEXT_MUTED, 0.7), 1.2, true)
	var font := get_theme_default_font()
	var width := font.get_string_size("？", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, centre + Vector2(-width * 0.5, 7), "？", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Palette.TEXT)
