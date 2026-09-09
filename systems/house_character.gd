class_name HouseCharacter
extends RefCounted

## What kind of family this is.
##
## Two houses with the same land and the same standing are not the same house.
## One keeps priests, one keeps soldiers, one keeps a library, one keeps the
## accounts — and that shapes both what the family is good at and what it throws
## off into the world. A house of scholars produces the arguments that become
## factions; a house of courtiers is what a feudal crown is actually made of, and
## props one up as long as it stands.
##
## A character is settled at founding from the ground the family sits on, and
## then re-read from what the family actually does: keep putting your sons in
## temples for a century and you are a clerical house whatever you started as.

const NOBLE := &"noble"          # 貴族一家
const CLERICAL := &"clerical"    # 神官一家
const MARTIAL := &"martial"      # 騎士一家
const SCHOLARLY := &"scholarly"  # 学究一家
const MERCANTILE := &"mercantile"# 商家
const AGRARIAN := &"agrarian"    # 郷士

const ALL: Array[StringName] = [NOBLE, CLERICAL, MARTIAL, SCHOLARLY, MERCANTILE, AGRARIAN]

const LABELS := {
	NOBLE: "貴族一家",
	CLERICAL: "神官一家",
	MARTIAL: "騎士一家",
	SCHOLARLY: "学究一家",
	MERCANTILE: "商家",
	AGRARIAN: "郷士の家",
}

const DESCRIPTIONS := {
	NOBLE: "宮廷に生き、王権のかたちそのものを支えている。",
	CLERICAL: "代々神に仕え、祭壇の側から世を見ている。",
	MARTIAL: "剣を家業とし、境を守ることで名を保っている。",
	SCHOLARLY: "書物と議論を家業とし、しばしば新しい思想を世に放つ。",
	MERCANTILE: "帳簿と商路を握り、金の流れで発言力を得ている。",
	AGRARIAN: "土地に根を張り、実りとともに生きている。",
}

## Which character a region's trade tends to raise.
const BY_INDUSTRY := {
	&"mining": MERCANTILE,
	&"forestry": AGRARIAN,
	&"farming": AGRARIAN,
	&"trade": MERCANTILE,
	&"frontier": MARTIAL,
}

## What each character is worth, as a share of a house's own standing.
const POWER_BONUS := {
	NOBLE: 0.16,
	CLERICAL: 0.12,
	MARTIAL: 0.12,
	SCHOLARLY: 0.10,
	MERCANTILE: 0.14,
	AGRARIAN: 0.10,
}

## How much likelier a body led by a member of such a house is to throw off a
## breakaway. A house of scholars is where new politics comes from.
const SCHISM_AFFINITY := {
	SCHOLARLY: 2.2,
	CLERICAL: 1.3,
	MERCANTILE: 1.1,
	NOBLE: 0.7,
	MARTIAL: 0.8,
	AGRARIAN: 0.9,
}

## Forms of government each character props up. A noble house makes a feudal
## crown work; take the nobles away and the same crown is a man in a hat.
const SUPPORTS_FORMS := {
	NOBLE: [&"feudal_kingdom", &"centralized_kingdom", &"kingdom",
		&"constitutional_kingdom", &"elective_monarchy"],
	CLERICAL: [&"theocracy"],
	MARTIAL: [&"military_regime", &"warden_state"],
	MERCANTILE: [&"merchant_republic", &"plutocracy", &"guild_council"],
	SCHOLARLY: [&"meritocratic_state"],
	AGRARIAN: [&"agrarian_republic", &"popular_republic"],
}

## How long a family has to behave a certain way before it is that kind of family.
const REDEFINE_SHARE := 0.5
const REDEFINE_MIN_OFFICES := 4
## And how rarely the question is asked. A family does not change character in a
## season, and asking every epoch fills the chronicle with families changing
## their minds — as well as walking the whole population for no new answer.
const REDEFINE_INTERVAL := 80


static func label(character_id: StringName) -> String:
	return LABELS.get(character_id, "家")


static func description(character_id: StringName) -> String:
	return DESCRIPTIONS.get(character_id, "")


## The character a house is born with: mostly the trade of the ground it sits on,
## sometimes not, because a family is allowed to be unlike its neighbours.
static func assign_at_founding(house: Organization, rng: RandomNumberGenerator) -> void:
	var seat: SettlementState = GameState.world.settlements.get(house.dynasty_seat_settlement_id)
	var from_land: StringName = BY_INDUSTRY.get(seat.industry, AGRARIAN) if seat != null else AGRARIAN
	if house.standing == Organization.Standing.NOBLE and rng.randf() < 0.45:
		from_land = NOBLE
	elif rng.randf() < 0.3:
		from_land = ALL[rng.randi_range(0, ALL.size() - 1)]
	house.character_id = from_land


## Re-reads every house from what its members have actually been doing. Offices
## held in temples make priests of a family; offices held in guilds of trade make
## merchants of it. Called on the slow epoch — a family does not change character
## in a season.
static func refresh_all(tick: int) -> void:
	if tick % REDEFINE_INTERVAL != 0:
		return
	var by_house := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.role_history.is_empty() or p.house_org_id == &"":
			continue
		for t in p.role_history:
			var org := GameState.get_organization(t.org_id)
			if org == null:
				continue
			var implied := _implied_by(org)
			if implied == &"":
				continue
			var counts: Dictionary = by_house.get(p.house_org_id, {})
			counts[implied] = int(counts.get(implied, 0)) + 1
			by_house[p.house_org_id] = counts

	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		var counts: Dictionary = by_house.get(house.org_id, {})
		var total := 0
		for key in counts:
			total += int(counts[key])
		if total < REDEFINE_MIN_OFFICES:
			continue
		for key in counts:
			if float(counts[key]) / float(total) < REDEFINE_SHARE:
				continue
			if house.character_id == key:
				continue
			var previous := house.character_id
			house.character_id = key
			HistoryLog.emit_event(
				HistoryEvent.EventType.IDEOLOGY_SHIFT,
				tick,
				"%sは代を重ねるうちに%sから%sへと性格を変えた。"
					% [house.display_name, label(previous), label(key)],
				{"from_character": String(previous), "to_character": String(key),
					"transient": true},
				house.org_id,
				house.leader_person_id,
				house.origin_event_id)
			break


## What holding office in this body says about a family.
static func _implied_by(org: Organization) -> StringName:
	match org.kind:
		Organization.OrgKind.RELIGION:
			return CLERICAL
		Organization.OrgKind.POLITICAL_SYSTEM:
			return NOBLE
	match org.archetype_id:
		&"temple_faction", &"millenarian_faction":
			return CLERICAL
		&"monster_hunters_guild", &"war_junta_faction":
			return MARTIAL
		&"merchants_guild", &"free_city_faction":
			return MERCANTILE
		&"mage_guild", &"technocrat_faction":
			return SCHOLARLY
		&"farmers_faction", &"levellers_faction":
			return AGRARIAN
	return &""


# -------------------------------------------------------------------- effects

## What a house's character is worth to it, in points of standing. Courtiers are
## worth more under a crown that has a court; priests are worth more where the
## country prays.
static func power_bonus(house: Organization) -> float:
	if house.character_id == &"":
		return 0.0
	var base: float = float(POWER_BONUS.get(house.character_id, 0.0)) * 40.0
	var realm := HouseRank.dominant_realm()
	var form := PolityFormEvaluator.form_of(realm)
	if form != null and SUPPORTS_FORMS.get(house.character_id, []).has(form.form_id):
		# The family and the country's shape suit each other, and both gain.
		base *= 1.8
	return base


## How much this house props up the form of government it lives under. A feudal
## crown standing on nine houses of courtiers is a different proposition from the
## same crown standing on nine houses of farmers who would rather it left.
static func realm_support(polity: Organization) -> float:
	var form := PolityFormEvaluator.form_of(polity)
	if form == null:
		return 0.0
	var supporting := 0.0
	var total := 0.0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		var weight: float = 1.0 + float(house.rank_tier)
		total += weight
		if SUPPORTS_FORMS.get(house.character_id, []).has(form.form_id):
			supporting += weight
	return 0.0 if total <= 0.0 else supporting / total


## The multiplier on a breakaway's chance, from the family the sitting leader
## comes from.
static func schism_affinity(org: Organization) -> float:
	var leader := GameState.get_person(org.leader_person_id)
	if leader == null or leader.house_org_id == &"":
		return 1.0
	var house := GameState.get_organization(leader.house_org_id)
	if house == null:
		return 1.0
	return float(SCHISM_AFFINITY.get(house.character_id, 1.0))
