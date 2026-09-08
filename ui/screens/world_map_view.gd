extends Control

## The world at a glance: settlements sized by population, coloured by who holds
## them, ringed by how unsettled they are. Tap one to read its numbers.

## Taller than wide, to match the phone screen it is drawn on.
const MAP_SIZE := Vector2(1000, 1450)

@onready var _canvas: PannableCanvas = $Canvas
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Body

var _selected_id: StringName = &""


func _ready() -> void:
	_canvas.draw.connect(_draw_map)
	_canvas.canvas_tapped.connect(_on_tapped)
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.game_loaded.connect(_refresh)
	EventBus.world_reset.connect(_refresh)
	_detail.visible = false
	await get_tree().process_frame
	_frame_world()


func on_shown() -> void:
	_refresh()


func _on_tick(tick: int) -> void:
	if tick % 4 == 0:
		_refresh()


func _refresh() -> void:
	_canvas.queue_redraw()
	if _selected_id != &"":
		_show_detail(_selected_id)


func _frame_world() -> void:
	var fit: float = minf(_canvas.size.x / MAP_SIZE.x, _canvas.size.y / MAP_SIZE.y) * 0.92
	_canvas.view_zoom = clampf(fit, _canvas.min_zoom, _canvas.max_zoom)
	_canvas.center_on(MAP_SIZE * 0.5)


func _draw_map() -> void:
	var world: WorldState = GameState.world

	# A soft frame so the world reads as a place rather than floating markers.
	var top_left := _canvas.to_screen(Vector2.ZERO)
	var extent := MAP_SIZE * _canvas.view_zoom
	_canvas.draw_rect(Rect2(top_left, extent), Palette.PANEL, true)
	_canvas.draw_rect(Rect2(top_left, extent), Palette.LINE, false, 2.0)

	var font := _canvas.get_theme_default_font()
	for id in world.settlements:
		var s: SettlementState = world.settlements[id]
		var centre := _canvas.to_screen(s.position * MAP_SIZE)
		var radius: float = (22.0 + 34.0 * clampf(s.population / 2500.0, 0.0, 1.0)) \
			* _canvas.view_zoom

		var holder := GameState.get_organization(s.controlling_org_id)
		var fill := Palette.for_kind(holder.kind) if holder != null else Palette.TEXT_DIM
		if s.starving:
			fill = fill.lerp(Palette.DANGER, 0.55)

		_canvas.draw_circle(centre, radius, fill.darkened(0.35))
		_canvas.draw_arc(centre, radius, 0, TAU, 32, fill, 2.0 * _canvas.view_zoom)

		# Unrest rides as an outer arc, so trouble is visible without tapping in.
		if s.unrest > 0.02:
			_canvas.draw_arc(centre, radius + 6.0 * _canvas.view_zoom, -PI / 2,
				-PI / 2 + TAU * s.unrest, 40, Palette.severity(s.unrest),
				3.0 * _canvas.view_zoom)

		if s.id == _selected_id:
			_canvas.draw_arc(centre, radius + 12.0 * _canvas.view_zoom, 0, TAU, 40,
				Palette.ACCENT, 2.0)

		var label_size := maxi(12, int(17 * _canvas.view_zoom))
		var text_width := font.get_string_size(s.display_name, HORIZONTAL_ALIGNMENT_LEFT,
			-1, label_size).x
		_canvas.draw_string(font, centre + Vector2(-text_width * 0.5, radius + 24), s.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Palette.TEXT)


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
	if closest_distance > 0.09:
		_selected_id = &""
		_detail.visible = false
		_canvas.queue_redraw()
		return
	_selected_id = closest
	_show_detail(closest)
	_keep_selection_clear_of_detail(closest)
	_canvas.queue_redraw()


## The detail sheet covers the bottom of the screen, so a settlement tapped down
## there would disappear behind the panel describing it.
func _keep_selection_clear_of_detail(id: StringName) -> void:
	var s: SettlementState = GameState.world.settlements.get(id)
	if s == null:
		return
	var screen_y := _canvas.to_screen(s.position * MAP_SIZE).y
	var panel_top: float = _canvas.size.y - _detail.size.y - 40.0
	if screen_y > panel_top:
		_canvas.view_offset.y -= screen_y - panel_top


func _show_detail(id: StringName) -> void:
	var s: SettlementState = GameState.world.settlements.get(id)
	if s == null:
		_detail.visible = false
		return
	var holder := GameState.get_organization(s.controlling_org_id)
	var holder_name := holder.display_name if holder != null else "支配者なし"
	var leader := GameState.get_current_leader(s.controlling_org_id)

	_detail_title.text = s.display_name
	var lines := [
		"[color=#9a9080]統治[/color]  %s" % holder_name,
		"[color=#9a9080]為政者[/color]  %s" % (leader.full_name if leader != null else "不在"),
		"[color=#9a9080]人口[/color]  %d　[color=#9a9080]富[/color]  %d" % [int(s.population), int(s.wealth)],
		"[color=#9a9080]食料[/color]  %d%s" % [int(s.food_stock),
			"　[color=#c85a4a]飢饉[/color]" if s.starving else ""],
		"[color=#9a9080]鉱石[/color]  %d　[color=#9a9080]木材[/color]  %d" % [int(s.local_ore), int(s.local_wood)],
		"[color=#9a9080]不満[/color]  %d%%" % int(s.unrest * 100.0),
	]
	_detail_body.text = "\n".join(lines)
	_detail.visible = true
