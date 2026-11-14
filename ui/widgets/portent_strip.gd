class_name PortentStrip
extends PanelContainer

## One line of what is brewing, over the map: the most pressing portents in
## turn, each a tap away from where it can be watched.
##
## The map is the screen the game opens on and returns to, and by itself it only
## says who holds what. This is what gives it a pulse: the prophecy that has
## eleven years left, the capital about to be taken, the old king. It is also
## where a new god is told the one thing worth doing first.

signal chosen(item: Dictionary)

## How many of the most pressing are shown in turn, and for how long each.
const SHOWN := 4
const TURN_SECONDS := 4.5

var _items: Array[Dictionary] = []
var _index := 0
var _since := 0.0
var _icon: GlyphIcon
var _label: Label
var _title: Label
var _sub: Label
var _dots: Control
var _box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.06, 0.05, 0.04, 0.86)
	_box.border_color = Color(Palette.ACCENT, 0.5)
	_box.border_width_left = 4
	_box.set_corner_radius_all(12)
	_box.content_margin_left = 12
	_box.content_margin_right = 12
	_box.content_margin_top = 7
	_box.content_margin_bottom = 7
	_box.shadow_color = Color(0, 0, 0, 0.35)
	_box.shadow_size = 6
	add_theme_stylebox_override("panel", _box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = GlyphIcon.make(&"sparkle", Palette.ACCENT, 30)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", -2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(head)
	_label = _line(13, Palette.ACCENT)
	# The kind of portent is one short word and is never cut short.
	_label.clip_text = false
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	head.add_child(_label)
	_title = _line(17, Palette.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_sub = _line(13, Palette.TEXT_MUTED)
	words.add_child(_sub)
	_dots = Control.new()
	_dots.custom_minimum_size = Vector2(16, 0)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	row.add_child(_dots)

	gui_input.connect(_on_input)
	EventBus.power_recalculated.connect(func(_t): if is_visible_in_tree(): refresh())
	EventBus.world_reset.connect(refresh)
	EventBus.game_loaded.connect(refresh)
	Oracle.prophecies_changed.connect(refresh)
	refresh()


func _line(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Reads the world again. Whatever was being shown stays if it is still on the
## list, so the strip does not jump every time the list is re-read.
func refresh() -> void:
	var showing: String = _items[_index]["title"] if _index < _items.size() else ""
	_items = Portents.current(SimClock.current_tick).slice(0, SHOWN)
	_index = 0
	for i in _items.size():
		if _items[i]["title"] == showing:
			_index = i
	_show()


func _process(delta: float) -> void:
	if _items.size() <= 1 or not is_visible_in_tree():
		return
	_since += delta
	if _since < TURN_SECONDS:
		return
	_since = 0.0
	_index = (_index + 1) % _items.size()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.tween_callback(_show)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _show() -> void:
	if _items.is_empty():
		return
	var item: Dictionary = _items[_index]
	var colour: Color = item["colour"]
	_icon.glyph = item["glyph"]
	_icon.colour = colour
	_label.text = item["label"]
	_label.add_theme_color_override("font_color", colour.lightened(0.1))
	_title.text = item["title"]
	_sub.text = item["sub"]
	_box.border_color = Color(colour, 0.8)
	_dots.queue_redraw()


func _draw_dots() -> void:
	if _items.size() <= 1:
		Glyph.draw(_dots, &"play", _dots.size * 0.5, 10, Palette.TEXT_DIM)
		return
	var gap := 8.0
	var top := _dots.size.y * 0.5 - gap * float(_items.size() - 1) * 0.5
	for i in _items.size():
		_dots.draw_circle(Vector2(_dots.size.x * 0.5, top + gap * i), 2.5,
			Palette.ACCENT if i == _index else Color(1, 1, 1, 0.22))


func _on_input(event: InputEvent) -> void:
	if Touch.tapped(self, event) and _index < _items.size():
		chosen.emit(_items[_index])
