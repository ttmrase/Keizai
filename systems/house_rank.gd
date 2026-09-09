class_name HouseRank
extends RefCounted

## 家格 — the standing a family carries by name rather than by force, and how
## much anyone bothers to care about it.
##
## The tier itself is read off what the house actually holds: land, influence,
## the crown, and how long it has been around. What makes it interesting is that
## its *weight* is not constant. A hereditary monarchy runs on pedigree, so a
## count outranks a merchant of twice his wealth; a popular republic barely
## notices. The same split runs through the guilds — a temple or a trading house
## wants well-born officers, a hunters' lodge wants someone who can fight.
##
## So rank is one number that means a great deal in one century and almost
## nothing in the next, without any of the systems that read it changing.

## Tier 0 is the lowest. A house below the bottom threshold is simply untitled.
const TIER_NAMES: Array[String] = ["男爵", "子爵", "伯爵", "侯爵", "公爵"]
const UNTITLED := "郷士"

## Composite standing needed to reach each tier, highest first.
const TIER_THRESHOLDS: Array[float] = [2.35, 1.70, 1.05, 0.55, 0.0]

## What each strand of standing is worth.
const LAND_WEIGHT := 0.85
const POWER_WEIGHT := 1.0
const CROWN_WEIGHT := 1.15
const OFFICE_WEIGHT := 0.45
const AGE_WEIGHT := 0.4
## Land beyond this many regions stops adding to a family's dignity.
const LAND_SATURATION := 3.0
## Years after which a house counts as fully established.
const AGE_SATURATION := 300.0

## Rank moves at most one tier per epoch, so a bad season cannot turn a duke into
## a squire between one chronicle entry and the next.
const MAX_TIER_STEP := 1


static func refresh_all(tick: int) -> void:
	# The peerage is the nobility's own order of precedence. A retainer family
	# stands outside it entirely — that is what being a retainer means — and
	# ranking them alongside would give the world thirty-two dukes.
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			houses.append(house)
	if houses.is_empty():
		return

	var strongest := 1.0
	for h in houses:
		strongest = maxf(strongest, h.power_score)

	var crowned := _crowned_houses()
	var officed := _houses_holding_office()

	var standings: Array = []
	for house in houses:
		standings.append([_standing_of(house, strongest, crowned, officed, tick), house])
	# Order matters: a peerage is comparative. Ties break on org id so a replay of
	# the same world produces the same order of precedence.
	standings.sort_custom(func(a, b):
		return a[0] > b[0] if not is_equal_approx(a[0], b[0]) else String(a[1].org_id) < String(b[1].org_id))

	for position in standings.size():
		var standing: float = standings[position][0]
		var house: Organization = standings[position][1]
		var previous := house.rank_tier
		# Earned by standing, but capped by precedence: there is room for one
		# duke in a country, not eight. Without the quota every family that owns
		# three counties is a duke and the peerage stops meaning anything.
		var target: int = mini(_tier_for(standing, previous), _quota_tier(position))
		house.rank_tier = clampi(target, previous - MAX_TIER_STEP, previous + MAX_TIER_STEP)
		if house.rank_tier != previous and house.founding_tick < tick:
			_chronicle(house, previous, tick)


## How high the n-th house in order of precedence may stand.
const TIER_QUOTA: Array[int] = [4, 3, 3, 2, 2, 2, 1, 1]


static func _quota_tier(position: int) -> int:
	return TIER_QUOTA[position] if position < TIER_QUOTA.size() else 0


## 0..~3.2. Deliberately unnormalized: the thresholds are absolute, so a world
## where every house is poor has no dukes rather than crowning its least poor.
static func _standing_of(house: Organization, strongest: float, crowned: Dictionary,
		officed: Dictionary, tick: int) -> float:
	var standing := POWER_WEIGHT * clampf(house.power_score / strongest, 0.0, 1.0)
	standing += LAND_WEIGHT * clampf(house.held_settlement_ids.size() / LAND_SATURATION, 0.0, 1.0)
	if crowned.has(house.org_id):
		standing += CROWN_WEIGHT
	if officed.has(house.org_id):
		standing += OFFICE_WEIGHT
	var years := float(tick - house.founding_tick) / SimConfig.TICKS_PER_YEAR
	standing += AGE_WEIGHT * clampf(years / AGE_SATURATION, 0.0, 1.0)
	return standing


## Hysteresis: a house has to clear the threshold by a margin to rise, and fall
## below it by the same margin to sink. Without it a family hovering on a
## boundary is promoted and demoted every epoch, and the chronicle fills with it.
const TIER_MARGIN := 0.09


static func _tier_for(standing: float, current: int) -> int:
	for i in TIER_THRESHOLDS.size():
		var tier: int = TIER_NAMES.size() - 1 - i
		var bar: float = TIER_THRESHOLDS[i]
		bar += TIER_MARGIN if tier > current else -TIER_MARGIN
		if standing >= bar:
			return tier
	return 0


## Houses whose blood currently sits on a throne.
static func _crowned_houses() -> Dictionary:
	var out := {}
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var ruler := GameState.get_person(polity.leader_person_id)
		if ruler != null and ruler.house_org_id != &"":
			out[ruler.house_org_id] = true
	return out


## Houses with one of their own at the head of a guild or a faction.
static func _houses_holding_office() -> Dictionary:
	var out := {}
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		for org in GameState.organizations_of_kind(kind):
			var head := GameState.get_person(org.leader_person_id)
			if head != null and head.house_org_id != &"":
				out[head.house_org_id] = true
	return out


static func _chronicle(house: Organization, previous: int, tick: int) -> void:
	var risen := house.rank_tier > previous
	HistoryLog.emit_event(
		HistoryEvent.EventType.IDEOLOGY_SHIFT,
		tick,
		"%sの家格は%sから%sへと%s。" % [house.display_name, TIER_NAMES[previous],
			TIER_NAMES[house.rank_tier], "上がった" if risen else "下がった"],
		{"from_tier": previous, "to_tier": house.rank_tier, "transient": true},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)


# ------------------------------------------------------------------ readers

static func tier_of(house_org_id: StringName) -> int:
	var house := GameState.get_organization(house_org_id)
	return house.rank_tier if house != null and house.kind == Organization.OrgKind.HOUSE else 0


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]


## The peerage title a house head carries. Only meaningful where the regime cares
## about pedigree; a republic calls the same person a mayor.
static func title_of(house_org_id: StringName) -> String:
	return tier_name(tier_of(house_org_id))


## The rank of the house a person belongs to, 0 for anyone unattached.
static func tier_of_person(person: NotableIndividual) -> int:
	if person == null or person.house_org_id == &"":
		return 0
	return tier_of(person.house_org_id)


## How much this world currently cares about pedigree, 0..1. A hereditary
## monarchy is near 1, an assembly of merchants near 0 — and the same house's
## name is worth a great deal or nothing at all depending on which it is.
static func regard_in_realm(polity: Organization) -> float:
	if polity == null:
		return 0.5
	var form := PolityFormEvaluator.form_of(polity)
	var weight: float = form.rank_weight if form != null else 0.6
	# A regime that draws its legitimacy from birth cares more than its form
	# alone suggests; one that draws it from merit or votes cares less.
	if polity.ideology != null:
		match polity.ideology.legitimacy_basis:
			PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
				weight += 0.25
			PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC, \
			PoliticalSystemAxes.LegitimacyBasis.ELECTED:
				weight -= 0.25
	return clampf(weight, 0.0, 1.0)


## How much this particular body cares about pedigree: the realm's regard for it
## multiplied by whether this kind of institution wants well-born officers at all.
static func weight_for(org: Organization) -> float:
	var profile := ContentRegistry.get_power_profile(org.archetype_id)
	var sensitivity: float = profile.rank_sensitivity if profile != null else 0.0
	if sensitivity <= 0.0:
		return 0.0
	return sensitivity * regard_in_realm(dominant_realm())


## The realm a settlement belongs to, or the largest one, so callers with no
## particular place in mind still get a sensible answer.
static func dominant_realm() -> Organization:
	var best: Organization = null
	for p in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		if best == null or p.governs_settlement_ids.size() > best.governs_settlement_ids.size():
			best = p
	return best
