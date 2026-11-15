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

## Asks the shell to follow a portent to whoever or wherever it is about.
signal reveal_requested(id: StringName)
signal tab_requested(id: String)

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

	# A war under way comes before everything else: it is what is happening.
	var fighting := CivilWar.wars()
	if not fighting.is_empty():
		_rows.add_child(_heading("戦", "割れた国が戦っている。棒は戦況、中央の線が開戦時"))
		for war in fighting:
			_rows.add_child(_war_card(war))
		_rows.add_child(_spacer())

	# What is brewing, of every kind, most pressing first — the same list the
	# map shows a line of, here in full.
	_rows.add_child(_heading("兆し", "いま起きそうなこと。タップするとそれを見に行ける"))
	for item in Portents.current(SimClock.current_tick):
		_rows.add_child(_portent_row(item))

	_rows.add_child(_spacer())
	_rows.add_child(_heading("四つの破局", "めったに起きず、起きれば世界が塗り替わる。棒は機運"))
	var pressures := Incidents.pressures()
	pressures.sort_custom(func(a, b): return float(a["pressure"]) > float(b["pressure"]))
	for entry in pressures:
		_rows.add_child(_pressure_row(entry))

	_rows.add_child(_spacer())
	_rows.add_child(_heading("起きたこと", ""))
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

	# Wars that have ended, and how.
	var past := CivilWar.past_wars()
	if not past.is_empty():
		_rows.add_child(_spacer())
		_rows.add_child(_heading("過ぎた戦", "どう終わり、誰が何を失ったか"))
		for e in past:
			_rows.add_child(_past_war_row(e))


## A war under way: who against whom, the tug of the line, what each side is
## made of, how long it has gone on, and the latest battles.
func _war_card(war: WarState) -> Control:
	var a := GameState.get_organization(war.side_a)
	var b := GameState.get_organization(war.side_b)
	var colour_a := Heraldry.of_org(a) if a != null else Palette.POLITY
	var colour_b := Heraldry.of_org(b) if b != null else Palette.DANGER
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED.lerp(Palette.DANGER, 0.06)
	box.border_color = Color(Palette.DANGER, 0.8)
	box.border_width_top = 3
	box.set_corner_radius_all(10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", box)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)

	var title := Label.new()
	title.text = "%s年目の%s" % [war.years(SimClock.current_tick) + 1,
		"再戦" if war.cause == "renewal" else "内戦"]
	title.add_theme_color_override("font_color", Palette.DANGER.lightened(0.2))
	title.add_theme_font_size_override("font_size", 15)
	rows.add_child(title)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 8)
	sides.add_child(_side_label(a, colour_a, HORIZONTAL_ALIGNMENT_LEFT))
	var versus := GlyphIcon.make(&"swords", Palette.TEXT_MUTED, 26)
	versus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sides.add_child(versus)
	sides.add_child(_side_label(b, colour_b, HORIZONTAL_ALIGNMENT_RIGHT))
	rows.add_child(sides)

	rows.add_child(WarBar.new().setup(colour_a, colour_b, war.front))

	if a != null and b != null:
		var sa := CivilWar.strength(a, war)
		var sb := CivilWar.strength(b, war)
		rows.add_child(_strength_line(sa, sb, a.short_name(), b.short_name()))
		var tired := Label.new()
		tired.text = "疲弊　%d%% ／ %d%%　　地域　%d ／ %d" % [
			int(minf(war.exhaustion_a, 1.0) * 100.0), int(minf(war.exhaustion_b, 1.0) * 100.0),
			a.governs_settlement_ids.size(), b.governs_settlement_ids.size()]
		tired.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		tired.add_theme_font_size_override("font_size", 14)
		rows.add_child(tired)

	var recent: Array[String] = []
	for i in range(war.battles.size() - 1, maxi(-1, war.battles.size() - 4), -1):
		var fought: Dictionary = war.battles[i]
		var victor := a if String(fought["winner"]) == "a" else b
		recent.append("%d年 %s（%s%s）" % [int(int(fought["tick"]) / SimConfig.TICKS_PER_YEAR),
			CivilWar.battle_name(StringName(fought["settlement_id"])),
			victor.short_name() if victor != null else "?",
			"・奪取" if bool(fought.get("taken", false)) else "の勝ち"])
	var log := Label.new()
	log.text = "最近の戦い　" + ("、".join(recent) if not recent.is_empty() else "まだない")
	if not war.defectors.is_empty():
		var names: Array[String] = []
		for id in war.defectors:
			var house := GameState.get_organization(id)
			if house != null:
				names.append(house.formal_name())
		log.text += "\n寝返り　" + "、".join(names)
	log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	log.add_theme_font_size_override("font_size", 14)
	rows.add_child(log)
	return card


func _side_label(polity: Organization, colour: Color, align: int) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var name := Label.new()
	name.text = polity.formal_name() if polity != null else "?"
	name.horizontal_alignment = align
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_color_override("font_color", colour.lightened(0.25))
	name.add_theme_font_size_override("font_size", 17)
	box.add_child(name)
	var house := CivilWar.ruling_house_of(polity)
	var under := Label.new()
	under.text = "%s方" % house.formal_name() if house != null else "長は空位"
	under.horizontal_alignment = align
	under.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	under.add_theme_font_size_override("font_size", 13)
	box.add_child(under)
	return box


## What each side's strength is made of: land and people, the families behind
## it, the guilds and factions behind it, and what is dragging it down.
func _strength_line(sa: Dictionary, sb: Dictionary, name_a: String, name_b: String) -> Control:
	var label := Label.new()
	var parts: Array[String] = []
	for entry in [["土地と民", "land"], ["諸家", "houses"], ["ギルド・派閥", "bodies"]]:
		parts.append("%s %.1f／%.1f" % [entry[0], float(sa[entry[1]]), float(sb[entry[1]])])
	var drag: Array[String] = []
	for entry in [["飢え", "food"], ["威信", "standing"], ["不満", "calm"], ["魔物", "monsters"]]:
		var x: float = sa[entry[1]]
		var y: float = sb[entry[1]]
		if absf(x - y) >= 0.05:
			drag.append("%sが%sの足を引く" % [entry[0], name_a if x < y else name_b])
	label.text = "力 %.1f ／ %.1f\n%s%s" % [float(sa["total"]), float(sb["total"]),
		"　".join(parts), "\n" + "、".join(drag) if not drag.is_empty() else ""]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.add_theme_font_size_override("font_size", 14)
	return label


func _past_war_row(e: HistoryEvent) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := GlyphIcon.make(&"swords", Palette.ACCENT_SOFT, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	var years := int(e.payload.get("years", 0))
	head.text = "%d年　%s（%d年・%d戦）" % [int(e.tick / SimConfig.TICKS_PER_YEAR),
		CivilWar.outcome_label(String(e.payload.get("outcome", ""))), years,
		int(e.payload.get("battles", 0))]
	head.add_theme_color_override("font_color", Palette.ACCENT)
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	var text := Label.new()
	var lines: Array = e.payload.get("aftermath", [])
	text.text = e.description + ("\n" + "、".join(lines) if not lines.is_empty() else "")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Palette.TEXT)
	text.add_theme_font_size_override("font_size", 16)
	box.add_child(text)
	row.add_child(box)
	return row


func _heading(text: String, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Palette.ACCENT)
	label.add_theme_font_size_override("font_size", 20)
	box.add_child(label)
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
		sub.add_theme_font_size_override("font_size", 13)
		box.add_child(sub)
	return box


## One thing that is brewing: what, how pressing, and a way to go and look.
func _portent_row(item: Dictionary) -> Control:
	var colour: Color = item["colour"]
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED.lerp(colour, 0.05)
	box.border_color = Color(colour, 0.75)
	box.border_width_left = 4
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := GlyphIcon.make(item["glyph"], colour, 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var title := Label.new()
	title.text = item["title"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.add_theme_font_size_override("font_size", 18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(title)
	var sub := Label.new()
	sub.text = item["sub"]
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	sub.add_theme_font_size_override("font_size", 14)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(sub)
	var go := GlyphIcon.make(&"play", Palette.TEXT_DIM, 14)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.gui_input.connect(func(event: InputEvent):
		if not Touch.tapped(card, event):
			return
		var subject := StringName(item.get("subject", &""))
		if item["tab"] == "lineage" and subject != &"":
			reveal_requested.emit(subject)
		elif item["tab"] != "incidents":
			tab_requested.emit(item["tab"]))
	return card


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
