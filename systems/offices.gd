class_name Offices
extends RefCounted

## 要職 — the seats beside the head of a state, and what holding them makes a
## family.
##
## A great house used to be great because a number said so: some land, some
## power, some years, a favour from the crown. Nobody could say *why* this house
## was a marquess and that one a count. Real great families are great for
## reasons anyone can list: they gave the realm three regents, they are first in
## line if the royal house fails, their head won a war as commander-in-general,
## the treasury has been theirs for a century. This is where those reasons come
## from.
##
## Which seats a state keeps depends on what it is. A crown that runs on blood
## has a regent when its king is a child or its queen's family is too strong to
## ignore, and names the houses next in line (跡目家). A republic or a council has
## aides chosen by who holds the chamber. Every state has a treasurer — the first
## office of a plutocracy — and a marshal; a war gives each side a commander and
## a strategist; a theocracy keeps a priest at the ruler's ear. How they are
## filled depends on it too: an autocrat appoints by favour and birth, a council
## by its blocs, a plutocracy by money, a theocracy by faith. Each seat has a
## floor of rank below which no family may hold it, so a high seat makes a high
## house and a high house reaches high seats: that is how a name stays a name.
## The predecessor's family is favoured, and three holders in a row from one
## family make the seat theirs by right (家職).
##
## Appointments, departures, a seat becoming hereditary, the order of the heir
## houses and the chief house of each 氏 are all OFFICE events; GameState folds
## them in. The god appoints no one.

const LABELS := {
	"regent": "摂政",
	"treasurer": "財務官",
	"marshal": "元帥",
	"aide_1": "執政補佐",
	"aide_2": "執政補佐",
	"high_priest": "聖職顧問",
	"general": "総大将",
	"strategist": "参謀",
}
const AUTOCRATIC_AIDE := "側近"
const WAR_SEATS := ["general", "strategist"]

## What each seat is worth, as a ground of rank (see HouseRank.grounds_of).
const WEIGHT := {
	"regent": 0.9,
	"treasurer": 0.5,
	"marshal": 0.5,
	"aide_1": 0.45,
	"aide_2": 0.4,
	"high_priest": 0.45,
	"general": 0.55,
	"strategist": 0.35,
}

## The lowest standing (HouseRank.precedence) a family needs to hold each seat:
## a regent comes from a count's house or above, a treasurer or a commander
## from the nobility, a marshal from a knight's household up, a strategist or an
## aide from anyone.
const BASE := HouseRank.NOBLE_PRECEDENCE_BASE
const MIN_RANK := {
	"regent": BASE + 2.0,
	"treasurer": BASE,
	"marshal": 1.0,
	"aide_1": 0.0,
	"aide_2": 0.0,
	"high_priest": 0.0,
	"general": BASE,
	"strategist": 0.0,
}

## How long somebody holds a seat before a far better candidate may displace
## them, and how much better that candidate must be.
const RESHUFFLE_YEARS := 15
const RESHUFFLE_MARGIN := 1.6
## A regent is wanted for a child, or an old ruler, or one whose wife's or
## mother's family is too strong to leave outside the council.
const OLD_RULER := 72
const IN_LAW_RANK := BASE + 3.0
const IN_LAW_POWER := 0.9
## The houses named next in line to a crown, at most.
const HEIRS := 3
const HEIR_FLOOR := 1.0


static func label_of(key: String, polity: Organization = null) -> String:
	if key.begins_with("aide") and polity != null and polity.ideology != null \
			and polity.ideology.decision_structure == PoliticalSystemAxes.DecisionStructure.AUTOCRATIC:
		return AUTOCRATIC_AIDE
	return LABELS.get(key, key)


static func weight_of(key: String, polity: Organization) -> float:
	var w: float = WEIGHT.get(key, 0.3)
	if polity != null and polity.ideology != null:
		var basis := polity.ideology.legitimacy_basis
		if key == "treasurer" and basis == PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
			w = 0.85
		if key == "marshal" and basis == PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
			w = 0.75
	return w


static func min_rank_of(key: String, polity: Organization) -> float:
	var floor_rank: float = MIN_RANK.get(key, 0.0)
	# A plutocracy takes its treasurer from wherever the money is.
	if key == "treasurer" and polity != null and polity.ideology != null \
			and polity.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
		floor_rank = 0.5
	return floor_rank


## The seats a state keeps, by what it is (the war seats come and go with wars).
static func seats_for(polity: Organization) -> Array[String]:
	var out: Array[String] = []
	if polity == null or polity.ideology == null:
		return out
	var basis := polity.ideology.legitimacy_basis
	var structure := polity.ideology.decision_structure
	if basis == PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
		out.append("regent")
	else:
		out.append("aide_1")
		if structure != PoliticalSystemAxes.DecisionStructure.AUTOCRATIC:
			out.append("aide_2")
	out.append("treasurer")
	out.append("marshal")
	if basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC:
		out.append("high_priest")
	return out


# ==================================================================== readers

## Every seat a family's people hold now: [{polity, key, person}].
static func held_by(house_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		for key in polity.offices:
			var entry: Dictionary = polity.offices[key]
			if StringName(entry.get("house", "")) == house_id:
				out.append({"polity": polity, "key": String(key),
					"person": GameState.get_person(StringName(entry.get("person", "")))})
	return out


## Whether somebody holds any great office anywhere.
static func holds_office(person: NotableIndividual) -> bool:
	if person == null:
		return false
	for record in person.office_history:
		if int(record.get("end", -1)) < 0:
			return true
	return false


## The house actually governing a crown while a regent holds the realm by
## right (摂関政治), or empty.
static func regent_house(polity: Organization) -> StringName:
	if polity == null:
		return &""
	return StringName(polity.offices.get("regent", {}).get("house", ""))


static func is_regency_by_right(polity: Organization) -> bool:
	return polity != null and polity.hereditary_offices.has("regent")


## A ruler's in-laws: the house their mother or a living spouse was born to.
static func in_law_houses(ruler: NotableIndividual) -> Array[StringName]:
	var out: Array[StringName] = []
	if ruler == null:
		return out
	var mother := GameState.get_person(ruler.mother_id)
	if mother != null and mother.birth_house_org_id != &"" \
			and mother.birth_house_org_id != ruler.house_org_id:
		out.append(mother.birth_house_org_id)
	for spouse_id in ruler.spouse_ids:
		var spouse := GameState.get_person(spouse_id)
		if spouse == null or not spouse.is_alive():
			continue
		var born := spouse.birth_house_org_id if spouse.birth_house_org_id != &"" else spouse.house_org_id
		if born != &"" and born != ruler.house_org_id and not out.has(born):
			out.append(born)
	return out


# ======================================================================= step

static func step(tick: int) -> void:
	if tick % SimConfig.TICKS_PER_YEAR != 2:
		return
	_refresh_uji_chiefs(tick)
	var realm_of := _realms()
	for polity in GameState.organizations_of_kind(Organization.OrgKind.POLITICAL_SYSTEM):
		_refresh(polity, realm_of, tick)


## house id -> the state its cause lies with, for every family at once.
static func _realms() -> Dictionary:
	var out := {}
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		out[house.org_id] = CivilWar.realm_of_house(house)
	return out


static func _refresh(polity: Organization, realm_of: Dictionary, tick: int) -> void:
	if polity.ideology == null:
		return
	var seats := seats_for(polity)
	# A seat the state no longer keeps is abolished; who held it stays recorded.
	for key in polity.offices.keys():
		if not seats.has(String(key)) and not WAR_SEATS.has(String(key)):
			_vacate(polity, String(key), "abolished", tick)
	for key in polity.hereditary_offices.keys():
		if not seats.has(String(key)):
			_emit(polity, "hereditary", String(key), &"", tick,
				{"house": ""}, "%sの%sは廃され、家職も失われた。" % [polity.formal_name(),
					label_of(String(key), polity)])

	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing != Organization.Standing.COMMONER \
				and StringName(realm_of.get(house.org_id, &"")) == polity.org_id:
			houses.append(house)
	houses.sort_custom(func(x: Organization, y: Organization): return String(x.org_id) < String(y.org_id))
	var ruler := GameState.get_current_leader(polity.org_id)
	var ruler_house := GameState.get_organization(ruler.house_org_id) if ruler != null else null

	var regency := _regency_wanted(polity, ruler, ruler_house)
	for key in seats:
		if key == "regent" and not bool(regency.get("wanted", false)):
			if polity.offices.has("regent"):
				_vacate(polity, "regent", "ended", tick)
			continue
		var entry: Dictionary = polity.offices.get(key, {})
		var holder := GameState.get_person(StringName(entry.get("person", "")))
		var holder_house := GameState.get_organization(StringName(entry.get("house", "")))
		var best := _best(polity, key, houses, ruler, ruler_house, regency)
		if holder != null and holder.is_alive():
			var fit := holder_house != null and holder_house.is_active() \
				and StringName(realm_of.get(holder_house.org_id, &"")) == polity.org_id \
				and HouseRank.precedence(holder_house) >= min_rank_of(key, polity)
			if fit:
				var years := int((tick - int(entry.get("since", tick))) / SimConfig.TICKS_PER_YEAR)
				var mine := _score(polity, key, holder_house, ruler, ruler_house, regency)
				if best.is_empty() or years < RESHUFFLE_YEARS \
						or float(best["score"]) <= mine * RESHUFFLE_MARGIN + 0.2 \
						or best["house"] == holder_house:
					continue
				_vacate(polity, key, "replaced", tick,
					{"successor_house": String(best["house"].org_id)})
			else:
				_vacate(polity, key, "unfit", tick)
		if not best.is_empty():
			_appoint(polity, key, best["person"], best["house"], tick)

	# A commander who falls in a war is replaced while it lasts.
	var war := CivilWar.war_of(polity.org_id)
	if war != null:
		for key in WAR_SEATS:
			if not polity.offices.has(key):
				var best := _best(polity, key, houses, ruler, ruler_house, {})
				if not best.is_empty():
					_appoint(polity, key, best["person"], best["house"], tick,
						{"war_id": String(war.war_id)})

	if polity.ideology.legitimacy_basis == PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
		_refresh_heirs(polity, houses, ruler, ruler_house, tick)
	elif not polity.heir_houses.is_empty():
		_emit(polity, "heirs", "", &"", tick, {"houses": []},
			"%sは血統によらぬ国となり、跡目家の定めも絶えた。" % polity.formal_name())


static func _regency_wanted(polity: Organization, ruler: NotableIndividual,
		ruler_house: Organization) -> Dictionary:
	if polity.ideology.legitimacy_basis != PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
		return {}
	if ruler == null:
		return {}
	if is_regency_by_right(polity):
		return {"wanted": true, "why": "家職",
			"house": StringName(polity.hereditary_offices["regent"])}
	var tick := SimClock.current_tick
	var why := ""
	if not ruler.is_adult(tick):
		why = "幼君"
	elif ruler.age_years(tick) >= OLD_RULER:
		why = "老君"
	var strong_in_law := &""
	for id in in_law_houses(ruler):
		var house := GameState.get_organization(id)
		if house == null or not house.is_active() or not house.is_noble():
			continue
		if HouseRank.precedence(house) < IN_LAW_RANK:
			continue
		if ruler_house != null and house.power_score < ruler_house.power_score * IN_LAW_POWER:
			continue
		strong_in_law = id
		break
	if why == "" and strong_in_law != &"":
		why = "外戚"
	if why == "":
		return {}
	return {"wanted": true, "why": why, "house": strong_in_law}


## The best family for a seat and the person it would send.
static func _best(polity: Organization, key: String, houses: Array[Organization],
		ruler: NotableIndividual, ruler_house: Organization, regency: Dictionary) -> Dictionary:
	var best := {}
	var best_score := -INF
	for house in houses:
		var score := _score(polity, key, house, ruler, ruler_house, regency)
		if score == -INF or score <= best_score:
			continue
		var person := _sent_by(house, polity)
		if person == null:
			continue
		best_score = score
		best = {"house": house, "person": person, "score": score}
	return best


## What a family is worth for a seat, under the kind of state this is.
static func _score(polity: Organization, key: String, house: Organization,
		ruler: NotableIndividual, ruler_house: Organization, regency: Dictionary) -> float:
	if house == null or not house.is_active():
		return -INF
	var rank := HouseRank.precedence(house)
	if rank < min_rank_of(key, polity):
		return -INF
	var axes := polity.ideology
	var structure := axes.decision_structure
	var basis := axes.legitimacy_basis
	var favour_w := 0.8 if structure == PoliticalSystemAxes.DecisionStructure.AUTOCRATIC \
		else (0.45 if structure == PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL else 0.2)
	var seats_w := 1.2 - favour_w
	var rank_w := 1.0 if structure == PoliticalSystemAxes.DecisionStructure.AUTOCRATIC \
		else (0.75 if structure == PoliticalSystemAxes.DecisionStructure.OLIGARCHIC_COUNCIL else 0.5)

	var score := rank / 8.0 * rank_w
	if ruler_house != null:
		score += favour_w * HouseRelations.relation(ruler_house.org_id, house.org_id)
		if house.uji_id != &"" and house.uji_id == ruler_house.uji_id:
			score += 0.2 * favour_w
		if house.org_id == ruler_house.org_id and key != "regent":
			score -= 0.6
	score += seats_w * _chamber_weight(polity, house)
	var wealth := _wealth_of(house)
	var martial := _martial_of(house)
	var faithful := 1.0 if ruler_house != null and house.faith_id != &"" \
		and house.faith_id == ruler_house.faith_id else 0.0
	match key:
		"treasurer":
			score += wealth * 1.2
		"marshal", "general":
			score += martial
		"high_priest":
			score += faithful + (0.3 if _head_has(house, &"pious") else 0.0)
		"strategist":
			score += (0.6 if _head_has(house, &"scholarly") else 0.0) + martial * 0.5
		"regent":
			if StringName(regency.get("house", &"")) == house.org_id:
				score += 1.5
			if ruler != null and in_law_houses(ruler).has(house.org_id):
				score += 0.6
		_:
			score += (0.3 if _head_has(house, &"just") or _head_has(house, &"scholarly") else 0.0)
	if basis == PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
		score += wealth * 0.6
	elif basis == PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC:
		score += faithful * 0.5
	elif basis == PoliticalSystemAxes.LegitimacyBasis.MILITARY_STRENGTH:
		score += martial * 0.4
	# Whoever held it last is likelier to be followed by their own; a seat that
	# has become a family's by right goes to that family.
	var line: Array = polity.office_lines.get(key, [])
	if not line.is_empty() and StringName(line.back()) == house.org_id:
		score += 0.35
	if StringName(polity.hereditary_offices.get(key, "")) == house.org_id:
		score += 2.0
	# A family just put down at court is not soon given a seat there again.
	score -= 2.0 * Intrigue.disgrace(house)
	# A family already sitting beside the head is less likely to be given a
	# second seat — the others would not stand for it.
	for other in polity.offices:
		if String(other) != key and StringName(polity.offices[other].get("house", "")) == house.org_id:
			score -= 0.6
	return score


## How much of the chamber stands behind a family: its share of the seats of
## every faction it backs, or that it owns.
static func _chamber_weight(polity: Organization, house: Organization) -> float:
	if polity.seat_total <= 0:
		return 0.0
	var total := 0.0
	for faction_id in polity.faction_seats:
		var faction := GameState.get_organization(faction_id)
		if faction == null:
			continue
		var share := float(polity.faction_seats[faction_id]) / float(polity.seat_total)
		var backing := float(faction.support_base.get(house.org_id, 0.0))
		if faction.patron_house_id == house.org_id:
			backing = 1.0
		total += share * backing
	return clampf(total * 2.0, 0.0, 1.0)


static func _wealth_of(house: Organization) -> float:
	var gold := float(house.resources.get(&"gold", 0.0))
	for guild in GameState.organizations_of_kind(Organization.OrgKind.GUILD):
		if guild.patron_house_id == house.org_id:
			gold += float(guild.resources.get(&"gold", 0.0))
	return clampf(gold / 1200.0, 0.0, 1.0)


static func _martial_of(house: Organization) -> float:
	var m := 0.0
	if house.character_id == HouseCharacter.MARTIAL:
		m += 0.6
	if _head_has(house, &"martial"):
		m += 0.4
	return m


static func _head_has(house: Organization, tag: StringName) -> bool:
	var head := GameState.get_current_leader(house.org_id)
	return head != null and head.has_tag(tag)


## Who a family would send: its head, or else one of its own grown blood with no
## seat already.
static func _sent_by(house: Organization, polity: Organization) -> NotableIndividual:
	var tick := SimClock.current_tick
	var head := GameState.get_current_leader(house.org_id)
	if head != null and head.is_alive() and head.is_adult(tick) and not holds_office(head) \
			and not _leads_a_state(head):
		return head
	var members := GameState.house_members(house.org_id)
	members.sort_custom(func(x: NotableIndividual, y: NotableIndividual):
		return x.birth_tick < y.birth_tick if x.birth_tick != y.birth_tick \
			else String(x.person_id) < String(y.person_id))
	for member in members:
		if not member.is_adult(tick) or member.age_years(tick) > 70:
			continue
		if not HouseNaming.is_of_the_blood(member, house) or holds_office(member):
			continue
		if member.current_tenure() != null or member.is_disinherited():
			continue
		return member
	return null


static func _leads_a_state(person: NotableIndividual) -> bool:
	for t in person.role_history:
		if t.is_current():
			var org := GameState.get_organization(t.org_id)
			if org != null and org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
				return true
	return false


# ===================================================================== events

static func _appoint(polity: Organization, key: String, person: NotableIndividual,
		house: Organization, tick: int, extra: Dictionary = {}) -> void:
	var label := label_of(key, polity)
	var payload := {"house": String(house.org_id)}
	payload.merge(extra)
	var line: Array = polity.office_lines.get(key, [])
	var text := "%sは%sを%sに任じた。" % [polity.formal_name(), person.full_name, label]
	if StringName(polity.hereditary_offices.get(key, "")) == house.org_id:
		text = "%sの%sは家職により%sが継いだ。" % [polity.formal_name(), label, person.full_name]
	elif key == "regent":
		text = "%sに%sが立った。%sが国の政を執る。" % [polity.formal_name(), label, person.full_name]
	_emit(polity, "appoint", key, person.person_id, tick, payload, text, house.org_id)
	# Three of one family in a row and the seat is theirs by right.
	line = polity.office_lines.get(key, [])
	if line.size() >= 3 and not polity.hereditary_offices.has(key) and not WAR_SEATS.has(key):
		var same := true
		for id in line.slice(line.size() - 3):
			if StringName(id) != house.org_id:
				same = false
		if same:
			var what := "摂関の家となった。国の政はこの家が執る" if key == "regent" \
				else "家職となった"
			_emit(polity, "hereditary", key, &"", tick, {"house": String(house.org_id)},
				"%sの%sは三代続いて%sから出、%s。" % [polity.formal_name(), label,
					house.formal_name(), what], house.org_id)
	elif polity.hereditary_offices.has(key) \
			and StringName(polity.hereditary_offices[key]) != house.org_id:
		var lost := GameState.get_organization(StringName(polity.hereditary_offices[key]))
		_emit(polity, "hereditary", key, &"", tick, {"house": ""},
			"%sの%sは%sの手を離れ、家職ではなくなった。" % [polity.formal_name(), label,
				lost.formal_name() if lost != null else "旧家"], lost.org_id if lost != null else &"")


static func _vacate(polity: Organization, key: String, reason: String, tick: int,
		extra: Dictionary = {}) -> void:
	var entry: Dictionary = polity.offices.get(key, {})
	if entry.is_empty():
		return
	var holder := GameState.get_person(StringName(entry.get("person", "")))
	var label := label_of(key, polity)
	var name := holder.full_name if holder != null else "前任"
	var text: String = {
		"abolished": "%sの%sは廃され、%sはその座を去った。" % [polity.formal_name(), label, name],
		"ended": "%sは%sを退き、国の長が自ら政を執ることとなった。" % [name, label],
		"replaced": "%sは%sを解かれた。" % [name, label],
		"unfit": "%sは%sの座にとどまれず、これを去った。" % [name, label],
		"intrigue": "%sは政争に敗れ、%sを解かれた。" % [name, label],
	}.get(reason, "%sは%sを去った。" % [name, label])
	var payload := {"reason": reason, "house": String(entry.get("house", ""))}
	payload.merge(extra)
	_emit(polity, "vacate", key, StringName(entry.get("person", "")), tick, payload, text,
		StringName(entry.get("house", "")))


static func _emit(polity: Organization, action: String, key: String, person_id: StringName,
		tick: int, extra: Dictionary, text: String, subject: StringName = &"") -> HistoryEvent:
	var payload := {"action": action, "office": key, "polity": String(polity.org_id) if polity != null else ""}
	payload.merge(extra)
	return HistoryLog.emit_event(
		HistoryEvent.EventType.OFFICE,
		tick,
		text,
		payload,
		subject if subject != &"" else (polity.org_id if polity != null else &""),
		person_id,
		polity.origin_event_id if polity != null else &"")


# ================================================================ heir houses

## The houses named to take the crown if the royal line fails: the royal
## house's own cadet lines (same 氏) first, nearest first, then its in-laws.
static func _refresh_heirs(polity: Organization, houses: Array[Organization],
		ruler: NotableIndividual, ruler_house: Organization, tick: int) -> void:
	if ruler_house == null:
		return
	var in_laws := in_law_houses(ruler)
	var ranked: Array = []
	for house in houses:
		if house.org_id == ruler_house.org_id or not house.is_noble():
			continue
		var score := HouseRank.precedence(house) / 8.0
		if house.uji_id != &"" and house.uji_id == ruler_house.uji_id:
			score += 2.0 - 0.25 * float(_distance(house, ruler_house))
		if in_laws.has(house.org_id):
			score += 1.2
		score += 0.4 * HouseRelations.relation(ruler_house.org_id, house.org_id)
		# Nor named next in line, once it has been struck out of the order.
		score -= 1.5 * Intrigue.disgrace(house)
		if score >= HEIR_FLOOR:
			ranked.append([score, house])
	ranked.sort_custom(func(x, y):
		return x[0] > y[0] if not is_equal_approx(x[0], y[0]) else String(x[1].org_id) < String(y[1].org_id))
	var named: Array[StringName] = []
	for entry in ranked.slice(0, HEIRS):
		named.append(entry[1].org_id)
	if named == polity.heir_houses:
		return
	# Who went down the order, or out of it: a family does not forget that.
	var lowered: Array = []
	for i in polity.heir_houses.size():
		var id: StringName = polity.heir_houses[i]
		var now := named.find(id)
		if now < 0 or now > i:
			lowered.append(String(id))
	var names: Array[String] = []
	for id in named:
		names.append(GameState.get_organization(id).formal_name())
	var text := "%sは跡目家を%sと定めた。" % [polity.formal_name(),
		"・".join(names) if not names.is_empty() else "置かぬこと"]
	if not polity.heir_houses.is_empty() and not lowered.is_empty():
		text = "%sは跡目家の順位を改め、%sとした。" % [polity.formal_name(),
			"・".join(names) if not names.is_empty() else "定めなし"]
	_emit(polity, "heirs", "", &"", tick,
		{"houses": Organization._names_to_strings(named), "lowered": lowered,
			"reordered": not polity.heir_houses.is_empty()}, text,
		named[0] if not named.is_empty() else polity.org_id)


## How many branchings separate two houses of one 氏.
static func _distance(a: Organization, b: Organization) -> int:
	var ancestors := {}
	var walk := a
	var steps := 0
	while walk != null and steps < 32:
		ancestors[walk.org_id] = steps
		walk = GameState.get_organization(walk.parent_org_id)
		steps += 1
	walk = b
	steps = 0
	while walk != null and steps < 32:
		if ancestors.has(walk.org_id):
			return int(ancestors[walk.org_id]) + steps
		walk = GameState.get_organization(walk.parent_org_id)
		steps += 1
	return 8


## The next in line, for a crown whose own house has failed: the head of the
## first heir house that has one. Read by SuccessionResolver.
static func heir_claimant(polity: Organization, tick: int) -> NotableIndividual:
	for id in polity.heir_houses:
		var house := GameState.get_organization(id)
		if house == null or not house.is_active():
			continue
		var head := GameState.get_current_leader(id)
		if head != null and head.is_alive() and head.is_adult(tick):
			return head
	return null


# ================================================================ 氏の長者

## The chief house of each 氏: the house that founded it while it lives, then
## the living house of that 氏 nearest the founding line.
static func _refresh_uji_chiefs(tick: int) -> void:
	for uji_id in HouseNaming.all_uji():
		var founder := GameState.get_organization(uji_id)
		var chief: Organization = founder if founder != null and founder.is_active() else null
		if chief == null:
			var best_steps := 999
			for house in HouseNaming.houses_of_uji(uji_id, true):
				var steps := _distance(house, founder)
				if chief == null or steps < best_steps:
					chief = house
					best_steps = steps
		var chief_id: StringName = chief.org_id if chief != null else &""
		if founder == null or founder.uji_chief_id == chief_id:
			continue
		var text := "%sの長者は%sに移った。" % [HouseNaming.uji_label(uji_id),
			chief.formal_name()] if chief != null \
			else "%sの家はすべて絶え、長者もいなくなった。" % HouseNaming.uji_label(uji_id)
		if founder.uji_chief_id == &"" and chief == founder:
			# The founding of the record, not news: the founder is chief from the
			# first day.
			text = "%sが%sの長者である。" % [founder.formal_name(), HouseNaming.uji_label(uji_id)]
		HistoryLog.emit_event(
			HistoryEvent.EventType.OFFICE,
			tick,
			text,
			{"action": "uji_chief", "uji": String(uji_id), "house": String(chief_id),
				"polity": ""},
			chief_id if chief_id != &"" else uji_id,
			&"",
			founder.origin_event_id)


static func is_uji_chief(house: Organization) -> bool:
	if house == null or house.uji_id == &"":
		return false
	var founder := GameState.get_organization(house.uji_id)
	return founder != null and founder.uji_chief_id == house.org_id


# ======================================================================= war

## A war gives each side a commander and a strategist: a commander from the
## nobility by arms, birth and the ruler's trust; a strategist from any family,
## by learning and arms.
static func appoint_war_command(war: WarState, tick: int) -> void:
	var realm_of := _realms()
	for polity_id in [war.side_a, war.side_b]:
		var polity := GameState.get_organization(polity_id)
		if polity == null or polity.ideology == null:
			continue
		var houses: Array[Organization] = []
		for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
			if house.standing != Organization.Standing.COMMONER \
					and StringName(realm_of.get(house.org_id, &"")) == polity.org_id:
				houses.append(house)
		houses.sort_custom(func(x: Organization, y: Organization): return String(x.org_id) < String(y.org_id))
		var ruler := GameState.get_current_leader(polity.org_id)
		var ruler_house := GameState.get_organization(ruler.house_org_id) if ruler != null else null
		for key in WAR_SEATS:
			var best := _best(polity, key, houses, ruler, ruler_house, {})
			if not best.is_empty():
				_appoint(polity, key, best["person"], best["house"], tick,
					{"war_id": String(war.war_id)})


## What the commanders won or lost, written to their families; then they stand
## down. Called by CivilWar as a war ends, before a losing state is dissolved.
static func settle_war_command(war: WarState, winner_side: String, tick: int) -> Array[String]:
	var lines: Array[String] = []
	for side in ["a", "b"]:
		var polity := GameState.get_organization(war.side_a if side == "a" else war.side_b)
		if polity == null:
			continue
		for key in WAR_SEATS:
			var entry: Dictionary = polity.offices.get(key, {})
			if entry.is_empty():
				continue
			var house := GameState.get_organization(StringName(entry.get("house", "")))
			var person := GameState.get_person(StringName(entry.get("person", "")))
			var result := "draw" if winner_side == "" else ("victory" if winner_side == side else "defeat")
			if house != null:
				_emit(polity, "merit", key, person.person_id if person != null else &"", tick,
					{"war_id": String(war.war_id), "result": result, "house": String(house.org_id)},
					"%s%sの%sとして、%s。" % [person.full_name if person != null else "",
						"" if person != null else house.formal_name(), label_of(key, polity),
						{"victory": "戦を勝ちに導いた", "defeat": "敗軍の将となった",
							"draw": "引き分けの戦を戦い抜いた"}[result]], house.org_id)
				if result == "defeat" and key == "general":
					_emit(polity, "blemish", key, person.person_id if person != null else &"", tick,
						{"kind": "defeat", "weight": 0.25, "war_id": String(war.war_id)},
						"%sは敗戦の責を負った。" % house.formal_name(), house.org_id)
				if result == "victory" and person != null:
					lines.append("%sの%s%s" % [label_of(key, polity), person.full_name,
						"は戦功を挙げた"])
			_vacate(polity, key, "war_end", tick)
	return lines


## A war's commander, for the strength of the side: what they bring to it.
static func command_bonus(polity: Organization) -> float:
	var bonus := 0.0
	for key in WAR_SEATS:
		var house := GameState.get_organization(StringName(polity.offices.get(key, {}).get("house", "")))
		if house == null:
			continue
		bonus += _martial_of(house) * (0.4 if key == "general" else 0.2)
		if key == "strategist" and _head_has(house, &"scholarly"):
			bonus += 0.25
	return bonus
