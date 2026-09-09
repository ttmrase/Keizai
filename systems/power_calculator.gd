class_name PowerCalculator
extends RefCounted

## Scores every organization's influence from world conditions.
##
## Nothing here knows what a monster hunter or a merchant is. Each archetype's
## PowerProfile names the world variables that feed it and how heavily, so a new
## kind of institution is a new .tres file — the reason "monsters are common, so
## the hunters gain power" is one instance of a general rule rather than a
## special case.
##
## The per-driver contributions are kept on the organization so the dashboard can
## show *why* someone is powerful, and they sum exactly to the pre-clamp score.

const BASE_KEY := &"base"
const MEMBERSHIP_KEY := &"membership"
const LEADERSHIP_KEY := &"leadership"
const PEDIGREE_KEY := &"pedigree"

## What each trait is worth to the organization a person leads. Two guilds with
## identical world conditions would otherwise always score identically; who is
## actually in charge is the thing that legitimately differs between them.
const TRAIT_VALUE := {
	&"ambitious": 4.0,
	&"just": 5.0,
	&"scholarly": 3.5,
	&"martial": 3.0,
	&"pious": 2.5,
	&"cautious": 2.0,
	&"greedy": -2.0,
}


static func recalculate_all(tick: int) -> void:
	var total_suppression := 0.0
	var active := GameState.active_organizations()
	for org in active:
		var profile := ContentRegistry.get_power_profile(org.archetype_id)
		if profile == null:
			continue
		calculate(org, profile)
		total_suppression += org.power_score * profile.monster_suppression_factor
	# Whoever hunts monsters holds them down — which then erodes the very threat
	# that made them powerful. That negative feedback is intentional.
	GameState.world.monster_suppression = total_suppression
	_settle_membership(active, tick)


## Membership follows influence: organizations people have reason to join grow,
## irrelevant ones wither, and one that withers past saving dies out. Its record
## stays in the lineage tree — a dead branch is still part of the history.
static func _settle_membership(active: Array[Organization], tick: int) -> void:
	var population: float = GameState.world.global_population
	var power_by_kind := {}
	for org in active:
		power_by_kind[org.kind] = float(power_by_kind.get(org.kind, 0.0)) + maxf(1.0, org.power_score)

	# One pass over the population, rather than one per house.
	var living_by_house := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.is_alive() and p.house_org_id != &"":
			living_by_house[p.house_org_id] = int(living_by_house.get(p.house_org_id, 0)) + 1

	for org in active:
		if org.kind == Organization.OrgKind.HOUSE:
			# A house is not a share of the population — it is a family, and its
			# size is however many of it are currently alive. That is also what
			# makes a house able to die out, which a share-based figure never could.
			org.member_count = int(living_by_house.get(org.org_id, 0))
		else:
			var share: float = maxf(1.0, org.power_score) / maxf(1.0, float(power_by_kind[org.kind]))
			var target: float = population * float(SimConfig.MEMBERSHIP_SHARE.get(org.kind, 0.05)) * share
			var step: float = maxf(1.0, target * SimConfig.MEMBERSHIP_ADJUST_FRACTION)
			org.member_count = int(move_toward(float(org.member_count), target, step))

		# A house ends when the last of its blood does — even the first house in
		# the world, which is why this is the one dissolution a root is not spared.
		# Its record stays in the lineage tree; it simply has no more members.
		var floor_size: int = 1 if org.kind == Organization.OrgKind.HOUSE \
			else SimConfig.ORG_DISSOLVE_MEMBERS
		var may_dissolve: bool = not org.is_root() or org.kind == Organization.OrgKind.HOUSE
		if org.member_count < floor_size and may_dissolve:
			HistoryLog.emit_event(
				HistoryEvent.EventType.DISSOLVED,
				tick,
				"%sは人を失い、絶えた。" % org.display_name,
				{},
				org.org_id,
				org.leader_person_id,
				org.origin_event_id)


static func calculate(org: Organization, profile: PowerProfile) -> float:
	var drivers: Dictionary[StringName, float] = {}
	var score := profile.base_score
	drivers[BASE_KEY] = profile.base_score

	for driver in profile.drivers:
		var raw := WorldStateQuery.get_value(driver.world_var_path, org)
		var contribution := driver.evaluate(raw)
		drivers[driver.world_var_path] = contribution
		score += contribution

	if profile.membership_weight > 0.0:
		var member_term: float = profile.membership_weight \
			* clampf(float(org.member_count) / 500.0, 0.0, 1.0) * 40.0
		drivers[MEMBERSHIP_KEY] = member_term
		score += member_term

	var leader_term := _leadership_bonus(org)
	if leader_term != 0.0:
		drivers[LEADERSHIP_KEY] = leader_term
		score += leader_term

	var pedigree_term := _pedigree_bonus(org, profile)
	if pedigree_term != 0.0:
		drivers[PEDIGREE_KEY] = pedigree_term
		score += pedigree_term

	org.power_drivers = drivers
	org.power_score = clampf(score, 0.0, profile.max_score)
	return org.power_score


## What the current leader is worth. An experienced holder of the seat counts for
## more than someone who took it last season.
static func _leadership_bonus(org: Organization) -> float:
	var leader := GameState.get_current_leader(org.org_id)
	if leader == null:
		return -3.0     # a vacant seat is a weakness in itself
	var bonus := 0.0
	for tag in leader.personality_tags:
		bonus += float(TRAIT_VALUE.get(tag, 0.0))
	var tenure := leader.current_tenure()
	if tenure != null:
		var years: float = float(SimClock.current_tick - tenure.start_tick) / SimConfig.TICKS_PER_YEAR
		bonus += clampf(years / 25.0, 0.0, 1.0) * 4.0
	return bonus


## What the family behind this body is worth to it. A trading house or a temple
## gains from a well-born officer and says so; a hunters' lodge gains nothing
## from one. And under a republic almost nobody gains much, however grand the
## name — which is the whole point of 家格 being weighted rather than absolute.
static func _pedigree_bonus(org: Organization, profile: PowerProfile) -> float:
	if profile.rank_sensitivity <= 0.0:
		return 0.0
	var tier := 0
	if org.kind == Organization.OrgKind.HOUSE:
		tier = org.rank_tier
	elif org.patron_house_id != &"":
		tier = HouseRank.tier_of(org.patron_house_id)
	else:
		tier = HouseRank.tier_of_person(GameState.get_current_leader(org.org_id))
	if tier <= 0:
		return 0.0
	var regard := HouseRank.regard_in_realm(HouseRank.dominant_realm())
	return profile.rank_sensitivity * regard * float(tier) * 4.0


## Ranked snapshot for the dashboard.
static func ranked(kind_filter: int = -1) -> Array[Organization]:
	var out: Array[Organization] = []
	for org in GameState.active_organizations():
		if kind_filter >= 0 and org.kind != kind_filter:
			continue
		out.append(org)
	out.sort_custom(func(a, b): return a.power_score > b.power_score)
	return out


## The single strongest contributor to an organization's score, for compact UI.
static func top_driver(org: Organization) -> StringName:
	var best := &""
	var best_value := -INF
	for key in org.power_drivers:
		if key == BASE_KEY:
			continue
		if org.power_drivers[key] > best_value:
			best_value = org.power_drivers[key]
			best = key
	return best
