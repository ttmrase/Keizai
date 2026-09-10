extends Node

## The queryable projection of everything that has happened.
##
## Entity lifecycle and leadership are only ever mutated by `apply()`, which
## HistoryLog calls for each recorded event — so "who leads what, descended from
## whom" is always a fold over the event log and can never drift from it.
##
## Continuously varying numbers are deliberately outside that rule: resource
## stocks, populations, unrest, power scores and ideology drift are recomputed by
## their owning system every tick or epoch and captured by the snapshot. Logging
## a float that changes every tick would bloat the history for no narrative gain.

var world: WorldState
var organizations: Dictionary[StringName, Organization] = {}
var people: Dictionary[StringName, NotableIndividual] = {}

# Deterministic id counters. Persisted, so ids stay stable across save/load.
var _next_event_seq: int = 0
var _next_org_seq: int = 0
var _next_person_seq: int = 0
var _next_disaster_seq: int = 0


func _ready() -> void:
	world = WorldState.new()


# ---------------------------------------------------------------- id minting

func mint_event_id() -> StringName:
	_next_event_seq += 1
	return StringName("evt_%06d" % _next_event_seq)


func mint_org_id() -> StringName:
	_next_org_seq += 1
	return StringName("org_%04d" % _next_org_seq)


func mint_person_id() -> StringName:
	_next_person_seq += 1
	return StringName("per_%06d" % _next_person_seq)


func mint_disaster_id() -> StringName:
	_next_disaster_seq += 1
	return StringName("dis_%05d" % _next_disaster_seq)


# ------------------------------------------------------------------ queries

func get_organization(id: StringName) -> Organization:
	return organizations.get(id)


func get_person(id: StringName) -> NotableIndividual:
	return people.get(id)


func get_current_leader(org_id: StringName) -> NotableIndividual:
	var org: Organization = organizations.get(org_id)
	if org == null or org.leader_person_id == &"":
		return null
	return people.get(org.leader_person_id)


## Everyone who has ever held this body's seat, earliest first, with the years
## they held it. Nothing is stored for this — the tenures are already on the
## people, and a roll of past leaders is just a different way of reading them.
func leader_roll(org_id: StringName) -> Array:
	var out: Array = []
	for id in people:
		var p: NotableIndividual = people[id]
		for t in p.role_history:
			if t.org_id == org_id:
				out.append({"person": p, "tenure": t})
	out.sort_custom(func(a, b):
		var sa: int = a["tenure"].start_tick
		var sb: int = b["tenure"].start_tick
		return sa < sb if sa != sb else String(a["person"].person_id) < String(b["person"].person_id))
	return out


func organizations_of_kind(kind: Organization.OrgKind, only_active := true) -> Array[Organization]:
	var out: Array[Organization] = []
	for id in organizations:
		var o: Organization = organizations[id]
		if o.kind == kind and (not only_active or o.is_active()):
			out.append(o)
	return out


func active_organizations() -> Array[Organization]:
	var out: Array[Organization] = []
	for id in organizations:
		if organizations[id].is_active():
			out.append(organizations[id])
	return out


func root_of_kind(kind: Organization.OrgKind) -> Organization:
	for id in organizations:
		var o: Organization = organizations[id]
		if o.kind == kind and o.is_root():
			return o
	return null


## Named to avoid colliding with Node.get_children().
func child_organizations(org_id: StringName) -> Array[Organization]:
	var out: Array[Organization] = []
	var parent: Organization = organizations.get(org_id)
	if parent == null:
		return out
	for child_id in parent.child_org_ids:
		var c: Organization = organizations.get(child_id)
		if c != null:
			out.append(c)
	return out


func living_people() -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for id in people:
		if people[id].is_alive():
			out.append(people[id])
	return out


func house_members(house_id: StringName, only_living := true) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for id in people:
		var p: NotableIndividual = people[id]
		if p.house_org_id == house_id and (not only_living or p.is_alive()):
			out.append(p)
	return out


## Every seat in the world currently held by somebody of this family — the guild
## halls, the temples, the chamber, the throne.
##
## This is what a great house actually is, as distinct from what it owns: a
## family with three of its own at the head of things is running the country
## whatever its title says, and a duke with none of them is a duke and nothing
## else. Read from the tenures rather than stored, so it is never stale.
func offices_of_house(house_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if house_id == &"":
		return out
	for org in active_organizations():
		if org.kind == Organization.OrgKind.HOUSE:
			continue
		var holder: NotableIndividual = people.get(org.leader_person_id)
		if holder == null or not holder.is_alive() or holder.house_org_id != house_id:
			continue
		out.append({"org": org, "person": holder, "title": org.leadership_title})
	out.sort_custom(func(a, b):
		var x: Organization = a["org"]
		var y: Organization = b["org"]
		if x.kind != y.kind:
			return x.kind < y.kind
		return String(x.org_id) < String(y.org_id))
	return out


func children_of(person_id: StringName, only_living := true) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	var p: NotableIndividual = people.get(person_id)
	if p == null:
		return out
	for child_id in p.children_ids:
		var c: NotableIndividual = people.get(child_id)
		if c != null and (not only_living or c.is_alive()):
			out.append(c)
	return out


# -------------------------------------------------------- the single mutator

## Applies one recorded event to the projection. Called only by HistoryLog.record().
func apply(e: HistoryEvent) -> void:
	match e.event_type:
		HistoryEvent.EventType.FOUNDING, HistoryEvent.EventType.SCHISM:
			_apply_org_created(e)
		HistoryEvent.EventType.BIRTH:
			_apply_birth(e)
		HistoryEvent.EventType.MARRIAGE:
			_apply_marriage(e)
		HistoryEvent.EventType.DEATH:
			_apply_death(e)
		HistoryEvent.EventType.SUCCESSION:
			_apply_succession(e)
		HistoryEvent.EventType.POWER_TRANSFER:
			_apply_power_transfer(e)
		HistoryEvent.EventType.DISASTER_OCCURRED:
			_apply_disaster(e)
		HistoryEvent.EventType.DISSOLVED:
			_apply_dissolution(e)
		_:
			# IDEOLOGY_SHIFT, CONFLICT_*, RESOURCE_SHOCK and EPOCH_SUMMARY are
			# chronicle markers for values their owning system already changed.
			pass


func _apply_org_created(e: HistoryEvent) -> void:
	var org := Organization.from_dict(e.payload.get("organization", {}))
	org.origin_event_id = e.event_id
	if org.parent_org_id != &"":
		var parent: Organization = organizations.get(org.parent_org_id)
		if parent != null:
			org.branch_depth = parent.branch_depth + 1
			if not parent.child_org_ids.has(org.org_id):
				parent.child_org_ids.append(org.org_id)
			# A branch takes members and treasury with it.
			var taken := int(e.payload.get("inherited_members", 0))
			if taken > 0:
				parent.member_count = maxi(1, parent.member_count - taken)
			var taken_gold := float(e.payload.get("inherited_gold", 0.0))
			if taken_gold > 0.0:
				parent.resources[&"gold"] = maxf(0.0, parent.resources.get(&"gold", 0.0) - taken_gold)
			for raw_id in e.payload.get("seceded_settlements", []):
				var settlement_id := StringName(raw_id)
				parent.governs_settlement_ids.erase(settlement_id)
				var s: SettlementState = world.settlements.get(settlement_id)
				if s != null:
					s.controlling_org_id = org.org_id
	else:
		org.branch_depth = 0
	organizations[org.org_id] = org

	# A cadet branch takes a line of the family with it. Those people change
	# house, and therefore change surname — the split is visible in the names.
	for raw_id in e.payload.get("moved_person_ids", []):
		var person: NotableIndividual = people.get(StringName(raw_id))
		if person != null:
			HouseNaming.adopt_into_house(person, org.org_id)

	var leader: NotableIndividual = people.get(org.leader_person_id)
	if leader != null:
		_open_tenure(leader, org, e)


func _apply_birth(e: HistoryEvent) -> void:
	var p := NotableIndividual.from_dict(e.payload.get("person", {}))
	p.birth_event_id = e.event_id
	people[p.person_id] = p
	for parent_id in [p.father_id, p.mother_id]:
		var parent: NotableIndividual = people.get(parent_id)
		if parent != null and not parent.children_ids.has(p.person_id):
			parent.children_ids.append(p.person_id)


func _apply_marriage(e: HistoryEvent) -> void:
	if e.related_person_ids.size() < 2:
		return
	var a: NotableIndividual = people.get(e.related_person_ids[0])
	var b: NotableIndividual = people.get(e.related_person_ids[1])
	if a == null or b == null:
		return
	if not a.spouse_ids.has(b.person_id):
		a.spouse_ids.append(b.person_id)
	if not b.spouse_ids.has(a.person_id):
		b.spouse_ids.append(a.person_id)

	# Marriage is how houses acquire each other's blood: normally the bride joins
	# her husband's house and takes its name, so the surname on the family tree
	# always says which house someone belongs to now. The exception is a woman who
	# already heads a house — she does not leave it, and her husband marries in
	# instead, which is how a house with no sons survives.
	var husband: NotableIndividual = a if a.sex == "m" else b
	var wife: NotableIndividual = b if a.sex == "m" else a
	if husband.sex != "m" or wife.sex != "f":
		return
	if _heads_house(wife) and not _heads_house(husband):
		HouseNaming.adopt_into_house(husband, wife.house_org_id)
	elif husband.house_org_id != &"" and wife.house_org_id != husband.house_org_id \
			and not _heads_house(wife):
		HouseNaming.adopt_into_house(wife, husband.house_org_id)


func _heads_house(person: NotableIndividual) -> bool:
	var house: Organization = organizations.get(person.house_org_id)
	return house != null and house.is_active() and house.leader_person_id == person.person_id


func _apply_death(e: HistoryEvent) -> void:
	var p: NotableIndividual = people.get(e.subject_person_id)
	if p == null:
		return
	p.death_tick = e.tick
	p.death_event_id = e.event_id
	# Every seat, not the first one found: a monarch usually also heads their own
	# house, and closing only one leaves the other open forever — which reads, in
	# the roll of that body's leaders, as somebody still in office two centuries
	# after they died.
	for tenure in p.open_tenures():
		tenure.end_tick = e.tick
		tenure.end_event_id = e.event_id
	# The seat is left empty; a SUCCESSION event fills it.
	var org: Organization = organizations.get(p.house_org_id)
	for id in organizations:
		var o: Organization = organizations[id]
		if o.leader_person_id == p.person_id:
			o.leader_person_id = &""


func _apply_succession(e: HistoryEvent) -> void:
	var org: Organization = organizations.get(e.subject_org_id)
	var heir: NotableIndividual = people.get(e.subject_person_id)
	if org == null or heir == null:
		return
	var previous: NotableIndividual = people.get(StringName(e.payload.get("previous_leader_id", "")))
	if previous != null:
		var old_tenure := previous.tenure_in(org.org_id)
		if old_tenure != null:
			old_tenure.end_tick = e.tick
			old_tenure.end_event_id = e.event_id
	org.leader_person_id = heir.person_id
	_open_tenure(heir, org, e)

	# How the losing claimant took it. Standing down and being cut off are both
	# discrete facts about a person, like a leadership, so they change here and
	# nowhere else — folded into the succession they came out of rather than
	# recorded separately, because they are the same thing happening.
	var loser: NotableIndividual = people.get(StringName(e.payload.get("loser_id", "")))
	if loser == null:
		return
	var retire_from := StringName(e.payload.get("retire_from", ""))
	if retire_from != &"" and not loser.retired_from.has(retire_from):
		loser.retired_from.append(retire_from)
	if bool(e.payload.get("disinherit", false)):
		loser.disinherited_tick = e.tick
		var seat := loser.current_tenure()
		if seat != null:
			seat.end_tick = e.tick
			seat.end_event_id = e.event_id
		for id in organizations:
			var held: Organization = organizations[id]
			if held.leader_person_id == loser.person_id:
				held.leader_person_id = &""


func _apply_power_transfer(e: HistoryEvent) -> void:
	var to_org: Organization = organizations.get(e.subject_org_id)
	var from_org: Organization = organizations.get(StringName(e.payload.get("from_org_id", "")))
	var settlement_id := StringName(e.payload.get("settlement_id", ""))
	if to_org == null:
		return
	if bool(e.payload.get("regime_change", false)):
		_apply_regime_change(to_org, e)
		return
	if bool(e.payload.get("house_rising", false)):
		_apply_house_rising(to_org, e)
		return
	if settlement_id != &"":
		var s: SettlementState = world.settlements.get(settlement_id)
		if s != null:
			s.controlling_org_id = to_org.org_id
		if from_org != null:
			from_org.governs_settlement_ids.erase(settlement_id)
		if to_org.kind == Organization.OrgKind.POLITICAL_SYSTEM \
				and not to_org.governs_settlement_ids.has(settlement_id):
			to_org.governs_settlement_ids.append(settlement_id)
	if from_org != null:
		from_org.legitimacy = clampf(from_org.legitimacy - float(e.payload.get("legitimacy_cost", 0.1)), 0.0, 1.0)


## A retainer family becomes a noble one — by force, by blood, or by favour. The
## rank of a house is a discrete fact like a leadership, so it changes here and
## nowhere else; whatever it cost the family it displaced is settled here too.
func _apply_house_rising(risen: Organization, e: HistoryEvent) -> void:
	var source: Organization = organizations.get(StringName(e.payload.get("from_house_id", "")))
	risen.standing = Organization.Standing.NOBLE
	risen.liege_house_id = &""
	risen.loyalty = 1.0

	var seized := StringName(e.payload.get("seized_settlement", ""))
	if seized != &"":
		var s: SettlementState = world.settlements.get(seized)
		if s != null:
			s.ruling_house_id = risen.org_id
		if not risen.held_settlement_ids.has(seized):
			risen.held_settlement_ids.append(seized)
		if source != null:
			source.held_settlement_ids.erase(seized)
		if risen.dynasty_seat_settlement_id == &"":
			risen.dynasty_seat_settlement_id = seized

	if source != null and bool(e.payload.get("demote_source", false)):
		# The family that lost is not destroyed, only lowered — and lowered into
		# the service of the family that beat it, which is where the next
		# generation of grievance comes from.
		source.standing = Organization.Standing.RETAINER
		source.liege_house_id = risen.org_id
		source.loyalty = 0.2
		source.rank_tier = 0
		for settlement_id in source.held_settlement_ids.duplicate():
			var lost: SettlementState = world.settlements.get(settlement_id)
			if lost != null and lost.ruling_house_id == source.org_id:
				lost.ruling_house_id = risen.org_id
			if not risen.held_settlement_ids.has(settlement_id):
				risen.held_settlement_ids.append(settlement_id)
		source.held_settlement_ids.clear()

	# Everyone who served the risen house now serves it as a noble house.
	for id in organizations:
		var other: Organization = organizations[id]
		if other.liege_house_id == risen.org_id and other.org_id != risen.org_id:
			other.loyalty = maxf(other.loyalty, 0.5)


## A regime is overturned. What a country rests on and who decides in it are
## discrete institutional facts, not drifting values, so unlike ideology axes
## they change here — through the record — and nowhere else.
func _apply_regime_change(polity: Organization, e: HistoryEvent) -> void:
	if polity.ideology == null:
		return
	polity.ideology.legitimacy_basis = PoliticalSystemAxes.legitimacy_from_name(
		e.payload.get("legitimacy_basis", ""), polity.ideology.legitimacy_basis)
	polity.ideology.decision_structure = PoliticalSystemAxes.structure_from_name(
		e.payload.get("decision_structure", ""), polity.ideology.decision_structure)

	# The new order drags the country's ideals a long way toward its own — this
	# is a seizure, not a season's drift.
	var shift: Dictionary = e.payload.get("axis_shift", {})
	for key in shift:
		var axis := StringName(key)
		polity.ideology.set_axis(axis, lerpf(polity.ideology.get_axis(axis),
			float(shift[key]), RegimeShift.AXIS_SEIZURE))

	# What it was founded on is now this. Otherwise every later drift rule would
	# keep measuring the new regime against the beliefs of the one it replaced.
	polity.ideology_baseline = polity.ideology.clone()
	polity.legitimacy = RegimeShift.FRESH_LEGITIMACY

	if bool(e.payload.get("depose_ruler", false)):
		var ruler: NotableIndividual = people.get(polity.leader_person_id)
		if ruler != null:
			var tenure := ruler.tenure_in(polity.org_id)
			if tenure != null:
				tenure.end_tick = e.tick
				tenure.end_event_id = e.event_id
			# Turned out by the order that replaced them. They keep every claim
			# they had — but they carry the fallen regime with them, and whoever
			# comes next has to weigh that.
			if not ruler.deposed_from.has(polity.org_id):
				ruler.deposed_from.append(polity.org_id)
		# Left empty on purpose: the seat is filled again next tick under
		# whatever rules the country now runs on, which is the whole point.
		polity.leader_person_id = &""

	var named := PoliticalSystemGenerator.name_and_describe(polity)
	polity.display_name = named["display_name"]
	polity.description = named["description"]


func _apply_dissolution(e: HistoryEvent) -> void:
	var org: Organization = organizations.get(e.subject_org_id)
	if org == null or not org.is_active():
		return
	org.dissolved_tick = e.tick
	org.power_score = 0.0
	org.power_drivers.clear()
	var leader: NotableIndividual = people.get(org.leader_person_id)
	if leader != null:
		var tenure := leader.tenure_in(org.org_id)
		if tenure != null:
			tenure.end_tick = e.tick
			tenure.end_event_id = e.event_id
		# A state that fell rather than merely ended turned its head out, and
		# whoever comes next has to weigh that they were the last one.
		if bool(e.payload.get("depose_ruler", false)) \
				and not leader.deposed_from.has(org.org_id):
			leader.deposed_from.append(org.org_id)
	org.leader_person_id = &""
	# Whatever it still held reverts to the parent it broke away from.
	var parent: Organization = organizations.get(org.parent_org_id)
	if parent != null and parent.is_active():
		for settlement_id in org.governs_settlement_ids:
			if not parent.governs_settlement_ids.has(settlement_id):
				parent.governs_settlement_ids.append(settlement_id)
			var s: SettlementState = world.settlements.get(settlement_id)
			if s != null:
				s.controlling_org_id = parent.org_id
	org.governs_settlement_ids.clear()


func _apply_disaster(e: HistoryEvent) -> void:
	var inst := DisasterInstance.from_dict(e.payload.get("disaster", {}))
	world.active_disasters.append(inst)
	world.recent_disaster_pressure += 1.0


func _open_tenure(person: NotableIndividual, org: Organization, e: HistoryEvent) -> void:
	var t := RoleTenure.new()
	t.org_id = org.org_id
	t.title = org.leadership_title
	t.start_tick = e.tick
	t.start_event_id = e.event_id
	person.role_history.append(t)


# ------------------------------------------------------- continuous economy

## Advances every continuously varying number by one tick. Never touches
## leadership or lineage — those only change through recorded events.
func step_resources(tick: int) -> void:
	world.tick = tick
	var mods := _disaster_modifiers(tick)
	world.global_harvest_modifier = maxf(0.0, world.harvest_rate_modifier * float(mods.get("harvest", 1.0)))

	var total_ore := 0.0
	var total_wood := 0.0
	var total_food := 0.0
	var total_pop := 0.0
	var total_wealth := 0.0
	var unrest_weighted := 0.0

	var threat := world.global_monster_threat_level
	# A realm feeds its mining towns from its farming ones. Without this, any
	# region whose industry is not food simply starves to the floor and stays
	# there, which is not a country so much as eight unrelated villages.
	_redistribute_food()
	for id in world.settlements:
		var s: SettlementState = world.settlements[id]
		var pop := s.population

		# What a region produces depends on what it lives on: a mining valley
		# yields ore and little food, a farming one the reverse.
		var ore_gain: float = SimConfig.ORE_YIELD_PER_CAPITA * pop * world.ore_supply_rate \
			* float(mods.get("ore", 1.0)) * Industry.yield_modifier(s.industry, "ore")
		var wood_gain: float = SimConfig.WOOD_YIELD_PER_CAPITA * pop * world.wood_supply_rate \
			* float(mods.get("wood", 1.0)) * Industry.yield_modifier(s.industry, "wood")
		var food_gain: float = SimConfig.FOOD_YIELD_PER_CAPITA * pop * world.global_harvest_modifier \
			* Industry.yield_modifier(s.industry, "food")
		var food_use: float = SimConfig.FOOD_CONSUMPTION_PER_CAPITA * pop

		var ore_use: float = pop * SimConfig.ORE_USE_PER_CAPITA + s.local_ore * SimConfig.STOCK_SPOILAGE
		var wood_use: float = pop * SimConfig.WOOD_USE_PER_CAPITA + s.local_wood * SimConfig.STOCK_SPOILAGE
		s.local_ore = clampf(s.local_ore + ore_gain - ore_use, 0.0, SimConfig.MAX_LOCAL_STOCK)
		s.local_wood = clampf(s.local_wood + wood_gain - wood_use, 0.0, SimConfig.MAX_LOCAL_STOCK)
		s.food_stock += food_gain - food_use
		s.starving = s.food_stock < 0.0
		var starvation_severity := 0.0
		if s.starving:
			starvation_severity = clampf(-s.food_stock / maxf(1.0, food_use), 0.0, 1.0)
			s.food_stock = 0.0
		s.food_stock = minf(s.food_stock, SimConfig.MAX_FOOD_STOCK)

		s.wealth = clampf(
			s.wealth + (ore_gain * SimConfig.WEALTH_PER_ORE + wood_gain * SimConfig.WEALTH_PER_WOOD)
				* Industry.yield_modifier(s.industry, "wealth")
				- s.wealth * SimConfig.WEALTH_DECAY,
			0.0, SimConfig.MAX_WEALTH)

		var food_security := clampf(s.food_stock / maxf(1.0, food_use * 8.0), 0.0, 1.0)
		var birth_rate: float = SimConfig.BASE_BIRTH_RATE * (0.35 + 0.65 * food_security)
		var death_rate: float = SimConfig.BASE_DEATH_RATE \
			+ SimConfig.STARVATION_DEATH_RATE * starvation_severity \
			+ SimConfig.MONSTER_RAID_DAMAGE * threat
		death_rate *= float(mods.get("mortality", 1.0))
		s.population = clampf(pop * (1.0 + birth_rate - death_rate),
			SimConfig.MIN_POPULATION, SimConfig.MAX_POPULATION)

		var unrest_target: float = clampf(
			SimConfig.UNREST_FROM_STARVATION * starvation_severity
				+ SimConfig.UNREST_FROM_MONSTERS * threat
				+ SimConfig.UNREST_FROM_FAITH * Religion.friction_in(s),
			0.0, 1.0)
		s.unrest = move_toward(s.unrest, unrest_target, SimConfig.UNREST_ADJUST_RATE)

		total_ore += s.local_ore
		total_wood += s.local_wood
		total_food += s.food_stock
		total_pop += s.population
		total_wealth += s.wealth
		unrest_weighted += s.unrest * s.population

	world.global_ore = total_ore
	world.global_wood = total_wood
	world.global_food_stock = total_food
	world.global_population = total_pop
	world.global_wealth = total_wealth
	world.global_unrest = unrest_weighted / maxf(1.0, total_pop)

	_step_monsters(mods)
	_expire_disasters(tick)
	world.recent_disaster_pressure = maxf(0.0, world.recent_disaster_pressure * 0.9965)


## Moves food from regions with a surplus to regions running short, keeping some
## back for the effort. Only settlements under the same ruler share.
func _redistribute_food() -> void:
	var by_realm := {}
	for id in world.settlements:
		var s: SettlementState = world.settlements[id]
		var realm: StringName = s.controlling_org_id
		if not by_realm.has(realm):
			by_realm[realm] = []
		by_realm[realm].append(s)

	for realm in by_realm:
		var members: Array = by_realm[realm]
		if members.size() < 2:
			continue
		var needy: Array = []
		var donors: Array = []
		for s in members:
			var reserve: float = s.population * SimConfig.FOOD_CONSUMPTION_PER_CAPITA * 12.0
			if s.food_stock < reserve:
				needy.append([s, reserve - s.food_stock])
			elif s.food_stock > reserve:
				donors.append([s, s.food_stock - reserve])
		if needy.is_empty() or donors.is_empty():
			continue

		var available := 0.0
		for d in donors:
			available += d[1]
		var wanted := 0.0
		for n in needy:
			wanted += n[1]
		var moved: float = minf(available, wanted) * SimConfig.FOOD_SHARING_FRACTION

		for d in donors:
			d[0].food_stock -= moved * (d[1] / available)
		for n in needy:
			n[0].food_stock += moved * (n[1] / wanted) * SimConfig.FOOD_TRANSPORT_EFFICIENCY


func _step_monsters(mods: Dictionary) -> void:
	var m := world.global_monster_population
	var headroom := 1.0 - m / SimConfig.MONSTER_CARRYING_CAPACITY
	var spawn_pressure: float = world.monster_spawn_rate * float(mods.get("monster_spawn", 1.0))
	var growth: float = SimConfig.MONSTER_BASE_GROWTH * spawn_pressure * headroom
	m += m * growth
	m += SimConfig.MONSTER_BASELINE_SPAWN * spawn_pressure * maxf(0.0, headroom)
	m -= world.monster_suppression * SimConfig.MONSTER_CULL_PER_POWER
	m += float(mods.get("monster_influx", 0.0))
	world.global_monster_population = clampf(m, 0.0, SimConfig.MONSTER_CARRYING_CAPACITY * 1.5)

	# Saturating 0..1 threat: monsters matter relative to how many people they menace.
	var defenders := maxf(1.0, world.global_population * 0.08)
	world.global_monster_threat_level = world.global_monster_population \
		/ (world.global_monster_population + defenders)


func _disaster_modifiers(tick: int) -> Dictionary:
	var mods := {}
	var peak := 0.0
	for inst in world.active_disasters:
		if not inst.is_active(tick):
			continue
		var def: DisasterDefinition = ContentRegistry.get_disaster(inst.definition_id)
		if def == null:
			continue
		var intensity := def.intensity_at(inst.progress(tick)) * inst.magnitude
		peak = maxf(peak, intensity)
		for key in def.effects:
			var effect := float(def.effects[key]) * intensity
			if key == "monster_influx":
				mods[key] = float(mods.get(key, 0.0)) + effect
			else:
				# Multiplicative modifiers stack, so two droughts are worse than one.
				mods[key] = float(mods.get(key, 1.0)) * (1.0 + effect)
	world.peak_disaster_magnitude = peak
	return mods


func _expire_disasters(tick: int) -> void:
	var still_active: Array[DisasterInstance] = []
	for inst in world.active_disasters:
		if inst.is_active(tick):
			still_active.append(inst)
	world.active_disasters = still_active


# ------------------------------------------------------------ serialization

func reset() -> void:
	world = WorldState.new()
	organizations.clear()
	people.clear()
	_next_event_seq = 0
	_next_org_seq = 0
	_next_person_seq = 0
	_next_disaster_seq = 0


func to_dict() -> Dictionary:
	var orgs := {}
	for id in organizations:
		orgs[String(id)] = organizations[id].to_dict()
	var folks := {}
	for id in people:
		folks[String(id)] = people[id].to_dict()
	return {
		"world": world.to_dict(),
		"organizations": orgs,
		"people": folks,
		"next_event_seq": _next_event_seq,
		"next_org_seq": _next_org_seq,
		"next_person_seq": _next_person_seq,
		"next_disaster_seq": _next_disaster_seq,
	}


func from_dict(d: Dictionary) -> void:
	world = WorldState.from_dict(d.get("world", {}))
	organizations.clear()
	for id in d.get("organizations", {}):
		organizations[StringName(id)] = Organization.from_dict(d["organizations"][id])
	people.clear()
	for id in d.get("people", {}):
		people[StringName(id)] = NotableIndividual.from_dict(d["people"][id])
	_next_event_seq = int(d.get("next_event_seq", 0))
	_next_org_seq = int(d.get("next_org_seq", 0))
	_next_person_seq = int(d.get("next_person_seq", 0))
	_next_disaster_seq = int(d.get("next_disaster_seq", 0))
