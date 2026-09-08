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
	person.house_org_id = house_org_id
	person.family_name = surname_of(house_org_id)


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
