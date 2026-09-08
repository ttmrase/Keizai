class_name WorldGenerator
extends RefCounted

## Seeds a new world: a handful of settlements, and exactly one root organization
## of each kind with its founding generation.
##
## Only four institutions exist at the start — one guild, one house, one faction,
## one political system. Every specialised institution the world later needs (a
## monster-hunting order, a merchants' guild, a temple) is *invented* by the
## civilization itself, as a branch of one of these four, when conditions call
## for it. That is what keeps the promise that every lineage traces back to a
## single origin, and it is also the point of the game: the player never founds
## anything, they only make the world that makes founding necessary.

const SETTLEMENT_COUNT := 5

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

	var house_id := _create_house()
	var polity_id := _create_polity(house_id)
	_create_guild()
	_create_faction()

	# One resource step so the world has believable numbers before the first tick.
	GameState.step_resources(0)
	PowerCalculator.recalculate_all(0)
	EventBus.world_reset.emit()


static func _create_settlements() -> void:
	var rng := RngService.stream(&"worldgen")
	for i in SETTLEMENT_COUNT:
		var s := SettlementState.new()
		s.id = StringName("stl_%02d" % (i + 1))
		s.display_name = NameGenerator.place_name()
		s.population = rng.randf_range(320.0, 780.0)
		s.food_stock = s.population * 0.5
		s.local_ore = rng.randf_range(20.0, 90.0)
		s.local_wood = rng.randf_range(20.0, 90.0)
		s.wealth = rng.randf_range(60.0, 180.0)
		s.position = Vector2(rng.randf_range(0.12, 0.88), rng.randf_range(0.14, 0.86))
		GameState.world.settlements[s.id] = s


static func _create_house() -> StringName:
	var rng := RngService.stream(&"worldgen")
	var house_id := GameState.mint_org_id()
	var seat: SettlementState = _settlement_at(0)

	var house := Organization.new()
	house.org_id = house_id
	house.kind = Organization.OrgKind.HOUSE
	house.archetype_id = ROOT_HOUSE
	house.dynasty_seat_settlement_id = seat.id
	house.leadership_title = "当主"
	house.member_count = 6
	house.resources = {&"gold": 400.0}
	house.ideology = PoliticalSystemGenerator.generate_root_axes()
	house.ideology_baseline = house.ideology.clone()
	var named := PoliticalSystemGenerator.name_and_describe(house)
	house.display_name = named["display_name"]
	house.description = named["description"]

	var family_name: String = house.display_name.trim_suffix("家")

	# The founding couple, born before the chronicle proper begins.
	var monarch := _make_founder(family_name, "m", 38, house_id, rng)
	var consort := _make_founder(family_name, "f", 35, house_id, rng)
	_record_founder_birth(monarch)
	_record_founder_birth(consort)
	HistoryLog.emit_event(
		HistoryEvent.EventType.MARRIAGE,
		-4,
		"%sと%sが婚姻を結んだ。" % [monarch.full_name, consort.full_name],
		{}, &"", &"", &"", [monarch.person_id, consort.person_id] as Array[StringName])

	# Two heirs, so the very first succession already has something to argue about.
	for i in 2:
		var heir := _make_founder(family_name, "f" if i == 1 else "m",
			rng.randi_range(12, 19), house_id, rng)
		heir.is_founder_generation = false
		heir.father_id = monarch.person_id
		heir.mother_id = consort.person_id
		_record_founder_birth(heir)

	house.leader_person_id = monarch.person_id
	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"%sが%sに興った。" % [house.display_name, seat.display_name],
		{"organization": house.to_dict()},
		house.org_id, monarch.person_id)
	return house_id


static func _create_polity(house_id: StringName) -> StringName:
	var house := GameState.get_organization(house_id)
	var polity := Organization.new()
	polity.org_id = GameState.mint_org_id()
	polity.kind = Organization.OrgKind.POLITICAL_SYSTEM
	polity.archetype_id = ROOT_POLITY
	polity.leadership_title = "君主"
	polity.member_count = 40
	polity.legitimacy = 0.8
	polity.resources = {&"gold": 900.0}
	polity.ideology = house.ideology.clone()
	polity.ideology_baseline = polity.ideology.clone()
	polity.leader_person_id = house.leader_person_id
	for id in GameState.world.settlements:
		polity.governs_settlement_ids.append(id)
		GameState.world.settlements[id].controlling_org_id = polity.org_id

	var named := PoliticalSystemGenerator.name_and_describe(polity)
	polity.display_name = named["display_name"]
	polity.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"%sのもと、%sが全土を治めることとなった。" % [house.display_name, polity.display_name],
		{"organization": polity.to_dict()},
		polity.org_id, polity.leader_person_id)
	return polity.org_id


static func _create_guild() -> StringName:
	var rng := RngService.stream(&"worldgen")
	var guild_id := GameState.mint_org_id()
	var master := _make_founder(NameGenerator.family_stem(), "f" if rng.randf() < 0.5 else "m",
		45, &"", rng)
	_record_founder_birth(master)

	var guild := Organization.new()
	guild.org_id = guild_id
	guild.kind = Organization.OrgKind.GUILD
	guild.archetype_id = ROOT_GUILD
	guild.dynasty_seat_settlement_id = _settlement_at(1).id
	guild.leadership_title = "組合長"
	guild.member_count = 120
	guild.resources = {&"gold": 260.0}
	guild.ideology = PoliticalSystemGenerator.generate_root_axes()
	guild.ideology_baseline = guild.ideology.clone()
	guild.leader_person_id = master.person_id
	var named := PoliticalSystemGenerator.name_and_describe(guild)
	guild.display_name = named["display_name"]
	guild.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"働き手たちが%sを結成した。" % guild.display_name,
		{"organization": guild.to_dict()},
		guild.org_id, master.person_id)
	return guild_id


static func _create_faction() -> StringName:
	var rng := RngService.stream(&"worldgen")
	var faction_id := GameState.mint_org_id()
	var speaker := _make_founder(NameGenerator.family_stem(), "f" if rng.randf() < 0.5 else "m",
		41, &"", rng)
	_record_founder_birth(speaker)

	var faction := Organization.new()
	faction.org_id = faction_id
	faction.kind = Organization.OrgKind.FACTION
	faction.archetype_id = ROOT_FACTION
	faction.dynasty_seat_settlement_id = _settlement_at(2).id
	faction.leadership_title = "代表"
	faction.member_count = 200
	faction.cause_tags = [&"commons"]
	faction.resources = {&"gold": 90.0}
	faction.ideology = PoliticalSystemGenerator.generate_root_axes()
	faction.ideology_baseline = faction.ideology.clone()
	faction.leader_person_id = speaker.person_id
	var named := PoliticalSystemGenerator.name_and_describe(faction)
	faction.display_name = named["display_name"]
	faction.description = named["description"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.FOUNDING,
		0,
		"民の声をまとめる%sが生まれた。" % faction.display_name,
		{"organization": faction.to_dict()},
		faction.org_id, speaker.person_id)
	return faction_id


# ------------------------------------------------------------------ helpers

static func _settlement_at(index: int) -> SettlementState:
	var keys := GameState.world.settlements.keys()
	return GameState.world.settlements[keys[index % keys.size()]]


static func _make_founder(family_name: String, sex: String, age_years: int,
		house_id: StringName, rng: RandomNumberGenerator) -> NotableIndividual:
	var p := NotableIndividual.new()
	p.person_id = GameState.mint_person_id()
	p.sex = sex
	p.family_name = family_name
	p.full_name = "%s・%s" % [family_name, NameGenerator.given_name(sex)]
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
