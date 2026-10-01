extends Control

## Always-visible world summary and time controls. This is the one place the
## player's own actions live outside the god-power screen, because pausing to go
## read the chronicle needs to be possible from anywhere.
##
## The top line says when and where: the year, and which state the world is in —
## because "the year 650" means nothing on its own and "the year 650, under a
## merchant republic" is half a history.

signal speed_changed(scale: float)

const SPEEDS := [0.0, 1.0, 2.0, 4.0]

var _speed_buttons: Array[SpeedButton] = []
var _realm: Label

@onready var _date: Label = $Rows/Top/Date
@onready var _speed_row: HBoxContainer = $Rows/Top/Speeds
@onready var _gauges: HBoxContainer = $Rows/Gauges


func _ready() -> void:
	# The date sits over a line naming the realm, so the two read as one.
	var when := VBoxContainer.new()
	when.add_theme_constant_override("separation", -4)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = _date.get_parent()
	top.add_child(when)
	top.move_child(when, 0)
	_date.reparent(when)
	_date.add_theme_font_size_override("font_size", 24)
	_realm = Label.new()
	_realm.add_theme_font_size_override("font_size", 13)
	_realm.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_realm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_realm.clip_text = true
	when.add_child(_realm)

	_speed_row.add_theme_constant_override("separation", 0)
	for i in SPEEDS.size():
		var button := SpeedButton.new()
		button.arrows = i
		button.first = i == 0
		button.last = i == SPEEDS.size() - 1
		button.custom_minimum_size = Vector2(54, 44)
		button.pressed.connect(_on_speed_pressed.bind(i))
		_speed_row.add_child(button)
		_speed_buttons.append(button)

	EventBus.tick_advanced.connect(_on_tick)
	EventBus.speed_changed.connect(_sync_speed_buttons)
	EventBus.game_loaded.connect(_on_world_changed)
	EventBus.world_reset.connect(_on_world_changed)
	_sync_speed_buttons(SimClock.time_scale)
	_refresh()


func _on_world_changed() -> void:
	for gauge in _gauges.get_children():
		if gauge.has_method("reset_trend"):
			gauge.reset_trend()
	_refresh()


func _on_speed_pressed(index: int) -> void:
	speed_changed.emit(SPEEDS[index])
	_sync_speed_buttons(SPEEDS[index])


func _sync_speed_buttons(scale: float) -> void:
	for i in _speed_buttons.size():
		var active: bool = is_equal_approx(SPEEDS[i], scale)
		_speed_buttons[i].button_pressed = active
		_speed_buttons[i].active = active


func _on_tick(tick: int) -> void:
	# The strip only needs to keep up with the eye, not with the simulation.
	if tick % 4 == 0:
		_refresh()


func _refresh() -> void:
	var w: WorldState = GameState.world
	_date.text = "%d年" % SimClock.year()
	var realm := HouseRank.dominant_realm()
	var form := PolityFormEvaluator.form_of(realm) if realm != null else null
	_realm.text = "%s　・　人口 %s" % [
		form.display_name if form != null else (realm.display_name if realm != null else "国なき世"),
		_compact(w.global_population)]

	_set_gauge(0, "魔物", &"claw", w.global_monster_threat_level,
		Palette.severity(w.global_monster_threat_level))
	_set_gauge(1, "不満", &"unrest", w.global_unrest, Palette.severity(w.global_unrest))
	var harvest_norm: float = clampf(w.global_harvest_modifier / 1.5, 0.0, 1.0)
	_set_gauge(2, "収穫", &"wheat", harvest_norm, Palette.severity(1.0 - harvest_norm))
	_set_gauge(3, "鉱石", &"gem", clampf(w.global_ore / 3000.0, 0.0, 1.0), Palette.GUILD)
	_set_gauge(4, "木材", &"pine", clampf(w.global_wood / 3000.0, 0.0, 1.0), Palette.FACTION)


func _set_gauge(index: int, label: String, glyph: StringName, value: float, color: Color) -> void:
	if index >= _gauges.get_child_count():
		return
	var gauge: Control = _gauges.get_child(index)
	gauge.set_value(label, value, color, glyph)


static func _compact(n: float) -> String:
	if n >= 10000.0:
		return "%.1f万" % (n / 10000.0)
	return "%d" % int(n)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PANEL)
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Palette.LINE, 1.0)
