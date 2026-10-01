extends Control

const NAMES := [&"map", &"scroll", &"tree", &"web", &"flame", &"bars", &"sun",
	&"claw", &"unrest", &"wheat", &"gem", &"pine", &"crown", &"coin", &"tower",
	&"keep", &"mountain", &"plague", &"drought", &"sparkle", &"pause", &"play",
	&"people", &"banner", &"altar"]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		OS.get_cmdline_user_args()[0].split("=")[1])
	get_tree().quit(0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	var font := get_theme_default_font()
	for i in NAMES.size():
		var col := i % 5
		var row := i / 5
		var c := Vector2(72 + col * 144, 90 + row * 150)
		Glyph.draw(self, NAMES[i], c, 64, Palette.ACCENT)
		Glyph.draw(self, NAMES[i], c + Vector2(44, 52), 20, Palette.TEXT)
		draw_string(font, c + Vector2(-50, 62), String(NAMES[i]), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 14, Palette.TEXT_MUTED)
