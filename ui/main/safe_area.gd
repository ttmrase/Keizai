class_name SafeArea
extends RefCounted

## Where on the glass the game may put things a finger has to reach.
##
## The game draws to the whole window, edge to edge, and Android's status and
## navigation bars float over it. That is the one arrangement that behaves the
## same on every version of Android: the surface is the window, a touch lands
## where it is seen, and nothing is padded by the system on the game's behalf.
## (Letting the system pad the window instead left strips of the screen that
## looked like the game and could not be touched.)
##
## So the game keeps its own margins. The backdrop runs under the bars; the
## status strip, the screens and the dock sit between them. The margins come
## from the device, and the reader can widen them from the settings if a
## particular phone reports them short.

## No device honestly needs more than this share of the screen for a bar, so
## anything larger is a bad reading rather than a margin.
const MAX_SHARE := 0.2
## How far the reader may widen a margin by hand, in screen units, and the step.
const NUDGE_MAX := 96
const NUDGE_STEP := 8

## For tools and tests: margins to pretend the device has, as (left, top,
## right, bottom) in screen units. Null asks the device.
static var pretend: Variant = null


## The margins to keep clear, as (left, top, right, bottom) in the viewport's
## own units.
static func margins(viewport: Viewport) -> Vector4:
	var out := Vector4.ZERO
	if pretend != null:
		out = pretend
	elif on_phone():
		out = from_device(Vector2(DisplayServer.window_get_size()),
			DisplayServer.get_display_safe_area(), viewport.get_visible_rect().size)
	out.y += float(nudge("margin_top"))
	out.w += float(nudge("margin_bottom"))
	return out


## Turns what the device reports — the window in pixels and the rectangle of it
## that is clear of bars and cut-outs — into margins in screen units.
static func from_device(window: Vector2, safe: Rect2i, view: Vector2) -> Vector4:
	if window.x <= 0.0 or window.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var per_pixel := Vector2(view.x / window.x, view.y / window.y)
	var left := clampf(float(safe.position.x), 0.0, window.x * MAX_SHARE)
	var top := clampf(float(safe.position.y), 0.0, window.y * MAX_SHARE)
	var right := clampf(window.x - float(safe.end.x), 0.0, window.x * MAX_SHARE)
	var bottom := clampf(window.y - float(safe.end.y), 0.0, window.y * MAX_SHARE)
	return Vector4(left * per_pixel.x, top * per_pixel.y, right * per_pixel.x,
		bottom * per_pixel.y)


static func on_phone() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS"


static func nudge(key: String) -> int:
	return clampi(int(UiSettings.get_value(key, 0)), 0, NUDGE_MAX)


static func set_nudge(key: String, value: int) -> void:
	UiSettings.set_value(key, clampi(value, 0, NUDGE_MAX))


## Whether the reader has asked for the system bars to be hidden altogether.
static func wants_fullscreen() -> bool:
	return bool(UiSettings.get_value("hide_system_bars", false))


## Hides or shows Android's bars to match the setting. The window itself does
## not change size either way; only what floats over it does.
static func apply_display_mode() -> void:
	if not on_phone():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if wants_fullscreen()
		else DisplayServer.WINDOW_MODE_WINDOWED)


## Lays a full-rect control out inside the margins.
static func inset(control: Control, m: Vector4) -> void:
	control.offset_left = m.x
	control.offset_top = m.y
	control.offset_right = -m.z
	control.offset_bottom = -m.w
