extends Control

## Always-visible world summary and time controls. This is the one place the
## player's own actions live outside the god-power screen, because pausing to go
## read the chronicle needs to be possible from anywhere.

signal speed_changed(scale: float)

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const SPEED_LABELS := ["‖", "▶", "▶▶", "▶▶▶"]

var _speed_buttons: Array[Button] = []

@onready var _date: Label = $Rows/Top/Date
@onready var _speed_row: HBoxContainer = $Rows/Top/Speeds
@onready var _gauges: HBoxContainer = $Rows/Gauges


func _ready() -> void:
	for i in SPEEDS.size():
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(52, 44)
		button.pressed.connect(_on_speed_pressed.bind(i))
		_speed_row.add_child(button)
		_speed_buttons.append(button)

	EventBus.tick_advanced.connect(_on_tick)
	EventBus.speed_changed.connect(_sync_speed_buttons)
	EventBus.game_loaded.connect(_refresh)
	EventBus.world_reset.connect(_refresh)
	_sync_speed_buttons(SimClock.time_scale)
	_refresh()


func _on_speed_pressed(index: int) -> void:
	speed_changed.emit(SPEEDS[index])
	_sync_speed_buttons(SPEEDS[index])


func _sync_speed_buttons(scale: float) -> void:
	for i in _speed_buttons.size():
		var active: bool = is_equal_approx(SPEEDS[i], scale)
		_speed_buttons[i].button_pressed = active
		_speed_buttons[i].add_theme_color_override("font_color",
			Palette.ACCENT if active else Palette.TEXT_MUTED)


func _on_tick(tick: int) -> void:
	# The strip only needs to keep up with the eye, not with the simulation.
	if tick % 4 == 0:
		_refresh()


func _refresh() -> void:
	var w: WorldState = GameState.world
	_date.text = "%s年　人口 %s" % [SimClock.year(), _compact(w.global_population)]

	_set_gauge(0, "魔物", w.global_monster_threat_level, Palette.severity(w.global_monster_threat_level))
	_set_gauge(1, "不満", w.global_unrest, Palette.severity(w.global_unrest))
	var harvest_norm: float = clampf(w.global_harvest_modifier / 1.5, 0.0, 1.0)
	_set_gauge(2, "収穫", harvest_norm, Palette.severity(1.0 - harvest_norm))
	_set_gauge(3, "鉱石", clampf(w.global_ore / 3000.0, 0.0, 1.0), Palette.GUILD)
	_set_gauge(4, "木材", clampf(w.global_wood / 3000.0, 0.0, 1.0), Palette.FACTION)


func _set_gauge(index: int, label: String, value: float, color: Color) -> void:
	if index >= _gauges.get_child_count():
		return
	var gauge: Control = _gauges.get_child(index)
	gauge.set_value(label, value, color)


static func _compact(n: float) -> String:
	if n >= 10000.0:
		return "%.1f万" % (n / 10000.0)
	return "%d" % int(n)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PANEL)
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Palette.LINE, 1.0)
