class_name NewsBar
extends Control

## The latest headline, in one line, just above the dock.
##
## Headlines used to slide in over the top of whatever screen was open, which is
## exactly where every screen keeps its own controls: while there was news, the
## filters under it could not be reached, and at four times speed there is
## always news. So the news has a place of its own now. It never covers
## anything, it is always in the same spot, and a tap on it goes to whatever it
## is about.
##
## A burst of headlines is shown one after another; the last one stays, dimmed,
## until something else happens, so a glance always says what happened last.

signal followed(item: Dictionary)

const HEIGHT := 46
## How long a headline holds the bar before the next one waiting may take it.
const HOLD := 2.6
## After this long with nothing new, the headline fades back.
const FRESH := 9.0
const MAX_WAITING := 6

var _waiting: Array = []
var _current: Dictionary = {}
var _shown_for := 99.0
var _flash := 0.0

var _row: HBoxContainer
var _icon: GlyphIcon
var _label: Label
var _text: Label
var _more: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = 14
	_row.offset_right = -12
	_row.add_theme_constant_override("separation", 9)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_icon = GlyphIcon.make(&"scroll", Palette.TEXT_DIM, 22)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_icon)
	_label = _make_label(15, Palette.TEXT_MUTED)
	_row.add_child(_label)
	_text = _make_label(16, Palette.TEXT)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.clip_text = true
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_row.add_child(_text)
	_more = _make_label(13, Palette.TEXT_DIM)
	_row.add_child(_more)
	gui_input.connect(_on_input)
	EventBus.world_reset.connect(_reset)
	EventBus.game_loaded.connect(_reset)
	_reset()


func _make_label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A new world, or another one loaded: the bar starts from the last thing that
## world's record would have headlined, or from nothing.
func _reset() -> void:
	_waiting.clear()
	_current = {}
	for i in range(HistoryLog.buffer.size() - 1, maxi(-1, HistoryLog.buffer.size() - 400), -1):
		var item := NewsFeed.classify(HistoryLog.buffer[i])
		if int(item["weight"]) != NewsFeed.Weight.NONE:
			_current = item
			break
	_shown_for = FRESH
	_flash = 0.0
	_sync()


func push(item: Dictionary) -> void:
	if not _current.is_empty() and _current.get("text", "") == item.get("text", ""):
		return
	for waiting in _waiting:
		if waiting.get("text", "") == item.get("text", ""):
			return
	if _waiting.size() >= MAX_WAITING:
		# The oldest is already history by the time it would be read.
		_waiting.pop_front()
	_waiting.append(item)


func _process(delta: float) -> void:
	_shown_for += delta
	if not _waiting.is_empty() and (_current.is_empty() or _shown_for >= HOLD):
		_current = _waiting.pop_front()
		_shown_for = 0.0
		_flash = 1.0
		_sync()
		_row.position.y = 12.0
		_row.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_row, "position:y", 0.0, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_row, "modulate:a", 1.0, 0.18)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.4)
		queue_redraw()
	var dim := _waiting.is_empty() and _shown_for >= FRESH
	var want := 0.6 if dim else 1.0
	if not is_equal_approx(_text.modulate.a, want):
		_text.modulate.a = move_toward(_text.modulate.a, want, delta * 1.5)
		_label.modulate.a = _text.modulate.a
		_icon.modulate.a = _text.modulate.a


func _sync() -> void:
	if _current.is_empty():
		_icon.glyph = &"scroll"
		_icon.colour = Palette.TEXT_DIM
		_label.text = ""
		_text.text = "まだ語るべきことは起きていない"
		_text.add_theme_color_override("font_color", Palette.TEXT_DIM)
	else:
		var colour: Color = _current["colour"]
		_icon.glyph = _current["glyph"]
		_icon.colour = colour
		_label.text = _current["label"]
		_label.add_theme_color_override("font_color", colour.lightened(0.1))
		_text.text = String(_current["text"]).replace("\n", "　")
		_text.add_theme_color_override("font_color", Palette.TEXT)
	_more.text = "＋%d" % _waiting.size() if not _waiting.is_empty() else "▸"
	queue_redraw()


func _on_input(event: InputEvent) -> void:
	if Touch.tapped(self, event) and not _current.is_empty():
		followed.emit(_current)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PANEL)
	draw_line(Vector2.ZERO, Vector2(size.x, 0), Palette.LINE, 1.0)
	if _current.is_empty():
		return
	var colour: Color = _current["colour"]
	# The headline's colour on the leading edge, and washed across the bar for a
	# moment when it arrives.
	draw_rect(Rect2(0, 1, 4, size.y - 1), colour)
	if _flash > 0.0:
		draw_rect(Rect2(0, 1, size.x, size.y - 1), Color(colour, 0.28 * _flash))
