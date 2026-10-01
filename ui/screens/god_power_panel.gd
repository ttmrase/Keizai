extends Control

## Everything the player can actually do. Four dials that shape what the world
## provides, and a set of one-off calamities and blessings.
##
## Note what is not here: no way to name a ruler, back a faction, or force a
## split. Whatever the society does with any of this, it decides on its own.
##
## What *is* here is the other half of that bargain: each dial says who in the
## world it currently feeds, read off the same profiles the simulation scores
## power with. A god who can only change the weather should at least be able to
## see whose harvest it is.

const DIALS := [
	{"label": "鉱石", "glyph": &"gem", "colour": Color("8c95a6"),
		"get": "ore_supply_rate", "set": "set_ore_supply_rate", "max": 3.0,
		"world": &"global_ore", "hint": "採れる鉱石の量。",
		"words": ["枯渇", "乏しい", "平年", "豊か", "溢れる"], "bands": [0.05, 0.6, 1.4, 2.2]},
	{"label": "木材", "glyph": &"pine", "colour": Color("4f8a52"),
		"get": "wood_supply_rate", "set": "set_wood_supply_rate", "max": 3.0,
		"world": &"global_wood", "hint": "森の恵み。",
		"words": ["禿山", "乏しい", "平年", "豊か", "溢れる"], "bands": [0.05, 0.6, 1.4, 2.2]},
	{"label": "収穫", "glyph": &"wheat", "colour": Color("c8a64a"),
		"get": "harvest_rate_modifier", "set": "set_harvest_modifier", "max": 2.0,
		"world": &"global_harvest_modifier", "hint": "実りの豊かさ。凶作は飢えと不満を招く。",
		"words": ["大飢饉", "凶作", "平年", "豊作", "大豊作"], "bands": [0.05, 0.6, 1.3, 1.7]},
	{"label": "魔物", "glyph": &"claw", "colour": Color("b8503f"),
		"get": "monster_spawn_rate", "set": "set_monster_spawn_rate", "max": 3.0,
		"world": &"global_monster_threat_level", "hint": "魔物の湧く勢い。",
		"words": ["静穏", "まばら", "並", "多い", "跋扈"], "bands": [0.05, 0.6, 1.4, 2.2]},
]

## What each calamity does, in the words a chronicler would use. Read from what
## the definitions actually change, not what their names suggest.
const EFFECT_LINES := {
	&"drought": "実りが枯れ、飢えと不満が広がる",
	&"plague": "人が死に、家が絶えかねない",
	&"wildfire": "森が焼け、木材と実りが失われる",
	&"monster_incursion": "魔物が溢れ、武を頼む者が台頭する",
	&"bountiful_harvest": "実りが溢れ、飢えが遠のく",
	&"mineral_strike": "鉱脈が開け、職人と商人が潤う",
	&"blessed_grove": "森が茂り、木材が満ちる",
}

## How long a calamity card waits for the second tap that confirms it.
const ARM_SECONDS := 3.0

@onready var _rows: VBoxContainer = $Scroll/Rows
@onready var _new_world_confirm: ConfirmationDialog = $NewWorldConfirm

var _sliders: Array[HSlider] = []
var _values: Array[Label] = []
var _gainers: Array[Label] = []
var _cards: Dictionary = {}
var _armed: StringName = &""
var _armed_left := 0.0


func _ready() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_rows.add_theme_constant_override("separation", 12)
	_build_header()
	_rows.add_child(_section("世界の理", "上げ下げすると、誰かが力を得る"))
	for i in DIALS.size():
		_rows.add_child(_dial_card(i))
	_rows.add_child(_section("災厄と恵み", "二度押すと下る。世界全体に及ぶ"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for definition in GodPowerAPI.available_disasters():
		grid.add_child(_calamity_card(definition))
	_rows.add_child(grid)
	_rows.add_child(_section("観察", ""))
	_rows.add_child(_settings_card())
	var note := Label.new()
	note.text = "神が触れられるのは世界だけであり、人の営みではない。誰が王となり、どの組織が興り、どこで袂を分かつかは、すべて人の側が決める。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_rows.add_child(note)

	_new_world_confirm.confirmed.connect(_on_new_world_confirmed)
	EventBus.game_loaded.connect(_sync)
	EventBus.world_reset.connect(_sync)
	EventBus.power_recalculated.connect(func(_t): if is_visible_in_tree(): _sync())
	_sync()


func on_shown() -> void:
	_sync()


func _process(delta: float) -> void:
	if _armed == &"":
		return
	_armed_left -= delta
	if _armed_left <= 0.0:
		_disarm()


# ------------------------------------------------------------------ layout

func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(GlyphIcon.make(&"sun", Palette.ACCENT, 52))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	var title := Label.new()
	title.text = "神の御業"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Palette.ACCENT)
	words.add_child(title)
	var sub := Label.new()
	sub.text = "四つの理と七つの災厄。それが神の持つすべて。"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	words.add_child(sub)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_rows.add_child(row)


func _section(title: String, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(head)
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_font_size_override("font_size", 13)
		sub.add_theme_color_override("font_color", Palette.TEXT_DIM)
		box.add_child(sub)
	return box


static func _card_style(accent: Color, lit := false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_RAISED if not lit else Palette.PANEL_RAISED.lerp(accent, 0.18)
	box.border_color = accent if lit else Color(accent, 0.35)
	box.border_width_left = 4
	box.border_width_top = 1 if not lit else 2
	box.border_width_right = 1 if not lit else 2
	box.border_width_bottom = 1 if not lit else 2
	box.set_corner_radius_all(12)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


# ------------------------------------------------------------------- dials

func _dial_card(index: int) -> Control:
	var dial: Dictionary = DIALS[index]
	var colour: Color = dial["colour"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(colour))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	card.add_child(rows)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(GlyphIcon.make(dial["glyph"], colour, 36))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = dial["label"]
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	names.add_child(name_label)
	var hint := Label.new()
	hint.text = dial["hint"]
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Palette.TEXT_DIM)
	names.add_child(hint)
	head.add_child(names)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", colour.lightened(0.25))
	head.add_child(value)
	_values.append(value)
	rows.add_child(head)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = dial["max"]
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(0, 40)
	_style_slider(slider, colour)
	slider.value_changed.connect(_on_dial_changed.bind(index))
	rows.add_child(slider)
	_sliders.append(slider)

	var gainers := Label.new()
	gainers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gainers.add_theme_font_size_override("font_size", 14)
	gainers.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	rows.add_child(gainers)
	_gainers.append(gainers)
	return card


func _style_slider(slider: HSlider, colour: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.BG
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(colour.lightened(0.35))
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob)


## A round grabber, drawn into a texture once rather than shipped as an image.
static func _knob(colour: Color) -> Texture2D:
	var side := 28
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var centre := Vector2(side, side) * 0.5
	for y in side:
		for x in side:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var a := clampf(side * 0.5 - d, 0.0, 1.0)
			var ring := clampf(side * 0.5 - 3.0 - d, 0.0, 1.0)
			var c := colour if ring > 0.0 else Palette.INK
			image.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(image)


func _on_dial_changed(value: float, index: int) -> void:
	GodPowerAPI.call(DIALS[index]["set"], value)
	_values[index].text = _reading(index, value)


## The dial as a word. Measured against 1.0, which is an ordinary year, not
## against the top of the slider — "half way along" for a dial that runs to three
## is a good year, not a lean one.
func _reading(index: int, value: float) -> String:
	var words: Array = DIALS[index]["words"]
	var bands: Array = DIALS[index]["bands"]
	var at := words.size() - 1
	for i in bands.size():
		if value < float(bands[i]):
			at = i
			break
	return "%s　×%.2f" % [words[at], value]


## Whoever in the world is fed by this dial right now, read off the same driver
## tables power is scored with: those whose power rises with it, and those whose
## power rises when it falls.
func _who_gains(world_var: StringName) -> Dictionary:
	var up: Array[String] = []
	var down: Array[String] = []
	for org in GameState.active_organizations():
		var profile := ContentRegistry.get_power_profile(org.archetype_id)
		if profile == null:
			continue
		for driver in profile.drivers:
			if driver.world_var_path != world_var or driver.weight <= 0.0:
				continue
			if driver.invert:
				down.append(org.display_name)
			else:
				up.append(org.display_name)
			break
	return {"up": up, "down": down}


func _sync() -> void:
	for i in _sliders.size():
		var current: float = GodPowerAPI.get_dial(DIALS[i]["get"])
		_sliders[i].set_value_no_signal(current)
		_values[i].text = _reading(i, current)
		var gains := _who_gains(DIALS[i]["world"])
		var parts: Array[String] = []
		if not gains["up"].is_empty():
			parts.append("上げると　%s" % "・".join(gains["up"].slice(0, 3)))
		if not gains["down"].is_empty():
			parts.append("下げると　%s" % "・".join(gains["down"].slice(0, 3)))
		_gainers[i].text = "\n".join(parts) if not parts.is_empty() \
			else "いまこれに頼る組織はない"
	for id in _cards:
		_sync_card(id)


# -------------------------------------------------------------- calamities

func _calamity_card(definition: DisasterDefinition) -> Control:
	var tint: Color = Palette.GOOD if definition.is_benevolent else Palette.DANGER
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 132)
	card.add_theme_stylebox_override("panel", _card_style(tint))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rows)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(GlyphIcon.make(Glyph.DISASTER_GLYPHS.get(definition.definition_id, &"sun"),
		tint, 34))
	var name_label := Label.new()
	name_label.text = definition.display_name
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	rows.add_child(head)

	var effect := Label.new()
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_font_size_override("font_size", 13)
	effect.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(effect)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", tint.lightened(0.2))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(status)

	card.gui_input.connect(_on_card_input.bind(definition))
	_cards[definition.definition_id] = {"card": card, "effect": effect, "status": status,
		"definition": definition, "tint": tint}
	_sync_card(definition.definition_id)
	return card


func _sync_card(id: StringName) -> void:
	var entry: Dictionary = _cards[id]
	var definition: DisasterDefinition = entry["definition"]
	var armed := _armed == id
	(entry["card"] as PanelContainer).add_theme_stylebox_override("panel",
		_card_style(entry["tint"], armed))
	(entry["effect"] as Label).text = "もう一度押すと下る" if armed \
		else EFFECT_LINES.get(id, "")
	var remaining := _remaining(id)
	(entry["status"] as Label).text = "進行中　あと%d季" % remaining if remaining > 0 \
		else "%d季にわたる" % definition.duration_ticks


func _remaining(id: StringName) -> int:
	var left := 0
	for inst in GameState.world.active_disasters:
		if inst.definition_id == id:
			left = maxi(left, inst.start_tick + inst.duration_ticks - SimClock.current_tick)
	return left


func _on_card_input(event: InputEvent, definition: DisasterDefinition) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if not tapped:
		return
	var id := definition.definition_id
	if _armed != id:
		var previous := _armed
		_armed = id
		_armed_left = ARM_SECONDS
		if previous != &"":
			_sync_card(previous)
		_sync_card(id)
		return
	_disarm()
	GodPowerAPI.trigger_disaster(id, &"", 1.0)
	_flash(_cards[id]["card"])
	_sync_card(id)


func _disarm() -> void:
	var was := _armed
	_armed = &""
	if was != &"" and _cards.has(was):
		_sync_card(was)


func _flash(card: Control) -> void:
	var tween := card.create_tween()
	card.modulate = Color(1.8, 1.6, 1.2)
	tween.tween_property(card, "modulate", Color.WHITE, 0.45)


# ---------------------------------------------------------------- settings

func _settings_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(Palette.TEXT_MUTED))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	card.add_child(rows)

	var pause := CheckButton.new()
	pause.text = "大事件で時を止める"
	pause.button_pressed = UiSettings.auto_pause()
	pause.focus_mode = Control.FOCUS_NONE
	pause.add_theme_font_size_override("font_size", 17)
	pause.toggled.connect(UiSettings.set_auto_pause)
	rows.add_child(pause)
	var pause_note := Label.new()
	pause_note.text = "政変や事件が起きたとき、読み終えるまで時を止める。"
	pause_note.add_theme_font_size_override("font_size", 13)
	pause_note.add_theme_color_override("font_color", Palette.TEXT_DIM)
	rows.add_child(pause_note)

	var new_world := Button.new()
	new_world.text = "新しい世界を興す"
	new_world.focus_mode = Control.FOCUS_NONE
	new_world.custom_minimum_size = Vector2(0, 50)
	new_world.add_theme_font_size_override("font_size", 17)
	new_world.pressed.connect(func(): _new_world_confirm.popup_centered())
	rows.add_child(new_world)
	return card


## Asks for a world rather than making one: creating it belongs to main, not to
## a screen.
func _on_new_world_confirmed() -> void:
	var shell := get_parent()
	while shell != null and not shell.has_method("request_new_world"):
		shell = shell.get_parent()
	if shell != null:
		shell.request_new_world()
