extends Control

## The chronicle: what happened, newest first, with filters for the kinds of
## events worth following. This is where the game is actually read.
##
## It reads at two speeds. The births, marriages and deaths that make up most of
## any year are a quiet line each, with a small mark for what kind of thing
## happened; the events the news would have headlined — a house splitting, a
## regime falling, a rupture — stand out as cards, so a reader scrolling back a
## century sees its turning points first. Anything naming somebody can be tapped
## to open the family tree on them.

## Asks the shell to open the family tree on a person or organization.
signal reveal_requested(id: StringName)

const PAGE := 60
## How far a finger may move between press and release and still be a tap
## rather than the start of a scroll.
const TAP_SLOP := 14.0

const FILTERS := [
	{"label": "すべて", "types": []},
	{"label": "分派", "types": [HistoryEvent.EventType.SCHISM, HistoryEvent.EventType.DISSOLVED]},
	{"label": "継承", "types": [HistoryEvent.EventType.SUCCESSION,
		HistoryEvent.EventType.POWER_TRANSFER, HistoryEvent.EventType.CONFLICT_RESOLVED]},
	{"label": "人物", "types": [HistoryEvent.EventType.BIRTH, HistoryEvent.EventType.DEATH,
		HistoryEvent.EventType.MARRIAGE]},
	{"label": "災厄", "types": [HistoryEvent.EventType.DISASTER_OCCURRED,
		HistoryEvent.EventType.INCIDENT]},
	# The households in service generate most of the births, marriages and deaths
	# in the world. Left in the main feed they bury everything else, so they get
	# a page of their own rather than being thrown away.
	{"label": "側近家", "types": [], "service": true},
]

var _filter_index := 0
var _shown := PAGE
## When set, only what happened to this family is shown. A chronicle of the whole
## world is the point of the screen and also the reason one family's story is
## impossible to follow in it.
var _house_filter: StringName = &""

@onready var _tabs: HBoxContainer = $Rows/Filters
@onready var _list: VBoxContainer = $Rows/Scroll/List
@onready var _scroll: ScrollContainer = $Rows/Scroll
@onready var _more: Button = $Rows/More
@onready var _house_button: Button = $Rows/HouseRow/House
@onready var _picker: PanelContainer = $Picker
@onready var _picker_list: VBoxContainer = $Picker/Scroll/List


func _ready() -> void:
	for i in FILTERS.size():
		var button := Button.new()
		button.text = FILTERS[i]["label"]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_filter.bind(i))
		_tabs.add_child(button)

	_more.pressed.connect(_on_more)
	_house_button.pressed.connect(_on_house_button)
	EventBus.event_recorded.connect(_on_event_recorded)
	EventBus.game_loaded.connect(_on_world_changed)
	EventBus.world_reset.connect(_on_world_changed)
	_picker.visible = false
	_sync_tabs()
	_sync_house_button()
	_rebuild()


## A house filter cannot survive into a world where that house never existed.
func _on_world_changed() -> void:
	if GameState.get_organization(_house_filter) == null:
		_house_filter = &""
		_sync_house_button()
	_rebuild()


func on_shown() -> void:
	_sync_house_button()
	_rebuild()


# --------------------------------------------------------- one family's news

func _on_house_button() -> void:
	if _house_filter != &"":
		_house_filter = &""
		_sync_house_button()
		_shown = PAGE
		_rebuild()
		return
	_open_picker()


func _open_picker() -> void:
	for child in _picker_list.get_children():
		child.queue_free()
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)
	houses.sort_custom(func(a, b):
		var pa := HouseRank.precedence(a)
		var pb := HouseRank.precedence(b)
		return pa > pb if not is_equal_approx(pa, pb) else String(a.org_id) < String(b.org_id))
	for house in houses:
		var button := Button.new()
		button.text = "%s　%s" % [house.display_name, HouseRank.title_of_house(house)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 48)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_on_house_chosen.bind(house.org_id))
		_picker_list.add_child(button)
	_picker.visible = true


func _on_house_chosen(house_id: StringName) -> void:
	_house_filter = house_id
	_picker.visible = false
	_shown = PAGE
	_sync_house_button()
	_rebuild()
	_scroll.scroll_vertical = 0


func _sync_house_button() -> void:
	var house := GameState.get_organization(_house_filter)
	_house_button.text = "家で絞る" if house == null else "%sの記事のみ　✕" % house.display_name
	_house_button.add_theme_color_override("font_color",
		Palette.TEXT_MUTED if house == null else Palette.ACCENT)


## Whether this is news about a particular family: something that happened to the
## house itself, or to somebody who belongs to it.
func _concerns_house(e: HistoryEvent, house_id: StringName) -> bool:
	if e.subject_org_id == house_id:
		return true
	if _belongs(e.subject_person_id, house_id):
		return true
	for id in e.related_person_ids:
		if _belongs(id, house_id):
			return true
	for key in ["from_house_id", "to_house_id", "granted_by", "liege_house_id"]:
		if StringName(e.payload.get(key, "")) == house_id:
			return true
	# A cadet house leaving is news for the family it left.
	var born: Dictionary = e.payload.get("organization", {})
	return StringName(born.get("parent_org_id", "")) == house_id


func _belongs(person_id: StringName, house_id: StringName) -> bool:
	var p := GameState.get_person(person_id)
	return p != null and p.house_org_id == house_id


func _on_filter(index: int) -> void:
	_picker.visible = false
	_filter_index = index
	_shown = PAGE
	_sync_tabs()
	_rebuild()
	_scroll.scroll_vertical = 0


func _sync_tabs() -> void:
	for i in _tabs.get_child_count():
		Palette.style_pill(_tabs.get_child(i), i == _filter_index)


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
	var only_service: bool = FILTERS[_filter_index].get("service", false)
	var matched := 0
	var last_year := -99999

	for i in range(HistoryLog.buffer.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.buffer[i]
		if not wanted.is_empty() and not wanted.has(e.event_type):
			continue
		if Retainers.is_service_household_event(e) != only_service:
			continue
		if _house_filter != &"" and not _concerns_house(e, _house_filter):
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
		if _house_filter != &"":
			empty.text = "この家に伝えるべきことはまだない。"
		else:
			empty.text = "側近家の家中に目立った動きはない。" if only_service else "まだ何も起きていない。"
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 18)
		_list.add_child(empty)

	_more.visible = matched > _shown


func _year_header(year: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "%d年" % year
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(Palette.ACCENT, 0.22)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(spacer)
	box.add_child(row)
	return box


func _entry(e: HistoryEvent) -> Control:
	var news := NewsFeed.classify(e)
	var subject := NewsFeed.subject_of(e)
	var entry: Control
	if int(news["weight"]) == NewsFeed.Weight.NONE:
		entry = _quiet_line(e)
	else:
		entry = _milestone(e, news)
	if subject != &"":
		entry.mouse_filter = Control.MOUSE_FILTER_PASS
		entry.gui_input.connect(_on_entry_input.bind(subject))
	return entry


## One line for the ordinary business of a year.
func _quiet_line(e: HistoryEvent) -> Control:
	var look := _look_of(e)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := GlyphIcon.make(look["glyph"], look["colour"], 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.custom_minimum_size = Vector2(22, 28)
	row.add_child(icon)

	var text := Label.new()
	text.text = e.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", look["ink"])
	text.add_theme_font_size_override("font_size", 18)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	return row


## A card for a turning point: what kind of turn it was, in its colour, over
## the line itself. The ruptures are larger and lit from within.
func _milestone(e: HistoryEvent, news: Dictionary) -> Control:
	var major: bool = int(news["weight"]) == NewsFeed.Weight.MAJOR
	var colour: Color = news["colour"]
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL.lerp(colour, 0.12 if major else 0.04)
	box.border_color = colour if major else Color(colour, 0.85)
	box.border_width_left = 4
	if major:
		box.border_width_top = 1
		box.border_width_right = 1
		box.border_width_bottom = 1
		box.border_color = Color(colour, 0.7)
		box.border_width_left = 5
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10 if major else 8
	box.content_margin_bottom = 10 if major else 8
	card.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := GlyphIcon.make(news["glyph"], colour, 38 if major else 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rows)
	var label := Label.new()
	label.text = news["label"]
	label.add_theme_font_size_override("font_size", 19 if major else 15)
	label.add_theme_color_override("font_color", colour)
	rows.add_child(label)
	var text := Label.new()
	text.text = e.description
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Palette.TEXT)
	text.add_theme_font_size_override("font_size", 19 if major else 18)
	rows.add_child(text)
	return card


## A tap, not the end of a scroll, follows the entry to whoever it names.
var _press_at := Vector2.ZERO

func _on_entry_input(event: InputEvent, subject: StringName) -> void:
	# A touch also arrives as an emulated click; listening to the click alone
	# keeps one tap from being followed twice.
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_press_at = event.global_position
	elif event.global_position.distance_to(_press_at) <= TAP_SLOP:
		reveal_requested.emit(subject)


## The mark and the ink for an ordinary line. Births and marriages are the
## background hum of the world and are written a little softer than deaths and
## changes of hands.
func _look_of(e: HistoryEvent) -> Dictionary:
	match e.event_type:
		HistoryEvent.EventType.BIRTH:
			return {"glyph": &"sparkle", "colour": Palette.GOOD, "ink": Palette.TEXT_MUTED}
		HistoryEvent.EventType.MARRIAGE:
			return {"glyph": &"rings", "colour": Color("d0889a"), "ink": Palette.TEXT_MUTED}
		HistoryEvent.EventType.DEATH:
			return {"glyph": &"candle", "colour": Color(Palette.DANGER, 0.8), "ink": Palette.TEXT}
		HistoryEvent.EventType.SUCCESSION:
			return {"glyph": &"crown", "colour": Palette.POLITY, "ink": Palette.TEXT}
		HistoryEvent.EventType.POWER_TRANSFER:
			return {"glyph": &"banner", "colour": Palette.POLITY, "ink": Palette.TEXT}
		HistoryEvent.EventType.SCHISM:
			return {"glyph": &"split", "colour": Palette.ACCENT, "ink": Palette.TEXT}
		HistoryEvent.EventType.FOUNDING:
			return {"glyph": &"seal", "colour": Palette.GUILD, "ink": Palette.TEXT}
		HistoryEvent.EventType.DISSOLVED:
			return {"glyph": &"candle", "colour": Palette.TEXT_DIM, "ink": Palette.TEXT_MUTED}
		HistoryEvent.EventType.INCIDENT:
			return {"glyph": &"flame", "colour": Palette.DANGER, "ink": Palette.TEXT}
		HistoryEvent.EventType.DISASTER_OCCURRED:
			return {"glyph": &"drought", "colour": Palette.HOUSE, "ink": Palette.TEXT}
		HistoryEvent.EventType.CONFLICT_DECLARED, HistoryEvent.EventType.CONFLICT_RESOLVED:
			return {"glyph": &"unrest", "colour": Palette.DANGER, "ink": Palette.TEXT}
		HistoryEvent.EventType.IDEOLOGY_SHIFT:
			# A house's rank moving is written as a shift in what it stands for.
			if e.payload.has("to_tier"):
				var risen: bool = int(e.payload["to_tier"]) > int(e.payload.get("from_tier", 0))
				return {"glyph": &"seal", "colour": Palette.ACCENT if risen else Palette.TEXT_DIM,
					"ink": Palette.TEXT}
			return {"glyph": &"scroll", "colour": Palette.RELIGION, "ink": Palette.TEXT}
	return {"glyph": &"scroll", "colour": Palette.TEXT_DIM, "ink": Palette.TEXT_MUTED}
