extends Spec

## Rank as something granted: the crown standing outside the order it hands out,
## a knighthood worth what the world says it is worth, and what becomes of people
## and households when the thing above them falls over.

func run() -> void:
	_check_the_crown_holds_no_title()
	_check_the_crown_raises_and_strips()
	_check_a_knighthood_is_worth_less_when_everyone_has_one()
	_check_a_masterless_house_finds_a_new_master()
	_check_a_household_with_nobody_to_serve_falls_out_of_service()
	_check_an_outcast_gets_a_fate()
	_check_whoever_married_in_never_takes_the_name()
	_check_a_deposed_ruler_is_not_the_obvious_successor()
	_check_a_house_knows_what_offices_it_holds()
	finish()


## The realm as a kingdom, so the questions about crowns have a crown to ask
## about. World generation does not promise one.
func _crown_the_realm() -> Organization:
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	if realm == null or realm.ideology == null:
		return null
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	var monarch := GameState.get_current_leader(realm.org_id)
	if monarch == null or monarch.house_org_id == &"":
		return null
	return GameState.get_organization(monarch.house_org_id)


func _check_the_crown_holds_no_title() -> void:
	SimTestHarness.fresh_world(9101)
	var royal := _crown_the_realm()
	check(royal != null, "a kingdom should have a family wearing the crown")
	if royal == null:
		return
	check_eq(HouseRank.royal_house_id(), royal.org_id, "and the world should know which")
	check_eq(HouseRank.title_of_house(royal), HouseRank.ROYAL_TITLE,
		"a royal house holds no county title while it holds a crown")

	# It stands above every rank it grants, and takes no place in the order.
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.org_id == royal.org_id or house.standing != Organization.Standing.NOBLE:
			continue
		check_gt(HouseRank.precedence(royal), HouseRank.precedence(house),
			"the crown outranks %s" % house.display_name)

	royal.rank_tier = 0
	royal.power_score = 500.0
	for i in 6:
		HouseRank.refresh_all(SimClock.current_tick)
	check_eq(royal.rank_tier, 0,
		"however strong it is, the crown is not ranked among the peers")

	# And once the crown is gone the family rejoins the peerage like anyone else.
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.ELECTED
	check_eq(HouseRank.royal_house_id(), &"", "an elected realm has no royal house")
	for i in 6:
		HouseRank.refresh_all(SimClock.current_tick)
	check_gt(float(royal.rank_tier), 0.0, "and the family it belonged to is titled again")


func _check_the_crown_raises_and_strips() -> void:
	SimTestHarness.fresh_world(9102)
	var royal := _crown_the_realm()
	check(royal != null, "a kingdom should have a family wearing the crown")
	if royal == null:
		return

	var friend: Organization = null
	var enemy: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.org_id == royal.org_id or house.standing != Organization.Standing.NOBLE:
			continue
		royal.house_relations[house.org_id] = 0.0
		if friend == null:
			friend = house
		elif enemy == null:
			enemy = house
	if friend == null or enemy == null:
		check(false, "the realm should have great houses besides the crown's")
		return

	# A crown with an enemy answers the enemy first.
	royal.house_relations[friend.org_id] = 0.8
	royal.house_relations[enemy.org_id] = -0.8
	Honours._crown_honours(SimClock.current_tick)
	check(enemy.honour < 0.0, "a house the crown has fallen out with is put down")
	check_eq(friend.honour, 0.0, "and the favour waits its turn")

	# With nobody left to answer, it rewards instead.
	royal.house_relations[enemy.org_id] = 0.1
	Honours._crown_honours(SimClock.current_tick + Honours.HOUSE_COOLDOWN)
	check_gt(friend.honour, 0.0, "a crown at peace confirms its friends")

	# An honour is worth something in the order of precedence, and the family
	# feels it toward the crown and nobody else.
	var warm := HouseRelations._target_relation(friend, royal, HouseRelations._gather(
		[friend, royal, enemy]))
	friend.honour = -1.0
	var cold := HouseRelations._target_relation(friend, royal, HouseRelations._gather(
		[friend, royal, enemy]))
	check_gt(warm - cold, 0.1, "a family raised by the crown thinks better of it")


func _check_a_knighthood_is_worth_less_when_everyone_has_one() -> void:
	SimTestHarness.fresh_world(9103)
	check_eq(HouseRank.service_bar_shift(), 0.0,
		"a world where nobody is knighted has no inflation to correct")

	var served := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		# Every liege in the world is generous at once, which is the case the
		# whole mechanism exists for.
		house.favour = 2.0
		served += 1
	check_gt(float(served), 3.0, "there should be households in service to knight")

	for i in 20:
		HouseRank.refresh_all(SimClock.current_tick)

	var total := 0.0
	var count := 0
	var top := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		total += float(house.rank_tier)
		count += 1
		if house.rank_tier >= HouseRank.SERVICE_TITLES.size() - 1:
			top += 1
	check_gt(float(count), 0.0, "the households in service should still be there")
	check_gt(HouseRank.service_bar_shift(), 0.0,
		"handing them out freely raises the bar for everyone")
	check_eq(top, 0, "and nobody reaches the top rung on a currency that cheap")
	check(total / float(count) < float(HouseRank.SERVICE_TITLES.size() - 1),
		"the ladder still has rungs above where the crowd stands")


func _check_a_masterless_house_finds_a_new_master() -> void:
	SimTestHarness.fresh_world(9104)
	var house: Organization = null
	for candidate in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if candidate.standing == Organization.Standing.RETAINER:
			house = candidate
			break
	check(house != null, "the world should have households in service")
	if house == null:
		return
	var liege := GameState.get_organization(house.liege_house_id)
	check(liege != null, "and they should be serving somebody")
	if liege == null:
		return

	# The county passes to another family, so there is no vacancy for this
	# household to claim and the only question left is who it now serves.
	var heir: Organization = null
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.org_id != liege.org_id and other.standing == Organization.Standing.NOBLE:
			heir = other
			break
	for settlement_id in liege.held_settlement_ids.duplicate():
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s != null and heir != null:
			s.ruling_house_id = heir.org_id
			heir.held_settlement_ids.append(settlement_id)
	liege.held_settlement_ids.clear()
	liege.dissolved_tick = SimClock.current_tick

	var fate := Aftermath.settle_masterless(house, SimClock.current_tick)
	check_eq(fate, Aftermath.CHANGED_LIEGE, "a household with no master finds one")
	var successor := GameState.get_organization(house.liege_house_id)
	check(successor != null and successor.is_active(),
		"and the new master is a family that actually exists")
	if successor != null:
		check_eq(successor.standing, Organization.Standing.NOBLE,
			"a household in service serves a great house")
		check(successor.org_id != liege.org_id, "not the one that just died out")
	check(house.loyalty <= 0.45,
		"a household handed on rather than sworn starts cool about it")


func _check_a_household_with_nobody_to_serve_falls_out_of_service() -> void:
	SimTestHarness.fresh_world(9105)
	var house: Organization = null
	for candidate in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if candidate.standing == Organization.Standing.RETAINER:
			house = candidate
			break
	if house == null:
		check(false, "the world should have households in service")
		return

	# No nobility left anywhere: the rank they belong to has nothing above it.
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.standing == Organization.Standing.NOBLE:
			other.dissolved_tick = SimClock.current_tick

	var fate := Aftermath.settle_masterless(house, SimClock.current_tick)
	check_eq(fate, Aftermath.MASTERLESS, "with no master to be had, service ends")
	check_eq(house.standing, Organization.Standing.COMMONER,
		"and the household goes back among the people")
	check_eq(house.rank_tier, 0, "carrying no rank out with it")
	check_eq(HouseRank.precedence(house), 0.0, "and standing nowhere in the order")


func _check_an_outcast_gets_a_fate() -> void:
	SimTestHarness.eventful_world(9106, 900)
	var settled := 0
	var known := [Aftermath.TAKEN_IN, Aftermath.MARRIED_AWAY, Aftermath.NEW_HOUSE,
		Aftermath.COMMONER]
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if settled >= 3:
			break
		for member in GameState.house_members(house.org_id):
			if member.person_id == house.leader_person_id or not member.is_adult(
					SimClock.current_tick):
				continue
			var fate := Aftermath.settle_outcast(member, house, &"disinheritance",
				SimClock.current_tick)
			check(known.has(fate),
				"%s should end up somewhere nameable, not nowhere" % member.full_name)
			check_eq(member.fate, fate, "and carry it afterwards")
			check_eq(member.fate_tick, SimClock.current_tick, "with the year it happened")
			if fate == Aftermath.COMMONER:
				check_eq(member.house_org_id, &"", "somebody cast down holds no house")
			else:
				check(member.house_org_id != &"" or fate == Aftermath.MARRIED_AWAY,
					"and anyone else has somewhere to be")
			settled += 1
			break
	check_gt(float(settled), 0.0, "the record should have had somebody to cast out")

	# Whatever happened to them, the world still hangs together.
	for id in GameState.people:
		check(GenealogyValidator.trace_to_founder(id),
			"a life that changed houses still traces to the founding cohort")


## Somebody who married in belongs to the household and carries its name. What
## they never do is inherit it, or take it away from the partner it came from.
func _check_whoever_married_in_never_takes_the_name() -> void:
	SimTestHarness.eventful_world(9107, 1500)
	var outsiders := 0
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		var house := GameState.get_organization(p.house_org_id)
		if house != null and not HouseNaming.is_of_the_blood(p, house):
			outsiders += 1
	check_gt(float(outsiders), 0.0, "houses should have taken people in by now")

	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		var head := GameState.get_person(house.leader_person_id)
		if head == null:
			continue
		check(HouseNaming.is_of_the_blood(head, house),
			"%s is headed by its own blood, not by somebody who married in"
				% house.display_name)

	# A daughter who married away and came home widowed is still of the blood she
	# was born to, whatever name she is carrying at the moment.
	var returned := 0
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.birth_house_org_id == &"" or p.house_org_id != p.birth_house_org_id:
			continue
		var home := GameState.get_organization(p.house_org_id)
		if home == null:
			continue
		check(HouseNaming.is_of_the_blood(p, home),
			"%s was born to the house they are living in" % p.full_name)
		returned += 1
	check_gt(float(returned), 0.0, "most people live in the house they were born to")

	# And every cadet house was founded by somebody born to the family it left.
	# Read off the founding event rather than off the founder as they are now:
	# a life goes on after founding a house, and may be taken into another one.
	var branches := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		if house.parent_org_id == &"" or house.origin_event_id == &"":
			continue
		var origin := HistoryLog.find_event(house.origin_event_id)
		if origin == null or origin.event_type != HistoryEvent.EventType.SCHISM:
			continue
		branches += 1
		check(not bool(origin.payload.get("founder_married_in", false)),
			"%s was founded by the family's own blood, not by somebody who married in"
				% house.display_name)
	check_gt(float(branches), 0.0, "the centuries should have produced cadet houses")


func _check_a_deposed_ruler_is_not_the_obvious_successor() -> void:
	SimTestHarness.fresh_world(9108)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	var monarch := GameState.get_current_leader(realm.org_id)
	check(monarch != null, "the realm should have somebody at its head")
	if monarch == null:
		return

	var tick := SimClock.current_tick
	var untainted := SuccessionResolver._claim_weight(monarch, realm, tick, null)
	monarch.deposed_from.append(realm.org_id)
	var tainted := SuccessionResolver._claim_weight(monarch, realm, tick, null)
	check_gt(untainted - tainted, 0.0, "the order that deposed somebody remembers it")
	check(tainted < untainted * 0.4,
		"a deposed head is a poor candidate for the seat that deposed them")
	check_gt(tainted, 0.0,
		"but not barred — a country that cannot govern without its king has happened")


func _check_a_house_knows_what_offices_it_holds() -> void:
	SimTestHarness.eventful_world(9109, 800)
	var found := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		for seat in GameState.offices_of_house(house.org_id):
			var org: Organization = seat["org"]
			var holder: NotableIndividual = seat["person"]
			check(org.kind != Organization.OrgKind.HOUSE,
				"a family's own headship is not one of the offices it holds")
			check(org.is_active(), "and a dissolved body holds nobody")
			check_eq(holder.house_org_id, house.org_id,
				"the holder should belong to the house the seat is listed under")
			check_eq(org.leader_person_id, holder.person_id,
				"and should actually be the one holding it")
			found += 1
	check_gt(float(found), 0.0, "somebody's family should be running something by now")
