extends Spec

## The wiring between the four kinds of institution, and what it makes possible:
## a family owning a guild, a chamber dividing, a peerage that counts in one
## century and not the next, a regime being taken, and a politics nobody in the
## world had heard of.

func run() -> void:
	_check_support_base_follows_belief()
	_check_the_chamber_divides()
	_check_a_family_can_own_an_office()
	_check_rank_is_a_pyramid()
	_check_rank_counts_where_it_counts()
	_check_land_leans()
	_check_a_regime_can_actually_fall()
	_check_crisis_produces_new_politics()
	_check_everyone_appears_once_in_the_family_chart()
	finish()


func _check_support_base_follows_belief() -> void:
	SimTestHarness.fresh_world(7101)
	SimTestHarness.advance(600)

	var backed := 0
	for org in GameState.organizations_of_kind(Organization.OrgKind.FACTION):
		for backer_id in org.support_base:
			var strength: float = org.support_base[backer_id]
			check(strength > 0.0 and strength <= 1.0,
				"%s is backed by %s at %f, outside 0..1"
					% [org.display_name, backer_id, strength])
			check(GameState.get_organization(backer_id) != null,
				"%s is backed by something that does not exist" % org.display_name)
			backed += 1
	check_gt(float(backed), 0.0, "factions should have somebody standing behind them")

	# The tie is read off belief, so moving a house's beliefs moves the tie.
	var faction := GameState.organizations_of_kind(Organization.OrgKind.FACTION)[0]
	var house := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)[0]
	for axis in PoliticalSystemAxes.AXIS_NAMES:
		house.ideology.set_axis(axis, faction.ideology.get_axis(axis))
	SocialTies.refresh_all(SimClock.current_tick)
	var aligned: float = faction.support_base.get(house.org_id, 0.0)

	for axis in PoliticalSystemAxes.AXIS_NAMES:
		house.ideology.set_axis(axis, -faction.ideology.get_axis(axis))
	SocialTies.refresh_all(SimClock.current_tick)
	var opposed: float = faction.support_base.get(house.org_id, 0.0)
	check_gt(aligned - opposed, 0.05,
		"a house that believes what a faction believes should back it more than one that does not")


func _check_the_chamber_divides() -> void:
	SimTestHarness.eventful_world(7102, 900)
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var form := PolityFormEvaluator.form_of(polity)
		check(form != null, "%s should have a form" % polity.display_name)
		if form == null:
			continue
		check_eq(polity.seat_total, form.chamber_seats,
			"%s should seat as many as its form does" % polity.display_name)

		var given := 0
		for id in polity.faction_seats:
			var seats: int = polity.faction_seats[id]
			check_gt(float(seats), 0.0, "a faction listed in the chamber should hold seats")
			check(GameState.get_organization(id) != null,
				"%s seats a faction that does not exist" % polity.display_name)
			given += seats
		if not polity.faction_seats.is_empty():
			check_eq(given, polity.seat_total,
				"%s should hand out every seat it has" % polity.display_name)


## A guild whose masters keep coming from one family becomes that family's, and
## then fills its next vacancy from that family — the loop the design was missing.
func _check_a_family_can_own_an_office() -> void:
	SimTestHarness.fresh_world(7103)
	var guild := GameState.root_of_kind(Organization.OrgKind.GUILD)
	var house := GameState.root_of_kind(Organization.OrgKind.HOUSE)

	# Hand the guild a long history of masters from one house.
	var planted := 0
	for member in GameState.house_members(house.org_id):
		var tenure := RoleTenure.new()
		tenure.org_id = guild.org_id
		tenure.title = guild.leadership_title
		tenure.start_tick = 0
		tenure.end_tick = SocialTies.PATRON_MIN_TENURE_TICKS * 2
		member.role_history.append(tenure)
		planted += 1
		if planted >= 2:
			break
	check_gt(float(planted), 0.0, "the house should have members to plant a history with")

	SocialTies.refresh_all(SimClock.current_tick)
	check_eq(guild.patron_house_id, house.org_id,
		"a guild led by one family for its whole history should belong to that family")

	# And an owned office drifts to admitting it is hereditary.
	guild.ideology.set_axis(&"tradition_reform", -0.9)
	SocialTies.refresh_all(SimClock.current_tick)
	check_eq(SocialTies.office_basis(guild), SocialTies.OfficeBasis.HEREDITARY,
		"an office one family owns should end up filled by inheritance")
	check_eq(SocialTies.office_basis_label(guild), "世襲制",
		"and should say so")

	# A body with no owning family fills its seats some other way.
	var faction := GameState.root_of_kind(Organization.OrgKind.FACTION)
	faction.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC
	check_eq(SocialTies.office_basis_label(faction), "実力制",
		"a body that chooses on merit should say that instead")


func _check_rank_is_a_pyramid() -> void:
	SimTestHarness.eventful_world(7104, 1400)
	var tiers := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		check(house.rank_tier >= 0 and house.rank_tier < HouseRank.TIER_NAMES.size(),
			"%s stands at tier %d, outside the peerage" % [house.display_name, house.rank_tier])
		tiers[house.rank_tier] = int(tiers.get(house.rank_tier, 0)) + 1
		check(not HouseRank.tier_name(house.rank_tier).is_empty(),
			"every tier should have a name")
	check(int(tiers.get(4, 0)) <= 1, "a country has room for one duke, not several")
	check(int(tiers.get(3, 0)) <= 2, "and for two marquesses at the outside")


## The same family name is worth a great deal under a crown and almost nothing
## under an assembly. That is the whole point of weighting it.
func _check_rank_counts_where_it_counts() -> void:
	SimTestHarness.fresh_world(7105)
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)

	polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	polity.polity_form_id = &"feudal_kingdom"
	var under_crown := HouseRank.regard_in_realm(polity)

	polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.ELECTED
	polity.polity_form_id = &"popular_republic"
	var under_assembly := HouseRank.regard_in_realm(polity)

	check_gt(under_crown - under_assembly, 0.4,
		"pedigree should count for far more under a crown than under an assembly")

	# And the same split runs through the guilds.
	var merchants := ContentRegistry.get_power_profile(&"merchants_guild")
	var hunters := ContentRegistry.get_power_profile(&"monster_hunters_guild")
	check(merchants != null and hunters != null, "both profiles should be authored")
	if merchants != null and hunters != null:
		check_gt(merchants.rank_sensitivity - hunters.rank_sensitivity, 0.4,
			"a trading house should care about a name where a hunters' lodge does not")

	# Where birth counts, the lord of a region is addressed by his family's rank.
	polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	polity.polity_form_id = &"feudal_kingdom"
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		if s.ruling_house_id == &"":
			continue
		check_eq(PolityFormEvaluator.local_title_for(id),
			HouseRank.title_of(s.ruling_house_id),
			"under a feudal crown a lord carries his own family's rank")
		break


func _check_land_leans() -> void:
	SimTestHarness.eventful_world(7106, 900)
	var leaning := 0
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		if s.faction_lean_id == &"":
			continue
		leaning += 1
		check(GameState.get_organization(s.faction_lean_id) != null,
			"%s leans toward a faction that does not exist" % s.display_name)
	check_gt(float(leaning), 0.0, "regions should be with somebody")


## The old world could not change its constitution: whoever rose, the crown
## stayed a crown. A regime outweighed by somebody else has to be able to fall.
func _check_a_regime_can_actually_fall() -> void:
	SimTestHarness.fresh_world(7107)
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	polity.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	polity.ideology.decision_structure = PoliticalSystemAxes.DecisionStructure.AUTOCRATIC
	polity.legitimacy = 0.1
	polity.power_score = 5.0
	polity.last_fired_tick[&"regime_shift"] = -999999

	# Somebody else is plainly holding the country up.
	for guild in GameState.organizations_of_kind(Organization.OrgKind.GUILD):
		guild.archetype_id = &"merchants_guild"
		guild.power_score = 95.0

	var before_ruler := polity.leader_person_id
	RegimeShift.consider_all(SimClock.current_tick)

	check_eq(polity.ideology.legitimacy_basis,
		PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED,
		"a country held up by its merchants should end up resting on wealth")
	check(polity.leader_person_id != before_ruler,
		"a monarch deposed by a change of constitution should not still be on the throne")
	check_near(polity.legitimacy, RegimeShift.FRESH_LEGITIMACY, 0.001,
		"a new order starts with its own standing, not the old one's")

	# And the form of government follows the constitution, not the other way round.
	PolityFormEvaluator.refresh_all(SimClock.current_tick)
	var form := PolityFormEvaluator.form_of(polity)
	check(form != null and form.form_id != &"feudal_kingdom",
		"the country should no longer be describable as a feudal kingdom")


## A world in crisis should be able to arrive at a politics it did not start
## with, rather than producing another variation on what it already had.
func _check_crisis_produces_new_politics() -> void:
	SimTestHarness.fresh_world(7108)
	var parent := GameState.root_of_kind(Organization.OrgKind.FACTION)
	parent.member_count = 400

	var rule: TriggerRule = null
	for candidate in ContentRegistry.rules():
		if candidate.rule_id == &"radical_levellers":
			rule = candidate
			break
	check(rule != null, "the levellers' rule should be authored")
	if rule == null:
		return
	check_gt(rule.radicalism, 0.5, "a rule born of famine should be a radical break")

	var branch := SchismResolver.create_branch(parent, rule, SimClock.current_tick)
	check(branch != null, "a crisis should be able to produce a new movement")
	if branch == null:
		return
	check_eq(branch.archetype_id, &"levellers_faction",
		"and it should be a kind of body the world did not have")
	check_eq(branch.ideology.legitimacy_basis, PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"a movement against inherited rank should not rest on inherited rank")
	check_eq(branch.ideology.decision_structure, PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
		"nor decide things by one voice")
	check_gt(branch.ideology.ideological_distance(parent.ideology), 0.12,
		"a radical break should not believe roughly what its parent believed")
	check(GenealogyValidator.traces_to_root(branch.org_id),
		"however far it breaks, it still traces to the first faction in the world")


## The complaint this layout exists to answer: drawn as one tree per house, a
## married couple appeared twice, once in each family.
func _check_everyone_appears_once_in_the_family_chart() -> void:
	SimTestHarness.eventful_world(7109, 900)
	var source := GenealogySource.new()
	check(source.is_generational(), "the family chart is laid out by generation")

	var view := LineageGraphView.new()
	view.source = source
	view.rebuild()

	var placed: Dictionary = view._positions
	check_gt(float(placed.size()), 20.0, "the chart should have people on it")
	var living_and_dead := 0
	for id in GameState.people:
		living_and_dead += 1
		check(placed.has(id), "%s is missing from the family chart" % id)
	check_eq(placed.size(), living_and_dead,
		"every person should be drawn exactly once, and nobody twice")

	# Descent lines must point downward, or the chart is not a chart.
	for edge in view._edges:
		var parent_pos: Vector2 = placed.get(edge[0], Vector2.ZERO)
		var child_pos: Vector2 = placed.get(edge[1], Vector2.ZERO)
		check(child_pos.y > parent_pos.y,
			"a child should be drawn below their parents (%s -> %s)" % [edge[0], edge[1]])

	# Spouses sit side by side on the same row, which is what makes the marriage
	# line read as a join between two houses rather than a stray connector.
	for pair in view._spouse_edges:
		var a: Vector2 = placed.get(pair[0], Vector2.ZERO)
		var b: Vector2 = placed.get(pair[1], Vector2.ZERO)
		check_near(a.y, b.y, 0.01, "a married pair should share a row")
	view.free()
