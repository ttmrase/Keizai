class_name Sheet
extends Control

## A sheet that rises from the bottom over whatever screen opened it, with a
## title, a scrolling body and a way out. Tapping the dimmed screen behind it
## closes it too, as a phone reader expects.

signal closed

var body: VBoxContainer
var _panel: PanelContainer


static func open(host: Control, title: String, subtitle: String = "") -> Sheet:
	var sheet := Sheet.new()
	host.add_child(sheet)
	sheet._build(title, subtitle)
	return sheet


func _build(title: String, subtitle: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.015, 0.01, 0.7)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(event: InputEvent):
		if Touch.tapped(veil, event):
			close())
	add_child(veil)

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.085, 0.075, 0.06, 0.99)
	box.border_color = Color(Palette.ACCENT, 0.45)
	box.border_width_top = 3
	box.corner_radius_top_left = 18
	box.corner_radius_top_right = 18
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 16
	box.content_margin_bottom = 14
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 20
	_panel.add_theme_stylebox_override("panel", box)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_top = 0.12
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)
	var head := HBoxContainer.new()
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", -2)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Palette.ACCENT)
	words.add_child(heading)
	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 14)
		sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		words.add_child(sub)
	head.add_child(words)
	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(96, 44)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(close)
	head.add_child(close_button)
	rows.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	# Rises into place: offsets rather than position, so the motion does not
	# depend on whether layout has happened yet.
	_panel.offset_top = 60.0
	_panel.offset_bottom = 60.0
	modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	for side in ["offset_top", "offset_bottom"]:
		tween.tween_property(_panel, side, 0.0, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func clear() -> void:
	for child in body.get_children():
		child.queue_free()


func close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func():
		closed.emit()
		queue_free())
