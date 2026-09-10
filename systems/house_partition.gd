class_name HousePartition
extends RefCounted

## Why a family actually splits.
##
## Cadet branches used to appear because a rule's conditions happened to hold and
## a die came up short, which produced plenty of branches and no stories. A house
## divides for reasons anyone would recognise, and the reason ought to be legible
## in the chronicle a century later:
##
##   跡目不当   the heir is not up to it and a better sibling will not serve them
##   駆け落ち   a match beneath the family's rank that the family will not have,
##              so the couple leave with nothing and start again a rank lower
##
## Each writes its own sentence and its own kind of branch: the eloping couple
## are cast down to retainers, the passed-over sibling takes half the household
## with them.
##
## A head dying with only young children used to be a third cause here, and it
## was the wrong shape: what happens then is that the seat goes sideways and
## somebody is passed over, which is a contested succession. It lives in
## SuccessionResolver now, where the argument can end in a retirement instead of
## always costing the family a branch.

const CHECK_INTERVAL := 40

const UNFIT_COOLDOWN := 600
const ELOPEMENT_COOLDOWN := 120
## Above this much isolation the marriage is a decision rather than a scandal:
## the family needed it, and the couple stay.
const NEEDED_MATCH_ISOLATION := 0.5

## Traits that make somebody fit to hold a house, and the ones that do not.
const CAPABLE_TRAITS: Array[StringName] = [&"just", &"ambitious", &"scholarly", &"martial"]
const UNFIT_TRAITS: Array[StringName] = [&"greedy"]

## How much better the passed-over sibling has to be before it is worth a split.
const UNFIT_MARGIN := 2.0


static func step(tick: int) -> void:
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		# Staggered per family rather than checked for all of them on the same
		# tick. Asking every house at once means that whenever the conditions are
		# generally true, five families have the same crisis in the same season,
		# which reads as a bug because it is one.
		if (tick + absi(hash(house.org_id))) % CHECK_INTERVAL != 0:
			continue
		_try_unfit_heir(house, tick)


# ------------------------------------------------------------- an unfit heir

## The head of the house is not up to it, and a sibling who plainly is refuses to
## spend a life taking orders from them.
static func _try_unfit_heir(house: Organization, tick: int) -> bool:
	if tick - int(house.last_fired_tick.get(&"unfit_heir", -999999)) < UNFIT_COOLDOWN:
		return false
	var head := GameState.get_person(house.leader_person_id)
	if head == null or not head.is_alive():
		return false
	var head_fitness := _fitness(head)

	var challenger: NotableIndividual = null
	for member in GameState.house_members(house.org_id):
		if member.person_id == head.person_id or not member.is_adult(tick):
			continue
		if member.current_tenure() != null:
			continue
		if not _is_sibling(member, head):
			continue
		if challenger == null or _fitness(member) > _fitness(challenger):
			challenger = member
	if challenger == null or _fitness(challenger) - head_fitness < UNFIT_MARGIN:
		return false

	house.last_fired_tick[&"unfit_heir"] = tick
	var rule := _branch_rule(house, &"unfit_heir",
		"{leader}は兄姉の器量を認めず、{parent}を割って{branch}を立てた。",
		Vector2(0.3, 0.5), {"tradition_reform": 0.35, "centralization": -0.2})
	return SchismResolver.create_branch(house, rule, tick, challenger) != null


## Only a brother or sister disputes a headship this way; a cousin has no claim
## worth walking out over.
static func _is_sibling(a: NotableIndividual, b: NotableIndividual) -> bool:
	if a.father_id != &"" and a.father_id == b.father_id:
		return true
	return a.mother_id != &"" and a.mother_id == b.mother_id


static func _fitness(p: NotableIndividual) -> float:
	var score := 0.0
	for tag in p.personality_tags:
		if CAPABLE_TRAITS.has(tag):
			score += 1.5
		if UNFIT_TRAITS.has(tag):
			score -= 1.5
	return score


# ---------------------------------------------------------------- elopement

## A match the family will not have. The pair are not stopped — they are simply
## no longer of the house, and the branch they found starts a rank below the one
## they left. This is called from the marriage step, because the marriage is what
## causes it.
static func try_elopement(a: NotableIndividual, b: NotableIndividual, tick: int) -> bool:
	if not Retainers.is_match_beneath_rank(a, b):
		return false
	var noble_partner := a
	var lesser_partner := b
	var house_a := GameState.get_organization(a.house_org_id)
	if house_a == null or house_a.standing != Organization.Standing.NOBLE:
		noble_partner = b
		lesser_partner = a
	var noble_house := GameState.get_organization(noble_partner.house_org_id)
	if noble_house == null:
		return false
	if tick - int(noble_house.last_fired_tick.get(&"elopement", -999999)) < ELOPEMENT_COOLDOWN:
		return false
	# The head of a house is not disowned by it; anyone else is fair game.
	if noble_house.leader_person_id == noble_partner.person_id:
		return false
	# A family with nowhere else to look made this match on purpose and keeps the
	# couple. A family with options made no such decision, and disowns them.
	if Retainers.isolation_of(noble_house) >= NEEDED_MATCH_ISOLATION:
		return false

	noble_house.last_fired_tick[&"elopement"] = tick
	var rule := _branch_rule(noble_house, &"elopement",
		"{leader}は家格を越えた相手を選び、{parent}から除かれて{branch}となった。",
		Vector2(0.05, 0.15), {"tradition_reform": 0.5, "centralization": -0.4})
	var branch := SchismResolver.create_branch(noble_house, rule, tick, noble_partner)
	if branch == null:
		return false
	# Cast out, not merely separated: the new house begins in the service of the
	# one that disowned it, which is a debt its grandchildren will still be paying.
	branch.standing = Organization.Standing.RETAINER
	branch.liege_house_id = noble_house.org_id
	branch.loyalty = 0.3
	branch.rank_tier = 0
	branch.held_settlement_ids.clear()
	HouseNaming.adopt_into_house(lesser_partner, branch.org_id)
	return true


# ------------------------------------------------------------------- helpers

## A rule describing one particular family quarrel. These are not authored as
## content because they are not pressures from the world — they are things that
## go wrong inside a household, and the conditions are the household's own.
static func _branch_rule(house: Organization, kind: StringName, chronicle: String,
		inherited: Vector2, drift: Dictionary) -> TriggerRule:
	var r := TriggerRule.new()
	r.rule_id = StringName("house_%s" % kind)
	r.rule_type = TriggerRule.RuleType.SCHISM
	r.schism_kind = kind
	r.applies_to_kind = Organization.OrgKind.HOUSE
	r.inherited_member_fraction = inherited
	r.ideology_drift_bias = drift
	r.branch_leadership_title = house.leadership_title
	r.chronicle_template = chronicle
	return r


const REASON_LABELS := {
	&"unfit_heir": "跡目不当",
	&"minority": "幼君",
	&"elopement": "駆け落ち",
	&"succession_dispute": "継承争い",
	&"ideological_split": "思想の別れ",
	&"specialization": "専業化",
	&"radical_break": "決別",
	&"revelation": "啓示",
}


static func reason_label(schism_kind: StringName) -> String:
	return REASON_LABELS.get(schism_kind, "分派")
