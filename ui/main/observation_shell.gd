extends Control

## The navigation shell: a status strip that is always visible, one screen at a
## time, and a bottom dock to move between them.
##
## Nothing in here writes simulation state. Screens read GameState and listen to
## EventBus; the only outward action available anywhere in the UI is through
## GodPowerAPI, on the god-power screen.

signal new_world_requested
## The reader changed how the screen is arranged (bars hidden, margins widened).
signal display_changed

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
var _fx: FxLayer
var _help: Sheet

@onready var _root: Control = $Root
@onready var _status: Control = $Root/StatusBar
@onready var _screen_host: Control = $Root/ScreenHost
@onready var _news_bar: NewsBar = $Root/NewsBar
@onready var _dock: HBoxContainer = $Root/Dock


func _ready() -> void:
	# Every list on every screen lets a swipe reach its scroll, whichever control
	# the finger happened to land on. Screens are built later, as they are first
	# opened, so this watches for them rather than walking them now.
	if not get_tree().node_added.is_connected(Touch.let_swipes_through):
		get_tree().node_added.connect(Touch.let_swipes_through)
	_build_dock()
	_status.speed_changed.connect(_on_speed_changed)
	_status.oracle_requested.connect(show_tab.bind("god"))
	_status.help_requested.connect(show_help)
	# Ruptures take the screen wherever the reader is; headlines go to the bar
	# above the dock, which covers nothing.
	_news = NewsFeed.new()
	_screen_host.add_child(_news)
	_news.open_tab.connect(show_tab)
	_news.reveal_requested.connect(reveal)
	_news.headline.connect(_news_bar.push)
	_news_bar.followed.connect(_news.follow)
	_build_fx()
	show_tab("map")


## The moments worth a second of light: what the god foretold coming true, what
## the god called down landing, and the ruptures a history is remembered by.
func _build_fx() -> void:
	_fx = FxLayer.new()
	add_child(_fx)
	_fx.shake_target = _root
	Oracle.prophecy_resolved.connect(func(p: Dictionary):
		if p["state"] == "fulfilled":
			_fx.wash(Palette.ACCENT, 0.3, 1.0)
			_fx.burst(Palette.ACCENT, &"sun")
			_fx.rise("神威 +%d" % int(p["reward"]), Palette.ACCENT, _status.might_anchor()))
	Oracle.feat_unlocked.connect(func(_feat: Dictionary):
		_fx.burst(Palette.ACCENT, &"scroll", _news_bar.global_position - global_position
			+ Vector2(32, NewsBar.HEIGHT * 0.5), 0.3))
	_news.chapter_closed.connect(func(chapter: Dictionary):
		if is_visible_in_tree():
			_fx.caption("第%d章　%d〜%d年　閉幕" % [chapter["number"], chapter["start_year"],
				chapter["end_year"]], chapter["title"]))
	EventBus.world_reset.connect(func():
		if is_visible_in_tree():
			_fx.caption("0年", "新しい世界が興った"))
	_news.rupture.connect(func(item: Dictionary):
		if item.get("label", "") != "神託成就":
			_fx.wash(item["colour"], 0.38, 0.9)
			_fx.quake(0.4, 8.0))
	EventBus.event_recorded.connect(func(e: HistoryEvent):
		if e.event_type != HistoryEvent.EventType.DISASTER_OCCURRED or not is_visible_in_tree():
			return
		var def := ContentRegistry.get_disaster(StringName(e.payload.get("definition_id", "")))
		if def == null:
			return
		var colour := Palette.GOOD if def.is_benevolent else Palette.DANGER
		_fx.wash(colour, 0.3, 0.9)
		_fx.omen(Glyph.DISASTER_GLYPHS.get(def.definition_id, &"sun"), colour)
		if not def.is_benevolent:
			_fx.quake(0.3, 5.0))


## 「この画面の読み方」for whichever screen is open.
func show_help() -> void:
	if _help != null and is_instance_valid(_help):
		_help.close()
		return
	_help = HelpSheet.open(self, _current_id)
	move_child(_fx, get_child_count() - 1)


func current_tab() -> String:
	return _current_id


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
	Oracle.prophecies_changed.connect(_sync_oracle_badge)
	_sync_oracle_badge()


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
	_sync_oracle_badge()


## The god's tab carries a gold mark while no future has been spoken: the one
## thing in the game that waits on the reader.
func _sync_oracle_badge() -> void:
	for i in TABS.size():
		if TABS[i]["id"] == "god":
			var button := _dock.get_child(i) as DockButton
			button.badge_colour = Palette.ACCENT
			button.badge = Oracle.prophecies.is_empty()


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
				if screen.has_signal("tab_requested"):
					screen.tab_requested.connect(show_tab)
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


## Lets the settings say the screen's arrangement changed; main.gd owns the
## window and the margins.
func notify_display_changed() -> void:
	display_changed.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	# The dock sits on its own panel, ruled off from the screen above it.
	var dock_top := _dock.position.y
	draw_rect(Rect2(Vector2(0, dock_top), Vector2(size.x, size.y - dock_top)), Palette.PANEL)
	draw_line(Vector2(0, dock_top), Vector2(size.x, dock_top), Palette.LINE, 1.0)
