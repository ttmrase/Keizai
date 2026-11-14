extends Node

## Boots a world, runs it forward far enough to have a history, then captures
## each screen. Development tooling for looking at the UI without a device.
##
##   xvfb-run -a godot --path . res://tools/Screenshot.tscn -- --out=/tmp/shots
##
## --phone draws it as a phone would show it: a tall window with the status and
## navigation bars floating over the game, and the game keeping clear of them.
## Run it as
##   xvfb-run -a --server-args="-screen 0 720x1600x24" godot --path . \
##     --resolution 720x1600 res://tools/Screenshot.tscn -- --phone --out=/tmp/shots
##
## --cache keeps the fast-forwarded world between runs, so looking at a change
## to a screen does not mean waiting for six centuries again.

const CACHE_SLOT := 9
## How much of the run is always played out, cache or not, so the things only
## the screens remember (who has been rising) have something in them.
const WARM_TICKS := 320
## The bars a phone keeps over the game, in screen units: status above,
## navigation below.
const PHONE_MARGINS := Vector4(0, 46, 0, 62)

var _out_dir := "/tmp/keizai-shots"
var _ticks := 1600
var _seed := 20260908
var _phone := false
var _cache := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.split("=")[1]
		elif arg.begins_with("--ticks="):
			_ticks = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			_seed = int(arg.split("=")[1])
		elif arg == "--phone":
			_phone = true
		elif arg == "--cache":
			_cache = true
	DirAccess.make_dir_recursive_absolute(_out_dir)

	ContentRegistry.ensure_loaded()
	Oracle.use_annals("%s/annals.cfg" % _out_dir)
	DirAccess.remove_absolute("%s/annals.cfg" % _out_dir)
	# The power screen remembers what it was shown; here nothing is shown while
	# the world runs ahead, so it is fed directly.
	EventBus.power_recalculated.connect(func(tick: int): PowerHistory.sample(tick))
	_run_world()
	SimClock.set_time_scale(0.0)

	if _phone:
		SafeArea.pretend = PHONE_MARGINS
	var margins := SafeArea.margins(get_viewport())
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.draw.connect(_draw_backdrop.bind(frame, margins))
	add_child(frame)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.inset(host, margins)
	frame.add_child(host)

	var shell: Control = preload("res://ui/main/ObservationShell.tscn").instantiate()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(shell)
	if _phone:
		var bars := Control.new()
		bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.z_index = 100
		bars.draw.connect(_draw_phone_bars.bind(bars, margins))
		frame.add_child(bars)
	await get_tree().process_frame
	await get_tree().process_frame

	# The title over everything, and the first card of the guide.
	var title := TitleScreen.new()
	frame.add_child(title)
	title.set_safe_margins(margins)
	for i in 40:
		await get_tree().process_frame
	await _capture("%s/title.png" % _out_dir)
	title._menu.visible = false
	title._guide_index = 0
	title._guide_cards = [TitleScreen.GUIDE[2]]
	title._show_guide_card()
	for i in 20:
		await get_tree().process_frame
	await _capture("%s/title_guide.png" % _out_dir)
	title.queue_free()
	await _settle()

	# Two prophecies spoken, so the god's panel shows what one looks like.
	Oracle.current_offers()
	Oracle.declare(0)
	Oracle.declare(0)

	for tab in shell.TABS:
		shell.show_tab(tab["id"])
		await _settle()
		await _capture("%s/%s.png" % [_out_dir, tab["id"]])

	# The oracle: the offers, the record of feats, and the chronicle as a book.
	shell.show_tab("god")
	await _settle()
	var god: Control = shell._screens["god"]
	god._open_offers()
	for i in 20:
		await get_tree().process_frame
	await _capture("%s/oracle_offers.png" % _out_dir)
	god._sheet.close()
	await _settle()
	var god_scroll: ScrollContainer = god.get_node("Scroll")
	god_scroll.scroll_vertical = 1240
	await _settle()
	await _capture("%s/god_calamities.png" % _out_dir)
	god_scroll.scroll_vertical = 0
	god_scroll.scroll_vertical = 100000
	await _settle()
	await _capture("%s/god_settings.png" % _out_dir)
	god_scroll.scroll_vertical = 0
	var feats := FeatsSheet.open(god)
	for i in 20:
		await get_tree().process_frame
	await _capture("%s/feats.png" % _out_dir)
	feats.close()
	await _settle()
	# The legend for a screen, and the light a fulfilled prophecy is given.
	shell.show_tab("map")
	await _settle()
	shell.show_help()
	for i in 20:
		await get_tree().process_frame
	await _capture("%s/help_map.png" % _out_dir)
	shell.show_help()
	await _settle()
	shell._fx.wash(Palette.ACCENT, 0.3, 1.0)
	shell._fx.burst(Palette.ACCENT, &"sun")
	shell._fx.rise("神威 +64", Palette.ACCENT, shell._status.might_anchor())
	for i in 9:
		await get_tree().process_frame
	await _capture("%s/fx_burst.png" % _out_dir)
	for i in 60:
		await get_tree().process_frame
	shell._fx.wash(Palette.DANGER, 0.3, 0.9)
	shell._fx.omen(&"plague", Palette.DANGER)
	for i in 14:
		await get_tree().process_frame
	await _capture("%s/fx_omen.png" % _out_dir)
	for i in 50:
		await get_tree().process_frame

	shell.show_tab("chronicle")
	var book: Control = shell._screens["chronicle"]
	book._on_filter(book.FILTERS.size() - 1)
	await _settle()
	await _capture("%s/chronicle_eras.png" % _out_dir)
	book._on_filter(0)
	await _settle()

	# Following the chronicle to whoever it names: the latest house split,
	# opened in the tree on the new branch, and the latest death, on the person.
	for kind in [HistoryEvent.EventType.SCHISM, HistoryEvent.EventType.DEATH]:
		for i in range(HistoryLog.buffer.size() - 1, -1, -1):
			var e: HistoryEvent = HistoryLog.buffer[i]
			if e.event_type == kind and NewsFeed.subject_of(e) != &"" \
					and not Retainers.is_service_household_event(e):
				shell.reveal(NewsFeed.subject_of(e))
				break
		for f in 6:
			await get_tree().process_frame
		await _settle()
		await _capture("%s/reveal_%s.png" % [_out_dir,
			"branch" if kind == HistoryEvent.EventType.SCHISM else "person"])

	# The news reaching the reader: a headline in the bar, then a rupture.
	shell.show_tab("map")
	await _settle()
	var news: NewsFeed = shell._news
	GodPowerAPI.trigger_disaster(&"plague", &"", 1.0)
	for e in HistoryLog.buffer.slice(maxi(0, HistoryLog.buffer.size() - 400)):
		if NewsFeed.classify(e)["weight"] == NewsFeed.Weight.NOTABLE \
				and e.event_type != HistoryEvent.EventType.DISASTER_OCCURRED:
			shell._news_bar.push(NewsFeed.classify(e))
			break
	for i in 30:
		await get_tree().process_frame
	await _capture("%s/news_bar.png" % _out_dir)
	var rupture := HistoryEvent.new()
	rupture.event_type = HistoryEvent.EventType.INCIDENT
	rupture.tick = SimClock.current_tick
	rupture.payload = {"incident_kind": "capital_seizure"}
	rupture.description = "門前会議がウド森を制圧した。門は内から開かれ、誰も血を流さずに国の主が替わった。"
	var item := NewsFeed.classify(rupture)
	item["paused"] = true
	news._show_banner(item)
	for i in 20:
		await get_tree().process_frame
	var fall := HistoryEvent.new()
	fall.event_type = HistoryEvent.EventType.POWER_TRANSFER
	fall.tick = SimClock.current_tick
	fall.payload = {"regime_change": true}
	fall.description = "開かれた神権評議制は倒れ、中央集権的な軍事評議制が国を継いだ。"
	news._follow_up(NewsFeed.classify(fall))
	for i in 6:
		await get_tree().process_frame
	await _capture("%s/news_banner.png" % _out_dir)
	news._close_banner(0.0)
	news._clear()
	await _settle()
	var spoken: Dictionary = Oracle.prophecies[0].duplicate() if not Oracle.prophecies.is_empty() \
		else {"text": "30年のうちに、真商人会が世で最も力ある組織となる", "reward": 64}
	spoken["state"] = "fulfilled"
	spoken["resolved"] = SimClock.current_tick
	news._on_prophecy(spoken)
	for i in 40:
		await get_tree().process_frame
	await _capture("%s/news_prophecy.png" % _out_dir)
	news._close_banner(0.0)
	news._clear()
	await _settle()

	# The chronicle narrowed to one family, which is how a house is followed.
	shell.show_tab("chronicle")
	await _settle()
	var chronicle: Control = shell._screens["chronicle"]
	var followed: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE \
				and (followed == null or house.power_score > followed.power_score):
			followed = house
	if followed != null:
		chronicle._on_house_chosen(followed.org_id)
		await _settle()
		await _capture("%s/chronicle_house.png" % _out_dir)
		chronicle._on_house_button()          # back to the whole world
		await _settle()

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
	# Opened on a family that broke away from another, so the sheet shows why.
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.founding_tick > 0 and house.parent_org_id != &"":
			lineage._graph.selected_id = house.org_id
			lineage._show_detail(house.org_id)
			lineage._graph.center_on_node(house.org_id)
			break
	await _settle()
	await _capture("%s/lineage_houses.png" % _out_dir)

	# That same family on its own: who carries the name, and who married into it.
	lineage._open_house_tree()
	lineage._toggle_scope()          # everyone, not just the heads
	await _settle()
	await _capture("%s/lineage_house_tree.png" % _out_dir)
	lineage._toggle_scope()

	lineage._show_all_people()
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

	# And the chart a long press opens: one line of descent, with each generation
	# of it shown beside its own brothers and sisters.
	var kin_subject := _somebody_with_relatives()
	if kin_subject != &"":
		lineage._on_node_long_pressed(kin_subject)
		await _settle()
		await _capture("%s/lineage_kin.png" % _out_dir)
	lineage._graph.clear_focus()
	lineage._update_focus_note()

	# The relations field, with a house picked out so the sheet is showing.
	shell.show_tab("relations")
	await _settle()
	var relations: Control = shell._screens["relations"]
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE and relations._spots.has(house.org_id):
			relations._on_tapped(relations._spots[house.org_id])
			break
	await _settle()
	await _capture("%s/relations.png" % _out_dir)

	# The other questions the map can answer, and a calamity across it.
	shell.show_tab("map")
	await _settle()
	var atlas: Control = shell._screens["map"]
	atlas._on_overlay(1)
	await _settle()
	await _capture("%s/map_faith.png" % _out_dir)
	atlas._on_overlay(3)
	for id in GameState.world.settlements:
		GameState.world.settlements[id].unrest = randf_range(0.2, 0.95)
	atlas._refresh()
	await _settle()
	await _capture("%s/map_unrest.png" % _out_dir)
	atlas._on_overlay(0)
	GodPowerAPI.trigger_disaster(&"drought", &"", 1.3)
	atlas._refresh()
	for i in 20:
		await get_tree().process_frame
	await _capture("%s/map_drought.png" % _out_dir)

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


## Somebody far enough down the record to have ancestors above them, siblings
## beside them and children below — so the chart shows all three.
func _somebody_with_relatives() -> StringName:
	var best := &""
	var best_depth := -1
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.father_id == &"" or p.children_ids.is_empty():
			continue
		var father := GameState.get_person(p.father_id)
		if father == null or father.children_ids.size() < 2:
			continue
		var depth := 0
		var walk := p
		while walk != null and walk.father_id != &"" and depth < 20:
			walk = GameState.get_person(walk.father_id)
			depth += 1
		if depth > best_depth:
			best_depth = depth
			best = id
	return best


## Builds the world the screens are shown over: monsters, then hardship, then
## plenty. With --cache, everything but the last stretch is kept between runs.
func _run_world() -> void:
	var warm := maxi(0, _ticks - WARM_TICKS)
	var manifest_path := SaveManager.slot_dir(CACHE_SLOT).path_join("manifest.json")
	var cached := false
	if _cache and FileAccess.file_exists(manifest_path):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if int(manifest.get("tick", -1)) == warm and int(manifest.get("world_seed", 0)) == _seed:
			cached = SaveManager.load_game(CACHE_SLOT)
	if not cached:
		WorldGenerator.generate(_seed)
		SimClock.start(0)
		GodPowerAPI.set_monster_spawn_rate(2.2)
		SimClock.advance_n_ticks_instant(int(_ticks * 0.4))
		GodPowerAPI.set_harvest_modifier(0.55)
		GodPowerAPI.trigger_disaster(&"drought", &"", 1.3)
		SimClock.advance_n_ticks_instant(int(_ticks * 0.25))
		GodPowerAPI.trigger_disaster(&"plague", &"", 1.0)
		GodPowerAPI.set_harvest_modifier(1.2)
		GodPowerAPI.set_ore_supply_rate(2.2)
		GodPowerAPI.set_monster_spawn_rate(0.9)
		SimClock.advance_n_ticks_instant(maxi(0, warm - SimClock.current_tick))
		if _cache:
			SaveManager.save_game(CACHE_SLOT)
	SimClock.advance_n_ticks_instant(maxi(0, _ticks - SimClock.current_tick))


## What main.gd paints under the phone's bars.
func _draw_backdrop(frame: Control, margins: Vector4) -> void:
	frame.draw_rect(Rect2(Vector2.ZERO, frame.size), Palette.BG)
	frame.draw_rect(Rect2(0, 0, frame.size.x, margins.y), Palette.PANEL)
	frame.draw_rect(Rect2(0, frame.size.y - margins.w, frame.size.x, margins.w), Palette.PANEL)


## A phone's own furniture, floating over the game as Android draws it.
func _draw_phone_bars(bars: Control, margins: Vector4) -> void:
	var font := bars.get_theme_default_font()
	var ink := Color(1, 1, 1, 0.9)
	bars.draw_string(font, Vector2(34, margins.y * 0.5 + 8), "22:16", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 20, ink)
	bars.draw_string(font, Vector2(bars.size.x - 150, margins.y * 0.5 + 8), "5G  ▮▮▮  54",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	bars.draw_circle(Vector2(bars.size.x * 0.5, margins.y * 0.5), 9, Color.BLACK)
	var y := bars.size.y - margins.w * 0.5
	bars.draw_rect(Rect2(0, bars.size.y - margins.w, bars.size.x, margins.w), Color(0, 0, 0, 0.35))
	bars.draw_colored_polygon(PackedVector2Array([Vector2(bars.size.x * 0.25 + 9, y - 11),
		Vector2(bars.size.x * 0.25 - 9, y), Vector2(bars.size.x * 0.25 + 9, y + 11)]), ink)
	bars.draw_circle(Vector2(bars.size.x * 0.5, y), 10, ink)
	bars.draw_rect(Rect2(bars.size.x * 0.75 - 10, y - 10, 20, 20), ink)


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("  %s" % path)
