class_name SuccessionResolver
extends RefCounted

## Fills an empty seat. When more than one credible claimant exists the contest
## is decided by weight, not by rank alone — and an ambitious loser may walk out
## and found their own line, which is where most branches in a long game come from.

## Fallback used when no rule is authored for an organization's kind.
const DEFAULT_SCHISM_CHANCE_ON_LOSS := 0.3


static func resolve(org: Organization, tick: int) -> void:
	var rule := _rule_for(org)
	var candidates := _eligible(_candidates(org, tick, rule), org)
	if candidates.is_empty():
		candidates = [_raise_successor(org, tick)]

	var rng := RngService.stream(&"rules")
	var weights: Array = []
	for c in candidates:
		weights.append(_claim_weight(c, org, tick, rule))

	var winner: NotableIndividual = RngService.pick_weighted(&"rules", candidates, weights)
	if winner == null:
		return

	var previous_id := _previous_leader_id(org)
	var previous := GameState.get_person(previous_id)
	var contested := candidates.size() > 1 and rule != null and rule.allow_dispute

	var text := "%sの%sに%sが就いた。" % [org.display_name, org.leadership_title, winner.full_name]
	if contested:
		text = "%sの%sをめぐる争いの末、%sが座に就いた。" \
			% [org.display_name, org.leadership_title, winner.full_name]

	HistoryLog.emit_event(
		HistoryEvent.EventType.SUCCESSION,
		tick,
		text,
		{
			"previous_leader_id": String(previous_id),
			"contested": contested,
			"claimants": candidates.size(),
		},
		org.org_id,
		winner.person_id,
		previous.death_event_id if previous != null else org.origin_event_id)

	if contested:
		_maybe_break_away(org, candidates, winner, tick, rule)


# ---------------------------------------------------------------- candidates

## A monarch may also head their own house — different kinds of authority, and
## historically the same person. Holding two thrones at once is another matter:
## rival states descended from the same dynasty would otherwise all crown the
## same claimant and quietly become one state again.
static func _eligible(candidates: Array[NotableIndividual],
		org: Organization) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in candidates:
		if p == null or not p.is_alive():
			continue
		if _already_leads_kind(p, org.kind):
			continue
		out.append(p)
	return out


static func _already_leads_kind(person: NotableIndividual, kind: Organization.OrgKind) -> bool:
	for t in person.role_history:
		if not t.is_current():
			continue
		var held := GameState.get_organization(t.org_id)
		if held != null and held.is_active() and held.kind == kind:
			return true
	return false

static func _candidates(org: Organization, tick: int, rule: TriggerRule) -> Array[NotableIndividual]:
	var method := rule.method if rule != null else TriggerRule.SuccessionMethod.PRIMOGENITURE
	var basis := org.ideology.legitimacy_basis if org.ideology != null \
		else PoliticalSystemAxes.LegitimacyBasis.HEREDITARY

	# The regime's own legitimacy basis overrides the authored default: once a
	# polity has drifted to electing its leaders, blood stops deciding.
	match basis:
		PoliticalSystemAxes.LegitimacyBasis.ELECTED, PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC:
			method = TriggerRule.SuccessionMethod.ELECTIVE
		PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			method = TriggerRule.SuccessionMethod.MILITARY_STRONGEST
		_:
			pass

	if org.kind == Organization.OrgKind.POLITICAL_SYSTEM \
			and method == TriggerRule.SuccessionMethod.PRIMOGENITURE:
		var from_house := _ruling_house_candidates(org, tick)
		if not from_house.is_empty():
			return from_house

	if method == TriggerRule.SuccessionMethod.PRIMOGENITURE:
		var heirs := _bloodline_heirs(org, tick)
		if not heirs.is_empty():
			return heirs

	return _open_candidates(org, tick)


static func _bloodline_heirs(org: Organization, tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	var previous := GameState.get_person(_previous_leader_id(org))
	if previous != null:
		for child in GameState.children_of(previous.person_id):
			if child.is_adult(tick) and child.current_tenure() == null:
				out.append(child)
	if out.is_empty() and org.kind == Organization.OrgKind.HOUSE:
		for member in GameState.house_members(org.org_id):
			if member.is_adult(tick) and member.current_tenure() == null:
				out.append(member)
	return out


static func _ruling_house_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var previous := GameState.get_person(_previous_leader_id(org))
	if previous == null or previous.house_org_id == &"":
		return []
	var house := GameState.get_organization(previous.house_org_id)
	if house == null or not house.is_active():
		return []
	# The crown follows whoever now heads the house that held it.
	var head := GameState.get_person(house.leader_person_id)
	if head != null and head.is_alive():
		return [head]
	var out: Array[NotableIndividual] = []
	for member in GameState.house_members(house.org_id):
		if member.is_adult(tick):
			out.append(member)
	return out


static func _open_candidates(org: Organization, tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in GameState.living_people():
		if not p.is_adult(tick) or p.current_tenure() != null:
			continue
		if p.age_years(tick) > 68:
			continue
		out.append(p)
	# Keep the contest legible: the few strongest claims, not the whole populace.
	out.sort_custom(func(a, b): return _static_prestige(a) > _static_prestige(b))
	return out.slice(0, 4)


static func _static_prestige(p: NotableIndividual) -> float:
	var score := 1.0
	if p.has_tag(&"ambitious"):
		score += 1.2
	if p.has_tag(&"martial"):
		score += 0.6
	if p.has_tag(&"scholarly"):
		score += 0.4
	if p.house_org_id != &"":
		score += 0.8
	return score


static func _claim_weight(p: NotableIndividual, org: Organization, tick: int,
		rule: TriggerRule) -> float:
	var w := _static_prestige(p)
	var method := rule.method if rule != null else TriggerRule.SuccessionMethod.PRIMOGENITURE
	match method:
		TriggerRule.SuccessionMethod.PRIMOGENITURE:
			# Seniority counts, but does not settle it outright.
			w += clampf(p.age_years(tick) / 40.0, 0.0, 1.5)
		TriggerRule.SuccessionMethod.MILITARY_STRONGEST:
			w += 2.0 if p.has_tag(&"martial") else 0.0
		TriggerRule.SuccessionMethod.MERITOCRATIC_APPOINTMENT:
			w += 1.5 if p.has_tag(&"scholarly") else 0.0
		TriggerRule.SuccessionMethod.ELECTIVE:
			w += 1.2 if p.has_tag(&"just") else 0.0
	if org.ideology != null \
			and org.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC \
			and p.has_tag(&"pious"):
		w += 1.5
	return maxf(0.1, w)


# ------------------------------------------------------------------ fallout

static func _maybe_break_away(org: Organization, candidates: Array[NotableIndividual],
		winner: NotableIndividual, tick: int, rule: TriggerRule) -> void:
	var rng := RngService.stream(&"rules")
	var chance := rule.schism_probability_on_loss if rule != null else DEFAULT_SCHISM_CHANCE_ON_LOSS
	for loser in candidates:
		if loser.person_id == winner.person_id:
			continue
		var personal_chance := chance * (1.8 if loser.has_tag(&"ambitious") else 0.6)
		if rng.randf() >= personal_chance:
			continue
		var split_rule := _succession_schism_rule(org, rule)
		SchismResolver.create_branch(org, split_rule, tick, loser)
		return   # one break-away per succession keeps the tree readable


## A synthetic rule describing "the losing claimant takes their followers and
## leaves". Authored rules cover pressures from the world; this one is internal
## to a contested succession, so it is built here rather than sitting in content.
static func _succession_schism_rule(org: Organization, base: TriggerRule) -> TriggerRule:
	var r := TriggerRule.new()
	r.rule_id = &"succession_breakaway"
	r.rule_type = TriggerRule.RuleType.SCHISM
	r.schism_kind = &"succession_dispute"
	r.applies_to_kind = org.kind
	r.inherited_member_fraction = Vector2(0.15, 0.4)
	r.ideology_drift_bias = {"tradition_reform": -0.2, "centralization": -0.25}
	r.branch_leadership_title = org.leadership_title
	r.chronicle_template = "{leader}は継承の裁定を認めず、{parent}を割って{branch}を立てた。"
	return r


static func _rule_for(org: Organization) -> TriggerRule:
	for rule in ContentRegistry.rules():
		if rule.rule_type != TriggerRule.RuleType.SUCCESSION:
			continue
		if rule.applies_to_kind != org.kind:
			continue
		if rule.applies_to_archetypes.is_empty() or rule.applies_to_archetypes.has(org.archetype_id):
			return rule
	return null


static func _previous_leader_id(org: Organization) -> StringName:
	# The seat is already cleared by the death, so the predecessor is whoever
	# most recently closed a tenure here.
	var best_tick := -1
	var best_id := &""
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		for t in p.role_history:
			if t.org_id == org.org_id and t.end_tick > best_tick:
				best_tick = t.end_tick
				best_id = p.person_id
	return best_id


## Nobody left to take the seat, so a new figure steps forward out of the ranks.
static func _raise_successor(org: Organization, tick: int) -> NotableIndividual:
	var rng := RngService.stream(&"rules")
	var p := NotableIndividual.new()
	p.person_id = GameState.mint_person_id()
	p.sex = "f" if rng.randf() < 0.5 else "m"
	p.family_name = NameGenerator.family_stem()
	p.full_name = "%s・%s" % [p.family_name, NameGenerator.given_name(p.sex)]
	p.birth_tick = tick - rng.randi_range(26, 44) * SimConfig.TICKS_PER_YEAR
	p.is_founder_generation = true
	p.house_org_id = org.org_id if org.kind == Organization.OrgKind.HOUSE else &""
	p.personality_tags = Demography.roll_personality(rng)
	HistoryLog.emit_event(
		HistoryEvent.EventType.BIRTH,
		p.birth_tick,
		"%sが生まれた。" % p.full_name,
		{"person": p.to_dict()},
		&"", p.person_id)
	return GameState.get_person(p.person_id)
