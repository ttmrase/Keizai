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
	return _resolve(person_id, {})


## The people whose ancestry does not terminate, checked in a single memoized
## pass. Doing this per person means re-walking the same ancestors thousands of
## times over — on a world with several thousand recorded lives that is not just
## slow, it used to exceed its own step limit and report failures that were not
## there.
static func ancestry_failures() -> Array[StringName]:
	var state := {}
	var out: Array[StringName] = []
	for id in GameState.people:
		if not _resolve(id, state):
			out.append(id)
	return out


## Depth-first with three states per person: in progress, sound, unsound. Meeting
## a person who is still in progress means the ancestry loops back on itself.
static func _resolve(person_id: StringName, state: Dictionary) -> bool:
	if person_id == &"":
		return true          # an unrecorded parent is a valid place to stop
	var known: int = state.get(person_id, -1)
	if known == 1:
		return true
	if known == 2:
		return false
	if known == 0:
		state[person_id] = 2
		return false         # a cycle: somebody is their own ancestor

	var p := GameState.get_person(person_id)
	if p == null:
		return false         # a parent that does not exist
	state[person_id] = 0

	var ok := true
	if not p.is_founder_generation:
		ok = _resolve(p.father_id, state) and _resolve(p.mother_id, state)
	state[person_id] = 1 if ok else 2
	return ok


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
