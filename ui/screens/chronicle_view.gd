extends Control

## The chronicle: what happened, newest first, with filters for the kinds of
## events worth following. This is where the game is actually read.

const PAGE := 60

const FILTERS := [
	{"label": "すべて", "types": []},
	{"label": "分派", "types": [HistoryEvent.EventType.SCHISM, HistoryEvent.EventType.DISSOLVED]},
	{"label": "継承", "types": [HistoryEvent.EventType.SUCCESSION,
		HistoryEvent.EventType.POWER_TRANSFER, HistoryEvent.EventType.CONFLICT_RESOLVED]},
	{"label": "人物", "types": [HistoryEvent.EventType.BIRTH, HistoryEvent.EventType.DEATH,
		HistoryEvent.EventType.MARRIAGE]},
	{"label": "災厄", "types": [HistoryEvent.EventType.DISASTER_OCCURRED]},
]

var _filter_index := 0
var _shown := PAGE

@onready var _tabs: HBoxContainer = $Rows/Filters
@onready var _list: VBoxContainer = $Rows/Scroll/List
@onready var _scroll: ScrollContainer = $Rows/Scroll
@onready var _more: Button = $Rows/More


func _ready() -> void:
	for i in FILTERS.size():
		var button := Button.new()
		button.text = FILTERS[i]["label"]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_on_filter.bind(i))
		_tabs.add_child(button)

	_more.pressed.connect(_on_more)
	EventBus.event_recorded.connect(_on_event_recorded)
	EventBus.game_loaded.connect(_rebuild)
	_sync_tabs()
	_rebuild()


func on_shown() -> void:
	_rebuild()


func _on_filter(index: int) -> void:
	_filter_index = index
	_shown = PAGE
	_sync_tabs()
	_rebuild()
	_scroll.scroll_vertical = 0


func _sync_tabs() -> void:
	for i in _tabs.get_child_count():
		var button: Button = _tabs.get_child(i)
		button.button_pressed = i == _filter_index
		button.add_theme_color_override("font_color",
			Palette.ACCENT if button.button_pressed else Palette.TEXT_MUTED)


func _on_more() -> void:
	_shown += PAGE
	_rebuild()


var _pending_refresh := false

func _on_event_recorded(_event: HistoryEvent) -> void:
	# Events arrive in bursts during fast-forward; rebuilding per event would
	# rebuild the whole list dozens of times in one tick.
	if _pending_refresh or not is_visible_in_tree():
		return
	_pending_refresh = true
	_refresh_soon.call_deferred()


func _refresh_soon() -> void:
	_pending_refresh = false
	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var wanted: Array = FILTERS[_filter_index]["types"]
	var matched := 0
	var last_year := -99999

	for i in range(HistoryLog.buffer.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.buffer[i]
		if not wanted.is_empty() and not wanted.has(e.event_type):
			continue
		if e.description.strip_edges().is_empty():
			continue
		matched += 1
		if matched > _shown:
			break

		var year := int(e.tick / SimConfig.TICKS_PER_YEAR)
		if year != last_year:
			_list.add_child(_year_header(year))
			last_year = year
		_list.add_child(_entry(e))

	if matched == 0:
		var empty := Label.new()
		empty.text = "まだ何も起きていない。"
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 18)
		_list.add_child(empty)

	_more.visible = matched > _shown


func _year_header(year: int) -> Control:
	var label := Label.new()
	label.text = "%d年" % year
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _entry(e: HistoryEvent) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var marker := Panel.new()
	marker.custom_minimum_size = Vector2(4, 0)
	marker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = _colour_for(e)
	marker.add_theme_stylebox_override("panel", style)
	row.add_child(marker)

	var text := Label.new()
	text.text = e.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", Palette.TEXT)
	text.add_theme_font_size_override("font_size", 19)
	row.add_child(text)
	return row


func _colour_for(e: HistoryEvent) -> Color:
	match e.event_type:
		HistoryEvent.EventType.SCHISM:
			return Palette.ACCENT
		HistoryEvent.EventType.DISSOLVED, HistoryEvent.EventType.DEATH:
			return Palette.DANGER
		HistoryEvent.EventType.SUCCESSION, HistoryEvent.EventType.POWER_TRANSFER:
			return Palette.POLITY
		HistoryEvent.EventType.DISASTER_OCCURRED:
			return Palette.HOUSE
		HistoryEvent.EventType.BIRTH, HistoryEvent.EventType.MARRIAGE:
			return Palette.GOOD
		HistoryEvent.EventType.FOUNDING:
			return Palette.GUILD
	return Palette.TEXT_DIM
