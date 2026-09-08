extends Spec

## The houses are the only source of people, and a surname is a house's name.

func run() -> void:
	_check_one_house_per_region()
	_check_nobody_is_created_from_nothing()
	_check_surnames_follow_houses()
	_check_house_heads_are_family()
	_check_marriage_joins_houses()
	finish()


func _check_one_house_per_region() -> void:
	SimTestHarness.fresh_world(4001)
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)
	check_eq(houses.size(), WorldGenerator.SETTLEMENT_COUNT,
		"the world should begin with one house per region")

	var seats := {}
	for house in houses:
		check(house.dynasty_seat_settlement_id != &"", "%s should hold a seat" % house.display_name)
		check(not seats.has(house.dynasty_seat_settlement_id),
			"two houses were seated in the same region")
		seats[house.dynasty_seat_settlement_id] = true

	for id in GameState.world.settlements:
		check(GameState.world.settlements[id].ruling_house_id != &"",
			"every region should have a house holding it at the start")


## The sharpest form of the rule: after world generation, nobody may enter the
## world except by being born to somebody already in it.
func _check_nobody_is_created_from_nothing() -> void:
	SimTestHarness.fresh_world(4002)
	var founders_at_start := _founder_count()
	check_gt(float(founders_at_start), 0.0, "the founding generation should exist")

	SimTestHarness.advance(3000)
	check_eq(_founder_count(), founders_at_start,
		"no new founding-generation person may appear after the world begins")

	# And everyone who does exist has a parent, unless they were there at the start.
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.is_founder_generation:
			continue
		check(p.father_id != &"" or p.mother_id != &"",
			"%s appeared with no parents and is not of the founding generation" % p.full_name)


func _founder_count() -> int:
	var n := 0
	for id in GameState.people:
		if GameState.people[id].is_founder_generation:
			n += 1
	return n


func _check_surnames_follow_houses() -> void:
	SimTestHarness.fresh_world(4003)
	SimTestHarness.advance(2000)
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		var house := GameState.get_organization(p.house_org_id)
		if house == null:
			continue
		check_eq(p.family_name, HouseNaming.surname_of_name(house.display_name),
			"%s carries a surname that is not their house's" % p.full_name)


func _check_house_heads_are_family() -> void:
	SimTestHarness.eventful_world(4004, 3000)
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		var head := GameState.get_current_leader(house.org_id)
		if head == null:
			continue
		check_eq(head.house_org_id, house.org_id,
			"%s is headed by %s, who belongs to another house"
				% [house.display_name, head.full_name])


## A bride joins her husband's house and takes its name — unless she heads a
## house of her own, in which case he joins hers.
func _check_marriage_joins_houses() -> void:
	SimTestHarness.fresh_world(4005)
	SimTestHarness.advance(1500)
	var couples := 0
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		var spouse := Demography.living_spouse(p)
		if spouse == null or not p.is_alive():
			continue
		couples += 1
		check_eq(p.house_org_id, spouse.house_org_id,
			"%s and %s are married but belong to different houses"
				% [p.full_name, spouse.full_name])
	check_gt(float(couples), 0.0, "some marriages should have happened by now")
