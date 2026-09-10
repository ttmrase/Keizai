class_name HouseRelations
extends RefCounted

## How the houses feel about each other, and why.
##
## Relations are not stored as opinions that drift on their own — they are read
## off things that actually happened. Two houses that have married into each
## other are bound together; two whose heads are competing for the same guild are
## not; two whose ideals have drifted apart find less and less to agree on. The
## value is recomputed rather than accumulated, so a feud ends when its causes do.

## Weights for each strand of the relationship. They sum to well over 1 before
## clamping, so one strong tie can carry a relationship on its own.
const MARRIAGE_WEIGHT := 0.26
const KINSHIP_WEIGHT := 0.20
const IDEOLOGY_WEIGHT := 0.42
const GUILD_RIVALRY_WEIGHT := 0.30
const SHARED_CAUSE_WEIGHT := 0.18
const CROWN_ENVY_WEIGHT := 0.22
## What the crown has said about a family, felt toward the crown itself: a house
## it has raised is grateful, a house it has stripped is not. This is the whole
## of what an honour buys, and the whole of what it costs.
const HONOUR_WEIGHT := 0.30
## And what the other great families think of a house that has knighted its whole
## household — a currency they also hold, cheapened by somebody else's generosity.
const INFLATION_WEIGHT := 0.28
## And what they believe. Worth nothing in a world that all prays the same way —
## agreeing costs nothing when there is nothing to disagree about — and a great
## deal in one that has just split down the middle.
const FAITH_WEIGHT := 0.34

const ADJUST_RATE := 0.12


static func refresh_all(tick: int) -> void:
	# Only the great families keep this kind of web with each other. A retainer
	# house has one relationship that matters and it is with its liege, which is
	# loyalty rather than standing — see Retainers.
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			houses.append(house)
	if houses.size() < 2:
		return

	# Everything each pair needs is gathered in one pass over people and one over
	# organizations. Computing it per pair instead means rescanning the whole
	# population dozens of times an epoch, which is most of a turn's budget.
	var facts := _gather(houses)

	for a in houses:
		for b in houses:
			if a.org_id == b.org_id:
				continue
			var target := _target_relation(a, b, facts)
			var current: float = a.house_relations.get(b.org_id, 0.0)
			# Ease toward the target so a single marriage does not flip a feud
			# into an alliance overnight.
			a.house_relations[b.org_id] = move_toward(current, target, ADJUST_RATE)


## One sweep of the world, indexed so each pair is then a dictionary lookup.
static func _gather(houses: Array[Organization]) -> Dictionary:
	var marriage_ties := {}     # "a|b" -> count
	var blood_ties := {}        # "a|b" -> true
	var free_adult := {}        # house id -> has an unoccupied grown member
	var office_holder := {}     # org id -> house of whoever holds it
	var members_in := {}        # "house|org" -> true

	var tick := SimClock.current_tick
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if not p.is_alive():
			continue
		var house := p.house_org_id
		if house == &"":
			continue

		var tenure := p.current_tenure()
		if tenure == null:
			if p.is_adult(tick):
				free_adult[house] = true
		else:
			members_in["%s|%s" % [house, tenure.org_id]] = true

		# Marriages count from the house someone was born into to the one they
		# live in, which is what actually binds two families together.
		for spouse_id in p.spouse_ids:
			var spouse := GameState.get_person(spouse_id)
			if spouse == null:
				continue
			var born := _birth_house_of(spouse)
			if born != &"" and born != house:
				var key := "%s|%s" % [house, born]
				marriage_ties[key] = int(marriage_ties.get(key, 0)) + 1

		for parent_id in [p.father_id, p.mother_id]:
			var parent := GameState.get_person(parent_id)
			if parent == null:
				continue
			var parent_house := _birth_house_of(parent)
			if parent_house != &"" and parent_house != house:
				blood_ties["%s|%s" % [house, parent_house]] = true
				blood_ties["%s|%s" % [parent_house, house]] = true

	for org in GameState.active_organizations():
		if org.kind == Organization.OrgKind.HOUSE:
			continue
		var holder := GameState.get_current_leader(org.org_id)
		if holder != null and holder.house_org_id != &"":
			office_holder[org.org_id] = holder.house_org_id

	# How far each family has titled its own servants above the world's ordinary
	# run. Worked out once here rather than per pair, which would rescan every
	# household in the world a hundred times an epoch.
	var over_titled := {}
	for house in houses:
		over_titled[house.org_id] = Honours.service_excess(house)

	return {
		"marriages": marriage_ties,
		"blood": blood_ties,
		"free_adult": free_adult,
		"office_holder": office_holder,
		"members_in": members_in,
		"crown": _crown_house_id(),
		"over_titled": over_titled,
	}


## The standing two houses ought to have, given everything currently true.
static func _target_relation(a: Organization, b: Organization, facts: Dictionary) -> float:
	var score := 0.0
	var key := "%s|%s" % [a.org_id, b.org_id]
	var reverse := "%s|%s" % [b.org_id, a.org_id]

	var marriages: int = int(facts["marriages"].get(key, 0)) \
		+ int(facts["marriages"].get(reverse, 0))
	if marriages > 0:
		score += MARRIAGE_WEIGHT * minf(1.0, float(marriages) / 3.0)
	if facts["blood"].has(key):
		score += KINSHIP_WEIGHT

	if a.ideology != null and b.ideology != null:
		# Neutral at a moderate distance, warm when they think alike, cold when
		# they have grown apart.
		var distance := a.ideology.ideological_distance(b.ideology)
		score += IDEOLOGY_WEIGHT * (1.0 - distance / 0.09)

	var contested := 0
	var shared := false
	for org_id in facts["office_holder"]:
		var holder_house: StringName = facts["office_holder"][org_id]
		if holder_house != a.org_id and holder_house != b.org_id:
			continue
		var rival: StringName = b.org_id if holder_house == a.org_id else a.org_id
		# A rival house with a grown, unoccupied member is a claim not pressed.
		if facts["free_adult"].has(rival):
			contested += 1
		if facts["members_in"].has("%s|%s" % [rival, org_id]):
			shared = true
	if contested > 0:
		score -= GUILD_RIVALRY_WEIGHT * minf(1.0, float(contested) / 2.0)
	elif shared:
		score += SHARED_CAUSE_WEIGHT

	# Whoever holds the crown is resented by the houses that do not.
	var crown: StringName = facts["crown"]
	if crown != &"" and (a.org_id == crown) != (b.org_id == crown):
		score -= CROWN_ENVY_WEIGHT
		# Except by whoever it has just honoured, and doubly by whoever it has
		# just put down. Only felt toward the crown: a favour from anybody else
		# is not a favour.
		var subject: Organization = b if a.org_id == crown else a
		score += HONOUR_WEIGHT * clampf(subject.honour, -1.0, 1.0)

	# A house that has titled its whole household is resented by its equals, who
	# hold the same coin and did not spend it.
	score -= INFLATION_WEIGHT * clampf(float(facts["over_titled"].get(b.org_id, 0.0)), 0.0, 1.0)

	# And what the two of them believe, once there is more than one answer.
	score += FAITH_WEIGHT * Religion.alignment(a, b)

	return clampf(score, -1.0, 1.0)


static func _crown_house_id() -> StringName:
	# The realm that actually governs, not the first one ever founded — a state
	# that has been refounded leaves the old one standing in the record with
	# nobody at its head.
	var polity := HouseRank.dominant_realm()
	if polity == null:
		return &""
	var monarch := GameState.get_current_leader(polity.org_id)
	return monarch.house_org_id if monarch != null else &""


## Which house someone was born into, as opposed to the one they married into.
static func _birth_house_of(person: NotableIndividual) -> StringName:
	var father := GameState.get_person(person.father_id)
	if father != null:
		return father.house_org_id
	return person.house_org_id


static func relation(a_id: StringName, b_id: StringName) -> float:
	var a := GameState.get_organization(a_id)
	if a == null:
		return 0.0
	return a.house_relations.get(b_id, 0.0)


static func describe(value: float) -> String:
	if value > 0.55:
		return "同盟"
	if value > 0.2:
		return "友好"
	if value > -0.2:
		return "中立"
	if value > -0.55:
		return "冷淡"
	return "対立"
