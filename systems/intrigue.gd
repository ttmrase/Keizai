class_name Intrigue
extends RefCounted

## 政争 — a quarrel fought with favour instead of arms.
##
## Far commoner than a war and far smaller: one great family at court moves
## against another, works on it for a season or a few years, and either brings
## it down — out of its office, down in the order of heirs, its standing cut —
## or is found out and brought down itself, or neither, and both are worse
## enemies than before.
##
## What starts one is mostly a grudge (see Grudges), and most grudges are the
## loser's side of a disputed succession; so the quarrels of one generation are
## very often the successions of the one before. A grudge alone is not enough —
## there has to be an opening: a weak crown, a new one, an office worth taking, a
## head ambitious enough to try. Rarely a family with no grudge at all tries its
## luck against one that has the seat it wants.
##
## How it ends is worked out from many things at once, each kept as its own line
## so the reader can be shown why: standing, offices, how close each family is
## to the head of state, who would stand with it, the chamber, faith, money, the
## character of the people doing it, how their earlier quarrels went, the kind
## of state it is — and luck.
##
## The god has no hand in it. A failing harvest that has the crown's legitimacy
## sliding opens the court to quarrels; that is as close as the god comes.

## One look a year for new quarrels; the ones under way move every season.
const CONSIDER_SEASON := 3
## The least grudge that moves a family to act on it.
const MOTIVE := 0.2
## Yearly chance, at a full grudge and an ordinary opening, that a family moves.
const GRUDGE_CHANCE := 0.024
## And for a family with no grudge, only ambition and somebody in its way.
const AMBITION_CHANCE := 0.0004
## Years a family is left alone after a quarrel, either side of it.
const COOLDOWN_YEARS := 12
## Quarrels the whole world has going at once; one per court.
const MOST_AT_ONCE := 4

## Seasons from the first move to the real work, and from that to the end.
const PLOT_SEASONS := Vector2i(1, 3)
const SCHEME_SEASONS := Vector2i(2, 9)

## Where the margin has to fall for the instigator to win, or to be found out.
const WIN_MARGIN := 0.2
const BACKFIRE_MARGIN := -0.35
## And past which the loser's fall is a heavy one.
const HEAVY_MARGIN := 1.25
## Defending is easier than attacking.
const DEFENDER_EDGE := 0.15
const LUCK := 0.6
## How long a family put down at court stays out of favour there (decay, years).
const DISGRACE_YEARS := 30.0
const BLEMISH_WEIGHT := 0.3
const HEAVY_BLEMISH_WEIGHT := 0.5

const FACTOR_KEYS: Array[String] = ["rank", "office", "favour", "allies", "seats", "faith",
	"wealth", "character", "reputation", "edge", "luck"]
const FACTOR_LABELS := {
	"rank": "家格と席次",
	"office": "現任の役職",
	"favour": "長との近さ",
	"allies": "味方の数",
	"seats": "派閥の議席",
	"faith": "信仰の一致",
	"wealth": "富",
	"character": "当人の気質",
	"reputation": "政争の評判",
	"edge": "守る側の利",
	"luck": "運",
}
const OUTCOME_LABELS := {
	"won": "仕掛けた側の勝ち",
	"backfired": "露見し返り討ち",
	"stalemate": "痛み分け",
	"faded": "立ち消え",
}
const FALL_LABELS := {
	"displaced": "左遷",
	"demoted": "降格",
	"retired": "隠居",
	"exiled": "追放",
	"jailed": "投獄",
}


static func settled(d: Dictionary) -> Dictionary:
	var s := d.duplicate(true)
	for field in ["stage", "start", "scheme_tick", "resolve_tick", "motive", "motive_since",
			"motive_generations", "motive_root_since"]:
		s[field] = int(s.get(field, 0))
	for field in ["id", "polity", "instigator", "target", "instigator_person", "target_person",
			"prize", "motive_cause", "motive_kind", "motive_why", "motive_root_kind"]:
		s[field] = String(s.get(field, ""))
	s["motive_strength"] = float(s.get("motive_strength", 0.0))
	return s


# ===================================================================== reading

static func active() -> Array:
	return GameState.world.intrigues


static func involving(house_id: StringName) -> Dictionary:
	for state in GameState.world.intrigues:
		if StringName(state["instigator"]) == house_id or StringName(state["target"]) == house_id:
			return state
	return {}


static func fall_label(kind: String) -> String:
	return FALL_LABELS.get(kind, kind)


static func outcome_label(outcome: String) -> String:
	return OUTCOME_LABELS.get(outcome, outcome)


## "612年の家督争いの遺恨から" — what moved the instigator, in a phrase. A
## quarrel answering an older one names where the chain began.
static func motive_phrase(state: Dictionary) -> String:
	if String(state.get("motive_kind", "")) == "":
		return "出世を狙って"
	var direct := "%d年の%s" % [int(int(state.get("motive_since", 0)) / SimConfig.TICKS_PER_YEAR),
		Grudges.kind_label(String(state["motive_kind"]))]
	var root := Grudges.root_label(String(state.get("motive_root_kind", "")),
		int(state.get("motive_root_since", 0)))
	if root != "" and root != direct:
		return "%sに始まる遺恨から" % root
	return "%sの遺恨から" % direct


## What is being fought over, in words.
static func prize_label(state: Dictionary) -> String:
	var prize := String(state.get("prize", ""))
	var polity := GameState.get_organization(StringName(state.get("polity", "")))
	if prize.begins_with("office:"):
		return Offices.label_of(prize.substr(7), polity) + "の座"
	if prize == "heir":
		return "跡目の順位"
	if prize.begins_with("hereditary:"):
		return Offices.label_of(prize.substr(11), polity) + "の家職"
	return "家格"


## How far a family is still out of favour at court after being put down there.
static func disgrace(house: Organization, tick: int = -1) -> float:
	if house == null:
		return 0.0
	if tick < 0:
		tick = SimClock.current_tick
	var total := 0.0
	for mark in house.blemishes:
		if String(mark.get("kind", "")) != "intrigue":
			continue
		var years := float(tick - int(mark.get("tick", tick))) / SimConfig.TICKS_PER_YEAR
		total += float(mark.get("weight", BLEMISH_WEIGHT)) * exp(-years / DISGRACE_YEARS)
	return total


## Who would win if it were settled today, without luck: the breakdown shown
## while a quarrel is under way. Positive favours the instigator.
static func outlook(state: Dictionary) -> Dictionary:
	var polity := GameState.get_organization(StringName(state.get("polity", "")))
	var a := GameState.get_organization(StringName(state.get("instigator", "")))
	var b := GameState.get_organization(StringName(state.get("target", "")))
	if polity == null or a == null or b == null:
		return {}
	var factors := _factors(polity, a, b,
		GameState.get_person(StringName(state.get("instigator_person", ""))),
		GameState.get_person(StringName(state.get("target_person", ""))))
	factors.erase("luck")
	return factors


# ======================================================================= step

static func step(tick: int) -> void:
	_advance(tick)
	if tick % SimConfig.TICKS_PER_YEAR == CONSIDER_SEASON:
		_consider(tick)


## Moves every quarrel under way on by a season.
static func _advance(tick: int) -> void:
	for state in GameState.world.intrigues.duplicate():
		var polity := GameState.get_organization(StringName(state["polity"]))
		var a := GameState.get_organization(StringName(state["instigator"]))
		var b := GameState.get_organization(StringName(state["target"]))
		if polity == null or not polity.is_active() or a == null or not a.is_active() \
				or b == null or not b.is_active() or CivilWar.realm_of_house(a) != polity.org_id \
				or CivilWar.realm_of_house(b) != polity.org_id:
			_fade(state, tick, "宮廷の様が変わり、")
			continue
		var actor := _actor(state, "instigator")
		if actor == null:
			_fade(state, tick, "仕掛けた当人が世を去り、")
			continue
		if int(state["stage"]) == 1 and tick >= int(state["scheme_tick"]):
			_scheme(state, polity, a, b, tick)
		elif int(state["stage"]) >= 2 and tick >= int(state["resolve_tick"]):
			_resolve(state, polity, a, b, tick)


## The person acting for one side: whoever began it, or if they are gone, the
## head of the family now. A target who dies is replaced by their house.
static func _actor(state: Dictionary, side: String) -> NotableIndividual:
	var person := GameState.get_person(StringName(state[side + "_person"]))
	if person != null and person.is_alive():
		return person
	if side == "instigator":
		return null
	return GameState.get_current_leader(StringName(state[side]))


## Looks, once a year, for a family that has a reason and an opening.
static func _consider(tick: int) -> void:
	if GameState.world.intrigues.size() >= MOST_AT_ONCE:
		return
	var rng := RngService.stream(&"intrigue")
	var courts := {}
	# The court is every family with a name in the country: the great houses, and
	# the houses in their service — a cadet line that left its family over a
	# succession serves it still, and is the likeliest of all to move against it.
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.COMMONER:
			continue
		var realm := CivilWar.realm_of_house(house)
		if realm == &"":
			continue
		if not courts.has(realm):
			courts[realm] = []
		courts[realm].append(house)
	# Grudges by the family that holds them, so a family with none (and no
	# ambition) is passed over without weighing it against every other.
	var held := {}
	var table := Grudges.table(tick)
	for key in table:
		var pair := String(key).split("|")
		var mine: Dictionary = held.get(StringName(pair[0]), {})
		mine[StringName(pair[1])] = float(table[key])
		held[StringName(pair[0])] = mine
	var busy := {}
	for state in GameState.world.intrigues:
		busy[state["polity"]] = true
		busy[state["instigator"]] = true
		busy[state["target"]] = true
	var cooldown := COOLDOWN_YEARS * SimConfig.TICKS_PER_YEAR
	var realms: Array = courts.keys()
	# By name: StringNames compare by where they happen to live in memory.
	realms.sort_custom(func(x, y) -> bool: return String(x) < String(y))
	for realm_id in realms:
		if busy.has(String(realm_id)) or GameState.world.intrigues.size() >= MOST_AT_ONCE:
			continue
		var polity := GameState.get_organization(realm_id)
		if polity == null or polity.ideology == null or CivilWar.is_at_war(realm_id):
			continue
		var houses: Array = courts[realm_id]
		if houses.size() < 2:
			continue
		houses.sort_custom(func(x: Organization, y: Organization) -> bool:
			return String(x.org_id) < String(y.org_id))
		var ruler := GameState.get_current_leader(polity.org_id)
		var ruler_house := GameState.get_organization(ruler.house_org_id) if ruler != null else null
		# What is the same for every pair at this court, read once.
		var seated := {}
		for key in polity.offices:
			seated[StringName(polity.offices[key].get("house", ""))] = true
		var court := {"seated": seated, "new_ruler": _ruler_is_new(polity, ruler, tick)}
		var chosen := {}
		var best := 0.0
		for a: Organization in houses:
			if busy.has(String(a.org_id)) or _cooling(a, tick, cooldown):
				continue
			var mine: Dictionary = held.get(a.org_id, {})
			var actor := _acting_for(a, tick)
			if actor == null or (mine.is_empty() and not actor.has_tag(&"ambitious")):
				continue
			for b: Organization in houses:
				if b.org_id == a.org_id or busy.has(String(b.org_id)) or _cooling(b, tick, cooldown):
					continue
				var grudge := float(mine.get(b.org_id, 0.0))
				var chance := 0.0
				if grudge >= MOTIVE:
					chance = GRUDGE_CHANCE * minf(1.2, grudge)
				elif seated.has(b.org_id) and actor.has_tag(&"ambitious"):
					chance = AMBITION_CHANCE
				else:
					continue
				chance *= _opening(polity, a, b, actor, ruler, ruler_house, tick, court)
				var roll := rng.randf()
				if roll >= chance:
					continue
				# A family that would move weighs its chances first: few try what
				# they can see they would lose. Read only for the few that would.
				chance *= _prospects(polity, a, b, actor)
				# Of the families that would move this year, the one with the most
				# reason to goes first.
				if roll < chance and chance - roll > best:
					best = chance - roll
					chosen = {"a": a, "b": b, "actor": actor, "grudge": grudge}
		if not chosen.is_empty():
			_begin(polity, chosen["a"], chosen["b"], chosen["actor"], tick, rng)
			busy[String(chosen["a"].org_id)] = true
			busy[String(chosen["b"].org_id)] = true


static func _cooling(house: Organization, tick: int, cooldown: int) -> bool:
	return house.last_intrigue_tick >= 0 and tick - house.last_intrigue_tick < cooldown


static func _acting_for(house: Organization, tick: int) -> NotableIndividual:
	var head := GameState.get_current_leader(house.org_id)
	if head != null and head.is_alive() and head.is_adult(tick):
		return head
	return null


static func _holds_seat(polity: Organization, house: Organization) -> bool:
	for key in polity.offices:
		if StringName(polity.offices[key].get("house", "")) == house.org_id:
			return true
	return false


## What makes a court a place where a family would try it: a crown that has
## lost its grip or is new to it, a seat worth taking, a family above one's own,
## ambition, and a body both belong to where they meet every day.
static func _opening(polity: Organization, a: Organization, b: Organization,
		actor: NotableIndividual, ruler: NotableIndividual, ruler_house: Organization,
		tick: int, court: Dictionary = {}) -> float:
	var o := 1.0 + 0.8 * (1.0 - polity.legitimacy)
	var new_ruler: bool = court["new_ruler"] if court.has("new_ruler") \
		else _ruler_is_new(polity, ruler, tick)
	if new_ruler:
		o += 0.6
	var holds: bool = (court["seated"] as Dictionary).has(b.org_id) if court.has("seated") \
		else _holds_seat(polity, b)
	if holds:
		o += 0.5
	var above := HouseRank.precedence(b) - HouseRank.precedence(a)
	if above > 0.0:
		o += 0.25 * minf(2.0, above)
	if actor.has_tag(&"ambitious"):
		o += 0.5
	if actor.has_tag(&"greedy"):
		o += 0.2
	if actor.has_tag(&"cautious"):
		o -= 0.4
	if _share_a_body(a, b):
		o += 0.3
	# What they believe: a family that thinks differently about how the country
	# should be run is easier to move against, one that thinks the same harder.
	var belief_a := Doctrines.sympathy_of(a)
	var belief_b := Doctrines.sympathy_of(b)
	if belief_a != null and belief_b != null:
		o += 0.25 if belief_a != belief_b else -0.2
	# Moving against the crown's own family is rare, and dangerous.
	if ruler_house != null and b.org_id == ruler_house.org_id:
		o *= 0.3
	return maxf(0.1, o)


## How a family reads its own chances: near-even odds or better and it goes
## ahead; plainly hopeless and it mostly does not. Never quite zero — a grudge
## deep enough makes people do foolish things.
static func _prospects(polity: Organization, a: Organization, b: Organization,
		actor: NotableIndividual) -> float:
	var lead := 0.0
	var factors := _factors(polity, a, b, actor, GameState.get_current_leader(b.org_id))
	for key in factors:
		lead += float(factors[key])
	var reckless := 0.25 if actor.has_tag(&"ambitious") else 0.0
	return clampf(0.55 + 0.6 * lead + reckless, 0.08, 1.0)


static func _ruler_is_new(polity: Organization, ruler: NotableIndividual, tick: int) -> bool:
	if ruler == null:
		return false
	var seat := ruler.tenure_in(polity.org_id)
	return seat != null and tick - seat.start_tick < 3 * SimConfig.TICKS_PER_YEAR


## Whether two families meet in the same guild, faction or faith.
static func _share_a_body(a: Organization, b: Organization) -> bool:
	if a.faith_id != &"" and a.faith_id == b.faith_id and Religion.division() > 0.2:
		return true
	var signature := [SimClock.current_tick, GameState.world]
	if signature != _bodies_signature:
		_bodies_signature = signature
		_bodies = {}
		for kind in [Organization.OrgKind.GUILD, Organization.OrgKind.FACTION]:
			for org in GameState.organizations_of_kind(kind):
				var backers: Array = org.support_base.keys()
				if org.patron_house_id != &"":
					backers.append(org.patron_house_id)
				for house_id in backers:
					var held: Dictionary = _bodies.get(house_id, {})
					held[org.org_id] = true
					_bodies[house_id] = held
	var of_a: Dictionary = _bodies.get(a.org_id, {})
	var of_b: Dictionary = _bodies.get(b.org_id, {})
	for id in of_a:
		if of_b.has(id):
			return true
	return false


static var _bodies_signature: Array = []
static var _bodies: Dictionary = {}


# ===================================================================== stages

static func _begin(polity: Organization, a: Organization, b: Organization,
		actor: NotableIndividual, tick: int, rng: RandomNumberGenerator) -> void:
	var target := GameState.get_current_leader(b.org_id)
	var prize := _prize(polity, a, b)
	# If the seat being fought over is held by somebody other than the head, it
	# is that person who is aimed at.
	if prize.begins_with("office:"):
		var holder := GameState.get_person(StringName(
			polity.offices.get(prize.substr(7), {}).get("person", "")))
		if holder != null and holder.is_alive():
			target = holder
	var motive := Grudges.between(a.org_id, b.org_id, tick)
	var id := "intrigue_%d_%s" % [tick, a.org_id]
	var scheme_tick := tick + rng.randi_range(PLOT_SEASONS.x, PLOT_SEASONS.y)
	var state := {
		"id": id,
		"polity": String(polity.org_id),
		"instigator": String(a.org_id),
		"target": String(b.org_id),
		"instigator_person": String(actor.person_id),
		"target_person": String(target.person_id) if target != null else "",
		"prize": prize,
		"stage": 1,
		"start": tick,
		"scheme_tick": scheme_tick,
		"resolve_tick": scheme_tick + rng.randi_range(SCHEME_SEASONS.x, SCHEME_SEASONS.y),
		"motive": int(motive.get("id", 0)),
		"motive_cause": String(motive.get("cause", "")),
		"motive_kind": String(motive.get("kind", "")),
		"motive_why": String(motive.get("why", "")),
		"motive_since": int(motive.get("since", 0)),
		"motive_generations": int(motive.get("generations", 0)),
		"motive_root_kind": String(motive.get("root_kind", motive.get("kind", ""))),
		"motive_root_since": int(motive.get("root_since", motive.get("since", 0))),
		"motive_strength": Grudges.strength_of(motive, tick) if not motive.is_empty() else 0.0,
	}
	var cause := StringName(motive.get("cause", ""))
	var text := "%sの宮廷で、%sが%sの%sを狙って動き出した（%s）。" % [
		polity.formal_name(), actor.full_name, b.formal_name(), prize_label(state),
		motive_phrase(state)]
	HistoryLog.emit_event(HistoryEvent.EventType.INTRIGUE, tick, text,
		{"action": "begin", "id": id, "state": state, "polity": String(polity.org_id),
			"instigator": String(a.org_id), "target": String(b.org_id)},
		a.org_id, actor.person_id, cause if cause != &"" else a.origin_event_id)


## What the instigator is after: the target's seat if it has one, else its
## place in the order of heirs or its office by right, else its standing.
static func _prize(polity: Organization, a: Organization, b: Organization) -> String:
	var best_key := ""
	var best_weight := -1.0
	for key in polity.offices:
		if StringName(polity.offices[key].get("house", "")) == b.org_id \
				and not Offices.WAR_SEATS.has(String(key)):
			var w := Offices.weight_of(String(key), polity)
			if w > best_weight:
				best_weight = w
				best_key = String(key)
	if best_key != "":
		return "office:" + best_key
	var at_b := polity.heir_houses.find(b.org_id)
	var at_a := polity.heir_houses.find(a.org_id)
	if at_b >= 0 and (at_a < 0 or at_a > at_b):
		return "heir"
	for key in polity.hereditary_offices:
		if StringName(polity.hereditary_offices[key]) == b.org_id:
			return "hereditary:" + String(key)
	return "standing"


static func _scheme(state: Dictionary, polity: Organization, a: Organization,
		b: Organization, tick: int) -> void:
	var actor := _actor(state, "instigator")
	var factors := outlook(state)
	var lead := 0.0
	for key in factors:
		lead += float(factors[key])
	var how := "味方を集めている" if lead >= 0.0 else "形勢は思わしくない"
	HistoryLog.emit_event(HistoryEvent.EventType.INTRIGUE, tick,
		"%sは%sを追い落とす工作を進め、%s。" % [actor.full_name, b.formal_name(), how],
		{"action": "scheme", "id": state["id"], "polity": state["polity"],
			"instigator": state["instigator"], "target": state["target"],
			"resolve_tick": int(state["resolve_tick"])},
		a.org_id, actor.person_id, a.origin_event_id)


static func _fade(state: Dictionary, tick: int, why: String) -> void:
	var a := GameState.get_organization(StringName(state["instigator"]))
	var b := GameState.get_organization(StringName(state["target"]))
	HistoryLog.emit_event(HistoryEvent.EventType.INTRIGUE, tick,
		"%s%sと%sの政争は立ち消えになった。" % [why,
			a.formal_name() if a != null else "一方", b.formal_name() if b != null else "他方"],
		{"action": "resolve", "id": state["id"], "outcome": "faded", "polity": state["polity"],
			"instigator": state["instigator"], "target": state["target"],
			"instigator_person": state["instigator_person"],
			"target_person": state["target_person"], "falls": [], "factors": {},
			"prize": state["prize"]},
		StringName(state["instigator"]), StringName(state["instigator_person"]),
		a.origin_event_id if a != null else &"")


# ================================================================= the reckoning

## Each side's case, line by line, weighted for the kind of state this is.
## Every value is the instigator's side minus the target's.
static func _factors(polity: Organization, a: Organization, b: Organization,
		pa: NotableIndividual, pb: NotableIndividual, rng: RandomNumberGenerator = null) -> Dictionary:
	var ruler := GameState.get_current_leader(polity.org_id)
	var ruler_house := GameState.get_organization(ruler.house_org_id) if ruler != null else null
	var axes := polity.ideology
	var w := {"rank": 0.7, "office": 0.5, "favour": 0.7, "allies": 0.8, "seats": 0.6,
		"faith": 0.4, "wealth": 0.6, "character": 1.0, "reputation": 1.0}
	if axes != null:
		match axes.decision_structure:
			PoliticalSystemAxes.DecisionStructure.AUTOCRATIC:
				# Under one ruler, what the ruler thinks of you is most of it.
				w["favour"] = 1.3
				w["allies"] = 0.45
				w["seats"] = 0.2
				w["rank"] = 0.8
			PoliticalSystemAxes.DecisionStructure.ASSEMBLY:
				# In a chamber, it is how many stand with you.
				w["favour"] = 0.35
				w["allies"] = 1.1
				w["seats"] = 1.1
				w["rank"] = 0.4
		match axes.legitimacy_basis:
			PoliticalSystemAxes.LegitimacyBasis.HEREDITARY:
				w["rank"] *= 1.3
			PoliticalSystemAxes.LegitimacyBasis.WEALTH_BASED:
				w["wealth"] *= 2.0
			PoliticalSystemAxes.LegitimacyBasis.THEOCRATIC:
				w["faith"] *= 2.0
			PoliticalSystemAxes.LegitimacyBasis.MERITOCRATIC:
				w["reputation"] *= 1.4
	var sa := _case(polity, a, pa, ruler, ruler_house, true)
	var sb := _case(polity, b, pb, ruler, ruler_house, false)
	var out := {}
	for key in w:
		out[key] = snappedf(float(w[key]) * (float(sa[key]) - float(sb[key])), 0.01)
	out["edge"] = -DEFENDER_EDGE
	if rng != null:
		out["luck"] = snappedf(rng.randf_range(-LUCK, LUCK), 0.01)
	return out


## One side's case, each line on a scale of roughly 0 to 1.5.
static func _case(polity: Organization, house: Organization, person: NotableIndividual,
		ruler: NotableIndividual, ruler_house: Organization, attacking: bool) -> Dictionary:
	var c := {}
	c["rank"] = HouseRank.precedence(house) / 8.0
	var held := 0.0
	for key in polity.offices:
		if StringName(polity.offices[key].get("house", "")) == house.org_id:
			held += Offices.weight_of(String(key), polity)
	c["office"] = minf(1.5, held / 2.0)
	var favour := 0.0
	if ruler_house != null:
		if house.org_id == ruler_house.org_id:
			favour = 1.5
		else:
			favour = HouseRelations.relation(ruler_house.org_id, house.org_id)
			if house.uji_id != &"" and house.uji_id == ruler_house.uji_id:
				favour += 0.3
			if ruler != null and Offices.in_law_houses(ruler).has(house.org_id):
				favour += 0.4
	c["favour"] = favour - disgrace(house)
	var allies := 0.0
	var belief := Doctrines.sympathy_of(house)
	for other in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if other.org_id == house.org_id or other.standing != Organization.Standing.NOBLE:
			continue
		if HouseRelations.relation(other.org_id, house.org_id) > 0.25:
			allies += 1.0
		elif house.uji_id != &"" and other.uji_id == house.uji_id:
			allies += 0.5
		elif belief != null and Doctrines.sympathy_of(other) == belief:
			# Those who think as it does count as friends.
			allies += 0.4
	for servant in Retainers.retainers_of(house.org_id):
		if servant.loyalty > 0.5:
			allies += 0.3
	c["allies"] = minf(1.5, allies / 4.0)
	c["seats"] = Offices._chamber_weight(polity, house)
	c["faith"] = Religion.alignment(house, ruler_house) if ruler_house != null \
		and ruler_house.org_id != house.org_id else (0.5 if ruler_house != null else 0.0)
	c["wealth"] = Offices._wealth_of(house)
	var character := 0.0
	if person != null:
		if person.has_tag(&"ambitious"):
			character += 0.3 if attacking else 0.1
		if person.has_tag(&"cautious"):
			character += -0.2 if attacking else 0.3
		if person.has_tag(&"scholarly"):
			character += 0.15
		if person.has_tag(&"just"):
			character += 0.0 if attacking else 0.15
		if person.has_tag(&"greedy"):
			character -= 0.1
	c["character"] = character
	c["reputation"] = clampf(0.15 * float(house.intrigue_won - house.intrigue_lost), -0.6, 0.6)
	return c


static func _resolve(state: Dictionary, polity: Organization, a: Organization,
		b: Organization, tick: int) -> void:
	var rng := RngService.stream(&"intrigue")
	var pa := _actor(state, "instigator")
	var pb := _actor(state, "target")
	var factors := _factors(polity, a, b, pa, pb, rng)
	var margin := 0.0
	for key in factors:
		margin += float(factors[key])
	var outcome := "stalemate"
	if margin >= WIN_MARGIN:
		outcome = "won"
	elif margin <= BACKFIRE_MARGIN:
		outcome = "backfired"
	var heavy := absf(margin) >= HEAVY_MARGIN

	var winner := a if outcome == "won" else b
	var loser := b if outcome == "won" else a
	var loser_person := pb if outcome == "won" else pa
	var plan := {}
	if outcome != "stalemate":
		plan = _plan_fall(state, polity, winner, loser, loser_person, heavy, tick)

	var ruler := GameState.get_current_leader(polity.org_id)
	var major := false
	if outcome != "stalemate":
		major = (ruler != null and ruler.house_org_id == loser.org_id) \
			or String(plan.get("office", "")) == "regent" \
			or HouseRank.precedence(loser) >= _top_precedence(polity)
	var text := _resolve_text(state, polity, a, b, pa, pb, outcome, plan)
	var e := HistoryLog.emit_event(HistoryEvent.EventType.INTRIGUE, tick, text,
		{"action": "resolve", "id": state["id"], "outcome": outcome, "polity": state["polity"],
			"instigator": state["instigator"], "target": state["target"],
			"instigator_person": String(pa.person_id) if pa != null else "",
			"target_person": String(pb.person_id) if pb != null else "",
			"falls": plan.get("falls", []), "factors": factors, "margin": snappedf(margin, 0.01),
			"heavy": heavy, "major": major, "prize": state["prize"],
			"gained": plan.get("gained", ""),
			"motive_kind": state["motive_kind"], "motive_since": int(state["motive_since"]),
			"motive_generations": int(state["motive_generations"]),
			"motive_root_kind": state["motive_root_kind"],
			"motive_root_since": int(state["motive_root_since"]),
			"motive_cause": state["motive_cause"]},
		a.org_id, pa.person_id if pa != null else &"", a.origin_event_id)
	if outcome != "stalemate":
		_carry_out(plan, polity, winner, loser, e, tick)


static func _top_precedence(polity: Organization) -> float:
	var top := 0.0
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.is_noble() and CivilWar.realm_of_house(house) == polity.org_id:
			top = maxf(top, HouseRank.precedence(house))
	return top


## What the loser loses, worked out before anything is written so the account
## of the quarrel can say it.
static func _plan_fall(state: Dictionary, polity: Organization, winner: Organization,
		loser: Organization, loser_person: NotableIndividual, heavy: bool, tick: int) -> Dictionary:
	var plan := {"falls": [], "heavy": heavy}
	# 左遷: out of the seat — the one fought over, or the loser's weightiest.
	var key := ""
	var prize := String(state["prize"])
	if prize.begins_with("office:") and StringName(polity.offices.get(prize.substr(7), {})
			.get("house", "")) == loser.org_id:
		key = prize.substr(7)
	else:
		var best := -1.0
		for k in polity.offices:
			if StringName(polity.offices[k].get("house", "")) == loser.org_id \
					and not Offices.WAR_SEATS.has(String(k)):
				var w := Offices.weight_of(String(k), polity)
				if w > best:
					best = w
					key = String(k)
	if key != "":
		plan["office"] = key
		plan["falls"].append({"person": String(polity.offices[key].get("person", "")),
			"kind": "displaced", "office": key})
		if HouseRank.precedence(winner) >= Offices.min_rank_of(key, polity) \
				and Offices._sent_by(winner, polity) != null:
			plan["gained"] = key
	# 降格: the family's standing — its office by right, its place among the
	# heirs, its honours — and a mark against its name either way.
	for k in polity.hereditary_offices:
		if StringName(polity.hereditary_offices[k]) == loser.org_id:
			plan["hereditary"] = String(k)
			break
	if polity.heir_houses.has(loser.org_id):
		plan["heir"] = true
	if loser.honour > 0.0:
		plan["honour"] = true
	# The head of the family bears its fall.
	var head := GameState.get_current_leader(loser.org_id)
	if head != null:
		plan["falls"].append({"person": String(head.person_id), "kind": "demoted", "office": ""})
	# A heavy fall takes the head of the family with it, if the family has
	# somebody else to put at its head and the head does not rule a state.
	if heavy and head != null and not Offices._leads_a_state(head) \
			and _has_successor(loser, head, tick):
		plan["falls"].append({"person": String(head.person_id), "kind": "retired", "office": ""})
		plan["retired"] = String(head.person_id)
	return plan


static func _has_successor(house: Organization, head: NotableIndividual, tick: int) -> bool:
	for member in GameState.house_members(house.org_id):
		if member.person_id != head.person_id and member.is_adult(tick) \
				and HouseNaming.is_of_the_blood(member, house) and not member.is_disinherited():
			return true
	return false


## Writes what the loser lost, each through the record that owns it.
static func _carry_out(plan: Dictionary, polity: Organization, winner: Organization,
		loser: Organization, e: HistoryEvent, tick: int) -> void:
	var tag := {"intrigue": String(e.payload["id"])}
	var key := String(plan.get("office", ""))
	if key != "":
		Offices._vacate(polity, key, "intrigue", tick, tag)
		if String(plan.get("gained", "")) == key:
			var person := Offices._sent_by(winner, polity)
			if person != null:
				Offices._appoint(polity, key, person, winner, tick, tag)
	if plan.has("hereditary"):
		var hk := String(plan["hereditary"])
		var payload := {"house": ""}
		payload.merge(tag)
		Offices._emit(polity, "hereditary", hk, &"", tick, payload,
			"%sは%sの家職を失った。" % [loser.formal_name(), Offices.label_of(hk, polity)],
			loser.org_id)
	if bool(plan.get("heir", false)):
		var order: Array[StringName] = polity.heir_houses.duplicate()
		order.erase(loser.org_id)
		var payload := {"houses": Organization._names_to_strings(order),
			"lowered": [String(loser.org_id)], "reordered": true}
		payload.merge(tag)
		Offices._emit(polity, "heirs", "", &"", tick, payload,
			"%sは跡目家から外された。" % loser.formal_name(), loser.org_id)
	if bool(plan.get("honour", false)):
		loser.honour = clampf(loser.honour - Honours.HONOUR_STEP, -Honours.HONOUR_CEILING,
			Honours.HONOUR_CEILING)
		HistoryLog.emit_event(HistoryEvent.EventType.POWER_TRANSFER, tick,
			"%sは叙勲を剥がれた。" % loser.formal_name(),
			{"honour": true, "stripped": true, "granted_by": String(polity.org_id),
				"legitimacy_cost": 0.0, "intrigue": tag["intrigue"]},
			loser.org_id, loser.leader_person_id, e.event_id)
	HistoryLog.emit_event(HistoryEvent.EventType.OFFICE, tick,
		"%sは政争に敗れた汚名を負った。" % loser.formal_name(),
		{"action": "blemish", "kind": "intrigue", "polity": String(polity.org_id),
			"weight": HEAVY_BLEMISH_WEIGHT if bool(plan.get("heavy", false)) else BLEMISH_WEIGHT,
			"intrigue": tag["intrigue"]},
		loser.org_id, loser.leader_person_id, e.event_id)


static func _resolve_text(state: Dictionary, polity: Organization, a: Organization,
		b: Organization, pa: NotableIndividual, pb: NotableIndividual, outcome: String,
		plan: Dictionary) -> String:
	var why := "（%s）" % motive_phrase(state)
	var an := pa.full_name if pa != null else a.formal_name()
	var bn := pb.full_name if pb != null else b.formal_name()
	match outcome:
		"won":
			return "%sの工作が実り、%s%s" % [an, _losses_text(plan, polity, b, a), why]
		"backfired":
			return "%sは%sを陥れようとしたが露見し、かえって%s%s" % [an, bn,
				_losses_text(plan, polity, a, b), why]
	return "%sと%sの政争は決着がつかず、両家は遺恨を深めた。%s" % [a.formal_name(),
		b.formal_name(), why]


## "B某は財務官を解かれ、B家は叙勲を失った。その座はA家に移った。"
static func _losses_text(plan: Dictionary, polity: Organization, loser: Organization,
		winner: Organization) -> String:
	var clauses: Array = []
	var key := String(plan.get("office", ""))
	if key != "":
		var holder := GameState.get_person(StringName(polity.offices.get(key, {}).get("person", "")))
		clauses.append(["%sは%sを解かれ" % [holder.full_name if holder != null else loser.formal_name(),
			Offices.label_of(key, polity)], "た"])
	var cut: Array[String] = []
	if plan.has("hereditary"):
		cut.append("家職")
	if bool(plan.get("heir", false)):
		cut.append("跡目の順位")
	if bool(plan.get("honour", false)):
		cut.append("叙勲")
	if not cut.is_empty():
		clauses.append(["%sは%sを失" % [loser.formal_name(), "と".join(cut)], ["い", "った"]])
	if plan.has("retired"):
		var head := GameState.get_person(StringName(plan["retired"]))
		clauses.append(["当主%sは隠居に追い込まれ" % (head.full_name if head != null else ""), "た"])
	if clauses.is_empty():
		return "%sは家格を落とされた。" % loser.formal_name()
	var parts: Array[String] = []
	for i in clauses.size():
		var c: Array = clauses[i]
		var last := i == clauses.size() - 1
		if c[1] is Array:
			parts.append(String(c[0]) + String(c[1][1] if last else c[1][0]))
		else:
			parts.append(String(c[0]) + (String(c[1]) if last else ""))
	var out := "、".join(parts) + "。"
	if String(plan.get("gained", "")) == key and key != "":
		out += "その座は%sに移った。" % winner.formal_name()
	return out
