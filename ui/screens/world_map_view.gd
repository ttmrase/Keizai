extends Control

## The world at a glance.
##
## The land itself is drawn by a shader (ui/shaders/world_map.gdshader): every
## region is the ground nearer its own town than any other, on a continent with a
## hatched coast and open sea beyond. Over it this script draws what a reader
## needs to find — roads between neighbours, the lie of the land, the towns
## themselves sized by how many live there, the capital's crown — and, when
## something happens somewhere, a ripple at that place so the eye knows where to
## look.
##
## What the regions are coloured by is the reader's choice: who holds them, what
## they believe, which state they answer to, how angry they are, what they live
## on. One map, five questions.

const MAP_SIZE := Vector2(1000, 1450)

enum Overlay { HOUSE, FAITH, REALM, UNREST, INDUSTRY }

const OVERLAYS := [
	{"id": Overlay.HOUSE, "label": "支配家"},
	{"id": Overlay.FAITH, "label": "信仰"},
	{"id": Overlay.REALM, "label": "国"},
	{"id": Overlay.UNREST, "label": "不満"},
	{"id": Overlay.INDUSTRY, "label": "産業"},
]

## How long a ripple stays on the map, in seconds of real time.
const PING_LIFE := 3.2
const MAX_PINGS := 7

@onready var _canvas: PannableCanvas = $Canvas
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Body
@onready var _rename_button: Button = $Detail/Margin/Rows/Rename

var _selected_id: StringName = &""
var _rename_dialog: RenameDialog
var _overlay: int = Overlay.HOUSE

var _land: ColorRect
var _land_material: ShaderMaterial
var _chips: HBoxContainer
var _legend: PanelContainer
var _legend_rows: VBoxContainer

## Settlement ids in a fixed order, so index n in the shader is always the same
## town between one frame and the next.
var _order: Array[StringName] = []
var _pings: Array = []
var _clock := 0.0


func _ready() -> void:
	_build_land()
	_build_chips()
	_build_legend()

	_canvas.draw.connect(_draw_map)
	_canvas.canvas_tapped.connect(_on_tapped)
	_canvas.resized.connect(_sync_land)
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.game_loaded.connect(_on_world_changed)
	EventBus.world_reset.connect(_on_world_changed)
	EventBus.event_recorded.connect(_on_event)
	_detail.visible = false

	_rename_dialog = RenameDialog.new()
	add_child(_rename_dialog)
	_rename_dialog.name_applied.connect(func(_id): _refresh())
	_rename_button.pressed.connect(_on_rename_pressed)

	_reorder()
	await get_tree().process_frame
	_frame_world()
	_refresh()


func on_shown() -> void:
	_refresh()


func _on_world_changed() -> void:
	_pings.clear()
	_selected_id = &""
	_detail.visible = false
	_reorder()
	_frame_world()
	_refresh()


func _reorder() -> void:
	_order.clear()
	for id in GameState.world.settlements:
		_order.append(id)
	_order.sort_custom(func(a, b): return String(a) < String(b))
	# A world seed shifts the noise, so two worlds do not share a coastline.
	if _land_material != null:
		var s := float(GameState.world.seed % 9973) / 9973.0
		_land_material.set_shader_parameter("noise_shift", Vector2(s, fmod(s * 7.13, 1.0)))


func _on_rename_pressed() -> void:
	var s: SettlementState = GameState.world.settlements.get(_selected_id)
	if s != null:
		_rename_dialog.open_for_settlement(_selected_id, s.display_name)


func _on_tick(tick: int) -> void:
	if tick % 4 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	_sync_land()
	_rebuild_legend()
	_canvas.queue_redraw()
	if _selected_id != &"":
		_show_detail(_selected_id)


func _process(delta: float) -> void:
	_clock += delta
	if not is_visible_in_tree():
		return
	if not _pings.is_empty():
		for ping in _pings:
			ping["age"] = float(ping["age"]) + delta
		_pings = _pings.filter(func(p): return float(p["age"]) < PING_LIFE)
		_canvas.queue_redraw()
	elif _has_restless_town():
		# The small flames over angry towns flicker, which needs a redraw now
		# and again — not every frame.
		if int(_clock * 8.0) != int((_clock - delta) * 8.0):
			_canvas.queue_redraw()


func _has_restless_town() -> bool:
	for id in GameState.world.settlements:
		if GameState.world.settlements[id].unrest >= 0.45:
			return true
	return false


func _frame_world() -> void:
	if _canvas.size.x < 1.0:
		return
	var fit: float = minf(_canvas.size.x / MAP_SIZE.x, (_canvas.size.y - 40.0) / MAP_SIZE.y) * 0.96
	_canvas.view_zoom = clampf(fit, _canvas.min_zoom, _canvas.max_zoom)
	_canvas.center_on(MAP_SIZE * 0.5 + Vector2(0, -12.0 / _canvas.view_zoom))


# ------------------------------------------------------------------ the land

func _build_land() -> void:
	_land_material = MapMaterial.create()
	_land_material.set_shader_parameter("map_size", MAP_SIZE)
	_land_material.set_shader_parameter("aspect", Vector2(1.0, MAP_SIZE.y / MAP_SIZE.x))

	_land = ColorRect.new()
	_land.material = _land_material
	_land.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_land.show_behind_parent = true
	_land.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_land)


## Hands the shader everything it draws from: where the towns are, what colour
## each region is under the current question, how angry each is, and whatever
## calamity is abroad.
func _sync_land() -> void:
	if _land_material == null:
		return
	var sites := PackedVector2Array()
	var tints: Array = []
	var unrest := PackedFloat32Array()
	var selected := -1
	for i in _order.size():
		var s: SettlementState = GameState.world.settlements.get(_order[i])
		if s == null:
			continue
		sites.append(s.position)
		tints.append(_tint_of(s))
		# Only real trouble smoulders, or every region glows faintly forever.
		unrest.append(clampf((s.unrest - 0.3) / 0.7, 0.0, 1.0))
		if s.id == _selected_id:
			selected = i
	for i in range(sites.size(), 16):
		sites.append(Vector2(-9, -9))
		tints.append(Color(0, 0, 0, 0))
		unrest.append(0.0)

	_land_material.set_shader_parameter("site_count", mini(_order.size(), 16))
	_land_material.set_shader_parameter("sites", sites)
	_land_material.set_shader_parameter("site_tint", tints)
	_land_material.set_shader_parameter("site_unrest", unrest)
	_land_material.set_shader_parameter("selected_site", selected)
	_sync_view()

	var fx := _calamity()
	_land_material.set_shader_parameter("fx_kind", fx["kind"])
	_land_material.set_shader_parameter("fx_strength", fx["strength"])


func _sync_view() -> void:
	if _land_material == null:
		return
	_land_material.set_shader_parameter("canvas_size", _canvas.size)
	_land_material.set_shader_parameter("view_offset", _canvas.view_offset)
	_land_material.set_shader_parameter("view_zoom", _canvas.view_zoom)


func _tint_of(s: SettlementState) -> Color:
	var c: Color
	match _overlay:
		Overlay.HOUSE:
			if GameState.get_organization(s.ruling_house_id) == null:
				return Color(0, 0, 0, 0)
			c = Heraldry.of_id(s.ruling_house_id)
		Overlay.FAITH:
			if GameState.get_organization(s.religion_id) == null:
				return Color(0, 0, 0, 0)
			c = Heraldry.of_id(s.religion_id)
		Overlay.REALM:
			if GameState.get_organization(s.controlling_org_id) == null:
				return Color(0, 0, 0, 0)
			c = Heraldry.of_id(s.controlling_org_id)
		Overlay.UNREST:
			c = Palette.severity(s.unrest)
			c.a = 0.35 + 0.65 * s.unrest
			return c
		Overlay.INDUSTRY:
			c = Heraldry.of_industry(s.industry)
	c.a = 1.0
	return c


## The worst thing happening in the world right now, for the shader to show.
## Calamities are world-wide, so the whole land takes the colour of the one that
## matters most.
func _calamity() -> Dictionary:
	var best_kind := 0
	var best := 0.0
	var tick := SimClock.current_tick
	for inst in GameState.world.active_disasters:
		var remaining: float = 1.0 - float(tick - inst.start_tick) / maxf(1.0, float(inst.duration_ticks))
		var strength: float = clampf(remaining, 0.0, 1.0) * clampf(inst.magnitude, 0.4, 1.4)
		var kind := _fx_kind_of(inst.definition_id)
		if kind != 0 and strength > best:
			best = strength
			best_kind = kind
	return {"kind": best_kind, "strength": clampf(best, 0.0, 1.0)}


static func _fx_kind_of(definition_id: StringName) -> int:
	match definition_id:
		&"drought":
			return 1
		&"plague":
			return 2
		&"wildfire":
			return 3
		&"monster_incursion":
			return 4
		&"bountiful_harvest", &"mineral_strike", &"blessed_grove":
			return 5
	return 0


# -------------------------------------------------------------- the question

func _build_chips() -> void:
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	_chips.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_chips.offset_left = 10
	_chips.offset_right = -10
	_chips.offset_top = 10
	_chips.offset_bottom = 50
	add_child(_chips)
	for entry in OVERLAYS:
		var chip := Button.new()
		chip.text = entry["label"]
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, 38)
		chip.add_theme_font_size_override("font_size", 16)
		chip.pressed.connect(_on_overlay.bind(int(entry["id"])))
		_chips.add_child(chip)
	_style_chips()


func _style_chips() -> void:
	for i in _chips.get_child_count():
		var chip: Button = _chips.get_child(i)
		var active: bool = int(OVERLAYS[i]["id"]) == _overlay
		chip.button_pressed = active
		chip.add_theme_stylebox_override("normal", _pill(active))
		chip.add_theme_stylebox_override("hover", _pill(active))
		chip.add_theme_stylebox_override("pressed", _pill(true))
		chip.add_theme_stylebox_override("hover_pressed", _pill(true))
		chip.add_theme_color_override("font_color", Palette.INK if active else Palette.TEXT)
		chip.add_theme_color_override("font_pressed_color", Palette.INK)
		chip.add_theme_color_override("font_hover_color", Palette.INK if active else Palette.TEXT)
		chip.add_theme_color_override("font_hover_pressed_color", Palette.INK)


static func _pill(active: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT if active else Color(0.08, 0.07, 0.05, 0.78)
	box.border_color = Palette.ACCENT if active else Color(1, 1, 1, 0.12)
	box.set_border_width_all(1)
	box.set_corner_radius_all(19)
	box.content_margin_left = 8
	box.content_margin_right = 8
	return box


func _on_overlay(id: int) -> void:
	_overlay = id
	_style_chips()
	_refresh()


# ------------------------------------------------------------------- legend

func _build_legend() -> void:
	_legend = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.05, 0.04, 0.82)
	box.border_color = Color(1, 1, 1, 0.08)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_legend.add_theme_stylebox_override("panel", box)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend.offset_left = 10
	_legend.offset_bottom = -10
	add_child(_legend)
	_legend_rows = VBoxContainer.new()
	_legend_rows.add_theme_constant_override("separation", 3)
	_legend.add_child(_legend_rows)


## What the colours on the map currently mean, largest first.
func _rebuild_legend() -> void:
	if _legend_rows == null:
		return
	for child in _legend_rows.get_children():
		child.queue_free()
	var entries := _legend_entries()
	for entry in entries.slice(0, 6):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.color = entry["colour"]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := Label.new()
		label.text = entry["label"]
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Palette.TEXT)
		row.add_child(label)
		_legend_rows.add_child(row)
	if entries.size() > 6:
		var more := Label.new()
		more.text = "ほか%d" % (entries.size() - 6)
		more.add_theme_font_size_override("font_size", 13)
		more.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		_legend_rows.add_child(more)
	_legend.visible = not entries.is_empty() and not _detail.visible


func _legend_entries() -> Array:
	if _overlay == Overlay.UNREST:
		return [
			{"colour": Palette.severity(0.1), "label": "穏やか"},
			{"colour": Palette.severity(0.5), "label": "不穏"},
			{"colour": Palette.severity(0.9), "label": "騒乱"},
		]
	var counts := {}
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var key: StringName
		match _overlay:
			Overlay.HOUSE:
				key = s.ruling_house_id
			Overlay.FAITH:
				key = s.religion_id
			Overlay.REALM:
				key = s.controlling_org_id
			Overlay.INDUSTRY:
				key = s.industry
		if key != &"":
			counts[key] = int(counts.get(key, 0)) + 1
	var out: Array = []
	for key in counts:
		var label := ""
		var colour := Palette.TEXT_DIM
		if _overlay == Overlay.INDUSTRY:
			label = Industry.label(key)
			colour = Heraldry.of_industry(key)
		else:
			var org := GameState.get_organization(key)
			if org == null:
				continue
			label = org.display_name
			colour = Heraldry.of_org(org)
		out.append({"label": "%s　%d" % [label, counts[key]], "colour": colour,
			"n": counts[key]})
	out.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	return out


# ------------------------------------------------------------------ drawing

func _draw_map() -> void:
	_sync_view()
	var font := _canvas.get_theme_default_font()
	var zoom := _canvas.view_zoom
	_draw_roads(zoom)
	_draw_terrain(zoom)
	var capital := _capital_id()
	for id in _order:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null:
			_draw_town(s, font, zoom, id == capital)
	_draw_pings(font, zoom)


## Roads to each town's two nearest neighbours: what makes eight dots a country.
func _draw_roads(zoom: float) -> void:
	var drawn := {}
	var road := Palette.INK
	road.a = 0.55
	for id in _order:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s == null:
			continue
		var near: Array = []
		for other_id in _order:
			if other_id == id:
				continue
			var o: SettlementState = GameState.world.settlements.get(other_id)
			near.append([s.position.distance_to(o.position), other_id])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for entry in near.slice(0, 2):
			var other_id: StringName = entry[1]
			var key := "%s|%s" % [mini(hash(id), hash(other_id)), maxi(hash(id), hash(other_id))]
			if drawn.has(key):
				continue
			drawn[key] = true
			var o: SettlementState = GameState.world.settlements[other_id]
			_dashed(_canvas.to_screen(s.position * MAP_SIZE),
				_canvas.to_screen(o.position * MAP_SIZE), road, maxf(1.0, 2.2 * zoom),
				14.0 * zoom)


func _dashed(a: Vector2, b: Vector2, colour: Color, width: float, dash: float) -> void:
	var span := b - a
	var length := span.length()
	if length < 1.0:
		return
	var step := maxf(4.0, dash)
	var dir := span / length
	var t := 0.0
	while t < length:
		var end: float = minf(t + step * 0.6, length)
		_canvas.draw_line(a + dir * t, a + dir * end, colour, width, true)
		t += step


## The lie of the land around each town: peaks round a mine, pines round a
## timber town, wheat round a farm, a coin for a market, watchtowers on the
## frontier. Scattered by a fixed hash so the same world always looks the same.
func _draw_terrain(zoom: float) -> void:
	if zoom < 0.32:
		return
	var tone := Palette.INK
	tone.a = 0.5
	for id in _order:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s == null:
			continue
		var glyph: StringName = Glyph.INDUSTRY_GLYPHS.get(s.industry, &"")
		if glyph == &"":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(id))
		var count := 5 if s.industry != &"trade" else 3
		for i in count:
			var angle := rng.randf() * TAU
			var reach := rng.randf_range(70.0, 135.0)
			var at := s.position * MAP_SIZE + Vector2(cos(angle), sin(angle)) * reach
			var size := rng.randf_range(24.0, 36.0) * zoom
			Glyph.draw(_canvas, glyph, _canvas.to_screen(at), size, tone)


func _draw_town(s: SettlementState, font: Font, zoom: float, is_capital: bool) -> void:
	var centre := _canvas.to_screen(s.position * MAP_SIZE)
	var scale: float = (34.0 + 26.0 * clampf(s.population / 2500.0, 0.0, 1.0)) * zoom
	var house := GameState.get_organization(s.ruling_house_id)
	var banner: Color = Heraldry.of_org(house) if house != null else Palette.TEXT_MUTED

	# A dark plinth so the keep reads on any colour of ground.
	_canvas.draw_circle(centre + Vector2(0, scale * 0.08), scale * 0.62, Color(0, 0, 0, 0.45))
	Glyph.draw(_canvas, &"keep", centre, scale, Palette.TEXT.darkened(0.08))
	# The holding family's colour flies over the gate.
	_canvas.draw_rect(Rect2(centre + Vector2(-scale * 0.14, -scale * 0.72),
		Vector2(scale * 0.28, scale * 0.2)), banner)

	if is_capital:
		Glyph.draw(_canvas, &"crown", centre + Vector2(0, -scale * 0.95), scale * 0.5,
			Palette.ACCENT)
	if s.id == _selected_id:
		_canvas.draw_arc(centre, scale * 0.85, 0, TAU, 40, Palette.ACCENT, maxf(2.0, 3.0 * zoom))

	# Trouble shows over the town itself, not only in the ground around it.
	if s.unrest >= 0.45:
		var flicker := 0.75 + 0.25 * sin(_clock * 9.0 + float(hash(s.id) % 100))
		var flame := Palette.DANGER.lerp(Color("f0a040"), 0.3)
		flame.a = flicker
		Glyph.draw(_canvas, &"flame", centre + Vector2(scale * 0.66, -scale * 0.58),
			scale * (0.5 + 0.3 * s.unrest) * flicker, flame)
	if s.starving:
		Glyph.draw(_canvas, &"drought", centre + Vector2(-scale * 0.66, -scale * 0.5),
			scale * 0.4, Palette.DANGER)

	# The name on a dark tab, so it reads over coast and border alike.
	var label_size := maxi(13, int(18 * zoom))
	var width := font.get_string_size(s.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var tab := Rect2(centre + Vector2(-width * 0.5 - 8, scale * 0.52),
		Vector2(width + 16, label_size + 8))
	_canvas.draw_rect(tab, Color(0.05, 0.04, 0.03, 0.78))
	_canvas.draw_rect(Rect2(tab.position, Vector2(3, tab.size.y)), banner)
	_canvas.draw_string(font, tab.position + Vector2(8, label_size + 1), s.display_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Palette.TEXT)


## The seat of whatever governs the most of the world: its largest town.
func _capital_id() -> StringName:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return &""
	var best: SettlementState = null
	for id in realm.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null and (best == null or s.population > best.population):
			best = s
	return best.id if best != null else &""


# -------------------------------------------------------------------- pings

## Something happened somewhere: a ripple at that place, so the eye knows where
## to look before the chronicle has said a word.
func _on_event(e: HistoryEvent) -> void:
	var kind := _ping_kind(e)
	if kind.is_empty():
		return
	var at := _locate(e)
	if at == Vector2(-1, -1):
		return
	if _pings.size() >= MAX_PINGS:
		_pings.pop_front()
	_pings.append({"at": at, "age": 0.0, "label": kind["label"], "colour": kind["colour"],
		"glyph": kind["glyph"], "big": kind.get("big", false)})


func _ping_kind(e: HistoryEvent) -> Dictionary:
	match e.event_type:
		HistoryEvent.EventType.INCIDENT:
			return {"label": Incidents.label_of(StringName(e.payload.get("incident_kind", ""))),
				"colour": Palette.DANGER, "glyph": &"flame", "big": true}
		HistoryEvent.EventType.SCHISM:
			if String(e.payload.get("schism_kind", "")) == "refounding":
				return {"label": "建国", "colour": Palette.POLITY, "glyph": &"crown", "big": true}
			return {"label": "分派", "colour": Palette.ACCENT, "glyph": &"tree"}
		HistoryEvent.EventType.POWER_TRANSFER:
			if bool(e.payload.get("regime_change", false)):
				return {"label": "政変", "colour": Palette.POLITY, "glyph": &"crown", "big": true}
			if bool(e.payload.get("house_rising", false)):
				return {"label": "台頭", "colour": Palette.HOUSE, "glyph": &"banner"}
			if bool(e.payload.get("honour", false)):
				return {"label": "叙勲" if not bool(e.payload.get("stripped", false)) else "降格",
					"colour": Palette.ACCENT, "glyph": &"sparkle"}
		HistoryEvent.EventType.IDEOLOGY_SHIFT:
			if e.payload.has("settlement") and e.payload.has("from_faith"):
				return {"label": "改宗", "colour": Palette.RELIGION, "glyph": &"altar"}
		HistoryEvent.EventType.SUCCESSION:
			var org := GameState.get_organization(e.subject_org_id)
			if org != null and (org.kind == Organization.OrgKind.POLITICAL_SYSTEM
					or (org.kind == Organization.OrgKind.HOUSE
						and org.standing == Organization.Standing.NOBLE)):
				return {"label": "継承", "colour": Palette.TEXT, "glyph": &"crown"}
		HistoryEvent.EventType.DISSOLVED:
			var org := GameState.get_organization(e.subject_org_id)
			if org != null and org.kind == Organization.OrgKind.HOUSE:
				return {"label": "断絶", "colour": Palette.TEXT_MUTED, "glyph": &"banner"}
		HistoryEvent.EventType.DISASTER_OCCURRED:
			var def_id := StringName(e.payload.get("definition_id", ""))
			return {"label": _disaster_name(def_id), "colour": Palette.HOUSE,
				"glyph": Glyph.DISASTER_GLYPHS.get(def_id, &"sun"), "big": true}
	return {}


func _disaster_name(definition_id: StringName) -> String:
	var def := ContentRegistry.get_disaster(definition_id)
	return def.display_name if def != null else "災厄"


## Where on the map an event belongs, in map space; (-1, -1) if nowhere.
func _locate(e: HistoryEvent) -> Vector2:
	var world := GameState.world
	for key in ["settlement", "seized_settlement", "worst_settlement"]:
		var sid := StringName(e.payload.get(key, ""))
		if sid != &"" and world.settlements.has(sid):
			return world.settlements[sid].position
	if e.event_type == HistoryEvent.EventType.DISASTER_OCCURRED:
		return Vector2(0.5, 0.5)
	var org := GameState.get_organization(e.subject_org_id)
	if org != null:
		match org.kind:
			Organization.OrgKind.HOUSE:
				var seat: SettlementState = world.settlements.get(org.dynasty_seat_settlement_id)
				if seat != null:
					return seat.position
			Organization.OrgKind.POLITICAL_SYSTEM:
				var capital: SettlementState = world.settlements.get(_capital_id())
				if capital != null:
					return capital.position
		var head := GameState.get_current_leader(org.org_id)
		if head != null:
			var home := GameState.get_organization(head.house_org_id)
			if home != null:
				var seat: SettlementState = world.settlements.get(home.dynasty_seat_settlement_id)
				if seat != null:
					return seat.position
	var person := GameState.get_person(e.subject_person_id)
	if person != null:
		var home := GameState.get_organization(person.house_org_id)
		if home != null:
			var seat: SettlementState = world.settlements.get(home.dynasty_seat_settlement_id)
			if seat != null:
				return seat.position
	return Vector2(-1, -1)


func _draw_pings(font: Font, zoom: float) -> void:
	for ping in _pings:
		var t: float = float(ping["age"]) / PING_LIFE
		var centre := _canvas.to_screen(Vector2(ping["at"]) * MAP_SIZE)
		var big: bool = ping["big"]
		var colour: Color = ping["colour"]
		var reach := (90.0 if big else 60.0) * zoom
		for ring in 2:
			var phase := fmod(t * 1.6 + ring * 0.35, 1.0)
			var c := colour
			c.a = (1.0 - phase) * (1.0 - t) * 0.9
			_canvas.draw_arc(centre, reach * (0.25 + phase), 0, TAU, 48, c,
				maxf(2.0, (4.0 if big else 2.5) * zoom))
		# The label rises out of the ripple and fades.
		var rise := -46.0 * zoom - 30.0 * t * zoom
		var alpha := clampf(1.0 - maxf(0.0, t - 0.6) / 0.4, 0.0, 1.0) \
			* clampf(t / 0.08, 0.0, 1.0)
		var size := maxi(14, int((24 if big else 18) * zoom))
		var text: String = ping["label"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var icon := size * 1.1
		var tab := Rect2(centre + Vector2(-(width + icon) * 0.5 - 10, rise - size - 4),
			Vector2(width + icon + 20, size + 12))
		var back := Color(0.05, 0.04, 0.03, 0.85 * alpha)
		_canvas.draw_rect(tab, back)
		var edge := colour
		edge.a = alpha
		_canvas.draw_rect(tab, edge, false, 2.0)
		Glyph.draw(_canvas, ping["glyph"], tab.position + Vector2(10 + icon * 0.5, tab.size.y * 0.5),
			icon * 0.8, edge)
		var ink := Palette.TEXT
		ink.a = alpha
		_canvas.draw_string(font, tab.position + Vector2(14 + icon, size + 3), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


# ------------------------------------------------------------------ tapping

func _on_tapped(world_position: Vector2) -> void:
	var normalized := world_position / MAP_SIZE
	var closest := &""
	var closest_distance := INF
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var d := s.position.distance_to(normalized)
		if d < closest_distance:
			closest_distance = d
			closest = id
	# Anywhere inside a region selects its town — the region is the town's.
	if closest_distance > 0.32:
		_selected_id = &""
		_detail.visible = false
		_refresh()
		return
	_selected_id = closest
	_show_detail(closest)
	_refresh()
	_keep_selection_clear_of_detail(closest)


## The detail sheet covers the bottom of the screen, so a settlement tapped down
## there would disappear behind the panel describing it.
##
## The sheet's height is only true after the frame in which its text was set —
## asked in the same frame it reports the height of the unwrapped text, which on
## the first tap was 2991px against a 1120px screen and scrolled the entire map
## out of view. So: wait for the layout, then never believe more than half the
## screen is covered.
func _keep_selection_clear_of_detail(id: StringName) -> void:
	var s: SettlementState = GameState.world.settlements.get(id)
	if s == null:
		return
	await get_tree().process_frame
	if _selected_id != id or _canvas.size.y < 1.0:
		return
	var screen_y := _canvas.to_screen(s.position * MAP_SIZE).y
	var panel_top: float = maxf(_canvas.size.y * 0.5,
		_canvas.size.y - _detail.size.y - 40.0)
	if screen_y > panel_top:
		_canvas.view_offset.y -= screen_y - panel_top
		_canvas.queue_redraw()


func _show_detail(id: StringName) -> void:
	var s: SettlementState = GameState.world.settlements.get(id)
	if s == null:
		_detail.visible = false
		return
	var holder := GameState.get_organization(s.controlling_org_id)
	var guild := GameState.get_organization(s.dominant_guild_id)
	var lord := RegionalStanding.local_ruler(id)

	_detail_title.text = s.display_name
	var lines := [
		"[color=#9a9080]産業[/color]  %s　%s"
			% [Industry.label(s.industry), Industry.description(s.industry)],
		"[color=#9a9080]主なギルド[/color]  %s" % (guild.display_name if guild != null else "なし"),
	]

	# Who holds this place locally, under whatever the realm currently calls them.
	if lord.is_empty():
		lines.append("[color=#9a9080]領主[/color]  不在")
	else:
		var person: NotableIndividual = lord.get("person")
		lines.append("[color=#9a9080]%s[/color]  %s（[color=#%s]%s[/color]）"
			% [lord.get("title", "領主"),
				person.full_name if person != null else "空位",
				Heraldry.of_org(lord["house"]).to_html(false),
				lord["house"].display_name])
	lines.append("[color=#9a9080]属する国[/color]  %s"
		% (holder.display_name if holder != null else "なし"))
	# A region is not only governed, it leans. Its trade and the family holding it
	# put it behind some faction in the capital, which is how land counts there.
	var lean := GameState.get_organization(s.faction_lean_id)
	lines.append("[color=#9a9080]この地の声[/color]  %s"
		% (lean.display_name if lean != null else "定まらず"))
	var faith := GameState.get_organization(s.religion_id)
	lines.append("[color=#9a9080]信仰[/color]  %s"
		% ("[color=#%s]%s[/color]" % [Heraldry.of_org(faith).to_html(false), faith.display_name]
			if faith != null else "なし"))
	lines.append("[color=#9a9080]人口[/color]  %d　[color=#9a9080]富[/color]  %d"
		% [int(s.population), int(s.wealth)])
	lines.append("[color=#9a9080]食料[/color]  %d%s" % [int(s.food_stock),
		"　[color=#c85a4a]飢饉[/color]" if s.starving else ""])
	lines.append("[color=#9a9080]鉱石[/color]  %d　[color=#9a9080]木材[/color]  %d"
		% [int(s.local_ore), int(s.local_wood)])
	lines.append("[color=#9a9080]不満[/color]  [color=#%s]%d%%[/color]"
		% [Palette.severity(s.unrest).to_html(false), int(s.unrest * 100.0)])

	_detail_body.text = "\n".join(lines)
	_detail.visible = true
	if _legend != null:
		_legend.visible = false
