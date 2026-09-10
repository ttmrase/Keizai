class_name Retainers
extends RefCounted

## The rank between the people and the nobility, and the three ways out of it.
##
## Every founding noble house is attached three retainer families: not commoners
## any more, not nobles yet, and close enough to the great house to know exactly
## what they are missing. A retainer marries a noble only with difficulty, holds
## no county in their own name, and answers for their liege's decisions without
## making any.
##
## That gap is the point. A retainer house has somewhere to go, and three roads
## there:
##
##   revolt        loyalty gone and standing enough to take the seat by force
##   inheritance   so much of the liege's blood is theirs that the house is
##                 theirs in all but name, and nobody left is loyal enough to
##                 mind
##   patronage     a noble who seizes the state strips a rival and raises his own
##
## All three go through the record as ordinary events, so a family that rose in
## the third century is traceable in the fourth, and the peerage of any given
## year is a consequence of things that actually happened.

# --- loyalty ---
const LOYALTY_ADJUST := 0.05
const MARRIAGE_LOYALTY := 0.30
const LAND_LOYALTY := 0.20
const IDEOLOGY_LOYALTY := 0.30
const NEGLECT_PENALTY := 0.25

# --- revolt ---
## Loyalty below which a retainer house will consider turning on its liege.
const REVOLT_LOYALTY := 0.22
## And the standing it needs relative to that liege before the attempt is worth
## making.
const REVOLT_STRENGTH_RATIO := 0.85
const REVOLT_COOLDOWN := 320

# --- inheritance ---
## Share of a noble house's living blood that must descend from one retainer
## family before the house is theirs in all but name.
const INFILTRATION_SHARE := 0.5
const INFILTRATION_LOYALTY := 0.45


## Loyalty is cheap to keep current and worth keeping current. Working out whose
## blood a noble house is actually made of means walking three generations up
## from every living person, so it is asked rarely — a house does not quietly
## change hands between one season and the next either.
const DESCENT_INTERVAL := 40


static func refresh_all(tick: int) -> void:
	var retainers := _retainer_houses()
	if retainers.is_empty():
		return
	_raise_holders_for_unheld_land(retainers, tick)
	_keep_a_nobility(tick)
	for house in retainers:
		_settle_loyalty(house)

	var descent := {} if tick % DESCENT_INTERVAL != 0 else _descent_from_retainers()
	for house in retainers:
		if _try_revolt(house, tick):
			continue
		if not descent.is_empty():
			_try_inheritance(house, descent, tick)


## Land that no noble family holds gets one, raised out of the households that
## were already serving there.
##
## This is what keeps a nobility in the world at all. Every road upward converts
## one noble house into a retainer as it promotes another, and elopement pushes
## families downward with nothing coming back, so the rank drains: eight
## centuries in, a world could have thirty households and not one noble among
## them, no rank, no feuds between great families, and no candidate for a vacant
## county — since a retainer cannot take one until it has stopped being a
## retainer. Somebody has to hold the ground, and whoever does is thereafter
## noble, which is how the rank worked before anyone wrote it down.
static func _raise_holders_for_unheld_land(retainers: Array[Organization], tick: int) -> void:
	var risings: Array = []
	var promised := {}
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var holder := GameState.get_organization(s.ruling_house_id)
		# Only a county whose family is actually gone. A living holder keeps it,
		# whatever rank they have fallen to.
		if holder != null and holder.is_active():
			continue
		var claimant := _best_claimant_for(s, retainers, promised)
		if claimant == null:
			continue
		promised[claimant.org_id] = true
		risings.append([claimant, s])

	for entry in risings:
		var claimant: Organization = entry[0]
		var settlement: SettlementState = entry[1]
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sを頂く家は絶えた。仕えていた%sが跡を継ぎ、貴族の列に加わった。"
				% [settlement.display_name, claimant.display_name],
			{
				"house_rising": true,
				"seized_settlement": String(settlement.id),
				"reason": "succession_of_service",
				"legitimacy_cost": 0.0,
			},
			claimant.org_id,
			claimant.leader_person_id,
			claimant.origin_event_id)


## A crown cannot govern eight counties through one family. When the great houses
## have thinned past the point of holding the country between them, the greatest
## of the households still standing are raised until there are enough again —
## which is how a nobility has always replaced itself.
static func nobility_floor() -> int:
	return maxi(2, int(GameState.world.settlements.size() / 2))


static func _keep_a_nobility(tick: int) -> void:
	var nobles := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			nobles += 1
	var short := nobility_floor() - nobles
	if short <= 0:
		return

	var candidates := _retainer_houses()
	candidates.sort_custom(func(a, b):
		return a.power_score > b.power_score if not is_equal_approx(a.power_score, b.power_score) \
			else String(a.org_id) < String(b.org_id))
	for i in mini(short, candidates.size()):
		var risen: Organization = candidates[i]
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"諸家は数を減らしすぎた。%sが引き上げられ、貴族の列に加えられた。" % risen.display_name,
			{"house_rising": true, "reason": "thin_nobility", "legitimacy_cost": 0.0},
			risen.org_id,
			risen.leader_person_id,
			risen.origin_event_id)


## Whoever has a claim on a county whose family has died out — and only somebody
## who actually served there. There is no general claim: a household with no
## connection to the place has no more right to it than any other, and letting
## the greatest household left take every vacancy promotes the whole rank out of
## existence within a few centuries.
static func _best_claimant_for(settlement: SettlementState, retainers: Array[Organization],
		promised: Dictionary) -> Organization:
	var best: Organization = null
	var best_claim := -INF
	for house in retainers:
		if promised.has(house.org_id) or house.member_count <= 0:
			continue
		var served_here := house.liege_house_id == settlement.ruling_house_id
		var seated_here := house.dynasty_seat_settlement_id == settlement.id
		if not served_here and not seated_here:
			continue
		var claim: float = house.power_score + (60.0 if served_here else 0.0)
		if claim > best_claim:
			best_claim = claim
			best = house
	return best


static func _retainer_houses() -> Array[Organization]:
	var out: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.RETAINER:
			out.append(house)
	return out


# ------------------------------------------------------------------- loyalty

## How a retainer family currently feels about the house it serves. Read off what
## has actually passed between them — marriages made, land granted, ideals shared
## — rather than accumulated, so a liege that starts treating its retainers well
## gets the benefit within a generation.
static func _settle_loyalty(house: Organization) -> void:
	var liege := GameState.get_organization(house.liege_house_id)
	if liege == null or not liege.is_active():
		# A retainer with nobody to serve keeps its own counsel.
		house.loyalty = move_toward(house.loyalty, 0.5, LOYALTY_ADJUST)
		return

	var target := 0.25
	if _married_into(house, liege):
		target += MARRIAGE_LOYALTY
	if not house.held_settlement_ids.is_empty():
		target += LAND_LOYALTY
	if house.ideology != null and liege.ideology != null:
		var distance := house.ideology.ideological_distance(liege.ideology)
		target += IDEOLOGY_LOYALTY * clampf(1.0 - distance / 0.3, 0.0, 1.0)
	# A liege that has climbed while its retainers stayed where they were is
	# resented for it.
	if liege.rank_tier >= 3 and house.held_settlement_ids.is_empty():
		target -= NEGLECT_PENALTY
	house.loyalty = move_toward(house.loyalty, clampf(target, 0.0, 1.0), LOYALTY_ADJUST)


static func _married_into(house: Organization, liege: Organization) -> bool:
	for member in GameState.house_members(house.org_id):
		for spouse_id in member.spouse_ids:
			var spouse := GameState.get_person(spouse_id)
			if spouse != null and spouse.house_org_id == liege.org_id:
				return true
	return false


# -------------------------------------------------------------------- revolt

static func _try_revolt(house: Organization, tick: int) -> bool:
	if house.loyalty > REVOLT_LOYALTY:
		return false
	if tick - int(house.last_fired_tick.get(&"revolt", -999999)) < REVOLT_COOLDOWN:
		return false
	var liege := GameState.get_organization(house.liege_house_id)
	if liege == null or not liege.is_active() or liege.held_settlement_ids.is_empty():
		return false
	if house.power_score < liege.power_score * REVOLT_STRENGTH_RATIO:
		return false

	house.last_fired_tick[&"revolt"] = tick
	var seized: StringName = liege.held_settlement_ids[0]
	var settlement: SettlementState = GameState.world.settlements.get(seized)

	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sへの忠義を捨て、%sを実力で奪った。"
			% [house.display_name, liege.display_name,
				settlement.display_name if settlement != null else "その領"],
		{
			"house_rising": true,
			"seized_settlement": String(seized),
			"from_house_id": String(liege.org_id),
			"reason": "revolt",
			"legitimacy_cost": 0.12,
		},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)
	return true


# --------------------------------------------------------------- inheritance

## For each noble house, how much of its living blood came out of each retainer
## family. One sweep, so the check below is a lookup.
static func _descent_from_retainers() -> Dictionary:
	var out := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if not p.is_alive() or p.house_org_id == &"":
			continue
		var house := GameState.get_organization(p.house_org_id)
		if house == null or house.standing != Organization.Standing.NOBLE:
			continue
		var totals: Dictionary = out.get(p.house_org_id, {})
		totals["__all"] = int(totals.get("__all", 0)) + 1
		for origin in _retainer_origins(p):
			totals[origin] = int(totals.get(origin, 0)) + 1
		out[p.house_org_id] = totals
	return out


## The retainer families a person is descended from, within living memory. Only
## the nearer generations count: everyone is descended from everyone eventually,
## and a claim four centuries old is not a claim.
static func _retainer_origins(person: NotableIndividual) -> Array[StringName]:
	var out: Array[StringName] = []
	var frontier: Array = [[person.person_id, 0]]
	var seen := {}
	while not frontier.is_empty():
		var entry: Array = frontier.pop_front()
		var id: StringName = entry[0]
		var depth: int = entry[1]
		if id == &"" or depth > 3 or seen.has(id):
			continue
		seen[id] = true
		var p := GameState.get_person(id)
		if p == null:
			continue
		if depth > 0:
			var origin := GameState.get_organization(p.house_org_id)
			if origin != null and origin.standing == Organization.Standing.RETAINER \
					and not out.has(origin.org_id):
				out.append(origin.org_id)
		frontier.append([p.father_id, depth + 1])
		frontier.append([p.mother_id, depth + 1])
	return out


## A noble house that is mostly its retainers' blood, and whose retainers no
## longer feel much about it, changes hands without a sword being drawn.
static func _try_inheritance(house: Organization, descent: Dictionary, tick: int) -> bool:
	if house.loyalty > INFILTRATION_LOYALTY:
		return false
	var liege := GameState.get_organization(house.liege_house_id)
	if liege == null or not liege.is_active():
		return false
	var totals: Dictionary = descent.get(liege.org_id, {})
	var living := int(totals.get("__all", 0))
	if living < 3:
		return false
	if float(totals.get(house.org_id, 0)) / float(living) < INFILTRATION_SHARE:
		return false

	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sの血はすでに%sのものだった。家督は争いもなく移り、%sが貴族の座に就いた。"
			% [liege.display_name, house.display_name, house.display_name],
		{
			"house_rising": true,
			"from_house_id": String(liege.org_id),
			"demote_source": true,
			"reason": "inheritance",
			"legitimacy_cost": 0.0,
		},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)
	return true


# ------------------------------------------------------------------ patronage

## A house that has just taken the state strips a rival of its land and raises
## its own most loyal retainer in its place. Called by RegimeShift when the new
## order is a house rather than a guild or a movement.
static func reward_and_punish(winner_house: Organization, tick: int) -> void:
	if winner_house == null or winner_house.kind != Organization.OrgKind.HOUSE:
		return
	var rival := _strongest_rival_house(winner_house)
	var favourite := _most_loyal_retainer(winner_house)
	if rival == null or favourite == null or rival.held_settlement_ids.is_empty():
		return

	var taken: StringName = rival.held_settlement_ids[0]
	var settlement: SettlementState = GameState.world.settlements.get(taken)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sから%sを取り上げて位を落とし、腹心の%sを貴族に列した。"
			% [winner_house.display_name, rival.display_name,
				settlement.display_name if settlement != null else "その領",
				favourite.display_name],
		{
			"house_rising": true,
			"seized_settlement": String(taken),
			"from_house_id": String(rival.org_id),
			"demote_source": true,
			"reason": "patronage",
			"legitimacy_cost": 0.0,
		},
		favourite.org_id,
		favourite.leader_person_id,
		favourite.origin_event_id)


static func _strongest_rival_house(winner: Organization) -> Organization:
	var best: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.org_id == winner.org_id or house.standing != Organization.Standing.NOBLE:
			continue
		if HouseRelations.relation(winner.org_id, house.org_id) > -0.1:
			continue
		if best == null or house.power_score > best.power_score:
			best = house
	return best


static func _most_loyal_retainer(liege: Organization) -> Organization:
	var best: Organization = null
	for house in _retainer_houses():
		if house.liege_house_id != liege.org_id:
			continue
		if best == null or house.loyalty > best.loyalty:
			best = house
	return best


# ------------------------------------------------------------------- marriage

## How much a match between these two is worth considering. A retainer courting
## a noble is not forbidden, only unlikely — and it becomes likelier exactly when
## the great houses have fallen out with each other and have nowhere else to
## look, which is how the rank gets crossed in practice.
static func match_weight(a: NotableIndividual, b: NotableIndividual) -> float:
	var house_a := GameState.get_organization(a.house_org_id)
	var house_b := GameState.get_organization(b.house_org_id)
	if house_a == null or house_b == null:
		return 1.0
	if house_a.standing == house_b.standing:
		return 1.0
	var noble := house_a if house_a.standing == Organization.Standing.NOBLE else house_b
	var lesser := house_b if noble == house_a else house_a
	if lesser.standing != Organization.Standing.RETAINER:
		return 0.05          # a noble does not marry a commoner at all, ordinarily
	# A house on bad terms with every other noble family has to look downward —
	# and only then. Squared, because a family with one feud still has options
	# and a family with nothing but feuds does not.
	var isolation := isolation_of(noble)
	# Its own retainers are the ones it knows.
	var served := 1.8 if lesser.liege_house_id == noble.org_id else 1.0
	return (0.025 + isolation * isolation * 0.55) * served


## How isolated a noble family is: 0 when it is on good terms with the others,
## 1 when it is on bad terms with all of them. This is the number that decides
## both whether it will look below its rank for a match and whether it can afford
## to disown the pair afterwards.
static func isolation_of(house: Organization) -> float:
	var hostile := 0
	var total := 0
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.org_id == house.org_id or other.standing != Organization.Standing.NOBLE:
			continue
		total += 1
		if HouseRelations.relation(house.org_id, other.org_id) < -0.1:
			hostile += 1
	return 0.0 if total == 0 else float(hostile) / float(total)


## Whether a match across the rank line is entertained at all.
##
## Weighting it down is not enough: when every partner available to a noble is a
## retainer, a weighted draw still picks one with certainty, and the line gets
## crossed constantly. The rank has to be able to refuse.
static func rank_allows(a: NotableIndividual, b: NotableIndividual) -> bool:
	if not is_match_beneath_rank(a, b):
		return true
	return RngService.stream(&"demography").randf() < clampf(match_weight(a, b), 0.0, 1.0)


## Whether this match is one the noble family would disown the pair for.
static func is_match_beneath_rank(a: NotableIndividual, b: NotableIndividual) -> bool:
	var house_a := GameState.get_organization(a.house_org_id)
	var house_b := GameState.get_organization(b.house_org_id)
	if house_a == null or house_b == null:
		return false
	return house_a.standing != house_b.standing \
		and (house_a.standing == Organization.Standing.NOBLE
			or house_b.standing == Organization.Standing.NOBLE)


# -------------------------------------------------------------------- readers

static func retainers_of(liege_id: StringName) -> Array[Organization]:
	var out: Array[Organization] = []
	for house in _retainer_houses():
		if house.liege_house_id == liege_id:
			out.append(house)
	return out


## Whether an event is the private life of a family in service — a birth, a
## marriage, a death among the households below the nobility.
##
## Three retainer families under each of eight houses generate most of the
## domestic events in the world, and they bury everything else: a chronicle where
## the fall of a regime sits between two births in a knight's household is not a
## chronicle anybody reads. They get their own filter instead.
static func is_service_household_event(e: HistoryEvent) -> bool:
	match e.event_type:
		HistoryEvent.EventType.BIRTH, HistoryEvent.EventType.DEATH:
			return _serves(GameState.get_person(e.subject_person_id))
		HistoryEvent.EventType.MARRIAGE:
			if e.related_person_ids.is_empty():
				return false
			for id in e.related_person_ids:
				if not _serves(GameState.get_person(id)):
					return false
			return true
	return false


static func _serves(person: NotableIndividual) -> bool:
	if person == null:
		return false
	var house := GameState.get_organization(person.house_org_id)
	return house != null and house.standing == Organization.Standing.RETAINER


static func describe_loyalty(value: float) -> String:
	if value >= 0.75:
		return "忠実"
	if value >= 0.5:
		return "従順"
	if value >= 0.3:
		return "冷ややか"
	if value >= 0.15:
		return "不穏"
	return "叛意"
