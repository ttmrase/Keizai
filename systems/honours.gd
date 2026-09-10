class_name Honours
extends RefCounted

## Rank as a thing granted, not only earned.
##
## Two ladders and two authorities. The crown stands outside the peerage — a
## royal family holds no county title while it wears a crown, because a title is
## what a crown hands out — and in exchange it can raise or strip any great house
## in the realm. That is the whole of a monarch's ordinary power over the
## nobility: not armies, but the order of precedence, and who is placed where in
## it. A house lifted is grateful and its equals are not; a house stripped
## remembers it for a reign.
##
## The lower ladder belongs to the great houses themselves. A liege knights
## whoever it likes among its own servants and no one outside can forbid it —
## but what a knighthood is *worth* is settled by the whole world (see
## HouseRank.service_bar_shift), so a house that hands them out freely finds the
## bar risen under everyone's feet, its peers resentful of a currency they also
## hold, and its own retainers no more distinguished than before, because a rank
## every neighbour shares distinguishes nobody.

# --- the crown's gift ---
## How often the crown troubles itself about the order of precedence.
const CROWN_INTERVAL := 140
## Roughly one tier's worth of standing.
const HONOUR_STEP := 0.5
## What a favour is still worth a reign later, per epoch.
const HONOUR_DECAY := 0.0011
## Relations warm enough to be worth rewarding, and cold enough to punish.
const REWARD_RELATION := 0.25
const STRIP_RELATION := -0.35
## An honour is not repeated on the same family straight away.
const HOUSE_COOLDOWN := 400
const HONOUR_CEILING := 1.1

# --- a liege's gift ---
const SERVICE_INTERVAL := 110
## What a knighting is worth in the favour a service rank is read from.
const KNIGHTING_FAVOUR := 0.42
## A liege only bothers with a household it is actually pleased with.
const KNIGHTING_LOYALTY := 0.55
## Once a liege's servants are titled this far above the world's ordinary run,
## its peers notice, and the honours stop meaning anything inside the house too.
const EXCESS_MARGIN := 0.6
const SAMENESS_LOYALTY := 0.10


static func consider_all(tick: int) -> void:
	_decay(tick)
	if tick % CROWN_INTERVAL == 0:
		_crown_honours(tick)
	if tick % SERVICE_INTERVAL == 0:
		_liege_honours(tick)


static func _decay(tick: int) -> void:
	if tick % SimConfig.POWER_RECALC_EPOCH_TICKS != 0:
		return
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if not is_zero_approx(house.honour):
			house.honour = move_toward(house.honour, 0.0, HONOUR_DECAY)


# ------------------------------------------------------------- from the crown

## One act of patronage a reign or so: the family that has served the crown best
## is raised, or the one that has opposed it longest is put down. Which of the
## two depends on what the crown has more of — friends worth confirming, or
## enemies worth answering.
static func _crown_honours(tick: int) -> void:
	var royal := GameState.get_organization(HouseRank.royal_house_id())
	if royal == null:
		return

	var favourite: Organization = null
	var target: Organization = null
	var best := REWARD_RELATION
	var worst := STRIP_RELATION
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.org_id == royal.org_id or house.standing != Organization.Standing.NOBLE:
			continue
		if tick - int(house.last_fired_tick.get(&"honour", -999999)) < HOUSE_COOLDOWN:
			continue
		var standing := HouseRelations.relation(royal.org_id, house.org_id)
		if standing > best and house.honour < HONOUR_CEILING:
			best = standing
			favourite = house
		if standing < worst and house.honour > -HONOUR_CEILING:
			worst = standing
			target = house

	# A crown with enemies answers them first; a crown at peace rewards.
	if target != null:
		_strip(royal, target, tick)
	elif favourite != null:
		_elevate(royal, favourite, tick)


static func _elevate(royal: Organization, house: Organization, tick: int) -> void:
	house.last_fired_tick[&"honour"] = tick
	house.honour = clampf(house.honour + HONOUR_STEP, -HONOUR_CEILING, HONOUR_CEILING)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sの功を賞し、その家格を引き上げた。" % [royal.display_name, house.display_name],
		{"honour": true, "granted_by": String(royal.org_id), "legitimacy_cost": 0.0},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)


static func _strip(royal: Organization, house: Organization, tick: int) -> void:
	house.last_fired_tick[&"honour"] = tick
	house.honour = clampf(house.honour - HONOUR_STEP, -HONOUR_CEILING, HONOUR_CEILING)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sの不遜を咎め、その家格を削った。" % [royal.display_name, house.display_name],
		{"honour": true, "stripped": true, "granted_by": String(royal.org_id),
			"legitimacy_cost": 0.0},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)


# ------------------------------------------------------------- from a liege

## A great house knighting its own. Nobody outside can forbid it, which is the
## point: the check on it is not permission but worth.
static func _liege_honours(tick: int) -> void:
	for liege in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if liege.standing != Organization.Standing.NOBLE:
			continue
		if tick - int(liege.last_fired_tick.get(&"knighting", -999999)) < SERVICE_INTERVAL * 2:
			continue
		var served := Retainers.retainers_of(liege.org_id)
		if served.is_empty():
			continue
		var best: Organization = null
		for house in served:
			if house.loyalty < KNIGHTING_LOYALTY:
				continue
			if best == null or house.loyalty > best.loyalty:
				best = house
		if best == null:
			continue
		liege.last_fired_tick[&"knighting"] = tick
		best.favour += KNIGHTING_FAVOUR
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sは家中の%sを取り立て、位を授けた。" % [liege.display_name, best.display_name],
			{"knighting": true, "granted_by": String(liege.org_id), "legitimacy_cost": 0.0},
			best.org_id,
			best.leader_person_id,
			best.origin_event_id)


## A rank all one's neighbours share is not a rank. Where a liege has titled its
## whole household alike, none of them feels singled out by it, and the loyalty
## the honours were meant to buy is simply not bought.
##
## Read into the loyalty target rather than subtracted from loyalty each epoch:
## loyalty is recomputed toward a target every epoch, so a nudge afterwards is
## undone before anybody notices it.
static func sameness_penalty(house: Organization) -> float:
	if house == null or house.standing != Organization.Standing.RETAINER \
			or house.rank_tier < 1:
		return 0.0
	var served := Retainers.retainers_of(house.liege_house_id)
	if served.size() < 2:
		return 0.0
	for other in served:
		if other.rank_tier != house.rank_tier:
			return 0.0
	return SAMENESS_LOYALTY


# ------------------------------------------------------------------ readers

## How far a house has titled its servants above the world's ordinary run. Read
## by HouseRelations: a family cheapening a currency its peers also hold is
## resented for it, which is the outside check on a gift nobody can forbid.
static func service_excess(liege: Organization) -> float:
	if liege == null or liege.standing != Organization.Standing.NOBLE:
		return 0.0
	var served := Retainers.retainers_of(liege.org_id)
	if served.is_empty():
		return 0.0
	var total := 0.0
	for house in served:
		total += float(house.rank_tier)
	var mine := total / float(served.size())
	return maxf(0.0, mine - HouseRank.SERVICE_REFERENCE - EXCESS_MARGIN)


## What the crown has said about a family, for a screen that wants to say so.
static func honour_label(house: Organization) -> String:
	if house == null or is_zero_approx(house.honour):
		return ""
	if house.honour > 0.0:
		return "叙勲を受けている"
	return "咎めを受けている"
