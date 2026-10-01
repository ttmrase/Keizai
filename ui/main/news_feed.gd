class_name NewsFeed
extends Control

## News from the world while you are looking at something else.
##
## The chronicle records everything and the map ripples where it happens, but
## both have to be looked at. At four times speed a kingdom can fall between two
## glances at the family tree, and an observation game whose drama happens
## off-screen is not much of one. So the things a history will remember come to
## the reader instead: a strip of news across the top of whatever screen is open,
## and — for the ruptures — the whole screen, with the clock stopped so nothing
## is missed while it is read.
##
## It decides nothing about the world. It listens, sorts what it hears by how
## much it will matter in a century, and holds back the rest, so a fast hour of
## play reads as a sequence of headlines rather than a firehose.

signal open_tab(id: String)

enum Weight { NONE, NOTABLE, MAJOR }

const MAX_SHOWN := 3
const MAX_WAITING := 4
## At most one new headline in this many seconds, so a burst reads as a
## sequence rather than arriving in one heap.
const SPACING := 0.9
const NOTABLE_LIFE := 4.6

var _waiting: Array = []
var _shown: Array[Control] = []
var _since_last := 99.0
var _stack: VBoxContainer
var _banner: Control
## Where the banner that is open keeps its text, so a rupture that brings down
## a regime in the same season reads as one story rather than two banners.
var _banner_rows: VBoxContainer
## The speed the reader was watching at before a rupture stopped the clock.
var _resume_speed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack = VBoxContainer.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", 6)
	_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stack.offset_left = 10
	_stack.offset_right = -10
	_stack.offset_top = 8
	add_child(_stack)
	EventBus.event_recorded.connect(_on_event)
	EventBus.world_reset.connect(_clear)
	EventBus.game_loaded.connect(_clear)


func _clear() -> void:
	_waiting.clear()
	for card in _shown:
		card.queue_free()
	_shown.clear()
	if _banner != null:
		_banner.queue_free()
		_banner = null


func _process(delta: float) -> void:
	_since_last += delta
	if _waiting.is_empty() or _since_last < SPACING:
		return
	var next: Dictionary = _waiting.pop_front()
	_since_last = 0.0
	if next["weight"] == Weight.MAJOR:
		if _banner != null and is_instance_valid(_banner_rows):
			_follow_up(next)
		else:
			_show_banner(next)
	else:
		_show_card(next)


# ---------------------------------------------------------------- sorting

func _on_event(e: HistoryEvent) -> void:
	var item := classify(e)
	if item["weight"] == Weight.NONE:
		return
	if item["weight"] == Weight.MAJOR:
		# A rupture is never queued behind lesser news, and never dropped.
		_waiting.push_front(item)
		if UiSettings.auto_pause() and SimClock.time_scale > 0.0:
			_resume_speed = SimClock.time_scale
			SimClock.set_time_scale(0.0)
			item["paused"] = true
		return
	if _waiting.size() >= MAX_WAITING:
		# A burst of lesser news: the oldest is already history by the time it
		# would be read, so it goes first.
		for i in _waiting.size():
			if _waiting[i]["weight"] == Weight.NOTABLE:
				_waiting.remove_at(i)
				break
	_waiting.append(item)


## How much an event will matter to anybody reading the history later, and how
## to present it. Static so the map and the tests can ask the same question.
static func classify(e: HistoryEvent) -> Dictionary:
	var none := {"weight": Weight.NONE}
	match e.event_type:
		HistoryEvent.EventType.INCIDENT:
			return _item(e, Weight.MAJOR,
				Incidents.label_of(StringName(e.payload.get("incident_kind", ""))),
				Palette.DANGER, &"flame", "incidents")
		HistoryEvent.EventType.SCHISM:
			var kind := String(e.payload.get("schism_kind", ""))
			if kind == "refounding":
				return _item(e, Weight.MAJOR, "国の興亡", Palette.POLITY, &"crown", "lineage")
			var org := GameState.get_organization(e.subject_org_id)
			if org == null:
				return none
			if org.kind == Organization.OrgKind.HOUSE:
				if org.standing == Organization.Standing.RETAINER \
						and kind != "elopement" and kind != "recognition":
					return none
				return _item(e, Weight.NOTABLE, "分家", Palette.HOUSE, &"tree", "lineage")
			if org.kind == Organization.OrgKind.RELIGION:
				return _item(e, Weight.NOTABLE, "新たな信仰", Palette.RELIGION, &"altar", "lineage")
			return _item(e, Weight.NOTABLE, "分派", Palette.ACCENT, &"tree", "lineage")
		HistoryEvent.EventType.POWER_TRANSFER:
			if bool(e.payload.get("regime_change", false)):
				return _item(e, Weight.MAJOR, "政変", Palette.POLITY, &"crown", "power")
			if bool(e.payload.get("house_rising", false)):
				return _item(e, Weight.NOTABLE, "台頭", Palette.HOUSE, &"banner", "relations")
			if bool(e.payload.get("honour", false)):
				return _item(e, Weight.NOTABLE,
					"降格" if bool(e.payload.get("stripped", false)) else "叙勲",
					Palette.ACCENT, &"sparkle", "relations")
			if e.payload.has("person_fate") or e.payload.has("house_fate"):
				return _item(e, Weight.NOTABLE, "その後", Palette.TEXT_MUTED, &"people", "chronicle")
		HistoryEvent.EventType.SUCCESSION:
			var org := GameState.get_organization(e.subject_org_id)
			if org == null:
				return none
			if org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
				return _item(e, Weight.NOTABLE, "国の長", Palette.POLITY, &"crown", "chronicle")
			if bool(e.payload.get("contested", false)) and org.kind == Organization.OrgKind.HOUSE \
					and org.standing == Organization.Standing.NOBLE:
				return _item(e, Weight.NOTABLE, "家督争い", Palette.HOUSE, &"banner", "chronicle")
		HistoryEvent.EventType.DISASTER_OCCURRED:
			var def := ContentRegistry.get_disaster(StringName(e.payload.get("definition_id", "")))
			var good: bool = def != null and def.is_benevolent
			return _item(e, Weight.NOTABLE, def.display_name if def != null else "災厄",
				Palette.GOOD if good else Palette.HOUSE,
				Glyph.DISASTER_GLYPHS.get(def.definition_id if def != null else &"", &"sun"), "map")
		HistoryEvent.EventType.DISSOLVED:
			var org := GameState.get_organization(e.subject_org_id)
			if org != null and org.kind == Organization.OrgKind.HOUSE \
					and org.standing == Organization.Standing.NOBLE:
				return _item(e, Weight.NOTABLE, "断絶", Palette.TEXT_MUTED, &"banner", "chronicle")
	return none


static func _item(e: HistoryEvent, weight: int, label: String, colour: Color,
		glyph: StringName, tab: String) -> Dictionary:
	return {"weight": weight, "label": label, "colour": colour, "glyph": glyph,
		"tab": tab, "text": e.description,
		"year": int(e.tick / SimConfig.TICKS_PER_YEAR)}


# --------------------------------------------------------------- headlines

func _show_card(item: Dictionary) -> void:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.06, 0.05, 0.95)
	box.border_color = item["colour"]
	box.border_width_left = 5
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 8
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := GlyphIcon.make(item["glyph"], item["colour"], 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = item["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", item["colour"])
	head.add_child(label)
	var year := Label.new()
	year.text = "%d年" % item["year"]
	year.add_theme_font_size_override("font_size", 13)
	year.add_theme_color_override("font_color", Palette.TEXT_DIM)
	head.add_child(year)
	text.add_child(head)
	var body := Label.new()
	body.text = item["text"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.max_lines_visible = 2
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Palette.TEXT)
	text.add_child(body)

	card.gui_input.connect(_on_card_input.bind(card, item["tab"]))
	_stack.add_child(card)
	_shown.append(card)
	while _shown.size() > MAX_SHOWN:
		_dismiss(_shown[0])

	card.modulate.a = 0.0
	card.pivot_offset = Vector2(card.size.x * 0.5, 0)
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.22)
	tween.tween_interval(NOTABLE_LIFE)
	tween.tween_callback(_dismiss.bind(card))


func _on_card_input(event: InputEvent, card: Control, tab: String) -> void:
	var tapped: bool = (event is InputEventMouseButton and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)
	if not tapped:
		return
	open_tab.emit(tab)
	_dismiss(card)


func _dismiss(card: Control) -> void:
	if not is_instance_valid(card) or not _shown.has(card):
		return
	_shown.erase(card)
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 0.0, 0.25)
	tween.tween_callback(card.queue_free)


# ----------------------------------------------------------------- ruptures

## The whole screen, for the things a history is remembered by.
func _show_banner(item: Dictionary) -> void:
	if _banner != null:
		_banner.queue_free()
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.01, 0.01, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	_banner = veil

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(centre)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(620.0, size.x - 40.0), 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.06, 0.05, 0.98)
	box.border_color = item["colour"]
	box.set_border_width_all(2)
	box.border_width_top = 6
	box.set_corner_radius_all(14)
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 24
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 24
	box.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", box)
	centre.add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)
	_banner_rows = rows

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(GlyphIcon.make(item["glyph"], item["colour"], 58))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	var kicker := Label.new()
	kicker.text = "%d年　歴史が動いた" % item["year"]
	kicker.add_theme_font_size_override("font_size", 15)
	kicker.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	titles.add_child(kicker)
	var title := Label.new()
	title.text = item["label"]
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", item["colour"].lightened(0.15))
	titles.add_child(title)
	top.add_child(titles)
	rows.add_child(top)

	var rule := ColorRect.new()
	rule.color = Color(item["colour"], 0.4)
	rule.custom_minimum_size = Vector2(0, 1)
	rows.add_child(rule)

	var body := Label.new()
	body.text = item["text"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Palette.TEXT)
	rows.add_child(body)

	if item.get("paused", false):
		var note := Label.new()
		note.text = "時は止められている。読み終えたら再び流そう。"
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", Palette.TEXT_DIM)
		rows.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var close := _banner_button("見届ける", false)
	close.pressed.connect(func(): _close_banner(_resume_speed))
	buttons.add_child(close)
	var go := _banner_button("詳しく見る", true)
	go.pressed.connect(func():
		_close_banner(0.0)
		open_tab.emit(item["tab"]))
	buttons.add_child(go)
	rows.add_child(buttons)

	veil.modulate.a = 0.0
	card.scale = Vector2(0.94, 0.94)
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var tween := veil.create_tween().set_parallel(true)
	tween.tween_property(veil, "modulate:a", 1.0, 0.25)
	tween.tween_property(card, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _banner_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 19)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT if primary else Palette.PANEL_RAISED
	box.set_corner_radius_all(10)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)
	var ink := Palette.INK if primary else Palette.TEXT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	return button


## What followed from the rupture on the screen, in the same season: added to
## the open banner rather than replacing it before it has been read.
func _follow_up(item: Dictionary) -> void:
	var rule := ColorRect.new()
	rule.color = Color(item["colour"], 0.3)
	rule.custom_minimum_size = Vector2(0, 1)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var icon := GlyphIcon.make(item["glyph"], item["colour"], 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(icon)
	var text := Label.new()
	text.text = "%s　%s" % [item["label"], item["text"]]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	line.add_child(text)
	# Above the buttons, which are always last.
	var at := maxi(0, _banner_rows.get_child_count() - 1)
	_banner_rows.add_child(rule)
	_banner_rows.move_child(rule, at)
	_banner_rows.add_child(line)
	_banner_rows.move_child(line, at + 1)


## Resuming is left to the reader, except when they dismiss a rupture that
## stopped the clock — then the clock picks up at the speed they were watching at.
func _close_banner(resume_at: float) -> void:
	if _banner == null:
		return
	var closing := _banner
	_banner = null
	_banner_rows = null
	var tween := closing.create_tween()
	tween.tween_property(closing, "modulate:a", 0.0, 0.2)
	tween.tween_callback(closing.queue_free)
	if resume_at > 0.0 and SimClock.time_scale <= 0.0:
		SimClock.set_time_scale(resume_at)
	_resume_speed = 0.0
