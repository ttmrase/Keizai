class_name Incidents
extends RefCounted

## Ruptures: the handful of things that do not happen in the ordinary course of a
## century, and rearrange the board when they do.
##
## Everything else in this world moves by degrees — a family climbs, a faith
## spreads, a legitimacy drains. That is the right speed for almost everything
## and the wrong speed for the moments a history is actually remembered by. An
## incident is the other kind of event: it needs several unlikely things to be
## true at once, it happens in a single season, and what follows is not what was
## going to follow.
##
## The conditions are deliberately hard. Each of these wants two or three
## independent pressures at once — a country already angry, two bodies already
## past speaking to each other, a faith already holding most of the world — so
## that an incident reads as the thing those pressures were building toward
## rather than as a die coming up short.
##
## Their consequences go through the ordinary record: a death, a transfer of
## power, a regime falling. The INCIDENT event is the headline that says what
## they were all part of, which is what the 事件 screen reads.

const KIND_EXCOMMUNICATION := &"excommunication"
const KIND_ASSASSINATION := &"assassination"
const KIND_CAPITAL_SEIZURE := &"capital_seizure"
const KIND_UPRISING := &"uprising"

const KIND_LABELS := {
	KIND_EXCOMMUNICATION: "破門",
	KIND_ASSASSINATION: "暗殺",
	KIND_CAPITAL_SEIZURE: "王都制圧",
	KIND_UPRISING: "民衆蜂起",
}

## Nothing on this scale twice in a lifetime, of any kind.
const GLOBAL_COOLDOWN := 260
## And nothing of the same kind twice in three.
const KIND_COOLDOWN := 1100
## Checked rarely: these are not seasonal questions.
const CHECK_INTERVAL := 20

# --- 破門 ---
## A faith needs most of the world before it can afford to cut somebody out of it.
const EXCOMM_REACH := 0.65
## And the world has to have more than one answer for the cutting to mean anything.
const EXCOMM_DIVISION := 0.3
## What being cut out costs a family in standing, and its servants in loyalty.
const EXCOMM_HONOUR := 0.9
const EXCOMM_LOYALTY := 0.3
const EXCOMM_UNREST := 0.25

# --- 暗殺 ---
## Two bodies have to be past speaking to each other.
const ASSASSIN_HOSTILITY := -0.72
## And the country has to be somewhere a killing would not simply be punished.
const ASSASSIN_UNREST := 0.42
const ASSASSIN_LEGITIMACY_COST := 0.25
const ASSASSIN_UNREST_SHOCK := 0.18

# --- 王都制圧 ---
## Somebody armed has to be plainly stronger than the state.
const SEIZURE_STRENGTH := 1.25
const SEIZURE_UNREST := 0.4
const SEIZURE_LEGITIMACY := 0.55
## And be the sort of body that would.
const SEIZURE_MILITARISM := 0.25

# --- 民衆蜂起 ---
const UPRISING_UNREST := 0.6
## Not one bad province: most of the country.
const UPRISING_SHARE := 0.5


static func label_of(kind: StringName) -> String:
	return KIND_LABELS.get(kind, "事件")


static func consider_all(tick: int) -> void:
	if tick % CHECK_INTERVAL != 0:
		return
	if tick - _last_any() < GLOBAL_COOLDOWN:
		return
	# Ordered by how much they rearrange: the biggest rupture that qualifies is
	# the one that happens, and nothing else happens that season.
	if _try_capital_seizure(tick):
		return
	if _try_uprising(tick):
		return
	if _try_assassination(tick):
		return
	_try_excommunication(tick)


# ------------------------------------------------------------------ 破門

## A faith that holds most of the world cuts a great family out of it.
##
## The mark is not on the family's soldiers, it is on its standing: a house
## outside the faith its neighbours and its own servants hold is a house nobody
## owes anything to. What follows is not the excommunication, it is everything
## the excommunication makes possible.
static func _try_excommunication(tick: int) -> bool:
	if not _kind_ready(KIND_EXCOMMUNICATION, tick):
		return false
	if Religion.division() < EXCOMM_DIVISION:
		return false
	var faith := Religion.dominant_faith()
	if faith == null or faith.leader_person_id == &"":
		return false
	if Religion.reach_of(faith) < EXCOMM_REACH:
		return false

	# Not merely a family that believes something else — an eccentric is left to
	# it. The one that gets cut out is a great house of a rival confession that
	# is already ruling over the faithful, and only where the faith is strong
	# enough that the mark will actually stick to it.
	var target: Organization = null
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.NOBLE or house.faith_id == faith.org_id:
			continue
		if house.held_settlement_ids.is_empty() or house.honour <= -0.5:
			continue
		# A rival confession with ground of its own, not one man's opinion.
		if Religion.reach_of(GameState.get_organization(house.faith_id)) <= 0.0:
			continue
		# And a faith that cannot outweigh the family it is condemning has
		# condemned nothing.
		if faith.power_score < house.power_score:
			continue
		var holds_the_faithful := false
		for settlement_id in house.held_settlement_ids:
			var s: SettlementState = GameState.world.settlements.get(settlement_id)
			if s != null and s.religion_id == faith.org_id:
				holds_the_faithful = true
		if not holds_the_faithful:
			continue
		if target == null or house.power_score > target.power_score:
			target = house
	if target == null:
		return false

	var head := GameState.get_current_leader(target.org_id)
	target.honour = clampf(target.honour - EXCOMM_HONOUR, -2.0, 2.0)
	for servant in Retainers.retainers_of(target.org_id):
		servant.loyalty = maxf(0.0, servant.loyalty - EXCOMM_LOYALTY)
	for settlement_id in target.held_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(settlement_id)
		if s != null:
			s.unrest = clampf(s.unrest + EXCOMM_UNREST, 0.0, 1.0)
	# A crown outside the faith of its own country has very little left.
	var realm := HouseRank.dominant_realm()
	if realm != null and HouseRank.royal_house_id() == target.org_id:
		realm.legitimacy = maxf(0.05, realm.legitimacy - 0.3)

	_record(KIND_EXCOMMUNICATION, tick,
		"%sは%sを破門した。%sの家中は主を失った信徒となり、その所領は騒然となった。" % [
			faith.display_name, target.display_name,
			head.full_name if head != null else target.display_name],
		{"faith_id": String(faith.org_id), "target_house_id": String(target.org_id)},
		target.org_id, target.leader_person_id)
	return true


# ------------------------------------------------------------------ 暗殺

## Somebody at the head of something is killed by somebody who had run out of
## other ways to disagree with them.
static func _try_assassination(tick: int) -> bool:
	if not _kind_ready(KIND_ASSASSINATION, tick):
		return false
	if GameState.world.global_unrest < ASSASSIN_UNREST:
		return false

	# The two families furthest past speaking to each other, where one of them
	# holds something worth killing for.
	var victim_house: Organization = null
	var killer_house: Organization = null
	var worst := ASSASSIN_HOSTILITY
	for a in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if a.standing != Organization.Standing.NOBLE:
			continue
		for b in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			if b.org_id == a.org_id or b.standing != Organization.Standing.NOBLE:
				continue
			var standing := HouseRelations.relation(a.org_id, b.org_id)
			if standing >= worst:
				continue
			# The one with an office to lose is the one who gets killed.
			if GameState.offices_of_house(b.org_id).is_empty():
				continue
			worst = standing
			killer_house = a
			victim_house = b
	if victim_house == null or killer_house == null:
		return false

	var seats := GameState.offices_of_house(victim_house.org_id)
	var seat: Dictionary = seats[0]
	for candidate in seats:
		var held: Organization = candidate["org"]
		var best: Organization = seat["org"]
		if held.power_score > best.power_score:
			seat = candidate
	var victim: NotableIndividual = seat["person"]
	var body: Organization = seat["org"]

	HistoryLog.emit_event(
		HistoryEvent.EventType.DEATH,
		tick,
		"%s%sの%sが凶刃に倒れた。" % [body.display_name, seat["title"], victim.full_name],
		{"assassinated": true, "accused_house_id": String(killer_house.org_id)},
		body.org_id,
		victim.person_id,
		body.origin_event_id)

	# The accusation costs the accused whatever standing they had, whether or not
	# anybody proves it — which is the part that changes the next fifty years.
	killer_house.honour = clampf(killer_house.honour - 0.6, -2.0, 2.0)
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		s.unrest = clampf(s.unrest + ASSASSIN_UNREST_SHOCK, 0.0, 1.0)
	if body.kind == Organization.OrgKind.POLITICAL_SYSTEM:
		body.legitimacy = maxf(0.05, body.legitimacy - ASSASSIN_LEGITIMACY_COST)

	_record(KIND_ASSASSINATION, tick,
		"%sの%sが殺された。下手人は挙がらなかったが、誰もが%sを疑った。" % [
			body.display_name, victim.full_name, killer_house.display_name],
		{"victim_person_id": String(victim.person_id),
			"accused_house_id": String(killer_house.org_id),
			"body_org_id": String(body.org_id)},
		body.org_id, victim.person_id)
	return true


# ------------------------------------------------------------ 王都制圧

## An armed body plainly stronger than the state walks into the capital and takes
## it. The state does not negotiate its way out of this one: it ends, and what is
## founded in its place is founded on strength.
static func _try_capital_seizure(tick: int) -> bool:
	if not _kind_ready(KIND_CAPITAL_SEIZURE, tick):
		return false
	var realm := HouseRank.dominant_realm()
	if realm == null or realm.ideology == null:
		return false
	if realm.legitimacy > SEIZURE_LEGITIMACY:
		return false
	if WorldStateQuery.get_value(&"org.governed.avg_unrest", realm) < SEIZURE_UNREST:
		return false
	if realm.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
		return false

	var army: Organization = null
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		for org in GameState.organizations_of_kind(kind):
			if org.ideology == null \
					or org.ideology.get_axis(&"militarism_pacifism") < SEIZURE_MILITARISM:
				continue
			if org.power_score < realm.power_score * SEIZURE_STRENGTH:
				continue
			if army == null or org.power_score > army.power_score:
				army = org
	if army == null:
		return false

	var seat := _capital_of(realm)
	if seat != null:
		seat.unrest = clampf(seat.unrest + 0.3, 0.0, 1.0)
	_record(KIND_CAPITAL_SEIZURE, tick,
		"%sが%sを制圧した。門は内から開かれ、誰も血を流さずに国の主が替わった。" % [
			army.display_name, seat.display_name if seat != null else realm.display_name],
		{"army_org_id": String(army.org_id)},
		realm.org_id, realm.leader_person_id)

	# The state does not survive this. Forced through the ordinary machinery, so
	# a seizure founds a successor exactly the way any other upheaval does.
	RegimeShift.force_overturn(realm, {
		"org": army,
		"ground": "武力",
		"hold": 1.0,
		"basis": PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH,
		"structure": PoliticalSystemAxes.DecisionStructure.AUTOCRATIC,
	}, tick)
	return true


# ------------------------------------------------------------- 民衆蜂起

## Most of the country is past bearing it. What follows answers to a crowd.
static func _try_uprising(tick: int) -> bool:
	if not _kind_ready(KIND_UPRISING, tick):
		return false
	var realm := HouseRank.dominant_realm()
	if realm == null or realm.ideology == null:
		return false
	if realm.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.ELECTED:
		return false

	var burning := 0
	var total := 0
	var worst: SettlementState = null
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		total += 1
		if s.unrest >= UPRISING_UNREST:
			burning += 1
		if worst == null or s.unrest > worst.unrest:
			worst = s
	if total == 0 or float(burning) / float(total) < UPRISING_SHARE:
		return false

	# The family holding the worst of it loses it. Nobody grants this; it is
	# taken, and whoever was serving there is standing in the square.
	var fallen := GameState.get_organization(worst.ruling_house_id) if worst != null else null
	if fallen != null:
		fallen.honour = clampf(fallen.honour - 0.7, -2.0, 2.0)
		for servant in Retainers.retainers_of(fallen.org_id):
			servant.loyalty = maxf(0.0, servant.loyalty - 0.35)
	realm.legitimacy = maxf(0.05, realm.legitimacy - 0.35)

	_record(KIND_UPRISING, tick,
		"%sを筆頭に、国じゅうが立ち上がった。%sの威令はもはやどこにも届かない。" % [
			worst.display_name if worst != null else "諸地方", realm.display_name],
		{"worst_settlement": String(worst.id) if worst != null else "",
			"burning_regions": burning},
		realm.org_id, realm.leader_person_id)

	var voice := SocialTies.largest_bloc(realm)
	if voice != null:
		RegimeShift.force_overturn(realm, {
			"org": voice,
			"ground": "民衆",
			"hold": 1.0,
			"basis": PoliticalSystemAxes.LegitimacyBasis.ELECTED,
			"structure": PoliticalSystemAxes.DecisionStructure.ASSEMBLY,
		}, tick)
	return true


# ------------------------------------------------------------------ pressure

## How close each rupture currently stands, 0..1, and what is still holding it
## back. Read by the 事件 screen: this world is meant to be watched, and watching
## a pressure build is most of what there is to watch.
static func pressures() -> Array:
	return [
		_pressure_capital_seizure(),
		_pressure_uprising(),
		_pressure_assassination(),
		_pressure_excommunication(),
	]


static func _pressure_excommunication() -> Dictionary:
	var faith := Religion.dominant_faith()
	var reach := Religion.reach_of(faith)
	var division := Religion.division()
	var ready: float = minf(reach / EXCOMM_REACH, division / EXCOMM_DIVISION)
	var missing := ""
	if faith == null or faith.leader_person_id == &"":
		ready = 0.0
		missing = "教えを説く座がまだない"
	elif division < EXCOMM_DIVISION:
		missing = "世は一つの信仰にまとまっている"
	elif reach < EXCOMM_REACH:
		missing = "%sはまだ世の半ばに届かない" % faith.display_name
	else:
		missing = "%sは異なる信仰の大家を待っている" % faith.display_name
	return _pressure(KIND_EXCOMMUNICATION, ready, missing)


static func _pressure_assassination() -> Dictionary:
	var unrest := GameState.world.global_unrest
	var worst := 0.0
	for a in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		for b in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			if a.org_id != b.org_id:
				worst = minf(worst, HouseRelations.relation(a.org_id, b.org_id))
	var ready: float = minf(unrest / ASSASSIN_UNREST, worst / ASSASSIN_HOSTILITY)
	var missing := "国は落ち着いている"
	if unrest / ASSASSIN_UNREST < worst / ASSASSIN_HOSTILITY:
		missing = "不満はまだ足りない"
	else:
		missing = "家同士はまだ話ができている"
	return _pressure(KIND_ASSASSINATION, ready, missing)


static func _pressure_capital_seizure() -> Dictionary:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return _pressure(KIND_CAPITAL_SEIZURE, 0.0, "国がない")
	var strongest := 0.0
	var name := ""
	for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
		for org in GameState.organizations_of_kind(kind):
			if org.ideology == null \
					or org.ideology.get_axis(&"militarism_pacifism") < SEIZURE_MILITARISM:
				continue
			if org.power_score > strongest:
				strongest = org.power_score
				name = org.display_name
	var strength: float = strongest / maxf(1.0, realm.power_score * SEIZURE_STRENGTH)
	var unrest: float = WorldStateQuery.get_value(&"org.governed.avg_unrest", realm) / SEIZURE_UNREST
	var standing: float = SEIZURE_LEGITIMACY / maxf(0.01, realm.legitimacy)
	var ready: float = minf(minf(strength, unrest), standing)
	var missing := "武を頼む者がいない"
	if name.is_empty():
		missing = "武を頼む者がいない"
	elif strength <= unrest and strength <= standing:
		missing = "%sはまだ国より弱い" % name
	elif unrest <= standing:
		missing = "民はまだ門を開かない"
	else:
		missing = "%sの威信がまだ残っている" % realm.display_name
	return _pressure(KIND_CAPITAL_SEIZURE, ready, missing)


static func _pressure_uprising() -> Dictionary:
	var burning := 0
	var total := 0
	for id in GameState.world.settlements:
		total += 1
		if GameState.world.settlements[id].unrest >= UPRISING_UNREST:
			burning += 1
	var share: float = 0.0 if total == 0 else float(burning) / float(total)
	var ready: float = share / UPRISING_SHARE
	return _pressure(KIND_UPRISING, ready,
		"荒れているのは%d地方のうち%d" % [total, burning])


static func _pressure(kind: StringName, ready: float, missing: String) -> Dictionary:
	var last := _last_of(kind)
	return {
		"kind": kind,
		"label": label_of(kind),
		"pressure": clampf(ready, 0.0, 1.0),
		"missing": missing,
		"last_tick": last,
	}


# ------------------------------------------------------------------- record

## When each kind last happened, kept on the first state the world ever had.
##
## These are world-scoped facts and the record needs somewhere to put them that
## survives a save and a refounding alike. The original polity is the one thing
## guaranteed to exist for the life of a world — it is the root of its lineage,
## so it stays in the record even after it falls — which makes it the right shelf
## for a memory that belongs to the country rather than to any government of it.
static func _ledger() -> Organization:
	return GameState.root_of_kind(Organization.OrgKind.POLITICAL_SYSTEM)


static func _last_of(kind: StringName) -> int:
	var ledger := _ledger()
	if ledger == null:
		return -999999
	return int(ledger.last_fired_tick.get(_key(kind), -999999))


static func _key(kind: StringName) -> StringName:
	return StringName("incident_%s" % kind)


static func _last_any() -> int:
	var latest := -999999
	for kind in KIND_LABELS:
		latest = maxi(latest, _last_of(kind))
	return latest


static func _kind_ready(kind: StringName, tick: int) -> bool:
	return tick - _last_of(kind) >= KIND_COOLDOWN


static func _record(kind: StringName, tick: int, text: String, payload: Dictionary,
		subject_org: StringName, subject_person: StringName) -> void:
	var ledger := _ledger()
	if ledger != null:
		ledger.last_fired_tick[_key(kind)] = tick
	payload["incident_kind"] = String(kind)
	var subject := GameState.get_organization(subject_org)
	HistoryLog.emit_event(
		HistoryEvent.EventType.INCIDENT,
		tick,
		text,
		payload,
		subject_org,
		subject_person,
		subject.origin_event_id if subject != null else &"")


static func _capital_of(realm: Organization) -> SettlementState:
	var best: SettlementState = null
	for id in realm.governs_settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null and (best == null or s.population > best.population):
			best = s
	return best
