class_name MightChip
extends Button

## The god's might and spoken prophecies, at a glance from any screen: the
## number to spend, and a pip for each prophecy waiting to come true. Tapping it
## goes to the god's panel.

func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(98, 44)
	Oracle.might_changed.connect(func(_v): queue_redraw())
	Oracle.prophecies_changed.connect(queue_redraw)
	EventBus.world_reset.connect(queue_redraw)
	EventBus.game_loaded.connect(queue_redraw)


func _draw() -> void:
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.ACCENT, 0.16 if button_pressed or is_hovered() else 0.1)
	box.border_color = Color(Palette.ACCENT, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(int(rect.size.y * 0.5))
	draw_style_box(box, rect)
	Glyph.draw(self, &"sparkle", Vector2(rect.position.x + 20, rect.get_center().y - 5), 18,
		Palette.ACCENT)
	var font := get_theme_default_font()
	var value := "∞" if Oracle.free_mode() else "%d" % int(Oracle.might)
	draw_string(font, Vector2(rect.position.x + 34, rect.get_center().y + 2), value,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 19, Palette.ACCENT)
	# One pip per prophecy slot: lit while a prophecy is waiting.
	for i in Oracle.MAX_ACTIVE:
		var lit := i < Oracle.prophecies.size()
		var centre := Vector2(rect.position.x + 14 + i * 9, rect.end.y - 8)
		if lit:
			draw_circle(centre, 3.2, Palette.ACCENT)
		else:
			draw_arc(centre, 3.0, 0, TAU, 12, Color(Palette.ACCENT, 0.45), 1.0)
	draw_string(font, Vector2(rect.position.x + 42, rect.end.y - 3), "神威",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT_MUTED)
