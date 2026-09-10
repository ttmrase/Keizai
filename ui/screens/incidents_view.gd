extends Control

## 事件 — the ruptures, and the pressures building toward the next one.
##
## Everything else in this world moves by degrees, and the screens that read it
## are built for degrees. This one is for the other kind of event: the handful of
## things that need several unlikely conditions at once and rearrange the board
## when they get them.
##
## The top half is the part worth having. A history of what already happened is
## the chronicle's job; what this screen adds is what is currently building — how
## close each rupture stands and what is still holding it back — so the player
## can watch a country arrive at its crisis instead of only reading about it
## afterwards. That is the whole game in miniature: you turn four dials, and this
## is where you find out what they were doing.

@onready var _rows: VBoxContainer = $Scroll/Rows


func _ready() -> void:
	EventBus.power_recalculated.connect(_on_recalculated)
	EventBus.game_loaded.connect(_rebuild)
	EventBus.world_reset.connect(_rebuild)
	_rebuild()


func on_shown() -> void:
	_rebuild()


func _on_recalculated(_tick: int) -> void:
	if is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()

	_rows.add_child(_heading("いま高まっているもの"))
	var pressures := Incidents.pressures()
	pressures.sort_custom(func(a, b): return float(a["pressure"]) > float(b["pressure"]))
	for entry in pressures:
		_rows.add_child(_pressure_row(entry))

	_rows.add_child(_spacer())
	_rows.add_child(_heading("起きたこと"))
	var found := 0
	for i in range(HistoryLog.buffer.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.buffer[i]
		if e.event_type != HistoryEvent.EventType.INCIDENT:
			continue
		_rows.add_child(_incident_row(e))
		found += 1
		if found >= 24:
			break
	if found == 0:
		var empty := Label.new()
		empty.text = "この世界はまだ、語り継がれるほどのことを経験していない。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 18)
		_rows.add_child(empty)


func _heading(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.add_theme_font_size_override("font_size", 20)
	return label


func _spacer() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	return gap


## One rupture: how close it stands, and the one thing most in its way.
func _pressure_row(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var name := Label.new()
	name.text = entry["label"]
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_color_override("font_color", Palette.TEXT)
	name.add_theme_font_size_override("font_size", 19)
	top.add_child(name)

	var reading := Label.new()
	var ready: float = float(entry["pressure"])
	reading.text = "%d%%" % int(ready * 100.0)
	reading.add_theme_color_override("font_color", Palette.severity(ready))
	reading.add_theme_font_size_override("font_size", 18)
	top.add_child(reading)
	box.add_child(top)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = ready
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.severity(ready)
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill)
	var trough := StyleBoxFlat.new()
	trough.bg_color = Palette.PANEL_RAISED
	trough.corner_radius_top_left = 4
	trough.corner_radius_top_right = 4
	trough.corner_radius_bottom_left = 4
	trough.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", trough)
	box.add_child(bar)

	var note := Label.new()
	var last: int = int(entry["last_tick"])
	var history := "" if last < 0 \
		else "　（前回 %d年）" % int(last / SimConfig.TICKS_PER_YEAR)
	note.text = "%s%s" % [entry["missing"], history]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	note.add_theme_font_size_override("font_size", 15)
	box.add_child(note)
	return box


func _incident_row(e: HistoryEvent) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var marker := Panel.new()
	marker.custom_minimum_size = Vector2(4, 0)
	marker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.DANGER
	marker.add_theme_stylebox_override("panel", style)
	row.add_child(marker)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var head := Label.new()
	head.text = "%d年　%s" % [int(e.tick / SimConfig.TICKS_PER_YEAR),
		Incidents.label_of(StringName(e.payload.get("incident_kind", "")))]
	head.add_theme_color_override("font_color", Palette.ACCENT)
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)

	var text := Label.new()
	text.text = e.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Palette.TEXT)
	text.add_theme_font_size_override("font_size", 18)
	box.add_child(text)

	row.add_child(box)
	return row
