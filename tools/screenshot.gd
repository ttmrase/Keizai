extends Node

## Boots a world, runs it forward far enough to have a history, then captures
## each screen. Development tooling for looking at the UI without a device.
##
##   xvfb-run -a godot --path . res://tools/Screenshot.tscn -- --out=/tmp/shots

var _out_dir := "/tmp/keizai-shots"
var _ticks := 1600
var _seed := 20260908


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.split("=")[1]
		elif arg.begins_with("--ticks="):
			_ticks = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			_seed = int(arg.split("=")[1])
	DirAccess.make_dir_recursive_absolute(_out_dir)

	ContentRegistry.ensure_loaded()
	WorldGenerator.generate(_seed)
	SimClock.start(0)

	# A world with something to show: monsters, then hardship, then plenty.
	GodPowerAPI.set_monster_spawn_rate(2.2)
	SimClock.advance_n_ticks_instant(int(_ticks * 0.4))
	GodPowerAPI.set_harvest_modifier(0.55)
	GodPowerAPI.trigger_disaster(&"drought", &"", 1.3)
	SimClock.advance_n_ticks_instant(int(_ticks * 0.25))
	GodPowerAPI.trigger_disaster(&"plague", &"", 1.0)
	GodPowerAPI.set_harvest_modifier(1.2)
	GodPowerAPI.set_ore_supply_rate(2.2)
	GodPowerAPI.set_monster_spawn_rate(0.9)
	SimClock.advance_n_ticks_instant(_ticks - int(_ticks * 0.65))
	SimClock.set_time_scale(0.0)

	var shell: Control = preload("res://ui/main/ObservationShell.tscn").instantiate()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	await get_tree().process_frame
	await get_tree().process_frame

	for tab in shell.TABS:
		shell.show_tab(tab["id"])
		await _settle()
		await _capture("%s/%s.png" % [_out_dir, tab["id"]])

	# The lineage screen is worth two shots: institutions and people.
	shell.show_tab("lineage")
	await _settle()
	var lineage: Control = shell._screens["lineage"]
	lineage._show_people()
	await _settle()
	await _capture("%s/lineage_people.png" % _out_dir)

	# Families are their own screen now, so it gets its own shot.
	lineage._show_houses()
	await _settle()
	await _capture("%s/lineage_houses.png" % _out_dir)

	lineage._show_people()
	await _settle()

	# The whole family at once: every house on one chart, joined by marriage.
	lineage._graph.clear_focus()
	lineage._update_focus_note()
	await _settle()
	await _capture("%s/lineage_all_people.png" % _out_dir)

	# And one focused on a single figure, which is how it is normally read.
	var subject := &""
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.ever_held_office() and not p.children_ids.is_empty():
			subject = id
			break
	if subject != &"":
		lineage._graph.focus_on(subject)
		lineage._show_detail(subject)
		lineage._update_focus_note()
		await _settle()
		await _capture("%s/lineage_focus.png" % _out_dir)

	# A settlement selected on the map, so the detail sheet is visible.
	shell.show_tab("map")
	await _settle()
	var map: Control = shell._screens["map"]
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		map._on_tapped(s.position * map.MAP_SIZE)
		break
	await _settle()
	await _capture("%s/map_detail.png" % _out_dir)

	print("captured to %s" % _out_dir)
	get_tree().quit(0)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("  %s" % path)
