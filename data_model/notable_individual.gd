class_name NotableIndividual
extends Resource

## A named figure worth remembering: a monarch, house head, guild master, or
## faction leader — plus their relatives, so the family tree is complete.
##
## The general populace is never represented here; it stays aggregate in
## SettlementState. Ancestry always terminates: either at an empty parent id or
## at someone flagged `is_founder_generation`.

@export var person_id: StringName = &""
@export var full_name: String = ""
## Inherited surname. Members of a house take the house's name; commoner lines
## (guild masters, faction leaders) carry their own and pass it down the same way.
@export var family_name: String = ""
@export var sex: String = "f"          # "f" / "m"

@export var birth_tick: int = 0
@export var birth_event_id: StringName = &""
@export var death_tick: int = -1       # -1 = alive
@export var death_event_id: StringName = &""

# --- Genealogy ---
@export var father_id: StringName = &""
@export var mother_id: StringName = &""
@export var spouse_ids: Array[StringName] = []
@export var children_ids: Array[StringName] = []
## Seeded at world generation with no simulated parents. Ancestry walks stop here.
@export var is_founder_generation: bool = false

## Which house this person belongs to. Succession searches heirs within it.
@export var house_org_id: StringName = &""

## Open-ended traits that bias rule weights (e.g. &"ambitious", &"pious").
@export var personality_tags: Array[StringName] = []

@export var role_history: Array[RoleTenure] = []


func is_alive() -> bool:
	return death_tick < 0


func age_years(current_tick: int) -> int:
	var end_tick := current_tick if is_alive() else death_tick
	return int((end_tick - birth_tick) / SimConfig.TICKS_PER_YEAR)


func is_adult(current_tick: int) -> bool:
	return age_years(current_tick) >= SimConfig.ADULT_AGE_YEARS


func has_tag(tag: StringName) -> bool:
	return personality_tags.has(tag)


func current_tenure() -> RoleTenure:
	for t in role_history:
		if t.is_current():
			return t
	return null


func ever_held_office() -> bool:
	return not role_history.is_empty()


func to_dict() -> Dictionary:
	var roles: Array = []
	for r in role_history:
		roles.append(r.to_dict())
	var d := {
		"person_id": String(person_id),
		"full_name": full_name,
		"family_name": family_name,
		"sex": sex,
		"birth_tick": birth_tick,
		"birth_event_id": String(birth_event_id),
		"death_tick": death_tick,
		"father_id": String(father_id),
		"mother_id": String(mother_id),
		"spouse_ids": Organization._names_to_strings(spouse_ids),
		"children_ids": Organization._names_to_strings(children_ids),
		"house_org_id": String(house_org_id),
	}
	if death_event_id != &"":
		d["death_event_id"] = String(death_event_id)
	if is_founder_generation:
		d["is_founder_generation"] = true
	if not personality_tags.is_empty():
		d["personality_tags"] = Organization._names_to_strings(personality_tags)
	if not roles.is_empty():
		d["role_history"] = roles
	return d


static func from_dict(d: Dictionary) -> NotableIndividual:
	var p := NotableIndividual.new()
	p.person_id = StringName(d.get("person_id", ""))
	p.full_name = d.get("full_name", "")
	p.family_name = d.get("family_name", "")
	p.sex = d.get("sex", "f")
	p.birth_tick = int(d.get("birth_tick", 0))
	p.birth_event_id = StringName(d.get("birth_event_id", ""))
	p.death_tick = int(d.get("death_tick", -1))
	p.death_event_id = StringName(d.get("death_event_id", ""))
	p.father_id = StringName(d.get("father_id", ""))
	p.mother_id = StringName(d.get("mother_id", ""))
	p.spouse_ids = Organization._strings_to_names(d.get("spouse_ids", []))
	p.children_ids = Organization._strings_to_names(d.get("children_ids", []))
	p.is_founder_generation = bool(d.get("is_founder_generation", false))
	p.house_org_id = StringName(d.get("house_org_id", ""))
	p.personality_tags = Organization._strings_to_names(d.get("personality_tags", []))
	var roles: Array[RoleTenure] = []
	for r in d.get("role_history", []):
		roles.append(RoleTenure.from_dict(r))
	p.role_history = roles
	return p
