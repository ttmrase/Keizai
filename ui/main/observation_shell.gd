extends Control

## The navigation shell: a status strip that is always visible, one screen at a
## time, and a bottom dock to move between them.
##
## Nothing in here writes simulation state. Screens read GameState and listen to
## EventBus; the only outward action available anywhere in the UI is through
## GodPowerAPI, on the god-power screen.

signal new_world_requested

const TABS := [
	{"id": "map", "label": "世界", "scene": "res://ui/screens/WorldMapView.tscn"},
	{"id": "chronicle", "label": "年代記", "scene": "res://ui/screens/ChronicleView.tscn"},
	{"id": "lineage", "label": "系譜", "scene": "res://ui/screens/LineageView.tscn"},
	{"id": "relations", "label": "関係", "scene": "res://ui/screens/RelationsView.tscn"},
	{"id": "incidents", "label": "事件", "scene": "res://ui/screens/IncidentsView.tscn"},
	{"id": "power", "label": "勢力", "scene": "res://ui/screens/PowerDashboard.tscn"},
	{"id": "god", "label": "神の力", "scene": "res://ui/screens/GodPowerPanel.tscn"},
]

var _screens: Dictionary = {}
var _current_id: String = ""

@onready var _status: Control = $Root/StatusBar
@onready var _screen_host: Control = $Root/ScreenHost
@onready var _dock: HBoxContainer = $Root/Dock


func _ready() -> void:
	_build_dock()
	_status.speed_changed.connect(_on_speed_changed)
	show_tab("map")


func _build_dock() -> void:
	for tab in TABS:
		var button := Button.new()
		button.text = tab["label"]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 60)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(show_tab.bind(tab["id"]))
		_dock.add_child(button)


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
				_screen_host.add_child(screen)
				_screens[id] = screen
				break
	var active: Control = _screens.get(id)
	if active != null:
		active.visible = true
		if active.has_method("on_shown"):
			active.on_shown()
	_sync_dock()


func _sync_dock() -> void:
	for i in _dock.get_child_count():
		var button: Button = _dock.get_child(i)
		button.button_pressed = TABS[i]["id"] == _current_id
		button.add_theme_color_override("font_color",
			Palette.ACCENT if button.button_pressed else Palette.TEXT_MUTED)


func _on_speed_changed(scale: float) -> void:
	SimClock.set_time_scale(scale)


## Lets a screen ask for a fresh world without reaching into world generation
## itself — main.gd owns that.
func request_new_world() -> void:
	new_world_requested.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
