class_name Demography
extends RefCounted

## Birth, marriage and death for named figures only. The general populace stays
## aggregate in SettlementState — this is the hybrid granularity the design calls
## for: enough individual detail to draw a real family tree, without simulating
## thousands of people.

## Above this many living notables, fertility falls off sharply. Without a cap
## the cast grows without bound; set too low, and the houses cannot replace their
## own dead — nobody is ever created from nothing to make up the shortfall.
const CROWDING_SOFT_CAP := 165
const MAX_CHILDREN := 6

## The number of named figures the houses tend toward. Below it, families push
## urgently for heirs; above it, they stop. Without the lower half of this the
## population is only ever pushed downward, and one bad century ends the world —
## there is nobody to invent a replacement.
const NOTABLE_TARGET := 105
const SCARCITY_FERTILITY_BOOST := 2.4

## Famine and plague reach the great houses, but they eat before their tenants
## do. Left uncapped, a long famine kills every named figure in the world.
const MAX_MORTALITY_MODIFIER := 1.9

## Named figures eat before their tenants do. Famine still reaches them, but a
## bad harvest should not sterilise the aristocracy the way it starves the fields.
const NOTABLE_FOOD_INSULATION := 0.55


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
	return clampf(mod, 0.2, MAX_MORTALITY_MODIFIER)


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
	# When the houses are thin, matches are made quickly rather than waited on.
	var living := GameState.living_people().size()
	var urgency: float = 1.0 if living >= NOTABLE_TARGET \
		else 1.0 + (1.0 - float(living) / float(NOTABLE_TARGET)) * 3.0
	for i in singles.size():
		var a: NotableIndividual = singles[i]
		if not a.is_alive() or living_spouse(a) != null:
			continue
		if rng.randf() > SimConfig.MARRIAGE_CHANCE_PER_TICK * urgency:
			continue
		var partner := _find_partner(a, singles, tick)
		if partner == null:
			continue
		# A match across the line between the nobility and its servants is not
		# forbidden, only disowned. The couple are cast out first, so the marriage
		# that follows is recorded between the people they have become.
		var beneath := Retainers.is_match_beneath_rank(a, partner)
		var cast_out := beneath and HousePartition.try_elopement(a, partner, tick)
		HistoryLog.emit_event(
			HistoryEvent.EventType.MARRIAGE,
			tick,
			"%sと%sが婚姻を結んだ。%s" % [a.full_name, partner.full_name,
				"家格を越えた縁組であった。" if beneath and not cast_out else ""],
			{"across_rank": beneath, "cast_out": cast_out},
			&"",
			&"",
			&"",
			[a.person_id, partner.person_id] as Array[StringName])


## Anyone grown, alive, and without a living spouse. Widowhood is not the end of
## a line: remarriage is how houses survive a plague year, and forbidding it was
## enough on its own to make the whole notable population die out.
static func _eligible_singles(tick: int) -> Array[NotableIndividual]:
	var out: Array[NotableIndividual] = []
	for p in GameState.living_people():
		if p.is_adult(tick) and p.age_years(tick) < 62 and living_spouse(p) == null:
			out.append(p)
	return out


static func living_spouse(person: NotableIndividual) -> NotableIndividual:
	for spouse_id in person.spouse_ids:
		var spouse := GameState.get_person(spouse_id)
		if spouse != null and spouse.is_alive():
			return spouse
	return null


static func _find_partner(a: NotableIndividual, pool: Array[NotableIndividual],
		tick: int) -> NotableIndividual:
	var eligible: Array[NotableIndividual] = []
	for b in pool:
		if b.person_id == a.person_id or b.sex == a.sex:
			continue
		if not b.is_alive() or living_spouse(b) != null:
			continue
		if _too_closely_related(a, b):
			continue
		# The line between the nobility and its servants is a real refusal, not a
		# preference. A family with no equals left to marry may cross it; one
		# with options will not hear of it.
		if not Retainers.rank_allows(a, b):
			continue
		eligible.append(b)
	if eligible.is_empty():
		return null
	# Pick at random rather than taking the first match: always pairing the
	# earliest-listed person funnels every marriage into one family line, and
	# within a few generations the whole world shares a surname.
	#
	# Rank is the other half of it. A noble family marries its equals, and looks
	# below itself only when it has fallen out with everyone at its own level —
	# which is precisely when the line between the ranks gets crossed.
	var weights: Array = []
	for b in eligible:
		var weight: float = 2.0 if b.family_name != a.family_name else 0.4
		weights.append(weight * Retainers.match_weight(a, b))
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
	var harvest: float = clampf(GameState.world.global_harvest_modifier, 0.0, 1.5)
	var food_security: float = lerpf(harvest, 1.0, NOTABLE_FOOD_INSULATION)
	var crowding := _crowding_factor()

	for mother in GameState.living_people():
		if mother.sex != "f":
			continue
		var age := mother.age_years(tick)
		if age < SimConfig.ADULT_AGE_YEARS or age > 45:
			continue
		if mother.children_ids.size() >= MAX_CHILDREN:
			continue
		# The current husband, not the first one she ever had.
		var father := living_spouse(mother)
		if father == null:
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


## Pushes fertility down when there are too many named figures to follow, and up
## when the houses are close to dying out.
static func _crowding_factor() -> float:
	var living := GameState.living_people().size()
	if living > CROWDING_SOFT_CAP:
		return maxf(0.08, float(CROWDING_SOFT_CAP) / float(living))
	if living < NOTABLE_TARGET:
		var scarcity: float = 1.0 - float(living) / float(NOTABLE_TARGET)
		return 1.0 + scarcity * SCARCITY_FERTILITY_BOOST
	return 1.0


static func _record_birth(mother: NotableIndividual, father: NotableIndividual, tick: int) -> void:
	var rng := RngService.stream(&"demography")
	var child := NotableIndividual.new()
	child.person_id = GameState.mint_person_id()
	child.sex = "f" if rng.randf() < 0.5 else "m"
	child.birth_tick = tick
	child.father_id = father.person_id
	child.mother_id = mother.person_id
	# The child belongs to its father's house, and takes that house's name.
	child.house_org_id = father.house_org_id if father.house_org_id != &"" else mother.house_org_id
	# Whose blood they are, settled once and never revised. Where they live moves;
	# this does not.
	child.birth_house_org_id = child.house_org_id
	child.given_name = NameGenerator.given_name(child.sex)
	child.family_name = HouseNaming.surname_of(child.house_org_id)
	if child.family_name == "":
		child.family_name = father.family_name if father.family_name != "" else mother.family_name
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
