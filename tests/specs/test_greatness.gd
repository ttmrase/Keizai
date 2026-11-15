extends Spec

## 偉人: a few, recorded once, kept forever, and never the ordinary run of rulers.

const SLOT := 6


func run() -> void:
	_check_recognition_is_recorded()
	_check_founder_of_a_lasting_state()
	_check_rarity_and_determinism()
	finish()


func _count_events() -> int:
	var n := 0
	for e in HistoryLog.backbone:
		if e.event_type == HistoryEvent.EventType.GREATNESS:
			n += 1
	return n


## Recognition goes through the record, lands in the state, survives a save and
## is never given twice for the same field.
func _check_recognition_is_recorded() -> void:
	SimTestHarness.fresh_world(7101)
	SimTestHarness.advance(200)
	var someone: NotableIndividual = null
	for p in GameState.living_people():
		if p.ever_held_office():
			someone = p
			break
	check(someone != null, "somebody to recognise")
	if someone == null:
		return
	var before := Greatness.all().size()
	var events_before := _count_events()
	Greatness._recognise(someone, "craft", "試しの祖", "試しに列せられた。", [], SimClock.current_tick)
	check_eq(Greatness.all().size(), before + 1, "recognition lands in the state")
	check_eq(_count_events(), events_before + 1, "and in the permanent record, as an event")
	check(Greatness.is_great(someone.person_id), "and can be asked about")
	Greatness._recognise(someone, "craft", "試しの祖", "二度目。", [], SimClock.current_tick)
	check_eq(Greatness.all().size(), before + 1, "the same person is not listed twice in one field")
	Greatness._recognise(someone, "rule", "試しの君", "別の分野。", [], SimClock.current_tick)
	check_eq(Greatness.all().size(), before + 2, "but may be in another")

	GameState.world.great_pending.append({"person_id": String(someone.person_id),
		"house_id": String(someone.house_org_id), "due": SimClock.current_tick + 400,
		"from": "男爵", "to": "侯爵"})
	var greats := Greatness.all().duplicate(true)
	var pending := GameState.world.great_pending.size()
	check(SaveManager.save_game(SLOT), "saving")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading")
	check_eq(Greatness.all().size(), greats.size(), "the hall survives a save")
	for i in mini(greats.size(), Greatness.all().size()):
		for key in ["person_id", "field", "title", "text", "tick"]:
			check_eq(Greatness.all()[i][key], greats[i][key], "greats[%d].%s survives a save" % [i, key])
	check_eq(GameState.world.great_pending.size(), pending, "judgements still pending survive a save")
	SaveManager.delete_save(SLOT)


## A state that lasts a century and a half makes its first ruler a founder —
## if they reigned long enough to have founded anything.
func _check_founder_of_a_lasting_state() -> void:
	SimTestHarness.fresh_world(7201)
	SimTestHarness.advance((Greatness.FOUNDER_YEARS + 2) * SimConfig.TICKS_PER_YEAR)
	var root := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	var first := Greatness._first_holding(root.org_id)
	if first.is_empty():
		return
	var founder_id := String(first["person"].person_id)
	var span := (root.dissolved_tick if not root.is_active() else SimClock.current_tick) \
		- root.founding_tick
	var lasted := span >= Greatness.FOUNDER_YEARS * SimConfig.TICKS_PER_YEAR
	var named := false
	for entry in Greatness.in_field("rule"):
		if entry["person_id"] == founder_id and entry["title"] == "建国の父":
			named = true
	if lasted and int(first["years"]) >= Greatness.FOUNDER_REIGN_YEARS:
		check(named, "the first ruler of a state that lasted %d years is its founder"
			% Greatness.FOUNDER_YEARS)
	else:
		check(not named, "no founder is named for a state that did not last, or a reign too short")


## Every state that somebody took and that then lasted the full span names
## who took it, whatever else was judged about it first.
func _check_takers_are_judged() -> void:
	var seen := 0
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false):
		var span := (polity.dissolved_tick if not polity.is_active() else SimClock.current_tick) \
			- polity.founding_tick
		if span < (Greatness.CHANGE_YEARS + 1) * SimConfig.TICKS_PER_YEAR:
			continue
		var origin := HistoryLog.find_event(polity.origin_event_id)
		if origin == null:
			continue
		var taker := String(origin.payload.get("claimant_leader_id", ""))
		if taker == "" or GameState.get_person(StringName(taker)) == null:
			continue
		seen += 1
		var named := false
		for entry in Greatness.in_field("change"):
			if entry["person_id"] == taker:
				named = true
		check(named, "%s lasted %d years: whoever took it should be its 変革者"
			% [polity.display_name, span / SimConfig.TICKS_PER_YEAR])
	print("    %d states taken and lasting, each with its 変革者" % seen)


## Over long runs, quiet and hard, the hall stays small: a few per thousand
## years, a tiny share of everyone who ever held office, nobody twice in a
## field — and the same world remembers the same people.
func _check_rarity_and_determinism() -> void:
	var summaries: Array[String] = []
	for attempt in 2:
		SimTestHarness.eventful_world(7301, 4000)
		var line: Array[String] = []
		for entry in Greatness.all():
			line.append("%s|%s|%d" % [entry["person_id"], entry["title"], int(entry["tick"])])
		summaries.append(",".join(line))
		if attempt == 0:
			_check_takers_are_judged()
	check_eq(summaries[1], summaries[0], "the same world remembers the same people")

	for world_seed in [7302, 7303]:
		SimTestHarness.fresh_world(world_seed)
		SimTestHarness.advance(4000)
		var officers := 0
		for id in GameState.people:
			if GameState.people[id].ever_held_office():
				officers += 1
		var greats := Greatness.all()
		var years := SimClock.year()
		check(float(greats.size()) <= 15.0 * float(years) / 1000.0 + 2.0,
			"seed %d: %d 偉人 in %d years is too many" % [world_seed, greats.size(), years])
		check(float(greats.size()) < 0.05 * float(officers),
			"seed %d: 偉人 (%d) must be a tiny share of office-holders (%d)" % [world_seed,
				greats.size(), officers])
		var seen := {}
		for entry in greats:
			var key := "%s|%s" % [entry["person_id"], entry["field"]]
			check(not seen.has(key), "seed %d: nobody twice in a field" % world_seed)
			seen[key] = true
			check(GameState.get_person(StringName(entry["person_id"])) != null,
				"seed %d: every 偉人 is somebody in the record" % world_seed)
		print("    seed %d: %d 偉人 among %d office-holders in %d years" % [world_seed,
			greats.size(), officers, years])
