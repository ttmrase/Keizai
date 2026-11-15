extends Spec

## 要職と家格の根拠: the seats beside a head of state, who may hold them, how they
## become a family's, the houses next in line, and a rank that is the sum of
## grounds anyone can list.

const SLOT := 5


func run() -> void:
	_check_seats_and_holders()
	_check_rank_is_its_grounds()
	_check_hereditary_after_three()
	_check_heir_house_takes_the_crown()
	_check_war_command()
	_check_records_survive_a_regime()
	_check_round_trip_and_old_save()
	_check_determinism()
	finish()


## A tick just after the yearly appointments and with no rank change since.
func _advance_to_settled(at_least: int) -> void:
	var target := at_least
	while target % SimConfig.TICKS_PER_YEAR != 3 or (target - 1) % 10 == 0 or target % 10 == 0:
		target += 1
	SimTestHarness.advance(target - SimClock.current_tick)


func _check_seats_and_holders() -> void:
	SimTestHarness.fresh_world(8101)
	var seen_seats := {}
	for round_index in 6:
		_advance_to_settled(SimClock.current_tick + 600)
		var realm_of := {}
		for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			realm_of[house.org_id] = CivilWar.realm_of_house(house)
		for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
			var allowed := Offices.seats_for(polity)
			for key in polity.offices:
				seen_seats[String(key)] = true
				var entry: Dictionary = polity.offices[key]
				var person := GameState.get_person(StringName(entry.get("person", "")))
				var house := GameState.get_organization(StringName(entry.get("house", "")))
				check(allowed.has(String(key)) or Offices.WAR_SEATS.has(String(key)),
					"%s keeps a %s it should not have" % [polity.display_name, key])
				check(person != null and person.is_alive(), "every seat is held by somebody alive")
				check(house != null and house.is_active(), "every seat's family still exists")
				if house == null:
					continue
				check(StringName(realm_of.get(house.org_id, &"")) == polity.org_id,
					"%s's %s comes from a family of that state" % [polity.display_name, key])
				check(HouseRank.precedence(house) >= Offices.min_rank_of(String(key), polity) - 0.001,
					"%s (%.1f) is not of the rank to hold %s (needs %.1f)" % [house.display_name,
						HouseRank.precedence(house), key, Offices.min_rank_of(String(key), polity)])
				var held := 0
				for record in person.office_history:
					if int(record.get("end", -1)) < 0:
						held += 1
				check_eq(held, 1, "nobody holds two great offices at once")
	check(seen_seats.has("treasurer") and seen_seats.has("marshal"),
		"every state keeps a treasurer and a marshal")


func _check_rank_is_its_grounds() -> void:
	SimTestHarness.eventful_world(8201, 3000)
	var ctx := HouseRank.context(true)
	var kinds := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		var grounds := HouseRank.grounds_of(house, ctx)
		var total := 0.0
		for g in grounds:
			check(String(g["label"]) != "", "every ground has a name")
			total += float(g["value"])
			kinds[String(g["kind"])] = true
		check_near(HouseRank.standing_from(grounds), total, 0.0001,
			"a family's standing is exactly the sum of its grounds")
	for kind in ["presence", "land", "age", "office", "history"]:
		check(kinds.has(kind), "after a long run some family's standing rests on %s" % kind)


func _check_hereditary_after_three() -> void:
	SimTestHarness.fresh_world(8301)
	SimTestHarness.advance(40)
	var polity := HouseRank.dominant_realm()
	var house: Organization = null
	for h in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if h.is_noble() and GameState.house_members(h.org_id).size() >= 3:
			house = h
			break
	check(house != null, "a family with three grown members")
	if house == null:
		return
	var members := GameState.house_members(house.org_id)
	for i in 3:
		Offices._vacate(polity, "marshal", "replaced", SimClock.current_tick)
		Offices._appoint(polity, "marshal", members[i], house, SimClock.current_tick)
	check_eq(StringName(polity.hereditary_offices.get("marshal", "")), house.org_id,
		"three of one family in a row make the seat theirs by right")
	var grounds := HouseRank.grounds_of(house, HouseRank.context(true))
	var hereditary := false
	for g in grounds:
		if String(g["kind"]) == "hereditary":
			hereditary = true
	check(hereditary, "and that right is one of the family's grounds of rank")


func _check_heir_house_takes_the_crown() -> void:
	SimTestHarness.fresh_world(8401)
	var polity := HouseRank.dominant_realm()
	var guard := 0
	while polity.heir_houses.is_empty() and guard < 40:
		SimTestHarness.advance(40)
		polity = HouseRank.dominant_realm()
		guard += 1
	if polity.heir_houses.is_empty() or polity.ideology.legitimacy_basis \
			!= PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
		check(true, "no hereditary crown with heirs in this world to test")
		return
	var ruler := GameState.get_current_leader(polity.org_id)
	var royal_id := ruler.house_org_id
	var expected := Offices.heir_claimant(polity, SimClock.current_tick)
	check(expected != null, "the first heir house has a head to send")
	# The royal line fails: everyone of it dies in one season.
	for member in GameState.house_members(royal_id):
		HistoryLog.emit_event(HistoryEvent.EventType.DEATH, SimClock.current_tick,
			"%sが没した。" % member.full_name, {}, royal_id, member.person_id)
	SimTestHarness.advance(2)
	var next := GameState.get_current_leader(polity.org_id)
	check(next != null, "the crown is filled again")
	if next != null and expected != null:
		check_eq(next.house_org_id, expected.house_org_id,
			"the first heir house with a head takes the crown")


func _check_war_command() -> void:
	SimTestHarness.fresh_world(8501)
	SimTestHarness.advance(400)
	var polity := HouseRank.dominant_realm()
	var claimant: Organization = null
	for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if claimant == null or faction.power_score > claimant.power_score:
			claimant = faction
	var ids := polity.governs_settlement_ids.duplicate()
	CivilWar.split_country(polity, {"org": claimant, "ground": "議会"},
		{"loyal": ids.slice(0, ids.size() / 2), "rebel": ids.slice(ids.size() / 2), "share": 0.5},
		PoliticalSystemAxes.LegitimacyBasis.ELECTED, PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
		{}, SimClock.current_tick)
	check(not CivilWar.wars().is_empty(), "a war to command")
	if CivilWar.wars().is_empty():
		return
	var war: WarState = CivilWar.wars()[0]
	var war_id := String(war.war_id)
	for side_id in [war.side_a, war.side_b]:
		var side := GameState.get_organization(side_id)
		check(side.offices.has("general"), "each side has a commander-in-general")
	var guard := 0
	while not CivilWar.wars().is_empty() and guard < 200:
		SimTestHarness.advance(4)
		guard += 4
	var recorded := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		for m in house.merits:
			if String(m.get("war_id", "")) != war_id:
				continue
			recorded += 1
			if String(m.get("result", "")) == "draw" or not house.is_active():
				continue
			var counted := false
			for g in HouseRank.grounds_of(house, HouseRank.context(true)):
				if String(g["kind"]) == "merit":
					counted = true
			check(counted, "%s's command counts in its grounds of rank" % house.display_name)
	check_gt(float(recorded), 0.0, "what the commanders did is written to their families")
	for side_id in [war.side_a, war.side_b]:
		var side := GameState.get_organization(side_id)
		for key in Offices.WAR_SEATS:
			check(not side.offices.has(key), "war seats stand down when the war ends")


func _check_records_survive_a_regime() -> void:
	SimTestHarness.fresh_world(8601)
	_advance_to_settled(800)
	var polity := HouseRank.dominant_realm()
	var holders: Array[NotableIndividual] = []
	for key in polity.offices:
		holders.append(GameState.get_person(StringName(polity.offices[key]["person"])))
	check(not holders.is_empty(), "a state with offices to abolish")
	var voice := SocialTies.largest_bloc(polity)
	if voice == null:
		return
	# Nobody stands by the old order: it falls whole.
	polity.legitimacy = 0.0
	for id in GameState.world.settlements:
		GameState.world.settlements[id].unrest = 1.0
	RegimeShift.force_overturn(polity, {"org": voice, "ground": "民衆", "hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY}, SimClock.current_tick)
	_advance_to_settled(SimClock.current_tick + 8)
	for person in holders:
		if person == null:
			continue
		var closed := false
		for record in person.office_history:
			if String(record.get("polity", "")) == String(polity.org_id):
				closed = int(record.get("end", -1)) >= 0 or (polity.is_active()
					and polity.offices.has(String(record.get("office", ""))))
		check(closed, "a seat abolished or left is still on the record of who held it")
	var now := HouseRank.dominant_realm()
	check(not now.offices.has("regent"), "an elected state keeps no regent")


func _check_round_trip_and_old_save() -> void:
	SimTestHarness.eventful_world(8701, 2500)
	var before := GameState.to_dict()
	check(SaveManager.save_game(SLOT), "saving")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading")
	var after := GameState.to_dict()
	for id in before["organizations"]:
		var a: Dictionary = before["organizations"][id]
		var b: Dictionary = after["organizations"].get(id, {})
		for key in ["offices", "hereditary_offices", "heir_houses", "merits", "blemishes", "uji_chief_id"]:
			check_eq(_canon(b.get(key, null)), _canon(a.get(key, null)), "%s.%s survives a save" % [id, key])
	for id in before["people"]:
		check_eq(_canon(after["people"][id].get("office_history", null)),
			_canon(before["people"][id].get("office_history", null)), "office history survives a save")

	# A save from before offices: none of it written down. The world carries on
	# and fills its seats; rank is read from what there is.
	for org_id in GameState.organizations:
		var org: Organization = GameState.organizations[org_id]
		org.offices = {}
		org.hereditary_offices = {}
		org.office_lines = {}
		org.heir_houses = []
		org.merits = []
		org.blemishes = []
		org.uji_chief_id = &""
	for person_id in GameState.people:
		GameState.people[person_id].office_history = []
	check(SaveManager.save_game(SLOT), "saving an old-style world")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading an old-style world")
	_advance_to_settled(SimClock.current_tick + 8)
	var filled := 0
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		filled += polity.offices.size()
	check_gt(float(filled), 0.0, "an old world fills its seats once it runs again")
	SaveManager.delete_save(SLOT)


## The same value written the same way whatever order its keys were read in.
func _canon(value) -> String:
	return JSON.stringify(value, "", true)


func _check_determinism() -> void:
	var lines: Array[String] = []
	for attempt in 2:
		SimTestHarness.fresh_world(8801)
		SimTestHarness.advance(2400)
		var parts: Array[String] = []
		for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false):
			parts.append(str(polity.offices) + str(polity.hereditary_offices) + str(polity.heir_houses))
		lines.append("|".join(parts))
	check_eq(lines[1], lines[0], "the same world fills the same seats")
