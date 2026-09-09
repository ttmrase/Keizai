class_name RegionalStanding
extends RefCounted

## Works out, for each region, which guild carries weight there and which house
## holds it.
##
## A guild's standing in a region is its national power bent by whether the
## region's industry has any use for it: a mining valley lifts the artisans and
## ignores the farmers. That is what makes the map worth reading — the same
## country looks different from one town to the next.

## How much a matching industry counts for, relative to raw national power.
const AFFINITY_BONUS := 45.0
## How much being seated in the region itself counts for.
const SEAT_BONUS := 25.0
## How much less a family wants another county for each one it already holds.
const LAND_SATIETY := 26.0


static func refresh_all(tick: int) -> void:
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		s.dominant_guild_id = _dominant_guild(s)
		_verify_ruling_house(s)


static func _dominant_guild(settlement: SettlementState) -> StringName:
	var best := &""
	var best_standing := -INF
	for guild in GameState.organizations_of_kind(Organization.OrgKind.GUILD):
		var standing := guild.power_score
		if Industry.favours(settlement.industry, guild.archetype_id):
			standing += AFFINITY_BONUS
		if guild.dynasty_seat_settlement_id == settlement.id:
			standing += SEAT_BONUS
		if standing > best_standing:
			best_standing = standing
			best = guild.org_id
	return best


## A region is held by a house. If that house has died out, the strongest house
## with a claim nearby takes it over — land does not go unheld for long.
static func _verify_ruling_house(settlement: SettlementState) -> void:
	var holder := GameState.get_organization(settlement.ruling_house_id)
	if holder != null and holder.is_active():
		if not holder.held_settlement_ids.has(settlement.id):
			holder.held_settlement_ids.append(settlement.id)
		return

	# Where the realm cares about pedigree, a grand old family takes the vacant
	# county over a stronger upstart; where it does not, strength simply wins.
	var regard := HouseRank.regard_in_realm(HouseRank.dominant_realm())
	var best: Organization = null
	var best_claim := -INF
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		# A county is held by a noble family. A retainer takes one only by rising
		# out of that rank first, which is a different thing entirely.
		if house.standing != Organization.Standing.NOBLE:
			continue
		var claim: float = house.power_score + regard * float(house.rank_tier) * 18.0
		# A family already holding several counties is a less obvious candidate
		# for another one. Without this the strongest house takes every vacancy
		# in the same epoch and ends up holding the entire country, which is not
		# a feudal kingdom, it is one man with eight houses.
		claim -= float(house.held_settlement_ids.size()) * LAND_SATIETY
		if claim > best_claim:
			best_claim = claim
			best = house
	if best == null:
		settlement.ruling_house_id = &""
		return
	settlement.ruling_house_id = best.org_id
	if not best.held_settlement_ids.has(settlement.id):
		best.held_settlement_ids.append(settlement.id)


## The head of the house holding this region, under the title its government uses.
static func local_ruler(settlement_id: StringName) -> Dictionary:
	var settlement: SettlementState = GameState.world.settlements.get(settlement_id)
	if settlement == null:
		return {}
	var house := GameState.get_organization(settlement.ruling_house_id)
	if house == null:
		return {}
	var head := GameState.get_current_leader(house.org_id)
	return {
		"house": house,
		"person": head,
		"title": PolityFormEvaluator.local_title_for(settlement_id),
	}
