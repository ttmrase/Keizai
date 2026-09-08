class_name Demography
extends RefCounted

## Birth, marriage and death for named figures only. The general populace stays
## aggregate in SettlementState — this is the hybrid granularity the design calls
## for: enough individual detail to draw a real family tree, without simulating
## thousands of people.

## Above this many living notables in one lineage group, fertility falls off
## sharply. Without it the cast would grow without bound over a long game.
const CROWDING_SOFT_CAP := 42
const MAX_CHILDREN := 5


static func step(tick: int) -> void:
	_step_deaths(tick)
	_step_marriages(tick)
	_step_births(tick)


# --------------------------------------------------------------------- death

static func _step_deaths(tick: int) -> void:
	var rng := RngService.stream(&"demography")
	var mortality_mod := _mortality_modifier()
	# Snapshot first: recording a death mutates state through HistoryLog.
	var living := GameState.living_people()
	for p in living:
		var age := p.age_years(tick)
		var annual: float = 0.006 + pow(maxf(0.0, age - 45.0) / 45.0, 3.2) * 0.55
		annual *= mortality_mod
		var per_tick: float = annual / float(SimConfig.TICKS_PER_YEAR)
		if age >= SimConfig.MAX_AGE_YEARS or rng.randf() < per_tick:
			_record_death(p, tick, age)


static func _mortality_modifier() -> float:
	var world: WorldState = GameState.world
	var mod := 1.0
	# Famine and monsters kill the famous too, just more slowly than the poor.
	mod += world.global_unrest * 0.4
	mod += world.global_monster_threat_level * 0.5
	if world.global_harvest_modifier < 0.6:
		mod += (0.6 - world.global_harvest_modifier) * 1.2
	for inst in world.active_disasters:
		var def := ContentRegistry.get_disaster(inst.definition_id)
		if def != null and def.effects.has("mortality"):
			mod += float(def.effects["mortality"]) * inst.magnitude * 0.5
	return maxf(0.2, mod)


static func _record_death(p: NotableIndividual, tick: int, age: int) -> void:
	var role := ""
	var tenure := p.current_tenure()
	if tenure != null:
		var org := GameState.get_organization(tenure.org_id)
		if org != null:
			role = "%s%sの" % [org.display_name, tenure.title]
	HistoryLog.emit_event(
		HistoryEvent.EventType.DEATH,
		tick,
		"%s%sが%d歳で没した。" % [role, p.full_name, age],
		{"age": age},
		&"",
		p.person_id,
		p.birth_event_id)


# ------------------------------------------------------------------ marriage

static func _step_marriages(tick: int) -> void:
	var rng := RngService.stream(&"demography")
	var singles := _eligible_singles(tick)
	if singles.size() < 2:
		return
	for i in singles.size():
		var a: NotableIndividual = singles[i]
		if not a.spouse_ids.is_empty() or not a.is_alive():
			continue
		if rng.randf() > SimConfig.MARRIAGE_CHANCE_PER_TICK:
			continue
		var partner := _find_partner(a, singles, tick)
		if partner == null:
			continue
		HistoryLog.emit_event(
			HistoryEvent.EventType.MARRIAGE,
			tick,
			"%sと%sが婚姻を結んだ。" % [a.full_name, partner.full_name],
			{},
			&"",
			&"",
			&"",
			[a.person_id, partner.person_id] as Array[StringName])


static func _eligible_singles(tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in GameState.living_people():
		if p.spouse_ids.is_empty() and p.is_adult(tick) and p.age_years(tick) < 60:
			out.append(p)
	return out


static func _find_partner(a: NotableIndividual, pool: Array[NotableIndividual],
		tick: int) -> NotableIndividual:
	var eligible: Array[NotableIndividual] = []
	for b in pool:
		if b.person_id == a.person_id or b.sex == a.sex:
			continue
		if not b.spouse_ids.is_empty() or not b.is_alive():
			continue
		if _too_closely_related(a, b):
			continue
		eligible.append(b)
	if eligible.is_empty():
		return null
	# Pick at random rather than taking the first match: always pairing the
	# earliest-listed person funnels every marriage into one family line, and
	# within a few generations the whole world shares a surname.
	var weights: Array = []
	for b in eligible:
		weights.append(2.0 if b.family_name != a.family_name else 0.4)
	return RngService.pick_weighted(&"demography", eligible, weights)


static func _too_closely_related(a: NotableIndividual, b: NotableIndividual) -> bool:
	if a.father_id != &"" and a.father_id == b.father_id:
		return true
	if a.mother_id != &"" and a.mother_id == b.mother_id:
		return true
	if a.children_ids.has(b.person_id) or b.children_ids.has(a.person_id):
		return true
	if a.father_id == b.person_id or a.mother_id == b.person_id:
		return true
	if b.father_id == a.person_id or b.mother_id == a.person_id:
		return true
	return false


# --------------------------------------------------------------------- birth

static func _step_births(tick: int) -> void:
	var rng := RngService.stream(&"demography")
	var food_security: float = clampf(GameState.world.global_harvest_modifier, 0.0, 1.5)
	var crowding := _crowding_factor()

	for mother in GameState.living_people():
		if mother.sex != "f" or mother.spouse_ids.is_empty():
			continue
		var age := mother.age_years(tick)
		if age < SimConfig.ADULT_AGE_YEARS or age > 44:
			continue
		if mother.children_ids.size() >= MAX_CHILDREN:
			continue
		var father := GameState.get_person(mother.spouse_ids[0])
		if father == null or not father.is_alive():
			continue

		var fertility: float = SimConfig.BASE_FERTILITY_PER_TICK \
			* _age_fertility(age) * food_security * crowding
		if rng.randf() < fertility:
			_record_birth(mother, father, tick)


static func _age_fertility(age: int) -> float:
	if age < 20:
		return 0.6
	if age < 32:
		return 1.0
	if age < 38:
		return 0.7
	return 0.3


static func _crowding_factor() -> float:
	var living := GameState.living_people().size()
	if living <= CROWDING_SOFT_CAP:
		return 1.0
	return maxf(0.08, float(CROWDING_SOFT_CAP) / float(living))


static func _record_birth(mother: NotableIndividual, father: NotableIndividual, tick: int) -> void:
	var rng := RngService.stream(&"demography")
	var child := NotableIndividual.new()
	child.person_id = GameState.mint_person_id()
	child.sex = "f" if rng.randf() < 0.5 else "m"
	child.birth_tick = tick
	child.father_id = father.person_id
	child.mother_id = mother.person_id
	# Houses and commoner lines both pass the name down the paternal side.
	child.house_org_id = father.house_org_id if father.house_org_id != &"" else mother.house_org_id
	child.family_name = father.family_name if father.family_name != "" else mother.family_name
	var given := NameGenerator.given_name(child.sex)
	child.full_name = "%s・%s" % [child.family_name, given] if child.family_name != "" else given
	child.personality_tags = roll_personality(rng)

	HistoryLog.emit_event(
		HistoryEvent.EventType.BIRTH,
		tick,
		"%sに%sが生まれた。" % [mother.full_name, child.full_name],
		{"person": child.to_dict()},
		&"",
		child.person_id,
		mother.birth_event_id,
		[mother.person_id, father.person_id] as Array[StringName])


## Traits that later bias succession contests and the urge to break away.
static func roll_personality(rng: RandomNumberGenerator) -> Array[StringName]:
	const POOL: Array[StringName] = [
		&"ambitious", &"pious", &"cautious", &"martial", &"scholarly", &"greedy", &"just",
	]
	var tags: Array[StringName] = []
	var count := 1 if rng.randf() < 0.7 else 2
	for i in count:
		var pick: StringName = POOL[rng.randi_range(0, POOL.size() - 1)]
		if not tags.has(pick):
			tags.append(pick)
	return tags
