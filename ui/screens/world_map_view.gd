extends Control

## The world at a glance: settlements sized by population, coloured by who holds
## them, ringed by how unsettled they are. Tap one to read its numbers.

## Taller than wide, to match the phone screen it is drawn on.
const MAP_SIZE := Vector2(1000, 1450)

@onready var _canvas: PannableCanvas = $Canvas
@onready var _detail: PanelContainer = $Detail
@onready var _detail_title: Label = $Detail/Margin/Rows/Title
@onready var _detail_body: RichTextLabel = $Detail/Margin/Rows/Body
@onready var _rename_button: Button = $Detail/Margin/Rows/Rename

var _selected_id: StringName = &""
var _rename_dialog: RenameDialog


func _ready() -> void:
	_canvas.draw.connect(_draw_map)
	_canvas.canvas_tapped.connect(_on_tapped)
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.game_loaded.connect(_refresh)
	EventBus.world_reset.connect(_refresh)
	_detail.visible = false

	_rename_dialog = RenameDialog.new()
	add_child(_rename_dialog)
	_rename_dialog.name_applied.connect(func(_id): _refresh())
	_rename_button.pressed.connect(_on_rename_pressed)

	await get_tree().process_frame
	_frame_world()


func _on_rename_pressed() -> void:
	var s: SettlementState = GameState.world.settlements.get(_selected_id)
	if s != null:
		_rename_dialog.open_for_settlement(_selected_id, s.display_name)


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
	_canvas.queue_redraw()
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
		lines.append("[color=#9a9080]%s[/color]  %s（%s）"
			% [lord.get("title", "領主"),
				person.full_name if person != null else "空位",
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
		% (faith.display_name if faith != null else "なし"))
	lines.append("[color=#9a9080]人口[/color]  %d　[color=#9a9080]富[/color]  %d"
		% [int(s.population), int(s.wealth)])
	lines.append("[color=#9a9080]食料[/color]  %d%s" % [int(s.food_stock),
		"　[color=#c85a4a]飢饉[/color]" if s.starving else ""])
	lines.append("[color=#9a9080]鉱石[/color]  %d　[color=#9a9080]木材[/color]  %d"
		% [int(s.local_ore), int(s.local_wood)])
	lines.append("[color=#9a9080]不満[/color]  %d%%" % int(s.unrest * 100.0))

	_detail_body.text = "\n".join(lines)
	_detail.visible = true
