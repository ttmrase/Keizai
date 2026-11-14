extends Spec

## Everything on the screen that can be pressed can be reached.
##
## Twice now a part of the screen has ended up dead to the finger: once under
## the phone's own bars, and once under the game's own news, which slid in over
## the top of every screen exactly where each keeps its filters. Neither showed
## up in any test, because every test pressed a control it already knew was
## there. This one asks the other way round: on every screen, for every button
## the reader can see, is that button what a finger would actually hit there?
##
## It also checks the margins the game keeps for the phone's bars, since a
## control under a bar is as unreachable as one under a card.

var _host: Node
var _viewport: Viewport
var _shell: Control


func run() -> void:
	_margins_are_read_from_the_device()


func run_in_tree(host: Node) -> void:
	_host = host
	_viewport = host.get_viewport()

	ContentRegistry.ensure_loaded()
	SimTestHarness.fresh_world(4242)
	SimTestHarness.advance(240)
	SimClock.set_time_scale(0.0)

	# Laid out as on a phone: bars above and below, the game between them.
	var margins := Vector4(0, 40, 0, 56)
	var frame := Control.new()
	host.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell = load("res://ui/main/ObservationShell.tscn").instantiate()
	frame.add_child(_shell)
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.inset(_shell, margins)
	await _frames(4)

	var view := _viewport.get_visible_rect().size
	check_near(_shell.global_position.y, margins.y, 0.5, "the shell should start below the top bar")
	check_near(_shell.global_position.y + _shell.size.y, view.y - margins.w, 0.5,
		"the shell should end above the bottom bar")

	# The question itself has to be able to say no: something laid over a
	# button, even something that cannot be seen, must be noticed.
	_shell.show_tab("map")
	await _frames(5)
	var chip: Control = _shell._screens["map"]._chips.get_child(1)
	check(_reaches(chip), "a map chip should be reachable to begin with")
	var cover := Control.new()
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.add_child(cover)
	cover.global_position = chip.global_position - Vector2(4, 4)
	cover.size = chip.size + Vector2(8, 8)
	await _frames(2)
	check(not _reaches(chip), "something laid over a button should be noticed")
	cover.queue_free()
	await _frames(2)

	# Every screen, with nothing in the way.
	for tab in _shell.TABS:
		_shell.show_tab(tab["id"])
		await _frames(5)
		await _sweep("on %s" % tab["label"])

	# With news arriving: headlines go to the bar and cover nothing.
	for tab in _shell.TABS:
		_shell.show_tab(tab["id"])
		await _frames(3)
		for i in 3:
			_shell._news._queue({"weight": NewsFeed.Weight.NOTABLE, "label": "分家",
				"colour": Palette.HOUSE, "glyph": &"tree", "tab": "lineage", "subject": &"",
				"year": 60, "text": "試しの見出し その%d" % i})
		await _frames(8)
		await _sweep("on %s with news arriving" % tab["label"])

	# After a rupture has taken the screen and been dismissed.
	_shell.show_tab("map")
	_shell._news._queue({"weight": NewsFeed.Weight.MAJOR, "label": "王都制圧",
		"colour": Palette.DANGER, "glyph": &"flame", "tab": "incidents", "subject": &"",
		"year": 60, "text": "試しの破局"})
	await _wait(1.3)
	check(_shell._news._banner != null, "a rupture should take the screen")
	_shell._news._close_banner(0.0)
	await _wait(0.5)
	await _sweep("after a rupture is dismissed")

	# After the help sheet has been opened and closed.
	_shell.show_help()
	await _wait(0.4)
	_shell.show_help()
	await _wait(0.4)
	await _sweep("after the help sheet is closed")

	# After the title has lifted.
	var title := TitleScreen.new()
	frame.add_child(title)
	title.set_safe_margins(margins)
	await _frames(4)
	var resume: Button = title._menu.get_child(0)
	check(_reaches(resume), "the title's 続きから should be reachable")
	title._leave()
	await _wait(0.8)
	await _sweep("after the title lifts")

	# The dock and the clock are never covered by a sheet opened from a screen.
	_shell.show_tab("god")
	await _frames(4)
	_shell._screens["god"]._open_offers()
	await _wait(0.5)
	for i in _shell._dock.get_child_count():
		check(_reaches(_shell._dock.get_child(i)),
			"dock tab %d should stay reachable while a sheet is open" % i)
	_shell._screens["god"]._sheet.close()
	await _wait(0.4)

	frame.queue_free()
	await _frames(2)
	finish()


func _margins_are_read_from_the_device() -> void:
	# A 1080x2400 window with a 96px status bar and a 132px navigation bar,
	# shown at 720 units wide.
	var m := SafeArea.from_device(Vector2(1080, 2400), Rect2i(0, 96, 1080, 2400 - 96 - 132),
		Vector2(720, 1600))
	check_near(m.y, 64.0, 0.01, "the top margin should be the status bar, in screen units")
	check_near(m.w, 88.0, 0.01, "the bottom margin should be the navigation bar, in screen units")
	check_near(m.x + m.z, 0.0, 0.01, "there should be no side margins on a plain phone")
	var none := SafeArea.from_device(Vector2(1080, 2400), Rect2i(0, 0, 0, 0), Vector2(720, 1600))
	check_eq(none, Vector4.ZERO, "a device that reports nothing yet should get no margins")
	var absurd := SafeArea.from_device(Vector2(1080, 2400), Rect2i(0, 2000, 1080, 100),
		Vector2(720, 1600))
	check(absurd.y <= 1600.0 * SafeArea.MAX_SHARE + 0.01,
		"a nonsensical reading should not push the game off the screen")


## Presses nothing: asks, for every button a reader can see, whether a finger
## put on its middle would land on it.
func _sweep(where: String) -> void:
	await _frames(2)
	var view := Rect2(Vector2.ZERO, _viewport.get_visible_rect().size)
	var seen := 0
	for button in _buttons(_shell):
		if not _on_screen(button, view):
			continue
		seen += 1
		check(_reaches(button), "%s: '%s' at %s cannot be reached — %s is in the way" % [where,
			_name_of(button), button.get_global_rect().get_center(), _blocker(button)])
	check_gt(float(seen), 6.0, "%s: there should be buttons to reach" % where)


func _reaches(control: Control) -> bool:
	var hit := _hit_at(control.get_global_rect().get_center())
	return hit != null and (hit == control or control.is_ancestor_of(hit))


func _blocker(control: Control) -> String:
	var hit := _hit_at(control.get_global_rect().get_center())
	return "nothing" if hit == null else "%s (%s)" % [hit.name, hit.get_class()]


func _hit_at(point: Vector2) -> Control:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_viewport.push_input(motion, true)
	return _viewport.gui_get_hovered_control()


func _buttons(node: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for child in node.get_children():
		if child is Control and not (child as Control).visible:
			continue
		if child is BaseButton and not (child as BaseButton).disabled:
			out.append(child)
		out.append_array(_buttons(child))
	return out


## Visible, in the tree, on the screen, and not scrolled out of the list it is in.
func _on_screen(control: Control, view: Rect2) -> bool:
	if not control.is_visible_in_tree() or control.size.x < 4.0 or control.size.y < 4.0:
		return false
	var centre := control.get_global_rect().get_center()
	if not view.has_point(centre):
		return false
	var parent := control.get_parent()
	while parent != null and parent is Control:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().has_point(centre):
			return false
		if (parent as Control).clip_contents and not (parent as Control).get_global_rect().has_point(centre):
			return false
		parent = parent.get_parent()
	return true


func _name_of(button: BaseButton) -> String:
	if button is Button and not (button as Button).text.is_empty():
		return (button as Button).text
	return "%s/%s" % [button.get_parent().name, button.name]


func _frames(count: int) -> void:
	for i in count:
		await _host.get_tree().process_frame


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _host.get_tree().process_frame
