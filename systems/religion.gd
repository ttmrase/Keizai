class_name Religion
extends RefCounted

## What people believe, and how a belief becomes an institution.
##
## The world opens on an animism with no priests, no doctrine and no seat to
## fill — not an organization so much as the absence of one. It is the root of
## the lineage for its kind, so every later faith traces back to it, and it never
## goes away entirely: where nothing organized has answered the life people are
## actually living, this is what remains.
##
## Organized faiths derive from it, and from each other, by the same schism
## machinery that produces guilds and factions — the conditions are authored in
## data/rules/faith_*.tres. What makes them faiths rather than factions is what
## they do next: every region holds one, regions drift toward whichever faith
## speaks to their circumstances, and how much of the world a faith holds is what
## makes it strong.

const ROOT_ARCHETYPE := &"animism"

## How fast a region's faith gives way to another, per epoch.
const CONVERSION_RATE := 0.11
## A faith needs this much more standing than the incumbent before a region will
## change what it believes at all. Faith is sticky; that is most of what it is.
const CONVERSION_MARGIN := 0.12
## And a faith is not driven out of the last place that holds it for anything
## less than a rout. Otherwise a revelation that has just found its first
## believers loses them to fashion before it has said anything.
const LAST_REFUGE_MARGIN := 0.45


static func root() -> Organization:
	return GameState.root_of_kind(Organization.OrgKind.RELIGION)


## Called each power epoch: works out how much of the world each faith holds,
## then lets regions drift toward the one that answers their conditions.
static func refresh_all(tick: int) -> void:
	var faiths := GameState.organizations_of_kind(Organization.OrgKind.RELIGION)
	if faiths.is_empty():
		return
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		if GameState.get_organization(s.religion_id) == null:
			s.religion_id = root().org_id if root() != null else &""
	_seed_new_faiths(faiths, tick)
	for id in GameState.world.settlements:
		_maybe_convert(GameState.world.settlements[id], faiths, tick)
	_settle_house_faiths(faiths)
	_settle_followings(faiths)


## A family keeps the faith of its own seat, and carries it to everywhere else it
## holds. That is the loop that lets a revelation get out of the valley it was
## born in: it takes a region, the region's family takes it up, and the family
## brings it to the other regions it holds.
static func _settle_house_faiths(faiths: Array[Organization]) -> void:
	var strongest: Organization = null
	for faith in faiths:
		if strongest == null or faith.power_score > strongest.power_score:
			strongest = faith
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		# A family of priests follows the faith that is winning, not the one
		# outside its own window.
		if house.character_id == HouseCharacter.CLERICAL and strongest != null:
			house.faith_id = strongest.org_id
			continue
		var seat: SettlementState = GameState.world.settlements.get(
			house.dynasty_seat_settlement_id)
		if seat != null and seat.religion_id != &"":
			house.faith_id = seat.religion_id


## A faith with nowhere that holds it has no congregation, and a body with no
## members dies out the same epoch it was founded — so a new faith takes the
## place it arose in with it. Somebody was the first to believe it somewhere.
static func _seed_new_faiths(faiths: Array[Organization], tick: int) -> void:
	var claimed := {}
	for id in GameState.world.settlements:
		claimed[GameState.world.settlements[id].religion_id] = true
	for faith in faiths:
		if claimed.has(faith.org_id):
			continue
		var best: SettlementState = null
		var best_appeal := -1.0
		for id in GameState.world.settlements:
			var s: SettlementState = GameState.world.settlements[id]
			# Never take the last ground from another faith: a new revelation
			# starts where an old one is already sharing the field.
			if _regions_holding(s.religion_id) <= 1:
				continue
			var appeal := _appeal_of(faith, s) - _appeal_of(GameState.get_organization(s.religion_id), s)
			if appeal > best_appeal:
				best_appeal = appeal
				best = s
		if best == null:
			continue
		var previous := GameState.get_organization(best.religion_id)
		best.religion_id = faith.org_id
		claimed[faith.org_id] = true
		HistoryLog.emit_event(
			HistoryEvent.EventType.IDEOLOGY_SHIFT,
			tick,
			"%sで%sが最初の信徒を得た。" % [best.display_name, faith.display_name],
			{"settlement": String(best.id),
				"from_faith": String(previous.org_id) if previous != null else "",
				"transient": true},
			faith.org_id,
			faith.leader_person_id,
			faith.origin_event_id)


static func _regions_holding(faith_id: StringName) -> int:
	var n := 0
	for id in GameState.world.settlements:
		if GameState.world.settlements[id].religion_id == faith_id:
			n += 1
	return n


## A region weighs each faith by what it offers the life being lived there: a
## frontier under raids wants a protector, a valley that keeps burying its
## harvest wants a harvest god, and a house that keeps priests carries its own
## faith into the places it holds.
static func _maybe_convert(s: SettlementState, faiths: Array[Organization], tick: int) -> void:
	var incumbent := GameState.get_organization(s.religion_id)
	var best: Organization = null
	var best_appeal := 0.0
	for faith in faiths:
		var appeal := _appeal_of(faith, s)
		if appeal > best_appeal:
			best_appeal = appeal
			best = faith
	if best == null or incumbent == null or best.org_id == incumbent.org_id:
		return
	var margin := CONVERSION_MARGIN
	if _regions_holding(incumbent.org_id) <= 1:
		margin = LAST_REFUGE_MARGIN
	if best_appeal - _appeal_of(incumbent, s) < margin:
		return
	if RngService.stream(&"faith").randf() > CONVERSION_RATE:
		return

	s.religion_id = best.org_id
	HistoryLog.emit_event(
		HistoryEvent.EventType.IDEOLOGY_SHIFT,
		tick,
		"%sの人々は%sを捨て、%sに祈るようになった。"
			% [s.display_name, incumbent.display_name, best.display_name],
		{"settlement": String(s.id), "from_faith": String(incumbent.org_id), "transient": true},
		best.org_id,
		best.leader_person_id,
		best.origin_event_id)


static func _appeal_of(faith: Organization, s: SettlementState) -> float:
	if faith == null:
		return 0.0
	var appeal: float = clampf(faith.power_score / 60.0, 0.0, 1.0)
	# The family holding a place brings its own chaplains with it.
	var house := GameState.get_organization(s.ruling_house_id)
	if house != null and house.faith_id == faith.org_id:
		appeal += 0.35
	if house != null and house.character_id == HouseCharacter.CLERICAL \
			and house.faith_id == faith.org_id:
		appeal += 0.2
	# A faith already held has the enormous advantage of being what people know.
	if s.religion_id == faith.org_id:
		appeal += 0.25
	return appeal


## A faith's following is how much of the world holds it, not a membership roll.
static func _settle_followings(faiths: Array[Organization]) -> void:
	var held := {}
	var total := 0.0
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		if s.religion_id == &"":
			continue
		held[s.religion_id] = float(held.get(s.religion_id, 0.0)) + s.population
		total += s.population
	for faith in faiths:
		faith.resources[&"following"] = float(held.get(faith.org_id, 0.0))
		faith.member_count = int(held.get(faith.org_id, 0.0))
	GameState.world.faith_concentration = 0.0 if total <= 0.0 \
		else _largest(held) / total


static func _largest(held: Dictionary) -> float:
	var best := 0.0
	for key in held:
		best = maxf(best, float(held[key]))
	return best


# ------------------------------------------------------------------- readers

## The faith a house keeps: its own if it has declared one, otherwise whatever is
## believed where it is seated.
static func faith_of_house(house: Organization) -> Organization:
	if house == null:
		return null
	if house.faith_id != &"":
		var declared := GameState.get_organization(house.faith_id)
		if declared != null and declared.is_active():
			return declared
	var seat: SettlementState = GameState.world.settlements.get(house.dynasty_seat_settlement_id)
	return GameState.get_organization(seat.religion_id) if seat != null else null


## How many regions hold each faith, strongest first — for the UI.
static func congregations() -> Array:
	var counts := {}
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		counts[s.religion_id] = int(counts.get(s.religion_id, 0)) + 1
	var out: Array = []
	for faith in GameState.organizations_of_kind(Organization.OrgKind.RELIGION):
		out.append([faith, int(counts.get(faith.org_id, 0))])
	out.sort_custom(func(a, b):
		return a[1] > b[1] if a[1] != b[1] else String(a[0].org_id) < String(b[0].org_id))
	return out


## Houses keep the faith of the ground they sit on unless they have taken up
## another. Called when a world is made and when a house takes a new seat.
static func settle_house_faith(house: Organization) -> void:
	if house == null or house.kind != Organization.OrgKind.HOUSE:
		return
	var seat: SettlementState = GameState.world.settlements.get(house.dynasty_seat_settlement_id)
	if seat != null and seat.religion_id != &"":
		house.faith_id = seat.religion_id
	elif root() != null:
		house.faith_id = root().org_id
