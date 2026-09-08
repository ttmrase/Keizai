class_name WorldStateQuery
extends RefCounted

## Resolves the string paths that power profiles and rule conditions are written
## in terms of. Keeping this one small router is what lets a new archetype or a
## new social pressure be authored as a .tres file instead of engine code.
##
## Supported paths:
##   global_*                       any field on WorldState
##   org.self.<field>               a field on the organization being evaluated
##   org.self.ideology.<axis>       one of its ideology axes
##   org.self.ideology_drift        distance from its founding baseline
##   org.governed.<stat>            aggregate over settlements it governs
##   world.settlements.<stat>       aggregate over every settlement
##   count.archetype.<id>           how many active orgs use that archetype
##   count.children                 how many branches this organization has
##
## <stat> is one of: avg_unrest, max_unrest, avg_food_security, min_food_stock,
## avg_wealth, total_population, starving_fraction.

static func get_value(path: StringName, org: Organization = null) -> float:
	var p := String(path)
	var world: WorldState = GameState.world

	if p.begins_with("org.self."):
		if org == null:
			return 0.0
		var field := p.substr("org.self.".length())
		if field == "ideology_drift":
			if org.ideology == null or org.ideology_baseline == null:
				return 0.0
			return org.ideology.ideological_distance(org.ideology_baseline)
		if field.begins_with("ideology."):
			if org.ideology == null:
				return 0.0
			return org.ideology.get_axis(StringName(field.substr("ideology.".length())))
		if field == "governed_count":
			return float(org.governs_settlement_ids.size())
		if field == "held_count":
			return float(org.held_settlement_ids.size())
		if field == "legitimacy_basis":
			return 0.0 if org.ideology == null else float(org.ideology.legitimacy_basis)
		if field == "decision_structure":
			return 0.0 if org.ideology == null else float(org.ideology.decision_structure)
		var v = org.get(field)
		return float(v) if v != null else 0.0

	if p.begins_with("org.governed."):
		if org == null:
			return 0.0
		var ids := org.governs_settlement_ids
		if ids.is_empty() and org.dynasty_seat_settlement_id != &"":
			ids = [org.dynasty_seat_settlement_id]
		return _settlement_stat(_settlements_by_id(ids), p.substr("org.governed.".length()))

	if p.begins_with("world.settlements."):
		return _settlement_stat(_all_settlements(), p.substr("world.settlements.".length()))

	if p.begins_with("count.archetype."):
		var archetype := StringName(p.substr("count.archetype.".length()))
		var n := 0
		for o in GameState.active_organizations():
			if o.archetype_id == archetype:
				n += 1
		return float(n)

	if p == "count.children":
		return 0.0 if org == null else float(org.child_org_ids.size())

	# Share of all standing held by one kind of institution, 0..1. This is how a
	# form of government reads whether the houses, the guilds or the factions are
	# the ones actually holding the country up.
	if p.begins_with("power_share."):
		return _power_share(p.substr("power_share.".length()))

	# 1.0 when this archetype leads its own kind, 0.0 otherwise — "the temple is
	# the strongest faction", rather than any particular score.
	if p.begins_with("dominant_archetype."):
		return 1.0 if _dominant_archetype(StringName(p.substr("dominant_archetype.".length()))) else 0.0

	# Anything else is a plain WorldState field, which is most of them.
	var v = world.get(p)
	if v == null:
		push_warning("WorldStateQuery: unknown path '%s'" % p)
		return 0.0
	return float(v)


const _KIND_BY_NAME := {
	"guild": Organization.OrgKind.GUILD,
	"house": Organization.OrgKind.HOUSE,
	"faction": Organization.OrgKind.FACTION,
	"polity": Organization.OrgKind.POLITICAL_SYSTEM,
}


static func _power_share(kind_name: String) -> float:
	if not _KIND_BY_NAME.has(kind_name):
		push_warning("WorldStateQuery: unknown kind '%s'" % kind_name)
		return 0.0
	var wanted: int = _KIND_BY_NAME[kind_name]
	var total := 0.0
	var mine := 0.0
	for o in GameState.active_organizations():
		total += o.power_score
		if o.kind == wanted:
			mine += o.power_score
	return 0.0 if total <= 0.0 else mine / total


static func _dominant_archetype(archetype_id: StringName) -> bool:
	var subject: Organization = null
	for o in GameState.active_organizations():
		if o.archetype_id == archetype_id:
			subject = o
			break
	if subject == null:
		return false
	for o in GameState.active_organizations():
		if o.kind == subject.kind and o.power_score > subject.power_score:
			return false
	return true


static func _all_settlements() -> Array[SettlementState]:
	var out: Array[SettlementState] = []
	for id in GameState.world.settlements:
		out.append(GameState.world.settlements[id])
	return out


static func _settlements_by_id(ids: Array) -> Array[SettlementState]:
	var out: Array[SettlementState] = []
	for id in ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null:
			out.append(s)
	return out


static func _settlement_stat(list: Array[SettlementState], stat: String) -> float:
	if list.is_empty():
		return 0.0
	match stat:
		"avg_unrest":
			var total := 0.0
			for s in list:
				total += s.unrest
			return total / list.size()
		"max_unrest":
			var best := 0.0
			for s in list:
				best = maxf(best, s.unrest)
			return best
		"avg_food_security":
			var total := 0.0
			for s in list:
				var need: float = maxf(1.0, s.population * SimConfig.FOOD_CONSUMPTION_PER_CAPITA * 8.0)
				total += clampf(s.food_stock / need, 0.0, 1.0)
			return total / list.size()
		"min_food_stock":
			var lowest := INF
			for s in list:
				lowest = minf(lowest, s.food_stock)
			return lowest
		"avg_wealth":
			var total := 0.0
			for s in list:
				total += s.wealth
			return total / list.size()
		"total_population":
			var total := 0.0
			for s in list:
				total += s.population
			return total
		"starving_fraction":
			var n := 0
			for s in list:
				if s.starving:
					n += 1
			return float(n) / list.size()
	push_warning("WorldStateQuery: unknown settlement stat '%s'" % stat)
	return 0.0
