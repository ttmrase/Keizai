class_name SchismResolver
extends RefCounted

## Splits a branch off an existing organization.
##
## Two things happen here that matter to the design. First, the branch always
## records `parent_org_id` and chains `origin_event_id` to the parent's own
## founding, so the new institution can always be walked back to the single root
## of its kind. Second, when a rule names a `branch_archetype_id`, the branch is
## not merely a splinter — it is a *new kind of institution* the society did not
## have before, invented because the world started demanding it.


## Returns null when the society has no room for another institution of this kind.
## Every path that creates a branch goes through here — authored rules and
## contested successions alike — so this is the one place the ceiling holds.
static func create_branch(parent: Organization, rule: TriggerRule, tick: int,
		leader_override: NotableIndividual = null) -> Organization:
	if not has_room_for_branch(parent, rule):
		return null

	var rng := RngService.stream(&"rules")
	var branch := Organization.new()
	branch.org_id = GameState.mint_org_id()
	branch.kind = parent.kind
	branch.archetype_id = rule.branch_archetype_id if rule.branch_archetype_id != &"" \
		else parent.archetype_id
	branch.parent_org_id = parent.org_id
	branch.founding_tick = tick
	branch.dynasty_seat_settlement_id = parent.dynasty_seat_settlement_id
	branch.cause_tags = parent.cause_tags.duplicate()
	# A cadet branch is still the same kind of family and still keeps the same
	# faith. Both can change later; neither is forgotten at the moment of the
	# split, which is what leaving them blank amounted to.
	branch.character_id = parent.character_id
	branch.faith_id = parent.faith_id
	if parent.kind == Organization.OrgKind.HOUSE:
		branch.standing = parent.standing
		branch.liege_house_id = parent.liege_house_id
		branch.loyalty = parent.loyalty
		# A cadet line leaves with a name and no land, which makes it a client of
		# the house it left rather than its equal. This is also what keeps the
		# rank below the nobility populated: every branch of a great house swells
		# it, and only holding ground gets a family back out of it. Treating a
		# branch as another noble house instead inverts the world within a few
		# centuries — thirty noble families and nobody in service to any of them.
		if parent.standing == Organization.Standing.NOBLE:
			branch.standing = Organization.Standing.RETAINER
			branch.liege_house_id = parent.org_id
			branch.loyalty = 0.6

	var profile := ContentRegistry.get_power_profile(branch.archetype_id)
	branch.leadership_title = rule.branch_leadership_title
	if branch.leadership_title.is_empty():
		branch.leadership_title = profile.default_leadership_title if profile != null \
			else parent.leadership_title

	branch.ideology = PoliticalSystemGenerator.generate_branch_axes(
		parent, rule.ideology_drift_bias, rule.radicalism)
	if rule.branch_archetype_id != &"":
		branch.ideology.legitimacy_basis = PoliticalSystemGenerator.legitimacy_for_archetype(
			branch.archetype_id, branch.ideology.legitimacy_basis)
	# A movement born of a crisis does not merely disagree about degree. Where the
	# rule says so, the branch rejects how the old body chooses its officers at
	# all — which is what lets a society arrive at a shape it has never had.
	if rule.branch_legitimacy_basis >= 0:
		branch.ideology.legitimacy_basis = rule.branch_legitimacy_basis
	if rule.branch_decision_structure >= 0:
		branch.ideology.decision_structure = rule.branch_decision_structure
	branch.ideology_baseline = branch.ideology.clone()

	var fraction := rng.randf_range(rule.inherited_member_fraction.x, rule.inherited_member_fraction.y)
	var inherited := int(parent.member_count * fraction)
	branch.member_count = maxi(5, inherited)
	var inherited_gold: float = parent.resources.get(&"gold", 0.0) * fraction
	branch.resources = {&"gold": inherited_gold}

	# A breakaway regime that governs nothing is not a rival, it is a rumour.
	# It takes land with it, which is also what makes the parent weaker.
	var seceded: Array[StringName] = []
	if parent.kind == Organization.OrgKind.POLITICAL_SYSTEM and parent.governs_settlement_ids.size() > 1:
		var take := maxi(1, int(parent.governs_settlement_ids.size() * fraction))
		for i in mini(take, parent.governs_settlement_ids.size() - 1):
			seceded.append(parent.governs_settlement_ids[i])
		branch.governs_settlement_ids = seceded
		branch.legitimacy = parent.legitimacy * 0.6

	var leader := leader_override
	if leader == null:
		leader = _find_leader(parent, tick, rng)
	if leader == null:
		# A breakaway needs somebody to lead it, and nobody is invented for the
		# purpose. With no willing figure, the split simply does not happen.
		return null
	branch.leader_person_id = leader.person_id

	# A cadet branch takes a line of the family with it, and that line takes the
	# new house's name — which is what makes a 分家 legible in the family tree.
	var moved: Array[StringName] = []
	if parent.kind == Organization.OrgKind.HOUSE:
		moved = _line_of(leader)

	var named := PoliticalSystemGenerator.name_and_describe(branch, true, parent)
	branch.display_name = named["display_name"]
	branch.description = named["description"]

	var reason := RuleConditionEvaluator.describe(rule, parent)
	var text := rule.chronicle_template
	if text.is_empty():
		text = "{parent}から{branch}が分かれ出た。"
	text = text.replace("{parent}", parent.display_name) \
		.replace("{branch}", branch.display_name) \
		.replace("{leader}", leader.full_name) \
		.replace("{reason}", reason)

	HistoryLog.emit_event(
		HistoryEvent.EventType.SCHISM,
		tick,
		text,
		{
			"organization": branch.to_dict(),
			"inherited_members": inherited,
			"inherited_gold": inherited_gold,
			"schism_kind": String(rule.schism_kind),
			"rule_id": String(rule.rule_id),
			"reason": reason,
			"seceded_settlements": Organization._names_to_strings(seceded),
			"moved_person_ids": Organization._names_to_strings(moved),
			# Whether the line that walked out was the family's own blood. Always
			# should be, for a house — a cadet branch is a family going out of
			# itself, and anchoring one on somebody who married in renames the
			# partner whose name it was. Recorded so the suite can say so.
			"founder_married_in": not HouseNaming.is_of_the_blood(leader, parent),
		},
		branch.org_id,
		leader.person_id,
		parent.origin_event_id)

	# The dissenters have gone. What remains has, in effect, redefined itself, so
	# the parent stops being measured against beliefs it no longer holds —
	# otherwise the same unresolved drift would split it again every cooldown.
	if rule.schism_kind == &"ideological_split" and parent.ideology != null:
		parent.ideology_baseline = parent.ideology.clone()

	return GameState.get_organization(branch.org_id)


## Whether the world has room for this branch at all. Separated out so a caller
## can find out *before* announcing that somebody stormed off to found their own
## house — the chronicle should not record a departure that never happened.
static func has_room_for_branch(parent: Organization, rule: TriggerRule) -> bool:
	if GameState.organizations_of_kind(parent.kind).size() >= _ceiling_for(rule):
		return false
	var archetype: StringName = rule.branch_archetype_id if rule.branch_archetype_id != &"" \
		else parent.archetype_id
	# The per-archetype cap exists so the world does not fill with seven
	# lookalike guilds. Every family in the world shares one archetype, so
	# applying it to houses would forbid the second family outright.
	if parent.kind != Organization.OrgKind.HOUSE \
			and _count_of(archetype) >= SimConfig.MAX_ACTIVE_PER_ARCHETYPE:
		return false
	return true


## How many bodies of this kind the world will carry. A society always has room
## for something it has never had before, so a branch that introduces a genuinely
## new kind of institution is allowed past the ordinary ceiling — otherwise a
## world that has already filled its quota with lookalike splinters could never
## produce a new politics, however badly it needed one.
static func _ceiling_for(rule: TriggerRule) -> int:
	if rule.applies_to_kind == Organization.OrgKind.HOUSE:
		return SimConfig.MAX_ACTIVE_HOUSES
	if rule.branch_archetype_id == &"":
		return SimConfig.MAX_ACTIVE_ORGS_PER_KIND
	if _count_of(rule.branch_archetype_id) > 0:
		return SimConfig.MAX_ACTIVE_ORGS_PER_KIND
	return SimConfig.MAX_ACTIVE_ORGS_PER_KIND + SimConfig.NEW_ARCHETYPE_HEADROOM


static func _count_of(archetype_id: StringName) -> int:
	return int(WorldStateQuery.get_value(
		StringName("count.archetype." + String(archetype_id))))


## A branch needs someone to lead it, and it has to be somebody who already
## exists: an adult who is not already holding an office elsewhere. Ambition
## makes a person likelier to be the one who walks out.
static func _find_leader(parent: Organization, tick: int,
		rng: RandomNumberGenerator) -> NotableIndividual:
	var candidates: Array[NotableIndividual] = []
	var weights: Array = []
	for p in GameState.living_people():
		if not p.is_adult(tick) or p.current_tenure() != null:
			continue
		if p.age_years(tick) > 62 or p.is_disinherited():
			continue
		var weight := 1.0
		if p.has_tag(&"ambitious"):
			weight += 2.0
		# Somebody already inside the organization's own house is the likeliest
		# person to lead a split from it — but only its own blood. A woman who
		# married in belongs to the household and carries its name; she does not
		# found a cadet line of a family she was not born to, and letting her do
		# it renames her husband, who is the one the name actually belongs to.
		if parent.kind == Organization.OrgKind.HOUSE:
			if p.house_org_id != parent.org_id or not HouseNaming.is_of_the_blood(p, parent):
				continue
			weight += 2.5
		candidates.append(p)
		weights.append(weight)
	if candidates.is_empty():
		return null
	return RngService.pick_weighted(&"rules", candidates, weights)


## The leader, everyone descended from them, and the people those descendants
## married — the household that leaves with a cadet branch.
##
## Taking the descendants without their spouses splits married couples between
## two houses, which is visible in the family tree as a pair with two different
## surnames and no reason for it. Whoever married into this line goes where the
## line goes. The line is always anchored on somebody born to the house, so this
## never runs the other way and renames the partner whose name it was.
static func _line_of(leader: NotableIndividual) -> Array[StringName]:
	var out: Array[StringName] = [leader.person_id]
	_take_spouses(leader, out)
	for descendant in GenealogyValidator.descendants(leader.person_id, 6):
		if not out.has(descendant.person_id):
			out.append(descendant.person_id)
		_take_spouses(descendant, out)
	return out


static func _take_spouses(person: NotableIndividual, out: Array[StringName]) -> void:
	for spouse_id in person.spouse_ids:
		var spouse := GameState.get_person(spouse_id)
		if spouse == null or not spouse.is_alive() or out.has(spouse_id):
			continue
		out.append(spouse_id)
