extends Spec

## 氏: only the great houses of the first day found one, every other family
## carries the 氏 of the house it came out of, and nothing ever changes it.

const SLOT := 8


func run() -> void:
	_check_founding()
	_check_names()
	_check_long_run()
	_check_rename()
	_check_round_trip_and_migration()
	finish()


func _founding_nobles() -> Array[Organization]:
	var out: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		if house.founding_tick == 0 and house.standing == Organization.Standing.NOBLE \
				and house.liege_house_id == &"":
			out.append(house)
	return out


func _check_founding() -> void:
	SimTestHarness.fresh_world(5101)
	var founders := HouseNaming.all_uji()
	check_eq(founders.size(), WorldGenerator.SETTLEMENT_COUNT,
		"every great house of the first day founds a 氏, and nobody else does")
	for house in _founding_nobles():
		check(HouseNaming.founded_uji(house), "%s should found its own 氏" % house.display_name)
		check_eq(HouseNaming.uji_label(house.org_id),
			HouseNaming.surname_of_name(house.display_name) + "氏",
			"a 氏 is named for the house that founded it")
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		var liege := GameState.get_organization(house.liege_house_id)
		check(liege != null and house.uji_id == liege.uji_id,
			"%s serves %s and should go by its 氏" % [house.display_name,
				liege.display_name if liege != null else "?"])
		check(not HouseNaming.founded_uji(house), "a household in service founds no 氏")


func _check_names() -> void:
	SimTestHarness.fresh_world(5102)
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		var house := GameState.get_organization(p.house_org_id)
		if house == null:
			continue
		var surname := HouseNaming.surname_of_name(house.display_name)
		if HouseNaming.founded_uji(house):
			check_eq(p.full_name, "%s・%s" % [surname, p.given_name],
				"somebody of the house that founded the 氏 goes by its name alone")
			check_eq(house.formal_name(), house.display_name, "the founding house is just ネシ家")
		else:
			var uji := HouseNaming.uji_surname(house.uji_id)
			check_eq(p.full_name, "%s氏%s・%s" % [uji, surname, p.given_name],
				"everyone else goes by 氏 and house")
			check_eq(p.short_name, "%s・%s" % [surname, p.given_name],
				"the short form drops the 氏")
			check_eq(house.formal_name(), "%s氏%s" % [uji, house.display_name],
				"a house of another's 氏 is written ネシ氏コド家")


func _check_long_run() -> void:
	SimTestHarness.eventful_world(5103, 5000)
	var first := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		first[house.org_id] = house.uji_id
	SimTestHarness.advance(3000)

	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false)
	var founders := 0
	var branches := 0
	for house in houses:
		check(house.uji_id != &"", "%s should have a 氏" % house.display_name)
		check(GameState.get_organization(house.uji_id) != null,
			"the 氏 of %s should name a house that exists" % house.display_name)
		if HouseNaming.founded_uji(house):
			founders += 1
		if first.has(house.org_id):
			check_eq(house.uji_id, first[house.org_id],
				"the 氏 of %s must never change" % house.display_name)
		var parent := GameState.get_organization(house.parent_org_id)
		if house.founding_tick > 0 and parent != null:
			branches += 1
			check_eq(house.uji_id, parent.uji_id,
				"%s should carry the 氏 of %s, which it came out of"
					% [house.display_name, parent.display_name])
	check_eq(founders, WorldGenerator.SETTLEMENT_COUNT,
		"after eight thousand ticks there are still exactly as many 氏 as great houses of the first day")
	check_gt(float(branches), 0.0, "the run should have produced some cadet houses to check")


func _check_rename() -> void:
	SimTestHarness.fresh_world(5104)
	var founder: Organization = null
	for house in _founding_nobles():
		if HouseNaming.houses_of_uji(house.org_id).size() > 1:
			founder = house
			break
	check(founder != null, "a 氏 with households under it")
	if founder == null:
		return
	var kin: Organization = null
	for house in HouseNaming.houses_of_uji(founder.org_id):
		if house.org_id != founder.org_id:
			kin = house
			break
	var kin_member: NotableIndividual = GameState.house_members(kin.org_id)[0]
	var kin_surname := HouseNaming.surname_of_name(kin.display_name)

	check(NamingService.rename_organization(founder.org_id, "アマツ"), "renaming the founding house")
	check_eq(HouseNaming.uji_label(founder.org_id), "アマツ氏", "the 氏 follows the house it is named for")
	check_eq(kin.formal_name(), "アマツ氏%s家" % kin_surname,
		"every house of the 氏 is written with the new name")
	check_eq(kin_member.full_name, "アマツ氏%s・%s" % [kin_surname, kin_member.given_name],
		"and so is everyone in it")

	check(NamingService.rename_organization(kin.org_id, "ハタ"), "renaming a house of the 氏")
	check_eq(kin.formal_name(), "アマツ氏ハタ家", "only its own part of the name changes")
	check_eq(kin.uji_id, founder.org_id, "renaming does not change the 氏")
	check_eq(kin_member.full_name, "アマツ氏ハタ・%s" % kin_member.given_name, "its people follow")


func _check_round_trip_and_migration() -> void:
	SimTestHarness.eventful_world(5105, 3000)
	var expected := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		expected[house.org_id] = house.uji_id

	check(SaveManager.save_game(SLOT), "saving")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading")
	for id in expected:
		var house := GameState.get_organization(id)
		check(house != null and house.uji_id == expected[id], "the 氏 survives a save")

	# A save from before 氏: nothing in the snapshot, nothing in the record.
	_strip_uji()
	check(SaveManager.save_game(SLOT), "saving an old-style world")
	WorldGenerator.generate(1)
	check(SaveManager.load_game(SLOT), "loading an old-style world")
	for id in expected:
		var house := GameState.get_organization(id)
		check(house != null and house.uji_id == expected[id],
			"an old save is given the same 氏 the world would have given (%s)" % id)

	# And one whose record has nothing to say: the great houses are found by
	# the order they were made in.
	_strip_uji()
	HistoryLog.backbone.clear()
	check_eq(HouseNaming.migrate_uji(), expected.size(), "every house is given a 氏")
	for id in expected:
		check_eq(GameState.get_organization(id).uji_id, expected[id],
			"without a record, the 氏 still comes out the same (%s)" % id)
	SaveManager.delete_save(SLOT)


func _strip_uji() -> void:
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		house.uji_id = &""
	for log in [HistoryLog.buffer, HistoryLog.backbone]:
		for e in log:
			var org = e.payload.get("organization")
			if org is Dictionary:
				org.erase("uji_id")
