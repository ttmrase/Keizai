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
	if GameState.organizations_of_kind(parent.kind).size() >= SimConfig.MAX_ACTIVE_ORGS_PER_KIND:
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

	var profile := ContentRegistry.get_power_profile(branch.archetype_id)
	branch.leadership_title = rule.branch_leadership_title
	if branch.leadership_title.is_empty():
		branch.leadership_title = profile.default_leadership_title if profile != null \
			else parent.leadership_title

	branch.ideology = PoliticalSystemGenerator.generate_branch_axes(parent, rule.ideology_drift_bias)
	if rule.branch_archetype_id != &"":
		branch.ideology.legitimacy_basis = PoliticalSystemGenerator.legitimacy_for_archetype(
			branch.archetype_id, branch.ideology.legitimacy_basis)
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
		leader = _recruit_founder(parent, tick, rng)
	branch.leader_person_id = leader.person_id

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


## A branch needs someone to lead it. Preference goes to an existing member of
## the parent's world; failing that a new figure rises from the ranks, flagged as
## founding generation so their ancestry terminates cleanly.
static func _recruit_founder(parent: Organization, tick: int,
		rng: RandomNumberGenerator) -> NotableIndividual:
	var candidates: Array[NotableIndividual] = []
	for p in GameState.living_people():
		if not p.is_adult(tick) or p.current_tenure() != null:
			continue
		if p.age_years(tick) > 60:
			continue
		candidates.append(p)

	if not candidates.is_empty() and rng.randf() < 0.5:
		var weights: Array = []
		for c in candidates:
			weights.append(2.0 if c.has_tag(&"ambitious") else 1.0)
		var chosen: NotableIndividual = RngService.pick_weighted(&"rules", candidates, weights)
		if chosen != null:
			return chosen

	var founder := NotableIndividual.new()
	founder.person_id = GameState.mint_person_id()
	founder.sex = "f" if rng.randf() < 0.5 else "m"
	founder.family_name = NameGenerator.family_stem()
	founder.full_name = "%s・%s" % [founder.family_name, NameGenerator.given_name(founder.sex)]
	founder.birth_tick = tick - rng.randi_range(28, 46) * SimConfig.TICKS_PER_YEAR
	founder.is_founder_generation = true
	founder.personality_tags = Demography.roll_personality(rng)
	HistoryLog.emit_event(
		HistoryEvent.EventType.BIRTH,
		founder.birth_tick,
		"%sが生まれた。" % founder.full_name,
		{"person": founder.to_dict()},
		&"", founder.person_id)
	return GameState.get_person(founder.person_id)
