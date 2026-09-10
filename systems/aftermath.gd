class_name Aftermath
extends RefCounted

## What becomes of people and families after the thing they belonged to falls.
##
## A chronicle that records a disinheritance and then says nothing more about the
## person is not a record of a life, it is a record of an argument. Somebody cut
## off from their family does not evaporate: another house takes them in, they
## marry away, their standing is worth enough that the realm recognises a line of
## their own — or nothing is offered, and they go down among the people, which is
## the outcome the whole rank exists to avoid.
##
## Every path here is chosen from things the world already knows — who is on good
## terms with whom, who has blood in common, what the person's name is worth —
## and every one of them is written down, so a family can be followed out of the
## record it was thrown out of.

const TAKEN_IN := &"taken_in"
const MARRIED_AWAY := &"married_away"
const NEW_HOUSE := &"new_house"
const COMMONER := &"commoner"
const RETIRED_HOME := &"retired_home"
const CHANGED_LIEGE := &"changed_liege"
const MASTERLESS := &"masterless"

const FATE_LABELS := {
	TAKEN_IN: "他家の預かり",
	MARRIED_AWAY: "他家へ嫁いだ",
	NEW_HOUSE: "新たな家を立てた",
	COMMONER: "市井に下った",
	RETIRED_HOME: "家に退いた",
}

## A house has to be on at least this good terms to take in somebody another
## family has just thrown out.
const SHELTER_RELATION := 0.15
## And the standing a person needs before the realm recognises a house in their
## own name instead.
const RECOGNITION_STANDING := 1.4
## Past this age nobody is married away to solve the problem.
const MARRIAGEABLE_UNTIL := 46


static func fate_label(fate: StringName) -> String:
	return FATE_LABELS.get(fate, "")


# --------------------------------------------------------------- individuals

## Where somebody goes after being cut off from the family that held them.
##
## Called by whoever did the cutting off, after the event that recorded it — not
## from inside the record, which is only allowed to apply what already happened.
static func settle_outcast(person: NotableIndividual, from_house: Organization,
		cause: StringName, tick: int) -> StringName:
	if person == null or not person.is_alive():
		return &""

	var fate := _recognise(person, from_house, cause, tick)
	if fate == &"":
		fate = _marry_away(person, from_house, tick)
	if fate == &"":
		fate = _shelter(person, from_house, tick)
	if fate == &"":
		fate = _cast_down(person, from_house, tick)
	person.fate = fate
	person.fate_tick = tick
	return fate


## Standing worth enough that the realm would rather have them inside it. The
## line they found begins in the service of the house that disowned them, which
## is the ordinary price of being recognised at all.
static func _recognise(person: NotableIndividual, from_house: Organization,
		cause: StringName, tick: int) -> StringName:
	if from_house == null or not HouseNaming.is_of_the_blood(person, from_house):
		return &""
	if _standing_of(person, from_house) < RECOGNITION_STANDING:
		return &""
	var rule := TriggerRule.new()
	rule.rule_id = &"house_recognition"
	rule.rule_type = TriggerRule.RuleType.SCHISM
	rule.schism_kind = &"recognition"
	rule.applies_to_kind = Organization.OrgKind.HOUSE
	rule.inherited_member_fraction = Vector2(0.05, 0.15)
	rule.ideology_drift_bias = {"tradition_reform": 0.2}
	rule.branch_leadership_title = from_house.leadership_title
	rule.chronicle_template = "{leader}は{parent}を出されたが、その家格を惜しまれ、{branch}として遇された。"
	if not SchismResolver.has_room_for_branch(from_house, rule):
		return &""
	var branch := SchismResolver.create_branch(from_house, rule, tick, person)
	if branch == null:
		return &""
	branch.standing = Organization.Standing.RETAINER
	branch.liege_house_id = from_house.org_id
	branch.loyalty = 0.35 if cause == &"disinheritance" else 0.5
	branch.rank_tier = 0
	branch.held_settlement_ids.clear()
	return NEW_HOUSE


## Married into a family that will have them. The marriage is recorded as any
## other, so the house they join takes them in by the ordinary rule and the
## family tree shows the join.
static func _marry_away(person: NotableIndividual, from_house: Organization,
		tick: int) -> StringName:
	if person.age_years(tick) > MARRIAGEABLE_UNTIL or not person.is_adult(tick):
		return &""
	if Demography.living_spouse(person) != null:
		return &""
	var partner := _best_match(person, from_house, tick)
	if partner == null:
		return &""
	HistoryLog.emit_event(
		HistoryEvent.EventType.MARRIAGE,
		tick,
		"%sは行き場を失い、%sに迎えられて%sと結ばれた。" % [person.full_name,
			_house_name(partner.house_org_id), partner.full_name],
		{"shelter_match": true},
		&"",
		&"",
		&"",
		[person.person_id, partner.person_id] as Array[StringName])
	return MARRIED_AWAY


static func _best_match(person: NotableIndividual, from_house: Organization,
		tick: int) -> NotableIndividual:
	var best: NotableIndividual = null
	var best_warmth := -INF
	for other in GameState.living_people():
		if other.sex == person.sex or not other.is_adult(tick):
			continue
		if other.age_years(tick) > MARRIAGEABLE_UNTIL:
			continue
		if Demography.living_spouse(other) != null or other.house_org_id == &"":
			continue
		var house := GameState.get_organization(other.house_org_id)
		if house == null or not house.is_active():
			continue
		if from_house != null and house.org_id == from_house.org_id:
			continue
		var warmth := _warmth(from_house, house)
		if warmth < SHELTER_RELATION:
			continue
		if warmth > best_warmth:
			best_warmth = warmth
			best = other
	return best


## Taken in without a marriage: a household on good terms with the one that threw
## them out, and glad enough of the connection to feed another mouth.
static func _shelter(person: NotableIndividual, from_house: Organization,
		tick: int) -> StringName:
	var best: Organization = null
	var best_warmth := -INF
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if from_house != null and house.org_id == from_house.org_id:
			continue
		if house.member_count <= 0:
			continue
		var warmth := _warmth(from_house, house)
		# Blood already in the house counts for more than goodwill does.
		if _has_kin_in(person, house):
			warmth += 0.5
		if warmth < SHELTER_RELATION:
			continue
		if warmth > best_warmth:
			best_warmth = warmth
			best = house
	if best == null:
		return &""
	HouseNaming.adopt_into_house(person, best.org_id)
	_take_the_household(person, best)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sに引き取られ、その名を名乗ることとなった。"
			% [person.full_name, best.display_name],
		{"shelter": true, "person_fate": String(TAKEN_IN)},
		best.org_id,
		person.person_id,
		best.origin_event_id)
	return TAKEN_IN


## Nobody would have them. A name is the whole of what the nobility is, and
## losing it is what falling out of it means.
static func _cast_down(person: NotableIndividual, from_house: Organization,
		tick: int) -> StringName:
	var kept := person.family_name
	person.house_org_id = &""
	_take_the_household(person, null)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sを引き取る家はなく、%sは上流の列を離れて市井に下った。"
			% [person.full_name, kept if kept != "" else person.given_name],
		{"cast_down": true, "person_fate": String(COMMONER),
			"from_house_id": String(from_house.org_id) if from_house != null else ""},
		from_house.org_id if from_house != null else &"",
		person.person_id,
		from_house.origin_event_id if from_house != null else &"")
	return COMMONER


## A ruler turned out of a seat that still has a family behind it has somewhere
## to go, and it is not interesting; a ruler with nothing behind them does.
static func settle_deposed(ruler: NotableIndividual, polity: Organization,
		tick: int) -> StringName:
	if ruler == null or not ruler.is_alive():
		return &""
	var house := GameState.get_organization(ruler.house_org_id)
	if house != null and house.is_active():
		ruler.fate = RETIRED_HOME
		ruler.fate_tick = tick
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sは%sの座を退き、%sに戻った。"
				% [ruler.full_name, polity.display_name, house.display_name],
			{"deposed_home": true, "person_fate": String(RETIRED_HOME)},
			house.org_id,
			ruler.person_id,
			house.origin_event_id)
		return RETIRED_HOME
	return settle_outcast(ruler, house, &"deposition", tick)


# -------------------------------------------------------------------- houses

## What a family in service does when the house it served is gone.
##
## Taking the county is the first answer and it is already somebody else's
## business — a household with a claim on vacant ground rises to hold it. This is
## for the ones with no claim: they find another master, and if the realm has no
## masters left to find, they stop being a house in service and become one more
## family among the people.
static func settle_masterless(house: Organization, tick: int) -> StringName:
	if house == null or house.standing != Organization.Standing.RETAINER:
		return &""
	var liege := GameState.get_organization(house.liege_house_id)
	if liege != null and liege.is_active():
		return &""

	var successor := _new_liege_for(house, liege)
	if successor != null:
		house.liege_house_id = successor.org_id
		# A household transferred rather than chosen starts cool: the new master
		# is not the one their grandfather swore to.
		house.loyalty = minf(house.loyalty, 0.45)
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sを頂く家は絶えた。%sは%sの下に移り、その家中に加わった。" % [
				liege.display_name if liege != null else "旧主",
				house.display_name, successor.display_name],
			{"changed_liege": true, "to_house_id": String(successor.org_id),
				"house_fate": String(CHANGED_LIEGE)},
			house.org_id,
			house.leader_person_id,
			house.origin_event_id)
		return CHANGED_LIEGE

	house.standing = Organization.Standing.COMMONER
	house.liege_house_id = &""
	house.rank_tier = 0
	house.favour = 0.0
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"仕えるべき家はどこにもなく、%sは士分を退いて民の列に戻った。" % house.display_name,
		{"lost_standing": true, "house_fate": String(MASTERLESS)},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)
	return MASTERLESS


## Whoever a masterless household would rather serve: the family it already has
## blood with, then whoever took its old master's ground, then the greatest house
## it is on any sort of terms with.
static func _new_liege_for(house: Organization, fallen: Organization) -> Organization:
	var best: Organization = null
	var best_claim := -INF
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.standing != Organization.Standing.NOBLE or not other.is_active():
			continue
		var claim := other.power_score * 0.01
		claim += _warmth(house, other)
		if _married_between(house, other):
			claim += 1.0
		if fallen != null and other.held_settlement_ids.has(fallen.dynasty_seat_settlement_id):
			claim += 0.8
		if house.dynasty_seat_settlement_id != &"" \
				and other.held_settlement_ids.has(house.dynasty_seat_settlement_id):
			claim += 1.2
		if claim > best_claim:
			best_claim = claim
			best = other
	return best


# ------------------------------------------------------------------- helpers

static func _warmth(a: Organization, b: Organization) -> float:
	if a == null or b == null:
		return 0.0
	return (HouseRelations.relation(a.org_id, b.org_id)
		+ HouseRelations.relation(b.org_id, a.org_id)) * 0.5


static func _married_between(a: Organization, b: Organization) -> bool:
	for member in GameState.house_members(a.org_id):
		for spouse_id in member.spouse_ids:
			var spouse := GameState.get_person(spouse_id)
			if spouse != null and spouse.house_org_id == b.org_id:
				return true
	return false


static func _has_kin_in(person: NotableIndividual, house: Organization) -> bool:
	for relative_id in [person.father_id, person.mother_id]:
		var relative := GameState.get_person(relative_id)
		if relative != null and relative.house_org_id == house.org_id:
			return true
	for spouse_id in person.spouse_ids:
		var spouse := GameState.get_person(spouse_id)
		if spouse != null and spouse.house_org_id == house.org_id:
			return true
	return false


static func _standing_of(person: NotableIndividual, from_house: Organization) -> float:
	var standing := HouseRank.precedence(from_house) * 0.2
	if person.ever_held_office():
		standing += 0.6
	if person.has_tag(&"ambitious"):
		standing += 0.4
	if person.has_tag(&"martial") or person.has_tag(&"scholarly"):
		standing += 0.3
	return standing


## Whatever happens to somebody happens to the person they are married to. A
## couple left in two different houses is a household split down the middle, and
## the family tree shows it as a pair with two surnames and no reason for it.
##
## The exception is the one that already governs marriage: somebody who heads a
## family of their own does not leave it, whatever becomes of their spouse.
static func _take_the_household(person: NotableIndividual, into: Organization) -> void:
	var spouse := Demography.living_spouse(person)
	if spouse == null:
		return
	var theirs := GameState.get_organization(spouse.house_org_id)
	if theirs != null and theirs.leader_person_id == spouse.person_id:
		return
	if into == null:
		spouse.house_org_id = &""
		return
	HouseNaming.adopt_into_house(spouse, into.org_id)


static func _house_name(house_org_id: StringName) -> String:
	var house := GameState.get_organization(house_org_id)
	return house.display_name if house != null else "他家"
