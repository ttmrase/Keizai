class_name GenealogyValidator
extends RefCounted

## Checks the two traceability promises the whole design rests on: every
## organization reaches the single root of its kind, and every person's ancestry
## terminates at the founding generation. Used by the headless invariant suite
## and by the debug panel.

const MAX_WALK := 4096


## Walks parent_org_id up from `org_id`, returning the chain including the start.
## Returns an empty array if the chain cycles or dangles.
static func org_lineage(org_id: StringName) -> Array[Organization]:
	var chain: Array[Organization] = []
	var seen := {}
	var current: Organization = GameState.get_organization(org_id)
	var steps := 0
	while current != null and steps < MAX_WALK:
		if seen.has(current.org_id):
			return []          # cycle
		seen[current.org_id] = true
		chain.append(current)
		if current.is_root():
			return chain
		var parent := GameState.get_organization(current.parent_org_id)
		if parent == null:
			return []          # dangling parent reference
		current = parent
		steps += 1
	return []


static func traces_to_root(org_id: StringName) -> bool:
	return not org_lineage(org_id).is_empty()


static func root_ancestor(org_id: StringName) -> Organization:
	var chain := org_lineage(org_id)
	return chain[chain.size() - 1] if not chain.is_empty() else null


## True when the person's ancestry terminates properly: every path upward ends at
## an empty parent id or at someone marked as founding generation, with no cycles.
static func trace_to_founder(person_id: StringName) -> bool:
	var seen := {}
	var frontier: Array[StringName] = [person_id]
	var steps := 0
	while not frontier.is_empty() and steps < MAX_WALK:
		steps += 1
		var id: StringName = frontier.pop_back()
		if id == &"":
			continue
		if seen.has(id):
			continue           # already validated this branch of the tree
		seen[id] = true
		var p := GameState.get_person(id)
		if p == null:
			return false       # dangling parent reference
		if p.is_founder_generation:
			continue
		if p.father_id != &"":
			if p.father_id == id:
				return false
			frontier.append(p.father_id)
		if p.mother_id != &"":
			if p.mother_id == id:
				return false
			frontier.append(p.mother_id)
	return steps < MAX_WALK


## Every ancestor of a person, nearest first. Used by the family tree's focus mode.
static func ancestors(person_id: StringName, max_depth: int = 6) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	var seen := {}
	var frontier: Array = [[person_id, 0]]
	while not frontier.is_empty():
		var entry: Array = frontier.pop_front()
		var id: StringName = entry[0]
		var depth: int = entry[1]
		if depth > max_depth or id == &"" or seen.has(id):
			continue
		seen[id] = true
		var p := GameState.get_person(id)
		if p == null:
			continue
		if depth > 0:
			out.append(p)
		frontier.append([p.father_id, depth + 1])
		frontier.append([p.mother_id, depth + 1])
	return out


static func descendants(person_id: StringName, max_depth: int = 6) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	var seen := {}
	var frontier: Array = [[person_id, 0]]
	while not frontier.is_empty():
		var entry: Array = frontier.pop_front()
		var id: StringName = entry[0]
		var depth: int = entry[1]
		if depth > max_depth or id == &"" or seen.has(id):
			continue
		seen[id] = true
		var p := GameState.get_person(id)
		if p == null:
			continue
		if depth > 0:
			out.append(p)
		for child_id in p.children_ids:
			frontier.append([child_id, depth + 1])
	return out


## Walks up to the earliest traceable ancestor — what "Jump to Founder" uses.
static func founder_of(person_id: StringName) -> NotableIndividual:
	var current := GameState.get_person(person_id)
	var seen := {}
	while current != null and not seen.has(current.person_id):
		seen[current.person_id] = true
		if current.is_founder_generation:
			return current
		var next := GameState.get_person(current.father_id)
		if next == null:
			next = GameState.get_person(current.mother_id)
		if next == null:
			return current
		current = next
	return current
