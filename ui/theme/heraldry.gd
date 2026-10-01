class_name Heraldry
extends RefCounted

## The colours a family flies, a faith wears and a state paints its borders in.
##
## Nothing in the simulation has a colour; this is purely how the screens tell
## forty families apart at a glance. Two rules pull against each other. A colour
## has to be stable — a house that is red on the map today and blue tomorrow is
## two houses to anybody watching — and two houses on the map at once must not
## share one, or the map says they are the same family.
##
## Hashing the id gives stability and collides constantly: eight families drawing
## from fourteen tinctures share one more often than not. So colours are handed
## out the way a herald would: the first time a body is seen it takes whichever
## tincture the bodies of its kind still standing are using least, and keeps it.
## Assignment walks ids in order, so the same world hands out the same colours.

const HOUSE_TINCTURES: Array[Color] = [
	Color("b8503f"),   # gules
	Color("4673ad"),   # azure
	Color("55904d"),   # vert
	Color("8a62b0"),   # purpure
	Color("c9a13c"),   # or
	Color("c77a3c"),   # tenné
	Color("3f948a"),   # teal
	Color("a34d72"),   # murrey
	Color("6fa8cc"),   # celeste
	Color("9c8a5a"),   # ochre
	Color("8c3f3f"),   # sanguine
	Color("d0889a"),   # rose
	Color("5e6fb8"),   # cobalt
	Color("7d9a3e"),   # olive
]

const FAITH_TINCTURES: Array[Color] = [
	Color("a89a7a"),   # the old ways: undyed linen
	Color("d6b04a"),   # harvest gold
	Color("7aa6d6"),   # warden blue
	Color("b86a9a"),   # ancestor rose
	Color("8a6fd0"),   # mystery violet
	Color("d05a4a"),   # apocalyptic red
	Color("5ab0a0"),   # pale teal
	Color("c8c8b0"),   # bone
]

const POLITY_TINCTURES: Array[Color] = [
	Color("9a6fc0"),
	Color("c0705a"),
	Color("5a8fc0"),
	Color("6fae6f"),
	Color("c0a050"),
	Color("b05a8a"),
]

const INDUSTRY_COLOURS := {
	&"mining": Color("8c95a6"),
	&"forestry": Color("4f8a52"),
	&"farming": Color("c8a64a"),
	&"trade": Color("c9853c"),
	&"frontier": Color("a8503f"),
}


static var _assigned: Dictionary = {}
static var _world_seed: int = -1


static func of_org(org: Organization) -> Color:
	if org == null:
		return Palette.TEXT_DIM
	var table := _table_for(org.kind)
	if table.is_empty():
		return Palette.for_kind(org.kind)
	if GameState.world.seed != _world_seed:
		_assigned.clear()
		_world_seed = GameState.world.seed
	if not _assigned.has(org.org_id):
		_settle(org.kind)
	return table[int(_assigned.get(org.org_id, 0)) % table.size()]


static func _table_for(kind: int) -> Array[Color]:
	match kind:
		Organization.OrgKind.HOUSE:
			return HOUSE_TINCTURES
		Organization.OrgKind.RELIGION:
			return FAITH_TINCTURES
		Organization.OrgKind.POLITICAL_SYSTEM:
			return POLITY_TINCTURES
	return []


## Hands a tincture to every body of this kind that has none yet, in id order,
## each taking whichever its living kin are using least.
static func _settle(kind: int) -> void:
	var table := _table_for(kind)
	var everyone := GameState.organizations_of_kind(kind, false)
	everyone.sort_custom(func(a, b): return String(a.org_id) < String(b.org_id))
	var in_use := {}
	for org in everyone:
		if org.is_active() and _assigned.has(org.org_id):
			var slot: int = _assigned[org.org_id]
			in_use[slot] = int(in_use.get(slot, 0)) + 1
	for org in everyone:
		if _assigned.has(org.org_id):
			continue
		var best := 0
		for slot in table.size():
			if int(in_use.get(slot, 0)) < int(in_use.get(best, 0)):
				best = slot
		_assigned[org.org_id] = best
		if org.is_active():
			in_use[best] = int(in_use.get(best, 0)) + 1


static func of_id(id: StringName) -> Color:
	return of_org(GameState.get_organization(id))


static func of_industry(industry: StringName) -> Color:
	return INDUSTRY_COLOURS.get(industry, Palette.TEXT_DIM)
