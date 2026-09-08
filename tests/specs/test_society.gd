extends Spec

## Regions, forms of government, and how the houses regard one another.

func run() -> void:
	_check_regions_have_industry_and_standing()
	_check_government_form_is_derived()
	_check_form_follows_the_balance_of_power()
	_check_house_relations_are_mutual_and_varied()
	_check_renaming()
	finish()


func _check_regions_have_industry_and_standing() -> void:
	SimTestHarness.fresh_world(5001)
	SimTestHarness.advance(400)
	var industries := {}
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		check(Industry.ALL.has(s.industry), "%s has an unknown industry" % s.display_name)
		industries[s.industry] = true
		check(s.dominant_guild_id != &"",
			"%s should have a guild carrying weight there" % s.display_name)
		var lord := RegionalStanding.local_ruler(id)
		check(not lord.is_empty(), "%s should have a house holding it" % s.display_name)
		check(not String(lord.get("title", "")).is_empty(),
			"%s's lord should have a title" % s.display_name)
	check_gt(float(industries.size()), 2.0,
		"a world should not be eight regions of the same industry")


func _check_government_form_is_derived() -> void:
	SimTestHarness.fresh_world(5002)
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var form := PolityFormEvaluator.form_of(polity)
		check(form != null, "%s should have a form of government" % polity.display_name)
		if form == null:
			continue
		check(not form.display_name.is_empty(), "the form should have a name")
		check_eq(polity.leadership_title, form.ruler_title,
			"the head of state should carry the title the form uses")


## The form is read off the balance of power, so changing that balance changes
## the form — this is what makes factions and polities mean something together.
func _check_form_follows_the_balance_of_power() -> void:
	SimTestHarness.fresh_world(5003)
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	var before := PolityFormEvaluator.evaluate(polity)

	# A temple that outweighs every other faction should produce a theocracy,
	# without anything anywhere naming one.
	var temple := Organization.new()
	temple.org_id = &"probe_temple"
	temple.kind = Organization.OrgKind.FACTION
	temple.archetype_id = &"temple_faction"
	temple.display_name = "試みの神殿派"
	temple.ideology = PoliticalSystemAxes.new()
	temple.power_score = 99.0
	GameState.organizations[temple.org_id] = temple
	for other in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		if other.org_id != temple.org_id:
			other.power_score = 1.0

	var after := PolityFormEvaluator.evaluate(polity)
	check(after != null and after.form_id == &"theocracy",
		"a dominant temple faction should make the country a theocracy (got %s)"
			% (after.display_name if after != null else "nothing"))
	check(before == null or before.form_id != after.form_id,
		"the form should have changed when the balance of power did")


func _check_house_relations_are_mutual_and_varied() -> void:
	SimTestHarness.eventful_world(5004, 3000)
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)
	if houses.size() < 2:
		check(false, "the run should still have several houses standing")
		return

	var lowest := INF
	var highest := -INF
	for a in houses:
		for b in houses:
			if a.org_id == b.org_id:
				continue
			var value := HouseRelations.relation(a.org_id, b.org_id)
			check(value >= -1.0 and value <= 1.0,
				"%s regards %s at %f, outside the allowed range"
					% [a.display_name, b.display_name, value])
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
			check(not HouseRelations.describe(value).is_empty(),
				"every standing should have a word for it")
	check_gt(highest - lowest, 0.15,
		"the houses should not all regard each other identically")


func _check_renaming() -> void:
	SimTestHarness.fresh_world(5005)
	var settlement_id := &""
	for id in GameState.world.settlements:
		settlement_id = id
		break
	check(NamingService.rename_settlement(settlement_id, "新しい港"),
		"renaming a settlement should succeed")
	check_eq(GameState.world.settlements[settlement_id].display_name, "新しい港",
		"the settlement should carry its new name")

	var house := GameState.root_of_kind(Organization.OrgKind.HOUSE)
	var members := GameState.house_members(house.org_id)
	check_gt(float(members.size()), 0.0, "the house should have members to rename")
	check(NamingService.rename_organization(house.org_id, "改名"),
		"renaming a house should succeed")
	check_eq(house.display_name, "改名家", "a house name should keep its suffix")
	for member in GameState.house_members(house.org_id):
		check_eq(member.family_name, "改名",
			"%s should have taken the house's new name" % member.full_name)

	check(not NamingService.rename_settlement(settlement_id, "   "),
		"an empty name should be refused")
