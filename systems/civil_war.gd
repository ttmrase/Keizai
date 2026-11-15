class_name CivilWar
extends RefCounted

## When a country splits rather than falls, and what the war that follows does
## to everyone in it.
##
## Until now a change of regime always took the whole country with it: whoever
## was holding the country up rewrote it, and the old order simply ended. That is
## right when the old order has nobody left — and wrong when half the country
## still stands behind it, or when the change was taken with a knife or at the
## gates. Then the country divides: the regions that keep faith with the old
## order stay with it, the rest go with the new one, and two states stand where
## one stood.
##
## The war itself is abstract. What matters is how it ends and what the ending
## does: which families lose their land and which are given it, which guilds and
## factions backed the wrong side, whose faith follows the victors into the
## regions they take. A war is the one moment in this world when the board is
## rearranged by force rather than by degrees, and the aftermath is where that
## shows.
##
## The god starts no wars and wins none. But a war is fought with what each side
## is made of — people, food, gold, hunters, smiths — and the dials and the
## disasters land on the two sides differently, which is room enough.
##
## Everything discrete goes through the record: the split is a SCHISM, the war
## opens with CONFLICT_DECLARED and closes with CONFLICT_RESOLVED, battles and
## defections are POWER_TRANSFERs carrying the war's id, the fallen die by DEATH.
## How the war stands is cached on the WarState.

# --- whether a country splits ---
## The share of the country (by people) that must stand with the old order.
const SPLIT_SHARE := 0.27
## Less, when the change was taken by force: a seizure makes enemies.
const FORCED_SPLIT_SHARE := 0.20
## Each side needs at least this many regions to be a side at all.
const MIN_SIDE_REGIONS := 2
## No country splits twice in this long, and no new war starts this soon after
## the last one ended anywhere.
const POLITY_COOLDOWN := 800
const WORLD_COOLDOWN := 320
## A knife in the right place within this long makes the next change forced.
const ASSASSINATION_MEMORY := 40

# --- how a war runs ---
const MIN_YEARS := 2
const MAX_YEARS := 30
const FRONT_PULL := 0.14
const FRONT_NOISE := 0.1
const BATTLE_CHANCE := 0.5
const EXHAUSTION_PER_YEAR := 0.05
const BATTLE_EXHAUSTION := 0.04
const DECISIVE_FRONT := 0.9
## What the old order fights with that a breakaway does not have yet: the
## treasury, the garrisons, the habit of being obeyed.
const INCUMBENCY := 1.2
## How far a battle moves the line, won outright or merely held.
const BATTLE_SWING_TAKEN := 0.16
const BATTLE_SWING := 0.1
## Losses where a battle is fought.
const BATTLE_POPULATION_LOSS := 0.08
const BATTLE_WEALTH_LOSS := 0.15
const LORD_DEATH_CHANCE := 0.14
const RULER_DEATH_CHANCE := 0.05
const DEFECTION_CHANCE := 0.18

# --- renewal ---
## How long two states that were one stay at peace before they may fight again.
const TRUCE_TICKS := 240
const RENEWAL_RATIO := 1.8
const RENEWAL_HOSTILITY := -0.25
const RENEWAL_CHANCE := 0.04

# --- aftermath ---
const ATTAINDER_HONOUR := 0.8
const REDUCTION_HONOUR := 0.35
const MERIT_HONOUR := 0.5
const WINNER_LEGITIMACY := 0.25
const OCCUPATION_UNREST := 0.25
const CONVERSION_CHANCE := 0.45
const LOSER_FORTUNE := -0.35
const WINNER_FORTUNE := 0.25
## A trade that swelled to fight a war shrinks when it ends.
const DEMOBILISATION := -0.2
const FORTUNE_DECAY := 0.02

## What each kind of body brings to a war, by archetype.
const WAR_WEIGHT := {
	&"monster_hunters_guild": 1.0,
	&"war_junta_faction": 1.0,
	&"artisans_guild": 0.7,
	&"merchants_guild": 0.6,
	&"mage_guild": 0.5,
}
const MARTIAL_ARCHETYPES: Array[StringName] = [&"monster_hunters_guild", &"war_junta_faction"]

const OUTCOME_LABELS := {
	"restoration": "復古",
	"revolution": "革命の成就",
	"reunification": "再統一",
	"peace": "講和",
}


# =================================================================== readers

static func wars() -> Array[WarState]:
	return GameState.world.wars


static func is_at_war(polity_id: StringName) -> bool:
	return war_of(polity_id) != null


static func war_of(polity_id: StringName) -> WarState:
	for war in GameState.world.wars:
		if war.involves(polity_id):
			return war
	return null


static func outcome_label(outcome: String) -> String:
	return OUTCOME_LABELS.get(outcome, "終戦")


## The state a family's cause lies with: whichever governs most of the land it
## holds — or, for a family with none, the state its liege's land lies in.
static func realm_of_house(house: Organization) -> StringName:
	var walk := house
	for depth in 3:
		if walk == null:
			return &""
		if not walk.held_settlement_ids.is_empty():
			var counts := {}
			for settlement_id in walk.held_settlement_ids:
				var s: SettlementState = GameState.world.settlements.get(settlement_id)
				if s != null and s.controlling_org_id != &"":
					counts[s.controlling_org_id] = int(counts.get(s.controlling_org_id, 0)) + 1
			var best := &""
			for id in counts:
				if best == &"" or counts[id] > counts[best] \
						or (counts[id] == counts[best] and String(id) < String(best)):
					best = id
			if best != &"":
				return best
		if walk.liege_house_id != &"":
			walk = GameState.get_organization(walk.liege_house_id)
			continue
		var seat: SettlementState = GameState.world.settlements.get(walk.dynasty_seat_settlement_id)
		return seat.controlling_org_id if seat != null else &""
	return &""


## The state a guild, faction or faith stands behind: its owning family's, or
## failing that its head's family's. Empty for a body with no stake.
static func side_of_body(org: Organization) -> StringName:
	var house := GameState.get_organization(org.patron_house_id)
	if house == null:
		var head := GameState.get_current_leader(org.org_id)
		if head != null:
			house = GameState.get_organization(head.house_org_id)
	if house == null or not house.is_active():
		return &""
	return realm_of_house(house)


## The house a state's cause centres on: its ruler's.
static func ruling_house_of(polity: Organization) -> Organization:
	if polity == null:
		return null
	var ruler := GameState.get_current_leader(polity.org_id)
	if ruler == null:
		return null
	return GameState.get_organization(ruler.house_org_id)


static func capital_of(polity: Organization) -> SettlementState:
	var best: SettlementState = null
	if polity == null:
		return null
	for id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null and (best == null or s.population > best.population):
			best = s
	return best


## Wars that have ended, newest first, read back off the permanent record.
static func past_wars(limit: int = 12) -> Array[HistoryEvent]:
	var out: Array[HistoryEvent] = []
	for i in range(HistoryLog.backbone.size() - 1, -1, -1):
		var e: HistoryEvent = HistoryLog.backbone[i]
		if e.event_type == HistoryEvent.EventType.CONFLICT_RESOLVED and e.payload.has("war_id"):
			out.append(e)
			if out.size() >= limit:
				break
	return out


static func battle_name(settlement_id: StringName) -> String:
	var s: SettlementState = GameState.world.settlements.get(settlement_id)
	return "%sの戦い" % (s.display_name if s != null else "名もなき野")


# ================================================================ the split

## Called by RegimeShift at the moment a regime would fall. Returns true if the
## country split instead — the old order keeps the regions that stand by it, the
## new one takes the rest, and the two are at war. Returns false, changing
## nothing, if the old order has too few friends left to fight for it.
static func try_split(polity: Organization, claimant: Dictionary, basis: int,
		structure: int, axis_shift: Dictionary, tick: int) -> bool:
	if polity == null or not polity.is_active() or polity.ideology == null:
		return false
	if not _may_start_war(polity, tick):
		return false
	var plan := plan_split(polity, claimant, tick)
	if not bool(plan.get("splits", false)):
		return false
	split_country(polity, claimant, plan, basis, structure, axis_shift, tick)
	return true


static func _may_start_war(polity: Organization, tick: int) -> bool:
	if not GameState.world.wars.is_empty():
		return false
	if polity.governs_settlement_ids.size() < MIN_SIDE_REGIONS * 2:
		return false
	if tick - int(polity.last_fired_tick.get(&"war", -999999)) < POLITY_COOLDOWN:
		return false
	return tick - _last_war_tick() >= WORLD_COOLDOWN


## How the regions of a country would divide if its regime were overturned now:
## which would hold to the old order and which would go with the claimant, and
## whether that is enough to split it. Read-only — the 兆し read it too.
static func plan_split(polity: Organization, claimant: Dictionary, tick: int) -> Dictionary:
	var winner: Organization = claimant.get("org")
	if winner == null:
		return {}
	var forced := bool(claimant.get("forced", false)) \
		or tick - Incidents.last_tick(Incidents.KIND_ASSASSINATION) <= ASSASSINATION_MEMORY
	var ground := String(claimant.get("ground", ""))
	var ruler_house := ruling_house_of(polity)
	var claimant_houses := _claimant_houses(winner)

	var loyal: Array[StringName] = []
	var rebel: Array[StringName] = []
	var loyal_people := 0.0
	var all_people := 0.0
	for settlement_id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s == null:
			continue
		var score := _loyalty_of_region(s, polity, winner, ruler_house, claimant_houses,
			forced, ground)
		all_people += s.population
		if score > 0.0:
			loyal.append(settlement_id)
			loyal_people += s.population
		else:
			rebel.append(settlement_id)
	var share := loyal_people / maxf(1.0, all_people)
	var needed := FORCED_SPLIT_SHARE if forced else SPLIT_SHARE
	return {
		"loyal": loyal,
		"rebel": rebel,
		"share": share,
		"needed": needed,
		"forced": forced,
		"splits": share >= needed and loyal.size() >= MIN_SIDE_REGIONS
			and rebel.size() >= MIN_SIDE_REGIONS,
	}


## Positive: this region stands by the old order. Read from what the world
## already knows — whose family holds it and how that family stands with the
## ruler's and with the challenger, what the region prays to and whom it speaks
## for, how angry it is, and how much the old order is still worth.
static func _loyalty_of_region(s: SettlementState, polity: Organization, winner: Organization,
		ruler_house: Organization, claimant_houses: Dictionary, forced: bool,
		ground: String) -> float:
	var score := (polity.legitimacy - 0.45) * 0.8
	if forced:
		score += 0.3
	var lord := GameState.get_organization(s.ruling_house_id)
	if lord != null and lord.is_active():
		if ruler_house != null:
			if lord.org_id == ruler_house.org_id:
				score += 1.2
			else:
				score += HouseRelations.relation(lord.org_id, ruler_house.org_id) * 0.7
				if lord.uji_id != &"" and lord.uji_id == ruler_house.uji_id:
					score += 0.3
				# A lord who has not forgiven the crown's house will not die for it.
				score -= 0.6 * minf(1.0, Grudges.toward(lord.org_id, ruler_house.org_id))
		score -= float(claimant_houses.get(lord.org_id, 0.0))
	if s.faction_lean_id != &"":
		if s.faction_lean_id == winner.org_id:
			score -= 0.5
		else:
			var lean := GameState.get_organization(s.faction_lean_id)
			if lean != null and lean.ideology != null \
					and lean.ideology.legitimacy_basis == polity.ideology.legitimacy_basis:
				score += 0.2
	if winner.kind == Organization.OrgKind.RELIGION and s.religion_id == winner.org_id:
		score -= 0.5
	# And what the lord of the region believes: a family that shares the old
	# state's creed stands by it, one that shares the challenger's goes over.
	if lord != null and lord.is_active():
		var belief := Doctrines.sympathy_of(lord)
		if belief != null:
			if belief.doctrine_id == polity.doctrine_id:
				score += 0.2
			var theirs := Doctrines.get_doctrine(winner.doctrine_id)
			if theirs == null:
				theirs = Doctrines.sympathy_of(winner)
			if theirs != null and belief.doctrine_id == theirs.doctrine_id:
				score -= 0.25
	if ruler_house != null and ruler_house.faith_id != &"" and s.religion_id == ruler_house.faith_id:
		score += 0.15
	score -= (s.unrest - 0.3) * 0.9
	if ground == "民衆":
		score -= s.unrest * 0.4
	return score


## Families that stand behind the challenger, and how firmly (house id -> 0..1.2).
static func _claimant_houses(winner: Organization) -> Dictionary:
	var out := {}
	if winner.kind == Organization.OrgKind.HOUSE:
		out[winner.org_id] = 1.2
	if winner.patron_house_id != &"":
		out[winner.patron_house_id] = 1.2
	var head := GameState.get_current_leader(winner.org_id)
	if head != null and head.house_org_id != &"":
		out[head.house_org_id] = maxf(float(out.get(head.house_org_id, 0.0)), 0.8)
	for backer_id in winner.support_base:
		var backer := GameState.get_organization(backer_id)
		if backer != null and backer.kind == Organization.OrgKind.HOUSE:
			out[backer_id] = maxf(float(out.get(backer_id, 0.0)),
				float(winner.support_base[backer_id]) * 0.9)
	return out


## Divides a country along a plan (see plan_split) and starts the war. Called
## by try_split once the plan says the country splits; public so a test can
## divide one along lines of its own choosing.
static func split_country(polity: Organization, claimant: Dictionary, plan: Dictionary, basis: int,
		structure: int, axis_shift: Dictionary, tick: int) -> void:
	var winner: Organization = claimant["org"]
	var ground := String(claimant.get("ground", ""))
	var rebel: Array[StringName] = []
	for id in plan["rebel"]:
		rebel.append(StringName(id))
	var old_capital := capital_of(polity)
	var ruler := GameState.get_current_leader(polity.org_id)
	var ruler_house := ruling_house_of(polity)

	var breakaway := Organization.new()
	breakaway.org_id = GameState.mint_org_id()
	breakaway.kind = Organization.OrgKind.POLITICAL_SYSTEM
	breakaway.archetype_id = polity.archetype_id
	breakaway.parent_org_id = polity.org_id
	breakaway.founding_tick = tick
	breakaway.member_count = maxi(5, int(polity.member_count * float(rebel.size())
		/ float(maxi(1, polity.governs_settlement_ids.size()))))
	breakaway.resources = {&"gold": polity.resources.get(&"gold", 0.0) * 0.4}
	breakaway.governs_settlement_ids = rebel.duplicate()
	breakaway.legitimacy = RegimeShift.FRESH_LEGITIMACY * 0.85
	breakaway.last_fired_tick[&"regime_shift"] = tick
	breakaway.last_fired_tick[&"war"] = tick
	breakaway.ideology = polity.ideology.clone()
	breakaway.ideology.legitimacy_basis = basis
	breakaway.ideology.decision_structure = structure
	for key in axis_shift:
		var axis := StringName(key)
		breakaway.ideology.set_axis(axis, lerpf(breakaway.ideology.get_axis(axis),
			float(axis_shift[key]), RegimeShift.AXIS_SEIZURE))
	breakaway.ideology_baseline = breakaway.ideology.clone()
	var profile := ContentRegistry.get_power_profile(breakaway.archetype_id)
	breakaway.leadership_title = profile.default_leadership_title if profile != null \
		else polity.leadership_title
	var named := PoliticalSystemGenerator.name_and_describe(breakaway, true, polity)
	breakaway.display_name = named["display_name"]
	breakaway.description = named["description"]

	polity.last_fired_tick[&"regime_shift"] = tick
	polity.last_fired_tick[&"war"] = tick

	HistoryLog.emit_event(
		HistoryEvent.EventType.SCHISM,
		tick,
		"%sを戴く%sに、国の半ばが従わなかった。%sは%sを掲げて%sを称した。" % [
			ruler.full_name if ruler != null else "旧体制", polity.formal_name(),
			_region_list(rebel), winner.formal_name(), breakaway.display_name],
		{
			"organization": breakaway.to_dict(),
			"schism_kind": "civil_war",
			"reason": ground,
			"seceded_settlements": Organization._names_to_strings(rebel),
			"claimant_org_id": String(winner.org_id),
			"claimant_leader_id": String(winner.leader_person_id),
			"founder_married_in": false,
		},
		breakaway.org_id,
		&"",
		polity.origin_event_id)

	var moved := ""
	var new_capital := capital_of(polity)
	if old_capital != null and new_capital != null and old_capital.id != new_capital.id:
		moved = "都を失った%sは%sに拠を移した。" % [polity.formal_name(), new_capital.display_name]
	var house_b := GameState.get_organization(winner.patron_house_id)
	if house_b == null and winner.kind == Organization.OrgKind.HOUSE:
		house_b = winner
	HistoryLog.emit_event(
		HistoryEvent.EventType.CONFLICT_DECLARED,
		tick,
		"%sと%sの間に戦が始まった。%s" % [polity.formal_name(), breakaway.display_name, moved],
		{
			"war": {
				"side_a": String(polity.org_id),
				"side_b": String(breakaway.org_id),
				"cause": "split",
				"ground": ground,
				"forced": bool(plan.get("forced", false)),
				"house_a": String(ruler_house.org_id) if ruler_house != null else "",
				"house_b": String(house_b.org_id) if house_b != null else "",
			},
			"loyal_share": float(plan.get("share", 0.0)),
			"claimant_org_id": String(winner.org_id),
		},
		polity.org_id,
		polity.leader_person_id,
		polity.origin_event_id,
		[] as Array[StringName])
	_note_war_start(tick)
	var war := war_of(polity.org_id)
	if war != null:
		Offices.appoint_war_command(war, tick)
	# The breakaway marches under its claimant's doctrine, if it has one: the
	# two sides are told apart by what they believe as much as by who leads them.
	var banner := Doctrines.get_doctrine(winner.doctrine_id)
	if banner == null:
		banner = Doctrines.sympathy_of(winner)
	if banner != null and banner.is_alive() and polity.doctrine_id != banner.doctrine_id:
		Doctrines._adopt(breakaway, banner, tick, "旗揚げした%sは" % breakaway.display_name)


static func _region_list(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null:
			names.append(s.display_name)
	if names.size() > 3:
		return "%sなど%d地方" % ["・".join(names.slice(0, 3)), names.size()]
	return "・".join(names)


# ============================================================ the war itself

static func step(tick: int) -> void:
	if tick % SimConfig.POWER_RECALC_EPOCH_TICKS == 0:
		_decay_fortunes()
	if tick % SimConfig.TICKS_PER_YEAR != 1:
		return
	for war in GameState.world.wars.duplicate():
		_campaign_year(war, tick)
	if GameState.world.wars.is_empty():
		_consider_renewal(tick)


static func _decay_fortunes() -> void:
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION,
			Organization.OrgKind.RELIGION]:
		for org in GameState.organizations_of_kind(kind):
			if not is_zero_approx(org.fortune):
				org.fortune = move_toward(org.fortune, 0.0, FORTUNE_DECAY)


static func _campaign_year(war: WarState, tick: int) -> void:
	var a := GameState.get_organization(war.side_a)
	var b := GameState.get_organization(war.side_b)
	if a == null or not a.is_active() or a.governs_settlement_ids.is_empty():
		_conclude(war, "b", tick)
		return
	if b == null or not b.is_active() or b.governs_settlement_ids.is_empty():
		_conclude(war, "a", tick)
		return

	var rng := RngService.stream(&"war")
	var sa: float = strength(a, war)["total"]
	var sb: float = strength(b, war)["total"]
	war.strength_a = sa
	war.strength_b = sb
	if war.opening_a <= 0.0 and war.opening_b <= 0.0:
		war.opening_a = sa
		war.opening_b = sb
	var ratio := (sa - sb) / maxf(0.01, sa + sb)
	war.front = clampf(war.front + ratio * FRONT_PULL + rng.randf_range(-FRONT_NOISE, FRONT_NOISE),
		-1.0, 1.0)
	war.exhaustion_a += EXHAUSTION_PER_YEAR + 0.03 * _starving_share(a)
	war.exhaustion_b += EXHAUSTION_PER_YEAR + 0.03 * _starving_share(b)

	if rng.randf() < BATTLE_CHANCE:
		_battle(war, a, b, ratio, tick)
	if war.years(tick) >= 1:
		_maybe_defect(war, a, b, tick)
	_check_end(war, tick)


## A side's strength and what it is made of. Read by the war each year and by
## the screen that shows why one side is winning.
static func strength(polity: Organization, war: WarState) -> Dictionary:
	var land := 0.0
	var unrest := 0.0
	var people := 0.0
	for id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s == null:
			continue
		land += s.population / 1000.0 + s.wealth / 2500.0
		unrest += s.unrest * s.population
		people += s.population
	unrest = unrest / maxf(1.0, people)

	var strongest := 1.0
	for org in GameState.active_organizations():
		strongest = maxf(strongest, org.power_score)

	var houses := 0.0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE or house.held_settlement_ids.is_empty():
			continue
		if realm_of_house(house) != polity.org_id:
			continue
		var h := 0.25 + 0.35 * clampf(house.power_score / strongest, 0.0, 1.0) \
			+ 0.05 * float(house.rank_tier)
		if house.character_id == HouseCharacter.MARTIAL:
			h += 0.25
		houses += h

	var bodies := 0.0
	var hunters_here := 0.0
	var hunters_all := 0.0
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		for org in GameState.organizations_of_kind(kind):
			var weight: float = float(WAR_WEIGHT.get(org.archetype_id, 0.25))
			var side := side_of_body(org)
			if org.archetype_id == &"monster_hunters_guild":
				hunters_all += org.power_score
				if side == polity.org_id:
					hunters_here += org.power_score
			if side == polity.org_id:
				bodies += clampf(org.power_score / strongest, 0.0, 1.0) * weight * 1.5

	var food := 1.0 - 0.35 * _starving_share(polity)
	var standing := 0.75 + 0.5 * polity.legitimacy
	var calm := 1.0 - 0.45 * unrest
	var hunter_share := hunters_here / hunters_all if hunters_all > 0.0 else 0.5
	var monsters := 1.0 - GameState.world.global_monster_threat_level * 0.35 * (1.0 - hunter_share)
	var worn := 1.0
	var incumbent := 1.0
	if war != null:
		var exhausted := war.exhaustion_a if war.side_of(polity.org_id) == "a" else war.exhaustion_b
		worn = 1.0 - 0.3 * clampf(exhausted, 0.0, 1.0)
		if war.cause == "split" and war.side_of(polity.org_id) == "a":
			incumbent = INCUMBENCY
	var command := Offices.command_bonus(polity) if war != null else 0.0
	var total := (land + houses + bodies + command) * food * standing * calm * monsters * worn * incumbent
	return {
		"total": total,
		"land": land,
		"houses": houses,
		"bodies": bodies,
		"food": food,
		"standing": standing,
		"calm": calm,
		"monsters": monsters,
		"worn": worn,
		"incumbent": incumbent,
		"command": command,
	}


static func _starving_share(polity: Organization) -> float:
	var starving := 0
	var total := 0
	for id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s == null:
			continue
		total += 1
		if s.starving:
			starving += 1
	return 0.0 if total == 0 else float(starving) / float(total)


## One battle a season, somewhere on the line between the two: the side the war
## is going for attacks the nearest region of the other.
static func _battle(war: WarState, a: Organization, b: Organization, ratio: float,
		tick: int) -> void:
	var rng := RngService.stream(&"war")
	var a_attacks := rng.randf() < 0.5 + 0.45 * war.front
	var attacker := a if a_attacks else b
	var defender := b if a_attacks else a
	var lean := war.front if a_attacks else -war.front
	var edge := ratio if a_attacks else -ratio
	var field := _border_region(attacker, defender)
	if field == null:
		return
	var won := rng.randf() < clampf(0.5 + 0.3 * lean + 0.3 * edge, 0.12, 0.88)
	var victor := attacker if won else defender
	var loser := defender if won else attacker
	var victor_side := war.side_of(victor.org_id)
	var taken := won and defender.governs_settlement_ids.size() > 1 and rng.randf() < 0.6

	# What a battle costs the place it is fought over, whoever wins it.
	field.population = maxf(SimConfig.MIN_POPULATION, field.population * (1.0 - BATTLE_POPULATION_LOSS))
	field.wealth *= 1.0 - BATTLE_WEALTH_LOSS
	field.unrest = clampf(field.unrest + 0.15, 0.0, 1.0)

	var name := battle_name(field.id)
	var text := "%s。%sは%sを破り、%sを手に入れた。" % [name, victor.formal_name(),
		loser.formal_name(), field.display_name] if taken \
		else "%s。%sは%sを退けた。" % [name, victor.formal_name(), loser.formal_name()]
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		text,
		{
			"war_id": String(war.war_id),
			"battle": {"settlement_id": String(field.id), "winner": victor_side, "taken": taken},
			"settlement_ids": [String(field.id)] if taken else [],
			"from_org_id": String(loser.org_id),
		},
		victor.org_id,
		victor.leader_person_id,
		victor.origin_event_id)

	var swing := BATTLE_SWING_TAKEN if taken else BATTLE_SWING
	war.front = clampf(war.front + (swing if victor_side == "a" else -swing), -1.0, 1.0)
	war.exhaustion_a += BATTLE_EXHAUSTION
	war.exhaustion_b += BATTLE_EXHAUSTION
	if victor_side == "a":
		war.exhaustion_b += BATTLE_EXHAUSTION
	else:
		war.exhaustion_a += BATTLE_EXHAUSTION

	# The lord who held the field, if they were on the losing side, and now and
	# then the losing side's own head, fall with it.
	var lord_house := GameState.get_organization(field.ruling_house_id)
	if lord_house != null and realm_of_house(lord_house) == loser.org_id \
			and rng.randf() < LORD_DEATH_CHANCE:
		_fall_in_battle(GameState.get_current_leader(lord_house.org_id), name, war, tick)
	if rng.randf() < RULER_DEATH_CHANCE:
		_fall_in_battle(GameState.get_current_leader(loser.org_id), name, war, tick)


static func _fall_in_battle(person: NotableIndividual, battle: String, war: WarState,
		tick: int) -> void:
	if person == null or not person.is_alive():
		return
	var house := GameState.get_organization(person.house_org_id)
	HistoryLog.emit_event(
		HistoryEvent.EventType.DEATH,
		tick,
		"%sは%sで討ち死にした。" % [person.full_name, battle],
		{"killed_in_battle": true, "war_id": String(war.war_id)},
		house.org_id if house != null else &"",
		person.person_id,
		house.origin_event_id if house != null else &"")


## The defender's region nearest to anything the attacker holds.
static func _border_region(attacker: Organization, defender: Organization) -> SettlementState:
	var best: SettlementState = null
	var best_distance := INF
	for did in defender.governs_settlement_ids:
		var d: SettlementState = GameState.world.settlements.get(did)
		if d == null:
			continue
		for aid in attacker.governs_settlement_ids:
			var a: SettlementState = GameState.world.settlements.get(aid)
			if a == null:
				continue
			var distance := d.position.distance_to(a.position)
			if distance < best_distance:
				best_distance = distance
				best = d
	return best


## A family on the losing side with reason to like the winning one — kin by 氏,
## friends of its ruling house, or just nervous — goes over with its land.
static func _maybe_defect(war: WarState, a: Organization, b: Organization, tick: int) -> void:
	if absf(war.front) < 0.3:
		return
	var rng := RngService.stream(&"war")
	var losing := b if war.front > 0.0 else a
	var winning := a if war.front > 0.0 else b
	var winning_house := ruling_house_of(winning)
	var losing_house := ruling_house_of(losing)
	var best: Organization = null
	var best_pull := 0.15
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE or house.held_settlement_ids.is_empty():
			continue
		if realm_of_house(house) != losing.org_id or war.defectors.has(house.org_id):
			continue
		if house.org_id == war.house_a or house.org_id == war.house_b:
			continue
		if losing_house != null and house.org_id == losing_house.org_id:
			continue
		var pull := 0.2 * absf(war.front)
		if winning_house != null:
			pull += HouseRelations.relation(house.org_id, winning_house.org_id)
			if house.uji_id != &"" and house.uji_id == winning_house.uji_id:
				pull += 0.35
		if losing_house != null:
			pull -= 0.3 * HouseRelations.relation(house.org_id, losing_house.org_id)
			# An old grudge against one's own side is the easiest reason to leave it,
			# and one against the other side the hardest to get past.
			pull += 0.45 * minf(1.0, Grudges.toward(house.org_id, losing_house.org_id))
		if winning_house != null:
			pull -= 0.45 * minf(1.0, Grudges.toward(house.org_id, winning_house.org_id))
		if pull > best_pull:
			best_pull = pull
			best = house
	if best == null or rng.randf() > DEFECTION_CHANCE:
		return
	var lands: Array = []
	for settlement_id in best.held_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s != null and s.controlling_org_id == losing.org_id:
			lands.append(String(settlement_id))
	if lands.is_empty():
		return
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		"%sは%sを見限り、所領%sごと%sに寝返った。" % [best.formal_name(), losing.formal_name(),
			_region_list(lands), winning.formal_name()],
		{
			"war_id": String(war.war_id),
			"defector_house_id": String(best.org_id),
			"settlement_ids": lands,
			"from_org_id": String(losing.org_id),
		},
		winning.org_id,
		best.leader_person_id,
		best.origin_event_id)
	war.front = clampf(war.front + (0.1 if winning.org_id == war.side_a else -0.1), -1.0, 1.0)


static func _check_end(war: WarState, tick: int) -> void:
	var a := GameState.get_organization(war.side_a)
	var b := GameState.get_organization(war.side_b)
	if a.governs_settlement_ids.is_empty():
		_conclude(war, "b", tick)
		return
	if b.governs_settlement_ids.is_empty():
		_conclude(war, "a", tick)
		return
	var years := war.years(tick)
	if years < MIN_YEARS:
		return
	if war.front >= DECISIVE_FRONT:
		_conclude(war, "a", tick)
	elif war.front <= -DECISIVE_FRONT:
		_conclude(war, "b", tick)
	elif war.exhaustion_a >= 1.0 and war.exhaustion_b >= 1.0:
		if absf(war.front) >= 0.5:
			_conclude(war, "a" if war.front > 0.0 else "b", tick)
		else:
			_conclude(war, "", tick)
	elif war.exhaustion_a >= 1.0 and war.front < -0.35:
		_conclude(war, "b", tick)
	elif war.exhaustion_b >= 1.0 and war.front > 0.35:
		_conclude(war, "a", tick)
	elif years >= MAX_YEARS:
		if absf(war.front) >= 0.6:
			_conclude(war, "a" if war.front > 0.0 else "b", tick)
		else:
			_conclude(war, "", tick)


# ================================================================ the ending

## Ends a war: "a" or "b" won it outright, "" means both were too worn out to
## go on and the border holds where it is.
static func _conclude(war: WarState, winner_side: String, tick: int) -> void:
	if winner_side == "":
		_make_peace(war, tick)
	else:
		_settle_victory(war, winner_side, tick)
	_note_war_end(tick)


static func _make_peace(war: WarState, tick: int) -> void:
	var a := GameState.get_organization(war.side_a)
	var b := GameState.get_organization(war.side_b)
	var lines: Array[String] = ["国は%sと%sの二つに分かれたまま、境が定まった" % [
		a.formal_name(), b.formal_name()]]
	Offices.settle_war_command(war, "", tick)
	for polity in [a, b]:
		polity.legitimacy = maxf(0.1, polity.legitimacy - 0.05)
		polity.last_fired_tick[&"war"] = tick
	var shrunk := _demobilise()
	if not shrunk.is_empty():
		lines.append("戦で膨らんだ%sは縮んだ" % "・".join(shrunk))
	HistoryLog.emit_event(
		HistoryEvent.EventType.CONFLICT_RESOLVED,
		tick,
		"%sと%sは%d年の戦の末に矛を収めた。勝者はなく、国は二つのまま残った。" % [
			a.formal_name(), b.formal_name(), war.years(tick)],
		{
			"war_id": String(war.war_id),
			"outcome": "peace",
			"side_a": String(war.side_a),
			"side_b": String(war.side_b),
			"years": war.years(tick),
			"battles": war.battles.size(),
			"cause": war.cause,
			"aftermath": lines,
		},
		war.side_a,
		&"",
		a.origin_event_id)


static func _settle_victory(war: WarState, winner_side: String, tick: int) -> void:
	var winner := GameState.get_organization(war.side_a if winner_side == "a" else war.side_b)
	var loser := GameState.get_organization(war.side_b if winner_side == "a" else war.side_a)
	var outcome := "reunification" if war.cause == "renewal" \
		else ("restoration" if winner_side == "a" else "revolution")
	var rng := RngService.stream(&"war")

	# Who stood where, read before anything moves.
	var loser_house := ruling_house_of(loser)
	var winner_house := ruling_house_of(winner)
	var losers: Array[Organization] = []
	var winners: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE:
			continue
		var realm := realm_of_house(house)
		if realm == loser.org_id and not war.defectors.has(house.org_id):
			losers.append(house)
		elif realm == winner.org_id:
			winners.append(house)
	var core: Array[Organization] = []
	for candidate in [loser_house, GameState.get_organization(
			war.house_a if winner_side == "b" else war.house_b)]:
		if candidate != null and candidate.is_active() and not core.has(candidate) \
				and not war.defectors.has(candidate.org_id) \
				and (winner_house == null or candidate.org_id != winner_house.org_id):
			core.append(candidate)
	var strongest_loser: Organization = null
	for house in losers:
		if not core.has(house) and (strongest_loser == null
				or house.power_score > strongest_loser.power_score):
			strongest_loser = house
	if strongest_loser != null:
		core.append(strongest_loser)
	var reduced: Array[Organization] = []
	for house in losers:
		if not core.has(house):
			reduced.append(house)
	winners.sort_custom(func(x: Organization, y: Organization):
		if winner_house != null and (x.org_id == winner_house.org_id) != (y.org_id == winner_house.org_id):
			return x.org_id == winner_house.org_id
		if not is_equal_approx(x.power_score, y.power_score):
			return x.power_score > y.power_score
		return String(x.org_id) < String(y.org_id))
	# A family answering for the losing cause is not also rewarded for winning it.
	var deserving: Array[Organization] = []
	for house in winners:
		if not core.has(house) and not reduced.has(house):
			deserving.append(house)
	var merit: Array[Organization] = deserving.slice(0, 3)
	if merit.is_empty() and winner_house != null:
		merit.append(winner_house)
	var sides := _body_sides(winner, loser)

	var lines: Array[String] = []
	var headline := ""
	match outcome:
		"restoration":
			headline = "%sは%sを打ち破った。旧き秩序は国を取り戻した。" % [
				winner.formal_name(), loser.formal_name()]
		"revolution":
			headline = "%sは%sを打ち倒した。新しい秩序が国を手にした。" % [
				winner.formal_name(), loser.formal_name()]
		_:
			headline = "%sは%sを併せ、国はふたたび一つになった。" % [
				winner.formal_name(), loser.formal_name()]
	var attainted: Array = []
	var reduced_ids: Array = []
	var rewarded: Array = []
	for house in core:
		attainted.append(String(house.org_id))
		lines.append("%sは改易" % house.formal_name())
	for house in reduced:
		reduced_ids.append(String(house.org_id))
	if not reduced.is_empty():
		lines.append("%sは減封" % _house_list(reduced))
	for house in merit.slice(0, 2):
		rewarded.append(String(house.org_id))
	if not merit.is_empty():
		lines.append("%sは加増・叙勲" % _house_list(merit.slice(0, 2)))
	var pardoned: Array[Organization] = []
	for id in war.defectors:
		var house := GameState.get_organization(id)
		if house != null and house.is_active():
			pardoned.append(house)
	if not pardoned.is_empty():
		lines.append("寝返った%sは赦された" % _house_list(pardoned))
	var down_bodies: Array[String] = []
	var up_bodies: Array[String] = []
	for org_id in sides:
		var org := GameState.get_organization(org_id)
		if org == null:
			continue
		if sides[org_id] == loser.org_id:
			down_bodies.append(org.formal_name())
		elif sides[org_id] == winner.org_id:
			up_bodies.append(org.formal_name())
	if not down_bodies.is_empty():
		lines.append("%sは議席と人を失った" % "・".join(down_bodies.slice(0, 3)))
	if not up_bodies.is_empty():
		lines.append("%sは伸びた" % "・".join(up_bodies.slice(0, 3)))

	var ending := HistoryLog.emit_event(
		HistoryEvent.EventType.CONFLICT_RESOLVED,
		tick,
		"%d年の戦が終わった。%s" % [war.years(tick), headline],
		{
			"war_id": String(war.war_id),
			"outcome": outcome,
			"winner": String(winner.org_id),
			"loser": String(loser.org_id),
			"side_a": String(war.side_a),
			"side_b": String(war.side_b),
			"years": war.years(tick),
			"battles": war.battles.size(),
			"cause": war.cause,
			"attainted": attainted,
			"reduced": reduced_ids,
			"rewarded": rewarded,
			"pardoned": Organization._names_to_strings(war.defectors),
			"winner_ruler_id": String(winner.leader_person_id),
			# Whether the side that won was the weaker when the war began.
			"underdog": _opening_of(war, winner_side) < _opening_of(war,
				"b" if winner_side == "a" else "a") * 0.85,
			"aftermath": lines,
		},
		winner.org_id,
		winner.leader_person_id,
		winner.origin_event_id)

	# Its commanders' deeds go to their families, while both states still stand.
	Offices.settle_war_command(war, winner_side, tick)

	# The losing state's regions go to the winner.
	var annexed: Array = Organization._names_to_strings(loser.governs_settlement_ids)
	if not annexed.is_empty():
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sの治めていた%sは%sに帰した。" % [loser.formal_name(), _region_list(annexed),
				winner.formal_name()],
			{"war_id": String(war.war_id), "annexed": true, "settlement_ids": annexed,
				"from_org_id": String(loser.org_id)},
			winner.org_id,
			winner.leader_person_id,
			winner.origin_event_id)

	# The families at the heart of the losing cause lose everything they hold;
	# the rest who stood with it lose a part; the winners are given it.
	var turn := 0
	for house in core:
		var held := house.held_settlement_ids.duplicate()
		for i in held.size():
			var recipient: Organization = null
			if not merit.is_empty():
				recipient = merit[turn % merit.size()]
			turn += 1
			if recipient == null or recipient.org_id == house.org_id:
				continue
			_transfer_estate(war, house, recipient, held[i], i == held.size() - 1, tick,
				"%sは改易され、%sは%sに与えられた。")
		house.honour = clampf(house.honour - ATTAINDER_HONOUR, -2.0, 2.0)
		_mark(house, "attainder", 0.5, war, tick, "%sは改易の汚名を負った。")
	for house in reduced:
		if house.held_settlement_ids.size() < 2 or merit.is_empty():
			house.honour = clampf(house.honour - REDUCTION_HONOUR, -2.0, 2.0)
			continue
		var recipient := merit[turn % merit.size()]
		turn += 1
		if recipient.org_id != house.org_id:
			_transfer_estate(war, house, recipient,
				house.held_settlement_ids[house.held_settlement_ids.size() - 1], false, tick,
				"%sは減封され、%sは%sに移された。")
		house.honour = clampf(house.honour - REDUCTION_HONOUR, -2.0, 2.0)
		_mark(house, "reduction", 0.2, war, tick, "%sは減封の汚名を負った。")
	for house in merit.slice(0, 2):
		house.honour = clampf(house.honour + MERIT_HONOUR, -2.0, Honours.HONOUR_CEILING)
		HistoryLog.emit_event(
			HistoryEvent.EventType.POWER_TRANSFER,
			tick,
			"%sは戦功を賞され、その家格を引き上げられた。" % house.formal_name(),
			{"war_id": String(war.war_id), "war_honour": true, "honour": true},
			house.org_id,
			house.leader_person_id,
			house.origin_event_id)

	# The guilds, factions and faiths that backed each side.
	for org_id in sides:
		var org := GameState.get_organization(org_id)
		if org == null:
			continue
		if sides[org_id] == loser.org_id:
			org.fortune = clampf(org.fortune + LOSER_FORTUNE, -1.0, 1.0)
			org.member_count = maxi(5, int(org.member_count * 0.65))
			org.resources[&"gold"] = float(org.resources.get(&"gold", 0.0)) * 0.5
		elif sides[org_id] == winner.org_id:
			org.fortune = clampf(org.fortune + WINNER_FORTUNE, -1.0, 1.0)
			org.member_count = int(org.member_count * 1.1)
	_demobilise()

	# The victors' faith follows them into the regions they took.
	var faith := _faith_of_side(winner, winner_house)
	if faith != null:
		for raw_id in annexed:
			var s: SettlementState = GameState.world.settlements.get(StringName(raw_id))
			if s == null or s.religion_id == faith.org_id:
				continue
			if rng.randf() > CONVERSION_CHANCE:
				continue
			var previous := GameState.get_organization(s.religion_id)
			s.religion_id = faith.org_id
			HistoryLog.emit_event(
				HistoryEvent.EventType.IDEOLOGY_SHIFT,
				tick,
				"%sの人々は%sとともに来た%sに改宗した。" % [s.display_name,
					winner.formal_name(), faith.display_name],
				{"settlement": String(s.id), "from_faith":
					String(previous.org_id) if previous != null else "", "transient": true,
					"war_id": String(war.war_id)},
				faith.org_id,
				faith.leader_person_id,
				faith.origin_event_id)

	# The country as a whole.
	for raw_id in annexed:
		var s: SettlementState = GameState.world.settlements.get(StringName(raw_id))
		if s != null:
			s.unrest = clampf(s.unrest + OCCUPATION_UNREST, 0.0, 1.0)
	winner.legitimacy = minf(RegimeShift.LEGITIMACY_CEILING, winner.legitimacy + WINNER_LEGITIMACY)
	winner.last_fired_tick[&"war"] = tick

	# The losing ruler does not survive the cause, and the losing state ends.
	var fallen_ruler := GameState.get_current_leader(loser.org_id)
	if fallen_ruler != null and fallen_ruler.is_alive():
		var fallen_house := GameState.get_organization(fallen_ruler.house_org_id)
		HistoryLog.emit_event(
			HistoryEvent.EventType.DEATH,
			tick,
			"敗れた%sの%sは捕らえられ、処刑された。" % [loser.formal_name(), fallen_ruler.full_name],
			{"executed": true, "war_id": String(war.war_id)},
			fallen_house.org_id if fallen_house != null else &"",
			fallen_ruler.person_id,
			fallen_house.origin_event_id if fallen_house != null else &"")
	HistoryLog.emit_event(
		HistoryEvent.EventType.DISSOLVED,
		tick,
		"%sはここに滅んだ。" % loser.formal_name(),
		{"succeeded_by": String(winner.org_id), "depose_ruler": true,
			"war_id": String(war.war_id)},
		loser.org_id,
		loser.leader_person_id,
		loser.origin_event_id)
	# Whoever won it may be one the histories keep.
	Greatness.consider_war(ending, tick)


## A mark against a family's name, for its grounds of rank (HouseRank).
static func _mark(house: Organization, kind: String, weight: float, war: WarState, tick: int,
		template: String) -> void:
	HistoryLog.emit_event(
		HistoryEvent.EventType.OFFICE,
		tick,
		template % house.formal_name(),
		{"action": "blemish", "kind": kind, "weight": weight, "war_id": String(war.war_id),
			"polity": ""},
		house.org_id,
		house.leader_person_id,
		house.origin_event_id)


static func _opening_of(war: WarState, side: String) -> float:
	return war.opening_a if side == "a" else war.opening_b


static func _transfer_estate(war: WarState, from_house: Organization, to_house: Organization,
		settlement_id: StringName, last: bool, tick: int, template: String) -> void:
	var s: SettlementState = GameState.world.settlements.get(settlement_id)
	HistoryLog.emit_event(
		HistoryEvent.EventType.POWER_TRANSFER,
		tick,
		template % [from_house.formal_name(), s.display_name if s != null else "その領",
			to_house.formal_name()],
		{
			"war_id": String(war.war_id),
			"estate": true,
			"from_house_id": String(from_house.org_id),
			"settlement_ids": [String(settlement_id)],
			"demote_source": last,
		},
		to_house.org_id,
		to_house.leader_person_id,
		to_house.origin_event_id)


## Which side each guild, faction and faith was on: org id -> state id.
static func _body_sides(a: Organization, b: Organization) -> Dictionary:
	var out := {}
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION,
			Organization.OrgKind.RELIGION]:
		for org in GameState.organizations_of_kind(kind):
			var side := side_of_body(org)
			if side == a.org_id or side == b.org_id:
				out[org.org_id] = side
	return out


## The trades that swell for a war and shrink after it. Returns their names.
static func _demobilise() -> Array[String]:
	var out: Array[String] = []
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		for org in GameState.organizations_of_kind(kind):
			if MARTIAL_ARCHETYPES.has(org.archetype_id):
				org.fortune = clampf(org.fortune + DEMOBILISATION, -1.0, 1.0)
				out.append(org.formal_name())
	return out


static func _faith_of_side(polity: Organization, ruler_house: Organization) -> Organization:
	if ruler_house != null:
		var faith := GameState.get_organization(ruler_house.faith_id)
		if faith != null and faith.is_active():
			return faith
	var counts := {}
	for id in polity.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null and s.religion_id != &"":
			counts[s.religion_id] = int(counts.get(s.religion_id, 0)) + 1
	var best := &""
	for id in counts:
		if best == &"" or counts[id] > counts[best]:
			best = id
	return GameState.get_organization(best)


static func _house_list(houses: Array) -> String:
	var names: Array[String] = []
	for house in houses:
		names.append(house.formal_name())
	return "・".join(names)


# ================================================================== renewal

## Two states that were one, a generation after the truce: if one has grown far
## stronger than the other and their ruling families are past speaking to each
## other, the stronger may try to finish what the last war did not.
static func _consider_renewal(tick: int) -> void:
	if tick - _last_war_tick() < WORLD_COOLDOWN:
		return
	var polities := GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)
	if polities.size() < 2:
		return
	polities.sort_custom(func(x: Organization, y: Organization): return String(x.org_id) < String(y.org_id))
	var rng := RngService.stream(&"war")
	for i in polities.size():
		for j in range(i + 1, polities.size()):
			var p := polities[i]
			var q := polities[j]
			if p.governs_settlement_ids.is_empty() or q.governs_settlement_ids.is_empty():
				continue
			if tick - int(p.last_fired_tick.get(&"war", p.founding_tick)) < TRUCE_TICKS \
					or tick - int(q.last_fired_tick.get(&"war", q.founding_tick)) < TRUCE_TICKS:
				continue
			var sp: float = strength(p, null)["total"]
			var sq: float = strength(q, null)["total"]
			if maxf(sp, sq) / maxf(0.01, minf(sp, sq)) < RENEWAL_RATIO:
				continue
			var hp := ruling_house_of(p)
			var hq := ruling_house_of(q)
			var hostile := hp != null and hq != null \
				and HouseRelations.relation(hp.org_id, hq.org_id) <= RENEWAL_HOSTILITY
			var estranged := p.ideology != null and q.ideology != null \
				and p.ideology.legitimacy_basis != q.ideology.legitimacy_basis
			if not hostile and not estranged:
				continue
			if rng.randf() > RENEWAL_CHANCE:
				continue
			# The elder state is side A, whichever is stronger.
			var elder := p if p.branch_depth <= q.branch_depth else q
			var younger := q if elder == p else p
			_declare_renewal(elder, younger, tick)
			return


static func _declare_renewal(a: Organization, b: Organization, tick: int) -> void:
	var ha := ruling_house_of(a)
	var hb := ruling_house_of(b)
	a.last_fired_tick[&"war"] = tick
	b.last_fired_tick[&"war"] = tick
	HistoryLog.emit_event(
		HistoryEvent.EventType.CONFLICT_DECLARED,
		tick,
		"休戦は終わった。%sと%sは、ふたたび国を一つにしようと戦を構えた。" % [
			a.formal_name(), b.formal_name()],
		{
			"war": {
				"side_a": String(a.org_id),
				"side_b": String(b.org_id),
				"cause": "renewal",
				"ground": "",
				"forced": false,
				"house_a": String(ha.org_id) if ha != null else "",
				"house_b": String(hb.org_id) if hb != null else "",
			},
		},
		a.org_id,
		a.leader_person_id,
		a.origin_event_id,
		[] as Array[StringName])
	_note_war_start(tick)
	var war := war_of(a.org_id)
	if war != null:
		Offices.appoint_war_command(war, tick)


# =================================================================== ledger

## When the last war began or ended anywhere, kept on the first state the world
## ever had — the same shelf Incidents keeps its memory on.
static func _ledger() -> Organization:
	return GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)


static func _last_war_tick() -> int:
	var ledger := _ledger()
	return int(ledger.last_fired_tick.get(&"war_any", -999999)) if ledger != null else -999999


static func _note_war_start(tick: int) -> void:
	var ledger := _ledger()
	if ledger != null:
		ledger.last_fired_tick[&"war_any"] = tick


static func _note_war_end(tick: int) -> void:
	_note_war_start(tick)


# =================================================================== outlook

## Whether the country would split if the regime fell now, for the 兆し and the
## 事件 screen: who is pressing it, and how much of the country would hold.
static func split_outlook(polity: Organization) -> Dictionary:
	if polity == null or polity.ideology == null:
		return {}
	var claimant := RegimeShift.standing_challenge(polity)
	if claimant.is_empty():
		return {}
	var plan := plan_split(polity, claimant, SimClock.current_tick)
	if plan.is_empty():
		return {}
	plan["claimant"] = claimant["org"]
	return plan
