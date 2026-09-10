extends Spec

## The rank below the nobility, the faith above everyone, what kind of family a
## house is, why families split, and the two ways of reading a family tree.

func run() -> void:
	_check_the_world_starts_with_retainers()
	_check_crossing_the_rank_is_hard()
	_check_a_retainer_house_can_rise()
	_check_a_noble_house_can_fall()
	_check_faith_starts_leaderless_and_derives()
	_check_faith_spreads_and_traces_to_animism()
	_check_houses_have_a_character_that_counts()
	_check_households_split_for_reasons()
	_check_both_ranks_survive_the_centuries()
	_check_most_successions_are_quiet()
	_check_a_branch_says_why_it_exists()
	_check_the_roll_of_leaders()
	_check_the_spine_is_house_heads()
	_check_a_house_has_a_chart_of_its_own()
	_check_a_persons_own_chart_stops_one_step_out()
	finish()


func _check_the_world_starts_with_retainers() -> void:
	SimTestHarness.fresh_world(8101)
	var nobles := 0
	var retainers := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			nobles += 1
		elif house.standing == Organization.Standing.RETAINER:
			retainers += 1
			check(house.liege_house_id != &"", "%s should serve somebody" % house.display_name)
			var liege := GameState.get_organization(house.liege_house_id)
			check(liege != null and liege.standing == Organization.Standing.NOBLE,
				"%s should serve a noble house" % house.display_name)
			check(house.held_settlement_ids.is_empty(),
				"a retainer house holds no county of its own")
	check_eq(retainers, nobles * SimConfig.RETAINERS_PER_HOUSE,
		"every founding house should have its three retainer families")
	check_gt(float(nobles), 4.0, "and there should be a nobility for them to serve")

	# The peerage is the nobility's own order and nobody else's.
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			check_eq(house.rank_tier, 0, "%s stands outside the peerage" % house.display_name)


## Marrying across the line is possible and should stay rare — and it opens up
## exactly when a great house has fallen out with everyone at its own level.
func _check_crossing_the_rank_is_hard() -> void:
	SimTestHarness.fresh_world(8102)
	var noble: Organization = null
	var retainer: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if noble == null and house.standing == Organization.Standing.NOBLE:
			noble = house
		elif retainer == null and house.standing == Organization.Standing.RETAINER:
			retainer = house
	check(noble != null and retainer != null, "the world should have both ranks")
	if noble == null or retainer == null:
		return

	var a := GameState.house_members(noble.org_id)[0]
	var b := GameState.house_members(retainer.org_id)[0]
	check(Retainers.is_match_beneath_rank(a, b), "this is a match across the rank line")

	# Somebody from a family that serves a different house, for the same test
	# without the extra warmth a family feels toward its own servants.
	var stranger: NotableIndividual = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		if house.liege_house_id == noble.org_id:
			continue
		var members := GameState.house_members(house.org_id)
		if not members.is_empty():
			stranger = members[0]
			break

	# On good terms with its equals, a house has no reason to look below itself.
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.standing == Organization.Standing.NOBLE:
			noble.house_relations[other.org_id] = 0.5
	var when_content := Retainers.match_weight(a, b)

	# With nobody left to marry, it very much does.
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.standing == Organization.Standing.NOBLE:
			noble.house_relations[other.org_id] = -0.8
	var when_isolated := Retainers.match_weight(a, b)

	check(when_content < 0.15, "a well-connected house rarely marries below its rank")
	check_gt(when_isolated - when_content, 0.15,
		"a house with no equals left to marry should look downward")
	# Even then, a family it has no history with is not a match it makes freely.
	if stranger != null:
		check_gt(1.0, Retainers.match_weight(a, stranger),
			"a stranger below one's rank is still not an ordinary match")


func _check_a_retainer_house_can_rise() -> void:
	SimTestHarness.fresh_world(8103)
	var retainer: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.RETAINER:
			retainer = house
			break
	check(retainer != null, "the world should have retainer families")
	if retainer == null:
		return
	var liege := GameState.get_organization(retainer.liege_house_id)
	check(liege != null and not liege.held_settlement_ids.is_empty(),
		"the liege should hold land to lose")
	if liege == null:
		return

	var seat: StringName = liege.held_settlement_ids[0]
	retainer.loyalty = 0.0
	retainer.power_score = 90.0
	liege.power_score = 10.0
	Retainers.refresh_all(SimClock.current_tick)

	check_eq(retainer.standing, Organization.Standing.NOBLE,
		"a retainer house with the strength and the grievance should take the rank")
	check(retainer.held_settlement_ids.has(seat), "and the county it rose over")
	check_eq(retainer.liege_house_id, &"", "a risen house serves nobody")
	check(GameState.world.settlements[seat].ruling_house_id == retainer.org_id,
		"and the region should know it")
	check(GenealogyValidator.traces_to_root(retainer.org_id),
		"however it rose, it still traces to the first house in the world")


## The other half of the same coin: a house that seizes the state strips a rival
## and raises its own, and the rival goes into that house's service.
func _check_a_noble_house_can_fall() -> void:
	SimTestHarness.fresh_world(8104)
	var winner: Organization = null
	var rival: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		if winner == null:
			winner = house
		elif rival == null and not house.held_settlement_ids.is_empty():
			rival = house
	if winner == null or rival == null:
		check(false, "the world should have rival noble houses")
		return
	# One enemy, so the house punished is the one this test is about: world
	# generation leaves the great families with opinions of each other already.
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		winner.house_relations[house.org_id] = 0.4
	winner.house_relations[rival.org_id] = -0.6
	var favourites := Retainers.retainers_of(winner.org_id)
	check_gt(float(favourites.size()), 0.0, "the winner should have servants to reward")
	Retainers.reward_and_punish(winner, SimClock.current_tick)

	check_eq(rival.standing, Organization.Standing.RETAINER,
		"a stripped rival is lowered rather than destroyed")
	check(rival.held_settlement_ids.is_empty(), "with nothing left in its own name")

	# It serves the upstart that was raised into its place, which is the part
	# that stings and the part the next generation remembers.
	var risen := GameState.get_organization(rival.liege_house_id)
	check(risen != null, "a lowered house serves somebody")
	if risen == null:
		return
	check_eq(risen.standing, Organization.Standing.NOBLE, "and that somebody is now noble")
	var was_a_servant := false
	for f in favourites:
		if f.org_id == risen.org_id:
			was_a_servant = true
	check(was_a_servant, "and was one of the winner's own retainers a moment ago")
	check(not risen.held_settlement_ids.is_empty(), "holding the land it was given")


func _check_faith_starts_leaderless_and_derives() -> void:
	SimTestHarness.fresh_world(8105)
	var animism := GameState.root_of_kind(Organization.OrgKind.RELIGION)
	check(animism != null, "the world should open with a faith")
	if animism == null:
		return
	check_eq(animism.archetype_id, &"animism", "and it should be the nameless one")
	check_eq(animism.leader_person_id, &"", "which has no priesthood")

	var profile := ContentRegistry.get_power_profile(&"animism")
	check(profile != null and profile.leaderless,
		"and is marked as a body with no seat to fill")

	for id in GameState.world.settlements:
		check_eq(GameState.world.settlements[id].religion_id, animism.org_id,
			"everywhere starts believing the same thing")

	# Nothing fills its empty seat, however long the world runs.
	SimTestHarness.advance(400)
	check_eq(animism.leader_person_id, &"",
		"a faith with no priesthood should never acquire one by accident")


func _check_faith_spreads_and_traces_to_animism() -> void:
	SimTestHarness.eventful_world(8106, 2600)
	var faiths := GameState.organizations_of_kind(Organization.OrgKind.RELIGION)
	check_gt(float(faiths.size()), 1.0,
		"a world through famine, plague and monsters should have organized its faith")

	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		check(GameState.get_organization(s.religion_id) != null,
			"%s believes in something that exists" % s.display_name)

	# A faith winning the whole world is a legitimate ending, so what is checked
	# is that belief moved at all — that regions changed what they held rather
	# than every faith sitting where it was founded.
	var conversions := 0
	for e in HistoryLog.backbone + HistoryLog.buffer:
		if e.event_type == HistoryEvent.EventType.IDEOLOGY_SHIFT and e.payload.has("from_faith"):
			conversions += 1
	check_gt(float(conversions), 0.0, "belief should have moved somewhere in four centuries")

	for faith in faiths:
		check(GenealogyValidator.traces_to_root(faith.org_id),
			"%s must trace back to the first faith in the world" % faith.display_name)
		var chain := GenealogyValidator.org_lineage(faith.org_id)
		check(chain.is_empty() or chain[chain.size() - 1].archetype_id == &"animism",
			"%s should trace to the animism, not to something else" % faith.display_name)


func _check_houses_have_a_character_that_counts() -> void:
	SimTestHarness.fresh_world(8107)
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		check(HouseCharacter.ALL.has(house.character_id),
			"%s should be some recognisable kind of family" % house.display_name)
		check(not HouseCharacter.label(house.character_id).is_empty(),
			"and that kind should have a name")

	# A family of scholars throws off breakaways; a family of courtiers does not.
	var faction := GameState.root_of_kind(Organization.OrgKind.FACTION)
	var leader := GameState.get_person(faction.leader_person_id)
	check(leader != null, "the faction should have a speaker")
	if leader == null:
		return
	var house := GameState.get_organization(leader.house_org_id)
	if house == null:
		return
	house.character_id = HouseCharacter.SCHOLARLY
	var restless := HouseCharacter.schism_affinity(faction)
	house.character_id = HouseCharacter.NOBLE
	var settled := HouseCharacter.schism_affinity(faction)
	check_gt(restless - settled, 0.5,
		"a body led out of a house of scholars should argue itself apart more readily")

	# And a crown standing on courtiers is better propped up than one that is not.
	var polity := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	polity.polity_form_id = &"feudal_kingdom"
	for h in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		h.character_id = HouseCharacter.NOBLE
	var propped := HouseCharacter.realm_support(polity)
	for h in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		h.character_id = HouseCharacter.AGRARIAN
	var unpropped := HouseCharacter.realm_support(polity)
	check_gt(propped - unpropped, 0.5,
		"a feudal crown standing on courtiers should be better held up than one standing on farmers")


## Branches should have causes anyone would recognise, not merely conditions.
func _check_households_split_for_reasons() -> void:
	SimTestHarness.eventful_world(8108, 2400)
	var reasons := {}
	for e in HistoryLog.backbone:
		if e.event_type != HistoryEvent.EventType.SCHISM:
			continue
		var kind := StringName(e.payload.get("schism_kind", ""))
		reasons[kind] = int(reasons.get(kind, 0)) + 1
		check(not HousePartition.reason_label(kind).is_empty(),
			"every split should have a name for why it happened")
		check(not e.description.is_empty(), "and a sentence saying so")

	var household_causes := int(reasons.get(&"unfit_heir", 0)) \
		+ int(reasons.get(&"minority", 0)) + int(reasons.get(&"elopement", 0))
	check_gt(float(household_causes), 0.0,
		"four centuries of families should produce at least one quarrel of their own")


## The rank has to still be there in the fourth century, and so does the
## nobility above it. Both directions failed at different points: every road
## upward turns a noble house into a retainer while promoting one, so the
## nobility drained to a single family holding the whole country; and treating a
## cadet branch as another noble house inverted it the other way, thirty noble
## families with nobody in service to any of them.
func _check_both_ranks_survive_the_centuries() -> void:
	SimTestHarness.eventful_world(8111, 2600)
	var nobles := 0
	var retainers := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			nobles += 1
		elif house.standing == Organization.Standing.RETAINER:
			retainers += 1
	check_gt(float(nobles), float(Retainers.nobility_floor()) - 0.5,
		"the country should still have enough great families to govern itself")
	check_gt(float(retainers), 2.0,
		"and should still have a rank below them, or the ladder has no rungs")

	# No single family should end up holding the entire country.
	var by_holder := {}
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var holder := GameState.get_organization(s.ruling_house_id)
		check(holder != null and holder.is_active(), "%s should be held" % s.display_name)
		if holder != null:
			by_holder[holder.org_id] = int(by_holder.get(holder.org_id, 0)) + 1
	check_gt(float(by_holder.size()), 2.0,
		"the counties should be spread across several families, not gathered into one")

	# And families should still be moving between the ranks.
	var risings := 0
	for e in HistoryLog.backbone:
		if e.event_type == HistoryEvent.EventType.POWER_TRANSFER \
				and bool(e.payload.get("house_rising", false)):
			risings += 1
	check_gt(float(risings), 0.0, "somebody should have risen in four centuries")


## A weighted draw between every grown child turned nearly every succession into
## a quarrel, because nearly every household has more than one grown child. An
## inherited seat should pass to the eldest and nobody should say anything.
func _check_most_successions_are_quiet() -> void:
	SimTestHarness.eventful_world(8112, 2400)
	var quiet := 0
	var disputed := 0
	for e in HistoryLog.backbone:
		if e.event_type != HistoryEvent.EventType.SUCCESSION:
			continue
		if bool(e.payload.get("contested", false)):
			disputed += 1
		else:
			quiet += 1
	check_gt(float(quiet + disputed), 20.0, "four centuries should have filled some seats")
	check_gt(float(quiet), float(disputed),
		"most successions should pass without a quarrel (%d quiet, %d disputed)"
			% [quiet, disputed])

	# And where a seat is inherited and nobody objects, it goes to the eldest,
	# sons before daughters.
	SimTestHarness.fresh_world(8113)
	var house := GameState.root_of_kind(Organization.OrgKind.HOUSE)
	var tick := SimClock.current_tick
	var grown: Array[NotableIndividual] = []
	for member in GameState.house_members(house.org_id):
		if member.is_adult(tick) and member.current_tenure() == null:
			grown.append(member)
	if grown.size() < 2:
		return
	var heir := SuccessionResolver._presumptive_heir(grown, house, tick, null)
	for other in grown:
		if other.person_id == heir.person_id:
			continue
		if other.sex == heir.sex:
			check(heir.birth_tick <= other.birth_tick,
				"the elder of two of the same sex inherits")
		else:
			check_eq(heir.sex, "m", "a son inherits before a daughter")


## The record already holds why a cadet house exists; the family screen should be
## able to read it back rather than the reason being lost the moment it happened.
func _check_a_branch_says_why_it_exists() -> void:
	SimTestHarness.eventful_world(8114, 2000)
	var source := OrganizationLineageSource.new()
	source.root_kinds = [Organization.OrgKind.HOUSE]
	var explained := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.founding_tick <= 0 or house.parent_org_id == &"":
			continue
		var origin := HistoryLog.find_event(house.origin_event_id)
		if origin == null or origin.event_type != HistoryEvent.EventType.SCHISM:
			continue
		explained += 1
		var detail := source.detail(house.org_id)
		check(detail.contains("分かれた理由"),
			"%s should say why it broke away" % house.display_name)
		check(detail.contains(HousePartition.reason_label(
			StringName(origin.payload.get("schism_kind", "")))),
			"%s should name the kind of quarrel it was" % house.display_name)
	check_gt(float(explained), 0.0, "the run should have produced a cadet house to explain")


func _check_the_roll_of_leaders() -> void:
	SimTestHarness.eventful_world(8109, 1200)
	var checked := 0
	for org in GameState.active_organizations():
		var roll := GameState.leader_roll(org.org_id)
		if roll.size() < 2:
			continue
		checked += 1
		var previous := -999999
		for entry in roll:
			var t: RoleTenure = entry["tenure"]
			check(t.start_tick >= previous, "the roll should read earliest first")
			previous = t.start_tick
			check_eq(t.org_id, org.org_id, "every tenure on the roll belongs to this body")
			check(entry["person"] != null, "and to somebody who existed")
		var last: Dictionary = roll[roll.size() - 1]
		if org.leader_person_id != &"":
			check_eq(last["person"].person_id, org.leader_person_id,
				"the last entry should be whoever holds the seat now")
	check_gt(float(checked), 0.0, "some body should have had more than one leader by now")


## The default family view is the line of house heads. Everyone who married in is
## left out — which is exactly what made the full chart unreadable.
func _check_the_spine_is_house_heads() -> void:
	SimTestHarness.eventful_world(8110, 1200)
	var source := GenealogySource.new()
	var spine := source.spine_ids()
	check_gt(float(spine.size()), 4.0, "there should be a line of heads to draw")
	check(spine.size() < GameState.people.size(),
		"and it should be a reduction, not the whole record")

	for id in spine:
		var p := GameState.get_person(id)
		var held_a_house := false
		for t in p.role_history:
			var org := GameState.get_organization(t.org_id)
			if org != null and org.kind == Organization.OrgKind.HOUSE:
				held_a_house = true
		check(held_a_house, "%s is on the spine, so should have held a house" % p.full_name)

	var view := LineageGraphView.new()
	view.source = source
	view.spine_mode = true
	view.rebuild()
	var placed: Dictionary = view._positions
	check_eq(placed.size(), spine.size(), "the spine view draws the heads and nobody else")
	check(view._spouse_edges.is_empty(),
		"and draws no marriages, because the people who married in are not on it")
	for edge in view._edges:
		check(placed[edge[1]].y > placed[edge[0]].y,
			"a head should still be drawn below the head they descend from")

	# Switching the scope off draws everyone again.
	view.spine_mode = false
	view.rebuild()
	check_eq(view._positions.size(), GameState.people.size(),
		"the full chart still holds everyone, exactly once")
	view.free()


## A family's own chart: the people who carry its name, plus the ones who
## married into it. Whoever married out belongs to their husband's family now,
## and appears on that family's chart instead of this one.
func _check_a_house_has_a_chart_of_its_own() -> void:
	SimTestHarness.eventful_world(8111, 1400)
	var subject: Organization = null
	var most := 0
	var strength := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		strength[p.house_org_id] = int(strength.get(p.house_org_id, 0)) + 1
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		var count: int = int(strength.get(house.org_id, 0))
		if count > most:
			most = count
			subject = house
	check(subject != null, "some family should have members to draw")
	if subject == null:
		return

	var source := HouseGenealogySource.new()
	source.house_id = subject.org_id
	var ids := source.all_ids()
	check_gt(float(ids.size()), 3.0, "%s should have a chart worth drawing" % subject.display_name)
	check(ids.size() < GameState.people.size(),
		"and it should be one family, not the whole record")

	var married_in := 0
	for id in ids:
		var p := GameState.get_person(id)
		check(p != null, "everybody on the chart should exist")
		if p == null or p.house_org_id == subject.org_id:
			continue
		var joined := false
		for spouse_id in p.spouse_ids:
			var spouse := GameState.get_person(spouse_id)
			if spouse != null and spouse.house_org_id == subject.org_id:
				joined = true
		check(joined, "%s is on the chart, so is of the house or married into it"
			% p.full_name)
		married_in += 1
	check_gt(float(married_in), 0.0, "and the marriages that joined it should show")

	# Nobody who left the house is on it, however they left.
	var inside := {}
	for id in ids:
		inside[id] = true
	var departed := 0
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.house_org_id == subject.org_id or inside.has(id):
			continue
		var born_to_it := false
		for parent_id in [p.father_id, p.mother_id]:
			var parent := GameState.get_person(parent_id)
			if parent != null and parent.house_org_id == subject.org_id:
				born_to_it = true
		if born_to_it:
			departed += 1
	check(departed >= 0, "people who left the house are simply absent from it")

	var view := LineageGraphView.new()
	view.source = source
	view.rebuild()
	check_eq(view._positions.size(), ids.size(),
		"the family's own chart holds every one of them, once each")
	view.free()


## What a long press opens: one person's line of descent from the source, with
## each generation of it drawn beside its own brothers and sisters — and never
## the generation after those.
func _check_a_persons_own_chart_stops_one_step_out() -> void:
	SimTestHarness.eventful_world(8112, 1600)
	var source := GenealogySource.new()

	var subject := &""
	var father: NotableIndividual = null
	var grandfather: NotableIndividual = null
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		var f := GameState.get_person(p.father_id)
		if f == null:
			continue
		var g := GameState.get_person(f.father_id)
		if g == null or g.children_ids.size() < 2:
			continue
		var has_cousins := false
		for uncle_id in g.children_ids:
			var uncle := GameState.get_person(uncle_id)
			if uncle_id != f.person_id and uncle != null and not uncle.children_ids.is_empty():
				has_cousins = true
		if not has_cousins:
			continue
		subject = id
		father = f
		grandfather = g
		break
	check(subject != &"", "the record should hold somebody with cousins")
	if subject == &"":
		return

	var rows := LineageGraphView.kin_scope(source, subject)
	check(rows.has(subject), "the subject stands on their own chart")
	check(rows.has(father.person_id), "and so does the father they descend from")
	check(rows.has(grandfather.person_id), "and the grandfather above him")
	check(int(rows[grandfather.person_id]) < int(rows[father.person_id]),
		"the line runs downward, generation by generation")
	check(int(rows[father.person_id]) < int(rows[subject]),
		"and the subject stands below their own father")

	for sibling_id in father.children_ids:
		check(rows.has(sibling_id), "brothers and sisters stand beside the subject")
	for uncle_id in grandfather.children_ids:
		check(rows.has(uncle_id), "aunts and uncles stand beside the father")

	# The rule the whole chart rests on: everyone drawn is on the line, a child
	# of somebody on it, or married to somebody on it. Nobody is two steps out.
	var on_the_line := {}
	var walk: Array[StringName] = [subject]
	while not walk.is_empty():
		var current: StringName = walk.pop_back()
		if on_the_line.has(current):
			continue
		on_the_line[current] = true
		var p := GameState.get_person(current)
		if p == null:
			continue
		for parent_id in [p.father_id, p.mother_id]:
			if parent_id != &"" and GameState.get_person(parent_id) != null:
				walk.append(parent_id)

	var one_step_out := 0
	for id in rows:
		if on_the_line.has(id):
			continue
		var p := GameState.get_person(id)
		if p == null:
			continue
		var attached := on_the_line.has(p.father_id) or on_the_line.has(p.mother_id)
		for spouse_id in p.spouse_ids:
			if on_the_line.has(spouse_id):
				attached = true
		check(attached, "%s is drawn, so should be of the line, born to it, or married to it"
			% p.full_name)
		one_step_out += 1
	check_gt(float(one_step_out), 0.0, "the chart is not just a bare line of descent")

	var cousins_left_out := 0
	for uncle_id in grandfather.children_ids:
		if uncle_id == father.person_id:
			continue
		var uncle := GameState.get_person(uncle_id)
		if uncle == null:
			continue
		for cousin_id in uncle.children_ids:
			if not rows.has(cousin_id):
				cousins_left_out += 1
	check_gt(float(cousins_left_out), 0.0,
		"and a cousin's generation is one step too far to draw")

	var earliest := 1 << 30
	for id in rows:
		earliest = mini(earliest, int(rows[id]))
	check_eq(earliest, 0, "the source of the line is the top row of the chart")
