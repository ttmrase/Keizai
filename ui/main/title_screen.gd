class_name TitleScreen
extends Control

## The first thing seen: the world drifting past under the title, a way back into
## the history already running, and a way to begin another.
##
## The first time anyone opens the game, three cards say what kind of game it is
## before they are left with it — because "you can only change the weather" is the
## single most surprising thing about it, and the one that makes everything else
## make sense. After that the cards are not shown again.
##
## It builds no world. Asking for a new one is a signal; main owns world creation,
## exactly as the god panel's button does.

signal continue_requested
signal new_world_requested
signal leaving
signal dismissed

const MAP_SIZE := Vector2(1000, 1450)

const GUIDE := [
	{"glyph": &"sun", "title": "神にできるのは、世界を変えることだけ",
		"body": "鉱石・木材・収穫・魔物の四つの理と、七つの災厄と恵み。誰を王にするかも、どの組織を潰すかも、神には選べない。"},
	{"glyph": &"tree", "title": "人は勝手に興り、争い、分かれる",
		"body": "家が婚姻で結ばれ、ギルドや信仰が生まれ、国が倒れては建つ。どれほど枝分かれしても、すべては最初のひとつまで辿れる。"},
	{"glyph": &"map", "title": "地図と事件を見ていよう",
		"body": "地図は誰が何を治めているかを示し、事件の画面は次の破局がどこまで近づいているかを示す。大事件が起きたら、時は止まって知らせてくれる。"},
]

var _land: ColorRect
var _material: ShaderMaterial
var _clock := 0.0
var _menu: VBoxContainer
var _guide_index := -1
var _guide_card: PanelContainer
var _after_guide := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_title()
	_build_menu()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)


func _process(delta: float) -> void:
	_clock += delta
	if _material == null:
		return
	# The continent drifts slowly under the title, as if seen from a height.
	var zoom := 1.15 + 0.08 * sin(_clock * 0.05)
	var centre := MAP_SIZE * 0.5 + Vector2(sin(_clock * 0.035) * 180.0, cos(_clock * 0.027) * 260.0)
	_material.set_shader_parameter("canvas_size", size)
	_material.set_shader_parameter("view_zoom", zoom)
	_material.set_shader_parameter("view_offset", size * 0.5 - centre * zoom)


# ---------------------------------------------------------------- building

func _build_backdrop() -> void:
	_material = MapMaterial.create()
	MapMaterial.feed_world(_material, MAP_SIZE)
	_land = ColorRect.new()
	_land.material = _material
	_land.set_anchors_preset(Control.PRESET_FULL_RECT)
	_land.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_land)

	# A dark sky over the top and a dark table under the bottom, so the words
	# sit on something.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0.03, 0.025, 0.02, 0.92),
		Color(0.03, 0.025, 0.02, 0.35), Color(0.03, 0.025, 0.02, 0.25),
		Color(0.03, 0.025, 0.02, 0.96)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 8
	texture.height = 256
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _build_title() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 150
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var mark := GlyphIcon.make(&"sun", Palette.ACCENT, 64)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)

	var spaced := FontVariation.new()
	spaced.base_font = get_theme_default_font()
	spaced.spacing_glyph = 14
	var title := Label.new()
	title.text = "KEIZAI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", spaced)
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", Palette.ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 3)
	box.add_child(title)

	var tagline := Label.new()
	tagline.text = "神は世界を変え、人は歴史を変える"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 20)
	tagline.add_theme_color_override("font_color", Palette.TEXT)
	tagline.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	tagline.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(tagline)


func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_menu.offset_left = 40
	_menu.offset_right = -40
	_menu.offset_bottom = -70
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.add_theme_constant_override("separation", 12)
	add_child(_menu)

	var realm := HouseRank.dominant_realm()
	var form := PolityFormEvaluator.form_of(realm) if realm != null else null
	var resume := _button("続きから", true)
	resume.pressed.connect(_on_continue)
	_menu.add_child(resume)
	var where := Label.new()
	where.text = "%d年　%s　・　%d家" % [SimClock.year(),
		form.display_name if form != null else "国なき世",
		GameState.organizations_of_kind(Organization.OrgKind.HOUSE).size()]
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.add_theme_font_size_override("font_size", 14)
	where.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_menu.add_child(where)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_menu.add_child(spacer)
	var fresh := _button("新しい世界を興す", false)
	fresh.pressed.connect(_on_new_world)
	_menu.add_child(fresh)


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 62)
	button.add_theme_font_size_override("font_size", 22)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT if primary else Color(0.08, 0.07, 0.05, 0.85)
	box.border_color = Palette.ACCENT
	box.set_border_width_all(0 if primary else 1)
	box.set_corner_radius_all(14)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 10
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)
	var ink := Palette.INK if primary else Palette.ACCENT
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	return button


# ----------------------------------------------------------------- choices

func _on_continue() -> void:
	continue_requested.emit()
	_maybe_guide("continue")


func _on_new_world() -> void:
	new_world_requested.emit()
	MapMaterial.feed_world(_material, MAP_SIZE)
	_maybe_guide("new")


## The guide is shown once, ever. Everybody after that knows what game this is.
func _maybe_guide(after: String) -> void:
	_after_guide = after
	if bool(UiSettings.get_value("seen_intro", false)):
		_leave()
		return
	_menu.visible = false
	_guide_index = 0
	_show_guide_card()


func _show_guide_card() -> void:
	if _guide_card != null:
		_guide_card.queue_free()
	var step: Dictionary = GUIDE[_guide_index]
	_guide_card = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.06, 0.05, 0.96)
	box.border_color = Color(Palette.ACCENT, 0.5)
	box.set_border_width_all(1)
	box.border_width_top = 4
	box.set_corner_radius_all(16)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 24
	box.content_margin_bottom = 20
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 18
	_guide_card.add_theme_stylebox_override("panel", box)
	_guide_card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_guide_card.offset_left = 30
	_guide_card.offset_right = -30
	_guide_card.offset_bottom = -60
	_guide_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_guide_card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	_guide_card.add_child(rows)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(GlyphIcon.make(step["glyph"], Palette.ACCENT, 44))
	var count := Label.new()
	count.text = "%d / %d" % [_guide_index + 1, GUIDE.size()]
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Palette.TEXT_DIM)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(count)
	rows.add_child(head)
	var title := Label.new()
	title.text = step["title"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Palette.ACCENT)
	rows.add_child(title)
	var body := Label.new()
	body.text = step["body"]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Palette.TEXT)
	rows.add_child(body)
	var last := _guide_index == GUIDE.size() - 1
	var next := _button("始める" if last else "次へ", true)
	next.custom_minimum_size = Vector2(0, 54)
	next.pressed.connect(_on_guide_next)
	rows.add_child(next)

	_guide_card.modulate.a = 0.0
	create_tween().tween_property(_guide_card, "modulate:a", 1.0, 0.25)


func _on_guide_next() -> void:
	_guide_index += 1
	if _guide_index >= GUIDE.size():
		UiSettings.set_value("seen_intro", true)
		_leave()
		return
	_show_guide_card()


func _leave() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaving.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.tween_callback(func():
		dismissed.emit()
		queue_free())
