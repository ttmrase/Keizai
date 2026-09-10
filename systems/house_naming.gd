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
