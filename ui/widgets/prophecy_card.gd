class_name ProphecyCard
extends RefCounted

## How a prophecy looks, wherever it is shown: offered, spoken, or settled.

const LOOKS := {
	ProphecyBook.HEGEMONY: ["覇権", &"bars", Color("d4a748")],
	ProphecyBook.THRONE: ["王座", &"crown", Color("b48fd0")],
	ProphecyBook.EXTINCTION: ["断絶", &"candle", Color("c85a4a")],
	ProphecyBook.NEW_FAITH: ["啓示", &"altar", Color("d0b48f")],
	ProphecyBook.BRANCH: ["分裂", &"split", Color("c8926f")],
	ProphecyBook.INCIDENT: ["破局", &"flame", Color("c85a4a")],
	ProphecyBook.REGIME: ["政変", &"banner", Color("b48fd0")],
	ProphecyBook.FALL: ["興亡", &"keep", Color("b48fd0")],
	ProphecyBook.GROWTH: ["繁栄", &"people", Color("7ab87a")],
	ProphecyBook.DECLINE: ["衰亡", &"plague", Color("c85a4a")],
	ProphecyBook.LONGEVITY: ["長寿", &"sparkle", Color("7ab87a")],
	ProphecyBook.ASCENT: ["叙爵", &"seal", Color("d4a748")],
}


static func look(p: Dictionary) -> Array:
	return LOOKS.get(String(p["kind"]), ["神託", &"sun", Palette.ACCENT])


## The card itself. `mode` is "offer", "active" or "past"; an offer carries the
## button that speaks it, which calls `on_declare`. Anything naming somebody can
## be followed to them through `on_follow`.
static func build(p: Dictionary, tick: int, mode: String,
		on_declare: Callable = Callable(), on_follow: Callable = Callable()) -> PanelContainer:
	var kind_look := look(p)
	var colour: Color = kind_look[2]
	var settled := mode == "past"
	var fulfilled: bool = settled and p["state"] == "fulfilled"
	if settled and not fulfilled:
		colour = Palette.TEXT_DIM

	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED.lerp(colour, 0.08 if mode == "active" else 0.03)
	box.border_color = Color(colour, 0.8 if mode == "active" else 0.4)
	box.border_width_left = 4
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.set_corner_radius_all(12)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10 if settled else 12
	box.content_margin_bottom = 10 if settled else 12
	card.add_theme_stylebox_override("panel", box)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	card.add_child(rows)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(GlyphIcon.make(kind_look[1], colour, 22 if settled else 26))
	var label := Label.new()
	label.text = kind_look[0]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", colour)
	head.add_child(label)
	# How bold the prophecy is: the bolder, the more it pays.
	var bold := ProphecyBook.stars(p)
	var stars := Label.new()
	stars.text = "★".repeat(bold) + "☆".repeat(3 - bold)
	stars.add_theme_font_size_override("font_size", 13)
	stars.add_theme_color_override("font_color", Color(colour, 0.9) if not settled else Palette.TEXT_DIM)
	stars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(stars)
	var right := Label.new()
	right.add_theme_font_size_override("font_size", 14)
	match mode:
		"offer":
			right.text = "神威 +%d" % int(p["reward"])
			right.add_theme_color_override("font_color", Palette.ACCENT)
		"active":
			right.text = "あと%d年　神威 +%d" % [ProphecyBook.years_left(p, tick), int(p["reward"])]
			right.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		_:
			right.text = "成就 +%d" % int(p["reward"]) if fulfilled else "外れ"
			right.add_theme_color_override("font_color",
				Palette.ACCENT if fulfilled else Palette.TEXT_DIM)
	head.add_child(right)
	rows.add_child(head)

	var text := Label.new()
	text.text = p["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 16 if settled else 19)
	text.add_theme_color_override("font_color", Palette.TEXT_MUTED if settled else Palette.TEXT)
	rows.add_child(text)

	if mode == "active":
		var where := ProphecyBook.progress(p, tick)
		if not where.is_empty():
			var line := Label.new()
			line.text = "いま　%s" % where if not where.begins_with("いま") else where
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_size_override("font_size", 15)
			line.add_theme_color_override("font_color", colour.lightened(0.2))
			rows.add_child(line)
		# The race: how near the world stands, against how much time is gone.
		var span := maxf(1.0, float(int(p["deadline"]) - int(p["declared"])))
		var used := clampf(float(tick - int(p["declared"])) / span, 0.0, 1.0)
		var near := ProphecyBook.closeness(p, tick)
		if near >= 0.0:
			rows.add_child(_meter("近さ", near, colour))
		rows.add_child(_meter("時", used, Palette.TEXT_MUTED if used < 0.8 else Palette.DANGER))
	if mode == "offer":
		# Where things stand now, so the choice is made knowing the odds.
		var standing := ProphecyBook.progress(p, tick)
		if not standing.is_empty():
			var now := Label.new()
			now.text = "いま　%s" % standing if not standing.begins_with("いま") else standing
			now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			now.add_theme_font_size_override("font_size", 15)
			now.add_theme_color_override("font_color", colour.lightened(0.2))
			rows.add_child(now)
	if not settled:
		# How the god might bring it about: the most useful line on the card.
		var hint := Label.new()
		hint.text = "手がかり　%s" % p["hint"]
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		rows.add_child(hint)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	var target := StringName(p["target"])
	var followable := GameState.get_person(target) != null or GameState.get_organization(target) != null
	if followable and on_follow.is_valid():
		var follow := _small_button("系譜で見る", false)
		follow.pressed.connect(on_follow.bind(target))
		actions.add_child(follow)
	if mode == "offer" and on_declare.is_valid():
		var speak := _small_button("この神託を下す", true)
		speak.pressed.connect(on_declare)
		actions.add_child(speak)
	if actions.get_child_count() > 0:
		rows.add_child(actions)
	return card


## One of the two bars of the race, with its name beside it.
static func _meter(name: String, value: float, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = name
	label.custom_minimum_size = Vector2(34, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = value
	var back := StyleBoxFlat.new()
	back.bg_color = Palette.BG
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(colour, 0.85)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return row


static func _small_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 15)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT if primary else Color(0, 0, 0, 0)
	box.border_color = Palette.ACCENT
	box.set_border_width_all(0 if primary else 1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)
	var ink := Palette.INK if primary else Palette.ACCENT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	return button
