class_name PannableCanvas
extends Control

## Pan and zoom for the two views that need it: the world map and the lineage
## trees. Handles touch drag, pinch, and mouse wheel, and reports taps that were
## not part of a drag so a subclass can treat them as selection.
##
## Subclasses draw in world coordinates and convert with to_screen().

signal canvas_tapped(world_position: Vector2)
## A press held in place rather than tapped. Used as a second verb on a node —
## the family tree opens a person's own chart with it — so a phone with one
## finger and no right mouse button still has two things it can say.
signal canvas_long_pressed(world_position: Vector2)

@export var min_zoom: float = 0.35
@export var max_zoom: float = 3.0

var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0

var _dragging := false
var _drag_moved := 0.0
var _last_drag_position := Vector2.ZERO
## Fingers currently down, so a two-finger pinch is not mistaken for two drags.
var _touch_points: Dictionary = {}
var _pinch_reference: float = 0.0

## A press that has not moved and has not yet been let go of.
var _press_started_ms: int = -1
var _press_position := Vector2.ZERO
var _long_press_fired := false

const TAP_SLOP := 12.0
## Long enough not to fire while someone is deciding where to drag, short enough
## that holding still feels deliberate rather than broken.
const LONG_PRESS_MS := 480


func to_screen(world_position: Vector2) -> Vector2:
	return world_position * view_zoom + view_offset


func to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - view_offset) / view_zoom


func center_on(world_position: Vector2) -> void:
	view_offset = size * 0.5 - world_position * view_zoom
	queue_redraw()


func set_zoom_about(new_zoom: float, screen_anchor: Vector2) -> void:
	var clamped := clampf(new_zoom, min_zoom, max_zoom)
	if is_equal_approx(clamped, view_zoom):
		return
	var anchor_world := to_world(screen_anchor)
	view_zoom = clamped
	view_offset = screen_anchor - anchor_world * view_zoom
	queue_redraw()


## Watches a held press. Cheap enough to leave running: it is one comparison per
## frame while nothing is pressed.
func _process(_delta: float) -> void:
	if _press_started_ms < 0 or _long_press_fired:
		return
	if _drag_moved >= TAP_SLOP or _touch_points.size() > 1:
		_press_started_ms = -1
		return
	if Time.get_ticks_msec() - _press_started_ms < LONG_PRESS_MS:
		return
	_long_press_fired = true
	canvas_long_pressed.emit(to_world(_press_position))


func _begin_press(at: Vector2) -> void:
	_press_started_ms = Time.get_ticks_msec()
	_press_position = at
	_long_press_fired = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMagnifyGesture:
		set_zoom_about(view_zoom * event.factor, event.position)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_pan_by(event.relative)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_dragging = true
			_drag_moved = 0.0
			_last_drag_position = event.position
			_begin_press(event.position)
		else:
			_dragging = false
			_press_started_ms = -1
			_pinch_reference = _touch_spread()
	else:
		_touch_points.erase(event.index)
		if _dragging and _drag_moved < TAP_SLOP and not _long_press_fired:
			canvas_tapped.emit(to_world(event.position))
		_press_started_ms = -1
		if _touch_points.is_empty():
			_dragging = false


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position
	if _touch_points.size() >= 2:
		var spread := _touch_spread()
		if _pinch_reference > 1.0 and spread > 1.0:
			set_zoom_about(view_zoom * (spread / _pinch_reference), _touch_centroid())
		_pinch_reference = spread
		return
	_drag_moved += event.relative.length()
	_pan_by(event.relative)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				set_zoom_about(view_zoom * 1.12, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				set_zoom_about(view_zoom / 1.12, event.position)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
				_begin_press(event.position)
			else:
				if _dragging and _drag_moved < TAP_SLOP and not _long_press_fired:
					canvas_tapped.emit(to_world(event.position))
				_press_started_ms = -1
				_dragging = false


func _pan_by(delta: Vector2) -> void:
	view_offset += delta
	_drag_moved += delta.length()
	queue_redraw()


func _touch_spread() -> float:
	var points := _touch_points.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1])


func _touch_centroid() -> Vector2:
	var points := _touch_points.values()
	if points.is_empty():
		return size * 0.5
	var total := Vector2.ZERO
	for p in points:
		total += p
	return total / points.size()
