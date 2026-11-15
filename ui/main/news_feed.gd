class_name NewsFeed
extends Control

## News from the world while you are looking at something else.
##
## The chronicle records everything and the map ripples where it happens, but
## both have to be looked at. At four times speed a kingdom can fall between two
## glances at the family tree, and an observation game whose drama happens
## off-screen is not much of one. So the things a history will remember come to
## the reader instead: a headline in the news bar above the dock, and — for the
## ruptures — the whole screen, with the clock stopped so nothing is missed
## while it is read.
##
## It decides nothing about the world. It listens, sorts what it hears by how
## much it will matter in a century, and holds back the rest, so a fast hour of
## play reads as a sequence of headlines rather than a firehose.
##
## Headlines are handed on (`headline`) rather than drawn here: this control
## lies over the open screen, and anything it drew there would sit on top of
## that screen's own controls.

signal open_tab(id: String)
## Asks for the family tree opened on whoever a headline is about.
signal reveal_requested(id: StringName)
## Something worth a line in the news bar.
signal headline(item: Dictionary)
## A rupture has taken the screen: `item` is what it is.
signal rupture(item: Dictionary)
## Fifty years have closed and been given a name.
signal chapter_closed(chapter: Dictionary)

enum Weight { NONE, NOTABLE, MAJOR }

## At most one new banner in this many seconds, so a burst reads as a
## sequence rather than arriving in one heap.
const SPACING := 0.9

var _waiting: Array = []
var _since_last := 99.0
var _banner: Control
## Where the banner that is open keeps its text, so a rupture that brings down
## a regime in the same season reads as one story rather than two banners.
var _banner_rows: VBoxContainer
## The speed the reader was watching at before a rupture stopped the clock.
var _resume_speed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.event_recorded.connect(_on_event)
	EventBus.world_reset.connect(_clear)
	EventBus.game_loaded.connect(_clear)
	EventBus.tick_advanced.connect(_on_tick)
	Oracle.prophecy_resolved.connect(_on_prophecy)
	Oracle.prophecy_nearing.connect(_on_prophecy_nearing)
	Oracle.prophecy_pressing.connect(_on_prophecy_pressing)
	Oracle.feat_unlocked.connect(_on_feat)


func _clear() -> void:
	_waiting.clear()
	if _banner != null:
		_banner.queue_free()
		_banner = null


func _process(delta: float) -> void:
	_since_last += delta
	if _waiting.is_empty() or _since_last < SPACING:
		return
	var next: Dictionary = _waiting.pop_front()
	_since_last = 0.0
	if _banner != null and is_instance_valid(_banner_rows):
		_follow_up(next)
	else:
		_show_banner(next)


# ---------------------------------------------------------------- sorting

func _on_event(e: HistoryEvent) -> void:
	_queue(classify(e))


## The god's own news: a prophecy fulfilled is as large a moment as any rupture,
## and is announced like one.
func _on_prophecy(p: Dictionary) -> void:
	var fulfilled: bool = p["state"] == "fulfilled"
	var year := int(int(p["resolved"]) / SimConfig.TICKS_PER_YEAR)
	if fulfilled:
		_queue({"weight": Weight.MAJOR, "label": "神託成就", "colour": Palette.ACCENT,
			"glyph": &"sun", "tab": "god", "subject": &"", "year": year,
			"kicker": "%d年　告げた未来が来た" % year,
			"text": "「%s」\n神威 +%d" % [p["text"], int(p["reward"])]})
	else:
		_queue({"weight": Weight.NOTABLE, "label": "神託外れ", "colour": Palette.TEXT_MUTED,
			"glyph": &"scroll", "tab": "god", "subject": &"", "year": year,
			"text": "「%s」は果たされなかった" % p["text"]})


## The race between a prophecy and its deadline, told as it turns: when the
## world draws near to bearing it out, and when the time is nearly gone.
func _on_prophecy_nearing(p: Dictionary, closeness: float) -> void:
	var where := ProphecyBook.progress(p, SimClock.current_tick)
	_queue({"weight": Weight.NOTABLE, "label": "神託近づく", "colour": Palette.ACCENT,
		"glyph": &"sparkle", "tab": "god", "subject": &"", "year": SimClock.year(),
		"text": "「%s」まであと一歩%s" % [ProphecyBook.headline(p),
			"（%s）" % where if not where.is_empty() else ""] if closeness >= 0.85
			else "「%s」に世が傾きはじめた%s" % [ProphecyBook.headline(p),
			"（%s）" % where if not where.is_empty() else ""]})


func _on_prophecy_pressing(p: Dictionary, years_left: int) -> void:
	_queue({"weight": Weight.NOTABLE, "label": "刻限迫る", "colour": Palette.DANGER,
		"glyph": &"sparkle", "tab": "god", "subject": &"", "year": SimClock.year(),
		"text": "「%s」——残り%d年" % [ProphecyBook.headline(p), years_left]})


func _on_feat(feat: Dictionary) -> void:
	_queue({"weight": Weight.NOTABLE, "label": "史録　%s" % feat["title"],
		"colour": Palette.ACCENT, "glyph": feat["glyph"], "tab": "god", "subject": &"",
		"year": int(feat.get("year", SimClock.year())), "text": feat["text"]})


## Every fifty years the chronicle closes a chapter and names it.
func _on_tick(tick: int) -> void:
	if tick <= 0 or tick % EraBook.CHAPTER_TICKS != 0:
		return
	var chapter := EraBook.chapter(int(tick / EraBook.CHAPTER_TICKS) - 1)
	if chapter.is_empty():
		return
	var lines: Array = chapter["lines"]
	chapter_closed.emit(chapter)
	_queue({"weight": Weight.NOTABLE, "label": "第%d章　閉幕" % chapter["number"],
		"colour": Palette.ACCENT_SOFT.lightened(0.3), "glyph": &"scroll", "tab": "chronicle",
		"subject": &"", "year": int(chapter["end_year"]),
		"text": "「%s」%s" % [chapter["title"], "　" + lines[0] if not lines.is_empty() else ""]})


func _queue(item: Dictionary) -> void:
	if item["weight"] == Weight.NONE:
		return
	if item["weight"] != Weight.MAJOR:
		headline.emit(item)
		return
	# A rupture is never dropped, and is told in the order it happened.
	_waiting.append(item)
	if UiSettings.auto_pause() and SimClock.time_scale > 0.0:
		_resume_speed = SimClock.time_scale
		SimClock.set_time_scale(0.0)
		item["paused"] = true


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
			if kind == "civil_war":
				return _item(e, Weight.MAJOR, "国が割れた", Palette.DANGER, &"split", "incidents")
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
		HistoryEvent.EventType.CONFLICT_DECLARED:
			if e.payload.has("war"):
				var renewal: bool = String(e.payload["war"].get("cause", "")) == "renewal"
				return _item(e, Weight.MAJOR, "再戦" if renewal else "開戦", Palette.DANGER,
					&"swords", "incidents")
		HistoryEvent.EventType.CONFLICT_RESOLVED:
			if e.payload.has("war_id"):
				var item := _item(e, Weight.MAJOR,
					CivilWar.outcome_label(String(e.payload.get("outcome", ""))),
					Palette.ACCENT, &"swords", "incidents")
				var lines: Array = e.payload.get("aftermath", [])
				if not lines.is_empty():
					var listed: Array[String] = []
					for line in lines:
						listed.append("・" + String(line))
					item["text"] = "%s\n%s" % [e.description, "\n".join(listed)]
				return item
		HistoryEvent.EventType.GREATNESS:
			return _item(e, Weight.NOTABLE, "偉人", Palette.ACCENT, &"laurel", "lineage")
		HistoryEvent.EventType.OFFICE:
			match String(e.payload.get("action", "")):
				"appoint":
					if String(e.payload.get("office", "")) == "regent":
						return _item(e, Weight.NOTABLE, "摂政", Palette.POLITY, &"crown", "power")
				"hereditary":
					if String(e.payload.get("house", "")) != "":
						return _item(e, Weight.NOTABLE,
							"摂関政治" if String(e.payload.get("office", "")) == "regent" else "家職",
							Palette.ACCENT, &"seal", "power")
				"heirs":
					if bool(e.payload.get("reordered", false)):
						return _item(e, Weight.NOTABLE, "跡目", Palette.HOUSE, &"crown", "power")
		HistoryEvent.EventType.DEATH:
			if bool(e.payload.get("killed_in_battle", false)):
				return _item(e, Weight.NOTABLE, "討死", Palette.DANGER, &"swords", "incidents")
			if bool(e.payload.get("executed", false)):
				return _item(e, Weight.NOTABLE, "処刑", Palette.DANGER, &"swords", "incidents")
		HistoryEvent.EventType.POWER_TRANSFER:
			if e.payload.has("war_id"):
				# The aftermath of a war is listed on the banner that ends it.
				if e.payload.has("battle"):
					return _item(e, Weight.NOTABLE, "合戦", Palette.DANGER, &"swords", "incidents")
				if e.payload.has("defector_house_id"):
					return _item(e, Weight.NOTABLE, "寝返り", Palette.HOUSE, &"banner", "incidents")
				return none
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
		"tab": tab, "text": e.description, "subject": subject_of(e),
		"year": int(e.tick / SimConfig.TICKS_PER_YEAR)}


## Who an event is about, for following it into the family tree. Births, deaths,
## marriages and successions are about a person; a founding, a split or an end
## is about the organization (and a split's subject is the new branch).
static func subject_of(e: HistoryEvent) -> StringName:
	var org_first := e.event_type in [HistoryEvent.EventType.FOUNDING,
		HistoryEvent.EventType.SCHISM, HistoryEvent.EventType.DISSOLVED,
		HistoryEvent.EventType.POWER_TRANSFER, HistoryEvent.EventType.IDEOLOGY_SHIFT,
		HistoryEvent.EventType.INCIDENT]
	var org_id := e.subject_org_id if GameState.get_organization(e.subject_org_id) != null else &""
	var person_id := e.subject_person_id if GameState.get_person(e.subject_person_id) != null else &""
	if person_id == &"":
		for id in e.related_person_ids:
			if GameState.get_person(id) != null:
				person_id = id
				break
	if org_first:
		return org_id if org_id != &"" else person_id
	return person_id if person_id != &"" else org_id


## Goes where a headline points. One about a branch or a family opens the tree
## on it, rather than leaving the reader to find it among everyone else.
func follow(item: Dictionary) -> void:
	if item["tab"] == "lineage" and StringName(item.get("subject", &"")) != &"":
		reveal_requested.emit(item["subject"])
	else:
		open_tab.emit(item["tab"])


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
	rupture.emit(item)

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
	kicker.text = item.get("kicker", "%d年　歴史が動いた" % item["year"])
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
		follow(item))
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
