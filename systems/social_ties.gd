class_name SocialTies
extends RefCounted

## The horizontal wiring between the four kinds of institution, and the land.
##
## Guilds, houses, factions and regimes each made sense on their own but stood
## side by side without touching. This is what runs between them, recomputed
## every epoch from things that are already true:
##
##   house  → guild/faction   a family whose members keep taking an office ends
##                            up owning it, and the office becomes hereditary
##   house  → faction         who actually stands behind a body of opinion
##   guild  → faction         and which trades stand behind it
##   faction → regime         how the chamber divides, which is what a faction
##                            *is* in a regime that has one
##   land   → all of it       a region's industry gives some faction a
##                            constituency and some guild a claim, and the house
##                            holding it carries both into the capital
##
## None of it is stored as an opinion that drifts on its own. It is read off
## offices held, marriages made, ideals professed and ground occupied, so when
## the cause goes the tie goes with it.

# --- support base ---
## Strands of backing, before clamping to 0..1.
const IDEOLOGY_BACKING := 0.55
const OFFICE_BACKING := 0.35
const PATRON_BACKING := 0.45
const LAND_BACKING := 0.30
## And what the two of them believe. Worth nothing where the world all prays the
## same way, and a great deal where it does not — see Religion.division().
const FAITH_BACKING := 0.32
## Ideological distance at which two bodies stop having anything in common.
const IDEOLOGY_SPAN := 0.34
## Below this a backer is not worth listing; it keeps the record to real ties.
const SUPPORT_FLOOR := 0.18

# --- patron house ---
## Share of an office's whole recorded history one family must have held before
## the office counts as theirs.
const PATRON_SHARE := 0.55
## And how long that history has to be before the share means anything.
const PATRON_MIN_TENURE_TICKS := 240
## How fast a captured office drifts toward admitting it is hereditary.
const CAPTURE_DRIFT := 0.035

enum OfficeBasis { HEREDITARY, MERITOCRATIC, CONSULTATIVE }

const OFFICE_BASIS_LABELS := {
	OfficeBasis.HEREDITARY: "世襲制",
	OfficeBasis.MERITOCRATIC: "実力制",
	OfficeBasis.CONSULTATIVE: "協議制",
}


static func refresh_all(tick: int) -> void:
	var bodies := _political_bodies()
	var tenure_by_house := _tenure_by_house(tick)

	for org in bodies:
		_settle_patron(org, tenure_by_house.get(org.org_id, {}), tick)
	for org in bodies:
		_settle_support_base(org)

	_settle_regional_lean()
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		_settle_seats(polity)


## Guilds, factions and faiths: the bodies that have a following rather than a
## bloodline. Faiths belong here for the same reason the others do — a temple
## whose seat one family has held for three generations is that family's temple,
## and the houses that hold its faith are its constituency in exactly the way a
## trade is a faction's.
static func _political_bodies() -> Array[Organization]:
	var out: Array[Organization] = []
	out.append_array(GameState.organizations_of_kind(Organization.OrgKind.GUILD))
	out.append_array(GameState.organizations_of_kind(Organization.OrgKind.FACTION))
	out.append_array(GameState.organizations_of_kind(Organization.OrgKind.RELIGION))
	return out


# ------------------------------------------------------- house owns an office

## org_id -> {house_id -> ticks that house has held the seat}. One sweep over the
## population; almost nobody has a role history, so the inner loop rarely runs.
static func _tenure_by_house(tick: int) -> Dictionary:
	var out := {}
	for id in GameState.people:
		var p: NotableIndividual = GameState.people[id]
		if p.role_history.is_empty() or p.house_org_id == &"":
			continue
		for t in p.role_history:
			var ended: int = t.end_tick if t.end_tick >= 0 else tick
			var held := maxi(1, ended - t.start_tick)
			var by_house: Dictionary = out.get(t.org_id, {})
			by_house[p.house_org_id] = int(by_house.get(p.house_org_id, 0)) + held
			out[t.org_id] = by_house
	return out


## A guild whose masters have come from one family for generations belongs to
## that family, whatever its charter says — and once it does, it starts to admit
## as much: its legitimacy drifts toward blood, which then makes the next
## succession favour the same house again. That loop is the point.
static func _settle_patron(org: Organization, by_house: Dictionary, tick: int) -> void:
	var total := 0
	for house_id in by_house:
		total += int(by_house[house_id])

	var patron := &""
	if total >= PATRON_MIN_TENURE_TICKS:
		for house_id in by_house:
			var house := GameState.get_organization(house_id)
			if house == null or not house.is_active():
				continue
			if float(by_house[house_id]) / float(total) >= PATRON_SHARE:
				patron = house_id
				break
	org.patron_house_id = patron

	if org.ideology == null:
		return
	if patron != &"":
		# Captured: the office grows comfortable with inheritance.
		org.ideology.nudge_axis(&"tradition_reform", -0.6, CAPTURE_DRIFT)
		org.ideology.nudge_axis(&"centralization", 0.4, CAPTURE_DRIFT * 0.5)
		if org.ideology.legitimacy_basis != PoliticalSystemAxes.LegitimacyBasis.HEREDITARY \
				and org.ideology.get_axis(&"tradition_reform") < -0.45:
			org.ideology.legitimacy_basis = PoliticalSystemAxes.LegitimacyBasis.HEREDITARY
			HistoryLog.emit_event(
				HistoryEvent.EventType.IDEOLOGY_SHIFT,
				tick,
				"%sの座は%sのものとなり、世襲で受け継がれるようになった。"
					% [org.display_name, GameState.get_organization(patron).display_name],
				{"patron_house": String(patron), "office_basis": "hereditary"},
				org.org_id,
				org.leader_person_id,
				org.origin_event_id)
	elif org.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.HEREDITARY \
			and org.kind != Organization.OrgKind.HOUSE:
		# The family that owned it is gone. An office nobody inherits stops being
		# inherited, and goes back to being argued over.
		org.ideology.nudge_axis(&"tradition_reform", 0.5, CAPTURE_DRIFT)
		if org.ideology.get_axis(&"tradition_reform") > 0.2:
			org.ideology.legitimacy_basis = _open_basis_for(org)


static func _open_basis_for(org: Organization) -> int:
	if org.ideology != null \
			and org.ideology.decision_structure == PoliticalSystemAxes.DecisionStructure.AUTOCRATIC:
		return PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC
	return PoliticalSystemAxes.LegitimacyBasis.ELECTED


## How this body fills its offices — the third link the design was missing, and
## the one that says what a house is worth inside a guild.
static func office_basis(org: Organization) -> OfficeBasis:
	if org == null or org.ideology == null:
		return OfficeBasis.CONSULTATIVE
	match org.ideology.legitimacy_basis:
		PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
			return OfficeBasis.HEREDITARY
		PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC, \
		PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			return OfficeBasis.MERITOCRATIC
	return OfficeBasis.CONSULTATIVE


static func office_basis_label(org: Organization) -> String:
	return OFFICE_BASIS_LABELS[office_basis(org)]


# ------------------------------------------------------------- support base

## Who stands behind this body. Houses back what they agree with, what they hold
## office in, and what speaks for the land they hold; factions are additionally
## backed by the guilds whose interests they carry.
static func _settle_support_base(org: Organization) -> void:
	var support: Dictionary[StringName, float] = {}

	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		var backing := _ideological_backing(org, house) * IDEOLOGY_BACKING
		if house.org_id == org.patron_house_id:
			backing += PATRON_BACKING
		var head := GameState.get_person(org.leader_person_id)
		if head != null and head.house_org_id == house.org_id:
			backing += OFFICE_BACKING
		backing += LAND_BACKING * _land_sympathy(org, house.held_settlement_ids)
		backing += FAITH_BACKING * _faith_backing(org, house)
		if backing >= SUPPORT_FLOOR:
			support[house.org_id] = clampf(backing, 0.0, 1.0)

	if org.kind == Organization.OrgKind.FACTION:
		for guild in GameState.organizations_of_kind(Organization.OrgKind.GUILD):
			var backing := _ideological_backing(org, guild) * IDEOLOGY_BACKING
			if guild.patron_house_id != &"" and guild.patron_house_id == org.patron_house_id:
				backing += PATRON_BACKING
			if backing >= SUPPORT_FLOOR:
				support[guild.org_id] = clampf(backing, 0.0, 1.0)
		# A faith stands behind a body of opinion that wants what it wants, which
		# is how a revelation becomes a policy rather than only a liturgy.
		for faith in GameState.organizations_of_kind(Organization.OrgKind.RELIGION):
			var backing := _ideological_backing(org, faith) * IDEOLOGY_BACKING
			backing *= clampf(Religion.reach_of(faith) * 2.0, 0.0, 1.0)
			if backing >= SUPPORT_FLOOR:
				support[faith.org_id] = clampf(backing, 0.0, 1.0)

	org.support_base = support


## Whether this family holds this body's faith. For a faith itself that is
## simply whether the house belongs to it; for anything else it is whose chapel
## the head of it prays in, which is how a temple reaches the guild halls.
static func _faith_backing(org: Organization, house: Organization) -> float:
	if org.kind == Organization.OrgKind.RELIGION:
		var held := Religion.faith_of_house(house)
		if held == null:
			return 0.0
		return Religion.division() if held.org_id == org.org_id else -Religion.division()
	return Religion.alignment(org, house)


## 1.0 for two bodies that believe the same thing, 0.0 once they are further
## apart than anyone bridges.
static func _ideological_backing(a: Organization, b: Organization) -> float:
	if a.ideology == null or b.ideology == null:
		return 0.0
	var distance := a.ideology.ideological_distance(b.ideology)
	return clampf(1.0 - distance / IDEOLOGY_SPAN, 0.0, 1.0)


## How much of this land is ground the body speaks for, 0..1.
static func _land_sympathy(org: Organization, settlement_ids: Array[StringName]) -> float:
	if settlement_ids.is_empty():
		return 0.0
	var matched := 0
	for id in settlement_ids:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s == null:
			continue
		if org.kind == Organization.OrgKind.FACTION:
			if Industry.sympathetic_to(s.industry, org.archetype_id):
				matched += 1
		elif Industry.favours(s.industry, org.archetype_id):
			matched += 1
	return float(matched) / float(settlement_ids.size())


## Everyone who stands behind this body, strongest first — for the dashboard.
static func backers_of(org: Organization) -> Array[Organization]:
	var out: Array[Organization] = []
	for id in org.support_base:
		var backer := GameState.get_organization(id)
		if backer != null and backer.is_active():
			out.append(backer)
	out.sort_custom(func(a, b):
		return org.support_base.get(a.org_id, 0.0) > org.support_base.get(b.org_id, 0.0))
	return out


# ------------------------------------------------------------- land leanings

## Which faction each region is with. A region leans toward whoever speaks for
## its trade, and toward whatever the family holding it and the guild working it
## already back.
static func _settle_regional_lean() -> void:
	var factions := GameState.organizations_of_kind(Organization.OrgKind.FACTION)
	for id in GameState.world.settlements:
		var s: SettlementState = GameState.world.settlements[id]
		var best := &""
		var best_score := 0.0
		for faction in factions:
			var score := 0.0
			if Industry.sympathetic_to(s.industry, faction.archetype_id):
				score += 1.0
			score += float(faction.support_base.get(s.ruling_house_id, 0.0))
			score += float(faction.support_base.get(s.dominant_guild_id, 0.0)) * 0.6
			# A faction nobody has heard of does not carry a county.
			score *= 0.4 + 0.6 * clampf(faction.power_score / 60.0, 0.0, 1.0)
			if score > best_score:
				best_score = score
				best = faction.org_id
		s.faction_lean_id = best


# ------------------------------------------------------------------- seats

## How the chamber divides. This is what a faction *is* under a regime that has
## a chamber: not a mood in the country, a count of seats — and the count is
## what the next regime change is decided on.
static func _settle_seats(polity: Organization) -> void:
	var seats := _chamber_size(polity)
	var factions := GameState.organizations_of_kind(Organization.OrgKind.FACTION)
	if seats <= 0 or factions.is_empty():
		polity.faction_seats = {}
		polity.seat_total = 0
		return

	var realm := polity.governs_settlement_ids
	var claims: Array[float] = []
	var total := 0.0
	for faction in factions:
		var claim: float = maxf(0.0, faction.power_score)
		claim *= 0.45 + 0.55 * _realm_lean_share(faction, realm)
		claims.append(claim)
		total += claim

	var allocation: Dictionary[StringName, int] = {}
	if total <= 0.0:
		polity.faction_seats = allocation
		polity.seat_total = seats
		return

	# Largest remainder, with ties broken by org id so a replay of the same world
	# divides the chamber the same way.
	var remainders: Array = []
	var given := 0
	for i in factions.size():
		var exact: float = claims[i] / total * float(seats)
		var whole := int(floorf(exact))
		if whole > 0:
			allocation[factions[i].org_id] = whole
		given += whole
		remainders.append([exact - float(whole), factions[i].org_id])
	remainders.sort_custom(func(a, b):
		return a[0] > b[0] if not is_equal_approx(a[0], b[0]) else String(a[1]) < String(b[1]))
	for i in mini(seats - given, remainders.size()):
		var id: StringName = remainders[i][1]
		allocation[id] = int(allocation.get(id, 0)) + 1

	polity.faction_seats = allocation
	polity.seat_total = seats


## An autocrat keeps a small court however large the country; an assembly seats
## the whole quarrel. The form decides, and the form is itself derived — so a
## regime that becomes a republic grows a chamber to argue in.
static func _chamber_size(polity: Organization) -> int:
	var form := PolityFormEvaluator.form_of(polity)
	if form != null:
		return form.chamber_seats
	if polity.ideology == null:
		return 9
	match polity.ideology.decision_structure:
		PoliticalSystemAxes.DecisionStructure.ASSEMBLY:
			return 21
		PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL:
			return 13
	return 7


## The share of a realm's regions leaning this faction's way, 0..1.
static func _realm_lean_share(faction: Organization, realm: Array[StringName]) -> float:
	if realm.is_empty():
		return 0.0
	var leaning := 0
	for id in realm:
		var s: SettlementState = GameState.world.settlements.get(id)
		if s != null and s.faction_lean_id == faction.org_id:
			leaning += 1
	return float(leaning) / float(realm.size())


## The factions holding the chamber, largest first.
static func seat_order(polity: Organization) -> Array[Organization]:
	var out: Array[Organization] = []
	for id in polity.faction_seats:
		var faction := GameState.get_organization(id)
		if faction != null and faction.is_active():
			out.append(faction)
	out.sort_custom(func(a, b):
		var sa: int = polity.faction_seats.get(a.org_id, 0)
		var sb: int = polity.faction_seats.get(b.org_id, 0)
		return sa > sb if sa != sb else String(a.org_id) < String(b.org_id))
	return out


## The faction holding the most seats, and whether it holds them outright.
static func largest_bloc(polity: Organization) -> Organization:
	var order := seat_order(polity)
	return order[0] if not order.is_empty() else null


static func has_majority(polity: Organization, faction: Organization) -> bool:
	if faction == null or polity.seat_total <= 0:
		return false
	return int(polity.faction_seats.get(faction.org_id, 0)) * 2 > polity.seat_total
