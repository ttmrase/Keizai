extends Spec

## 戦争: a country that splits instead of falling, the war that follows, and
## what its ending does to everyone in it.

const SLOT := 7


func run() -> void:
	_check_no_split_without_friends()
	_check_forced_wars()
	_check_mid_war_round_trip()
	_check_determinism()
	_check_long_run()
	finish()


# ------------------------------------------------------------------ helpers

## Every region belongs to exactly one living state, and that state lists it.
func _check_regions(context: String) -> void:
	var listed := {}
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		for id in polity.governs_settlement_ids:
			listed[id] = int(listed.get(id, 0)) + 1
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var holder := GameState.get_organization(s.controlling_org_id)
		check(holder != null and holder.is_active()
			and holder.kind == Organization.OrgKind.POLITICAL_SYSTEM,
			"%s: %s should answer to a living state" % [context, s.display_name])
		check_eq(int(listed.get(id, 0)), 1,
			"%s: %s should be listed by exactly one state" % [context, s.display_name])
		if holder != null:
			check(holder.governs_settlement_ids.has(id),
				"%s: the state %s answers to should list it" % [context, s.display_name])


func _check_one_root(context: String) -> void:
	var roots := 0
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM, false):
		if polity.is_root():
			roots += 1
		check(GenealogyValidator.traces_to_root(polity.org_id),
			"%s: %s should trace to the first state" % [context, polity.display_name])
	check_eq(roots, 1, "%s: states have one root" % context)


## Starts a war in a fresh world by dividing its state down the middle.
func _start_war(world_seed: int) -> WarState:
	SimTestHarness.fresh_world(world_seed)
	SimTestHarness.advance(400)
	var polity := HouseRank.dominant_realm()
	var claimant_org: Organization = null
	for faction in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if claimant_org == null or faction.power_score > claimant_org.power_score:
			claimant_org = faction
	var ids := polity.governs_settlement_ids.duplicate()
	var loyal: Array = []
	var rebel: Array = []
	for i in ids.size():
		(loyal if i < ids.size() / 2 else rebel).append(ids[i])
	var axis := {}
	for a in PoliticalSystemAxes.AXIS_NAMES:
		axis[String(a)] = claimant_org.ideology.get_axis(a)
	CivilWar.split_country(polity, {"org": claimant_org, "ground": "議会"},
		{"loyal": loyal, "rebel": rebel, "share": 0.5, "forced": false},
		PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		PoliticalSystemAxes.DecisionStructure.ASSEMBLY, {}, SimClock.current_tick)
	return CivilWar.wars()[0] if not CivilWar.wars().is_empty() else null


func _resolution_of(war_id: StringName) -> HistoryEvent:
	for e in HistoryLog.backbone:
		if e.event_type == HistoryEvent.EventType.CONFLICT_RESOLVED \
				and StringName(e.payload.get("war_id", "")) == war_id:
			return e
	return null


# ------------------------------------------------------------------- checks

## A regime with nobody left behind it falls whole, exactly as before.
func _check_no_split_without_friends() -> void:
	SimTestHarness.fresh_world(6101)
	SimTestHarness.advance(400)
	var polity := HouseRank.dominant_realm()
	polity.legitimacy = 0.0
	for id in GameState.world.settlements:
		GameState.world.settlements[id].unrest = 1.0
	var voice := SocialTies.largest_bloc(polity)
	check(voice != null, "a bloc to speak for the street")
	if voice == null:
		return
	var claimant := {"org": voice, "ground": "民衆", "hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY}
	var plan := CivilWar.plan_split(polity, claimant, SimClock.current_tick)
	check(not bool(plan.get("splits", true)),
		"a country all of whose regions are burning does not split (share %.2f)" % float(plan.get("share", 0.0)))
	var before := GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size()
	RegimeShift.force_overturn(polity, claimant, SimClock.current_tick)
	check(CivilWar.wars().is_empty(), "and no war follows")
	check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(), before,
		"the country falls whole: still one state")
	check(not polity.is_active() or polity.ideology.legitimacy_basis
		== PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"and the old regime is replaced as it always was")
	_check_regions("after a whole fall")


## Wars started on purpose in several worlds: they always end, the map always
## adds up, and the ending moves land, rank and seats.
func _check_forced_wars() -> void:
	var outcomes := {}
	for world_seed in [6201, 6202, 6203, 6204, 6205]:
		var war := _start_war(world_seed)
		check(war != null, "seed %d: the split should start a war" % world_seed)
		if war == null:
			continue
		var war_id := war.war_id
		_check_regions("seed %d at the split" % world_seed)
		_check_one_root("seed %d at the split" % world_seed)
		check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(), 2,
			"seed %d: two states stand where one stood" % world_seed)

		var honour_before := {}
		for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			honour_before[house.org_id] = house.honour
		var land_before := {}
		for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			land_before[house.org_id] = house.held_settlement_ids.size()

		var guard := 0
		while not CivilWar.wars().is_empty() and guard < (CivilWar.MAX_YEARS + 3) * 4:
			SimTestHarness.advance(4)
			guard += 4
			_check_regions("seed %d during the war" % world_seed)
		check(CivilWar.wars().is_empty(), "seed %d: the war must end" % world_seed)
		var ending := _resolution_of(war_id)
		check(ending != null, "seed %d: the ending is in the permanent record" % world_seed)
		if ending == null:
			continue
		var years := int(ending.payload.get("years", -1))
		check(years >= CivilWar.MIN_YEARS or int(ending.payload.get("battles", 0)) > 0
			or String(ending.payload.get("outcome", "")) != "peace",
			"seed %d: a peace takes at least the minimum years" % world_seed)
		check(years <= CivilWar.MAX_YEARS + 1, "seed %d: no war outlasts the limit" % world_seed)
		var outcome := String(ending.payload.get("outcome", ""))
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		_check_one_root("seed %d after the war" % world_seed)
		_check_regions("seed %d after the war" % world_seed)

		if outcome == "peace":
			check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(), 2,
				"seed %d: a peace leaves two states" % world_seed)
			continue
		check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(), 1,
			"seed %d: a victory leaves one state" % world_seed)
		var loser := GameState.get_organization(StringName(ending.payload.get("loser", "")))
		check(loser != null and not loser.is_active(), "seed %d: the losing state ends" % world_seed)
		var attainted: Array = ending.payload.get("attainted", [])
		check(not attainted.is_empty(), "seed %d: somebody answers for the losing cause" % world_seed)
		for raw_id in attainted:
			var house := GameState.get_organization(StringName(raw_id))
			if house == null or not house.is_active():
				continue
			check(house.honour < float(honour_before.get(house.org_id, 0.0)),
				"seed %d: %s, attainted, stands lower" % [world_seed, house.display_name])
			check(house.held_settlement_ids.size() == 0
				or house.held_settlement_ids.size() < int(land_before.get(house.org_id, 0)),
				"seed %d: %s, attainted, has lost its land" % [world_seed, house.display_name])
		for raw_id in ending.payload.get("rewarded", []):
			var house := GameState.get_organization(StringName(raw_id))
			if house != null:
				check(house.honour > float(honour_before.get(house.org_id, 0.0)) - 0.05,
					"seed %d: %s, rewarded, stands higher" % [world_seed, house.display_name])
		# The bodies that backed the losers carry it into their power and seats.
		PowerCalculator.recalculate_all(SimClock.current_tick)
		var marked := 0
		for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
			for org in GameState.organizations_of_kind(kind):
				if org.power_drivers.has(PowerCalculator.WAR_KEY):
					marked += 1
		check_gt(float(marked), 0.0, "seed %d: the war leaves its mark on the guilds and factions" % world_seed)
	print("    forced wars ended: %s" % [outcomes])


func _check_mid_war_round_trip() -> void:
	var war := _start_war(6301)
	check(war != null, "a war to save in the middle of")
	if war == null:
		return
	SimTestHarness.advance(12)
	if CivilWar.wars().is_empty():
		return
	var before := GameState.to_dict()
	var wars_before: Array = before["world"]["wars"]
	check(SaveManager.save_game(SLOT), "saving mid-war")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading mid-war")
	var after := GameState.to_dict()
	var wars_after: Array = after["world"]["wars"]
	check_eq(wars_after.size(), wars_before.size(), "the war survives a save")
	if wars_after.size() == wars_before.size() and not wars_after.is_empty():
		var a: Dictionary = wars_before[0]
		var b: Dictionary = wars_after[0]
		for key in ["war_id", "side_a", "side_b", "start_tick", "cause", "house_a", "house_b"]:
			check_eq(b[key], a[key], "war.%s survives a save" % key)
		for key in ["front", "exhaustion_a", "exhaustion_b"]:
			check_near(float(b[key]), float(a[key]), 0.0001, "war.%s survives a save" % key)
		check_eq((b["battles"] as Array).size(), (a["battles"] as Array).size(), "battles survive a save")
	# And it goes on to the same end either way.
	var guard := 0
	while not CivilWar.wars().is_empty() and guard < 200:
		SimTestHarness.advance(4)
		guard += 4
	check(CivilWar.wars().is_empty(), "a loaded war still ends")
	SaveManager.delete_save(SLOT)


func _check_determinism() -> void:
	var endings: Array[String] = []
	for attempt in 2:
		var war := _start_war(6401)
		if war == null:
			endings.append("none")
			continue
		var war_id := war.war_id
		var guard := 0
		while not CivilWar.wars().is_empty() and guard < 200:
			SimTestHarness.advance(4)
			guard += 4
		var ending := _resolution_of(war_id)
		endings.append("%d|%s" % [ending.tick, ending.description] if ending != null else "open")
	check_eq(endings[1], endings[0], "the same world fights the same war to the same end")


## A long hard world: whatever wars it has, the map always adds up, the state
## lineage keeps one root, and every war ends within the limit.
func _check_long_run() -> void:
	SimTestHarness.fresh_world(6501)
	var wars_seen := {}
	for round_index in 8:
		GodPowerAPI.set_monster_spawn_rate(2.4 if round_index % 2 == 0 else 0.6)
		GodPowerAPI.set_harvest_modifier(0.35 if round_index % 2 == 0 else 1.2)
		if round_index % 2 == 0:
			GodPowerAPI.trigger_disaster(&"plague", &"", 1.3)
		for step in 25:
			SimTestHarness.advance(40)
			_check_regions("long run")
			for war in CivilWar.wars():
				wars_seen[war.war_id] = war.start_tick
				check(war.years(SimClock.current_tick) <= CivilWar.MAX_YEARS + 1,
					"a war in the long run outlasted the limit")
				check(GameState.get_organization(war.side_a).is_active()
					and GameState.get_organization(war.side_b).is_active(),
					"both sides of a war under way are living states")
	_check_one_root("long run")
	for war_id in wars_seen:
		if CivilWar.war_of(war_id) == null and not CivilWar.wars().any(func(w): return w.war_id == war_id):
			check(_resolution_of(war_id) != null, "every war that ended says how")
	print("    long run: %d wars in %d years" % [wars_seen.size(), SimClock.year()])
