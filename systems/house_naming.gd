class_name HouseNaming
extends RefCounted

## Surnames belong to houses, not to people.
##
## A person's family name is always the name of the house they belong to, so
## renaming a house renames everyone in it, and a cadet branch taking a name of
## its own gives that name to everyone who left with it. This is what makes a
## 分家 visible in the family tree: the branch stops sharing a surname with the
## line it came from.

const HOUSE_SUFFIX := "家"
const UJI_SUFFIX := "氏"


static func surname_of_name(house_display_name: String) -> String:
	return house_display_name.trim_suffix(HOUSE_SUFFIX)


static func surname_of(house_org_id: StringName) -> String:
	var house := GameState.get_organization(house_org_id)
	if house == null:
		return ""
	return surname_of_name(house.display_name)


## Moves a person into a house and restyles their name accordingly.
static func adopt_into_house(person: NotableIndividual, house_org_id: StringName) -> void:
	# Somebody who heads a family and then leaves it — married out, or gone with
	# a cadet branch — leaves the seat empty behind them. Without this the house
	# they left is still led by a person who is no longer of it, which is not a
	# thing a family tolerates and not a thing the record should show.
	var previous := GameState.get_organization(person.house_org_id)
	if previous != null and previous.org_id != house_org_id \
			and previous.leader_person_id == person.person_id:
		previous.leader_person_id = &""

	person.house_org_id = house_org_id
	GameState.note_house_move()
	person.family_name = surname_of(house_org_id)


## Whether somebody is of a family's own blood, as opposed to belonging to its
## household.
##
## Born to it, or born to a house this one is a cadet line of — a branch is a
## family going out of itself, so its founders and everyone who left with them
## are of its blood, and so is everyone born under the new name afterwards.
##
## What it excludes is everyone who came in from outside: a bride, a husband who
## married into a house with no sons, somebody another family took in. They carry
## the name and belong to the household, and the name is not theirs to inherit or
## to take away.
static func is_of_the_blood(person: NotableIndividual, house: Organization) -> bool:
	if person == null or house == null:
		return false
	if person.birth_house_org_id == &"":
		return person.house_org_id == house.org_id
	var walk := house
	var guard := 0
	while walk != null and guard < 32:
		if walk.org_id == person.birth_house_org_id:
			return true
		walk = GameState.get_organization(walk.parent_org_id)
		guard += 1
	return false


## Re-applies a house's surname to every living member. Called after a rename and
## after a branch takes its members with it.
static func restyle_members(house_org_id: StringName) -> int:
	var surname := surname_of(house_org_id)
	var changed := 0
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.house_org_id == house_org_id and p.family_name != surname:
			p.family_name = surname
			changed += 1
	return changed


# ---------------------------------------------------------------------- 氏

## 氏 — where a family comes from, written on its name.
##
## Only the great houses that held a region when the world began found a 氏,
## and its name is theirs: ネシ家 founds ネシ氏. Every family after them — a
## cadet line, an eloping couple, a disinherited son recognised in his own
## name, the households that served them at the start — carries the 氏 of the
## house it came out of, and keeps it whatever happens to it afterwards. So the
## name says where a house came from: ネシ氏カベ家 is a ネシ family whatever it
## is called and whomever it serves.
##
## The 氏 is a pointer to the house that founded it, never a copy of its name,
## so renaming that house renames the 氏 everywhere at once.


## The house that founded this family's 氏, or null.
static func uji_house(house: Organization) -> Organization:
	if house == null or house.kind != Organization.OrgKind.HOUSE or house.uji_id == &"":
		return null
	return GameState.get_organization(house.uji_id)


## Whether this house is the one that founded its 氏 (宗家).
static func founded_uji(house: Organization) -> bool:
	return house != null and house.uji_id != &"" and house.uji_id == house.org_id


## "ネシ" — the 氏 by itself, from the id of the house that founded it.
static func uji_surname(uji_id: StringName) -> String:
	return surname_of(uji_id)


## "ネシ氏".
static func uji_label(uji_id: StringName) -> String:
	var surname := uji_surname(uji_id)
	return surname + UJI_SUFFIX if surname != "" else ""


## A house's name in full: ネシ家 for the house that founded the 氏, and
## ネシ氏コド家 for every other.
static func house_label(house: Organization) -> String:
	if house == null:
		return ""
	if house.kind != Organization.OrgKind.HOUSE or house.uji_id == &"" or founded_uji(house):
		return house.display_name
	var uji := uji_surname(house.uji_id)
	if uji == "":
		return house.display_name
	return uji + UJI_SUFFIX + house.display_name


## A person's name in full: ネシ・名 for somebody of the house that founded the
## 氏, ネシ氏コド・名 for anyone else. Somebody outside every house keeps the
## surname they last had, alone.
static func person_formal_name(person: NotableIndividual) -> String:
	if person.family_name == "":
		return person.given_name
	var short := "%s・%s" % [person.family_name, person.given_name]
	var house := GameState.get_organization(person.house_org_id)
	if house == null or house.uji_id == &"" or founded_uji(house):
		return short
	var uji := uji_surname(house.uji_id)
	if uji == "":
		return short
	return "%s%s%s・%s" % [uji, UJI_SUFFIX, person.family_name, person.given_name]


## The 氏 line a person's card carries above their own name ("ネシ氏"), or empty
## when the name itself already says it — somebody of the founding house.
static func person_uji_line(person: NotableIndividual) -> String:
	if person == null:
		return ""
	var house := GameState.get_organization(person.house_org_id)
	if house == null or house.uji_id == &"" or founded_uji(house):
		return ""
	return uji_label(house.uji_id)


## The 氏 a new family takes: that of the house it came out of. Never chosen,
## never changed afterwards.
static func uji_for_branch(parent: Organization) -> StringName:
	if parent == null or parent.kind != Organization.OrgKind.HOUSE:
		return &""
	return parent.uji_id if parent.uji_id != &"" else parent.org_id


## Every family of one 氏, living and extinct, the founding house first and the
## rest in the order they were founded.
static func houses_of_uji(uji_id: StringName, only_active := false) -> Array[Organization]:
	var out: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, only_active):
		if house.uji_id == uji_id:
			out.append(house)
	out.sort_custom(func(a: Organization, b: Organization):
		if (a.org_id == uji_id) != (b.org_id == uji_id):
			return a.org_id == uji_id
		if a.founding_tick != b.founding_tick:
			return a.founding_tick < b.founding_tick
		return String(a.org_id) < String(b.org_id))
	return out


## "ネシ氏（宗家ネシ家／現存4家・断絶2家）" — one line saying what a 氏 is.
static func uji_summary(uji_id: StringName) -> String:
	var founder := GameState.get_organization(uji_id)
	if founder == null:
		return ""
	var living := 0
	var extinct := 0
	for house in houses_of_uji(uji_id):
		if house.is_active():
			living += 1
		else:
			extinct += 1
	var text := "%s（宗家%s／現存%d家" % [uji_label(uji_id), founder.display_name, living]
	if extinct > 0:
		text += "・断絶%d家" % extinct
	return text + "）"


## Every 氏 in the world: the ids of the houses that founded one, in order.
static func all_uji() -> Array[StringName]:
	var out: Array[StringName] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false):
		if founded_uji(house):
			out.append(house.org_id)
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out


## Fills in the 氏 of every house that has none — a save written before there
## were 氏. Deterministic, and decided from the permanent record where it can be:
## the founding of each house is in the backbone with the standing it was founded
## at, which says which houses were the great houses of the first day. Failing
## that, those houses are the first ones minted, one per region.
##
## Returns how many houses were given a 氏.
static func migrate_uji() -> int:
	var houses := GameState.organizations_of_kind(Organization.OrgKind.HOUSE, false)
	var missing := 0
	for house in houses:
		if house.uji_id == &"":
			missing += 1
	if missing == 0:
		return 0

	var founders := {}
	var founding_events := {}
	for e in HistoryLog.backbone:
		if e.event_type != HistoryEvent.EventType.FOUNDING or e.tick > 0:
			continue
		var org: Dictionary = e.payload.get("organization", {})
		if String(org.get("kind", "")) != "HOUSE":
			continue
		founding_events[StringName(org.get("org_id", ""))] = org
	for id in founding_events:
		var org: Dictionary = founding_events[id]
		# Founded as a great house: no standing written means noble, and no
		# liege. The households founded beside them carry RETAINER and a liege.
		if String(org.get("standing", "NOBLE")) == "NOBLE" \
				and String(org.get("liege_house_id", "")) == "":
			founders[id] = true
	if founders.is_empty():
		# No backbone to read: the great houses were minted first, one per region.
		var by_id := houses.duplicate()
		by_id.sort_custom(func(a: Organization, b: Organization):
			return String(a.org_id) < String(b.org_id))
		var regions := GameState.world.settlements.size()
		for house in by_id:
			if founders.size() >= regions:
				break
			if house.founding_tick == 0:
				founders[house.org_id] = true

	var given := 0
	for house in houses:
		if house.uji_id == &"" and founders.has(house.org_id):
			house.uji_id = house.org_id
			given += 1
	# Everyone else takes the 氏 of the house they came out of. Walked in order of
	# founding so a parent is always settled before its branches.
	var ordered := houses.duplicate()
	ordered.sort_custom(func(a: Organization, b: Organization):
		if a.founding_tick != b.founding_tick:
			return a.founding_tick < b.founding_tick
		return String(a.org_id) < String(b.org_id))
	for house in ordered:
		if house.uji_id != &"":
			continue
		var walk := GameState.get_organization(house.parent_org_id)
		var guard := 0
		while walk != null and walk.uji_id == &"" and guard < 64:
			walk = GameState.get_organization(walk.parent_org_id)
			guard += 1
		house.uji_id = walk.uji_id if walk != null else house.org_id
		given += 1
	return given
