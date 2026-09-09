class_name WorldGenerator
extends RefCounted

## Seeds a new world.
##
## Every region gets a house, and those houses are the *only* source of people in
## the game. Nobody is ever conjured up later to fill a vacant post: every guild
## master, every faction speaker and every monarch for the rest of the world's
## history has to be somebody's child. That makes the family tree the real
## substrate of the simulation — if the houses stop marrying and having children,
## the institutions run out of people to lead them.
##
## Institutions themselves start minimal: one guild, one faction, one political
## system. Everything specialised — hunters, artisans, merchants, mages, temples,
## farmers' movements — is invented later as a branch, when the world makes it
## necessary.

const SETTLEMENT_COUNT := 8

const ROOT_GUILD := &"founders_guild"
const ROOT_HOUSE := &"crown_house"
const ROOT_FACTION := &"commons_faction"
const ROOT_POLITY := &"crown_political_system"


static func generate(world_seed: int) -> void:
	# The clock has to be at zero before anything reads it: leadership tenure
	# length feeds power scores, so generating a world while the clock still
	# holds the previous world's tick makes the same seed produce a different
	# starting state.
	SimClock.start(0)
	GameState.reset()
	HistoryLog.reset()
	RngService.configure(world_seed)
	ContentRegistry.ensure_loaded()

	GameState.world.seed = world_seed
	_create_settlements()
	var houses := _create_houses()
	_create_polity(houses)
	_create_guild(houses)
	_create_faction(houses)

	# One resource step so the world has believable numbers before the first tick.
	GameState.step_resources(0)
	PowerCalculator.recalculate_all(0)
	HouseRank.refresh_all(0)
	RegionalStanding.refresh_all(0)
	SocialTies.refresh_all(0)
	PolityFormEvaluator.refresh_all(0)
	HouseRelations.refresh_all(0)
	EventBus.world_reset.emit()


static func _create_settlements() -> void:
	var rng := RngService.stream(&"worldgen")
	var industries := Industry.assign_spread(SETTLEMENT_COUNT, rng)
	for i in SETTLEMENT_COUNT:
		var s := SettlementState.new()
		s.id = StringName("stl_%02d" % (i + 1))
		s.display_name = NameGenerator.place_name()
		s.industry = industries[i]
		s.population = rng.randf_range(320.0, 780.0)
		s.food_stock = s.population * 0.5
		s.local_ore = rng.randf_range(20.0, 90.0)
		s.local_wood = rng.randf_range(20.0, 90.0)
		s.wealth = rng.randf_range(60.0, 180.0)
		s.position = _spread_position(rng)
		GameState.world.settlements[s.id] = s


## Rejection-samples a spot away from the settlements already placed, so the map
## does not end up with two towns drawn on top of each other.
static func _spread_position(rng: RandomNumberGenerator) -> Vector2:
	var best := Vector2.ZERO
	var best_clearance := -1.0
	for attempt in 24:
		var candidate := Vector2(rng.randf_range(0.10, 0.90), rng.randf_range(0.08, 0.92))
		var clearance := INF
		for id in GameState.world.settlements:
			clearance = minf(clearance, candidate.distance_to(GameState.world.settlements[id].position))
		if clearance == INF:
			return candidate
		if clearance > best_clearance:
			best_clearance = clearance
			best = candidate
		if clearance > 0.24:
			return candidate
	return best


## One house per region, each holding its own seat. The first is the reigning
## house only because somebody has to be; the rest are its equals to begin with.
static func _create_houses() -> Array[Organization]:
	var rng := RngService.stream(&"worldgen")
	var houses: Array[Organization] = []
	var index := 0
	for settlement_id in GameState.world.settlements:
		var settlement: SettlementState = GameState.world.settlements[settlement_id]
		var house_id := GameState.mint_org_id()

		var house := Organization.new()
		house.org_id = house_id
		house.kind = Organization.OrgKind.HOUSE
		house.archetype_id = ROOT_HOUSE
		house.dynasty_seat_settlement_id = settlement_id
		house.held_settlement_ids = [settlement_id]
		house.leadership_title = "当主"
		house.member_count = 6
		house.resources = {&"gold": rng.randf_range(180.0, 460.0)}
		house.ideology = PoliticalSystemGenerator.generate_root_axes()
		house.ideology_baseline = house.ideology.clone()
		# Only the first house is a root; the others descend from it in the
		# lineage tree, because the invariant is one root per kind. They are
		# founded at the same moment, as branches of the same original line.
		if index > 0:
			house.parent_org_id = houses[0].org_id
		var named := PoliticalSystemGenerator.name_and_describe(house)
		house.display_name = named["display_name"]
		house.description = named["description"]

		var surname := HouseNaming.surname_of_name(house.display_name)
		var patriarch := _make_founder(surname, "m", rng.randi_range(36, 44), house_id, rng)
		var matriarch := _make_founder(surname, "f", rng.randi_range(33, 41), house_id, rng)
		_record_founder_birth(patriarch)
		_record_founder_birth(matriarch)
		HistoryLog.emit_event(
			HistoryEvent.EventType.MARRIAGE,
			-4,
			"%sと%sが婚姻を結んだ。" % [patriarch.full_name, matriarch.full_name],
			{}, &"", &"", &"",
			[patriarch.person_id, matriarch.person_id] as Array[StringName])

		# Heirs, so the first succession already has something to argue about,
		# and spare children who can be spared for a guild or a faction.
		for c in rng.randi_range(2, 3):
			var heir := _make_founder(surname, "f" if c % 2 == 1 else "m",
				rng.randi_range(10, 22), house_id, rng)
			heir.is_founder_generation = false
			heir.father_id = patriarch.person_id
			heir.mother_id = matriarch.person_id
			_record_founder_birth(heir)

		house.leader_person_id = patriarch.person_id
		settlement.ruling_house_id = house_id
		HistoryLog.emit_event(
			HistoryEvent.EventType.FOUNDING,
			0,
			"%sが%sに拠を構えた。" % [house.display_name, settlement.display_name],
			{"organization": house.to_dict()},
			house.org_id, patriarch.person_id)
		houses.append(GameState.get_organization(house_id))
		index += 1
	return houses


static func _create_polity(houses: Array[Organization]) -> StringName:
	var seat_house := houses[0]
	var polity := Organization.new()
	polity.org_id = GameState.mint_org_id()
	polity.kind = Organization.OrgKind.POLITICAL_SYSTEM
	polity.archetype_id = ROOT_POLITY
	polity.leadership_title = "君主"
	polity.member_count = 40
	polity.legitimacy = 0.8
	polity.resources = {&"gold": 900.0}
	polity.ideology = seat_house.ideology.clone()
	polity.ideology_baseline = polity.ideology.clone()
	polity.leader_person_id = seat_house.leader_person_id
	for id in GameState.world.settlements:
		polity.governs_settlement_ids.append(id)
		GameState.world.settlements[id].controlling_org_id = polity.org_id

	var named := PoliticalSystemGenerator.name_and_describe(polity)
	polity.display_name = named["display_name"]
	polity.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"%sのもと、諸家が%sとしてひとつに束ねられた。" % [seat_house.display_name, polity.display_name],
		{"organization": polity.to_dict()},
		polity.org_id, polity.leader_person_id)
	return polity.org_id


static func _create_guild(houses: Array[Organization]) -> StringName:
	var master := _spare_child(houses, 1)
	var guild := Organization.new()
	guild.org_id = GameState.mint_org_id()
	guild.kind = Organization.OrgKind.GUILD
	guild.archetype_id = ROOT_GUILD
	guild.dynasty_seat_settlement_id = houses[1 % houses.size()].dynasty_seat_settlement_id
	guild.leadership_title = "組合長"
	guild.member_count = 120
	guild.resources = {&"gold": 260.0}
	guild.ideology = PoliticalSystemGenerator.generate_root_axes()
	guild.ideology_baseline = guild.ideology.clone()
	guild.leader_person_id = master.person_id if master != null else &""
	var named := PoliticalSystemGenerator.name_and_describe(guild)
	guild.display_name = named["display_name"]
	guild.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"働き手たちが%sを結成した。" % guild.display_name,
		{"organization": guild.to_dict()},
		guild.org_id, guild.leader_person_id)
	return guild.org_id


static func _create_faction(houses: Array[Organization]) -> StringName:
	var speaker := _spare_child(houses, 2)
	var faction := Organization.new()
	faction.org_id = GameState.mint_org_id()
	faction.kind = Organization.OrgKind.FACTION
	faction.archetype_id = ROOT_FACTION
	faction.dynasty_seat_settlement_id = houses[2 % houses.size()].dynasty_seat_settlement_id
	faction.leadership_title = "代表"
	faction.member_count = 200
	faction.cause_tags = [&"commons"]
	faction.resources = {&"gold": 90.0}
	faction.ideology = PoliticalSystemGenerator.generate_root_axes()
	faction.ideology_baseline = faction.ideology.clone()
	faction.leader_person_id = speaker.person_id if speaker != null else &""
	var named := PoliticalSystemGenerator.name_and_describe(faction)
	faction.display_name = named["display_name"]
	faction.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"民の声をまとめる%sが生まれた。" % faction.display_name,
		{"organization": faction.to_dict()},
		faction.org_id, faction.leader_person_id)
	return faction.org_id


# ------------------------------------------------------------------ helpers

## A grown child of some house who is not already the head of one — the sort of
## person who goes off and runs a guild instead of waiting to inherit.
static func _spare_child(houses: Array[Organization], preferred_index: int) -> NotableIndividual:
	var order: Array[int] = []
	for i in houses.size():
		order.append((preferred_index + i) % houses.size())
	for i in order:
		for member in GameState.house_members(houses[i].org_id):
			if member.is_founder_generation or member.current_tenure() != null:
				continue
			if member.age_years(0) >= SimConfig.ADULT_AGE_YEARS:
				return member
	# Fall back to any adult at all rather than leaving the seat empty at turn one.
	for p in GameState.living_people():
		if p.current_tenure() == null and p.age_years(0) >= SimConfig.ADULT_AGE_YEARS:
			return p
	return null


static func _make_founder(surname: String, sex: String, age_years: int,
		house_id: StringName, rng: RandomNumberGenerator) -> NotableIndividual:
	var p := NotableIndividual.new()
	p.person_id = GameState.mint_person_id()
	p.sex = sex
	p.family_name = surname
	p.given_name = NameGenerator.given_name(sex)
	p.birth_tick = -age_years * SimConfig.TICKS_PER_YEAR
	p.house_org_id = house_id
	p.is_founder_generation = true
	p.personality_tags = Demography.roll_personality(rng)
	return p


static func _record_founder_birth(p: NotableIndividual) -> void:
	HistoryLog.emit_event(
		HistoryEvent.EventType.BIRTH,
		p.birth_tick,
		"%sが生まれた。" % p.full_name,
		{"person": p.to_dict()},
		&"", p.person_id)
