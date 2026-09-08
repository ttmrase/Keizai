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

	var best: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if best == null or house.power_score > best.power_score:
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
