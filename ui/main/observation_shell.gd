extends Control

## The navigation shell: a status strip that is always visible, one screen at a
## time, and a bottom dock to move between them.
##
## Nothing in here writes simulation state. Screens read GameState and listen to
## EventBus; the only outward action available anywhere in the UI is through
## GodPowerAPI, on the god-power screen.

signal new_world_requested

const TABS := [
	{"id": "map", "label": "世界", "glyph": &"map", "scene": "res://ui/screens/WorldMapView.tscn"},
	{"id": "chronicle", "label": "年代記", "glyph": &"scroll", "scene": "res://ui/screens/ChronicleView.tscn"},
	{"id": "lineage", "label": "系譜", "glyph": &"tree", "scene": "res://ui/screens/LineageView.tscn"},
	{"id": "relations", "label": "関係", "glyph": &"web", "scene": "res://ui/screens/RelationsView.tscn"},
	{"id": "incidents", "label": "事件", "glyph": &"flame", "scene": "res://ui/screens/IncidentsView.tscn"},
	{"id": "power", "label": "勢力", "glyph": &"bars", "scene": "res://ui/screens/PowerDashboard.tscn"},
	{"id": "god", "label": "神の力", "glyph": &"sun", "scene": "res://ui/screens/GodPowerPanel.tscn"},
]

## A rupture this close is worth a mark on its tab.
const BADGE_PRESSURE := 0.75

var _screens: Dictionary = {}
var _current_id: String = ""
var _news: NewsFeed

@onready var _status: Control = $Root/StatusBar
@onready var _screen_host: Control = $Root/ScreenHost
@onready var _dock: HBoxContainer = $Root/Dock


func _ready() -> void:
	_build_dock()
	_status.speed_changed.connect(_on_speed_changed)
	# The news sits over the screens and under nothing: whatever is open, a
	# headline can reach the reader.
	_news = NewsFeed.new()
	_screen_host.add_child(_news)
	_news.open_tab.connect(show_tab)
	_news.reveal_requested.connect(reveal)
	show_tab("map")


func _build_dock() -> void:
	for tab in TABS:
		var button := DockButton.new()
		button.glyph = tab["glyph"]
		button.caption = tab["label"]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 66)
		button.pressed.connect(show_tab.bind(tab["id"]))
		_dock.add_child(button)
	EventBus.power_recalculated.connect(_on_recalculated)


## The incidents tab carries a mark while any rupture stands close, so the
## pressure can be noticed from anywhere rather than only by going to look.
func _on_recalculated(tick: int) -> void:
	# The power screen's memory of who has been rising is kept here, where it
	# is fed whichever screen happens to be open.
	PowerHistory.sample(tick)
	var close := false
	for entry in Incidents.pressures():
		if float(entry["pressure"]) >= BADGE_PRESSURE:
			close = true
	for i in TABS.size():
		if TABS[i]["id"] == "incidents":
			(_dock.get_child(i) as DockButton).badge = close


func show_tab(id: String) -> void:
	if id == _current_id:
		_sync_dock()
		return
	_current_id = id

	for child in _screen_host.get_children():
		child.visible = false

	if not _screens.has(id):
		for tab in TABS:
			if tab["id"] == id:
				var screen: Control = load(tab["scene"]).instantiate()
				screen.set_anchors_preset(Control.PRESET_FULL_RECT)
				if screen.has_signal("reveal_requested"):
					screen.reveal_requested.connect(reveal)
				_screen_host.add_child(screen)
				_screens[id] = screen
				break
	var active: Control = _screens.get(id)
	if active != null:
		active.visible = true
		if active.has_method("on_shown"):
			active.on_shown()
	if _news != null:
		_news.visible = true
		_screen_host.move_child(_news, _screen_host.get_child_count() - 1)
	_sync_dock()


## Opens the family tree on a person or organization — wherever a screen or a
## headline names somebody, this is how the reader follows them. The tree is
## given a frame to take its size first, because it centres on what it opens.
func reveal(id: StringName) -> void:
	show_tab("lineage")
	await get_tree().process_frame
	var lineage: Control = _screens.get("lineage")
	if lineage != null and lineage.has_method("reveal"):
		lineage.reveal(id)


func _sync_dock() -> void:
	for i in _dock.get_child_count():
		var button: DockButton = _dock.get_child(i)
		button.button_pressed = TABS[i]["id"] == _current_id
		button.active = button.button_pressed


func _on_speed_changed(scale: float) -> void:
	SimClock.set_time_scale(scale)


## Lets a screen ask for a fresh world without reaching into world generation
## itself — main.gd owns that.
func request_new_world() -> void:
	new_world_requested.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	# The dock sits on its own panel, ruled off from the screen above it.
	var dock_top := _dock.position.y
	draw_rect(Rect2(Vector2(0, dock_top), Vector2(size.x, size.y - dock_top)), Palette.PANEL)
	draw_line(Vector2(0, dock_top), Vector2(size.x, dock_top), Palette.LINE, 1.0)
