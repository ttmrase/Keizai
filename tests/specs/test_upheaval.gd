extends Spec

## What faith is worth to everybody who is not a priest, the ruptures that need
## several unlikely things at once, and a state falling rather than being amended.

func run() -> void:
	_check_faith_is_worth_nothing_where_all_agree()
	_check_a_divided_world_takes_sides()
	_check_a_region_at_odds_with_its_lord_is_unruly()
	_check_a_faith_can_claim_the_state()
	_check_a_changed_basis_founds_a_new_state()
	_check_a_reform_keeps_the_same_state()
	_check_a_fallen_state_is_remembered_by_its_successor()
	_check_ruptures_need_everything_at_once()
	_check_an_uprising_ends_the_regime()
	finish()


## A world with one faith has no religious politics: agreeing costs nothing when
## there is nothing to disagree about.
func _check_faith_is_worth_nothing_where_all_agree() -> void:
	SimTestHarness.fresh_world(6101)
	var faith := Religion.root()
	check(faith != null, "the world should open on one faith")
	for id in GameState.world.settlements:
		GameState.world.settlements[id].religion_id = faith.org_id
	Religion.refresh_all(SimClock.current_tick)

	check_near(Religion.division(), 0.0, 0.01, "one faith everywhere is no division")
	check_near(Religion.reach_of(faith), 1.0, 0.01, "and it reaches all of it")
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE)
	check_gt(float(houses.size()), 1.0, "there should be families to compare")
	check_near(Religion.alignment(houses[0], houses[1]), 0.0, 0.01,
		"sharing the only faith there is says nothing about two families")
	for id in GameState.world.settlements:
		check_near(Religion.friction_in(GameState.world.settlements[id]), 0.0, 0.01,
			"and nowhere is at odds with anybody about it")


## Split the world and the same reading turns into the loudest fact about it.
func _check_a_divided_world_takes_sides() -> void:
	SimTestHarness.fresh_world(6102)
	var faiths := _two_faiths()
	if faiths.is_empty():
		return
	var a: Organization = faiths[0]
	var b: Organization = faiths[1]

	var half := true
	for id in GameState.world.settlements:
		GameState.world.settlements[id].religion_id = a.org_id if half else b.org_id
		half = not half
	Religion.refresh_all(SimClock.current_tick)
	check_gt(Religion.division(), 0.5, "a world split down the middle is divided")

	var same_a: Organization = null
	var same_b: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		house.faith_id = a.org_id if same_a == null else b.org_id
		if same_a == null:
			same_a = house
		elif same_b == null:
			same_b = house
	if same_a == null or same_b == null:
		check(false, "the world should have two great families")
		return
	var third: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE \
				and house.org_id != same_a.org_id and house.org_id != same_b.org_id:
			house.faith_id = a.org_id
			third = house
			break
	if third == null:
		return
	check_gt(Religion.alignment(same_a, third), 0.3,
		"two families of the same faith are on the same side of something")
	check_gt(0.0 - Religion.alignment(same_a, same_b), 0.3,
		"and two of different faiths are not")


## The link that makes a revelation cost a country something.
func _check_a_region_at_odds_with_its_lord_is_unruly() -> void:
	SimTestHarness.fresh_world(6103)
	var faiths := _two_faiths()
	if faiths.is_empty():
		return
	var held: SettlementState = null
	var lord: Organization = null
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var house := GameState.get_organization(s.ruling_house_id)
		if house != null:
			held = s
			lord = house
			break
	if held == null or lord == null:
		check(false, "some region should have a family set over it")
		return

	# Split the world so faith is worth something, then set the region against
	# the family holding it.
	var half := true
	for id in GameState.world.settlements:
		GameState.world.settlements[id].religion_id = faiths[0].org_id if half \
			else faiths[1].org_id
		half = not half
	Religion._settle_followings(GameState.organizations_of_kind(Organization.OrgKind.RELIGION))

	lord.faith_id = held.religion_id
	check_near(Religion.friction_in(held), Religion.friction_in(held), 0.001, "read twice the same")
	var at_peace := Religion.friction_in(held)
	lord.faith_id = faiths[0].org_id if held.religion_id == faiths[1].org_id \
		else faiths[1].org_id
	var at_odds := Religion.friction_in(held)
	check_gt(at_odds - at_peace, 0.2,
		"a region set under a family of another faith is at odds with it")


## A faith most of the world holds, with a priesthood to speak for it, is a claim
## on the country and not only on the temple.
func _check_a_faith_can_claim_the_state() -> void:
	SimTestHarness.fresh_world(6104)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	var faiths := _two_faiths()
	if faiths.is_empty() or realm == null:
		return
	var faith: Organization = faiths[0]

	# Almost everywhere, but no priesthood: the altar has nobody to speak at it.
	for id in GameState.world.settlements:
		GameState.world.settlements[id].religion_id = faith.org_id
	Religion.refresh_all(SimClock.current_tick)
	faith.leader_person_id = &""
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	check(RegimeShift._altar_claim(realm).is_empty(),
		"a faith with no seat claims nothing")

	# Give it one, and the claim is there.
	for p in GameState.living_people():
		if p.current_tenure() == null:
			faith.leader_person_id = p.person_id
			break
	faith.power_score = maxf(faith.power_score, realm.power_score)
	var claim := RegimeShift._altar_claim(realm)
	check(not claim.is_empty(), "a faith holding the country has a claim on it")
	if claim.is_empty():
		return
	check_eq(claim["ground"], "信仰", "and presses it as a faith")
	check_eq(claim["basis"], PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC,
		"what it wants is a country founded on the faith")

	# Except from a country already founded on it.
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC
	check(RegimeShift._altar_claim(realm).is_empty(),
		"a theocracy is not overthrown in the name of theocracy")


## What a country rests on changing is a different country.
func _check_a_changed_basis_founds_a_new_state() -> void:
	SimTestHarness.fresh_world(6105)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	var before := GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size()
	var ground := realm.governs_settlement_ids.size()
	check_gt(float(ground), 0.0, "the state should govern something to hand on")
	var voice := _some_faction()
	if voice == null:
		return

	RegimeShift.force_overturn(realm, {
		"org": voice,
		"ground": "民衆",
		"hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
	}, SimClock.current_tick)

	check(not realm.is_active(), "the state that rested on blood has ended")
	var heir := HouseRank.dominant_realm()
	check(heir != null and heir.org_id != realm.org_id, "and a successor stands in its place")
	if heir == null:
		return
	check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(),
		before, "one country, one state at a time")
	check_eq(heir.parent_org_id, realm.org_id,
		"the successor records what it was founded out of")
	check_eq(heir.ideology.legitimacy_basis, PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"and rests on something else")
	check_eq(heir.governs_settlement_ids.size(), ground,
		"a successor takes the whole country, not a piece of it")
	check(realm.governs_settlement_ids.is_empty(), "and the fallen state governs nothing")
	check(GenealogyValidator.traces_to_root(heir.org_id),
		"however far it has come, it still traces to the first state in the world")


## How a country decides changing is the same country under new arrangements.
func _check_a_reform_keeps_the_same_state() -> void:
	SimTestHarness.fresh_world(6106)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.ELECTED
	realm.ideology.decision_structure = PoliticalSystemAxes.DecisionStructure.AUTOCRATIC
	var voice := _some_faction()
	if voice == null:
		return

	RegimeShift.force_overturn(realm, {
		"org": voice,
		"ground": "議会",
		"hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
	}, SimClock.current_tick)

	check(realm.is_active(), "a chamber reorganizing itself does not end the country")
	check_eq(realm.ideology.decision_structure,
		PoliticalSystemAxes.DecisionStructure.ASSEMBLY, "it decides differently now")
	check_eq(GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM).size(), 1,
		"and there is still one state")


## Whoever a fallen state turned out carries it into everything it became.
func _check_a_fallen_state_is_remembered_by_its_successor() -> void:
	SimTestHarness.fresh_world(6107)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	var monarch := GameState.get_current_leader(realm.org_id)
	check(monarch != null, "the kingdom should have a king to depose")
	if monarch == null:
		return
	var voice := _some_faction()
	if voice == null:
		return

	RegimeShift.force_overturn(realm, {
		"org": voice,
		"ground": "民衆",
		"hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
		"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
	}, SimClock.current_tick)

	check(monarch.was_deposed_from(realm.org_id), "the king was turned out of his own state")
	var heir := HouseRank.dominant_realm()
	if heir == null:
		return
	var tick := SimClock.current_tick
	var tainted := SuccessionResolver._claim_weight(monarch, heir, tick, null)
	monarch.deposed_from.clear()
	var untainted := SuccessionResolver._claim_weight(monarch, heir, tick, null)
	check(tainted < untainted * 0.5,
		"a republic founded on a king's ruin has not forgotten who the king was")


## Every rupture wants two or three unlikely things at once. Take one away and
## nothing happens, which is what makes it a rupture rather than weather.
func _check_ruptures_need_everything_at_once() -> void:
	SimTestHarness.fresh_world(6108)
	var tick := SimClock.current_tick
	# A world at peace, all of one faith, with nobody armed: none of them.
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		s.unrest = 0.0
		s.religion_id = Religion.root().org_id
	Religion.refresh_all(tick)
	GameState.world.global_unrest = 0.0

	check(not Incidents._try_uprising(tick), "a contented country does not rise")
	check(not Incidents._try_assassination(tick), "and nobody is killed in it")
	check(not Incidents._try_capital_seizure(tick), "and no gate is opened")
	check(not Incidents._try_excommunication(tick),
		"and a world of one faith has nobody to cut out of it")

	for entry in Incidents.pressures():
		check(float(entry["pressure"]) < 1.0,
			"%s should not read as ready in a world at peace" % entry["label"])
		check(not String(entry["missing"]).is_empty(),
			"%s should say what is holding it back" % entry["label"])


## And when everything is true at once, the country ends.
func _check_an_uprising_ends_the_regime() -> void:
	SimTestHarness.fresh_world(6109)
	var realm := GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	realm.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
	var tick := SimClock.current_tick
	for id in GameState.world.settlements:
		GameState.world.settlements[id].unrest = 1.0
	GameState.world.global_unrest = 1.0
	SocialTies.refresh_all(tick)

	check(Incidents._try_uprising(tick), "a country entirely in revolt rises")
	var incidents := 0
	for e in HistoryLog.buffer:
		if e.event_type == HistoryEvent.EventType.INCIDENT:
			incidents += 1
			check(e.is_lineage_critical, "a rupture is never compacted away")
			check_eq(String(e.payload.get("incident_kind", "")), String(Incidents.KIND_UPRISING),
				"and says which rupture it was")
	check_eq(incidents, 1, "one rupture, recorded once")

	# It happened, so it does not happen again next season.
	check(not Incidents._try_uprising(tick + 1), "and not again the following year")
	check(not realm.is_active(), "the regime it rose against is gone")


# ------------------------------------------------------------------- helpers

## Two faiths in a world that opens with one. The second is branched off the
## first the way the world would branch it.
func _two_faiths() -> Array[Organization]:
	var root := Religion.root()
	if root == null:
		check(false, "the world should open on a faith")
		return []
	var rule := TriggerRule.new()
	rule.rule_id = &"test_faith"
	rule.rule_type = TriggerRule.RuleType.SCHISM
	rule.schism_kind = &"revelation"
	rule.applies_to_kind = Organization.OrgKind.RELIGION
	rule.inherited_member_fraction = Vector2(0.2, 0.3)
	rule.branch_leadership_title = "祭主"
	var branch := SchismResolver.create_branch(root, rule, SimClock.current_tick)
	if branch == null:
		check(false, "the world should have room for a second faith")
		return []
	return [root, branch]


func _some_faction() -> Organization:
	var factions := GameState.organizations_of_kind(Organization.OrgKind.FACTION)
	if factions.is_empty():
		check(false, "the world should have a body of opinion")
		return null
	return factions[0]
