class_name ProphecyBook
extends RefCounted

## What a god can foretell, and how to tell whether it came true.
##
## A prophecy is a claim about the world's own future — a family on the throne,
## a guild above all others, a rupture, an extinction — made with a deadline.
## The god cannot bring it about directly: the four dials and the calamities
## are still all there is. What a prophecy adds is a reason to use them: a
## future worth steering toward, and a way to find out how well you understand
## a world that decides everything for itself.
##
## Everything here reads the world and nothing writes it. Offers are built from
## what the world currently is, so they are always about real families and real
## pressures, and they are judged against what the record then says happened.
##
## Prophecies are plain dictionaries so they go into a save as they are.

const HEGEMONY := "hegemony"
const THRONE := "throne"
const EXTINCTION := "extinction"
const NEW_FAITH := "new_faith"
const BRANCH := "branch"
const INCIDENT := "incident"
const REGIME := "regime"
const FALL := "fall"
const GROWTH := "growth"
const DECLINE := "decline"
const LONGEVITY := "longevity"
const ASCENT := "ascent"

const KINDS := [HEGEMONY, THRONE, EXTINCTION, NEW_FAITH, BRANCH, INCIDENT, REGIME,
	FALL, GROWTH, DECLINE, LONGEVITY, ASCENT]

## The kinds whose outcome the dials reach most directly. Every set of offers
## carries at least one, so there is always a prophecy the god can work toward
## rather than only wait on.
const STEERABLE := [HEGEMONY, INCIDENT, GROWTH, DECLINE, NEW_FAITH]

enum Verdict { PENDING, FULFILLED, FAILED }

const Y := SimConfig.TICKS_PER_YEAR


# ------------------------------------------------------------------- offers

## Up to `count` prophecies the world could plausibly bear out, of different
## kinds and none repeating one already spoken.
static func offers(rng: RandomNumberGenerator, tick: int, spoken: Array,
		count: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for kind in KINDS:
		var candidate := _candidate(kind, rng, tick)
		if candidate.is_empty() or _already_spoken(candidate, spoken):
			continue
		pool.append(candidate)

	# Shuffled by the oracle's own generator — never the world's, so asking for a
	# prophecy cannot change what history does next.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Dictionary = pool[i]
		pool[i] = pool[j]
		pool[j] = swap

	var out: Array[Dictionary] = []
	for candidate in pool:
		if STEERABLE.has(candidate["kind"]):
			out.append(candidate)
			break
	for candidate in pool:
		if out.size() >= count:
			break
		if not out.has(candidate):
			out.append(candidate)
	return out


static func _already_spoken(candidate: Dictionary, spoken: Array) -> bool:
	for p in spoken:
		if p["kind"] == candidate["kind"] and p["target"] == candidate["target"]:
			return true
	return false


static func _candidate(kind: String, rng: RandomNumberGenerator, tick: int) -> Dictionary:
	match kind:
		HEGEMONY:
			return _offer_hegemony(rng, tick)
		THRONE:
			return _offer_throne(rng, tick)
		EXTINCTION:
			return _offer_extinction(rng, tick)
		NEW_FAITH:
			return _offer_new_faith(tick)
		BRANCH:
			return _offer_branch(rng, tick)
		INCIDENT:
			return _offer_incident(rng, tick)
		REGIME:
			return _make(REGIME, "", "", 0.0, tick, 50, 55,
				"%d年のうちに、統治のかたちが覆る" % 50,
				"飢えと不満、それに力をつけすぎた者が体制を揺るがす")
		FALL:
			return _make(FALL, "", "", 0.0, tick, 80, 95,
				"%d年のうちに、この国が倒れ、新たな国が興る" % 80,
				"体制が覆るだけでは足りない。国そのものが血筋を捨てるほどの変革を")
		GROWTH, DECLINE:
			return _offer_population(kind, tick)
		LONGEVITY:
			return _offer_longevity(rng, tick)
		ASCENT:
			return _offer_ascent(rng, tick)
	return {}


static func _make(kind: String, target: String, target_name: String, param: float,
		tick: int, years: int, reward: int, text: String, hint: String) -> Dictionary:
	return {
		"kind": kind,
		"target": target,
		"target_name": target_name,
		"param": param,
		"text": text,
		"hint": hint,
		"declared": tick,
		"deadline": tick + years * Y,
		"years": years,
		"reward": reward,
		"state": "offer",
		"met": false,
		"resolved": -1,
		"id": 0,
	}


static func _offer_hegemony(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var ranked := PowerCalculator.ranked(-1)
	if ranked.size() < 3:
		return {}
	var place := rng.randi_range(1, mini(5, ranked.size() - 1))
	var org: Organization = ranked[place]
	var gap := ranked[0].power_score - org.power_score
	var reward := clampi(int(30 + place * 9 + gap * 0.5), 30, 120)
	return _make(HEGEMONY, String(org.org_id), org.display_name, 0.0, tick, 30, reward,
		"%d年のうちに、%sが世で最も力ある組織となる" % [30, org.display_name],
		dial_hint(org))


static func _offer_throne(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return {}
	var ruler := GameState.get_current_leader(realm.org_id)
	var ruling_house := ruler.house_org_id if ruler != null else &""
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE and house.org_id != ruling_house:
			houses.append(house)
	if houses.is_empty():
		return {}
	houses.sort_custom(func(a, b): return HouseRank.precedence(a) > HouseRank.precedence(b))
	var place := rng.randi_range(0, mini(3, houses.size() - 1))
	var house: Organization = houses[place]
	var seat := realm.leadership_title if not realm.leadership_title.is_empty() else "国の長"
	return _make(THRONE, String(house.org_id), house.display_name, 0.0, tick, 60,
		clampi(45 + place * 15, 45, 110),
		"%d年のうちに、%sの者が%sの座に就く" % [60, house.display_name, seat],
		"国の長を決めるのは人の側。家が力と家格を増し、いまの長の家が揺らげば道が開く")


static func _offer_extinction(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var royal := HouseRank.royal_house_id()
	var frail: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE and house.org_id != royal \
				and house.member_count <= 6:
			frail.append(house)
	if frail.is_empty():
		return {}
	frail.sort_custom(func(a, b): return a.member_count < b.member_count)
	var house: Organization = frail[rng.randi_range(0, mini(2, frail.size() - 1))]
	return _make(EXTINCTION, String(house.org_id), house.display_name, 0.0, tick, 50,
		clampi(30 + 60 / maxi(1, house.member_count), 35, 70),
		"%d年のうちに、%sの血が絶える" % [50, house.display_name],
		"疫病と飢えが家を細らせる。子が生まれる前に")


static func _offer_new_faith(tick: int) -> Dictionary:
	if Religion.root() == null:
		return {}
	return _make(NEW_FAITH, "", "", 0.0, tick, 50, 45,
		"%d年のうちに、新たな信仰が生まれる" % 50,
		"凶作、続く災厄、跋扈する魔物、積み上がる鉱石——世が揺れると新たな啓示が下る")


static func _offer_branch(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var bodies: Array[Organization] = []
	for org in GameState.active_organizations():
		if org.kind == Organization.OrgKind.POLITICAL_SYSTEM:
			continue
		if org.kind == Organization.OrgKind.HOUSE and org.standing != Organization.Standing.NOBLE:
			continue
		bodies.append(org)
	if bodies.is_empty():
		return {}
	bodies.sort_custom(func(a, b): return a.power_score > b.power_score)
	var org: Organization = bodies[rng.randi_range(0, mini(5, bodies.size() - 1))]
	var house := org.kind == Organization.OrgKind.HOUSE
	return _make(BRANCH, String(org.org_id), org.display_name, 0.0, tick, 40,
		45 if house else 40,
		"%d年のうちに、%sが割れて新たな%sが生まれる" % [40, org.display_name,
			"分家" if house else "一派"],
		"家督争いや婚姻のもつれで家は割れる" if house
			else "境遇が急に変わると、組織の中の考えが割れる。%s" % dial_hint(org))


static func _offer_incident(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var possible: Array[Dictionary] = []
	var horizon := tick + 40 * Y - 8 * Y
	var last_any := Incidents._last_any()
	for entry in Incidents.pressures():
		var kind: StringName = entry["kind"]
		var last_kind := Incidents._last_of(kind)
		var earliest := tick
		if last_any >= 0:
			earliest = maxi(earliest, last_any + Incidents.GLOBAL_COOLDOWN)
		if last_kind >= 0:
			earliest = maxi(earliest, last_kind + Incidents.KIND_COOLDOWN)
		if earliest > horizon:
			continue
		possible.append(entry)
	if possible.is_empty():
		return {}
	possible.sort_custom(func(a, b): return float(a["pressure"]) > float(b["pressure"]))
	var entry: Dictionary = possible[rng.randi_range(0, mini(1, possible.size() - 1))]
	var pressure := float(entry["pressure"])
	var missing := String(entry.get("missing", ""))
	return _make(INCIDENT, String(entry["kind"]), String(entry["label"]), 0.0, tick, 40,
		clampi(int(55 + (1.0 - pressure) * 65), 55, 120),
		"%d年のうちに、%sが起きる" % [40, entry["label"]],
		"いま足りないもの：%s" % missing if not missing.is_empty()
			else "条件はほぼ揃っている。あとは時を待つだけ")


static func _offer_population(kind: String, tick: int) -> Dictionary:
	var now := GameState.world.global_population
	if now <= 0.0:
		return {}
	if kind == GROWTH:
		var goal := ceilf(now * 1.25 / 100.0) * 100.0
		return _make(GROWTH, "", "", goal, tick, 40, 35,
			"%d年のうちに、世の人口が%sに達する" % [40, population_words(goal)],
			"収穫を上げ、災厄を控えれば人は増える")
	var floor_value := floorf(now * 0.8 / 100.0) * 100.0
	return _make(DECLINE, "", "", floor_value, tick, 30, 40,
		"%d年のうちに、世の人口が%sまで減る" % [30, population_words(floor_value)],
		"疫病、飢饉、魔物——どれも人を減らす")


static func _offer_longevity(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var people: Array[NotableIndividual] = []
	var realm := HouseRank.dominant_realm()
	if realm != null:
		var ruler := GameState.get_current_leader(realm.org_id)
		if ruler != null:
			people.append(ruler)
	for org in PowerCalculator.ranked(Organization.OrgKind.HOUSE).slice(0, 3):
		var head := GameState.get_current_leader(org.org_id)
		if head != null and not people.has(head):
			people.append(head)
	var eligible: Array[NotableIndividual] = []
	for p in people:
		if p.is_alive() and p.age_years(tick) >= 45 and p.age_years(tick) <= 80:
			eligible.append(p)
	if eligible.is_empty():
		return {}
	var person: NotableIndividual = eligible[rng.randi_range(0, eligible.size() - 1)]
	var age := person.age_years(tick)
	var goal := age + 12
	var years := goal - age + 1
	return _make(LONGEVITY, String(person.person_id), person.full_name, float(goal), tick,
		years, clampi(30 + maxi(0, goal - 60) * 3, 30, 90),
		"%sは%d歳まで生きる" % [person.full_name, goal],
		"疫病と飢えを遠ざけておく。いま%d歳" % age)


static func _offer_ascent(rng: RandomNumberGenerator, tick: int) -> Dictionary:
	var top := HouseRank.TIER_NAMES.size() - 1
	var houses: Array[Organization] = []
	for house in GameState.organizations_of_kind(Organization.OrgKind.HOUSE):
		if house.standing == Organization.Standing.NOBLE and house.rank_tier < top \
				and not HouseRank.is_royal(house):
			houses.append(house)
	if houses.is_empty():
		return {}
	var house: Organization = houses[rng.randi_range(0, houses.size() - 1)]
	var goal := house.rank_tier + 1
	return _make(ASCENT, String(house.org_id), house.display_name, float(goal), tick, 50,
		40 + goal * 8,
		"%d年のうちに、%sが%sに叙される" % [50, house.display_name, HouseRank.TIER_NAMES[goal]],
		"所領・力・官職、そして王家との近さが家格を上げる")


# ------------------------------------------------------------------ judging

## Marks a prophecy whose event has now happened. Events are the only way to
## see some outcomes — a faith born and gone between two looks is still born.
static func notice(p: Dictionary, e: HistoryEvent) -> void:
	if p["met"] or e.tick < int(p["declared"]):
		return
	match String(p["kind"]):
		NEW_FAITH:
			if e.event_type == HistoryEvent.EventType.SCHISM \
					and String(e.payload.get("schism_kind", "")) == "revelation":
				p["met"] = true
		BRANCH:
			if e.event_type == HistoryEvent.EventType.SCHISM:
				var born: Dictionary = e.payload.get("organization", {})
				if String(born.get("parent_org_id", "")) == String(p["target"]):
					p["met"] = true
		INCIDENT:
			if e.event_type == HistoryEvent.EventType.INCIDENT \
					and String(e.payload.get("incident_kind", "")) == String(p["target"]):
				p["met"] = true
		REGIME:
			if e.event_type == HistoryEvent.EventType.POWER_TRANSFER \
					and bool(e.payload.get("regime_change", false)):
				p["met"] = true
		FALL:
			if e.event_type == HistoryEvent.EventType.SCHISM \
					and String(e.payload.get("schism_kind", "")) == "refounding":
				p["met"] = true


static func judge(p: Dictionary, tick: int) -> int:
	var target := StringName(p["target"])
	match String(p["kind"]):
		HEGEMONY:
			var org := GameState.get_organization(target)
			if org == null or not org.is_active():
				return Verdict.FAILED
			var ranked := PowerCalculator.ranked(-1)
			if not ranked.is_empty() and ranked[0].org_id == target:
				return Verdict.FULFILLED
		THRONE:
			var house := GameState.get_organization(target)
			if house == null or not house.is_active():
				return Verdict.FAILED
			if _ruling_house() == target:
				return Verdict.FULFILLED
		EXTINCTION:
			var house := GameState.get_organization(target)
			if house == null or not house.is_active():
				return Verdict.FULFILLED
		GROWTH:
			if GameState.world.global_population >= float(p["param"]):
				return Verdict.FULFILLED
		DECLINE:
			if GameState.world.global_population <= float(p["param"]):
				return Verdict.FULFILLED
		LONGEVITY:
			var person := GameState.get_person(target)
			if person == null:
				return Verdict.FAILED
			if person.is_alive() and person.age_years(tick) >= int(p["param"]):
				return Verdict.FULFILLED
			if not person.is_alive():
				return Verdict.FAILED
		ASCENT:
			var house := GameState.get_organization(target)
			if house == null or not house.is_active():
				return Verdict.FAILED
			if house.rank_tier >= int(p["param"]):
				return Verdict.FULFILLED
		BRANCH:
			if p["met"]:
				return Verdict.FULFILLED
			var org := GameState.get_organization(target)
			if org == null or not org.is_active():
				return Verdict.FAILED
		_:
			if p["met"]:
				return Verdict.FULFILLED
	if tick >= int(p["deadline"]):
		return Verdict.FAILED
	return Verdict.PENDING


static func _ruling_house() -> StringName:
	var realm := HouseRank.dominant_realm()
	if realm == null:
		return &""
	var ruler := GameState.get_current_leader(realm.org_id)
	return ruler.house_org_id if ruler != null else &""


# ---------------------------------------------------------------- reading

## Where things stand, in a line: how close the prophecy is, as the world now is.
static func progress(p: Dictionary, tick: int) -> String:
	var target := StringName(p["target"])
	match String(p["kind"]):
		HEGEMONY:
			var ranked := PowerCalculator.ranked(-1)
			for i in ranked.size():
				if ranked[i].org_id == target:
					if i == 0:
						return "いま首位"
					return "いま第%d位　首位の%sとの差 %d" % [i + 1, ranked[0].display_name,
						int(ranked[0].power_score - ranked[i].power_score)]
			return "もう世にない"
		THRONE:
			var realm := HouseRank.dominant_realm()
			var ruler := GameState.get_current_leader(realm.org_id) if realm != null else null
			var house := GameState.get_organization(_ruling_house())
			return "いまの%sは%s（%s）" % [realm.leadership_title if realm != null else "長",
				ruler.full_name if ruler != null else "空位",
				house.display_name if house != null else "家なし"]
		EXTINCTION:
			var house := GameState.get_organization(target)
			return "存命の者 %d人" % (house.member_count if house != null else 0)
		GROWTH, DECLINE:
			return "いま %s／目標 %s" % [population_words(GameState.world.global_population),
				population_words(float(p["param"]))]
		LONGEVITY:
			var person := GameState.get_person(target)
			if person == null or not person.is_alive():
				return "すでに亡い"
			return "いま%d歳" % person.age_years(tick)
		ASCENT:
			var house := GameState.get_organization(target)
			return "いまは%s" % HouseRank.title_of_house(house) if house != null else "もう世にない"
		INCIDENT:
			for entry in Incidents.pressures():
				if String(entry["kind"]) == String(p["target"]):
					return "機運 %d%%" % int(float(entry["pressure"]) * 100.0)
		BRANCH:
			var org := GameState.get_organization(target)
			return "勢力 %d" % int(org.power_score) if org != null else "もう世にない"
		REGIME, FALL:
			var realm := HouseRank.dominant_realm()
			if realm == null:
				return ""
			var challenge := RegimeShift.standing_challenge(realm)
			if challenge.is_empty():
				return "正統性 %d%%　体制に挑む者なし" % int(realm.legitimacy * 100.0)
			return "正統性 %d%%　%sが迫る（掌握 %d%%）" % [int(realm.legitimacy * 100.0),
				challenge["org"].display_name, int(float(challenge.get("hold", 0.0)) * 100.0)]
		NEW_FAITH:
			return "いま世にある信仰 %d" % GameState.organizations_of_kind(
				Organization.OrgKind.RELIGION).size()
	return ""


static func years_left(p: Dictionary, tick: int) -> int:
	return maxi(0, int(ceil(float(int(p["deadline"]) - tick) / float(Y))))


## Which dials feed an organization's influence, in words — read from the same
## profile the simulation scores it with.
static func dial_hint(org: Organization) -> String:
	var profile := ContentRegistry.get_power_profile(org.archetype_id)
	if profile == null:
		return "この組織の力は人の営みから来る。神の手は届きにくい"
	var parts: Array[String] = []
	for driver in profile.drivers:
		var dial := _dial_name(driver.world_var_path)
		if dial.is_empty() or driver.weight <= 0.0:
			continue
		parts.append("%sを%s" % [dial, "下げる" if driver.invert else "上げる"])
	if parts.is_empty():
		return "この組織の力は人の営みから来る。神の手は届きにくい"
	return "%sと力を増す" % "・".join(parts)


static func _dial_name(world_var: StringName) -> String:
	match world_var:
		&"global_ore":
			return "鉱石"
		&"global_wood":
			return "木材"
		&"global_harvest_modifier":
			return "収穫"
		&"global_monster_threat_level":
			return "魔物"
		&"recent_disaster_pressure":
			return "災厄"
	return ""


static func population_words(value: float) -> String:
	if value >= 10000.0:
		return "%.1f万" % (value / 10000.0)
	return "%d" % int(value)
