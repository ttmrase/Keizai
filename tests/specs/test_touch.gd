extends Spec

## Touches the screens the way a phone does.
##
## On Android every touch reaches Godot twice — the touch itself, and a mouse
## event made up from it — and a swipe meant for a list starts on whatever the
## finger happened to land on. Both of those once did real harm: a single tap
## armed and fired a calamity in one go, a swipe down the god's panel fired the
## cards it crossed and turned the dials it started on, and the map moved twice
## as far as the finger. So every gesture here is delivered as the phone
## delivers it, the made-up mouse event first and then the touch, and the
## checks are about what the player would have seen happen.

const STEPS := 12

var _host: Node
var _viewport: Viewport


func run_in_tree(host: Node) -> void:
	_host = host
	_viewport = host.get_viewport()
	# With no touchscreen, scroll lists ignore drags; Godot counts a mouse that
	# makes touches as one.
	var emulating := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true

	ContentRegistry.ensure_loaded()
	SimTestHarness.fresh_world(5150)
	SimTestHarness.advance(240)
	SimClock.set_time_scale(0.0)

	var shell: Control = load("res://ui/main/ObservationShell.tscn").instantiate()
	host.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(4)

	await _god_panel(shell)
	await _power_rows(shell)
	await _chronicle(shell)
	await _map(shell)

	shell.queue_free()
	await _frames(2)
	Input.emulate_touch_from_mouse = emulating
	finish()


# ------------------------------------------------------------------ god panel

func _god_panel(shell: Control) -> void:
	shell.show_tab("god")
	await _frames(4)
	var panel: Control = shell._screens["god"]
	var scroll: ScrollContainer = panel.get_node("Scroll")
	var id: StringName = panel._cards.keys()[0]
	var card: Control = panel._cards[id]["card"]
	var running := GameState.world.active_disasters.size()

	# A swipe up the panel that starts on a calamity card scrolls the panel and
	# does nothing else.
	await _bring_into_view(scroll, card)
	var top := scroll.scroll_vertical
	var at := _centre(card)
	await _swipe(at, at + Vector2(0, -320))
	check(scroll.scroll_vertical > top, "a swipe on the god's panel should scroll it")
	check_eq(panel._armed, &"", "a swipe across a calamity card should not arm it")
	check_eq(GameState.world.active_disasters.size(), running,
		"a swipe across a calamity card should not call it down")

	# One tap arms; it does not also fire.
	await _bring_into_view(scroll, card)
	at = _centre(card)
	await _tap(at)
	check_eq(panel._armed, id, "one tap should arm the calamity")
	check_eq(GameState.world.active_disasters.size(), running,
		"one tap should not call the calamity down")
	await _tap(at)
	check_eq(GameState.world.active_disasters.size(), running + 1,
		"a second tap should call it down, once")
	check_eq(panel._armed, &"", "calling it down should disarm the card")

	# A swipe that starts on a dial scrolls the panel and leaves the dial alone.
	var slider: HSlider = panel._sliders[0]
	await _bring_into_view(scroll, slider)
	top = scroll.scroll_vertical
	var before := slider.value
	at = _centre(slider)
	await _swipe(at, at + Vector2(0, -300))
	check_near(slider.value, before, 0.0001, "a vertical swipe from a dial should not turn it")
	check(scroll.scroll_vertical > top, "a vertical swipe from a dial should scroll the panel")

	# A tap on the track changes nothing either.
	await _bring_into_view(scroll, slider)
	at = _centre(slider)
	await _tap(at + Vector2(slider.size.x * 0.4, 0))
	check_near(slider.value, before, 0.0001, "a tap on a dial's track should not turn it")

	# A sideways drag turns it, and the panel stays where it is.
	top = scroll.scroll_vertical
	at = _centre(slider)
	await _swipe(at, at + Vector2(140, 0))
	check_gt(slider.value, before + 0.05, "a sideways drag on a dial should turn it up")
	check_eq(scroll.scroll_vertical, top, "turning a dial should not scroll the panel")
	slider.value = before


## Scrolls a list so a control sits in its upper half, with room to swipe both
## ways, as a reader would before reaching for it.
func _bring_into_view(scroll: ScrollContainer, control: Control) -> void:
	scroll.scroll_vertical = 0
	await _frames(2)
	var offset := control.get_global_rect().position.y - scroll.get_global_rect().position.y
	scroll.scroll_vertical = int(maxf(0.0, offset - scroll.size.y * 0.3))
	await _frames(3)


# ----------------------------------------------------------------- power rows

func _power_rows(shell: Control) -> void:
	shell.show_tab("power")
	await _frames(4)
	var dashboard: Control = shell._screens["power"]
	var row: Control = null
	for child in dashboard._list.get_children():
		if child is Button:
			row = child
			break
	check(row != null, "the power screen should list organizations as rows")
	if row == null:
		return

	# Pressed by a swipe, a row stays shut — even a short one that never leaves
	# the row, which is the swipe a button would otherwise take as its press.
	var at := _centre(row)
	await _swipe(at, at + Vector2(0, -26))
	check_eq(dashboard._expanded, &"", "a short swipe within a power row should not open it")
	await _swipe(at, at + Vector2(0, -260))
	check_eq(dashboard._expanded, &"", "a swipe over a power row should not open it")

	# Tapped, it opens.
	var scroll: ScrollContainer = dashboard.get_node("Rows/Scroll")
	scroll.scroll_vertical = 0
	await _frames(3)
	row = null
	for child in dashboard._list.get_children():
		if child is Button:
			row = child
			break
	await _tap(_centre(row))
	check(dashboard._expanded != &"", "a tap on a power row should open it")
	dashboard._expanded = &""


# ------------------------------------------------------------------ chronicle

func _chronicle(shell: Control) -> void:
	shell.show_tab("chronicle")
	await _frames(4)
	var chronicle: Control = shell._screens["chronicle"]
	var followed := [0]
	var counter := func(_id: StringName): followed[0] += 1
	chronicle.reveal_requested.connect(counter)

	var entry: Control = null
	for child in chronicle._list.get_children():
		if child.gui_input.get_connections().size() > 0:
			entry = child
			break
	check(entry != null, "the chronicle should have an entry that names somebody")
	if entry == null:
		return
	var at := _centre(entry)
	await _swipe(at, at + Vector2(0, -240))
	check_eq(followed[0], 0, "a swipe over a chronicle entry should not follow it")

	var scroll: ScrollContainer = chronicle.get_node("Rows/Scroll")
	scroll.scroll_vertical = 0
	await _frames(3)
	# Following a name changes tab, so the shell is held still for this one.
	chronicle.reveal_requested.disconnect(shell.reveal)
	await _tap(_centre(entry))
	check_eq(followed[0], 1, "a tap on a chronicle entry should follow it exactly once")
	chronicle.reveal_requested.connect(shell.reveal)
	chronicle.reveal_requested.disconnect(counter)


# ------------------------------------------------------------------------ map

func _map(shell: Control) -> void:
	shell.show_tab("map")
	await _frames(4)
	var map: Control = shell._screens["map"]
	var canvas: PannableCanvas = map._canvas
	var taps := [0]
	canvas.canvas_tapped.connect(func(_p: Vector2): taps[0] += 1)

	var start := canvas.view_offset
	var at := _centre(canvas)
	await _press(at)
	await _move(at, at + Vector2(120, 0))
	check_near(canvas.view_offset.x - start.x, 120.0, 1.0,
		"the map should move exactly as far as the finger")
	# Held still before letting go: the map stops where it was left.
	await _wait_ms(150)
	var held := canvas.view_offset
	await _release(at + Vector2(120, 0))
	await _frames(6)
	check_near(canvas.view_offset.x, held.x, 0.5, "a drag that stopped should not glide on")
	check_eq(taps[0], 0, "a drag on the map is not a tap")

	await _tap(at)
	check_eq(taps[0], 1, "a tap on the map should count once")


# ------------------------------------------------------------------- gestures

func _tap(at: Vector2) -> void:
	await _press(at)
	await _release(at)


func _swipe(from: Vector2, to: Vector2) -> void:
	await _press(from)
	await _move(from, to)
	await _release(to)


func _press(at: Vector2) -> void:
	_send_button(at, true)
	await _frames(1)


func _release(at: Vector2) -> void:
	_send_button(at, false)
	await _frames(2)


func _send_button(at: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.device = InputEvent.DEVICE_ID_EMULATION
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.position = at
	click.global_position = at
	_viewport.push_input(click, true)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = pressed
	touch.position = at
	_viewport.push_input(touch, true)


func _move(from: Vector2, to: Vector2) -> void:
	var last := from
	for i in range(1, STEPS + 1):
		var point := from.lerp(to, float(i) / STEPS)
		var motion := InputEventMouseMotion.new()
		motion.device = InputEvent.DEVICE_ID_EMULATION
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = point
		motion.global_position = point
		motion.relative = point - last
		motion.velocity = (point - last) * 60.0
		_viewport.push_input(motion, true)
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = point
		drag.relative = point - last
		drag.velocity = (point - last) * 60.0
		_viewport.push_input(drag, true)
		last = point
		await _frames(1)


func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _frames(count: int) -> void:
	for i in count:
		await _host.get_tree().process_frame


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await _host.get_tree().process_frame
