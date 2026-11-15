extends Spec

## 政争 and 遺恨: grudges born of the things that wrong a family, each pointing at
## its cause; quarrels at court that cost the loser a seat or its standing; the
## grudges they leave, fading slowly over generations; and all of it far commoner
## than war, the same every time, and kept by a save.

const SLOT := 5

## What each kind of grudge has to be caused by.
const CAUSE_TYPES := {
	"succession": HistoryEvent.EventType.SUCCESSION,
	"seat": HistoryEvent.EventType.SUCCESSION,
	"heirs": HistoryEvent.EventType.OFFICE,
	"displaced": HistoryEvent.EventType.OFFICE,
	"estate": HistoryEvent.EventType.POWER_TRANSFER,
	"stripped": HistoryEvent.EventType.POWER_TRANSFER,
	"excommunication": HistoryEvent.EventType.INCIDENT,
	"assassination": HistoryEvent.EventType.DEATH,
	"intrigue": HistoryEvent.EventType.INTRIGUE,
}


func run() -> void:
	_check_grudges_point_at_their_causes()
	_check_grudges_fade_but_outlive_a_head()
	_check_the_loser_loses()
	_check_more_quarrels_than_wars()
	_check_round_trip_and_old_save()
	_check_determinism()
	finish()


func _event(id: String) -> HistoryEvent:
	return HistoryLog.find_event(StringName(id))


## Every grudge goes back to a recorded event of the right kind, and every
## recent disputed succession between two houses has left one.
func _check_grudges_point_at_their_causes() -> void:
	var kinds := {}
	var from_succession := 0
	for world_seed in [9101, 9102, 9103]:
		SimTestHarness.eventful_world(world_seed, 2400)
		var tick := SimClock.current_tick
		for g in GameState.world.grudges:
			kinds[g["kind"]] = int(kinds.get(g["kind"], 0)) + 1
			var cause := _event(String(g["cause"]))
			check(cause != null, "seed %d: grudge %d (%s) points at an event that exists" % [
				world_seed, int(g["id"]), g["kind"]])
			if cause == null:
				continue
			check_eq(cause.event_type, CAUSE_TYPES.get(String(g["kind"]), -1),
				"seed %d: a %s grudge is caused by the right kind of event" % [world_seed, g["kind"]])
			check_eq(int(g["since"]), cause.tick, "a grudge dates from its cause")
			check(int(g["updated"]) >= int(g["since"]) and int(g["updated"]) <= tick,
				"a grudge was last deepened between its cause and now")
			check((g["causes"] as Array).has(String(g["cause"])), "the first cause stays on the list")
			check(StringName(g["holder"]) != StringName(g["target"]) or String(g["holder_person"]) != "",
				"a quarrel inside one family is held by a person")
			if String(g["kind"]) == "succession" or String(g["kind"]) == "seat":
				from_succession += 1
		# Recent disputed successions between two families have left a grudge.
		for e in HistoryLog.backbone:
			if e.event_type != HistoryEvent.EventType.SUCCESSION \
					or not bool(e.payload.get("contested", false)) \
					or tick - e.tick > 30 * SimConfig.TICKS_PER_YEAR:
				continue
			var loser := GameState.get_person(StringName(e.payload.get("loser_id", "")))
			var winner := GameState.get_person(e.subject_person_id)
			if loser == null or winner == null:
				continue
			# A family that has since died out holds and is held to nothing.
			var lh := GameState.get_organization(loser.house_org_id)
			var wh := GameState.get_organization(winner.house_org_id)
			if lh == null or not lh.is_active() or wh == null or not wh.is_active():
				continue
			var found := false
			for g in GameState.world.grudges:
				if (g["causes"] as Array).has(String(e.event_id)):
					found = true
			check(found, "seed %d: the disputed succession of %d年 left a grudge" % [
				world_seed, int(e.tick / SimConfig.TICKS_PER_YEAR)])
	check_gt(float(from_succession), 0.0, "disputed successions leave grudges")
	print("    grudges by kind: %s" % [kinds])


## A grudge burns less every year it is not fed, a little less again when the
## house holding it changes head — and still outlasts the head who first held it.
func _check_grudges_fade_but_outlive_a_head() -> void:
	SimTestHarness.eventful_world(9201, 2400)
	var watched := {}
	for g in GameState.world.grudges:
		watched[int(g["id"])] = g.duplicate(true)
	check_gt(float(watched.size()), 0.0, "a world of 600 years has grudges")
	for id in watched:
		var g: Dictionary = watched[id]
		var now := SimClock.current_tick
		check(Grudges.strength_of(g, now + 200) < Grudges.strength_of(g, now),
			"a grudge fades with the years")
		check_near(Grudges.strength_of(g, int(g["updated"]) + 60 * SimConfig.TICKS_PER_YEAR),
			float(g["strength"]) * pow(1.0 - Grudges.YEARLY_FADE, 60.0), 0.0001,
			"by the rate it is meant to")
	SimTestHarness.advance(800)
	var outlived := 0
	var faded_by_head := 0
	for g in GameState.world.grudges:
		var old: Dictionary = watched.get(int(g["id"]), {})
		if old.is_empty():
			continue
		if int(g["generations"]) > int(old["generations"]):
			faded_by_head += 1
			if int(g["updated"]) > int(old["updated"]) and (g["causes"] as Array).size() \
					== (old["causes"] as Array).size():
				check(float(g["strength"]) < Grudges.strength_of(old, int(g["updated"])) + 0.0001,
					"a new head lets some of it go")
		if int(g["generations"]) >= 1 and Grudges.strength_of(g) >= Grudges.FORGOTTEN:
			outlived += 1
	var outlived_anywhere := outlived
	for world_seed in [9202, 9203]:
		if outlived_anywhere > 0:
			break
		SimTestHarness.eventful_world(world_seed, 3200)
		for g in GameState.world.grudges:
			if int(g["generations"]) >= 1 and Grudges.strength_of(g) >= Grudges.FORGOTTEN:
				outlived_anywhere += 1
	check_gt(float(outlived_anywhere), 0.0, "some grudge outlives the head who first held it")
	print("    grudges outliving a head: %d (faded at a change of head: %d)" % [
		outlived_anywhere, faded_by_head])


## Starts a quarrel between two families at one court and runs it to its end.
func _force_quarrel(world_seed: int, pair_index: int) -> HistoryEvent:
	SimTestHarness.fresh_world(world_seed)
	SimTestHarness.advance(1600)
	var courts := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		var realm := CivilWar.realm_of_house(house)
		if realm == &"":
			continue
		if not courts.has(realm):
			courts[realm] = []
		courts[realm].append(house)
	for realm_id in courts:
		var houses: Array = courts[realm_id]
		if houses.size() < 2 or not GameState.world.intrigues.is_empty():
			continue
		houses.sort_custom(func(x: Organization, y: Organization) -> bool:
			return String(x.org_id) < String(y.org_id))
		var a: Organization = houses[pair_index % houses.size()]
		var b: Organization = houses[(pair_index + 1) % houses.size()]
		# Prefer a target that holds a seat, so a win has one to take.
		for h: Organization in houses:
			if h != a and Intrigue._holds_seat(GameState.get_organization(realm_id), h):
				b = h
				break
		var actor := GameState.get_current_leader(a.org_id)
		if actor == null or not actor.is_adult(SimClock.current_tick):
			continue
		Intrigue._begin(GameState.get_organization(realm_id), a, b, actor, SimClock.current_tick,
			RngService.stream(&"intrigue"))
		var id := String(GameState.world.intrigues[0]["id"])
		var guard := 0
		while not GameState.world.intrigues.is_empty() and guard < 80:
			SimTestHarness.advance(1)
			guard += 1
		for i in range(HistoryLog.backbone.size() - 1, -1, -1):
			var e: HistoryEvent = HistoryLog.backbone[i]
			if e.event_type == HistoryEvent.EventType.INTRIGUE \
					and String(e.payload.get("action", "")) == "resolve" \
					and String(e.payload.get("id", "")) == id:
				return e
		return null
	return null


## Whoever loses really does lose: a seat, or standing that shows in the
## family's grounds of rank — and the loser resents the winner.
func _check_the_loser_loses() -> void:
	var decided := 0
	var displaced := 0
	var attempts := 0
	for world_seed in [9301, 9302, 9303, 9304, 9305, 9306]:
		for pair_index in 2:
			attempts += 1
			var e := _force_quarrel(world_seed, pair_index)
			if e == null:
				continue
			var outcome := String(e.payload.get("outcome", ""))
			check(["won", "backfired", "stalemate", "faded"].has(outcome), "a quarrel ends one of four ways")
			check(e.payload.has("factors") and (outcome == "faded"
				or (e.payload["factors"] as Dictionary).has("luck")), "and says why, line by line")
			if outcome == "faded" or outcome == "stalemate":
				if outcome == "stalemate":
					check_gt(Grudges.toward(StringName(e.payload["instigator"]),
						StringName(e.payload["target"])), 0.0, "a drawn quarrel leaves a grudge")
				continue
			decided += 1
			var id := String(e.payload["id"])
			var loser_id := StringName(e.payload["target"] if outcome == "won" else e.payload["instigator"])
			var winner_id := StringName(e.payload["instigator"] if outcome == "won" else e.payload["target"])
			var loser := GameState.get_organization(loser_id)
			var marked := false
			for mark in loser.blemishes:
				if String(mark.get("kind", "")) == "intrigue" and int(mark.get("tick", -1)) == e.tick:
					marked = true
			check(marked, "the loser carries the mark of it")
			var blemish := 0.0
			for ground in HouseRank.grounds_of(loser, HouseRank.context(true)):
				if String(ground["kind"]) == "blemish":
					blemish = float(ground["value"])
			check(blemish < 0.0, "and it counts against the family's rank")
			for fall in e.payload.get("falls", []):
				var person := GameState.get_person(StringName(fall.get("person", "")))
				check(person != null, "every fall is somebody's")
				if person == null:
					continue
				var recorded := false
				for f in person.falls:
					if String(f.get("intrigue", "")) == id and String(f.get("kind", "")) == String(fall["kind"]):
						recorded = true
				check(recorded, "%s's %s is on their record" % [person.full_name, fall["kind"]])
				if String(fall["kind"]) == "displaced":
					displaced += 1
					var closed := false
					for record in person.office_history:
						if String(record.get("office", "")) == String(fall["office"]) \
								and int(record.get("end", -1)) == e.tick \
								and String(record.get("why", "")) == "intrigue":
							closed = true
					check(closed, "%s was put out of the seat" % person.full_name)
					var polity := GameState.get_organization(StringName(e.payload["polity"]))
					check(StringName(polity.offices.get(String(fall["office"]), {}).get("house", ""))
						!= loser_id or not Intrigue._holds_seat(polity, loser),
						"and the family no longer holds it")
			check_gt(Grudges.toward(loser_id, winner_id), 0.5, "the loser resents the winner")
	check_gt(float(decided), 0.0, "of %d quarrels forced, some were decided" % attempts)
	print("    forced quarrels: %d decided, %d seats lost" % [decided, displaced])


## Over a long run, quarrels at court far outnumber wars, and most go back to a
## disputed succession.
func _check_more_quarrels_than_wars() -> void:
	var quarrels := 0
	var wars := 0
	var from_succession := 0
	for world_seed in [9401, 9402]:
		SimTestHarness.fresh_world(world_seed)
		SimTestHarness.advance(4800)
		for e in HistoryLog.backbone:
			if e.event_type == HistoryEvent.EventType.INTRIGUE \
					and String(e.payload.get("action", "")) == "resolve" \
					and String(e.payload.get("outcome", "")) != "faded":
				quarrels += 1
				var root := String(e.payload.get("motive_root_kind", ""))
				if ["succession", "seat", "heirs"].has(root):
					from_succession += 1
			elif e.event_type == HistoryEvent.EventType.CONFLICT_DECLARED and e.payload.has("war"):
				wars += 1
	check_gt(float(quarrels), float(wars), "quarrels at court outnumber wars")
	check_gt(float(quarrels), 6.0, "two worlds of 1,200 years see more than a handful of quarrels")
	check_gt(float(from_succession) * 2.0, float(quarrels) * 0.8,
		"a good share of quarrels go back to a disputed succession")
	print("    long run: %d quarrels (%d from successions), %d wars in 2400 years" % [
		quarrels, from_succession, wars])


func _canon(value) -> String:
	return JSON.stringify(value, "", true)


func _check_round_trip_and_old_save() -> void:
	SimTestHarness.eventful_world(9501, 2400)
	# Leave a quarrel under way to be saved in the middle of.
	var polity: Organization = null
	for p in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		polity = p
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE and polity != null \
				and CivilWar.realm_of_house(house) == polity.org_id:
			houses.append(house)
	if GameState.world.intrigues.is_empty() and houses.size() >= 2:
		var actor := GameState.get_current_leader(houses[0].org_id)
		if actor != null and actor.is_adult(SimClock.current_tick):
			Intrigue._begin(polity, houses[0], houses[1], actor, SimClock.current_tick,
				RngService.stream(&"intrigue"))
	var before := GameState.to_dict()
	check(SaveManager.save_game(SLOT), "saving")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading")
	var after := GameState.to_dict()
	for key in ["grudges", "intrigues", "next_grudge_id"]:
		check_eq(_canon(after["world"].get(key)), _canon(before["world"].get(key)), "%s survive a save" % key)
	for id in before["organizations"]:
		check_eq(_canon(after["organizations"].get(id, {}).get("intrigue")),
			_canon(before["organizations"][id].get("intrigue")), "a house's record of its quarrels survives")
	for id in before["people"]:
		check_eq(_canon(after["people"][id].get("falls")), _canon(before["people"][id].get("falls")),
			"a person's falls survive a save")
	# A loaded quarrel still ends.
	var guard := 0
	while not GameState.world.intrigues.is_empty() and guard < 80:
		SimTestHarness.advance(1)
		guard += 1
	check(GameState.world.intrigues.is_empty(), "a loaded quarrel still ends")

	# A save from before grudges: none of it written down. The world carries on
	# and begins to bear grudges of its own.
	GameState.world.grudges = []
	GameState.world.intrigues = []
	GameState.world.next_grudge_id = 1
	for org_id in GameState.organizations:
		var org: Organization = GameState.organizations[org_id]
		org.intrigue_won = 0
		org.intrigue_lost = 0
		org.last_intrigue_tick = -1
	for person_id in GameState.people:
		GameState.people[person_id].falls = []
	var data := GameState.to_dict()
	for key in ["grudges", "intrigues", "next_grudge_id"]:
		data["world"].erase(key)
	check(SaveManager.save_game(SLOT), "saving an old-style world")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading an old-style world")
	check(GameState.world.grudges.is_empty(), "an old world remembers no grudges it never recorded")
	SimTestHarness.advance(1200)
	check_gt(float(GameState.world.grudges.size()), 0.0, "and starts bearing them as it runs")
	SaveManager.delete_save(SLOT)


func _check_determinism() -> void:
	var lines: Array[String] = []
	for attempt in 2:
		SimTestHarness.fresh_world(9601)
		SimTestHarness.advance(2800)
		var parts: Array[String] = [_canon(GameState.world.grudges), _canon(GameState.world.intrigues)]
		for e in HistoryLog.backbone:
			if e.event_type == HistoryEvent.EventType.INTRIGUE:
				parts.append("%d %s" % [e.tick, e.description])
		lines.append("\n".join(parts))
	check_eq(lines[1], lines[0], "the same world bears the same grudges and fights the same quarrels")
