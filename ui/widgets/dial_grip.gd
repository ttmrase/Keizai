class_name DialGrip
extends Control

## Lets a thumb scroll past a slider that sits in a scrolling list.
##
## A slider takes any press on its track as a new value, so a swipe down the
## god's panel that happened to start on a dial turned it. The grip lies over the
## slider instead and moves it only for a drag that is plainly sideways; a drag
## that is plainly vertical carries on to the list, and a tap changes nothing.
## The dial follows the finger from where it was, rather than jumping to where
## the finger landed.

## How far a finger travels before its direction is decided. Under the scroll
## dead zone, so the list has not started moving when a dial is taken hold of.
const LOCK := 10.0

enum State { IDLE, UNDECIDED, DIALLING, SCROLLING }

var _slider: HSlider
var _from := Vector2.ZERO
var _start_value := 0.0
var _state := State.IDLE


static func attach(slider: HSlider) -> DialGrip:
	var grip := DialGrip.new()
	grip._slider = slider
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.mouse_filter = Control.MOUSE_FILTER_PASS
	grip.set_anchors_preset(Control.PRESET_FULL_RECT)
	slider.add_child(grip)
	return grip


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_from = event.global_position
			_start_value = _slider.value
			_state = State.UNDECIDED
		else:
			if _state == State.DIALLING:
				accept_event()
			_state = State.IDLE
		return
	if not (event is InputEventMouseMotion) or _state == State.IDLE \
			or _state == State.SCROLLING:
		return
	var moved: Vector2 = event.global_position - _from
	if _state == State.UNDECIDED:
		if absf(moved.y) > LOCK and absf(moved.y) >= absf(moved.x):
			_state = State.SCROLLING
			return
		if absf(moved.x) <= LOCK:
			return
		_state = State.DIALLING
	# Once the dial is held the list must not move under it.
	accept_event()
	var knob := 28.0
	var travel := maxf(size.x - knob, 1.0)
	_slider.value = _start_value + moved.x / travel * (_slider.max_value - _slider.min_value)
