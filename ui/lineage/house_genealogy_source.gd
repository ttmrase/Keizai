class_name HouseGenealogySource
extends GenealogySource

## One family's own tree, rather than the whole world's.
##
## The seamless chart is the truthful view — everyone appears once, and the
## marriages between houses are visible as the joins they are — but it is also
## four centuries wide, and reading one family out of it means tracing a surname
## across a hundred boxes. This is that family on its own.
##
## Membership is exactly what the world already tracks: a person belongs to the
## house whose name they carry. So a bride who married in is here under her new
## surname, and a daughter who married out is not — she is in her husband's tree
## now, which is where the record says she belongs. The one addition is a spouse
## who kept their own house (a woman who heads hers, or a man who married one):
## they never joined, but the marriage did, and a household drawn with one half
## missing is not a household.

var house_id: StringName = &""


func members() -> Array[StringName]:
	var out: Array[StringName] = []
	if house_id == &"":
		return out
	var seen := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.house_org_id != house_id:
			continue
		out.append(id)
		seen[id] = true
	for id in out.duplicate():
		var p := GameState.get_person(id)
		if p == null:
			continue
		for spouse_id in p.spouse_ids:
			if seen.has(spouse_id) or GameState.get_person(spouse_id) == null:
				continue
			seen[spouse_id] = true
			out.append(spouse_id)
	return out


func all_ids() -> Array[StringName]:
	return members()


## The heads of this house, in the order they held it. A family of two hundred
## years is still a long chart, and the line of heads is its backbone.
func spine_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in members():
		var p := GameState.get_person(id)
		if p == null:
			continue
		for t in p.role_history:
			if t.org_id == house_id:
				out.append(id)
				break
	return out


func roots() -> Array[StringName]:
	var out: Array[StringName] = []
	var inside := {}
	for id in members():
		inside[id] = true
	for id in inside:
		var p := GameState.get_person(id)
		if p == null:
			continue
		if not inside.has(p.father_id) and not inside.has(p.mother_id):
			out.append(id)
	return out


func search(query: String) -> Array[StringName]:
	var needle := query.strip_edges()
	if needle.is_empty():
		return []
	var out: Array[StringName] = []
	for id in members():
		var p := GameState.get_person(id)
		if p != null and p.full_name.contains(needle):
			out.append(id)
	return out
