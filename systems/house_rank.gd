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

## The families in service have their own ladder, and it sits entirely below the
## peerage: the highest of them still stands under the lowest baron. Almost all
## of them are 従士 — that is what being in service ordinarily means — and the
## rungs above are earned in their liege's quarrels rather than held by birth.
const SERVICE_TITLES: Array[String] = ["従士", "下級騎士", "騎士", "準男爵"]

## One scale both ladders are read on, so anywhere rank counts, a baronet counts
## for less than a baron without every caller having to know the two tables.
const NOBLE_PRECEDENCE_BASE := 4.0
const SERVICE_PRECEDENCE_STEP := 0.5

## Composite standing needed to reach each tier, highest first.
const TIER_THRESHOLDS: Array[float] = [2.35, 1.70, 1.05, 0.55, 0.0]

## What each strand of standing is worth. (See grounds_of for the rest.)
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
	#
	# So does the royal house, at the other end. A title is a thing the crown
	# grants; a crown that granted itself one would be standing in its own order
	# of precedence, which is not what a crown is. While a family wears it they
	# hold no county title at all, and the duke's place they vacate goes to
	# somebody else — one of the things a dynasty actually loses on the way up.
	var royals := royal_house_ids()
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if royals.has(house.org_id):
			# Held no title means holds no title. Leaving the old tier standing in
			# the field while the name reads 王家 puts a third marquess in a
			# country with room for two, and takes his place out of the quota
			# without taking him out of the count.
			house.rank_tier = 0
			continue
		if house.standing == Organization.Standing.NOBLE:
			houses.append(house)
	if houses.is_empty():
		return

	_rank_service_houses(tick)

	# What each family's standing rests on, counted ground by ground. The
	# context is built fresh: appointments made this season count this season.
	var ctx := context(true)
	var standings: Array = []
	for house in houses:
		standings.append([standing_from(grounds_of(house, ctx)), house])
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
		var quota := _quota_tier(position)
		var target: int = mini(_tier_for(standing, previous), quota)
		# Damping slows how fast standing moves a house up or down the order. It
		# does not protect a house from the quota: precedence is comparative, and
		# a family that has been displaced to seventh cannot be a marquess while
		# it climbs down. Applied after the damping rather than before it, or the
		# country carries four marquesses for as long as the descent takes.
		house.rank_tier = mini(
			clampi(target, previous - MAX_TIER_STEP, previous + MAX_TIER_STEP), quota)
		if house.rank_tier != previous and house.founding_tick < tick:
			_chronicle(house, previous, tick)


## How high the n-th house in order of precedence may stand.
const TIER_QUOTA: Array[int] = [4, 3, 3, 2, 2, 2, 1, 1]


static func _quota_tier(position: int) -> int:
	return TIER_QUOTA[position] if position < TIER_QUOTA.size() else 0


# --------------------------------------------------------- the grounds of rank

## What a family's standing rests on, item by item, so that "why is this house
## a marquess?" has an answer anyone can read: three regents, first of the heir
## houses, a war won in command, two counties, two centuries, the chief house of
## its 氏 — and the marks against it. The standing is exactly the sum.
##
## Deliberately unnormalized: the thresholds are absolute, so a world where every
## house is poor has no dukes rather than crowning its least poor.
const PRESENCE_WEIGHT := 0.6
const HISTORY_PER_TERM := 0.12
const HISTORY_CAP := 0.45
const HISTORY_FADE_YEARS := 200.0
const HEREDITARY_WEIGHT := 0.3
const HEIR_WEIGHTS: Array[float] = [0.45, 0.3, 0.2]
const IN_LAW_WEIGHT := 0.35
const UJI_CHIEF_WEIGHT := 0.25
const TITLE_WEIGHT := 0.06
const MERIT := {"general": {"victory": 0.35, "defeat": -0.25},
	"strategist": {"victory": 0.25, "defeat": -0.12}}
const MERIT_FADE_YEARS := 150.0
const BLEMISH_FADE_YEARS := 100.0

const ROMAN_COUNT := ["", "一代", "二代", "三代", "四代", "五代", "六代", "七代", "八代", "九代"]

static var _ctx: Dictionary = {}
static var _ctx_tick := -1
static var _ctx_world: WorldState = null


## Everything the grounds of every house are read from, gathered in one pass.
static func context(fresh := false) -> Dictionary:
	var tick := SimClock.current_tick
	if not fresh and _ctx_tick == tick and _ctx_world == GameState.world and not _ctx.is_empty():
		return _ctx
	var strongest := 1.0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE:
			strongest = maxf(strongest, house.power_score)
	var current := {}
	var heirs := {}
	var in_laws := {}
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		for key in polity.offices:
			var holder: StringName = StringName(polity.offices[key].get("house", ""))
			var list: Array = current.get(holder, [])
			list.append([String(key), polity])
			current[holder] = list
		for i in polity.heir_houses.size():
			var id: StringName = polity.heir_houses[i]
			heirs[id] = mini(int(heirs.get(id, 99)), i)
		if polity.ideology != null \
				and polity.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
			for id in Offices.in_law_houses(GameState.get_current_leader(polity.org_id)):
				in_laws[id] = true
	var history := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		for record in p.office_history:
			var house_id := StringName(record.get("house", ""))
			var list: Array = history.get(house_id, [])
			list.append(record)
			history[house_id] = list
	_ctx = {
		"tick": tick,
		"strongest": strongest,
		"crowned": _crowned_houses(),
		"officed": _houses_holding_office(),
		"current": current,
		"history": history,
		"heirs": heirs,
		"in_laws": in_laws,
	}
	_ctx_tick = tick
	_ctx_world = GameState.world
	return _ctx


static func standing_from(grounds: Array) -> float:
	var total := 0.0
	for g in grounds:
		total += float(g["value"])
	return total


## The grounds of a family's standing: [{label, value, kind}], largest first.
## kind is one of presence, land, crown, organization, office, history,
## hereditary, heir, in_law, merit, uji, age, honour, title, blemish.
static func grounds_of(house: Organization, ctx: Dictionary = {}) -> Array:
	if ctx.is_empty():
		ctx = context()
	var out: Array = []
	if house == null:
		return out
	var tick: int = ctx["tick"]
	var add := func(kind: String, label: String, value: float) -> void:
		if not is_zero_approx(value):
			out.append({"kind": kind, "label": label, "value": value})

	add.call("presence", "家勢", PRESENCE_WEIGHT * clampf(house.power_score / float(ctx["strongest"]), 0.0, 1.0))
	add.call("land", "所領%d" % house.held_settlement_ids.size(),
		LAND_WEIGHT * clampf(house.held_settlement_ids.size() / LAND_SATURATION, 0.0, 1.0))
	if (ctx["crowned"] as Dictionary).has(house.org_id):
		add.call("crown", "国の長を出している", CROWN_WEIGHT)
	if (ctx["officed"] as Dictionary).has(house.org_id):
		add.call("organization", "ギルド・派閥の長", OFFICE_WEIGHT)
	for entry in ctx["current"].get(house.org_id, []):
		var key: String = entry[0]
		var polity: Organization = entry[1]
		add.call("office", "%s（現任）" % Offices.label_of(key, polity), Offices.weight_of(key, polity))

	# What its people held before: a seat counted once per holder, older terms
	# fading but never gone.
	var terms := {}
	for record in ctx["history"].get(house.org_id, []):
		var key := String(record.get("office", ""))
		if Offices.WAR_SEATS.has(key):
			continue
		var ended := int(record.get("end", -1))
		if ended < 0:
			continue
		var age := float(tick - ended) / SimConfig.TICKS_PER_YEAR
		var fade := 0.4 + 0.6 * exp(-age / HISTORY_FADE_YEARS)
		var t: Dictionary = terms.get(key, {"n": 0, "value": 0.0})
		t["n"] = int(t["n"]) + 1
		t["value"] = float(t["value"]) + HISTORY_PER_TERM * float(Offices.WEIGHT.get(key, 0.3)) * fade
		terms[key] = t
	var term_keys := terms.keys()
	term_keys.sort()
	for key in term_keys:
		var t: Dictionary = terms[key]
		var n := int(t["n"])
		add.call("history", "%s %s" % [Offices.LABELS.get(key, key),
			ROMAN_COUNT[n] if n < ROMAN_COUNT.size() else "%d代" % n],
			minf(float(t["value"]) * 4.0, HISTORY_CAP))

	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		for key in polity.hereditary_offices:
			if StringName(polity.hereditary_offices[key]) == house.org_id:
				add.call("hereditary", "家職：%s" % Offices.label_of(String(key), polity), HEREDITARY_WEIGHT)
	if (ctx["heirs"] as Dictionary).has(house.org_id):
		var rank: int = ctx["heirs"][house.org_id]
		add.call("heir", "跡目家 第%s位" % ["一", "二", "三"][clampi(rank, 0, 2)],
			HEIR_WEIGHTS[clampi(rank, 0, HEIR_WEIGHTS.size() - 1)])
	if (ctx["in_laws"] as Dictionary).has(house.org_id):
		add.call("in_law", "国の長の外戚", IN_LAW_WEIGHT)

	var won := 0.0
	var lost := 0.0
	for merit in house.merits:
		var table: Dictionary = MERIT.get(String(merit.get("office", "")), {})
		var value: float = float(table.get(String(merit.get("result", "")), 0.0))
		var age := float(tick - int(merit.get("tick", tick))) / SimConfig.TICKS_PER_YEAR
		value *= 0.3 + 0.7 * exp(-age / MERIT_FADE_YEARS)
		if value > 0.0:
			won += value
		else:
			lost += value
	add.call("merit", "武功", won)
	add.call("merit", "敗戦の責", lost)

	if Offices.is_uji_chief(house):
		add.call("uji", "%sの長者" % HouseNaming.uji_label(house.uji_id), UJI_CHIEF_WEIGHT)
	var years := float(tick - house.founding_tick) / SimConfig.TICKS_PER_YEAR
	add.call("age", "家の古さ %d年" % int(years), AGE_WEIGHT * clampf(years / AGE_SATURATION, 0.0, 1.0))
	# What the crown has said about them, worth something for as long as anyone
	# remembers the reign that said it — and the title itself, a little.
	add.call("honour", "叙勲" if house.honour > 0.0 else "咎め", house.honour)
	if house.standing == Organization.Standing.NOBLE:
		add.call("title", "爵位（%s）" % tier_name(house.rank_tier), TITLE_WEIGHT * float(house.rank_tier))

	var marks := 0.0
	for mark in house.blemishes:
		var age := float(tick - int(mark.get("tick", tick))) / SimConfig.TICKS_PER_YEAR
		marks -= float(mark.get("weight", 0.3)) * (0.3 + 0.7 * exp(-age / BLEMISH_FADE_YEARS))
	add.call("blemish", "汚点", marks)

	out.sort_custom(func(x, y): return absf(float(x["value"])) > absf(float(y["value"])))
	return out


## Favour above which a family in service is worth a rung, per rung. Almost
## nobody clears the first: standing in service is earned in a liege's quarrels,
## and most families are never asked to take a side.
const SERVICE_THRESHOLDS: Array[float] = [0.35, 0.75, 1.2]
## And what a season of nobody asking is worth, which is a little less each time.
const FAVOUR_DECAY := 0.004
const SERVICE_MARGIN := 0.09


## What a knighthood is worth is settled by the whole world, not by the house
## that granted it. A liege may knight whoever it likes among its own servants
## and nobody outside can stop it — but the more of them there are, the less the
## rank distinguishes anybody, so the bar rises for everyone until the honours
## granted are worth about what they were before.
const SERVICE_REFERENCE := 0.55
const INFLATION_SHIFT := 0.40
## And how fast the world changes its mind. Slowly, and by less per epoch than
## the hysteresis margin: recomputing the bar outright each epoch makes a whole
## cohort of households sitting on a boundary rise and fall a rung together every
## other season, and the chronicle announces every one of them.
const INFLATION_ADJUST := 0.015


## What the bar currently stands at — a world value, moved gradually.
static func service_bar_shift() -> float:
	return GameState.world.service_rank_inflation


## And where the current spread of titles says it ought to stand.
static func _inflation_target() -> float:
	var total := 0.0
	var count := 0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		total += float(house.rank_tier)
		count += 1
	if count == 0:
		return 0.0
	return maxf(0.0, total / float(count) - SERVICE_REFERENCE) * INFLATION_SHIFT


static func _rank_service_houses(tick: int) -> void:
	GameState.world.service_rank_inflation = move_toward(
		GameState.world.service_rank_inflation, _inflation_target(), INFLATION_ADJUST)
	var inflation := GameState.world.service_rank_inflation
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.RETAINER:
			continue
		house.favour = move_toward(house.favour, 0.0, FAVOUR_DECAY)
		var previous := house.rank_tier
		var tier := 0
		for i in SERVICE_THRESHOLDS.size():
			# Clear the bar by a margin to rise, fall below it by one to sink,
			# or a family hovering on a threshold is knighted and unknighted
			# every few seasons and the chronicle says so every time.
			var bar: float = SERVICE_THRESHOLDS[i] + inflation
			bar += SERVICE_MARGIN if i + 1 > previous else -SERVICE_MARGIN
			if house.favour >= bar:
				tier = i + 1
		house.rank_tier = clampi(tier, previous - MAX_TIER_STEP, previous + MAX_TIER_STEP)
		if house.rank_tier != previous and house.founding_tick < tick:
			_chronicle(house, previous, tick)


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
		"%sの家格は%sから%sへと%s。" % [house.formal_name(),
			tier_name(previous, house.standing), tier_name(house.rank_tier, house.standing),
			"上がった" if risen else "下がった"],
		{"from_tier": previous, "to_tier": house.rank_tier, "transient": true},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)


# ------------------------------------------------------------------ readers

static func tier_of(house_org_id: StringName) -> int:
	var house := GameState.get_organization(house_org_id)
	return house.rank_tier if house != null and house.kind == Organization.OrgKind.HOUSE else 0


static func tier_name(tier: int, standing: int = Organization.Standing.NOBLE) -> String:
	if standing == Organization.Standing.NOBLE:
		return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]
	if standing == Organization.Standing.COMMONER:
		return ""
	return SERVICE_TITLES[clampi(tier, 0, SERVICE_TITLES.size() - 1)]


## The name the crown is known by instead of a title, while it holds one.
const ROYAL_TITLE := "王家"


## The family whose blood currently sits on the throne of a realm that runs on
## blood. A republic's president heads no royal house, however grand his family:
## what makes a house royal is a crown that is inherited.
static func royal_house_id() -> StringName:
	return royal_house_of(dominant_realm())


## Every family wearing a hereditary crown. Usually one; two while a divided
## country has a king on each side of the line, and each of them stands outside
## the peerage of the whole world, not only of their own half.
static func royal_house_ids() -> Dictionary:
	var out := {}
	for realm in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		var house_id := royal_house_of(realm)
		if house_id != &"":
			out[house_id] = realm.org_id
	return out


## The family wearing this realm's crown, if its crown is inherited.
static func royal_house_of(realm: Organization) -> StringName:
	if realm == null or realm.ideology == null:
		return &""
	if realm.ideology.legitimacy_basis != PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
		return &""
	var monarch := GameState.get_current_leader(realm.org_id)
	if monarch == null or monarch.house_org_id == &"":
		return &""
	var house := GameState.get_organization(monarch.house_org_id)
	return house.org_id if house != null and house.is_active() else &""


static func is_royal(house: Organization) -> bool:
	return house != null and house.org_id != &"" and royal_house_ids().has(house.org_id)


## What a house is called, from the house itself.
static func title_of_house(house: Organization) -> String:
	if house == null or house.kind != Organization.OrgKind.HOUSE:
		return ""
	if is_royal(house):
		return ROYAL_TITLE
	return tier_name(house.rank_tier, house.standing)


## Where a family stands on the one ladder that runs through both: 従士 at 0,
## 準男爵 at 1.5, 男爵 at 4, 公爵 at 8. Everything that reads rank reads this, so
## the lower titles count for something and never for as much.
static func precedence(house: Organization) -> float:
	if house == null or house.kind != Organization.OrgKind.HOUSE:
		return 0.0
	# The crown holds no title and outranks every title there is.
	if is_royal(house):
		return NOBLE_PRECEDENCE_BASE + float(TIER_NAMES.size())
	if house.standing == Organization.Standing.NOBLE:
		return NOBLE_PRECEDENCE_BASE + float(house.rank_tier)
	if house.standing == Organization.Standing.COMMONER:
		return 0.0
	return float(house.rank_tier) * SERVICE_PRECEDENCE_STEP


static func precedence_of_person(person: NotableIndividual) -> float:
	if person == null or person.house_org_id == &"":
		return 0.0
	return precedence(GameState.get_organization(person.house_org_id))


## The peerage title a house head carries. Only meaningful where the regime cares
## about pedigree; a republic calls the same person a mayor.
static func title_of(house_org_id: StringName) -> String:
	return title_of_house(GameState.get_organization(house_org_id))


## The rank of the house a person belongs to, 0 for anyone unattached.
static func tier_of_person(person: NotableIndividual) -> int:
	if person == null or person.house_org_id == &"":
		return 0
	return tier_of(person.house_org_id)


## What a rank is worth to whoever is reading it: the realm's regard for birth,
## multiplied by where the family stands on the one ladder.
static func standing_value_of(person: NotableIndividual) -> float:
	return regard_in_realm(dominant_realm()) * precedence_of_person(person)


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


## The realm a family lives under: the one governing its land, or its liege's.
## With a single state in the world that is always the same answer.
static func realm_of(house: Organization) -> Organization:
	return GameState.get_organization(CivilWar.realm_of_house(house))
