class_name Touch
extends RefCounted

## How a finger is read, in one place.
##
## On a phone every touch arrives twice: once as a touch and once as a mouse
## click Godot makes up from it, so that buttons work. Anything that listens to
## both acts twice — a calamity card took one tap as "arm" and "fire" together,
## and a map panned at double the speed of the finger. So the rules here are:
##
## * A tap is read from the click alone, and only if the finger came up within
##   SLOP of where it went down; anything further was a swipe.
## * Drags and pinches are read from the touches alone (`is_emulated` says which
##   clicks to ignore), because only touches know about a second finger.
## * Inside a scrolling list, nothing stops a swipe on its way to the list.
##   Godot cancels a button press when its list starts to scroll, but only if
##   the button lets the swipe through; by default buttons keep it.

## How far a finger may move and still have tapped. Kept under the scroll dead
## zone (project setting gui/common/default_scroll_deadzone), so a press that a
## list has started scrolling can never also count as a tap.
const SLOP := 14.0

const _PRESSED_AT := &"_touch_pressed_at"


## Whether a mouse event was made up from a touch rather than a real mouse.
static func is_emulated(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION


## Feed every gui_input event of a control through this; it answers true once,
## on the release that ends a tap on that control.
static func tapped(control: Control, event: InputEvent) -> bool:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return false
	if event.pressed:
		control.set_meta(_PRESSED_AT, event.global_position)
		return false
	if not control.has_meta(_PRESSED_AT):
		return false
	var from: Vector2 = control.get_meta(_PRESSED_AT)
	control.remove_meta(_PRESSED_AT)
	return from.distance_to(event.global_position) <= SLOP


## Lets swipes through to the scrolling list a control sits in. Called for every
## control that enters the tree; ignores those outside a list, the list's own
## scroll bars, and the controls that need a drag of their own.
static func let_swipes_through(node: Node) -> void:
	var control := node as Control
	if control == null or control.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	if control is ScrollContainer or control is Range or control is LineEdit \
			or control is TextEdit or control is PannableCanvas:
		return
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
			return
		if parent is PannableCanvas or not parent is Control:
			return
		parent = parent.get_parent()
